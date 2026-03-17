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
	if not ItemScoreData.profiles then
		ItemScoreData.profiles = {
			["DPS"] = {
				weights = {},
				enabled = true,
				collapsed = false,
				armorTypeFilter = {},
				weaponTypeFilter = {},
			}
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
		ItemScoreData.profiles[name] = {
			weights = {},
			enabled = true,
			collapsed = false,
			armorTypeFilter = {},
			weaponTypeFilter = {},
		}
		table.insert(ItemScoreData.order, name)
	end
	normalizeProfile(ItemScoreData.profiles[name])
	return ItemScoreData.profiles[name]
end

function addon.GetProfiles() return getData().order end

function addon.GetProfileData(name) return getProfile(name) end

function addon.AddProfile(name)
	if name == "" or ItemScoreData.profiles[name] then return false end
	ItemScoreData.profiles[name] = {
		weights = {},
		enabled = true,
		collapsed = false,
		armorTypeFilter = {},
		weaponTypeFilter = {},
	}
	table.insert(ItemScoreData.order, name)
	return true
end

function addon.DeleteProfile(name)
	ItemScoreData.profiles[name] = nil
	for i, n in ipairs(ItemScoreData.order) do
		if n == name then
			table.remove(ItemScoreData.order, i)
			break
		end
	end
	if #ItemScoreData.order == 0 then addon.AddProfile("DPS") end
	if ItemScoreData.activeProfile == name then ItemScoreData.activeProfile = ItemScoreData.order[1] end
	return true
end

function addon.MoveProfile(name, direction)
	local order = ItemScoreData.order
	for i, n in ipairs(order) do
		if n == name then
			local target = i + direction
			if target < 1 or target > #order then return end
			order[i], order[target] = order[target], order[i]
			return
		end
	end
end

function addon.SetActiveProfile(name) ItemScoreData.activeProfile = name end

function addon.ToggleProfileEnabled(name)
	local profile = getProfile(name)
	profile.enabled = not profile.enabled
end

function addon.ToggleProfileCollapsed(name)
	local profile = getProfile(name)
	profile.collapsed = not profile.collapsed
end

function addon.SetWeight(profileName, statKey, value)
	local profile = getProfile(profileName)
	if value == nil or value == "" then
		profile.weights[statKey] = nil
	else
		profile.weights[statKey] = value
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
	local invType = inventoryType(itemLink)
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
	local itemStats = GetItemStats(itemLink)
	if not itemStats then return 0 end
	local score = 0
	for statKey, statValue in pairs(itemStats) do
		local weight = profileWeightForStat(profile, statKey)
		score = score + statValue * weight
	end
	return normalizeScore(score, itemLink)
end

local function addScoreToTooltip(tooltip)
	local _, itemLink = tooltip:GetItem()
	if not itemLink then return end
	local data = getData()
	for _, name in ipairs(data.order) do
		local score = addon.CalculateScore(itemLink, name)
		if score and score > 0 then tooltip:AddLine(string.format("%s: %.1f", name or "IS", score or 0), 0.1, 1, 0.1) end
	end
end

GameTooltip:HookScript("OnTooltipSetItem", addScoreToTooltip)
ItemRefTooltip:HookScript("OnTooltipSetItem", addScoreToTooltip)
ShoppingTooltip1:HookScript("OnTooltipSetItem", addScoreToTooltip)
ShoppingTooltip2:HookScript("OnTooltipSetItem", addScoreToTooltip)

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
