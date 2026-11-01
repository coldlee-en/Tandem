# Save states

During a 3DS game, tap the tray icon in the player toolbar. The game pauses while the menu is open. Three slots are shared by copies of the same game title, using the core's title ID. Each occupied slot shows the date and time recorded in the state itself.

Save captures the current emulation state; saving over an occupied slot requires confirmation. Load restores a compatible state and discards current unsaved progress. Close the menu and tap Resume when ready. Normal in-game saves remain separate and should still be used regularly.

States live in the core's `Tandem/System/3DS/states` directory. Writes go to a temporary file and replace the old slot only after a successful write, flush, and close. A stale temporary file is not listed as a slot. The native core validates game identity and its revision before loading. Future core changes may make a state incompatible; an incompatible state can be replaced by saving to its slot.

The bridge executes requests on the emulation worker even while paused and rejects operations when asynchronous game filesystem work is pending. Resume briefly and retry that case. Unsupported game loaders may reject saving. A failure during deserialization ends the native session rather than continuing with potentially inconsistent emulated memory.

Automated checks cover the real bridge control flow with stub core dependencies, session pause/error behavior, patch application, and native compilation. They do not establish successful save/load gameplay for a retail game on a physical device.
