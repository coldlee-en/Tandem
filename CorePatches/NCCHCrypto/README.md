# Encrypted NCCH support

`changes.json` is a checked port of the NCCH decryption paths from the
[Citra/Lime3DS loader at 7a5e1de441f51e992816b59c561f7dfd849093a9](https://github.com/Lime3DS/Lime3DS/tree/7a5e1de441f51e992816b59c561f7dfd849093a9),
before encrypted-game support was removed. The affected upstream files retain
their Citra/Azahar copyright and GPLv2-or-later notices.

The port adapts primary/secondary key selection, seeded KeyY generation, and
NCCH version 0/1/2 CTRs to Cytrus's newer IOFile/SubIOFile interface. ExeFS is
decrypted before decompression; RomFS is decrypted on demand, including cached
and uncached reads. Encrypted extended headers and ExeFS sections are verified
before use. System fixed-key NCCH is explicitly unsupported.

No console keys are included or downloaded. Settings imports console-supplied
Citra-style AES text into `Tandem/System/3DS/system_data/keys.txt` with an `:AES`
section. Required entries are `generatorConstant` and `slot0x2CKeyX`; later
crypto methods can require `slot0x25KeyX`, `slot0x18KeyX`, or `slot0x1BKeyX`.
Seeded games also require a console-supplied `seeddb.bin`. Key values are never
included in import errors or AES parse-error logs.

This restores cartridge NCSD/NCCH decryption, not installation of encrypted
CIA archives. Ocarina of Time 3D gameplay still requires physical-device
verification with matching console keys and the user's own dump.
