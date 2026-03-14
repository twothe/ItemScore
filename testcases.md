# Test Cases

## Core scoring
- `CalculateScore(itemLink, nil)` must evaluate profile names from `ItemScoreData.order` and return the highest enabled-profile score.
- Disabled profiles must never contribute to aggregate/best score.

## Search data providers
- ItemScore only (no LootCollector, no AtlasLoot): search opens and shows deterministic "no data source available" state without Lua errors.
- LootCollector only: vendor and discovery-derived items are searchable by zone/source.
- LootCollector Worldforged aggregation: records appear as `Zone -> Worldforged -> itemIDs`.
- AtlasLoot only: dungeon/raid loot entries are searchable by instance and boss/source.
- AtlasLoot expansion filters (`classic/tbc/wrath`) immediately change cache contents after refresh.
- AtlasLoot dungeons are always included for enabled expansions and cannot be disabled independently.
- AtlasLoot raids are individually toggleable in `Interface -> AddOns -> ItemScore -> Loot Sources`, grouped by expansion.
- Search max-level filter (from search window): with `Max Required Level = 38`, results must exclude items requiring level 39+.
- Search max-level filter updates must not trigger a full cache rebuild; only search results should change.
- Search max-level input must keep proper focus behavior (cursor should stop blinking after clicking other search controls/background).
- If user never set a custom max-level value, default value in search should follow current character level.
- LootCollector Worldforged tier filters (`MC/BWL/Naxxramas`) must affect which Worldforged entries are added to search catalog.
- AtlasLoot area filter: `/is atlas place off <Area>` removes that area from search results.
- Both addons: merged result deduplicates identical `(place, source, itemID)` triples and preserves multi-source items.
- Late addon load (`ADDON_LOADED` during session): source catalog invalidates and rebuilds without UI reload.
- Manual rebuild `/is refresh` always refreshes cache regardless daily interval.
- Regression: after showing "No search data source enabled", enabling at least one source in `Interface -> AddOns -> ItemScore -> Loot Sources` must allow immediate search on next click (no sticky old message).
- Performance regression: toggling source options and clicking `Okay` in Interface options must not freeze the client while cache rebuild runs.
- Performance regression: clicking `Search` must keep UI responsive while the result list is processed in background batches.
- Regression: running search repeatedly (e.g. `Weapons` slot) must not enter an endless auto-search loop when some itemIDs never resolve via `GetItemInfo`.
- Regression: while `Fetching...` is active, a re-entrant follow-up search that queues additional item queries must not leave the search button permanently disabled.
- Regression: clicking `Refresh Cache Now` in options triggers only one immediate rebuild (or queues one retry only when current rebuild is busy), never two unconditional rebuilds.
- Regression: LootCollector provider must respect per-frame `maxOps` budget even when many vendor records contain zero items.
- Regression: if delta calculation returns sentinel/invalid extreme values for scaled items, search row must display `?` instead of large negative garbage.

## DropWatch lifecycle
- Regression: dropped upgrade entries in `ItemDropWatch` stay fully visible for about 60 seconds, then fade out smoothly, and are removed shortly after.
- Regression: stale `ItemDropWatchDB.items` entries from previous sessions must not persist in the window after login/reload.
- Regression: pending GET_ITEM_INFO entries that resolve to non-upgrades must be removed from pending state to avoid unbounded growth.

## Locale compatibility
- On non-English clients, class-restricted items must still be filtered correctly (class list parsing must use localized `ITEM_CLASSES_ALLOWED` label).
