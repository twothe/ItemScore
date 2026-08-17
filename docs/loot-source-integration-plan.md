# Loot Source Integration

## Goal
Replace static `ItemScoreData.lua` item mapping with runtime data providers while preserving ItemScore search and comparison behavior.

Status:
- Completed. `ItemScoreData.lua` static dataset has been removed from load order and deleted from the addon.

Target source shape remains:
- `Loot Place` -> `Specific Source` -> `Item IDs`

## Findings

### LootCollector
- Global addon object: `_G.LootCollector`.
- Public accessors:
	- `LootCollector:GetDiscoveriesDB()`
	- `LootCollector:GetVendorsDB()`
- Current LootCollector releases are split into:
	- `LootCollector`: the main addon and only authoritative database owner.
	- `LootCollector_StarterDB`: optional load-on-demand import payload.
	- `LootCollector_CustomImport`: optional load-on-demand custom import buffer.
- Data model:
	- Active V8 records are realm-bucketed under `LootCollectorDB_Asc.global.realms[realmKey].discoveries` and `.blackmarketVendors`.
	- Discoveries are keyed records with at least `i` (itemID), `c/z/iz` (zone ids), `xy`, `dt`, `src`.
	- Vendor records include `vendorName`, `vendorType`, `vendorItems[]` where entries contain `itemID`.
- Zone name resolution is available via:
	- `LootCollector.ResolveZoneDisplay(continent, zoneID, iz)`
	- `ZoneList.MapDataByID`.

Important limitation:
- LootCollector discovery records do not provide boss/NPC source names for normal drops.
- Vendors are source-specific (`vendorName`) and can be represented as dedicated sources.
- Worldforged tier information (ZG/MC/BWL/Naxxramas) is not stored directly in discovery records; it must be inferred via `GetItemDifficultyID(itemID, difficulty)`.

### AtlasLoot
- Main addon object: `ATLASLOOT` / `LibStub("AceAddon-3.0"):GetAddon("AtlasLoot")`.
- AtlasLoot 8.1 also creates a UI frame named `AtlasLoot`, causing `_G.AtlasLoot` to reference the frame rather than the addon object; ItemScore therefore validates global candidates and prefers AceAddon resolution.
- Legacy clients expose `LibStub` as a callable table, so ItemScore resolves `AceAddon-3.0` through `LibStub:GetLibrary(...)` and retains function-style LibStub only as a compatibility fallback.
- AtlasLoot Ascension 8.x beta keeps global `AtlasLoot_Data` only as a compatibility stub.
- AtlasLoot Ascension 8.x beta stores instance menus in `AtlasLoot.ui.menus.data` and item rows in `AtlasLoot.data.item`.
- AtlasLoot Ascension 8.1+ is monolithic: instance menus no longer carry expansion-module metadata, and expansion ownership is listed in `AtlasLoot.ui.menus.collection.DungeonsAndRaidsCLASSIC/TBC/WRATH`.
- AtlasLoot Ascension 8.1+ exposes difficulty caps through `AtlasLoot.Difficulties:GetMax(typeName)` rather than direct type-indexed tables.
- Legacy AtlasLoot builds store boss loot in global `AtlasLoot_Data`.
- Split-module releases use load-on-demand expansion addons (`AtlasLoot_OriginalWoW`, `AtlasLoot_BurningCrusade`, `AtlasLoot_WrathoftheLichKing`, etc.); monolithic 8.1+ releases do not.
- In split-module releases, `AtlasLoot:IsLootTableAvailable(moduleName)` expects the real module addon name, including underscores.
- Legacy table structure for boss loot is consistent:
	- top table has `Name` (instance/loot place) and usually `Type`.
	- nested entries have `Name` (boss/source) and sides with `{ itemID = ... }`.
- 8.x beta menu structure is:
	- `menu.Name`, `menu.Type`, plus `menu.Module` in split-module releases.
	- numeric menu pages like `{ "Boss Name", { npcOrRefIds... } }`.
	- direct item tables are keyed as `dataID .. pageIndex` in `AtlasLoot.data.item`.
	- referenced/drop-rate item tables may also be keyed by numeric NPC/ref id.

Important limitation:
- AtlasLoot contains many non-boss datasets (crafting, collections, events).
- Filtering is required to avoid noisy/unrelated sources.

## Implemented Architecture (ItemScore)

### 1. New data provider layer
Add module: `ItemScoreSources.lua`.

Public API:
- `addon.GetSearchCatalog()`: cached catalog getter.
- `addon.RefreshSearchCache(forceRefresh, silent)`: rebuilds cache now.
- `addon.QueueSearchCacheRefresh(reason)`: schedules background rebuild.
- `addon.GetSearchCacheStatus()`: reports cache/provider health.

Normalized internal shape:
- `catalog.byPlace[placeName][sourceName] = { itemID, ... }`
- `catalog.itemSources[itemID] = { { place = "...", source = "..." }, ... }`
- `catalog.itemMeta[itemID] = { difficultyLabel = "...", difficultyRank = number }`

Notes:
- `byPlace` preserves current conceptual shape.
- `itemSources` prevents lossy mapping and handles multi-source duplicates.
- `itemMeta` stores compact display metadata such as AtlasLoot difficulty labels (`N`, `HC`, `M`, `M+10`, `Asc`).
- Provider difficulty metadata is provisional display data; once an item tooltip is available, search display should prefer the tooltip-derived item grade to correct stale or misindexed provider records.
- Search normalizes Ascension's `Item:CreateFromID(...):GetInfoInstant()` result to the legacy `GetItemInfo` tuple when a custom difficulty ID is absent from the WDB cache. The asynchronous warmer queries both item APIs.

### 2. Provider implementations
Add provider modules:
- `ItemScoreSourceLootCollector.lua`
- `ItemScoreSourceAtlasLoot.lua`

Provider contract:
- `IsAvailable() -> boolean`
- `Collect(addMapping, settings) -> statsTable` (mutates catalog through helper inserter)
- Incremental providers may expose `StartCollect`, `StepCollect`, and `FinishCollect`.
- Never throw; fail closed and return partial data.

### 3. Provider priority and merge
Merge order:
1. LootCollector
2. AtlasLoot

Merge rules:
- Deduplicate by `(place, source, itemID)`.
- Keep all source tuples for each item (do not collapse to one location).
- Stable deterministic sort when converting sets to arrays.

## Source-specific extraction plan

### LootCollector extraction
Adapter decision order:
1. Use the loaded or loadable main `LootCollector` addon through `LootCollector:GetDiscoveriesDB()` and `LootCollector:GetVendorsDB()`.
2. If the object is present but the accessor path is not ready, read the current realm bucket from `LootCollectorDB_Asc.global.realms[realmKey]` as a read-only fallback.
3. If only legacy pre-bucket `global.discoveries` / `global.blackmarketVendors` tables exist, read them as a compatibility fallback.
4. Do not read `LootCollector_StarterDB` or `LootCollector_CustomImport` directly; those are import sources and must be applied by LootCollector so its migration, deduplication, and network-compatible record handling stay authoritative.

Mapping:
- Vendors:
	- `place = ResolveZoneDisplay(c, z, iz)` (fallback `"Unknown Zone"`).
	- `source = vendorName` (fallback `"Vendor"`).
	- `itemIDs = vendorItems[].itemID`.
- Discoveries:
	- `place = ResolveZoneDisplay(c, z, iz)`.
	- `source = "World Drop"` (or `"Worldforged"` / `"Mystic Scroll"` derived from `dt`).
	- `itemID = i` if positive.

Rationale:
- Discovery records usually lack boss/NPC names.
- Zone + typed source remains meaningful and searchable.

### AtlasLoot extraction
Preparation:
- If AtlasLoot is installed but not loaded, attempt guarded `LoadAddOn("AtlasLoot")`.
- In split-module releases, load only enabled expansion modules during cache build and all expansion modules when building the raid checklist for the settings UI.
- In split-module releases, use `AtlasLoot:IsLootTableAvailable("AtlasLoot_OriginalWoW")`, `AtlasLoot:IsLootTableAvailable("AtlasLoot_BurningCrusade")`, and `AtlasLoot:IsLootTableAvailable("AtlasLoot_WrathoftheLichKing")` when available.
- In monolithic 8.1+ releases, use the already initialized core menu/item data and do not probe obsolete expansion addons.
- Select the runtime adapter automatically:
	- prefer `atlasloot_v8` when `AtlasLoot.ui.menus.data` and `AtlasLoot.data.item` are available.
	- in monolithic 8.1+ data, restrict scanning to the authoritative `DungeonsAndRaids*` collections so collection/PvP menus reusing dungeon or raid difficulty types are not misclassified as instance loot.
	- fall back to `legacy` when useful `AtlasLoot_Data` tables are available.

Selection filter:
- Include only tables that look like loot-instance datasets.
- Preferred filter:
	- `Type` contains `"Dungeon"` or `"Raid"`, or
	- table has nested entries with `Name` + item lists and module in dungeon/raid expansion addons.
- Exclude known crafting/collection/vanity-only datasets.

Mapping:
- `place = instance/menu Name`.
- `source = boss/page Name` (fallback `"Unknown Source"`).
- `itemID = entry.itemID` for every item row.
- For AtlasLoot 8.x beta, collect rows from direct `dataID .. pageIndex` tables plus referenced item tables listed by the menu page.
- AtlasLoot difficulty expansion passes metadata into the catalog so search rows can show the concrete item grade next to the item link.

## Search integration changes

### Current issue
`ItemScoreSearch.collectItems()` currently stores one dungeon per item and only appends bosses.
This is lossy for items from multiple places.

### Implemented update
- Iterate `catalog.itemSources[itemID]` instead of static nested table directly.
- Preserve full multi-source list.
- UI row:
	- show first source (`place - source`) and append `(+N)` if multiple alternatives exist.
	- tooltip can list all known sources for that item.

## Optional addon handling

Rules:
- No hard dependency on LootCollector/AtlasLoot.
- Build catalog from whichever providers are available.
- If none available, search returns empty with explicit user-facing info.

Refresh triggers:
- `PLAYER_LOGIN`
- `ADDON_LOADED` for `LootCollector`, `LootCollector_StarterDB`, `LootCollector_CustomImport`, `AtlasLoot`, and AtlasLoot expansion modules
- Manual `/is refresh`.

## AtlasLoot Controls
- `/is atlas on|off`: enable/disable AtlasLoot provider.
- `/is atlas classic|tbc|wrath on|off`: expansion filters.
- Dungeons are always enabled for active expansions.
- Dungeon AtlasLoot variants are included up to the requested `Dungeon Max Mythic Level` in `Interface -> AddOns -> ItemScore -> Loot Sources`; `0` means base Mythic. The input is not upper-capped, while effective results are naturally limited by AtlasLoot difficulty metadata or missing difficulty IDs. The field is initialized directly from the current character's SavedVariables, refreshes from persisted state unless the player is actively editing a draft, and resets its horizontal text viewport after legacy-client enable-state updates.
- Raid AtlasLoot variants are included up to `Raid Max Difficulty` (`Normal`, `Heroic`, `Mythic`, `Ascended`) in `Interface -> AddOns -> ItemScore -> Loot Sources`.
- Raids are individually toggleable in `Interface -> AddOns -> ItemScore -> Loot Sources` (grouped by expansion).
- `The Karazhan Crypts` is treated as a raid even though AtlasLoot labels its Classic copy as `ClassicDungeonExt` and uses the custom `BCkarazhanCrypts` type for its TBC copy. Both copies therefore follow raid difficulty and per-raid enablement controls.
- `/is atlas raid on|off`: convenience switch for all raids at once.
- `/is atlas place on <Area Name>` / `/is atlas place off <Area Name>`: per-area toggle for locked/unavailable content.
- `/is atlas place list`: inspect disabled areas.
- `/is atlas place all`: list known cached area names for easier toggling.

## Cache Controls
- `/is lootcollector on|off`: enable/disable LootCollector provider.
- `/is refresh`: rebuild cache immediately.
- Automatic refresh runs in background when stale (once per day), on login, and after relevant addon load events.
- Cache rebuild uses incremental per-frame batches with adaptive budget to avoid UI freezes.

## Search Runtime
- Search processing over large item catalogs runs in incremental per-frame batches with adaptive budget.
- UI remains responsive while search progresses and updates asynchronously.
- Item-info fetching is adaptive per frame: it starts conservatively, measures actual work time, raises throughput when cheap, lowers it when frames get expensive, and has per-item retry limits.
- Optional search cap: `Max Required Level` limits visible results while leveling (toggle + value in the search window).
- The default max-level value is the current character level until the player sets a custom value.
- `Max Required Level` is a search-time filter only and does not invalidate/rebuild the cache.
- LootCollector Worldforged tiers (`ZG/MC/BWL/Naxxramas`) are configurable in Loot Sources options. The effective filter is inclusive from Zul'Gurub through the highest selected tier. If no tier is selected, or if selected tier IDs cannot be derived or resolved through client item info yet, the original LootCollector discovery item remains available as a search fallback.
- AtlasLoot difficulty limits are cache-time filters because they change which item IDs are collected.

## Validation checklist
- Search works when only ItemScore is enabled (shows "no source addons" state).
- Search works with only LootCollector enabled.
- Search works with only AtlasLoot enabled.
- AtlasLoot Ascension 8.x beta (`Version: 8.0.0`) uses the `atlasloot_v8` adapter and does not depend on populated legacy `AtlasLoot_Data`.
- AtlasLoot Ascension 8.1 monolithic menus use the `atlasloot_v8` adapter without legacy expansion addons or per-menu `Module` fields.
- Legacy AtlasLoot data still uses the `legacy` adapter when beta menu/item data is absent.
- AtlasLoot module loading uses underscore addon names, e.g. `AtlasLoot_OriginalWoW`.
- AtlasLoot dungeon search includes Heroic, base Mythic, and configured Mythic+ variants when `Dungeon Max Mythic Level` permits them.
- Search must not use a source cache built for older loot-source settings; changed settings require a rebuild before results are shown.
- AtlasLoot raid search includes Normal/Heroic/Mythic/Ascended variants only up to `Raid Max Difficulty`.
- Search rows show known AtlasLoot item grades directly beside the item link, e.g. `[Wildfire Cape] (M+10)`.
- Missing or custom item IDs must not keep the search button stuck on `Fetching...`; after retry limits, the search continues with available data.
- Search works with both enabled and deduplicates cleanly.
- Duplicate multi-source items remain represented (no silent overwrite).
- No Lua errors when source addon loads later during session.
