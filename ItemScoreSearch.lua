local addonName, addon = ...

local LIST_UPGRADES_MAX = 6
local LIST_SLOT_MAX = 20

local Search = {}
_G.ItemScoreSearch = Search

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
	{ label = "Ranged Weapon", inv = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT" } },
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

local function belongsToSlot(invType, wanted)
	if not invType or not wanted then return false end
	for _, value in ipairs(wanted) do
		if value == invType then return true end
	end
	return false
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
	local budget = tonumber(currentBudget) or 200
	if budget < 20 then budget = 20 end
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
	if budget < 20 then budget = 20 end
	if budget > 8000 then budget = 8000 end
	return budget
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

local function makeRowData(itemID, raw, link, rarity, name, icon, score, sources)
	local placeText, sourceText = sourcePreview(sources)
	return {
		score = score,
		link = link or raw,
		raw = raw,
		rarity = rarity,
		name = name,
		icon = icon,
		dungeon = placeText,
		sourceText = sourceText,
		sources = sources,
	}
end

--------------------------------------------------
-- UI construction
--------------------------------------------------
local WIDTH, HEIGHT, ROW_HEIGHT, MAX_ROWS = 800, 440, 20, 100
local frame = CreateFrame("Frame", "ItemScoreSearchFrame", UIParent, "UIPanelDialogTemplate")
frame:SetSize(WIDTH, HEIGHT)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.title:SetPoint("TOP", frame, "TOP", 0, -9)
frame.title:SetText("ItemScore Search")

local profileDrop = CreateFrame("Frame", "ISSearchProfileDD", frame, "UIDropDownMenuTemplate")
profileDrop:SetPoint("TOPLEFT", 16, -40)

local slotDrop = CreateFrame("Frame", "ISSearchSlotDD", frame, "UIDropDownMenuTemplate")
slotDrop:SetPoint("LEFT", profileDrop, "RIGHT", 120, 0)

local searchBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
searchBtn:SetSize(110, 22)
searchBtn:SetText("Search")
searchBtn:SetPoint("LEFT", slotDrop, "RIGHT", 16, 0)

local maxLevelLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
maxLevelLabel:SetPoint("LEFT", searchBtn, "RIGHT", 14, 0)
maxLevelLabel:SetText("Max Lvl")

local maxLevelEdit = addon.CreateEditBox(frame, 44)
maxLevelEdit:SetPoint("LEFT", maxLevelLabel, "RIGHT", 6, 0)
maxLevelEdit:SetNumeric(true)
maxLevelEdit:SetText("0")

local maxLevelToggle = addon.CreateCheckButton(frame, "")
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

local scrollFrame = CreateFrame("ScrollFrame", "ISSearchScroll", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 12, -80)
scrollFrame:SetPoint("BOTTOMRIGHT", -28, 12)
frame:HookScript("OnMouseDown", clearMaxLevelEditFocus)
scrollFrame:HookScript("OnMouseDown", clearMaxLevelEditFocus)
local SCROLL_PADDING = 16

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetWidth(WIDTH - 40)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetPoint("RIGHT", -SCROLL_PADDING - 4, 0)

local rows = {}
for rowIndex = 1, MAX_ROWS do
	local row = CreateFrame("Frame", nil, scrollChild)
	row:SetSize(scrollChild:GetWidth() - SCROLL_PADDING, ROW_HEIGHT)
	row:EnableMouse(true)
	if rowIndex == 1 then
		row:SetPoint("TOPLEFT")
	else
		row:SetPoint("TOPLEFT", rows[rowIndex - 1], "BOTTOMLEFT")
	end

	row.scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.scoreText:SetWidth(100)
	row.scoreText:SetJustifyH("LEFT")
	row.scoreText:SetPoint("LEFT", 2, 0)

	row.itemLink = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.itemLink:SetPoint("LEFT", row.scoreText, "RIGHT", 4, 0)
	row.itemLink:SetWidth(230)
	row.itemLink:SetJustifyH("LEFT")

	row.dungeonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.dungeonText:SetPoint("LEFT", row.itemLink, "RIGHT", 4, 0)
	row.dungeonText:SetWidth(210)
	row.dungeonText:SetJustifyH("LEFT")

	row.bossText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.bossText:SetPoint("LEFT", row.dungeonText, "RIGHT", 4, 0)
	row.bossText:SetWidth(220)
	row.bossText:SetJustifyH("LEFT")

	row:SetScript("OnEnter", function(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(self.link)
		if type(self.sources) == "table" and #self.sources > 1 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Known Sources", 0.9, 0.9, 0.9)
			local maxSources = math.min(#self.sources, 8)
			for i = 1, maxSources do
				local sourceData = self.sources[i]
				local line = string.format("%s - %s", sourceData.place or "Unknown Place", sourceData.source or "Unknown Source")
				GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
			end
			if #self.sources > maxSources then
				GameTooltip:AddLine(string.format("+%d more", #self.sources - maxSources), 0.6, 0.6, 0.6)
			end
		end
		GameTooltip:Show()
	end)

	row:SetScript("OnLeave", function()
		if GameTooltip:IsShown() then GameTooltip:Hide() end
	end)
	row:SetScript("OnMouseDown", clearMaxLevelEditFocus)

	rows[rowIndex] = row
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
				row.scoreText:SetText("")
				row.itemLink:SetText("|cff00ff00" .. rowData.label .. "|r")
				row.dungeonText:SetText("")
				row.bossText:SetText("")
				row.link = nil
				row.sources = nil
			else
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
				row.itemLink:SetText(color .. (select(2, GetItemInfo(rowData.raw)) or ("[" .. rowData.name .. "]")) .. "|r")
				row.dungeonText:SetText(rowData.dungeon or "")
				row.bossText:SetText(rowData.sourceText or "")
				row.link = rowData.link
				row.sources = rowData.sources
			end
			row:Show()
		else
			row.scoreText:SetText("")
			row.itemLink:SetText("")
			row.dungeonText:SetText("")
			row.bossText:SetText("")
			row.link = nil
			row.sources = nil
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
	if status.updating and status.itemCount == 0 then
		return "Building search cache in background. Try again shortly."
	end
	if status.enabledProviderCount == 0 then
		return "No search data source enabled. Enable them in Interface -> AddOns -> ItemScore -> Loot Sources (or use /is lootcollector on, /is atlas on)."
	end
	if status.availableProviderCount == 0 then
		return "No supported source addon loaded (LootCollector / AtlasLoot)."
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
local searchWorker = CreateFrame("Frame")

local function resetSearchButton()
	searchBtn:SetText("Search")
	searchBtn:Enable()
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

		local raw = "item:" .. itemID .. ":::::::::"
		local name, link, rarity, _, requiredLevel, itemType, subType, _, invType, icon = GetItemInfo(raw)
		if not name then
			ItemScoreQuery.Add(itemID)
			state.missingItemInfo = true
		else
			local reqLevel = tonumber(requiredLevel) or 0
			local blockedByArmorType = false
			if state.hasArmorTypeFilter and type(addon.NormalizeArmorType) == "function" then
				local armorTypeKey = addon.NormalizeArmorType(itemType, subType)
				if armorTypeKey and not isArmorTypeFilterExemptSlot(invType) and not state.armorTypeFilter[armorTypeKey] then
					blockedByArmorType = true
				end
			end

			local blockedByWeaponType = false
			if state.hasWeaponTypeFilter and type(addon.IsWeaponTypeFilterRelevant) == "function" and addon.IsWeaponTypeFilterRelevant(itemType, invType) then
				local weaponTypeKey = nil
				if type(addon.NormalizeWeaponType) == "function" then
					weaponTypeKey = addon.NormalizeWeaponType(itemType, subType, invType)
				end
				if not weaponTypeKey or not state.weaponTypeFilter[weaponTypeKey] then
					blockedByWeaponType = true
				end
			end

			if not blockedByArmorType and not blockedByWeaponType and not (state.maxRequiredLevel > 0 and reqLevel > state.maxRequiredLevel) then
				local itemLink = link or raw
				if addon.CanPlayerEquip(itemLink) then
					local score = addon.CalculateScore(itemLink, state.profileName)
					if score and score >= 5 then
						local sources = state.itemSources[itemID] or {}
						local rowData = makeRowData(itemID, raw, itemLink, rarity, name, icon, score, sources)

						if state.isUpgradeSearch then
							if addon.IsUpgrade(itemLink, state.profileName) then
								for _, slotState in ipairs(state.upgradeSlotStates) do
									if belongsToSlot(invType, slotState.inv) then
										insertTop(slotState.results, rowData, LIST_UPGRADES_MAX)
									end
								end
							end
						elseif belongsToSlot(invType, state.slotInvTypes) then
							insertTop(state.results, rowData, LIST_SLOT_MAX)
						end
					end
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
	if ItemScoreQuery.IsBusy() then
		if #rowsData > 0 then
			refreshRows(rowsData)
		else
			refreshRows({
				{ isHeader = true, label = "Fetching item info. Results will update shortly." },
			})
		end
		searchBtn:SetText("Fetching...")
		searchBtn:Disable()
		ItemScoreQuery.RegisterDone(function()
			if frame:IsShown() then
				Search.DoSearch()
			end
		end)
		return
	end

	resetSearchButton()
	if #rowsData == 0 then
		refreshRows({
			{ isHeader = true, label = state.missingItemInfo and "No data found (some item info unavailable)." or "No data found" },
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
		total = #((catalog and catalog.itemIDs) or {}),
		index = 1,
		missingItemInfo = false,
		opsBudget = 220,
		targetMs = 5,
		maxRequiredLevel = maxRequiredLevel,
		hasArmorTypeFilter = hasArmorTypeFilter,
		armorTypeFilter = armorTypeFilter,
		hasWeaponTypeFilter = hasWeaponTypeFilter,
		weaponTypeFilter = weaponTypeFilter,
		results = {},
		isUpgradeSearch = slotLabel == "Upgrades",
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

	if ItemScoreQuery.IsBusy() then
		searchBtn:SetText("Fetching...")
		searchBtn:Disable()
		ItemScoreQuery.RegisterDone(function()
			if frame:IsShown() then
				doSearch()
			end
		end)
		return
	end

	if not selectedProfile or not selectedSlot then return end

	local catalog, cacheStatus = getCatalogAndStatus()
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
		if status.currentProvider then
			print("ItemScore: currently processing provider: " .. tostring(status.currentProvider))
		end
		if status.lastError then
			print("ItemScore: last cache error: " .. status.lastError)
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
