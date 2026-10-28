# Referring to features in explanatory text

Use clear sentences that distinguish a named screen, setting or action from
ordinary prose. Render exact feature names in semibold, using semantic SwiftUI
`Text` attributes rather than literal Markdown, quotation styling or italics.

For example, the full sentence reads:

> After saving, find this person in linked profiles or on the All people screen.
> To also show them on your main list, turn on the Show on main list setting.

In the app, only the exact names All people and Show on main list are semibold.
The surrounding words identify the screen and setting. Do not emphasize every
ordinary noun, rename a control, or modify user-entered names and notes.

`FeatureReference` supplies localized `Text` names. Interpolate those values into
a localized full-sentence `Text`, so translation can reorder placeholders and
accessibility retains one natural reading order. `FeatureHelp` shares repeated
list-inclusion guidance. Keep ordinary descriptions such as linked profiles or
estimated ages in normal weight when they are not naming a particular control.
Nonvisual accessibility hints use the same clear names and context without raw
formatting markers. Plain-string errors may use ordinary explanatory wording
when they do not need to name a specific feature.

Canonical references include People and All people (screens), Show on main list
(setting), Friend/Family/Colleague (optional categories), and exact action names
such as Save, Cancel, Import, Import and Save, and Clear search and filters.

Review changed examples at standard and largest text. Check that their
accessibility label is the complete sentence with no markup or isolated feature
words, and that cancellation and navigation still behave as described. Automated
checks supplement the owner's quick VoiceOver/text-size review; they do not
establish a physical VoiceOver pass or a full accessibility audit.
