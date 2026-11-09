# ItemScore

## Behaviour

- Target WoW Forever, interface 16001. Do not restore Ascension or legacy connector compatibility.
- Keep all AtlasLoot schema knowledge in `ItemScoreSourceAtlasLoot.lua`.
- Missing Blizzard item data scores zero. Retry in bounded batches and observe late success events; never permanently blacklist an item.
- Publish catalogues atomically. A settings/version/faction mismatch must hide the previous catalogue.
- Preserve user profiles when changing the source schema. Source keys use module/content identifiers, never translated labels.
- Test production Lua with `python tests/run.py`; the installed AtlasLoot database is an integration dependency for the contract test.
- Live client verification is required before promoting a release candidate to a release. UI stubs do not prove rendering or client event delivery.

## Project Overview

ItemScore ranks items using per-character attribute weights. AtlasLoot Forever supplies item IDs and source locations; Blizzard's C_Item API supplies names, inventory slots and attributes. The runtime has no Python dependency. Version 5.0.0 is the Forever major release.

## Documentation Index

- [Forever migration and release validation](docs/forever.md): architecture, cache behavior, upgrade limits, test command and in-game acceptance checks. Documentation is German; code and developer diagnostics are English.

## Glossary

- Score: weighted sum of available item attributes; the existing two-handed weapon convention divides the score by two.
- Catalogue: deduplicated item IDs and provenance, not cached item attributes or scores.
- Source: one AtlasLoot module/content pair, selectable in Loot Sources.
- Unresolved item: Blizzard has not supplied its identity or attributes. This does not prove whether the item is unreleased, invalid, or temporarily unavailable.
