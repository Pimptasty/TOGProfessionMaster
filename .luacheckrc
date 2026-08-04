-- luacheck configuration for TOGProfessionMaster.
std = "lua51"

-- WoW globals the addon reads/writes. Not exhaustive — extend as luacheck complains.
read_globals = {
	"LibStub", "CreateFrame", "UIParent", "GameTooltip", "GameFontNormalSmall",
	"GetLocale", "GetBuildInfo", "GetServerTime", "GetTime",
	"GetItemInfo", "GetItemInfoInstant", "GetItemIcon", "GetItemCount",
	"GetSpellInfo", "GetSpellLink", "GetSpellTexture",
	"GetTradeSkillInfo", "GetNumTradeSkills", "GetTradeSkillLine",
	"GetTradeSkillItemLink", "GetTradeSkillRecipeLink", "GetTradeSkillReagentItemLink",
	"GetCraftInfo", "GetNumCrafts", "GetCraftItemLink", "GetCraftDisplaySkillLine",
	"GetNormalizedRealmName", "UnitName", "UnitFactionGroup", "IsShiftKeyDown",
	"ChatEdit_InsertLink", "ChatEdit_GetActiveWindow", "UIDropDownMenu_SetWidth",
	"SPELL_REAGENTS", "Item", "C_Timer", "C_ChatInfo",
}
globals = { "UISpecialFrames", "SLASH_TOGPM1", "SlashCmdList", "TOGPM_GuildDB", "TOGPM_Settings" }

-- Vendored libraries and the shared test harness are not ours to lint.
exclude_files = { "libs", "Tests/wowapi" }

files["Tests"] = {
	std = "lua51+busted",
	ignore = { "143/assert" },
}
