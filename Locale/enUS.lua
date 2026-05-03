-- TOG Profession Master — English (enUS) locale
-- This is the authoritative locale and serves as the fallback for all other
-- locales.  Add a new file under Locale/ for each additional language, using
-- the same keys.  Missing keys fall back to the enUS string automatically via
-- AceLocale's silent-fill feature.

local _, addon = ...
local L = LibStub("AceLocale-3.0"):NewLocale("TOGProfessionMaster", "enUS", true)
if not L then return end
addon.L = L

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
L["FilterProfessionDesc"]   = "Filter the cooldown list to a single profession (Alchemy, Tailoring, etc.)."
L["FilterCooldownDesc"]     = "Within the selected profession, filter to a single shared-timer cooldown (e.g. Transmute, Mooncloth)."
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
L["MissingCountFormat"]         = "%d Missing %s"
L["MissingCountSingular"]       = "Recipe"
L["MissingCountPlural"]         = "Recipes"
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

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Display"
L["SettingsMinimapBtn"]          = "Show minimap button"
L["SettingsMinimapBtnDesc"]      = "Show or hide the minimap launcher button."
L["SettingsPersistProfFilter"]     = "Remember profession filter"
L["SettingsPersistProfFilterDesc"] = "Restore the selected profession when you log in or reload."
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

-- Settings
L["SettingsAlertsHeader"]              = "Crafter Alerts"
L["SettingsCrafterAlert"]              = "Enable crafter alerts"
L["SettingsCrafterAlertDesc"]          = "Play a sound and flash the screen when a guild member who can craft an alerted shopping list item comes online."
L["SettingsCrafterAlertSuppressAV"]    = "Suppress sound & flash"
L["SettingsCrafterAlertSuppressAVDesc"]    = "Disable the audio and screen-flash effects (chat message still appears)."
L["SettingsCrafterAlertSuppressLogin"]     = "Suppress alerts on login"
L["SettingsCrafterAlertSuppressLoginDesc"] = "Don't fire alerts during the initial burst of online notifications at login or UI reload."
