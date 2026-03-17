local addonName, addon = ...

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

local function escapeLuaPattern(text)
	return (tostring(text or ""):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
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

function inventoryType(itemLink)
	local _, _, _, _, _, _, _, _, invType = GetItemInfo(itemLink)
	if (invType == nil or strtrim(invType) == "") then
		return nil
	else
		return invType
	end
end

function tableToString(tbl, indent, visited)
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
			valueStr = tableToString(v, indent + 1, visited)
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

_G.addon = addon
