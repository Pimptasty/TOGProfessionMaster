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
AceCommQueue-1.0 and LibGuildRoster-1.0 (0.2.5 / MINOR 10). Recorded so a later
session doesn't have to re-derive the same conclusions.
**AceCommQueue re-audited 2026-08-05 at MINOR 6.**

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
| `RegisterSlashCommand` | ACQ 1 | `Ace:OnInitialize` registers `/acq`. Nothing else does — the standalone ships the library and its tests, no loader file — so without this call the library's only runtime diagnostic does not exist in game. Registering it is also what puts MINOR 6's `/acq unstick` in the player's hands, at no further cost here |
| `reason = "lost"` | ACQ 6 | `OnXGuildSendResult` and the `ace GUILD` probe. **Not free on upgrade:** `"lost"` arrives with `delivered == nil`, so the MINOR 5 test (`delivered == false or rejected or error`) walked straight past it. It is also the failure that matters most — a send reported `"lost"` has already been released, re-sent under the retry budget and failed again, so unlike a refusal it will *not* heal itself on the next periodic pass |

### The stall report: fixed upstream, and what that means here

The `queue STALLED — 74s with no progress on an in-flight send` errors were
**AceCommQueue misdiagnosing ordinary client throttling**, and MINOR 6 fixes it
in the library, not here. Recorded because the shape of the fix decides what
this addon should and should not do about it:

- ChatThrottleLib moves a *throttled* send into its `Blocked` ring and retries it
  ~2.5×/sec while firing **no callback**. From the queue's side that is
  indistinguishable from a lost callback, and MINOR 5's 60-second timeout
  reported it as a host-addon bug. `checkStall` now asks CTL first and stays
  silent for as long as CTL still holds the message.
- The default timeout moved 60 → **300s**, and a stall is now reported once per
  queue per session, then counted as `stalls=N` in `/acq status`.
- A genuine stall now **recovers**: the slot is released and the message re-sent
  at the head of its bucket under the retry budget.

**So TOGPM overrides neither `SetStallTimeout` nor `SetRetryPolicy`, and does not
call `Unstick`.** The defaults are the tuned values, and forcing a release from
here would re-introduce the duplicate-on-the-wire risk the library's own CTL
safety test exists to prevent. What TOGPM owes the contract is reading the fifth
reason correctly, which is the row above.

### AceCommQueue: deliberately not adopted

| Capability | Since | Why not |
| --- | --- | --- |
| `SetStallTimeout` / `SetRetryPolicy` | ACQ 5 | The MINOR 6 defaults (300s, standard retry budget) are the tuned values, chosen against exactly the traffic pattern that produced our stall reports. Overriding them here would be guessing against the library author's measurements |
| `Unstick` / `/acq unstick` (called from TOGPM) | ACQ 6 | The command is already in the player's hands via our `/acq` registration. Calling it *automatically* from the addon would defeat the point: recovery already happens on its own after 300s, and a programmatic force-release is a way to reintroduce interleaved chunks if our own timing guess is worse than the library's |

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

---

## 4. ItemDB / LibProfessionDB — the recipe→teaching-item mapping is incomplete, and the gap is filled by a NAME MATCH

**Status:** open request. Raised 2026-08-06.

### What is being asked for

An authoritative, DBC-sourced mapping from a **recipe spell id** to the **item
that teaches it** (`Pattern:` / `Plans:` / `Recipe:` / `Formula:` /
`Schematic:` / `Design:` / `Manual:` / `Technique:` scrolls and books), covering
the recipes that ship today with no `itemId`.

### Why TOGPM wants it

The Professions tab lists the **crafted item's** name and icon — "Barbaric
Shoulders", not "Plans: Barbaric Shoulders" — and that display is staying. What
should change is the mouseover: showing the real teaching-item tooltip gives the
authentic recipe tooltip (which natively embeds the crafted item's stats) and
lets other addons' tooltip hooks contribute, which is the thing a user asked for
on Discord after seeing a chat link render richer than our own list.

That is only worth doing where the mapping exists. Measured against the shipped
Vanilla data:

| Profession | Recipes | Has `itemId` | Coverage |
| --- | ---: | ---: | ---: |
| Cooking | 89 | 76 | 85.4% |
| Blacksmithing | 315 | 227 | 72.1% |
| Leatherworking | 314 | 226 | 72.0% |
| Enchanting | 279 | 199 | 71.3% |
| Tailoring | 291 | 193 | 66.3% |
| Engineering | 196 | 124 | 63.3% |
| Alchemy | 131 | 75 | 57.3% |
| First Aid | 14 | 5 | 35.7% |
| Mining | 13 | 1 | 7.7% |
| **Total** | **1642** | **1126** | **68.6%** |

### The part that makes this a contract rather than a nice-to-have

**The 68.6% is already propped up by string parsing, which this project's own
rule forbids.** `tools/build_authoritative_data.py` documents why, at the
"Recipe-scroll name-match supplemental linker" comment:

> `ItemEffect` only contains direct spell-teach mappings — but many WoW recipe
> scrolls implement their teaching via a generic "Learning" spell (483) whose
> effect is then chained server-side to grant the specific craft spell.
> `ItemEffect` captures the item→Learning link, not the item→specific-craft
> link. As a result our `items_by_spell` map misses ~80-100 recipes per
> profession whose scrolls exist but aren't directly linked in DBC.

The workaround strips the scroll prefix and matches the remainder against
`SpellName`. Self-reported at a 97% hit rate (1,047 of 1,082 Vanilla scrolls),
with 35 misses attributed to singular/plural mismatches and legacy "Imbue X"
naming. It is also locale-fragile by construction: the prefix list is English,
so a non-enUS pull cannot use it at all.

### The specific lead worth chasing first

The missing hop looks like it is one join away, not a data absence:

```text
ItemEffect.ParentItemID → ItemEffect.SpellID            (item → "Learning", 483)
SpellEffect[SpellID, Effect = 36].EffectTriggerSpell    (→ the real craft spell)
```

`Effect = 36` is `SPELL_EFFECT_LEARN_SPELL`. If that chain resolves, the
name-match linker can be deleted outright rather than merely supplemented, and
the mapping becomes locale-independent.

### How to tell a real answer from a plausible one

**Mining must NOT reach high coverage.** Smelting recipes are trainer-taught and
genuinely have no teaching item — 7.7% is close to correct there, and a result
claiming Mining at 90%+ has matched something that is not a recipe scroll. Same
caution for First Aid, where several entries are skill-rank books rather than
recipes. The useful signal is Alchemy and Engineering, currently the weakest of
the professions that clearly *do* have scrolls.

Please also report, per build, the count of recipes with **no** teaching item
after the join — that number is the real answer to "how much of this can ever be
uniform", and TOGPM's fallback design depends on it.

### What TOGPM will do with it

Recipes with a teaching item get the genuine item tooltip on hover. The
remainder keep the hand-built tooltip, shaped to match, so the seam is not
visible. No display change either way.

> **ItemDB response — 2026-08-05 — DELIVERED (LibItemDB-1.0 MINOR 17, ItemDB v0.6.0).**
> The lead was right, and it is stronger than "chase this first": the
> `ItemEffect.SpellID → SpellEffect[Effect = 36].EffectTriggerSpell` chain resolves, and the
> name-match linker can be **deleted outright**, not merely supplemented.
>
> New API: `lib:GetRecipeItem(spellID)` → `itemID, isRankBook`. Built by
> `tools/build-recipe-items.py`, shipped as `Data/{Vanilla,TBC}/_core/RecipeItems.lua`.
>
> **Measured scroll-by-scroll against your linker on Vanilla `1.15.9`, all 1,082 scroll-named
> items:** agree 1,040 · disagree 1 (item 228118 — DBC wins) · **DBC-only 35** · **name-match-only
> 0** · neither 6. Deleting the linker loses nothing and gains 35, which are exactly the cases its
> own comment predicted — *Ornate Mithril Shoulder* vs *Shoulders*, *Philosopher's* vs
> *Philosophers'*, *Imbue Cloak* vs *Enchant Cloak*, and the whole *Transmute X to Y* vs
> *Transmute: X to Y* family. It is also locale-independent, so a non-enUS pull can use it.
>
> **The number your fallback design depends on — recipes with NO teaching item after the join:**
> Vanilla `1.15.9` **572** of 1,645 (65.2% covered); TBC `2.5.6` **814** of 2,267 (64.1% covered).
> So roughly a third will always need the hand-built tooltip. `GetRecipeItem` returns nil for those
> deliberately — nil means "no such item exists", not "data missing".
>
> **Your sanity checks hold.** Mining is 4.3% / 3.3%, and its single hit is a genuine SoD scroll
> (*Manual: Smelt Obsidian-Infused Thorium Bar*), not a false positive. Herbalism and Skinning are
> 0%.
>
> **One thing you flagged that turned out to matter more than expected:** you warned First Aid has
> "skill-rank books rather than recipes". It does, and so do Fishing and Cooking — *Expert Fishing -
> The Bass and You* genuinely teaches spell 7732, so the join is right to resolve it, but it is not
> a recipe, and it is what makes those professions look surprisingly well covered. They are
> classified from data rather than titles (the taught spell's name is the profession's own name) and
> returned as `isRankBook = true`, so your recipe list can exclude them without string-matching.
>
> **One caveat worth knowing before you rely on a single build:** the two resolution paths invert
> between expansions. Vanilla is 61 direct `ItemEffect` / 1,027 chained; TBC is 1,580 direct / 9
> chained. Both are load-bearing — a build-specific implementation that only handled the chain would
> silently collapse on TBC.
>
> Not yet done: Wrath / Cata / Mists (no `_core` tree, same block as the other LibItemDB data), and
> the 6 scrolls neither method resolves (*Recipe: Instant Toxin*, *Formula: Imbue Chest -
> Minor Spirit* / *- Spirit*, *Manual: The Path of Defense*, *Manual: Path of the Berserker*,
> *Formula: Powerful Smelling Salts*) — all of which reach a spell that is not in any profession's
> `SkillLineAbility`, so they may not be craft recipes at all.

---

## 5. ItemDB — a synthetic recipe-scroll descriptor for the third that have no real one

**Status:** open request. Raised 2026-08-06, following on from §4.

### What is being asked for

A second table alongside `RecipeItems`, describing what a recipe scroll **would** look like for every
craft spell that has no real teaching item — the 572 Vanilla / 814 TBC that `GetRecipeItem` correctly
returns nil for. Enough to render a scroll-shaped tooltip:

```lua
lib:GetSyntheticRecipeScroll(spellID)
--> { name          = "Plans: Barbaric Shoulders",  -- localized, profession's own prefix
      professionID  = 164,
      requiredSkill = 200,
      craftedItemID = 15053,
      isSynthetic   = true }
--> nil when the recipe HAS a real teaching item (use GetRecipeItem for those)
```

### Why this belongs in ItemDB and not in each addon

This is the point of the request, and the reason it is not being solved locally. Every addon that
lists profession recipes hits the same wall: two thirds of rows can show a real scroll tooltip and
one third cannot, so each invents its own fallback and they all look different. That is the exact
fragmentation ProfessionDB exists to prevent for recipe data. Put the descriptor in the shared
library and Skillet, TSM, TOGPM and anything else render the identical thing without coordinating.

The alternative — every consumer hardcoding `"Plans: %s"` in English — is precisely the trap the
name-match linker fell into, and §4 has just finished getting us out of it.

### The one hard constraint: NO synthetic item ID

**Do not mint an `itemID` for these, not even a negative or out-of-range one.** A fabricated id is a
field something downstream will eventually hand to `GetItemInfo`, `SetItemByID`, an auction search or
a chat link, and the failure is silent. Our own code documents it at
`GUI/MissingRecipesTab.lua:1167` — *"Calling SetItemByID on a cache-cold item ID silently sets an
empty tooltip"* — and a permanently fictional id is permanently cache-cold.

`isSynthetic = true` and no id field at all makes the distinction impossible to miss. A consumer that
wants a real item tooltip calls `GetRecipeItem`; one that wants to *draw* a scroll calls this. Never
both for the same recipe.

### The field that actually needs DBC, and cannot be derived locally

`name` — the localized scroll prefix per profession. `"Plans: "` for Blacksmithing, `"Pattern: "` for
Tailoring and Leatherworking, `"Recipe: "` for Alchemy / Cooking / First Aid, `"Formula: "` for
Enchanting, `"Schematic: "` for Engineering, `"Design: "` for Jewelcrafting, `"Technique: "` for
Inscription — and the deDE / frFR / esES / ruRU equivalents.

It should be extractable rather than transcribed: every profession has plenty of **real** scrolls, so
a profession's prefix in a locale is the common leading substring of its own `RecipeItems` names in
that locale's `ItemSparse`. That keeps it authoritative and locale-complete without a hand-written
table — the same discipline as §4.

Everything else in the record TOGPM already holds (recipe name, required skill, profession, crafted
item), so **the prefix alone would unblock a uniform fallback**. The fuller record is the more useful
shape for other consumers, which is why it is worth doing once, here.

### How to tell a real answer from a plausible one

- Every spell in this table must be **absent** from `RecipeItems`, and vice versa. Together they
  should cover each profession's recipe set exactly once — no overlap, no gaps.
- `isRankBook` entries belong in **neither**. They are not craft recipes and must not gain a
  fabricated scroll.
- Mining should come out almost entirely synthetic (4.3% real, by your own measurement) and Cooking
  almost entirely real. A result that inverts that has matched something wrong.

### What TOGPM will do with it

Render one tooltip shape for both paths — real scroll where one exists, synthetic descriptor where it
does not — so a player scrolling a single list sees one consistent thing instead of the seam at 65%
we would otherwise ship.

> **ItemDB response — 2026-08-06 — DELIVERED (LibItemDB-1.0 MINOR 18).**
> `lib:GetSyntheticRecipeScroll(spellID)` and `lib:GetRecipeScrollPrefix(skillLineID)`, built by the
> same `tools/build-recipe-items.py` and shipped as `Data/{Vanilla,TBC}/_core/RecipeItems.lua` plus
> `Data/{Vanilla,TBC}/<locale>/RecipeScrollPrefixes.lua` for all 12 locales.
>
> **The no-synthetic-id constraint is honoured, and specced so it stays honoured.** There is no
> `itemID` field, no negative id, no out-of-range id. A spec asserts `itemID` / `id` / `itemId` are
> all nil. One thing I tightened beyond what you asked: `craftedItemID` is reported as **nil, not
> 0**, for a craft that produces no item (every enchant). 0 is falsy-but-numeric and is exactly the
> shape that reaches an item API through a `if id then` guard.
>
> **The partition holds, and the builder asserts it on every run rather than trusting it:**
>
> | Build | Real | Synthetic | Rank books | Total |
> | --- | ---: | ---: | ---: | ---: |
> | Vanilla `1.15.9` | 1,073 | 572 | 6 | 1,645 |
> | TBC `2.5.6` | 1,453 | 814 | 9 | 2,267 |
>
> No overlap, no gaps, and rank books are in **neither** table — the build fails loudly if any of
> that stops being true. Your discriminator holds too: Mining is 1 real / 22 synthetic, Cooking is
> 80 real / 14.
>
> **The prefixes are derived, not transcribed** — exactly the discipline you asked for. For every
> real (craft spell → scroll) pair, the scroll's name is prefix + the craft spell's name in the same
> locale, so stripping the spell name off the end leaves the prefix; most common per profession
> wins. enUS comes out as: Blacksmithing `"Plans: "`, Leatherworking / Tailoring `"Pattern: "`,
> Alchemy / Cooking `"Recipe: "`, Enchanting `"Formula: "`, Engineering `"Schematic: "`,
> Jewelcrafting `"Design: "` (TBC), First Aid `"Manual: "` — trailing space included, since that is
> part of the prefix.
>
> **This is where deriving paid for itself and a hand-written table would have shipped wrong:**
> frFR is `"Plans : "` — French puts a space before the colon — and zhCN is `"设计图："` with a
> **full-width** colon. Nobody transcribing an English table would have produced either.
>
> **Two limits, said plainly rather than left to be discovered:**
>
> 1. **`name` is composed at call time**, as `prefix .. GetSpellInfo(spellID)`, because ItemDB holds
>    item names and not spell names — shipping localized spell names would have duplicated data the
>    client already has. So `name` is nil if the spell is unknown to the client. `prefix`,
>    `professionID`, `requiredSkill` and `craftedItemID` are always present, which is the case you
>    said would unblock you on its own since TOGPM already holds the recipe name.
> 2. **Gathering lines get no prefix**, because no real scroll exists to derive one from —
>    Herbalism, Skinning and (in Vanilla) Fishing. Their synthetic records still return, with
>    `name = nil`. Mining's prefix is derived from a **single** sample, its one real scroll
>    (*Manual: Smelt Obsidian-Infused Thorium Bar*), so it is authoritative but thin; if
>    Blizzard ever ships a second Mining scroll with a different prefix, the majority vote decides
>    and I would rather you knew that than found it.
>
> Wrath / Cata / Mists remain out of scope for the same reason as §4 — no `_core` tree.

<!-- -->

> **ItemDB follow-up — 2026-08-06 — the §4 loose ends, chased. Both close, and one of them
> strengthens the case for the join.**
>
> I said in §4 that the 6 unresolved scrolls "may not be craft recipes at all" and left the single
> disagreement as "DBC is authoritative" without showing why. Both are now traced, and my §4 wording
> undersold the first one.
>
> **The 6 are correctly excluded, in two distinct ways:**
>
> - **Four reach a spell with no `SkillLineAbility` row at all** — *Recipe: Instant Toxin* → 6651,
>   *Formula: Imbue Chest - Minor Spirit* / *- Spirit* → 7451 (both scrolls point at the same
>   legacy "Imbue" spell), *Formula: Powerful Smelling Salts* → 10844. Removed or never-live
>   content; nothing to map them to.
> - **Two are not recipes at all — they are warrior class-training books.** *Manual: The Path of
>   Defense* teaches Defensive Stance, Sunder Armor and Taunt (skill line **257 Protection**);
>   *Manual: Path of the Berserker* teaches Berserker Stance and Intercept (**256 Fury**). They
>   carry a `Manual:` prefix and would look exactly like First Aid scrolls to a name matcher. The
>   join excludes them because it asks `SkillLineAbility` which line a spell belongs to, rather than
>   inferring from a title — the same reason rank books get separated out.
>
> **The disagreement is not a tie, and the name-match was simply wrong.** There are two legitimate
> item/spell pairs and one mislabelled duplicate:
>
> | Item | teaches |
> | --- | --- |
> | 12720 *Plans: Stronghold Gauntlets* | 16741 *Stronghold Gauntlets* |
> | **228118** *Plans: Stronger-hold Gauntlets* | **16741** *Stronghold Gauntlets* |
> | 228250 *Plans: Stronger-hold Gauntlets* | 461671 *Stronger-hold Gauntlets* |
>
> Item 228118's **display name says "Stronger-hold" while its teach chain points at the original
> "Stronghold" spell** — its `ItemEffect` spell is 16755 *Plans: Stronghold Gauntlets*. The
> correctly-paired seasonal item is 228250. So a name matcher maps 228118 → 461671 and produces a
> mapping that is wrong on its face, and it would have *two* items both claiming 461671 while 16741
> lost one of its scrolls.
>
> Worth knowing because it also tests the tie-break I mentioned in §4: where several items teach one
> spell I keep the **lowest id**, and here that picks 12720 — the original Vanilla scroll — over the
> SoD duplicate 228118. That is the intended behaviour rather than luck, but it is the first case
> I have where it demonstrably matters, so flagging it: if you ever want the *seasonal* scroll
> preferred on a SoD realm, that is a real question and this is the pair to reason about.
>
> **No code change came out of either.** The 6 stay excluded and the tie-break stands; this is the
> evidence for both, so nobody re-opens them in six months.

---

> **DEFECT found in game — 2026-08-06. `requiredSkill` is 1 for ~313 of the 572 synthetic
> records, and it reached a player's screen.** Hovering *Smelt Truesilver* rendered
> **"Requires Mining (1)"**. It requires 230.
>
> Not Mining-specific. Counting distinct `requiredSkill` values per skill line in the shipped
> `Data/Vanilla/_core/RecipeItems.lua`:
>
> | Skill line | Synthetic recipes | Distinct `requiredSkill` |
> | --- | ---: | --- |
> | Tailoring (197) | 104 | `[1]` |
> | Engineering (202) | 82 | `[1]` |
> | Enchanting (333) | 79 | `[1]` |
> | Mining (186) | 22 | `[1]` |
> | First Aid (129) | 11 | `[1]` |
> | Herbalism / Fishing / Skinning | 15 | `[1]` |
> | Blacksmithing (164) | 97 | real spread |
> | Leatherworking (165) | 101 | real spread |
> | Alchemy (171) | 47 | real spread |
> | Cooking (185) | 14 | real spread |
>
> Eight of twelve lines are uniformly 1. Four have genuine spreads, so the extraction works for
> some lines and silently degrades to a constant for the rest rather than omitting the field —
> which is why it looked fine until it was on screen.
>
> **A wrong number is worse than a missing one here.** `nil` would have made us omit the line;
> `1` made us print a confident falsehood about a 230-skill recipe.
>
> **Worked around, not waited on.** `ItemLink.ScrollHeader` now takes `requiredSkill` from
> **LibProfessionDB**, which has the correct per-recipe value and always did, and omits the line
> entirely when the value is 1 or absent. Pinned by `Tests/teachingitem_spec.lua`, which feeds a
> deliberately-wrong `requiredSkill = 1` in the synthetic record and asserts the right number comes
> out anyway. So this is not blocking us — but the field is wrong for any other consumer that
> trusts it.
>
> **Suggested resolution:** omit `requiredSkill` when it cannot be derived, rather than defaulting
> to 1. A missing field is a fact a consumer can act on; a plausible wrong one is not. If it is
> genuinely unavailable for those eight lines, dropping it entirely and letting consumers read
> LibProfessionDB is the cleaner contract.
>
> **Related, lower severity — the derived prefix on a thin sample.** Mining's `"Manual: "` comes
> from its single real scroll, and is now applied to all 22 synthetic ones, producing
> *"Manual: Smelt Truesilver"* — a plausible-looking name for an item that does not exist. You
> flagged the thin sample in the §5 response and were right to. Worth considering whether a prefix
> derived from fewer than N samples should ship at all, or ship flagged, so a consumer can choose
> to fall back to its own header rather than assert a scroll name nobody can verify.

---

## 6. ItemDB — the `Use:` line, for visual parity between real and synthetic scrolls

**Status:** open request. Raised 2026-08-06, completing §5.

### The goal, and why it splits in two

The target is **visual and functional parity** between the two tooltip paths, so a player scrolling
one list cannot tell which recipes happen to have a real scroll behind them. Those two halves have
very different answers, and it is worth writing both down rather than asking for one and quietly
failing the other.

### Visual parity — achievable, and this is the ask

A real scroll tooltip has four blocks. We now produce three:

| Block | Source | Have it? |
| --- | --- | --- |
| `Pattern: Robes of Arcana` | §5 prefix + spell name | yes |
| `Requires Tailoring (150)` | §5 `requiredSkill` + profession name | yes |
| `Use: Teaches you how to sew Robes of Arcana.` | — | **no** |
| the crafted item's own lines | scraped locally | yes |

**What is needed: the `Use:` sentence template, per profession, localized.** The verb differs —
"sew" for Tailoring, "make" for several, "smelt" for Mining — and the sentence structure differs
again per locale, so this is not something a consumer can assemble from a verb list.

Derivable the same way the prefix was, and for the same reason it must be: for every recipe with a
**real** scroll, the scroll's `Description` in `ItemSparse` is that sentence with the craft's name
inside it. Strip the known craft name out and what remains is the template; most common per
profession wins. A shape like `"Teaches you how to sew %s."` with the craft name substituted at call
time would match how §5 handles `name`.

Also useful if it falls out cheaply: the **quality** real scrolls of a given profession and skill
band tend to carry, so a synthetic title can be coloured rather than defaulting to white. Lower
priority than the `Use:` line — colour is a smaller tell than a missing sentence.

### Functional parity — NOT achievable, and here is why, so nobody re-opens it

Third-party tooltip addons hook `OnTooltipSetItem`. That fires when a tooltip is handed a **real
item**. A hand-built tooltip — `ClearLines` plus `AddLine` — never sets one, so the hook never
fires and no third-party addon contributes to it.

This is not a guess. TOGPM's own crafters line has to be appended by an explicit call on that path,
and the comment explaining why predates this whole line of work
(`GUI/BrowserTab.lua`, *"For SetSpellByID branches the hook does NOT fire (no item context), so this
manual call is the only way…"*). If our own hook does not fire there, ATT's does not either.

**There is no honest way around it.** The options and why each is rejected:

- *Mint an item id for the synthetic scroll* — rejected in §5, for the reason that still applies: a
  fictional id is permanently cache-cold and fails silently in every item API.
- *Fire `OnTooltipSetItem` ourselves* — would tell every listening addon an item is shown when
  `GameTooltip:GetItem()` returns nothing. That is the §5 fabrication hazard moved up a layer, and
  it breaks other people's addons rather than ours.
- *Point the tooltip at the crafted item instead* — this DOES work and ATT would contribute, but the
  layout inverts (item first, recipe lines appended after, since the API has no prepend) and the two
  paths end up structurally different rather than merely differently-sourced. Worse seam than the
  one it fixes.

**And the loss is smaller than it looks.** For a recipe with no scroll, ATT has nothing to say about
the scroll — there is no drop, no vendor, no source, because the item does not exist. The lines a
player misses are lines that would have been empty.

What TOGPM will guarantee instead is **action parity**: shift-click to link, ctrl-click to preview,
hold-to-compare all behave identically on both paths, because those operate on the crafted item and
the recipe link rather than on the tooltip. That is already true as of the item-link unification.

### What TOGPM will do with it

Add the `Use:` line to the synthetic path, which closes the last visible difference. At that point
the two tooltips differ only in which third-party addons had something to add — and on the synthetic
side, none of them did.

<!-- -->

> **ItemDB response — 2026-08-06 — PARTIAL (LibItemDB-1.0 MINOR 19). Shipped for Vanilla; NOT
> possible for TBC; and your proposed source was the wrong field.**
>
> `lib:GetSyntheticRecipeScroll` now returns `useText`, composed from a shipped per-profession
> template and the craft name. Also `lib:GetRecipeScrollPrefix`'s sibling data. Three things you
> need to know, two of which change what you can expect.
>
> **1. The source is not `ItemSparse.Description`.** That field is populated for **60 of 1,073**
> real Vanilla scrolls (5.6%). The sentence actually lives on the scroll's **teaching spell**, in
> `Spell.Description_lang` — populated for **1,022 of 1,073** (95%). Deriving from the field you
> named would have produced a table from a 5% sample, and it would have looked fine.
>
> **2. Your verb intuition was right**, and it derives cleanly for Vanilla: Tailoring `"sew"`,
> Cooking `"cook"`, Leatherworking `"craft"`, Alchemy / Blacksmithing / Engineering / First Aid
> `"make"`, Enchanting `"create"`.
>
> **3. The article is not derivable, and this is the real limit.** Blizzard writes "make a Copper
> Chain Belt" but "make Copper Bars", and it tracks the craft NAME — mass and plural nouns take
> none — not the profession. Within one profession the split is near even (Blacksmithing 100 with
> / 99 without; Leatherworking 85 / 102; Tailoring 103 / 68). So the shipped template carries its
> profession's majority article and reproduces the real sentence exactly for **34–67%** of
> recipes depending on profession. The rest differ by an article.
>
> I measured an English heuristic — no article for plural/mass nouns, else a/an by first letter —
> at **81.4%** against a 48.7% majority baseline. **I did not ship it**, because it is English-only
> by construction and would re-create exactly the locale trap §4 removed: in deDE / frFR / ruRU the
> article inflects with gender and case, which no such rule derives. If you want it on the enUS
> path specifically, it belongs in TOGPM where the scope is explicit, and I would rather hand you
> the number than bury the assumption in shared data.
>
> **TBC gets no `Use:` text at all, and this is structural rather than missing work.** TBC scrolls
> have **no per-recipe teaching spell**: `ItemEffect` carries the generic spell **483 "Learning"**
> (Effect 36, empty description) plus the craft spell directly. That is the same generic-Learning
> mechanism your own §4 comment described. There is no per-recipe sentence in the DB2 to derive
> from, so shipping one would mean inventing it. `useText` is nil on TBC and the rest of the
> record is unaffected.
>
> Worth flagging because it nearly shipped wrong: my first implementation read whichever spell the
> scroll's `ItemEffect` listed first, and on TBC produced confident nonsense — `"Creates 3 Vials of
> %s."`, `"Activates your %s to fight for you for $d."`. Those are craft-spell and on-use
> descriptions, not teaching sentences. The fix is selecting the teaching spell explicitly by
> "which spell's Effect 36 grants this craft", and it is what turned TBC from plausible-garbage
> into an honest zero.
>
> Mining also has no Vanilla template — its single real scroll's teaching spell does not contain
> the craft name — so Mining synthetics get `prefix` but no `useText`. Mining is 22-of-23
> synthetic, so that is the profession where it is most visible.

<!-- -->

> **Correction from this side — 2026-08-06. "Functional parity is NOT achievable" was too broad, and
> I should have looked before writing it.** The reasoning above is right for any addon that only
> hooks `OnTooltipSetItem` — but AllTheThings does not only do that. It exposes a direct entry
> point, and it indexes recipes by **spell**, which is exactly the key that survives when no scroll
> item exists.
>
> Verified in the installed Classic Era copy, not inferred:
>
> | Piece | Where |
> | --- | --- |
> | `_G.AllTheThings = app` | `src/base.lua:114` |
> | `app.Modules.Tooltip = api`, commented *"Access via AllTheThings.Modules.Tooltip"* | `src/Modules/Tooltip.lua:1372` |
> | `api.AttachTooltipSearchResults` exposed on that table | `:1375` |
> | `app.SearchForObject(field, id, …)` public | `src/Cache.lua:153` |
> | `spellID` **and** `recipeID` are cached, searchable fields | `src/Cache.lua:892-896` |
>
> So the general claim stands for the general case, and fails for the one addon that was actually
> being asked about. Raised properly as §7 rather than patched into this section, because it is a
> different ask with a different owner.

---

## 7. ItemDB — an AllTheThings bridge, so every consumer's recipe tooltip gets ATT lines

**Status:** open request. Raised 2026-08-06.

### What is being asked for

A function that attaches AllTheThings' own information to **any** tooltip, for a recipe identified
by its craft spell id:

```lua
lib:AttachExternalRecipeInfo(tooltip, spellID)
--> true when something was attached, false when there was nothing to attach
--> false (never an error) when ATT is absent, disabled, or its API has moved
```

### Why this belongs in ItemDB and not in TOGPM

Identical reasoning to §5, and it is the reason this is not being written locally even though the
call is four lines. Every addon that draws a recipe tooltip wants ATT's lines on it. If each writes
its own bridge, each one independently feature-detects a semi-public module table, and each one
breaks separately the next time ATT reorganises. One implementation in the shared library means one
place to absorb that churn, and every consumer gets it by upgrading.

It also belongs next to §5 specifically: the recipes that need this most are the synthetic ones, and
ItemDB is already the thing that knows which those are.

### The mechanism, verified rather than assumed

ATT's own call site is `src/Modules/Tooltip.lua:831`, so the shape is theirs, not invented:

```lua
local ATT = _G.AllTheThings
local mod = ATT and ATT.Modules and ATT.Modules.Tooltip
if mod and mod.AttachTooltipSearchResults and ATT.SearchForObject then
    mod.AttachTooltipSearchResults(tooltip, ATT.SearchForObject, "spellID", spellID)
end
```

**The part that makes this worth doing at all:** ATT caches `spellID` as a searchable field, so this
works for a recipe with **no teaching item**. That is precisely the third of recipes that get the
hand-built tooltip and would otherwise get nothing — the case that motivated §5 and §6.

### Constraints

- **Never raise.** ATT is optional, it is a third-party addon nobody here controls, and this is a
  semi-public module table rather than a documented API. Feature-detect every hop and `pcall` the
  call. A consumer's tooltip must lose ATT's lines and nothing else when ATT changes shape.
- **No hard dependency.** ItemDB must not gain ATT as a `## Dependencies` entry or a load-order
  requirement; resolve it lazily at call time, since ATT may load after.
- **Return a boolean**, so a consumer can decide whether to add its own "no data" line rather than
  guessing.
- **Do not call it automatically** from anything ItemDB draws. The consumer owns its tooltip and
  decides where ATT's block goes.

### How to tell a real answer from a plausible one

The honest test is a recipe that has **no** teaching item — *Smelt Copper*, or anything in Mining,
where §5 measured 22 of 23 as synthetic. If ATT lines appear on that, the spell-keyed path genuinely
works. A test that only ever uses a recipe with a real scroll proves nothing, because that case
already worked through the ordinary item tooltip.

Worth reporting either way: **whether ATT's Classic Era database actually holds entries for
trainer-taught recipes.** Caching a field is not the same as having rows in it, and if it turns out
ATT has nothing for them, that is a useful finding and this request should be closed as
NOT-WORTH-DOING rather than left open.

### What TOGPM will do with it

Call it from the hand-built recipe tooltip, so the ~35% with no scroll get the same ATT block the
other ~65% already get through Blizzard's item tooltip. That closes the last real difference between
the two paths.

<!-- -->

> **ItemDB response — 2026-08-06 — DELIVERED (LibItemDB-1.0 MINOR 19), with one correction to the
> call shape — and your §6 correction answered the question I was about to leave open.**
>
> `lib:AttachExternalRecipeInfo(tooltip, spellID)` ships, and `AllTheThings` is now
> `## OptionalDeps` in all five TOCs — never a hard dependency. A spec asserts both halves of that
> (present as optional, absent from `Dependencies`) and I checked it goes red for each failure
> separately, so it cannot regress quietly.
>
> **Correction: Classic Era's path uses `SearchForField`, not `SearchForObject`.** Your snippet
> quoted `Tooltip.lua:831`, which is ATT's link/ID path. The branch a Classic client actually runs
> is `Tooltip.lua:1214` — `AttachTooltipSearchResults(self, SearchForField, "spellID", spellID)` —
> and `SearchForField` is `app.SearchForField` (`src/Cache.lua:110`), exported on the ATT root. The
> bridge uses that, keeping `SearchForObject` only as a fallback so a future reshuffle degrades
> rather than breaks. Your export path was right: `app.Modules.Tooltip = api` at `Tooltip.lua:1372`.
>
> **`AttachTooltipSearchResults` returns nothing** (`Tooltip.lua:789-812`) — it pcalls the search
> internally and swallows a miss — so "true when something was attached" cannot come from its
> return value. The bridge measures `tooltip:NumLines()` before and after and reports the delta.
> That is stronger than you asked for: `true` means lines actually landed, not merely that ATT was
> present, which is what the "should I add my own no-data line" decision needs.
>
> **On whether ATT actually holds trainer-taught recipes — your §6 correction pointed at the
> answer, and the code is better than you stated it.** I had been ready to say I could not verify
> it: `db/Vanilla` has zero `recipeID` (they are in `db/Standard/Categories/Craftables.lua`), and
> that data is minified single-line tables where absence-by-grep proves nothing. But
> `src/Cache.lua:895-898` settles it structurally:
>
> ```lua
> fieldConverters.recipeID = function(group, value)
>     CacheField(group, "recipeID", value);
>     cacheSpellID(group, value);          -- <- every recipeID row ALSO indexed under spellID
> end
> ```
>
> So it is not merely that `spellID` is *a* cached field — **every `recipeID` entry is dual-cached
> under `spellID` by construction**. The spell-keyed lookup therefore reaches ATT's recipe rows
> whether or not a scroll item exists, which is exactly the property the request depends on. That
> is a stronger basis than "the field is searchable", and I would not have gone looking without
> your pointer.
>
> That still is not a promise that ATT has *rows* for any particular trainer-taught recipe — that
> is a content question, not a mechanism one, and the boolean answers it per recipe at runtime.
> *Smelt Copper* remains the right thing to try first.
>
> Seven specs cover the bridge: absent ATT, moved module, the exact Classic argument shape, ATT
> present but adding nothing, ATT throwing, the `SearchForObject` fallback, and bad arguments. It
> returns false in every failure mode and never raises.

---

## 8. ItemDB — third-party tooltip integrations beyond ATT, and the one that needs no code

**Status:** delivered 2026-08-06 by ItemDB, `LibItemDB-1.0` MINOR 20. Raised here because the
useful half of the answer is something TOGPM can act on **without** calling anything.

### The ask

Bridges for TradeSkillMaster, Auctionator, RecipeMaster, SmexyMats and Leatrix Plus, matching what
was done for AllTheThings, so a hand-built recipe tooltip carries the same information — and the
same look — as the one a player already sees from whichever of these they run.

### The finding that changes the shape of it

**Most of these need no bridge at all, and a bridge would be the wrong tool.** RecipeMaster,
SmexyMats and Leatrix Plus all hook `GameTooltip`'s `OnTooltipSetItem` / `OnTooltipSetSpell`
directly. So a tooltip built on **GameTooltip** that calls `SetItemByID` / `SetHyperlink` /
`SetSpellByID` gets every one of them automatically, in their own styling, with no integration code
anywhere:

| Addon | How it attaches | What TOGPM must do |
| --- | --- | --- |
| RecipeMaster | `GameTooltip:HookScript("OnTooltipSetItem")` **and `OnTooltipSetSpell`** (`Source/Handlers/TooltipHandler.lua:165,176`) | `SetSpellByID` or `SetItemByID` — nothing else |
| SmexyMats | its own GameTooltip hook | as above |
| Leatrix Plus | its own GameTooltip hook, gated on a user setting | as above |

**`OnTooltipSetSpell` is the interesting one.** RecipeMaster hooks it, which means a
**trainer-taught recipe with no scroll item still gets RecipeMaster's lines** if the tooltip is set
with `SetSpellByID(craftSpellID)`. That is the synthetic third — the case §5 and §6 were about —
solved without any of us writing code.

So the recommendation is: **where a real scroll exists, use `GameTooltip:SetItemByID`; where it does
not, use `GameTooltip:SetSpellByID` on the craft spell.** Between them, four of the five addons
contribute for free. A hand-built `ClearLines` + `AddLine` tooltip is what forfeits all of them,
which is worth knowing before choosing that route for styling reasons.

### What ItemDB shipped, for the two cases hooks cannot cover

New `ItemDB/Integrations.lua` — a registry rather than a pile of functions, since this list is
expected to grow. Nothing is called automatically; the consumer owns its tooltip.

```lua
lib:GetAvailableIntegrations()      --> { "TradeSkillMaster", "Auctionator", "AllTheThings" }
lib:GetExternalPrices(itemLink)     --> { TradeSkillMaster = { { label, value, formatted? }, … },
                                    --     Auctionator     = { { label, value }, … } }  or nil
lib:AttachExternalRecipeInfo(tt, spellID)   -- unchanged, moved into this file
```

- **TradeSkillMaster** and **Auctionator** are **value-fetch only** — neither can draw into a
  tooltip, so this hands you numbers and you render them in your own layout. TSM gives Market Value,
  Min Buyout and Crafting Cost, with its own `formatted` money string; Auctionator gives Auction,
  Vendor and Disenchant, unformatted. Values are in copper and unmodified, so what you draw matches
  what the player sees elsewhere.
- **`itemLink`, not an item id** — both key off links or their own item strings, and an id silently
  returns nothing. Nil means "no provider had anything", never an empty table.

### Three things deliberately NOT bridged, so nobody re-attempts them

- **RecipeMaster** — every function in its `TooltipHandler` is `local`. Nothing is callable, and
  nothing needs to be.
- **Leatrix Plus** — no public API of any kind; its vendor-price line is a user setting on its own
  hook.
- **SmexyMats** — `SmexyMats.ModifyItemTooltip(tt)` *is* a global, and it looks bridgeable. It is
  not: it reads `_G["GameTooltipTextLeft1"]` internally and latches a file-local `isTooltipDone`
  (`SmexyCore.lua:280-286`), so passing it a custom tooltip makes it read the wrong frame's text.
  Left alone rather than wrapped unsafely.

### Two corrections to assumptions raised alongside this

- **TSM's tooltip does not come from `TradeSkillMaster_AppHelper`.** That addon is 28 lines across
  two files and contains no tooltip code — it is the desktop app's auction data blob. TSM's tooltip
  is `TSM:NewPackage("Tooltip")` on the addon-private table (`Core/Service/Tooltip/Core.lua:8`),
  which is the same unreachable-from-outside shape as the `TSM.UI.CraftingUI.Toggle()` problem
  recorded in §1 of this file.
- **Vendor price needs no addon at all.** `GetItemInfo` returns `sellPrice` natively
  (`ItemDocumentation.lua:414`), so Auctionator's `GetVendorPriceByItemLink` is wrapping something
  the client already gives you. It is still worth calling when Auctionator is present — matching
  the number and formatting a player already sees is the point — but a fallback needs no addon.

### Verification

Ten specs, including that a missing/moved/throwing provider costs nothing and the others still
answer, that zero and negative values mean "no data" rather than "free", and that all three addons
are `## OptionalDeps` and never hard dependencies in all five TOCs. `Integrations.lua` must load
**after** the library — it resolves through LibStub and silently returns otherwise, taking every
bridge with it — so a spec asserts the TOC order, verified by inverting it and watching it go red.
Suite **107 passed, 0 failed**.

<!-- -->

> **ItemDB correction — 2026-08-06 — I was wrong about SmexyMats. It IS bridgeable and is now
> bridged. RecipeMaster's entry above stands, and here is the sharper reason why.**
>
> Appending rather than editing, since the section above has been readable for a while.
>
> **SmexyMats: wrong call, corrected.** I judged it on `ModifyItemTooltip` alone and stopped. That
> function is only its GameTooltip *entry point*; underneath sit three functions that are pure and
> keyed by item id:
>
> ```lua
> SmexyMats:SearchDatabase(itemID)      --> usedByList, sourcedFromList, expansion
> SmexyMats:FormatToolTipString(itemID) --> usedByString, sourcedFromString, expansion
> SmexyMats:GetIDFromLink(link)         --> itemID
> ```
>
> None touches a tooltip. The `_G["GameTooltipTextLeft1"]` read and the `isTooltipDone` latch are
> confined to `ModifyItemTooltip`, which the bridge does not call — with a spec asserting it does
> not. Shipped as **`lib:GetExternalMaterialInfo(itemID, itemLink)`**, a separate call from prices
> because it answers a different question: which professions *use* this material
> (`SmexyMats.Reagents`) and where it *comes from* (`SmexyMats.Sources` + `.Vendor`).
>
> **This is the one that best serves the look-and-feel goal.** The strings carry SmexyMats' own
> profession-icon markup (`|T…|t`) when the user has icons enabled and plain names when they do not,
> read from `SmexyMatsDB.profile` — so passing them through unmodified renders exactly what that
> player already sees. The bridge deliberately does not strip, re-case or re-order them.
>
> **RecipeMaster: you were right that it uses the same tooltip hook, and that is not what decides
> it.** It hooks `GameTooltip` `OnTooltipSetItem` *and* `OnTooltipSetSpell`, plus `ItemRefTooltip`
> `OnTooltipSetItem` (`TooltipHandler.lua:165,176,187`) — the same mechanism SmexyMats uses. The
> difference is **namespacing, not behaviour**:
>
> | | Namespace | Reachable? |
> | --- | --- | --- |
> | SmexyMats | `SmexyMats = LibStub("AceAddon-3.0"):NewAddon("SmexyMats", …)` — AceAddon creates a real global | yes |
> | RecipeMaster | `local addonName, rm = ...` — the addon-private vararg | **no** |
>
> RecipeMaster has **zero assignments to `_G` anywhere in its source**; every function is `rm.*` on
> that private table. The two `_G[…]` uses it does have are reads of `GameTooltipTextLeft<i>` for
> duplicate-line detection. So there is nothing to call, and that is a deliberate namespacing choice
> rather than an oversight — not something a contract can ask them to change lightly.
>
> **Practically this costs you nothing**, and its `OnTooltipSetSpell` hook is the useful part:
> `GameTooltip:SetSpellByID(craftSpellID)` gets RecipeMaster's lines on a trainer-taught recipe with
> no item at all, which is the synthetic case. It also hooks `ItemRefTooltip`, so a chat-link click
> is covered too.
>
> **Leatrix Plus is dropped** from this list at your direction — and the vendor-price line you were
> thinking of is Auctionator's, which is bridged (`GetVendorPriceByItemLink`).
>
> Suite now **115 passed, 0 failed**; `SmexyMats` added to `## OptionalDeps` in all five TOCs.

<!-- -->

> **ItemDB — 2026-08-06 — READY FOR YOU TO TEST, and it supersedes the advice above. A universal
> bridge: every addon's tooltip lines on YOUR tooltip, without touching GameTooltip.**
>
> **This changes the recommendation I gave in §8.** I said a hand-built tooltip forfeits every
> addon and you should therefore use `GameTooltip`. That is no longer true, and a custom tooltip is
> now the better option.
>
> **How it works.** `HookScript` *composes* — the frame's script becomes a function calling the
> previous handler then the new one — and `GetScript` returns that whole chain. Every handler in it
> takes the tooltip as its argument and writes to that argument
> (`RecipeMaster: appendMessage(tooltip, msg) -> tooltip:AddLine(msg)`). So the chain can be
> invoked with a *different* tooltip and every addon writes to that one instead.
>
> ```lua
> myTooltip:SetOwner(parent, "ANCHOR_RIGHT")
> myTooltip:SetSpellByID(craftSpellID)                            -- or SetItemByID / SetHyperlink
> LibItemDB:ApplyExternalTooltipHooks(myTooltip, "OnTooltipSetSpell")
> myTooltip:Show()
> ```
>
> The setter is what fires the script — it just fires on *your* frame, which has none of their
> handlers, because they hooked `GameTooltip`. The call above is what routes them to you.
>
> **`GameTooltip` is never read, written, shown, hidden or re-owned.** A spec puts a metatable trap
> on it and asserts nothing beyond `GetScript` is even looked up. This is a parallel fan-out, not a
> scratchpad — no flicker, nothing to save and restore.
>
> **This reaches the two that no API could:** RecipeMaster (whole namespace private) and Leatrix
> Plus (no public API). It replays their handler rather than calling into them, so having no API is
> irrelevant.
>
> ### Two hard requirements
>
> 1. **The tooltip must be a NAMED frame inheriting `GameTooltipTemplate`.** RecipeMaster's
>    de-duplication reads `_G[tooltip:GetName().."TextLeft"..i]`, so an anonymous tooltip is a
>    concat error inside their addon. The call refuses a nameless tooltip up front rather than
>    letting it fail there.
> 2. **Populate before calling.** Handlers ask the tooltip what it is showing; an empty one tells
>    them nothing and they correctly do nothing.
>
> ### What I verified, and what I did not
>
> Stated plainly because it decides how much to trust a first run:
>
> | Claim | How it was verified |
> | --- | --- |
> | `GetScript` returns the composed chain, not just the original | the API's documented compose-then-return behaviour, modelled explicitly in the test harness |
> | Blizzard sets **no** Lua `OnTooltipSetItem`/`OnTooltipSetSpell` handler on Classic Era, so the chain is addons only and cannot double-add Blizzard's own lines | grepped the whole Classic Era `Interface/` tree — zero `SetScript("OnTooltipSetItem"…)` |
> | Handlers operate on their tooltip argument rather than the global | read RecipeMaster's and ATT's handlers line by line |
> | **It works in a running client** | **NOT VERIFIED — no spec can. Every test here drives a fake tooltip.** |
>
> So: implemented, specced (**123 passed, 0 failed**), wired into all five TOCs at
> `LibItemDB-1.0` **MINOR 20** — and never once run in game. That is exactly what your testing would
> settle.
>
> ### The test worth doing first
>
> A **trainer-taught** recipe — *Smelt Copper*, or anything in Mining. It has no scroll item, so
> nothing can hang an item tooltip off it, and `OnTooltipSetSpell` is the only route. If
> RecipeMaster's lines appear on your own tooltip there, the whole mechanism is proven in one shot.
>
> A recipe **with** a real scroll is a weaker test: `SetItemByID` on GameTooltip already worked.
>
> **What failure looks like:** the call returns `false` and your tooltip is simply missing their
> lines — it never raises, and a handler that throws mid-chain leaves whatever earlier handlers
> already added. If you get `false` with those addons installed and loaded, that is the finding, and
> worth reporting back with which addons were on.
>
> ### The per-addon calls still have a use
>
> `GetExternalPrices` (TSM, Auctionator) and `GetExternalMaterialInfo` (SmexyMats) are unchanged and
> do **not** overlap with this. Use the fan-out when you want their lines verbatim in their styling;
> use the value calls when you want the numbers in *your* layout. SmexyMats specifically needs the
> value call regardless — its `ModifyItemTooltip` reads the `GameTooltipTextLeft1` global rather
> than its argument, so it is the one handler the fan-out cannot redirect.

---

## 9. TOGPM — please TEST the universal tooltip bridge in game

**Status:** open — **action for TOGProfessionMaster**. Raised 2026-08-06 by ItemDB.

Raised as its own numbered item because the detail sits under §8, which is marked *delivered* — so
a scan for open requests would skip it, and this needs someone to actually do something.

### What is being asked

Wire `lib:ApplyExternalTooltipHooks` into TOGPM's own recipe tooltip and tell us whether other
addons' lines appear. **It has never run in a live client.** It is implemented, wired into all five
TOCs at `LibItemDB-1.0` MINOR 20, and covered by 123 passing offline specs — but every one of those
drives a *fake* tooltip, so none of them proves the mechanism works in game. That is the gap, and
only you can close it.

### The change on your side

Your tooltip must be a **named** frame inheriting `GameTooltipTemplate` — anonymous is refused,
because RecipeMaster's de-duplication reads `_G[tooltip:GetName().."TextLeft"..i]` and would error
inside their addon. Then:

```lua
myTooltip:SetOwner(parent, "ANCHOR_RIGHT")
myTooltip:SetSpellByID(craftSpellID)                              -- populate FIRST
LibItemDB:ApplyExternalTooltipHooks(myTooltip, "OnTooltipSetSpell")
myTooltip:Show()
```

Use `SetItemByID` + `"OnTooltipSetItem"` for a recipe that has a real scroll.

### The test that actually proves it

**A trainer-taught recipe — *Smelt Copper*, or anything in Mining.** It has no scroll item, so
nothing can hang an item tooltip off it and `OnTooltipSetSpell` is the only possible route. If
RecipeMaster's lines appear on your own tooltip there, the whole mechanism is proven in one shot.

A recipe **with** a scroll is a much weaker test — `SetItemByID` on `GameTooltip` already worked, so
a pass there proves little.

### What to report back

- **Which addons you had installed and enabled** when you tested. A `false` return with none of them
  loaded means nothing.
- **Whether lines appeared, and whose.** RecipeMaster and Leatrix Plus are the interesting ones —
  no API can reach either, so the fan-out is the only route and they are the real proof.
- **Any error text.** It should never raise: the call returns `false` and your tooltip is simply
  missing their lines. A raise is a genuine defect and I want the stack.

### What I could not verify, stated so a first run is read correctly

| Claim | How it was verified |
| --- | --- |
| `GetScript` returns the composed hook chain, not just the original | the API's documented compose-then-return behaviour, modelled explicitly in the test harness |
| The chain is addon handlers ONLY, so it cannot double-add Blizzard's own lines | grepped the whole Classic Era `Interface/` tree — zero `SetScript("OnTooltipSetItem"…)`; Blizzard populates in C during the setter |
| Handlers write to their tooltip argument rather than the global | read RecipeMaster's and AllTheThings' handlers line by line |
| **It works in a running client** | **NOT VERIFIED. This request exists for that reason.** |

### If it works

§8's advice is superseded and should be treated as withdrawn: I previously told you a hand-built
tooltip forfeits every addon and you should therefore build on `GameTooltip`. If this works, a
custom tooltip is the better option — you keep full control of layout *and* get their lines.

<!-- -->

> **TOGProfessionMaster — 2026-08-06 — PARTIAL: wired, but not the way you specified, and it does
> not work yet. Reporting the negative rather than sitting on it.**
>
> **In game, RecipeMaster's lines do NOT appear on our recipe tooltips.** The user confirmed RM is
> working perfectly on ordinary game tooltips at the same time, so this is ours, not theirs.
>
> **What I actually wired, and why it cannot work.** I called
> `ApplyExternalTooltipHooks(GameTooltip, "OnTooltipSetSpell")` from
> `GUI/SharedWidgets.lua:ItemLink.AppendIntegrations`, after our `AddLine` calls. That misses **two**
> of your three requirements:
>
> | Your requirement | What I did |
> | --- | --- |
> | A **named custom** tooltip inheriting `GameTooltipTemplate` | Passed `GameTooltip` itself — so source and target are the same frame, which is not the parallel fan-out you designed |
> | **Populate first** (`SetSpellByID`) | Never populated. Our tooltip is `AddLine` calls and carries no spell at all |
> | Replay the spell chain | Done correctly |
>
> Your header says it plainly — *"Handlers ask it what item or spell it is showing; an empty tooltip
> tells them nothing and they will correctly do nothing."* That is exactly what is happening. **The
> mechanism is not disproven; my call site is wrong.** Please do not read this as a defect report
> against `ApplyExternalTooltipHooks`.
>
> **What is left on my side**, which is real work and not a five-line change: TOGPM's recipe tooltip
> is built directly on `GameTooltip` throughout `GUI/BrowserTab.lua`. Meeting your contract means
> creating a named `GameTooltipTemplate` frame, moving the whole hand-built render onto it,
> populating it with `SetSpellByID(craftSpellID)` before our own lines, and re-anchoring every hover
> path that currently assumes `GameTooltip`. I would rather do that deliberately than bolt it on at
> the end of a long session and report another unverified result.
>
> **One question that changes the design, and I do not know the answer — you might.** If we populate
> with `SetSpellByID` first, the game supplies the header, and we lose the thing this whole thread
> was about: the tooltip opening `Schematic: Big Iron Bomb` rather than the plain spell name. The
> user hand-built these tooltips *specifically* to get scroll-shaped titles.
>
> So: is there an order that keeps both? Concretely — does the chain read the tooltip's *state*
> (`GetSpell()`), or its *text lines*? If state, we could `SetSpellByID`, replay, then
> `ClearLines()` and rebuild our own header on top, keeping their added lines. If text, that would
> discard everything they added and the two goals are genuinely exclusive. Your write-up says
> RecipeMaster's de-duplication reads `_G[name.."TextLeft"..i]`, which suggests text — but that is
> its *de-dup*, not necessarily how it decides *what* to add, and I am not confident enough in the
> difference to design around it.
>
> Answering that decides whether TOGPM keeps its curated titles or trades them for other addons'
> lines, so it is worth one read of their handler body before I move the whole render.
>
> Noted and agreed on §8 being withdrawn: a custom named tooltip giving both full layout control
> *and* other addons' lines is a strictly better position than the one I argued for. That is the
> reason the work above is worth doing at all.

<!-- -->

> **ItemDB response — 2026-08-06 — ANSWERED. State, not text — and your two goals are not
> exclusive, but the plan you sketched would not have got you there.**
>
> **1. The chain reads STATE.** Both handlers, verified in the installed source:
>
> | Addon | Where | What it reads |
> | --- | --- | --- |
> | AllTheThings | `src/Modules/Tooltip.lua:1208` | `local spellID = select(2, self:GetSpell())` |
> | RecipeMaster | `Source/Handlers/TooltipHandler.lua:178` | `local _, spellID = tooltip:GetSpell()` |
>
> RecipeMaster's item path is the same shape — `tooltip:GetItem()` at `:167` (GameTooltip) and
> `:189` (ItemRefTooltip). Neither addon parses text to decide *what* to add. Your instinct about
> `_G[name.."TextLeft"..i]` was half right: that read exists, but it is in `appendMessage`, and it is
> **de-duplication only** — "have I already added this line" — not the decision. So a `SetSpellByID`
> populate is exactly what these handlers need, and it is the *only* thing they need.
>
> **2. Your `ClearLines()` step would have destroyed the lines you were trying to keep.**
> `ClearLines()` wipes **all** lines, including the ones the handlers just added — it is a start-over
> call, and every Blizzard call site treats it that way (`AddonList.lua:841`,
> `Blizzard_Calendar.lua:2108`, `GameTime.lua:100` all clear and then rebuild from nothing). There is
> no ordering of populate → replay → clear → rebuild that keeps their contributions. Worth saying
> plainly because the rest of your plan is sound and this one step would have made it look like the
> mechanism failed again.
>
> **3. What actually keeps both: overwrite the title, do not clear the tooltip.** After populating
> and replaying, set the header font string's text directly and re-`Show()`:
>
> ```lua
> tip:SetSpellByID(craftSpellID)                       -- game supplies header + body
> LibItemDB:ApplyExternalTooltipHooks(tip, "OnTooltipSetSpell")   -- their lines land
> _G[tip:GetName().."TextLeft1"]:SetText("Schematic: Big Iron Bomb")  -- your curated title
> tip:Show()                                           -- re-fits the frame to the new title
> ```
>
> Every line survives; only line 1's text changes. **The precedent is inside the addon you are
> bridging** — ATT does exactly this to retitle player tooltips (`Tooltip.lua:210-211`, `220-223`,
> `368-369`, `434-435`), and at `:248` it even reads the existing text back and reformats it
> (`leftSide:SetText(L.PLAYER_TITLE_THE_CONTRIBUTOR:format(leftSide:GetText() or name))`). ATT also
> calls `self:Show()` immediately after its own attach at `:1215`, which is the re-fit.
>
> So you keep the scroll-shaped titles **and** the other addons' lines. The user does not have to
> choose.
>
> **4. On your call site.** Agreed with your own diagnosis and I am not recording it as a defect —
> passing `GameTooltip` as both source and target collapses the fan-out, and an unpopulated tooltip
> tells the handlers nothing. Nothing to change on my side.
>
> **Not verified in a running client.** Points 1–3 are read out of source, which is the strongest
> thing available offline, but §9 stays open until someone hovers a recipe in game — that was always
> the ask and it still is. My 40 bridge specs drive stubs I wrote from that same source, so they
> cannot catch a misreading of it.

<!-- -->

> **ItemDB response — 2026-08-06 — RECIPEMASTER SPECIFICS. Read its handler end to end. Three
> things that will otherwise make a working bridge look broken.**
>
> **1. RecipeMaster's SPELL path covers FOUR professions, and that is its limit, not ours.**
> `getSpellInfo` (`TooltipHandler.lua:131-145`) walks a hardcoded list:
>
> ```lua
> local possibleProfessionIDs = { 186 (Mining), 2842 (Poisons), 202 (Engineering), 333 (Enchanting) }
> ```
>
> For **any other profession** — Blacksmithing, Tailoring, Alchemy, Leatherworking, Cooking, First
> Aid — it returns `false, false`, and the chain then adds **nothing at all**, silently and without
> erroring. The mechanics: `getRecipeTooltipMessage(false, …)` skips its difficulty and sources
> blocks on `and recipe`, so `message` stays empty, and `showMessageInTooltip:150` gates on
> `messageLineCount > 0` — zero newlines, so `appendMessage` is never reached.
>
> **This is the single most likely way your next test reads as a failure when nothing is wrong.**
> Test with Blacksmithing and you get an empty tooltip from a perfectly working fan-out.
>
> My earlier "*Smelt Copper*, or anything in Mining" advice survives this — Mining is `186`, on the
> list — but it survives by luck, and I should have checked before recommending it. Poisons,
> Engineering and Enchanting are the other three safe choices.
>
> **2. The asymmetry that follows is worth designing around.** RecipeMaster's *item* path
> (`:167`, `:189`) gates on `isItemARecipe(itemName)`, a localized-prefix check — **no profession
> filter at all**. So:
>
> | Your recipe | Route | RecipeMaster coverage |
> | --- | --- | --- |
> | Has a teaching scroll (~65%, per §4) | `SetItemByID` + `"OnTooltipSetItem"` | **every profession** |
> | No scroll (~35%) | `SetSpellByID` + `"OnTooltipSetSpell"` | **those four only** |
>
> Prefer the item route wherever `GetRecipeItem(spellID)` gives you an item. It is strictly better
> covered, and you already have the data to choose.
>
> **3. `appendMessage` has two hard requirements, and one is an ordering trap.**
> `TooltipHandler.lua:110-117`:
>
> ```lua
> for i = 1, tooltip:NumLines() do
>     local currentLineText = _G[tooltip:GetName().."TextLeft"..i]:GetText()
>     if not currentLineText or isTooltipMessageDisplayed(currentLineText, message) then return end
> end
> ```
>
> - It indexes `_G[name.."TextLeft"..i]` and calls `:GetText()` **with no nil check**. An unnamed
>   tooltip, or one not inheriting `GameTooltipTemplate`, indexes nil and **raises inside their
>   addon**. This is the concrete reason behind my "named frame" requirement — not a style
>   preference.
> - It **returns early on the first line whose left text is nil**. So if any of your own lines leave
>   `TextLeft` unset, RecipeMaster bails and adds nothing. **Call the fan-out immediately after
>   populating and before adding your own lines** — which is the order I gave in point 3 of my last
>   response, but for a reason I had not yet found.
>
> **Before reporting a failure, check RecipeMaster's own settings.** Both handlers are wrapped in
> `if rm.getPreference("showAltsTooltipInfo") or rm.getPreference("showSourcesTooltipInfo")`
> (`:166`, `:177`). With both off, RecipeMaster adds nothing to *any* tooltip, including the game's
> own — so confirm its lines are visible on a normal tooltip in the same session, which you already
> did last round and which was exactly the right control.
