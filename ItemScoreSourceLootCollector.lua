local addonName, addon = ...

local provider = {
	key = "LootCollector",
}

local WORLDFORGED_TIERS = {
	{ settingKey = "worldforgedMC", difficulty = 6, label = "Worldforged MC" },
	{ settingKey = "worldforgedBWL", difficulty = 7, label = "Worldforged BWL" },
	{ settingKey = "worldforgedNaxx", difficulty = 9, label = "Worldforged Naxxramas" },
}

local function clean(text)
	if type(text) ~= "string" then return nil end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then return nil end
	return text
end

local function resolveZoneName(lootCollector, record)
	local c = tonumber(record and record.c) or 0
	local z = tonumber(record and record.z) or 0
	local iz = tonumber(record and record.iz) or 0

	if type(lootCollector.ResolveZoneDisplay) == "function" then
		local zoneName = lootCollector.ResolveZoneDisplay(c, z, iz)
		zoneName = clean(zoneName)
		if zoneName then return zoneName end
	end

	if type(lootCollector.GetModule) == "function" then
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

function provider.IsAvailable()
	local lootCollector = _G.LootCollector
	return type(lootCollector) == "table"
		and type(lootCollector.GetDiscoveriesDB) == "function"
		and type(lootCollector.GetVendorsDB) == "function"
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

local function addWorldforgedMappings(state, addMapping, placeName, itemID)
	local settings = state.settings
	if not (settings.worldforgedMC or settings.worldforgedBWL or settings.worldforgedNaxx) then
		return false
	end

	local tierIDs = buildWorldforgedTierIDs(itemID, state.worldforgedTierCache)
	local added = false
	for _, tierDef in ipairs(WORLDFORGED_TIERS) do
		if settings[tierDef.settingKey] then
			local tierItemID = tierIDs[tierDef.settingKey]
			if tierItemID then
				addMapping(placeName, tierDef.label, tierItemID)
				added = true
			end
		end
	end

	if not added and settings.worldforgedMC and settings.worldforgedBWL and settings.worldforgedNaxx then
		addMapping(placeName, "Worldforged", itemID)
		added = true
	end

	return added
end

function provider.StartCollect(settings)
	local lootCollector = _G.LootCollector
	local worldforgedType, mysticScrollType = resolveDiscoveryTypes(lootCollector)
	return {
		lootCollector = lootCollector,
		worldforgedType = worldforgedType,
		mysticScrollType = mysticScrollType,
		discoveries = lootCollector and (lootCollector:GetDiscoveriesDB() or {}) or {},
		discoveryCursor = nil,
		vendors = lootCollector and (lootCollector:GetVendorsDB() or {}) or {},
		vendorCursor = nil,
		mode = "discoveries",
		settings = {
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
