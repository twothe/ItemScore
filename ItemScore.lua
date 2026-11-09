-- Stores per-character score profiles and evaluates Blizzard item attributes.
local addonName, addon = ...
_G.ItemScore = addon

local ARMOR_PROFILE_WEIGHT_KEY = "ARMOR"
local ARMOR_STAT_KEYS = {
	RESISTANCE0_NAME = true,
	ITEM_MOD_ARMOR_SHORT = true,
}
local ARMOR_TYPE_FILTER_KEYS = {
	cloth = true,
	leather = true,
	mail = true,
	plate = true,
}
local ARMOR_TYPE_FILTER_ORDER = { "cloth", "leather", "mail", "plate" }
local WEAPON_TYPE_FILTER_KEYS = {
	one_hand_axe = true,
	one_hand_mace = true,
	one_hand_sword = true,
	dagger = true,
	fist_weapon = true,
	two_hand_axe = true,
	two_hand_mace = true,
	two_hand_sword = true,
	polearm = true,
	staff = true,
	shield = true,
	off_hand = true,
	bow = true,
	gun = true,
	crossbow = true,
	thrown = true,
	wand = true,
}
local WEAPON_TYPE_FILTER_ORDER = {
	"one_hand_axe", "one_hand_mace", "one_hand_sword", "dagger", "fist_weapon",
	"two_hand_axe", "two_hand_mace", "two_hand_sword", "polearm", "staff",
	"shield", "off_hand",
	"bow", "gun", "crossbow", "thrown", "wand",
}

--------------------------------------------------
-- Data Handling
--------------------------------------------------

local function createProfile()
	return {
		weights = {},
		enabled = true,
		collapsed = false,
		armorTypeFilter = {},
		weaponTypeFilter = {},
	}
end

local function invalidateEquipScores()
	if type(addon.InvalidateEquipScores) == "function" then
		addon.InvalidateEquipScores()
	end
end

local function normalizeArmorTypeFilter(filterTable)
	if type(filterTable) ~= "table" then
		return {}
	end

	local normalized = {}
	for _, armorTypeKey in ipairs(ARMOR_TYPE_FILTER_ORDER) do
		if filterTable[armorTypeKey] then
			normalized[armorTypeKey] = true
		end
	end
	return normalized
end

local function normalizeWeaponTypeFilter(filterTable)
	if type(filterTable) ~= "table" then
		return {}
	end

	local normalized = {}
	for _, weaponTypeKey in ipairs(WEAPON_TYPE_FILTER_ORDER) do
		if filterTable[weaponTypeKey] then
			normalized[weaponTypeKey] = true
		end
	end
	return normalized
end

local function normalizeProfile(profile)
	if type(profile.weights) ~= "table" then
		profile.weights = {}
	end
	if type(profile.enabled) ~= "boolean" then
		profile.enabled = true
	end
	if type(profile.collapsed) ~= "boolean" then
		profile.collapsed = false
	end
	profile.armorTypeFilter = normalizeArmorTypeFilter(profile.armorTypeFilter)
	profile.weaponTypeFilter = normalizeWeaponTypeFilter(profile.weaponTypeFilter)
end

local function ensureData()
	if not ItemScoreData then ItemScoreData = {} end
	ItemScoreData.searchDiagnostics = nil -- Remove temporary pre-release diagnostics.
	if not ItemScoreData.profiles then
		ItemScoreData.profiles = {
			["DPS"] = createProfile()
		}
		ItemScoreData.order = {"DPS"}
		ItemScoreData.activeProfile = "DPS"
	end

	for _, profile in pairs(ItemScoreData.profiles) do
		normalizeProfile(profile)
	end
end

local function getData()
	ensureData()
	return ItemScoreData
end

local function getProfile(name)
	ensureData()
	if not ItemScoreData.profiles[name] then
		ItemScoreData.profiles[name] = createProfile()
		table.insert(ItemScoreData.order, name)
	end
	normalizeProfile(ItemScoreData.profiles[name])
	return ItemScoreData.profiles[name]
end

function addon.GetProfiles() return getData().order end

function addon.GetProfileData(name) return getProfile(name) end

function addon.AddProfile(name)
	if type(name) ~= "string" then return false end
	local data = getData()
	if name == "" or data.profiles[name] then return false end
	data.profiles[name] = createProfile()
	table.insert(data.order, name)
	invalidateEquipScores()
	return true
end

function addon.DeleteProfile(name)
	if type(name) ~= "string" then return false end
	local data = getData()
	if not data.profiles[name] then return false end
	data.profiles[name] = nil
	for i, n in ipairs(data.order) do
		if n == name then
			table.remove(data.order, i)
			break
		end
	end
	if #data.order == 0 then addon.AddProfile("DPS") end
	if data.activeProfile == name then data.activeProfile = data.order[1] end
	invalidateEquipScores()
	return true
end

function addon.MoveProfile(name, direction)
	if type(name) ~= "string" then return end
	local order = getData().order
	for i, n in ipairs(order) do
		if n == name then
			local target = i + direction
			if target < 1 or target > #order then return end
			order[i], order[target] = order[target], order[i]
			return
		end
	end
end

function addon.SetActiveProfile(name)
	if type(name) ~= "string" then return end
	local data = getData()
	if data.profiles[name] then
		data.activeProfile = name
	end
end

function addon.ToggleProfileEnabled(name)
	local profile = getProfile(name)
	profile.enabled = not profile.enabled
end

function addon.ToggleProfileCollapsed(name)
	local profile = getProfile(name)
	profile.collapsed = not profile.collapsed
end

function addon.SetWeight(profileName, statKey, value)
	if type(profileName) ~= "string" or type(statKey) ~= "string" then return end
	local profile = getProfile(profileName)
	local oldValue = profile.weights[statKey]
	if value == nil or value == "" then
		profile.weights[statKey] = nil
	else
		profile.weights[statKey] = value
	end
	if oldValue ~= profile.weights[statKey] then
		invalidateEquipScores()
	end
end

function addon.GetProfileArmorTypeFilterState(profileName)
	local profile = getProfile(profileName)
	local filter = profile.armorTypeFilter or {}
	local selected = {}
	local hasFilter = false
	for _, armorTypeKey in ipairs(ARMOR_TYPE_FILTER_ORDER) do
		if filter[armorTypeKey] then
			selected[armorTypeKey] = true
			hasFilter = true
		end
	end
	return hasFilter, selected
end

function addon.SetProfileArmorTypeEnabled(profileName, armorTypeKey, enabled)
	if not ARMOR_TYPE_FILTER_KEYS[armorTypeKey] then
		return false
	end

	local profile = getProfile(profileName)
	local filter = profile.armorTypeFilter
	local oldValue = filter[armorTypeKey] and true or false
	local newValue = enabled and true or false
	if oldValue == newValue then
		return false
	end

	if newValue then
		filter[armorTypeKey] = true
	else
		filter[armorTypeKey] = nil
	end
	return true
end

function addon.GetProfileWeaponTypeFilterState(profileName)
	local profile = getProfile(profileName)
	local filter = profile.weaponTypeFilter or {}
	local selected = {}
	local hasFilter = false
	for _, weaponTypeKey in ipairs(WEAPON_TYPE_FILTER_ORDER) do
		if filter[weaponTypeKey] then
			selected[weaponTypeKey] = true
			hasFilter = true
		end
	end
	return hasFilter, selected
end

function addon.SetProfileWeaponTypeEnabled(profileName, weaponTypeKey, enabled)
	if not WEAPON_TYPE_FILTER_KEYS[weaponTypeKey] then
		return false
	end

	local profile = getProfile(profileName)
	local filter = profile.weaponTypeFilter
	local oldValue = filter[weaponTypeKey] and true or false
	local newValue = enabled and true or false
	if oldValue == newValue then
		return false
	end

	if newValue then
		filter[weaponTypeKey] = true
	else
		filter[weaponTypeKey] = nil
	end
	return true
end

--------------------------------------------------
-- Scoring
--------------------------------------------------

local function normalizeScore(score, itemLink)
	local invType = addon.GetInventoryType(itemLink)
	if invType == "INVTYPE_2HWEAPON" then
		return score / 2
	else
		return score
	end
end

local function profileWeightForStat(profile, statKey)
	if ARMOR_STAT_KEYS[statKey] then
		local armorWeight = profile.weights[ARMOR_PROFILE_WEIGHT_KEY]
		if armorWeight ~= nil then
			return armorWeight
		end
	end
	return profile.weights[statKey] or 0
end

local function calculateItemScoreForProfile(itemLink, profile)
	local itemStats = addon.Query.GetItemStats(itemLink)
	if not itemStats or not addon.Query.GetItemInfo(itemLink) then
		addon.Query.Add(itemLink)
		return 0
	end
	-- Classic items can expose spell damage separately from healing and spell power.
	local score = 0
	local spellDamageKey = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"
	local spellPowerKey = "ITEM_MOD_SPELL_POWER_SHORT"
	for statKey, statValue in pairs(itemStats) do
		local weight = profileWeightForStat(profile, statKey)
		if statKey == spellDamageKey and itemStats[spellPowerKey] == nil and profile.weights[spellDamageKey] == nil then
			weight = profileWeightForStat(profile, spellPowerKey)
		end
		score = score + statValue * weight
	end
	return normalizeScore(score, itemLink)
end

local function addScoreToTooltip(tooltip, tooltipData)
	local itemLink
	if type(tooltip.GetItem) == "function" then
		local name
		name, itemLink = tooltip:GetItem()
	end
	if issecretvalue(itemLink) then return end
	if not itemLink and tooltipData and not issecretvalue(tooltipData.id) and tooltipData.id then
		itemLink = select(2, addon.Query.GetItemInfo(tooltipData.id)) or ("item:" .. tooltipData.id)
	end
	if not itemLink then return end
	local data = getData()
	for _, name in ipairs(data.order) do
		if data.profiles[name].enabled then
			local score = addon.CalculateScore(itemLink, name)
			tooltip:AddLine(string.format("%s: %.1f", name, score), 0.1, 1, 0.1)
		end
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, tooltipData)
	if tooltip == GameTooltip or tooltip == ItemRefTooltip or tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2 then
		addScoreToTooltip(tooltip, tooltipData)
	end
end)

--------------------------------------------------
-- Public scoring API (for Search UI)
--------------------------------------------------

function addon.CalculateScore(itemLink, profileName)
	local data = getData()
	if (profileName) then
		local profile = data.profiles[profileName]
		if (profile and profile.enabled) then
			return calculateItemScoreForProfile(itemLink, profile)
		else
			return 0
		end
	else
		local bestScore = 0
		for _, name in ipairs(data.order) do
			local score = addon.CalculateScore(itemLink, name)
			if (score > bestScore) then bestScore = score end
		end
		return bestScore
	end
end
