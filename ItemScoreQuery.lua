local addonName, addon = ...

-- Bounded asynchronous item-info warmer used by search when custom item IDs resolve slowly.

local Query = {}
addon.Query = Query

--------------------------------------------------
-- internal state
--------------------------------------------------
local queue = {}
local queued = {}
local queryAttempts = {}
local queueHead = 1
local queueTail = 0
local QUERY_TIMEOUT_SECONDS = 20
local QUERY_WAIT_AFTER_SECONDS = 1.5
local QUERY_MAX_ATTEMPTS_PER_ITEM = 2
local QUERY_UNRESOLVED_RETRY_SECONDS = 5 * 60
local QUERY_START_ITEMS_PER_FRAME = 1
local QUERY_MIN_ITEMS_PER_FRAME = 1
local QUERY_MAX_ITEMS_PER_FRAME = 250
local QUERY_TARGET_FRAME_FRACTION = 0.12
local QUERY_MIN_FRAME_BUDGET_MS = 0.75
local QUERY_MAX_FRAME_BUDGET_MS = 4

local hiddenTooltip = CreateFrame("GameTooltip", "ISQHiddenTooltip", nil, "GameTooltipTemplate")
hiddenTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local driver = CreateFrame("Frame")
local listeners = {}
local isSearching = false
local searchTimeWaitAfter = 0
local searchStartedAt = 0
local queryItemsPerFrame = QUERY_START_ITEMS_PER_FRAME

local function process(id)
	if not id then return end
	pcall(hiddenTooltip.SetHyperlink, hiddenTooltip, "item:" .. id .. ":::::::::")
end

local function nowSeconds()
	if type(GetTime) == "function" then
		return GetTime()
	end
	return 0
end

local function nowMillis()
	if type(debugprofilestop) == "function" then
		return debugprofilestop()
	end
	return nowSeconds() * 1000
end

local function hasQueuedItems()
	return queueHead <= queueTail
end

local function currentFrameBudgetMs()
	local frameMs = 16.7
	if type(GetFramerate) == "function" then
		local fps = tonumber(GetFramerate()) or 0
		if fps > 0 then
			frameMs = 1000 / fps
		end
	end

	local budgetMs = frameMs * QUERY_TARGET_FRAME_FRACTION
	if budgetMs < QUERY_MIN_FRAME_BUDGET_MS then budgetMs = QUERY_MIN_FRAME_BUDGET_MS end
	if budgetMs > QUERY_MAX_FRAME_BUDGET_MS then budgetMs = QUERY_MAX_FRAME_BUDGET_MS end
	return budgetMs
end

local function tuneQueryItemsPerFrame(processed, elapsedMs, targetMs)
	if processed <= 0 then return end

	local budget = queryItemsPerFrame
	if elapsedMs <= 0 then
		budget = math.floor((budget * 1.6) + 0.5)
	elseif elapsedMs < (targetMs * 0.55) then
		budget = math.floor((budget * 1.5) + 0.5)
	elseif elapsedMs < (targetMs * 0.85) then
		budget = budget + math.max(1, math.floor(budget * 0.20))
	elseif elapsedMs > (targetMs * 1.50) then
		budget = math.floor((budget * 0.50) + 0.5)
	elseif elapsedMs > (targetMs * 1.10) then
		budget = math.floor((budget * 0.80) + 0.5)
	end

	if budget < QUERY_MIN_ITEMS_PER_FRAME then budget = QUERY_MIN_ITEMS_PER_FRAME end
	if budget > QUERY_MAX_ITEMS_PER_FRAME then budget = QUERY_MAX_ITEMS_PER_FRAME end
	queryItemsPerFrame = budget
end

local function clearPendingQueue(markUnresolved)
	local currentTime = nowSeconds()
	for i = queueHead, queueTail do
		local itemID = queue[i]
		if itemID then
			queued[itemID] = nil
			if markUnresolved then
				queryAttempts[itemID] = {
					count = QUERY_MAX_ATTEMPTS_PER_ITEM,
					lastAttemptAt = currentTime,
				}
			end
		end
		queue[i] = nil
	end
	queueHead = 1
	queueTail = 0
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
	queryItemsPerFrame = QUERY_START_ITEMS_PER_FRAME
	driver:Hide()

	if forceTimeout then
		clearPendingQueue(true)
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

	if not hasQueuedItems() then
		searchTimeWaitAfter = searchTimeWaitAfter - elapsed
		if (searchTimeWaitAfter <= 0) then
			finishSearch(false)
		end
	else
		local startMs = nowMillis()
		local targetMs = currentFrameBudgetMs()
		local itemBudget = queryItemsPerFrame
		local processed = 0
		while hasQueuedItems() do
			local id = queue[queueHead]
			queue[queueHead] = nil
			queueHead = queueHead + 1
			if id then
				queued[id] = nil
				process(id)
				processed = processed + 1
			end
			if processed >= itemBudget then break end
			if nowMillis() - startMs >= targetMs then break end
		end
		tuneQueryItemsPerFrame(processed, nowMillis() - startMs, targetMs)
		if not hasQueuedItems() then
			queueHead = 1
			queueTail = 0
		end
	end
end)

driver:Hide()

--------------------------------------------------
-- public API
--------------------------------------------------
function Query.Add(id)
	local itemID = tonumber(id)
	if not itemID or itemID <= 0 then return false end
	if queued[itemID] then return true end

	local currentTime = nowSeconds()
	local attempts = queryAttempts[itemID]
	if attempts and attempts.count >= QUERY_MAX_ATTEMPTS_PER_ITEM then
		local retryAt = (attempts.lastAttemptAt or 0) + QUERY_UNRESOLVED_RETRY_SECONDS
		if currentTime < retryAt then
			return false
		end
		attempts.count = 0
	end

	if not isSearching then
		searchStartedAt = currentTime
	end
	isSearching = true
	searchTimeWaitAfter = QUERY_WAIT_AFTER_SECONDS
	attempts = attempts or { count = 0, lastAttemptAt = 0 }
	attempts.count = attempts.count + 1
	attempts.lastAttemptAt = currentTime
	queryAttempts[itemID] = attempts
	queued[itemID] = true
	queueTail = queueTail + 1
	queue[queueTail] = itemID
	driver:Show()
	return true
end

function Query.RegisterDone(cb)
	if not Query.IsBusy() then
		cb()
	else
		table.insert(listeners, cb)
	end
end

function Query.IsBusy() return isSearching end
