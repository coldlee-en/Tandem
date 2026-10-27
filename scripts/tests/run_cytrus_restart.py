#!/usr/bin/env python3
"""Exercise the patched bridge start/stop methods and core shutdown signal reset."""
import argparse
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('source', type=pathlib.Path)
args = parser.parse_args()
bridge = (args.source / 'System/bridge.cpp').read_text()
core = (args.source / 'System/core/core.cpp').read_text()
start = bridge[bridge.index('void cytrus::start(void)'):bridge.index('void cytrus::set_screens(')]
reset = core.split('void System::Shutdown(bool is_deserializing) {', 1)[1].split('    // Shutdown emulation session', 1)[0]
assert 'current_signal = Signal::None;' in reset
code = '''#include <atomic>\n#include <chrono>\n#include <mutex>\n#include <thread>\n#include <cassert>\nnamespace Core {\nstruct System {\n enum class ResultStatus { Success, ShutdownRequested };\n enum class Signal { None, Shutdown };\n std::mutex signal_mutex; Signal current_signal = Signal::None; unsigned signal_param = 0;\n static System& GetInstance() { static System s; return s; }\n void RequestShutdown() { std::scoped_lock lock{signal_mutex}; current_signal = Signal::Shutdown; }\n ResultStatus RunLoop() { std::scoped_lock lock{signal_mutex}; if (current_signal == Signal::Shutdown) { current_signal = Signal::None; return ResultStatus::ShutdownRequested; } std::this_thread::yield(); return ResultStatus::Success; }\n void Shutdown() { RESET }\n}; }\nstruct { std::jthread thread; std::atomic<bool> paused{false}, running{false}; } cntnr;\nnamespace InputManager { void Shutdown() {} }\nnamespace Network { void Shutdown() {} }\nnamespace cytrus { void start(); void stop(); }\nSTART\nint main() {\n auto& system = Core::System::GetInstance();\n for (int i = 0; i < 1000; ++i) {\n  cntnr.running = true; cytrus::start(); cytrus::stop();\n  assert(system.RunLoop() == Core::System::ResultStatus::Success);\n }\n system.RequestShutdown(); system.Shutdown();\n assert(system.RunLoop() == Core::System::ResultStatus::Success);\n}\n'''.replace('RESET', reset).replace('START', start)
with tempfile.TemporaryDirectory() as tmp:
    path = pathlib.Path(tmp)
    (path / 'test.cpp').write_text(code)
    subprocess.run(['c++', '-std=c++20', '-pthread', str(path / 'test.cpp'), '-o', str(path / 'test')], check=True, timeout=60)
    subprocess.run([str(path / 'test')], check=True, timeout=30)
print('Cytrus restart lifecycle: 1000 stop/restart cycles and pending-signal cleanup passed')
