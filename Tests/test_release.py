import importlib.util
from pathlib import Path
import unittest
import tempfile
import json
import hashlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_stable_and_preview_tags(self):
        self.assertFalse(release.validate_tag('v1.2.3', '1.2.3'))
        self.assertTrue(release.validate_tag('v1.2.3-preview.1', '1.2.3'))
        for invalid in ['main', 'v1.2.4', 'v1.2.3-preview.0', 'v1.2.3-rc.1', 'v1.2.3;echo bad', '../v1.2.3']:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                release.validate_tag(invalid, '1.2.3')

    def test_notes_select_only_requested_release(self):
        text = '# Log\n\n## [Unreleased]\nfuture\n## [1.2.3]\n\n- selected\n\n## [1.2.2]\nold\n'
        self.assertEqual(release.release_notes(text, '1.2.3'), '- selected\n')
        for missing in ['1.0.0', '1.2.30']:
            with self.assertRaises(ValueError):
                release.release_notes(text, missing)

    def test_cask_uses_immutable_version_and_real_checksum(self):
        text = release.cask_text('owner/Neylu', '1.2.3', 'a' * 64)
        self.assertIn('releases/download/v#{version}/Neylu-#{version}-arm64.zip', text)
        self.assertIn('sha256 "' + 'a' * 64 + '"', text)
        self.assertIn('depends_on arch: :arm64', text)
        self.assertNotIn('no_check', text)
        self.assertNotIn('quarantine', text)
        for repo, version, digest in [('bad"/repo', '1.2.3', 'a'*64), ('owner/repo', 'latest', 'a'*64), ('owner/repo', '1.2.3', 'fake')]:
            with self.assertRaises(ValueError):
                release.cask_text(repo, version, digest)

    def test_reused_assets_reject_tampering_and_wrong_repository(self):
        version = (ROOT / 'VERSION').read_text().strip()
        tag = 'v' + version + '-preview.1'
        repository = 'owner/Neylu'
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            asset = f'Neylu-{tag[1:]}-arm64.zip'
            content = b'fixture archive bytes'
            (output / asset).write_bytes(content)
            digest = hashlib.sha256(content).hexdigest()
            (output / 'SHA256SUMS').write_text(f'{digest}  {asset}\n')
            (output / 'release.json').write_text(json.dumps(dict(version=version, tag=tag,
                repository=repository, preview=True, asset=asset, sha256=digest)))
            release.verify_assets(output, repository, tag)
            with self.assertRaises(ValueError):
                release.verify_assets(output, 'other/repo', tag)
            (output / asset).write_bytes(content + b'changed')
            with self.assertRaises(ValueError):
                release.verify_assets(output, repository, tag)

    def test_project_metadata_is_release_ready(self):
        version = (ROOT / 'VERSION').read_text().strip()
        self.assertRegex(version, r'^\d+\.\d+\.\d+$')
        self.assertRegex((ROOT / 'BUILD_NUMBER').read_text().strip(), r'^\d+$')
        self.assertTrue(release.release_notes((ROOT / 'CHANGELOG.md').read_text(), version))


if __name__ == '__main__':
    unittest.main()
