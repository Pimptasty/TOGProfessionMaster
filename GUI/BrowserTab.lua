-- TOG Profession Master — Profession Browser Tab
-- Draws the "Professions" tab inside the main window.
--
-- Layout:
--   [Profession ▼]  [Search .................]  [Guild ▼]
--   ┌──────────────────────────────┬────────────────────────────┐
--   │ [icon] Recipe   Crafter, +N  │ [icon] Selected Recipe     │
--   │ [icon] Recipe 2 You          │ Shopping: [-] 1 [+] [x]   │
--   │ ...                          │ Reagents ──────────────    │
--   │                              │  [i] Iron Ore      ×5      │
--   │                              │ Known By ──────────────    │
--   │                              │  |cff..You|r               │
--   └──────────────────────────────┴────────────────────────────┘
--
-- Clicking a recipe row populates the right-hand detail panel.
-- The left list is a LibAceGUIWidgets RowList (MINOR 36), which draws only the
-- visible rows.

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local BrowserTab = {}
addon.BrowserTab = BrowserTab

-- Row height of the recipe list and the shopping list.
local ROW_HEIGHT = 14

-- Resolve the best chat-insertable link for a recipe entry, falling back
-- through several sources so the link / tooltip work even when the cached
-- itemLink and recipeLink are both missing (true for trainer-taught recipes
-- and for stub-created entries before recipemeta arrives).
--
-- entry.id is ALWAYS a spell id — every key in addon.recipeDB
-- (LibProfessionDB) is the recipe's SkillLineAbility spell, for every
-- profession and every flavour — so it must never be handed to an item API.
-- Doing so silently resolves whatever unrelated ITEM happens to share the
-- number: spell 13937 (Enchant 2H Weapon - Impact) vs item 13937 (Headmaster's
-- Charge), which is exactly what made enchant hovers show a random staff.
-- Crafted-item recipes escaped it only because entry.itemLink is populated
-- from craftedItemId and wins first; enchants have no crafted item, so they
-- fell straight through to the bad GetItemInfo(entry.id) lookup.
--
-- Priority: entry.itemLink (crafted item) > entry.recipeLink (recipe scroll) >
-- GetItemInfo(entry.craftedItemId) > GetSpellLink(spellId) > synthetic
-- "spell:<id>" link.
local function ResolveRecipeLink(entry)
    if not entry then return nil end
    if type(entry.itemLink)   == "string" and entry.itemLink:find("|Hitem:")   then return entry.itemLink   end
    if type(entry.recipeLink) == "string" and entry.recipeLink:find("|Hitem:") then return entry.recipeLink end
    if type(entry.craftedItemId) == "number" then
        local _, link = addon.Item.GetInfo(entry.craftedItemId)
        if link then return link end
    end
    -- entry.id is a recipeDB key, i.e. a spell id, with or without the isSpell
    -- flag — deliberately NOT gated on the flag, so an entry built before the
    -- flag existed still resolves as a spell instead of falling through to an
    -- item lookup.
    local spellId = entry.spellId or entry.id
    if type(spellId) == "number" then
        local link = addon.Spell.GetLink(spellId)
        if link then return link end
    end
    -- Synthetic minimal link. Won't carry the proper colour or stats but
    -- will at least populate chat with something the user can paste.
    if spellId then
        return "|cff71d5ff|Hspell:" .. spellId .. "|h[" .. (entry.name or ("#" .. spellId)) .. "]|h|r"
    end
    return nil
end

-- Anchor the recipe's SPELL tooltip (the trade-skill spell: description +
-- reagents). SetSpellByID isn't guaranteed on every Classic flavour, so fall
-- back to the "spell:<id>" hyperlink form, which every client resolves (the
-- same call CooldownsTab's popup uses). Returns true when something was set.
local function SetSpellTooltip(tooltip, spellId)
    if type(spellId) ~= "number" then return false end
    if tooltip.SetSpellByID then
        tooltip:SetSpellByID(spellId)
    else
        tooltip:SetHyperlink("spell:" .. spellId)
    end
    return true
end

-- Offline-test seam (Tests/browserlink_spec.lua). These file-locals carry the
-- "is this number a spell id or an item id?" decision that made enchant hovers
-- resolve an unrelated item, so the suite drives them directly. Unused at
-- runtime — the addon always calls the locals.
BrowserTab._ResolveRecipeLink = ResolveRecipeLink
BrowserTab._SetSpellTooltip   = SetSpellTooltip

-- Append the brand-coloured [TOGPM] crafters + IDs lines to GameTooltip
-- for a BrowserTab entry. Pulls itemID and spellID from the entry, then
-- defers to addon.Tooltip's shared helpers — same code paths the global
-- item-hover tooltip uses, so Browser tooltips look identical to AH /
-- bag / chat-link tooltips. Crafters line only fires for recipes that
-- produce an item (the item-tooltip hook resolves crafters from an item
-- id, not a spell id); IDs line always fires (gated on tooltipShowIds).
local function AppendBrandTooltipLines(entry)
    if not entry then return end
    -- Enriched effect text ("+5 Weapon Damage", "+12 Agility", "Mining") from
    -- the authoritative recipeDB. Shown in green right under the recipe name —
    -- crucial for guild recipes the local client can't resolve natively (the
    -- custom/fallback name-only tooltip would otherwise carry no detail).
    if entry.effect and entry.effect ~= "" then
        GameTooltip:AddLine(entry.effect, 0.4, 1, 0.4, true)
    end
    -- Crafters line — keyed by the CRAFTED item, which is what the tooltip is
    -- actually showing (AppendCraftersNow re-verifies via GameTooltip:GetItem
    -- and bails on a mismatch). entry.id is a spell id and must never be used
    -- here: it silently resolved an unrelated item and the line never appeared.
    -- Enchants have no crafted item, so they legitimately get no crafters line
    -- (the row / detail panel already lists them).
    local craftedId = entry.craftedItemId
    if type(craftedId) == "number" and addon.Tooltip.AppendCrafters then
        addon.Tooltip.AppendCrafters(GameTooltip, craftedId)
    end
    -- IDs line. entry.id is the recipe's spell id (every addon.recipeDB key
    -- is); the item id, when the recipe produces one, is entry.craftedItemId.
    if addon.Tooltip.AppendBrandIds then
        local spellID = entry.spellId or entry.id
        addon.Tooltip.AppendBrandIds(GameTooltip, craftedId, spellID)
    end
    -- Recipe details (difficulty + sources), UNGATED by the RecipeMaster check.
    -- That gate asks "would RM already have drawn this?", and for a tooltip in
    -- our own window the answer is always no: RM attaches through
    -- OnTooltipSetItem, which never fires for a tooltip assembled from AddLine
    -- calls, and does not fire for our SetHyperlink branches either because RM
    -- has no idea our window exists. Gating here would hand a RecipeMaster user
    -- an addon window with the block conspicuously missing. "Never" still wins —
    -- that check lives inside AppendRecipeDetails.
    --
    -- Called on every branch because this function is: the real-scroll tooltip,
    -- the scroll-shaped one, and the name-only fallback all route through here,
    -- and the block must not depend on which one a given recipe happened to get.
    addon.ItemLink.AppendRecipeDetails(GameTooltip, entry.profId, entry.id)
    -- The row says "(unconfirmed)"; the tooltip says what that means. Here for
    -- the same reason as the block above: every branch passes through.
    addon.ItemLink.AppendUnconfirmed(GameTooltip, entry.unconfirmed)
end
BrowserTab._AppendBrandTooltipLines = AppendBrandTooltipLines   -- test seam, see above

-- Detail panel constants
local DP_W    = 268   -- outer width of the right detail panel
local DP_PAD  = 6     -- inner padding
local DP_GAP  = 4     -- gap between left list and detail panel
local DP_ROW  = 14    -- row height inside the detail panel
local DP_ICON = 18    -- recipe icon size in detail header

-- Minimum row width below which the recipe pool's name + crafter list +
-- [Bank] start to stack and overlap. Computed from the row's anchor
-- arithmetic: 22 (icon area) + 160 (nameLbl fixed width) + 80 (minimum
-- crafter list area) + 56 (bank button + right pad) = 318 for the recipe
-- pool, + 4 (DP_GAP) + 268 (DP_W) = 590 total content. Add safety to
-- guarantee fit. MainWindow reads this and uses max() with the other
-- tabs' minimums when setting SetResizeBounds — preventing the user
-- from dragging the window narrow enough to break this tab's layout.
BrowserTab.MIN_ROW_WIDTH = 600

-- Window size policy — Browser is the ONLY resizable tab. Unlike Cooldowns
-- and Missing (which lock to a fixed size for content predictability),
-- Browser benefits from extra width for the recipe-pool / detail-panel
-- split. MainWindow reads this on tab switch: it restores the user's last
-- Browser-tab size from saved-vars (browserWidth/browserHeight) and
-- enforces this minimum via SetResizeBounds.
BrowserTab.WINDOW_SIZE = { minWidth = BrowserTab.MIN_ROW_WIDTH + 80, minHeight = 350 }

-- ---------------------------------------------------------------------------
-- TOGBankClassic integration helpers
-- ---------------------------------------------------------------------------

-- Resolve a reagent's item ID, falling back through itemLink → name lookup.
-- On Classic Era, GetTradeSkillReagentItemLink returns nil for many reagents
-- so the scan path can't always populate itemLink — without this helper the
-- bank-stock lookup at render time silently fails for older scanned recipes
-- and for peer broadcasts predating v0.1.5. Cached back onto the reagent
-- table so subsequent renders are O(1).
local function ResolveReagentItemId(r)
    if not r then return nil end
    if r.itemId and r.itemId > 0 then return r.itemId end
    if type(r.itemLink) == "string" then
        local id = tonumber(r.itemLink:match("item:(%d+)"))
        if id then r.itemId = id; return id end
    end
    if r.name then
        local id = addon.Item.GetInfoInstant(r.name)
        if id then r.itemId = id; return id end
    end
    return nil
end

-- Resolve a reagent's item link, reconstructing it from itemId via GetItemInfo
-- when the original link is missing.  GetItemInfo returns nil for items not
-- yet in the local cache; callers should treat a nil result as "unavailable
-- this frame, try again next render."
local function ResolveReagentItemLink(r)
    if type(r.itemLink) == "string" and r.itemLink ~= "" then return r.itemLink end
    local id = ResolveReagentItemId(r)
    if id then
        local _, link = addon.Item.GetInfo(id)
        if link then r.itemLink = link; return link end
    end
    return nil
end

-- Hidden tooltip used to scrape raw item data without triggering other addon hooks.
local _itemScraper
local function GetItemScraper()
    if not _itemScraper then
        _itemScraper = CreateFrame("GameTooltip", "TOGPMItemScraper", nil, "GameTooltipTemplate")
        _itemScraper:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return _itemScraper
end

-- State persisted across tab switches (reset on UI reload).
BrowserTab._selectedProfId    = 0        -- 0 = All Professions (default)
BrowserTab._selectedProfs     = nil      -- multi-select profession set
BrowserTab._selectedTiers     = nil      -- skill-tier filter: set of enabled
                                         -- SKILL_TIER_BANDS keys, or nil = all
                                         -- tiers shown (see FilterTiers).
BrowserTab._searchText        = ""
BrowserTab._viewMode          = "guild"  -- "guild" | "mine" | "missing"
BrowserTab._showAllRecipes    = false    -- v0.7.0 toolbar checkbox: when true,
                                         -- include recipes from the shipped
                                         -- addon.recipeDB with no crafters
                                         -- (rendered greyed out). Pairs with
                                         -- the "Show Missing" entry in the
                                         -- profession dropdown for gap-finding.
BrowserTab._listSection       = nil      -- AceGUI group the list + detail panel sit in
BrowserTab._container         = nil      -- the tab container widget
BrowserTab._rowList           = nil      -- the recipe RowList (lives for the session)
BrowserTab._recipes           = nil      -- current filtered recipe list
BrowserTab._detailOuter       = nil      -- persistent right-panel raw frame
BrowserTab._selectedEntry     = nil      -- recipe currently shown in detail panel
BrowserTab._slSection         = nil      -- shopping list InlineGroup (if visible)

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

local function GetGuildDb()
    return addon:GetGuildDb()
end

-- Profession dropdown entries — built fresh each call from the shared
-- master list so a profession added to addon.PROF_NAMES (in
-- TOGProfessionMaster.lua) automatically appears here on the right
-- versions. Filters by:
--   • addon.CRAFTING_PROFS — Browser shows craftable recipes only,
--     skipping pure gathering professions (Herbalism / Skinning /
--     Fishing) and Smelting (which is a sub-skill of Mining).
--   • addon.IsProfessionAvailable — hide professions that don't exist
--     on this client version (Jewelcrafting on Vanilla, Inscription on
--     Vanilla / TBC).
local function GetProfDropdownEntries()
    local entries = { { profId = 0, name = L["AllProfessions"] } }
    local crafting = {}
    for profId in pairs(addon.CRAFTING_PROFS or {}) do
        if addon.IsProfessionAvailable(profId) then
            crafting[#crafting + 1] = profId
        end
    end
    table.sort(crafting, function(a, b)
        return (addon.PROF_NAMES[a] or "") < (addon.PROF_NAMES[b] or "")
    end)
    for _, profId in ipairs(crafting) do
        entries[#entries + 1] = { profId = profId, name = addon.PROF_NAMES[profId] }
    end
    return entries
end

-- v0.7.0: gdb.recipes is already a flat universal table (no more per-guild
-- buckets), so the old cross-bucket merge for the "mine" view collapses into
-- a single direct return. viewMode filtering now happens at the BuildRecipeList
-- level via the visibility gate (IsVisibleCrafter + IsMyCharacter).
local function CollectRecipesForView(_viewMode)
    local gdb = GetGuildDb()
    return gdb and gdb.recipes or {}
end

-- Recipe list pipeline (split so the slow part runs once and search is cheap):
--   BuildFullList(profId, viewMode, opts) — the expensive, search-INDEPENDENT
--     build (DB lookups, per-crafter visibility gate, tooltip text). Cached +
--     background-warmed. profId 0 = all professions; viewMode "guild"/"mine"/
--     "missing"; opts.showAll also yields no-crafter rows (greyed); viewMode
--     "missing" yields ONLY no-crafter rows.
--   FilterList(full, searchText) — cheap per-keystroke search over the cache.
--   GetFullList / FillList — read the cache (or build on a miss), then FilterList.
--
-- Cheap search filter over an already-built full list. Every whitespace term
-- must appear in the row's precomputed `searchText` (name + effect + item
-- tooltip, lowercased), order-independent — tokens so "5 agi" matches the
-- stat-first "Agility +5". Empty query returns the full list unchanged. THIS is
-- what runs on every keystroke now: no DB reads, no visibility gate, no tooltip
-- scans — those all happened once when the full list was built and cached.
local function FilterList(full, searchText)
    local filter = searchText and searchText:lower() or ""
    if filter == "" then return full end
    local terms = {}
    for t in filter:gmatch("%S+") do terms[#terms + 1] = t end
    if #terms == 0 then return full end
    local out = {}
    for _, row in ipairs(full) do
        local hay  = row.searchText or ""
        local keep = true
        for _, term in ipairs(terms) do
            if not hay:find(term, 1, true) then keep = false; break end
        end
        if keep then out[#out + 1] = row end
    end
    return out
end

-- Skill-tier bands for the "Skill tier" toolbar filter. Each band is the
-- 75-point training block named after its WoW trainer rank; `cap` is the
-- inclusive top of the band (also the trainer skill cap for that rank), `min`
-- the inclusive bottom. A recipe's band is the first one whose cap is >= its
-- learn skill, so bands are disjoint and cover the whole 1..600 range. Only
-- bands reachable on the running client (cap <= clientMaxSkill) are offered in
-- the dropdown. `labelKey` is the AceLocale key for the rank name; the numeric
-- range is appended in code (locale-independent) so translators only touch the
-- name — see TierBandLabel below.
local TIER_SELECT_ALL = "__tier_select_all__"
local TIER_CLEAR_ALL  = "__tier_clear_all__"
local SKILL_TIER_BANDS = {
    { key = "apprentice",  labelKey = "TierApprentice",  min = 1,   cap = 75  },
    { key = "journeyman",  labelKey = "TierJourneyman",  min = 76,  cap = 150 },
    { key = "expert",      labelKey = "TierExpert",      min = 151, cap = 225 },
    { key = "artisan",     labelKey = "TierArtisan",     min = 226, cap = 300 },
    { key = "master",      labelKey = "TierMaster",      min = 301, cap = 375 },
    { key = "grandmaster", labelKey = "TierGrandMaster", min = 376, cap = 450 },
    { key = "illustrious", labelKey = "TierIllustrious", min = 451, cap = 525 },
    { key = "zenmaster",   labelKey = "TierZenMaster",   min = 526, cap = 600 },
}

-- Localized display label for a band: "<rank name> (min-cap)". The rank name is
-- localized; the numeric range is universal.
local function TierBandLabel(band)
    return ("%s (%d-%d)"):format(L[band.labelKey] or band.labelKey, band.min, band.cap)
end

-- Map a learn skill (requiredSkill, or difficulty[1] fallback) to a band key.
local function TierBandKey(reqSkill)
    if not reqSkill or reqSkill < 1 then return nil end
    for _, band in ipairs(SKILL_TIER_BANDS) do
        if reqSkill <= band.cap then return band.key end
    end
    return SKILL_TIER_BANDS[#SKILL_TIER_BANDS].key
end

-- Filter a full list by the enabled-tier set. `tiers` is a set of enabled band
-- keys, or nil meaning "all tiers shown" (the default) — in which case the list
-- is returned untouched. Recipes with no known learn skill (reqSkill nil) are
-- always kept: we never hide something we can't classify.
local function FilterTiers(full, tiers)
    if not tiers then return full end
    local out = {}
    for _, row in ipairs(full) do
        if not row.reqSkill or tiers[TierBandKey(row.reqSkill)] then
            out[#out + 1] = row
        end
    end
    return out
end

-- Stable cache key for a (profId, viewMode, showAll) build. profId may be a
-- number (0 = All), or a SET table (multi-select professions) — the latter is
-- folded to a sorted, comma-joined string so the same selection always maps to
-- the same key regardless of table identity.
local function listCacheKey(profId, viewMode, showAll)
    local pk
    if type(profId) == "table" then
        local ids = {}
        for k in pairs(profId) do ids[#ids + 1] = tostring(k) end
        table.sort(ids)
        pk = "{" .. table.concat(ids, ",") .. "}"
    else
        pk = tostring(profId)
    end
    return pk .. "|" .. tostring(viewMode or "guild") .. "|" .. (showAll and "1" or "0")
end

-- BuildFullList helpers, hoisted to file scope so a build does not create a
-- fresh closure per recipe for each sort. Same orderings as before: online
-- crafters first, then by name; own alts by name.
local _NIL_TAG = {}   -- memo key standing in for a nil crafter tag
local function crafterOrder(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
end
local function nameOrder(a, b) return a.name < b.name end

-- Build the FULL, search-INDEPENDENT recipe list for a profession/view. This is
-- the expensive half — DB lookups, the per-crafter visibility gate, and the
-- per-item tooltip search text — so it runs ONCE and is cached (and pre-warmed
-- in the background via addon.Warmer); search then just FilterList()s the cache.
-- Yields between recipes (addon.Warmer:Yield) so the warm can slice it across
-- frames without stuttering; that's a no-op when called synchronously on demand.
-- Each row carries `searchText` for the cheap filter above.
local function BuildFullList(profId, viewMode, opts)
    if profId == nil or (type(profId) == "table" and next(profId) == nil) then return {} end
    local gdb = GetGuildDb()
    if not gdb then return {} end
    local recipes = CollectRecipesForView(viewMode)

    local myKey   = addon:GetCharacterKey()
    local showAll = opts and opts.showAll or false
    local list    = {}
    -- Yield counter spanning the WHOLE build (across professions for profId 0),
    -- so the background warm slices evenly even when each profession is small.
    local _yieldN = 0

    -- Per-build memoization of the per-crafter visibility checks. A crafter appears
    -- under EVERY recipe they know (a maxed blacksmith → 100+ recipes), so without this
    -- IsMyCharacter / IsInCurrentGuildScope / IsVisibleCrafter would each run once per
    -- (recipe × crafter) — tens of thousands of roster lookups on a big guild, which is
    -- what froze the first (synchronous) open. Memoized by charKey they run once per
    -- unique crafter. Safe: the checks are stable within one build pass, and
    -- IsVisibleCrafter's FlagForPurge side-effect is idempotent (pendingPurge is a set).
    local _mineMemo, _scopeMemo, _visMemo = {}, {}, {}
    local function craftIsMine(ck)
        local v = _mineMemo[ck]
        if v == nil then v = addon:IsMyCharacter(ck) and true or false; _mineMemo[ck] = v end
        return v
    end
    local function craftInScope(ck)
        local v = _scopeMemo[ck]
        if v == nil then v = addon:IsInCurrentGuildScope(ck) and true or false; _scopeMemo[ck] = v end
        return v
    end
    local function craftIsVisible(ck, tag)
        -- Key on ck+tag, not ck alone: a crafter's visibility depends on its guild tag,
        -- which can legitimately differ across recipes during a mid-sync guild switch —
        -- keying on ck alone would apply the first-seen tag's verdict to all its recipes.
        -- Two-level (tag, then ck) rather than a concatenated "ck\0tag" key: the
        -- concatenation built and hashed a fresh string for every recipe-crafter
        -- pair (~37k on a large guild) just to look the memo up.
        local byTag = _visMemo[tag == nil and _NIL_TAG or tag]
        if not byTag then byTag = {}; _visMemo[tag == nil and _NIL_TAG or tag] = byTag end
        local v = byTag[ck]
        if v == nil then v = addon:IsVisibleCrafter(ck, tag) and true or false; byTag[ck] = v end
        return v
    end

    -- Per-build memo of what a visible guild crafter DISPLAYS as: their short
    -- name, or "Alt (Main)" when the crafter is offline and an alt of theirs is
    -- online, plus the online flag. Like the memos above it is stable for one
    -- build pass (online state is read once per build either way) and keyed by
    -- crafter, so the roster lookups -- IsOnline per crafter, and per alt of
    -- every offline crafter -- run once per unique crafter instead of once per
    -- recipe-crafter pair. Each row still gets its own { name, online } table.
    local _shownName, _shownOnline = {}, {}
    local GuildRoster = addon.Scanner and addon.Scanner.GuildRoster
    local function crafterDisplay(ck)
        local displayName = _shownName[ck]
        if displayName ~= nil then return displayName, _shownOnline[ck] end
        local shortName = ck:match("^(.-)%-") or ck
        local online    = GuildRoster and GuildRoster:IsOnline(ck) or false
        displayName = shortName
        if not online and gdb.altGroups and gdb.altGroups[ck] then
            for _, altCk in ipairs(gdb.altGroups[ck]) do
                if altCk ~= ck and GuildRoster and GuildRoster:IsOnline(altCk) then
                    local altShort = altCk:match("^(.-)%-") or altCk
                    displayName = altShort .. " (" .. shortName .. ")"
                    online = true
                    break
                end
            end
        end
        _shownName[ck], _shownOnline[ck] = displayName, online
        return displayName, online
    end

    -- v0.7.5: per-client expansion cap. The shipped recipeDB is a universal
    -- union of every recipe across every expansion (wago.tools' MoP build
    -- inherits Vanilla / TBC / Wrath / Cata content), so an unfiltered
    -- iteration shows Wrath / Cata / MoP recipes to a Vanilla user — both
    -- in the "Show all recipes" mode (showAll = true) AND through guild
    -- view when a peer in a different-version guild has broadcast their
    -- data and our addon.recipeDB happens to include it. The MissingRecipesTab
    -- already applies the same gate (see GUI/MissingRecipesTab.lua:284-318);
    -- pull the rules in here so the Browser tab agrees with it.
    --   minExpansion       : recipeDB ships 1=Vanilla, 2=TBC, 3=Wrath,
    --                        4=Cata, 5=MoP — primary cross-expansion gate.
    --   clientMaxSkill cap : belt-and-suspenders against future-expansion
    --                        recipes whose minExpansion tag is missing but
    --                        whose requiredSkill exceeds the client's cap.
    --   spellId > 25000    : defensive gate for Classic Era against untagged
    --                        post-Vanilla recipes (covers Cata / SoD /
    --                        Anniversary additions that lack minExpansion).
    --   season             : SoD seasonal content — hidden on EVERY client,
    --                        including a SoD realm. This addon does not support
    --                        Season of Discovery; IsSoD() exists only to relax
    --                        the exclusion gates above, never to enable SoD
    --                        behaviour. (This line used to read "hide on non-SoD
    --                        clients", which the code below has never done.)
    --
    -- All of the above now lives in ONE place — addon.RecipeGate
    -- (Modules/RecipeGate.lua) — and is shared with MissingRecipesTab. It used
    -- to be written out here as a second copy of that tab's chain, and the two
    -- drifted: this copy had the First Aid blacklist and no phase gate, that one
    -- had the phase gate and no First Aid blacklist. Do not re-inline any of it.
    local function passesClientGate(thisProfId, recipeId)
        local meta = addon.recipeDB and addon.recipeDB[thisProfId]
                                    and addon.recipeDB[thisProfId][recipeId]
        return (addon.RecipeGate:IsValidOnClient(thisProfId, recipeId, meta))
    end

    local function buildCrafterList(profRecipeData, thisViewMode)
        if not profRecipeData or not profRecipeData.crafters then return nil end
        local crafterObjs = {}
        local youSelf, youAlts = nil, {}
        for ck, tag in pairs(profRecipeData.crafters) do
            -- Own alts: shown in the "mine" view regardless of guild, but in the
            -- guild/missing views ONLY when the alt is in the current guild scope
            -- — otherwise a cross-guild alt (a toon of yours in another guild)
            -- leaks its recipes into this guild's list. See IsInCurrentGuildScope.
            if craftIsMine(ck)
               and (thisViewMode == "mine" or craftInScope(ck)) then
                if ck == myKey then
                    youSelf = { name = L["You"], online = true, isYou = true }
                else
                    local altShort = ck:match("^(.-)%-") or ck
                    table.insert(youAlts, {
                        name   = L["You"] .. " (" .. altShort .. ")",
                        online = true,
                        isYou  = true,
                    })
                end
            elseif thisViewMode ~= "mine" and craftIsVisible(ck, tag) then
                local displayName, online = crafterDisplay(ck)
                crafterObjs[#crafterObjs + 1] = { name = displayName, online = online }
            end
        end
        table.sort(crafterObjs, crafterOrder)
        table.sort(youAlts, nameOrder)
        for i = #youAlts, 1, -1 do
            table.insert(crafterObjs, 1, youAlts[i])
        end
        if youSelf then
            table.insert(crafterObjs, 1, youSelf)
        end
        return crafterObjs
    end

    local function processProf(thisProfId, profRecipes)
        local profName   = addon.PROF_NAMES[thisProfId] or ""
        local profIconId = addon.ProfessionIcons and addon.ProfessionIcons[thisProfId]
                        or (addon.ProfessionIconFallback or 134400)
        local profMetaDB = addon.recipeDB and addon.recipeDB[thisProfId]

        -- Build the union of recipeIds to consider:
        --   default               → keys of profRecipes (recipes someone knows)
        --   showAll or missing    → keys of profMetaDB (every shipped recipe)
        local recipeIdSet = {}
        if showAll or viewMode == "missing" then
            if profMetaDB then
                for rId in pairs(profMetaDB) do recipeIdSet[rId] = true end
            end
        end
        if profRecipes then
            for rId in pairs(profRecipes) do recipeIdSet[rId] = true end
        end

        for recipeId in pairs(recipeIdSet) do
            _yieldN = _yieldN + 1
            -- Yield to the Warmer every 25 recipes so a BACKGROUND build slices
            -- across frames (invisible). No-op when called synchronously. We
            -- yield BETWEEN recipes, never inside buildCrafterList, so each
            -- crafter walk stays atomic even if sync mutates gdb between frames.
            if _yieldN % 25 == 0 then addon.Warmer:Yield() end
            local rd = profRecipes and profRecipes[recipeId]

            -- Only recipes the local addon DB knows + valid on this client
            -- version are kept (unknown / wrong-expansion recipeIds hidden
            -- silently — see passesClientGate). NO search filter here: this is
            -- the full, search-INDEPENDENT list — FilterList() does the search.
            if profMetaDB and profMetaDB[recipeId]
               and passesClientGate(thisProfId, recipeId) then
                local name          = addon:GetRecipeName(thisProfId, recipeId)
                local craftedItemId = addon:GetRecipeCraftedItemId(thisProfId, recipeId)
                -- Effect/buff text: the shipped enchant effect, else the crafted
                -- consumable's use-effect buff from LibItemDB (food/elixir/flask),
                -- so those recipes are searchable by stat ("12 stam").
                local effect = addon:GetCraftedItemStatText(craftedItemId)
                if not effect or effect == "" then effect = profMetaDB[recipeId].effect end

                local crafters = rd and buildCrafterList(rd, viewMode) or {}
                local hasAny   = (#crafters > 0)

                -- View-mode filter (needs the crafter-list size).
                local viewKeep
                if viewMode == "mine" then
                    -- Crafted by one of my own characters
                    viewKeep = false
                    if rd and rd.crafters then
                        for ck in pairs(rd.crafters) do
                            if craftIsMine(ck) then viewKeep = true; break end
                        end
                    end
                elseif viewMode == "missing" then
                    viewKeep = (not hasAny)
                else  -- "guild" (default)
                    viewKeep = showAll or hasAny
                end

                if viewKeep then
                    -- Precompute the searchable text ONCE — name + effect + the
                    -- crafted item's full tooltip (use/proc/durations/flavor),
                    -- lowercased — so FilterList is a cheap string match per
                    -- keystroke instead of re-scanning tooltips every time.
                    -- Assembled as parts + one table.concat: appending each piece
                    -- with `..` copied the whole growing string every time, which
                    -- for a recipe with a hundred crafters is a hundred copies and
                    -- was ~65 MB of garbage per All-professions build.
                    local parts = { (name or ""):lower() }
                    if effect and effect ~= "" then parts[#parts + 1] = effect:lower() end
                    local tt = craftedItemId and addon:GetItemTooltipSearchText(craftedItemId)
                    if tt then parts[#parts + 1] = tt end
                    -- Fold the crafter names into the haystack so typing a player's
                    -- name in the search box filters the list to the recipes that
                    -- player crafts. Reuses `crafters` (already built above), so it
                    -- honours the same viewMode/visibility rules as the shown crafter
                    -- list — a name only matches recipes where that crafter is visible.
                    for _, c in ipairs(crafters) do
                        if c.name then parts[#parts + 1] = c.name:lower() end
                    end
                    local hay = table.concat(parts, " ")
                    local itemLink = craftedItemId and select(2, addon.Item.GetInfo(craftedItemId))
                    -- Learn skill for the tier filter: authoritative requiredSkill
                    -- when shipped, else the orange (difficulty[1]) breakpoint
                    -- unless ProfessionDB marks the tiers unanchored — same
                    -- helper MissingRecipesTab uses. nil when unknown;
                    -- FilterTiers keeps those rows unconditionally.
                    local meta      = profMetaDB[recipeId]
                    local reqSkill  = addon.RecipeLearnSkill(meta)
                    table.insert(list, {
                        id            = recipeId,
                        -- The profession this row belongs to. Rows are built per
                        -- profession and consumers used to read profName only, so
                        -- this was never recorded -- which silently cost two
                        -- things: ScrollHeader could not look the recipe up and
                        -- dropped its "Requires Engineering (190)" line, and
                        -- TeachingItem's meta.itemId fallback was unreachable.
                        -- That fallback is the ONLY teaching-item source on
                        -- Wrath / Cata / Mists, where no scroll data is generated.
                        profId        = thisProfId,
                        -- Every addon.recipeDB key is the recipe's trade-skill
                        -- SPELL id (LibProfessionDB builds them from
                        -- SkillLineAbility), on every profession and every
                        -- flavour — record that explicitly so no consumer
                        -- mistakes `id` for an item id. The crafted item, when
                        -- there is one, is craftedItemId below.
                        spellId       = recipeId,
                        isSpell       = true,
                        name          = name,
                        reqSkill      = reqSkill,
                        effect        = effect,
                        profName      = profName,
                        profIconId    = profIconId,
                        icon          = addon:GetRecipeIcon(thisProfId, recipeId),
                        craftedItemId = craftedItemId,
                        itemLink      = itemLink,
                        reagents      = addon:GetRecipeReagents(thisProfId, recipeId),
                        crafters      = crafters,
                        greyed        = (not hasAny),  -- v0.7.0: rendered de-emphasized
                        -- Shown only because its "never implemented" flag is
                        -- another flavour's (WoW Forever): the row and its
                        -- tooltip mark it unconfirmed. Worked out here, once
                        -- per build, so a repaint pays nothing for it.
                        unconfirmed   = addon.RecipeGate:IsUnconfirmed(recipeId) or nil,
                        searchText    = hay,
                    })
                end
            end
        end
    end

    if type(profId) == "table" then
        for pid in pairs(profId) do
            processProf(pid, recipes[pid])
        end
    elseif profId == 0 then
        -- "All professions" view. Iterate the union of
        --   (a) profs with at least one crafter row in gdb.recipes, AND
        --   (b) profs in addon.recipeDB when showAll / missing is active
        --       (so empty professions still surface their unlearned recipes).
        local profIds = {}
        for pid in pairs(recipes) do profIds[pid] = true end
        if (showAll or viewMode == "missing") and addon.recipeDB then
            for pid in pairs(addon.recipeDB) do profIds[pid] = true end
        end
        for pid in pairs(profIds) do
            processProf(pid, recipes[pid])
        end
    else
        processProf(profId, recipes[profId])
    end

    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ---------------------------------------------------------------------------
-- Offline-test seam
--
-- Everything above this line is the tab's LOGIC half — the recipe-list pipeline,
-- the search and tier filters, the cache key — and it touches no frame at all
-- (the first CreateFrame in this file is in Draw, below). It is `local` only
-- because nothing outside the file needs it at runtime, which also put it out of
-- reach of the spec suite. Exposing it here is what makes it testable WITHOUT
-- relocating it: a move would buy nothing a name doesn't, and would mean a new
-- file in all five .toc load orders. Not used by the addon at runtime — every
-- caller below uses the local directly.
-- See Tests/browserlist_spec.lua.
-- ---------------------------------------------------------------------------
BrowserTab._BuildFullList          = BuildFullList
BrowserTab._FilterList             = FilterList
BrowserTab._FilterTiers            = FilterTiers
BrowserTab._TierBandKey            = TierBandKey
BrowserTab._TierBandLabel          = TierBandLabel
BrowserTab._listCacheKey           = listCacheKey
BrowserTab._CollectRecipesForView  = CollectRecipesForView
BrowserTab._GetProfDropdownEntries = GetProfDropdownEntries
BrowserTab._ResolveReagentItemId   = ResolveReagentItemId
BrowserTab._ResolveReagentItemLink = ResolveReagentItemLink
BrowserTab._SKILL_TIER_BANDS       = SKILL_TIER_BANDS

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function BrowserTab:Draw(container)
    addon:DebugPrint("BrowserTab:Draw — prof=", self._selectedProfId,
        "view=", self._viewMode, "cacheKeys=", self._listCache and "(table)" or "nil")
    self._container = container
    -- Flow, not List: the last row (the recipe list and detail panel) is full
    -- height, and Flow is the layout that gives a full-height child the rest
    -- of the tab -- the Cooldowns tab's shape.
    container:SetLayout("Flow")

    self._slSection = nil
    local slData = Ace.db.char.shoppingList
    -- One pass. The count already answers "is it non-empty?", so the previous
    -- probe-then-count walked the table twice and the probe was a `for … break`
    -- that never loops.
    local slCount = 0
    for _ in pairs(slData) do slCount = slCount + 1 end
    local hasSL = slCount > 0

    -- ---- Toolbar -----------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    local profEntries = GetProfDropdownEntries()
    -- Initialize to "All Professions" (0) if no selection exists. The saved
    -- filter is account-wide (profile scope) and only honoured when the user has
    -- opted in via the persistProfFilter setting. Storage goes through the shared
    -- addon.GUI.PersistentChoice helper.
    if not self._selectedProfId then
        local getProfFilter = addon.GUI.PersistentChoice("profile", "savedProfFilter", 0)
        self._selectedProfId = (Ace.db.profile.persistProfFilter and getProfFilter()) or 0
    end

    local profItems = {}
    for _, p in ipairs(profEntries) do
        profItems[#profItems + 1] = { value = p.profId, text = p.name }
    end

    addon.GUI.ToolbarDropdown(self, "prof", toolbar, {
        label    = L["PanelProfessions"],
        width    = 180,
        items    = function() return profItems end,
        value    = self._selectedProfId,
        onChange = function(value)
            self._selectedProfId = value
            if Ace.db.profile.persistProfFilter then
                local _, setProfFilter = addon.GUI.PersistentChoice("profile", "savedProfFilter")
                setProfFilter(value)
            end
            self:RefreshList()
        end,
        tipTitle = "Profession Filter",
        tipBody  = "Pick a profession to filter the recipe list.",
    })

    local spTier = AceGUI:Create("Label"); spTier:SetWidth(8); toolbar:AddChild(spTier)

    -- Skill-tier multi-select filter: a tick-box menu that stays open while
    -- ticking tiers, with Select All / Clear All at the bottom as rows that
    -- act and close it. Only tiers reachable on this client version are offered.
    -- The filter runs post-cache (in FillList → FilterTiers) so changing it is a
    -- cheap re-filter, never a rebuild.
    -- Skill cap comes from addon.RecipeGate:Client() — the same table the recipe
    -- gate uses. This was a third hand-written copy of the expansion ladder and
    -- had already drifted (it folded MoP into the else branch).
    local _, clientMaxSkill = addon.RecipeGate:Client()

    -- Hydrate the saved tier selection once per session (state resets on reload).
    -- { __none = true } is the Clear All marker → an empty enabled set; any other
    -- non-empty table restores its keys; absent/nil leaves the default (all on).
    if not self._tiersHydrated then
        self._tiersHydrated = true
        local getTiers = addon.GUI.PersistentChoice("profile", "browserTierFilter")
        local saved = getTiers()
        if saved and saved.__none then
            self._selectedTiers = {}
        elseif saved and next(saved) then
            local restored = {}
            for k, v in pairs(saved) do if v then restored[k] = true end end
            self._selectedTiers = next(restored) and restored or nil
        end
    end

    local availBands = {}
    for _, band in ipairs(SKILL_TIER_BANDS) do
        if band.cap <= clientMaxSkill then availBands[#availBands + 1] = band end
    end

    -- Band rows first, then Select All / Clear All at the bottom of the menu.
    local tierItems = {}
    for _, band in ipairs(availBands) do
        tierItems[#tierItems + 1] = { value = band.key, text = TierBandLabel(band) }
    end
    tierItems[#tierItems + 1] = { value = TIER_SELECT_ALL, text = L["FilterSelectAll"], action = true }
    tierItems[#tierItems + 1] = { value = TIER_CLEAR_ALL,  text = L["FilterClearAll"],  action = true }

    -- nil _selectedTiers means every band is on (the canonical "all").
    local function tierOn(key)
        return (self._selectedTiers == nil) or (self._selectedTiers[key] == true)
    end
    local function tierChanged()
        self:PersistTierFilter()
        self:RefreshList()
    end

    addon.GUI.ToolbarDropdown(self, "tier", toolbar, {
        label     = L["BrowserSkillTier"],
        width     = 180,
        multi     = true,
        items     = function() return tierItems end,
        isChecked = tierOn,
        -- Materialize the current effective set (nil = every available band on),
        -- flip the clicked band, then collapse "all ticked" back to nil.
        onToggle  = function(key, checked)
            local sel = {}
            for _, band in ipairs(availBands) do
                if tierOn(band.key) then sel[band.key] = true end
            end
            if checked then sel[key] = true else sel[key] = nil end
            local all = true
            for _, band in ipairs(availBands) do
                if not sel[band.key] then all = false; break end
            end
            -- NOT `all and nil or sel`: `true and nil` is nil, so that form
            -- always yields `sel`, and re-ticking every band never collapsed
            -- back to "all" (found by Tests/toolbar_spec.lua).
            if all then self._selectedTiers = nil else self._selectedTiers = sel end
            tierChanged()
        end,
        onAction  = function(key)
            -- Select All: all tiers shown (canonical nil). Clear All: nothing
            -- ticked, so only recipes with no known tier show.
            self._selectedTiers = (key == TIER_CLEAR_ALL) and {} or nil
            tierChanged()
        end,
        -- The ticked bands' names, as AceGUI's multiselect box showed them.
        text      = function()
            local names = {}
            for _, band in ipairs(availBands) do
                if tierOn(band.key) then names[#names + 1] = TierBandLabel(band) end
            end
            return table.concat(names, ", ")
        end,
        tipTitle  = L["BrowserSkillTierTip"],
        tipBody   = L["BrowserSkillTierDesc"],
    })

    local sp = AceGUI:Create("Label")
    sp:SetWidth(8)
    toolbar:AddChild(sp)

    -- Debounced 200ms, so only the value after the player pauses rebuilds the
    -- list. RefreshList rebuilds only the list, not this box, so the caret
    -- stays where it is while typing.
    addon.GUI.ToolbarSearch(toolbar, {
        width     = 220,
        aligned   = true,
        debounce  = 0.2,
        text      = self._searchText,
        onChanged = function(text)
            self._searchText = text
            self:RefreshList()
        end,
        tipTitle  = L["SearchPlaceholder"],
        tipBody   = L["CraftSearchDesc"],
    })

    local sp2 = AceGUI:Create("Label")
    sp2:SetWidth(8)
    toolbar:AddChild(sp2)

    -- The view: guild / mine, plus "Show Missing" while "Show all recipes" is
    -- on. The base pair comes from `UI.ScopeList`, shared with the Cooldowns
    -- tab; the Browser-only third mode is passed in as an extra. A mode the
    -- list no longer offers is never drawn as a blank row (MenuItems drops a
    -- key with no label), which is the bug an AceGUI order array once had here.
    local viewLabels, viewOrder = addon.UI.ScopeList(self._showAllRecipes and {
        { key = "missing", label = L["ViewMissing"] or "Show Missing" },
    } or nil)
    -- "missing" chosen, then "Show all recipes" turned off: back to "guild".
    if self._viewMode == "missing" and not self._showAllRecipes then
        self._viewMode = "guild"
    end
    local function redraw()
        C_Timer.After(0, function()
            if self._container then
                self._container:ReleaseChildren()
                self:Draw(self._container)
            end
        end)
    end
    addon.GUI.ToolbarDropdown(self, "view", toolbar, {
        aligned  = true,
        width    = 150,
        items    = function() return addon.GUI.MenuItems(viewLabels, viewOrder) end,
        value    = self._viewMode,
        onChange = function(value)
            self._viewMode       = value
            self._selectedProfs  = nil
            self._selectedProfId = 0
            self._selectedEntry  = nil
            redraw()
        end,
    })

    local sp3 = AceGUI:Create("Label"); sp3:SetWidth(8); toolbar:AddChild(sp3)

    -- "Show all recipes": every recipe in the shipped addon.recipeDB, ones
    -- nobody in the guild knows greyed out, so the gaps can be scanned. Also
    -- unlocks "Show Missing" in the view menu.
    addon.GUI.ToolbarCheckbox(self, "showAll", toolbar, {
        aligned  = true,
        width    = 170,
        label    = L["BrowserShowAllRecipes"] or "Show all recipes",
        get      = function() return self._showAllRecipes end,
        set      = function(value)
            self._showAllRecipes = value
            if not value and self._viewMode == "missing" then
                self._viewMode = "guild"
            end
            redraw()
        end,
        tipTitle = L["BrowserShowAllRecipes"] or "Show all recipes",
        tipBody  = L["BrowserShowAllRecipesDesc"]
            or ("Include every recipe in the shipped database, even ones nobody in the guild knows. "
                .. "Missing recipes render greyed out so officers can spot which skills the guild "
                .. "still needs to cover."),
    })

    local sp3b = AceGUI:Create("Label"); sp3b:SetWidth(8); toolbar:AddChild(sp3b)

    -- Scan AH button — kicks off a throttled scan over every reagent in
    -- the user's shopping list. After completion, reagent rows in the
    -- shopping list section AND the detail panel that have live AH
    -- listings get an [AH] button (gated on AH.GetListingsFor — same
    -- pattern as [Bank] gating on Bank.GetStock). Disabled when AH is
    -- closed; shows scan progress while running. Click during scan
    -- cancels. Mirrors the Missing Recipes tab's Scan AH button.
    addon.GUI.MakeScanAHButton({
        parent        = toolbar,
        tabName       = "browser",
        label         = L["BrowserScanAH"],
        progressLabel = L["BrowserScanAHProgress"],
        tooltipTitle  = L["BrowserScanAH"],
        tooltipDesc   = L["BrowserScanAHDesc"],
        noItemsError  = "Shopping list is empty — nothing to scan.",
        getItems      = function()
            local items, seen = {}, {}
            for _, ent in pairs(Ace.db.char.shoppingList or {}) do
                for _, r in ipairs((ent and ent.reagents) or {}) do
                    local id   = r.itemId
                    local name = r.name
                    if id and type(name) == "string" and name ~= "" and not seen[id] then
                        seen[id] = true
                        items[#items + 1] = { itemId = id, itemName = name }
                    end
                end
            end
            return items
        end,
        onRefresh     = function()
            if BrowserTab._slSection then
                BrowserTab:FillShoppingListSection(BrowserTab._slSection)
            end
            if BrowserTab._selectedEntry then
                BrowserTab:DrawDetail(BrowserTab._selectedEntry)
            end
        end,
    })

    -- ---- Shopping list (below toolbar) -------------------------------------
    if hasSL then
        local slSection = AceGUI:Create("InlineGroup")
        slSection:SetTitle("")
        slSection:SetLayout("List")
        slSection:SetFullWidth(true)
        slSection.noAutoHeight = true
        slSection:SetHeight(slCount * ROW_HEIGHT + 40)
        -- The list's host is handed back to UIParent when this InlineGroup is
        -- released (ParkList → AttachRawFrames), so it never rides the pooled
        -- widget into another addon's window -- the bleed players hit on TBC /
        -- Anniversary.
        container:AddChild(slSection)
        self._slSection = slSection
        self:FillShoppingListSection(slSection)
    end

    -- ---- Recipe list (left) and detail panel (right) ------------------------
    -- One full-height group holds both. The list is a RowList on a host the tab
    -- owns for the session (addon.GUI.ParkList); the detail panel is the tab's
    -- own raw frame, created once. Both are handed back to UIParent when the
    -- group is released (AttachRawFrames), so neither rides the pooled group
    -- into another addon's window. Neither is anchored to anything outside this
    -- group, which is what v1.0.6's "the list is drawn over the game world after
    -- opening Settings" came from: the old scroll was anchored to chrome that
    -- its own release had already detached.
    local section = AceGUI:Create("SimpleGroup")
    section:SetLayout("Fill")
    section:SetFullWidth(true)
    section:SetFullHeight(true)
    container:AddChild(section)
    self._listSection = section
    if addon.W then
        addon.W:OnWidgetRelease(section, "togpm:browserList", function()
            GameTooltip:Hide()
            if self._listSection == section then self._listSection = nil end
        end)
    end

    self:EnsureDetailPanel(section.content)
    local rp = self._detailOuter
    rp:SetParent(section.content)
    rp:SetWidth(DP_W)
    rp:ClearAllPoints()
    rp:SetPoint("TOPRIGHT",    section.content, "TOPRIGHT",    0, 0)
    rp:SetPoint("BOTTOMRIGHT", section.content, "BOTTOMRIGHT", 0, 0)
    rp:Show()
    if addon.W then addon.W:AttachRawFrames(section, rp) end

    if self._selectedEntry then
        self:DrawDetail(self._selectedEntry)
    else
        self:ClearDetail()
    end

    self:FillList()
end

-- ---------------------------------------------------------------------------
-- Shopping list helpers
-- ---------------------------------------------------------------------------

-- The shopping-list section may show at most this share of the tab's height;
-- past it the rows scroll inside the section instead of pushing the column
-- headers and the recipe list off the bottom of the window. Reported on
-- Discord 2026-08-28 (six Shadoweave recipes expanded, ~28 rows: the section
-- was taller than the tab and the recipe list drew below the frame).
local SL_MAX_SHARE = 0.4
local SL_MIN_ROWS  = 4
local SL_SLACK     = 2   -- pixels; see FillShoppingListSection
BrowserTab.SL_SLACK = SL_SLACK

-- Tallest the section's row area may be right now. Derived from the tab
-- container's live height so a taller window shows more rows; falls back to
-- a fixed row count before the first layout has given the container a size.
function BrowserTab:ShoppingListMaxHeight()
    local frame = self._container and self._container.frame
    local h = frame and frame.GetHeight and frame:GetHeight() or 0
    if h and h > 0 then
        return math.max(ROW_HEIGHT * SL_MIN_ROWS, math.floor(h * SL_MAX_SHARE))
    end
    return ROW_HEIGHT * 10
end

-- The shopping list's rows, flattened: one per recipe on the list, sorted by
-- name, and under an EXPANDED recipe one per reagent. A recipe row carries
-- `_exp` (true expanded, false collapsed) only when it has reagents to show,
-- which is what makes the list draw its +/- toggle there and nowhere else.
function BrowserTab:BuildShoppingRows()
    self._slExpanded = self._slExpanded or {}
    local recipes = {}
    for sid, entry in pairs(Ace.db.char.shoppingList) do
        recipes[#recipes + 1] = { sid = sid, entry = entry }
    end
    table.sort(recipes, function(a, b)
        local na = (a.entry and a.entry.name) or tostring(a.sid)
        local nb = (b.entry and b.entry.name) or tostring(b.sid)
        return na < nb
    end)
    local rows = {}
    for _, rec in ipairs(recipes) do
        local ent      = rec.entry
        local qty      = (ent and ent.quantity) or 1
        local reagents = (ent and ent.reagents) or {}
        local row = { kind = "recipe", sid = rec.sid, ent = ent, qty = qty }
        rows[#rows + 1] = row
        if #reagents > 0 then
            row._exp = self._slExpanded[rec.sid] and true or false
            if row._exp then
                for _, r in ipairs(reagents) do
                    rows[#rows + 1] = { kind = "reagent", sid = rec.sid, r = r, qty = qty, _indent = 1 }
                end
            end
        end
    end
    return rows
end

-- The shopping list's quantity controls, shared by the list's [-] [+] [x].
-- Each keeps the detail panel in step when it shows the same recipe.
function BrowserTab:ShoppingStep(sid, ent, delta)
    local bl = Ace.db.char.shoppingList
    if delta == nil then
        bl[sid] = nil
        self._slExpanded[sid] = nil
        Ace.db.char.shoppingAlerts[sid] = nil
    elseif delta < 0 then
        local cur = (bl[sid] and bl[sid].quantity) or 1
        if cur <= 1 then
            bl[sid] = nil
            self._slExpanded[sid] = nil
        else
            bl[sid].quantity = cur - 1
        end
    else
        local name = (ent and ent.name) or tostring(sid)
        if bl[sid] then
            bl[sid].quantity = (bl[sid].quantity or 1) + 1
            if ent then
                bl[sid].name     = ent.name     or bl[sid].name
                bl[sid].icon     = ent.icon     or bl[sid].icon
                bl[sid].itemLink = ent.itemLink or bl[sid].itemLink
                bl[sid].reagents = ent.reagents or bl[sid].reagents
            end
        else
            bl[sid] = { name = name, quantity = 1,
                        icon = ent and ent.icon, itemLink = ent and ent.itemLink,
                        reagents = ent and ent.reagents }
        end
    end
    if self._selectedEntry and self._selectedEntry.id == sid then
        self:DrawDetail(self._selectedEntry)
    end
    self:RefreshShoppingList()
end

-- A reagent row's bank / AH state, worked out the same way the detail panel's
-- reagent rows do.
local function reagentStock(r)
    local id   = ResolveReagentItemId(r)
    local ah   = id and addon.AH and addon.AH.GetListingsFor(id)
    return id,
           id and addon.Bank and addon.Bank.GetStock(id) > 0,
           ah and (ah.count or 0) > 0 and r.name and r.name ~= ""
end

local function isRecipe(e)  return e.kind == "recipe"  end

-- The small text buttons on a recipe row. `glyph` is the button's text.
local function recipeButton(key, glyph, onClick, tip)
    return { key = key, width = 14, button = true, sortable = false,
             show = isRecipe, text = function() return glyph end,
             tip = tip, onClick = onClick }
end

function BrowserTab:BuildShoppingList(host)
    return addon.W.RowList:New(host, {
        rowHeight      = ROW_HEIGHT,
        hoverHighlight = true,
        columns = {
            -- +/- on a recipe with reagents: shows or hides them.
            { key = "_exp", expander = true, width = 14, sortable = false,
              onToggle = function(e, open)
                  self._slExpanded[e.sid] = open or nil
                  self:RefreshShoppingList()
              end },
            { key = "_icon", width = 16, iconSize = 14, iconTexCoord = true, sortable = false,
              icon = function(e)
                  if e.kind == "recipe" then return e.ent and e.ent.icon end
                  local id = e.r.itemId
                  return id and id > 0 and select(10, addon.Item.GetInfo(id)) or nil
              end },
            -- Recipe: coloured by the CRAFTED item's quality, falling back to
            -- ItemDB's shipped quality when the link is not cached (most of the
            -- time on a fresh login), so pieces of one set do not render in
            -- different colours. Reagent: resolved at draw time -- this table is
            -- the one the shopping list PERSISTS, so a placeholder name here
            -- would otherwise survive a reload.
            { key = "name",
              format = function(_, e)
                  if e.kind == "reagent" then return addon:ResolveReagentName(e.r) end
                  local ent  = e.ent
                  local name = (ent and ent.name) or tostring(e.sid)
                  local hex  = addon.ItemLink and addon.ItemLink.QualityHex
                      and addon.ItemLink.QualityHex(ent and ent.itemLink, ent and ent.craftedItemId)
                  return hex and ("|c" .. hex .. name .. "|r") or name
              end },
            { key = "count", width = 44, align = "RIGHT", sortable = false,
              format = function(_, e)
                  if e.kind ~= "reagent" then return "" end
                  return "|cffffffff x" .. ((e.r.count or 1) * e.qty) .. "|r"
              end },
            { key = "bankBtn", width = 62, button = true, sortable = false, gapBefore = 4,
              show = function(e)
                  return e.kind == "reagent" and select(2, reagentStock(e.r))
              end,
              text = function(e) return addon.Bank.ButtonText(ResolveReagentItemId(e.r)) end,
              tip  = function(e)
                  local body = L["TooltipBankDescGeneric"]
                  local status = addon.Bank.StatusText(ResolveReagentItemId(e.r))
                  if status then body = body .. "\n\n" .. status end
                  return L["TooltipBankTitle"], body
              end,
              onClick = function(e)
                  addon.Bank.ShowRequestDialog(ResolveReagentItemId(e.r), e.r.name or "",
                      ResolveReagentItemLink(e.r))
              end },
            { key = "ahBtn", width = 36, button = true, sortable = false,
              show = function(e)
                  return e.kind == "reagent" and select(3, reagentStock(e.r))
              end,
              text = function() return "|cFF88CCFF[AH]|r" end,
              tip  = function() return L["TooltipAHTitle"], L["TooltipAHDescReagent"] end,
              onClick = function(e) addon.AH.SearchFor(e.r.name) end },
            -- The crafter-online alert for this recipe: gold when on.
            { key = "alert", width = 14, button = true, sortable = false, show = isRecipe,
              text = function(e)
                  return Ace.db.char.shoppingAlerts[e.sid] and "|cffFFD700!|r" or "|cff666666!|r"
              end,
              tip = function(e)
                  return Ace.db.char.shoppingAlerts[e.sid] and L["ShoppingAlertDisable"]
                      or L["ShoppingAlertEnable"]
              end,
              onClick = function(e)
                  local alerts = Ace.db.char.shoppingAlerts
                  alerts[e.sid] = (not alerts[e.sid]) or nil
                  if self._slList then self._slList:Refresh() end
              end },
            recipeButton("minus", "|cFFFFD100-|r", function(e) self:ShoppingStep(e.sid, e.ent, -1) end),
            { key = "qty", width = 22, align = "RIGHT", sortable = false,
              format = function(_, e) return e.kind == "recipe" and tostring(e.qty) or "" end },
            recipeButton("plus", "|cFFFFD100+|r", function(e) self:ShoppingStep(e.sid, e.ent, 1) end),
            recipeButton("remove", "|cFFFF4444x|r", function(e) self:ShoppingStep(e.sid, e.ent, nil) end),
        },
        onRowEnter = function(e, _, _, rowFrame) self:ShowShoppingTooltip(e, rowFrame) end,
        onRowLeave = function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end,
        -- A click anywhere on a recipe row with reagents opens or closes it,
        -- as the toggle does.
        onRowClick = function(e, _, _, button)
            if button ~= "LeftButton" or e._exp == nil then return end
            self._slExpanded[e.sid] = (not e._exp) or nil
            self:RefreshShoppingList()
        end,
    })
end

-- A recipe row shows its crafted item (or, for an enchant, which has none, the
-- recipe's spell: the shopping-list key IS the spell id). A reagent row shows
-- the reagent.
function BrowserTab:ShowShoppingTooltip(e, owner)
    if e.kind == "reagent" then
        addon.Tooltip.Owner(owner)
        if addon.ItemLink.SetItem(GameTooltip, ResolveReagentItemLink(e.r), ResolveReagentItemId(e.r)) then
            GameTooltip:Show()
        end
        return
    end
    local link = e.ent and (e.ent.itemLink or e.ent.recipeLink)
    if link then
        addon.Tooltip.Owner(owner)
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    elseif type(e.sid) == "number" then
        addon.Tooltip.Owner(owner)
        if SetSpellTooltip(GameTooltip, e.sid) then GameTooltip:Show() end
    end
end

-- Fill the shopping-list section. The list is a RowList on a host the tab owns
-- for the session (addon.GUI.ParkList), parked in the section and handed back
-- to UIParent when the section is released. The section is as tall as its
-- rows, up to ShoppingListMaxHeight; past that the list scrolls inside it.
function BrowserTab:FillShoppingListSection(container)
    if not addon.W then return end
    local rows = self:BuildShoppingRows()
    local rl = addon.GUI.ParkList(self, "_slList", container, function(host)
        return self:BuildShoppingList(host)
    end)
    -- Whole rows only, at the list's own (scaled) row height, and at least
    -- one, so the cap never cuts a row in half.
    local rowH    = rl.rowHeight or ROW_HEIGHT
    local maxRows = math.max(1, math.floor(self:ShoppingListMaxHeight() / rowH))
    local shown   = math.max(1, math.min(#rows, maxRows))
    -- 40 is the InlineGroup's own chrome (17 title + 3 border + 2 x 10 inset).
    -- The extra SL_SLACK keeps the row area from landing a fraction UNDER
    -- `shown` rows once the client snaps the anchors to whole pixels: the
    -- RowList floors height / rowHeight, so one recipe drew as zero rows and
    -- a scrollbar (operator, 2026-10-07: "i can't see the stuff on my
    -- shopping list anymore").
    container:SetHeight(shown * rowH + 40 + SL_SLACK)
    rl:SetData(rows, true)
end

function BrowserTab:RefreshShoppingList()
    if not self._container then return end
    if addon.ReagentTracker then addon.ReagentTracker:QueueRefresh() end

    if self._slSection then
        local bl    = Ace.db.char.shoppingList
        local hasSL = next(bl) ~= nil

        if hasSL then
            self:FillShoppingListSection(self._slSection)
            if self._container then self._container:DoLayout() end
        else
            self._slSection.frame:Hide()
            self._slSection = nil
            C_Timer.After(0, function()
                if self._container then
                    self._container:ReleaseChildren()
                    self:Draw(self._container)
                end
            end)
        end
    else
        C_Timer.After(0, function()
            if self._container then
                self._container:ReleaseChildren()
                self:Draw(self._container)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Recipe list helpers
-- ---------------------------------------------------------------------------

-- Persist the current skill-tier selection to the profile.
--   nil (all tiers)   → clear the saved value (the default).
--   {} (Clear All)    → store a { __none = true } marker so "nothing ticked"
--                       survives a reload and isn't confused with "all".
--   explicit set      → store the key→true table verbatim.
function BrowserTab:PersistTierFilter()
    local _, setTiers = addon.GUI.PersistentChoice("profile", "browserTierFilter")
    if self._selectedTiers == nil then
        setTiers(nil)
    elseif next(self._selectedTiers) == nil then
        setTiers({ __none = true })
    else
        local saved = {}
        for k in pairs(self._selectedTiers) do saved[k] = true end
        setTiers(saved)
    end
end

-- A filter or search change. The player expects the top of the new result
-- set, not whatever offset the previous list was scrolled to.
function BrowserTab:RefreshList()
    local section = self._listSection
    if not section then return end
    addon.GUI.ListScroll.Set("browser", 0)
    -- Drops a hint label a previous fill left; the list host is a raw frame
    -- and is not a child, so it stays attached.
    section:ReleaseChildren()
    self:FillList()
end

-- Cache of full (search-independent) lists, keyed by listCacheKey. Filled lazily
-- on a miss and pre-warmed in the background by :Warm(); FillList reads it then
-- applies the cheap search filter.
BrowserTab._listCache = BrowserTab._listCache or {}

-- Return the full list for a build — from cache, or built synchronously on a
-- miss (the warm hasn't reached this key yet). The warm runs the SAME
-- BuildFullList, just sliced across frames.
function BrowserTab:GetFullList(profId, viewMode, showAll)
    local key    = listCacheKey(profId, viewMode, showAll)
    local cached = self._listCache[key]
    if cached then return cached end
    -- A miss is the one place this tab can stall a frame the player is waiting
    -- on, so it is timed, with the tooltip-scrape share broken out: that share
    -- is the client's cost and the only part the offline suite cannot measure.
    local P = addon.Perf
    local t0, scrape0, n0 = P.now(), P.scrapeMs, P.scrapeN
    local full = BuildFullList(profId, viewMode, { showAll = showAll })
    P.mark("Professions list build (synchronous, cache miss)", P.now() - t0,
        ("%d rows, key %s; %d tooltip scrapes = %.0f ms of it"):format(
            #full, tostring(key), P.scrapeN - n0, P.scrapeMs - scrape0))
    self._listCache[key] = full
    return full
end

-- Wipe the entire list cache. Call when guild data is removed wholesale — e.g.
-- the Settings "Purge all guild data" / "Purge my character data" buttons — so a
-- subsequent Draw rebuilds from the now-empty DB on a cache miss instead of
-- re-rendering stale pre-purge entries. (Ongoing sync UPDATES go through Warm(),
-- which overwrites keys in place so the open tab never blanks mid-rewarm; a purge
-- is destructive, so clearing — and thus blanking to the real empty state — is
-- the correct behavior here.)
function BrowserTab:InvalidateCache()
    self._listCache = {}
end

-- Pre-warm the cache in the background (invisible, chunked via addon.Warmer) so
-- opening the tab — and switching professions within it — is instant. Warms the
-- default guild view for All Professions plus each profession the guild has data
-- for. Safe to re-run (debounced) on data change: each coroutine overwrites its
-- cache entry in place, so the previous list keeps serving until the rebuild
-- finishes — never a blank/jarring moment.
function BrowserTab:Warm()
    local gdb = GetGuildDb()
    if not gdb then return end

    -- A full build is sliced across frames (BuildFullList yields), so on a busy
    -- guild it can take longer than the rewarm interval. DON'T Clear + restart an
    -- in-flight build — that's why the cache never caught up during continuous
    -- sync: every rewarm killed the running build before it finished, so it only
    -- completed in a quiet moment like /reload. Instead, if a build is already
    -- running, mark it dirty and let it finish; the completion sentinel re-warms
    -- exactly once so the cache ends up current without piling up or restarting.
    if self._warmInFlight then
        self._warmDirty = true
        addon:DebugPrint("BrowserTab:Warm — build in flight; marked dirty")
        return
    end
    self._warmInFlight = true
    self._warmDirty    = false
    addon:DebugPrint("BrowserTab:Warm — starting build")

    addon.Warmer:Clear()   -- belt-and-suspenders; nothing of ours should be queued
    self._listCache = self._listCache or {}
    local cache = self._listCache
    local viewMode, showAll = "guild", false

    local function queue(profId)
        addon.Warmer:Queue(function()
            cache[listCacheKey(profId, viewMode, showAll)] =
                BuildFullList(profId, viewMode, { showAll = showAll })
            -- Re-render ONLY when the profession we just (re)built is the exact view
            -- currently on screen. Refreshing after EVERY profession made a background
            -- warm of N professions fire N full tab rebuilds (ReleaseChildren +
            -- DrawTab — every dropdown/toolbar/pool) back-to-back while you were
            -- looking at one of them: THAT is the Professions-tab freeze (each build
            -- itself is ~0 ms; the rebuild storm is the hang). The viewed profession
            -- still updates live; the other N-1 land silently in the cache and appear
            -- instantly when you switch to them. Gated to an exact key match so the
            -- refresh is always a cache HIT (never a fresh synchronous build).
            if addon.MainWindow and addon.MainWindow.QueueRefresh
               and addon.MainWindow.activeTab == "browser"
               and self._selectedProfId == profId
               and self._viewMode == viewMode
               and (self._showAllRecipes and true or false) == showAll then
                addon.MainWindow:QueueRefresh()
            end
        end)
    end

    -- Queue the most-likely-first views FIRST so they're ready soonest:
    -- All Professions (the default), then the saved profession filter if set.
    local queued = {}
    queue(0); queued[0] = true
    local getProfFilter = addon.GUI.PersistentChoice("profile", "savedProfFilter", 0)
    local saved = Ace.db.profile.persistProfFilter and getProfFilter()
    if saved and saved ~= 0 and not queued[saved] then queue(saved); queued[saved] = true end
    -- Then each profession the guild has data for, so switching is instant too.
    for profId in pairs(gdb.recipes or {}) do
        if not queued[profId] then queue(profId); queued[profId] = true end
    end

    -- Completion sentinel: runs after every profession above finishes. Releases
    -- the in-flight flag and, if more guild data arrived mid-build, kicks off
    -- exactly one more build so the cache converges on the latest gdb.
    addon.Warmer:Queue(function()
        self._warmInFlight = false
        if self._warmDirty then
            addon:DebugPrint("BrowserTab:Warm — build complete (dirty -> re-warm)")
            self._warmDirty = false
            self:Warm()
        else
            addon:DebugPrint("BrowserTab:Warm — build complete")
        end
    end)
end

function BrowserTab:FillList()
    local section = self._listSection
    if not section then return end
    -- A fill that ends on a hint label must not leave the previous list
    -- showing under it; ParkList shows the host again when there are rows.
    if self._rowListHost then self._rowListHost:Hide() end
    self._recipes = nil

    if not self._selectedProfId then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["SelectProfHint"])
        lbl:SetFullWidth(true)
        section:AddChild(lbl)
        return
    end

    -- Get the full (search-independent) list from cache — pre-warmed in the
    -- background, or built on demand on a miss — then apply the cheap search
    -- filter. Searching never rebuilds; it just re-filters this cached list.
    local full    = self:GetFullList(self._selectedProfId, self._viewMode, self._showAllRecipes)
    local recipes = FilterTiers(FilterList(full, self._searchText), self._selectedTiers)
    local _crafters = 0
    for _, e in ipairs(full) do _crafters = _crafters + (e.crafters and #e.crafters or 0) end
    addon:DebugPrint("BrowserTab:FillList — prof=", self._selectedProfId,
        "fullList=", #full, "afterSearch=", #recipes, "totalCrafters=", _crafters)
    if #recipes == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(self._searchText ~= "" and L["NoMatchingRecipes"] or L["NoDataYet"])
        lbl:SetFullWidth(true)
        section:AddChild(lbl)
        return
    end

    self._recipes = recipes

    if addon.W then
        local rl = addon.GUI.ParkList(self, "_rowList", section, function(host)
            return self:BuildRowList(host)
        end)
        -- ParkList fills the group; the list takes the part left of the
        -- detail panel. Both are anchored inside this group only.
        local host = self._rowListHost
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT",     section.content,   "TOPLEFT",    0,       0)
        host:SetPoint("BOTTOMRIGHT", self._detailOuter, "BOTTOMLEFT", -DP_GAP, 0)
        -- Keep the player's place across the rebuilds a guild-data refresh
        -- causes. Read before SetData, whose scroll-to-top is reported too.
        local saved = addon.GUI.ListScroll.Get("browser")
        rl:SetData(recipes)
        rl:SetScrollOffset(saved)
        self:SyncListSelection()
    end

    -- If TOGBankClassic is loaded but not yet initialized (Info is nil on first
    -- login before GUILD_RANKS_UPDATE fires), watch for it and refresh bank buttons.
    if _G["TOGBankClassic_Guild"] and not _G["TOGBankClassic_Guild"].Info
       and not self._bankRefreshPending then
        self._bankRefreshPending = true
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("GUILD_RANKS_UPDATE")
        watcher:SetScript("OnEvent", function(f)
            f:UnregisterEvent("GUILD_RANKS_UPDATE")
            f:SetScript("OnEvent", nil)
            C_Timer.After(0.5, function()
                self._bankRefreshPending = nil
                if self._rowList then self._rowList:Refresh() end
                -- Bank buttons live in the detail panel; redraw it too.
                if self._selectedEntry then self:DrawDetail(self._selectedEntry) end
                -- Refresh shopping list bank buttons as well.
                if self._slSection then self:FillShoppingListSection(self._slSection) end
            end)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- The recipe list: a LibAceGUIWidgets RowList (MINOR 36)
-- ---------------------------------------------------------------------------
-- It draws only the visible rows and reuses its row frames for the session,
-- which is what the 35-frame pool did by hand up to v1.1.3, and it draws the
-- header, banding, hover highlight, selection tint and scrollbar.

-- As many crafter names as `width` allows, then a greyed "+N" for the rest,
-- instead of a fixed two. `width` and `measure` are the list's own: the cell's
-- live width, and the rendered width of a string in the cell's font -- so the
-- count follows the window as it is dragged. Always at least one name (the cell
-- clips it when even that overflows). Before the first layout there is no
-- width yet, and it falls back to the two-name summary.
local function fitCrafterText(crafters, width, measure, colOnline, colOffline, colYou)
    local total = crafters and #crafters or 0
    if total == 0 then return "" end
    local names = {}
    for ci = 1, total do
        local c   = crafters[ci]
        local col = c.isYou and colYou or (c.online and colOnline or colOffline)
        names[ci] = col .. c.name .. "|r"
    end
    local function suffix(n)
        return (n < total) and (" |cffaaaaaa+" .. (total - n) .. "|r") or ""
    end
    if not (measure and width and width > 1) then
        local n = math.min(2, total)
        return table.concat(names, ", ", 1, n) .. suffix(n)
    end
    -- Adding a name grows the rendered width, so the first overflow is the
    -- stopping point. The name list is extended one name at a time rather than
    -- re-joined per step: a recipe hundreds of crafters know, in a cell wide
    -- enough to measure many of them, made the re-join quadratic per row.
    local shown = names[1]
    local best  = shown .. suffix(1)
    for n = 2, total do
        shown = shown .. ", " .. names[n]
        local candidate = shown .. suffix(n)
        if measure(candidate) > width then break end
        best = candidate
    end
    return best
end
BrowserTab._fitCrafterText = fitCrafterText   -- test seam, see above

function BrowserTab:BuildRowList(host)
    return addon.W.RowList:New(host, {
        rowHeight      = ROW_HEIGHT,
        hoverHighlight = true,
        -- Rows arrive sorted by name (BuildFullList); the headers explain the
        -- columns and do not re-sort.
        onScroll       = function(_, offset) addon.GUI.ListScroll.Set("browser", offset) end,
        columns = {
            { key = "_icon", width = 18, iconSize = 14, iconTexCoord = true, sortable = false,
              icon = function(e) return e.icon end },
            -- Coloured by the CRAFTED item's quality, resolved through ItemDB
            -- when the link is not cached. Reading entry.itemLink alone made the
            -- colour depend on what the client happened to have seen, so one
            -- armour set could render its pieces in different colours.
            { key = "name", header = "Recipes", width = 160, sortable = false,
              headerTip = L["TooltipRecipeDesc"],
              format = function(_, e)
                  local hex = addon.ItemLink and addon.ItemLink.QualityHex
                      and addon.ItemLink.QualityHex(e.itemLink, e.craftedItemId)
                  local name = hex and ("|c" .. hex .. e.name .. "|r") or e.name
                  -- "(unconfirmed)" when the recipe may not exist in this game.
                  if e.unconfirmed then name = name .. addon.ItemLink.UnconfirmedRowSuffix(true) end
                  return name
              end },
            { key = "crafters", header = L["CraftersColHeader"], sortable = false,
              headerTip = L["TooltipCraftersDesc"],
              format = function(_, e, width, measure)
                  return fitCrafterText(e.crafters, width, measure,
                      "|c" .. (addon.ColorOnline  or "ffffffff"),
                      "|c" .. (addon.ColorOffline or "ffaaaaaa"),
                      "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF"))
              end },
            -- [Bank]: the crafted item itself has bank stock. Keyed by
            -- craftedItemId -- entry.id is the recipe's spell id, and asking the
            -- bank about it asks about whatever item shares that number.
            { key = "bankBtn", width = 60, button = true, sortable = false,
              show = function(e)
                  return e.craftedItemId and addon.Bank and addon.Bank.GetStock(e.craftedItemId) > 0
              end,
              text = function(e) return addon.Bank.ButtonText(e.craftedItemId) end,
              tip  = function(e)
                  local body = L["TooltipBankDescGeneric"]
                  local status = addon.Bank.StatusText(e.craftedItemId)
                  if status then body = body .. "\n\n" .. status end
                  return L["TooltipBankTitle"], body
              end,
              onClick = function(e)
                  addon.Bank.ShowRequestDialog(e.craftedItemId, e.name or "", e.itemLink)
              end },
        },
        onRowEnter = function(e, _, _, rowFrame) self:ShowRowTooltip(e, rowFrame) end,
        onRowLeave = function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end,
        onRowClick = function(e, _, _, button) self:ClickRow(e, button) end,
    })
end

-- A left click shows the recipe in the detail panel. A modified click inserts
-- the recipe link into chat instead: ResolveRecipeLink falls back through
-- itemLink → recipeLink → GetItemInfo(craftedItemId) → GetSpellLink →
-- synthetic "spell:<id>", so the click produces a link even for a
-- trainer-taught recipe whose entry has no link cached.
function BrowserTab:ClickRow(entry, button)
    if button ~= "LeftButton" or not entry then return end
    if addon.ItemLink.Click(ResolveRecipeLink(entry)) then return end
    self:DrawDetail(entry)
end

-- The list's selection tint follows the recipe in the detail panel. Matched by
-- id: the cached list is rebuilt by a guild-data rewarm, so the selected entry
-- is often an equal-looking table from the previous build.
function BrowserTab:SyncListSelection()
    local rl = self._rowList
    if not rl then return end
    local sel = self._selectedEntry
    rl:SetSelected(sel and function(e) return e.id == sel.id end or nil)
end

-- The row tooltip. Re-run by ItemLink.BeginHover when the compare modifier
-- changes while the row is hovered -- see the branches that hand it a rebuild
-- callback.
function BrowserTab:ShowRowTooltip(entry, owner)
    if not entry then return end
    local function renderRowTooltip() self:ShowRowTooltip(entry, owner) end
    addon.Tooltip.Owner(owner)

    -- The CRAFTED item is what a player wants compared against their
    -- gear — `recipeLink` is the recipe scroll, which equips nothing.
    local craftedLink = (type(entry.itemLink) == "string"
                         and entry.itemLink:find("|Hitem:")) and entry.itemLink or nil

    -- Two ways to end up on the real item tooltip: the player turned
    -- the setting on, or they are holding the compare modifier right
    -- now. The second matters because the curated tooltip below is
    -- assembled from AddLine calls and carries no item, so a comparison
    -- has nothing to attach to; swapping to the real tooltip for as
    -- long as the key is held is what makes hold-to-compare work here
    -- at all, and it returns to the trimmed version on release.
    if craftedLink and addon.ItemLink.WantsCompare() then
        addon.ItemLink.SetItem(GameTooltip, craftedLink)
        AppendBrandTooltipLines(entry)
        GameTooltip:Show()
        addon.ItemLink.BeginHover(GameTooltip, renderRowTooltip)
        return
    end

    -- THE REAL RECIPE TOOLTIP, where the game has one to give.
    -- RecipeTooltipSource answers "item" for the ~65% of recipes with a
    -- genuine teaching scroll ("Plans: Barbaric Shoulders"). That tooltip
    -- natively embeds the crafted item AND lets other addons'
    -- OnTooltipSetItem hooks contribute -- which is the whole reason a
    -- chat link looked richer than our own list.
    --
    -- The link comes from LibItemDB SYNCHRONOUSLY. Deliberately not
    -- GetItemInfo: a cold scroll's async cache-fill fires
    -- GET_ITEM_INFO_RECEIVED, and that refresh storm is what crept the
    -- Missing Recipes list. Falls through to the scroll-SHAPED tooltip
    -- below when no link is cached, rather than showing an empty one.
    local kind, teachingId = addon.ItemLink.RecipeTooltipSource(entry.profId, entry.id)
    if kind == "item" then
        local idb = addon:GetItemDB()
        local scrollLink = idb and idb.GetLink and idb:GetLink(teachingId)
        if scrollLink then
            GameTooltip:SetHyperlink(scrollLink)
            AppendBrandTooltipLines(entry)
            GameTooltip:Show()
            addon.ItemLink.BeginHover(GameTooltip, renderRowTooltip)
            return
        end
    end

    -- Only use recipeLink if it is a real item link; enchanting stores
    -- enchant:SPELLID here which produces an unhelpful tooltip.
    if entry.recipeLink and entry.recipeLink:find("|Hitem:") then
        GameTooltip:SetHyperlink(entry.recipeLink)
        addon.ItemLink.BeginHover(GameTooltip, renderRowTooltip)
    elseif entry.reagents and #entry.reagents > 0 then
        local parts = {}
        for _, r in ipairs(entry.reagents) do
            table.insert(parts, addon:ResolveReagentName(r) .. " (" .. r.count .. ")")
        end
        local reagentLine = (SPELL_REAGENTS or "Reagents:") .. " " .. table.concat(parts, ", ")
        -- Titled like the scroll the game does not have, so the list has
        -- no visible seam where real scrolls run out -- a third of every
        -- profession. Prefix is LibItemDB's localized, derived one.
        local header, requires, useText, metReq = addon.ItemLink.ScrollHeader(
            entry.profId, entry.id, entry.name, entry.profName)
        GameTooltip:ClearLines()
        -- ⚠ THE NAME IS DELIBERATELY *NOT* WRAPPED, and it is the only
        -- line in this addon that isn't. It is the line the game lets
        -- SET the frame width, exactly as Blizzard's own item tooltip
        -- does -- an item's name is never wrapped there.
        --
        -- Wrapping it was a real, observed regression: with every line
        -- opted into the preset, NOTHING claimed a natural width, so the
        -- frame collapsed to the bare preset and came out NARROWER than
        -- the game's own tooltip for the same item. "Schematic: Advanced
        -- Target Dummy" broke onto two lines, which the game does not
        -- do. The preset is a MINIMUM the long lines wrap to, not the
        -- width every tooltip ends up at.
        --
        -- So the rule is: the title sizes the frame, everything else
        -- wraps to the preset -- ours by passing the flag, third
        -- parties' by `ItemLink.WithWrappedLines`. Enumerated in
        -- `Tests/tooltipwrapflag_spec.lua`'s TITLE_EXEMPT so a second
        -- unwrapped line still fails the sweep.
        GameTooltip:AddLine("|cffffff00" .. (header or entry.name) .. "|r")
        if requires then
            -- Red when this character cannot meet it, exactly as the
            -- game colours an unmet requirement. Without this the line
            -- reads as satisfied whether or not it is, which is the
            -- one thing it exists to tell you.
            if metReq == false then
                GameTooltip:AddLine(requires, 1, 0.13, 0.13, true)
            else
                GameTooltip:AddLine(requires, 1, 1, 1, true)
            end
        end
        -- "Already known", red, between the requirement and the Use
        -- line — where the game's scroll puts it. Keyed on the `isYou`
        -- crafter, which only THIS character gets (alts are tagged
        -- "You (Altname)" without it), matching the game: a scroll is
        -- "already known" to the character reading it, not to the
        -- account. ITEM_SPELL_KNOWN is Blizzard's localized string.
        local knownByMe = false
        for _, crafter in ipairs(entry.crafters or {}) do
            if crafter.isYou then knownByMe = true break end
        end
        if knownByMe then
            GameTooltip:AddLine(_G.ITEM_SPELL_KNOWN or "Already known", 1, 0.13, 0.13, true)
        end
        -- "Use: Teaches you how to craft X." — ordered directly under
        -- the requirement, which is where the game's scroll puts it.
        -- ITEM_SPELL_TRIGGER_ONUSE is Blizzard's own localized "Use:",
        -- so this reads correctly in every client language; the stored
        -- sentence carries only the verb phrase.
        if useText then
            local usePrefix = _G.ITEM_SPELL_TRIGGER_ONUSE
            GameTooltip:AddLine(
                usePrefix and (usePrefix .. " " .. useText) or useText,
                1, 1, 1, true)
        end
        GameTooltip:AddLine(reagentLine, 1, 1, 1, true)
        -- Only scrape crafted-item tooltip for real item links (not enchant:).
        if type(entry.itemLink) == "string" and entry.itemLink:find("|Hitem:") then
            local scraper = GetItemScraper()
            scraper:ClearLines()
            scraper:SetHyperlink(entry.itemLink)
            local n = scraper:NumLines()
            if n > 1 then
                GameTooltip:AddLine(" ")
                for li = 1, n do
                    local lt = _G["TOGPMItemScraperTextLeft"  .. li]
                    local rt = _G["TOGPMItemScraperTextRight" .. li]
                    local lStr = (lt and lt:GetText()) or ""
                    local rStr = (rt and rt:GetText()) or ""
                    -- Drop the crafted item's own "Requires <Prof> (N)"
                    -- when it repeats the line we already put at the
                    -- top. They are different facts wearing identical
                    -- text -- ours is the skill to LEARN the recipe,
                    -- the item's is the skill to USE what it makes --
                    -- and printing both just looks like a bug.
                    if requires and lStr == requires then
                        lStr, rStr = "", ""
                    end
                    if lStr ~= "" or rStr ~= "" then
                        local lr, lg, lb = 1, 1, 1
                        local rr, rg, rb = 1, 1, 1
                        if lt then lr, lg, lb = lt:GetTextColor() end
                        if rt then rr, rg, rb = rt:GetTextColor() end
                        if rStr ~= "" then
                            -- ⚠ THIS BRANCH CANNOT WRAP. `AddDoubleLine`
                            -- has no wrap parameter -- its eight arguments
                            -- are two strings and six colour components --
                            -- so a scraped line with both halves is
                            -- exempt from the preset by construction, and
                            -- a long left half here WILL widen the
                            -- tooltip. Enumerated in
                            -- `Tests/tooltipwrapflag_spec.lua`'s
                            -- DOUBLELINE_EXEMPT so a fourth site fails.
                            -- Audit finding 18.
                            --
                            -- The branch is chosen on whether right-hand
                            -- text EXISTS, not on whether the line is
                            -- short, so this is not a "short lines only"
                            -- path.
                            GameTooltip:AddDoubleLine(lStr, rStr, lr, lg, lb, rr, rg, rb)
                        else
                            -- wrapText=true so long item lines (e.g. a flask's verbose
                            -- "Use:" text) wrap instead of stretching the tooltip across
                            -- the screen.
                            GameTooltip:AddLine(lStr, lr, lg, lb, true)
                        end
                    end
                end
            end
        end
        -- Custom-built tooltip: add the brand-colored crafters + IDs
        -- lines as the LAST content so they sit at the bottom. The
        -- conditional inside AppendBrandTooltipLines handles the
        -- crafted-item branch (no crafters line for enchants, which
        -- produce no item).
        AppendBrandTooltipLines(entry)
        -- Everything the OTHER addons would have added if this tooltip
        -- carried an item. It does not — it is AddLine calls — so
        -- OnTooltipSetItem never fires and ATT / TOGBankClassic / TSM
        -- are all silently absent here while appearing on the real
        -- scroll tooltip one row up. This is what made the two look
        -- like different addons.
        addon.ItemLink.AppendIntegrations(
            GameTooltip, entry.spellId or entry.id, entry.craftedItemId)
        GameTooltip:Show()
        -- Keep listening even though this tooltip cannot itself
        -- compare: pressing the modifier re-runs this function, which
        -- takes the branch above and swaps to the real item tooltip.
        addon.ItemLink.BeginHover(GameTooltip, renderRowTooltip)
        return
    end

    -- Tracks whether the tooltip ended up carrying a real ITEM. Only a
    -- real item makes OnTooltipSetItem fire, and that hook is how ATT /
    -- TOGBankClassic / TSM attach — so it decides whether we add their
    -- lines ourselves below or would be duplicating theirs.
    local hasItem = false
    if type(entry.itemLink) == "string" and entry.itemLink:find("|Hitem:") then
        addon.ItemLink.SetItem(GameTooltip, entry.itemLink)
        hasItem = true
    elseif not SetSpellTooltip(GameTooltip, entry.spellId or entry.id) then
        -- No link, no spell id: name-only so the hover still says
        -- something. Never "item:<entry.id>" — entry.id is a spell id
        -- and that lookup lands on an unrelated item.
        -- wrap = TRUE. The sixth argument is `wrap` and it defaults to
        -- false (FrameAPITooltipDocumentation.lua:72). Passing the flag
        -- opts the line into the client's own PRESET wrap width -- the
        -- engine-side figure Blizzard sizes ability tooltips to. It is
        -- not exposed as a number and does not need to be: the preset
        -- scales with each player's client, so the flag gives every user
        -- the right width with nothing calculated.
        GameTooltip:SetText(entry.name or "", 1, 1, 1, 1, true)
    end
    -- For SetHyperlink branches the global tooltip hook will fire on
    -- Show() and add its own brand crafters+IDs (the hook dedups via
    -- _togpmAppended). For SetSpellByID branches the hook does NOT
    -- fire (no item context), so this manual call is the only way
    -- spell-only recipes get an IDs line. The dedup means we don't
    -- double-up on SetHyperlink branches — the manual call wins,
    -- the hook's later call early-returns.
    AppendBrandTooltipLines(entry)
    -- Same reasoning as the curated branch, but only where the tooltip
    -- has NO item: a SetHyperlink tooltip already gets ATT /
    -- TOGBankClassic / TSM from their own OnTooltipSetItem hooks, and
    -- adding ours on top would print every block twice.
    if not hasItem then
        addon.ItemLink.AppendIntegrations(
            GameTooltip, entry.spellId or entry.id, entry.craftedItemId)
    end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Detail panel (right column)
-- ---------------------------------------------------------------------------

-- Lazily create all detail-panel sub-frames the first time; subsequent Draw()
-- calls just re-parent the outer frame to the new container.content.
function BrowserTab:EnsureDetailPanel(parent)
    if self._detailOuter then return end

    local rp = CreateFrame("Frame", nil, parent)
    rp:SetWidth(DP_W)
    self._detailOuter = rp

    -- Subtle backdrop to visually separate the panel from the list.
    if rp.SetBackdrop then
        rp:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, tileSize = 1, edgeSize = 8,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        rp:SetBackdropColor(0, 0, 0, 0.22)
        rp:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end

    -- Placeholder text shown when no recipe is selected.
    local ph = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ph:SetPoint("CENTER", rp, "CENTER", 0, 0)
    ph:SetText("|cffaaaaaa>> Select a recipe|r")
    ph:SetJustifyH("CENTER")
    self._dpPH = ph

    -- The panel's body: the header and shopping controls at the top, and the
    -- reagents / Known By list (a library RowList, which scrolls itself) filling
    -- the rest. Hidden while the placeholder shows.
    local content = CreateFrame("Frame", nil, rp)
    content:SetPoint("TOPLEFT",     rp, "TOPLEFT",     DP_PAD, -DP_PAD)
    content:SetPoint("BOTTOMRIGHT", rp, "BOTTOMRIGHT", -DP_PAD, DP_PAD)
    content:Hide()
    self._dpBody = content

    -- ── Persistent header widgets ──────────────────────────────────────────

    -- Button wrapper so the icon+name row can show an item tooltip and
    -- accept shift-click to insert the item link into chat.
    local hdrBtn = CreateFrame("Button", nil, content)
    hdrBtn:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, 0)
    hdrBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    hdrBtn:SetHeight(DP_ICON)
    hdrBtn:RegisterForClicks("AnyUp")
    self._dpHdrBtn = hdrBtn

    local dpIcon = hdrBtn:CreateTexture(nil, "ARTWORK")
    dpIcon:SetSize(DP_ICON, DP_ICON)
    dpIcon:SetPoint("TOPLEFT", hdrBtn, "TOPLEFT", 0, 0)
    dpIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    self._dpIcon = dpIcon

    local dpName = hdrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dpName:SetPoint("TOPLEFT",  dpIcon, "TOPRIGHT", 4, -2)
    dpName:SetPoint("TOPRIGHT", hdrBtn, "TOPRIGHT", 0, -2)
    dpName:SetWordWrap(true)
    dpName:SetJustifyH("LEFT")
    self._dpName = dpName

    -- Shopping list row (below the icon/name block)
    local shopRow = CreateFrame("Frame", nil, content)
    shopRow:SetHeight(DP_ROW)
    shopRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(DP_ICON + 4))
    shopRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(DP_ICON + 4))
    self._dpShopRow = shopRow

    local shopLbl = shopRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shopLbl:SetPoint("LEFT", shopRow, "LEFT", 0, 0)
    shopLbl:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Shopping List:|r")

    -- Controls right-justified: [x] at right edge, then [+] [qty] [-] leftward
    local dpRemove = CreateFrame("Button", nil, shopRow)
    dpRemove:SetSize(14, 14)
    dpRemove:SetPoint("RIGHT", shopRow, "RIGHT", 0, 0)
    local dpRemoveT = dpRemove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpRemoveT:SetAllPoints(); dpRemoveT:SetJustifyH("CENTER"); dpRemoveT:SetText("|cFFFF4444x|r")
    self._dpRemove = dpRemove

    local dpPlus = CreateFrame("Button", nil, shopRow)
    dpPlus:SetSize(14, 14)
    dpPlus:SetPoint("RIGHT", dpRemove, "LEFT", -4, 0)
    local dpPlusT = dpPlus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpPlusT:SetAllPoints(); dpPlusT:SetJustifyH("CENTER"); dpPlusT:SetText("|cFFFFD100+|r")
    self._dpPlus = dpPlus

    local dpQty = shopRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpQty:SetPoint("RIGHT", dpPlus, "LEFT", -4, 0)
    dpQty:SetWidth(20)
    dpQty:SetJustifyH("CENTER")
    self._dpQty = dpQty

    local dpMinus = CreateFrame("Button", nil, shopRow)
    dpMinus:SetSize(14, 14)
    dpMinus:SetPoint("RIGHT", dpQty, "LEFT", -4, 0)
    local dpMinusT = dpMinus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpMinusT:SetAllPoints(); dpMinusT:SetJustifyH("CENTER"); dpMinusT:SetText("|cFFFFD100-|r")
    self._dpMinus = dpMinus

    -- Reagents and Known By: one library RowList under the shopping row. Its
    -- host is a child of this panel, which the tab owns for the session, so the
    -- list's HookScripts never land on a pooled AceGUI frame.
    local host = CreateFrame("Frame", nil, content)
    host:SetPoint("TOPLEFT",     shopRow, "BOTTOMLEFT", 0, -4)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    self._dpListHost = host
    self._dpList = self:BuildDetailList(host)
end

-- The shopping-list quantity the reagent counts are multiplied by: the list's
-- own quantity, and never less than one, so a recipe that is not on the list
-- shows what one craft takes.
local function detailMultiplier(entryId)
    local sl = Ace.db.char.shoppingList[entryId]
    return math.max(1, (sl and sl.quantity) or 0)
end

-- The detail panel's reagents / Known By list. Rows are
--   { _header = "Reagents" | "Known By" }
--   { kind = "reagent", r = <reagent>, entryId = <recipe id> }
--   { kind = "crafter", c = <crafter> }
--   { kind = "none" }                      -- nobody is known to craft it
-- Reagent cells read the shopping-list quantity when drawn, so the +/- buttons
-- restate the counts with a Refresh.
function BrowserTab:BuildDetailList(host)
    local colorOnline  = function() return "|c" .. (addon.ColorOnline  or "ffffffff") end
    local colorOffline = function() return "|c" .. (addon.ColorOffline or "ffaaaaaa") end
    local colorYou     = function() return "|c" .. (addon.ColorYou or addon.BrandColor or "ffDA8CFF") end
    local function isReagent(e) return e.kind == "reagent" end
    return addon.W.RowList:New(host, {
        rowHeight      = DP_ROW,
        hoverHighlight = true,
        headerFont     = "GameFontNormalSmall",
        columns = {
            { key = "_icon", width = 14, iconSize = 12, iconTexCoord = true, sortable = false,
              icon = function(e)
                  if not isReagent(e) then return nil end
                  local id = ResolveReagentItemId(e.r)
                  return id and id > 0 and select(10, addon.Item.GetInfo(id)) or nil
              end },
            -- Reagent names are resolved at draw time: see addon:ResolveReagentName
            -- for why a name frozen at build time rendered as "Item #15417".
            { key = "name", sortable = false,
              format = function(_, e)
                  if e.kind == "reagent" then return addon:ResolveReagentName(e.r) end
                  if e.kind == "none" then return "|cffaaaaaa" .. L["NoDataYet"] .. "|r" end
                  if e.kind ~= "crafter" then return "" end
                  local c = e.c
                  local col = c.isYou and colorYou() or (c.online and colorOnline() or colorOffline())
                  return col .. c.name .. "|r"
              end },
            { key = "count", width = 40, align = "RIGHT", sortable = false,
              format = function(_, e)
                  if not isReagent(e) then return "" end
                  return "|cffffffff\195\151" .. (e.r.count or 1) * detailMultiplier(e.entryId) .. "|r"
              end },
            { key = "bankBtn", width = 56, button = true, sortable = false, gapBefore = 4,
              show = function(e) return isReagent(e) and select(2, reagentStock(e.r)) end,
              text = function(e) return addon.Bank.ButtonText(ResolveReagentItemId(e.r)) end,
              tip  = function(e)
                  local body = L["TooltipBankDescGeneric"]
                  local status = addon.Bank.StatusText(ResolveReagentItemId(e.r))
                  if status then body = body .. "\n\n" .. status end
                  return L["TooltipBankTitle"], body
              end,
              onClick = function(e)
                  addon.Bank.ShowRequestDialog(ResolveReagentItemId(e.r), e.r.name or "",
                      ResolveReagentItemLink(e.r))
              end },
            { key = "ahBtn", width = 32, button = true, sortable = false,
              show = function(e) return isReagent(e) and select(3, reagentStock(e.r)) end,
              text = function() return "|cFF88CCFF[AH]|r" end,
              tip  = function() return L["TooltipAHTitle"], L["TooltipAHDescReagent"] end,
              onClick = function(e) addon.AH.SearchFor(e.r.name) end },
        },
        onRowEnter = function(e, _, _, rowFrame)
            if isReagent(e) then
                local link, id = ResolveReagentItemLink(e.r), ResolveReagentItemId(e.r)
                if link or id then
                    addon.Tooltip.Owner(rowFrame)
                    if addon.ItemLink.SetItem(GameTooltip, link, id) then GameTooltip:Show() end
                end
            elseif e.kind == "crafter" and not e.c.isYou then
                addon.Tooltip.Owner(rowFrame)
                GameTooltip:SetText(e.c.name, 1, 1, 1, 1, true)
                GameTooltip:AddLine(L["TooltipWhisperRightClick"], 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end
        end,
        onRowLeave = function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end,
        -- Left-click a reagent: its link into chat (or the dressing room, per
        -- the player's bindings). Right-click a guildmate: whisper them.
        onRowClick = function(e, _, _, button, rowFrame)
            if isReagent(e) then
                if button == "LeftButton" then
                    addon.ItemLink.Click(ResolveReagentItemLink(e.r))
                end
            elseif e.kind == "crafter" and not e.c.isYou and button == "RightButton" then
                local charKey, shortName = e.c.charKey or e.c.name, e.c.name
                local openWhisper = addon.UI.OpenWhisper
                if Menu and Menu.CreateContextMenu then
                    Menu.CreateContextMenu(rowFrame, function(_, root)
                        root:CreateTitle(shortName)
                        root:CreateButton(shortName, function() openWhisper(charKey) end)
                    end)
                else
                    openWhisper(charKey)
                end
            end
        end,
    })
end

-- The list rows for one recipe: the Reagents heading and a row per reagent
-- (both left out when it takes none), then Known By and a row per crafter, or
-- one "no data yet" row.
function BrowserTab:DetailRows(entry)
    local rows = {}
    local reagents = entry.reagents or {}
    if #reagents > 0 then
        rows[#rows + 1] = { _header = L["CraftReagents"] }
        for _, r in ipairs(reagents) do
            rows[#rows + 1] = { kind = "reagent", r = r, entryId = entry.id }
        end
    end
    rows[#rows + 1] = { _header = L["DetailKnownBy"] }
    local crafters = entry.crafters or {}
    if #crafters == 0 then
        rows[#rows + 1] = { kind = "none" }
    end
    for _, c in ipairs(crafters) do
        rows[#rows + 1] = { kind = "crafter", c = c }
    end
    return rows
end

-- Populate the detail panel for the given recipe entry.
function BrowserTab:DrawDetail(entry)
    self:EnsureDetailPanel(
        self._container and self._container.content or UIParent)
    self._selectedEntry = entry
    self:SyncListSelection()

    self._dpPH:Hide()
    self._dpBody:Show()

    -- Header: icon + name
    self._dpIcon:SetTexture(entry.icon)
    local titleColor = type(entry.itemLink) == "string" and entry.itemLink:match("|c(ff%x%x%x%x%x%x)|H") or "ffffd100"
    -- The same "(unconfirmed)" the row shows, so selecting a recipe shown on a
    -- borrowed never-implemented flag does not drop the warning.
    local suffix = entry.unconfirmed and addon.ItemLink.UnconfirmedRowSuffix(true) or ""
    self._dpName:SetText("|c" .. titleColor .. entry.name .. "|r" .. suffix)

    -- Tooltip + shift-click to insert link on the header button.
    -- ResolveRecipeLink falls back through itemLink → recipeLink →
    -- GetItemInfo(craftedItemId) → GetSpellLink → synthetic "spell:<id>" so
    -- the click always produces a link. The previous behaviour bound NO
    -- click handler when both itemLink and recipeLink were missing,
    -- silently swallowing shift-clicks on trainer-taught recipes and on
    -- any stub-created entry where sync hadn't filled in a link yet.
    self._dpHdrBtn:SetScript("OnEnter", function()
        addon.Tooltip.Owner(self._dpHdrBtn)
        local link = ResolveRecipeLink(entry)
        local sid  = link and tonumber(link:match("|Hspell:(%d+)"))
        if link and link:find("|Hitem:") then
            GameTooltip:SetHyperlink(link)
        elseif not SetSpellTooltip(GameTooltip, sid or entry.spellId or entry.id) then
            -- wrap = true, same reason as the other name-only fallback in this
            -- file: the flag opts the line into the client's preset wrap width.
            GameTooltip:SetText(entry.name or "", 1, 1, 1, 1, true)
        end
        -- Brand crafters + IDs lines at the bottom — same helper used by
        -- the recipe row tooltip and the global item tooltip hook, so
        -- styling stays consistent across every TOGPM tooltip surface.
        AppendBrandTooltipLines(entry)
        GameTooltip:Show()
    end)
    self._dpHdrBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self._dpHdrBtn:SetScript("OnClick", function(_, btn)
        if btn == "LeftButton" then
            addon.ItemLink.Click(ResolveRecipeLink(entry))
        end
    end)

    -- Shopping list qty display and controls
    local function RefreshQty()
        local qty = (Ace.db.char.shoppingList[entry.id]
                    and Ace.db.char.shoppingList[entry.id].quantity) or 0
        self._dpQty:SetText(tostring(qty))
        -- The reagent counts read the quantity when drawn; redraw them.
        if self._dpList and self._selectedEntry and self._selectedEntry.id == entry.id then
            self._dpList:Refresh()
        end
    end
    RefreshQty()

    self._dpMinus:SetScript("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity = sl[entry.id].quantity - 1
            if sl[entry.id].quantity <= 0 then sl[entry.id] = nil end
        end
        RefreshQty()
        self:RefreshShoppingList()
    end)
    self._dpPlus:SetScript("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity    = sl[entry.id].quantity + 1
            sl[entry.id].name        = entry.name
            sl[entry.id].icon        = entry.icon
            sl[entry.id].itemLink    = entry.itemLink
            sl[entry.id].reagents    = entry.reagents
        else
            sl[entry.id] = { name = entry.name, quantity = 1,
                             icon = entry.icon, itemLink = entry.itemLink,
                             reagents = entry.reagents }
        end
        RefreshQty()
        self:RefreshShoppingList()
    end)
    self._dpRemove:SetScript("OnClick", function()
        Ace.db.char.shoppingList[entry.id] = nil
        RefreshQty()
        self:RefreshShoppingList()
    end)

    -- Reagents and Known By. A new recipe opens at the top of the list.
    self._dpList:SetData(self:DetailRows(entry))
end

-- Show the "select a recipe" placeholder.
function BrowserTab:ClearDetail()
    if not self._detailOuter then return end
    if self._dpBody then self._dpBody:Hide() end
    if self._dpPH  then self._dpPH:Show() end
    self._selectedEntry = nil
    self:SyncListSelection()
end

-- ---------------------------------------------------------------------------
-- AH callbacks
-- ---------------------------------------------------------------------------
-- Refresh the scan button label whenever the AH opens or closes (it
-- enables/disables based on AH availability), and refresh the shopping list
-- section + detail panel so [AH] buttons appear/disappear on reagent rows
-- as scan results arrive or get cleared (addon.AH wipes results on close).
-- Both callbacks early-out unless the browser tab is the active tab and
-- has its widgets built — cheap when the tab is closed.
-- (Removed: per-tab AH_OPEN_STATE_CHANGED / AH_SCAN_COMPLETE handlers.
-- The shared addon.GUI.MakeScanAHButton factory in GUI/SharedWidgets.lua
-- owns one global handler that refreshes the active tab's scan button
-- and runs the tab's onRefresh hook — for browser, that hook re-fills
-- the shopping list section + the detail panel.)

-- ---------------------------------------------------------------------------
-- Background cache warming
-- ---------------------------------------------------------------------------
-- Pre-build the recipe cache in the idle time after login so opening the
-- Professions tab (and searching within it) is instant, and re-warm — coalesced
-- — when guild/cross-guild data changes so the cache stays current without a
-- foreground rebuild. Both run through addon.Warmer, sliced across frames so
-- they never stutter. While a re-warm is in flight the previous cache keeps
-- serving, so the open tab never blanks. (Trade-off: the open tab can show data
-- up to ~one debounce stale; that's the cost of never hitching, which is the
-- behavior we want.)
do
    local rewarmTimer
    local burstStart          -- GetTime() of the first update since the last warm
    local DEBOUNCE = 5        -- coalesce a burst of updates into one rebuild
    local MAX_WAIT = 10       -- ...but never let continuous sync starve the rebuild
    local function fireWarm()
        rewarmTimer = nil
        burstStart  = nil
        BrowserTab:Warm()
    end
    local function scheduleRewarm()
        burstStart = burstStart or GetTime()
        if rewarmTimer then rewarmTimer:Cancel() end
        -- Trailing debounce, CAPPED by MAX_WAIT. The bug this fixes: the old code
        -- cancelled + rescheduled a fixed 10s timer on EVERY GUILD_DATA_UPDATED,
        -- so on an actively-syncing realm (updates arriving faster than the
        -- debounce) Warm() never fired at all — the recipe cache was never
        -- rebuilt, the Professions tab kept rendering the stale cache, and ONLY a
        -- /reload (which clears the cache) showed new data. Switching tabs didn't
        -- help because it just re-reads the same never-rebuilt cache. Capping the
        -- wait guarantees a rebuild lands even under continuous guild traffic.
        if GetTime() - burstStart >= MAX_WAIT then
            fireWarm()
        else
            rewarmTimer = C_Timer.NewTimer(DEBOUNCE, fireWarm)
        end
    end
    -- First warm a short while after load, once gdb + the roster have settled.
    C_Timer.After(8, function() BrowserTab:Warm() end)
    -- Re-warm on guild/cross-guild data changes (debounced, starvation-capped).
    -- The recipe-list cache is built only from crafter/alt data, so a cooldown-
    -- only sync can't change it — skip the rewarm when the change scope carries
    -- none of recipes / altgroups / roster. nil/unknown scope still rewarms (safe).
    --
    -- `roster` MUST rewarm even though it isn't recipe data: BuildFullList bakes
    -- each crafter's visibility verdict into the cache, and a cache built during
    -- the cold-start window (before LibGuildRoster is ready, when the gate hides
    -- nobody) contains rows for characters who have since left the guild. That
    -- poisoned cache is served for the rest of the session unless roster truth
    -- invalidates it — which is why an ex-member survived a reload. Note this
    -- runs regardless of whether the tab is on screen, on purpose: the background
    -- pre-warm is exactly what caches the unfiltered list.
    addon:RegisterCallback("GUILD_DATA_UPDATED", function(_event, _charKey, scopes)
        if type(scopes) == "table" and next(scopes)
           and not (scopes.recipes or scopes.altgroups or scopes.roster) then
            return
        end
        scheduleRewarm()
    end)

    -- (No WINDOW_RESIZED handler: the recipe list repaints itself when its
    -- host is resized, and the crafter column re-fits on every repaint.)

    -- Roster online/offline transitions flip crafter-online status, which
    -- BuildFullList bakes into the recipe-list cache (including the "an alt is
    -- online" logic) — so a redraw alone won't reflect it; the cached list must be
    -- rebuilt. Debounce roster events (login/logout bursts fire many at once) and,
    -- ONLY while the Professions tab is actually on screen, invalidate + refresh so
    -- someone going offline/online shows within ~2s instead of waiting for the next
    -- data change or a /reload. Gating on visible keeps roster churn from wiping the
    -- background pre-warm while the tab is closed.
    local rosterRefreshTimer
    local function browserVisible()
        local mw = addon.MainWindow
        return mw and mw.activeTab == "browser"
            and mw.frame and mw.frame.frame and mw.frame.frame:IsShown()
    end
    local function scheduleRosterRefresh()
        if rosterRefreshTimer or not browserVisible() then return end
        rosterRefreshTimer = C_Timer.NewTimer(2, function()
            rosterRefreshTimer = nil
            if not browserVisible() then return end
            BrowserTab:InvalidateCache()
            if addon.MainWindow.QueueRefresh then addon.MainWindow:QueueRefresh() end
        end)
    end
    -- The roster lib is resolved during Scanner init, which may be after this file
    -- loads — register once it's available (retry alongside the first warm at +8s).
    -- Registrant is BrowserTab (not the lib) so we don't collide with the
    -- crafter-online alert, which registers OnMemberOnline on the lib itself.
    local rosterHooked = false
    local function hookRoster()
        if rosterHooked then return true end
        local GR = addon.Scanner and addon.Scanner.GuildRoster
        if not (GR and GR.RegisterCallback) then return false end
        rosterHooked = true
        GR.RegisterCallback(BrowserTab, "OnMemberOnline",  scheduleRosterRefresh)
        GR.RegisterCallback(BrowserTab, "OnMemberOffline", scheduleRosterRefresh)
        return true
    end
    if not hookRoster() then
        C_Timer.After(8, hookRoster)
    end
end
