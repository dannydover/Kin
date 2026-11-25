"""Compare a Kin production archive with the owner's approved export answer."""
import argparse
from pathlib import Path
import plistlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--expected", required=True, choices=("true", "false"))
    args = parser.parse_args()
    path = args.archive / "Products/Applications/Kin.app/Info.plist"
    with path.open("rb") as source:
        info = plistlib.load(source)
    if info.get("CFBundleIdentifier") != "com.intriguingideas.Kin":
        raise SystemExit("Expected the production Kin bundle identifier")
    expected = args.expected == "true"
    key = "ITSAppUsesNonExemptEncryption"
    if key not in info:
        raise SystemExit(f"Archived production Info.plist is missing {key}")
    if info[key] is not expected:
        raise SystemExit(f"Expected Boolean {args.expected} for {key}")
    print("Production archive matches the supplied export declaration.")


if __name__ == "__main__":
    main()
