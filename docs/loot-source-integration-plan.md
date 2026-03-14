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
- Data model:
	- Discoveries are keyed records with at least `i` (itemID), `c/z/iz` (zone ids), `xy`, `dt`, `src`.
	- Vendor records include `vendorName`, `vendorType`, `vendorItems[]` where entries contain `itemID`.
- Zone name resolution is available via:
	- `LootCollector.ResolveZoneDisplay(continent, zoneID, iz)`
	- `ZoneList.MapDataByID`.

Important limitation:
- LootCollector discovery records do not provide boss/NPC source names for normal drops.
- Vendors are source-specific (`vendorName`) and can be represented as dedicated sources.
- Worldforged tier information (MC/BWL/Naxxramas) is not stored directly in discovery records; it must be inferred via `GetItemDifficultyID(itemID, difficulty)`.

### AtlasLoot
- Main addon object: `ATLASLOOT` / `LibStub("AceAddon-3.0"):GetAddon("AtlasLoot")`.
- Loot tables are in global `AtlasLoot_Data`.
- Expansion modules are load-on-demand (`AtlasLoot_OriginalWoW`, `AtlasLoot_BurningCrusade`, `AtlasLoot_WrathoftheLichKing`, etc.).
- The addon already exposes load helpers:
	- `AtlasLoot:LoadAllModules()`
	- `AtlasLoot:IsLootTableAvailable(dataSourceKey)`
- Table structure for boss loot is consistent:
	- top table has `Name` (instance/loot place) and usually `Type`.
	- nested entries have `Name` (boss/source) and sides with `{ itemID = ... }`.

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

Notes:
- `byPlace` preserves current conceptual shape.
- `itemSources` prevents lossy mapping and handles multi-source duplicates.

### 2. Provider implementations
Add provider modules:
- `ItemScoreSourceLootCollector.lua`
- `ItemScoreSourceAtlasLoot.lua`

Provider contract:
- `IsAvailable() -> boolean`
- `Collect(addMapping, settings) -> statsTable` (mutates catalog through helper inserter)
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
Use `LootCollector:GetVendorsDB()` and `LootCollector:GetDiscoveriesDB()`.

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
- If AtlasLoot is loaded, call `AtlasLoot:LoadAllModules()` once.
- If AtlasLoot is installed but not loaded, attempt guarded `LoadAddOn("AtlasLoot")`, then load modules.

Selection filter:
- Include only tables that look like loot-instance datasets.
- Preferred filter:
	- `Type` contains `"Dungeon"` or `"Raid"`, or
	- table has nested entries with `Name` + item lists and module in dungeon/raid expansion addons.
- Exclude known crafting/collection/vanity-only datasets.

Mapping:
- `place = instanceTable.Name`.
- `source = bossTable.Name` (fallback `"Unknown Source"`).
- `itemID = entry.itemID` for every item row.

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
- `ADDON_LOADED` for `LootCollector`, `AtlasLoot`, and AtlasLoot expansion modules
- Manual `/is refresh`.

## AtlasLoot Controls
- `/is atlas on|off`: enable/disable AtlasLoot provider.
- `/is atlas classic|tbc|wrath on|off`: expansion filters.
- Dungeons are always enabled for active expansions.
- Raids are individually toggleable in `Interface -> AddOns -> ItemScore -> Loot Sources` (grouped by expansion).
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
- Optional search cap: `Max Required Level` limits visible results while leveling (toggle + value in the search window).
- The default max-level value is the current character level until the player sets a custom value.
- `Max Required Level` is a search-time filter only and does not invalidate/rebuild the cache.
- LootCollector Worldforged tiers (`MC/BWL/Naxxramas`) are configurable in Loot Sources options.

## Validation checklist
- Search works when only ItemScore is enabled (shows "no source addons" state).
- Search works with only LootCollector enabled.
- Search works with only AtlasLoot enabled.
- Search works with both enabled and deduplicates cleanly.
- Duplicate multi-source items remain represented (no silent overwrite).
- No Lua errors when source addon loads later during session.
