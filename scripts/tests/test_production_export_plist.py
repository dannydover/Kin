import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ProductionArchiveTests(unittest.TestCase):
    def test_packaged_declaration(self):
        script = Path(__file__).resolve().parents[1] / "check-production-export-plist.py"
        key = "ITSAppUsesNonExemptEncryption"
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "Kin.xcarchive"
            plist = archive / "Products/Applications/Kin.app/Info.plist"
            plist.parent.mkdir(parents=True)
            for fields, passes in [
                ({key: False}, True), ({}, False), ({key: True}, False),
                ({key: "false"}, False), ({key: 0}, False),
                ({key: False, "CFBundleIdentifier": "com.intriguingideas.Kin.dev"}, False),
            ]:
                with self.subTest(fields=fields):
                    info = {"CFBundleIdentifier": "com.intriguingideas.Kin", **fields}
                    plist.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
                    result = subprocess.run(
                        [sys.executable, script, archive, "--expected", "false"],
                        capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode == 0, passes, result.stderr)
