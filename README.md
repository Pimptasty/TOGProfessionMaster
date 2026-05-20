# TOG Profession Master

Stop whispering every alchemist in your guild to ask "is your transmute up?" and stop logging into five different alts to remember who knows the recipe you need. TOG Profession Master keeps a live, shared view of every guildmate's professions, recipes, and cooldowns — and lets you mail reagents straight to the crafter without typing a single character name.

Works on Classic Era / Anniversary, TBC Classic, Wrath Classic, Cataclysm Classic, and Mists of Pandaria Classic.

## Quickstart

1. Install via [CurseForge](https://www.curseforge.com/wow/addons/tog-profession-master) (recommended — handles dependencies automatically) or drop the folder into `Interface\AddOns`
2. `/reload` or restart WoW
3. Click the **TOGPM minimap button** to open the main window
4. Open your own profession windows (Alchemy, Tailoring, etc.) at least once on each character — TOGPM scans them automatically and starts syncing with the guild

That's it. Within a minute or two you'll see your guildmates' recipes and cooldowns alongside your own.

## What it does

**Profession Browser** — Every recipe known by anyone in your guild, with a list of crafters per recipe. Filter by profession, search by name, see who's online, right-click to whisper the crafter.

**Cooldowns Tab** — Every guildmate's active and ready profession cooldowns in one view: transmutes, Mooncloth, Salt Shaker, Northrend Research, Icy Prism, Truegold, Living Steel, JC daily cuts, and more. Hit the one-click **[Mail]** button to send the crafter a pre-composed supply mail with the right reagent.

**Missing Recipes Tab** — Pick a character and a profession and see every recipe scroll they haven't learned yet, with where to obtain it (vendor, drop, quest, container, fishing). Filter to a single profession or search by name.

**Shopping List + Reagent Tracker** — Queue any recipe to your shopping list. The floating Reagent Tracker shows a live total of everything you need vs. what's in your bags. Chat alert when all reagents are available.

**Scan AH** — One click scans the auction house for whatever's relevant to the current tab (shopping-list reagents, cooldown reagents, missing recipes). Rows that have live listings get an **[AH]** button you can click to jump straight to the AH browse search.

**TOGBankClassic integration** — When TOGBankClassic is loaded, every reagent shows a **[Bank]** button when the guild bank has stock. One click opens a request dialog.

**Crafter Online Alerts** — Chat ping when a guildmate who can craft something on your shopping list comes online.

**Item Tooltips** — Hover any item in your bags, the AH, a vendor, or a chat link, and you'll see which guildmates know how to craft it, with their skill rank and online status.

## Slash Commands

| Command | What it does |
|---|---|
| `/togpm` | Open the main window |
| `/togpm reagents` | Open the floating Reagent Tracker |
| `/togpm minimap` | Show the minimap button (if you've hidden it) |
| `/togpm sync` | Force a fresh sync with the guild now |
| `/togpm status` | Show sync status and online member count |
| `/togpm versioncheck` | Check which guildmates are running which version |
| `/togpm purge` | Open the purge-data dialog (clear stored guild data) |
| `/togpm help` | Show all commands |

## Settings

All settings live in WoW's standard Options panel: **ESC → Options → AddOns → TOG Profession Master**. Or click the gear icon on the main window, or use `/togpm` and then the gear.

Settings include cooldown-ready alarms, crafter-online alerts, instance-mute toggle, periodic reminder cadence, and more — every option has a hover tooltip explaining what it does.

## Need Help?

Bug reports, feature requests, questions, or just chatting: **[Join the Discord](https://discord.com/invite/bY2R5TmBSz)**.

## Credits

**Pimptasty** — author and maintainer.

Built on the [Ace3](https://www.curseforge.com/wow/addons/ace3) library suite (AceAddon, AceGUI, AceDB, AceConfig, AceComm, AceSerializer, AceTimer, AceConsole), plus [DeltaSync](https://www.curseforge.com/wow/addons/deltasync) for the peer-to-peer sync engine, [AceCommQueue](https://www.curseforge.com/wow/addons/acecommqueue), [VersionCheck](https://www.curseforge.com/wow/addons/versioncheck), LibDataBroker, and LibDBIcon.

Optional integrations: [TOGBankClassic](https://www.curseforge.com/wow/addons/togbankclassic) for guild-bank reagent buttons; [GreenWall](https://www.curseforge.com/wow/addons/greenwall) for confederate-guild cooldown announcements.
