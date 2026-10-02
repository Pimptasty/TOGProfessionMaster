<!-- charset-ok: this file is never drawn by the WoW client. It is rendered by
     GitHub and by the CurseForge listing, both UTF-8, and read in an editor.
     Its prose has used em dashes since the first release. Same declaration and
     same reason as CHANGELOG.md. Added 2026-08-20. -->
# TOG Profession Master

Stop whispering every alchemist in your guild to ask "is your transmute up?" and stop logging into five different alts to remember who knows the recipe you need. TOG Profession Master keeps a live, shared view of every guildmate's professions, recipes, and cooldowns — and lets you mail reagents straight to the crafter without typing a single character name.

Works on Classic Era / Anniversary, TBC Classic, Wrath Classic, Cataclysm Classic, and Mists of Pandaria Classic, with early support for WoW Forever.

## Quickstart

1. Install via [CurseForge](https://www.curseforge.com/wow/addons/togprofessionmaster) (recommended — handles dependencies automatically) or drop the folder into `Interface\AddOns`
2. `/reload` or restart WoW
3. Click the **TOGPM minimap button** to open the main window
4. Open your own profession windows (Alchemy, Tailoring, etc.) at least once on each character — TOGPM scans them automatically and starts syncing with the guild

That's it. Within a minute or two you'll see your guildmates' recipes and cooldowns alongside your own.

## What it does

**Profession Browser** — Every recipe known by anyone in your guild, with a list of crafters per recipe. Filter by profession, search by name, see who's online, right-click to whisper the crafter.

**Cooldowns Tab** — Every guildmate's active and ready profession cooldowns in one view: transmutes, Mooncloth, Salt Shaker, Northrend Research, Icy Prism, Truegold, Living Steel, JC daily cuts, and more. Hit the one-click **[Mail]** button to send the crafter a pre-composed supply mail with every reagent of that cooldown on it — one mail per cooldown, even for a two-reagent transmute like Arcanite; the click splits whatever stacks need splitting, attaches them all and fills in the recipient, and it sends nothing at all if you are short of any reagent. The reagent column is white when your bags hold enough of it to fill that mail and grey when they don't, so a glance down the list tells you which cooldowns you can actually feed — and it recolours as you loot or send things, without a tab switch.

**Missing Recipes Tab** — Pick a character and a profession and see every recipe scroll they haven't learned yet, with where to obtain it (vendor, drop, quest, container, fishing). Filter to a single profession or search by name. A **Guild** view shows recipes *nobody* in the guild knows, which is the coverage gap worth acting on. Rank-up books (Expert, Artisan and so on) drop off the list once you have outgrown them. A **[Where]** button opens every vendor, drop and zone for the recipe's scroll, with drop chances and map coordinates (from ItemDB). With **Questbook** installed, a **[Guide]** button starts the route to the best place for the scroll in one click — one in your current zone first, then a vendor, then the best drop chance — and clicking any place in the [Where] window guides you there instead. Questbook's own stop button sits in the main window's bottom row, beside the gear, on every tab, to cancel the route. On TBC there is an optional filter to hide recipes from content phases that are not live yet — it ships off, so by default nothing is hidden from you.

**Guild Tab** — Who in the guild has which profession, at what skill, and with which specialization. Specializations are inferred from the spec-gated recipes a crafter knows, so they show up even for people who never announced them. Gathering professions are included, and a profession with nobody in it is shown at zero — coverage gaps are the thing you actually want to see.

**Crafting Tab** — A full crafting screen in TOGPM's own style, including a drag-to-reorder craft queue (Craft All crafts one recipe's full batch per click, because the game needs a click for each recipe) and a cost-to-craft with profit preview (a reagent a vendor sells is costed at the vendor price, never an auction listing). Optionally takes over the default profession window (`/togpm craft`). Enchanting is supported, recipe tooltips included. A hunter's Beast Training shares Enchanting's window on Classic and TBC; the takeover leaves it to the game, so pets can always be trained.

**Profit Planner** — What's worth making right now, using auction prices from **ItemDB**: its own Auction House scan, or Auctionator, Auctioneer and TradeSkillMaster if you run them. Which sources are used, and in what order, is set once in ItemDB (`/itemdb`, or the **Price sources** button in TOGPM's settings) and applies to every TOG addon; the Historical view uses only the sources that keep a history. No other pricing addon required.

**Allied Guilds (cross-guild sharing)** — Share professions and cooldowns between two guilds. Set up under **Settings → Cross-Guild** by an officer or the guild leader; it is bilateral by design, so both sides opt in, and it shares the whole guild's data rather than just yours. The allied-guild list and the allied rosters live in **GuildRoster** (also editable with `/guildroster sisters`), so every TOG addon on your account — this one, TOGTools, TOGBankClassic — reads one list and one set of rosters rather than each keeping its own. Pull an allied roster once from any online member of that guild (`/togpm pullroster <Name>`) and GuildRoster keeps it current from then on, for the whole guild.

**Shopping List + Reagent Tracker** — Queue any recipe to your shopping list. The floating Reagent Tracker shows a live total of everything you need vs. what's in your bags. You get a chat alert once your bags hold every reagent for a craft on your list.

**Scan AH** — One click scans the auction house (through ItemDB's scanner) for whatever's relevant to the current tab (shopping-list reagents, cooldown reagents, missing recipes). Rows that have live listings get an **[AH]** button you can click to jump straight to the AH browse search.

**TOGBankClassic integration** — When TOGBankClassic is loaded, every reagent shows a **[Bank]** button when the guild bank has stock. One click opens a request dialog: pick the banker, set the quantity, send. The maximum is the one TOG Bank enforces: the officer's request percentage of that banker's stock, less what you already have on order from them. View-only bankers aren't offered, and when an order is refused you see TOG Bank's own reason. While TOG Bank's shop is open, the order goes in as a shop purchase with TOG Bank's price estimate shown in the dialog; the bank character sets the final price when it's filled. The button carries TOG Bank's own status dot — green when your copy of that bank is current, red or yellow when a newer copy is on its way, grey when the only newer copy can't reach your client — so you can tell at a glance whether the stock behind it is current; hover for each banker's count and status.

**Crafter Online Alerts** — Chat ping when a guildmate who can craft something on your shopping list comes online.

**Item Tooltips** — Hover any item in your bags, the AH, a vendor, or a chat link, and you'll see which guildmates know how to craft it, with their skill rank and online status.

**Recipe details on every tooltip** — Hover a recipe scroll, or the item it makes, anywhere in the game: skill-up difficulty in the game's own tier colours, where the recipe comes from (trainer, drop, vendor, quest, container), and a red **Unlearned** list of which of *your* characters could still learn it, with their skill rank and specialisation. The source data is keyed by the recipe rather than by a scroll item, so it answers for the roughly one recipe in three that is trainer-taught and has no scroll at all — 74.9% of Vanilla recipes, against 44.6% for an item-keyed lookup. **This renders even if you run RecipeMaster**, and that is deliberate as of v1.0.7. TOGPM's block is not a duplicate of RM's: only TOGPM tells you which of *your own* characters could still learn the recipe, and which guildmates can craft it. Standing down to avoid overlapping two rows also withheld the rows nothing else in the game provides. A setting reverts to the old behaviour (RM owns the game's tooltips, TOGPM fills in the ones RM can't see) or switches the block off entirely.

**Item links behave like the rest of the game** — Shift-click any item name, reagent or recipe anywhere in the addon to link it in chat; ctrl-click to preview it in the dressing room. Hold the compare modifier over an item to see it side by side with what you're wearing. All of it goes through Blizzard's own handler, so it honours whatever you have those modifiers bound to rather than assuming shift and ctrl. If you'd rather have the full stock tooltip everywhere instead of TOGPM's trimmed one, there's a setting for that (off by default).

**Vendor buy *and* sell price, on every item** — Hover anything, anywhere: your bags, the auction house, a vendor, a chat link. Not just recipes. Two rows, and each one appears only when its number is real, so you never get a confident zero.

**Sell** is what a vendor pays you, the same figure TradeSkillMaster labels "Vendor Sell Price". **Buy** is what a vendor charges, which is a different number entirely — the two differ by roughly 4x, and cost-to-craft totals elsewhere in the addon deliberately use the buy price, because that is what a reagent actually costs you.

Buy comes from ItemDB's three-tier lookup: Auctionator's vendor cache, then prices captured live from vendors *you* have opened, then ItemDB's base price. Where you have met the vendor yourself the figure reflects your reputation discount rather than a book value. Sell asks the client first and falls back to ItemDB, so unlike most vendor-price lines it still answers for an item your client has never cached.

Nobody else shows both: TSM and Leatrix Plus show sell only, AllTheThings shows neither, and the game itself shows neither in your bags.

### How TOGPM behaves on a tooltip that isn't its own

Hovering an item can involve several addons writing into one shared frame. TOGPM follows four rules so it never degrades what the rest of your UI puts there.

**Nothing drawn on a TOGPM tooltip can stretch it, including other addons' lines.** A WoW tooltip has a preset wrap width the engine derives from your resolution, UI scale and font, and a line opts into it with a flag that defaults to *off*. One line that doesn't opt in ignores the preset and widens the whole frame — everyone's content with it. TOGPM passes that flag on every line it writes, and forces it on for the duration of any third-party render, so an addon that never heard of the flag still gets held to the game's width. Exactly one line is left unwrapped: the recipe title, because something has to claim a natural width or the frame collapses to the bare preset and an item name that the game fits on one line breaks onto two. No width is measured, and none is hardcoded — a hardcoded one would be right on the machine it was measured on and wrong on yours.

**TOGPM's block renders after the integrations it draws itself.** On tooltips TOGPM builds — the recipe browser, Missing Recipes — other addons' contributions are drawn first and ours last, matching the order a stock tooltip uses. It also means a fault in TOGPM's block can't take anything else down with it: before v1.0.7 an error partway through our block silently deleted AllTheThings, TradeSkillMaster and RecipeMaster from the tooltip, because the raise aborted before their content was rendered.

On the game's own tooltips — your bags, the auction house, a chat link — TOGPM appends wherever the hook chain puts it, which is not necessarily last. Addon tooltip order there is decided by load order and hook registration across every addon you run, and no single addon controls it.

**TOGPM hands the tooltip back exactly as it found it.** The tooltip you hover is a single frame shared by the whole UI, and the game never resets a width once something has widened it — that has to be undone deliberately by whoever set it. Through v1.0.6 one hover of TOGPM's help icon widened *every tooltip in the game*, ours and every other addon's, for the rest of the session. That's fixed, and if another addon has legitimately set its own minimum width, TOGPM restores that value rather than clearing it.

**Every tab uses the game's own tooltip, including Missing Recipes.** That tab used a private tooltip frame from v0.7.5 to v1.0.6, to sidestep a third-party addon raising on recipe scrolls it hadn't cached. The cost was that its rows looked different from the rest of the game and no other addon's tooltip additions appeared on them. That addon has been rewritten since, so the private frame is gone and Missing Recipes behaves like everything else.

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
| `/togpm perf` | How long each window open, tab draw, background build and incoming sync took this session; the game's own record of every addon's worst frame since login (so a pause is attributed to whichever addon owned it); and how large each part of your saved data is. If the game pauses, run this straight afterwards and paste it |
| `/acq status` | The comm queue's own view: which sends are in flight, stalled, or refused |

## Requirements

Installing from CurseForge pulls these in automatically. Installing by hand means fetching them yourself, and the addon will not load without them:

**Ace3**, **DeltaSync**, **AceCommQueue-1.0**, **VersionCheck-1.0**, **GuildRoster**, **ProfessionDB**, **ItemDB**, **LibAceGUIWidgets**, **LibDBIcon-1.0**.

LibDBIcon-1.0 is bundled on WoW Forever, where it is not published yet; everywhere else it is a separate addon.

Keep **AceCommQueue-1.0** current in particular — it is the layer that queues addon traffic, and older copies mistook ordinary server throttling for a fault and reported it as an error. **GuildRoster 0.7.0 or newer** is needed for cross-guild sharing: it holds the allied-guild list and rosters for every TOG addon; on an older copy the addon runs normally with cross-guild sharing off. **ItemDB carrying LibItemDB 25 or newer** is needed for any auction price: since v1.1.0 the Auction House scanner, the Auctionator / Auctioneer / TSM connections and the price-source settings all live there; on an older ItemDB you get vendor prices only, and no [AH] or Scan AH buttons.

## Settings

All settings live in WoW's standard Options panel: **ESC → Options → AddOns → TOG Profession Master**. Or click the gear icon on the main window, or use `/togpm` and then the gear.

Settings include cooldown-ready alarms, crafter-online alerts, instance-mute toggle, periodic reminder cadence, window scale and background opacity (turn the window see-through without fading its text), and more — every option has a hover tooltip explaining what it does. Price sources (which of Auctionator / Auctioneer / TSM / the ItemDB scan are used, and in what order) are set in ItemDB's own window; the **Price sources (ItemDB)...** button here opens it, and the choices you had made in TOGPM before v1.1.0 were carried over on your first login.

## Need Help?

Bug reports, feature requests, questions, or just chatting: **[Join the Discord](https://discord.com/invite/bY2R5TmBSz)**.

## Credits

**Pimptasty** — author and maintainer.

Built on the [Ace3](https://www.curseforge.com/wow/addons/ace3) library suite (AceAddon, AceGUI, AceDB, AceConfig, AceComm, AceSerializer, AceTimer, AceConsole), plus [DeltaSync](https://www.curseforge.com/wow/addons/deltasync) for the peer-to-peer sync engine, [GuildRoster](https://www.curseforge.com/wow/addons/libguildroster) for guild membership and online state, [ItemDB](https://www.curseforge.com/wow/addons/libitemdb) for item stats, vendor prices and recipe-scroll data, [AceCommQueue](https://www.curseforge.com/wow/addons/acecommqueue), [VersionCheck](https://www.curseforge.com/wow/addons/versioncheck), LibAceGUIWidgets for the shared window and list widgets, LibDataBroker, and LibDBIcon.

Optional integrations: [TOGBankClassic](https://www.curseforge.com/wow/addons/togbankclassic) for guild-bank reagent buttons; [GreenWall](https://www.curseforge.com/wow/addons/greenwall) for confederate-guild cooldown announcements; Questbook for guiding you to where a missing recipe's scroll is sold or drops.

### Data sources

Recipe data comes from [ProfessionDB](https://www.curseforge.com/wow/addons/libprofessiondb),
built from Blizzard's own client data via [wago.tools](https://wago.tools). This
addon ships no recipe data of its own and generates none — ProfessionDB owns the
whole pipeline, so every table is correct for the exact client version you are
running rather than being an all-expansion merge.

Two things the client does not know are derived from community projects at build
time, and shipped as static tables:

- **Where a recipe comes from** — trainer, vendor, quest, container and drop
  sources are derived from the [TrinityCore](https://github.com/TrinityCore) and
  [AzerothCore](https://github.com/azerothcore) world databases, which
  reverse-engineered and tested them. The client stores none of it. They ship in
  ProfessionDB, with the npc names alongside the ids, and the npc names are
  English only because the world databases are not localized.
- **Which TBC content phase gates a recipe** — the `phase` tags behind the
  optional Missing Recipes phase filter are derived from
  [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT), via its raid,
  reputation and patch metadata. That filter **ships off** as of v1.0.8: by
  default you see every recipe, and you turn it on if you would rather hide
  content that is not live on your realm yet. It defaulted to *on* before that,
  pinned to a phase number that had to be bumped by a release each time Blizzard
  opened one — which stopped happening, and quietly hid 194 real TBC recipes.

In every case the projects' files are **not** redistributed: only the factual
mappings are extracted and re-expressed in this addon's own format, and each
project is gratefully acknowledged.
