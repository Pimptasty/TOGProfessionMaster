# Harness contracts — TOGProfessionMaster

The staging point for requests on the shared **WoWAPITesting** harness (`Tests/wowapi`).

The tracked home is `f:\Game Development\WoWAPITesting\docs\contracts\TOGProfessionMaster.md`, which
carries the full text and the harness's responses. This file exists so a request is committed to
**this** repo too — a contract left only in a submodule checkout is discarded by the next pull.
Protocol, the one-way rule and the append-only rule live in
[`Tests/wowapi/HARNESS_CONTRACT.md`](wowapi/HARNESS_CONTRACT.md).

Pin: `8bc4c51` (2026-08-05). Adopted in full; suite green at 770.

`tools/verify-addons.lua` reports **57/57 TOC files load** for this addon, so nothing here is
unloadable offline — every remaining coverage gap is an unwritten spec rather than an environment
limit.

## Open

_None._ All three raised on 2026-08-04/05 were delivered same-day: `GetSpellInfo` (`5b8bd2e`), and
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

_None._ All three are deleted:

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
