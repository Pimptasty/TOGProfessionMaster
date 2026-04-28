# TOG Profession Master — Feature Specification

**Status:** Clean-room build from scratch  
**Tech stack:** Ace3 · AceCommQueue-1.0 · DeltaSync-1.0 · GuildCache-1.0 · VersionCheck-1.0 · LibDataBroker-1.1 · LibDBIcon-1.0  
**UI:** AceGUI-3.0 + AceConfig-3.0 throughout (no manual frame XML)

---

## 1. Addon Bootstrap

- `AceAddon-3.0` as the base — `TOGProfessionMaster:OnInitialize()` and `OnEnable()`
- `AceDB-3.0` for all SavedVariables — one account-wide DB (`TOGPM_DB`), one per-character DB (`TOGPM_CharDB`)
- `AceConsole-3.0` for slash command registration (`/pm`)
- `AceEvent-3.0` for all WoW event subscriptions
- `AceTimer-3.0` for any deferred or repeating work
- `VersionCheck-1.0` embedded — registers the addon on `OnInitialize`, gates all sync on compatible peer versions

---

## 2. Version Detection

- Detect `isVanilla / isTBC / isWrath / isCata / isMoP` from `GetBuildInfo()` at startup using anchored patterns (`^1%.`, `^2%.`, etc.)
- Store detected version on the addon global for all other modules to read
- Skills data sets, API compat shims, and UI adjustments all branch on this flag

---

## 3. Guild Roster (GuildCache-1.0)

- Use `GuildCache-1.0` (bundled inside the standalone DeltaSync addon, MINOR ≥ 2) as the sole source of truth for guild membership
- `IsInGuild(name)` and `IsPlayerOnline(name)` used by all other modules — no raw `GetGuildRosterInfo` calls anywhere else
- `GetNormalizedRealmName()` used for all realm comparisons (connected-realm safe)
- Roster rebuilt on `GUILD_ROSTER_UPDATE`; online/offline transitions tracked via `CHAT_MSG_SYSTEM`
- CallbackHandler-1.0 transition events: `OnMemberOnline`, `OnMemberOffline`, `OnMemberJoined`, `OnMemberLeft`, `OnRosterReady`, `OnRosterUpdated`

---

## 4. Communication Layer

### 4.1 Transport

- **DeltaSync-1.0** is the comm backend — handles version broadcast, full data sync, delta sync, and P2P sessions
- **AceCommQueue-1.0** wraps all `SendCommMessage` calls to prevent CRC errors from chunk interleaving
- TOGPM registers a single DeltaSync instance keyed to `"TOGPM"` on `OnInitialize`

### 4.2 Data that syncs

- Own profession list (profession ID, skill level, all known recipe IDs, specialization)
- Own profession cooldown states (spell ID → expiry timestamp)
- Character identity (name, realm, faction)

### 4.3 Sync triggers

- `PLAYER_ENTERING_WORLD` — initial broadcast
- `TRADE_SKILL_SHOW` / `TRADE_SKILL_UPDATE` — rescan and delta-sync professions
- `BAG_UPDATE_COOLDOWN` — rescan and delta-sync cooldowns
- On receiving a version broadcast from a peer — initiate sync if their data is newer than our stored copy
- Manual `/pm sync` command

### 4.4 GreenWall support (optional dep)

- On guild announce, also relay to GreenWall confederate channel if `GreenWall` is loaded

---

## 5. Profession Data

### 5.1 Scanning own professions

- `GetProfessions()` → iterate each slot → `GetProfessionInfo()` → `GetNumTradeSkills()` / `GetTradeSkillInfo()` for recipes
- Specialization detection from `specialization-spells` data table (keyed per expansion)
- All data stored in `AceDB` account-wide table, keyed by `characterKey` (`Name-Realm`)

### 5.2 Skills data tables

- Static Lua tables per expansion: `vanilla-skills`, `bcc-skills`, `wrath-skills`, `cata-skills`, `mop-skills`
- Each entry: `{ spellId, itemId, reagents = { {itemId, count}, ... } }`
- Loaded on demand based on version flag — only the relevant expansion's table is used

### 5.3 Profession icon map

- Static table mapping profession ID → icon texture path
- Used for UI display; missing entries fall back to a generic trade icon (never crashes)

### 5.4 BOP item list

- Static table of item IDs that are bind-on-pickup — used to suppress irrelevant tooltip entries

---

## 6. Cooldown Tracker

- Static `cooldown-ids` table: spell ID → `{ name, reagentItemId, group }` per expansion
- Groups: `"transmute"`, `"cloth"`, `"leatherworking"`, `"inscription"`, `"jewelcrafting"`, `"blacksmithing"`
- **Scanning:** `GetSpellCooldown(spellId)` — compute `expiresAt = GetTime() + remaining`; discard values > 30 days as bogus
- **Seeding:** On login, any known spell with no stored entry is seeded as `expiresAt = 0` (Ready)
- **Storage:** `TOGPM_CharDB.cooldowns[spellId] = { expiresAt, name }`
- Synced to guild via DeltaSync delta channel on change

---

## 7. Guild Profession Browser (Main Window)

Built with `AceGUI-3.0`:

- `AceGUI:Create("Frame")` as the root window — resizable, movable, position saved in `AceDB`
- Left panel: scrollable list of professions (one row per profession found across all guild data)
- Right panel: scrollable list of characters who have the selected profession, with skill level
- Recipe sub-list: selecting a character expands their known recipes for that profession
- Search box: filters recipe rows by item name (client-side, no server calls)
- Addon filter dropdown: toggle between "Guild" and "My Characters" views
- Profession dropdown: alternatively select profession from a dropdown instead of clicking the list

---

## 8. Cooldowns Panel (tab inside main window)

- Tab on the main window: `AceGUI:Create("TabGroup")`
- Columns: Character · Cooldown · Reagent · Time Left
- Rows sorted by column header click (ascending/descending toggle, sort state persisted in `AceDB`)
- "Ready Only" filter button — hides rows where `expiresAt > GetTime()`
- Grouped rows for multi-spell cooldowns (Transmute, Dreamcloth variants, etc.) — click to expand popup listing individual spells
- Spell tooltip on cooldown name hover (`GameTooltip:SetSpellByID`)
- Item tooltip on reagent name hover (`GameTooltip:SetItemByID`)
- Right-click row → whisper context menu (pre-fills `/w CharacterName`)
- **[Bank] button** per row — visible when `TOGBankClassic` is loaded and has the reagent in stock; opens bank request dialog
- **[Mail] button** per row — visible when at a mailbox; opens pre-composed supply mail to cooldown owner with reagent attached from bags
- **TODO: Sort indicator on active column header** — show a sort arrow (▲/▼) next to the active sort column label. Attempted via `|T|t` inline texture and Unicode characters; both failed in Classic Era. Needs a working WoW Classic–compatible approach (e.g. a Blizzard sort-arrow texture that actually exists in the Classic client, or a FontString texture approach).

---

## 9. Bucket List & Missing Reagents

### 9.1 Bucket List

- Stored in `AceDB` per-character: `{ spellId → { quantity, note } }`
- Add from recipe row via "+" button in the main browser
- Displayed in a separate `AceGUI` panel (accessible from main window tab or `/pm reagents`)
- Remove via "[x]" button per row
- **[Bank] button** per row — same TOGBankClassic integration as cooldowns panel

### 9.2 Missing Reagents

- Aggregate all reagents needed across bucket list entries × quantity
- Subtract current bag contents (scanned via `GetContainerItemInfo` with Classic/Dragonflight compat shim)
- Display shortfall per reagent — item name, quantity needed, quantity in bags
- Item tooltip on hover (`GameTooltip:SetItemByID`)
- Shift-click reagent name → insert item link into chat
- **[Bank] button** per row — TOGBankClassic integration

### 9.3 Reagent Watch

- Separate list of watched item IDs — tracked in `AceDB`
- Shows current bag count per watched item
- Updates on `BAG_UPDATE`

### 9.4 Bucket List Alerts

- `AceTimer` polling: check bag counts vs bucket list requirements on `BAG_UPDATE`
- Fire a chat notification when all reagents for a queued craft are available

---

## 10. Item Tooltips

- Hook `GameTooltip:SetItem`, `GameTooltip:SetHyperlink` via `AceHook-3.0`
- Extract item ID from the link; look up in guild profession data
- Append crafter rows: `Name (Profession, Skill X)` — online crafters first (white), offline (grey)
- Guard with BOP list — skip BOP items
- `professionIcon` nil-safe: always check icon exists before concatenating

---

## 11. Minimap Button

- `LibDataBroker-1.1` data object + `LibDBIcon-1.0` for the minimap button
- Left-click: open profession browser
- Right-click: open missing reagents
- Shift+Left-click: open settings
- Shift+Right-click: hide minimap button
- Visibility state persisted in `AceDB`

---

## 12. Settings Panel

- `AceConfig-3.0` option table registered with `AceConfigRegistry`
- `AceConfigDialog-3.0` renders it under ESC → Options → Addons → TOG Profession Master
- Settings:
  - Minimap button visibility toggle
  - Mail ready-cooldowns-only toggle
  - Debug logging toggle
  - **Purge All Data** button (with confirmation dialog)
  - **Purge My Data** button (with confirmation dialog)
  - Link to Sync Log

---

## 13. Slash Commands

All registered via `AceConsole-3.0`:

| Command | Action |
| --- | --- |
| `/pm` | Open profession browser |
| `/pm reagents` | Open missing reagents |
| `/pm minimap` | Show minimap button |
| `/pm purge` | Open purge dialog |
| `/pm sync` | Force a full re-sync with guild |
| `/pm debug` | Toggle debug output |
| `/pm help` | Print command list |

---

## 14. Data Management

- **Purge All:** wipe all guild profession data, own professions, sync times, cooldowns, bucket list, reagent watch, specializations, faction cache, character sets — everything
- **Purge My Data:** remove only entries for the current `characterKey` from all tables
- Both show `StaticPopupDialogs` confirmation (defined once at module scope, not in click handlers)
- Purge resets only the specific sync-time entry for the purged character, not the entire sync-time table

---

## 15. Sync Log

- Ring buffer of recent sync events stored in `AceDB` (capped at 200 entries)
- Entries: timestamp, event type, peer name, bytes
- Accessible from settings panel and via an AceGUI scrollable list view

---

## 16. Locale Support

- `AceLocale-3.0` for all display strings
- English (`enUS`) is the authoritative source and serves as fallback for any missing key in other locales
- Locale files in `locale/` directory, one per language code

---

## 17. Multi-Version Support

All Classic versions share one codebase; version-specific branches are isolated to:

| Area | Handling |
| --- | --- |
| API compat | Version flag checked once at startup; compat shims defined in `compat.lua` |
| `GuildRoster()` vs `C_GuildInfo.GuildRoster()` | GuildCache-1.0 (in DeltaSync) already handles this |
| `C_Container` vs legacy bag APIs | Shim in inventory module |
| `Settings.*` vs `InterfaceOptions_AddCategory` | AceConfigDialog handles this automatically |
| `C_AddOns.IsAddOnLoaded` vs `IsAddOnLoaded` | Shim in compat.lua |
| Skills data | Per-expansion static table loaded by version flag |
| Cooldown IDs | Per-expansion static table loaded by version flag |

Supported interface versions: Vanilla (1.x) · TBC (2.x) · Wrath (3.x) · Cata (4.x) · MoP (5.x)

---

## Backlog / Ideas

Quick notes — not yet designed or scheduled.

- **Professions tab tooltip — TOGBank stock line:** When hovering a recipe row, append a "In bank: N" line to the custom tooltip if `TOGBankClassic_Guild` has stock of the crafted item.

- **Equipment slot filter in Guild Profession Browser** — A filter dropdown or button bar in the browser that lets the player pick an equipment slot (Head, Shoulder, Back, Chest, etc.) to show all craftable items of that type across *all* professions at once. For example selecting "Back" would surface cloaks made by Leatherworking, Tailoring, and Blacksmithing in a single merged list, each row labelled with the crafting profession and the guild member who knows it. Useful when a player knows what slot they need but not which profession covers it. Requires item slot data added to the per-expansion skills tables (currently only `spellId`, `itemId`, and `reagents` are stored). Requested by user April 2026.
