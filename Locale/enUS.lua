-- TOG Profession Master — English (enUS) locale
-- This is the authoritative locale and serves as the fallback for all other
-- locales. Add a new file under Locale/ for each additional language, using
-- the same keys. Missing keys fall back to the enUS string automatically via
-- AceLocale's silent-fill feature.
--
-- Uses addon.NewLocale (defined in Locale/_init.lua, which loads first) so
-- writes flow to BOTH AceLocale (auto-detect path) AND addon.Locales.enUS
-- (UI-language-override path).

local _, addon = ...
local L = addon.NewLocale("enUS", true)   -- true = default fallback for missing keys

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
L["WindowTitle"]        = "|c" .. (addon.BrandColor or "ffFF8000") .. "TOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master \226\128\148 Sync Log"

-- Tab labels
L["TabProfessions"]     = "Professions"
L["TabCooldowns"]       = "Cooldowns"
L["TabReagents"]        = "Reagents"
L["TabMissingRecipes"]  = "Missing Recipes"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Search recipes\226\128\166"
L["ViewGuild"]          = "Guild"
L["ViewMine"]           = "My Characters"
L["AllProfessions"]     = "All Professions"
L["PanelProfessions"]   = "Professions"
L["PanelCharacters"]    = "Characters"
L["SelectProfession"]   = "Select a profession"
L["NoDataYet"]          = "|cffaaaaaa(no data yet)|r"
L["SelectProfHint"]     = "|cffaaaaaa\226\134\144 Select a profession to see who knows it.|r"
L["NoProfMembers"]      = "|cffaaaaaa(no guild members with this profession)|r"
L["BackToCharacters"]   = "|cff00aaff\226\134\144 Back to characters|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(no matching recipes)|r"
L["AddToShoppingList"]  = "+"
L["You"]                = "You"
L["BrowserScanAH"]          = "Scan AH"
L["BrowserScanAHProgress"]  = "Scanning %d/%d"
L["BrowserScanAHDesc"]      = "Scan the auction house for every reagent in your shopping list. Reagent rows whose item is currently on the AH get an [AH] button; click that to jump straight to the AH search for it."
L["CooldownsScanAHDesc"]    = "Scan the auction house for every unique reagent in the visible cooldown rows. Rows whose reagent is currently on the AH get an [AH] button (left of [Bank]); click that to jump straight to the AH search for it."

-- Recipe detail popup
L["PopupCrafters"]       = "Known by"
L["PopupOnList"]         = "On shopping list"
L["PopupNotOnList"]      = "Not on shopping list"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Ready Only"
L["ShowAll"]                = "All"
L["FilterColProfession"]    = "Profession"
L["FilterColCooldown"]      = "Cooldown"
L["FilterColView"]          = "View"
L["FilterProfessionDesc"]   = "Filter the cooldown list to a single profession (Alchemy, Tailoring, etc.)."
L["FilterCooldownDesc"]     = "Within the selected profession, filter to a single shared-timer cooldown (e.g. Transmute, Mooncloth)."
L["FilterViewDesc"]         = "Switch between every guild member's cooldowns and just your own characters."
L["AllCooldowns"]           = "All Cooldowns"
-- Cooldown filter entry labels (one per shared-timer entry in
-- COOLDOWN_BY_PROFESSION). Display names shown in the cooldown dropdown.
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
L["FilterJcDaily"]              = "JC Daily Cut"
L["FilterInscriptionResearch"]  = "Inscription Research"
L["FilterForgedDocuments"]      = "Forged Documents"
L["FilterScrollOfWisdom"]       = "Scroll of Wisdom"
L["FilterTitansteelBar"]        = "Titansteel Bar"
L["FilterBsIngot"]              = "Smelting"
L["FilterMagnificence"]         = "Magnificence"
L["FilterJards"]                = "Jard's Energy"
L["ColCharacter"]           = "Character"
L["ColCooldown"]            = "Cooldown"
L["ColReagent"]             = "Reagent"
L["ColTimeLeft"]            = "Time Left"
L["NoCooldownData"]         = "|cffaaaaaa(no cooldown data yet \226\128\148 open a trade skill window)|r"
L["Ready"]                  = "|cff00ff00Ready|r"
L["Transmute"]              = "Transmute"
L["MailBtn"]                = "Mail"
L["MailBtnTooltip"]         = "Send Supply Mail"
L["MailBtnTooltipDesc"]     = "Open a mailbox, then click to attach reagents and compose a supply mail to this player."
L["BankBtn"]                = "[Bank]"
L["CloseBtn"]               = "Close"

-- Profession-spec bonus-output indicator (small icon left of crafter name).
-- The header line on the indicator's tooltip is the spec's name, pulled
-- automatically from GetSpellInfo and localized by the WoW client.
L["SpecBonusGuaranteedDouble"]  = "Guaranteed 2x output"
L["SpecBonusProcChance"]        = "Chance to proc extra output"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Shopping List"
L["SectionMissingReagents"] = "Missing Reagents"
L["SectionReagentWatch"]    = "Reagent Watch"
L["ShoppingListEmpty"]      = "|cffaaaaaa(empty \226\128\148 click a recipe row in the Professions tab to add items to your shopping list)|r"
L["MissingReagentsEmpty"]   = "|cffaaaaaa(shopping list is empty or all reagents are in bags)|r"
L["ReagentWatchEmpty"]      = "|cffaaaaaa(no items being watched \226\128\148 enter an item ID or link above)|r"
L["ReagentWatchModuleMissing"] = "|cffaaaaaa(ReagentWatch module not loaded)|r"
L["WatchInputLabel"]        = "Item ID or link"
L["WatchBtn"]               = "Watch"
L["WatchedItemsHeading"]    = "Watched Items"
L["ColHave"]                = "Have"
L["ColNeed"]                = "Need"
L["ColShort"]               = "Short"
L["ColItem"]                = "Item"

-- ---------------------------------------------------------------------------
-- Missing Recipes tab
-- ---------------------------------------------------------------------------
L["MissingCharacterLabel"]      = "|c" .. (addon.BrandColor or "ffFF8000") .. "Character|r"
L["MissingProfessionLabel"]     = "|c" .. (addon.BrandColor or "ffFF8000") .. "Profession|r"
L["MissingSearchLabel"]         = "|c" .. (addon.BrandColor or "ffFF8000") .. "Search recipes\226\128\166|r"
L["MissingIncludeTrainer"]      = "Include trainer-only"
L["MissingIncludeTrainerDesc"]  = "Include recipes that can only be learned from a trainer (no AH scroll)."
L["MissingScanAH"]              = "Scan AH"
L["MissingScanAHProgress"]      = "Scanning %d/%d (click to cancel)"
L["MissingScanAHDesc"]          = "Open the auction house, then click to scan it for every recipe scroll currently in the visible list. Rows whose scroll has live listings get an [AH] button; click that to jump to the AH search for it."
L["MissingNoCharacters"]        = "|cffaaaaaa(no characters with profession data yet \226\128\148 open a trade skill window)|r"
L["MissingNoProfessions"]       = "|cffaaaaaa(this character has no professions tracked yet \226\128\148 open a trade skill window)|r"
L["MissingNoneFound"]           = "|cff00ff00All known recipes for this profession have been learned.|r"
L["MissingPickProfession"]      = "|cffaaaaaa\226\134\144 Pick a profession to see what's missing.|r"
L["MissingNoData"]              = "|cffff8888(no recipe data available for this profession)|r"
L["MissingColIcon"]             = ""
L["MissingColRecipe"]           = "Recipe"
L["MissingColSkill"]            = "Skill"
L["MissingColSource"]           = "Sources"
L["MissingAddToWatch"]          = "+"
L["MissingAddToWatchTooltip"]   = "Watch this recipe scroll"
L["MissingAddToWatchDesc"]      = "Add the recipe scroll to your Reagent Watch list so you'll see it the moment it lands in your bags."
L["MissingRemoveFromWatch"]     = "\226\156\147"
L["MissingRemoveFromWatchTooltip"] = "Already on Reagent Watch \226\128\148 click to stop watching"
-- Format intentionally "%d %s" so the inflected adjective travels with the
-- singular/plural noun phrase (German adjective endings differ; English doesn't).
L["MissingCountFormat"]         = "%d %s"
L["MissingCountSingular"]       = "Missing Recipe"
L["MissingCountPlural"]         = "Missing Recipes"
L["MissingTruncatedHint"]       = "(showing first %d \226\128\148 type in the search box to narrow the list)"
L["MissingCharTooltipTitle"]    = "Character Filter"
L["MissingCharTooltipDesc"]     = "Pick which of your characters to view missing recipes for. Defaults to the currently logged-in character."
L["MissingProfTooltipTitle"]    = "Profession Filter"
L["MissingProfTooltipDesc"]     = "Choose a profession to see scrolls this character hasn't learned yet."
L["MissingSearchTooltipTitle"]  = "Search Recipes"
L["MissingSearchTooltipDesc"]   = "Type to filter the missing-recipe list by name."
L["MissingHdrCountTitle"]       = "Missing Recipes"
L["MissingHdrCountDesc"]        = "Recipes the selected character hasn't learned yet but are obtainable in this version of the game. The number reflects the current filter (profession, search, trainer toggle)."
L["MissingHdrSkillTitle"]       = "Skill Level"
L["MissingHdrSkillDesc"]        = "The profession skill rank required to learn this recipe. Greyed-out rows mean the character isn't high enough yet."
L["MissingHdrSourceTitle"]      = "Sources"
L["MissingHdrSourceDesc"]       = "How to obtain this recipe \226\128\148 trainer, drop, vendor, quest, or crafted. Hover the source text on a row for the specific NPC / mob / step."
L["MissingRowTooltipShift"]     = "Shift-click to link in chat."
L["MissingSrcVendor"]           = "Vendor"
L["MissingSrcDrop"]             = "Drop"
L["MissingSrcQuest"]            = "Quest"
L["MissingSrcCrafted"]          = "Crafted"
L["MissingSrcFishing"]          = "Fishing"
L["MissingSrcContainer"]        = "Container"
L["MissingSrcTrainer"]          = "Trainer"
L["MissingSrcOther"]            = "Other"
L["MissingSrcUnknown"]          = "Unknown"

-- Settings: global item tooltip lines
L["SettingsTooltipHeader"]          = "Item tooltip"
L["SettingsTooltipShowCrafters"]    = "Show guild crafters on item tooltips"
L["SettingsTooltipShowCraftersDesc"]= "Append a [TOGPM] line listing every guildmate who can craft the item you're hovering. Online crafters in white, offline in grey. Bind-on-Pickup items are skipped (can't be traded anyway)."
L["SettingsTooltipShowIds"]         = "Show item ID / spell ID on item tooltips"
L["SettingsTooltipShowIdsDesc"]     = "Append a [TOGPM] line with the item ID and (if known) the recipe spell ID. Mostly useful for troubleshooting wrong icons or missing recipes — paste the IDs into Wowhead to verify what the addon is matching against."

-- Settings: TBC Anniversary phase filter
L["SettingsTBCPhaseHeader"]     = "TBC Anniversary phase"
L["SettingsTBCPhase"]           = "Current content phase"
L["SettingsTBCPhaseDesc"]       = "Hide Missing Recipes that come from later phases than the one Anniversary is currently in. Bump this each time Blizzard advances the phase. (Recipes you can already access on the live phase stay visible.)"
L["SettingsTBCPhase1"]          = "Phase 1 — Karazhan / Gruul / Magtheridon"
L["SettingsTBCPhase2"]          = "Phase 2 — Serpentshrine Cavern / Tempest Keep"
L["SettingsTBCPhase3"]          = "Phase 3 — Black Temple / Mount Hyjal"
L["SettingsTBCPhase4"]          = "Phase 4 — Sunwell / Magisters' Terrace"

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Display"
L["SettingsMinimapBtn"]          = "Show minimap button"
L["SettingsMinimapBtnDesc"]      = "Show or hide the minimap launcher button."
L["SettingsPersistProfFilter"]     = "Remember profession filter"
L["SettingsPersistProfFilterDesc"] = "Restore the selected profession when you log in or reload."
L["SettingsUILangOverride"]        = "UI Language Override"
L["SettingsUILangOverrideDesc"]    = "Force the TOGPM addon UI (tabs, buttons, tooltips, settings) into a specific language regardless of your WoW client's language. \"Auto\" follows your WoW client's language. In-game item / spell / recipe names still render in the client's actual language since those come from Blizzard's APIs, not from this addon. Includes Thai and Filipino, which Blizzard's client doesn't natively support but TOGPM ships translations for via this override."
L["SettingsUILangAuto"]            = "Auto (use WoW client language)"
L["SettingsUILangReloadHint"]      = "UI language changed. Type |cffffd100/reload|r for the change to apply everywhere."
L["SettingsCooldownsHeader"]= "Cooldowns"
L["SettingsMailReadyOnly"]  = "Mail: show ready cooldowns only"
L["SettingsMailReadyOnlyDesc"] = "When composing supply mail from the cooldowns panel, only list guild members whose cooldown is ready."
L["SettingsDevHeader"]      = "Developer"
L["SettingsDebug"]          = "Debug output"
L["SettingsDebugDesc"]      = "Print verbose debug messages to the chat frame."
L["SettingsDataHeader"]     = "Data"
L["SettingsSyncNow"]        = "Force re-sync"
L["SettingsSyncNowDesc"]    = "Broadcast your profession data to the guild immediately."
L["SettingsPurgeGuild"]     = "Purge all guild data"
L["SettingsPurgeGuildDesc"] = "Delete all stored profession and cooldown data for every guild member on this account.  Cannot be undone."
L["SettingsPurgeGuildConfirm"] = "Delete ALL guild data for this account?"
L["SettingsPurgeMine"]      = "Purge my character data"
L["SettingsPurgeMineDesc"]  = "Delete only your own character's stored data from the guild database."
L["SettingsPurgeMineConfirm"] = "Delete your own profession and cooldown data?"
L["SettingsSyncLogHeader"]  = "Sync Log"
L["SettingsViewLog"]        = "View sync log"
L["SettingsViewLogDesc"]    = "Open a scrollable list of recent sync events (last 200)."
L["SettingsClearLog"]       = "Clear sync log"
L["SettingsClearLogConfirm"]= "Clear all sync log entries?"

-- ---------------------------------------------------------------------------
-- Sync log
-- ---------------------------------------------------------------------------
L["SyncLogModuleMissing"]   = "|cffaaaaaa(SyncLog module not loaded)|r"
L["SyncLogNoEntries"]       = "|cffaaaaaa(no sync events recorded yet)|r"

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
L["MinimapHidden"]          = "Minimap button hidden. Use |cffda8cff/togpm minimap|r to restore."

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
L["CraftedBy"]              = "Crafted by:"

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
L["AlertReadyFormat"]       = "|cff00ff00Ready to craft:|r %s \195\151 %d  (%s \195\151 %d in bags)"

-- Shopping list crafter alert
L["ShoppingAlertEnable"]               = "Enable crafter alert for this recipe"
L["ShoppingAlertDisable"]              = "Disable crafter alert for this recipe"
L["AlertCrafterOnline"]                = "|cffFFD700[TOGPM]|r %s is online — can craft: %s"
L["AlertCrafterOnlineAlt"]             = "|cffFFD700[TOGPM]|r %s is online (alt of %s) — can craft: %s"

-- Cooldown-ready alert (own characters only; toggled per row in the Cooldowns tab)
L["CooldownAlertEnable"]               = "Enable ready alert for this cooldown"
L["CooldownAlertDisable"]              = "Disable ready alert for this cooldown"
L["AlertCooldownReady"]                = "|cff00ffff[TOGPM]|r Cooldown ready: %s — %s"

-- Settings
L["SettingsAlertsHeader"]              = "Crafter Alerts"
L["SettingsCrafterAlert"]              = "Enable crafter alerts"
L["SettingsCrafterAlertDesc"]          = "Play a sound and flash the screen when a guild member who can craft an alerted shopping list item comes online."
L["SettingsCrafterAlertSuppressAV"]    = "Suppress sound & flash"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Disable the audio and screen-flash effects (chat message still appears)."
L["SettingsCrafterAlertSuppressLogin"]     = "Suppress alerts on login"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Don't fire alerts during the initial burst of online notifications at login or UI reload."
L["SettingsCooldownAlertSuppressProtected"]     = "Mute alerts in instances"
L["SettingsCooldownAlertSuppressProtectedDesc"] = "Don't ping or print cooldown-ready alerts while in a raid, dungeon, battleground, arena, or scenario. Capital cities are NOT suppressed — your transmute will still ping while you're AFK in Stormwind. Pending alerts fire the moment you leave the instance."
L["SettingsCooldownReminderInterval"]      = "Cooldown ready reminder"
L["SettingsCooldownReminderIntervalDesc"]  = "Re-fire each armed cooldown alert every N minutes while the cooldown stays ready (i.e. until you actually craft). Enter 0, empty, or 'off' to fire only once per ready cycle. Valid range: 1–1440 minutes (24 hours)."
L["SettingsCooldownReminderInvalid"]       = "Enter a whole number from 0 to 1440, or 'off'."

L["SettingsAHHeader"]                      = "Auction House"
L["SettingsAHScanDelay"]                   = "AH scan delay (seconds)"
L["SettingsAHScanDelayDesc"]               = "Seconds between AH scan queries. Empty / 0 / 'off' uses the version default (1.5s on Classic Era and Anniversary; 3.0s on TBC, Wrath, Cata, MoP — those servers throttle stricter). Lower it for faster scans, raise it if scans stall. Valid range: 0.5–10 seconds."
L["SettingsAHScanDelayInvalid"]            = "Enter a number from 0.5 to 10, or 'off'."

-- ---------------------------------------------------------------------------
-- Tooltips & button hover-text (column headers, action buttons)
-- ---------------------------------------------------------------------------
L["TooltipRecipeTitle"]          = "Recipe"
L["TooltipRecipeDesc"]           = "The name of the craftable item or spell."
L["TooltipCraftersTitle"]        = "Crafters"
L["TooltipCraftersDesc"]         = "Guild members who know this recipe. Click a recipe for the full list."
L["CraftersColHeader"]           = "Crafters"
L["TooltipBankTitle"]            = "Request from Bank"
L["TooltipBankDescScroll"]       = "Send a request to a TOGBankClassic guild banker for this recipe scroll."
L["TooltipBankDescGeneric"]      = "Send a request to a TOGBankClassic guild banker."
L["TooltipAHTitle"]              = "Search Auction House"
L["TooltipAHDescScroll"]         = "Open this recipe scroll in the AH browse search."
L["TooltipAHDescReagent"]        = "Open this reagent in the AH browse search."
L["TooltipSettingsTitle"]        = "Settings"
L["TooltipSettingsDesc"]         = "Open the TOG Profession Master settings panel (|cffffd700ESC > Options > AddOns > TOG Profession Master|r). Same target as |cffffd700/togpm settings|r and Shift+left-click on the minimap button."
L["TooltipWhisperRightClick"]    = "Right-click to whisper"
L["TooltipClickTransmutes"]      = "Click to see transmutes"
L["TooltipClickDetailsFormat"]   = "Click to see %s"
L["TooltipClickDetailsFallback"] = "details"

-- ---------------------------------------------------------------------------
-- Mail composer (Cooldowns tab supply-mail flow)
-- ---------------------------------------------------------------------------
L["MailSubjectFormat"]      = "Cooldown supply: %s"
L["MailBodyFormat"]         = "Hi %s! Please use these materials to make %s. Please send me the %s when you have time to craft it. Thanks!"
L["MailMsgNoEmptyBag"]      = "No empty bag slot to split into."
L["MailMsgOpenMailbox"]     = "Open a mailbox first."
L["MailMsgHasItems"]        = "Mail already has items attached \226\128\148 send or clear them first."
L["MailMsgCannotFulfill"]   = "Cannot fulfill."
L["MailMsgCouldNotAttach"]  = "Could not attach items."
L["MailMsgAttachedFormat"]  = "Attached %dx %s for %s."

-- ---------------------------------------------------------------------------
-- Minimap button tooltip (LDB)
-- ---------------------------------------------------------------------------
L["MinimapTooltipLeftClick"]   = "|cffffd100Left-click|r to toggle profession browser"
L["MinimapTooltipRightClick"]  = "|cffffd100Right-click|r to toggle reagents"
L["MinimapTooltipShiftLeft"]   = "|cffffd100Shift+Left|r to open settings"
L["MinimapButtonShown"]        = "Minimap button shown."

-- ---------------------------------------------------------------------------
-- Slash command help (/togpm help)
-- Command names (/togpm, reagents, sync, etc.) are NOT translated.
-- ---------------------------------------------------------------------------
L["SlashHelpHeader"]        = "|cffda8cffTOG Profession Master|r \226\128\148 commands:"
L["SlashHelpOpen"]          = "open profession browser"
L["SlashHelpReagents"]      = "open missing reagents"
L["SlashHelpMinimap"]       = "show minimap button"
L["SlashHelpPurge"]         = "open purge dialog"
L["SlashHelpSync"]          = "force full guild re-sync"
L["SlashHelpStatus"]        = "dump sync/comm diagnostic info"
L["SlashHelpVersionCheck"]  = "check addon versions across guild"
L["SlashHelpDebug"]         = "toggle debug output"
L["SlashHelpHelp"]          = "show this list"
L["SlashForceSyncSent"]     = "Force sync sent."
L["AHScannerOpenAH"]        = "Open the auction house to search."
L["AHOpenFirst"]            = "Open the auction house first."
L["AHNoItemsToScan"]        = "No items to scan in the current view."

-- ---------------------------------------------------------------------------
-- Bank request dialog (Compat.lua)
-- ---------------------------------------------------------------------------
L["BankDialogTitle"]        = "Request from Guild Bank"
L["BankDialogBanker"]       = "Banker:"
L["BankDialogQty"]          = "Qty:"
L["BankDialogSend"]         = "Send Request"
L["BankDialogCancel"]       = "Cancel"

-- ---------------------------------------------------------------------------
-- Purge confirmations & misc slash output
-- ---------------------------------------------------------------------------
L["MsgGuildDataPurged"]      = "All guild data purged."
L["MsgOwnDataPurged"]        = "Your character data purged."
L["SlashForceBroadcastSent"] = "Force broadcast sent."
L["SlashDebugEnabled"]       = "|cff00ff00enabled|r"
L["SlashDebugDisabled"]      = "|cffff4444disabled|r"
L["SlashDebugToggleFormat"]  = "Debug output %s"

-- ---------------------------------------------------------------------------
-- Profession display names (feeds addon.PROF_NAMES in TOGProfessionMaster.lua)
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
