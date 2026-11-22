<!-- charset-ok: this file is never drawn by the WoW client. The BigWigs packager
     publishes it verbatim as the GitHub release body and it is read on the
     CurseForge listing -- both render UTF-8, and the em dashes in entries up to
     v1.0.7 are already published under those release tags, so rewriting them
     would make the repo disagree with what people have read. New entries from
     v1.0.8 on use -- and -> . Added 2026-08-19. -->
# Ultimate Profession Master Changelog (formerly TOG Profession Master)

## [v1.11.3] (2026-11-21) - WoW Forever: a blocked Crafting tab says what to do

### Bug Fixes

- **A blocked profession open on WoW Forever left the Crafting tab blank.**
  The client still sometimes refuses `C_TradeSkillUI.OpenTradeSkill` from the
  tab click (`ADDON_ACTION_BLOCKED` "UNKNOWN()", operator's BugSack and taint
  log 2026-11-21: the block is on the call itself, and it happens even on the
  first open after a login). My v1.11.2 note that a first click after a
  `/reload` is safe was wrong. The cause is still not known; another WoW
  Forever addon found the same call blocked from addon code
  (cjber/commissions-forever#194). The tab now says "The game blocked opening
  X this time. Pick it from the menu above, or open it from your spellbook."
  instead of the plain "Open X to view" prompt. `Engine:OpenProfession` returns
  `false, "blocked"` when the block watcher saw a block, and counts a blocked
  call as failed even when it returned `true` -- in game it did exactly that
  (`-> true BLOCKED(BLOCKED)`). Location: `Modules/Crafting/CraftingEngine.lua`,
  `GUI/CraftingTab.lua`, `Locale/enUS.lua` (`CraftOpenBlocked`).
- **One click raised the block error twice.** After the first call, the engine
  asked again when Blizzard's window had just been shown and the wrong
  profession came up; when the first call was blocked, that retry only added a
  second error. It no longer asks again after a block (one BugSack entry per
  click since, in game 2026-11-21). Location:
  `Modules/Crafting/CraftingEngine.lua`.

### Improvements

- **Specs** for the blocked open: no retry after a block, the `"blocked"`
  reason, a blocked call that returned `true`, and no reason when nothing
  opened without a block. Location: `Tests/craftsuppress_spec.lua`.
- **`Locale/enUS.lua`**: two locale lines that had been written on one line
  are split back onto their own lines.

---

## [v1.11.2] (2026-11-20) - WoW Forever: Crafting tab profession open

### Bug Fixes

- **Clicking the Crafting tab on WoW Forever still raised
  `ADDON_ACTION_BLOCKED` ("UNKNOWN()")** (operator's BugSack, 2026-11-13 to
  2026-11-19, 2x per click from both `OpenTradeSkill` calls). My v1.11.0 fix
  blamed combat and added an `InCombatLockdown()` gate; that was the wrong
  cause -- these blocks came from ordinary tab clicks with the gate already in
  place. Blizzard's own caller loads the profession window
  (`ProfessionsFrame_LoadUI`) BEFORE `OpenTradeSkill`
  (`Blizzard_FrameXMLUtil/ProfessionsUtil.lua:84`, forever tree) and ours did
  not, so a first open loaded Blizzard_Professions inside the call. The engine
  now loads it first, in Blizzard's order. This is Peer Review's H4 from
  2026-09-29; the operator's first tab click after a `/reload` raised no
  error with it in place (in game, 2026-11-20). The block watcher also dropped
  every block not named `OpenTradeSkill`/`CastSpell`, so this one never reached
  `/upm opendebug`; while an open is in flight it now records a block under any
  name. Specs in `Tests/craftsuppress_spec.lua`. Location:
  `Modules/Crafting/CraftingEngine.lua`.

---

## [v1.11.1] (2026-11-18) - WoW Forever's new recipes on the Professions tab, shift-click links in the Crafting tab, a full-size minimap icon

### Bug Fixes

- **WoW Forever's own recipes were missing from the Professions and Missing
  Recipes tabs.** Reported in game: Brawler's Leather Gloves showed in the
  Crafting tab but not on the Professions tab. WoW Forever reports Interface
  16001, so `addon.isVanilla` is true there, and the recipe gate treated it as
  Classic Era -- whose "Season of Discovery" rule hides every recipe id at or
  above 200000. Every recipe Forever added (Brawler's is 1255130) has an id far
  above that, so all of them were dropped, along with the other Era-only
  heuristics about the 1.15 client's shared spell tables. The gate now excludes
  WoW Forever from "Era" (`addon.IsForeverClient`, ProfessionDB's own
  detection, now public); Forever's data is built from its own client tables,
  so those heuristics never applied to it. Specs: the "WoW Forever" block in
  `Tests/recipegate_spec.lua`. Location: `Modules/RecipeGate.lua`,
  `TOGProfessionMaster.lua`.
- **Shift-click did nothing on the Crafting tab's reagents or recipe name.**
  The detail panel's reagent list had a hover tooltip but no click handler,
  and the recipe name had none either. Both now go through
  `addon.ItemLink.Click`, the same as the Browser tab: a modified left click
  links the item in chat (or opens the dressing room, depending on your key
  bindings). Specs in `Tests/craftingtab_controls_spec.lua`. Location:
  `GUI/CraftingTab.lua`.
- **The minimap icon was cut flat, then tiny, in Ultimate Tools' square
  button bag.** The crop had been tuned by eye for the round minimap slot,
  where LibDBIcon's ring hides the rim, and cut about 1 px off the right of
  the coin and 2 px off the bottom. Then the bag stopped honouring addon
  crops and draws each icon file whole (TOGTools `BagIconCoord`), and the UPM
  art had its coin in only 44x46 px of the 64x64 file where UGR's and UTr's
  fill 56x58 -- so UPM drew noticeably smaller than its siblings. The art
  (`icons/UPM_MMB_Icon.tga`) is rescaled so the coin fills the same box as
  theirs (x 4..59, y 2..58), and `iconCoords` is re-measured to the 58 px
  square on it for the round minimap. Specs in `Tests/minimap_spec.lua` read
  the TGA and check the crop against it; `Tests/tga_bounds.lua` prints the
  coin box of UPM's art beside its siblings'. Location: `GUI/MinimapButton.lua`,
  `icons/UPM_MMB_Icon.tga`.

---

## [v1.11.0] (2026-11-15) - Talent specs for every guildmate, WoW Forever camp recipes and Merchant's Favor vendors, a Shopping List button

### New Features

- **Talent specs are recorded and synced for every guildmate.** Each
  character's own client reads its talent spec at login and whenever talents
  change -- the main spec and, where the client has dual spec, the off spec --
  and it reaches the guild with the rest of that character's data. Three client
  families, call shapes read from each flavour's Blizzard UI source (not yet
  verified in game on any): talent tabs on Era / TBC Anniversary (the tab with
  the most points, through `C_SpecializationInfo.GetSpecializationInfo` with the
  talent group), specializations on MoP / Retail
  (`C_SpecializationInfo.GetSpecialization`; Retail reports one spec), trait
  trees on WoW Forever (the tree group with the most points spent, through
  `C_Traits`). Stored at `gdb.talents[charKey] = { a, ai, o, oi }` and shipped as
  the `t` key of the owner-minted `professions:<charKey>` snapshot, so a spec
  change re-mints and propagates like a skill-up. Every reader before v1.11.0
  walks that snapshot through `tonumber(key)` and skips `t`, and a character
  with no spec recorded mints exactly the hash it did before. The owner
  re-mints only when it already holds an authoritative profession snapshot,
  with a strictly newer timestamp. KNOWN COST: a relay on an older build
  rebuilds the snapshot without `t` under the owner's token, so a receiver
  keeps the spec it already holds (never erases it) and can be one change
  behind until the owner's next re-mint. A character whose professions have
  never had a reliable read (for example none at all on Era) does not ship its
  spec. Location: `Compat.lua` (ReadPlayerTalentSpec), `Scanner.lua`
  (ScanTalentSpec, the talent events, the professions receive),
  `Modules/HashManager.lua`. Spec: `Tests/talents_api_spec.lua`.
- **Public read API, `TOGPM.API` version 1**, for other addons (asked for by
  Ultimate Guild Roster for its guild notes, so it stops reading
  `TOGPM_GuildDB`): `GetCharacterKey`, `GetCharacters`, `HasData`,
  `GetProfessions(charKey)` (`{ profId, name, skillRank, skillMax, isPrimary }`,
  primaries first), `GetSpec(charKey)` (`{ active, activeId, other, otherId }`)
  and a `CharacterChanged(charKey)` callback that names the CHARACTER whose
  professions or spec changed, from their own scan or from guild sync --
  `GUILD_DATA_UPDATED` names the sender. Every result is a fresh copy. New file
  in all seven TOCs. `Scanner.ProfessionName` gives the client's own profession
  name, else the English one. Location: `Modules/API.lua`, `Scanner.lua`,
  every `.toc`.
- **WoW Forever camp objects: Herbalism, Skinning and Fishing are recipe
  professions there.** Forever's camp system gives each of them craftable
  objects (Greenhouse / Incense Candle / Seed Hybridizer, Camp Chair / Field
  Guide / Trapper's Workbench, Fish Bowl / Fishing Hut / Fishing Rack), which
  ProfessionDB reads from Forever's SkillLineAbility (Herbalism and Skinning
  from ProfessionDB v1.10.0). New `addon.IsRecipeProfession(profId)`: every
  crafting profession, plus those three on Forever only (ProfessionDB's
  `IsGameVersion("Forever")`). The Browse dropdown and the guild-sync
  placeholder padding (so a Forever player pulls a guildmate's camp recipes)
  use it. `CRAFTING_PROFS` is unchanged, because it also shapes the gathering
  `skills:` sync leaf, which stays frozen. Missing Recipes already followed
  ProfessionDB's data and needed no change. The Crafting tab's profession list
  does NOT take them: whether Forever opens a recipe window for these lines
  through `OpenTradeSkill` is not verified in game. Location: `TOGProfessionMaster.lua`,
  `GUI/BrowserTab.lua`, `Modules/HashManager.lua`,
  `Modules/Crafting/CraftingEngine.lua`. Spec:
  `Tests/forevergathering_spec.lua`.
- **WoW Forever Merchant's Favor vendors in the recipe Sources.** ProfessionDB
  MINOR 14 ships the Azeroth Commerce Authority's recipe vendors with each
  recipe's price (a currency, item or copper cost) and the vendor's faction.
  The recipe-detail block now reads "Vendor: Nina Surefire (45 Merchant's
  Favor)" instead of the bare word, names the currency through
  `C_CurrencyInfo.GetCurrencyInfo` (ProfessionDB ships only its id), and leaves
  out a vendor of the other faction. A vendor with no cost, and every vendor on
  an older ProfessionDB, still reads "Vendor". Only the Alliance vendors are
  captured so far. Location: `GUI/SharedWidgets.lua` (FormatVendorCost,
  RecipeDetails). Spec: `Tests/vendorcost_spec.lua`.
- **[List] on Missing Recipes adds the recipe scroll to Personal Shopper's
  shopping list** (asked for by Personal Shopper, which dropped its own
  missing-recipe finder in favour of this tab). Shown only on a row with a
  scroll to buy, and only when Personal Shopper's `PersonalShopperAPI` is
  loaded -- read at click time, since Personal Shopper loads after this addon.
  Calls `AddToShoppingList(scrollItemId, 1, "<Profession> Recipes")` and prints
  whether it worked, with Personal Shopper's own reason on a refusal (Bind on
  Pickup, not yet cached). Location: `GUI/MissingRecipesTab.lua`,
  `Locale/enUS.lua`. Spec: `Tests/shoplist_spec.lua`.

### Bug Fixes

- **Clicking the Crafting tab during a fight raised 3x `ADDON_ACTION_BLOCKED`**
  (operator, in game 2026-11-15, in a dungeon). The tab's automatic
  profession open skipped combat only on `UnitAffectingCombat("player")`, but
  the client gates protected calls on combat lockdown, and the two can
  disagree; so `C_TradeSkillUI.OpenTradeSkill` ran under lockdown. The tab and
  `CraftingEngine:OpenProfession` now also check `InCombatLockdown()`.
  Location: `GUI/CraftingTab.lua`, `Modules/Crafting/CraftingEngine.lua`.
  Spec: `Tests/craftsuppress_spec.lua`.
- **The window forgot its size after a `/reload`** (operator, in game
  2026-11-13). Every tab shares one resizable size profile, which
  LibAceGUIWidgets' `SetWindowProfile` restores from
  `saved.profiles.browse` but writes only on a profile switch or on close, and
  a `/reload` with the window open never closes it. The window's
  `OnSizeChanged` script now writes that entry on every resize, but only with
  a LibAceGUIWidgets older than MINOR 52; MINOR 52 saves on every resize
  itself, through a watcher frame of its own over the window. Location:
  `GUI/MainWindow.lua`. Spec: `Tests/mainwindow_spec.lua`.
- **Most WoW Forever recipes showed "-" in the Skill column** (operator, in
  game 2026-11-13: Embossed Leather Boots, Handstitched Leather Belt and more).
  Forever's ProfessionDB data carries an orange tier of 1 with a borrowed
  `requiredSkill` for them, which is ProfessionDB's UNANCHORED case, and
  `FormatSkillTiers` hid all four numbers. The rule says only the orange tier
  is a placeholder; yellow, green and grey are the build's own thresholds. The
  column (and the recipe tooltip's block) now reads `? 80 95 110`, falling
  back to "-" only when every tier is a placeholder. Location:
  `Modules/Crafting/CraftingEngine.lua`. Specs: `Tests/skilltiers_spec.lua`,
  `Tests/borrowed_spec.lua`.
- **A skill-up did not show in the open window until it was reopened**
  (operator, in game 2026-11-13: the Crafting tab kept "Cooking (22/75)" while
  crafting to 37). Two causes. The Crafting and Missing Recipes tabs redrew
  only for `recipes` changes, not `skills`, though both show a rank (the
  profession dropdown; "Can learn now"). And a window scan usually records the
  new rank before `SKILL_LINES_CHANGED`'s profession scan runs, which then sees
  no change and announced nothing; the scan's caller refreshes only when the
  recipe SET changed. `MergeRecipesIntoGdb` now fires `GUILD_DATA_UPDATED` with
  `{ skills = true }` whenever the rank or cap it records changes, and both
  tabs redraw on `skills`. Location: `Scanner.lua`, `GUI/MainWindow.lua`.
  Specs: `Tests/callbackkeys_spec.lua`, `Tests/scanner_merge_spec.lua`.
- **Cooking (and any profession after an empty slot) was missing from the
  Crafting tab's profession dropdown** on clients with `GetProfessions` (WoW
  Forever, in game 2026-11-13; also TBC-era and later flavours). It returns
  fixed positional slots -- prof1, prof2, archaeology, fishing, cooking,
  first aid -- with nil for an empty one, and three sites walked it with
  `ipairs({ GetProfessions() })`, which stops at the first nil. A character
  with one primary profession therefore saw only that one; Cooking could only
  be opened through the game's own window. The same walk fed
  `ResolveProfessionId` (so the open Cooking window resolved through the
  fallback name map only) and `enumerateHeldProfessions`, which marks its read
  reliable -- and since the gap was the same on every read, the
  two-consecutive-reads guard dropped Cooking (and anything after the gap)
  from the character's profession registry. All three now
  use the new `addon.GetProfessionSlots()`, which walks every slot by count.
  Location: `Compat.lua`, `Modules/Crafting/CraftingEngine.lua`,
  `Scanner.lua`. Spec: `Tests/craftsuppress_spec.lua`.

---

## [v1.10.3] (2026-11-12) - WoW Forever: guild sync works, no combat error, no trainer spam

### Bug Fixes

- **WoW Forever: no guildmate's professions ever showed, on any client**
  (Discord 2026-11-08, with a status screenshot reading sends=24 rcvs=176, so
  data was flowing). Forever names are regionally unique "First Last" with no
  realm, and `UnitName`'s second return there is the SURNAME. The character
  key was `UnitName("player") .. "-" .. realm`, i.e. "First-Realm", while
  LibGuildRoster keys Forever members "First Last" and its `NormalizeName`
  cuts an incoming "First-Realm" down to "First". Every guildmate's data was
  filed under a key no roster entry matched and the roster gate hid it; the
  own-echo check never matched either. `GetCharacterKey()` now returns
  `LibGuildRoster:GetNormalizedPlayer()` when the library's `RegionalNames()`
  is on, so the key matches the roster and the wire; every other client keeps
  "Name-Realm". At login on Forever the old "First-Realm" own key leaves the
  account-character set and goes to the roster-gated pending purge, so it
  does not linger as a phantom alt. A Forever player re-records their recipes
  by opening each profession window once. Location: `TOGProfessionMaster.lua`
  (GetCharacterKey, OnPlayerEnteringWorld). Spec: new
  `Tests/forevernames_spec.lua`.
- **WoW Forever: a search or filter in the Professions window stripped
  recipes from your character.** Forever has no `GetAllRecipeIDs`, only the
  window's filtered list, and the scan treats its list as the whole
  profession, so a filtered window removed the character from every recipe
  it did not show and shared that shortened set as authoritative. The scan
  now skips while any filter is active (the same reads as Blizzard's
  `Professions.IsUsingDefaultFilters`) and re-scans on the next list update.
  Location: `Compat.lua` (ModernRecipeListFiltered,
  GetModernLearnedRecipeIDs). Spec: `Tests/scanner_scan_spec.lua`.
- **WoW Forever / Retail: "attempt to compare local 'start' (a secret number
  value)" from the cooldown scan** (Discord 2026-11-07). `C_Spell.GetSpellCooldown`
  is `SecretWhenCooldownsRestricted`, so in combat its fields are secret.
  `addon.Spell.GetCooldown` now answers nil values plus a fifth `true` for a
  secret read; the scan skips that pass instead of mistaking "unreadable" for
  "ready", and the transmute diagnostic says to try again out of combat.
  Location: `Compat.lua`, `Scanner.lua` (ScanCooldowns),
  `TOGProfessionMaster.lua` (DumpTransmuteDiag). Specs:
  `Tests/compat_spec.lua`, `Tests/scanner_cooldowns_spec.lua`.
- **"Trainer scan: 0 new, 4 updated" printed after every spell learned at a
  class trainer** (Discord 2026-11-07). The trainer scan ran at any trainer
  and re-fired on each `TRAINER_UPDATE`. It now runs only where
  `IsTradeskillTrainer()` is true, and its summary is debug output only.
  Location: `Scanner.lua` (OnTrainerShow). Spec: new
  `Tests/scanner_trainer_spec.lua`.
- **`/togpm status` said every online guildmate had "(no data)" and 0 stored
  members, on every client.** It counted `gdb.guildData`, which nothing
  writes. It now reads the profession registry (`gdb.skills`). Location:
  `Scanner.lua` (PrintStatus).

### Improvements

- **Missing Recipes is ready for ItemDB's WoW Forever vendor locations.** No
  code change was needed: the where-to-get rows, the Vendor only filter and
  [Guide] read the same rows on Forever as on Classic; two comments that said
  Forever has no places were corrected. Location: `GUI/MissingRecipesTab.lua`.

---

## [v1.10.2] (2026-11-05) - Retail: no more error when a system message arrives

### Bug Fixes

- **Retail: "attempt to index local 'message' (a secret string value, while
  execution tainted by 'TOGProfessionMaster')"** (Discord 2026-11-05). Retail
  sometimes hands addons a `CHAT_MSG_SYSTEM` payload as a secret value;
  `type()` still answers "string", so the learned-recipe handler's guard let
  it through and `message:match` raised. `OnLearnMessage` now returns early
  when `issecretvalue(message)` is true, read through `_G` because the global
  exists only on the live client (FrameScriptDocumentation.lua), so every
  Classic flavour skips the check. The "No player named X is currently
  playing" chat filter read the same payload with `message:find` and gets the
  same guard, plus a `type()` check where it only tested for nil. A recipe
  learned while the message is secret is still recorded by the trade-skill
  scan the next time that profession window opens. Location: `Scanner.lua`
  (OnLearnMessage, InstallChatFilter). Specs: `Tests/scanner_learn_spec.lua`,
  new `Tests/scanner_chatfilter_spec.lua` (the filter had no spec before).

### Improvements

- **README rebranded and reorganised** -- a "Works even better with" section
  near the top, Ultimate Bank and Ultimate Questbook integrations as their own
  sections, and the cooldown ready alerts and Missing Recipes' Can learn now
  filter, both shipped features, now described. Location: `README.md`.
- **Dev replication script reaches the new WoW Forever install** --
  `_forever_` added to the target list, and a target is picked when its
  version folder exists rather than its `Interface\AddOns`, so a fresh install
  without an AddOns folder is no longer skipped silently; `-DryRun` no longer
  creates folders. Dev-only, not shipped. Location:
  `wow-version-replication.ps1`.

---

## [v1.10.1] (2026-10-31) - Enchant button clickable again; Guide stops once the scroll is bought

### Bug Fixes

- **The Enchant button on the Crafting tab was dim and took no clicks, on
  every enchant** (Discord 2026-10-30, Classic Hardcore, with a screenshot of
  Agility 7 boots selected and materials for two). The secure button lives
  off the pooled window on a UIParent holder, and the AceGUI Frame is
  Toplevel, so a click on the window Raised it above the button. TOGPM's own
  placement code for that button (holder, strata and level sync, the OnUpdate
  watcher, the placement key, the regen re-sync) broke three times and is
  deleted. The button is now LibAceGUIWidgets'
  `W:CreateSecureOverlayButton` (MINOR 48, LibAceGUIWidgets v0.10.0, inbox
  contract 48ef6be4), which draws it in the strata above the panel, follows
  the panel, hides it for combat and detaches it when the window or tab is
  released. The draw re-attaches it with `SetPanel` after parking the
  session-lifetime detail panel, because the library now detaches on the
  innermost widget's release (a tab switch). Feature-detected: with a
  LibAceGUIWidgets older than MINOR 48 enchants use the plain button, which
  opens the game's Enchanting window. The reagent list and cost line now end
  at `W:ScaledSize(230)`, re-applied on `OnScaleChanged`, because the
  library's button grows with its size slider and would have run over the
  reagent list above a scale of about 1.06 (arithmetic, not seen in game).
  Location: `GUI/CraftingTab.lua` (EnsureCraftButton, AdoptCraftButton,
  HasSecureCraft, SyncCraftButton, ApplyControlsWidth, Draw). Spec:
  `Tests/craftingtab_draw_spec.lua`.
- **[Guide] on Missing Recipes kept guiding to the vendor after the scroll
  was bought** (Discord 2026-10-30: "will not quit after you talk to the
  vendor and buy"). Questbook never clears a place on arrival, so the guide
  is now ended by TOGPM: [Guide] records the scroll's bag count and watches
  `BAG_UPDATE_DELAYED`; when the count rises it stops the guide through
  `WhereStopTracking` and says so. If Questbook is no longer guiding, the
  watch just ends. KNOWN COST: Questbook has no public read of what it is
  guiding, so a track the player started in Questbook after our [Guide] is
  the one this stops. The start message now says the guide stops by itself.
  Location: `GUI/MissingRecipesTab.lua` (Guide, StopGuide,
  OnGuidedBagsChanged), `Locale/enUS.lua`. Spec:
  `Tests/missingrecipes_spec.lua`.

---

## [v1.10.0] (2026-10-26) - Missing Recipes shows Auction House prices and a Vendor only filter; German clients scan professions

### New Features

- **On AH column on Missing Recipes** (Discord 2026-10-24: a player ran an
  ItemDB scan, closed the AH and saw nothing for a listed Pattern: Red Linen
  Robe, because the [AH] button answers from the live AH session only). A
  sortable column shows each scroll's cheapest buyout at the last ItemDB
  scan, read through `Price.GetLastScanListing`, which answers from the live
  session while the AH is open and otherwise from ItemDB's public
  `GetScanRecord` (LibItemDB MINOR 47, inbox contract a583dabb). The row
  tooltip adds the listing count and the scan's age. A scroll the scan did
  not see sorts last in both directions. No read of ItemDB's private price
  store: with an ItemDB older than MINOR 47 the column is blank. Location:
  `GUI/MissingRecipesTab.lua` (AHPrice, BuildRowList, SortList,
  ShowRowTooltip), `Modules/Price.lua`, `Locale/enUS.lua`. Specs:
  `Tests/price_spec.lua`, `Tests/missingrecipes_spec.lua`.
- **Vendor only filter on Missing Recipes** (Discord 2026-10-24: "filter
  missing recipes to just the ones you can run around and buy from a vendor
  and if they are faction vendors, only show if you have the faction to get
  them"). Keeps a scroll when LibItemDB's places for the player's faction
  include a vendor; a scroll only the other faction's vendors sell is
  dropped; with no LibItemDB vendor at all, ProfessionDB's vendor source
  decides. With LibItemDB `GetRequiredReputation` (MINOR 47, inbox contract
  e1313d35), a scroll that needs reputation passes only once the
  character's standing (`C_Reputation.GetFactionDataByID` reaction, else
  `GetFactionInfoByID` standingID) reaches the requirement; a faction the
  character has never met counts as not reached. Location:
  `GUI/MissingRecipesTab.lua` (SoldByVendor, whereRowsFor, FillList,
  DrawScope). Spec: `Tests/missingrecipes_spec.lua`.

### Bug Fixes

- **German (and other non-English) Classic Era clients stored no recipes**
  (Discord 2026-10-24, deDE Era). Era has no `GetProfessions`, so the
  English name map was the only name-to-id path: `GetTradeSkillLine()`
  returned "Schneiderei", the scan bailed and stored nothing. Profession
  names now also resolve through the client's own
  `C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID)`. Removing a dropped
  profession stays English-only, because nothing proves the character panel
  spells every skill line the same as the trade-skill window, and a miss
  there must not delete a profession. Not yet confirmed on a German client.
  Location: `Scanner.lua` (LocalizedProfessionId, ProfessionIdFromName).
  Spec: `Tests/scanner_scan_spec.lua`.

---

## [v1.9.0] (2026-10-24) - Share missing recipes between accounts

### New Features

- **Missing Recipes import and export** (asked for on Discord 2026-10-24 for
  a player with characters on several accounts who wants every character's
  missing recipe scrolls in one place to buy at any Auction House; operator:
  "it needs to be between accounts, so it needs to be exportable, like we did
  with the copy/paste for the shopping list, but we need it for the missing
  recipes"). A **Share List** button on the Missing Recipes tab (My Character
  view) opens a window holding every character this account knows as text:
  its own characters' missing scrolls, computed live with the toolbar at its
  defaults, plus any characters shared in earlier, so a list passes along a
  chain of accounts. Only scrolls travel; a trainer-only recipe is nothing to
  buy. Pasting a list there and pressing **Import** stores each character in
  it account-wide (`TOGPM_Settings` `global.missingShared`), replacing that
  character's earlier share, so a re-import after they learn a recipe drops
  it and importing twice changes nothing. This account's own characters in
  an import are ignored, because their list is live. Shared characters
  appear in the Character dropdown marked "(shared)", with a **Forget**
  button, and **All characters** lists every scroll any character needs, once
  each, with "for Name, Name" after it. The skill, spec, "Can learn now" and
  "Show All" filters do not apply to a shared character, since the other
  account already applied them and no skill is held for them here. The text
  is plain `UPMMR1:<Name-Realm>=<spell>,<spell>,...;...` with no Discord
  markup character; whitespace a chat client adds is ignored; names are
  checked (must hold a realm, at most 64 characters, no `|`) and capped at 50
  characters and 3000 recipes each; a recipe this game version does not have
  is skipped and counted in the window's status line. Kept separate from the
  Recipes-tab shopping list on purpose: that list holds recipes a character
  crafts, with reagents, and a scroll to buy has none. Location:
  `GUI/MissingRecipesTab.lua` (MakeEntry, ExportMissing, ImportMissing,
  ForgetShared, BuildFor, OpenShareDialog), `TOGProfessionMaster.lua`,
  `Locale/enUS.lua`. Spec: `Tests/missingshare_spec.lua`.

### Improvements

- **One share window for both lists.** The copy/paste window the shopping
  list's Share List opened is now `addon.GUI.ShareDialog`, used by the
  Recipes tab and Missing Recipes alike, so the two cannot drift apart.
  Location: `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`.

---

## [v1.8.0] (2026-10-21) - Share the shopping list between accounts and friends

### New Features

- **Shopping list import and export** (asked for on Discord 2026-10-21 by a
  player on three paid accounts who wants one list any of their characters
  can search the AH with). A **Share List** button on the Recipes toolbar
  opens a window holding the list as one block of text, selected and ready to
  copy. Pasting a shared list there and pressing **Import** adds it to the
  current character's list and never replaces it. Each entry remembers which
  other character wants how many: the shopping list shows "for Name" after
  the recipe and its tooltip lists everyone with their counts, so a pattern
  found on the AH can be mailed to the right character. A character's share
  is replaced on import, never added again, so importing the same list twice
  or your own list back changes nothing. Your own counts in an imported list
  are restored (raised to the imported count, never lowered), so a list
  exported, deleted and imported back on one character comes back whole;
  the first build dropped them, which the operator caught in game. A list
  passed through several accounts keeps crediting each item to the character
  who asked for it. Only
  the recipe ids and who wants how many travel (operator, 2026-10-21: "we
  don't need to import/export the recipies, just the items/count on the list.
  everything needed to repopulate it is in the addon"): the text is plain
  `UPMSL1:<recipe>:<Name-Realm>=<count>,...;...`, and the name, icon, crafted
  item and reagents are rebuilt from the addon's own recipe data with the same
  calls and client gate the recipe list uses. A recipe this game version does
  not have is skipped and counted in the window's status line. The text holds
  no Discord markup character, and line breaks a chat client adds are
  ignored. Character names and counts from an import are checked and clamped
  (1-999, at most 64 characters, no `|`), at most 500 entries. Location:
  `GUI/BrowserTab.lua` (ExportShoppingList, ImportShoppingList,
  ShoppingEntryFor, OpenShareDialog), `GUI/SharedWidgets.lua` (new
  `addon.GUI.ToolbarButton`), `Locale/enUS.lua`. Spec:
  `Tests/shoppingshare_spec.lua`.

---

## [v1.7.0] (2026-10-21) - Renamed to Ultimate Profession Master; supply mail sends from the Mail button and is marked Sent; Guild tab + clicks land; Missing Recipes Sources sort no longer stalls

### New Features

- **Renamed to Ultimate Profession Master** (operator, 2026-10-21: "i want
  to rebrand TOGPM as Ultimate Profession Master"). Every name a player sees
  changes: the addon list title in all seven TOCs, the window and sync-log
  titles, the settings page, the minimap button, chat prefixes and the
  "[TOGPM]" tooltip and alert tags (now "[UPM]") in all fifteen locales, and
  the README. `/upm` is added beside `/togpm`, which keeps working. The
  minimap tooltip title, slash-help header, status printouts and the bank
  dialog's "[UPM]" tag now draw in the brand orange instead of the old TOG
  purple (operator, in game: "ensure you check tooltips, like the minimap
  button one that still have old info"). The minimap button and the
  AddOns-list icon (`## IconTexture` in all seven TOCs) use the operator's new
  `icons/UPM_MMB_Icon.tga` instead of the "TOG PM" art. The minimap button
  crops that art with `iconCoords = { 0.135, 0.825, 0.105, 0.795 }` instead of
  LibDBIcon's default 5% trim, so the coin fills the slot and sits centred
  (operator, in game: "the rest of the icons aren't squished like mine"; the
  offsets were nudged to the operator's in-game reports). Location:
  `GUI/MinimapButton.lua`.
  Chat lines start with an orange "UPM:" instead of "TOGProfessionMaster:"
  (operator, in game: "/upm help" printed the internal name on every line):
  `Ace:Print`/`Printf` in `TOGProfessionMaster.lua` replace AceConsole's,
  which prefix with the AceAddon name. The supply-mail messages
  (`GUI/CooldownsTab.lua`) say "UPM:" instead of the full name, and `/upm help`
  lists every command as `/upm`, with one line saying `/togpm` still works.
  The test env now restores the addon object's `Print`/`Printf` on every reset,
  since three specs replaced them without putting them back. Spec:
  `Tests/chatprefix_spec.lua`.
  Deliberately unchanged, because changing them would lose data or split the
  guild: the folder and file names (the game keys each player's saved data by
  folder), the internal addon, locale, options, LibDataBroker and DeltaSync
  names (guild sync derives its message prefix from the namespace, so a
  renamed one would not talk to players on older versions), frame global
  names and the CurseForge slug. The release tag prefix DOES change, to
  `UltimateProfessionMaster-vX.Y.Z` from this release on (operator,
  2026-10-21: "we need to change the tags to align with the brand"); older
  `TOGProfessionMaster-vX.Y.Z` tags stay. The tag becomes the addon's version
  string, and VersionCheck-1.0 compares only its digit groups, so guild
  version checks across the two prefixes still order correctly.

- **A Sent column on the Cooldowns tab** (operator, 2026-10-21: "add a column
  using the same frameworks as the other columns to annotate who we've sent
  mats to"). Once a supply mail goes, the row shows how long ago ("5m ago",
  "3h ago", "2d ago"), with the date and time on hover. It clears by itself
  when that crafter uses the cooldown, because the record keeps the cooldown's
  expiry from the moment of sending and drops itself once the expiry jumps
  forward into the future. A minute of slack keeps it through a resync, since
  cooldowns travel as time remaining and come back a few seconds off.
  Every transmute shares one record per crafter, since they share one
  cooldown. Kept per character in the sender's own saved settings. A mail
  sent with the mailbox's own Send button counts too. Location:
  `GUI/CooldownsTab.lua` (the `sent` column, `CooldownsTab:SentInfo`).

- **Click Mail again to send the supply mail** (operator, same day: "we need
  to be able to keep clicking the button to also send the mail"). Once the
  mail is attached and addressed, the next click on the same row's Mail
  button sends it through the mailbox's own Send handler, which clears any
  money or COD and sends exactly as the Send button does. A click on another
  row's Mail still refuses while the mail holds items, and a failed send can
  be clicked again. The send call is marked restricted in Blizzard's
  documentation; the operator confirmed in game on 2026-10-21 that the click
  on our button sends the mail and the Sent column marks the row. If the game
  ever blocks it (`ADDON_ACTION_FORBIDDEN` or `_BLOCKED` naming
  `SendMail`), or the mailbox's handler errors, the mail goes back to ready,
  the mailbox's Send is re-enabled and chat says to use it. The Sent record
  is only written when, at the moment of sending, the mail is still addressed
  to the supply mail's recipient and still carries items (a post-hook on
  `SendMailFrame_SendMail`, which both Send paths reach), so a different mail
  sent from the same mailbox does not mark the row. Peer Review on the
  self-audit. Location: `GUI/CooldownsTab.lua`.

### Bug Fixes

- **A supply mail sometimes carried two of a reagent it needed one of**
  (operator, in game 2026-10-21: a Salt Shaker mail with 2 Deeprock Salt). A
  second click while the first click's split was still landing split again
  into the same empty bag slot, which stacked the two pieces before the attach
  picked the slot up. A click while a mail is being built is now ignored, with
  a "still preparing" line in chat; the operator confirmed the splitting in
  game the same day. Six specs in `Tests/cooldownmail_spec.lua`
  cover the double click, the send on the next click, another row's click, the
  Send button not ready, a failed send retried, and a mail emptied by hand.
  The same file could not load on its own, because the Cooldowns tab needs the
  shared widgets file first, as the addon's load order has it; it now loads it.
  Location: `GUI/CooldownsTab.lua`.

- **Known By names were cut off in the Professions detail panel** (operator,
  in game 2026-10-21: "you're truncating the names here when we have a lot of
  space in the row left"). Crafter rows share the reagent rows' columns, so a
  name stopped where the empty count, [Bank] and [AH] cells began. The name
  column now spans every following cell that draws nothing for its row, using
  the column span LibAceGUIWidgets added for this at MINOR 46. The reagent
  count moved to the last column, so a reagent name ("Refreshing Spring
  Water", which drew as "Refreshing..." in the same screenshot) also runs over
  a hidden [Bank]/[AH] and stops at its count. The operator confirmed both
  the crafter names and the reagent names in game the same day. A row with
  only one button still cut its name ("Raw Brillian..." before [Bank], with
  the empty [AH] slot after it), so both buttons now collapse when hidden
  (RowList `col.collapse`, also MINOR 46): the visible one sits beside the
  count and the name spans the rest. With an older LibAceGUIWidgets the names
  truncate as before.
  Spec in `Tests/browserdetail_spec.lua`. Location: `GUI/BrowserTab.lua`
  (`BrowserTab:BuildDetailList`).
  On a LibAceGUIWidgets below MINOR 46 the list keeps v1.6.1's column order
  (name, count, [Bank], [AH]), because that RowList ignores span and collapse
  and the count-last order would have parked the count behind two
  always-reserved button slots on every reagent row: a visible regression on
  any released library, not merely no improvement (Peer Review F1 on
  self-audit 3ea3379a). `addon.W_LOADED_MINOR` now records the loaded MINOR
  for features newer than `W_MINOR`, which stays 36 so an older library still
  runs the GUI. Two specs pin both orders by handing the list each MINOR; the
  RowList loaded offline is the working copy at 46, so the older library's own
  drawing is not exercised. The span spec now reads the public
  `RowList:RowPlan` that LibAceGUIWidgets added at MINOR 47 for it, instead
  of the private `_rowPlan`, which had already been renamed once under it
  (Peer Review F4). Location: `TOGProfessionMaster.lua`,
  `GUI/BrowserTab.lua` (`BrowserTab.DETAIL_SPAN_MINOR`).

- **`/upm settings` printed the command list instead of opening the
  settings.** The settings tooltip in every locale has named this command,
  but it was never in the dispatcher's table, so it fell through to help. It
  now opens the settings panel and is listed in `/upm help` (new
  `SlashHelpSettings` string in all fifteen locales). Found while switching
  the hints to `/upm`. Spec in `Tests/slash_spec.lua`. Location:
  `TOGProfessionMaster.lua`.

- **Hints and usage lines still named `/togpm`** after the rebrand: the
  cross-guild pull description, the minimap-hidden message (which also drew
  the command in the old TOG purple, now the brand orange) and the settings
  tooltip in every locale, and the usage lines for `pullroster`,
  `dumprecipe`, `dumpprice`, `itemgaps`, `whyvisible` and the blocked
  profession-open message. All say `/upm` now (Peer Review F3). Location:
  `Locale/*.lua`, `TOGProfessionMaster.lua`,
  `Modules/Crafting/CraftingEngine.lua`.

- **Hiding the minimap button gave no hint how to bring it back.** The
  "Minimap button hidden. Use /upm minimap to restore." line was translated in
  every locale but no code printed it. The Settings toggle now prints it when
  the button is hidden, and not when it is shown. Spec in
  `Tests/settings_spec.lua`. That file's Settings re-layout spec also failed
  when run on its own (6 timers where it expects 2): Ace3's Slider constructor
  schedules its own font workaround for each slider it builds new
  (`Ace3/AceGUI-3.0/widgets/AceGUIWidget-Slider.lua:276`), and a lone run has
  no pooled sliders yet. It now counts only timers scheduled from
  `GUI/Settings.lua`. Location: `GUI/Settings.lua`.

- **Clicking + on a Guild tab profession often did nothing** (operator, in
  game 2026-10-21: "the click isn't working"). The Guild tab renders every
  kind of data a guild sync carries, so the window tore it down and rebuilt
  it every few seconds. Each teardown hides the list frame and shows it again,
  and a hide between the mouse-down and the mouse-up cancels the click. A
  guild-data refresh now recounts and re-hands the tree to the list in place,
  the same path a filter change already took. The full redraw remains for the
  one change that needs it, the empty-guild message giving way to the list.
  The cause is read from the code and has not been confirmed in game (not
  verified): if a click still fails, it is not this. Three specs in
  `Tests/guildtab_spec.lua`, one of which watches the list frame for a hide.
  The same file's scale-change spec only passed in a whole-suite run, because
  an earlier file had created the main window table; it now supplies its own.
  Location: `GUI/GuildTab.lua` (`GuildTab:RefreshInPlace`),
  `GUI/MainWindow.lua`.

- **Sorting Missing Recipes by Sources looked up every row's places in one
  frame.** A row with no recipe-database sources gets its Sources text from
  the item library's place list for the scroll, which decodes every spawn and
  names each zone. On Retail that is nearly every row, and the sort asked for
  all of them at once (self-audit cd8c79f4, item 1). The sort now spends at
  most 4 ms on those lookups, sorts with what is ready, and finishes the rest
  one slice per frame, re-sorting and redrawing once when every key is known.
  The continuation drops itself if the list is rebuilt or the player sorts by
  another column. Not measured against Retail data: the fix bounds the work per
  frame regardless of its size. The place rows are also cached per scroll for
  the session (keyed by the item library object and the faction), because the
  rows are rebuilt on every search keystroke and sync, and without the cache
  every later sort redid every lookup (Peer Review). Five specs in
  `Tests/missingrecipes_spec.lua` pin the slice, the single redraw, the single
  continuation, the give-up and the cache. Location: `GUI/MissingRecipesTab.lua`.

- **The Professions tab offered the classic trainer-rank tier filter on
  Retail, where it cannot classify anything.** Retail measures each expansion
  line on its own scale (Khaz Algar Blacksmithing runs 1-100), while the bands
  are the classic 75-point ranks up to Zen Master's 600, so most bands matched
  no Retail recipe (self-audit cd8c79f4, item 5). Retail now draws no tier
  filter; every classic flavour keeps it unchanged. Traced on the way: the
  recipe gate's expansion number is harmless on Retail, because the only field
  it compares against is absent from every flavour's data, not only Retail's
  (Peer Review). That check is now marked defensive in the code, and two stale
  comments that called it the primary gate, and the skill cap a gate, are
  rewritten. Location:
  `GUI/BrowserTab.lua` (the filter moved into `BrowserTab:AddTierFilter`),
  `Tests/toolbar_spec.lua`.

- **Three places showed an item as a number or "?" while the item library knew
  its name.** The Missing Recipes tooltip for an uncached scroll and the name
  the [Bank] dialog opens with went straight to `Item #<id>`, and the Crafting
  tab's reagent list drew "?" for a reagent the modern trade-skill API handed
  over without a name. A new `addon:ItemDisplayName` gives the one bare-id
  chain (client name, then the item library, then the placeholder), and the
  Crafting reagent column now goes through `addon:ResolveReagentName`. The
  Crafting reagent hover, [Bank] and [AH] read the healed name and link too:
  the heal writes `itemLink` while the trade-skill reagent tables say `link`,
  so the healed link was never read (Peer Review). The guild bank request
  dialog's own placeholder now comes from the same helper. Filed in
  self-audit b37931c3 on 2026-09-11 and not done until now. Location:
  `TOGProfessionMaster.lua`, `GUI/MissingRecipesTab.lua`, `GUI/CraftingTab.lua`,
  `Compat.lua`, `Tests/reagentname_spec.lua`, `Tests/craftingtab_controls_spec.lua`.

---

## [v1.6.1] (2026-10-20) - Every tab is the same size; the Craft button is a plain button for trade skills; the close path runs once

### Bug Fixes

- **The Cooldowns and Guild tabs were smaller than the rest, so switching to
  or from them made the window jump** (operator, in game 2026-10-20). Those two
  tabs were locked at 720x500, while Crafting and the Profit Planner need at
  least 820 and 920 wide, and the other tabs shared a resizable size of their
  own. Every tab now uses one shared size, resizable, whose floor is the
  largest minimum any tab declares (920x540 today), so a tab switch never moves
  the window. Pinned by a new spec in `Tests/mainwindow_spec.lua`. Two
  existing size specs there were moved to the new floor, because the change
  made them fail (run 20261020-223619.605, red) rather than because they were
  wrong: the "restores a saved size that fits" case now saves 960 wide instead
  of 800 (below the new floor), with a new spec that a smaller saved size is
  raised to the floor; and the uncapped shopping-list control uses ten recipes
  instead of six, since 30 rows now fit in the taller tab. Green after the
  edit on run 20261020-223845.589. Location:
  `GUI/MainWindow.lua`, `GUI/CooldownsTab.lua`, `GUI/GuildTab.lua`.

- **Clicking the main window's title bar closed the window** (operator, in
  game 2026-10-19). The temporary chat trace never caught it: the one trace
  captured (on WoW Forever) was an ordinary Close-button click. No cause was
  identified. The operator reports it no longer happens in Classic Era
  (2026-10-20). The temporary trace is removed. Location: `GUI/MainWindow.lua`,
  `Modules/Crafting/CraftingEngine.lua`.

- **Closing the window from code ran its close-down twice.** `Close()` releases
  the AceGUI frame, and AceGUI hides it before clearing its callbacks, so the
  frame's own close callback re-entered the release mid-way and the bottom-row
  cleanup, the clamp restore, the Craft button re-check and the Crafting
  engine's window-closed handler all ran a second time. On a close from code the
  second run also undid the clamp restore, so the pooled frame always went back
  to AceGUI unclamped whatever its earlier setting (the X button ran the
  cleanup once and restored it correctly). The release path now returns at
  once when AceGUI is already releasing the widget. Found by Peer Review by
  reading. In `Tests/mainwindow_spec.lua`, two specs reproduce the bug and were
  seen failing before the fix (one close for `Close()`; a frame clamped before
  opening is still clamped after `Close()`), and one is a regression guard that
  already passed (one close for a direct hide). Location: `GUI/MainWindow.lua`.

- **The Craft button showed greyed and took no clicks for a trade skill**
  (in game 2026-10-18), while the debug line reported it enabled and above the
  window. The cause in the secure button was not found. Trade skills no longer
  use it: Craft is now a plain button inside the detail panel, built like
  Craft Max (which kept working), and crafts the selected recipe at the
  stepper's quantity through the same engine call. A trade-skill craft needs
  only the click, so nothing secure is required. The secure button now shows
  for Enchanting alone, where the enchant goes through a secure `/cast`
  (whether `DoCraft` itself is protected is not verified), and lost the
  trade-skill crafting it no longer used. An enchant with no name to cast,
  which got no button at all, now gets the plain button labelled Enchant, which
  opens Blizzard's Craft window. Craft, Craft Max and the queue's Craft Next
  and Craft All are disabled in combat, matching the Enchant button, which is
  hidden then. An enchant picked during combat is what the Enchant button casts
  once combat ends; it used to keep the one picked before. Craft Next and Craft
  All also come back after combat when the selected recipe left the list during
  it; they used to stay greyed until the queue next changed. Not yet seen in
  game. Location: `GUI/CraftingTab.lua`, `Modules/Crafting/CraftingEngine.lua`.

- **The Craft button stayed on screen after TOGPM's window closed, and looked
  dimmed behind the window while it was open** (in game 2026-10-18). The button
  is a secure frame kept outside the window on purpose, so it has to be told
  when to hide. It now shows only while the window is open on the Crafting
  tab, and closing the window re-checks it. Why the panel's own hide did not
  already hide it was not found; the window check is a guard, not the
  diagnosis. The placement watcher now also re-places the button when the
  panel changes strata. Whether that caused the dimmed look is not
  established: the button is disabled when nothing can be made, which looks
  much the same. The window's own level is part of the placement check as well,
  and the button is lifted above whichever of the panel and the window is
  higher. Each placement now prints its strata, level, enabled state, alpha and
  mouse state under `/togpm debug`. Uses only `GetFrameStrata`, a base frame method; checked
  against the Classic Era client source, not the other flavours' trees.
  Location: `GUI/CraftingTab.lua`, `GUI/MainWindow.lua`.

### Improvements

- **One recipe-id mapping instead of four copies.** Turning a recipe id read
  from the client (the crafted item's id on Vanilla) into the spell id the
  shipped data and the guild data key on was written out separately in the
  scanner's merge, the crafter-set receive, the crafting engine and the
  Crafting tab's Profit Planner jump, with slightly different guards and
  nothing checking they agreed. All four now call `addon:CanonicalRecipeId`,
  pinned by `Tests/canonicalrecipeid_spec.lua`. The Crafting tab's copy used
  to try the crafted-item map even for a profession with no shipped data; that
  map is built from the shipped data, so it was always empty there and nothing
  a player sees changes. Location: `TOGProfessionMaster.lua`, `Scanner.lua`,
  `Modules/Crafting/CraftingEngine.lua`, `GUI/CraftingTab.lua`.

---

## [v1.6.0] (2026-10-17) - Allied guild tags; Reagent Tracker scale, opacity and background; cross-realm supply mail

### New Features

- **Allied guild members carry a short guild tag after their name**, like
  `Ahmbrai <Other>`, so it is clear at a glance who is in which guild
  (operator, 2026-10-17: "The Old Gods (TOG) and The Other Gods (TOG) show
  you the problem"). The tag is worked out automatically from the first word
  that tells the guild names apart once filler words ("the", "of") are dropped,
  cut to five letters, and never shared by two guilds -- so The Old Gods and
  The Other Gods read `<Old>` and `<Other>`. Settings -> Cross-Guild has an
  "Allied guild tags" box (`Guild Name = Tag`, one per line) to pick your own,
  and lists the tags in use. Home-guild members carry no tag. The tags are
  LibGuildRoster's (MINOR 35, GuildRoster 1.4.0), at the operator's direction
  ("it should feed that to every addon that consumes a sister guild"; inbox
  49703e36): the library derives them and stores your own tags account-wide
  under the home guild, so every TOG addon shows one guild under one tag.
  TOGPM's readers (`GetGuildAbbrev`, `GetCharGuildAbbrev`, the Settings box)
  are thin wrappers over `GetGuildTag` / `GetCharGuildTag` / `SetGuildTag`,
  the name columns repaint on the library's `OnGuildTagsChanged`, and
  `MigrateGuildTagsToLibrary` (from `OnRosterReady`) moves any tags a working
  copy kept in `profile.guildAbbrevs` into the library once and deletes them.
  Under an older GuildRoster there are no tags and the Settings box is greyed
  out. Typing a tag another allied guild already shows keeps it (your choice)
  but says so in chat, naming that guild, from `SetGuildTag`'s second return
  (Peer Review G1, inbox 2899de7d) -- once, when that tag is changed, not on
  every later save, and in the form the library stored (trimmed, at most 12
  characters). TOGPM's own derivation is gone; its spec fixtures now run against the
  library's. Specs in `Tests/sisterguild_spec.lua`. Location:
  `TOGProfessionMaster.lua`, `GUI/Settings.lua`, `Locale/enUS.lua`.
- **A supply mail the game refuses now says why in chat.** After the Cooldowns
  tab fills in a mail, the game's own mail error (and a failed send) is
  repeated in chat with the recipient's name and the error's `ERR_MAIL_` name
  until the mail goes or the mailbox closes. Only mail errors are repeated --
  the first cut also blamed unrelated ones such as "Out of range." on the mail
  (Peer Review F1, inbox 60941923). Added for the operator's report of a mail to an allied-guild member
  that loops on the "might be someone you don't know" confirm (cause not yet
  known; GuildRoster asked to check its mailbox autocomplete, inbox 9aa8c30f).
  Spec in `Tests/cooldownmail_spec.lua`. Location: `GUI/CooldownsTab.lua`.
- **Scale and opacity sliders for the Reagent Tracker** (the shopping-list
  window opened by right-clicking the minimap button). Settings -> Display now
  has "Reagent Tracker scale" (50-150%) and "Reagent Tracker opacity"
  (0-100%) right below the main window's pair, and both apply live. Changing
  the scale keeps the window's top-left corner on the same spot on screen.
  Saved per profile as `trackerScale` / `trackerOpacity`. Specs in
  `Tests/reagenttracker_spec.lua`. Scale checked in game on Classic Era.
- **The Reagent Tracker has a dark background, and the opacity slider sets
  only that.** It had none, so the list read as see-through over bright ground.
  A black panel (50% at 100% opacity) now sits behind the rows; the slider
  fades just the panel, never the text, icons or buttons, and 0% removes it,
  matching the old look. The first cut faded the whole window, text included.
  Not yet checked in game.
  Location: `GUI/ReagentTracker.lua`, `GUI/Settings.lua`, `Locale/enUS.lua`.

### Bug Fixes

- **The Professions tab kept showing the recipe list from login until a
  /reload** -- a guildmate learning a recipe, or someone leaving the guild,
  never reached it. CallbackHandler keeps one handler per (event, `self`) and a
  second registration under the same `self` replaces the first (Ace3
  `CallbackHandler-1.0.lua:126-129`). BrowserTab registered its
  `GUILD_DATA_UPDATED` re-warm as `addon:RegisterCallback(...)` at load, and
  MainWindow registered its refresh the same way at OnEnable, so MainWindow's
  replaced BrowserTab's and the cache built 8 s after login was served all
  session (Peer Review H1, inbox 95fc14a4). Every addon-event subscription now
  registers as its own module (`BrowserTab`, `MainWindow`, `CooldownsTab`,
  `addon.GUI`, `SyncLog`, the Sync Log window's listener), and TOGPM's seven
  LibGuildRoster subscriptions register as the addon rather than as the
  library, a slot another addon making the same mistake would have shared
  (Peer Review M1). Specs in `Tests/callbackkeys_spec.lua`. Its first seven
  cases (the GUILD_DATA_UPDATED one and the six AH / SYNC key checks) were red
  against the old code (run 20261017-173040.786-2899038007, 0 of 7 passing);
  the seven LibGuildRoster key cases were added after the fix and have only
  been run green. All 14 pass (run 20261017-174130.037-3435744109). Location: `GUI/BrowserTab.lua`,
  `GUI/MainWindow.lua`, `GUI/CooldownsTab.lua`, `GUI/SharedWidgets.lua`,
  `GUI/Settings.lua`, `Modules/SyncLog.lua`, `TOGProfessionMaster.lua`.
- **The crafter-online alert named the two characters the wrong way round.**
  When an alt of a shopping-list crafter logged in, chat read "Crafter is
  online (alt of Alt)" instead of "Alt is online (alt of Crafter)" -- the two
  names were passed to the message in swapped order. Specs (the first for this
  alert) in `Tests/crafteralert_spec.lua`. Location: `TOGProfessionMaster.lua`.
- **Right-clicking a crafter on the Professions tab whispered the display text,
  not the character** -- the crafter list carried no character key, so the
  whisper fell back to the shown name, which can read "Alt (Main)". Each entry
  now carries its key -- the online alt's when an alt stands in for an offline
  crafter, so the whisper reaches someone who is on. Typing in the search box
  also no longer matches the allied-guild tag's colour code ("cff", "9d").
  Specs in `Tests/browserlist_spec.lua`. Location: `GUI/BrowserTab.lua`.
- **Cooldown supply mail to a crafter on another realm went to the wrong
  person** (operator, 2026-10-16). The mail button cut the realm off the stored
  `Name-Realm` key before filling the To: box, and a bare name is delivered to
  that name on the sender's own realm. The recipient now keeps the realm when it
  is not the sender's, and stays a bare name on the same realm; the greeting
  still uses the bare name. Spec in `Tests/cooldownmail_spec.lua`. Not yet
  checked in game. Location: `GUI/CooldownsTab.lua`.
- **The Reagent Tracker showed a scroll bar and one row too few** (operator,
  2026-10-15: "why did you add a scroll bar to the tracker?"). The list sizes
  its host to exactly the rows it holds, then counts the rows that fit by
  flooring the host's height; a height returned a hair short (likeliest at a
  tracker scale other than 100%, not verified in game) floored to one row
  fewer. The host now carries one unit of slack, and the window is sized from
  the list's own height so the slack never shows. LibAceGUIWidgets is told
  (inbox 62eb5c52) and RowList tolerates it itself from MINOR 44, so the slack
  is applied only under an older LibAceGUIWidgets. Spec in
  `Tests/reagenttracker_spec.lua`. Location: `GUI/ReagentTracker.lua`.
- **Clicking a recipe on the Professions tab did nothing while
  TradeSkillMaster's Crafting window was open** -- the recipe went into TSM's
  search box and our detail panel stayed on "Select a recipe" (operator,
  2026-10-15, with a screenshot of TSM's search reading the clicked recipe).
  TSM replaces `HandleModifiedItemClick` with `orig(link) or hookFunc(link)`
  (LibTSMWoW `Source/API/Item.lua:158-166`), so its hook runs on every click
  and answers "consumed" whenever its search box takes the link, modifier or
  not. `ItemLink.Click` handed every click to that router, so a plain left
  click looked consumed and `ClickRow` returned before drawing. It now asks the
  router only when a modifier Blizzard's own router acts on is held (CHATLINK
  and DRESSUP everywhere, plus EXPANDITEM, which on Retail opens the profession
  window for profession gear), so nothing changes without TSM. Every item
  link click in the addon goes through this one function, so all of them are
  fixed. Specs in `Tests/itemlink_spec.lua`. Not yet checked in game.
  Location: `GUI/SharedWidgets.lua`.
- **The shopping list on the Professions tab could still draw as an empty box
  with a scrollbar** (Discord, 2026-10-13, one recipe on the list). v1.3.1 gave
  the section 2 px of slack against the client's whole-pixel snapping. That
  figure was a guess and was never confirmed in game, and at a large UI scale
  several snapped edges can take more than 2 px off. The list then floored one
  row to zero. The slack is now half a scale-1.0 row (`SL_SLACK = 7`), which is
  well past what pixel snapping should cost and still less than a row at scale
  0.5 or above. That snapping is the whole cause is read from the code, not
  measured in the client. A new spec in `Tests/browserdetail_spec.lua` takes 4 px
  off the content and requires the row to draw. It was run with 2 px and fails,
  and only that spec fails. Verified in game on WoW Forever with one item
  (operator, 2026-10-13: "it looks good in forever with 1 item"). Not seen on
  the other flavours or with the scale change, and the poster's addon version
  is not known. Location: `GUI/BrowserTab.lua`.
- **The shopping list did not re-fit when the shared text scale changed** (Peer
  Review on the above). The section was sized once, at draw time. Another
  addon's Text Size slider (TOG Bank's) raising the LibAceGUIWidgets scale
  grew each row but not the section, so one item could floor to zero rows
  again until the tab was redrawn. The tab now registers a scale listener and
  refits the section while it is showing. The listener takes the tab as its
  owner argument, so the weak-keyed listener table does not keep a reloaded
  tab alive. The section's row height now comes from the scale itself rather
  than the list, so it does not depend on which listener runs first. The
  unused first `SetHeight` in `Draw`, a second formula for the same height, is
  removed. Spec in `Tests/mainwindow_spec.lua` (scale 1.0 to 2.0). Location:
  `GUI/BrowserTab.lua`.
- **TOGPM handed three kinds of damaged widget back to the shared AceGUI pool**
  (operator, 2026-10-13: "i think we may have some tabs not recycling widgets
  properly, and they are getting corrupted widgets from teh pool"). A read of
  every GUI file found three.
  - Every tab draw set the main TabGroup's `LayoutFinished` to nil. TabGroup
    copies that method onto each instance, so this deleted it from the pooled
    widget. Once the window closed, the next addon to get that TabGroup could
    not auto-size it. It is now `SetAutoAdjustHeight(false)` at creation, and
    AceGUI's Release clears that.
  - The shopping-list section's reference outlived the widget. The TOG Bank
    watcher's timer could refill a section already back in the pool, parking
    our list inside another addon's box. That box's release would later hide
    our list while it was showing in our window. The reference is now cleared
    by a release hook, which also covers the scale refit above.
  - Column headers turned word wrap off on a pooled label and never turned it
    back on. AceGUI's Label does not reset that, so the next owner's text was
    cut to one line. That included our own Missing Recipes empty-state
    message. A release hook turns it back on.
  - Also: the Professions tab's three next-frame redraws and the shopping-list
    refresh only checked that the tab had ever been drawn. They now check that
    the window is open on that tab (`BrowserTab:IsShowing`), so a close in the
    same frame cannot draw the tab into a TabGroup already back in the pool.

  Three specs in `Tests/mainwindow_spec.lua`. Each would fail against the old
  code (read, not run). `CLAUDE.md` said the TabGroup is not pool-recycled. That
  was wrong, and the rule now says how to undo raw changes. Whether these
  caused the Discord empty box is not shown. Location: `GUI/MainWindow.lua`,
  `GUI/BrowserTab.lua`, `GUI/SharedWidgets.lua`.

### Improvements

- **Removed: the Scan AH buttons on the Professions, Cooldowns, Missing
  Recipes and Crafting tabs** (operator on Discord, 2026-10-17: "remove the
  scan AH button from TOGPM."; inbox 546bcca7). ItemDB's own button on the
  Auction House scans the whole house in one pass, and every [AH] button and
  price in TOGPM already reads that scan. The per-tab button looked items up by
  name in the game's item cache and silently skipped any it had not seen, which
  is why Missing Recipes missed patterns that were listed (Discord, GUNNEY,
  inbox efaad501). `addon.GUI.MakeScanAHButton` and `CraftingTab:ScanAHItems`
  are gone. What the button's callbacks also did -- repaint the visible tab's
  [AH] buttons when the AH opens, closes or a scan lands -- is now
  `addon.GUI.SetAHRefresh(tab, fn)`, registered once per tab and run only for
  the active tab of an open window. The Crafting list is a row taller without
  the button, so `craftscroll_spec` scrolls to 35 rather than the list's end.
  Specs in `Tests/sharedwidgets_spec.lua`. The 12 specs that tested only the
  button are deleted (operator approval, 2026-10-17: "yes, delete the old
  tests and leftover test strings"), and so are the button's 11 locale keys
  (`BrowserScanAH*`, `CooldownsScanAHDesc`, `MissingScanAH*`, `CraftScanAH*`)
  from all 15 locale files. The six `addon.AH` scan functions only the button
  called (`StartScan`, `StartFullScan`, `CancelScan`, `IsScanning`,
  `IsFullScanning`, `GetScanProgress`) are deleted with their five specs in
  `Tests/pricefacade_spec.lua`, on Peer Review's finding (inbox 0b5694c8)
  that they had no production caller left. Location: `GUI/SharedWidgets.lua`,
  `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`, `GUI/MissingRecipesTab.lua`,
  `GUI/CraftingTab.lua`, `Modules/AHScanner.lua`, `Locale/*.lua`.
- **Less empty space above the shopping list** — the shopping-list box is an
  AceGUI InlineGroup with no title, but an InlineGroup draws its border 17 px
  below its top for a title regardless. The Professions tab now lifts the
  border to the top of the group and puts AceGUI's own anchor back when the
  pooled group is released (a keyed `OnWidgetRelease` hook). The section's
  height sum drops the strip with it: the chrome is now `SL_CHROME` (23 px),
  one exported constant the specs read instead of a hard-coded 40. A spec in
  `Tests/mainwindow_spec.lua` checks the border is lifted while showing and
  back at -17 after the window closes. Location: `GUI/BrowserTab.lua`.
- **A click spec through the row's real mouse handler** — the recipe-list
  click spec called `onRowClick` directly, skipping the library's dispatch.
  A new spec drives the row frame's own `OnMouseDown` and checks the detail
  panel shows the recipe, not the placeholder. Location:
  `Tests/browservirtual_spec.lua`.
- **The settings file is fully covered by the offline suite** (Peer Review
  thread bf2313d2, item F4). New specs drive the purge buttons and their
  confirm dialogs, the alert options, the cross-guild options and the sync-log
  window, which no spec reached before. `GUI/Settings.lua` is at 881/881
  executable lines, and the whole suite passes (1907, 0 failed). Location:
  `Tests/settings_spec.lua`.
- **A report line for the toolbar "anchor family connection" error** (seen in
  game when opening the main window from the minimap; cause not yet found,
  Peer Review thread 329b6368). Before a toolbar control's slot is laid out,
  the toolbar now checks whether that slot is already reachable through the
  toolbar's own anchors. The first time it is, it prints the chain of widgets
  once per session, so the next report names the stale widget. A loop is only
  one candidate: warcraft.wiki.gg names anchoring to the screen after a frame
  is gone instead. So if a control comes out of AceGUI's layout anchored to
  nothing, the toolbar also prints (once) every point of that control, of the
  toolbar's first control and of the toolbar, with each target and parent.
  AceGUI already runs its layout under its own error catcher, which hands the
  error to BugSack and carries on, so this changes nothing about what is drawn
  or logged; it only adds the chat line. Specs in `Tests/toolbar_spec.lua`
  drive the real AceGUI layout with a SetPoint that raises and one that does
  nothing. The test harness is pinned at `baca63c`, whose frames refuse an
  anchor loop with the client's message, so the loop spec now checks that
  AceGUI's layout hit that error and that both report lines print once. A
  control AceGUI leaves unplaced on purpose is skipped: any but the first
  child of a Fill layout, and one added after a full-height child in a Flow
  layout. Every other toolbar case now fails
  if it prints either report, so an ordinary draw can never show a player a
  false "please report this line". Location: `GUI/SharedWidgets.lua`.
- **Spec files no longer leave Settings open or stubbed timers behind.**
  `Tests/settingsbleed_spec.lua` closed Settings by calling the toggle, which
  opened it for every example that had not; it now closes through the dialog
  and moves the clock. `Tests/browserlink_spec.lua`,
  `Tests/craftsuppress_spec.lua` and `Tests/pettraining_spec.lua` now reinstall
  the base globals in `teardown`, so the next file does not load against their
  `C_Timer` / `GetTime` stubs.

---

## [v1.5.0] (2026-10-13) - Guild tab: search and filter by crafting skill; the Reagent Tracker stays open and minimises

### New Features

- **Guild tab filter strip, built from LibAceGUIWidgets.** The library's
  search box and two of its number steppers (Min skill / Max skill) sit
  above the list in toolbar slots.
  - The search matches every label on the page: a profession whose name
    matches keeps everyone in it, a specialization whose name matches keeps
    all its members, and otherwise only characters whose name matches are
    kept (case-insensitive, realm ignored; "You" finds your own characters;
    an account-mate's name finds its main, whose row reads "Alt (Main)").
    It is applied in `GuildTab:BuildTree`, which recounts from what it
    keeps. Branches open when a search starts and close when it is cleared,
    never on a refresh in between.
  - The skill steppers filter on CRAFTING skill in the profession being
    counted, and run from 1 to `addon.SKILL_CAP` (300 Classic Era, 375 TBC,
    450 Wrath, 525 Cata, 600 MoP; on Retail the highest recorded skillMax,
    else 100). The full range is no limit, and a bound filters only once
    moved off its end. A character with no recorded skill in a profession
    is hidden from it while the range is narrowed. The range is applied per
    profession in `BuildCounts`, so headcounts read "how many matching".
    Empty rows are left out while filtering.
  - The list re-lays its rows when its scroll box changes size. Before, the
    library re-laid only on its outer frame's resize; in game every row was
    40px wide and the profession names drew as ".." while the scrollbar sat
    at full width, so the last layout read the scroll box before it had its
    width (inferred from the screenshot, not instrumented). LibAceGUIWidgets
    MINOR 42 fixes it in the library (contract 0f350cea), so the hook is
    installed only on an older copy (`GuildTab:NeedsRelayoutHook`).
  - The character counts form one 80px column, centred under the
    "Characters" header, which is itself centred over that column; the space
    right of it is left free for later columns. The list's `valueColumn`
    option is LibAceGUIWidgets MINOR 42 (contract a79b0269); an older copy
    ignores it and keeps the counts at the row's right edge. The library
    scales that column by its shared scale (another addon can set it), so
    the headers are sized through `GuildTab:ColumnWidths` with
    `W:ScaledSize`, and a scale change redraws the window while the Guild
    tab shows.
  - The steppers are parked across draws by the new
    `addon.GUI.ToolbarStepper` (`GUI/SharedWidgets.lua`), like the other
    toolbar controls, so a guild sync redrawing the tab mid-typing keeps
    the box and its number.
  - A debounced search that fires after a tab switch is dropped (per-draw
    token cleared on release), so it cannot write the Guild count into
    another tab's status bar. The tab's help tooltip describes the strip.
  Location: `GUI/GuildTab.lua`, `GUI/SharedWidgets.lua`, specs in
  `Tests/guildtab_spec.lua`.
- **The Reagent Tracker stays up like Questie's tracker, and minimises.**
  It is no longer in `UISpecialFrames`, so Escape does not close it. Whether
  it is open and whether it is minimised are saved per character beside its
  position (`RT:State()`, `db.char.frames.reagentTracker`), and
  `PLAYER_ENTERING_WORLD` reopens it (`RT:Restore`) after a logout or
  /reload. A new -/+ button left of the close button folds it to its title
  bar. Dragging now writes the position fields into that record instead of
  replacing it, so the flags survive a move. The window is always anchored
  by its top-left corner (`RT:PinTop`, on build and after every drag):
  anchored by its centre, as the default spot and the game's own drag anchor
  could be, minimising pulled the title bar down toward that centre. A
  position saved as a centre anchor by an older build moves its top once,
  by half the difference between the old height and 200, on the first
  open. `SetDontSavePosition(true)` keeps the client's own layout cache
  from competing with that saved anchor, and the window is clamped to the
  screen. Location:
  `GUI/ReagentTracker.lua`, specs in `Tests/reagenttracker_spec.lua`.

### Bug Fixes

- **Every icon in the Reagent Tracker was greyed out.** The icon column
  returned `select(10, GetItemInfo(id))`, which is the icon AND every value
  after it; the RowList reads a second return as "desaturate", and the sell
  price came second. `RT:IconFor` now returns one value. The other icon
  columns were checked: each cuts to one value with `and ... or` or a plain
  field. Location: `GUI/ReagentTracker.lua`.

- **The Guild tab's column headers were drawn over the first rows of the
  list.** The list's group was added to the tab's Flow layout while the
  header group above it was still empty, so it was placed at the very top
  with the full height; filling the headers afterwards never moved it.
  `Draw` now lays the tab out again once the top group has its real height.
  Location: `GUI/GuildTab.lua`.

---

## [v1.4.0] (2026-10-11) - Item tooltips: an on/off setting for every line, no duplicate sell price, no doubled crafter names

### New Features

- **Every line TOGPM adds to an item tooltip has its own on/off setting.**
  Settings > Item tooltip gains five toggles: recipe difficulty, recipe
  sources, your characters who haven't learned the recipe, vendor buy price
  and vendor sell price. Crafters and IDs already had one each. The vendor
  rows had no setting at all; they were driven by one hidden key,
  `tooltipVendorPrices`, which `addon:MigrateVendorPriceToggles` carries onto
  both new keys once (off stays off) and then deletes -- at login and again on
  every profile switch or copy, since a login only reaches the active profile.
  A row switched off is not priced at all. The recipe-details
  mode still decides whether the recipe block may appear at all, so its three
  part toggles are greyed out under "Never". A part switched off is dropped
  before the block's "is there anything to show" test, so a block left with
  nothing still writes no heading. Location: `GUI/Settings.lua`,
  `GUI/SharedWidgets.lua`, `TOGProfessionMaster.lua`, `Locale/enUS.lua`.

### Bug Fixes

- **The crafters line and the IDs checkbox read a missing setting the opposite
  way from each other.** Tooltip.lua treated a missing `tooltipShowCrafters`
  as off although crafters has shipped on since v1.0.7 and its checkbox read
  it as on; the IDs checkbox read a missing `tooltipShowIds` as on although
  IDs ship off. Every reader now takes the shipped default. A spec that
  asserted the old silent default was rewritten to the shipped one. Location:
  `Tooltip.lua`, `GUI/Settings.lua`.
- **The Item tooltip header shared order 19.5 with the cooldown reminder
  field**, a tie between the two. The header is now
  19.505. Location: `GUI/Settings.lua`.

- **The vendor block repeated the game's own sell price.** Classic's client
  prints "Sell Price:" on item tooltips while a vendor window is open (its
  `OnTooltipAddMoney` script, classic_era `GameTooltip.lua:297`), and Retail's
  tooltip data has a `SellPrice` line type for the same thing
  (`TooltipInfoSharedDocumentation.lua:45`; when Retail emits it was not
  checked). Our "Vendor Sell" row then showed the same number a second time. The hooks now notice the game's line and our
  sell row stands down; the buy row, which the game never shows, stays. Whether
  the Classic `OnTooltipAddMoney` script fires before or after our item hook
  on every client has not been checked in game: where it fires after, the
  duplicate remains as before. Location: `Tooltip.lua`, `GUI/SharedWidgets.lua`.
- **A crafter who makes an item through two professions was listed twice**
  ("Bob, Bob"). The crafters line deduplicated per character AND profession,
  and seven Vanilla items come from two (Gold Bar is Mining's Smelt Gold and
  Alchemy's Transmute Iron to Gold). Deduplicated per character now. Location:
  `Tooltip.lua`.
- **The crafters line and the IDs line scanned every shipped recipe on every
  item hover** (~1,565 on Vanilla, twice with the IDs line on). They read the
  cached item-to-recipe index the recipe block already used, filtered to
  crafted items so a teaching scroll is never credited to the recipe's crafters.
  Each item's recipes are sorted, so "the first recipe" the recipe block and
  the IDs line describe no longer depends on table layout; the sort falls back
  to comparing as text, so a non-numeric key cannot make it raise. Location:
  `Tooltip.lua`.
- **The legacy `OnTooltipSetItem` hook skipped any item while the previous
  item's flag was still set.** It tested the flag for truthiness instead of
  comparing it to the hovered item, the same defect the Show fallback had
  already fixed for itself. The vendor block's per-hover guard had the same
  shape and now compares to the item too. Location: `Tooltip.lua`,
  `GUI/SharedWidgets.lua`.
- **A tooltip could carry two TOGPM labels.** The crafters and IDs lines open
  with "[TOGPM]" and the recipe and vendor blocks with their own "TOGPM"
  heading; the vendor block checked only whether the recipe block had written
  one. A crafted reagent with a guild crafter and a vendor price showed both.
  One flag now records that a label was written, and every later block
  continues under it. Location: `Tooltip.lua`, `GUI/SharedWidgets.lua`.
- **Per-hover flags could outlive their item** where `OnTooltipCleared` does
  not run between two hovers, which the Show fallback's own comment says can
  happen. The recipe block and the brand heading then stayed suppressed for the
  rest of the session, and the new game-sell flag could hide the sell row on
  every later item. When a different item arrives while the last one's flag is
  still set, those flags are now reset as Cleared would have; the game-sell
  flag holds the item it was set for, and the modern post-call assigns it per
  item rather than only ever setting it. Raised by Peer Review on the self-audit
  thread (245309dd). Location: `Tooltip.lua`, `GUI/SharedWidgets.lua`.
- **The IDs line's crafter count could disagree with the crafters line.** It
  counted the first recipe's raw crafters, including ones the visibility gate
  hides, so it could read "crafters=1" over an empty crafters line. It now
  counts the same list the crafters line draws. The two IDs-line builders are
  one function. Location: `Tooltip.lua`.
- **`Tooltip.lua` disabled every tooltip hook if AceHook-3.0 was missing**,
  a library the file never calls (its hooks are the frames' own `HookScript`
  and `hooksecurefunc`). The guard is gone. The crafters header's fallback
  colour was also a stale purple rather than the brand orange.
  Location: `Tooltip.lua`.

### Improvements

- **Tests:** specs for each fix above, plus the crafters sort (online first,
  then name) and the WoW Forever `TooltipUtil` path, neither of which any spec
  reached before. `Tooltip.lua` and `GUI/SharedWidgets.lua` are at 100% line
  coverage. Location: `Tests/tooltip_spec.lua`, `Tests/tooltiphooks_spec.lua`,
  `Tests/vendorprices_spec.lua`, `Tests/sharedwidgets_spec.lua`.

---

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

Older versions (v0.0.1 to v1.2.0) are in [CHANGELOG_ARCHIVE.md](CHANGELOG_ARCHIVE.md).
