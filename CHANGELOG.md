# TOG Profession Master Changelog

## [v0.10.8] (2026-06-28) - Fix: commtest missing from per-flavor TOCs

Follow-up to v0.10.7. The new diagnostic shipped in only one of the addon's five TOC files, so it never loaded on the very clients it was built for. This release wires it into all of them.

### Bug Fixes

- **`/togpm commtest` now loads on TBC / Wrath / Cata / MoP clients.** v0.10.7 added `Modules/CommTest.lua` to only the base `TOGProfessionMaster.toc`. WoW loads the *flavor-specific* TOC when one exists, so on TBC/Wrath/Cata/Mists clients — including privately-hosted Cataclysm servers like **Whitemane "Maelstrom"** — the file was never in the load list, `RunCommTest` stayed undefined, and `/togpm commtest` silently fell through to the help menu (the command's help line still showed because that lives in the always-loaded main file, which is what made it look present). Added the line to all four flavor TOCs (`_TBC`, `_Wrath`, `_Cata`, `_Mists`) so the diagnostic is available on every supported version. Location: `TOGProfessionMaster_TBC.toc`, `TOGProfessionMaster_Wrath.toc`, `TOGProfessionMaster_Cata.toc`, `TOGProfessionMaster_Mists.toc`.

### Notes

- **Whitemane runs a modern Classic-engine client, not the original 4.3.4 client.** Diagnostics surfaced that its addon-message API is `C_ChatInfo.SendAddonMessage` (the bare global `SendAddonMessage` is `nil`), and `C_ChatInfo.SendAddonMessage` returns a `SendAddonMessageResult` code. The `commtest` probe already handles this via its `C_ChatInfo` shim; this corrects the v0.10.7 note that assumed the original 4.3.4 client.

---

## [v0.10.7] (2026-06-27) - Private-server addon-comm diagnostics

Groundwork for running TOGPM on privately-hosted **Cataclysm 4.3.4 (build 15595)** servers such as **Whitemane "Maelstrom"**, where some emulation cores leave the Cataclysm per-channel addon opcodes (`CMSG_MESSAGECHAT_ADDON_GUILD`, …) unhandled and silently drop guild addon traffic — which makes the sync stack look dead even though the addon loads fine. This release adds a diagnostic to pinpoint exactly which addon-message channels a given server relays. **No change to existing behavior** — it's a new, opt-in command; nothing in the live sync path was touched.

### New Features

- **`/togpm commtest [name]` — addon-channel diagnostic probe.** Fires a tagged addon message on every distribution (GUILD, WHISPER→self, a temporary CHANNEL, and PARTY/RAID when grouped), listens briefly for which ones echo back, then prints a copy-pasteable verdict including the client build number. The **GUILD self-echo is the decisive test** and works solo — on a healthy core you receive your own guild addon message; if the server drops guild addon traffic you get nothing. It probes **both** the raw `SendAddonMessage` path and your actual AceComm + AceCommQueue send path, so a server-side drop is distinguishable from a wrapper/chunking issue. Pass a player name to add a real two-player WHISPER probe. Run it on your home realm (control) and on the private server (test); the diff identifies the broken channel and which fallback (WHISPER/CHANNEL) is viable. Cross-version safe — uses `C_ChatInfo` where present, bare globals on 4.3.4, registers prefixes only where that API exists, and deliberately uses an `OnUpdate` timer instead of `C_Timer` (which the original 4.3.4 client lacks). Location: `Modules/CommTest.lua`.

---

## [v0.10.6] (2026-06-12) - Cross-guild profession sharing & crafting hands-off

First stable release of cross-guild profession sharing (matured across the v0.10.x beta line) plus new crafting-window controls. **Fully backward-compatible** — single-guild use is unchanged, and cross-guild sharing stays completely dormant until you configure an allied guild. Cross-guild requires DeltaSync **v3.1.0+** and GuildRoster **v6+** (both install/update automatically).

### New Features

- **Cross-guild profession sharing.** Share recipe and crafter data between two socially-linked guilds that can't reach each other over the normal guild addon channel. An **officer or the guild leader** sets the allied guild under **Settings → Cross-Guild** (the list is guild-wide and members see it read-only); once **both** guilds list each other (it's bilateral — a one-sided config does nothing, and a guild you don't list can't pull or inject anything), their crafters become visible to each other. The allied-guild list propagates across your guild automatically, allied rosters are shared so **every** member sees the crafters (not just whoever pulled them), and a live **Diagnostics** panel plus `/togpm xgdiag` show exactly what's synced. With no allied guild configured, the addon does nothing cross-guild — purely local. Location: `Scanner.lua`, `TOGProfessionMaster.lua`, `GUI/Settings.lua`.
- **Crafting hands-off mode** — *Settings → Crafting, on by default.* TOGPM no longer opens or forces a crafting window when you open a profession; Blizzard's window (or another addon such as TSM / Skillet) owns it, so no second window appears beside it. The TOGPM toggle button still rides on the Blizzard window when it's shown, and the Crafting tab stays available from the main window. **If you previously enabled "Open the TOGPM Crafting tab automatically," untick this to keep that behavior.** Requires `/reload`. Location: `Modules/Crafting/CraftingEngine.lua`.
- **Hide the Crafting tab** — *Settings → Crafting.* Removes the Crafting tab from the main window entirely, for those who craft with another addon. Requires `/reload`. Location: `GUI/MainWindow.lua`.

### Bug Fixes

- **Browser performance overhaul — instant tab open and instant search.** The recipe list (the expensive part: DB lookups, the per-crafter visibility gate, item tooltip text) is now built **once** and cached, and pre-warmed in the background after login — sliced across frames so it's invisible — so opening the Professions tab and switching professions are instant instead of taking a second or more. Searching just filters the cache (no rebuild, no per-keystroke freeze). This removes the multi-second tab-load and search stutter that had grown as cross-guild sharing enlarged the crafter sets. Location: `GUI/BrowserTab.lua`, `TOGProfessionMaster.lua`.

### Improvements

- **Settings window is tabbed** (General / Cross-Guild) and remembers its position, size, and selected tab across `/reload`.
- **Roster engine** runs on the standalone LibGuildRoster-1.0 (GuildRoster addon), an auto-installed dependency — the foundation for cross-guild support.

---

## [v0.10.5-beta] (2026-06-09) - Roster propagation & Browser search fix (beta)

> **Beta build.** Completes the cross-guild "anyone is a transfer point" model. Backward-compatible; single-guild operation is unchanged. Requires DeltaSync **v3.1.0+** and GuildRoster **v6+**.

### New Features

- **Sister-roster propagation (Part B).** The visibility gate keeps an allied crafter only if their character is in a sister roster you hold — so a member who configured an allied guild but never *pulled* its roster would purge every relayed crafter. Now a member who holds a sister roster broadcasts it on the guild channel and everyone applies it, so the whole guild sees allied crafters, not just the puller. A "recently-seen by hash" suppression keeps it to ~one broadcaster per interval (duty rotates if that member logs off), fresh pulls propagate within ~10s, and receipt is gated by the allied-guild list (an unlisted guild's roster is never accepted). This is the piece that makes federated members churn-free without each pulling. Location: `TOGProfessionMaster.lua`, `Scanner.lua`.

### Bug Fixes

- **Browser (recipe) search no longer freezes on each keystroke.** Two causes: the search box rebuilt the whole list synchronously on every character (no debounce — the fix that was already in Missing Recipes had never been applied here), and the per-recipe crafter list was built *before* the search filter ran, so every keystroke walked every recipe's crafter set — which grew heavier as cross-guild sharing added crafters. The search now debounces (~200ms) and applies the cheap client-version + name/effect filters before the expensive crafter-list build, so excluded recipes are skipped. Location: `GUI/BrowserTab.lua`.

---

## [v0.10.4-beta] (2026-06-09) - Cross-guild bilateral federation gate (beta)

> **Beta build.** Security model for cross-guild sharing. Backward-compatible; single-guild operation is unchanged. Requires DeltaSync **v3.1.0+** and GuildRoster **v6+**.

### New Features

- **Bilateral federation — both guilds must list each other.** Cross-guild data now only flows when **both** sides have configured each other as allied guilds. A one-sided config does nothing; a stranger, an accidental config, or a malicious puller from a guild you don't list gets nothing. Enforced by gating every direction:
  - **Serve gate:** we hand over our data only if we list the requester's guild **and** the request proves they list us (it carries their guild key + sister-guild set). Plus an anti-spoof check — once we hold the requester's guild roster, the requester must actually be a member of it.
  - **Accept gate:** we ingest cross-guild data only from a guild on our list.
  - **Merge gate:** every crafter is kept only if its guild tag is our home, our own alts, or a *listed* sister — so data for an unlisted guild is dropped even when it arrives relayed inside a home-guild broadcast, and is never re-relayed.
  - **Roster gate:** we persist/re-feed a sister roster only for a guild we list; a de-configured guild can't be resurrected on login.
  - **De-configure cleanup:** removing a guild from the list (or receiving a federated removal) tears down its roster and stops its data from displaying.
- **No allied guilds configured → purely local operation.** With an empty list the permitted-tag set collapses to home + your own alts, so the addon does nothing cross-guild at all. Location: `Scanner.lua`, `TOGProfessionMaster.lua`.

---

## [v0.10.3-beta] (2026-06-09) - Cross-guild config propagation & churn fix (beta)

> **Beta build.** Continues the cross-guild work. Backward-compatible and dormant until an allied guild is configured. Requires DeltaSync **v3.1.0+** and GuildRoster **v6+**. For the relay/anti-churn behavior, **all participating beta players need this build** — a peer on an older build re-broadcasts relayed crafters with the guild tag stripped.

### New Features

- **Allied-guild config now propagates across your guild.** The allied-guild list you set under Settings → Cross-Guild is broadcast to the rest of your guild (on change, every ~12 minutes, and via a new **Sync now** button), so every member participates — essential once editing becomes officer-only. Conflict resolution is last-writer-wins by the timestamp captured when the list was set; members re-broadcast what they hold without clobbering a newer edit. A member holding no config never broadcasts. Location: `TOGProfessionMaster.lua`, `GUI/Settings.lua`.

### Bug Fixes

- **Relayed cross-guild crafters no longer churn under mixed addon versions.** Because guild sync is gossip, a single guildmate on an older build (no per-crafter tags) re-broadcasts relayed sister crafters with the tag stripped; the receiver then re-stamped them as the home guild, the visibility gate purged them (not in the home roster), the relay re-added them, and the cycle repeated — counts visibly oscillating with no membership change. The merge now treats an explicit shipped tag as authoritative and **never lets a tagless (older-build) broadcast overwrite an attribution it already holds**, so a known cross-guild crafter stops flipping. The roster gate still decides visibility, so genuine leavers are still purged. Location: `Scanner.lua` (`MergeCraftersIntoGdb`).

### Improvements

- **Diagnostics: orphan breakdown.** The Cross-Guild diagnostics now show, per allied guild, how many crafters match the roster vs. are orphaned (with a few example keys), making it easy to tell roster-matching issues from genuine non-members. Location: `GUI/Settings.lua`.

---

## [v0.10.2-beta] (2026-06-09) - Cross-guild relay attribution & diagnostics (beta)

> **Beta build.** Continues the cross-guild work from v0.10.1-beta. Backward-compatible and dormant until an allied guild is configured. Requires DeltaSync **v3.1.0+** and GuildRoster **v6+** (both install/update automatically). For cross-guild relay to work, **all** participating players need this build.

### New Features

- **Cross-guild diagnostics panel.** A live, read-only status section on **Settings → Cross-Guild** showing dependency status (DeltaSync/RosterSync, LibGuildRoster/multi-roster), known rosters (home + each sister) with member counts, configured allied guilds, crafter counts per guild, and persisted allied rosters with feed timestamps. Plus a "Pull from player" field to trigger a pull without the slash command. Location: `GUI/Settings.lua`.
- **`/togpm xgdiag` command.** Dumps the same cross-guild diagnostics to chat as plain lines for easy copy-paste when troubleshooting. Location: `GUI/Settings.lua`, `TOGProfessionMaster.lua`.

### Bug Fixes

- **Cross-guild attribution now survives relays.** The crafters sync leaf previously shipped bare character keys with no guild tag, on the assumption that every crafter in a payload belonged to the receiver's guild. In a confederation that assumption breaks: when a member who holds sister-guild data rebroadcasts it into their home guild, those sister crafters were re-stamped as the home guild and then hidden/purged by the visibility gate (not in the home roster). The leaf now ships each crafter's **origin guild tag** (already stored locally), so a relaying "bridge" member can propagate allied-guild crafters into their home guild with attribution intact. The leaf **hash is unchanged** (it already normalized values before hashing), so old and new clients stay in sync — but both ends of a relay must run this build for tags to be preserved. Location: `Scanner.lua` (`BuildLeafPayload`, `MergeCraftersIntoGdb`).

---

## [v0.10.1-beta] (2026-06-09) - Cross-guild profession sharing (beta)

> **Beta build.** This is the first testable cut of cross-guild sharing. It is fully backward-compatible — single-guild users are unaffected and the feature stays dormant until an allied guild is configured — but the cross-guild round-trip has not yet been validated with live players. Please report issues. Requires DeltaSync **v3.1.0+** and GuildRoster **v6+** (both install/update automatically).

### New Features

- **Cross-guild profession sharing (beta).** TOGPM can now share recipe/crafter data between two socially-linked guilds that can't reach each other over the normal guild addon channel. Configure an allied guild under **Settings → Cross-Guild**, and your crafters become discoverable to them (and theirs to you). Built on directed peer-to-peer whispers — no extra chat channel required. Location: `GUI/Settings.lua`, `Scanner.lua`, `TOGProfessionMaster.lua`.
- **Sister-guild roster tracking.** Allied-guild rosters are pulled, persisted across `/reload`, and kept live via LibGuildRoster-1.0's multi-roster store, so allied crafters survive a session restart and stay correctly attributed to their own guild. Location: `Scanner.lua` (`PersistSisterRoster`, `RefeedSisterRosters`, `OnSisterRosterUpdated`).
- **`/togpm pullroster <player>` command.** Manually pull an online allied-guild member's roster **and** crafter data on demand — the testing/bootstrap path before automatic discovery lands. Location: `TOGProfessionMaster.lua`.

### Improvements

- **Settings window is now tabbed.** Options are organized into General and Cross-Guild tabs (with room for officer/GM-only settings as features grow). Location: `GUI/Settings.lua`.
- **Each guild stays authoritative for its own membership.** Cross-guild data exchange shares only a guild's *own* crafters and is opt-in (nothing is served until you configure an allied guild), so attribution can never bleed between guilds in a multi-guild confederation. Location: `Scanner.lua` (`BuildFullGuildPayload`).

### Bug Fixes

- **Settings window position, size, and selected tab now persist across `/reload`.** The standalone options window kept its geometry in a runtime-only table; it's now backed by SavedVariables (`.char.frames.settings`), matching the main window. Location: `GUI/Settings.lua`.

### Known Limitations (beta)

- Allied-guild crafters currently display as **offline** — live presence arrives with automatic `/who` discovery in a later beta.
- Cooldown sharing is **not** yet cross-guild (crafter data only this build).
- Allied data must be bootstrapped with `/togpm pullroster <name>`; automatic discovery is not in this build.

---

## [v0.10.0] (2026-06-05) - Roster engine migration (LibGuildRoster-1.0)

### Improvements

- **Roster engine migrated to LibGuildRoster-1.0.** Guild-roster data (membership, online state, and the join/leave/online callbacks) now comes from the standalone LibGuildRoster-1.0 library (the GuildRoster addon) instead of the retired GuildCache-1.0. This is the foundation for upcoming cross-guild support. GuildRoster is now a dependency and installs automatically. Location: `Scanner.lua`, `TOGProfessionMaster.lua`, `Tooltip.lua`, `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`.

### Bug Fixes

- **Pending-purge sweep now re-validates before deleting.** The timed sweep that removes departed members' data re-checks each flagged character against the live roster, deletes only confirmed non-members, and bails entirely if the roster isn't ready — closing any path where a legitimate guildmate's crafter data could be removed by a stale or early-login purge flag. Location: `TOGProfessionMaster.lua` (`RunPendingPurge`).
- **Visibility gate hardened against an unbuilt roster.** A tag-matching crafter is shown (not flagged for purge) while the roster library is absent or still loading, restoring the pre-migration leniency and preventing early-login false-flags. Location: `TOGProfessionMaster.lua` (`IsVisibleCrafter`).

---

## [v0.9.1] (2026-06-02) - Profit Planner UX, addon-wide sortable headers, search icons & persistence fixes

### New Features

- **Profit Planner profession filter now supports multi-select.** The Professions dropdown in the Profit tab is a native AceGUI multi-select dropdown (matching the Crafters/Sources dropdowns) that stays open while you tick multiple professions, with `Select All` / `Clear All` rows at the top. It defaults to all professions except Enchanting on first load (locale-safe `addon.PROF_NAMES[333]` lookup); once you clear the selection it stays cleared. Location: `GUI/AHProfitTab.lua`.

- **Missing Recipes columns are now sortable.** Click the Recipe, Skill, or Sources headers to sort the list (click again to reverse); it defaults to skill ascending. Location: `GUI/MissingRecipesTab.lua`.

- **Tab selection now persists across /reload and addon reopen.** The main window remembers which tab you were viewing (Browser, Cooldowns, Missing Recipes, Crafting, Profit Planner, Shopping List) in `lastMainTab` and restores it when you reopen the addon or reload the UI. Profit Planner's subtab (Live AH Profit vs Historical Profit) also persists independently in `profitSubTab`. Location: `GUI/MainWindow.lua`, `GUI/AHProfitTab.lua`, `TOGProfessionMaster.lua`.

### Improvements

- **Profit Planner money columns sized to fit the window.** Craft Cost, Sell Price, and Profit columns widened from 72px to 112px for readability while still fitting inside the minimized window (the right edge and scrollbar stay on-screen). Location: `GUI/AHProfitTab.lua`.

- **Sortable column headers now share one consistent style across the addon.** On the Profit Planner, Cooldowns, Crafting, and Missing Recipes tabs, headers are centered over their columns with the up/down sort arrow placed beside the header text (measured via `GetStringWidth`) rather than at the column's far edge, plus a brand-colored glow that fades in on hover to signal "click to sort". Built as shared helpers (`ConfigureCenteredHeaderIcon`, `MakeHeaderHoverGlow`) so any future sortable header matches automatically. Location: `GUI/SharedWidgets.lua`, `GUI/AHProfitTab.lua`, `GUI/CooldownsTab.lua`, `GUI/CraftingTab.lua`, `GUI/MissingRecipesTab.lua`.

- **Profit Planner row count moved to the window status bar.** "Rows: N" now follows the version string in the bottom status bar (e.g. `v0.9.1    Rows: 300`) instead of a mid-panel label, and reverts to just the version on other tabs. Location: `GUI/AHProfitTab.lua`, `GUI/MainWindow.lua`.

- **Profit Planner recipe tooltips now show full game item tooltips with profit details.** Row hover anchors the game's native item tooltip (via `GameTooltip:SetHyperlink`) and appends a profit breakdown (source, craft cost, sell price, profit) below the standard item data, matching the enriched tooltip pattern from the Browser/Cooldowns tabs. Location: `GUI/AHProfitTab.lua`.

- **AH data source toggle changes now prompt for /reload in settings.** Added a yellow warning label above the AH data source checkboxes (Auctionator, TSM, etc.) reminding users that toggling pricing integrations on/off requires a `/reload` to fully take effect, since external addon APIs are cached at load time. Location: `GUI/Settings.lua`.

- **Search boxes now use a magnifying-glass icon instead of a text label.** The Profit Planner, Browser, Crafting, and Missing Recipes search fields show WoW's universal search icon inside the box (TSM-style) rather than a "Search recipes" label, via a shared `StyleSearchBox` helper. The Profit Planner "+ Profit only" checkbox also sits on the same center line as the dropdown controls. Location: `GUI/SharedWidgets.lua`, `GUI/AHProfitTab.lua`, `GUI/BrowserTab.lua`, `GUI/CraftingTab.lua`, `GUI/MissingRecipesTab.lua`.

### Bug Fixes

- **Profit Planner empty profession filter now shows no rows.** Previously, unchecking every profession (or using Clear All) displayed *all* rows and re-checked everything on the next redraw. An empty selection now matches no rows, and the all-except-Enchanting default applies only on first build. Location: `GUI/AHProfitTab.lua`.

- **Sort arrow no longer vanishes after the first sort/filter.** The arrow texture was detached (`SetParent(nil)`) when its column went unsorted and never re-attached when shown again, so it disappeared once the sort column changed. `ConfigureHeaderIcon` now re-parents the texture before showing it, and sortable headers register `OnRelease` callbacks that clean up `widget._sortIcon` textures (Hide, SetParent(nil), ClearAllPoints, nil) so they don't bleed across pooled AceGUI widgets. Location: `GUI/SharedWidgets.lua`, `GUI/AHProfitTab.lua`, `GUI/CooldownsTab.lua`, `GUI/CraftingTab.lua`.

- **Missing Recipes skill sort no longer buries default recipes.** Sorting by Skill now falls back to a recipe's orange difficulty tier when it has no explicit required-skill value (e.g. Basic Campfire), so low-skill recipes sort to the top instead of being treated as unknown and pushed to the bottom. Only recipes with neither value remain last. Location: `GUI/MissingRecipesTab.lua`.

- **Fixed memory leak: GameTooltip now hides when switching tabs.** If the tooltip was showing for a Profit tab element when you switched tabs, it remained visible and anchored to the wrong position. `DetachPool` now calls `GameTooltip:Hide()` on tab detach. Location: `GUI/AHProfitTab.lua`.

---

## [v0.9.0] (2026-06-01) - Shared global headers/sort across tabs

### New Features

- **Added a dedicated Profit Planner tab.** TOGPM now has a full AH profit-planning view for recipes known by your own characters, with separate Live AH Profit and Historical Profit subtabs so you can compare current listings against longer-horizon pricing without leaving the addon. The tab is wired into the main window as a first-class screen rather than a Crafting detail add-on, giving profit sorting/planning its own workspace. Location: `GUI/AHProfitTab.lua`, `GUI/MainWindow.lua`, `Locale/enUS.lua`.

### Improvements

- **One shared global sortable-header path now drives all sortable tabs.** Added shared helpers in `addon.GUI.Sort` for header-icon rendering and click-state transitions, then switched the Profit Planner, Cooldowns, and Crafting tab headers to use those globals instead of per-tab copies. Sort arrows now come from one reusable function (`ConfigureHeaderIcon`) with the same FGI-style texture behavior everywhere, and click transitions now use one shared state function (`Next` / `NextOrNone`) so tab behavior stays consistent as future columns are added. Location: `GUI/SharedWidgets.lua`, `GUI/AHProfitTab.lua`, `GUI/CooldownsTab.lua`, `GUI/CraftingTab.lua`.

- **Column-header styling is further centralized through shared helpers.** Updated remaining table headers that were still hand-styled to use the shared brand/header factory, reducing drift between tabs and keeping color/style changes globally managed. Location: `GUI/ShoppingListTab.lua`, `GUI/BrowserTab.lua`.

- **Labeled dropdowns and edit boxes now share one global label offset.** The old per-tab one-off nudges were replaced with a shared input-label helper that shifts labeled Dropdown/EditBox headers by the same 4px everywhere they appear, and restores the original anchors on release so pooled AceGUI widgets do not leak the tweak into other owners. Location: `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`, `GUI/MissingRecipesTab.lua`, `GUI/ShoppingListTab.lua`.

- **Zebra striping is now global across tab row lists.** The shared `addon.GUI.ApplyRowStripe` helper now drives row banding throughout the addon table UIs (not just Profit Planner), so stripe appearance is centralized and consistent across Browser, Missing Recipes, Crafting, Cooldowns, and Shopping List views. Location: `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`, `GUI/MissingRecipesTab.lua`, `GUI/CraftingTab.lua`, `GUI/CooldownsTab.lua`, `GUI/ShoppingListTab.lua`.

- **Cooldowns rows now render with the same raw frame/fontstring model as Missing Recipes, while still using the shared GUI helpers.** The tab no longer relies on AceGUI row-cell widgets for the list body; each row now uses raw frame hit zones, textures, and fontstrings like the working Missing Recipes/Professions lists. The reworked rows now also detach their raw child frames through the shared `addon.GUI.DetachPool` release path when AceGUI recycles a row widget, so the pooled Cooldowns rows don't bleed into later widget reuses. Headers remain on the shared column factory and row hovers stay on the addon-wide tooltip-owner path. Location: `GUI/CooldownsTab.lua`, `GUI/SharedWidgets.lua`.

- **Profit Planner now has Missing-Recipes-style subtab filters plus recipe search.** Each Profit subtab now renders its own toolbar with dynamic Profession and Crafter dropdowns populated only from rows currently present in that subtab, a `+ Profit only` toggle, a recipe search box, and a multi-select source filter that defaults to all sources currently enabled by settings for that mode. Filtering runs before sort/render and keeps per-subtab state. Location: `GUI/AHProfitTab.lua`.

- **Profit Planner now shows all known craftable recipes, not only fully-priced rows.** Row construction no longer drops recipes just because the crafted item has no current sale source or because one or more reagents lack price data; those rows are now retained with clear "No price" source text and empty cost/profit values until pricing is available. Source filtering now applies only when a row actually has source data, so default views do not hide unpriced recipes. Location: `GUI/AHProfitTab.lua`.

- **TSM App Helper pricing is now wired into material-cost lookups used by Profit/Crafting cost math.** The generic item-price resolver (`Price.Get`) now includes TSM live/history fallbacks (before TOGPM scan/vendor tiers), so reagent costing can consume TSM coverage instead of appearing unpriced when Auctionator/TOGPM scan data is absent. Also removed a hidden gate that required the separate "Use TSM" toggle for App Helper reads, so App Helper can function when its own toggle is enabled. Location: `Modules/Price.lua`.

- **Crafting reagent source tags no longer truncate in the detail panel cost column.** The per-reagent cost field was width-limited to coin text only, which clipped trailing source suffixes (e.g. `[TOGPM]`/`[TSM]`) on longer values; the column now has enough width to extend left and render full cost+source text. Location: `GUI/CraftingTab.lua`.

- **TSM sell-price lookup now falls back across the full TSM source stack to avoid nil sell prices when TSM has data.** The TSM bridge now tries both item string forms (`i:itemId` and `item:itemId`) and a broader ordered source chain (`DBMinBuyout`/`DBRecent`/`DBMarket`/`DBHistorical` plus `DBRegionMarketAvg` and `DBRegionSaleAvg` fallbacks), so items missing realm-live values can still resolve from TSM historical/region datasets in Profit views. Location: `Modules/Price.lua`.

- **Profit Planner now resolves sell-price item IDs and source filters more defensively to avoid false `No price` rows.** Sell lookup now probes multiple candidate output IDs per recipe (scanned crafted-item link first, then LibProfessionDB crafted item, then fallback item field), using the first one that resolves a price. Historical/live views now also allow cross-mode fallback when one side is missing, and the Profit-tab enabled-source defaults were aligned with the shared `Price` module's TSM toggle logic so valid TSM rows are not filtered out accidentally. Location: `GUI/AHProfitTab.lua`.

- **Per-tab scroll position now persists to SavedVariables and restores after tab switches/reopen.** The shared `PersistentScroll` helper now stores each tab's scroll status in `TOGPM_Settings.char.frames.scrollTabs` and restores from that table on redraw, so Browser/Cooldowns/Missing/Crafting/Profit return to the same place after refreshes, tab hops, and window reopen/reload. Profit keeps separate saved scroll for Live vs Historical subtabs. Location: `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`, `GUI/MissingRecipesTab.lua`, `GUI/CraftingTab.lua`, `GUI/AHProfitTab.lua`.

- **BoP reagents no longer create false profit/cost gaps.** Craft-cost completeness now excludes Bind-on-Pickup reagents from the `priced == count` gate, so recipes like Gordok Ogre Suit are still costed/profited from their priceable materials even when BoP components (for example Ogre Tannin) have no AH/vendor market price. Non-BoP unpriced reagents still correctly mark totals as lower-bound. Location: `Modules/Price.lua`.

- **Profit search box no longer drops keyboard focus after the first character.** The Profit tab search handler previously triggered a full table redraw on every `OnTextChanged`, which recreated the edit box and swallowed the caret. Search now refreshes rows in place (filter/sort/row repaint only) so typing remains continuous. Location: `GUI/AHProfitTab.lua`.

- **TSM source labels now distinguish live quotes from AppHelper-backed data.** TSM prices are now classified by the exact TSM expression that resolved: `DBMinBuyout`/`DBRecent` remain `TSM Live`, while `DBMarket`/`DBHistorical`/region values are labeled as non-live (`TSM App`) so Profit/Crafting columns no longer show everything as live. Profit source filters were updated so both TSM categories stay visible by default in each subtab. Location: `Modules/Price.lua`, `TOGProfessionMaster.lua`, `GUI/AHProfitTab.lua`, `GUI/MainWindow.lua`.

- **Auctioneer pricing is now integrated as an optional non-live source.** Added a new `Use Auctioneer pricing` toggle and wired `AucAdvanced.API.GetMarketValue` into sale/cost lookups as `Auctioneer App` (non-live), with source labels/colors, Profit source-filter support, Crafting source tags, and TOC/pkgmeta optional dependency declarations. This allows using Auctioneer-backed values when TSM is disabled, without mislabeling them as live quotes. Location: `Modules/Price.lua`, `GUI/Settings.lua`, `TOGProfessionMaster.lua`, `GUI/AHProfitTab.lua`, `GUI/CraftingTab.lua`, `GUI/MainWindow.lua`, `.toc` files, `.pkgmeta`.

- **Auctioneer source naming now resolves more reliably on sell-price rows.** Auctioneer market-value lookup now tries canonical item string forms (including full 8-field `item:` form) before falling back, which avoids false `No price` rows where Auctioneer has data but couldn't parse a compact link form. Resulting rows now correctly show the `Auctioneer App` source label. Location: `Modules/Price.lua`.

- **Auctioneer source naming now falls back to stat-engine values when market-value returns nil.** When Auctioneer's combined market-value PDF path has insufficient data for an item, TOGPM now probes common Auctioneer stat engines (`stat_simple`, `stat_histogram`, `stat_stddev`, `stat_iLevel`) before giving up, reducing remaining false `No price` rows and preserving `Auctioneer App` source labels where Auctioneer has usable pricing. Location: `Modules/Price.lua`.

- **Auctioneer now has a separate cached-fallback toggle, mirroring live-then-helper behavior.** Settings now include a second checkbox directly under `Use Auctioneer pricing`: `Use Auctioneer cached pricing fallback`. Resolver flow now tries Auctioneer primary market value first, then only uses Auctioneer cached stat-engine values when primary returns nil and the cached toggle is enabled, matching the intended two-stage fallback model used by other pricing integrations. Location: `GUI/Settings.lua`, `Locale/enUS.lua`, `Modules/Price.lua`, `TOGProfessionMaster.lua`.

- **Auctionator now has a separate historical/cached fallback toggle, matching the Auctioneer two-stage model.** Added `Use Auctionator cached historical fallback` directly under `Use Auctionator pricing`; resolver flow now tries Auctionator live first, then only uses Auctionator cached historical pricing when live is unavailable and the second toggle is enabled. Profit source defaults were aligned so `Auctionator History` is enabled only when this toggle is on. Location: `GUI/Settings.lua`, `Locale/enUS.lua`, `Modules/Price.lua`, `GUI/AHProfitTab.lua`, `TOGProfessionMaster.lua`.

- **Auctioneer source labels are now split in UI to clearly show live vs cached origin.** Resolver output now distinguishes Auctioneer primary market values (`Auctioneer Live`) from stat-engine fallback values (`Auctioneer Cached`) instead of reporting both as one `Auctioneer App` bucket, aligning with the same live-vs-cached clarity used for TSM labels. Profit source filters, main help legend, and Crafting source tags now surface the split explicitly, with a back-compat migration path for existing saved Profit source selections. Location: `Modules/Price.lua`, `TOGProfessionMaster.lua`, `GUI/AHProfitTab.lua`, `GUI/MainWindow.lua`, `GUI/CraftingTab.lua`.

- **Legacy Auctioneer alias text now resolves to `Auctioneer Cached` for consistency.** The old compatibility key (`auctioneer-app`) is still accepted for saved-state/back-compat paths, but its UI label/color now map to cached semantics so users never see contradictory `Auctioneer App` wording after the live/cached split. Location: `TOGProfessionMaster.lua`, `GUI/CraftingTab.lua`.

- **Missing Recipes column-header sorting is now wired into the shared global sort path.** The header row now uses clickable shared column headers with global sort indicators and state transitions (same `addon.GUI.Sort` pipeline as other sortable tabs), and the tab now applies sort to Recipe, Skill, and Source before virtual-row render. This fixes the broken/no-op header clicks in Missing Recipes. Location: `GUI/MissingRecipesTab.lua`.

- **Auctioneer live/cached probes are now more tolerant across API variants, and a new price diagnostic slash command was added.** The resolver now probes multiple Auctioneer call signatures and alternate stat-engine identifiers for cached values instead of relying on one strict signature, reducing false nils when Auctioneer builds/plugins expose slightly different APIs. Added `/togpm dumpprice <itemId|itemLink>` to print `Get`/`GetSaleLive`/`GetSaleHistorical` and Auctioneer live-vs-cached diagnostics for one item (for example Savory Deviate Delight `6657`) directly in chat. Location: `Modules/Price.lua`, `TOGProfessionMaster.lua`.

- **Auctioneer cached pricing now falls back to Stat modules directly when algorithm APIs yield nil.** Some Auctioneer installations expose cached prices through loaded `Stat-*` modules even when `GetAlgorithmValue` is unavailable or non-productive; TOGPM now probes `AucAdvanced.GetAllModules(nil, "Stat")` + each module's `GetPriceArray` and picks the best seen-backed cached value before giving up. `dumpprice` output now also reports whether the Auctioneer module registry is available for this fallback path. Location: `Modules/Price.lua`, `TOGProfessionMaster.lua`.

- **Global multi-select dropdown handler added, and Profit tab dropdown filters now all use it.** Added a shared `addon.GUI.MakeMultiSelectDropdown` factory (summary row + checkmark rows + no-empty fallback) and migrated Profit `Profession`, `Crafters`, and `Sources` filters to it so they now share one look/behavior and all support multi-select. Back-compat migration from older single-select `profession`/`crafter` state is handled automatically. Location: `GUI/SharedWidgets.lua`, `GUI/AHProfitTab.lua`.

- **TOGPM scanned-AH source now has an explicit on/off gate (no bleed when disabled).** Added a dedicated `Use TOGPM scanned AH pricing` setting and wired the central resolver to honor it for both reagent costs and live sell-price paths; when turned off, TOGPM's cached AH values are excluded so external-only testing (for example Auctioneer-only) is accurate. Profit source defaults now also respect this toggle. Location: `Modules/Price.lua`, `GUI/Settings.lua`, `GUI/AHProfitTab.lua`, `TOGProfessionMaster.lua`.

- **Blizzard Auction House now gets a native `TOGPM Scan` button.** Mirroring the profession-window TOGPM toggle pattern, the addon now injects a manual branded scan button directly onto the Blizzard AH frame (legacy and modern frame names), wired to TOGPM's full-scan path so users can trigger a TOGPM price refresh from the AH UI itself without opening any TOGPM tab first. Button state auto-disables while scans run and re-enables on completion/cancel/close. Location: `Modules/AHScanner.lua`.

- **Profit-tab recipe icons now use Crafting-style fallbacks for reliable rendering.** Profit rows now resolve icons using crafted-item texture first and fall back to recipe spell texture when item-icon cache data is unavailable, fixing intermittent `?`/missing icons on entries like Savory Deviate Delight while preserving normal item-icon rendering when available. Location: `GUI/AHProfitTab.lua`.

- **Profit now rejects recipe-scroll IDs when crafted output IDs exist.** For recipes that provide both IDs (for example Savory Deviate Delight: crafted `6657`, recipe scroll `6661`), Profit sell/icon candidate selection now anchors to crafted output and ignores scroll-item IDs, preventing recipe-scroll icon/source leakage in Profit rows. Location: `GUI/AHProfitTab.lua`.

- **Browser and Cooldowns profession filters now use the shared global multi-select dropdown handler.** Both tabs now use `addon.GUI.MakeMultiSelectDropdown` for profession filtering so the selector look/behavior matches Profit (same summary row/checkmark UX) and supports selecting multiple professions at once. Cooldowns keeps its specific cooldown sub-filter visible only when exactly one profession is selected, preserving the existing two-level workflow without inconsistent dropdown styles. Location: `GUI/BrowserTab.lua`, `GUI/CooldownsTab.lua`, `GUI/SharedWidgets.lua`.

- **Era recipe gating is now stricter in Missing Recipes and Browser to stop SoD/non-valid bleed-through.** Client-validity filtering no longer skips required-skill/high-ID sanity checks just because recipe metadata is lib-backed, and unknown-client suppression now checks crafted-item IDs as well as recipe-scroll IDs before showing rows. This keeps legitimate late-Vanilla recipes while filtering non-Era bleed from shared 1.15-era datasets. Location: `GUI/MissingRecipesTab.lua`, `GUI/BrowserTab.lua`.

- **Global multi-select dropdown UX now supports true multi-pick sessions.** The redundant selected-row check indicator was removed by moving the selected-count summary into the collapsed control text, and multi-select menus now stay open while you toggle items so you can select/deselect several entries before clicking away. Profit filter updates now refresh rows in place (not full redraw) so the open pullout is preserved while selecting. Location: `GUI/SharedWidgets.lua`, `GUI/AHProfitTab.lua`.

- **Fixed Missing Recipes `invalid order function for sorting` Lua error.** Header-sort logic now precomputes stable sort keys before `table.sort` instead of calling live item/spell lookup APIs inside the comparator, preventing comparator instability while cache lookups change during sort passes. Location: `GUI/MissingRecipesTab.lua`.

- **Fixed blank captions on global multi-select dropdowns.** The collapsed selected-count text now persists correctly after list refreshes; dropdowns no longer render as empty dark boxes after the keep-open multi-select UX change. Location: `GUI/SharedWidgets.lua`.

- **Fixed first-click multi-select behavior in profession filters.** The dropdown now clears AceGUI's internal selected row marker (so only per-item checkmarks are shown) and uses a short delayed reopen tick so the pullout reliably stays open while you pick multiple entries in one session. Location: `GUI/SharedWidgets.lua`.

- **Fixed multi-select reopen race that could still close after each pick.** The shared dropdown now waits for the pullout to finish closing, then reopens once (with short retry ticks) instead of blindly toggling immediately, so multi-select sessions stay open consistently on first and subsequent clicks. Location: `GUI/SharedWidgets.lua`.

- **Multi-select action rows now include both `Select all` and `Clear all`.** The old `Reset to all` action is now named `Select all`, and a new `Clear all` action clears every selected entry in one click for profession/crafter/source filters using the shared helper. Location: `GUI/SharedWidgets.lua`, `GUI/BrowserTab.lua`, `GUI/AHProfitTab.lua`.

- **Fixed Missing Recipes tab crash (`attempt to index local 'kb' (a nil value)`) during sort.** Sort-key precompute now uses defensive fallback key generation inside the comparator so sparse/edge-case lists cannot crash when a compared row lacks a cached key. Location: `GUI/MissingRecipesTab.lua`.

- **Fixed multi-select toggles that appeared to do nothing on some dropdowns.** The shared dropdown function now maps UI tokens back to canonical key types before mutating selection state, preventing numeric/string key mismatches from turning select/unselect clicks into no-ops. Location: `GUI/SharedWidgets.lua`.

- **Multi-select dropdowns now use AceGUI's built-in multiselect flow directly.** The shared helper now calls `Dropdown:SetMultiselect(true)` and synchronizes selection via `SetItemValue(...)`, removing custom keep-open/reopen hacks and aligning behavior with AceGUI's native toggle handling while keeping shared `Select all` / `Clear all` actions. Location: `GUI/SharedWidgets.lua`.

- **Fixed open multi-select pullouts going visually empty after a click.** The shared helper no longer rebuilds `SetList(...)` on every toggle while the pullout is open; it builds once and then only syncs check-state/text, matching AceGUI's open-time item rendering lifecycle. Location: `GUI/SharedWidgets.lua`.

- **Fixed Missing Recipes sparse-list sort crash (`table index is nil`).** The comparator now guards nil operands before key lookup and never indexes the key cache with nil, preventing edge-case tab-open crashes when a sparse row list reaches `table.sort`. Location: `GUI/MissingRecipesTab.lua`.

---

## [v0.8.4] (2026-06-01) — Enchanting shows a single "Enchant" button

### Improvements

- **Enchanting now presents one clean "Enchant" button.** Because an enchant is applied to a single item, the Crafting tab's controls for Enchanting are simplified to just an **Enchant** button (the secure `/cast` from v0.8.3) — the quantity stepper, **Craft Max**, and **Queue** are hidden (none apply to one-at-a-time enchanting), the button moves to the top of the controls column, and the detail panel sizes down to suit. Every other profession keeps the full Craft / Craft Max / Queue stack with the quantity controls. Also hardened: the now-secure Craft button's enable / position / attribute changes are guarded against combat lockdown (they can't be changed mid-combat). Location: `GUI/CraftingTab.lua`.

---

## [v0.8.3] (2026-06-01) — Enchanting can be cast from the Crafting tab (protected-function fix)

> The `DoCraft` error is gone for certain (we no longer call it); the secure-cast enchant path is pushed for **community testing** — there's no enchanter on the test account to verify it in-game.

### Bug Fixes

- **The `DoCraft` error is gone, and Enchanting should now craft from the Crafting tab.** Root cause of the long-running "can't enchant" bug: `DoCraft` — the Vanilla/TBC Craft API used for Enchanting — is a **protected** function, so an addon calling it from Lua trips `ADDON_ACTION_FORBIDDEN` and the craft is blocked. (That's why *only* Enchanting failed; `DoTradeSkill`, used by every other profession, isn't protected.) Fix — the same technique TradeSkillMaster uses: the **Craft button is now a secure action button** that, for an enchant, runs a `/cast <recipe>` macro. A `/cast` inside a secure macro is allowed, so the enchant casts and you click the target item to apply it — just like Blizzard's own Create button. Trade-skill professions keep the normal Lua craft (with batch quantity) via the button's PreClick. Craft Max / queued enchants still open Blizzard's Create button. Location: `GUI/CraftingTab.lua`, `Modules/Crafting/CraftingEngine.lua`, `Locale/enUS.lua`.

---

## [v0.8.2] (2026-06-01) — Opt-in AH scan & crafting takeover, SoD recipe filtering, enchant-button fix, consumable buffs

> **Heads-up:** this release adds **LibItemDB** as a required dependency (for consumable buff data). Like LibProfessionDB it must be published on CurseForge before this ships, or installs break on the missing dependency.

### New Features

- **Crafted-item stats & consumable buffs from LibItemDB.** Recipes now carry their product's stats, read at runtime from the new **LibItemDB** library via `DB:GetStats` (which merges equip stats + use-effects) — so it covers **crafted gear** (Blacksmithing / Tailoring / Leatherworking: `+5 Strength, +12 Stamina, +400 Armor`) **and consumables** (food / elixir / flask / potion: `+12 Spirit, +12 Stamina`) in one path. The Crafting / Professions / Missing Recipes searches now find recipes by stat — `strength`, `12 stam`, `spirit` — and the recipe tooltip shows the stat line, the same `effect` field enchants already use. **LibItemDB is authoritative**; ProfessionDB's effect text is the fallback only for true enchants, which LibItemDB doesn't cover. It's a **required dependency** (auto-installed by CurseForge; read via LibStub, never embedded), and its data is per-game-version. `GetStats` exposes the `GetItemStats` vocabulary (+stats, resistances/armor, crit/health/mana), so an item whose only effect is a non-stat one (a flat damage *absorb* like Fire Protection Potion) has no line to show. A new **`/togpm itemgaps [profId]`** command lists crafted items LibItemDB returns no stats for, to surface coverage gaps for filling. Location: `TOGProfessionMaster.lua` (`GetCraftedItemStatText` / `GetRecipeEffect` / `ReportItemDBGaps`), `GUI/CraftingTab.lua`, `GUI/BrowserTab.lua`, `GUI/MissingRecipesTab.lua`, TOCs + `.pkgmeta`.

- **Craft Max & Craft All — fewer clicks to batch-craft.** A new **Craft Max** button in the detail panel (between Craft and Queue) queues the most of the selected recipe you can make right now *and* starts crafting it in one click — Skillet's "Create All"; fan across several recipes (Craft Max each) to stack them all up fast. And a new **Craft All** button in the queue panel (between Craft Next and Clear All, all three on one row at the same total width) works down the whole queue, crafting each eligible recipe in turn — it chains to the next as each batch finishes, stopping on an interrupt or when nothing's left (Enchanting still pauses for you to click each target). Location: `GUI/CraftingTab.lua`, `Modules/Crafting/CraftQueue.lua`.

- **Profit / loss on the Crafting tab.** The Crafting Cost row now also shows — when the crafted item has an **Auction House** price (from Auctionator or TOGPM's own AH scan; never the vendor table) — the item's lowest AH buyout and the **profit**: AH price − crafting cost, green if you'd come out ahead, red if you'd lose coin (cost 5g / sells 8g → `+3g`; cost 5g / sells 3g → `-2g`). The row reads **cost / AH / profit**. Profit only shows when the craft cost is fully priced and there's a real AH sale price for the product. (First cut: assumes one item per craft and ignores the AH cut.) Location: `GUI/CraftingTab.lua`.

### Changes

- **The automatic Auction House full-scan is now opt-in (off by default).** v0.8.0 auto-ran a full `getAll` scan every time you opened the Auction House. That scan draws on a **shared, client-wide budget the server limits to roughly once every 15 minutes** — so on a client also running a dedicated AH addon (Auctionator, TradeSkillMaster, etc.) it consumed the budget that addon needs for its own scan and blocked it. A new **Settings → Auction House → "Auto-scan the Auction House on open"** toggle, **off by default**, now gates it, with a tooltip that spells out the once-per-15-min, shared-across-addons trade-off. With it off, TOGPM never fires a `getAll` on open (your other AH addon keeps its budget); cost-to-craft falls back to the built-in vendor prices, Auctionator (if you enable that), and the per-tab **[Scan AH]** buttons — which do small targeted per-item lookups, not `getAll`, and are unaffected. Turn the toggle on to restore the v0.8.0 auto-scan behaviour. Location: `Modules/AHScanner.lua`, `GUI/Settings.lua`.

- **The TOGPM Crafting tab no longer replaces the Blizzard profession window by default.** Opening a profession *at a station* now opens **Blizzard's own crafting window**, with the **TOGPM** button on it to switch to the Crafting tab whenever you like — so TOGPM no longer takes over every profession open. Two new **Settings → Crafting** toggles, both **off by default**: *"Open the TOGPM Crafting tab automatically"* restores the old takeover (opens straight into the TOGPM tab), and *"Remember the last crafting UI used"* reopens whichever UI — Blizzard window or TOGPM tab — you last used, overriding the first toggle (saved per character). The takeover setting moved from per-character to account-wide (`profile`); `/togpm craft on|off` still flips it. **Conversely, navigating to the TOGPM Crafting tab itself now auto-opens your selected profession straight into TOGPM** (no `Open <profession>` button click needed) — going to that tab is an explicit choice to craft there, so it overrides the default-to-Blizzard rule. Location: `Modules/Crafting/CraftingEngine.lua`, `GUI/CraftingTab.lua`, `GUI/Settings.lua`.

### Bug Fixes

- **Missing Recipes (and the Professions browser) no longer list Season of Discovery recipes on Era / Hardcore / Anniversary.** SoD runs on the same 1.15 client as Era, so its recipes live in the shared client tables — and therefore in LibProfessionDB's Vanilla set — even though they can't be learned on a non-SoD realm (e.g. *Enchant Weapon - Grand Crusader*, *Sigil of Innovation*, *Blackfathom Mana Oil*, *Scroll of Spatial Mending*). v0.8.0 had dropped TOGPM's client-side recipe gates (trusting the version-scoped lib data), which let them through. SoD content sits in a distinct spell-ID range (**400,000+**) far above any real Vanilla recipe (under ~30,000), so a Vanilla client that isn't running Season of Discovery now hides IDs ≥ 200,000. SoD itself is detected via the rune-engraving system (`C_Engraving`), so actual SoD players keep their recipes. Location: `Compat.lua`, `GUI/MissingRecipesTab.lua`, `GUI/BrowserTab.lua`.

- **Enchanting's Craft button enable now covers both crafting APIs.** v0.8.1 made the Craft button derive its craftable count from reagents for the Vanilla/TBC Craft window (since `GetCraftInfo`'s `numAvailable` reads 0 for enchants, which produce no item). That repair now also applies to the trade-skill API as a fallback (`GetTradeSkillInfo` `numAvailable == 0` → mats-based count), so Enchanting's Craft button enables when you hold the materials regardless of which API the client routes Enchanting through. A disabled button was why clicking did nothing / never put up the apply-to-item cursor; once enabled, `DoCraft`/`DoTradeSkill` raises that cursor — the same call TradeSkillMaster makes from its own UI. (Still pending community confirmation — no enchanter on the test account.) Location: `Modules/Crafting/CraftingEngine.lua`.

- **The "TOGPM" button now appears on Blizzard's profession window whenever it's open — not only when you switch to it from TOGPM.** It's hooked to the frame's `OnShow`, so it rides along even when a coexisting addon (TSM, Skillet) or the auto-open-into-TOGPM flow is what put the Blizzard window up, and even if that addon shows the frame after our handler runs (immediate-show-if-visible covers the event-order race). That guarantees there's always a way back into TOGPM after you close its window. Previously the button was only injected on our own `ShowDefaultUI` path, so it was missing in those cases. Location: `Modules/Crafting/CraftingEngine.lua`.

- **Recipe tooltips no longer stretch across the screen.** The Professions tab builds a recipe's hover tooltip by scraping the crafted item's tooltip lines; long ones (e.g. a flask's verbose `Use:` text, or a six-school resistance line) were added unwrapped and blew the tooltip out to full screen width. They're now word-wrapped, so the tooltip sizes to its header/stat lines. Location: `GUI/BrowserTab.lua`.

### Improvements

- **Window scale slider.** A new **Settings → Display → "Window scale"** control (50%–150%) scales the entire TOG Profession Master window. It lets the Crafting tab — and every tab — take far less screen space than the resize floor (820×540) allows: scaling shrinks the text, recipe columns and queue panel together instead of squeezing the layout, so nothing overlaps. Independent of size, so the window still resizes and remembers its dimensions; the on-screen footprint is size × scale. Stacks with corner-dragging for full control. Location: `GUI/MainWindow.lua`, `GUI/Settings.lua`.

- **Recipe search now matches the crafted item's full tooltip text.** Beyond the recipe name and stat line, the Crafting and Professions searches fold in the *whole* crafted-item tooltip — use/proc text, durations, requirements, flavor — so any word matches (e.g. `hour` finds a 1-hour elixir, `chance on hit` finds a proc weapon, `requires level 40` works). LibItemDB stores stat *values*, not the prose, so this text is scraped from the live client item tooltip and cached per item; an item the client hasn't loaded yet becomes searchable once its data arrives. Location: `TOGProfessionMaster.lua` (`GetItemTooltipSearchText`), `GUI/CraftingTab.lua`, `GUI/BrowserTab.lua`.

- **Clearer reagent counts in the Crafting detail panel.** v0.8.1's `bank / bags / needed` triple was easy to misread — the "needed" figure looked like part of an inventory count. The needed quantity is now a **prefix on the reagent name** ("12x Greater Eternal Essence"), and the count column is just your inventory, in **bags / bank** order. Same green/red colouring (green when bags + bank covers the need). The needed prefix carries no tooltip. Location: `GUI/CraftingTab.lua`.

---

## [v0.8.1] (2026-05-31) — Crafting tab: Enchanting craft, queue completion, resizable window, bank counts & smarter search

> Reported from **Classic Era Hardcore** play-testing. The Enchanting / craft-queue fixes could not be verified locally (no enchanter on the test account) — pushed for community testing.

### New Features

- **Crafting tab reagents now show bank / bags / needed.** The Missing Materials column previously showed only bags-on-hand against the needed amount; each reagent now reads `bank / bags / needed`. **bank** is the count from your last visit to your personal bank — a cached snapshot persisted between sessions (it reuses the existing Reagent Watch bank scan taken on `BANKFRAME_CLOSED`), so it can be slightly stale until your next bank visit; **bags** is live. A reagent you've stashed in the bank no longer reads as missing — the row turns red only when **bank + bags together** fall short of what's needed. Location: `GUI/CraftingTab.lua`, `Modules/ReagentWatch.lua`.

- **Optional: clear the craft queue when switching professions.** The queue is intentionally **kept** across profession switches (so you can bounce between professions toward a single goal without rebuilding it). A new **Settings → Crafting** toggle — *"Clear craft queue when switching professions"*, **off by default** — empties the queue each time you change the Crafting tab's profession dropdown, for players who prefer a clean slate per profession. Location: `GUI/Settings.lua`, `GUI/CraftingTab.lua`.

### Bug Fixes

- **Enchanting (and any Vanilla/TBC Craft-window profession) couldn't be crafted from the Crafting tab — the Craft button stayed greyed out, the Have-Materials filter hid every enchant, and the craftable-count column read blank.** Root cause: the tab gated craftability on `GetCraftInfo`'s `numAvailable`, which is **unreliable on the classic Craft API** — it returns 0 for enchants even with reagents in hand (item-making professions like Alchemy were fine, which is why the bug looked Enchanting-specific). Confirmed against TradeSkillMaster, which ignores `numAvailable` entirely and derives the craftable count from materials. Fix: `CraftingEngine:GetRecipeList` now computes `num` for Craft-window recipes from reagents (`min(floor(have/need))`, matching TSM's `GetNumCraftable`), so the Craft button enables when you hold the mats, the Have-Materials filter keeps those enchants, and the count column is correct — all from one corrected number. The enchanting rod is a spell-focus (not a reagent), so it never skews the count. Trade-skill professions keep their reliable `numAvailable` and are unchanged. Location: `Modules/Crafting/CraftingEngine.lua`.

- **Switching professions via the Crafting-tab dropdown closed the TOGPM window when another profession addon (e.g. Skillet) was loaded.** Root cause: two addons both hijack the trade/craft window, so a profession switch fires a window `CLOSE` immediately followed by a `SHOW`, and we tore down synchronously on the `CLOSE` — collapsing our window in that gap before the `SHOW` reopened it (disabling Skillet made it stop). Fix: the teardown is now debounced (`CraftingEngine:ScheduleClose`) — on a `CLOSE` we wait 0.2s and only fold the window up if **both** the trade-skill and craft sessions are still closed, so a profession-switch handoff (or a rival addon's event churn) can no longer close us. Location: `Modules/Crafting/CraftingEngine.lua`.

- **Finished crafts didn't always drop off the craft queue.** Two gaps: (1) completion tracking only ran for the queue's **Craft Next** button — crafting a queued recipe with the detail-panel **Craft** button left the made item stuck in the queue, because that path never told the queue a craft had started; (2) on the Vanilla/TBC Craft window (Enchanting), the queue expected one `UNIT_SPELLCAST_SUCCEEDED` per item in the batch even though `DoCraft` makes exactly one item per call, so an enchant entry never counted down to zero. Fix: both craft buttons now route completion tracking through the single `CraftingEngine:Craft` chokepoint (new `CraftQueue:TrackCraft`), and the Craft window registers a single expected success — so a queued recipe decrements as it's made no matter which button started it. Location: `Modules/Crafting/CraftQueue.lua`, `Modules/Crafting/CraftingEngine.lua`.

### Improvements

- **The Crafting tab is now resizable.** It previously opened at a fixed 820×600 with the resize grip removed entirely. It now has a draggable grip (minimum 820×540, no maximum) and the layout reflows to fit: the recipe list grows in both directions while the detail panel stays pinned full-width along the bottom and the queue panel stays pinned to the right. The chosen size is remembered (shared with the Browser tab's resizable size). Reported in-game. Location: `GUI/CraftingTab.lua`, `GUI/MainWindow.lua`.

- **Crafting and Professions search now matches each term independently across name + effect.** Effect text ships stat-first (e.g. `Agility +5`, `Weapon Damage +5`), so the old single-substring match couldn't find natural queries like `5 agi` or `5 agility` — `"5 agi"` simply isn't a substring of `"agility +5"`, which is why an Enchanting search for `5 agi` came back empty even though the effect-search feature was working. Search now splits the query on spaces and requires **every** term to appear somewhere in the recipe's name + effect, in any order, so `5 agi`, `agi 5`, `5 agility`, and `weapon damage` all match regardless of how the effect text is worded. Reported in-game. Location: `GUI/CraftingTab.lua`, `GUI/BrowserTab.lua`.

---

## [v0.8.0] (2026-05-30) — Crafting tab, cost-to-craft, and the LibProfessionDB data library

> **Heads-up:** this release moves the recipe database into the new standalone **LibProfessionDB** library and depends on it. It cannot load until LibProfessionDB is installed (it's a required dependency in the TOC / `.pkgmeta`), so it must not ship before that library is published.

### New Features

- **Crafting tab.** A full fourth tab modeled on TradeSkillMaster's crafting screen but in TOGPM's own style (AceGUI widgets, brand colour, shared tooltip handler). It **replaces the native profession window** when you open a profession — with a toggle button to drop back to the Blizzard UI — pre-populates a dropdown from your known professions, and lists every recipe with a difficulty-coloured name and an orange→yellow→green→grey skill-tier column. Local single-character crafting; a virtual-scroll raw-frame row pool keeps it instant on large recipe sets. Location: [GUI/CraftingTab.lua](GUI/CraftingTab.lua), [Modules/Crafting/CraftingEngine.lua](Modules/Crafting/CraftingEngine.lua).

- **Craft queue.** Queue recipes and craft them top-down, with click-drag to reorder so you can stack-rank what gets made first. Completion-tracked (watches `UNIT_SPELLCAST_SUCCEEDED`) and persisted as a proper per-character table. Location: [Modules/Crafting/CraftQueue.lua](Modules/Crafting/CraftQueue.lua).

- **Cost-to-craft.** A per-recipe **Crafting Cost** total (on the recipe-name row, above the Missing Materials label) plus a per-reagent **Cost** column, summed by a unified price provider. Sources, in priority order: the Auction House (TOGPM's own scan, or Auctionator when you opt in) then a shipped vendor-price table. Markers: `*` = a reagent has no price yet (total is a lower bound), `~` = a contributing price is stale, `—` = nothing priced. Location: [Modules/Price.lua](Modules/Price.lua), [GUI/CraftingTab.lua](GUI/CraftingTab.lua).

- **Built-in Auction House scan — no Auctionator required.** Opening the Auction House auto-fires a one-pass full scan (legacy `getAll` on Era/TBC/Wrath, `C_AuctionHouse.ReplicateItems` on Cata/MoP) that builds TOGPM's own price DB — no button to click. Modeled on Auctionator's FullScan: a dedicated scan frame silences every other `AUCTION_ITEM_LIST_UPDATE` listener during the getAll so the Blizzard AH UI can't corrupt the result set; lowest per-unit buyout per item, batched across frames. Honours the server's ~once/15-min getAll throttle, and the scan is cached for the whole session so re-opening the AH inside the cooldown reuses it. Location: [Modules/AHScanner.lua](Modules/AHScanner.lua).

- **Auto-populated `[AH]` buttons.** Because the full scan knows every listed item, the per-row `[AH]` buttons across the Professions / Crafting / Missing / Cooldowns / Shopping List tabs now light up straight from it — no per-recipe "Scan AH" click. Location: [Modules/AHScanner.lua](Modules/AHScanner.lua) `GetListingsFor`.

- **Optional Auctionator integration (off by default).** A "Use Auctionator pricing" toggle under Settings → Auction House. Off by default so the addon uses its own scanned + vendor prices first; tick it to prefer Auctionator's price database when installed. Auctionator is an `OptionalDeps`, never required. Location: [GUI/Settings.lua](GUI/Settings.lua), [Modules/Price.lua](Modules/Price.lua).

- **Shipped vendor-price table.** A generated [Data/VendorPrices.lua](Data/VendorPrices.lua) gives thread, dyes, vials, flux and other vendor-bought reagents a cost out of the box — gated to genuinely vendor-sold items (emulator `npc_vendor`, unlimited-stock + gold-only, so drop/farmed mats are never mis-priced) and priced from wago ItemSparse.

### Changes

- **Recipe data now comes from the standalone LibProfessionDB-1.0 library.** TOGPM no longer bundles its own all-version-merged `Data/Recipes/*.lua`; those are removed and replaced by a small bridge ([Data/RecipeDB.lua](Data/RecipeDB.lua)) that points `addon.recipeDB` at the library's **point-in-time** recipe set for the running game version + locale. Because the library data is already version-scoped, the per-client expansion gates in BrowserTab / MissingRecipesTab (`minExpansion`, the `spellId > 25000` heuristic, the skill cap) now step aside for it — which also fixes the class of bug where legitimate high-ID Classic recipes were wrongly hidden. ProfessionDB is declared in `## Dependencies` and `.pkgmeta required-dependencies`.

- **Enriched, searchable effect text.** Enchanting recipes carry their effect (`+5 Weapon Damage`, `+1 All Stats`, …). The Crafting and Professions tab searches now match recipe **name OR effect** (so `5 damage`, `agility`, `mining` all find recipes), and both tabs' tooltips show the effect. Search boxes lost the non-functional AceGUI "okay" button and got clearer tooltips. Location: [GUI/CraftingTab.lua](GUI/CraftingTab.lua), [GUI/BrowserTab.lua](GUI/BrowserTab.lua).

### Localization

- **Crafting tab is fully localized.** Every crafting-tab string is a locale key (no hardcoded text), defined in `Locale/enUS.lua` and present in all 15 shipped locale files so translators can localize in place — English fallback until then. The per-reagent **Cost** column also right-aligns cleanly (coin strings no longer wrap to a second line). Location: [Locale/](Locale/), [GUI/CraftingTab.lua](GUI/CraftingTab.lua).

- **Dutch (`nlNL`) native-speaker review.** Reviewed by a Dutch speaker: game-mechanic terms (profession / reagent / Auction House / cooldown names, etc.) kept in English, "watch" → "in de gaten houden", "characters" → "personages". Location: [Locale/nlNL.lua](Locale/nlNL.lua).

---

## [v0.7.6] (2026-05-29) — GetTradeSkillLine signature bug — every Classic scan was writing maxRank as skillRank

### Bug Fixes

- **"Can learn now" filter on Missing Recipes was comparing recipes' required-skill against the character's MAX skill instead of their current rank.** Reported in-game: a 267/300 Vanilla Blacksmith named Genguin with the filter on still saw 116 missing recipes including every 290 / 295 / 300 Plan (Volcanic Hammer, Thorium Leggings, Imperial Plate Chest, Runic Plate Shoulders, etc.) — recipes that were clearly above his actual rank. Root cause: [Scanner.lua](Scanner.lua) `ScanTradeSkillInto` read the trade-skill window header as `local skillName, _, skillRank, skillMax = GetTradeSkillLine()` — a 4-return signature with `texture` discarded in position 2. That's the **modern WoW (pre-`C_TradeSkillUI`) signature**, but on **every Classic version** (Vanilla / TBC / Wrath / Cata / MoP) `GetTradeSkillLine()` returns just `(name, rank, maxRank)` — 3 values, no texture. Confirmed against AllTheThings (`src/UI/Windows/Tradeskills.lua:167`) and MissingTradeSkillsList (`ui/event_handler.lua:168`), both of which run on every Classic expansion and use the 3-return signature. So our read was misaligned by one position: the `_` discarded the actual current rank, `skillRank` picked up `maxRank` instead, and `skillMax` came back nil and got defaulted to 300 inside `MergeRecipesIntoGdb`. Net effect for every Classic trade-skill scan since the addon was written: `gdb.skills[charKey][profId].skillRank = the character's MAX skill`, `skillMax = 300` regardless of cap. Nothing read these fields until v0.7.4's "Can learn now" filter, so the bug stayed invisible for the entire pre-v0.7.4 history. Then the filter compared each recipe's `requiredSkill` against a `skillRank` that was silently pinned to the player's max forever, and every recipe up to that max passed through. **Fix:** changed the read to `local skillName, skillRank, skillMax = GetTradeSkillLine()`. Existing affected players need to open each trade-skill window once post-update to overwrite their stale `gdb.skills` entries with the correctly-read rank — same self-healing model as the v0.7.5 `ScanCraftSkillInto` fix for Vanilla Enchanters. Location: [Scanner.lua](Scanner.lua) `ScanTradeSkillInto`.

---

## [v0.7.5] (2026-05-29) — "Can learn now" follow-ups + Browser cross-version gate + RecipeMaster crash sidestep + Alchemy data tidy

### Bug Fixes

- **"Can learn now" filter on Missing Recipes resurrected every recipe the character already knew.** Reported in-game: with the filter OFF a Vanilla Leatherworking char showed 33 missing recipes; flipping the filter ON jumped that to 155, because every recipe the char already knew (and the unfiltered list was correctly hiding) suddenly reappeared. Root cause was a structural bug in v0.7.4's first cut: the `canLearnOnly` branch was wired as another `elseif` in the existing skip-rule chain inside `BuildMissingList`, sitting BEFORE the `elseif knownByChar(spellId)` / `elseif knownByChar(data.teaches)` / `elseif knownByChar(data.craftedItemId)` checks. `elseif` short-circuits the rest of the chain once any branch's condition is true — so as soon as `canLearnOnly` was on, the chain landed in MY branch, set `skip` based purely on the skill-rank comparison, and never ran the known-by-char checks at all. Net effect: "known" recipes stopped being filtered out the moment the toggle came on. **Fix:** pulled the filter out of the `elseif` chain entirely. It now runs as a separate `if not skip and canLearnOnly then ... end` guard AFTER the elseif chain finishes — so all the existing skip rules (minExpansion, requiredSkill cap, season, knownByChar variants, rank-book caps, unknown-spell gate) get a chance to mark a row skipped first. The "Can learn now" filter only ever tightens the visible set; it never relaxes earlier rules. Location: [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua) `BuildMissingList`.

- **Vanilla Enchanters saw an empty "Can learn now" list — every Enchanting recipe got hidden.** [Scanner.lua](Scanner.lua) `ScanCraftSkillInto` is the legacy Craft-API scan path Vanilla uses for Enchanting (and a couple of similar trade-skill-like Crafts) instead of the modern TradeSkill API. v0.7.4 and earlier only read the SKILL NAME from `GetCraftDisplaySkillLine()` and hardcoded `skillRank = 0, skillMax = 300` when calling `MergeRecipesIntoGdb`. The actual API returns `(name, rank, maxRank)` — the 2nd and 3rd return values were just being discarded. v0.7.4's "Can learn now" filter then compared every recipe's `requiredSkill` against the persisted `skillRank = 0`, and since virtually every recipe has `requiredSkill > 0`, every Enchanting recipe got hidden when the filter was on. **Fix:** read all three return values from `GetCraftDisplaySkillLine` and pass the real rank/max through. Existing Vanilla Enchanters need to open their Enchanting window once post-update to overwrite the stale `gdb.skills[charKey][333].skillRank = 0`; the next scan re-populates correctly. Location: [Scanner.lua](Scanner.lua) `ScanCraftSkillInto`.

- **"Can learn now" still let high-skill Blacksmithing / Tailoring / etc. recipes through for low-rank chars.** Coverage gap in the shipped recipeDB: ~13% of Blacksmithing entries, ~16% of Tailoring entries, smaller fractions across other professions ship without an explicit `requiredSkill` field — because the upstream sources (recipe scroll's `RequiredSkillRank`, trainer SQL's `ReqSkillRank`) didn't supply a value. v0.7.4's filter only checked `data.requiredSkill`, treated nil as "unknown → keep visible" per the original spec, and let those high-tier recipes through; a 267 Blacksmith with the filter on still saw 300-skill recipes in their list. **Fix:** when `requiredSkill` is nil, fall back to `data.difficulty[1]` — the orange threshold, which IS the lowest skill rank the recipe can actually be cast at. Better proxy than "unknown" for the recipes our DB has incomplete `requiredSkill` coverage for. Recipes with NEITHER field still pass (true unknowns — same intentional permissive behaviour as v0.7.4). Location: [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua) `BuildMissingList` gate resolution.

- **"Show all recipes" on the Browser tab leaked cross-expansion content on Vanilla / TBC clients.** The shipped `addon.recipeDB` is a universal union of every recipe across Vanilla / TBC / Wrath / Cata / MoP (built from wago.tools' MoP build, which inherits every earlier expansion's SkillLineAbility entries), so iterating it unfiltered on a Vanilla client surfaced Wrath / Cata / MoP recipes — both via the "Show all recipes" toolbar checkbox AND via guild view when a peer in a different-version guild had broadcast their data. The MissingRecipesTab already applied a per-client gate (`minExpansion` + spell-ID-greater-than-25000 defensive rule + `requiredSkill > clientMaxSkill` cap + season flag), but BrowserTab had no such gate. **Fix:** pulled the rule set into a `passesClientGate(profId, recipeId)` helper inside `BuildRecipeList` and applied it to every view path — `guild`, `mine`, `missing`, and the `showAll` toggle alike. Browser now agrees with MissingRecipesTab on what's reachable on the current client. Location: [GUI/BrowserTab.lua](GUI/BrowserTab.lua) `BuildRecipeList`.

- **RecipeMaster's tooltip hook caused a 100+ error storm every time you opened Missing Recipes.** RecipeMaster's `TooltipHandler.lua:165` and `:176` register `OnTooltipSetItem` and `OnTooltipSetSpell` handlers on `_G.GameTooltip` via `GameTooltip:HookScript`. On Vanilla their `cachedRecipes` table is empty, so `getRecipeInfo` returns nil for every recipe-scroll tooltip; `getAllCharactersRecipeStatus` then hands the nil into `isSkillLearnedByCharacter` which nil-indexes `recipe.teaches` at `RecipeHandler.lua:43`. Every mouseover threw. v0.6.1 tried wrapping our `SetItemByID` call in `pcall` — script-handler errors are dispatched by WoW outside the caller's stack, so pcall never saw them. v0.7.5's first attempt swapped `geterrorhandler()` for a no-op during the call — BugGrabber (BugSack's capture lib) hooks at a deeper level than `seterrorhandler` reaches, so it still logged them. **Final fix:** lazy-create a private `TOGPMMissingRecipeTip` GameTooltip frame inheriting from `"GameTooltipTemplate"` (the same virtual template `_G.GameTooltip` itself is built from — see [Blizzard_GameTooltip/Mainline/GameTooltip.xml](file) line 4) and route every Missing-Recipes-row tooltip through that instance instead of the global. Same template = full Blizzard appearance, full `SetItemByID` / `SetSpellByID` / `SetText` API. Different frame instance = RecipeMaster's `HookScript` on the global never fires. Zero errors, full rich tooltip preserved. Other tabs continue using the global GameTooltip — they don't surface "Recipe:" / "Pattern:" prefixed items so RecipeMaster's `isItemARecipe` gate never matches and the broken path never runs. Location: new `MissingRecipesTab:GetCustomTip()` lazy-init + every `GameTooltip:` call in the row-OnEnter handler swapped for `tip:`. [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua).

### Data

- **Recipe: Elixir of Tongues (spell 2336) and Recipe: Cowardly Flight Potion (spell 6619) removed from the Alchemy recipeDB.** Player-confirmed not obtainable in current Classic Era / Anniversary. Were showing as missing on every alchemist with no source data because the underlying recipe scrolls (item 2556 / 5641) genuinely don't drop / spawn. Cleaner to drop them than show with "Unknown" source forever. Location: [Data/Recipes/Alchemy.lua](Data/Recipes/Alchemy.lua).

- **Source categories added for Recipe: Restorative Potion (spell 11452) and Recipe: Greater Holy Protection Potion (spell 17579).** Both were showing "Unknown" in the Missing Recipes Sources column. Restorative Potion tagged as `quest` (rewarded by Uldaman Reagent Run / Badlands Reagent Run / Badlands Reagent Run II). Greater Holy Protection Potion tagged as `drop`. UI only reads category presence, never the specific NPC/quest IDs, so the inner ID tables are intentionally empty — backfill specific IDs later if a tooltip ever surfaces them. Location: [Data/Sources/Alchemy.lua](Data/Sources/Alchemy.lua).

---

## [v0.7.4] (2026-05-29) — "Can learn now" filter on the Missing Recipes tab

### New Features

- **"Can learn now" checkbox on the Missing Recipes toolbar.** Player request. Hides recipes the selected character isn't skilled enough to train yet — strict comparison: only shows rows where the character's current skill rank (from `gdb.skills[charKey][profId].skillRank`) is at or above the recipe's `requiredSkill`. Recipes with unknown skill requirement (where neither the recipe scroll's `RequiredSkillRank` nor the trainer SQL's `ReqSkillRank` supplied a value — `requiredSkill` is nil) stay visible regardless of the filter, so officers scanning gaps don't miss anything we can't classify. Sits next to the existing "Include trainer-only" checkbox in the toolbar; off by default; state survives tab switches but resets on UI reload (same pattern as `_includeTrainer`). Location: [GUI/MissingRecipesTab.lua](GUI/MissingRecipesTab.lua) — new `canLearnOnly` parameter on `BuildMissingList`, new state field `MissingRecipesTab._canLearnOnly`, new locale keys `MissingCanLearnOnly` / `MissingCanLearnOnlyDesc` in [Locale/enUS.lua](Locale/enUS.lua). Other locales fall back to English via AceLocale writeproxy until translations land.

---

## [v0.7.3] (2026-05-28) — Salt Shaker banker exclusion actually works now

### Bug Fixes

- **Salt Shaker banker exclusion shipped broken in v0.7.2.** The v0.7.2 fix added `addon.Bank.IsBanker(charKey)` in `Compat.lua` that rolled its own check: walk `TOG:GetBanks()`, compare each entry against `charKey:match("^([^-]+)")` (the short name without the realm suffix). On connected-realm guilds — which is to say, virtually all live Classic Era / TBC / Wrath realms — `TOG:GetBanks()` returns roster `member.name` values which are `"Name-Realm"` because cross-realm clusters report the realm suffix on every roster entry. My short-name comparison stripped the realm before comparing, so the LHS was always `"Name"` while the RHS was always `"Name-Realm"` — no entry ever matched, every banker fell through as non-banker, and the Salt Shaker filter never fired. **Fix:** delegate to TOGBankClassic's own canonical `TOG:IsBank(name)` method (in `TOGBankClassic/Modules/Guild.lua`) instead of rolling our own loop. `TOG:IsBank` accepts any name format, normalizes via its `NormalizeName` helper, and does an O(1) `memberRoster` lookup against the live banker set — bypassing all of the format-mismatch hazards. Location: [Compat.lua](Compat.lua) `addon.Bank.IsBanker`. The caller in [GUI/CooldownsTab.lua](GUI/CooldownsTab.lua) is unchanged — same signature, just a working implementation behind it.

---

## [v0.7.2] (2026-05-28) — Bogus cooldown entries (mage talents, portals) evicted + transmute popup correctness + banker exclusion

### Bug Fixes

- **Non-profession spells (e.g. Impact rank 5 / spell 12360, Portal: Undercity) rendered as cooldown rows under alchemist / other profession characters.** Root cause was a missing whitelist on two paths: (1) `GUI/CooldownsTab.lua`'s `BuildRows` walked every spell ID in `gdb.cooldowns[charKey]` and fell through to `GetSpellInfo`/`GetItemInfo` for the row label, so any spell ID happily rendered as a "cooldown" — including Mage talents and class spells with no profession meaning. (2) `Scanner:OnGuildDataReceived`'s `cooldown:` leaf handler accepted any spell ID from a peer broadcast with no validation against the addon's known cooldown set. Stale entries from old v0.6.x code paths or buggy peer broadcasts therefore stuck around forever, displaying nonsense rows on every reload. **Fix:** two-part. (a) `BuildRows` now guards the single-spell branch with `data.cooldowns[spellId] or spellId == data.saltShakerItem` — anything not in `Data/CooldownIds.lua`'s whitelist gets silently skipped. Same defensive-display pattern as `IsVisibleCrafter`. (b) A one-shot `addon:RemoveBogusCooldowns` sweep runs at every `OnInitialize` after migration — walks `gdb.cooldowns`, strips any spell ID not in the whitelist (`data.cooldowns` / `data.transmutes` / `groupBySpell` / `saltShakerItem`), and stops the entries from re-broadcasting forward. Idempotent. Existing affected players see their cooldown DB cleaned on the next `/reload`; the display guard catches any new ones that arrive via future inbound payloads.

- **Transmute popup showed transmutes the alchemist doesn't know.** The cooldown-derived emit branch in `GUI/CooldownsTab.lua` accepted any spell ID in `tg.spellIds` whose live `GetSpellInfo` name matched `"Transmute"` — even when the alchemist's `gdb.recipes[171]` cross-reference returned no hit. Stale cooldown records (transmutes they had on CD before unlearning, or pre-v0.7.0 leftovers, or peer-broadcast pollution under wrong charKey) therefore surfaced as phantom popup rows for transmutes the char no longer knows. **Fix:** the cooldown-derived branch now requires `recipeBySpellId[sid]` to resolve (i.e., the spell ID is one the char actually owns per the recipe DB cross-reference). The "Transmute"-name fallback is removed — anything not backed by current recipe knowledge is silently filtered.

- **Transmute popup showed different per-row timers for spells that share one cooldown.** In Classic Era / TBC / Wrath, all alchemy transmutes share a single ~20-hour cooldown — but the game only records the CD under the spell ID the alchemist actually cast. The popup's per-row time column used `charCds[spellId]` to look up the time per entry, so the cast spell showed (e.g.) "5h 17m" while every other transmute in the same popup showed "Ready" — visually inconsistent and misleading (the others aren't actually castable). **Fix:** transmute-group popup rows now use the group's shared `row.expiresAt` (the max future expiry across every transmute spell the char knows) for every entry. Non-transmute group popups (Mooncloth tier, etc.) still resolve per-spell — those CDs are genuinely independent. Location: `GUI/CooldownsTab.lua` `ShowGroupPopup`.

- **TOGBankClassic banker alts surfaced spurious Salt Shaker cooldown rows.** A bank toon with no cooking skill had a stale Salt Shaker (item 15846) CD record in `gdb.cooldowns` — most likely from a pre-repurposing scan, or peer-broadcast pollution under the wrong charKey, or pre-v0.7.0 data that survived migration. The CD was display-only noise (bankers can't cast Salt Shaker anyway), but it cluttered the Cooldowns tab with a row that always read "Ready" and could never actually go anywhere. **Fix:** added `addon.Bank.IsBanker(charKey)` helper in `Compat.lua` that compares the charKey's short-name against `TOGBankClassic_Guild:GetBanks()`. The Salt Shaker branch of `BuildRows` in `GUI/CooldownsTab.lua` now skips emit when the row's charKey is a banker. No-op when TOGBank isn't loaded. **NOTE:** this first-pass implementation was broken on connected-realm guilds — see v0.7.3 for the fix.

---

## [v0.7.1] (2026-05-28) — Vanilla / Classic Hardcore scan-key bug + minimap position persistence

### Bug Fixes

- **Vanilla / Classic Hardcore recipes scanned but didn't display.** On TBC and later, `GetTradeSkillRecipeLink` returns `|Henchant:SPELLID|h…` for every profession, so `Scanner:ExtractTradeSkillId` returns the spell ID — which is the same key `addon.recipeDB` is built around, and the cross-reference at display time works. On Vanilla (and 1.15.x Classic Hardcore which inherits the same APIs), the link format is `|Hitem:ITEMID|h…` for everything except Enchanting, so `ExtractTradeSkillId` returns the crafted item ID instead. The scanner then wrote `gdb.recipes[197][2996] = { crafters = … }` (Bolt of Linen Cloth's item ID) while BrowserTab / DumpRecipe / every consumer looked up `gdb.recipes[197][2963]` (the spell ID). Same recipe, two different keys, lookup misses, UI shows nothing. A character could scan 60 Tailoring recipes and see none of them. Enchanting always worked because it uses `enchant:` links on Vanilla too; BS only "worked" on TBC for the same reason. **Fix:** a reverse lookup `addon:GetSpellIdForCraftedItem(profId, craftedItemId)` (built lazily per profession from `addon.recipeDB[profId].craftedItemId`). `MergeRecipesIntoGdb` and `MergeCraftersIntoGdb` now resolve item IDs to spell IDs before storing, so future scans + peer broadcasts land on the right key. Plus a one-shot recovery pass `addon:RemapItemKeysToSpellIds` runs at every OnInitialize — idempotent, walks `gdb.recipes`, and moves any item-ID-keyed entry whose value matches a `craftedItemId` in the shipped DB onto the corresponding spell-ID slot (unioning crafter sets when both keys carry data). Existing affected users get their data recovered on the next `/reload`. Location: [TOGProfessionMaster.lua](TOGProfessionMaster.lua) (helper + recovery), [Scanner.lua](Scanner.lua) (`MergeRecipesIntoGdb` + `MergeCraftersIntoGdb`).

- **Minimap button always reset to its default angle (220°) on every `/reload`.** [GUI/MinimapButton.lua](GUI/MinimapButton.lua)'s `SetupMinimapButton` was passing a FRESH local table (`minimapData = { hide = ..., minimapPos = ... }`) to `LibDBIcon:Register` on each load. LibDBIcon does write the new angle back into the table when the user drags the button — but the throwaway local goes out of scope at function end and the updated `minimapPos` never reaches `Ace.db.profile`. On the next reload, SetupMinimapButton reads the original default value and re-pins the button there. **Fix:** give LibDBIcon a sub-table that lives directly on the AceDB profile (`Ace.db.profile.minimap`). LibDBIcon's writes now land in a persisted location, so the button stays where you put it across reloads, character switches, and full client restarts. The legacy `profile.minimapPos` field stays in place as a one-time seed for existing users so nobody loses their last-set position on the first v0.7.1 launch.

---

## [v0.7.0] (2026-05-28) — Flat universal recipe DB + libguildroster visibility gate + slim sync protocol (backwards-breaking)

This is a major architectural rework. The SV schema flattens from per-guild buckets to a single universal recipe table, the sync protocol drops the recipe-metadata leaf entirely (metadata lives in the shipped `addon.recipeDB` now), and crafter visibility is gated against libguildroster so departed members get swept out automatically. **Wire-protocol incompatible with v0.6.x and earlier** — the DeltaSync namespace bumps from `TOGPmv2` to `TOGPmv3`, so old clients and new clients silently don't sync with each other during the transition window.

### Architectural rework

- **Flat universal recipe table.** `TOGPM_GuildDB.global.guilds[guildKey]` is gone. Recipes live in a single `gdb.recipes[profId][recipeId] = { crafters = { [charKey] = guildTag } }` table — one row per recipe, every crafter (across every guild) tagged inline with the guild they were sync'd via. Per-character data (`cooldowns`, `skills`, `specializations`, `factions`, `accountChars`, `altGroups`, `syncTimes`) moves to the top level (charKey is globally unique, no guild scope needed). The recipe-metadata fields (name, icon, reagents, itemLink, recipeLink, isSpell, spellId) that used to be stored per recipe are **no longer in the SV at all** — they're looked up from the shipped `addon.recipeDB` at render time via the new `addon:GetRecipeName / GetRecipeIcon / GetRecipeReagents / GetRecipeCraftedItemId` helpers. Location: [TOGProfessionMaster.lua](TOGProfessionMaster.lua) (new `GUILD_DB_DEFAULTS`, recipe-meta accessors).

- **Guild registry with FNV-1a tags.** Each guild gets registered in `gdb.guildRegistry[tag] = { name, faction, key }` where `tag` is a 6-hex-char FNV-1a-32 hash of the guildKey ("Faction-GuildName"). Deterministic — every client computes the same tag for the same guild, so a crafter sync'd from Alice's client and Bob's client gets the same tag locally. The reserved tag `"personal"` covers guildless own alts (only visible to the owning player). Location: [TOGProfessionMaster.lua](TOGProfessionMaster.lua) (`fnv1aHash6`, `GetGuildTagFor`, `GetCurrentGuildTag`).

- **libguildroster visibility gate at every display site.** New `addon:IsVisibleCrafter(charKey, crafterTag)` rule:
  1. Own alts (tracked via `accountChars`) are ALWAYS visible regardless of guild.
  2. Tag mismatch with the player's current guild → hidden AND queued in `gdb.pendingPurge` for the timed sweep.
  3. Tag matches but charKey isn't in `GuildCache:IsInGuild` → hidden + queued, unless they're an alt of someone in the roster (bank alts of in-guild mains stay visible via `IsAltOfInRosterCharacter`).
  Covers the "left the guild" + "switched guilds" cases symmetrically: when the user is guildless or in a new guild, every old-guild crafter fails rule 2 and gets queued for purge. Location: [TOGProfessionMaster.lua](TOGProfessionMaster.lua).

- **Timed purge sweep on `OnRosterReady + 60s`.** `GuildCache:RegisterCallback("OnRosterReady", ...)` schedules `addon:RunPendingPurge()` 60 seconds after the initial guild roster scan completes. The 60-second buffer covers straggler `GUILD_ROSTER_UPDATE` events on large rosters (>500 members) where the roster trickles in over multiple ticks. The sweep walks `gdb.pendingPurge` and for each charKey strips every reference across `gdb.recipes` (crafter sets), `cooldowns`, `skills`, `specializations`, `factions`, `syncTimes`, and `altGroups` (own entry + sibling references). Empty `guildRegistry` entries get dropped as their last crafter is removed. Net effect: the DB stays trimmed to active guild members forever, no long-term bloat. Location: [TOGProfessionMaster.lua](TOGProfessionMaster.lua) (`RunPendingPurge`), OnEnable wires the callback.

- **Slim sync protocol.** DeltaSync namespace bumps from `TOGPmv2` to `TOGPmv3`. The `recipemeta:<profId>` leaf is REMOVED entirely (every byte of name/icon/reagents/links was redundant since receivers already have it in `addon.recipeDB`). The `crafters:<profId>` leaf shrinks to bare `{[recipeId] = {[charKey] = true}}` — guild tags are derived locally at receive time from the receiver's own current guild context (inbound data always arrives through the receiver's guild channel, so all crafters in the payload share the receiver's tag). Per-recipe payload drops by ~90%; hash-leaf negotiation gets much faster. Cooldowns leaf is unchanged. Location: [Scanner.lua](Scanner.lua) (`BuildLeafPayload`, `OnGuildDataReceived`, `MergeCraftersIntoGdb`).

- **Receiver hides unknown recipeIds silently.** If a sender's addon DB knows a recipe the receiver's (older or different-version) DB doesn't ship, the receive path skips it — no "Unknown #N" placeholder, no SV pollution. The right answer is "ship an addon update" rather than "sync metadata at runtime."

### New Features

- **Dutch (nlNL) locale added.** Same override-only mechanism as Thai and Filipino — `nlNL` isn't a WoW-recognized locale code (Dutch-speaking players play on enGB or enUS clients), so AceLocale never auto-selects it. Dutch users opt in via the Settings "UI Language Override" dropdown which now lists "Nederlands" alongside the existing 14 languages. Best-effort translation; native-speaker review welcome. Location: [Locale/nlNL.lua](Locale/nlNL.lua), [GUI/Settings.lua](GUI/Settings.lua).

- **"Show all recipes" toggle on the Browser tab toolbar.** Default off (today's behavior — only recipes someone in the guild knows appear). When on, every recipe in the shipped `addon.recipeDB` appears in the list with no-crafter rows rendered greyed out, so officers can scan the gaps at a glance.

- **"Show Missing" entry in the View dropdown.** Surfaces ONLY recipes nobody in the guild knows (across the selected profession or all professions). The dropdown entry is hidden until "Show all recipes" is on, so the two controls operate independently — toggle "Show all recipes" to see what's missing inline, switch View to "Show Missing" for a focused gap list. Location: [GUI/BrowserTab.lua](GUI/BrowserTab.lua) (new toolbar checkbox + View dropdown entry, `BuildRecipeList` accepts `{ showAll = bool }` opts + new `missing` view-mode).

### Migration

- **v0.6.x → v0.7.0 is one-shot at first OnInitialize.** `MigrateGuildDb()` runs once when `gdb.schemaVersion` is missing or < 7. Cooldown timers are preserved (merged out of every old `gdb.guilds[guildKey].cooldowns` table into the new flat `gdb.cooldowns`) — those are time-sensitive and re-scanning loses the active expiry. Everything else is wiped: recipes / skills / specializations / hashes / lastScan all rebuild organically on the next trade-skill scan and DeltaSync exchange (cheap now that we're not syncing metadata). The old `gdb.guilds` tree is dropped. `accountChars` and `syncLog` survive in place (already top-level). **There is no rollback** — going back to v0.6.x on a v0.7.0-migrated SV would see an empty DB.

- **Bugs caught during pre-ship testing:**
  1. *UI Language Override was completely broken.* `ApplyLocaleOverride` read `self.db.profile.uiLanguageOverride`, but `self` is `addon` and the AceDB instance lives on the AceAddon object (`addon.lib`), so the read was always `nil`. The function fell through to `"auto"` and never applied the override — so picking Spanish, French, anything in Settings did nothing. **Fix:** read from `addon.lib.db` correctly. This bug pre-dated v0.7.0 (introduced in v0.6.2 when the override was added) and was just never noticed until a user tested with a non-default locale during v0.7.0 pre-ship.
  2. *`addon.PROF_NAMES` froze English strings at module load.* The table was populated with `[171] = L["ProfAlchemy"], ...` at file-load time, before `ApplyLocaleOverride` had a chance to mutate the AceLocale table. So even with the override fixed, profession dropdowns + tooltips would still show English. **Fix:** `PROF_NAMES` is now rebuilt via `addon:RebuildLocalizedTables()` (driven by a `PROF_LOCALE_KEYS` lookup), and `ApplyLocaleOverride` calls the rebuild after mutating the locale table.
  3. *`TAB_DEFS` in `GUI/MainWindow.lua` had the same module-load-time L capture problem.* Tab labels stayed English even when the AceLocale table had been mutated to Spanish. **Fix:** converted to a `getTabDefs()` function that reads `L["..."]` at tab-creation time.
  4. *`schemaVersion` was wrongly in defaults.* AceDB applies defaults BEFORE `OnInitialize` runs, so on the first v0.7.0 launch the default `schemaVersion = 7` got written into the SV before `MigrateGuildDb` could run — the migration's early-return check then tripped, the cooldown-merge walk never executed, and active cooldown timers appeared wiped (the data was still in `gdb.guilds[X].cooldowns` but stranded). **Fix:** removed `schemaVersion` from defaults so it's set ONLY at the end of a successful migration. Migration trigger also widened to re-run when `gdb.guilds` still exists, so SVs that hit the first-launch bug recover their cooldown data on the next reload after patch.
  5. *Thai entry in the UI Language Override dropdown rendered as boxes.* WoW's default fonts only ship glyphs for Blizzard's officially supported locales (Latin / Cyrillic / Han / Hangul) — Thai script falls outside that set, so the native-script label `ไทย` couldn't render. Cyrillic (`Русский`), Korean (`한국어`), and both Chinese variants all work because those scripts have native WoW font support. **Fix:** dropdown label changed to the Latin-script `Thai`. The Thai UI strings themselves are unaffected — selecting `Thai` still applies the `thTH` locale; only the dropdown LABEL changed.
  6. *`accountChars` / `altClaims` collision.* The flat schema collapsed two formerly-separate `accountChars` semantics — the local-only boolean flag set (`{[charKey] = true}` for `IsMyCharacter`) and the per-broadcaster sync'd alt-group array (`{[broadcasterKey] = [...]}`) — into one table. When the same charKey was both an own char AND a broadcaster, the array stomped the boolean for its own slot but other charKeys stayed as `true`, causing a runtime crash in `BuildLeafPayload` when broadcasting `accountchars:<charKey>` for those entries (`#group` on a boolean). **Fix:** split the two semantics into separate fields — `gdb.accountChars[charKey] = true` (local flag, unchanged) and the new `gdb.altClaims[broadcasterKey] = [...]` (sync'd array). All read/write sites (`OnPlayerEnteringWorld`, `BuildLeafPayload`, `OnGuildDataReceived`, `RebuildAltGroups`, `HashManager.ComputeAccountCharsHash`, `HashManager.HasContent`, `HashManager.RebuildOnFirstLoad`) updated to use `altClaims` for the array semantics. The DeltaSync leaf key (`accountchars:`) is unchanged on the wire — only the internal field name moved.

- **`ForEachGuildBucket` + `FindBucketForChar` compatibility shims** — both old helpers now operate over the single global table, so any GUI consumer that hadn't been migrated yet keeps working without code changes. The walk-every-bucket model collapses to a single virtual "bucket" that exposes the same field names (`recipes`, `skills`, `cooldowns`, etc.).

### Cleanup

- **Dead-code removal.** `recipemeta:<profId>` hash + leaf handlers removed from HashManager. `MergeRecipeMetaIntoGdb`, `BackfillBogusRecipeNames`, `BackfillReagentItemIds`, `ScrubObsoleteRecipeNames`, `isObsoleteItemName`, `isBogusName`, `cleanRecipeName`, `GetReagentScraper`, and the namespace-collision/obsolete-name guards in Scanner are now dead — left in place but unreferenced (will be stripped in a follow-up patch once we're confident the new path is stable). `/togpm backfill` is now a no-op that just prints a notice ("metadata lives in addon.recipeDB").

### Multi-version safety

The new schema and visibility gate are entirely additive on every supported client (Vanilla / TBC / Wrath / Cata / MoP). The shipped `addon.recipeDB` already loads per-game-version via the TOC includes, so each client sees the right recipe metadata at render time. The libguildroster gate falls back to "visible" if `GuildCache:IsInGuild` is unavailable (defensive: better to over-display than to hide a real crafter).

---

> Older releases (v0.6.3 and earlier) are archived in [CHANGELOG_ARCHIVE.md](CHANGELOG_ARCHIVE.md).
