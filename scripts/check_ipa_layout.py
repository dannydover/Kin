#!/usr/bin/env python3
"""Conservative pre-extraction screen for this job's Xcode output only.

Not a general-purpose hostile ZIP extractor or proof of Apple acceptance.
"""
from pathlib import Path
import stat
import sys
import zipfile


def check(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 1024 ** 3:
        raise ValueError('ipa-unavailable')
    try:
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            if not 0 < len(entries) <= 10000:
                raise ValueError('entry-limit')
            seen, apps, files, total = set(), set(), set(), 0
            for item in entries:
                name = item.filename
                if (name != item.orig_filename or not name or '\\' in name or ':' in name or name.startswith('/') or
                        any(ord(c) < 32 or ord(c) == 127 for c in name)):
                    raise ValueError('unsafe-name')
                parts = name.rstrip('/').split('/')
                canonical = name.rstrip('/')
                if any(p in ('', '.', '..') for p in parts) or canonical in seen:
                    raise ValueError('unsafe-name')
                seen.add(canonical)
                mode = item.external_attr >> 16
                kind = stat.S_IFMT(mode)
                if (kind not in (0, stat.S_IFREG, stat.S_IFDIR) or
                        (item.is_dir() and kind == stat.S_IFREG) or
                        (not item.is_dir() and kind == stat.S_IFDIR) or mode & 0o7000 or
                        item.flag_bits & 1 or item.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
                    raise ValueError('unsupported-entry')
                total += item.file_size
                if total > 1024 ** 3:
                    raise ValueError('size-limit')
                if len(parts) >= 2 and parts[0] == 'Payload' and parts[1].endswith('.app'):
                    apps.add(parts[1])
                if len(parts) >= 2 and parts[0] == 'Payload' and parts[1] != 'Kin.app':
                    raise ValueError('app-layout')
                if not item.is_dir(): files.add(name)
            if apps != {'Kin.app'} or not {'Payload/Kin.app/Info.plist', 'Payload/Kin.app/Kin'} <= files:
                raise ValueError('app-layout')
    except (OSError, zipfile.BadZipFile, RuntimeError, NotImplementedError):
        raise ValueError('ipa-unavailable') from None
    return True


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2: raise ValueError('invalid-input')
        check(sys.argv[1])
    except (ValueError, OSError):
        print('IPA layout check failed.', file=sys.stderr)
        sys.exit(1)
