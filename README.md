# Tandem

Tandem is an iOS emulator project with a local game library, touch controls, and controller support. The project is moving toward a polished **3DS-focused 1.0**; the current development release still includes both 3DS and experimental Switch integrations. iOS 17 or later is required.

## Download

Get the latest development build from [GitHub Releases](https://github.com/coldlee-en/Tandem/releases). The current release is [v0.1.6](https://github.com/coldlee-en/Tandem/releases/tag/v0.1.6), including `tandemv0.1.6.ipa`. The IPA is unsigned: re-sign it and its embedded code before sideloading. See [IPA packaging and signing](docs/IPA.md).

One 3DS game has been reported working on a physical device. Broader compatibility, performance, and the latest changes still need device testing. Switch support in the current build requires a JIT-capable development environment and remains experimental.

## Features today

- Import supported games from Files into a searchable local library. Choose cover images, mark favorites, and return to a recently played game.
- Emerald styling with dark, light, and system appearance options.
- Dual-screen 3DS display, touch controls, analog sticks, and compatible Bluetooth controllers. Remap controller buttons and swap sticks in Settings.
- Background pause and session controls. Existing game files and saves remain on your device.
- Cytrus/Azahar 3DS integration with interpreter support, and an experimental MeloNX/Ryujinx Switch integration in the current native build.

For encrypted 3DS games, import your own console's AES keys in Settings; some titles also require a seed database. Decrypted games do not necessarily need those files. See [3DS encryption setup](docs/3DS_ENCRYPTION.md). No games, keys, or firmware are included.

## Direction for 1.0

The target is a finished, sideloadable **3DS-only** app, with a more polished library and player. Planned work includes save states and rewind, configurable screen and touch layouts, library collections, controller profiles, backups and sync, and accessibility improvements. These are **planned, not yet available**. The 3DS-only build must preserve existing user data, including any Switch data from earlier versions. See the [1.0 release plan](docs/V1_RELEASE_PLAN.md).

## Build

See [the build guide](docs/BUILDING.md) for the complete commands and requirements.
For unsigned IPA packaging and the macOS workflow, see [IPA.md](docs/IPA.md).
The current website is hosted with ChatGPT Sites. See
[GitHub publication](docs/GITHUB.md) for repository and build automation.
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

Choose an installed simulator. Simulator tests exercise the interface and session lifecycle using test cores; they do not verify native gameplay. See [device acceptance checks](docs/DEVICE_TESTING.md) and the [GitHub Actions results](https://github.com/coldlee-en/Tandem/actions).

## License

Tandem's new source is licensed under AGPL-3.0-or-later; see [LICENSE](LICENSE).
Upstream sources retain their own notices. Cytrus declares GPLv3 and contains
GPLv2-or-later Azahar/Citra code. The pinned MeloNX fork declares AGPLv3-or-later;
its license file also records its earlier license and Ryujinx's MIT lineage.
See [third-party notes](docs/THIRD_PARTY.md) and [LICENSES](LICENSES).
