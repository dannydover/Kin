import importlib.util
from pathlib import Path
import unittest
import tempfile

spec = importlib.util.spec_from_file_location('shards', Path(__file__).resolve().parents[1] / 'ci-test-shards.py')
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)

class CoverageTests(unittest.TestCase):
    def test_shared_helper_cannot_hide_a_test(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'KinUITests').mkdir()
            helper = root / 'KinUITests/EditorTestSupport.swift'
            helper.write_text('func testAccidentallyAdded() {}')
            with self.assertRaisesRegex(ValueError, 'EditorTestSupport'):
                shards.discover(root)

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

    def test_allocation_is_deterministic_and_includes_new_tests(self):
        ids = ['suite/testA', 'suite/testB', 'suite/testC', 'suite/testD', 'suite/testNew']
        timings = {'suite/testA': 400, 'suite/testB': 80, 'suite/removed': 999}
        groups = shards.allocate(ids, timings, 90)
        self.assertEqual(groups, shards.allocate(list(reversed(ids)), timings, 90))
        self.assertEqual(sorted(item for group in groups for item in group), sorted(ids))
        self.assertEqual(len({item for group in groups for item in group}), len(ids))
        self.assertIn('suite/testNew', [item for group in groups for item in group])
        self.assertEqual(groups[0], ['suite/testA'])

    def test_bad_timing_data_fails_closed(self):
        for timings, fallback in [({'a': -1}, 90), ({'a': True}, 90), ({'a': float('nan')}, 90), ({}, 0)]:
            with self.subTest(timings=timings, fallback=fallback), self.assertRaises(ValueError):
                shards.allocate(['a'], timings, fallback)

    def test_result_tree_requires_exact_unique_test_identities(self):
        selected = ['KinUITests/Suite/testOne', 'KinUITests/Suite/testTwo']
        def report(ids):
            return {'testNodes': [{'nodeType': 'Test Suite', 'children': [
                {'nodeType': 'Test Case', 'nodeIdentifier': ident} for ident in ids
            ]}]}
        shards.verify_test_ids(report(['Suite/testTwo()', 'Suite/testOne()']), selected)
        for ids in (['Suite/testOne()', 'Suite/testOther()'],
                    ['Suite/testOne()', 'Suite/testOne()'], ['Suite/testOne()'],
                    ['Suite/testOne()', 'Suite/testTwo'], []):
            with self.subTest(ids=ids), self.assertRaises(ValueError):
                shards.verify_test_ids(report(ids), selected)
        with self.assertRaises(ValueError):
            shards.verify_test_ids({}, selected)
