# Switch core integration

The integration targets the actual C exports of the MeloNX iOS port of Ryujinx,
pinned to [`AzureDominus/melonx` at `55f84af15144e40d7fbe8984747855534d2a8ec1`](https://github.com/AzureDominus/melonx/tree/55f84af15144e40d7fbe8984747855534d2a8ec1).
The source contains a NativeAOT .NET core and its own Swift frontend. Tandem uses
the native core with its own interface.

**Status:** the Switch NativeAOT runtime has compiled on macOS, and its cached
artifact has been verified. The final native app archive and IPA remain pending.
Runtime behavior, JIT, and gameplay have not been verified on an iPhone. This is
a development integration, not a tested compatibility claim.

## Build requirements

- macOS with Xcode selected by `xcode-select` and an installed iPhoneOS SDK.
- A .NET 8 SDK on `PATH`. The source's `global.json` requests `8.0.100` with
  `latestFeature` roll-forward and targets `net8.0`/`ios-arm64`.
- Git, Git LFS, and Python 3. Native dependencies are Git LFS objects.
- Access to NuGet (`https://api.nuget.org/v3/index.json`), GitHub, and the
  repository's Git LFS storage. NativeAOT restores packages from the upstream
  project; unavailable historical packages stop the build with the restore error.
- A physical arm64 iPhone or iPad. This Switch core has no simulator build.

From the Tandem root:

```sh
bash scripts/build_switch.sh
```

The script creates `Vendor/MeloNX` at the pinned revision if it is absent. It
refuses an existing checkout at a different revision and never resets local
source edits. `TANDEM_MELONX_SOURCE=/absolute/path/to/checkout` can select an
existing pinned checkout.

The publication command is the upstream iOS command with an explicit selected
Xcode path:

```sh
dotnet publish src/Ryujinx.Headless.SDL2/Ryujinx.Headless.SDL2.csproj \
  -c Release -r ios-arm64 --self-contained true \
  -p:ExtraDefineConstants=DISABLE_UPDATER \
  -p:XCodePath=/Applications/Xcode.app/Contents/Developer/
```

The script does not install .NET workloads, change `xcode-select`, request
entitlements, or sign the final app. A NativeAOT toolchain failure must be
resolved on the Mac before proceeding. The final native Xcode project must
embed and sign the copied dynamic libraries and frameworks using the app's
development signing identity. Build instructions for the complete app are in
[BUILDING.md](BUILDING.md).

## Runtime artifacts

| Artifact | Purpose |
| --- | --- |
| `Ryujinx.Headless.SDL2.dylib` | The compiled NativeAOT Switch core. |
| `SDL2.xcframework` | iOS window/event services used by the core. |
| `libMoltenVK.dylib` | Vulkan translation to Metal. |
| `libavcodec.dylib`, `libavutil.dylib` | Video decoding dependencies. |
| `RyujinxHelper.framework` | Tandem's source-built native event and applet bridge. |
| `BreakpointJIT.framework` | Optional upstream JIT-mapping path on supported setups. |
| `Hypervisor.framework` | Optional upstream hypervisor path; ordinary JIT launches keep it disabled. |

The copied `.dylib` files in the source checkout may initially contain Git LFS
pointer text. `build_switch.sh` downloads the selected LFS objects and checks
that they contain arm64 Mach-O binaries before packaging. `SwitchBuildManifest.json`
records the source revision and the copied dynamic libraries' SHA-256 hashes.
`Frameworks/Notices/Switch` receives the upstream license and third-party notices;
include those notices as resources when distributing the native app.
The upstream precompiled `RyujinxHelper` is not copied; Tandem builds that helper
from source.

Upstream `FFmpegApi.cs` searches for versioned iOS names such as
`libavcodec.59.dylib`, while the included artifacts have unversioned names. A
Tandem core patch must make the iOS resolver use the included artifact names;
otherwise video playback can fail even when the game boots.
The build script also normalizes the copied dylibs' install names and their
known FFmpeg/MoltenVK references to the bundled unversioned filenames before
Xcode signs them. The first device build must still check for any additional
transitive native dependencies reported by the dynamic loader.

## Storage and startup

Tandem's Switch data directory is `Documents/Tandem/System/Switch`, visible in
the Files app when File Sharing is enabled. The core expects its standard
Ryujinx directory structure: console keys under `system/`, NAND content under
`bis/`, and saves/cache in the core's other managed directories. Firmware
content belongs to the NAND tree managed by the core; copying a firmware ZIP
into a folder does not install it.

The pinned `initialize` export initializes the VFS using `Documents` before
command-line arguments are parsed. Tandem's patch must select the Switch data
directory before calling that export, as well as passing `--root-data-dir`
when invoking the native runner. Setting only the command-line option after
initialization is too late for already constructed VFS/account objects.

Supply games and any required console data yourself. The application does not
download games, keys, or firmware. Importable extensions identify library files;
they do not establish that a title is valid or compatible with this core.

## JIT and lifecycle

Switch execution requires a suitable JIT-enabled development process. A normal
signed iOS build does not acquire JIT just by requesting a build entitlement.
Tandem checks the process state and reports a launch error when JIT is absent.
An OS debug flag is a preflight check; successful executable-memory allocation
and game compatibility still require testing on the target device and iOS
version. The upstream iOS 26 dual-mapped path has additional runtime requirements.

The native `main_ryujinx_sdl` call blocks until the run loop exits and belongs on
a worker thread. The real `ran-first-frame` event is the useful startup signal;
returning from a wrapper immediately after creating a thread does not prove a
game started. Pause calls use `pause_emulation`. The adapter resolves
`tandem_request_stop`, which captures the current native window and queues stop,
latches early cancellation, and wakes a GPU waiting on pause. Keep the native
library loaded and the `CAMetalLayer`, strings, controller identity, and callbacks
alive until the worker has exited.

The [native lifecycle regression harness](../scripts/tests/README.md) compiles
the actual lifecycle methods with graphics/SDL stubs. All five test groups passed,
including 300 concurrent start/stop races. This checks cancellation control flow;
it does not run games or validate real graphics and the iOS ABI.

Validate startup errors, background pause, repeated stop/start, touch, controller
input, video decoding, firmware failures, and memory limits on real hardware
using [DEVICE_TESTING.md](DEVICE_TESTING.md).

The pinned fork's `LICENSE.txt` states **AGPL version 3 or later** and includes
historical MeloNX license text. Preserve that exact file, its
`distribution/legal/THIRDPARTY.md` notices, and the corresponding source and
Tandem patches with redistributed builds. Do not assume the original Ryujinx
project's MIT license describes all code added by this fork.
