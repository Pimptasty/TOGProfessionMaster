# Harness contracts — TOGProfessionMaster

The staging point for requests on the shared **WoWAPITesting** harness (`Tests/wowapi`).

The tracked home is `f:\Game Development\WoWAPITesting\docs\contracts\TOGProfessionMaster.md`, which
carries the full text and the harness's responses. This file exists so a request is committed to
**this** repo too — a contract left only in a submodule checkout is discarded by the next pull.
Protocol, the one-way rule and the append-only rule live in
[`Tests/wowapi/HARNESS_CONTRACT.md`](wowapi/HARNESS_CONTRACT.md).

Pin: `440ed4a` (2026-08-06). Adopted in full; suite green at 1100, every local stand-in deleted.

`tools/verify-addons.lua` reports **57/57 TOC files load** for this addon, so nothing here is
unloadable offline — every remaining coverage gap is an unwritten spec rather than an environment
limit.

## Open

Full text and exact contracts are in the tracked home; summaries here.

### `Item` / `ItemMixin` and `GetSpellTexture` — the two globals every icon-and-label row needs

Both raised together because they block the same thing: a list row that shows an icon and an item
name. Local stand-ins are in `Tests/env_togpm.lua`'s `install()`.

**`GetSpellTexture(spellIdentifier)`** → `iconID, originalIconID`, and returns **nothing** for an
unknown spell (`SpellDocumentation.lua:357`, `MayReturnNothing = true`). First-class on Classic Era,
not a deprecation fallback — six bare call sites under `Interface/` and no `Blizzard_DeprecatedSpell`
entry, so it belongs in **both** spellings like the Cooldown family. Should read `wow.spells`, so a
spell nobody declared has no icon and the `if iconTexture then … else SetTexture(nil) end` fallback
every icon site has stays reachable.

**`Item` / `ItemMixin`** — the async item-data object, six call sites here. **The callback must be
QUEUED, never run inline.** `Blizzard_ObjectAPI/Classic/Item.lua:233` sends `ContinueOnItemLoad`
straight to `ItemEventListener:AddCallback`, which appends and calls
`C_Item.RequestLoadItemDataByID`; the "fires immediately if already loaded" in the comment above it
is not what the code does. A stand-in that called back inline would make every async branch behave
synchronously and hide exactly the ordering bugs it exists to catch — a callback that writes to a
fontstring belonging to a pooled row that has since been recycled into another tab, for one.

Minimum surface: `Item:CreateFromItemID(id)` (errors on a non-number, as the real one does),
`GetItemID`, `IsItemEmpty`, `IsItemDataCached`, `GetItemName`, `GetItemLink`, `GetItemIcon`,
`ContinueOnItemLoad`, `ContinueWithCancelOnItemLoad` (returns a canceller).

**And the delivery needs a way to make the data ARRIVE**, which is the whole point of the object.
The stand-in pairs with an `env.loadItem(itemID, fields)` fixture: register the item, then run the
parked callbacks. Deliberately separate from writing `wow.items[id]` — that models an item that was
**already cached when the frame drew**, so no callback is ever parked. The two are different code
paths and only the second one can catch the recycled-row bug above.

**Why this mattered here.** With `wow.items` empty by default the `GetItemInfo` miss is now the
normal path, so `Item:CreateFromItemID` went from rarely-reached to reached on nearly every row —
`attempt to index global 'Item'` took out fifteen specs the moment the tab drew real data. The
harness's own default is what promoted this from a nice-to-have to a blocker, which seems worth
saying out loud.

### The modified-click and item-comparison surface

`HandleModifiedItemClick`, `IsModifiedClick`, `GameTooltip_ShowCompareItem`,
`GameTooltip_HideShoppingTooltips`, and `ChatFrameUtil.InsertLink`. Stubbed per-spec in
`Tests/itemlink_spec.lua` rather than in the env, because what those specs assert is _which_ router
the addon reaches for — which can only be checked by watching them.

**Why it is worth the harness's time anyway:** this family is where a "verified present in
GlobalAPI.lua" answer is most likely to be wrong, and it cost this addon six broken call sites.
`ChatEdit_InsertLink` **is not a Classic Era API.** It exists only in
`Blizzard_DeprecatedChatInfo/Deprecated_ChatFrame.lua:43`, behind
`GetCVarBool("loadDeprecationFallbacks")`, as `ChatEdit_InsertLink = ChatFrameUtil.InsertLink`. With
that CVar off the global is nil — so three of our call sites guarded it and silently did nothing,
and three called it unguarded and raised at the click. Exactly the `InviteUnit` shape, and exactly
what an env that installs the bare global would have hidden.

So if these are ever installed, the request is: **install `HandleModifiedItemClick` and
`ChatFrameUtil.InsertLink`, and spec that `ChatEdit_InsertLink` is ABSENT**, the way the container
family was handled.

`IsModifiedClick(action)` is the other half. It takes an action name (`"CHATLINK"`, `"DRESSUP"`,
`"COMPAREITEMS"`) and resolves it against the player's binding — it is **not** a synonym for
`IsShiftKeyDown`, and treating it as one silently breaks every player who has rebound the modifier.
A stub should read a steerable table of held actions, empty by default.

> **Correction from this side — 2026-08-06. The premise above about `ChatEdit_InsertLink` was
> WRONG, and it was mine.** Delivered as asked in `fe974c4` — including speccing the global
> **absent**, on my evidence — and then reversed in `5d36a04` when the harness read
> `F:\Blizzard API Docs\CVars.lua:912`: `loadDeprecationFallbacks` has a documented default of
> `"1"`. The fallback globals load on a stock client, so `ChatEdit_InsertLink` **exists**. This
> addon's own 14 unguarded calls to it have always worked in game, which should have been the
> clue.
>
> I asserted "with that CVar off the global is nil" without checking what the CVar defaults to —
> the same shape of error as the `InviteUnit` case this file warns about, inverted: I argued a
> working API into absence instead of a missing one into existence. Had the harness not re-checked,
> it would have specced away something real.
>
> What survives: the three implementations genuinely differ (`ChatEdit_InsertLink` and
> `editBox:Insert` need an already-open edit box and ignore bindings), so unifying on
> `HandleModifiedItemClick` is still right — as a **behaviour** fix, not a crash fix. The
> changelog, the CurseForge entry, three source comments and `Tests/itemlink_spec.lua` are all
> corrected. The container-family refusal is untouched and still correct, for the reason that
> always held: no `Blizzard_DeprecatedContainer` exists at all, so no CVar can conjure those
> globals.

---

> **Answering the loose end — 2026-08-06.** You asked us to re-examine the six call sites, because
> "if three of them guarded the global and did nothing, that guard should have passed — so whatever
> they observed had another cause". You are right, and the answer is worse than a mis-diagnosis:
>
> **There was no observation.** No bug report, no repro, no symptom. I read the six call sites,
> concluded from the CVar that the global was nil, and wrote up the consequences that would follow
> — "silently did nothing", "raised at the click" — as if they were things that had happened. They
> were deductions from a false premise, presented as findings. Nothing moved the symptom, because
> there was no symptom.
>
> **And re-examining turned up a second wrong claim, in the replacement text.** I had written that
> `HandleModifiedItemClick` "opens chat when chat is closed". It does not: it calls
> `ChatFrameUtil.InsertLink`, which returns **false** when no edit box is active
> (`ChatFrameUtilOverrides.lua:6`) — the same function `ChatEdit_InsertLink` aliases. I had
> corrected one unverified claim by writing another.
>
> **What is actually true, now checked against `ItemButtonTemplate.lua:137`:** the router asks
> `IsModifiedClick("CHATLINK")` and `IsModifiedClick("DRESSUP")`, where the other two hard-code a
> shift test. So a player who rebinds the link modifier gets nothing from seven of the ten
> surfaces, ctrl-click for the dressing room works on three tabs and not the rest, and the raw
> `editBox:Insert` sites skip the auction-house search box and macro-frame handling that Blizzard's
> insert does. That is a real inconsistency and unification still fixes it — but it is a
> keybinding-fidelity fix, not a crash fix and not a chat-closed fix.
>
> Corrected in `CHANGELOG.md`, `README.md`, the CurseForge entry, three source comments and
> `Tests/itemlink_spec.lua`. The v1.0.6 release carrying the wrong text was pulled before this and
> has not been re-tagged.

### `LockHighlight` / `UnlockHighlight` record no state

`env/frames.lua`'s Button accepts both and keeps nothing, so a spec cannot ask whether a row is
highlighted — and highlight **is** the selection model for a pooled list. TOGPM's recipe browser
reuses 35 frames for thousands of recipes and marks the selected one with `LockHighlight`, so
`Tests/browservirtual_spec.lua` has to `pending()` on the case that asks whether the right row is
selected. Guarded with an explicit `pending()` rather than a silent skip, because the tempting
workaround here is a test that asserts nothing.

### `FrameUtil` is not installed

`FrameUtil.RegisterFrameForEvents` / `UnregisterFrameForEvents` — FrameXML's batch event helpers.
`Modules/AHScanner.lua` uses them to silence every other frame listening for
`AUCTION_ITEM_LIST_UPDATE` during a full scan (the Auctionator pattern), so the whole full-scan path
raises `attempt to index global 'FrameUtil'` offline.

**Workaround here:** a local pair in `Tests/ahfullscan_spec.lua`'s `before_each`, implemented as a
loop over `RegisterEvent`/`UnregisterEvent` so the frame's event state is real rather than a no-op.

### Four more client globals — delivered, and it corrected the addon

`GetItemInfo`, the bag API, `GetSpellCooldown`, `IsSpellKnown`. Delivered in `616c914`; all four
stand-ins deleted from `Tests/env_togpm.lua`. The asked-for defaults (empty items, empty bags,
`IsSpellKnown` **false**) were adopted as the harness's general rule rather than as four decisions.

**Two things came back corrected, and both were right:**

- **The bare bag globals were REFUSED, and refusing them was correct.** Classic Era, Anniversary and
  Cata/MoP all document the container API under `C_Container` **only** — zero bare call sites, and
  no deprecation fallback file for that family, where Item and SpellBook both have one. So the local
  stub had been driving `Compat.lua`'s fallback branch, which **no supported client reaches**.
  Verified per flavour against `F:\Blizzard API Docs` rather than taken on trust. Two
  `cooldownrows_spec.lua` cases went red on adoption — they were the ones nilling `C_Container` to
  reach that branch — and are rewritten against the namespace. `Compat.lua`'s comment claimed the
  fallback was the Classic path; it is now labelled as unreachable insurance so nobody puts a fix
  there expecting players to receive it.
- **Two arities were short.** `GetItemInfo` returns 18 values, not 11, and the bare
  `GetSpellCooldown` returns four (`start, duration, enable, modRate`), not three. Exactly the
  failure mode flagged when raising it: a wrong-arity call site passes offline and breaks in game.

## Delivered same-day, stand-ins removed

All three raised on 2026-08-04/05 were delivered same-day: `GetSpellInfo` (`5b8bd2e`), and
`libs.register`'s `major` field plus `AnimationGroup:SetToFinalAlpha` (`20626da`). Every local
stand-in is deleted.

**Adopting `GetSpellInfo` was not free, and that is the point.** With the global absent, the Vanilla
"this spell does not exist on this client" filter in `GUI/BrowserTab.lua` short-circuited on
`GetSpellInfo and …` — so the filter had **never run offline** and 29 specs were passing with it
inert. Installing a faithful `GetSpellInfo` turned it on and they failed immediately. Specs now
declare which recipes exist via `env.spellsExist(...)`, and the filter has a test of its own.

## Closed

Full text and responses are in the tracked home; these are the summaries.

### `GetSpellInfo` is not installed

One of the most-used client lookups, absent from `env/wow.lua`. Not a load blocker — the calls sit
inside functions — but it stops the functions a spec is usually aimed at. GuildTab names every
specialisation row with it, so eleven specs died on it at once.

Asked for Classic Era's **seven positional returns**, `nil` for a nil id, and `nil` for an unknown
id — the last one matters because TOGPM has an `or ("Spell " .. id)` fallback that a
never-nil stub would make unreachable offline.

**Workaround here:** a local stub in `Tests/guildtab_spec.lua`'s `before_each`, with full arity.

### `libs.fresh` evicts by manifest key, not by the library's LibStub major

`libs.forget` calls `ace.freshLib(name)` with the manifest key, so a `libs.register`ed entry keyed
by anything other than the library's real major silently reloads nothing. It defeats `fresh()` for
exactly the entries `register` exists for — including FastGuildInvite's `FGI-WhoLib`, which is
deliberately keyed away from its major so vendored copies cannot collide.

Found registering the vendored `LibDBIcon-1.0` as `TOGPM-LibDBIcon`: LibDBIcon errors on a second
`Register` of the same object (correctly — `OnEnable` runs once in game), and `fresh()` appeared to
do nothing, with no indication the eviction had missed. Asked for a `major` field on the entry.

**Workaround here:** `Tests/minimap_spec.lua` keys both vendored entries by their real majors, which
is what `register` was meant to let a consumer avoid.

### `AnimationGroup:SetToFinalAlpha` is missing

`LibDBIcon-1.0` builds a fade-out at registration (`LibDBIcon-1.0.lua:301`), so registering a
minimap button dies with `attempt to call method 'SetToFinalAlpha' (a nil value)` — on the
registration path, so it takes the whole `OnEnable` down. Affects every addon with a minimap button.

**Workaround here:** `env.frames.declareNoop("AnimationGroup", "SetToFinalAlpha")` in
`Tests/minimap_spec.lua`, which is the escape hatch the `env/frames.lua` adoption entry documents.

## Local stand-ins

Currently two, both awaiting a pin move rather than a delivery: **`Item` / `ItemMixin`** and
**`GetSpellTexture`** in `Tests/env_togpm.lua`. Delivered upstream at `41fdefe`, which is newer than
this addon's pin — adopt the pin and delete them together, never one without the other.

The three below are deleted:

- **`readoptLoadTimeFrames()`** — raised and fixed the same day, at `9f0dd38`. `frames.reset()` was
  emptying the object registry, which is what `wow.advanceTime()` ticks and what event dispatch
  walks, so every frame a library created at load was orphaned by the first reset. ChatThrottleLib
  despools its send queue from `ChatThrottleLib.OnUpdate` and nowhere else, so a queued addon
  message was never delivered, `wow.sent` stayed empty, and **nothing errored** — a comms spec saw
  zero sends and no failure. The harness measured it as 18 despooled before a reset, 0 after.
  Verified here before deleting the stand-in: `ChatThrottleLib.Frame` is still in `frames.all()`
  after a full `install()`.

- **`SendChatMessage` / `C_BattleNet.SendGameData`** — the harness now ships the **namespaced**
  forms as the real implementations with the bare globals forwarding to them, verified against
  Blizzard's Classic Era source. This addon's contract had asserted the opposite shape (bare global
  present, namespaced absent) and was wrong; ChatThrottleLib feature-detects the namespaced form, so
  the stand-in had been driving the fallback branch — the one a Classic Era client never takes.
- **`_G.C_Timer`** — superseded by the harness's **driven** clock plus `wow.advanceTime(seconds)`.
  Our stub's `After` was a no-op, which would have made every delay-dependent path silently
  untestable.

Six more globals went with them, all of which this env had been shadowing without knowing:
`GetCurrentRegion`, `time`, `StaticPopup*`, `print`, `GetAddOnMetadata`, and
`C_AddOns.GetAddOnMetadata`.

## Rules this addon's env now follows

- **Never assign a `C_*` namespace table — add to it.** `_G.C_AddOns = { … }` would drop the
  harness's `C_AddOns.GetAddOnMetadata`, exactly as the wholesale `_G.C_ChatInfo = { … }` in the
  Adoption log drops its recording `C_ChatInfo`. Same hazard, different namespace, and it fails
  layers away from the line that causes it.
- **The widget layer is suite-wide, not per-spec.** `Tests/env_togpm.lua`'s `install()` always calls
  `frames.reset()`. It has to: every AceGUI widget file opens with
  `local CreateFrame, UIParent = CreateFrame, UIParent`, so AceGUI binds whichever model is
  installed when it loads and keeps it for the whole run, and Ace3 loads once in `boot()`. A
  per-spec `frames.reset()` yields the rich model for `CreateFrame` and **hollow** frames inside
  every AceGUI widget — presenting as
  `attempt to get length of field '_children' (a function value)` from inside the frames layer.
  Written up in the tracked contract file as a suggested Adoption log addition.
- **`print` goes to `wow.chat`, not stdout.** Any throwaway probe script that loads the env must use
  `io.write`, or it produces no output and looks like a hang.

## Delivered

- **`assert` modifier chain** — 2026-08-03. Originally raised in `docs/DEPENDENCY_CONTRACTS.md`
  before this intake point existed; closed there.
- **`coverage.lua` in the harness** — 2026-08-03, adopted 2026-08-04. Local copy deleted; numbers
  verified identical across the switch.
- **`env/ace.lua`**, **`env/libs.lua`**, **`env/guild.lua`**, **`env/frames.lua`** — adopted
  2026-08-04. The widget layer is what `Tests/gui_pool_spec.lua` runs on.
