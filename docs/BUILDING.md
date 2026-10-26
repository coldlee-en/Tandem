# Building Tandem

## Validation status

All 23 EmulationKit library tests pass on macOS. They cover file import, index
persistence, failed-write rollback, path/symlink rejection, and interrupted-delete
recovery. The iOS interface compiles in macOS CI, and all 4 session-lifecycle
tests pass in the iOS simulator with 0 failures.

The complete native app, including Switch NativeAOT and Cytrus, archived and
packaged successfully in [macOS CI](https://github.com/coldlee-en/Tandem/actions/runs/40418548887).
The [unsigned development IPA](https://github.com/coldlee-en/Tandem/actions/runs/40418548887/artifacts/12696757979)
must be re-signed for sideloading. Signing, physical-device execution, performance,
and game compatibility remain unverified; Switch requires JIT. See
[VALIDATION.md](VALIDATION.md) and [IPA.md](IPA.md) for evidence and installation requirements.

## Interface project

Use macOS with Xcode 26 or later, Python 3, Git, and XcodeGen. The app supports
iOS 17+, while the pinned SharedDependencies package requires Swift tools 6.2.
Install XcodeGen with your preferred package manager, then from the project root:

```sh
xcodegen generate
open Tandem.xcodeproj
```

Choose a simulator or device and build the `Tandem` scheme. This project needs no
emulator binaries. It supports ROM imports and controls, and reports that cores
are unavailable when attempting emulation. Change `PRODUCT_BUNDLE_IDENTIFIER`
and select your own development team when signing for a device.

## 3DS native integration

```sh
bash scripts/prepare_3ds.sh
```

The script checks out these source pins without overwriting a different existing
checkout:

| Source | Revision |
| --- | --- |
| folium-app/Folium | `64b4528e0e126ebc9f3b7538c52ffec2bf69c4e5` |
| folium-app/Cytrus submodule | `81a12f0e425be4f5b3b4b67752e4abb211dcbe2d` |
| folium-app/SharedDependencies | `9787aa9062d8ff220f127052597e6f3ae1dcbc7a` |
| jarrodnorwell/zstd | `9baae4431585740983318801beff0a7ae4494291` |

Cytrus needs Vulkan, SPIR-V, glslang, and Vulkan Memory Allocator headers, in addition to
the dependencies provided through SwiftPM. Preparation now automatically checks
out the matching open-source Vulkan SDK `1.4.363.0` headers and VMA `3.3.0` into
`Vendor/GraphicsHeaders/include`, without a full SDK installer:

```sh
python3 scripts/generate_native_project.py --3ds --generate
open TandemNative.xcodeproj
```

The script pins SPIRV-Headers to `496543121ce6419f23d6fa5d7194ba66c36212d2`
(Vulkan SDK 1.4.363.0). A recognized earlier generated header set is preserved
under `Vendor/GraphicsHeaders/headers-backup-*` when upgraded; unknown directories
are left untouched.

The generator verifies `vulkan/vulkan.hpp`, `spirv/unified1/spirv.hpp11`,
`spirv/unified1/GLSL.std.450.h`, `glslang/Public/ShaderLang.h`, and
`vma/vk_mem_alloc.h`. If your SDK places these elsewhere, create a matching
development include directory and set `TANDEM_VULKAN_INCLUDE` to override the
automatic headers. It uses Folium's existing MoltenVK, Boost, and FFmpeg
XCFrameworks, and SharedDependencies/zstd
Swift packages. SwiftPM restores additional upstream packages/artifacts, so
network access to GitHub and those artifact hosts is required.
When `--generate` is used, the generator also seeds the native workspace's
`Package.resolved` with the reviewed upstream OpenSSL and PLzmaSDK
revisions from `Config/NativePackage.resolved`.

The zstd package is checked out at its listed pin into `Vendor/Zstd` and used as
a local Swift package. Cytrus also receives explicit `lib` and `contrib` header
search paths, so its C++ files can include `zstd.h` and
`seekable_format/zstd_seekable.h` during archive builds.

The pinned SharedDependencies revision includes Boost headers and declares
nihstro's dependency on them. Its DDS header uses the upstream `dds-ktx.h`
filename; Tandem's Cytrus patch updates the two older includes accordingly.

The generated `Cytrus` static target uses upstream build definitions and includes
the core's Swift/C++ bridge. The app embeds/signs MoltenVK. The checked source
patch makes the user directory explicit, returns native load failures, selects
playback audio, avoids a missing LED callback crash, joins the CPU thread before
teardown, releases old windows, updates resized screens, and reports run-loop
termination. It sleeps during pause instead of spinning continuously.

The adapter chooses the CPU interpreter unless the process has debugger/JIT
state. It disables shader CPU JIT and uses native resolution as conservative
defaults. Interpreter performance and title compatibility are unverified.

## Switch native integration

See [SWITCH_CORE.md](SWITCH_CORE.md) for the .NET 8 NativeAOT, Git LFS, SDK,
artifact, and runtime details. Build the pinned native core on a Mac:

```sh
bash scripts/build_switch.sh
python3 scripts/generate_native_project.py --switch --generate
open TandemNative.xcodeproj
```

For both systems, run the two preparation scripts and generate with
`--3ds --switch --generate`. The resulting project retains the same `Tandem`
app/scheme and adds the selected native targets/dependencies. Generated specs
and Vendor/Frameworks outputs are ignored by Git.

The Switch adapter loads signed binaries from the app's Frameworks directory.
It never downloads executable cores at runtime. A source-built `RyujinxHelper`
framework provides first-frame events and native keyboard/alert applets.
Shader-cache progress and rumble callbacks are currently ignored.

Run a development build through Xcode on a physical arm64 iPhone/iPad so the
process can obtain debugger/JIT state. The native dual-mapping initialization
must also succeed. Simulator and ordinary signed execution are rejected for
Switch. No entitlement file is added claiming to grant JIT. Resource-heavy games
may exceed a device's memory budget; no increased-memory entitlement is assumed.

The core patch adds exception-contained initialization exports, reloads console
keys before initialization, selects `TANDEM_SWITCH_ROOT` before VFS/account setup,
uses bundled FFmpeg names, synchronizes native touch state, and waits for firmware
installation before reporting completion. A failed VFS constructor does not mark
the singleton initialized, allowing recovery after correcting keys.

## Game and system files

Import game files using the library's + button. The app copies supported files
into `On My iPhone/Tandem/Tandem/ROMs`; the source remains intact. CIA packages
are not directly bootable imports. An accepted extension does not validate game
content; the core decides whether a file can actually boot.

In Settings, import your Switch `prod.keys`, then install your firmware ZIP when
the Switch core is embedded. Key import checks text/file shape; the native core
validates the actual key contents. Firmware installation does not require guest
JIT. Only one native maintenance/game operation runs at a time.

3DS user data lives under `Tandem/System/3DS` in the app's Documents directory.
Use that core's standard directories (`sysdata`, `nand`, `sdmc`, and so on) for
your console's required data. Switch keys live in `Tandem/System/Switch/system`;
its native installer manages firmware under the standard NAND `bis` tree.
Switch logs/cache/saves remain under the same Switch root. Some upstream log
sinks may be disabled; use Xcode's console when diagnosing startup.

Save states, multiplayer, cheats, automatic game metadata/artwork, game updates,
DLC management, motion/gyro, and rumble are not implemented in this interface.
In-game saves use the native core's user-data directory.

## Tests and device validation

```sh
swift test --package-path Packages/EmulationKit
xcodegen generate
xcodebuild -project Tandem.xcodeproj -scheme Tandem \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Use an installed simulator name (`xcrun simctl list devices available`). The
session tests inject a fake core to check lifecycle ordering without native
emulation. CI has compiled the interface and executed all 4 session-lifecycle
tests in the iOS simulator with 0 failures. Native builds require the dependencies
described above. Complete
[DEVICE_TESTING.md](DEVICE_TESTING.md) on a physical device before calling this
a playable release. A native core that hangs cannot be safely killed inside the
app; teardown retains its surfaces/arguments while waiting for native exit.
