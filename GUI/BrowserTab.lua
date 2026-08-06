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
-- The left list uses virtual scrolling (raw frame pool, 35 rows).

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local BrowserTab = {}
addon.BrowserTab = BrowserTab

-- Virtual scroll constants
local ROW_HEIGHT = 14
local POOL_SIZE  = 35

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
    if type(entry.craftedItemId) == "number" and GetItemInfo then
        local _, link = GetItemInfo(entry.craftedItemId)
        if link then return link end
    end
    -- entry.id is a recipeDB key, i.e. a spell id, with or without the isSpell
    -- flag — deliberately NOT gated on the flag, so an entry built before the
    -- flag existed still resolves as a spell instead of falling through to an
    -- item lookup.
    local spellId = entry.spellId or entry.id
    if type(spellId) == "number" and GetSpellLink then
        local link = GetSpellLink(spellId)
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
    if r.name and GetItemInfoInstant then
        local id = GetItemInfoInstant(r.name)
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
        local _, link = GetItemInfo(id)
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
BrowserTab._scroll            = nil      -- active AceGUI ScrollFrame widget
BrowserTab._container         = nil      -- the tab container widget
BrowserTab._pool              = nil      -- raw-frame row pool (left list)
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
        local mk = ck .. "\0" .. tostring(tag)
        local v = _visMemo[mk]
        if v == nil then v = addon:IsVisibleCrafter(ck, tag) and true or false; _visMemo[mk] = v end
        return v
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
    --   season             : SoD seasonal content — hide on non-SoD clients.
    local clientExp, clientMaxSkill
    if     addon.isVanilla then clientExp, clientMaxSkill = 1, 300
    elseif addon.isTBC     then clientExp, clientMaxSkill = 2, 375
    elseif addon.isWrath   then clientExp, clientMaxSkill = 3, 450
    elseif addon.isCata    then clientExp, clientMaxSkill = 4, 525
    elseif addon.isMoP     then clientExp, clientMaxSkill = 5, 600
    else                        clientExp, clientMaxSkill = 5, 600
    end
    local function passesClientGate(thisProfId, recipeId)
        local meta = addon.recipeDB and addon.recipeDB[thisProfId]
                                    and addon.recipeDB[thisProfId][recipeId]
        if not meta then return false end
        -- SoD/Anniversary recipes leak into the Vanilla lib set (the 1.15 client's
        -- tables carry them); their IDs are 400k+ while real Vanilla recipes are
        -- under ~30k. Hide that range on a Vanilla client that isn't running
        -- Season of Discovery.
        if clientExp == 1 and recipeId >= 200000 and not addon:IsSoD() then return false end
        if meta.minExpansion and meta.minExpansion > clientExp then return false end
        -- Non-SoD Vanilla: require spell presence for all recipes.
        if clientExp == 1 and not addon:IsSoD() and GetSpellInfo and not GetSpellInfo(recipeId) then return false end
        -- Non-SoD Vanilla cooking: blacklist known TBC recipes that leaked
        -- into ProfessionDB Vanilla data (exist in 1.15 client but aren't
        -- obtainable on Era/Anniversary).
        local TBC_COOKING_BLACKLIST = { [30047] = true }  -- Crystal Throat Lozenge
        if clientExp == 1 and not addon:IsSoD() and thisProfId == 185 and TBC_COOKING_BLACKLIST[recipeId] then
            return false
        end
        -- Non-SoD Vanilla First Aid: blacklist TBC Netherweave bandage recipes.
        local TBC_FIRSTAID_BLACKLIST = { [27032] = true, [27033] = true }  -- Netherweave Bandage, Heavy Netherweave Bandage
        if clientExp == 1 and not addon:IsSoD() and thisProfId == 129 and TBC_FIRSTAID_BLACKLIST[recipeId] then
            return false
        end
        if (not meta.minExpansion) and clientExp == 1 and recipeId > 25000 then
            -- Vanilla client, untagged high-ID recipe: require BOTH spell
            -- and item presence. TBC recipes like Crystal Throat Lozenge
            -- have items in shared tables but no spell on Era clients.
            local spellExists = GetSpellInfo and GetSpellInfo(recipeId) ~= nil
            local itemExists = GetItemInfoInstant and (
                (meta.itemId and GetItemInfoInstant(meta.itemId)) or
                (meta.craftedItemId and GetItemInfoInstant(meta.craftedItemId)))
            if not (spellExists and itemExists) then return false end
        end
        if meta.requiredSkill and meta.requiredSkill > clientMaxSkill then return false end
        if meta.season then return false end
        return true
    end

    local function buildCrafterList(profRecipeData, thisViewMode)
        if not profRecipeData or not profRecipeData.crafters then return nil end
        local GuildRoster  = addon.Scanner and addon.Scanner.GuildRoster
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
                local shortName   = ck:match("^(.-)%-") or ck
                local online      = GuildRoster and GuildRoster:IsOnline(ck) or false
                local displayName = shortName
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
                table.insert(crafterObjs, { name = displayName, online = online })
            end
        end
        table.sort(crafterObjs, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.name < b.name
        end)
        table.sort(youAlts, function(a, b) return a.name < b.name end)
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
                    local hay = (name or ""):lower()
                    if effect and effect ~= "" then hay = hay .. " " .. effect:lower() end
                    local tt = craftedItemId and addon:GetItemTooltipSearchText(craftedItemId)
                    if tt then hay = hay .. " " .. tt end
                    -- Fold the crafter names into the haystack so typing a player's
                    -- name in the search box filters the list to the recipes that
                    -- player crafts. Reuses `crafters` (already built above), so it
                    -- honours the same viewMode/visibility rules as the shown crafter
                    -- list — a name only matches recipes where that crafter is visible.
                    for _, c in ipairs(crafters) do
                        if c.name then hay = hay .. " " .. c.name:lower() end
                    end
                    local itemLink = craftedItemId and select(2, GetItemInfo(craftedItemId))
                    -- Learn skill for the tier filter: authoritative requiredSkill
                    -- when shipped, else the orange (difficulty[1]) breakpoint —
                    -- same fallback MissingRecipesTab uses. nil when neither is
                    -- known; FilterTiers keeps those rows unconditionally.
                    local meta      = profMetaDB[recipeId]
                    local reqSkill  = meta.requiredSkill
                                      or (meta.difficulty and meta.difficulty[1])
                    table.insert(list, {
                        id            = recipeId,
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
    container:SetLayout("List")

    -- Clean up a raw headerBar left over from a previous Draw() or tab switch.
    addon.GUI.DetachPool(self._headerBar)
    self._headerBar = nil

    self._slSection = nil
    local slData = Ace.db.char.shoppingList
    local hasSL  = false
    for _ in pairs(slData) do hasSL = true; break end
    local slCount = 0
    if hasSL then
        for _ in pairs(slData) do slCount = slCount + 1 end
    end

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

    local profOrder = {}
    local profLabelById = {}
    for _, p in ipairs(profEntries) do
        profOrder[#profOrder + 1] = p.profId
        profLabelById[p.profId] = p.name
    end

    local profDropdown = AceGUI:Create("Dropdown")
    profDropdown:SetLabel("|c" .. (addon.BrandColor or "ffFF8000") .. L["PanelProfessions"] .. "|r")
    profDropdown:SetWidth(180)
    addon.GUI.OffsetInputLabel(profDropdown)
    profDropdown:SetList(profLabelById, profOrder)
    -- Default to "All Professions" (0) when no selection exists
    if not self._selectedProfId then
        self._selectedProfId = 0
    end
    profDropdown:SetValue(self._selectedProfId)
    profDropdown:SetCallback("OnValueChanged", function(_w, _e, value)
        self._selectedProfId = value
        if Ace.db.profile.persistProfFilter then
            local _, setProfFilter = addon.GUI.PersistentChoice("profile", "savedProfFilter")
            setProfFilter(value)
        end
        self:RefreshList()
    end)
    addon.GUI.AttachTooltip(profDropdown, "Profession Filter", "Pick a profession to filter the recipe list.")
    toolbar:AddChild(profDropdown)

    local spTier = AceGUI:Create("Label"); spTier:SetWidth(8); toolbar:AddChild(spTier)

    -- Skill-tier multi-select filter. Same native AceGUI multiselect Dropdown as
    -- the AH Profit tab's Professions picker: the pullout stays open while
    -- ticking tiers, and Select All / Clear All ride at the top as button-like
    -- toggle rows. Only tiers reachable on this client version are offered.
    -- The filter runs post-cache (in FillList → FilterTiers) so changing it is a
    -- cheap re-filter, never a rebuild.
    local clientMaxSkill
    if     addon.isVanilla then clientMaxSkill = 300
    elseif addon.isTBC     then clientMaxSkill = 375
    elseif addon.isWrath   then clientMaxSkill = 450
    elseif addon.isCata    then clientMaxSkill = 525
    else                        clientMaxSkill = 600 end

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

    -- Band rows first, then Select All / Clear All as button-like toggle rows at
    -- the BOTTOM of the pullout.
    local tierList  = {}
    local tierOrder = {}
    for _, band in ipairs(availBands) do
        tierList[band.key] = TierBandLabel(band)
        tierOrder[#tierOrder + 1] = band.key
    end
    tierList[TIER_SELECT_ALL] = L["FilterSelectAll"]
    tierList[TIER_CLEAR_ALL]  = L["FilterClearAll"]
    tierOrder[#tierOrder + 1] = TIER_SELECT_ALL
    tierOrder[#tierOrder + 1] = TIER_CLEAR_ALL

    local tierDD = AceGUI:Create("Dropdown")
    tierDD:SetLabel("|c" .. (addon.BrandColor or "ffFF8000") .. L["BrowserSkillTier"] .. "|r")
    tierDD:SetWidth(180)
    addon.GUI.OffsetInputLabel(tierDD)
    tierDD:SetMultiselect(true)
    tierDD:SetList(tierList, tierOrder)

    -- Reapply every checkbox from the canonical _selectedTiers (nil = all on).
    -- Called after every change so the visible ticks always match state and the
    -- Select All / Clear All rows never keep a stray tick. This is the single
    -- source of truth for the pullout's visuals — no fragile mid-callback order.
    local function applyTierChecks()
        for _, band in ipairs(availBands) do
            local on = (self._selectedTiers == nil) or (self._selectedTiers[band.key] == true)
            tierDD:SetItemValue(band.key, on)
        end
        tierDD:SetItemValue(TIER_SELECT_ALL, false)
        tierDD:SetItemValue(TIER_CLEAR_ALL, false)
    end
    applyTierChecks()

    tierDD:SetCallback("OnValueChanged", function(_w, _e, key, checked)
        if key == TIER_SELECT_ALL then
            self._selectedTiers = nil            -- all tiers shown (canonical)
        elseif key == TIER_CLEAR_ALL then
            self._selectedTiers = {}             -- nothing ticked → only unclassified show
        else
            -- Materialize the current effective set (nil = every available band on),
            -- flip the clicked band, then collapse "all ticked" back to nil.
            local sel = {}
            if self._selectedTiers == nil then
                for _, band in ipairs(availBands) do sel[band.key] = true end
            else
                for k in pairs(self._selectedTiers) do sel[k] = true end
            end
            if checked then sel[key] = true else sel[key] = nil end
            local all = true
            for _, band in ipairs(availBands) do
                if not sel[band.key] then all = false; break end
            end
            self._selectedTiers = all and nil or sel
        end
        applyTierChecks()
        self:PersistTierFilter()
        self:RefreshList()
    end)
    addon.GUI.AttachTooltip(tierDD, L["BrowserSkillTierTip"], L["BrowserSkillTierDesc"])
    toolbar:AddChild(tierDD)

    local sp = AceGUI:Create("Label")
    sp:SetWidth(8)
    toolbar:AddChild(sp)

    local search = AceGUI:Create("EditBox")
    search:SetWidth(220)
    search:SetText(self._searchText)
    search:DisableButton(true)
    -- OnTextChanged fires on every keystroke; debounce so each character typed
    -- doesn't trigger a full BuildRecipeList + virtual-scroll redraw (which got
    -- heavier as cross-guild crafters grew the per-recipe crafter sets). Cancel-
    -- and-reschedule means only the value after the user pauses ~200ms rebuilds.
    -- Mirrors MissingRecipesTab. RefreshList rebuilds only the scroll list, not
    -- this EditBox, so focus/cursor are preserved while typing.
    search:SetCallback("OnTextChanged", function(_w, _e, text)
        self._searchText = text
        if self._searchTimer then self._searchTimer:Cancel() end
        self._searchTimer = C_Timer.NewTimer(0.2, function()
            self._searchTimer = nil
            self:RefreshList()
        end)
    end)
    addon.GUI.AttachTooltip(search, L["SearchPlaceholder"], L["CraftSearchDesc"])
    -- TSM-style search field: magnifying-glass icon instead of a text label
    -- (call after AttachTooltip so the icon's OnRelease cleanup chains).
    -- keepLabelSpace=true: aligns with the labeled dropdowns in this row.
    addon.GUI.StyleSearchBox(search, true)
    toolbar:AddChild(search)

    local sp2 = AceGUI:Create("Label")
    sp2:SetWidth(8)
    toolbar:AddChild(sp2)

    local viewDD = AceGUI:Create("Dropdown")
    viewDD:SetLabel("")
    viewDD:SetWidth(150)
    -- v0.7.0 view-mode dropdown gains "Show Missing" (only meaningful when
    -- _showAllRecipes is on). Items are listed in a deterministic order via
    -- the sorting array; AceConfig-style sorting isn't supported on raw
    -- AceGUI Dropdowns so we just SetList with the order we want.
    local viewItems = { guild = L["ViewGuild"], mine = L["ViewMine"] }
    if self._showAllRecipes then
        viewItems.missing = L["ViewMissing"] or "Show Missing"
    end
    viewDD:SetList(viewItems, { "guild", "mine", "missing" })
    -- If the user previously selected "missing" then toggled the checkbox off,
    -- fall back to "guild" so the dropdown value stays valid.
    if self._viewMode == "missing" and not self._showAllRecipes then
        self._viewMode = "guild"
    end
    viewDD:SetValue(self._viewMode)
    viewDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._viewMode       = value
        self._selectedProfs  = nil
        self._selectedProfId = 0
        self._selectedEntry  = nil
        C_Timer.After(0, function()
            if self._container then
                self._container:ReleaseChildren()
                self:Draw(self._container)
            end
        end)
    end)
    toolbar:AddChild(viewDD)

    local sp3 = AceGUI:Create("Label"); sp3:SetWidth(8); toolbar:AddChild(sp3)

    -- v0.7.0 "Show all recipes" checkbox. When ON, every recipe in the shipped
    -- addon.recipeDB appears in the list — ones nobody in the guild knows
    -- render greyed out so users can scan the gaps. Also unlocks the
    -- "Show Missing" entry in the View dropdown above.
    local showAllCB = AceGUI:Create("CheckBox")
    showAllCB:SetLabel(L["BrowserShowAllRecipes"] or "Show all recipes")
    showAllCB:SetWidth(170)
    showAllCB:SetValue(self._showAllRecipes)
    showAllCB:SetCallback("OnValueChanged", function(_w, _e, value)
        self._showAllRecipes = value
        if not value and self._viewMode == "missing" then
            self._viewMode = "guild"
        end
        C_Timer.After(0, function()
            if self._container then
                self._container:ReleaseChildren()
                self:Draw(self._container)
            end
        end)
    end)
    addon.GUI.AttachTooltip(showAllCB, L["BrowserShowAllRecipes"] or "Show all recipes",
        L["BrowserShowAllRecipesDesc"] or "Include every recipe in the shipped database, even ones nobody in the guild knows. Missing recipes render greyed out so officers can spot which skills the guild still needs to cover.")
    toolbar:AddChild(showAllCB)

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
        -- OnRelease: detach our pooled raw row frames from the InlineGroup
        -- before AceGUI recycles it into another addon. Without this our
        -- pool frames stay parented to the recycled widget and visibly
        -- bleed into the other addon's UI (the bug the user hit on
        -- TBC / Anniversary). Mirrors the recipe-scroll's DestroyPool
        -- OnRelease pattern below at line ~464.
        slSection:SetCallback("OnRelease", function()
            self:DetachShoppingListPool()
        end)
        container:AddChild(slSection)
        self._slSection = slSection
        self:FillShoppingListSection(slSection)
    end

    -- ---- Column headers (raw frame) ----------------------------------------
    local anchorFrame = (self._slSection and self._slSection.frame) or toolbar.frame
    local headerBar   = CreateFrame("Frame", nil, container.content)
    headerBar:SetHeight(18)
    headerBar:SetPoint("TOPLEFT",  anchorFrame, "BOTTOMLEFT",  0, 0)
    headerBar:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    self._headerBar = headerBar

    local recipeHdr = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipeHdr:ClearAllPoints()
    recipeHdr:SetPoint("LEFT", headerBar, "LEFT", 24, 0)
    recipeHdr:SetText(addon.UI.Brand("Recipes"))

    local recipeHdrHit = CreateFrame("Frame", nil, headerBar)
    recipeHdrHit:SetPoint("LEFT",  recipeHdr, "LEFT",  -2, 0)
    recipeHdrHit:SetPoint("RIGHT", recipeHdr, "RIGHT",  2, 0)
    recipeHdrHit:SetHeight(18)
    recipeHdrHit:SetScript("OnEnter", function(f)
        addon.Tooltip.Owner(f)
        GameTooltip:SetText(L["TooltipRecipeTitle"], 1, 1, 1)
        GameTooltip:AddLine(L["TooltipRecipeDesc"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    recipeHdrHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local craftersHdr = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftersHdr:ClearAllPoints()
    craftersHdr:SetPoint("LEFT", headerBar, "LEFT", 186, 0)
    craftersHdr:SetText(addon.UI.Brand(L["CraftersColHeader"]))

    local craftersHdrHit = CreateFrame("Frame", nil, headerBar)
    craftersHdrHit:SetPoint("LEFT",  craftersHdr, "LEFT",  -2, 0)
    craftersHdrHit:SetPoint("RIGHT", craftersHdr, "RIGHT",  2, 0)
    craftersHdrHit:SetHeight(18)
    craftersHdrHit:SetScript("OnEnter", function(f)
        addon.Tooltip.Owner(f)
        GameTooltip:SetText(L["TooltipCraftersTitle"], 1, 1, 1)
        GameTooltip:AddLine(L["TooltipCraftersDesc"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    craftersHdrHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ---- Recipe scroll list (left column) ----------------------------------
    if self._pool then
        self:DestroyPool()
    end

    -- Persist scroll position across redraws so sync-triggered
    -- GUILD_DATA_UPDATED rebuilds (every few seconds in active guilds)
    -- don't yank the user back to the top mid-scroll. Acquire captures
    -- the saved value BEFORE we hand the scroll widget off to FillList
    -- (which calls FixScroll → scrollbar:SetValue(0) → would clobber a
    -- live status table). We restore at the end of Draw, after FillList
    -- + content-height are settled.
    local scroll, savedScroll = addon.GUI.PersistentScroll.Acquire(self, {
        key       = "browser",
        layout    = "List",
        fullWidth = true,
        onRelease = function()
            self:DestroyPool()
            -- Detach raw frames parented to container.content BEFORE
            -- AceGUI recycles the container (see GUI/SharedWidgets.lua :
            -- addon.GUI.DetachPool for the one true cleanup). The
            -- LayoutFinished override our FillList installs as part of
            -- the virtual-scroll trick is restored on the NEXT Acquire
            -- (PersistentScroll.Acquire reassigns the class method on
            -- every acquire), so we don't have to clean it up here.
            addon.GUI.DetachPool(self._headerBar)
            self._headerBar = nil
            -- _detailOuter is reused across Draws (lazy-created in
            -- EnsureDetailPanel, re-parented + re-anchored next Draw),
            -- so we detach but do NOT nil it.
            addon.GUI.DetachPool(self._detailOuter)
        end,
    })
    container:AddChild(scroll)
    self._scroll = scroll

    -- ---- Detail panel (right column, persistent) ---------------------------
    self:EnsureDetailPanel(container.content)
    local rp = self._detailOuter
    rp:SetParent(container.content)
    rp:SetWidth(DP_W)
    rp:ClearAllPoints()
    rp:SetPoint("TOPRIGHT",    headerBar, "BOTTOMRIGHT",         0, 0)
    rp:SetPoint("BOTTOMRIGHT", container.content, "BOTTOMRIGHT", 0, 0)
    rp:Show()

    if self._selectedEntry then
        self:DrawDetail(self._selectedEntry)
    else
        self:ClearDetail()
    end

    -- Anchor scroll frame to fill the left column (right edge = detail panel left - gap).
    local function AnchorScrollToFill()
        if not (self._scroll and self._scroll.frame) then return end
        if not self._detailOuter then return end
        self._scroll.frame:ClearAllPoints()
        self._scroll.frame:SetPoint("TOPLEFT",     headerBar, "BOTTOMLEFT",  0, 0)
        self._scroll.frame:SetPoint("BOTTOMRIGHT", self._detailOuter, "BOTTOMLEFT", -DP_GAP, 0)
    end
    container.LayoutFinished = function() AnchorScrollToFill() end
    AnchorScrollToFill()

    self:FillList()

    -- Restore captured scroll position now that content height is set.
    -- FillList wrote scroll.content height and ran FixScroll above, so
    -- SetScroll(saved) can derive a correct offset. The afterFn re-
    -- positions our raw-frame pool to match.
    addon.GUI.PersistentScroll.Restore(scroll, savedScroll, function()
        self:UpdateVirtualRows()
    end)
end

-- ---------------------------------------------------------------------------
-- Shopping list helpers
-- ---------------------------------------------------------------------------

function BrowserTab:FillShoppingListSection(container)
    local bl = Ace.db.char.shoppingList

    local parent = container.content or container.frame

    if not self._slPool        then self._slPool        = {} end
    if not self._slReagentPool then self._slReagentPool = {} end
    if not self._slExpanded    then self._slExpanded    = {} end

    local rows = {}
    for sid, entry in pairs(bl) do
        table.insert(rows, { sid = sid, entry = entry })
    end
    table.sort(rows, function(a, b)
        local na = (a.entry and a.entry.name) or tostring(a.sid)
        local nb = (b.entry and b.entry.name) or tostring(b.sid)
        return na < nb
    end)

    for _, f in ipairs(self._slPool)        do f:SetParent(parent) end
    for _, f in ipairs(self._slReagentPool) do f:SetParent(parent) end

    local function GetRecipeFrame(idx)
        if self._slPool[idx] then return self._slPool[idx] end

        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrow:SetPoint("LEFT", f, "LEFT", 2, 0)
        arrow:SetWidth(12)
        arrow:SetJustifyH("CENTER")
        f.arrow = arrow

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", 16, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(210)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        local removeBtn = CreateFrame("Button", nil, f)
        removeBtn:SetSize(12, 18)
        removeBtn:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        local removeLbl = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        removeLbl:SetAllPoints()
        removeLbl:SetJustifyH("CENTER")
        removeLbl:SetText("|cFFFF4444x|r")
        f.removeBtn = removeBtn

        local plusBtn = CreateFrame("Button", nil, f)
        plusBtn:SetSize(12, 18)
        plusBtn:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
        local plusLbl = plusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        plusLbl:SetAllPoints()
        plusLbl:SetJustifyH("CENTER")
        plusLbl:SetText("|cFFFFD100+|r")
        f.plusBtn = plusBtn

        local qtyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qtyLbl:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)
        qtyLbl:SetWidth(22)
        qtyLbl:SetJustifyH("CENTER")
        f.qtyLbl = qtyLbl

        local minusBtn = CreateFrame("Button", nil, f)
        minusBtn:SetSize(12, 18)
        minusBtn:SetPoint("RIGHT", qtyLbl, "LEFT", -4, 0)
        local minusLbl = minusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        minusLbl:SetAllPoints()
        minusLbl:SetJustifyH("CENTER")
        minusLbl:SetText("|cFFFFD100-|r")
        f.minusBtn = minusBtn

        local alertBtn = CreateFrame("Button", nil, f)
        alertBtn:SetSize(12, 18)
        alertBtn:SetPoint("RIGHT", minusBtn, "LEFT", -4, 0)
        local alertLbl = alertBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        alertLbl:SetAllPoints()
        alertLbl:SetJustifyH("CENTER")
        alertLbl:SetText("|cff666666!|r")
        alertBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(alertBtn)
            local enabled = alertBtn._sid and Ace.db.char.shoppingAlerts[alertBtn._sid]
            GameTooltip:SetText(enabled and L["ShoppingAlertDisable"] or L["ShoppingAlertEnable"], 1, 1, 1)
            GameTooltip:Show()
        end)
        alertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.alertBtn  = alertBtn
        f.alertLbl  = alertLbl

        self._slPool[idx] = f
        return f
    end

    local INDENT = 18
    local function GetReagentFrame(idx)
        if self._slReagentPool[idx] then return self._slReagentPool[idx] end

        local f = CreateFrame("Frame", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:EnableMouse(true)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("LEFT", f, "LEFT", INDENT + 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(200)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        nameLbl:SetTextColor(1, 1, 1)
        f.nameLbl = nameLbl

        local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countLbl:SetPoint("LEFT", nameLbl, "RIGHT", 4, 0)
        countLbl:SetWidth(44)
        countLbl:SetJustifyH("RIGHT")
        countLbl:SetTextColor(1, 1, 1)
        f.countLbl = countLbl

        local bankBtn = CreateFrame("Button", nil, f)
        bankBtn:SetSize(52, 14)
        bankBtn:SetPoint("LEFT", countLbl, "RIGHT", 4, 0)
        bankBtn:SetNormalFontObject(GameFontNormalSmall)
        bankBtn:SetText("|cFF88FF88[Bank]|r")
        bankBtn:Hide()
        bankBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(bankBtn)
            GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1)
            GameTooltip:AddLine(L["TooltipBankDescGeneric"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.bankBtn = bankBtn

        -- [AH] button — visible only when the AH scanner has found live
        -- listings for this reagent (gates on AH.GetListingsFor.count > 0).
        -- Click jumps the AH browse search to this reagent's name. Anchor
        -- gets re-set per-row in the update loop below depending on
        -- whether [Bank] is also showing, so the two buttons sit cleanly
        -- side-by-side without a gap when only one is visible.
        local ahBtn = CreateFrame("Button", nil, f)
        ahBtn:SetSize(36, 14)
        ahBtn:SetNormalFontObject(GameFontNormalSmall)
        ahBtn:SetText("|cFF88CCFF[AH]|r")
        ahBtn:Hide()
        ahBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(ahBtn)
            GameTooltip:SetText(L["TooltipAHTitle"], 1, 1, 1)
            GameTooltip:AddLine(L["TooltipAHDescReagent"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.ahBtn = ahBtn

        self._slReagentPool[idx] = f
        return f
    end

    for _, f in ipairs(self._slPool)        do f:Hide() end
    for _, f in ipairs(self._slReagentPool) do f:Hide() end

    local yOffset    = 0
    local reagentIdx = 0

    for recipeIdx, rowData in ipairs(rows) do
        local sid      = rowData.sid
        local ent      = rowData.entry
        local qty      = (ent and ent.quantity) or 1
        local name     = (ent and ent.name) or tostring(sid)
        local reagents = (ent and ent.reagents) or {}
        local hasReagents = #reagents > 0
        local expanded = self._slExpanded[sid]

        local f = GetRecipeFrame(recipeIdx)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -yOffset)
        f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
        yOffset = yOffset + ROW_HEIGHT

        if hasReagents then
            f.arrow:SetText(expanded and "|cFFFFD100-|r" or "|cFFFFD100+|r")
        else
            f.arrow:SetText("")
        end

        if ent and ent.icon then
            f.icon:SetTexture(ent.icon)
        else
            f.icon:SetTexture(nil)
        end

        local colorHex = ent and type(ent.itemLink) == "string" and ent.itemLink:match("|c(ff%x%x%x%x%x%x)|H")
        f.nameLbl:SetText(colorHex and ("|c" .. colorHex .. name .. "|r") or name)
        f.qtyLbl:SetText(tostring(qty))

        -- Alert toggle button state
        f.alertBtn._sid = sid
        local alertOn = Ace.db.char.shoppingAlerts[sid]
        f.alertLbl:SetText(alertOn and "|cffFFD700!|r" or "|cff666666!|r")
        f.alertBtn:SetScript("OnClick", function()
            if Ace.db.char.shoppingAlerts[sid] then
                Ace.db.char.shoppingAlerts[sid] = nil
            else
                Ace.db.char.shoppingAlerts[sid] = true
            end
            f.alertLbl:SetText(Ace.db.char.shoppingAlerts[sid] and "|cffFFD700!|r" or "|cff666666!|r")
        end)

        f:SetScript("OnClick", function(btn)
            if f.minusBtn:IsMouseOver() or f.plusBtn:IsMouseOver() or f.removeBtn:IsMouseOver()
            or f.alertBtn:IsMouseOver() then
                return
            end
            if hasReagents then
                self._slExpanded[sid] = not self._slExpanded[sid]
                self:RefreshShoppingList()
            end
        end)

        f.minusBtn:SetScript("OnClick", function()
            local cur = (bl[sid] and bl[sid].quantity) or 1
            if cur <= 1 then
                bl[sid] = nil
                self._slExpanded[sid] = nil
            else
                bl[sid].quantity = cur - 1
            end
            -- Sync detail panel if this recipe is currently selected
            if self._selectedEntry and self._selectedEntry.id == sid then
                self:DrawDetail(self._selectedEntry)
            end
            self:RefreshShoppingList()
        end)
        f.plusBtn:SetScript("OnClick", function()
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
            if self._selectedEntry and self._selectedEntry.id == sid then
                self:DrawDetail(self._selectedEntry)
            end
            self:RefreshShoppingList()
        end)
        f.removeBtn:SetScript("OnClick", function()
            bl[sid] = nil
            self._slExpanded[sid] = nil
            Ace.db.char.shoppingAlerts[sid] = nil
            if self._selectedEntry and self._selectedEntry.id == sid then
                self:DrawDetail(self._selectedEntry)
            end
            self:RefreshShoppingList()
        end)

        f:SetScript("OnEnter", function()
            local link = ent and (ent.itemLink or ent.recipeLink)
            if link then
                addon.Tooltip.Owner(f)
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            elseif type(sid) == "number" then
                -- No crafted item (enchants): the shopping-list key IS the
                -- recipe's spell id, so show the spell tooltip rather than
                -- leaving the row with no hover at all.
                addon.Tooltip.Owner(f)
                if SetSpellTooltip(GameTooltip, sid) then GameTooltip:Show() end
            end
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:Show()

        if expanded and hasReagents then
            for _, r in ipairs(reagents) do
                reagentIdx = reagentIdx + 1
                local rf = GetReagentFrame(reagentIdx)
                rf:ClearAllPoints()
                rf:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -yOffset)
                rf:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
                yOffset = yOffset + ROW_HEIGHT

                if r.itemId and r.itemId > 0 then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(r.itemId)
                    rf.icon:SetTexture(itemTexture or nil)
                else
                    rf.icon:SetTexture(nil)
                end

                rf.nameLbl:SetText(r.name or "")

                local rItemId   = ResolveReagentItemId(r)
                local rItemLink = ResolveReagentItemLink(r)
                rf:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(rf)
                    if addon.ItemLink.SetItem(GameTooltip, rItemLink, rItemId) then
                        GameTooltip:Show()
                    end
                end)
                rf:SetScript("OnLeave", function()
                    addon.ItemLink.EndHover(GameTooltip)
                    GameTooltip:Hide()
                end)

                local needed = (r.count or 1) * qty
                rf.countLbl:SetText("|cffffffff x" .. needed .. "|r")

                local hasBank = rItemId and addon.Bank and addon.Bank.GetStock(rItemId) > 0
                local ahData  = rItemId and addon.AH and addon.AH.GetListingsFor(rItemId)
                local hasAH   = ahData and (ahData.count or 0) > 0 and r.name and r.name ~= ""

                if hasBank then
                    rf.bankBtn:SetScript("OnClick", function()
                        addon.Bank.ShowRequestDialog(rItemId, r.name or "", rItemLink)
                    end)
                end
                if hasAH then
                    local rName = r.name
                    rf.ahBtn:SetScript("OnClick", function()
                        addon.AH.SearchFor(rName)
                    end)
                end

                -- Dynamic anchoring: order is [Bank] [AH] (left to right).
                -- count→bank gap is 8 (not 4) to balance the perceived gap
                -- with bank→ah: countLbl's right-justified text is flush
                -- against its frame edge, but both [Bank] and [AH] have
                -- internal text padding inside their button frames, so the
                -- visible "]" / "[" gap is wider than a 4px frame gap. 8px
                -- frame gap to count compensates for the missing left-text-
                -- padding that count doesn't have. When only one button
                -- shows, it anchors to countLbl directly so there's never an
                -- empty slot gap from the other.
                rf.bankBtn:ClearAllPoints()
                rf.ahBtn:ClearAllPoints()
                if hasBank then
                    rf.bankBtn:SetPoint("LEFT", rf.countLbl, "RIGHT", 8, 0)
                    rf.bankBtn:Show()
                    if hasAH then
                        rf.ahBtn:SetPoint("LEFT", rf.bankBtn, "RIGHT", 4, 0)
                        rf.ahBtn:Show()
                    else
                        rf.ahBtn:Hide()
                    end
                else
                    rf.bankBtn:Hide()
                    if hasAH then
                        rf.ahBtn:SetPoint("LEFT", rf.countLbl, "RIGHT", 8, 0)
                        rf.ahBtn:Show()
                    else
                        rf.ahBtn:Hide()
                    end
                end

                rf:Show()
            end
        end
    end

    local totalH = math.max(yOffset, ROW_HEIGHT)
    container:SetHeight(totalH + 40)
end

function BrowserTab:RefreshShoppingList()
    if not self._container then return end
    if addon.ReagentTracker then addon.ReagentTracker:QueueRefresh() end

    if self._slSection then
        local bl    = Ace.db.char.shoppingList
        local hasSL = false
        for _ in pairs(bl) do hasSL = true; break end

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

function BrowserTab:RefreshList()
    local scroll = self._scroll
    if not scroll then return end
    if self._pool then
        for _, f in ipairs(self._pool) do f:Hide() end
    end
    self._recipes = nil
    -- Filter/search change: user expects to see the top of the new
    -- result set, not whatever offset the previous list was scrolled to.
    addon.GUI.PersistentScroll.Reset(self, scroll)
    if scroll.scrollbar and scroll.scrollbar.SetValue then
        scroll.scrollbar:SetValue(0)
    end
    scroll:ReleaseChildren()
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
    local full = BuildFullList(profId, viewMode, { showAll = showAll })
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
    local scroll = self._scroll
    if not scroll then return end

    scroll.LayoutFinished = nil

    if not self._selectedProfId then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["SelectProfHint"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
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
        scroll:AddChild(lbl)
        return
    end

    self._recipes = recipes

    scroll.LayoutFinished = function() end
    scroll.content:SetHeight(#recipes * ROW_HEIGHT)
    scroll:FixScroll()

    if not self._pool then
        self:BuildPool(scroll.content)
    end

    self:UpdateVirtualRows()

    scroll.scrollbar:SetScript("OnValueChanged", function(bar, value)
        bar.obj:SetScroll(value)
        self:UpdateVirtualRows()
    end)

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
                if self._pool then self:UpdateVirtualRows() end
                -- Bank buttons live in the detail panel; redraw it too.
                if self._selectedEntry then self:DrawDetail(self._selectedEntry) end
                -- Refresh shopping list bank buttons as well.
                if self._slSection then self:FillShoppingListSection(self._slSection) end
            end)
        end)
    end
end

-- Build POOL_SIZE raw WoW frames parented to the scroll content frame.
function BrowserTab:BuildPool(parent)
    self._pool = {}
    for i = 1, POOL_SIZE do
        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:Hide()
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        -- Name column
        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(160)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        -- Crafter column: truncated summary; narrowed to leave room for bank button
        local crafterLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        crafterLbl:SetPoint("LEFT",  f, "LEFT",  186, 0)
        crafterLbl:SetPoint("RIGHT", f, "RIGHT",  -56, 0)
        crafterLbl:SetJustifyH("LEFT")
        crafterLbl:SetWordWrap(false)
        f.crafterLbl = crafterLbl

        -- Bank button at far right
        local bankBtn = CreateFrame("Button", nil, f)
        bankBtn:SetSize(50, 12)
        bankBtn:SetPoint("RIGHT", f, "RIGHT", -2, 0)
        bankBtn:SetNormalFontObject(GameFontNormalSmall)
        bankBtn:SetText("|cFF88FF88[Bank]|r")
        bankBtn:Hide()
        bankBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(bankBtn)
            GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1)
            GameTooltip:AddLine(L["TooltipBankDescGeneric"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.bankBtn = bankBtn

        f:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local entry = f._entry
            if not entry then return end
            -- Shift-click inserts the recipe link into the chat edit box.
            -- ResolveRecipeLink falls back through itemLink → recipeLink →
            -- GetItemInfo(id) → GetSpellLink → synthetic "item:<id>" so the
            -- click always produces a link even for trainer-taught recipes
            -- whose gdb entry has no link cached. Without this, shift-click
            -- silently did nothing for entries with nil itemLink/recipeLink.
            if addon.ItemLink.Click(ResolveRecipeLink(entry)) then return end
            self:DrawDetail(entry)
        end)

        f:SetScript("OnEnter", function()
            local entry = f._entry
            if not entry then return end
            addon.Tooltip.Owner(f)
            -- Only use recipeLink if it is a real item link; enchanting stores
            -- enchant:SPELLID here which produces an unhelpful tooltip.
            if entry.recipeLink and entry.recipeLink:find("|Hitem:") then
                GameTooltip:SetHyperlink(entry.recipeLink)
            elseif entry.reagents and #entry.reagents > 0 then
                local parts = {}
                for _, r in ipairs(entry.reagents) do
                    table.insert(parts, r.name .. " (" .. r.count .. ")")
                end
                local reagentLine = (SPELL_REAGENTS or "Reagents:") .. " " .. table.concat(parts, ", ")
                local header = (entry.profName and entry.profName ~= "")
                    and (entry.profName .. ": " .. entry.name) or entry.name
                GameTooltip:ClearLines()
                GameTooltip:AddLine("|cffffff00" .. header .. "|r")
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
                            if lStr ~= "" or rStr ~= "" then
                                local lr, lg, lb = 1, 1, 1
                                local rr, rg, rb = 1, 1, 1
                                if lt then lr, lg, lb = lt:GetTextColor() end
                                if rt then rr, rg, rb = rt:GetTextColor() end
                                if rStr ~= "" then
                                    GameTooltip:AddDoubleLine(lStr, rStr, lr, lg, lb, rr, rg, rb)
                                else
                                    -- wrapText=true so long item lines (e.g. a flask's verbose
                                    -- "Use:" text) wrap instead of stretching the tooltip across
                                    -- the screen. With no unwrapped long line left, the tooltip
                                    -- sizes to the header/stat lines.
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
                GameTooltip:Show()
                return
            elseif type(entry.itemLink) == "string" and entry.itemLink:find("|Hitem:") then
                addon.ItemLink.SetItem(GameTooltip, entry.itemLink)
            elseif not SetSpellTooltip(GameTooltip, entry.spellId or entry.id) then
                -- No link, no spell id: name-only so the hover still says
                -- something. Never "item:<entry.id>" — entry.id is a spell id
                -- and that lookup lands on an unrelated item.
                GameTooltip:SetText(entry.name or "", 1, 1, 1, 1, false)
            end
            -- For SetHyperlink branches the global tooltip hook will fire on
            -- Show() and add its own brand crafters+IDs (the hook dedups via
            -- _togpmAppended). For SetSpellByID branches the hook does NOT
            -- fire (no item context), so this manual call is the only way
            -- spell-only recipes get an IDs line. The dedup means we don't
            -- double-up on SetHyperlink branches — the manual call wins,
            -- the hook's later call early-returns.
            AppendBrandTooltipLines(entry)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self._pool[i] = f
    end
end

function BrowserTab:DestroyPool()
    if self._pool then
        addon.GUI.DetachPool(self._pool)
        -- Also nil the OnMouseDown/OnEnter/OnLeave scripts on each row
        -- (the recipe-row pool uses raw script handlers for click + hover,
        -- not AceGUI callbacks; explicit nil here matches the intent of
        -- DetachPool — make these frames inert until next acquire).
        for _, f in ipairs(self._pool) do
            f:SetScript("OnMouseDown", nil)
            f:SetScript("OnEnter",     nil)
            f:SetScript("OnLeave",     nil)
        end
        self._pool    = nil
        self._recipes = nil
    end
    self._scroll             = nil
    self._bankRefreshPending = nil
end

--- Detach the shopping-list pooled rows from their AceGUI InlineGroup
--- parent before the InlineGroup gets recycled. Called from the
--- InlineGroup's OnRelease callback wired up in Draw().
---
--- Without this, the pooled frames in self._slPool / self._slReagentPool
--- remain SetParent()'d to the InlineGroup's content frame; when AceGUI
--- pools the InlineGroup and another addon acquires it, our rows show
--- up in the other addon's UI. Same problem the recipe-scroll's
--- DestroyPool above prevents for the main recipe list, and the same
--- problem MissingRecipesTab:DetachPool prevents for the missing-
--- recipes list.
---
--- Re-parents to UIParent (a globally-rooted frame the pool can sit
--- under harmlessly) and clears all anchors. Frames stay alive in the
--- pool tables for the next FillShoppingListSection — Re-parented again
--- when that runs (line 533/534).
function BrowserTab:DetachShoppingListPool()
    addon.GUI.DetachPool(self._slPool)
    addon.GUI.DetachPool(self._slReagentPool)
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

    -- Native WoW ScrollFrame for the detail content.
    local sf = CreateFrame("ScrollFrame", nil, rp)
    sf:SetPoint("TOPLEFT",     rp, "TOPLEFT",     DP_PAD, -DP_PAD)
    sf:SetPoint("BOTTOMRIGHT", rp, "BOTTOMRIGHT", -(DP_PAD + 16), DP_PAD)
    sf:Hide()
    self._dpSF = sf

    local cw = DP_W - DP_PAD * 2 - 18
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(cw)
    content:SetHeight(10)
    sf:SetScrollChild(content)
    self._dpContent = content

    -- Scrollbar (sits in the right margin of the outer panel).
    local sb = CreateFrame("Slider", nil, rp, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT",    2, -16)
    sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2,  16)
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(8)
    if sb.SetObeyStepOnDrag then sb:SetObeyStepOnDrag(true) end
    sf:SetScript("OnScrollRangeChanged", function(_, _, yr)
        local m = math.max(0, yr or 0)
        sb:SetMinMaxValues(0, m)
        if m > 0 then sb:Show() else sb:Hide() end
    end)
    sf:SetScript("OnMouseWheel", function(_, delta)
        sb:SetValue(sb:GetValue() - delta * 20)
    end)
    sb:SetScript("OnValueChanged", function(_, val)
        sf:SetVerticalScroll(val)
    end)
    self._dpSB = sb

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

    -- Dynamic-position headings (repositioned each DrawDetail call)
    local dpReagHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpReagHdr:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Reagents|r")
    self._dpReagHdr = dpReagHdr

    local dpCraftHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpCraftHdr:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Known By|r")
    self._dpCraftHdr = dpCraftHdr

    -- Pools for reagent and crafter rows (grow as needed, never shrink)
    self._dpReagPool  = {}
    self._dpCraftPool = {}
end

-- Get-or-create a reagent row frame inside the detail content.
function BrowserTab:GetDetailReagRow(idx)
    if self._dpReagPool[idx] then return self._dpReagPool[idx] end

    local content = self._dpContent
    local f = CreateFrame("Button", nil, content)
    f:SetHeight(DP_ROW)
    f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameLbl:SetWidth(120)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetWordWrap(false)
    f.nameLbl = nameLbl

    local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLbl:SetPoint("LEFT", nameLbl, "RIGHT", 4, 0)
    countLbl:SetWidth(36)
    countLbl:SetJustifyH("RIGHT")
    f.countLbl = countLbl

    local bankBtn = CreateFrame("Button", nil, f)
    bankBtn:SetSize(46, 12)
    bankBtn:SetPoint("LEFT", countLbl, "RIGHT", 4, 0)
    bankBtn:SetNormalFontObject(GameFontNormalSmall)
    bankBtn:SetText("|cFF88FF88[Bank]|r")
    bankBtn:Hide()
    bankBtn:SetScript("OnEnter", function()
        addon.Tooltip.Owner(bankBtn)
        GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1)
        GameTooltip:AddLine(L["TooltipBankDescGeneric"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.bankBtn = bankBtn

    -- [AH] button — sibling of [Bank], shown only when the AH scanner has
    -- found live listings for this reagent. Click jumps to AH browse search.
    local ahBtn = CreateFrame("Button", nil, f)
    ahBtn:SetSize(32, 12)
    ahBtn:SetNormalFontObject(GameFontNormalSmall)
    ahBtn:SetText("|cFF88CCFF[AH]|r")
    ahBtn:Hide()
    ahBtn:SetScript("OnEnter", function()
        addon.Tooltip.Owner(ahBtn)
        GameTooltip:SetText(L["TooltipAHTitle"], 1, 1, 1)
        GameTooltip:AddLine(L["TooltipAHDescReagent"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.ahBtn = ahBtn

    self._dpReagPool[idx] = f
    return f
end

-- Get-or-create a crafter row frame inside the detail content.
function BrowserTab:GetDetailCraftRow(idx)
    if self._dpCraftPool[idx] then return self._dpCraftPool[idx] end

    local content = self._dpContent
    local f = CreateFrame("Button", nil, content)
    f:SetHeight(DP_ROW)
    f:RegisterForClicks("AnyUp")  -- enables right-click for whisper
    f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT",  f, "LEFT",  0, 0)
    lbl:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    f.lbl = lbl

    self._dpCraftPool[idx] = f
    return f
end

-- Populate the detail panel for the given recipe entry.
function BrowserTab:DrawDetail(entry)
    self:EnsureDetailPanel(
        self._container and self._container.content or UIParent)
    self._selectedEntry = entry

    local content = self._dpContent

    self._dpPH:Hide()
    self._dpSF:Show()
    self._dpSB:SetValue(0)
    self._dpSF:SetVerticalScroll(0)

    -- Header: icon + name
    self._dpIcon:SetTexture(entry.icon)
    local titleColor = type(entry.itemLink) == "string" and entry.itemLink:match("|c(ff%x%x%x%x%x%x)|H") or "ffffd100"
    self._dpName:SetText("|c" .. titleColor .. entry.name .. "|r")

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
            GameTooltip:SetText(entry.name or "", 1, 1, 1, 1, false)
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
        -- Also refresh reagent counts if panel is showing this entry
        if self._selectedEntry and self._selectedEntry.id == entry.id then
            for ri, r in ipairs(entry.reagents or {}) do
                local rf = self._dpReagPool[ri]
                if rf and rf:IsShown() then
                    local mult = math.max(1, qty)
                    rf.countLbl:SetText("|cffffffff\195\151" .. (r.count or 1) * mult .. "|r")
                end
            end
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

    -- Running y-offset (negative = downward from content top)
    local yOff = -(DP_ICON + 4 + DP_ROW + 4)

    -- ── Reagents ──────────────────────────────────────────────────────────
    local reagents    = entry.reagents or {}
    local hasReagents = #reagents > 0

    if hasReagents then
        self._dpReagHdr:ClearAllPoints()
        self._dpReagHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        self._dpReagHdr:Show()
        yOff = yOff - DP_ROW

        local slQty = (Ace.db.char.shoppingList[entry.id]
                      and Ace.db.char.shoppingList[entry.id].quantity) or 0
        local mult  = math.max(1, slQty)

        for i, r in ipairs(reagents) do
            local rf = self:GetDetailReagRow(i)
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
            rf:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
            yOff = yOff - DP_ROW

            local rItemId = ResolveReagentItemId(r)
            local rLink   = ResolveReagentItemLink(r)
            if rItemId and rItemId > 0 then
                local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(rItemId)
                rf.icon:SetTexture(tex or nil)
            else
                rf.icon:SetTexture(nil)
            end
            rf.nameLbl:SetText(r.name or "")
            rf.countLbl:SetText("|cffffffff\195\151" .. (r.count or 1) * mult .. "|r")

            if rLink or rItemId then
                rf:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(rf)
                    if addon.ItemLink.SetItem(GameTooltip, rLink, rItemId) then
                        GameTooltip:Show()
                    end
                end)
                rf:SetScript("OnLeave", function()
                    addon.ItemLink.EndHover(GameTooltip)
                    GameTooltip:Hide()
                end)
                -- OnMouseDown (not OnClick) for the row's shift-click-link behaviour.
                -- Parent OnClick competes with the child bankBtn's OnClick on some
                -- WoW builds — the parent-Button click handler swallows the event
                -- and the inner [Bank] button's OnClick never fires.  Using
                -- OnMouseDown for the row avoids the conflict (different event)
                -- while preserving the shift-click-to-insert-link behaviour.
                -- This matches the recipe-row mouse handler pattern at
                -- BrowserTab.lua:936 (which always worked).
                rf:SetScript("OnMouseDown", function(_, btn)
                    if btn == "LeftButton" then addon.ItemLink.Click(rLink) end
                end)
                rf:SetScript("OnClick", nil)  -- ensure no stale OnClick from a prior render
            else
                rf:SetScript("OnEnter", nil)
                rf:SetScript("OnLeave", nil)
                rf:SetScript("OnMouseDown", nil)
                rf:SetScript("OnClick", nil)
            end

            local hasBank = rItemId and addon.Bank and addon.Bank.GetStock(rItemId) > 0
            local ahData  = rItemId and addon.AH and addon.AH.GetListingsFor(rItemId)
            local hasAH   = ahData and (ahData.count or 0) > 0 and r.name and r.name ~= ""

            if hasBank then
                rf.bankBtn:SetScript("OnClick", function()
                    addon.Bank.ShowRequestDialog(rItemId, r.name or "", rLink)
                end)
            end
            if hasAH then
                local rName = r.name
                rf.ahBtn:SetScript("OnClick", function()
                    addon.AH.SearchFor(rName)
                end)
            end

            -- Dynamic anchoring: order is [Bank] [AH] (left to right).
            -- count→bank gap is 8 (not 4) to balance against bank→ah; see
            -- the matching comment in FillShoppingListSection above for why.
            rf.bankBtn:ClearAllPoints()
            rf.ahBtn:ClearAllPoints()
            if hasBank then
                rf.bankBtn:SetPoint("LEFT", rf.countLbl, "RIGHT", 8, 0)
                rf.bankBtn:Show()
                if hasAH then
                    rf.ahBtn:SetPoint("LEFT", rf.bankBtn, "RIGHT", 4, 0)
                    rf.ahBtn:Show()
                else
                    rf.ahBtn:Hide()
                end
            else
                rf.bankBtn:Hide()
                if hasAH then
                    rf.ahBtn:SetPoint("LEFT", rf.countLbl, "RIGHT", 8, 0)
                    rf.ahBtn:Show()
                else
                    rf.ahBtn:Hide()
                end
            end

            rf:Show()
        end
        for i = #reagents + 1, #self._dpReagPool do
            self._dpReagPool[i]:Hide()
        end
    else
        self._dpReagHdr:Hide()
        for _, f in ipairs(self._dpReagPool) do f:Hide() end
    end

    -- ── Known By ──────────────────────────────────────────────────────────
    yOff = yOff - 4
    self._dpCraftHdr:ClearAllPoints()
    self._dpCraftHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
    self._dpCraftHdr:Show()
    yOff = yOff - DP_ROW

    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
    local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
    local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF")

    for _, f in ipairs(self._dpCraftPool) do f:Hide() end

    local crafters = entry.crafters or {}

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

    if #crafters > 0 then
        for i, c in ipairs(crafters) do
            local cf = self:GetDetailCraftRow(i)
            cf:ClearAllPoints()
            cf:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
            cf:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
            yOff = yOff - DP_ROW

            local col = c.isYou and colorYou or (c.online and colorOnline or colorOffline)
            cf.lbl:SetText(col .. c.name .. "|r")

            if not c.isYou then
                local charKey   = c.charKey or c.name
                local shortName = c.name
                cf:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(cf)
                    GameTooltip:SetText(shortName, 1, 1, 1)
                    GameTooltip:AddLine(L["TooltipWhisperRightClick"], 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                cf:SetScript("OnLeave", function() GameTooltip:Hide() end)
                cf:SetScript("OnClick", function(_, btn)
                    if btn == "RightButton" then
                        if Menu and Menu.CreateContextMenu then
                            Menu.CreateContextMenu(cf, function(_, root)
                                root:CreateTitle(shortName)
                                root:CreateButton(shortName, function() openWhisper(charKey) end)
                            end)
                        else
                            openWhisper(charKey)
                        end
                    end
                end)
            else
                cf:SetScript("OnEnter", nil)
                cf:SetScript("OnLeave", nil)
                cf:SetScript("OnClick", nil)
            end
            cf:Show()
        end
        for i = #crafters + 1, #self._dpCraftPool do
            self._dpCraftPool[i]:Hide()
        end
    else
        local cf = self:GetDetailCraftRow(1)
        cf:ClearAllPoints()
        cf:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
        cf:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        cf.lbl:SetText("|cffaaaaaa" .. L["NoDataYet"] .. "|r")
        cf:SetScript("OnEnter", nil)
        cf:SetScript("OnLeave", nil)
        cf:SetScript("OnClick", nil)
        cf:Show()
        yOff = yOff - DP_ROW
        for i = 2, #self._dpCraftPool do self._dpCraftPool[i]:Hide() end
    end

    -- Resize content to fit all rows so the scrollbar range is correct.
    content:SetHeight(math.abs(yOff) + DP_PAD)
end

-- Show the "select a recipe" placeholder.
function BrowserTab:ClearDetail()
    if not self._detailOuter then return end
    if self._dpSF  then self._dpSF:Hide() end
    if self._dpPH  then self._dpPH:Show() end
    self._selectedEntry = nil
end

-- ---------------------------------------------------------------------------
-- Crafter-column text fitting
-- ---------------------------------------------------------------------------
-- Show as many crafter names as the column's CURRENT width allows, then a greyed
-- "+N" for the rest — instead of a fixed 2 names. The crafter fontstring is
-- anchored LEFT 186 / RIGHT -56, so it widens as the user drags the window;
-- measuring against its live width (and recomputing on WINDOW_RESIZED) makes the
-- summary fill the available space. Always shows at least one name (clipped by
-- the word-wrap-off fontstring if even that overflows a very narrow column).
local function fitCrafterText(label, crafters, colOnline, colOffline, colYou)
    local total = #crafters
    if total == 0 then
        label:SetText("")
        return
    end

    -- Pre-colour each name once.
    local names = {}
    for ci = 1, total do
        local c   = crafters[ci]
        local col = c.isYou and colYou or (c.online and colOnline or colOffline)
        names[ci] = col .. c.name .. "|r"
    end

    -- Available width = the fontstring's laid-out width (tracks the window via its
    -- LEFT/RIGHT anchors). Before the first layout it can read 0 — fall back to the
    -- old fixed 2-name summary until a later paint has a real width.
    local availW = label:GetWidth() or 0
    if availW <= 1 then
        local shown  = math.min(2, total)
        local suffix = (total > shown) and (" |cffaaaaaa+" .. (total - shown) .. "|r") or ""
        label:SetText(table.concat(names, ", ", 1, shown) .. suffix)
        return
    end

    -- Greedily include names while the rendered string still fits, reserving room
    -- for the "+N" suffix at each step. Adding a name grows the visible width
    -- monotonically, so the first overflow is the stopping point.
    local best
    for n = 1, total do
        local suffix    = (n < total) and (" |cffaaaaaa+" .. (total - n) .. "|r") or ""
        local candidate = table.concat(names, ", ", 1, n) .. suffix
        label:SetText(candidate)
        if label:GetStringWidth() <= availW then
            best = candidate
        else
            label:SetText(best or candidate)   -- at least one name (clipped if needed)
            return
        end
    end
    -- Everything fit; label already holds the full string from the final loop pass.
end

-- ---------------------------------------------------------------------------
-- Virtual row update
-- ---------------------------------------------------------------------------

function BrowserTab:UpdateVirtualRows()
    local scroll   = self._scroll
    local recipes  = self._recipes
    if not scroll or not recipes or not self._pool then return end

    local status   = scroll.status or scroll.localstatus
    local offset   = status.offset or 0
    local firstIdx = math.floor(offset / ROW_HEIGHT)

    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
    local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
    local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF")

    for i = 1, POOL_SIZE do
        local f         = self._pool[i]
        local recipeIdx = firstIdx + i
        local entry     = recipes[recipeIdx]
        if entry then
            addon.GUI.ApplyRowStripe(f, recipeIdx)
            f._entry = entry
            f.icon:SetTexture(entry.icon)

            local colorHex = type(entry.itemLink) == "string" and entry.itemLink:match("|c(ff%x%x%x%x%x%x)|H")
            f.nameLbl:SetText(colorHex and ("|c" .. colorHex .. entry.name .. "|r") or entry.name)

            -- Crafter summary: fit as many names as the (drag-resizable) column
            -- width allows, then a greyed "+N" for the rest.
            fitCrafterText(f.crafterLbl, entry.crafters, colorOnline, colorOffline, colorYou)

            -- Bank button: show if the crafted item itself has bank stock.
            -- Keyed by craftedItemId — entry.id is the recipe's spell id, so
            -- the old `not entry.isSpell and entry.id` asked the bank for
            -- stock of whatever item shares that number.
            local craftedId = entry.craftedItemId
            if addon.Bank and craftedId and addon.Bank.GetStock(craftedId) > 0 then
                f.bankBtn:SetScript("OnClick", function()
                    addon.Bank.ShowRequestDialog(craftedId, entry.name or "", entry.itemLink)
                end)
                f.bankBtn:Show()
            else
                f.bankBtn:Hide()
            end

            -- Highlight selected recipe
            if self._selectedEntry and self._selectedEntry.id == entry.id then
                f:LockHighlight()
            else
                f:UnlockHighlight()
            end

            local y = -((recipeIdx - 1) * ROW_HEIGHT)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT",  scroll.content, "TOPLEFT",  0, y)
            f:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, y)
            f:Show()
        else
            f._entry = nil
            f:Hide()
        end
    end
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

    -- Re-fit the crafter column when the window is dragged wider/narrower so the
    -- visible-name count tracks the new width. The crafter fontstrings stretch
    -- live via their LEFT/RIGHT anchors, but the name COUNT only recomputes when
    -- the rows repaint — so nudge a repaint on the debounced resize callback.
    addon:RegisterCallback("WINDOW_RESIZED", function()
        local mw = addon.MainWindow
        if mw and mw.frame and mw.activeTab == "browser" and BrowserTab._pool then
            BrowserTab:UpdateVirtualRows()
        end
    end)

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
