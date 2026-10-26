# Validation performed

Executed in the Linux workspace on 2026-10-26:

| Check | Result |
| --- | --- |
| EmulationKit build and XCTest suite, official Swift 6.2.3 Linux toolchain | **16 passed, 0 failures** |
| Real upstream Cytrus patch against fresh files from pinned Git revision | Applied successfully; second application byte-identical |
| Real upstream MeloNX patch against fresh files from pinned Git revision | Applied successfully; second application byte-identical |
| Native specification generation using isolated dependency fixtures | 3DS-only, Switch-only, and combined specs produced expected targets/dependencies; missing Vulkan headers rejected |
| Required Switch `dlsym` exports versus patched C# and source helper | All referenced exports present |
| `bash -n scripts/build_switch.sh scripts/prepare_3ds.sh` | Passed |
| Python compilation of setup/patch/generation scripts | Passed |
| App Info.plist parse | Passed |
| Swift frontend parse of all 16 app/test Swift files | Passed, no diagnostics |
| Non-UI logic typecheck against temporary Linux platform shims | Passed after correcting an explicit-self capture in the Switch event callback; this does not validate Apple APIs |
| IPA packaging/rejection unit tests | 12 passed; fixtures are structural parser tests, not compiled applications |
| Static website browser checks | Index/build pages passed at 390, 768, and 1440px; no overflow, internal-anchor or JavaScript errors |
| Pinned graphics headers | Downloaded and assembled successfully from the reviewed commits |
| Native FFmpeg header compatibility | Actual Cytrus FFmpeg header compiled with bundled framework headers |
| GitHub publishing attempt | Blocked before changes by HTTP 401 Bad credentials |
| GitHub connection restored | Authenticated as coldlee-en; creating a repository was then denied with HTTP 403 Resource not accessible by integration |
| Local IPA build attempt | Correctly refused Linux; no Xcode or iPhoneOS SDK is present |

The file tests use temporary synthetic bytes as imported files, not runnable ROMs.
They validate storage behavior; they do not test game compatibility.

Swift frontend parsing checks syntax without resolving the Apple frameworks;
it is **not** an iOS typecheck/build. The included macOS workflow builds the iOS interface
test bundle but has not executed in this environment.

Still unverified: iOS app/helper compilation, linking either native core, signing,
device JIT behavior, firmware installation, graphics/audio/input during gameplay,
saving, title compatibility, performance, memory limits, and physical-device
lifecycle checks. The four iOS session tests are authored but require an iOS
simulator to execute. Follow DEVICE_TESTING.md before preparing a release.
