-- Loads item data and retains successful reads for the session across client cache eviction.
local _, addon = ...
local Query = {}
addon.Query = Query
local TIMEOUT, COOLDOWN, MAX_ATTEMPTS = 8, 300, 2
local watched, pending, listeners, doneListeners = {}, {}, {}, {}
local pendingCount, elapsedSinceUpdate = 0, 0
local driver = CreateFrame("Frame")
local requestsSuppressed = false
local itemInfoCache, itemStatsCache = {}, {}

-- Preserve the complete item string: variants must not inherit base-item attributes.
local function cacheKey(value)
    if type(value) == "number" then return "item:" .. value end
    if type(value) ~= "string" then return nil end
    return value:match("|H(item:[^|]+)|h") or value
end

local function pack(...)
    return { n = select("#", ...), ... }
end

-- Prefer fresh client data; only successful reads may populate the session cache.
function Query.GetItemInfo(value)
    local key = cacheKey(value)
    local info = pack(C_Item.GetItemInfo(value))
    if info[1] then
        if key then itemInfoCache[key] = info end
        local linkKey = cacheKey(info[2])
        if linkKey then itemInfoCache[linkKey] = info end
    else
        info = key and itemInfoCache[key]
    end
    if info then return unpack(info, 1, info.n) end
end

-- Returned attribute tables are read-only to callers. Empty tables are valid data.
function Query.GetItemStats(value)
    local key = cacheKey(value)
    local stats = C_Item.GetItemStats(value)
    if stats then
        local snapshot = {}
        for stat, amount in pairs(stats) do snapshot[stat] = amount end
        if key then
            itemStatsCache[key] = snapshot
            local info = itemInfoCache[key]
            local linkKey = info and cacheKey(info[2])
            if linkKey then itemStatsCache[linkKey] = snapshot end
        end
        return snapshot
    end
    return key and itemStatsCache[key]
end

-- A cache-driven search may read item data but must never start another load batch.
function Query.TryWithoutRequests(callback, ...)
    local previous = requestsSuppressed
    requestsSuppressed = true
    local ok, result = pcall(callback, ...)
    requestsSuppressed = previous
    return ok, result
end

local function itemID(value)
    local id = type(value) == "number" and value or tonumber(tostring(value):match("item:(%d+)"))
    if id and id > 0 and id == math.floor(id) then return id end
end

local function readiness(id)
    if not Query.GetItemInfo(id) then return 0 end
    if not Query.GetItemStats("item:" .. id) then return 1 end
    return 2
end

local function notify(list, ...)
    for _, callback in ipairs(list) do
        local ok, err = pcall(callback, ...)
        if not ok then geterrorhandler()("ItemScore item-data callback: " .. tostring(err)) end
    end
end

local function removePending(id)
    if pending[id] then pending[id] = nil; pendingCount = pendingCount - 1 end
end

local function observe(id)
    local record = watched[id]
    if not record then return end
    local ready = readiness(id)
    if ready > record.ready then
        record.ready = ready
        notify(listeners, id)
    end
    if ready == 2 then
        removePending(id)
        watched[id] = nil
    end
    return ready
end

local function finishBatch()
    if pendingCount ~= 0 then return end
    driver:SetScript("OnUpdate", nil)
    local callbacks = doneListeners
    doneListeners = {}
    notify(callbacks)
end

local function update(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < 0.1 then return end
    elapsedSinceUpdate = 0
    local now, sent = GetTime(), 0
    for id, record in pairs(pending) do
        if observe(id) ~= 2 and now >= record.nextRequest then
            if record.attempts >= MAX_ATTEMPTS then
                removePending(id)
            elseif sent < 40 then
                record.attempts = record.attempts + 1
                record.nextRequest = now + TIMEOUT
                sent = sent + 1
                C_Item.RequestLoadItemDataByID(id)
            end
        end
    end
    finishBatch()
end

-- Deduplicates requests; a failed batch can be retried after five minutes or next login.
function Query.Add(value)
    if requestsSuppressed then return false end
    local id = itemID(value)
    if not id then return false end
    if pending[id] then return true end
    local ready = readiness(id)
    if ready == 2 then return false end
    local now = GetTime()
    local record = watched[id]
    if record and now < record.retryAt then return false end
    record = { ready = ready, attempts = 0, nextRequest = now, retryAt = now + COOLDOWN }
    watched[id], pending[id] = record, record
    pendingCount = pendingCount + 1
    driver:SetScript("OnUpdate", update)
    return true
end

function Query.IsBusy() return pendingCount > 0 end

-- Batch completion includes failure/timeout and does not imply data availability.
function Query.RegisterDone(callback)
    assert(type(callback) == "function", "Item-data completion callback required")
    if Query.IsBusy() then doneListeners[#doneListeners + 1] = callback else callback() end
end

-- Persistent readiness notifications include successes arriving after a timeout.
function Query.Subscribe(callback)
    assert(type(callback) == "function", "Item-data callback required")
    listeners[#listeners + 1] = callback
end

driver:RegisterEvent("ITEM_DATA_LOAD_RESULT")
driver:RegisterEvent("GET_ITEM_INFO_RECEIVED")
driver:SetScript("OnEvent", function(_, _, id, success)
    local record = watched[id]
    if success and record then observe(id) end
    finishBatch()
end)
