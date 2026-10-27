#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TANDEM_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TANDEM_MODE=native
TANDEM_OUTPUT="$TANDEM_ROOT/dist/ipa"

usage() {
    cat <<'EOF'
Usage: bash scripts/build_ipa.sh [--native | --interface] [--output DIRECTORY]

The default native mode prepares both emulator cores and builds an unsigned
device IPA. Interface mode explicitly excludes the emulator cores and produces
a separately named IPA for interface testing. macOS and Xcode are required.
EOF
}
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --native) TANDEM_MODE=native; shift ;;
        --interface) TANDEM_MODE=interface; shift ;;
        --output)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "--output requires a directory."
            TANDEM_OUTPUT="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# Do not create a Payload directory or IPA when there is no Apple compiler.
[[ "$(uname -s)" == Darwin ]] || fail "IPA compilation requires macOS with Xcode and the iPhoneOS SDK. This host cannot compile an iOS application."
for tool in python3 xcodebuild xcrun xcodegen; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required command not found: $tool. See docs/IPA.md."
done
xcrun --sdk iphoneos --show-sdk-path >/dev/null || fail "The selected Xcode has no iPhoneOS SDK."

if [[ "$TANDEM_MODE" == native ]]; then
    bash "$SCRIPT_DIR/prepare_3ds.sh"
    export TANDEM_VULKAN_INCLUDE="${TANDEM_VULKAN_INCLUDE:-$TANDEM_ROOT/Vendor/GraphicsHeaders/include}"
    bash "$SCRIPT_DIR/build_switch.sh"
    python3 "$SCRIPT_DIR/generate_native_project.py" --3ds --switch --generate
    TANDEM_PROJECT="$TANDEM_ROOT/TandemNative.xcodeproj"
else
    (
        cd -- "$TANDEM_ROOT"
        xcodegen generate --spec project.yml
    )
    TANDEM_PROJECT="$TANDEM_ROOT/Tandem.xcodeproj"
fi

mkdir -p -- "$TANDEM_OUTPUT"
TANDEM_OUTPUT="$(cd -- "$TANDEM_OUTPUT" && pwd)"
TANDEM_BUILD_DIR="$(mktemp -d "$TANDEM_OUTPUT/build-$TANDEM_MODE-XXXXXX")"
TANDEM_ARCHIVE="$TANDEM_BUILD_DIR/Tandem.xcarchive"


# Preserve the build log and real archive for inspection. A failed compiler or
# linker exits through pipefail and can never fall through to IPA packaging.
xcodebuild \
    -project "$TANDEM_PROJECT" \
    -scheme Tandem \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$TANDEM_ARCHIVE" \
    -derivedDataPath "$TANDEM_BUILD_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    archive 2>&1 | tee "$TANDEM_BUILD_DIR/xcodebuild.log"

TANDEM_VERSION="$(python3 - "$TANDEM_ARCHIVE/Products/Applications/Tandem.app/Info.plist" <<'PYVERSION'
import plistlib, re, sys
with open(sys.argv[1], 'rb') as file:
    version = plistlib.load(file).get('CFBundleShortVersionString')
if not isinstance(version, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version):
    raise SystemExit('The archived app has no valid numeric version.')
print(version)
PYVERSION
)"
TANDEM_SUFFIX=""
if [[ "$TANDEM_MODE" == interface ]]; then TANDEM_SUFFIX="-interface"; fi
TANDEM_IPA="$TANDEM_OUTPUT/tandemv$TANDEM_VERSION$TANDEM_SUFFIX.ipa"

TANDEM_REVISION="${GITHUB_SHA:-}"
if [[ -z "$TANDEM_REVISION" ]]; then
    if command -v git >/dev/null 2>&1 && git -C "$TANDEM_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
        TANDEM_REVISION="$(git -C "$TANDEM_ROOT" rev-parse HEAD)"
    else
        TANDEM_REVISION=unversioned-source
    fi
fi
TANDEM_XCODE_VERSION="$(xcodebuild -version)"
if [[ "$TANDEM_MODE" == native ]]; then
    python3 "$SCRIPT_DIR/verify_native_exports.py" \
        --app "$TANDEM_ARCHIVE/Products/Applications/Tandem.app"
fi
python3 "$SCRIPT_DIR/package_ipa.py" \
    --app "$TANDEM_ARCHIVE/Products/Applications/Tandem.app" \
    --output "$TANDEM_IPA" \
    --mode "$TANDEM_MODE" \
    --source-revision "$TANDEM_REVISION" \
    --archive-path "$TANDEM_ARCHIVE" \
    --xcode-version "$TANDEM_XCODE_VERSION"

printf 'Compiled %s\n' "$TANDEM_IPA"
printf 'Unsigned development artifact: re-sign the app and all embedded native code before installing.\n'
if [[ "$TANDEM_MODE" == interface ]]; then
    printf 'This interface IPA contains no emulator cores and cannot run games.\n'
fi
