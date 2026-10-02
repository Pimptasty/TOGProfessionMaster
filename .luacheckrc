-- luacheck configuration for TOGProfessionMaster.
std = "lua51"

-- WoW globals the addon reads/writes. Not exhaustive — extend as luacheck complains.
read_globals = {
	"LibStub", "CreateFrame", "UIParent", "GameTooltip", "GameFontNormalSmall",
	"hooksecurefunc",
	"GetLocale", "GetBuildInfo", "GetServerTime", "GetTime",
	"GetItemInfo", "GetItemInfoInstant", "GetItemIcon", "GetItemCount",
	"GetSpellInfo", "GetSpellLink", "GetSpellTexture",
	"GetTradeSkillInfo", "GetNumTradeSkills", "GetTradeSkillLine",
	"GetTradeSkillItemLink", "GetTradeSkillRecipeLink", "GetTradeSkillReagentItemLink",
	"GetCraftInfo", "GetNumCrafts", "GetCraftItemLink", "GetCraftDisplaySkillLine",
	"GetNormalizedRealmName", "UnitName", "UnitFactionGroup", "IsShiftKeyDown",
	"IsModifiedClick", "GameTooltip_ShowCompareItem", "GameTooltip_HideShoppingTooltips",
	"ChatFrameUtil", "HandleModifiedItemClick", "GetCVarBool",
	"ChatEdit_InsertLink", "ChatEdit_GetActiveWindow", "UIDropDownMenu_SetWidth",
	"ChatFrame_OpenChat", "DEFAULT_CHAT_FRAME",
	-- Bag/mail/cursor APIs behind the Cooldowns tab's supply-mail button, and
	-- the frames it reads. The container family is `C_Container` ONLY on every
	-- supported flavour (Compat.lua's note); the bare split/pickup globals are
	-- not declared so a call to one is reported.
	"C_Container", "ClearCursor",
	"MailFrame", "MailFrameTab2", "HasSendMailItem", "ClickSendMailItemButton", "ATTACHMENTS_MAX_SEND",
	"SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox", "MailEditBox",
	"BackdropTemplateMixin",
	"SPELL_REAGENTS", "Item", "C_Timer", "C_ChatInfo",
	-- GetScreenHeight is a first-class bare global (GlobalAPI.lua:5509).
	-- C_Item is the modern item namespace. GetItemQualityColor is declared
	-- only as the FALLBACK half of a feature-detect: it is a deprecation
	-- shim that Blizzard_DeprecatedItemScript assigns from
	-- C_Item.GetItemQualityColor, and only when the `loadDeprecationFallbacks`
	-- CVar is on. Never call it unguarded.
	"GetScreenHeight", "C_Item", "GetItemQualityColor",
	-- Compat.lua's shims. `C_AddOns`, `C_Engraving` and `C_Item` are modern
	-- namespaces feature-detected at the point of resolution; `NUM_BAG_SLOTS`
	-- and the bare `GetContainer*` trio are the pre-C_Container spellings kept
	-- as the older-client half of those same shims. All are read behind a
	-- detect, never called blind.
	"C_AddOns", "C_Engraving", "NUM_BAG_SLOTS",
	"GetContainerItemInfo", "GetContainerNumSlots", "GetContainerItemLink",
	-- The pre-C_AddOns spellings, again only as the fallback half of a detect.
	"IsAddOnLoaded", "GetAddOnMetadata",
	-- Blizzard's classic dropdown API, used by the spec picker in Compat.lua.
	"UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
	"UIDropDownMenu_SetText", "UIDropDownMenu_AddButton",
	-- WoW hoists these into _G: `time`/`floor` are the Lua library functions,
	-- GetCoinTextureString is Price.Money's fallback against an ItemDB with no
	-- FormatMoney. (The merchant-capture globals left with the capture itself,
	-- to ItemDB, in v1.1.0.)
	"time", "floor", "GetCoinTextureString",
	-- WorldFrame is the engine-side root frame (used for cursor position);
	-- Menu is Blizzard's modern context-menu namespace, present on the
	-- flavours whose branch reads it and feature-detected at every call site.
	"WorldFrame", "Menu",
	-- TradeSkillMaster's API, feature-detected at every call site: the
	-- crafting-UI hand-off in Modules/Crafting/CraftingEngine.lua. (Auctionator
	-- and AucAdvanced were declared here for the price bridges, which moved to
	-- ItemDB in v1.1.0; nothing in this addon reads either global now.)
	"TSM_API",

	-- ------------------------------------------------------------------
	-- Added 2026-08-19. The header above says "extend as luacheck complains"
	-- and that had stopped happening: a repo-wide run reported ~90 undeclared
	-- names, so EVERY file was permanently non-empty and the report had become
	-- unreadable -- which is how a real defect hides. A name here means only
	-- "this comes from the environment, not from our code"; it is NOT a claim
	-- that a given flavour has it. Where the addon feature-detects (the
	-- C_* namespaces, the modern-vs-classic AH pair) the detect is at the call
	-- site and stays there.
	-- ------------------------------------------------------------------
	-- Lua and utility functions WoW hoists into _G.
	"bit", "date", "wipe", "strtrim", "tinsert", "debugprofilestop",
	-- The unresettable clock Perf.now prefers; C_AddOnProfiler is the client's
	-- own per-addon frame profiler that /togpm perf reads (both feature-detected).
	"GetTimePreciseSec", "C_AddOnProfiler",
	-- Tooltip surfaces. TooltipDataProcessor and Enum are the modern
	-- (Cata/MoP+) hook API, absent on Vanilla/TBC/Wrath and feature-detected
	-- in Tooltip.lua; the four frames are the shopping/compare tooltips.
	"TooltipDataProcessor", "Enum", "ItemRefTooltip",
	"ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
	"FrameUtil",
	-- Auction house. The scanner that read C_AuctionHouse / AuctionFrame / the
	-- Browse* widgets / QueryAuctionItems moved to ItemDB in v1.1.0 and the
	-- names went with it; Modules/AHScanner.lua is a facade over the library
	-- and touches no AH global.
	-- Trade skill / craft / trainer. The Craft* family is Vanilla-only
	-- (Enchanting), the TradeSkill* family is everything else.
	"CloseTradeSkill", "CloseCraft", "DoTradeSkill", "ExpandTradeSkillSubClass",
	"IsTradeSkillLinked", "GetTradeSkillIcon", "GetTradeSkillNumReagents",
	"GetTradeSkillReagentInfo", "GetCraftIcon", "GetCraftNumReagents",
	"GetCraftReagentInfo", "GetCraftReagentItemLink",
	"GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost",
	"GetTrainerServiceItemLink", "GetTrainerServiceSkillLine", "GetTrainerServiceSkillReq",
	-- Spell book / skills / professions. GetProfessions is TBC+; the
	-- GetNumSkillLines pair is the Vanilla path, and Compat picks between them.
	"GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
	"GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemInfo", "IsSpellKnown",
	"GetSpellCooldown", "GetItemCooldown", "CastSpellByName",
	-- The namespaced spell API; the only spelling WoW Forever has (Compat.lua).
	"C_Spell", "C_SpellBook",
	-- The trade-skill API WoW Forever reads and crafts through (CraftingEngine.lua).
	"C_TradeSkillUI",
	-- The player's map, for the Missing Recipes [Guide] pick (feature-detected).
	"C_Map",
	-- Key bindings: the K key uncloaks WoW Forever's ProfessionsFrame (CraftingEngine.lua).
	"GetBindingKey", "SetOverrideBindingClick", "ClearOverrideBindings",
	-- The modern tooltip helpers (Tooltip.lua's TooltipLink, WoW Forever).
	"TooltipUtil",
	-- Group / guild / instance state.
	"IsInGuild", "IsInGroup", "IsInRaid", "IsInInstance", "IsGuildLeader",
	"CanEditOfficerNote", "GetGuildInfo", "InCombatLockdown", "UnitAffectingCombat",
	-- Secure state driver (the Craft button's holder hides itself for combat).
	"RegisterStateDriver",
	-- Mail inbox, read by the Cooldowns tab's supply-mail flow.
	"GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "ATTACHMENTS_MAX_RECEIVE",
	-- Chat channels, used by Modules/CommTest.lua's CHANNEL probe.
	"JoinTemporaryChannel", "LeaveChannelByName", "GetChannelName",
	"ChatFrame_AddMessageEventFilter", "ChatTypeInfo",
	-- Alerts and misc UI feedback.
	"PlaySound", "FlashClientIcon", "RaidNotice_AddMessage", "RaidWarningFrame",
	"UIErrorsFrame", "UIFrameFlash", "HideUIPanel", "UIParent_OnEvent",
	"GetCursorPosition", "GetFramesRegisteredForEvent", "WOW_PROJECT_CLASSIC",
}
-- Written to, not just read.
globals = { "UISpecialFrames", "SLASH_TOGPM1", "SlashCmdList", "TOGPM_GuildDB", "TOGPM_Settings",
	-- The addon's own public table (`TOGPM = TOGPM or {}`, TOGProfessionMaster.lua:13).
	"TOGPM",
	-- Blizzard's quality-colour registry, and we genuinely WRITE one key into it:
	-- Modules/AHScanner.lua:682 back-fills `[-1]` because the Classic AH code
	-- indexes it with -1 on a getAll result set and errors when it is absent.
	-- Declared as writable rather than read-only so that deliberate write is not
	-- reported as a defect -- it is the whole point of the guard.
	"ITEM_QUALITY_COLORS" }

-- 542 = "empty if branch". This addon uses a deliberately empty branch as a
-- documented skip inside a filter chain — `if <excluded> then -- skip, reason
-- elseif <visible> then <render> end` — which reads better than inverting the
-- condition into a compound `not (a and b) and (c or d)`. Two sites in
-- GUI/CooldownsTab.lua; both carry the reason in the branch.
-- 542 = "empty if branch" (see above).
-- 212/self = "unused argument 'self'". Methods are declared `function addon:Foo()`
-- for a uniform call shape -- every consumer writes `addon:Foo(...)` -- so a body
-- that happens not to read `self` is a style artefact of that uniformity, not a
-- defect. Converting those few to `addon.Foo` would make the call shape depend on
-- the implementation, which is worse than the warning.
-- 211/_.* = "unused variable" for a name the author deliberately prefixed with
-- an underscore. luacheck only exempts a bare `_`, so a multi-return destructure
-- that names the slots it is skipping -- `local _name, _tex, count, ... = ` in
-- Modules/AHScanner.lua:615 -- reports one warning PER SKIPPED SLOT (fourteen
-- from two lines). Naming them is better than seventeen bare underscores,
-- because the position of the one you want is then checkable by eye against
-- Blizzard's documented return order. The underscore IS the declaration of
-- intent; this makes luacheck read it.
ignore = { "542", "212/self", "211/_.*" }

-- Vendored libraries and the shared test harness are not ours to lint.
exclude_files = { "libs", "Tests/wowapi" }

-- Locale files are one player-facing sentence per line, by design: a string
-- wrapped into concatenations is harder to translate and harder to read than
-- a long line. Every other check still applies to them.
files["Locale"] = { ignore = { "631" } }

files["Tests"] = {
	std = "lua51+busted",
	ignore = { "143/assert" },
	-- A spec-only helper deliberately declared as a global so a later spec file
	-- can reach it (scanner_sync_spec.lua:64). Not shipped code.
	--
	-- LibStub is writable HERE and read-only in shipped code, which is the
	-- correct split: specs evict `LibStub.libs[major]` / `.minors[major]` before
	-- reloading a library, because without that `NewLibrary` returns nil, the
	-- file bails at `if not lib then return end`, and the test silently reuses
	-- the PREVIOUS test's library. That eviction is the harness's documented
	-- pattern, not a spec reaching into something it should not.
	globals = { "Scanner_subsyncReset", "LibStub" },
}
