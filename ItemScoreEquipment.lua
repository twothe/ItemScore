local addonName, addon = ...

local DEFAULT_PROFILE_KEY = "DPS"

--
-- Cached equipment scores per profile.
-- Structure: equipCache[profileKey] = {
--   [slotId] = score
-- }
--
local equipCache = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local SLOTNAME_TO_ID = setmetatable({}, {
	__index = function(table, key) return select(1, GetInventorySlotInfo(key)) end
})

local function wipe() equipCache = {} end

------------------------------------------------------------
-- Slot mapping (non-weapon)
------------------------------------------------------------
local INVTYPE_TO_SLOTS = {
	INVTYPE_HEAD = {"HeadSlot"},
	INVTYPE_NECK = {"NeckSlot"},
	INVTYPE_SHOULDER = {"ShoulderSlot"},
	INVTYPE_CLOAK = {"BackSlot"},
	INVTYPE_CHEST = {"ChestSlot"},
	INVTYPE_ROBE = {"ChestSlot"},
	INVTYPE_WRIST = {"WristSlot"},
	INVTYPE_HAND = {"HandsSlot"},
	INVTYPE_WAIST = {"WaistSlot"},
	INVTYPE_LEGS = {"LegsSlot"},
	INVTYPE_FEET = {"FeetSlot"},
	INVTYPE_FINGER = {"Finger0Slot", "Finger1Slot"},
	INVTYPE_TRINKET = {"Trinket0Slot", "Trinket1Slot"},
	INVTYPE_SHIELD = {"SecondaryHandSlot"},
	INVTYPE_HOLDABLE = {"SecondaryHandSlot"},
	INVTYPE_WEAPON = {"MainHandSlot", "SecondaryHandSlot"},
	INVTYPE_2HWEAPON = {"MainHandSlot"},
	INVTYPE_RANGED = {"RangedSlot"},
	INVTYPE_RANGEDRIGHT = {"RangedSlot"}
}

------------------------------------------------------------
-- Cache builder
------------------------------------------------------------
local function computeProfileRecord(profileKey)
	local scores = {}

	for slotId = 1, 19 do
		local link = GetInventoryItemLink("player", slotId)
		scores[slotId] = (link and addon.CalculateScore(link, profileKey)) or 0
	end

	local mainScore = scores[SLOTNAME_TO_ID["MainHandSlot"]] or 0
	local offScore = scores[SLOTNAME_TO_ID["SecondaryHandSlot"]] or mainScore or 0

	scores[SLOTNAME_TO_ID["SecondaryHandSlot"]] = offScore

	return scores
end

local function getProfileRecord(profileName)
	local key = profileName or DEFAULT_PROFILE_KEY
	local rec = equipCache[key]
	if not rec then
		rec = computeProfileRecord(key)
		equipCache[key] = rec
	end
	return rec
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function addon.GetEquipScores(profileName) return getProfileRecord(profileName) end

function addon.IsUpgrade(itemLink, profileName) return addon.CompareDelta(itemLink, profileName) > 0 end

function addon.CompareDelta(itemLink, profileName)
	local invType = inventoryType(itemLink)
	if (not invType) then return -999999 end
	local slotNames = INVTYPE_TO_SLOTS[invType]
	if (not slotNames) then return -999999 end

	if (not profileName) then
		local profiles = addon.GetProfiles()
		local best = 0
		for _, profile in pairs(profiles) do
			local delta = addon.CompareDelta(itemLink, profile)
			if (delta > best) then best = delta end
		end
		return best
	else
		local cand = addon.CalculateScore(itemLink, profileName)
		local rec = getProfileRecord(profileName)
		assert(rec, "profile for " .. profileName .. " not found")
		assert(#rec ~= 20, "profile for " .. profileName .. " has invalid content, expected 20 entries but got " .. #rec .. ": " .. tableToString(rec))
		assert(slotNames, "slotNames for " .. invType .. " not found")
		local worst = 99999999
		for _, slotName in ipairs(slotNames) do
			local slotId = SLOTNAME_TO_ID[slotName]
			assert(slotId > 0 and slotId <= 19, "slotId for " .. slotName .. " of profile " .. profileName .. " out of range: " .. slotId)
			local scoreInSlot = rec[slotId]
			assert(scoreInSlot ~= nil, "scoreInSlot for " .. slotName .. " (ID: " .. slotId .. ") of profile " .. profileName .. " not found. Scores: " .. tableToString(rec))
			if not (invType == "INVTYPE_WEAPON" and slotName == "SecondaryHandSlot" and scoreInSlot == 0 and rec[SLOTNAME_TO_ID["MainHandSlot"]] > 0) then if scoreInSlot < worst then worst = scoreInSlot end end
		end
		return cand - worst
	end
end

------------------------------------------------------------
-- Invalidate cache on gear changes
------------------------------------------------------------
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
evFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
evFrame:SetScript("OnEvent", function() wipe(equipCache) end)
