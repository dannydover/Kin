#!/usr/bin/env python3
"""Create a source-only draft; never publish or replace a tag/release.

Run only from the trusted default-branch checkout. Source files are read as data.
The GITHUB_TOKEN is used in memory and is never printed or persisted.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


class Refused(Exception):
    pass


def require(condition, message):
    if not condition:
        raise Refused(message)


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def version_tag(version):
    require(re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?', version),
            'Version must be two or three numeric components without leading zeroes.')
    parts = version.split('.')
    return 'v' + '.'.join(parts + ['0'] * (3 - len(parts)))


def project_identity(project):
    # Deliberately accept only the current literal pbxproj format. Configuration
    # inheritance/xcconfig changes require revisiting this validation, not guessing.
    blocks = re.findall(r'isa = XCBuildConfiguration;\s*buildSettings = \{([^{}]*)\};\s*name = Release;',
                        project, re.S)
    app = [b for b in blocks if re.search(
        r'PRODUCT_BUNDLE_IDENTIFIER = com\.intriguingideas\.Kin;', b)]
    require(len(app) == 1, 'Expected exactly one Kin app Release configuration.')
    values = []
    for key in ['MARKETING_VERSION', 'CURRENT_PROJECT_VERSION']:
        matches = re.findall(r'\b' + key + r' = ([0-9.]+);', app[0])
        require(len(matches) == 1, 'Release version/build must be explicit literal settings.')
        values.append(matches[0])
    return tuple(values)


class API:
    def __init__(self, repo, token):
        require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo), 'Invalid repository.')
        self.base = 'https://api.github.com/repos/' + repo
        self.token = token

    def request(self, path, data=None, missing=False):
        request = urllib.request.Request(self.base + path,
            data=None if data is None else json.dumps(data).encode(),
            headers={'Authorization': 'Bearer ' + self.token,
                     'Accept': 'application/vnd.github+json',
                     'Content-Type': 'application/json',
                     'X-GitHub-Api-Version': '2026-03-10'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404 and missing:
                return None
            # Do not echo API bodies, headers, or credential-bearing requests.
            raise Refused(f'GitHub API refused request (HTTP {error.code}); no overwrite attempted.') from None

    def pages(self, path, key=None):
        result = []
        for page in range(1, 101):
            separator = '&' if '?' in path else '?'
            response = self.request(f'{path}{separator}per_page=100&page={page}')
            items = response if key is None else response[key]
            result.extend(items)
            if len(items) < 100:
                return result
        raise Refused('Pagination limit reached; refusing incomplete validation.')

    def tag_commit(self, tag):
        ref = self.request('/git/ref/tags/' + urllib.parse.quote(tag, safe=''), missing=True)
        if ref is None:
            return None
        obj = ref['object']
        for _ in range(10):
            if obj['type'] == 'commit':
                return obj['sha']
            require(obj['type'] == 'tag', 'Tag does not resolve to a commit.')
            obj = self.request('/git/tags/' + obj['sha'])['object']
        raise Refused('Annotated tag nesting limit exceeded.')


def check_ci(api, sha):
    runs = api.pages('/actions/workflows/ci.yml/runs?' +
                     urllib.parse.urlencode({'head_sha': sha, 'event': 'push', 'branch': 'main'}),
                     'workflow_runs')
    runs = [r for r in runs if r['head_sha'] == sha and r['event'] == 'push'
            and r['head_branch'] == 'main' and r['path'] == '.github/workflows/ci.yml']
    require(runs, 'No main push CI run exists for the exact source SHA.')
    latest = max(runs, key=lambda r: (r['run_number'], r['run_attempt']))
    require(latest['status'] == 'completed' and latest['conclusion'] == 'success',
            'Latest CI attempt for the source SHA must have completed successfully.')
    jobs = api.pages(f'/actions/runs/{latest["id"]}/attempts/{latest["run_attempt"]}/jobs', 'jobs')
    validate = [j for j in jobs if j['name'] == 'validate']
    require(len(validate) == 1 and validate[0]['status'] == 'completed'
            and validate[0]['conclusion'] == 'success', 'Required validate job did not succeed.')


def prepare(api, sha, version, build, previous, main_sha):
    require(re.fullmatch(r'[0-9a-f]{40}', sha), 'Source must be a full lowercase commit SHA.')
    tag = version_tag(version)
    require(api.request('/git/ref/heads/main')['object']['sha'] == main_sha,
            'Main moved during validation; dispatch again.')
    require(re.fullmatch(r'[1-9][0-9]*', build), 'Build must be a positive integer.')
    require(git('rev-parse', sha + '^{commit}') == sha, 'Source is not an exact commit.')
    require(subprocess.run(['git', 'merge-base', '--is-ancestor', sha, main_sha],
                           capture_output=True).returncode == 0, 'Source must be on main history.')
    require(project_identity(git('show', sha + ':Kin.xcodeproj/project.pbxproj')) == (version, build),
            'Inputs differ from the source app Release version/build.')
    # Current GITHUB_TOKEN cannot authorize changes to workflows relative to main.
    require(not git('diff', sha, main_sha, '--', '.github/workflows'),
            'Source workflow files differ from current main. Use a reviewed manual release; do not add credentials.')
    check_ci(api, sha)
    releases = api.pages('/releases')  # Includes drafts with contents:write.
    matches = [r for r in releases if r['tag_name'] == tag]
    require(len(matches) <= 1, 'Multiple releases use the version tag.')
    # Also reject a noncanonical tag for the same numeric version.
    for release in releases:
        other = release['tag_name']
        if re.fullmatch(r'v[0-9]+\.[0-9]+(?:\.[0-9]+)?', other):
            require(version_tag(other[1:]) != tag or other == tag,
                    'An alternate tag already represents this public version.')
    if previous:
        require(previous != tag and previous == version_tag(previous.removeprefix('v')),
                'Previous tag must be a different canonical version tag.')
    if previous and not matches:
        prior = [r for r in releases if r['tag_name'] == previous and not r['draft']
                 and not r['prerelease']]
        require(len(prior) == 1, 'Previous tag must identify a published stable release.')
        prior_sha = api.tag_commit(previous)
        require(prior_sha and prior_sha != sha, 'Previous release must have a different source.')
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', prior_sha, sha],
                               capture_output=True).returncode == 0,
                'Previous release is not an ancestor of source.')
    elif not previous and not matches:
        require(not any(not r['draft'] and not r['prerelease'] and r['tag_name'] != tag for r in releases),
                'Supply the previous published version tag for generated notes.')
    marker = f'<!-- kin-release source={sha} version={version} build={build} previous={previous or "none"} -->'
    if tag.endswith('.0'):
        alias = tag.rsplit('.', 1)[0]
        require(api.tag_commit(alias) is None,
                'A noncanonical existing tag already represents this public version.')
    existing_sha = api.tag_commit(tag)
    require(existing_sha is None or existing_sha == sha, 'Existing version tag points to a different commit.')
    if matches:
        release = matches[0]
        require(release['target_commitish'] == sha and marker in (release['body'] or '')
                and not release['prerelease'], 'Existing release has conflicting or unverifiable identity.')
        require(existing_sha == sha or (release['draft'] and existing_sha is None),
                'Published release has no matching tag.')
        return tag, marker, release
    return tag, marker, None


def create_draft(api, sha, version, build, previous, main_sha):
    tag, marker, existing = prepare(api, sha, version, build, previous, main_sha)
    if existing:
        print('Matching release already exists; preserved without edits: ' + existing['html_url'])
        return
    notes_request = {'tag_name': tag, 'target_commitish': sha}
    if previous:
        notes_request['previous_tag_name'] = previous
    notes = api.request('/releases/generate-notes', notes_request)
    body = (f'{marker}\n\nApp Store version: **{version}** · build: **{build}**\n'
            f'Shipped source: `{sha}`\n\n'
            'Review these generated notes and confirm this version is publicly available '
            'on the App Store before publishing.\n\n' + notes['body'])
    # Repeat all checks immediately before the only write. Concurrent dispatches
    # are serialized by the workflow; API conflicts fail without update/delete.
    _, _, existing = prepare(api, sha, version, build, previous, main_sha)
    if existing:
        print('Matching release already exists; preserved without edits: ' + existing['html_url'])
        return
    release = api.request('/releases', {'tag_name': tag, 'target_commitish': sha,
        'name': f'Kin {version} (build {build})', 'body': body, 'draft': True,
        'prerelease': False, 'make_latest': 'false'})
    print('Draft created for review: ' + release['html_url'])


def main():
    require(os.environ.get('GITHUB_REPOSITORY') == 'dannydover/Kin', 'Unexpected repository.')
    require(os.environ.get('GITHUB_REF') == 'refs/heads/main', 'Dispatch this workflow on main only.')
    require(os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch', 'Manual dispatch required.')
    require(os.environ.get('GITHUB_TOKEN'), 'Ephemeral workflow token required.')
    api = API(os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_TOKEN'])
    main_sha = api.request('/git/ref/heads/main')['object']['sha']
    require(git('rev-parse', 'HEAD') == main_sha == os.environ.get('GITHUB_SHA'),
            'Main moved after dispatch; dispatch again from current main.')
    create_draft(api, os.environ['SOURCE_SHA'], os.environ['APP_VERSION'],
                 os.environ['APP_BUILD'], os.environ.get('PREVIOUS_TAG', ''), main_sha)


if __name__ == '__main__':
    try:
        main()
    except (Refused, subprocess.CalledProcessError, urllib.error.URLError) as error:
        print(f'Draft release refused: {error}', file=sys.stderr)
        sys.exit(1)
