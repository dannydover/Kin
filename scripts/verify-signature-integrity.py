#!/usr/bin/env python3
"""Bounded signature-integrity check, not an identity or distribution approval.

This unwired component checks only that macOS codesign accepts the sealed app.
It does not establish the signer, certificate trust, profile, entitlements,
source, or authorization to upload. Never treat its success alone as approval.
"""
from pathlib import Path
import subprocess


class SignatureIntegrityError(Exception):
    """A sanitized failure; tool output and paths are intentionally omitted."""


def verify(app):
    path = Path(app)
    if path.is_symlink() or not path.is_dir() or path.suffix != '.app':
        raise SignatureIntegrityError('invalid app bundle')
    try:
        result = subprocess.run(
            ['/usr/bin/codesign', '--verify', '--strict', '--all-architectures', str(path)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=60, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SignatureIntegrityError('signature verification unavailable') from None
    if result.returncode != 0:
        raise SignatureIntegrityError('signature verification failed')
    return True
