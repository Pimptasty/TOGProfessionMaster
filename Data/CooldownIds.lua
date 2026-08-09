-- TOG Profession Master — Profession cooldown spell IDs
-- Used to scan active cooldowns via GetSpellCooldown() on login and
-- BAG_UPDATE_COOLDOWN. Transmutes are handled as a separate group.
-- Ordered alphabetically by spell name within each expansion block.

local _, addon = ...

-- ---------------------------------------------------------------------------
-- Non-transmute cooldown IDs
-- { [spellId] = name }
-- ---------------------------------------------------------------------------

-- Vanilla
local VANILLA_COOLDOWNS = {
    [18560] = "Mooncloth",            -- Tailoring, 4-day
    -- Salt Shaker (15846) is item-based; excluded here and handled by ScanSaltShaker.
}

-- TBC
local TBC_COOLDOWNS = {
    [47280] = "Brilliant Glass",      -- Jewelcrafting, 1-day
    [28027] = "Prismatic Sphere",     -- Enchanting
    [31373] = "Spellcloth",           -- Tailoring cloth spec, 3-day
    [36686] = "Shadowcloth",          -- Tailoring cloth spec, 3-day
    [28028] = "Void Sphere",          -- Enchanting
    [26751] = "Primal Mooncloth",     -- Tailoring cloth spec, 3-day
}

-- Wrath
local WRATH_COOLDOWNS = {
    [56002] = "Ebonweave",            -- Tailoring cloth spec, 4-day
    [56005] = "Glacial Bag",          -- Tailoring, 7-day
    [62242] = "Icy Prism",            -- Jewelcrafting, 1-day
    [61288] = "Minor Inscription Research",   -- Inscription, 1-day
    [56001] = "Moonshroud",           -- Tailoring cloth spec, 4-day
    [60893] = "Northrend Alchemy Research",   -- Alchemy, 7-day
    [61177] = "Northrend Inscription Research", -- Inscription, 1-day
    [56003] = "Spellweave",           -- Tailoring cloth spec, 4-day
    [55208] = "Titansteel Bar",       -- Blacksmithing/Mining, 1-day
}

-- Cata
local CATA_COOLDOWNS = {
    [75146] = "Dream of Azshara",     -- Tailoring Dreamcloth, 4-day
    [75142] = "Dream of Deepholm",    -- Tailoring Dreamcloth, 4-day
    [75144] = "Dream of Hyjal",       -- Tailoring Dreamcloth, 4-day
    [75145] = "Dream of Ragnaros",    -- Tailoring Dreamcloth, 4-day
    [75141] = "Dream of Skywall",     -- Tailoring Dreamcloth, 4-day
    [73478] = "Fire Prism",           -- Jewelcrafting, 1-day
    [86654] = "Forged Documents",     -- Inscription (Horde), 1-day
    [89244] = "Forged Documents",     -- Inscription (Alliance), 1-day
}

-- MoP
local MOP_COOLDOWNS = {
    [139170] = "Balanced Trillium Ingot",    -- Blacksmithing, 1-day
    [125557] = "Imperial Silk",              -- Tailoring, 1-day
    [139176] = "Jard's Peculiar Energy Source", -- Engineering, 1-day
    -- JC Daily Cuts (7 spells, handled via DAILY_JC_CUTS group below)
    [140040] = "Magnificence of Leather",    -- Leatherworking
    [140041] = "Magnificence of Scales",     -- Leatherworking
    [138646] = "Lightning Steel Ingot",      -- Blacksmithing, 1-day
    [112996] = "Scroll of Wisdom",           -- Inscription, 1-day
    [116499] = "Sha Crystal",                -- Enchanting, 1-day
}

-- ---------------------------------------------------------------------------
-- Transmute spell IDs — share a single cooldown timer per expansion
-- Ordered alphabetically by name within each expansion.
-- ---------------------------------------------------------------------------

local VANILLA_TRANSMUTES = {
    [17187] = "Transmute: Arcanite",
    [17559] = "Transmute: Air to Fire",
    [17560] = "Transmute: Fire to Earth",
    [17561] = "Transmute: Earth to Water",
    [17562] = "Transmute: Water to Air",
    [11479] = "Transmute: Iron to Gold",
    [11480] = "Transmute: Mithril to Truesilver",
    [17563] = "Transmute: Undeath to Water",
    [17564] = "Transmute: Water to Undeath",
    [17566] = "Transmute: Earth to Life",
    [17565] = "Transmute: Life to Earth",
}

local TBC_TRANSMUTES = {
    [28566] = "Transmute: Primal Air to Fire",
    [28576] = "Transmute: Primal Earth to Life",   -- corrected from 28585 alias
    [28567] = "Transmute: Primal Earth to Water",
    [28568] = "Transmute: Primal Fire to Earth",
    [28583] = "Transmute: Primal Fire to Mana",
    [32765] = "Transmute: Earthstorm Diamond",
    [28584] = "Transmute: Primal Life to Earth",
    [28582] = "Transmute: Primal Mana to Fire",
    [28580] = "Transmute: Primal Shadow to Water",
    [32766] = "Transmute: Skyfire Diamond",
    [28569] = "Transmute: Primal Water to Air",
    [28581] = "Transmute: Primal Water to Shadow",
}

local WRATH_TRANSMUTES = {
    [53777] = "Transmute: Eternal Air to Earth",
    [53776] = "Transmute: Eternal Air to Water",
    [66659] = "Transmute: Cardinal Ruby",
    [53781] = "Transmute: Eternal Earth to Air",
    [53782] = "Transmute: Eternal Earth to Shadow",
    [53784] = "Transmute: Eternal Water to Fire",
    [53783] = "Transmute: Eternal Water to Air",
    [53774] = "Transmute: Eternal Fire to Water",
    [53775] = "Transmute: Eternal Fire to Life",
    [66662] = "Transmute: Dreadstone",
    [66658] = "Transmute: Ametrine",
    [66664] = "Transmute: Eye of Zul",
    [66660] = "Transmute: King's Amber",
    [53780] = "Transmute: Eternal Shadow to Life",
    [53779] = "Transmute: Eternal Shadow to Earth",
    [53773] = "Transmute: Eternal Life to Fire",
    [53771] = "Transmute: Eternal Life to Shadow",
    [66663] = "Transmute: Majestic Zircon",
}

local CATA_TRANSMUTES = {
    [78866] = "Transmute: Living Elements",
    [80243] = "Transmute: Truegold",
}

local MOP_TRANSMUTES = {
    [114780] = "Transmute: Living Steel",
}

-- ---------------------------------------------------------------------------
-- Reagents — DERIVED from ProfessionDB, not transcribed here.
--
-- These three tables (REAGENTS / MULTI_REAGENTS / TRANSMUTE_REAGENTS) used to be
-- ~90 lines of hand-written { id = itemId, qty = N }. NINE OF THE 49 ENTRIES
-- WERE WRONG, and every one of them had a correct comment beside it:
--
--   17187 Transmute: Arcanite   -> 12364 "Huge Emerald"     (Arcane Crystal is 12363)
--   11480 Mithril to Truesilver -> 3859  "Steel Bar"        (Mithril Bar is 3860)
--   17559/60/61/62 elemental    -> 7067-7070 "Elemental X"  (the recipes take "Essence of X",
--                                                            7076/7078/7080/7082 — different items)
--   28569/28581 Primal Water    -> 22454                    (does not exist as an item AT ALL)
--   28584 Primal Life           -> 22455                    (likewise)
--
-- The consequence was silent and user-visible: the Cooldowns tab's reagent
-- count, its [AH] price lookup, its [Bank] withdrawal button and its
-- shopping-list add all pointed at the wrong item — or, for the three
-- nonexistent ids, at nothing that could ever resolve.
--
-- Nothing detected it because the numbers were only ever compared to the
-- comment next to them. ProfessionDB has carried the authoritative reagent list
-- from Blizzard's own SpellReagents the entire time; this file was a second,
-- hand-maintained copy of data we already had, which is exactly the shape that
-- rots. Tests/cooldownreagents_spec.lua now cross-checks what remains.
--
-- WHAT IS STILL HAND-MAINTAINED, and why it has to be: which single reagent to
-- FEATURE on a collapsed row when the recipe takes several. That is a display
-- choice — Titansteel Bar takes 4 reagents and the one worth showing is the 3x
-- Titanium Bar — and no DBC field expresses it. Ids only; the QUANTITY always
-- comes from ProfessionDB, so the pair can no longer disagree.
-- ---------------------------------------------------------------------------

local FEATURED_REAGENT = {
    [55208] = 41163,  -- Titansteel Bar   -> Titanium Bar (3x), not the 3 eternals
    [62242] = 43102,  -- Icy Prism        -> Frozen Orb, not the 3 uncommon gems
    [56005] = 41594,  -- Glacial Bag      -> Moonshroud
}

-- Cooldowns keyed by ITEM id rather than craft spell, so ProfessionDB has no
-- recipe to look up. Salt Shaker is a tool whose Use effect has the cooldown;
-- it is scanned via GetItemCooldown, not GetSpellCooldown.
local ITEM_REAGENTS = {
    [15846] = { id = 8150, qty = 1 },  -- Salt Shaker -> Deeprock Salt
}

-- Retained ONLY as the fallback for a client where ProfessionDB is absent or
-- has no entry for a cooldown spell. Kept deliberately small; anything here is
-- unverified against DBC by definition, so prefer letting the row show no
-- reagent over inventing one.
-- Every entry below was cross-checked against ProfessionDB's SpellReagents data
-- and agrees with it. They are kept ONLY so a client without ProfessionDB still
-- shows something; the live path derives from the library. Entries that
-- DISAGREED with DBC were deleted rather than corrected — a fallback nobody can
-- verify is how this went wrong in the first place.
local REAGENT_FALLBACK = {
    -- Vanilla
    [18560] = { id = 14256, qty = 2  },  -- Mooncloth → 2x Felcloth
    -- TBC — Primal Mooncloth / Spellcloth / Shadowcloth take three reagents each
    -- and render as expand rows, so they have no single-reagent entry.
    [28027] = { id = 22449, qty = 4  },  -- Prismatic Sphere → 4x Large Prismatic Shard
    [28028] = { id = 22450, qty = 2  },  -- Void Sphere → 2x Void Crystal
    -- Wrath
    [56001] = { id = 41511, qty = 1  },  -- Moonshroud → Bolt of Imbued Frostweave
    [56002] = { id = 41511, qty = 1  },  -- Ebonweave → Bolt of Imbued Frostweave
    [56003] = { id = 41511, qty = 1  },  -- Spellweave → Bolt of Imbued Frostweave
    -- Cata
    [75141] = { id = 53643, qty = 8  },  -- Dream of Azshara → Bolt of Embersilk Cloth
    [75142] = { id = 53643, qty = 8  },  -- Dream of Deepholm → Bolt of Embersilk Cloth
    [75144] = { id = 53643, qty = 8  },  -- Dream of Hyjal → Bolt of Embersilk Cloth
    [75145] = { id = 53643, qty = 8  },  -- Dream of Ragnaros → Bolt of Embersilk Cloth
    [75146] = { id = 53643, qty = 8  },  -- Dream of Skywall → Bolt of Embersilk Cloth
    -- MoP
    [125557] = { id = 82441,  qty = 8  }, -- Imperial Silk → Bolt of Windwool Cloth
    [138646] = { id = 72096,  qty = 10 }, -- Lightning Steel Ingot → Ghost Iron Bar
}



-- Output item name overrides — for cooldowns where the spell/item name is NOT the
-- produced item (e.g. Salt Shaker produces Refined Deeprock Salt, not "Salt Shaker").
-- Any ID not listed here falls back to the cooldown display name at runtime.
local OUTPUT_OVERRIDES = {
    [15846] = "Refined Deeprock Salt",  -- Salt Shaker tool → product name
}

-- ---------------------------------------------------------------------------
-- Profession-spec bonus output map
--
-- Indexed by spec spell ID (the spell granted by the spec quest, what
-- IsSpellKnown returns true for). Each entry lists the cooldown spell IDs
-- whose output the spec affects, plus a bonusType that drives the indicator
-- tooltip text:
--   "guaranteed" = the spec ALWAYS doubles output (Mooncloth/Shadoweave/Spellfire)
--   "proc"       = the spec gives a chance to proc extra output (Transmutation Master)
--
-- Only specs that actually affect a shared-cooldown row are listed here.
-- Elixir Master / Potion Master DO proc on elixir/flask/potion crafts, but
-- those aren't shared-cooldown crafts so they have no row to indicate on.
-- Engineering specs (Gnomish/Goblin) gate exclusive recipes rather than
-- bonus output. Wrath cloth cooldowns (Ebonweave/Spellweave/Moonshroud)
-- are universal — no Wrath-era cloth spec.
--
-- The 4.0.1 (Cata) patch removed the Vanilla/TBC proc system entirely; the
-- caller is responsible for gating the indicator render on isTBC/isWrath.
-- ---------------------------------------------------------------------------

local SPEC_BONUSES = {
    -- Alchemy: Transmutation Master (28672) — procs extra output on EVERY
    -- transmute. All TBC + Wrath transmute spell IDs are listed individually
    -- (matches the spells in VANILLA_TRANSMUTES / TBC_TRANSMUTES / WRATH_TRANSMUTES
    -- above). Vanilla transmutes aren't listed because the spec didn't exist
    -- yet in Vanilla — a Wrath alchemist who never re-specced doesn't proc on
    -- Vanilla transmutes either (the spec is TBC-introduced content).
    -- (28683 = "Leap", 28682 = "Combustion" — both were wrong; 28672 is the spec.)
    [28672] = {
        bonusType = "proc",
        spells = {
            -- TBC transmutes
            [28566] = true, [28567] = true, [28568] = true, [28569] = true,
            [28576] = true, [28580] = true, [28581] = true, [28582] = true,
            [28583] = true, [28584] = true, [32765] = true, [32766] = true,
            -- Wrath eternal/gem transmutes
            [53771] = true, [53773] = true, [53774] = true, [53775] = true,
            [53776] = true, [53777] = true, [53779] = true, [53780] = true,
            [53781] = true, [53782] = true, [53783] = true, [53784] = true,
            [66658] = true, [66659] = true, [66660] = true, [66662] = true,
            [66663] = true, [66664] = true,
        },
        -- Used by CooldownsTab when the transmute group row collapses many
        -- transmutes into one row: any spec marked affectsAllTransmutes lights
        -- up the group-row indicator without needing per-spell lookups.
        affectsAllTransmutes = true,
    },

    -- Tailoring cloth specs — each spec GUARANTEES 2x output on its specific
    -- cloth cooldown. (Patch 2.1+: the proc was changed from random to flat 2x.)
    [26798] = { bonusType = "guaranteed", spells = { [26751] = true } }, -- Mooncloth Tailoring → Primal Mooncloth
    [26801] = { bonusType = "guaranteed", spells = { [36686] = true } }, -- Shadoweave Tailoring → Shadowcloth
    [26797] = { bonusType = "guaranteed", spells = { [31373] = true } }, -- Spellfire Tailoring  → Spellcloth
}

-- Spell IDs where GetSpellTexture returns a bad/missing icon.
-- Value is the item ID whose icon should be used instead.
local ICON_OVERRIDES = {
    [18560] = 14342,  -- Mooncloth spell → Mooncloth item icon
    [15846] = 15846,  -- Salt Shaker → Salt Shaker item icon
    -- TBC tailoring cloth specs — GetSpellTexture returns generic net/cloth
    -- icons (Blizzard never assigned proper spell icons to these crafts).
    -- Map each to the produced bolt's item icon instead.
    [26751] = 21845,  -- Primal Mooncloth spell → Bolt of Primal Mooncloth icon
    [31373] = 24272,  -- Spellcloth spell      → Bolt of Spellcloth icon
    [36686] = 24271,  -- Shadowcloth spell     → Bolt of Shadowcloth icon
}

-- ---------------------------------------------------------------------------
-- Multi-spell cooldown groups
-- Spells in a group collapse into one row with a click-to-expand popup.
-- Transmutes always form their own implicit group; these cover others.
-- { groupKey, label, spells = { [spellId] = name } }
-- ---------------------------------------------------------------------------

local COOLDOWN_GROUPS = {
    {
        groupKey = "bs_ingot",
        label    = "BS Ingot",
        spells   = { [138646] = "Balanced Trillium Ingot", [139170] = "Lightning Steel Ingot" },
    },
    {
        groupKey = "dreamcloth",
        label    = "Dreamcloth",
        spells   = { [75141] = "Dream of Azshara", [75142] = "Dream of Deepholm",
                     [75144] = "Dream of Hyjal",   [75145] = "Dream of Ragnaros",
                     [75146] = "Dream of Skywall" },
    },
    {
        groupKey = "inscription_research",
        label    = "Inscription Research",
        spells   = { [61288] = "Minor Inscription Research", [61177] = "Northrend Inscription Research" },
    },
    {
        groupKey = "jc_daily",
        label    = "JC Daily Cut",
        spells   = { [131593] = "River's Heart",   [131686] = "Primordial Ruby",
                     [131695] = "Sun's Radiance",  [131690] = "Vermilion Onyx",
                     [131691] = "Imperial Amethyst",[131688] = "Wild Jade",
                     [140050] = "Serpent's Heart" },
    },
    {
        groupKey = "magnificence",
        label    = "Magnificence",
        spells   = { [140040] = "Magnificence of Leather", [140041] = "Magnificence of Scales" },
    },
}

-- ---------------------------------------------------------------------------
-- Cooldown spellId → profession ID
-- Which profession each NON-transmute cooldown belongs to, so a character who
-- UNLEARNS that profession stops showing its cooldown (checked against the
-- authoritative gdb.skills snapshot). Transmutes are all Alchemy (171) and are
-- assigned in Build() from the transmute set, so they aren't repeated here.
-- ---------------------------------------------------------------------------

local PROFESSION_OF = {
    -- Leatherworking (165)
    [140040] = 165, [140041] = 165,  -- Magnificence
    -- Salt Shaker (item 15846): its Use effect "Requires Leatherworking (250)",
    -- so dropping LW means you can no longer use it — its cooldown must go too.
    [15846] = 165,
    -- Tailoring (197)
    [18560] = 197,  -- Mooncloth
    [26751] = 197,  -- Primal Mooncloth
    [31373] = 197,  -- Spellcloth
    [36686] = 197,  -- Shadowcloth
    [56001] = 197,  -- Moonshroud
    [56002] = 197,  -- Ebonweave
    [56003] = 197,  -- Spellweave
    [56005] = 197,  -- Glacial Bag
    [75141] = 197, [75142] = 197, [75144] = 197, [75145] = 197, [75146] = 197,  -- Dreamcloth
    [125557] = 197, -- Imperial Silk
    -- Enchanting (333)
    [28027] = 333,  -- Prismatic Sphere
    [28028] = 333,  -- Void Sphere
    [116499] = 333, -- Sha Crystal
    -- Jewelcrafting (755)
    [47280] = 755,  -- Brilliant Glass
    [62242] = 755,  -- Icy Prism
    [73478] = 755,  -- Fire Prism
    [131593] = 755, [131686] = 755, [131695] = 755, [131690] = 755,
    [131691] = 755, [131688] = 755, [140050] = 755,  -- JC daily cuts
    -- Inscription (773)
    [61288] = 773,  -- Minor Inscription Research
    [61177] = 773,  -- Northrend Inscription Research
    [86654] = 773, [89244] = 773,  -- Forged Documents
    [112996] = 773, -- Scroll of Wisdom
    -- Blacksmithing (164)
    [55208] = 164,  -- Titansteel Bar
    [139170] = 164, -- Balanced Trillium Ingot
    [138646] = 164, -- Lightning Steel Ingot
    -- Engineering (202)
    [139176] = 202, -- Jard's Peculiar Energy Source
    -- Alchemy (171)
    [60893] = 171,  -- Northrend Alchemy Research
}

-- ---------------------------------------------------------------------------
-- Public accessor — builds version-appropriate tables once on first call
-- ---------------------------------------------------------------------------

local _cache = nil

local function Build()
    local a = addon
    local cooldowns, transmutes = {}, {}

    -- Cumulative loading: spell/item IDs from earlier expansions stay valid on
    -- later clients (Wrath transmutes still tick on Cata, etc.), and a Cata
    -- alchemist almost certainly still has them on cooldown.  The previous
    -- version-exclusive loading missed transmutes from any expansion before
    -- the current one, so casting e.g. Eternal Fire on a Cata client never
    -- showed up on the cooldown tab.
    if a.isVanilla or a.isTBC or a.isWrath or a.isCata or a.isMoP then
        for id, name in pairs(VANILLA_COOLDOWNS)   do cooldowns[id]  = name end
        for id, name in pairs(VANILLA_TRANSMUTES)  do transmutes[id] = name end
    end
    if a.isTBC or a.isWrath or a.isCata or a.isMoP then
        for id, name in pairs(TBC_COOLDOWNS)       do cooldowns[id]  = name end
        for id, name in pairs(TBC_TRANSMUTES)      do transmutes[id] = name end
    end
    if a.isWrath or a.isCata or a.isMoP then
        for id, name in pairs(WRATH_COOLDOWNS)     do cooldowns[id]  = name end
        for id, name in pairs(WRATH_TRANSMUTES)    do transmutes[id] = name end
    end
    if a.isCata or a.isMoP then
        for id, name in pairs(CATA_COOLDOWNS)      do cooldowns[id]  = name end
        for id, name in pairs(CATA_TRANSMUTES)     do transmutes[id] = name end
    end
    if a.isMoP then
        for id, name in pairs(MOP_COOLDOWNS)       do cooldowns[id]  = name end
        for id, name in pairs(MOP_TRANSMUTES)      do transmutes[id] = name end
    end

    -- Build a fast spellId → group lookup
    local groupBySpell = {}
    for _, group in ipairs(COOLDOWN_GROUPS) do
        for spellId in pairs(group.spells) do
            groupBySpell[spellId] = group
        end
    end

    -- spellId → profession ID. Every transmute is Alchemy (171); the rest come
    -- from the static PROFESSION_OF map. Drives the "unlearned the profession →
    -- drop its cooldown" prune/filter against the authoritative gdb.skills set.
    local professionOf = {}
    for id in pairs(transmutes) do professionOf[id] = 171 end
    for id, profId in pairs(PROFESSION_OF) do professionOf[id] = profId end

    -- ---- Reagents, derived from ProfessionDB -------------------------------
    -- Read from addon.recipeDB (which Data/RecipeDB.lua points at the library)
    -- rather than transcribed here. See the note above FEATURED_REAGENT: the
    -- hand-written tables this replaces had nine wrong entries out of 49,
    -- including three item ids that do not exist.
    --
    -- Keyed by profession because that is how recipeDB is keyed, and
    -- professionOf already answers it for every cooldown we track.
    local reagents, multiReagents = {}, {}

    local function reagentsFor(spellId)
        local profId = professionOf[spellId]
        if not profId then return nil end
        local profMeta = a.recipeDB and a.recipeDB[profId]
        local meta     = profMeta and profMeta[spellId]
        local list     = meta and meta.reagents
        if type(list) ~= "table" or next(list) == nil then return nil end
        return list
    end

    for _, set in ipairs({ cooldowns, transmutes }) do
        for spellId in pairs(set) do
            local list = reagentsFor(spellId)
            if list then
                -- Count first: one reagent is a plain row, several is an
                -- expand row unless a featured reagent says otherwise.
                local only, n = nil, 0
                for itemId, qty in pairs(list) do
                    n = n + 1
                    only = { id = itemId, qty = qty }
                end
                local featured = FEATURED_REAGENT[spellId]
                if n == 1 then
                    reagents[spellId] = only
                elseif featured and list[featured] then
                    reagents[spellId] = { id = featured, qty = list[featured] }
                else
                    -- Sorted by item id so the popup's order is stable across
                    -- sessions; pairs() order is not.
                    local rows = {}
                    for itemId, qty in pairs(list) do
                        rows[#rows + 1] = { id = itemId, qty = qty }
                    end
                    table.sort(rows, function(x, y) return x.id < y.id end)
                    multiReagents[spellId] = rows
                end
            elseif REAGENT_FALLBACK[spellId] then
                -- No library, or a cooldown the shipped data has no recipe for.
                reagents[spellId] = REAGENT_FALLBACK[spellId]
            end
        end
    end

    -- Item-keyed cooldowns (Salt Shaker) have no craft spell to look up.
    for itemId, rg in pairs(ITEM_REAGENTS) do reagents[itemId] = rg end

    return {
        cooldowns      = cooldowns,
        transmutes     = transmutes,
        professionOf   = professionOf,
        reagents       = reagents,
        multiReagents  = multiReagents,
        -- Transmutes now resolve through the same `reagents` table as
        -- everything else; kept as an alias because GUI/CooldownsTab.lua and
        -- Modules/ReagentWatch.lua both read `data.reagents[id] or
        -- data.transReagents[id]` and neither should have to care.
        transReagents  = reagents,
        iconOverrides  = ICON_OVERRIDES,
        outputOverrides = OUTPUT_OVERRIDES,
        groups         = COOLDOWN_GROUPS,
        groupBySpell   = groupBySpell,
        specBonuses    = SPEC_BONUSES,
        saltShakerItem = 15846,
    }
end

function addon:GetCooldownData()
    if not _cache then _cache = Build() end
    return _cache
end

--- Augment the cached transmute catalogue with any "Transmute*" alchemy
--- recipes from the guild DB.  Self-heals for clients (Classic Era
--- Anniversary, alt-locale spell IDs) where the actual transmute spell IDs
--- don't match VANILLA_TRANSMUTES.  Idempotent — only adds missing entries.
--- Returns the number of new entries added.
---
--- Also backfills `rd.spellId` via GetSpellLink(rd.name) when the recipe
--- arrived without a spellId.  On some Classic Era builds (notably
--- Anniversary), transmute spells don't appear in the GetNumSpellTabs /
--- GetSpellBookItemInfo enumeration that BuildSpellNameCache uses, so
--- ScanTradeSkillInto stores the recipe with rd.spellId = nil.  GetSpellLink
--- works for any spell the player knows by name regardless of spellbook
--- presentation, so we use it as a fallback name→ID lookup.
function addon:RefreshTransmuteCatalogueFromRecipes()
    -- v0.7.0: gdb.recipes no longer stores name/spellId. Walk the shipped
    -- addon.recipeDB[171] (authoritative metadata) for transmute names and
    -- add any spellIds (via meta.teaches) that aren't in the static catalogue.
    local data = self:GetCooldownData()
    if not data or not data.transmutes then return 0 end
    local profMeta = self.recipeDB and self.recipeDB[171]
    if not profMeta then return 0 end

    local added = 0
    for _, meta in pairs(profMeta) do
        if type(meta.name) == "string" and meta.name:find("[Tt]ransmute") then
            local spellId = meta.teaches
            if spellId and not data.transmutes[spellId] then
                data.transmutes[spellId] = meta.name
                added = added + 1
            end
        end
    end
    return added
end
