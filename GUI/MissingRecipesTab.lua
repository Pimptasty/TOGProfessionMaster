-- TOG Profession Master — Missing Recipes Tab
-- Standalone "what scrolls am I missing?" view, modeled on PersonalShopper's
-- Collector. Compares the static recipe universe (Data/Recipes/<Profession>.lua)
-- against gdb.recipes[profId][recipeId].crafters[charKey] to compute which
-- AH-obtainable scrolls a given character has yet to learn.
--
-- The recipe + source DBs are loaded as plain Lua tables in TOC order; this
-- file consumes them read-only. No new sync traffic, no scanner changes — the
-- "known" half of the comparison reuses the data Scanner.lua already populates.

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local MissingRecipesTab = {}
addon.MissingRecipesTab = MissingRecipesTab

-- Window size policy — locked to the SAME dimensions as CooldownsTab so
-- switching between Missing and Cooldowns produces no visible jump.
-- MainWindow reads this on tab switch and on Open. Keep these in sync
-- with CooldownsTab.WINDOW_SIZE — that's the whole point.
MissingRecipesTab.WINDOW_SIZE = { width = 720, height = 500, locked = true }

-- Profession display names come from the shared addon.PROF_NAMES table
-- in TOGProfessionMaster.lua (covers everything Vanilla through MoP).
-- Per-version filtering happens via addon.IsProfessionAvailable in the
-- dropdown build below — a profession that doesn't exist on the current
-- client (Jewelcrafting on Vanilla, Inscription on Vanilla / TBC) is
-- hidden even if the character somehow has stale skill data for it cached.

-- Source key → locale key, and the order that drives display order on each row.
-- Canonical copies live in GUI/SharedWidgets.lua (loaded earlier per the TOC),
-- because the recipe-detail tooltip block renders the same kinds and the two
-- silently disagreeing is exactly the drift worth avoiding: a source kind added
-- to one list would render as a raw lowercase key in the other.
local SRC_LABELS = addon.ItemLink.SOURCE_LABELS
local SRC_ORDER  = addon.ItemLink.SOURCE_ORDER

-- Tab state — survives tab switches but resets on UI reload.
MissingRecipesTab._scope           = nil      -- "personal" | "guild" sub-tab
MissingRecipesTab._charKey         = nil
MissingRecipesTab._profId          = 0
MissingRecipesTab._searchText      = ""
MissingRecipesTab._includeTrainer  = false
MissingRecipesTab._canLearnOnly    = false
MissingRecipesTab._showAll         = false   -- show every recipe (known + missing)
-- Sort state for the clickable Recipe / Skill / Sources headers. Defaults to
-- skill ascending, which matches BuildMissingList's natural order (and shows the
-- arrow on the Skill column on first open). "recipe" sorts by display name,
-- "source" by the formatted sources text.
MissingRecipesTab._sortCol         = "skill"
MissingRecipesTab._sortAsc         = true
MissingRecipesTab._container       = nil
MissingRecipesTab._listSection     = nil
MissingRecipesTab._customTip       = nil  -- lazy-init via GetCustomTip

-- v0.7.5: Private GameTooltip instance owned by this tab. RecipeMaster
-- and similar addons hook OnTooltipSetItem / OnTooltipSetSpell on the
-- GLOBAL _G.GameTooltip via GameTooltip:HookScript — those handlers
-- belong to that specific frame instance. A separate GameTooltip frame
-- inheriting from the same "GameTooltipTemplate" virtual template (the
-- one _G.GameTooltip itself is built from — see
-- Blizzard_GameTooltip/Mainline/GameTooltip.xml lines 4 and 249) gets
-- the full Blizzard API, full appearance, but a separate script handler
-- registry. RecipeMaster's broken cachedRecipes nil-index at
-- RecipeHandler.lua:43 never runs because OnTooltipSetItem doesn't fire
-- on this frame.
--
-- Lazy because CreateFrame requires UIParent to exist, which isn't
-- guaranteed at file-load time on Vanilla (the AddOn loader can run
-- before the UI is fully constructed in some load orders).
function MissingRecipesTab:GetCustomTip()
    if not self._customTip then
        self._customTip = CreateFrame("GameTooltip", "TOGPMMissingRecipeTip",
                                      UIParent, "GameTooltipTemplate")
    end
    return self._customTip
end

-- ---------------------------------------------------------------------------
-- Pure helpers
-- ---------------------------------------------------------------------------

local function HasNonTrainerSource(srcEntry)
    if not srcEntry then return false end
    for k in pairs(srcEntry) do
        if k ~= "trainer" then return true end
    end
    return false
end

local function FormatSources(srcEntry, includeTrainer)
    -- No source data at all → the recipe is in the universe (wago.tools knows
    -- about it) but no emulator we ship from catalogs where it comes from.
    -- Surface it with an explicit "Unknown" tag so the user still sees the
    -- recipe is missing and can look it up externally. Used heavily for
    -- MoP-introduced recipes since we don't have a MoP emulator source yet.
    if not srcEntry then return L["MissingSrcUnknown"] end
    local parts, seen = {}, {}
    for _, key in ipairs(SRC_ORDER) do
        if srcEntry[key] and (key ~= "trainer" or includeTrainer) then
            table.insert(parts, L[SRC_LABELS[key]] or key)
            seen[key] = true
        end
    end
    -- Catch any source key not in SRC_ORDER (unknown future sources).
    for k in pairs(srcEntry) do
        if not seen[k] and SRC_LABELS[k] == nil and (k ~= "trainer" or includeTrainer) then
            table.insert(parts, L["MissingSrcOther"])
            break
        end
    end
    -- srcEntry exists but every kind in it is filtered (e.g. trainer-only
    -- with the toggle off): fall through to "Unknown" so the row still
    -- displays something rather than an empty cell.
    if #parts == 0 then return L["MissingSrcUnknown"] end
    return table.concat(parts, ", ")
end

local function CharShortName(charKey)
    return charKey:match("^([^%-]+)") or charKey
end

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

-- Return list of charKeys that belong to this account and have any tracked
-- profession data, regardless of which guild bucket the data lives in. The
-- currently-logged-in toon is always included even if it has not opened a
-- trade-skill window yet.
local function GetCharactersWithProfessions()
    -- v0.7.0: gdb.skills is a single flat table keyed by charKey (no more
    -- per-guild buckets). Walk it once.
    local list, seen = {}, {}
    local gdb = addon:GetGuildDb()
    if gdb and gdb.skills then
        for charKey, profMap in pairs(gdb.skills) do
            if not seen[charKey]
               and addon:IsMyCharacter(charKey)
               and profMap and next(profMap) then
                table.insert(list, charKey)
                seen[charKey] = true
            end
        end
    end
    local myKey = addon:GetCharacterKey()
    if not seen[myKey] then table.insert(list, myKey) end

    table.sort(list, function(a, b)
        if a == myKey then return true end
        if b == myKey then return false end
        return a < b
    end)
    return list
end

-- Return profIds the given charKey has tracked skills for, restricted to
-- (a) professions we have a static recipe DB for AND (b) professions
-- that exist on the current client version. The version check guards
-- against stale skill data — e.g. a character whose Wrath-era data
-- lingers in the SavedVariables shouldn't surface Inscription on a
-- Vanilla client.
local function GetProfessionsForCharacter(charKey)
    -- v0.7.0: skills are at the top level (gdb.skills[charKey][profId]).
    local gdb = addon:GetGuildDb()
    local charSkills = gdb and gdb.skills and gdb.skills[charKey]
    if not charSkills then return {} end
    local out = {}
    for profId in pairs(charSkills) do
        if addon.recipeDB and addon.recipeDB[profId]
           and addon.IsProfessionAvailable(profId) then
            table.insert(out, profId)
        end
    end
    table.sort(out, function(a, b)
        return (addon.PROF_NAMES[a] or tostring(a)) < (addon.PROF_NAMES[b] or tostring(b))
    end)
    return out
end

-- Guild scope: profIds any guild character has skill in OR has crafters/recipes
-- for — i.e. professions the guild actually practices — restricted (as above) to
-- professions we ship a recipe DB for and that exist on this client. These are
-- the professions worth showing a guild-wide "what are we missing?" list for;
-- a profession nobody in the guild has would just be its entire recipe universe.
local function GetGuildProfessions()
    local gdb = addon:GetGuildDb()
    if not gdb then return {} end
    local seen = {}
    -- Any character's tracked skills.
    if gdb.skills then
        for _, profMap in pairs(gdb.skills) do
            for profId in pairs(profMap) do seen[profId] = true end
        end
    end
    -- Any profession with at least one known recipe in the guild.
    if gdb.recipes then
        for profId, recps in pairs(gdb.recipes) do
            if next(recps) ~= nil then seen[profId] = true end
        end
    end
    local out = {}
    for profId in pairs(seen) do
        if addon.recipeDB and addon.recipeDB[profId]
           and addon.IsProfessionAvailable(profId) then
            table.insert(out, profId)
        end
    end
    table.sort(out, function(a, b)
        return (addon.PROF_NAMES[a] or tostring(a)) < (addon.PROF_NAMES[b] or tostring(b))
    end)
    return out
end

-- Virtual-scroll constants. Mirrors BrowserTab's approach: a raw frame pool
-- of POOL_SIZE rows is reused as the user scrolls, so total widget count
-- stays bounded regardless of list size. AceGUI's layout pass scales badly
-- past a few hundred children, so we pay the layout cost on POOL_SIZE rows
-- only — never on the full result.
local ROW_HEIGHT = 16
local POOL_SIZE  = 35

-- Skill cap each rank-up book grants. Used to filter rank books out of
-- the missing list when the character's skillMax is already at or above
-- that cap — the only way the character could have raised their cap
-- past a rank's threshold is to have consumed the book. There's no WoW
-- API to detect "did the player use this item" so skillMax is the proxy.
--
-- Currently only Cooking, First Aid, and Fishing have rank-book entries
-- in our static recipe DB (other professions advance via trainer); the
-- map is exhaustive across all expansion ranks anyway in case future
-- data files add more.
-- Blacksmithing weapon sub-spec → parent spec. Master Swordsmith / Hammersmith
-- / Axesmith each build on Weaponsmith, so a sub-spec smith can ALSO learn the
-- general Weaponsmith (9787) recipes. Every other profession spec (LW, Tailoring,
-- Engineering, Armorsmith) is a mutually-exclusive leaf with no parent.
local SPEC_PARENT = {
    [17039] = 9787,  -- Master Swordsmith  → Weaponsmith
    [17040] = 9787,  -- Master Hammersmith → Weaponsmith
    [17041] = 9787,  -- Master Axesmith    → Weaponsmith
}

local RANK_CAPS = {
    ["Journeyman"]               = 150,
    ["Expert"]                   = 225,
    ["Artisan"]                  = 300,
    ["Master"]                   = 375,
    ["Grand Master"]             = 450,
    ["Illustrious Grand Master"] = 525,
    ["Zen Master"]               = 600,
}

-- Build the missing-recipe list for (charKey, profId). Returns the full
-- unfiltered set sorted by required skill — search filtering is applied at
-- render time via GetItemInfoInstant (which does NOT trigger an async load),
-- and the row count is capped during render. Item-name resolution itself
-- happens per-row inside FillList so we only ever pay for the visible slice.
-- scope: "personal" (default) counts a recipe as known when THIS charKey crafts
-- it; "guild" counts it known when ANY guild character crafts it — so the guild
-- list surfaces recipes NObody in the guild has. Guild scope has no single
-- character, so the "Can learn now" skill gate is forced off.
local function BuildMissingList(charKey, profId, includeTrainer, canLearnOnly, showAll, scope)
    local guildScope = (scope == "guild")
    if not profId or profId == 0 then return {} end
    if not guildScope and not charKey then return {} end
    if guildScope then canLearnOnly = false end
    local recipes = addon.recipeDB and addon.recipeDB[profId]
    if not recipes then return {} end

    -- Hoist sources / spec lookups out of the per-recipe loop.
    local sources     = (addon.sourceDB and addon.sourceDB[profId]) or {}

    -- Pre-build a set of every spell-id the character is known to craft for
    -- this profession. There are TWO independent reasons the previous
    -- per-call lookup `bucket.recipes[profId][recipeId]` returned false for
    -- recipes the player actually knew:
    --
    --   1. (v0.4.7 fix) cross-bucket scatter: a character's scanned recipes
    --      live in whichever guild bucket was active at scan time, which
    --      may not be the bucket their skills are cached in. We walk all
    --      buckets here.
    --
    --   2. (v0.5.0 fix) keyspace mismatch: Scanner:ScanTradeSkill at
    --      Scanner.lua:776 stores each recipe row keyed by what
    --      ExtractTradeSkillId returns, which is the SPELL id for Enchanting
    --      (whose recipe links carry enchant:SPELLID) but the CRAFTED ITEM
    --      id for every other profession (whose links carry item:ITEMID for
    --      the produced item). Meanwhile our v0.5.0 recipeDB is uniformly
    --      keyed by recipe SPELL id (from wago.tools SkillLineAbility.Spell).
    --      A direct `profRecipes[spellId]` lookup misses every non-Enchanting
    --      recipe because the stored key is the item id, not the spell id.
    --      Scanner DOES populate rd.spellId as a field on every entry (line
    --      743 + 856 — looked up via spellNameCache during the scan), so we
    --      index both the table KEY and the rd.spellId FIELD into one set.
    --      Lookup against that set is O(1) and works for all professions.
    -- v0.7.0: gdb.recipes is a single flat table (no more per-guild buckets).
    -- crafters[charKey] now holds a guild tag string (truthy) instead of the
    -- old boolean `true`. Either way the presence check is the same.
    local knownSpells = {}
    local gdb         = addon:GetGuildDb()
    local profRecipes = gdb and gdb.recipes and gdb.recipes[profId]
    if profRecipes then
        local function markKnown(id)
            if id ~= nil then
                local n = tonumber(id)
                if n then knownSpells[n] = true end
            end
        end
        for recipeKey, rd in pairs(profRecipes) do
            -- "Known" = this character crafts it (personal) OR anyone in the
            -- guild crafts it (guild scope → any non-empty crafter set). Guild
            -- scope therefore leaves only recipes NObody in the guild has.
            local isKnown
            if guildScope then
                -- "Known" only if a crafter in the CURRENT guild scope has it —
                -- a recipe that merely one of your cross-guild alts (or a stale
                -- foreign crafter) knows must still count as missing for THIS
                -- guild. See addon:IsInCurrentGuildScope.
                isKnown = false
                if rd and rd.crafters then
                    for ck in pairs(rd.crafters) do
                        if addon:IsInCurrentGuildScope(ck) then isKnown = true; break end
                    end
                end
            else
                isKnown = rd and rd.crafters and rd.crafters[charKey]
            end
            if isKnown then
                -- Normalize all known key shapes into one set. Historical
                -- data can contain spell IDs or crafted-item IDs depending on
                -- client/version at scan time.
                markKnown(recipeKey)
                -- If recipeKey is a crafted-item id, map it back to spell id.
                markKnown(addon.GetSpellIdForCraftedItem and addon:GetSpellIdForCraftedItem(profId, recipeKey))
                -- Also index explicit scanner-side ids when present.
                markKnown(rd.spellId)
                markKnown(rd.teaches)
                markKnown(rd.itemId)
                markKnown(rd.craftedItemId)
                -- Legacy cross-reference via recipeDB metadata.
                local meta = addon.recipeDB and addon.recipeDB[profId]
                                            and addon.recipeDB[profId][recipeKey]
                if meta and meta.teaches then
                    markKnown(meta.teaches)
                end
                if meta and meta.craftedItemId then
                    markKnown(meta.craftedItemId)
                end
            end
        end
    end
    local function knownByChar(recipeId)
        return knownSpells[recipeId] == true
    end

    -- skillRank + skillMax from the flat skills table.
    --   skillRank is consumed by the "Can learn now" filter below.
    --   skillMax gates the rank-book RANK_CAPS check (Expert / Artisan / etc.).
    local skillRank, skillMax = 0, 0
    if gdb and gdb.skills and gdb.skills[charKey] and gdb.skills[charKey][profId] then
        skillRank = gdb.skills[charKey][profId].skillRank or 0
        skillMax  = gdb.skills[charKey][profId].skillMax  or 0
    end

    local out = {}

    -- On TBC clients, also hide recipes from later TBC phases than the user
    -- has set in Settings. The recipe DB ships a `phase` field on Phase 2+
    -- TBC recipes (Sunwell jewelcrafting, Black Temple drops, Shattered Sun
    -- quartermaster patterns, etc.) sourced at build time from ATT. A user
    -- on Phase 2 (current Anniversary live state) shouldn't see Phase 3/4
    -- recipes in the Missing list because the content gating them isn't open
    -- yet. Recipes WITHOUT a phase field show on every phase (safe default —
    -- they're launch/early content). Other expansions don't ship phase tags
    -- yet, so the filter is gated on isTBC.
    local tbcPhaseLimit
    if addon.isTBC and Ace and Ace.db and Ace.db.profile then
        tbcPhaseLimit = Ace.db.profile.tbcAnniversaryPhase or 2
    end

    -- Per-client expansion index. The shipped recipeDB tags each recipe
    -- with `minExpansion` = the earliest build (1=Vanilla, 2=TBC, 3=Wrath,
    -- 4=Cata, 5=MoP) where the spell first appeared in wago.tools
    -- SkillLineAbility. We hide recipes whose minExpansion > the current
    -- client's expansion index — that's how Wrath transmute spell 53771
    -- gets blocked on a TBC client even though its raw difficulty values
    -- might look TBC-compatible (wago.tools' MoP build inherits every
    -- spell ever shipped, so a forward-union of all 5 builds means Wrath /
    -- Cata / MoP spells appear in our DB; the minExpansion tag keeps them
    -- from displaying on earlier clients).
    --
    -- Also keep the requiredSkill > clientMaxSkill filter as belt-and-
    -- suspenders — minExpansion is the primary gate but a misclassified
    -- recipe still gets caught if its required-skill exceeds the cap.
    local clientExp, clientMaxSkill
    if     addon.isVanilla then clientExp, clientMaxSkill = 1, 300
    elseif addon.isTBC     then clientExp, clientMaxSkill = 2, 375
    elseif addon.isWrath   then clientExp, clientMaxSkill = 3, 450
    elseif addon.isCata    then clientExp, clientMaxSkill = 4, 525
    elseif addon.isMoP     then clientExp, clientMaxSkill = 5, 600
    else                        clientExp, clientMaxSkill = 5, 600
    end

    -- Even with lib-backed recipe data, keep defensive client-validity gates
    -- enabled: Season-of-Discovery and Anniversary content can still leak into
    -- Era/HC clients through shared 1.15 data tables.
    local libData = addon.recipeDBFromLib

    -- SoD/Anniversary recipes leak into the Vanilla LibProfessionDB set (the 1.15
    -- client's tables carry them), and they're not learnable on regular Era / HC.
    -- Their spell IDs sit far above any real Vanilla recipe (<~30k) — every SoD
    -- formula observed is 400k+ — so on a Vanilla client that ISN'T running
    -- Season of Discovery, hide that ID range. This runs even on lib-sourced data
    -- (the cross-expansion gates below are skipped for it; this one is not).
    local SOD_RECIPE_ID_MIN = 200000
    local hideSoD = (clientExp == 1) and not addon:IsSoD()
    -- TBC cooking recipe IDs that contaminated Vanilla ProfessionDB data
    -- (exist in 1.15 client spell tables but can't be learned on Era).
    local TBC_COOKING_BLACKLIST = {
        [30047] = true,  -- Crystal Throat Lozenge
    }

    for spellId, data in pairs(recipes) do
        local skip = false
        if hideSoD and spellId >= SOD_RECIPE_ID_MIN then
            skip = true
        end
        -- Non-SoD Vanilla: require spell presence for all recipes.
        if hideSoD and GetSpellInfo and not GetSpellInfo(spellId) then
            skip = true
        end
        -- Non-SoD Vanilla cooking: blacklist known TBC recipes that leaked
        -- into ProfessionDB Vanilla data (exist in 1.15 client but aren't
        -- obtainable on Era/Anniversary).
        if hideSoD and profId == 185 and TBC_COOKING_BLACKLIST[spellId] then
            skip = true
        end
        if data.minExpansion and data.minExpansion > clientExp then
            -- Recipe was first introduced in a later expansion than this
            -- client supports. Wrath transmute on TBC, Cata recipe on
            -- Wrath, etc. — never learnable here regardless of phase or
            -- skill cap. PRIMARY cross-expansion gate.
            skip = true
        elseif (not data.minExpansion) and clientExp == 1 and spellId > 25000 then
            -- Defensive gate for Classic Era against untagged post-Vanilla
            -- recipes. Most Vanilla recipe spell IDs are in the 2000-25000
            -- range, so untagged spellId > 25000 is USUALLY post-Vanilla.
            -- Require BOTH spell presence AND item presence to pass —
            -- TBC recipes like Crystal Throat Lozenge (spell 30047) have
            -- items in shared 1.15 tables but no spell on Era clients.
            local spellExists = GetSpellInfo and GetSpellInfo(spellId) ~= nil
            local itemExists = GetItemInfoInstant and (
                (data.itemId        and GetItemInfoInstant(data.itemId)) or
                (data.craftedItemId and GetItemInfoInstant(data.craftedItemId)))
            if not (spellExists and itemExists) then
                skip = true
            end
        elseif data.requiredSkill and data.requiredSkill > clientMaxSkill then
            -- Recipe is from a future expansion the current client can't
            -- support. Hide it; the player will see it once they're on a
            -- later TOC variant.
            skip = true
        elseif tbcPhaseLimit and data.phase and data.phase > tbcPhaseLimit then
            -- TBC client: recipe is gated by a content phase that hasn't
            -- gone live yet (e.g. Sunwell content while Anniversary is on
            -- Phase 2). User bumps Settings → TBC Anniversary phase when
            -- Blizzard advances. Recipes without a `phase` field are
            -- always shown (launch / unidentified content).
            skip = true
        elseif data.season then
            skip = true
        elseif type(data.teaches) == "string" and RANK_CAPS[data.teaches] then
            -- Rank-up book (e.g. "Expert First Aid" raises max from 150
            -- to 225, "Artisan First Aid" from 225 to 300). The character's
            -- skillMax is the only proxy we have for "did they consume
            -- this book" — there's no WoW API to detect that. If their
            -- skillMax is already at or above the rank's cap they must
            -- have used the book to get there.
            if skillMax >= RANK_CAPS[data.teaches] then
                skip = true
            end
        end

        -- Known-recipe filter — additive guard, NOT an elseif in the chain
        -- above. Same fix as the "Can learn now" guard below: an earlier
        -- version-gate branch that evaluates true but doesn't skip (the untagged
        -- `spellId > 25000` Classic-Era existence gate is the culprit) would
        -- short-circuit the elseif chain and bypass this filter — so recipes the
        -- character/guild already knows wrongly showed as missing (Smoked
        -- Sagefish, spell 25704 > 25000, was the reported case). As an additive
        -- guard it always runs for recipes that survive the version gates.
        if not skip and (not showAll)
           and (knownByChar(spellId)
                or (data.teaches and knownByChar(data.teaches))
                or (data.craftedItemId and knownByChar(data.craftedItemId))) then
            skip = true
        end

        -- Specialization gate — hide recipes this character's profession spec
        -- can never learn (a Tribal leatherworker can't learn Elemental /
        -- Dragonscale patterns). data.requiredSpec is the spec spell shipped in
        -- the recipe DB (ItemSparse.RequiredAbility), which equals the spell
        -- IsSpellKnown returns, so it compares directly against the recorded
        -- spec. Personal scope only (guild scope is guild-wide); only when we
        -- actually KNOW this character's spec (else stay permissive); off under
        -- Show All. Additive guard, same rationale as the filters around it.
        if not skip and not guildScope and (not showAll) and data.requiredSpec then
            local charSpecs = gdb and gdb.specializations and gdb.specializations[charKey]
            local mySpec    = charSpecs and charSpecs[profId]
            if mySpec then
                local req = data.requiredSpec
                -- Learnable when it matches my spec, or my spec is a sub-spec of
                -- it (a Swordsmith can make general Weaponsmith recipes).
                if req ~= mySpec and req ~= SPEC_PARENT[mySpec] then
                    skip = true
                end
            end
        end

        -- "Can learn now" toolbar filter — additive guard, runs AFTER the
        -- elseif chain above so it never bypasses knownByChar / rank-book /
        -- season / etc. v0.7.5's first cut wired this as another
        -- `elseif canLearnOnly` branch inside the chain, which short-
        -- circuited the entire chain when the flag was on — every recipe
        -- the user already knows reappeared in the "missing" list (~120
        -- extra rows). Pulling it out of the chain restores the prior
        -- semantics: this filter only TIGHTENS the visible set, never
        -- relaxes earlier rules.
        --
        -- Gate resolution: data.requiredSkill when present, else
        -- data.difficulty[1] (orange threshold = lowest castable rank).
        -- ~13% of Blacksmithing and ~16% of Tailoring recipes ship with
        -- no requiredSkill; falling back to difficulty[1] closes that
        -- coverage gap. If BOTH are nil the row still passes (truly
        -- unknown — same intentional permissive behavior).
        if not skip and canLearnOnly then
            local gate = data.requiredSkill
                      or (data.difficulty and data.difficulty[1])
            if gate and gate > skillRank then
                skip = true
            end
        end

        if not skip then
            local srcEntry = sources[spellId]
            -- v0.5.0: surface every recipe in the universe, even those without
            -- a known source entry. Previously we filtered out anything without
            -- a srcEntry on the assumption that the recipe wasn't actually
            -- obtainable; v0.5.0's authoritative recipeDB makes that assumption
            -- wrong (we know the recipe exists from Blizzard's DBC even when
            -- no emulator catalogs the NPC). Show the row anyway with an
            -- "Unknown" source tag (handled in FormatSources). Users still get
            -- the value of "I'm missing this recipe" even when we can't tell
            -- them where to get it. This is the main lever closing the
            -- visibility gap on MoP-introduced recipes for now.
            --
            -- The includeTrainer toggle still hides recipes whose ONLY known
            -- source is a trainer — those add noise to the "AH-hunting"
            -- workflow the tab is built around (a trainer is always
            -- available). The toggle is unchanged in scope and effect.
            local isTrainerOnly = srcEntry and not HasNonTrainerSource(srcEntry)
            if isTrainerOnly and not includeTrainer then
                -- skip — trainer-only entries are hidden when the toggle is off
            else
                table.insert(out, {
                    spellId       = spellId,
                    itemId        = data.itemId,  -- recipe-scroll item id (nil for trainer-only)
                    craftedItemId = data.craftedItemId,  -- crafted (produced) item id; used for icon
                    teaches       = data.teaches,
                    -- requiredSkill: nil when neither the recipe scroll's
                    -- RequiredSkillRank nor the trainer SQL's ReqSkillRank
                    -- supplied a value. UI renders "-" so the data gap is
                    -- visible. Do NOT default to 0 here — that would let
                    -- the sort treat "unknown" as "lowest skill" and bury
                    -- those recipes at the top of the list.
                    requiredSkill = data.requiredSkill,
                    tiers         = data.difficulty,  -- {orange,yellow,green,grey} skill breakpoints
                    effect        = addon:GetCraftedItemStatText(data.craftedItemId) or data.effect,  -- crafted gear/consumable stats (LibItemDB) win; enchant effect (ProfessionDB) is the fallback
                    known         = knownByChar(spellId)
                                    or (data.teaches and knownByChar(data.teaches))
                                    or (data.craftedItemId and knownByChar(data.craftedItemId))
                                    or false,
                    sources       = srcEntry,
                    sourcesText   = FormatSources(srcEntry, includeTrainer),
                })
            end
        end
    end

    -- Sort: known skill ascending, then unknown (nil) recipes last, then
    -- by spellId for stable ties. Nil-safety matters because most rank
    -- comparisons will involve at least one nil after the requiredSkill
    -- field became optional — `nil < number` would error otherwise.
    table.sort(out, function(a, b)
        local ar, br = a.requiredSkill, b.requiredSkill
        if ar ~= br then
            if ar == nil then return false end
            if br == nil then return true end
            return ar < br
        end
        return a.spellId < b.spellId
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- Tooltip helpers
-- All tooltip anchoring goes through addon.Tooltip.Owner per CLAUDE.md.
-- ---------------------------------------------------------------------------

-- Thin alias kept for the existing call sites below; the real work
-- (including the Dropdown/EditBox label-area mouse trick) lives in the
-- shared addon.GUI.AttachTooltip in GUI/SharedWidgets.lua.
-- ---------------------------------------------------------------------------
-- Offline-test seam — the frame-free half (missing-set computation, source
-- formatting, the character/profession pickers). `local` only because nothing
-- outside the file calls them; not used at runtime.
-- See Tests/missingrecipes_spec.lua.
-- ---------------------------------------------------------------------------
MissingRecipesTab._BuildMissingList             = BuildMissingList
MissingRecipesTab._FormatSources                = FormatSources
MissingRecipesTab._HasNonTrainerSource          = HasNonTrainerSource
MissingRecipesTab._CharShortName                = CharShortName
MissingRecipesTab._GetCharactersWithProfessions = GetCharactersWithProfessions
MissingRecipesTab._GetProfessionsForCharacter   = GetProfessionsForCharacter
MissingRecipesTab._GetGuildProfessions          = GetGuildProfessions

local function AttachWidgetTooltip(widget, title, desc)
    addon.GUI.AttachTooltip(widget, title, desc)
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

-- Sub-tabs use an AceGUI TabGroup (My Character / Guild), matching the log
-- sub-tabs in TOG Tools. Draw builds the strip; DrawScope renders the active
-- scope's toolbar + result list INTO the TabGroup's content.
--
-- DrawScope's result-list anchoring installs a LayoutFinished override on the
-- TabGroup (its content container). AceGUI pools widgets globally and does NOT
-- clear such overrides on release, so on teardown we restore the TabGroup's
-- CLASS LayoutFinished (captured once from a fresh instance) — otherwise the
-- override would bleed into whatever addon next acquires that pooled TabGroup and
-- break its auto-size. (The MAIN tab container is protected differently:
-- MainWindow nils its LayoutFinished on every tab switch.)
local _TG_CLASS_LAYOUTFINISHED  -- captured once from a fresh TabGroup

function MissingRecipesTab:Draw(container)
    container:SetLayout("Fill")
    self._container = container

    -- Persisted sub-tab scope (Personal / Guild) + dropdown selections, via the
    -- shared addon.GUI.PersistentChoice helper. Restored once per session (first
    -- Draw after a login / reload, when these fields are still at their fresh-Lua
    -- defaults). The character (nil) and profession (0) sentinels are re-validated
    -- against the live lists in DrawScope, so a stale saved value falls back
    -- gracefully to the first available entry.
    if not self._scope then
        local getScope = addon.GUI.PersistentChoice("char", "missingScope",   "personal")
        local getChar  = addon.GUI.PersistentChoice("char", "missingCharKey", nil)
        local getProf  = addon.GUI.PersistentChoice("char", "missingProfId",  0)
        self._scope   = getScope()
        self._charKey = getChar()
        self._profId  = getProf()
    end

    -- Built here (not at file scope) so the labels honour a UI-language override.
    local subDefs = {
        { value = "personal", text = L["MissingSubtabPersonal"] },
        { value = "guild",    text = L["MissingSubtabGuild"]    },
    }

    local tg = AceGUI:Create("TabGroup")
    tg:SetTabs(subDefs)
    tg:SetLayout("Fill")
    tg:SetFullWidth(true)
    tg:SetFullHeight(true)

    -- Capture the class LayoutFinished once; restore it on release (pool safety).
    if not _TG_CLASS_LAYOUTFINISHED and type(tg.LayoutFinished) == "function" then
        _TG_CLASS_LAYOUTFINISHED = tg.LayoutFinished
    end
    tg:SetCallback("OnRelease", function(widget)
        if _TG_CLASS_LAYOUTFINISHED then widget.LayoutFinished = _TG_CLASS_LAYOUTFINISHED end
        -- Detach the virtual-scroll pool via the shared addon.GUI.DetachPool
        -- helper (through DetachPool), so the pooled raw rows can't bleed into
        -- another addon if this TabGroup is torn down without the inner scroll's
        -- own onRelease having fired first.
        self:DetachPool()
    end)

    tg:SetCallback("OnGroupSelected", function(widget, _e, value)
        self._scope = value
        -- Keep the profession selection across sub-tabs when it's valid in the
        -- new scope; DrawScope re-picks the first profession if it isn't.
        local _, setScope = addon.GUI.PersistentChoice("char", "missingScope")
        setScope(value)
        widget:ReleaseChildren()
        self:DrawScope(widget)
    end)

    container:AddChild(tg)
    tg:SelectTab(self._scope)
end

-- Render the active scope's toolbar + result list into `container` (the TabGroup
-- content). Split out of Draw so OnGroupSelected can redraw just the content.
function MissingRecipesTab:DrawScope(container)
    container:SetLayout("List")
    local guildScope = (self._scope == "guild")

    -- Persist the character / profession dropdown selections across /reload
    -- (shared helper; restored in Draw). Saved on every user change below.
    local _, setChar = addon.GUI.PersistentChoice("char", "missingCharKey")
    local _, setProf = addon.GUI.PersistentChoice("char", "missingProfId")

    -- Personal scope needs a character; guild scope is guild-wide (no character).
    local chars = {}
    if guildScope then
        self._charKey = nil
    else
        if not self._charKey then
            self._charKey = addon:GetCharacterKey()
        end
        chars = GetCharactersWithProfessions()
        -- Validate the persisted selection still exists in our roster.
        local stillValid = false
        for _, ck in ipairs(chars) do
            if ck == self._charKey then stillValid = true; break end
        end
        if not stillValid and #chars > 0 then
            self._charKey = chars[1]
        end
        if #chars == 0 then
            local lbl = AceGUI:Create("Label")
            lbl:SetText(L["MissingNoCharacters"])
            lbl:SetFullWidth(true)
            container:AddChild(lbl)
            return
        end
    end

    -- ---- Toolbar -----------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    -- Character dropdown (personal scope only).
    if not guildScope then
        local charList, charOrder = {}, {}
        local myKey = addon:GetCharacterKey()
        for _, ck in ipairs(chars) do
            local short = CharShortName(ck)
            local label = (ck == myKey)
                and (short .. " |cffaaaaaa(" .. L["You"] .. ")|r")
                or  short
            charList[ck] = label
            table.insert(charOrder, ck)
        end
        local charDD = AceGUI:Create("Dropdown")
        charDD:SetLabel(L["MissingCharacterLabel"])
        charDD:SetWidth(180)
        addon.GUI.OffsetInputLabel(charDD)
        charDD:SetList(charList, charOrder)
        charDD:SetValue(self._charKey)
        charDD:SetCallback("OnValueChanged", function(_w, _e, value)
            self._charKey = value
            setChar(value)
            self._profId  = 0  -- reset profession when switching character
            setProf(0)
            self:Refresh()
        end)
        AttachWidgetTooltip(charDD, L["MissingCharTooltipTitle"], L["MissingCharTooltipDesc"])
        toolbar:AddChild(charDD)

        local sp1 = AceGUI:Create("Label"); sp1:SetWidth(8); toolbar:AddChild(sp1)
    end

    -- Profession dropdown — personal: the selected char's tracked skills;
    -- guild: every profession the guild practices.
    local profIds = guildScope and GetGuildProfessions()
                                or GetProfessionsForCharacter(self._charKey)
    if #profIds == 0 then
        -- Nothing to show — render a scope-appropriate hint below the toolbar.
        local lblProf = AceGUI:Create("Label")
        lblProf:SetText(guildScope and L["MissingGuildNoData"] or L["MissingNoProfessions"])
        lblProf:SetFullWidth(true)
        container:AddChild(lblProf)
        return
    end

    local profList, profOrder = {}, {}
    -- "All Professions" aggregate first, then each profession.
    profList["all"] = L["MissingAllProfessions"]
    table.insert(profOrder, "all")
    for _, pid in ipairs(profIds) do
        profList[pid] = addon.PROF_NAMES[pid] or ("Profession " .. pid)
        table.insert(profOrder, pid)
    end
    -- Preserve a valid selection ("all" or a still-present profession); default
    -- to the first profession when unset/invalid.
    if (self._profId == 0 or not profList[self._profId]) and #profIds > 0 then
        self._profId = profIds[1]
    end

    local profDD = AceGUI:Create("Dropdown")
    profDD:SetLabel(L["MissingProfessionLabel"])
    profDD:SetWidth(180)
    addon.GUI.OffsetInputLabel(profDD)
    profDD:SetList(profList, profOrder)
    profDD:SetValue(self._profId)
    profDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._profId = value
        setProf(value)
        self:RefreshList()
    end)
    AttachWidgetTooltip(profDD, L["MissingProfTooltipTitle"], L["MissingProfTooltipDesc"])
    toolbar:AddChild(profDD)

    local sp2 = AceGUI:Create("Label"); sp2:SetWidth(8); toolbar:AddChild(sp2)

    -- Search box. OnTextChanged fires on every keystroke; debounce so each
    -- character typed doesn't trigger a full BuildMissingList + 100-row
    -- AceGUI redraw. Cancelling-and-rescheduling means only the final value
    -- after the user pauses ~200ms actually rebuilds.
    local search = AceGUI:Create("EditBox")
    search:SetWidth(200)
    search:SetText(self._searchText)
    search:DisableButton(true)
    search:SetCallback("OnTextChanged", function(_w, _e, text)
        self._searchText = text
        if self._searchTimer then self._searchTimer:Cancel() end
        self._searchTimer = C_Timer.NewTimer(0.2, function()
            self._searchTimer = nil
            self:RefreshList()
        end)
    end)
    AttachWidgetTooltip(search, L["MissingSearchTooltipTitle"], L["MissingSearchTooltipDesc"])
    -- TSM-style search field: magnifying-glass icon instead of a text label
    -- (call after the tooltip so the icon's OnRelease cleanup chains).
    -- keepLabelSpace=true: aligns with the labeled dropdowns in this row.
    addon.GUI.StyleSearchBox(search, true)
    toolbar:AddChild(search)

    local sp3 = AceGUI:Create("Label"); sp3:SetWidth(8); toolbar:AddChild(sp3)

    -- Include trainer-only checkbox
    local trainCb = AceGUI:Create("CheckBox")
    trainCb:SetLabel(L["MissingIncludeTrainer"])
    trainCb:SetValue(self._includeTrainer)
    trainCb:SetWidth(160)
    trainCb:SetCallback("OnValueChanged", function(_w, _e, value)
        self._includeTrainer = value and true or false
        self:RefreshList()
    end)
    AttachWidgetTooltip(trainCb, L["MissingIncludeTrainer"], L["MissingIncludeTrainerDesc"])
    toolbar:AddChild(trainCb)

    -- "Can learn now" checkbox — strict skillRank >= requiredSkill filter.
    -- Personal scope only: guild scope has no single character's skill to gate on.
    if not guildScope then
        local learnCb = AceGUI:Create("CheckBox")
        learnCb:SetLabel(L["MissingCanLearnOnly"])
        learnCb:SetValue(self._canLearnOnly)
        learnCb:SetWidth(140)
        learnCb:SetCallback("OnValueChanged", function(_w, _e, value)
            self._canLearnOnly = value and true or false
            self:RefreshList()
        end)
        AttachWidgetTooltip(learnCb, L["MissingCanLearnOnly"], L["MissingCanLearnOnlyDesc"])
        toolbar:AddChild(learnCb)
    end

    -- "Show All" checkbox — include recipes the character already knows, so the
    -- list becomes every recipe for the selected profession (known marked ✓).
    local allCb = AceGUI:Create("CheckBox")
    allCb:SetLabel(L["MissingShowAll"])
    allCb:SetValue(self._showAll)
    allCb:SetWidth(110)
    allCb:SetCallback("OnValueChanged", function(_w, _e, value)
        self._showAll = value and true or false
        self:RefreshList()
    end)
    AttachWidgetTooltip(allCb, L["MissingShowAll"], L["MissingShowAllDesc"])
    toolbar:AddChild(allCb)

    -- Scan AH button — kicks off a throttled scan over the currently-displayed
    -- missing-recipes list. After completion, rows whose recipe scroll has
    -- live AH listings get a [AH] button (gated on AH.GetListingsFor — same
    -- pattern as [Bank] gating on Bank.GetStock). Disabled when AH is closed,
    -- displays scan progress while running. Filter changes during a scan
    -- don't affect the in-progress scan; the user can cancel and re-scan
    -- after narrowing the list to fewer items.
    addon.GUI.MakeScanAHButton({
        parent        = toolbar,
        tabName       = "missing",
        label         = L["MissingScanAH"],
        progressLabel = L["MissingScanAHProgress"],
        tooltipTitle  = L["MissingScanAH"],
        tooltipDesc   = L["MissingScanAHDesc"],
        width         = 140,
        noItemsError  = "No scannable items in the current view.",
        getItems      = function()
            -- GetItemInfo (not GetItemInfoInstant — its first return is the
            -- itemID number not the name) gives us the string name. Items
            -- not yet in the WoW cache get skipped silently; the user can
            -- re-scan after scrolling has populated more entries. Trainer-
            -- only recipes (entry.itemId == nil) have no scroll item and
            -- can't be auctioned, so we skip them here.
            local items = {}
            for _, entry in ipairs(self._list or {}) do
                local iid = entry.itemId
                if iid then
                    local name = GetItemInfo and GetItemInfo(iid)
                    if type(name) == "string" and name ~= "" then
                        items[#items + 1] = { itemId = iid, itemName = name }
                    end
                end
            end
            return items
        end,
        onRefresh     = function()
            if MissingRecipesTab._pool and MissingRecipesTab._scroll then
                MissingRecipesTab:UpdateVirtualRows()
            end
        end,
    })

    -- ---- Result section ----------------------------------------------------
    local section = AceGUI:Create("SimpleGroup")
    section:SetLayout("List")
    section:SetFullWidth(true)
    section:SetFullHeight(true)
    container:AddChild(section)
    self._listSection = section

    -- When section is released (tab switch / character switch / Refresh),
    -- clear our four-edge fill anchors so they don't bleed into another
    -- tab's content if AceGUI recycles this SimpleGroup. Also nil
    -- self._listSection so the leftover container.LayoutFinished hook
    -- early-returns on other tabs (BrowserTab uses the same pattern via
    -- self._scroll = nil in DestroyPool).
    section:SetCallback("OnRelease", function()
        if section.frame then section.frame:ClearAllPoints() end
        if self._listSection == section then self._listSection = nil end
    end)

    -- Pin each edge of section.frame to fill the container, AND anchor the
    -- scroll inside section to fill below the column header. Both anchors
    -- live in the same container.LayoutFinished hook because we MUST NOT
    -- override section.LayoutFinished — SimpleGroup defines a class-level
    -- LayoutFinished that auto-resizes the widget to fit its content
    -- (AceGUIContainer-SimpleGroup.lua:25), and that method lives on the
    -- widget table itself, not in widget.events. AceGUI:Release does not
    -- restore class methods on the recycled widget. So if we replace
    -- section.LayoutFinished, the override survives recycling — when the
    -- pooled SimpleGroup is acquired by e.g. Cooldowns' headers group,
    -- AceGUI's layout calls headers:LayoutFinished, hits our (now-orphaned)
    -- override which early-returns on a nil self._scroll, and the headers
    -- frame is never SetHeight'd to fit its column labels. It keeps the
    -- stale ~300px from when it was our fill-anchored section, and Flow
    -- layout positions the next sibling 300px below — the user's "huge
    -- gap." Doing all anchoring through container.LayoutFinished (TabGroup,
    -- which is not pooled across tab uses) avoids that trap entirely.
    local function AnchorAll()
        if not (self._listSection and self._listSection.frame and toolbar.frame) then return end
        local cContent = container.content or container.frame
        if not cContent then return end

        local sf = self._listSection.frame
        sf:ClearAllPoints()
        sf:SetPoint("TOP",    toolbar.frame, "BOTTOM", 0, -4)
        sf:SetPoint("LEFT",   cContent,      "LEFT",   0,  0)
        sf:SetPoint("RIGHT",  cContent,      "RIGHT",  0,  0)
        sf:SetPoint("BOTTOM", cContent,      "BOTTOM", 0,  4)

        if self._scroll and self._scroll.frame and self._headerFrame then
            local f = self._scroll.frame
            f:ClearAllPoints()
            f:SetPoint("TOP",    self._headerFrame, "BOTTOM", 0, -2)
            f:SetPoint("LEFT",   sf,                "LEFT",   0,  0)
            f:SetPoint("RIGHT",  sf,                "RIGHT",  0,  0)
            f:SetPoint("BOTTOM", sf,                "BOTTOM", 0,  4)
        end
    end
    -- Anchor on the TabGroup container's LayoutFinished. We intentionally do NOT
    -- chain the TabGroup's class LayoutFinished here: that class method does
    -- `self:SetHeight(contentHeight + 46)`, auto-growing the TabGroup to fit the
    -- (virtually huge) list content and fighting the SetFullHeight(true) we asked
    -- for — which would make the container resize every pass. Suppressing it (by
    -- replacing with just AnchorAll) keeps the TabGroup at its parent-assigned
    -- fill height. The class method is restored on release for pool safety
    -- (_TG_CLASS_LAYOUTFINISHED in the OnRelease handler).
    container.LayoutFinished = function() AnchorAll() end
    self._anchorAll = AnchorAll
    AnchorAll()

    self:FillList()
end

-- ---------------------------------------------------------------------------
-- Refresh helpers
-- ---------------------------------------------------------------------------

-- Full redraw — when the character or profession set changes shape.
function MissingRecipesTab:Refresh()
    if not self._container then return end
    self._container:ReleaseChildren()
    self._listSection = nil
    self:Draw(self._container)
end

-- Light refresh — only the result list rebuilds (search, trainer toggle,
-- profession switch within the same character).
function MissingRecipesTab:RefreshList()
    if not self._listSection then return end
    self._listSection:ReleaseChildren()
    self:FillList()
end

-- ---------------------------------------------------------------------------
-- Result list — virtual-scroll using a raw frame pool (35 rows), mirroring
-- BrowserTab's pattern. AceGUI is reserved for the toolbar and a few static
-- header / count widgets above the scrollable list. Without virtual scrolling
-- a profession with several hundred missing recipes spawns thousands of
-- AceGUI widgets and the layout pass freezes the WoW client.
-- ---------------------------------------------------------------------------

-- Build the pool of POOL_SIZE raw Frames, parented to the AceGUI ScrollFrame's
-- content frame so they scroll naturally. Each pool frame holds an icon,
-- name / skill / sources fontstrings, and a small watch-toggle button. Frames
-- are reused as the user scrolls; only the content of each is updated.
function MissingRecipesTab:BuildPool(parent)
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

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(240)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        -- Skill data column shifted 5px left of name's right edge so its
        -- right-justified values align with the column header above it.
        local skillLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        skillLbl:SetPoint("LEFT", nameLbl, "RIGHT", -1, 0)
        skillLbl:SetWidth(104)
        skillLbl:SetJustifyH("LEFT")
        f.skillLbl = skillLbl

        -- 16px gap from the skill column matches the header's 4 + 8 spacer +
        -- 4 (Flow's default child gap) so the column edges line up.
        local srcLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        srcLbl:SetPoint("LEFT", skillLbl, "RIGHT", 16, 0)
        srcLbl:SetWidth(180)
        srcLbl:SetJustifyH("LEFT")
        srcLbl:SetWordWrap(false)
        srcLbl:SetTextColor(0.75, 0.75, 0.75)
        f.srcLbl = srcLbl

        -- [Bank] button — same pattern as BrowserTab/CooldownsTab/ShoppingListTab.
        -- Visible only when TOGBankClassic reports stock for this recipe scroll;
        -- click opens the bank-request dialog. Sized/styled to match the other
        -- [Bank] buttons across the addon for consistency. Sits to the LEFT
        -- of [AH] so the on-row order reads [Bank] [AH] left-to-right (Bank
        -- first, AH after), matching BrowserTab's reagent-row order.
        local bankBtn = CreateFrame("Button", nil, f)
        bankBtn:SetSize(50, 12)
        bankBtn:SetPoint("RIGHT", f, "RIGHT", -42, 0)  -- right edge of [Bank] sits left of [AH]
        bankBtn:SetNormalFontObject(GameFontNormalSmall)
        bankBtn:SetText("|cFF88FF88[Bank]|r")
        bankBtn:Hide()
        bankBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(bankBtn)
            GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1)
            GameTooltip:AddLine(L["TooltipBankDescScroll"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.bankBtn = bankBtn

        -- [AH] button — visible only when the AH scanner has cached listings
        -- for this recipe scroll. Click jumps the AH UI to a Browse search
        -- for the scroll's name so the user can bid/buyout from the standard
        -- Blizzard UI. Sits to the RIGHT of [Bank] so the on-row order reads
        -- [Bank] [AH] left-to-right; when only one is shown the other slot
        -- is empty (small gap acceptable since these are conditionally-
        -- visible action buttons). Width 36 fits "[AH]" comfortably.
        local ahBtn = CreateFrame("Button", nil, f)
        ahBtn:SetSize(36, 12)
        ahBtn:SetPoint("RIGHT", f, "RIGHT", -2, 0)  -- far right of the row
        ahBtn:SetNormalFontObject(GameFontNormalSmall)
        ahBtn:SetText("|cFF88CCFF[AH]|r")
        ahBtn:Hide()
        ahBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(ahBtn)
            GameTooltip:SetText(L["TooltipAHTitle"], 1, 1, 1)
            GameTooltip:AddLine(L["TooltipAHDescScroll"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.ahBtn = ahBtn

        -- Row-level mouse handling for hover tooltip + shift-click chat link.
        -- Item-id path renders the recipe-scroll tooltip (reagents, prof
        -- requirement). For trainer-only recipes (no scroll item exists),
        -- fall back to the spell tooltip so the row still has SOMETHING on
        -- hover instead of nothing — and so we never pass nil into
        -- SetItemByID (Blizzard silently sets an empty tooltip, but
        -- addons that hook SetItemByID such as LoonBestInSlot then crash
        -- on the empty state).
        --
        -- v0.7.5: route the tooltip through a private GameTooltip instance
        -- (MissingRecipesTab:GetCustomTip below) instead of the global
        -- _G.GameTooltip. Third-party addons that crash on recipe-scroll
        -- tooltips — RecipeMaster on Vanilla (RecipeHandler.lua:43 nil-
        -- indexes recipe.teaches when its cachedRecipes table is empty),
        -- LoonBestInSlot, etc. — hook their OnTooltipSetItem /
        -- OnTooltipSetSpell handlers onto the GLOBAL GameTooltip instance
        -- via GameTooltip:HookScript. Those handlers don't run when the
        -- tooltip lives on a different frame instance, even if both
        -- frames inherit from "GameTooltipTemplate" (same look and feel,
        -- same SetX API, but separate script handler registries). So we
        -- get the rich Blizzard item tooltip — reagents, required skill,
        -- quality colouring — without ever triggering RecipeMaster's
        -- broken hook chain. v0.6.1's pcall wrap and v0.7.5's
        -- seterrorhandler swap both failed because the hook crashes were
        -- dispatched via WoW's internal script-error path which BugGrabber
        -- captures before either guard reaches the error.
        f:SetScript("OnEnter", function()
            if not (f._itemId or f._spellId) then return end
            -- ItemLink.Tooltip picks the frame — our private one whenever this
            -- tab supplies it, so the third-party OnTooltipSetItem hooks that
            -- crash on recipe scrolls never run. Routed through the helper
            -- rather than used directly so there is one place that decision
            -- lives if it ever needs to change again.
            local tip = addon.ItemLink.Tooltip(MissingRecipesTab:GetCustomTip())
            -- Anchor next to the row using the same screen-half logic as
            -- addon.Tooltip.Owner — popup appears just below the row when
            -- the row is in the upper half of the screen, just above
            -- when it's in the lower half.
            local _, y = f:GetCenter()
            local anchor = (y and y > GetScreenHeight() / 2)
                           and "ANCHOR_BOTTOMLEFT" or "ANCHOR_TOPLEFT"
            tip:SetOwner(f, anchor)
            -- Decide between item tooltip and spell tooltip. Item is
            -- preferred (shows reagents + profession requirement) but
            -- ONLY when the item is already in the WoW client's cache.
            -- Calling SetItemByID on a cache-cold item ID silently sets
            -- an empty tooltip — fall back to spell or plain text. The
            -- cold-cache check via GetItemInfo doubles as an async
            -- prefetch trigger, so the next mouseover lands warm.
            local useItem = false
            if f._itemId and GetItemInfo then
                local cachedName = GetItemInfo(f._itemId)
                useItem = cachedName ~= nil
            end
            if useItem then
                tip:SetItemByID(f._itemId)
            elseif f._spellId and tip.SetSpellByID then
                tip:SetSpellByID(f._spellId)
            else
                local name = (f._spellId and GetSpellInfo and GetSpellInfo(f._spellId))
                             or (f._itemId and ("Item #" .. f._itemId))
                             or "?"
                tip:SetText(name, 1, 1, 1, 1, true)
            end
            -- v0.9.0: Optionally append [TOGPM] itemId / spellId footer
            -- for troubleshooting recipe bleedthrough (SoD/TBC/etc.). Respects
            -- the same tooltipShowIds toggle as the global item-tooltip hook.
            local showIds = Ace and Ace.db and Ace.db.profile
                            and Ace.db.profile.tooltipShowIds
            if showIds then
                local brandColor = addon.BrandColor or "ffFF8000"
                local idParts = {}
                if f._itemId  then table.insert(idParts, "itemId="  .. tostring(f._itemId))  end
                if f._spellId then table.insert(idParts, "spellId=" .. tostring(f._spellId)) end
                if #idParts > 0 then
                    tip:AddLine(" ")
                    tip:AddLine("|c" .. brandColor .. "[TOGPM]|r " ..
                                "|c" .. brandColor .. table.concat(idParts, "  ") .. "|r",
                                1, 1, 1, true)
                end
            end
            tip:AddLine(" ")
            tip:AddLine(L["MissingRowTooltipShift"], 0.7, 0.7, 0.7, true)
            tip:Show()
            -- Register for hold-to-compare. Only meaningful when the row is
            -- showing an ITEM — a recipe-scroll tooltip has an equip slot to
            -- compare against, a spell tooltip does not.
            if useItem then addon.ItemLink.BeginHover(tip) end
        end)
        f:SetScript("OnLeave", function()
            addon.ItemLink.EndHover(GameTooltip)
            if MissingRecipesTab._customTip then
                MissingRecipesTab._customTip:Hide()
            end
            GameTooltip:Hide()
        end)
        -- Was a raw editBox:Insert, which ignores the player's modified-click
        -- bindings and skips the AH-search and macro handling Blizzard's own
        -- insert does. addon.ItemLink.Click
        -- routes through Blizzard's own HandleModifiedItemClick, as every other
        -- row in the addon now does.
        f:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local link
            if f._itemId then
                _, link = GetItemInfo(f._itemId)
            elseif f._spellId and GetSpellLink then
                link = GetSpellLink(f._spellId)
            end
            addon.ItemLink.Click(link)
        end)

        self._pool[i] = f
    end
end

-- Detach the pool from a soon-to-be-released parent without throwing the
-- frames away. The ScrollFrame is released on every RefreshList; keeping the
-- pool persistent across releases avoids leaking 35 fresh CreateFrame() calls
-- per refresh (WoW frames are session-lifetime and never GC'd). Pool frames
-- get reparented onto the new ScrollFrame's content in the next FillList.
function MissingRecipesTab:DetachPool()
    addon.GUI.DetachPool(self._pool)
    self._scroll = nil
    self._list   = nil
end

-- Reposition + repopulate the pool based on the current scroll offset. Only
-- runs over POOL_SIZE rows regardless of total list size — the scroll math
-- decides which slice of self._list is visible.
function MissingRecipesTab:UpdateVirtualRows()
    local scroll = self._scroll
    local list   = self._list
    if not scroll or not list or not self._pool then return end

    local status   = scroll.status or scroll.localstatus
    local offset   = (status and status.offset) or 0
    local firstIdx = math.floor(offset / ROW_HEIGHT)

    -- Item name / quality / icon ALL come from synchronous sources — LibItemDB
    -- (offline item DB) and ProfessionDB (recipe names) — so every row renders
    -- fully on the FIRST paint with NO client-cache round-trip. That's what lets
    -- this stay quiet: nothing is ever "pending" a GetItemInfo cache-fill, so the
    -- tab only re-renders on genuine data changes (GUILD_DATA_UPDATED, e.g. a
    -- skill learned) — never on the item-load storm that used to refresh it
    -- several times a second and creep the scroll.
    local idb = addon.GetItemDB and addon:GetItemDB()

    for i = 1, POOL_SIZE do
        local f       = self._pool[i]
        local listIdx = firstIdx + i
        local entry   = list[listIdx]
        if entry then
            addon.GUI.ApplyRowStripe(f, listIdx)
            -- v0.5.0 keyed recipeDB by spell id; the row's entry.itemId is the
            -- recipe-scroll item that teaches the spell (when one exists —
            -- trainer-taught recipes have no scroll item). Use entry.itemId
            -- for any item-id API call (GameTooltip:SetItemByID, GetItemInfo,
            -- GetItemIcon, GetItemQualityColor). When nil, fall back to
            -- spell-based display via GetSpellInfo. Never pass the spell id
            -- to item APIs — silently sets an empty tooltip and (worse)
            -- breaks downstream addons like LoonBestInSlot that hook
            -- SetItemByID and then crash on the empty result.
            local itemId = entry.itemId
            f._itemId = itemId
            f._spellId = entry.spellId

            local displayName, itemName, itemLink
            if itemId then
                -- Synchronous item-name resolution (LibItemDB), then the recipe's
                -- own ProfessionDB name, then the spell name — see below. No
                -- GetItemInfo, so nothing is ever left as a cache-miss placeholder
                -- and the row is complete on the first paint. (Historically this
                -- used GetItemInfo + a GET_ITEM_INFO_RECEIVED refresh, which is
                -- what created the refresh storm / scroll creep.)
                --
                -- Legacy note retained: some recipe items legitimately don't
                -- exist on the current client (e.g. Vanilla recipes whose scroll
                -- items were removed) — those simply fall through to the recipe /
                -- spell name so the row still shows SOMETHING meaningful instead
                -- of a permanent
                -- "#22430 (loading…)" placeholder.
                -- Name from LibItemDB (synchronous) — the full scroll name, e.g.
                -- "Recipe: Thistle Tea". CRITICAL: never fall back to GetItemInfo
                -- here. A cold scroll item's async cache-fill fires
                -- GET_ITEM_INFO_RECEIVED, and the resulting refresh storm is what
                -- crept the scroll to the bottom. When LibItemDB doesn't carry the
                -- scroll item, use the recipe's OWN name from ProfessionDB
                -- (entry.name), then the spell name — all synchronous.
                itemName = idb and idb:GetName(itemId)
                itemLink = idb and idb:GetLink(itemId)
                displayName = itemName
                              or entry.name
                              or (GetSpellInfo and GetSpellInfo(entry.spellId))
                              or ("|cffaaaaaaspell:" .. tostring(entry.spellId) .. "|r")
                -- GetItemIcon reads static item file data (synchronous, fires no
                -- cache event); fall back to the spell texture.
                f.icon:SetTexture((GetItemIcon and GetItemIcon(itemId))
                                  or (GetSpellTexture and GetSpellTexture(entry.spellId))
                                  or 134400)
            else
                -- Trainer-only recipe with no scroll item. Fall back to the
                -- spell's name + icon. No item link / quality colour
                -- available — recipes are uncoloured in this branch.
                local spellName = (GetSpellInfo and GetSpellInfo(entry.spellId))
                                  or (entry.name)
                                  or ("|cffaaaaaaspell:" .. entry.spellId .. "|r")
                displayName = spellName
                -- Icon resolution priority for trainer-only crafts:
                --
                --   1. entry.craftedItemId — the item the spell PRODUCES,
                --      shipped in addon.recipeDB from SpellEffect[Effect=24]
                --      data (see tools/build_authoritative_data.py). This
                --      is the authoritative source for trainer-taught
                --      craft icons (Heavy Weightstone → item 3241, Coarse
                --      Sharpening Stone → item 2863, etc.) and works for
                --      every recipe whose primary effect is Create Item,
                --      regardless of whether the player has ever seen the
                --      crafted item.
                --
                --   2. GetSpellTexture(spellId) — fallback when no
                --      craftedItemId was shipped (Enchanting craft spells
                --      have no produced item, so they correctly fall here
                --      and render the enchant scroll icon Blizzard
                --      assigned the spell).
                local craftedIcon
                if entry.craftedItemId and GetItemIcon then
                    craftedIcon = GetItemIcon(entry.craftedItemId)
                end
                local spellIcon = craftedIcon
                              or (GetSpellTexture and GetSpellTexture(entry.spellId))
                f.icon:SetTexture(spellIcon or 134400)
            end

            -- Colour the name by the CRAFTED item's quality (what the recipe
            -- produces) — matching the crafting window, where a recipe for an
            -- epic shows purple even when its pattern scroll is common/white
            -- (e.g. "Pattern: Molten Helm"). Fall back to the recipe-scroll item's
            -- own quality (enchants have no crafted item), then to no colour.
            -- GetItemInfo returns nil while an item is still loading; the
            -- GET_ITEM_INFO_RECEIVED handler re-renders the row once it lands.
            -- Crafted-item quality colour, from LibItemDB ONLY (synchronous).
            -- CRITICAL: never call GetItemInfo on the crafted item here. A cold
            -- crafted item (gear/food the player has never seen) would trigger an
            -- async cache load, and the resulting GET_ITEM_INFO_RECEIVED storm
            -- re-rendered the list several times a second and crept the scroll to
            -- the bottom — that is exactly what "colour by crafted quality"
            -- regressed. Uncommon+ crafted gear gets its quality colour; common /
            -- poor produce (most food) stays uncoloured (white); enchants and
            -- other no-produced-item recipes fall back to the scroll item's own
            -- link colour, which was already resolved above with no extra call.
            local color
            local q = idb and entry.craftedItemId and idb:GetQuality(entry.craftedItemId)
            if q and q > 1 then
                local r, g, b = GetItemQualityColor(q)
                if r and g and b then
                    color = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
                end
            elseif not entry.craftedItemId and itemLink then
                color = itemLink:match("|c(%x%x%x%x%x%x%x%x)|H")
            end
            local nmText = color and ("|c" .. color .. displayName .. "|r") or displayName
            if self._showAll and entry.known then
                -- Show All mode marks recipes the character already knows with a check.
                nmText = "|TInterface\\Buttons\\UI-CheckBox-Check:0|t " .. nmText
            end
            -- "All Professions" view: tag each row with its profession so the
            -- flat, cross-profession list stays readable.
            if self._profId == "all" and entry.profName then
                nmText = "|cff888888[" .. entry.profName .. "]|r " .. nmText
            end
            f.nameLbl:SetText(nmText)

            -- Skill column: the recipe's authoritative difficulty breakpoints
            -- (orange→yellow→green→grey). Pattern-recipe orange is corrected in
            -- the data pipeline, so this just colours the shipped values.
            f.skillLbl:SetText(addon.FormatSkillTiers(entry.tiers, entry.requiredSkill))
            f.srcLbl:SetText(entry.sourcesText or "")

            -- [Bank] button: show only when TOGBankClassic reports stock for
            -- this recipe scroll. Click opens the request dialog with the
            -- scroll's name + link. Bank stock is queried fresh per row each
            -- pool refresh — cheap (single table walk in addon.Bank.GetStock).
            -- Trainer-only recipes (itemId == nil) have no scroll to bank.
            if itemId and addon.Bank and addon.Bank.GetStock(itemId) > 0 then
                local rowItemId   = itemId
                local rowItemName = itemName or ("Item #" .. itemId)
                local rowItemLink = itemLink
                f.bankBtn:SetScript("OnClick", function()
                    addon.Bank.ShowRequestDialog(rowItemId, rowItemName, rowItemLink)
                end)
                f.bankBtn:Show()
            else
                f.bankBtn:Hide()
            end

            -- [AH] button: show ONLY when a scan has found live listings for
            -- this recipe scroll, mirroring [Bank]'s "show iff stock > 0"
            -- pattern. Click jumps the AH browse search to the scroll's name
            -- so the user can bid/buy from the standard Blizzard UI. The
            -- button stays visible after the scan even if the user clicks
            -- another tab; AH.SearchFor handles "AH closed" gracefully with
            -- a chat message so a stale-results click is harmless. Trainer-
            -- only recipes (itemId == nil) have no scroll to find on the AH.
            local listings = itemId and addon.AH and addon.AH.GetListingsFor(itemId)
            if listings and (listings.count or 0) > 0 and itemName then
                local rowItemName = itemName
                f.ahBtn:SetScript("OnClick", function()
                    addon.AH.SearchFor(rowItemName)
                end)
                f.ahBtn:Show()
            else
                f.ahBtn:Hide()
            end

            local y = -((listIdx - 1) * ROW_HEIGHT)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT",  scroll.content, "TOPLEFT",  0, y)
            f:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, y)
            f:Show()
        else
            f._itemId = nil
            f:Hide()
        end
    end
end

-- Apply the active column sort to the (already search-filtered) list, in place.
-- Recipe name resolution mirrors the search filter: scroll-item name, then spell
-- name, then the stored fallback — best-effort for cold-cache items (they re-sort
-- correctly on the next refresh as the item cache fills). Skill keeps unknown
-- (nil) ranks last in BOTH directions so blank-data rows never bury the list.
function MissingRecipesTab:SortList(list)
    local col = self._sortCol
    if not col or type(list) ~= "table" then return end
    local asc = self._sortAsc == true

    -- Precompute the text sort key once per entry so the comparator doesn't call
    -- GetItemInfo O(n log n) times (skill sorts on the numeric field directly).
    local key
    if col == "recipe" or col == "source" then
        key = {}
        local idb = addon.GetItemDB and addon:GetItemDB()
        for _, e in ipairs(list) do
            if col == "recipe" then
                local n = (e.itemId and idb and idb:GetName(e.itemId))
                          or (e.itemId and GetItemInfo and GetItemInfo(e.itemId))
                          or (GetSpellInfo and GetSpellInfo(e.spellId))
                          or e.name or ""
                key[e] = tostring(n):lower()
            else
                key[e] = (e.sourcesText or ""):lower()
            end
        end
    end

    local function cmp(x, y)
        if asc then return x < y else return x > y end
    end
    -- Effective learn skill = requiredSkill, falling back to the orange
    -- difficulty tier (tiers[1]) — same gate resolution BuildMissingList uses.
    -- This keeps recipes like Basic Campfire (no requiredSkill but orange=1)
    -- sorting by their real skill instead of being treated as unknown. Only
    -- recipes with NEITHER value are genuinely unknown and sort last.
    local function skillOf(e)
        return e.requiredSkill or (e.tiers and e.tiers[1])
    end
    local groupByProf = (self._profId == "all")
    table.sort(list, function(a, b)
        -- All-Professions view: keep recipes grouped by profession first (always
        -- A→Z, independent of the column sort direction), then sort within each
        -- profession by the chosen column.
        if groupByProf and a.profName ~= b.profName then
            return (a.profName or "") < (b.profName or "")
        end
        if col == "skill" then
            local ar, br = skillOf(a), skillOf(b)
            if ar ~= br then
                if ar == nil then return false end  -- unknown skill always last
                if br == nil then return true end
                return cmp(ar, br)
            end
        else
            local ka, kb = key[a], key[b]
            if ka ~= kb then return cmp(ka, kb) end
        end
        return (a.spellId or 0) < (b.spellId or 0)  -- stable tiebreak
    end)
end

function MissingRecipesTab:FillList()
    local section = self._listSection
    if not section then return end

    -- Empty / waiting-for-pick states
    if not self._profId or self._profId == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["MissingPickProfession"])
        lbl:SetFullWidth(true)
        section:AddChild(lbl)
        return
    end

    local fullList
    if self._profId == "all" then
        -- Aggregate every profession in the current scope into one list, tagging
        -- each entry with its profId/name so the row can show a [Profession]
        -- prefix and SortList can group by profession. Ordering is handled by
        -- SortList below (profession-first in this view).
        local guildScope = (self._scope == "guild")
        local profIds = guildScope and GetGuildProfessions()
                                    or GetProfessionsForCharacter(self._charKey)
        fullList = {}
        for _, pid in ipairs(profIds) do
            if addon.recipeDB and addon.recipeDB[pid] then
                local sub   = BuildMissingList(self._charKey, pid, self._includeTrainer, self._canLearnOnly, self._showAll, self._scope)
                local pname = addon.PROF_NAMES[pid] or tostring(pid)
                for _, e in ipairs(sub) do
                    e.profId   = pid
                    e.profName = pname
                    fullList[#fullList + 1] = e
                end
            end
        end
    else
        if not (addon.recipeDB and addon.recipeDB[self._profId]) then
            local lbl = AceGUI:Create("Label")
            lbl:SetText(L["MissingNoData"])
            lbl:SetFullWidth(true)
            section:AddChild(lbl)
            return
        end
        fullList = BuildMissingList(self._charKey, self._profId, self._includeTrainer, self._canLearnOnly, self._showAll, self._scope)
    end

    -- Apply search filter using GetItemInfo — its first return IS the item
    -- name (string). NOT GetItemInfoInstant (whose first return is the
    -- itemID number, not the name — using it here previously caused
    -- "attempt to index a number value" crashes). GetItemInfo can trigger
    -- an async load for uncached items; we wrap with a type check so
    -- unloaded items get skipped from the filter rather than crashing on
    -- :lower(). As the user scrolls the list, UpdateVirtualRows calls
    -- GetItemInfo per visible row, populating the WoW item cache, so the
    -- search filter progressively matches more items as more get cached.
    local list = fullList
    local filter = (self._searchText or ""):lower()
    if filter ~= "" then
        list = {}
        for _, entry in ipairs(fullList) do
            -- Search both the recipe-scroll item name (when one exists) AND
            -- the spell name as a fallback. The OR keeps trainer-only
            -- recipes searchable by their spell name even though they have
            -- no scroll item; lets the user find e.g. "Brown Linen Vest"
            -- regardless of whether the recipe is taught by a pattern or
            -- only by a trainer.
            local name = (entry.itemId and GetItemInfo and GetItemInfo(entry.itemId))
                         or (GetSpellInfo and GetSpellInfo(entry.spellId))
            local nameHit = type(name) == "string" and name:lower():find(filter, 1, true)
            -- Also match the effect text ("+5 Weapon Damage", "+12 Agility")
            -- so e.g. "5 damage" / "agility" find the right recipes.
            local effHit = entry.effect and entry.effect:lower():find(filter, 1, true)
            if nameHit or effHit then
                list[#list + 1] = entry
            end
        end
    end

    self:SortList(list)
    self._list = list

    local brand = addon.BrandColor or "ffFF8000"

    -- Empty-state: no column headers, just the "everything's covered" line.
    if #list == 0 then
        local empty = AceGUI:Create("InteractiveLabel")
        local msg = (self._scope == "guild") and L["MissingGuildNoneFound"] or L["MissingNoneFound"]
        empty:SetText("|c" .. brand .. msg .. "|r")
        empty:SetFullWidth(true)
        section:AddChild(empty)
        return
    end

    -- Single header row that doubles as the count line — the first column
    -- shows "X Missing Recipe(s)" instead of a redundant "Recipe" title
    -- (every row IS a recipe, so the column title was tautological and
    -- visually duplicated the count line stacked above it). Column widths
    -- mirror the pool row widths in BuildPool; the 8px spacer between
    -- Skill and Sources plus the pool's 16px skill→source gap keeps the
    -- columns visually distinct.
    local noun
    if self._showAll then
        noun = (#list == 1) and L["MissingCountAllSingular"] or L["MissingCountAllPlural"]
    else
        noun = (#list == 1) and L["MissingCountSingular"] or L["MissingCountPlural"]
    end
    local countText = string.format(L["MissingCountFormat"], #list, noun)

    local hdr = AceGUI:Create("SimpleGroup")
    hdr:SetLayout("Flow")
    hdr:SetFullWidth(true)
    section:AddChild(hdr)
    local function H(text, w, justifyH, tipTitle, tipDesc, sortKey)
        -- Sortable columns (sortKey set) get the shared sort treatment: centred
        -- text, the arrow beside it (ConfigureCenteredHeaderIcon), a brand hover
        -- glow, a click-to-sort handler, and a "Click to sort." tooltip hint —
        -- matching the Profit / Cooldowns / Crafting headers. Plain spacers and
        -- label-only headers pass no sortKey and stay as they were.
        local desc = tipDesc
        if sortKey and desc then
            desc = desc .. " " .. (L["CraftSortHint"] or "Click to sort.")
        end
        local widget = addon.GUI.MakeColumnHeader({
            parent       = hdr,
            label        = text,
            width        = w,
            justifyH     = sortKey and "CENTER" or justifyH,
            hoverGlow    = sortKey ~= nil,
            tooltipTitle = tipTitle,
            tooltipDesc  = desc,
            onClick      = sortKey and function()
                self._sortCol, self._sortAsc =
                    addon.GUI.Sort.Next(self._sortCol, self._sortAsc, sortKey)
                self:RefreshList()
            end or nil,
        })
        if sortKey then
            addon.GUI.Sort.ConfigureCenteredHeaderIcon(
                widget, self._sortCol == sortKey, self._sortAsc, w)
            -- Clean up the sort-icon texture when the pooled widget is released
            -- (chains MakeColumnHeader's hover-glow OnRelease via prevOnRelease).
            local prevOnRelease = widget.events and widget.events.OnRelease
            widget:SetCallback("OnRelease", function(wdg)
                if wdg._sortIcon then
                    wdg._sortIcon:Hide()
                    wdg._sortIcon:SetParent(nil)
                    wdg._sortIcon:ClearAllPoints()
                    wdg._sortIcon = nil
                end
                if prevOnRelease then prevOnRelease(wdg) end
            end)
        end
    end
    H("",                    22)
    H(countText,             240, nil,
        L["MissingHdrCountTitle"], L["MissingHdrCountDesc"], "recipe")
    H(L["MissingColSkill"],  104, "LEFT",
        L["MissingHdrSkillTitle"], L["MissingHdrSkillDesc"], "skill")
    H("",                    16)  -- 8 + 8 nudge so Sources header sits over its data column
    H(L["MissingColSource"], 180, nil,
        L["MissingHdrSourceTitle"], L["MissingHdrSourceDesc"], "source")
    H("",                    24)

    -- Stash hdr.frame so the AnchorAll function (set on container.LayoutFinished
    -- in Draw) can reference it when anchoring scroll. We do NOT override
    -- hdr.LayoutFinished or section.LayoutFinished — see the comment in Draw
    -- for why that breaks the Cooldowns tab via SimpleGroup recycling.
    self._headerFrame = hdr.frame

    -- Virtual-scroll container. The AceGUI ScrollFrame manages the scrollbar
    -- and clipping; the raw pool inside scroll.content does the actual row
    -- rendering. Shared PersistentScroll helper captures the saved scroll
    -- position so sync-triggered Refresh / RefreshList rebuilds don't yank
    -- the user back to the top mid-scroll (matches the BrowserTab and
    -- CooldownsTab fixes from v0.3.5).
    local scroll, savedScroll = addon.GUI.PersistentScroll.Acquire(self, {
        key        = "missing",
        layout     = "List",
        fullWidth  = true,
        fullHeight = true,
        onRelease  = function() self:DetachPool() end,
    })
    section:AddChild(scroll)
    self._scroll = scroll

    -- Virtual-scroll trick (matches BrowserTab:FillList): install a no-op
    -- LayoutFinished on the scroll instance so AceGUI's class default
    -- doesn't overwrite our manual content.height. Required because
    -- FixScroll calls DoLayout on every scrollbar visibility transition
    -- (AceGUIContainer-ScrollFrame.lua:108/118), and DoLayout fires the
    -- "List" layout function which calls scroll.LayoutFinished(_, _, 0)
    -- when scroll.children is empty (Missing parents raw frames to
    -- scroll.content directly, so AceGUI sees no children). The class
    -- default would then set content:SetHeight(0 or 20) — collapsing
    -- our virtual list to 0 px and hiding every row. Pre-v0.4.0 this
    -- silently worked because BrowserTab's no-op override leaked through
    -- the shared AceGUI ScrollFrame pool; Missing was free-riding on
    -- it. PersistentScroll.Acquire now restores the class default on
    -- every acquire (so Cooldowns' AceGUI-children auto-size works
    -- correctly), so Missing has to install its own no-op explicitly.
    scroll.LayoutFinished = function() end

    -- Tell the AceGUI ScrollFrame how tall the virtual content is so the
    -- scrollbar sizes correctly. Then build (or reuse) the pool and slot
    -- the visible rows in.
    scroll.content:SetHeight(#list * ROW_HEIGHT)
    if scroll.FixScroll then scroll:FixScroll() end

    if not self._pool then
        self:BuildPool(scroll.content)
    else
        -- Reparent existing pool frames onto the new scroll content (the
        -- ScrollFrame is recreated on every RefreshList).
        for _, f in ipairs(self._pool) do f:SetParent(scroll.content) end
    end

    self:UpdateVirtualRows()

    if scroll.scrollbar then
        scroll.scrollbar:SetScript("OnValueChanged", function(bar, value)
            if bar.obj and bar.obj.SetScroll then bar.obj:SetScroll(value) end
            self:UpdateVirtualRows()
        end)
    end

    -- Restore saved scroll position. PersistentScroll.Restore is order-robust
    -- (it re-applies the exact pixel offset, which needs no frame height), so it
    -- does NOT matter that we anchor the frame just below this. afterFn
    -- re-positions the raw-frame pool to the restored offset (without it, the
    -- scrollbar shows the right value but the rows stay anchored to row 0).
    addon.GUI.PersistentScroll.Restore(scroll, savedScroll, function()
        self:UpdateVirtualRows()
    end)

    -- Apply scroll anchor now that self._scroll and self._headerFrame are set.
    -- AceGUI will also re-fire container.LayoutFinished as part of section's
    -- own resize cascade, but doing it here means the first paint is correct
    -- without waiting for the next layout pass.
    if self._anchorAll then self._anchorAll() end
end

-- (No GET_ITEM_INFO_RECEIVED handler by design.) Item names, quality colours
-- and icons are resolved synchronously from LibItemDB + ProfessionDB in
-- UpdateVirtualRows, so there is nothing to "fill in" when the WoW item cache
-- warms up. The tab therefore re-renders ONLY on real data changes
-- (GUILD_DATA_UPDATED via MainWindow:Refresh — e.g. a crafter learns a recipe),
-- not on the background item-load storm that used to fire several times a
-- second and creep the scroll.

-- Refresh the scan button label whenever the AH opens or closes (it
-- enables/disables based on AH availability). Also refresh pool rows so
-- the [AH] button visibility (gated on cached scan results) correctly
-- clears when the AH closes — addon.AH wipes its results on close, so
-- without this the [AH] buttons would linger on rows until the next
-- pool refresh.
-- (Removed: per-tab AH_OPEN_STATE_CHANGED / AH_SCAN_COMPLETE handlers.
-- The shared addon.GUI.MakeScanAHButton factory in GUI/SharedWidgets.lua
-- owns one global handler that refreshes the active tab's scan button
-- and runs the tab's onRefresh hook — for missing, that hook calls
-- UpdateVirtualRows so [AH] buttons appear/disappear with scan results.)
