"""Unwired keychain lifecycle component; never signs or uploads an app.

No workflow imports or calls this module. It must not be used with real
credentials until its caller, environment protection and security model have
been reviewed and explicitly approved. Tests inject a fake security backend.
"""
import os
from pathlib import Path
import secrets
import signal
import subprocess
import tempfile
import threading


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
                 remove_workspace=_remove_owned_workspace):
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
