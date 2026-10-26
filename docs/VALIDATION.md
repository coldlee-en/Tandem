# Validation performed

Current evidence as of 2026-10-26:

| macOS CI check | Result |
| --- | --- |
| EmulationKit library tests | **16 passed** |
| iOS interface compilation and simulator session tests | Passed in [Validate](https://github.com/coldlee-en/Tandem/actions/runs/40408625904); all **4 session-lifecycle tests executed, 0 failures** |
| Switch NativeAOT runtime | Compiled for iOS arm64; cached artifact verified |
| Cytrus static archive | `libCytrus.a` compiled in [native build](https://github.com/coldlee-en/Tandem/actions/runs/40405335353) |
| Final native app archive and IPA | Pending; [corrected native build](https://github.com/coldlee-en/Tandem/actions/runs/40408070813) retries the final link after fixing raw-dylib search paths |

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
| Swift frontend parse of all 16 app/test Swift files | Passed, no diagnostics |
| Non-UI logic typecheck against temporary Linux platform shims | Passed after correcting an explicit-self capture in the Switch event callback; this does not validate Apple APIs |
| IPA packaging/rejection unit tests | 12 passed; fixtures are structural parser tests, not compiled applications |
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

No IPA is available. The final native app archive, signing, device JIT, firmware
installation, graphics/audio/input during gameplay, saving, title compatibility,
performance, memory limits, and physical-device lifecycle behavior remain
unverified. Follow [DEVICE_TESTING.md](DEVICE_TESTING.md) before preparing a release.
