#!/usr/bin/env python3
"""Reject a native archive with missing dynamic core/helper entry points."""
from __future__ import annotations

import argparse
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HELPER_EXPORTS = {
    "TandemRegisterEventCallback", "TriggerCallback", "TriggerCallbackWithData",
    "showKeyboardAlert", "showAlert", "getKeyboardInput", "clearKeyboardInput",
}


class ExportError(ValueError):
    pass


def required_core_exports(source: Path) -> set[str]:
    # Match the exact native names used by this checkout's Swift adapter rather
    # than silently accepting a stale hand-maintained API list.
    symbols = set(re.findall(r'symbol\("([A-Za-z0-9_-]+)",\s*from:\s*handle\b', source.read_text()))
    if not {"tandem_initialize", "tandem_initialize_jit", "main_ryujinx_sdl"}.issubset(symbols):
        raise ExportError("Cannot determine the required Switch exports from SwitchCore.swift")
    return symbols


def parse_nm_names(output: str) -> set[str]:
    symbols = set()
    for line in output.splitlines():
        name = line.strip()
        if re.fullmatch(r"[_A-Za-z$][_A-Za-z0-9$@.\-]*", name):
            # Mach-O prepends one underscore to a C external symbol.
            symbols.add(name[1:] if name.startswith("_") else name)
    return symbols


def defined_exports(binary: Path) -> set[str]:
    if not binary.is_file():
        raise ExportError(f"Missing archived native binary: {binary}")
    result = subprocess.run(
        ["xcrun", "nm", "-arch", "arm64", "-g", "-U", "-j", str(binary)],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise ExportError(f"Cannot inspect native exports in {binary.name}: {result.stderr.strip()}")
    return parse_nm_names(result.stdout)


def check_exports(binary: Path, required: set[str], actual: set[str]):
    missing = required - actual
    if missing:
        raise ExportError(f"{binary.name} is missing required exported symbols: {', '.join(sorted(missing))}")


def verify(app: Path, reader=defined_exports):
    core = app / "Frameworks/Ryujinx.Headless.SDL2.dylib"
    helper = app / "Frameworks/RyujinxHelper.framework/RyujinxHelper"
    required = required_core_exports(ROOT / "App/Emulation/SwitchCore.swift")
    for binary, symbols in [(core, required), (helper, HELPER_EXPORTS)]:
        if not binary.is_file():
            raise ExportError(f"Missing archived native binary: {binary}")
        check_exports(binary, symbols, reader(binary))
        print(f"Verified {len(symbols)} required dynamic exports in {binary.name}")


class ExportTests(unittest.TestCase):
    """Mocked nm output checks rejection behavior; it does not compile iOS code."""

    def test_names_only_macho_output(self):
        self.assertEqual(parse_nm_names("_TriggerCallback\n_tandem_initialize\n/path (arm64):\n"),
                         {"TriggerCallback", "tandem_initialize"})

    def test_undefined_or_addressed_rows_are_not_treated_as_exports(self):
        self.assertEqual(parse_nm_names("                 U _showAlert\n00000123 T _showAlert\n"), set())

    def test_missing_export_rejected(self):
        with self.assertRaisesRegex(ExportError, "showAlert"):
            check_exports(Path("RyujinxHelper"), HELPER_EXPORTS, HELPER_EXPORTS - {"showAlert"})

    def test_current_adapter_exports_are_read(self):
        names = required_core_exports(ROOT / "App/Emulation/SwitchCore.swift")
        self.assertTrue({"install_firmware", "free_firmware_version", "touch_began", "set_view_size"}.issubset(names))
        self.assertNotIn("TandemRegisterEventCallback", names)

    def test_archive_with_hidden_helper_export_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="tandem-export-test-") as directory:
            app = Path(directory) / "Fixture.app"
            core = app / "Frameworks/Ryujinx.Headless.SDL2.dylib"
            helper = app / "Frameworks/RyujinxHelper.framework/RyujinxHelper"
            core.parent.mkdir(parents=True)
            helper.parent.mkdir(parents=True)
            core.write_text("mock symbol-reader input, not a compiled binary")
            helper.write_text("mock symbol-reader input, not a compiled binary")
            exports = required_core_exports(ROOT / "App/Emulation/SwitchCore.swift")
            def read(binary):
                return exports if binary == core else HELPER_EXPORTS - {"TandemRegisterEventCallback"}
            with self.assertRaisesRegex(ExportError, "TandemRegisterEventCallback"):
                verify(app, reader=read)

    def test_missing_binary_rejected_before_inspection(self):
        with tempfile.TemporaryDirectory(prefix="tandem-export-test-") as directory:
            with self.assertRaisesRegex(ExportError, "Missing archived native binary"):
                verify(Path(directory) / "Missing.app")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ExportTests))
        return 0 if result.wasSuccessful() else 1
    if arguments.app is None:
        parser.error("--app is required unless --self-test is selected")
    if platform.system() != "Darwin":
        parser.exit(1, "error: Native iOS export verification requires macOS and Xcode's nm tool.\n")
    try:
        verify(arguments.app)
    except (ExportError, OSError) as error:
        parser.exit(1, f"error: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
