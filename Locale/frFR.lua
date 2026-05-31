-- TOG Profession Master -- French (frFR) locale
-- Any missing key falls back to enUS automatically via AceLocale.
-- Translations are best-effort; native-speaker review welcome.

local _, addon = ...
local L = addon.NewLocale("frFR")

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master — Journal de synchronisation"

-- Tab labels
L["TabProfessions"]     = "Métiers"
L["TabCooldowns"]       = "Récupérations"
L["TabReagents"]        = "Composants"
L["TabMissingRecipes"]  = "Recettes manquantes"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Rechercher des recettes…"
L["ViewGuild"]          = "Guilde"
L["ViewMine"]           = "Mes personnages"
L["AllProfessions"]     = "Tous les métiers"
L["PanelProfessions"]   = "Métiers"
L["PanelCharacters"]    = "Personnages"
L["SelectProfession"]   = "Choisissez un métier"
L["NoDataYet"]          = "|cffaaaaaa(aucune donnée pour l’instant)|r"
L["SelectProfHint"]     = "|cffaaaaaa← Choisissez un métier pour voir qui le connaît.|r"
L["NoProfMembers"]      = "|cffaaaaaa(aucun membre de guilde avec ce métier)|r"
L["BackToCharacters"]   = "|cff00aaff← Retour aux personnages|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(aucune recette correspondante)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "Vous"
L["BrowserScanAH"]          = "Scanner l’HV"
L["BrowserScanAHProgress"]  = "Scan %d/%d"
L["BrowserScanAHDesc"]      = "Scanne l’hôtel des ventes pour chaque composant de votre liste de courses. Les lignes dont le composant est actuellement à l’HV reçoivent un bouton [HV] ; cliquez dessus pour sauter directement à la recherche correspondante."
L["CooldownsScanAHDesc"]    = "Scanne l’hôtel des ventes pour chaque composant unique des lignes de récupération visibles. Les lignes dont le composant est actuellement à l’HV reçoivent un bouton [HV] (à gauche de [Banque]) ; cliquez dessus pour sauter à la recherche."

-- Recipe detail popup
L["PopupCrafters"]       = "Connue par"
L["PopupOnList"]         = "Sur la liste de courses"
L["PopupNotOnList"]      = "Pas sur la liste"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Prêt uniquement"
L["ShowAll"]                = "Tout"
L["FilterColProfession"]    = "Métier"
L["FilterColCooldown"]      = "Récupération"
L["FilterColView"]          = "Vue"
L["FilterProfessionDesc"]   = "Filtre la liste des récupérations sur un seul métier (Alchimie, Couture, etc.)."
L["FilterCooldownDesc"]     = "Au sein du métier sélectionné, filtre sur une seule récupération partagée (par ex. Transmutation, Étoffe de lune)."
L["FilterViewDesc"]         = "Bascule entre les récupérations de tous les membres de la guilde et seulement vos propres personnages."
L["AllCooldowns"]           = "Toutes les récupérations"
-- Cooldown filter entry labels
L["FilterTransmute"]            = "Transmutation"
L["FilterAlchResearch"]         = "Recherche en alchimie"
L["FilterMooncloth"]            = "Étoffe de lune"
L["FilterSpecialtyCloth"]       = "Étoffe de spécialité"
L["FilterGlacialBag"]           = "Sac glaciaire"
L["FilterDreamcloth"]           = "Étoffe onirique"
L["FilterImperialSilk"]         = "Soie impériale"
L["FilterSaltShaker"]           = "Salière"
L["FilterMagicSphere"]          = "Sphère magique"
L["FilterShaCrystal"]           = "Cristal de sha"
L["FilterBrilliantGlass"]       = "Verre brillant"
L["FilterIcyPrism"]             = "Prisme glacial"
L["FilterFirePrism"]            = "Prisme de feu"
L["FilterJcDaily"]              = "Taille quotidienne (Joaillerie)"
L["FilterInscriptionResearch"]  = "Recherche en calligraphie"
L["FilterForgedDocuments"]      = "Documents falsifiés"
L["FilterScrollOfWisdom"]       = "Parchemin de sagesse"
L["FilterTitansteelBar"]        = "Barre de titacier"
L["FilterBsIngot"]              = "Fonte"
L["FilterMagnificence"]         = "Magnificence"
L["FilterJards"]                = "Énergie de Jard"
L["ColCharacter"]           = "Personnage"
L["ColCooldown"]            = "Récupération"
L["ColReagent"]             = "Composant"
L["ColTimeLeft"]            = "Temps restant"
L["NoCooldownData"]         = "|cffaaaaaa(aucune donnée de récupération — ouvrez une fenêtre de métier)|r"
L["Ready"]                  = "|cff00ff00Prêt|r"
L["Transmute"]              = "Transmutation"
L["MailBtn"]                = "Courrier"
L["MailBtnTooltip"]         = "Envoyer un courrier de fournitures"
L["MailBtnTooltipDesc"]     = "Ouvrez une boîte aux lettres puis cliquez pour joindre les composants et rédiger un courrier de fournitures à ce joueur."
L["BankBtn"]                = "[Banque]"
L["CloseBtn"]               = "Fermer"

-- Indicateur de bonus de spécialisation de métier
L["SpecBonusGuaranteedDouble"]  = "Production 2x garantie"
L["SpecBonusProcChance"]        = "Chance de production supplémentaire"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Liste de courses"
L["SectionMissingReagents"] = "Composants manquants"
L["SectionReagentWatch"]    = "Surveillance des composants"
L["ShoppingListEmpty"]      = "|cffaaaaaa(vide — cliquez une ligne de recette dans l’onglet Métiers pour ajouter des objets à votre liste)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(la liste de courses est vide ou tous les composants sont dans les sacs)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(aucun objet surveillé — entrez un ID d’objet ou un lien ci-dessus)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(module ReagentWatch non chargé)|r"
L["WatchInputLabel"]        = "ID d’objet ou lien"
L["WatchBtn"]               = "Surveiller"
L["WatchedItemsHeading"]    = "Objets surveillés"
L["ColHave"]                = "Possédé"
L["ColNeed"]                = "Requis"
L["ColShort"]               = "Manque"
L["ColItem"]                = "Objet"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Personnage|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Métier|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Rechercher des recettes…|r"
L["MissingIncludeTrainer"]      = "Inclure exclusives au maître"
L["MissingIncludeTrainerDesc"]  = "Inclut les recettes qui ne s’apprennent que chez un maître de métier (pas de parchemin à l’HV)."
L["MissingScanAH"]              = "Scanner l’HV"
L["MissingScanAHProgress"]      = "Scan %d/%d (cliquez pour annuler)"
L["MissingScanAHDesc"]          = "Ouvrez l’hôtel des ventes puis cliquez pour le scanner à la recherche de chaque parchemin de recette de la liste visible. Les lignes dont le parchemin est mis en vente reçoivent un bouton [HV] ; cliquez dessus pour sauter à la recherche."
L["MissingNoCharacters"]        = "|cffaaaaaa(aucun personnage avec données de métier — ouvrez une fenêtre de métier)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(ce personnage n’a encore aucun métier suivi — ouvrez une fenêtre de métier)|r"
L["MissingNoneFound"]           = "|cff00ff00Toutes les recettes connues de ce métier ont été apprises.|r"
L["MissingPickProfession"]      = "|cffaaaaaa← Choisissez un métier pour voir ce qui manque.|r"
L["MissingNoData"]              = "|cffff8888(aucune donnée de recette disponible pour ce métier)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Recette"
L["MissingColSkill"]            = "Compétence"
L["MissingColSource"]           = "Sources"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Surveiller ce parchemin de recette"
L["MissingAddToWatchDesc"]      = "Ajoute le parchemin de recette à votre liste de surveillance des composants pour le voir dès qu’il atterrit dans vos sacs."
L["MissingRemoveFromWatch"]     = "✓"
L["MissingRemoveFromWatchTooltip"] = "Déjà sous surveillance — cliquez pour arrêter"
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Recette manquante"
L["MissingCountPlural"]         = "Recettes manquantes"
L["MissingTruncatedHint"]       = "(affiche les %d premières — tapez dans la zone de recherche pour réduire la liste)"
L["MissingCharTooltipTitle"]    = "Filtre par personnage"
L["MissingCharTooltipDesc"]     = "Choisissez pour lequel de vos personnages afficher les recettes manquantes. Par défaut, le personnage actuellement connecté."
L["MissingProfTooltipTitle"]    = "Filtre par métier"
L["MissingProfTooltipDesc"]     = "Choisissez un métier pour voir les parchemins que ce personnage n’a pas encore appris."
L["MissingSearchTooltipTitle"]  = "Rechercher des recettes"
L["MissingSearchTooltipDesc"]   = "Tapez pour filtrer la liste des recettes manquantes par nom."
L["MissingHdrCountTitle"]       = "Recettes manquantes"
L["MissingHdrCountDesc"]        = "Recettes que le personnage sélectionné n’a pas encore apprises mais qui sont disponibles dans cette version du jeu. Le nombre reflète le filtre actuel (métier, recherche, bouton maître)."
L["MissingHdrSkillTitle"]       = "Niveau de compétence"
L["MissingHdrSkillDesc"]        = "Le niveau de compétence requis pour apprendre cette recette. Les lignes grisées indiquent que le personnage n’est pas encore assez haut."
L["MissingHdrSourceTitle"]      = "Sources"
L["MissingHdrSourceDesc"]       = "Comment obtenir cette recette — maître, butin, marchand, quête ou fabrication. Survolez le texte de source d’une ligne pour le PNJ / monstre / étape précis."
L["MissingRowTooltipShift"]     = "Maj-clic pour lier dans le chat."
L["MissingSrcVendor"]           = "Marchand"
L["MissingSrcDrop"]             = "Butin"
L["MissingSrcQuest"]            = "Quête"
L["MissingSrcCrafted"]          = "Fabrication"
L["MissingSrcFishing"]          = "Pêche"
L["MissingSrcContainer"]        = "Conteneur"
L["MissingSrcTrainer"]          = "Maître"
L["MissingSrcOther"]            = "Autre"
L["MissingSrcUnknown"]          = "Inconnue"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Infobulle d’objet"
L["SettingsTooltipShowCrafters"]    = "Afficher les artisans de la guilde sur les infobulles d’objet"
L["SettingsTooltipShowCraftersDesc"]= "Ajoute une ligne [TOGPM] listant chaque compagnon de guilde capable de fabriquer l’objet survolé. Artisans en ligne en blanc, hors ligne en gris. Les objets liés quand ramassés sont ignorés (de toute façon non échangeables)."
L["SettingsTooltipShowIds"]         = "Afficher l’ID d’objet / de sort sur les infobulles"
L["SettingsTooltipShowIdsDesc"]     = "Ajoute une ligne [TOGPM] avec l’ID d’objet et (si connu) l’ID de sort de la recette. Surtout utile pour diagnostiquer des icônes incorrectes ou des recettes manquantes — collez les IDs dans Wowhead pour vérifier la correspondance."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "Phase TBC Anniversary"
L["SettingsTBCPhase"]           = "Phase de contenu actuelle"
L["SettingsTBCPhaseDesc"]       = "Masque les Recettes manquantes issues de phases ultérieures à celle d’Anniversary en cours. Augmentez cette valeur à chaque avancée de phase. (Les recettes déjà accessibles dans la phase active restent visibles.)"
L["SettingsTBCPhase1"]          = "Phase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Phase 2 — Caverne du Sanctuaire du serpent / Donjon de la tempête"
L["SettingsTBCPhase3"]          = "Phase 3 — Temple noir / Mont Hyjal"
L["SettingsTBCPhase4"]          = "Phase 4 — Puits de soleil / Terrasse des Magistères"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Affichage"
L["SettingsMinimapBtn"]          = "Afficher le bouton de minicarte"
L["SettingsMinimapBtnDesc"]      = "Affiche ou masque le bouton de lancement sur la minicarte."
L["SettingsPersistProfFilter"]     = "Mémoriser le filtre de métier"
L["SettingsPersistProfFilterDesc"] = "Restaure le métier sélectionné lors de la connexion ou du rechargement."
L["SettingsCooldownsHeader"]= "Récupérations"
L["SettingsMailReadyOnly"]  = "Courrier : afficher uniquement les récupérations prêtes"
L["SettingsMailReadyOnlyDesc"] = "Lors de la rédaction de courriers de fournitures depuis le panneau des récupérations, ne liste que les membres dont la récupération est prête."
L["SettingsDevHeader"]      = "Développeur"
L["SettingsDebug"]          = "Sortie de débogage"
L["SettingsDebugDesc"]      = "Affiche des messages de débogage détaillés dans la fenêtre de discussion."
L["SettingsDataHeader"]     = "Données"
L["SettingsSyncNow"]        = "Forcer la resynchronisation"
L["SettingsSyncNowDesc"]    = "Diffuse immédiatement vos données de métier à la guilde."
L["SettingsPurgeGuild"]     = "Purger toutes les données de guilde"
L["SettingsPurgeGuildDesc"] = "Supprime toutes les données de métier et de récupération stockées pour chaque membre de la guilde sur ce compte. Irréversible."
L["SettingsPurgeGuildConfirm"] = "Supprimer TOUTES les données de guilde de ce compte ?"
L["SettingsPurgeMine"]      = "Purger les données de mon personnage"
L["SettingsPurgeMineDesc"]  = "Supprime uniquement les données stockées de votre propre personnage de la base de la guilde."
L["SettingsPurgeMineConfirm"] = "Supprimer vos propres données de métier et de récupération ?"
L["SettingsSyncLogHeader"]  = "Journal de synchronisation"
L["SettingsViewLog"]        = "Voir le journal de synchronisation"
L["SettingsViewLogDesc"]    = "Ouvre une liste défilante des événements de synchronisation récents (200 derniers)."
L["SettingsClearLog"]       = "Vider le journal de synchronisation"
L["SettingsClearLogConfirm"]= "Effacer toutes les entrées du journal de synchronisation ?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(module SyncLog non chargé)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(aucun événement de synchronisation enregistré)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Bouton de minicarte masqué. Utilisez |cffda8cff/togpm minimap|r pour le restaurer."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Fabriqué par :"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Prêt à fabriquer :|r %s × %d  (%s × %d dans les sacs)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Activer l’alerte d’artisan pour cette recette"
L["ShoppingAlertDisable"]              = "Désactiver l’alerte d’artisan pour cette recette"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s est en ligne — peut fabriquer : %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s est en ligne (alt de %s) — peut fabriquer : %s"

-- Cooldown-ready alert
L["CooldownAlertEnable"]               = "Activer l’alerte de prêt pour cette récupération"
L["CooldownAlertDisable"]              = "Désactiver l’alerte de prêt pour cette récupération"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Récupération prête : %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Alertes d’artisan"
L["SettingsCrafterAlert"]              = "Activer les alertes d’artisan"
L["SettingsCrafterAlertDesc"]          = "Joue un son et fait clignoter l’écran lorsqu’un membre de la guilde capable de fabriquer un objet alerté de la liste de courses se connecte."
L["SettingsCrafterAlertSuppressAV"]    = "Supprimer son et clignotement"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Désactive les effets audio et le clignotement d’écran (le message de chat reste affiché)."
L["SettingsCrafterAlertSuppressLogin"]     = "Supprimer les alertes à la connexion"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Ne déclenche pas d’alertes pendant la rafale initiale de notifications de connexion au login ou rechargement."
L["SettingsCooldownAlertSuppressProtected"]     = "Mettre en sourdine les alertes en instance"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Ne déclenche ni n’affiche d’alerte de récupération prête en raid, donjon, champ de bataille, arène ou scénario. Les capitales NE sont PAS supprimées — votre transmutation continuera à pinger pendant que vous êtes AFK à Hurlevent. Les alertes en attente se déclenchent dès la sortie de l’instance."
L["SettingsCooldownReminderInterval"]      = "Rappel de récupération prête"
L["SettingsCooldownReminderIntervalDesc"]  = "Re-déclenche chaque alerte de récupération armée toutes les N minutes tant que la récupération reste prête (jusqu’à ce que vous fabriquiez réellement). Entrez 0, vide ou 'off' pour ne déclencher qu’une fois par cycle de prêt. Plage valide : 1–1440 minutes (24 heures)."
L["SettingsCooldownReminderInvalid"]       = "Entrez un entier entre 0 et 1440, ou 'off'."

L["SettingsAHHeader"]                      = "Hôtel des ventes"
L["SettingsAHScanDelay"]                   = "Délai de scan HV (secondes)"
L["SettingsAHScanDelayDesc"]               = "Secondes entre chaque requête de scan HV. Vide / 0 / 'off' utilise la valeur par défaut de la version (1.5s sur Classic Era et Anniversary ; 3.0s sur TBC, Wrath, Cata, MoP — ces serveurs sont plus stricts). Réduisez pour des scans plus rapides, augmentez si les scans se bloquent. Plage valide : 0.5–10 secondes."
L["SettingsAHScanDelayInvalid"]            = "Entrez un nombre de 0.5 à 10, ou 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Recette"
L["TooltipRecipeDesc"]           = "Le nom de l’objet fabricable ou du sort."
L["TooltipCraftersTitle"]        = "Artisans"
L["TooltipCraftersDesc"]         = "Membres de guilde qui connaissent cette recette. Cliquez une recette pour la liste complète."
L["CraftersColHeader"]           = "Artisans"
L["TooltipBankTitle"]            = "Demander à la banque"
L["TooltipBankDescScroll"]       = "Envoie une demande à un banquier de guilde TOGBankClassic pour ce parchemin de recette."
L["TooltipBankDescGeneric"]      = "Envoie une demande à un banquier de guilde TOGBankClassic."
L["TooltipAHTitle"]              = "Rechercher à l’hôtel des ventes"
L["TooltipAHDescScroll"]         = "Ouvre ce parchemin de recette dans la recherche HV."
L["TooltipAHDescReagent"]        = "Ouvre ce composant dans la recherche HV."
L["TooltipSettingsTitle"]        = "Paramètres"
L["TooltipSettingsDesc"]         = "Ouvre le panneau de paramètres de TOG Profession Master (|cffffd700ÉCHAP > Options > AddOns > TOG Profession Master|r). Même cible que |cffffd700/togpm settings|r et Maj+clic gauche sur le bouton de minicarte."
L["TooltipWhisperRightClick"]    = "Clic droit pour chuchoter"
L["TooltipClickTransmutes"]      = "Cliquez pour voir les transmutations"
L["TooltipClickDetailsFormat"]   = "Cliquez pour voir %s"
L["TooltipClickDetailsFallback"] = "les détails"

-- ---------------------------------------------------------------------------
-- Mail composer
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Fournitures de récupération : %s"
L["MailBodyFormat"]         = "Salut %s ! Utilise s’il te plaît ces matériaux pour fabriquer %s. Renvoie-moi le %s quand tu auras le temps. Merci !"
L["MailMsgNoEmptyBag"]      = "Aucun emplacement de sac vide pour la division."
L["MailMsgOpenMailbox"]     = "Ouvrez d’abord une boîte aux lettres."
L["MailMsgHasItems"]        = "Le courrier a déjà des objets attachés — envoyez-les ou retirez-les d’abord."
L["MailMsgCannotFulfill"]   = "Impossible de remplir."
L["MailMsgCouldNotAttach"]  = "Impossible d’attacher les objets."
L["MailMsgAttachedFormat"]  = "%dx %s attachés pour %s."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Clic gauche|r pour afficher/masquer le navigateur de métiers"
L["MinimapTooltipRightClick"]  = "|cffffd100Clic droit|r pour afficher/masquer les composants"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Maj+gauche|r ouvre les paramètres"
L["MinimapButtonShown"]        = "Bouton de minicarte affiché."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help) -- les noms de commande ne sont pas traduits
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r — commandes :"
L["SlashHelpOpen"]          = "ouvre le navigateur de métiers"
L["SlashHelpReagents"]      = "ouvre les composants manquants"
L["SlashHelpMinimap"]       = "affiche le bouton de minicarte"
L["SlashHelpPurge"]         = "ouvre la boîte de dialogue de purge"
L["SlashHelpSync"]          = "force une resynchronisation complète de la guilde"
L["SlashHelpStatus"]        = "affiche les infos de diagnostic sync/comm"
L["SlashHelpVersionCheck"]  = "vérifie les versions de l’addon dans la guilde"
L["SlashHelpDebug"]         = "active/désactive la sortie de débogage"
L["SlashHelpHelp"]          = "affiche cette liste"
L["SlashForceSyncSent"]     = "Synchronisation forcée envoyée."
L["AHScannerOpenAH"]        = "Ouvrez l’hôtel des ventes pour rechercher."
L["AHOpenFirst"]            = "Ouvrez d’abord l’hôtel des ventes."
L["AHNoItemsToScan"]        = "Aucun objet à scanner dans la vue actuelle."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Demande à la banque de guilde"
L["BankDialogBanker"]       = "Banquier :"
L["BankDialogQty"]          = "Qté :"
L["BankDialogSend"]         = "Envoyer la demande"
L["BankDialogCancel"]       = "Annuler"

-- ---------------------------------------------------------------------------
-- Confirmations de purge & autres sorties de commandes
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "Toutes les données de guilde purgées."
L["MsgOwnDataPurged"]        = "Données de votre personnage purgées."
L["SlashForceBroadcastSent"] = "Diffusion forcée envoyée."
L["SlashDebugEnabled"]       = "|cff00ff00activée|r"
L["SlashDebugDisabled"]      = "|cffff4444désactivée|r"
L["SlashDebugToggleFormat"]  = "Sortie de débogage %s"

-- ---------------------------------------------------------------------------
-- Noms de métiers (officiel Blizzard frFR, les 15)
-- ---------------------------------------------------------------------------
L["ProfAlchemy"]        = "Alchimie"
L["ProfBlacksmithing"]  = "Forge"
L["ProfCooking"]        = "Cuisine"
L["ProfEnchanting"]     = "Enchantement"
L["ProfEngineering"]    = "Ingénierie"
L["ProfFirstAid"]       = "Secourisme"
L["ProfLeatherworking"] = "Travail du cuir"
L["ProfMining"]         = "Minage"
L["ProfTailoring"]      = "Couture"
L["ProfHerbalism"]      = "Herboristerie"
L["ProfSkinning"]       = "Dépeçage"
L["ProfJewelcrafting"]  = "Joaillerie"
L["ProfInscription"]    = "Calligraphie"
L["ProfFishing"]        = "Pêche"
L["ProfSmelting"]       = "Fonte"

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
