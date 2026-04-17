-- TOG Profession Master — Hierarchical Hash Manager
-- Author: Pimptasty
--
-- Implements a Merkle-tree style cache of content hashes for DeltaSync P2P.
-- All hashes are stored in gdb.hashes (guild-scoped SavedVariables).
--
-- Two levels of hash keys:
--   guild:cooldowns          — roll-up over all per-member cooldown hashes
--   guild:recipes            — roll-up over all per-profession recipe hashes
--   cooldown:<Name-Realm>    — per-member cooldown leaf
--   recipes:<profId>         — per-profession recipe leaf
--
-- Invalidation is targeted: changing one member's cooldowns only recomputes
-- that member's leaf hash plus the guild:cooldowns roll-up.

local _, addon = ...

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local HashManager = {}
addon.HashManager = HashManager

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Ensure gdb.hashes table exists (lazy-init for old saved-variable buckets).
local function ensureHashes(gdb)
    if not gdb.hashes then gdb.hashes = {} end
    return gdb.hashes
end

--- Write (or overwrite) a hash entry.
local function setEntry(hashes, key, hash, now)
    hashes[key] = { hash = hash, updatedAt = now }
end

-- ---------------------------------------------------------------------------
-- Leaf hash computations
-- ---------------------------------------------------------------------------

--- Compute the cooldown hash for a single character.
-- Hashes the full cooldown table (spellId → expiresAt) directly.
-- @param DS      DeltaSync-1.0 library reference
-- @param gdb     guild DB bucket
-- @param charKey "Name-Realm" string
-- @return        numeric hash
function HashManager:ComputeCharCooldownHash(DS, gdb, charKey)
    return DS:ComputeHash(gdb.cooldowns and gdb.cooldowns[charKey] or {})
end

--- Compute the recipe hash for a single profession.
-- Combines a count-per-recipe map (crafter counts) with per-member skill ranks
-- for that profession so that any change to who-knows-what or rank increments
-- produce a different hash.
-- @param DS     DeltaSync-1.0 library reference
-- @param gdb    guild DB bucket
-- @param profId numeric profession skill-line ID
-- @return       numeric hash
function HashManager:ComputeProfessionHash(DS, gdb, profId)
    -- Count crafters per recipe — avoids serialising full crafter-key strings.
    local recipeCounts = {}
    if gdb.recipes and gdb.recipes[profId] then
        for recipeId, rd in pairs(gdb.recipes[profId]) do
            local n = 0
            for _ in pairs(rd.crafters or {}) do n = n + 1 end
            recipeCounts[tostring(recipeId)] = n
        end
    end

    -- Collect skill ranks for this profession across all members.
    local skillRanks = {}
    if gdb.skills then
        for charKey, charSkills in pairs(gdb.skills) do
            local skill = charSkills[profId]
            if skill then
                skillRanks[charKey] = skill.skillRank or 0
            end
        end
    end

    return DS:ComputeStructuredHash({
        recipeCounts = DS:ComputeHash(recipeCounts),
        skillRanks   = DS:ComputeHash(skillRanks),
    })
end

-- ---------------------------------------------------------------------------
-- Roll-up computations (derived from cached leaf entries)
-- ---------------------------------------------------------------------------

--- Recompute guild:cooldowns as a structured hash over all cached cooldown leaves.
-- Reads leaf hashes already stored in gdb.hashes; call after updating leaves.
-- @param DS  DeltaSync-1.0 library reference
-- @param gdb guild DB bucket
-- @return    numeric hash
function HashManager:ComputeGuildCooldownsHash(DS, gdb)
    local hashes  = ensureHashes(gdb)
    local leafNums = {}
    for key, entry in pairs(hashes) do
        if key:sub(1, 9) == "cooldown:" then
            leafNums[key] = entry.hash
        end
    end
    return DS:ComputeStructuredHash(leafNums)
end

--- Recompute guild:recipes as a structured hash over all cached recipe leaves.
-- @param DS  DeltaSync-1.0 library reference
-- @param gdb guild DB bucket
-- @return    numeric hash
function HashManager:ComputeGuildRecipesHash(DS, gdb)
    local hashes   = ensureHashes(gdb)
    local leafNums = {}
    for key, entry in pairs(hashes) do
        if key:sub(1, 8) == "recipes:" then
            leafNums[key] = entry.hash
        end
    end
    return DS:ComputeStructuredHash(leafNums)
end

-- ---------------------------------------------------------------------------
-- Targeted invalidation
-- ---------------------------------------------------------------------------

--- Invalidate the cooldown hash for one character and recompute the roll-up.
-- Call after ScanCooldowns() updates gdb.cooldowns[charKey].
-- @param DS      DeltaSync-1.0 library reference
-- @param gdb     guild DB bucket
-- @param charKey "Name-Realm" string
function HashManager:InvalidateCharCooldowns(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local now    = GetServerTime()
    setEntry(hashes, "cooldown:" .. charKey, self:ComputeCharCooldownHash(DS, gdb, charKey), now)
    setEntry(hashes, "guild:cooldowns",      self:ComputeGuildCooldownsHash(DS, gdb),         now)
end

--- Invalidate the recipe hash for one profession and recompute the roll-up.
-- Call after MergeRecipesIntoGdb() updates gdb.recipes[profId].
-- @param DS     DeltaSync-1.0 library reference
-- @param gdb    guild DB bucket
-- @param profId numeric profession skill-line ID
function HashManager:InvalidateProfession(DS, gdb, profId)
    local hashes = ensureHashes(gdb)
    local now    = GetServerTime()
    setEntry(hashes, "recipes:" .. tostring(profId), self:ComputeProfessionHash(DS, gdb, profId), now)
    setEntry(hashes, "guild:recipes",                self:ComputeGuildRecipesHash(DS, gdb),        now)
end

--- Full rebuild of all hash levels from scratch.
-- Use on first login, after a bulk import, or after OnGuildDataReceived.
-- @param DS  DeltaSync-1.0 library reference
-- @param gdb guild DB bucket
function HashManager:RebuildAll(DS, gdb)
    local hashes = ensureHashes(gdb)
    local now    = GetServerTime()

    -- Per-member cooldown leaves.
    for charKey in pairs(gdb.cooldowns or {}) do
        setEntry(hashes, "cooldown:" .. charKey, self:ComputeCharCooldownHash(DS, gdb, charKey), now)
    end

    -- Per-profession recipe leaves.
    for profId in pairs(gdb.recipes or {}) do
        setEntry(hashes, "recipes:" .. tostring(profId), self:ComputeProfessionHash(DS, gdb, profId), now)
    end

    -- Top-level roll-ups (uses the leaves we just wrote).
    setEntry(hashes, "guild:cooldowns", self:ComputeGuildCooldownsHash(DS, gdb), now)
    setEntry(hashes, "guild:recipes",   self:ComputeGuildRecipesHash(DS, gdb),   now)
end

-- ---------------------------------------------------------------------------
-- Map accessors (consumed by Scanner:InitP2P callbacks)
-- ---------------------------------------------------------------------------

--- Return the two guild-level hash entries for the initial broadcast.
-- @param gdb guild DB bucket
-- @return    { ["guild:cooldowns"] = {hash, updatedAt}, ["guild:recipes"] = {hash, updatedAt} }
function HashManager:GetGuildLevelMap(gdb)
    local hashes = ensureHashes(gdb)
    local map    = {}
    for _, key in ipairs({ "guild:cooldowns", "guild:recipes" }) do
        local e = hashes[key]
        if e then map[key] = { hash = e.hash, updatedAt = e.updatedAt } end
    end
    return map
end

--- Return all per-member cooldown hash entries.
-- @param gdb guild DB bucket
-- @return    { ["cooldown:Name-Realm"] = {hash, updatedAt}, ... }
function HashManager:GetCooldownLevelMap(gdb)
    local hashes = ensureHashes(gdb)
    local map    = {}
    for key, entry in pairs(hashes) do
        if key:sub(1, 9) == "cooldown:" then
            map[key] = { hash = entry.hash, updatedAt = entry.updatedAt }
        end
    end
    return map
end

--- Return all per-profession recipe hash entries.
-- @param gdb guild DB bucket
-- @return    { ["recipes:171"] = {hash, updatedAt}, ... }
function HashManager:GetProfessionLevelMap(gdb)
    local hashes = ensureHashes(gdb)
    local map    = {}
    for key, entry in pairs(hashes) do
        if key:sub(1, 8) == "recipes:" then
            map[key] = { hash = entry.hash, updatedAt = entry.updatedAt }
        end
    end
    return map
end

-- ---------------------------------------------------------------------------
-- Content ownership check
-- ---------------------------------------------------------------------------

--- Returns true if this client can authoritatively serve content for itemKey.
--
-- guild:*           → false  (synthetic roll-ups; no raw data to serve)
-- cooldown:Name-Realm → true only when Name-Realm is the local player
-- recipes:N           → true when the local player has any recipes for profession N
--
-- @param gdb     guild DB bucket
-- @param itemKey DeltaSync item key string
-- @return        boolean
function HashManager:HasContent(gdb, itemKey)
    local DS = addon.Scanner and addon.Scanner.DS
    if not DS then return false end

    -- Roll-up keys are never directly servable.
    if itemKey:sub(1, 6) == "guild:" then return false end

    -- Per-member cooldown key.
    if itemKey:sub(1, 9) == "cooldown:" then
        return itemKey:sub(10) == DS:GetNormalizedPlayer()
    end

    -- Per-profession recipe key.
    if itemKey:sub(1, 8) == "recipes:" then
        local profId  = tonumber(itemKey:sub(9))
        if not profId then return false end
        local charKey = DS:GetNormalizedPlayer()
        if gdb.recipes and gdb.recipes[profId] then
            for _, rd in pairs(gdb.recipes[profId]) do
                if rd.crafters and rd.crafters[charKey] then return true end
            end
        end
        return false
    end

    return false
end
