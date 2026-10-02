-- GUI/SharedWidgets.lua: the helpers no other spec drives end to end.
--
-- Written for LAGW adoption step 7 (v1.1.3), which asked for the file's
-- coverage once the hand-rolled list helpers were gone. Each block is a
-- behaviour a player reaches: whispering a crafter, the Scan AH button, the
-- last-resort quality colour, a curated tooltip that redraws while the compare
-- key is held, and a price label too long to share a row.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, IL, L
local saved

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
	L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
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

describe("the Scan AH button", function()
	local AceGUI, parent, state, printed

	before_each(function()
		AceGUI = LibStub("AceGUI-3.0")
		parent = AceGUI:Create("SimpleGroup")
		state = { scanning = false, open = true, started = nil, cancelled = 0, result = { true } }
		printed = {}
		ns.Print = function(_, msg) printed[#printed + 1] = msg end
		ns.AH = {
			IsScanning      = function() return state.scanning end,
			IsOpen          = function() return state.open end,
			GetScanProgress = function() return 3, 10 end,
			CancelScan      = function() state.cancelled = state.cancelled + 1; state.scanning = false end,
			StartScan       = function(items)
				state.started = items
				return state.result[1], state.result[2]
			end,
		}
	end)

	-- The button is parent's child (MakeScanAHButton AddChilds it), so releasing
	-- parent releases it. Releasing the button as well put it in AceGUI's
	-- shared pool twice, and toolbar_spec's "hands its frame back to UIParent"
	-- then failed whenever it ran after this file.
	after_each(function()
		AceGUI:Release(parent)
	end)

	local function make(extra)
		local opts = {
			parent = parent, tabName = "spec", label = "Scan AH", progressLabel = "Scanning %d/%d",
			tooltipTitle = "Scan AH", tooltipDesc = "desc",
			getItems = function() return { 2589 } end,
		}
		for k, v in pairs(extra or {}) do opts[k] = v end
		return ns.GUI.MakeScanAHButton(opts)
	end

	it("is enabled with its label while the Auction House is open", function()
		local btn = make()
		assert.equal("Scan AH", btn.text:GetText())
		assert.is_true(btn.frame:IsEnabled())
	end)

	it("shows the scan's progress while one is running", function()
		state.scanning = true
		local btn = make()
		assert.equal("Scanning 3/10", btn.text:GetText())
		assert.is_true(btn.frame:IsEnabled(), "a running scan must stay clickable, to cancel")
	end)

	it("starts a scan of the tab's items, and refreshes the tab", function()
		local refreshed = 0
		local btn = make({ onRefresh = function() refreshed = refreshed + 1 end })
		btn:Fire("OnClick")
		assert.same({ 2589 }, state.started)
		assert.is_true(refreshed > 0)
	end)

	it("cancels the scan when clicked while one is running", function()
		state.scanning = true
		local btn = make()
		btn:Fire("OnClick")
		assert.equal(1, state.cancelled)
		assert.is_nil(state.started)
		assert.equal("Scan AH", btn.text:GetText())
	end)

	it("says to open the Auction House when the scan is refused for that", function()
		state.result = { false, "ah-closed" }
		local btn = make()
		btn:Fire("OnClick")
		assert.same({ L["AHOpenFirst"] }, printed)
	end)

	it("uses the tab's own message when there is nothing to scan", function()
		state.result = { false, "no-items" }
		local btn = make({ noItemsError = "Nothing on this tab to scan." })
		btn:Fire("OnClick")
		assert.same({ "Nothing on this tab to scan." }, printed)
	end)

	it("falls back to the shared message when the tab gives none", function()
		state.result = { false, "no-items" }
		local btn = make()
		btn:Fire("OnClick")
		assert.same({ L["AHNoItemsToScan"] }, printed)
	end)

	it("does nothing on a click once the AH module is gone", function()
		local btn = make()
		ns.AH = nil
		assert.has_no.errors(function() btn:Fire("OnClick") end)
		assert.is_nil(state.started)
	end)
end)
