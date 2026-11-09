import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).resolve().parents[1] / 'check-signing-environment.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

class SigningEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.env = {'id': p.EXPECTED_ENVIRONMENT_ID, 'name': 'kin-dev-signing',
            'deployment_branch_policy': {'protected_branches': False, 'custom_branch_policies': True},
            'protection_rules': [{'type': 'required_reviewers', 'prevent_self_review': False,
                'reviewers': [{'type': 'User', 'reviewer': {'id': p.EXPECTED_REVIEWER_ID, 'login': 'dannydover'}}]}],
            'can_admins_bypass': False}
        self.policies = {'total_count': 1, 'branch_policies': [{'name': 'main', 'type': 'branch'}]}

    def test_expected_and_optional_fields(self):
        self.assertEqual(p.validate(self.env, self.policies), {'admin_bypass_verified': True, 'branch_type_verified': True})
        del self.env['can_admins_bypass']
        del self.policies['branch_policies'][0]['type']
        self.assertEqual(p.validate(self.env, self.policies), {'admin_bypass_verified': False, 'branch_type_verified': False})

    def test_bad_environment_and_reviewer(self):
        variants = []
        for key, value in [('id', 1), ('name', 'other'), ('can_admins_bypass', True), ('can_admins_bypass', 'false'), ('protection_rules', [])]:
            e = copy.deepcopy(self.env); e[key] = value; variants.append(e)
        for field, value in [('prevent_self_review', True), ('reviewers', []), ('reviewers', [{'type':'User','reviewer':{'id':1,'login':'dannydover'}}])]:
            e = copy.deepcopy(self.env); e['protection_rules'][0][field] = value; variants.append(e)
        e = copy.deepcopy(self.env); e['protection_rules'].append(copy.deepcopy(e['protection_rules'][0])); variants.append(e)
        e = copy.deepcopy(self.env); e['deployment_branch_policy']['custom_branch_policies'] = False; variants.append(e)
        for e in variants:
            with self.subTest(e=e), self.assertRaises(ValueError): p.validate(e, self.policies)

    def test_bad_branch_policy(self):
        for policies in ({'total_count':0,'branch_policies':[]}, {'total_count':1,'branch_policies':[{'name':'*','type':'branch'}]}, {'total_count':1,'branch_policies':[{'name':'main','type':'tag'}]}, {'total_count':2,'branch_policies':[{'name':'main','type':'branch'}]}, {}):
            with self.subTest(policies=policies), self.assertRaises(ValueError): p.validate(self.env, policies)

    def test_fetch_endpoint_and_json_bounds(self):
        class Response:
            status = 200
            def __init__(self, data): self.data = data
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, count): return self.data[:count]
        class Opener:
            def __init__(self, data): self.data = data
            def open(self, request, timeout):
                self_timeout = timeout
                assert self_timeout == 10
                return Response(self.data)
        with self.assertRaises(ValueError): p.fetch('https://example.invalid/')
        for data in (b'{"a":1,"a":2}', b'x' * (p.MAX_BYTES + 1), b'{'):
            with self.subTest(size=len(data)), patch.object(p.urllib.request, 'build_opener', return_value=Opener(data)), self.assertRaises(ValueError): p.fetch(p.BASE)
        with patch.object(p.urllib.request, 'build_opener', return_value=Opener(b'{"ok":true}')):
            self.assertEqual(p.fetch(p.BASE), {'ok': True})
        self.assertIsNone(p._NoRedirect().redirect_request(None, None, None, None, None, None))

if __name__ == '__main__': unittest.main()
