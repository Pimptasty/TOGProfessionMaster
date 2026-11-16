-- Ultimate Profession Master -- public read API (TOGPM.API).
--
-- The supported way for another addon to read UPM's per-character data, so it
-- never depends on the shape of TOGPM_GuildDB. Asked for by Ultimate Guild
-- Roster (inbox cfb23d25, 2026-11-13), which writes guild notes from each
-- member's spec and professions.
--
-- Stability: everything below is kept working across releases. A change that
-- would break a caller raises VERSION; additions do not.
--
--   TOGPM.API.VERSION                  -> 1
--   TOGPM.API.GetCharacterKey()        -> the logged-in character's key
--   TOGPM.API.GetCharacters()          -> array of every character key UPM holds
--                                         profession or spec data for
--   TOGPM.API.HasData(charKey)         -> true when UPM holds either
--   TOGPM.API.GetProfessions(charKey)  -> array of { profId, name, skillRank,
--                                         skillMax, isPrimary }, primaries
--                                         first, then by profId; {} when none
--   TOGPM.API.GetSpec(charKey)         -> { active, activeId, other, otherId }
--                                         or nil when UPM has no spec for them
--   TOGPM.API.RegisterCallback(owner, "CharacterChanged", fn)
--                                      -> fn(event, charKey) whenever that
--                                         character's professions or spec change,
--                                         from their own scan or from guild sync
--   TOGPM.API.UnregisterCallback(owner, "CharacterChanged")
--
-- Character keys are "Name-Realm" ("Name-NormalizedRealm"), and on WoW Forever
-- the guild roster's own regional "First Last" name (addon:GetCharacterKey).
--
-- Spec names are the OWNER'S client's own words (its locale) and ids are that
-- client's: a talent-tab or specialization id on Era / TBC / MoP / Retail, a
-- talent-tree group id on WoW Forever. `active` is the spec in use; on
-- talent-tab clients it is the tab with the most points. `other` is the second
-- talent group's spec and is nil where the client has no dual spec. Either can
-- be nil when nothing is spent there; a returned table with both nil means
-- "known, no spec". Every returned table is a fresh copy.

local _, addon = ...

local API = { VERSION = 1 }
addon.API = API
TOGPM     = TOGPM or {}
TOGPM.API = API

API.callbacks = LibStub("CallbackHandler-1.0"):New(API)

-- Secondary professions: Cooking, First Aid, Fishing, Archaeology. Everything
-- else UPM records is a primary (crafting or gathering).
local SECONDARY = { [185] = true, [129] = true, [356] = true, [794] = true }

local function gdb()
    return addon.guildDb and addon:GetGuildDb() or nil
end

function API.GetCharacterKey()
    return addon:GetCharacterKey()
end

function API.GetCharacters()
    local db, seen, out = gdb(), {}, {}
    if not db then return out end
    for _, tbl in ipairs({ db.skills or {}, db.talents or {} }) do
        for ck, v in pairs(tbl) do
            if not seen[ck] and type(v) == "table" and next(v) ~= nil then
                seen[ck] = true
                out[#out + 1] = ck
            end
        end
    end
    table.sort(out)
    return out
end

function API.GetProfessions(charKey)
    local db, out = gdb(), {}
    local s = db and db.skills and db.skills[charKey]
    if type(s) ~= "table" then return out end
    for profId, rec in pairs(s) do
        if type(profId) == "number" and type(rec) == "table" then
            out[#out + 1] = {
                profId    = profId,
                name      = addon.Scanner and addon.Scanner.ProfessionName(profId) or nil,
                skillRank = rec.skillRank or 0,
                skillMax  = rec.skillMax or 0,
                isPrimary = not SECONDARY[profId],
            }
        end
    end
    table.sort(out, function(x, y)
        if x.isPrimary ~= y.isPrimary then return x.isPrimary end
        return x.profId < y.profId
    end)
    return out
end

function API.GetSpec(charKey)
    local db = gdb()
    local t = db and db.talents and db.talents[charKey]
    if type(t) ~= "table" then return nil end
    return { active = t.a, activeId = t.ai, other = t.o, otherId = t.oi }
end

function API.HasData(charKey)
    local db = gdb()
    if not db then return false end
    local s = db.skills and db.skills[charKey]
    if type(s) == "table" and next(s) ~= nil then return true end
    return type(db.talents and db.talents[charKey]) == "table"
end

-- Internal: Scanner calls this when a character's professions or spec change.
function API:_FireCharacterChanged(charKey)
    if charKey then self.callbacks:Fire("CharacterChanged", charKey) end
end
