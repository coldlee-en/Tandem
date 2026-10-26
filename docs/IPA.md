# Building an IPA

An IPA requires a real iOS device build from Xcode on macOS. This repository's
Linux development environment cannot compile that application. The scripts do
not create a placeholder IPA when the compiler or native dependencies are
unavailable.

## Available development artifact

[Native build 40418548887 succeeded](https://github.com/coldlee-en/Tandem/actions/runs/40418548887)
at source `8d34fae`. Download the
[unsigned native IPA artifact](https://github.com/coldlee-en/Tandem/actions/runs/40418548887/artifacts/12696757979)
from Actions. The artifact ZIP contains the IPA and a manifest with its SHA-256; GitHub
sign-in may be required, and Actions retention limits apply. This is an Actions
artifact. Version 0.1.1 is also published at
https://github.com/coldlee-en/Tandem/releases/tag/v0.1.1 with the IPA, manifest, and checksum.

Verified IPA SHA-256:

```text
ca44acd38c767e841f8d80e4bf6fa4787276b1d2930883bd75f5ce460e257f0f
```

All 21 packaged Mach-O images have minimum deployment versions at or below
iOS 17, and the bundled dependency-closure check passed. The app and embedded
native code still require re-signing before sideloading. Device gameplay and
JIT behavior remain unverified; Switch requires working JIT after installation.

## Native build

Install Xcode 26 or later with the iPhoneOS SDK, XcodeGen, Python 3, Git/Git LFS,
and a .NET 8 SDK on the Mac. Native preparation fetches the pinned graphics
headers automatically into `Vendor/GraphicsHeaders/include`; a separate Vulkan
SDK installation is not required. To use an existing compatible SDK instead,
set `TANDEM_VULKAN_INCLUDE` to its `macOS/include` directory before running.

```sh
bash scripts/build_ipa.sh --native --output dist/ipa
```

Native is the default mode. It prepares the pinned Cytrus source, builds the
MeloNX NativeAOT core, generates the native Xcode project, and archives the
`Tandem` scheme in Release configuration for `generic/platform=iOS`.
The Xcode invocation explicitly sets `CODE_SIGNING_ALLOWED=NO` and
`CODE_SIGNING_REQUIRED=NO`; no Apple account, certificate, or provisioning
profile is requested.

After a successful archive, the script validates and packages
`Tandem.xcarchive/Products/Applications/Tandem.app`. It requires an arm64 iOS
Mach-O executable and the native runtime libraries. A failed compiler, linker,
core build, or validation step stops the script before producing a new IPA.

Outputs:

- `dist/ipa/Tandem-native-unsigned.ipa`
- `dist/ipa/Tandem-native-unsigned.manifest.json`
- A `dist/ipa/build-native-*` directory containing the actual Xcode archive,
  DerivedData, and `xcodebuild.log`.

The manifest records build mode, source revision, SHA-256, bundle/version
information, platform, and unsigned status. CI supplies `GITHUB_SHA`; a local
Git checkout uses its HEAD revision. A source archive without Git metadata is
identified as `unversioned-source`.

## GitHub Actions

The repository includes the manually triggered
[Build unsigned IPA workflow](../.github/workflows/build-ipa.yml). In the
repository's **Actions** tab, select **Build unsigned IPA**, choose **Run
workflow**, and keep **mode: native** to include both emulator integrations.
The explicit **interface** choice produces the interface-only artifact described
below.

The workflow uses a `macos-15` runner, selects an installed Xcode 26 or later,
sets up Python and .NET 8, installs XcodeGen/Git LFS, tests the local library,
and calls `build_ipa.sh`. No signing secrets are required. The native job also
needs public upstream package, source, and Git LFS downloads to succeed; a
missing package or native compiler error fails the job rather than producing
an interface artifact under the native name.

After a successful run, download **Tandem-native-unsigned-IPA** from the run's
Artifacts section. It contains the IPA and build manifest. Build diagnostics
are uploaded separately as **Tandem-native-build-logs**. IPA artifacts are
retained for 14 days, and diagnostics for 7 days. A successful Actions run
establishes compilation and packaging; device installation and gameplay remain
separate checks. The successful native build linked above produced a real
unsigned IPA; future runs produce an artifact only after their own checks pass.

## Interface build

This explicit option compiles the native iOS interface without emulator cores:

```sh
bash scripts/build_ipa.sh --interface --output dist/ipa
```

It produces `Tandem-interface-unsigned.ipa` and the corresponding manifest.
This artifact supports interface testing and cannot run games. Its filename
and manifest identify it separately from the native emulator integration.

## Installation

The unsigned IPA is **not directly installable**. A compatible sideloading
workflow must re-sign the app and all embedded frameworks/libraries for the
destination device. Existing upstream library signatures may be present inside
an unsigned archive and must also be replaced. The build scripts do not claim
that an unsigned artifact has been installed or accepted by iOS.

Switch still requires a suitable JIT-enabled process after installation.
Successful compilation does not establish game compatibility or usable
performance. Device validation is tracked separately in
[DEVICE_TESTING.md](DEVICE_TESTING.md).

## Packaging checks

`scripts/package_ipa.py` packages only an existing `.app`; it is not a compiler.
It checks the bundle metadata, device architecture/platform, executable load
commands, required native libraries, permissions, and symlink containment.
The ZIP contains `Payload/Tandem.app` and preserves contained framework symlinks
and Unix permissions.

Run its structural unit tests on any Python 3 host:

```sh
python3 scripts/package_ipa.py --self-test
```

These tests use explicitly synthetic Mach-O parser fixtures. They verify the
packager's rejection and ZIP behavior; they do not constitute an iOS build or
gameplay test.

## Automatic releases

Changing the version/build in `project.yml` on main starts the native build.
The build reserves its version tag, and a successful native build triggers
`release.yml`, which validates its source, bundle metadata, and SHA-256 before
publishing an unsigned prerelease with all three assets. Published versions
are immutable; bump the version for changed source/binaries. The release
workflow also supports a successful build run ID for backfilling an artifact.
