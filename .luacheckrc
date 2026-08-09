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
}
-- Written to, not just read. `StaticPopupDialogs` is Blizzard's registry and
-- every addon adds its own keys to it.
globals = { "UISpecialFrames", "SLASH_TOGPM1", "SlashCmdList", "TOGPM_GuildDB", "TOGPM_Settings",
	"StaticPopupDialogs" }

-- 542 = "empty if branch". This addon uses a deliberately empty branch as a
-- documented skip inside a filter chain — `if <excluded> then -- skip, reason
-- elseif <visible> then <render> end` — which reads better than inverting the
-- condition into a compound `not (a and b) and (c or d)`. Two sites in
-- GUI/CooldownsTab.lua; both carry the reason in the branch.
ignore = { "542" }

-- Vendored libraries and the shared test harness are not ours to lint.
exclude_files = { "libs", "Tests/wowapi" }

files["Tests"] = {
	std = "lua51+busted",
	ignore = { "143/assert" },
}
