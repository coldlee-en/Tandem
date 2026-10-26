#!/usr/bin/env bash
set -euo pipefail

# Build the pinned MeloNX/Ryujinx NativeAOT iOS core. This script never changes
# signing settings, installs SDKs, or modifies files outside this project.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TANDEM_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TANDEM_MELONX_SOURCE="${TANDEM_MELONX_SOURCE:-$TANDEM_ROOT/Vendor/MeloNX}"
TANDEM_MELONX_REVISION="55f84af15144e40d7fbe8984747855534d2a8ec1"
TANDEM_FRAMEWORKS_DIR="$TANDEM_ROOT/Frameworks"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "The Switch core requires macOS, Xcode, and the iPhoneOS SDK."
for tool in git dotnet xcode-select xcrun ditto python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required command not found: $tool. See docs/SWITCH_CORE.md."
done
git lfs version >/dev/null 2>&1 || fail "Git LFS is required to fetch the pinned native dependencies."
TANDEM_XCODE_PATH="$(xcode-select -p)"
xcrun --sdk iphoneos --show-sdk-path >/dev/null || fail "The selected Xcode does not have an iPhoneOS SDK."
dotnet --list-sdks | awk '/^8[.]/ { found = 1 } END { exit !found }' || fail "Install a .NET 8 SDK; the pinned source uses net8.0."

if [[ ! -d "$TANDEM_MELONX_SOURCE/.git" ]]; then
    [[ ! -e "$TANDEM_MELONX_SOURCE" ]] || fail "The source path exists but is not a Git checkout: $TANDEM_MELONX_SOURCE"
    mkdir -p -- "$(dirname -- "$TANDEM_MELONX_SOURCE")"
    GIT_LFS_SKIP_SMUDGE=1 git clone --no-checkout https://github.com/AzureDominus/melonx.git "$TANDEM_MELONX_SOURCE"
    GIT_LFS_SKIP_SMUDGE=1 git -C "$TANDEM_MELONX_SOURCE" checkout --detach "$TANDEM_MELONX_REVISION"
fi
[[ "$(git -C "$TANDEM_MELONX_SOURCE" rev-parse HEAD)" == "$TANDEM_MELONX_REVISION" ]] || fail "MeloNX source revision differs from the reviewed pin. Use a separate checkout at $TANDEM_MELONX_REVISION."

# These .dylib files are Git LFS objects, not normal Git blobs. A source clone
# can otherwise appear complete while containing 130-byte pointer files.
git -C "$TANDEM_MELONX_SOURCE" lfs pull --include='src/MeloNX/MeloNX/Dependencies/Dynamic Libraries/*.dylib' --exclude=''
TANDEM_DEPENDENCIES_DIR="$TANDEM_MELONX_SOURCE/src/MeloNX/MeloNX/Dependencies"
for library in libMoltenVK.dylib libavcodec.dylib libavutil.dylib; do
    artifact="$TANDEM_DEPENDENCIES_DIR/Dynamic Libraries/$library"
    [[ -f "$artifact" ]] || fail "Missing upstream native dependency: $library"
    xcrun lipo "$artifact" -verify_arch arm64 || fail "$library is not an arm64 Mach-O library. Check Git LFS download access."
done

# These exports and data-path changes are required by Tandem's native adapter.
[[ -f "$SCRIPT_DIR/patch_switch.py" ]] || fail "Missing scripts/patch_switch.py; restore the complete Tandem source checkout."
python3 "$SCRIPT_DIR/patch_switch.py" "$TANDEM_MELONX_SOURCE"

(
    cd -- "$TANDEM_MELONX_SOURCE"
    dotnet publish src/Ryujinx.Headless.SDL2/Ryujinx.Headless.SDL2.csproj \
        -c Release -r ios-arm64 --self-contained true \
        -p:ExtraDefineConstants=DISABLE_UPDATER \
        "-p:XCodePath=$TANDEM_XCODE_PATH/"
)

TANDEM_NATIVE_OUTPUT="$TANDEM_MELONX_SOURCE/src/Ryujinx.Headless.SDL2/bin/Release/net8.0/ios-arm64"
TANDEM_CORE_BINARY="$TANDEM_NATIVE_OUTPUT/publish/Ryujinx.Headless.SDL2.dylib"
if [[ ! -f "$TANDEM_CORE_BINARY" ]]; then
    TANDEM_CORE_BINARY="$TANDEM_NATIVE_OUTPUT/native/Ryujinx.Headless.SDL2.dylib"
fi
[[ -f "$TANDEM_CORE_BINARY" ]] || fail "NativeAOT completed without the expected Ryujinx.Headless.SDL2.dylib artifact."
xcrun lipo "$TANDEM_CORE_BINARY" -verify_arch arm64 || fail "The compiled core is not an arm64 Mach-O library."

mkdir -p -- "$TANDEM_FRAMEWORKS_DIR"
ditto "$TANDEM_CORE_BINARY" "$TANDEM_FRAMEWORKS_DIR/Ryujinx.Headless.SDL2.dylib"
mkdir -p -- "$TANDEM_FRAMEWORKS_DIR/Notices/Switch"
ditto "$TANDEM_MELONX_SOURCE/LICENSE.txt" "$TANDEM_FRAMEWORKS_DIR/Notices/Switch/LICENSE.txt"
ditto "$TANDEM_MELONX_SOURCE/distribution/legal/THIRDPARTY.md" "$TANDEM_FRAMEWORKS_DIR/Notices/Switch/THIRDPARTY.md"
for library in libMoltenVK.dylib libavcodec.dylib libavutil.dylib; do
    ditto "$TANDEM_DEPENDENCIES_DIR/Dynamic Libraries/$library" "$TANDEM_FRAMEWORKS_DIR/$library"
done
for framework in SDL2; do
    ditto "$TANDEM_DEPENDENCIES_DIR/XCFrameworks/$framework.xcframework" "$TANDEM_FRAMEWORKS_DIR/$framework.xcframework"
done
# These paths are only used by the corresponding optional native code path.
for framework in BreakpointJIT Hypervisor; do
    source_framework="$TANDEM_DEPENDENCIES_DIR/Dynamic Libraries/$framework.framework"
    if [[ -d "$source_framework" ]]; then
        xcrun lipo "$source_framework/$framework" -verify_arch arm64 || fail "$framework has no arm64 binary."
        ditto "$source_framework" "$TANDEM_FRAMEWORKS_DIR/$framework.framework"
    fi
done

# RyujinxHelper is built from Tandem's source, so the upstream precompiled helper
# is intentionally not copied. Xcode must Embed & Sign every dynamic artifact.
# Historical FFmpeg binaries can refer to versioned filenames or build-machine
# paths. Relocate known bundled dependencies before Xcode signs the final copies.
python3 - "$TANDEM_FRAMEWORKS_DIR" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
names = ["Ryujinx.Headless.SDL2.dylib", "libMoltenVK.dylib", "libavcodec.dylib", "libavutil.dylib"]
for name in names:
    artifact = root / name
    subprocess.run(["xcrun", "install_name_tool", "-id", "@rpath/" + name, str(artifact)], check=True)
    lines = subprocess.check_output(["xcrun", "otool", "-L", str(artifact)], text=True).splitlines()[1:]
    for line in lines:
        dependency = line.strip().split(" (compatibility version", 1)[0]
        basename = Path(dependency).name
        for stem in ["libMoltenVK", "libavcodec", "libavutil"]:
            if re.fullmatch(re.escape(stem) + r"(?:\.\d+)*\.dylib", basename):
                relocated = "@rpath/" + stem + ".dylib"
                if dependency != relocated:
                    subprocess.run(["xcrun", "install_name_tool", "-change", dependency, relocated, str(artifact)], check=True)
                break
PY

python3 - "$TANDEM_FRAMEWORKS_DIR" "$TANDEM_MELONX_REVISION" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
files = ["Ryujinx.Headless.SDL2.dylib", "libMoltenVK.dylib", "libavcodec.dylib", "libavutil.dylib"]
manifest = {
    "source": "https://github.com/AzureDominus/melonx",
    "revision": sys.argv[2],
    "runtime": "ios-arm64",
    "artifacts": {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files},
}
(root / "SwitchBuildManifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
printf 'Switch core artifacts prepared in %s\n' "$TANDEM_FRAMEWORKS_DIR"
printf 'Next: generate the native Xcode project and build for a physical iPhone/iPad.\n'
