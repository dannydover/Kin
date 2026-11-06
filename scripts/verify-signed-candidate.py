"""Read-only local checks on a signed .app; not Apple authorization.

The caller must use an isolated, immutable workspace and owner-reviewed inputs.
Matching the supplied profile bytes does not prove the profile is active or
authorizes the entitlements. Xcode export and Apple processing are separate.
This module is not invoked by any workflow and does not sign or transmit.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import selectors
import subprocess
import time

_spec = importlib.util.spec_from_file_location('signature_integrity', Path(__file__).with_name('verify-signature-integrity.py'))
_signature = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_signature)
_evidence_spec = importlib.util.spec_from_file_location('hosted_evidence', Path(__file__).with_name('verify-hosted-ci-evidence.py'))
_evidence = importlib.util.module_from_spec(_evidence_spec)
_evidence_spec.loader.exec_module(_evidence)


class CandidateError(Exception):
    """Fixed categories only; never include paths, profile data or tool output."""


def _read_file(path, limit):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= limit:
        raise CandidateError('candidate file unavailable')
    with path.open('rb') as handle:
        data = handle.read(limit + 1)
    if len(data) > limit:
        raise CandidateError('candidate file exceeds limit')
    return data


def _entitlements(app):
    """Read at most 64 KiB from codesign; kill and reap only our own process."""
    deadline = time.monotonic() + 60
    proc = None
    primary = None
    cleanup_failed = False
    result = None
    try:
        proc = subprocess.Popen(['/usr/bin/codesign', '--display', '--entitlements', '-', '--xml', str(app)],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        output = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise CandidateError('entitlement inspection timed out')
                chunk = os.read(proc.stdout.fileno(), 65537 - len(output))
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > 65536:
                    raise CandidateError('entitlement output exceeds limit')
        remaining = deadline - time.monotonic()
        if remaining <= 0 or proc.wait(timeout=remaining) != 0:
            raise CandidateError('entitlement inspection failed')
        result = plistlib.loads(bytes(output))
    except CandidateError as exc:
        primary = exc
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.TimeoutExpired):
        primary = CandidateError('entitlement inspection unavailable')
    finally:
        if proc is not None:
            try:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                cleanup_failed = True
            finally:
                if proc.stdout is not None:
                    try:
                        proc.stdout.close()
                    except OSError:
                        cleanup_failed = True
    if primary is not None and cleanup_failed:
        raise CandidateError('entitlement inspection and process cleanup failed') from None
    if primary is not None:
        raise primary from None
    if cleanup_failed:
        raise CandidateError('entitlement process cleanup failed') from None
    return result


def _verify_candidate(app, *, team_id, certificate_sha256, profile_sha256,
                     version, build, expected_entitlements):
    """Check reviewed identity, metadata and exact claimed entitlements.

    These checks do not establish that Apple has issued or still authorizes the
    supplied profile. No caller may treat this result as release permission.
    """
    app = Path(app)
    if app.is_symlink() or not app.is_dir() or app.suffix != '.app':
        raise CandidateError('invalid app bundle')
    if not isinstance(profile_sha256, str) or not re.fullmatch(r'[0-9a-f]{64}', profile_sha256):
        raise CandidateError('invalid expected profile hash')
    if not isinstance(version, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version):
        raise CandidateError('invalid expected version')
    if not isinstance(build, str) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise CandidateError('invalid expected build')
    if not isinstance(expected_entitlements, dict) or not expected_entitlements:
        raise CandidateError('expected entitlements required')
    try:
        info = plistlib.loads(_read_file(app / 'Info.plist', 1024 * 1024))
        if not isinstance(info, dict) or any(info.get(k) != v for k, v in {
                'CFBundleIdentifier': 'com.intriguingideas.Kin', 'CFBundleExecutable': 'Kin',
                'CFBundleShortVersionString': version, 'CFBundleVersion': build}.items()):
            raise CandidateError('candidate identity mismatch')
        profile = _read_file(app / 'embedded.mobileprovision', 8 * 1024 * 1024)
        if hashlib.sha256(profile).hexdigest() != profile_sha256:
            raise CandidateError('profile hash mismatch')
        actual = _entitlements(app)
        if not isinstance(actual, dict) or actual.get('get-task-allow', False) is not False:
            raise CandidateError('invalid distribution entitlements')
        if actual.get('com.apple.developer.team-identifier') != team_id:
            raise CandidateError('entitlement team mismatch')
        app_identifier = actual.get('application-identifier')
        if not isinstance(app_identifier, str) or not re.fullmatch(r'[A-Z0-9]{10}\.com\.intriguingideas\.Kin', app_identifier):
            raise CandidateError('entitlement application identity mismatch')
        # Serialized plist comparison preserves boolean/integer distinctions.
        if plistlib.dumps(actual, fmt=plistlib.FMT_BINARY, sort_keys=True) != plistlib.dumps(expected_entitlements, fmt=plistlib.FMT_BINARY, sort_keys=True):
            raise CandidateError('entitlements differ from reviewed policy')
        if _signature.verify(app, team_id, certificate_sha256) is not True:
            raise CandidateError('signature verification failed')
    except (OSError, ValueError, TypeError, OverflowError, _signature.SignatureIntegrityError):
        raise CandidateError('candidate verification failed') from None
    return True


def verify_with_preflight(app, **reviewed_inputs):
    """Recheck exact main, CI and environment before and after local checks.

    This does not lock those systems, establish profile authorization, sign,
    upload or grant release approval. The caller must keep the app immutable.
    """
    _evidence.main()
    if _verify_candidate(app, **reviewed_inputs) is not True:
        raise CandidateError('candidate verification failed')
    _evidence.main()
    return True
