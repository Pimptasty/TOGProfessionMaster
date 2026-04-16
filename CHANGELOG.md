# TOG Profession Master Changelog

## [v1.1.5] (2026-04-15) - TBC Compatibility Fix

### New Features

- **`[Bank]` button in the Skills List and Bucket List panels** — A `[Bank]` button now appears next to any craftable item that TOGBankClassic currently has in guild-bank stock. In the Skills List panel the button sits to the right of the item name; in the Bucket List panel it sits to the left of the craft `[x]` button. Clicking it opens the TOGBankClassic bank-request dialog pre-filled with the item. The button is hidden when TOGBankClassic is not loaded or when the item is not in stock, so it never clutters rows that don't need it. Location: `views/skills-list-panel.lua`, `views/bucket-list-panel.lua`.

- **Full reagent data for all expansions + multi-spell cooldown grouping** ([CD-016]) — `GetReagents()` and `GetTransmuteReagents()` are now fully populated for TBC, Wrath, Cata, and MoP. Multi-spell groups — Dreamcloth (×5), Inscription Research (×2), JC Daily Cut (×7), Magnificence (×2), BS Ingot (×2) — now collapse into a single row with a click popup listing each individual spell and its reagent, using the same pattern as the Transmute group. Location: `models/cooldown-ids.lua` (`GetCooldownGroups()`, `GetCooldownGroupSet()`), `services/cooldowns-service.lua`, `views/cooldowns-panel.lua`.

### Bug Fixes

- **Movement keys blocked / search box auto-focused on login** — Two related issues prevented normal movement while the addon window was open. (1) The main professions frame called `EnableKeyboard()` without propagating unhandled keys, swallowing W/A/S/D and arrow input. Fixed by adding `SetPropagateKeyboardInput(true)` as the default; the `OnKeyDown` handler now calls `SetPropagateKeyboardInput(false)` only for ESC and ENTER. (2) `SelectTab(1)` was calling `FocusSearch()` on every tab switch and window open, which after a `/reload` stole keyboard focus to the search EditBox and blocked movement keys. Fixed by removing the automatic `FocusSearch()` call from `SelectTab`; the search box still auto-focuses when the player explicitly picks a profession or addon from the dropdowns. Location: `views/professions-view.lua`.

- **`GuildRoster()` crash on TBC+ clients** ([API-006]) — `LibGuildRoster-1.0` called the global `GuildRoster()` unconditionally in `OnPlayerLogin`, the `OnGuildRosterUpdate` retry loop, and the `OnChatMsgSystem` guild-join handler. In TBC Classic (2.5.x) and all later clients this global was removed in favour of `C_GuildInfo.GuildRoster()`. On TBC+ the call during `PLAYER_LOGIN` threw `attempt to call global 'GuildRoster' (a nil value)`, preventing the guild roster from ever populating and breaking all guild-membership checks and online-status detection. Fixed by resolving the correct function at load time: `local RequestGuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster`. All three call sites now use `RequestGuildRoster()`. Classic Era (1.x) is unaffected — it continues to call the original global. Location: `libs/LibGuildRoster-1.0/LibGuildRoster-1.0.lua`.

---

## [v1.1.4] (2026-04-15) - Cooldown Icons, Ready Only Filter & Bug Fixes

### New Features

- **Spell icon in Cooldown column** ([CD-008]) — A 14×14 icon now appears to the left of each cooldown name in the Cooldowns tab. The transmute group row always shows the Alchemy trade icon (`Interface\Icons\Trade_Alchemy`). All other cooldowns use `GetSpellTexture(spellId)`. A new `GetIconItemIds()` method on `cooldown-ids.lua` provides item ID overrides for cooldowns whose spell texture is absent or misleading: Mooncloth (spell 18560) resolves to item 14342, Salt Shaker (item 15846) resolves to its own item icon. Override icons are loaded asynchronously via `ContinueOnItemLoad` when not yet in the client cache. Icon is trimmed with `SetTexCoord(0.08, 0.92, 0.08, 0.92)` to remove the default border. Cooldown text offset shifted right from 192 to 210px to accommodate. Location: `models/cooldown-ids.lua` `GetIconItemIds()`, `views/cooldowns-panel.lua`.

- **"Ready Only" filter toggle** ([CD-009]) — A toggle button in the top-right of the Cooldowns panel header filters the list to show only cooldowns whose timer has expired (i.e. ready to use). The button highlights green when active and reverts to grey when inactive. State is stored on the panel instance and re-applied on every `Refresh()`. Button label and tooltip are localised in all 10 supported languages (`CooldownsFilterReadyOnly`, `CooldownsFilterReadyOnlyTooltip`). Location: `views/cooldowns-panel.lua` `Create()` / `Refresh()`, `models/locales.lua`.

- **Column header sort** ([CD-011]) — Clicking a column header (Character, Cooldown, Time Left) sorts the Cooldowns panel by that column ascending; clicking again toggles to descending. The active column shows a `Interface\Calendar\MoreArrow` indicator (up = asc, down = desc). Sort state (`cdSortCol`, `cdSortDir`) is persisted in `TOGPM_CharacterSettings` so it survives UI reloads. When a column sort is active it fully overrides the default ready-first sort from `GetAllCooldowns()`. Cooldown column sorts by display name (transmute group sorts as "Transmute"); character and cooldown sorts are case-insensitive. Location: `views/cooldowns-panel.lua` `Create()` / `Refresh()`.

- **Mail ready cooldowns only setting** ([CD-017]) — A new "Mail ready cooldowns only" checkbox has been added under a "Cooldowns" section in ESC > Options > Addons > TOG Profession Master. When unchecked (default), the mail icon appears on every cooldown row with a known reagent. When checked, the icon is hidden for any cooldown that isn't yet ready (`remaining > 0`), so mail can only be sent for cooldowns that are up. Setting is stored in `TOGPM_Settings.mailReadyOnly`. Location: `views/settings-view.lua`, `views/cooldowns-panel.lua`, `models/locales.lua`.

- **Cooldown supply mail** ([CD-014]) — A mail icon button (envelope icon, matching TOGBankClassic's style) now appears to the right of the `[Bank]` button on each Cooldowns panel row that has a known reagent. Clicking it opens a pre-composed mail to the cooldown owner: reagents are attached from your bags using a greedy fulfillment algorithm that handles multi-stack attachment and split-stack prompts (matching the TOGBankClassic fulfillment logic). If a stack needs to be split first, a confirmation popup appears — click Split, then click the mail icon again to attach the split stack. The mail subject and body are pre-filled. The same mail icon is available per-spell in the transmute click popup. Requires a mailbox to be open. Location: `views/cooldowns-panel.lua` `CdMail_PrepareSupplyMail()`, `CdMail_CountItemInBags()`, `CdMail_CalculateFulfillmentPlan()`, `StaticPopupDialogs["TOGPM_SPLIT_STACK"]`.

### Bug Fixes

- **`[Bank]` button not appearing until tab away** — The bank button show/hide logic was only evaluated in the synchronous `GetItemInfo` path. When the reagent name wasn't yet cached, `ContinueOnItemLoad` set the text but never called the bank button logic, so the button stayed hidden until the next full `Refresh()`. Fixed by extracting `ApplyBankButton(itemId)` as a local helper and calling it from inside the `ContinueOnItemLoad` callback as well as the synchronous path. Location: `views/cooldowns-panel.lua` `Refresh()`.

- **Transmute popup mail icon invisible** — The per-spell mail icon button inside the transmute click popup was still using `Interface\GossipFrame\MailGossipIcon` (invisible on Classic Era). Fixed to `Interface\Icons\INV_Letter_15`, matching all other mail buttons. Location: `views/cooldowns-panel.lua` `ShowTransmutePopup()`.

- **Mail icon invisible / bag scan Lua error** — The mail button was using `Interface\GossipFrame\MailGossipIcon` which renders as an invisible texture on Classic Era. Replaced with `Interface\Icons\INV_Letter_15`, matching TOGBankClassic's Fulfill button icon. The bag-scanning helpers (`CdMail_CountItemInBags`, the split-stack popup) were calling the removed Classic Era global `GetContainerNumSlots` (and related globals) instead of `C_Container.*`, causing a Lua error on click. All bag API calls now use `C_Container` exclusively, matching TOGBankClassic. Location: `views/cooldowns-panel.lua`.

- **Ready Only filter showing wrong empty-state text** — When the Ready Only filter was active and no cooldowns were ready, the panel displayed the generic "no data" message that instructs the player to open profession windows. Added a distinct `CooldownsNoReady` locale key ("No cooldowns are currently ready.") shown only when the filter is the reason for an empty list. Location: `views/cooldowns-panel.lua` `Refresh()`, `models/locales.lua`.

---

## [v1.1.3] (2026-04-15) - Transmute Redesign, Reagent Display & TOGBank Integration

### New Features

- **Spell tooltip on cooldown name hover** — Hovering the cooldown name cell in the Cooldowns tab now shows the native WoW spell tooltip (profession name, description, cooldown duration) via `GameTooltip:SetHyperlink`. Works for all spell-based cooldowns. Location: `views/cooldowns-panel.lua`.

- **Per-spell transmute tracking** — Transmutes are now stored individually per spell ID (e.g. Fire→Earth, Air→Water) rather than all under a single canonical ID. This fixes the root cause of transmute entries never appearing for players who don't know the specific water-to-air transmute (spell 17562) used as the old canonical key. `ScanTransmuteCooldown` now finds the active expiry once by scanning all transmute IDs, then seeds an entry under every transmute spell the player knows. `CheckMessage` accumulates transmute IDs permanently so guildmates' known transmutes are retained across sessions. Location: `models/cooldown-ids.lua`, `services/cooldowns-service.lua`.

- **"Transmute" grouped row with click popup** — All of a player's transmutes are collapsed into a single "Transmute" row in the Cooldowns panel. Clicking the row opens a floating popup listing every transmute that player knows (by spell name), each with its own spell tooltip on hover. The popup anchors directly to the right of the "Transmute" text using `GetStringWidth()` and dismisses when clicking outside. Location: `views/cooldowns-panel.lua` `ShowTransmutePopup()`.

- **Reagent column in Cooldowns panel** ([CD-003]) — The primary reagent for each cooldown is now shown right-aligned in the cooldown row (e.g. "Felcloth" for Mooncloth, "Deeprock Salt" for Salt Shaker, the primary input for each transmute). Reagent names are loaded lazily via `ContinueOnItemLoad` when not yet in the client cache. Hovering a reagent name shows the native item tooltip. Shift-clicking inserts an item link into chat. `GetReagents()` and `GetTransmuteReagents()` added to `models/cooldown-ids.lua` (Vanilla only; CD-016 tracks remaining expansion reagent IDs). Location: `models/cooldown-ids.lua`, `views/cooldowns-panel.lua`.

- **TOGBank `[Bank]` button & reagent tooltips** ([CD-004]) — When TOGBankClassic has the cooldown's primary reagent in stock, a `[Bank]` button appears next to the reagent name. Clicking it opens the TOGBank bank request dialog pre-filled for that item. The transmute popup is extended with a reagent column: each row shows the transmute's primary reagent on the right with an item tooltip on hover; clicking with TOGBank stock opens the bank request dialog. `reagentHover` frame is narrowed when the `[Bank]` button is visible to prevent overlap. Location: `views/cooldowns-panel.lua`.

### Improvements

- **"Remaining" column renamed to "Time Left"** ([CD-005]) — The third column header in the Cooldowns panel is now labelled "Time Left" across all 10 supported languages (EN, DE, RU, ES, FR, IT, KO, PT, zhCN, zhTW). Hovering the column header now shows a tooltip explaining what the column displays. Location: `models/locales.lua`, `views/cooldowns-panel.lua`.

---

## [v1.1.2] (2026-04-15) - Cooldown Debug Improvements

### Improvements

- **Improved `/pm debug cooldowns` output** — The debug command now prints every tracked spell ID (both transmute and other profession cooldowns) with its `IsSpellKnown` status, raw `GetSpellCooldown` values, and computed remaining — regardless of whether the cooldown is currently active. Previously it only printed IDs that were actively on cooldown, making it impossible to diagnose why a cooldown was never seeded as "Ready". Output is now sectioned (`--- Transmute IDs ---` / `--- Other Profession CDs ---` / `--- Stored for <player> ---`) and always shows `(no stored entries)` when the stored table is empty. This makes it possible to identify missing spell IDs in the tracked list and failed seeding in a single run of the command. Location: `services/commands-service.lua`.

---

## [v1.1.1] (2026-04-15) - Cooldown Fixes & Debug Tools

### New Features

- **Right-click to whisper from Cooldowns tab** — Right-clicking any row in the Cooldowns tab now shows a whisper context menu pre-filled with `/w CharacterName`, matching the existing behaviour on the skills list panel. Online/offline colour coding applies. Works on Classic Era (legacy `UIDropDownMenu` API) and TBC Anniversary / Cata / Mists (`Menu.CreateContextMenu`). Location: `views/cooldowns-panel.lua`.

- **`/pm debug cooldowns` command** — New debug subcommand that prints raw `GetSpellCooldown` values (`start`, `duration`, `remaining`) for all tracked transmute and spell cooldown IDs, plus the stored `expiresAt` and computed remaining for every entry in `TOGPM_Cooldowns` for the current character. Use this to diagnose incorrect cooldown times and share the output when reporting bugs.

### Bug Fixes

- **Version comparison crash** ([VER-002]) — The BigWigsMods packager sets `@project-version@` to the full git tag name (e.g. `TOGProfessionMaster-v1.1.0`), not just `1.1.0`. Splitting that string on `.` produces `"TOGProfessionMaster-v1"` as the first token, which `tonumber()` cannot parse, causing an `attempt to compare number with nil` crash whenever a guildmate's version broadcast was received. Fixed by replacing the raw `string.gmatch`/`tonumber` loops in `OwnIsLower()` and `OwnIsHigher()` with a new `ParseVersionParts()` helper that strips any non-numeric prefix before splitting, and falls back to `{0,0,0}` for completely unparseable strings (e.g. unpackaged dev builds). Location: `services/version-service.lua`.

- **Wildly incorrect cooldown remaining times** ([DATA-004]) — Some clients reported absurdly large remaining times (e.g. "50d 23h" for a Mooncloth or Transmute with ~30h left). Root cause not yet confirmed — debug output from testers needed. Mitigations applied: computed `remaining` values beyond 30 days are discarded at the scan site for both transmute and regular spell cooldowns, and for values received via guild broadcast; any already-stored entry more than 30 days in the future is reset to "Ready" on the next scan if no valid active cooldown is returned by `GetSpellCooldown`. Location: `services/cooldowns-service.lua`.

---

## [v1.1.0] (2026-04-14) - Guild Cooldown Tracker

### New Features

- **Guild Profession Cooldown Tracker** — New **Cooldowns** tab in the main profession browser showing every guild member's tracked profession cooldown alongside their character name and time remaining (or "Ready"). Cooldown data is broadcast to guildmates via addon messaging whenever a trade skill window is opened or a relevant item cooldown fires, and is received and stored automatically for all online addon users.

  - **Tracked cooldowns:** Tailoring (Mooncloth, Shadoweave, Spellweave, Ebonweave, Dreamcloth variants), Alchemy transmutes (all version-appropriate spell IDs, stored under a single canonical entry), Leatherworking Salt Shaker (item-based cooldown via `C_Container.GetItemCooldown`), and all other spell-based profession cooldowns.
  - **"Ready" seeding:** Entries are seeded as "Ready" immediately on login if the character knows the spell (`IsSpellKnown`) or owns the item (`GetItemCount`), so every tracked crafter appears in the panel rather than only those who have actively used the cooldown since installing the addon.
  - **Real-time detection:** `BAG_UPDATE_COOLDOWN` fires whenever an item cooldown starts or expires — Salt Shaker is detected without the player needing to open the Leatherworking window. Spell-based cooldowns are scanned on `TRADE_SKILL_SHOW`, `TRADE_SKILL_UPDATE`, `CRAFT_SHOW`, and `CRAFT_UPDATE`.
  - **Login scan:** A 2-second deferred scan runs on `PLAYER_LOGIN` so local cooldown data is populated immediately on each login.
  - **Cooldown name resolution:** `GetSpellInfo` is tried first; item-based cooldowns fall back to `GetItemInfo` so the panel shows "Salt Shaker" rather than "Spell 15846".

### Improvements

- **Custom minimap button icon** — The minimap launcher button now uses the addon's own `TOGPM_MMB_Icon.tga` instead of the placeholder WoW book icon (`Inv_misc_book_05`). All 5 TOC files updated to reference the same asset for the in-game addon list icon. `pm.png` removed.

---

## [v1.0.1] (2026-04-14) - TOGBank Integration & Settings Panel Rework

### Improvements

- **Item tooltip on hover in Missing Reagents window** — Hovering a reagent row in the Missing Reagents popup now shows the full item tooltip (quality, stats, and TOGBank banker stock). `OnLeave` guards with `GetOwner()` to avoid clobbering the Bank request button tooltip. Location: `views/missing-reagents-view.lua`.

- **TOGBank banker stock in skills list tooltips** — The skills list panel now shows TOGBank banker inventory inline when hovering a recipe, matching the existing behaviour in the bucket list panel. `SetHyperlink(skillLink)` fires `OnTooltipSetSpell`, not `OnTooltipSetItem`, so TOGBankClassic's hook never ran; fixed by appending banker lines manually via `AppendTOGBankLines()` and calling `tooltip:Show()` after. Item IDs absent from synced guild recipe data are recovered by parsing the raw `skill.itemLink` string. Location: `services/tooltip-service.lua`.

- **Settings panel Tools section** — ESC > Options > Addons > "TOG Profession Master" now includes a full Tools section below the Alerts checkboxes:
  - **Show Minimap Button** — Checkbox to show or hide the minimap launcher button (replaces needing `/pm minimap`). Synced from `TOGPM_Settings` when the panel opens; persists immediately on toggle.
  - **Purge All Data** — Button with confirmation dialog; wipes profession data for every character. Cannot be undone.
  - **Purge My Data** — Button with confirmation dialog; removes only the current character's profession data.
  - **Open Sync Log** — Opens the sync activity log directly from settings.
  - **Tooltips on all controls** — Every checkbox and button on the settings panel now shows a descriptive tooltip on hover.

- **Whisper crafter from skills list** — Right-clicking a recipe row in the skills list now shows a context menu listing all visible crafters for that recipe. Online crafters (white) appear first, offline (grey) below, both sorted alphabetically. Clicking a name opens a chat input pre-filled with `/w CharacterName` ready to type. Supports both the legacy `UIDropDownMenu` API (Classic Era) and the newer `Menu.CreateContextMenu` API (TBC Anniversary / Cata / Mists). Location: `views/skills-list-panel.lua`.

- **GreenWall-aware guild chat announce** — The "Promote in Guild Chat" button now also relays the announcement to GreenWall's confederate guild channel when the GreenWall addon is loaded and connected. Checks `GreenWallAPI` and `gw.config.channel.guild:is_connected()` before calling `send(GW_MTYPE_CHAT, message)` — no settings toggle needed, active only when GreenWall is present. Location: `views/professions-view.lua`.

### Bug Fixes

- **`StaticPopupDialogs` button labels** — Purge All Data and Purge My Data confirmation dialogs were using the `YES` / `NO` WoW globals as button labels, which are `nil` in Classic Era, leaving the buttons blank. Fixed to use string literals `"Yes"` / `"No"`. Location: `views/settings-view.lua`.

---

## [v1.0.0] (2026-04-14) - TOG Fork: Rename, Guild Roster Overhaul & Connected-Realm Support

### New Features

- **TOG fork established** — Source forked from ProfessionMaster by Kurki. All internal identifiers, SavedVariables, and display strings updated for The Old Gods guild distribution. Addon is now distributed as `TOGProfessionMaster` on CurseForge (project ID 1513588).

- **LibGuildRoster-1.0** — New embedded library replacing direct `GetGuildRosterInfo` iteration throughout the addon. LibStub + CallbackHandler-1.0 backed. Guild roster is wiped and rebuilt on `GUILD_ROSTER_UPDATE` with real-time online/offline transitions via `CHAT_MSG_SYSTEM`. Supports up to 5 login retries to handle the race between addon load and the first roster update event.

- **Connected-realm aware player matching** — `LibGuildRoster-1.0` uses `GetNormalizedRealmName()` for all realm comparisons, correctly handling connected-realm clusters where guild members may appear on any of several linked realms. `NormalizeName()` includes full defensive guards (nil check, trim, lowercase) matching the pattern established in TOGBankClassic.

- **`IsGuildMember()` and `IsGuildMemberOnline()`** — New methods on `player-service.lua` wrapping the library. All guild membership checks in the codebase now go through these methods rather than iterating the roster directly.

### Internal

- **SavedVariables renamed** — All `PM_*` SavedVariables renamed to `TOGPM_*` (e.g. `PM_Professions` → `TOGPM_Professions`). Legacy unprefixed names (`Professions`, `OwnProfessions`, `SyncTimes`, `PMSettings`, `Logs`, `CharacterSets`, `BucketList`, `ReagentWatchList`, `Convert`, `PlayerFactions`, `Frames`, `CharacterSettings`) removed from all TOC `SavedVariables` declarations.

- **Global addon reference renamed** — `_G.professionMaster` → `_G.togProfessionMaster` throughout all service, view, model, message, and skills files (~44 files).

- **Slash command renamed** — `SLASH_ProfessionMaster1` → `SLASH_TOGProfessionMaster1`, `SlashCmdList["ProfessionMaster"]` → `SlashCmdList["TOGProfessionMaster"]`.

- **LibDataBroker / LibDBIcon keys renamed** — `NewDataObject("ProfessionMaster", ...)`, `libDbIcon:Hide("ProfessionMaster")`, and `libDbIcon:Register("ProfessionMaster", ...)` updated to `"TOGProfessionMaster"`.

- **Tooltip guard key renamed** — `_self["ProfessionMaster"]` guard in `tooltip-service.lua` renamed to `_self["TOGProfessionMaster"]` to avoid key collisions with any remaining ProfessionMaster installation.

- **TOC metadata updated** — All 5 TOC files (`_Vanilla`, `_TBC`, `_Wrath`, `_Cata`, `_Mists`): Title updated to `TOG Profession Master`, `IconTexture` path updated, `SavedVariables` updated to `TOGPM_*`, legacy unprefixed names stripped, file entry updated to `TOGProfessionMaster.lua`, version set to `@project-version@`, authors set to `Kurki, Pimptasty`, CurseForge project ID set to `1513588`.

- **PM_Guildmates SavedVariable removed** — Removed from all Lua files and TOC declarations as part of the LibGuildRoster migration.
