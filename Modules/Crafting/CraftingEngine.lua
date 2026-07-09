-- TOG Profession Master — Crafting Engine (window-hijack controller)
--
-- This module is the "make-or-break" piece of the Crafting tab: it lets TOGPM
-- REPLACE the default Blizzard profession window with our own tab, the same way
-- TradeSkillMaster reskins it. We don't copy TSM's code — we use the same
-- well-known mechanism:
--
--   1. UIParent has a built-in handler that auto-opens Blizzard's profession
--      window whenever TRADE_SKILL_SHOW (or, on Vanilla/TBC, CRAFT_SHOW) fires.
--      We `UIParent:UnregisterEvent(...)` those so the default window NEVER
--      auto-pops.
--   2. We listen for the same events on our OWN frame and decide what to show:
--      our Crafting tab (takeover ON) or — via the escape button / takeover
--      OFF — Blizzard's real window, summoned on demand by re-dispatching the
--      event through UIParent_OnEvent().
--
-- The trade-skill / craft API (GetTradeSkillInfo, GetCraftInfo, DoTradeSkill,
-- DoCraft, reagent reads) stays valid for the ENTIRE open session even while
-- Blizzard's frame is hidden — that is what makes a reskin possible. We read
-- and craft through the live API; Blizzard's frame is purely cosmetic.
--
-- Why our own CreateFrame instead of AceEvent: Scanner.lua already owns
-- TRADE_SKILL_SHOW / CRAFT_SHOW via Ace:RegisterEvent, and AceEvent keeps only
-- ONE handler per event per object (the whole addon is one Ace object). A
-- second Ace:RegisterEvent here would clobber the scanner. A dedicated frame is
-- fully independent, and our UIParent:UnregisterEvent does NOT affect AceEvent
-- (AceEvent uses its own hidden frame), so scanning keeps working untouched.
--
-- Version branching (per the multi-version rule): the separate "Craft" window
-- (Enchanting / weapon crafting via CRAFT_SHOW / DoCraft / GetCraftInfo) exists
-- on Vanilla and TBC only — Wrath merged it into the trade-skill window, so
-- Wrath / Cata / MoP only ever see TRADE_SKILL_SHOW. HAS_CRAFT_WINDOW gates all
-- craft-window handling so earlier-removed globals are never touched on newer
-- clients.

local _, addon = ...
local Ace = addon.lib

local Engine = {}
addon.CraftingEngine = Engine

-- Vanilla + TBC have the separate Craft window; Wrath+ do not.
local HAS_CRAFT_WINDOW = addon.isVanilla or addon.isTBC

-- ---------------------------------------------------------------------------
-- Session state
-- ---------------------------------------------------------------------------
-- _tradeOpen / _craftOpen mirror TSM's flags: the two windows are mutually
-- exclusive (opening one closes the other), and the mutual-exclusion close
-- fires a *_CLOSE event we must NOT mistake for the user walking away. The
-- guards in OnEvent ("close only if the OTHER window isn't open") keep a
-- handoff between the two from collapsing the whole session.
Engine._tradeOpen     = false   -- the trade-skill session is open server-side
Engine._craftOpen     = false   -- the craft-window session is open (Vanilla/TBC)
Engine._sessionOpen   = false   -- either of the above (the public "is open")
Engine._isCraftWindow = false   -- the currently-open session is the Craft window
Engine._autoOpened    = false   -- WE opened the main window for this takeover
Engine._showingDefault = false  -- Blizzard's frame is the active view this session
Engine._toggleBtn     = nil     -- "back to TOGPM" button injected on Blizzard's frame
Engine._suppressUpdate = false  -- guard: ignore TRADE_SKILL_UPDATE while we mutate the list
Engine._closePending  = false   -- a debounced teardown is scheduled (see ScheduleClose)
Engine._forceTakeoverOnce = false -- next show opens TOGPM regardless of the default (set by OpenProfession)
Engine._hookedFrames  = {}      -- Blizzard frames whose OnShow we've hooked to inject the TOGPM toggle button

-- ---------------------------------------------------------------------------
-- Which crafting UI opens when you open a profession. Default: Blizzard's own
-- window (with the TOGPM toggle button on it to switch). Two opt-in settings,
-- both OFF by default:
--   profile.craftingTakeover     — open the TOGPM Crafting tab instead
--   profile.craftingRememberLast — reopen whichever UI you used last; when a
--                                  choice is saved it WINS over craftingTakeover
--   char.craftingLastUI          — "togpm" | "blizzard", the per-character last
--                                  choice (recorded whenever a UI is shown)
-- The TOGPM button on Blizzard's frame and the "WoW UI" button on our tab let
-- the user switch at any time; that switch is what craftingLastUI captures.
-- ---------------------------------------------------------------------------
function Engine:IsTakeoverEnabled()
    local p = Ace.db and Ace.db.profile
    return (p and p.craftingTakeover) == true
end

-- Master switch (default ON): when hands-off, TOGPM does NOT touch the crafting
-- window at all — it doesn't unregister Blizzard's auto-show, force a window, or
-- inject the toggle button. Blizzard's UI (or TSM/Skillet) owns the window; we
-- only track the session so the manually-opened Crafting tab still works. nil
-- (never set) reads as ON so existing installs default to hands-off.
function Engine:IsHandsOff()
    local p = Ace.db and Ace.db.profile
    if not p or p.craftingHandsOff == nil then return true end
    return p.craftingHandsOff == true
end

function Engine:SetTakeoverEnabled(on)
    if Ace.db and Ace.db.profile then
        Ace.db.profile.craftingTakeover = on and true or false
    end
end

-- Decide whether a fresh profession show opens the TOGPM tab (true) or
-- Blizzard's window (false). Remember-last wins when a per-character choice is
-- saved; otherwise the craftingTakeover default (off → Blizzard) applies.
function Engine:ShouldTakeoverOnShow()
    local p = Ace.db and Ace.db.profile
    if p and p.craftingRememberLast then
        local last = Ace.db.char and Ace.db.char.craftingLastUI
        if last == "togpm"    then return true  end
        if last == "blizzard" then return false end
    end
    return self:IsTakeoverEnabled()
end

-- Record which crafting UI is now showing so "remember last" can reopen it.
function Engine:_RecordLastUI(which)
    if Ace.db and Ace.db.char then Ace.db.char.craftingLastUI = which end
end

-- ---------------------------------------------------------------------------
-- Live reads off the open window
-- ---------------------------------------------------------------------------
-- Returns nil when no profession is open, else a small descriptor the view
-- uses to render its header. profId is resolved through the Scanner's existing
-- name→id map so it matches addon.recipeDB keys.
function Engine:GetOpenInfo()
    if not self._sessionOpen then return nil end

    local name, rank, max
    if self._isCraftWindow then
        if GetCraftDisplaySkillLine then name, rank, max = GetCraftDisplaySkillLine() end
    else
        if GetTradeSkillLine then name, rank, max = GetTradeSkillLine() end
    end
    if not name or name == "" or name == "UNKNOWN" then return nil end

    local profId = addon.Scanner and addon.Scanner:ResolveProfessionId(name) or nil
    return {
        name          = name,
        rank          = rank or 0,
        max           = max or 0,
        profId        = profId,
        isCraftWindow = self._isCraftWindow,
    }
end

function Engine:IsOpen()
    return self._sessionOpen
end

-- Gathering professions have no craftable window, so they never belong in the
-- crafting dropdown: Fishing (356), Herbalism (182), Skinning (393).
local NO_CRAFT_WINDOW = { [356] = true, [182] = true, [393] = true }

-- The player's own craftable professions, available WITHOUT any window open so
-- the tab can prepopulate its dropdown. Returns
--   { name, castName, profId, rank, max }
-- where `castName` is what OpenProfession() casts (= name, except Mining whose
-- craft window is opened by casting Smelting).
--
-- Version-robust source (per the multi-version rule): GetProfessions /
-- GetProfessionInfo only exist from Cataclysm on (they return nothing on
-- Classic Era — the same reason Scanner:ResolveProfessionId keeps a fallback),
-- so we use them for Cata/MoP and fall back to the classic skill API
-- (GetNumSkillLines / GetSkillLineInfo) on Era / TBC / Wrath.
function Engine:GetKnownProfessions()
    local out, seen = {}, {}

    local function tryAdd(name, rank, max, profId)
        if not name or name == "" then return end
        profId = profId or (addon.Scanner and addon.Scanner:ResolveProfessionId(name))
        if not profId or NO_CRAFT_WINDOW[profId] or seen[profId] then return end
        seen[profId] = true
        local castName = name
        if profId == 186 and GetSpellInfo then        -- Mining → cast Smelting (spell 2656)
            castName = GetSpellInfo(2656) or name
        end
        out[#out + 1] = {
            name = name, castName = castName, profId = profId,
            rank = rank or 0, max = max or 0,
        }
    end

    -- Cata/MoP path.
    if GetProfessions then
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local name, _icon, rank, max, _, _, skillLine = GetProfessionInfo(idx)
                tryAdd(name, rank, max, skillLine)
            end
        end
    end

    -- Classic skill-API path (Era / TBC / Wrath) — also the fallback if the
    -- Cata path yielded nothing.
    if #out == 0 and GetNumSkillLines then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if name and not isHeader then
                tryAdd(name, rank, maxRank, nil)
            end
        end
    end

    return out
end

-- Open a profession's window by casting it (the spellbook profession entry is
-- castable and opens the trade-skill / craft window). TRADE_SKILL_SHOW /
-- CRAFT_SHOW then fires and our handler takes over with live data. Casting is
-- a no-op in combat (the window can't open then), so we guard and report it.
--
-- This is only ever called from the Crafting TAB (its profession dropdown / the
-- "Open <profession>" button), i.e. the user explicitly wants the result IN
-- TOGPM — so force the next show to open the TOGPM tab regardless of the
-- default-to-Blizzard setting (otherwise clicking "Open Enchanting" inside the
-- TOGPM tab would pop the Blizzard window instead). One-shot; consumed by the
-- next OnProfessionShow.
function Engine:OpenProfession(name)
    if not name then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        addon:Print(addon.L and addon.L["CraftCantOpenInCombat"] or "Can't open a profession in combat.")
        return false
    end
    self._forceTakeoverOnce = true
    if CastSpellByName then CastSpellByName(name) end
    return true
end

-- Native difficulty-tier colours (match Blizzard's TradeSkillTypeColor). The
-- recipe name is tinted by how trivial the craft is — the same data the
-- default window uses, free from GetTradeSkillInfo / GetCraftInfo.
Engine.DIFFICULTY_COLOR = {
    optimal = "ffff8040",  -- orange  (guaranteed skill-up)
    medium  = "ffffff00",  -- yellow  (high skill-up chance)
    easy    = "ff40c040",  -- green   (low skill-up chance)
    trivial = "ff808080",  -- grey    (no skill-up)
}

local TIER_HEX = { "ffff8040", "ffffff00", "ff40c040", "ff808080" }  -- orange/yellow/green/grey

-- Colored, space-separated tier string from the recipe's difficulty array:
-- orange yellow green grey. The data is now authoritative (the build tool
-- corrects the orange/tiers for pattern recipes — see
-- tools/build_authoritative_data.py), so this just colours the four values;
-- no runtime fix-ups. Falls back to a single requiredSkill when there's no
-- difficulty array, and "-" when there's nothing.
function addon.FormatSkillTiers(tiers, requiredSkill)
    if not tiers then
        return requiredSkill and ("|c" .. TIER_HEX[1] .. requiredSkill .. "|r") or "-"
    end
    local parts = {}
    for i = 1, 4 do
        local v = tiers[i]
        if v then parts[#parts + 1] = "|c" .. TIER_HEX[i] .. tostring(v) .. "|r" end
    end
    return (#parts > 0) and table.concat(parts, " ") or "-"
end

-- Read the live recipe list off the open window. Returns an ordered array of
-- entries the view renders in place:
--   { kind = "header", name = <category> }
--   { kind = "recipe", index = <live index>, name, difficulty, num, recipeId }
-- `index` is the positional index the craft API addresses (DoTradeSkill /
-- DoCraft); `num` is numAvailable (the "Craft" count = how many you can make
-- now with mats on hand); `recipeId` links to addon.recipeDB for icons.
--
-- We expand every collapsed category first so nothing is hidden, guarded by
-- _suppressUpdate: ExpandTradeSkillSubClass fires TRADE_SKILL_UPDATE, and
-- without the guard our UPDATE handler would redraw → re-read → expand →
-- UPDATE in an infinite loop.
-- Shipped recipe metadata for (profId, recipeId), with the Vanilla item→spell
-- remap: on Vanilla, ExtractTradeSkillId returns the crafted item id but
-- addon.recipeDB is keyed by spell id, so fall back through
-- GetSpellIdForCraftedItem (same remap Scanner:MergeRecipesIntoGdb uses).
local function recipeMeta(profId, rid)
    if not (profId and rid and addon.recipeDB and addon.recipeDB[profId]) then return nil end
    local m = addon.recipeDB[profId][rid]
    if m then return m end
    if addon.GetSpellIdForCraftedItem then
        local sid = addon:GetSpellIdForCraftedItem(profId, rid)
        if sid then return addon.recipeDB[profId][sid] end
    end
    return nil
end

-- Item-quality colour hex (e.g. "ff1eff00") from the crafted item's link, used
-- to tint the recipe name like the in-game item. nil when no link/colour.
local function linkColour(link)
    return link and link:match("|c(%x%x%x%x%x%x%x%x)") or nil
end

-- Craftable count from reagents: min over floor(have/need). Repairs the API's
-- numAvailable, which reads 0 for recipes that produce no item — enchants. That
-- happens on BOTH the Craft API (GetCraftInfo) and, on clients that route
-- Enchanting through the trade-skill UI instead, GetTradeSkillInfo — so the same
-- repair has to cover both. `numReagents`/`reagentInfo` are the matching API
-- pair; `fallback` is returned when there are no reagents to measure. The
-- enchanting ROD is a spell-focus, not a reagent, so it never appears here.
local function matsCraftable(numReagents, reagentInfo, index, fallback)
    local n = numReagents and numReagents(index) or 0
    if n == 0 then return fallback or 0 end
    local num = math.huge
    for j = 1, n do
        local _, _, need, have = reagentInfo(index, j)
        if need and need > 0 then
            num = math.min(num, math.floor((have or 0) / need))
        end
    end
    return (num == math.huge) and (fallback or 0) or num
end

-- Craft window (Enchanting on Vanilla/TBC): numAvailable is unreliable (0 even
-- with mats — TSM ignores it too), so derive from mats first.
local function craftWindowCraftable(index, numAvailable)
    return matsCraftable(GetCraftNumReagents, GetCraftReagentInfo, index, numAvailable)
end

-- Trade-skill window: numAvailable IS reliable for item-producing recipes, so
-- trust it; only when it reads 0 fall back to a mats count. That rescues no-item
-- recipes (e.g. Enchanting if this client routes it through the trade-skill UI)
-- while leaving genuinely unmakeable rows at 0 (no mats → mats count is 0 too).
local function tradeSkillCraftable(index, numAvailable)
    if numAvailable and numAvailable > 0 then return numAvailable end
    return matsCraftable(GetTradeSkillNumReagents, GetTradeSkillReagentInfo, index, numAvailable or 0)
end

function Engine:GetRecipeList()
    if not self._sessionOpen then return {} end
    local out = {}
    local profId = (self:GetOpenInfo() or {}).profId
    self._suppressUpdate = true

    if self._isCraftWindow then
        local n = GetNumCrafts and GetNumCrafts() or 0
        for i = 1, n do
            local name, _, ctype, numAvailable = GetCraftInfo(i)
            if name and name ~= "" then
                if ctype == "header" then
                    out[#out + 1] = { kind = "header", name = name }
                else
                    local link = GetCraftItemLink and GetCraftItemLink(i)
                    local rid  = link and tonumber(link:match("enchant:(%d+)")) or nil
                    local meta = recipeMeta(profId, rid)
                    out[#out + 1] = {
                        kind = "recipe", index = i, name = name,
                        difficulty = ctype, num = craftWindowCraftable(i, numAvailable), recipeId = rid,
                        icon = GetCraftIcon and GetCraftIcon(i) or nil,
                        link = link, color = linkColour(link),
                        requiredSkill = meta and meta.requiredSkill or nil,
                        tiers = meta and meta.difficulty or nil,  -- {orange,yellow,green,grey}
                        effect = meta and (addon:GetCraftedItemStatText(meta.craftedItemId) or meta.effect) or nil,  -- crafted consumable's use-effect buff (LibItemDB) wins; enchant effect (ProfessionDB) is the fallback
                    }
                end
            end
        end
    else
        if ExpandTradeSkillSubClass then
            for i = (GetNumTradeSkills() or 0), 1, -1 do
                local _, ttype, _, isExpanded = GetTradeSkillInfo(i)
                if ttype == "header" and not isExpanded then
                    ExpandTradeSkillSubClass(i)
                end
            end
        end
        local n = GetNumTradeSkills() or 0
        for i = 1, n do
            local name, ttype, numAvailable = GetTradeSkillInfo(i)
            if name and name ~= "" then
                if ttype == "header" or ttype == "subheader" then
                    out[#out + 1] = { kind = "header", name = name }
                else
                    local rid  = addon.Scanner and addon.Scanner:ExtractTradeSkillId(i) or nil
                    local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
                    local meta = recipeMeta(profId, rid)
                    out[#out + 1] = {
                        kind = "recipe", index = i, name = name,
                        difficulty = ttype, num = tradeSkillCraftable(i, numAvailable), recipeId = rid,
                        icon = GetTradeSkillIcon and GetTradeSkillIcon(i) or nil,
                        link = link, color = linkColour(link),
                        requiredSkill = meta and meta.requiredSkill or nil,
                        tiers = meta and meta.difficulty or nil,  -- {orange,yellow,green,grey}
                        effect = meta and (addon:GetCraftedItemStatText(meta.craftedItemId) or meta.effect) or nil,  -- crafted consumable's use-effect buff (LibItemDB) wins; enchant effect (ProfessionDB) is the fallback
                    }
                end
            end
        end
    end

    self._suppressUpdate = false
    return out
end

-- Reagents for one recipe index, with live have/need counts straight from the
-- API (have = playerReagentCount, need = reagentCount). Version-branched.
function Engine:GetReagents(index)
    if not index then return {} end
    local out = {}
    if self._isCraftWindow then
        local n = GetCraftNumReagents and GetCraftNumReagents(index) or 0
        for j = 1, n do
            local name, tex, need, have = GetCraftReagentInfo(index, j)
            local link = GetCraftReagentItemLink and GetCraftReagentItemLink(index, j)
            out[#out + 1] = { name = name, texture = tex, need = need or 0, have = have or 0,
                link = link, itemId = link and tonumber(link:match("item:(%d+)")) or nil }
        end
    else
        local n = GetTradeSkillNumReagents and GetTradeSkillNumReagents(index) or 0
        for j = 1, n do
            local name, tex, need, have = GetTradeSkillReagentInfo(index, j)
            local link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(index, j)
            out[#out + 1] = { name = name, texture = tex, need = need or 0, have = have or 0,
                link = link, itemId = link and tonumber(link:match("item:(%d+)")) or nil }
        end
    end
    return out
end

-- Resolve the live positional index for a recipeId in the open window. Indices
-- shift with filter/expand state, so re-resolving by id right before a craft
-- avoids DoTradeSkill / DoCraft firing on the wrong (stale) index.
function Engine:ResolveIndex(recipeId)
    if not recipeId then return nil end
    for _, e in ipairs(self:GetRecipeList()) do
        if e.kind == "recipe" and e.recipeId == recipeId then
            return e.index
        end
    end
    return nil
end

-- Live recipe entry (index, num, name, icon, difficulty) for a recipeId in the
-- open window, or nil if it isn't in the current list. Used by the queue to
-- check craftability (num > 0) and resolve the index for crafting.
function Engine:GetRecipeEntry(recipeId)
    if not recipeId then return nil end
    for _, e in ipairs(self:GetRecipeList()) do
        if e.kind == "recipe" and e.recipeId == recipeId then
            return e
        end
    end
    return nil
end

-- Execute a craft. Version-branched: DoTradeSkill(index, repeats) on the
-- trade-skill window (all versions); DoCraft(index) on the Vanilla/TBC Craft
-- window (single craft only — no repeat parameter, so qty is ignored there).
-- recipeId re-resolves the index defensively; falls back to the passed index.
function Engine:Craft(recipeId, index, qty)
    if not self._sessionOpen then return end
    local liveIndex = self:ResolveIndex(recipeId) or index
    if not liveIndex then return end
    qty = math.max(1, qty or 1)
    -- Tell the queue what we're about to craft so a queued recipe decrements as
    -- it's made — through THIS one chokepoint, so it works whether the craft was
    -- started by Craft Next OR the detail-panel Craft button (previously only
    -- Craft Next tracked, so manual crafts left finished items stuck in queue).
    -- The Craft window (Enchanting) makes exactly one per DoCraft — no repeat
    -- arg — so the queue should expect a single success there, not `qty`.
    -- The Vanilla/TBC Craft API (Enchanting) applies via DoCraft, which is a
    -- PROTECTED function — an addon calling it trips ADDON_ACTION_FORBIDDEN and
    -- the craft is blocked. (DoTradeSkill, used by every other profession, is
    -- NOT protected.) So we cannot apply an enchant ourselves: pop Blizzard's own
    -- Craft window so the player clicks its secure Create button, and say so once.
    if self._isCraftWindow then
        self:ShowDefaultUI()
        local now = GetTime and GetTime() or 0
        if now - (self._enchantNoticeAt or 0) > 8 then
            self._enchantNoticeAt = now
            addon:Print(addon.L and addon.L["CraftEnchantViaBlizzard"]
                or "Enchants are applied from Blizzard's Craft window — opened it; click Create there.")
        end
        return
    end
    -- Trade skills: track for the queue, then craft (the API handles repeats).
    if addon.CraftQueue and addon.CraftQueue.TrackCraft then
        addon.CraftQueue:TrackCraft(recipeId, qty)
    end
    if DoTradeSkill then DoTradeSkill(liveIndex, qty) end
end

-- ---------------------------------------------------------------------------
-- Event plumbing
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

-- Load Blizzard_CraftUI ourselves and stop its frame from auto-popping. Only
-- meaningful on Vanilla/TBC (HAS_CRAFT_WINDOW) and only when we've taken over
-- CRAFT_SHOW from UIParent. Blizzard_CraftUI is a load-on-demand addon; the
-- default UIParent CRAFT_SHOW handler is what normally loads it, and once loaded
-- CraftFrame registers its own CRAFT_SHOW to ShowUIPanel(CraftFrame). We want the
-- frames to EXIST (so co-installed CRAFT_SHOW listeners like Auctionator can read
-- CraftReagent1..N) without the window showing — so load it, then unregister
-- CraftFrame's CRAFT_SHOW. ShowDefaultUI summons it via UIParent_OnEvent(), which
-- calls into the loader/ShowUIPanel path directly and does not depend on
-- CraftFrame's own registration, so the escape-to-Blizzard button still works.
function Engine:AssumeCraftUILoadResponsibility()
    if not HAS_CRAFT_WINDOW or self._craftUILoadAssumed then return end
    self._craftUILoadAssumed = true

    local loadIt = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
    if loadIt and not addon:IsAddOnLoaded("Blizzard_CraftUI") then
        pcall(loadIt, "Blizzard_CraftUI")
    end

    if _G.CraftFrame and _G.CraftFrame.UnregisterEvent then
        _G.CraftFrame:UnregisterEvent("CRAFT_SHOW")
    end
end

function Engine:Init()
    -- Suppress Blizzard's auto-show ONLY when we're going to manage the window
    -- ourselves. In hands-off mode (default) we leave UIParent's handler intact
    -- so Blizzard's window (or whatever TSM/Skillet does) behaves natively — we
    -- never put a second window on screen. We still register our own event frame
    -- below either way, because the Crafting tab relies on the session tracking.
    if not self:IsHandsOff() then
        UIParent:UnregisterEvent("TRADE_SKILL_SHOW")
        if HAS_CRAFT_WINDOW then
            UIParent:UnregisterEvent("CRAFT_SHOW")
            -- UIParent's CRAFT_SHOW handler is the ONLY thing that lazy-loads
            -- Blizzard_CraftUI (which creates the CraftReagent1..N frames). Having
            -- unregistered it, we now own that responsibility: other addons that
            -- also hook CRAFT_SHOW (e.g. Auctionator's CraftShown) index those
            -- globals and would nil-error if the addon never loaded. Load it here
            -- so the frames exist, then unregister CraftFrame's own CRAFT_SHOW so
            -- it doesn't auto-pop a second window over our tab — we still summon it
            -- on demand via UIParent_OnEvent() in ShowDefaultUI, which is unaffected.
            self:AssumeCraftUILoadResponsibility()
        end
    end

    eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
    eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
    eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
    if HAS_CRAFT_WINDOW then
        eventFrame:RegisterEvent("CRAFT_SHOW")
        eventFrame:RegisterEvent("CRAFT_UPDATE")
        eventFrame:RegisterEvent("CRAFT_CLOSE")
    end
    eventFrame:SetScript("OnEvent", function(_, event) Engine:OnEvent(event) end)

    addon:DebugPrint("CraftingEngine: init (craft window:", tostring(HAS_CRAFT_WINDOW), ")")
end

function Engine:OnEvent(event)
    if event == "TRADE_SKILL_SHOW" then
        self._closePending = false   -- (re)opening: cancel any debounced teardown
        self._tradeOpen = true
        -- Hand off from the Craft window if it was open (mutual exclusion).
        -- CloseCraft fires CRAFT_CLOSE, but _tradeOpen is already true so the
        -- guard below won't treat it as a real session close.
        if HAS_CRAFT_WINDOW and CloseCraft then CloseCraft() end
        self._isCraftWindow = false
        self:OnProfessionShow()

    elseif event == "CRAFT_SHOW" then
        self._closePending = false
        self._craftOpen = true
        if CloseTradeSkill then CloseTradeSkill() end
        self._isCraftWindow = true
        self:OnProfessionShow()

    elseif event == "TRADE_SKILL_CLOSE" then
        self._tradeOpen = false
        self:ScheduleClose()

    elseif event == "CRAFT_CLOSE" then
        self._craftOpen = false
        self:ScheduleClose()

    elseif event == "TRADE_SKILL_UPDATE" or event == "CRAFT_UPDATE" then
        -- Skill rank / craftable counts may have changed (e.g. after a craft).
        -- Refresh the view if it's showing, but don't re-open anything. The
        -- _suppressUpdate guard breaks the expand-all → UPDATE → redraw →
        -- expand-all loop in GetRecipeList.
        if self._sessionOpen and not self._suppressUpdate then self:FireLiveUpdate() end
    end
end

-- Debounced teardown. A profession SWITCH (and rival reskin addons such as
-- Skillet that also hijack the trade/craft window) fire a *_CLOSE immediately
-- followed by a *_SHOW for the new profession. Tearing down synchronously on the
-- CLOSE collapsed our window in that gap — users running Skillet alongside TOGPM
-- reported "switching professions closes the TOGPM window," and disabling Skillet
-- made it go away. So we wait a short grace period and only tear down if BOTH
-- windows are still closed (a real walk-away, not a handoff). The SHOW handler
-- clears _closePending; the both-closed guard is the real safety net — it also
-- covers the mutual-exclusion CloseTradeSkill / CloseCraft we fire ourselves
-- (which re-sets the flag but leaves the other window open, so no teardown).
function Engine:ScheduleClose()
    self._closePending = true
    local function check()
        if self._closePending and not self._tradeOpen and not self._craftOpen then
            self._closePending = false
            self:OnProfessionClose()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, check)
    else
        check()  -- no timer API (defensive): preserve the old immediate close
    end
end

-- ---------------------------------------------------------------------------
-- Show / close transitions
-- ---------------------------------------------------------------------------
function Engine:OnProfessionShow()
    self._sessionOpen = true

    -- Hands-off (default): never add a window the user didn't ask for. Two cases:
    if self:IsHandsOff() then
        local force = self._forceTakeoverOnce
        self._forceTakeoverOnce = false
        if force then
            -- Explicit tab action: the user navigated to the TOGPM Crafting tab
            -- (OpenProfession casts the profession to read it, which pops the
            -- Blizzard/TSM window). Suppress that window — we just show our tab.
            -- ShowOurUI hides it safely (the trade-skill session stays open, so
            -- the tab reads live data) and shows our tab; the tab's "WoW UI"
            -- button brings Blizzard back. Call it immediately (when UIParent's
            -- handler already showed the frame, it's hidden the same frame → no
            -- flicker) AND deferred (covers the frame being shown/created after
            -- this handler). ShowOurUI also fires the view update.
            self:ShowOurUI()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() self:ShowOurUI() end)
            end
        else
            -- Automatic profession open: stay fully hands-off, but keep our
            -- "TOGPM" toggle button riding on Blizzard's frame whenever it shows
            -- so a non-TSM user can still jump to the TOGPM Crafting tab. A TSM
            -- user whose Blizzard frame stays hidden never sees the button (its
            -- OnShow hook never fires) — exactly what they want. The deferred
            -- call covers Blizzard's load-on-demand frame not existing yet.
            self:EnsureToggleHook()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() self:EnsureToggleHook() end)
            end
            self:FireUpdate()
        end
        return
    end

    -- Ensure our toggle button is wired to ride on Blizzard's frame whenever it
    -- shows — even if a coexisting addon (TSM/Skillet) is what shows it, or it
    -- ends up visible alongside our taken-over tab. So closing the TOGPM window
    -- always leaves a way back on the Blizzard UI.
    self:EnsureToggleHook()

    -- A tab-initiated open (OpenProfession) forces the TOGPM tab this once,
    -- overriding the default-to-Blizzard rule AND a mid-session Blizzard choice.
    local force = self._forceTakeoverOnce
    self._forceTakeoverOnce = false

    -- Otherwise open Blizzard's window when takeover is off (the default), when
    -- remember-last points there, or when the user already chose it this
    -- session → hand off to the default frame (suppressed at Init) and stop.
    if not force and ((not self:ShouldTakeoverOnShow()) or self._showingDefault) then
        self:ShowDefaultUI()
        self:FireUpdate()
        return
    end

    -- Take over: open our window on the Crafting tab. Blizzard's frame was
    -- never shown (we suppressed the event), so there's nothing to hide.
    --
    -- Fail-safe: if opening our UI errors, fall back to Blizzard's window so
    -- the player is NEVER left unable to use a profession (the show event was
    -- suppressed — without this they'd have no window at all). Also their
    -- escape during development if the reskin breaks: `/togpm craft off`.
    self._autoOpened = true
    local ok = true
    if addon.MainWindow then
        ok = pcall(function() addon.MainWindow:Open("crafting") end)
    end
    if not ok then
        addon:DebugPrint("CraftingEngine: takeover failed — falling back to Blizzard UI")
        self._autoOpened = false
        self:ShowDefaultUI()
        return
    end
    self:_RecordLastUI("togpm")
    self:FireUpdate()
end

function Engine:OnProfessionClose()
    local wasAuto = self._autoOpened

    self._sessionOpen   = false
    self._isCraftWindow = false
    self._showingDefault = false
    self._autoOpened    = false
    self._forceTakeoverOnce = false
    self:HideToggleButton()

    -- If we auto-opened the window for this craft session and the user is
    -- still on the Crafting tab, fold it back down — mirrors the way the
    -- native window vanishes when you step away from the forge/anvil.
    if wasAuto and addon.MainWindow and addon.MainWindow.frame
       and addon.MainWindow.activeTab == "crafting" then
        addon.MainWindow:Close()
    end

    self:FireUpdate()
end

-- Summon Blizzard's real window. We unregistered the show event from UIParent,
-- so the default frame won't appear on its own — re-dispatch exactly the event
-- UIParent's handler expects. This loads Blizzard_TradeSkillUI on demand and
-- shows TradeSkillFrame (or CraftFrame on Vanilla/TBC). Used by the escape
-- button and the takeover-OFF path.
function Engine:ShowDefaultUI()
    if not self._sessionOpen then return end
    self._showingDefault = true
    self:_RecordLastUI("blizzard")

    -- Fold our own window away first so the two don't stack.
    if self._autoOpened and addon.MainWindow and addon.MainWindow.frame
       and addon.MainWindow.activeTab == "crafting" then
        addon.MainWindow:Close()
        self._autoOpened = false
    end

    if UIParent_OnEvent then
        if self._isCraftWindow then
            UIParent_OnEvent(UIParent, "CRAFT_SHOW")
        else
            UIParent_OnEvent(UIParent, "TRADE_SKILL_SHOW")
        end
    end

    -- Inject our "back to TOGPM" toggle onto Blizzard's frame, mirroring TSM's
    -- corner button. TSM anchors its "TSM4" button TOP-RIGHT, so we anchor ours
    -- TOP-LEFT — the two never overlap and can coexist while testing.
    local frame = self._isCraftWindow and _G.CraftFrame or _G.TradeSkillFrame
    self:ShowToggleButton(frame)
end

-- Toggle back from Blizzard's window to our Crafting tab WITHOUT ending the
-- session. The default frame's OnHide calls CloseTradeSkill / CloseCraft, which
-- would tear down the whole session — so we nil OnHide around HideUIPanel and
-- restore it afterwards (TSM uses the same clear-then-hide trick). The session
-- stays open server-side, so our tab keeps reading live data.
function Engine:ShowOurUI()
    if not self._sessionOpen then return end
    self._showingDefault = false
    self:_RecordLastUI("togpm")

    local frame = self._isCraftWindow and _G.CraftFrame or _G.TradeSkillFrame
    if frame and frame:IsShown() then
        local prevOnHide = frame:GetScript("OnHide")
        frame:SetScript("OnHide", nil)
        HideUIPanel(frame)
        frame:SetScript("OnHide", prevOnHide)
    end
    self:HideToggleButton()

    self._autoOpened = true
    if addon.MainWindow then addon.MainWindow:Open("crafting") end
    self:FireUpdate()
end

-- ---------------------------------------------------------------------------
-- "Back to TOGPM" button injected onto Blizzard's frame (LEFT side so it
-- coexists with TSM's top-right button)
-- ---------------------------------------------------------------------------
function Engine:ShowToggleButton(frame)
    if not frame then return end
    local b = self._toggleBtn
    if not b then
        b = CreateFrame("Button", "TOGPMCraftBackButton", frame, "UIPanelButtonTemplate")
        b:SetSize(72, 18)
        b:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "TOGPM|r")
        b:SetScript("OnClick", function() Engine:ShowOurUI() end)
        self._toggleBtn = b
    end
    b:SetParent(frame)
    b:ClearAllPoints()
    -- TOP-LEFT, inset to clear the frame's portrait/title-bar corner. Offset is
    -- easy to tweak if it clashes with the title on any particular client.
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 72, -14)
    b:SetFrameStrata("HIGH")
    b:Show()
end

function Engine:HideToggleButton()
    if self._toggleBtn then self._toggleBtn:Hide() end
end

-- Make sure our "TOGPM" toggle button rides on Blizzard's trade/craft frame
-- WHENEVER that frame is visible — not only when WE summon it via ShowDefaultUI.
-- With another profession addon installed (TSM, Skillet) the Blizzard frame can
-- be shown by it — or by the auto-open-into-TOGPM flow ending up alongside it —
-- even while we've "taken over", and the player needs our button there to get
-- back into TOGPM after closing our window. Hook each frame's OnShow once so the
-- button reappears on every show, and show it immediately if the frame is
-- already up (covers the handler-order race on the triggering event).
function Engine:EnsureToggleHook()
    for _, name in ipairs({ "TradeSkillFrame", "CraftFrame" }) do
        local frame = _G[name]
        if frame and not self._hookedFrames[frame] then
            self._hookedFrames[frame] = true
            frame:HookScript("OnShow", function() Engine:ShowToggleButton(frame) end)
            if frame:IsShown() then self:ShowToggleButton(frame) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- View notification — direct call (no callback plumbing needed for one view).
-- The view re-renders itself only when it's the active tab.
--   FireUpdate     — full redraw, for session open/close/profession switch.
--   FireLiveUpdate — light in-place refresh (counts/reagents) within the same
--                    session, e.g. after a craft. Avoids rebuilding the whole
--                    tab (toolbar/scroll) on every craft tick.
-- ---------------------------------------------------------------------------
function Engine:FireUpdate()
    if addon.CraftingTab and addon.CraftingTab.OnSessionChanged then
        addon.CraftingTab:OnSessionChanged()
    end
end

function Engine:FireLiveUpdate()
    if addon.CraftingTab and addon.CraftingTab.OnLiveRefresh then
        addon.CraftingTab:OnLiveRefresh()
    end
end

-- Run Init() once AceDB is ready, matching Scanner / MainWindow.
hooksecurefunc(Ace, "OnEnable", function(_self)
    Engine:Init()
end)
