#!/usr/bin/env python3
"""Small, checked safety/API changes against the pinned upstream Cytrus tree."""
from pathlib import Path
import argparse
import hashlib
import json

REPLACEMENTS = {
    # libc++ no longer guarantees type_traits through unrelated standard headers.
    # Each of these headers directly names traits from that standard header.
    "System/include/common/hash.h": [
        ("#include <string>", "#include <string>\n#include <string_view>\n#include <type_traits>\n#include <utility>"),
    ],
    "System/include/common/common_funcs.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/common/threadsafe_queue.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/core/file_sys/archive_backend.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/core/hle/kernel/hle_ipc.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/core/hle/mii.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/core/hle/service/fs/archive.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/core/hle/service/ldr_ro/cro_helper.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/core/hle/service/nfc/nfc_types.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/pica/output_vertex.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/pica/regs_lcd.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/rasterizer_cache/framebuffer_base.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/rasterizer_cache/rasterizer_cache_base.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/rasterizer_cache/sampler_params.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/renderer_vulkan/vk_graphics_pipeline.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/renderer_vulkan/vk_shader_disk_cache.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    "System/include/video_core/shader/generator/pica_fs_config.h": [
        ("#pragma once", "#pragma once\n\n#include <type_traits>"),
    ],
    # Headers live in System/include; qualified paths avoid Xcode's flattened
    # header map and its collisions between unrelated internal basenames.
    "System/video_core/right_eye_disabler.cpp": [
        ('#include "right_eye_disabler.h"', '#include "video_core/right_eye_disabler.h"'),
    ],
    "System/network/socket_manager.cpp": [
        ('#include "socket_manager.h"', '#include "network/socket_manager.h"'),
    ],
    "System/network/announce_multiplayer_session.cpp": [
        ('#include "announce_multiplayer_session.h"', '#include "network/announce_multiplayer_session.h"'),
    ],
    "System/common/web_util.cpp": [
        ('#include "web_util.h"', '#include "common/web_util.h"'),
    ],
    "System/common/math_util.cpp": [
        ('#include "math_util.h"', '#include "common/math_util.h"'),
    ],
    "System/common/cityhash.cpp": [
        ('#include "cityhash.h"', '#include "common/cityhash.h"'),
    ],
    "System/video_core/renderer_vulkan/vk_present_window.cpp": [
        ('#include "vk_platform.h"', '#include "video_core/renderer_vulkan/vk_platform.h"'),
    ],
    "System/video_core/renderer_vulkan/vk_blit_helper.cpp": [
        ('#include "vk_blit_helper.h"', '#include "video_core/renderer_vulkan/vk_blit_helper.h"'),
    ],
    "System/network/artic_base/artic_base_client.cpp": [
        ('#include "artic_base_client.h"', '#include "network/artic_base/artic_base_client.h"'),
    ],
    "System/input_common/sdl/sdl3_joystick.cpp": [
        ('#include "sdl3_joystick.h"', '#include "input_common/sdl/sdl3_joystick.h"'),
    ],
    "System/core/file_sys/secure_value_backend.cpp": [
        ('#include "secure_value_backend.h"', '#include "core/file_sys/secure_value_backend.h"'),
    ],
    "System/core/file_sys/artic_cache.cpp": [
        ('#include "artic_cache.h"', '#include "core/file_sys/artic_cache.h"'),
    ],
    "System/core/file_sys/archive_artic.cpp": [
        ('#include "archive_artic.h"', '#include "core/file_sys/archive_artic.h"'),
    ],
    "System/core/hle/service/http/http_c.cpp": [
        ('#include "ctr-common-1-cert.h"', '#include "core/hle/service/http/ctr-common-1-cert.h"'),
        ('#include "ctr-common-1-key.h"', '#include "core/hle/service/http/ctr-common-1-key.h"'),
    ],
    "System/core/hle/service/dlp/dlp_clt_base.cpp": [
        ('#include "dlp_clt_base.h"', '#include "core/hle/service/dlp/dlp_clt_base.h"'),
    ],
    "System/core/hle/service/dlp/dlp_base.cpp": [
        ('#include "dlp_base.h"', '#include "core/hle/service/dlp/dlp_base.h"'),
    ],
    "System/common/hacks/hack_manager.cpp": [
        ('#include "hack_manager.h"', '#include "common/hacks/hack_manager.h"'),
    ],
    "System/core/frontend/image_interface.cpp": [
        ("#include <dds_ktx.h>", "#include <dds-ktx.h>"),
    ],
    "System/include/core/frontend/image_interface.h": [
        ("#include <dds_ktx.h>", "#include <dds-ktx.h>"),
    ],
    "System/common/dynamic_library/dynamic_library.cpp": [
        ('#include "dynamic_library.h"', '#include "common/dynamic_library/dynamic_library.h"'),
        ('#elif defined(__APPLE__)\n    auto prefix = name.starts_with("lib") ? "" : "lib";', '#elif defined(__APPLE__)\n    if (name == "avcodec" || name == "avdevice" || name == "avfilter" || name == "avformat" || name == "avutil" || name == "swresample" || name == "swscale") {\n        return fmt::format("@rpath/lib{}.framework/lib{}", name, name);\n    }\n    auto prefix = name.starts_with("lib") ? "" : "lib";'),
    ],
    "Cytrus.swift": [
        ("cytrus.is_running()", "cytrus.is_running(false, false)"),
        ("cytrus.is_paused()", "cytrus.is_paused(false, false)"),
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
    "System/core/core.cpp": [
        ("void System::Shutdown(bool is_deserializing) {\n",
         "void System::Shutdown(bool is_deserializing) {\n    {\n        std::scoped_lock lock{signal_mutex};\n        current_signal = Signal::None;\n        signal_param = 0;\n    }\n"),
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
         "if (cntnr.thread.joinable()) cntnr.thread.join();\n    system.Shutdown();"),
        ("cntnr.secondary_width = width;", 
         "cntnr.secondary_width = width;\n        if (cntnr.secondary_window) cntnr.secondary_window->SizeChanged(height, width);"),
        ("cntnr.width = width;", 
         "cntnr.width = width;\n        if (cntnr.window) cntnr.window->SizeChanged(height, width);"),
    ],
    "System/emu_window_vk.cpp": [
        ("window_width = m_size_w;\n}", "window_width = m_size_w;\n    OnFramebufferSizeChanged();\n}"),
    ],
}

# Reviewed port from the last pre-removal Citra loader; kept separate so the
# upstream changes and attribution can be audited without hiding them in setup.
CRYPTO_PATCH = Path(__file__).resolve().parent.parent / "CorePatches/NCCHCrypto/changes.json"
CRYPTO_REPLACEMENTS = json.loads(CRYPTO_PATCH.read_text())
LEGACY_CRYPTO_SETUP = CRYPTO_PATCH.with_name("legacy-0.1.2-setup.txt").read_text()

def patch(root: Path):
    marker = root / ".tandem-patched-v1"
    version = hashlib.sha256(json.dumps([REPLACEMENTS, CRYPTO_REPLACEMENTS], sort_keys=True).encode()).hexdigest()
    if marker.is_file() and marker.read_text().strip() == version:
        return
    # Validate every expected string before changing any source file.
    updated = {}
    for relative in dict.fromkeys([*REPLACEMENTS, *CRYPTO_REPLACEMENTS]):
        source = (root / relative).read_text()
        # Restore the base spans before reapplying: later crypto changes can
        # contain edits inside an earlier safety patch's replacement string.
        for old, new in reversed(CRYPTO_REPLACEMENTS.get(relative, [])):
            if new in source:
                source = source.replace(new, old)
        if relative == "System/core/file_sys/ncch_container.cpp" and LEGACY_CRYPTO_SETUP in source:
            old_guard = next(old for old, new in CRYPTO_REPLACEMENTS[relative]
                             if "bool failed_to_decrypt = false;" in new)
            source = source.replace(LEGACY_CRYPTO_SETUP, old_guard)
        for old, new in [*REPLACEMENTS.get(relative, []), *CRYPTO_REPLACEMENTS.get(relative, [])]:
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
