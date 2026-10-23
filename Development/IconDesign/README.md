# Icon artwork

The production design is the supplied G-2 reference SVG: a large clay disc,
an outlined Libre Baskerville Bold K cutout, and a smaller cream disc in front
at the lower right. [Production.svg](Production.svg) preserves the reference
320-unit geometry, gradients, rim and shadow filters at a 1024-pixel canvas.
It has no font dependency or manual corner mask. The flat PNG in
[AppIcon](../../Kin/Assets.xcassets/AppIcon.appiconset/AppIcon.png) is a faithful
SVG render prepared as opaque sRGB artwork.

## Native production layers

[Kin.icon](../../Kin/Kin.icon/icon.json) contains a native background gradient and
two independently lit foreground groups. Its reviewed source layers are
[background](../../Kin/Kin.icon/Assets/bg.svg),
[adult with K cutout](../../Kin/Kin.icon/Assets/adult.svg), and
[child](../../Kin/Kin.icon/Assets/child.svg). The background SVG records the source
geometry; the document uses its equivalent native fill for system appearances.
The installed renderer treats the first foreground group as frontmost, so Child
precedes Adult in the document. The K is subtracted with an even-odd compound
path, not rendered as a raised text layer. Native foreground shadows are enabled,
blur is zero and the renderer supplies its specular edge treatment. The flat
reference keeps the explicitly drawn rim/shadow effects instead.

Icon Composer's installed preview tool can render the document without changing
an app or signing settings. Resolve its path relative to the selected Xcode:

```sh
ICON_RENDERER="${DEVELOPER_DIR}/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$ICON_RENDERER" Kin/Kin.icon --export-preview iOS Default 1024 1024 1 Kin-preview.png
```

Run from the repository root after setting `DEVELOPER_DIR` as described in the
main README. PNG exports are review artifacts, not source replacements. Inspect
Default/Dark, TintedLight/TintedDark and ClearLight/ClearDark appearances at full and small sizes. Native
preview/simulator output does not replace physical device acceptance.

## Development artwork

[Blueprint.svg](Blueprint.svg) retains the same circle coordinates and outlined
K path, with blue gradients, a drafting grid and construction guides. It is native
vector artwork; the asset PNG is a deterministic browser render followed only by
format normalization. It is not an Apple icon copy. Dev selects its separate
[AppIconDev](../../Kin/Assets.xcassets/AppIconDev.appiconset/AppIcon.png) catalog;
its flat graphic retains the fine blueprint linework.

## Typeface license

The outlined K uses Libre Baskerville at weight 700, from the
[Google Fonts source](https://github.com/google/fonts/tree/main/ofl/librebaskerville).
Core Text created the outline directly from the project-local variable font at
that weight; no font is installed or required at runtime. The font's
[SIL Open Font License](FontLicense.md) and copyright notice are retained.
The in-app notebook illustration/logo is separate from these app-icon resources.
