"""Synthetic-only control-flow exercise; never pass real signing material.

This module has no CLI and is not used by a workflow. The injected runner and
security backend MUST be fakes; commands are plans, not authorization to execute
them. This is not a production signing workflow or build attestation.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import uuid


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_candidate = _load('candidate', 'verify-signed-candidate.py')
_keychain = _load('keychain', 'isolated-signing-keychain.py')


def run_synthetic(runner_temp, profile_directory, *, runner, security_backend, cleanup_check):
    """Exercise control flow with fixed fake credentials and injected fakes.

    Each planned command has a requested deadline; enforcement is the injected
    runner's responsibility. Real subprocess execution is not implemented.
    The workspace and synthetic IPA are removed before a result is returned.
    """
    if not callable(runner) or not callable(security_backend) or not callable(cleanup_check):
        raise ValueError('Synthetic fakes required')
    source = os.environ.get('GITHUB_SHA', '')
    if not re.fullmatch(r'[0-9a-f]{40}', source):
        raise ValueError('Invalid source identity')
    team = 'ABCDEFGHIJ'
    profile_bytes = b'kin-synthetic-profile-only'
    profile_sha = hashlib.sha256(profile_bytes).hexdigest()
    profile_uuid = str(uuid.UUID(int=1)).upper()
    directory = Path(profile_directory)
    if not directory.is_absolute() or directory.is_symlink() or directory.resolve(strict=True) != directory:
        raise ValueError('Invalid synthetic profile directory')
    profile = {'directory': str(directory), 'uuid': profile_uuid,
               'bytes': profile_bytes, 'sha256': profile_sha}
    reviewed = {'team_id': team, 'certificate_sha256': 'a' * 64, 'profile_sha256': profile_sha,
                'version': '1.3.0', 'build': '7', 'expected_entitlements': {
                    'application-identifier': team + '.com.intriguingideas.Kin',
                    'com.apple.developer.team-identifier': team, 'get-task-allow': False}}
    _candidate._evidence.main()
    tree = _candidate._evidence.command('git', 'rev-parse', 'HEAD^{tree}')
    if not re.fullmatch(r'[0-9a-f]{40}', tree):
        raise ValueError('Invalid source tree')
    observation = []; keychains = []

    def operation(keychain_path):
        keychains.append(keychain_path)
        workspace = keychain_path.parent
        archive = workspace / 'Kin.xcarchive'
        export_dir = workspace / 'export'
        options_path = workspace / 'ExportOptions.plist'
        options = {'destination': 'export', 'method': 'app-store-connect', 'signingStyle': 'manual',
                   'teamID': team, 'signingCertificate': 'Apple Distribution',
                   'provisioningProfiles': {'com.intriguingideas.Kin': profile_uuid}}
        with options_path.open('xb') as handle:
            plistlib.dump(options, handle)
        archive_cmd = ('/usr/bin/xcodebuild', '-project', 'Kin.xcodeproj', '-scheme', 'Kin',
                       '-destination', 'generic/platform=iOS', '-configuration', 'Release',
                       '-derivedDataPath', str(workspace / 'derived'), '-archivePath', str(archive),
                       'archive', 'CODE_SIGN_STYLE=Manual')
        export_cmd = ('/usr/bin/xcodebuild', '-exportArchive', '-archivePath', str(archive),
                      '-exportPath', str(export_dir), '-exportOptionsPlist', str(options_path))
        if runner(archive_cmd, 1200) is not True or runner(export_cmd, 600) is not True:
            raise ValueError('Synthetic build did not succeed')
        value = _candidate.verify_archive_export_ipa_with_preflight(
            archive, export_dir / 'Payload/Kin.app', export_dir / 'Kin.ipa', **reviewed)
        if value.get('source_sha') != source or value.get('source_tree') != tree:
            raise ValueError('Observed source changed')
        observation.append(value)
        return True

    failure = None
    try:
        _keychain.run_isolated(runner_temp, b'kin-synthetic-identity-only', 'kin-synthetic-password-only',
                               operation, backend=security_backend, profile=profile)
    except _keychain.TransactionFailed as exc:
        failure = exc
    try:
        verified = (len(keychains) == 1 and
                    cleanup_check(keychains[0], Path(profile_directory) / (profile_uuid + '.mobileprovision')) is True)
    except Exception:
        verified = False
    if failure is not None:
        if not verified:
            raise _keychain.TransactionFailed(failure.primary_error,
                                              failure.cleanup_errors + ('independent-cleanup:unverified',)) from None
        raise failure
    if not verified:
        raise ValueError('Synthetic cleanup could not be independently verified')
    _candidate._evidence.main()
    if (os.environ.get('GITHUB_SHA') != source or
            _candidate._evidence.command('git', 'rev-parse', 'HEAD^{tree}') != tree or len(observation) != 1):
        raise ValueError('Source or synthetic output changed')
    return dict(observation[0], kind='synthetic-control-flow-not-build-attestation')
