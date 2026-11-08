import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import json
import uuid

P = Path(__file__).resolve().parents[2] / 'scripts' / 'kin_upload_review.py'
spec = importlib.util.spec_from_file_location('upload', P)
upload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upload)


class UploadReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.ipa = self.root / 'Kin.ipa'
        self.ipa.write_bytes(b'synthetic')
        self.key = 'ABCDEFGHIJ'
        self.issuer = str(uuid.UUID(int=1))

    def tearDown(self): self.tmp.cleanup()

    def call(self, runner):
        return upload.upload_once(self.ipa, self.key, self.issuer, b'synthetic-key', self.root, runner=runner)

    def test_success_is_not_processing_proof_and_no_retry(self):
        calls = []
        def fake(argv, timeout, env):
            key = Path(env['HOME']) / '.appstoreconnect/private_keys' / ('AuthKey_' + self.key + '.p8')
            self.assertEqual(key.read_bytes(), b'synthetic-key')
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)
            calls.append((argv, timeout, env)); return 0
        self.assertEqual(self.call(fake), 'tool-success-processing-unverified')
        self.assertEqual((self.root / 'upload-outcome').read_text(), 'tool-success-processing-unverified\n')
        self.assertEqual(len(calls), 1)
        self.assertFalse(Path(calls[0][2]['HOME']).exists())
        self.assertEqual(calls[0][0][0:3], ['/usr/bin/xcrun', 'altool', '--upload-app'])
        with self.assertRaises(FileExistsError): self.call(fake)
        self.assertEqual(len(calls), 1)

    def test_failure_and_exception_stay_uncertain(self):
        for fail in (False, True):
            with self.subTest(timeout=fail):
                (self.root / 'upload-outcome').unlink(missing_ok=True)
                homes = []
                def runner(a,t,e):
                    homes.append(e['HOME'])
                    if fail: raise TimeoutError()
                    return 1
                self.assertEqual(self.call(runner), 'uncertain')
                self.assertEqual((self.root / 'upload-outcome').read_text(), 'uncertain\n')
                self.assertFalse(Path(homes[0]).exists())

    def test_real_deadline_cleans_auth_home_and_blocks_retry(self):
        homes = []
        def runner(argv, timeout, env):
            homes.append(Path(env['HOME']))
            return upload._bounded_run([sys.executable, '-c', 'import time; time.sleep(3)'], 0.1, env)
        self.assertEqual(self.call(runner), 'uncertain')
        self.assertFalse(homes[0].exists())
        self.assertEqual((self.root / 'upload-outcome').read_text(), 'uncertain\n')
        with self.assertRaises(FileExistsError): self.call(runner)
        self.assertEqual(len(homes), 1)

    def test_interruption_preserves_uncertainty(self):
        homes = []
        def interrupted(argv, timeout, env):
            homes.append(env['HOME'])
            raise KeyboardInterrupt()
        with self.assertRaises(KeyboardInterrupt): self.call(interrupted)
        self.assertEqual((self.root / 'upload-outcome').read_text(), 'uncertain\n')
        self.assertFalse(Path(homes[0]).exists())

    def test_individual_key_proposal_does_not_require_issuer(self):
        calls=[]
        upload.upload_once(self.ipa, self.key, '', b'synthetic-key', self.root,
                           runner=lambda a,t,e: calls.append(a) or 0)
        self.assertNotIn('--apiIssuer', calls[0])

    def test_upload_processing_and_key_cleanup_are_sequenced(self):
        calls=[]
        def runner(a,t,e): calls.append('upload'); return 0
        def processor(key, kid, issuer, version, build):
            self.assertEqual(key.read_bytes(), b'synthetic-key')
            calls.append('processing'); return 'valid'
        result=upload.upload_once(self.ipa,self.key,self.issuer,b'synthetic-key',self.root,
                                  version='1.3.0',build='7',runner=runner,processor=processor)
        self.assertEqual(result,'processing-valid-metadata-match')
        self.assertEqual(calls,['upload','processing'])
        self.assertEqual((self.root/'upload-outcome').read_text(),'processing-valid-metadata-match\n')
        self.assertEqual({x.name for x in self.root.iterdir()},{'Kin.ipa','upload-outcome'})

    def test_upload_composes_with_real_processing_parser_offline(self):
        sys.path.insert(0, str(P.parent))
        try:
            import apple_processing_review as processing
            response=json.dumps({'data':[{'attributes':{'cfBundleShortVersionString':'1.3.0',
                      'cfBundleVersion':'7','platform':'IOS'},'relationships':{'build':{'data':
                      {'type':'builds','id':'fake'}}}}], 'links':{'next':None},
                      'included':[{'type':'builds','id':'fake',
                      'attributes':{'processingState':'VALID'}}]}).encode()
            def processor(key, kid, issuer, version, build):
                return processing.wait_for_processing('fake-token',version,build,
                    reader=lambda *_:response,clock=lambda:0,sleeper=lambda _:None)
            result=upload.upload_once(self.ipa,self.key,self.issuer,b'synthetic-key',self.root,
                       version='1.3.0',build='7',runner=lambda *a:0,processor=processor)
            self.assertEqual(result,'processing-valid-metadata-match')
        finally: sys.path.pop(0)

    def test_failed_upload_does_not_check_processing(self):
        calls=[]
        result=upload.upload_once(self.ipa,self.key,self.issuer,b'synthetic-key',self.root,
                                  version='1.3.0',build='7',runner=lambda *a:1,
                                  processor=lambda *a:calls.append(1))
        self.assertEqual(result,'uncertain'); self.assertEqual(calls,[])

    def test_processing_failure_and_unknown_are_distinct(self):
        for observed, expected in [('failed','apple-processing-failed'),
                                   ('unknown','tool-success-processing-unverified')]:
            with self.subTest(observed=observed):
                (self.root/'upload-outcome').unlink(missing_ok=True)
                result=upload.upload_once(self.ipa,self.key,self.issuer,b'synthetic-key',self.root,
                                         version='1.3.0',build='7',runner=lambda *a:0,
                                         processor=lambda *a:observed)
                self.assertEqual(result,expected)

    def test_invalid_inputs_never_invoke(self):
        calls=[]
        with self.assertRaises(ValueError):
            upload.upload_once(self.ipa, self.key, 'bad', b'synthetic-key', self.root, runner=lambda a,t,e: calls.append(a))
        self.assertEqual(calls, [])
        self.assertFalse((self.root / 'upload-outcome').exists())

    def test_real_bounded_runner_uses_harmless_processes(self):
        self.assertEqual(upload._bounded_run([sys.executable, '-c', 'pass'], 2), 0)
        self.assertNotEqual(upload._bounded_run([sys.executable, '-c', 'raise SystemExit(7)'], 2), 0)
        with self.assertRaises(subprocess.TimeoutExpired):
            upload._bounded_run([sys.executable, '-c', 'import time; time.sleep(3)'], 0.1)

    def test_cli_is_inert(self):
        p = subprocess.run([sys.executable, str(P)], capture_output=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn(b'Upload is disabled', p.stderr)

    def test_script_upload_precedes_cleanup_boundary_and_guards_remain(self):
        sign = (P.parent / 'kin-sign-dev-review.sh').read_text()
        clean = (P.parent / 'kin-sign-cleanup.sh').read_text()
        self.assertIn('exit 1', sign.split('set -euo pipefail')[0])
        self.assertIn('exit 1', clean.split('set -euo pipefail')[0])
        self.assertIn('check_ipa_layout.py', sign)
        self.assertIn('codesign --verify', sign)
        self.assertNotIn('kin_upload_review.py', sign)


if __name__ == '__main__': unittest.main()
