<!-- charset-ok: this file is never drawn by the WoW client. The BigWigs packager
     publishes it verbatim as the GitHub release body and it is read on the
     CurseForge listing -- both render UTF-8, and the em dashes in entries up to
     v1.0.7 are already published under those release tags, so rewriting them
     would make the repo disagree with what people have read. New entries from
     v1.0.8 on use -- and -> . Added 2026-08-19. -->
# TOG Profession Master Changelog

## [v1.3.1] (2026-10-07) - The CurseForge app installs LibDBIcon again; Missing Recipes shows recipe names

### Bug Fixes

- **The CurseForge app stopped installing LibDBIcon on every client except WoW
  Forever.** The copy of LibDBIcon bundled for the Forever TOC still had the
  packager's `@curseforge-project-slug: libdbicon-1-0@` marker on line 1. The
  BigWigs packager scans every packaged `.lua` for that marker and lists the
  slug as an embedded library for the whole upload, which overrides
  `.pkgmeta`'s `required-dependencies` (release.sh 1880-1890). So the upload told
  CurseForge LibDBIcon was embedded, and the app did not install the standalone
  addon that the Era, TBC, Wrath, Cata, Mists and Retail TOCs need before they
  can load. The marker is removed, and `Tests/loadorder_spec.lua` (PKG-EMBED-001)
  now fails if either Forever-embedded file carries one. Found by
  TOGBankClassic's and Peer Review's audits (inbox 5503f91c, 5d7eaf86). Whether
  the v1.3.0 file on CurseForge shows LibDBIcon as embedded was not checked on
  the site. Location: `Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua`.
- **Missing Recipes cut recipe names to about ten characters and the window
  could not be widened** (Discord, 2026-10-07: "I cannot read what the recipe is
  without scrolling over it and there is no way to move columns to the right to
  read it"). The tab was locked at 720x500 to match Cooldowns, and Sources took
  a fixed 180 px for a word like "Drop". Recipe is the list's auto-width column,
  so it got only what was left over. The tab is now resizable and shares the
  saved size of Professions, Crafting and Profit Planner, and Sources sizes to
  its widest text (`autoFit`, minimum 60), so the space goes to Recipe. Three
  specs in `Tests/missingrecipes_spec.lua`. Verified in game (operator,
  2026-10-07: "the rows are indeed much wider"). Location:
  `GUI/MissingRecipesTab.lua`, `GUI/MainWindow.lua` (comments).
- **The shopping list on the Professions tab could draw as an empty box with a
  scrollbar** (operator, 2026-10-07: "i can't see the stuff on my shopping list
  anymore", one recipe on the list). Since the move to the LibAceGUIWidgets
  RowList in v1.2.0, the section was sized to exactly its rows plus the
  InlineGroup's 40 px of chrome. The client snaps anchors to whole pixels, so the
  row area could come out a fraction short. The RowList floors height / row
  height, so one row became zero, and a longer list lost its last row. The
  section now gets 2 px of slack (`SL_SLACK`). A new spec in
  `Tests/browserdetail_spec.lua` takes half a pixel off the content and
  requires the one row to still draw; it fails without the slack. The diagnosis
  is read from the code and fits the screenshot, but not yet confirmed in game.
  Location: `GUI/BrowserTab.lua`.

---

## [v1.3.0] (2026-10-04) - Retail support; WoW Forever's borrowed ProfessionDB values are shown as unconfirmed

### New Features

- **Retail (operator, 2026-10-04: "lets add retail support, i belive PDB was
  updated enough for that").** A new `TOGProfessionMaster_Mainline.toc`
  (Interface 120005 / 120007 / 120100) loads the same files with the same
  dependencies as every other TOC; each required library already lists those
  interfaces, and LibProfessionDB MINOR 13 ships its own Retail data tree.
  Retail runs the C_TradeSkillUI scan and craft path built for WoW Forever.
  `addon.isRetail` (Interface 100000+, the bound LibProfessionDB uses) makes
  Jewelcrafting, Inscription and Archaeology available and hides First Aid.
  Retail has no single expansion skill cap, so `addon.SKILL_CAP` is nil there
  and the Guild tab shows the scanned max. Retail recipes carry a per-expansion
  `skillLine`, and their skill numbers are on that line's scale: the new
  `addon:GetRecipeSkillRank` reads the local character's rank for that line
  live (`C_TradeSkillUI.GetProfessionInfoBySkillLineID`) for "Can learn now" and
  the scroll tooltip's Requires line, and answers "unknown" (no gate) for
  another character, whose per-line ranks are not synced yet. The profession
  registry refresh no longer requires `GetNumSkillLines`, which Retail lacks;
  `GetProfessions` serves. `wow-version-replication.ps1` now also replicates to
  `_retail_`. Loads and scans in game (operator, 2026-10-04: "retail opens now
  without errors, i was able to populate my retail data in"). Location: `TOGProfessionMaster_Mainline.toc`,
  `Compat.lua`, `TOGProfessionMaster.lua`, `Scanner.lua`, `GUI/GuildTab.lua`,
  `GUI/MissingRecipesTab.lua`, `GUI/SharedWidgets.lua`, `Modules/CommTest.lua`,
  `Tests/compat_spec.lua`, `Tests/loadorder_spec.lua`.
- **Retail: every character's per-expansion skill syncs, so alts are gated too.**
  A profession record may carry `lines` (`[skillLine] = { skillRank, skillMax }`),
  recorded by the owner's window scan from `C_TradeSkillUI.GetChildProfessionInfos`
  and sent as an optional `l` field on the owner's existing `professions:` leaf,
  re-minted by the owner only (peers adopt the hash as before). Only a Retail
  scan writes `lines`, so a Classic client's payload and minted hash are
  unchanged, and the v1.2.0 reader ignores `l`. `GetRecipeSkillRank` answers
  another character's synced line rank. Four writers that rebuilt a profession
  record from scratch now keep its `lines`. On Retail the profession-level rank
  has one writer, the profession registry (`GetProfessionInfo`); the window scan
  no longer overwrites it with the open line's rank, which would have flipped
  the record and re-minted the leaf whenever the two differed. Location: `Scanner.lua`,
  `Modules/HashManager.lua`, `Compat.lua`, `Tests/retaillines_spec.lua`.

### Bug Fixes

- **Retail: recipe names had no quality colour, and "Can learn now" could hide
  every recipe (operator, in game 2026-10-04).** Newer Retail recipes ship from
  ProfessionDB with only their plans' `itemId` and no `craftedItemId` (1229652
  Blood Knight's Mercy), so the row had no crafted item to colour by;
  `GetRecipeCraftedItemId` now falls back to the client's
  `C_TradeSkillUI.GetRecipeSchematic(id, false).outputItemID`, cached per recipe
  (ProfessionDB asked for the field). `ItemLink.QualityHex` also reads Retail's
  `|cnIQ<n>:` link colour and a quality string with or without its `|c`. And with
  no profession window open, Retail's `GetProfessionInfoBySkillLineID` answers
  skill 0 for a line the character has (`/run` in game printed 0), which "Can
  learn now" read as a rank; `GetRecipeSkillRank` now treats 0 as unknown and
  falls back to the rank recorded at the last scan. Location:
  `TOGProfessionMaster.lua`, `GUI/SharedWidgets.lua`, `Compat.lua`,
  `Tests/compat_spec.lua`.
- **Retail: a scan of one expansion could strip the others' recipes.** The
  merge removed the character from EVERY recipe of the profession before
  re-adding what the scan listed, and whether Retail's recipe list covers every
  expansion line or only the open one is not verified. A Retail scan now removes
  the character only from recipes on the lines it actually covered (the recipe
  DB's `skillLine`, else `GetTradeSkillLineForRecipe`); an unlearned recipe on a
  scanned line is still removed. A re-scan listing a recipe whose line cannot be
  placed no longer reports a change and redraws every time. Classic and Forever
  are unchanged. Location: `Scanner.lua`, `Tests/retaillines_spec.lua`.

- **WoW Forever: a skill value ProfessionDB borrowed from Vanilla anchored the
  orange skill-up tier (LibProfessionDB MINOR 13 notice, thread 9ac3ba2a).** The
  tiers are unanchored when `difficulty[1] == 1` and `requiredSkill` is absent
  OR borrowed (`IsBorrowed(id, "requiredSkill")`), feature-detected so older
  ProfessionDB builds behave as before. The recipe id now reaches every
  `FormatSkillTiers` call. The Missing Recipes skill sort used the raw first
  tier, so placeholder tiers sorted as skill 1; it now uses the same learn-skill
  rule as the "Can learn now" gate. Location: `TOGProfessionMaster.lua`,
  `Modules/Crafting/CraftingEngine.lua`, `GUI/CraftingTab.lua`,
  `GUI/MissingRecipesTab.lua`, `GUI/SharedWidgets.lua`, `Tests/borrowed_spec.lua`.

- **Missing Recipes said "Unknown" for recipes ItemDB knows where to get
  (operator, 2026-10-04: "itemdb has a lot of the drop info, and you're showing
  it as unkown").** The Sources cell read only ProfessionDB's sources, and Retail
  ships none, so a row whose [Where] listed a quest and a vendor said "Unknown".
  When ProfessionDB has no sources for a recipe, the cell now names the kinds of
  place LibItemDB knows for its scroll -- the same rows [Where] opens, with the
  same faction filter -- mapped to the usual labels (Drop and Boss as Drop,
  Vendor, Quest, Crafted, Object as Container), and the Sources sort uses the
  same text. Worked out once per row. Location: `GUI/MissingRecipesTab.lua`,
  `Tests/missingrecipes_spec.lua`.

### Improvements

- **Borrowed values are shown and marked unconfirmed (operator's direction via
  ProfessionDB).** The Requires line reads "(85, unconfirmed)", and the recipe
  Sources heading and Missing Recipes source text say "unconfirmed" when
  ProfessionDB borrowed them. A recipe hidden only by a borrowed "never
  implemented" flag is no longer hidden. Location: `GUI/SharedWidgets.lua`,
  `GUI/MissingRecipesTab.lua`, `Modules/RecipeGate.lua`, `Locale/enUS.lua`,
  `Tests/recipegate_spec.lua`.
- **A recipe shown only on a borrowed "never implemented" flag says so.** Its
  Professions and Missing Recipes rows and the detail panel header read
  "Name (unconfirmed)", and its tooltip adds "Unconfirmed: this recipe may not
  exist in this version of the game." -- outside the recipe-detail block, so the
  "never" setting cannot hide it. `RecipeGate:IsUnconfirmed` and the gate read
  the flag through one helper, so a recipe the gate let through on a borrowed
  flag is always the one marked. Location: `Modules/RecipeGate.lua`,
  `GUI/BrowserTab.lua`, `GUI/MissingRecipesTab.lua`, `GUI/SharedWidgets.lua`,
  `Locale/enUS.lua`, `Tests/borrowed_spec.lua`, `Tests/browserdetail_spec.lua`.
- **The Professions and Guild tabs build their lists with less work.** Three
  `openperf_spec` budgets failed in the 2026-10-04 run (the All-professions
  list build 349 ms, the Browser cold draw up to 526 ms, both against 250 ms).
  Profiled, not guessed: the guild-tag hash ran 541 times per build and is now
  cached per guild key (registration still runs every call); each crafter's
  display name and online state is resolved once per build instead of once per
  recipe; the crafter sorts no longer build a comparator per recipe; the search
  text is one `table.concat`; and the Guild tab's counts ask the guild-scope
  check once per character instead of once per recipe-crafter pair (~37k calls
  for ~700 characters). Same output, specs unchanged. Location:
  `TOGProfessionMaster.lua`, `GUI/BrowserTab.lua`, `GUI/GuildTab.lua`.
- **The perf budgets measure TOGPM, not the machine.** On Windows `os.clock` is
  wall time (Microsoft's CRT `clock()` "doesn't strictly conform to ISO C"), so
  one sample includes whatever else the box is doing: across 2026-10-04's runs
  the same Profit Planner draw read 27 to 1089 ms. `Tests/wowapi` moves from
  `515873b` to `99111aa` (WoWAPITesting `953768d`: `bit` 5-12x faster, and
  `wow.bestTime`, inbox 0822420a). Every repeatable budget now gates on the
  fastest of five runs; `RebuildOnFirstLoad`, which works only on its first call,
  is timed five times on a fresh copy of the tables it writes. The other login
  stages mutate the database and still run once. The wire budget times every
  crafters leaf once and re-times only the worst five times: five passes over
  every leaf ran the file past the runner's 60 s limit under load. Even best of
  five cannot beat a machine pinned for the whole run (the Professions draw read
  402 ms at 100% CPU, 72 ms on a quieter run), so the budgets moved out of the
  default suite: `Tests/openperf_spec.lua` is now `Tests/perf/openperf.lua`,
  outside the runner's `*_spec.lua` pattern, and `.writ-suites.json` declares it
  as its own suite to run on purpose (WoWAPITesting's answer, inbox d53bb661).
  The same file suppresses `.busted`, which must never be run directly. Location:
  `Tests/openperf_spec.lua`, `Tests/wowapi`.

---

## [v1.2.0] (2026-10-01) - Every window and list moves to LibAceGUIWidgets; WoW Forever: the Crafting tab works, and Forever characters' recipes sync

### New Features

- **[Where] on Missing Recipes rows: where to buy or farm the pattern
  (Discord request 2026-09-29, "add integration with questbook to lead you to
  where patterns are sold/dropped").** A [Where] button on each row whose
  recipe scroll LibItemDB knows a source for opens ItemDB's "Where to get it"
  window on that scroll: every vendor, drop and zone, with coordinates. With
  Questbook installed, clicking a place there guides the player to it -- ItemDB
  hands the waypoint to Questbook (`LibItemDB:WhereTrack`), so TOGPM never
  talks to Questbook and works the same without it. No button for a
  trainer-taught recipe (no scroll), for a scroll with no known source (WoW
  Forever's ItemDB ships no places data), or with a LibItemDB older than the
  window. Whether a row has sources is asked once per row, not on every
  paint. The Professions tab has no [Where] yet: its rows are recipes someone
  already knows. Not yet tried in game. Location: `GUI/MissingRecipesTab.lua`,
  `Locale/enUS.lua`, `Tests/missingrecipes_spec.lua`.
- **[Guide] on the Missing Recipes tab and a stop icon on the window: start
  and cancel Questbook's route from TOGPM (operator, 2026-10-01: "give us the guide
  route/cancel route inside TOGPM too").** With Questbook installed, a [Guide]
  button on each row hands the best place for the recipe scroll straight to
  Questbook -- one in the player's current zone first, then a vendor, then the
  highest drop chance -- and says in chat where it is guiding to; [Where] still
  opens the full list to pick another. The window's bottom row carries
  Questbook's own stop control beside the gear, on every tab (operator: "use
  the same button/function from questbook"): its red X
  (`ReadyCheck-NotReady`), dimmed to 0.4 while Questbook guides to nothing
  (Questbook's public `IsTracking`, re-checked four times a second while the
  window is open, since guiding can start from Questbook itself), with its
  tooltip, and Questbook's universal stop. A first cut put a "Stop Guide"
  button on the Missing Recipes toolbar, where it wrapped onto a row of its own
  and existed on that one tab (in game, 2026-10-01); removed. The route and the
  stop go through LibItemDB (`WhereTrack` / `WhereStopTracking`); TOGPM only
  checks that Questbook is installed, with the same test LibItemDB makes, and
  reads `IsTracking` for the dim. Without Questbook neither control is drawn:
  the route is Questbook's, and ItemDB's data alone gives the places and
  coordinates but no arrow. Questbook is added to `## OptionalDeps` in all six
  TOCs. The route was confirmed working in game by the operator (2026-10-01);
  the stop icon is not yet tried there. Location:
  `GUI/MissingRecipesTab.lua`, `GUI/MainWindow.lua`, `Locale/enUS.lua`, all six
  TOCs, `.luacheckrc`, `.luarc.json`, `Tests/missingrecipes_spec.lua`,
  `Tests/toolbar_spec.lua`.

### Bug Fixes

- **The Crafting tab's Enchant button stayed greyed out and could not be
  clicked, even with the materials in the bags (Discord, 2026-09-29, Classic
  Hardcore, v1.1.2).** Since v1.1.2 the secure Craft/Enchant button lives on
  its own holder outside the window, placed over the detail panel at the
  panel's frame level + 10. The window is Toplevel
  (`AceGUIContainer-Frame.lua:194`), so any click on it Raises it within
  FULLSCREEN_DIALOG -- above the button, which is not its descendant. The
  watcher that keeps the button over the panel compared only position and
  scale, so it never noticed: the button sat under the panel's backdrop
  (dimmed) and the panel took its clicks. The watcher's key now includes the
  panel's frame level, and the button is stacked 100 levels above the panel
  (the Cooldowns popup's margin) so it also clears the panel's own children.
  It affected the Craft button for every profession, not only Enchanting.
  Spec: the button stays above the panel after it is raised. Not yet tried in
  game. Location: `GUI/CraftingTab.lua`, `Tests/craftingtab_draw_spec.lua`.
- **The Cooldowns tab's [Bank] button raised "attempt to index local
  'anchorBelow' (a number value)" (in game, 2026-09-30).** Its click passed
  `select(2, addon.Item.GetInfo(id))` as the LAST argument to
  `addon.Bank.ShowRequestDialog`, so every return after the link spilled
  into the dialog's fourth parameter, `anchorBelow`, and the dialog indexed a
  number. The group popup's [Bank] carried the same call. Both now wrap the
  `select` in parentheses, which keeps it to one value, and the dialog anchors
  only to a frame, so a stray value can no longer stop it opening. Spec:
  the popup's [Bank] hands the dialog exactly three arguments. Location:
  `GUI/CooldownsTab.lua`, `Compat.lua`, `Tests/cooldowndraw_spec.lua`.
- **WoW Forever: clicking the Crafting tab raised ADDON_ACTION_BLOCKED for
  `CastSpellByName()` (in-game report, 2026-09-28), and the tab could not read
  or craft anything there.** `Engine:OpenProfession` opened a profession by
  casting it; the report's stack is the tab click, a hardware event, so Forever
  blocks that cast from addon code even on a click, where Classic Era allows it.
  And every read and craft went through the classic trade-skill globals
  (`GetTradeSkillLine` / `GetNumTradeSkills` / `GetTradeSkillInfo` /
  `DoTradeSkill`), which Forever does not have at all -- not in its source tree,
  not even as deprecation fallbacks. The engine now has a second path on
  `C_TradeSkillUI`, the API Forever's own Professions UI uses, taken only where
  the classic globals are absent (`addon:HasModernTradeSkillAPI()`):
  - **Open:** `C_TradeSkillUI.OpenTradeSkill(skillLineID)` on the profession's
    skill line, from the tab click, the dropdown and a Profit Planner jump.
    warcraft.wiki.gg marks it restricted with the hwevent tag only, so a click
    may call it. No Open button on Forever (operator, 2026-09-29: "you should
    not have added the button"). **UNRESOLVED:** a tab click still raised
    ADDON_ACTION_BLOCKED for `OpenTradeSkill()` on some clicks only (in game,
    2026-09-29). A secure button and a "use your profession book" prompt were
    both tried and removed the same day. Every attempt is now recorded
    (`Engine:_LogOpenAttempt`: trigger, skill line, the open base and child
    profession, first call of the session, calls in the same frame, combat,
    mouse button, whether Blizzard_Professions is loaded, the result, a stack)
    and paired with any `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN`, which is announced
    in chat. `/togpm opendebug` prints the record. Peer Review's leading
    hypothesis (thread 4d8158c1): Blizzard's own callers skip OpenTradeSkill
    when that profession is already open, and the tab does not.
  - **Switching professions from the dropdown drew the old one** (in game,
    2026-09-29: the K window "pops up briefly, a flicker, then closes, and it
    doesn't change to the tradeskill i select"). A switch while a profession is
    open lands on `TRADE_SKILL_LIST_UPDATE` once the new data source is built,
    not on `TRADE_SKILL_SHOW` -- which is where Blizzard's own window switches,
    yielding while `IsDataSourceChanging()` (`Blizzard_ProfessionsFrame.lua`
    :138-161). The engine treated that update as a light refresh, so the tab
    kept the old profession. It now redraws the whole tab when the update shows
    a profession other than the one last drawn (`Engine._drawnProf`), and also
    listens for `TRADE_SKILL_DATA_SOURCE_CHANGED`. Every event is logged for
    `/togpm opendebug`.
  - **The K key could not open Blizzard's window after the tab had opened a
    profession** (in game, 2026-09-29). The tab's claim on the session hid that
    window on every show. On Forever a show of `ProfessionsFrame` that does not
    follow the tab's own open within `OWN_OPEN_WINDOW` (2 seconds: a margin I
    chose, not measured; the event log records the real gap) is now the player's
    choice: the window stays and the claim is dropped, as the WoW UI button
    does. Classic's frames keep the old rule. `Tests/pettraining_spec.lua` now
    loads the real `Compat.lua`, which the engine asks on every event.
  - **The dropdown always landed on the last profession tab** (in game,
    2026-09-29; the debug log showed every pick ending on Fishing, "Bait and
    Tackle"). When `ProfessionsFrame` goes from hidden to shown, each of its
    profession tabs that is not the open profession casts its own profession
    spell (`Blizzard_ProfessionsTemplates.lua:963-971`), each cast opening that
    profession, so the last tab wins. The takeover HID the frame, so every open
    from the tab re-showed it and set this off. On Forever the frame is now
    CLOAKED instead -- alpha 0 with mouse input off on it and every frame
    inside it, restored on reveal -- and stays shown, so a switch does not
    re-fire it. Its size is never touched: a first build also scaled it to 1%,
    and the revealed window came up far narrower than Blizzard's normal one
    with its Create bar off the edge (in game, compared against an untouched
    window), and a relayout call to correct that made it worse. The first open,
    which has to show it, asks for the profession a second time once the
    cascade is over. Operator's conditions (2026-09-29): K must show Blizzard's
    window -- the `TOGGLEPROFESSIONBOOK` keys are override-bound to reveal it
    while cloaked, since `ToggleProfessionsBook` would toggle the shown frame
    closed -- and both windows may be up at once: revealing it (K, or the WoW
    UI button) leaves TOGPM open. Closing TOGPM while cloaked closes Blizzard's
    window through its own `HideUIPanel`, ending the session. Not verified in
    game: all of it, including whether the second ask goes through inside the
    same click, and what Escape does with a cloaked frame.
  - **Read:** the open profession from `GetChildProfessionInfo`, falling back to
    `GetBaseProfessionInfo` when the child id is 0, as
    `Blizzard_Professions.lua:1665` does; learned recipes from `GetAllRecipeIDs`
    (falling back to `GetFilteredRecipeIDs`) plus `GetRecipeInfo`, grouped under
    `GetCategoryInfo` names; difficulty from `relativeDifficulty`; reagents from
    `GetRecipeSchematic`'s basic reagent slots with bag counts.
  - **Craft:** `C_TradeSkillUI.CraftRecipe(recipeID, count)`, as
    `Blizzard_ProfessionsTransaction.lua:352` does. The row index on this path
    is the recipe id.
  - **Other windows:** Forever's `ProfessionsFrame` joins `TradeSkillFrame` /
    `CraftFrame` in the foreign-window suppression and the TOGPM toggle button.
  Classic Era, TBC, Wrath, Cata and MoP have the classic globals and never take
  this path. Not verified in game: the cause of the intermittent block,
  whether Forever has `GetAllRecipeIDs`, and whether hiding
  `ProfessionsFrame` keeps the session open. Location:
  `Modules/Crafting/CraftingEngine.lua`, `Compat.lua`, `GUI/CraftingTab.lua`.
- **WoW Forever: a character's own recipes were never recorded or synced to the
  guild (known gap since v1.1.2).** `Scanner:OnTradeSkillEvent` returned early
  without the classic API. New `Scanner:ScanModernTradeSkillInto` records the
  learned recipe ids (spell ids, the key `addon.recipeDB` uses) through the same
  `MergeRecipesIntoGdb`, skill rank and cap included. It skips a linked or
  NPC-crafting session, and it never merges an empty list, which would strip
  every recipe from the character's crafter set while the data is still
  loading. Location: `Scanner.lua`, `Compat.lua`.
- **WoW Forever: switching professions stored one profession's recipes under
  the others.** In game (2026-09-29, debug log) every profession switched to
  scanned "16 recipes", the Blacksmithing count, and the result was broadcast:
  the list the client handed back did not follow the open profession.
  `Scanner:ScanModernTradeSkillInto` now skips while
  `C_TradeSkillUI.IsDataSourceChanging()` (as `Blizzard_ProfessionsFrame.lua`
  :142 does) and keeps only recipes that `GetTradeSkillLineForRecipe` places in
  the open base profession (`ProfessionsUtil.lua:79-82`); a recipe it cannot
  place is kept, as before. A character's wrongly stored recipes are replaced
  the next time each profession is opened and scanned, since a scan rewrites
  that character's whole set for the profession. Specs in
  `Tests/scanner_scan_spec.lua`. Location: `Scanner.lua`.
- **New specs** in `Tests/craftsuppress_spec.lua` for the Forever path: never
  opens through `OpenTradeSkill` and never casts, drops the claim when
  nothing opens, records each attempt (including one that raises), the list,
  the reagents, the craft
  call, and the classic path winning wherever both exist. The spec now loads
  the real `Compat.lua` rather than a copy of its check. `C_TradeSkillUI` is
  added to `.luacheckrc` and `.luarc.json`. The new `CraftUnsupportedClient`
  note (English only) is now shown only on a client with neither trade-skill
  API. The Scanner's Forever scan has no spec yet. Location:
  `Tests/craftsuppress_spec.lua`, `Locale/enUS.lua`.
- **Re-ticking every skill tier on the Professions tab never went back to
  "all tiers".** The toggle ended `self._selectedTiers = all and nil or sel`;
  in Lua `true and nil` is nil, so the expression always yields `sel`, and a
  player who unticked a tier and ticked it again was left on an explicit set
  that no longer grew with the client's tiers and persisted that way. Now an
  `if`. The same idiom in `Modules/CommTest.lua` stored the string "nil" as the
  send error on every successful probe (read only on failure, so never shown);
  fixed the same way. Found by the new `Tests/toolbar_spec.lua`. Location:
  `GUI/BrowserTab.lua`, `Modules/CommTest.lua`.
- **The Professions tab's crafter column re-joined the whole name list for
  every name it tried.** `fitCrafterText` now extends the string one name at a
  time. The cold draw on the reporter-scale database had gone from ~140 ms to
  676 ms against a 250 ms budget; it is 197 ms again. Location:
  `GUI/BrowserTab.lua`.

### Improvements

- **The spell helpers now use the namespaced API first on every client.**
  `addon.Spell.GetInfo` / `GetTexture` / `GetLink` tried the bare global first,
  for a test-only reason: the offline harness had no `C_Spell`. WoWAPITesting
  delivered it (a7675ce, with a WoW Forever build), and `C_Spell.GetSpellInfo`
  / `GetSpellTexture` / `GetSpellLink` / `GetSpellCooldown` are documented on
  Classic Era and Classic (Cata/MoP) as well as Forever, so every client now
  takes the same branch; the bare name is the fallback. `GetInfo`'s second
  return (rank) is nil on this path; no caller reads it. `addon.Spell.IsKnown`
  now asks `C_SpellBook.IsSpellInSpellBook` first too, and its comment was
  wrong: the bare `IsSpellKnown` is a deprecation fallback on Classic Era as
  well, not only on Forever (`Deprecated_SpellBook.lua:16` in the classic_era
  tree). The specs feed spells through the harness's `wow.spells` /
  `wow.knownSpells` instead of stubbing bare globals, and `Tests/compat_spec.lua`
  drops its hand-built `C_Spell` / `C_SpellBook` for the harness's, with a
  Forever case. `Tests/wowapi` moved to 0e90e7d. Location: `Compat.lua`,
  `Tests/compat_spec.lua`, `Tests/scanner_scan_spec.lua`,
  `Tests/scanner_cooldowns_spec.lua`, `Tests/scanner_names_spec.lua`,
  `Tests/recipedetails_spec.lua`.
- **The Professions tab's recipe list and shopping list are LibAceGUIWidgets
  RowLists (LAGW adoption step 5b).** The last two hand-built row pools in the
  addon. The recipe list was 35 raw frames over an AceGUI ScrollFrame, with its
  own header bar, index arithmetic and a container `LayoutFinished` hook that
  anchored the scroll to that header bar and the detail panel -- the hook
  behind v1.0.6's "the list is drawn over the game world after opening
  Settings". It is now a RowList on a host the tab owns for the session
  (`addon.GUI.ParkList`), anchored inside its own group only, with the header,
  hover highlight, selection tint (matched by recipe id, so it survives a
  guild-data rewarm), scroll memory (`ListScroll` key `browser`) and a [Bank]
  button column. The crafter column is fitted with the list's own cell width
  and measure (`fitCrafterText`, now pure), so the `WINDOW_RESIZED` repaint
  nudge is gone. The shopping list is a second RowList: a +/- expander per
  recipe with reagents, reagent rows indented under it, [Bank] / [AH] / "!" /
  [-] qty [+] / [x] as button columns, capped at its share of the tab in whole
  rows and scrolling inside. The tab lays out with Flow so the list and detail
  panel take the rest of its height. Removed: `BuildPool`, `DestroyPool`,
  `UpdateVirtualRows`, `EnsureHeaderBar`, `EnsureShoppingListScroll`,
  `DetachShoppingListPool` and the shopping list's `OnRelease` callback on the
  pooled InlineGroup. The row tooltip is unchanged, now
  `BrowserTab:ShowRowTooltip`. Not yet tried in game. Location:
  `GUI/BrowserTab.lua`, `Tests/browservirtual_spec.lua`,
  `Tests/browserdetail_spec.lua`, `Tests/mainwindow_spec.lua`,
  `Tests/tooltipwrapflag_spec.lua`.
- **The [Bank] request dialog is a LibAceGUIWidgets form dialog (LAGW adoption
  step 6, first part).** `addon.Bank.ShowRequestDialog` built its own frame,
  backdrop, close button, UIDropDownMenu banker picker and fixed heights (165,
  or 205 with the shop line). It is now `W:CreateFormDialog` (MINOR 36, TOGPM
  contract 6cf3b4e4): an item row, the library's dropdown box for the banker, a
  digits-only quantity; the stock line is the hint, "/ max N" a note under the
  quantity, TOGBank's shop line the body, and the dialog sizes itself to what
  shows. It opens where it did (below a given anchor, else beside the main
  window, else centred) through the dialog's own `SetAnchor`. The allowance,
  view-only, shop-order and Send logic is unchanged, and so are the field names
  the rest of the file reads. Not yet tried in game. Location: `Compat.lua`,
  `Tests/compat_spec.lua`.
- **Every tab's toolbar uses LibAceGUIWidgets controls, and the window's
  "don't redraw under the player's hands" check is the library's (LAGW
  adoption step 6).** The Professions, Cooldowns, Missing Recipes, Profit
  Planner and Crafting toolbars had 14 AceGUI Dropdowns, 4 AceGUI EditBoxes
  styled as search fields and 6 AceGUI CheckBoxes. They are now the library's
  dropdown box (single choice, or a tick-box menu that stays open with Select
  All / Clear All rows that act and close it), `LAGW-SearchBox` and
  `CreateCheckbox`, through three shared helpers in `GUI/SharedWidgets.lua`
  (`ToolbarDropdown`, `ToolbarSearch`, `ToolbarCheckbox`, plus `MenuItems`). The
  raw dropdown and check-box frames are built once per tab and parked in each
  draw's slot, so the redraw every guild sync causes creates none. A labelled
  control and its unlabelled neighbours share one height, so a row of them
  lines up. `MainWindow:Refresh` now asks `W:IsMenuOpenFor` (and redraws once,
  through `W:OnMenuClosed`, when the menu closes) and `W:IsInputFocusedIn`
  instead of walking AceGUI's global `AceGUI30Pullout<N>` frames -- which every
  AceGUI addon shares, and which once held this window's redraws forever on
  another addon's leaked pullout. Removed: `addon.GUI.IsAnyDropdownPulloutOpen`,
  `OffsetInputLabel`, `StyleSearchBox`, `IsAnySearchFocused`. Not yet tried in
  game. Location: `GUI/SharedWidgets.lua`, `GUI/MainWindow.lua`,
  `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`, `GUI/MissingRecipesTab.lua`,
  `GUI/AHProfitTab.lua`, `GUI/CraftingTab.lua`.
- **The hand-rolled list and pool helpers are gone (LAGW adoption step 7).**
  With every list a library RowList and every toolbar control the library's,
  nothing called them any more. Removed from `GUI/SharedWidgets.lua`:
  `addon.GUI.DetachPool`, `PersistentScroll` (`Acquire` / `Restore` / `Reset`
  and its LayoutFinished repair), `RowStripe` / `ApplyRowStripe`, the whole
  `addon.GUI.Sort` table (`SetIndicator`, `Indicator`, `Next`, `NextOrNone`,
  `ConfigureHeaderIcon`, `ConfigureCenteredHeaderIcon`), `LiftAboveSizers`,
  `MakeHeaderHoverGlow`, and `MakeColumnHeader`'s `justifyH` / `onClick` /
  `hoverGlow` options (its only caller, the Guild tab, passes none of them).
  The new `Tests/sharedwidgets_spec.lua` (16 cases) covers the paths nothing
  else drove, bringing `GUI/SharedWidgets.lua` to 100% line coverage (661/661).
  The Cooldowns group popup, the last `DetachPool` caller, is parented to
  UIParent for its whole life, so its release now just hides it and its
  click-outside overlay. `addon.GUI.ListScroll` keeps its store in the same
  `db.char.frames.scrollTabs` table. The specs for the removed helpers
  (`gui_pool_spec`, `gui_scroll_spec`, `bottomrow_spec`) are rewritten or
  dropped; `gui_scroll_spec` now specs `ListScroll`. Location:
  `GUI/SharedWidgets.lua`, `GUI/CooldownsTab.lua`.
- **The last hand-built row lists are library RowLists (finishing the
  LibAceGUIWidgets adoption).** Three panels still drew their rows from
  their own frame pools, and each is now a RowList, like every other list in
  the addon:
  - **Professions tab, recipe details:** the panel's own ScrollFrame, slider,
    reagent-row pool and crafter-row pool are gone. Reagents and Known By are
    one list under the header and shopping controls, with the two headings as
    the library's group-heading rows. The list scrolls itself. Reagent counts
    read the shopping-list quantity when drawn, so +/- restates them with a
    refresh. The crafter right-click whisper goes through the list's click
    handler.
  - **Crafting tab, reagents:** the fixed pool of 12 reagent rows and the
    hand-placed "Reagents" / "Cost" labels are replaced by a list whose own
    header carries both headings and their tooltips. The list sizes itself to
    its rows (`fitContent`), and the panel's auto-height reads that. The
    header bar moves the first reagent row down 2 px.
  - **Cooldowns, the group popup:** its pooled rows (name, reagent, [AH],
    [Bank], mail) are a list whose columns switch with `SetColumns` between a
    transmute group and a plain one. The reagent's white/grey is now a colour
    code in the cell rather than a font colour. The popup moves from TOOLTIP
    strata to the main window's FULLSCREEN_DIALOG, with a frame level 100 above
    the window's set on every open, so tooltips draw above it without the old
    frame-level bump. (A first cut set the strata alone and the popup opened
    behind the window, in game 2026-10-01.) The Crafting tab's "Missing
    Materials" label sits inside the reagent list's header bar, right-aligned
    and centred on it (in game it floated above the bar and ran past its end).
  None of it has been tried in game. New specs: the Crafting reagent list
  (7 cases in `craftingtab_draw_spec`), the popup's colours and mail icon, and
  the Known By whisper. Four `browserdetail_spec` and three
  `cooldowndraw_spec` cases that read the old frames now read the list's rows
  and cells instead (test changes approved by the operator 2026-09-30).
  Location: `GUI/BrowserTab.lua`,
  `GUI/CraftingTab.lua`, `GUI/CooldownsTab.lua`,
  `Tests/browserdetail_spec.lua`, `Tests/craftingtab_draw_spec.lua`,
  `Tests/cooldowndraw_spec.lua`.
- **The [Bank] dialog's item keeps hold-to-compare and the chat-link click.**
  Moving the dialog onto the library's form dialog lost both: the library's
  item row drew its own tooltip and click. LibAceGUIWidgets MINOR 39 (TOGPM
  contract 1d7a76ba) lets the row take the consumer's `onEnter` / `onLeave` /
  `onClick`, and the dialog now passes TOGPM's own `ItemLink.SetItem` /
  `EndHover` / `Click`. Against an older library the fields are ignored and
  the built-in hover and click stay. Not yet tried in game. Location:
  `Compat.lua`, `Tests/compat_spec.lua`.
- **A spec corrupted AceGUI's shared widget pool for every file after it.**
  `settingsbleed_spec`'s "never re-anchors" case released the Professions list
  section while it was still listed in its TabGroup's children, so the window's
  later close released that pooled widget a second time. A TabGroup went back
  to the pool with a nil child, and every later spec file's Professions draw
  died in `ReleaseChildren` -- the seven `toolbar_spec` failures that appeared
  only in a full run. The case now takes the section out of the list, as
  AceGUI's own `ReleaseChildren` does. No production code releases a child on
  its own (only `MainWindow` releases, and only the root window).
  `toolbar_spec` now names the error when the Professions draw fails, instead
  of failing on a missing toolbar. Location: `Tests/settingsbleed_spec.lua`,
  `Tests/toolbar_spec.lua`.
- **The offline suite no longer keeps every reload of every tab alive
  (WoWAPITesting thread 83f92459).** Its heap climbed to 377-720 MB and ~85%
  of a 321 s median run was garbage collection. The new
  `Tests/reloadleak_spec.lua` reloads each tab and asserts the old copy is
  collected, printing the reference chain when it is not; five of six were
  held. Two holders, both in the test env: containers `env.drawTab` drew were
  never released, so AceGUI's `_G`-named frames kept the tabs' callbacks; and
  each module reload re-registered on the addon's, AceEvent's and
  LibGuildRoster's callback registries under its own (new) owner key. The env
  now releases drawn containers at each install (collecting every failure and
  raising them together at the end), re-shows a pooled container before
  drawing into it, and drops a replaced module's registrations. Full suite
  1676/0 in 219 s; the heap still ended near 334 MB. A second pass extended
  the spec to every module and found the third holder: Scanner,
  CraftingEngine, MainWindow and MinimapButton `hooksecurefunc` the addon's
  `OnEnable` (Scanner also `OnPlayerEnteringWorld`) at load -- once per
  session in game -- and each spec file's reload wrapped the previous wrapper,
  keeping every older copy alive down the chain. Fixed first with a layer in
  the env, then moved into the harness on TOGPM's request (pin 515873b: a hook
  re-made from the same source line after a reset replaces the earlier one)
  and the env layer deleted; the leak spec now resets between its two loads,
  as between two spec files. 16 module cases added, all collected. Two more found by the full run: AHScanner's
  LibItemDB callback (the env's reload cleanup now covers LibItemDB's
  registry, and the leak spec loads the real LibItemDB), and a reloaded
  `GUI/MinimapButton.lua` got nil from `LDB:NewDataObject` for its own,
  already-held name, so the next `OnEnable` handed LibDBIcon nothing; the file
  now reuses the existing object (in game it loads once, so nothing a player
  sees changes). Full suite 1700/0.
  A spec use of a container after the env released it is NOT guarded: AceGUI's
  pool is private to the library, so a released widget cannot be marked
  without breaking its next owner. `tooltipwrapflag_spec`'s floor comments now
  list each file's remaining tooltip calls. Harness pin 0e90e7d -> 515873b.
  `docs/AUDIT.md` and `Tests/HARNESS_CONTRACT.md` are deleted; findings and
  requests travel through writ's inbox, and git history keeps both boards.
  Location: `Tests/env_togpm.lua`, `Tests/reloadleak_spec.lua`,
  `Tests/tooltipwrapflag_spec.lua`, `CLAUDE.md`.
- **The offline suite runs one full garbage collection per spec file, not per
  example (WoWAPITesting thread 48754b3d).** Its telemetry put the suite at a
  251 s median, the slowest in the fleet, with 89% of example time inside the
  reset's full collections. The harness reset already ran exactly one per
  example, after the env's own release, so its opt-in deferral alone would
  save nothing; the env now turns it on (`wow.deferCollection(true)`) and calls
  `wow.collect()` the first time each spec file installs. Known cost, the
  harness's: inside one spec file, a frame an earlier example discarded is
  still alive and still hears events until the next file. `reloadleak_spec`
  collects for itself and is unaffected. Full suite 1712/0; the whole
  background run, agent overhead included, took 64 s against 206-331 s for
  the day's earlier runs. Location: `Tests/env_togpm.lua`.

---

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

> Releases v1.0.9 and earlier are in [CHANGELOG_ARCHIVE.md](CHANGELOG_ARCHIVE.md).
