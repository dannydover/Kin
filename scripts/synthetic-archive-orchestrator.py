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
import signal
import subprocess
import uuid


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_candidate = _load('candidate', 'verify-signed-candidate.py')
_keychain = _load('keychain', 'isolated-signing-keychain.py')


class BoundedProcessError(Exception):
    """Fixed-category failure; do not expose arguments or process output."""
    def __init__(self, reason, cleanup_failed=False):
        self.reason = reason
        self.cleanup_failed = cleanup_failed
        super().__init__('Bounded process failed')


def _run_bounded(command, timeout, *, cwd, env):
    """Run an owned subprocess without logs, with bounded termination/reaping.

    This helper does not authorize a command and is not wired to real signing.
    The caller must supply a restricted environment and trusted argument vector.
    Detached descendants and runner loss cannot be cleaned up by this helper.
    """
    if (not isinstance(command, (tuple, list)) or not command or
            any(not isinstance(part, str) or not part or '\x00' in part for part in command) or
            not isinstance(timeout, (int, float)) or isinstance(timeout, bool) or not 0 < timeout <= 1200 or
            not isinstance(env, dict) or not set(env).issubset({'PATH', 'HOME', 'TMPDIR', 'DEVELOPER_DIR', 'LANG', 'LC_ALL'}) or
            any(not isinstance(value, str) or '\x00' in value for value in env.values()) or
            not isinstance(cwd, (str, Path))):
        raise ValueError('Invalid bounded process input')
    try:
        directory = Path(cwd)
        if (not directory.is_absolute() or directory.is_symlink() or
                directory.resolve(strict=True) != directory or not directory.is_dir()):
            raise ValueError('Invalid bounded process directory')
    except (OSError, RuntimeError):
        raise ValueError('Invalid bounded process directory') from None
    try:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   close_fds=True, start_new_session=True, shell=False)
    except OSError:
        raise BoundedProcessError('start') from None
    try:
        code = process.wait(timeout=timeout)
    except BaseException as exc:
        cleanup_failed = False
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except OSError:
            cleanup_failed = True
        try:
            process.wait(timeout=3)
        except (subprocess.TimeoutExpired, OSError):
            cleanup_failed = True
        reason = ('timeout' if isinstance(exc, subprocess.TimeoutExpired) else
                  'interrupted' if isinstance(exc, (KeyboardInterrupt, SystemExit)) else 'wait')
        raise BoundedProcessError(reason, cleanup_failed) from None
    if code != 0:
        raise BoundedProcessError('exit')
    return True


def run_production_xcode(*_args, **_kwargs):
    """Real signing is intentionally unavailable pending reviewed integration."""
    raise BoundedProcessError('production-disabled')


def _reviewed_plan(reviewed, profile_uuid, workspace, keychain_path):
    """Construct an argument vector from validated inputs; no shell is used.

    This plan has not been proven to locate a real keychain or profile, and
    production execution remains disabled. Paths with whitespace or shell-like
    punctuation are rejected because Xcode interprets some build settings.
    """
    required = {'team_id', 'certificate_sha256', 'profile_sha256', 'version', 'build', 'expected_entitlements'}
    if not isinstance(reviewed, dict) or set(reviewed) != required:
        raise ValueError('Invalid reviewed inputs')
    team = reviewed['team_id']; entitlements = reviewed['expected_entitlements']
    if (not isinstance(team, str) or not re.fullmatch(r'[A-Z0-9]{10}', team) or
            any(not isinstance(reviewed[k], str) or not re.fullmatch(r'[0-9a-f]{64}', reviewed[k])
                for k in ('certificate_sha256', 'profile_sha256')) or
            not isinstance(reviewed['version'], str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', reviewed['version']) or
            not isinstance(reviewed['build'], str) or not re.fullmatch(r'[1-9][0-9]*', reviewed['build']) or
            not isinstance(entitlements, dict) or entitlements.get('get-task-allow', False) is not False or
            entitlements.get('application-identifier') != team + '.com.intriguingideas.Kin' or
            entitlements.get('com.apple.developer.team-identifier') != team):
        raise ValueError('Invalid reviewed identity')
    try:
        if not isinstance(profile_uuid, str) or str(uuid.UUID(profile_uuid)).upper() != profile_uuid:
            raise ValueError('Invalid profile identity')
    except (ValueError, AttributeError):
        raise ValueError('Invalid profile identity') from None
    workspace = Path(workspace); keychain_path = Path(keychain_path)
    if (not workspace.is_absolute() or not keychain_path.is_absolute() or keychain_path.parent != workspace or
            not re.fullmatch(r'/[A-Za-z0-9_./-]+', str(workspace)) or
            not re.fullmatch(r'/[A-Za-z0-9_./-]+', str(keychain_path))):
        raise ValueError('Invalid owned workspace')
    archive = workspace / 'Kin.xcarchive'; export_dir = workspace / 'export'
    options_path = workspace / 'ExportOptions.plist'
    options = {'destination': 'export', 'method': 'app-store-connect', 'signingStyle': 'manual',
               'teamID': team, 'signingCertificate': 'Apple Distribution',
               'provisioningProfiles': {'com.intriguingideas.Kin': profile_uuid}}
    settings = {'CODE_SIGN_STYLE': 'Manual', 'DEVELOPMENT_TEAM': team,
                'PROVISIONING_PROFILE_SPECIFIER': profile_uuid, 'CODE_SIGN_IDENTITY': 'Apple Distribution',
                'OTHER_CODE_SIGN_FLAGS': '--keychain ' + str(keychain_path)}
    archive_cmd = ('/usr/bin/xcodebuild', '-project', 'Kin.xcodeproj', '-scheme', 'Kin',
                   '-destination', 'generic/platform=iOS', '-configuration', 'Release',
                   '-derivedDataPath', str(workspace / 'derived'), '-archivePath', str(archive),
                   'archive') + tuple(key + '=' + value for key, value in settings.items())
    export_cmd = ('/usr/bin/xcodebuild', '-exportArchive', '-archivePath', str(archive),
                  '-exportPath', str(export_dir), '-exportOptionsPlist', str(options_path))
    return archive, export_dir, options_path, options, archive_cmd, export_cmd


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
    observation = []; keychains = []; process_failure = []

    def operation(keychain_path):
        keychains.append(keychain_path)
        workspace = keychain_path.parent
        archive, export_dir, options_path, options, archive_cmd, export_cmd = _reviewed_plan(
            reviewed, profile_uuid, workspace, keychain_path)
        with options_path.open('xb') as handle:
            plistlib.dump(options, handle)
        try:
            if runner(archive_cmd, 1200) is not True or runner(export_cmd, 600) is not True:
                raise ValueError('Synthetic build did not succeed')
        except BoundedProcessError as exc:
            reason = exc.reason if exc.reason in {'start', 'timeout', 'interrupted', 'wait', 'exit', 'production-disabled'} else 'other'
            process_failure.append((reason, exc.cleanup_failed is True))
            raise
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
    if failure is not None and process_failure:
        reason, process_cleanup_failed = process_failure[0]
        errors = failure.cleanup_errors + (('process:cleanup-failed',) if process_cleanup_failed else ())
        failure = _keychain.TransactionFailed('process:' + reason, errors)
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
