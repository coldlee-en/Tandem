"""Publication guards using temporary structural fixtures and mocked GitHub calls."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_release as publisher

class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tandem-release-test-')
        self.directory = Path(self.temp.name)
        self.source = 'a' * 40
        self.ipa = self.directory / 'Tandem-native-unsigned.ipa'
        info = {'CFBundleShortVersionString': '0.1.1', 'CFBundleVersion': '2',
                'CFBundleIdentifier': 'app.tandem.emulator'}
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/Tandem.app/Info.plist', plistlib.dumps(info))
            archive.writestr('Payload/Tandem.app/test-fixture.txt', 'Structural release test; not an iOS application.')
        self.data = {'artifact': self.ipa.name, 'source_revision': self.source,
                     'build_mode': 'native', 'contains_emulator_cores': True,
                     'signing': 'unsigned', 'requires_resigning': True,
                     'platform': 'iOS', 'architecture': 'arm64', 'version': '0.1.1',
                     'build': '2', 'minimum_ios': '17.0', 'bundle_identifier': info['CFBundleIdentifier'],
                     'sha256': publisher.digest(self.ipa), 'byte_count': self.ipa.stat().st_size}
        self.save()

    def tearDown(self):
        self.temp.cleanup()

    def save(self):
        (self.directory / 'Tandem-native-unsigned.manifest.json').write_text(json.dumps(self.data))

    def prepare(self):
        return publisher.prepare(self.directory, self.source, '1234', 'owner/Tandem')

    def test_prepare_produces_checksum_and_unsigned_notes(self):
        tag, assets, notes = self.prepare()
        self.assertEqual(tag, 'v0.1.1')
        self.assertEqual(len(assets), 3)
        self.assertIn(self.data['sha256'], assets[2].read_text())
        self.assertIn('unsigned', notes.read_text())
        self.assertIn(self.source, notes.read_text())

    def test_modified_ipa_rejected_before_any_github_call(self):
        with self.ipa.open('ab') as stream:
            stream.write(b'modified')
        with patch.object(publisher, 'command') as gh:
            with self.assertRaisesRegex(ValueError, 'checksum or size'):
                self.prepare()
            gh.assert_not_called()

    def test_wrong_source_and_interface_artifacts_rejected(self):
        for field, value in [('source_revision', 'b' * 40), ('build_mode', 'interface'),
                             ('contains_emulator_cores', False)]:
            original = self.data[field]
            self.data[field] = value
            self.save()
            with self.assertRaisesRegex(ValueError, 'expected native source'):
                self.prepare()
            self.data[field] = original

    def test_unsafe_version_and_bundle_version_mismatch_rejected(self):
        for version in ['../main', '1.2.3-..', '0.1.2']:
            self.data['version'] = version
            self.save()
            with self.assertRaises(ValueError):
                self.prepare()

    def test_existing_release_from_other_source_is_not_modified(self):
        tag, assets, notes = self.prepare()
        responses = [json.dumps({'isDraft': False, 'targetCommitish': 'main', 'assets': [], 'url': 'release'}), 'b' * 40]
        with patch.object(publisher, 'command', side_effect=responses) as gh:
            with self.assertRaisesRegex(ValueError, 'another source'):
                publisher.publish(tag, assets, notes, 'owner/Tandem', self.source)
            self.assertEqual(gh.call_count, 2)

    def test_publication_remains_draft_until_assets_uploaded(self):
        tag, assets, notes = self.prepare()
        calls = []
        def gh(args, **kwargs):
            calls.append(args)
            return None if args[:3] == ['gh', 'release', 'view'] else ''
        missing = subprocess.CompletedProcess([], 1, '', 'gh: Not Found (HTTP 404)')
        with patch.object(publisher, 'command', side_effect=gh), patch.object(publisher.subprocess, 'run', return_value=missing):
            publisher.publish(tag, assets, notes, 'owner/Tandem', self.source)
        self.assertEqual([call[2] for call in calls], ['view', 'create', 'upload', 'edit'])
        self.assertIn('--draft', calls[1])
        self.assertIn('--draft=false', calls[-1])
        self.assertIn(self.source, calls[1])

if __name__ == '__main__':
    unittest.main()
