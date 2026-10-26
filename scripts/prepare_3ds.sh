#!/usr/bin/env bash
set -euo pipefail
TANDEM_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TANDEM_VENDOR="$TANDEM_ROOT/Vendor"
mkdir -p "$TANDEM_VENDOR"

fetch_pin() {
    local name="$1" url="$2" revision="$3"
    local destination="$TANDEM_VENDOR/$name"
    if [[ ! -d "$destination/.git" ]]; then
        [[ ! -e "$destination" ]] || { printf 'error: %s already exists\n' "$destination" >&2; exit 1; }
        git clone --no-checkout "$url" "$destination"
        git -C "$destination" checkout --detach "$revision"
    fi
    [[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]] || {
        printf 'error: %s differs from pinned revision %s. Preserve your changes and use another checkout.\n' "$destination" "$revision" >&2
        exit 1
    }
}

fetch_pin Folium https://github.com/folium-app/Folium.git 64b4528e0e126ebc9f3b7538c52ffec2bf69c4e5
# Only this submodule is used; no other Folium emulator cores are needed.
git -C "$TANDEM_VENDOR/Folium" submodule update --init Cytrus
[[ "$(git -C "$TANDEM_VENDOR/Folium/Cytrus" rev-parse HEAD)" == 81a12f0e425be4f5b3b4b67752e4abb211dcbe2d ]] || {
    printf 'error: Cytrus revision differs from pin\n' >&2; exit 1;
}
fetch_pin SharedDependencies https://github.com/folium-app/SharedDependencies.git 2ee6621fcfe7cb4b938c1d0f1d842c6e2d72f97e
python3 "$TANDEM_ROOT/scripts/patch_cytrus.py" "$TANDEM_VENDOR/Folium/Cytrus"
if [[ -z "${TANDEM_VULKAN_INCLUDE:-}" ]]; then
    python3 "$TANDEM_ROOT/scripts/prepare_graphics_headers.py"
fi
printf 'Pinned 3DS sources and graphics headers prepared. Generate the native project with scripts/generate_native_project.py --3ds --generate.\n'
