local addonName, addon = ...

local ROW_H, PAD = 20, 16
local FULL_VISIBILITY_SECONDS = 60
local FADE_SECONDS = 3
local EXPIRE_SECONDS = FULL_VISIBILITY_SECONDS + FADE_SECONDS

ItemDropWatchDB = ItemDropWatchDB or {
	count = 0,
	items = {}
}

------------------------------------------------------------------------
--  Saved-Variables Defaults
------------------------------------------------------------------------
local defaults = {
	count = 3,
	items = {}
}

local function clamp(v, mi, ma) return math.max(mi, math.min(ma, v)) end
local function capacity(h) return clamp(math.floor((h - PAD) / (ROW_H + 2)), 1, 50) end

local rarityColors = {
	[0] = "|cff9d9d9d",
	[1] = "|cffffffff",
	[2] = "|cff1eff00",
	[3] = "|cff0070dd",
	[4] = "|cffa335ee",
	[5] = "|cffff8000",
	[6] = "|cffe6cc80"
}

------------------------------------------------------------------------
--  Frame Creation & Drag/Resize
------------------------------------------------------------------------
local frame do
    local ok, obj = pcall(CreateFrame, "Frame", "ItemDropWatchFrame", UIParent, "BackdropTemplate")
    if ok and obj then frame = obj else frame = CreateFrame("Frame", "ItemDropWatchFrame", UIParent) end
end
frame:SetPoint("CENTER", 0, -200)
frame:SetSize(250, PAD + 3 * (ROW_H + 2))
frame:SetBackdrop({
	bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 12,
	insets = {
		left = 3,
		right = 3,
		top = 3,
		bottom = 3
	}
})
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:SetMinResize(120, PAD + ROW_H)
frame:EnableMouse(true)

local function handleDrag(button, start)
	if button ~= "LeftButton" or not IsAltKeyDown() then return end
	if start then
		frame:StartMoving()
	else
		frame:StopMovingOrSizing()
	end
end
frame:SetScript("OnMouseDown", function(_, b) handleDrag(b, true) end)
frame:SetScript("OnMouseUp", function(_, b) handleDrag(b, false) end)

-- Sizer
local sizer = CreateFrame("Frame", nil, frame)
sizer:SetPoint("BOTTOMRIGHT")
sizer:SetSize(16, 16)
sizer:EnableMouse(true)
local sizerTex = sizer:CreateTexture(nil, "BACKGROUND")
sizerTex:SetAllPoints()
sizerTex:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
sizer:SetScript("OnEnter", function() sizerTex:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight") end)
sizer:SetScript("OnLeave", function() sizerTex:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up") end)
sizer:SetScript("OnMouseDown", function(_, b) if b == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
sizer:SetScript("OnMouseUp", function(_, b) if b == "LeftButton" then frame:StopMovingOrSizing() end end)

------------------------------------------------------------------------
--  Item Rows
------------------------------------------------------------------------
local rows = {}
local function makeRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 8, -8 - (index - 1) * (ROW_H + 2))
	row:SetPoint("RIGHT", -24, 0)
	row:EnableMouse(true)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT")

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontWhiteSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetJustifyH("LEFT")

	local function showTip(self)
		if self.link then
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			GameTooltip:SetHyperlink(self.link)
			GameTooltip:Show()
		end
	end
	local function hideTip() if GameTooltip:IsShown() then GameTooltip:Hide() end end
	row:SetScript("OnEnter", showTip)
	row:SetScript("OnLeave", hideTip)
	row:SetScript("OnHide", hideTip)

	row:SetScript("OnMouseDown", function(_, b) handleDrag(b, true) end)
	row:SetScript("OnMouseUp", function(_, b) handleDrag(b, false) end)

	rows[index] = row
end
for i = 1, 3 do makeRow(i) end

local function getItemAgeSeconds(item, now, nowUptime)
	local uptime = tonumber(item and (item.uptime or item.time))
	if uptime and uptime >= 0 and nowUptime and nowUptime >= uptime then
		return nowUptime - uptime
	end

	local timestamp = tonumber(item and item.timestamp)
	if not timestamp or timestamp <= 0 then return math.huge end
	local age = now - timestamp
	if age < 0 then return math.huge end
	return age
end

local function getRowAlpha(ageSeconds)
	if ageSeconds <= FULL_VISIBILITY_SECONDS then return 1 end
	if ageSeconds >= EXPIRE_SECONDS then return 0 end
	return (EXPIRE_SECONDS - ageSeconds) / FADE_SECONDS
end

------------------------------------------------------------------------
--  UI Refresh
------------------------------------------------------------------------
local function refresh(now)
	local maxRows = ItemDropWatchDB.count
	local currentTime = now or time()
	local currentUptime = GetTime()
	for i = #rows + 1, maxRows do makeRow(i) end

	for i = 1, maxRows do
		local item = ItemDropWatchDB.items[i]
		if item then
			rows[i].icon:SetTexture(item.icon)
			rows[i].text:SetText(rarityColors[item.rarity] .. item.name .. "|r")
			rows[i].link = item.link
			rows[i]:SetAlpha(getRowAlpha(getItemAgeSeconds(item, currentTime, currentUptime)))
			rows[i]:Show()
		else
			rows[i]:Hide()
			rows[i]:SetAlpha(1)
			rows[i].link = nil
		end
	end
	for i = maxRows + 1, #rows do
		rows[i]:Hide()
		rows[i]:SetAlpha(1)
	end
end

local function setCapacityByHeight(h)
	local cap = capacity(h)
	if cap ~= ItemDropWatchDB.count then
		ItemDropWatchDB.count = cap
		refresh()
	end
end
frame:SetScript("OnSizeChanged", function(_, _, h) setCapacityByHeight(h) end)

------------------------------------------------------------------------
--  Item Handling (Upgrade filter)
------------------------------------------------------------------------
local function isUpgrade(link)
	local name = GetItemInfo(link)
	if not name then return nil end -- defer until info ready
	return addon.IsUpgrade(link, nil)
end

local pending = {}

local function actuallyInsert(link)
	local name, _, rarity, _, _, _, _, _, _, icon = GetItemInfo(link)
	if not name then return false end
	table.insert(ItemDropWatchDB.items, 1, {
		name = name,
		icon = icon,
		rarity = rarity,
		link = link,
		timestamp = time(),
		uptime = GetTime()
	})
	refresh()
	return true
end

local function push(link)
	local ok = isUpgrade(link)
	if ok == nil then
		pending[link] = true
		return
	end
	if not ok then return end
	if not actuallyInsert(link) then pending[link] = true end
end

------------------------------------------------------------------------
--  Expiration & OnUpdate
------------------------------------------------------------------------
local function pruneExpiredItems(now, nowUptime)
	local changed = false
	for i = #ItemDropWatchDB.items, 1, -1 do
		if getItemAgeSeconds(ItemDropWatchDB.items[i], now, nowUptime) >= EXPIRE_SECONDS then
			table.remove(ItemDropWatchDB.items, i)
			changed = true
		end
	end
	return changed
end

local fadeAccumulator = 0
local pruneAccumulator = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	if #ItemDropWatchDB.items == 0 then return end

	fadeAccumulator = fadeAccumulator + elapsed
	pruneAccumulator = pruneAccumulator + elapsed
	if fadeAccumulator < 0.2 and pruneAccumulator < 1 then return end

	local now = time()
	local nowUptime = GetTime()
	local changed = false
	if pruneAccumulator >= 1 then
		pruneAccumulator = 0
		changed = pruneExpiredItems(now, nowUptime)
	end
	if changed or fadeAccumulator >= 0.2 then
		fadeAccumulator = 0
		refresh(now)
	end
end)

frame:SetScript("OnShow", function()
	local now = time()
	pruneExpiredItems(now, GetTime())
	refresh(now)
end)

------------------------------------------------------------------------
--  SavedVariables Init & Events
------------------------------------------------------------------------
local function initDB()
	if not ItemDropWatchDB then ItemDropWatchDB = {} end
	for k, v in pairs(defaults) do if ItemDropWatchDB[k] == nil then ItemDropWatchDB[k] = v end end
	if type(ItemDropWatchDB.items) ~= "table" then ItemDropWatchDB.items = {} end

	for i = #ItemDropWatchDB.items, 1, -1 do
		local item = ItemDropWatchDB.items[i]
		if type(item) ~= "table" then
			table.remove(ItemDropWatchDB.items, i)
		elseif item.timestamp == nil then
			local legacyTime = tonumber(item.time)
			if legacyTime and legacyTime > 1000000000 then
				item.timestamp = math.floor(legacyTime)
			else
				item.timestamp = 0
			end
		end
	end

	pruneExpiredItems(time(), GetTime())
end

frame:SetScript("OnEvent", function(_, event, msg)
	if event == "CHAT_MSG_LOOT" then
		local link = msg:match("|Hitem:%d+.-|h%[.-%]|h")
		if link then push(link) end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		local itemID = msg
		for link in pairs(pending) do if link:match("item:" .. itemID .. ":") then if isUpgrade(link) and actuallyInsert(link) then pending[link] = nil end end end
	elseif event == "PLAYER_LOGIN" then
		initDB()
		setCapacityByHeight(frame:GetHeight())
		refresh()
	end
end)
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

------------------------------------------------------------------------
--  Slash Commands (lock / unlock / clear)
------------------------------------------------------------------------
SLASH_ITEMDROPWATCH1, SLASH_ITEMDROPWATCH2 = "/idw", "/itemdropwatch"
SlashCmdList["ITEMDROPWATCH"] = function(cmd)
	local a = cmd:match("^(%S*)")
	if a == "clear" then
		wipe(ItemDropWatchDB.items)
		refresh()
		print("IDW: list cleared.")
	elseif (a == "show") then
		frame:Show()
	elseif (a == "hide") then
		frame:Hide()
	else
		print("/idw show   – show window")
		print("/idw hide   – hide window")
		print("/idw clear  – clear current list")
		print("Only items that are real upgrades for your character are displayed. They start fading after about 1 minute and are then removed.")
	end
end
