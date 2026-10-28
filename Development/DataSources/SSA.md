# Offline first-name associations

The generator `scripts/build-name-associations.py` accepts an unmodified national
SSA ZIP and produces a deterministic JSON lookup with source SHA-256 and counts.
It pools the published M/F application counts for each exact spelling over
1940–2025 inclusive. A spelling is included only when the combined count is at
least 100 and the dominant recorded sex is at least 85%, using integer arithmetic.
There is no suppression correction, additional cohort-conflict filter, alias
expansion, transliteration or fuzzy matching.

These are recorded sex associations in Social Security card applications, not
individual identity. The editable draft default makes no claim about a person.
Manual choices always take priority and existing people are never re-inferred.
Entered names are not logged or sent to a service.

Source: [SSA national data](https://www.ssa.gov/oact/babynames/names.zip).
License: [CC0](https://creativecommons.org/publicdomain/zero/1.0/), as recorded in
[the official dataset catalog](https://catalog.data.gov/dataset/baby-names-from-social-security-card-applications-national-data).
Credit: U.S. Social Security Administration; no endorsement implied.

## Reproducible generation

```sh
python3 scripts/build-name-associations.py /path/to/names.zip Kin/Core/Resources/NameAssociations.json
```

The agreed research snapshot has SHA-256
`cd78e975ed7bb358e018dd62fbe14ced89295e9581c49172ca4eedcb011b3724`.
Its expected output is 13,373 M-associated and 22,486 F-associated spellings,
35,859 total. These are verification expectations, not forced generator counts.
If the official snapshot changes, report its actual hash and differences before
replacing a released resource.

## Verified snapshot

The approved Library transfer was independently checked on the Mac: 7,860,026
readable bytes with the SHA-256 above. Running the generator on those actual ZIP
bytes produced exactly 13,373 M-associated and 22,486 F-associated spellings,
35,859 total. The generated resource is tracked; the raw ZIP is kept in ignored
local evidence. Runtime lookup trims outer whitespace and matches case only;
case-fold collisions with conflicting associations fail closed to Unspecified.

Synthetic tests separately cover integer thresholds, annual pooling, year limits,
exact spelling independence and incomplete source failure. A bundled-resource
regression checks the full count and the agreed Michael, Mike and Chris examples.
