-- Profile editing and AtlasLoot source selection in Blizzard Settings.
local addonName, addon = ...
local U = addon

--------------------------------------------------
-- Constants
--------------------------------------------------
local HEADER_HEIGHT = 24

local function setButtonEnabled(btn, enabled)
	btn:SetEnabled(enabled)
end

-- Creates a restrained visual group for dense settings panels.
local function createOptionsGroup(parent)
	local group = CreateFrame("Frame", nil, parent, "BackdropTemplate")
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
-- client. Resetting the cursor exposes the beginning of the value.
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
            local name = pop:GetEditBox():GetText()
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

local RootPanel = CreateFrame("Frame", "ItemScoreRootOptionsFrame", UIParent)
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

local rootCategory = Settings.RegisterCanvasLayoutCategory(RootPanel, "ItemScore")
Settings.RegisterAddOnCategory(rootCategory)

local ScorePanel = CreateFrame("Frame", "ItemScoreOptionsFrame", UIParent)
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

local scoreCategory = Settings.RegisterCanvasLayoutSubcategory(rootCategory, ScorePanel, "Scores")

local SourcesPanel = CreateFrame("Frame", "ItemScoreSourcesOptionsFrame", UIParent)
Settings.RegisterCanvasLayoutSubcategory(rootCategory, SourcesPanel, "Loot Sources")
local sourceTitle = SourcesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
sourceTitle:SetPoint("TOPLEFT", 16, -16)
sourceTitle:SetText("AtlasLoot Forever")
local enabled = U.CreateCheckButton(SourcesPanel, "Use AtlasLoot Forever for item searches")
enabled:SetPoint("TOPLEFT", 16, -44)
enabled:SetScript("OnClick", function(self) addon.SetSearchSourceOption("useAtlasLoot", self:GetChecked()) end)
local refreshButton = U.CreateButton(SourcesPanel, 130, 24, "Refresh catalogue")
refreshButton:SetPoint("TOPLEFT", 16, -78)
refreshButton:SetScript("OnClick", function() addon.RefreshSearchCache(true, false) end)
local allButton = U.CreateButton(SourcesPanel, 90, 24, "Select all")
allButton:SetPoint("LEFT", refreshButton, "RIGHT", 12, 0)
local noneButton = U.CreateButton(SourcesPanel, 90, 24, "Clear all")
noneButton:SetPoint("LEFT", allButton, "RIGHT", 8, 0)
local sourceStatus = SourcesPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sourceStatus:SetPoint("TOPLEFT", 16, -112)
sourceStatus:SetPoint("RIGHT", SourcesPanel, "RIGHT", -24, 0)
sourceStatus:SetJustifyH("LEFT")
local sourceScroll = CreateFrame("ScrollFrame", nil, SourcesPanel, "UIPanelScrollFrameTemplate")
sourceScroll:SetPoint("TOPLEFT", 16, -160)
sourceScroll:SetPoint("BOTTOMRIGHT", -34, 16)
local sourceChild = CreateFrame("Frame", nil, sourceScroll)
sourceChild:SetWidth(580)
sourceScroll:SetScrollChild(sourceChild)
local sourceRows = {}

local function refreshSources()
    local settings, status = addon.GetSearchSourceSettings(), addon.GetSearchCacheStatus()
    enabled:SetChecked(settings.useAtlasLoot)
    local text = string.format("%d items. Select the places and categories to search.", status.itemCount)
    if status.updating then text = "Building catalogue..."
    elseif status.lastError then text = status.lastError
    elseif status.availableProviderCount == 0 then text = "Enable AtlasLoot Forever and its loot modules, then reload the UI." end
    sourceStatus:SetText(text)
    local sourceChoices = addon.GetSearchSourceChoices()
    for index, choice in ipairs(sourceChoices) do
        local row = sourceRows[index]
        if not row then
            row = U.CreateCheckButton(sourceChild, "")
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 26)
            row:SetScript("OnClick", function(self) addon.SetSearchSourceEnabled(self.sourceKey, self:GetChecked()) end)
            sourceRows[index] = row
        end
        row.sourceKey = choice.key
        row.text:SetText(choice.group .. " - " .. choice.label)
        row:SetChecked(not settings.disabledSources[choice.key])
        row:Show()
    end
    for index = #sourceChoices + 1, #sourceRows do sourceRows[index]:Hide() end
    sourceChild:SetHeight(math.max(1, #sourceChoices * 26))
    sourceScroll:UpdateScrollChildRect()
end

local function selectAllSources(value)
    for _, choice in ipairs(addon.GetSearchSourceChoices()) do addon.SetSearchSourceEnabled(choice.key, value) end
    refreshSources()
end
allButton:SetScript("OnClick", function() selectAllSources(true) end)
noneButton:SetScript("OnClick", function() selectAllSources(false) end)
SourcesPanel:SetScript("OnShow", refreshSources)
addon.SubscribeSearchCatalog(function() if SourcesPanel:IsShown() then refreshSources() end end)
SLASH_ITEMSCORE1 = "/itemscore"
SlashCmdList["ITEMSCORE"] = function() Settings.OpenToCategory(scoreCategory:GetID()) end
