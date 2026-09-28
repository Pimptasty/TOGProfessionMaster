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
              -- TBC: Primal Mooncloth, Spellcloth, Shadowcloth
              26751, 31373, 36686,
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
          -- Balanced Trillium + Lightning Steel group
          match = groupKeyMatcher("bs_ingot") },
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
-- Column widths (scale-1.0), for the RowList that draws the rows
-- ---------------------------------------------------------------------------
-- The cooldown name is the list's one auto-width column and takes what the
-- fixed columns leave. [Bank] is 50 wide because its label carries TOGBank's
-- staleness dot in front of the text since v1.1.0.
local COL = {
    char    = 140,
    icon    = 18,
    reagent = 110,
    ah      = 36,
    bank    = 50,
    mail    = 20,
    time    = 80,
    alert   = 18,
}

-- Window size policy for this tab — read by MainWindow on tab switch
-- and on Open. `locked = true` means the resize grip is disabled and
-- the frame snaps to width/height. Cooldowns and Missing share the
-- SAME locked dimensions so switching between those two tabs produces
-- no visible jump (only switching to/from Browser changes the size).
CooldownsTab.WINDOW_SIZE = { width = 720, height = 500, locked = true }

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
    -- Guild view. Cooldowns carry no guild tag, so scope the flat account-wide
    -- map to the current guild by roster membership: own cross-guild alts AND
    -- other-guild members (whose cooldowns synced while we were logged into that
    -- guild) are filtered out, leaving only the current guild (+ sister guilds).
    -- Without this, every character's cooldowns in the account-wide DB rendered
    -- under whichever guild you were currently in.
    local gdb = addon:GetGuildDb()
    local all = gdb and gdb.cooldowns
    if not all then return {} end
    local scoped = {}
    local nInDb, nKept = 0, 0
    for charKey, charCds in pairs(all) do
        nInDb = nInDb + 1
        if addon:IsInCurrentGuildScope(charKey) then
            scoped[charKey] = charCds
            nKept = nKept + 1
        else
            addon:DebugPrint("CooldownsTab: guild scope FILTERED OUT cooldown owner:", charKey)
        end
    end
    addon:DebugPrint("CooldownsTab: guild view — cooldown owners in DB:", nInDb,
        "| passed guild scope:", nKept)
    return scoped
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
            -- Hide a cooldown whose profession this character has unlearned (e.g.
            -- an Alchemy transmute after they drop Alchemy). Authoritative against
            -- their profession snapshot; a no-op for characters we hold no snapshot
            -- for, or for non-profession cooldowns like Salt Shaker.
            if addon:IsCooldownProfessionDropped(charKey, spellId) then
                -- skip: profession dropped
            else
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
                            cdName = addon.Item.GetInfo(spellId) or "Salt Shaker"
                        else
                            cdName = data.cooldowns[spellId] or addon.Spell.GetInfo(spellId)
                                     or addon.Item.GetInfo(spellId) or tostring(spellId)
                        end
                        local iconItemId    = data.iconOverrides and data.iconOverrides[spellId]
                        local outputName    = (data.outputOverrides and data.outputOverrides[spellId]) or cdName
                        local multi         = data.multiReagents and data.multiReagents[spellId]
                        if multi then
                            -- Multi-reagent cooldown (e.g. Brilliant Glass = six
                            -- gems). Single-reagent rows can't show more than one
                            -- reagent, so emit a click-to-expand group row whose
                            -- popup lists every reagent with its own [AH]/[Bank]/
                            -- mail — the same shape transmute rows use. All
                            -- entries carry the SAME spellId (one spell, one
                            -- shared cooldown), so the popup resolves each row's
                            -- timer from that spell's cooldown record.
                            local entries = {}
                            for ri, r in ipairs(multi) do
                                entries[#entries + 1] = {
                                    spellId    = spellId,
                                    name       = cdName,
                                    reagentId  = r.id,
                                    reagentQty = r.qty,
                                    showName   = ri == 1,
                                    showTime   = ri == 1,
                                }
                            end
                            table.insert(rows, {
                                charKey          = charKey,
                                shortName        = shortName,
                                spellId          = spellId,
                                cdName           = cdName,
                                outputName       = outputName,
                                iconItemId       = iconItemId,
                                expiresAt        = expiresAt,
                                isGroup          = true,
                                transmuteEntries = entries,
                            })
                        else
                            local reagentItemId = data.reagents[spellId] and data.reagents[spellId].id
                            local reagentQty    = data.reagents[spellId] and data.reagents[spellId].qty or 1
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

--- Scan the carried bags for all stacks of itemId.
-- Returns total (number), stacks ({ {bag,slot,count}, ... })
local function CdMail_CountItemInBags(itemId)
    local total, stacks = 0, {}
    for bag = 0, addon:GetNumBagSlots() do
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
            table.insert(attachList, { bag = item.bag, slot = item.slot,
                                       count = item.count, originalIndex = item.originalIndex })
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
                        table.insert(testList, { bag = item.bag, slot = item.slot,
                                                 count = item.count, originalIndex = item.originalIndex })
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
    -- Split the remainder off a stack not already in the list. Such a stack is
    -- always STRICTLY larger than the remainder: the greedy pass takes any stack
    -- that fits the remaining need at the moment it is visited, and the need
    -- only shrinks after that, so a stack equal to the final remainder would
    -- already be in the list. Tests/cooldownrows_spec.lua pins that property
    -- over every small bag layout, because the split call refuses amount >=
    -- count and nothing downstream guards it again. This branch also covers
    -- the nothing-taken case (every stack bigger than the need), so the
    -- separate `accumulated == 0` branch that used to follow it was dead.
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
    return { canFulfill = false,
             reason = string.format("Need %d more.", qtyNeeded - totalInBags),
             stacksToAttach = {}, totalAttachable = totalInBags }
end

-- ---------------------------------------------------------------------------
-- Offline-test seam — everything above is frame-free logic (row building, the
-- sort, the supply-mail planner); the first CreateFrame in this file is ~500
-- lines below. `local` only because nothing outside the file calls them, which
-- also put them out of the spec suite's reach. Not used at runtime.
-- See Tests/cooldownrows_spec.lua.
-- ---------------------------------------------------------------------------
CooldownsTab._BuildRows                 = BuildRows
CooldownsTab._SortRows                  = SortRows
CooldownsTab._SecondsToString           = SecondsToString
CooldownsTab._CollectCooldownsByChar    = CollectCooldownsByChar
CooldownsTab._ProfessionMatchesRow      = ProfessionMatchesRow
CooldownsTab._CountItemInBags           = CdMail_CountItemInBags
CooldownsTab._CalculateFulfillmentPlan  = CdMail_CalculateFulfillmentPlan

local function CdMail_Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF88CCCCTOG Profession Master:|r " .. msg)
end
local function CdMail_Complain(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r " .. msg)
end

--- Whether ANY send slot already holds something. `HasSendMailItem` is the
--- client's own occupancy test (Classic Era MailFrame.lua:881/:1087); the old
--- `if GetSendMailItem(1)` read the NAME, which is the one return an item the
--- client has not cached yet leaves nil. Every slot, not slot 1: a player who
--- detaches slot 1 by hand leaves slots 2+ loaded (TOGBankClassic's
--- MULTIFILL-001 finding).
local function CdMail_MailHasItems()
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        if HasSendMailItem(i) then return true end
    end
    return false
end

--- The first `n` empty carried-bag slots, as { {bag, slot}, ... } -- fewer when the
--- bags have fewer. Enumerated UP FRONT because a split that has not been picked
--- up yet is invisible to the container API, so a per-split search would hand
--- every split the same slot (TOGBankClassic's MULTIFILL-002 finding).
local function CdMail_EmptyBagSlots(n)
    local out = {}
    for bag = 0, addon:GetNumBagSlots() do
        for slot = 1, (addon:GetContainerNumSlots(bag) or 0) do
            if #out >= n then return out end
            if not addon:GetContainerItemInfo(bag, slot) then
                out[#out + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return out
end

--- Plan ONE mail carrying EVERY reagent of a cooldown, decided before anything
--- in the bags is touched. `reagents` is { { id=, qty= }, ... }.
---
--- All-or-nothing on purpose: a supply mail that carries the Thorium Bars but
--- not the Arcane Crystal is not a supply mail, it is a puzzle for the
--- recipient -- so a reagent that cannot be covered blocks the whole send and
--- every shortfall is reported together, not just the first. The per-reagent
--- arithmetic is CdMail_CalculateFulfillmentPlan, unchanged; this only sums it
--- across reagents and checks the result fits in one mail's attachment slots.
---
--- Returns { ok, problems = {msg...}, stacks = {{bag,slot,count,itemId}...},
---           splits = {{bag,slot,count,amount,itemId,name}...}, lines = {{qty,name}...} }.
local function CdMail_PlanSupplyMail(reagents)
    local plan = { ok = true, problems = {}, stacks = {}, splits = {}, lines = {} }
    local slotsUsed = 0
    for _, r in ipairs(reagents or {}) do
        -- At least one: a zero would "fulfil" with nothing attached.
        local qty  = math.max(1, tonumber(r.qty) or 1)
        local name = addon.Item.GetInfo(r.id) or ("item:" .. tostring(r.id))
        local total, stacks = CdMail_CountItemInBags(r.id)
        if total == 0 then
            plan.problems[#plan.problems + 1] = string.format(L["MailMsgNoneInBags"], name)
        else
            local p = CdMail_CalculateFulfillmentPlan(stacks, qty, total)
            if not p.canFulfill then
                plan.problems[#plan.problems + 1] = name .. ": " .. (p.reason or L["MailMsgCannotFulfill"])
            else
                for _, s in ipairs(p.stacksToAttach) do
                    plan.stacks[#plan.stacks + 1] = { bag = s.bag, slot = s.slot, count = s.count, itemId = r.id }
                    slotsUsed = slotsUsed + 1
                end
                local s = p.splitStack
                if s then
                    -- amount < count always -- see the planner's split branch.
                    plan.splits[#plan.splits + 1] = { bag = s.bag, slot = s.slot, count = s.count,
                                                      amount = s.amount, itemId = r.id, name = name }
                    slotsUsed = slotsUsed + 1
                end
                plan.lines[#plan.lines + 1] = { qty = qty, name = name }
            end
        end
    end
    local maxSlots = ATTACHMENTS_MAX_SEND or 12
    if slotsUsed > maxSlots then
        plan.problems[#plan.problems + 1] = string.format(L["MailMsgTooManyStacks"], slotsUsed, maxSlots)
    end
    if #plan.lines == 0 and #plan.problems == 0 then
        plan.problems[#plan.problems + 1] = L["MailMsgCannotFulfill"]
    end
    plan.ok = #plan.problems == 0
    return plan
end

--- "1x Arcane Crystal, 1x Thorium Bar" -- the attached list, in reagent order.
local function CdMail_DescribeLines(lines)
    local parts = {}
    for _, l in ipairs(lines) do parts[#parts + 1] = string.format("%dx %s", l.qty, l.name) end
    return table.concat(parts, ", ")
end

--- The ATTACH half: every split stack (now sitting in the bag slot it was
--- placed into) and every whole stack goes into the send-mail slots, then the
--- recipient, subject and body are filled in. Runs straight from the click when
--- nothing needed splitting, or from a timer once the splits have landed --
--- so it re-checks the mailbox and the slots rather than trusting what the
--- click saw. A split that has not committed to its bag slot yet (the place is
--- deferred a frame, matching the manual-split timing) is waited for a few
--- ticks, then given up on with a message rather than attaching half a mail.
local function CdMail_AttachSupplyMail(plan, playerName, cooldownName, outputName, tries)
    for _, s in ipairs(plan.splits) do
        local info = addon:GetContainerItemInfo(s.dstBag, s.dstSlot)
        if not (info and (info.itemID or info.itemId) == s.itemId) then
            if (tries or 0) < 5 then
                C_Timer.After(0.2, function()
                    CdMail_AttachSupplyMail(plan, playerName, cooldownName, outputName, (tries or 0) + 1)
                end)
            else
                CdMail_Complain(L["MailMsgSplitNotLanded"])
            end
            return
        end
    end
    if not MailFrame or not MailFrame:IsShown() then
        CdMail_Complain(L["MailMsgOpenMailbox"])
        return
    end
    if CdMail_MailHasItems() then
        CdMail_Complain(L["MailMsgHasItems"])
        return
    end
    -- The Send Mail tab, so the attachments are in front of the player when
    -- the mailbox opened on the inbox -- the same step TOGBankClassic's fulfil
    -- path takes before it attaches.
    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end

    -- All or nothing here too: a stack the plan counted on that is no longer
    -- where it was (moved between the click and the attach) fails its pickup,
    -- and rather than mail the rest and describe the whole plan as sent,
    -- everything already attached is put back (the client's right-click
    -- detach, ClickSendMailItemButton(i, true)) and the click is reported as
    -- failed -- the next click re-plans against the bags as they are now.
    local attachSlot = 1
    local function attach(bag, slot)
        ClearCursor()
        C_Container.PickupContainerItem(bag, slot)
        ClickSendMailItemButton(attachSlot)
        if HasSendMailItem(attachSlot) then
            attachSlot = attachSlot + 1
            return true
        end
        ClearCursor()
        return false
    end
    local ok = true
    for _, s in ipairs(plan.splits) do
        if ok then ok = attach(s.dstBag, s.dstSlot) end
    end
    for _, s in ipairs(plan.stacks) do
        if ok then ok = attach(s.bag, s.slot) end
    end
    if not ok then
        for i = attachSlot - 1, 1, -1 do ClickSendMailItemButton(i, true) end
        CdMail_Complain(L["MailMsgCouldNotAttach"])
        return
    end

    local baseName = playerName:match("^([^%-]+)") or playerName
    if SendMailNameEditBox then SendMailNameEditBox:SetText(baseName) end
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText(string.format(L["MailSubjectFormat"], cooldownName))
    end
    local bodyBox = MailEditBox or SendMailBodyEditBox
    if bodyBox then
        bodyBox:SetText(string.format(L["MailBodyFormat"], baseName, outputName, outputName))
    end
    CdMail_Say(string.format(L["MailMsgAttachedListFormat"], CdMail_DescribeLines(plan.lines), baseName))
end

--- ONE click, ONE mail, EVERY reagent of the cooldown (v1.1.0). Before this,
--- each reagent row in the transmute popup had its own mail button, so an
--- Arcanite transmute (Thorium Bar + Arcane Crystal) cost the sender two
--- mails; the user's words: "split ALL the components for the cooldown and
--- attach ALL the components to the mail ... ONE mail/order fulfill button".
---
--- Splits run from THIS click rather than behind a confirmation popup, all of
--- them, 0.25s apart with each split's placement 0.1s after it -- so a
--- placement has cleared the cursor before the next split loads it (the
--- client refuses a split onto a loaded cursor). The attach step is scheduled
--- after the last placement and verifies every split landed before it
--- touches a send slot. Whole stacks with nothing to split attach immediately.
--- The sequence is TOGBankClassic's FulfillStep, which is in players' hands.
local function CdMail_PrepareSupplyMail(playerName, cooldownName, outputName, reagents)
    if not MailFrame or not MailFrame:IsShown() then
        CdMail_Complain(L["MailMsgOpenMailbox"])
        return
    end
    if CdMail_MailHasItems() then
        CdMail_Complain(L["MailMsgHasItems"])
        return
    end
    local plan = CdMail_PlanSupplyMail(reagents)
    if not plan.ok then
        for _, msg in ipairs(plan.problems) do CdMail_Complain(msg) end
        return
    end
    if #plan.splits == 0 then
        CdMail_AttachSupplyMail(plan, playerName, cooldownName, outputName, 0)
        return
    end
    local empties = CdMail_EmptyBagSlots(#plan.splits)
    if #empties < #plan.splits then
        CdMail_Complain(string.format(L["MailMsgNeedEmptySlots"], #plan.splits))
        return
    end
    local pieces = {}
    for i, s in ipairs(plan.splits) do
        local dst = empties[i]
        s.dstBag, s.dstSlot = dst.bag, dst.slot
        pieces[#pieces + 1] = string.format("%dx %s", s.amount, s.name)
        local at = (i - 1) * 0.25
        local function doSplit()
            ClearCursor()
            C_Container.SplitContainerItem(s.bag, s.slot, s.amount)
        end
        if i == 1 then doSplit() else C_Timer.After(at, doSplit) end
        C_Timer.After(at + 0.1, function()
            C_Container.PickupContainerItem(dst.bag, dst.slot)
        end)
    end
    C_Timer.After(#plan.splits * 0.25, function()
        CdMail_AttachSupplyMail(plan, playerName, cooldownName, outputName, 0)
    end)
    CdMail_Say(string.format(L["MailMsgSplittingFormat"], table.concat(pieces, ", ")))
end

-- Offline-test seam for the mail path (same reasoning as the block above; these
-- are defined after it). See Tests/cooldownmail_spec.lua.
CooldownsTab._EmptyBagSlots     = CdMail_EmptyBagSlots
CooldownsTab._PlanSupplyMail    = CdMail_PlanSupplyMail
CooldownsTab._PrepareSupplyMail = CdMail_PrepareSupplyMail

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

    -- ---- Toolbar -----------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    local readyBtn = AceGUI:Create("Button")
    readyBtn:SetText(self._readyOnly and L["ShowAll"] or L["ReadyOnly"])
    readyBtn:SetWidth(110)
    readyBtn:SetCallback("OnClick", function(widget)
        self._readyOnly = not self._readyOnly
        widget:SetText(self._readyOnly and L["ShowAll"] or L["ReadyOnly"])
        self:RedrawTable(container)
    end)
    readyBtn:SetCallback("OnEnter", function(widget)
        addon.Tooltip.Owner(widget.frame)
        -- rawget avoids AceLocale's missing-key metatable (which fires a "Missing
        -- entry" error on ACCESS, before our `or` fallback can run). Returns the
        -- localized string when registered, nil otherwise → literal fallback.
        GameTooltip:AddLine(rawget(L, "ReadyOnlyTooltip")
            or "Toggle: show only cooldowns that are Ready, or show every cooldown.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    readyBtn:SetCallback("OnLeave", function() GameTooltip:Hide() end)
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
    -- Shared with the Browser tab via `UI.ScopeList` rather than re-listed
    -- here. This tab passes no extras: guild/mine is the whole of its scope
    -- filter, and the Browser's third mode is Browser-only.
    viewDD:SetList(addon.UI.ScopeList())
    viewDD:SetValue(self._viewMode or addon.UI.SCOPE_DEFAULT)
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
                local name = addon.Item.GetInfo(id)
                if type(name) == "string" and name ~= "" then
                    seen[id] = true
                    items[#items + 1] = { itemId = id, itemName = name }
                end
            end
            for _, row in ipairs(rows) do
                if row.transmuteEntries then
                    -- Group rows carry per-entry reagents and row.reagentItemId
                    -- == nil: transmute groups (each transmute has its own
                    -- reagent, sometimes multiple — Arcanite needs Thorium Bar +
                    -- Arcane Crystal) AND multi-reagent cooldowns (Brilliant
                    -- Glass = six gems). Iterate the entries so the scan covers
                    -- every reagent, not just the single-reagent standalone
                    -- cooldowns (Salt Shaker, Mooncloth, etc.).
                    for _, e in ipairs(row.transmuteEntries) do
                        addItem(e.reagentId)
                    end
                else
                    addItem(row.reagentItemId)
                end
            end
            return items
        end,
        -- [AH] buttons follow the scan results; the list re-reads each
        -- button column's `show` on a repaint.
        onRefresh     = function()
            if CooldownsTab._rowList then CooldownsTab._rowList:Refresh() end
        end,
    })

    -- ---- Rows --------------------------------------------------------------
    -- A LibAceGUIWidgets RowList, built once per session on a host the tab
    -- owns (addon.GUI.ParkList), parked in a group that takes the rest of the
    -- tab. Released on a tab switch or redraw: the popup is detached, and the
    -- host goes back to UIParent.
    local section = AceGUI:Create("SimpleGroup")
    section:SetLayout("Fill")
    section:SetFullWidth(true)
    section:SetFullHeight(true)
    container:AddChild(section)
    self._section   = section
    self._container = container
    if addon.W then
        addon.W:OnWidgetRelease(section, "togpm:cooldownsList", function()
            GameTooltip:Hide()
            self:DetachPopup()
            if self._section == section then self._section = nil end
            self._rows = nil
        end)
    end

    self:FillRows(section)
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

function CooldownsTab:RedrawTable(container)
    container:ReleaseChildren()
    self:Draw(container)
end

function CooldownsTab:FillRows(section)
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
    self._rows = rows

    if #rows == 0 then
        if self._rowListHost then self._rowListHost:Hide() end
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["NoCooldownData"])
        lbl:SetFullWidth(true)
        section:AddChild(lbl)
        return
    end
    if not addon.W then return end

    local rl = addon.GUI.ParkList(self, "_rowList", section, function(host)
        return self:BuildRowList(host)
    end)
    -- Keep the player's place across the rebuilds GUILD_DATA_UPDATED causes
    -- every few seconds in an active guild. Read before SetData, whose
    -- scroll-to-top is reported too.
    local saved = addon.GUI.ListScroll.Get("cooldowns")
    rl:SetSort(self._sortCol, not self._sortAsc)
    rl:SetData(rows)
    rl:SetScrollOffset(saved)
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

-- ---------------------------------------------------------------------------
-- The rows: a LibAceGUIWidgets RowList (MINOR 36). It draws only the visible
-- rows and reuses its row frames and cells for the session, which is what
-- the per-row kits did by hand up to v1.1.2. Each column below is what one
-- part of the old hand-built row did; the hover and click on each cell are
-- the list's `onCellEnter` / `onCellClick` / button `onClick`, resolved
-- against the entry the pooled row is showing at that moment.
-- ---------------------------------------------------------------------------

local function timeColor(remaining)
    if remaining <= 0 then return "|cff00ff00" end      -- green: ready
    if remaining < 28800 then return "|cffffff00" end   -- yellow: < 8h
    if remaining < 86400 then return "|cffff8800" end   -- orange: < 24h
    return "|cffff2200"                                 -- red: >= 24h
end

--- The character cell's text: "You" / "You (Alt)" for the account's own
--- characters, an offline crafter's online alt credited by name, coloured
--- you / online / offline.
local function charCellText(row)
    local gdb = addon:GetGuildDb()
    local GuildRoster = addon.Scanner and addon.Scanner.GuildRoster
    local online = GuildRoster and GuildRoster:IsOnline(row.charKey) or false
    local displayName = row.shortName
    local isYou = addon:IsMyCharacter(row.charKey)
    if isYou then
        -- "You" alone is ambiguous when several alts are listed.
        if row.charKey == addon:GetCharacterKey() then
            displayName = L["You"]
        else
            displayName = L["You"] .. " (" .. row.shortName .. ")"
        end
    elseif not online and gdb and gdb.altGroups and gdb.altGroups[row.charKey] then
        -- Crafter offline — check if one of their alts is online.
        for _, altCk in ipairs(gdb.altGroups[row.charKey]) do
            if altCk ~= row.charKey and GuildRoster and GuildRoster:IsOnline(altCk) then
                local altShort = altCk:match("^(.-)%-") or altCk
                displayName = altShort .. " (" .. row.shortName .. ")"
                online = true
                break
            end
        end
    end
    local color = isYou and (addon.ColorYou or addon.BrandColor or "ffDA8CFF")
        or (online and (addon.ColorOnline or "ffffffff") or (addon.ColorOffline or "ffaaaaaa"))
    return "|c" .. color .. displayName .. "|r"
end

--- The cooldown's icon. An item-icon override (cloth crafts whose spell icon
--- is a generic net texture) is checked BEFORE the group check, so a
--- multi-reagent cloth cooldown still shows the produced bolt.
local function rowIcon(row)
    if row.isTransmuteGroup then return "Interface\\Icons\\Trade_Alchemy" end
    if row.iconItemId then
        local t = select(10, addon.Item.GetInfo(row.iconItemId))
        if t then return t end
    end
    return row.spellId and addon.Spell.GetTexture(row.spellId) or nil
end

-- A cooldown's reagent names and icons can be cold in the client's item cache.
-- Each item asks the client once, and the list repaints when it answers.
local itemAsked = {}
function CooldownsTab:WhenItemLoads(itemId)
    if not itemId or itemAsked[itemId] or not Item then return end
    itemAsked[itemId] = true
    Item:CreateFromItemID(itemId):ContinueOnItemLoad(function()
        if self._rowList then self._rowList:Refresh() end
    end)
end

-- Right-click anywhere on a row: whisper the character. Shared with the
-- Browser tab through addon.UI.OpenWhisper.
local function whisperMenu(row, anchorFrame)
    local openWhisper = addon.UI.OpenWhisper
    if Menu and Menu.CreateContextMenu then
        Menu.CreateContextMenu(anchorFrame, function(_, root)
            root:CreateTitle(row.shortName)
            root:CreateButton(row.shortName, function() openWhisper(row.charKey) end)
        end)
    else
        openWhisper(row.charKey)
    end
end

-- The cooldown name's tooltip: a click hint on a group row, else the spell
-- with the same recipe block the Professions tab shows. The `spell:` branch
-- is why that block is explicit: the global tooltip hook is OnTooltipSetItem,
-- so a spell tooltip inherits nothing.
function CooldownsTab:ShowCooldownTooltip(row, owner)
    if row.isGroup then
        addon.Tooltip.Owner(owner)
        if row.isTransmuteGroup then
            GameTooltip:AddLine(L["TooltipClickTransmutes"], 1, 1, 1, true)
        else
            GameTooltip:AddLine(string.format(L["TooltipClickDetailsFormat"],
                row.cdName or L["TooltipClickDetailsFallback"]), 1, 1, 1, true)
        end
        GameTooltip:Show()
    elseif row.spellId then
        addon.Tooltip.Owner(owner)
        if addon.Spell.GetInfo(row.spellId) then
            GameTooltip:SetHyperlink("spell:" .. row.spellId)
        else
            GameTooltip:SetHyperlink("item:" .. row.spellId)
        end
        addon.ItemLink.AppendRecipeBlocks(GameTooltip, nil, row.spellId)
        GameTooltip:Show()
    end
end

local function hideTip() GameTooltip:Hide() end

function CooldownsTab:BuildRowList(host)
    local CA = addon.CooldownAlerts
    local columns = {}
    -- On TBC/Wrath, the spec-bonus indicator in front of the crafter's name:
    -- this crafter's profession spec gives bonus output on this cooldown.
    if SPEC_SLOT_RESERVED then
        columns[#columns + 1] = { key = "_spec", width = SPEC_ICON_W, iconSize = 12,
            iconTexCoord = true, sortable = false,
            icon = function(row)
                local specSpellId = getSpecBonus(row, addon:GetGuildDb())
                return specSpellId and addon.Spell.GetTexture(specSpellId) or nil
            end,
            onCellEnter = function(row, _, _, cell)
                local specSpellId, bonusType = getSpecBonus(row, addon:GetGuildDb())
                if not specSpellId then return end
                addon.Tooltip.Owner(cell)
                GameTooltip:SetText(addon.Spell.GetInfo(specSpellId) or "", 1, 1, 1, 1, true)
                GameTooltip:AddLine(bonusType == "guaranteed" and L["SpecBonusGuaranteedDouble"]
                    or L["SpecBonusProcChance"], 0.7, 0.85, 1.0, true)
                GameTooltip:Show()
            end,
            onCellLeave = hideTip }
    end
    columns[#columns + 1] = { key = "char", header = L["ColCharacter"], width = COL.char,
        headerTip = "The guild member who has this cooldown. Right-click a row to whisper them.",
        format = function(_, row) return charCellText(row) end,
        onCellEnter = function(row, _, _, cell)
            addon.Tooltip.Owner(cell)
            GameTooltip:SetText(row.shortName, 1, 1, 1, 1, true)
            GameTooltip:AddLine(L["TooltipWhisperRightClick"], 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end,
        onCellLeave = hideTip }
    columns[#columns + 1] = { key = "_icon", width = COL.icon, iconSize = 12, iconTexCoord = true,
        sortable = false,
        icon = function(row)
            if row.iconItemId and not select(10, addon.Item.GetInfo(row.iconItemId)) then
                self:WhenItemLoads(row.iconItemId)
            end
            return rowIcon(row)
        end }
    -- The cooldown name. A group row reads "[+] Transmute" and a left click
    -- opens its popup under the cell; a button cell so the click has a frame.
    columns[#columns + 1] = { key = "cd", header = L["ColCooldown"], button = true,
        headerTip = "The name of the profession cooldown spell.",
        text = function(row) return row.isGroup and ("[+] " .. row.cdName) or row.cdName end,
        onClick = function(row, _, _, button, cell)
            if row.isGroup and button == "LeftButton" then self:ShowGroupPopup(row, cell) end
        end,
        onCellEnter = function(row, _, _, cell) self:ShowCooldownTooltip(row, cell) end,
        onCellLeave = hideTip }
    -- The reagent, white when this character holds enough to fulfil the mail
    -- and grey otherwise -- the same rule the group popup uses. Repainted on
    -- REAGENT_WATCH_UPDATED (every BAG_UPDATE), so buying it recolours it.
    columns[#columns + 1] = { key = "reagent", width = COL.reagent, sortable = false,
        format = function(_, row)
            local itemId = row.reagentItemId
            if not itemId then return "" end
            local name = addon.Item.GetInfo(itemId)
            if not name then
                self:WhenItemLoads(itemId)
                return ""
            end
            local enough = CdMail_CountItemInBags(itemId) >= (row.reagentQty or 1)
            return (enough and "|cffffffff" or "|cffa6a6a6") .. name .. "|r"
        end,
        onCellEnter = function(row, _, _, cell)
            if not row.reagentItemId then return end
            addon.Tooltip.Owner(cell)
            addon.ItemLink.SetItem(GameTooltip, nil, row.reagentItemId)
            GameTooltip:Show()
        end,
        onCellLeave = function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end,
        onCellClick = function(row, _, _, button)
            if button ~= "LeftButton" or not row.reagentItemId then return end
            addon.ItemLink.Click((select(2, addon.Item.GetInfo(row.reagentItemId))))
            return true
        end }
    -- [AH] left of [Bank] -- the order the operator chose for this tab.
    columns[#columns + 1] = { key = "ahBtn", width = COL.ah, button = true, sortable = false,
        show = function(row)
            local listings = row.reagentItemId and addon.AH and addon.AH.GetListingsFor(row.reagentItemId)
            return listings and (listings.count or 0) > 0 or false
        end,
        text = function() return "|cFF88CCFF[AH]|r" end,
        tip  = function() return L["TooltipAHTitle"], L["TooltipAHDescReagent"] end,
        onClick = function(row)
            local name = addon.Item.GetInfo(row.reagentItemId)
            if name then addon.AH.SearchFor(name) end
        end }
    columns[#columns + 1] = { key = "bankBtn", width = COL.bank, button = true, sortable = false,
        show = function(row)
            return row.reagentItemId and addon:IsAddOnLoaded("TOGBankClassic")
                and addon.Bank.GetStock(row.reagentItemId) > 0 or false
        end,
        text = function(row) return addon.Bank.ButtonText(row.reagentItemId) end,
        tip  = function(row)
            local body = L["TooltipBankDescGeneric"]
            local status = addon.Bank.StatusText(row.reagentItemId)
            if status then body = body .. "\n\n" .. status end
            return L["TooltipBankTitle"], body
        end,
        onClick = function(row)
            local id = row.reagentItemId
            addon.Bank.ShowRequestDialog(id, addon.Item.GetInfo(id), select(2, addon.Item.GetInfo(id)))
        end }
    columns[#columns + 1] = { key = "mailBtn", width = COL.mail, button = true, sortable = false,
        show = function(row) return row.reagentItemId ~= nil end,
        text = function() return "|TInterface\\Icons\\INV_Letter_15:12:12|t" end,
        tip  = function()
            return L["MailBtnTooltip"] or "Send Supply Mail",
                L["MailBtnTooltipDesc"] or "Open a mailbox, then click to attach reagents."
        end,
        onClick = function(row)
            local cdName = row.isTransmuteGroup and L["Transmute"] or row.cdName
            CdMail_PrepareSupplyMail(row.charKey, cdName, row.outputName or cdName,
                { { id = row.reagentItemId, qty = row.reagentQty or 1 } })
        end }
    columns[#columns + 1] = { key = "time", header = L["ColTimeLeft"], width = COL.time, align = "RIGHT",
        headerTip = "How long until this cooldown is ready. Green = ready now.",
        format = function(_, row)
            local remaining = row.expiresAt - GetServerTime()
            return timeColor(remaining) .. SecondsToString(remaining) .. "|r"
        end }
    -- The "!" cooldown-ready alarm, on the account's own characters only:
    -- cyan when armed, grey when off. Arming an already-ready cooldown pings
    -- at once, so the player sees it is wired up.
    columns[#columns + 1] = { key = "alertBtn", width = COL.alert, button = true, sortable = false,
        justify = "CENTER",
        show = function(row) return CA ~= nil and addon:IsMyCharacter(row.charKey) end,
        text = function(row) return CA and CA:IsArmed(row) and "|cff00ffff!|r" or "|cff666666!|r" end,
        tip  = function(row)
            return CA and CA:IsArmed(row) and L["CooldownAlertDisable"] or L["CooldownAlertEnable"]
        end,
        onClick = function(row, _, rl)
            CA:Toggle(row)
            rl:Refresh()
        end }

    local rl = addon.W.RowList:New(host, {
        rowHeight      = ROW_HEIGHT,
        hoverHighlight = true,
        -- SortRows orders the rows (ready ones by name, ties by character);
        -- the header sets the key and the arrow.
        externalSort   = true,
        onSortChanged  = function(key, desc) self:OnSortChanged(key, desc) end,
        onScroll       = function(_, offset) addon.GUI.ListScroll.Set("cooldowns", offset) end,
        columns        = columns,
        onRowClick     = function(row, _, _, button, rowFrame)
            if button == "RightButton" then whisperMenu(row, rowFrame) end
        end,
    })
    -- Bag changes recolour the reagent column. Registered once: the list is
    -- built once per session.
    addon:RegisterCallback("REAGENT_WATCH_UPDATED", function()
        if self._rowList and self._rowListHost and self._rowListHost:IsShown() then
            self._rowList:Refresh()
        end
    end)
    return rl
end

-- A header click, reported by the list after it set its own key and arrow.
function CooldownsTab:OnSortChanged(key, desc)
    self._sortCol = key or "time"
    self._sortAsc = not desc
    if self._rows then
        SortRows(self._rows, self._sortCol, self._sortAsc)
        if self._rowList then self._rowList:SetData(self._rows, true) end
    end
end

-- One popup row's frames and regions, built once per row slot and reused on
-- every later open (see ShowGroupPopup). Only the parts that never change per
-- open are set here.
local function NewPopupRow(popup)
    local s = {}
    s.frame = CreateFrame("Frame", nil, popup)
    s.nameLbl = s.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.nameLbl:SetJustifyH("LEFT")
    -- The font's own colour, restored on reuse: hovering a name leaves it white.
    s.nameColor = { s.nameLbl:GetTextColor() }
    s.nameZone = CreateFrame("Frame", nil, s.frame)
    s.nameZone:EnableMouse(true)
    s.reagentLbl = s.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.reagentLbl:SetJustifyH("RIGHT")
    s.reagentLbl:SetWordWrap(false)
    s.reagentZone = CreateFrame("Frame", nil, s.frame)
    s.reagentZone:EnableMouse(true)
    s.ahBtn = CreateFrame("Button", nil, s.frame)
    s.ahBtn:SetNormalFontObject(GameFontNormalSmall)
    s.ahBtn:SetText("|cFF88CCFF[AH]|r")
    s.bankBtn = CreateFrame("Button", nil, s.frame)
    s.bankBtn:SetNormalFontObject(GameFontNormalSmall)
    s.mailBtn = CreateFrame("Button", nil, s.frame)
    s.mailBtn:SetSize(16, 16)
    s.mailBtn:SetNormalTexture("Interface\\Icons\\INV_Letter_15")
    s.mailBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    s.optional = { s.reagentLbl, s.reagentZone, s.ahBtn, s.bankBtn, s.mailBtn }
    return s
end

--- Show a popup listing all individual spells inside a cooldown group.
-- For transmute groups: shows each spell with its per-spell reagent and a mail button.
-- For other groups: shows spell name and time remaining.
-- Clicking the same row again or clicking outside closes the popup.
function CooldownsTab:ShowGroupPopup(row, sourceWidget)
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
                name    = addon.Spell.GetInfo(sid) or ("Spell " .. sid),
            }
        end
        table.sort(entries, function(a, b) return a.name < b.name end)
    end
    if not entries or #entries == 0 then return end

    local hasReagents = false
    for _, e in ipairs(entries) do
        if e.reagentId then hasReagents = true; break end
    end
    local charKey = row.charKey

    -- One mail per COOLDOWN, not per reagent row (v1.1.0). A multi-reagent
    -- transmute is emitted as one entry per reagent (so each keeps its own
    -- [AH] / [Bank] request), all sharing the cooldown's spellId. The mail
    -- button goes on the FIRST row of each such group and carries the whole
    -- group's reagent list, so Arcanite's Thorium Bar + Arcane Crystal leave
    -- in one mail instead of two. Sibling rows keep the mail column's space
    -- for alignment and draw nothing in it. Keyed on spellId, falling back to
    -- the display name for an entry the spellId backfill could not resolve.
    local groupReagents, mailEntry = {}, {}
    for _, e in ipairs(entries) do
        if e.reagentId then
            local key = e.spellId or e.name or e
            local list = groupReagents[key]
            if not list then
                list = {}
                groupReagents[key] = list
                mailEntry[e] = list
            end
            list[#list + 1] = { id = e.reagentId, qty = e.reagentQty or 1 }
        end
    end

    local rowH   = 14
    local pad    = 6
    -- popupW = 500: name + reagent + [AH]/[Bank]/mail + time all tile inside this
    -- width. The name/reagent split is chosen per popup type below — transmute
    -- popups have long names + short reagents; multi-reagent cooldown popups
    -- (cloths, Brilliant Glass) are the reverse — so we don't need extra width,
    -- just a different division of the same space.
    local popupW = 500
    local totalH = pad + #entries * rowH + pad

    -- The popup shell, its click-outside overlay and its rows are built once and
    -- reused: WoW never frees a frame, and up to v1.1.2 every open built a new
    -- shell, overlay and ~6 frames per row. `_gen` is bumped per open so an
    -- item-load callback from an earlier open does nothing.
    local popup = self._popupShell
    if not popup then
        popup = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
        popup:SetFrameStrata("TOOLTIP")
        popup:SetBackdrop({
            bgFile   = [[Interface\Tooltips\UI-Tooltip-Background]],
            edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
            edgeSize = 12,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        popup:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
        popup:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        popup:EnableMouse(true)
        popup:SetScript("OnMouseDown", function() end)  -- block click-through
        popup._rows, popup._gen = {}, 0

        -- Click-outside-to-close overlay
        local closeOnClick = CreateFrame("Frame", nil, UIParent)
        closeOnClick:SetAllPoints(UIParent)
        closeOnClick:SetFrameStrata("DIALOG")
        closeOnClick:EnableMouse(true)
        closeOnClick:SetScript("OnMouseDown", function()
            popup:Hide(); closeOnClick:Hide()
            if CooldownsTab._groupPopup == popup then CooldownsTab._groupPopup = nil end
        end)
        popup._closeOnClick = closeOnClick  -- store reference for cleanup
        self._popupShell = popup
    end
    popup:Hide()  -- hidden so popup:Show() at the end fires OnShow
    popup._gen = popup._gen + 1
    local popupGen = popup._gen
    local closeOnClick = popup._closeOnClick
    -- DetachPopup may have detached them from a released window.
    popup:SetParent(UIParent)
    closeOnClick:SetParent(UIParent)
    closeOnClick:ClearAllPoints()
    closeOnClick:SetAllPoints(UIParent)
    closeOnClick:Show()
    popup:SetWidth(popupW)
    popup:SetHeight(totalH)
    popup:ClearAllPoints()
    -- Position under the clicked row, or over it when there is no room below,
    -- kept on screen horizontally: LibAceGUIWidgets' AnchorPopup (MINOR 36,
    -- TOGPM contract c8d6892f), which measures both frames in UIParent units so
    -- a scaled window places right. Centred on UIParent when the caller passed
    -- no source.
    local sourceFrame = sourceWidget and (sourceWidget.frame or sourceWidget)
    if sourceFrame and addon.W then
        addon.W:AnchorPopup(popup, sourceFrame)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    popup._sourceRow = row

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
    local bankW    = hasReagents and 58 or 0   -- +10 for the staleness dot
    -- AH button column. 40px matches the per-row [AH] width used in the
    -- main cooldown row (C2_AH_BTN). Sits to the LEFT of [Bank], to the
    -- RIGHT of the reagent label — same ordering as the main row.
    local ahW      = hasReagents and 40 or 0
    -- Reagent column: 180px so long names ("Bolt of Imbued Netherweave") fit on
    -- ONE line. There's no time/status column in the popup (removed as redundant
    -- — the main cooldown row already shows readiness), so both a wide reagent
    -- column AND a wide name column fit inside the unchanged 500px width.
    local reagentW = hasReagents and 180 or 0
    local nameW    = popupW - pad * 2 - reagentW - ahW - bankW - mailW - 8

    for i = #entries + 1, #popup._rows do popup._rows[i].frame:Hide() end
    for i, e in ipairs(entries) do
        local spellId    = e.spellId
        local recipeId   = e.recipeId
        local entryName  = e.name or (spellId and ("Spell " .. spellId)) or "?"
        local reagentId  = e.reagentId
        local reagentQty = e.reagentQty or 1
        local showName   = e.showName ~= false
        -- No time/status column in the popup — it was redundant with the main
        -- cooldown row's own readiness, so the per-entry cooldown lookup is gone.

        local yOff = -(pad + (i - 1) * rowH)

        local slot = popup._rows[i]
        if not slot then
            slot = NewPopupRow(popup)
            popup._rows[i] = slot
        end
        for _, f in ipairs(slot.optional) do f:Hide() end
        local rowFrame = slot.frame
        rowFrame:ClearAllPoints()
        rowFrame:SetHeight(rowH)
        rowFrame:SetPoint("TOPLEFT",  popup, "TOPLEFT",  pad, yOff)
        rowFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -pad, yOff)
        rowFrame:Show()

        -- Spell name (blank on the 2nd+ row of a multi-reagent transmute so
        -- the visual grouping stays clean).
        local nameLbl = slot.nameLbl
        nameLbl:ClearAllPoints()
        nameLbl:SetPoint("LEFT", 0, 0)
        nameLbl:SetWidth(nameW)
        nameLbl:SetTextColor(unpack(slot.nameColor))
        nameLbl:SetText(showName and entryName or "")

        -- Mouseover tooltip for the name zone: spell tooltip when we have a
        -- spellId, falls back to the recipe's output-item tooltip via recipeId
        -- (which IS the output itemId for non-spell recipes).  Either way the
        -- user gets some hover info on every row.
        local nameZone = slot.nameZone
        nameZone:ClearAllPoints()
        nameZone:SetPoint("TOPLEFT",     rowFrame, "TOPLEFT",    0, 0)
        nameZone:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMLEFT", nameW, 0)
        nameZone:SetScript("OnEnter", function()
            if showName then nameLbl:SetTextColor(1, 1, 0, 1) end
            if spellId then
                addon.Tooltip.Owner(nameZone)
                GameTooltip:SetHyperlink("spell:" .. spellId)
                -- Explicit: a `spell:` tooltip carries no item, so the global
                -- OnTooltipSetItem hook never fires on it.
                addon.ItemLink.AppendRecipeBlocks(GameTooltip, nil, spellId)
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

        -- Reagent and mail button (transmute groups only)
        if reagentId then
            local reagentLbl = slot.reagentLbl
            reagentLbl:Show()
            reagentLbl:ClearAllPoints()
            -- Sit to the LEFT of [AH] [Bank] [mail] (the +6 is per-button
            -- gap padding × 3 stacked widgets). Order right-to-left:
            --   mailBtn   at -(mailW + 2)
            --   bankBtn   at -(bankW + mailW + 4)
            --   ahBtn     at -(ahW + bankW + mailW + 6)
            --   reagent   at -(reagentW + ahW + bankW + mailW + 8)
            reagentLbl:SetPoint("RIGHT", rowFrame, "RIGHT", -(ahW + bankW + mailW + 6), 0)
            reagentLbl:SetWidth(reagentW)
            -- One line only (SetWordWrap(false) in NewPopupRow): the row is a
            -- fixed rowH tall, so a wrapped name would overlap the row below.
            -- Resting colour reflects bag stock: WHITE when the viewer holds
            -- enough of this reagent to fulfill the mail (>= reagentQty), GREY
            -- otherwise — a glance shows which reagents you can actually send.
            -- Yellow on hover, then restored to the correct rest colour on leave.
            -- A refresher recomputes it (cheap bag scan) on popup show + the
            -- deferred tick, so acquiring/sending items updates it live.
            local reagentHovered = false
            local function reagentRestColor()
                local inBags = CdMail_CountItemInBags(reagentId)
                if inBags >= reagentQty then return 1, 1, 1, 1 end
                return 0.65, 0.65, 0.65, 1
            end
            local function applyReagentRestColor()
                if not reagentHovered then reagentLbl:SetTextColor(reagentRestColor()) end
            end
            applyReagentRestColor()
            rowRefreshers[#rowRefreshers + 1] = applyReagentRestColor
            local rName = addon.Item.GetInfo(reagentId)
            if rName then
                reagentLbl:SetText(rName)
            else
                reagentLbl:SetText("")
                local rItem = Item:CreateFromItemID(reagentId)
                rItem:ContinueOnItemLoad(function()
                    if popup._gen ~= popupGen then return end  -- a later open owns the row
                    reagentLbl:SetText(rItem:GetItemName() or "")
                end)
            end

            local reagentZone = slot.reagentZone
            reagentZone:ClearAllPoints()
            reagentZone:SetPoint("TOPLEFT",     rowFrame, "TOPRIGHT",    -(reagentW + ahW + bankW + mailW + 6), 0)
            reagentZone:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -(ahW + bankW + mailW + 6), 0)
            reagentZone:Show()
            reagentZone:SetScript("OnEnter", function()
                reagentHovered = true
                reagentLbl:SetTextColor(1, 1, 0, 1)
                addon.Tooltip.Owner(reagentZone)
                addon.ItemLink.SetItem(GameTooltip, nil, reagentId)
                showAbovePopup()
            end)
            reagentZone:SetScript("OnLeave", function()
                reagentHovered = false
                reagentLbl:SetTextColor(reagentRestColor())
                GameTooltip:Hide()
            end)
            reagentZone:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then
                    addon.ItemLink.Click((select(2, addon.Item.GetInfo(reagentId))))
                end
            end)

            -- [AH] button — always created, visibility toggled per row by
            -- a refresher that queries addon.AH.GetListingsFor(reagentId)
            -- (gates same way [Bank] gates on Bank.GetStock). The refresher
            -- runs on popup OnShow + the deferred tick alongside the bank
            -- refreshers so a Scan AH that completes BEFORE the user opens
            -- the popup is reflected in row visibility immediately.
            if addon.AH then
                local ahBtn = slot.ahBtn  -- hidden above; the refresher reveals it
                ahBtn:ClearAllPoints()
                ahBtn:SetSize(ahW, rowH)
                ahBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -(bankW + mailW + 4), 0)
                ahBtn:SetScript("OnClick", function()
                    local name = addon.Item.GetInfo(reagentId)
                    if name then addon.AH.SearchFor(name) end
                end)
                ahBtn:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(ahBtn)
                    GameTooltip:SetText(L["TooltipAHTitle"], 1, 1, 1, 1, true)
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
                local bankBtn = slot.bankBtn  -- hidden above; the refresher reveals it
                bankBtn._bankItemId = nil
                bankBtn:ClearAllPoints()
                bankBtn:SetSize(bankW, rowH)
                bankBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -(mailW + 2), 0)
                bankBtn:SetText(addon.Bank.ButtonText(nil))
                bankBtn:SetScript("OnClick", function()
                    local name = addon.Item.GetInfo(reagentId)
                    local link = select(2, addon.Item.GetInfo(reagentId))
                    addon.Bank.ShowRequestDialog(reagentId, name, link)
                end)
                bankBtn:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(bankBtn)
                    GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1, 1, true)
                    GameTooltip:AddLine(L["TooltipBankDescGeneric"], nil, nil, nil, true)
                    addon.Bank.AddStatusLines(bankBtn)
                    showAbovePopup()
                end)
                bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                rowRefreshers[#rowRefreshers + 1] = function()
                    if addon.Bank.GetStock(reagentId) > 0 then
                        addon.Bank.Decorate(bankBtn, reagentId)
                        bankBtn:Show()
                    else
                        bankBtn:Hide()
                    end
                end
            end

            -- Mail icon button -- on the first row of the cooldown only, and it
            -- mails EVERY reagent in the group (see groupReagents above).
            local mailReagents = mailEntry[e]
            if mailReagents then
                local mailBtn = slot.mailBtn
                mailBtn:ClearAllPoints()
                mailBtn:SetPoint("RIGHT", rowFrame, "RIGHT", 0, 0)
                mailBtn:Show()
                mailBtn:SetScript("OnClick", function()
                    local spellName = (spellId and addon.Spell.GetInfo(spellId)) or entryName
                    -- Resolve the crafted-output name for the mail body. The
                    -- PRODUCT first -- "Arcanite Bar", from the recipe's crafted
                    -- item, so the body does not read "make Transmute: Arcanite ...
                    -- send me the Transmute: Arcanite" (which is what the user's
                    -- first in-game mail said, 2026-09-14). Then the fallbacks for
                    -- an entry with no recipe: the row's display name, the spell
                    -- name, the output item (recipeId IS the output itemId for
                    -- non-spell recipes), else a blank rather than a raw id.
                    local craftedId = recipeId and addon:GetRecipeCraftedItemId(171, recipeId)
                    local craftedName = craftedId and addon.Item.GetInfo(craftedId)
                    local outputName
                    if craftedName and craftedName ~= "" then
                        outputName = craftedName
                    elseif entryName and entryName ~= "" then
                        outputName = entryName
                    elseif spellName and spellName ~= "" then
                        outputName = spellName
                    elseif recipeId then
                        outputName = addon.Item.GetInfo(recipeId) or spellName or ""
                    else
                        outputName = spellName or ""
                    end
                    CdMail_PrepareSupplyMail(charKey, spellName, outputName, mailReagents)
                end)
                mailBtn:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(mailBtn)
                    GameTooltip:SetText(L["MailBtnTooltip"], 1, 1, 1, 1, true)
                    GameTooltip:AddLine(L["MailBtnTooltipDesc"], nil, nil, nil, true)
                    showAbovePopup()
                end)
                mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
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
    -- Escape closes this popup before the main window.
    if addon.MainWindow then addon.MainWindow:AddEscapeChild(popup) end
end

-- ---------------------------------------------------------------------------
-- AH callbacks
-- ---------------------------------------------------------------------------
-- (Removed: per-tab AH_OPEN_STATE_CHANGED / AH_SCAN_COMPLETE handlers.
-- The shared addon.GUI.MakeScanAHButton factory in GUI/SharedWidgets.lua
-- owns one global handler that refreshes the active tab's scan button +
-- runs the tab's onRefresh hook. The hook for this tab repaints the list,
-- which re-reads the [AH] column's `show`.)
