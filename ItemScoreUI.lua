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
local HEADER_Y_GAP = 4
local STAT_FIELD_HEIGHT = 24
local STATS_LEFT_PAD = 16
local STAT_FIRST_COL_X = STATS_LEFT_PAD
local STAT_SECOND_COL_X = STATS_LEFT_PAD + 240

local STAT_GROUPS = {{
	label = "Primary Attributes",
	keys = {"ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_SPIRIT_SHORT"}
}, {
	label = "Power",
	keys = {"ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "ITEM_MOD_SPELL_POWER_SHORT"}
}, {
	label = "Ratings",
	keys = {"ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_EXPERTISE_RATING_SHORT", "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
         "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT", "ITEM_MOD_RESILIENCE_RATING_SHORT"}
}}

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
				box:SetText(current)
			end)

			local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			lbl:SetPoint("LEFT", edit, "RIGHT", 6, 0)
			lbl:SetWidth(120)
			lbl:SetJustifyH("LEFT")
			lbl:SetText(_G[key] or key)

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

	local statsHeight = -y
	self.statsFrame:SetHeight(statsHeight)
	self.totalHeight = statsHeight + HEADER_HEIGHT

	-- populate default values once immediately after construction
	for _, field in ipairs(self.fields) do
		local v = self.profileData and self.profileData.weights[field.statKey]
		if v then
			field.edit:SetText(tostring(v))
		else
			field.edit:SetText("")
		end
		field.edit:ClearFocus()
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
            field.edit:SetText(txt)
            field.edit:SetCursorPosition(0)
			field.edit:ClearFocus()
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
ScorePanel.refreshing = false
ScorePanel.pendingRefresh = false

function ScorePanel:clear()
	for _, comp in pairs(self.components) do comp.root:Hide() end
	self.components = {}
end

function ScorePanel:refreshAll()
	if self.refreshing then return end
	self.refreshing = true
	self:clear()
	local ordered = addon.GetProfiles()
    for index, name in ipairs(ordered) do
		local comp = ProfileComponent:Create(scrollChild, name, self)
		comp.parent = self
		self.components[name] = comp
	end
	self:layout()
	self.refreshing = false
end

local function forceTextRefresh(panel)
	for _, comp in pairs(panel.components) do
		for _, field in ipairs(comp.fields or {}) do
			local txt = field.edit:GetText()
			field.edit:SetText(txt)
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
	forceTextRefresh(self)
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

local function setSourceOption(optionKey, value)
	if type(addon.SetSearchSourceOption) ~= "function" then
		print("|cffff7f00ItemScore:|r source manager unavailable.")
		return false
	end
	local changed = addon.SetSearchSourceOption(optionKey, value)
	if changed and optionKey ~= "searchMaxRequiredLevel" and type(addon.QueueSearchCacheRefresh) == "function" then
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

local function setAllAtlasRaidsEnabled(enabled)
	if type(addon.SetAllAtlasLootRaidsEnabled) ~= "function" then
		print("|cffff7f00ItemScore:|r source manager unavailable.")
		return false
	end
	local changed = addon.SetAllAtlasLootRaidsEnabled(enabled and true or false)
	if changed and type(addon.QueueSearchCacheRefresh) == "function" then
		addon.QueueSearchCacheRefresh("options:raid_all")
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

local function getRaidChoices()
	if type(addon.GetAtlasLootRaidChoices) ~= "function" then
		return {}
	end
	local choices = addon.GetAtlasLootRaidChoices()
	if type(choices) ~= "table" then return {} end
	return choices
end

local function hideRaidRows(panel)
	if not panel.raidRows then return end
	for _, row in ipairs(panel.raidRows) do
		row:Hide()
	end
end

local function acquireRaidHeader(panel, rowIndex)
	panel.raidRows = panel.raidRows or {}
	local row = panel.raidRows[rowIndex]
	if row and row._isHeader then
		return row
	end
	row = panel.raidChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row._isHeader = true
	panel.raidRows[rowIndex] = row
	return row
end

local function acquireRaidCheck(panel, rowIndex)
	panel.raidRows = panel.raidRows or {}
	local row = panel.raidRows[rowIndex]
	if row and not row._isHeader then
		return row
	end
	row = U.CreateCheckButton(panel.raidChild, "")
	row._isHeader = false
	row:SetScript("OnClick", function(btn)
		local raidName = btn._raidName
		if raidName then
			setAtlasRaidEnabled(raidName, btn:GetChecked())
			refreshSourcesPanel(panel)
		end
	end)
	panel.raidRows[rowIndex] = row
	return row
end

local function rebuildRaidList(panel, settings)
	if not panel.raidChild then return end

	hideRaidRows(panel)
	local atlasEnabled = settings.useAtlasLoot and true or false
	local raidChoices = getRaidChoices()

	local rowIndex = 1
	local y = 0
	if #raidChoices == 0 then
		local empty = acquireRaidHeader(panel, rowIndex)
		empty:ClearAllPoints()
		empty:SetPoint("TOPLEFT", 0, y)
		empty:SetText("No AtlasLoot raid tables available.")
		empty:Show()
		rowIndex = rowIndex + 1
		y = y - 20
	else
		for _, group in ipairs(raidChoices) do
			local groupLabel = acquireRaidHeader(panel, rowIndex)
			groupLabel:ClearAllPoints()
			groupLabel:SetPoint("TOPLEFT", 0, y)
			groupLabel:SetText(group.label or tostring(group.key or "Expansion"))
			groupLabel:Show()
			rowIndex = rowIndex + 1
			y = y - 20

			local groupEnabled = atlasEnabled and groupEnabledByExpansion(settings, group.key)
			for _, raidName in ipairs(group.raids or {}) do
				local check = acquireRaidCheck(panel, rowIndex)
				check._raidName = raidName
				check:ClearAllPoints()
				check:SetPoint("TOPLEFT", 8, y)
				check:SetChecked(not settings.atlasDisabledRaids[raidName])
				if check.text then
					check.text:SetText(raidName)
				end
				setButtonEnabled(check, groupEnabled)
				check:Show()
				rowIndex = rowIndex + 1
				y = y - 22
			end

			y = y - 4
		end
	end

	panel.raidChild:SetHeight(math.max(1, -y + 8))
	if panel.raidScroll and panel.raidScroll.UpdateScrollChildRect then
		panel.raidScroll:UpdateScrollChildRect()
	end
end

refreshSourcesPanel = function(panel)
	local settings = getSourceSettings()
	local status = getSourceStatus()

	setCheckIfExists(panel.useLootCollector, settings.useLootCollector)
	setCheckIfExists(panel.useAtlasLoot, settings.useAtlasLoot)
	setCheckIfExists(panel.worldforgedMC, settings.worldforgedMC)
	setCheckIfExists(panel.worldforgedBWL, settings.worldforgedBWL)
	setCheckIfExists(panel.worldforgedNaxx, settings.worldforgedNaxx)
	setCheckIfExists(panel.atlasClassic, settings.atlasClassic)
	setCheckIfExists(panel.atlasTBC, settings.atlasTBC)
	setCheckIfExists(panel.atlasWrath, settings.atlasWrath)

	local atlasEnabled = settings.useAtlasLoot and true or false
	local lootCollectorEnabled = settings.useLootCollector and true or false
	setButtonEnabled(panel.worldforgedMC, lootCollectorEnabled)
	setButtonEnabled(panel.worldforgedBWL, lootCollectorEnabled)
	setButtonEnabled(panel.worldforgedNaxx, lootCollectorEnabled)
	setButtonEnabled(panel.atlasClassic, atlasEnabled)
	setButtonEnabled(panel.atlasTBC, atlasEnabled)
	setButtonEnabled(panel.atlasWrath, atlasEnabled)
	setButtonEnabled(panel.enableAllRaidsBtn, atlasEnabled)
	setButtonEnabled(panel.disableAllRaidsBtn, atlasEnabled)
	rebuildRaidList(panel, settings)

		panel.statusText:SetText(string.format("Cache: %d items", status.itemCount or 0))

	local disabledCount = 0
	if type(addon.GetDisabledAtlasLootPlaces) == "function" then
		disabledCount = #(addon.GetDisabledAtlasLootPlaces() or {})
	end
	panel.helpText:SetText("Dungeons are always active for enabled expansions.\nArea-level filters via chat:\n/is atlas place off <Area>\n/is atlas place on <Area>\n/is atlas place all\n/is atlas place list\nDisabled areas: " ..
		tostring(disabledCount))
end

SourcesPanel:SetScript("OnShow", function(self)
	if not self.initialized then
		self.initialized = true

		local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 16, -16)
		title:SetText("ItemScore Loot Sources")

			local y = -48

			self.useLootCollector = U.CreateCheckButton(self, "Use LootCollector")
			self.useLootCollector:SetPoint("TOPLEFT", 16, y)
			self.useLootCollector:SetScript("OnClick", function(btn)
				setSourceOption("useLootCollector", btn:GetChecked())
				refreshSourcesPanel(self)
			end)

			y = y - 28
			local wfLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			wfLabel:SetPoint("TOPLEFT", 36, y)
			wfLabel:SetText("LootCollector Worldforged Tiers")

			y = y - 22
			self.worldforgedMC = U.CreateCheckButton(self, "MC")
			self.worldforgedMC:SetPoint("TOPLEFT", 40, y)
			self.worldforgedMC:SetScript("OnClick", function(btn)
				setSourceOption("worldforgedMC", btn:GetChecked())
				refreshSourcesPanel(self)
			end)

			y = y - 22
			self.worldforgedBWL = U.CreateCheckButton(self, "BWL")
			self.worldforgedBWL:SetPoint("TOPLEFT", 40, y)
			self.worldforgedBWL:SetScript("OnClick", function(btn)
				setSourceOption("worldforgedBWL", btn:GetChecked())
				refreshSourcesPanel(self)
			end)

			y = y - 22
			self.worldforgedNaxx = U.CreateCheckButton(self, "Naxxramas")
			self.worldforgedNaxx:SetPoint("TOPLEFT", 40, y)
			self.worldforgedNaxx:SetScript("OnClick", function(btn)
				setSourceOption("worldforgedNaxx", btn:GetChecked())
				refreshSourcesPanel(self)
			end)

			y = y - 34
			self.useAtlasLoot = U.CreateCheckButton(self, "Use AtlasLoot")
			self.useAtlasLoot:SetPoint("TOPLEFT", 16, y)
			self.useAtlasLoot:SetScript("OnClick", function(btn)
				setSourceOption("useAtlasLoot", btn:GetChecked())
				refreshSourcesPanel(self)
			end)

		y = y - 30
		local expLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		expLabel:SetPoint("TOPLEFT", 36, y)
		expLabel:SetText("AtlasLoot Expansions")

		y = y - 24
		self.atlasClassic = U.CreateCheckButton(self, "Classic")
		self.atlasClassic:SetPoint("TOPLEFT", 40, y)
		self.atlasClassic:SetScript("OnClick", function(btn)
			setSourceOption("atlasClassic", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		y = y - 24
		self.atlasTBC = U.CreateCheckButton(self, "Burning Crusade")
		self.atlasTBC:SetPoint("TOPLEFT", 40, y)
		self.atlasTBC:SetScript("OnClick", function(btn)
			setSourceOption("atlasTBC", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		y = y - 24
		self.atlasWrath = U.CreateCheckButton(self, "Wrath of the Lich King")
		self.atlasWrath:SetPoint("TOPLEFT", 40, y)
		self.atlasWrath:SetScript("OnClick", function(btn)
			setSourceOption("atlasWrath", btn:GetChecked())
			refreshSourcesPanel(self)
		end)

		y = y - 24
		local dungeonInfo = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		dungeonInfo:SetPoint("TOPLEFT", 36, y)
		dungeonInfo:SetJustifyH("LEFT")
		dungeonInfo:SetText("Dungeons are always active for enabled expansions.")

		y = y - 34
		self.refreshCacheBtn = U.CreateButton(self, 150, HEADER_HEIGHT, "Refresh Cache Now")
		self.refreshCacheBtn:SetPoint("TOPLEFT", 16, y)
		self.refreshCacheBtn:SetScript("OnClick", function()
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

		y = y - 34
		self.statusText = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		self.statusText:SetPoint("TOPLEFT", 16, y)
		self.statusText:SetJustifyH("LEFT")

		y = y - 34
		self.helpText = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		self.helpText:SetPoint("TOPLEFT", 16, y)
		self.helpText:SetJustifyH("LEFT")

		self.raidTitle = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		self.raidTitle:SetPoint("TOPLEFT", 340, -48)
		self.raidTitle:SetText("AtlasLoot Raids")

		self.enableAllRaidsBtn = U.CreateButton(self, 100, HEADER_HEIGHT, "Enable All")
		self.enableAllRaidsBtn:SetPoint("TOPLEFT", 340, -70)
		self.enableAllRaidsBtn:SetScript("OnClick", function()
			setAllAtlasRaidsEnabled(true)
			refreshSourcesPanel(self)
		end)

		self.disableAllRaidsBtn = U.CreateButton(self, 100, HEADER_HEIGHT, "Disable All")
		self.disableAllRaidsBtn:SetPoint("LEFT", self.enableAllRaidsBtn, "RIGHT", 8, 0)
		self.disableAllRaidsBtn:SetScript("OnClick", function()
			setAllAtlasRaidsEnabled(false)
			refreshSourcesPanel(self)
		end)

		self.raidScroll = CreateFrame("ScrollFrame", nil, self, "UIPanelScrollFrameTemplate")
		self.raidScroll:SetPoint("TOPLEFT", 340, -100)
		self.raidScroll:SetSize(290, 265)

		self.raidChild = CreateFrame("Frame", nil, self.raidScroll)
		self.raidChild:SetWidth(268)
		self.raidChild:SetHeight(1)
		self.raidScroll:SetScrollChild(self.raidChild)
		self.raidRows = {}
	end

	refreshSourcesPanel(self)
end)

InterfaceOptions_AddCategory(SourcesPanel)

SLASH_ITEMSCORE1 = "/itemscore"
SlashCmdList["ITEMSCORE"] = function()
	InterfaceOptionsFrame_OpenToCategory(ScorePanel)
	InterfaceOptionsFrame_OpenToCategory(ScorePanel)
end
