#!/usr/bin/env python3
"""Package complete XCTest bundles; label partial state without claiming success."""
import hashlib,json,os,sys,zipfile
from pathlib import Path
root=Path(os.environ['RUNNER_TEMP']);result=root/'KinTests.xcresult';out=root/'KinCI-retained';out.mkdir(exist_ok=True)
manifest={'status':'partial','result_sha256':None}
if result.is_dir():
    dest=out/'KinTests-xcresult.zip'
    try:
        with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,allowZip64=True) as z:
            for p in sorted(result.rglob('*')):
                if p.is_symlink():raise ValueError('symlink')
                if p.is_file():z.write(p,Path(result.name)/p.relative_to(result))
        with zipfile.ZipFile(dest) as z:
            if z.testzip():raise ValueError('invalid_zip')
        manifest['result_sha256']=hashlib.sha256(dest.read_bytes()).hexdigest()
        try:
            summary=json.loads((root/'KinTests-summary.json').read_text())
            counts=('totalTestCount','passedTests','failedTests','skippedTests')
            if (result/'Info.plist').is_file() and summary.get('result') in ('Passed','Failed') and all(type(summary.get(k)) is int for k in counts) and summary['totalTestCount']>0:
                manifest['status']='finalized'
        except (OSError,ValueError,AttributeError):pass
    except (OSError,ValueError,zipfile.BadZipFile) as e:
        dest.unlink(missing_ok=True);manifest['error_type']=type(e).__name__
for name in ('KinTests-progress.jsonl','KinTests-summary.json','KinTests-setup.json','KinTests-cleanup.json'):
    p=root/name
    if p.is_file(): (out/name).write_bytes(p.read_bytes())
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
