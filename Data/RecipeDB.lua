local _, addon = ...

-- Recipe data source: LibProfessionDB-1.0.
--
-- TOGProfessionMaster no longer bundles its own recipe tables. The static
-- recipe reference (names, reagents, skill-up difficulty tiers, required skill,
-- produced item, enriched effect text) now comes from the standalone
-- LibProfessionDB-1.0 library, declared as a required dependency in every .toc
-- so it is guaranteed loaded before this file.
--
-- The library ships the correct POINT-IN-TIME recipe set for this exact game
-- version + locale (Vanilla data on a Vanilla client, TBC data on a TBC client,
-- and so on) — it never merges expansions. We point addon.recipeDB straight at
-- the library's per-profession tables (read-only on our side; TOGPM only ever
-- reads recipeDB, never mutates it).
--
-- Because the data is already version-scoped, the per-client expansion gates in
-- GUI/BrowserTab.lua (passesClientGate) and GUI/MissingRecipesTab.lua — which
-- existed only to filter the old all-version merged union — short-circuit when
-- addon.recipeDBFromLib is set. (Content-phase gating on TBC still applies; the
-- library carries the `phase` field.)

local lib = LibStub and LibStub("LibProfessionDB-1.0", true)
if not lib then
    -- Required dependency, so this should never happen on a normal install.
    -- Leave addon.recipeDB as the empty table TOGProfessionMaster.lua created
    -- so every consumer degrades gracefully (empty lists, no errors).
    return
end

addon.recipeDB = addon.recipeDB or {}
for _, profId in ipairs(lib:GetProfessions()) do
    addon.recipeDB[profId] = lib:GetRecipes(profId)
end
addon.recipeDBFromLib = true
