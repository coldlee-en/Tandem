# Tandem

A native iOS development project for Nintendo 3DS and Nintendo Switch emulation,
using Cytrus/Azahar and the MeloNX iOS port of Ryujinx. SwiftUI, Metal surfaces,
GameController, and local file storage. iOS 17 or later.

**An unsigned native development IPA is available** from the
[successful Actions build](https://github.com/coldlee-en/Tandem/actions/runs/40418548887/artifacts/12696757979).
It includes both emulator integrations and must be re-signed for sideloading.
All 23 ROM-library tests and 4 iOS simulator session tests pass in macOS CI.
Physical-device execution, performance, and game compatibility remain unverified;
Switch requires working JIT after installation. See [IPA.md](docs/IPA.md).

Version **0.1.1** adds encrypted 3DS cartridge loading with console-supplied AES
keys. In Settings, use **Import 3DS AES keys**, then retry the game. Some titles
also require **Import 3DS seed database**. See [encrypted 3DS setup](docs/3DS_ENCRYPTION.md).

## What is implemented

- Searchable 3DS/Switch library, Files imports, persistence, last-played dates,
  source-file preservation, and recoverable deletion transactions.
- Paired 3DS displays, Switch display, Metal layer resize, touchscreen routing,
  simultaneous touch buttons, analog sticks, and Bluetooth gamepad input.
- Session startup/pause/stop state, background pause, release of held controls,
  startup cancellation, and native exit reporting.
- A Cytrus adapter with interpreter/JIT selection and checked native load results.
- A MeloNX adapter using its real NativeAOT exports, with a JIT gate, native
  worker, retained arguments/surfaces, first-frame startup confirmation, timeout,
  touchscreen, and safe stop sequencing.
- Switch key import and native firmware ZIP installation in Settings. Firmware
  completion is reported after installation finishes. No guest JIT is needed
  just to install firmware.
- Pinned-source setup scripts, checked core patches, an XcodeGen project,
  optional native project generation, library tests, and iOS lifecycle tests.

The standard project builds the interface without emulator binaries and reports
the missing cores in Settings. The native project links/embeds the cores you
build on a Mac. No gameplay, FPS, or compatibility result is simulated.

## Build

See [the build guide](docs/BUILDING.md) for the complete commands and requirements.
For unsigned IPA packaging and the macOS workflow, see [IPA.md](docs/IPA.md).
The ready-to-publish GitHub Pages site is in `site/`; see
[GitHub publication](docs/GITHUB.md) for repository, hosting, and build automation.
For the interface project on a Mac with Xcode and XcodeGen:

```sh
xcodegen generate
open Tandem.xcodeproj
```

To prepare both native integrations:

```sh
bash scripts/prepare_3ds.sh
bash scripts/build_switch.sh
python3 scripts/generate_native_project.py --3ds --switch --generate
open TandemNative.xcodeproj
```

Select your own signing team and a physical iPhone/iPad. Switch emulation requires
a JIT-capable development process; the app checks for debugger state and the
native core then verifies its JIT mapping. Ordinary signing does not grant JIT.
3DS can select interpreter mode, with device-dependent performance.

Use your own games and required console data. No ROMs, keys, or firmware are
included or downloaded by this project. The build scripts fetch emulator source
and native development dependencies only.

## Verification

```sh
swift test --package-path Packages/EmulationKit
xcodegen generate
xcodebuild -project Tandem.xcodeproj -scheme Tandem \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Choose an installed simulator name for the last command. The simulator exercises
the interface/lifecycle tests; it does not run the native emulator cores.
The [Validate workflow passed](https://github.com/coldlee-en/Tandem/actions/runs/40418548684),
including all 23 library tests on macOS, interface compilation, and execution of
all 4 session-lifecycle tests in the iOS simulator with 0 failures. Those tests
use an injected core. The [native archive and IPA build also passed](https://github.com/coldlee-en/Tandem/actions/runs/40418548887);
signing, installation, and gameplay require separate device validation.
See [device acceptance checks](docs/DEVICE_TESTING.md) and
[the Switch integration details](docs/SWITCH_CORE.md).

## License

Tandem's new source is licensed under AGPL-3.0-or-later; see [LICENSE](LICENSE).
Upstream sources retain their own notices. Cytrus declares GPLv3 and contains
GPLv2-or-later Azahar/Citra code. The pinned MeloNX fork declares AGPLv3-or-later;
its license file also records its earlier license and Ryujinx's MIT lineage.
See [third-party notes](docs/THIRD_PARTY.md) and [LICENSES](LICENSES).
