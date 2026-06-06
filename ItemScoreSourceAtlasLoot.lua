local addonName, addon = ...

local provider = {
	key = "AtlasLoot",
}
local raidChoicesCache = {
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
	BCkarazhanCrypts = true,
	WrathDungeon = true,
}

local RAID_TYPES = {
	ClassicRaid = true,
	BCRaid = true,
	WrathRaid = true,
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

local function resolveAtlasLootObject()
	if _G.ATLASLOOT then return _G.ATLASLOOT end
	if _G.AtlasLoot then return _G.AtlasLoot end
	if type(LibStub) ~= "function" then return nil end

	local ok, atlasLoot = pcall(function()
		local aceAddon = LibStub("AceAddon-3.0", true)
		if not aceAddon then return nil end
		return aceAddon:GetAddon("AtlasLoot", true)
	end)
	if ok then return atlasLoot end
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

local function ensureExpansionModulesLoaded(atlasLoot, settings, includeAllExpansions)
	settings = settings or {}
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		if includeAllExpansions or expansionEnabled(expansionKey, settings) then
			loadAtlasLootModule(atlasLoot, EXPANSION_MODULE_BY_KEY[expansionKey])
		end
	end
end

local function lootTypeFlags(typeName)
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

local function sourceAllowed(placeName, hasDungeon, hasRaid, settings)
	if settings.atlasDisabledPlaces[placeName] then return false end
	if hasDungeon then return true end
	if hasRaid and raidEnabled(placeName, settings) then return true end
	return false
end

local function createRaidChoiceMap()
	local byExpansion = {}
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		byExpansion[expansionKey] = {}
	end
	return byExpansion
end

local function buildRaidChoiceGroups(byExpansion)
	local groups = {}
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		local moduleName = EXPANSION_MODULE_BY_KEY[expansionKey]
		local moduleMeta = moduleName and MODULE_EXPANSIONS[moduleName]
		local raids = {}
		for raidName in pairs(byExpansion[expansionKey]) do
			raids[#raids + 1] = raidName
		end
		table.sort(raids)
		groups[#groups + 1] = {
			key = expansionKey,
			label = moduleMeta and moduleMeta.label or expansionKey,
			raids = raids,
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

local function appendDirectItemRows(rows, itemTable)
	if type(itemTable) ~= "table" then return 0 end
	local added = 0
	for _, itemRow in ipairs(itemTable) do
		if type(itemRow) == "table" and tonumber(itemRow.itemID) then
			rows[#rows + 1] = itemRow
			added = added + 1
		end
	end
	return added
end

local function appendBetaItemTableRows(itemData, tableKey, rows, seenItemTables)
	local itemTable = itemTableByKey(itemData, tableKey)
	if type(itemTable) ~= "table" then return false, 0 end
	if seenItemTables[itemTable] then return true, 0 end
	seenItemTables[itemTable] = true
	return true, appendDirectItemRows(rows, itemTable)
end

local function appendItemRowsDeep(rows, data, visited, depth)
	if type(data) ~= "table" then return end
	if visited[data] then return end
	if depth > 6 then return end
	visited[data] = true
	if tonumber(data.itemID) then
		rows[#rows + 1] = data
		return
	end
	for _, value in pairs(data) do
		appendItemRowsDeep(rows, value, visited, depth + 1)
	end
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
			local moduleMeta = MODULE_EXPANSIONS[lootMenu.Module]
			if moduleMeta then
				meta.scannedMenus = meta.scannedMenus + 1
			end
			if moduleMeta and expansionEnabled(moduleMeta.key, settings) then
				local hasDungeon, hasRaid = lootTypeFlags(lootMenu.Type)
				local placeName = clean(lootMenu.Name) or clean(dataID) or "Unknown Place"
				if (hasDungeon or hasRaid) and sourceAllowed(placeName, hasDungeon, hasRaid, settings) then
					for pageIndex, menuEntry in ipairs(lootMenu) do
						if type(menuEntry) == "table" then
							local rows = {}
							local seenItemTables = {}
							local directFound = appendBetaItemTableRows(itemData, tostring(dataID) .. tostring(pageIndex), rows, seenItemTables)
							if not directFound then
								meta.missingItemTables = meta.missingItemTables + 1
							end
							if type(menuEntry[2]) == "table" then
								for _, refKey in ipairs(menuEntry[2]) do
									appendBetaItemTableRows(itemData, refKey, rows, seenItemTables)
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
local function buildLegacyCollectSources(atlasData, settings)
	local meta = {
		ready = type(atlasData) == "table",
		scannedMenus = 0,
		scannedSources = 0,
	}
	local sources = {}
	if not meta.ready then return sources, meta end

	for dataID, lootTable in pairs(atlasData) do
		if type(lootTable) == "table" then
			local moduleMeta = MODULE_EXPANSIONS[lootTable.Module]
			if moduleMeta then
				meta.scannedMenus = meta.scannedMenus + 1
			end
			if moduleMeta and expansionEnabled(moduleMeta.key, settings) then
				local hasDungeon, hasRaid = lootTypeFlags(lootTable.Type)
				local placeName = clean(lootTable.Name) or clean(dataID) or "Unknown Place"
				if (hasDungeon or hasRaid) and sourceAllowed(placeName, hasDungeon, hasRaid, settings) then
					for _, sourceTable in pairs(lootTable) do
						if type(sourceTable) == "table" and sourceTable.Name then
							local rows = {}
							appendItemRowsDeep(rows, sourceTable, {}, 0)
							if #rows > 0 then
								meta.scannedSources = meta.scannedSources + 1
								sources[#sources + 1] = {
									placeName = placeName,
									sourceName = clean(sourceTable.Name) or "Unknown Source",
									typeName = lootTable.Type,
									isDungeon = hasDungeon,
									isRaid = hasRaid,
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

	local legacySources, legacyMeta = buildLegacyCollectSources(_G.AtlasLoot_Data, settings)
	if legacyMeta.ready and (legacyMeta.scannedMenus > 0 or not anyExpansionEnabled(settings)) then
		return "legacy", legacySources, legacyMeta
	end

	if betaMeta.ready then
		betaMeta.reason = "AtlasLoot beta data found, but no supported dungeon or raid menus are loaded"
		return "atlasloot_v8", betaSources, betaMeta
	end
	if legacyMeta.ready then
		legacyMeta.reason = "AtlasLoot_Data found, but no supported dungeon or raid tables are loaded"
		return "legacy", legacySources, legacyMeta
	end
	return nil, {}, { reason = "No supported AtlasLoot data layout available" }
end

local function buildBetaRaidChoices(atlasLoot)
	local menusData = getBetaDataTables(atlasLoot)
	if type(menusData) ~= "table" then return nil end
	local byExpansion = createRaidChoiceMap()
	for dataID, lootMenu in pairs(menusData) do
		if type(lootMenu) == "table" then
			local moduleMeta = MODULE_EXPANSIONS[lootMenu.Module]
			if moduleMeta then
				local _, hasRaid = lootTypeFlags(lootMenu.Type)
				if hasRaid then
					local placeName = clean(lootMenu.Name) or clean(dataID)
					if placeName then
						byExpansion[moduleMeta.key][placeName] = true
					end
				end
			end
		end
	end
	return buildRaidChoiceGroups(byExpansion)
end

local function buildLegacyRaidChoices(atlasData)
	if type(atlasData) ~= "table" then return nil end
	local byExpansion = createRaidChoiceMap()
	for dataID, lootTable in pairs(atlasData) do
		if type(lootTable) == "table" then
			local moduleMeta = MODULE_EXPANSIONS[lootTable.Module]
			if moduleMeta then
				local _, hasRaid = lootTypeFlags(lootTable.Type)
				if hasRaid then
					local placeName = clean(lootTable.Name) or clean(dataID)
					if placeName then
						byExpansion[moduleMeta.key][placeName] = true
					end
				end
			end
		end
	end
	return buildRaidChoiceGroups(byExpansion)
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

-- Returns raid names grouped by AtlasLoot expansion for the source settings UI.
function provider.GetRaidChoices(settings)
	local currentTime = nowSeconds()
	if raidChoicesCache.data and (currentTime - raidChoicesCache.builtAt) < 10 then
		return raidChoicesCache.data
	end

	if not ensureAtlasLootLoaded() then return {} end

	local atlasLoot = resolveAtlasLootObject()
	if not atlasLoot then return {} end

	local normalizedSettings = normalizeSettings(settings)
	ensureExpansionModulesLoaded(atlasLoot, normalizedSettings, true)

	local choices = buildBetaRaidChoices(atlasLoot) or buildLegacyRaidChoices(_G.AtlasLoot_Data)
	if not choices then return {} end
	raidChoicesCache.data = choices
	raidChoicesCache.builtAt = currentTime
	return raidChoicesCache.data
end

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
				local itemID = tonumber(itemRow.itemID)
				if itemID and itemID > 0 then
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
