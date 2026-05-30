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
-- Translation note (native-speaker reviewed): Dutch isn't an official WoW
-- language, so Dutch players use the ENGLISH terms for core game mechanics.
-- We therefore keep these in English even inside Dutch sentences: profession
-- names, reagent names (Mooncloth, Icy Prism, ...), Auction House / AH, Guild,
-- Cooldown, Reagent, Profession, Transmute, Item, Daily. "Watch" is rendered
-- as "in de gaten houden", and a character is a "poppetje".

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
L["ViewMine"]           = "Mijn poppetjes"
L["AllProfessions"]     = "Alle professions"
L["PanelProfessions"]   = "Professions"
L["PanelCharacters"]    = "Poppetjes"
L["SelectProfession"]   = "Kies een profession"
L["NoDataYet"]          = "|cffaaaaaa(nog geen gegevens)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Kies een profession om te zien wie het kent.|r"
L["NoProfMembers"]      = "|cffaaaaaa(geen Guild-leden met deze profession)|r"
L["BackToCharacters"]   = "|cff00aaff← Terug naar poppetjes|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(geen overeenkomende recepten)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Jij"
L["BrowserScanAH"]          = "AH scannen"
L["BrowserScanAHProgress"]  = "Scannen %d/%d"
L["BrowserScanAHDesc"]      = "Scan het Auction House op elk reagent in je boodschappenlijst. Rijen waarvan het reagent momenteel in het AH staat krijgen een [AH]-knop; klik daarop om direct naar het AH-zoekresultaat te springen."
L["CooldownsScanAHDesc"]    = "Scan het Auction House op elk uniek reagent in de zichtbare Cooldown-rijen. Rijen waarvan het reagent momenteel in het AH staat krijgen een [AH]-knop (links van [Bank]); klik daarop om direct naar het zoekresultaat te springen."

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
L["FilterProfessionDesc"]   = "Filter de Cooldown-lijst op één profession (Alchemy, Tailoring, enz.)."
L["FilterCooldownDesc"]     = "Filter binnen de gekozen profession op één gedeelde Cooldown (bijv. Transmute, Mooncloth)."
L["FilterViewDesc"]         = "Wissel tussen de Cooldowns van alle Guild-leden en alleen je eigen poppetjes."
L["AllCooldowns"]           = "Alle Cooldowns"
L["FilterTransmute"]            = "Transmute"
L["FilterAlchResearch"]         = "Alchemy Research"
L["FilterMooncloth"]            = "Mooncloth"
L["FilterSpecialtyCloth"]       = "Specialty Cloth"
L["FilterGlacialBag"]           = "Glacial Bag"
L["FilterDreamcloth"]           = "Dreamcloth"
L["FilterImperialSilk"]         = "Imperial Silk"
L["FilterSaltShaker"]           = "Salt Shaker"
L["FilterMagicSphere"]          = "Magic Sphere"
L["FilterShaCrystal"]           = "Sha Crystal"
L["FilterBrilliantGlass"]       = "Brilliant Glass"
L["FilterIcyPrism"]             = "Icy Prism"
L["FilterFirePrism"]            = "Fire Prism"
L["FilterJcDaily"]              = "Jewelcrafting Daily"
L["FilterInscriptionResearch"]  = "Inscription Research"
L["FilterForgedDocuments"]      = "Forged Documents"
L["FilterScrollOfWisdom"]       = "Scroll of Wisdom"
L["FilterTitansteelBar"]        = "Titansteel Bar"
L["FilterBsIngot"]              = "Smelting"
L["FilterMagnificence"]         = "Magnificence"
L["FilterJards"]                = "Jard's Energy"
L["ColCharacter"]           = "Poppetje"
L["ColCooldown"]            = "Cooldown"
L["ColReagent"]             = "Reagent"
L["ColTimeLeft"]            = "Resterende tijd"
L["NoCooldownData"]         = "|cffaaaaaa(nog geen Cooldown-gegevens — open een profession-venster)|r"
L["Ready"]                  = "|cff00ff00Klaar|r"
L["Transmute"]              = "Transmute"
L["MailBtn"]                = "Post"
L["MailBtnTooltip"]         = "Bevoorradingspost versturen"
L["MailBtnTooltipDesc"]     = "Open een brievenbus en klik dan om reagents bij te voegen en een bevoorradingsbericht aan deze speler op te stellen."
L["BankBtn"]                = "[Bank]"
L["CloseBtn"]               = "Sluiten"

-- Profession-specialisatie-bonusoutputindicator
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
L["ReagentWatchEmpty"]      = "|cffaaaaaa(geen items in de gaten aan het houden - voer hierboven een item-id of link in)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch-module niet geladen)|r"
L["WatchInputLabel"]        = "Item-ID of link"
L["WatchBtn"]               = "In de gaten houden"
L["WatchedItemsHeading"]    = "Items die je in de gaten houdt"
L["ColHave"]                = "Heb"
L["ColNeed"]                = "Nodig"
L["ColShort"]               = "Tekort"
L["ColItem"]                = "Item"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Poppetje|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Profession|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Zoek recepten…|r"
L["MissingIncludeTrainer"]      = "Alleen-trainer opnemen"
L["MissingIncludeTrainerDesc"]  = "Voegt recepten toe die alleen bij een trainer geleerd kunnen worden (geen AH-rol)."
L["MissingScanAH"]              = "AH scannen"
L["MissingScanAHProgress"]      = "Scannen %d/%d (klik om te annuleren)"
L["MissingScanAHDesc"]          = "Open het Auction House en klik dan om elke receptrol in de zichtbare lijst te scannen. Rijen met actieve aanbiedingen krijgen een [AH]-knop; klik daarop om direct naar het zoekresultaat te springen."
L["MissingNoCharacters"]        = "|cffaaaaaa(nog geen poppetjes met profession-gegevens — open een profession-venster)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(dit poppetje heeft nog geen geregistreerde professions — open een profession-venster)|r"
L["MissingNoneFound"]           = "|cff00ff00Alle bekende recepten voor deze profession zijn geleerd.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Kies een profession om te zien wat ontbreekt.|r"
L["MissingNoData"]              = "|cffff8888(geen receptgegevens beschikbaar voor deze profession)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Recept"
L["MissingColSkill"]            = "Skill"
L["MissingColSource"]           = "Bronnen"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Houd deze receptrol in de gaten"
L["MissingAddToWatchDesc"]      = "Voegt de receptrol toe aan je 'in de gaten houden'-lijst zodat je hem ziet zodra hij in je tassen terechtkomt."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Wordt al in de gaten gehouden — klik om te stoppen"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Ontbrekend recept"
L["MissingCountPlural"]         = "Ontbrekende recepten"
L["MissingTruncatedHint"]       = "(toont de eerste %d — typ in het zoekvak om de lijst te beperken)"
L["MissingCharTooltipTitle"]    = "Poppetje-filter"
L["MissingCharTooltipDesc"]     = "Kies voor welk van je poppetjes ontbrekende recepten getoond worden. Standaard het momenteel ingelogde poppetje."
L["MissingProfTooltipTitle"]    = "Profession-filter"
L["MissingProfTooltipDesc"]     = "Kies een profession om de rollen te zien die dit poppetje nog niet heeft geleerd."
L["MissingSearchTooltipTitle"]  = "Zoek recepten"
L["MissingSearchTooltipDesc"]   = "Typ om de lijst met ontbrekende recepten op naam te filteren."
L["MissingHdrCountTitle"]       = "Ontbrekende recepten"
L["MissingHdrCountDesc"]        = "Recepten die het gekozen poppetje nog niet heeft geleerd maar wel verkrijgbaar zijn in deze versie van het spel. Het aantal weerspiegelt het huidige filter (profession, zoekopdracht, trainer-schakelaar)."
L["MissingHdrSkillTitle"]       = "Skill-niveau"
L["MissingHdrSkillDesc"]        = "Het vereiste profession-skillniveau om dit recept te leren. Grijze rijen betekenen dat het poppetje nog niet hoog genoeg is."
L["MissingHdrSourceTitle"]      = "Bronnen"
L["MissingHdrSourceDesc"]       = "Hoe je dit recept verkrijgt — trainer, drop, vendor, queeste of vervaardigd. Beweeg de muis over de bronnentekst van een rij voor de specifieke NPC / monster / stap."
L["MissingRowTooltipShift"]     = "Shift-klik om in de chat te linken."
L["MissingSrcVendor"]           = "Vendor"
L["MissingSrcDrop"]             = "Drop"
L["MissingSrcQuest"]            = "Queeste"
L["MissingSrcCrafted"]          = "Vervaardigd"
L["MissingSrcFishing"]          = "Fishing"
L["MissingSrcContainer"]        = "Container"
L["MissingSrcTrainer"]          = "Trainer"
L["MissingSrcOther"]            = "Overig"
L["MissingSrcUnknown"]          = "Onbekend"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Item-tooltip"
L["SettingsTooltipShowCrafters"]    = "Toon Guild-vervaardigers in item-tooltips"
L["SettingsTooltipShowCraftersDesc"]= "Voegt een [TOGPM]-regel toe met alle Guild-genoten die het item waarover je zweeft kunnen maken. Online in wit, offline in grijs. Bij-oppakken-gebonden items worden overgeslagen (toch niet verhandelbaar)."
L["SettingsTooltipShowIds"]         = "Toon item-ID / spell-ID in tooltips"
L["SettingsTooltipShowIdsDesc"]     = "Voegt een [TOGPM]-regel toe met het item-ID en (indien bekend) het spell-ID van het recept. Vooral nuttig voor het diagnosticeren van verkeerde iconen of ontbrekende recepten — plak de ID's in Wowhead om de overeenkomst te verifiëren."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "TBC Anniversary-fase"
L["SettingsTBCPhase"]           = "Huidige inhoudsfase"
L["SettingsTBCPhaseDesc"]       = "Verbergt ontbrekende recepten uit fases later dan de huidige Anniversary-fase. Verhoog deze waarde telkens als Blizzard de fase vooruitschuift. (Recepten die al toegankelijk zijn in de actieve fase blijven zichtbaar.)"
L["SettingsTBCPhase1"]          = "Fase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Fase 2 — Serpentshrine Cavern / Tempest Keep"
L["SettingsTBCPhase3"]          = "Fase 3 — Black Temple / Mount Hyjal"
L["SettingsTBCPhase4"]          = "Fase 4 — Sunwell / Magisters' Terrace"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Weergave"
L["SettingsMinimapBtn"]          = "Toon minimapknop"
L["SettingsMinimapBtnDesc"]      = "Toont of verbergt de starter-knop op de minimap."
L["SettingsPersistProfFilter"]     = "Onthoud profession-filter"
L["SettingsPersistProfFilterDesc"] = "Herstelt de geselecteerde profession bij inloggen of herladen."
L["SettingsCooldownsHeader"]= "Cooldowns"
L["SettingsMailReadyOnly"]  = "Post: toon alleen klare Cooldowns"
L["SettingsMailReadyOnlyDesc"] = "Bij het opstellen van bevoorradingspost vanuit het Cooldown-paneel, toon alleen Guild-leden waarvan de Cooldown klaar is."
L["SettingsDevHeader"]      = "Ontwikkelaar"
L["SettingsDebug"]          = "Debug-uitvoer"
L["SettingsDebugDesc"]      = "Drukt gedetailleerde debugberichten af in het chatvenster."
L["SettingsDataHeader"]     = "Gegevens"
L["SettingsSyncNow"]        = "Forceer hersynchronisatie"
L["SettingsSyncNowDesc"]    = "Zendt je profession-gegevens onmiddellijk uit naar de Guild."
L["SettingsPurgeGuild"]     = "Wis alle Guild-gegevens"
L["SettingsPurgeGuildDesc"] = "Verwijdert alle opgeslagen profession- en Cooldown-gegevens voor elk Guild-lid op dit account. Kan niet ongedaan gemaakt worden."
L["SettingsPurgeGuildConfirm"] = "ALLE Guild-gegevens voor dit account verwijderen?"
L["SettingsPurgeMine"]      = "Wis mijn poppetje-gegevens"
L["SettingsPurgeMineDesc"]  = "Verwijdert alleen de opgeslagen gegevens van je eigen poppetje uit de Guild-database."
L["SettingsPurgeMineConfirm"] = "Je eigen profession- en Cooldown-gegevens verwijderen?"
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
L["ShoppingAlertEnable"]               = "Activeer vervaardigerwaarschuwing voor dit recept"
L["ShoppingAlertDisable"]              = "Deactiveer vervaardigerwaarschuwing voor dit recept"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s is online — kan maken: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s is online (alt van %s) — kan maken: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Activeer klaar-waarschuwing voor deze Cooldown"
L["CooldownAlertDisable"]              = "Deactiveer klaar-waarschuwing voor deze Cooldown"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Cooldown klaar: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Vervaardigerwaarschuwingen"
L["SettingsCrafterAlert"]              = "Activeer vervaardigerwaarschuwingen"
L["SettingsCrafterAlertDesc"]          = "Speelt een geluid af en laat het scherm knipperen wanneer een Guild-lid dat een gewaarschuwd boodschappenlijst-item kan maken online komt."
L["SettingsCrafterAlertSuppressAV"]    = "Onderdruk geluid en knipperen"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Deactiveert audio-effecten en schermknippering (chatbericht verschijnt wel)."
L["SettingsCrafterAlertSuppressLogin"]     = "Onderdruk waarschuwingen bij inloggen"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Geen waarschuwingen activeren tijdens de initiële stroom van online-meldingen bij inloggen of herladen."
L["SettingsCooldownAlertSuppressProtected"]     = "Dempt waarschuwingen in instances"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Geen geluid of weergave van Cooldown-klaar-waarschuwingen terwijl je in een raid, dungeon, slagveld, arena of scenario bent. Hoofdsteden worden NIET gedempt — je Transmute blijft pingen terwijl je AFK staat in Stormwind. Wachtende waarschuwingen vuren af zodra je de instance verlaat."
L["SettingsCooldownReminderInterval"]      = "Cooldown-klaar herinnering"
L["SettingsCooldownReminderIntervalDesc"]  = "Vuurt elke geactiveerde Cooldown-waarschuwing opnieuw af elke N minuten zolang de Cooldown klaar blijft (d.w.z. totdat je daadwerkelijk maakt). Voer 0, leeg of 'off' in om slechts één keer per klaar-cyclus af te vuren. Geldig bereik: 1–1440 minuten (24 uur)."
L["SettingsCooldownReminderInvalid"]       = "Voer een geheel getal in van 0 tot 1440, of 'off'."

L["SettingsAHHeader"]                      = "Auction House"
L["SettingsAHScanDelay"]                   = "AH-scanvertraging (seconden)"
L["SettingsAHScanDelayDesc"]               = "Seconden tussen AH-scanverzoeken. Leeg / 0 / 'off' gebruikt de versiestandaard (1,5s op Classic Era en Anniversary; 3,0s op TBC, Wrath, Cata, MoP — die servers beperken strenger). Verlaag voor snellere scans, verhoog als scans vastlopen. Geldig bereik: 0,5–10 seconden."
L["SettingsAHScanDelayInvalid"]            = "Voer een getal in van 0,5 tot 10, of 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Recept"
L["TooltipRecipeDesc"]           = "De naam van het te vervaardigen item of de spell."
L["TooltipCraftersTitle"]        = "Vervaardigers"
L["TooltipCraftersDesc"]         = "Guild-leden die dit recept kennen. Klik op een recept voor de volledige lijst."
L["CraftersColHeader"]           = "Vervaardigers"
L["TooltipBankTitle"]            = "Aanvragen bij bank"
L["TooltipBankDescScroll"]       = "Stuurt een verzoek naar een TOGBankClassic-Guild-bankier voor deze receptrol."
L["TooltipBankDescGeneric"]      = "Stuurt een verzoek naar een TOGBankClassic-Guild-bankier."
L["TooltipAHTitle"]              = "Zoek in Auction House"
L["TooltipAHDescScroll"]         = "Opent deze receptrol in de AH-zoekfunctie."
L["TooltipAHDescReagent"]        = "Opent dit reagent in de AH-zoekfunctie."
L["TooltipSettingsTitle"]        = "Instellingen"
L["TooltipSettingsDesc"]         = "Opent het instellingenpaneel van TOG Profession Master (|cffffd700ESC > Opties > AddOns > TOG Profession Master|r). Hetzelfde doel als |cffffd700/togpm settings|r en Shift+linkermuisknop op de minimapknop."
L["TooltipWhisperRightClick"]    = "Rechterklik om te fluisteren"
L["TooltipClickTransmutes"]      = "Klik om transmutes te bekijken"
L["TooltipClickDetailsFormat"]   = "Klik om %s te bekijken"
L["TooltipClickDetailsFallback"] = "details"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Cooldown-bevoorrading: %s"
L["MailBodyFormat"]         = "Hallo %s! Gebruik deze materialen om %s te maken. Stuur me de %s wanneer je tijd hebt om het te maken. Bedankt!"
L["MailMsgNoEmptyBag"]      = "Geen lege tasvak om te splitsen."
L["MailMsgOpenMailbox"]     = "Open eerst een brievenbus."
L["MailMsgHasItems"]        = "Post heeft al items bijgevoegd — verstuur of verwijder ze eerst."
L["MailMsgCannotFulfill"]   = "Kan niet voltooien."
L["MailMsgCouldNotAttach"]  = "Kan items niet bijvoegen."
L["MailMsgAttachedFormat"]  = "%dx %s voor %s bijgevoegd."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Linkerklik|r om profession-browser te schakelen"
L["MinimapTooltipRightClick"]  = "|cffffd100Rechterklik|r om reagents te schakelen"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+links|r opent instellingen"
L["MinimapButtonShown"]        = "Minimapknop getoond."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- commando-namen worden niet vertaald
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — commando's:"
L["SlashHelpOpen"]          = "open profession-browser"
L["SlashHelpReagents"]      = "open ontbrekende reagents"
L["SlashHelpMinimap"]       = "toon minimapknop"
L["SlashHelpPurge"]         = "open wisdialoog"
L["SlashHelpSync"]          = "forceer volledige Guild-hersynchronisatie"
L["SlashHelpStatus"]        = "dump sync/comm-diagnose-informatie"
L["SlashHelpVersionCheck"]  = "controleer addon-versies in de Guild"
L["SlashHelpDebug"]         = "schakel debug-uitvoer"
L["SlashHelpHelp"]          = "toon deze lijst"
L["SlashForceSyncSent"]     = "Forced sync verzonden."
L["AHScannerOpenAH"]        = "Open het Auction House om te zoeken."
L["AHOpenFirst"]            = "Open eerst het Auction House."
L["AHNoItemsToScan"]        = "Geen items om te scannen in de huidige weergave."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Aanvraag bij Guild-bank"
L["BankDialogBanker"]       = "Bankier:"
L["BankDialogQty"]          = "Aantal:"
L["BankDialogSend"]         = "Verzoek versturen"
L["BankDialogCancel"]       = "Annuleren"

-- ---------------------------------------------------------------------------
-- Wissingsbevestigingen en andere commando-uitvoer
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Alle Guild-gegevens gewist."
L["MsgOwnDataPurged"]        = "Je poppetje-gegevens gewist."
L["SlashForceBroadcastSent"] = "Forced broadcast verzonden."
L["SlashDebugEnabled"]       = "|cff00ff00ingeschakeld|r"
L["SlashDebugDisabled"]      = "|cffff4444uitgeschakeld|r"
L["SlashDebugToggleFormat"]  = "Debug-uitvoer %s"

-- ---------------------------------------------------------------------------
-- Profession-namen — Dutch players use the ENGLISH profession names in-game.
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
