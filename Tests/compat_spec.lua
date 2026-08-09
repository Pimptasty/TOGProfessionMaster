-- Compat: the version flags and API shims every other module branches on.
--
-- These are decided ONCE at load time from the client build, so the only honest
-- way to test them is to load the file again under each build — which is what
-- this spec does. It matters because `addon.isTBC` and friends gate real
-- behaviour (the separate Craft window on Vanilla/TBC, the skill cap shown on
-- every skill readout), and a wrong flag is invisible until someone logs into
-- that flavour.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local wow = env.wow

-- Load a FRESH copy of Compat.lua at a given client build.
--
-- The namespace INHERITS the booted addon (Compat is a member of it and calls
-- back into it — addon:DebugPrint at file scope, for one) but WRITES land on the
-- scratch table, so re-loading at five different builds never disturbs the real
-- addon's flags for the other spec files sharing this Lua state.
local function compatAt(iface)
	wow.setProject(WOW_PROJECT_CLASSIC, { iface = iface })
	local ns = setmetatable({}, { __index = env.boot() })
	wow.loadAddonFile("Compat.lua", "TOGProfessionMaster", ns)
	return ns
end

setup(function()
	env.initDb()
end)

before_each(function()
	env.install()
	_G.GameTooltip = nil
	_G.TOGBankClassic_Guild, _G.TOGBankClassic_Options = nil, nil
end)

after_each(function()
	-- Any spec here leaves the flavour where it found it; the whole suite shares
	-- one Lua state and a stray build number would silently re-flavour later files.
	wow.useClassicEra()
end)

describe("version flags", function()
	local CASES = {
		{ iface = 11508, flag = "isVanilla", cap = 300 },
		{ iface = 20504, flag = "isTBC",     cap = 375 },
		{ iface = 30403, flag = "isWrath",   cap = 450 },
		{ iface = 40402, flag = "isCata",    cap = 525 },
		{ iface = 50500, flag = "isMoP",     cap = 600 },
	}
	local ALL = { "isVanilla", "isTBC", "isWrath", "isCata", "isMoP" }

	it("sets exactly one flavour flag per build", function()
		for _, case in ipairs(CASES) do
			local ns = compatAt(case.iface)
			for _, flag in ipairs(ALL) do
				if flag == case.flag then
					assert.is_true(ns[flag], case.flag .. " should be true at " .. case.iface)
				else
					assert.is_false(ns[flag], flag .. " should be false at " .. case.iface)
				end
			end
		end
	end)

	it("sets the profession skill cap for the expansion", function()
		for _, case in ipairs(CASES) do
			assert.equal(case.cap, compatAt(case.iface).SKILL_CAP)
		end
	end)

	it("treats only the vanilla protocol as Classic", function()
		assert.is_true(compatAt(11508).isClassic)
		assert.is_false(compatAt(20504).isClassic)
	end)

	it("falls back to the Vanilla cap on an unrecognised build", function()
		assert.equal(300, compatAt(99999).SKILL_CAP)
	end)
end)

describe("IsSoD", function()
	it("is true only where rune engraving exists — SoD shares Era's build", function()
		local ns = compatAt(11508)
		_G.C_Engraving = { IsEngravingEnabled = function() return true end }
		assert.is_true(ns:IsSoD())
	end)

	it("is false on Era, Hardcore and Anniversary", function()
		local ns = compatAt(11508)
		_G.C_Engraving = { IsEngravingEnabled = function() return false end }
		assert.is_false(ns:IsSoD())
		_G.C_Engraving = nil
		assert.is_false(ns:IsSoD())
	end)
end)

describe("container shim", function()
	it("uses the modern C_Container API when the client has it", function()
		_G.C_Container = {
			GetContainerItemInfo  = function(bag, slot) return { itemID = 100 * bag + slot } end,
			GetContainerNumSlots  = function() return 20 end,
			GetContainerItemLink  = function() return "link" end,
		}
		-- The shim closes over the GLOBAL, not a captured upvalue, so it has to
		-- stay installed for the call — as it is in game, where C_Container never
		-- disappears mid-session.
		local ns = compatAt(11508)
		assert.equal(102, ns:GetContainerItemInfo(1, 2).itemID)
		assert.equal(20, ns:GetContainerNumSlots(1))
		assert.equal("link", ns:GetContainerItemLink(1, 2))
		_G.C_Container = nil
	end)

	it("normalises the old positional API into the same table", function()
		_G.C_Container = nil
		_G.GetContainerItemInfo = function()
			return "tex", 5, false, 2, false, false,
			       "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", false, false, 2589
		end
		local info = compatAt(11508):GetContainerItemInfo(0, 1)
		assert.equal("tex", info.iconFileID)
		assert.equal(5, info.stackCount)
		assert.equal(2589, info.itemID)
		assert.equal(2, info.quality)
	end)

	it("derives the item id from the link on builds that omit it", function()
		-- Older Classic/TBC builds return only 7 values. Without this the
		-- cooldown supply-mail bag scan matched nothing and told the player they
		-- had no reagents when they did.
		_G.C_Container = nil
		_G.GetContainerItemInfo = function()
			return "tex", 5, false, 2, false, false,
			       "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r"
		end
		assert.equal(2589, compatAt(11508):GetContainerItemInfo(0, 1).itemID)
	end)

	it("returns nothing for an empty slot", function()
		_G.C_Container = nil
		_G.GetContainerItemInfo = function() return nil end
		assert.is_nil(compatAt(11508):GetContainerItemInfo(0, 1))
	end)

	it("reports the bag count, defaulting when the constant is absent", function()
		_G.C_Container = nil
		_G.NUM_BAG_SLOTS = nil
		assert.equal(4, compatAt(11508):GetNumBagSlots())
		_G.NUM_BAG_SLOTS = 5
		assert.equal(5, compatAt(11508):GetNumBagSlots())
		_G.NUM_BAG_SLOTS = nil
	end)
end)

describe("addon-info shims", function()
	it("prefers the C_AddOns namespace when present", function()
		_G.C_AddOns = {
			IsAddOnLoaded    = function(n) return n == "Yes" end,
			GetAddOnMetadata = function() return "9.9.9" end,
		}
		local ns = compatAt(11508)
		assert.is_true(ns:IsAddOnLoaded("Yes"))
		assert.is_false(ns:IsAddOnLoaded("No"))
		assert.equal("9.9.9", ns.GetAddOnMetadata())
	end)

	it("falls back to the bare globals on older clients", function()
		_G.C_AddOns = nil
		_G.IsAddOnLoaded    = function(n) return n == "Old" end
		_G.GetAddOnMetadata = function() return "1.0.0" end
		local ns = compatAt(11508)
		assert.is_true(ns:IsAddOnLoaded("Old"))
		assert.equal("1.0.0", ns.GetAddOnMetadata())
	end)

	it("wraps the spell and item info calls", function()
		local ns = compatAt(11508)
		_G.GetSpellInfo = function(id) return "Spell" .. id end
		_G.GetItemInfo  = function(id) return "Item" .. id end
		assert.equal("Spell7", ns:GetSpellInfo(7))
		assert.equal("Item7", ns:GetItemInfo(7))
	end)
end)

describe("tooltip anchoring", function()
	local ns, owned

	before_each(function()
		ns = compatAt(11508)
		owned = nil
		_G.GetScreenHeight = function() return 1000 end
		_G.GameTooltip = { SetOwner = function(_, f, anchor) owned = { f, anchor } end }
	end)

	it("anchors below a frame in the top half of the screen", function()
		local f = { GetCenter = function() return 500, 800 end }
		ns.Tooltip.Owner(f)
		assert.equal("ANCHOR_BOTTOMLEFT", owned[2])
	end)

	it("anchors above a frame in the bottom half", function()
		local f = { GetCenter = function() return 500, 200 end }
		ns.Tooltip.Owner(f)
		assert.equal("ANCHOR_TOPLEFT", owned[2])
	end)

	it("copes with a frame that reports no centre", function()
		local f = { GetCenter = function() return nil, nil end }
		ns.Tooltip.Owner(f)
		assert.equal("ANCHOR_TOPLEFT", owned[2])
	end)
end)

describe("AnchorFrame", function()
	local ns, points

	local function target()
		return { ClearAllPoints = function() end,
		         SetPoint = function(_, ...) points = { ... } end }
	end

	before_each(function()
		ns = compatAt(11508)
		points = nil
		_G.GetScreenHeight = function() return 1000 end
	end)

	it("puts the popup below a source in the top half", function()
		ns.Tooltip.AnchorFrame(target(), { GetCenter = function() return 0, 800 end })
		assert.equal("TOPLEFT", points[1])
		assert.equal("BOTTOMLEFT", points[3])
	end)

	it("puts the popup above a source in the bottom half", function()
		ns.Tooltip.AnchorFrame(target(), { GetCenter = function() return 0, 200 end })
		assert.equal("BOTTOMLEFT", points[1])
		assert.equal("TOPLEFT", points[3])
	end)

	it("unwraps an AceGUI widget to its underlying frame", function()
		local widget = { frame = { GetCenter = function() return 0, 800 end } }
		ns.Tooltip.AnchorFrame(target(), widget)
		assert.equal("TOPLEFT", points[1])
	end)

	it("does nothing for a source that is neither", function()
		ns.Tooltip.AnchorFrame(target(), {})
		assert.is_nil(points)
	end)
end)

describe("TOGBankClassic integration", function()
	local ns

	local function installBank(alts, banks)
		_G.TOGBankClassic_Guild = {
			Info = { alts = alts },
			GetBanks = function() return banks or {} end,
			IsBank = function(_, ck) return ck == "Banker-Testrealm" end,
		}
	end

	before_each(function() ns = compatAt(11508) end)

	it("reports zero stock when the bank addon isn't loaded", function()
		assert.equal(0, ns.Bank.GetStock(2589))
		assert.same({}, ns.Bank.GetBanksWithItem(2589))
		assert.is_false(ns.Bank.IsBanker("Banker-Testrealm"))
	end)

	it("totals an item across every banker alt", function()
		installBank({
			Bank1 = { items = { { ID = 2589, Count = 20 }, { ID = 999, Count = 5 } } },
			Bank2 = { items = { { ID = 2589, Count = 12 } } },
		})
		assert.equal(32, ns.Bank.GetStock(2589))
		assert.equal(0, ns.Bank.GetStock(4444))
	end)

	it("lists the bankers holding an item, sorted by name", function()
		installBank({
			Zed  = { items = { { ID = 2589, Count = 3 } } },
			Abe  = { items = { { ID = 2589, Count = 7 } } },
			None = { items = { { ID = 2589, Count = 0 } } },
		}, { "Zed", "Abe", "None", "Ghost" })
		local out = ns.Bank.GetBanksWithItem(2589)
		assert.equal(2, #out)
		assert.equal("Abe", out[1].name)
		assert.equal(7, out[1].count)
		assert.equal("Zed", out[2].name)
	end)

	it("sums every stack a banker holds, not just the first", function()
		-- A bank stores one entry per STACK, so a reagent held in bulk is
		-- always several entries. Reporting the first one under-counted the
		-- tooltip AND capped ShowRequestDialog's maxRequestable at one stack.
		installBank({
			Abe = { items = {
				{ ID = 2589, Count = 20 },
				{ ID = 999,  Count = 5 },
				{ ID = 2589, Count = 20 },
				{ ID = 2589, Count = 20 },
			} },
		}, { "Abe" })
		local out = ns.Bank.GetBanksWithItem(2589)
		assert.equal(1, #out)
		assert.equal(60, out[1].count)
	end)

	it("agrees with GetStock when every alt is a banker", function()
		-- The two walk different tables; nothing else asserts they compose.
		installBank({
			Abe = { items = { { ID = 2589, Count = 20 }, { ID = 2589, Count = 7 } } },
			Zed = { items = { { ID = 2589, Count = 12 } } },
		}, { "Abe", "Zed" })
		local total = 0
		for _, b in ipairs(ns.Bank.GetBanksWithItem(2589)) do total = total + b.count end
		assert.equal(ns.Bank.GetStock(2589), total)
		assert.equal(39, total)
	end)

	it("omits a banker whose stacks all total zero", function()
		installBank({
			Abe = { items = { { ID = 2589, Count = 0 }, { ID = 2589, Count = 0 } } },
		}, { "Abe" })
		assert.same({}, ns.Bank.GetBanksWithItem(2589))
	end)

	it("returns an empty list when there are no bankers at all", function()
		installBank({}, {})
		assert.same({}, ns.Bank.GetBanksWithItem(2589))
	end)

	it("delegates the banker test to TOGBank's own normalising check", function()
		-- Rolling our own short-name match broke on connected realms, where
		-- GetBanks() returns "Name-Realm".
		installBank({})
		assert.is_true(ns.Bank.IsBanker("Banker-Testrealm"))
		assert.is_false(ns.Bank.IsBanker("Someone-Testrealm"))
		assert.is_false(ns.Bank.IsBanker(nil))
	end)

	it("refuses to open a request dialog when nobody stocks the item", function()
		local said
		_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) said = msg end }
		installBank({ Bank1 = { items = { { ID = 111, Count = 1 } } } }, { "Bank1" })
		ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
		assert.is_true(said:find("No bankers", 1, true) ~= nil)
	end)

	it("does nothing at all without the bank addon", function()
		local said
		_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) said = msg end }
		ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
		assert.is_nil(said)
	end)
end)
