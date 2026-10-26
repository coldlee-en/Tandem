#!/usr/bin/env python3
"""Assemble the pinned Vulkan SDK's open-source headers without an installer."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "Vendor/GraphicsHeaders"
SOURCES = {
    "Vulkan-Headers": ("https://github.com/KhronosGroup/Vulkan-Headers.git", "6802bb4733b63ed5efd3adb308a6c885ef180ea1"),
    "glslang": ("https://github.com/KhronosGroup/glslang.git", "e1b562a8bed273a02f30b59b66a5d499793cede5"),
    "VulkanMemoryAllocator": ("https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator.git", "1d8f600fd424278486eade7ed3e877c99f0846b1"),
}

def fetch(name, url, revision):
    checkout = VENDOR / name
    if not checkout.exists():
        checkout.mkdir(parents=True)
        subprocess.run(["git", "init", str(checkout)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "-C", str(checkout), "remote", "add", "origin", url], check=True)
        subprocess.run(["git", "-C", str(checkout), "fetch", "--depth", "1", "origin", revision], check=True)
        subprocess.run(["git", "-C", str(checkout), "checkout", "--detach", "FETCH_HEAD"], check=True)
    current = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if current != revision:
        raise RuntimeError(f"Preserving existing {name} checkout: expected {revision}, found {current}")
    return checkout

def copy_headers(source, destination):
    for path in source.rglob("*"):
        if path.is_file() and path.suffix in {".h", ".hpp", ".inl", ".inc", ".ipp"}:
            target = destination / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)

def main():
    VENDOR.mkdir(parents=True, exist_ok=True)
    checkouts = {name: fetch(name, *pin) for name, pin in SOURCES.items()}
    include = VENDOR / "include"
    marker = VENDOR / "headers-manifest.json"
    pins = {name: {"url": pin[0], "revision": pin[1]} for name, pin in SOURCES.items()}
    if include.exists():
        if marker.is_file() and json.loads(marker.read_text()) == pins:
            print(f"Graphics headers ready: {include}")
            return
        raise RuntimeError(f"Preserving unrecognized existing include directory: {include}")
    with tempfile.TemporaryDirectory(prefix="tandem-headers-", dir=VENDOR) as scratch:
        staging = Path(scratch) / "include"
        shutil.copytree(checkouts["Vulkan-Headers"] / "include", staging)
        copy_headers(checkouts["glslang"] / "glslang", staging / "glslang")
        copy_headers(checkouts["glslang"] / "SPIRV", staging / "glslang/SPIRV")
        (staging / "vma").mkdir()
        shutil.copy2(checkouts["VulkanMemoryAllocator"] / "include/vk_mem_alloc.h", staging / "vma/vk_mem_alloc.h")
        for relative in ["vulkan/vulkan.hpp", "glslang/Public/ShaderLang.h", "glslang/SPIRV/GlslangToSpv.h", "vma/vk_mem_alloc.h"]:
            if not (staging / relative).is_file():
                raise RuntimeError(f"Pinned headers missing {relative}")
        staging.rename(include)
    marker.write_text(json.dumps(pins, indent=2) + "\n")
    print(f"Graphics headers ready: {include}")

if __name__ == "__main__":
    main()
