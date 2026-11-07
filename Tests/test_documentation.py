"""Check cross-file user documentation contracts against the shipped build."""
from pathlib import Path
import re
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def local_targets(text):
    markdown = re.findall(r'!?\[[^\]]*\]\(([^\s)]+)\)', text)
    html = re.findall(r'(?:href|src|srcset)="([^"]+)"', text)
    return [target for target in markdown + html if target and not urlsplit(target).scheme and not target.startswith('#')]


class DocumentationTests(unittest.TestCase):
    def test_local_links_and_images_exist_with_correct_case(self):
        for doc in [*ROOT.glob('*.md'), *ROOT.joinpath('docs').glob('*.md')]:
            for target in local_targets(doc.read_text()):
                relative = unquote(urlsplit(target).path)
                path = doc.parent.joinpath(relative)
                with self.subTest(document=doc.name, target=target):
                    self.assertTrue(path.exists(), 'Broken local documentation link or image')
                    current = doc.parent
                    for part in Path(relative).parts:
                        if part == '..':
                            current = current.parent
                        elif part != '.':
                            self.assertIn(part, {entry.name for entry in current.iterdir()}, 'Link casing differs from the real path')
                            current = current / part

    def test_readme_languages_share_commands_and_destinations(self):
        chinese = ROOT.joinpath('README.md').read_text()
        english = ROOT.joinpath('README.en.md').read_text()
        shell = lambda text: re.findall(r'```sh\n(.*?)```', text, re.S)
        self.assertEqual(shell(chinese), shell(english), 'Installation commands differ between languages')
        def destinations(text):
            return {target.replace('UPDATING.en.md', 'UPDATING.md') for target in local_targets(text)
                    if not Path(target).name.startswith('README.') and not target.startswith('docs/images/')}
        self.assertEqual(destinations(chinese), destinations(english), 'README documentation entry points differ')

    def test_runtime_requirement_matches_build_and_no_stale_current_version(self):
        minimums = set(re.findall(r'<key>LSMinimumSystemVersion</key>\s*<string>([^<]+)</string>', ROOT.joinpath('build.sh').read_text()))
        self.assertEqual(len(minimums), 1, 'App and login helper requirements differ')
        minimum = minimums.pop().removesuffix('.0')
        version = ROOT.joinpath('VERSION').read_text().strip()
        for name in ['README.md', 'README.en.md', 'CONTRIBUTING.md']:
            text = ROOT.joinpath(name).read_text()
            self.assertIn('macOS ' + minimum, text, name + ' has an outdated runtime requirement')
            current = re.findall(r'(?:当前版本(?:为|是)|Current version:)\s*\*{0,2}([0-9]+\.[0-9]+\.[0-9]+(?:-[a-z]+\.[0-9]+)?)', text)
            for stated in current:
                self.assertEqual(stated, version, name + ' has an outdated current release')
