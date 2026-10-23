# Kin Dev blueprint icon

Dev selects `AppIconDev` from its separate asset catalog. Kin selects the native
`Kin.icon` document. The two configurations retain distinct bundle identifiers,
app names and ordinary app storage.

The blueprint treatment is authored in [SVG](IconDesign/Blueprint.svg) from the
same outlined Libre Baskerville K and two-disc geometry as the production design.
It uses a saturated blue field, fine grid/construction lines and stronger pale
outlines. The smaller disc stays in front. Apple's Developer app is a style
reference; no Apple symbol, tools, branding or artwork is redistributed.

[Artwork documentation](IconDesign/README.md) covers source geometry, native
production layers, licensing and preview rendering. The format-only
`normalize-dev-icon.swift` script creates an opaque square sRGB PNG and removes
its ancillary EXIF block. It does not redraw the artwork. No Python pixel editing
is used. Source artwork has no pre-rounded corner mask; iOS supplies that mask.

```sh
swift Development/normalize-dev-icon.swift approved-square.png \
  Kin/Assets.xcassets/AppIconDev.appiconset/AppIcon.png
```

Inspect artwork at full resolution and small icon sizes, verify PNG metadata,
and update the reviewed artwork hash in the repository guard after an intentional
change. Native system appearances and physical device review remain separate
from checking the source PNG. Never infer physical validation from a simulator.
