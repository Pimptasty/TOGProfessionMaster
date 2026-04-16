-- TOG Profession Master — Profession icon map
-- Maps WoW profession skill line IDs to their FileDataID icons.
-- Profession IDs are the values returned by GetProfessionInfo() / GetProfessions().
-- FileDataIDs are queried at runtime via GetSpellTexture / appearance in the client.
-- Ordered alphabetically by profession name.

local _, addon = ...

addon.ProfessionIcons = {
    [171] = 136240,  -- Alchemy
    [164] = 136241,  -- Blacksmithing
    [185] = 133971,  -- Cooking
    [333] = 136244,  -- Enchanting
    [202] = 136243,  -- Engineering
    [356] = 136245,  -- Fishing
    [182] = 136065,  -- Herbalism
    [773] = 237171,  -- Inscription
    [755] = 134071,  -- Jewelcrafting
    [165] = 133611,  -- Leatherworking
    [186] = 136248,  -- Mining
    [393] = 134366,  -- Skinning
    [197] = 136249,  -- Tailoring
}

-- Fallback icon used when a profession ID is not in the map above.
addon.ProfessionIconFallback = 134400  -- INV_Misc_QuestionMark
