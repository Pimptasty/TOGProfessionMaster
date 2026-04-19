# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tool Usage (Always Follow)

**Always use dedicated tools for file operations — never Bash or PowerShell for these tasks:**

- **Read files** → Read tool (not `cat`/`type`/`Get-Content`)
- **Edit files** → Edit or Write tool (not `sed`/`Set-Content`/shell redirects)
- **Search content** → Grep tool (not `grep`/`rg`/`Select-String`)
- **Find files** → Glob tool (not `find`/`Get-ChildItem`/`ls`)

Only use Bash/PowerShell for operations with no dedicated tool equivalent: running scripts, git commands, process management.

## Project Overview

WoW Classic Era addon (Lua 5.1) that tracks guild profession recipes, cooldowns, and reagents across all characters and alts using a peer-to-peer sync system. Supports Vanilla/TBC/Wrath/Cata/MoP via a single codebase with version flags.

**Tech stack:** AceAddon-3.0, AceGUI-3.0, AceDB-3.0, AceComm-3.0, AceCommQueue-1.0, DeltaSync-1.0, VersionCheck-1.0, LibGuildRoster-1.0, LibDataBroker/LibDBIcon, CallbackHandler-1.0

## Development Rules (Always Follow)

- **Use AceGUI widgets** — never raw `CreateFrame()` unless a specific WoW API requires it.
- **Use AceGUI methods** — e.g. `widget:SetFont()` not `widget.label:SetFont()`. Raw fontstring calls leak into recycled widgets.
- **Persistent windows** — never call `Release()` on a window that stays open. Use `ReleaseChildren()` + `Show()` to refresh content, matching the PersonalShopper/Grouper pattern.
- **Tooltip positioning** — always use `addon.Tooltip.Owner(frame)` (defined in Compat.lua). Never call `GameTooltip:SetOwner()` directly.
- **Look at other addons in the workspace first** — PersonalShopper, Grouper, etc. often have the exact pattern needed. Check them before inventing a solution.
- **Fix lint/compile errors automatically** without being asked.

## Tooling

There is no build system, test runner, or package manager. The `.toc` version placeholder `@project-version@` is resolved by the CurseForge/BigWigs packager on release.

- **Linting:** `.luarc.json` configures Lua 5.1 LSP (lua-language-server). Several checks are intentionally disabled (need-check-nil, deprecated, param-type-mismatch). The `libs/` folder is excluded from workspace analysis.
- **Version sync:** `.vscode/tasks.json` runs `wow-version-replication.ps1` on folder open to mirror the addon across WoW installations on this machine.
- **No automated tests.** Verification is done in-game.

## File Load Order (from TOC)

Understanding this matters because Lua has no `require`; each file must only reference symbols defined in earlier files.

1. `libs/DeltaSync-1.0/` (4 files) → vendor libs (LibDataBroker, LibDBIcon, LibGuildRoster) → `Locale/enUS.lua`
2. `TOGProfessionMaster.lua` — AceAddon instance, AceDB schemas, slash commands, utility functions
3. `Compat.lua` — version detection flags (`addon.isVanilla`, `addon.isTBC`, etc.) and API shims
4. `Data/` — static lookup tables (cooldown spell IDs, profession icons)
5. `Scanner.lua` — data engine: scans professions/cooldowns, manages DeltaSync, fires sync callbacks
6. `Modules/` — HashManager, ReagentWatch, SyncLog
7. `GUI/` — MinimapButton, MainWindow, BrowserTab, CooldownsTab, ShoppingListTab, Settings, Tooltip

## Architecture

### Data Storage (AceDB)

Two SavedVariables:

**`TOGPM_GuildDB`** (account-wide, guild-scoped):

```lua
.global.guilds["Faction-GuildName"] = {
  recipes:         [profId][recipeId] = { name, icon, reagents, crafters={charKey→true}, ... }
  skills:          [charKey][profId] = { skillRank, skillMax }
  cooldowns:       [charKey][spellId] = expiresAt  -- absolute server-time UNIX timestamp
  specializations: [charKey][profId] = spellId
  altGroups:       [charKey] = { array of account characters }
  hashes:          [itemKey] = { hash, updatedAt }
}
```

**`TOGPM_Settings`** (per-character UI prefs + lists):

```lua
.char = { shoppingList, reagentWatch, shoppingAlerts, frames }
```

**Key formats:**

- Guild key: `"Faction-GuildName"` — realm intentionally omitted for connected-realm clusters
- Character key: `"Name-NormalizedRealm"` via `GetNormalizedRealmName()`
- Cooldowns stored as absolute timestamps; transmitted as relative seconds-remaining and converted on receipt

### Data Flow

```text
WoW events (TRADE_SKILL_SHOW, BAG_UPDATE_COOLDOWN, etc.)
  → Scanner.lua  (scans, merges into GuildDB, invalidates hashes)
  → HashManager  (maintains Merkle-style leaf hashes for cooldowns + recipe sets)
  → DeltaSync-1.0 (broadcasts payload; P2P hash negotiation avoids redundant transfers)
  → Scanner.OnGuildDataReceived() (merges incoming data, rebuilds hashes)
  → CallbackHandler fires GUILD_DATA_UPDATED / SYNC_SENT / SYNC_RECV
  → GUI modules read GuildDB directly on refresh
```

**Broadcast debounce:** 30s coalescing timer in Scanner; P2P hash-offers sent on login.

### Module Communication

Modules do **not** call each other directly across layers. Communication uses:

1. **AceEvent** — WoW game events (PLAYER_ENTERING_WORLD, TRADE_SKILL_SHOW, etc.)
2. **`addon.callbacks`** (CallbackHandler-1.0) — custom events: `GUILD_DATA_UPDATED`, `SYNC_SENT`, `SYNC_RECV`, `REAGENT_WATCH_UPDATED`
3. **Shared GuildDB** — GUI modules read `gdb` directly; Scanner writes it

### Version Detection (Compat.lua)

`addon.isVanilla` / `addon.isTBC` / `addon.isWrath` / `addon.isCata` / `addon.isMists` are set at load time from `GetBuildInfo()` build number ranges. All version-branching uses these flags directly — no polymorphism pattern.

### DeltaSync-1.0 (embedded P2P library)

Custom P2P sync protocol built on AceComm. Key concepts:

- 7 logical channels: VERSION, DATA, QUERY, RESPONSE, DELTA, OFFER, HANDSHAKE
- Full payload on first contact → delta sync → hash-based leaf negotiation for ongoing sync
- `HashManager` provides the leaf keys (`cooldown:Name-Realm`, `recipes:profId`) and roll-ups (`guild:cooldowns`, `guild:recipes`)
- AceCommQueue-1.0 wraps `SendCommMessage` to prevent CRC errors under high traffic

### GUI Pattern

All tabs follow the same structure:

- `MainWindow.lua` holds the root AceGUI Frame and TabGroup; routes tab switches
- Each tab (`BrowserTab`, `CooldownsTab`, `ShoppingListTab`) implements `:Refresh()` which calls `ReleaseChildren()` then rebuilds content
- **Virtual scrolling** in BrowserTab and CooldownsTab uses a raw frame pool (35 rows) + scroll math — not AceGUI ScrollFrame — for performance with large datasets
- Settings panel is generated by AceConfig-3.0 (appears in ESC → Game Menu → Options)

### Optional Dependencies

- **TOGBankClassic** — when loaded, adds "Bank" stock buttons in the recipe browser
- **GreenWall** — when loaded, cooldown announcements relay to confederate guild channel

## Changelog & Commit Process (Always Follow)

**Before every commit, you MUST:**

1. Ask the user: "What version should I use for this commit? (current latest is vX.X.Y)" — check `CHANGELOG.md` for the current latest.
2. Wait for their answer before writing the changelog entry or running `git commit`.
3. Stage **all** modified and untracked addon files — never cherry-pick only the files you worked on. Run `git status` first and add everything relevant.

**Changelog rules:**

- `CHANGELOG.md` lives at the repo root. Update it on every commit — never skip it.
- Always prepend a new entry. Never edit existing entries.

**Format:**

```markdown
## [v0.0.X] (YYYY-MM-DD) - Short Title

### New Features
- **Feature name** — What it does, why it matters, where to find it. Location: `GUI/File.lua`.

### Bug Fixes
- **Bug description** — Root cause and fix. Location: `Module/File.lua`.

### Improvements
- **Improvement** — What changed and why.

---
```

- Increment patch (Z) for bug fixes/polish; minor (Y) for new user-facing features.
- Today's date is always available in the system context as `currentDate`.
- File locations reference TOGProfessionMaster paths (e.g. `GUI/BrowserTab.lua`), not copy-addon paths.

## Common Slash Commands

```text
/togpm          -- open main window
/togpm sync     -- force immediate broadcast of own data
/togpm debug    -- toggle debug output
/togpm purge    -- purge all guild data
/togpm version  -- show addon version
```
