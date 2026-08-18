# AGENTS.md

## 1. Behaviour
- Keep implementation compatible with WoW 3.3.5a (`Interface: 30300`) APIs.
- Prioritize simple, explicit Lua code with clear addon-level module boundaries.
- Preserve the additive profile-based scoring model (stat weights per profile).
- Prefer deterministic UI and score behavior over implicit fallbacks.
- Treat external loot providers (`LootCollector`, `AtlasLoot`) as optional; never hard-fail when absent.
- Keep async callback dispatch reentrancy-safe (callbacks may enqueue new callbacks while running).
- Keep background work schedulers single-shot (avoid combining immediate and queued refresh triggers for the same action).
- Bump `## Version:` in `ItemScore.toc` whenever addon code changes are made for release.
- Treat AtlasLoot dungeon/raid difficulty limits as cache-time filters because they change collected item IDs.
- Store the user's requested Mythic+ cap without an upper input clamp; provider metadata or missing difficulty IDs define the effective collected maximum.
- Initialize focus-sensitive loot-source fields from per-character SavedVariables before installing edit handlers; preserve only drafts that were actually edited, and reset the horizontal text viewport after programmatic text, enable, or layout transitions.
- Reuse profile option components across panel refreshes; WoW frames cannot be destroyed, so recreating the complete options tree on every show leaks hidden UI objects.
- Keep loot-source settings that reflect current character needs in per-character `ItemScoreData.searchSources`.
- Never return or search a catalog built for a different loot-source settings fingerprint.
- Invalidate equipped-score caches whenever profile scoring weights or profile identities change.
- Detect AtlasLoot data layout at runtime; prefer the 8.x beta menu/item adapter and keep legacy `AtlasLoot_Data` as fallback.
- For monolithic AtlasLoot 8.1+, derive expansion ownership from `ui.menus.collection.DungeonsAndRaids*` and read difficulty caps through `Difficulties:GetMax`; older module metadata and direct difficulty tables remain compatibility fallbacks.
- Resolve AtlasLoot through AceAddon before considering `_G.AtlasLoot`; monolithic 8.1 creates an unrelated UI frame under that global name, so global candidates must satisfy the addon data contract.
- Treat legacy-client `LibStub` as its actual callable-table API (`LibStub:GetLibrary`) rather than requiring `type(LibStub) == "function"`.
- Resolve custom item variants through Ascension's `Item:GetInfoInstant` API when legacy `GetItemInfo` has no WDB entry, and warm both APIs for asynchronous searches.
- Keep LootCollector Worldforged tier filtering inclusive from Zul'Gurub upward, and treat no selected Worldforged tier as an unfiltered base Worldforged discovery view.
- Keep search usable when custom item IDs never resolve through `GetItemInfo`; unresolved IDs must be bounded by retry/timeout behavior.
- Keep item-info fetching adaptive per frame so the addon maximizes throughput without unbounded frame spikes.
- Prefer item-tooltip difficulty labels over provider-derived AtlasLoot labels once tooltip data is available.
- Treat AtlasLoot Classic Tier 1-3 collection tables as raid-style sources; their items may skip tooltip class restrictions in search, but must still satisfy profile and native armor restrictions.
- Treat AtlasLoot `FactionsCLASSIC`, `FactionsTBC`, and `FactionsWRATH` collections as expansion-owned reputation sources, but expose and collect a faction only when its item rows are actually loaded.
- Treat AtlasLoot `CraftingCLASSIC`, `CraftingTBC`, and `CraftingWRATH` collections as expansion-owned crafting sources. Resolve recipe `spellID` rows through `AtlasLoot:GetCraftedItemID`, keep profession toggles expansion-local, and expose only sources with loaded item rows.
- Keep the Loot Sources options panel in fixed visual groups and render long AtlasLoot source selections through a bounded `FauxScrollFrame` row pool; dynamic source counts must never extend controls outside the list viewport.

## 2. Project Overview
- `ItemScore` is a Lua WoW addon for a private WotLK 3.3.5a server.
- Core feature: user-defined stat weights per profile to compute comparable item scores.
- Main workflows:
	- Tooltip scoring for inspected items.
	- Upgrade delta against currently equipped gear.
	- Search UI over cached runtime data from optional providers (`LootCollector`, `AtlasLoot`).
- Saved variables:
	- Per-character: `ItemScoreData` (profiles, stat weights, profile UI state, loot-source settings).
	- Global: `ItemScoreCacheDB` (search catalog cache).

## 3. Documentation Index
- [`./docs/loot-source-integration-plan.md`](./docs/loot-source-integration-plan.md): implemented architecture for runtime loot sources, provider filters, and cache refresh behavior.
- [`./docs/github-release-workflow.md`](./docs/github-release-workflow.md): GitHub Actions release packaging flow, TOC version bump gating, and artifact composition rules.
- Recommended next docs:
	- `./docs/scoring-model.md`: formal score and upgrade-delta rules.
	- `./docs/ui-map.md`: slash commands and frame interactions.

## 4. Glossary
- Profile: named stat-weight configuration (e.g. `DPS`).
- Score: weighted sum of item stats (2H weapons normalized by `/2`).
- Delta: candidate score minus weakest relevant equipped-slot score.
- Upgrade: item with positive delta for at least one enabled profile.
