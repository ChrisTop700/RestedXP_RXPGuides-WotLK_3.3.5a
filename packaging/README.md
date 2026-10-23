# Release contents

Player ZIPs use `git archive`. Developer tooling, tests and private local
artifacts are excluded by `.gitattributes`.

`release-exclusions.txt` lists additional **reviewed exact paths**, mirrored in
`.gitattributes`: unloaded guide sources, the dormant Classic introduction UI
and its exclusive artwork/font, and working artwork. These files remain in Git
for historical reference and deterministic builders. They are not the active
Hardcore guide families or current theme assets.

When changing exclusions, run `tests/release-archive.ps1`. The validator requires
all other tracked runtime assets and licenses, checks recursive TOC/XML
dependencies, and rejects excluded files or private artifacts in the ZIP.
An exclusion must never be inferred only from absence in a text search:
theme textures and other assets can be selected dynamically.

`Validation-Scratch335.ps1` gives offline tests invocation-owned scratch
directories. Successful work is removed; failed diagnostics are retained.
Requested reports and generated release outputs are not scratch directories.
Local cleanup archives belong under ignored `.local/cleanup-archives`, never in
Git or a player package. Cleaning local evidence does not alter live guides,
SavedVariables, or the release's guide counts.
