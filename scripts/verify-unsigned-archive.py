#!/usr/bin/env python3
"""Fail-closed local unsigned archive verification; write only public-safe metadata.

This is not a signature, upload, delivery or binary-reproducibility attestation.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'com.intriguingideas.Kin'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def parse_uuids(output):
    found = []
    for line in output.splitlines():
        match = re.fullmatch(r'UUID: ([0-9A-Fa-f-]{36}) \(([A-Za-z0-9_]+)\) .+', line)
        require(match is not None, 'Unexpected UUID output')
        try:
            canonical = str(uuid.UUID(match.group(1))).upper()
        except ValueError as exc:
            raise ValueError('Invalid UUID') from exc
        require(canonical == match.group(1).upper(), 'Noncanonical UUID')
        found.append((match.group(2), canonical))
    require(found and len(found) == len(set(found)), 'Missing or duplicate UUIDs')
    require(len({arch for arch, _ in found}) == len(found), 'Duplicate architecture')
    return sorted(found)


def validate_metadata(app, archive, version, build, sdk, sdk_build, xcode_build, binary_uuids, dsym_uuids):
    require(isinstance(app, dict) and isinstance(archive, dict), 'Malformed plist')
    require(re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', sdk) is not None, 'Invalid SDK')
    require(re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', version) is not None, 'Invalid version')
    require(re.fullmatch(r'[1-9][0-9]*', build) is not None, 'Invalid build')
    expected = {'CFBundleIdentifier': BUNDLE, 'CFBundleShortVersionString': version,
                'CFBundleVersion': build}
    for key, value in expected.items():
        require(app.get(key) == value, 'App identity mismatch: ' + key)
    require(app.get('CFBundleExecutable') == 'Kin', 'Unexpected app executable')
    require(app.get('DTPlatformName') == 'iphoneos', 'Unexpected app platform')
    require(app.get('DTSDKName') == 'iphoneos' + sdk, 'SDK does not match app metadata')
    require(re.fullmatch(r'[A-Za-z0-9]+', sdk_build) is not None and app.get('DTSDKBuild') == sdk_build, 'SDK build mismatch')
    require(re.fullmatch(r'[A-Za-z0-9]+', xcode_build) is not None and app.get('DTXcodeBuild') == xcode_build, 'Xcode build mismatch')
    properties = archive.get('ApplicationProperties')
    require(isinstance(properties, dict), 'Missing archive application properties')
    for key, value in expected.items():
        require(properties.get(key) == value, 'Archive identity mismatch: ' + key)
    require(properties.get('ApplicationPath') == 'Applications/Kin.app', 'Unexpected archive app path')
    require(properties.get('Architectures') == ['arm64'], 'Unexpected archive metadata architecture')
    require(not properties.get('SigningIdentity') and not properties.get('Team'),
            'Archive contains signing identity metadata')
    require(binary_uuids and binary_uuids == dsym_uuids, 'Executable and dSYM UUIDs do not match')
    require({arch for arch, _ in binary_uuids} == {'arm64'}, 'Unexpected archive architecture')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()


def main():
    require(len(sys.argv) == 3, 'Expected archive path and manifest path')
    archive = Path(sys.argv[1]); output = Path(sys.argv[2]); app = archive / 'Products/Applications/Kin.app'
    # Invalidate an earlier result before verification, never publish stale evidence.
    output.unlink(missing_ok=True)
    head = run('git', 'rev-parse', 'HEAD'); tree = run('git', 'rev-parse', 'HEAD^{tree}')
    app_tree = run('git', 'rev-parse', 'HEAD:Kin')
    for value in (head, tree, app_tree):
        require(re.fullmatch(r'[0-9a-f]{40}', value) is not None, 'Invalid source identity')
    require(head == os.environ.get('GITHUB_SHA'), 'Checkout does not match event commit')
    require(not run('git', 'status', '--porcelain'), 'Checkout is not clean')
    spec = importlib.util.spec_from_file_location('release', ROOT / 'scripts/draft-release.py')
    release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
    version, build = release.project_identity((ROOT / 'Kin.xcodeproj/project.pbxproj').read_text())
    toolchain = run('xcodebuild', '-version').splitlines()
    require(len(toolchain) == 2 and re.fullmatch(r'Xcode [0-9]+(?:\.[0-9]+)+', toolchain[0])
            and re.fullmatch(r'Build version [A-Za-z0-9]+', toolchain[1]), 'Invalid Xcode identity')
    sdk = run('xcodebuild', '-version', '-sdk', 'iphoneos', 'SDKVersion')
    sdk_build = run('xcodebuild', '-version', '-sdk', 'iphoneos', 'ProductBuildVersion')
    xcode_build = toolchain[1].removeprefix('Build version ')
    binary = app / 'Kin'; dsym = archive / 'dSYMs/Kin.app.dSYM/Contents/Resources/DWARF/Kin'
    app_info = plistlib.loads((app / 'Info.plist').read_bytes())
    archive_info = plistlib.loads((archive / 'Info.plist').read_bytes())
    binary_uuids = parse_uuids(run('xcrun', 'dwarfdump', '--uuid', str(binary)))
    dsym_uuids = parse_uuids(run('xcrun', 'dwarfdump', '--uuid', str(dsym)))
    validate_metadata(app_info, archive_info, version, build, sdk, sdk_build, xcode_build, binary_uuids, dsym_uuids)
    subprocess.run([sys.executable, str(ROOT / 'scripts/check-release.py'), str(app)],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    manifest = {'kind': 'unsigned-archive-exercise', 'checkout_sha': head, 'checkout_tree': tree,
                'app_source_tree': app_tree, 'xcode': toolchain[0], 'xcode_build': toolchain[1],
                'iphoneos_sdk': sdk, 'iphoneos_sdk_build': sdk_build, 'bundle_id': BUNDLE, 'version': version, 'build': build,
                'executable_sha256': sha(binary), 'dsym_sha256': sha(dsym),
                'architectures': [arch for arch, _ in binary_uuids],
                'uuids': [{'architecture': arch, 'uuid': value} for arch, value in binary_uuids],
                'signed': False, 'uploaded': False}
    tmp = output.with_suffix(output.suffix + '.tmp')
    tmp.write_text(json.dumps(manifest, indent=2) + '\n'); tmp.replace(output)
    print('Unsigned archive identity, release checks, and dSYM match verified.')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        # Do not print raw commands, paths or tool output in public CI logs.
        print('Unsigned archive verification failed:', type(exc).__name__, file=sys.stderr)
        sys.exit(1)
