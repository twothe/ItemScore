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
	{ key = "cloth", labelGlobal = "ITEM_SUBCLASS_ARMOR_CLOTH", fallback = "Cloth" },
	{ key = "leather", labelGlobal = "ITEM_SUBCLASS_ARMOR_LEATHER", fallback = "Leather" },
	{ key = "mail", labelGlobal = "ITEM_SUBCLASS_ARMOR_MAIL", fallback = "Mail" },
	{ key = "plate", labelGlobal = "ITEM_SUBCLASS_ARMOR_PLATE", fallback = "Plate" },
}

local ARMOR_TYPE_LOOKUP = {}
for _, def in ipairs(ARMOR_TYPE_DEFS) do
	ARMOR_TYPE_LOOKUP[def.key] = def.key
	ARMOR_TYPE_LOOKUP[string.lower(def.fallback)] = def.key
	local localized = _G[def.labelGlobal]
	if type(localized) == "string" and localized ~= "" then
		ARMOR_TYPE_LOOKUP[string.lower(localized)] = def.key
	end
end

function addon.GetArmorTypeOptions()
	local result = {}
	for _, def in ipairs(ARMOR_TYPE_DEFS) do
		local label = _G[def.labelGlobal] or def.fallback
		result[#result + 1] = {
			key = def.key,
			label = label,
		}
	end
	return result
end

function addon.NormalizeArmorType(itemType, subType)
	if itemType ~= "Armor" then return nil end
	local normalized = string.lower(strtrim(tostring(subType or "")))
	if normalized == "" then return nil end
	return ARMOR_TYPE_LOOKUP[normalized]
end

local WEAPON_TYPE_DEFS = {
	{ key = "one_hand_axe", labelGlobal = "ITEM_SUBCLASS_WEAPON_AXE", fallback = "One-Handed Axes" },
	{ key = "one_hand_mace", labelGlobal = "ITEM_SUBCLASS_WEAPON_MACE", fallback = "One-Handed Maces" },
	{ key = "one_hand_sword", labelGlobal = "ITEM_SUBCLASS_WEAPON_SWORD", fallback = "One-Handed Swords" },
	{ key = "dagger", labelGlobal = "ITEM_SUBCLASS_WEAPON_DAGGER", fallback = "Daggers" },
	{ key = "fist_weapon", labelGlobal = "ITEM_SUBCLASS_WEAPON_FIST", fallback = "Fist Weapons" },
	{ key = "two_hand_axe", labelGlobal = "ITEM_SUBCLASS_WEAPON_AXE2", fallback = "Two-Handed Axes" },
	{ key = "two_hand_mace", labelGlobal = "ITEM_SUBCLASS_WEAPON_MACE2", fallback = "Two-Handed Maces" },
	{ key = "two_hand_sword", labelGlobal = "ITEM_SUBCLASS_WEAPON_SWORD2", fallback = "Two-Handed Swords" },
	{ key = "polearm", labelGlobal = "ITEM_SUBCLASS_WEAPON_POLEARM", fallback = "Polearms" },
	{ key = "staff", labelGlobal = "ITEM_SUBCLASS_WEAPON_STAFF", fallback = "Staves" },
	{ key = "shield", labelGlobal = "ITEM_SUBCLASS_ARMOR_SHIELD", fallback = "Shields", invType = "INVTYPE_SHIELD" },
	{ key = "off_hand", labelGlobal = "INVTYPE_HOLDABLE", fallback = "Held In Off-Hand", invType = "INVTYPE_HOLDABLE" },
	{ key = "bow", labelGlobal = "ITEM_SUBCLASS_WEAPON_BOW", fallback = "Bows" },
	{ key = "gun", labelGlobal = "ITEM_SUBCLASS_WEAPON_GUN", fallback = "Guns" },
	{ key = "crossbow", labelGlobal = "ITEM_SUBCLASS_WEAPON_CROSSBOW", fallback = "Crossbows" },
	{ key = "thrown", labelGlobal = "ITEM_SUBCLASS_WEAPON_THROWN", fallback = "Thrown" },
	{ key = "wand", labelGlobal = "ITEM_SUBCLASS_WEAPON_WAND", fallback = "Wands" },
}

local function toLookupKey(value)
	local text = strtrim(tostring(value or ""))
	if text == "" then return nil end
	return string.lower(text)
end

local WEAPON_SUBTYPE_LOOKUP = {}
local WEAPON_INVTYPE_LOOKUP = {}
for _, def in ipairs(WEAPON_TYPE_DEFS) do
	local localized = _G[def.labelGlobal]
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
		local label = _G[def.labelGlobal] or def.fallback
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
	return itemType == "Weapon"
end

function addon.NormalizeWeaponType(itemType, subType, invType)
	local keyByInvType = WEAPON_INVTYPE_LOOKUP[invType]
	if keyByInvType then
		return keyByInvType
	end
	if itemType ~= "Weapon" then return nil end
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
		Cloth = true,
		Leather = true,
		Mail = true,
		Plate = true,
		Shields = true
	},
	PALADIN = {
		Cloth = true,
		Leather = true,
		Mail = true,
		Plate = true,
		Shields = true
	},
	DEATHKNIGHT = {
		Cloth = true,
		Leather = true,
		Mail = true,
		Plate = true
	},
	HUNTER = {
		Cloth = true,
		Leather = true,
		Mail = true
	},
	SHAMAN = {
		Cloth = true,
		Leather = true,
		Mail = true,
		Shields = true
	},
	ROGUE = {
		Cloth = true,
		Leather = true
	},
	DRUID = {
		Cloth = true,
		Leather = true
	},
	PRIEST = {
		Cloth = true
	},
	MAGE = {
		Cloth = true
	},
	WARLOCK = {
		Cloth = true
	}
}

local classCheckTip = CreateFrame("GameTooltip", "IS_ClassCheckTip", nil, "GameTooltipTemplate")
classCheckTip:SetOwner(UIParent, "ANCHOR_NONE")

local difficultyTip = CreateFrame("GameTooltip", "IS_DifficultyTip", nil, "GameTooltipTemplate")
difficultyTip:SetOwner(UIParent, "ANCHOR_NONE")

local function escapeLuaPattern(text)
	return (tostring(text or ""):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function cleanTooltipText(text)
	text = tostring(text or "")
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "%s+", " ")
	if text == "" then return nil end
	return text
end

local function tooltipLineText(tooltip, lineIndex)
	local tooltipName = tooltip and tooltip.GetName and tooltip:GetName()
	if not tooltipName then return nil end
	local line = _G[tooltipName .. "TextLeft" .. tostring(lineIndex)]
	if not line or type(line.GetText) ~= "function" then return nil end
	return cleanTooltipText(line:GetText())
end

local function parseMythicPlusLevel(text)
	local patterns = {
		"[Mm]ythic%s*%+%s*(%d+)",
		"[Mm]ythic%s+[Ll]evel%s+(%d+)",
		"[Mm]ythic%s+(%d+)",
		"[Mm]%s*%+%s*(%d+)",
	}
	for _, pattern in ipairs(patterns) do
		local level = tonumber(string.match(text, pattern))
		if level and level > 0 then
			return math.floor(level)
		end
	end
	return nil
end

local function parseDifficultyText(text)
	text = cleanTooltipText(text)
	if not text then return nil end

	local mythicPlusLevel = parseMythicPlusLevel(text)
	if mythicPlusLevel then
		return {
			difficultyLabel = "M+" .. tostring(mythicPlusLevel),
			difficultyRank = 5 + mythicPlusLevel,
		}
	end

	local normalized = string.lower(text)
	normalized = string.gsub(normalized, "^difficulty:%s*", "")
	normalized = string.gsub(normalized, "^mode:%s*", "")
	normalized = string.gsub(normalized, "%s+mode$", "")
	normalized = strtrim(normalized)

	if normalized == "ascended" then
		return { difficultyLabel = "Asc", difficultyRank = 6 }
	end
	if normalized == "mythic" then
		return { difficultyLabel = "M", difficultyRank = 5 }
	end
	if normalized == "heroic" then
		return { difficultyLabel = "HC", difficultyRank = 4 }
	end
	if normalized == "normal" then
		return { difficultyLabel = "N", difficultyRank = 3 }
	end
	return nil
end

-- Returns authoritative item difficulty metadata from rendered tooltip text when present.
function addon.GetTooltipDifficultyInfo(tooltip)
	if not tooltip or type(tooltip.NumLines) ~= "function" then return nil end
	for lineIndex = 2, tooltip:NumLines() do
		local info = parseDifficultyText(tooltipLineText(tooltip, lineIndex))
		if info then return info end
	end
	return nil
end

-- Renders a hidden tooltip for an item link and extracts the displayed item difficulty.
function addon.GetItemTooltipDifficultyInfo(itemLink)
	if not itemLink then return nil end
	difficultyTip:ClearLines()
	local ok = pcall(difficultyTip.SetHyperlink, difficultyTip, itemLink)
	if not ok then return nil end
	return addon.GetTooltipDifficultyInfo(difficultyTip)
end

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

function addon.CanPlayerEquip(itemLink)
	local name, _, _, _, reqLevel, itemType, subType, _, equipLoc = GetItemInfo(itemLink)
	if not name or equipLoc == "" then return false end

	classCheckTip:ClearLines()
	classCheckTip:SetHyperlink(itemLink)
	local pLoc, pKey = UnitClass("player")
	local localizedClassesLabel = tostring(_G.ITEM_CLASSES_ALLOWED or "Classes")
	localizedClassesLabel = string.gsub(localizedClassesLabel, "%s*:%s*$", "")
	local classesPattern = "^" .. escapeLuaPattern(localizedClassesLabel) .. ":?%s*(.+)"
	for i = 2, classCheckTip:NumLines() do
		local txt = _G["IS_ClassCheckTipTextLeft" .. i]:GetText()
		local list = txt and txt:match(classesPattern)
		if list and not classListContains(list, pLoc) then return false end
	end

	if itemType == "Armor" then
		if equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_NECK" or equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" then return true end
		local allowed = armorAllowed[pKey]
		if not allowed or not allowed[subType] then return false end
	end
	return true
end

function addon.GetInventoryType(itemLink)
	local _, _, _, _, _, _, _, _, invType = GetItemInfo(itemLink)
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
