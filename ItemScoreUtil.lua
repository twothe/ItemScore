local addonName, addon = ...

-- Shared helpers for ItemScore UI construction, item classification, and debug-safe formatting.

local counter = 0
local function unique(prefix)
	counter = counter + 1
	return prefix .. counter
end

function addon.CreateButton(parent, width, height, text, template)
	assert(parent, "parent nil")
	local btn = CreateFrame("Button", unique("ISBtn"), parent, template or "UIPanelButtonTemplate")
	if width and height then btn:SetSize(width, height) end
	if text then btn:SetText(text) end
	return btn
end

function addon.CreateCheckButton(parent, label)
	assert(parent, "parent nil")
	local cb = CreateFrame("CheckButton", unique("ISChk"), parent, "UICheckButtonTemplate")
	local textRegion = _G[cb:GetName() .. "Text"]
	textRegion:SetText(label)
	cb.text = textRegion
	return cb
end

function addon.CreateEditBox(parent, width)
	assert(parent, "parent nil")
	local eb = CreateFrame("EditBox", unique("ISEB"), parent, "InputBoxTemplate")
	eb:SetAutoFocus(false)
	eb:SetSize(width or 80, 20)
	eb:SetFontObject("ChatFontNormal")
	eb:SetScript("OnEnterPressed", eb.ClearFocus)
	eb:SetScript("OnEscapePressed", eb.ClearFocus)
	return eb
end

local ARMOR_TYPE_DEFS = {
	{ key = "cloth", classID = 4, subclassID = 1, fallback = "Cloth" },
	{ key = "leather", classID = 4, subclassID = 2, fallback = "Leather" },
	{ key = "mail", classID = 4, subclassID = 3, fallback = "Mail" },
	{ key = "plate", classID = 4, subclassID = 4, fallback = "Plate" },
}

local function toLookupKey(value)
	local text = strtrim(tostring(value or ""))
	if text == "" then return nil end
	return string.lower(text)
end

-- Client-provided subclass names keep filters valid in every locale.
local function itemTypeLabel(def)
	if def.classID then return C_Item.GetItemSubClassInfo(def.classID, def.subclassID) or def.fallback end
	return _G[def.labelGlobal] or def.fallback
end

local ARMOR_TYPE_LOOKUP = {}
for _, def in ipairs(ARMOR_TYPE_DEFS) do
	ARMOR_TYPE_LOOKUP[def.key] = def.key
	ARMOR_TYPE_LOOKUP[toLookupKey(def.fallback)] = def.key
	local localizedKey = toLookupKey(itemTypeLabel(def))
	if localizedKey then ARMOR_TYPE_LOOKUP[localizedKey] = def.key end
end

function addon.GetArmorTypeOptions()
	local result = {}
	for _, def in ipairs(ARMOR_TYPE_DEFS) do
		local label = itemTypeLabel(def)
		result[#result + 1] = {
			key = def.key,
			label = label,
		}
	end
	return result
end

function addon.NormalizeArmorType(itemType, subType)
	return ARMOR_TYPE_LOOKUP[toLookupKey(subType)]
end

local WEAPON_TYPE_DEFS = {
	{ key = "one_hand_axe", classID = 2, subclassID = 0, fallback = "One-Handed Axes" },
	{ key = "one_hand_mace", classID = 2, subclassID = 4, fallback = "One-Handed Maces" },
	{ key = "one_hand_sword", classID = 2, subclassID = 7, fallback = "One-Handed Swords" },
	{ key = "dagger", classID = 2, subclassID = 15, fallback = "Daggers" },
	{ key = "fist_weapon", classID = 2, subclassID = 13, fallback = "Fist Weapons" },
	{ key = "two_hand_axe", classID = 2, subclassID = 1, fallback = "Two-Handed Axes" },
	{ key = "two_hand_mace", classID = 2, subclassID = 5, fallback = "Two-Handed Maces" },
	{ key = "two_hand_sword", classID = 2, subclassID = 8, fallback = "Two-Handed Swords" },
	{ key = "polearm", classID = 2, subclassID = 6, fallback = "Polearms" },
	{ key = "staff", classID = 2, subclassID = 10, fallback = "Staves" },
	{ key = "shield", classID = 4, subclassID = 6, fallback = "Shields", invType = "INVTYPE_SHIELD" },
	{ key = "off_hand", labelGlobal = "INVTYPE_HOLDABLE", fallback = "Held In Off-Hand", invType = "INVTYPE_HOLDABLE" },
	{ key = "bow", classID = 2, subclassID = 2, fallback = "Bows" },
	{ key = "gun", classID = 2, subclassID = 3, fallback = "Guns" },
	{ key = "crossbow", classID = 2, subclassID = 18, fallback = "Crossbows" },
	{ key = "thrown", classID = 2, subclassID = 16, fallback = "Thrown" },
	{ key = "wand", classID = 2, subclassID = 19, fallback = "Wands" },
}

local WEAPON_SUBTYPE_LOOKUP = {}
local WEAPON_INVTYPE_LOOKUP = {}
for _, def in ipairs(WEAPON_TYPE_DEFS) do
	local localized = itemTypeLabel(def)
	local localizedKey = toLookupKey(localized)
	if localizedKey then
		WEAPON_SUBTYPE_LOOKUP[localizedKey] = def.key
	end
	local fallbackKey = toLookupKey(def.fallback)
	if fallbackKey then
		WEAPON_SUBTYPE_LOOKUP[fallbackKey] = def.key
	end
	if def.invType then
		WEAPON_INVTYPE_LOOKUP[def.invType] = def.key
	end
end

function addon.GetWeaponTypeOptions()
	local result = {}
	for _, def in ipairs(WEAPON_TYPE_DEFS) do
		local label = itemTypeLabel(def)
		result[#result + 1] = {
			key = def.key,
			label = label,
		}
	end
	return result
end

function addon.IsWeaponTypeFilterRelevant(itemType, invType)
	if invType == "INVTYPE_SHIELD" or invType == "INVTYPE_HOLDABLE" then
		return true
	end
	local itemTypeKey = toLookupKey(itemType)
	local weaponClassKey = toLookupKey(C_Item.GetItemClassInfo(2))
	return itemTypeKey == "weapon" or (weaponClassKey and itemTypeKey == weaponClassKey)
end

function addon.NormalizeWeaponType(itemType, subType, invType)
	local keyByInvType = WEAPON_INVTYPE_LOOKUP[invType]
	if keyByInvType then
		return keyByInvType
	end
	local normalizedSubType = toLookupKey(subType)
	if not normalizedSubType then return nil end
	return WEAPON_SUBTYPE_LOOKUP[normalizedSubType]
end

function addon.TuneAdaptiveBudget(currentBudget, elapsedMs, targetMs, minBudget, maxBudget)
	local budget = tonumber(currentBudget) or minBudget or 200
	local minValue = tonumber(minBudget) or 20
	local maxValue = tonumber(maxBudget) or 10000
	if budget < minValue then budget = minValue end
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
	if budget < minValue then budget = minValue end
	if budget > maxValue then budget = maxValue end
	return budget
end

local armorAllowed = {
	WARRIOR = {
		cloth = true,
		leather = true,
		mail = true,
		plate = true,
		shield = true
	},
	PALADIN = {
		cloth = true,
		leather = true,
		mail = true,
		plate = true,
		shield = true
	},
	DEATHKNIGHT = {
		cloth = true,
		leather = true,
		mail = true,
		plate = true
	},
	HUNTER = {
		cloth = true,
		leather = true,
		mail = true
	},
	SHAMAN = {
		cloth = true,
		leather = true,
		mail = true,
		shield = true
	},
	ROGUE = {
		cloth = true,
		leather = true
	},
	DRUID = {
		cloth = true,
		leather = true
	},
	PRIEST = {
		cloth = true
	},
	MAGE = {
		cloth = true
	},
	WARLOCK = {
		cloth = true
	}
}

local classCheckTip = CreateFrame("GameTooltip", "IS_ClassCheckTip", nil, "GameTooltipTemplate")
classCheckTip:SetOwner(UIParent, "ANCHOR_NONE")

local function classListContains(classListText, localizedClassName)
	if type(classListText) ~= "string" or type(localizedClassName) ~= "string" then
		return false
	end
	local wanted = string.lower(localizedClassName)
	for token in string.gmatch(classListText, "([^,]+)") do
		local normalized = string.lower(strtrim(token))
		if normalized == wanted then
			return true
		end
	end
	return false
end

local function normalizedEquipArmorKey(itemType, subType, equipLoc)
	if equipLoc == "INVTYPE_SHIELD" then return "shield" end
	return addon.NormalizeArmorType(itemType, subType)
end

-- Checks native armor eligibility and the localized class restriction tooltip line.
function addon.CanPlayerEquip(itemLink)
	local name, _, _, _, reqLevel, itemType, subType, _, equipLoc = addon.Query.GetItemInfo(itemLink)
	if not name or equipLoc == "" then return false end

	local pLoc, pKey = UnitClass("player")
	classCheckTip:ClearLines()
	classCheckTip:SetHyperlink(itemLink)
	local label = ITEM_CLASSES_ALLOWED:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
	for i = 2, classCheckTip:NumLines() do
		local line = _G["IS_ClassCheckTipTextLeft" .. i]
		local text = line and line:GetText()
		local list = text and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^" .. label .. "$")
		if list and not classListContains(list, pLoc) then return false end
	end

	local armorKey = normalizedEquipArmorKey(itemType, subType, equipLoc)
	if armorKey or equipLoc == "INVTYPE_SHIELD" then
		if equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_NECK" or equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" then return true end
		local allowed = armorAllowed[pKey]
		if not allowed then return true end
		if armorKey and not allowed[armorKey] then return false end
	end
	return true
end

function addon.GetInventoryType(itemLink)
	local _, _, _, _, _, _, _, _, invType = addon.Query.GetItemInfo(itemLink)
	if (invType == nil or strtrim(invType) == "") then
		return nil
	else
		return invType
	end
end

function addon.TableToString(tbl, indent, visited)
	indent = indent or 0
	visited = visited or {}

	if visited[tbl] then return string.rep("  ", indent) .. "*RECURSION*\n" end
	visited[tbl] = true

	local lines = {}
	table.insert(lines, string.rep("  ", indent) .. "{")

	for k, v in pairs(tbl) do
		local keyStr = tostring(k)
		local valueStr
		local valueType = type(v)

		if valueType == "table" then
			valueStr = addon.TableToString(v, indent + 1, visited)
		elseif valueType == "string" then
			valueStr = "\"" .. v .. "\""
		else
			valueStr = tostring(v)
		end

		table.insert(lines, string.rep("  ", indent + 1) .. "[" .. keyStr .. "] = " .. valueStr .. ",")
	end

	table.insert(lines, string.rep("  ", indent) .. "}")
	return table.concat(lines, "\n")
end
