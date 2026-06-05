# Cross-Guild Sync Design (working doc)

Status: **exploration — no decisions committed yet.**

Goal: let users who belong to two (or more) configured sister guilds share TOGPM
profession/cooldown/recipe data across those guilds, since the normal GUILD
addon-comm channel can't reach a sister guild. Discovery is via `/who`;
**GreenWall is NOT used (dropped — see D6).**

This doc records ONLY what we discuss and decisions as we make them.

**Stack ownership:** we own and can modify every layer — TOGPM, GreenWall,
DeltaSync (which contains the GuildCache-1.0 roster lib), and LibGuildRoster.
So any layer is fair game to change rather than work around.

> Compat note: TOGPM resolves the roster lib by the LibStub major string
> `"GuildCache-1.0"` (Scanner.lua:184, TOGProfessionMaster.lua:459, + the `.toc`
> `## Dependencies`). If the lib is renamed inside DeltaSync, the major string,
> both call sites, and the `.toc` dep must change together or roster goes nil
> and guild sync soft-disables (Scanner.lua:185-186).

---

## Background fact — how data is stored today (verified from code)

There is **no per-guild bucket.** (The `.global.guilds["Faction-GuildName"]`
schema in `CLAUDE.md` is stale — it describes a pre-v0.7.0 design that was
refactored into the flat, tag-based model below.)

- **Recipes — flat, one row per recipe; guild attached per-crafter inline:**

  ```lua
  recipes[profId][recipeId] = { crafters = { [charKey] = guildTag } }
  ```

  `charKey` = `"Name-NormalizedRealm"`. The recipe row is shared; what gets
  added per crafter is `charKey → guildTag`.
  Source: TOGProfessionMaster.lua:129-135, :1234

- **Guild tag** = 6-hex FNV-1a hash of `"Faction-GuildName"` (or `"personal"`
  for guildless). `guildRegistry[tag] = { name, faction, key }` maps it back to
  a readable name. Source: TOGProfessionMaster.lua:1307 (`GetGuildTagFor`),
  :1325 (`GetCurrentGuildTag`).

- **Cooldowns / skills / specs / factions — keyed by `charKey` only, no guild
  scope:** `cooldowns[charKey][spellId] = expiresAt`.
  Source: TOGProfessionMaster.lua:138-142.

- **Consequence:** the model already supports multiple guilds coexisting in the
  same flat tables, with a display-time visibility gate filtering crafters by
  tag (TOGProfessionMaster.lua:1337). Cross-guild data does NOT need new
  storage — it goes in the same tables carrying the **origin** guild's tag.

- **Single contained bug this exposes:** inbound merge stamps
  `GetCurrentGuildTag()` (the *receiver's* tag) onto incoming crafters
  (Scanner.lua:1862, :1889). Correct within one guild; mislabels sister-guild
  crafters as ours. Fix (not yet decided): payload carries each crafter's true
  origin tag; receiver registers it in `guildRegistry` and tags with it.

---

## Background fact — roster source for sister guilds (verified)

- TOGPM's roster truth is **GuildCache-1.0** (bundled in the DeltaSync addon at
  `DeltaSync/Libs/GuildCache-1.0/`), NOT LibGuildRoster-1.0. LibGuildRoster
  lives in other addons (fastguildinvite, standalone GuildRoster). Source:
  Scanner.lua:184, TOGProfessionMaster.lua:459.

- **Hard constraint:** no WoW addon can read the roster of a guild it isn't in.
  `GetGuildRosterInfo` / guild events only ever return the player's OWN guild.
  GuildCache and LibGuildRoster both populate solely from that API. Therefore a
  sister-guild roster **cannot be scanned** — it can only be **built from
  over-the-wire presence** (the `sender` field of TOGPM messages bridged across
  GreenWall, and/or an explicit roster-announce sent over the bridge).

- Owning a roster lib helps only by letting us extend it to *hold* N named
  rosters (one self-scanned + others externally fed). It can never *populate*
  the sister rosters; that is TOGPM's job, sourced from GreenWall traffic.

- **Open question (not yet decided):** does the sync need a full sister-guild
  roster mirror, or just a lightweight **confederation-peer presence table**
  `{ sisterCharKey → { guildTag, lastSeen } }` built from sync traffic?
  - Presence table covers everything the *sync* needs: isValidPeer (any TOGPM
    sender over the GreenWall bridge is self-certifyingly confederated), online
    inference, whisper targeting. Tag→name display already handled by
    `guildRegistry`.
  - Full roster mirror is only needed to *display* complete sister membership
    (incl. members with no TOGPM data), and is the expensive path — big payload
    vs. GreenWall's ~186-byte / no-fragmentation cap.

---

## Decisions

### D1 — Mirror the FULL sister-guild roster (membership list)

We will maintain a full membership list for each sister guild, not just the
sister characters that have TOGPM data.

**Why (the real driver):** the display/purge gate `IsVisibleCrafter`
(TOGProfessionMaster.lua:1346) hides+purges any crafter whose tag ≠ the local
guild tag, and otherwise requires `GuildCache:IsInGuild(charKey)` against the
LOCAL roster. Sister crafters fail both. To show them AND correctly purge them
when they leave the sister guild, the gate must validate sister crafters against
the sister guild's roster — which therefore must be complete and current.
(Note: the *viewing* goal — non-crafters seeing who can craft X — does NOT by
itself need a roster; that rides on the recipe rows + `guildRegistry`. The gate
is what forces full membership.)

**Implications / costs accepted:**

- Only members of a guild can scan its own roster, so each guild's TOGPM users
  broadcast THEIR roster over GreenWall; the other guild ingests it. Needs a
  designated/coalesced broadcaster per guild to avoid duplicate copies.
- We only need the charKey membership set for the gate (not ranks/levels/notes),
  which trims payload — but it's still far over GreenWall's ~186-byte /
  no-fragmentation / throttled `EXTERNAL` cap. This likely forces the GreenWall
  fragmentation change or a roster-chunking protocol (previously deferred).
- GuildCache-1.0 becomes a multi-roster store (one self-scanned + N fed).
- `IsVisibleCrafter` and `IsAltOfInRosterCharacter` (TOGProfessionMaster.lua:1346,
  :1381) become confederation-aware: accept confederated tags, validate against
  the matching sister roster.

### D2 — Transport: roster HASH over GreenWall, roster DATA over whispers

The roster crosses the confederation as a normal DeltaSync leaf, not via any new
transport and not by riding GreenWall's channel.

- The roster is a leaf `roster:<guildTag>`, hashed by HashManager like cooldown
  and recipe leaves.
- Only the tiny **hash-offer** (guild tag + short digest) goes over GreenWall's
  clean `EXTERNAL` API (`GreenWallAPI.SendMessage` / `AddMessageHandler`). Fits
  the ~186-byte cap easily — no fragmentation, no channel-riding, no DeltaSync
  transport changes.
- **Resolution** uses the existing whisper path: receiver sees a hash it lacks →
  `RequestData` → provider `SendData` over AceComm WHISPER with normal
  segmentation. A ~500-member roster ≈ 10KB ≈ 40 whisper chunks — smaller than a
  full recipe-set sync already done today. The chat bridge is never touched.
- DeltaSync's relay model lets any peer with a cached sister roster serve it.

**Rejected alternatives:** (A) rewrite GreenWall's chat bridging on DeltaSync —
breaks GreenWall's primary function, no benefit; (B) DeltaSync rides GreenWall's
hidden channel — shares the per-player chat-send throttle with the chat bridge,
couples us to GreenWall's channel lifecycle, fights the intended `EXTERNAL` API
boundary. We use GreenWall purely as a thin confederation-wide doorbell.

**Faults to handle in implementation:**

1. **Broadcaster coalescing** — all online sister members compute the same
   `roster:<tag>` hash; debounce + "saw this hash already, suppress mine" dedup
   so the doorbell rings once per change, not N times. Mirror the existing 30s
   GUILD broadcast debounce.
2. **Freshness depends on a sister being online** — leave-detection only updates
   when a sister member is online to re-scan + re-advertise. Stale otherwise.
   Accepted degradation (same as "owner offline" today).
3. **Cold-start ordering trap (correctness risk)** — sister crafter data and the
   sister roster are independent leaves that propagate separately. If crafter
   data arrives before the roster, the visibility gate has no roster to validate
   against and would flag those crafters for purge. The gate's deferred-purge
   safety (pendingPurge sweep, TOGProfessionMaster.lua:163) was designed for an
   always-present local roster. For sister rosters the semantics must INVERT:
   "no roster loaded yet for this tag" → KEEP the crafters (can't judge them),
   never purge. Without this, cold-start ordering silently deletes valid
   sister-crafter data.
4. **GreenWall echo/guild flags** — beacon handler filters `echo=true` and
   ignores `guild=true` beacons (own co-guild already covered by GUILD comm).
5. **Trust boundary** — a confederation member could advertise a fake
   `roster:<otherTag>` hash. Low risk (whisper resolution is server-authenticated
   point-to-point); sanity-check the broadcaster's own char is in the roster it
   advertises.

### D3 — LibGuildRoster stays framework-agnostic; gains only "sister guild" wiring

Dependency direction: **DeltaSync (and TOGPM) integrate WITH LibGuildRoster; the
lib is NOT aware of DeltaSync or GreenWall.** (This supersedes the earlier
Scope A/B question — Scope A confirmed. A lib that registered DeltaSync leaves
would invert the dependency.)

The **membership hash is the seam**: the lib produces a stable per-roster
fingerprint and stores rosters it is handed; DeltaSync reads the fingerprint,
decides when to sync, and hands resolved data back. Neither crosses the line.

LibGuildRoster is MINOR 5 today (standalone `GuildRoster` repo; `fastguildinvite`
ships an older MINOR 2) — single self-scanned in-memory roster, no multi-roster,
no sync. Additions needed:

Minimum:

1. **Multi-roster storage** — `lib.roster` → `lib.rosters[guildKey]`; one
   self-scanned *home* roster (unchanged) + N externally-fed *sister* rosters.
   Key on `"Faction-GuildName"`; the FNV *tag* concept stays in TOGPM.
2. **Ingest API** — `lib:SetSisterRoster(guildKey, members[, meta])` (wipe+
   replace), `lib:RemoveSisterRoster(guildKey)`. Caller hands plain data; the lib
   has no idea it came from sync.
3. **Cross-roster query** — `lib:IsInAnyRoster(name) → guildKey|nil` (what the
   gate needs), `lib:IsInGuildScoped(guildKey, name)`, `lib:GetRoster(guildKey)`.
   Existing `IsInGuild`/`IsOnline`/`GetMember`/`GetAllMembers` stay home-only and
   UNCHANGED — bump MINOR, add, never mutate.

Strongly recommended (correctness, still framework-agnostic):

1. **Deterministic membership hash** — `lib:GetRosterHash(guildKey)` +
   `OnRosterHashChanged(guildKey)`. Hash the SORTED MEMBERSHIP SET ONLY, never
   presence: so every client of the same guild computes the identical hash and it
   doesn't churn on login/logout. This is the leaf-hash seam for D2.
2. **Sister-scoped diff callbacks** — `OnMemberJoined/Left(name, guildKey)` from
   diffing successive `SetSisterRoster` snapshots; drives sister-crafter purge.

Explicitly NOT in the lib:

- Any DeltaSync/GreenWall reference (sync+transport glue lives in DeltaSync +
  TOGPM).
- Export/import persistence — the consumer fed the data, already has it, and
  persists it in its own SavedVariables, re-feeding via `SetSisterRoster` on
  login. Lib stays in-memory.

Contracts to pin (not lib code):

- `guildKey` / `charKey` / realm spelling identical across lib + TOGPM or
  `IsInAnyRoster` matches nothing.
- `SetSisterRoster` on the home guildKey is ignored (self-scan wins).
- Fed charKeys are full `"Name-Realm"` (guaranteed within the connected-realm
  cluster confederations live in).
- Version skew: all embedders (incl. the GuildCache-1.0↔LibGuildRoster
  consolidation in DeltaSync) and `.toc` deps must move to the new MINOR together,
  or LibStub hands an old copy lacking `SetSisterRoster` and feeds become no-ops.

### D4 — Reusable sync lives in DeltaSync (`RosterSync`), not in LibGuildRoster

"Scope B" reconciled with D3: the reusable cross-guild roster sync goes in
**DeltaSync** (a shared lib also embedded by TOGBank), NOT inside LibGuildRoster.
This keeps LibGuildRoster framework-agnostic AND lets other addons (TOGBank)
reuse the sync for free. Three layers:

- **LibGuildRoster** — dumb multi-roster store (D3): home + sister rosters,
  ingest / query / hash / diff. No sync awareness.
- **DeltaSync `RosterSync` (new)** — the reusable piece. Reads the home-roster
  hash from LibGuildRoster, broadcasts it, resolves sister rosters over WHISPER,
  feeds them back via `lib:SetSisterRoster`. Natural home: DeltaSync already
  depends on a roster lib. **TOGBank reuses this by embedding DeltaSync + Lib.**
- **TOGPM / TOGBank** — inject the *discovery transport* (GreenWall beacon for
  TOGPM's confederation) as an adapter, and read `IsInAnyRoster` for the gate.

Note on the confederation medium (we own GreenWall, so this is a real choice, not
a coupling-avoidance default):

- GreenWall's true value is the confederation **definition + membership** (which
  guilds are linked, the shared hidden channel, secret/config from officer notes,
  cross-realm bridging, hold-down). The message API is thin on top. Rebuilding
  confederation natively in DeltaSync would duplicate that hard part and create a
  SECOND parallel config admins maintain separately → rejected unless the goal is
  confederation with GreenWall NOT installed.
- **Recommendation: DeltaSync consumes GreenWall's confederation** (don't rebuild
  it), through a THIN seam (a two-function indirection: `broadcastHash` /
  `onHashReceived`) rather than GreenWall calls scattered through `RosterSync`.
- **Key sizing insight:** because of D2, the only thing crossing the confederation
  medium is the tiny hash beacon, which already fits GreenWall's existing 186-byte
  `EXTERNAL` API. So this feature needs NO GreenWall transport enhancement —
  fragmentation/acks would be a separate, optional improvement, not a prerequisite.
- Throttle physics unchanged by ownership: the shared `SendChatMessage` rate limit
  is a server constraint. Ownership only adds levers (separate hold-down budget for
  addon traffic, chat-priority) — and D2 keeps beacon volume low enough we don't
  need them here.

**Open decision (sets the seam thickness):** is confederation ALWAYS GreenWall for
us?

- Yes → DeltaSync leans on GreenWall directly, near-zero seam, simplest. TOGBank
  cross-guild then simply requires GreenWall (already true for these users).
- Maybe not → keep the thin seam with GreenWall as the first/best provider, so a
  future non-GreenWall confederation plugs in without touching `RosterSync`.

### D5 — Discovery via `/who`, NOT GreenWall broadcast (LEADING — under discussion)

Reconsidering D2's discovery half. Primary discovery = a polite `/who g-"GuildName"`
query (the FGI pattern) to find ONLINE sister-guild members, then whisper-sync with
one of them. Supersedes the GreenWall beacon as the FIRST path; GreenWall demoted to
an optional seed/backstop (and its residual value is questionable — see below).
The whisper-resolution half of D2 (roster + recipe data as leaves over WHISPER) is
UNCHANGED — only the discovery mechanism changes (GreenWall-push → /who-pull).

Why /who wins for our case (2 guilds):

- WoW allows only 10 chat channels; burning one per addon integration is wasteful.
  /who needs none.
- Zero dependency / zero setup: sister guild(s) configured by NAME in TOGPM options.
  No GreenWall, no confederation config. Trivially reusable for TOGBank.
- Pull, on our schedule. Rosters rarely change, so no real-time push medium needed.
- The probe is invisible: once /who yields an online name, the DeltaSync handshake is
  a WHISPER = CHAT_MSG_ADDON, invisible to the recipient. Non-TOGPM members simply
  never reply. No human is spammed.

Architectural payoff: discovery becomes a PURE CONSUMER concern. DeltaSync RosterSync
no longer needs a confederation-broadcast concept at all — the beacon/seam/
`OnConfederationBeacon` apparatus from D4/Block-1 collapses to "consumer hands
RosterSync a candidate peer: sync `roster:<guildKey>` with `<name>`." Less code in
the shared lib, more reusable (discovery-agnostic).

Hazards / must-handle (downgraded — see note):

- **/who throttle is NOT a blocker for us.** Earlier concern was retail-calibrated;
  this addon is Classic-only. Non-retail allows /who every ~2s, we only need ONE
  responder to seed, and the DeltaSync handshake is an invisible addon WHISPER. The
  ~2s is a FLOOR for the bootstrap burst, NOT the steady-state cadence — rosters
  rarely change, so steady-state polling is slow (minutes) to avoid spamming other
  players' /who.
- Residual (minor): the /who result buffer + WHO_LIST_UPDATE are a shared singleton,
  so TOGPM's poller must coexist with the player's manual /who AND with FGI's /who
  (user runs both addons). Not a correctness risk — share a who-queue / don't poll
  simultaneously. We own both, so coordinate.
- ~50-result cap: only bites if >50 online and none of the first 50 run TOGPM. We need
  one hit to seed — low severity.
- Same-faction only (/who + whispers don't cross factions). GreenWall had the same
  effective limit.
- Name normalization from /who results → "Name-Realm" charKey (reuse FGI normalize).

Refinement — bootstrap vs steady-state + targeting (resolves sub-Q2 & sub-Q5):

Two distinct roles, do not conflate:

- sister ROSTER → the visibility/purge GATE (D1).
- known sister CRAFTERS → whisper TARGETING (D5). Known crafters are ALREADY held in
  persisted recipe data, so targeting doesn't need the roster.

Persistence (the D3 consumer-persists decision applied here): TOGPM persists the
sister roster in `TOGPM_GuildDB` and re-feeds `SetSisterRoster` on login/reload; the
lib stays in-memory. Crafter data already persists (it IS the DB).

Refined flow:

- First contact ever: /who → blind-probe up to 50 (invisible) → first responder seeds
  roster + crafters → persist.
- Every session after: re-feed persisted roster/crafters on login → /who → intersect
  `online ∩ known-crafters` → whisper precisely. No blind probe, no cold-start.

### D6 — Drop GreenWall entirely

GreenWall is removed from the design. Discovery is `/who`-only (D5); persistence
(D3 consumer-persist, applied in D5) eliminates cold-start after first contact. The
only gap GreenWall could have filled — true first contact when NO sister member is
online during your session — is unsolvable by any medium (a broadcast can't conjure
data from offline players), so the seed earns nothing.

Supersedes:

- D2's discovery half (the GreenWall hash-beacon) — GONE. D2's whisper-resolution half
  (roster + recipe data as leaves over WHISPER) STANDS.
- D4's confederation seam — GONE. No `broadcastBeacon` / `OnConfederationBeacon`, no
  beacon payloads, no beacon coalescing/dedup. `RosterSync` no longer has any
  confederation-broadcast concept; the consumer hands it a discovered peer to sync.

Resulting clean architecture:

- **LibGuildRoster** — dumb multi-roster store (D3), unchanged by this decision (it
  never knew about GreenWall).
- **DeltaSync `RosterSync`** — thin adapter: builds/serves the `roster:<guildKey>` leaf
  from LibGuildRoster, syncs it over WHISPER via the existing leaf machinery, feeds
  `SetSisterRoster` on receipt. Driven by a consumer-supplied peer. No broadcast.
- **TOGPM** — `/who` discovery + known-crafter targeting + persistence +
  confederation-aware gate.

### D7 — Sister presence: YES, sourced from `/who` only (GreenWall stays dropped)

Sister-guild crafters show live online status in the UI. Source is `/who` — which is
required for discovery anyway, so crafter presence is essentially a FREE byproduct of
a discovery query. GreenWall stays dropped (D6 holds); presence does NOT re-introduce
it.

Lib API (presence overlay — distinct from the roster snapshot, source-agnostic):

- `lib:MarkOnline(guildKey, names)` — stamp `lastSeenOnline = now` for each name that
  exists in `rosters[guildKey]` (ignore unknowns — they hint the roster is stale, but
  that's TOGPM's concern). Fed from a `/who` snapshot.
- `lib:GetOnlineMembers(guildKey)` — for a SISTER guild, return members stamped within
  a freshness window (`lib.PRESENCE_TTL`, ~a couple poll cycles); for the HOME guild,
  keep using the authoritative live `member.isOnline`. (Add a scoped read; existing
  home-only `IsOnline`/`GetOnlineMembers` semantics unchanged.)
- **Timestamp/last-seen model, NOT a hard boolean** — robust to `/who`'s 50-cap and
  poll gaps: never assert "offline", just age out. Self-corrects next cycle.

Reversibility (why this is low-risk): the overlay is source-agnostic. If `/who`
presence proves too laggy, a GreenWall online-event feed can be added later as a pure
addition — `lib:SetMemberPresence(guildKey, name, true)` into the SAME overlay — with
no change to storage or any other layer. Deferred enhancement, not a dead end.

Refinements already agreed if GreenWall presence is ever added: broadcast only
"came online" (offline inferred by aging out); light coalescing for login bursts.

Scaling caveat (honest): /who scales linearly in queries per sister guild — fine for
2–3 guilds, worse than a single shared channel for large (5+) confederations. So /who
primary for small confederations; channel better for large. This is exactly why
GreenWall stays an optional seed. BUT: the seed's residual value is thin, because the
"someone cached the data while the owner is offline" case is already covered by normal
GUILD-comm relay within our own guild. Decide whether the seed earns its keep before
building it.

Open sub-questions (the "first path"):

1. /who scheduling — login (delayed) / periodic / on-demand when the cross-guild view
   opens? Cadence given rosters rarely change.
2. Candidate selection + probe bounds — whom to whisper-probe among online hits, how
   many before stopping (invisible, but whisper-throttle applies).
3. Does the GreenWall seed earn its keep at all, given the relay overlap?
