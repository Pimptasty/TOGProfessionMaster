-- TOG Profession Master -- Locale system bootstrap
--
-- Loads FIRST (alphabetically before all locale files) per the TOC, and
-- defines addon.NewLocale(code, isDefault) which every Locale/<code>.lua
-- file uses to register itself.
--
-- Why this layer exists:
--   AceLocale-3.0 only populates the locale table that matches GetLocale()
--   (plus the default-locale table, which the user sees if no locale matches).
--   Non-matching locale files exit early via `if not L then return end`, so
--   their translations never reach memory. That's fine for auto-detect, but
--   it blocks the "UI Language Override" Settings dropdown — to force the
--   addon into French on an enUS client we need the French strings IN
--   memory, not just on disk.
--
--   This helper writes every L["key"] = "value" assignment to BOTH:
--     • AceLocale's standard table (when the locale matches the current
--       client, so the auto-detect path works exactly as before), AND
--     • addon.Locales[code] (always, so the override path has every locale
--       available for a runtime swap by ApplyLocaleOverride).
--
-- Usage in each locale file (replaces the old AceLocale boilerplate):
--   local _, addon = ...
--   local L = addon.NewLocale("deDE")        -- isDefault defaults to false
--   L["TabProfessions"] = "Berufe"
--   ...

local _, addon = ...
addon.Locales = addon.Locales or {}

function addon.NewLocale(code, isDefault)
    addon.Locales[code] = addon.Locales[code] or {}
    local store = addon.Locales[code]

    -- Register with AceLocale. Returns the AceLocale-managed table only when
    -- this is the current client locale OR isDefault=true. Otherwise nil.
    local AceL = LibStub("AceLocale-3.0"):NewLocale("TOGProfessionMaster", code, isDefault)

    -- Return a proxy whose __newindex writes to both stores. The locale file
    -- writes to the proxy via L["key"] = "value" as before; never reads from
    -- it (no __index needed). AceL stays nil on non-current locales — the
    -- proxy still records into addon.Locales[code] for the override path.
    return setmetatable({}, {
        __newindex = function(_, k, v)
            store[k] = v
            if AceL then AceL[k] = v end
        end,
    })
end
