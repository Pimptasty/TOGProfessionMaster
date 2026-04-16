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
    -- Salt Shaker (15846) is item-based; scanned separately via GetItemCooldown
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
-- Primary reagent for non-transmute cooldowns
-- { [spellId or itemId] = { id = itemId, qty = N } }
-- Salt Shaker uses item ID 15846 as the key (scanned via GetItemCooldown).
-- ---------------------------------------------------------------------------

local REAGENTS = {
    -- Vanilla
    [18560] = { id = 14256, qty = 2  },  -- Mooncloth → 2x Felcloth
    [15846] = { id = 8150,  qty = 1  },  -- Salt Shaker → Deeprock Salt
    -- TBC
    [26751] = { id = 21842, qty = 1  },  -- Primal Mooncloth → Bolt of Imbued Netherweave
    [31373] = { id = 21842, qty = 1  },  -- Spellcloth → Bolt of Imbued Netherweave
    [36686] = { id = 21842, qty = 1  },  -- Shadowcloth → Bolt of Imbued Netherweave
    -- Wrath
    [62242] = { id = 43102, qty = 1  },  -- Icy Prism → Frozen Orb
    [56001] = { id = 41511, qty = 1  },  -- Moonshroud → Bolt of Imbued Frostweave
    [56002] = { id = 41511, qty = 1  },  -- Ebonweave → Bolt of Imbued Frostweave
    [56003] = { id = 41511, qty = 1  },  -- Spellweave → Bolt of Imbued Frostweave
    [56005] = { id = 41594, qty = 4  },  -- Glacial Bag → 4x Moonshroud
    [55208] = { id = 41163, qty = 3  },  -- Titansteel Bar → 3x Titanium Bar
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

-- Primary reagent for transmute spells
local TRANSMUTE_REAGENTS = {
    -- Vanilla
    [17187] = { id = 12364, qty = 1 },  -- Arcanite → Arcane Crystal
    [17559] = { id = 7069,  qty = 1 },  -- Air to Fire → Elemental Air
    [17560] = { id = 7068,  qty = 1 },  -- Fire to Earth → Elemental Fire
    [17561] = { id = 7067,  qty = 1 },  -- Earth to Water → Elemental Earth
    [17562] = { id = 7070,  qty = 1 },  -- Water to Air → Elemental Water
    [11479] = { id = 3575,  qty = 1 },  -- Iron to Gold → Iron Bar
    [11480] = { id = 3859,  qty = 1 },  -- Mithril to Truesilver → Mithril Bar
    -- TBC
    [28566] = { id = 22451, qty = 1 },  -- Primal Air to Fire → Primal Air
    [28567] = { id = 22452, qty = 1 },  -- Primal Earth to Water → Primal Earth
    [28568] = { id = 21884, qty = 1 },  -- Primal Fire to Earth → Primal Fire
    [28569] = { id = 22454, qty = 1 },  -- Primal Water to Air → Primal Water
    [28580] = { id = 22456, qty = 1 },  -- Primal Shadow to Water → Primal Shadow
    [28581] = { id = 22454, qty = 1 },  -- Primal Water to Shadow → Primal Water
    [28582] = { id = 22457, qty = 1 },  -- Primal Mana to Fire → Primal Mana
    [28583] = { id = 21884, qty = 1 },  -- Primal Fire to Mana → Primal Fire
    [28584] = { id = 22455, qty = 1 },  -- Primal Life to Earth → Primal Life
    [28585] = { id = 22452, qty = 1 },  -- Primal Earth to Life → Primal Earth
    -- Wrath eternal transmutes
    [53771] = { id = 35625, qty = 1 },  -- Eternal Life to Shadow → Eternal Life
    [53773] = { id = 35625, qty = 1 },  -- Eternal Life to Fire → Eternal Life
    [53774] = { id = 36860, qty = 1 },  -- Eternal Fire to Water → Eternal Fire
    [53775] = { id = 36860, qty = 1 },  -- Eternal Fire to Life → Eternal Fire
    [53776] = { id = 35623, qty = 1 },  -- Eternal Air to Water → Eternal Air
    [53777] = { id = 35623, qty = 1 },  -- Eternal Air to Earth → Eternal Air
    [53779] = { id = 35627, qty = 1 },  -- Eternal Shadow to Earth → Eternal Shadow
    [53780] = { id = 35627, qty = 1 },  -- Eternal Shadow to Life → Eternal Shadow
    [53781] = { id = 35624, qty = 1 },  -- Eternal Earth to Air → Eternal Earth
    [53782] = { id = 35624, qty = 1 },  -- Eternal Earth to Shadow → Eternal Earth
    [53783] = { id = 35622, qty = 1 },  -- Eternal Water to Air → Eternal Water
    [53784] = { id = 35622, qty = 1 },  -- Eternal Water to Fire → Eternal Water
    -- Cata
    [78866] = { id = 52329, qty = 15 }, -- Living Elements → Volatile Life
    [80243] = { id = 51950, qty = 3  }, -- Truegold → Pyrium Bar
    -- MoP
    [114780] = { id = 72095, qty = 6 }, -- Living Steel → Trillium Bar
}

-- Spell IDs where GetSpellTexture returns a bad/missing icon.
-- Value is the item ID whose icon should be used instead.
local ICON_OVERRIDES = {
    [18560] = 14342,  -- Mooncloth spell → Mooncloth item icon
    [15846] = 15846,  -- Salt Shaker → Salt Shaker item icon
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
-- Public accessor — builds version-appropriate tables once on first call
-- ---------------------------------------------------------------------------

local _cache = nil

local function Build()
    local a = addon
    local cooldowns, transmutes = {}, {}

    if a.isVanilla then
        for id, name in pairs(VANILLA_COOLDOWNS)   do cooldowns[id]  = name end
        for id, name in pairs(VANILLA_TRANSMUTES)  do transmutes[id] = name end
    end
    if a.isTBC then
        for id, name in pairs(TBC_COOLDOWNS)       do cooldowns[id]  = name end
        for id, name in pairs(TBC_TRANSMUTES)      do transmutes[id] = name end
    end
    if a.isWrath then
        for id, name in pairs(WRATH_COOLDOWNS)     do cooldowns[id]  = name end
        for id, name in pairs(WRATH_TRANSMUTES)    do transmutes[id] = name end
    end
    if a.isCata then
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

    return {
        cooldowns      = cooldowns,
        transmutes     = transmutes,
        reagents       = REAGENTS,
        transReagents  = TRANSMUTE_REAGENTS,
        iconOverrides  = ICON_OVERRIDES,
        groups         = COOLDOWN_GROUPS,
        groupBySpell   = groupBySpell,
        saltShakerItem = 15846,
    }
end

function addon:GetCooldownData()
    if not _cache then _cache = Build() end
    return _cache
end
