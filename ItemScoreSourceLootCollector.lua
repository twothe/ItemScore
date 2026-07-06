local addonName, addon = ...

-- LootCollector search provider: selects the safest available data adapter and emits normalized item-source mappings.
local provider = {
	key = "LootCollector",
}

local LOOTCOLLECTOR_ADDON = "LootCollector"
local LOOTCOLLECTOR_STARTER_DB_ADDON = "LootCollector_StarterDB"
local LOOTCOLLECTOR_CUSTOM_IMPORT_ADDON = "LootCollector_CustomImport"

local WORLDFORGED_TIERS = {
	{ settingKey = "worldforgedZG", difficulty = 5, label = "Worldforged Zul'Gurub", difficultyLabel = "WF ZG" },
	{ settingKey = "worldforgedMC", difficulty = 6, label = "Worldforged MC", difficultyLabel = "WF MC" },
	{ settingKey = "worldforgedBWL", difficulty = 7, label = "Worldforged BWL", difficultyLabel = "WF BWL" },
	{ settingKey = "worldforgedNaxx", difficulty = 9, label = "Worldforged Naxxramas", difficultyLabel = "WF Naxx" },
}

local function clean(text)
	if type(text) ~= "string" then return nil end
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

local function resolveLootCollectorObject()
	if type(_G.LootCollector) == "table" then
		return _G.LootCollector
	end
	if type(LibStub) ~= "function" then return nil end

	local ok, lootCollector = pcall(function()
		local aceAddon = LibStub("AceAddon-3.0", true)
		if not aceAddon then return nil end
		return aceAddon:GetAddon("LootCollector", true)
	end)
	if ok and type(lootCollector) == "table" then return lootCollector end
	return nil
end

local function ensureLootCollectorLoaded()
	if resolveLootCollectorObject() then return true end
	if addonLoaded(LOOTCOLLECTOR_ADDON) then return true end
	if not addonInstalled(LOOTCOLLECTOR_ADDON) then return false end
	loadAddonIfInstalled(LOOTCOLLECTOR_ADDON)
	return resolveLootCollectorObject() ~= nil or addonLoaded(LOOTCOLLECTOR_ADDON)
end

local function callMethod(object, methodName, ...)
	local method = object and object[methodName]
	if type(method) ~= "function" then return false, nil end
	return pcall(method, object, ...)
end

local function rawDBRoot()
	return type(_G.LootCollectorDB_Asc) == "table" and _G.LootCollectorDB_Asc or nil
end

local function resolveRealmKey(lootCollector)
	local ok, realmKey = callMethod(lootCollector, "GetActiveRealmKey")
	realmKey = ok and clean(realmKey) or nil
	if realmKey then return realmKey end

	realmKey = clean(lootCollector and lootCollector.activeRealmKey)
	if realmKey then return realmKey end

	if type(GetRealmName) == "function" then
		realmKey = clean(GetRealmName())
		if realmKey then return realmKey end
	end

	return "Unknown Realm"
end

local function selectSingleRealmBucket(realms)
	local selectedBucket
	for _, bucket in pairs(realms or {}) do
		if selectedBucket ~= nil then return nil end
		selectedBucket = bucket
	end
	return selectedBucket
end

local function resolveRealmBucket(dbRoot, lootCollector)
	local globalDB = dbRoot and dbRoot.global
	local realms = globalDB and globalDB.realms
	if type(realms) ~= "table" then return nil end

	local realmKey = resolveRealmKey(lootCollector)
	local bucket = realms[realmKey]
	if type(bucket) == "table" then return bucket, realmKey end

	bucket = selectSingleRealmBucket(realms)
	if type(bucket) == "table" then return bucket, "single-realm-fallback" end
	return nil, realmKey
end

local function hasUsableRecords(discoveries, vendors)
	return type(discoveries) == "table" or type(vendors) == "table"
end

local function resolveZoneName(lootCollector, record)
	local c = tonumber(record and record.c) or 0
	local z = tonumber(record and record.z) or 0
	local iz = tonumber(record and record.iz) or 0

	if type(lootCollector) == "table" and type(lootCollector.ResolveZoneDisplay) == "function" then
		local zoneName = lootCollector.ResolveZoneDisplay(c, z, iz)
		zoneName = clean(zoneName)
		if zoneName then return zoneName end
	end

	if type(lootCollector) == "table" and type(lootCollector.GetModule) == "function" then
		local ok, zoneList = pcall(lootCollector.GetModule, lootCollector, "ZoneList", true)
		if ok and type(zoneList) == "table" and type(zoneList.MapDataByID) == "table" then
			local zoneData = zoneList.MapDataByID[z]
			local zoneName = clean(zoneData and zoneData.name)
			if zoneName then return zoneName end
		end
	end

	if z > 0 then return "Zone " .. z end
	return "Unknown Zone"
end

local function resolveDiscoveryTypes(lootCollector)
	if type(lootCollector) ~= "table" then
		return 1, 2
	end
	local constants
	if type(lootCollector.GetModule) == "function" then
		local ok, module = pcall(lootCollector.GetModule, lootCollector, "Constants", true)
		if ok then constants = module end
	end
	local discoveryType = constants and constants.DISCOVERY_TYPE or {}
	return tonumber(discoveryType.WORLDFORGED) or 1, tonumber(discoveryType.MYSTIC_SCROLL) or 2
end

local function createAccessorAdapter(lootCollector)
	if type(lootCollector) ~= "table"
		or type(lootCollector.GetDiscoveriesDB) ~= "function"
		or type(lootCollector.GetVendorsDB) ~= "function" then
		return nil
	end

	local discoveriesOk, discoveries = pcall(lootCollector.GetDiscoveriesDB, lootCollector)
	local vendorsOk, vendors = pcall(lootCollector.GetVendorsDB, lootCollector)
	if not discoveriesOk then discoveries = nil end
	if not vendorsOk then vendors = nil end
	if not hasUsableRecords(discoveries, vendors) then return nil end

	return {
		key = "accessors",
		label = "LootCollector accessors",
		lootCollector = lootCollector,
		discoveries = type(discoveries) == "table" and discoveries or {},
		vendors = type(vendors) == "table" and vendors or {},
	}
end

local function createRealmBucketAdapter(lootCollector)
	local dbRoot = rawDBRoot()
	local bucket, realmKey = resolveRealmBucket(dbRoot, lootCollector)
	if type(bucket) ~= "table" then return nil end

	local discoveries = bucket.discoveries
	local vendors = bucket.blackmarketVendors
	if not hasUsableRecords(discoveries, vendors) then return nil end

	return {
		key = "realm_bucket_savedvariables",
		label = "LootCollector realm bucket SavedVariables",
		lootCollector = lootCollector,
		realmKey = realmKey,
		discoveries = type(discoveries) == "table" and discoveries or {},
		vendors = type(vendors) == "table" and vendors or {},
	}
end

local function createLegacySavedVariablesAdapter(lootCollector)
	local dbRoot = rawDBRoot()
	local globalDB = dbRoot and dbRoot.global
	if type(globalDB) ~= "table" then return nil end

	local discoveries = globalDB.discoveries
	local vendors = globalDB.blackmarketVendors
	if not hasUsableRecords(discoveries, vendors) then return nil end

	return {
		key = "legacy_savedvariables",
		label = "LootCollector legacy SavedVariables",
		lootCollector = lootCollector,
		discoveries = type(discoveries) == "table" and discoveries or {},
		vendors = type(vendors) == "table" and vendors or {},
	}
end

local function selectAdapter()
	ensureLootCollectorLoaded()

	local lootCollector = resolveLootCollectorObject()
	local adapter = createAccessorAdapter(lootCollector)
	if adapter then return adapter end

	adapter = createRealmBucketAdapter(lootCollector)
	if adapter then return adapter end

	adapter = createLegacySavedVariablesAdapter(lootCollector)
	if adapter then return adapter end

	return nil
end

function provider.GetAdapterInfo()
	local adapter = selectAdapter()
	if adapter then
		return {
			adapter = adapter.key,
			label = adapter.label,
			realmKey = adapter.realmKey,
			mainInstalled = addonInstalled(LOOTCOLLECTOR_ADDON),
			mainLoaded = addonLoaded(LOOTCOLLECTOR_ADDON),
			starterDBInstalled = addonInstalled(LOOTCOLLECTOR_STARTER_DB_ADDON),
			customImportInstalled = addonInstalled(LOOTCOLLECTOR_CUSTOM_IMPORT_ADDON),
		}
	end

	local starterOnly = addonInstalled(LOOTCOLLECTOR_STARTER_DB_ADDON) or addonInstalled(LOOTCOLLECTOR_CUSTOM_IMPORT_ADDON)
	return {
		adapter = "none",
		mainInstalled = addonInstalled(LOOTCOLLECTOR_ADDON),
		mainLoaded = addonLoaded(LOOTCOLLECTOR_ADDON),
		starterDBInstalled = addonInstalled(LOOTCOLLECTOR_STARTER_DB_ADDON),
		customImportInstalled = addonInstalled(LOOTCOLLECTOR_CUSTOM_IMPORT_ADDON),
		reason = starterOnly and "LootCollector main addon is required; split data addons are import sources only" or "LootCollector data unavailable",
	}
end

function provider.IsAvailable()
	return selectAdapter() ~= nil
end

local function buildWorldforgedTierIDs(itemID, cache)
	local existing = cache[itemID]
	if existing ~= nil then
		return existing
	end

	local tierIDs = {}
	if type(GetItemDifficultyID) == "function" then
		for _, tierDef in ipairs(WORLDFORGED_TIERS) do
			local tierItemID = tonumber(GetItemDifficultyID(itemID, tierDef.difficulty))
			if tierItemID and tierItemID > 0 then
				tierIDs[tierDef.settingKey] = tierItemID
			end
		end
	end

	cache[itemID] = tierIDs
	return tierIDs
end

local function hasSelectedWorldforgedTier(settings)
	for _, tierDef in ipairs(WORLDFORGED_TIERS) do
		if settings[tierDef.settingKey] then
			return true
		end
	end
	return false
end

local function hasAllWorldforgedTiersSelected(settings)
	for _, tierDef in ipairs(WORLDFORGED_TIERS) do
		if not settings[tierDef.settingKey] then
			return false
		end
	end
	return true
end

local function addWorldforgedMappings(state, addMapping, placeName, itemID)
	local settings = state.settings
	local hasTierFilter = hasSelectedWorldforgedTier(settings)

	local tierIDs = buildWorldforgedTierIDs(itemID, state.worldforgedTierCache)
	local added = false
	for _, tierDef in ipairs(WORLDFORGED_TIERS) do
		if settings[tierDef.settingKey] then
			local tierItemID = tierIDs[tierDef.settingKey]
			if tierItemID then
				addMapping(placeName, tierDef.label, tierItemID, {
					difficultyLabel = tierDef.difficultyLabel,
					difficultyRank = tierDef.difficulty,
				})
				added = true
			end
		end
	end

	if not added and (not hasTierFilter or hasAllWorldforgedTiersSelected(settings)) then
		addMapping(placeName, "Worldforged", itemID)
		added = true
	end

	return added
end

function provider.StartCollect(settings)
	local adapter = selectAdapter()
	local lootCollector = adapter and adapter.lootCollector
	local worldforgedType, mysticScrollType = resolveDiscoveryTypes(lootCollector)
	return {
		adapter = adapter,
		lootCollector = lootCollector,
		worldforgedType = worldforgedType,
		mysticScrollType = mysticScrollType,
		discoveries = adapter and adapter.discoveries or {},
		discoveryCursor = nil,
		vendors = adapter and adapter.vendors or {},
		vendorCursor = nil,
		mode = "discoveries",
		settings = {
			worldforgedZG = settings and settings.worldforgedZG ~= false,
			worldforgedMC = settings and settings.worldforgedMC ~= false,
			worldforgedBWL = settings and settings.worldforgedBWL ~= false,
			worldforgedNaxx = settings and settings.worldforgedNaxx ~= false,
		},
		worldforgedTierCache = {},
		currentVendorItems = nil,
		currentVendorPlace = nil,
		currentVendorSource = nil,
		currentVendorIndex = 1,
		done = false,
		stats = {
			adapter = adapter and adapter.key or "none",
			realmKey = adapter and adapter.realmKey or nil,
			discoveries = 0,
			vendorItems = 0,
		},
	}
end

function provider.StepCollect(state, addMapping, maxOps)
	if state.done then return true, 0 end

	local budget = tonumber(maxOps) or 50
	if budget < 1 then budget = 1 end
	local ops = 0

	while ops < budget do
		if state.mode == "discoveries" then
			local key, discovery = next(state.discoveries, state.discoveryCursor)
			if key == nil then
				state.mode = "vendors"
			else
				state.discoveryCursor = key
				ops = ops + 1

				local itemID = tonumber(discovery and discovery.i)
				if itemID and itemID > 0 then
					local placeName = resolveZoneName(state.lootCollector, discovery)
					local dt = tonumber(discovery.dt) or -1

					if dt == state.worldforgedType then
						if addWorldforgedMappings(state, addMapping, placeName, itemID) then
							state.stats.discoveries = state.stats.discoveries + 1
						end
					elseif dt == state.mysticScrollType then
						addMapping(placeName, "Mystic Scroll", itemID)
						state.stats.discoveries = state.stats.discoveries + 1
					else
						addMapping(placeName, "World Drop", itemID)
						state.stats.discoveries = state.stats.discoveries + 1
					end
				end
			end
		else
			if not state.currentVendorItems then
				local key, vendor = next(state.vendors, state.vendorCursor)
				if key == nil then
					state.done = true
					break
				end
				ops = ops + 1
				state.vendorCursor = key
				state.currentVendorItems = (vendor and vendor.vendorItems) or {}
				state.currentVendorPlace = resolveZoneName(state.lootCollector, vendor)
				state.currentVendorSource = clean(vendor and vendor.vendorName) or "Vendor"
				state.currentVendorIndex = 1
			else
				local vendorItem = state.currentVendorItems[state.currentVendorIndex]
				if not vendorItem then
					ops = ops + 1
					state.currentVendorItems = nil
					state.currentVendorPlace = nil
					state.currentVendorSource = nil
				else
					state.currentVendorIndex = state.currentVendorIndex + 1
					ops = ops + 1
					local itemID = tonumber(vendorItem and (vendorItem.itemID or vendorItem.i))
					if itemID and itemID > 0 then
						addMapping(state.currentVendorPlace, state.currentVendorSource, itemID)
						state.stats.vendorItems = state.stats.vendorItems + 1
					end
				end
			end
		end
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
