-- TOG Profession Master -- Dutch (nlNL) locale
--
-- IMPORTANT: nlNL is NOT a WoW-recognized locale code. GetLocale() will
-- never return "nlNL" on any Blizzard client, so AceLocale will never
-- auto-select this file. This locale is reachable ONLY via the Settings
-- "UI Language Override" dropdown (default Auto). Dutch-speaking players
-- (most of whom play on enGB or enUS builds) can opt into Dutch addon UI
-- while in-game item / spell / NPC names continue to render in their
-- client's actual locale (since those come from Blizzard's APIs, not
-- from this addon).
--
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("nlNL")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — Synchronisatielogboek"

-- Tab labels
L["TabProfessions"]     = "Professions"
L["TabCooldowns"]       = "Cooldowns"
L["TabReagents"]        = "Reagents"
L["TabMissingRecipes"]  = "Ontbrekende recepten"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Zoek recepten…"
L["ViewGuild"]          = "Guild"
L["ViewMine"]           = "Mijn personages"
L["AllProfessions"]     = "Alle professions"
L["PanelProfessions"]   = "Professions"
L["PanelCharacters"]    = "Personages"
L["SelectProfession"]   = "Kies een profession"
L["NoDataYet"]          = "|cffaaaaaa(nog geen gegevens)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Kies een profession om te zien wie het kent.|r"
L["NoProfMembers"]      = "|cffaaaaaa(geen guildleden met deze profession)|r"
L["BackToCharacters"]   = "|cff00aaff← Terug naar personages|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(geen overeenkomende recepten)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Jij"
L["BrowserScanAH"]          = "AH scannen"
L["BrowserScanAHProgress"]  = "Scannen %d/%d"
L["BrowserScanAHDesc"]      = "Scan de auction house op elke reagent in je boodschappenlijst. Rijen waarvan de reagents momenteel op de AH staan krijgen een [AH]-knop; klik daarop om direct naar het AH-zoekresultaat te springen."
L["CooldownsScanAHDesc"]    = "Scan de auction house op elke unieke reagent in de zichtbare cooldownrijen. Rijen waarvan de reagents momenteel op de AH staan krijgen een [AH]-knop (links van [Bank]); klik daarop om direct naar het zoekresultaat te springen."

-- Recipe detail popup
L["PopupCrafters"]       = "Gekend door"
L["PopupOnList"]         = "Op boodschappenlijst"
L["PopupNotOnList"]      = "Niet op boodschappenlijst"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Alleen klaar"
L["ShowAll"]                = "Alle"
L["FilterColProfession"]    = "Profession"
L["FilterColCooldown"]      = "Cooldown"
L["FilterColView"]          = "Weergave"
L["FilterProfessionDesc"]   = "Filter de hersteltijdlijst op één profession (Alchemy, Tailoring, enz.)."
L["FilterCooldownDesc"]     = "Filter binnen de gekozen profession op één gedeelde cooldown (bijv. Transmutaties, Mooncloth)."
L["FilterViewDesc"]         = "Wissel tussen de hersteltijden van alle gildeleden en alleen je eigen personages."
L["AllCooldowns"]           = "Alle hersteltijden"
L["FilterTransmute"]            = "Transmutatie"
L["FilterAlchResearch"]         = "Alchemy Research"
L["FilterMooncloth"]            = "Mooncloth"
L["FilterSpecialtyCloth"]       = "Specialty Cloth"
L["FilterGlacialBag"]           = "Glacial Bag"
L["FilterDreamcloth"]           = "Dreamcloth"
L["FilterImperialSilk"]         = "Imperial Silk"
L["FilterSaltShaker"]           = "Salt Shaker"
L["FilterMagicSphere"]          = "Magic Sphere"
L["FilterShaCrystal"]           = "Sha Crystal"
L["FilterBrilliantGlass"]       = "Brilliant glass"
L["FilterIcyPrism"]             = "Icy Prism"
L["FilterFirePrism"]            = "Fire Prism"
L["FilterJcDaily"]              = "Jewelcrafting Daily"
L["FilterInscriptionResearch"]  = "Inscription research"
L["FilterForgedDocuments"]      = "Forged Documents"
L["FilterScrollOfWisdom"]       = "Scroll of Wisdom"
L["FilterTitansteelBar"]        = "Titansteel Bar"
L["FilterBsIngot"]              = "Smelten"
L["FilterMagnificence"]         = "Magnificence"
L["FilterJards"]                = "Jard's Energy"
L["ColCharacter"]           = "Personages"
L["ColCooldown"]            = "Cooldown"
L["ColReagent"]             = "Ingrediënt"
L["ColTimeLeft"]            = "Resterende tijd"
L["NoCooldownData"]         = "|cffaaaaaa(nog geen Cooldowngegevens — open een profession)|r"
L["Ready"]                  = "|cff00ff00Klaar|r"
L["Transmute"]              = "Transmutatie"
L["MailBtn"]                = "Post"
L["MailBtnTooltip"]         = "Bevoorradingspost versturen"
L["MailBtnTooltipDesc"]     = "Open een brievenbus en klik dan om reagents bij te voegen en een bevoorradingsbericht aan deze speler op te stellen."
L["BankBtn"]                = "[Bank]"
L["CloseBtn"]               = "Sluiten"

-- Beroepsspecialisatie-bonusoutputindicator
L["SpecBonusGuaranteedDouble"]  = "Gegarandeerde 2x opbrengst"
L["SpecBonusProcChance"]        = "Kans op extra opbrengst"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Boodschappenlijst"
L["SectionMissingReagents"] = "Ontbrekende reagents"
L["SectionReagentWatch"]    = "Reagents in de gaten houden"
L["ShoppingListEmpty"]      = "|cffaaaaaa(leeg — klik op een receptrij in het tabblad Professions om items aan je boodschappenlijst toe te voegen)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(de boodschappenlijst is leeg of alle reagents zitten in je tassen)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(geen in de gaten te houden items — voer hierboven een item-ID of link in)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch-module niet geladen)|r"
L["WatchInputLabel"]        = "Voorwerp-ID of link"
L["WatchBtn"]               = "Bewaken"
L["WatchedItemsHeading"]    = "In de gaten te houden items"
L["ColHave"]                = "Heb"
L["ColNeed"]                = "Nodig"
L["ColShort"]               = "Tekort"
L["ColItem"]                = "Item"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Personage|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Profession|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Zoek recepten…|r"
L["MissingIncludeTrainer"]      = "Alleen-trainer opnemen"
L["MissingIncludeTrainerDesc"]  = "Voegt recepten toe die alleen bij een trainer geleerd kunnen worden (geen VH-rol)."
L["MissingScanAH"]              = "AH scannen"
L["MissingScanAHProgress"]      = "Scannen %d/%d (klik om te annuleren)"
L["MissingScanAHDesc"]          = "Open de auction house en klik dan om elke receptrol in de zichtbare lijst te scannen. Rijen met actieve aanbiedingen krijgen een [AH]-knop; klik daarop om direct naar het zoekresultaat te springen."
L["MissingNoCharacters"]        = "|cffaaaaaa(nog geen personages met informatie over je professions — open een profession)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(dit personage heeft nog geen geregistreerde professions — open een profession)|r"
L["MissingNoneFound"]           = "|cff00ff00Alle bekende recepten voor deze profession zijn geleerd.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Kies een profession om te zien wat er ontbreekt.|r"
L["MissingNoData"]              = "|cffff8888(geen receptgegevens beschikbaar voor deze profession)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Recept"
L["MissingColSkill"]            = "Skill"
L["MissingColSource"]           = "Bronnen"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Houd dit recept in de gaten"
L["MissingAddToWatchDesc"]      = "Voegt het recept toe aan je in de gaten te houden reagentlijst zodat je hem ziet zodra hij in je tassen terechtkomt."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Al in de gaten aan het houden — klik om te stoppen met in de gaten houden"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Ontbrekend recept"
L["MissingCountPlural"]         = "Ontbrekende recepten"
L["MissingTruncatedHint"]       = "(toont de eerste %d — typ in het zoekvak om de lijst te beperken)"
L["MissingCharTooltipTitle"]    = "Personagefilter"
L["MissingCharTooltipDesc"]     = "Kies voor welk van je personages ontbrekende recepten getoond worden. Standaard het momenteel ingelogde personage."
L["MissingProfTooltipTitle"]    = "Professionfilter"
L["MissingProfTooltipDesc"]     = "Kies een profession om de recepten te zien die dit personage nog niet heeft geleerd."
L["MissingSearchTooltipTitle"]  = "Zoek recepten"
L["MissingSearchTooltipDesc"]   = "Typ om de lijst met ontbrekende recepten op naam te filteren."
L["MissingHdrCountTitle"]       = "Ontbrekende recepten"
L["MissingHdrCountDesc"]        = "Recepten die het gekozen personage nog niet heeft geleerd maar wel verkrijgbaar zijn in deze versie van het spel. Het aantal weerspiegelt het huidige filter (profession, zoekopdracht, trainer-schakelaar)."
L["MissingHdrSkillTitle"]       = "Skillniveau"
L["MissingHdrSkillDesc"]        = "Het vereiste skillniveau om dit recept te leren. Grijze rijen betekenen dat het personage nog niet hoog genoeg is."
L["MissingHdrSourceTitle"]      = "Bronnen"
L["MissingHdrSourceDesc"]       = "Hoe je dit recept verkrijgt — trainer, drop, vendor, quest of vervaardigd. Beweeg de muis over de bronnentekst van een rij voor de specifieke NPC / monster / stap."
L["MissingRowTooltipShift"]     = "Shift-klik om in de chat te linken."
L["MissingSrcVendor"]           = "Vendor"
L["MissingSrcDrop"]             = "Drop"
L["MissingSrcQuest"]            = "Quest"
L["MissingSrcCrafted"]          = "Vervaardigd"
L["MissingSrcFishing"]          = "Vissen"
L["MissingSrcContainer"]        = "Container"
L["MissingSrcTrainer"]          = "Trainer"
L["MissingSrcOther"]            = "Overig"
L["MissingSrcUnknown"]          = "Onbekend"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Itemtooltip"
L["SettingsTooltipShowCrafters"]    = "Toon guild in itemtooltips"
L["SettingsTooltipShowCraftersDesc"]= "Voegt een [TOGPM]-regel toe met alle guildgenoten die het voorwerp waarover je zweeft kunnen maken. Online in wit, offline in grijs. BoP voorwerpen worden overgeslagen (toch niet verhandelbaar)."
L["SettingsTooltipShowIds"]         = "Toon item-ID / spell-ID in tooltips"
L["SettingsTooltipShowIdsDesc"]     = "Voegt een [TOGPM]-regel toe met het item-ID en (indien bekend) het spell-ID van het recept. Vooral nuttig voor het diagnosticeren van verkeerde iconen of ontbrekende recepten — plak de ID's in WoWhead om de overeenkomst te verifiëren."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "TBC Anniversary-fase"
L["SettingsTBCPhase"]           = "Huidige contentphase"
L["SettingsTBCPhaseDesc"]       = "Verbergt ontbrekende recepten uit versies later dan de huidige Anniversary-phase. Verhoog deze waarde telkens als Blizzard de phase vooruitschuift. (Recepten die al toegankelijk zijn in de actieve phase blijven zichtbaar.)"
L["SettingsTBCPhase1"]          = "Phase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Phase 2 — Serpentshrine Cavern / Tempest Keep"
L["SettingsTBCPhase3"]          = "Phase 3 — Black Temple / Mount Hyjal"
L["SettingsTBCPhase4"]          = "Phase 4 — Sunwell / Magisters' Terrace"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Weergave"
L["SettingsMinimapBtn"]          = "Toon minimapknop"
L["SettingsMinimapBtnDesc"]      = "Toont of verbergt de starter-knop op de minimap."
L["SettingsPersistProfFilter"]     = "Onthoud professionfilter"
L["SettingsPersistProfFilterDesc"] = "Herstelt de geselecteerde profession bij inloggen of herladen."
L["SettingsSyncHeader"]     = "Synchronisatie"
L["SettingsGuildMode"]      = "Alleen-gilde synchronisatiemodus (privéservers)"
L["SettingsGuildModeDesc"]  = "Voor privé- of geëmuleerde servers (bijv. Whitemane) die addon-berichten niet via gefluister bezorgen, waardoor gildeleden elkaars beroepsgegevens niet ontvangen. Wanneer AAN wordt al het synchronisatieverkeer in plaats daarvan via het gildekanaal geleid. Schakel dit alleen in als gildesynchronisatie op jouw server niet werkt. |cffffd100Iedereen in de gilde moet het inschakelen|r — het werkt alleen tussen leden die het allebei aan hebben staan. Delen tussen gildes wordt automatisch uitgeschakeld zolang dit aan staat. Geldt voor elk personage op deze realm. (Verborgen als jouw geïnstalleerde DeltaSync-versie het niet ondersteunt.)"
L["SettingsCooldownsHeader"]= "Cooldowntijden"
L["SettingsMailReadyOnly"]  = "Post: toon alleen cooldowntijden die gereed zijn"
L["SettingsMailReadyOnlyDesc"] = "Bij het opstellen van bevoorradingspost vanuit het cooldowntijdpaneel, toon alleen guildleden waarvan de cooldowntijd gereed is."
L["SettingsDevHeader"]      = "Ontwikkelaar"
L["SettingsDebug"]          = "Debug-uitvoer"
L["SettingsDebugDesc"]      = "Drukt gedetailleerde debugberichten af in het chatvenster."
L["SettingsDataHeader"]     = "Gegevens"
L["SettingsSyncNow"]        = "Forceer hersynchronisatie"
L["SettingsSyncNowDesc"]    = "Zendt je beroepsgegevens onmiddellijk uit naar de guild."
L["SettingsPurgeGuild"]     = "Wis alle guildgegevens"
L["SettingsPurgeGuildDesc"] = "Verwijdert alle opgeslagen profession- en cooldowntijdgegevens voor elk guildlid op dit account. Kan niet ongedaan gemaakt worden."
L["SettingsPurgeGuildConfirm"] = "ALLE guildegegevens voor dit account verwijderen?"
L["SettingsPurgeMine"]      = "Wis mijn personagegegevens"
L["SettingsPurgeMineDesc"]  = "Verwijdert alleen de opgeslagen gegevens van je eigen personage uit de guilddatabase."
L["SettingsPurgeMineConfirm"] = "Je eigen profession- en hersteltijdgegevens verwijderen?"
L["SettingsSyncLogHeader"]  = "Synchronisatielogboek"
L["SettingsViewLog"]        = "Synchronisatielogboek bekijken"
L["SettingsViewLogDesc"]    = "Opent een scrollbare lijst van recente synchronisatiegebeurtenissen (laatste 200)."
L["SettingsClearLog"]       = "Synchronisatielogboek wissen"
L["SettingsClearLogConfirm"]= "Alle vermeldingen van het synchronisatielogboek wissen?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(SyncLog-module niet geladen)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(nog geen synchronisatiegebeurtenissen opgenomen)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Minimapknop verborgen. Gebruik |cffda8cff/togpm minimap|r om te herstellen."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Gemaakt door:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Klaar om te maken:|r %s × %d  (%s × %d in tassen)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Activeer crafterswaarschuwing voor dit recept"
L["ShoppingAlertDisable"]              = "Deactiveer crafterswaarschuwing voor dit recept"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s is online — kan maken: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s is online (alt van %s) — kan maken: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Activeer gereed-waarschuwing voor deze cooldown"
L["CooldownAlertDisable"]              = "Deactiveer gereed-waarschuwing voor deze cooldown"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Cooldown klaar: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Crafterswaarschuwingen"
L["SettingsCrafterAlert"]              = "Activeer crafterswaarschuwingen"
L["SettingsCrafterAlertDesc"]          = "Speelt een geluid af en laat het scherm knipperen wanneer een guildlid dat een in de gaten gehouden item op je boodschappenlijst kan maken online komt."
L["SettingsCrafterAlertSuppressAV"]    = "Onderdruk geluid en knipperen"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Deactiveert audio-effecten en schermknippering (chatbericht verschijnt wel)."
L["SettingsCrafterAlertSuppressLogin"]     = "Onderdruk waarschuwingen bij inloggen"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Geen waarschuwingen activeren tijdens de initiële stroom van online-meldingen bij inloggen of herladen."
L["SettingsCooldownAlertSuppressProtected"]     = "Dempt waarschuwingen in instances"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Geen geluid of weergave van cooldown-gereed-waarschuwingen terwijl je in een raid, dungeon, battleground, arena of scenario bent. Hoofdsteden worden NIET gedempt — je transmutatie blijft pingen terwijl je AFK staat in Stormwind. Wachtende waarschuwingen komen in je scherm zodra je de instance verlaat."
L["SettingsCooldownReminderInterval"]      = "Cooldown-gereed herinnering"
L["SettingsCooldownReminderIntervalDesc"]  = "Vuurt elke geactiveerde hersteltijd-waarschuwing opnieuw af elke N minuten zolang de cooldown gereed blijft (d.w.z. totdat je deze daadwerkelijk maakt). Voer 0, leeg of 'off' in om slechts één keer per gereed-cyclus af te vuren. Geldig bereik: 1–1440 minuten (24 uur)."
L["SettingsCooldownReminderInvalid"]       = "Voer een geheel getal in van 0 tot 1440, of 'off'."

L["SettingsAHHeader"]                      = "Auction House"
L["SettingsAHScanDelay"]                   = "AH-scanvertraging (seconden)"
L["SettingsAHScanDelayDesc"]               = "Seconden tussen AH-scanverzoeken. Leeg / 0 / 'off' gebruikt de versiestandaard (1,5s op Classic Era en Anniversary; 3,0s op TBC, Wrath, Cata, MoP — die servers beperken strenger). Verlaag voor snellere scans, verhoog als scans vastlopen. Geldig bereik: 0,5–10 seconden."
L["SettingsAHScanDelayInvalid"]            = "Voer een getal in van 0,5 tot 10, of 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Recept"
L["TooltipRecipeDesc"]           = "De naam van het te maken item of spell."
L["TooltipCraftersTitle"]        = "Crafters"
L["TooltipCraftersDesc"]         = "Guildleden die dit recept kennen. Klik op een recept voor de volledige lijst."
L["CraftersColHeader"]           = "Crafters"
L["TooltipBankTitle"]            = "Aanvragen bij bank"
L["TooltipBankDescScroll"]       = "Stuurt een verzoek naar een TOGBankClassic-guildbankier voor deze receptrol."
L["TooltipBankDescGeneric"]      = "Stuurt een verzoek naar een TOGBankClassic-guildbankier."
L["TooltipAHTitle"]              = "Zoek in Auction House"
L["TooltipAHDescScroll"]         = "Opent deze receptrol in de AH-zoekfunctie."
L["TooltipAHDescReagent"]        = "Opent deze reagent in de AH-zoekfunctie."
L["TooltipSettingsTitle"]        = "Instellingen"
L["TooltipSettingsDesc"]         = "Opent het instellingenscherm van TOG Profession Master (|cffffd700ESC > Opties > AddOns > TOG Profession Master|r). Hetzelfde doel als |cffffd700/togpm settings|r en Shift+linkermuisknop op de minimapknop."
L["TooltipWhisperRightClick"]    = "Rechterklik om te whisperen"
L["TooltipClickTransmutes"]      = "Klik om transmutaties te bekijken"
L["TooltipClickDetailsFormat"]   = "Klik om %s te bekijken"
L["TooltipClickDetailsFallback"] = "details"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Cooldown-bevoorrading: %s"
L["MailBodyFormat"]         = "Hallo %s! Zou je deze materialen willen gebruiken om %s te maken wanneer je tijd hebt? Bedankt!"
L["MailMsgNoEmptyBag"]      = "Geen lege plek meer in je tassen om te splitsen."
L["MailMsgOpenMailbox"]     = "Open eerst een brievenbus."
L["MailMsgHasItems"]        = "Post heeft al items bijgevoegd — verstuur of verwijder ze eerst."
L["MailMsgCannotFulfill"]   = "Kan niet voltooien."
L["MailMsgCouldNotAttach"]  = "Kan items niet bijvoegen."
L["MailMsgAttachedFormat"]  = "%dx %s voor %s bijgevoegd."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Linkerklik|r om professionzoekmachine in / uit te schakelen"
L["MinimapTooltipRightClick"]  = "|cffffd100Rechterklik|r om reagents in / uit te schakelen"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+links|r opent instellingen"
L["MinimapButtonShown"]        = "Minimapknop getoond."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- commando-namen worden niet vertaald
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — commando's:"
L["SlashHelpOpen"]          = "open professionzoekmachine"
L["SlashHelpReagents"]      = "open ontbrekende reagents"
L["SlashHelpMinimap"]       = "toon minimapknop"
L["SlashHelpPurge"]         = "open wisdialoog"
L["SlashHelpSync"]          = "forceer volledige gilde-hersynchronisatie"
L["SlashHelpStatus"]        = "dump sync/comm-diagnose-informatie"
L["SlashHelpVersionCheck"]  = "controleer addon-versies in de guild"
L["SlashHelpDebug"]         = "schakel debug-uitvoer in / uit"
L["SlashHelpHelp"]          = "toon deze lijst"
L["SlashForceSyncSent"]     = "Geforceerde synchronisatie verzonden."
L["AHScannerOpenAH"]        = "Open de auction house om te zoeken."
L["AHOpenFirst"]            = "Open eerst de auction house."
L["AHNoItemsToScan"]        = "Geen items om te scannen in de huidige weergave."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Aanvraag bij guildbank"
L["BankDialogBanker"]       = "Bankier:"
L["BankDialogQty"]          = "Aantal:"
L["BankDialogSend"]         = "Verzoek versturen"
L["BankDialogCancel"]       = "Annuleren"

-- ---------------------------------------------------------------------------
-- Wissingsbevestigingen en andere commando-uitvoer
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Alle guildgegevens gewist."
L["MsgOwnDataPurged"]        = "Je personagegegevens gewist."
L["SlashForceBroadcastSent"] = "Geforceerde broadcast verzonden."
L["SlashDebugEnabled"]       = "|cff00ff00ingeschakeld|r"
L["SlashDebugDisabled"]      = "|cffff4444uitgeschakeld|r"
L["SlashDebugToggleFormat"]  = "Debug-uitvoer %s"

-- ---------------------------------------------------------------------------
-- Beroepsnamen (alle 15 — community-vertaling, native-speaker review welkom)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alchemy"
L["ProfBlacksmithing"]  = "Blacksmithing"
L["ProfCooking"]        = "Cooking"
L["ProfEnchanting"]     = "Enchanting"
L["ProfEngineering"]    = "Engineering"
L["ProfFirstAid"]       = "First Aid"
L["ProfLeatherworking"] = "Leatherworking"
L["ProfMining"]         = "Mining"
L["ProfTailoring"]      = "Tailoring"
L["ProfHerbalism"]      = "Herbalism"
L["ProfSkinning"]       = "Skinning"
L["ProfJewelcrafting"]  = "Jewelcrafting"
L["ProfInscription"]    = "Inscription"
L["ProfFishing"]        = "Fishing"
L["ProfSmelting"]       = "Smelting"

-- ---------------------------------------------------------------------------
-- Crafting tab (added in v0.8.0) -- TODO: translate (English fallback for now)
-- ---------------------------------------------------------------------------
L["TabCrafting"]        = "Crafting"
L["CraftOpenAProfession"] = "Open a profession to craft."
L["CraftBlizzardUI"]      = "WoW UI"
L["CraftScanAH"]          = "Scan AH"
L["CraftScanAHProgress"]  = "%d/%d"
L["CraftScanAHDesc"]      = "Scan the Auction House for the selected recipe's reagents. Afterwards, an [AH] button appears next to each reagent that's for sale. Open the Auction House first."
L["CraftScanAHNoItems"]   = "Select a recipe first to scan its reagents."
L["CraftHaveMaterials"]   = "Have Materials"
L["CraftCostLabel"]       = "Crafting Cost"
L["CraftCostDesc"]        = "Estimated material cost for one craft: each reagent priced from the Auction House (Auctionator if installed, otherwise TOGPM's own AH scan) or vendor. \"*\" means one or more reagents had no price yet, so the total is a lower bound. \"~\" means a price is stale (>14 days)."
L["CraftCostNone"]        = "—"
L["CraftColCostHdr"]      = "Cost"
L["CraftColCostHdrDesc"]  = "Per-reagent cost: the price for the quantity this recipe needs (unit price × needed). Priced from the Auction House (Auctionator if enabled, else TOGPM's own scan) or vendor; \"—\" when no price is known yet."
L["CraftSearchDesc"]      = "Filter recipes by name or by what they do. Searches the enriched effect text too, so \"5 damage\", \"agility\", or \"mining\" all find matching recipes."
L["CraftColRecipe"]       = "Recipe Name"
L["CraftColRecipeDesc"]   = "The recipes you can make in this profession. Colour shows skill-up difficulty (orange/yellow/green/grey)."
L["CraftColCount"]        = "Craft"
L["CraftColCountDesc"]    = "How many you can craft right now with the materials on hand."
L["CraftColSkill"]        = "Skill"
L["CraftSortHint"]        = "Click to sort. Click again to reverse, once more to return to categories."
L["CraftNoRecipes"]       = "No recipes match."
L["CraftSelectRecipe"]    = "Select a recipe to see its reagents."
L["CraftReagents"]        = "Reagents"
L["CraftQuantity"]        = "Qty"
L["CraftMax"]             = "Max"
L["CraftMissingMaterials"] = "Missing Materials"
L["CraftBankReagentDesc"] = "A guild-bank character has this reagent. Click to request it."
L["CraftAHReagentDesc"]   = "The Auction House has this reagent (from your last scan). Click to search for it."
L["CraftReagentsDesc"]    = "Materials required to craft the selected recipe. The number is how many you have vs. how many you need; red means you're short."
L["CraftMissingMaterialsDesc"] = "Appears when you don't have enough of at least one reagent to craft this recipe."
L["CraftQueueHeaderTitle"] = "Queue"
L["CraftQueueHeaderDesc"]  = "Recipes you've queued to craft, in priority order. Drag rows to reorder; Craft Next makes the top one you can craft right now."
L["CraftHaveMaterialsDesc"] = "Show only recipes you can make right now with the materials on hand."
L["CraftButton"]          = "Craft"
L["CraftNoProfessions"]   = "You don't have any professions."
L["CraftProfessionDesc"]  = "Choose one of your professions. Selecting it opens that profession so you can craft."
L["CraftOpenToView"]      = "Open %s to view and craft its recipes."
L["CraftOpenButton"]      = "Open %s"
L["CraftCantOpenInCombat"] = "Can't open a profession while in combat."
L["CraftQueueTitle"]      = "Queue (%d)"
L["CraftQueueButton"]     = "Queue"
L["CraftCraftNext"]       = "Craft Next"
L["CraftClearAll"]        = "Clear All"
L["CraftMaxDesc"]         = "Set quantity to the most you can make with materials on hand."
L["CraftIncrease"]        = "Increase quantity"
L["CraftDecrease"]        = "Decrease quantity"
L["CraftButtonDesc"]      = "Craft the selected recipe now."
L["CraftQueueDesc"]       = "Add the selected recipe to the queue."
L["SettingsUseAuctionator"]                = "Use Auctionator pricing"
