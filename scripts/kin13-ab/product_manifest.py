#!/usr/bin/env python3
"""Hash every archived build-product file and verify exact extraction."""
import hashlib
import json
import os
import stat
import sys
from pathlib import Path


def file_hash(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()


def manifest(root):
    root=Path(root).resolve(strict=True)
    if not root.is_dir():raise ValueError('Product root unavailable')
    entries=[]
    for p in sorted(root.rglob('*')):
        relative=p.relative_to(root).as_posix()
        if '\n' in relative or '\r' in relative:raise ValueError('Invalid product path')
        info=p.lstat();mode=stat.S_IMODE(info.st_mode)
        if p.is_symlink():
            target=os.readlink(p)
            if os.path.isabs(target) or not p.resolve(strict=True).is_relative_to(root):
                raise ValueError('Product link leaves archive')
            entries.append({'path':relative,'kind':'link','mode':mode,'target':target})
        elif p.is_file():entries.append({'path':relative,'kind':'file','mode':mode,'sha256':file_hash(p)})
        elif p.is_dir():entries.append({'path':relative,'kind':'directory','mode':mode})
        else:raise ValueError('Unsupported product type')
    if not entries:raise ValueError('Empty product archive')
    return entries


def main():
    try:
        mode,root=sys.argv[1:3]
        data=manifest(root)
        if mode=='create':print(json.dumps(data,sort_keys=True,separators=(',',':')))
        elif mode=='verify':
            expected=json.loads(Path(sys.argv[3]).read_text())
            if data!=expected:raise ValueError('Extracted products differ')
            print('KIN_AB_PRODUCT files_and_modes=verified')
        else:raise ValueError('Invalid mode')
    except (OSError,ValueError,IndexError,TypeError) as e:
        safe={'Product root unavailable','Invalid product path','Product link leaves archive',
              'Unsupported product type','Empty product archive','Extracted products differ','Invalid mode'}
        print('KIN_AB_PRODUCT failure='+type(e).__name__+' reason='+(str(e) if str(e) in safe else 'unavailable or invalid data'),file=sys.stderr)
        return 1
    return 0
if __name__=='__main__':sys.exit(main())
