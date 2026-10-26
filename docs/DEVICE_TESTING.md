# Device verification

**Status: none of the device checks below have run.** The development workspace is Linux and has no iOS SDK, signing tools, or attached iPhone/iPad. These are acceptance checks, not reported results. Passing package tests or source parsing does not establish that an emulator core builds, renders, produces audio, or runs a game on iOS.

Record the Git revision, Xcode version, iOS version, device model, core revisions, signing method, and whether a debugger/JIT is active for each run. Use a homebrew input-test program or another known-good test image with visible input and touch feedback. Retain device logs and a short screen recording for failures.

## Builds to exercise

- [ ] Build the app with no optional cores linked. Open Settings and confirm each unavailable core has an explanation. Importing a game must remain possible; attempting to play must show a useful error without claiming emulation has started.
- [ ] Build with the pinned and patched Cytrus framework. Verify a development build installs and opens on a physical arm64 device.
- [ ] Build with the Switch core and its required native dependencies. Verify the framework actually links and loads before assessing Switch behavior.
- [ ] Test one small iPhone and one iPad where available, including portrait and both landscape orientations.

## Library, persistence, and source files

- [ ] Import a small `.3dsx` and `.nro` through Files. Confirm each title, system, and file size appears correctly. Uppercase extensions must behave the same way.
- [ ] Import from both local storage and a downloaded iCloud Drive file. Confirm the app finishes copying before launch and does not require the source location to remain accessible.
- [ ] Import several files at once. Include an unsupported file among valid files. Valid imports must remain in the library, and the error must name the failed file.
- [ ] Cancel the file picker. Confirm no row or partial game is added.
- [ ] Force-quit after a completed import, reopen, and confirm the library remains intact. Launch a game successfully, reopen again, and confirm its last-played date persists.
- [ ] Rename or move the original source after import. Launch the managed copy successfully.
- [ ] Delete a game through the library. Relaunch the app and confirm its row and managed ROM copy are gone. Open the original source in Files and confirm its name, size, and contents are unchanged.
- [ ] Import two different files with the same name. Delete one entry and confirm the other remains playable; storage must use independent identifiers.
- [ ] Delete or move an app-managed game using Files, then attempt to play its row. Expect a missing-file error and a usable library; deleting the stale row must work.
- [ ] Fill storage enough to make an import fail, using a disposable test device or app container. Expect an actionable error, no successful row for that import, and no damage to earlier games or the source file.

Import classification uses extensions; it does not validate a console executable at import time. A nonempty corrupt file with a recognized extension can appear in the library and must fail safely when the core tries to load it. CIA archives are not direct-boot imports.

## Touch controls and simultaneous input

- [ ] Hold a direction and a face button with different fingers. Confirm both remain pressed until each finger is released independently.
- [ ] Hold an analog stick, a face button, and a shoulder button together. Confirm diagonal input and simultaneous buttons reach the test program.
- [ ] Drag outside a button and release, then test that button again. Confirm no button remains stuck.
- [ ] Drag each stick through its full range. Confirm positive Y means up, diagonal magnitude stays within the expected range, and lifting the finger returns both axes to zero.
- [ ] Interrupt held controls with Control Center, a system gesture, a pause, and a rotation. On return, confirm released fingers do not leave buttons or axes active.
- [ ] Exercise VoiceOver activation of a button and confirm it produces a press followed by a release.

## Hardware controllers

Connect an extended gamepad before launch and repeat after launch. Use physical positions for face-button expectations; labels printed on Xbox and Nintendo pads differ.

| Physical input / GameController property | Emulator input |
| --- | --- |
| South / `buttonA` | B |
| East / `buttonB` | A |
| West / `buttonX` | Y |
| North / `buttonY` | X |
| D-pad directions | Matching direction |
| Left / right shoulder | L / R |
| Left / right trigger | ZL / ZR |
| Menu / Options | Plus (Start) / Minus (Select) |
| Home, if delivered by iOS | Home |
| Left / right stick click | Left / right stick click, where supported by the core |
| Left / right analog stick | Left / right analog stick; up is positive Y |

- [ ] Verify every available input against this table with visible input feedback. A missing optional controller button must not prevent the other inputs from working.
- [ ] Hold buttons and tilt both sticks, then disconnect the active gamepad. Confirm all held hardware buttons release and both axes return to zero.
- [ ] Reconnect repeatedly. A single physical press must cause one effective press, and callbacks from the prior connection must not reapply old input.
- [ ] Connect two pads. The first selected extended gamepad controls the session. Disconnect it and confirm the other connected pad takes over without a stuck button or axis.
- [ ] Repeat pause/resume with a held button and a displaced stick. After releasing and pressing again, confirm input works and no pre-pause input remains stuck.

## Session lifecycle and orientation

- [ ] Pause while the game is running. Confirm simulation and audio pause, held input releases, and controls cannot affect the paused game. Resume and confirm simulation, audio, and fresh input work.
- [ ] Background a running session, including locking the device. Confirm the session pauses and does not resume itself on return.
- [ ] Start a game and immediately background the app before native initialization finishes. On return, the session must be paused or show a clear startup error; it must not run unnoticed in the background.
- [ ] Start a game and immediately end the session. Confirm teardown waits for initialization, the app returns to the library, and it can start another session.
- [ ] Rotate while starting, running, paused, and stopping. Confirm controls fit within safe areas, layers resize without starting a second core instance, and the rendered image remains correctly proportioned.
- [ ] End a session and repeat launch/pause/stop at least ten times, alternating systems where both cores are available. Check for crashes, lingering audio, stale frames, controller callbacks into the old session, and steadily increasing memory.
- [ ] Confirm a failed startup can return to the library and start a known-good image without relaunching the app.

## Nintendo 3DS

- [ ] Launch known-good homebrew with visible output on both screens. Confirm the top display is 400:240 and the lower display is 320:240, with no cropping or swapped output.
- [ ] Touch all four lower-screen corners and its center. Confirm coordinates reach the corresponding test locations in portrait and landscape, including Retina scaling.
- [ ] Drag across the lower screen, then lift or interrupt the touch. Confirm the core receives the final release. The top display must not generate lower-screen touches.
- [ ] Use lower-screen touch while holding a face button and moving the analog pad. Confirm independent touch ownership.
- [ ] Test audio, in-game saving, stop, and relaunch. Confirm the core's save files persist independently of library metadata.
- [ ] Run a signed build without debugger/JIT, then repeat with debugger/JIT where supported. Record actual speed and correctness for each device; do not infer performance from successful launch.

## Nintendo Switch and JIT

- [ ] With the Switch core linked, open the app without an attached debugger or another working JIT mechanism. Attempt to launch a Switch image. Expect the explicit JIT-required error before native emulation starts; confirm the library remains usable.
- [ ] Enable JIT through the documented development workflow, relaunch, and verify the app detects the actual process state. The presence of a configuration option alone must not report JIT as active.
- [ ] Launch a known-good homebrew `.nro` on a physical device. Verify rendered output, audio, controls, pause/resume, and clean stop.
- [ ] Where the core requires system data for a title, test with that data missing first. Expect a useful loading error and successful teardown. Supply the required data through the documented local folder layout and retry.
- [ ] Rotate the Switch display. Confirm a 16:9 image, correct touch coordinates for a touch-capable test program, and zero input after touch cancellation.

## Errors and recovery

- [ ] Attempt a zero-byte file, an unsupported archive, and a CIA file. Each must be rejected without adding an entry.
- [ ] Attempt recognized-extension files containing truncated or invalid data. The core must return an error or otherwise fail visibly without leaving a permanent starting state, leaked audio, or an unusable library.
- [ ] Launch with an absent or incompatible framework. Confirm the availability/error message identifies the core problem rather than reporting the game as running.
- [ ] Inspect device logs after each failed launch and repeated teardown. Treat native crashes, hangs, invalid-layer warnings, and use-after-free reports as release blockers.

## Result record

For each check, record `PASS`, `FAIL`, or `NOT RUN`, together with the device/build identifiers and evidence. Record a blocked check as `NOT RUN` with its missing dependency. No row above is a pass until observed on the relevant device and core build.
