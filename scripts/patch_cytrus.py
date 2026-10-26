#!/usr/bin/env python3
"""Small, checked safety/API changes against the pinned upstream Cytrus tree."""
from pathlib import Path
import argparse
import hashlib
import json

REPLACEMENTS = {
    "System/core/frontend/image_interface.cpp": [
        ("#include <dds_ktx.h>", "#include <dds-ktx.h>"),
    ],
    "System/include/core/frontend/image_interface.h": [
        ("#include <dds_ktx.h>", "#include <dds-ktx.h>"),
    ],
    "System/common/dynamic_library/dynamic_library.cpp": [
        ('#elif defined(__APPLE__)\n    auto prefix = name.starts_with("lib") ? "" : "lib";', '#elif defined(__APPLE__)\n    if (name == "avcodec" || name == "avdevice" || name == "avfilter" || name == "avformat" || name == "avutil" || name == "swresample" || name == "swscale") {\n        return fmt::format("@rpath/lib{}.framework/lib{}", name, name);\n    }\n    auto prefix = name.starts_with("lib") ? "" : "lib";'),
    ],
    "Cytrus.swift": [
        ("public func initializeLogging() {\n        cytrus.initialize_logging()", 
         "public func initializeLogging(userDirectory: URL) {\n        cytrus.initialize_logging(std.string(userDirectory.path + \"/\"))"),
        ("public func insertDisc(at url: URL) {\n        cytrus.insert_disc(std.string(url.path))", 
         "public func insertDisc(at url: URL) -> Bool {\n        return cytrus.insert_disc(std.string(url.path))"),
        ("try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)",
         "try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)"),
    ],
    "System/include/cytrus/bridge.h": [
        ("void initialize_logging(void);", "void initialize_logging(std::string);"),
        ("void insert_disc(std::string);", "bool insert_disc(std::string);"),
    ],
    "System/bridge.cpp": [
        ("void cytrus::initialize_logging(void) {", "void cytrus::initialize_logging(std::string user_directory) {\n    FileUtil::SetUserPath(user_directory);"),
        ("void cytrus::insert_disc(std::string path) {", "bool cytrus::insert_disc(std::string path) {"),
        ("cntnr.window.release();", "cntnr.window.reset();"),
        ("cntnr.secondary_window.release();", "cntnr.secondary_window.reset();"),
        ("cytrus::callback(cytrus::context, color.x, color.y, color.z);", "if (cytrus::callback) cytrus::callback(cytrus::context, color.x, color.y, color.z);"),
        ("void(system.Load(*cntnr.window, path, cntnr.secondary_window.get()));", 
         "const auto result = system.Load(*cntnr.window, path, cntnr.secondary_window.get());\n    if (result != Core::System::ResultStatus::Success) {\n        system.Shutdown();\n        InputManager::Shutdown();\n        Network::Shutdown();\n        cntnr.window.reset();\n        cntnr.secondary_window.reset();\n        return false;\n    }\n    return true;"),
        ("if (cntnr.paused.load())\n                continue;", 
         "if (cntnr.paused.load()) {\n                std::this_thread::sleep_for(std::chrono::milliseconds(5));\n                continue;\n            }"),
        ("void(system.RunLoop());", "if (system.RunLoop() != Core::System::ResultStatus::Success) {\n                cntnr.running.store(false);\n                break;\n            }"),
        ("system.RequestShutdown();\n    system.Shutdown();", 
         "system.RequestShutdown();\n    if (cntnr.thread.joinable()) cntnr.thread.join();\n    system.Shutdown();"),
        ("cntnr.secondary_width = width;", 
         "cntnr.secondary_width = width;\n        if (cntnr.secondary_window) cntnr.secondary_window->SizeChanged(height, width);"),
        ("cntnr.width = width;", 
         "cntnr.width = width;\n        if (cntnr.window) cntnr.window->SizeChanged(height, width);"),
    ],
    "System/emu_window_vk.cpp": [
        ("window_width = m_size_w;\n}", "window_width = m_size_w;\n    OnFramebufferSizeChanged();\n}"),
    ],
}

def patch(root: Path):
    marker = root / ".tandem-patched-v1"
    version = hashlib.sha256(json.dumps(REPLACEMENTS, sort_keys=True).encode()).hexdigest()
    if marker.is_file() and marker.read_text().strip() == version:
        return
    # Validate every expected string before changing any source file.
    updated = {}
    for relative, replacements in REPLACEMENTS.items():
        source = (root / relative).read_text()
        for old, new in replacements:
            if new in source:
                # Preserve already patched spans while upgrading older source
                # checkouts with newly added fixes.
                pieces = source.split(new)
                source = new.join(piece.replace(old, new) for piece in pieces)
                continue
            if old not in source:
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
