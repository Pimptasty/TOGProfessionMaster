-- TOG Profession Master — Craft Queue (model + completion tracking)
--
-- The queue is an ORDERED array persisted at Ace.db.char.craftQueue. Order IS
-- the user's stack rank (drag-to-reorder in the UI); Craft Next always takes
-- the highest-priority entry that can be crafted right now. Each entry:
--   { profId = <number>, recipeId = <number>, qty = <number> }
--
-- COMPLETION TRACKING (the "flawless" requirement): crafting a stack with
-- DoTradeSkill(index, n) produces items one at a time, each firing
-- UNIT_SPELLCAST_SUCCEEDED for the player. We decrement the queue entry by one
-- per success, so the queue always reflects reality — if the player moves and
-- interrupts mid-stack, the remaining count stays queued (we do NOT optimistically
-- remove it). UNIT_SPELLCAST_INTERRUPTED / _FAILED end the active batch, leaving
-- the remainder in place.
--
-- Craft execution itself (DoTradeSkill / DoCraft, version-branched, index
-- re-resolved by recipeId) lives in CraftingEngine:Craft. This module decides
-- WHAT to craft and tracks progress; the engine does the casting.

local _, addon = ...
local Ace = addon.lib

local CraftQueue = {}
addon.CraftQueue = CraftQueue

-- In-memory tracker for the batch currently being crafted (not persisted —
-- it's transient and rebuilt on demand). { recipeId, profId, remaining }.
CraftQueue._active = nil

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
local function queue()
    local d = Ace.db and Ace.db.char
    if not d then return {} end
    if not d.craftQueue then d.craftQueue = {} end
    return d.craftQueue
end

local function findIndex(q, profId, recipeId)
    for i, e in ipairs(q) do
        if e.profId == profId and e.recipeId == recipeId then return i end
    end
end

function CraftQueue:Get()   return queue() end
function CraftQueue:Count() return #queue() end
function CraftQueue:IsEmpty() return #queue() == 0 end

-- ---------------------------------------------------------------------------
-- Mutations (each fires a UI refresh)
-- ---------------------------------------------------------------------------

-- Add qty for a recipe. If already queued, accumulate (keeping its rank);
-- otherwise append to the BOTTOM so existing priorities are preserved.
function CraftQueue:Add(profId, recipeId, qty)
    if not profId or not recipeId then return end
    qty = math.max(1, math.floor(qty or 1))
    local q = queue()
    local i = findIndex(q, profId, recipeId)
    if i then
        q[i].qty = q[i].qty + qty
    else
        q[#q + 1] = { profId = profId, recipeId = recipeId, qty = qty }
    end
    self:_Changed()
end

function CraftQueue:SetQty(index, qty)
    local q = queue()
    if not q[index] then return end
    qty = math.floor(qty or 0)
    if qty <= 0 then table.remove(q, index) else q[index].qty = qty end
    self:_Changed()
end

function CraftQueue:Remove(index)
    local q = queue()
    if q[index] then table.remove(q, index); self:_Changed() end
end

function CraftQueue:Clear()
    local q = queue()
    for i = #q, 1, -1 do q[i] = nil end
    self._active = nil
    self:_Changed()
end

-- Drag-to-reorder: move the entry at `from` to position `to` (1 = top).
function CraftQueue:Move(from, to)
    local q = queue()
    if not q[from] then return end
    to = math.max(1, math.min(#q, to))
    if from == to then return end
    local e = table.remove(q, from)
    table.insert(q, to, e)
    self:_Changed()
end

-- ---------------------------------------------------------------------------
-- Craft Next — top-down, eligibility-gated
-- ---------------------------------------------------------------------------

-- The index of the highest-priority entry that can be crafted RIGHT NOW: its
-- profession is the open one and it has at least one craftable with current
-- mats. Returns (queueIndex, liveRecipeEntry) or nil.
function CraftQueue:NextEligible()
    local Engine = addon.CraftingEngine
    local info = Engine and Engine:GetOpenInfo()
    if not info then return nil end
    local q = queue()
    for i, e in ipairs(q) do
        if e.profId == info.profId then
            local entry = Engine:GetRecipeEntry(e.recipeId)
            if entry and (entry.num or 0) > 0 then
                return i, entry
            end
        end
    end
    return nil
end

function CraftQueue:CanCraftNext()
    return self:NextEligible() ~= nil
end

-- Start crafting the top eligible entry. We craft min(queued qty, craftable-
-- with-mats); completion tracking decrements the entry per finished craft.
function CraftQueue:CraftNext()
    local Engine = addon.CraftingEngine
    if not Engine then return end
    local i, entry = self:NextEligible()
    if not i then return end
    local e = queue()[i]
    local count = math.min(e.qty, entry.num or e.qty)
    if count < 1 then return end

    self._active = { recipeId = e.recipeId, profId = e.profId, remaining = count }
    Engine:Craft(e.recipeId, entry.index, count)
end

-- ---------------------------------------------------------------------------
-- Completion tracking
-- ---------------------------------------------------------------------------
function CraftQueue:_OnCraftSuccess()
    local active = self._active
    if not active then return end

    active.remaining = active.remaining - 1

    local q = queue()
    local i = findIndex(q, active.profId, active.recipeId)
    if i then
        q[i].qty = q[i].qty - 1
        if q[i].qty <= 0 then table.remove(q, i) end
    end

    if active.remaining <= 0 then self._active = nil end
    self:_Changed()
end

local trackFrame = CreateFrame("Frame")
trackFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
trackFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
trackFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
trackFrame:SetScript("OnEvent", function(_, event, unit)
    if unit ~= "player" then return end
    if not CraftQueue._active then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        CraftQueue:_OnCraftSuccess()
    else
        -- Batch interrupted/failed: stop tracking; the unmade remainder stays
        -- in the queue exactly as the completion model promises.
        CraftQueue._active = nil
        CraftQueue:_Changed()
    end
end)

-- ---------------------------------------------------------------------------
-- UI refresh hook
-- ---------------------------------------------------------------------------
function CraftQueue:_Changed()
    if addon.CraftingTab and addon.CraftingTab.OnQueueChanged then
        addon.CraftingTab:OnQueueChanged()
    end
end
