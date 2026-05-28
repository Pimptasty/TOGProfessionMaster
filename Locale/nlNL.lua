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
L["TabProfessions"]     = "Beroepen"
L["TabCooldowns"]       = "Hersteltijden"
L["TabReagents"]        = "Ingrediënten"
L["TabMissingRecipes"]  = "Ontbrekende recepten"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Zoek recepten…"
L["ViewGuild"]          = "Gilde"
L["ViewMine"]           = "Mijn personages"
L["AllProfessions"]     = "Alle beroepen"
L["PanelProfessions"]   = "Beroepen"
L["PanelCharacters"]    = "Personages"
L["SelectProfession"]   = "Kies een beroep"
L["NoDataYet"]          = "|cffaaaaaa(nog geen gegevens)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Kies een beroep om te zien wie het kent.|r"
L["NoProfMembers"]      = "|cffaaaaaa(geen gildeleden met dit beroep)|r"
L["BackToCharacters"]   = "|cff00aaff← Terug naar personages|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(geen overeenkomende recepten)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Jij"
L["BrowserScanAH"]          = "VH scannen"
L["BrowserScanAHProgress"]  = "Scannen %d/%d"
L["BrowserScanAHDesc"]      = "Scan het veilinghuis op elk ingrediënt in je boodschappenlijst. Rijen waarvan het ingrediënt momenteel in het VH staat krijgen een [VH]-knop; klik daarop om direct naar het VH-zoekresultaat te springen."
L["CooldownsScanAHDesc"]    = "Scan het veilinghuis op elk uniek ingrediënt in de zichtbare hersteltijdrijen. Rijen waarvan het ingrediënt momenteel in het VH staat krijgen een [VH]-knop (links van [Bank]); klik daarop om direct naar het zoekresultaat te springen."

-- Recipe detail popup
L["PopupCrafters"]       = "Gekend door"
L["PopupOnList"]         = "Op boodschappenlijst"
L["PopupNotOnList"]      = "Niet op boodschappenlijst"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Alleen klaar"
L["ShowAll"]                = "Alle"
L["FilterColProfession"]    = "Beroep"
L["FilterColCooldown"]      = "Hersteltijd"
L["FilterColView"]          = "Weergave"
L["FilterProfessionDesc"]   = "Filter de hersteltijdlijst op één beroep (Alchemie, Kleermakerij, enz.)."
L["FilterCooldownDesc"]     = "Filter binnen het gekozen beroep op één gedeelde hersteltijd (bijv. Transmutatie, Maanstof)."
L["FilterViewDesc"]         = "Wissel tussen de hersteltijden van alle gildeleden en alleen je eigen personages."
L["AllCooldowns"]           = "Alle hersteltijden"
L["FilterTransmute"]            = "Transmutatie"
L["FilterAlchResearch"]         = "Alchemie-onderzoek"
L["FilterMooncloth"]            = "Maanstof"
L["FilterSpecialtyCloth"]       = "Specialiteitsstof"
L["FilterGlacialBag"]           = "Gletsjertas"
L["FilterDreamcloth"]           = "Droomstof"
L["FilterImperialSilk"]         = "Keizerlijke zijde"
L["FilterSaltShaker"]           = "Zoutvaatje"
L["FilterMagicSphere"]          = "Magische bol"
L["FilterShaCrystal"]           = "Sha-kristal"
L["FilterBrilliantGlass"]       = "Schitterend glas"
L["FilterIcyPrism"]             = "IJzig prisma"
L["FilterFirePrism"]            = "Vuurprisma"
L["FilterJcDaily"]              = "Edelsmederij dagelijkse slijping"
L["FilterInscriptionResearch"]  = "Inscriptie-onderzoek"
L["FilterForgedDocuments"]      = "Vervalste documenten"
L["FilterScrollOfWisdom"]       = "Rol der Wijsheid"
L["FilterTitansteelBar"]        = "Titaanstaalstaaf"
L["FilterBsIngot"]              = "Smelten"
L["FilterMagnificence"]         = "Pracht"
L["FilterJards"]                = "Jard's energie"
L["ColCharacter"]           = "Personage"
L["ColCooldown"]            = "Hersteltijd"
L["ColReagent"]             = "Ingrediënt"
L["ColTimeLeft"]            = "Resterende tijd"
L["NoCooldownData"]         = "|cffaaaaaa(nog geen hersteltijdgegevens — open een beroepenvenster)|r"
L["Ready"]                  = "|cff00ff00Klaar|r"
L["Transmute"]              = "Transmutatie"
L["MailBtn"]                = "Post"
L["MailBtnTooltip"]         = "Bevoorradingspost versturen"
L["MailBtnTooltipDesc"]     = "Open een brievenbus en klik dan om ingrediënten bij te voegen en een bevoorradingsbericht aan deze speler op te stellen."
L["BankBtn"]                = "[Bank]"
L["CloseBtn"]               = "Sluiten"

-- Beroepsspecialisatie-bonusoutputindicator
L["SpecBonusGuaranteedDouble"]  = "Gegarandeerde 2x opbrengst"
L["SpecBonusProcChance"]        = "Kans op extra opbrengst"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Boodschappenlijst"
L["SectionMissingReagents"] = "Ontbrekende ingrediënten"
L["SectionReagentWatch"]    = "Ingrediëntenbewaking"
L["ShoppingListEmpty"]      = "|cffaaaaaa(leeg — klik op een receptrij in het tabblad Beroepen om voorwerpen aan je boodschappenlijst toe te voegen)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(de boodschappenlijst is leeg of alle ingrediënten zitten in je tassen)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(geen bewaakte voorwerpen — voer hierboven een voorwerp-ID of link in)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch-module niet geladen)|r"
L["WatchInputLabel"]        = "Voorwerp-ID of link"
L["WatchBtn"]               = "Bewaken"
L["WatchedItemsHeading"]    = "Bewaakte voorwerpen"
L["ColHave"]                = "Heb"
L["ColNeed"]                = "Nodig"
L["ColShort"]               = "Tekort"
L["ColItem"]                = "Voorwerp"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Personage|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Beroep|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Zoek recepten…|r"
L["MissingIncludeTrainer"]      = "Alleen-trainer opnemen"
L["MissingIncludeTrainerDesc"]  = "Voegt recepten toe die alleen bij een trainer geleerd kunnen worden (geen VH-rol)."
L["MissingScanAH"]              = "VH scannen"
L["MissingScanAHProgress"]      = "Scannen %d/%d (klik om te annuleren)"
L["MissingScanAHDesc"]          = "Open het veilinghuis en klik dan om elke receptrol in de zichtbare lijst te scannen. Rijen met actieve aanbiedingen krijgen een [VH]-knop; klik daarop om direct naar het zoekresultaat te springen."
L["MissingNoCharacters"]        = "|cffaaaaaa(nog geen personages met beroepsgegevens — open een beroepenvenster)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(dit personage heeft nog geen geregistreerde beroepen — open een beroepenvenster)|r"
L["MissingNoneFound"]           = "|cff00ff00Alle bekende recepten voor dit beroep zijn geleerd.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Kies een beroep om te zien wat ontbreekt.|r"
L["MissingNoData"]              = "|cffff8888(geen receptgegevens beschikbaar voor dit beroep)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Recept"
L["MissingColSkill"]            = "Vaardigheid"
L["MissingColSource"]           = "Bronnen"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Bewaak deze receptrol"
L["MissingAddToWatchDesc"]      = "Voegt de receptrol toe aan je ingrediëntenbewakingslijst zodat je hem ziet zodra hij in je tassen terechtkomt."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Al bewaakt — klik om te stoppen met bewaken"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Ontbrekend recept"
L["MissingCountPlural"]         = "Ontbrekende recepten"
L["MissingTruncatedHint"]       = "(toont de eerste %d — typ in het zoekvak om de lijst te beperken)"
L["MissingCharTooltipTitle"]    = "Personagefilter"
L["MissingCharTooltipDesc"]     = "Kies voor welk van je personages ontbrekende recepten getoond worden. Standaard het momenteel ingelogde personage."
L["MissingProfTooltipTitle"]    = "Beroepsfilter"
L["MissingProfTooltipDesc"]     = "Kies een beroep om de rollen te zien die dit personage nog niet heeft geleerd."
L["MissingSearchTooltipTitle"]  = "Zoek recepten"
L["MissingSearchTooltipDesc"]   = "Typ om de lijst met ontbrekende recepten op naam te filteren."
L["MissingHdrCountTitle"]       = "Ontbrekende recepten"
L["MissingHdrCountDesc"]        = "Recepten die het gekozen personage nog niet heeft geleerd maar wel verkrijgbaar zijn in deze versie van het spel. Het aantal weerspiegelt het huidige filter (beroep, zoekopdracht, trainer-schakelaar)."
L["MissingHdrSkillTitle"]       = "Vaardigheidsniveau"
L["MissingHdrSkillDesc"]        = "Het vereiste beroepsvaardigheidsniveau om dit recept te leren. Grijze rijen betekenen dat het personage nog niet hoog genoeg is."
L["MissingHdrSourceTitle"]      = "Bronnen"
L["MissingHdrSourceDesc"]       = "Hoe je dit recept verkrijgt — trainer, drop, handelaar, queeste of vervaardigd. Beweeg de muis over de bronnentekst van een rij voor de specifieke NPC / monster / stap."
L["MissingRowTooltipShift"]     = "Shift-klik om in de chat te linken."
L["MissingSrcVendor"]           = "Handelaar"
L["MissingSrcDrop"]             = "Drop"
L["MissingSrcQuest"]            = "Queeste"
L["MissingSrcCrafted"]          = "Vervaardigd"
L["MissingSrcFishing"]          = "Vissen"
L["MissingSrcContainer"]        = "Container"
L["MissingSrcTrainer"]          = "Trainer"
L["MissingSrcOther"]            = "Overig"
L["MissingSrcUnknown"]          = "Onbekend"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Voorwerptooltip"
L["SettingsTooltipShowCrafters"]    = "Toon gildevervaardigers in voorwerptooltips"
L["SettingsTooltipShowCraftersDesc"]= "Voegt een [TOGPM]-regel toe met alle gildegenoten die het voorwerp waarover je zweeft kunnen maken. Online in wit, offline in grijs. Bij-oppakken-gebonden voorwerpen worden overgeslagen (toch niet verhandelbaar)."
L["SettingsTooltipShowIds"]         = "Toon voorwerp-ID / spreuk-ID in tooltips"
L["SettingsTooltipShowIdsDesc"]     = "Voegt een [TOGPM]-regel toe met het voorwerp-ID en (indien bekend) het spreuk-ID van het recept. Vooral nuttig voor het diagnosticeren van verkeerde iconen of ontbrekende recepten — plak de ID's in Wowhead om de overeenkomst te verifiëren."

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
L["SettingsPersistProfFilter"]     = "Onthoud beroepsfilter"
L["SettingsPersistProfFilterDesc"] = "Herstelt het geselecteerde beroep bij inloggen of herladen."
L["SettingsCooldownsHeader"]= "Hersteltijden"
L["SettingsMailReadyOnly"]  = "Post: toon alleen klare hersteltijden"
L["SettingsMailReadyOnlyDesc"] = "Bij het opstellen van bevoorradingspost vanuit het hersteltijdpaneel, toon alleen gildeleden waarvan de hersteltijd klaar is."
L["SettingsDevHeader"]      = "Ontwikkelaar"
L["SettingsDebug"]          = "Debug-uitvoer"
L["SettingsDebugDesc"]      = "Drukt gedetailleerde debugberichten af in het chatvenster."
L["SettingsDataHeader"]     = "Gegevens"
L["SettingsSyncNow"]        = "Forceer hersynchronisatie"
L["SettingsSyncNowDesc"]    = "Zendt je beroepsgegevens onmiddellijk uit naar de gilde."
L["SettingsPurgeGuild"]     = "Wis alle gildegegevens"
L["SettingsPurgeGuildDesc"] = "Verwijdert alle opgeslagen beroeps- en hersteltijdgegevens voor elk gildelid op dit account. Kan niet ongedaan gemaakt worden."
L["SettingsPurgeGuildConfirm"] = "ALLE gildegegevens voor dit account verwijderen?"
L["SettingsPurgeMine"]      = "Wis mijn personagegegevens"
L["SettingsPurgeMineDesc"]  = "Verwijdert alleen de opgeslagen gegevens van je eigen personage uit de gildedatabase."
L["SettingsPurgeMineConfirm"] = "Je eigen beroeps- en hersteltijdgegevens verwijderen?"
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
L["CooldownAlertEnable"]               = "Activeer klaar-waarschuwing voor deze hersteltijd"
L["CooldownAlertDisable"]              = "Deactiveer klaar-waarschuwing voor deze hersteltijd"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Hersteltijd klaar: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Vervaardigerwaarschuwingen"
L["SettingsCrafterAlert"]              = "Activeer vervaardigerwaarschuwingen"
L["SettingsCrafterAlertDesc"]          = "Speelt een geluid af en laat het scherm knipperen wanneer een gildelid dat een gewaarschuwd boodschappenlijst-voorwerp kan maken online komt."
L["SettingsCrafterAlertSuppressAV"]    = "Onderdruk geluid en knipperen"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Deactiveert audio-effecten en schermknippering (chatbericht verschijnt wel)."
L["SettingsCrafterAlertSuppressLogin"]     = "Onderdruk waarschuwingen bij inloggen"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Geen waarschuwingen activeren tijdens de initiële stroom van online-meldingen bij inloggen of herladen."
L["SettingsCooldownAlertSuppressProtected"]     = "Dempt waarschuwingen in instances"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Geen geluid of weergave van hersteltijd-klaar-waarschuwingen terwijl je in een raid, dungeon, slagveld, arena of scenario bent. Hoofdsteden worden NIET gedempt — je transmutatie blijft pingen terwijl je AFK staat in Stormwind. Wachtende waarschuwingen vuren af zodra je de instance verlaat."
L["SettingsCooldownReminderInterval"]      = "Hersteltijd-klaar herinnering"
L["SettingsCooldownReminderIntervalDesc"]  = "Vuurt elke geactiveerde hersteltijd-waarschuwing opnieuw af elke N minuten zolang de hersteltijd klaar blijft (d.w.z. totdat je daadwerkelijk maakt). Voer 0, leeg of 'off' in om slechts één keer per klaar-cyclus af te vuren. Geldig bereik: 1–1440 minuten (24 uur)."
L["SettingsCooldownReminderInvalid"]       = "Voer een geheel getal in van 0 tot 1440, of 'off'."

L["SettingsAHHeader"]                      = "Veilinghuis"
L["SettingsAHScanDelay"]                   = "VH-scanvertraging (seconden)"
L["SettingsAHScanDelayDesc"]               = "Seconden tussen VH-scanverzoeken. Leeg / 0 / 'off' gebruikt de versiestandaard (1,5s op Classic Era en Anniversary; 3,0s op TBC, Wrath, Cata, MoP — die servers beperken strenger). Verlaag voor snellere scans, verhoog als scans vastlopen. Geldig bereik: 0,5–10 seconden."
L["SettingsAHScanDelayInvalid"]            = "Voer een getal in van 0,5 tot 10, of 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Recept"
L["TooltipRecipeDesc"]           = "De naam van het te vervaardigen voorwerp of de spreuk."
L["TooltipCraftersTitle"]        = "Vervaardigers"
L["TooltipCraftersDesc"]         = "Gildeleden die dit recept kennen. Klik op een recept voor de volledige lijst."
L["CraftersColHeader"]           = "Vervaardigers"
L["TooltipBankTitle"]            = "Aanvragen bij bank"
L["TooltipBankDescScroll"]       = "Stuurt een verzoek naar een TOGBankClassic-gildebankier voor deze receptrol."
L["TooltipBankDescGeneric"]      = "Stuurt een verzoek naar een TOGBankClassic-gildebankier."
L["TooltipAHTitle"]              = "Zoek in veilinghuis"
L["TooltipAHDescScroll"]         = "Opent deze receptrol in de VH-zoekfunctie."
L["TooltipAHDescReagent"]        = "Opent dit ingrediënt in de VH-zoekfunctie."
L["TooltipSettingsTitle"]        = "Instellingen"
L["TooltipSettingsDesc"]         = "Opent het instellingenpaneel van TOG Profession Master (|cffffd700ESC > Opties > AddOns > TOG Profession Master|r). Hetzelfde doel als |cffffd700/togpm settings|r en Shift+linkermuisknop op de minimapknop."
L["TooltipWhisperRightClick"]    = "Rechterklik om te fluisteren"
L["TooltipClickTransmutes"]      = "Klik om transmutaties te bekijken"
L["TooltipClickDetailsFormat"]   = "Klik om %s te bekijken"
L["TooltipClickDetailsFallback"] = "details"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Hersteltijd-bevoorrading: %s"
L["MailBodyFormat"]         = "Hallo %s! Gebruik deze materialen om %s te maken. Stuur me de %s wanneer je tijd hebt om het te maken. Bedankt!"
L["MailMsgNoEmptyBag"]      = "Geen lege tasvak om te splitsen."
L["MailMsgOpenMailbox"]     = "Open eerst een brievenbus."
L["MailMsgHasItems"]        = "Post heeft al voorwerpen bijgevoegd — verstuur of verwijder ze eerst."
L["MailMsgCannotFulfill"]   = "Kan niet voltooien."
L["MailMsgCouldNotAttach"]  = "Kan voorwerpen niet bijvoegen."
L["MailMsgAttachedFormat"]  = "%dx %s voor %s bijgevoegd."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Linkerklik|r om beroepsbrowser te schakelen"
L["MinimapTooltipRightClick"]  = "|cffffd100Rechterklik|r om ingrediënten te schakelen"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+links|r opent instellingen"
L["MinimapButtonShown"]        = "Minimapknop getoond."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- commando-namen worden niet vertaald
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — commando's:"
L["SlashHelpOpen"]          = "open beroepsbrowser"
L["SlashHelpReagents"]      = "open ontbrekende ingrediënten"
L["SlashHelpMinimap"]       = "toon minimapknop"
L["SlashHelpPurge"]         = "open wisdialoog"
L["SlashHelpSync"]          = "forceer volledige gilde-hersynchronisatie"
L["SlashHelpStatus"]        = "dump sync/comm-diagnose-informatie"
L["SlashHelpVersionCheck"]  = "controleer addon-versies in de gilde"
L["SlashHelpDebug"]         = "schakel debug-uitvoer"
L["SlashHelpHelp"]          = "toon deze lijst"
L["SlashForceSyncSent"]     = "Forced sync verzonden."
L["AHScannerOpenAH"]        = "Open het veilinghuis om te zoeken."
L["AHOpenFirst"]            = "Open eerst het veilinghuis."
L["AHNoItemsToScan"]        = "Geen voorwerpen om te scannen in de huidige weergave."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Aanvraag bij gildebank"
L["BankDialogBanker"]       = "Bankier:"
L["BankDialogQty"]          = "Aantal:"
L["BankDialogSend"]         = "Verzoek versturen"
L["BankDialogCancel"]       = "Annuleren"

-- ---------------------------------------------------------------------------
-- Wissingsbevestigingen en andere commando-uitvoer
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Alle gildegegevens gewist."
L["MsgOwnDataPurged"]        = "Je personagegegevens gewist."
L["SlashForceBroadcastSent"] = "Forced broadcast verzonden."
L["SlashDebugEnabled"]       = "|cff00ff00ingeschakeld|r"
L["SlashDebugDisabled"]      = "|cffff4444uitgeschakeld|r"
L["SlashDebugToggleFormat"]  = "Debug-uitvoer %s"

-- ---------------------------------------------------------------------------
-- Beroepsnamen (alle 15 — community-vertaling, native-speaker review welkom)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alchemie"
L["ProfBlacksmithing"]  = "Smeden"
L["ProfCooking"]        = "Koken"
L["ProfEnchanting"]     = "Betoveren"
L["ProfEngineering"]    = "Techniek"
L["ProfFirstAid"]       = "Eerste hulp"
L["ProfLeatherworking"] = "Leerbewerken"
L["ProfMining"]         = "Mijnbouw"
L["ProfTailoring"]      = "Kleermakerij"
L["ProfHerbalism"]      = "Kruidenkunde"
L["ProfSkinning"]       = "Vilkunst"
L["ProfJewelcrafting"]  = "Edelsmederij"
L["ProfInscription"]    = "Inscriptie"
L["ProfFishing"]        = "Vissen"
L["ProfSmelting"]       = "Smelten"
