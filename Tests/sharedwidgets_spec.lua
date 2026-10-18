-- GUI/SharedWidgets.lua: the helpers no other spec drives end to end.
--
-- Written for LAGW adoption step 7 (v1.1.3), which asked for the file's
-- coverage once the hand-rolled list helpers were gone. Each block is a
-- behaviour a player reaches: whispering a crafter, the AH-scan repaint hook,
-- the last-resort quality colour, a curated tooltip that redraws while the compare
-- key is held, and a price label too long to share a row.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, IL
local saved

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	saved = {
		ChatEdit_GetActiveWindow    = _G.ChatEdit_GetActiveWindow,
		ChatFrame_OpenChat          = _G.ChatFrame_OpenChat,
		IsModifiedClick             = _G.IsModifiedClick,
		GameTooltip_ShowCompareItem = _G.GameTooltip_ShowCompareItem,
		AH = ns.AH, Item = ns.Item, GetItemDB = ns.GetItemDB, Print = ns.Print,
	}
	IL.EndHover(nil)
end)

after_each(function()
	IL.EndHover(nil)
	_G.ChatEdit_GetActiveWindow    = saved.ChatEdit_GetActiveWindow
	_G.ChatFrame_OpenChat          = saved.ChatFrame_OpenChat
	_G.IsModifiedClick             = saved.IsModifiedClick
	_G.GameTooltip_ShowCompareItem = saved.GameTooltip_ShowCompareItem
	ns.AH, ns.Item, ns.GetItemDB, ns.Print = saved.AH, saved.Item, saved.GetItemDB, saved.Print
end)

describe("UI.OpenWhisper", function()
	it("fills the chat box that is already open, caret at the end", function()
		local box = { text = "" }
		function box:SetText(t) self.text = t end
		function box:GetText() return self.text end
		function box:SetFocus() self.focused = true end
		function box:SetCursorPosition(p) self.caret = p end
		_G.ChatEdit_GetActiveWindow = function() return box end
		_G.ChatFrame_OpenChat = function() error("must not open a second box") end
		ns.UI.OpenWhisper("Bob-Testrealm")
		assert.equal("/w Bob-Testrealm ", box.text)
		assert.is_true(box.focused)
		assert.equal(#"/w Bob-Testrealm ", box.caret)
	end)

	it("opens the chat box with the whisper when none is open", function()
		local opened
		_G.ChatEdit_GetActiveWindow = function() return nil end
		_G.ChatFrame_OpenChat = function(text, frame) opened = { text, frame } end
		ns.UI.OpenWhisper("Bob")
		assert.same({ "/w Bob ", DEFAULT_CHAT_FRAME }, opened)
	end)
end)

describe("ItemLink.SyncCompare", function()
	it("reports no comparison when the client has no compare function", function()
		_G.IsModifiedClick = function() return true end
		_G.GameTooltip_ShowCompareItem = nil
		assert.is_false(IL.SyncCompare({}))
	end)
end)

describe("ItemLink.QualityHex", function()
	it("falls back to the item's cached quality when there is no link and no ItemDB", function()
		ns.GetItemDB = function() return nil end
		ns.Item = {
			GetInfo = function(id)
				assert.equal(929, id)
				return "Healing Potion", nil, 3
			end,
			GetQualityColor = function(q)
				assert.equal(3, q)
				return 0, 0.44, 0.87, "ff0070dd"
			end,
		}
		assert.equal("ff0070dd", IL.QualityHex(nil, 929))
	end)

	it("reads Retail's |cnIQ<quality>: link colour, which carries no hex", function()
		ns.GetItemDB = function() return nil end
		ns.Item = {
			GetInfo = function() error("must not need the item cache") end,
			GetQualityColor = function(q)
				assert.equal(4, q)
				return 0.64, 0.21, 0.93, "|cffA335EE"
			end,
		}
		assert.equal("ffa335ee", IL.QualityHex("|cnIQ4:|Hitem:19019::|h[x]|h|r", 19019))
	end)

	it("answers nil rather than a malformed colour", function()
		ns.GetItemDB = function() return nil end
		ns.Item = {
			GetInfo = function() return "x", nil, 3 end,
			GetQualityColor = function() return 0, 0, 0, "0070dd" end,
		}
		assert.is_nil(IL.QualityHex(nil, 929))
	end)
end)

describe("ItemLink.WithWrappedLines", function()
	it("forces the wrap flag on SetText as well as AddLine", function()
		local got
		local tip = {}
		function tip:SetText(text, _, _, _, _, wrap) got = { text, wrap } end
		assert.is_true(IL.WithWrappedLines(tip, function(t) t:SetText("Title", 1, 1, 1, 1) end))
		assert.same({ "Title", true }, got)
		assert.is_function(tip.SetText, "the tooltip's own SetText was not put back")
	end)
end)

describe("a curated tooltip while the compare key changes", function()
	it("is redrawn by its own rebuild, not by the item comparison", function()
		local rebuilt = 0
		_G.GameTooltip_ShowCompareItem = function() error("a curated tooltip has no item to compare") end
		local tip = { IsShown = function() return true end }
		IL.BeginHover(tip, function() rebuilt = rebuilt + 1 end)
		_G.IsModifiedClick = function() return true end
		env.frames.fireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		assert.equal(1, rebuilt)
	end)
end)

describe("a price label too long to share a row", function()
	it("drops to two wrapped lines instead of widening the tooltip", function()
		local LINK = "|cffffffff|Hitem:4394::::::::|h[Big Iron Bomb]|h|r"
		local long = string.rep("x", 41)
		ns.GetItemDB = function()
			return {
				GetLink = function() return LINK end,
				GetExternalPrices = function()
					return { Provider = { { label = long, value = 12, formatted = "12c" } } }
				end,
			}
		end
		local lines, doubles = {}, 0
		local tip = {}
		function tip:AddLine(text, _, _, _, wrap) lines[#lines + 1] = { text, wrap } end
		function tip:AddDoubleLine() doubles = doubles + 1 end
		IL.AppendIntegrations(tip, nil, 4394)
		assert.equal(0, doubles)
		assert.same({ long, true }, lines[#lines - 1])
		assert.same({ "  12c", true }, lines[#lines])
	end)
end)

-- TOGPM has no Scan AH button since 2026-10-17 (ItemDB's AH button scans the
-- whole house), but the [AH] row buttons still have to appear when that scan
-- lands and go when the AH closes. Only the visible tab repaints, and only
-- while the window is open.
describe("the [AH] buttons follow the Auction House", function()
	local realMW, calls

	before_each(function()
		realMW = ns.MainWindow
		calls = { spec = 0, other = 0 }
		ns.GUI.SetAHRefresh("spec",  function() calls.spec  = calls.spec  + 1 end)
		ns.GUI.SetAHRefresh("other", function() calls.other = calls.other + 1 end)
	end)

	after_each(function()
		ns.MainWindow = realMW
		ns.GUI.SetAHRefresh("spec", nil)
		ns.GUI.SetAHRefresh("other", nil)
	end)

	it("repaints the visible tab when a scan finishes, and no other", function()
		ns.MainWindow = { frame = {}, activeTab = "spec" }
		ns.callbacks:Fire("AH_SCAN_COMPLETE", {}, "done")
		assert.same({ spec = 1, other = 0 }, calls)
	end)

	it("repaints the visible tab when the Auction House opens or closes", function()
		ns.MainWindow = { frame = {}, activeTab = "spec" }
		ns.callbacks:Fire("AH_OPEN_STATE_CHANGED", true)
		ns.callbacks:Fire("AH_OPEN_STATE_CHANGED", false)
		assert.same({ spec = 2, other = 0 }, calls)
	end)

	it("repaints nothing while the window is closed", function()
		ns.MainWindow = { frame = nil, activeTab = "spec" }
		ns.callbacks:Fire("AH_SCAN_COMPLETE", {}, "done")
		assert.same({ spec = 0, other = 0 }, calls)
	end)

	it("is quiet for a tab with nothing to repaint", function()
		ns.MainWindow = { frame = {}, activeTab = "guild" }
		assert.has_no.errors(function() ns.callbacks:Fire("AH_SCAN_COMPLETE", {}, "done") end)
		assert.same({ spec = 0, other = 0 }, calls)
	end)
end)
