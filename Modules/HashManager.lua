-- TOG Profession Master — Hash Manager (v0.2.0 protocol)
-- Author: Pimptasty
--
-- Implements the per-leaf hash cache for the v0.2.0 hash-then-fetch sync
-- protocol.  See docs/v0.2.0-protocol.md for the canonical design.
--
-- Leaf keys
--   recipemeta:<profId>     — immutable recipe metadata for one profession
--                             (name, icon, isSpell, spellId, itemLink, recipeLink, reagents)
--   crafters:<profId>       — crafter membership { recipeId → {charKey → true} }
--   cooldown:<charKey>      — cooldown bucket { spellId → expiresAt } for one character
--   accountchars:<charKey>  — alt group { charKey, ... } owned by one broadcaster
--   guild:cooldowns         — structured roll-up over cooldown:<charKey> leaves
--   guild:accountchars      — structured roll-up over accountchars:<charKey> leaves
--
-- Hash + timestamp invariant
--   Each leaf entry is { hash, updatedAt }.  Both fields are pure functions
--   of the data state.  setEntry is a no-op when the new (hash, updatedAt)
--   matches the existing one.  updatedAt is content-derived (sourced from
--   gdb.lastScan), never GetServerTime() at a non-content-changing site.
--
-- No RebuildAll
--   The v0.1.x RebuildAll re-stamped every leaf's updatedAt on every receive,
--   even no-op merges, causing the "stale relayer beats fresh owner" routing
--   bug.  Replaced with targeted invalidation: each scan / merge calls only
--   the Invalidate* helpers for what changed.

local _, addon = ...

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local HashManager = {}
addon.HashManager = HashManager

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function ensureHashes(gdb)
    if not gdb.hashes then gdb.hashes = {} end
    return gdb.hashes
end

--- Write a hash entry only if the new (hash, updatedAt) tuple differs from
--- what's already stored.  Idempotent for no-op recomputations.
--- Returns true if the entry was written, false if it was a no-op.
local function setEntry(hashes, key, hash, updatedAt)
    local existing = hashes[key]
    if existing
       and existing.hash == hash
       and existing.updatedAt == updatedAt then
        return false
    end
    hashes[key] = { hash = hash, updatedAt = updatedAt }
    return true
end

--- Look up a content-derived timestamp from gdb.lastScan, with 0 fallback.
local function lastScan(gdb, charKey, scope)
    local cs = gdb.lastScan and gdb.lastScan[charKey]
    return (cs and cs[scope]) or 0
end

-- ---------------------------------------------------------------------------
-- Leaf hash computations
-- ---------------------------------------------------------------------------

--- Hash for cooldown:<charKey> — full cooldown bucket for one character.
function HashManager:ComputeCharCooldownHash(DS, gdb, charKey)
    return DS:ComputeHash(gdb.cooldowns and gdb.cooldowns[charKey] or {})
end

--- Hash for accountchars:<charKey> — alt group claimed by one broadcaster.
function HashManager:ComputeAccountCharsHash(DS, gdb, charKey)
    return DS:ComputeHash(gdb.accountChars and gdb.accountChars[charKey] or {})
end

--- Hash for crafters:<profId> — crafter membership map for one profession.
-- Independent of recipe metadata so the metadata leaf can stay stable while
-- crafter membership changes (the common case).
function HashManager:ComputeCraftersHash(DS, gdb, profId)
    local map = {}
    if gdb.recipes and gdb.recipes[profId] then
        for recipeId, rd in pairs(gdb.recipes[profId]) do
            local crafters = {}
            if rd.crafters then
                for ck, v in pairs(rd.crafters) do
                    if v then crafters[ck] = true end
                end
            end
            -- Only include recipes that have at least one crafter — empty
            -- entries can drift between peers and would falsely change the hash.
            if next(crafters) then
                map[tostring(recipeId)] = crafters
            end
        end
    end
    return DS:ComputeHash(map)
end

--- Hash for recipemeta:<profId> — immutable recipe metadata for one profession.
-- Excludes crafters intentionally; crafters live in a separate leaf.
function HashManager:ComputeRecipeMetaHash(DS, gdb, profId)
    local map = {}
    if gdb.recipes and gdb.recipes[profId] then
        for recipeId, rd in pairs(gdb.recipes[profId]) do
            -- Only the static fields.  spellId may be nil for non-local scans
            -- so we use false as the placeholder so the hash is stable.
            map[tostring(recipeId)] = {
                name       = rd.name       or "",
                icon       = rd.icon       or 0,
                isSpell    = rd.isSpell    and true or false,
                spellId    = rd.spellId    or 0,
                itemLink   = rd.itemLink   or "",
                recipeLink = rd.recipeLink or "",
                reagents   = rd.reagents,
            }
        end
    end
    return DS:ComputeHash(map)
end

-- ---------------------------------------------------------------------------
-- Roll-up computations (derived from cached leaf entries)
-- ---------------------------------------------------------------------------

local function rollupOver(hashes, prefix, DS)
    local leafNums = {}
    local prefLen  = #prefix
    for key, entry in pairs(hashes) do
        if key:sub(1, prefLen) == prefix then
            leafNums[key] = entry.hash
        end
    end
    return DS:ComputeStructuredHash(leafNums)
end

--- Roll-up updatedAt: max across child leaves with this prefix.
local function rollupTime(hashes, prefix)
    local maxT     = 0
    local prefLen  = #prefix
    for key, entry in pairs(hashes) do
        if key:sub(1, prefLen) == prefix then
            if (entry.updatedAt or 0) > maxT then maxT = entry.updatedAt end
        end
    end
    return maxT
end

function HashManager:ComputeGuildCooldownsHash(DS, gdb)
    return rollupOver(ensureHashes(gdb), "cooldown:", DS)
end

function HashManager:ComputeGuildAccountCharsHash(DS, gdb)
    return rollupOver(ensureHashes(gdb), "accountchars:", DS)
end

-- ---------------------------------------------------------------------------
-- Targeted invalidation
-- Each helper computes the new (hash, updatedAt) tuple from current content
-- and gdb.lastScan, then calls setEntry which is a no-op if unchanged.
-- ---------------------------------------------------------------------------

--- After a cooldown scan or merge for one character.
function HashManager:InvalidateCharCooldowns(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash   = self:ComputeCharCooldownHash(DS, gdb, charKey)
    local ts     = lastScan(gdb, charKey, "cooldowns")
    local wrote  = setEntry(hashes, "cooldown:" .. charKey, hash, ts)
    -- Roll-up only needs to recompute when a child changed.
    if wrote then
        setEntry(hashes, "guild:cooldowns",
            self:ComputeGuildCooldownsHash(DS, gdb),
            rollupTime(hashes, "cooldown:"))
    end
end

--- After an accountchars scan or merge for one broadcaster.
function HashManager:InvalidateAccountChars(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash   = self:ComputeAccountCharsHash(DS, gdb, charKey)
    local ts     = lastScan(gdb, charKey, "accountchars")
    local wrote  = setEntry(hashes, "accountchars:" .. charKey, hash, ts)
    if wrote then
        setEntry(hashes, "guild:accountchars",
            self:ComputeGuildAccountCharsHash(DS, gdb),
            rollupTime(hashes, "accountchars:"))
    end
end

--- After a profession scan or merge.  Invalidates BOTH recipemeta:<profId>
--- and crafters:<profId> since either may have changed.
function HashManager:InvalidateProfession(DS, gdb, profId)
    local hashes = ensureHashes(gdb)
    local key    = tostring(profId)

    -- Content-derived timestamp = freshest contributing scan.
    local maxTs = 0
    if gdb.recipes and gdb.recipes[profId] then
        for _, rd in pairs(gdb.recipes[profId]) do
            for ck in pairs(rd.crafters or {}) do
                local ts = lastScan(gdb, ck, profId)
                if ts > maxTs then maxTs = ts end
            end
        end
    end

    setEntry(hashes, "recipemeta:" .. key, self:ComputeRecipeMetaHash(DS, gdb, profId), maxTs)
    setEntry(hashes, "crafters:"   .. key, self:ComputeCraftersHash(DS, gdb, profId),   maxTs)
end

-- ---------------------------------------------------------------------------
-- First-load rebuild + v0.1.x → v0.2.0 hash migration
--
-- Computes any v0.2.0 leaves missing from gdb.hashes and removes legacy
-- v0.1.x leaf keys (recipes:<profId>, guild:recipes).  Idempotent — safe to
-- call multiple times; only writes when content actually changes.  NEVER
-- call this on guild data receive: that path uses targeted invalidation.
-- ---------------------------------------------------------------------------

function HashManager:RebuildOnFirstLoad(DS, gdb)
    local hashes = ensureHashes(gdb)

    -- ── Drop legacy v0.1.x leaf keys ──────────────────────────────────────
    -- recipes:<profId> was split into recipemeta:<profId> + crafters:<profId>.
    -- guild:recipes was replaced by guild:accountchars (different roll-up).
    local toRemove = {}
    for key in pairs(hashes) do
        if key:sub(1, 8) == "recipes:" or key == "guild:recipes" then
            toRemove[#toRemove + 1] = key
        end
    end
    for _, key in ipairs(toRemove) do
        hashes[key] = nil
    end

    -- ── Ensure all expected v0.2.0 leaves exist ──────────────────────────
    -- These calls no-op when content is unchanged (setEntry has the guard),
    -- so it's safe to invoke unconditionally.

    if gdb.cooldowns then
        for charKey in pairs(gdb.cooldowns) do
            if not hashes["cooldown:" .. charKey] then
                self:InvalidateCharCooldowns(DS, gdb, charKey)
            end
        end
    end

    if gdb.accountChars then
        for charKey in pairs(gdb.accountChars) do
            if not hashes["accountchars:" .. charKey] then
                self:InvalidateAccountChars(DS, gdb, charKey)
            end
        end
    end

    if gdb.recipes then
        for profId in pairs(gdb.recipes) do
            local k = tostring(profId)
            if not hashes["recipemeta:" .. k] or not hashes["crafters:" .. k] then
                self:InvalidateProfession(DS, gdb, profId)
            end
        end
    end

    -- Roll-ups: recompute if missing or stale.  InvalidateChar* / Invalidate*
    -- helpers only refresh the roll-up when their leaf changed, so a fresh
    -- recompute here covers the case where leaves existed but the roll-up
    -- was lost (e.g., v0.1.x guild:cooldowns survived but is now stale).
    setEntry(hashes, "guild:cooldowns",
        self:ComputeGuildCooldownsHash(DS, gdb),
        rollupTime(hashes, "cooldown:"))
    setEntry(hashes, "guild:accountchars",
        self:ComputeGuildAccountCharsHash(DS, gdb),
        rollupTime(hashes, "accountchars:"))
end

-- ---------------------------------------------------------------------------
-- Map accessors (consumed by Scanner P2P callbacks)
-- ---------------------------------------------------------------------------

local function copyEntries(hashes, prefix)
    local map = {}
    local prefLen = #prefix
    for key, entry in pairs(hashes) do
        if key:sub(1, prefLen) == prefix then
            map[key] = { hash = entry.hash, updatedAt = entry.updatedAt }
        end
    end
    return map
end

function HashManager:GetCooldownLevelMap(gdb)
    return copyEntries(ensureHashes(gdb), "cooldown:")
end

function HashManager:GetAccountCharsLevelMap(gdb)
    return copyEntries(ensureHashes(gdb), "accountchars:")
end

function HashManager:GetRecipeMetaLevelMap(gdb)
    return copyEntries(ensureHashes(gdb), "recipemeta:")
end

function HashManager:GetCraftersLevelMap(gdb)
    return copyEntries(ensureHashes(gdb), "crafters:")
end

--- Return the L0 broadcast map: per-profession (recipemeta + crafters) plus
--- the two roll-up entries.  Per-character leaves are NOT included at L0 —
--- they're drilled down on roll-up mismatch via the subhashes request.
function HashManager:GetL0BroadcastMap(gdb)
    local hashes = ensureHashes(gdb)
    local map    = {}
    -- Per-profession
    for key, entry in pairs(hashes) do
        if key:sub(1, 11) == "recipemeta:" or key:sub(1, 9) == "crafters:" then
            map[key] = { hash = entry.hash, updatedAt = entry.updatedAt }
        end
    end
    -- Roll-ups
    for _, key in ipairs({ "guild:cooldowns", "guild:accountchars" }) do
        local e = hashes[key]
        if e then map[key] = { hash = e.hash, updatedAt = e.updatedAt } end
    end
    return map
end

-- ---------------------------------------------------------------------------
-- Content ownership check
-- v0.2.0: anyone with cached data for a leaf can serve it (relay).
-- ---------------------------------------------------------------------------

function HashManager:HasContent(gdb, itemKey)
    -- Roll-ups are servable when we have underlying per-character data.
    -- We don't serve the roll-up data itself — onSyncAccepted dispatches to
    -- BroadcastSubhashesToGuild which sends the per-character sub-hash list,
    -- letting the receiver identify which specific leaves they need.  Returning
    -- false here would break the drill-down chain entirely: peers wouldn't
    -- offer for guild:* hashes, so the broadcaster's onSyncAccepted never
    -- fires, so the subhashes broadcast never happens.
    if itemKey == "guild:cooldowns" then
        return gdb.cooldowns and next(gdb.cooldowns) ~= nil
    end
    if itemKey == "guild:accountchars" then
        return gdb.accountChars and next(gdb.accountChars) ~= nil
    end
    if itemKey:sub(1, 6) == "guild:" then return false end

    if itemKey:sub(1, 9) == "cooldown:" then
        local owner = itemKey:sub(10)
        return gdb.cooldowns
           and gdb.cooldowns[owner]
           and next(gdb.cooldowns[owner]) ~= nil
    end

    if itemKey:sub(1, 13) == "accountchars:" then
        local owner = itemKey:sub(14)
        return gdb.accountChars
           and gdb.accountChars[owner]
           and #gdb.accountChars[owner] > 0
    end

    if itemKey:sub(1, 11) == "recipemeta:" then
        local profId = tonumber(itemKey:sub(12))
        return profId
           and gdb.recipes
           and gdb.recipes[profId]
           and next(gdb.recipes[profId]) ~= nil
    end

    if itemKey:sub(1, 9) == "crafters:" then
        local profId = tonumber(itemKey:sub(10))
        if not profId or not gdb.recipes or not gdb.recipes[profId] then return false end
        for _, rd in pairs(gdb.recipes[profId]) do
            if rd.crafters and next(rd.crafters) then return true end
        end
        return false
    end

    return false
end
