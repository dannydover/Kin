"""Unwired keychain lifecycle component; never signs or uploads an app.

No workflow imports or calls this module. It must not be used with real
credentials until its caller, environment protection and security model have
been reviewed and explicitly approved. Tests inject a fake security backend.
"""
import os
import hashlib
from pathlib import Path
import re
import secrets
import signal
import stat
import subprocess
import tempfile
import threading
import uuid


class TransactionFailed(Exception):
    def __init__(self, primary_error, cleanup_errors):
        self.primary_error = primary_error
        self.cleanup_errors = tuple(cleanup_errors)
        self.primary_failed = primary_error is not None
        self.cleanup_failed = bool(cleanup_errors)
        super().__init__('Signing keychain transaction failed')


class _RequestedStop(Exception):
    pass


def _security(*args):
    # This real backend is not invoked by any checked-in workflow or test.
    # Raw tool output and argv are deliberately not printed or retained.
    subprocess.run(['/usr/bin/security', *args], check=True, timeout=20,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _remove_owned_workspace(workspace):
    # workspace is the direct mkdtemp result, never an input supplied by a caller.
    subprocess.run(['/bin/rm', '-rf', '--', str(workspace)], check=True, timeout=20,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _error_category(exc):
    if isinstance(exc, _RequestedStop):
        return 'interrupted'
    if isinstance(exc, subprocess.TimeoutExpired):
        return 'timeout'
    if isinstance(exc, subprocess.CalledProcessError):
        return 'command-failed'
    if isinstance(exc, OSError):
        return 'filesystem-error'
    if isinstance(exc, ValueError):
        return 'validation-error'
    return 'other-error'


def run_isolated(runner_temp, p12_bytes, p12_password, operation, *, backend=_security,
                 remove_workspace=_remove_owned_workspace, profile=None):
    """Run a caller operation with a disposable keychain and fail-closed cleanup.

    This component alone does not validate an environment, signing identity,
    provisioning profile, code signature, signed artifact or upload destination.
    Never invoke it with real material until those controls are implemented and
    approved. A temporary keychain password and p12 password are passed to the
    system `security` process as arguments; same-user process visibility remains
    a risk requiring review. Only a GitHub-hosted ephemeral runner is eligible.
    """
    if os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
        raise ValueError('GitHub-hosted runner required')
    if threading.current_thread() is not threading.main_thread():
        raise ValueError('Main thread required for cleanup signal handling')
    if not isinstance(p12_bytes, bytes) or not p12_bytes or not isinstance(p12_password, str) or not p12_password:
        raise ValueError('Signing material is unavailable')
    if profile is not None:
        if not isinstance(profile, dict) or set(profile) != {'directory', 'uuid', 'bytes', 'sha256'}:
            raise ValueError('Invalid profile configuration')
        profile_uuid, profile_bytes, profile_sha = profile['uuid'], profile['bytes'], profile['sha256']
        try:
            valid_uuid = isinstance(profile_uuid, str) and str(uuid.UUID(profile_uuid)).upper() == profile_uuid
        except (ValueError, AttributeError):
            valid_uuid = False
        if (not valid_uuid or not isinstance(profile_bytes, bytes) or not 0 < len(profile_bytes) <= 8 * 1024 * 1024
                or not isinstance(profile_sha, str) or not re.fullmatch(r'[0-9a-f]{64}', profile_sha)
                or hashlib.sha256(profile_bytes).hexdigest() != profile_sha):
            raise ValueError('Invalid reviewed profile')
    supplied_root = Path(runner_temp)
    if supplied_root.is_symlink():
        raise ValueError('Invalid runner temporary directory')
    try:
        root = supplied_root.resolve(strict=True)
    except (OSError, RuntimeError):
        raise ValueError('Invalid runner temporary directory') from None
    if not root.is_dir():
        raise ValueError('Invalid runner temporary directory')
    try:
        workspace = Path(tempfile.mkdtemp(prefix='kin-signing-', dir=root))
    except OSError:
        raise TransactionFailed('workspace-creation-error', ()) from None
    p12_path = workspace / 'identity.p12'
    keychain_path = workspace / 'signing.keychain-db'
    primary_error = None
    cleanup_errors = []
    attempted_create = False
    profile_dir_fd = None
    profile_identity = None
    profile_name = None
    profile_complete = False
    old_handlers = {}
    interrupted = False
    def request_stop(_signum, _frame):
        nonlocal interrupted
        if not interrupted:
            interrupted = True
            raise _RequestedStop()
    try:
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            previous = signal.getsignal(sig)
            if previous is None:
                raise ValueError('Existing signal handler cannot be restored')
            old_handlers[sig] = previous
            signal.signal(sig, request_stop)
        os.chmod(workspace, 0o700)
        if profile is not None:
            directory = Path(profile['directory'])
            if not directory.is_absolute() or directory.is_symlink() or directory.resolve(strict=True) != directory:
                raise ValueError('Invalid profile directory')
            profile_dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            directory_stat = os.fstat(profile_dir_fd)
            if directory_stat.st_uid != os.geteuid() or directory_stat.st_mode & 0o077:
                raise ValueError('Profile directory is not private and owned')
            profile_name = profile_uuid + '.mobileprovision'
            profile_fd = os.open(profile_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600, dir_fd=profile_dir_fd)
            try:
                created = os.fstat(profile_fd)
                profile_identity = (created.st_dev, created.st_ino)
                if not stat.S_ISREG(created.st_mode) or created.st_uid != os.geteuid() or created.st_nlink != 1:
                    raise ValueError('Invalid owned profile')
                view = memoryview(profile_bytes)
                while view:
                    written = os.write(profile_fd, view)
                    if written <= 0:
                        raise OSError('Profile write failed')
                    view = view[written:]
            finally:
                os.close(profile_fd)
            profile_complete = True
        keychain_password = secrets.token_urlsafe(32)
        fd = os.open(p12_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as handle:
            handle.write(p12_bytes)
        attempted_create = True
        backend('create-keychain', '-p', keychain_password, str(keychain_path))
        backend('unlock-keychain', '-p', keychain_password, str(keychain_path))
        backend('import', str(p12_path), '-k', str(keychain_path), '-P', p12_password,
                '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
        backend('set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k',
                keychain_password, str(keychain_path))
        if operation(keychain_path) is not True:
            raise ValueError('Operation did not succeed')
    except Exception as exc:
        # Preserve that the original operation failed without logging secret-bearing
        # exception text, command arguments or tool output.
        primary_error = _error_category(exc)
    finally:
        if profile_dir_fd is not None:
            if profile_identity is not None:
                try:
                    current = os.stat(profile_name, dir_fd=profile_dir_fd, follow_symlinks=False)
                    if ((current.st_dev, current.st_ino) != profile_identity or not stat.S_ISREG(current.st_mode)
                            or current.st_uid != os.geteuid() or current.st_nlink != 1):
                        cleanup_errors.append('profile:ownership-changed')
                    else:
                        check_fd = os.open(profile_name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=profile_dir_fd)
                        try:
                            opened = os.fstat(check_fd)
                            content = bytearray()
                            while len(content) <= 8 * 1024 * 1024:
                                chunk = os.read(check_fd, min(65536, 8 * 1024 * 1024 + 1 - len(content)))
                                if not chunk: break
                                content.extend(chunk)
                            latest = os.stat(profile_name, dir_fd=profile_dir_fd, follow_symlinks=False)
                            if ((opened.st_dev, opened.st_ino) != profile_identity
                                    or (latest.st_dev, latest.st_ino) != profile_identity
                                    or len(content) > 8 * 1024 * 1024
                                    or (profile_complete and hashlib.sha256(content).hexdigest() != profile_sha)):
                                cleanup_errors.append('profile:content-or-ownership-changed')
                            else:
                                os.unlink(profile_name, dir_fd=profile_dir_fd)
                                try:
                                    os.stat(profile_name, dir_fd=profile_dir_fd, follow_symlinks=False)
                                    cleanup_errors.append('profile:still-present')
                                except FileNotFoundError:
                                    pass
                        finally:
                            os.close(check_fd)
                except Exception as exc:
                    cleanup_errors.append('profile:' + _error_category(exc))
            try:
                os.close(profile_dir_fd)
            except Exception as exc:
                cleanup_errors.append('profile-directory:' + _error_category(exc))
        if attempted_create:
            try:
                backend('delete-keychain', str(keychain_path))
            except Exception as exc:
                cleanup_errors.append('keychain:' + _error_category(exc))
        try:
            remove_workspace(workspace)
            if workspace.exists() or workspace.is_symlink():
                cleanup_errors.append('workspace:StillPresent')
        except Exception as exc:
            cleanup_errors.append('workspace:' + _error_category(exc))
        for sig, handler in old_handlers.items():
            try:
                signal.signal(sig, handler)
            except (OSError, ValueError, TypeError):
                cleanup_errors.append('signal:restore-error')
    if primary_error is not None or cleanup_errors:
        raise TransactionFailed(primary_error, cleanup_errors)
    return True
