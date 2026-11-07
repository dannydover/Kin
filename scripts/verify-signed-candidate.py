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
import uuid
import zipfile
import stat

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


def _bounded_output(args, label, *, merge_stderr=False):
    """Read at most 64 KiB from one child; kill and reap only that child."""
    deadline = time.monotonic() + 60
    proc = None
    primary = None
    cleanup_failed = False
    result = None
    try:
        proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT if merge_stderr else subprocess.DEVNULL)
        output = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise CandidateError(label + ' timed out')
                chunk = os.read(proc.stdout.fileno(), 65537 - len(output))
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > 65536:
                    raise CandidateError(label + ' output exceeds limit')
        remaining = deadline - time.monotonic()
        if remaining <= 0 or proc.wait(timeout=remaining) != 0:
            raise CandidateError(label + ' failed')
        result = bytes(output)
    except CandidateError as exc:
        primary = exc
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.TimeoutExpired):
        primary = CandidateError(label + ' unavailable')
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
        raise CandidateError(label + ' and process cleanup failed') from None
    if primary is not None:
        raise primary from None
    if cleanup_failed:
        raise CandidateError(label + ' process cleanup failed') from None
    return result


def _entitlements(app):
    try:
        return plistlib.loads(_bounded_output(
            ['/usr/bin/codesign', '--display', '--entitlements', '-', '--xml', str(app)],
            'entitlement inspection'))
    except (ValueError, plistlib.InvalidFileException):
        raise CandidateError('entitlement inspection unavailable') from None


def _binary_uuid(path):
    if path.is_symlink() or not path.is_file():
        raise CandidateError('binary or dSYM unavailable')
    data = _bounded_output(['/usr/bin/xcrun', 'dwarfdump', '--uuid', str(path)], 'UUID inspection')
    try:
        lines = data.decode('utf-8').splitlines()
        if len(lines) != 1:
            raise ValueError('unexpected architecture count')
        match = re.fullmatch(r'UUID: ([0-9A-Fa-f-]{36}) \(arm64\) .+', lines[0])
        if match is None:
            raise ValueError('invalid UUID output')
        parsed = str(uuid.UUID(match.group(1))).upper()
        if parsed != match.group(1).upper():
            raise ValueError('noncanonical UUID')
        return parsed
    except (UnicodeError, ValueError):
        raise CandidateError('invalid arm64 UUID evidence') from None


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


def _binary_hash(path):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 1024 * 1024 * 1024:
        raise CandidateError('binary unavailable')
    digest = hashlib.sha256(); size = 0
    with path.open('rb') as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk: break
            size += len(chunk)
            if size > 1024 * 1024 * 1024:
                raise CandidateError('binary exceeds limit')
            digest.update(chunk)
    return digest.hexdigest()


def verify_archive_export_with_preflight(archive, exported_app, **reviewed_inputs):
    """Compare signed archive/export app and dSYM under the read-only preflight.

    The caller must keep every path immutable. This does not run Xcode, prove
    either app came from the source, validate the IPA container or establish
    profile authorization. The returned observation is not an attestation.
    """
    archive = Path(archive); exported_app = Path(exported_app)
    if archive.is_symlink() or not archive.is_dir() or archive.suffix != '.xcarchive':
        raise CandidateError('invalid archive')
    archive_app = archive / 'Products/Applications/Kin.app'
    binary = archive_app / 'Kin'; exported_binary = exported_app / 'Kin'
    dsym = archive / 'dSYMs/Kin.app.dSYM/Contents/Resources/DWARF/Kin'
    _evidence.main()
    source = os.environ.get('GITHUB_SHA', '')
    tree = _evidence.command('git', 'rev-parse', 'HEAD^{tree}')
    if not re.fullmatch(r'[0-9a-f]{40}', source) or not re.fullmatch(r'[0-9a-f]{40}', tree):
        raise CandidateError('invalid source identity')
    if _verify_candidate(archive_app, **reviewed_inputs) is not True:
        raise CandidateError('archive app verification failed')
    if _verify_candidate(exported_app, **reviewed_inputs) is not True:
        raise CandidateError('exported app verification failed')
    binary_id = _binary_uuid(binary)
    if _binary_uuid(exported_binary) != binary_id or _binary_uuid(dsym) != binary_id:
        raise CandidateError('archive, export and dSYM UUID mismatch')
    archive_hash = _binary_hash(binary); export_hash = _binary_hash(exported_binary)
    _evidence.main()
    if _evidence.command('git', 'rev-parse', 'HEAD^{tree}') != tree:
        raise CandidateError('source tree changed')
    return {'kind': 'local-observation-not-build-attestation', 'source_sha': source,
            'source_tree': tree, 'architecture': 'arm64', 'uuid': binary_id,
            'archive_binary_sha256': archive_hash, 'export_binary_sha256': export_hash}


def verify_ipa_payload(ipa, exported_app):
    """Fail closed unless the IPA's sole app payload matches the inspected app.

    The caller must keep inputs immutable. This checks content, not file modes,
    Apple acceptance, or provenance. It does not extract or execute the IPA.
    """
    ipa = Path(ipa); exported_app = Path(exported_app)
    limit = 1024 * 1024 * 1024
    if ipa.is_symlink() or not ipa.is_file() or not 0 < ipa.stat().st_size <= limit:
        raise CandidateError('IPA unavailable')
    if exported_app.is_symlink() or not exported_app.is_dir() or exported_app.name != 'Kin.app':
        raise CandidateError('exported app unavailable')
    try:
        expected = {}
        for root, dirs, files in os.walk(exported_app, followlinks=False):
            for name in dirs:
                if (Path(root) / name).is_symlink():
                    raise CandidateError('app symlink unsupported')
            for name in files:
                path = Path(root) / name
                if path.is_symlink() or not path.is_file():
                    raise CandidateError('app file unsupported')
                relative = path.relative_to(exported_app).as_posix()
                if len(expected) >= 10000:
                    raise CandidateError('app entry limit')
                expected[relative] = path
        if not expected:
            raise CandidateError('empty app')
        found = set(); total = 0
        with zipfile.ZipFile(ipa) as archive:
            infos = archive.infolist()
            if len(infos) > 10000:
                raise CandidateError('IPA entry limit')
            seen = set()
            for info in infos:
                name = info.filename
                parts = name.rstrip('/').split('/')
                if not name or name in seen or '\\' in name or any(p in ('', '.', '..') for p in parts):
                    raise CandidateError('invalid IPA entry')
                seen.add(name)
                mode = (info.external_attr >> 16) & 0xffff
                kind = stat.S_IFMT(mode)
                if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
                    raise CandidateError('unsupported IPA entry')
                if info.is_dir():
                    continue
                if not name.startswith('Payload/Kin.app/'):
                    raise CandidateError('unexpected IPA content')
                relative = name[len('Payload/Kin.app/'):]
                if relative not in expected or relative in found:
                    raise CandidateError('unexpected IPA payload')
                total += info.file_size
                if total > limit or info.file_size != expected[relative].stat().st_size:
                    raise CandidateError('IPA size mismatch')
                digest = hashlib.sha256()
                with archive.open(info) as item:
                    while True:
                        chunk = item.read(1024 * 1024)
                        if not chunk: break
                        digest.update(chunk)
                local = hashlib.sha256()
                with expected[relative].open('rb') as item:
                    while True:
                        chunk = item.read(1024 * 1024)
                        if not chunk: break
                        local.update(chunk)
                if digest.digest() != local.digest():
                    raise CandidateError('IPA content mismatch')
                found.add(relative)
        if found != set(expected):
            raise CandidateError('IPA payload incomplete')
        return _binary_hash(ipa)
    except (OSError, ValueError, zipfile.BadZipFile, RuntimeError, EOFError, NotImplementedError):
        raise CandidateError('IPA inspection failed') from None


def verify_archive_export_ipa_with_preflight(archive, exported_app, ipa, **reviewed_inputs):
    observation = verify_archive_export_with_preflight(archive, exported_app, **reviewed_inputs)
    ipa_hash = verify_ipa_payload(ipa, exported_app)
    _evidence.main()
    if _evidence.command('git', 'rev-parse', 'HEAD^{tree}') != observation['source_tree']:
        raise CandidateError('source tree changed')
    return dict(observation, ipa_sha256=ipa_hash)
