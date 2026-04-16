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
L["WindowTitle"]        = "|cffda8cffTOG Profession Master|r"
L["SyncLogTitle"]       = "TOG Profession Master \226\128\148 Sync Log"

-- Tab labels
L["TabProfessions"]     = "Professions"
L["TabCooldowns"]       = "Cooldowns"
L["TabReagents"]        = "Reagents"

-- ---------------------------------------------------------------------------
-- Browser tab
-- ---------------------------------------------------------------------------
L["SearchPlaceholder"]  = "Search recipes\226\128\166"
L["ViewGuild"]          = "Guild"
L["ViewMine"]           = "My Characters"
L["PanelProfessions"]   = "Professions"
L["PanelCharacters"]    = "Characters"
L["SelectProfession"]   = "Select a profession"
L["NoDataYet"]          = "|cffaaaaaa(no data yet)|r"
L["SelectProfHint"]     = "|cffaaaaaa\226\134\144 Select a profession to see who knows it.|r"
L["NoProfMembers"]      = "|cffaaaaaa(no guild members with this profession)|r"
L["BackToCharacters"]   = "|cff00aaff\226\134\144 Back to characters|r"
L["NoMatchingRecipes"]  = "|cffaaaaaa(no matching recipes)|r"
L["AddToShoppingList"]  = "+"

-- ---------------------------------------------------------------------------
-- Cooldowns tab
-- ---------------------------------------------------------------------------
L["ReadyOnly"]              = "Ready Only"
L["ShowAll"]                = "All"
L["ColCharacter"]           = "Character"
L["ColCooldown"]            = "Cooldown"
L["ColReagent"]             = "Reagent"
L["ColTimeLeft"]            = "Time Left"
L["NoCooldownData"]         = "|cffaaaaaa(no cooldown data yet \226\128\148 open a trade skill window)|r"
L["Ready"]                  = "|cff00ff00Ready|r"
L["BankBtn"]                = "[Bank]"
L["CloseBtn"]               = "Close"

-- ---------------------------------------------------------------------------
-- Shopping list tab
-- ---------------------------------------------------------------------------
L["SectionShoppingList"]    = "Shopping List"
L["SectionMissingReagents"] = "Missing Reagents"
L["SectionReagentWatch"]    = "Reagent Watch"
L["ShoppingListEmpty"]      = "|cffaaaaaa(empty \226\128\148 use the + button in the Professions tab to add items to your shopping list)|r"
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
-- Settings
-- ---------------------------------------------------------------------------
L["SettingsDisplayHeader"]  = "Display"
L["SettingsMinimapBtn"]     = "Show minimap button"
L["SettingsMinimapBtnDesc"] = "Show or hide the minimap launcher button."
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
