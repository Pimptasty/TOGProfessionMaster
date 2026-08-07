# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tool Usage (Always Follow)

**Always use dedicated tools for file operations — never Bash or PowerShell for these tasks:**

- **Read files** → Read tool (not `cat`/`type`/`Get-Content`)
- **Edit files** → Edit or Write tool (not `sed`/`Set-Content`/shell redirects)
- **Search content** → Grep tool (not `grep`/`rg`/`Select-String`)
- **Find files** → Glob tool (not `find`/`Get-ChildItem`/`ls`)

Only use Bash/PowerShell for operations with no dedicated tool equivalent: running scripts, git commands, process management.

## Peer review and harness contracts (Always Follow)

Two standing append-only conversation files. **Read both at the start of any session that touches
this addon's code or tests** — a session watcher only catches writes made while a session is already
running, so this pointer is the only thing that fires unconditionally.

| File | Raised by | Answered by | What it is |
| --- | --- | --- | --- |
| [docs/AUDIT.md](docs/AUDIT.md) | a **review session** | **us** | Peer-review findings against this addon. Each carries a `file:line` and a concrete failure scenario. |
| [Tests/HARNESS_CONTRACT.md](Tests/HARNESS_CONTRACT.md) | **us** | the **harness** | Things `Tests/wowapi` is missing. Mirrored into `WoWAPITesting/docs/contracts/TOGProfessionMaster.md` during a harness session. |

- **Both are APPEND-ONLY in both directions.** Never edit, re-title, re-order or move what the other
  side wrote. Answer underneath with an `> **Addon response — YYYY-MM-DD — FIXED | DISPUTED | WON'T
  FIX | NOT A DEFECT | DEFERRED.**` block.
- **A fixed finding is answered in place and stays where it is.** Do not add a `Fixed` section and
  move it there — the failure scenario's value is sitting next to the code it describes. Flip its
  row in the Status table instead; that table is the only place state is tracked.
- **Never overwrite `docs/AUDIT.md` with the harness's `AUDIT_TEMPLATE.md`.** A review session can
  write findings before we adopt, and the reviewer's session is gone — nothing else holds a copy.
- **Never edit `Tests/wowapi`.** It is a submodule checkout; the next pull discards edits. A gap in
  the harness goes in `Tests/HARNESS_CONTRACT.md`, with a reference implementation staged locally so
  the suite still runs.

## Project Overview

WoW Classic Era addon (Lua 5.1) that tracks guild profession recipes, cooldowns, and reagents across all characters and alts using a peer-to-peer sync system. Supports Vanilla/TBC/Wrath/Cata/MoP via a single codebase with version flags.

**Tech stack:** AceAddon-3.0, AceGUI-3.0, AceDB-3.0, AceComm-3.0, AceCommQueue-1.0, DeltaSync-1.0, LibGuildRoster-1.0, VersionCheck-1.0, LibDataBroker/LibDBIcon, CallbackHandler-1.0

## Development Rules (Always Follow)

- **Use AceGUI widgets** — never raw `CreateFrame()` unless a specific WoW API requires it.
- **Use AceGUI methods** — e.g. `widget:SetFont()` not `widget.label:SetFont()`. Raw fontstring calls leak into recycled widgets.
- **Persistent windows** — never call `Release()` on a window that stays open. Use `ReleaseChildren()` + `Show()` to refresh content, matching the PersonalShopper/Grouper pattern.
- **Tooltip positioning** — always use `addon.Tooltip.Owner(frame)` (defined in Compat.lua). Never call `GameTooltip:SetOwner()` directly.
- **Column header style** — every column header (and prominent count/status label above a list) must use `AceGUI:Create("InteractiveLabel")` with the brand color: `widget:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. labelText .. "|r")`. Never hard-code `|cffffd100` or any other yellow — the brand color is the single source of truth and any future palette change should propagate everywhere automatically. Reference implementation: [GUI/CooldownsTab.lua:DrawHeaders](GUI/CooldownsTab.lua).
- **Never override class-level methods on AceGUI widgets** (e.g. `widget.LayoutFinished = ...`). AceGUI's release pool keeps non-event method overrides alive on the widget table; when the pooled widget is later recycled into another tab, your override survives and breaks the new owner's layout. SimpleGroup's class-level `LayoutFinished` auto-sizes the widget to fit its content (AceGUIContainer-SimpleGroup.lua:25) — replacing it will manifest as "huge gap" or "wrong size" bugs in the OTHER tab that recycled the widget. Only set callbacks via `widget:SetCallback("OnRelease"/"OnEnter"/etc.)` (those go in `widget.events` and AceGUI clears them on release). For per-tab layout hooks, use `container.LayoutFinished` on the TabGroup container (which is not pool-recycled across tabs).
- **Never call `widget.frame:SetScript(...)` directly on AceGUI widgets** — same pool-recycling hazard as above, but for raw frame scripts. AceGUI clears `widget.events` (the SetCallback registry) on Release but does NOT reset scripts set on the underlying `widget.frame`. Worse, many widgets' Constructors install their own internal dispatcher there (e.g. Button's `frame:SetScript("OnEnter", Control_OnEnter)`) — overwriting it both leaks into other addons via the pool AND breaks the recycled widget's `widget:SetCallback("OnEnter", fn)` for the next owner. **Default fix: use `widget:SetCallback("OnEnter"/"OnLeave"/"OnClick"/"OnValueChanged"/...)` — Button, Dropdown, EditBox, CheckBox all wire Control_OnEnter to fire that registry and AceGUI clears the registry on release.** Only when a widget has no native dispatch for the event you need (e.g. SimpleGroup right-click handlers, `OnMouseDown` on any widget) use `addon.AceGUIFrameScripts(widget, { OnMouseDown = function(f, btn) ... end })` in [GUI/MainWindow.lua](GUI/MainWindow.lua) — it saves the prior script and RESTORES it on release (not nils it). Reference: rowGroup right-click in `GUI/CooldownsTab.lua` is the only legitimate user of the helper today.
- **Never call `widget:SetCallback("OnRelease", ...)` on a widget you didn't construct in a one-shot context** — `widget.events.OnRelease` only holds one callback, and the helper above uses it. Any second SetCallback("OnRelease", ...) on the same widget will stomp the cleanup and reintroduce the leak. If you need to do work on release AND raw-script restoration, hand the work to the helper rather than calling SetCallback("OnRelease") yourself.
- **Pool-attach pattern — always wire `addon.GUI.DetachPool` into OnRelease.** Tabs that maintain a pool of raw `CreateFrame` rows (the virtual-scroll perf trick) parent those frames to an AceGUI widget's content frame. When AceGUI recycles that widget into another addon's UI, our pool frames stay parented to it and visibly bleed into the other addon. Whenever you `:SetParent(someAceGUIWidget.content)` on pooled raw frames, you MUST register a cleanup on the parent widget's `OnRelease` that calls `addon.GUI.DetachPool(self._myPool)` (defined in [GUI/SharedWidgets.lua](GUI/SharedWidgets.lua)) — it Hides + re-parents to UIParent + ClearAllPoints, leaving the frames in the pool table for the next attach. Reference implementations: `BrowserTab:DestroyPool` (recipe scroll), `BrowserTab:DetachShoppingListPool` (shopping list), `MissingRecipesTab:DetachPool` (missing recipes). All three call `addon.GUI.DetachPool` and stay in sync via that one function.
- **Look at other addons in the workspace first** — PersonalShopper, Grouper, etc. often have the exact pattern needed. Check them before inventing a solution.
- **Fix lint/compile errors automatically** without being asked.

## Tooling

There is no build system, test runner, or package manager. The `.toc` version placeholder `@project-version@` is resolved by the CurseForge/BigWigs packager on release.

- **Linting:** `.luarc.json` configures Lua 5.1 LSP (lua-language-server). Several checks are intentionally disabled (need-check-nil, deprecated, param-type-mismatch). The `libs/` folder is excluded from workspace analysis.
- **Version sync:** `.vscode/tasks.json` runs `wow-version-replication.ps1` on folder open to mirror the addon across WoW installations on this machine.
- **No automated tests.** Verification is done in-game.

## File Load Order (from TOC)

Understanding this matters because Lua has no `require`; each file must only reference symbols defined in earlier files.

1. `libs/` vendor libs (LibDataBroker, LibDBIcon) → `Locale/enUS.lua`. DeltaSync-1.0 and LibGuildRoster-1.0 are **not** embedded — DeltaSync-1.0 loads from the standalone `DeltaSync` addon and LibGuildRoster-1.0 from the standalone `GuildRoster` addon, both declared in `## Dependencies`.
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

### DeltaSync-1.0 (external P2P library)

Loaded from the standalone `DeltaSync` addon (declared in `## Dependencies` and `.pkgmeta required-dependencies`). Resolved at runtime via `LibStub("DeltaSync-1.0", true)` in [Scanner.lua](Scanner.lua) — guild sync silently disables if the dependency is missing.

**Multi-host API (DeltaSync v4.0.0 / LibStub MINOR 15+).** DeltaSync is no longer a singleton. `Scanner:InitDeltaSync` creates an **isolated per-host object** via `DSlib:NewHost({…})` and stores it in `Scanner.DS`; it does **not** call the old `DS:Initialize` (that path kept per-addon state on the one shared LibStub table, so two DeltaSync consumers in a client clobbered each other). The init **hard-gates on `DSlib.NewHost and DSlib.MINOR >= 15`** — an older/stale DeltaSync disables guild sync rather than falling back to the singleton. Everything is called on the host, never the bare `DSlib` handle: every consumer already reads `Scanner.DS` (Settings guild-mode toggle, `TOGProfessionMaster.lua` roster sync) or receives it as a parameter (`HashManager:RebuildOnFirstLoad(DS, …)` / `:PadMissingProfessionPlaceholders(DS, …)` / `:ComputeHash`), so the host propagates automatically. The host inherits the full `DS:` method surface via a metatable, and the wire format is unchanged — a v15 host interoperates with any peer as before.

Custom P2P sync protocol built on AceComm. Key concepts:

- 7 logical channels: VERSION, DATA, QUERY, RESPONSE, DELTA, OFFER, HANDSHAKE
- Full payload on first contact → delta sync → hash-based leaf negotiation for ongoing sync
- `HashManager` provides the leaf keys (`cooldown:Name-Realm`, `recipes:profId`) and roll-ups (`guild:cooldowns`, `guild:recipes`)
- AceCommQueue-1.0 wraps `SendCommMessage` to prevent CRC errors under high traffic
- The `LibGuildRoster-1.0` LibStub library (the standalone `GuildRoster` addon, also vendored inside DeltaSync; MINOR ≥ 6 for the sister-roster API, MINOR 5+ for the base roster) is the **sole source of guild-roster truth** for TOGPM. Resolved as `Scanner.GuildRoster = LibStub("LibGuildRoster-1.0", true)`. It exposes query methods (`GetOnlineMembers`, `IsOnline`, `IsInGuild` — now a **strict** membership check, with a live-scan fallback before the first build, so display sites guard on `IsReady()` to avoid early-login false-flags — `IsReady`, `NormalizeName`, `GetNormalizedPlayer`) and CallbackHandler-1.0 transition events (`OnMemberOnline`, `OnMemberOffline`, `OnMemberJoined`, `OnMemberLeft`, `OnRosterReady`, `OnRosterUpdated`, `OnMemberRankChanged`, `OnRosterHashChanged`). The crafter-online alert in [TOGProfessionMaster.lua](TOGProfessionMaster.lua) registers `OnMemberOnline` on it. LibGuildRoster-1.0 replaced the retired GuildCache-1.0 in TOGPM v0.10.0; it is a capability superset that adds a multi-roster store (`SetSisterRoster`, `RemoveSisterRoster`, `GetRoster`, `GetRosterHash`, `IsInAnyRoster`, `MarkOnline`, `GetOnlineMembersScoped`, `GetHomeGuildKey`) for upcoming cross-guild support.

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

**Release tagging (Always Follow):**

- Release tags MUST use the template **`TOGProfessionMaster-vX.Y.Z`** (e.g. `TOGProfessionMaster-v0.9.1`) — **never** a bare `vX.Y.Z`. Every release tag in this repo follows this format; the BigWigs packager + CurseForge release rely on it.
- Pushing any tag triggers the release workflow (`.github/workflows/release.yml` fires on `tags: '**'`), which packages and publishes to CurseForge. Only create/push a tag when the user explicitly asks.
- Tag the exact commit being released (annotated tag) and push it: `git tag -a TOGProfessionMaster-vX.Y.Z -m "..." <sha>` then `git push origin TOGProfessionMaster-vX.Y.Z`.

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

**CurseForge description rules:**

- `docs/Curseforge_Description.html` lives in the repo (gitignored — local-only file used to update the CurseForge listing). Update it on every commit alongside `CHANGELOG.md`.
- The "Recent Updates" section in the HTML keeps **only the last 5 patches**. When prepending a new patch entry, drop the oldest one so the section stays at 5 entries max.
- The HTML patch entries should match the CHANGELOG format but condensed (one bullet per fix/feature, code-formatted file paths, `&mdash;` for em-dashes, `&ge;` for `>=`, `&rarr;` for arrows).

## Common Slash Commands

```text
/togpm          -- open main window
/togpm sync     -- force immediate broadcast of own data
/togpm debug    -- toggle debug output
/togpm purge    -- purge all guild data
/togpm version  -- show addon version
```
