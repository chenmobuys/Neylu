"""Losslessly recompress ICNS PNG payloads using only Python's standard library.

Keep all Apple icon slots, PNG metadata, filters and pixel bytes unchanged.
The SVG and iconutil remain the source of artwork and ICNS structure.
"""
import struct
import sys
import zlib
from pathlib import Path

PNG = b"\x89PNG\r\n\x1a\n"


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def png_chunks(data):
    if not data.startswith(PNG):
        raise ValueError("Invalid PNG")
    result = []
    offset = len(PNG)
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("Truncated PNG chunk")
        size, kind = struct.unpack_from(">I4s", data, offset)
        end = offset + 12 + size
        if end > len(data):
            raise ValueError("Truncated PNG payload")
        payload = data[offset + 8:end - 4]
        if struct.unpack_from(">I", data, end - 4)[0] != zlib.crc32(kind + payload):
            raise ValueError("PNG CRC mismatch")
        result.append((kind, payload))
        offset = end
    return result


def optimize_png(data):
    chunks = png_chunks(data)
    compressed = b"".join(payload for kind, payload in chunks if kind == b"IDAT")
    pixels = zlib.decompress(compressed)
    replacement = zlib.compress(pixels, 9)
    if len(replacement) >= len(compressed):
        return data
    assert zlib.decompress(replacement) == pixels
    output = bytearray(PNG)
    written = False
    for kind, payload in chunks:
        if kind == b"IDAT":
            if written:
                continue
            payload = replacement
            written = True
        output.extend(chunk(kind, payload))
    return bytes(output)


def icon_chunks(data):
    if len(data) < 8 or data[:4] != b"icns" or struct.unpack_from(">I", data, 4)[0] != len(data):
        raise ValueError("Invalid ICNS header")
    result = []
    offset = 8
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("Truncated ICNS chunk")
        kind, size = struct.unpack_from(">4sI", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid ICNS payload")
        result.append((kind, data[offset + 8:offset + size]))
        offset += size
    return result


def optimize(data):
    parts = icon_chunks(data)
    parts = [(kind, optimize_png(payload) if payload.startswith(PNG) else payload) for kind, payload in parts]
    # Some tools add a table of contents; keep its per-slot sizes consistent.
    records = b"".join(struct.pack(">4sI", kind, len(payload) + 8) for kind, payload in parts if kind != b"TOC ")
    parts = [(kind, records if kind == b"TOC " else payload) for kind, payload in parts]
    body = b"".join(struct.pack(">4sI", kind, len(payload) + 8) + payload for kind, payload in parts)
    return b"icns" + struct.pack(">I", len(body) + 8) + body


if __name__ == "__main__":
    path = Path(sys.argv[1])
    original = path.read_bytes()
    optimized = optimize(original)
    if len(optimized) < len(original):
        path.write_bytes(optimized)
    print(f"Icon: {len(original):,} -> {min(len(original), len(optimized)):,} bytes (lossless)")
