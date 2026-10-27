# Encrypted 3DS cartridges

Tandem 0.1.1 added encrypted NCSD/NCCH loading for supported `.3ds`, `.cci`, and
`.cxi` files. Decrypted games remain supported. Import your own console's keys
locally in Settings; Tandem does not include or download console keys.

## Setup

1. Install the updated unsigned IPA using your existing re-signing/sideloading
   setup.
2. Close any active game and open **Settings → Import 3DS AES keys**.
3. Select your Citra-compatible AES keys text file. Both plain AES entries and
   a sectioned file containing `:AES` are accepted. Import validation checks the
   text format; loading a game verifies that the keys actually match.
4. For a seed-encrypted title, use **Import 3DS seed database** to import your
   `seeddb.bin`. Older titles such as the original Ocarina of Time 3D release
   normally use the original NCCH key method without seed crypto.
5. Launch your existing imported cartridge. Keys are reloaded before each load;
   the ROM file is not overwritten or decrypted to disk.

Required AES entries are `generatorConstant` and `slot0x2CKeyX`. The key generator
constant is an input to the key-scrambling algorithm. Later NCCH methods can
additionally require `slot0x25KeyX`, `slot0x18KeyX`, or `slot0x1BKeyX`. Every value
must contain exactly 32 hexadecimal characters. These are 3DS AES entries;
the separate Switch keys importer does not configure 3DS decryption.

Version 0.1.2 fixes the import location and automatically copies earlier keys and seeds when needed, without replacing files already in the correct directory.

The importer normalizes entries into `Tandem/System/3DS/system_data/keys.txt`, using
the core's `:AES` section format, and stores seeds alongside it as `seeddb.bin`.
It imports only NCCH AES entries. Key values stay on the device and are omitted
from import errors and AES parsing logs. Keep existing console data backed up
before replacing it with another file.

## Errors and limits

Missing keys, missing title seeds, unsupported crypto methods, and failed
decrypted-header/section verification produce a loading error. The log at
`Tandem/System/3DS/log/cytrus_log.txt` distinguishes these cases. In the older
build, loader error 8 meant `ErrorEncrypted`; the new error text points to the
3DS key/seed import flow.

This feature covers cartridge NCSD/NCCH decryption. It does not add encrypted
CIA installation or support system fixed-key NCCH content. It does not grant JIT.
Synthetic encrypted-container tests and compilation do not establish physical
device gameplay or compatibility with every title or dump.

See [the checked core port](../CorePatches/NCCHCrypto/README.md) and
[the native regression harness](../scripts/tests/README.md) for provenance and
test scope.
