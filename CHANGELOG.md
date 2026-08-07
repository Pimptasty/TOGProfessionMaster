# TOG Profession Master Changelog

## [v1.0.6] (2026-08-06) - Recipe details on every tooltip, the scroll data source moves, and item links unified

The recipe browser's tooltips are meant to open like the game's own scroll —
`Schematic: Biznicks 247x128 Accurascope` — and fall back to a scroll-*shaped*
one for the third of recipes that are trainer-taught and have no scroll at all.
That data now comes from ProfessionDB rather than ItemDB, the ids behind it are
no longer derived by matching names, and the recipe detail a player wants —
difficulty, where it comes from, which of your alts could still learn it — now
appears on every tooltip in the game rather than only inside this window.

This release also carries the item-link and comm-queue work originally written
up under v1.0.6: AceCommQueue-1.0 MINOR 5 turned sending from fire-and-forget
into a two-way contract, where every accepted send ends in exactly one callback
carrying the delivery verdict for the whole message. TOGProfessionMaster had
adopted that contract for its sync traffic (through DeltaSync) but not for the
three sends it makes directly, and had never registered the library's own
diagnostic command. Both gaps are closed here, plus MINOR 6's fifth verdict.

**On the `queue STALLED — 74s with no progress` errors:** they were **AceCommQueue misreading ordinary client throttling**, and the fix is in that library at MINOR 6, not here. ChatThrottleLib moves a throttled send into its blocked ring and retries it several times a second while firing no callback at all, which from the queue's side is indistinguishable from a callback that was lost — so the 60-second timeout reported normal whisper throttling on a busy realm as a bug in the host addon. The library now asks ChatThrottleLib before reporting anything, waits 300 seconds instead of 60, and **recovers** rather than staying blocked. Nothing in TOGPM caused those errors and nothing in TOGPM had to change to stop them; **update the standalone AceCommQueue-1.0 addon and they go away.** What this release owes that contract is reading its new verdict correctly, below.

### Bug Fixes

- **Recipe tooltips showed the pre-move `Engineering: …` header instead of
  `Schematic: …` for every recipe.** ProfessionDB's 26 shipped data files were
  still registering against `LibItemDB-1.0`, the handle they were generated with
  before the move, so every scroll query returned nil and this addon fell through
  to its oldest fallback. Fixed in ProfessionDB v1.5.0 — **update that addon**;
  no change was needed here. Location: `ProfessionDB/Data/`.

- **The teaching-item ids were built by matching recipe names against item
  names.** That 57-line matcher is gone, replaced by the authoritative DBC join
  `ItemEffect.SpellID → SpellEffect[Effect=36].EffectTriggerSpell` — the same
  relationship the client uses. Cross-checking the two found **42
  disagreements**, and then a second bug only the cross-check could surface: the
  candidate list included ids for items that do not exist in the client's item
  table. With an existence filter the two extractions agree on **all 1,073**.
  Location: `tools/build_authoritative_data.py`.

- **Both `[Bank]` buttons in the Shopping List did nothing.** They called
  `TOGBankClassic.RequestItem(itemId)` behind a guard that tested for that
  function first — but `_G.TOGBankClassic` is that addon's UI controller
  *frame*, which has never carried such a field, so the guard was never once
  true. The buttons looked enabled and silently did nothing for their whole
  life; the guard is what hid it. Now routed through
  `addon.Bank.ShowRequestDialog`, which every other surface already used, and
  which says so in chat when no banker stocks the item instead of opening an
  empty dialog. Location: `GUI/ShoppingListTab.lua`.

- **Recipe-list name colours depended on what the client had cached.** The
  quality colour was read only from the crafted item's cached `itemLink`, so
  the same recipe rendered coloured on one login and plain on the next. Now
  falls back to ItemDB's shipped quality, which answers offline for every item;
  `GetItemInfo` is consulted last, because it returns nil for a cold item and
  asking it first would discard a perfectly good shipped answer. Both row pools
  were affected. Location: `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`.

- **The `Requires <Profession> (N)` line was missing from every browser recipe
  tooltip.** Rows are built per profession and consumers only ever read
  `profName`, so the row never recorded `profId` — and without it `ScrollHeader`
  could not look the recipe up, so it dropped the line silently. The same
  omission made `TeachingItem`'s `meta.itemId` fallback unreachable, which is
  the **only** teaching-item source on Wrath, Cata and Mists. Location:
  `GUI/BrowserTab.lua`.

- **`Requires Mining (1)` on a recipe that needs 230.** The skill number came
  from a field that is a floor of 1 on eight of twelve skill lines, so it was
  wrong for roughly 313 records. The header now reads the correct per-recipe
  value ProfessionDB has always carried, and **omits the line entirely** when
  there is no number worth standing behind. Location: `GUI/SharedWidgets.lua`.

- **Shift-click ignored your keybindings on seven of the ten surfaces that offer it.** There were three implementations of the same gesture: `HandleModifiedItemClick` (Cooldowns, Crafting, Profit Planner), `ChatEdit_InsertLink` (recipe browser ×3, Reagent Tracker, the bank dialog) and a raw `editBox:Insert` (Missing Recipes, Shopping List). Only the first is Blizzard's own router, and only it asks `IsModifiedClick("CHATLINK")` — the other two hard-code a shift check, so anyone who has rebound the link modifier got nothing from those seven surfaces, and ctrl-click for the dressing room existed on three tabs and not the rest. The raw `editBox:Insert` sites also skipped the auction-house search box and macro-frame handling that Blizzard's insert does. All ten now share one router. Location: `Compat.lua`, `GUI/BrowserTab.lua`, `GUI/ReagentTracker.lua`, `GUI/MissingRecipesTab.lua`, `GUI/ShoppingListTab.lua`, `GUI/SharedWidgets.lua`.

- **A TOGPM mouse handler could keep firing inside another addon's window.** `AceGUIFrameScripts` exists to put a raw frame script on an AceGUI widget without leaking it — AceGUI pools widgets account-wide and recycles them into whatever addon asks next, so it saves the widget's prior script and restores it on release. It saved the prior script into a table keyed by event name, and when there **was** no prior script that store was `saved[event] = nil` — which writes no key at all, so the restore loop never visited that event and **our** handler stayed on the widget. The leak therefore happened in the commonest case of all: a widget with no existing handler for the event we wanted, which is every current caller. A released widget kept our `OnMouseDown` and fired it for its next owner. Now recorded with an explicit "there was nothing here" sentinel, so the event is restored to genuinely empty. Found by the new GUI specs, not by a report. Location: `GUI/MainWindow.lua`.

- **`/togpm commtest` gave no verdict in the one case it exists for.** The probe's whole job is answering "does this server core relay guild addon traffic?", and its conclusion is printed by comparing each probe against `== false` — but a probe that never came back was left as **nil**, which satisfies neither branch. So on a server that works you got "GUILD addon relay works"; on a server that drops guild addon traffic you got the word `Verdict:` followed by nothing at all. Every user who ran the tool because sync was broken saw the empty case. Probes now start as `recv = false` so "demonstrably did not arrive" is a state the report can actually read. Found by writing the first tests for this file, which had none. Location: `Modules/CommTest.lua`.

### New Features

- **ATT, TOGBankClassic and price lines now appear on trainer-taught recipe
  tooltips too.** They never did, and the reason is structural: those addons all
  attach through `OnTooltipSetItem`, and a tooltip built from `AddLine` calls
  carries no item, so the hook never fires. Recipes with a real scroll went
  through `SetHyperlink` and got all three for free; the trainer-taught third
  got none of them, which is why the two looked like different addons.

  AllTheThings and prices now come from **ItemDB's `Integrations.lua`
  registry** — one place owning every third-party bridge, so this addon asks
  once and renders whatever providers the player actually has (TSM,
  Auctionator, or neither) instead of duplicating each one's labels and layout.
  Provider formatting is preferred where offered, because showing a different
  number to the one TSM shows everywhere else is worse than showing none.

  TOGBankClassic's block is still rebuilt here, because its renderer is a
  file-local closure with no callable form. That is duplicated layout and it
  will drift if that addon restyles; a contract asking it to expose
  `AppendTo(tooltip, itemId)` is raised in its
  `docs/DEPENDENCY_CONTRACTS.md`. Location: `GUI/SharedWidgets.lua`,
  `GUI/BrowserTab.lua`.

- **Recipe details — skill-up difficulty and where the recipe comes from — now
  appear on tooltips everywhere, not just in our window.** Bags, bank, chat
  links, the auction house, trainers, vendors: hovering a recipe scroll *or the
  item it makes* adds a block in the shape RecipeMaster uses.

  ```text
  TOGPM
  Difficulty
    275 300 310 320      <- orange / yellow / green / grey
  Sources
    Trainer
  Unlearned:                    <- red
    Bob (Skill 71, Elixir Master)
  ```

  **Where the source data comes from is the part that matters.** It is read from
  this addon's own `Data/Sources/`, which is keyed by recipe **spell** — not from
  an item-keyed lookup, which can only answer for a recipe that has a teaching
  scroll. Measured against the shipped Vanilla set: item-keyed covers 44.6% of
  recipes, spell-keyed covers **74.9%** (1172 of 1565), and its single largest
  kind is `trainer` at 508 recipes — precisely the third of every profession that
  has no scroll to inspect and most needs the line. The Sources heading is
  omitted rather than shown empty for the ~25% with no data.

  **`Unlearned:` lists which of your own characters could still learn it**, with
  their skill rank and specialisation. This is the section where we are
  structurally better placed than RecipeMaster rather than merely equal to it:
  RM's spell path covers four skill lines — Mining, Poisons, Engineering,
  Enchanting — and adds nothing on the other eight, silently. Ours reads the
  addon's own synced store, which carries skills, specialisations and alt groups
  for **every** profession, so the section answers everywhere. Scoped to your
  characters rather than the guild on purpose: "who in the guild can make this"
  is already the crafters line, and a guild-wide unlearned list would be forty
  names nobody can act on. The heading is red — the same red as the
  `Already known` line a few rows up (Blizzard's `RED_FONT_COLOR`) rather than a
  second hand-picked one, since the two lines are exact opposites and should read
  as one palette. The character rows stay white so only the heading carries the
  warning.

  **Coverage is decided by who built the tooltip, not by profession.** If we
  built it, we render the block; if the game built it, RecipeMaster does — unless
  RM is not installed, in which case we do that too. RM attaches through
  `OnTooltipSetItem`, which never fires for a tooltip we assemble from `AddLine`
  calls, so the two never overlap and no per-profession logic is needed.

  A setting (*Interface → AddOns → TOG Profession Master → Recipe details on
  tooltips*) forces it on or off, because *loaded* is not the same as
  *contributing*: RM's own display switches are addon-private and unreadable, so
  a player running RM with those turned off would otherwise get the block from
  neither addon. Location: `GUI/SharedWidgets.lua`, `Tooltip.lua`,
  `GUI/BrowserTab.lua`, `GUI/Settings.lua`.

- **`Already known`, in red, on recipes this character knows** — between the
  requirement and the Use line, where the game's scroll puts it. Keyed on the
  `isYou` crafter, so it means what the game means: known to the character
  reading it, not to the account. An alt knowing the recipe does not trigger it.
  Location: `GUI/BrowserTab.lua`.

- **The scroll's `Use: Teaches you how to craft X.` line.** The game's scroll
  tooltip always carries one and ours did not. Localized, and derived at build
  time from the teaching *spell's* description rather than the scroll item's —
  the item field is populated for only 60 of 1,073 Vanilla scrolls against the
  spell's 1,022. Location: `GUI/SharedWidgets.lua`.

- **Shift-click any item in the addon to link it in chat — everywhere, the way the rest of WoW does.** Every item name, reagent row and recipe header now routes through Blizzard's own `HandleModifiedItemClick`, the same function the game's own bag and character panes use. It honours **your** modified-click bindings rather than assuming shift, posts to the social frame when that is what is open, and drops a link into the auction-house search box or an open macro when those have focus. Ctrl-click to preview in the dressing room comes along free, because it is the same router. Location: `GUI/SharedWidgets.lua` and every tab.

- **Hold the compare modifier over an item to see it against what you're wearing.** The side-by-side comparison the game gives you from a bag slot, now on every item in the addon. It follows the modifier **while you hover** — pressing shift with the tooltip already open works — which is how the game behaves and is not free: Blizzard's own frames check the modifier once, when the tooltip is built, and never again. Gated on `IsModifiedClick("COMPAREITEMS")` and the `alwaysCompareItems` CVar, so a rebound compare key and the always-on setting are both respected. Location: `GUI/SharedWidgets.lua`.

- **New setting: "Use the game's standard item tooltips"**, in Options → TOG Profession Master, **off by default**. TOGPM normally draws trimmed tooltips inside its own window so a long list stays readable — a full item tooltip can take half the screen. Turn this on and you get exactly what a chat link gives you instead, including the lines other addons contribute (All The Things and similar). Off by default for a stated reason, repeated in the setting's own description: the Missing Recipes list uses a private tooltip frame **specifically** so third-party `OnTooltipSetItem` hooks never run on it, because some of them error on recipe scrolls and take the tooltip down with them. Turning this on re-exposes you to that, and turning it back off is the fix. Requested on Discord. Location: `GUI/Settings.lua`, `GUI/SharedWidgets.lua`, `Locale/enUS.lua`.

- **`/acq status` now works in game.** AceCommQueue ships the command but no loader that registers it, and nothing else in the addon did either — so the one tool that shows what the comm queues are actually doing did not exist. It prints, per (prefix, distribution, target) queue: whether a send is in flight, how many seconds it has been quiet, how many messages are waiting behind it, and how many the client has refused this session. That is what identifies **which** queue is stuck when a send stops progressing, instead of waiting for the stall report 60 seconds later. `/acq on` / `/acq off` toggle the library's debug tracing. Registered defensively (silent LibStub lookup, feature-detected command) so an older standalone copy degrades to simply not having it. Location: `TOGProfessionMaster.lua`.

### Improvements

- **`Tests/integrations_spec.lua`** — 12 specs pinning the shape of those
  blocks, weighted toward the absent cases: no ATT, no bank addon, TSM installed
  but switched off, no banker holding the item. Each must leave the tooltip
  untouched rather than erroring or printing an empty heading.

- **`Tests/scrollintegration_spec.lua` — the tooltip path is now tested against
  the real shipped data**, not a fake ProfessionDB. Every other spec hands
  `ItemLink` a fixture, which proves the branching and proves nothing about
  whether the library answers on a live client; that gap is precisely what let
  the header bug above ship green. This one loads the real library, executes the
  real data files, and asserts a genuine Engineering recipe resolves to its
  actual scroll. Verified by mutation: reintroducing the defect fails it.

- Both halves of the teaching-item lookup are asserted independently — through
  ProfessionDB with the fallback removed, and through the recipe's own `itemId`
  with the library removed — so neither can rot unnoticed. The second is the
  path Wrath, Cata and Mists rely on entirely, since no recipe-scroll data is
  generated for those flavours yet.

- **Two new spec files were corrupting later ones, and the suite was not
  actually green.** `scrollintegration_spec.lua` overwrote `addon.GetProfessionDB`
  to return the **real** shipped library, and `integrations_spec.lua` blanked
  `addon.Bank` / `addon.Price` / `addon.GetItemDB` — neither restored what it
  replaced. The whole suite shares one addon table, so both leaked into every
  later spec file: 13 assertions in `teachingitem_spec.lua` silently read
  shipped data instead of their own fixtures, and 2 in `shoppingbank_spec.lua`
  died on `attempt to index field 'Bank'` with no visible connection to the file
  that caused it. Every one of those files passes on its own, so only a
  whole-suite run reproduces it. Both now restore in `after_each`; the suite is
  **1190/1190** under the harness's own runner. This is the same discipline the
  env follows for globals, and the one `teachingitem_spec.lua` already followed
  for its own cached library handle.

- **`Tests/recipedetails_spec.lua`** — 35 specs on the new block, weighted toward
  the two things a reader would get wrong. That sources are keyed by recipe
  **spell** and therefore answer for trainer-taught recipes, which is the whole
  reason the block is worth having; and that the RecipeMaster gate is a
  tooltip-**type** split, so our own windows render it unconditionally while
  game-built tooltips defer. Verified by mutation: dropping the scroll half of
  the item index, labelling a source kind whose npc list is empty, and dropping
  the already-learned / is-mine filters from the Unlearned list each fail exactly
  the specs that name them and no others.

- **The recipe block could render twice on one tooltip, on the seven Vanilla
  items that more than one recipe produces.** Gold Bar comes from Alchemy's
  *Transmute Iron to Gold* **and** Mining's *Smelt Gold*; the Gordok Ogre Suit
  from both Leatherworking and Tailoring. Two paths legitimately draw the block
  for a single hover — the browser passes the row's own recipe, the global
  tooltip hook independently resolves the first recipe indexed for that item —
  and the guard against drawing twice was keyed on the **recipe id**, which on
  those items differs between the two callers, so it matched neither. Now keyed
  on whether a block has been drawn at all: a tooltip describes one thing.

  Found by a method the test harness published today — *a spec per feature does
  not test the PAIR, and coverage cannot see it*. Both appenders were specced
  thoroughly in isolation and one of those specs was actively **ratifying** this
  behaviour, asserting a second block should render. Its suggested diagnostic
  ("grep each spec file for the other feature's vocabulary") returned zero in one
  command. Location: `GUI/SharedWidgets.lua`.

- **`profId` on browser rows is now actually tested**, in `browserlist_spec.lua`.
  It had been recorded as "fixed but untestable", on the belief that the guild-db
  fixture could not drive the real row builder — which was wrong; that spec file
  has driven it all along. A stale commented-out attempt and a "NOT COVERED" note
  were left in `scrollintegration_spec.lua` claiming otherwise, and have been
  removed rather than left to mislead again. The field is load-bearing for three
  things now, including the new tooltip block, so a written-down coverage hole
  that did not need to exist was worth closing. Two specs: every row carries it,
  and an **all-professions** build stamps each row's *own* profession rather than
  the one that was requested — the second is the one that matters, because those
  are the same number in a single-profession build, so the obvious test passes
  against the wrong variable. Confirmed by mutation.

- **Offline harness adopted, `2299e12` → `502e31b`** (40 commits). The relevant
  ones for this addon: `time(dateTable)` had been dropping its argument, so any
  date computation silently collapsed onto "now"; `wow.setBuild(flavour)` now
  covers all six clients using the interface numbers from this addon's own
  per-flavour TOCs, which lets a spec probe a version gate on every client
  rather than only the one the shared env happens to be set to; and Classic
  Era's default interface moved 11508 → 11509 to match what we ship.

- **`docs/AUDIT.md`** — the standing peer-review conversation, the inverse of a
  harness contract: findings are raised by a review session and answered here.
  It exists now so that a review has somewhere to land. The first audit written
  under this protocol went into a repo with no index entry and no pointer, and
  no later session had any way to find it — a review nobody reads is worse than
  no review, because it reads as work already done. `CLAUDE.md` points at it,
  which is the part that fires unconditionally.

- **A cross-guild broadcast that the queue gave up on was silently ignored.** AceCommQueue MINOR 6 adds a fifth terminal verdict, `reason = "lost"` — the callback never arrived, ChatThrottleLib had no record of the send, and the retry budget is spent. It arrives with `delivered == nil`, the same shape as a deliberate suppression, so the MINOR 5 test this addon shipped (`delivered == false`, or `"rejected"`, or `"error"`) walked straight past it. That made the **most** serious verdict the only one nobody logged: a send reported `"lost"` has already been released and re-sent once under the retry budget and failed again, so unlike a refusal it will *not* heal itself on the next periodic pass — an allied-guild link can be genuinely down with nothing in the Sync Log to say so. Both broadcasts now treat it as the failure it is, and `"suppressed"` is still deliberately not one. Location: `TOGProfessionMaster.lua`.
- **`/togpm commtest` reported a lost send as "no delivery verdict".** Same root cause, opposite consequence: a `"lost"` probe *did* get a verdict, and it said the queue had given up — but with `delivered == nil` it fell into the "accepted, still waiting" branch and pointed the reader at `/acq status` to hunt a queue that had already moved on. It now prints `LOST — queue gave up after retries` as its own outcome, and the still-waiting message is reworded, because since MINOR 6 a genuinely silent send is usually ChatThrottleLib holding it — which is normal, not broken. Location: `Modules/CommTest.lua`.
- **The two cross-guild broadcasts now take the delivery verdict, so failing federation traffic is visible.** `BroadcastSisterConfig` and `BroadcastSisterRosters` are the only sends TOGPM makes itself — everything else rides DeltaSync, which has its own delivery accounting behind `/togpm dsstatus`. These two passed no callback, which meant AceCommQueue reported a refusal through `geterrorhandler()` itself: correct behaviour by the library, but it lands in the player's bug catcher attributed to the comm layer, and the addon learned nothing about its own allied-guild propagation failing. Both now pass a callback and record a refusal to the **Sync Log** and the debug stream, naming what did not arrive (and, for a roster, **which** allied guild's). This is about visibility, not recovery: both broadcasts are periodic, so a refusal heals itself on the next pass — what was missing was any way to see it happening. A `"suppressed"` verdict is deliberately not treated as a failure, since that is one of our own wrappers dropping a send on purpose. Location: `TOGProfessionMaster.lua`.

- **`/togpm commtest` no longer blames the server for a send the client refused.** The probe exists to answer one question — does this server core relay guild addon traffic? — and its AceComm probe reported a refused send as `NO REPLY`, which is the exact signature of a broken core. It now reads the delivery verdict: a send the client refused prints `NOT SENT — client refused it (reason)`, and the verdict block says plainly that this tells you nothing about the core and points at `/acq status`. A probe that was accepted but produced neither a receipt nor a verdict inside the listen window is now called out too, because that is what a blocked send queue looks like from the outside. Location: `Modules/CommTest.lua`.

- **The offline suite can now test the GUI, and does** — that work took it to 1,087 specs and coverage from 43% to 71%, on the way to the 1,225 this release ships. Three fixtures did most of that: one that draws a tab into a real AceGUI container, one that fakes a live trade-skill session (the state that on Classic can only be reached by casting a profession, and without which none of the Crafting tab runs), and driving `/togpm` through its real dispatcher — **every one of its twenty-four commands, none of which had ever been executed outside the game**. Most of them are diagnostics a user is told to run when something is already broken, which is the worst possible moment for one to throw. The shared test harness gained a widget layer (`env/frames.lua`), so a spec can build a **real** AceGUI widget tree offline: factories return real objects, `SetParent` really re-parents, `GetScript` returns what was set, and an absent method answers `nil` rather than a truthy no-op — which is what makes a multi-flavour `if frame.SetResizeBounds then` feature test pick a real branch offline instead of always taking the retail one. Twelve new specs in `Tests/gui_pool_spec.lua` cover the two helpers written to survive AceGUI's account-wide widget recycling — `GUI.DetachPool` (pooled scroll rows must end up orphaned onto `UIParent`, hidden and unanchored, but still in the pool for the next attach) and `AceGUIFrameScripts` — which is what found the leak above. Nine more in `Tests/gui_scroll_spec.lua` cover `PersistentScroll.Acquire`, the one function five tabs get their scroll frame from and route their pooled-row cleanup through: that releasing the scroll really runs the tab's cleanup, that one tab's cleanup never fires for the next owner of the recycled widget, that a `LayoutFinished` a previous owner overrode **or nilled** is repaired (the v0.3.x regression that cost a tab its scrollbar after a few tab switches), and that a saved scroll position survives a rebuild per key. Eleven more in `Tests/minimap_spec.lua` take `GUI/MinimapButton.lua` from **0% to 91%**, against the real vendored LibDataBroker-1.1 and LibDBIcon-1.0: the click routing (plain left, shift+left, right, and a button with no binding), the tooltip documenting all three, and — the one with history — that LibDBIcon is handed the table that **persists**, seeded from the pre-v0.7.1 field, since LibDBIcon writes the new angle into it when the user drags the button and a throwaway table lost the position on every `/reload`. Eighteen more in `Tests/guildtab_spec.lua` take `GUI/GuildTab.lua` from **0% to 58%**, covering the two functions the Guild tab's claims about your guild rest on: that "who has this profession" is the **union** of recorded skills and known crafters (neither signal alone is complete — most crafters never open their window with the addon watching, and gathering professions have no recipes at all), that a cross-guild alt cannot inflate the headcount an officer recruits on, that a specialisation is inferred from the spec-gated recipes a crafter knows and that a sub-spec beats its parent, and that a skill reading can never render the impossible `375/300` the v1.0.1 fix removed. The whole suite runs on the widget layer rather than a per-spec opt-in, because every AceGUI widget file captures `CreateFrame` as a file-scope local at load, so the model has to be in place before Ace3 loads or no widget is testable at all. Every pre-existing spec passed the switch unchanged.

  Thirteen more in `Tests/shoppinglist_spec.lua` cover the reagent arithmetic behind "what do I still need to buy" — the quantity multiplier, summing a reagent shared by two queued crafts into one line, what the bags already hold across several stacks, and that the shortfall is never negative, because "buy -6 Thorium Bars" is not a shopping list. `BuildReagentList` was made a method to make it reachable; everything around it is rendering.

  Sixteen more in `Tests/reagentwatch_spec.lua` take `Modules/ReagentWatch.lua` from **0% to 78%**, driven through the real `BAG_UPDATE` and `PLAYER_LOGIN` events rather than by calling the internals, so the event wiring is under test too. The subject is the craft-ready alert's latch: it fires **once** when the reagents arrive, stays silent while they are still there (BAG_UPDATE fires constantly — without the latch that is a line of chat every time anything moves in your bags), re-arms only after the bags drop below the requirement, and — a separate code path written for exactly this — does **not** announce on login something that was already sitting in your bags.

  Twenty-four more in `Tests/ahscanner_spec.lua` take `Modules/AHScanner.lua` from **0% to 29%** without needing an auction house: the scan-delay resolution (a configured `0` must not be honoured — that would mean no gap between queries at all), every guard that refuses to start, the queue the scan is built from, and the lowest-buyout selection every cost-to-craft figure rests on. Two of those have field history: a call site once passed `GetItemInfoInstant`'s first return — the item **id**, not the name — and the scanner died on the first `:lower()`; and a bid-only listing carries a buyout of `0`, which counted as a price would report every item as free. A wrong lowest-buyout is invisible in a way a crash is not: it produces a plausible number that simply is not the cheapest listing.

  Twenty-four more in `Tests/cooldownalerts_spec.lua` take `Modules/CooldownAlerts.lua` from **0% to 88%**. Every rule in that module is about not annoying you, and all of them are silent when broken because the code only runs on a timer nobody watches: ding once on the transition to ready, stay quiet afterwards unless a reminder interval was asked for, say nothing in an instance if that setting is on — but **defer** rather than swallow, so it still fires when you leave — and reset cleanly when the cooldown is re-cast so the next expiry gets a fresh first alert. Group rows resolve to the **latest** expiry among their members, matching what the Cooldowns tab counts down to, so the ding lands the moment the row the user is watching reaches zero. Stale entries for characters that are no longer yours are dropped rather than sitting armed forever, never firing and never cleaned up.

  Seventeen more in `Tests/reagenttracker_spec.lua` take `GUI/ReagentTracker.lua` from **0% to 31%** — the two numbers that window exists to show. "Have" is deliberately richer than the shopping list's: it counts the **bank and the mailbox** as well as your bags, because a stack sitting in the bank is not a reason to buy more. "Need" consolidates every reagent across the list, and resolves a reagent's item id from its item **link** when it carries no usable numeric id — reagents arrive from trade-skill scans in exactly that shape, and the failure it prevents is one reagent rendering as two rows that each show part of the requirement.

  Sixteen more in `Tests/settings_spec.lua` take `GUI/Settings.lua` from **0% to 63%**. The headline assertion is that the whole options table passes **AceConfigRegistry's own validator** — the same check the game runs before drawing the panel, across 908 lines of options, where a missing `type` or a nil name anywhere means the Settings panel throws the moment a player opens it and nothing else in the suite would notice. Alongside it, the handlers that actually decide behaviour: the two defaults written as `~= false` / `== true` (invert either and every existing user's crafting UI changes on upgrade), the window-scale coercion that keeps a stale string out of arithmetic, and guild mode — whose `get` must report the **live** DeltaSync state rather than the saved one, so the checkbox cannot claim something the addon is not doing.

  **One branch had never executed offline in the whole history of this suite.** The recipe browser drops any recipe whose spell does not exist on a Vanilla client — that is what keeps a synced later-expansion recipe out of a Classic Era list — but the guard reads `GetSpellInfo and not GetSpellInfo(recipeId)`, and the test harness had no `GetSpellInfo` at all, so it short-circuited and the filter was inert. Every browser spec had been passing with it switched off. The harness now installs it (raised from here), the specs declare which recipes exist on the simulated client, and the filter itself finally has a test.

  Nine more in `Tests/craftscroll_spec.lua` cover `CraftingTab:ScrollToRow` — the first piece of this addon's virtual-scroll code that has ever been testable, because it needs `GetHeight()` to return what was set and the old hollow frame model could not do that. Scroll up with context, scroll down with context, clamp at both ends, and do **nothing at all** when the row is already visible, which if it fired anyway would yank the list out from under the user every time they clicked a recipe they could already see.

  Twenty-one more in `Tests/ahprofit_spec.lua` cover the Profit Planner's `ApplyFilters`, where a wrong answer costs in both directions — a row wrongly hidden is a craft you never make, a row wrongly shown is one you make at a loss. Professions, crafter, price source, search and profitable-only, each alone and combined (they must **all** pass, not any). The rule most at risk is the empty profession set: "nothing ticked" has to match **nothing**, and the natural `if next(set) then` tidy-up inverts it into "show everything" — which looks entirely plausible on screen, because a full list is what you saw before touching the filter.

  Eleven more in `Tests/cooldownfilter_spec.lua` cover the Cooldowns tab's profession filter, which is the **only** place the cooldown taxonomy's expansion gating is applied — so it is all that stands between a Classic Era player and a filter offering Northrend Alchemy Research. Because the suite runs as Classic Era, those are real multi-version assertions rather than a restatement of the table: every later-expansion entry must be inert here while the Vanilla ones still match, and the spec says so out loud by asserting the flavour first, so the "must not match" cases cannot quietly become vacuous if that ever changes.

  Twelve more in `Tests/browservirtual_spec.lua` cover the recipe browser's virtual scroll against the **real** 35-frame pool and a real scroll frame. The trick that makes a list of thousands cheap is that pooled frame `i` shows recipe `firstIdx + i` and is anchored at that recipe's **absolute** place in the content — the frames stay put and the content moves. Position a row by its pool slot instead and the list still looks plausible while showing the wrong thing, which reads as a data bug rather than a scroll bug. Also pinned: a partial row of scroll must not skip an entry, frames past the end of a filtered list are hidden rather than left showing stale recipes, and the tail of a short list renders correctly.

  Fifteen more in `Tests/ahfullscan_spec.lua` cover the full auction scan that builds the local price DB — the source of every cost-to-craft figure in the addon, and arithmetic that goes wrong **silently and by a plausible factor**. An auction is a stack, so the price that matters is `ceil(buyout / count)`; forget the division and a stack of 20 prices the item at twenty times its worth, every craft in the Profit Planner reads as a loss, and nothing errors. The corollary is worth stating out loud because it is what a naive scanner gets backwards: **the cheapest listing is not the cheapest item** — a single bar at 60 is dearer per unit than a stack of 20 at 1000. Also pinned: bid-only auctions (buyout 0) contribute no price rather than a free one, a claimed stack of zero cannot divide by zero, and an item whose only listings are bid-only reaches the price DB not at all rather than as a zero. The **Cata/MoP** scan path gets its own cases rather than sharing the Classic ones, because the API it reads is **0-indexed** while the loop is 1-based: lose that correction and the first listing of every scan silently vanishes from the price DB while the rest of it looks perfectly healthy. A Classic Era player never runs that branch, which is exactly why it is the one nobody would notice breaking.

  Every one of these specs was **mutation-tested**: the behaviour it names was deleted from the source and the spec had to fail. That found **two** of them asserting nothing. One was a sub-spec test that passed with the rule removed, because it was measuring Lua table iteration order rather than the rule; rewritten to control visit order (small contiguous recipe ids land in the table's array part) and asserted in **both** orders, since the rule has to hold whichever recipe the scan reaches first. The other was subtler: two scroll-clamp tests survived deleting the clamp entirely, because AceGUI wires the scrollbar's `OnValueChanged` back into `SetScroll` and the slider clamps to its own 0..1000 range — so the value the test read back was the scrollbar's re-clamp, not what the addon had computed. They were asserting AceGUI's clamping. Fixed by reading the **first** `SetScroll` call rather than the last.

- **Offline suite: eight new specs in `Tests/purge_spec.lua`** covering the delivery contract on both cross-guild broadcasts: that a callback is passed at all, that a delivered message logs nothing, that a refusal is logged naming the payload and the allied guild, that all three `nil` verdicts are told apart (`"suppressed"` is success; `"rejected"` and `"error"` are losses), and that a verdict arriving before the guild DB exists cannot take the callback down. Location: `Tests/purge_spec.lua`.

- **`docs/DEPENDENCY_CONTRACTS.md` records the AceCommQueue adoption at MINOR 5** rather than at the original embed, so a later session can see what is taken up and what is deliberately left.

---

## [v1.0.5] (2026-08-03) - Enchant recipes showed a random item's tooltip; the Crafting tab left a second window open

### Bug Fixes

- **Opening the Crafting tab also popped a second profession window — TSM's, or Blizzard's — and left it there.** Reported on TBC. On Classic there is exactly one way to get a trade-skill session: **cast the profession**. That session (not any frame) is what the tab reads recipes from and crafts through — but the cast fires `TRADE_SKILL_SHOW` / `CRAFT_SHOW`, which is the same event every *other* profession UI listens for. So clicking our tab handed TSM (or Blizzard) their cue too, and the player got two windows. TOGPM only ever hid Blizzard's own frames, and only the one belonging to the current session, so anything else stayed up. The Crafting tab now **claims the session it opens**: for as long as it owns one, Blizzard's `TradeSkillFrame` *and* `CraftFrame` are hidden — re-hidden from an `OnShow` hook, so an addon that shows one later can't leave it up — and TSM's window is hidden through TSM's own public API (`TSM_API.RegisterUICallback`, the only integration point it exposes). Every hide clears the frame's `OnHide` script first, because each of those windows closes the trade-skill session from `OnHide` and that would blank our own tab; if the session is ever observed dying anyway, TSM suppression disables itself for the rest of the play session — a second window beats a Crafting tab with no data in it. The **WoW UI** button releases the claim, so choosing the native window mid-session still works and it stays up. Location: `Modules/Crafting/CraftingEngine.lua`. See `docs/DEPENDENCY_CONTRACTS.md` for the TSM API this is working around.

- **Hovering an enchant in the Professions tab showed a completely unrelated item — a staff, a trinket, whatever happened to share the number.** Reported on TBC; it was present on every flavour. Every recipe key in the shipped recipe data (LibProfessionDB) is the recipe's trade-skill **spell** id, but the browser's link resolver treated that key as an **item** id whenever the entry carried no crafted-item link — and WoW's item and spell id spaces overlap freely, so the lookup silently succeeded on the wrong thing. Spell **13937** is *Enchant 2H Weapon - Greater Impact*; item **13937** is the staff *Headmaster's Charge*, which is precisely what the report's screenshot showed. Crafted-item recipes hid the fault because their link is built from `craftedItemId` and wins first — enchants produce no item, so they fell straight through to the bad lookup. Recipe entries now carry their spell id explicitly, the crafted-item lookup is keyed by `craftedItemId`, and an enchant resolves to its **spell** tooltip (description + reagents). Shift-clicking an enchant likewise inserts the recipe's spell link instead of an unrelated item link. Location: `GUI/BrowserTab.lua`.

- **The recipe list's `[Bank]` button was reading stock for the wrong item.** Same root cause: the button asked TOGBankClassic for stock of `entry.id` — a spell id — so it appeared (or didn't) based on whatever unrelated item shared that number, and the request dialog it opened named that item. It now uses the recipe's `craftedItemId`, so it appears only for recipes that actually produce a bankable item. Location: `GUI/BrowserTab.lua`.

- **The `[TOGPM] crafters` line never appeared on Professions-tab tooltips.** It was looked up by spell id against an item-keyed table, so the lookup always missed and the line silently never rendered. Now keyed by the crafted item, matching the global item-tooltip hook. The `[TOGPM] itemId= spellId=` diagnostic line was reporting the spell id in the **itemId** slot for every recipe; both fields are now correct. Location: `GUI/BrowserTab.lua`.

- **Enchants on the shopping list had no hover tooltip at all** (no crafted item to link). They now show the recipe's spell tooltip. Location: `GUI/BrowserTab.lua`.

- **A guildless player could get sync errors in their bug catcher.** `BroadcastSisterConfig` and `BroadcastSisterRosters` send on `GUILD` and neither checked the player was actually in one. The client refuses such a send — it always did, silently — but **AceCommQueue-1.0 MINOR 5+ now reports a refusal with no delivery callback through `geterrorhandler()`**, so what used to be an invisible dropped message became a visible error, repeating on the ~12-minute config-gossip timer. Anyone who configured allied guilds and then left their guild (or received the list by gossip) would see it. Both now return early when guildless. Location: `TOGProfessionMaster.lua`.

- **Recipes named "… [PH]" were never filtered out of the cache.** The obsolete-name guard that keeps Blizzard's internal placeholders (TEST / QA / DEPRECATED / ZZOLD / OLD) from reaching the UI checks for `[PH]` with `string.find(..., plain)` — and with the plain flag set, the pattern is matched **literally**, so the escaped form `%[ph%]` searched for a percent sign followed by a bracket and matched nothing, ever. Every "Manual: … [PH]" placeholder sailed through the filter and persisted in SavedVariables, where the only way to shift it was a purge. Written plainly now. Found by `Tests/scanner_names_spec.lua`. Location: `Scanner.lua`.

- **Auctioneer pricing never ran for any item the client hadn't cached.** Found while writing `Modules/Price.lua`'s specs. Both Auctioneer bridges build their probe list as `{ itemLink, "item:N:0:0:…", "item:N" }` — and `itemLink` is nil whenever `GetItemInfo` hasn't loaded the item yet, which puts a **nil in slot 1** and makes `ipairs` stop on entry. So the two synthetic item forms, which exist precisely *for* the uncached case, were unreachable exactly when they were needed and Auctioneer was never queried at all. The list is now built by appending, so the synthetic forms are always probed. (Both call sites shared the bug; they now share one builder.) Location: `Modules/Price.lua`.

- **Removed a dead TSM code path.** `tsmAppHelperLoaded` — an `IsAddOnLoaded` probe — was referenced by nothing; readiness is decided by the useTSM / useTSMAppHelper toggles plus the presence of `TSM_API`, which is the real capability test. Location: `Modules/Price.lua`.

- **`Scanner:ResolveProfessionId` called `GetProfessions()` without checking it exists.** Found while writing its specs. `GetProfessions` is the Cata+ API; this addon feature-detects it at every *other* call site — `enumerateHeldProfessions` right below it (whose own comment notes it is a no-op on Classic Era), and `CraftingEngine:GetKnownProfessions` — but not here. This one sits in the hot path of **every** trade-skill and craft-window scan, so on a client without the global nothing would scan at all rather than degrading. Now guarded like its neighbours: absent → fall through to the static profession-name map, exactly as a slot walk that finds nothing already does. Behaviour is identical wherever the API exists. Location: `Scanner.lua`.

- **`HashManager:HasContent` answered "no" as `nil` on some paths and `false` on others.** Found while writing its specs: branches written as `gdb.cooldowns and next(gdb.cooldowns) ~= nil` evaluate to **nil** — not false — when the table is absent, so the same "we hold nothing for this leaf" answer came back with two different types depending on which table happened to be missing. Harmless for `if HasContent(...)`, a trap for any caller comparing against `false` or putting the result on the wire. Every branch now returns a real boolean. Location: `Modules/HashManager.lua`.

### Improvements

- **Guild sync now uses DeltaSync's revision-2 content hash.** Revision 1 renders a number and its string form identically — `{v = 1}` and `{v = "1"}` hash the same — so a genuine difference between two clients can be invisible and the sync silently skipped. Revision 2 (DeltaSync MINOR 16) types each scalar. Both now ride together on every leaf: `HashManager` mints the pair, the wire carries both, a delivered pair is adopted **verbatim** like any other owner-minted token, and every comparison — DeltaSync's own OFFER protocol and our subhash diff alike — uses the **highest revision both ends advertise**. A peer on an older build sends no revision-2 token, so that pair falls back to revision 1 and still agrees; two updated peers get the collision-free comparison. No flag day, no coordination, and no version bump on the wire. One subtlety worth recording: a **roll-up** advertises revision 2 only when *every* contributing leaf has one — a roll-up composed from a mix of revisions isn't comparable to another client's mix, so a half-upgraded guild would otherwise churn; it upgrades itself once the last old leaf is re-minted. This is what lets revision 1 eventually retire across the addon suite. Two now-unreachable helpers (`ComputeCharSkillsHash`, `ComputeCharProfessionsHash`) were removed as part of this — the coverage run flagged them as the only unexecuted lines left in the file, and they were the last revision-1-only minting paths in the addon: a leaf minted through one would carry no revision-2 token and quietly drag its whole roll-up back down. Location: `Modules/HashManager.lua`, `Scanner.lua`.

- **`/togpm dsstatus` now answers "did my sync messages actually arrive?"** DeltaSync-1.0 MINOR 17 added delivery accounting — WoW silently discards addon messages under congestion, and AceComm forwards only a boolean, so a refused send was previously indistinguishable from a delivered one and a sync that had quietly stopped working looked exactly like an idle one. The status block now reports `delivered / refused / not-attempted` with the last refusal's channel, target and size, and adds a plain-language note when the refusals are simply because you're guildless. A new `onSendFailed` hook also logs each refusal to the Sync Log as it happens (capped at the first three, so a guildless player doesn't get one line per message forever). Degrades quietly on an older DeltaSync, which is reported rather than shown as a misleading zero. Location: `Scanner.lua`.

- **Offline test suite added — 634 specs.** TOGProfessionMaster now carries the shared `WoWAPITesting` harness (`Tests/wowapi`, git submodule), `Tests/coverage.lua` (exact line coverage from Lua 5.1 bytecode debug info, not a source-text heuristic), and `Tests/env_togpm.lua`, which boots the **real** addon core offline: the real Ace3 chain, the real AceCommQueue-1.0 and DeltaSync-1.0 from the sibling AddOns folders, the real `Ace:OnInitialize()` with its AceDB and guild-tag hashing. Specs therefore read real tables and compute real hashes rather than hand-copied stand-ins that drift. The specs:

  - `hash_spec.lua` — `Modules/HashManager.lua` at **100%**, including the owner-mints/relay-adopts convergence invariant the cooldown-drift disaster came from.
  - `craftqueue_spec.lua` — `Modules/Crafting/CraftQueue.lua` at **99.2%**, driving the REAL CraftingEngine against stubbed trade-skill APIs, so the queue is tested against the engine rather than against our assumptions about it. Covers the per-item completion model that v0.8.1 fixed twice.
  - `scope_spec.lua` — the display-time visibility gates, run against the REAL LibGuildRoster driven to ready (or deliberately left mid-build). Every bug those gates have had was a question about what to do when the roster *cannot yet answer*, so the cold-start and library-absent paths are asserted explicitly — including that hiding a cross-guild alt must never queue it for deletion.
  - `scanner_merge_spec.lua` — Scanner's merge and normalise half: id extraction, recipe/crafter merges, the cross-guild federation gate, the dropped-profession resurrection guard, alt-group indexing.
  - `price_spec.lua` — `Modules/Price.lua` at **100%**: the source priority ladder, and every optional integration (Auctionator, Auctioneer, TSM) proven inert until the user opts in.
  - `compat_spec.lua` — the version flags and API shims, loaded once per client build (Vanilla → MoP) so a wrong flavour flag or skill cap fails here instead of on someone else's client.
  - `tooltip_spec.lua` — the `[TOGPM]` crafters and IDs lines: the item → recipe → crafter → visibility-gate lookup, deduping, and the deferred-append guard.
  - `browserlist_spec.lua` — the Professions tab's recipe-list pipeline: `BuildFullList` (including the visibility verdict it bakes into each cached row), the tokenised search filter, the skill-tier bands, and the multi-select cache key.
  - `cooldownrows_spec.lua` — the Cooldowns tab's row pipeline (transmute grouping, the spell whitelist, the dropped-profession hide, Salt Shaker's item/spell id collision), the tiebreaking sort, and the supply-mail stack planner.
  - `missingrecipes_spec.lua` — the missing-set subtraction in both scopes, including a recipe stored under its crafted-item id counting as known, and a cross-guild alt NOT covering the guild's gap.
  - `craftingtab_spec.lua` — the Crafting tab's filter and sort, and the Profit Planner's row builder and money formatting.
  - `scanner_sync_spec.lua` — what goes on the wire and what happens to what arrives: absolute-expiry cooldown leaves shipped with the owner's minted token, the adopt-or-ignore rules (including the strict-newer test that stops two peers ping-ponging drifted tokens, and the refusal to let anyone overwrite our own cooldowns), and the subhash diff's `-1` stamp for a leaf we hold no data for.
  - `scanner_cooldowns_spec.lua` — the only place a cooldown is minted: the shared transmute bucket, Ready seeding, the salt-shaker API fallback, and the change-detection that keeps a re-scan from redrawing.
  - `scanner_broadcast_spec.lua` — the send side: the differential hash broadcast, and the serve-side coalescing rules that stop one popular leaf being re-broadcast guild-wide once per requester — including the asymmetry that a CHANGED leaf must always go out immediately (swallowing that is what once stalled two-client cooldown sync), and the orphan-hash self-heal when we're asked for a leaf we hold no data for. Plus sister-roster persistence and the accept gate that rejects a roster for a guild we haven't allied with.
  - `purge_spec.lua` — the only code that deletes another player's data: it refuses to run against an unconfirmed roster, re-validates every flag at sweep time, protects own alts and bank alts of current members, and drops the departed character's leaf HASHES along with the data (a surviving hash is re-minted from surviving data on the next rebuild and resurrects them).
  - `scanner_scan_spec.lua` — the owner-authoritative profession registry and the specialisation read. The delete path is the point: a dropped profession has no window to re-scan, so a wrong "gone" reading destroys data permanently — it therefore deletes only from a read it can trust (locale-independent ids, or an English client) and only after TWO consecutive reads agree, because a partial skill-line read seconds after login looks exactly like a drop.
  - `scanner_names_spec.lua` — recipe-name recovery and the item/spell id-namespace collision behind it (spell 26926 is "Heavy Copper Ring"; item 26926 is "59 TEST Green Shaman Chest").
  - `hashv2_spec.lua` — the revision-2 hash rollout: the revision-1 collision it exists to fix (asserted against the real library, not assumed), that every leaf family carries both tokens, the roll-up's all-or-nothing V2 rule, and the mixed-version comparison in both directions — including the phantom-difference case where getting the fallback wrong would make an old peer and a new one re-sync the same leaf forever.
  - `browserlink_spec.lua` and `craftsuppress_spec.lua` — the two fixes above.

  Run with `lua Tests/wowapi/run.lua` from the addon root (Lua 5.1 only, no busted needed). `Tests` is excluded from packaged builds via `.pkgmeta`. Overall coverage is **4,743 of 14,601** executable lines (32.5%, counting everything the addon ships except the `Locale/` translation tables): Price, HashManager and CraftQueue 100%, CooldownIds 94.7%, Tooltip 68.5%, Scanner 58.8%, CraftingEngine 50.1%, TOGProfessionMaster.lua 48.2%, Compat 44.0%, CooldownsTab 28.5%, MissingRecipesTab 28.2%, AHProfitTab 25.4%, BrowserTab 22.3%, SharedWidgets 18.6%, CraftingTab 14.7%.

  On testing GUI files: the logic in a tab (list building, filters, sort keys) touches no frame — in `GUI/BrowserTab.lua` the first `CreateFrame` sits 300 lines below the last logic function. Those functions are `local` purely because nothing outside the file calls them, which also put them out of the suite's reach. Each such file therefore ends with a small, commented **test seam** exposing them by name. That is deliberately preferred over relocating the logic into `Modules/`: it reaches exactly the same code, changes no call site, and avoids adding a file to all five `.toc` load orders. What stays untested is genuine frame construction, which needs the game client.

- **`docs/DEPENDENCY_CONTRACTS.md` added.** Dependency and third-party-addon repos are read-only from TOGPM: when work here needs a change in one of them, it is written up as a contract (what, why, exact API shape) and applied upstream separately rather than patched locally. Opens with the TradeSkillMaster "suppress the crafting UI for this session" contract that the fix above is working around.

---

## [v1.0.4] (2026-07-28) - Enchanting's Craft button, departed guildmates clearing on their own & the Settings scrollbar

### Bug Fixes

- **Enchanting's Craft button did nothing — the long-standing "every profession works except Enchanting" bug. Fixed.** Enchanting is the one profession whose craft runs through a **secure action button** (it casts `/cast <recipe>` from a secure macro; every other profession crafts from the button's ordinary, insecure `PreClick`). Blizzard's `SecureActionButton_OnClick` only performs the action when the click that arrived matches its key-down/key-up gate — `(down and useOnKeyDown) or (not down and not useOnKeyDown)`, where `useOnKeyDown` falls back to the **`ActionButtonUseKeyDown` CVar**. TOGPM registered the button for `LeftButtonUp` **only**, so for every player with that CVar switched on — **ElvUI** and **Bartender4** both set it, as does Blizzard's own "use key down" option — the click was dispatched, the secure gate discarded it, and no enchant was ever cast. Trade skills were unaffected because their craft happens in `PreClick`, which isn't gated: exactly the reported "I tested alchemy and the craft function works fine, so enchanting may be the only profession not working". The button now registers **both** the up- and down-click while it's in enchant mode, so whichever way the CVar is set (and whichever variant of the gate the client ships) exactly one of the two satisfies it and the enchant casts once. Trade skills keep the single up-click registration so their `PreClick` can't fire twice per click. Verified against Blizzard's `SecureTemplates.lua` and against TradeSkillMaster, whose `SecureMacroActionButton` branches on the same CVar for the same reason. Location: `GUI/CraftingTab.lua`.

- **Guildmates who left the guild kept showing after login until you clicked around — now they clear on their own.** TOGPM never deletes data on its own; it *masks* it by bouncing the database off the live guild roster. Until LibGuildRoster reports its first build complete, that gate deliberately hides **nothing** — a half-built roster can't vouch for anyone, and blanking a legitimate list is far worse than briefly over-showing one. That guard is right; the other half of it was missing. **Nothing told the UI when the cold-start window closed.** The only roster callbacks anyone had hooked were `OnMemberOnline` / `OnMemberOffline` (and only in the Professions tab), so after a login or `/reload` a departed member kept rendering until some *unrelated* event happened to rebuild the list — which is exactly the reported "I saw his name, looked through TOGPM a bit, and then it disappeared". Three fixes: the roster's **ready**, **joined** and **left** transitions now raise a re-scope signal; that signal (`roster`) is routed to every guild-scoped tab instead of only the Guild tab — **Professions, Cooldowns, Missing Recipes** all filter through the same gate and were all missing it; and the Professions tab now rebuilds its recipe-list cache on it, because that cache **bakes each crafter's visibility verdict in at build time**, so a cache warmed during the cold-start window kept serving ex-members for the rest of the session even after the roster went ready. Location: `TOGProfessionMaster.lua`, `GUI/MainWindow.lua`, `GUI/BrowserTab.lua`.

- **The Settings window could clip its lower options with no scrollbar (reported with ElvUI).** AceGUI's scroll frame decides whether to show its scrollbar by comparing the window height against a content height it **cached during layout** — not against what the widgets measure now. Ace3 skinners restyle those widgets *after* AceConfigDialog has laid the options out, which changes their real heights while the cached figure stays at the pre-skin value, so the scroll frame concludes everything fits: no scrollbar appears, the options past the bottom edge are clipped, and the mouse wheel doesn't rescue you either (AceGUI ignores the wheel while the bar is hidden). Opening Settings now re-runs the layout once the window has settled, re-measuring the skinned widgets so the scrollbar comes up. Location: `GUI/Settings.lua`.

### New Features

- **`/togpm whyvisible <Name>` — find out why a character is still being shown.** The display gate keeps several deliberate escape hatches (roster not ready yet, a **sister-guild** tag on the crafter entry, a **stale sister roster**, or being an **alt of somebody still in the guild**) and from the outside they're indistinguishable from "it just isn't purging" — which is what made the bug above so hard to pin down from reports. The command prints each gate's answer for one character, plus the crafter tags actually stored against them and the final `IsVisibleCrafter` / `IsInCurrentGuildScope` verdicts, so a report can name the real cause. Note a `false` verdict also queues that character for the timed purge sweep — the command says so in its output rather than mutating quietly. Location: `TOGProfessionMaster.lua`.

---

## [v1.0.3] (2026-07-15) - Cooldown-sync repair, switched-profession cleanup & cross-guild data-leak fixes

### Bug Fixes

- **Guild cooldown sync has been broken since v1.0.0 — now fixed.** The v1.0.0 "cooldown-sync overhaul" wrapped cooldown *serving* in a timestamp gate: a client would only hand over a cooldown when its own copy was strictly *newer* than the requester's. That comparison can't hold across a guild — it trusts each client's `updatedAt`, but the migration off the old relative-remaining format left every client stamping `updatedAt` at its local receive time (≈now), so an owner's real copy was never "newer" than anyone's stamp and **nobody ever served a cooldown to anybody**. Guild cooldown data silently froze at v1.0.0 and withered as cooldowns expired with nothing replacing them — most people saw only their own. TOGPM now serves cooldowns like every other leaf (prefer-newer, but it never stays silent), and the request advertises what you actually *hold* — real data, not a leftover hash — so a first fetch always resolves and orphaned hashes can't block it. The absolute-timestamp format that stops sync churn is kept; only the broken serve gate is gone. Cooldowns propagate again the moment two updated clients share a guild. Location: `Scanner.lua`, `Modules/HashManager.lua`, `TOGProfessionMaster.lua`, `GUI/Settings.lua`.
- **Synced guild cooldowns no longer vanish because *your* character lacks the profession.** A cooldown that had genuinely synced (e.g. a guildmate's Salt Shaker) could be filtered out on your end if your copy of *their* profession snapshot hadn't caught up — so a bank alt or a fresh login saw an empty Cooldowns tab even though the data was sitting in the database. The dropped-profession hide now applies only to your **own** characters, where the profession read is authoritative and current; guild sync always displays what it received. The owner decides what to broadcast — a viewer shows everything it got. Location: `TOGProfessionMaster.lua`.
- **Fixed a Lua error when hovering the Cooldowns tab's "Ready Only" button.** The button's new tooltip referenced a locale key (`ReadyOnlyTooltip`) that didn't exist, and AceLocale raises its "Missing entry" error on the *access* itself — before the code's own fallback string could run. Added the string and hardened the lookup (`rawget`) so it can never throw regardless of client locale. Location: `GUI/CooldownsTab.lua`, `Locale/enUS.lua`.
- **Alt-group sync (`accountchars`) no longer churns forever.** The alt-group leaf still ran the original v0.7.0 model: a relay **union-added** incoming entries and then **recomputed** the hash on receipt, so every client hashed its *own accumulated view* instead of the owner's canonical one. The leaf therefore perpetually differed between clients and peers re-requested it every sync cycle — a constant background of `accountchars:*` re-sends and repeated full-list subhash broadcasts. It's now **owner-authoritative** like cooldowns and professions: the alt group is minted only by its own account and adopted **verbatim** everywhere else — no union, no recompute — so all clients converge on one hash. Two bonuses fall out of the verbatim *replace* (vs. the grow-only union): a **dropped alt now propagates** guild-wide (the old union could never remove one), and a peer can no longer union stray entries into your *own* alt list. The character purge was also completing this loop wrong — it dropped the alt-group *hash* but left the *data*, so the next cache rebuild re-minted the hash and a purged (left-the-guild) character reappeared; the purge now removes the data too, so a purge sticks. Same release-gated convergence as cooldowns — it settles fully once peers are on the new code. Location: `Scanner.lua`, `Modules/HashManager.lua`, `TOGProfessionMaster.lua`.
- **Guildmates who drop or switch a profession no longer linger in the old profession's data.** When someone unlearned a profession, TOGPM kept listing them as a crafter of its recipes, kept counting them on the Guild tab, and kept showing their profession cooldowns — forever. A dropped profession has no trade-skill window to re-scan, and guild sync could only ever *add* data, never remove it, so the stale entries never cleared. TOGPM now keeps an **owner-authoritative snapshot of each character's current professions** and syncs it on a new `professions:` channel: on login your client reads the professions you *actually* have right now (window-less — it doesn't need you to open anything) and broadcasts the complete set, so a profession you dropped is removed for everyone. Your recipes disappear from the Professions browser, your headcount drops off the Guild tab, the recipes you no longer cover reappear in Missing Recipes, and (below) your profession cooldowns drop off the Cooldowns tab. Heavily guarded against false removals: it only acts on a **confident, complete** read (never a partial early-login scan — a profession must be absent from *two* consecutive reads before it's removed), so a profession you still have but simply haven't opened is never touched. Location: `Scanner.lua`, `Modules/HashManager.lua`, `GUI/GuildTab.lua`, `GUI/MissingRecipesTab.lua`, `TOGProfessionMaster.lua`.
- **Dropping a profession now also clears its cooldowns.** Unlearn Alchemy and its transmute drops off the Cooldowns tab; the same applies to every profession cooldown — Tailoring's Mooncloth / specialty cloths / Dreamcloth, Enchanting spheres, JC prisms and daily cuts, Inscription research, Blacksmithing ingots, Leatherworking Magnificence, and the **Salt Shaker** (whose Use effect requires Leatherworking 250, so losing LW means you can't use it). Each cooldown is matched to its profession. For **your own** characters the row is hidden immediately (checked against your live, authoritative profession read); a **guildmate's** dropped cooldown clears once their client rescans and re-broadcasts without it — the viewer-side hide is deliberately limited to your own toons so a guildmate's genuinely-synced cooldown is never hidden just because your copy of their profession snapshot lagged. Location: `Data/CooldownIds.lua`, `GUI/CooldownsTab.lua`, `TOGProfessionMaster.lua`.
- **On accounts with characters in more than one guild, each toon showed profession/cooldown data from the OTHER guild.** The "guild only" filter on the Professions tab (and the Cooldowns, Guild, and Missing Recipes tabs, plus item tooltips) failed to filter out data belonging to a different guild. Root cause: the database is a single account-wide table (all your toons write into it), and the display-time guild gate `IsVisibleCrafter` short-circuited with *"own alts are always visible, regardless of guild."* So when you were logged into a Guild A character, your Guild B alts — and any recipe or cooldown only they knew — leaked into Guild A's view. The Cooldowns "guild" view was worse still: it carries no guild tag and returned the *entire* account-wide cooldown table with no scoping at all, so even other-guild *members'* cooldowns (synced while you were on a Guild B toon) rendered under Guild A. Fixed with a single roster-truth scope test, `addon:IsInCurrentGuildScope` — a character counts only when LibGuildRoster confirms it's in your current guild (or a configured sister guild), your own alts included. It's applied to every guild-scoped view: the Professions **guild/missing** views (the **Mine** view still shows all your alts across every guild), item tooltips, the Cooldowns guild view, the Guild-tab profession headcounts, and the Missing Recipes "known by the guild" test. The check is read-only — a hidden cross-guild alt is never purged, so its data survives for when you log into that guild — and cold-start-safe (before the roster finishes its first build nothing is hidden; the tabs re-scope once it's ready). Note: because cooldowns/skills carry no guild tag, an own bank alt that is *guildless* (not in the guild) is also scoped out of the guild views — it remains in the **Mine** view. Location: `TOGProfessionMaster.lua`, `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`, `GUI/GuildTab.lua`, `GUI/MissingRecipesTab.lua`, `Tooltip.lua`.

### Improvements

- **Fixed a 1–2 second freeze the first time you open the Professions tab.** The background cache-warmer builds one profession at a time, and after *each* one it forced a **full tab teardown-and-rebuild** (`ReleaseChildren` + redraw of every dropdown, the toolbar, and the scroll pool). With the tab open while the warm ran, that was ~one full rebuild *per profession* back-to-back — a dozen complete UI rebuilds in a row, which is the hitch (the list build itself is effectively instant). The warm now refreshes **only** when the profession it just built is the exact view you're looking at, collapsing that storm to a single redraw; the other professions still warm silently into the cache and appear instantly when you switch to them. Location: `GUI/BrowserTab.lua`.
- **Recipe-browser build does fewer redundant roster lookups.** Each crafter's visibility/guild-scope checks (`IsMyCharacter`, `IsVisibleCrafter`, `IsInCurrentGuildScope`) are now memoized per character within a build, so a crafter known across many recipes is evaluated once instead of once per recipe. Location: `GUI/BrowserTab.lua`.
- **Serve-side coalescing cuts redundant guild broadcasts.** Serving a leaf (or a roll-up's subhash list) is a guild-wide broadcast, but it's request-driven per peer — so when many clients ask for the same thing at once (common in a mixed-version guild, where the one client actually holding real cooldown data gets asked by everyone), it was re-broadcast to the *whole guild* once per requester. TOGPM now suppresses a repeat of the same leaf or roll-up subhash list within a short window — everyone already got the first copy — collapsing those request bursts to a single send. It targets burst amplification (e.g. a login storm); the steady per-cycle re-requests from un-converged old clients still settle only on release. Location: `Scanner.lua`.
- **The new profession snapshot is owner-authoritative and fully backward-compatible.** Each character's profession set is minted only by that character's own client and adopted verbatim by everyone else — hashes are never recomputed on receipt, the same convergence-safe model the cooldown sync uses (recompute-on-receive is what caused past drift/redraw churn). It rides a **separate** `professions:` sync leaf, so un-updated guildmates are completely undisturbed — their existing sync is byte-identical to before and there's no cross-version churn. Un-updated clients simply don't get the switched-profession cleanup until they update. Location: `Scanner.lua`, `Modules/HashManager.lua`.

---

## [v1.0.2] (2026-07-09) - Fix: Auctionator error when opening Enchanting with crafting takeover on

### Bug Fixes

- **Opening Enchanting with crafting takeover enabled threw an Auctionator error (`attempt to index global 'CraftReagent1'`).** On Vanilla/TBC the Enchanting "Craft" window's frames (`CraftReagent1..N`) are created by the load-on-demand `Blizzard_CraftUI` addon, and the *only* thing that lazy-loads it is UIParent's built-in `CRAFT_SHOW` handler. When crafting takeover is on, TOGPM unregisters that handler so Blizzard's window doesn't pop over its own tab — which also removed the loader, so any other addon that hooks `CRAFT_SHOW` (Auctionator's `CraftShown`) ran while those globals were still `nil` and errored. TOGPM now assumes UIParent's load responsibility: it loads `Blizzard_CraftUI` itself so the frames exist for co-installed listeners, then unregisters `CraftFrame`'s own `CRAFT_SHOW` so it still won't auto-pop a second window. Gated on Vanilla/TBC (`HAS_CRAFT_WINDOW`) and the takeover path only, so default hands-off users and Wrath+ clients are unaffected; the escape-to-Blizzard button still works (it summons the window via `UIParent_OnEvent`, which doesn't depend on that registration). Location: `Modules/Crafting/CraftingEngine.lua`.

---

## [v1.0.1] (2026-07-05) - Specialization detection fixes, full guild coverage & crafter search

### New Features

- **Search the Professions tab by crafter name.** Typing a guild member's name into the recipe search box now lists every recipe that player can make — crafter names are folded into the same cached, per-keystroke filter, so there's no added cost, and it honours the current view/visibility. Set the Profession dropdown to **All** and type a name to audit "what can this character craft?" across every profession at once. Location: `GUI/BrowserTab.lua`, `Locale/enUS.lua`.

### Bug Fixes

- **Alchemy specializations were detected with the wrong spell IDs.** The spec scan checked `28682` / `28683` — which are actually **"Combustion"** and **"Leap"**, not alchemy specs — so Transmutation and Potion Masters were never detected and fell to Unspecialized (only Elixir Master, `28677`, happened to be correct). Corrected to the DBC-verified `28672` / `28675` / `28677` (Transmutation / Potion / Elixir Master) in the spec scan, the Guild tab's canonical spec list, **and** the transmute-proc cooldown table (which was keying the every-transmute proc on "Leap"). Location: `Scanner.lua`, `GUI/GuildTab.lua`, `Data/CooldownIds.lua`.
- **Mooncloth Tailoring could never be detected.** The Tailoring spec list used `26802` — **"Detect Amore"**, a Love-is-in-the-Air holiday spell — where Mooncloth's real id `26798` belongs, so Mooncloth tailors were never categorised, and anyone who owned the holiday spell risked a bogus tag. Fixed to `26797` / `26798` / `26801` (Spellfire / Mooncloth / Shadoweave) in the spec scan, the Guild tab list, the recipe-tagging pipeline, and the cloth-cooldown table. Location: `Scanner.lua`, `GUI/GuildTab.lua`, `Data/CooldownIds.lua`, `tools/build_authoritative_data.py`.
- **Cloth-cooldown "guaranteed 2×" bonus was mapped to the wrong specs.** Primal Mooncloth's bonus was keyed to Spellfire's spec id and Spellcloth's to the holiday spell, so Mooncloth tailors got no bonus indicator and Spellfire's never lit up. Each cloth cooldown now maps to its own spec — Mooncloth → Primal Mooncloth, Spellfire → Spellcloth, Shadoweave → Shadowcloth. Location: `Data/CooldownIds.lua`.
- **Archaeology didn't appear on the Guild tab.** The skill-name → profession map was missing Archaeology (`794`), so the gathering scan never recorded it on Cata/MoP clients. Added. Location: `Scanner.lua`.
- **Skill levels rendered an impossible cap like "375/300".** A missing or stale `skillMax` defaulted to the hard-coded Vanilla cap of 300, which then synced guild-wide and displayed *below* the actual rank on TBC/Wrath. The stored fallback is now the rank (a cap can't be below the current skill), and the Guild tab shows every skill against **this expansion's real cap** (`addon.SKILL_CAP`: 300/375/450/525/600 for Vanilla…MoP) instead of the per-character value. Location: `Scanner.lua`, `Compat.lua`, `GUI/GuildTab.lua`.
- **Gathering skills were missed when a skill header was collapsed.** `GetSkillLineInfo` hides a collapsed header's children, so a character with "Professions" or "Secondary Skills" collapsed dropped Skinning / Herbalism / Fishing / Archaeology from the scan. It now expands all headers first (`ExpandSkillHeader`), guarded against the re-entrant `SKILL_LINES_CHANGED` that expansion fires. Location: `Scanner.lua`.

### Improvements

- **The Guild tab now lists EVERY profession, even at 0.** Previously only the gathering professions were force-shown; now every profession available on this client appears with a headcount (0 when nobody has it), so the guild-wide "who has what" view surfaces crafting-profession coverage gaps too. Location: `GUI/GuildTab.lua`.
- **TBC/Wrath specialization recipes now attribute their crafters (requires ProfessionDB v1.2.2).** The recipe data only tagged Vanilla-era spec plans; TBC and Wrath moved the spec gate onto the *crafted item*, so ~65 TBC and ~72 Wrath spec recipes — Lionheart weapons, Dragonscale/Elemental/Tribal leatherworking, Gnomish/Goblin engineering, Mooncloth tailoring — shipped untagged and their crafters showed as Unspecialized. The ProfessionDB generator now reads the crafted item's requirement as well. **Update to ProfessionDB v1.2.2** to pick this up. Location: `tools/build_authoritative_data.py` (ProfessionDB).

---

## [v1.0.0] (2026-07-01) - First full release: Guild professions tab, skill-tier filter & Cooldowns reagent overhaul

**TOG Profession Master reaches 1.0 — its first full release.** A milestone worth marking, and still growing. A new **Guild** tab drills from a profession headcount down to each specialization and the individual crafters — with their skill levels — and now tracks the gathering professions (Herbalism, Skinning, Fishing) that have no window to open; a **skill-tier filter** declutters the Professions browser; the **Cooldowns tab** gets a batch of reagent improvements — every reagent shown for multi-reagent crafts (Brilliant Glass, the specialty cloths), an at-a-glance "you already have this" highlight, a tidier reagent popup, and a fix for the supply-mail button that looked up the wrong item; and under the hood, profession-cooldown sync was overhauled to kill a convergence bug that churned CPU and redraws on busy guilds.

### New Features

- **New Guild tab — the guild's crafting capacity, from headcount down to the people.** Tallies how many guild characters have each profession, then lets you drill in: click a **profession** to expand its **specializations**, then a specialization to list the **characters** in it. Every specialization is shown **even at 0**, so coverage gaps are obvious ("nobody's an Axesmith"). Names are coloured exactly like the Professions tab — white online, grey offline, brand-colour **You** — with an online alt surfacing its offline main, and each name carries that character's **skill level** (`You (300/300)`). A character's spec comes from their recorded specialization *or* is inferred from the spec-only recipes they're known to craft, so even guildmates who don't run the addon get categorised. Counts are the **union of synced skills and known recipe crafters**, the tracked-character total sits in the status bar, column headers and a dedicated **help (`i`) tooltip** explain the view, and it's localized. Location: `GUI/GuildTab.lua`, `Scanner.lua`, `GUI/MainWindow.lua`.
- **Gathering professions are now tracked — see who herbs, skins, and fishes.** Herbalism, Skinning, Fishing (and Archaeology on Cata/MoP) have no trade-skill window to open, so the recipe scan never saw them. They're now read from the character's **skill lines** (`GetSkillLineInfo` — `GetProfessions` is a no-op on Classic Era) and shown on the Guild tab, **always listed even at 0** so the gap is visible. The skill levels sync guild-wide through a new **owner-authoritative `skills:` leaf** that mirrors the cooldown / alt-group leaves — you record your own, it's relayed by anyone — so once a guildmate offers theirs up, everyone sees it. Mining stays on its existing Smelting path. Location: `Scanner.lua`, `Modules/HashManager.lua`, `GUI/GuildTab.lua`.
- **Missing Recipes now has Personal / Guild sub-tabs.** The Missing Recipes tab gained a sub-tab switch: **My Character** (the existing per-character "what am I missing?" view) and **Guild** — a guild-wide list of recipes **nobody in the guild knows**, filterable by profession (or **All Professions**, which tags each row with its profession) and searchable, so officers can spot coverage gaps at a glance. The Guild view drops the character dropdown and the "Can learn now" filter (both are per-character) and computes "missing" as any recipe in the shipped universe with zero crafters across the whole guild. Your sub-tab choice persists across sessions. Location: `GUI/MissingRecipesTab.lua`.
- **Missing Recipes hides recipes your specialization can never learn.** A Tribal leatherworker no longer sees Elemental or Dragonscale patterns; an Armorsmith no longer sees Weaponsmith plans, etc. Recipe scrolls carry their required spec in the game data (`ItemSparse.RequiredAbility`), which the ProfessionDB pipeline now ships as a `requiredSpec` field; the My Character view compares it against your recorded spec and hides mismatches (guild view and "Show All" keep everything). Understands the Blacksmithing sub-spec hierarchy — a Swordsmith still sees general Weaponsmith recipes. Covers Leatherworking, Blacksmithing, Engineering, and Tailoring across Vanilla/TBC/Wrath (specializations were removed in Cata). **Requires the updated ProfessionDB** (regenerated data + `LibProfessionDB` load of the new field). Location: `GUI/MissingRecipesTab.lua`, `Scanner.lua`, `tools/build_authoritative_data.py` (ProfessionDB).
- **Filter the Professions browser by skill tier.** A new multi-select **Skill tier** dropdown in the Professions toolbar shows only recipes in the trainer ranks you tick (Apprentice / Journeyman / Expert / Artisan, plus Master / Grand Master / Illustrious / Zen Master on later clients) — untick the lower tiers to hide their recipes and cut the clutter. Tick multiple tiers (the menu stays open), with **Select All / Clear All** at the bottom; only tiers your client can reach are offered, your selection persists across sessions, and recipes with no known skill level always stay visible. Localized in all shipped languages. Location: `GUI/BrowserTab.lua`.
- **Cooldowns tab now shows every reagent for multi-reagent crafts.** Brilliant Glass (six gems) and Primal Mooncloth / Spellcloth / Shadowcloth (three reagents each) previously showed only one reagent — or none — and no mail button. They now render as click-to-expand **`[+]` rows** whose popup lists every reagent with its own [AH] / [Bank] / mail controls, matching how transmutes already work. Prismatic Sphere and Void Sphere, which showed no reagent at all, now display theirs. Location: `Data/CooldownIds.lua`, `GUI/CooldownsTab.lua`.
- **Reagents you already have are highlighted.** In the Cooldowns reagent popup, a reagent name turns **white (from grey)** when you're holding enough of it in your bags to fill the supply mail — so you can see at a glance which reagents you can send. Location: `GUI/CooldownsTab.lua`.

### Bug Fixes

- **Profession-cooldown sync no longer churns the client (or redraws the UI) every second.** On active guilds, cooldown sync never converged: cooldowns are stored as absolute expiry timestamps but were transmitted as a countdown and rebuilt against each receiver's clock, so every relay hop added the transmission latency, the value ratcheted upward, its hash changed, and the peer-to-peer negotiation re-fired forever — pegging CPU and tearing down / rebuilding the open tab about once a second. Cooldowns are now **owner-authoritative**: the owner ships the absolute expiry plus its own hash, and receivers **adopt both verbatim** instead of reconstructing them, so the hash converges in one exchange and stays quiet. Legacy-format cooldowns from un-updated peers are dropped rather than merged. Location: `Scanner.lua`, `Modules/HashManager.lua`.
- **Your own cooldown starting/finishing now refreshes the Cooldowns tab.** Using a transmute or Salt Shaker committed the cooldown to the database but raised no UI signal — the constant sync churn used to redraw the tab anyway, so it went unnoticed; with that churn fixed, the tab stopped updating until the next guild event. A local cooldown scan that actually changes a value now fires a **cooldowns-scoped** refresh, plus a short follow-up re-check for a cooldown the client reports a beat late. Location: `Scanner.lua`.
- **Salt Shaker cooldown detected on more Classic builds.** The scan called only `C_Container.GetItemCooldown`; where that's absent or returns nothing it fell through to showing "Ready". It now falls back **on the result** to the global `GetItemCooldown`. Location: `Scanner.lua`.
- **Search fields keep focus while guild data streams in — fixed for every tab.** The earlier fix relied on `GetCurrentKeyBoardFocus`, which isn't available on all Classic flavors, so it silently no-op'd (the Professions search still went "unbound"). The focus-aware refresh deferral now lives in the shared `StyleSearchBox` helper that every search box already uses, keys off the reliable `EditBox:HasFocus()`, and resets the deferral counter on each keystroke so continuous typing is never interrupted. Covers Professions, Missing Recipes, Crafting, and Profit Planner. Location: `GUI/SharedWidgets.lua`, `GUI/MainWindow.lua`.
- **Missing Recipes recipe names now colour by the crafted item's quality.** Names were tinted by the recipe-scroll item's own quality, so e.g. "Pattern: Molten Helm" (a common/white scroll that produces an epic helm) showed white instead of purple, and uncached scrolls showed white inconsistently. They now use the produced item's quality — matching the crafting window — falling back to the scroll's quality for recipes with no crafted item (enchants). Location: `GUI/MissingRecipesTab.lua`.
- **Missing Recipes no longer lists recipes you (or the guild) already know.** Recipes whose spell ID is above 25000 — e.g. several patch-added Vanilla cooking recipes like **Smoked Sagefish** (spell 25704) — were wrongly appearing in the missing list even when known. Root cause: the Classic-Era "untagged post-Vanilla" existence gate (`spellId > 25000`) sat inside the same `elseif` chain as the "already known" filter; when a recipe passed that gate (the recipe genuinely exists), the chain short-circuited and the known-filter was never evaluated. The known-filter is now an additive guard that always runs for recipes that survive the version gates — the same fix pattern the "Can learn now" filter already used. Location: `GUI/MissingRecipesTab.lua`.
- **Search fields no longer lose focus mid-typing during guild sync.** On a busy guild, incoming sync fired a window refresh that rebuilt the active tab's toolbar — including its search box — dropping keyboard focus so further keystrokes fell through to keybinds ("unbound"). The refresh now defers while a search field in the window is focused (the same way it already defers while a dropdown pullout is open), so typing isn't interrupted. Location: `GUI/MainWindow.lua`.
- **Fixed the cooldown reagent-mail button reporting "You have no item:1 in your bags."** The mail button inside the reagent-breakdown popup called the mail helper with a missing argument, which shifted the reagent's item ID out of position — so it looked up item "1" (which nobody has) instead of the real reagent. It now passes the full argument set and attaches the correct reagent. This is distinct from the v0.10.10 `C_Container` bag-scan fix — different button, different cause. Location: `GUI/CooldownsTab.lua`.
- **Missing Recipes stops re-rendering several times a second (and the scroll no longer creeps to the bottom).** The list rendered item names and quality colours through WoW's asynchronous `GetItemInfo`, which returns nothing until the client caches each item — so every row stayed "pending", every cache-fill event (from any addon) fired another full re-render several times a second, and that churn slowly walked the scroll position down to the bottom while colours flickered white. Names and quality colours now come from the synchronous, offline **LibItemDB** (the `ItemDB` dependency) on the first paint, with `GetItemInfo` only as a fallback for items LibItemDB doesn't carry — so a drawn list is stable immediately, doesn't refresh on unrelated item loads, holds its scroll position, and shows the correct quality colour right away. Location: `GUI/MissingRecipesTab.lua`.
- **Basic Campfire no longer appears as a Cooking "recipe."** It's the learned campfire ability (it produces no item), not a craftable, so it never belonged in the recipe list. It's now excluded from the shipped data in every game version, and `LibProfessionDB` was hardened so a recipe present only in a locale name file (but not the structural `_core` set) is no longer resurrected as a dataless phantom — which is why it kept showing with a blank skill even after the data drop. **Requires the updated ProfessionDB.** Location: `tools/build_authoritative_data.py`, `LibProfessionDB-1.0.lua` (ProfessionDB).
- **Crystal Infused Bandage no longer shows on Classic Era.** This is a TBC First Aid recipe (skill 300→360, Netherweave-based); the Anniversary Classic client ships its data even though it isn't learnable in Vanilla, so it leaked into the Classic missing list. It's now excluded from the Vanilla data only — TBC and later clients still get it. **Requires the updated ProfessionDB.** Location: `tools/build_authoritative_data.py` (ProfessionDB).

### Improvements

- **Redraws are scoped to what actually changed.** `GUILD_DATA_UPDATED` now carries a change-scope (cooldowns / recipes / skills / alt-groups), and each tab skips refreshes it doesn't render — so a cooldown sync no longer tears down and rebuilds the thousands-of-rows recipe Browser, and a skills sync only touches the Guild tab. Tab switches still always redraw from live data, so nothing goes stale. Location: `GUI/MainWindow.lua`, `GUI/BrowserTab.lua`, `Scanner.lua`.
- **Cooldown sync send-storm curbed.** Un-updated peers were pulling every cooldown leaf each round (and being served all of them). The request and serve paths now gate cooldown leaves on a delivered timestamp, so a converged client neither pulls stale copies nor re-serves them, and old clients that can't parse the new format are no longer fed a stream of leaves. Location: `Scanner.lua`.
- **Sync Log gets a Pause button.** *Settings → General → Sync Log.* Freezes the live view so a text selection survives long enough to copy; entries keep accumulating while paused and the view catches up on unpause, with a "(paused — N buffered)" note in the title. Location: `GUI/Settings.lua`.
- **Spec breakdowns fill in for the whole guild, not just addon users.** The Guild tab now infers a crafter's specialization from the spec-only recipes they're known to craft (the `requiredSpec` the Missing tab already uses), so a Tribal leatherworker who's never run the addon still lands under Tribal instead of Unspecialized. Location: `GUI/GuildTab.lua`.
- **Tidier reagent popup on the Cooldowns tab.** Removed the redundant per-reagent status column (readiness is already shown on the main cooldown row) and widened the reagent column so long names like "Bolt of Imbued Netherweave" sit on one line instead of wrapping — all within the existing popup width. Location: `GUI/CooldownsTab.lua`.
- **Profession-spec detection now covers Leatherworking & Blacksmithing.** The spec scan learned the Vanilla LW specs (Dragonscale / Elemental / Tribal) and BS specs (Armorsmith / Weaponsmith → Swordsmith / Hammersmith / Axesmith) that feed the new Guild tab's breakdown. Harmless on Cata+, where these specializations were removed (the scan simply finds none). Location: `Scanner.lua`.
- **Cooldown group rows keep their proper icon.** Reworked the cooldown-row icon resolution so multi-reagent cloth cooldowns rendered as `[+]` group rows still show the produced-bolt icon override instead of Blizzard's generic net/cloth spell icon. Location: `GUI/CooldownsTab.lua`.
- **Migrated to DeltaSync's multi-host API (requires DeltaSync v4.0.0+).** DeltaSync v4.0.0 (LibStub MINOR 15) made the library multi-host: each addon now creates its own **isolated sync host** instead of sharing one singleton, so TOGPM no longer clobbers — or gets clobbered by — another DeltaSync-using addon in the same client (previously whichever addon initialized last owned the shared namespace). TOGPM now creates its host via `NewHost` and routes everything through it. **This requires the standalone `DeltaSync` addon at v4.0.0 or newer** — on an older DeltaSync, TOGPM's guild sync stays disabled (it will *not* silently fall back to the clobbering singleton path) until you update the dependency. The wire format is unchanged, so a v15 host still syncs with peers exactly as before. A new **`/togpm dsstatus`** command reports the host's namespace, the DeltaSync MINOR, the comm prefixes and P2P state, so you can confirm the multi-host setup at a glance (and prove isolation by running it next to another DeltaSync addon's status). Location: `Scanner.lua`.

---

> Older releases (v0.10.10 and earlier) are archived in [CHANGELOG_ARCHIVE.md](CHANGELOG_ARCHIVE.md).
