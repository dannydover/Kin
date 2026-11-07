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
import shlex
import signal
import stat
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


class SecuritySearchList:
    """Bounded local security-tool adapter; never invoked by a workflow here.

    List contents stay in memory. Concurrent same-user mutations remain a
    race, so this is only suitable for a reviewed isolated runner. Calling
    write changes that user's settings and needs the future signing approval.
    """
    def read(self):
        try:
            data = _candidate._bounded_output(['/usr/bin/security', 'list-keychains', '-d', 'user'],
                                              'keychain list')
            return _keychain._validated_search_list(shlex.split(data.decode('utf-8')))
        except Exception:
            raise ValueError('Keychain list unavailable') from None

    def write(self, paths):
        try:
            paths = _keychain._validated_search_list(paths)
            _keychain._security('list-keychains', '-d', 'user', '-s', *paths)
        except Exception:
            raise ValueError('Keychain list update failed') from None


def _checkout_snapshot(source_directory, expected_sha):
    """Observe a clean exact checkout and reject known unpinned build inputs.

    This is not a filesystem lock or build attestation. Same-user changes and
    compiler/SDK, generated and other external inputs require separate controls.
    """
    source = Path(source_directory)
    if (not source.is_absolute() or source.is_symlink() or source.resolve(strict=True) != source or
            any(ord(char) < 32 or ord(char) == 127 for char in str(source)) or
            not source.is_dir() or not isinstance(expected_sha, str) or
            not re.fullmatch(r'[0-9a-f]{40}', expected_sha)):
        raise ValueError('Invalid source checkout')
    env = {'PATH': '/usr/bin:/bin', 'HOME': '/tmp', 'LC_ALL': 'C',
           'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_TERMINAL_PROMPT': '0'}
    prefix = ['/usr/bin/git', '-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false',
              '-c', 'core.hooksPath=/dev/null', '-C', str(source)]
    def git(*args):
        return _candidate._bounded_output(prefix + list(args), 'source inspection', cwd=str(source), env=env)
    try:
        head = git('rev-parse', 'HEAD').decode('ascii').strip()
        tree = git('rev-parse', 'HEAD^{tree}').decode('ascii').strip()
        top = git('rev-parse', '--show-toplevel').decode('utf-8').strip()
    except UnicodeError:
        raise ValueError('Source identity unavailable') from None
    if head != expected_sha or not re.fullmatch(r'[0-9a-f]{40}', tree) or top != str(source):
        raise ValueError('Source checkout identity differs')
    entries = git('ls-files', '--stage', '-z').split(b'\0'); schemes = []
    for entry in entries:
        if not entry: continue
        meta, separator, name = entry.partition(b'\t')
        fields = meta.split(b' ')
        if (not separator or len(fields) != 3 or fields[0] not in (b'100644', b'100755') or fields[2] != b'0' or
                b'\\' in name or any(part in (b'', b'.', b'..') for part in name.split(b'/')) or
                any(byte < 32 or byte == 127 for byte in name) or
                name.endswith(b'.xcconfig') or
                name.rsplit(b'/', 1)[-1] in (b'.gitattributes', b'.gitmodules', b'Package.resolved', b'Podfile', b'Cartfile')):
            raise ValueError('Unsupported source input')
        if name.endswith(b'.xcscheme'):
            try: schemes.append(name.decode('utf-8'))
            except UnicodeError: raise ValueError('Unsupported source input') from None
    index_flags = [entry for entry in git('ls-files', '-v', '-z').split(b'\0') if entry]
    if len(index_flags) != len([entry for entry in entries if entry]) or any(not entry.startswith(b'H ') for entry in index_flags):
        raise ValueError('Unsupported source index flags')
    if git('status', '--porcelain=v1', '--untracked-files=all', '--ignored=matching'):
        raise ValueError('Source checkout changed or is not clean')
    project = _candidate._read_file(source / 'Kin.xcodeproj/project.pbxproj', 5 * 1024 * 1024)
    if any(marker in project for marker in (b'PBXShellScriptBuildPhase', b'XCRemoteSwiftPackageReference',
                                             b'XCLocalSwiftPackageReference', b'XCSwiftPackageProductDependency',
                                             b'PBXBuildRule', b'baseConfigurationReference', b'-load-plugin',
                                             b'sourceTree = "<absolute>"', b'../')):
        raise ValueError('Unsupported project build inputs')
    for name in schemes:
        scheme = _candidate._read_file(source / name, 2 * 1024 * 1024)
        if any(marker in scheme for marker in (b'<ExecutionAction', b'<PreActions', b'<PostActions', b'scriptText=')):
            raise ValueError('Unsupported scheme build inputs')
    return {'source_sha': head, 'source_tree': tree}


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
                   '-skipPackageUpdates', '-disableAutomaticPackageResolution',
                   'archive') + tuple(key + '=' + value for key, value in settings.items())
    export_cmd = ('/usr/bin/xcodebuild', '-exportArchive', '-archivePath', str(archive),
                  '-exportPath', str(export_dir), '-exportOptionsPlist', str(options_path))
    return archive, export_dir, options_path, options, archive_cmd, export_cmd


def _verify_owned_cleanup(keychain_path, profile_path):
    """Independently observe absence in private owned parent directories."""
    keychain = Path(keychain_path); profile = Path(profile_path)
    try:
        if (not keychain.is_absolute() or keychain.name != 'signing.keychain-db' or
                not profile.is_absolute() or profile.suffix != '.mobileprovision'):
            return False
        for directory in (keychain.parent.parent, profile.parent):
            info = directory.lstat()
            if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077 or
                    directory.resolve(strict=True) != directory):
                return False
        for path in (keychain.parent, keychain, profile):
            try: path.lstat()
            except FileNotFoundError: continue
            return False
        return True
    except (OSError, RuntimeError):
        return False


def run_synthetic(runner_temp, profile_directory, *, runner, security_backend, cleanup_check, search_list):
    """Exercise control flow with fixed fake credentials and injected fakes.

    Each planned command has a requested deadline; enforcement is the injected
    runner's responsibility. Real subprocess execution is not implemented.
    The workspace and synthetic IPA are removed before a result is returned.
    """
    if (not callable(runner) or not callable(security_backend) or not callable(cleanup_check) or
            not callable(getattr(search_list, 'read', None)) or not callable(getattr(search_list, 'write', None))):
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
    result = _execute_controlled(runner_temp, profile, reviewed, b'kin-synthetic-identity-only',
                                 'kin-synthetic-password-only', runner=runner, security_backend=security_backend,
                                 cleanup_check=cleanup_check, search_list=search_list,
                                 runner_env={'PATH': '/usr/bin:/bin'})
    return dict(result, kind='synthetic-control-flow-not-build-attestation')


def _execute_controlled(runner_temp, profile, reviewed, identity_bytes, identity_password, *,
                        runner, security_backend, cleanup_check, search_list, runner_env):
    """Shared transaction flow; not an authorization boundary or workflow.

    Only synthetic inputs are used by this repository. Production entry remains
    disabled until its execution gate, environment, delivery and real behavior
    are reviewed. Output is destroyed with the temporary workspace.
    """
    if (not callable(runner) or not callable(security_backend) or not callable(cleanup_check) or
            not callable(getattr(search_list, 'read', None)) or not callable(getattr(search_list, 'write', None)) or
            not isinstance(profile, dict) or set(profile) != {'directory', 'uuid', 'bytes', 'sha256'} or
            not isinstance(profile['directory'], str) or
            not isinstance(profile['bytes'], bytes) or not 0 < len(profile['bytes']) <= 8 * 1024 * 1024 or
            not isinstance(reviewed, dict) or profile['sha256'] != reviewed.get('profile_sha256') or
            hashlib.sha256(profile['bytes']).hexdigest() != profile['sha256'] or
            not isinstance(identity_bytes, bytes) or not 0 < len(identity_bytes) <= 8 * 1024 * 1024 or
            not isinstance(identity_password, str) or not 0 < len(identity_password) <= 1024 or '\x00' in identity_password or
            not isinstance(runner_env, dict) or runner_env.get('PATH') != '/usr/bin:/bin' or
            not set(runner_env).issubset({'PATH', 'HOME', 'TMPDIR', 'DEVELOPER_DIR', 'LANG', 'LC_ALL'}) or
            any(not isinstance(value, str) or '\x00' in value for value in runner_env.values())):
        raise ValueError('Invalid controlled inputs')
    if (identity_bytes != b'kin-synthetic-identity-only' or identity_password != 'kin-synthetic-password-only' or
            profile['bytes'] != b'kin-synthetic-profile-only'):
        raise BoundedProcessError('production-disabled')
    profile_uuid = profile['uuid']; profile_directory = profile['directory']
    directory = Path(profile_directory)
    if not directory.is_absolute() or directory.is_symlink() or directory.resolve(strict=True) != directory:
        raise ValueError('Invalid profile directory')
    _reviewed_plan(reviewed, profile_uuid, Path('/synthetic/workspace'), Path('/synthetic/workspace/keychain'))
    source = os.environ.get('GITHUB_SHA', '')
    if not re.fullmatch(r'[0-9a-f]{40}', source):
        raise ValueError('Invalid source identity')
    _candidate._evidence.main()
    source_directory = str(Path.cwd().resolve(strict=True))
    checkout = _checkout_snapshot(source_directory, source)
    original_search = _keychain._validated_search_list(search_list.read())
    tree = _candidate._evidence.command('git', 'rev-parse', 'HEAD^{tree}')
    if not re.fullmatch(r'[0-9a-f]{40}', tree) or checkout['source_tree'] != tree:
        raise ValueError('Invalid source tree')
    observation = []; keychains = []; process_failure = []; artifact_failure = []

    def operation(keychain_path):
        keychains.append(keychain_path)
        workspace = keychain_path.parent
        archive, export_dir, options_path, options, archive_cmd, export_cmd = _reviewed_plan(
            reviewed, profile_uuid, workspace, keychain_path)
        with options_path.open('xb') as handle:
            plistlib.dump(options, handle)
        try:
            if (runner(archive_cmd, 1200, cwd=source_directory, env=runner_env) is not True or
                    runner(export_cmd, 600, cwd=source_directory, env=runner_env) is not True):
                raise ValueError('Controlled build did not succeed')
        except BoundedProcessError as exc:
            reason = exc.reason if exc.reason in {'start', 'timeout', 'interrupted', 'wait', 'exit', 'production-disabled'} else 'other'
            process_failure.append((reason, exc.cleanup_failed is True))
            raise
        try:
            ipa = export_dir / 'Kin.ipa'
            ipa_hash = _candidate._binary_hash(ipa)
            inspected_app = _candidate.extract_ipa_for_inspection(ipa, workspace)
            value = _candidate.verify_archive_export_ipa_with_preflight(archive, inspected_app, ipa, **reviewed)
            if value.get('ipa_sha256') != ipa_hash:
                raise ValueError('IPA changed during inspection')
        except (_candidate.CandidateError, OSError, ValueError):
            artifact_failure.append(True)
            raise
        if value.get('source_sha') != source or value.get('source_tree') != tree:
            raise ValueError('Observed source changed')
        observation.append(value)
        return True

    failure = None
    try:
        _keychain.run_isolated(runner_temp, identity_bytes, identity_password,
                               operation, backend=security_backend, profile=profile, search_list=search_list)
    except _keychain.TransactionFailed as exc:
        failure = exc
    if failure is not None and process_failure:
        reason, process_cleanup_failed = process_failure[0]
        errors = failure.cleanup_errors + (('process:cleanup-failed',) if process_cleanup_failed else ())
        failure = _keychain.TransactionFailed('process:' + reason, errors)
    elif failure is not None and artifact_failure:
        failure = _keychain.TransactionFailed('artifact:verification', failure.cleanup_errors)
    try:
        profile_path = Path(profile_directory) / (profile_uuid + '.mobileprovision')
        verified = (len(keychains) == 1 and _verify_owned_cleanup(keychains[0], profile_path) and
                    _keychain._validated_search_list(search_list.read()) == original_search and
                    cleanup_check(keychains[0], profile_path) is True)
    except Exception:
        verified = False
    if failure is not None:
        if not verified:
            raise _keychain.TransactionFailed(failure.primary_error,
                                              failure.cleanup_errors + ('independent-cleanup:unverified',)) from None
        raise failure
    if not verified:
        raise ValueError('Cleanup could not be independently verified')
    _candidate._evidence.main()
    if (os.environ.get('GITHUB_SHA') != source or
            _candidate._evidence.command('git', 'rev-parse', 'HEAD^{tree}') != tree or
            _checkout_snapshot(source_directory, source) != checkout or len(observation) != 1):
        raise ValueError('Source or output changed')
    return dict(observation[0], kind='controlled-observation-not-build-attestation')
