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
-- WoW Forever (the _Camelot TOC, 11.x+ engine) has NONE of the classic
-- trade-skill globals (GetTradeSkillLine / GetNumTradeSkills /
-- GetTradeSkillInfo / DoTradeSkill: absent from its source tree, not even as
-- deprecation fallbacks). Its own Professions UI reads and crafts through
-- C_TradeSkillUI instead, and so do we there:
--   list     GetFilteredRecipeIDs (Blizzard_Professions.lua:847) + GetRecipeInfo
--   reagents GetRecipeSchematic -> reagentSlotSchematics
--   craft    CraftRecipe(recipeID, count) (Blizzard_ProfessionsTransaction.lua:352)
--   open     OpenTradeSkill(skillLineID) (ProfessionsUtil.lua:101), restricted
--            to a hardware event (warcraft.wiki.gg), from the tab's clicks --
--            never CastSpellByName, which Forever blocked (see OpenProfession).
-- Checked at call time (Compat.lua, HasModernTradeSkillAPI). The classic API
-- wins wherever it exists, so no classic client ever takes this path.
-- ---------------------------------------------------------------------------
function Engine:UsesModernAPI()
    return addon:HasModernTradeSkillAPI()
end

function Engine:HasTradeSkillAPI()
    return addon:HasClassicTradeSkillAPI() or self:UsesModernAPI()
end

-- The profession window this client draws: TradeSkillFrame on the classic
-- clients, ProfessionsFrame on Forever.
local function tradeFrameName()
    return _G.TradeSkillFrame and "TradeSkillFrame" or "ProfessionsFrame"
end

-- Enum.TradeskillRelativeDifficulty (TradeSkillUITypesDocumentation.lua:84-94)
-- to the classic difficulty strings the view colours by.
local MODERN_DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

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
Engine._tabDriven     = false   -- THIS session was opened by the Crafting tab, so no other
                                -- profession window may stay on screen (see HideForeignWindows)
Engine._suppressHooked = {}     -- frames whose OnShow we've hooked for tab-driven suppression
Engine._tsmFrame      = nil     -- TSM's crafting frame while its UI is up (from TSM_API)
Engine._tsmHooked     = false   -- our TSM_API UI callback is registered
Engine._tsmSuppressFailed = false -- hiding TSM's window killed the session once; don't retry

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
    if self:UsesModernAPI() then
        local p = addon:GetModernOpenProfession()
        if not p then return nil end
        local Scanner = addon.Scanner
        local profId = (Scanner and (Scanner:ResolveProfessionId(p.professionName)
            or (p.parentProfessionName and Scanner:ResolveProfessionId(p.parentProfessionName))))
            or p.parentProfessionID or p.professionID
        return {
            name          = p.parentProfessionName or p.professionName,
            rank          = p.skillLevel or 0,
            max           = p.maxSkillLevel or 0,
            profId        = profId,
            isCraftWindow = false,
        }
    elseif self._isCraftWindow then
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
        if profId == 186 then                         -- Mining → cast Smelting (spell 2656)
            castName = addon.Spell.GetInfo(2656) or name
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
--
-- WoW Forever: never cast. CastSpellByName from a Crafting tab click raised
-- ADDON_ACTION_BLOCKED there (in game 2026-09-28). It opens through
-- C_TradeSkillUI.OpenTradeSkill(skillLineID) instead, which warcraft.wiki.gg
-- marks restricted with the hwevent tag only: addon code may call it during a
-- keyboard or mouse event. The skill line is the profId GetKnownProfessions
-- carries (GetProfessionInfo's 7th return, the same one Forever's own
-- profession book stores as frame.skillLine).
--
-- UNEXPLAINED (2026-09-29): a tab click still raised ADDON_ACTION_BLOCKED for
-- OpenTradeSkill() "intermittently" (operator), while other clicks through the
-- same path opened the profession. Every Forever attempt is recorded by
-- _LogOpenAttempt and paired with any block, for `/togpm opendebug`.
function Engine:CanOpenFromCode()
    return self:HasTradeSkillAPI() and true or false
end

-- ---------------------------------------------------------------------------
-- OpenTradeSkill diagnostics (WoW Forever). A ring of the last attempts, each
-- with what could decide whether an hwevent call is allowed; an
-- ADDON_ACTION_BLOCKED / _FORBIDDEN naming this addon is attached to the
-- attempt it belongs to and announced in chat whether debug is on or not.
-- ---------------------------------------------------------------------------
local OPEN_LOG_MAX = 20
Engine._openLog = Engine._openLog or {}

local function profName(p) return p and (p.parentProfessionName or p.professionName) or "-" end

function Engine:_LogOpenAttempt(how, skillLine)
    local now = GetTime and GetTime() or 0
    local log = self._openLog
    local sameFrame = 0
    for _, r in ipairs(log) do if r.t == now then sameFrame = sameFrame + 1 end end
    local T = C_TradeSkillUI
    local baseInfo  = T and T.GetBaseProfessionInfo and T.GetBaseProfessionInfo() or nil
    local childInfo = T and T.GetChildProfessionInfo and T.GetChildProfessionInfo() or nil
    local rec = {
        t         = now,
        how       = how or "?",
        skillLine = skillLine,
        combat    = (InCombatLockdown and InCombatLockdown()) and true or false,
        -- Read through _G: each may be absent on some client, and a nil
        -- answer is itself worth recording.
        button    = _G.GetMouseButtonClicked and _G.GetMouseButtonClicked() or nil,
        mouseDown = (_G.IsMouseButtonDown and _G.IsMouseButtonDown()) and true or false,
        loaded    = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Professions"))
                    and true or false,
        frameUp   = (_G.ProfessionsFrame and _G.ProfessionsFrame:IsShown()) and true or false,
        openNow   = profName(addon:GetModernOpenProfession()),
        -- Peer Review's H1 (thread 4d8158c1): Blizzard's own callers skip
        -- OpenTradeSkill when that profession is already open
        -- (Blizzard_Professions_Bootstrap.lua:15-18, ProfessionsUtil.lua:86-101).
        baseId    = baseInfo and baseInfo.professionID or nil,
        childId   = childInfo and childInfo.professionID or nil,
        session   = self._sessionOpen and true or false,
        sameFrame = sameFrame,
        first     = (self._openCount or 0) == 0,
        stack     = _G.debugstack and _G.debugstack(3, 8, 0) or nil,
    }
    self._openCount = (self._openCount or 0) + 1
    log[#log + 1] = rec
    while #log > OPEN_LOG_MAX do table.remove(log, 1) end
    return rec
end

function Engine:_FormatOpenAttempt(r)
    return ("%.3f %s line=%s base=%s child=%s open=%s first=%s same=%d combat=%s btn=%s down=%s"
        .. " profUI=%s frame=%s session=%s -> %s%s"):format(
        r.t, r.how, tostring(r.skillLine), tostring(r.baseId), tostring(r.childId), tostring(r.openNow),
        tostring(r.first), r.sameFrame, tostring(r.combat), tostring(r.button), tostring(r.mouseDown),
        tostring(r.loaded), tostring(r.frameUp), tostring(r.session),
        tostring(r.result), r.blocked and (" BLOCKED(" .. r.blocked .. ")") or "")
end

-- The trade-skill events around those attempts, with what was open and
-- whether Blizzard's window was up at each: how a switch actually unfolds.
local EVENT_LOG_MAX = 40
Engine._eventLog = Engine._eventLog or {}

function Engine:_LogEvent(event)
    local T = C_TradeSkillUI
    local log = self._eventLog
    log[#log + 1] = {
        t        = GetTime and GetTime() or 0,
        event    = event,
        openNow  = profName(addon:GetModernOpenProfession()),
        changing = (T and T.IsDataSourceChanging and T.IsDataSourceChanging()) and true or false,
        frameUp  = (_G.ProfessionsFrame and _G.ProfessionsFrame:IsShown()) and true or false,
        drawn    = self._drawnProf,
        tabOwned = self._tabDriven and true or false,
    }
    while #log > EVENT_LOG_MAX do table.remove(log, 1) end
    -- Also to the debug stream: /togpm opendebug printed nothing in game
    -- (2026-09-29, cause not found), and the debug stream is what reached us.
    local e = log[#log]
    addon:DebugPrint(("Crafting event: %s open=%s changing=%s frame=%s drawn=%s tabOwned=%s"):format(
        e.event, tostring(e.openNow), tostring(e.changing), tostring(e.frameUp),
        tostring(e.drawn), tostring(e.tabOwned)))
end

-- `/togpm opendebug`: every recorded attempt, oldest first, with its stack,
-- then the events.
function Engine:DumpOpenLog()
    if #self._openLog == 0 then
        addon:Print("No profession-open attempts recorded this session.")
    end
    for _, r in ipairs(self._openLog) do
        addon:Print(self:_FormatOpenAttempt(r))
        if r.stack then
            for line in r.stack:gmatch("[^\n]+") do addon:Print("    " .. line) end
        end
    end
    for _, e in ipairs(self._eventLog) do
        addon:Print(("%.3f %s open=%s changing=%s frame=%s drawn=%s tabOwned=%s"):format(
            e.t, e.event, tostring(e.openNow), tostring(e.changing), tostring(e.frameUp),
            tostring(e.drawn), tostring(e.tabOwned)))
    end
end

-- Forever: when ProfessionsFrame shows, each of its profession tabs casts its
-- own profession unless it is the open one (Blizzard_ProfessionsTemplates.lua
-- :963-971, on "ProfessionsFrame.Show" from ProfessionsMixin:OnShow). The
-- in-game log of 2026-09-29 showed the open profession cycling through all
-- five within a second. These post-hooks only OBSERVE (hooksecurefunc runs
-- after the original and changes nothing), so the log can show whether those
-- casts are what undoes a switch from the tab.
function Engine:_WatchProfessionCasts()
    if self._castWatch or not self:UsesModernAPI() then return end
    self._castWatch = true
    if C_SpellBook and C_SpellBook.CastSpellBookItem and hooksecurefunc then
        hooksecurefunc(C_SpellBook, "CastSpellBookItem", function(slot)
            local info = C_SpellBook.GetSpellBookItemInfo
                and C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            Engine:_LogEvent("CastSpellBookItem " .. tostring(info and info.name or slot))
        end)
    end
end

local blockWatch = CreateFrame("Frame")
pcall(blockWatch.RegisterEvent, blockWatch, "ADDON_ACTION_BLOCKED")
pcall(blockWatch.RegisterEvent, blockWatch, "ADDON_ACTION_FORBIDDEN")
blockWatch:SetScript("OnEvent", function(_, event, who, func)
    if not (tostring(func):find("OpenTradeSkill", 1, true) or tostring(func):find("CastSpell", 1, true)) then return end
    if who ~= "TOGProfessionMaster" then
        -- Peer Review: a block naming another addon means the taint came in
        -- through shared code, not through this call.
        if Engine._opening then
            addon:Print(("Profession open: %s for %s was blamed on %s."):format(event, tostring(func), tostring(who)))
        end
        return
    end
    -- The attempt being made right now, else the latest one within a second.
    local r = Engine._opening
    if not r then
        local last = Engine._openLog[#Engine._openLog]
        if last and GetTime and (GetTime() - last.t) <= 1 then r = last end
    end
    if r then r.blocked = event:gsub("ADDON_ACTION_", "") end
    addon:Print("Profession open was blocked -- please send the output of /togpm opendebug. "
        .. (r and Engine:_FormatOpenAttempt(r) or ("no matching attempt for " .. tostring(func))))
end)

-- The tab is about to open a profession: force its next show into the TOGPM
-- tab and claim the session.
function Engine:ClaimNextShow()
    self._forceTakeoverOnce = true
    -- This session belongs to the tab: no other profession window may stay on
    -- screen for it. Arm the TSM callback BEFORE the cast so we catch its very
    -- first show (the callback only fires on the transition into open).
    self._tabDriven = true
    self:EnsureTSMHook()
    self:EnsureSuppressHook()
end

-- `how` names the trigger for the diagnostics: "tab", "dropdown", "jump" or
-- "button".
-- Seconds after the tab's own open within which a show of Blizzard's window
-- is taken to be that open's. A margin I chose, NOT measured: the show should
-- follow in the same or the next few frames, and the event log records the
-- real gap for checking it.
local OWN_OPEN_WINDOW = 2

function Engine:_OwnOpenIsRecent()
    return self._ownOpenAt ~= nil and GetTime ~= nil and (GetTime() - self._ownOpenAt) <= OWN_OPEN_WINDOW
end

function Engine:OpenProfession(name, how)
    if not name then return end
    if not self:CanOpenFromCode() then return false end
    local skillLine
    if self:UsesModernAPI() then
        if not C_TradeSkillUI.OpenTradeSkill then return false end
        for _, p in ipairs(self:GetKnownProfessions()) do
            if p.castName == name or p.name == name then skillLine = p.profId break end
        end
        if not skillLine then return false end
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        addon:Print(addon.L and addon.L["CraftCantOpenInCombat"] or "Can't open a profession in combat.")
        return false
    end
    self:ClaimNextShow()
    self._ownOpenAt = GetTime and GetTime() or nil
    if skillLine then
        local rec = self:_LogOpenAttempt(how, skillLine)
        local wasShown = _G.ProfessionsFrame and _G.ProfessionsFrame:IsShown()
        self._opening = rec
        local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
        -- Blizzard's window was hidden, so this open showed it and its tabs'
        -- cast cascade ran (see _CloakProfessionsFrame), leaving the LAST tab's
        -- profession open. The window is shown now -- and cloaked by our OnShow
        -- hook -- so asking once more does not re-fire the cascade. In game the
        -- cascade's casts all went through inside the same click, so a second
        -- call inside it is expected to as well; not verified, and the block
        -- watcher reports it if not.
        if ok and opened and not wasShown then
            local T = C_TradeSkillUI
            local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
            if base and base.professionID ~= skillLine then
                rec.retried = true
                ok, opened = pcall(T.OpenTradeSkill, skillLine)
            end
        end
        self._opening = nil
        rec.result = (ok and tostring(opened) or ("error: " .. tostring(opened)))
            .. (rec.retried and " (asked twice)" or "")
        addon:DebugPrint("Crafting: " .. self:_FormatOpenAttempt(rec))
        if ok and opened then return true end
        -- Nothing opened, so no show event will consume the claim.
        self._forceTakeoverOnce, self._tabDriven = false, false
        return false
    end
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
-- difficulty array, and "-" when there's nothing -- or when the tiers are
-- UNANCHORED (addon.IsUnanchoredDifficulty, TOGProfessionMaster.lua), which
-- ProfessionDB says to show as unknown rather than as thresholds.
--
-- `recipeId` (the craft spell id) is optional and only matters on a flavour
-- whose ProfessionDB data BORROWS requiredSkill (WoW Forever, MINOR 13): a
-- borrowed requiredSkill does not anchor the tiers, and the lone-requiredSkill
-- fallback is marked unconfirmed. Without it the output is exactly as before.
function addon.FormatSkillTiers(tiers, requiredSkill, recipeId)
    if addon.IsUnanchoredDifficulty(tiers, requiredSkill, recipeId) then return "-" end
    if not tiers then
        if not requiredSkill then return "-" end
        local s = "|c" .. TIER_HEX[1] .. requiredSkill .. "|r"
        if addon.IsBorrowedValue and addon.IsBorrowedValue(recipeId, "requiredSkill") then
            s = s .. " (" .. addon.UnconfirmedText() .. ")"
        end
        return s
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

-- WoW Forever's recipe list, in the same entry shape as the classic reads
-- below. `index` IS the recipe id there: the modern API addresses a recipe by
-- its spell id, never by a row position. Learned recipes only, grouped under
-- their category's name in the order the client lists them.
function Engine:_ModernRecipeList(profId)
    local T = C_TradeSkillUI
    local groups, order = {}, {}
    for _, id in ipairs(addon:GetModernLearnedRecipeIDs()) do
        local r = T.GetRecipeInfo(id)
        if r then
            local cat = r.categoryID or 0
            if not groups[cat] then
                groups[cat] = {}
                order[#order + 1] = cat
            end
            local out = T.GetRecipeOutputItemData and T.GetRecipeOutputItemData(id)
            local link = out and out.hyperlink or nil
            local meta = recipeMeta(profId, id)
            local num = T.GetCraftableCount and T.GetCraftableCount(id) or nil
            if num == nil then
                num = math.huge
                for _, rg in ipairs(self:GetReagents(id)) do
                    if rg.need > 0 then num = math.min(num, math.floor(rg.have / rg.need)) end
                end
                if num == math.huge then num = 0 end
            end
            local g = groups[cat]
            g[#g + 1] = {
                kind = "recipe", index = id, name = r.name,
                difficulty = MODERN_DIFFICULTY[r.relativeDifficulty] or "trivial",
                num = num, recipeId = id,
                icon = r.icon, link = link, color = linkColour(link),
                requiredSkill = meta and meta.requiredSkill or nil,
                tiers = meta and meta.difficulty or nil,
                effect = meta and (addon:GetCraftedItemStatText(meta.craftedItemId) or meta.effect) or nil,
            }
        end
    end
    local list = {}
    for _, cat in ipairs(order) do
        local ci = T.GetCategoryInfo and cat ~= 0 and T.GetCategoryInfo(cat)
        if ci and ci.name and ci.name ~= "" then
            list[#list + 1] = { kind = "header", name = ci.name }
        end
        for _, e in ipairs(groups[cat]) do list[#list + 1] = e end
    end
    return list
end

function Engine:GetRecipeList()
    if not self._sessionOpen then return {} end
    local out = {}
    local profId = (self:GetOpenInfo() or {}).profId
    if self:UsesModernAPI() then return self:_ModernRecipeList(profId) end
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
                        -- crafted consumable's use-effect buff (LibItemDB) wins;
                        -- enchant effect (ProfessionDB) is the fallback
                        effect = meta and (addon:GetCraftedItemStatText(meta.craftedItemId) or meta.effect) or nil,
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
                        -- crafted consumable's use-effect buff (LibItemDB) wins;
                        -- enchant effect (ProfessionDB) is the fallback
                        effect = meta and (addon:GetCraftedItemStatText(meta.craftedItemId) or meta.effect) or nil,
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
    if self:UsesModernAPI() then
        -- index is the recipe id (see _ModernRecipeList). Basic reagents only:
        -- a slot whose dataSlotType is not Reagent (1) is an optional/modified
        -- reagent or a currency (TradeSkillUITypesDocumentation.lua:98-107).
        local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, index, false)
        if not (ok and s and s.reagentSlotSchematics) then return out end
        for _, slot in ipairs(s.reagentSlotSchematics) do
            local rg = slot.reagents and slot.reagents[1]
            local itemId = rg and rg.itemID
            if itemId and slot.required ~= false
               and (slot.dataSlotType == nil or slot.dataSlotType == 1) then
                local name, link = addon.Item.GetInfo(itemId)
                out[#out + 1] = {
                    name = name, texture = addon.Item.GetIcon(itemId),
                    need = slot.quantityRequired or 0,
                    have = addon.Item.GetCount(itemId) or 0,
                    link = link, itemId = itemId,
                }
            end
        end
        return out
    end
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
    --
    -- The interactive enchant path does NOT come through here: the Crafting tab's
    -- Craft button is a secure action button that casts "/cast <recipe>" itself
    -- (see GUI/CraftingTab.lua) and its PreClick returns early for enchants. This
    -- branch is only reached by a QUEUED enchant (Craft Next / Craft All), so it
    -- pops Blizzard's own Craft window for the player to click Create, and says so
    -- once.
    -- NOTE for future work: v0.8.3 introduced the secure-cast path on the premise
    -- that `DoCraft` is a protected function. That premise was never validated and
    -- looks wrong — TradeSkillMaster calls `DoCraft(index)` straight from a plain,
    -- NON-secure button's OnClick in its classic-crafting path
    -- (LibTSMWoW/Source/API/TradeSkill.lua `TradeSkill.Craft`). If that holds, this
    -- branch could simply call DoCraft and let queued enchants craft in place.
    -- Left alone here because it can't be verified on this account.
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
    if self:UsesModernAPI() then
        -- WoW Forever: by recipe id, as Blizzard_ProfessionsTransaction.lua:352 does.
        if C_TradeSkillUI.CraftRecipe then C_TradeSkillUI.CraftRecipe(liveIndex, qty) end
        return
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

    -- RegisterEvent RAISES on a name the client does not know, which aborted
    -- this Init on WoW Forever: it has no TRADE_SKILL_UPDATE (its
    -- TradeSkillUIDocumentation.lua declares TRADE_SKILL_LIST_UPDATE instead)
    -- and no CRAFT_* events in its API docs. Those go through a pcall that
    -- skips an unknown name; each client gets whichever update event it has.
    local function tryRegister(event) pcall(eventFrame.RegisterEvent, eventFrame, event) end
    eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
    tryRegister("TRADE_SKILL_UPDATE")
    tryRegister("TRADE_SKILL_LIST_UPDATE")
    tryRegister("TRADE_SKILL_DATA_SOURCE_CHANGED")   -- WoW Forever
    eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
    if HAS_CRAFT_WINDOW then
        tryRegister("CRAFT_SHOW")
        tryRegister("CRAFT_UPDATE")
        tryRegister("CRAFT_CLOSE")
    end
    eventFrame:SetScript("OnEvent", function(_, event) Engine:OnEvent(event) end)

    addon:DebugPrint("CraftingEngine: init (craft window:", tostring(HAS_CRAFT_WINDOW), ")")
end

function Engine:OnEvent(event)
    if self:UsesModernAPI() then
        self:_WatchProfessionCasts()
        self:EnsureSuppressHook()   -- so the OnShow log line exists from the first show
        self:_LogEvent(event)
    end
    -- A client with neither the classic trade-skill API nor C_TradeSkillUI has
    -- nothing to read, so no session opens there. WoW Forever reads through
    -- C_TradeSkillUI (UsesModernAPI).
    if event:find("^TRADE_SKILL_") and not self:HasTradeSkillAPI() then return end
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
        if self:IsPetTrainingSession() then
            self:HandOffPetTraining()
            return
        end
        self:OnProfessionShow()

    elseif event == "TRADE_SKILL_CLOSE" then
        self._tradeOpen = false
        self:ScheduleClose()

    elseif event == "CRAFT_CLOSE" then
        self._craftOpen = false
        self:ScheduleClose()

    elseif self:UsesModernAPI() and self._sessionOpen
           and (event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED") then
        -- WoW Forever: a switch to another profession while one is open lands
        -- here, once the new data source is built -- not on TRADE_SKILL_SHOW.
        -- Blizzard's own window switches at exactly this point and yields while
        -- the source is still changing (Blizzard_ProfessionsFrame.lua:138-161).
        -- A light refresh would keep drawing the old profession's tab, which is
        -- what the dropdown did in game (2026-09-29).
        local T = C_TradeSkillUI
        if T.IsDataSourceChanging and T.IsDataSourceChanging() then return end
        local now = profName(addon:GetModernOpenProfession())
        if now ~= self._drawnProf then
            self:FireUpdate()
        elseif not self._suppressUpdate then
            self:FireLiveUpdate()
        end

    elseif event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE"
           or event == "CRAFT_UPDATE" then
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
-- Beast Training: a craft session that is NOT a profession
-- ---------------------------------------------------------------------------
-- On Vanilla/TBC a hunter's Beast Training opens the SAME window as Enchanting
-- -- Blizzard_CraftUI's CraftFrame -- and fires the same CRAFT_SHOW. Reported
-- from Discord, 2026-09-10: "hunter training skill conflicts in classic with
-- TOGPM causing it to not be usable to train pets". With the crafting takeover
-- on, Init has unregistered CRAFT_SHOW from UIParent and CraftFrame, so the
-- only window that can teach a pet never appears, and our Crafting tab opens
-- on a session it cannot read -- GetOpenInfo returns nil, because there is no
-- skill line. The hunter is left with nothing.
--
-- How the game itself tells them apart, from Blizzard_CraftUI.lua (Vanilla
-- :101-116, TBC :136-151): `GetCraftDisplaySkillLine()` returns the skill name
-- for a profession and NIL for Beast Training, and CraftFrame hides its rank
-- bar on exactly that nil. Its rows carry a `trainingPointCost` too, but the
-- skill line is the check Blizzard's own frame makes, so it is the one here.
-- The Scanner already keys on the same nil (ScanCraftSkillInto).
function Engine:IsPetTrainingSession()
    if not self._isCraftWindow or not GetCraftDisplaySkillLine then return false end
    local name = GetCraftDisplaySkillLine()
    return name == nil or name == ""
end

-- Give the session straight back to Blizzard's window and take no part in it:
-- no tab, no toggle button, no "last UI" record, no foreign-window suppression.
-- In hands-off mode UIParent's handler was never unregistered and has already
-- shown the frame, so there is nothing to summon. The session flags stay set
-- so CRAFT_CLOSE unwinds through the normal path.
function Engine:HandOffPetTraining()
    self._sessionOpen  = true
    self._tabDriven    = false      -- the OnShow suppress hook must not hide it
    self._autoOpened   = false
    self._showingDefault = true
    if not self:IsHandsOff() and UIParent_OnEvent then
        UIParent_OnEvent(UIParent, "CRAFT_SHOW")
    end
    self:FireUpdate()
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
                -- One more pass a beat later: TSM opens its window from a state
                -- machine driven off the same event, and a rival addon can show
                -- Blizzard's frame on its own delay — both land after the
                -- next-frame pass above. The OnShow hook covers re-shows from
                -- here on; this catches the initial one whatever its timing.
                C_Timer.After(0.1, function() self:HideForeignWindows() end)
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
    -- Takeover mode: TOGPM owns the crafting window for this session. Blizzard's
    -- frame was suppressed at Init, but a third-party UI (TSM) registers the show
    -- event itself and is unaffected by that — so claim the session and hide
    -- whatever else appears, same as the tab-driven path.
    self._tabDriven = true
    self:EnsureTSMHook()
    self:EnsureSuppressHook()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function() self:HideForeignWindows() end)
    end

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
    -- Session over: the next open belongs to whoever triggers it, so drop our
    -- claim on the window. (_tsmFrame is cleared by TSM's own hide callback,
    -- but a session can end without one — e.g. we hid the frame ourselves.)
    self._tabDriven     = false
    self._tsmFrame      = nil
    self:HideToggleButton()
    -- WoW Forever: the next open, by anyone, must be visible.
    self:_UncloakProfessionsFrame()

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
    -- The user asked for the native window: stop suppressing foreign windows,
    -- or the OnShow hook would hide the very frame we're about to summon.
    self._tabDriven = false
    self:_RecordLastUI("blizzard")

    -- WoW Forever: the frame is still shown, only cloaked, so revealing it is
    -- all there is to do -- re-showing it would set off its tabs' casts. Our
    -- window stays open: the operator wants both up when the player asks
    -- (2026-09-29). Reached from the "WoW UI" button and from the K key while
    -- cloaked.
    if self:UsesModernAPI() and self:_UncloakProfessionsFrame() then
        self:ShowToggleButton(_G.ProfessionsFrame)
        return
    end

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
    local frame = self._isCraftWindow and _G.CraftFrame or _G[tradeFrameName()]
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
    -- Reached either from a tab-driven open or from the TOGPM button on
    -- Blizzard's frame. Both are the user choosing our tab, so from here on no
    -- other profession window may sit on top of it.
    self._tabDriven = true
    self:EnsureTSMHook()
    self:_RecordLastUI("togpm")

    -- Clear the field for our tab: Blizzard's frames and, when the session is
    -- ours, TSM's window too. HideForeignWindows no-ops unless _tabDriven.
    if self:UsesModernAPI() then
        self:_CloakProfessionsFrame()   -- WoW Forever: cloak, never hide
    else
        self:_HideFrameSafely(self._isCraftWindow and _G.CraftFrame or _G[tradeFrameName()], true)
    end
    self:EnsureSuppressHook()
    self:HideForeignWindows()
    self:HideToggleButton()

    self._autoOpened = true
    if addon.MainWindow then addon.MainWindow:Open("crafting") end
    self:FireUpdate()
end

-- ---------------------------------------------------------------------------
-- Foreign-window suppression for a TAB-DRIVEN session
--
-- Opening a profession means CASTING it — that is the only way to get a
-- trade-skill session on Classic, and the live session is what the tab reads
-- and crafts through. The cast fires TRADE_SKILL_SHOW / CRAFT_SHOW, which is
-- exactly what every OTHER profession UI listens for. So clicking our Crafting
-- tab also pops Blizzard's window, or TSM's — the reported "two windows open".
--
-- When the tab is what opened the session (_tabDriven), no other profession
-- window may stay on screen. We can't stop the event reaching them, so we hide
-- whatever appears:
--   * Blizzard's TradeSkillFrame / CraftFrame — hidden here AND re-hidden from
--     an OnShow hook, so an addon that shows them later can't leave one up.
--   * TSM's crafting window — via its PUBLIC API (TSM_API.RegisterUICallback),
--     which hands us the frame when it opens. See docs/DEPENDENCY_CONTRACTS.md:
--     TSM has no "don't open for this session" API, so hiding the frame it
--     gives us is the only integration point available.
-- The user's "WoW UI" button clears _tabDriven, so choosing the native window
-- mid-session turns all of this off and it stays up.
-- ---------------------------------------------------------------------------

-- Hide a frame WITHOUT letting its OnHide run. Every profession UI closes the
-- trade-skill session from OnHide (Blizzard's calls CloseTradeSkill/CloseCraft;
-- TSM's fires EV_FRAME_HIDE → TradeSkill.CloseUI) — and that session is the
-- data source our tab is reading, so letting it fire would blank our own tab.
-- Clearing the script around the hide is the same technique TSM itself uses on
-- Blizzard's frame. `panel` picks HideUIPanel (UIPanel-managed Blizzard frames)
-- over a plain Hide (TSM's frame is not UIPanel-managed).
function Engine:_HideFrameSafely(frame, panel)
    if not (frame and frame.IsShown and frame:IsShown()) then return false end
    local prevOnHide = frame.GetScript and frame:GetScript("OnHide")
    if prevOnHide then frame:SetScript("OnHide", nil) end
    if panel and HideUIPanel then HideUIPanel(frame) else frame:Hide() end
    if prevOnHide then frame:SetScript("OnHide", prevOnHide) end
    return true
end

-- ---------------------------------------------------------------------------
-- WoW Forever: CLOAK Blizzard's ProfessionsFrame instead of hiding it.
--
-- Whenever ProfessionsFrame goes from hidden to shown, each of its profession
-- tabs that is not the open profession casts its own profession spell
-- (Blizzard_ProfessionsTemplates.lua:963-971, on "ProfessionsFrame.Show" from
-- ProfessionsMixin:OnShow). Each cast opens that profession, so the next tab
-- casts too, and the last tab always wins. Confirmed in game 2026-09-29: every
-- dropdown pick ended on Fishing ("Bait and Tackle"), the last tab, because the
-- takeover had HIDDEN the frame and our open re-showed it. A frame that stays
-- shown never re-fires OnShow, so a switch sticks.
--
-- So while the tab owns the session the frame stays shown but invisible:
-- alpha 0, and mouse input off on it and every frame inside it, so it catches
-- no clicks. NOT its scale: a first build shrank it to 1% and the revealed
-- window came up far narrower than Blizzard's normal one, its Create bar
-- running off the edge (in game 2026-09-29; compared against an untouched
-- window). Its size is never touched now. The operator's conditions (2026-09-29):
-- "if the user pushes K, it needs to appear" -- the TOGGLEPROFESSIONBOOK keys
-- are bound to uncloak while cloaked, since ToggleProfessionsBook would
-- otherwise TOGGLE the shown frame closed (Blizzard_ProfessionsBook_Bootstrap
-- .lua:11-12) -- and "we need to be able to show both at the same time if the
-- user wants it": uncloaking never closes our window.
-- ---------------------------------------------------------------------------
-- Turn mouse input off on `frame` and everything inside it, recording what
-- each had so it can be put back. A frame Blizzard creates inside it while
-- cloaked (a pooled recipe row) is not covered until the next cloak.
local function muteMouse(frame, saved)
    if frame.IsMouseEnabled then
        saved[#saved + 1] = { f = frame, mouse = frame:IsMouseEnabled(),
            wheel = frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() }
        frame:EnableMouse(false)
        if frame.EnableMouseWheel then frame:EnableMouseWheel(false) end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do muteMouse(child, saved) end
    end
end

local function restoreMouse(saved)
    for _, s in ipairs(saved or {}) do
        s.f:EnableMouse(s.mouse and true or false)
        if s.f.EnableMouseWheel then s.f:EnableMouseWheel(s.wheel and true or false) end
    end
end

local uncloakButton, bindOwner
local function ensureUncloakButton()
    if uncloakButton then return end
    uncloakButton = CreateFrame("Button", "TOGPMShowProfessionsButton", UIParent)
    uncloakButton:Hide()
    uncloakButton:SetScript("OnClick", function() Engine:ShowDefaultUI() end)
    bindOwner = CreateFrame("Frame")
end

function Engine:IsCloaked()
    return self._cloaked and true or false
end

function Engine:_CloakProfessionsFrame()
    local f = _G.ProfessionsFrame
    if not (f and f:IsShown()) or self._cloaked then return false end
    self._cloakSaved = { alpha = f:GetAlpha(), mouse = {} }
    f:SetAlpha(0)
    muteMouse(f, self._cloakSaved.mouse)
    self._cloaked = true
    -- Rebinding is protected in combat; there K keeps Blizzard's behaviour.
    if not (InCombatLockdown and InCombatLockdown()) and SetOverrideBindingClick and GetBindingKey then
        ensureUncloakButton()
        for _, key in ipairs({ GetBindingKey("TOGGLEPROFESSIONBOOK") }) do
            SetOverrideBindingClick(bindOwner, false, key, "TOGPMShowProfessionsButton")
        end
    end
    self:_LogEvent("ProfessionsFrame cloaked")
    return true
end

function Engine:_UncloakProfessionsFrame()
    if not self._cloaked then return false end
    self._cloaked = false
    local f, saved = _G.ProfessionsFrame, self._cloakSaved
    self._cloakSaved = nil
    if f then
        f:SetAlpha(saved and saved.alpha or 1)
        restoreMouse(saved and saved.mouse)
    end
    if bindOwner and ClearOverrideBindings and not (InCombatLockdown and InCombatLockdown()) then
        ClearOverrideBindings(bindOwner)
    end
    self:_LogEvent("ProfessionsFrame uncloaked")
    return true
end

-- Our window closed while Blizzard's is cloaked: close Blizzard's too, through
-- its own HideUIPanel, whose OnHide ends the session as closing it by hand
-- does. Otherwise an invisible profession window would stay open.
function Engine:OnMainWindowClosed()
    if not self._cloaked then return end
    local f = _G.ProfessionsFrame
    self:_UncloakProfessionsFrame()
    if f and f:IsShown() and HideUIPanel then HideUIPanel(f) end
end

-- True while the trade-skill session we're reading is still alive. Used to
-- verify a foreign-window hide didn't take the session down with it.
function Engine:_SessionStillLive()
    if not self._sessionOpen then return false end
    if self._isCraftWindow then
        return (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) ~= nil
    end
    if self:UsesModernAPI() then return addon:GetModernOpenProfession() ~= nil end
    return (GetTradeSkillLine and GetTradeSkillLine()) ~= nil
end

-- Hide every profession window that isn't ours. No-op unless this session was
-- opened by the tab.
function Engine:HideForeignWindows()
    if not (self._tabDriven and self._sessionOpen) then return end

    -- Both Blizzard frames, not just the current session's: a profession switch
    -- can leave the other one up.
    self:_HideFrameSafely(_G.TradeSkillFrame, true)
    -- WoW Forever's window is cloaked, never hidden: re-showing a hidden one
    -- sets off its tabs' cast cascade (see _CloakProfessionsFrame).
    self:_CloakProfessionsFrame()
    if HAS_CRAFT_WINDOW then self:_HideFrameSafely(_G.CraftFrame, true) end

    -- TSM's window. If clearing OnHide didn't hold and the session died, stop
    -- trying for the rest of the play session — a visible second window is a
    -- far smaller problem than a Crafting tab with no data in it.
    if self._tsmFrame and not self._tsmSuppressFailed then
        if self:_HideFrameSafely(self._tsmFrame, false) and not self:_SessionStillLive() then
            self._tsmSuppressFailed = true
            addon:DebugPrint("CraftingEngine: hiding TSM's crafting window closed the session — suppression disabled")
        end
    end
end

-- Re-hide on OnShow, so a window opened after our pass (TSM's FSM tick, a rival
-- addon, Blizzard's load-on-demand frame arriving late) can't linger. Hooked
-- once per frame; the handler defers because hiding a frame from inside its own
-- OnShow is asking for trouble.
function Engine:EnsureSuppressHook()
    for _, name in ipairs({ "TradeSkillFrame", "CraftFrame", "ProfessionsFrame" }) do
        local frame = _G[name]
        if frame and not self._suppressHooked[frame] then
            self._suppressHooked[frame] = true
            frame:HookScript("OnShow", function()
                if name == "ProfessionsFrame" then Engine:_LogEvent("ProfessionsFrame OnShow") end
                if not Engine._tabDriven then return end
                -- WoW Forever: Blizzard's window showing when the tab did not
                -- just open a profession is the player asking for it (the K
                -- key, their profession book). Hiding it then made K unusable
                -- for the rest of the session (in game 2026-09-29: "once i've
                -- opened it with TOGPM, i can't use the K key to open
                -- crafting"). Let the player have it and drop the tab's claim,
                -- as the "WoW UI" button does. Classic's frames keep the old
                -- rule; this is Forever's window only.
                if name == "ProfessionsFrame" then
                    if Engine:_OwnOpenIsRecent() then
                        -- Our open showed it: cloak it now, in this OnShow,
                        -- so it never appears (the "popping" in game).
                        Engine:_CloakProfessionsFrame()
                    else
                        Engine._tabDriven = false
                        Engine:_LogEvent("ProfessionsFrame shown by the player: claim released")
                    end
                    return
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() Engine:HideForeignWindows() end)
                else
                    Engine:HideForeignWindows()
                end
            end)
        end
    end
end

-- Register our TSM UI callback once. TSM_API only exists when TSM is installed,
-- and RegisterUICallback ERRORS on a duplicate tag, so both are guarded. The
-- callback is how we learn TSM's frame exists at all — it is not exposed any
-- other way.
function Engine:EnsureTSMHook()
    if self._tsmHooked then return end
    if not (TSM_API and TSM_API.RegisterUICallback) then return end
    local ok = pcall(TSM_API.RegisterUICallback, "CRAFTING", "TOGProfessionMaster:CraftingTab",
        function(shown, frame)
            Engine._tsmFrame = shown and frame or nil
            if not shown then return end
            -- Fired from inside TSM's state-machine transition; never touch the
            -- frame synchronously or its OnHide re-enters that transition.
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() Engine:HideForeignWindows() end)
            end
        end)
    self._tsmHooked = ok and true or false
    if not ok then addon:DebugPrint("CraftingEngine: TSM_API.RegisterUICallback failed") end
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
    for _, name in ipairs({ "TradeSkillFrame", "CraftFrame", "ProfessionsFrame" }) do
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
    -- The profession this redraw shows (WoW Forever): a later list update
    -- naming a different one is a switch that has not been drawn yet.
    if self:UsesModernAPI() then
        self._drawnProf = profName(addon:GetModernOpenProfession())
    end
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
