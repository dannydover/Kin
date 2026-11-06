#!/usr/bin/env python3
"""Read-only hosted release preflight; does not sign or upload an app.

The workflow must check out the exact protected-main event SHA with full
history. API replies are fetched only from GitHub over HTTPS; no caller-supplied
result files or claimed test booleans are accepted. Passing is necessary but
not sufficient to authorize signing or establish signed artifact provenance.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

REPOSITORY = 'dannydover/Kin'
CI_SHA256 = '2924126f6af03e12c84ce196271fc04a048653892bc29ba20f9a31028229b986'
REQUIRED = {'core-validation', 'ios-tests', 'candidate-smoke', 'release-validation', 'validate'}
API = 'https://api.github.com/repos/' + REPOSITORY


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=20).strip()


def fetch(path, token):
    request = Request(API + path, headers={'Accept': 'application/vnd.github+json',
                                          'Authorization': 'Bearer ' + token,
                                          'X-GitHub-Api-Version': '2022-11-28',
                                          'User-Agent': 'Kin-hosted-release-preflight'})
    with build_opener(NoRedirect()).open(request, timeout=20) as response:
        require(response.status == 200, 'GitHub API unavailable')
        data = response.read(2_000_001)
    require(len(data) <= 2_000_000, 'GitHub response exceeds limit')
    return json.loads(data)


def verify_latest(source, response, fetch_jobs):
    require(isinstance(response, dict) and isinstance(response.get('workflow_runs'), list), 'Invalid run response')
    runs = response['workflow_runs']
    require(type(response.get('total_count')) is int and 0 < response['total_count'] <= 100
            and response['total_count'] == len(runs), 'Incomplete or missing run list')
    require(all(isinstance(r, dict) and isinstance(r.get('created_at'), str)
                and type(r.get('id')) is int for r in runs), 'Invalid run metadata')
    require(all(r.get('head_sha') == source and r.get('head_branch') == 'main'
                and r.get('event') == 'push' and r.get('path') == '.github/workflows/ci.yml'
                and r.get('status') == 'completed' and r.get('conclusion') == 'success'
                for r in runs), 'Nonpassing main CI evidence exists for source')
    run = max(runs, key=lambda r: (r['created_at'], r['id']))
    require(run.get('head_sha') == source and run.get('head_branch') == 'main'
            and run.get('event') == 'push' and run.get('path') == '.github/workflows/ci.yml'
            and run.get('status') == 'completed' and run.get('conclusion') == 'success',
            'Latest main CI run is not successful for source')
    run_id, attempt = run['id'], run.get('run_attempt')
    require(type(attempt) is int and attempt == 1, 'Rerun requires separate review')
    jobs_data = fetch_jobs(run_id, attempt)
    require(isinstance(jobs_data, dict) and isinstance(jobs_data.get('jobs'), list), 'Invalid jobs response')
    jobs = jobs_data['jobs']
    require(type(jobs_data.get('total_count')) is int and jobs_data['total_count'] == len(jobs)
            and len(jobs) == len(REQUIRED), 'Incomplete or unexpected job list')
    require({j.get('name') for j in jobs if isinstance(j, dict)} == REQUIRED, 'Required job identities differ')
    for job in jobs:
        require(job.get('status') == 'completed' and job.get('conclusion') == 'success'
                and job.get('run_id') == run_id and job.get('run_attempt') == attempt
                and job.get('head_sha') == source, 'Required job did not pass on source and attempt')
    return run_id, attempt


def main():
    source = os.environ.get('GITHUB_SHA', '')
    token = os.environ.get('GITHUB_TOKEN', '')
    require(os.environ.get('GITHUB_REPOSITORY') == REPOSITORY
            and os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and os.environ.get('GITHUB_REF') == 'refs/heads/main', 'Unexpected workflow context')
    require(re.fullmatch(r'[0-9a-f]{40}', source) is not None and bool(token), 'Missing source or token')
    require(command('git', 'rev-parse', 'HEAD') == source
            and command('git', 'rev-parse', 'refs/remotes/origin/main') == source
            and command('git', 'status', '--porcelain') == '', 'Checkout is not exact clean main')
    require(hashlib.sha256(Path('.github/workflows/ci.yml').read_bytes()).hexdigest() == CI_SHA256,
            'CI workflow has changed and needs review')
    require(command('xcodebuild', '-version') == 'Xcode 27.0\nBuild version 27A266a'
            and command('uname', '-m') == 'arm64', 'Hosted signing toolchain mismatch')
    def verify_remote_main():
        ref = fetch('/git/ref/heads/main', token)
        require(isinstance(ref, dict) and ref.get('ref') == 'refs/heads/main'
                and isinstance(ref.get('object'), dict) and ref['object'].get('type') == 'commit'
                and ref['object'].get('sha') == source, 'Main changed during preflight')
        branch = fetch('/branches/main', token)
        require(isinstance(branch, dict) and branch.get('name') == 'main'
                and branch.get('protected') is True and isinstance(branch.get('commit'), dict)
                and branch['commit'].get('sha') == source, 'Main is unprotected or changed')
    verify_remote_main()
    query = urlencode({'branch': 'main', 'event': 'push', 'head_sha': source, 'per_page': 100})
    runs = fetch('/actions/workflows/ci.yml/runs?' + query, token)
    def jobs(run_id, attempt):
        return fetch('/actions/runs/%d/attempts/%d/jobs?per_page=100' % (run_id, attempt), token)
    run_id, attempt = verify_latest(source, runs, jobs)
    current = fetch('/actions/runs/%d' % run_id, token)
    require(isinstance(current, dict) and current.get('id') == run_id
            and current.get('run_attempt') == attempt and current.get('head_sha') == source
            and current.get('status') == 'completed' and current.get('conclusion') == 'success',
            'CI run changed during preflight')
    require(verify_latest(source, fetch('/actions/workflows/ci.yml/runs?' + query, token), jobs)
            == (run_id, attempt), 'Latest CI evidence changed during preflight')
    verify_remote_main()
    print('Exact protected-main CI evidence verified: run %d attempt %d.' % (run_id, attempt))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        # Do not echo token, URLs with unexpected content, paths, or raw API data.
        print('Hosted CI evidence preflight failed: ' + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
