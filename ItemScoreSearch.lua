local addonName, addon = ...

-- Search UI and slash-command surface for scoring cached provider items against configured profiles.
local LIST_UPGRADES_MAX = 6
local LIST_SLOT_MAX = 20

local Search = {}
addon.Search = Search
local Query = addon.Query

--------------------------------------------------
-- Slot mapping
--------------------------------------------------
local SLOT_MAP = {
	{ label = "Upgrades", inv = nil, special = true },
	{ label = "Head", inv = { "INVTYPE_HEAD" } },
	{ label = "Neck", inv = { "INVTYPE_NECK" } },
	{ label = "Shoulder", inv = { "INVTYPE_SHOULDER" } },
	{ label = "Back", inv = { "INVTYPE_CLOAK" } },
	{ label = "Chest", inv = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
	{ label = "Wrist", inv = { "INVTYPE_WRIST" } },
	{ label = "Hands", inv = { "INVTYPE_HAND" } },
	{ label = "Waist", inv = { "INVTYPE_WAIST" } },
	{ label = "Legs", inv = { "INVTYPE_LEGS" } },
	{ label = "Feet", inv = { "INVTYPE_FEET" } },
	{ label = "Finger", inv = { "INVTYPE_FINGER" } },
	{ label = "Trinket", inv = { "INVTYPE_TRINKET" } },
	{ label = "Weapon", inv = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "INVTYPE_SHIELD" }, special = true },
	{ label = "1H Weapon", inv = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" } },
	{ label = "Off-Hand", inv = { "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE" } },
	{ label = "Shield", inv = { "INVTYPE_SHIELD" } },
	{ label = "2H Weapon", inv = { "INVTYPE_2HWEAPON" } },
	{ label = "Ranged Weapon", inv = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" } },
}

local slotLabelToInv = {}
for _, slotData in ipairs(SLOT_MAP) do
	slotLabelToInv[slotData.label] = slotData.inv
end

local UPGRADE_SLOTS = {}
for _, slotData in ipairs(SLOT_MAP) do
	if not slotData.special then
		UPGRADE_SLOTS[#UPGRADE_SLOTS + 1] = {
			label = slotData.label,
			inv = slotData.inv,
		}
	end
end

--------------------------------------------------
-- Helpers
--------------------------------------------------
local function trim(value)
	if type(value) ~= "string" then return nil end
	local text = string.gsub(value, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then return nil end
	return text
end

local function parseBoolean(value)
	local low = string.lower(trim(value) or "")
	if low == "on" or low == "true" or low == "1" then return true, true end
	if low == "off" or low == "false" or low == "0" then return true, false end
	return false, nil
end

local function sourcePreview(sourceList)
	if type(sourceList) ~= "table" or #sourceList == 0 then
		return "Unknown Source", "Unknown Source"
	end

	local first = sourceList[1]
	local placeName = first.place or "Unknown Place"
	local sourceName = first.source or "Unknown Source"
	if #sourceList > 1 then
		sourceName = string.format("%s (+%d)", sourceName, #sourceList - 1)
	end
	return placeName, sourceName
end

local function difficultySuffix(label)
	label = trim(label)
	if not label then return "" end
	return " |cffcfcfcf(" .. label .. ")|r"
end

local function isAtlasDifficultyLabel(label)
	label = trim(label)
	if not label then return false end
	return label == "N" or label == "HC" or label == "M" or label == "Asc" or string.match(label, "^M%+%d+$") ~= nil
end

local function shouldUseTooltipDifficulty(metadata, tooltipInfo)
	if type(tooltipInfo) ~= "table" or not tooltipInfo.difficultyLabel then return false end
	if not metadata or not isAtlasDifficultyLabel(metadata.difficultyLabel) then return false end
	return true
end

local function resolveDisplayMetadata(itemLink, metadata)
	if type(addon.GetItemTooltipDifficultyInfo) ~= "function" then return metadata, nil end
	if not metadata or not isAtlasDifficultyLabel(metadata.difficultyLabel) then return metadata, nil end
	local tooltipInfo = addon.GetItemTooltipDifficultyInfo(itemLink)
	if not shouldUseTooltipDifficulty(metadata, tooltipInfo) then
		return metadata, nil
	end
	return tooltipInfo, tooltipInfo.difficultyLabel
end

local function replaceSourceDifficultyLabels(sources, difficultyLabel)
	if not difficultyLabel or type(sources) ~= "table" then return sources end
	local adjusted = {}
	for index, sourceData in ipairs(sources) do
		adjusted[index] = {
			place = sourceData.place,
			source = sourceData.source,
			difficultyLabel = difficultyLabel,
		}
	end
	return adjusted
end

local function belongsToSlot(invType, wanted)
	if not invType or not wanted then return false end
	for _, value in ipairs(wanted) do
		if value == invType then return true end
	end
	return false
end

local function itemRaw(itemID)
	return "item:" .. tostring(itemID) .. ":::::::::"
end

local function resolveSearchItemInfo(itemID, metadata)
	local primaryRaw = itemRaw(itemID)
	local name, link, rarity, itemLevel, requiredLevel, itemType, subType, stackCount, invType, icon = GetItemInfo(primaryRaw)
	if name then
		return {
			raw = primaryRaw,
			name = name,
			link = link,
			rarity = rarity,
			itemLevel = itemLevel,
			requiredLevel = requiredLevel,
			itemType = itemType,
			subType = subType,
			stackCount = stackCount,
			invType = invType,
			icon = icon,
		}
	end

	local fallbackID = metadata and tonumber(metadata.fallbackItemID)
	local fallbackRaw = metadata and metadata.fallbackItemLink
	if not fallbackRaw and fallbackID and fallbackID > 0 then
		fallbackRaw = itemRaw(fallbackID)
	end

	if fallbackRaw and fallbackRaw ~= primaryRaw then
		name, link, rarity, itemLevel, requiredLevel, itemType, subType, stackCount, invType, icon = GetItemInfo(fallbackRaw)
		if name then
			return {
				raw = fallbackRaw,
				name = name,
				link = link or fallbackRaw,
				rarity = rarity,
				itemLevel = itemLevel,
				requiredLevel = requiredLevel,
				itemType = itemType,
				subType = subType,
				stackCount = stackCount,
				invType = invType,
				icon = icon,
				fallbackUsed = true,
			}
		end
	end

	return nil, primaryRaw, fallbackID
end

local function queueMissingItemInfo(itemID, fallbackID)
	local queuedPrimary = Query.Add(itemID)
	local queuedFallback = false
	if fallbackID and fallbackID ~= itemID then
		queuedFallback = Query.Add(fallbackID)
	end
	return queuedPrimary or queuedFallback
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
	return addon.TuneAdaptiveBudget(currentBudget, elapsedMs, targetMs, 20, 8000)
end

local function insertTop(list, itemData, maxItems)
	local insertAt = #list + 1
	for i = 1, #list do
		if itemData.score > list[i].score then
			insertAt = i
			break
		end
	end
	table.insert(list, insertAt, itemData)
	while #list > maxItems do
		table.remove(list)
	end
end

local function makeRowData(itemID, raw, link, rarity, name, icon, score, sources, metadata, sourceDifficultyOverride)
	local displaySources = replaceSourceDifficultyLabels(sources, sourceDifficultyOverride)
	local placeText, sourceText = sourcePreview(displaySources)
	return {
		score = score,
		link = link or raw,
		raw = raw,
		rarity = rarity,
		name = name,
		icon = icon,
		dungeon = placeText,
		sourceText = sourceText,
		sources = displaySources,
		difficultyLabel = metadata and metadata.difficultyLabel or nil,
	}
end

--------------------------------------------------
-- UI construction
--------------------------------------------------
local DEFAULT_WIDTH, DEFAULT_HEIGHT, ROW_HEIGHT, MAX_ROWS = 840, 460, 20, 100
local SCORE_COLUMN_WIDTH = 100
local COLUMN_GAP = 6
local COLUMN_LEFT_INSET = 2
local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local function createPanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.035, 0.038, 0.045, 0.94)
	panel:SetBackdropBorderColor(0.34, 0.29, 0.20, 0.95)
	return panel
end

local function getWindowSettings()
	ItemScoreData = ItemScoreData or {}
	if type(ItemScoreData.searchWindow) ~= "table" then
		ItemScoreData.searchWindow = {}
	end
	return ItemScoreData.searchWindow
end

local function validDimension(value, fallback)
	value = tonumber(value)
	if not value or value ~= value or value <= 0 then
		return fallback
	end
	return value
end

local windowSettings = getWindowSettings()
local frame = CreateFrame("Frame", "ItemScoreSearchFrame", UIParent)
frame:SetSize(
	validDimension(windowSettings.width, DEFAULT_WIDTH),
	validDimension(windowSettings.height, DEFAULT_HEIGHT)
)
frame:SetPoint(
	type(windowSettings.point) == "string" and windowSettings.point or "CENTER",
	UIParent,
	type(windowSettings.relativePoint) == "string" and windowSettings.relativePoint or "CENTER",
	tonumber(windowSettings.x) or 0,
	tonumber(windowSettings.y) or 0
)
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:SetResizable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true,
	tileSize = 32,
	edgeSize = 24,
	insets = { left = 7, right = 7, top = 7, bottom = 7 },
})
frame:SetBackdropColor(0.025, 0.028, 0.034, 0.98)
frame:Hide()

local function saveWindowSettings()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	windowSettings.point = point or "CENTER"
	windowSettings.relativePoint = relativePoint or windowSettings.point
	windowSettings.x = x or 0
	windowSettings.y = y or 0
	windowSettings.width = frame:GetWidth()
	windowSettings.height = frame:GetHeight()
end

frame:SetScript("OnDragStart", function(self)
	self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	saveWindowSettings()
end)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -14)
frame.title:SetText("ItemScore Search")
frame.title:SetTextColor(0.76, 0.88, 1.0)

local titleAccent = frame:CreateTexture(nil, "ARTWORK")
titleAccent:SetTexture(FLAT_TEXTURE)
titleAccent:SetVertexColor(0.34, 0.29, 0.20, 0.85)
titleAccent:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -37)
titleAccent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -37)
titleAccent:SetHeight(1)

local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

local toolbarPanel = createPanel(frame)
toolbarPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -43)
toolbarPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -43)
toolbarPanel:SetHeight(54)

local controlsRow = CreateFrame("Frame", nil, toolbarPanel)
controlsRow:SetSize(550, 40)
controlsRow:SetPoint("LEFT", toolbarPanel, "LEFT", 14, 0)

local profileDrop = CreateFrame("Frame", "ISSearchProfileDD", controlsRow, "UIDropDownMenuTemplate")
profileDrop:SetPoint("LEFT", controlsRow, "LEFT", -16, 0)

local slotDrop = CreateFrame("Frame", "ISSearchSlotDD", controlsRow, "UIDropDownMenuTemplate")
slotDrop:SetPoint("LEFT", controlsRow, "LEFT", 120, 0)

local searchBtn = CreateFrame("Button", nil, controlsRow, "UIPanelButtonTemplate")
searchBtn:SetSize(110, 22)
searchBtn:SetText("Search")
searchBtn:SetPoint("LEFT", controlsRow, "LEFT", 284, 0)

local maxLevelLabel = controlsRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
maxLevelLabel:SetHeight(22)
maxLevelLabel:SetPoint("LEFT", controlsRow, "LEFT", 408, 0)
maxLevelLabel:SetText("Max Lvl")
maxLevelLabel:SetTextColor(0.95, 0.88, 0.68)
maxLevelLabel:SetJustifyV("MIDDLE")

local maxLevelEdit = addon.CreateEditBox(controlsRow, 44)
maxLevelEdit:SetPoint("LEFT", maxLevelLabel, "RIGHT", 6, 0)
maxLevelEdit:SetNumeric(true)
maxLevelEdit:SetText("0")

local maxLevelToggle = addon.CreateCheckButton(controlsRow, "")
maxLevelToggle:SetSize(22, 22)
maxLevelToggle:SetPoint("LEFT", maxLevelEdit, "RIGHT", -2, 0)
maxLevelToggle:SetChecked(false)
if maxLevelToggle.text then
	maxLevelToggle.text:SetText("")
	maxLevelToggle.text:Hide()
end

local function clearMaxLevelEditFocus()
	if maxLevelEdit and maxLevelEdit:HasFocus() then
		maxLevelEdit:ClearFocus()
	end
end

local resultsPanel = createPanel(frame)
resultsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -106)
resultsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)

local columnHeader = CreateFrame("Frame", nil, resultsPanel)
columnHeader:SetHeight(22)
columnHeader:SetPoint("TOPLEFT", resultsPanel, "TOPLEFT", 8, -6)
columnHeader:SetPoint("TOPRIGHT", resultsPanel, "TOPRIGHT", -28, -6)

local function createColumnLabel(parent, text)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetText(text)
	label:SetTextColor(0.86, 0.78, 0.58)
	label:SetJustifyH("LEFT")
	label:SetHeight(ROW_HEIGHT)
	if label.SetWordWrap then label:SetWordWrap(false) end
	return label
end

columnHeader.scoreText = createColumnLabel(columnHeader, "Score / Delta")
columnHeader.itemLink = createColumnLabel(columnHeader, "Item")
columnHeader.dungeonText = createColumnLabel(columnHeader, "Place")
columnHeader.bossText = createColumnLabel(columnHeader, "Source")

local headerDivider = columnHeader:CreateTexture(nil, "ARTWORK")
headerDivider:SetTexture(FLAT_TEXTURE)
headerDivider:SetVertexColor(0.34, 0.29, 0.20, 0.85)
headerDivider:SetPoint("BOTTOMLEFT", columnHeader, "BOTTOMLEFT", 0, 0)
headerDivider:SetPoint("BOTTOMRIGHT", columnHeader, "BOTTOMRIGHT", 0, 0)
headerDivider:SetHeight(1)

local scrollFrame = CreateFrame("ScrollFrame", "ISSearchScroll", resultsPanel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", resultsPanel, "TOPLEFT", 8, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", resultsPanel, "BOTTOMRIGHT", -28, 8)
frame:HookScript("OnMouseDown", clearMaxLevelEditFocus)
scrollFrame:HookScript("OnMouseDown", clearMaxLevelEditFocus)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetWidth(1)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)

local function layoutColumns(container)
	local width = container:GetWidth() or 0
	local flexibleWidth = math.max(
		0,
		(width - COLUMN_LEFT_INSET - SCORE_COLUMN_WIDTH - (COLUMN_GAP * 3)) / 3
	)

	container.scoreText:ClearAllPoints()
	container.scoreText:SetPoint("LEFT", container, "LEFT", COLUMN_LEFT_INSET, 0)
	container.scoreText:SetWidth(SCORE_COLUMN_WIDTH)
	container.itemLink:ClearAllPoints()
	container.itemLink:SetPoint("LEFT", container.scoreText, "RIGHT", COLUMN_GAP, 0)
	container.itemLink:SetWidth(flexibleWidth)
	container.dungeonText:ClearAllPoints()
	container.dungeonText:SetPoint("LEFT", container.itemLink, "RIGHT", COLUMN_GAP, 0)
	container.dungeonText:SetWidth(flexibleWidth)
	container.bossText:ClearAllPoints()
	container.bossText:SetPoint("LEFT", container.dungeonText, "RIGHT", COLUMN_GAP, 0)
	container.bossText:SetWidth(flexibleWidth)
end

layoutColumns(columnHeader)

local rows = {}
local hoveredItemRow = nil
local tooltipModifierWatcher = CreateFrame("Frame")

local function hideCompareTooltips()
	if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
	if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
end

local function showItemTooltip(row)
	if not row or not row.link then return end

	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(row.link)
	if type(addon.GetTooltipDifficultyInfo) == "function" and isAtlasDifficultyLabel(row.difficultyLabel) then
		local tooltipInfo = addon.GetTooltipDifficultyInfo(GameTooltip)
		if shouldUseTooltipDifficulty({ difficultyLabel = row.difficultyLabel }, tooltipInfo) then
			row.difficultyLabel = tooltipInfo.difficultyLabel
			row.sources = replaceSourceDifficultyLabels(row.sources, row.difficultyLabel)
			if row.baseItemText then
				row.itemLink:SetText(row.baseItemText .. difficultySuffix(row.difficultyLabel))
			end
		end
	end
	if type(row.sources) == "table" and #row.sources > 1 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Known Sources", 0.9, 0.9, 0.9)
		local maxSources = math.min(#row.sources, 8)
		for sourceIndex = 1, maxSources do
			local sourceData = row.sources[sourceIndex]
			local line = string.format(
				"%s - %s",
				sourceData.place or "Unknown Place",
				sourceData.source or "Unknown Source"
			)
			if sourceData.difficultyLabel then
				line = line .. " (" .. sourceData.difficultyLabel .. ")"
			end
			GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
		end
		if #row.sources > maxSources then
			GameTooltip:AddLine(string.format("+%d more", #row.sources - maxSources), 0.6, 0.6, 0.6)
		end
	end
	GameTooltip:Show()

	local compareEnabled = IsShiftKeyDown and IsShiftKeyDown() and true or false
	if compareEnabled and GameTooltip_ShowCompareItem then
		GameTooltip_ShowCompareItem(GameTooltip)
	else
		hideCompareTooltips()
	end
	row.compareShown = compareEnabled
end

local function watchTooltipModifier()
	if
		hoveredItemRow
		and IsShiftKeyDown
		and hoveredItemRow.compareShown ~= (IsShiftKeyDown() and true or false)
	then
		showItemTooltip(hoveredItemRow)
	end
end

local function stopItemTooltip(row)
	if hoveredItemRow ~= row then return end
	hoveredItemRow = nil
	row.compareShown = nil
	tooltipModifierWatcher:SetScript("OnUpdate", nil)
	GameTooltip:Hide()
	hideCompareTooltips()
end

for rowIndex = 1, MAX_ROWS do
	local row = CreateFrame("Frame", nil, scrollChild)
	row:SetSize(1, ROW_HEIGHT)
	row:EnableMouse(true)
	if rowIndex == 1 then
		row:SetPoint("TOPLEFT")
	else
		row:SetPoint("TOPLEFT", rows[rowIndex - 1], "BOTTOMLEFT")
	end

	row.scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.scoreText:SetHeight(ROW_HEIGHT)
	row.scoreText:SetJustifyH("LEFT")
	if row.scoreText.SetWordWrap then row.scoreText:SetWordWrap(false) end

	row.itemLink = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.itemLink:SetHeight(ROW_HEIGHT)
	row.itemLink:SetJustifyH("LEFT")
	if row.itemLink.SetWordWrap then row.itemLink:SetWordWrap(false) end

	row.dungeonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.dungeonText:SetHeight(ROW_HEIGHT)
	row.dungeonText:SetJustifyH("LEFT")
	if row.dungeonText.SetWordWrap then row.dungeonText:SetWordWrap(false) end

	row.bossText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.bossText:SetHeight(ROW_HEIGHT)
	row.bossText:SetJustifyH("LEFT")
	if row.bossText.SetWordWrap then row.bossText:SetWordWrap(false) end

	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints()
	row.background:SetTexture(FLAT_TEXTURE)
	row.backgroundColor = { 0.035, 0.038, 0.045, rowIndex % 2 == 0 and 0.82 or 0.55 }
	row.background:SetVertexColor(unpack(row.backgroundColor))
	layoutColumns(row)

	row:SetScript("OnEnter", function(self)
		self.background:SetVertexColor(0.10, 0.12, 0.15, 0.95)
		if not self.link then return end
		hoveredItemRow = self
		showItemTooltip(self)
		tooltipModifierWatcher:SetScript("OnUpdate", watchTooltipModifier)
	end)

	row:SetScript("OnLeave", function(self)
		self.background:SetVertexColor(unpack(self.backgroundColor))
		stopItemTooltip(self)
	end)
	row:SetScript("OnHide", stopItemTooltip)
	row:SetScript("OnMouseDown", clearMaxLevelEditFocus)

	rows[rowIndex] = row
end

local function layoutSearchWindow()
	local contentWidth = math.max(0, scrollFrame:GetWidth() or 0)
	scrollChild:SetWidth(contentWidth)
	layoutColumns(columnHeader)
	for _, row in ipairs(rows) do
		row:SetWidth(contentWidth)
		layoutColumns(row)
	end
	scrollFrame:UpdateScrollChildRect()
end

frame.resizeGrip = CreateFrame("Button", nil, frame)
frame.resizeGrip:SetSize(18, 18)
frame.resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
frame.resizeGrip:SetScript("OnMouseDown", function(_, button)
	if button == "LeftButton" then
		frame:StartSizing("BOTTOMRIGHT")
	end
end)
frame.resizeGrip:SetScript("OnMouseUp", function(_, button)
	if button == "LeftButton" then
		frame:StopMovingOrSizing()
		saveWindowSettings()
		layoutSearchWindow()
	end
end)

frame:SetScript("OnSizeChanged", layoutSearchWindow)
frame:SetScript("OnHide", saveWindowSettings)
layoutSearchWindow()

if type(UISpecialFrames) == "table" then
	UISpecialFrames[#UISpecialFrames + 1] = "ItemScoreSearchFrame"
end

local selectedProfile
local selectedSlot = SLOT_MAP[1].label

local function fallbackStatus(errorText)
	return {
		updating = false,
		stale = true,
		lastBuildAt = 0,
		itemCount = 0,
		lastError = errorText or "Search source manager unavailable",
		enabledProviderCount = 0,
		availableProviderCount = 0,
		settingsChanged = false,
		providers = {},
	}
end

local function getCatalogAndStatus()
	if type(addon.GetSearchCatalog) == "function" then
		return addon.GetSearchCatalog()
	end
	return {
		itemIDs = {},
		itemSources = {},
		itemMeta = {},
		byPlace = {},
	}, fallbackStatus("GetSearchCatalog unavailable")
end

local function getStatusSafe()
	if type(addon.GetSearchCacheStatus) == "function" then
		return addon.GetSearchCacheStatus()
	end
	return fallbackStatus("GetSearchCacheStatus unavailable")
end

local function refreshCacheSafe(forceRefresh, silent)
	if type(addon.RefreshSearchCache) == "function" then
		return addon.RefreshSearchCache(forceRefresh, silent)
	end
	print("|cffff7f00ItemScore:|r search source manager unavailable.")
	return false, "unavailable"
end

local function setSourceOptionSafe(optionKey, value)
	if type(addon.SetSearchSourceOption) == "function" then
		return addon.SetSearchSourceOption(optionKey, value)
	end
	print("|cffff7f00ItemScore:|r search source manager unavailable.")
	return false
end

local function getSourceSettingsSafe()
	if type(addon.GetSearchSourceSettings) == "function" then
		return addon.GetSearchSourceSettings()
	end
	return {}
end

local function getArmorTypeFilterForProfile(profileName)
	if type(addon.GetProfileArmorTypeFilterState) == "function" then
		local hasFilter, selectedTypes = addon.GetProfileArmorTypeFilterState(profileName)
		if hasFilter and type(selectedTypes) == "table" then
			return true, selectedTypes
		end
	end
	return false, {}
end

local function getWeaponTypeFilterForProfile(profileName)
	if type(addon.GetProfileWeaponTypeFilterState) == "function" then
		local hasFilter, selectedTypes = addon.GetProfileWeaponTypeFilterState(profileName)
		if hasFilter and type(selectedTypes) == "table" then
			return true, selectedTypes
		end
	end
	return false, {}
end

local function isArmorTypeFilterExemptSlot(invType)
	return invType == "INVTYPE_CLOAK"
end

local function queueRefreshSafe(reason)
	if type(addon.QueueSearchCacheRefresh) == "function" then
		addon.QueueSearchCacheRefresh(reason)
	end
end

local function getDisabledPlacesSafe()
	if type(addon.GetDisabledAtlasLootPlaces) == "function" then
		return addon.GetDisabledAtlasLootPlaces()
	end
	return {}
end

local function setAtlasPlaceEnabledSafe(placeName, enabled)
	if type(addon.SetAtlasLootPlaceEnabled) == "function" then
		return addon.SetAtlasLootPlaceEnabled(placeName, enabled)
	end
	print("|cffff7f00ItemScore:|r search source manager unavailable.")
	return false
end

local function setAllAtlasRaidsEnabledSafe(enabled)
	if type(addon.SetAllAtlasLootRaidsEnabled) == "function" then
		return addon.SetAllAtlasLootRaidsEnabled(enabled)
	end
	print("|cffff7f00ItemScore:|r search source manager unavailable.")
	return false
end

local function getKnownPlacesSafe()
	if type(addon.GetKnownSearchPlaces) == "function" then
		return addon.GetKnownSearchPlaces()
	end
	return {}
end

local function normalizeMaxRequiredLevel(value)
	local numeric = math.floor(tonumber(value) or 0)
	if numeric < 0 then numeric = 0 end
	if numeric > 80 then numeric = 80 end
	return numeric
end

local function refreshMaxLevelFilterControls()
	local settings = getSourceSettingsSafe()
	local enabled = settings.searchUseMaxRequiredLevel and true or false
	local maxLevel = normalizeMaxRequiredLevel(settings.searchMaxRequiredLevel)

	maxLevelToggle:SetChecked(enabled)
	if not maxLevelEdit:HasFocus() then
		maxLevelEdit:SetText(tostring(maxLevel))
		maxLevelEdit:SetCursorPosition(0)
	end

	maxLevelEdit:Enable()
end

local function applyMaxLevelFilterValue()
	local maxLevel = normalizeMaxRequiredLevel(maxLevelEdit:GetText())
	maxLevelEdit:SetText(tostring(maxLevel))
	maxLevelEdit:SetCursorPosition(0)
	setSourceOptionSafe("searchMaxRequiredLevel", maxLevel)
end

local function applyMaxLevelFilterEnabled()
	setSourceOptionSafe("searchUseMaxRequiredLevel", maxLevelToggle:GetChecked())
end

maxLevelToggle:SetScript("OnClick", function(btn)
	clearMaxLevelEditFocus()
	setSourceOptionSafe("searchUseMaxRequiredLevel", btn:GetChecked())
	refreshMaxLevelFilterControls()
end)

maxLevelEdit:SetScript("OnEnterPressed", function(box)
	box:ClearFocus()
	applyMaxLevelFilterValue()
end)

maxLevelEdit:SetScript("OnEditFocusLost", function()
	applyMaxLevelFilterValue()
end)

local function refreshRows(data)
	if #data == 0 then
		data = {
			{ isHeader = true, label = "No results" },
		}
	end

	for rowIndex = 1, MAX_ROWS do
		local row = rows[rowIndex]
		local rowData = data[rowIndex]
		if rowData then
			if rowData.isHeader then
				row.backgroundColor = { 0.13, 0.10, 0.05, 0.90 }
				row.background:SetVertexColor(unpack(row.backgroundColor))
				row.scoreText:SetText("")
				row.itemLink:SetText("|cffffd66b" .. rowData.label .. "|r")
				row.dungeonText:SetText("")
				row.bossText:SetText("")
				row.link = nil
				row.sources = nil
				row.baseItemText = nil
				row.difficultyLabel = nil
			else
				row.backgroundColor = { 0.035, 0.038, 0.045, rowIndex % 2 == 0 and 0.82 or 0.55 }
				row.background:SetVertexColor(unpack(row.backgroundColor))
				local delta = addon.CompareDelta(rowData.link, selectedProfile)
				local deltaInvalid = type(delta) ~= "number" or delta ~= delta or math.abs(delta) >= 999999
				if deltaInvalid then
					row.scoreText:SetText(string.format("%.1f |cffffff00(?)|r", rowData.score))
				else
					local deltaColor = "|cffffffff"
					if delta < 0 then deltaColor = "|cffff0000" end
					row.scoreText:SetText(string.format("%.1f %s(%+.1f)|r", rowData.score, deltaColor, delta))
				end
				local _, _, rarity = GetItemInfo(rowData.link)
				local color = select(4, GetItemQualityColor(rarity or 1))
				local itemText = color .. (select(2, GetItemInfo(rowData.raw)) or ("[" .. rowData.name .. "]")) .. "|r"
				row.itemLink:SetText(itemText .. difficultySuffix(rowData.difficultyLabel))
				row.dungeonText:SetText(rowData.dungeon or "")
				row.bossText:SetText(rowData.sourceText or "")
				row.link = rowData.link
				row.sources = rowData.sources
				row.baseItemText = itemText
				row.difficultyLabel = rowData.difficultyLabel
			end
			row:Show()
		else
			row.scoreText:SetText("")
			row.itemLink:SetText("")
			row.dungeonText:SetText("")
			row.bossText:SetText("")
			row.link = nil
			row.sources = nil
			row.baseItemText = nil
			row.difficultyLabel = nil
			row:Hide()
		end
	end

	local count = #data
	if count > MAX_ROWS then count = MAX_ROWS end
	scrollChild:SetHeight(ROW_HEIGHT * count)
	scrollFrame:UpdateScrollChildRect()
end

local function profile_OnClick(self)
	clearMaxLevelEditFocus()
	selectedProfile = self.value
	UIDropDownMenu_SetSelectedValue(profileDrop, self.value)
end

local function slot_OnClick(self)
	clearMaxLevelEditFocus()
	selectedSlot = self.value
	UIDropDownMenu_SetSelectedValue(slotDrop, self.value)
end

UIDropDownMenu_Initialize(profileDrop, function()
	for _, name in ipairs(addon.GetProfiles()) do
		UIDropDownMenu_AddButton({
			text = name,
			value = name,
			func = profile_OnClick,
		})
	end
end)
UIDropDownMenu_SetWidth(profileDrop, 100)
selectedProfile = addon.GetProfiles()[1]
UIDropDownMenu_SetSelectedValue(profileDrop, selectedProfile)

UIDropDownMenu_Initialize(slotDrop, function()
	for _, slotData in ipairs(SLOT_MAP) do
		UIDropDownMenu_AddButton({
			text = slotData.label,
			value = slotData.label,
			func = slot_OnClick,
		})
	end
end)
UIDropDownMenu_SetWidth(slotDrop, 100)
UIDropDownMenu_SetSelectedValue(slotDrop, selectedSlot)

local function cacheStatusToMessage(status)
	if status.enabledProviderCount == 0 then
		return "No search data source enabled. Enable them in Interface -> AddOns -> ItemScore -> Loot Sources (or use /is lootcollector on, /is atlas on)."
	end
	if status.availableProviderCount == 0 then
		return "No supported source addon loaded (LootCollector / AtlasLoot)."
	end
	if status.settingsChanged then
		return "Search cache is rebuilding after loot-source setting changes. Try again shortly."
	end
	if status.updating and status.itemCount == 0 then
		return "Building search cache in background. Try again shortly."
	end
	if status.itemCount == 0 then
		return "Search cache empty. Refresh in ItemScore -> Loot Sources or use /is refresh."
	end
	if status.lastError then
		return "Last cache update failed. Use /is refresh."
	end
	return "No data found"
end

--------------------------------------------------
-- Background search worker
--------------------------------------------------
local searchState = nil
local lastSearchStats = nil
local searchWorker = CreateFrame("Frame")
local pendingQueryRefresh = false

local function summarizeSearchStats(stats)
	if type(stats) ~= "table" then return nil end
	return string.format(
		"checked=%d, rows=%d, itemInfo=%d, level=%d, armor=%d, weapon=%d, equip=%d, score=%d, upgrade=%d, slot=%d",
		stats.checked or 0,
		stats.rows or 0,
		stats.missingItemInfo or 0,
		stats.blockedByLevel or 0,
		stats.blockedByArmorType or 0,
		stats.blockedByWeaponType or 0,
		stats.blockedByEquip or 0,
		stats.blockedByScore or 0,
		stats.blockedByUpgrade or 0,
		stats.blockedBySlot or 0
	)
end

local function resetSearchButton()
	searchBtn:SetText("Search")
	searchBtn:Enable()
end

local function scheduleSearchAfterItemInfo()
	if pendingQueryRefresh then return end
	pendingQueryRefresh = true
	Query.RegisterDone(function()
		pendingQueryRefresh = false
		if frame:IsShown() then
			Search.DoSearch()
		end
	end)
end

local function buildUpgradeRows(slotStates)
	local resultRows = {}
	for _, slotState in ipairs(slotStates) do
		if #slotState.results > 0 then
			resultRows[#resultRows + 1] = {
				isHeader = true,
				label = slotState.label,
			}
			for _, rowData in ipairs(slotState.results) do
				resultRows[#resultRows + 1] = rowData
			end
		end
	end
	return resultRows
end

local function processSearchTask(state, maxOps)
	local budget = tonumber(maxOps) or 200
	if budget < 1 then budget = 1 end
	local ops = 0

	while ops < budget and state.index <= state.total do
		local itemID = state.itemIDs[state.index]
		state.index = state.index + 1
		ops = ops + 1
		state.stats.checked = state.stats.checked + 1

		local itemMetadata = state.itemMeta[itemID]
		local itemInfo, raw, fallbackID = resolveSearchItemInfo(itemID, itemMetadata)
		if not itemInfo then
			if not queueMissingItemInfo(itemID, fallbackID) then
				state.skippedItemInfo = true
			end
			state.missingItemInfo = true
			state.stats.missingItemInfo = state.stats.missingItemInfo + 1
		else
			local reqLevel = tonumber(itemInfo.requiredLevel) or 0
			local blockedByArmorType = false
			if state.hasArmorTypeFilter and type(addon.NormalizeArmorType) == "function" then
				local armorTypeKey = addon.NormalizeArmorType(itemInfo.itemType, itemInfo.subType)
				if armorTypeKey and not isArmorTypeFilterExemptSlot(itemInfo.invType) and not state.armorTypeFilter[armorTypeKey] then
					blockedByArmorType = true
					state.stats.blockedByArmorType = state.stats.blockedByArmorType + 1
				end
			end

			local blockedByWeaponType = false
			if state.hasWeaponTypeFilter and type(addon.IsWeaponTypeFilterRelevant) == "function" and addon.IsWeaponTypeFilterRelevant(itemInfo.itemType, itemInfo.invType) then
				local weaponTypeKey = nil
				if type(addon.NormalizeWeaponType) == "function" then
					weaponTypeKey = addon.NormalizeWeaponType(itemInfo.itemType, itemInfo.subType, itemInfo.invType)
				end
				if not weaponTypeKey or not state.weaponTypeFilter[weaponTypeKey] then
					blockedByWeaponType = true
					state.stats.blockedByWeaponType = state.stats.blockedByWeaponType + 1
				end
			end

			local blockedByLevel = state.maxRequiredLevel > 0 and reqLevel > state.maxRequiredLevel
			if blockedByLevel then
				state.stats.blockedByLevel = state.stats.blockedByLevel + 1
			end

			if not blockedByArmorType and not blockedByWeaponType and not blockedByLevel then
				local itemLink = itemInfo.link or itemInfo.raw or raw
				if addon.CanPlayerEquip(itemLink) then
					local score = addon.CalculateScore(itemLink, state.profileName)
					if score and score >= 5 then
						local sources = state.itemSources[itemID] or {}
						local metadata, sourceDifficultyOverride = resolveDisplayMetadata(itemLink, itemMetadata)
						local rowData = makeRowData(itemID, itemInfo.raw or raw, itemLink, itemInfo.rarity, itemInfo.name, itemInfo.icon, score, sources, metadata, sourceDifficultyOverride)

						if state.isUpgradeSearch then
							if addon.IsUpgrade(itemLink, state.profileName) then
								for _, slotState in ipairs(state.upgradeSlotStates) do
									if belongsToSlot(itemInfo.invType, slotState.inv) then
										insertTop(slotState.results, rowData, LIST_UPGRADES_MAX)
										state.stats.rows = state.stats.rows + 1
									end
								end
							else
								state.stats.blockedByUpgrade = state.stats.blockedByUpgrade + 1
							end
						elseif belongsToSlot(itemInfo.invType, state.slotInvTypes) then
							insertTop(state.results, rowData, LIST_SLOT_MAX)
							state.stats.rows = state.stats.rows + 1
						else
							state.stats.blockedBySlot = state.stats.blockedBySlot + 1
						end
					else
						state.stats.blockedByScore = state.stats.blockedByScore + 1
					end
				else
					state.stats.blockedByEquip = state.stats.blockedByEquip + 1
				end
			end
		end
	end

	if state.index > state.total then
		if state.isUpgradeSearch then
			state.finalRows = buildUpgradeRows(state.upgradeSlotStates)
		else
			state.finalRows = state.results
		end
		return true
	end

	return false
end

local function finishSearchTask(state)
	searchState = nil
	searchWorker:SetScript("OnUpdate", nil)

	local rowsData = state.finalRows or {}
	lastSearchStats = state.stats
	if Query.IsBusy() then
		if #rowsData > 0 then
			refreshRows(rowsData)
		else
			refreshRows({
				{ isHeader = true, label = "Fetching item info. Results will update shortly." },
			})
		end
		resetSearchButton()
		scheduleSearchAfterItemInfo()
		return
	end

	resetSearchButton()
	if #rowsData == 0 then
		local detail = summarizeSearchStats(state.stats)
		local label = state.missingItemInfo and "No data found (some item info unavailable)." or "No data found"
		if detail then
			label = label .. " " .. detail
		end
		refreshRows({
			{ isHeader = true, label = label },
		})
	else
		refreshRows(rowsData)
	end
end

local function searchWorkerOnUpdate()
	local state = searchState
	if not state then
		searchWorker:SetScript("OnUpdate", nil)
		return
	end

	local startMs = nowMillis()
	local done = processSearchTask(state, state.opsBudget)
	local elapsedMs = nowMillis() - startMs
	state.opsBudget = tuneBudget(state.opsBudget, elapsedMs, state.targetMs)

	local processed = state.index - 1
	if processed < 0 then processed = 0 end
	local percent = 100
	if state.total > 0 then
		percent = math.floor((processed / state.total) * 100)
		if percent > 100 then percent = 100 end
	end
	searchBtn:SetText(string.format("Search %d%%", percent))

	if done then
		finishSearchTask(state)
	end
end

local function startSearchTask(profileName, slotLabel, catalog)
	local settings = getSourceSettingsSafe()
	local maxRequiredLevel = normalizeMaxRequiredLevel(settings.searchMaxRequiredLevel)
	local hasArmorTypeFilter, armorTypeFilter = getArmorTypeFilterForProfile(profileName)
	local hasWeaponTypeFilter, weaponTypeFilter = getWeaponTypeFilterForProfile(profileName)
	if not settings.searchUseMaxRequiredLevel then
		maxRequiredLevel = 0
	end

	searchState = {
		profileName = profileName,
		slotLabel = slotLabel,
		itemIDs = (catalog and catalog.itemIDs) or {},
		itemSources = (catalog and catalog.itemSources) or {},
		itemMeta = (catalog and catalog.itemMeta) or {},
		total = #((catalog and catalog.itemIDs) or {}),
		index = 1,
		missingItemInfo = false,
		skippedItemInfo = false,
		opsBudget = 220,
		targetMs = 5,
		maxRequiredLevel = maxRequiredLevel,
		hasArmorTypeFilter = hasArmorTypeFilter,
		armorTypeFilter = armorTypeFilter,
		hasWeaponTypeFilter = hasWeaponTypeFilter,
		weaponTypeFilter = weaponTypeFilter,
		results = {},
		isUpgradeSearch = slotLabel == "Upgrades",
		stats = {
			checked = 0,
			rows = 0,
			missingItemInfo = 0,
			blockedByLevel = 0,
			blockedByArmorType = 0,
			blockedByWeaponType = 0,
			blockedByEquip = 0,
			blockedByScore = 0,
			blockedByUpgrade = 0,
			blockedBySlot = 0,
		},
	}

	if searchState.isUpgradeSearch then
		searchState.upgradeSlotStates = {}
		for _, slotInfo in ipairs(UPGRADE_SLOTS) do
			searchState.upgradeSlotStates[#searchState.upgradeSlotStates + 1] = {
				label = slotInfo.label,
				inv = slotInfo.inv,
				results = {},
			}
		end
	else
		searchState.slotInvTypes = slotLabelToInv[slotLabel]
	end

	searchBtn:SetText("Search 0%")
	searchBtn:Disable()
	searchWorker:SetScript("OnUpdate", searchWorkerOnUpdate)
end

--------------------------------------------------
-- Search entrypoint
--------------------------------------------------
local function doSearch()
	if not frame:IsShown() then return end

	clearMaxLevelEditFocus()
	applyMaxLevelFilterValue()
	applyMaxLevelFilterEnabled()

	if not selectedProfile or not selectedSlot then return end

	local catalog, cacheStatus = getCatalogAndStatus()
	if cacheStatus.settingsChanged then
		if cacheStatus.enabledProviderCount > 0 then
			refreshCacheSafe(true, true)
			catalog, cacheStatus = getCatalogAndStatus()
		end
		if cacheStatus.settingsChanged or cacheStatus.updating or cacheStatus.enabledProviderCount == 0 then
			resetSearchButton()
			refreshRows({
				{ isHeader = true, label = cacheStatusToMessage(cacheStatus) },
			})
			return
		end
	end

	if #(catalog.itemIDs or {}) == 0 and cacheStatus.enabledProviderCount > 0 and not cacheStatus.updating then
		refreshCacheSafe(true, true)
		catalog, cacheStatus = getCatalogAndStatus()
	end

	if #(catalog.itemIDs or {}) == 0 then
		resetSearchButton()
		refreshRows({
			{ isHeader = true, label = cacheStatusToMessage(cacheStatus) },
		})
		return
	end

	startSearchTask(selectedProfile, selectedSlot, catalog)
end

Search.DoSearch = doSearch
searchBtn:SetScript("OnClick", doSearch)

function Search.Toggle()
	if frame:IsShown() then
		frame:Hide()
		searchState = nil
		searchWorker:SetScript("OnUpdate", nil)
		resetSearchButton()
	else
		refreshMaxLevelFilterControls()
		frame:Show()
	end
end

--------------------------------------------------
-- Slash commands
--------------------------------------------------
local function printHelp()
	print("|cff00ff00ItemScore Search Commands|r")
	print("/is                  - Toggle search window")
	print("/is refresh          - Rebuild local search cache now")
	print("/is status           - Show cache/provider status")
	print("/is searchstatus     - Show last search filter counters")
	print("/is lootcollector on|off")
	print("/is atlas on|off")
	print("/is atlas classic on|off")
	print("/is atlas tbc on|off")
	print("/is atlas wrath on|off")
	print("/is atlas raid on|off  (enable/disable all raids)")
	print("/is atlas place on <Area Name>")
	print("/is atlas place off <Area Name>")
	print("/is atlas place list")
	print("/is atlas place all")
end

local function setAtlasOption(optionKey, valueString)
	local parsed, boolValue = parseBoolean(valueString)
	if not parsed then
		print("ItemScore: use on/off.")
		return
	end

	local changed = setSourceOptionSafe(optionKey, boolValue)
	if changed then
		queueRefreshSafe("atlas_option:" .. optionKey)
		refreshCacheSafe(true, true)
	end
	print(string.format("ItemScore: %s = %s", optionKey, boolValue and "on" or "off"))
end

SLASH_ISSEARCH1 = "/is"
SlashCmdList["ISSEARCH"] = function(msg)
	msg = trim(msg) or ""
	if msg == "" or msg == "search" then
		Search.Toggle()
		return
	end

	if msg == "refresh" then
		refreshCacheSafe(true, false)
		return
	end

	if msg == "status" then
		local status = getStatusSafe()
		print(string.format("ItemScore: cache items=%d, stale=%s, updating=%s", status.itemCount, tostring(status.stale), tostring(status.updating)))
		print(string.format("ItemScore: providers enabled=%d, available=%d", status.enabledProviderCount, status.availableProviderCount))
		for providerKey, providerStatus in pairs(status.providers or {}) do
			local adapterText = providerStatus.adapterLabel or providerStatus.adapter or "n/a"
			local detailText = providerStatus.reason and (" - " .. providerStatus.reason) or ""
			print(string.format(
				"ItemScore: %s enabled=%s, available=%s, adapter=%s%s",
				tostring(providerKey),
				tostring(providerStatus.enabled),
				tostring(providerStatus.available),
				tostring(adapterText),
				detailText
			))
			local last = providerStatus.last
			if type(last) == "table" then
				local parts = {}
				local keys = { "items", "sources", "discoveries", "worldforgedDiscoveries", "worldforgedMappings", "vendorItems", "mappingCount", "tables", "scannedMenus", "missingItemTables" }
				for _, key in ipairs(keys) do
					if last[key] ~= nil then
						parts[#parts + 1] = key .. "=" .. tostring(last[key])
					end
				end
				if last.realmKey then
					parts[#parts + 1] = "realm=" .. tostring(last.realmKey)
				end
				if last.adapter then
					parts[#parts + 1] = "lastAdapter=" .. tostring(last.adapter)
				end
				if #parts > 0 then
					print("ItemScore: " .. tostring(providerKey) .. " last " .. table.concat(parts, ", "))
				end
				if last.error then
					print("ItemScore: " .. tostring(providerKey) .. " error: " .. tostring(last.error))
				elseif last.reason then
					print("ItemScore: " .. tostring(providerKey) .. " reason: " .. tostring(last.reason))
				end
			end
		end
		if status.currentProvider then
			print("ItemScore: currently processing provider: " .. tostring(status.currentProvider))
		end
		if status.lastError then
			print("ItemScore: last cache error: " .. status.lastError)
		end
		return
	end

	if msg == "searchstatus" or msg == "searchdiag" then
		local detail = summarizeSearchStats(lastSearchStats)
		if detail then
			print("ItemScore: last search " .. detail)
		else
			print("ItemScore: no search has completed yet.")
		end
		return
	end

	local lootCollectorArg = msg:match("^lootcollector%s+(.+)$") or msg:match("^lc%s+(.+)$")
	if lootCollectorArg then
		setAtlasOption("useLootCollector", lootCollectorArg)
		return
	end

	local atlasArgs = msg:match("^atlas%s+(.+)$")
	if atlasArgs then
		local token, remainder = atlasArgs:match("^(%S+)%s*(.-)$")
		token = string.lower(token or "")
		remainder = trim(remainder) or ""

		if token == "on" or token == "off" then
			setAtlasOption("useAtlasLoot", token)
			return
		end

		if token == "classic" then
			setAtlasOption("atlasClassic", remainder)
			return
		end

		if token == "tbc" then
			setAtlasOption("atlasTBC", remainder)
			return
		end

		if token == "wrath" then
			setAtlasOption("atlasWrath", remainder)
			return
		end

		if token == "dungeon" then
			print("ItemScore: dungeons are always enabled for active expansions.")
			return
		end

		if token == "raid" then
			local parsed, enabled = parseBoolean(remainder)
			if not parsed then
				print("ItemScore: use /is atlas raid on|off")
				return
			end
			local changed = setAllAtlasRaidsEnabledSafe(enabled)
			if changed then
				queueRefreshSafe("atlas_raid_all")
				refreshCacheSafe(true, true)
			end
			print(string.format("ItemScore: all AtlasLoot raids %s.", enabled and "enabled" or "disabled"))
			return
		end

		if token == "place" then
			local action, placeName = remainder:match("^(%S+)%s*(.-)$")
			action = string.lower(action or "")
			placeName = trim(placeName)

			if action == "list" then
				local disabledPlaces = getDisabledPlacesSafe()
				if #disabledPlaces == 0 then
					print("ItemScore: no disabled AtlasLoot areas.")
				else
					print("ItemScore: disabled AtlasLoot areas:")
					for _, name in ipairs(disabledPlaces) do
						print(" - " .. name)
					end
				end
				return
			end

			if action == "all" then
				local places = getKnownPlacesSafe()
				if #places == 0 then
					print("ItemScore: no cached places available yet. Run /is refresh first.")
				else
					print("ItemScore: known cached places:")
					for _, name in ipairs(places) do
						print(" - " .. name)
					end
				end
				return
			end

			if (action == "on" or action == "off") and placeName then
				local enabled = action == "on"
				local changed = setAtlasPlaceEnabledSafe(placeName, enabled)
				if changed then
					queueRefreshSafe("atlas_place:" .. action)
					refreshCacheSafe(true, true)
				end
				print(string.format("ItemScore: AtlasLoot area '%s' %s.", placeName, enabled and "enabled" or "disabled"))
				return
			end
		end
	end

	printHelp()
end
