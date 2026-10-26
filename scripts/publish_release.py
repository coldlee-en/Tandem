#!/usr/bin/env python3
"""Publish a validated native build as an immutable versioned development release.

Run in the release workflow with its repository GITHUB_TOKEN. --prepare-only
validates local files and writes release notes/checksum without contacting GitHub.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def prepare(directory, source_sha, run_id, repository):
    if not re.fullmatch(r'[0-9a-f]{40}', source_sha) or not re.fullmatch(r'[0-9]+', run_id):
        raise ValueError('Invalid build identity.')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid repository.')
    ipa = directory / 'Tandem-native-unsigned.ipa'
    manifest = directory / 'Tandem-native-unsigned.manifest.json'
    data = json.loads(manifest.read_text())
    required = {'artifact': ipa.name, 'source_revision': source_sha, 'build_mode': 'native',
                'contains_emulator_cores': True, 'signing': 'unsigned',
                'platform': 'iOS', 'architecture': 'arm64', 'requires_resigning': True}
    if any(data.get(key) != value for key, value in required.items()):
        raise ValueError('Manifest does not identify the expected native source build.')
    if data.get('sha256') != digest(ipa) or data.get('byte_count') != ipa.stat().st_size:
        raise ValueError('IPA checksum or size differs from its manifest.')
    version = data.get('version', '')
    if not isinstance(version, str) or not re.fullmatch(r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)?', version):
        raise ValueError('A semantic version is required for the release tag.')
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupt IPA ZIP entry.')
        info = plistlib.loads(archive.read('Payload/Tandem.app/Info.plist'))
    if (info.get('CFBundleShortVersionString') != version
            or str(info.get('CFBundleVersion')) != str(data.get('build'))
            or info.get('CFBundleIdentifier') != data.get('bundle_identifier')):
        raise ValueError('IPA bundle metadata differs from its manifest.')
    checksum = directory / 'Tandem-native-unsigned.sha256'
    checksum.write_text(f'{data["sha256"]}  {ipa.name}\n')
    notes = directory / 'release-notes.md'
    notes.write_text(f'''Native iOS development build of Tandem {version}, including the Cytrus/Azahar 3DS and MeloNX/Ryujinx Switch integrations.

- Source: `{source_sha}`
- [Successful native build](https://github.com/{repository}/actions/runs/{run_id})
- iOS {data['minimum_ios']} or later; arm64; build {data['build']}.
- SHA-256: `{data['sha256']}`

The IPA is unsigned. Re-sign the app and all embedded frameworks/libraries before sideloading. Switch requires a suitable JIT-enabled process; signing alone does not grant JIT. Supply your own games and required console data. No console keys are included.

This is an experimental prerelease. Device gameplay, performance, and compatibility require separate testing. The manifest and checksum are attached. Corresponding Tandem source and pinned upstream source/build instructions are available in the repository.
''')
    return 'v' + version, [ipa, manifest, checksum], notes

def command(args, allow_missing=False):
    result = subprocess.run(args, capture_output=True, text=True, timeout=180)
    if result.returncode:
        if allow_missing and ('release not found' in result.stderr.lower() or 'HTTP 404' in result.stderr):
            return None
        raise RuntimeError((result.stderr or result.stdout).strip())
    return result.stdout.strip()

def publish(tag, assets, notes, repository, source_sha):
    existing = command(['gh', 'release', 'view', tag, '--repo', repository,
                        '--json', 'isDraft,targetCommitish,assets,url'], allow_missing=True)
    if existing is not None:
        release = json.loads(existing)
        target = release['targetCommitish']
        if not release['isDraft']:
            target = command(['gh', 'api', f'repos/{repository}/commits/{tag}', '--jq', '.sha'])
        if target != source_sha:
            raise ValueError('This version already points to another source commit; bump the version.')
        if not release['isDraft']:
            metadata = json.loads(command(['gh', 'api', f'repos/{repository}/releases/tags/{tag}']))
            remote = {asset['name']: asset for asset in metadata['assets']}
            if all(remote.get(path.name, {}).get('digest') == 'sha256:' + digest(path) for path in assets):
                print('Already published: ' + release['url'])
                return release['url']
            raise ValueError('Published assets are immutable; bump the version for a different build.')
    else:
        # A pre-existing tag must also resolve to this exact compiled source.
        ref = subprocess.run(['gh', 'api', f'repos/{repository}/git/ref/tags/{tag}'], capture_output=True, text=True)
        if ref.returncode == 0:
            target = command(['gh', 'api', f'repos/{repository}/commits/{tag}', '--jq', '.sha'])
            if target != source_sha:
                raise ValueError('Existing tag points to another commit; no release was created.')
        elif 'HTTP 404' not in ref.stderr:
            raise RuntimeError(ref.stderr.strip())
        command(['gh', 'release', 'create', tag, '--repo', repository,
                 *([] if ref.returncode == 0 else ['--target', source_sha]),
                 '--title', f'Tandem {tag[1:]} — unsigned native iOS build', '--draft', '--prerelease',
                 '--notes-file', str(notes)])
    command(['gh', 'release', 'upload', tag, *map(str, assets), '--repo', repository, '--clobber'])
    command(['gh', 'release', 'edit', tag, '--repo', repository, '--draft=false', '--prerelease', '--latest=false'])
    url = f'https://github.com/{repository}/releases/tag/{tag}'
    print(url)
    return url

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--artifact-directory', type=Path, required=True)
    p.add_argument('--source-sha', required=True)
    p.add_argument('--run-id', required=True)
    p.add_argument('--repository', required=True)
    p.add_argument('--prepare-only', action='store_true')
    args = p.parse_args()
    try:
        tag, assets, notes = prepare(args.artifact_directory, args.source_sha, args.run_id, args.repository)
        if args.prepare_only:
            print(json.dumps({'tag': tag, 'assets': [p.name for p in assets]}))
        else:
            url = publish(tag, assets, notes, args.repository, args.source_sha)
            summary = __import__('os').environ.get('GITHUB_STEP_SUMMARY')
            if summary:
                with open(summary, 'a') as out:
                    out.write(f'Published [{tag}]({url}) with native IPA, manifest, and SHA-256.\n')
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
