local _, addon = ...

-- Recipe source data: LibProfessionDB-1.0.
--
-- TOGProfessionMaster no longer bundles its own `Data/Sources/*.lua`. Those
-- twelve files were 380,000 lines and 6.7 MB of a single ALL-EXPANSION merge,
-- loaded verbatim on every client — a Vanilla player carried Cata's drop
-- tables. The data now ships per-version from the library, alongside the recipe
-- tables it describes, in 968 KB for all five versions combined.
--
-- Same reasoning as Data/RecipeDB.lua: the addon that consumes the data should
-- not be the repo generating it. The builder
-- (ProfessionDB/tools/build_authoritative_sources.py) reads the TrinityCore
-- Cata and AzerothCore Wrath world databases and emits into ProfessionDB.
--
-- WHAT CHANGED FOR CONSUMERS, beyond where the table comes from:
--
--   * Sources are keyed by SPELL alone, not [profId][spellId]. A craft spell
--     belongs to exactly one skill line, so the profession key was never adding
--     information — but it means `addon.sourceDB[profId]` is now a per-profession
--     VIEW built on demand rather than a stored table.
--   * Each kind now carries the npc/object IDS and their English NAMES, not
--     just its own presence. "Trainer" can become "Trainer: Brawn". Nothing in
--     this addon renders that yet; the data is there for it.
--   * Lists are capped at 12 entries with the true count alongside, because
--     1,649 recipes drop from 50+ creatures each. Read `.total`, never `#list`.
--
-- Names are ENGLISH ONLY (they come from emulator creature_template, which is
-- not localized) unlike recipe names, which ship in 12 languages.

local lib = LibStub and LibStub("LibProfessionDB-1.0", true)

-- addon.sourceDB is created in TOGProfessionMaster.lua and stays a table no
-- matter what, so every consumer's `addon.sourceDB and addon.sourceDB[profId]`
-- guard behaves. Without the library it simply stays empty and the UI shows
-- "Unknown" sources, which is the same degradation as a recipe with no source.
addon.sourceDB = addon.sourceDB or {}

if not (lib and lib.GetRecipeSources) then
    -- Either ProfessionDB is missing (a required dependency, so this should not
    -- happen on a normal install) or it predates MINOR 10. Feature-detect on the
    -- METHOD rather than the MINOR so a partial rollback degrades instead of
    -- erroring.
    return
end

addon.sourceDBFromLib = true

-- The two production consumers — GUI/SharedWidgets.lua's ItemLink.RecipeDetails
-- and GUI/MissingRecipesTab.lua's BuildMissingList — both index
-- `addon.sourceDB[profId][recipeId]` and then ask which KINDS are present. A
-- metatable keeps that shape working unchanged against spell-keyed library data,
-- so neither call site had to move.
--
-- Built lazily per profession and cached: BuildMissingList hoists
-- `addon.sourceDB[profId]` out of its per-recipe loop, so this resolves once per
-- list build, not once per row.
local profCache = setmetatable({}, {
    __index = function(t, profId)
        local recipes = addon.recipeDB and addon.recipeDB[profId]
        local view = setmetatable({}, {
            __index = function(inner, recipeId)
                -- GetRecipeSources, NOT GetRecipeSourceKinds.
                --
                -- The cheap form returns `{ trainer = true }`, and that shipped
                -- a live error: GUI/SharedWidgets.lua's RecipeDetails does
                -- `next(npcs)` on each kind's value to reject a kind that is
                -- present but empty, and `next(true)` raises "bad argument #1
                -- to 'next' (table expected, got boolean)" — once per drawn row,
                -- 112 times on one Missing Recipes draw.
                --
                -- The contract this table has to honour is the OLD sourceDB's:
                -- every kind's value is a non-empty TABLE. GetRecipeSources
                -- satisfies it (each kind is a list of {id, name} records, and
                -- empty kinds are omitted entirely), and hands consumers the npc
                -- ids and names as a bonus. The per-call allocation it costs is
                -- paid once per recipe thanks to the rawset cache below.
                local sources = lib:GetRecipeSources(recipeId)
                rawset(inner, recipeId, sources or false)
                return sources
            end,
        })
        -- Guard the view to this profession's own recipes. Without it, asking
        -- sourceDB[171][someTailoringSpell] would answer, because the library's
        -- store is not partitioned by profession — and MissingRecipesTab walks
        -- recipe ids it already scoped to a profession, so a leak would be
        -- silent rather than visible.
        if recipes then
            local scoped = setmetatable({}, {
                __index = function(_, recipeId)
                    if recipes[recipeId] == nil then return nil end
                    return view[recipeId]
                end,
            })
            rawset(t, profId, scoped)
            return scoped
        end
        rawset(t, profId, view)
        return view
    end,
})

setmetatable(addon.sourceDB, { __index = profCache })

--- Full source detail for a recipe — ids and English names, not just the kinds.
--- Returns nil when nothing is known, which is a real answer for ~25% of
--- recipes; check addon.IsAutoTaughtRecipe before calling it unknown.
--- Each kind's list carries `.total`, which is NOT always `#list` (lists are
--- capped at 12). See LibProfessionDB-1.0.lua's GetRecipeSources.
--- @return table|nil { trainer = { { id, name }, ... , total = n }, vendor = ... }
function addon:GetRecipeSourceDetail(recipeId)
    if not recipeId then return nil end
    return lib:GetRecipeSources(recipeId)
end
