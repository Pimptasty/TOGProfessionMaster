-- TOG Profession Master — Cooldowns Tab
-- Draws the "Cooldowns" tab inside the main window.
--
-- Columns: Character · Cooldown · Reagent · Time Left
-- Features:
--   • Sort by any column (click header; toggle asc/desc; state saved in AceDB)
--   • "Ready Only" toggle filter
--   • Grouped rows for multi-spell cooldowns (Transmute, Dreamcloth, etc.)
--   • Spell tooltip on cooldown name hover
--   • Item tooltip on reagent name hover
--   • Right-click row → whisper character

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local CooldownsTab = {}
addon.CooldownsTab = CooldownsTab

-- Sort state persisted across redraws (but not saved to AceDB for now).
CooldownsTab._sortCol   = "time"    -- "char" | "cd" | "time"
CooldownsTab._sortAsc   = true
CooldownsTab._readyOnly = false
-- Two-level cooldown filter: profession (0 = All) → specific cooldown
-- ("all" = All within that profession). Two AceGUI dropdowns on the toolbar.
CooldownsTab._filterProf = 0
CooldownsTab._filterProfs = nil
CooldownsTab._filterCd   = "all"
-- Scope filter: "guild" shows every guild member's cooldowns,
-- "mine" narrows to the local player's own characters. Mirrors the
-- Browser tab's _viewMode dropdown.
CooldownsTab._viewMode   = "guild"

-- Profession display names come from the shared addon.PROF_NAMES table
-- in TOGProfessionMaster.lua — single source of truth for every tab.

-- Cumulative version availability helpers. A TBC entry stays available on
-- Wrath/Cata/MoP because the cooldown spells from earlier expansions still
-- exist on later clients (the cooldown data tables are loaded cumulatively
-- in Data/CooldownIds.lua for the same reason). Profession-level version
-- gating (e.g. JC = TBC+, Inscription = Wrath+) lives in
-- addon.PROF_AVAILABILITY; these per-cooldown helpers gate individual
-- shared-timer entries within COOLDOWN_BY_PROFESSION below.
local function fromVanilla() return true end
local function fromTBC()     return addon.isTBC   or addon.isWrath or addon.isCata or addon.isMoP end
local function fromWrath()   return addon.isWrath or addon.isCata  or addon.isMoP end
local function fromCata()    return addon.isCata  or addon.isMoP end
local function fromMoP()     return addon.isMoP end

-- Match-function builders. spellIdMatcher(...) returns a closure that tests
-- row.spellId against the supplied id set; groupKeyMatcher(key) tests the
-- row's group identity for cooldowns that BuildRows already collapses into
-- a single grouped row (Dreamcloth, JC Daily Cut, etc.).
local function spellIdMatcher(...)
    local set = {}
    for i = 1, select("#", ...) do set[(select(i, ...))] = true end
    return function(row) return set[row.spellId] == true end
end
local function groupKeyMatcher(key)
    return function(row) return row.isGroup and row.group and row.group.groupKey == key end
end

-- Cooldown filter taxonomy, organised by profession. Each profession bucket
-- lists logical "shared-timer" entries — multiple spells that share one
-- cooldown collapse to ONE entry (e.g. all vanilla transmutes share one
-- timer per alchemist, so Alchemy has just "Transmute" rather than 11
-- individual transmute entries). Spec-locked spells that aren't technically
-- shared but where a single character can only ever cast one (TBC/Wrath
-- specialty cloth) likewise collapse to one entry. `match(row)` returns
-- true for cooldown rows belonging to that entry. `isAvailable()` gates by
-- game version. Add new entries here for future expansions; the parent
-- profession's match coverage extends automatically (it's the union of its
-- entries' matches), and the dropdowns rebuild themselves with no further
-- UI plumbing changes.
local COOLDOWN_BY_PROFESSION = {
    [171] = {  -- Alchemy
        { id = "transmute",       labelKey = "FilterTransmute",
          isAvailable = fromVanilla,
          match = function(row) return row.isTransmuteGroup == true end },
        { id = "alch_research",   labelKey = "FilterAlchResearch",
          isAvailable = fromWrath,
          match = spellIdMatcher(60893) },                                   -- Northrend Alchemy Research
    },
    [197] = {  -- Tailoring
        { id = "mooncloth",       labelKey = "FilterMooncloth",
          isAvailable = fromVanilla,
          match = spellIdMatcher(18560) },                                   -- Mooncloth (4-day)
        { id = "specialty_cloth", labelKey = "FilterSpecialtyCloth",
          isAvailable = fromTBC,
          match = spellIdMatcher(
              26751, 31373, 36686,                                           -- TBC: Primal Mooncloth, Spellcloth, Shadowcloth
              56001, 56002, 56003                                            -- Wrath: Moonshroud, Ebonweave, Spellweave
          ) },
        { id = "glacial_bag",     labelKey = "FilterGlacialBag",
          isAvailable = fromWrath,
          match = spellIdMatcher(56005) },                                   -- Glacial Bag (7-day)
        { id = "dreamcloth",      labelKey = "FilterDreamcloth",
          isAvailable = fromCata,
          match = groupKeyMatcher("dreamcloth") },                           -- 5-spell group
        { id = "imperial_silk",   labelKey = "FilterImperialSilk",
          isAvailable = fromMoP,
          match = spellIdMatcher(125557) },
    },
    [333] = {  -- Enchanting
        { id = "magic_sphere",    labelKey = "FilterMagicSphere",
          isAvailable = fromTBC,
          match = spellIdMatcher(28027, 28028) },                            -- Prismatic Sphere + Void Sphere
        { id = "sha_crystal",     labelKey = "FilterShaCrystal",
          isAvailable = fromMoP,
          match = spellIdMatcher(116499) },
    },
    [755] = {  -- Jewelcrafting
        { id = "brilliant_glass", labelKey = "FilterBrilliantGlass",
          isAvailable = fromTBC,
          match = spellIdMatcher(47280) },
        { id = "icy_prism",       labelKey = "FilterIcyPrism",
          isAvailable = fromWrath,
          match = spellIdMatcher(62242) },
        { id = "fire_prism",      labelKey = "FilterFirePrism",
          isAvailable = fromCata,
          match = spellIdMatcher(73478) },
        { id = "jc_daily",        labelKey = "FilterJcDaily",
          isAvailable = fromMoP,
          match = groupKeyMatcher("jc_daily") },                             -- 7-spell daily-cut group
    },
    [773] = {  -- Inscription
        { id = "inscription_research", labelKey = "FilterInscriptionResearch",
          isAvailable = fromWrath,
          match = groupKeyMatcher("inscription_research") },                 -- Minor + Northrend group
        { id = "forged_documents", labelKey = "FilterForgedDocuments",
          isAvailable = fromCata,
          match = spellIdMatcher(86654, 89244) },                            -- Horde + Alliance variants
        { id = "scroll_of_wisdom", labelKey = "FilterScrollOfWisdom",
          isAvailable = fromMoP,
          match = spellIdMatcher(112996) },
    },
    [164] = {  -- Blacksmithing
        { id = "titansteel_bar",  labelKey = "FilterTitansteelBar",
          isAvailable = fromWrath,
          match = spellIdMatcher(55208) },
        { id = "bs_ingot",        labelKey = "FilterBsIngot",
          isAvailable = fromMoP,
          match = groupKeyMatcher("bs_ingot") },                             -- Balanced Trillium + Lightning Steel group
    },
    [165] = {  -- Leatherworking
        -- Salt Shaker is an item-based cooldown (no profession requirement to
        -- USE it), but its output Refined Deeprock Salt is a Leatherworking
        -- reagent — so leatherworkers are the ones who actually rotate it on
        -- cooldown for crafting purposes. Filed here rather than under
        -- Cooking despite the misleading name.
        { id = "saltshaker",      labelKey = "FilterSaltShaker",
          isAvailable = fromVanilla,
          match = spellIdMatcher(15846) },                                   -- Salt Shaker (8-hour)
        { id = "magnificence",    labelKey = "FilterMagnificence",
          isAvailable = fromMoP,
          match = groupKeyMatcher("magnificence") },                         -- of Leather + of Scales group
    },
    [202] = {  -- Engineering
        { id = "jards",           labelKey = "FilterJards",
          isAvailable = fromMoP,
          match = spellIdMatcher(139176) },                                  -- Jard's Peculiar Energy Source
    },
}

-- Profession-level row matcher: a row belongs to profession X iff any of
-- X's cooldown entries match it. Self-managing — adding a new entry to
-- COOLDOWN_BY_PROFESSION automatically extends the parent profession's
-- match coverage with no separate map to maintain.
local function ProfessionMatchesRow(profId, row)
    local entries = COOLDOWN_BY_PROFESSION[profId]
    if not entries then return false end
    for _, cd in ipairs(entries) do
        if cd.isAvailable() and cd.match(row) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Responsive column widths
-- ---------------------------------------------------------------------------
-- The Cooldowns tab adapts its column widths to the available content area
-- so a user-resized window squeezes the columns gracefully instead of
-- clipping rows off the right edge. COL_MIN sets the lower bound for each
-- top-level column; below the sum of these the resize bound on the frame
-- prevents further dragging. COL_PREFER is the comfortable / max width.
-- Fixed column widths. Cooldowns previously computed widths from window
-- size on every WINDOW_RESIZED redraw, but that meant AceGUI Flow inside
-- each rowGroup reflowed mid-drag (the user perceived this as "rows
-- stacking into 2-3 lines and snapping back when the drag stops"). The
-- MissingRecipesTab and BrowserTab don't have this problem because their
-- virtual-scroll rows are raw CreateFrame frames at fixed widths — Flow
-- never re-runs on them. We get the same smooth-resize behaviour by just
-- using fixed widths here and letting wider windows leave empty space on
-- the right of the rows, instead of stretching.
--
-- col2 = 360 covers icon(18) + cdName(80) + reagent(80) + [AH](40) +
-- [Bank](40) + mail(20) + Flow inter-widget slack (40) + 42px headroom
-- so the [AH] button has definite room when scan results gate it on.
-- time = 80 fits the "Time Left" header comfortably (below ~70 it wraps).
local COL_W      = { char = 140, col2 = 360, time = 80 }
-- Total width the row needs, exposed so MainWindow can size the frame's
-- SetResizeBounds correctly — preventing the user from dragging the
-- window below the point where columns would clip past the right edge.
-- With fixed widths (no responsive shrinking), this IS the row width
-- always — not just a floor.
CooldownsTab.MIN_ROW_WIDTH = COL_W.char + COL_W.col2 + COL_W.time  -- 580

-- Window size policy for this tab — read by MainWindow on tab switch
-- and on Open. `locked = true` means the resize grip is disabled and
-- the frame snaps to width/height. Cooldowns and Missing share the
-- SAME locked dimensions so switching between those two tabs produces
-- no visible jump (only switching to/from Browser changes the size).
CooldownsTab.WINDOW_SIZE = { width = 720, height = 500, locked = true }

-- Inside col2 (the "Cooldown" column), widget widths break down as
-- icon + cdName + reagent + [AH] + [Bank] + mail. icon / [AH] / [Bank] /
-- mail are fixed-width; cdName + reagent share the remaining space.
local C2_ICON      = 18
local C2_MAIL      = 20
local C2_AH_BTN    = 40
local C2_BANK_BTN  = 40
local C2_MIN_NAME  = 80
local C2_MIN_RGNT  = 80

--- Compute inner col2 widths for the fixed col2 width and which buttons
--- are currently shown for this row. Returns iconW, cdNameW, reagentW,
--- ahW, bankW, mailW.
---
--- Reserves ~40px of internal slack for AceGUI Flow's per-widget gaps
--- between col2's children (icon / cdName / reagent / AH / Bank / mail —
--- up to 5 inter-widget gaps). Without the slack, the children sum
--- to col2W exactly; Flow then can't fit them on one line, wraps the last
--- few widgets to a second line, and col2 becomes ~2 rows tall — which
--- visually pushes the row's Time Left column off to look like it's on
--- the row below.
local function ComputeCol2InnerWidths(col2W, hasReagent, hasAH, hasBank)
    local mailW = hasReagent and C2_MAIL    or 0
    local ahW   = hasAH      and C2_AH_BTN  or 0
    local bankW = hasBank    and C2_BANK_BTN or 0
    local fixed = C2_ICON + mailW + ahW + bankW
    -- 40px slack for AceGUI Flow's per-widget gaps inside col2 (up to 5
    -- inter-widget gaps × ~8px). Without enough slack the children sum
    -- exceeds col2W and Flow wraps the last few widgets to a second line,
    -- which makes col2 visually 2 rows tall and pushes the row's data
    -- (including the Time Left text) onto a second visual row.
    local internal_slack = 40
    local variable = col2W - fixed - internal_slack
    if variable < (C2_MIN_NAME + (hasReagent and C2_MIN_RGNT or 0)) then
        variable = C2_MIN_NAME + (hasReagent and C2_MIN_RGNT or 0)
    end
    if not hasReagent then
        return C2_ICON, math.max(C2_MIN_NAME, variable), 0, ahW, bankW, mailW
    end
    -- 50/50 split between cdName and reagent, with per-side minimums.
    local cdNameW  = math.max(C2_MIN_NAME, math.floor(variable * 0.5))
    local reagentW = math.max(C2_MIN_RGNT, variable - cdNameW)
    return C2_ICON, cdNameW, reagentW, ahW, bankW, mailW
end

--- Disable word-wrap on an AceGUI Label / InteractiveLabel widget — text
--- that's slightly too wide for the cell truncates instead of wrapping
--- to a second line and inflating the row height. AceGUI's internal
--- fontstring lives at widget.label; SetWordWrap(false) was added to
--- WoW FontString in patch 3.0 so we guard for older clients.
--- Module-level so DrawHeaders, DrawRow, and the group popup all share
--- the same helper — applied to every Label-style widget the cooldowns
--- table renders so wrap is impossible anywhere.
local function nowrap(w)
    if w and w.label and w.label.SetWordWrap then
        w.label:SetWordWrap(false)
    end
end

-- Leak-safe wrapper for `widget.frame:SetScript(...)` on AceGUI widgets.
-- Used here only for the rowGroup right-click handler — SimpleGroup has
-- no native OnMouseDown dispatch so we have to install a raw script and
-- restore the prior one on release. For Button / Dropdown / EditBox use
-- widget:SetCallback("OnEnter"/"OnLeave"/...) instead — those widgets'
-- Constructors install their own internal Control_OnEnter dispatch that
-- fires the SetCallback registry, and AceGUI clears the registry on
-- release for free. See addon.AceGUIFrameScripts in MainWindow.lua.
local frameScripts = addon.AceGUIFrameScripts

-- (Removed: GetAvailableWidth + ComputeColWidths. The cooldowns tab now
-- uses fixed COL_W widths so rows don't reflow during resize-drag — same
-- smoothness as the Missing/Browser tabs which also use fixed widths.)

-- Keep row height consistent with MissingRecipesTab so text baselines align
-- visually the same across both locked-size tabs.
local ROW_HEIGHT = 16

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function SecondsToString(secs)
    if secs <= 0 then return L["Ready"] end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    if d > 0 then
        if h > 0 then return string.format("%dd %dh", d, h) end
        return string.format("%dd", d)
    elseif h > 0 then
        if m > 0 and h < 24 then return string.format("%dh %dm", h, m) end
        return string.format("%dh", h)
    end
    return string.format("%dm", m)
end

--- Build the flat list of rows to render.
-- Returns array of:
-- { charKey, shortName, spellId, cdName, reagentItemId, expiresAt,
--   isGroup, group, isTransmuteGroup, transmutes, transmuteReagents }
-- When viewMode == "mine", walk every bucket in addon.guildDb.global.guilds
-- and merge their cooldown maps (own characters only) so guildless / cross-
-- guild alts surface in the Cooldowns tab. When viewMode is anything else,
-- just return the current guild bucket's cooldown map. The walk is local-
-- read-only — no network involvement.
local function CollectCooldownsByChar(viewMode)
    if viewMode == "mine" then
        local merged = {}
        addon:ForEachGuildBucket(function(bucket)
            for charKey, charCds in pairs(bucket.cooldowns or {}) do
                if addon:IsMyCharacter(charKey) then
                    if not merged[charKey] then merged[charKey] = {} end
                    for spellId, expiresAt in pairs(charCds) do
                        -- Latest expiresAt wins if the same char's data appears
                        -- in multiple buckets (e.g., stale entry left behind
                        -- after switching guilds).
                        local existing = merged[charKey][spellId]
                        if not existing or expiresAt > existing then
                            merged[charKey][spellId] = expiresAt
                        end
                    end
                end
            end
        end)
        return merged
    end
    local gdb = addon:GetGuildDb()
    return gdb and gdb.cooldowns or {}
end

local function BuildRows(readyOnly, viewMode)
    local gdb = addon:GetGuildDb()
    if not gdb then return {} end

    -- Refresh the transmute catalogue from the recipe DB so any alchemist
    -- spellIds that arrived via guild sync are recognised as transmutes.
    -- Without this, non-alchemist viewers only have the static VANILLA_TRANSMUTES
    -- IDs in data.transmutes — Anniversary client IDs that the alchemist
    -- broadcast (with their own GetSpellLink fallback) don't match, so the
    -- cooldown row falls through the "is this a transmute?" check and renders
    -- as a regular row showing the specific spell name (e.g., "Earth to Water")
    -- instead of the generic "[+] Transmute" group with the per-spell popup.
    -- ScanCooldowns calls this too, but only fires on the LOCAL player's scan
    -- events; non-alchemists rarely trigger it.  Cheap and idempotent.
    if addon.RefreshTransmuteCatalogueFromRecipes then
        addon:RefreshTransmuteCatalogueFromRecipes()
    end

    local data = addon:GetCooldownData()
    local now  = GetServerTime()
    local rows = {}

    -- Accumulate transmute spells per player before emitting rows.
    -- All transmutes for one player collapse into a single "Transmute" group row.
    local transmuteGroups = {}  -- [charKey] = { spellIds={}, expiresAt }

    for charKey, charCds in pairs(CollectCooldownsByChar(viewMode)) do
        local shortName = charKey:match("^(.-)%-") or charKey

        -- Track which non-transmute group keys we've already emitted.
        local emittedGroups = {}

        for spellId, expiresAt in pairs(charCds) do
            local remaining = expiresAt - now

            if data.transmutes[spellId] then
                -- Accumulate into this player's transmute group.
                if not transmuteGroups[charKey] then
                    transmuteGroups[charKey] = { shortName = shortName, spellIds = {}, expiresAt = now - 1 }
                end
                local tg = transmuteGroups[charKey]
                tg.spellIds[#tg.spellIds + 1] = spellId
                -- Track the active expiry (past = ready; keep the most-future value).
                if expiresAt > now and expiresAt > tg.expiresAt then
                    tg.expiresAt = expiresAt
                end

            else
                local group = data.groupBySpell and data.groupBySpell[spellId]
                if group then
                    -- Emit a single group row the first time we see any spell from this group.
                    if not emittedGroups[group.groupKey] then
                        emittedGroups[group.groupKey] = true
                        -- Find the longest remaining CD in the group for this char.
                        local groupExpiry = expiresAt
                        for groupSpellId in pairs(group.spells) do
                            local ge = charCds[groupSpellId]
                            if ge and ge > groupExpiry then groupExpiry = ge end
                        end
                        local groupRemaining = groupExpiry - now
                        if not readyOnly or groupRemaining <= 0 then
                            table.insert(rows, {
                                charKey       = charKey,
                                shortName     = shortName,
                                spellId       = spellId,
                                cdName        = group.label,
                                reagentItemId = nil,
                                expiresAt     = groupExpiry,
                                isGroup       = true,
                                group         = group,
                            })
                        end
                    end
                elseif data.cooldowns[spellId] or spellId == data.saltShakerItem then
                    -- v0.7.2: only render single-spell rows when the spell ID
                    -- is in the explicit whitelist (data.cooldowns from
                    -- Data/CooldownIds.lua, or the Salt Shaker item ID).
                    -- Stops stale junk like Impact 12360 (Fire Mage talent)
                    -- or Portal: Undercity from rendering as cooldown rows
                    -- when they happen to be left over in gdb.cooldowns
                    -- from old code paths or buggy peer broadcasts. The
                    -- one-shot RemoveBogusCooldowns sweep at OnInitialize
                    -- evicts them from the SV; this guard catches anything
                    -- that slips back in via future inbound payloads.
                    -- v0.7.2: also hide Salt Shaker rows for TOGBankClassic
                    -- banker alts. Reported case — a bank toon with no
                    -- cooking surfaces a stale Salt Shaker CD record
                    -- (legacy data from before the char was repurposed,
                    -- or stale peer broadcast under the wrong charKey).
                    -- Bankers can't cast Salt Shaker, so the row is
                    -- pure noise. Gated on TOGBank being loaded; no-op
                    -- when it isn't.
                    if spellId == data.saltShakerItem
                       and addon.Bank and addon.Bank.IsBanker
                       and addon.Bank.IsBanker(charKey) then
                        -- skip — banker alt, can't use Salt Shaker
                    elseif not readyOnly or remaining <= 0 then
                        -- Salt Shaker stores its cooldown under the ITEM id
                        -- (15846), which is also a valid SPELL id — namely
                        -- "Veil of Shadow," a generic NPC ability. Without
                        -- this special case GetSpellInfo wins the fallback
                        -- chain and the row labels as "Veil of Shadow"
                        -- instead of "Salt Shaker." Resolve item-based
                        -- cooldowns through GetItemInfo first.
                        local cdName
                        if spellId == data.saltShakerItem then
                            cdName = GetItemInfo(spellId) or "Salt Shaker"
                        else
                            cdName = data.cooldowns[spellId] or GetSpellInfo(spellId) or GetItemInfo(spellId) or tostring(spellId)
                        end
                        local reagentItemId = data.reagents[spellId] and data.reagents[spellId].id
                        local reagentQty    = data.reagents[spellId] and data.reagents[spellId].qty or 1
                        local iconItemId    = data.iconOverrides and data.iconOverrides[spellId]
                        local outputName    = (data.outputOverrides and data.outputOverrides[spellId]) or cdName
                        table.insert(rows, {
                            charKey       = charKey,
                            shortName     = shortName,
                            spellId       = spellId,
                            cdName        = cdName,
                            outputName    = outputName,
                            reagentItemId = reagentItemId,
                            reagentQty    = reagentQty,
                            iconItemId    = iconItemId,
                            expiresAt     = expiresAt,
                            isGroup       = false,
                        })
                    end
                end
            end
        end
    end

    -- Emit one transmute row per player.
    for charKey, tg in pairs(transmuteGroups) do
        local remaining = tg.expiresAt - now
        if not readyOnly or remaining <= 0 then
            -- Build the popup entries list.  Each entry is one row in the
            -- popup — for transmutes that take multiple reagents (e.g.,
            -- Arcanite Bar = Thorium Bar + Arcane Crystal), we emit ONE row
            -- per reagent so the user can [Bank]-request or mail each
            -- independently.  showName/showTime flags collapse repeated
            -- name/time labels: they appear only on the first row of a
            -- multi-reagent transmute, leaving sibling rows visually grouped.
            local entries = {}
            local seenSpellIds = {}

            local function emitTransmute(spellId, displayName, recipeId, reagents)
                if #reagents == 0 then
                    table.insert(entries, {
                        spellId = spellId, name = displayName, recipeId = recipeId,
                        showName = true, showTime = true,
                    })
                    return
                end
                for ri, r in ipairs(reagents) do
                    table.insert(entries, {
                        spellId    = spellId,
                        name       = displayName,
                        recipeId   = recipeId,
                        reagentId  = r.id,
                        reagentQty = r.qty,
                        showName   = ri == 1,
                        showTime   = ri == 1,
                    })
                end
            end

            -- v0.7.0: build the spellId → recipe lookup from addon.recipeDB
            -- (authoritative metadata, shipped with the addon) intersected
            -- with this character's known-recipe set from gdb. The crafters
            -- table now only stores presence + guild tag — name/reagents/
            -- spellId come from addon.recipeDB[171][recipeId].
            local recipeBySpellId = {}
            local profRecipeDB    = addon.recipeDB and addon.recipeDB[171]
            local charKnownAlch   = (gdb.recipes and gdb.recipes[171]) or {}
            if profRecipeDB then
                for recipeId, meta in pairs(profRecipeDB) do
                    local rd = charKnownAlch[recipeId]
                    if rd and rd.crafters and rd.crafters[charKey]
                       and type(meta.name) == "string"
                       and meta.name:find("[Tt]ransmute") then
                        -- The spell taught by this recipe. Most TBC/Wrath
                        -- recipes carry teaches = the actual transmute spell;
                        -- for Enchanting-style spell-keyed recipes recipeId
                        -- itself is the spell.
                        local spellId = meta.teaches or recipeId
                        recipeBySpellId[spellId] = {
                            recipeId = recipeId,
                            name     = meta.name,
                            reagents = meta.reagents,
                        }
                    end
                end
            end

            -- Reagent helper. addon.recipeDB ships reagents as { [itemId] = count };
            -- convert to the { id, qty } shape this tab expects.
            local function reagentsFor(spellId, hit)
                local reagents = {}
                if hit and type(hit.reagents) == "table" then
                    for itemId, count in pairs(hit.reagents) do
                        reagents[#reagents + 1] = { id = itemId, qty = count or 1 }
                    end
                end
                if #reagents == 0 and spellId
                   and data.transReagents and data.transReagents[spellId] then
                    local rg = data.transReagents[spellId]
                    reagents[1] = { id = rg.id, qty = rg.qty or 1 }
                end
                return reagents
            end

            -- Cooldown-derived entries (definite spellIds, on cooldown).
            -- v0.7.2: only emit when the char actually knows this recipe
            -- as a transmute (hit). The earlier "spell name contains
            -- 'Transmute'" fallback emitted entries for stale cooldown
            -- IDs the char no longer knows — e.g., transmutes they had
            -- on CD before re-rolling / unlearning alchemy, transmutes
            -- inherited from pre-v0.7.0 data, or peer-broadcast pollution
            -- under wrong charKey. Requiring `hit` keeps the popup
            -- pinned to the char's CURRENT alchemy knowledge.
            for _, sid in ipairs(tg.spellIds) do
                seenSpellIds[sid] = true
                local hit = recipeBySpellId[sid]
                if hit then
                    emitTransmute(sid, hit.name, hit.recipeId, reagentsFor(sid, hit))
                end
            end

            -- Recipe-DB-derived entries (transmutes the char knows but
            -- hasn't cast — not yet in tg.spellIds).
            for spellId, hit in pairs(recipeBySpellId) do
                if not seenSpellIds[spellId] then
                    seenSpellIds[spellId] = true
                    emitTransmute(spellId, hit.name, hit.recipeId, reagentsFor(spellId, hit))
                end
            end

            -- Sort by name, keeping multi-reagent rows of the same transmute
            -- adjacent (showName=true row first, then siblings).
            table.sort(entries, function(a, b)
                if a.name ~= b.name then return (a.name or "") < (b.name or "") end
                if a.showName ~= b.showName then return a.showName == true end
                return false
            end)
            table.insert(rows, {
                charKey           = charKey,
                shortName         = tg.shortName,
                spellId           = tg.spellIds[1],
                cdName            = L["Transmute"],
                reagentItemId     = nil,
                expiresAt         = tg.expiresAt,
                isGroup           = true,
                isTransmuteGroup  = true,
                transmuteEntries  = entries,
            })
        end
    end

    return rows
end

local function SortRows(rows, col, asc)
    local now = GetServerTime()
    table.sort(rows, function(a, b)
        local va, vb
        if col == "char" then
            va, vb = a.shortName:lower(), b.shortName:lower()
        elseif col == "cd" then
            va, vb = a.cdName:lower(), b.cdName:lower()
        else  -- "time"
            va, vb = a.expiresAt - now, b.expiresAt - now
            -- Ready (<=0) sorts to the top when ascending.
            if va <= 0 then va = -math.huge end
            if vb <= 0 then vb = -math.huge end
        end
        -- Stable tiebreaker (cooldown name → character name, both ascending
        -- regardless of the primary asc flag). Without this, equal-keyed
        -- rows — most notably every ready cooldown all tied at -math.huge —
        -- shuffle into a different order every redraw because Lua's
        -- table.sort is not stable. Now the Ready Only view stays in a
        -- predictable A-Z order across refreshes.
        if va == vb then
            local na, nb = (a.cdName or ""):lower(), (b.cdName or ""):lower()
            if na ~= nb then return na < nb end
            return (a.shortName or ""):lower() < (b.shortName or ""):lower()
        end
        if asc then return va < vb else return va > vb end
    end)
end

-- ---------------------------------------------------------------------------
-- Supply mail helpers (ported from reference cooldowns-panel.lua)
-- ---------------------------------------------------------------------------

--- Scan bags 0-4 for all stacks of itemId.
-- Returns total (number), stacks ({ {bag,slot,count}, ... })
local function CdMail_CountItemInBags(itemId)
    local total, stacks = 0, {}
    for bag = 0, 4 do
        local numSlots = addon:GetContainerNumSlots(bag)
        for slot = 1, (numSlots or 0) do
            local info = addon:GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemId and (info.stackCount or 0) > 0 then
                total = total + info.stackCount
                table.insert(stacks, { bag = bag, slot = slot, count = info.stackCount })
            end
        end
    end
    return total, stacks
end

--- Greedy fulfillment plan — returns { canFulfill, reason, stacksToAttach, splitStack, totalAttachable }.
local function CdMail_CalculateFulfillmentPlan(items, qtyNeeded, totalInBags)
    if not items or #items == 0 then
        return { canFulfill = false, reason = "No items found in bags.", stacksToAttach = {}, totalAttachable = 0 }
    end
    for i, item in ipairs(items) do item.originalIndex = i end
    table.sort(items, function(a, b)
        if a.count == b.count then return a.originalIndex < b.originalIndex end
        return a.count > b.count
    end)
    local accumulated, attachList = 0, {}
    for _, item in ipairs(items) do
        local remaining = qtyNeeded - accumulated
        if item.count <= remaining then
            accumulated = accumulated + item.count
            table.insert(attachList, { bag = item.bag, slot = item.slot, count = item.count, originalIndex = item.originalIndex })
        end
    end
    if accumulated == qtyNeeded then
        return { canFulfill = true, stacksToAttach = attachList, totalAttachable = accumulated }
    end
    if accumulated < qtyNeeded and totalInBags >= qtyNeeded then
        local bestAcc, bestList = accumulated, attachList
        for skipIdx = 1, math.min(5, #items) do
            local testAcc, testList = 0, {}
            for i, item in ipairs(items) do
                if i ~= skipIdx then
                    local rem = qtyNeeded - testAcc
                    if item.count <= rem then
                        testAcc = testAcc + item.count
                        table.insert(testList, { bag = item.bag, slot = item.slot, count = item.count, originalIndex = item.originalIndex })
                    end
                end
            end
            if testAcc == qtyNeeded then
                return { canFulfill = true, stacksToAttach = testList, totalAttachable = testAcc }
            end
            if testAcc > bestAcc and testAcc < qtyNeeded then bestAcc, bestList = testAcc, testList end
        end
        accumulated, attachList = bestAcc, bestList
    end
    if accumulated < qtyNeeded and totalInBags >= qtyNeeded then
        local remaining = qtyNeeded - accumulated
        for _, item in ipairs(items) do
            if item.count >= remaining then
                local alreadyIn = false
                for _, a in ipairs(attachList) do
                    if a.originalIndex == item.originalIndex then alreadyIn = true; break end
                end
                if not alreadyIn then
                    return { canFulfill = true,
                             reason = string.format("Split %d from stack of %d.", remaining, item.count),
                             stacksToAttach = attachList,
                             splitStack = { bag = item.bag, slot = item.slot, count = item.count, amount = remaining },
                             totalAttachable = accumulated }
                end
            end
        end
    end
    if accumulated == 0 and totalInBags >= qtyNeeded then
        local s = items[1]
        return { canFulfill = true,
                 reason = string.format("Split from stack of %d.", s.count),
                 stacksToAttach = {},
                 splitStack = { bag = s.bag, slot = s.slot, count = s.count, amount = qtyNeeded },
                 totalAttachable = 0 }
    end
    return { canFulfill = false,
             reason = string.format("Need %d more.", qtyNeeded - totalInBags),
             stacksToAttach = {}, totalAttachable = totalInBags }
end

if not StaticPopupDialogs["TOGPM_SPLIT_STACK"] then
    StaticPopupDialogs["TOGPM_SPLIT_STACK"] = {
        text = "%s",
        button1 = "Split",
        button2 = "Cancel",
        OnAccept = function(self, data)
            if not data then return end
            ClearCursor()
            local emptyBag, emptySlot
            for bag = 0, 4 do
                local n = addon:GetContainerNumSlots(bag)
                for slot = 1, (n or 0) do
                    if not addon:GetContainerItemInfo(bag, slot) then
                        emptyBag, emptySlot = bag, slot; break
                    end
                end
                if emptyBag then break end
            end
            if not emptyBag then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r " .. L["MailMsgNoEmptyBag"])
                return
            end
            if C_Container then
                C_Container.SplitContainerItem(data.bag, data.slot, data.amount)
                C_Timer.After(0.1, function()
                    C_Container.PickupContainerItem(emptyBag, emptySlot)
                    C_Timer.After(0.05, function()
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(
                            "|cFF88CCCCTOG Profession Master:|r Split %d x %s — click Mail again to attach.",
                            data.amount, (data.itemName or "items")))
                    end)
                end)
            else
                SplitContainerItem(data.bag, data.slot, data.amount)
                C_Timer.After(0.1, function()
                    PickupContainerItem(emptyBag, emptySlot)
                end)
            end
        end,
        OnCancel = function() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

--- Open mailbox, attach reagents, pre-fill recipient/subject/body.
local function CdMail_PrepareSupplyMail(playerName, cooldownName, outputName, reagentId, reagentQty)
    if not MailFrame or not MailFrame:IsShown() then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r " .. L["MailMsgOpenMailbox"])
        return
    end
    if GetSendMailItem(1) then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r " .. L["MailMsgHasItems"])
        return
    end
    local reagentName = GetItemInfo(reagentId) or ("item:" .. reagentId)
    local totalInBags, stacks = CdMail_CountItemInBags(reagentId)
    if totalInBags == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFF4444TOG Profession Master:|r You have no %s in your bags.", reagentName))
        return
    end
    local plan = CdMail_CalculateFulfillmentPlan(stacks, reagentQty, totalInBags)
    if not plan.canFulfill then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r " .. (plan.reason or L["MailMsgCannotFulfill"]))
        return
    end
    if plan.splitStack then
        local s = plan.splitStack
        local dialog = StaticPopup_Show("TOGPM_SPLIT_STACK",
            string.format("Split %d from stack of %d %s?", s.amount, s.count, reagentName))
        if dialog then
            dialog.data = { bag = s.bag, slot = s.slot, amount = s.amount, itemName = reagentName }
        end
        return
    end
    local attached, attachSlot = 0, 1
    local maxSlots = ATTACHMENTS_MAX_SEND or 12
    for _, stack in ipairs(plan.stacksToAttach) do
        if attached >= reagentQty or attachSlot > maxSlots then break end
        ClearCursor()
        if C_Container then
            C_Container.PickupContainerItem(stack.bag, stack.slot)
        else
            PickupContainerItem(stack.bag, stack.slot)
        end
        ClickSendMailItemButton(attachSlot)
        attached = attached + stack.count
        attachSlot = attachSlot + 1
    end
    if attached == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r " .. L["MailMsgCouldNotAttach"])
        return
    end
    local baseName = playerName:match("^([^%-]+)") or playerName
    if SendMailNameEditBox then SendMailNameEditBox:SetText(baseName) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(string.format(L["MailSubjectFormat"], cooldownName)) end
    local bodyBox = MailEditBox or SendMailBodyEditBox
    if bodyBox then
        bodyBox:SetText(string.format(L["MailBodyFormat"], baseName, outputName, outputName))
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cFF88CCCCTOG Profession Master:|r " ..
        string.format(L["MailMsgAttachedFormat"], attached, reagentName, baseName))
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function CooldownsTab:Draw(container)
    -- Flow layout (not List) so the ScrollFrame's SetFullHeight(true) actually
    -- works.  AceGUI's List layout ignores child.height == "fill"; only Flow
    -- honors it (anchors the child's BOTTOM to parent content).  Without this
    -- the scroll frame and its scrollbar grow unbounded past the window edge.
    -- Toolbar + headers + scroll all SetFullWidth(true), so Flow stacks them
    -- vertically the same way List did.
    container:SetLayout("Flow")

    -- Fixed column widths — see COL_W comment block. No more responsive
    -- recomputation per resize; rows stay put as the window drags wider
    -- or narrower (matching the Missing/Browser tab feel).
    self._colWidths = COL_W

    -- ---- Toolbar -----------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    local readyBtn = AceGUI:Create("Button")
    readyBtn:SetText(self._readyOnly and L["ShowAll"] or L["ReadyOnly"])
    readyBtn:SetWidth(90)
    readyBtn:SetCallback("OnClick", function(_widget)
        self._readyOnly = not self._readyOnly
        _widget:SetText(self._readyOnly and L["ShowAll"] or L["ReadyOnly"])
        self:RedrawTable(container)
    end)
    toolbar:AddChild(readyBtn)

    -- Two-level filter: Profession dropdown → Cooldown dropdown. Mirrors the
    -- BrowserTab / MissingRecipesTab dropdown style. The cooldown dropdown
    -- lists shared-timer entries from COOLDOWN_BY_PROFESSION (e.g. all
    -- transmutes collapse to one "Transmute" entry under Alchemy), so it
    -- doesn't get janky for alchemists with 11 individual transmute spells.
    -- When profession is "All", the cooldown dropdown is hidden — there's
    -- nothing meaningful to filter by until the user narrows the scope.
    local brand = addon.BrandColor or "ffFF8000"

    -- Build the profession dropdown from COOLDOWN_BY_PROFESSION (only
    -- professions that have at least one cooldown applicable to the
    -- current client version make the cut). Belt-and-suspenders the
    -- per-cooldown isAvailable() check with addon.IsProfessionAvailable
    -- — defensive against any future profession-level gating that the
    -- per-cooldown predicates might miss. Names from the shared
    -- addon.PROF_NAMES master table.
    local profList  = { [0] = L["AllProfessions"] }
    local profOrder = { 0 }
    for profId, entries in pairs(COOLDOWN_BY_PROFESSION) do
        if addon.IsProfessionAvailable(profId) then
            local anyAvailable = false
            for _, cd in ipairs(entries) do
                if cd.isAvailable() then anyAvailable = true; break end
            end
            if anyAvailable then
                profList[profId] = addon.PROF_NAMES[profId] or ("Profession " .. profId)
                profOrder[#profOrder + 1] = profId
            end
        end
    end
    table.sort(profOrder, function(a, b)
        if a == 0 then return true end
        if b == 0 then return false end
        return (profList[a] or ""):lower() < (profList[b] or ""):lower()
    end)

    if not self._filterProfId then
        self._filterProfId = 0
    end

    local multiProfOrder = {}
    for _, profId in ipairs(profOrder) do
        if profId ~= 0 then
            multiProfOrder[#multiProfOrder + 1] = profId
        end
    end

    -- Add "All Professions" at the start
    local profDropdownList = { [0] = L["AllProfessions"] }
    local profDropdownOrder = { 0 }
    for _, profId in ipairs(multiProfOrder) do
        profDropdownList[profId] = profList[profId]
        profDropdownOrder[#profDropdownOrder + 1] = profId
    end

    local profDropdown = AceGUI:Create("Dropdown")
    profDropdown:SetLabel("|c" .. brand .. L["FilterColProfession"] .. "|r")
    profDropdown:SetWidth(135)
    addon.GUI.OffsetInputLabel(profDropdown)
    profDropdown:SetList(profDropdownList, profDropdownOrder)
    profDropdown:SetValue(self._filterProfId or 0)
    profDropdown:SetCallback("OnValueChanged", function(_w, _e, value)
        self._filterProfId = value
        self._filterCd = "all"  -- reset specific-cooldown filter on profession change
        self:RedrawTable(container)
    end)
    addon.GUI.AttachTooltip(profDropdown, L["FilterColProfession"], "Pick a profession to filter cooldowns.")
    toolbar:AddChild(profDropdown)

    -- Cooldown dropdown is only meaningful once a specific profession is
    -- selected. Skip rendering it when profession is "All" — keeps the
    -- toolbar compact and avoids a "Cooldown ▼" stub that does nothing.
    if self._filterProfId and self._filterProfId ~= 0 then
        local cdList  = { ["all"] = L["AllCooldowns"] }
        local cdOrder = { "all" }
        for _, cd in ipairs(COOLDOWN_BY_PROFESSION[self._filterProfId] or {}) do
            if cd.isAvailable() then
                cdList[cd.id] = L[cd.labelKey] or cd.id
                cdOrder[#cdOrder + 1] = cd.id
            end
        end
        table.sort(cdOrder, function(a, b)
            if a == "all" then return true end
            if b == "all" then return false end
            return (cdList[a] or ""):lower() < (cdList[b] or ""):lower()
        end)

        if not cdList[self._filterCd] then self._filterCd = "all" end

        local cdDD = AceGUI:Create("Dropdown")
        cdDD:SetLabel("|c" .. brand .. L["FilterColCooldown"] .. "|r")
        cdDD:SetWidth(155)
        cdDD:SetList(cdList, cdOrder)
        cdDD:SetValue(self._filterCd or "all")
        addon.GUI.OffsetInputLabel(cdDD)
        cdDD:SetCallback("OnValueChanged", function(_w, _e, value)
            self._filterCd = value
            self:RedrawTable(container)
        end)
        addon.GUI.AttachTooltip(cdDD, L["FilterColCooldown"], L["FilterCooldownDesc"])
        toolbar:AddChild(cdDD)
    end

    -- Scope dropdown: Guild (every guild member) vs My Characters (own alts
    -- only). Mirrors the Browser tab's view-mode dropdown so the two tabs
    -- behave the same way when the user wants to focus on their own
    -- cooldowns. State is session-only (not persisted to AceDB) to match
    -- the existing profession/cooldown filters above.
    local viewDD = AceGUI:Create("Dropdown")
    viewDD:SetLabel("|c" .. brand .. L["FilterColView"] .. "|r")
    viewDD:SetWidth(115)
    viewDD:SetList({ guild = L["ViewGuild"], mine = L["ViewMine"] },
                   { "guild", "mine" })
    viewDD:SetValue(self._viewMode or "guild")
    addon.GUI.OffsetInputLabel(viewDD)
    viewDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._viewMode = value
        self:RedrawTable(container)
    end)
    addon.GUI.AttachTooltip(viewDD, L["FilterColView"], L["FilterViewDesc"])
    toolbar:AddChild(viewDD)

    -- 8px spacer matching the existing toolbar gap convention.
    local sp4 = AceGUI:Create("Label"); sp4:SetWidth(8); toolbar:AddChild(sp4)

    -- Scan AH button — kicks off a throttled scan over every unique reagent
    -- itemId in the currently-visible cooldown rows (after filter applied).
    -- After completion, rows whose reagent has live AH listings get an
    -- [AH] button left of [Bank] (gates on AH.GetListingsFor — same pattern
    -- as [Bank] gating on Bank.GetStock). All boilerplate (label refresh,
    -- AH state gating, scan dispatch, AH callbacks) lives in the shared
    -- factory; this site only owns the per-tab item-collection logic.
    addon.GUI.MakeScanAHButton({
        parent        = toolbar,
        tabName       = "cooldowns",
        label         = L["BrowserScanAH"],
        progressLabel = L["BrowserScanAHProgress"],
        tooltipTitle  = L["BrowserScanAH"],
        tooltipDesc   = L["CooldownsScanAHDesc"],
        noItemsError  = "No reagents to scan in the current view.",
        getItems      = function()
            local rows = BuildRows(self._readyOnly, self._viewMode)
            local profId = self._filterProfId or 0
            local cdId   = self._filterCd   or "all"
            if profId ~= 0 then
                local kept = {}
                for _, row in ipairs(rows) do
                    if ProfessionMatchesRow(profId, row) then
                        kept[#kept + 1] = row
                    end
                end
                rows = kept
            end
            if profId ~= 0 and cdId ~= "all" then
                local kept = {}
                local cdEntry
                for _, cd in ipairs(COOLDOWN_BY_PROFESSION[profId] or {}) do
                    if cd.id == cdId then cdEntry = cd; break end
                end
                if cdEntry then
                    for _, row in ipairs(rows) do
                        if cdEntry.match(row) then
                            kept[#kept + 1] = row
                        end
                    end
                end
                rows = kept
            end
            -- Match the visible-rows scope filter so Scan AH only walks
            -- reagents the user can actually see in the list.
            if (self._viewMode or "guild") == "mine" then
                local kept = {}
                for _, row in ipairs(rows) do
                    if addon:IsMyCharacter(row.charKey) then
                        kept[#kept + 1] = row
                    end
                end
                rows = kept
            end
            local items, seen = {}, {}
            local function addItem(id)
                if not id or seen[id] then return end
                local name = GetItemInfo(id)
                if type(name) == "string" and name ~= "" then
                    seen[id] = true
                    items[#items + 1] = { itemId = id, itemName = name }
                end
            end
            for _, row in ipairs(rows) do
                if row.isTransmuteGroup and row.transmuteEntries then
                    -- Transmute group rows have row.reagentItemId == nil
                    -- because each transmute spell inside the group has
                    -- its own reagent (sometimes multiple — e.g.
                    -- Arcanite needs Thorium Bar + Arcane Crystal).
                    -- Iterate the per-spell entries to pick up every
                    -- reagent so the scan covers the actual transmutes
                    -- the user can craft, not just the standalone non-
                    -- transmute cooldowns (Salt Shaker, Mooncloth, etc.).
                    for _, e in ipairs(row.transmuteEntries) do
                        addItem(e.reagentId)
                    end
                else
                    addItem(row.reagentItemId)
                end
            end
            return items
        end,
        onRefresh     = function()
            -- Re-fill rows so [AH] buttons appear/disappear with scan
            -- results. ReleaseChildren on _scroll only — preserves toolbar
            -- and headers (and crucially the live scanBtn).
            local scroll = CooldownsTab._scroll
            if scroll and scroll.ReleaseChildren then
                scroll:ReleaseChildren()
                CooldownsTab:FillRows(scroll)
                if scroll.DoLayout then scroll:DoLayout() end
            end
        end,
    })

    -- ---- Column headers ----------------------------------------------------
    local headers = AceGUI:Create("SimpleGroup")
    headers:SetLayout("Flow")
    headers:SetFullWidth(true)
    container:AddChild(headers)
    self:DrawHeaders(headers, container)

    -- ---- Scrollable rows ---------------------------------------------------
    -- Persist scroll position across redraws so sync-triggered
    -- GUILD_DATA_UPDATED rebuilds (every few seconds in active guilds)
    -- and filter changes don't yank the user back to the top. Shared
    -- helper handles SetStatusTable + saved-value capture; we just have
    -- to call Restore() after FillRows + DoLayout so SetScroll can
    -- derive a correct offset from the now-known content height.
    local scroll, saved = addon.GUI.PersistentScroll.Acquire(self, {
        key        = "cooldowns",
        layout     = "List",
        fullWidth  = true,
        fullHeight = true,
        onRelease  = function() self:DetachPopup() end,
    })
    container:AddChild(scroll)
    self._scroll    = scroll
    self._container = container

    self:FillRows(scroll)
    if scroll.DoLayout then scroll:DoLayout() end
    addon.GUI.PersistentScroll.Restore(scroll, saved)
end

function CooldownsTab:DetachPopup()
    if self._groupPopup then
        if self._groupPopup._closeOnClick then
            addon.GUI.DetachPool(self._groupPopup._closeOnClick)
        end
        addon.GUI.DetachPool(self._groupPopup)
        self._groupPopup = nil
    end
end

function CooldownsTab:DrawHeaders(parent, container)
    -- Column widths are fixed (COL_W) — same widths for headers and data
    -- rows, so the header columns visually align with the row contents.
    -- self._colWidths is set in Draw() to COL_W before this runs.
    local cw = self._colWidths or { char = 190, col2 = 456, time = 80 }
    local cols = {
        { key = "char", label = L["ColCharacter"], width = cw.char,
          tip = "Character", tipDesc = "The guild member who has this cooldown. Right-click a row to whisper them.", justify = "LEFT" },
        { key = "cd",   label = L["ColCooldown"],  width = cw.col2,
          tip = "Cooldown", tipDesc = "The name of the profession cooldown spell.", justify = "LEFT" },
        { key = "time", label = L["ColTimeLeft"],  width = cw.time,
          tip = "Time Left", tipDesc = "How long until this cooldown is ready. Green = ready now.", justify = "RIGHT" },
    }

    self._headerCols = cols
    self._headerWidgets = {}

    for _, col in ipairs(cols) do
        local key = col.key
        local w = addon.GUI.MakeColumnHeader({
            parent       = parent,
            label        = col.label,
            -- Headers are centred over their columns with the sort arrow placed
            -- beside the text (shared ConfigureCenteredHeaderIcon below), matching
            -- the Profit Planner tab. Data cells keep their own justification.
            width        = col.width,
            justifyH     = "CENTER",
            hoverGlow    = true,
            tooltipTitle = col.tip,
            tooltipDesc  = col.tipDesc,
            onClick      = function()
                self._sortCol, self._sortAsc = addon.GUI.Sort.Next(self._sortCol, self._sortAsc, key)
                self:RedrawTable(container)
            end,
        })
        addon.GUI.Sort.ConfigureCenteredHeaderIcon(w, self._sortCol == key, self._sortAsc, col.width)
        
        -- Clean up sort icon when widget is released back to AceGUI pool
        local prevOnRelease = w.events and w.events.OnRelease
        w:SetCallback("OnRelease", function(widget)
            if widget._sortIcon then
                widget._sortIcon:Hide()
                widget._sortIcon:SetParent(nil)
                widget._sortIcon:ClearAllPoints()
                widget._sortIcon = nil
            end
            if prevOnRelease then prevOnRelease(widget) end
        end)
        
        self._headerWidgets[key] = w
    end
end

function CooldownsTab:RedrawTable(container)
    container:ReleaseChildren()
    self:Draw(container)
end

function CooldownsTab:FillRows(scroll)
    local rows = BuildRows(self._readyOnly, self._viewMode)

    -- Two-level dropdown filter:
    --   profession=All        → no filter
    --   profession=X, cd=All  → only rows belonging to profession X
    --   profession=X, cd=Y    → only rows matching the specific cooldown Y
    -- ProfessionMatchesRow is the union of all of X's cooldown predicates,
    -- so adding a new entry to COOLDOWN_BY_PROFESSION automatically extends
    -- both the profession-level match and the cooldown dropdown.
    local profId = self._filterProfId or 0
    local cdId   = self._filterCd   or "all"
    if profId ~= 0 then
        local kept = {}
        for _, row in ipairs(rows) do
            if ProfessionMatchesRow(profId, row) then
                kept[#kept + 1] = row
            end
        end
        rows = kept
    end

    if profId ~= 0 and cdId ~= "all" then
        local kept = {}
        local cdEntry
        for _, cd in ipairs(COOLDOWN_BY_PROFESSION[profId] or {}) do
            if cd.id == cdId then cdEntry = cd; break end
        end
        if cdEntry then
            for _, row in ipairs(rows) do
                if cdEntry.match(row) then
                    kept[#kept + 1] = row
                end
            end
        end
        rows = kept
    end

    -- Scope filter (applied after the prof/cd filter so the two compose
    -- naturally): "mine" keeps only rows whose charKey belongs to the
    -- local player's account. addon:IsMyCharacter consults the account-
    -- wide accountChars table so every own alt is recognised, not just
    -- the currently-logged-in character.
    if (self._viewMode or "guild") == "mine" then
        local kept = {}
        for _, row in ipairs(rows) do
            if addon:IsMyCharacter(row.charKey) then
                kept[#kept + 1] = row
            end
        end
        rows = kept
    end

    SortRows(rows, self._sortCol, self._sortAsc)
    local now = GetServerTime()

    if #rows == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["NoCooldownData"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    for rowIndex, row in ipairs(rows) do
        self:DrawRow(scroll, row, now, rowIndex)
    end
end

-- Profession-spec bonus output indicator support.
-- On TBC/Wrath, a small icon to the left of the crafter name signals that
-- this crafter's profession spec gives bonus output on this row's cooldown
-- (Mooncloth/Shadoweave/Spellfire tailoring → guaranteed 2x; Transmutation
-- Master alchemy → proc chance on every transmute). The 4.0.1 patch removed
-- the proc system, so the gate is isTBC/isWrath only — Vanilla never had the
-- system, Cata/MoP no longer do.
local SPEC_SLOT_RESERVED = addon.isTBC or addon.isWrath
local SPEC_ICON_W = SPEC_SLOT_RESERVED and 14 or 0

local function getSpecBonus(row, gdb)
    if not SPEC_SLOT_RESERVED then return nil end
    if not gdb or not gdb.specializations then return nil end
    local charSpecs = gdb.specializations[row.charKey]
    if not charSpecs then return nil end
    local data = addon:GetCooldownData()
    local specBonuses = data and data.specBonuses
    if not specBonuses then return nil end
    for _, specSpellId in pairs(charSpecs) do
        local bonus = specBonuses[specSpellId]
        if bonus then
            if row.isTransmuteGroup and bonus.affectsAllTransmutes then
                return specSpellId, bonus.bonusType
            elseif row.spellId and bonus.spells and bonus.spells[row.spellId] then
                return specSpellId, bonus.bonusType
            end
        end
    end
    return nil
end

function CooldownsTab:DrawRow(parent, row, now, rowIndex)
    -- Responsive column widths shared by charLbl / col2 / timeLbl below.
    -- Computed once in Draw() per redraw; falls back to preferred values
    -- if Draw hasn't run yet (defensive — shouldn't happen in practice).
    local cw = self._colWidths or { char = 190, col2 = 456, time = 80 }

    local remaining = row.expiresAt - now
    local timeStr   = SecondsToString(remaining)
    local timeColor
    if remaining <= 0 then
        timeColor = "|cff00ff00"   -- green: ready
    elseif remaining < 28800 then
        timeColor = "|cffffff00"   -- yellow: < 8h
    elseif remaining < 86400 then
        timeColor = "|cffff8800"   -- orange: < 24h
    else
        timeColor = "|cffff2200"   -- red: >= 24h
    end

    local rowGroup = AceGUI:Create("SimpleGroup")
    rowGroup:SetLayout("Flow")
    rowGroup:SetFullWidth(true)
    if rowGroup.SetAutoAdjustHeight then rowGroup:SetAutoAdjustHeight(false) end
    rowGroup:SetHeight(ROW_HEIGHT)
    parent:AddChild(rowGroup)
    local rf = rowGroup.frame
    addon.GUI.ApplyRowStripe(rf, rowIndex or 1)
    local rawChildren = {}
    local function track(frame)
        rawChildren[#rawChildren + 1] = frame
        return frame
    end

    -- Shared whisper helper (right-click on char label OR anywhere on the row)
    local function openWhisper(target)
        if ChatEdit_GetActiveWindow then
            local box = ChatEdit_GetActiveWindow()
            if box then
                box:SetText("/w " .. target .. " ")
                box:SetFocus()
                box:SetCursorPosition(#box:GetText())
                return
            end
        end
        ChatFrame_OpenChat("/w " .. target .. " ", DEFAULT_CHAT_FRAME)
    end
    local function doWhisper(anchorFrame)
        local shortName = row.shortName
        local fullKey   = row.charKey
        if Menu and Menu.CreateContextMenu then
            Menu.CreateContextMenu(anchorFrame, function(_, root)
                root:CreateTitle(shortName)
                root:CreateButton(shortName, function() openWhisper(fullKey) end)
            end)
        else
            openWhisper(fullKey)
        end
    end
    rf:EnableMouse(true)
    frameScripts(rowGroup, {
        OnMouseDown = function(f, button)
            if button == "RightButton" then doWhisper(f) end
        end,
    })
    local prevOnRelease = rowGroup.events and rowGroup.events.OnRelease
    rowGroup:SetCallback("OnRelease", function(widget)
        addon.GUI.DetachPool(rawChildren)
        if prevOnRelease then prevOnRelease(widget) end
    end)

    local function NewText(name, parentFrame, width, justify)
        local fs = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetHeight(ROW_HEIGHT)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetJustifyV("MIDDLE")
        fs:SetWordWrap(false)
        return fs
    end

    local x = 0

    -- ── Column 1: Character (190px) — online=white, offline=grey ─────────────
    -- On TBC/Wrath, the first SPEC_ICON_W pixels are reserved for the spec-
    -- bonus indicator (always present so column alignment stays consistent
    -- across rows; icon texture is only set when a spec bonus actually applies).
    local gdb        = addon:GetGuildDb()
    if SPEC_SLOT_RESERVED then
        local specSpellId, specBonusType = getSpecBonus(row, gdb)
        local specHit = track(CreateFrame("Frame", nil, rf))
        specHit:SetSize(SPEC_ICON_W, ROW_HEIGHT)
        specHit:SetPoint("LEFT", rf, "LEFT", x, 0)
        local specIcon = specHit:CreateTexture(nil, "ARTWORK")
        specIcon:SetSize(12, 12)
        specIcon:SetPoint("CENTER", specHit, "CENTER", 0, 0)
        if specSpellId then
            local tex = GetSpellTexture(specSpellId)
            if tex then
                specIcon:SetTexture(tex)
                specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                specHit:EnableMouse(true)
                specHit:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(specHit)
                    local specName = GetSpellInfo(specSpellId) or ""
                    GameTooltip:SetText(specName, 1, 1, 1)
                    local bonusLine = (specBonusType == "guaranteed")
                        and L["SpecBonusGuaranteedDouble"]
                        or  L["SpecBonusProcChance"]
                    GameTooltip:AddLine(bonusLine, 0.7, 0.85, 1.0, true)
                    GameTooltip:Show()
                end)
                specHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
        x = x + SPEC_ICON_W
    end

    local GuildCache = addon.Scanner and addon.Scanner.GuildCache
    local online = GuildCache and GuildCache:IsPlayerOnline(row.charKey) or false
    local displayName = row.shortName
    local isYou = addon:IsMyCharacter(row.charKey)

    if isYou then
        -- "You" alone is ambiguous when several alts are listed. Disambiguate
        -- alts as "You (AltName)" so the user can tell them apart at a glance.
        if row.charKey == addon:GetCharacterKey() then
            displayName = L["You"]
        else
            displayName = L["You"] .. " (" .. row.shortName .. ")"
        end
    elseif not online and gdb and gdb.altGroups and gdb.altGroups[row.charKey] then
        -- Crafter offline — check if one of their alts is online.
        for _, altCk in ipairs(gdb.altGroups[row.charKey]) do
            if altCk ~= row.charKey and GuildCache and GuildCache:IsPlayerOnline(altCk) then
                local altShort = altCk:match("^(.-)%-") or altCk
                displayName = altShort .. " (" .. row.shortName .. ")"
                online = true
                break
            end
        end
    end

    local colorYou     = "|c" .. (addon.ColorYou    or addon.BrandColor or "ffDA8CFF")
    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
    local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
    local nameColor = isYou and colorYou or (online and colorOnline or colorOffline)
    local charHit = track(CreateFrame("Button", nil, rf))
    charHit:SetSize(cw.char - SPEC_ICON_W, ROW_HEIGHT)
    charHit:SetPoint("LEFT", rf, "LEFT", x, 0)
    charHit:RegisterForClicks("AnyUp")
    local charLbl = NewText(nil, charHit, cw.char - SPEC_ICON_W, "LEFT")
    charLbl:SetPoint("LEFT", charHit, "LEFT", 0, 0)
    charLbl:SetText(nameColor .. displayName .. "|r")
    charHit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then doWhisper(charHit) end
    end)
    charHit:SetScript("OnEnter", function()
        addon.Tooltip.Owner(charHit)
        GameTooltip:SetText(row.shortName, 1, 1, 1)
        GameTooltip:AddLine(L["TooltipWhisperRightClick"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    charHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    x = x + cw.char

    -- ── Column 2: fixed 306px container — ALL cooldown content lives inside here ──
    -- This SimpleGroup acts as a hard column boundary: charLbl ends at 190px,
    -- col2 spans 190–496px, timeLbl starts at 496px regardless of inner content.

    -- Pre-check bank stock now so we can compute exact inner widths before
    -- creating any widgets (avoids dynamic resize after layout).
    local itemId   = row.reagentItemId
    local hasBank  = false
    if itemId and addon:IsAddOnLoaded("TOGBankClassic") then
        local TOG = _G["TOGBankClassic_Guild"]
        if TOG and TOG.Info and TOG.Info.alts then
            for _, alt in pairs(TOG.Info.alts) do
                for _, entry in ipairs(alt.items or {}) do
                    if entry.ID == itemId and (entry.Count or 0) > 0 then
                        hasBank = true; break
                    end
                end
                if hasBank then break end
            end
        end
    end

    -- Pre-check whether the AH scanner has cached listings for this row's
    -- reagent — same gating model as hasBank above. Flag drives whether
    -- the [AH] widget gets a width slot in the Flow layout below.
    local hasAH = false
    if itemId and addon.AH then
        local listings = addon.AH.GetListingsFor(itemId)
        hasAH = listings and (listings.count or 0) > 0
    end

    -- Width budget inside col2. ComputeCol2InnerWidths splits the fixed
    -- col2 width across the icon, cdName, reagent, [AH], [Bank], and mail
    -- widgets. Buttons get fixed slots when shown; cdName + reagent share
    -- the remainder 50/50 with per-side minimums. col2 itself is COL_W.col2
    -- (fixed), passed in via self._colWidths (read into `cw` at the top of
    -- this function).
    local iconColW, cdNameW, reagentW, ahW, bankW, mailW =
        ComputeCol2InnerWidths(cw.col2, itemId ~= nil, hasAH, hasBank)

    local col2 = track(CreateFrame("Frame", nil, rf))
    col2:SetSize(cw.col2, ROW_HEIGHT)
    col2:SetPoint("LEFT", rf, "LEFT", x, 0)
    local x2 = 0

    local iconCell = track(CreateFrame("Frame", nil, col2))
    iconCell:SetSize(iconColW, ROW_HEIGHT)
    iconCell:SetPoint("LEFT", col2, "LEFT", x2, 0)
    local iconW = iconCell:CreateTexture(nil, "ARTWORK")
    iconW:SetSize(12, 12)
    iconW:SetPoint("CENTER", iconCell, "CENTER", 0, 0)

    -- Resolve icon texture
    local iconTexture
    if row.isTransmuteGroup then
        iconTexture = "Interface\\Icons\\Trade_Alchemy"
    elseif row.isGroup then
        iconTexture = row.spellId and GetSpellTexture(row.spellId)
    elseif row.iconItemId then
        iconTexture = select(10, GetItemInfo(row.iconItemId))
        if not iconTexture then
            local iconItem = Item:CreateFromItemID(row.iconItemId)
            iconItem:ContinueOnItemLoad(function()
                local t = select(10, GetItemInfo(row.iconItemId))
                if t then
                    iconW:SetTexture(t)
                    iconW:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end)
            iconTexture = row.spellId and GetSpellTexture(row.spellId)
        end
    else
        iconTexture = row.spellId and GetSpellTexture(row.spellId)
    end
    if iconTexture then
        iconW:SetTexture(iconTexture)
        iconW:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        iconW:SetTexture(nil)
    end
    x2 = x2 + iconColW

    -- Cooldown name (text only — no image, so no stacking threshold applies)
    local cdText = row.isGroup and ("[+] " .. row.cdName) or row.cdName
    local cdHit = track(CreateFrame("Button", nil, col2))
    cdHit:SetSize(cdNameW, ROW_HEIGHT)
    cdHit:SetPoint("LEFT", col2, "LEFT", x2, 0)
    cdHit:RegisterForClicks("AnyUp")
    local cdNameLbl = NewText(nil, cdHit, cdNameW, "LEFT")
    cdNameLbl:SetPoint("LEFT", cdHit, "LEFT", 0, 0)
    cdNameLbl:SetText(cdText)
    if row.isGroup then
        cdHit:SetScript("OnEnter", function()
            addon.Tooltip.Owner(cdHit)
            if row.isTransmuteGroup then
                GameTooltip:AddLine(L["TooltipClickTransmutes"], 1, 1, 1)
            else
                GameTooltip:AddLine(string.format(L["TooltipClickDetailsFormat"], row.cdName or L["TooltipClickDetailsFallback"]), 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        cdHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cdHit:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then self:ShowGroupPopup(row, now, cdHit) end
        end)
    else
        cdHit:SetScript("OnEnter", function()
            if row.spellId then
                addon.Tooltip.Owner(cdHit)
                if GetSpellInfo(row.spellId) then
                    GameTooltip:SetHyperlink("spell:" .. row.spellId)
                else
                    GameTooltip:SetHyperlink("item:" .. row.spellId)
                end
                GameTooltip:Show()
            end
        end)
        cdHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    x2 = x2 + cdNameW

    -- Reagent + [Bank] + mail — all inside col2, only when a reagent exists
    if itemId then
        -- Reagent name
        local reagentHit = track(CreateFrame("Button", nil, col2))
        reagentHit:SetSize(reagentW, ROW_HEIGHT)
        reagentHit:SetPoint("LEFT", col2, "LEFT", x2, 0)
        reagentHit:RegisterForClicks("AnyUp")
        local reagentLbl = NewText(nil, reagentHit, reagentW, "LEFT")
        reagentLbl:SetPoint("LEFT", reagentHit, "LEFT", 0, 0)
        local reagentName = GetItemInfo(itemId)
        if reagentName then
            reagentLbl:SetText("|cffaaaaaa" .. reagentName .. "|r")
        else
            reagentLbl:SetText("")
            local rItem = Item:CreateFromItemID(itemId)
            rItem:ContinueOnItemLoad(function()
                local name = rItem:GetItemName()
                if name then reagentLbl:SetText("|cffaaaaaa" .. name .. "|r") end
            end)
        end
        reagentHit:SetScript("OnEnter", function()
            addon.Tooltip.Owner(reagentHit)
            GameTooltip:SetHyperlink("item:" .. itemId)
            GameTooltip:Show()
        end)
        reagentHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        reagentHit:SetScript("OnClick", function(_, button)
            if button == "LeftButton" and IsShiftKeyDown() then
                local link = select(2, GetItemInfo(itemId))
                if link then HandleModifiedItemClick(link) end
            end
        end)
        x2 = x2 + reagentW

        -- [AH] button — sits to the LEFT of [Bank] in the Flow order.
        -- Visible only when the AH scanner has cached listings for this
        -- reagent (gates on AH.GetListingsFor.count > 0). Click jumps the
        -- AH browse search to the reagent's name. Order matches the user's
        -- explicit preference for the Cooldowns tab (Professions tab uses
        -- the opposite [Bank] [AH] order on its reagent rows).
        if hasAH then
            local ahBtn = track(CreateFrame("Button", nil, col2))
            ahBtn:SetSize(ahW, ROW_HEIGHT)
            ahBtn:SetPoint("LEFT", col2, "LEFT", x2, 0)
            local ahLbl = NewText(nil, ahBtn, ahW, "LEFT")
            ahLbl:SetPoint("LEFT", ahBtn, "LEFT", 0, 0)
            ahLbl:SetText("|cFF88CCFF[AH]|r")
            ahBtn:SetScript("OnClick", function()
                local name = GetItemInfo(itemId)
                if name then addon.AH.SearchFor(name) end
            end)
            ahBtn:SetScript("OnEnter", function()
                addon.Tooltip.Owner(ahBtn)
                GameTooltip:SetText(L["TooltipAHTitle"], 1, 1, 1)
                GameTooltip:AddLine(L["TooltipAHDescReagent"], nil, nil, nil, true)
                GameTooltip:Show()
            end)
            ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            x2 = x2 + ahW
        end

        -- [Bank] button
        if hasBank then
            local bankBtn = track(CreateFrame("Button", nil, col2))
            bankBtn:SetSize(bankW, ROW_HEIGHT)
            bankBtn:SetPoint("LEFT", col2, "LEFT", x2, 0)
            local bankLbl = NewText(nil, bankBtn, bankW, "LEFT")
            bankLbl:SetPoint("LEFT", bankBtn, "LEFT", 0, 0)
            bankLbl:SetText("|cFF88FF88[Bank]|r")
            bankBtn:SetScript("OnClick", function()
                local name = GetItemInfo(itemId)
                local link = select(2, GetItemInfo(itemId))
                addon.Bank.ShowRequestDialog(itemId, name, link)
            end)
            bankBtn:SetScript("OnEnter", function()
                addon.Tooltip.Owner(bankBtn)
                GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1)
                GameTooltip:AddLine(L["TooltipBankDescGeneric"], nil, nil, nil, true)
                GameTooltip:Show()
            end)
            bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            x2 = x2 + bankW
        end

        -- Mail icon — use embedded texture tag (no SetImage) so this widget has
        -- the same line height as all other text widgets and doesn't inflate the row.
        local mailBtn = track(CreateFrame("Button", nil, col2))
        mailBtn:SetSize(mailW, ROW_HEIGHT)
        mailBtn:SetPoint("LEFT", col2, "LEFT", x2, 0)
        local mailIcon = mailBtn:CreateTexture(nil, "ARTWORK")
        mailIcon:SetSize(12, 12)
        mailIcon:SetPoint("CENTER", mailBtn, "CENTER", 0, 0)
        mailIcon:SetTexture("Interface\\Icons\\INV_Letter_15")
        mailBtn:SetScript("OnClick", function()
            local cdName    = row.isTransmuteGroup and L["Transmute"] or row.cdName
            local outputName = row.outputName or cdName
            CdMail_PrepareSupplyMail(row.charKey, cdName, outputName, itemId, row.reagentQty or 1)
        end)
        mailBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(mailBtn)
            GameTooltip:SetText(L["MailBtnTooltip"] or "Send Supply Mail", 1, 1, 1)
            GameTooltip:AddLine(L["MailBtnTooltipDesc"] or "Open a mailbox, then click to attach reagents.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- ── Column 3: Time Remaining — always at the right, never displaced ───
    local timeHit = track(CreateFrame("Frame", nil, rf))
    timeHit:SetSize(cw.time, ROW_HEIGHT)
    timeHit:SetPoint("LEFT", rf, "LEFT", cw.char + cw.col2, 0)
    local timeLbl = NewText(nil, timeHit, cw.time, "RIGHT")
    timeLbl:SetPoint("LEFT", timeHit, "LEFT", 0, 0)
    timeLbl:SetText(timeColor .. timeStr .. "|r")

    -- ── Optional "!" cooldown-ready alarm toggle (own characters only) ─────
    -- Mirrors the Browser tab's per-recipe alert "!" button. Cyan when armed,
    -- grey when off; clicking flips state via addon.CooldownAlerts, which
    -- also fires an immediate ping if the cooldown is already ready (gives
    -- the user a confirmation that the alarm is wired up). Skipped on
    -- non-own-character rows — guildmate cooldowns are informational and
    -- alerting on them isn't part of this feature.
    if isYou and addon.CooldownAlerts then
        local CA = addon.CooldownAlerts
        local alertBtn = track(CreateFrame("Button", nil, rf))
        alertBtn:SetSize(18, ROW_HEIGHT)
        alertBtn:SetPoint("LEFT", rf, "LEFT", cw.char + cw.col2 + cw.time, 0)
        local alertLbl = NewText(nil, alertBtn, 18, "CENTER")
        alertLbl:SetPoint("CENTER", alertBtn, "CENTER", 0, 0)
        local function paint(btn, armed)
            alertLbl:SetText(armed and "|cff00ffff!|r" or "|cff666666!|r")
        end
        paint(alertBtn, CA:IsArmed(row))
        alertBtn:SetScript("OnClick", function()
            local newState = CA:Toggle(row)
            paint(alertBtn, newState)
        end)
        alertBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(alertBtn)
            local enabled = CA:IsArmed(row)
            GameTooltip:SetText(enabled and L["CooldownAlertDisable"] or L["CooldownAlertEnable"], 1, 1, 1)
            GameTooltip:Show()
        end)
        alertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

--- Show a popup listing all individual spells inside a cooldown group.
-- For transmute groups: shows each spell with its per-spell reagent and a mail button.
-- For other groups: shows spell name and time remaining.
-- Clicking the same row again or clicking outside closes the popup.
function CooldownsTab:ShowGroupPopup(row, now, sourceWidget)
    -- Toggle off if the same row was clicked again.
    if self._groupPopup then
        local wasRow = self._groupPopup._sourceRow == row
        self._groupPopup:Hide()
        self._groupPopup = nil
        if wasRow then return end
    end

    -- Two row shapes are supported:
    --   transmute groups: row.transmuteEntries — list of {spellId, name,
    --     reagentId, reagentQty} (spellId may be nil on Anniversary clients
    --     where the alchemist's spellId backfill couldn't resolve all spells).
    --   non-transmute groups: row.group.spells — set of spellIds.  These
    --     always have spellIds (legacy hard-coded groups), no reagents.
    local entries
    if row.transmuteEntries and #row.transmuteEntries > 0 then
        entries = row.transmuteEntries
    elseif row.group and row.group.spells then
        entries = {}
        for sid in pairs(row.group.spells) do
            entries[#entries + 1] = {
                spellId = sid,
                name    = GetSpellInfo(sid) or ("Spell " .. sid),
            }
        end
        table.sort(entries, function(a, b) return a.name < b.name end)
    end
    if not entries or #entries == 0 then return end

    local hasReagents = false
    for _, e in ipairs(entries) do
        if e.reagentId then hasReagents = true; break end
    end
    -- In "mine" view a row's charKey can live in any guild bucket (including
    -- the synthetic NoGuildBucketKey for guildless alts), not just the current
    -- gdb. addon:FindBucketForChar walks every bucket and returns the one
    -- holding cooldowns for this charKey.
    local charKey = row.charKey
    local bucket  = addon:FindBucketForChar(charKey, "cooldowns")
    local charCds = bucket and bucket.cooldowns[charKey] or {}

    local rowH   = 14
    local pad    = 6
    -- popupW = 500 to make room for the [AH] button slot added between
    -- the reagent label and [Bank] (the slot is 40px). Without the bump,
    -- the spell-name column would compress from ~190px to ~150px and
    -- longer transmute names like "Transmute: Earth to Water" would
    -- truncate.
    local popupW = 500
    local totalH = pad + #entries * rowH + pad

    local popup = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    popup:Hide()  -- start hidden so popup:Show() at the end fires OnShow
    popup:SetWidth(popupW)
    popup:SetHeight(totalH)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetBackdrop({
        bgFile   = [[Interface\Tooltips\UI-Tooltip-Background]],
        edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    popup:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    popup:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    -- Position adjacent to the clicked widget using the shared screen-half
    -- helper (mirrors Tooltip.Owner for arbitrary frames).  Falls back to
    -- centered on UIParent if the caller didn't pass a source widget.
    if sourceWidget then
        addon.Tooltip.AnchorFrame(popup, sourceWidget)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    popup._sourceRow = row

    -- Click-outside-to-close overlay
    local closeOnClick = CreateFrame("Frame", nil, UIParent)
    closeOnClick:SetAllPoints(UIParent)
    closeOnClick:SetFrameStrata("DIALOG")
    closeOnClick:EnableMouse(true)
    closeOnClick:SetScript("OnMouseDown", function()
        popup:Hide(); closeOnClick:Hide()
        if CooldownsTab._groupPopup == popup then CooldownsTab._groupPopup = nil end
    end)
    popup:EnableMouse(true)
    popup:SetScript("OnMouseDown", function() end)  -- block click-through
    popup._closeOnClick = closeOnClick  -- store reference for cleanup

    -- The popup itself sits at TOOLTIP strata, which is the same strata as
    -- GameTooltip — so GameTooltip's default frame level loses to the popup's
    -- inner buttons/labels and tooltips render visually behind them.  Bumping
    -- the GameTooltip frame level after every Show() forces it on top.  Used
    -- by every OnEnter handler in the popup that opens a tooltip.
    local function showAbovePopup()
        GameTooltip:Show()
        GameTooltip:SetFrameLevel(popup:GetFrameLevel() + 20)
    end

    -- Per-row [Bank] / [AH] button visibility refreshers. TOGBankClassic
    -- constructs its `_G.TOGBankClassic_Guild.Info.alts` lazily — the
    -- first call that queries it during its uninitialized state returns
    -- 0 and we'd skip creating the button. Solution: always create the
    -- button, hide it when stock is 0, and re-evaluate on popup OnShow
    -- plus a short deferred tick so a late-loading TOGBank populates
    -- correctly without requiring the user to close and reopen the popup.
    -- AH refreshers piggyback on the same list so all per-row visibility
    -- updates run together — the gating data (Bank.GetStock and
    -- AH.GetListingsFor) are both queried fresh per refresh.
    local rowRefreshers = {}
    popup:SetScript("OnHide", function() closeOnClick:Hide() end)
    popup:SetScript("OnShow", function()
        for _, fn in ipairs(rowRefreshers) do fn() end
        C_Timer.After(0.1, function()
            if popup:IsShown() then
                for _, fn in ipairs(rowRefreshers) do fn() end
            end
        end)
    end)

    local mailW    = hasReagents and 20 or 0
    local bankW    = hasReagents and 48 or 0
    -- AH button column. 40px matches the per-row [AH] width used in the
    -- main cooldown row (C2_AH_BTN). Sits to the LEFT of [Bank], to the
    -- RIGHT of the reagent label — same ordering as the main row so users
    -- get consistent button positioning whether they're looking at the
    -- table or the transmute popup.
    local ahW      = hasReagents and 40 or 0
    local reagentW = hasReagents and 110 or 0
    local timeW    = 70
    local nameW    = popupW - pad * 2 - reagentW - ahW - bankW - mailW - timeW - 8

    for i, e in ipairs(entries) do
        local spellId    = e.spellId
        local recipeId   = e.recipeId
        local entryName  = e.name or (spellId and ("Spell " .. spellId)) or "?"
        local reagentId  = e.reagentId
        local reagentQty = e.reagentQty or 1
        local showName   = e.showName ~= false
        local showTime   = e.showTime ~= false
        -- v0.7.2: transmutes share a single 20h cooldown — once the
        -- alchemist casts any one of them, every other transmute is on
        -- CD too, but the game only records the cooldown under the cast
        -- spell's ID. A per-row charCds[spellId] lookup therefore shows
        -- the cast spell as "5h 17m" and every other transmute as
        -- "Ready" inside the same popup, which is wrong. For transmute
        -- groups, use the group's shared expiresAt (already computed as
        -- the max future expiry across every transmute spell the char
        -- knows). Non-transmute group popups (Mooncloth tier, etc.)
        -- still resolve per-spell — those are genuinely independent.
        local expiresAt
        if row.isTransmuteGroup then
            expiresAt = row.expiresAt and row.expiresAt > now and row.expiresAt or nil
        else
            expiresAt = spellId and charCds[spellId]
        end
        local remaining  = expiresAt and (expiresAt - now) or nil
        -- No spellId → cooldown can't be tracked, treat as Ready.
        -- No cooldown record OR expired (remaining <= 0) → spell is castable.
        local isReady   = (not expiresAt) or remaining <= 0
        local timeStr   = isReady and "Ready" or SecondsToString(remaining)
        local timeColor = isReady and "|cff00ff00" or "|cffaaaaaa"

        local yOff = -(pad + (i - 1) * rowH)

        local rowFrame = CreateFrame("Frame", nil, popup)
        rowFrame:SetHeight(rowH)
        rowFrame:SetPoint("TOPLEFT",  popup, "TOPLEFT",  pad, yOff)
        rowFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -pad, yOff)

        -- Spell name (blank on the 2nd+ row of a multi-reagent transmute so
        -- the visual grouping stays clean).
        local nameLbl = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", 0, 0)
        nameLbl:SetWidth(nameW)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetText(showName and entryName or "")

        -- Mouseover tooltip for the name zone: spell tooltip when we have a
        -- spellId, falls back to the recipe's output-item tooltip via recipeId
        -- (which IS the output itemId for non-spell recipes).  Either way the
        -- user gets some hover info on every row.
        local nameZone = CreateFrame("Frame", nil, rowFrame)
        nameZone:SetPoint("TOPLEFT",     rowFrame, "TOPLEFT",    0, 0)
        nameZone:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMLEFT", nameW, 0)
        nameZone:EnableMouse(true)
        nameZone:SetScript("OnEnter", function()
            if showName then nameLbl:SetTextColor(1, 1, 0, 1) end
            if spellId then
                addon.Tooltip.Owner(nameZone)
                GameTooltip:SetHyperlink("spell:" .. spellId)
                showAbovePopup()
            elseif recipeId then
                addon.Tooltip.Owner(nameZone)
                GameTooltip:SetHyperlink("item:" .. recipeId)
                showAbovePopup()
            end
        end)
        nameZone:SetScript("OnLeave", function()
            nameLbl:SetTextColor(1, 1, 1, 1)
            GameTooltip:Hide()
        end)

        -- Time remaining (only on the leading row of a multi-reagent transmute
        -- so the cooldown isn't repeated for every reagent of the same spell).
        local timeLbl = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeLbl:SetPoint("LEFT", nameW + 4, 0)
        timeLbl:SetWidth(timeW)
        timeLbl:SetJustifyH("LEFT")
        timeLbl:SetText(showTime and (timeColor .. timeStr .. "|r") or "")

        -- Reagent and mail button (transmute groups only)
        if reagentId then
            local reagentLbl = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            -- Sit to the LEFT of [AH] [Bank] [mail] (the +6 is per-button
            -- gap padding × 3 stacked widgets). Order right-to-left:
            --   mailBtn   at -(mailW + 2)
            --   bankBtn   at -(bankW + mailW + 4)
            --   ahBtn     at -(ahW + bankW + mailW + 6)
            --   reagent   at -(reagentW + ahW + bankW + mailW + 8)
            reagentLbl:SetPoint("RIGHT", rowFrame, "RIGHT", -(ahW + bankW + mailW + 6), 0)
            reagentLbl:SetWidth(reagentW)
            reagentLbl:SetJustifyH("RIGHT")
            reagentLbl:SetTextColor(0.65, 0.65, 0.65, 1)
            local rName = GetItemInfo(reagentId)
            if rName then
                reagentLbl:SetText(rName)
            else
                reagentLbl:SetText("")
                local rItem = Item:CreateFromItemID(reagentId)
                rItem:ContinueOnItemLoad(function()
                    reagentLbl:SetText(rItem:GetItemName() or "")
                end)
            end

            local reagentZone = CreateFrame("Frame", nil, rowFrame)
            reagentZone:SetPoint("TOPLEFT",     rowFrame, "TOPRIGHT",    -(reagentW + ahW + bankW + mailW + 6), 0)
            reagentZone:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -(ahW + bankW + mailW + 6), 0)
            reagentZone:EnableMouse(true)
            reagentZone:SetScript("OnEnter", function()
                reagentLbl:SetTextColor(1, 1, 0, 1)
                addon.Tooltip.Owner(reagentZone)
                GameTooltip:SetHyperlink("item:" .. reagentId)
                showAbovePopup()
            end)
            reagentZone:SetScript("OnLeave", function()
                reagentLbl:SetTextColor(0.65, 0.65, 0.65, 1)
                GameTooltip:Hide()
            end)
            reagentZone:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" and IsShiftKeyDown() then
                    local link = select(2, GetItemInfo(reagentId))
                    if link then HandleModifiedItemClick(link) end
                end
            end)

            -- [AH] button — always created, visibility toggled per row by
            -- a refresher that queries addon.AH.GetListingsFor(reagentId)
            -- (gates same way [Bank] gates on Bank.GetStock). The refresher
            -- runs on popup OnShow + the deferred tick alongside the bank
            -- refreshers so a Scan AH that completes BEFORE the user opens
            -- the popup is reflected in row visibility immediately.
            if addon.AH then
                local ahBtn = CreateFrame("Button", nil, rowFrame)
                ahBtn:SetSize(ahW, rowH)
                ahBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -(bankW + mailW + 4), 0)
                ahBtn:SetNormalFontObject(GameFontNormalSmall)
                ahBtn:SetText("|cFF88CCFF[AH]|r")
                ahBtn:Hide()  -- starts hidden; refresher reveals when listings exist
                ahBtn:SetScript("OnClick", function()
                    local name = GetItemInfo(reagentId)
                    if name then addon.AH.SearchFor(name) end
                end)
                ahBtn:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(ahBtn)
                    GameTooltip:SetText(L["TooltipAHTitle"], 1, 1, 1)
                    GameTooltip:AddLine(L["TooltipAHDescReagent"], nil, nil, nil, true)
                    showAbovePopup()
                end)
                ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                rowRefreshers[#rowRefreshers + 1] = function()
                    local listings = addon.AH.GetListingsFor(reagentId)
                    if listings and (listings.count or 0) > 0 then
                        ahBtn:Show()
                    else
                        ahBtn:Hide()
                    end
                end
            end

            -- [Bank] button — always created, visibility toggled per row by
            -- a refresher that runs on popup OnShow + a deferred tick (handles
            -- TOGBankClassic's lazy Info.alts initialization that returns 0
            -- on the first GetStock query of a session).
            if addon.Bank then
                local bankBtn = CreateFrame("Button", nil, rowFrame)
                bankBtn:SetSize(bankW, rowH)
                bankBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -(mailW + 2), 0)
                bankBtn:SetNormalFontObject(GameFontNormalSmall)
                bankBtn:SetText("|cFF88FF88[Bank]|r")
                bankBtn:Hide()  -- starts hidden; refresher reveals when stock > 0
                bankBtn:SetScript("OnClick", function()
                    local name = GetItemInfo(reagentId)
                    local link = select(2, GetItemInfo(reagentId))
                    addon.Bank.ShowRequestDialog(reagentId, name, link)
                end)
                bankBtn:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(bankBtn)
                    GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1)
                    GameTooltip:AddLine(L["TooltipBankDescGeneric"], nil, nil, nil, true)
                    showAbovePopup()
                end)
                bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                rowRefreshers[#rowRefreshers + 1] = function()
                    if addon.Bank.GetStock(reagentId) > 0 then
                        bankBtn:Show()
                    else
                        bankBtn:Hide()
                    end
                end
            end

            -- Mail icon button
            local mailBtn = CreateFrame("Button", nil, rowFrame)
            mailBtn:SetSize(16, 16)
            mailBtn:SetPoint("RIGHT", rowFrame, "RIGHT", 0, 0)
            mailBtn:SetNormalTexture("Interface\\Icons\\INV_Letter_15")
            mailBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            mailBtn:SetScript("OnClick", function()
                local spellName = (spellId and GetSpellInfo(spellId)) or entryName
                CdMail_PrepareSupplyMail(charKey, spellName, reagentId, reagentQty)
            end)
            mailBtn:SetScript("OnEnter", function()
                addon.Tooltip.Owner(mailBtn)
                GameTooltip:SetText(L["MailBtnTooltip"] or "Send Supply Mail", 1, 1, 1)
                GameTooltip:AddLine(L["MailBtnTooltipDesc"] or "Open a mailbox, then click to mail reagents to this player.", nil, nil, nil, true)
                showAbovePopup()
            end)
            mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    popup:Show()
    -- Belt-and-suspenders: invoke refreshers directly even if OnShow already
    -- did so, in case something about the WoW frame lifecycle skips it.  The
    -- refreshers are idempotent (just toggle Show/Hide based on current stock).
    for _, fn in ipairs(rowRefreshers) do fn() end
    C_Timer.After(0.1, function()
        if popup:IsShown() then
            for _, fn in ipairs(rowRefreshers) do fn() end
        end
    end)
    self._groupPopup = popup
end

-- ---------------------------------------------------------------------------
-- AH callbacks
-- ---------------------------------------------------------------------------
-- (Removed: per-tab AH_OPEN_STATE_CHANGED / AH_SCAN_COMPLETE handlers.
-- The shared addon.GUI.MakeScanAHButton factory in GUI/SharedWidgets.lua
-- owns one global handler that refreshes the active tab's scan button +
-- runs the tab's onRefresh hook. The hook for this tab refills row
-- children so [AH] buttons appear/disappear with scan results.)

-- (Removed: WINDOW_RESIZED handler. Column widths are now fixed (COL_W),
-- so window resizes need no per-tab response — Flow no longer reflows
-- mid-drag, and the rows stay put exactly like the Missing/Browser tabs.)
