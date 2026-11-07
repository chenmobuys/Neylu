"""Prove optimization preserves slots, PNG metadata and exact filtered pixels."""
import importlib.util
from pathlib import Path
import struct
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('icon', ROOT / 'Assets/optimize-icon.py')
icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icon)


class IconTests(unittest.TestCase):
    def test_lossless_recompression_and_slot_preservation(self):
        pixels = b'\x00' + b'\x10\x20\x30\xff' * 1024
        png = icon.PNG + icon.chunk(b'IHDR', struct.pack('>IIBBBBB', 1024, 1, 8, 6, 0, 0, 0))
        png += icon.chunk(b'tEXt', b'Comment\x00preserve metadata')
        png += icon.chunk(b'IDAT', zlib.compress(pixels, 1)) + icon.chunk(b'IEND', b'')
        parts = [(b'ic09', png), (b'ic10', png), (b'info', b'metadata')]
        body = b''.join(struct.pack('>4sI', k, len(v)+8)+v for k, v in parts)
        original = b'icns'+struct.pack('>I', len(body)+8)+body
        optimized = icon.optimize(original)
        self.assertLess(len(optimized), len(original))
        self.assertEqual(icon.optimize(optimized), optimized)
        for (old_kind, old), (kind, data) in zip(parts, icon.icon_chunks(optimized)):
            self.assertEqual(old_kind, kind)
            if old.startswith(icon.PNG):
                before, after = icon.png_chunks(old), icon.png_chunks(data)
                self.assertEqual([(k,v) for k,v in before if k != b'IDAT'], [(k,v) for k,v in after if k != b'IDAT'])
                self.assertEqual(zlib.decompress(b''.join(v for k,v in after if k == b'IDAT')), pixels)
            else:
                self.assertEqual(data, old)

    def test_malformed_containers_are_rejected(self):
        for value in [b'', b'icns\x00\x00\x00\x09', b'icns\x00\x00\x00\x10ic10\x00\x00\x00\x00']:
            with self.assertRaises(ValueError):
                icon.optimize(value)
