<!-- charset-ok: this file is never drawn by the WoW client. The BigWigs packager
     publishes it verbatim as the GitHub release body and it is read on the
     CurseForge listing -- both render UTF-8, and the em dashes in entries up to
     v1.0.7 are already published under those release tags, so rewriting them
     would make the repo disagree with what people have read. New entries from
     v1.0.8 on use -- and -> . Added 2026-08-19. -->
# TOG Profession Master Changelog

## [v1.0.8] (2026-08-19) - 206 TBC recipes come back, including every flask; the item API stops depending on a CVar; one offline gate instead of three

### Bug Fixes

- **Flask of Blinding Light, and every other TBC flask, was missing from the
  addon entirely.** Reported in game: *"flask of blinding light is not showing up
  on tbc"*.

  The recipe gate rejected anything whose `requiredSkill` exceeded the client's
  profession cap. TBC's cap is 375; the shipped data gives Flask of Blinding
  Light 390, with difficulty tiers `{390, 393, 397, 405}`. 390 is greater than
  375, so it was filtered out before any list could draw it.

  That rule read like an expansion check -- *"nobody on this client could ever
  need this much skill, so it must be from a later one"* -- and it is not one.
  Measured across all five shipped datasets, every recipe it rejected was a
  **real recipe of that expansion**: 12 on TBC (all Alchemy, being Super
  Rejuvenation Potion and all five flasks), 14 on Vanilla of which 13 were
  already rejected by the Season of Discovery id floor, and **zero** on Wrath,
  Cata and MoP, where the rule had never once fired. The fourteenth Vanilla one
  was Gurubashi Mojo Madness, an ordinary Zul'Gurub recipe hidden on Era for as
  long as the rule existed.

  So it caught nothing another gate had not already caught, and hid 13 real
  recipes doing it. Removed. The premise was wrong twice over: the recipe data is
  already scoped per flavour, so a skill number can never mean "wrong
  expansion"; and the TBC bandages the Era blacklist exists for do not arrive
  through the Vanilla dataset at all. Location: `Modules/RecipeGate.lua`.

- **194 more TBC recipes were hidden by a setting nobody had touched.** Reported
  in game as *"a lot of missing recipes"* on TBC, and a different cause from the
  flask above.

  The TBC content-phase filter defaulted to phase 2, described in the code as the
  live state *"as of v0.5.4"* with a note that a new default would ship each time
  a phase opened. That follow-up never happened. Measured against the shipped
  data, the default hid **194 of 2170 TBC recipes** -- 109 tagged phase 3 and 85
  tagged phase 4 -- across every profession: Jewelcrafting 69, Leatherworking 51,
  Engineering 20, Blacksmithing 17, Tailoring 17, Enchanting 10, Alchemy 6,
  Cooking 2, Fishing 1, Mining 1.

  **The filter is now opt-in and defaults to showing everything.** A constant
  that has to be chased forward by a release is wrong for most of every phase's
  life, and wrong silently. The two failure directions are not equal: filtering
  too little shows a few not-yet-live recipes in a list of things you do not
  have, which is visible and self-correcting; filtering too much deletes real,
  obtainable recipes with no sign anything was removed. The setting is still
  there for anyone who wants to hide unreleased content deliberately.
  Location: `TOGProfessionMaster.lua`, `Modules/RecipeGate.lua`, `GUI/Settings.lua`.

- **Every item lookup in the addon depended on a setting the player controls.**
  `GetItemInfo`, `GetItemInfoInstant`, `GetItemIcon`, `GetItemCount` and
  `GetItemQualityColor` are all deprecation fallbacks on Classic Era: Blizzard
  assigns them from their `C_Item` counterparts only when the
  `loadDeprecationFallbacks` CVar is on. With it off they are nil, so an
  unguarded call raises and a `if GetItemInfo then` guard silently skips the
  branch instead.

  Both shapes were live here. Taking the authoritative list of 47 such names from
  the client source and matching it against every shipped file found **~60 call
  sites across 14 files**. All of them now route through one resolver
  (`addon.Item.*`) that prefers the namespaced form and falls back only where it
  must. Locations: `Compat.lua` and the 14 files that call it.

- **A recipe row could render with no quality colour at all.**
  `ItemLink.QualityHex` guarded on two of those same fallback globals, so with
  the CVar off it returned nil rather than raising, defeating the very thing the
  function was written to guarantee: that an item's colour never depends on cache
  state. Location: `GUI/SharedWidgets.lua`.

- **Crafted-gear rows lost their colour on a client with deprecation fallbacks
  off.** The same defect, one site over, and this one raised rather than
  degrading. Location: `GUI/MissingRecipesTab.lua`.

- **The "(loading...)" placeholder rendered as a box.** Both the shopping list
  and the reagent watch used a single-glyph ellipsis; the client's fonts stop at
  Latin-1. It is the most-seen string in either list, because it shows for every
  item the client has not cached yet. Locations: `GUI/ShoppingListTab.lua`,
  `Modules/ReagentWatch.lua`.

### Improvements

- **The peer-offline check is one function instead of three copies.** Every
  outbound sync request is gated on whether the peer went offline between their
  broadcast and our reply, and that rule was written out three times with only
  one of them covered by a spec. It is now `Scanner:PeerIsOffline`, with its own
  specs plus one per call site. It answers *false* when no roster library is
  loaded, which is deliberate and load-bearing: knowing nothing about who is
  online must not be read as "everyone is offline", or sync refuses every send
  instead of protecting it. Location: `Scanner.lua`.

- **Dead code removed.** A hidden tooltip frame built to scrape reagent links had
  no caller anywhere in the addon. Location: `Scanner.lua`.

- **The `.pkgmeta` reader now refuses what the packager mishandles.** The dev
  replication script parsed trailing comments and unbalanced quotes that the
  BigWigs packager does not, so a `.pkgmeta` that dry-ran perfectly clean could
  still ship an empty zip. When two implementations of one rule disagree about a
  malformed input, the modelling one has to be at least as strict as the real
  one, or its green is worth less than no check at all. Verified firing against
  three fixtures. Location: `wow-version-replication.ps1`.

- **Test suite at 1433 passing.** The offline harness moved to its current
  release, which turned two comm specs red for the right reason: the environment
  now echoes guild addon messages back to the sender as a real server does, and
  the addon's comm diagnostic decides whether a server relays guild traffic *from
  that echo*. The old environment was a permanent simulation of the exact broken
  server the tool exists to detect, so the spec was asserting a property of the
  test harness and reporting it as a property of the addon.

---

## [v1.0.7] (2026-08-08) - The tooltip finally works outside the addon; tooltips are the width the game makes them; vendor buy AND sell; nine wrong reagents; all data generation leaves this addon

### Bug Fixes

- **The reagent column on a cooldown row was always grey, whether you held the
  reagent or not.** Reported in game: *Deeprock Salt* stayed dark grey with salt
  in the bags. The colour is meant to say whether you can actually feed that
  cooldown — white when you hold at least the quantity the mail needs, grey when
  you do not.

  The group popup had that rule and the row it expands from did not: the row
  hard-coded `|cffaaaaaa` into the text, so the two disagreed about the same
  fact. Worse, an inline colour escape beats `SetTextColor`, so the stock check
  had nowhere to write even if one had been added — which is exactly how this
  would read as a broken check rather than a missing one.

  The row now computes the same white/grey resting colour from a bag scan, and
  recolours live off `REAGENT_WATCH_UPDATED`, which fires on every `BAG_UPDATE`
  — so looting or mailing the reagent updates the column without switching tabs.
  Location: `GUI/CooldownsTab.lua`.

- **The recipe tooltip was wider than the game's again, and this time it was
  AllTheThings' line doing it.** Reported in game on *Schematic: Advanced Target
  Dummy*. The line setting the width is ATT's source breadcrumb —
  `ATT > Zone > Kalimdor > Tanaris > …` — measured by this addon's own width
  probe at 583.1px against a 603.6px frame, the difference being the tooltip's
  10px inset per side.

  ATT's row renderer only passes the wrap argument when the entry it is drawing
  asks for it, and breadcrumbs do not ask
  (`AllTheThings/src/Modules/Tooltip.lua:665-678`). The flag defaults to false,
  and an unwrapped line does not merely fail to wrap — it ignores the engine's
  preset width and stretches the whole frame. Every line this addon appends had
  been passing the flag since v1.0.6; what changed is that v1.0.7 started
  invoking ATT on the hand-built recipe tooltip, so it inherited ATT's width.

  Fixed as a **rule** rather than per integration: `ItemLink.WithWrappedLines`
  shims the tooltip's own `AddLine` / `SetText` for the duration of a foreign
  call, forcing the flag into its fixed slot, and puts the methods back
  afterwards — including when the third party raises mid-render. Every
  third-party render now goes through it: the ATT bridge, TOGBankClassic's
  renderer, and the hook-replay chain, which is the one a per-addon fix could
  never have covered because there is no list of addons in it.

  It replaces methods on one tooltip table, not properties on the
  `GameTooltipTextLeft` fontstrings every tooltip in the game shares — that
  being the mistake this addon already deleted once. It is installed and removed
  around a single synchronous call, so nothing but the code we invoked can
  observe it, and no width is measured, computed or stored.

  Raised upstream as `docs/DEPENDENCY_CONTRACTS.md` §11 — every consumer of that
  bridge has the same wide tooltip. Location: `GUI/SharedWidgets.lua`.

- **...and then it came out NARROWER than the game's, because the title was
  wrapping too.** Caught in game immediately after the fix above. With every
  line opted into the preset, nothing claimed a natural width, so the frame
  collapsed to the bare preset and *Schematic: Advanced Target Dummy* broke onto
  two lines — which Blizzard's item tooltip never does with an item name.

  The preset is the width long lines wrap **to**, not the width every tooltip
  ends up at. Exactly one line is now left unwrapped — the title — and it sizes
  the frame, matching where the game puts its own. Everything else still wraps.
  Location: `GUI/BrowserTab.lua`.

  The sweep spec gained a `TITLE_EXEMPT` budget for it, asserted in both
  directions: a *second* unwrapped line in that file fails, and so does the
  title starting to wrap again. Location: `Tests/tooltipwrapflag_spec.lua`.

- **The minimap button's tooltip could stretch every tooltip beside it.** Four of
  its five lines never passed the wrap flag, so they ignored the game's own wrap
  width and sized the frame to whichever line was longest. They are localised
  strings, so how long that is depends on the client's language — which is
  exactly the case that cannot be checked by looking at the English text.

  The lines now pass `nil, nil, nil, true`, Blizzard's own idiom for "keep the
  default colour, opt into the preset", so nothing about their appearance
  changes. Location: `GUI/MinimapButton.lua`.

  The reason it was missed is the more useful half. The spec that sweeps for
  this walked a hand-written list of eleven files and asserted the list was
  eleven long — a check that fails when a file is *added* to the sweep and
  passes forever while one is *missing* from it. It now walks what the TOCs
  actually ship and fails on any file appending tooltip lines that the list does
  not name. Two smaller holes in the same spec closed with it: it accepted a
  wrap flag with too many arguments in front of it (the flag's slot is fixed, so
  a sixth argument pushes it past), and it documented a defence against pattern
  name-collision that it did not implement and did not need. Location:
  `Tests/tooltipwrapflag_spec.lua`.

- **The vendor sell price no longer vanishes on an item you have never seen.**
  It was read straight off `GetItemInfo`, which returns nothing for an item the
  client has not cached — so the row went missing on exactly the tooltips where
  it is most useful: an unfamiliar item, on a fresh login, browsing someone
  else's profession list. Hovering warms the cache, so it appeared on a second
  pass, which is why it looked fine in every manual test.

  It now falls through to `LibItemDB:GetVendorSellPrice`, a shipped static table
  covering ~18,140 Vanilla and ~21,720 TBC items with no cache to wait on. The
  client's own value still wins where it exists.

  Worth recording, because it cost the most: this addon's code and tests carried
  comments in four places saying that library function was *"designed but not
  implemented — do not wire it until they ship it"*. It had been implemented and
  shipping the whole time. The claim was repeated across several sessions
  without anyone opening ItemDB's source to check it. Location:
  `Modules/Price.lua`, `GUI/SharedWidgets.lua`.

- **The Professions tab's View menu had a blank, clickable third row.** With
  "Show All Recipes" off, the dropdown was built from a hardcoded order of
  `guild / mine / missing` while only the first two had labels. AceGUI walks the
  order list and sets each row's text to `text or ""` without checking that the
  entry exists — so instead of erroring it drew an empty row, and clicking it
  switched the view to a mode the menu was no longer offering. Location:
  `GUI/BrowserTab.lua`.

- **TOGPM's tooltip lines were invisible on every bag item, and had been for the
  entire life of the feature.** Three hook paths feed the global item tooltip —
  the modern `TooltipDataProcessor` post-call, the legacy `OnTooltipSetItem`, and
  a fallback hooked onto `Show`. On Classic Era 1.15.9 only the **fallback**
  fires for a bag slot, and because `hooksecurefunc(tt, "Show", …)` runs *after*
  the tooltip has sized and laid itself out, `AddLine` appended to the tooltip's
  data and nothing was ever drawn.

  The addon therefore looked completely absent from game tooltips while its own
  debug log reported `fallback Show-hook fired for itemID = 8952` five times per
  hover — the hook working perfectly and the output invisible. It now forces a
  re-layout after appending, behind a re-entrancy guard since the handler is
  hooked onto `Show` itself.

  Worth recording: the comment twenty lines above that hook already described
  this exact failure for an earlier `C_Timer.After(0, …)` attempt — *"the
  deferred AddLine fired after the tooltip was already laid out and the new lines
  never became visible."* The same trap caught the fallback and nobody connected
  the two. Location: `Tooltip.lua`.

- **Nine of the forty-nine hard-coded cooldown reagents pointed at the wrong
  item, and three pointed at items that do not exist.** Every one had a correct
  comment sitting next to it, which is why nobody noticed.

  | cooldown | pointed at | should be |
  | --- | --- | --- |
  | Transmute: Arcanite | 12364 *Huge Emerald* | 12363 Arcane Crystal |
  | Mithril to Truesilver | 3859 *Steel Bar* | 3860 Mithril Bar |
  | 4 Vanilla elemental transmutes | 7067-7070 *"Elemental X"* | 7076-7082 *"Essence of X"* |
  | Primal Water ×2, Primal Life | 22454 / 22455 — **not real item ids** | 21885 / 21886 |

  The Cooldowns tab's reagent count, its `[AH]` price lookup, its `[Bank]` button
  and its shopping-list add all read that id — so six showed the wrong item and
  three could never resolve anything.

  **Fixed by deleting the tables, not by correcting the numbers.** Reagents are
  now derived from ProfessionDB, which has carried Blizzard's own
  `SpellReagents` the whole time; this addon was maintaining a second hand-typed
  copy of data it already had. What remains is a 3-entry "which reagent to show
  on a collapsed row" map (a display choice no DBC expresses) and a small
  no-library fallback, both cross-checked against the shipped data by
  `Tests/cooldownreagents_spec.lua`. Location: `Data/CooldownIds.lua`.

- **The shopping list silently ignored every multi-reagent cooldown.** Queue
  Brilliant Glass, Primal Mooncloth, Spellcloth or Shadowcloth and it added
  *nothing* — `BuildReagentList` only ever read the single-reagent table, so
  those four contributed no rows and said so nowhere. A shopping list that omits
  what you have to buy is worse than an empty one. Location:
  `GUI/ShoppingListTab.lua`.

- **Recipes ATT calls "never implemented" still appeared in Missing Recipes.**
  Darkspear, Steam Tonk Controller and others. Requires the updated ProfessionDB
  — the fix is in its extractor, which was reading only one of the two ways
  AllTheThings records the fact.

- **The TOGPM block rendered ABOVE other addons' blocks instead of below them.**
  On a normal game tooltip the third parties attach during `SetItemByID` and our
  hook fires after them, so we land at the bottom. The shared block-renderer
  added ours first and the integrations second, inverting that on every tab that
  routes through it. Swapped, so the two look the same.

  **The same ordering was containing failures the wrong way round**, which is how
  it was found: a raise inside our block aborted before the integrations ran, so
  one bug in our code silently deleted AllTheThings, TradeSkillMaster and
  RecipeMaster from the tooltip entirely. With ours last, their content is on
  screen before we can break anything. Location: `GUI/SharedWidgets.lua`
  `AppendRecipeBlocks`.

- **The recipe-detail block only appeared on the Professions tab and on
  game-built item tooltips — four other tabs showed none of it.** Reported
  against Missing Recipes; an audit found the same hole in Cooldowns, the
  Shopping List, Crafting and the Profit Planner.

  The cause is structural rather than an oversight, which is why it was uniform
  and silent: the global hook is `OnTooltipSetItem`, so it fires **only** on
  `GameTooltip` and **only** when the tooltip carries a real item. A recipe shown
  as a **spell** (Cooldowns rows, Shopping List rows), by **trade-skill index**
  (Crafting's enchant and no-link recipes), as **plain text** (the Profit
  Planner's fallback), or on a tab's own **private tooltip frame** (Missing
  Recipes, which uses one deliberately so third-party hooks that crash on recipe
  scrolls never run) inherited nothing at all. Each of those is a recipe, and
  each showed less than the same recipe did one tab over.

  All six surfaces now render the same block, through one entry point —
  `ItemLink.AppendRecipeBlocks` — so they cannot drift apart again. Location:
  `GUI/SharedWidgets.lua`, `GUI/MissingRecipesTab.lua`, `GUI/CooldownsTab.lua`,
  `GUI/ShoppingListTab.lua`, `GUI/CraftingTab.lua`, `GUI/AHProfitTab.lua`.

- **Missing Recipes rows carried no `profId`**, the same omission the browser
  rows had, so the block had nothing to look the recipe up by. Unambiguous to fix
  here: `BuildMissingList` takes one profession and returns nothing for "all", so
  every row in a build belongs to it.

- **One hover of the help icon widened every tooltip in the game for the rest of
  the session.** The icon set a 480px minimum width on `GameTooltip` and only
  called `Hide()`. That frame is shared by the entire UI, and **nothing resets a
  minimum width**: `GameTooltip_OnHide` clears money frames, status bars,
  inserted frames and the backdrop style, then sets `needsReset` — which is read
  only for the secondary compare item. The floor is never touched. So every
  tooltip the player saw afterwards, ours and every other addon's, was pinned
  480px wide until they logged out.

  Now 280, and restored on leave to **whatever it was before** rather than zeroed
  — another addon may legitimately have raised it, and clobbering that to 0 is
  the same bug pointed the other way. Both values are carried:
  `GetMinimumWidth` returns `width, forced` and `SetMinimumWidth` takes a `force`
  argument, so restoring the width alone silently cleared another addon's forced
  flag. Location: `GUI/MainWindow.lua`.

  Guarded by `Tests/tooltipminwidth_spec.lua` (6 cases; deleting the fix reds 5
  of them), which needed a harness change to be possible at all — the offline
  model listed `SetMinimumWidth` as a no-op and shipped no getter, so nothing
  offline could observe the leak. Raised, delivered and adopted the same day.

- **A banker's stock was reported as one stack, so the bank looked emptier than
  it was and requests were capped below what was there.** A bank stores an item
  as one entry **per stack** — 60 Copper Bars in a 20-stack bank is three
  entries — and `addon.Bank.GetBanksWithItem` took the first match and `break`ed.
  Every reagent held in bulk, which is most of them, was under-reported.

  It was visible in two places. The tooltip's "Bankers:" count showed the first
  stack. Worse, `ShowRequestDialog` sums those counts into `totalStock` and
  derives `maxRequestable` from it, so a player literally could not request past
  one stack of an item the bank had plenty of.

  `addon.Bank.GetStock` two functions above had always summed correctly, and so
  had TOGBankClassic's own renderer — this was the one of the three that
  disagreed, and nothing asserted they composed. There is now a spec that adds
  the per-banker counts up and requires the total to equal `GetStock`.
  Location: `Compat.lua`.

### New Features

- **Vendor buy price AND vendor sell price, on every item in the game.** Not just
  recipes — hover anything, anywhere:

  ```text
  TOGPM
  Vendor Buy Price
    1g 20s
  Vendor Sell Price
    17s 50c
  ```

  **Nobody else shows both.** TradeSkillMaster and Leatrix Plus offer vendor
  *sell* price on all items; All The Things shows neither; the game itself shows
  neither in your bags. Buy and sell together is the pair a player actually
  reasons with — "can I buy this cheaper than making it" needs buy, "is this
  worth bag space" needs sell.

  The two numbers come from different places and are not interchangeable.
  **Sell** is a two-tier ladder — `GetItemInfo`'s eleventh return (the same
  figure TSM prints) and then `LibItemDB:GetVendorSellPrice`, a static table that
  is always populated. **Buy** is a three-tier ladder — Auctionator's vendor
  cache, then prices TOGPM captured live from vendors *you* have opened, then
  `LibItemDB:GetVendorBasePrice` — so on an item you have actually met, it
  reflects your reputation discount rather than the Neutral book value. Either
  heading is omitted when its number is genuinely unknown.

  This **replaces** the scroll-only "Vendor Sell Price" row added earlier in this
  release, which fired only on recipes and priced the teaching scroll rather than
  the item under the cursor. Keeping both printed the same number twice on any
  recipe-scroll tooltip — caught in game, not in review. Location:
  `GUI/SharedWidgets.lua`, `Modules/Price.lua`.

### Improvements

- **Tooltip width is now testable offline, and both of this release's width bugs
  have a spec that goes red without the fix.** The test harness previously had no
  way to answer "how wide is this tooltip" — its text metrics are pinned
  deliberately unfaithful — so every width claim had to be checked by hand, in
  game, by the player running a debug probe and reading numbers back. Three hours
  of that produced two wrong fixes in a row.

  The harness now provides a steerable width oracle: a test declares what a given
  string measures, and `GameTooltip:GetWidth()` is computed from the lines rather
  than stubbed. That makes the arithmetic assertable — a wrapping line contributes
  nothing, a double line costs both halves plus the gap, and a tooltip in which
  every line wraps has no width at all. The last of those is the too-narrow bug,
  now stated as a test instead of a screenshot. Location:
  `Tests/tooltipwidth_spec.lua`; harness pin moved to `59c4280`.

- **The Professions and Cooldowns tabs now share one definition of the View
  filter.** Each carried its own guild/mine dropdown and its own default, with
  the Cooldowns copy commented *"Mirrors the Browser tab's `_viewMode`
  dropdown"* — a promise with nothing enforcing it. The peer review predicted
  the exact way it would break: one tab gaining a third mode. That had already
  happened (the Browser's "Show Missing"), and the blank-row bug above was the
  consequence. Both tabs are now call sites of one shared builder that returns
  the option list and its display order together, so a mode without a label is
  no longer expressible. Location: `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`,
  `GUI/CooldownsTab.lua`.

- **Deleted a helper on the Cooldowns tab that nothing ever called.** `nowrap`
  claimed in its own comment to be "applied to every Label-style widget the
  cooldowns table renders so wrap is impossible anywhere". It had no callers at
  all — the comment described an intention that was never wired up, which is
  worse than no comment, because it read as a guarantee. Location:
  `GUI/CooldownsTab.lua`.

- **The lint config now declares the optional price addons it feature-detects.**
  `Auctionator`, `AucAdvanced` and `TSM_API` are read in `Modules/Price.lua`
  behind a presence check at every call site, and the WoW globals `time`,
  `floor`, `GetCoinTextureString` and the three merchant accessors are hoisted
  by the client — so 53 of the file's 55 luacheck warnings were describing a
  deliberate design as a defect, and burying the two that were real. Location:
  `.luacheckrc`.

- **The "Bankers:" block is now drawn by TOGBankClassic itself, not by our copy
  of its layout.** We had rebuilt the block by hand because TOGBank's renderer
  was a file-local closure reachable only through its own `OnTooltipSetItem`
  hook — which never fires for the roughly one third of recipes that are
  trainer-taught and have no teaching item, i.e. exactly the tooltips where the
  block was wanted. It now exposes
  `TOGBankClassic_TooltipBankerInfo:AppendTo(tooltip, itemId)` and we call that.

  The stated cost of the copy was that a restyle in TOGBank would quietly stop
  matching. In fact the two had **already** diverged — not in layout, which was
  kept in step by hand, but in the data underneath it: designated bankers versus
  every rostered alt, raw `"Name-Realm"` versus the realm stripped, name-order
  versus stock-order, and the first-stack bug above. Kept-in-step-by-hand is the
  thing that failed, which is the argument for calling them rather than copying.

  The call is `pcall`'d — it is another addon's code running inside our render,
  the same rule ATT gets — and the old path stays as a fallback for an installed
  TOGBank predating the change, since the two addons update independently.
  Raised as their `docs/DEPENDENCY_CONTRACTS.md` §1 on 2026-08-06, delivered
  2026-08-08. Location: `GUI/SharedWidgets.lua`.

- **This addon no longer generates or stores any generated data.** `tools/` is
  gone entirely — all eleven scripts and both caches now live in ProfessionDB,
  which generates its whole tree from its own pipeline. Three data sets left with
  them:

  - **`Data/Sources/*.lua` — twelve files, 380,088 lines, 6.7 MB** — replaced by
    `Data/SourceDB.lua`, a thin view onto ProfessionDB. That tree was a single
    all-expansion merge loaded by every client, so a Vanilla player carried
    Cata's drop tables; the library ships it per version, in 968 KB for all five
    combined, and now carries the npc **names** as well as the ids.
  - **`Data/VendorPrices.lua`** — replaced by `LibItemDB-1.0:GetVendorBasePrice`.
    Vendor buy price is item data; our copy held 93 items only because it was
    filtered to reagents that appear in recipes, an artifact of living in a
    profession addon. The library's set is 862 on Vanilla and 1,708 on TBC. All
    59 overlapping values agreed before the switch.
  - **The cooldown reagent tables** — see Bug Fixes.

  Nothing about the price *integrations* changed: Auctionator, TSM, Auctioneer,
  the AH scanner and the live `MERCHANT_SHOW` capture are untouched, and the
  static vendor price stays the last-resort tier below all of them, because they
  know the player's actual discount and it does not.

- **`ItemLink.ProfessionForRecipe(recipeId)`** — resolves the owning profession
  from a craft spell id, cached on the addon table like the item→recipe index and
  invalidated the same way. Cooldowns, Shopping List and Crafting rows carry a
  spell id and no profession, and plumbing one through four separate row builders
  would have been four chances to get it wrong. `AppendRecipeBlocks` also
  resolves the crafted item the same way, so a caller holding only a spell id
  still gets the bank and price lines.

- **`Tests/tooltipparity_spec.lua` — 10 specs asserting the tabs actually CALL
  the block.** Worth its own file because the first pass at this release tested
  the block and not the wiring, which is the exact failure this suite already
  carries a warning about: a renderer can be perfect and the addon still show
  nothing in game if nobody invokes it. The whole of v1.0.7 is wiring.

  The Crafting tab is driven for real — `ShowItemTooltip` is a plain method, so
  the production path runs end to end, including the index-based branch that
  carries no item and therefore inherited nothing. The other four call sites are
  closures built deep inside a draw path (an AceGUI callback, pooled-row
  `OnEnter` handlers created during a virtual-scroll update) and are covered by a
  **source assertion**, labelled as one in the file rather than dressed up: it
  cannot prove the call runs, but deleting it fails a test, and these tabs went a
  whole release with the block absent. Mutation-verified — removing the Cooldowns
  and Crafting call sites fails four specs.

- **`Tests/recipedetails_spec.lua` grew to 42 specs**, seven covering the shared
  entry point: that the profession resolves from the recipe id alone, that the
  crafted item does too, that an unknown spell answers nil rather than guessing,
  that a `recipeDB` swap is picked up rather than the first answer served
  forever, and that the one-block-per-tooltip guard still holds when a caller
  passes the profession explicitly. Mutation-verified — removing the resolution
  fails exactly the two specs that name it.

- **The tooltip now ships switched ON.** Three separate defaults were gating the
  global hook down to silence, so on a stock install the addon put **nothing** on
  a game tooltip: `tooltipShowCrafters` was `false`, `tooltipShowIds` was `false`,
  and the pair of them share an early return — and `tooltipRecipeDetails` was
  `"auto"`, which stands down whenever RecipeMaster is installed.

  Crafters is now on, and the recipe block renders regardless of RecipeMaster.
  Standing down was a mistake in its own right: our block is **not** a duplicate
  of RM's. RM has difficulty and sources; only we list which of *your own*
  characters could still learn the recipe, and which guildmates can craft it. The
  `"auto"` mode is kept as a setting for anyone who prefers RM to own game
  tooltips. The IDs footer stays off — it is a diagnostic for bug reports.
  Location: `TOGProfessionMaster.lua`.

- **Missing Recipes draws on the game's own tooltip like every other tab.** It had
  owned a private `TOGPMMissingRecipeTip` frame since v0.7.5, created to sidestep
  a third-party addon erroring on recipe-scroll tooltips. That addon has been
  rewritten since — the crash was cited against a line that is now blank, and the
  surviving unguarded lookups are unreachable because its cache is populated for
  every profession at load. The private frame was also the only mechanism by which
  a TOGPM tooltip could differ in width or appearance from the game's, so it went.

  `ItemLink.Tooltip()`, which existed only to choose between the two frames, went
  with it. A structural guard now fails if a second *displayed* tooltip frame is
  ever created — the three permitted `CreateFrame("GameTooltip", …)` calls are
  invisible text scrapers and are whitelisted by name. Location:
  `GUI/MissingRecipesTab.lua`, `GUI/SharedWidgets.lua`.

- **Third-party tooltip bridges are now isolated.** `AppendIntegrations` replays
  other addons' hook chains onto tooltips we assemble — that is how All The Things
  and TSM reach a tooltip built from `AddLine` calls, which carries no item and so
  fires nobody's hooks. It means other addons' code runs inside our render, so both
  bridge calls are now `pcall`ed. (Note this works where an earlier attempt did
  not: a raise inside a *script handler* is dispatched by the C layer and never
  reaches a caller's `pcall`, but these are direct Lua calls.) Location:
  `GUI/SharedWidgets.lua`.

- **Tooltips no longer stretch across the screen.** A tooltip sizes itself to its
  widest line that cannot wrap, so a single long line — from us or from any other
  addon on the same tooltip — drags everything else out with it. Measured in game:
  a 14-line recipe tooltip reached 604px off one 583px line, while the widest line
  TOGPM contributed was 109px.

  WoW has a built-in wrap width for exactly this, and a line opts into it by
  asking. Every line TOGPM appends now does. It costs nothing, needs no setting,
  and is correct at any UI scale or resolution because the game supplies the
  number rather than the addon guessing at it.

  Guarded by `Tests/tooltipwrapflag_spec.lua`, which reads the source and fails if
  any tooltip line is added without opting in.

  **Worth being straight about how this was arrived at**, since the wrong version
  nearly shipped: several other explanations were pursued and discarded first — a
  leftover minimum width, a second tooltip frame, and a mechanism that measured
  each tooltip and force-wrapped over-long lines to the result. That last one was
  written, then deleted before release: it wrote sizing onto font strings the
  whole UI shares, so a single missed cleanup would have made *every* tooltip in
  the game — Blizzard's included — wrap at TOGPM's number. Location:
  `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`, `GUI/AHProfitTab.lua`.

- **Shared-helper aliases no longer depend on TOC order.** Deduplicating small
  helpers into `addon.UI.*` had been written as a file-scope capture
  (`local Brand = addon.UI.Brand`), which reads the value once as the file loads
  — quietly making `GUI/SharedWidgets.lua`'s position in the TOC load-bearing for
  seven aliases across six files. Move it below any consumer and every alias is
  nil at capture, then raises on first use.

  All seven now resolve at call time
  (`local function Brand(t) return addon.UI.Brand(t) end`), so the ordering stops
  mattering for them. Two further sites turned out to be safe already, by accident
  of sitting inside a function rather than at file scope — same idiom, different
  exposure, nothing distinguishing them but indentation. Location:
  `GUI/CraftingTab.lua`, `GUI/GuildTab.lua`, `GUI/Settings.lua`,
  `GUI/AHProfitTab.lua`, `GUI/MissingRecipesTab.lua`.

  `Tests/loadorder_spec.lua` (8 cases) holds both halves: the capture shape cannot
  come back, and `SharedWidgets.lua` is asserted to load before its consumers in
  all five TOCs. Both guards were verified to fail, not merely to pass.

- **The four `ComputeGuild*Hash` roll-up helpers are one function.** Each was a
  one-liner hardcoding a leaf prefix, four lines above the `ROLLUP_OF` table whose
  comment says it exists *"so the prefix and roll-up key can't drift apart"* — the
  file stated the invariant and broke it immediately above itself. Now
  `HashManager:ComposeRollup(DS, gdb, prefix)`, driven by that table, erroring on
  an unknown prefix instead of returning nil. One list.

  It carries an explicit warning that it composes **without storing** and that
  nothing in production calls it: this addon's hashing is owner-authoritative, and
  a plausibly-named function handing back a value the rest of the addon never sees
  is precisely the shape that caused an earlier cooldown-drift incident. Live
  paths go through `refreshRollup`, which composes *and* stores. Location:
  `Modules/HashManager.lua`.

---

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

> Releases v1.0.3 and earlier are in [CHANGELOG_ARCHIVE.md](CHANGELOG_ARCHIVE.md).
