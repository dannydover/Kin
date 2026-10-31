import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch

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

    def test_both_comparison_partitions_are_complete_and_disjoint(self):
        expected = shards.discover()
        for count in (4, 8):
            with self.subTest(count=count):
                selected = [item for index in range(count)
                            for item in shards.selections(f'ui-{index}', group_count=count)]
                self.assertEqual(sorted(selected), expected)
                self.assertEqual(len(selected), len(set(selected)))
                self.assertTrue(all(shards.selections(f'ui-{index}', group_count=count)
                                    for index in range(count)))
                with self.assertRaises(ValueError):
                    shards.selections(f'ui-{count}', group_count=count)

    def test_invalid_group_count_fails_closed(self):
        for count in (0, 3, 5, 9, True, '8'):
            with self.subTest(count=count), self.assertRaises(ValueError):
                shards.selections('ui-0', group_count=count)
        with patch.dict('os.environ', {'KIN_UI_SHARD_COUNT': '8'}):
            self.assertEqual(shards.selections('ui-7'), shards.selections('ui-7', group_count=8))
        with patch.dict('os.environ', {'KIN_UI_SHARD_COUNT': '9'}):
            with self.assertRaises(ValueError):
                shards.selections('ui-0')

    def test_comparison_is_pr_scoped_and_keeps_required_aggregate(self):
        workflow = (Path(__file__).resolve().parents[2] / '.github/workflows/ci.yml').read_text()
        comparison = workflow.split('  ui-comparison-eight:\n', 1)[1].split('  release-validation:\n', 1)[0]
        self.assertIn("github.event_name == 'pull_request'", comparison)
        self.assertIn('needs: [simulator-tests]', comparison)
        self.assertIn('always() && !cancelled()', comparison)
        self.assertIn("github.head_ref == 'feature/kin-1.3-ci-comparison'", comparison)
        self.assertIn('github.event.pull_request.head.repo.full_name == github.repository', comparison)
        self.assertIn('shard: [ui-0, ui-1, ui-2, ui-3, ui-4, ui-5, ui-6, ui-7]', comparison)
        self.assertIn('fail-fast: false', comparison)
        self.assertIn("KIN_UI_SHARD_COUNT: '8'", comparison)
        for script in ('ci-observe.py', 'check-test-results.py', 'ci-test-shards.py', 'ci-retain.py', 'ci-simulator.py'):
            self.assertIn(script, comparison)
        self.assertNotIn('continue-on-error', comparison)
        self.assertIn('needs: [core-validation, simulator-tests, release-validation]', workflow)

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
