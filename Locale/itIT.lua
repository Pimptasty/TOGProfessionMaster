-- TOG Profession Master -- Italian (itIT) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("itIT")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — Registro di sincronizzazione"

-- Tab labels
L["TabProfessions"]     = "Professioni"
L["TabCooldowns"]       = "Tempi di recupero"
L["TabReagents"]        = "Reagenti"
L["TabMissingRecipes"]  = "Ricette mancanti"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Cerca ricette…"
L["ViewGuild"]          = "Gilda"
L["ViewMine"]           = "I miei personaggi"
L["AllProfessions"]     = "Tutte le professioni"
L["PanelProfessions"]   = "Professioni"
L["PanelCharacters"]    = "Personaggi"
L["SelectProfession"]   = "Seleziona una professione"
L["NoDataYet"]          = "|cffaaaaaa(ancora nessun dato)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Seleziona una professione per vedere chi la conosce.|r"
L["NoProfMembers"]      = "|cffaaaaaa(nessun membro della gilda con questa professione)|r"
L["BackToCharacters"]   = "|cff00aaff← Torna ai personaggi|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(nessuna ricetta corrispondente)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Tu"
L["BrowserScanAH"]          = "Scansiona CA"
L["BrowserScanAHProgress"]  = "Scansione %d/%d"
L["BrowserScanAHDesc"]      = "Scansiona la casa d'aste per ogni reagente della tua lista della spesa. Le righe i cui reagenti sono attualmente in vendita ricevono un pulsante [CA]; cliccalo per saltare direttamente alla ricerca."
L["CooldownsScanAHDesc"]    = "Scansiona la casa d'aste per ogni reagente unico nelle righe di tempo di recupero visibili. Le righe i cui reagenti sono attualmente in vendita ricevono un pulsante [CA] (a sinistra di [Banca]); cliccalo per saltare alla ricerca."

-- Recipe detail popup
L["PopupCrafters"]       = "Conosciuta da"
L["PopupOnList"]         = "Nella lista della spesa"
L["PopupNotOnList"]      = "Non nella lista"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Solo pronti"
L["ShowAll"]                = "Tutti"
L["FilterColProfession"]    = "Professione"
L["FilterColCooldown"]      = "Recupero"
L["FilterColView"]          = "Vista"
L["FilterProfessionDesc"]   = "Filtra la lista dei tempi di recupero per una sola professione (Alchimia, Sartoria, ecc.)."
L["FilterCooldownDesc"]     = "All'interno della professione selezionata, filtra per un singolo tempo di recupero condiviso (es. Trasmutazione, Stoffa di Luna)."
L["FilterViewDesc"]         = "Alterna tra i tempi di recupero di tutti i membri della gilda e solo i tuoi personaggi."
L["AllCooldowns"]           = "Tutti i tempi di recupero"
-- Cooldown filter entry labels
L["FilterTransmute"]            = "Trasmutazione"
L["FilterAlchResearch"]         = "Ricerca alchemica"
L["FilterMooncloth"]            = "Stoffa di Luna"
L["FilterSpecialtyCloth"]       = "Stoffa speciale"
L["FilterGlacialBag"]           = "Borsa glaciale"
L["FilterDreamcloth"]           = "Stoffa onirica"
L["FilterImperialSilk"]         = "Seta imperiale"
L["FilterSaltShaker"]           = "Saliera"
L["FilterMagicSphere"]          = "Sfera magica"
L["FilterShaCrystal"]           = "Cristallo Sha"
L["FilterBrilliantGlass"]       = "Vetro brillante"
L["FilterIcyPrism"]             = "Prisma gelido"
L["FilterFirePrism"]            = "Prisma di fuoco"
L["FilterJcDaily"]              = "Taglio quotidiano di gioielleria"
L["FilterInscriptionResearch"]  = "Ricerca iscrizioni"
L["FilterForgedDocuments"]      = "Documenti falsificati"
L["FilterScrollOfWisdom"]       = "Pergamena di saggezza"
L["FilterTitansteelBar"]        = "Lingotto di Titanacciaio"
L["FilterBsIngot"]              = "Fusione"
L["FilterMagnificence"]         = "Magnificenza"
L["FilterJards"]                = "Energia di Jard"
L["ColCharacter"]           = "Personaggio"
L["ColCooldown"]            = "Recupero"
L["ColReagent"]             = "Reagente"
L["ColTimeLeft"]            = "Tempo rimanente"
L["NoCooldownData"]         = "|cffaaaaaa(ancora nessun dato sui tempi di recupero — apri una finestra di professione)|r"
L["Ready"]                  = "|cff00ff00Pronto|r"
L["Transmute"]              = "Trasmutazione"
L["MailBtn"]                = "Posta"
L["MailBtnTooltip"]         = "Invia posta di rifornimento"
L["MailBtnTooltipDesc"]     = "Apri una cassetta postale, poi clicca per allegare reagenti e comporre una posta di rifornimento per questo giocatore."
L["BankBtn"]                = "[Banca]"
L["CloseBtn"]               = "Chiudi"

-- Indicatore bonus di specializzazione professione
L["SpecBonusGuaranteedDouble"]  = "Produzione 2x garantita"
L["SpecBonusProcChance"]        = "Possibilità di produzione extra"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Lista della spesa"
L["SectionMissingReagents"] = "Reagenti mancanti"
L["SectionReagentWatch"]    = "Sorveglianza reagenti"
L["ShoppingListEmpty"]      = "|cffaaaaaa(vuota — clicca una riga di ricetta nella scheda Professioni per aggiungere oggetti alla lista della spesa)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(la lista della spesa è vuota o tutti i reagenti sono nelle borse)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(nessun oggetto sorvegliato — inserisci un ID oggetto o un link sopra)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(modulo ReagentWatch non caricato)|r"
L["WatchInputLabel"]        = "ID oggetto o link"
L["WatchBtn"]               = "Sorveglia"
L["WatchedItemsHeading"]    = "Oggetti sorvegliati"
L["ColHave"]                = "Hai"
L["ColNeed"]                = "Servono"
L["ColShort"]               = "Mancano"
L["ColItem"]                = "Oggetto"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Personaggio|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Professione|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Cerca ricette…|r"
L["MissingIncludeTrainer"]      = "Includi solo da addestratore"
L["MissingIncludeTrainerDesc"]  = "Include ricette apprendibili solo da un addestratore (nessuna pergamena alla CA)."
L["MissingScanAH"]              = "Scansiona CA"
L["MissingScanAHProgress"]      = "Scansione %d/%d (clicca per annullare)"
L["MissingScanAHDesc"]          = "Apri la casa d'aste, poi clicca per scansionarla cercando ogni pergamena di ricetta nella lista visibile. Le righe con aste attive ricevono un pulsante [CA]; cliccalo per saltare alla ricerca."
L["MissingNoCharacters"]        = "|cffaaaaaa(ancora nessun personaggio con dati di professione — apri una finestra di professione)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(questo personaggio non ha ancora professioni registrate — apri una finestra di professione)|r"
L["MissingNoneFound"]           = "|cff00ff00Tutte le ricette conosciute per questa professione sono state apprese.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Scegli una professione per vedere cosa manca.|r"
L["MissingNoData"]              = "|cffff8888(nessun dato di ricetta disponibile per questa professione)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Ricetta"
L["MissingColSkill"]            = "Abilità"
L["MissingColSource"]           = "Fonti"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Sorveglia questa pergamena di ricetta"
L["MissingAddToWatchDesc"]      = "Aggiunge la pergamena di ricetta alla tua lista di Sorveglianza reagenti per vederla appena entra nelle tue borse."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Già sorvegliato — clicca per smettere di sorvegliare"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Ricetta mancante"
L["MissingCountPlural"]         = "Ricette mancanti"
L["MissingTruncatedHint"]       = "(mostra le prime %d — digita nella casella di ricerca per ridurre la lista)"
L["MissingCharTooltipTitle"]    = "Filtro personaggio"
L["MissingCharTooltipDesc"]     = "Scegli per quale dei tuoi personaggi vedere le ricette mancanti. Predefinito il personaggio attualmente connesso."
L["MissingProfTooltipTitle"]    = "Filtro professione"
L["MissingProfTooltipDesc"]     = "Scegli una professione per vedere le pergamene che questo personaggio non ha ancora appreso."
L["MissingSearchTooltipTitle"]  = "Cerca ricette"
L["MissingSearchTooltipDesc"]   = "Digita per filtrare per nome la lista delle ricette mancanti."
L["MissingHdrCountTitle"]       = "Ricette mancanti"
L["MissingHdrCountDesc"]        = "Ricette che il personaggio selezionato non ha ancora appreso ma sono ottenibili in questa versione del gioco. Il numero riflette il filtro corrente (professione, ricerca, interruttore addestratore)."
L["MissingHdrSkillTitle"]       = "Livello di abilità"
L["MissingHdrSkillDesc"]        = "Il livello di abilità di professione richiesto per apprendere questa ricetta. Le righe in grigio indicano che il personaggio non ha ancora un livello sufficiente."
L["MissingHdrSourceTitle"]      = "Fonti"
L["MissingHdrSourceDesc"]       = "Come ottenere questa ricetta — addestratore, bottino, mercante, missione o artigianato. Passa il mouse sul testo della fonte di una riga per vedere il PNG / mostro / passo specifico."
L["MissingRowTooltipShift"]     = "Shift-clic per collegare nella chat."
L["MissingSrcVendor"]           = "Mercante"
L["MissingSrcDrop"]             = "Bottino"
L["MissingSrcQuest"]            = "Missione"
L["MissingSrcCrafted"]          = "Creata"
L["MissingSrcFishing"]          = "Pesca"
L["MissingSrcContainer"]        = "Contenitore"
L["MissingSrcTrainer"]          = "Addestratore"
L["MissingSrcOther"]            = "Altro"
L["MissingSrcUnknown"]          = "Sconosciuta"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Suggerimento oggetto"
L["SettingsTooltipShowCrafters"]    = "Mostra artigiani della gilda nei suggerimenti degli oggetti"
L["SettingsTooltipShowCraftersDesc"]= "Aggiunge una riga [TOGPM] che elenca ogni compagno di gilda che può creare l'oggetto evidenziato. Online in bianco, offline in grigio. Gli oggetti vincolati al raccoglimento vengono ignorati (non sono scambiabili comunque)."
L["SettingsTooltipShowIds"]         = "Mostra ID oggetto / ID incantesimo nei suggerimenti"
L["SettingsTooltipShowIdsDesc"]     = "Aggiunge una riga [TOGPM] con l'ID oggetto e (se noto) l'ID incantesimo della ricetta. Utile soprattutto per diagnosticare icone errate o ricette mancanti — incolla gli ID in Wowhead per verificare la corrispondenza."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "Fase di TBC Anniversary"
L["SettingsTBCPhase"]           = "Fase di contenuto corrente"
L["SettingsTBCPhaseDesc"]       = "Nasconde le Ricette mancanti provenienti da fasi successive rispetto a quella attuale di Anniversary. Aumenta il valore ogni volta che Blizzard avanza di fase. (Le ricette già accessibili nella fase attiva restano visibili.)"
L["SettingsTBCPhase1"]          = "Fase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Fase 2 — Caverna del Santuario del Serpente / Cittadella della Tempesta"
L["SettingsTBCPhase3"]          = "Fase 3 — Tempio Nero / Monte Hyjal"
L["SettingsTBCPhase4"]          = "Fase 4 — Plaga del Sole / Terrazza dei Magistri"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Visualizzazione"
L["SettingsMinimapBtn"]          = "Mostra pulsante minimappa"
L["SettingsMinimapBtnDesc"]      = "Mostra o nasconde il pulsante di avvio sulla minimappa."
L["SettingsPersistProfFilter"]     = "Ricorda filtro professione"
L["SettingsPersistProfFilterDesc"] = "Ripristina la professione selezionata al login o al ricaricamento."
L["SettingsSyncHeader"]     = "Sincronizzazione"
L["SettingsGuildMode"]      = "Modalità sincronizzazione solo gilda (server privati)"
L["SettingsGuildModeDesc"]  = "Per i server privati o emulati (es. Whitemane) che non recapitano i messaggi degli addon tramite i sussurri, impedendo ai membri della gilda di ricevere i reciproci dati di professione. Quando ATTIVO, tutto il traffico di sincronizzazione viene instradato sul canale di gilda. Attiva questa opzione solo se la sincronizzazione di gilda non funziona sul tuo server. |cffffd100Tutti nella gilda dovrebbero attivarla|r — funziona solo tra membri che l'hanno entrambi attiva. La condivisione tra gilde viene disattivata automaticamente mentre questa è attiva. Si applica a ogni personaggio in questo reame. (Nascosta se la versione installata di DeltaSync non la supporta.)"
L["SettingsCooldownsHeader"]= "Tempi di recupero"
L["SettingsMailReadyOnly"]  = "Posta: mostra solo recuperi pronti"
L["SettingsMailReadyOnlyDesc"] = "Quando componi posta di rifornimento dal pannello dei tempi di recupero, elenca solo i membri il cui recupero è pronto."
L["SettingsDevHeader"]      = "Sviluppatore"
L["SettingsDebug"]          = "Output di debug"
L["SettingsDebugDesc"]      = "Stampa messaggi di debug dettagliati nella chat."
L["SettingsDataHeader"]     = "Dati"
L["SettingsSyncNow"]        = "Forza risincronizzazione"
L["SettingsSyncNowDesc"]    = "Trasmette immediatamente i tuoi dati di professione alla gilda."
L["SettingsPurgeGuild"]     = "Cancella tutti i dati di gilda"
L["SettingsPurgeGuildDesc"] = "Elimina tutti i dati di professione e recupero memorizzati per ogni membro della gilda su questo account. Non può essere annullato."
L["SettingsPurgeGuildConfirm"] = "Eliminare TUTTI i dati di gilda di questo account?"
L["SettingsPurgeMine"]      = "Cancella i miei dati personaggio"
L["SettingsPurgeMineDesc"]  = "Elimina solo i dati memorizzati del tuo personaggio dal database della gilda."
L["SettingsPurgeMineConfirm"] = "Eliminare i tuoi dati di professione e recupero?"
L["SettingsSyncLogHeader"]  = "Registro di sincronizzazione"
L["SettingsViewLog"]        = "Visualizza registro di sincronizzazione"
L["SettingsViewLogDesc"]    = "Apre una lista scorrevole degli eventi recenti di sincronizzazione (ultimi 200)."
L["SettingsClearLog"]       = "Svuota registro di sincronizzazione"
L["SettingsClearLogConfirm"]= "Svuotare tutte le voci del registro di sincronizzazione?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(modulo SyncLog non caricato)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(ancora nessun evento di sincronizzazione registrato)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Pulsante minimappa nascosto. Usa |cffda8cff/togpm minimap|r per ripristinarlo."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Creato da:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Pronto da creare:|r %s × %d  (%s × %d nelle borse)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Attiva avviso artigiano per questa ricetta"
L["ShoppingAlertDisable"]              = "Disattiva avviso artigiano per questa ricetta"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s è online — può creare: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s è online (alt di %s) — può creare: %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Attiva avviso di pronto per questo recupero"
L["CooldownAlertDisable"]              = "Disattiva avviso di pronto per questo recupero"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Recupero pronto: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Avvisi artigiano"
L["SettingsCrafterAlert"]              = "Attiva avvisi artigiano"
L["SettingsCrafterAlertDesc"]          = "Riproduce un suono e fa lampeggiare lo schermo quando un membro della gilda che può creare un oggetto della lista della spesa con avviso si collega."
L["SettingsCrafterAlertSuppressAV"]    = "Sopprimi suono e lampeggio"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Disabilita gli effetti audio e di lampeggio dello schermo (il messaggio in chat appare comunque)."
L["SettingsCrafterAlertSuppressLogin"]     = "Sopprimi avvisi al login"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Non attivare avvisi durante la raffica iniziale di notifiche di connessione al login o ricaricamento."
L["SettingsCooldownAlertSuppressProtected"]     = "Silenzia avvisi nelle istanze"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Non emettere né stampare avvisi di recupero pronto mentre sei in un raid, dungeon, campo di battaglia, arena o scenario. Le capitali NON sono silenziate — la tua trasmutazione continuerà a suonare mentre sei AFK a Roccavento. Gli avvisi in attesa si attivano appena lasci l'istanza."
L["SettingsCooldownReminderInterval"]      = "Promemoria recupero pronto"
L["SettingsCooldownReminderIntervalDesc"]  = "Riattiva ogni avviso di recupero armato ogni N minuti finché il recupero rimane pronto (cioè finché non crei effettivamente). Inserisci 0, vuoto o 'off' per attivare solo una volta per ciclo pronto. Intervallo valido: 1–1440 minuti (24 ore)."
L["SettingsCooldownReminderInvalid"]       = "Inserisci un numero intero da 0 a 1440, o 'off'."

L["SettingsAHHeader"]                      = "Casa d'aste"
L["SettingsAHScanDelay"]                   = "Ritardo scansione CA (secondi)"
L["SettingsAHScanDelayDesc"]               = "Secondi tra le richieste di scansione della CA. Vuoto / 0 / 'off' usa il valore predefinito della versione (1.5s su Classic Era e Anniversary; 3.0s su TBC, Wrath, Cata, MoP — questi server limitano di più). Riduci il valore per scansioni più rapide, aumentalo se le scansioni si bloccano. Intervallo valido: 0.5–10 secondi."
L["SettingsAHScanDelayInvalid"]            = "Inserisci un numero da 0.5 a 10, o 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Ricetta"
L["TooltipRecipeDesc"]           = "Il nome dell'oggetto creabile o dell'incantesimo."
L["TooltipCraftersTitle"]        = "Artigiani"
L["TooltipCraftersDesc"]         = "Membri della gilda che conoscono questa ricetta. Clicca una ricetta per la lista completa."
L["CraftersColHeader"]           = "Artigiani"
L["TooltipBankTitle"]            = "Richiedi dalla banca"
L["TooltipBankDescScroll"]       = "Invia una richiesta a un banchiere di gilda TOGBankClassic per questa pergamena di ricetta."
L["TooltipBankDescGeneric"]      = "Invia una richiesta a un banchiere di gilda TOGBankClassic."
L["TooltipAHTitle"]              = "Cerca nella casa d'aste"
L["TooltipAHDescScroll"]         = "Apre questa pergamena di ricetta nella ricerca della CA."
L["TooltipAHDescReagent"]        = "Apre questo reagente nella ricerca della CA."
L["TooltipSettingsTitle"]        = "Impostazioni"
L["TooltipSettingsDesc"]         = "Apre il pannello delle impostazioni di TOG Profession Master (|cffffd700ESC > Opzioni > AddOn > TOG Profession Master|r). Stessa destinazione di |cffffd700/togpm settings|r e Shift+clic sinistro sul pulsante minimappa."
L["TooltipWhisperRightClick"]    = "Clic destro per sussurrare"
L["TooltipClickTransmutes"]      = "Clicca per vedere le trasmutazioni"
L["TooltipClickDetailsFormat"]   = "Clicca per vedere %s"
L["TooltipClickDetailsFallback"] = "dettagli"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Rifornimento di recupero: %s"
L["MailBodyFormat"]         = "Ciao %s! Per favore usa questi materiali per fare %s. Mandami il %s quando hai tempo di crearlo. Grazie!"
L["MailMsgNoEmptyBag"]      = "Nessuno slot di borsa vuoto per dividere."
L["MailMsgOpenMailbox"]     = "Apri prima una cassetta postale."
L["MailMsgHasItems"]        = "La posta ha già oggetti allegati — invia o rimuovi prima quelli."
L["MailMsgCannotFulfill"]   = "Non si può completare."
L["MailMsgCouldNotAttach"]  = "Impossibile allegare gli oggetti."
L["MailMsgAttachedFormat"]  = "Allegati %dx %s per %s."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Clic sinistro|r per mostrare/nascondere il navigatore di professioni"
L["MinimapTooltipRightClick"]  = "|cffffd100Clic destro|r per mostrare/nascondere i reagenti"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+sinistro|r apre le impostazioni"
L["MinimapButtonShown"]        = "Pulsante minimappa mostrato."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- i nomi dei comandi non sono tradotti
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — comandi:"
L["SlashHelpOpen"]          = "apri navigatore di professioni"
L["SlashHelpReagents"]      = "apri reagenti mancanti"
L["SlashHelpMinimap"]       = "mostra pulsante minimappa"
L["SlashHelpPurge"]         = "apri finestra di cancellazione"
L["SlashHelpSync"]          = "forza risincronizzazione completa della gilda"
L["SlashHelpStatus"]        = "stampa informazioni diagnostiche sync/comm"
L["SlashHelpVersionCheck"]  = "controlla versioni dell'addon nella gilda"
L["SlashHelpDebug"]         = "attiva/disattiva output di debug"
L["SlashHelpHelp"]          = "mostra questa lista"
L["SlashForceSyncSent"]     = "Sincronizzazione forzata inviata."
L["AHScannerOpenAH"]        = "Apri la casa d'aste per cercare."
L["AHOpenFirst"]            = "Apri prima la casa d'aste."
L["AHNoItemsToScan"]        = "Nessun oggetto da scansionare nella vista corrente."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Richiesta alla banca di gilda"
L["BankDialogBanker"]       = "Banchiere:"
L["BankDialogQty"]          = "Q.tà:"
L["BankDialogSend"]         = "Invia richiesta"
L["BankDialogCancel"]       = "Annulla"

-- ---------------------------------------------------------------------------
-- Conferme di cancellazione e altri output dei comandi
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Tutti i dati di gilda cancellati."
L["MsgOwnDataPurged"]        = "Dati del tuo personaggio cancellati."
L["SlashForceBroadcastSent"] = "Trasmissione forzata inviata."
L["SlashDebugEnabled"]       = "|cff00ff00attivato|r"
L["SlashDebugDisabled"]      = "|cffff4444disattivato|r"
L["SlashDebugToggleFormat"]  = "Output di debug %s"

-- ---------------------------------------------------------------------------
-- Nomi delle professioni (ufficiale Blizzard itIT, tutti 15)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alchimia"
L["ProfBlacksmithing"]  = "Forgiatura"
L["ProfCooking"]        = "Cucina"
L["ProfEnchanting"]     = "Incantamento"
L["ProfEngineering"]    = "Ingegneria"
L["ProfFirstAid"]       = "Pronto soccorso"
L["ProfLeatherworking"] = "Lavorazione del cuoio"
L["ProfMining"]         = "Estrazione mineraria"
L["ProfTailoring"]      = "Sartoria"
L["ProfHerbalism"]      = "Erboristeria"
L["ProfSkinning"]       = "Scuoiatura"
L["ProfJewelcrafting"]  = "Gioielleria"
L["ProfInscription"]    = "Iscrizione"
L["ProfFishing"]        = "Pesca"
L["ProfSmelting"]       = "Fusione"

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
