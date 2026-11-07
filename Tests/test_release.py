import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_exact_version_and_channel(self):
        self.assertFalse(release.validate_tag('v1.2.3', '1.2.3'))
        for stage in ['alpha', 'beta', 'rc']:
            version = f'1.2.3-{stage}.1'
            self.assertTrue(release.validate_tag('v' + version, version))
            with self.assertRaises(ValueError):
                release.validate_tag('v' + version, '1.2.3')
        for version in ['main', '1.2.3-alpha.0', '1.2.3-preview.1', '1.2.3;echo bad', '../1.2.3']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.validate_tag('v' + version, version)

    def test_notes_select_exact_release(self):
        text = '# Log\n## [Unreleased]\nfuture\n## [1.2.3-alpha.2]\n- second\n## [1.2.3-alpha.1]\n- first\n## [1.2.3]\n- stable\n'
        notes = release.release_notes(text, '1.2.3-alpha.2')
        self.assertIn('second', notes)
        self.assertNotIn('first', notes)
        self.assertEqual(release.release_notes(text, '1.2.3'), '- stable\n')
        with self.assertRaises(ValueError):
            release.release_notes(text, '1.2.30')

    def test_installers_and_github_digests(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            for arch in release.ARCHITECTURES:
                (output / release.asset_name('1.2.3-alpha.2', arch)).write_bytes(arch.encode())
            release.verify_assets(output, '1.2.3-alpha.2', release.ARCHITECTURES)
            self.assertEqual(len(list(output.iterdir())), 2)
            metadata = dict(tag_name='v1.2.3-alpha.2', draft=False, assets=[
                dict(name=p.name, size=p.stat().st_size, state='uploaded', digest='sha256:'+release.sha256_file(p))
                for p in output.iterdir()])
            release.verify_github_assets(output, '1.2.3-alpha.2', release.ARCHITECTURES, metadata)
            (output / 'release.json').write_text('{}')
            with self.assertRaises(ValueError):
                release.verify_assets(output, '1.2.3-alpha.2', release.ARCHITECTURES)
            (output / 'release.json').unlink()
            (output / release.asset_name('1.2.3-alpha.2', 'arm64')).write_bytes(b'tampered')
            with self.assertRaises(ValueError):
                release.verify_github_assets(output, '1.2.3-alpha.2', release.ARCHITECTURES, metadata)
            (output / release.asset_name('1.2.3-alpha.2', 'arm64')).write_bytes(b'arm64')
            metadata['assets'][0]['digest'] = None
            with self.assertRaises(ValueError):
                release.verify_github_assets(output, '1.2.3-alpha.2', release.ARCHITECTURES, metadata)
        with self.assertRaises(ValueError):
            release.asset_name('1.2.3', 'unknown')

    def test_cask_both_architectures_stable_only(self):
        digests = dict(arm64='a'*64, x86_64='b'*64)
        text = release.cask_text('owner/Neylu', '1.2.3', digests)
        self.assertIn('Neylu-#{version}-#{arch}.dmg', text)
        self.assertIn('arch arm: "arm64", intel: "x86_64"', text)
        for digest in digests.values():
            self.assertIn(digest, text)
        self.assertNotIn('no_check', text)
        self.assertNotIn('quarantine', text)
        for repo, version, checksums in [('bad"/repo', '1.2.3', digests), ('owner/repo', '1.2.3-alpha.1', digests), ('owner/repo', '1.2.3', {'arm64':'fake'})]:
            with self.assertRaises(ValueError):
                release.cask_text(repo, version, checksums)

    def test_owned_tap_prereleases_require_explicit_opt_in(self):
        digests = dict(arm64='a'*64, x86_64='b'*64)
        for stage in ['alpha', 'beta', 'rc']:
            version = f'0.1.0-{stage}.1'
            text = release.cask_text('owner/Neylu', version, digests, allow_prerelease=True)
            self.assertIn(f'version "{version}"', text)
            self.assertIn('cask "neylu"', text)
            self.assertIn('auto_updates true', text)
            self.assertNotIn('no_check', text)
            definition, caveats = text.split('  caveats <<~EOS', 1)
            self.assertNotIn('xattr', definition)
            self.assertNotIn('quarantine', definition)
            self.assertIn('xattr -dr com.apple.quarantine "#{appdir}/Neylu.app"', caveats)
            self.assertNotIn('postflight', text)
            self.assertNotIn('system_command', text)
        for version in ['0.1.0-preview.1', '../0.1.0', '0.1.0-alpha.0']:
            with self.assertRaises(ValueError):
                release.cask_text('owner/Neylu', version, digests, allow_prerelease=True)

    def test_installer_rejects_empty_files_links_and_directories(self):
        for kind in ['empty', 'installer_link', 'directory']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary) / 'dist'
                output.mkdir()
                image = output / release.asset_name('1.2.3-alpha.3', 'arm64')
                image.write_bytes(b'' if kind == 'empty' else b'installer')
                if kind == 'directory':
                    (output / 'unexpected').mkdir()
                elif kind.endswith('_link'):
                    target = image
                    outside = Path(temporary) / 'outside'
                    target.rename(outside)
                    target.symlink_to(outside)
                with self.assertRaises(ValueError):
                    release.verify_assets(output, '1.2.3-alpha.3', ['arm64'])

    def test_unsigned_stable_is_only_allowed_for_explicit_ci_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Neylu.app'
            resources = app / 'Contents/Resources'
            resources.mkdir(parents=True)
            helper = app / "Contents/Helpers/NeyluUpdater"
            helper.parent.mkdir()
            helper.write_bytes(b"fixture")
            for language in ['en','zh-Hans']:
                catalog = resources / (language+'.lproj') / 'Localizable.strings'
                catalog.parent.mkdir()
                catalog.write_text('"fixture.key" = "Fixture";')
            for name in ['AppIcon.icns', 'LICENSE', 'THIRD_PARTY_NOTICES.md']:
                (resources / name).write_bytes(b'fixture')
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
                CFBundleShortVersionString='1.2.3', NeyluReleaseVersion='1.2.3',
                CFBundleVersion=(ROOT / 'BUILD_NUMBER').read_text().strip(), CFBundleIdentifier='io.github.chenmobuys.Neylu')))
            with patch.object(release.subprocess, 'check_output', return_value='arm64'), patch.object(
                    release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, stderr='Signature=adhoc')) as run:
                with self.assertRaisesRegex(ValueError, 'Stable releases require Developer ID'):
                    release.check(app, '1.2.3', 'arm64')
                run.reset_mock()
                release.check(app, '1.2.3', 'arm64', require_notarization=False)
                run.assert_called_once_with(['codesign', '--verify', '--strict', '--deep', str(app)], check=True)

    def test_detach_retries_busy_without_force(self):
        busy = subprocess.CompletedProcess([], 16, stdout='', stderr='Resource busy')
        done = subprocess.CompletedProcess([], 0, stdout='', stderr='')
        with patch.object(release.subprocess, 'run', side_effect=[busy, busy, done]) as run, patch.object(release.time, 'sleep') as sleep:
            release.detach_image(Path('/temporary/mounted'))
            self.assertEqual(run.call_count, 3)
            self.assertEqual(sleep.call_count, 2)
            for call in run.call_args_list:
                self.assertEqual(call.args[0], ['hdiutil', 'detach', '/temporary/mounted'])
        with patch.object(release.subprocess, 'run', return_value=busy) as run, patch.object(release.time, 'sleep'):
            with self.assertRaises(subprocess.CalledProcessError):
                release.detach_image(Path('/temporary/mounted'))
            self.assertEqual(run.call_count, 6)
        with patch.object(release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, stdout='', stderr='Other error')) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                release.detach_image(Path('/temporary/mounted'))
            self.assertEqual(run.call_count, 1)

    def test_project_metadata(self):
        version = (ROOT / 'VERSION').read_text().strip()
        release.validate_tag('v' + version, version)
        self.assertRegex((ROOT / 'BUILD_NUMBER').read_text().strip(), r'^\d+$')
        self.assertTrue(release.release_notes((ROOT / 'CHANGELOG.md').read_text(), version))


if __name__ == '__main__':
    unittest.main()
