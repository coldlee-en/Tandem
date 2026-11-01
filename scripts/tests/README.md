# Core regression harnesses

These historical harnesses are retained for reference. Gameplay testing is currently performed manually.

## 3DS restart regression harness

Run `python3 scripts/tests/run_cytrus_restart.py /path/to/patched/Cytrus` with a
C++20 compiler. It compiles the patched bridge start and stop methods and core
shutdown signal cleanup against lightweight stubs. It checks 1,000 immediate
start/stop cycles and cleanup of a pending shutdown signal. It does not exercise
graphics, guest execution, or physical-device gameplay.

## Encrypted 3DS regression harness

With an installed Crypto++ development library and C++23 compiler:

```sh
python3 scripts/tests/run_ncch_crypto.py /path/to/patched/Cytrus \
  --cryptopp-include /path/to/cryptopp/include \
  --cryptopp-library /path/to/libcryptopp.a
```

This extracts the actual patched NCCH header layouts, loader methods, LZSS
decoder, RomFS read/cache methods, and AES arithmetic from the supplied checkout.
OS file access, key provisioning, and unrelated application services use test
scaffolding. Fixture encryption uses an independent integer key-scrambler
formulation and synthetic data; no console keys or copyrighted games are used.

Seventeen fixture combinations cover NCCH versions 0/1/2, the four secondary-key
methods, seed crypto, plaintext, NCSD partition offsets, and compressed executable
decryption. Each fixture checks 80 RomFS read ranges across cache hits/misses,
unaligned offsets, uncached reads, and EOF. Additional cases reject missing or
incorrect keys/seeds and unknown crypto methods, and allow plaintext without keys. It also checks a verified plaintext dump
with an incorrect encrypted flag and rejects a tampered plaintext header.
Compilation enables AddressSanitizer and UndefinedBehaviorSanitizer. Compilation
and execution are bounded at 120 and 30 seconds respectively.

These tests validate decryption and loading of synthetic containers. They do not
establish physical-device gameplay or compatibility with a particular game dump.

## Save-state regression checks

Run against the patched Cytrus checkout:

```sh
python3 scripts/tests/run_save_state_bridge.py /path/to/patched/Cytrus
python3 scripts/tests/run_save_state_writer.py /path/to/patched/Cytrus
```

Both compile extracted native methods with a C++20 compiler. The bridge harness
checks requests while paused, worker thread affinity, invalid and incompatible
slots, busy filesystem operations, failed writes, and stopped sessions. The
writer harness uses the actual SaveState method with stub serialization and
compression to verify that write, flush, and rename failures preserve the old
slot. Neither harness establishes retail-game serialization or iOS gameplay.
