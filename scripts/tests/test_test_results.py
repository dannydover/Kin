import importlib.util
from pathlib import Path
import struct
import unittest
import zlib


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestFinalizedResults(unittest.TestCase):
    def setUp(self):
        self.validate = load('check-test-results').validate_summary
        self.result = dict(result='Passed', totalTestCount=89, passedTests=89, failedTests=0, skippedTests=0, expectedFailures=0)

    def test_complete_passing_results(self):
        self.assertTrue(self.validate(self.result))

    def test_missing_and_incomplete_results(self):
        for result in [None, {}, {'result': 'Passed'}, {**self.result, 'result': 'In Progress'}]:
            self.assertFalse(self.validate(result))

    def test_failures_skips_and_expected_failures(self):
        for key in ['failedTests', 'skippedTests', 'expectedFailures']:
            self.assertFalse(self.validate({**self.result, key: 1}))

    def test_empty_and_inconsistent_counts(self):
        self.assertFalse(self.validate({**self.result, 'totalTestCount': 0, 'passedTests': 0}))
        self.assertFalse(self.validate({**self.result, 'passedTests': 88}))
        self.assertFalse(self.validate({**self.result, 'skippedTests': '0'}))

    def test_synthetic_photo_has_only_pixels_and_valid_chunks(self):
        data = load('create-simulator-photo').synthetic_png()
        self.assertTrue(data.startswith(b'\x89PNG\r\n\x1a\n'))
        chunks = []; offset = 8; compressed = b''
        while offset < len(data):
            size = struct.unpack('>I', data[offset:offset + 4])[0]
            kind = data[offset + 4:offset + 8]; payload = data[offset + 8:offset + 8 + size]
            crc = struct.unpack('>I', data[offset + 8 + size:offset + 12 + size])[0]
            self.assertEqual(crc, zlib.crc32(kind + payload))
            chunks.append(kind)
            if kind == b'IHDR': self.assertEqual(struct.unpack('>II', payload[:8]), (96, 96))
            if kind == b'IDAT': compressed += payload
            offset += size + 12
        self.assertEqual(chunks, [b'IHDR', b'IDAT', b'IEND'])
        self.assertEqual(len(zlib.decompress(compressed)), 96 * (1 + 96 * 3))
