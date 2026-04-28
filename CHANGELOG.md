# TOG Profession Master Changelog

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
