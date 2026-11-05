#!/usr/bin/env python3
"""Verify a random-order trial changed observed order without changing UI identities."""
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('shards', Path(__file__).with_name('ci-test-shards.py'))
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)


def compare(baseline, random, expected):
    if set(baseline) != set(expected) or set(random) != set(expected):
        raise ValueError('Missing or unexpected UI shard')
    changed = []
    for group, identities in expected.items():
        for label, values in (('baseline', baseline[group]), ('random', random[group])):
            if len(values) != len(set(values)) or set(values) != set(identities):
                raise ValueError(f'{label} test-start identities do not match {group}')
        if baseline[group] != random[group]:
            changed.append(group)
    if not changed:
        raise ValueError('Observed test order did not change')
    return changed


def read_starts(directory, group):
    records = [json.loads(line) for line in (Path(directory) / f'{group}.jsonl').read_text().splitlines()]
    kind = 'unit_order' if group == 'unit' else 'test'
    return [r['id'] for r in records if r.get('kind') == kind and r.get('event') == 'started']


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] not in ('--smoke', '--unit')):
        sys.exit('Usage: ci-compare-order.py BASELINE_DIR RANDOM_DIR [--smoke|--unit]')
    try:
        groups = (sys.argv[3][2:],) if len(sys.argv) == 4 else shards.GROUPS[1:]
        expected = {g: (['photo-reopen', 'row-render', 'notebook-lifecycle'] if g == 'unit' else shards.selections(g)) for g in groups}
        before = {g: read_starts(sys.argv[1], g) for g in groups}
        after = {g: read_starts(sys.argv[2], g) for g in groups}
        print('Observed order changed in:', ', '.join(compare(before, after, expected)))
    except (OSError, ValueError, KeyError, TypeError):
        sys.exit('Order comparison incomplete or unchanged; inspect the retained synthetic manifests.')
