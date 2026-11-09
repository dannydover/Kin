#!/usr/bin/env python3
"""Bounded read-only GitHub checks before the proposed secret-bearing step.

This detects common configuration drift; it is not an atomic deployment-policy
attestation. The owner must also verify unsupported/omitted settings in GitHub.
"""
import json
import urllib.error
import urllib.request

BASE = 'https://api.github.com/repos/dannydover/Kin/environments/kin-dev-signing'
EXPECTED_ENVIRONMENT_ID = 26652988418
EXPECTED_REVIEWER_ID = 136573
MAX_BYTES = 131072


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fetch(url):
    if url not in (BASE, BASE + '/deployment-branch-policies?per_page=100'):
        raise ValueError('unexpected endpoint')
    request = urllib.request.Request(url, headers={
        'Accept': 'application/vnd.github+json', 'User-Agent': 'kin-signing-preflight'})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())
    with opener.open(request, timeout=10) as response:
        if response.status != 200:
            raise ValueError('unexpected response')
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError('response too large')
    return json.loads(data, object_pairs_hook=_unique)


def validate(environment, policies):
    if not isinstance(environment, dict) or not isinstance(policies, dict):
        raise ValueError('malformed response')
    if environment.get('id') != EXPECTED_ENVIRONMENT_ID or environment.get('name') != 'kin-dev-signing':
        raise ValueError('environment missing or replaced')
    policy = environment.get('deployment_branch_policy')
    if not isinstance(policy, dict) or policy.get('protected_branches') is not False or policy.get('custom_branch_policies') is not True:
        raise ValueError('unexpected branch policy')
    rules = environment.get('protection_rules')
    if not isinstance(rules, list):
        raise ValueError('missing protection rules')
    reviews = [r for r in rules if isinstance(r, dict) and r.get('type') == 'required_reviewers']
    if len(reviews) != 1 or reviews[0].get('prevent_self_review') is not False:
        raise ValueError('unexpected review policy')
    reviewers = reviews[0].get('reviewers')
    if not isinstance(reviewers, list) or len(reviewers) != 1:
        raise ValueError('unexpected reviewers')
    reviewer = reviewers[0]
    if not isinstance(reviewer, dict) or reviewer.get('type') != 'User' or not isinstance(reviewer.get('reviewer'), dict):
        raise ValueError('unexpected reviewer')
    if reviewer['reviewer'].get('id') != EXPECTED_REVIEWER_ID or reviewer['reviewer'].get('login') != 'dannydover':
        raise ValueError('unexpected reviewer')
    branch_rules = policies.get('branch_policies')
    if policies.get('total_count') != 1 or not isinstance(branch_rules, list) or len(branch_rules) != 1:
        raise ValueError('unexpected branch policy count')
    branch = branch_rules[0]
    if not isinstance(branch, dict) or branch.get('name') != 'main' or branch.get('type', 'branch') != 'branch':
        raise ValueError('unexpected branch rule')
    # The public response may include this field, but it is not in GitHub's
    # published response schema. If absent, the owner must verify it in the UI.
    bypass = environment.get('can_admins_bypass')
    if bypass is not None and bypass is not False:
        raise ValueError('administrator bypass enabled or malformed')
    return {'admin_bypass_verified': bypass is False,
            'branch_type_verified': branch.get('type') == 'branch'}


def main():
    try:
        result = validate(fetch(BASE), fetch(BASE + '/deployment-branch-policies?per_page=100'))
    except Exception:
        raise SystemExit('Signing environment preflight failed; no secrets used.')
    print('Signing environment public checks passed; recheck owner settings before approval.')
    if not all(result.values()):
        print('Some optional response fields were absent; owner UI verification remains required.')


if __name__ == '__main__':
    main()
