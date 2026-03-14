local addonName, addon = ...

local Query = {}
_G.ItemScoreQuery = Query

--------------------------------------------------
-- internal state
--------------------------------------------------
local queue = {}
local queued = {}

local hiddenTooltip = CreateFrame("GameTooltip", "ISQHiddenTooltip", nil, "GameTooltipTemplate")
hiddenTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local driver = CreateFrame("Frame")
local listeners = {}
local isSearching = false
local searchTimeWaitAfter = 0
local function process(id) hiddenTooltip:SetHyperlink("item:" .. id .. ":::::::::") end

driver:SetScript("OnUpdate", function(_, elapsed)
	if #queue == 0 then
		searchTimeWaitAfter = searchTimeWaitAfter - elapsed
		if (searchTimeWaitAfter <= 0) then
			isSearching = false
			driver:Hide()
			if #listeners > 0 then
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
