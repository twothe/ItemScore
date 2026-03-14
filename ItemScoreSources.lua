local addonName, addon = ...

local CACHE_SCHEMA_VERSION = 2
local CACHE_REFRESH_INTERVAL_SECONDS = 24 * 60 * 60

local providers = {}
local providerOrder = {}
local runtime = {
	updating = false,
	pendingRefresh = false,
	queuedRefreshAfterUpdate = false,
	lastError = nil,
	forceRefresh = false,
	task = nil,
}

local EMPTY_CATALOG = {
	itemIDs = {},
	itemSources = {},
	byPlace = {},
	builtAt = 0,
	providerStats = {},
}

local function trim(value)
	if type(value) ~= "string" then return nil end
	local text = string.gsub(value, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then return nil end
	return text
end

local function stripColorCodes(text)
	text = tostring(text or "")
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	text = string.gsub(text, "|T.-|t", "")
	return trim(text)
end

local function defaultSourceSettings()
	return {
		useLootCollector = true,
		useAtlasLoot = true,
		searchUseMaxRequiredLevel = false,
		searchMaxRequiredLevel = 0,
		searchMaxRequiredLevelUserSet = false,
		atlasClassic = true,
		atlasTBC = false,
		atlasWrath = false,
		atlasDisabledPlaces = {},
		atlasDisabledRaids = {},
		worldforgedMC = true,
		worldforgedBWL = true,
		worldforgedNaxx = true,
	}
end

local function ensureSettings()
	if not ItemScoreData then ItemScoreData = {} end
	ItemScoreData.searchSources = ItemScoreData.searchSources or {}

	local defaults = defaultSourceSettings()
	for key, value in pairs(defaults) do
		if ItemScoreData.searchSources[key] == nil then
			if type(value) == "table" then
				ItemScoreData.searchSources[key] = {}
			else
				ItemScoreData.searchSources[key] = value
			end
		end
	end

	if type(ItemScoreData.searchSources.atlasDisabledPlaces) ~= "table" then
		ItemScoreData.searchSources.atlasDisabledPlaces = {}
	end
	if type(ItemScoreData.searchSources.atlasDisabledRaids) ~= "table" then
		ItemScoreData.searchSources.atlasDisabledRaids = {}
	end
	ItemScoreData.searchSources.searchMaxRequiredLevel = tonumber(ItemScoreData.searchSources.searchMaxRequiredLevel) or 0
	if ItemScoreData.searchSources.searchMaxRequiredLevel < 0 then
		ItemScoreData.searchSources.searchMaxRequiredLevel = 0
	end
	if ItemScoreData.searchSources.searchMaxRequiredLevel > 80 then
		ItemScoreData.searchSources.searchMaxRequiredLevel = 80
	end

	if type(ItemScoreData.searchSources.searchMaxRequiredLevelUserSet) ~= "boolean" then
		ItemScoreData.searchSources.searchMaxRequiredLevelUserSet = ItemScoreData.searchSources.searchMaxRequiredLevel > 0
	end

	if not ItemScoreData.searchSources.searchMaxRequiredLevelUserSet and type(UnitLevel) == "function" then
		local playerLevel = tonumber(UnitLevel("player")) or 0
		if playerLevel > 0 then
			if playerLevel > 80 then playerLevel = 80 end
			ItemScoreData.searchSources.searchMaxRequiredLevel = playerLevel
		end
	end

	return ItemScoreData.searchSources
end

local function snapshotSettings(settings)
	return {
		useLootCollector = settings.useLootCollector and true or false,
		useAtlasLoot = settings.useAtlasLoot and true or false,
		searchUseMaxRequiredLevel = settings.searchUseMaxRequiredLevel and true or false,
		searchMaxRequiredLevel = tonumber(settings.searchMaxRequiredLevel) or 0,
		searchMaxRequiredLevelUserSet = settings.searchMaxRequiredLevelUserSet and true or false,
		atlasClassic = settings.atlasClassic and true or false,
		atlasTBC = settings.atlasTBC and true or false,
		atlasWrath = settings.atlasWrath and true or false,
		worldforgedMC = settings.worldforgedMC and true or false,
		worldforgedBWL = settings.worldforgedBWL and true or false,
		worldforgedNaxx = settings.worldforgedNaxx and true or false,
		atlasDisabledPlaces = (function()
			local copy = {}
			for key, value in pairs(settings.atlasDisabledPlaces or {}) do
				copy[key] = value and true or nil
			end
			return copy
		end)(),
		atlasDisabledRaids = (function()
			local copy = {}
			for key, value in pairs(settings.atlasDisabledRaids or {}) do
				copy[key] = value and true or nil
			end
			return copy
		end)(),
	}
end

local function ensureCache()
	if type(ItemScoreCacheDB) ~= "table" then ItemScoreCacheDB = {} end
	if ItemScoreCacheDB.schemaVersion ~= CACHE_SCHEMA_VERSION then
		ItemScoreCacheDB = {
			schemaVersion = CACHE_SCHEMA_VERSION,
			lastBuildAt = 0,
			settingsFingerprint = "",
			catalog = EMPTY_CATALOG,
			providerStats = {},
		}
	end

	if type(ItemScoreCacheDB.catalog) ~= "table" then
		ItemScoreCacheDB.catalog = EMPTY_CATALOG
	end
	if type(ItemScoreCacheDB.catalog.itemIDs) ~= "table" then
		ItemScoreCacheDB.catalog.itemIDs = {}
	end
	if type(ItemScoreCacheDB.catalog.itemSources) ~= "table" then
		ItemScoreCacheDB.catalog.itemSources = {}
	end
	if type(ItemScoreCacheDB.catalog.byPlace) ~= "table" then
		ItemScoreCacheDB.catalog.byPlace = {}
	end
	if type(ItemScoreCacheDB.providerStats) ~= "table" then
		ItemScoreCacheDB.providerStats = {}
	end

	ItemScoreCacheDB.lastBuildAt = tonumber(ItemScoreCacheDB.lastBuildAt) or 0
	ItemScoreCacheDB.settingsFingerprint = ItemScoreCacheDB.settingsFingerprint or ""
	return ItemScoreCacheDB
end

local function settingsFingerprint(settings)
	local disabledPlaces = {}
	for placeName, disabled in pairs(settings.atlasDisabledPlaces or {}) do
		if disabled then
			local clean = stripColorCodes(placeName)
			if clean then disabledPlaces[#disabledPlaces + 1] = clean end
		end
	end
	table.sort(disabledPlaces)

	local disabledRaids = {}
	for raidName, disabled in pairs(settings.atlasDisabledRaids or {}) do
		if disabled then
			local clean = stripColorCodes(raidName)
			if clean then disabledRaids[#disabledRaids + 1] = clean end
		end
	end
	table.sort(disabledRaids)

	local parts = {
		settings.useLootCollector and "1" or "0",
		settings.useAtlasLoot and "1" or "0",
		settings.atlasClassic and "1" or "0",
		settings.atlasTBC and "1" or "0",
		settings.atlasWrath and "1" or "0",
		settings.worldforgedMC and "1" or "0",
		settings.worldforgedBWL and "1" or "0",
		settings.worldforgedNaxx and "1" or "0",
		table.concat(disabledPlaces, ","),
		table.concat(disabledRaids, ","),
	}

	return table.concat(parts, "|")
end

local function scheduleAfter(seconds, callback)
	if C_Timer and C_Timer.After then
		C_Timer.After(seconds, callback)
		return
	end

	local timerFrame = CreateFrame("Frame")
	local remaining = tonumber(seconds) or 0
	timerFrame:SetScript("OnUpdate", function(self, elapsed)
		remaining = remaining - elapsed
		if remaining <= 0 then
			self:SetScript("OnUpdate", nil)
			callback()
		end
	end)
end

local function nowMillis()
	if type(debugprofilestop) == "function" then
		return debugprofilestop()
	end
	if type(GetTime) == "function" then
		return GetTime() * 1000
	end
	return 0
end

local function tuneBudget(currentBudget, elapsedMs, targetMs)
	local budget = tonumber(currentBudget) or 200
	if budget < 20 then budget = 20 end
	if elapsedMs <= 0 then
		budget = budget * 1.2
	elseif elapsedMs < (targetMs * 0.7) then
		budget = budget * 1.25
	elseif elapsedMs > (targetMs * 1.6) then
		budget = budget * 0.60
	elseif elapsedMs > (targetMs * 1.2) then
		budget = budget * 0.80
	elseif elapsedMs < (targetMs * 0.9) then
		budget = budget * 1.08
	end
	budget = math.floor(budget + 0.5)
	if budget < 20 then budget = 20 end
	if budget > 10000 then budget = 10000 end
	return budget
end

local function providerEnabled(providerKey, settings)
	if providerKey == "LootCollector" then return settings.useLootCollector end
	if providerKey == "AtlasLoot" then return settings.useAtlasLoot end
	return true
end

local function createCollector()
	local byPlaceSets = {}
	local itemSourcesSets = {}
	local uniqueItemIDs = {}
	local mappingCount = 0

	local function addMapping(place, source, itemID)
		local numericItemID = tonumber(itemID)
		if not numericItemID or numericItemID <= 0 then return end

		local placeName = stripColorCodes(place) or "Unknown Zone"
		local sourceName = stripColorCodes(source) or "Unknown Source"

		byPlaceSets[placeName] = byPlaceSets[placeName] or {}
		byPlaceSets[placeName][sourceName] = byPlaceSets[placeName][sourceName] or {}
		if not byPlaceSets[placeName][sourceName][numericItemID] then
			byPlaceSets[placeName][sourceName][numericItemID] = true
			mappingCount = mappingCount + 1
		end

		uniqueItemIDs[numericItemID] = true

		itemSourcesSets[numericItemID] = itemSourcesSets[numericItemID] or {}
		local key = placeName .. "\031" .. sourceName
		itemSourcesSets[numericItemID][key] = {
			place = placeName,
			source = sourceName,
		}
	end

	local function finalize()
		local itemIDs = {}
		for itemID in pairs(uniqueItemIDs) do
			itemIDs[#itemIDs + 1] = itemID
		end
		table.sort(itemIDs)

		local itemSources = {}
		for itemID, sourceSet in pairs(itemSourcesSets) do
			local list = {}
			for _, sourceData in pairs(sourceSet) do
				list[#list + 1] = {
					place = sourceData.place,
					source = sourceData.source,
				}
			end
			table.sort(list, function(a, b)
				if a.place == b.place then return a.source < b.source end
				return a.place < b.place
			end)
			itemSources[itemID] = list
		end

		local byPlace = {}
		for placeName, sourceMap in pairs(byPlaceSets) do
			byPlace[placeName] = {}
			for sourceName, itemIDSet in pairs(sourceMap) do
				local list = {}
				for itemID in pairs(itemIDSet) do
					list[#list + 1] = itemID
				end
				table.sort(list)
				byPlace[placeName][sourceName] = list
			end
		end

		return {
			itemIDs = itemIDs,
			itemSources = itemSources,
			byPlace = byPlace,
			mappingCount = mappingCount,
		}
	end

	return addMapping, finalize
end

local function isCacheStale(settings, cache)
	if runtime.forceRefresh then return true end
	if cache.lastBuildAt <= 0 then return true end
	if (time() - cache.lastBuildAt) >= CACHE_REFRESH_INTERVAL_SECONDS then return true end
	if cache.settingsFingerprint ~= settingsFingerprint(settings) then return true end
	return false
end

local function buildTaskDone(task)
	return task.providerIndex > #providerOrder and task.activeProvider == nil
end

local function startNextProvider(task)
	while task.providerIndex <= #providerOrder do
		local providerKey = providerOrder[task.providerIndex]
		task.providerIndex = task.providerIndex + 1
		local provider = providers[providerKey]
		if not provider then
			task.providerStats[providerKey] = {
				ok = false,
				skipped = true,
				reason = "missing",
			}
		elseif not providerEnabled(providerKey, task.settings) then
			task.providerStats[providerKey] = {
				ok = false,
				skipped = true,
				reason = "disabled",
			}
		else
			local available = true
			if type(provider.IsAvailable) == "function" then
				local ok, isAvailable = pcall(provider.IsAvailable, task.settings)
				available = ok and (isAvailable ~= false)
			end

			if not available then
				task.providerStats[providerKey] = {
					ok = false,
					skipped = true,
					reason = "unavailable",
				}
			elseif type(provider.StartCollect) == "function"
				and type(provider.StepCollect) == "function"
				and type(provider.FinishCollect) == "function" then
				local ok, providerState = pcall(provider.StartCollect, task.settings)
				if not ok then
					task.providerStats[providerKey] = {
						ok = false,
						error = tostring(providerState),
					}
				else
					task.activeProvider = {
						key = providerKey,
						provider = provider,
						state = providerState,
					}
					task.currentProviderKey = providerKey
					return true
				end
			elseif type(provider.Collect) == "function" then
				local ok, statsOrErr = pcall(provider.Collect, task.addMapping, task.settings)
				if ok then
					task.providerStats[providerKey] = type(statsOrErr) == "table" and statsOrErr or { ok = true }
					task.providerStats[providerKey].ok = true
				else
					task.providerStats[providerKey] = {
						ok = false,
						error = tostring(statsOrErr),
					}
				end
			else
				task.providerStats[providerKey] = {
					ok = false,
					skipped = true,
					reason = "no_collect_method",
				}
			end
		end
	end

	task.currentProviderKey = nil
	return false
end

local function processTask(task, maxOps)
	local budget = tonumber(maxOps) or 200
	if budget < 1 then budget = 1 end
	local consumed = 0

	while consumed < budget do
		if not task.activeProvider then
			if not startNextProvider(task) then
				return buildTaskDone(task)
			end
		end

		local active = task.activeProvider
		local remaining = budget - consumed
		local ok, done, usedOrErr = pcall(active.provider.StepCollect, active.state, task.addMapping, remaining, task.settings)
		if not ok then
			task.providerStats[active.key] = {
				ok = false,
				error = tostring(done),
			}
			task.activeProvider = nil
			task.currentProviderKey = nil
		else
			local used = tonumber(usedOrErr) or 1
			if used < 1 then used = 1 end
			if used > remaining then used = remaining end
			consumed = consumed + used

			if done then
				local finishOk, statsOrErr = pcall(active.provider.FinishCollect, active.state, task.settings)
				if finishOk then
					task.providerStats[active.key] = type(statsOrErr) == "table" and statsOrErr or { ok = true }
					task.providerStats[active.key].ok = true
				else
					task.providerStats[active.key] = {
						ok = false,
						error = tostring(statsOrErr),
					}
				end
				task.activeProvider = nil
				task.currentProviderKey = nil
			end
		end
	end

	return buildTaskDone(task)
end

local function finishTask(task)
	local cache = ensureCache()
	local catalog = task.finalizeCollector()
	catalog.providerStats = task.providerStats
	catalog.builtAt = time()

	cache.catalog = catalog
	cache.lastBuildAt = time()
	cache.providerStats = task.providerStats
	cache.settingsFingerprint = settingsFingerprint(task.settings)

	runtime.task = nil
	runtime.updating = false
	runtime.lastError = nil
	runtime.forceRefresh = false

	if not task.silent then
		print(string.format("|cff00ff00ItemScore:|r search cache updated (%d items).", #catalog.itemIDs))
	end

	if runtime.queuedRefreshAfterUpdate then
		runtime.queuedRefreshAfterUpdate = false
		addon.QueueSearchCacheRefresh("post_update")
	end
end

local function failTask(task, message)
	runtime.task = nil
	runtime.updating = false
	runtime.lastError = tostring(message)

	if not task.silent then
		print("|cffff7f00ItemScore:|r search cache update failed: " .. runtime.lastError)
	end

	if runtime.queuedRefreshAfterUpdate then
		runtime.queuedRefreshAfterUpdate = false
		addon.QueueSearchCacheRefresh("post_update_error")
	end
end

local updateFrame = CreateFrame("Frame")
local function updateFrameOnUpdate(self)
	local task = runtime.task
	if not task then
		self:SetScript("OnUpdate", nil)
		return
	end

	local startMs = nowMillis()
	local ok, doneOrErr = pcall(processTask, task, task.opsBudget)
	local elapsedMs = nowMillis() - startMs
	task.opsBudget = tuneBudget(task.opsBudget, elapsedMs, task.targetMs)

	if not ok then
		failTask(task, doneOrErr)
		self:SetScript("OnUpdate", nil)
		return
	end

	if doneOrErr then
		finishTask(task)
		self:SetScript("OnUpdate", nil)
	end
end

function addon.RegisterSearchProvider(providerKey, provider)
	assert(type(providerKey) == "string" and providerKey ~= "", "providerKey missing")
	assert(type(provider) == "table", "provider missing")
	if providers[providerKey] then
		providers[providerKey] = provider
		return
	end
	providers[providerKey] = provider
	providerOrder[#providerOrder + 1] = providerKey
end

function addon.GetSearchSourceSettings()
	return ensureSettings()
end

function addon.SetSearchSourceOption(optionKey, value)
	local settings = ensureSettings()

	if optionKey == "searchMaxRequiredLevel" then
		local numeric = math.floor(tonumber(value) or 0)
		if numeric < 0 then numeric = 0 end
		if numeric > 80 then numeric = 80 end
		local changed = false
		if settings.searchMaxRequiredLevel ~= numeric then
			settings.searchMaxRequiredLevel = numeric
			changed = true
		end
		if settings.searchMaxRequiredLevelUserSet ~= true then
			settings.searchMaxRequiredLevelUserSet = true
			changed = true
		end
		return changed
	end

	if optionKey == "atlasDungeon" then
		return false
	end

	if optionKey == "atlasRaid" then
		local changed = addon.SetAllAtlasLootRaidsEnabled(value)
		return changed
	end

	if settings[optionKey] == nil then return false end
	local boolValue = value and true or false
	if settings[optionKey] == boolValue then return false end
	settings[optionKey] = boolValue
	runtime.forceRefresh = true
	return true
end

function addon.SetAtlasLootPlaceEnabled(placeName, enabled)
	local clean = stripColorCodes(placeName)
	if not clean then return false end

	local settings = ensureSettings()
	local disabledPlaces = settings.atlasDisabledPlaces
	local current = disabledPlaces[clean] and true or false
	local targetDisabled = not enabled
	if current == targetDisabled then return false end

	disabledPlaces[clean] = targetDisabled or nil
	runtime.forceRefresh = true
	return true
end

function addon.GetDisabledAtlasLootPlaces()
	local settings = ensureSettings()
	local list = {}
	for placeName, disabled in pairs(settings.atlasDisabledPlaces) do
		if disabled then list[#list + 1] = placeName end
	end
	table.sort(list)
	return list
end

function addon.SetAtlasLootRaidEnabled(raidName, enabled)
	local clean = stripColorCodes(raidName)
	if not clean then return false end

	local settings = ensureSettings()
	local disabledRaids = settings.atlasDisabledRaids
	local current = disabledRaids[clean] and true or false
	local targetDisabled = not enabled
	if current == targetDisabled then return false end

	disabledRaids[clean] = targetDisabled or nil
	runtime.forceRefresh = true
	return true
end

function addon.GetDisabledAtlasLootRaids()
	local settings = ensureSettings()
	local list = {}
	for raidName, disabled in pairs(settings.atlasDisabledRaids) do
		if disabled then list[#list + 1] = raidName end
	end
	table.sort(list)
	return list
end

function addon.GetAtlasLootRaidChoices()
	local provider = providers["AtlasLoot"]
	if not provider or type(provider.GetRaidChoices) ~= "function" then return {} end

	local settings = ensureSettings()
	local ok, raidChoices = pcall(provider.GetRaidChoices, settings)
	if not ok or type(raidChoices) ~= "table" then
		return {}
	end
	return raidChoices
end

function addon.SetAllAtlasLootRaidsEnabled(enabled)
	local settings = ensureSettings()
	local provider = providers["AtlasLoot"]
	if not provider or type(provider.GetRaidChoices) ~= "function" then return false end

	local ok, raidChoices = pcall(provider.GetRaidChoices, settings)
	if not ok or type(raidChoices) ~= "table" then return false end

	local changed = false
	for _, group in ipairs(raidChoices) do
		for _, raidName in ipairs(group.raids or {}) do
			local current = settings.atlasDisabledRaids[raidName] and true or false
			local target = not enabled
			if current ~= target then
				settings.atlasDisabledRaids[raidName] = target or nil
				changed = true
			end
		end
	end

	if changed then
		runtime.forceRefresh = true
	end

	return changed
end

function addon.GetKnownSearchPlaces()
	local cache = ensureCache()
	local places = {}
	local byPlace = cache.catalog and cache.catalog.byPlace or {}
	for placeName in pairs(byPlace) do
		places[#places + 1] = placeName
	end
	table.sort(places)
	return places
end

function addon.RefreshSearchCache(forceRefresh, silent)
	local settings = ensureSettings()
	local cache = ensureCache()

	if runtime.updating then
		if forceRefresh then
			runtime.forceRefresh = true
			runtime.queuedRefreshAfterUpdate = true
		end
		return false, "busy"
	end

	if not forceRefresh and not isCacheStale(settings, cache) then
		return false, "fresh"
	end

	local addMapping, finalizeCollector = createCollector()
	runtime.task = {
		settings = snapshotSettings(settings),
		addMapping = addMapping,
		finalizeCollector = finalizeCollector,
		providerStats = {},
		providerIndex = 1,
		activeProvider = nil,
		currentProviderKey = nil,
		opsBudget = 220,
		targetMs = 6,
		silent = silent and true or false,
	}
	runtime.updating = true
	runtime.lastError = nil

	updateFrame:SetScript("OnUpdate", updateFrameOnUpdate)
	return true, "started"
end

function addon.QueueSearchCacheRefresh(reason)
	runtime.forceRefresh = true
	if runtime.updating then
		runtime.queuedRefreshAfterUpdate = true
		return
	end
	if runtime.pendingRefresh then return end

	runtime.pendingRefresh = true
	scheduleAfter(2, function()
		runtime.pendingRefresh = false
		addon.RefreshSearchCache(true, true)
	end)
end

function addon.GetSearchCacheStatus()
	local settings = ensureSettings()
	local cache = ensureCache()
	local stale = isCacheStale(settings, cache)
	local catalog = cache.catalog or EMPTY_CATALOG

	local providerMeta = {}
	local availableProviderCount = 0
	local enabledProviderCount = 0
	for _, providerKey in ipairs(providerOrder) do
		local provider = providers[providerKey]
		local enabled = providerEnabled(providerKey, settings)
		if enabled then enabledProviderCount = enabledProviderCount + 1 end

		local available = false
		if provider and type(provider.IsAvailable) == "function" then
			local ok, isAvailable = pcall(provider.IsAvailable, settings)
			available = ok and (isAvailable ~= false)
		elseif provider then
			available = true
		end
		if available then availableProviderCount = availableProviderCount + 1 end

		providerMeta[providerKey] = {
			enabled = enabled,
			available = available,
			last = cache.providerStats[providerKey],
		}
	end

	return {
		updating = runtime.updating,
		stale = stale,
		lastBuildAt = cache.lastBuildAt,
		itemCount = #(catalog.itemIDs or {}),
		lastError = runtime.lastError,
		enabledProviderCount = enabledProviderCount,
		availableProviderCount = availableProviderCount,
		providers = providerMeta,
		currentProvider = runtime.task and runtime.task.currentProviderKey or nil,
		opsBudget = runtime.task and runtime.task.opsBudget or nil,
		queuedRefresh = runtime.queuedRefreshAfterUpdate,
	}
end

function addon.GetSearchCatalog()
	local settings = ensureSettings()
	local cache = ensureCache()

	local stale = isCacheStale(settings, cache)
	if stale and not runtime.updating then
		addon.QueueSearchCacheRefresh("stale")
	end

	return cache.catalog or EMPTY_CATALOG, addon.GetSearchCacheStatus()
end

local refreshEvents = {
	["LootCollector"] = true,
	["AtlasLoot"] = true,
	["AtlasLoot_OriginalWoW"] = true,
	["AtlasLoot_BurningCrusade"] = true,
	["AtlasLoot_WrathoftheLichKing"] = true,
}

local sourceEventFrame = CreateFrame("Frame")
sourceEventFrame:RegisterEvent("PLAYER_LOGIN")
sourceEventFrame:RegisterEvent("ADDON_LOADED")
sourceEventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		addon.QueueSearchCacheRefresh("login")
		return
	end

	if event == "ADDON_LOADED" and refreshEvents[arg1] then
		addon.QueueSearchCacheRefresh("addon_loaded:" .. tostring(arg1))
	end
end)
