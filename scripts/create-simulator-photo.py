#!/usr/bin/env python3
"""Write a deterministic, metadata-free synthetic Photos fixture."""
from pathlib import Path
import struct
import sys
import zlib


def synthetic_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    size = 96
    rows = b''.join(b'\0' + b''.join(bytes((240, 145, 35) if 20 <= x < 76 and 20 <= y < 76 else (0, 175, 190)) for x in range(size)) for y in range(size))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')


if __name__ == '__main__':
    Path(sys.argv[1]).write_bytes(synthetic_png())
