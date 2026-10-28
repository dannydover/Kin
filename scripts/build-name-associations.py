#!/usr/bin/env python3
"""Generate Kin's offline associations from the unmodified national SSA ZIP.
Counts describe recorded application sex, not anyone's individual identity.
No suppression correction, alias expansion or cohort filtering is applied.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import zipfile

FIRST_YEAR, LAST_YEAR = 1940, 2025
SOURCE = 'https://www.ssa.gov/oact/babynames/names.zip'
LICENSE = 'https://creativecommons.org/publicdomain/zero/1.0/'


def generate(source):
    counts = defaultdict(lambda: [0, 0])
    with zipfile.ZipFile(source) as archive:
        for year in range(FIRST_YEAR, LAST_YEAR + 1):
            with archive.open('yob%d.txt' % year) as records:
                for raw in records:
                    name, sex, count = raw.decode('utf-8-sig').strip().split(',')
                    if sex not in ('M', 'F') or int(count) < 0 or not name:
                        raise ValueError('Unexpected source record')
                    counts[name][sex == 'F'] += int(count)
    male, female = [], []
    for name, (m, f) in sorted(counts.items()):
        total = m + f
        if total >= 100 and max(m, f) * 100 >= total * 85:
            (male if m > f else female).append(name)
    return {
        'provenance': {
            'source': SOURCE, 'sha256': hashlib.sha256(Path(source).read_bytes()).hexdigest(),
            'firstYear': FIRST_YEAR, 'lastYear': LAST_YEAR,
            'minimumCount': 100, 'dominantPercent': 85,
            'license': LICENSE,
            'credit': 'Derived from U.S. Social Security Administration data. No endorsement implied.',
            'meaning': 'Recorded sex associations in Social Security card applications, not individual identity.',
            'maleCount': len(male), 'femaleCount': len(female), 'totalCount': len(male) + len(female)
        }, 'male': male, 'female': female
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = generate(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(json.dumps(result['provenance'], indent=2))
