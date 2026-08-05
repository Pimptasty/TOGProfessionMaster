# Dependency contracts

Requirements TOGProfessionMaster has on code it does **not** own — required
libraries (LibProfessionDB, DeltaSync, LibGuildRoster, LibItemDB, Ace3), the
shared test harness (WoWAPITesting), and third-party addons we integrate with
(TradeSkillMaster, TOGBankClassic, GreenWall, Auctionator).

## Why this file exists

**Those repos are read-only from here.** When work in TOGPM needs something from
a dependency, the fix does not get made in the dependency's source — it gets
written up here as a contract and applied upstream separately, by hand, in that
repo. Reading a dependency's source to find the right integration point is fine
and expected; editing it is not. The same applies to running a dependency's test
suite: run it, report what it says, do not "fix" it here.

Each entry states **what** is needed, **why** (traced to the behaviour that
forced it), and the **exact contract** — the API shape, so the upstream change is
unambiguous. Where TOGPM ships a workaround in the meantime, the entry says so
and what the workaround costs, because that is what gets deleted once the
contract lands.

Format follows `GuildRoster/Tests/HARNESS_CONTRACT.md`.

---

## 0. Adoption status — what we use, and what we deliberately don't

Audited 2026-08-03 against the READMEs of DeltaSync-1.0 (v4.0.3 / MINOR 17),
AceCommQueue-1.0 (MINOR 5) and LibGuildRoster-1.0 (0.2.5 / MINOR 10). Recorded
so a later session doesn't have to re-derive the same conclusions.

### Adopted

| Capability | Since | Where |
| --- | --- | --- |
| `NewHost` (multi-host isolation) | DS 15 | `Scanner:InitDeltaSync`, hard-gated — an older DeltaSync disables guild sync rather than falling back to the clobbering singleton |
| Send-size second return | DS 14 | `BroadcastItemHashes` / `BroadcastData` call sites, fed to the Sync Log |
| `InitRosterSync` | DS 12 | cross-guild sister rosters |
| `InitGuildMode` | DS 13 | the whisper-broken-server toggle in Settings |
| `onSendFailed` + delivery counters | DS 17 | `Scanner:InitDeltaSync` and `/togpm dsstatus` |
| `MakeHashEntry` / `ComputeHashV2` | DS 16 | `HashManager` mints both revisions; `Scanner` ships, adopts and compares them. See the rollout notes below |
| `GetRosterHash` | LGR 6 | `BroadcastSisterRosters` suppression — a roster whose membership set hasn't changed isn't re-broadcast |
| AceCommQueue embedded on the AceAddon instance | ACQ 1 | `TOGProfessionMaster.lua`, immediately after `NewAddon` — the one non-optional item on DeltaSync's checklist |
| Delivery verdict + `reason` on our own sends | ACQ 5 | `OnXGuildSendResult` in `TOGProfessionMaster.lua` (both cross-guild broadcasts) and the `ace GUILD` probe in `Modules/CommTest.lua`. Adopted in v1.0.6 — before that these three were the only sends in the addon with nobody listening, so a refusal reached the player's bug catcher from inside the comm layer and never reached TOGPM |
| `RegisterSlashCommand` | ACQ 1 | `Ace:OnInitialize` registers `/acq`. Nothing else does — the standalone ships the library and its tests, no loader file — so without this call the library's only runtime diagnostic does not exist in game |

### Revision-2 hash rollout — how it works here

Adopted in v1.0.5. The rules, because getting the fallback wrong makes a
mixed-version guild re-sync the same leaf forever:

- **Every leaf carries both tokens.** `HashManager` mints them together
  (`mint()` → `DS:MakeHashEntry`), stores both in `gdb.hashes`, ships both in the
  leaf payload, and adopts a delivered pair **verbatim** — the owner-authoritative
  rule applies to revision 2 exactly as it does to revision 1.
- **Comparisons pick the highest revision both ends advertise.** `hashesDiffer` in
  `Scanner:OnGuildDataReceived` mirrors DeltaSync's own `HashesDiffer`. A peer on
  an older build sends no `hashV2`, so that pair falls back to revision 1 and still
  agrees; two updated peers get the collision-free comparison.
- **A roll-up advertises V2 only when EVERY child has one** (`rollupOverV2`
  returns nil otherwise). A roll-up composed from a mix of V2 tokens and V1
  fallbacks is not comparable to another client's mix — two clients holding
  identical data would compute different V2 roll-ups and churn. It upgrades
  itself once the last V1-only child is re-minted by its upgraded owner.
- **Revision 1 stays byte-identical.** It is compared against clients that may
  never update.

Retiring revision 1 later is: stop minting `hash` in `mint()`, then delete the
fallback in `hashesDiffer`. No call site changes. Covered by
`Tests/hashv2_spec.lua`, including the mixed-version phantom-difference case.

### Deliberately not adopted

- **`RegisterDebugCategory` / `config.logger` (DS 16).** TOGPM has its own debug
  output (`addon:DebugPrint`) and an in-window Sync Log, so a user with debug on
  can end up with two surfaces. Worth resolving, but it is a UI consolidation
  question rather than a correctness one — and `config.onDebugMessage` (feeding
  DeltaSync's lines into our Sync Log) is probably the better shape than adopting
  its tab wholesale. Not attempted here.
- **`RegisterLeafType` (DS 12), `options.strictKeys` (DS 16).** TOGPM routes its
  sub-protocols on a `type` field inside its own payloads and never calls the
  delta-array API, so neither applies.

### Checked and already correct

- We do **not** call `SetGuildRosterShowOffline` — LibGuildRoster now handles the
  Show Offline Members flag itself, and its README explicitly asks consumers to
  stop doing it. Nothing to change.

---

## 1. TradeSkillMaster — a way to suppress the crafting UI for one session

**Status:** open. TOGPM ships a workaround (v1.0.5).

### What

A public API letting another profession UI take a trade-skill session without
TSM opening its crafting window for it. Something like:

```lua
--- Ask TSM not to show its crafting UI for the current/next trade-skill
--- session. Cleared automatically when the session ends.
--- @param addonTag string  Identifies the caller (as RegisterUICallback's)
--- @param suppress boolean
TSM_API.SuppressUI("CRAFTING", addonTag, suppress)

--- Reverse of the above for the current session, so a user who switches back
--- to TSM mid-session gets its window without reopening the profession.
TSM_API.ShowUI("CRAFTING")
```

### Why

On Classic there is exactly one way to obtain a trade-skill session: **cast the
profession**. The session — not any frame — is what `GetTradeSkillInfo` /
`GetCraftInfo` / `DoTradeSkill` / `DoCraft` read and act on, and it is what
TOGPM's Crafting tab is built on.

That cast fires `TRADE_SKILL_SHOW` (or `CRAFT_SHOW` on Vanilla/TBC). TSM
registers those events itself (`Core/UI/CraftingUI/Core.lua`, `private.FSMCreate`)
and transitions its state machine to `ST_FRAME_OPEN`. So a player who clicks
TOGPM's Crafting tab gets **two** windows: ours, and TSM's — reported in-game on
TBC. Neither addon is doing anything wrong; there is simply no way to say "this
session is mine" through TSM's public surface:

- `TSM_API.IsUIVisible("CRAFTING")` — read-only.
- `TSM_API.RegisterUICallback("CRAFTING", tag, fn)` — notifies **after** the
  window is already open, with `fn(true, frame)` / `fn(false)`.
- `TSM.UI.CraftingUI.Toggle()` — would do it, but `TSM` is a file-local upvalue,
  not reachable from another addon.

Unregistering `UIParent`'s show events (how TOGPM suppresses *Blizzard's* window)
has no effect on TSM, which holds its own registration.

### Workaround TOGPM ships today

`Modules/Crafting/CraftingEngine.lua` registers the public UI callback and, when
the session is one TOGPM's tab opened, hides the frame TSM hands it — with the
frame's `OnHide` script cleared around the hide, because TSM's `OnHide` runs
`EV_FRAME_HIDE` → `TradeSkill.CloseUI(true)`, which would close the very session
our tab is reading. (Clearing the script around a hide is the same technique TSM
itself uses on Blizzard's frame at `CraftingUI/Core.lua:300`.)

What it costs, and why the contract is still wanted:

- **TSM's state machine is left inconsistent** — `private.isVisible` stays `true`
  with the frame hidden, until the real `TRADE_SKILL_CLOSE` transitions it out.
  Harmless in practice today, but it is TSM's internal state and could stop being
  harmless in any release.
- **It is a frame poke, not an integration** — it breaks the moment TSM changes
  how the base frame's `OnHide` is wired.
- **A one-frame flicker**: TSM's window is shown, then hidden.
- TOGPM guards against the worst case (`_tsmSuppressFailed`): if the hide is ever
  observed to close the trade-skill session, suppression disables itself for the
  rest of the play session — a second window beats a Crafting tab with no data.

Covered offline by `Tests/craftsuppress_spec.lua`.

---

## 2. WoWAPITesting — `assert.is_truthy` missing from the bundled runner

**Status:** DELIVERED 2026-08-03, adopted here 2026-08-04 (harness pin `b389a54`). The runner now
resolves luassert's full modifier chain generically, so `assert.is_truthy` / `assert.is_falsy` and
any other combination work. `assert.has_error`'s second argument is now the **expected error**
rather than an ignored message — no TOGPM spec passed one, so nothing changed here.

Existing specs still use the `assert.is_true(x ~= nil)` workaround; it is equivalent and correct, so
it is being left alone rather than churned. New specs should use `assert.is_truthy`.

Requests on the harness now live in [`Tests/HARNESS_CONTRACT.md`](../Tests/HARNESS_CONTRACT.md),
which is the staging point the harness's own protocol asks for; this section stays as the record of
one that closed.

The original write-up follows, unchanged.

### What

`Tests/wowapi/run.lua`'s `assert` table should carry `is_truthy` / `is_falsy`
alongside the existing `is_true` / `is_nil` / `same` / `equal` / `is_function` /
`has_error`.

### Why

The runner exists so specs run **unchanged** under either it or real busted (its
own README says so). Real busted provides `assert.is_truthy`; the runner does
not, so a spec written against busted's documented API dies with
`attempt to call field 'is_truthy' (a nil value)` — observed while writing
`Tests/browserlink_spec.lua`. That breaks the interchangeability the runner is
built to provide, and it fails at *call* time, so it only surfaces on the branch
that happens to execute.

### Contract

```lua
-- In run.lua's assert table:
assert.is_truthy(v)  -- passes unless v is nil or false
assert.is_falsy(v)   -- passes when v is nil or false
-- Aliases, matching busted: assert.truthy / assert.falsy
```

Until then TOGPM specs use `assert.is_true(x ~= nil)`, which is equivalent but
noisier.

### Related — also delivered

`Tests/coverage.lua` used to be **copied** into each addon (seven copies existed across the suite,
in three functionally distinct lineages). It moved into the harness on 2026-08-03; TOGPM's local
copy was deleted on 2026-08-04 and the invocation is now
`lua Tests/wowapi/coverage.lua <targets>`. Verified identical on the switch — `TOGProfessionMaster.lua`
703/1409, `Modules/HashManager.lua` 340/340 — so the number moving later means the code moved, not
the tool.

---

## 3. LibProfessionDB — recipe keys are spell ids (documented, no change needed)

**Status:** satisfied. Recorded so the assumption is not re-derived.

Every key in `lib:GetRecipes(profId)` is the recipe's trade-skill **spell** id
(built from `SkillLineAbility`), on every profession and every game version. The
crafted item, when there is one, is the separate `craftedItemId` field;
`itemId` is the recipe *scroll*, not the product.

TOGPM depends on this in `GUI/BrowserTab.lua` and `Data/RecipeDB.lua`. Treating a
key as an item id resolves whatever unrelated item shares the number — spell
13937 (*Enchant 2H Weapon - Greater Impact*) vs item 13937 (*Headmaster's
Charge*) — which is the v1.0.5 enchant-tooltip bug. Guarded by
`Tests/browserlink_spec.lua`. If LibProfessionDB ever re-keys its tables, that is
a breaking change for TOGPM and belongs in its changelog as one.
