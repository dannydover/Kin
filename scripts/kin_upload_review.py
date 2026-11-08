#!/usr/bin/env python3
"""Review-only uploader: the CLI is unconditionally disabled.

Do not enable until Apple tool/authentication behavior and environment controls
are verified. A nonzero exit or timeout is uncertain, never a retry signal.
"""
import os
import base64
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import uuid


def upload_once(ipa, key_id, issuer_id, key_bytes, marker_dir, *, version='', build='',
                runner=None, processor=None, timeout=900):
    """One bounded tool invocation; runner is injected only by offline tests."""
    ipa = Path(ipa)
    marker_dir = Path(marker_dir)
    if not ipa.is_file() or ipa.is_symlink():
        raise ValueError("invalid IPA")
    if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
        raise ValueError("invalid key identifier")
    if not isinstance(key_bytes, bytes) or not 0 < len(key_bytes) <= 65536:
        raise ValueError("invalid key material")
    if issuer_id:
        try:
            if str(uuid.UUID(issuer_id)) != issuer_id.lower():
                raise ValueError("non-canonical issuer identifier")
        except (ValueError, AttributeError):
            raise ValueError("invalid issuer identifier")
    if not marker_dir.is_dir() or marker_dir.is_symlink() or marker_dir.stat().st_mode & 0o077:
        raise ValueError("private marker directory required")
    marker = marker_dir / "upload-outcome"
    # Exclusive creation is deliberately before transmission. A leftover marker
    # prohibits an automatic second invocation after interruption or uncertainty.
    fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("uncertain\n"); f.flush(); os.fsync(f.fileno())
    argv = ["/usr/bin/xcrun", "altool", "--upload-app", "-f", str(ipa), "-t", "ios",
            "--apiKey", key_id, "--output-format", "xml"]
    if issuer_id: argv.extend(["--apiIssuer", issuer_id])
    execute = runner or _bounded_run
    try:
        # Apple documents this altool key location for notarization. Its use
        # for the hosted App Store upload remains unverified; the CLI is inert.
        with tempfile.TemporaryDirectory(prefix=".apple-auth-", dir=marker_dir) as home:
            key_dir = Path(home) / '.appstoreconnect' / 'private_keys'
            key_dir.mkdir(mode=0o700, parents=True)
            key_path = key_dir / ('AuthKey_' + key_id + '.p8')
            key_fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(key_fd, 'wb') as key_file: key_file.write(key_bytes)
            env = {k: os.environ[k] for k in ('PATH', 'DEVELOPER_DIR', 'TMPDIR') if k in os.environ}
            env['HOME'] = home
            result = execute(argv, timeout, env)
            processing = 'unknown'
            if result == 0 and version and build:
                try:
                    if processor is None:
                        from apple_processing_review import token, wait_for_processing
                        processing = wait_for_processing(token(key_path, key_id, issuer_id), version, build)
                    else:
                        processing = processor(key_path, key_id, issuer_id, version, build)
                except Exception:
                    processing = 'unknown'
    except Exception:
        return "uncertain"
    if result != 0:
        return "uncertain"
    # Tool success is only delivery acknowledgement; processing and byte-level
    # correspondence remain unverified and must be reconciled with Apple.
    status = {'valid': 'processing-valid-metadata-match',
              'failed': 'apple-processing-failed'}.get(processing, 'tool-success-processing-unverified')
    temp = None
    try:
        fd, temp = tempfile.mkstemp(prefix=".upload-status-", dir=marker_dir)
        with os.fdopen(fd, "w") as f:
            f.write(status + "\n"); f.flush(); os.fsync(f.fileno())
        os.replace(temp, marker)
        return status
    finally:
        if temp and os.path.exists(temp): os.unlink(temp)


def _bounded_run(argv, timeout, env=None):
    # No shell and no raw uploader logs or credentials in output. A new process
    # group allows bounded termination of children on timeout, best effort only.
    proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True, env=env)
    try:
        return proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        try: os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            proc.wait(timeout=5)
        raise


def _main():
    key_bytes = base64.b64decode(os.environ.pop('KIN_ASC_PRIVATE_KEY_P8_BASE64'), validate=True)
    result = upload_once(os.environ["KIN_VERIFIED_IPA"], os.environ["KIN_ASC_KEY_ID"],
                         os.environ.get("KIN_ASC_ISSUER_ID", ""), key_bytes,
                         os.environ["KIN_UPLOAD_EVIDENCE_DIR"],
                         version=os.environ["VERSION"], build=os.environ["BUILD"])
    if result == 'apple-processing-failed':
        raise SystemExit('Apple reports build processing failed; do not retry upload automatically.')
    if result != "processing-valid-metadata-match":
        raise SystemExit("Upload outcome uncertain; reconcile with Apple before any retry.")
    print("Apple reports a matching processed build; byte identity is unverified.")


if __name__ == "__main__":
    raise SystemExit("Upload is disabled pending explicit approval and provider verification.")
    _main()  # unreachable until the explicit guard is removed by a reviewed change
