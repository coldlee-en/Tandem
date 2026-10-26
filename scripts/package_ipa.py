#!/usr/bin/env python3
"""Package an existing iOS device .app; this tool never compiles an application.

Run --self-test for structural validation and archive tests using explicitly
synthetic Mach-O fixtures. Those fixtures are not application build artifacts.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import tempfile
import unittest
import zipfile


class PackagingError(ValueError):
    pass


def validate_macho(path: Path, *, file_type: int = 2) -> dict:
    """Check an arm64 iOS Mach-O slice, including bounded load commands.

    This establishes executable format and target platform, not behavioral
    correctness or provenance. build_ipa.sh supplies the Xcode archive provenance.
    """
    if not path.is_file():
        raise PackagingError(f"Missing native binary: {path}")
    data = path.read_bytes()
    slice_start, slice_size = 0, len(data)
    if len(data) >= 8 and data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        fat64 = data[:4] == b"\xca\xfe\xba\xbf"
        count = struct.unpack_from(">I", data, 4)[0]
        entry_size = 32 if fat64 else 20
        if count < 1 or count > 64 or 8 + count * entry_size > len(data):
            raise PackagingError("Invalid universal Mach-O architecture table.")
        found = False
        for index in range(count):
            position = 8 + index * entry_size
            cpu = struct.unpack_from(">I", data, position)[0]
            offset, size = struct.unpack_from(">QQ" if fat64 else ">II", data, position + 8)
            if offset < 8 + count * entry_size or size < 32 or offset + size > len(data):
                raise PackagingError("A universal Mach-O slice lies outside its file.")
            if cpu == 0x0100000C and not found:
                slice_start, slice_size, found = offset, size, True
        if not found:
            raise PackagingError("The universal binary has no arm64 slice.")
    slice_end = slice_start + slice_size
    if slice_size < 32 or data[slice_start:slice_start + 4] != b"\xcf\xfa\xed\xfe":
        raise PackagingError("The binary is not a 64-bit arm64 Mach-O file.")
    header = struct.unpack_from("<8I", data, slice_start)
    _, cpu, _, actual_type, count, command_bytes, _, _ = header
    if cpu != 0x0100000C or actual_type != file_type:
        raise PackagingError("The binary has the wrong architecture or Mach-O file type.")
    commands_end = slice_start + 32 + command_bytes
    if count < 1 or count > 10000 or command_bytes < count * 8 or commands_end > slice_end:
        raise PackagingError("The Mach-O load-command table is invalid or truncated.")
    position = slice_start + 32
    ios_platform, text_segment, entry_point = False, False, False
    for _ in range(count):
        if position + 8 > commands_end:
            raise PackagingError("A Mach-O load command is truncated.")
        command, size = struct.unpack_from("<II", data, position)
        if size < 8 or size % 8 or position + size > commands_end:
            raise PackagingError("A Mach-O load command has invalid bounds.")
        if command == 0x19:  # LC_SEGMENT_64
            if size < 72:
                raise PackagingError("The Mach-O segment command is truncated.")
            segment = data[position + 8:position + 24].split(b"\0", 1)[0]
            file_offset, file_size = struct.unpack_from("<QQ", data, position + 40)
            if file_offset + file_size > slice_size:
                raise PackagingError("A Mach-O segment lies outside its slice.")
            if segment == b"__TEXT" and file_size > command_bytes + 32:
                text_segment = True
        elif command == 0x32:  # LC_BUILD_VERSION
            if size < 24:
                raise PackagingError("The Mach-O build-version command is truncated.")
            platform = struct.unpack_from("<I", data, position + 8)[0]
            if platform != 2:  # PLATFORM_IOS, excluding IOSSIMULATOR == 7
                raise PackagingError("The native binary targets a platform other than iOS devices.")
            ios_platform = True
        elif command == 0x25:  # LC_VERSION_MIN_IPHONEOS
            if size < 16:
                raise PackagingError("The Mach-O minimum-version command is truncated.")
            ios_platform = True
        elif command == 0x80000028:  # LC_MAIN
            if size < 24:
                raise PackagingError("The Mach-O entry-point command is truncated.")
            offset = struct.unpack_from("<Q", data, position + 8)[0]
            if offset < 32 + command_bytes or offset >= slice_size:
                raise PackagingError("The Mach-O entry point lies outside executable content.")
            entry_point = True
        position += size
    if position != commands_end or not ios_platform or not text_segment:
        raise PackagingError("The binary has no complete iOS executable text/load-command layout.")
    if file_type == 2 and not entry_point:
        raise PackagingError("The device executable has no LC_MAIN entry point.")
    return {"architecture": "arm64", "platform": "iOS", "file_type": actual_type}


def app_entries(app: Path) -> list[Path]:
    """Enumerate without traversing symlink directories; reject escaping links."""
    root = app.resolve(strict=True)
    entries = [root]
    def walk_error(error):
        raise error

    for current, directories, files in os.walk(root, followlinks=False, onerror=walk_error):
        for name in sorted(directories + files):
            entry = Path(current) / name
            mode = entry.lstat().st_mode
            if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode) or stat.S_ISLNK(mode)):
                raise PackagingError(f"Unsupported special file in the app: {entry.relative_to(root)}")
            if stat.S_ISLNK(mode):
                if Path(os.readlink(entry)).is_absolute():
                    raise PackagingError(f"An absolute symlink would break after app installation: {entry.relative_to(root)}")
                try:
                    destination = entry.resolve(strict=True)
                    destination.relative_to(root)
                except (OSError, RuntimeError, ValueError) as error:
                    raise PackagingError(f"App symlink is broken or escapes the bundle: {entry.relative_to(root)}") from error
            entries.append(entry)
        directories[:] = sorted(name for name in directories if not (Path(current) / name).is_symlink())
    return entries


def validate_app(app: Path, mode: str) -> tuple[Path, dict, list[Path]]:
    if mode not in ("native", "interface"):
        raise PackagingError("Build mode must be native or interface.")
    if app.suffix != ".app" or not app.is_dir():
        raise PackagingError("Select a compiled .app directory from an iOS Xcode archive.")
    app = app.resolve(strict=True)
    entries = app_entries(app)
    try:
        with (app / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise PackagingError("The application has no valid Info.plist.") from error
    if not isinstance(info, dict):
        raise PackagingError("Info.plist must contain a dictionary.")
    executable = info.get("CFBundleExecutable")
    bundle = info.get("CFBundleIdentifier")
    if not isinstance(executable, str) or executable in ("", ".", "..") or "/" in executable or "\\" in executable or "\0" in executable:
        raise PackagingError("CFBundleExecutable must name a file inside the app bundle.")
    if not isinstance(bundle, str) or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
        raise PackagingError("The application has no valid bundle identifier.")
    platforms = info.get("CFBundleSupportedPlatforms")
    if info.get("CFBundlePackageType") != "APPL" or not isinstance(platforms, list) or "iPhoneOS" not in platforms:
        raise PackagingError("Info.plist does not identify an iPhoneOS application.")
    binary = app / executable
    validate_macho(binary)
    if not binary.stat().st_mode & 0o111:
        raise PackagingError("The application binary does not have executable permissions.")
    if mode == "native":
        # Cytrus is linked statically. These dynamic artifacts prove the selected
        # native archive also carries the rendering and Switch dependencies.
        required = ["Ryujinx.Headless.SDL2.dylib", "libMoltenVK.dylib", "libavcodec.dylib", "libavutil.dylib",
                    "RyujinxHelper.framework/RyujinxHelper", "SDL2.framework/SDL2", "MoltenVK.framework/MoltenVK"]
        required += [f"{name}.framework/{name}" for name in
                     ["libavcodec", "libavdevice", "libavfilter", "libavformat", "libavutil", "libswresample", "libswscale"]]
        for relative in required:
            validate_macho(app / "Frameworks" / relative, file_type=6)
    elif (app / "Frameworks/Ryujinx.Headless.SDL2.dylib").exists():
        raise PackagingError("The interface artifact unexpectedly contains a Switch core; check the selected project.")
    return app, info, entries


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package(app: Path, output: Path, mode: str, source_revision: str,
            *, archive_path: str | None = None, xcode_version: str | None = None) -> dict:
    expected = f"Tandem-{mode}-unsigned.ipa"
    if output.name != expected:
        raise PackagingError(f"Use the explicit artifact name {expected} for this build mode.")
    app, info, entries = validate_app(app, mode)
    output = output.resolve(strict=False)
    try:
        output.relative_to(app)
    except ValueError:
        pass
    else:
        raise PackagingError("The output IPA must be outside the application bundle.")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".tandem-ipa-", suffix=".tmp", dir=output.parent, delete=False) as file:
            temporary = Path(file.name)
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            for entry in entries:
                relative = entry.relative_to(app)
                name = "Payload/Tandem.app" + ("/" + relative.as_posix() if relative.parts else "")
                mode_bits = entry.lstat().st_mode
                if stat.S_ISLNK(mode_bits):
                    item = zipfile.ZipInfo(name)
                    item.create_system = 3
                    item.external_attr = mode_bits << 16
                    archive.writestr(item, os.readlink(entry).encode("utf-8"))
                else:
                    archive.write(entry, name)
        os.replace(temporary, output)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    manifest = {
        "artifact": output.name,
        "sha256": sha256(output),
        "byte_count": output.stat().st_size,
        "build_mode": mode,
        "source_revision": source_revision,
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "bundle_identifier": info["CFBundleIdentifier"],
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "minimum_ios": info.get("MinimumOSVersion"),
        "platform": "iOS",
        "architecture": "arm64",
        "signing": "unsigned",
        "requires_resigning": True,
        "directly_installable": False,
        "contains_emulator_cores": mode == "native",
        "gameplay_verified": False,
        "xcode_version": xcode_version,
        "archive_path": archive_path,
    }
    manifest_path = output.with_suffix(".manifest.json")
    with tempfile.NamedTemporaryFile(mode="w", prefix=".tandem-manifest-", suffix=".tmp", dir=output.parent, delete=False) as file:
        json.dump(manifest, file, indent=2)
        file.write("\n")
        manifest_temp = Path(file.name)
    os.replace(manifest_temp, manifest_path)
    return manifest


class PackagingTests(unittest.TestCase):
    """Synthetic format fixtures test the packager; they do not compile iOS code."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="tandem-package-test-")
        self.root = Path(self.temporary.name)
        self.app = self.root / "Tandem.app"
        self.app.mkdir()
        self.info = {"CFBundleExecutable": "Tandem", "CFBundleIdentifier": "app.tandem.test",
                     "CFBundlePackageType": "APPL", "CFBundleSupportedPlatforms": ["iPhoneOS"],
                     "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1", "MinimumOSVersion": "17.0"}
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        self.binary = self.app / "Tandem"
        self.binary.write_bytes(self.fixture())
        self.binary.chmod(0o755)

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def fixture(platform=2):
        # Structurally complete header, __TEXT, device platform, LC_MAIN, ARM64
        # RET instruction. This is a parser fixture, never a produced app build.
        command_size = 72 + 24 + 24
        content_start = 32 + command_size
        header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 3, command_size, 0, 0)
        text = struct.pack("<II16sQQQQIIII", 0x19, 72, b"__TEXT", 0x100000000,
                           4096, 0, content_start + 4, 7, 5, 0, 0)
        version = struct.pack("<6I", 0x32, 24, platform, 17 << 16, 17 << 16, 0)
        entry = struct.pack("<IIQQ", 0x80000028, 24, content_start, 0)
        return header + text + version + entry + b"\xc0\x03\x5f\xd6"

    def test_valid_bundle_packages_payload_and_manifest(self):
        output = self.root / "Tandem-interface-unsigned.ipa"
        manifest = package(self.app, output, "interface", "test-source")
        with zipfile.ZipFile(output) as archive:
            self.assertIn("Payload/Tandem.app/Tandem", archive.namelist())
            self.assertEqual(archive.read("Payload/Tandem.app/Tandem"), self.binary.read_bytes())
        self.assertEqual(manifest["sha256"], sha256(output))
        self.assertFalse(manifest["directly_installable"])
        self.assertFalse(manifest["contains_emulator_cores"])
        self.assertTrue(output.with_suffix(".manifest.json").is_file())

    def test_missing_executable_rejected(self):
        self.binary.unlink()
        with self.assertRaises(PackagingError):
            validate_app(self.app, "interface")

    def test_text_or_truncated_header_rejected(self):
        for data in (b"version https://git-lfs.github.com/spec/v1\n", self.fixture()[:32]):
            self.binary.write_bytes(data)
            with self.assertRaises(PackagingError):
                validate_app(self.app, "interface")

    def test_simulator_binary_rejected(self):
        self.binary.write_bytes(self.fixture(platform=7))
        with self.assertRaises(PackagingError):
            validate_app(self.app, "interface")

    def test_escaping_symlink_rejected(self):
        outside = self.root / "outside"
        outside.write_text("external content")
        (self.app / "escape").symlink_to("../outside")
        with self.assertRaises(PackagingError):
            validate_app(self.app, "interface")

    def test_absolute_symlink_inside_source_is_not_portable(self):
        (self.app / "absolute").symlink_to(self.binary)
        with self.assertRaises(PackagingError):
            validate_app(self.app, "interface")

    def test_invalid_platform_metadata_rejected(self):
        self.info["CFBundleSupportedPlatforms"] = 7
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        with self.assertRaises(PackagingError):
            validate_app(self.app, "interface")

    def test_contained_symlink_preserved(self):
        (self.app / "alias").symlink_to("Tandem")
        output = self.root / "Tandem-interface-unsigned.ipa"
        package(self.app, output, "interface", "test-source")
        with zipfile.ZipFile(output) as archive:
            item = archive.getinfo("Payload/Tandem.app/alias")
            self.assertTrue(stat.S_ISLNK(item.external_attr >> 16))
            self.assertEqual(archive.read(item), b"Tandem")

    def test_bundle_executable_traversal_rejected(self):
        self.info["CFBundleExecutable"] = "../outside"
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        with self.assertRaises(PackagingError):
            validate_app(self.app, "interface")

    def test_native_mode_requires_real_core_libraries(self):
        with self.assertRaises(PackagingError):
            validate_app(self.app, "native")

    def test_misleading_artifact_name_rejected(self):
        with self.assertRaises(PackagingError):
            package(self.app, self.root / "Tandem-native-unsigned.ipa", "interface", "test-source")

    def test_invalid_segment_bounds_rejected(self):
        data = bytearray(self.fixture())
        struct.pack_into("<Q", data, 32 + 48, 2**32)
        self.binary.write_bytes(data)
        with self.assertRaises(PackagingError):
            validate_app(self.app, "interface")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--mode", choices=("native", "interface"))
    parser.add_argument("--source-revision", default="unversioned-source")
    parser.add_argument("--archive-path")
    parser.add_argument("--xcode-version")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PackagingTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    if args.app is None or args.output is None or args.mode is None:
        parser.error("--app, --output, and --mode are required unless --self-test is selected.")
    try:
        manifest = package(args.app, args.output, args.mode, args.source_revision,
                           archive_path=args.archive_path, xcode_version=args.xcode_version)
    except (PackagingError, OSError) as error:
        parser.exit(1, f"error: {error}\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
