# Test Cases

## Core scoring
- `CalculateScore(itemLink, nil)` must evaluate profile names from `ItemScoreData.order` and return the highest enabled-profile score.
- Disabled profiles must never contribute to aggregate/best score.
- Primary Attribute `Armor` weight must affect armor stat contributions from `GetItemStats` (including legacy armor stat keys).
- Rating key `Spell Penetration` must be configurable and contribute to scoring via `ITEM_MOD_SPELL_PENETRATION_SHORT`.
- Weapon DPS must be configurable and contribute to scoring via `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`.
- Block rating and block value must be independently configurable and contribute via `ITEM_MOD_BLOCK_RATING_SHORT` and `ITEM_MOD_BLOCK_VALUE_SHORT`.
- Holy, Fire, Nature, Frost, Shadow, and Arcane resistance weights must be independently configurable via `RESISTANCE1_NAME` through `RESISTANCE6_NAME`.
- Changing a profile stat weight must invalidate equipped-score caches before the next delta/upgrade calculation.
- Deleting and recreating a profile name must not reuse stale equipped scores from the deleted profile.

## Search data providers
- ItemScore only (no LootCollector, no AtlasLoot): search opens and shows deterministic "no data source available" state without Lua errors.
- LootCollector only: vendor and discovery-derived items are searchable by zone/source.
- LootCollector Worldforged aggregation: records appear as `Zone -> Worldforged -> itemIDs`.
- LootCollector split install: ItemScore uses the main `LootCollector` accessor adapter when available and does not directly parse `LootCollector_StarterDB` or `LootCollector_CustomImport`.
- LootCollector V8 fallback: if accessors are unavailable but `LootCollectorDB_Asc.global.realms[realmKey]` is loaded, ItemScore reads the current realm bucket read-only.
- AtlasLoot only: dungeon/raid loot entries are searchable by instance and boss/source.
- AtlasLoot adapter detection: Ascension 8.x beta data (`AtlasLoot.ui.menus.data` + `AtlasLoot.data.item`) must use the `atlasloot_v8` adapter even when global `AtlasLoot_Data` contains only compatibility data.
- AtlasLoot adapter fallback: legacy `AtlasLoot_Data` tables must still be collected when beta menu/item data is absent.
- AtlasLoot module loading must call real load-on-demand addon names with underscores, e.g. `AtlasLoot_OriginalWoW`.
- AtlasLoot 8.x beta collection must read direct item tables keyed by `dataID .. pageIndex` and referenced tables keyed by NPC/ref id.
- AtlasLoot expansion filters (`classic/tbc/wrath`) immediately change cache contents after refresh.
- AtlasLoot dungeons are always included for enabled expansions and cannot be disabled independently.
- AtlasLoot dungeon difficulty limit: default `Dungeon Max Mythic Level = 0` includes Heroic and base Mythic variants; raising the value includes Mythic+ item IDs up to the AtlasLoot-supported maximum.
- AtlasLoot dungeon difficulty input must preserve user values above the currently supported maximum; effective results are naturally capped by AtlasLoot difficulty metadata or missing difficulty IDs.
- AtlasLoot dungeon difficulty input persists per character across reload/restart; setting one character to `15` must not force another character to use `15`.
- Regression: closing `Interface -> AddOns -> ItemScore -> Loot Sources` with a blank or not-yet-loaded `Dungeon Max Mythic Level` field must not overwrite an existing per-character value with `0`.
- AtlasLoot raid difficulty limit: `Normal`, `Heroic`, `Mythic`, and `Ascended` include only variants at or below the selected maximum.
- AtlasLoot search row display must show item grade next to the item link when known, e.g. `[Wildfire Cape] (M+10)`, `[Item] (Asc)`.
- AtlasLoot search row display must prefer tooltip-derived item grade over provider metadata once the item tooltip is available, e.g. a cache-misindexed M+40 item must not stay labeled `M+3`.
- AtlasLoot raids are individually toggleable in `Interface -> AddOns -> ItemScore -> Loot Sources`, grouped by expansion.
- Search max-level filter (from search window): with `Max Required Level = 38`, results must exclude items requiring level 39+.
- Search max-level filter updates must not trigger a full cache rebuild; only search results should change.
- Search max-level input must keep proper focus behavior (cursor should stop blinking after clicking other search controls/background).
- If user never set a custom max-level value, default value in search should follow current character level.
- Profile armor-type filter supports multiple selections (`Cloth/Leather/Mail/Plate`) and must only restrict armor items; non-armor items remain unaffected.
- If no armor type is selected in a profile filter, search must not apply any armor-type restriction.
- `Back` (`INVTYPE_CLOAK`) must never be excluded by the armor-type filter, even though cloaks are cloth-subtyped items.
- Profile weapon-type filter supports multiple selections and must filter only weapon-like entries (`Weapon`, `Shield`, `Held In Off-hand`).
- If no weapon type is selected in a profile filter, search must not apply any weapon-type restriction.
- `Shield` and `Held In Off-hand` must be independently filterable (e.g. mage can disable shield, tank can disable held off-hand).
- Upgrade delta and upgrade search must support `INVTYPE_WEAPONMAINHAND`, `INVTYPE_WEAPONOFFHAND`, `INVTYPE_THROWN`, and `INVTYPE_RELIC`.
- LootCollector Worldforged tier filters (`ZG/MC/BWL/Naxxramas`) must affect which Worldforged entries are added to search catalog.
- LootCollector Worldforged tier filters must include Zul'Gurub as the lowest configurable tier.
- LootCollector Worldforged collection must keep base Worldforged discoveries visible when no Worldforged tier is selected.
- Search must not show cached AtlasLoot M+ variants from an older source-settings fingerprint after the Mythic+ limit changes.
- AtlasLoot area filter: `/is atlas place off <Area>` removes that area from search results.
- Both addons: merged result deduplicates identical `(place, source, itemID)` triples and preserves multi-source items.
- Late addon load (`ADDON_LOADED` during session): source catalog invalidates and rebuilds without UI reload.
- Manual rebuild `/is refresh` always refreshes cache regardless daily interval.
- Regression: after showing "No search data source enabled", enabling at least one source in `Interface -> AddOns -> ItemScore -> Loot Sources` must allow immediate search on next click (no sticky old message).
- Performance regression: toggling source options and clicking `Okay` in Interface options must not freeze the client while cache rebuild runs.
- Performance regression: clicking `Search` must keep UI responsive while the result list is processed in background batches.
- Regression: running search repeatedly (e.g. `Weapons` slot) must not enter an endless auto-search loop when some itemIDs never resolve via `GetItemInfo`.
- Regression: while `Fetching...` is active, a re-entrant follow-up search that queues additional item queries must not leave the search button permanently disabled.
- Regression: item-info fetching must stay per-frame/adaptive; it should increase throughput when cheap, reduce throughput when frames are expensive, and never process an unbounded queue in one frame.
- Regression: if `Fetching...` exceeds the bounded query timeout (e.g. loading-screen/zone transfer during query), query state must auto-reset, button must become usable again, and a new search must run normally.
- Regression: clicking `Refresh Cache Now` in options triggers only one immediate rebuild (or queues one retry only when current rebuild is busy), never two unconditional rebuilds.
- Regression: LootCollector provider must respect per-frame `maxOps` budget even when many vendor records contain zero items.
- Regression: if delta calculation returns sentinel/invalid extreme values for scaled items, search row must display `?` instead of large negative garbage.
- Regression: repeated unresolved/custom item IDs must not leave the search button stuck on `Fetching...`; after bounded retries, search remains usable and shows available results.

## DropWatch lifecycle
- Regression: dropped upgrade entries in `ItemDropWatch` stay fully visible for about 60 seconds, then fade out smoothly, and are removed shortly after.
- Regression: stale `ItemDropWatchDB.items` entries from previous sessions must not persist in the window after login/reload.
- Regression: pending GET_ITEM_INFO entries that resolve to non-upgrades must be removed from pending state to avoid unbounded growth.
- Regression: DropWatch row rendering must never throw Lua errors when an item has an unknown/custom rarity (e.g. quality `7`); row text must still render with fallback color.

## Locale compatibility
- On non-English clients, class-restricted items must still be filtered correctly (class list parsing must use localized `ITEM_CLASSES_ALLOWED` label).
