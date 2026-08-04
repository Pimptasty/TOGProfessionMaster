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

--- Write a hash entry only if the new (hash, hashV2, updatedAt) tuple differs
--- from what's already stored.  Idempotent for no-op recomputations.
--- Returns true if the entry was written, false if it was a no-op.
local function setEntry(hashes, key, hash, updatedAt, hashV2)
    local existing = hashes[key]
    if existing
       and existing.hash == hash
       and existing.hashV2 == hashV2
       and existing.updatedAt == updatedAt then
        return false
    end
    hashes[key] = { hash = hash, hashV2 = hashV2, updatedAt = updatedAt }
    return true
end

--- Mint BOTH hash revisions for a value.
---
--- Revision 1 renders a number and its string form identically, so `{v = 1}`
--- and `{v = "1"}` hash the same and a real difference is invisible. Revision 2
--- (DeltaSync MINOR 16+) types each scalar. Both ship side by side: every
--- comparison — DeltaSync's own OFFER protocol and our subhash diff alike —
--- uses the highest revision BOTH ends advertise, so a peer on an older build
--- (which sends only `hash`) still agrees with us, and two updated peers get the
--- collision-free comparison. That is what lets revision 1 eventually retire:
--- drop it from this one function and delete the fallbacks.
---
--- Falls back to revision 1 alone on a DeltaSync without MakeHashEntry, in which
--- case hashV2 is nil everywhere and every comparison stays on revision 1.
local function mint(DS, data)
    if DS.MakeHashEntry then
        local e = DS:MakeHashEntry(data, nil)
        return e.hash, e.hashV2
    end
    return DS:ComputeHash(data), nil
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

--- Payload map for skills:<charKey> (what the leaf ships). Mirrors the hashed shape.
---
--- There is deliberately no ComputeCharSkillsHash entry point beside this. The hash
--- is minted only in InvalidateCharSkills, through mint(), which stamps BOTH hash
--- revisions — a leaf minted through a revision-1-only helper would carry no hashV2
--- and silently drop its whole roll-up back to revision 1 (see rollupOverV2).
function HashManager:GetGatheringSkills(gdb, charKey)
    return gatheringSkills(gdb, charKey)
end

--- Payload map for professions:<charKey> (what the leaf ships). Mirrors the hashed shape.
--- Owner-MINTED only (InvalidateCharProfessions); peers adopt the hash verbatim via
--- StoreDeliveredProfessionsLeaf and NEVER recompute it on receive — the same
--- owner-authoritative rule as cooldowns, and the same no-V1-only-path rule as above.
function HashManager:GetProfessionSnapshot(gdb, charKey)
    return allProfessionSkills(gdb, charKey)
end

--- Hash for crafters:<profId> — crafter membership map for one profession.
-- Independent of recipe metadata so the metadata leaf can stay stable while
-- crafter membership changes (the common case).
--- The hashed SHAPE of a profession's crafter membership. Split out from the
--- hash itself so both revisions mint from one construction.
--- NOTE the deliberate `crafters[ck] = true`: a stored crafter value is a guild
--- TAG STRING on a current client and a bare `true` on an old one, so
--- normalising it here is what keeps the two computing the same hash. It also
--- means this leaf can never hit the revision-1 number/string collision.
local function craftersMap(gdb, profId)
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
    return map
end

function HashManager:ComputeCraftersHash(DS, gdb, profId)
    return DS:ComputeHash(craftersMap(gdb, profId))
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

--- Revision-2 roll-up, composed from the children's V2 tokens.
---
--- Returns nil unless EVERY contributing child carries one. That is the whole
--- correctness rule here: a roll-up composed from a mix of V2 tokens and V1
--- fallbacks is not comparable to another client's mix, so two clients holding
--- identical data would compute different V2 roll-ups and re-sync forever. When
--- any child is still V1-only — we adopted its token verbatim from a peer on an
--- older build — this roll-up simply advertises no V2 and both ends fall back to
--- revision 1, which they agree on. It upgrades itself the moment the last
--- V1-only child is replaced by a newer owner-minted one.
local function rollupOverV2(hashes, prefix, DS)
    if not DS.ComputeHashV2 then return nil end
    local leafNums = {}
    local prefLen  = #prefix
    local any = false
    for key, entry in pairs(hashes) do
        if key:sub(1, prefLen) == prefix then
            if entry.hashV2 == nil then return nil end
            leafNums[key] = entry.hashV2
            any = true
        end
    end
    if not any then return nil end
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

--- Recompose a roll-up from the STORED child tokens — never by re-hashing data.
--- That is the rule the whole owner-authoritative model rests on: an adopted
--- token must reach the roll-up exactly as its owner minted it, or two clients
--- holding the same data compute different roll-ups and never converge. One
--- helper so the prefix and roll-up key can't drift apart at ten call sites.
local ROLLUP_OF = {
    ["cooldown:"]     = "guild:cooldowns",
    ["accountchars:"] = "guild:accountchars",
    ["skills:"]       = "guild:skills",
    ["professions:"]  = "guild:professions",
}
local function refreshRollup(hashes, prefix, DS)
    setEntry(hashes, ROLLUP_OF[prefix],
        rollupOver(hashes, prefix, DS),
        rollupTime(hashes, prefix),
        rollupOverV2(hashes, prefix, DS))
end

-- ---------------------------------------------------------------------------
-- Targeted invalidation
-- Each helper computes the new (hash, updatedAt) tuple from current content
-- and gdb.lastScan, then calls setEntry which is a no-op if unchanged.
-- ---------------------------------------------------------------------------

--- After a cooldown scan or merge for one character.
function HashManager:InvalidateCharCooldowns(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash, hashV2 = mint(DS, gdb.cooldowns and gdb.cooldowns[charKey] or {})
    local ts     = lastScan(gdb, charKey, "cooldowns")
    local wrote  = setEntry(hashes, "cooldown:" .. charKey, hash, ts, hashV2)
    -- Roll-up only needs to recompute when a child changed.
    if wrote then refreshRollup(hashes, "cooldown:", DS) end
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
--- `tokenV2` is the owner's revision-2 token, adopted verbatim alongside the
--- revision-1 one. Absent when the owner is on an older build — in which case
--- this leaf stays V1-only and every roll-up it contributes to falls back to
--- revision 1 until the owner upgrades and re-mints.
function HashManager:StoreDeliveredCooldownLeaf(DS, gdb, ownerKey, token, updatedAt, isAbs, tokenV2)
    local hashes = ensureHashes(gdb)
    local wrote  = setEntry(hashes, "cooldown:" .. ownerKey, token, updatedAt or 0, tokenV2)
    -- Refresh the format flag even on a no-op (hash, updatedAt) write.
    local entry = hashes["cooldown:" .. ownerKey]
    if entry then entry.abs = isAbs and true or nil end
    if wrote then refreshRollup(hashes, "cooldown:", DS) end
    return wrote
end

--- After an accountchars scan for one broadcaster. Call ONLY on the owner's own
--- client, from its own alt-group scan — never on receive (recompute-on-receive is
--- exactly what made accountchars churn). Everyone else adopts via
--- StoreDeliveredAccountCharsLeaf.
function HashManager:InvalidateAccountChars(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash, hashV2 = mint(DS, gdb.altClaims and gdb.altClaims[charKey] or {})
    local ts     = lastScan(gdb, charKey, "accountchars")
    local wrote  = setEntry(hashes, "accountchars:" .. charKey, hash, ts, hashV2)
    if wrote then refreshRollup(hashes, "accountchars:", DS) end
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
function HashManager:StoreDeliveredAccountCharsLeaf(DS, gdb, ownerKey, token, updatedAt, tokenV2)
    local hashes = ensureHashes(gdb)
    local wrote  = setEntry(hashes, "accountchars:" .. ownerKey, token, updatedAt or 0, tokenV2)
    if wrote then refreshRollup(hashes, "accountchars:", DS) end
    return wrote
end

--- After a gathering-skills scan or merge for one character (skills:<charKey>).
--- Unchanged from v1.0.0 — the skills leaf stays gathering-only and drift-free
--- (max-rank-wins), so recompute here is safe and old clients interoperate.
function HashManager:InvalidateCharSkills(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash, hashV2 = mint(DS, gatheringSkills(gdb, charKey))
    local ts     = lastScan(gdb, charKey, "skills")
    local wrote  = setEntry(hashes, "skills:" .. charKey, hash, ts, hashV2)
    if wrote then refreshRollup(hashes, "skills:", DS) end
end

--- Owner MINT of the professions:<charKey> leaf — call ONLY on the character's own
--- client after its own profession scan (never on receive). Computes the full
--- profession-snapshot hash from local data and stamps it with the owner's scan
--- time. Everyone else adopts the result verbatim via StoreDeliveredProfessionsLeaf.
function HashManager:InvalidateCharProfessions(DS, gdb, charKey)
    local hashes = ensureHashes(gdb)
    local hash, hashV2 = mint(DS, allProfessionSkills(gdb, charKey))
    local ts     = lastScan(gdb, charKey, "professions")
    local wrote  = setEntry(hashes, "professions:" .. charKey, hash, ts, hashV2)
    if wrote then refreshRollup(hashes, "professions:", DS) end
end

--- Adopt a professions leaf hash delivered by a peer VERBATIM (v1.0.3 owner-
--- authoritative profession registry — the exact model as StoreDeliveredCooldownLeaf).
--- The character's OWN client mints the professions:<charKey> hash from its full
--- profession set; every relay stores that token verbatim and NEVER recomputes it,
--- so the hash stays owner-identical hop to hop and guild:professions converges
--- instead of churning. The caller has already replaced gdb.skills[owner] with the
--- delivered snapshot; here we just record the owner's token + updatedAt and
--- recompose the guild:professions roll-up from stored leaf hashes (no data re-hash).
function HashManager:StoreDeliveredProfessionsLeaf(DS, gdb, ownerKey, token, updatedAt, tokenV2)
    local hashes = ensureHashes(gdb)
    local wrote  = setEntry(hashes, "professions:" .. ownerKey, token, updatedAt or 0, tokenV2)
    if wrote then refreshRollup(hashes, "professions:", DS) end
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
        refreshRollup(hashes, "cooldown:", DS)
    elseif itemKey:sub(1, 12) == "professions:" then
        refreshRollup(hashes, "professions:", DS)
    elseif itemKey:sub(1, 7) == "skills:" then
        refreshRollup(hashes, "skills:", DS)
    elseif itemKey:sub(1, 13) == "accountchars:" then
        refreshRollup(hashes, "accountchars:", DS)
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

    local hash, hashV2 = mint(DS, craftersMap(gdb, profId))
    setEntry(hashes, "crafters:" .. key, hash, maxTs, hashV2)
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
    refreshRollup(hashes, "cooldown:", DS)
    refreshRollup(hashes, "accountchars:", DS)
    refreshRollup(hashes, "skills:", DS)
    refreshRollup(hashes, "professions:", DS)
end

-- ---------------------------------------------------------------------------
-- Map accessors (consumed by Scanner P2P callbacks)
-- ---------------------------------------------------------------------------

-- Both hash revisions ride on the wire. `hashV2` is simply absent for a leaf we
-- adopted from a peer on an older build, and a receiver falls back to revision 1
-- for that key — which is exactly how the rollout stays coordination-free.
local function copyEntries(hashes, prefix)
    local map = {}
    local prefLen = #prefix
    for key, entry in pairs(hashes) do
        if key:sub(1, prefLen) == prefix then
            map[key] = { hash = entry.hash, hashV2 = entry.hashV2, updatedAt = entry.updatedAt }
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
            map[key] = { hash = entry.hash, hashV2 = entry.hashV2, updatedAt = entry.updatedAt }
        end
    end
    -- Roll-ups
    for _, key in ipairs({ "guild:cooldowns", "guild:accountchars", "guild:skills", "guild:professions" }) do
        local e = hashes[key]
        if e then map[key] = { hash = e.hash, hashV2 = e.hashV2, updatedAt = e.updatedAt } end
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
    -- Both revisions of the empty-table hash, so a placeholder compares against a
    -- peer's real entry on whichever revision they share. A V1-only placeholder
    -- against a V2-carrying peer would fall back to revision 1 unnecessarily.
    local phHash, phHashV2 = mint(DS, {})
    for profId in pairs(addon.CRAFTING_PROFS) do
        local available = (not addon.IsProfessionAvailable)
                       or addon.IsProfessionAvailable(profId)
        if available then
            local crKey = "crafters:" .. tostring(profId)
            if not map[crKey] then
                map[crKey] = { hash = phHash, hashV2 = phHashV2, updatedAt = 0 }
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
    -- Every branch returns a real boolean. `a and b ~= nil` yields NIL when `a`
    -- is nil, so a predicate written that way answers "no" three different ways
    -- (false / nil) depending on which table happens to be missing — fine for
    -- `if HasContent(...)`, a trap for any caller that compares against false or
    -- serialises the result.
    if itemKey == "guild:cooldowns" then
        return gdb.cooldowns ~= nil and next(gdb.cooldowns) ~= nil
    end
    if itemKey == "guild:accountchars" then
        return gdb.altClaims ~= nil and next(gdb.altClaims) ~= nil
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
        local owner  = itemKey:sub(10)
        local bucket = gdb.cooldowns and gdb.cooldowns[owner]
        return bucket ~= nil and next(bucket) ~= nil
    end

    if itemKey:sub(1, 13) == "accountchars:" then
        local owner = itemKey:sub(14)
        local claim = gdb.altClaims and gdb.altClaims[owner]
        return type(claim) == "table" and #claim > 0
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
