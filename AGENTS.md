# AGENTS.md

## 1. Behaviour
- Keep implementation compatible with WoW 3.3.5a (`Interface: 30300`) APIs.
- Prioritize simple, explicit Lua code with clear addon-level module boundaries.
- Preserve the additive profile-based scoring model (stat weights per profile).
- Prefer deterministic UI and score behavior over implicit fallbacks.
- Treat external loot providers (`LootCollector`, `AtlasLoot`) as optional; never hard-fail when absent.

## 2. Project Overview
- `ItemScore` is a Lua WoW addon for a private WotLK 3.3.5a server.
- Core feature: user-defined stat weights per profile to compute comparable item scores.
- Main workflows:
	- Tooltip scoring for inspected items.
	- Upgrade delta against currently equipped gear.
	- Search UI over cached runtime data from optional providers (`LootCollector`, `AtlasLoot`).
	- Loot drop watch panel showing recently dropped upgrades.
- Saved variables:
	- Per-character: `ItemScoreData` (profiles, stat weights, profile UI state).
	- Global: `ItemDropWatchDB` (drop watch list and UI capacity), `ItemScoreCacheDB` (search catalog cache).

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
- DropWatch: floating frame listing recent dropped upgrades.
