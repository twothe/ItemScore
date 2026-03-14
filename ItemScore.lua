local addonName, addon = ...
_G.ItemScore = addon

--------------------------------------------------
-- Data Handling
--------------------------------------------------

local function ensureData()
	if not ItemScoreData then ItemScoreData = {} end
	if not ItemScoreData.profiles then
		ItemScoreData.profiles = {
			["DPS"] = {
				weights = {},
				enabled = true,
				collapsed = false
			}
		}
		ItemScoreData.order = {"DPS"}
		ItemScoreData.activeProfile = "DPS"
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
			collapsed = false
		}
		table.insert(ItemScoreData.order, name)
	end
	return ItemScoreData.profiles[name]
end

function addon.GetProfiles() return getData().order end

function addon.GetProfileData(name) return getProfile(name) end

function addon.AddProfile(name)
	if name == "" or ItemScoreData.profiles[name] then return false end
	ItemScoreData.profiles[name] = {
		weights = {},
		enabled = true,
		collapsed = false
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

local function calculateItemScoreForProfile(itemLink, profile)
	local itemStats = GetItemStats(itemLink)
	if not itemStats then return 0 end
	local score = 0
	for statKey, statValue in pairs(itemStats) do
		local weight = profile.weights[statKey] or 0
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
