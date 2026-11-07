import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('update_tap', ROOT / 'scripts/update-tap.py')
tap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tap)


class TapTests(unittest.TestCase):
    def fixture(self, directory, version='0.1.0-alpha.4'):
        assets = directory / 'assets'
        assets.mkdir(exist_ok=True)
        rows = []
        for arch in tap.release.ARCHITECTURES:
            image = assets / tap.release.asset_name(version, arch)
            image.write_bytes(arch.encode())
            rows.append(dict(name=image.name, state='uploaded', size=image.stat().st_size,
                             digest='sha256:' + tap.release.sha256_file(image),
                             browser_download_url=f'https://github.com/chenmobuys/Neylu/releases/download/v{version}/{image.name}'))
        return assets, dict(tag_name='v'+version, draft=False, published_at='2026-11-07T00:00:00Z', assets=rows)

    def test_published_release_verification_and_apply(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            assets, metadata = self.fixture(root)
            cask = root/'tap/Casks/neylu.rb'
            content = tap.candidate('v0.1.0-alpha.4', assets, metadata)
            self.assertTrue(tap.apply(cask, content))
            self.assertEqual(cask.read_text(), content)
            self.assertFalse(tap.apply(cask, content))
            for invalid in [dict(metadata, draft=True), dict(metadata, published_at=None), dict(metadata, tag_name='v0.1.0-alpha.3')]:
                with self.assertRaises(ValueError):
                    tap.candidate('v0.1.0-alpha.4', assets, invalid)
            for field, value in [('digest', 'sha256:'+'c'*64), ('size', 0), ('state', 'new'), ('browser_download_url', 'https://example.com/installer.dmg')]:
                invalid = json.loads(json.dumps(metadata))
                invalid['assets'][0][field] = value
                with self.subTest(field=field), self.assertRaises(ValueError):
                    tap.candidate('v0.1.0-alpha.4', assets, invalid)

    def test_missing_or_tampered_installer_does_not_update_cask(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            assets, metadata = self.fixture(root)
            image = assets / metadata['assets'][0]['name']
            image.write_bytes(b'tampered')
            with self.assertRaises(ValueError):
                tap.candidate('v0.1.0-alpha.4', assets, metadata)
            image.unlink()
            with self.assertRaises(FileNotFoundError):
                tap.candidate('v0.1.0-alpha.4', assets, metadata)
            self.assertFalse((root/'tap/Casks/neylu.rb').exists())

    def test_no_downgrades_or_same_version_checksum_changes(self):
        digests = dict(arm64='a'*64, x86_64='b'*64)
        def content(version, sums=digests):
            return tap.release.cask_text('chenmobuys/Neylu', version, sums, allow_prerelease=True)
        with tempfile.TemporaryDirectory() as tmp:
            cask = Path(tmp)/'Casks/neylu.rb'
            self.assertTrue(tap.apply(cask, content('0.1.0-alpha.10')))
            self.assertFalse(tap.apply(cask, content('0.1.0-alpha.9')))
            self.assertTrue(tap.apply(cask, content('0.1.0-beta.1')))
            self.assertFalse(tap.apply(cask, content('0.1.0-alpha.11')))
            self.assertTrue(tap.apply(cask, content('0.1.0-rc.1')))
            self.assertTrue(tap.apply(cask, content('0.1.0')))
            self.assertFalse(tap.apply(cask, content('0.1.0-rc.2')))
            before = cask.read_text()
            with self.assertRaises(ValueError):
                tap.apply(cask, content('0.1.0', dict(arm64='c'*64, x86_64='b'*64)))
            self.assertEqual(cask.read_text(), before)
            self.assertTrue(tap.apply(cask, content('0.1.1-alpha.1')))
            self.assertFalse(tap.apply(cask, content('0.1.0')))
            cask.write_text('invalid cask')
            with self.assertRaises(ValueError):
                tap.apply(cask, content('0.1.1'))
            cask.unlink()
            outside = Path(tmp)/'outside.rb'
            outside.write_text('preserve')
            cask.symlink_to(outside)
            with self.assertRaises(ValueError):
                tap.apply(cask, content('0.1.1'))
            self.assertEqual(outside.read_text(), 'preserve')

    def test_strict_semantic_versions(self):
        for value in ['1.2.3-alpha.0', '01.2.3', '1.2.3-alpha.01', 'v1.2.3', '1.2.3;echo bad']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                tap.version_key(value)
