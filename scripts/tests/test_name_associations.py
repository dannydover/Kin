import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('name_associations', Path(__file__).parents[1] / 'build-name-associations.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)

class NameAssociationsTests(unittest.TestCase):
    def test_integer_thresholds_pooling_exact_spellings_and_year_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'synthetic.zip'
            with zipfile.ZipFile(source, 'w') as archive:
                records = {
                    1940: 'Boundary,M,85\nBoundary,F,15\nBelow,M,84\nBelow,F,16\nTooSmall,F,99\nPooled,F,50\nMichael,M,100\nMike,F,100\n',
                    2025: 'Pooled,F,50\nChris,M,8623\nChris,F,1377\n',
                    1939: 'Excluded,M,100\n', 2026: 'Future,F,100\n'
                }
                for year in range(1939, 2027):
                    archive.writestr('yob%d.txt' % year, records.get(year, ''))
            result = generator.generate(source)
            self.assertEqual(result['male'], ['Boundary', 'Chris', 'Michael'])
            self.assertEqual(result['female'], ['Mike', 'Pooled'])
            self.assertEqual(result['provenance']['totalCount'], 5)
            self.assertEqual(len(result['provenance']['sha256']), 64)

    def test_incomplete_year_range_fails_instead_of_silently_changing_algorithm(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'synthetic.zip'
            with zipfile.ZipFile(source, 'w') as archive:
                archive.writestr('yob1940.txt', 'Synthetic,M,100\n')
            with self.assertRaises(KeyError):
                generator.generate(source)


class BundledNameResourceTests(unittest.TestCase):
    def test_tracked_snapshot_provenance_and_real_counts(self):
        resource = Path(__file__).parents[2] / 'Kin/Core/Resources/NameAssociations.json'
        payload = json.loads(resource.read_text())
        metadata = payload['provenance']
        self.assertEqual(metadata['sha256'], 'cd78e975ed7bb358e018dd62fbe14ced89295e9581c49172ca4eedcb011b3724')
        self.assertEqual((metadata['firstYear'], metadata['lastYear']), (1940, 2025))
        self.assertEqual((metadata['minimumCount'], metadata['dominantPercent']), (100, 85))
        self.assertEqual((len(payload['male']), len(payload['female'])), (13373, 22486))
        self.assertEqual(metadata['totalCount'], 35859)
        for group in ('male', 'female'):
            self.assertEqual(payload[group], sorted(set(payload[group])))
            self.assertEqual(metadata[group + 'Count'], len(payload[group]))
        self.assertFalse(set(payload['male']) & set(payload['female']))
        self.assertTrue({'Michael', 'Mike', 'Chris'} <= set(payload['male']))
        self.assertIn('creativecommons.org/publicdomain/zero', metadata['license'])
