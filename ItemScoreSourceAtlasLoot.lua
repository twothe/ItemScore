-- AtlasLoot Forever v1.x boundary. Only this file knows its module/table/row schema.
-- Scan emits source choices and item IDs; Blizzard alone supplies item attributes.
local _, addon = ...
local Adapter = { revision = 1 }
addon.AtlasLootSource = Adapter

local function clean(value)
    return (tostring(value or "Unknown"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Adapter.IsAvailable()
    local atlas = _G.AtlasLoot
    return type(atlas) == "table" and type(atlas.ItemDB) == "table"
        and type(atlas.ItemDB.GetItemTable) == "function"
        and type(atlas.Loader) == "table" and type(atlas.Loader.GetLootModuleList) == "function"
end

function Adapter.GetVersion()
    return tostring(C_AddOns.GetAddOnMetadata("AtlasLootClassic", "Version") or "missing") .. ":" .. Adapter.revision
end

local function modules(atlas)
    local list, result = atlas.Loader:GetLootModuleList(), {}
    assert(type(list) == "table", "AtlasLoot module list missing")
    for _, group in ipairs({ "module", "custom" }) do
        for _, module in ipairs(list[group] or {}) do result[#result + 1] = module end
    end
    table.sort(result, function(a, b) return a.addonName < b.addonName end)
    return result
end

-- Include module enablement/version in persistence identity, even before modules are loaded.
function Adapter.GetIdentity()
    if not Adapter.IsAvailable() then return "missing" end
    local parts = { Adapter.GetVersion() }
    for _, module in ipairs(modules(AtlasLoot)) do
        parts[#parts + 1] = module.addonName .. "=" .. tostring(C_AddOns.GetAddOnMetadata(module.addonName, "Version"))
    end
    return table.concat(parts, "|")
end

local function emitValue(atlas, kind, value, emit)
    if value == nil then return end
    if type(value) == "string" then
        local id = value:match("^i(%d+)$")
        if id then kind, value = "Item", tonumber(id)
        elseif value:match("^prof%d+$") then kind, value = "Profession", tonumber(value:sub(5))
        elseif value:match("^set%d+$") then kind, value = "Set", tonumber(value:sub(4))
        else return end -- Icon headings, links and other non-item buttons.
    end
    if type(value) ~= "number" or value <= 0 then return end
    if kind == "Item" then
        emit(value)
    elseif kind == "Profession" then
        local id = atlas.Data.Profession.GetCreatedItemID(value)
        if id then emit(id) end -- Enchants and gathering recipes need not create items.
    elseif kind == "Set" then
        local items = atlas.Data.ItemSet.GetSetItems(value)
        assert(type(items) == "table", "AtlasLoot set has no item list: " .. value)
        for _, id in ipairs(items) do emit(id) end
    elseif kind ~= "Faction" and kind ~= "Achievement" and kind ~= "Dummy" and kind ~= "Link" then
        error("Unsupported AtlasLoot row type: " .. tostring(kind))
    end
end

local function resolveBoss(db, moduleName, contentKey, bossIndex, visited)
    local key = moduleName .. ":" .. contentKey .. ":" .. bossIndex
    assert(not visited[key], "Cyclic AtlasLoot boss link: " .. key)
    visited[key] = true
    local module = assert(db:Get(moduleName), "AtlasLoot linked module missing: " .. moduleName)
    local content = assert(module[contentKey], "AtlasLoot content missing: " .. key)
    local boss = assert(content.items[bossIndex], "AtlasLoot boss missing: " .. key)
    if boss.link then return resolveBoss(db, boss.link[1], boss.link[2], boss.link[3], visited) end
    return moduleName, contentKey, bossIndex, module, content, boss
end

-- Faction replacements belong to the row schema; never mutate AtlasLoot's shared rows.
local function emitRow(atlas, formatTable, row, faction, emit)
    local own, other
    if faction == "horde" then own, other = row[ATLASLOOT_IT_HORDE], row[ATLASLOOT_IT_ALLIANCE]
    else own, other = row[ATLASLOOT_IT_ALLIANCE], row[ATLASLOOT_IT_HORDE] end
    if own == false or (own == nil and other ~= nil and other ~= false) then return end
    for column = 1, 2 do
        local value = row[column + 1]
        if type(own) == "table" and own[column] ~= nil then value = own[column]
        elseif column == 1 and type(own) == "number" then value = own end
        emitValue(atlas, formatTable[column], value, emit)
    end
end

-- Runs inside the source manager's coroutine. checkpoint yields without publishing partial data.
function Adapter.Scan(disabledSources, emitChoice, emitItem, checkpoint)
    assert(Adapter.IsAvailable(), "AtlasLoot Forever is not loaded")
    assert(not InCombatLockdown(), "AtlasLoot data loading is deferred until combat ends")
    local atlas, faction = AtlasLoot, string.lower(UnitFactionGroup("player") or "")
    local moduleList = modules(atlas)
    assert(#moduleList > 0, "No enabled AtlasLoot loot modules found")
    -- Preload dependencies so public ItemDB link resolution is synchronous.
    for _, entry in ipairs(moduleList) do
        atlas.Loader:LoadModule(entry.addonName)
        assert(atlas.Loader:IsModuleLoaded(entry.addonName), "Cannot load AtlasLoot module: " .. entry.addonName)
        checkpoint()
    end
    for _, entry in ipairs(moduleList) do
        local db, moduleName = atlas.ItemDB, entry.addonName
        local module = assert(db:Get(moduleName), "AtlasLoot module has no database: " .. moduleName)
        for _, contentKey in ipairs(db:GetModuleList(moduleName)) do
            local content = module[contentKey]
            if content.gameVersion == 0 or content.gameVersion == atlas:GetGameVersion() then
                local sourceKey = moduleName .. ":" .. contentKey
                local place = clean(content:GetName(true))
                emitChoice({ key = sourceKey, label = place, group = clean(entry.name) })
                if not disabledSources[sourceKey] then
                    for bossIndex in ipairs(content.items) do
                        local targetModule, targetKey, targetBoss, targetDB, targetContent, boss =
                            resolveBoss(db, moduleName, contentKey, bossIndex, {})
                        local source = clean(content:GetNameForItemTable(bossIndex, true))
                        if source == "Unknown" then source = clean(targetContent:GetNameForItemTable(targetBoss, true)) end
                        for difficulty, info in ipairs(targetDB:GetDifficultys()) do
                            local uniqueName = info.uniqueName
                            local allowed = (uniqueName ~= "alliance" and uniqueName ~= "horde") or uniqueName == faction
                            if boss[difficulty] ~= nil and allowed then
                                local rows, formatTable = db:GetItemTable(targetModule, targetKey, targetBoss, difficulty)
                                assert(type(rows) == "table" and type(formatTable) == "table", "Unsupported AtlasLoot item table: " .. sourceKey)
                                local label = not info.textIsHidden and clean(info.name) or nil
                                local mapping = { place = place, source = source, difficultyLabel = label }
                                for _, row in ipairs(rows) do
                                    assert(type(row) == "table", "Unsupported AtlasLoot row: " .. sourceKey)
                                    emitRow(atlas, formatTable, row, faction, function(id) emitItem(id, mapping) end)
                                    checkpoint()
                                end
                            end
                        end
                    end
                end
                checkpoint()
            end
        end
    end
end
