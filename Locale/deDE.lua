-- TOG Profession Master -- German (deDE) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("deDE")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master \226\128\148 Sync-Protokoll"

-- Tab labels
L["TabProfessions"]     = "Berufe"
L["TabCooldowns"]       = "Abklingzeiten"
L["TabReagents"]        = "Reagenzien"
L["TabMissingRecipes"]  = "Fehlende Rezepte"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Rezepte suchen\226\128\166"
L["ViewGuild"]          = "Gilde"
L["ViewMine"]           = "Meine Charaktere"
L["AllProfessions"]     = "Alle Berufe"
L["PanelProfessions"]   = "Berufe"
L["PanelCharacters"]    = "Charaktere"
L["SelectProfession"]   = "W\195\164hlt einen Beruf"
L["NoDataYet"]          = "|cffaaaaaa(noch keine Daten)|r"
L["SelectProfHint"]     = "|cffaaaaaa\226\134\144 W\195\164hlt einen Beruf, um zu sehen, wer ihn beherrscht.|r"
L["NoProfMembers"]      = "|cffaaaaaa(keine Gildenmitglieder mit diesem Beruf)|r"
L["BackToCharacters"]   = "|cff00aaff\226\134\144 Zur\195\188ck zu den Charakteren|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(keine passenden Rezepte)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Ihr"
L["BrowserScanAH"]          = "AH durchsuchen"
L["BrowserScanAHProgress"]  = "Durchsuche %d/%d"
L["BrowserScanAHDesc"]      = "Durchsucht das Auktionshaus nach jedem Reagenz auf eurer Einkaufsliste. Zeilen mit aktuell verf\195\188gbaren Reagenzien erhalten einen [AH]-Knopf; klickt diesen, um direkt zur AH-Suche zu springen."
L["CooldownsScanAHDesc"]    = "Durchsucht das Auktionshaus nach jedem Reagenz in den sichtbaren Abklingzeiten-Zeilen. Zeilen mit verf\195\188gbaren Reagenzien erhalten einen [AH]-Knopf (links von [Bank]); klickt diesen, um direkt zur AH-Suche zu springen."

-- Recipe detail popup
L["PopupCrafters"]       = "Beherrscht von"
L["PopupOnList"]         = "Auf Einkaufsliste"
L["PopupNotOnList"]      = "Nicht auf Einkaufsliste"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Nur bereit"
L["ShowAll"]                = "Alle"
L["FilterColProfession"]    = "Beruf"
L["FilterColCooldown"]      = "Abklingzeit"
L["FilterColView"]          = "Ansicht"
L["FilterProfessionDesc"]   = "Filtert die Abklingzeitenliste nach einem Beruf (Alchimie, Schneiderei usw.)."
L["FilterCooldownDesc"]     = "Filtert innerhalb des gew\195\164hlten Berufs nach einer einzelnen geteilten Abklingzeit (z.B. Transmutieren, Mondstoff)."
L["FilterViewDesc"]         = "Wechselt zwischen den Abklingzeiten aller Gildenmitglieder und nur euren eigenen Charakteren."
L["AllCooldowns"]           = "Alle Abklingzeiten"
-- Cooldown filter entry labels
L["FilterTransmute"]            = "Transmutieren"
L["FilterAlchResearch"]         = "Alchimie-Forschung"
L["FilterMooncloth"]            = "Mondstoff"
L["FilterSpecialtyCloth"]       = "Spezialstoff"
L["FilterGlacialBag"]           = "Gletschertasche"
L["FilterDreamcloth"]           = "Traumstoff"
L["FilterImperialSilk"]         = "Kaiserliche Seide"
L["FilterSaltShaker"]           = "Salzstreuer"
L["FilterMagicSphere"]          = "Magische Sph\195\164re"
L["FilterShaCrystal"]           = "Sha-Kristall"
L["FilterBrilliantGlass"]       = "Brillantes Glas"
L["FilterIcyPrism"]             = "Eisiges Prisma"
L["FilterFirePrism"]            = "Feuerprisma"
L["FilterJcDaily"]              = "Juwelenschleifen-T\195\164glich"
L["FilterInscriptionResearch"]  = "Inschriftenforschung"
L["FilterForgedDocuments"]      = "Gef\195\164lschte Dokumente"
L["FilterScrollOfWisdom"]       = "Schriftrolle der Weisheit"
L["FilterTitansteelBar"]        = "Titanstahlbarren"
L["FilterBsIngot"]              = "Verh\195\188tten"
L["FilterMagnificence"]         = "Grandiosit\195\164t"
L["FilterJards"]                = "Jards Energie"
L["ColCharacter"]           = "Charakter"
L["ColCooldown"]            = "Abklingzeit"
L["ColReagent"]             = "Reagenz"
L["ColTimeLeft"]            = "Verbleibende Zeit"
L["NoCooldownData"]         = "|cffaaaaaa(noch keine Abklingzeiten-Daten \226\128\148 \195\182ffnet ein Berufsfenster)|r"
L["Ready"]                  = "|cff00ff00Bereit|r"
L["Transmute"]              = "Transmutieren"
L["MailBtn"]                = "Post"
L["MailBtnTooltip"]         = "Versorgungspost senden"
L["MailBtnTooltipDesc"]     = "\195\150ffnet einen Briefkasten, dann klickt, um Reagenzien anzuh\195\164ngen und eine Versorgungspost an diesen Spieler zu verfassen."
L["BankBtn"]                = "[Bank]"
L["CloseBtn"]               = "Schlie\195\159en"

-- Profession-spec Bonus-Output-Indikator (kleines Symbol links vom Charakternamen)
L["SpecBonusGuaranteedDouble"]  = "Garantiert doppelter Ertrag"
L["SpecBonusProcChance"]        = "Chance auf zus\195\164tzlichen Ertrag"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Einkaufsliste"
L["SectionMissingReagents"] = "Fehlende Reagenzien"
L["SectionReagentWatch"]    = "Reagenzien\195\188berwachung"
L["ShoppingListEmpty"]      = "|cffaaaaaa(leer \226\128\148 klickt eine Rezeptzeile im Berufe-Tab, um Gegenst\195\164nde zur Einkaufsliste hinzuzuf\195\188gen)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(Einkaufsliste ist leer oder alle Reagenzien sind in den Taschen)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(keine Gegenst\195\164nde werden \195\188berwacht \226\128\148 gebt oben eine Gegenstands-ID oder einen Link ein)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch-Modul nicht geladen)|r"
L["WatchInputLabel"]        = "Gegenstands-ID oder Link"
L["WatchBtn"]               = "\195\156berwachen"
L["WatchedItemsHeading"]    = "\195\156berwachte Gegenst\195\164nde"
L["ColHave"]                = "Habe"
L["ColNeed"]                = "Ben\195\182tigt"
L["ColShort"]               = "Fehlt"
L["ColItem"]                = "Gegenstand"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Charakter|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Beruf|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Rezepte suchen\226\128\166|r"
L["MissingIncludeTrainer"]      = "Lehrer-exklusive einbeziehen"
L["MissingIncludeTrainerDesc"]  = "Bezieht Rezepte mit ein, die nur bei einem Lehrer erlernt werden k\195\182nnen (keine AH-Rolle)."
L["MissingScanAH"]              = "AH durchsuchen"
L["MissingScanAHProgress"]      = "Durchsuche %d/%d (klickt zum Abbrechen)"
L["MissingScanAHDesc"]          = "\195\150ffnet das Auktionshaus, dann klickt, um es nach jeder Rezeptrolle in der sichtbaren Liste zu durchsuchen. Zeilen mit aktiven Angeboten erhalten einen [AH]-Knopf; klickt diesen, um zur AH-Suche zu springen."
L["MissingNoCharacters"]        = "|cffaaaaaa(noch keine Charaktere mit Berufsdaten \226\128\148 \195\182ffnet ein Berufsfenster)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(f\195\188r diesen Charakter sind noch keine Berufe erfasst \226\128\148 \195\182ffnet ein Berufsfenster)|r"
L["MissingNoneFound"]           = "|cff00ff00Alle bekannten Rezepte f\195\188r diesen Beruf wurden erlernt.|r"
L["MissingPickProfession"]      = "|cffaaaaaa\226\134\144 W\195\164hlt einen Beruf, um zu sehen, was fehlt.|r"
L["MissingNoData"]              = "|cffff8888(keine Rezeptdaten f\195\188r diesen Beruf verf\195\188gbar)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Rezept"
L["MissingColSkill"]            = "Fertigkeit"
L["MissingColSource"]           = "Quellen"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Diese Rezeptrolle \195\188berwachen"
L["MissingAddToWatchDesc"]      = "F\195\188gt die Rezeptrolle zur Reagenzien\195\188berwachung hinzu, damit ihr sie sofort seht, sobald sie in den Taschen landet."
L["MissingRemoveFromWatch"]     = "\226\156\147"
L["MissingRemoveFromWatchTooltip"] = "Bereits in der \195\156berwachung \226\128\148 klickt, um die \195\156berwachung zu beenden"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Fehlendes Rezept"
L["MissingCountPlural"]         = "Fehlende Rezepte"
L["MissingTruncatedHint"]       = "(zeigt die ersten %d \226\128\148 tippt im Suchfeld, um die Liste einzugrenzen)"
L["MissingCharTooltipTitle"]    = "Charakterfilter"
L["MissingCharTooltipDesc"]     = "W\195\164hlt aus, f\195\188r welchen eurer Charaktere fehlende Rezepte angezeigt werden. Standard ist der aktuell eingeloggte Charakter."
L["MissingProfTooltipTitle"]    = "Berufsfilter"
L["MissingProfTooltipDesc"]     = "W\195\164hlt einen Beruf, um Rollen zu sehen, die dieser Charakter noch nicht erlernt hat."
L["MissingSearchTooltipTitle"]  = "Rezepte suchen"
L["MissingSearchTooltipDesc"]   = "Tippt, um die Liste der fehlenden Rezepte nach Namen zu filtern."
L["MissingHdrCountTitle"]       = "Fehlende Rezepte"
L["MissingHdrCountDesc"]        = "Rezepte, die der gew\195\164hlte Charakter noch nicht erlernt hat, aber in dieser Spielversion erh\195\164ltlich sind. Die Anzahl spiegelt den aktuellen Filter wider (Beruf, Suche, Lehrer-Schalter)."
L["MissingHdrSkillTitle"]       = "Fertigkeitsstufe"
L["MissingHdrSkillDesc"]        = "Der ben\195\182tigte Berufsskill, um dieses Rezept zu erlernen. Ausgegraute Zeilen bedeuten, dass der Charakter noch nicht weit genug ist."
L["MissingHdrSourceTitle"]      = "Quellen"
L["MissingHdrSourceDesc"]       = "Wie dieses Rezept zu erhalten ist \226\128\148 Lehrer, Beute, H\195\164ndler, Quest oder hergestellt. Bewegt die Maus \195\188ber den Quellentext einer Zeile, um den konkreten NPC / Mob / Schritt zu sehen."
L["MissingRowTooltipShift"]     = "Shift-Klick, um im Chat zu verlinken."
L["MissingSrcVendor"]           = "H\195\164ndler"
L["MissingSrcDrop"]             = "Beute"
L["MissingSrcQuest"]            = "Quest"
L["MissingSrcCrafted"]          = "Hergestellt"
L["MissingSrcFishing"]          = "Angeln"
L["MissingSrcContainer"]        = "Beh\195\164lter"
L["MissingSrcTrainer"]          = "Lehrer"
L["MissingSrcOther"]            = "Sonstiges"
L["MissingSrcUnknown"]          = "Unbekannt"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Gegenstands-Tooltip"
L["SettingsTooltipShowCrafters"]    = "Gildenhandwerker in Gegenstands-Tooltips zeigen"
L["SettingsTooltipShowCraftersDesc"]= "F\195\188gt eine [TOGPM]-Zeile hinzu, die jeden Gildenkameraden auflistet, der den gerade betrachteten Gegenstand herstellen kann. Online in Wei\195\159, offline in Grau. Bei-Abholen-gebundene Gegenst\195\164nde werden \195\188bersprungen (ohnehin nicht handelbar)."
L["SettingsTooltipShowIds"]         = "Gegenstands-ID / Zauber-ID in Tooltips zeigen"
L["SettingsTooltipShowIdsDesc"]     = "F\195\188gt eine [TOGPM]-Zeile mit der Gegenstands-ID und (falls bekannt) der Rezept-Zauber-ID hinzu. Vor allem n\195\188tzlich zur Fehlersuche bei falschen Symbolen oder fehlenden Rezepten \226\128\148 IDs in Wowhead einf\195\188gen, um zu pr\195\188fen, womit der Addon abgleicht."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "TBC-Anniversary-Phase"
L["SettingsTBCPhase"]           = "Aktuelle Inhaltsphase"
L["SettingsTBCPhaseDesc"]       = "Verbirgt Fehlende Rezepte aus sp\195\164teren Phasen als der aktuellen Anniversary-Phase. Erh\195\182ht den Wert, sobald Blizzard die Phase vorr\195\188cken l\195\164sst. (Bereits zug\195\164ngliche Rezepte bleiben sichtbar.)"
L["SettingsTBCPhase1"]          = "Phase 1 \226\128\148 Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Phase 2 \226\128\148 Schlangenschrein / Festung der St\195\188rme"
L["SettingsTBCPhase3"]          = "Phase 3 \226\128\148 Schwarzer Tempel / Berg Hyjal"
L["SettingsTBCPhase4"]          = "Phase 4 \226\128\148 Sonnenbrunnen / Terrasse der Magister"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Anzeige"
L["SettingsMinimapBtn"]          = "Minimap-Knopf anzeigen"
L["SettingsMinimapBtnDesc"]      = "Blendet den Minimap-Starter-Knopf ein oder aus."
L["SettingsPersistProfFilter"]     = "Berufsfilter merken"
L["SettingsPersistProfFilterDesc"] = "Stellt den gew\195\164hlten Beruf beim Einloggen oder Reload wieder her."
L["SettingsUILangOverride"]        = "UI-Sprache \195\188berschreiben"
L["SettingsUILangOverrideDesc"]    = "Erzwingt die TOGPM-Addon-UI (Tabs, Kn\195\182pfe, Tooltips, Einstellungen) in eine bestimmte Sprache, unabh\195\164ngig von der Sprache eures WoW-Clients. \"Automatisch\" folgt der Sprache eures WoW-Clients. Namen von Gegenst\195\164nden / Zaubern / Rezepten im Spiel werden weiterhin in der tats\195\164chlichen Client-Sprache angezeigt, da diese aus Blizzards APIs stammen und nicht aus diesem Addon. Inklusive Thai und Filipino, die Blizzards Client nicht nativ unterst\195\188tzt, f\195\188r die TOGPM aber \195\156bersetzungen \195\188ber diese \195\156berschreibung mitliefert."
L["SettingsUILangAuto"]            = "Automatisch (WoW-Client-Sprache verwenden)"
L["SettingsUILangReloadHint"]      = "UI-Sprache ge\195\164ndert. Tippt |cffffd100/reload|r, damit die \195\132nderung \195\188berall wirksam wird."
L["SettingsCooldownsHeader"]= "Abklingzeiten"
L["SettingsMailReadyOnly"]  = "Post: nur bereite Abklingzeiten anzeigen"
L["SettingsMailReadyOnlyDesc"] = "Beim Verfassen von Versorgungspost aus dem Abklingzeiten-Bereich nur Gildenmitglieder auflisten, deren Abklingzeit abgelaufen ist."
L["SettingsDevHeader"]      = "Entwickler"
L["SettingsDebug"]          = "Debug-Ausgabe"
L["SettingsDebugDesc"]      = "Gibt ausf\195\188hrliche Debug-Meldungen im Chatfenster aus."
L["SettingsDataHeader"]     = "Daten"
L["SettingsSyncNow"]        = "Erneut synchronisieren"
L["SettingsSyncNowDesc"]    = "Sendet eure Berufsdaten sofort an die Gilde."
L["SettingsPurgeGuild"]     = "Alle Gildendaten l\195\182schen"
L["SettingsPurgeGuildDesc"] = "L\195\182scht alle gespeicherten Berufs- und Abklingzeiten-Daten f\195\188r jedes Gildenmitglied auf diesem Konto. Kann nicht r\195\188ckg\195\164ngig gemacht werden."
L["SettingsPurgeGuildConfirm"] = "ALLE Gildendaten f\195\188r dieses Konto l\195\182schen?"
L["SettingsPurgeMine"]      = "Eigene Charakterdaten l\195\182schen"
L["SettingsPurgeMineDesc"]  = "L\195\182scht nur die gespeicherten Daten eures eigenen Charakters aus der Gilden-Datenbank."
L["SettingsPurgeMineConfirm"] = "Eigene Berufs- und Abklingzeiten-Daten l\195\182schen?"
L["SettingsSyncLogHeader"]  = "Sync-Protokoll"
L["SettingsViewLog"]        = "Sync-Protokoll anzeigen"
L["SettingsViewLogDesc"]    = "\195\150ffnet eine scrollbare Liste der letzten Sync-Ereignisse (letzte 200)."
L["SettingsClearLog"]       = "Sync-Protokoll leeren"
L["SettingsClearLogConfirm"]= "Alle Eintr\195\164ge des Sync-Protokolls l\195\182schen?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(SyncLog-Modul nicht geladen)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(noch keine Sync-Ereignisse aufgezeichnet)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Minimap-Knopf verborgen. Benutzt |cffda8cff/togpm minimap|r zum Wiederherstellen."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Hergestellt von:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Bereit zum Herstellen:|r %s \195\151 %d  (%s \195\151 %d in Taschen)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Handwerker-Alarm f\195\188r dieses Rezept aktivieren"
L["ShoppingAlertDisable"]              = "Handwerker-Alarm f\195\188r dieses Rezept deaktivieren"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s ist online \226\128\148 kann herstellen: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s ist online (Twink von %s) \226\128\148 kann herstellen: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Bereit-Alarm f\195\188r diese Abklingzeit aktivieren"
L["CooldownAlertDisable"]              = "Bereit-Alarm f\195\188r diese Abklingzeit deaktivieren"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Abklingzeit bereit: %s \226\128\148 %s"

-- Settings
L["SettingsAlertsHeader"]              = "Handwerker-Alarme"
L["SettingsCrafterAlert"]              = "Handwerker-Alarme aktivieren"
L["SettingsCrafterAlertDesc"]          = "Spielt einen Ton ab und l\195\164sst den Bildschirm blinken, wenn ein Gildenmitglied, das einen alarmierten Einkaufslisten-Gegenstand herstellen kann, online geht."
L["SettingsCrafterAlertSuppressAV"]    = "Ton & Blinken unterdr\195\188cken"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Deaktiviert Audio- und Bildschirmblitz-Effekte (Chat-Nachricht erscheint weiterhin)."
L["SettingsCrafterAlertSuppressLogin"]     = "Alarme beim Einloggen unterdr\195\188cken"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Keine Alarme w\195\164hrend des anf\195\164nglichen Schwalls an Online-Benachrichtigungen beim Einloggen oder Reload ausl\195\182sen."
L["SettingsCooldownAlertSuppressProtected"]     = "Alarme in Instanzen stummschalten"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Keine Abklingzeit-bereit-Alarme in Schlachtz\195\188gen, Dungeons, Schlachtfeldern, Arenen oder Szenarien ausl\195\182sen. Hauptst\195\164dte sind NICHT unterdr\195\188ckt \226\128\148 eure Transmutation pingt weiterhin, w\195\164hrend ihr AFK in Sturmwind seid. Wartende Alarme l\195\182sen aus, sobald ihr die Instanz verlasst."
L["SettingsCooldownReminderInterval"]      = "Abklingzeit-bereit-Erinnerung"
L["SettingsCooldownReminderIntervalDesc"]  = "Feuert jeden scharfgestellten Abklingzeit-Alarm alle N Minuten erneut, solange die Abklingzeit bereit bleibt (d.h. bis ihr tats\195\164chlich herstellt). Gebt 0, leer oder 'off' ein, um nur einmal pro Bereit-Zyklus zu feuern. G\195\188ltiger Bereich: 1-1440 Minuten (24 Stunden)."
L["SettingsCooldownReminderInvalid"]       = "Gebt eine ganze Zahl von 0 bis 1440 oder 'off' ein."

L["SettingsAHHeader"]                      = "Auktionshaus"
L["SettingsAHScanDelay"]                   = "AH-Scan-Verz\195\182gerung (Sekunden)"
L["SettingsAHScanDelayDesc"]               = "Sekunden zwischen AH-Scan-Anfragen. Leer / 0 / 'off' verwendet den Versions-Standard (1.5s auf Classic Era und Anniversary; 3.0s auf TBC, Wrath, Cata, MoP \226\128\148 diese Server drosseln st\195\164rker). Senkt den Wert f\195\188r schnellere Scans, erh\195\182ht ihn, wenn Scans stocken. G\195\188ltiger Bereich: 0.5-10 Sekunden."
L["SettingsAHScanDelayInvalid"]            = "Gebt eine Zahl von 0.5 bis 10 oder 'off' ein."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Rezept"
L["TooltipRecipeDesc"]           = "Der Name des herstellbaren Gegenstands oder Zaubers."
L["TooltipCraftersTitle"]        = "Handwerker"
L["TooltipCraftersDesc"]         = "Gildenmitglieder, die dieses Rezept beherrschen. Klickt ein Rezept f\195\188r die vollst\195\164ndige Liste."
L["CraftersColHeader"]           = "Handwerker"
L["TooltipBankTitle"]            = "Aus der Gildenbank anfordern"
L["TooltipBankDescScroll"]       = "Sendet eine Anfrage an einen TOGBankClassic-Gildenbankier f\195\188r diese Rezeptrolle."
L["TooltipBankDescGeneric"]      = "Sendet eine Anfrage an einen TOGBankClassic-Gildenbankier."
L["TooltipAHTitle"]              = "Auktionshaus durchsuchen"
L["TooltipAHDescScroll"]         = "\195\150ffnet diese Rezeptrolle in der AH-Suche."
L["TooltipAHDescReagent"]        = "\195\150ffnet dieses Reagenz in der AH-Suche."
L["TooltipSettingsTitle"]        = "Einstellungen"
L["TooltipSettingsDesc"]         = "\195\150ffnet das Einstellungsmen\195\188 von TOG Profession Master (|cffffd700ESC > Optionen > AddOns > TOG Profession Master|r). Gleiches Ziel wie |cffffd700/togpm settings|r und Shift+Linksklick auf den Minimap-Knopf."
L["TooltipWhisperRightClick"]    = "Rechtsklick zum Fl\195\188stern"
L["TooltipClickTransmutes"]      = "Klicken, um Transmutationen zu sehen"
L["TooltipClickDetailsFormat"]   = "Klicken, um %s zu sehen"
L["TooltipClickDetailsFallback"] = "Details"

-- ---------------------------------------------------------------------------
-- Mail composer (Versorgungspost aus dem Abklingzeiten-Tab)
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Abklingzeit-Versorgung: %s"
L["MailBodyFormat"]         = "Hallo %s! Bitte benutzt diese Materialien, um %s herzustellen. Bitte sendet mir %s, sobald ihr Zeit habt, es zu fertigen. Danke!"
L["MailMsgNoEmptyBag"]      = "Kein leerer Taschenplatz zum Aufteilen."
L["MailMsgOpenMailbox"]     = "Zuerst einen Briefkasten \195\182ffnen."
L["MailMsgHasItems"]        = "Post hat bereits angeh\195\164ngte Gegenst\195\164nde \226\128\148 sendet oder entfernt sie zuerst."
L["MailMsgCannotFulfill"]   = "Kann nicht erf\195\188llt werden."
L["MailMsgCouldNotAttach"]  = "Konnte keine Gegenst\195\164nde anh\195\164ngen."
L["MailMsgAttachedFormat"]  = "%dx %s f\195\188r %s angeh\195\164ngt."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Linksklick|r blendet den Berufe-Browser ein/aus"
L["MinimapTooltipRightClick"]  = "|cffffd100Rechtsklick|r blendet die Reagenzien ein/aus"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+Links|r \195\182ffnet die Einstellungen"
L["MinimapButtonShown"]        = "Minimap-Knopf eingeblendet."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- command names stay englisch
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r \226\128\148 Befehle:"
L["SlashHelpOpen"]          = "\195\150ffnet den Berufe-Browser"
L["SlashHelpReagents"]      = "\195\150ffnet die fehlenden Reagenzien"
L["SlashHelpMinimap"]       = "Minimap-Knopf einblenden"
L["SlashHelpPurge"]         = "\195\150ffnet den L\195\182sch-Dialog"
L["SlashHelpSync"]          = "Erzwingt eine vollst\195\164ndige Gildensynchronisation"
L["SlashHelpStatus"]        = "Gibt Sync-/Comm-Diagnoseinfos aus"
L["SlashHelpVersionCheck"]  = "Pr\195\188ft Addon-Versionen in der Gilde"
L["SlashHelpDebug"]         = "Debug-Ausgabe umschalten"
L["SlashHelpHelp"]          = "Zeigt diese Liste an"
L["SlashForceSyncSent"]     = "Erzwungene Synchronisation gesendet."
L["AHScannerOpenAH"]        = "\195\150ffnet das Auktionshaus, um zu suchen."
L["AHOpenFirst"]            = "\195\150ffnet zuerst das Auktionshaus."
L["AHNoItemsToScan"]        = "Keine Gegenst\195\164nde in der aktuellen Ansicht zu scannen."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Anfrage an Gildenbank"
L["BankDialogBanker"]       = "Bankier:"
L["BankDialogQty"]          = "Menge:"
L["BankDialogSend"]         = "Anfrage senden"
L["BankDialogCancel"]       = "Abbrechen"

-- ---------------------------------------------------------------------------
-- Purge-Best\195\164tigungen & sonstige Slash-Ausgaben
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Alle Gildendaten gel\195\182scht."
L["MsgOwnDataPurged"]        = "Eure Charakterdaten gel\195\182scht."
L["SlashForceBroadcastSent"] = "Erzwungener Broadcast gesendet."
L["SlashDebugEnabled"]       = "|cff00ff00aktiviert|r"
L["SlashDebugDisabled"]      = "|cffff4444deaktiviert|r"
L["SlashDebugToggleFormat"]  = "Debug-Ausgabe %s"

-- ---------------------------------------------------------------------------
-- Berufsnamen (native-speaker validated, all 15)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alchimie"
L["ProfBlacksmithing"]  = "Schmiedekunst"
L["ProfCooking"]        = "Kochkunst"
L["ProfEnchanting"]     = "Verzauberkunst"
L["ProfEngineering"]    = "Ingenieurkunst"
L["ProfFirstAid"]       = "Erste Hilfe"
L["ProfLeatherworking"] = "Lederverarbeitung"
L["ProfMining"]         = "Bergbau"
L["ProfTailoring"]      = "Schneiderei"
L["ProfHerbalism"]      = "Kr\195\164uterkunde"
L["ProfSkinning"]       = "K\195\188rschnerei"
L["ProfJewelcrafting"]  = "Juwelenschleifen"
L["ProfInscription"]    = "Inschriftenkunde"
L["ProfFishing"]        = "Angeln"
L["ProfSmelting"]       = "Verh\195\188tten"
