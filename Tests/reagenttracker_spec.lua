-- GUI/ReagentTracker.lua — the two numbers the tracker exists to show.
--
-- "need" comes from consolidating every reagent across the shopping list;
-- "have" is deliberately RICHER than the shopping list tab's version — it
-- counts the bank and the mailbox as well as your bags, because a reagent
-- sitting in the bank is one you do not need to buy.
--
-- The id resolution is the fragile part: a reagent can arrive carrying an item
-- LINK and no usable id, so the id is parsed out of the link, with the numeric
-- field as the fallback. Get that wrong and reagents either vanish from the
-- list or split into two rows that each show half the requirement.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, RT, saved

local THORIUM, FELCLOTH = 12359, 14256
local THORIUM_LINK = "|cffffffff|Hitem:12359:0:0:0:0:0:0:0|h[Thorium Bar]|h|r"

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/ReagentTracker.lua")
	RT = ns.ReagentTracker
end)

local function bagsHolding(contents)
	local slots = {}
	for itemId, count in pairs(contents or {}) do
		slots[#slots + 1] = { itemID = itemId, stackCount = count }
	end
	ns.GetNumBagSlots       = function() return 0 end
	ns.GetContainerNumSlots = function() return #slots end
	ns.GetContainerItemInfo = function(_, _bag, slot) return slots[slot] end
end

before_each(function()
	env.installFrames()
	env.resetDb()
	saved = {
		GetNumBagSlots       = ns.GetNumBagSlots,
		GetContainerNumSlots = ns.GetContainerNumSlots,
		GetContainerItemInfo = ns.GetContainerItemInfo,
	}
	bagsHolding({})
	ns.lib.db.char.shoppingList = {}
	ns.lib.db.char.bankCounts   = {}
	ns.lib.db.char.mailCounts   = {}
end)

after_each(function()
	for name, fn in pairs(saved or {}) do ns[name] = fn end
end)

--- Queue a craft needing `reagents`, `quantity` times.
local function queue(spellId, quantity, reagents)
	ns.lib.db.char.shoppingList[spellId] = { quantity = quantity, reagents = reagents }
end

local function needFor(itemId)
	for _, row in ipairs(RT:BuildReagentList()) do
		if row.id == itemId then return row.need end
	end
	return nil
end

describe("BuildReagentList — what you still need", function()
	it("multiplies a reagent by the queued quantity", function()
		queue(1, 4, { { itemId = THORIUM, name = "Thorium Bar", count = 3 } })
		assert.equal(12, needFor(THORIUM))
	end)

	it("consolidates the same reagent across two queued crafts", function()
		-- One row with the total, not two rows to add up in your head.
		queue(1, 1, { { itemId = THORIUM, name = "Thorium Bar", count = 2 } })
		queue(2, 3, { { itemId = THORIUM, name = "Thorium Bar", count = 1 } })
		local list = RT:BuildReagentList()
		assert.equal(1, #list)
		assert.equal(5, list[1].need)
	end)

	it("treats a reagent with no count as one per craft", function()
		queue(1, 2, { { itemId = THORIUM, name = "Thorium Bar" } })
		assert.equal(2, needFor(THORIUM))
	end)

	it("treats a craft with no quantity as one", function()
		queue(1, nil, { { itemId = THORIUM, name = "Thorium Bar", count = 5 } })
		assert.equal(5, needFor(THORIUM))
	end)

	it("reads the item id out of an item link when there is no numeric id", function()
		-- Reagents arrive from trade-skill scans carrying a link and nothing
		-- else; without this they would silently never appear in the list.
		queue(1, 1, { { itemLink = THORIUM_LINK, name = "Thorium Bar", count = 2 } })
		assert.equal(2, needFor(THORIUM))
	end)

	it("keeps a linked and an unlinked entry for the same item together", function()
		-- The failure this guards is two rows for one reagent, each showing part
		-- of the requirement.
		queue(1, 1, { { itemLink = THORIUM_LINK, name = "Thorium Bar", count = 2 } })
		queue(2, 1, { { itemId = THORIUM, name = "Thorium Bar", count = 3 } })
		local list = RT:BuildReagentList()
		assert.equal(1, #list)
		assert.equal(5, list[1].need)
	end)

	it("skips a reagent with neither a link nor a real id", function()
		-- itemId 0 is the "no item" sentinel the scan produces for enchants.
		queue(1, 1, {
			{ itemId = 0, name = "Nothing" },
			{ itemId = THORIUM, name = "Thorium Bar", count = 1 },
		})
		local list = RT:BuildReagentList()
		assert.equal(1, #list)
		assert.equal(THORIUM, list[1].id)
	end)

	it("sorts by reagent name", function()
		queue(1, 1, {
			{ itemId = THORIUM,  name = "Thorium Bar", count = 1 },
			{ itemId = FELCLOTH, name = "Felcloth",    count = 1 },
		})
		local list = RT:BuildReagentList()
		assert.equal("Felcloth",    list[1].name)
		assert.equal("Thorium Bar", list[2].name)
	end)

	it("returns nothing for an empty shopping list", function()
		assert.same({}, RT:BuildReagentList())
	end)
end)

describe("GetPlayerBagCount — what you already have", function()
	it("counts what is in the bags", function()
		bagsHolding({ [THORIUM] = 12 })
		assert.equal(12, RT:GetPlayerBagCount(THORIUM))
	end)

	it("adds up stacks split across slots", function()
		ns.GetNumBagSlots       = function() return 0 end
		ns.GetContainerNumSlots = function() return 3 end
		ns.GetContainerItemInfo = function(_, _bag, slot)
			return ({
				{ itemID = THORIUM,  stackCount = 20 },
				{ itemID = FELCLOTH, stackCount = 5 },
				{ itemID = THORIUM,  stackCount = 4 },
			})[slot]
		end
		assert.equal(24, RT:GetPlayerBagCount(THORIUM))
	end)

	it("counts the bank as well, because that is not a reason to buy more", function()
		bagsHolding({ [THORIUM] = 5 })
		ns.lib.db.char.bankCounts = { [THORIUM] = 40 }
		assert.equal(45, RT:GetPlayerBagCount(THORIUM))
	end)

	it("counts the mailbox too", function()
		bagsHolding({ [THORIUM] = 5 })
		ns.lib.db.char.mailCounts = { [THORIUM] = 10 }
		assert.equal(15, RT:GetPlayerBagCount(THORIUM))
	end)

	it("adds bags, bank and mail together", function()
		bagsHolding({ [THORIUM] = 1 })
		ns.lib.db.char.bankCounts = { [THORIUM] = 2 }
		ns.lib.db.char.mailCounts = { [THORIUM] = 4 }
		assert.equal(7, RT:GetPlayerBagCount(THORIUM))
	end)

	it("does not count a different item", function()
		bagsHolding({ [FELCLOTH] = 99 })
		ns.lib.db.char.bankCounts = { [FELCLOTH] = 99 }
		assert.equal(0, RT:GetPlayerBagCount(THORIUM))
	end)

	it("treats a stack with no count as a single item", function()
		ns.GetNumBagSlots       = function() return 0 end
		ns.GetContainerNumSlots = function() return 1 end
		ns.GetContainerItemInfo = function() return { itemID = THORIUM } end
		assert.equal(1, RT:GetPlayerBagCount(THORIUM))
	end)

	it("reports nothing when you hold none of it", function()
		assert.equal(0, RT:GetPlayerBagCount(THORIUM))
	end)
end)

describe("CountText — the colour says what you can do next", function()
	it("is green when the bags alone cover it", function()
		assert.equal("|cff00ff00" .. "4|r/4", RT:CountText({ have = 4, need = 4 }))
	end)

	it("is yellow when the guild bank fills the gap, and shows the bank's share", function()
		assert.equal("|cffffff00" .. "1|r/4 |cff88ccff+5|r", RT:CountText({ have = 1, need = 4, bank = 5 }))
	end)

	it("is orange when even bags and bank fall short", function()
		assert.equal("|cffff8800" .. "1|r/4", RT:CountText({ have = 1, need = 4 }))
	end)

	it("is red when there is none anywhere", function()
		assert.equal("|cffff4444" .. "0|r/4", RT:CountText({ have = 0, need = 4 }))
	end)
end)

-- The window, drawn by LibAceGUIWidgets' RowList: one row per reagent, and a
-- window that is exactly as tall as its rows.
describe("the tracker window", function()
	local W

	before_each(function()
		W = ns.W
		if RT.frame then RT.frame:Hide() end
		RT.frame, RT._list, RT._host, RT._emptyLbl = nil, nil, nil, nil
		if W.ClearDiagnostics then W:ClearDiagnostics() end
	end)

	after_each(function()
		if RT.frame then RT.frame:Hide() end
	end)

	it("lists one row per reagent and sizes the window to them", function()
		queue(1, 2, {
			{ itemId = THORIUM, name = "Thorium Bar", count = 2 },
			{ itemId = FELCLOTH, name = "Felcloth", count = 1 },
		})
		RT:Open()
		assert.equal(2, #RT._list.data)
		-- 20 title + 2 rows x 16 + 6 padding.
		assert.equal(20 + 2 * 16 + 6, RT.frame:GetHeight())
		assert.equal(0, #W:Diagnostics())
	end)

	it("draws every row, with no scroll bar, when the client reports a height a hair short", function()
		-- At a tracker scale other than 100% the client can give back a height
		-- just under the exact rows RowList set, which floored to one row
		-- fewer and showed a scroll bar. The host carries one unit of slack.
		queue(1, 2, {
			{ itemId = THORIUM, name = "Thorium Bar", count = 2 },
			{ itemId = FELCLOTH, name = "Felcloth", count = 1 },
		})
		RT:Open()
		local host = RT._host
		local realGet = host.GetHeight
		host.GetHeight = function(f) return realGet(f) - 0.01 end
		queue(2, 1, { { itemId = 12360, name = "Arcanite Bar", count = 1 } })
		RT:Refresh()
		host.GetHeight = realGet
		assert.equal(3, #RT._list.data)
		assert.equal(3, RT._list.visibleRowCount)
		assert.is_false(RT._list.scrollbar:IsShown())
		assert.equal(20 + 3 * 16 + 6, RT.frame:GetHeight())
	end)

	it("gives the host one unit of slack only under a LibAceGUIWidgets older than MINOR 44", function()
		-- MINOR 44 tolerates a short host height itself (inbox 62eb5c52).
		local minors = LibStub.minors
		local realMinor = minors["LibAceGUIWidgets-1.0"]
		queue(1, 2, { { itemId = THORIUM, name = "Thorium Bar", count = 2 } })
		minors["LibAceGUIWidgets-1.0"] = 43
		local ok, err = pcall(function()
			RT:Open()
			assert.equal(RT._listH + 1, RT._host:GetHeight())
		end)
		minors["LibAceGUIWidgets-1.0"] = 44
		local ok2, err2 = pcall(function()
			-- A second row changes the fitted height, so RowList reports it again.
			queue(2, 1, { { itemId = FELCLOTH, name = "Felcloth", count = 1 } })
			RT:Refresh()
			assert.equal(RT._listH, RT._host:GetHeight())
		end)
		minors["LibAceGUIWidgets-1.0"] = realMinor
		assert(ok, err)
		assert(ok2, err2)
	end)

	it("shows the empty line, and no list, for an empty shopping list", function()
		RT:Open()
		assert.is_true(RT._emptyLbl:IsShown())
		assert.is_false(RT._host:IsShown())
	end)

	it("hands the icon column exactly one value, so no icon is greyed", function()
		-- GetItemInfo returns the sell price right after the icon; a second
		-- return reads as "desaturate" to the list.
		local savedGet = ns.Item.GetInfo
		ns.Item.GetInfo = function()
			return "Thorium Bar", nil, 1, 1, 1, "Trade Goods", "Trade Goods", 20, "", 134400, 600
		end
		local n = select("#", RT:IconFor({ id = THORIUM }))
		local tex = RT:IconFor({ id = THORIUM })
		ns.Item.GetInfo = savedGet
		assert.equal(1, n)
		assert.equal(134400, tex)
	end)

	it("is not closed by Escape", function()
		RT:Open()
		for _, name in ipairs(UISpecialFrames or {}) do
			assert.are_not.equal("TOGPMReagentTracker", name)
		end
	end)

	it("remembers being open, and reopens at login", function()
		RT:Open()
		assert.is_true(RT:State().shown)
		RT.frame:Hide()   -- a fresh login: built, not shown
		RT:Restore()
		assert.is_true(RT.frame:IsShown())
		RT:Close()
		assert.is_nil(RT:State().shown)
		RT:Restore()
		assert.is_false(RT.frame:IsShown())
	end)

	it("minimises to its title bar and back, and remembers it", function()
		queue(1, 1, { { itemId = THORIUM, name = "Thorium Bar", count = 1 } })
		RT:Open()
		RT:ToggleCollapsed()
		assert.is_true(RT:State().collapsed)
		assert.is_false(RT._host:IsShown())
		assert.equal(20, RT.frame:GetHeight())
		assert.equal("|cffffffff+|r", RT._minLbl:GetText())
		RT:ToggleCollapsed()
		assert.is_nil(RT:State().collapsed)
		assert.is_true(RT._host:IsShown())
		assert.equal(20 + 16 + 6, RT.frame:GetHeight())
	end)

	it("keeps its title bar where it is when minimised", function()
		-- Anchored by a centre point, shrinking the window pulled its top
		-- down toward that centre.
		queue(1, 1, { { itemId = THORIUM, name = "Thorium Bar", count = 1 } })
		RT:Open()
		local top = RT.frame:GetTop()
		assert.is_number(top)
		assert.equal("TOPLEFT", (RT.frame:GetPoint()))
		RT:ToggleCollapsed()
		assert.is_true(RT:State().collapsed)
		assert.equal(top, RT.frame:GetTop())
		RT.frame:GetScript("OnDragStop")(RT.frame)
		assert.equal("TOPLEFT", RT:State().point)
		assert.equal(top, RT:State().y)
		RT:ToggleCollapsed()
		assert.equal(top, RT.frame:GetTop())
	end)

	it("pins the top on the first minimise when the window had no rect at build", function()
		-- In game a frame built at login may not be placed yet, so Build's pin
		-- finds no rect and the window keeps its centre anchor.
		queue(1, 1, { { itemId = THORIUM, name = "Thorium Bar", count = 1 } })
		RT.frame = nil
		local st = RT:State()
		st.point, st.relPoint, st.x, st.y = nil, nil, nil, nil
		local realCreate, built = _G.CreateFrame, nil
		_G.CreateFrame = function(...)
			local f = realCreate(...)
			if not built then
				built = f
				f.GetLeft = function() return nil end
			end
			return f
		end
		local ok, err = pcall(RT.Open, RT)
		_G.CreateFrame = realCreate
		assert(ok, err)
		assert.equal(built, RT.frame)
		built.GetLeft = nil
		-- Build's pin found no rect: still on the default centre anchor.
		assert.equal("RIGHT", (RT.frame:GetPoint()))
		RT:ToggleCollapsed()
		assert.equal("TOPLEFT", (RT.frame:GetPoint()))
		assert.equal("TOPLEFT", st.point)
		RT:ToggleCollapsed()
	end)

	it("opens at the saved scale and opacity", function()
		ns.lib.db.profile.trackerScale, ns.lib.db.profile.trackerOpacity = 0.75, 0.5
		RT:Open()
		assert.equal(0.75, RT.frame:GetScale())
		assert.equal(0.25, select(4, RT._bg:GetColorTexture()))
		assert.equal(1, RT.frame:GetAlpha())
		ns.lib.db.profile.trackerScale, ns.lib.db.profile.trackerOpacity = nil, nil
	end)

	it("draws a half-black panel behind the rows at 100% opacity", function()
		RT:Open()
		local r, g, b, a = RT._bg:GetColorTexture()
		assert.same({ 0, 0, 0, 0.5 }, { r, g, b, a })
		assert.equal("BACKGROUND", (RT._bg:GetDrawLayer()))
		assert.equal(RT.frame, RT._bg:GetParent())
	end)

	it("fades only the background: text stays solid, and 0% leaves no background", function()
		RT:Open()
		ns.lib.db.profile.trackerOpacity = 0
		RT:ApplyOpacity()
		assert.equal(0, select(4, RT._bg:GetColorTexture()))
		assert.equal(1, RT.frame:GetAlpha())
		ns.lib.db.profile.trackerOpacity = nil
		RT:ApplyOpacity()
	end)

	it("clamps scale to 50-150% and opacity to 0-100%, defaulting both to 100%", function()
		local p = ns.lib.db.profile
		assert.equal(1, RT:GetScale())
		assert.equal(1, RT:GetOpacity())
		p.trackerScale, p.trackerOpacity = 0.1, -0.5
		assert.equal(0.5, RT:GetScale())
		assert.equal(0, RT:GetOpacity())
		p.trackerScale, p.trackerOpacity = 9, 9
		assert.equal(1.5, RT:GetScale())
		assert.equal(1, RT:GetOpacity())
		p.trackerScale, p.trackerOpacity = nil, nil
	end)

	it("applies the sliders live, keeping its top-left on the same screen point", function()
		-- Point offsets are in the frame's scaled units: a bare SetScale moves
		-- the window toward or away from the screen corner.
		RT:Open()
		local left, top = RT.frame:GetLeft(), RT.frame:GetTop()
		ns.lib.db.profile.trackerScale, ns.lib.db.profile.trackerOpacity = 1.25, 0.4
		RT:ApplyScale()
		RT:ApplyOpacity()
		assert.equal(1.25, RT.frame:GetScale())
		assert.equal(0.2, select(4, RT._bg:GetColorTexture()))
		local st = RT:State()
		assert.equal("TOPLEFT", st.point)
		assert.equal(left / 1.25, st.x)
		assert.equal(top / 1.25, st.y)
		RT:ApplyScale()   -- unchanged setting: the window stays put
		assert.equal(left / 1.25, st.x)
		ns.lib.db.profile.trackerScale, ns.lib.db.profile.trackerOpacity = nil, nil
		RT:ApplyScale()
		RT:ApplyOpacity()
	end)

	it("does nothing before the window is built", function()
		assert.is_nil(RT.frame)
		RT:ApplyScale()
		RT:ApplyOpacity()
		assert.is_nil(RT.frame)
	end)

	it("keeps the open and minimised flags when the window is dragged", function()
		RT:Open()
		RT:ToggleCollapsed()
		RT.frame:GetScript("OnDragStop")(RT.frame)
		assert.is_true(RT:State().shown)
		assert.is_true(RT:State().collapsed)
		RT:ToggleCollapsed()
	end)
end)
