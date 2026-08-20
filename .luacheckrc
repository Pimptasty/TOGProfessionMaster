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
	-- the frames it reads. `C_Container` is the modern namespace and is
	-- feature-detected against the bare globals at every call site.
	"C_Container", "ClearCursor", "SplitContainerItem", "PickupContainerItem",
	"MailFrame", "GetSendMailItem", "ClickSendMailItemButton", "ATTACHMENTS_MAX_SEND",
	"SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox", "MailEditBox",
	"StaticPopup_Show", "BackdropTemplateMixin",
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
	-- and the merchant/coin calls are the vendor-capture path in Modules/Price.lua.
	"time", "floor", "GetCoinTextureString",
	"GetMerchantNumItems", "GetMerchantItemInfo", "GetMerchantItemLink",
	-- WorldFrame is the engine-side root frame (used for cursor position);
	-- Menu is Blizzard's modern context-menu namespace, present on the
	-- flavours whose branch reads it and feature-detected at every call site.
	"WorldFrame", "Menu",
	-- Optional third-party price addons. TOGPM never depends on any of them:
	-- Modules/Price.lua feature-detects each global at every call site and the
	-- tier simply answers nothing when the addon is absent. Declared here so the
	-- deliberate absence does not read as 55 warnings.
	"Auctionator", "AucAdvanced", "TSM_API",

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
	-- Tooltip surfaces. TooltipDataProcessor and Enum are the modern
	-- (Cata/MoP+) hook API, absent on Vanilla/TBC/Wrath and feature-detected
	-- in Tooltip.lua; the four frames are the shopping/compare tooltips.
	"TooltipDataProcessor", "Enum", "ItemRefTooltip",
	"ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
	"FrameUtil",
	-- Auction house. C_AuctionHouse + AuctionHouseFrame are the modern pair;
	-- AuctionFrame and the Browse* widgets are the pre-Cata UI. Modules/AHScanner.lua
	-- picks one at runtime -- both halves are read behind that branch.
	"C_AuctionHouse", "AuctionHouseFrame", "AuctionFrame", "AuctionFrameTab1",
	"AuctionFrameBrowse_Search", "BrowseDropDown", "BrowseMaxLevel", "BrowseMinLevel",
	"BrowseName", "BrowseSearchButton", "CanSendAuctionQuery", "QueryAuctionItems",
	"GetAuctionItemInfo", "GetNumAuctionItems",
	"IsUsableCheckButton", "ShowOnPlayerCheckButton", "UIDropDownMenu_SetSelectedValue",
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
	-- Group / guild / instance state.
	"IsInGuild", "IsInGroup", "IsInRaid", "IsInInstance", "IsGuildLeader",
	"CanEditOfficerNote", "GetGuildInfo", "InCombatLockdown", "UnitAffectingCombat",
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
-- Written to, not just read. `StaticPopupDialogs` is Blizzard's registry and
-- every addon adds its own keys to it.
globals = { "UISpecialFrames", "SLASH_TOGPM1", "SlashCmdList", "TOGPM_GuildDB", "TOGPM_Settings",
	"StaticPopupDialogs",
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
