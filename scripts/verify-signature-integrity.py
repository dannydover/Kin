#!/usr/bin/env python3
"""Bounded signer and integrity checks, not distribution approval.

This unwired component checks a reviewed team and certificate fingerprint.
It does not establish profile authorization, revocation, entitlements, source,
or authorization to upload. Never treat its success alone as approval.
"""
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile


class SignatureIntegrityError(Exception):
    """A sanitized failure; tool output and paths are intentionally omitted."""


def verify(app, team_id, certificate_sha256):
    path = Path(app)
    if path.is_symlink() or not path.is_dir() or path.suffix != '.app':
        raise SignatureIntegrityError('invalid app bundle')
    if not isinstance(team_id, str) or not re.fullmatch(r'[A-Z0-9]{10}', team_id):
        raise SignatureIntegrityError('invalid expected team')
    if not isinstance(certificate_sha256, str) or not re.fullmatch(r'[0-9a-f]{64}', certificate_sha256):
        raise SignatureIntegrityError('invalid expected certificate fingerprint')
    requirement = ('=anchor apple generic and identifier "com.intriguingideas.Kin" '
                   'and certificate leaf[subject.OU] = "' + team_id + '"')
    try:
        with tempfile.TemporaryDirectory(prefix='kin-cert-check-') as directory:
            prefix = str(Path(directory) / 'cert')
            for args in (
                ['/usr/bin/codesign', '--verify', '--deep', '--strict', '--all-architectures',
                 '--test-requirement', requirement, str(path)],
                ['/usr/bin/codesign', '--display', '--extract-certificates', prefix, str(path)],
            ):
                result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, timeout=60, check=False)
                if result.returncode != 0:
                    raise SignatureIntegrityError('signature verification failed')
            leaf = Path(prefix + '0')
            if leaf.is_symlink() or not leaf.is_file() or not 0 < leaf.stat().st_size <= 65536:
                raise SignatureIntegrityError('signing certificate unavailable')
            if hashlib.sha256(leaf.read_bytes()).hexdigest() != certificate_sha256:
                raise SignatureIntegrityError('signing certificate mismatch')
    except (OSError, subprocess.TimeoutExpired):
        raise SignatureIntegrityError('signature verification unavailable') from None
    return True
