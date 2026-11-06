import importlib.util
import pathlib
import unittest

p = pathlib.Path(__file__).with_name('run_tests.py')
spec = importlib.util.spec_from_file_location('ab_runner', p)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class RewriteTests(unittest.TestCase):
    def test_preserves_selection_and_limits(self):
        source = ['xcodebuild','-project','Kin.xcodeproj','-scheme','Kin','-destination','platform=iOS Simulator,id=synthetic',
                  '-derivedDataPath','DerivedData','-resultBundlePath','/tmp/result','-parallel-testing-enabled','NO',
                  '-collect-test-diagnostics','never','-test-timeouts-enabled','YES',
                  '-default-test-execution-time-allowance','240','-maximum-test-execution-time-allowance','600',
                  '-only-testing:KinTests','clean','test','CODE_SIGNING_ALLOWED=NO']
        result = m.rewrite(source, '/tmp/fixed.xctestrun')
        self.assertIn('test-without-building', result)
        self.assertEqual([x for x in result if x.startswith('-only-testing:')], ['-only-testing:KinTests'])
        for flag in ('-destination','-resultBundlePath','-parallel-testing-enabled','-collect-test-diagnostics',
                     '-test-timeouts-enabled','-default-test-execution-time-allowance','-maximum-test-execution-time-allowance'):
            self.assertEqual(source[source.index(flag)+1], result[result.index(flag)+1])
        self.assertNotIn('clean', result)
        self.assertEqual(m.rewrite(['vm_stat'], '/tmp/fixed'), ['vm_stat'])
        for old,new in [('240','241'),('Kin','Other'),('clean','test')]:
            changed = source.copy(); changed[changed.index(old)] = new
            with self.assertRaises(ValueError): m.rewrite(changed, '/tmp/fixed')
        with self.assertRaises(ValueError): m.rewrite(source[:-4]+source[-4:-3]+source[-4:], '/tmp/fixed')

if __name__ == '__main__': unittest.main()
