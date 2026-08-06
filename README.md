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

**Guild Tab** — Who in the guild has which profession, at what skill, and with which specialization. Specializations are inferred from the spec-gated recipes a crafter knows, so they show up even for people who never announced them. Gathering professions are included, and a profession with nobody in it is shown at zero — coverage gaps are the thing you actually want to see.

**Crafting Tab** — A full crafting screen in TOGPM's own style, including a craft queue and a cost-to-craft with profit preview. Optionally takes over the default profession window (`/togpm craft`). Enchanting is supported, recipe tooltips included.

**Profit Planner** — What's worth making right now, using auction prices from the built-in scanner. No other addon required, though it plays nicely with Auctionator.

**Allied Guilds (cross-guild sharing)** — Share professions and cooldowns between two guilds. Set up under **Settings → Cross-Guild** by an officer or the guild leader; it is bilateral by design, so both sides opt in, and it shares the whole guild's data rather than just yours.

**Shopping List + Reagent Tracker** — Queue any recipe to your shopping list. The floating Reagent Tracker shows a live total of everything you need vs. what's in your bags. Chat alert when all reagents are available.

**Scan AH** — One click scans the auction house for whatever's relevant to the current tab (shopping-list reagents, cooldown reagents, missing recipes). Rows that have live listings get an **[AH]** button you can click to jump straight to the AH browse search.

**TOGBankClassic integration** — When TOGBankClassic is loaded, every reagent shows a **[Bank]** button when the guild bank has stock. One click opens a request dialog.

**Crafter Online Alerts** — Chat ping when a guildmate who can craft something on your shopping list comes online.

**Item Tooltips** — Hover any item in your bags, the AH, a vendor, or a chat link, and you'll see which guildmates know how to craft it, with their skill rank and online status.

**Item links behave like the rest of the game** — Shift-click any item name, reagent or recipe anywhere in the addon to link it in chat; ctrl-click to preview it in the dressing room. Hold the compare modifier over an item to see it side by side with what you're wearing. All of it honours your own modified-click bindings rather than assuming shift. If you'd rather have the full stock tooltip everywhere instead of TOGPM's trimmed one, there's a setting for that (off by default).

## Slash Commands

| Command | What it does |
| --- | --- |
| `/togpm` | Open the main window |
| `/togpm reagents` | Open the floating Reagent Tracker |
| `/togpm minimap` | Show the minimap button (if you've hidden it) |
| `/togpm craft` | Toggle the crafting-window takeover on or off |
| `/togpm sync` | Force a fresh sync with the guild now |
| `/togpm status` | Show sync status and online member count |
| `/togpm versioncheck` | Check which guildmates are running which version |
| `/togpm purge` | Open the purge-data dialog (clear stored guild data) |
| `/togpm help` | Show all commands, including the diagnostics below |

If sync isn't working, these are the ones worth running before opening a bug report — paste the output into the Discord:

| Command | What it does |
| --- | --- |
| `/togpm commtest` | Asks whether your server actually relays guild addon messages at all. Some private cores don't, and nothing else can work if that's the answer |
| `/togpm dsstatus` | Sync engine status: what's been sent, received, and refused |
| `/togpm xgdiag` | Cross-guild diagnostics — why an allied guild's data isn't arriving |
| `/togpm whyvisible <Name>` | Explains why a particular character is (or isn't) shown |
| `/acq status` | The comm queue's own view: which sends are in flight, stalled, or refused |

## Requirements

Installing from CurseForge pulls these in automatically. Installing by hand means fetching them yourself, and the addon will not load without them:

**Ace3**, **DeltaSync**, **AceCommQueue-1.0**, **VersionCheck-1.0**, **GuildRoster**, **ProfessionDB**, **ItemDB**.

Keep **AceCommQueue-1.0** current in particular — it is the layer that queues addon traffic, and older copies mistook ordinary server throttling for a fault and reported it as an error.

## Settings

All settings live in WoW's standard Options panel: **ESC → Options → AddOns → TOG Profession Master**. Or click the gear icon on the main window, or use `/togpm` and then the gear.

Settings include cooldown-ready alarms, crafter-online alerts, instance-mute toggle, periodic reminder cadence, and more — every option has a hover tooltip explaining what it does.

## Need Help?

Bug reports, feature requests, questions, or just chatting: **[Join the Discord](https://discord.com/invite/bY2R5TmBSz)**.

## Credits

**Pimptasty** — author and maintainer.

Built on the [Ace3](https://www.curseforge.com/wow/addons/ace3) library suite (AceAddon, AceGUI, AceDB, AceConfig, AceComm, AceSerializer, AceTimer, AceConsole), plus [DeltaSync](https://www.curseforge.com/wow/addons/deltasync) for the peer-to-peer sync engine, [AceCommQueue](https://www.curseforge.com/wow/addons/acecommqueue), [VersionCheck](https://www.curseforge.com/wow/addons/versioncheck), LibDataBroker, and LibDBIcon.

Optional integrations: [TOGBankClassic](https://www.curseforge.com/wow/addons/togbankclassic) for guild-bank reagent buttons; [GreenWall](https://www.curseforge.com/wow/addons/greenwall) for confederate-guild cooldown announcements.
