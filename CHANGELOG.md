<!-- charset-ok: this file is never drawn by the WoW client. The BigWigs packager
     publishes it verbatim as the GitHub release body and it is read on the
     CurseForge listing -- both render UTF-8, and the em dashes in entries up to
     v1.0.7 are already published under those release tags, so rewriting them
     would make the repo disagree with what people have read. New entries from
     v1.0.8 on use -- and -> . Added 2026-08-19. -->
# TOG Profession Master Changelog

## [v1.1.2] (2026-09-27) - WoW Forever support, Craft All stops tripping a blocked action, the Craft button no longer protects the whole window, and LibDBIcon becomes a dependency

### Bug Fixes

- **The shopping-list "Ready to craft" alert fired only for cooldown crafts,
  and it rewrote the player's crafter-online choices.** `CheckAlerts` read the
  reagent from `addon:GetCooldownData()`, so a normal recipe on the list never
  alerted, although every entry the Professions tab adds carries the recipe's
  full reagent list (the one the Reagent Tracker sums). It also latched into
  `db.char.shoppingAlerts`, which is the per-recipe opt-in for the
  crafter-online alert (the "!" on a shopping-list row, read by
  `OnCrafterCameOnline`): a ready alert, or logging in with the reagents
  already in the bags, switched that recipe's crafter alert on, and running
  out switched a real opt-in off. The alert now checks every reagent on the
  entry (falling back to the cooldown catalogue for an entry with none), and
  its latch is a module-local table re-armed at login. A multi-reagent recipe
  prints the new `AlertReadyAllFormat` (English only; other clients fall back
  to it). New specs in `Tests/reagentwatch_spec.lua`; the opt-in spec was not
  run against the old code. Location: `Modules/ReagentWatch.lua`,
  `Locale/enUS.lua`.
- **WoW Forever: opening a profession would have scanned into a nil call.**
  Forever reaches profession data through `C_TradeSkillUI`, and whether it
  keeps `GetTradeSkillLine` / `GetNumTradeSkills` / `GetTradeSkillInfo` is not
  verified. New `addon:HasClassicTradeSkillAPI()` checks for all three at call
  time; the Scanner's and the Crafting engine's trade-skill handlers return
  early without them, so on Forever the Crafting tab shows its "open a
  profession" prompt instead of erroring. Known gap: no Forever recipe scan is
  built, so Forever characters contribute no recipes yet (the cooldown scan is
  separate and runs). Location: `Compat.lua`, `Scanner.lua`,
  `Modules/Crafting/CraftingEngine.lua`.
- **The Crafting quantity box overwrote what the player was typing on every bag
  update.** `RefreshDetail` set the stepper's value on every refresh; it now
  sets it only when the quantity actually changed and otherwise uses the
  library's non-forcing `Refresh`. Location: `GUI/CraftingTab.lua`.
- **A right-click on a Crafting queue row's [x] removed the entry.** The
  RowList button column fires on any button; the remove handler now acts only
  on a left click, as the hand-built queue did. Location: `GUI/CraftingTab.lua`.
- **The addon's name in the game's AddOns list used a broken grey colour code
  in every TOC.** All six titles now read
  `|cffFF8000TOG Profession Master|r |cff999999<version>|r` (brand orange,
  grey version tag), and the Cataclysm TOC's tag is spelled out (DeltaSync's
  fleet request). Not checked in the AddOns list. Location: all six TOCs.

- **WoW Forever: an error at login, and the scanner never finished starting
  (in-game report).** `Scanner:Init` registered `TRADE_SKILL_UPDATE`, which
  Forever does not have (its `TradeSkillUIDocumentation.lua` declares
  `TRADE_SKILL_LIST_UPDATE` instead). `RegisterEvent` raises on an unknown
  name, so everything after it in Init -- the login scans, the broadcast
  timers, the trainer and learned-recipe events -- was never set up. The
  events a client may lack (`TRADE_SKILL_UPDATE`, `TRADE_SKILL_LIST_UPDATE`,
  `CRAFT_SHOW`, `CRAFT_UPDATE`, `NEW_RECIPE_LEARNED`) now go through one
  `tryRegister` that skips an unknown name, and `TRADE_SKILL_LIST_UPDATE` is
  registered where it exists. Every other event Init registers is declared in
  Forever's API docs. `CraftingEngine:Init` had the same fault on its own event
  frame (`TRADE_SKILL_UPDATE`, and the `CRAFT_*` trio, none in Forever's docs)
  and now registers them the same way; `TRADE_SKILL_LIST_UPDATE` is handled as
  an update there too. Every other event the addon registers by name is
  declared in Forever's API docs. Not verified in a Forever client; whether the
  classic-style profession scan itself works on Forever is also not verified.
  Location: `Scanner.lua`, `Modules/Crafting/CraftingEngine.lua`.
- **WoW Forever: "bad argument #2 to HookScript" at every login (in-game
  report).** Forever's tooltips have no `OnTooltipSetItem` script (the modern
  engine replaced it with `TooltipDataProcessor`, which the same function
  already registers), and `HookScript` raises on a script a frame lacks. The
  tooltip hooks now go on only where `HasScript` says the frame has them.
  `Tests/tooltiphooks_spec.lua`'s fake tooltip now raises exactly as a real
  frame does and a new spec covers a tooltip with no `OnTooltipSetItem`.
  Location:
  `Tooltip.lua`.
- **WoW Forever: hovering a quest reward raised "attempt to call a nil value"
  from the tooltip (in-game report).** Forever's `GetItem` comes from
  `GameTooltipDataMixin`, which not every tooltip handed to the
  `TooltipDataProcessor` post-call carries. All four link reads now go
  through `TooltipLink`, which uses `GetItem` where it exists and
  `TooltipUtil.GetDisplayedItem` (that mixin's own implementation) otherwise.
  `tooltip_spec` and `tooltiphooks_spec` pass (33/0); not verified in a
  Forever client. Location: `Tooltip.lua`.
- **WoW Forever: the cooldown scan failed at every login with "attempt to call a
  nil value" (in-game report).** Forever has no bare `GetSpellCooldown`
  (`11_0_0_SpellBookAPITransitionGuide.lua:53` maps it to
  `C_Spell.GetSpellCooldown`, which answers one table), and its `IsSpellKnown`
  is only an off-by-default deprecation fallback. New `addon.Spell.GetCooldown`
  answers the classic `start, duration, enabled, modRate` from either API, and
  `addon.Spell.IsKnown` falls back to `C_SpellBook.IsSpellInSpellBook` exactly
  as Forever's own fallback does. All seven call sites use them (the cooldown
  scan, specialization detection, `/togpm transmutedebug`). Specs in
  `Tests/compat_spec.lua`. Location: `Compat.lua`, `Scanner.lua`,
  `TOGProfessionMaster.lua`.
- **WoW Forever: the Guild tab failed to open with "attempt to call a nil value"
  (in-game report).** Forever has no bare `GetSpellInfo` either, and its
  transition guide also drops the bare `GetSpellTexture` and `GetSpellLink`.
  New `addon.Spell.GetInfo` / `GetTexture` / `GetLink` use the bare function
  where it exists (the real one on the classic clients) and otherwise
  `C_Spell`'s, with `GetInfo` unpacking its `SpellInfo` table into the classic
  `name, rank, icon, castTime, minRange, maxRange, spellID` list. Every call in
  the addon now goes through them -- the Guild, Cooldowns, Missing Recipes,
  Crafting, Profit Planner, Professions and shopping-list code, the scanner,
  the recipe gate and reagent alerts -- so no other tab hits the same error.
  Specs in `Tests/compat_spec.lua`. After these five Forever fixes the operator
  reported no further errors in a Forever client (2026-09-27); nothing beyond
  logging in and opening the tabs has been exercised there. Known gap: `GetSpellBookItemInfo` / `GetNumSpellTabs` are also gone on
  Forever; the spellbook name cache is guarded and simply stays empty there.
- **A recipe learned from a pattern stayed on the Missing Recipes tab until the
  profession window was opened (player report).** Only the trade-skill and craft
  scans write the character's own crafter set, and they run only while that
  window is open. A pattern, plan or formula read from the bag learned the recipe
  with the window closed, so nothing recorded it. Two new listeners now do:
  `NEW_RECIPE_LEARNED(recipeID)`, which Classic Era's API docs declare but which
  is not confirmed to fire for profession recipes, and the
  `ERR_LEARN_RECIPE_S` system message ("You have learned how to create a new
  item: %s."). The message is matched against the client's own localised string
  and the name is looked up only in the character's own professions. Both go
  through the new `Scanner:RecordLearnedRecipe`, which adds the one recipe,
  stamps the scan time, invalidates the profession hash, refreshes the tabs and
  schedules the broadcast. A spell-known check was ruled out because
  `IsSpellKnown` answers false for trade-skill spells on Classic Era (DATA-004).
  Fixed for recipes whose learn message names them; Enchanting formulas (the
  Craft window) are not verified, and neither is whether the message's name is
  the recipe's or the crafted item's. Peer Review (thread dd630106) found
  Blizzard's own Era UI registers `NEW_RECIPE_LEARNED` only for Engraving, so
  the chat message is the real path and the event is a bonus. Not yet seen in
  game. Location: `Scanner.lua`, `Tests/scanner_learn_spec.lua`.
- **Craft All raised ADDON_ACTION_BLOCKED "DoTradeSkill()" as soon as the
  first recipe finished.** `_OnCraftSuccess` chained `CraftNext` through a
  `C_Timer` from `UNIT_SPELLCAST_SUCCEEDED`, but `DoTradeSkill` only runs from
  a hardware event, so the client blocked the second recipe. Craft All now
  crafts the top eligible entry's full batch and ends the run. When the batch
  finishes and more is craftable, it prints `CraftAllNextNeedsClick` telling the
  player to click again. `CraftAll` also clears `_craftAll` when no batch
  started (nothing eligible, or the Enchanting hand-off). Before, a later
  unrelated batch would finish "inside" the run and print the prompt. The
  tooltip (`CraftCraftAllDesc`) says a click is needed per recipe. Location:
  `Modules/Crafting/CraftQueue.lua`, `Locale/enUS.lua`.
- **Closing the window in combat raised ADDON_ACTION_BLOCKED "Frame:Hide()"
  (blamed on Ace3).** The secure `TOGPMCraftButton` was a child of the
  Crafting detail panel. A frame with a secure child is protected, and so is
  every ancestor, so the whole AceGUI window became protected. The pooled frame
  could also carry that protection to the next addon given it. The button now
  lives on `TOGPMCraftButtonHolder`, which is parented to `UIParent` and not
  anchored to the panel either. Peer Review (thread 008cd6d5) quoted the wiki:
  protection also carries to frames a secure frame is anchored to.
  `RegisterStateDriver(holder, "visibility", "[combat] hide; show")` hides it
  for combat. New `CraftingTab:SyncCraftButton` places it at the panel's
  screen position, strata and scale, out of combat only, and re-runs on panel
  show/hide, on `PLAYER_REGEN_ENABLED`, and from an `OnUpdate` watcher that
  runs only while the button is wanted and follows window drags and scale
  changes. The stepper row (-, MAX, +) is anchored to the panel instead of the
  button. The button stays secure because Enchanting's `DoCraft` is protected.
  Location: `GUI/CraftingTab.lua`.
- **Sister-guild data pulls were refused for every legitimate member once a
  sister roster was held.** The anti-spoof check called
  `IsInGuildScoped(name, guildKey)`, but the library's signature is
  `(guildKey, name)`, so identity always came back false. The gate moved into
  `Scanner:SisterPullGate(sender, baseline)`, which returns
  `(consentOk, identityOk)` and passes the arguments in the right order.
  Location: `Scanner.lua`.
- **Placeholder skill tiers were shown and filtered on as real thresholds.**
  ProfessionDB's rule: when `requiredSkill` is absent and `difficulty[1] == 1`,
  the tiers are unanchored placeholders. New `addon.IsUnanchoredDifficulty` and
  `addon.RecipeLearnSkill` apply that rule. `FormatSkillTiers` shows "-" for
  those recipes. The Browser tier filter and the Missing Recipes "Can learn
  now" gate treat them as unknown and keep the row. Location:
  `TOGProfessionMaster.lua`, `Modules/Crafting/CraftingEngine.lua`,
  `GUI/BrowserTab.lua`, `GUI/MissingRecipesTab.lua`.
- **The Missing Reagents [Bank] button sent requests with no item name.** It
  passed `entry.name` / `entry.link`, but `BuildReagentList` entries carry
  `itemName` and no link, so the dialog always got `nil` for both. The name and
  link are now resolved with `addon.Item.GetInfo(itemId)` at click time.
  Location: `GUI/ShoppingListTab.lua`. NOTE, found later the same day: nothing
  in the shipped addon draws `ShoppingListTab` -- `MainWindow:DrawTab` has no
  branch for it and `getTabDefs` lists no such tab -- so this fix, and the
  Reagent Watch panel in the same file, cannot be reached in game. The player
  notes no longer list it.
- **The Professions tab leaked three frames on every redraw.** `Draw` created a
  new column-header bar and two tooltip hit frames each time and dropped them on
  release. WoW never frees a frame, and `Draw` re-runs on every
  `GUILD_DATA_UPDATED`. New `BrowserTab:EnsureHeaderBar` creates them once, and
  `Draw` re-parents and re-anchors them, like `_detailOuter`. Location:
  `GUI/BrowserTab.lua`.
- **The Cooldowns tab leaked frames on every refresh and every popup open.**
  `DrawRow` created up to 11 raw frames per row, plus their textures and font
  strings, and dropped them on release. The transmute popup built a new shell,
  click-outside overlay and ~6 frames per row on every open. WoW frees neither
  frames nor regions. Each row now takes a kit (`NewRowKit`: every frame and
  region a row can use, built once) from a free list and returns it on release.
  Each element keeps its role, and whatever a row sets conditionally (the spec
  icon and its hover, the group row's click) is reset. `ReleaseRowKit` drops
  the reagent label's entry from `reagentTints`, so a kit sitting in the free
  list is no longer recoloured on every `BAG_UPDATE`. The popup keeps one shell
  (`_popupShell`) and one row slot per line (`NewPopupRow`), with unused slots
  hidden. A per-kit / per-open generation stops a late item-load callback
  writing into a kit or row that has moved on. Location: `GUI/CooldownsTab.lua`.
  Later in this release the rows themselves moved to a RowList (see
  Improvements), which retired the kits; the popup's shell and row-slot reuse
  stands.
- **The Scan AH button's tooltip never appeared while it was disabled**, which
  is whenever the Auction House is closed. A disabled Button fires no OnEnter
  unless `SetMotionScriptsWhileDisabled(true)` is set; Blizzard's own
  `UIButtonMixin:SetDisabledTooltip` does the same. `MakeScanAHButton` now sets
  it, and resets it in its `OnRelease` because the AceGUI frame is pooled.
  Location: `GUI/SharedWidgets.lua`.

### Improvements

- **The never-shown Shopping List tab and its Reagent Watch list are deleted as
  dead code.** `MainWindow` has no tab for `GUI/ShoppingListTab.lua` and has
  not drawn it since the shopping list moved into the Professions tab (v0.0.15
  era), so its Reagent Watch panel -- the only way to add an item to
  `db.char.reagentWatch` -- could not be reached in game. Removed: the file
  (from all six TOCs), `ReagentWatch`'s `Watch` / `Unwatch` / `IsWatching` /
  `GetWatchedItems`, the `reagentWatch` default, and
  `Tests/shoppinglist_spec.lua`; `PLAYER_LOGIN` drops any saved
  `reagentWatch` table once. Kept: the bag/bank/mail counts, the
  `REAGENT_WATCH_UPDATED` refresh the Cooldowns and Crafting tabs listen for,
  and the shopping-list alert. `Tests/shoppingbank_spec.lua` keeps only its
  `addon.Bank.ShowRequestDialog` cases; the specs that loaded or listed the
  file no longer do. The watch panel's locale strings are left in the 15
  locale files, unused. Suite 1615/0. Also stripped four leftover
  `writ-cannot:` gate markers from spec comments. Location:
  `Modules/ReagentWatch.lua`, `TOGProfessionMaster.lua`, all six TOCs, `Tests/`.
- **The Missing Recipes help told players to click a "+" that does not
  exist.** Its "Row actions" line said "+" adds the scroll to your Reagent
  Watch; the tab has no such button (and the watch list is gone, above). It
  now describes the row's real [Bank] and [AH] buttons. Location:
  `GUI/MainWindow.lua`.
- **LibDBIcon-1.0 is a required dependency; the embedded copies are gone.**
  `libs/LibDBIcon-1.0.lua` and `libs/LibDataBroker-1.1.lua` are deleted, all
  five TOCs list `LibDBIcon-1.0` in `## Dependencies`, and `.pkgmeta` adds
  `libdbicon-1-0` to `required-dependencies`.
- **WoW Forever support, with LibDBIcon embedded there only (temporary).** New
  `TOGProfessionMaster_Camelot.toc` (Interface 16001). LibDBIcon-1.0 is not
  yet published for Forever, so that TOC alone loads
  `Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` then
  `Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua` (byte-for-byte copies of the
  standalone v12.0.3: MINOR 4 and 56) before any addon code, and lists
  LibDBIcon-1.0 under `## OptionalDeps` instead of `## Dependencies`, so a
  standalone copy still wins when a player has one. The other five TOCs are
  unchanged. `Tests/loadorder_spec.lua` pins it. To undo once LibDBIcon ships
  for Forever: delete the two TOC lines and both `Libs` folders, move
  LibDBIcon-1.0 back into `_Camelot`'s `## Dependencies`, and empty
  `FOREVER_EMBEDS` in that spec. Not tested in a Forever client.
- **Specs.** New `Tests/skilltiers_spec.lua` covers the unanchored-tier rule.
  `Tests/craftingtab_draw_spec.lua` checks that the Craft button's only anchor
  is the holder, that it lands at the panel's spot, and that it follows the
  panel when the panel moves. `Tests/craftqueue_spec.lua` checks the Craft All
  run end and prompt. `Tests/sisterguild_spec.lua` checks the pull gate's
  argument order. `Tests/shoppingbank_spec.lua` clicks the Missing Reagents
  [Bank] button and checks the dialog's name and link. `Tests/gui_draw_spec.lua`
  checks that the Professions header bar is the same frame across redraws, and
  that the disabled Scan AH button shows its tooltip and releases a clean frame
  (red with the flag removed); that a Cooldowns redraw creates no frames and
  returns every kit (red with the free list bypassed); and that a reused kit
  keeps no click, reagent column, mail button or bank item from its previous
  row. `Tests/cooldowndraw_spec.lua` checks that reopening the popup builds no
  frames, and its one-mail-button spec now counts SHOWN buttons, since pooled
  row slots own hidden ones. `Tests/tooltiphooks_spec.lua` now counts only `Show` hooks,
  because the Ace lifecycle's own `hooksecurefunc` calls at `PLAYER_LOGIN` were
  inflating the count. The harness pin moved from 82eb99e to 7008976 in its own
  commit, then to f7742d1: on 7008976 the full suite ran past ten minutes
  without finishing while every spec file passed alone. The harness named
  d77ed4f (its reset now drops the old UIParent's children, a ~5x slowdown
  in one process) as the likely cause; the commits were not bisected.
  Whole suite 1639/0 on f7742d1.
- **LibAceGUIWidgets-1.0 is a required dependency (MINOR 36), and the window
  code it replaces is gone (adoption in progress).** All five TOCs and
  `.pkgmeta` list it; `addon.W` holds it when MINOR >= 36. Moved to the library
  so far:
  - `addon.GUI.AttachTooltip` and `addon.AceGUIFrameScripts` are pass-throughs
    to `AttachWidgetTooltip` / `WidgetFrameScripts`. The old tooltip helper
    enabled the mouse on a pooled Dropdown/EditBox frame and never turned it
    off; the library restores it. The label-offset, search-box, header-glow and
    sort-icon cleanups ride `W:OnWidgetRelease`, so none of them takes the
    widget's one `OnRelease` callback; the sort-icon cleanup that was copied into
    the AH Profit and Cooldowns tabs now lives once in the icon helper.
  - Main window: `PersistWindow` + `SetWindowProfile` (the resizable tabs share
    one profile; the old `browserWidth`/`browserHeight` move into it once),
    `SetWindowScale`, `SetWindowOpacity` (re-applied after each tab draw, and
    now reaching the tab panes too), `DressBottomRow` for the help and gear
    icons (help tooltip `tipMinWidth` 280), and `EscapeLayer` for Escape
    (popup first, then the window). Behaviour change: closing the window now
    also closes the [Bank] request dialog and the Cooldowns popup; the dialog
    used to outlive the window it came from. The window stays clamped to the
    screen while open (`PersistWindow` clamps only on restore), and the pooled
    frame's own clamp setting is put back on release. The `OnSizeChanged` resize hook was a
    `HookScript` on the pooled frame, added again on every open and never
    removable; it is now a `WidgetFrameScripts` script restored on Release.
    The gear's proxy-clearing workaround is gone: the options panel is an
    AceConfigDialog window, and the start of its `Open` wraps
    `CloseSpecialWindows` rather than calling it (Ace3
    `AceConfigDialog-3.0.lua:1853-1860`; the rest of `Open` not read, and not
    yet tried in game). A resizable profile's size is saved on Release by the
    library itself since MINOR 36 (LibAceGUIWidgets thread 7481d3a5); the
    `MainWindow:_SaveResizableSize` stand-in written earlier in this release
    is removed.
  - The Cooldowns group popup is placed by `AnchorPopup`;
    `addon.Tooltip.AnchorFrame` and its four specs are removed.
  - The crafter-online edge flash is `W:FlashScreen` (four flat edge bars in
    place of the low-health texture). New `Tests/crafteralert_spec.lua`.
  - The Reagent Tracker is a RowList: cropped icons, `hoverHighlight`, a
    `[Bank]` button column (`show`/`text`/`tip`, with the per-banker lines from
    the new `addon.Bank.StatusText`), and `fitContent` sizing the window. New
    specs in `Tests/reagenttracker_spec.lua`.
  - The Guild tab's profession -> specialisation -> member tree is
    `CreateExpandableList`, built once per session and parked in each draw's
    fill-height group (`AttachRawFrames` hands it back on release). A toggle
    re-lays the list instead of redrawing the tab, and the expand state now
    survives a guild-data refresh. The tab's scroll position is no longer saved
    across a /reload (the list scrolls itself; it was `PersistentScroll`).
    `BuildTree` specs in `Tests/guildtab_spec.lua`.
  - The Profit Planner's rows are a RowList, built once per session on a host
    the tab owns and parked in each draw's group (new `addon.GUI.ParkList`,
    because `RowList:New` hooks its parent's scripts for good and must never be
    given a pooled AceGUI frame). The list draws the headers, sort arrow,
    banding, hover highlight and scrollbar; it is `externalSort`, so `SortRows`
    still orders the rows (source by its label, ties by recipe). The raw
    36-row pool, the hand-built header bar, the scrollbar `OnValueChanged`
    swap and a `scroll.LayoutFinished` override on a pooled ScrollFrame are
    gone. Each subtab's scroll position is kept in rows by the new
    `addon.GUI.ListScroll`. The row tooltip now goes through
    `addon.Tooltip.Owner`, so it opens above a row in the lower half of the
    screen instead of always below. Specs in `Tests/gui_draw_spec.lua`;
    `env.drawTab` now anchors its container, since nothing inside an
    unanchored one had a real height.
  - Missing Recipes is a RowList the same way: `externalSort` over the
    existing `SortList`, `[Bank]` and `[AH]` as button columns (`show` /
    `text` / `tip`; the scan's `onRefresh` just repaints the list), and a row
    tooltip that also names the selected profession for the recipe block in a
    single-profession view (it passed nil before). Gone: the 35-row pool,
    `UpdateVirtualRows`, the hand-built header, `AnchorAll`, and two
    overrides on pooled AceGUI widgets -- the result ScrollFrame's
    `LayoutFinished` and the sub-tab TabGroup's, which is now AceGUI's own
    `SetAutoAdjustHeight(false)` (reset by AceGUI on release). Behaviour
    change: the "12 Missing Recipes" count moved from the first column's
    header to the window's status bar, as the Profit Planner's row count
    already is, because a header whose text changes on every search would
    rebuild the list's header and every row's cells. Specs in
    `Tests/gui_draw_spec.lua`, including the row tooltip driven for real.
  - Cooldowns is a RowList too, which replaces the row kits added earlier in
    this release (`NewRowKit` / `AcquireRowKit` / `DrawRow`), the
    `ComputeCol2InnerWidths` width budget and its specs, the hand-built
    headers, the ScrollFrame and the per-row AceGUI SimpleGroups. Each part of
    the old row is a column: the TBC/Wrath spec-bonus icon, the character
    (right-click anywhere on a row still whispers), the cooldown icon, the name
    as a button cell (`[+]` on a group row, a left click opens the popup under
    it), the reagent (white or grey by bag stock, repainted on
    `REAGENT_WATCH_UPDATED`, left click links it), then `[AH]`, `[Bank]`, mail
    and the "!" alarm as button columns, and the time. The reagent-tint
    registry is gone; a cold reagent name or icon asks the client once and
    repaints the list when it answers. The group popup is unchanged. The
    Cooldowns cold draw on the reporter's saved database fell from 266-407 ms
    (over its 250 ms budget on this machine) to 25 ms. `cooldowndraw_spec`'s
    27 specs, which assert on the drawn text, colours and the popup click,
    pass against the new list unchanged; the two kit specs in
    `gui_draw_spec` are now a no-new-frames-on-redraw spec and a pooled-row
    spec, and the name column's 80 px floor is pinned from the declared
    widths. `env.drawTab` now gives its container `SetAutoAdjustHeight(false)`
    before its size, as the window's all-sides-anchored TabGroup behaves:
    the harness fires `OnSizeChanged` synchronously and an empty auto-height
    SimpleGroup shrank itself back to 0.
  - Crafting: the recipe list is a RowList with the profession's category
    rows as group headers (`sortCycle = "three"` gives the third header click
    back to the tree), the queue is a reorderable RowList handing drops to
    `CraftQueue:Move`, the panels sit in a `NewDockLayout` the tab owns for
    the session (no more `container.LayoutFinished` or scroll `LayoutFinished`
    overrides, no `DetachPool`), the quantity box is `CreateStepper`, and the
    Craft button is `CreateSecureActionButton`, built lazily because the
    factory refuses in combat. The Profit Planner jump now uses
    `ScrollToEntry(..., { context = 2, ifNeeded = true })`, and
    `Tests/craftscroll_spec.lua` drives it end to end instead of pinning the
    retired `ScrollToRow` arithmetic. Suite 1624/0 at that point; not run in
    game.
  - The Professions list, the Bank dialog and the toolbars are still
    hand-rolled.

  Location: `TOGProfessionMaster.lua`, `Compat.lua`, `GUI/MainWindow.lua`,
  `GUI/SharedWidgets.lua`, `GUI/CooldownsTab.lua`, `GUI/AHProfitTab.lua`,
  `GUI/ReagentTracker.lua`, all five TOCs, `.pkgmeta`, `Tests/env_togpm.lua`.
- **26 weak spec assertions fixed** (Writ's peer review, thread feed68df):
  `is_nil` on a literal key now names its key once, shared by the setup and the
  assertion, with a positive assertion first where the key could have been
  absent. `Tests/pricefacade_spec.lua` now seeds the orphaned `ahPrices` store,
  so its removal is exercised.

---

## [v1.1.1] (2026-09-16) - The [Bank] request dialog follows TOGBank's enforced request limit and places shop orders

### Bug Fixes

- **The [Bank] dialog offered more than TOGBank would accept, then blamed
  syncing.** TOGBank's `Guild:AddRequest` now ENFORCES the officer's maximum
  request % (its SETTINGS-CANON-001, peer-review thread 17a1f2c9): per bank,
  less the requester's OPEN orders of that item from that bank. Our dialog
  capped at that percent of the WHOLE GUILD's stock and ignored open orders, so
  with Abe holding 10 and Zed 30 at 50% it offered 20 from Abe, where TOGBank
  allows 5 (fewer with orders open), and Send printed "Request failed. Check
  that TOGBankClassic is synced." in place of the reason. The ceiling is now
  `TOGBankClassic_Guild:RequestAllowance` for the selected banker, recomputed
  when the banker dropdown changes; an order over it is refused in the dialog
  with TOGBank's own `RequestLimitText` sentence; and any refusal from
  `AddRequest` (limit, ordering closed, not for sale) prints the sentence it
  returned. At 100% the ceiling is that banker's stock. Against a TOGBank
  without `RequestAllowance` the old whole-guild percent is kept, since nothing
  there enforces one. New `addon.Bank.RequestAllowance`. Location: `Compat.lua`.
- **Every [Bank] order was refused while TOGBank's shop was selling.**
  `AddRequest` refuses an order not marked `shopOrder = true` while the shop
  sells (TOGBank SHOP-NOFREE-001), and this dialog never marked one. It now
  merges `TOGBankClassic_Guild:ShopOrderFields(itemId)` (TOGBank's
  SHOP-ORDER-API-001, built for this button) into the request -- the mark and
  the estimate -- and shows its `prompt` line in the dialog, which grows to fit.
  The fields are taken when the dialog opens, so the estimate written is the one
  the player was shown. Found by an independent review of the change above.
  Location: `Compat.lua`.
- **Three smaller dialog defects from the same review.** (a) The allowance was
  computed only at open; an order filled while the dialog sat open raised it,
  and the stale figure refused an order TOGBank would take -- it is re-checked
  at Send now, keeping the typed quantity. (b) The stock line read "Bank stock:
  40 | Max requestable: 5 (50%)", pairing the whole guild's stock with one
  banker's cap; it shows the stock the percent is of. (c) A view-only banker
  (visible, not requestable -- TOGBank VIEWBANK-001) could be the pre-selected
  banker and every Send refused; view-only bankers are no longer offered, and
  when only they hold the item the dialog says so instead of opening.
  Location: `Compat.lua`.
- Sixteen specs in `Tests/compat_spec.lua` drive the real dialog (open, pick a
  banker, type, Send, read chat). Mutation runs: with the allowance and the
  reason switched off 6 go red; with the four review fixes switched off 6 go
  red; the rest pin behaviour that was already right and stay green by design.

---

## [v1.1.0] (2026-09-14) - Prices and the Auction House scan move to ItemDB; one mail per cooldown, every reagent split and attached from one click

### New Features

- **Every [Bank] button carries TOGBank's staleness dot.** The user, of the
  green dots beside each banker in TOGBank's own Browse list: *"i would like
  to add those dots next to the items in TOGPM as well if they have the bank
  button available, so folks can tell at a glance if it's stale or not."* The
  dot in front of [Bank] is TOGBank's own per-banker verdict
  (`TOGBankClassic_Guild:GetAltStaleness`, the accessor its Browse and Bankers
  lists read): green when our copy of that bank is current, red when a newer
  copy is published and being fetched (or the copy is in the old format),
  yellow when a peer has offered a newer copy, grey when the only newer copy
  is on a client that cannot send it. One button stands for every banker
  holding the item, so its dot is the WORST of theirs -- a red among greens
  is what the glance is for -- and hovering the button lists each banker with
  its count and status word. The colours are read from TOGBank's
  `TOGBankClassic_UI_Browse.STATE_COLOR` / `STATE_TEXT` when that window is
  present, so a palette change there reaches these dots without an edit here;
  against a TOGBank that predates the accessor the button reads exactly as
  before, with no dot. Every site that used to hard-code the green `[Bank]`
  label now goes through one `addon.Bank.Decorate` (the Professions detail and
  recipe rows, the shopping-list reagent rows, the Cooldowns main row and its
  transmute popup, the Crafting tab's reagents, the Missing Recipes scrolls,
  the Reagent Tracker, and the Shopping List's two AceGUI buttons); the
  buttons are ~10px wider for the bullet. Location: `Compat.lua`
  (`GetBanksWithItem` now carries `state`; `ItemState`, `StateColor`,
  `StateText`, `ButtonText`, `Decorate`, `AddStatusLines`), the eight GUI
  files above. Specs: `Tests/compat_spec.lua` ("the staleness dot on [Bank]",
  nine examples -- worst-wins, the palette read-through and its fallback, the
  no-dot degrade, that an AceGUI widget is never left carrying the item id,
  and the tooltip rows).

### Improvements

- **The Cooldowns tab's mail button sends ONE mail per cooldown per character,
  with every reagent of that cooldown on it.** The user's report: an Arcanite
  transmute (Thorium Bar + Arcane Crystal) cost the sender two mails, because
  the transmute popup drew a mail button on every reagent row and each one
  mailed its own reagent. The reagent rows stay -- each keeps its own [AH] and
  [Bank] request, which is what the rows are for -- but the mail button now
  sits on the first row of each cooldown only and carries the whole reagent
  list; the main (single-reagent) rows go through the same path with a
  one-item list. In the user's words: *"split ALL the components for the
  cooldown and attach ALL the components to the mail ... ONE mail/order
  fulfill button"*, then *"it's the one shot button, but per character"*.

  **One click does the whole thing.** The click plans every reagent against
  the bags first and touches nothing until the plan is whole: a reagent that
  cannot be covered blocks the send and EVERY shortfall is printed together
  (not just the first), and a plan needing more stacks than a mail's twelve
  slots is refused up front. Then every stack that needs splitting is split
  from that click -- 0.25s apart, each piece placed into an empty bag slot
  chosen before the first split (a placed piece is invisible to the container
  API until its deferred pickup fires, so choosing per split would hand every
  piece the same slot), 0.1s after its split so the cursor has cleared before
  the next split loads it. The attach step runs after the last placement,
  waits a few ticks for any piece that has not committed to its slot, and
  then attaches the pieces and the whole stacks in order. The confirmation
  popup ("Split N from stack of M?") and its "click Mail again" second click
  are gone. The sequence is TOGBankClassic's fulfil path (MULTIFILL-002),
  which is in players' hands.

  **All-or-nothing at the attach too.** A stack the plan counted on that is no
  longer where it was (moved between the click and the attach) fails its
  pickup; rather than send the rest under a summary naming the whole plan,
  everything already attached is taken back off the mail (the client's
  right-click detach) and the click is reported as failed, so the next click
  re-plans against the bags as they are. The occupancy test is
  `HasSendMailItem` over every slot -- the client's own (Classic Era
  `MailFrame.lua:881`); the old `if GetSendMailItem(1)` read the item NAME,
  which is nil for an item the client has not cached, and read slot 1 only.
  Locations: `GUI/CooldownsTab.lua` (`CdMail_PlanSupplyMail`,
  `CdMail_PrepareSupplyMail`, `CdMail_AttachSupplyMail`, `ShowGroupPopup`),
  `Locale/enUS.lua`, `docs/FEATURES.md`. Specs: `Tests/cooldownmail_spec.lua`
  (new, 23 examples over the harness's real bags, cursor and send-mail
  slots), `Tests/cooldowndraw_spec.lua` (a two-reagent transmute draws two
  reagent rows and ONE mail button, and clicking it puts both on one mail).

### Bug Fixes

- **The mail body from the transmute popup named the spell where the product
  belongs.** The user's first in-game mail read "Please use these materials to
  make Transmute: Arcanite. Please send me the Transmute: Arcanite" -- the
  popup handed the row's display name (the spell) to the body. It now resolves
  the recipe's crafted item first ("Arcanite Bar") and falls back to the old
  chain only for an entry with no recipe. Pinned in `Tests/cooldowndraw_spec.lua`.
  Location: `GUI/CooldownsTab.lua` (`ShowGroupPopup`).
- **The [Bank] button counted stock held by EX-bankers.** `addon.Bank.GetStock`
  walked every record in TOGBankClassic's `Info.alts`, which keeps a
  character's stored inventory after their bank note is removed -- so a
  retired banker still holding 20 Linen Cloth lit the button and reported 20
  in stock against a request nobody could fill. `GetBanksWithItem` already
  walked `GetBanks()` (the current bankers); `GetStock` is now the sum of it,
  one implementation. TOGBankClassic's peer review (thread 5eef0788, F2);
  its F1 -- read through `GetAltItemTotal` rather than the legacy rows -- was
  already in place since v1.0.10. Location: `Compat.lua`, `Tests/compat_spec.lua`.
- **The planner's "nothing fits, split the largest" branch was dead, and
  nothing pinned the property the split call depends on.** The branch before
  it already returns for every case it handled (any stack larger than the
  need qualifies there), so it could never run; removed. The split call
  refuses `amount >= count`, and the mail path now leans on the planner never
  asking for that -- so a spec walks every layout of up to four stacks of
  1..6 against every need up to 12 (10,000+ cases) and asserts the split, when
  there is one, is strictly inside its stack and the fulfilled total is exact.
  Location: `GUI/CooldownsTab.lua` (`CdMail_CalculateFulfillmentPlan`),
  `Tests/cooldownrows_spec.lua`.
- **The "Attached ..." chat line was erroring on the zhTW, zhCN and koKR
  clients.** Those three translations had the `%s` and `%dx %s` arguments in
  the other order, so `string.format` was handed a name where it expected a
  number. The line is now one list string ("Attached 1x Thorium Bar, 1x Arcane
  Crystal for Bob.") under a new key that every locale falls back to enUS
  for; the old key and the unused "no empty bag slot" key are removed from
  all 13 locale files. Location: `Locale/*.lua`.

- **The Crafting tab's "AH price" line for the crafted item ignored Auctioneer
  and TSM.** It read `Price.Get` and then accepted the answer only when its
  source id was Auctionator's or the own scan's, so a player whose only price
  source was Auctioneer or TSM never saw a sale price or a profit there, while
  the Profit Planner (which reads `GetSaleLive`) showed both. Found while
  porting the ladder; the line now reads `GetSaleLive` like the planner does.
  Location: `GUI/CraftingTab.lua` (`RefreshDetail`).

### Price sources move to ItemDB

- **Pricing, the AH scanner and every third-party price bridge now live in
  ItemDB (LibItemDB-1.0 MINOR 25), and this addon reads them from there.**
  The user's directive: *"we need to move those 3rd party integrations into
  itemDB now"*, then, once ItemDB was tested in game (its scan priced 524
  items; `/itemdb price` answered "Item 8952: 20 (TradeSkillMaster, Market
  value)" on Old Blanchy), *"i think you can get the pricing data from ItemDB
  now. also, the [AH] button funcitonality needs to tie into that for pricing
  and seaching as well"*. One copy of the Auctionator / Auctioneer / TSM
  adapters, one realm+faction scan store and one set of source toggles now
  serve every TOG addon; TOGBankClassic's storefront reads the same numbers.
  What this addon keeps is its POLICY over those numbers, which the library
  deliberately does not carry: a vendor-sold reagent is costed at the vendor
  price whatever the AH says (the 2026-09-11 directive), the crafting-cost
  sum with its BoP exclusion and lower-bound / stale flags, the vendor SELL
  row, and the source labels and colours every tab paints provenance with.
  - `Modules/Price.lua` is a facade: `Get` / `GetSaleLive` /
    `GetSaleHistorical` read `DB:GetPrice(id, "best" | "historical")`,
    `GetVendorBuy` reads `DB:GetVendorBuyPrice`, `Money` uses
    `DB:FormatMoney`. The three-return shape (copper, source, age) is
    unchanged, so the ~20 call sites across the tabs did not move. Everything
    is feature-gated on the METHOD, never a MINOR: against an older ItemDB the
    AH tiers answer nil, the static vendor tier still answers through
    `GetVendorBasePrice`, and nothing raises.
  - `Modules/AHScanner.lua` is the `addon.AH` facade over ItemDB's scanner --
    `IsOpen`, `SearchFor`, `StartScan`, `StartFullScan`, `CancelScan`, the
    progress reads and `GetListingsFor` -- installed only when the ItemDB in
    play carries `StartTargetedScan`, which is what every tab's `if addon.AH`
    degrade was written for. **The per-row [AH] buttons therefore gate on
    ItemDB's scan results and search through ItemDB**, and the shared Scan AH
    button drives ItemDB's targeted scan. The two addon events the tabs
    subscribe to (`AH_OPEN_STATE_CHANGED`, `AH_SCAN_COMPLETE`) are re-fired
    from the library's `LibItemDB_AuctionHouse` / `LibItemDB_ScanComplete`
    callbacks in one place. The "TOGPM Scan" button on the AH frame is gone
    (ItemDB draws its own at the same anchor; the two had rendered on top of
    each other in the user's screenshot). Two defects ItemDB's suite found
    while porting went with the code: a cancelled targeted scan left its
    next-item timer armed, and the Auctionator "historical" read reached for
    an API that does not exist and silently fell back to the live price.
  - **Settings: the nine price-source toggles and the scan delay are one
    button, "Price sources (ItemDB)...", which opens ItemDB's own window
    (`/itemdb`)** -- sources, precedence and statistic are set there once for
    every TOG addon. **A player's earlier choices carry over on first login**:
    `addon:MigratePriceSettingsToItemDB` writes each profile value that
    differs from ItemDB's default into `DB:SetPriceSetting` (parents before
    their fallbacks, since ItemDB turns a fallback off with its parent; never
    a `false` for the TSM App Helper toggle, whose ItemDB default is ON and
    which gates TSM's region-wide figures -- this addon's old default was
    OFF, so a stored false was the default, not a choice), ONCE PER ACCOUNT
    (stamped in `db.global`; ItemDB's settings are per account and ours were
    per profile, so the first character to log in after the update is the
    one whose choices carry), then clears the profile's copies and drops the
    orphaned `factionrealm.ahPrices` / `vendorPrices` scan store. Scanned
    prices are not migrated -- one scan refills ItemDB's store.
  - The Profit Planner's source filter reads `DB:GetPriceSources()` -- the
    library's registry, detection and enablement -- instead of probing the
    third-party globals itself; the Historical subtab offers only sources that
    carry a `historical` statistic. A filter saved by an older build folds its
    per-statistic keys onto ItemDB's provider ids (`togpm-ah` -> `scan`,
    `auctioneer-live` / `-cached` / `-app` -> `auctioneer`, `tsm-live` /
    `-history` -> `tsm`, `auctionator-history` -> `auctionator`).
    `addon.PriceSourceLabels` / `PriceSourceColors`, the Crafting tab's
    `[SCAN]` / `[AUC]` / `[AUCN]` / `[TSM]` badges and the help-panel legend are
    keyed by the same ids.
  - Locations: `Modules/Price.lua`, `Modules/AHScanner.lua`,
    `TOGProfessionMaster.lua` (source tables, `dumpprice`,
    `MigratePriceSettingsToItemDB`), `GUI/Settings.lua`, `GUI/AHProfitTab.lua`,
    `GUI/CraftingTab.lua`, `GUI/MainWindow.lua`, `Locale/*.lua` (sixteen
    settings keys retired, two added), `docs/FEATURES.md`. Specs:
    `Tests/price_spec.lua` (rewritten over the REAL ItemDB price files via the
    new `env.priceDB()`; the bridge, store and merchant-capture cases moved to
    ItemDB's `Tests/price_spec.lua` with the code), `Tests/pricefacade_spec.lua`
    (new: the `addon.AH` facade, the migration, the Profit Planner's filter, the
    Settings button), `Tests/craftingtab_spec.lua`; `Tests/ahfullscan_spec.lua`
    and `Tests/ahscanner_spec.lua` deleted (65 examples in ItemDB's
    `Tests/pricescan_spec.lua`). 100% line coverage on both modules.
  - Requires ItemDB carrying LibItemDB-1.0 MINOR 25 for any auction price;
    the [AH] buttons and the Scan AH button do not appear against an older
    one. Contract threads with ItemDB: 6b52f51f (the trigger, quoting the
    user's in-game test), 5bb73440 (the per-account stamp).

### Test harness

- **`Tests/wowapi` moves from `813f3d2` to `82eb99e`** (a month of Adoption
  log). What it cost here: the harness now dispatches `OnSizeChanged`, so
  `craftscroll_spec.lua`'s fixture -- which set a content height by hand on
  an AceGUI ScrollFrame with no children -- had AceGUI's own layout reset the
  height to 0 and four examples went red. The fixture now installs the no-op
  `LayoutFinished` exactly as `CraftingTab:Draw` does before `FillList`; the
  addon code was already right. The pin is what makes the cursor and send-mail
  slots above available offline. Location: `Tests/craftscroll_spec.lua`.

---

## [v1.0.10] (2026-09-14) - The allied-guild list and rosters move into GuildRoster, and the pause came back intermittently; /togpm perf now says whose it is

### Improvements

- **The allied ("sister") guild list and the allied rosters live in GuildRoster
  now, once, for every TOG addon.** The user's direction, 2026-09-13, on the
  same names being wanted in TOGTools' mail autocomplete and in TOGBankClassic:
  *"i need that and i need it to not step on each other"* / *"probably best
  to do it in the library"*. Since v0.10.1 TOGPM kept the list in its own
  settings, gossiped it to the guild on its own prefix, pulled an allied
  roster over a DeltaSync RosterSync host, persisted the roster in its own
  guild database and relayed it on a second prefix -- and every other addon
  wanting the same rosters would have needed all of that too, three lists
  that could disagree and three feeders doing wipe-and-replace into one
  store. LibGuildRoster-1.0 MINOR 18 (GuildRoster 0.7.0) owns every one of
  those now: the list in `LibGuildRosterDB` keyed by home guild, the officer
  gate, the gossip, the pull (its own two messages over WHISPER -- no
  DeltaSync needed on either end), the persistence, the login re-feed and the
  relay. TOGPM is a reader: `GetSisterGuilds` / `GetSisterGuildKeys` /
  `IsSisterGuildKey` resolve against the library, the Settings input edits
  through `SetSisterGuildNames` (the library refuses a non-officer itself),
  and the guild-scoped views refresh on the library's `OnSisterConfigChanged`
  and `OnSisterRosterUpdated`. `/togpm pullroster <Name>` is
  `lib:PullSisterRoster` plus TOGPM's own profession-data request to the same
  peer, which stays: recipes, cooldowns and skills are TOGPM's data and still
  travel over DeltaSync with the consent proof both sides check, gated on the
  library's list.

  **An older build's list and rosters are imported once.** On the first
  roster-ready after upgrading, `profile.sisterGuilds` (with its stamp) and
  `guild.sisterRosters` move into the library's store and the TOGPM copies
  are deleted, so nobody re-types a list an officer already typed and TOGPM
  can never feed the store again. Written directly rather than through the
  officer-gated setter, because the importing character is usually a member
  who held the list by gossip; the library's last-writer rule is kept, so a
  list the library already holds with a newer stamp wins. The library gossips
  whatever it holds on its own timer.

  **What is gone from TOGPM:** the `TOGPMxgc` / `TOGPMxgr` prefixes, the
  12-minute config timer, the 5-minute roster timer, the hash-suppressed
  relay, the RosterSync host, `PersistSisterRoster` / `RefeedSisterRosters` /
  `DropSisterGuildData`, and the delivery-verdict callback on those sends --
  TOGPM no longer makes any AceComm send of its own. The two AceDB defaults
  are removed too (a re-created empty table would have hidden "moved" from
  "never had one"). Under a GuildRoster older than 0.7.0 cross-guild is
  simply off -- every reader answers "nothing configured" and the Settings
  input says which version is needed -- rather than half-working from a list
  only TOGPM could see. Locations: `TOGProfessionMaster.lua` (the
  cross-guild configuration section, `MigrateSisterGuildsToLibrary`,
  `PullSisterRoster`, `OnEnable`), `Scanner.lua` (`InitDeltaSync`),
  `GUI/Settings.lua`, `Locale/enUS.lua`.

  **Tests:** `Tests/sisterguild_spec.lua` (25 specs) drives the real
  library: the readers answer from `LibGuildRosterDB` and TOGPM's settings
  stay empty; the import moves a list and its rosters, keeps a newer list the
  library holds, drops an unlisted roster, never overwrites a roster the
  library persisted, is idempotent, and leaves the copies alone under an old
  library; the library's callbacks reach `GUILD_DATA_UPDATED`; the removed
  feeders are pinned absent. Mutation-checked: with the list move disabled,
  four specs go red. The 29 specs that pinned the removed feeders
  (`purge_spec`, `scanner_broadcast_spec`) are gone with them.
  `Tests/env_guild.lua` adopts three MINOR-18 resets from GuildRoster's copy
  (the library's SavedVariables, ChatThrottleLib's queue, stale AceComm
  registrations) so one spec's roster cannot be re-fed into the next.
  Whole suite 1538/1538. **Not run in a client.** What proves it in game: an
  upgraded client whose officer had a list sees it under `/guildroster
  sisters` after the first login, and `/togpm pullroster <Name>` on a member
  of that guild prints "sister roster updated" and the Cross-Guild
  diagnostics list the roster under "Persisted allied rosters
  (LibGuildRoster)".

- **`/togpm perf` reads the client's own addon profiler.** The 4-5 s pause
  from v1.0.9 returned, intermittently. The marks added then covered only
  the sections this addon chose to time -- the window open, the tab draws,
  the synchronous list build -- so a pause with no window open recorded
  nothing, and no mark of ours could say whether another addon's frame was
  the one that stalled. The client keeps that record itself: `C_AddOnProfiler`
  (present on Classic Era, per `AddOnProfilerDocumentation.lua`) tracks every
  loaded addon's worst single frame since login and how many of its frames
  ran over 100 / 500 / 1000 ms. `/togpm perf` now prints the whole-client
  peak, the all-addons peak, this addon's own peak and hitch counts, and the
  five addons with the highest peaks. A 4 s frame is on that list against
  whoever owned it -- and a large whole-client peak beside small addon
  peaks means no addon's Lua was running during the pause at all. Location:
  `TOGProfessionMaster.lua` (`PrintPerf`).

  **One thing the profiler cannot do, found from its own rules:** an
  `OnEvent` script is charged to the addon that created the frame, and
  AceEvent / AceAddon / AceTimer each own one frame -- so for every addon
  that loads Ace3 from the standalone folder (this one included), its
  login work, its events and its timers are all charged to "Ace3", pooled
  with every other such addon's. The operator's first paste showed exactly
  that: TOGProfessionMaster 38 ms worst frame, "Ace3" 995 ms, and no way to
  split the second number. So the login path times itself (next entry).

- **The login path measured, and timed in game.** The operator: *"it
  'glitched' on login. i told you, this happens ON LOGIN"*. Every
  synchronous stage of TOGPM's login -- the three `OnInitialize`
  migrations, `RebuildAltGroups`, the first-load hash rebuild, the name
  scrub, the +2 s scans and hash broadcast, both backfills -- now runs in
  order against the operator's real database in `Tests/openperf_spec.lua`
  ("the login path"), with a 100 ms per-stage budget: **11 ms of Lua in
  total**, the largest stage the hash rebuild at 8 ms. The wire cost of
  every crafters leaf as a peer would send it -- `BuildLeafPayload`, then
  DeltaSync's `SerializeWithChecksum` (AceSerializer plus a byte-by-byte
  Lua checksum) and `DeserializeWithChecksum` -- is measured the same way:
  the largest, Cooking at 4,878 pairs / 158 KB, costs 10 ms to receive.
  Nothing in this addon's login accounts for seconds. What the suite still
  cannot run is the client's item-cache work inside the +3 s / +4 s
  backfills and the +2 s scans, so those timers, and the entering-world
  stage, now record a mark past 50 ms. Locations: `Scanner.lua`
  (`timedLogin`, the PEW hook), `Tests/openperf_spec.lua`,
  `Tests/perf_spec.lua`.

- **The profiler is now watched, not only read, so a stall gets a clock
  time.** The first paste after a 5 s pause (2026-09-12) answered WHOSE:
  this addon's worst frame 21 ms with no frame over 100 ms; AllTheThings'
  7,675 ms; the whole client's 7,718 ms, so the frame was addon Lua and
  almost all of it one addon's. It could not answer WHEN, which is the half
  a pause report needs: `PeakTime` is a high-water mark, so once one
  addon's login frame sets it a later 5 s frame by anyone smaller never
  moves it, and the hitch counts are cumulative with no clock. From
  `PLAYER_ENTERING_WORLD`, once a second, the all-addon count of frames
  over 500 ms is compared to its last read; a rise is a stall that happened
  in that second and leaves a "Client stall" mark with the wall-clock time,
  the new all-addon peak when it set one, and the addons whose own counts
  moved -- each with its peak. Counts baseline at zero, so the first tick
  puts the login load itself on the clock. Every mark now prints its clock
  time, and the printout carries the attribution rule beside the addon
  list so an "Ace3 1028 ms" line is never read as Ace3's own doing. One
  C call per quiet second. Location: `TOGProfessionMaster.lua`
  (`Perf.WatchStalls`, `PrintPerf`).

- **The two sections that run with nothing open are now timed.** The
  background warm tick and the sync merge were the untimed candidates for
  an intermittent pause; each now records a mark when it runs past 50 ms
  (`Perf.SLOW_MS`), with the resume count or the leaf count and byte size.
  Quiet ones record nothing, so the 40-entry ring keeps the marks that
  matter. Locations: `TOGProfessionMaster.lua` (Warmer), `Scanner.lua`
  (`OnGuildDataReceived`).

### Bug Fixes

- **Four presence guards vetoed the item calls they were guarding, and on a
  client with deprecation fallbacks off one of them hid every untagged
  high-ID Era recipe.** Audit findings 29-33, the deprecation-fallback sweep
  that v1.0.8 started. The v1.0.8 sweep routed the item calls through
  `addon.Item` (which prefers `C_Item.*` and answers nil itself) but left
  `if GetItemInfo then`-shaped guards above four of them, testing the BARE
  name -- a deprecation-fallback alias that is nil when the
  `loadDeprecationFallbacks` CVar is off. On that client the guard was
  false, the resolver would have answered through `C_Item`, and the branch
  was skipped anyway: `Modules/RecipeGate.lua` returned "untagged" for every
  untagged post-Vanilla recipe (gone from the UI, silently);
  `Scanner:BackfillReagentItemIds` aborted its whole pass printing
  "GetItemInfoInstant unavailable", which was false on the client printing
  it; the Missing Recipes tooltip and crafted-item icon degraded quietly. The
  four guards are gone (the backfill one now tests EITHER spelling), and the
  rule that stops it recurring is written where the resolver lives
  (`Compat.lua`, THE GUARD RULE): a bare global gets a presence guard if and
  only if it is a deprecation fallback, and a name routed through the
  resolver never does. Each site is pinned with the bare alias absent and
  `C_Item` present.

  **`ScanSaltShaker` never tried `C_Item.GetItemCooldown`.** Its ladder
  reached `C_Container.GetItemCooldown` and the bare `GetItemCooldown` --
  which is on the deprecated list (`Deprecated_ItemScript.lua:52`) -- so on
  a client where the container copy is absent or answers nothing AND the
  fallbacks are off, both tiers missed and the Salt Shaker seeded Ready:
  verbatim the bug the comment beside it claimed was covered. It was also
  the one bare, unguarded item-API call left in the addon.
  `addon.Item.GetCooldown` joins the resolver and is the second tier;
  mutation-checked (old ladder back: the finding-31 spec goes red).

  **The `GetSpellInfo and GetSpellInfo(id)` idiom is gone from all thirteen
  sites** that carried it, because it taught a false rule: `GetSpellInfo` is
  in no `Deprecated_*` file in either Classic tree and Blizzard's own UI
  calls it bare, so a guard on it can never be false -- and the same idiom
  applied by name shape rather than by family is exactly where the four
  wrong item guards came from. **Three `Compat.lua` shims with no production
  caller are deleted** -- `addon.GetAddOnMetadata`, `addon:GetSpellInfo`,
  `addon:GetItemInfo` -- along with the three spec cases that vouched for
  them; `addon.Version` (the copy that actually runs, resolved in the main
  file because it loads before Compat) is now asserted instead. Locations:
  `Compat.lua`, `Scanner.lua` (`BackfillReagentItemIds`, `ScanSaltShaker`),
  `Modules/RecipeGate.lua`, `GUI/MissingRecipesTab.lua`, and the twelve
  one-line guard removals. Suite 1543/1543.

- **The background warm's frame budget could stop working if any addon
  reset the shared profiler timer.** The Warmer bounded each tick with
  `debugprofilestop()`, which is one global timer that `debugprofilestart()`
  -- callable by any addon at any moment -- resets to zero. A reset between
  the tick's two reads makes the difference hugely negative and the budget
  never trips, so the whole warm queue (every profession's list build,
  tooltip scrapes included) drains in one frame. No addon on the
  development machine calls it, so this is not the operator's pause, but
  it is exactly the shape of one and any player's addon set could trigger
  it. `Perf.now` now prefers `GetTimePreciseSec()`, which has no shared
  state -- the same clock Blizzard's own console uses to budget its
  coroutine -- and the Warmer budgets on `Perf.now`. Spec pinned with the
  shared timer stubbed at zero: one resume per tick with the fix, all five
  queued tasks drained without it. Location: `TOGProfessionMaster.lua`.

- **Test env:** a reference `C_AddOnProfiler` model in `Tests/env_togpm.lua`
  (the harness ships none) with the Classic Era enum values; `Tests/perf_spec.lua`
  covers the clock preference, the budget, both slow-section marks, the
  login-path marks, the profiler read-out and the stall watch, 18 specs.
  Suite 1539/1539 at the time (1538/1538 after the allied-guild move above);
  `TOGProfessionMaster.lua` at 100% line coverage.

---

## [v1.0.9] (2026-09-11) - Background opacity, vendor reagents cost the vendor price, hunters get their pet-training window back, a reagent named "Item #15417", a shopping list that spilled out of the window, and a slow open measured

### New Features

- **Background opacity slider** (Settings -> Display -> "Background opacity",
  20-100%). Fades the window's two fills -- the frame's black backdrop and
  the tab pane's grey one -- and nothing else, so text, borders, icons and
  rows stay fully readable over the world behind the window. Frame alpha
  would have faded the contents too, which is not the ask. Applies live while
  the window is open. The stock AceGUI colours are put back before the
  widgets return to the pool, because both the Frame and the TabGroup are
  recycled across addons and neither resets its backdrop colour on release --
  a faded fill would otherwise surface in the next addon to acquire them.
  Six specs, mutation-checked: disabling the apply turns three red, skipping
  the restore turns the pool guard red. Locations: `GUI/MainWindow.lua`,
  `GUI/Settings.lua`, `Locale/enUS.lua`.

### Bug Fixes

- **Crafting cost and profit priced a vendor-sold reagent at whatever
  someone had listed it for on the Auction House.** Reported on Discord
  2026-08-23: *"it seems togpm uses the auction house price for easy to
  obtain vendor items like vials"* -- and the follow-up, *"when calculating
  profit margins, it should use the vendor price of reagents when
  applicable, not the ah price"*. Every reagent cost went through
  `Price.Get`, whose ladder is auction sources first and vendor last,
  because it answers "what is this worth" -- the right question for the item
  you are about to sell and the wrong one for a Crystal Vial, which nobody
  buys off the AH. One player listing vials at 5g made every alchemy
  recipe's cost, and its profit, wrong for everyone who scanned.

  New `Price.GetReagentCost`: vendor buy price first (Auctionator's vendor
  cache, our captured merchant prices, ItemDB's static table -- the existing
  `GetVendorBuy` ladder, unchanged), and the AH ladder only for a reagent no
  vendor sells. Both crafting-cost functions and the Crafting tab's
  per-reagent line use it, so the line and the total agree. `Price.Get` is
  untouched -- the crafted item's sale price still comes from the AH. Eight
  specs in `Tests/price_spec.lua`, including one that reproduces the report
  through `Price.Get`; with the vendor tier removed, five go red. The
  "Crafting Cost" header tooltip says which price a reagent gets, and the
  thirteen untranslated English copies of that tooltip in the other locale
  files are gone -- they fall back to enUS, so the text lives once.
  Locations: `Modules/Price.lua`, `GUI/CraftingTab.lua`, `Locale/`.

- **Scan AH on the Crafting tab never looked up the crafted item.** Same
  Discord thread: *"when I select a recipe in the crafting tab and hit scan
  AH, it does not search and update the value of the actual crafted item,
  only the mats"*. The scan list was built from the reagents alone, so the
  detail panel's AH price and Profit line -- which read the crafted item's
  price -- had nothing to show unless another addon had it. The list now
  starts with the crafted item, resolved from the recipe's item link exactly
  as the profit line resolves it; an enchant has no crafted item and scans
  its reagents as before. `CraftingTab:ScanAHItems` is the one place the
  list is built; four specs in `Tests/craftingtab_draw_spec.lua`. Location:
  `GUI/CraftingTab.lua`.

- **The shopping list in the Professions tab spilled out of the window.**
  Reported on Discord 2026-08-28 with a screenshot, and reproduced with
  ElvUI switched off: six Shadoweave recipes on the list, all expanded --
  about 28 rows -- and the section drew every one at full height. It had no
  height cap: an InlineGroup sized to its rows, so past a dozen or so it was
  taller than the tab, and the column headers and the recipe list (which
  anchor below it) were pushed out through the bottom of the frame.

  The section is now capped at 40% of the tab's height (never fewer than
  four rows, ten before the first layout) and the rows scroll inside it --
  a native ScrollFrame with a slider on the right and mouse-wheel support,
  the same pattern the detail panel has used since v0.9. The scroll frame
  is owned by the tab and re-parented on every fill, so it is detached
  from the pooled InlineGroup on release like the rows already were. A
  list that fits gets no slider and no reserved margin; one that shrinks
  under the cap snaps its scroll offset back so rows are never left
  scrolled out of view. Five specs in `Tests/browserdetail_spec.lua`,
  including one that reproduces the report's row count; the clamp case
  goes red with the clamp removed. Location: `GUI/BrowserTab.lua`.

- **The window's title bar could sit above the top of the screen, out of
  reach.** Same Discord thread, 2026-08-30; the reporter's workaround was
  dropping UI scale to 65%. The saved position (top/left) is restored
  verbatim, and one saved under a different UI scale or resolution -- the
  coordinate space is 768/uiScale units tall -- can land outside the
  screen the player has now, where the title bar cannot be dragged. The
  frame is now clamped to the screen, which the client applies to restored
  positions as well as drags (Blizzard's own `FrameUtil.lua` has to switch
  it off to animate a frame out of view). And a saved Browser/Crafting
  size is capped at the screen in the frame's scaled units, so clamping
  cannot trade an off-screen top for an off-screen bottom. Three specs in
  `Tests/mainwindow_spec.lua`. Location: `GUI/MainWindow.lua`.

- **On TBC, Wrath, Cataclysm and Mists, guild sync could silently stay off
  for a whole session.** Audit finding 34, from GuildRoster's review of
  2026-08-26, confirmed on the release vet: `GuildRoster` was declared in
  `## Dependencies` on the Classic Era TOC and on none of the other four.
  That header is a load-order declaration -- undeclared, the client may load
  TOGPM before the GuildRoster addon, `LibStub("LibGuildRoster-1.0", true)`
  answers nil at login, `Scanner:InitDeltaSync` returns, and guild sync is
  off until the next `/reload`, with one debug line as the only trace. From
  the player's seat it looks like a quiet guild. All five TOCs now declare
  the same dependencies, and `Tests/loadorder_spec.lua` asserts the five
  `## Dependencies` / `## OptionalDeps` headers are identical and that every
  hard-required library is listed -- a drift like this cannot land green
  again. Locations: `TOGProfessionMaster_TBC.toc`, `_Wrath.toc`, `_Cata.toc`,
  `_Mists.toc`.

- **A hunter could not train pets with the crafting takeover on.** Reported
  from Discord, 2026-09-10: *"hunter training skill conflicts in classic with
  TOGPM causing it to not be usable to train pets"*. Classic Era and TBC only.

  On Vanilla/TBC, Beast Training opens the same window as Enchanting --
  Blizzard's CraftFrame -- and fires the same `CRAFT_SHOW`. With the takeover
  on, the engine unregisters that event from UIParent and CraftFrame at init
  so it can put its own Crafting tab up instead. That is right for
  Enchanting and wrong for Beast Training: the only window that can teach a
  pet never appears, and the Crafting tab opens on a session it cannot read
  (no skill line, so nothing to show). The hunter is left with nothing.

  The engine now checks how Blizzard's own frame tells the two apart --
  `GetCraftDisplaySkillLine()` returns the profession's name for Enchanting
  and nil for Beast Training, which is why CraftFrame hides its rank bar there
  -- and hands a pet-training session straight to Blizzard's window: no tab,
  no toggle button, no "last UI" record, no foreign-window suppression. In
  hands-off mode the window was never suppressed and nothing changes. Ten
  specs in `Tests/pettraining_spec.lua`, including the Enchanting control that
  reproduces the takeover. Location: `Modules/Crafting/CraftingEngine.lua`.

- **A reagent could render as "Item #15417" beside its own real icon.** Reported
  in game on Devilsaur Gauntlets: Rugged Leather and Rune Thread by name,
  Devilsaur Leather as a number, with the correct leather icon next to it.

  The reagent tables are built once, when the recipe list is, and a
  `GetItemInfo` cache miss at that moment wrote the placeholder into the
  table for good. The icon beside it is re-fetched at draw time, so it was the
  only part of the row that noticed the cache warming up. Worse than the
  display: the shopping list persists that table into SavedVariables, so the
  placeholder survived a reload, and the [AH] button would have searched the
  auction house for the literal string.

  Names now resolve through `addon:ResolveReagentName` -- the client cache
  first (localized), then LibItemDB's shipped name, then the placeholder as a
  last resort -- and every draw site calls it instead of reading the stored
  name, so a placeholder written cold heals the first time it is drawn warm
  and writes the real name back. A name LibItemDB knows never reaches the
  screen as a number, and it never has to wait for the cache. Eleven specs in
  `Tests/reagentname_spec.lua` pin the resolver; five more drive the real
  draw paths end to end -- the detail pane built cold and redrawn warm, a
  placeholder already in the shopping-list SavedVariable, and the row
  tooltip's Reagents line -- in `Tests/browserdetail_spec.lua` and
  `Tests/browservirtual_spec.lua`, including one that reproduces the report
  verbatim. Locations: `TOGProfessionMaster.lua`, `GUI/BrowserTab.lua`.

- **The alt-group visibility gate walked the whole table on every call, and
  reported any guild member as "an alt of someone".** Found while measuring
  the report below. `IsAltOfInRosterCharacter` is asked once per crafter the
  roster does not list, per list build, and it scanned every key and every
  array in `altGroups` to find the character's own group -- 500 us per call
  against the operator's database (997 keys, 14,095 entries). The table is
  keyed per member, so the group is one lookup; it now is. The scan's owner
  branch also matched a character against itself, which is what made
  `/togpm whyvisible` print "alt of an in-roster character: true" for every
  ordinary guild member (audit finding 36). Gone with the scan. Location:
  `TOGProfessionMaster.lua`.

  Two neighbours closed with it. `IsAltOfKnownCharacter` -- no caller, no
  spec, and a docstring claiming the visibility gate used it (finding 37) --
  is deleted; wiring it in would have kept alive the alts of every ex-member
  still in the database. And the fact the purge depends on, that
  `RebuildAltGroups` files the altClaims arrays themselves rather than
  copies (finding 35), is now stated at the alias, at the purge and at the
  defaults, with `Tests/purge_spec.lua` pinning the one case a "store a
  copy" hardening would break: a character purged from another owner's
  claim stays purged across a rebuild.

### Improvements

- **"Lag on open of 3-5 seconds", reported 2026-09-11 -- measured, two
  things fixed, and an instrument for whatever is left.** The offline suite
  now loads the operator's real SavedVariables (2.4 MB: 1,166 recipes with
  crafters, 35,712 recipe-crafter pairs, 467 crafters) and the full Vanilla
  recipe database, and times every tab's cold draw for real
  (`Tests/openperf_spec.lua`). Result: the Lua behind an open is **under
  200 ms on every tab** -- the Professions list build, the one that runs
  synchronously on a cache miss, is ~170 ms of Lua. Two defects the
  measurement did flag are fixed above and below (the alt-group scan; the
  `altGroups` section of the saved data). With both in, the operator's own
  open lost its pause in game; a later open, right after a `/reload`, paused
  again. That is consistent with a cold cache -- the first open after a
  reload runs the build synchronously, and its client-side half (one tooltip
  render per crafted item, ~1,090, plus a server query per item the client
  has not cached) is the part the harness cannot time. Not confirmed.

  So: **`/togpm perf`** prints every timed section since login -- each window
  open and tab draw, each synchronous list build with its tooltip-scrape share
  broken out -- plus the entry count of every saved-data section. A report
  that pastes it carries the number that decides the next step. Locations:
  `TOGProfessionMaster.lua`, `GUI/MainWindow.lua`, `GUI/BrowserTab.lua`.

- **The saved data no longer carries `altGroups`, which was 16% of the file
  for nothing.** It is a derived view of `altClaims`, rebuilt on every load,
  and keyed per member -- so an account of N characters was written N times
  over: 14,095 entries on disk against 5,637 in the data it is derived from.
  The view is now served through a metatable, which the client's
  SavedVariables writer never sees, and rebuilt at login; every reader and
  writer is unchanged. A copy saved by an older build is dropped on the first
  login. Location: `Scanner.lua`, `TOGProfessionMaster.lua`.

- **Bank stock is read through TOGBankClassic's public accessor, and from
  one place.** Peer review relayed TOGBankClassic's own finding: its v1.4.2
  retires the per-alt `alt.items` rows (no longer written,
  stripped from SavedVariables on load) and reads inventory from a tuple
  store through `Guild:GetAltItemTotal(altName, itemId)`. Our `[Bank]` button, the
  "Bankers:" tooltip line and the request dialog walked those rows directly
  in three places -- `addon.Bank.GetStock`, `GetBanksWithItem`, and a third
  private copy of the same loop in the Cooldowns tab that nothing shared.

  TOGBank then added a compatibility metatable so `alt.items` still answers
  for us, so nothing was broken on the day; but a consumer should not depend
  on a shim another addon maintains for it. All three sites now go through
  one helper that prefers the accessor when the method exists and falls back
  to the rows for an older TOGBank -- feature-detected on the method, not a
  version string, so both shapes are covered without a version table. Roster
  names are normalized through `TOG:NormalizeName` before the store is asked,
  since the store is keyed by the normalized form. Six specs install the
  new shape (accessor present, rows absent), including one that shows the
  old reader returning empty against it. Locations: `Compat.lua`,
  `GUI/CooldownsTab.lua`.

---

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

> Releases v1.0.6 and earlier are in [CHANGELOG_ARCHIVE.md](CHANGELOG_ARCHIVE.md).
