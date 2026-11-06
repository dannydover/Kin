#!/usr/bin/env python3
"""Emit the one verified archive-relative xctestrun path for GitHub's env file."""
import re
import sys
from pathlib import Path
root=Path(sys.argv[1]).resolve(strict=True)
items=list(root.glob('*.xctestrun'))
if len(items)!=1 or not items[0].is_file() or items[0].is_symlink():
    sys.exit('KIN_AB_PRODUCT invalid xctestrun count')
path=str(items[0].resolve())
if '\n' in path or '\r' in path or not path.startswith(str(root)+'/'):
    sys.exit('KIN_AB_PRODUCT invalid xctestrun path')
print('KIN_AB_XCTESTRUN='+path)
