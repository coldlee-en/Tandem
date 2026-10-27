# Tandem 1.0: 3DS release plan

Target: Tuesday, November 3, 2026, for a finished sideloadable 3DS app. This is a target, not a guaranteed release date. App Store submission and approval are not required for this milestone. Distribution still requires a suitable signing method, physical-device testing, and license compliance.

## Product scope

Ship one 3DS-focused iOS app with a polished library and player. Preserve existing imported game files and saves when upgrading; do not delete or silently migrate existing Switch data. The 3DS app should not import, display as playable, or embed Switch emulation. Confirm the build and packaging pipeline actually excludes Switch binaries and dependencies rather than only hiding the interface.

- Reliable decrypted and supported encrypted 3DS game loading, normal in-game saves, controller input, pause/resume, and repeat launches.
- Library: extract game titles/icons where possible; allow manual artwork, favorites, and collections; handle missing metadata gracefully.
- Player: configurable screen arrangements, screen size, touch-control position and opacity, and independent portrait/landscape settings.
- External controllers: persistent profiles, per-game selection, and a readable setup flow. Keep existing remapping and stick swap.
- Save states: safe slots, explicit save/load, compatibility handling, and protection against corruption. Rewind requires a bounded history, memory/performance limits, and a reliable save-state implementation.
- Backup and sync: export/import local saves and settings first; add iCloud sync with clear status and conflict handling after entitlements and device testing are available. Do not upload ROMs or keys by default.
- Accessibility: support Dynamic Type where practical, VoiceOver labels and controls, usable contrast, larger touch targets, and alternatives to motion controls where the core permits.
- Design: consistent light/dark themes, legible typography, responsive layouts, accessible settings, and a polished player and library.
- Monetization: keep all planned features available for the finished sideloadable release. A paid edition and its purchase infrastructure can be evaluated separately if the user decides to pursue them later.

## Work sequence (America/Chicago)

| Date | Outcome and decision gate |
| --- | --- |
| Oct 27 | Inventory the current app, dependencies, data layout, native build, and distribution requirements; establish 3DS-only architecture and a device test matrix. |
| Oct 28 | Produce the 3DS-only build without deleting existing data; audit the JIT/interpreter path and native dependency licenses; verify load, save, exit, and relaunch on a real device. |
| Oct 29 | Implement library improvements and refreshed navigation; test metadata fallback, favorites, collections, imports, and migration. |
| Oct 30 | Implement player layout and input customization; test portrait/landscape, accessibility, and controller behavior on device. |
| Oct 31 | Implement and test save-state support; evaluate rewind against memory use and compatibility. Begin safe backup/export. |
| Nov 1 | Implement and test backup and eligible iCloud sync, including offline use and conflict handling. Exercise upgrade and restore flows. |
| Nov 2 | Feature freeze and regression testing; fix release blockers, check licenses, update documentation, and prepare release notes and installation instructions. |
| Nov 3 | Publish v1.0.0 only if the gates below pass; otherwise publish a clearly labeled development build and reschedule the affected features or 1.0. |

These items are interdependent and may exceed one week. Run implementation work in parallel where safe, but do not treat a scheduled date as evidence that a feature works.

## Release gates

1. Automated package, simulator, and native archive checks pass for the exact release commit; publish each development version per the existing release workflow.
2. Real-device tests cover several independently owned 3DS titles and both first and repeat launches, regular saves, app backgrounding, touchscreen, controller disconnect/reconnect, and orientation changes. Record device/iOS versions, frame pacing, audio, memory, and known issues.
3. Save states and rewind survive interruption, reject incompatible/corrupt data safely, and do not damage normal saves. Sync never silently overwrites divergent saves; backup/restore is validated on two devices if sync is included.
4. Migration preserves existing data and offers a recovery route; a 3DS-only upgrade does not delete existing Switch content.
5. Accessibility checks cover Dynamic Type, VoiceOver, contrast, touch targets, and navigation in every supported orientation.
6. Confirm each included core/dependency license and corresponding source/notices obligations for the planned distribution.
7. Verify signing and installation instructions on a real device. If iCloud sync is included, verify the necessary account configuration and entitlements on real devices; otherwise clearly mark it incomplete.

## Existing foundations and open questions

Themes and controller button remapping exist in the current development app. User reports that Ocarina of Time 3D ran on a device; wider gameplay compatibility, restart behavior, and the new settings need further device verification. The current native release includes both cores, while the current 3DS interpreter path avoids requiring JIT. These facts are a starting point, not release certification.
