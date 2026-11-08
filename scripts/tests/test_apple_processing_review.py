import base64
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

P = Path(__file__).resolve().parents[2] / 'scripts/apple_processing_review.py'
spec = importlib.util.spec_from_file_location('processing', P)
p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)


def fixture(state='VALID'):
    return json.dumps({'data': [{'attributes': {'cfBundleShortVersionString':'1.3.0',
             'cfBundleVersion':'7','platform':'IOS'}, 'relationships': {'build': {'data':
             {'type':'builds','id':'build1'}}}}], 'links': {'next': None},
             'included': [{'type':'builds','id':'build1','attributes':{'processingState':state}}]}).encode()


class ProcessingTests(unittest.TestCase):
    def test_processing_categories_and_ambiguity(self):
        for state, expected in [('VALID','valid'),('PROCESSING','pending'),('FAILED','failed'),
                                ('INVALID','failed'),('SURPRISE','unknown')]:
            self.assertEqual(p.interpret(fixture(state),'1.3.0','7'), expected)
        obj=json.loads(fixture()); obj['data'].append(obj['data'][0]);
        self.assertEqual(p.interpret(json.dumps(obj).encode(),'1.3.0','7'),'unknown')
        obj=json.loads(fixture()); obj['links']['next']='next'
        self.assertEqual(p.interpret(json.dumps(obj).encode(),'1.3.0','7'),'unknown')
        self.assertEqual(p.interpret(b'{"data":[],"data":[]}', '1.3.0','7'), 'unknown')

    def test_token_claims_and_der_signature(self):
        # Harmless synthetic DER signature with R=1 and S=2; no real key.
        t=p.token('/unused','ABCDEFGHIJ','',now=100,signer=lambda _: bytes.fromhex('3006020101020102'))
        pieces=t.split('.'); claims=json.loads(base64.urlsafe_b64decode(pieces[1]+'=='))
        self.assertEqual(claims['sub'],'user'); self.assertNotIn('iss',claims)
        self.assertEqual(len(base64.urlsafe_b64decode(pieces[2]+'==')),64)
        with self.assertRaises(ValueError):p._ecdsa_raw(bytes.fromhex('3006020180020102'))

    def test_bounded_poll_never_retries_upload(self):
        calls=[]; now=[0]
        def read(token, version, build):
            calls.append(1); return fixture('PROCESSING' if len(calls)==1 else 'VALID')
        result=p.wait_for_processing('fake','1.3.0','7',reader=read,clock=lambda:now[0],
                                     sleeper=lambda s:now.__setitem__(0,now[0]+s))
        self.assertEqual(result,'valid'); self.assertEqual(len(calls),2)
        self.assertEqual(p.wait_for_processing('fake','1.3.0','7',reader=lambda *_: b'',
                                             clock=lambda:0,sleeper=lambda _:None),'unknown')

    def test_fetch_uses_fixed_apple_url_and_stdin(self):
        class Result: stdout=fixture()
        with patch.object(p.subprocess,'run',return_value=Result()) as run:
            self.assertEqual(p.fetch('synthetic-token','1.3.0','7'),fixture())
        args, kwargs=run.call_args
        self.assertEqual(args[0][1],'-c')
        self.assertNotIn('synthetic-token',repr(args))
        payload=json.loads(kwargs['input'])
        self.assertTrue(payload['url'].startswith('https://api.appstoreconnect.apple.com/v1/apps/6832293368/buildUploads?'))
        self.assertEqual(kwargs['timeout'],8)


if __name__ == '__main__': unittest.main()
