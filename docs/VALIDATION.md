# Validation performed

Current evidence as of 2026-10-26:

| macOS CI check | Result |
| --- | --- |
| EmulationKit library tests | **23 passed** |
| iOS interface compilation and simulator session tests | Passed in [Validate](https://github.com/coldlee-en/Tandem/actions/runs/40418548684); all **4 session-lifecycle tests executed, 0 failures**, plus 23 library and key import tests |
| Switch NativeAOT runtime | Compiled for iOS arm64; cached artifact verified |
| Cytrus static archive | `libCytrus.a` compiled in [native build](https://github.com/coldlee-en/Tandem/actions/runs/40405335353) |
| Final native app archive and IPA | [Build 40418548887 passed](https://github.com/coldlee-en/Tandem/actions/runs/40418548887) at source `8d34fae`; [unsigned native artifact](https://github.com/coldlee-en/Tandem/actions/runs/40418548887/artifacts/12696757979) downloaded and checksum verified |
| Packaged Mach-O inspection | All 21 images have deployment minimums at or below iOS 17; bundled dependency-closure check passed |

Native IPA SHA-256:
`ca44acd38c767e841f8d80e4bf6fa4787276b1d2930883bd75f5ce460e257f0f`.

Additional checks performed in the Linux workspace:

| Check | Result |
| --- | --- |
| EmulationKit build and XCTest suite, official Swift 6.2.3 Linux toolchain | **16 passed, 0 failures** |
| Real upstream Cytrus patch against fresh files from pinned Git revision | Applied successfully; second application byte-identical |
| Real upstream MeloNX patch against fresh files from pinned Git revision | Applied successfully; second application byte-identical |
| Native specification generation using isolated dependency fixtures | 3DS-only, Switch-only, and combined specs produced expected targets/dependencies; missing Vulkan headers rejected |
| Required Switch `dlsym` exports versus patched C# and source helper | All referenced exports present |
| [Switch native lifecycle regression harness](../scripts/tests/README.md) | **5 groups passed**, including 300 concurrent start/stop races; actual lifecycle methods compiled with graphics/SDL stubs, without gameplay |
| `bash -n scripts/build_switch.sh scripts/prepare_3ds.sh` | Passed |
| Python compilation of setup/patch/generation scripts | Passed |
| App Info.plist parse | Passed |
| Swift frontend parse of all 23 app/test Swift files | Passed, no diagnostics |
| Non-UI logic typecheck against temporary Linux platform shims | Passed after correcting an explicit-self capture in the Switch event callback; this does not validate Apple APIs |
| IPA packaging/rejection unit tests | 14 passed; fixtures are structural parser tests, not compiled applications |
| Static website browser checks | Index/build pages passed at 390, 768, and 1440px; no overflow, internal-anchor or JavaScript errors |
| Pinned graphics headers | Downloaded and assembled successfully from the reviewed commits |
| Native FFmpeg header compatibility | Actual Cytrus FFmpeg header compiled with bundled framework headers |
| Local IPA build attempt | Correctly refused Linux; no Xcode or iPhoneOS SDK is present |

The file tests use temporary synthetic bytes as imported files, not runnable ROMs.
They validate storage behavior; they do not test game compatibility.

Linux Swift parsing and platform shims do not validate Apple APIs; the separate
macOS CI result establishes interface compilation and successful execution of all
4 session-lifecycle tests in the iOS simulator. Those tests use an injected core;
they do not run the native emulator cores.

The IPA is an unsigned development artifact. Re-signing, device installation, JIT,
firmware installation, graphics/audio/input during gameplay, saving, title
compatibility, performance, memory limits, and physical-device lifecycle behavior
remain unverified. Static deployment/dependency checks do not establish runtime
compatibility. Follow [DEVICE_TESTING.md](DEVICE_TESTING.md) for device validation.

## Encrypted 3DS loader (0.1.1)

The native build includes the restored NCCH/NCSD decryption paths and the new
3DS key/seed Settings imports. All 23 library/key-import tests and four simulator
session tests passed. Seventeen synthetic-container fixture combinations passed
under AddressSanitizer and UndefinedBehaviorSanitizer, covering versions 0/1/2,
four crypto methods, seeds, compressed ExeFS code, NCSD offsets, and cached and
uncached RomFS reads. Missing/wrong keys and seeds were rejected. Both modified
loader files passed independent C++23 syntax checks. Checked patches remained
byte-identical after marker deletion and reapplication.

The downloaded IPA is version 0.1.1, build 2; its ZIP CRC, manifest checksum,
new Settings labels, and all 21 embedded device binaries were verified. No
console keys or game content were used in these tests. Ocarina of Time 3D
gameplay with a real console dump remains unverified.
