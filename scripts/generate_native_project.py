#!/usr/bin/env python3
"""Generate XcodeGen's native spec; never pretend an absent core is present."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
FFMPEG_LIBRARIES = ["libavcodec", "libavdevice", "libavfilter", "libavformat",
                    "libavutil", "libswresample", "libswscale"]

def specification(vulkan_include: Path | None, with_3ds: bool, with_switch: bool):
    spec = {"include": ["project.yml"], "name": "TandemNative", "packages": {},
            "targets": {"Tandem": {"dependencies": []}}}
    app = spec["targets"]["Tandem"]
    if with_3ds:
        app.setdefault("settings", {}).setdefault("base", {})["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = [
            "$(inherited)", "TANDEM_HAS_CYTRUS"]
        cytrus = ROOT / "Vendor/Folium/Cytrus"
        shared = ROOT / "Vendor/SharedDependencies"
        zstd = ROOT / "Vendor/Zstd"
        if not (cytrus / ".tandem-patched-v1").is_file() or not (shared / "Package.swift").is_file():
            raise ValueError("Run scripts/prepare_3ds.sh first.")
        for relative in ["Package.swift", "lib/zstd.h", "contrib/seekable_format/zstd_seekable.h"]:
            if not (zstd / relative).is_file():
                raise ValueError(f"Missing pinned zstd source/header: {zstd / relative}. Run scripts/prepare_3ds.sh first.")
        vulkan_include = vulkan_include or ROOT / "Vendor/GraphicsHeaders/include"
        if not (vulkan_include / "vulkan/vulkan.hpp").is_file():
            raise ValueError("Run scripts/prepare_3ds.sh to prepare graphics headers, or set TANDEM_VULKAN_INCLUDE to a Vulkan SDK include directory.")
        for relative in ["vulkan/vulkan_core.h", "glslang/Public/ShaderLang.h",
                         "glslang/Include/ResourceLimits.h", "glslang/SPIRV/GlslangToSpv.h",
                         "vma/vk_mem_alloc.h", "spirv/unified1/spirv.hpp11",
                         "spirv/unified1/GLSL.std.450.h"]:
            if not (vulkan_include / relative).is_file():
                raise ValueError(f"Missing Vulkan SDK header: {vulkan_include / relative}")
        # FFmpeg is compiled unconditionally by the pinned Cytrus source. Add
        # every bundled framework because avfilter also loads swscale/avformat.
        ffmpeg = [f"Vendor/Folium/Dependencies/FFmpeg/{name}.xcframework"
                  for name in FFMPEG_LIBRARIES]
        native_frameworks = ffmpeg + [
            "Vendor/Folium/Dependencies/MoltenVK.xcframework",
            *[f"Vendor/Folium/Dependencies/Boost/{name}.xcframework"
              for name in ["libboost_iostreams", "libboost_serialization"]]]
        for relative in native_frameworks:
            if not (ROOT / relative / "Info.plist").is_file():
                raise ValueError(f"Missing bundled native dependency: {relative}. Run scripts/prepare_3ds.sh first.")
        includes = [str(path.relative_to(ROOT)) for path in sorted((shared / "Sources").glob("*/include"))]
        includes += ["$(SRCROOT)/Vendor/Zstd/lib", "$(SRCROOT)/Vendor/Zstd/contrib"]
        includes += [str(vulkan_include), str(vulkan_include / "vma"), str(vulkan_include / "glslang")]
        spec["packages"] = {
            "SharedDependencies": {"path": "Vendor/SharedDependencies"},
            "zstd": {"path": "Vendor/Zstd"}}
        spec["targets"]["Cytrus"] = {
            "type": "library.static", "platform": "iOS",
            # These headers are implementation files, resolved through search
            # paths. Exporting them flattens distinct names such as core/memory.h
            # and audio_core/memory.h into the same archive include directory.
            "sources": [{"path": "Vendor/Folium/Cytrus", "excludes": [
                "README.md", "LICENSE", ".tandem-patched-v1",
                "**/*.h", "**/*.hpp", "**/*.hh", "**/*.hxx", "**/*.inl", "**/*.inc"]}],
            "settings": {"base": {
                "SWIFT_VERSION": "6.0", "SWIFT_DEFAULT_ACTOR_ISOLATION": "nonisolated",
                "DEFINES_MODULE": "YES",
                "SWIFT_OBJC_BRIDGING_HEADER": "Vendor/Folium/Cytrus/System/include/cytrus/bridge.h",
                "USER_HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Vendor/Folium/Cytrus/System/include"],
                "SYSTEM_HEADER_SEARCH_PATHS": ["$(inherited)"] + includes,
                "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "CPPHTTPLIB_OPENSSL_SUPPORT", "FOR_CYTRUS", "HAVE_FASTINTERP", "HAVE_COREAUDIO", "HAVE_OPENAL", "HAVE_SDL3", "ENABLE_GDBSTUB", "ENABLE_SDL3", "ENABLE_VULKAN", "ENABLE_WEB_SERVICE"],
                "GCC_C_LANGUAGE_STANDARD": "gnu23", "CLANG_CXX_LANGUAGE_STANDARD": "gnu++23",
                "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"], "SKIP_INSTALL": "YES"}},
            "dependencies": [
                {"package": "SharedDependencies"},
                *[{"package": "zstd", "product": product} for product in ["libseekable_format", "libzstd", "libzstdwrapper"]],
                *[{"framework": f"Vendor/Folium/Dependencies/Boost/{name}.xcframework", "embed": False}
                  for name in ["libboost_iostreams", "libboost_serialization"]],
                *[{"framework": path, "embed": False} for path in ffmpeg]
            ]}
        app["dependencies"] += [
            {"target": "Cytrus"}, {"package": "SharedDependencies"},
            *[{"package": "zstd", "product": product}
              for product in ["libseekable_format", "libzstd", "libzstdwrapper"]],
            *[{"framework": f"Vendor/Folium/Dependencies/Boost/{name}.xcframework", "embed": False}
              for name in ["libboost_iostreams", "libboost_serialization"]],
            {"framework": "Vendor/Folium/Dependencies/MoltenVK.xcframework", "embed": True, "codeSign": True},
            *[{"framework": path, "embed": True, "codeSign": True} for path in ffmpeg],
            {"sdk": "CoreAudio.framework"}, {"sdk": "AudioToolbox.framework"},
            {"sdk": "Accelerate.framework"}, {"sdk": "CoreMedia.framework"},
            {"sdk": "VideoToolbox.framework"}, {"sdk": "CoreImage.framework"},
            {"sdk": "CoreVideo.framework"}, {"sdk": "libresolv.tbd"},
            {"sdk": "libz.tbd"}, {"sdk": "libbz2.tbd"}]
    if with_switch:
        for name in ["Ryujinx.Headless.SDL2.dylib", "libMoltenVK.dylib", "libavcodec.dylib", "libavutil.dylib", "SDL2.xcframework"]:
            if not (ROOT / "Frameworks" / name).exists():
                raise ValueError(f"Missing Frameworks/{name}; run scripts/build_switch.sh on a Mac first.")
            app["dependencies"].append({"framework": f"Frameworks/{name}", "embed": True, "codeSign": True})
        app["dependencies"].append({"target": "RyujinxHelper", "embed": True, "codeSign": True})
        app["sources"] = [{"path": "Frameworks/Notices", "buildPhase": "resources"}]
        for optional in ["BreakpointJIT.framework", "Hypervisor.framework"]:
            if (ROOT / "Frameworks" / optional).exists():
                app["dependencies"].append({"framework": f"Frameworks/{optional}", "embed": True, "codeSign": True})
        spec["targets"]["RyujinxHelper"] = {
            "type": "framework", "platform": "iOS",
            "sources": [{"path": "FrameworkSources/RyujinxHelper", "headerVisibility": "public"}],
            "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "app.tandem.RyujinxHelper",
                                   "GENERATE_INFOPLIST_FILE": "YES", "DEFINES_MODULE": "YES"}},
            "dependencies": [{"sdk": "UIKit.framework"}]}
    return spec

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--3ds", dest="with_3ds", action="store_true")
    parser.add_argument("--switch", dest="with_switch", action="store_true")
    parser.add_argument("--generate", action="store_true", help="Also run XcodeGen")
    args = parser.parse_args()
    if not args.with_3ds and not args.with_switch:
        parser.error("Select --3ds, --switch, or both. For the interface project, use xcodegen generate directly.")
    sdk = os.environ.get("TANDEM_VULKAN_INCLUDE")
    try:
        spec = specification(Path(sdk).expanduser().resolve() if sdk else None, args.with_3ds, args.with_switch)
    except ValueError as error:
        parser.exit(1, f"error: {error}\n")
    output = ROOT / "project.native.yml"
    output.write_text(json.dumps(spec, indent=2) + "\n")
    print(f"Wrote {output.name}; this spec includes the selected native cores.")
    if args.generate:
        subprocess.run(["xcodegen", "generate", "--spec", output.name], cwd=ROOT, check=True)
        if args.with_3ds:
            lock = ROOT / "TandemNative.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            lock.parent.mkdir(parents=True, exist_ok=True)
            lock.write_bytes((ROOT / "Config/NativePackage.resolved").read_bytes())

if __name__ == "__main__":
    main()
