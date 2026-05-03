# TOG Profession Master Changelog

## [v0.3.0] (2026-05-03) - Missing Recipes tab + AH scanner + shared widget factories

### New Features

- **New "Missing Recipes" tab** — third tab in the main window, modeled on PersonalShopper's Collector. Picks a character from a dropdown (defaults to the currently logged-in toon, includes any tracked alts on the account), then a profession from a second dropdown (filtered to professions that character has scanned), and renders every recipe scroll the character hasn't yet learned. Each row shows the scroll icon, color-coded item name, required skill, and source tags (Vendor / Drop / Quest / Crafted / Container / Fishing). Hover the icon or name for the standard item tooltip (anchored via `addon.Tooltip.Owner`); shift-click the row to insert the scroll's hyperlink into the active chat edit box. A `[Bank]` button appears at the right of each row when TOGBankClassic reports the recipe scroll in stock — click to open the standard bank-request dialog (matches the BrowserTab / CooldownsTab / ShoppingListTab `[Bank]` pattern). Search box filters by name; "Include trainer-only" checkbox unhides recipes obtainable only from a trainer (off by default to match PS, since trainer-only scrolls aren't AH-buyable). Column headers (count, Skill, Sources) now have hover tooltips explaining each column. Location: [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua).

- **Embedded recipe-universe database** — `Data/Recipes/<Profession>.lua` and `Data/Sources/<Profession>.lua`, copied verbatim from PersonalShopper's curated dataset (11 professions: Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Fishing, Leatherworking, Mining, Poisons, Tailoring). The Lua `local _, addon = ...` upvalue is per-addon, so `addon.recipeDB` and `addon.sourceDB` here are private to TOGPM and don't collide with PS even when both addons are loaded simultaneously. No optional dependency on PS — the tab works fully standalone. Location: [TOGProfessionMaster.lua](TOGProfessionMaster.lua), [Data/Recipes/](Data/Recipes/), [Data/Sources/](Data/Sources/).

- **`ReagentWatch:IsWatching(itemId)` API** — sibling to `RW:Watch` / `RW:Unwatch`. Returns true when the item is currently on the watch list. Lets the new tab toggle the `+` button between "add" and "already watching" states without poking at the underlying SavedVariable directly. Location: [Modules/ReagentWatch.lua](Modules/ReagentWatch.lua).

- **`addon.AH` module** — new shared module that mirrors the `addon.Bank` pattern for the auction house. `addon.AH.IsOpen()` tracks AH visibility via `AUCTION_HOUSE_SHOW`/`AUCTION_HOUSE_CLOSED`; `addon.AH.SearchFor(itemName)` switches the AH to Browse, populates the name field, clears any narrowing filters (level/quality/usable), and fires `AuctionFrameBrowse_Search`. `addon.AH.StartScan(items, opts)` queues `{itemId, itemName}` pairs and walks them at 1.5s intervals (rate-limit-safe), calling `QueryAuctionItems` per item with `exactMatch=true` and collecting results from `AUCTION_ITEM_LIST_UPDATE`; results cache per itemId for the session. Custom `AH_OPEN_STATE_CHANGED` and `AH_SCAN_COMPLETE` callbacks (via `addon.callbacks`) let each tab refresh its UI live as scan state changes. Auto-clears scan results when the AH closes (listings go stale fast). Targets Vanilla → MoP via the legacy `AuctionFrame` UI; retail (8.0+) needs a separate `C_AuctionHouse` path that's out of scope. Location: [Modules/AHScanner.lua](Modules/AHScanner.lua).

- **Scan AH on every tab + per-row `[AH]` button** — Browser, Cooldowns, Missing Recipes, and ShoppingList all gained "Scan AH" toolbar buttons that walk the items relevant to that tab (shopping-list reagents / cooldown reagents / missing recipe scrolls). After scan completes, rows whose item has live listings reveal an `[AH]` button next to `[Bank]`, gated on `addon.AH.GetListingsFor(itemId).count > 0` exactly like `[Bank]` is gated on `Bank.GetStock(itemId) > 0`. Click `[AH]` to jump the AH browse search to that item. Toolbar button label flips to `Scanning N/M` while running and click cancels. The Cooldowns tab's `[+] Transmute` popup also got per-row `[AH]` buttons mirroring its existing `[Bank]` pattern, so multi-reagent transmutes (Arcanite needs Thorium Bar + Arcane Crystal) get one `[AH]` per reagent row. Locations: [GUI/BrowserTab.lua](GUI/BrowserTab.lua), [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua), [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua), [GUI/ShoppingListTab.lua](GUI/ShoppingListTab.lua).

- **Cooldowns tab — two-level Profession / Cooldown filter dropdowns** — two new AceGUI dropdowns on the toolbar (next to the Ready Only button) let you narrow the cooldown list by profession then by specific shared-timer cooldown. Profession dropdown lists professions that have cooldowns in the current game version; cooldown dropdown is contextual to the selected profession and is hidden when profession is "All". Selecting a different profession resets the cooldown selection to "All" within it. Full taxonomy across all expansions: **Alchemy** (Transmute group, Alchemy Research), **Tailoring** (Mooncloth, Specialty Cloth — combined for TBC Spellcloth/Shadowcloth/Primal Mooncloth + Wrath Spellweave/Moonshroud/Ebonweave since they're spec-locked and a single tailor only has one, Glacial Bag, Dreamcloth group, Imperial Silk), **Leatherworking** (Salt Shaker — filed here because Refined Deeprock Salt is an LW reagent despite the misleading name, Magnificence group), **Enchanting** (Magic Sphere — Prismatic + Void combined, Sha Crystal), **Jewelcrafting** (Brilliant Glass, Icy Prism, Fire Prism, JC Daily Cut group), **Inscription** (Inscription Research group, Forged Documents — both faction variants combined, Scroll of Wisdom), **Blacksmithing** (Titansteel Bar, Smelting group — Balanced Trillium + Lightning Steel), **Engineering** (Jard's Energy). For alchemists, all transmute spells across all expansions collapse to a single "Transmute" entry (one shared timer per character) so the dropdown doesn't get janky. Driven by `COOLDOWN_BY_PROFESSION` at the top of [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua); the per-profession `match` predicate is the union of its cooldown entries' matches, so adding a new entry automatically extends both the cooldown dropdown options AND the parent profession's coverage with no UI plumbing changes. Location: [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua), [Locale/enUS.lua](Locale/enUS.lua).

- **Per-tab window sizing** — Cooldowns and Missing tabs are now LOCKED to a fixed 720×500 window (resize grip hidden) so switching between them produces no visible jump; only the Browser tab is resizable. Browser's last user-chosen size persists separately in `frames.mainWindow.browserWidth/browserHeight` so locked tabs can't overwrite it. Each tab declares its size policy as `WINDOW_SIZE = { width=W, height=H, locked=true }` or `{ minWidth=W, minHeight=H }`; `MainWindow:ApplyTabSize` reads the spec on Open and on every tab switch. Locations: [GUI/MainWindow.lua](GUI/MainWindow.lua), [GUI/BrowserTab.lua](GUI/BrowserTab.lua), [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua), [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua).

- **Shared GUI widget factories** — three reusable factories in a new [GUI/SharedWidgets.lua](GUI/SharedWidgets.lua) collapse what was previously ~240 lines of copy-pasted plumbing across the three tabs into ~10-line call sites: (1) `addon.GUI.MakeScanAHButton(opts)` — owns the Button widget, its label refresh closure, the OnClick handler that drives `addon.AH.StartScan`, the tooltip, and ONE module-level pair of AH callbacks that route via a small `_activeButtons` registry instead of N callbacks accumulating; (2) `addon.GUI.MakeColumnHeader(opts)` — InteractiveLabel + brand color + no-wrap + optional tooltip + optional sort onClick, enforcing the column-header rule from CLAUDE.md structurally instead of by convention; (3) `addon.GUI.AttachTooltip(widget, title, desc)` — standard hover tooltip with the Dropdown/EditBox label-area mouse trick built in (those widgets put their `SetLabel` fontstring above the body and `Control_OnEnter` fires only for the body, so hovering the label produced no tooltip; the helper detects `widget.type == "Dropdown" or "EditBox"` and adds a wrapper-frame mouse handler via `addon.AceGUIFrameScripts`). Location: [GUI/SharedWidgets.lua](GUI/SharedWidgets.lua).

### Improvements

- **Cooldowns tab — fixed-width columns for smooth resizing** — the tab originally tried responsive column widths driven by a `WINDOW_RESIZED` callback, but AceGUI's Flow layout reflowed mid-drag and the user saw rows visibly stacking into 2-3 lines and snapping back when the drag stopped. Switched to fixed widths (Char 140 / Cooldown 360 / Time 80 = 580 total) — same approach as Missing/Browser tabs, which use raw-frame virtual-scroll pools that never reflow. Combined with the per-tab window sizing, the Cooldowns tab is now locked to a single window size, so columns fit perfectly without any responsive math. Removed: `ComputeColWidths`, `GetAvailableWidth`, the `WINDOW_RESIZED` handler. Location: [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua).

- **Cooldowns tab — ready cooldowns now sort A-Z by name within the ready cohort** — every ready row had the same sort value (`-math.huge`) under the time column, and Lua's `table.sort` is not stable, so the ready cohort shuffled into a different order every redraw. With dozens of crafters running the addon, opening the window saw the same set of ready cooldowns appear in unpredictable orders, which was disorienting. Added a tiebreaker (cooldown name → character name, both ascending) that fires whenever two rows compare equal under the active sort column, so the Ready Only view stays in a stable A-Z order across refreshes. Also stabilises ties under the Character and Cooldown column sorts. Location: [GUI/CooldownsTab.lua:SortRows](GUI/CooldownsTab.lua).

- **Tab-routing extended for the new tab** — `MainWindow.TAB_DEFS` and `MainWindow:DrawTab()` now include a `missing` branch wired to `addon.MissingRecipesTab:Draw(container)`. The shared help-icon tooltip gains a `missing` entry describing the filters, trainer toggle, row actions, and source-tag legend so the in-game documentation matches the existing browser/cooldowns help text. Location: [GUI/MainWindow.lua](GUI/MainWindow.lua).

- **TOC load order extended** — 22 new data files (11 recipes + 11 sources) load after `Data/CooldownIds.lua` and before `Scanner.lua`; `Modules/AHScanner.lua` joins the modules group; `GUI/SharedWidgets.lua` loads after `GUI/MainWindow.lua` so all tabs can use the factories; `GUI/MissingRecipesTab.lua` loads after `GUI/ShoppingListTab.lua`. Location: [TOGProfessionMaster.toc](TOGProfessionMaster.toc).

### Bug Fixes

- **Cross-addon AceGUI tooltip leak — TOGPM tooltips appearing in OTHER addons' UIs** — the toolbar dropdown / search / scan-button tooltips, plus the cooldown row's right-click whisper handler, all set `widget.frame:SetScript("OnEnter", ...)` directly on AceGUI widgets. AceGUI clears `widget.events` (the SetCallback registry) on Release but does NOT reset raw frame scripts, and AceGUI pools widgets account-wide across every addon — so leftover scripts kept firing in whatever addon next acquired the recycled widget. Two-part fix: (1) new `addon.AceGUIFrameScripts(widget, scripts)` helper in [GUI/MainWindow.lua](GUI/MainWindow.lua) installs the scripts AND wires up an OnRelease cleanup that RESTORES the prior script (not nils — many AceGUI Constructors install internal `Control_OnEnter` dispatchers there that drive the SetCallback registry, and nilling them would break `widget:SetCallback("OnEnter")` for whoever recycles the widget next). (2) Migrated all toolbar tooltip attachments to use `widget:SetCallback("OnEnter")` instead of frame scripts — Button, Dropdown, EditBox, CheckBox all wire `Control_OnEnter` to fire the SetCallback registry, and AceGUI clears the registry on release for free. The frame-scripts helper is now used only for SimpleGroup right-click handlers (which have no native dispatcher). New CLAUDE.md rule documents the pattern. Locations: [GUI/MainWindow.lua](GUI/MainWindow.lua), [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua), [GUI/BrowserTab.lua](GUI/BrowserTab.lua), [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua), [CLAUDE.md](CLAUDE.md).

- **Scan AH button stayed greyed when AH opened on the active tab** — each per-tab `AH_OPEN_STATE_CHANGED` handler called `_refreshScanBtnLabel` UNCONDITIONALLY before the active-tab early-out, operating on a stale closure that captured a scanBtn from a prior tab visit (released the moment the user switched away). Calling SetText/SetDisabled on a recycled widget either no-op'd or stomped a pooled widget another addon now owned. Fixed by collapsing all three per-tab handlers into ONE module-level pair of handlers in `addon.GUI.MakeScanAHButton` that route via a small `_activeButtons[tabName]` registry — only the current tab's live button is touched. Locations: [GUI/SharedWidgets.lua](GUI/SharedWidgets.lua), per-tab handlers removed from [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua) / [GUI/BrowserTab.lua](GUI/BrowserTab.lua) / [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua).

- **Tooltips on dropdown / editbox LABELS (not bodies) didn't fire** — Dropdown and EditBox put their `SetLabel("...")` fontstring at the TOP of `widget.frame` and the actual interactive body (the dropdown button / input field) BELOW it. AceGUI's `Control_OnEnter` is wired only to the body, so hovering the label area produced no callback — the user mouseover on "Profession Filter" / "Search Recipes" labels never showed a tooltip. The new `addon.GUI.AttachTooltip` detects `widget.type == "Dropdown" or "EditBox"` and additionally enables mouse on `widget.frame` + wires a raw OnEnter via `addon.AceGUIFrameScripts` — covering the label area while preserving release-time cleanup. Location: [GUI/SharedWidgets.lua](GUI/SharedWidgets.lua).

- **Cooldowns transmute popup — multi-reagent transmutes collapsed to one row** — the cooldown branch in `BuildRows` used the hardcoded single-reagent `data.transReagents` map for every cast spellId, then marked `seenSpellIds` to block the multi-reagent recipe-DB branch from re-emitting. So Arcanite (Thorium Bar + Arcane Crystal) showed ONE row with whichever reagent the hardcoded map happened to list, instead of TWO adjacent rows. Restructured: the cooldown branch now consults the recipe-DB (which captures multi-reagent data from the alchemist's actual trade-skill scan) FIRST, falling back to `data.transReagents` only when the recipe scan didn't cover that spell. The recipe-DB branch then only runs for spells the cooldown branch didn't already emit. Location: [GUI/CooldownsTab.lua:BuildRows](GUI/CooldownsTab.lua) transmute group section.

- **Cooldowns tab — Scan AH didn't include transmute reagents** — `getItems` iterated `row.reagentItemId`, but transmute group rows have `reagentItemId = nil` because each transmute inside the group has its own reagent (sometimes multiple). The scan only picked up standalone non-transmute cooldowns (Salt Shaker, Mooncloth, etc.) — Arcane Crystal, Thorium Bar, Iron Bar, etc. were never queried. Now iterates `row.transmuteEntries[].reagentId` for transmute group rows so the scan covers everything the user can actually craft. Location: [GUI/CooldownsTab.lua:MakeScanAHButton getItems](GUI/CooldownsTab.lua).

- **Enchanting recipes broadcast as `? <id>` with "Retrieving item information" tooltips, never resolved by `/togpm backfill`** — Enchanting recipeIds are enchant SPELL IDs, but `MergeCraftersIntoGdb`'s stub creation only tried `GetItemInfo(recipeId)`, which returns nil for spell-only IDs. The resulting nameless stub left `isSpell`/`spellId` unset, and `BackfillBogusRecipeNames` then refused to call `GetSpellInfo` on it because its spell branch was gated on `rd.isSpell == true or rd.spellId` (both nil for the stub). BrowserTab's tooltip code fell through to `SetHyperlink("item:<id>")`, which is exactly what surfaces the "Retrieving item information" message in WoW for IDs the client treats as items it doesn't have cached. Two-part fix: (1) `MergeCraftersIntoGdb` now tries `GetSpellInfo` as a fallback when `GetItemInfo` fails, populating the stub's name/icon/isSpell/spellId in one shot. (2) `BackfillBogusRecipeNames`'s spell branch now runs unconditionally (bounded only by the bogus-name + numeric-recipeId guards). `GetSpellInfo` returns nil for non-spell IDs so there are no false positives. Locations: [Scanner.lua:MergeCraftersIntoGdb](Scanner.lua), [Scanner.lua:BackfillBogusRecipeNames](Scanner.lua).

### Performance

- **Missing Recipes tab — virtual-scroll rendering with raw frame pool (35 rows)** — initial implementation rendered every visible missing-recipe row as ~6 AceGUI widgets, so a profession with 500+ missing recipes spawned 3000+ AceGUI children and the layout pass froze the WoW client. Even capping at 100 rendered rows still produced 600 widgets — enough to choke AceGUI's layout. Switched the result body to mirror [GUI/BrowserTab.lua](GUI/BrowserTab.lua)'s pattern: a pool of 35 raw `CreateFrame` rows parented to the AceGUI ScrollFrame's content frame, repositioned and re-skinned as the user scrolls. Total widget count is now bounded at 35 regardless of list size. Pool is persistent across `RefreshList` (search keystrokes / trainer toggle / profession switch) via a new `DetachPool` helper that re-parents to UIParent on ScrollFrame release rather than destroying frames — WoW frames are session-lifetime and never GC'd, so destroying-and-rebuilding 35 frames on every search keystroke would leak. Location: [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua).

- **Missing Recipes tab — build pass no longer calls `GetItemInfo`** — initial implementation called `GetItemInfo(spellId)` inside the build loop to filter rows by recipe-scroll prefix; for Tailoring (~3000 recipes) this triggered thousands of simultaneous async cache loads, locking the WoW client for ~20 seconds and tripping `Script from "Bagnon" has exceeded its execution time limit` warnings (Bagnon registers for `GET_ITEM_INFO_RECEIVED` and re-runs its handler for every cache fill). Restructured: build pass uses `sourceDB` presence as the recipe-scroll proof (no `GetItemInfo`), all `gdb` lookups are hoisted out of the per-recipe loop. Per-row `GetItemInfo` runs only inside `UpdateVirtualRows` for the 35 currently-visible rows, so cache-miss volume is bounded by the visible window. A debounced `GET_ITEM_INFO_RECEIVED` handler refreshes the list 0.5s after the cache-fill burst settles so placeholder names get replaced once items finish loading. Search filtering uses `GetItemInfoInstant` (does not trigger async loads) so typing in the search box never re-fires the cache-miss firestorm. Search keystrokes are debounced 200ms so each character typed doesn't trigger a full rebuild. Location: [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua).

---

## [v0.2.7] (2026-05-01) - Transmute popup overhaul: known-transmute list, multi-reagent rows, anchored positioning

### New Features

- **The transmute group popup now lists every transmute the alchemist knows, not just the ones currently on cooldown** — clicking the `[+] Transmute` row used to show only the spells with active cooldown records, which meant if Alice had cast Earth-to-Water 3 hours ago and you wanted to send her materials for Iron-to-Gold (which she hadn't cast recently and so had no cooldown record), the row simply wasn't there. The popup now augments the cooldown-derived spell list with every transmute recipe in `gdb.recipes[171]` where `crafters[charKey]=true` — the alchemist's full learned-transmutes set. Each row shows time-remaining when on cooldown, "Ready" in green otherwise, with its own reagent label, `[Bank]`, and mail icon. Location: [GUI/CooldownsTab.lua:BuildRows](GUI/CooldownsTab.lua) transmute group section.

- **Multi-reagent transmutes render as one row per reagent** — Arcanite Bar requires both 1 Thorium Bar and 1 Arcane Crystal; previously the popup collapsed it into a single row showing only one reagent because the hardcoded `data.transReagents` map only stores one reagent per spell. Now each transmute emits one row per reagent from the alchemist's actual `rd.reagents` scan, with name and time-remaining shown only on the first row of the group so the visual grouping stays clean. Each row's `[Bank]` and mail buttons act on its own reagent independently — useful when you have one reagent in stock but not the other. Location: [GUI/CooldownsTab.lua:ShowGroupPopup](GUI/CooldownsTab.lua), entry-build path.

- **`addon.Tooltip.AnchorFrame(frame, source)` helper** — sibling to `addon.Tooltip.Owner` ([Compat.lua](Compat.lua)). Anchors any popup/dialog to a source widget using the same screen-half logic that places GameTooltips: source in upper half → popup below source; source in lower half → popup above source. Accepts either a raw Frame or an AceGUI widget (unwraps via `widget.frame`). The transmute popup uses this to sit adjacent to the row that opened it instead of centering on the screen — the user can mouse straight onto it without losing context. Reusable for any future click-popup that wants tooltip-like positioning.

### Bug Fixes

- **Transmute popup appeared centered on the screen far from the row that opened it** — `popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)` always anchored to the middle, requiring the user to drag their mouse across the UI to interact with it. Switched to `addon.Tooltip.AnchorFrame(popup, sourceWidget)`, where `sourceWidget` is the AceGUI InteractiveLabel that received the click. The popup now sits directly below the row when the row is in the top half of the screen, and above it when the row is in the bottom half — same ergonomics as a tooltip. Location: [GUI/CooldownsTab.lua:ShowGroupPopup](GUI/CooldownsTab.lua).

- **Reagent label and `[Bank]` button stacked on top of each other in the transmute popup** — both were anchored at `SetPoint("RIGHT", entry, "RIGHT", -(mailW + 2), 0)`, the same offset, so they overlapped. Moved the reagent label `(bankW + 2)` further left so it sits cleanly to the LEFT of the bank button. Also bumped popup width 400→460 for breathing room. Location: [GUI/CooldownsTab.lua:ShowGroupPopup](GUI/CooldownsTab.lua) reagent label SetPoint.

- **Tooltips on the transmute popup rows rendered visually behind the row text instead of on top** — the popup is at `TOOLTIP` strata, which is also `GameTooltip`'s default strata. Same strata means whichever has higher frame level wins, and the popup's child labels/buttons win by default. Added a `showAbovePopup()` helper called after every `GameTooltip:Show()` in the popup that bumps the GameTooltip's frame level above the popup's. Spell, item, [Bank], and mail tooltips all now render on top. Location: [GUI/CooldownsTab.lua:ShowGroupPopup](GUI/CooldownsTab.lua).

- **`[Bank]` buttons missing from the first transmute popup of a session, but appearing in subsequent popups** — TOGBankClassic constructs `_G.TOGBankClassic_Guild.Info.alts` lazily; the first `addon.Bank.GetStock(reagentId)` call during the popup creation loop hit that uninitialized state and returned 0, so no [Bank] button was created for any row. Subsequent popups queried after TOGBank had populated and worked normally. Fixed by always creating the bank button (initially hidden) and registering a per-row visibility refresher that runs on `popup:OnShow` plus a deferred `C_Timer.After(0.1, ...)` tick — so even when TOGBank's data lands asynchronously after our popup opens, the buttons reveal themselves without requiring the user to close and reopen. Also changed `popup:Show()` to follow an explicit `popup:Hide()` after `CreateFrame`, so OnShow fires the actual hidden→shown transition. Location: [GUI/CooldownsTab.lua:ShowGroupPopup](GUI/CooldownsTab.lua) bank-refresher block.

- **Non-alchemist viewers couldn't see proper spell tooltips for transmutes the alchemist had broadcast with `rd.spellId = nil`** — `RefreshTransmuteCatalogueFromRecipes` had only one resolution path: `GetSpellLink(rd.name)`, which only works for spells the local player knows. On a non-alchemist viewer, GetSpellLink returns nil for every transmute, so `rd.spellId` stayed nil and hover tooltips fell through to the output-item link. Added a static-catalogue name-match fallback that runs *first*: walk `data.transmutes` (the cumulative VANILLA / TBC / WRATH / CATA / MOP transmute table), find the entry whose name matches `rd.name`, and assign that spellId. Resolution works for non-alchemists because it's pure string compare against hardcoded data — no spell-knowledge required. Location: [Data/CooldownIds.lua:RefreshTransmuteCatalogueFromRecipes](Data/CooldownIds.lua).

### Improvements

- **Removed the `MINOR>=N` runtime version check on DeltaSync-1.0** — the addon previously gated guild sync on a hard-coded `LibStub.minors["DeltaSync-1.0"] >= N` check in `Scanner:InitDeltaSync`, which made the addon's source contain library version assumptions that drift over time. Library version compatibility is the responsibility of the `## Dependencies` declaration in the .toc, not a runtime check. Removed the check entirely; if a too-old DeltaSync is installed, behavior degrades gracefully via the existing `if not DS then return end` guard. Location: [Scanner.lua:InitDeltaSync](Scanner.lua).

- **Hover tooltip on every popup row, even when no spellId is available** — for transmute rows that propagated with `rd.spellId = nil`, the name zone now falls back to `GameTooltip:SetHyperlink("item:" .. recipeId)` which shows the output item's tooltip (since `recipeId` IS the output item ID for non-spell recipes). Less informative than the spell tooltip, but better than nothing. The static-catalogue name-match fallback above means most rows actually do get the proper spell tooltip now. Location: [GUI/CooldownsTab.lua:ShowGroupPopup](GUI/CooldownsTab.lua) name-zone OnEnter.

- **"Ready" label in green for transmutes castable right now** — replaced the previous `?` placeholder when a spell had no cooldown record. Both "no record" and "expired record" now render as `Ready` in `|cff00ff00` so the user can tell at a glance which transmutes are available to send materials for. Location: [GUI/CooldownsTab.lua:ShowGroupPopup](GUI/CooldownsTab.lua) row time-string formatting.

---

## [v0.2.6] (2026-04-30) - Recipe display recovery + lazy item-cache backfills + sync robustness

### Bug Fixes

- **Tailoring (and other) recipes showed as `? <id>` in the recipe browser** — when a peer's `crafters:<profId>` leaf arrived before the matching `recipemeta:<profId>` leaf, `MergeCraftersIntoGdb` created a stub `{crafters={}}` entry with no name/icon/links. The browser row then rendered the default question-mark icon plus `tostring(recipeId)` as the name — visually "? 10002" — even though hovering the row showed the proper name (BrowserTab falls back to `SetHyperlink("item:<id>")` for tooltips, which WoW resolves from its own item cache). Three-pronged fix: (1) new `cleanRecipeName` helper extracts the real name from the `[...]` portion of itemLink/recipeLink when the raw scan name is a placeholder; (2) `MergeCraftersIntoGdb` now populates name/icon/itemLink from `GetItemInfo(recipeId)` at stub creation so even the first-paint render is correct when the item is cached; (3) `MergeRecipeMetaIntoGdb` self-heals on receive — if the stored name is a placeholder, replace it with the cleaned-up version from the new payload. Locations: [Scanner.lua:cleanRecipeName](Scanner.lua), [Scanner.lua:MergeCraftersIntoGdb](Scanner.lua), [Scanner.lua:MergeRecipeMetaIntoGdb](Scanner.lua).

- **Clicking [Bank] on a reagent row in the recipe drilldown did nothing for some users (the button was visible, the click just didn't open the popup)** — the recipe drilldown's reagent row is a `Button` frame and had `SetScript("OnClick", ...)` for shift-click-to-insert-link. The child `[Bank]` button is also a `Button` with its own OnClick handler. On some WoW builds the parent-Button's OnClick swallows the click before the child-Button's OnClick can fire — explaining why the recipe-row [Bank] button (whose parent uses `OnMouseDown`, not `OnClick`) always worked, while the reagent-row [Bank] button intermittently didn't. Same fix as the recipe row: switch the parent's shift-click handler from `OnClick` to `OnMouseDown`. Different event = no conflict, child's OnClick fires normally. Location: [GUI/BrowserTab.lua:DrawDetail](GUI/BrowserTab.lua) reagent-row mouse-script setup.

- **Transmute on the cooldown tab showed the specific spell name (e.g., "Earth to Water") instead of grouping into a generic "[+] Transmute" row with the per-spell popup, on non-alchemist viewers** — the cooldown tab's `BuildRows` checks `data.transmutes[spellId]` to recognise a cooldown as a transmute. The runtime augmentation that adds Anniversary client spell IDs to `data.transmutes` (`addon:RefreshTransmuteCatalogueFromRecipes`) only ran inside `ScanCooldowns`, which fires off the LOCAL player's scan events. Non-alchemists rarely trigger it, so when an alchemist's transmute spell ID arrived via guild sync it never made it into the catalogue, and the row fell through to a regular per-spell display with no popup, no per-transmute reagents, and no per-transmute mail button. Fixed by calling the augmentation at the start of `BuildRows` itself — idempotent, cheap, runs every render. The recipe DB (populated from the alchemist's broadcast carrying spellIds backfilled via `GetSpellLink`) supplies all the IDs needed. Once augmented, the transmute group + click-to-expand popup with per-spell reagents and `[Bank]` / mail buttons works as designed. Location: [GUI/CooldownsTab.lua:BuildRows](GUI/CooldownsTab.lua).

- **Roll-up sync sessions could stay in ACTIVE state after a subhashes drill-down dispatched its child leaf-data requests** — when our addon received a subhashes response for `guild:cooldowns` or `guild:accountchars` and dispatched per-character leaf-data follow-ups in response, the parent session was never explicitly marked complete; it lingered until the underlying delivery timeout fired. With the parent's lifecycle now bracketed correctly — child leaf sessions are tracked independently and complete on their own data arrival — the roll-up's session slot is freed as soon as its drill-down dispatches, restoring full session-slot availability for the leaf fetches that follow. Location: [Scanner.lua:OnGuildDataReceived](Scanner.lua) subhashes branch.

### Improvements

- **Recipe-name and reagent-itemId backfills now run multiple passes with cache-loading fallback** — both backfills are scheduled at 3s/30s/120s post-login. The reagent backfill adds a third recovery path that calls `GetItemInfo(name)` (cache-loading variant), which returns `nil` on first call but issues an async server-side load — the next retry pass picks up the result via `GetItemInfoInstant` once the load resolves. The recipe-name backfill walks `gdb.recipes` and re-runs the full recovery chain (link `[...]` extract → `GetItemInfo(recipeId)` for items → `GetSpellInfo(spellId)` for spells), so both placeholder names and crafters-only stubs heal as the WoW item cache fills. Each pass logs only when something was actually checked, so silent runs after the data is healed don't spam chat. Locations: [Scanner.lua:BackfillReagentItemIds](Scanner.lua), [Scanner.lua:BackfillBogusRecipeNames](Scanner.lua), [Scanner.lua:Init](Scanner.lua).

- **Diagnostic ENTRY prints in guild-sync handlers** — when `/togpm debug` is on, `Scanner: onDataReceived ENTRY ...`, `Scanner: onDataRequest ENTRY ...`, `Scanner: OnGuildDataReceived ENTRY ...`, and `Scanner: onSyncAccepted ...` fire at every handler entry, plus a `BAIL — <reason>` line on each early-return path of `OnGuildDataReceived`. Without entry-level prints, when a sync handler silently no-op's (malformed payload, own echo, no guild, etc.) nothing is logged — making receive-side failures invisible. Now any future receive-path issue is observable from the user's chat without instrumenting code. Locations: [Scanner.lua:InitDeltaSync](Scanner.lua), [Scanner.lua:OnGuildDataReceived](Scanner.lua).

- **P2P concurrency limits raised for active guilds** — increased inbound and outbound concurrency from 3 to 8 and stretched the offer-collect window from 10s to 30s. In active 30+ member guilds the prior caps saturated within seconds because every peer was at the same limit, queuing requests faster than they drain. Higher caps plus a longer collect window let more sessions dispatch in parallel and accumulate offers from more peers before picking, increasing the odds of finding a peer that isn't at its own cap. Location: [Scanner.lua:InitDeltaSync](Scanner.lua).

- **`/togpm backfill` slash command runs both backfills** — runs the reagent-itemId backfill and the recipe-name backfill back-to-back. Useful for re-attempting on demand after the WoW item cache has had more time to populate (e.g., after opening a few trade-skill windows). Location: [TOGProfessionMaster.lua:RunBackfill](TOGProfessionMaster.lua).

---

## [v0.2.5] (2026-04-29) - GetSpellLink transmute-ID fallback + personal bank / mail in reagent counts

### Bug Fixes

- **Transmutes still didn't show on the cooldown tab on Classic Era Anniversary even with v0.2.4** — the v0.2.4 runtime-augment path required `rd.spellId` to be populated by `BuildSpellNameCache` (spellbook tab iteration via `GetNumSpellTabs` / `GetSpellBookItemInfo`). On Anniversary, transmute spells don't appear in that enumeration, so `ScanTradeSkillInto` stored the recipe with `rd.spellId = nil` and the augment path had nothing to do. Section 5 of `/togpm transmutedebug` showed transmute recipes present but with nil spellIds, confirming the spellbook-scan miss. Fixed by adding a `GetSpellLink(rd.name)` fallback in `RefreshTransmuteCatalogueFromRecipes` — `GetSpellLink` works for any known spell by name regardless of spellbook presentation, returns `|Hspell:NNNNN|h` from which we extract the ID, and the ID is also backfilled onto `rd.spellId` so the rest of the cooldown chain (`knownTransmutes` filter, cooldown-tab grouping) works. Location: [Data/CooldownIds.lua:RefreshTransmuteCatalogueFromRecipes](Data/CooldownIds.lua).

### Improvements

- **Reagent Tracker and Reagent Watch now show personal bank + mail alongside bag count** — the `have` total is now `bags + cached personal bank + cached mail`, where personal bank is scanned on `BANKFRAME_CLOSED` and mail is scanned on `MAIL_CLOSED` (mirroring TOGBankClassic's scan-on-close pattern). COD mail attachments are excluded (not really yours until you pay, matching TOGBank). TOGBankClassic guild-bank stock stays separate, surfaced as a `+<N>` annotation in the row — the user previously asked to keep guild-bank stock visually distinct from "in possession", so personal bank/mail join the `have` side and only TOGBank stays separate. New `Ace.db.char.bankCounts` and `Ace.db.char.mailCounts` cache per-character. First-visit-required: until the user opens their bank or mailbox once with v0.2.5 installed, the caches are empty (same first-time UX as TOGBank). Locations: [Modules/ReagentWatch.lua](Modules/ReagentWatch.lua), [GUI/ReagentTracker.lua:GetPlayerBagCount](GUI/ReagentTracker.lua), [GUI/ShoppingListTab.lua:FillReagentWatch](GUI/ShoppingListTab.lua).

- **Reagent Tracker color coding now reflects bag-vs-bank-vs-shortage** — green = bags alone satisfy the recipe; yellow = bags fall short but bag + bank covers it (request from bank); orange = bag + bank still short, partial; red = nothing in bags or bank. The `+<N>` bank annotation is light blue and always shown when bank stock > 0, deliberately separated from the `have/need` count so the player can read the bank contribution without it being conflated with personal possession. Display widened (`COUNT_W` 48 → 90, `WIN_W` 280 → 320) to fit the new format. Location: [GUI/ReagentTracker.lua:Refresh](GUI/ReagentTracker.lua).

- **Reagent Watch panel applies the same color scheme** — green = in your bags, yellow = only in the guild bank, grey = nowhere. Same `+<N>` annotation pattern. Location: [GUI/ShoppingListTab.lua:FillReagentWatch](GUI/ShoppingListTab.lua).

- **`/togpm transmutedebug` now also runs the runtime augmentation up front** — so the diagnostic reflects post-refresh state, including any spellIds resolved via the new `GetSpellLink` fallback. Prints a confirmation line when new IDs were added. Location: [TOGProfessionMaster.lua:DumpTransmuteDiag](TOGProfessionMaster.lua).

---

## [v0.2.4] (2026-04-29) - Runtime-augmented transmute catalogue + extended transmutedebug

### Bug Fixes

- **Transmutes never showed up on the cooldown tab on Classic Era Anniversary (and any client whose actual spell IDs don't match `VANILLA_TRANSMUTES`)** — the static spell-ID catalogue in `Data/CooldownIds.lua` was the only thing `ScanCooldowns` consulted. If the alchemist's actual transmute spells used different spell IDs than the ones we hard-coded (a real condition on Anniversary, where the recipe DB shows transmutes with spellIds that aren't in our catalogue), `GetSpellCooldown` was called with the wrong IDs, the recipe-DB filter found zero matches, and nothing got stored. New `addon:RefreshTransmuteCatalogueFromRecipes()` walks `gdb.recipes[171]` for any recipe whose name contains "Transmute" and adds its `spellId` to `data.transmutes` at runtime. Idempotent, cheap, runs at the start of every `ScanCooldowns`. The catalogue self-heals against any client-specific or locale-specific ID variation, picks up newly-learned transmutes from guildmate broadcasts, and the rest of the cooldown chain (cooldown-tab grouping, transmute popup, mail integration) works as a side effect. Locations: [Data/CooldownIds.lua:RefreshTransmuteCatalogueFromRecipes](Data/CooldownIds.lua), [Scanner.lua:ScanCooldowns](Scanner.lua).

### Improvements

- **`/togpm transmutedebug` now also dumps the actual alchemy recipe DB and a spellbook walk** — v0.2.3's diagnostic only showed which transmutes matched our catalogue. If the catalogue was stale, the diagnostic showed all zeros without a way to tell *why*. v0.2.4 adds two more sections: (5) total alchemy recipes in `gdb.recipes[171]` for the local char with their actual `spellId` values (filtered to anything whose name contains "Transmute"), and (6) a full spellbook walk for any spell whose name contains "Transmute" with the spell ID the client is actually using. If section 6 prints IDs that aren't in the catalogue, the new runtime augmentation will pick them up automatically; it's still a useful triage signal. Location: [TOGProfessionMaster.lua:DumpTransmuteDiag](TOGProfessionMaster.lua).

---

## [v0.2.3] (2026-04-29) - /togpm transmutedebug diagnostic command

### New Features

- **`/togpm transmutedebug`** — one-shot diagnostic for the transmute-cooldown chain. Prints what the WoW API says is on cooldown, what's in the recipe DB for the local character, what `IsSpellKnown` says, and what's actually stored in `gdb.cooldowns`. No spell IDs to look up — just run it and paste the output. Useful for triaging "transmute isn't showing on the cooldown tab" reports without making the user dig up spell IDs. Location: [TOGProfessionMaster.lua:DumpTransmuteDiag](TOGProfessionMaster.lua).

---

## [v0.2.2] (2026-04-29) - Cumulative cooldown ID loading across expansions

### Bug Fixes

- **Transmute cooldowns from earlier expansions never showed up on Cata/MoP clients** — `Data/CooldownIds.lua:Build()` loaded transmute and cooldown spell IDs version-exclusively: only `CATA_TRANSMUTES` on Cata, only `WRATH_TRANSMUTES` on Wrath, etc. But spell IDs from earlier expansions stay valid on later clients — a Cata alchemist still has the 18 Wrath Eternal transmutes, the TBC primal transmutes, and the Vanilla element transmutes in their spellbook, all sharing the same 24-hour cooldown. Casting any one of them was invisible to our scan because we never iterated those IDs in `ScanCooldowns`. Symptom: Cata alchemist casts Eternal Fire to Water → cooldown tab shows nothing for them. Same root cause for non-transmute cooldowns (Mooncloth, Spellcloth, Icy Prism) on later-expansion clients. Fixed by changing `Build()` to load IDs cumulatively — the current expansion plus every earlier one. Doesn't change behavior on Classic Era (only Vanilla IDs load, same as before). Location: [Data/CooldownIds.lua:Build](Data/CooldownIds.lua).

---

## [v0.2.1] (2026-04-29) - v0.2.0 sync convergence fixes

### Bug Fixes

- **Cooldowns weren't syncing between peers — drill-down chain never fired** — `HashManager:HasContent` returned `false` for `guild:cooldowns` and `guild:accountchars` roll-up keys, on the (incorrect) reasoning that we don't directly serve roll-up data. But DeltaSync's `OnHashListReceived` gates offers on `hasContent(itemKey)` — peers with stale data wouldn't offer for the roll-up because `hasContent` said no, the broadcaster never received an offer for `guild:cooldowns`, `onSyncAccepted` never fired, and the subhashes drill-down never happened. Symptom: PC with 10 cooldowns broadcasting; PC with 3 cooldowns receiving the broadcast but never reporting back. Fixed by returning `true` for `guild:cooldowns` when we have any cooldowns in `gdb.cooldowns`, and similarly for `guild:accountchars`. We don't serve the roll-up *data* — the offer triggers `onSyncAccepted` which calls `BroadcastSubhashesToGuild`, sending the per-character sub-hash list. Location: [Modules/HashManager.lua:HasContent](Modules/HashManager.lua).

- **Idle peers never broadcast — protocol can't push to them** — v0.2.0's broadcasts only fire on event triggers (cooldown scan, recipe scan, login). With differential broadcasting, an idle peer's "no changes since last broadcast" results in a skipped send. Other peers never see the idle peer's hashes, so they never offer fresh data, so the idle peer never receives anything. The protocol doc specified a 10-minute periodic broadcast for exactly this case but the implementation only had event-driven broadcasts. Added a 10-minute repeating timer in `Scanner:Init` that resets `_lastBroadcastHashes = nil` and broadcasts the full L0 hash list (non-differential), guaranteeing every peer is on the wire at least every 10 minutes regardless of local activity. Location: [Scanner.lua:Init](Scanner.lua).

- **Cooldowns tab scroll bar always visible and extending ~2x the window height below the bottom edge** — `CooldownsTab:Draw` set the container's layout to `"List"`, but AceGUI's List layout doesn't honor `child.height == "fill"` — it only manages widths. Only the Flow layout reads `SetFullHeight(true)` and anchors the child's BOTTOM to the parent content. Without that anchor, the AceGUI ScrollFrame's outer frame grew unbounded past the window edge and the scrollbar grew with it. Fixed by switching the container layout from `"List"` to `"Flow"`. Toolbar, headers, and scroll all already had `SetFullWidth(true)`, so Flow stacks them vertically the same way List did — Flow just additionally constrains the scroll's height to fit the remaining space. Location: [GUI/CooldownsTab.lua:Draw](GUI/CooldownsTab.lua).

### How to Force Sync on Already-Stale Data

If you upgraded between PCs and one is missing data, the periodic tick will catch up within 10 minutes. To force immediate sync, run `/togpm forcebroadcast` on the **less-data** PC — that broadcasts its hashes, peers see the mismatch, peers offer, your PC fetches the subhashes and missing leaves, and merges within seconds.

---

## [v0.2.0] (2026-04-29) - Hash-then-fetch sync protocol, content-aware merge, relay-capable cooldowns + recipes

### Major Protocol Overhaul

- **Replaced full-payload broadcast with hash-then-fetch sync** — v0.1.x broadcast each peer's full ~30 KB profession + cooldown payload to the guild every 30 seconds, multiplied by every active broadcaster. v0.2.0 broadcasts a tiny ~600 B leaf-hash list per peer every 10 minutes (differential — only leaves whose content has changed). Peers compare hashes; on mismatch they whisper a short handshake; the chosen sender broadcasts only the differing leaf's data on the GUILD/BULK channel, where every peer with stale data merges for free. Steady-state guild traffic drops by orders of magnitude. See [docs/v0.2.0-protocol.md](docs/v0.2.0-protocol.md) for the full design. Locations: [Scanner.lua](Scanner.lua), [Modules/HashManager.lua](Modules/HashManager.lua).

- **Content-aware merge replaces destructive overwrite** — `OnGuildDataReceived` now merges per leaf type so anyone with cached data can serve it without risk of clobbering fresher data: cooldowns merge with `max(local.expiresAt, incoming.expiresAt)` per (charKey, spellId); recipe metadata merges richest-non-nil per field via the existing `mergeReagents` helper; crafter sets union-add for relayed payloads and wipe-then-re-add when the broadcaster claims an authoritative own-scan; account-char groups replace authoritatively for the broadcaster's own slot and union for relayed slots. Receiving from any peer always converges to the same state. Locations: [Scanner.lua:OnGuildDataReceived](Scanner.lua), [Scanner.lua:MergeRecipeMetaIntoGdb](Scanner.lua), [Scanner.lua:MergeCraftersIntoGdb](Scanner.lua).

- **Cooldowns and recipes now relay through any peer** — `HashManager:HasContent` returns true for any locally-cached leaf, not just owner-owned. If Alice's alchemist is offline, Bob's cached copy of `cooldown:Alice-Realm` can serve the leaf to Carol when she logs in. Recipe metadata + crafter membership relay similarly. Cooldown coverage no longer requires the data owner to be online. Location: [Modules/HashManager.lua:HasContent](Modules/HashManager.lua).

- **Hash + timestamp invariant: both immutable per data state** — Each leaf entry `{hash, updatedAt}` is a co-determined function of the data: both change atomically when content changes, both stay frozen otherwise. `updatedAt` is content-derived from `gdb.lastScan[charKey][scope]`, never `GetServerTime()` at a no-op site. The v0.1.x `HashManager:RebuildAll` re-stamped every leaf's `updatedAt` on every receive — even no-op merges — which was the root cause of the "stale relayer with high updatedAt suppresses fresh owner's offer" routing bug. Replaced with targeted `Invalidate*` helpers that no-op when the new tuple matches existing. Location: [Modules/HashManager.lua:setEntry](Modules/HashManager.lua).

### New Hash Leaf Taxonomy

Replaces v0.1.x's `cooldown:<charKey>` + `recipes:<profId>` + `guild:cooldowns` + `guild:recipes` with:

- `recipemeta:<profId>` — immutable recipe metadata for one profession (rare-change, bootstrap-only after first sync).
- `crafters:<profId>` — crafter membership map for one profession (frequent, deltas).
- `cooldown:<charKey>` — full cooldown bucket for one character.
- `accountchars:<charKey>` — alt group claimed by one broadcaster.
- `guild:cooldowns` and `guild:accountchars` — structured roll-ups over per-character leaves; broadcast at L0 with per-character leaves drilled-down on roll-up mismatch.

L0 broadcast carries 9 + 9 + 2 = 20 hashes × ~30 B per peer ≈ 600 B. Per-character leaves stay out of L0 to avoid 300-500-leaf broadcast bloat for large guilds.

### Channel Allocation

GUILD/BULK for hash list broadcasts and per-leaf data responses (high throughput, throttle-tolerant); WHISPER for handshake control messages only (offers, requests). Whisper throttling no longer constrains bulk transfer.

### Storage Changes

Two new top-level fields on each guild bucket; existing data is preserved verbatim:

- `gdb.accountChars[broadcasterKey] = { charKey, ... }` — per-broadcaster authoritative alt group. `gdb.altGroups` becomes a derived view rebuilt from this.
- `gdb.lastScan[charKey][scope]` — content-derived timestamps (where `scope` is a profId, `"cooldowns"`, or `"accountchars"`). HashManager reads these to compute leaf `updatedAt`.

### Wire Format

Bumped DeltaSync namespace `TOGPmv1` → `TOGPmv2` to prevent v0.1.5 ↔ v0.2.0 cross-talk during rollout. v0.1.5 peers don't see v0.2.0 broadcasts and vice versa; once everyone upgrades, the v0.1.5 namespace dies.

Per-leaf payload format (`payload.leaves[itemKey] = { data, hash, updatedAt }`) carries content + the source's hash tuple. Multiple leaves can ride in one broadcast. Sub-hash drill-down responses (`payload.type = "subhashes"`) carry per-character hashes for one roll-up parent.

### Dependency Bump

Requires DeltaSync-1.0 MINOR>=9 (shipped in DeltaSync v2.0.3, 2026-04-29). The new offer condition (hash-mismatch instead of `updatedAt > peer's`) is required for the relay-capable sync model; older DeltaSync versions still load the addon but `Scanner:InitDeltaSync` refuses to enable sync and prints a clear error. Location: [Scanner.lua:InitDeltaSync](Scanner.lua).

### New Diagnostic Commands

- `/togpm dumphashes` — print the local L0 hash list (itemKey, hash, updatedAt) for cross-peer comparison.
- `/togpm dumpcooldowns [charKey]` — print stored cooldown bucket for a character (no arg = list every character with cooldowns).
- `/togpm forcebroadcast` — bypass the 10-min debounce and broadcast a full (non-differential) hash list immediately.

### Bug Fixes

- **Cooldowns tab letter (mail) icon wrapping under the cooldown name** — AceGUI Flow's wrap math `(framewidth + usedwidth > width)` is strict-greater, but in practice the mail icon was wrapping to a new row even when the inner widget widths summed exactly to col2's 456px. Reserved 12 px of slack in the `cdNameW` calculation so even a small rounding/padding discrepancy in any AceGUI Label widget can't push the row total past col2 width. Location: [GUI/CooldownsTab.lua:611-622](GUI/CooldownsTab.lua#L611-L622).

### Migration Notes

No existing data is destroyed. On first v0.2.0 load `gdb.accountChars` and `gdb.lastScan` initialize empty and populate as scans run + broadcasts arrive. `gdb.altGroups` is rebuilt from `gdb.accountChars` whenever it changes. Old `recipes:<profId>` hash entries become unused garbage in `gdb.hashes` and can be cleaned up in a future version. Existing recipes, cooldowns, and skill ranks remain usable through the merge.

---

## [v0.1.5] (2026-04-29) - Transmute cooldowns, reagent itemId capture, non-destructive merge, Reagent Tracker bag-vs-bank fix

### Bug Fixes

- **Transmute cooldown was detected but never stored — Cooldowns tab showed nothing while the recipe still appeared in the Browser tab** — `Scanner:ScanCooldowns` ran two loops: the first found the active transmute via `GetSpellCooldown`, the second wrote the expiry into `gdb.cooldowns[charKey]`. Both branches of the second loop (active-CD store and Ready seed) were gated on `IsSpellKnown(spellId, false)`. On Classic Era that call returns `false` for transmute spell IDs (documented in [docs/bugs.md DATA-004](docs/bugs.md#L51) — same root cause that bit the upstream ProfessionMaster fork), so `transmuteExpiry` was computed correctly but immediately discarded — the recipe still appeared in `gdb.recipes` from the trade-skill scan, but no cooldown row ever materialised. Fixed by deriving "known transmutes" from `gdb.recipes[171]` (alchemy recipes carry `spellId` from the spellbook scan via `BuildSpellNameCache`) and force-including the spell ID that was actually found on cooldown so the active CD shows even on first login before any trade-skill window has been opened. `IsSpellKnown` is kept as a third fallback path for any client where it does work. Location: [Scanner.lua:731-781](Scanner.lua#L731-L781).

- **Reagent `[Bank]` button and Reagent Tracker silently broken because reagent `itemLink`s were nil** — `GetTradeSkillReagentItemLink` and `GetCraftReagentItemLink` return `nil` on Classic Era for reagents that aren't in the local item cache (e.g. items the player has never owned), even though the equivalent tooltip APIs `SetTradeSkillItem(i, r)` / `SetCraftItem(i, r)` work fine. With no link captured, the bank-stock check in [BrowserTab.lua](GUI/BrowserTab.lua) (drilldown panel + shopping-list expansion) and the Reagent Tracker's `BuildReagentList` ([GUI/ReagentTracker.lua:54](GUI/ReagentTracker.lua#L54)) had no item ID to key off and either hid the row entirely (Reagent Tracker) or skipped the `[Bank]` button (drilldown). Fixed by routing every reagent through a hidden `GameTooltip` scraper (`SetTradeSkillItem` / `SetCraftItem` → `GetItem()`) when the link API returns nil, and by also resolving `itemId` directly via `GetItemInfoInstant(name)` as a third-tier fallback for items that happen to be cached. Both fields are now stored on every reagent. Locations: [Scanner.lua:467-491](Scanner.lua#L467-L491) (TradeSkill), [Scanner.lua:631-655](Scanner.lua#L631-L655) (Craft).

- **One peer with the broken reagent-link API would wipe the rich reagent data guild-wide** — `Scanner:MergeRecipesIntoGdb` was overwriting `existing.reagents` wholesale on every receive: `if rd[6] ~= nil then existing.reagents = asTable(rd[6]) end`. If a peer with `GetTradeSkillReagentItemLink` returning nil broadcast their version of a recipe, every receiver's previously-rich reagent table (with itemLink + itemId populated) got replaced by name+count-only entries — silently breaking the bank lookup, reagent tracker, and tooltip popups for everyone. Replaced with a non-destructive `mergeReagents` that matches incoming entries to existing ones by reagent name and preserves `itemLink` / `itemId` whenever the incoming payload lacks them. Location: [Scanner.lua:580-636](Scanner.lua#L580-L636).

- **Reagent Tracker counted guild bank stock as if it were in your bags — "0 in bags, 945 in bank" displayed as `945/30` green** — `RT:Refresh` set `have = bagCount + bankCount`, so a reagent sitting in TOGBankClassic's bank was indistinguishable from one in your character's bags for satisfaction display. Bank stock is still surfaced separately by the `[Bank]` button on each row (only shown when stock > 0), so collapsing it into `have` was double-signalling. Fixed by setting `have = GetPlayerBagCount(item.id)` only. The colour code (green/yellow/red) now reflects what you actually have on your character; the `[Bank]` button signals that more is available via guild-bank request. Location: [GUI/ReagentTracker.lua:146-149](GUI/ReagentTracker.lua#L146-L149).

### Improvements

- **Login-time reagent backfill** — `Scanner:BackfillReagentItemIds` runs on `PLAYER_ENTERING_WORLD` (3 s after PEW so guild + realm context are stable), walks every recipe's reagent table, and resolves `itemId` from `itemLink` (parse) or `GetItemInfoInstant(name)` for any reagent missing both. Best-effort: items still uncached on this character can't be resolved at login, but they get filled in on the next trade-skill scan via the new tooltip scraper. Location: [Scanner.lua:856-898](Scanner.lua#L856-L898).

- **`BrowserTab` reagent rendering tolerant of missing links** — Two new helpers `ResolveReagentItemId(r)` and `ResolveReagentItemLink(r)` lazy-resolve and cache item identity on each reagent table, so renderers transparently use whichever data is available. The detail-panel reagent row falls back to `GameTooltip:SetItemByID(rItemId)` when `itemLink` is nil, and the bank-stock check keys off the resolved `itemId` rather than only `itemLink`. Location: [GUI/BrowserTab.lua:45-79](GUI/BrowserTab.lua#L45-L79).

- **New diagnostic commands** — `/togpm dumprecipe <name>` prints a recipe's stored fields and full reagent table to chat (used to diagnose the missing-itemLink bug above). `/togpm backfill` runs the reagent backfill on demand and prints `checked=N fixed=N missed=N`. Locations: [TOGProfessionMaster.lua:140-141](TOGProfessionMaster.lua#L140-L141), [TOGProfessionMaster.lua:377-419](TOGProfessionMaster.lua#L377-L419).

---

## [v0.1.4] (2026-04-28) - Hand DeltaSync our AceAddon so sync goes through AceCommQueue

### Bug Fixes

- **`aceComm=false` in `/togpm status` — sync was bypassing AceCommQueue throttling** — When the v0.1.1 externalization moved DeltaSync out of `libs/`, the new external library expects the host addon to pass its AceAddon instance into `Initialize({ aceAddon = ... })`. Without it, DeltaSync falls back to raw `C_ChatInfo.SendAddonMessage` instead of routing through `self.aceAddon:SendCommMessage` — so chunked payloads aren't throttled by AceCommQueue-1.0 and can interleave + CRC-fail silently under sync load. The Scanner's `Initialize` call was missing this key entirely. Fixed by passing `aceAddon = addon.lib` (the AceAddon-3.0 instance with AceCommQueue already embedded onto it at [TOGProfessionMaster.lua:46](TOGProfessionMaster.lua#L46)). After this fix, `/togpm status` reports `aceComm=true` and chunked sync should be reliable. Location: [Scanner.lua:87-93](Scanner.lua#L87-L93).

---

## [v0.1.3] (2026-04-28) - GuildCache consolidation, "You (Alt)" disambiguation, sync-log datestamp

### Improvements

- **`LibGuildRoster-1.0` removed; all guild-roster work now goes through `GuildCache-1.0`** — Deleted the embedded `libs/LibGuildRoster-1.0/` folder (~300 lines) and rewired the `OnMemberOnline` crafter-alert callback at [TOGProfessionMaster.lua:179](TOGProfessionMaster.lua#L179) to register on `LibStub("GuildCache-1.0")` instead. GuildCache-1.0 (bundled inside the standalone DeltaSync addon, MINOR ≥ 2) is now a true superset: query API (`IsPlayerOnline`, `IsInGuild`, `GetOnlineGuildMembers`, `NormalizeName`, `GetNormalizedPlayer`) plus CallbackHandler-1.0 transition events (`OnMemberOnline`, `OnMemberOffline`, `OnMemberJoined`, `OnMemberLeft`, `OnRosterReady`, `OnRosterUpdated`) plus real-time `CHAT_MSG_SYSTEM` parsing plus login-race retry. One library, one source of truth. Requires the `DeltaSync` addon at a build that ships GuildCache-1.0 MINOR=2 (already a hard `## Dependencies` since v0.1.1). Locations: all five `*.toc` files, [TOGProfessionMaster.lua](TOGProfessionMaster.lua), [CLAUDE.md](CLAUDE.md), [docs/FEATURES.md](docs/FEATURES.md), [.luarc.json](.luarc.json).

- **Sync log entries now show full date+time, not just time** — `[14:23:11]` was useful for "what just happened" but not for "did this sync happen today or yesterday?" Switched the format string in [GUI/Settings.lua:317](GUI/Settings.lua#L317) from `"%H:%M:%S"` to `"%Y-%m-%d %H:%M:%S"`. The underlying `e.ts` (UNIX epoch seconds set at `time()`) didn't need any data change.

- **"You" disambiguation when several own alts appear in the same list** — In the Cooldowns tab and the Browser tab's recipe-row crafter list, every one of your characters used to render as a single "You" label. With ten alts that meant ten rows all called "You" — useful for color-coding, useless for telling the alts apart. Now the currently-logged-in character still shows `You`, and every other own alt shows `You (AltName)` (short name without realm). The Browser tab also expands the previously-consolidated single "You" entry into one entry per own crafter so each alt that can craft a given recipe is listed individually. Locations: [GUI/CooldownsTab.lua:550-557](GUI/CooldownsTab.lua#L550-L557), [GUI/BrowserTab.lua:127-172](GUI/BrowserTab.lua#L127-L172).

### Bug Fixes

- **`/togpm status` was silently hiding the online-roster section** — `PrintStatus` runs as `function addon:PrintStatus()` (so `self` is `addon`), but the GuildCache handle is stashed on `Scanner.GuildCache`. The diagnostic read `self.GuildCache` (always nil), the `if GuildCache then` block silently skipped, and the user saw two `----` separators with nothing between them — easy to misread as "0 people online." Fixed by reaching across to `Scanner.GuildCache` explicitly. Location: [Scanner.lua:289](Scanner.lua#L289).

- **`/togpm status` showed `AceComm=nil  AceCommQueue=nil` after the v0.1.1 DeltaSync externalization** — The external DeltaSync no longer exposes `useAceComm` / `useAceCommQueue` as direct fields on the lib handle; that data moved into `DS:GetCommStats()`. Replaced the stale field reads with `aceComm/registered/p2p/guildCache` line built from `GetCommStats()` plus an explicit `Scanner.GuildCache ~= nil` check so it's obvious at a glance whether the GuildCache library actually loaded. Location: [Scanner.lua:246-253](Scanner.lua#L246-L253).

---

## [v0.1.2] (2026-04-28) - Type-guard for malformed recipe wire data

### Bug Fixes

- **Browser tab crashed with `attempt to call method 'match' (a nil value)` on opening** — Six call sites in [GUI/BrowserTab.lua](GUI/BrowserTab.lua) (the recipe-row renderer at line 1466, the shopping-list color line at 594, two tooltip `SetHyperlink` paths at 909/940, and the detail-pane title/header-link block at 1199/1203) called `:match` / `:find` on `entry.itemLink` (and `entry.recipeLink`) after a plain truthy check. If any peer's wire payload landed a non-string at position `[5]` or `[7]` of a recipe array, the merged `gdb.recipes[*][*].itemLink` became non-string, the truthy check passed, and the method call crashed the UI. All six sites now gate on `type(entry.itemLink) == "string"`. Belt-and-suspenders type-guard added at the merge site in [Scanner.lua:530](Scanner.lua#L530) so future malformed wire data is coerced to `nil` instead of being stored as-is — `asString(rd[5])` for `itemLink`, `asTable(rd[6])` for `reagents`, `asString(rd[7])` for `recipeLink`.

---

## [v0.1.1] (2026-04-28) - DeltaSync externalized as a standalone addon

### Improvements

- **DeltaSync-1.0 is now an external dependency, not an embedded copy** — Removed the entire `libs/DeltaSync-1.0/` folder (DeltaSync.lua, GuildCache.lua, DeltaOperations.lua, P2PSession.lua) and switched to loading `DeltaSync-1.0` from the standalone `DeltaSync` addon via `LibStub`. This is the same pattern TOGPM already uses for `AceCommQueue-1.0` and `VersionCheck-1.0`. The benefit: when multiple addons consume DeltaSync, LibStub picks one shared copy at the highest MINOR instead of each addon shipping its own fork — exactly the conflict that the v0.1.0 mod 7 convergence was working around. The standalone DeltaSync also includes a newer `GuildCache-1.0` library and an optional `DeltaSyncChannel.lua` transport (TOGPM doesn't use either directly). Locations: all five `*.toc` files, `.pkgmeta`.

- **Dependency declaration updated everywhere it lives** — `## Dependencies` in `TOGProfessionMaster.toc`, `_TBC.toc`, `_Wrath.toc`, `_Cata.toc`, and `_Mists.toc` now lists `DeltaSync` alongside `Ace3`, `AceCommQueue-1.0`, and `VersionCheck-1.0`. `.pkgmeta` `required-dependencies` adds `deltasync` so CurseForge enforces installation. The 4 `libs\DeltaSync-1.0\*.lua` lines are gone from every TOC.

- **Roster helpers re-routed through the new `GuildCache-1.0` LibStub handle** — In the embedded copy, `GetOnlineGuildMembers`, `NormalizeName`, `GetNormalizedPlayer`, `IsInGuild`, and `IsPlayerOnline` were registered onto the `DeltaSync-1.0` LibStub handle itself (the embedded `GuildCache.lua` declared `local MAJOR = "DeltaSync-1.0"`). The external lib promotes GuildCache to its own LibStub library (`MAJOR = "GuildCache-1.0"`) bundled inside the DeltaSync addon. Scanner now resolves `LibStub("GuildCache-1.0", true)` alongside DeltaSync and stashes it as `Scanner.GuildCache`; all call sites in [Scanner.lua](Scanner.lua), [Modules/HashManager.lua](Modules/HashManager.lua), [Tooltip.lua](Tooltip.lua), [GUI/BrowserTab.lua](GUI/BrowserTab.lua), and [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua) were updated to call through the new handle. Wire format and the rest of the DeltaSync public surface (`Initialize`, `InitP2P`, `BroadcastData`, `RequestData`, `SendData`, `SerializeData`, `ComputeHash`, `ComputeStructuredHash`, etc.) are unchanged.

### Breaking Changes

- **Users must install the standalone `DeltaSync` addon** — Without it, TOGPM still loads (the `LibStub("DeltaSync-1.0", true)` call uses the silent variant), but guild sync silently disables and you'll see "DeltaSync-1.0 not found — guild sync disabled" in the debug log. CurseForge will prompt for the dependency automatically once the v0.1.1 release ships with the updated `.pkgmeta`. Manual installs need to grab `DeltaSync` separately.

---

## [v0.1.0] (2026-04-19) - DeltaSync-1.0 mod 7 convergence

### New Features

- **DeltaSync-1.0 bumped to MINOR=7, merging the TOGPM (mod 2) and PersonalShopper (mod 6) forks into a single shared library** — Previously each addon shipped an incompatible fork at the same `DeltaSync-1.0` MAJOR. LibStub always loaded whichever had the higher MINOR (PS mod 6), so TOGPM's P2P calls into a lib that didn't have them — forcing users to disable one addon. Mod 7 is the superset: kept PS mod 6's `NormalizeSender`, host-supplied `self.aceAddon` model, CHANNEL-distribution hooks, snifferFrame, and `DebugStatus`; ported in TOGPM mod 2's OFFER/HANDSHAKE channel types, `OnComm_OFFER`/`OnComm_HANDSHAKE` handlers, `BroadcastItemHashes`/`SendHashOffer`/`SendHandshake`/`InitP2P` public API, and CRC+stop-marker wire format (`SerializeWithChecksum`/`DeserializeWithChecksum`) with a legacy AceSerializer-only fallback so old mod 2 messages still decode. GuildCache hooks (`GetNormalizedPlayer`, `NormalizeName`, `guildRoster` whisper-offline guard) are soft deps guarded by presence checks so PS can run without `GuildCache.lua`. Location: `libs/DeltaSync-1.0/DeltaSync.lua`.

### Improvements

- **DeltaSync no longer embeds Ace libraries into its own `lib` object** — Mod 2 called `AceSerializer:Embed(lib)` and `AceCommQueue:Embed(lib)` at load time, which coupled DeltaSync to Ace's MINOR upgrades and duplicated methods the host addon already had. Mod 7 references `AceSerializer-3.0` via `LibStub(...)` at call-time inside `SerializeWithChecksum`/`DeserializeWithChecksum` (cached in a file-local upvalue), and delegates throttling to the host addon's own `SendCommMessage`. The library is now a pure consumer of Ace via LibStub, never an embedder. Location: `libs/DeltaSync-1.0/DeltaSync.lua`.

- **AceCommQueue throttling moved from the library to the host addon** — Because DeltaSync mod 7 calls `self.aceAddon:SendCommMessage(...)` instead of its own `lib:SendCommMessage`, the wrap target has to be on the host addon. Added `LibStub("AceCommQueue-1.0"):Embed(Ace)` immediately after `NewAddon(...)` so every DeltaSync send from TOGPM is still queued and throttled — preventing CRC corruption from chunk interleaving under sync load. `## Dependencies: AceCommQueue-1.0` was already listed in every TOC, so no new runtime deps. Location: `TOGProfessionMaster.lua`.

### Breaking Changes

- **Wire format changed for existing TOGPM users on mod 2** — The merged mod 7 format is still AceSerializer + CRC + stop-marker (same as mod 2), but `OnComm_*` receive paths now normalize sender names via `NormalizeSender` and route through the new checksum helpers. Mod 2 ↔ mod 7 messages remain decodable via the legacy fallback in `DeserializeWithChecksum`. No action required for existing users.

---

## [v0.0.17] (2026-04-19) - Global `[TOGPM]` Tooltip & Bank Button Fix

### New Features

- **`[TOGPM]` line on every item tooltip** — Hovering any crafted item anywhere in the game (bags, AH, loot, merchant, chat links, comparison tooltips) now appends a single line at the bottom of the tooltip: `[TOGPM] name1, name2, ...` showing every guildmate (and your own alts) who can craft it. Online names are white, offline are grey. A blank row separates it from the item's own info. Works across all supported clients via `TooltipDataProcessor` (MoP Classic+) or `OnTooltipSetItem`/`OnTooltipCleared` (Vanilla → Cata Classic) on GameTooltip, ItemRefTooltip, and the three ShoppingTooltips. Location: `Tooltip.lua`.

### Bug Fixes

- **Tooltip crafter feature silently disabled since day one** — `AceHook-3.0` was never listed in the `NewAddon` mixins, so `Ace.HookScript` was nil and `Tooltip.lua` early-returned on load. The global tooltip hook never ran in the addon's lifetime. Fixed by adding `AceHook-3.0` to the mixin list. Location: `TOGProfessionMaster.lua`.

- **`FindCrafters` traversing the wrong schema** — Walked `gdb.guildData[charKey].professions[].recipes[].craftedItemId`, which only exists in pre-migration SavedVariables. Rewritten to walk `gdb.recipes[profId][recipeId]` where `recipeId` IS the crafted item ID when `not rd.isSpell`, collecting charKeys from `rd.crafters`. Location: `Tooltip.lua`.

- **`[Bank]` button showing on every recipe row** — The recipe-row bank button was iterating `entry.reagents` and lighting up whenever *any* reagent had bank stock, so ~every row got a button that requested the wrong thing (e.g. Barbaric Belt asked for Leather). Replaced with a single check on `entry.id` so the button only appears when the crafted item itself is in bank stock, and the request dialog receives the crafted item's name/link. Suppressed entirely for enchants (no craftable item). Location: `GUI/BrowserTab.lua`.

- **Custom recipe tooltip missing the `[TOGPM]` line** — The BrowserTab reagent-list tooltip path builds its content manually with `ClearLines()` + `AddLine()`, bypassing all tooltip hooks. Added an explicit `addon.Tooltip.AppendCrafters(GameTooltip, entry.id)` call before `Show()` in that path. Location: `GUI/BrowserTab.lua`.

### Improvements

- **`PROF_NAMES` lookup promoted to addon namespace** — `_PROF_NAMES` was file-local in `TOGProfessionMaster.lua`, which prevented `Tooltip.lua` from showing profession names. Exposed as `addon.PROF_NAMES`. Location: `TOGProfessionMaster.lua`.

- **`AppendCrafters` exposed for explicit callers** — BrowserTab's custom tooltip path bypasses hooks, so `AppendCrafters` is now assigned to `addon.Tooltip.AppendCrafters` and callable directly. A per-tooltip `_togpmAppended` flag prevents the post-hook from double-adding when the custom path also fires a subsequent `Show()`. Location: `Tooltip.lua`.

- **Blank-line separator embedded via `|n`** — Two-line approach (`AddLine(" ")` + `AddLine("[TOGPM]...")`) was being reordered by the tooltip's internal build, landing at the top instead of the bottom. Switched to a single `AddLine("|n[TOGPM]...")` so the blank row can't be repositioned. Location: `Tooltip.lua`.

- **`.luarc.json` globals** — Added `TooltipDataProcessor` and `Enum` so the LSP stops warning on the MoP Classic+ branch. Location: `.luarc.json`.

- **Shopping list tooltips use the smart anchor helper** — Three `OnEnter` callbacks in `GUI/ShoppingListTab.lua` were hardcoding `GameTooltip:SetOwner(frame, "ANCHOR_TOPRIGHT")`, which clipped off-screen when the window was near the top or right edge. Swapped for `addon.Tooltip.Owner(frame)` so the tooltip anchors above or below based on which half of the screen the widget is in. Location: `GUI/ShoppingListTab.lua`.

- **Help tooltip rewritten for the current UI** — Browser and Cooldowns help blocks were written before the master-detail layout, the `!` alert toggle, and the global `[TOGPM]` tooltip line existed, and the `[Bank]` description was stale after the v0.0.17 scoping fix. Rewrote both blocks with current section layout (Filters / Shopping list / Recipe area / Detail area / Everywhere else on Browser; Columns / Row actions / Controls on Cooldowns), consolidated sub-bullets into wrap-friendly paragraphs, and added `GameTooltip:SetMinimumWidth(480)` so the tooltip lays out wide and short instead of tall and narrow. Location: `GUI/MainWindow.lua`.

- **Help-icon tooltip anchor kept as `ANCHOR_TOP`** — The help icon lives in a fixed position at the bottom-right of the main window, so centered-above reads better than the helper's TOPLEFT/BOTTOMLEFT picks. Left the raw `SetOwner` in place and added a comment so it isn't "fixed" back to the helper later. Location: `GUI/MainWindow.lua`.

- **Transmute cooldown scan simplified** — The transmute branch of `ScanCooldowns` had a fragile cross-addon dependency on the global `GetCooldownTimestamp`, which is defined by the separate **ProfessionCooldown** addon (not by WoW). When ProfessionCooldown wasn't loaded, we fell back to `GetSpellCooldown`; when it was loaded, we took a different code path that could behave differently. Removed the `GetCooldownTimestamp` branch entirely so the scan uses `GetSpellCooldown` on every client, matching the simpler pattern known to work in production. Location: `Scanner.lua`.

- **`[Bank]` button added to the transmute popup** — When you click a transmute group row in the Cooldowns tab, the popup lists each individual transmute with its reagent and a Mail icon. It was missing the `[Bank]` button that the main cooldown rows have. Added it (visible only when TOGBankClassic has stock of that specific reagent), wired to the same `addon.Bank.ShowRequestDialog` as the main rows. Widened the popup from 340 → 400 px to fit. Location: `GUI/CooldownsTab.lua`.

---

## [v0.0.16] (2026-04-19) - Enchanting Tooltip Fixes & Crafter Alerts

### New Features

- **Crafter online alerts** — When a guild member who can craft an item on your shopping list comes online, a chat message is printed and (unless suppressed) a sound plays and the screen flashes gold. Each shopping list row has a `!` toggle button (gray = off, gold = on) to arm alerts per recipe. Alt-group awareness: if the online player is an alt of a crafter, the alert still fires with an "(alt of X)" note. Three settings in ESC → Options → TOG Profession Master → Crafter Alerts: master on/off toggle, suppress sound & flash, suppress on login (default on to avoid the login burst). Location: `TOGProfessionMaster.lua`, `GUI/BrowserTab.lua`, `GUI/Settings.lua`.

### Bug Fixes

- **Enchanting tooltip showing wrong item** — On Vanilla Classic Era, enchanting recipes scanned via the Craft frame stored only name and icon (no `isSpell`, no reagents). The tooltip fallback chain would reach the last `else` branch and call `SetHyperlink("item:" .. spellId)`, resolving the enchant spell ID to a random item like "Sentinel's Leather Pants". Fixed by capturing reagents from the Craft frame (`GetCraftNumReagents`/`GetCraftReagentInfo`/`GetCraftReagentItemLink`) and setting `isSpell = true` so the data format matches the TradeSkill path. Location: `Scanner.lua`.

- **Enchanting tooltip not showing reagent list** — The Professions tab tooltip priority checked `recipeLink` before reagents, but enchanting stores an `enchant:SPELLID` link there (not a displayable item link). Added `|Hitem:` guards on `recipeLink` and `itemLink` usage, and moved the `spellId` fallback to after the reagent branch so enchanting now shows the same reagent-list tooltip as leatherworking. Location: `GUI/BrowserTab.lua`.

- **Shopping list alert toggle always staying enabled** — The `!` button on shopping list rows used `cur and nil or true` to toggle, which always evaluates to `true` in Lua because `nil` is falsy. Replaced with an explicit if/else. Location: `GUI/BrowserTab.lua`.

### Improvements

- **VersionCheck-1.0 version field wired correctly** — `Ace.Version` was nil, so VersionCheck-1.0 fell back to `GetAddOnMetadata` to read the version string. Fixed by setting `self.Version = addon.Version` on the Ace object in `OnInitialize` before calling `VC:Enable(self)`, so the library reads the version directly without the fallback. Location: `TOGProfessionMaster.lua`.

---

## [v0.0.15] (2026-04-19) - Reagent Tracker & Professions Tab Master-Detail Layout

### New Features

- **Reagent Tracker window** — Standalone floating window (no backdrop or border) opened by right-clicking the minimap button or `/togpm reagents`. Consolidates every reagent across all shopping list entries (e.g. 1 Runecloth from one recipe + 10 from another = 11 required). Each row shows the item icon, name coloured by item rarity, a have/need count (green = satisfied, yellow = partial, red = none), and a `[Bank]` button when a TOGBankClassic banker alt has stock. "Have" is live player bags + all banker alt stock via `TOGBankClassic_Guild`. Window position is saved per character. Refreshes automatically on `BAG_UPDATE` and whenever the shopping list changes. Location: `GUI/ReagentTracker.lua`.

- **Master-detail split layout in Professions tab** — The floating recipe popup is replaced by a persistent right-side detail panel (268 px wide) inline in the Professions tab. Clicking any recipe row populates the panel without opening a separate window. The panel shows: recipe icon + name (hover for item tooltip, shift-click to insert link), right-justified shopping list qty controls (`−` qty `+` `×`), per-reagent `[Bank]` buttons, and full crafter list with right-click-to-whisper. Location: `GUI/BrowserTab.lua`.

- **`[Bank]` button in recipe list rows** — Each left-column recipe row now shows a `[Bank]` button when any reagent is in TOGBankClassic stock. Recipe name column widened from 150 to 160 px; crafter column narrowed to RIGHT−56 to accommodate. Location: `GUI/BrowserTab.lua` `BuildPool()`, `UpdateVirtualRows()`.

### Bug Fixes

- **Bank buttons missing for ~5 minutes after login** — `TOGBankClassic_Guild.Info` is `nil` until `GUILD_RANKS_UPDATE` fires. Fixed by registering a one-shot event watcher in `FillList()` that triggers a deferred refresh of the recipe list, detail panel, and shopping list section once bank data is ready. Location: `GUI/BrowserTab.lua`.

- **ESC proxy cleanup** — Removed stale popup check from the ESC proxy `OnHide` handler; the recipe popup no longer exists as a floating frame. Location: `GUI/MainWindow.lua`.

---

## [v0.0.14] (2026-04-19) - Restore BrowserTab, CooldownsTab, MainWindow & Compat Work

### Bug Fixes

- **Restored Apr 18 evening work** — A version-sync script bug was self-copying the wrong directory, silently discarding an evening's worth of changes. Recovered and recommitted: BrowserTab virtual scroll pool, CooldownsTab group/transmute popup, MainWindow ESC proxy wiring, and Compat API shims. Location: `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`, `GUI/MainWindow.lua`, `Compat.lua`.

- **Version-sync script self-copy bug** — The `wow-version-replication.ps1` sync script was incorrectly including itself in the source glob, causing it to overwrite the destination copy with stale content. Fixed source path exclusion. Location: `.vscode/tasks.json`.

---

## [v0.0.13] (2026-04-18) - P2P Sync, Transmute Scan & Version Check Command

### Bug Fixes

- **P2P sync reliability** — Multiple DeltaSync handshake and delta-apply edge cases fixed: hash mismatches on first contact, offer/response sequencing under concurrent peers, and stale session state after a guild member relogged. Location: `libs/DeltaSync-1.0/`.

- **Transmute cooldown scan** — Transmute spell IDs were scanned against the wrong API path on some client builds, causing all transmutes to report as "Ready" immediately after use. Scanner now validates expiry against `GetSpellCooldown` with a 30-day sanity cap. Location: `Scanner.lua`.

- **`/togpm version` command** — Added `version` subcommand; prints the running addon version and broadcasts a version check request to online guildmates. Location: `TOGProfessionMaster.lua`.

---

## [v0.0.12] (2026-04-17) - BAG_UPDATE Storm, Guild Key Migration & Online Display Fixes

### Bug Fixes

- **`BAG_UPDATE_COOLDOWN` broadcast storm** — Every bag slot change was triggering a full guild broadcast. Added a 30-second coalescing debounce so rapid inventory changes collapse into a single send. Location: `Scanner.lua`.

- **Guild key migration** — Characters whose data was stored under the old `Faction-Realm-GuildName` key were invisible after the key format change in v0.0.11. Added a one-time migration pass on `OnEnable` that moves existing entries to the new `Faction-GuildName` key. Location: `Scanner.lua`.

- **Alt online display** — When a crafter's main was offline but an alt on the same account was online, the alt's name was not being shown in the crafter column. Fixed display logic to show `AltName (CrafterName)` format when the online alt is detected. Location: `GUI/BrowserTab.lua`.

---

## [v0.0.11] (2026-04-17) - Debug Timestamps & Guild Key Format Refactor

### Improvements

- **HH:MM:SS timestamps on debug output** — All `addon:DebugPrint()` calls now prefix output with the current wall-clock time, making it easier to correlate debug lines with in-game events. Location: `TOGProfessionMaster.lua`.

### Internal

- **Guild key format changed** — Guild DB key changed from `Faction-Realm-GuildName` to `Faction-GuildName`. Realm is intentionally omitted so connected-realm clusters share a single key regardless of which realm a member appears on. Location: `Scanner.lua`, `TOGProfessionMaster.lua`.

---

## [v0.0.10] (2026-04-17) - Mining Profession & Reagent Wire Payload

### New Features

- **Mining added to profession browser** — Mining (profession ID 186) added to the profession filter dropdown and static profession list. Location: `GUI/BrowserTab.lua`.

### Bug Fixes

- **Reagent data missing for guild peers** — `itemLink` and `reagents` arrays were not included in the DeltaSync wire payload, so recipients could not show item tooltips or reagent details for recipes learned by guildmates. Both fields now serialized and merged on receipt. Location: `Scanner.lua`.

---

## [v0.0.9] (2026-04-17) - Alt Detection & Account Character Tracking

### New Features

- **Alt detection** — Characters on the same account are now detected and linked. Own characters are shown as `You` (brand-coloured) in the crafter list and are sorted first. When a crafter's main is offline but a known alt is online, the crafter column displays `OnlineAlt (CrafterName)`. Location: `GUI/BrowserTab.lua`, `Scanner.lua`.

### Bug Fixes

- **`accountChars` registration timing** — Account character list was being registered in `OnInitialize`, before `PLAYER_ENTERING_WORLD` had fired and guild data was available. Moved to `PLAYER_ENTERING_WORLD` to ensure the roster is populated before alt matching runs. Location: `TOGProfessionMaster.lua`.

---

## [v0.0.8] (2026-04-17) - Connected-Realm Sender Normalization & Broadcast Storm Fix

### Bug Fixes

- **Connected-realm sender names not normalized** — Guild members appearing on connected realms were stored under their raw `Name-ConnectedRealm` key instead of the canonical normalized realm, creating duplicate entries and breaking online-status detection. All incoming sync messages now pass through `GetNormalizedRealmName()` before storage. Location: `Scanner.lua`.

- **Sync broadcast storm from cross-realm cluster members** — Receiving a sync payload from a cross-realm cluster member was triggering a re-broadcast of the full dataset back to the guild, causing exponential message traffic. Fixed by gating re-broadcast on a "data changed" flag rather than "data received". Location: `Scanner.lua`.

---

## [v0.0.7] (2026-04-17) - AceComm Sync Fixes

### Bug Fixes

- **AceComm handler signature mismatch** — The registered `OnCommReceived` handler had an incorrect parameter order (`prefix, message, channel, sender` vs the actual AceComm dispatch of `prefix, message, distribution, sender`), silently discarding all incoming sync messages. Corrected signature. Location: `Scanner.lua`.

- **AceComm handler parameter shift** — A secondary handler registration was using a closure that shifted all parameters by one, causing the sender field to be read as the channel and vice versa. Fixed parameter binding. Location: `Scanner.lua`.

- **Broken sort indicator on Cooldowns tab headers** — Column header sort arrow textures were referencing a path that doesn't exist on Classic Era, leaving a broken texture visible at all times. Removed the sort indicator until a valid asset is identified. Location: `GUI/CooldownsTab.lua`.

---

## [v0.0.6] (2026-04-17) - HashManager & DeltaSync Stability

### New Features

- **HashManager hierarchical hash system** — New `Modules/HashManager.lua` implements a Merkle-style hash cache: per-member cooldown leaf hashes, per-profession recipe leaf hashes, and guild-level roll-ups (`guild:cooldowns`, `guild:recipes`). DeltaSync uses these hashes to skip transfers when both peers already agree. Location: `Modules/HashManager.lua`, `Scanner.lua`.

### Bug Fixes

- **DeltaSync `Serialize` nil on early send** — AceSerializer-3.0 was being embedded inside `Initialize()`, so any send that fired before `Initialize` completed caused `attempt to call Serialize (nil)`. Moved library embedding to load time. Location: `libs/DeltaSync-1.0/DeltaSync.lua`.

- **`BroadcastItemHashes` nil guard** — A startup timer could fire before the P2P session was fully constructed, causing a nil-access crash in `BroadcastItemHashes`. Added existence guard. Location: `Scanner.lua`.

---

## [v0.0.5] (2026-04-17) - Cooldowns Tab UI Polish

### Improvements

- **Cooldowns row layout** — Fixed column width calculations so character name, cooldown name, reagent, and time-left columns no longer overlap at narrow window widths. Sort arrow positioning corrected. Location: `GUI/CooldownsTab.lua`.

- **Header tooltips and brand color** — Cooldowns tab column headers now show descriptive tooltips on hover and use the addon brand color (`FF8000`) for header text, matching the Professions tab style. Location: `GUI/CooldownsTab.lua`.

- **Header bleed fix** — Column header row was rendering 2 px outside the tab content frame at the bottom, causing a thin line of header background to bleed into the first data row. Fixed via explicit height clamp. Location: `GUI/CooldownsTab.lua`.

---

## [v0.0.4] (2026-04-17) - Package Metadata & TOC Fixes

### Bug Fixes

- **Incorrect CurseForge `.pkgmeta` slugs** — External library slugs in `.pkgmeta` were pointing to wrong CurseForge project paths, preventing the packager from embedding Ace3 and companion libraries correctly on release builds. Location: `.pkgmeta`.

- **TOC interface version mismatches** — `TOGProfessionMaster_TBC.toc`, `_Wrath.toc`, `_Cata.toc`, and `_Mists.toc` had incorrect `## Interface:` values that caused the client to flag the addon as out-of-date on those versions. Corrected to the appropriate build numbers. Location: all `.toc` files.

### Internal

- Added `.gitignore` entries for legacy and copyright-encumbered source files that must not be committed to the public repository.

---

## [v0.0.3] (2026-04-16) - Recipe Browser Tooltip Overhaul

### New Features

- **Rich recipe tooltips** — Hovering a recipe row in the Professions tab now shows a fully custom tooltip: profession name + recipe name header (WoW yellow), reagent list with quantities, and full item data (quality, stats, binding, flavor text) scraped from a hidden `GameTooltipTemplate` frame without triggering other addon hooks. Location: `GUI/BrowserTab.lua`, `Tooltip.lua`.

- **Crafter line in tooltips** — Tooltip footer lists all known crafters with the current player shown as gold `You` sorted first. Online crafters are shown in white; offline in grey. Location: `GUI/BrowserTab.lua`.

- **Centralized UI color palette** — `addon.BrandColor` (Legendary orange `FF8000`), `ColorYou`, `ColorCrafter`, `ColorOnline`, `ColorOffline` defined once on the addon table and used throughout all GUI files and Tooltip.lua. Location: `TOGProfessionMaster.lua`.

- **Smart tooltip anchoring** — Tooltip anchors below the hovered row when in the top half of the screen (`ANCHOR_BOTTOMLEFT`) and above when in the bottom half (`ANCHOR_TOPLEFT`), preventing clipping. `addon.Tooltip.Owner()` helper added to `Compat.lua` for consistent anchoring across all modules. Location: `Compat.lua`.

### Improvements

- **`L["You"]` locale key** — Added to `Locale/enUS.lua` for consistent localization of the self-reference label. Location: `Locale/enUS.lua`.

---

## [v0.0.2] (2026-04-16) - Complete Clean-Room v1.0 Build

### New Features

- **Profession browser** — `GUI/BrowserTab.lua`: virtual-scroll recipe list (35-row pool), profession dropdown filter, text search, Guild/Mine view toggle, shopping list integration. Location: `GUI/BrowserTab.lua`.

- **Cooldowns tracker** — `GUI/CooldownsTab.lua`: displays all guild members' tracked profession cooldowns with character name, cooldown name, reagent, and time remaining. Right-click any row to whisper. Location: `GUI/CooldownsTab.lua`.

- **Shopping list** — Per-character shopping list with quantity controls, reagent expansion, and missing-reagents tracking. Location: `GUI/ShoppingListTab.lua`, `Modules/ReagentWatch.lua`.

- **P2P guild sync via DeltaSync-1.0** — Custom embedded library broadcasting profession recipes, skills, cooldowns, specializations, and alt-group data peer-to-peer over guild addon channels. Full payload on first contact; hash-based delta sync thereafter. Location: `libs/DeltaSync-1.0/`, `Scanner.lua`.

- **Scanner** — Scans `TRADE_SKILL_SHOW`, `BAG_UPDATE_COOLDOWN`, and related events to capture recipe and cooldown data, merges into the guild DB, and fires `GUILD_DATA_UPDATED` callbacks. Location: `Scanner.lua`.

- **AceDB storage** — `TOGPM_GuildDB` (account-wide, guild-scoped): recipes, skills, cooldowns, specializations, altGroups, hashes. `TOGPM_Settings` (per-character): shopping list, reagent watch, alerts, frame positions. Location: `TOGProfessionMaster.lua`.

- **Minimap button** — LibDataBroker + LibDBIcon launcher. Left-click opens profession browser; right-click opens reagents; Shift+Left-click opens settings. Location: `GUI/MinimapButton.lua`.

- **Settings panel** — AceConfig-3.0 options registered under ESC → Options → Addons → TOG Profession Master: minimap button toggle, persist profession filter, debug output, force re-sync, purge data, sync log viewer. Location: `GUI/Settings.lua`.

- **Sync log** — Scrollable log of last 200 sync events (send/recv/request/version) with timestamps and byte counts. Location: `Modules/SyncLog.lua`, `GUI/Settings.lua`.

- **Multi-version TOC** — Supports Vanilla (Classic Era / Anniversary), TBC, Wrath, Cata, and Mists via separate `.toc` files. Version flags (`addon.isVanilla`, `addon.isTBC`, etc.) set at load time from `GetBuildInfo()`. Location: `Compat.lua`, all `.toc` files.

- **Slash commands** — `/togpm`, `/togpm sync`, `/togpm debug`, `/togpm purge`, `/togpm version`, `/togpm minimap`. Location: `TOGProfessionMaster.lua`.

---

## [v0.0.1] (2026-04-16) - Initial Scaffold

### Internal

- Repository initialized. Clean-room project structure established: `libs/`, `Data/`, `GUI/`, `Modules/`, `Locale/`, `docs/`. Core addon frame (`TOGProfessionMaster.lua`), AceAddon skeleton, and placeholder TOC created. No functional game code.
