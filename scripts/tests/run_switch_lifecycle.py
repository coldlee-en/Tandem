#!/usr/bin/env python3
"""Compile and exercise lifecycle methods from an already patched MeloNX checkout.

The harness substitutes graphics dependencies, not the native lifecycle methods.
It tests cancellation/control flow; it does not validate rendering or gameplay.
Requires an installed .NET 8 SDK. Restore is offline and downloads are disabled.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile


METHODS = ("SignalGpuDone", "Render", "Exit", "MainLoop", "Execute")
FIELD_PATTERNS = (
    r"public (?:volatile )?bool _isActive;",
    r"private (?:volatile )?bool _isStopped;",
    r"private readonly object _lifecycleLock = new\(\);",
    r"private int _gpuCompletionSignalled;",
)


def extract_native_members(source: str) -> tuple[str, str]:
    fields = []
    for pattern in FIELD_PATTERNS:
        matches = list(re.finditer(r"^        " + pattern + r"$", source, re.MULTILINE))
        if len(matches) != 1:
            raise ValueError(f"Expected one native lifecycle field matching {pattern!r}")
        fields.append(matches[0].group())

    methods = []
    for name in METHODS:
        pattern = rf"^        (?:public|private) void {name}\(\)\n        \{{"
        matches = list(re.finditer(pattern, source, re.MULTILINE))
        if len(matches) != 1:
            raise ValueError(f"Expected one {name}() method; use the pinned, patched source")
        start = matches[0].start()
        # The reviewed pin uses eight spaces for member declarations/closing
        # braces. Fail closed if that shape changes; do not rewrite method code.
        end = source.find("\n        }", matches[0].end())
        if end < 0:
            raise ValueError(f"Missing closing member brace for {name}()")
        methods.append(source[start : end + len("\n        }")])
    return "\n".join(fields), "\n\n".join(methods)


def run_bounded(command: list[str], *, cwd: Path, env: dict[str, str], timeout: int) -> str:
    # A regression may leave native foreground threads blocked. Kill the whole
    # process group on timeout rather than leave a hanging test behind.
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        if output:
            print(output, end="")
        raise RuntimeError(f"Lifecycle harness command exceeded {timeout} seconds") from None
    if process.returncode:
        if output:
            print(output, end="")
        raise RuntimeError(f"Lifecycle harness command exited with status {process.returncode}")
    return output


def run(source_root: Path, dotnet: str, timeout: int) -> None:
    native_file = source_root / "src/Ryujinx.Headless.SDL2/WindowBase.cs"
    source = native_file.read_text(encoding="utf-8-sig")
    fields, methods = extract_native_members(source)
    template = Path(__file__).with_name("SwitchLifecycleHarness.cs.in").read_text()
    for marker in ("// TANDEM_NATIVE_FIELDS", "// TANDEM_NATIVE_METHODS"):
        if template.count(marker) != 1:
            raise ValueError(f"Harness template must contain exactly one {marker}")
    code = template.replace("// TANDEM_NATIVE_FIELDS", fields).replace("// TANDEM_NATIVE_METHODS", methods)

    with tempfile.TemporaryDirectory(prefix="tandem-switch-lifecycle-") as directory:
        work = Path(directory)
        env = os.environ.copy()
        env.update(
            DOTNET_CLI_HOME=str(work / "dotnet-home"),
            DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1",
            DOTNET_CLI_TELEMETRY_OPTOUT="1",
            DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE="1",
            DOTNET_NOLOGO="1",
            NUGET_PACKAGES=str(work / "nuget-packages"),
            MSBUILDDISABLENODEREUSE="1",
        )
        sdks = run_bounded([dotnet, "--list-sdks"], cwd=work, env=env, timeout=15)
        versions = re.findall(r"^(8\.\d+\.\d+) \[", sdks, re.MULTILINE)
        if not versions:
            raise RuntimeError("An installed .NET 8 SDK is required; this script does not download SDKs")
        version = max(versions, key=lambda value: tuple(map(int, value.split("."))))
        (work / "global.json").write_text(json.dumps({"sdk": {"version": version, "rollForward": "disable"}}))
        (work / "NuGet.Config").write_text(
            '<?xml version="1.0" encoding="utf-8"?><configuration><packageSources><clear /></packageSources></configuration>'
        )
        (work / "Lifecycle.csproj").write_text(
            '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
            '<OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework>'
            '<ImplicitUsings>enable</ImplicitUsings><Nullable>disable</Nullable>'
            '<UseSharedCompilation>false</UseSharedCompilation>'
            '</PropertyGroup></Project>'
        )
        (work / "Program.cs").write_text(code)
        print(f"Testing native lifecycle methods extracted from {native_file}", flush=True)
        print("Building offline with .NET " + version, flush=True)
        output = run_bounded(
            [dotnet, "build", "Lifecycle.csproj", "--configuration", "Release", "--configfile", "NuGet.Config", "--nologo"],
            cwd=work,
            env=env,
            timeout=120,
        )
        print(output, end="")
        output = run_bounded(
            [dotnet, str(work / "bin/Release/net8.0/Lifecycle.dll")], cwd=work, env=env, timeout=timeout
        )
        print(output, end="")
        print("Lifecycle control-flow tests passed; graphics and gameplay were not exercised.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Pinned MeloNX checkout after scripts/patch_switch.py")
    parser.add_argument("--dotnet", required=True, help="Installed dotnet executable with a .NET 8 SDK")
    parser.add_argument("--timeout", type=int, default=30, help="Bound test execution in seconds (default: 30)")
    args = parser.parse_args()
    try:
        if args.timeout < 1 or args.timeout > 180:
            raise ValueError("--timeout must be between 1 and 180 seconds")
        executable = shutil.which(args.dotnet)
        if not executable:
            raise ValueError("The supplied dotnet executable was not found")
        run(args.source.resolve(strict=True), str(Path(executable).resolve()), args.timeout)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
