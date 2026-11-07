"""Validate standard Apple .strings catalogs, semantic keys and all entry points."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LITERAL = r'"(?:[^"\\]|\\.)*"'
KEY = r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+'


def load_catalog(language):
    path = ROOT / 'Resources' / (language + '.lproj') / 'Localizable.strings'
    pairs = re.findall(r'^(' + LITERAL + r')\s*=\s*(' + LITERAL + r');$', path.read_text(), re.M)
    result = {}
    for key, value in pairs:
        key, value = json.loads(key), json.loads(value)
        if key in result:
            raise AssertionError('Duplicate localization key: ' + key)
        result[key] = value
    return result


class LocalizationTests(unittest.TestCase):
    def test_catalogs_have_matching_semantic_keys_and_safe_formats(self):
        english, chinese = load_catalog('en'), load_catalog('zh-Hans')
        self.assertGreater(len(english), 100)
        self.assertEqual(english.keys(), chinese.keys())
        for key, value in english.items():
            self.assertRegex(key, '^' + KEY + '$')
            self.assertTrue(value.strip(), key)
            self.assertTrue(chinese[key].strip(), key)
            self.assertEqual(re.findall(r'%(?:@|d|f)', value), re.findall(r'%(?:@|d|f)', chinese[key]), key)
            # Language-picker names are intentionally shown in their own language.
            if key != 'language.simplified_chinese':
                self.assertIsNone(re.search(r'[\u4e00-\u9fff]', value), key)

    def test_all_native_sources_and_helpers_use_cataloged_keys(self):
        catalog = load_catalog('en')
        namespaces = {key.split('.')[0] for key in catalog}
        for path in (ROOT / 'Sources').rglob('*.swift'):
            text = path.read_text()
            for literal in re.findall(LITERAL, text):
                if re.search(r'[\u4e00-\u9fff]', literal):
                    self.fail(f'Hard-coded Chinese string in {path}: {literal}')
                try:
                    value = json.loads(literal)
                except ValueError:
                    continue  # Swift interpolation is not JSON.
                if re.fullmatch(KEY, value) and value.split('.')[0] in namespaces and value != 'history.sqlite':
                    self.assertIn(value, catalog, f'Missing resource for {value} in {path}')
            for literal in re.findall(r'\b(?:L|L10n\.text)\((' + LITERAL + r')', text):
                self.assertIn(json.loads(literal), catalog, str(path))


if __name__ == '__main__':
    unittest.main()
