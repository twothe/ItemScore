local addonName, addon = ...

local provider = {
	key = "AtlasLoot",
}
local raidChoicesCache = {
	data = nil,
	builtAt = 0,
}

local MODULE_EXPANSIONS = {
	["AtlasLoot_OriginalWoW"] = { key = "classic", label = "Classic" },
	["AtlasLoot_BurningCrusade"] = { key = "tbc", label = "Burning Crusade" },
	["AtlasLoot_WrathoftheLichKing"] = { key = "wrath", label = "Wrath of the Lich King" },
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

local function addonInstalled(addonName)
	if type(GetAddOnInfo) ~= "function" then return false end
	local name = GetAddOnInfo(addonName)
	return name ~= nil
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
	if IsAddOnLoaded and IsAddOnLoaded("AtlasLoot") then return true end
	if not addonInstalled("AtlasLoot") then return false end
	local ok = pcall(LoadAddOn, "AtlasLoot")
	return ok and IsAddOnLoaded and IsAddOnLoaded("AtlasLoot")
end

local function expansionEnabled(expansionKey, settings)
	if expansionKey == "classic" then return settings.atlasClassic end
	if expansionKey == "tbc" then return settings.atlasTBC end
	if expansionKey == "wrath" then return settings.atlasWrath end
	return false
end

local function ensureExpansionModulesLoaded(atlasLoot, settings, includeAllExpansions)
	if type(atlasLoot.IsLootTableAvailable) ~= "function" then return end
	local classicEnabled = includeAllExpansions or settings.atlasClassic
	local tbcEnabled = includeAllExpansions or settings.atlasTBC
	local wrathEnabled = includeAllExpansions or settings.atlasWrath

	if classicEnabled then pcall(atlasLoot.IsLootTableAvailable, atlasLoot, "AtlasLootOriginalWoW") end
	if tbcEnabled then pcall(atlasLoot.IsLootTableAvailable, atlasLoot, "AtlasLootBurningCrusade") end
	if wrathEnabled then pcall(atlasLoot.IsLootTableAvailable, atlasLoot, "AtlasLootWotLK") end
end

local function lootTypeFlags(typeName)
	local lootType = tostring(typeName or "")
	local hasDungeon = string.find(lootType, "Dungeon", 1, true) ~= nil
	local hasRaid = string.find(lootType, "Raid", 1, true) ~= nil
	return hasDungeon, hasRaid
end

local function raidEnabled(placeName, settings)
	local disabledRaids = settings.atlasDisabledRaids or {}
	return not disabledRaids[placeName]
end

local function buildRaidChoices(atlasData)
	local byExpansion = {}
	for expansionKey, _ in pairs({ classic = true, tbc = true, wrath = true }) do
		byExpansion[expansionKey] = {}
	end

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

	local groups = {}
	for _, expansionKey in ipairs(EXPANSION_ORDER) do
		local moduleMeta = nil
		for _, info in pairs(MODULE_EXPANSIONS) do
			if info.key == expansionKey then
				moduleMeta = info
				break
			end
		end
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

local function buildCollectTables(atlasData, settings)
	local tables = {}
	for dataID, lootTable in pairs(atlasData) do
		if type(lootTable) == "table" then
			local moduleMeta = MODULE_EXPANSIONS[lootTable.Module]
			if moduleMeta and expansionEnabled(moduleMeta.key, settings) then
				local hasDungeon, hasRaid = lootTypeFlags(lootTable.Type)
				if hasDungeon or hasRaid then
					local placeName = clean(lootTable.Name) or clean(dataID) or "Unknown Place"
					if not settings.atlasDisabledPlaces[placeName] then
						local includeTable = hasDungeon
						if hasRaid and raidEnabled(placeName, settings) then
							includeTable = true
						end
						if includeTable then
							tables[#tables + 1] = {
								lootTable = lootTable,
								placeName = placeName,
							}
						end
					end
				end
			end
		end
	end
	table.sort(tables, function(a, b) return a.placeName < b.placeName end)
	return tables
end

local function finalizeCurrentSource(state)
	if state.currentSource and state.currentSourceHasItems then
		state.stats.sources = state.stats.sources + 1
	end
	state.currentSource = nil
	state.currentSourceCursor = nil
	state.currentSourceHasItems = false
	state.currentSide = nil
	state.currentSideCursor = nil
end

local function finalizeCurrentTable(state)
	finalizeCurrentSource(state)
	if state.currentTable and state.currentTableHasItems then
		state.stats.tables = state.stats.tables + 1
	end
	state.currentTable = nil
	state.currentTableIndex = nil
	state.currentTableCursor = nil
	state.currentTableHasItems = false
end

function provider.IsAvailable()
	return addonInstalled("AtlasLoot")
end

function provider.GetRaidChoices(settings)
	if raidChoicesCache.data and (time() - raidChoicesCache.builtAt) < 10 then
		return raidChoicesCache.data
	end

	if not ensureAtlasLootLoaded() then return {} end

	local atlasLoot = resolveAtlasLootObject()
	if not atlasLoot then return {} end

	ensureExpansionModulesLoaded(atlasLoot, settings or {}, true)

	local atlasData = _G.AtlasLoot_Data
	if type(atlasData) ~= "table" then return {} end
	raidChoicesCache.data = buildRaidChoices(atlasData)
	raidChoicesCache.builtAt = time()
	return raidChoicesCache.data
end

function provider.StartCollect(settings)
	if not ensureAtlasLootLoaded() then
		return {
			done = true,
			stats = {
				tables = 0,
				sources = 0,
				items = 0,
				reason = "AtlasLoot not loaded",
			},
		}
	end

	local atlasLoot = resolveAtlasLootObject()
	if not atlasLoot then
		return {
			done = true,
			stats = {
				tables = 0,
				sources = 0,
				items = 0,
				reason = "AtlasLoot object unavailable",
			},
		}
	end

	ensureExpansionModulesLoaded(atlasLoot, settings, false)
	local atlasData = _G.AtlasLoot_Data
	if type(atlasData) ~= "table" then
		return {
			done = true,
			stats = {
				tables = 0,
				sources = 0,
				items = 0,
				reason = "AtlasLoot_Data unavailable",
			},
		}
	end

	return {
		done = false,
		tables = buildCollectTables(atlasData, settings),
		tableCursor = 1,
		currentTable = nil,
		currentTableIndex = nil,
		currentTableCursor = nil,
		currentTableHasItems = false,
		currentSource = nil,
		currentSourceCursor = nil,
		currentSourceHasItems = false,
		currentSide = nil,
		currentSideCursor = nil,
		stats = {
			tables = 0,
			sources = 0,
			items = 0,
		},
	}
end

function provider.StepCollect(state, addMapping, maxOps)
	if state.done then return true, 0 end

	local budget = tonumber(maxOps) or 50
	if budget < 1 then budget = 1 end
	local ops = 0

	while ops < budget do
		if not state.currentTable then
			local tableEntry = state.tables[state.tableCursor]
			if not tableEntry then
				state.done = true
				break
			end
			state.tableCursor = state.tableCursor + 1
			state.currentTable = tableEntry.lootTable
			state.currentTableIndex = tableEntry.placeName
			state.currentTableCursor = nil
			state.currentTableHasItems = false
		end

		if not state.currentSource then
			local sourceKey, sourceTable = next(state.currentTable, state.currentTableCursor)
			if sourceKey == nil then
				finalizeCurrentTable(state)
			else
				ops = ops + 1
				state.currentTableCursor = sourceKey
				if type(sourceTable) == "table" and sourceTable.Name then
					state.currentSource = sourceTable
					state.currentSourceCursor = nil
					state.currentSourceHasItems = false
				end
			end
		elseif not state.currentSide then
			local sideKey, sideTable = next(state.currentSource, state.currentSourceCursor)
			if sideKey == nil then
				finalizeCurrentSource(state)
			else
				ops = ops + 1
				state.currentSourceCursor = sideKey
				if type(sideTable) == "table" then
					state.currentSide = sideTable
					state.currentSideCursor = nil
				end
			end
		else
			local rowKey, itemRow = next(state.currentSide, state.currentSideCursor)
			if rowKey == nil then
				state.currentSide = nil
				state.currentSideCursor = nil
			else
				state.currentSideCursor = rowKey
				ops = ops + 1
				if type(itemRow) == "table" then
					local itemID = tonumber(itemRow.itemID)
					if itemID and itemID > 0 then
						addMapping(state.currentTableIndex, clean(state.currentSource.Name) or "Unknown Source", itemID)
						state.stats.items = state.stats.items + 1
						state.currentSourceHasItems = true
						state.currentTableHasItems = true
					end
				end
			end
		end
	end

	if state.done then
		finalizeCurrentTable(state)
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
