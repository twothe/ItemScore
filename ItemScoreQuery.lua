local addonName, addon = ...

local Query = {}
_G.ItemScoreQuery = Query

--------------------------------------------------
-- internal state
--------------------------------------------------
local queue = {}
local queued = {}
local QUERY_TIMEOUT_SECONDS = 60

local hiddenTooltip = CreateFrame("GameTooltip", "ISQHiddenTooltip", nil, "GameTooltipTemplate")
hiddenTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local driver = CreateFrame("Frame")
local listeners = {}
local isSearching = false
local searchTimeWaitAfter = 0
local searchStartedAt = 0
local function process(id) hiddenTooltip:SetHyperlink("item:" .. id .. ":::::::::") end

local function nowSeconds()
	if type(GetTime) == "function" then
		return GetTime()
	end
	return 0
end

local function clearPendingQueue()
	for i = #queue, 1, -1 do
		local itemID = queue[i]
		if itemID then
			queued[itemID] = nil
		end
		queue[i] = nil
	end
end

local function notifyListeners()
	if #listeners == 0 then
		return
	end

	-- Swap listener table before callbacks to keep re-entrant registrations.
	local pendingListeners = listeners
	listeners = {}
	for _, cb in ipairs(pendingListeners) do
		local ok, err = pcall(cb)
		if not ok and type(geterrorhandler) == "function" then
			geterrorhandler()(err)
		end
	end
end

local function finishSearch(forceTimeout)
	isSearching = false
	searchStartedAt = 0
	searchTimeWaitAfter = 0
	driver:Hide()

	if forceTimeout then
		clearPendingQueue()
		print(string.format("|cffff7f00ItemScore:|r item-info fetching timed out after %d seconds. Search was reset.", QUERY_TIMEOUT_SECONDS))
	end

	notifyListeners()
end

driver:SetScript("OnUpdate", function(_, elapsed)
	if isSearching and searchStartedAt > 0 then
		local elapsedSearch = nowSeconds() - searchStartedAt
		if elapsedSearch >= QUERY_TIMEOUT_SECONDS then
			finishSearch(true)
			return
		end
	end

	if #queue == 0 then
		searchTimeWaitAfter = searchTimeWaitAfter - elapsed
		if (searchTimeWaitAfter <= 0) then
			finishSearch(false)
		end
	else
		local id = table.remove(queue, 1)
		if id then process(id) end
	end
end)

driver:Hide()

--------------------------------------------------
-- public API
--------------------------------------------------
function Query.Add(id)
	if not id or queued[id] then return end
	if not isSearching then
		searchStartedAt = nowSeconds()
	end
	isSearching = true
	searchTimeWaitAfter = 2.0
	queued[id] = true
	queue[#queue + 1] = id
	driver:Show()
end

function Query.RegisterDone(cb)
	if not Query.IsBusy() then
		cb()
	else
		table.insert(listeners, cb)
	end
end

function Query.IsBusy() return isSearching end
