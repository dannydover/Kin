import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('shards', Path(__file__).resolve().parents[1] / 'ci-test-shards.py')
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)

class CoverageTests(unittest.TestCase):
    def test_all_ui_methods_appear_exactly_once(self):
        expected = shards.discover()
        selected = [item for group in shards.GROUPS[1:] for item in shards.selections(group)]
        self.assertEqual(sorted(selected), expected)
        self.assertEqual(len(selected), len(set(selected)))
        self.assertTrue(all(shards.selections(group) for group in shards.GROUPS))

    def test_unit_and_integration_target_is_unfiltered(self):
        self.assertEqual(shards.selections('unit'), ['KinTests'])

    def test_invalid_shard_fails_closed(self):
        with self.assertRaises(ValueError):
            shards.selections('ui-9')
