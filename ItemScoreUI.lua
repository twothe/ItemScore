local addonName, addon = ...
local U = addon

--------------------------------------------------
-- Constants
--------------------------------------------------
local HEADER_HEIGHT = 24

local function setButtonEnabled(btn, enabled)
	if btn.SetEnabled then
		btn:SetEnabled(enabled)
	else
		if enabled then btn:Enable() else btn:Disable() end
	end
end

-- Creates a restrained visual group for dense legacy Interface Options panels.
local function createOptionsGroup(parent)
	local group = CreateFrame("Frame", nil, parent)
	group:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 10,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	group:SetBackdropColor(0.035, 0.038, 0.045, 0.72)
	group:SetBackdropBorderColor(0.34, 0.29, 0.20, 0.9)
	return group
end

-- Programmatic SetText calls can retain a stale horizontal viewport on this
-- legacy client. Resetting the cursor exposes the beginning of the value.
local function setEditBoxText(editBox, value)
	editBox:SetText(value)
	if editBox.SetCursorPosition then
		editBox:SetCursorPosition(0)
	end
end

local HEADER_Y_GAP = 4
local STAT_FIELD_HEIGHT = 24
local STATS_LEFT_PAD = 16
local STAT_FIRST_COL_X = STATS_LEFT_PAD
local STAT_SECOND_COL_X = STATS_LEFT_PAD + 240
local DUNGEON_MAX_MYTHIC_LEVEL_FALLBACK = 40
local SOURCE_ROW_HEIGHT = 22
local SOURCE_LIST_INSET = 8

local STAT_LABEL_OVERRIDES = {
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Weapon DPS",
}

local STAT_GROUPS = {{
	label = "Primary Attributes",
	keys = {"ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ARMOR"}
}, {
	label = "Power",
	keys = {"ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"}
	}, {
		label = "Ratings",
		keys = {"ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_EXPERTISE_RATING_SHORT", "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", "ITEM_MOD_SPELL_PENETRATION_SHORT", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
			"ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT", "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT", "ITEM_MOD_RESILIENCE_RATING_SHORT"}
	}, {
		label = "Resistances",
		keys = {"RESISTANCE1_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME", "RESISTANCE4_NAME", "RESISTANCE5_NAME", "RESISTANCE6_NAME"}
	}}

local function statLabel(statKey)
	return STAT_LABEL_OVERRIDES[statKey] or _G[statKey] or statKey
end

--------------------------------------------------
-- Popup Manager
--------------------------------------------------
local function showAddProfilePopup(refreshCallback)
	StaticPopupDialogs["IS_ADD_PROFILE"] = {
		text = "Enter new profile name:",
		button1 = ACCEPT,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox = true,
		maxLetters = 12,
		OnAccept = function(pop)
            local name = pop.editBox:GetText()
            if name and name ~= "" then
                if addon.AddProfile(name) then
                    refreshCallback()
                end
            end
        end,
        EditBoxOnEnterPressed = function(self_)
            local parent = self_:GetParent()
            StaticPopupDialogs["IS_ADD_PROFILE"].OnAccept(parent)
            parent:Hide()
        end
	}
	StaticPopup_Show("IS_ADD_PROFILE")
end

local function showDeleteProfilePopup(profileName, refreshCallback)
	StaticPopupDialogs["IS_DEL_PROFILE"] = {
		text = "Delete profile '" .. profileName .. "'?",
		button1 = YES,
		button2 = NO,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnAccept = function()
			addon.DeleteProfile(profileName)
			refreshCallback()
		end
	}
	StaticPopup_Show("IS_DEL_PROFILE")
end

--------------------------------------------------
-- ProfileComponent
--------------------------------------------------
local ProfileComponent = {}
ProfileComponent.__index = ProfileComponent

function ProfileComponent:Create(parent, profileName, controller)
	local self = setmetatable({}, ProfileComponent)
	self.parentController = controller
	self.profileName = profileName
	self.profileData = addon.GetProfileData(profileName)
	self.root = CreateFrame("Frame", nil, parent)
	self.root:SetWidth(parent:GetWidth() or 580)
	self.root:Show()

	self:buildHeader()
	self:buildStats()
	self:refresh()
	return self
end

function ProfileComponent:buildHeader()
	local f = self.root
	local nameWidth = 160

	self.enable = U.CreateCheckButton(f, self.profileName)
	if self.enable.text then self.enable.text:SetWidth(nameWidth) end
	self.enable:SetPoint("TOPLEFT", 0, 0)
	self.enable:SetScript("OnClick", function() addon.ToggleProfileEnabled(self.profileName) end)

	self.toggle = U.CreateButton(f, HEADER_HEIGHT, HEADER_HEIGHT, "-")
	self.toggle:SetPoint("LEFT", self.enable.text, "RIGHT", 4, 0)
	self.toggle:SetScript("OnClick", function()
		addon.ToggleProfileCollapsed(self.profileName)
		self:refresh()
		self.parentController:layout()
	end)

	self.up = U.CreateButton(f, nil, nil, nil, "UIPanelScrollUpButtonTemplate")
	self.up:SetPoint("LEFT", self.toggle, "RIGHT", 4, 0)
	self.up:SetScript("OnClick", function()
		addon.MoveProfile(self.profileName, -1);
		self.parentController:refreshAll(true)
	end)

	self.down = U.CreateButton(f, nil, nil, nil, "UIPanelScrollDownButtonTemplate")
	self.down:SetPoint("LEFT", self.up, "RIGHT", 4, 0)
	self.down:SetScript("OnClick", function()
		addon.MoveProfile(self.profileName, 1);
		self.parentController:refreshAll(true)
	end)

	self.delete = U.CreateButton(f, 50, HEADER_HEIGHT, "Delete")
	self.delete:SetPoint("LEFT", self.down, "RIGHT", 4, 0)
	self.delete:SetScript("OnClick", function() showDeleteProfilePopup(self.profileName, function() self.parentController:refreshAll() end) end)
end

function ProfileComponent:buildStats()
	self.statsFrame = CreateFrame("Frame", nil, self.root)
	if DEBUG_BACKDROP then
		self.statsFrame:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background"
		})
		self.statsFrame:SetBackdropColor(0, 1, 0, 0.3)
	end
	self.statsFrame:SetPoint("TOPLEFT", self.root, "TOPLEFT", 0, -HEADER_HEIGHT - 9)
	self.statsFrame:SetPoint("RIGHT", self.root, "RIGHT", -STATS_LEFT_PAD, 0)
	self.statsFrame:SetWidth(self.root:GetWidth())

	local y = 0
	self.fields = {}
	self.armorTypeChecks = {}
	self.weaponTypeChecks = {}
	for _, group in ipairs(STAT_GROUPS) do
		local groupLabel = self.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		groupLabel:SetPoint("TOPLEFT", STAT_FIRST_COL_X, y)
		groupLabel:SetText(group.label)
		groupLabel:Show()
		y = y - 18

		local col = 0
		for _, key in ipairs(group.keys) do
			local container = CreateFrame("Frame", nil, self.statsFrame)
			container:SetSize(220, STAT_FIELD_HEIGHT)
			container:SetPoint("TOPLEFT", (col == 0) and STAT_FIRST_COL_X or STAT_SECOND_COL_X, y)
			container:Show()

			local edit = U.CreateEditBox(container, 90)
			edit:SetPoint("LEFT", 0, 0)
			edit:SetScript("OnTextChanged", function(box) if box:IsVisible() and box:HasFocus() then addon.SetWeight(self.profileName, key, tonumber(box:GetText())) end end)
			edit:SetScript("OnShow", function(box)
				local current = box:GetText()
				setEditBoxText(box, current)
			end)

			local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			lbl:SetPoint("LEFT", edit, "RIGHT", 6, 0)
			lbl:SetWidth(120)
			lbl:SetJustifyH("LEFT")
			lbl:SetText(statLabel(key))

			edit:Show()
			lbl:Show()
			container.edit = edit;
			container.statKey = key
			container:Show()
			table.insert(self.fields, container)

			col = 1 - col
			if col == 0 then y = y - STAT_FIELD_HEIGHT end
		end
		if col == 1 then y = y - STAT_FIELD_HEIGHT end
		y = y - 6
	end

	local armorTypeOptions = {}
	if type(addon.GetArmorTypeOptions) == "function" then
		armorTypeOptions = addon.GetArmorTypeOptions()
	end

	if #armorTypeOptions > 0 then
		local armorTypeLabel = self.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		armorTypeLabel:SetPoint("TOPLEFT", STAT_FIRST_COL_X, y)
		armorTypeLabel:SetText("Search Armor Type Filter")
		armorTypeLabel:Show()
		y = y - 18

		local col = 0
		for _, option in ipairs(armorTypeOptions) do
			local container = CreateFrame("Frame", nil, self.statsFrame)
			container:SetSize(220, STAT_FIELD_HEIGHT)
			container:SetPoint("TOPLEFT", (col == 0) and STAT_FIRST_COL_X or STAT_SECOND_COL_X, y)
			container:Show()

			local check = U.CreateCheckButton(container, option.label)
			check:SetPoint("LEFT", 0, 0)
			check:SetScript("OnClick", function(btn)
				addon.SetProfileArmorTypeEnabled(self.profileName, option.key, btn:GetChecked())
			end)
			check:Show()

			container.checkbox = check
			container.armorTypeKey = option.key
			self.armorTypeChecks[#self.armorTypeChecks + 1] = container

			col = 1 - col
			if col == 0 then y = y - STAT_FIELD_HEIGHT end
		end
		if col == 1 then y = y - STAT_FIELD_HEIGHT end

		local armorTypeHint = self.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		armorTypeHint:SetPoint("TOPLEFT", STAT_FIRST_COL_X, y)
		armorTypeHint:SetText("None selected = do not filter armor types in search")
		armorTypeHint:Show()
		y = y - 18
	end

	local weaponTypeOptions = {}
	if type(addon.GetWeaponTypeOptions) == "function" then
		weaponTypeOptions = addon.GetWeaponTypeOptions()
	end

	if #weaponTypeOptions > 0 then
		local weaponTypeLabel = self.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		weaponTypeLabel:SetPoint("TOPLEFT", STAT_FIRST_COL_X, y)
		weaponTypeLabel:SetText("Search Weapon Type Filter")
		weaponTypeLabel:Show()
		y = y - 18

		local col = 0
		for _, option in ipairs(weaponTypeOptions) do
			local container = CreateFrame("Frame", nil, self.statsFrame)
			container:SetSize(220, STAT_FIELD_HEIGHT)
			container:SetPoint("TOPLEFT", (col == 0) and STAT_FIRST_COL_X or STAT_SECOND_COL_X, y)
			container:Show()

			local check = U.CreateCheckButton(container, option.label)
			check:SetPoint("LEFT", 0, 0)
			check:SetScript("OnClick", function(btn)
				addon.SetProfileWeaponTypeEnabled(self.profileName, option.key, btn:GetChecked())
			end)
			check:Show()

			container.checkbox = check
			container.weaponTypeKey = option.key
			self.weaponTypeChecks[#self.weaponTypeChecks + 1] = container

			col = 1 - col
			if col == 0 then y = y - STAT_FIELD_HEIGHT end
		end
		if col == 1 then y = y - STAT_FIELD_HEIGHT end

		local weaponTypeHint = self.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		weaponTypeHint:SetPoint("TOPLEFT", STAT_FIRST_COL_X, y)
		weaponTypeHint:SetText("None selected = do not filter weapon types in search")
		weaponTypeHint:Show()
		y = y - 18
	end

	local statsHeight = -y
	self.statsFrame:SetHeight(statsHeight)
	self.totalHeight = statsHeight + HEADER_HEIGHT

	-- populate default values once immediately after construction
	for _, field in ipairs(self.fields) do
		local v = self.profileData and self.profileData.weights[field.statKey]
		if v then
			setEditBoxText(field.edit, tostring(v))
		else
			setEditBoxText(field.edit, "")
		end
		field.edit:ClearFocus()
	end

	local armorFilter = (self.profileData and self.profileData.armorTypeFilter) or {}
	for _, armorTypeContainer in ipairs(self.armorTypeChecks or {}) do
		local checked = armorFilter[armorTypeContainer.armorTypeKey] and true or false
		armorTypeContainer.checkbox:SetChecked(checked)
	end

	local weaponFilter = (self.profileData and self.profileData.weaponTypeFilter) or {}
	for _, weaponTypeContainer in ipairs(self.weaponTypeChecks or {}) do
		local checked = weaponFilter[weaponTypeContainer.weaponTypeKey] and true or false
		weaponTypeContainer.checkbox:SetChecked(checked)
	end
end

function ProfileComponent:refresh()
	self.profileData = addon.GetProfileData(self.profileName)
	self.enable:SetChecked(self.profileData.enabled)
	self.toggle:SetText(self.profileData.collapsed and "+" or "-")

	local order = addon.GetProfiles()
	setButtonEnabled(self.up, order[1] ~= self.profileName)
    setButtonEnabled(self.down, order[#order] ~= self.profileName)

	if self.profileData.collapsed then
		self.statsFrame:Hide()
		self.totalHeight = HEADER_HEIGHT
		self.root:SetHeight(HEADER_HEIGHT)
	else
		for _, field in ipairs(self.fields) do
			local v = self.profileData.weights[field.statKey]
			local txt = v and tostring(v) or ""
			setEditBoxText(field.edit, txt)
			field.edit:ClearFocus()
		end
		local armorFilter = self.profileData.armorTypeFilter or {}
		for _, armorTypeContainer in ipairs(self.armorTypeChecks or {}) do
			local checked = armorFilter[armorTypeContainer.armorTypeKey] and true or false
			armorTypeContainer.checkbox:SetChecked(checked)
		end
		local weaponFilter = self.profileData.weaponTypeFilter or {}
		for _, weaponTypeContainer in ipairs(self.weaponTypeChecks or {}) do
			local checked = weaponFilter[weaponTypeContainer.weaponTypeKey] and true or false
			weaponTypeContainer.checkbox:SetChecked(checked)
		end
		self.statsFrame:Show()
		local newHeight = self.statsFrame:GetHeight() + HEADER_HEIGHT
		self.totalHeight = newHeight
		self.root:SetHeight(newHeight)
	end
end

--------------------------------------------------
-- Options Panels
--------------------------------------------------

local RootPanel = CreateFrame("Frame", "ItemScoreRootOptionsFrame", InterfaceOptionsFramePanelContainer or UIParent)
RootPanel.name = "ItemScore"

RootPanel:SetScript("OnShow", function(self)
	if self.initialized then return end
	self.initialized = true

	local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("ItemScore")

	local text = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetJustifyH("LEFT")
	text:SetText("Use the two pages below:\n- Scores: profile weights\n- Loot Sources: search data providers and filters")
end)

InterfaceOptions_AddCategory(RootPanel)

local ScorePanel = CreateFrame("Frame", "ItemScoreOptionsFrame", InterfaceOptionsFramePanelContainer or UIParent)
ScorePanel.name = "Scores"
ScorePanel.parent = "ItemScore"

local scroll = CreateFrame("ScrollFrame", "ISScroll", ScorePanel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 16, -48)
scroll:SetPoint("BOTTOMRIGHT", -30, 16)

local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetWidth(580)
scroll:SetScrollChild(scrollChild)

ScorePanel.components = {}
ScorePanel.componentPool = {}
ScorePanel.refreshing = false
ScorePanel.pendingRefresh = false

function ScorePanel:refreshAll()
	if self.refreshing then return end
	self.refreshing = true

	local activeComponents = {}
	local ordered = addon.GetProfiles()
	for _, name in ipairs(ordered) do
		local comp = self.componentPool[name]
		if comp then
			comp:refresh()
		else
			comp = ProfileComponent:Create(scrollChild, name, self)
			self.componentPool[name] = comp
		end
		comp.root:Show()
		activeComponents[name] = comp
	end
	for name, comp in pairs(self.componentPool) do
		if not activeComponents[name] then
			comp.root:Hide()
		end
	end
	self.components = activeComponents
	self:layout()
	self.refreshing = false
end

local function refreshEditBoxViewports(panel)
	for _, comp in pairs(panel.components) do
		for _, field in ipairs(comp.fields or {}) do
			local txt = field.edit:GetText()
			setEditBoxText(field.edit, txt)
		end
	end
end

function ScorePanel:layout()
	local ordered = addon.GetProfiles()
	local y = 0
	for index, name in ipairs(ordered) do
		local comp = self.components[name]
		comp.root:ClearAllPoints()
		comp.root:SetPoint("TOPLEFT", 0, y)
		y = y - (comp.totalHeight or comp.root:GetHeight()) - HEADER_Y_GAP
	end
	scrollChild:SetHeight(-y)
	scroll:UpdateScrollChildRect()
	refreshEditBoxViewports(self)
end

ScorePanel:SetScript("OnShow", function(self)
	if self.initialized then
		self:refreshAll();
		return
	end
	self.initialized = true

	local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("ItemScore Profiles")

	local addBtn = U.CreateButton(self, 100, HEADER_HEIGHT, "Add Profile")
	addBtn:SetPoint("TOPRIGHT", -16, -16)
	addBtn:SetScript("OnClick", function() showAddProfilePopup(function() ScorePanel:refreshAll() end) end)

	self:refreshAll()
end)

InterfaceOptions_AddCategory(ScorePanel)

local SourcesPanel = CreateFrame("Frame", "ItemScoreSourcesOptionsFrame", InterfaceOptionsFramePanelContainer or UIParent)
SourcesPanel.name = "Loot Sources"
SourcesPanel.parent = "ItemScore"

local function getSourceSettings()
	if type(addon.GetSearchSourceSettings) == "function" then
		return addon.GetSearchSourceSettings()
	end
	return {}
end

local function getSourceStatus()
	if type(addon.GetSearchCacheStatus) == "function" then
		return addon.GetSearchCacheStatus()
	end
	return {
		itemCount = 0,
		stale = true,
		updating = false,
		enabledProviderCount = 0,
		availableProviderCount = 0,
	}
end

local function setSourceOption(optionKey, value, skipRefreshQueue)
	if type(addon.SetSearchSourceOption) ~= "function" then
		print("|cffff7f00ItemScore:|r source manager unavailable.")
		return false
	end
	local changed = addon.SetSearchSourceOption(optionKey, value)
	if changed and not skipRefreshQueue and optionKey ~= "searchMaxRequiredLevel" and type(addon.QueueSearchCacheRefresh) == "function" then
		addon.QueueSearchCacheRefresh("options:" .. optionKey)
	end
	return changed
end

local function setAtlasRaidEnabled(raidName, enabled)
	if type(addon.SetAtlasLootRaidEnabled) ~= "function" then
		print("|cffff7f00ItemScore:|r source manager unavailable.")
		return false
	end
	local changed = addon.SetAtlasLootRaidEnabled(raidName, enabled and true or false)
	if changed and type(addon.QueueSearchCacheRefresh) == "function" then
		addon.QueueSearchCacheRefresh("options:raid:" .. tostring(raidName))
	end
	return changed
end

local function setAtlasFactionEnabled(factionName, enabled)
	if type(addon.SetAtlasLootFactionEnabled) ~= "function" then
		print("|cffff7f00ItemScore:|r source manager unavailable.")
		return false
	end
	local changed = addon.SetAtlasLootFactionEnabled(factionName, enabled and true or false)
	if changed and type(addon.QueueSearchCacheRefresh) == "function" then
		addon.QueueSearchCacheRefresh("options:faction:" .. tostring(factionName))
	end
	return changed
end

local function setAtlasCraftingEnabled(expansionKey, sourceName, enabled)
	if type(addon.SetAtlasLootCraftingEnabled) ~= "function" then
		print("|cffff7f00ItemScore:|r source manager unavailable.")
		return false
	end
	local changed = addon.SetAtlasLootCraftingEnabled(expansionKey, sourceName, enabled and true or false)
	if changed and type(addon.QueueSearchCacheRefresh) == "function" then
		addon.QueueSearchCacheRefresh("options:crafting:" .. tostring(expansionKey) .. ":" .. tostring(sourceName))
	end
	return changed
end

local function setAllAtlasSourcesEnabled(enabled)
	local changed = false
	if type(addon.SetAllAtlasLootRaidsEnabled) == "function" then
		changed = addon.SetAllAtlasLootRaidsEnabled(enabled and true or false) or changed
	end
	if type(addon.SetAllAtlasLootFactionsEnabled) == "function" then
		changed = addon.SetAllAtlasLootFactionsEnabled(enabled and true or false) or changed
	end
	if type(addon.SetAllAtlasLootCraftingEnabled) == "function" then
		changed = addon.SetAllAtlasLootCraftingEnabled(enabled and true or false) or changed
	end
	if changed and type(addon.QueueSearchCacheRefresh) == "function" then
		addon.QueueSearchCacheRefresh("options:atlas_sources_all")
	end
	return changed
end

local function setCheckIfExists(checkButton, value)
	if checkButton then
		checkButton:SetChecked(value and true or false)
	end
end

local refreshSourcesPanel

local function groupEnabledByExpansion(settings, expansionKey)
	if expansionKey == "classic" then return settings.atlasClassic end
	if expansionKey == "tbc" then return settings.atlasTBC end
	if expansionKey == "wrath" then return settings.atlasWrath end
	return false
end

local function getSelectableSourceChoices()
	local getChoices = addon.GetAtlasLootSourceChoices or addon.GetAtlasLootRaidChoices
	if type(getChoices) ~= "function" then
		return {}
	end
	local choices = getChoices()
	if type(choices) ~= "table" then return {} end
	return choices
end

local function getAtlasDungeonMaxMythicLevel()
	if type(addon.GetAtlasLootMaxDungeonMythicLevel) ~= "function" then
		return DUNGEON_MAX_MYTHIC_LEVEL_FALLBACK
	end
	local maxLevel = math.floor(tonumber(addon.GetAtlasLootMaxDungeonMythicLevel()) or DUNGEON_MAX_MYTHIC_LEVEL_FALLBACK)
	if maxLevel < 0 then maxLevel = 0 end
	return maxLevel
end

local function getRaidDifficultyChoices()
	if type(addon.GetAtlasLootRaidDifficultyChoices) == "function" then
		local choices = addon.GetAtlasLootRaidDifficultyChoices()
		if type(choices) == "table" and #choices > 0 then
			return choices
		end
	end
	return {
		{ value = 3, label = "Normal" },
		{ value = 4, label = "Heroic" },
		{ value = 5, label = "Mythic" },
		{ value = 6, label = "Ascended" },
	}
end

local function getRaidDifficultyLabel(value)
	local numeric = tonumber(value) or 5
	for _, choice in ipairs(getRaidDifficultyChoices()) do
		if tonumber(choice.value) == numeric then
			return choice.label
		end
	end
	return "Mythic"
end

local function normalizeDungeonMaxMythicLevelInput(value, allowBlank)
	if allowBlank and tostring(value or "") == "" then return nil end
	local numeric = math.floor(tonumber(value) or 0)
	if numeric < 0 then numeric = 0 end
	return numeric
end

-- Synchronizes the persisted cap unless the player is actively editing a draft.
-- A newly created edit box can briefly own focus before SetAutoFocus(false)
-- takes effect, which must not suppress its initial SavedVariables value.
local function syncDungeonMaxMythicLevelField(panel, settings, force)
	if not panel or not panel.dungeonMaxMythicEdit then return false end
	if not force and panel.dungeonMaxMythicEdit:HasFocus() and panel.dungeonMaxMythicDirty then
		return false
	end

	local value = normalizeDungeonMaxMythicLevelInput(settings and settings.atlasDungeonMaxMythicLevel)
	panel.dungeonMaxMythicSyncing = true
	setEditBoxText(panel.dungeonMaxMythicEdit, tostring(value))
	panel.dungeonMaxMythicSyncing = false
	panel.dungeonMaxMythicValueLoaded = true
	panel.dungeonMaxMythicDirty = false
	return true
end

-- Restores the text viewport after enable-state changes. The value can remain
-- intact while its horizontal scroll position leaves every digit off-screen.
local function refreshDungeonMaxMythicLevelAppearance(panel, enabled)
	if not panel or not panel.dungeonMaxMythicEdit then return end

	local editBox = panel.dungeonMaxMythicEdit
	local currentText = editBox:GetText()
	local wasSyncing = panel.dungeonMaxMythicSyncing
	panel.dungeonMaxMythicSyncing = true
	setEditBoxText(editBox, currentText)
	panel.dungeonMaxMythicSyncing = wasSyncing
	if editBox.SetTextColor then
		local color = enabled and 1 or 0.5
		editBox:SetTextColor(color, color, color, 1)
	end
end

local function commitDungeonMaxMythicLevel(panel, skipPanelRefresh, skipRefreshQueue)
	if not panel or not panel.dungeonMaxMythicEdit then return end
	if not panel.dungeonMaxMythicValueLoaded and not panel.dungeonMaxMythicDirty and not panel.dungeonMaxMythicEdit:HasFocus() then
		return
	end
	local value = normalizeDungeonMaxMythicLevelInput(panel.dungeonMaxMythicEdit:GetText(), true)
	if value == nil then
		local settings = getSourceSettings()
		syncDungeonMaxMythicLevelField(panel, settings, true)
		if not skipPanelRefresh then
			refreshSourcesPanel(panel)
		end
		return
	end
	setEditBoxText(panel.dungeonMaxMythicEdit, tostring(value))
	panel.dungeonMaxMythicValueLoaded = true
	panel.dungeonMaxMythicDirty = false
	setSourceOption("atlasDungeonMaxMythicLevel", value, skipRefreshQueue)
	if not skipPanelRefresh then
		refreshSourcesPanel(panel)
	end
end

local function saveDungeonMaxMythicLevelDraft(panel, text)
	if not panel then return end
	panel.dungeonMaxMythicDirty = true
	local value = normalizeDungeonMaxMythicLevelInput(text, true)
	if value ~= nil then
		panel.dungeonMaxMythicValueLoaded = true
		setSourceOption("atlasDungeonMaxMythicLevel", value, false)
	end
end

local function buildSourceEntries(sourceChoices)
	local entries = {}
	for _, group in ipairs(sourceChoices or {}) do
		local sections = {
			{ label = "Raids", choices = group.raids, kind = "raid" },
			{ label = "Tier Sets", choices = group.tierSets, kind = "tierSet" },
			{ label = "Reputation", choices = group.factions, kind = "faction" },
			{ label = "Crafting", choices = group.crafting, kind = "crafting" },
		}
		local hasChoices = false
		for _, section in ipairs(sections) do
			if type(section.choices) == "table" and #section.choices > 0 then
				hasChoices = true
				break
			end
		end
		if hasChoices then
			if #entries > 0 then
				entries[#entries + 1] = { kind = "spacer" }
			end
			entries[#entries + 1] = {
				kind = "expansion",
				label = group.label or tostring(group.key or "Expansion"),
				expansionKey = group.key,
			}
			for _, section in ipairs(sections) do
				if type(section.choices) == "table" and #section.choices > 0 then
					entries[#entries + 1] = {
						kind = "section",
						label = section.label,
						expansionKey = group.key,
					}
					for _, sourceName in ipairs(section.choices) do
						entries[#entries + 1] = {
							kind = "choice",
							label = sourceName,
							sourceKind = section.kind,
							expansionKey = group.key,
						}
					end
				end
			end
		end
	end
	if #entries == 0 then
		entries[1] = {
			kind = "empty",
			label = "No selectable AtlasLoot sources available.",
		}
	end
	return entries
end

local function sourceVisibleRowCount(panel)
	local height = panel.sourceViewport and panel.sourceViewport:GetHeight() or 0
	return math.max(1, math.floor((height - (SOURCE_LIST_INSET * 2)) / SOURCE_ROW_HEIGHT))
end

local function scrollSourceListByWheel(panel, delta)
	if not panel.sourceScroll or not panel.sourceScroll.GetName then return end
	local scrollName = panel.sourceScroll:GetName()
	local scrollBar = scrollName and _G[scrollName .. "ScrollBar"]
	if not scrollBar or not scrollBar:IsShown() then return end
	local minimum, maximum = scrollBar:GetMinMaxValues()
	local target = scrollBar:GetValue() - ((tonumber(delta) or 0) * SOURCE_ROW_HEIGHT * 3)
	if target < minimum then target = minimum end
	if target > maximum then target = maximum end
	scrollBar:SetValue(target)
end

local function acquireSourceRow(panel, rowIndex)
	panel.sourceRows = panel.sourceRows or {}
	local row = panel.sourceRows[rowIndex]
	if row then return row end

	row = CreateFrame("Frame", nil, panel.sourceViewport)
	row:SetHeight(SOURCE_ROW_HEIGHT)
	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetTexture("Interface\\Buttons\\WHITE8X8")
	row.background:SetAllPoints(row)
	row.background:Hide()
	row.header = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.header:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.header:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.header:SetJustifyH("LEFT")
	if row.header.SetWordWrap then row.header:SetWordWrap(false) end
	row.check = U.CreateCheckButton(row, "")
	row.check:SetPoint("LEFT", row, "LEFT", 12, 0)
	row.check:SetScript("OnClick", function(btn)
		local entry = row.entry
		if not entry or entry.kind ~= "choice" then return end
		if entry.sourceKind == "faction" then
			setAtlasFactionEnabled(entry.label, btn:GetChecked())
		elseif entry.sourceKind == "crafting" then
			setAtlasCraftingEnabled(entry.expansionKey, entry.label, btn:GetChecked())
		else
			setAtlasRaidEnabled(entry.label, btn:GetChecked())
		end
		refreshSourcesPanel(panel)
	end)
	local wheelHandler = function(_, delta)
		scrollSourceListByWheel(panel, delta)
	end
	row:EnableMouseWheel(true)
	row:SetScript("OnMouseWheel", wheelHandler)
	row.check:EnableMouseWheel(true)
	row.check:SetScript("OnMouseWheel", wheelHandler)
	panel.sourceRows[rowIndex] = row
	return row
end

local function sourceChoiceDisabled(settings, entry)
	if entry.sourceKind == "faction" then
		return settings.atlasDisabledFactions and settings.atlasDisabledFactions[entry.label]
	end
	if entry.sourceKind == "crafting" then
		local disabledByExpansion = settings.atlasDisabledCrafting
		local disabledSources = type(disabledByExpansion) == "table" and disabledByExpansion[entry.expansionKey]
		return type(disabledSources) == "table" and disabledSources[entry.label]
	end
	return settings.atlasDisabledRaids and settings.atlasDisabledRaids[entry.label]
end

local function renderSourceRows(panel, settings)
	if not panel.sourceScroll or not panel.sourceViewport then return end
	local entries = panel.sourceEntries or {}
	local visibleRows = sourceVisibleRowCount(panel)
	FauxScrollFrame_Update(panel.sourceScroll, #entries, visibleRows, SOURCE_ROW_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(panel.sourceScroll)
	local textWidth = math.max(80, (panel.sourceViewport:GetWidth() or 400) - 78)

	for rowIndex = 1, visibleRows do
		local row = acquireSourceRow(panel, rowIndex)
		local entry = entries[offset + rowIndex]
		local rowTop = -SOURCE_LIST_INSET - ((rowIndex - 1) * SOURCE_ROW_HEIGHT)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel.sourceViewport, "TOPLEFT", SOURCE_LIST_INSET, rowTop)
		row:SetPoint("TOPRIGHT", panel.sourceViewport, "TOPRIGHT", -28, rowTop)
		row.entry = entry
		if not entry or entry.kind == "spacer" then
			row:Hide()
		elseif entry.kind == "choice" then
			row.background:Hide()
			row.header:Hide()
			row.check:Show()
			row.check:SetChecked(not sourceChoiceDisabled(settings, entry))
			if row.check.text then
				row.check.text:SetText(entry.label)
				row.check.text:SetWidth(textWidth)
				row.check.text:SetJustifyH("LEFT")
				if row.check.text.SetWordWrap then row.check.text:SetWordWrap(false) end
			end
			setButtonEnabled(row.check, settings.useAtlasLoot and groupEnabledByExpansion(settings, entry.expansionKey))
			row:Show()
		else
			row.check:Hide()
			row.header:Show()
			row.header:ClearAllPoints()
			row.header:SetPoint("LEFT", row, "LEFT", entry.kind == "section" and 14 or 6, 0)
			row.header:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			local label = entry.label
			if entry.kind == "expansion" and not groupEnabledByExpansion(settings, entry.expansionKey) then
				label = label .. " (disabled)"
			end
			row.header:SetText(label)
			if entry.kind == "expansion" then
				row.header:SetFontObject("GameFontNormal")
				if settings.useAtlasLoot and groupEnabledByExpansion(settings, entry.expansionKey) then
					row.header:SetTextColor(1, 0.82, 0)
				else
					row.header:SetTextColor(0.52, 0.52, 0.52)
				end
				row.background:SetVertexColor(0.18, 0.14, 0.06, 0.72)
				row.background:Show()
			elseif entry.kind == "section" then
				row.header:SetFontObject("GameFontHighlightSmall")
				if settings.useAtlasLoot and groupEnabledByExpansion(settings, entry.expansionKey) then
					row.header:SetTextColor(0.86, 0.78, 0.58)
				else
					row.header:SetTextColor(0.46, 0.46, 0.46)
				end
				row.background:Hide()
			else
				row.header:SetFontObject("GameFontHighlightSmall")
				row.header:SetTextColor(0.72, 0.72, 0.72)
				row.background:Hide()
			end
			row:Show()
		end
	end

	for rowIndex = visibleRows + 1, #(panel.sourceRows or {}) do
		panel.sourceRows[rowIndex]:Hide()
	end
end

local function rebuildSourceList(panel, settings)
	if not panel.sourceScroll then return end
	panel.sourceEntries = buildSourceEntries(getSelectableSourceChoices())
	renderSourceRows(panel, settings)
end

refreshSourcesPanel = function(panel)
	local settings = getSourceSettings()
	local status = getSourceStatus()

	setCheckIfExists(panel.useLootCollector, settings.useLootCollector)
	setCheckIfExists(panel.useAtlasLoot, settings.useAtlasLoot)
	setCheckIfExists(panel.worldforgedZG, settings.worldforgedZG)
	setCheckIfExists(panel.worldforgedMC, settings.worldforgedMC)
	setCheckIfExists(panel.worldforgedBWL, settings.worldforgedBWL)
	setCheckIfExists(panel.worldforgedNaxx, settings.worldforgedNaxx)
	setCheckIfExists(panel.atlasClassic, settings.atlasClassic)
	setCheckIfExists(panel.atlasTBC, settings.atlasTBC)
	setCheckIfExists(panel.atlasWrath, settings.atlasWrath)
	setCheckIfExists(panel.dungeonHighestMythicOnly, settings.atlasDungeonHighestMythicOnly ~= false)
	if panel.dungeonMaxMythicEdit then
		local availableMaxLevel = getAtlasDungeonMaxMythicLevel()
		syncDungeonMaxMythicLevelField(panel, settings, false)
		if panel.dungeonMaxMythicHint then
			panel.dungeonMaxMythicHint:SetText("0 = Mythic; available max " .. tostring(availableMaxLevel))
		end
	end
	if panel.raidMaxDifficultyDrop then
		UIDropDownMenu_SetSelectedValue(panel.raidMaxDifficultyDrop, settings.atlasRaidMaxDifficulty)
		UIDropDownMenu_SetText(panel.raidMaxDifficultyDrop, getRaidDifficultyLabel(settings.atlasRaidMaxDifficulty))
	end

	local atlasEnabled = settings.useAtlasLoot and true or false
	local lootCollectorEnabled = settings.useLootCollector and true or false
	setButtonEnabled(panel.worldforgedZG, lootCollectorEnabled)
	setButtonEnabled(panel.worldforgedMC, lootCollectorEnabled)
	setButtonEnabled(panel.worldforgedBWL, lootCollectorEnabled)
	setButtonEnabled(panel.worldforgedNaxx, lootCollectorEnabled)
	setButtonEnabled(panel.atlasClassic, atlasEnabled)
	setButtonEnabled(panel.atlasTBC, atlasEnabled)
	setButtonEnabled(panel.atlasWrath, atlasEnabled)
	setButtonEnabled(panel.dungeonHighestMythicOnly, atlasEnabled)
	setButtonEnabled(panel.enableAllSourcesBtn, atlasEnabled)
	setButtonEnabled(panel.disableAllSourcesBtn, atlasEnabled)
	setButtonEnabled(panel.dungeonMaxMythicEdit, atlasEnabled)
	refreshDungeonMaxMythicLevelAppearance(panel, atlasEnabled)
	if panel.raidMaxDifficultyDrop then
		if atlasEnabled and type(UIDropDownMenu_EnableDropDown) == "function" then
			UIDropDownMenu_EnableDropDown(panel.raidMaxDifficultyDrop)
		elseif not atlasEnabled and type(UIDropDownMenu_DisableDropDown) == "function" then
			UIDropDownMenu_DisableDropDown(panel.raidMaxDifficultyDrop)
		end
	end
	rebuildSourceList(panel, settings)

	local disabledCount = 0
	if type(addon.GetDisabledAtlasLootPlaces) == "function" then
		disabledCount = #(addon.GetDisabledAtlasLootPlaces() or {})
	end
	if status.updating then
		panel.statusText:SetText("Cache: updating...")
	else
		panel.statusText:SetText(string.format("Cache: %d items  |  Excluded areas: %d", status.itemCount or 0, disabledCount))
	end
end

SourcesPanel:SetScript("OnShow", function(self)
	if not self.initialized then
		self.initialized = true

		local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 16, -16)
		title:SetText("Loot Sources")

		self.lootCollectorGroup = createOptionsGroup(self)
		self.lootCollectorGroup:SetPoint("TOPLEFT", 16, -44)
		self.lootCollectorGroup:SetSize(300, 120)

		self.useLootCollector = U.CreateCheckButton(self.lootCollectorGroup, "LootCollector")
		self.useLootCollector:SetPoint("TOPLEFT", 10, -8)
		self.useLootCollector:SetScript("OnClick", function(btn)
			setSourceOption("useLootCollector", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		local wfLabel = self.lootCollectorGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		wfLabel:SetPoint("TOPLEFT", 32, -38)
		wfLabel:SetText("Worldforged tiers")

		self.worldforgedZG = U.CreateCheckButton(self.lootCollectorGroup, "Zul'Gurub")
		self.worldforgedZG:SetPoint("TOPLEFT", 30, -58)
		self.worldforgedZG:SetScript("OnClick", function(btn)
			setSourceOption("worldforgedZG", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.worldforgedMC = U.CreateCheckButton(self.lootCollectorGroup, "MC")
		self.worldforgedMC:SetPoint("TOPLEFT", 160, -58)
		self.worldforgedMC:SetScript("OnClick", function(btn)
			setSourceOption("worldforgedMC", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.worldforgedBWL = U.CreateCheckButton(self.lootCollectorGroup, "BWL")
		self.worldforgedBWL:SetPoint("TOPLEFT", 30, -84)
		self.worldforgedBWL:SetScript("OnClick", function(btn)
			setSourceOption("worldforgedBWL", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.worldforgedNaxx = U.CreateCheckButton(self.lootCollectorGroup, "Naxxramas")
		self.worldforgedNaxx:SetPoint("TOPLEFT", 160, -84)
		self.worldforgedNaxx:SetScript("OnClick", function(btn)
			setSourceOption("worldforgedNaxx", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.atlasGroup = createOptionsGroup(self)
		self.atlasGroup:SetPoint("TOPLEFT", 16, -176)
		self.atlasGroup:SetSize(300, 278)

		self.useAtlasLoot = U.CreateCheckButton(self.atlasGroup, "AtlasLoot")
		self.useAtlasLoot:SetPoint("TOPLEFT", 10, -8)
		self.useAtlasLoot:SetScript("OnClick", function(btn)
			setSourceOption("useAtlasLoot", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		local expLabel = self.atlasGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		expLabel:SetPoint("TOPLEFT", 32, -38)
		expLabel:SetText("Expansions")

		self.atlasClassic = U.CreateCheckButton(self.atlasGroup, "Classic")
		self.atlasClassic:SetPoint("TOPLEFT", 30, -58)
		self.atlasClassic:SetScript("OnClick", function(btn)
			setSourceOption("atlasClassic", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.atlasTBC = U.CreateCheckButton(self.atlasGroup, "Burning Crusade")
		self.atlasTBC:SetPoint("TOPLEFT", 30, -82)
		self.atlasTBC:SetScript("OnClick", function(btn)
			setSourceOption("atlasTBC", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.atlasWrath = U.CreateCheckButton(self.atlasGroup, "Wrath of the Lich King")
		self.atlasWrath:SetPoint("TOPLEFT", 30, -106)
		self.atlasWrath:SetScript("OnClick", function(btn)
			setSourceOption("atlasWrath", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.dungeonMaxMythicLabel = self.atlasGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		self.dungeonMaxMythicLabel:SetPoint("TOPLEFT", 30, -146)
		self.dungeonMaxMythicLabel:SetText("Dungeon Mythic+ cap")

		self.dungeonMaxMythicEdit = U.CreateEditBox(self.atlasGroup, 44)
		self.dungeonMaxMythicEdit:SetPoint("LEFT", self.dungeonMaxMythicLabel, "RIGHT", 10, 0)
		self.dungeonMaxMythicEdit:SetNumeric(true)
		syncDungeonMaxMythicLevelField(self, getSourceSettings(), true)
		self.dungeonMaxMythicEdit:ClearFocus()
		self.dungeonMaxMythicEdit:SetScript("OnEnterPressed", function(box)
			box:ClearFocus()
		end)
		self.dungeonMaxMythicEdit:SetScript("OnTextChanged", function(box)
			if not self.dungeonMaxMythicSyncing and box:IsVisible() and box:HasFocus() then
				saveDungeonMaxMythicLevelDraft(self, box:GetText())
			end
		end)
		self.dungeonMaxMythicEdit:SetScript("OnEditFocusLost", function()
			commitDungeonMaxMythicLevel(self)
		end)

		self.dungeonMaxMythicHint = self.atlasGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		self.dungeonMaxMythicHint:SetPoint("TOPLEFT", 30, -170)
		self.dungeonMaxMythicHint:SetText("0 = Mythic")

		self.dungeonHighestMythicOnly = U.CreateCheckButton(self.atlasGroup, "Only highest Mythic+ variant")
		self.dungeonHighestMythicOnly:SetPoint("TOPLEFT", 30, -190)
		self.dungeonHighestMythicOnly:SetScript("OnClick", function(btn)
			setSourceOption("atlasDungeonHighestMythicOnly", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		self.raidMaxDifficultyLabel = self.atlasGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		self.raidMaxDifficultyLabel:SetPoint("TOPLEFT", 30, -224)
		self.raidMaxDifficultyLabel:SetText("Raid difficulty cap")

		self.raidMaxDifficultyDrop = CreateFrame("Frame", "ISAtlasRaidDifficultyDD", self.atlasGroup, "UIDropDownMenuTemplate")
		self.raidMaxDifficultyDrop:SetPoint("LEFT", self.raidMaxDifficultyLabel, "RIGHT", -4, -3)
		UIDropDownMenu_Initialize(self.raidMaxDifficultyDrop, function()
			for _, choice in ipairs(getRaidDifficultyChoices()) do
				UIDropDownMenu_AddButton({
					text = choice.label,
					value = choice.value,
					func = function(button)
						setSourceOption("atlasRaidMaxDifficulty", button.value)
						refreshSourcesPanel(self)
					end,
				})
			end
		end)
		UIDropDownMenu_SetWidth(self.raidMaxDifficultyDrop, 100)

		self.cacheGroup = createOptionsGroup(self)
		self.cacheGroup:SetPoint("TOPLEFT", 16, -466)
		self.cacheGroup:SetSize(300, 70)

		self.refreshCacheBtn = U.CreateButton(self.cacheGroup, 126, HEADER_HEIGHT, "Refresh Cache")
		self.refreshCacheBtn:SetPoint("TOPLEFT", 10, -10)
		self.refreshCacheBtn:SetScript("OnClick", function()
			commitDungeonMaxMythicLevel(self, true, true)
			if type(addon.RefreshSearchCache) == "function" then
				local started, reason = addon.RefreshSearchCache(true, false)
				if not started and reason == "busy" and type(addon.QueueSearchCacheRefresh) == "function" then
					addon.QueueSearchCacheRefresh("options:manual_refresh_busy")
				end
			elseif type(addon.QueueSearchCacheRefresh) == "function" then
				addon.QueueSearchCacheRefresh("options:manual_refresh")
			else
				print("|cffff7f00ItemScore:|r source manager unavailable.")
			end
			refreshSourcesPanel(self)
		end)

		self.statusText = self.cacheGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		self.statusText:SetPoint("TOPLEFT", 10, -44)
		self.statusText:SetJustifyH("LEFT")

		self.sourceTitle = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		self.sourceTitle:SetPoint("TOPLEFT", 334, -48)
		self.sourceTitle:SetText("AtlasLoot Sources")

		self.sourceHint = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		self.sourceHint:SetPoint("TOPLEFT", 334, -70)
		self.sourceHint:SetText("Dungeons are automatic; other sources are selectable below.")

		self.enableAllSourcesBtn = U.CreateButton(self, 92, HEADER_HEIGHT, "Select All")
		self.enableAllSourcesBtn:SetPoint("TOPLEFT", 334, -88)
		self.enableAllSourcesBtn:SetScript("OnClick", function()
			setAllAtlasSourcesEnabled(true)
			refreshSourcesPanel(self)
		end)

		self.disableAllSourcesBtn = U.CreateButton(self, 92, HEADER_HEIGHT, "Clear All")
		self.disableAllSourcesBtn:SetPoint("LEFT", self.enableAllSourcesBtn, "RIGHT", 8, 0)
		self.disableAllSourcesBtn:SetScript("OnClick", function()
			setAllAtlasSourcesEnabled(false)
			refreshSourcesPanel(self)
		end)

		self.sourceViewport = createOptionsGroup(self)
		self.sourceViewport:SetPoint("TOPLEFT", 334, -120)
		self.sourceViewport:SetPoint("BOTTOMRIGHT", -16, 16)
		self.sourceViewport:EnableMouseWheel(true)
		self.sourceViewport:SetScript("OnMouseWheel", function(_, delta)
			scrollSourceListByWheel(self, delta)
		end)

		self.sourceScroll = CreateFrame("ScrollFrame", "ISAtlasSourceScroll", self.sourceViewport, "FauxScrollFrameTemplate")
		self.sourceScroll:SetPoint("TOPLEFT", 4, -4)
		self.sourceScroll:SetPoint("BOTTOMRIGHT", -26, 4)
		self.sourceScroll:SetScript("OnVerticalScroll", function(scrollFrame, offset)
			FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, SOURCE_ROW_HEIGHT, function()
				renderSourceRows(self, getSourceSettings())
			end)
		end)
		self.sourceRows = {}
		self.sourceViewport:SetScript("OnSizeChanged", function()
			if self.sourceEntries then
				renderSourceRows(self, getSourceSettings())
			end
		end)
	end

	refreshSourcesPanel(self)
end)

SourcesPanel.okay = function(self)
	commitDungeonMaxMythicLevel(self, true, false)
end

SourcesPanel:SetScript("OnHide", function(self)
	commitDungeonMaxMythicLevel(self, true, false)
end)

InterfaceOptions_AddCategory(SourcesPanel)

SLASH_ITEMSCORE1 = "/itemscore"
SlashCmdList["ITEMSCORE"] = function()
	InterfaceOptionsFrame_OpenToCategory(ScorePanel)
	InterfaceOptionsFrame_OpenToCategory(ScorePanel)
end
