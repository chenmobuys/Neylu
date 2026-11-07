import base64
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import appcast
import release
spec = importlib.util.spec_from_file_location('publish_appcast', ROOT / 'scripts/publish-appcast.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


def metadata(assets, version, body='### English\n\n- **Fix** & <data>\n<!-- neylu:zh-Hans -->\n中文'):
    for arch in release.ARCHITECTURES:
        (assets / release.asset_name(version, arch)).write_bytes(arch.encode())
    return dict(tag_name='v'+version, html_url=appcast.REPOSITORY+'/releases/tag/v'+version, draft=False,
                prerelease='-' in version, body=body, published_at='2026-11-07T14:00:00Z',
                assets=[dict(name=p.name, size=p.stat().st_size, state='uploaded', digest='sha256:'+release.sha256_file(p),
                             browser_download_url=appcast.REPOSITORY+'/releases/download/v'+version+'/'+p.name)
                        for p in assets.iterdir()])


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.assets = Path(self.folder.name)
        self.meta = metadata(self.assets, '0.1.0-alpha.4')
        self.items = appcast.candidate(self.meta, self.assets, '4')

    def test_xml_roundtrip_and_both_architectures(self):
        for arch, item in self.items.items():
            data = appcast.merge(None, item, arch)
            parsed = appcast.read_items(data, arch)
            self.assertEqual(list(parsed), ['0.1.0-alpha.4'])
            self.assertEqual(appcast.field(parsed['0.1.0-alpha.4'], 'description'), self.meta['body'])
            self.assertIn(b'&amp;', data)
            self.assertEqual(appcast.merge(data, item, arch), data)
            with self.assertRaises(ValueError):
                appcast.read_items(data, 'x86_64' if arch == 'arm64' else 'arm64')

    def test_published_metadata_must_match_real_installer(self):
        for change in ['digest', 'size', 'browser_download_url']:
            broken = json.loads(json.dumps(self.meta))
            broken['assets'][0][change] = {'digest': 'sha256:'+'0'*64, 'size': 999, 'browser_download_url': 'https://evil.example/file.dmg'}[change]
            with self.assertRaises(ValueError):
                appcast.candidate(broken, self.assets, '4')
        for field, value in [('draft', True), ('prerelease', False), ('html_url', 'https://evil.example/release')]:
            broken = dict(self.meta, **{field: value})
            with self.assertRaises(ValueError):
                appcast.candidate(broken, self.assets, '4')
        for build in ['0', '01', '-1', '1;echo bad', str(2**64)]:
            with self.assertRaises(ValueError):
                appcast.candidate(self.meta, self.assets, build)

    def test_existing_history_immutable_assets_and_old_reruns(self):
        arch = 'arm64'
        old = appcast.merge(None, self.items[arch], arch)
        # A release retry must not silently replace an already published installer.
        replacement = ET.fromstring(ET.tostring(self.items[arch]))
        replacement.find(appcast.tag(appcast.NEYLU, 'sha256')).text = '0'*64
        with self.assertRaises(ValueError):
            appcast.merge(old, replacement, arch)
        newer = ET.fromstring(ET.tostring(self.items[arch]))
        for element in newer.iter():
            if element.text:
                element.text = element.text.replace('0.1.0-alpha.4', '0.1.0-alpha.5')
            if element.tag == appcast.tag(appcast.SPARKLE, 'version'):
                element.text = '5'
            if 'url' in element.attrib:
                element.attrib['url'] = element.attrib['url'].replace('0.1.0-alpha.4', '0.1.0-alpha.5')
        updated = appcast.merge(old, newer, arch)
        replayed = appcast.merge(updated, self.items[arch], arch)
        self.assertEqual(list(appcast.read_items(replayed, arch)), ['0.1.0-alpha.5', '0.1.0-alpha.4'])

    def test_xml_security_and_schema(self):
        data = appcast.merge(None, self.items['arm64'], 'arm64')
        for bad in [b'', data.replace(b'<rss ', b'<!DOCTYPE rss [<!ENTITY x "bad">]><rss ', 1),
                    data.replace(b'<rss ', b'<!ENTITY x "bad"><rss ', 1), b'x'*(appcast.LIMIT+1),
                    data.replace(b'xmlns:neylu="'+appcast.NEYLU.encode()+b'"', b'xmlns:neylu="https://evil.example"'),
                    data.replace(b'<sparkle:channel>alpha', b'<sparkle:channel>stable')]:
            with self.assertRaises((ValueError, ET.ParseError)):
                appcast.read_items(bad, 'arm64')

    def test_publisher_creates_only_feed_branch_and_is_idempotent(self):
        calls = []
        files = {}
        parent = None
        def api(method, path, payload=None):
            nonlocal parent
            calls.append((method, path, payload))
            if path == 'git/ref/heads/updates':
                return {'object': {'sha': parent}} if parent else None
            if path.startswith('git/commits/'):
                return {'tree': {'sha': 'tree'}}
            if path.startswith('contents/'):
                name = path.split('/')[1].split('?')[0]
                data = files[name]
                return dict(type='file', size=len(data), content=base64.b64encode(data).decode())
            if path == 'git/trees':
                for entry in payload['tree']:
                    files[entry['path']] = entry['content'].encode()
                return {'sha': 'new-tree'}
            if path == 'git/commits':
                return {'sha': 'new-commit'}
            if path == 'git/refs/heads/updates':
                self.assertFalse(payload['force'])
                parent = payload['sha']
                return {}
            if path == 'git/refs':
                self.assertEqual(payload['ref'], 'refs/heads/updates')
                parent = payload['sha']
                return {}
            raise AssertionError((method, path))
        self.assertEqual(publisher.publish(api, self.items), 'new-commit')
        self.assertEqual(set(files), {'appcast-arm64.xml', 'appcast-x86_64.xml'})
        calls.clear()
        self.assertEqual(publisher.publish(api, self.items), 'new-commit')
        self.assertTrue(all(method == 'GET' for method, _, _ in calls))
        calls.clear()
        changed = {arch: ET.fromstring(ET.tostring(item)) for arch, item in self.items.items()}
        for item in changed.values():
            item.find('description').text += '\nClarified notes'
        publisher.publish(api, changed)
        updates = [payload for method, path, payload in calls if method == 'PATCH']
        self.assertEqual(updates, [{'sha': 'new-commit', 'force': False}])
        commit = next(payload for method, path, payload in calls if method == 'POST' and path == 'git/commits')
        self.assertEqual(commit['parents'], ['new-commit'])

    def test_retention_preserves_stable_after_many_previews(self):
        feed = None
        for i, version in enumerate([f'0.1.{n}' for n in range(12)] + [f'0.2.0-alpha.{n}' for n in range(1, 22)], 1):
            item = ET.fromstring(ET.tostring(self.items['arm64']))
            item.find(appcast.tag(appcast.SPARKLE, 'shortVersionString')).text = version
            item.find(appcast.tag(appcast.SPARKLE, 'version')).text = str(i)
            channel = item.find(appcast.tag(appcast.SPARKLE, 'channel'))
            if '-' in version:
                channel.text = 'alpha'
            else:
                item.remove(channel)
            item.find('link').text = appcast.REPOSITORY+'/releases/tag/v'+version
            item.find('enclosure').set('url', appcast.REPOSITORY+'/releases/download/v'+version+'/'+release.asset_name(version,'arm64'))
            feed = appcast.merge(feed, item, 'arm64')
        retained = appcast.read_items(feed, 'arm64')
        self.assertEqual(len(retained), 20)
        self.assertIn('0.1.11', retained)
        self.assertIn('0.2.0-alpha.21', retained)
        self.assertNotIn('0.1.0', retained)

    def test_publisher_rejects_missing_feed_or_conflicting_ref(self):
        def missing(method, path, payload=None):
            if path == 'git/ref/heads/updates': return {'object': {'sha': 'old'}}
            if path.startswith('git/commits/'): return {'tree': {'sha': 'tree'}}
            return None
        with self.assertRaisesRegex(ValueError, 'missing an architecture'):
            publisher.publish(missing, self.items)
        calls = []
        def conflict(method, path, payload=None):
            calls.append((method, path, payload))
            if path == 'git/ref/heads/updates': return {'object': {'sha': 'old'}}
            if path.startswith('git/commits/'): return {'tree': {'sha': 'tree'}}
            if path.startswith('contents/'):
                arch = 'arm64' if 'arm64' in path else 'x86_64'
                data = appcast.merge(None, self.items[arch], arch)
                return dict(type='file', size=len(data), content=base64.b64encode(data).decode())
            if path == 'git/trees': return {'sha': 'new-tree'}
            if path == 'git/commits': return {'sha': 'new-commit'}
            if path == 'git/refs/heads/updates':
                self.assertFalse(payload['force'])
                raise RuntimeError('conflicting ref')
            raise AssertionError((method, path))
        changed = {arch: ET.fromstring(ET.tostring(item)) for arch, item in self.items.items()}
        for item in changed.values(): item.find('description').text += '\nClarified notes'
        with self.assertRaisesRegex(RuntimeError, 'conflicting ref'):
            publisher.publish(conflict, changed)
        self.assertEqual(sum(method == 'PATCH' for method, _, _ in calls), 1)

    def test_historical_os_requirement_is_preserved(self):
        historical = appcast.candidate(self.meta, self.assets, '4', minimum_system='13.0.0')
        old = appcast.merge(None, historical['arm64'], 'arm64')
        self.assertEqual(appcast.field(appcast.read_items(old,'arm64')['0.1.0-alpha.4'],appcast.tag(appcast.SPARKLE,'minimumSystemVersion')),'13.0.0')
        with self.assertRaisesRegex(ValueError,'same-version'):
            appcast.merge(old, self.items['arm64'], 'arm64')
        workflow = (ROOT/'.github/workflows/appcast.yml').read_text()
        self.assertIn('--build-script .build/release-build.sh', workflow)
        tap = (ROOT/'.github/workflows/homebrew.yml').read_text()
        self.assertEqual(tap.count('--build-script .build/release-build.sh'), 2)

    def test_release_and_homebrew_jobs_remain_connected(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertIn('uses: ./.github/workflows/homebrew.yml', workflow)
        self.assertIn('uses: ./.github/workflows/appcast.yml', workflow)
        self.assertEqual(workflow.count('needs: [prepare, publish]'), 2)
        self.assertNotIn('appcast.xml dist/', workflow)
        self.assertNotIn('api.github.com', (ROOT / 'Sources/UpdateDiscovery.swift').read_text())
        self.assertNotIn('Sparkle.framework', (ROOT / 'build.sh').read_text())
