-- AtlasLoot search-provider adapter for legacy modules and monolithic 8.x menu/item data.
local addonName, addon = ...

local provider = {
	key = "AtlasLoot",
}
local sourceChoicesCache = {
	data = nil,
	builtAt = 0,
}

local DIFFICULTY_NORMAL = 3
local DIFFICULTY_HEROIC = 4
local DIFFICULTY_MYTHIC = 5
local DIFFICULTY_ASCENDED = 6
local MAX_DUNGEON_MYTHIC_LEVEL_FALLBACK = 40

local DUNGEON_TYPES = {
	ClassicDungeon = true,
	ClassicDungeonExt = true,
	BCDungeon = true,
	WrathDungeon = true,
}

local RAID_TYPES = {
	ClassicRaid = true,
	BCkarazhanCrypts = true,
	BCRaid = true,
	WrathRaid = true,
}

local CRAFTING_TYPES = {
	ClassicCrafting = true,
	BCCrafting = true,
	WrathCrafting = true,
}

-- AtlasLoot exposes the Classic copy of this raid as ClassicDungeonExt.
-- Keep the instance override centralized so collection and configuration agree.
local RAID_PLACES = {
	["The Karazhan Crypts"] = true,
}

-- These raid reward tables live in AtlasLoot's Collections navigation instead
-- of DungeonsAndRaids, so they need an explicit and deliberately narrow allowlist.
local TIER_SET_DATA_IDS = {
	TONE = true,
	TTWO = true,
	TTHREE = true,
}

local DIFFICULTY_BY_NAME = {
	Normal = DIFFICULTY_NORMAL,
	Heroic = DIFFICULTY_HEROIC,
	Superior = DIFFICULTY_HEROIC,
	Mythic = DIFFICULTY_MYTHIC,
	Ascended = DIFFICULTY_ASCENDED,
}

local MODULE_EXPANSIONS = {
	["AtlasLoot_OriginalWoW"] = { key = "classic", label = "Classic" },
	["AtlasLoot_BurningCrusade"] = { key = "tbc", label = "Burning Crusade" },
	["AtlasLoot_WrathoftheLichKing"] = { key = "wrath", label = "Wrath of the Lich King" },
}

local EXPANSION_MODULE_BY_KEY = {
	classic = "AtlasLoot_OriginalWoW",
	tbc = "AtlasLoot_BurningCrusade",
	wrath = "AtlasLoot_WrathoftheLichKing",
}

local EXPANSION_ORDER = { "classic", "tbc", "wrath" }

local EXPANSION_META_BY_KEY = {
	classic = MODULE_EXPANSIONS[EXPANSION_MODULE_BY_KEY.classic],
	tbc = MODULE_EXPANSIONS[EXPANSION_MODULE_BY_KEY.tbc],
	wrath = MODULE_EXPANSIONS[EXPANSION_MODULE_BY_KEY.wrath],
}

local EXPANSION_BY_LOOT_TYPE = {
	ClassicDungeon = "classic",
	ClassicDungeonExt = "classic",
	ClassicRaid = "classic",
	BCDungeon = "tbc",
	BCkarazhanCrypts = "tbc",
	BCRaid = "tbc",
	WrathDungeon = "wrath",
	WrathRaid = "wrath",
	ClassicCrafting = "classic",
	BCCrafting = "tbc",
	WrathCrafting = "wrath",
}

local function clean(text)
	text = tostring(text or "")
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then return nil end
	return text
end

local function nowSeconds()
	if type(time) == "function" then return time() end
	return 0
end

local function isTierSetDataID(dataID)
	return TIER_SET_DATA_IDS[tostring(dataID)] and true or false
end

local function addonInstalled(addonName)
	if type(GetAddOnInfo) ~= "function" then return false end
	local name = GetAddOnInfo(addonName)
	return name ~= nil
end

local function addonLoaded(addonName)
	if type(IsAddOnLoaded) ~= "function" then return false end
	return IsAddOnLoaded(addonName) and true or false
end

local function loadAddonIfInstalled(addonName)
	if addonLoaded(addonName) then return true end
	if not addonInstalled(addonName) then return false end
	if type(LoadAddOn) ~= "function" then return false end
	local ok, loaded = pcall(LoadAddOn, addonName)
	if not ok then return false end
	return addonLoaded(addonName) or loaded == true or loaded == 1
end

local function isAtlasLootAddonObject(candidate)
	if type(candidate) ~= "table" then return false end
	if type(candidate.AddItemData) == "function" then return true end
	if type(candidate.InitializeDataTables) == "function" then return true end
	if type(candidate.IsLootTableAvailable) == "function" then return true end
	return type(candidate.data) == "table" and type(candidate.Difficulties) == "table"
end

local function resolveAceAddonLibrary()
	local libStub = _G.LibStub
	if type(libStub) == "table" and type(libStub.GetLibrary) == "function" then
		local ok, aceAddon = pcall(libStub.GetLibrary, libStub, "AceAddon-3.0", true)
		if ok then return aceAddon end
	elseif type(libStub) == "function" then
		local ok, aceAddon = pcall(libStub, "AceAddon-3.0", true)
		if ok then return aceAddon end
	end
	return nil
end

local function resolveAtlasLootObject()
	if isAtlasLootAddonObject(_G.ATLASLOOT) then return _G.ATLASLOOT end
	local aceAddon = resolveAceAddonLibrary()
	if aceAddon and type(aceAddon.GetAddon) == "function" then
		local ok, atlasLoot = pcall(function()
			return aceAddon:GetAddon("AtlasLoot", true)
		end)
		if ok and isAtlasLootAddonObject(atlasLoot) then return atlasLoot end
	end

	-- AtlasLoot 8.1 names its main UI frame "AtlasLoot", which creates the
	-- unrelated _G.AtlasLoot frame. Only accept this global in older releases
	-- when it actually exposes the addon/data contract.
	if isAtlasLootAddonObject(_G.AtlasLoot) then return _G.AtlasLoot end
	return nil
end

local function ensureAtlasLootLoaded()
	if resolveAtlasLootObject() then return true end
	if addonLoaded("AtlasLoot") then return true end
	if not addonInstalled("AtlasLoot") then return false end
	loadAddonIfInstalled("AtlasLoot")
	return resolveAtlasLootObject() ~= nil or addonLoaded("AtlasLoot")
end

local function atlasLootVersion(atlasLoot)
	if atlasLoot and atlasLoot.Version then return tostring(atlasLoot.Version) end
	if type(GetAddOnMetadata) == "function" then
		local ok, version = pcall(GetAddOnMetadata, "AtlasLoot", "Version")
		if ok and version then return tostring(version) end
	end
	return nil
end

local function normalizeDungeonMaxMythicLevel(value)
	local numeric = math.floor(tonumber(value) or 0)
	if numeric < 0 then numeric = 0 end
	return numeric
end

local function normalizeRaidMaxDifficulty(value)
	local numeric = math.floor(tonumber(value) or DIFFICULTY_MYTHIC)
	if numeric < DIFFICULTY_NORMAL then numeric = DIFFICULTY_NORMAL end
	if numeric > DIFFICULTY_ASCENDED then numeric = DIFFICULTY_ASCENDED end
	return numeric
end

local function normalizeSettings(settings)
	settings = settings or {}
	return {
		atlasClassic = settings.atlasClassic ~= false,
		atlasTBC = settings.atlasTBC and true or false,
		atlasWrath = settings.atlasWrath and true or false,
		atlasDungeonMaxMythicLevel = normalizeDungeonMaxMythicLevel(settings.atlasDungeonMaxMythicLevel),
		atlasRaidMaxDifficulty = normalizeRaidMaxDifficulty(settings.atlasRaidMaxDifficulty),
		atlasDisabledPlaces = type(settings.atlasDisabledPlaces) == "table" and settings.atlasDisabledPlaces or {},
		atlasDisabledRaids = type(settings.atlasDisabledRaids) == "table" and settings.atlasDisabledRaids or {},
		atlasDisabledFactions = type(settings.atlasDisabledFactions) == "table" and settings.atlasDisabledFactions or {},
		atlasDisabledCrafting = type(settings.atlasDisabledCrafting) == "table" and settings.atlasDisabledCrafting or {},
	}
end

local function expansionEnabled(expansionKey, settings)
	if expansionKey == "classic" then return settings.atlasClassic end
	if expansionKey == "tbc" then return settings.atlasTBC end
	if expansionKey == "wrath" then return settings.atlasWrath end
	return false
end

local function anyExpansionEnabled(settings)
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		if expansionEnabled(expansionKey, settings) then return true end
	end
	return false
end

local function loadAtlasLootModule(atlasLoot, moduleName)
	if not moduleName then return end
	if atlasLoot and type(atlasLoot.IsLootTableAvailable) == "function" then
		local ok, available = pcall(atlasLoot.IsLootTableAvailable, atlasLoot, moduleName)
		if ok and (available or addonLoaded(moduleName)) then return true end
	end
	return loadAddonIfInstalled(moduleName)
end

local function indexSourceDataID(expansionByDataID, categoryByDataID, dataID, expansionKey, category)
	if dataID == nil then return end
	expansionByDataID[dataID] = expansionKey
	expansionByDataID[tostring(dataID)] = expansionKey
	if category then
		categoryByDataID[dataID] = category
		categoryByDataID[tostring(dataID)] = category
	end
end

local function getMonolithicExpansionIndex(atlasLoot)
	local collection = atlasLoot and atlasLoot.ui and atlasLoot.ui.menus and atlasLoot.ui.menus.collection
	local byDataID = {}
	local categoryByDataID = {}
	local foundCollection = false
	if type(collection) ~= "table" then return byDataID, foundCollection, categoryByDataID end

	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		local collectionKey = "DungeonsAndRaids" .. string.upper(expansionKey)
		local entries = collection[collectionKey]
		if type(entries) == "table" then
			foundCollection = true
			for _, entry in ipairs(entries) do
				local dataID = type(entry) == "table" and entry[1]
				indexSourceDataID(byDataID, categoryByDataID, dataID, expansionKey, "instance")
			end
		end
	end

	-- Tier 1-3 are raid rewards, but AtlasLoot exposes them only through the
	-- Classic Collections menu. Do not admit any other collection categories.
	local classicCollections = collection.CollectionsCLASSIC
	if type(classicCollections) == "table" then
		for _, entry in ipairs(classicCollections) do
			local dataID = type(entry) == "table" and entry[1]
			if isTierSetDataID(dataID) then
				indexSourceDataID(byDataID, categoryByDataID, dataID, "classic", "tierSet")
			end
		end
	end

	-- Reputation menus are authoritative for expansion ownership. Their entries
	-- are admitted only when the corresponding AtlasLoot menu and item rows exist.
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		local entries = collection["Factions" .. string.upper(expansionKey)]
		if type(entries) == "table" then
			for _, entry in ipairs(entries) do
				local dataID = type(entry) == "table" and entry[1]
				indexSourceDataID(byDataID, categoryByDataID, dataID, expansionKey, "faction")
			end
		end
	end

	-- Crafting navigation is also authoritative for expansion ownership. A few
	-- Classic-only custom professions are repeated in the TBC navigation; retain
	-- their first (Classic) owner so one source never appears in two expansions.
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		local entries = collection["Crafting" .. string.upper(expansionKey)]
		if type(entries) == "table" then
			for _, entry in ipairs(entries) do
				local dataID = type(entry) == "table" and entry[1]
				if dataID ~= nil and byDataID[dataID] == nil and byDataID[tostring(dataID)] == nil then
					indexSourceDataID(byDataID, categoryByDataID, dataID, expansionKey, "crafting")
				end
			end
		end
	end

	return byDataID, foundCollection, categoryByDataID
end

local function betaExpansionMeta(lootMenu, dataID, expansionByDataID, hasExpansionCollections)
	local moduleMeta = type(lootMenu) == "table" and MODULE_EXPANSIONS[lootMenu.Module]
	if moduleMeta then return moduleMeta end

	local expansionKey = expansionByDataID[dataID] or expansionByDataID[tostring(dataID)]
	if expansionKey then return EXPANSION_META_BY_KEY[expansionKey] end
	if hasExpansionCollections then return nil end

	-- Early 8.x betas may expose menus without the collection index. The exact
	-- dungeon, raid, or crafting type remains a safe fallback, unlike a broad name match.
	expansionKey = type(lootMenu) == "table" and EXPANSION_BY_LOOT_TYPE[lootMenu.Type]
	return expansionKey and EXPANSION_META_BY_KEY[expansionKey] or nil
end

local function ensureExpansionModulesLoaded(atlasLoot, settings, includeAllExpansions)
	local _, hasExpansionCollections = getMonolithicExpansionIndex(atlasLoot)
	if hasExpansionCollections then return end

	settings = settings or {}
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		if includeAllExpansions or expansionEnabled(expansionKey, settings) then
			loadAtlasLootModule(atlasLoot, EXPANSION_MODULE_BY_KEY[expansionKey])
		end
	end
end

local function lootTypeFlags(typeName, placeName)
	if RAID_PLACES[placeName] then return false, true end
	local lootType = tostring(typeName or "")
	local hasDungeon = DUNGEON_TYPES[lootType] or string.find(lootType, "Dungeon", 1, true) ~= nil
	local hasRaid = RAID_TYPES[lootType] or string.find(lootType, "Raid", 1, true) ~= nil
	return hasDungeon and true or false, hasRaid and true or false
end

local function difficultyFromName(value)
	if type(value) == "number" then return value end
	local text = clean(value)
	if not text then return nil end
	local mythicLevel = string.match(text, "^Mythic%s+(%d+)")
	if mythicLevel then
		return DIFFICULTY_MYTHIC + (tonumber(mythicLevel) or 0)
	end
	return DIFFICULTY_BY_NAME[text]
end

local function getAtlasTypeMaxDifficulty(atlasLoot, typeName)
	local difficulties = atlasLoot and atlasLoot.Difficulties
	if difficulties and type(difficulties.GetMax) == "function" then
		local ok, maxDifficulty = pcall(difficulties.GetMax, difficulties, typeName)
		if ok and tonumber(maxDifficulty) then return tonumber(maxDifficulty) end
	end
	local difficultyData = difficulties and typeName and difficulties[typeName]
	return tonumber(difficultyData and difficultyData.Max)
end

local function getMaxDungeonMythicLevelFromAtlasLoot(atlasLoot)
	local maxLevel = 0
	local foundDifficultyData = false
	for typeName in pairs(DUNGEON_TYPES) do
		local maxDifficulty = getAtlasTypeMaxDifficulty(atlasLoot, typeName)
		if maxDifficulty then
			foundDifficultyData = true
		end
		if maxDifficulty and maxDifficulty > DIFFICULTY_MYTHIC then
			local mythicLevel = maxDifficulty - DIFFICULTY_MYTHIC
			if mythicLevel > maxLevel then
				maxLevel = mythicLevel
			end
		end
	end
	if not foundDifficultyData then
		return MAX_DUNGEON_MYTHIC_LEVEL_FALLBACK
	end
	return normalizeDungeonMaxMythicLevel(maxLevel)
end

local function selectedMaxDifficultyForSource(state, sourceMeta, itemRow)
	local typeName = (itemRow and itemRow.Type) or (sourceMeta and sourceMeta.typeName)
	local atlasMax = getAtlasTypeMaxDifficulty(state.atlasLoot, typeName)
	local selectedMax
	if sourceMeta and sourceMeta.isDungeon then
		selectedMax = DIFFICULTY_MYTHIC + normalizeDungeonMaxMythicLevel(state.settings.atlasDungeonMaxMythicLevel)
	elseif sourceMeta and sourceMeta.isRaid then
		selectedMax = normalizeRaidMaxDifficulty(state.settings.atlasRaidMaxDifficulty)
	else
		selectedMax = DIFFICULTY_NORMAL
	end
	if atlasMax and atlasMax < selectedMax then
		selectedMax = atlasMax
	elseif sourceMeta and sourceMeta.isDungeon and selectedMax > (DIFFICULTY_MYTHIC + MAX_DUNGEON_MYTHIC_LEVEL_FALLBACK) then
		selectedMax = DIFFICULTY_MYTHIC + MAX_DUNGEON_MYTHIC_LEVEL_FALLBACK
	end
	if selectedMax < DIFFICULTY_NORMAL then
		selectedMax = DIFFICULTY_NORMAL
	end
	return selectedMax
end

local function itemDifficultyBounds(state, sourceMeta, itemRow)
	local selectedMax = selectedMaxDifficultyForSource(state, sourceMeta, itemRow)
	local minDifficulty = difficultyFromName(itemRow and itemRow.minDifficulty) or DIFFICULTY_NORMAL
	local maxDifficulty = difficultyFromName(itemRow and itemRow.maxDifficulty) or selectedMax
	if minDifficulty < DIFFICULTY_NORMAL then minDifficulty = DIFFICULTY_NORMAL end
	if maxDifficulty > selectedMax then maxDifficulty = selectedMax end
	if maxDifficulty < minDifficulty then return nil, nil end
	return minDifficulty, maxDifficulty
end

local function difficultyDisplayLabel(sourceMeta, difficulty)
	if difficulty == DIFFICULTY_NORMAL then return "N" end
	if difficulty == DIFFICULTY_HEROIC then return "HC" end
	if difficulty == DIFFICULTY_MYTHIC then return "M" end
	if sourceMeta and sourceMeta.isDungeon and difficulty > DIFFICULTY_MYTHIC then
		return "M+" .. tostring(difficulty - DIFFICULTY_MYTHIC)
	end
	if sourceMeta and sourceMeta.isRaid and difficulty == DIFFICULTY_ASCENDED then return "Asc" end
	if difficulty > DIFFICULTY_MYTHIC then return "M+" .. tostring(difficulty - DIFFICULTY_MYTHIC) end
	return tostring(difficulty)
end

local function resolveDifficultyItemID(state, itemID, difficulty, allowOriginalFallback)
	if difficulty == DIFFICULTY_NORMAL then return itemID end
	if type(GetItemDifficultyID) ~= "function" then
		return allowOriginalFallback and itemID or nil
	end

	state.itemDifficultyCache[itemID] = state.itemDifficultyCache[itemID] or {}
	local cached = state.itemDifficultyCache[itemID][difficulty]
	if cached == false then return nil end
	if cached == nil then
		cached = tonumber(GetItemDifficultyID(itemID, difficulty))
		if not cached or cached <= 0 then
			cached = false
		end
		state.itemDifficultyCache[itemID][difficulty] = cached
	end

	if cached == false then
		return allowOriginalFallback and itemID or nil
	end
	if cached ~= itemID or allowOriginalFallback then
		return cached
	end
	return nil
end

-- Adds all configured AtlasLoot difficulty variants for one source row.
local function addDifficultyMappings(state, addMapping, itemRow, itemID)
	local sourceMeta = state.currentSource
	if sourceMeta.isFaction or sourceMeta.isCrafting then
		addMapping(sourceMeta.placeName, sourceMeta.sourceName, itemID)
		return 1
	end

	local minDifficulty, maxDifficulty = itemDifficultyBounds(state, sourceMeta, itemRow)
	if not minDifficulty then return 0 end

	local added = 0
	local seen = {}
	for difficulty = minDifficulty, maxDifficulty do
		local allowOriginalFallback = itemRow.minDifficulty ~= nil and difficulty == minDifficulty
		local difficultyItemID = resolveDifficultyItemID(state, itemID, difficulty, allowOriginalFallback)
		if difficultyItemID and not seen[difficultyItemID] then
			seen[difficultyItemID] = true
			addMapping(sourceMeta.placeName, sourceMeta.sourceName, difficultyItemID, {
				difficultyLabel = difficultyDisplayLabel(sourceMeta, difficulty),
				difficultyRank = difficulty,
				ignoreClassRestriction = sourceMeta.ignoreClassRestriction,
			})
			added = added + 1
		end
	end
	return added
end

local function raidEnabled(placeName, settings)
	local disabledRaids = settings.atlasDisabledRaids or {}
	return not disabledRaids[placeName]
end

local function factionEnabled(placeName, settings)
	local disabledFactions = settings.atlasDisabledFactions or {}
	return not disabledFactions[placeName]
end

local function craftingEnabled(expansionKey, placeName, settings)
	local disabledByExpansion = settings.atlasDisabledCrafting or {}
	local disabledCrafting = disabledByExpansion[expansionKey]
	return type(disabledCrafting) ~= "table" or not disabledCrafting[placeName]
end

local function sourceAllowed(placeName, expansionKey, hasDungeon, hasRaid, isFaction, isCrafting, settings)
	if settings.atlasDisabledPlaces[placeName] then return false end
	if hasDungeon then return true end
	if hasRaid and raidEnabled(placeName, settings) then return true end
	if isFaction and factionEnabled(placeName, settings) then return true end
	if isCrafting and craftingEnabled(expansionKey, placeName, settings) then return true end
	return false
end

local function createSourceChoiceMap()
	local byExpansion = {}
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		byExpansion[expansionKey] = {
			raids = {},
			tierSets = {},
			factions = {},
			crafting = {},
		}
	end
	return byExpansion
end

local function sortedChoiceNames(choiceSet)
	local choices = {}
	for choiceName in pairs(choiceSet or {}) do
		choices[#choices + 1] = choiceName
	end
	table.sort(choices)
	return choices
end

local function buildSourceChoiceGroups(byExpansion)
	local groups = {}
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		local moduleName = EXPANSION_MODULE_BY_KEY[expansionKey]
		local moduleMeta = moduleName and MODULE_EXPANSIONS[moduleName]
		local expansionChoices = byExpansion[expansionKey]
		groups[#groups + 1] = {
			key = expansionKey,
			label = moduleMeta and moduleMeta.label or expansionKey,
			raids = sortedChoiceNames(expansionChoices.raids),
			tierSets = sortedChoiceNames(expansionChoices.tierSets),
			factions = sortedChoiceNames(expansionChoices.factions),
			crafting = sortedChoiceNames(expansionChoices.crafting),
		}
	end
	return groups
end

local function getBetaDataTables(atlasLoot)
	local menusData = atlasLoot and atlasLoot.ui and atlasLoot.ui.menus and atlasLoot.ui.menus.data
	local itemData = atlasLoot and atlasLoot.data and atlasLoot.data.item
	if type(menusData) ~= "table" or type(itemData) ~= "table" then
		return nil, nil
	end
	return menusData, itemData
end

local function itemTableByKey(itemData, tableKey)
	if tableKey == nil then return nil end
	local itemTable = itemData[tableKey]
	if itemTable then return itemTable end
	if type(tableKey) == "number" then
		return itemData[tostring(tableKey)]
	end
	local numericKey = tonumber(tableKey)
	if numericKey then
		return itemData[numericKey] or itemData[tostring(tableKey)]
	end
	return itemData[tostring(tableKey)]
end

local function appendDirectItemRows(rows, itemTable, allowSpellRows)
	if type(itemTable) ~= "table" then return 0 end
	local added = 0
	for _, itemRow in ipairs(itemTable) do
		if type(itemRow) == "table" and (tonumber(itemRow.itemID) or (allowSpellRows and tonumber(itemRow.spellID))) then
			rows[#rows + 1] = itemRow
			added = added + 1
		end
	end
	return added
end

local function appendBetaItemTableRows(itemData, tableKey, rows, seenItemTables, allowSpellRows)
	local itemTable = itemTableByKey(itemData, tableKey)
	if type(itemTable) ~= "table" then return false, 0 end
	if seenItemTables[itemTable] then return true, 0 end
	seenItemTables[itemTable] = true
	return true, appendDirectItemRows(rows, itemTable, allowSpellRows)
end

local function betaMenuHasItemRows(itemData, dataID, lootMenu, allowSpellRows)
	for pageIndex, menuEntry in ipairs(lootMenu or {}) do
		if type(menuEntry) == "table" then
			local rows = {}
			local seenItemTables = {}
			appendBetaItemTableRows(itemData, tostring(dataID) .. tostring(pageIndex), rows, seenItemTables, allowSpellRows)
			if type(menuEntry[2]) == "table" then
				for _, refKey in ipairs(menuEntry[2]) do
					appendBetaItemTableRows(itemData, refKey, rows, seenItemTables, allowSpellRows)
				end
			end
			if #rows > 0 then return true end
		end
	end
	return false
end

local function appendItemRowsDeep(rows, data, visited, depth, allowSpellRows)
	if type(data) ~= "table" then return end
	if visited[data] then return end
	if depth > 6 then return end
	visited[data] = true
	if tonumber(data.itemID) or (allowSpellRows and tonumber(data.spellID)) then
		rows[#rows + 1] = data
		return
	end
	for _, value in pairs(data) do
		appendItemRowsDeep(rows, value, visited, depth + 1, allowSpellRows)
	end
end

local function hasItemRowsDeep(data, allowSpellRows)
	local rows = {}
	appendItemRowsDeep(rows, data, {}, 0, allowSpellRows)
	return #rows > 0
end

local function sortSources(sources)
	table.sort(sources, function(a, b)
		if a.placeName == b.placeName then
			return a.sourceName < b.sourceName
		end
		return a.placeName < b.placeName
	end)
end

-- Builds source records from AtlasLoot 8.x beta menus and item data.
local function buildBetaCollectSources(atlasLoot, settings)
	local menusData, itemData = getBetaDataTables(atlasLoot)
	local expansionByDataID, hasExpansionCollections, categoryByDataID = getMonolithicExpansionIndex(atlasLoot)
	local meta = {
		ready = menusData ~= nil and itemData ~= nil,
		scannedMenus = 0,
		scannedSources = 0,
		missingItemTables = 0,
	}
	local sources = {}
	if not meta.ready then return sources, meta end

	for dataID, lootMenu in pairs(menusData) do
		if type(lootMenu) == "table" then
			local moduleMeta = betaExpansionMeta(lootMenu, dataID, expansionByDataID, hasExpansionCollections)
			local sourceCategory = categoryByDataID[dataID] or categoryByDataID[tostring(dataID)]
			if moduleMeta then
				meta.scannedMenus = meta.scannedMenus + 1
			end
			if moduleMeta and expansionEnabled(moduleMeta.key, settings) then
				local placeName = clean(lootMenu.Name) or clean(dataID) or "Unknown Place"
				local hasDungeon, hasRaid = lootTypeFlags(lootMenu.Type, placeName)
				local isTierSet = sourceCategory == "tierSet" or isTierSetDataID(dataID)
				local isFaction = sourceCategory == "faction"
				local isCrafting = sourceCategory == "crafting" or (not hasExpansionCollections and CRAFTING_TYPES[lootMenu.Type])
				if (hasDungeon or hasRaid or isFaction or isCrafting) and sourceAllowed(placeName, moduleMeta.key, hasDungeon, hasRaid, isFaction, isCrafting, settings) then
					for pageIndex, menuEntry in ipairs(lootMenu) do
						if type(menuEntry) == "table" then
							local rows = {}
							local seenItemTables = {}
							local directFound = appendBetaItemTableRows(itemData, tostring(dataID) .. tostring(pageIndex), rows, seenItemTables, isCrafting)
							if not directFound then
								meta.missingItemTables = meta.missingItemTables + 1
							end
							if type(menuEntry[2]) == "table" then
								for _, refKey in ipairs(menuEntry[2]) do
									appendBetaItemTableRows(itemData, refKey, rows, seenItemTables, isCrafting)
								end
							end
							if #rows > 0 then
								meta.scannedSources = meta.scannedSources + 1
								sources[#sources + 1] = {
									placeName = placeName,
									sourceName = clean(menuEntry[1]) or "Unknown Source",
									typeName = lootMenu.Type,
									isDungeon = hasDungeon,
									isRaid = hasRaid,
									isFaction = isFaction,
									isCrafting = isCrafting,
									ignoreClassRestriction = isTierSet,
									rows = rows,
								}
							end
						end
					end
				end
			end
		end
	end

	sortSources(sources)
	return sources, meta
end

-- Builds source records from legacy AtlasLoot_Data layouts.
local function buildLegacyCollectSources(atlasLoot, atlasData, settings)
	local meta = {
		ready = type(atlasData) == "table",
		scannedMenus = 0,
		scannedSources = 0,
	}
	local sources = {}
	if not meta.ready then return sources, meta end
	local expansionByDataID, _, categoryByDataID = getMonolithicExpansionIndex(atlasLoot)

	for dataID, lootTable in pairs(atlasData) do
		if type(lootTable) == "table" then
			local indexedExpansion = expansionByDataID[dataID] or expansionByDataID[tostring(dataID)]
			local moduleMeta = MODULE_EXPANSIONS[lootTable.Module] or (indexedExpansion and EXPANSION_META_BY_KEY[indexedExpansion])
			local sourceCategory = categoryByDataID[dataID] or categoryByDataID[tostring(dataID)]
			if moduleMeta then
				meta.scannedMenus = meta.scannedMenus + 1
			end
			if moduleMeta and expansionEnabled(moduleMeta.key, settings) then
				local placeName = clean(lootTable.Name) or clean(dataID) or "Unknown Place"
				local hasDungeon, hasRaid = lootTypeFlags(lootTable.Type, placeName)
				local isTierSet = sourceCategory == "tierSet" or isTierSetDataID(dataID)
				local isFaction = sourceCategory == "faction"
				local isCrafting = sourceCategory == "crafting" or CRAFTING_TYPES[lootTable.Type]
				if (hasDungeon or hasRaid or isFaction or isCrafting) and sourceAllowed(placeName, moduleMeta.key, hasDungeon, hasRaid, isFaction, isCrafting, settings) then
					for _, sourceTable in pairs(lootTable) do
						if type(sourceTable) == "table" and sourceTable.Name then
							local rows = {}
							appendItemRowsDeep(rows, sourceTable, {}, 0, isCrafting)
							if #rows > 0 then
								meta.scannedSources = meta.scannedSources + 1
								sources[#sources + 1] = {
									placeName = placeName,
									sourceName = clean(sourceTable.Name) or "Unknown Source",
									typeName = lootTable.Type,
									isDungeon = hasDungeon,
									isRaid = hasRaid,
									isFaction = isFaction,
									isCrafting = isCrafting,
									ignoreClassRestriction = isTierSet,
									rows = rows,
								}
							end
						end
					end
				end
			end
		end
	end

	sortSources(sources)
	return sources, meta
end

local function selectCollectAdapter(atlasLoot, settings)
	local betaSources, betaMeta = buildBetaCollectSources(atlasLoot, settings)
	if betaMeta.ready and (betaMeta.scannedMenus > 0 or not anyExpansionEnabled(settings)) then
		return "atlasloot_v8", betaSources, betaMeta
	end

	local legacySources, legacyMeta = buildLegacyCollectSources(atlasLoot, _G.AtlasLoot_Data, settings)
	if legacyMeta.ready and (legacyMeta.scannedMenus > 0 or not anyExpansionEnabled(settings)) then
		return "legacy", legacySources, legacyMeta
	end

	if betaMeta.ready then
		betaMeta.reason = "AtlasLoot beta data found, but no supported loot-source menus are loaded"
		return "atlasloot_v8", betaSources, betaMeta
	end
	if legacyMeta.ready then
		legacyMeta.reason = "AtlasLoot_Data found, but no supported loot-source tables are loaded"
		return "legacy", legacySources, legacyMeta
	end
	return nil, {}, { reason = "No supported AtlasLoot data layout available" }
end

local function buildBetaSourceChoices(atlasLoot)
	local menusData, itemData = getBetaDataTables(atlasLoot)
	if type(menusData) ~= "table" or type(itemData) ~= "table" then return nil end
	local expansionByDataID, hasExpansionCollections, categoryByDataID = getMonolithicExpansionIndex(atlasLoot)
	local byExpansion = createSourceChoiceMap()
	for dataID, lootMenu in pairs(menusData) do
		if type(lootMenu) == "table" then
			local moduleMeta = betaExpansionMeta(lootMenu, dataID, expansionByDataID, hasExpansionCollections)
			if moduleMeta then
				local placeName = clean(lootMenu.Name) or clean(dataID)
				local _, hasRaid = lootTypeFlags(lootMenu.Type, placeName)
				local sourceCategory = categoryByDataID[dataID] or categoryByDataID[tostring(dataID)]
				if placeName and hasRaid then
					local target = sourceCategory == "tierSet" and byExpansion[moduleMeta.key].tierSets or byExpansion[moduleMeta.key].raids
					target[placeName] = true
				elseif placeName and sourceCategory == "faction" and betaMenuHasItemRows(itemData, dataID, lootMenu, false) then
					byExpansion[moduleMeta.key].factions[placeName] = true
				elseif placeName and sourceCategory == "crafting" and betaMenuHasItemRows(itemData, dataID, lootMenu, true) then
					byExpansion[moduleMeta.key].crafting[placeName] = true
				end
			end
		end
	end
	return buildSourceChoiceGroups(byExpansion)
end

local function buildLegacySourceChoices(atlasLoot, atlasData)
	if type(atlasData) ~= "table" then return nil end
	local byExpansion = createSourceChoiceMap()
	local expansionByDataID, _, categoryByDataID = getMonolithicExpansionIndex(atlasLoot)
	for dataID, lootTable in pairs(atlasData) do
		if type(lootTable) == "table" then
			local indexedExpansion = expansionByDataID[dataID] or expansionByDataID[tostring(dataID)]
			local moduleMeta = MODULE_EXPANSIONS[lootTable.Module] or (indexedExpansion and EXPANSION_META_BY_KEY[indexedExpansion])
			if moduleMeta then
				local placeName = clean(lootTable.Name) or clean(dataID)
				local _, hasRaid = lootTypeFlags(lootTable.Type, placeName)
				local sourceCategory = categoryByDataID[dataID] or categoryByDataID[tostring(dataID)]
				if placeName and hasRaid then
					local target = (sourceCategory == "tierSet" or isTierSetDataID(dataID)) and byExpansion[moduleMeta.key].tierSets or byExpansion[moduleMeta.key].raids
					target[placeName] = true
				elseif placeName and sourceCategory == "faction" and hasItemRowsDeep(lootTable, false) then
					byExpansion[moduleMeta.key].factions[placeName] = true
				elseif placeName and (sourceCategory == "crafting" or CRAFTING_TYPES[lootTable.Type]) and hasItemRowsDeep(lootTable, true) then
					byExpansion[moduleMeta.key].crafting[placeName] = true
				end
			end
		end
	end
	return buildSourceChoiceGroups(byExpansion)
end

local function createDoneState(reason, atlasLoot, adapterName)
	return {
		done = true,
		stats = {
			tables = 0,
			sources = 0,
			items = 0,
			adapter = adapterName or "none",
			version = atlasLootVersion(atlasLoot),
			reason = reason,
		},
	}
end

local function finalizeCurrentSource(state)
	local source = state.currentSource
	if source and state.currentSourceHasItems then
		state.stats.sources = state.stats.sources + 1
		if not state.tableStatsSeen[source.placeName] then
			state.tableStatsSeen[source.placeName] = true
			state.stats.tables = state.stats.tables + 1
		end
	end
	state.currentSource = nil
	state.currentRowCursor = nil
	state.currentSourceHasItems = false
end

function provider.IsAvailable()
	return addonInstalled("AtlasLoot") or resolveAtlasLootObject() ~= nil
end

-- Returns the highest Mythic+ dungeon level exposed by AtlasLoot difficulty metadata.
function provider.GetMaxDungeonMythicLevel()
	if not ensureAtlasLootLoaded() then return MAX_DUNGEON_MYTHIC_LEVEL_FALLBACK end
	local atlasLoot = resolveAtlasLootObject()
	if not atlasLoot then return MAX_DUNGEON_MYTHIC_LEVEL_FALLBACK end
	return getMaxDungeonMythicLevelFromAtlasLoot(atlasLoot)
end

-- Returns selectable raids, tier sets, factions, and crafting professions grouped by AtlasLoot expansion.
function provider.GetSourceChoices(settings)
	local currentTime = nowSeconds()
	if sourceChoicesCache.data and (currentTime - sourceChoicesCache.builtAt) < 10 then
		return sourceChoicesCache.data
	end

	if not ensureAtlasLootLoaded() then return {} end

	local atlasLoot = resolveAtlasLootObject()
	if not atlasLoot then return {} end

	local normalizedSettings = normalizeSettings(settings)
	ensureExpansionModulesLoaded(atlasLoot, normalizedSettings, true)

	local choices = buildBetaSourceChoices(atlasLoot) or buildLegacySourceChoices(atlasLoot, _G.AtlasLoot_Data)
	if not choices then return {} end
	sourceChoicesCache.data = choices
	sourceChoicesCache.builtAt = currentTime
	return sourceChoicesCache.data
end

-- Compatibility for existing ItemScore callers and older integrations.
provider.GetRaidChoices = provider.GetSourceChoices

-- Starts an incremental AtlasLoot scan using the adapter that matches the loaded AtlasLoot version.
function provider.StartCollect(settings)
	local normalizedSettings = normalizeSettings(settings)
	if not ensureAtlasLootLoaded() then
		return createDoneState("AtlasLoot not loaded", nil, "none")
	end

	local atlasLoot = resolveAtlasLootObject()
	if not atlasLoot then
		return createDoneState("AtlasLoot object unavailable", nil, "none")
	end

	ensureExpansionModulesLoaded(atlasLoot, normalizedSettings, false)
	local adapterName, sources, adapterMeta = selectCollectAdapter(atlasLoot, normalizedSettings)
	if not adapterName then
		return createDoneState(adapterMeta.reason or "AtlasLoot data unavailable", atlasLoot, "none")
	end

	return {
		done = false,
		adapterName = adapterName,
		sources = sources,
		sourceCursor = 1,
		currentSource = nil,
		currentRowCursor = nil,
		currentSourceHasItems = false,
		atlasLoot = atlasLoot,
		settings = normalizedSettings,
		itemDifficultyCache = {},
		tableStatsSeen = {},
		stats = {
			tables = 0,
			sources = 0,
			items = 0,
			adapter = adapterName,
			version = atlasLootVersion(atlasLoot),
			availableSources = #sources,
			scannedMenus = adapterMeta.scannedMenus,
			missingItemTables = adapterMeta.missingItemTables,
			reason = adapterMeta.reason,
		},
	}
end

-- Crafting tables primarily store recipe spell IDs. Resolve the crafted result
-- exactly as AtlasLoot's item frame does, retaining an explicit itemID fallback.
local function resolveSourceRowItemID(state, itemRow)
	if state.currentSource and state.currentSource.isCrafting and tonumber(itemRow.spellID) then
		local getCraftedItemID = state.atlasLoot and state.atlasLoot.GetCraftedItemID
		if type(getCraftedItemID) == "function" then
			local ok, craftedItemID = pcall(getCraftedItemID, state.atlasLoot, tonumber(itemRow.spellID))
			craftedItemID = ok and tonumber(craftedItemID) or nil
			if craftedItemID and craftedItemID > 0 then return craftedItemID end
		end
	end
	local itemID = tonumber(itemRow.itemID)
	return itemID and itemID > 0 and itemID or nil
end

-- Processes AtlasLoot rows in small batches so cache rebuilds stay frame-friendly.
function provider.StepCollect(state, addMapping, maxOps)
	if state.done then return true, 0 end

	local budget = tonumber(maxOps) or 50
	if budget < 1 then budget = 1 end
	local ops = 0

	while ops < budget do
		if not state.currentSource then
			local source = state.sources[state.sourceCursor]
			if not source then
				state.done = true
				break
			end
			state.sourceCursor = state.sourceCursor + 1
			state.currentSource = source
			state.currentRowCursor = 1
			state.currentSourceHasItems = false
		end

		local itemRow = state.currentSource.rows[state.currentRowCursor]
		if not itemRow then
			finalizeCurrentSource(state)
		else
			state.currentRowCursor = state.currentRowCursor + 1
			ops = ops + 1
			if type(itemRow) == "table" then
				local itemID = resolveSourceRowItemID(state, itemRow)
				if itemID then
					local added = addDifficultyMappings(state, addMapping, itemRow, itemID)
					if added > 0 then
						state.stats.items = state.stats.items + added
						state.currentSourceHasItems = true
					end
				end
			end
		end
	end

	if state.done then
		finalizeCurrentSource(state)
	end

	return state.done, ops
end

function provider.FinishCollect(state)
	return state.stats
end

function provider.Collect(addMapping, settings)
	local state = provider.StartCollect(settings)
	while not state.done do
		provider.StepCollect(state, addMapping, 500)
	end
	return provider.FinishCollect(state)
end

addon.RegisterSearchProvider(provider.key, provider)
