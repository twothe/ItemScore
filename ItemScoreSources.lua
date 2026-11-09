-- Owns source selection, cache migration and atomic, frame-budgeted catalogue publication.
-- The adapter emits IDs and provenance; the manager never interprets AtlasLoot tables.
local addonName, addon = ...
local SCHEMA = 10
local settings, cache, choices
local worker, rebuildQueued, refreshAgain, lastError = nil, false, false, nil
local listeners = {}
local driver = CreateFrame("Frame")
local EMPTY = { itemIDs = {}, itemSources = {} }

local function initialize()
    if settings then return end
    ItemScoreData = ItemScoreData or {}
    local old = type(ItemScoreData.searchSources) == "table" and ItemScoreData.searchSources or {}
    settings = {
        useAtlasLoot = old.useAtlasLoot ~= false,
        searchUseMaxRequiredLevel = old.searchUseMaxRequiredLevel ~= false,
        searchMaxRequiredLevel = math.max(0, math.min(60, tonumber(old.searchMaxRequiredLevel) or UnitLevel("player"))),
        disabledSources = old.schema == SCHEMA and old.disabledSources or {},
        schema = SCHEMA,
    }
    if type(settings.disabledSources) ~= "table" then settings.disabledSources = {} end
    ItemScoreData.searchSources = settings
    if type(ItemScoreCacheDB) ~= "table" or ItemScoreCacheDB.schema ~= SCHEMA then
        ItemScoreCacheDB = { schema = SCHEMA }
    end
    cache = ItemScoreCacheDB
    choices = cache.choices or {}
end

local function fingerprint()
    initialize()
    local parts = { addon.AtlasLootSource.GetIdentity(), GetLocale(), UnitFactionGroup("player") or "", tostring(settings.useAtlasLoot) }
    local disabled = {}
    for key, value in pairs(settings.disabledSources) do if value then disabled[#disabled + 1] = key end end
    table.sort(disabled)
    for _, key in ipairs(disabled) do parts[#parts + 1] = key end
    return table.concat(parts, "\n")
end

local function notify()
    for _, callback in ipairs(listeners) do
        local ok, err = pcall(callback)
        if not ok then geterrorhandler()("ItemScore catalogue callback: " .. tostring(err)) end
    end
end

function addon.SubscribeSearchCatalog(callback)
    assert(type(callback) == "function", "Catalogue callback required")
    listeners[#listeners + 1] = callback
end

function addon.GetSearchSourceSettings() initialize(); return settings end
function addon.GetSearchSourceChoices() initialize(); return choices end

function addon.SetSearchSourceOption(key, value)
    initialize()
    assert(key == "useAtlasLoot" or key == "searchUseMaxRequiredLevel" or key == "searchMaxRequiredLevel", "Unknown source setting: " .. tostring(key))
    if key == "searchMaxRequiredLevel" then value = math.max(0, math.min(60, math.floor(tonumber(value) or 0)))
    else value = not not value end
    if settings[key] == value then return false end
    settings[key] = value
    if key == "useAtlasLoot" then addon.QueueSearchCacheRefresh() end
    return true
end

function addon.SetSearchSourceEnabled(key, enabled)
    initialize()
    assert(type(key) == "string" and key ~= "", "Source key required")
    settings.disabledSources[key] = not enabled or nil
    addon.QueueSearchCacheRefresh()
end

function addon.GetSearchCacheStatus()
    initialize()
    local available = addon.AtlasLootSource.IsAvailable()
    local changed = cache.fingerprint ~= fingerprint()
    return {
        updating = worker ~= nil or rebuildQueued,
        stale = changed or lastError ~= nil,
        settingsChanged = changed,
        itemCount = cache.catalog and #cache.catalog.itemIDs or 0,
        lastError = lastError,
        enabledProviderCount = settings.useAtlasLoot and 1 or 0,
        availableProviderCount = available and 1 or 0,
        providers = { AtlasLoot = { enabled = settings.useAtlasLoot, available = available, adapterLabel = "Forever " .. addon.AtlasLootSource.GetVersion() } },
    }
end

-- Stale results from another character/filter/version must never leak into a new search.
function addon.GetSearchCatalog()
    local status = addon.GetSearchCacheStatus()
    return not status.settingsChanged and cache.catalog or EMPTY, status
end

local function build()
    local identity = fingerprint()
    local disabled = {}
    for key, value in pairs(settings.disabledSources) do disabled[key] = value end
    local catalog = { itemIDs = {}, itemSources = {}, builtAt = time(), mappingCount = 0 }
    local newChoices, seen = {}, {}
    local operations = 0
    local function checkpoint()
        operations = operations + 1
        if operations >= 100 then operations = 0; coroutine.yield() end
    end
    local function emit(id, source)
        assert(type(id) == "number" and id > 0 and id == math.floor(id), "Source emitted an invalid item ID")
        if not catalog.itemSources[id] then
            catalog.itemIDs[#catalog.itemIDs + 1] = id
            catalog.itemSources[id], seen[id] = {}, {}
        end
        local key = source.place .. "\n" .. source.source .. "\n" .. (source.difficultyLabel or "")
        if not seen[id][key] then
            seen[id][key] = true
            table.insert(catalog.itemSources[id], source)
            catalog.mappingCount = catalog.mappingCount + 1
        end
    end
    if settings.useAtlasLoot then
        addon.AtlasLootSource.Scan(disabled, function(choice) newChoices[#newChoices + 1] = choice end, emit, checkpoint)
    end
    table.sort(catalog.itemIDs)
    table.sort(newChoices, function(a, b)
        if a.group == b.group then return a.label < b.label end
        return a.group < b.group
    end)
    -- Configuration may change while yielding. Only commit a complete, matching snapshot.
    if identity ~= fingerprint() then refreshAgain = true; return end
    cache.catalog, cache.fingerprint, cache.choices = catalog, identity, newChoices
    choices, lastError = newChoices, nil
end

local function update()
    if InCombatLockdown() then return end
    local started = debugprofilestop()
    repeat
        local ok, err = coroutine.resume(worker)
        if not ok then
            lastError = tostring(err)
            print("ItemScore: catalogue update failed: " .. lastError)
            worker = nil
        elseif coroutine.status(worker) == "dead" then
            worker = nil
        end
    until not worker or debugprofilestop() - started >= 4
    if not worker then
        driver:SetScript("OnUpdate", nil)
        if refreshAgain then refreshAgain = false; addon.QueueSearchCacheRefresh() end
        notify()
    end
end

function addon.RefreshSearchCache(_, silent)
    initialize()
    if worker then refreshAgain = true; return false end
    if InCombatLockdown() then rebuildQueued = true; return false end
    rebuildQueued, lastError = false, nil
    worker = coroutine.create(build)
    driver:SetScript("OnUpdate", update)
    if not silent then print("ItemScore: rebuilding AtlasLoot Forever catalogue.") end
    return true
end

function addon.QueueSearchCacheRefresh()
    if worker then refreshAgain = true; return end
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.2, function()
        if rebuildQueued and not InCombatLockdown() then addon.RefreshSearchCache(true, true) end
    end)
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        settings = nil
        initialize()
    elseif event == "PLAYER_REGEN_ENABLED" and rebuildQueued then
        addon.RefreshSearchCache(true, true)
    elseif event == "PLAYER_LOGIN"
        or (event == "ADDON_LOADED" and name == "AtlasLootClassic") then
        addon.QueueSearchCacheRefresh()
    end
end)
