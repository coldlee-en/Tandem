#!/usr/bin/env python3
"""Checked changes to the pinned NativeAOT core, with no binary rewriting."""
from pathlib import Path
import argparse
import hashlib
import json

REPLACEMENTS = {
    "src/Ryujinx.HLE/FileSystem/VirtualFileSystem.cs": [
        ("_isInitialized = true;\n\n            return new VirtualFileSystem();", "var instance = new VirtualFileSystem();\n            _isInitialized = true;\n            return instance;"),
    ],
    "src/Ryujinx.Headless.SDL2/Program.cs": [
        ("private static WindowBase _window;", "private static volatile WindowBase _window;"),
        ('''        [UnmanagedCallersOnly(EntryPoint = "stop_emulation")]
''', '''        // Snapshot the window before queuing: a delayed stop must never
        // affect the window belonging to a subsequent native invocation.
        [UnmanagedCallersOnly(EntryPoint = "tandem_request_stop")]
        public static void RequestStopTandem()
        {
            WindowBase window = _window;
            if (window == null) return;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                try { window.Exit(); }
                catch (Exception error) { Console.Error.WriteLine(error); }
            });
        }

        [UnmanagedCallersOnly(EntryPoint = "stop_emulation")]
'''),
        ("public static unsafe void Initialize()\n        {", "public static unsafe void Initialize() { InitializeCore(); }\n\n        [UnmanagedCallersOnly(EntryPoint = \"tandem_initialize\")]\n        public static byte InitializeTandem()\n        {\n            try { InitializeCore(); return 1; }\n            catch (Exception error) { Console.Error.WriteLine(error); return 0; }\n        }\n\n        [UnmanagedCallersOnly(EntryPoint = \"tandem_initialize_jit\")]\n        public static byte InitializeJitTandem()\n        {\n            try { return Cpu.LightningJit.DualMappedTranslator.InitializeDualMapped() ? (byte)1 : (byte)0; }\n            catch (Exception error) { Console.Error.WriteLine(error); return 0; }\n        }\n\n        private static void InitializeCore()\n        {"),
        ("AppDataManager.Initialize(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));", "AppDataManager.Initialize(Environment.GetEnvironmentVariable(\"TANDEM_SWITCH_ROOT\") ?? Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));"),
        ("if (_libHacHorizonManager == null)", "_virtualFileSystem.ReloadKeySet();\n\n            if (_libHacHorizonManager == null)"),
        ("Task.Run(() => _contentManager.InstallFirmware(filePath));", "_contentManager.InstallFirmware(filePath);"),
        ("_inputManager = new InputManager(new SDL2KeyboardDriver(), new NativeGamepadDriver());", "_inputManager?.Dispose();\n            _inputManager = new InputManager(new SDL2KeyboardDriver(), new NativeGamepadDriver());"),
    ],
    "src/Ryujinx.Graphics.Nvdec.FFmpeg/Native/FFmpegApi.cs": [
        ('string libName = $"lib{libraryName}.{version}.dylib";', 'string libName = $"lib{libraryName}.dylib";'),
    ],
    "src/Ryujinx.Headless.SDL2/iOSTouchDriver.cs": [
        ("using System.Collections.Generic;", "using System.Collections.Generic;\nusing System.Collections.Concurrent;"),
        ("private static Dictionary<int, Vector2> _activeTouches = new();", "private static ConcurrentDictionary<int, Vector2> _activeTouches = new();"),
        ("_activeTouches.Remove(index);", "_activeTouches.TryRemove(index, out _);"),
    ],
    "src/Ryujinx.Headless.SDL2/WindowBase.cs": [
        ("public bool _isActive;\n        private bool _isStopped;",
         "public volatile bool _isActive;\n        private volatile bool _isStopped;\n        private readonly object _lifecycleLock = new();"),
        ('''        public void Render()
        {
            InitializeWindowRenderer();''', '''        private int _gpuCompletionSignalled;

        private void SignalGpuDone()
        {
            // The threaded renderer can outlive Execute(). Signal from its
            // callback and from early renderer failures, without touching an
            // event that Execute() has already consumed and disposed.
            if (Interlocked.Exchange(ref _gpuCompletionSignalled, 1) == 0)
            {
                _gpuDoneEvent.Set();
            }
        }

        public void Render()
        {
            try
            {
            InitializeWindowRenderer();'''),
        ('''            Device.Gpu.Renderer.RunLoop(() =>
            {
                Device.Gpu.SetGpuThread();''', '''            Device.Gpu.Renderer.RunLoop(() =>
            {
                try
                {
                Device.Gpu.SetGpuThread();'''),
        ('''                    if (_isStopped)
                    {
                        return;
                    }

                    _pauseEvent.WaitOne();''', '''                    if (_isStopped)
                    {
                        break;
                    }

                    _pauseEvent.WaitOne();
                    if (_isStopped || !_isActive) break;'''),
        ('''                _gpuDoneEvent.Set();
            });

            FinalizeWindowRenderer();
        }''', '''                }
                finally
                {
                    SignalGpuDone();
                }
            });

            FinalizeWindowRenderer();
            }
            finally
            {
                SignalGpuDone();
            }
        }'''),
        ('''        public void Exit()
        {
            TouchScreenManager?.Dispose();
            NpadManager?.Dispose();

            if (_isStopped)
            {
                return;
            }

            _gpuCancellationTokenSource.Cancel();

            _isStopped = true;
            _isActive = false;

            _exitEvent.WaitOne();
            _exitEvent.Dispose();
        }''', '''        public void Exit()
        {
            lock (_lifecycleLock)
            {
                if (_isStopped) return;
                _isStopped = true;
                _isActive = false;
                // Wake a paused GPU before waiting for native completion.
                _pauseEvent.Set();
                _gpuCancellationTokenSource.Cancel();
            }
            // Input managers are disposed only by Dispose(), after Execute()
            // and the emulation context have finished using them.
        }'''),
        ('''            _chrono.Restart();
            _isActive = true;

            InitializeWindow();''', '''            _chrono.Restart();
            lock (_lifecycleLock)
            {
                // A stop between publishing _window and entering Execute()
                // must remain latched; it cannot be undone by startup.
                if (_isStopped) return;
                _isActive = true;
            }

            InitializeWindow();'''),
        ('''                _isActive = false;
                TouchScreenManager?.Dispose();
                NpadManager.Dispose();''', '''                Exit();
                TouchScreenManager?.Dispose();
                NpadManager.Dispose();
                _exitEvent.Dispose();
                _pauseEvent.Dispose();'''),
    ],
}

def patch(root: Path):
    marker = root / ".tandem-patched-v1"
    version = hashlib.sha256(json.dumps(REPLACEMENTS, sort_keys=True).encode()).hexdigest()
    if marker.is_file() and marker.read_text().strip() == version:
        return
    updated = {}
    for relative, replacements in REPLACEMENTS.items():
        source = (root / relative).read_text(encoding="utf-8-sig")
        for old, new in replacements:
            if new in source:
                pieces = source.split(new)
                source = new.join(piece.replace(old, new) for piece in pieces)
                continue
            if source.count(old) != 1:
                raise RuntimeError(f"Pinned source mismatch: {relative}: {old[:70]}")
            source = source.replace(old, new)
        updated[relative] = source
    for relative, source in updated.items():
        (root / relative).write_text(source)
    marker.write_text(version + "\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    patch(parser.parse_args().source)
