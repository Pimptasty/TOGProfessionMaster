-- TOG Profession Master — Hash Manager (v0.2.0 protocol)
-- Author: Pimptasty
--
-- Implements the per-leaf hash cache for the v0.2.0 hash-then-fetch sync
-- protocol.  See docs/v0.2.0-protocol.md for the canonical design.
--
-- Leaf keys (v0.7.0 — recipemeta leaf REMOVED, metadata lives in addon.recipeDB)
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
-- v0.7.0: the synced per-broadcaster array lives in gdb.altClaims; gdb.accountChars
-- is now a local-only boolean-flag set for IsMyCharacter and isn't synced.
function HashManager:ComputeAccountCharsHash(DS, gdb, charKey)
    return DS:ComputeHash(gdb.altClaims and gdb.altClaims[charKey] or {})
end

--- GATHERING (recipe-less) skills for a character — the subset of gdb.skills whose
--- profession is NOT a crafting profession. Crafting skills sync on the crafters:
--- leaf already; this is what the skills:<charKey> leaf carries (Herbalism /
--- Skinning / Fishing / Archaeology). String keys + normalized {r,m} shape so the
--- hash is deterministic across clients (same discipline as ComputeCraftersHash).
--- UNCHANGED since v1.0.0 — the skills: leaf stays gathering-only so un-updated
--- peers keep interoperating with zero rollout churn; the v1.0.3 dropped-profession
--- work lives on the separate, additive-nothing professions:<charKey> leaf below.
local function gatheringSkills(gdb, charKey)
    local out = {}
    local s = gdb.skills and gdb.skills[charKey]
    if s then
        for profId, rec in pairs(s) do
            if type(rec) == "table"
               and not (addon.CRAFTING_PROFS and addon.CRAFTING_PROFS[profId]) then
                out[tostring(profId)] = { r = rec.skillRank or 0, m = rec.skillMax or 0 }
            end
        end
    end
    return out
end

--- FULL profession snapshot for a character — EVERY profession in gdb.skills[charKey]
--- (crafting AND gathering), normalized to {r,m}. This is what the v1.0.3
--- OWNER-AUTHORITATIVE professions:<charKey> leaf carries: the complete set the
--- owner currently holds, so a DROPPED profession (absent from the owner's fresh
--- snapshot) removes the stale row on every peer — additive merges could never
--- delete. This membership is the single source of truth the crafter-reconcile
--- prunes against (Scanner:ReconcileCraftersAgainstSkills). Separate leaf key so
--- the legacy skills: leaf and its hash are untouched — old clients never see this.
local function allProfessionSkills(gdb, charKey)
    local out = {}
    local s = gdb.skills and gdb.skills[charKey]
    if s then
        for profId, rec in pairs(s) do
            if type(rec) == "table" then
                out[tostring(profId)] = { r = rec.skillRank or 0, m = rec.skillMax or 0 }
            end
        end
    end
    return out
end

--- Hash for skills:<charKey> — that character's gathering-profession skill levels.
function HashManager:ComputeCharSkillsHash(DS, gdb, charKey)
    return DS:ComputeHash(gatheringSkills(gdb, charKey))
end

--- Payload map for skills:<charKey> (what the leaf ships). Mirrors the hashed shape.
function HashManager:GetGatheringSkills(gdb, charKey)
    return gatheringSkills(gdb, charKey)
end

--- Hash for professions:<charKey> — the character's full profession snapshot.
--- Owner-MINTED only; peers adopt it verbatim via StoreDeliveredProfessionsLeaf and
--- NEVER recompute it on receive (same owner-authoritative rule as cooldowns).
function HashManager:ComputeCharProfessionsHash(DS, gdb, charKey)
    return DS:ComputeHash(allProfessionSkills(gdb, charKey))
end

--- Payload map for professions:<charKey> (what the leaf ships). Mirrors the hashed shape.
function HashManager:GetProfessionSnapshot(gdb, charKey)
    return allProfessionSkills(gdb, charKey)
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

--- Per-(profession, player) sub-hash map for the optional player-level drill-down
--- under crafters:<profId>. ADDITIVE: the crafters:<profId> profession hash above is
--- unchanged (the compat linchpin — old and new clients must compute it identically),
--- this is a SEPARATE parallel derivation from the same gdb.recipes, bucketed by
--- crafter instead of summed. No new stored state:
---   * h  — content hash of that player's recipeId set in this profession, normalized
---           to {recipeId → true} exactly like ComputeCraftersHash so attribution /
---           relay tag changes never move it.
---   * ts — that player's last scan time for this profession, already stored at
---           gdb.lastScan[charKey][profId] and already propagated on the crafters leaf.
--- Used by BOTH sides: the responder ships it; the requester recomputes its own and
--- diffs h to find which players to pull (newest ts first).
function HashManager:GetProfessionPlayerSubhashes(DS, gdb, profId)
    local buckets = {}   -- charKey → { [recipeIdStr] = true }
    if gdb.recipes and gdb.recipes[profId] then
        for recipeId, rd in pairs(gdb.recipes[profId]) do
            if rd.crafters then
                for ck, v in pairs(rd.crafters) do
                    if v then
                        local b = buckets[ck]
                        if not b then b = {}; buckets[ck] = b end
                        b[tostring(recipeId)] = true
                    end
                end
            end
        end
    end
    local out = {}
    for ck, set in pairs(buckets) do
        out[ck] = { h = DS:ComputeHash(set), ts = lastScan(gdb, ck, profId) }
    end
    return out
end

-- v0.7.0: ComputeRecipeMetaHash removed — recipe metadata isn't synced anymore.
-- The shipped addon.recipeDB carries name/icon/reagents/links, identical on
-- every client that ships the same addon version, so there's no per-leaf hash
-- to negotiate.

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

function HashManager:ComputeGuildSkillsHash(DS, gdb)
    return rollupOver(ensureHashes(gdb), "skills:", DS)
end

function HashManager:ComputeGuildProfessionsHash(DS, gdb)
    return rollupOver(ensureHashes(gdb), "professions:", DS)
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

--- Adopt a cooldown leaf hash delivered by a peer VERBATIM (v0.10.11 owner-
--- authoritative token model). Unlike InvalidateCharCooldowns, this does NOT
--- recompute the hash from local data: the cooldown OWNER minted the token, and
--- it must survive relay unchanged. Per-client recomputation is exactly what
--- reintroduced drift — a receiver that reconstructs the expiry against its own
--- clock computes a different hash, so guild:cooldowns never converged and the
--- P2P negotiation (and its redraws) churned forever. Here the caller has already
--- stored the owner's absolute-expiry bucket verbatim; we record the owner's token
--- + updatedAt as the leaf hash and refresh the guild:cooldowns roll-up from the
--- stored leaf hashes (rollupOver reads entry.hash, so no recompute leaks in).
--- Only the owner (via InvalidateCharCooldowns on its own scan) ever computes a
--- cooldown hash from data; everyone else adopts through here.
--- `isAbs` records whether this token came from the new ABSOLUTE format or the
--- legacy relative one, so a drift-prone legacy copy can never override an
--- authoritative absolute one for the same owner (the receiver checks entry.abs).
function HashManager:StoreDeliveredCooldownLeaf(DS, gdb, ownerKey, token, updatedAt, isAbs)
    local hashes = ensureHashes(gdb)
    local wrote  = setEntry(hashes, "cooldown:" .. ownerKey, token, updatedAt or 0)
    -- Refresh the format flag even on a no-op (hash, updatedAt) write.
    local entry = hashes["cooldown:" .. ownerKey]
    if entry then entry.abs = isAbs and true or nil end
    if wrote then
        setEntry(hashes, "guild:cooldowns",
            self:ComputeGuildCooldownsHash(DS, gdb),
            rollupTime(hashes, "cooldown:"))
    end
    return wrote
end

--- After an accountchars scan for one broadcaster. Call ONLY on the owner's own
--- client, from its own alt-group scan — never on receive (recompute-on-receive is
--- exactly what made accountchars churn). Everyone else adopts via
--- StoreDeliveredAccountCharsLeaf.
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

--- Adopt an accountchars leaf hash delivered by a peer VERBATIM (owner-authoritative,
--- exactly like StoreDeliveredCooldownLeaf / StoreDeliveredProfessionsLeaf). The alt
--- group is minted only by its own account and adopted token-for-token by everyone
--- else — NEVER recomputed on receipt and NEVER union-merged, which is what made the
--- v0.7.0 accountchars model churn forever (each client hashed its own accumulated
--- view, so peers never converged and re-requested the leaf every cycle). The caller
--- has already replaced gdb.altClaims[owner] with the delivered array; here we just
--- record the owner's token + updatedAt and recompose the guild:accountchars roll-up
--- from stored leaf hashes (no data re-hash).
function HashManager:StoreDeliveredAccountCharsLeaf(DS, gdb, ownerKey, token, updatedAt)
    local hashes = ensureHashes(gdb)
    local wrote  = setEntry(hashes, "accountchars:" .. ownerKey, token, updatedAt or 0)
    if wrote then
        setEntry(hashes, "guild:accountchars",
            self:ComputeGuildAccountCharsHash(DS, gdb),
            rollupTime(hashes, "accountchars:"))
    end
    return wrote
end

--- After a gathering-skills scan or merge for one character (skills:<charKey>).
--- Unchanged from v1.0.0 — the skills leaf stays gathering-only and drift-free
--- (max-rank-wins), so recompute here is safe and old clients interoperate.
function HashManager:InvalidateCharSkills(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash   = self:ComputeCharSkillsHash(DS, gdb, charKey)
    local ts     = lastScan(gdb, charKey, "skills")
    local wrote  = setEntry(hashes, "skills:" .. charKey, hash, ts)
    if wrote then
        setEntry(hashes, "guild:skills",
            self:ComputeGuildSkillsHash(DS, gdb),
            rollupTime(hashes, "skills:"))
    end
end

--- Owner MINT of the professions:<charKey> leaf — call ONLY on the character's own
--- client after its own profession scan (never on receive). Computes the full
--- profession-snapshot hash from local data and stamps it with the owner's scan
--- time. Everyone else adopts the result verbatim via StoreDeliveredProfessionsLeaf.
function HashManager:InvalidateCharProfessions(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash   = self:ComputeCharProfessionsHash(DS, gdb, charKey)
    local ts     = lastScan(gdb, charKey, "professions")
    local wrote  = setEntry(hashes, "professions:" .. charKey, hash, ts)
    if wrote then
        setEntry(hashes, "guild:professions",
            self:ComputeGuildProfessionsHash(DS, gdb),
            rollupTime(hashes, "professions:"))
    end
end

--- Adopt a professions leaf hash delivered by a peer VERBATIM (v1.0.3 owner-
--- authoritative profession registry — the exact model as StoreDeliveredCooldownLeaf).
--- The character's OWN client mints the professions:<charKey> hash from its full
--- profession set; every relay stores that token verbatim and NEVER recomputes it,
--- so the hash stays owner-identical hop to hop and guild:professions converges
--- instead of churning. The caller has already replaced gdb.skills[owner] with the
--- delivered snapshot; here we just record the owner's token + updatedAt and
--- recompose the guild:professions roll-up from stored leaf hashes (no data re-hash).
function HashManager:StoreDeliveredProfessionsLeaf(DS, gdb, ownerKey, token, updatedAt)
    local hashes = ensureHashes(gdb)
    local wrote  = setEntry(hashes, "professions:" .. ownerKey, token, updatedAt or 0)
    if wrote then
        setEntry(hashes, "guild:professions",
            self:ComputeGuildProfessionsHash(DS, gdb),
            rollupTime(hashes, "professions:"))
    end
    return wrote
end

-- Drop a leaf hash we hold NO data for (an "orphan") and refresh its roll-up.
-- Called when a serve attempt finds no content: the hash was gossiping to us via
-- subhashes but the actual data never landed, so we kept advertising a leaf we
-- can't serve. That churns peers (they request it forever) AND — for cooldowns —
-- inflates our request stamp so the real owner's copy isn't "strictly newer" and
-- they stay silent, so the data can never reach us. Removing the orphan hash stops
-- the advertisement and lets a fresh (stamp = -1) request pull the owner's data.
-- Safe: BuildLeafPayload only returns nil when the backing data is genuinely
-- absent, so a leaf we truly hold is never dropped.
function HashManager:DropOrphanLeaf(DS, gdb, itemKey)
    local hashes = gdb.hashes
    if not hashes or not hashes[itemKey] then return false end
    hashes[itemKey] = nil
    if itemKey:sub(1, 9) == "cooldown:" then
        setEntry(hashes, "guild:cooldowns",
            self:ComputeGuildCooldownsHash(DS, gdb), rollupTime(hashes, "cooldown:"))
    elseif itemKey:sub(1, 12) == "professions:" then
        setEntry(hashes, "guild:professions",
            self:ComputeGuildProfessionsHash(DS, gdb), rollupTime(hashes, "professions:"))
    elseif itemKey:sub(1, 7) == "skills:" then
        setEntry(hashes, "guild:skills",
            self:ComputeGuildSkillsHash(DS, gdb), rollupTime(hashes, "skills:"))
    elseif itemKey:sub(1, 13) == "accountchars:" then
        setEntry(hashes, "guild:accountchars",
            self:ComputeGuildAccountCharsHash(DS, gdb), rollupTime(hashes, "accountchars:"))
    end
    -- crafters:<profId> has no roll-up (it rides the L0 map directly) — the bare
    -- removal above is enough.
    return true
end

--- After a profession scan or merge. v0.7.0: only the crafters:<profId> leaf
--- needs invalidation — recipemeta is dead.
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

    setEntry(hashes, "crafters:" .. key, self:ComputeCraftersHash(DS, gdb, profId), maxTs)
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

    -- ── Drop legacy v0.1.x → v0.6.x leaf keys ─────────────────────────────
    -- recipes:<profId> (v0.1.x) was split into recipemeta + crafters in v0.2.
    -- v0.7.0 then drops recipemeta entirely (metadata lives in addon.recipeDB,
    -- not on the wire). Strip both old key prefixes here so the hash store
    -- doesn't carry dead entries across the schema migration.
    local toRemove = {}
    for key in pairs(hashes) do
        if key:sub(1, 8) == "recipes:" or key:sub(1, 11) == "recipemeta:"
        or key == "guild:recipes" then
            toRemove[#toRemove + 1] = key
        end
    end
    for _, key in ipairs(toRemove) do
        hashes[key] = nil
    end

    -- ── Ensure all expected v0.7.0 leaves exist ──────────────────────────
    -- These calls no-op when content is unchanged (setEntry has the guard).

    if gdb.cooldowns then
        for charKey in pairs(gdb.cooldowns) do
            if not hashes["cooldown:" .. charKey] then
                self:InvalidateCharCooldowns(DS, gdb, charKey)
            end
        end
    end

    -- v0.7.0: iterate altClaims (synced per-broadcaster arrays). The local-only
    -- gdb.accountChars boolean-flag set isn't a sync source — it just gates
    -- "is this charKey one of mine" lookups.
    if gdb.altClaims then
        for charKey in pairs(gdb.altClaims) do
            if not hashes["accountchars:" .. charKey] then
                self:InvalidateAccountChars(DS, gdb, charKey)
            end
        end
    end

    if gdb.recipes then
        for profId in pairs(gdb.recipes) do
            local k = tostring(profId)
            if not hashes["crafters:" .. k] then
                self:InvalidateProfession(DS, gdb, profId)
            end
        end
    end

    -- Gathering-skill leaves: a character with any recipe-less profession skill.
    if gdb.skills then
        for charKey in pairs(gdb.skills) do
            if not hashes["skills:" .. charKey] and next(gatheringSkills(gdb, charKey)) then
                self:InvalidateCharSkills(DS, gdb, charKey)
            end
        end
    end

    -- One-time self-heal (v1.0.3): an earlier build fabricated updatedAt-0
    -- professions leaves and set bogus lastScan.professions == 0 (0 is truthy in
    -- Lua). Purge both so we stop advertising orphan hashes we can't serve and stop
    -- ignoring characters' real skills leaves / mis-filtering their cooldowns.
    for key, entry in pairs(hashes) do
        if key:sub(1, 12) == "professions:" and type(entry) == "table"
           and (not entry.updatedAt or entry.updatedAt <= 0) then
            hashes[key] = nil
        end
    end
    if gdb.lastScan then
        for _ck, scopes in pairs(gdb.lastScan) do
            if type(scopes) == "table" and scopes.professions ~= nil
               and scopes.professions <= 0 then
                scopes.professions = nil
            end
        end
    end

    -- Profession-snapshot leaves (v1.0.3): restore a MISSING hash ONLY for a
    -- character we hold a real AUTHORITATIVE snapshot timestamp for
    -- (lastScan[char].professions > 0 — our own scan, or an owner's delivered
    -- leaf). We must NOT fabricate a professions leaf for a character we merely
    -- relayed skills for: that would mint a bogus updatedAt-0 leaf which, once
    -- relayed and adopted elsewhere, sets a truthy lastScan.professions and makes
    -- peers ignore that character's real skills leaf (orphan hashes) and mis-filter
    -- their cooldowns. The owner's own scan is the sole authority for their snapshot.
    if gdb.skills then
        for charKey in pairs(gdb.skills) do
            local snapT = gdb.lastScan and gdb.lastScan[charKey]
                          and gdb.lastScan[charKey].professions
            if not hashes["professions:" .. charKey]
               and snapT and snapT > 0
               and next(allProfessionSkills(gdb, charKey)) then
                self:InvalidateCharProfessions(DS, gdb, charKey)
            end
        end
    end

    -- Orphan-hash sweep (v1.0.3): drop any per-character/profession leaf hash we
    -- hold NO backing data for. These gossip in via subhashes and, left advertised,
    -- churn peers who request them AND — for cooldowns — inflate our request stamps
    -- so the real owner's copy isn't "strictly newer" and never serves us. Bare
    -- removal here (the roll-ups below recompute from what remains). Same self-heal
    -- as the serve path, applied up-front so we don't wait for a request per orphan.
    local orphans = {}
    for key in pairs(hashes) do
        if (key:sub(1, 9)  == "cooldown:"    or key:sub(1, 7)  == "skills:"
         or key:sub(1, 12) == "professions:" or key:sub(1, 13) == "accountchars:")
           and not self:HasContent(gdb, key) then
            orphans[#orphans + 1] = key
        end
    end
    for _, key in ipairs(orphans) do hashes[key] = nil end

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
    setEntry(hashes, "guild:skills",
        self:ComputeGuildSkillsHash(DS, gdb),
        rollupTime(hashes, "skills:"))
    setEntry(hashes, "guild:professions",
        self:ComputeGuildProfessionsHash(DS, gdb),
        rollupTime(hashes, "professions:"))
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

function HashManager:GetSkillsLevelMap(gdb)
    return copyEntries(ensureHashes(gdb), "skills:")
end

function HashManager:GetProfessionsLevelMap(gdb)
    return copyEntries(ensureHashes(gdb), "professions:")
end

function HashManager:GetCraftersLevelMap(gdb)
    return copyEntries(ensureHashes(gdb), "crafters:")
end

--- Return the L0 broadcast map: per-profession crafters leaf plus the two
--- roll-up entries. v0.7.0: recipemeta leaf removed. Per-character leaves
--- are NOT included at L0 — drilled down on roll-up mismatch via subhashes.
function HashManager:GetL0BroadcastMap(gdb)
    local hashes = ensureHashes(gdb)
    local map    = {}
    -- Per-profession (crafters only)
    for key, entry in pairs(hashes) do
        if key:sub(1, 9) == "crafters:" then
            map[key] = { hash = entry.hash, updatedAt = entry.updatedAt }
        end
    end
    -- Roll-ups
    for _, key in ipairs({ "guild:cooldowns", "guild:accountchars", "guild:skills", "guild:professions" }) do
        local e = hashes[key]
        if e then map[key] = { hash = e.hash, updatedAt = e.updatedAt } end
    end
    return map
end

--- Pad the broadcast L0 map with placeholder hash entries for every
--- available crafting profession the local player has no data for. Without
--- these placeholders the DeltaSync OFFER protocol never triggers sync for
--- keys absent from the broadcaster's hash list — peers only offer data for
--- keys that appear in your hashes. So a player who has Enchanting locally
--- will sync Enchanting data from peers (mismatched hashes → offer → fetch)
--- but will never receive Engineering / BS / LW recipes from guildmates
--- because they have no `recipemeta:202` / `crafters:202` entry to put in
--- their broadcast.
---
--- Placeholders are added only to the BROADCAST map, not to gdb.hashes —
--- writing them to gdb.hashes would conflate "I want this" with "I have
--- this". The placeholder hash is the stable hash of an empty table, so it
--- always differs from a real-content hash; first peer with real data sees
--- the mismatch and offers; we accept; we merge; on the next broadcast the
--- real computed hash naturally replaces the placeholder.
function HashManager:PadMissingProfessionPlaceholders(DS, map)
    if not DS or not addon.CRAFTING_PROFS then return end
    local placeholderHash = DS:ComputeHash({})
    for profId in pairs(addon.CRAFTING_PROFS) do
        local available = (not addon.IsProfessionAvailable)
                       or addon.IsProfessionAvailable(profId)
        if available then
            local crKey = "crafters:" .. tostring(profId)
            if not map[crKey] then
                map[crKey] = { hash = placeholderHash, updatedAt = 0 }
            end
        end
    end
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
        return gdb.altClaims and next(gdb.altClaims) ~= nil
    end
    if itemKey == "guild:skills" then
        -- Servable when any character has a gathering skill recorded.
        if gdb.skills then
            for ck in pairs(gdb.skills) do
                if next(gatheringSkills(gdb, ck)) then return true end
            end
        end
        return false
    end
    if itemKey == "guild:professions" then
        -- Servable when any character has any profession recorded.
        if gdb.skills then
            for ck in pairs(gdb.skills) do
                if next(allProfessionSkills(gdb, ck)) then return true end
            end
        end
        return false
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
        return gdb.altClaims
           and type(gdb.altClaims[owner]) == "table"
           and #gdb.altClaims[owner] > 0
    end

    if itemKey:sub(1, 12) == "professions:" then
        local owner = itemKey:sub(13)
        return next(allProfessionSkills(gdb, owner)) ~= nil
    end

    if itemKey:sub(1, 7) == "skills:" then
        local owner = itemKey:sub(8)
        return next(gatheringSkills(gdb, owner)) ~= nil
    end

    -- v0.7.0: recipemeta: leaf removed. Any inbound query for it returns
    -- false so peers stop asking.
    if itemKey:sub(1, 11) == "recipemeta:" then return false end

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
