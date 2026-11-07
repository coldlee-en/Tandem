# Library collections and game details

Choose Collections in the library to create a named collection. Open it to rename it or choose games with the membership toggles. Games can belong to multiple collections, and collection filters work with library search.

Use the visible ellipsis button beside a game title to open its details. Details include Play, Favorites, collection membership, imported-file information, and cover-image controls. Tapping a cover still starts the game directly. Play from the details menu closes that sheet before opening the player.

Removing a game from a collection does not remove it from the library. Deleting a collection removes only its name and memberships. Removing a game from the library remains a separate, confirmed action that removes the imported game file and cover; in-game saves and save states stay on the device.

Collection information is stored separately from game files and the library index. If it cannot be read, it is preserved and collection editing is disabled until the user explicitly confirms a reset in Collections. Resetting collections does not reset favorites, game files, or saves.

Collections are local to this app installation. Reimported games have new library identifiers and must be assigned again. Missing or removed game entries are excluded from displayed collection counts.

## Testing

Automated tests cover collection serialization, names and duplicates, memberships in multiple collections, deleting a collection while preserving the game file, preference persistence, failed edits, and preserving corrupt metadata until explicit reset. Device testing should cover creating, renaming, filtering, changing memberships, artwork management, launching from details, and reopening the app.

## Previous device testing

The user reported that v0.4.0 worked on their phone. That report is recorded without assigning a broader compatibility result or assuming additional device details. The new collection and game-details flows remain to be checked on a phone.
