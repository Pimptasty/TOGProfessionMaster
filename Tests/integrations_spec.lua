-- ItemLink.AppendIntegrations — the other addons' lines on a tooltip that has
-- no item.
--
-- A hand-built (AddLine) tooltip never fires OnTooltipSetItem, and that one hook
-- is how AllTheThings, TOGBankClassic and TradeSkillMaster all attach. So the
-- ~65% of recipes with a real teaching scroll got all three for free via
-- SetHyperlink, and the trainer-taught third got none of them — the two tooltips
-- visibly looked like different addons.
--
-- Only ATT offers an entry point for this. The other two are re-rendered from
-- data this addon already reads, so these specs pin the SHAPE of that rendering
-- (headings, ordering, the double-line pairs) as well as the fact it happens.
--
-- Everything is feature-detected, so the most important cases here are the
-- absent ones: no ATT, no bank addon, TSM installed but switched off. Each must
-- leave the tooltip untouched rather than erroring or printing an empty heading.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local SPELL_ID, CRAFTED_ID = 3967, 4394

local ns, IL, tip

--- A tooltip that records what was added, in order.
local function fakeTooltip()
	local t = { lines = {} }
	-- `wrap` is captured because it is the whole subject of the ATT block below:
	-- it is the LAST parameter, it defaults to false, and a line that omits it
	-- ignores the engine's preset and stretches the frame.
	function t:AddLine(text, r, _g, _b, wrap)
		self.lines[#self.lines + 1] = { text = text, r = r, wrap = wrap }
	end
	function t:AddDoubleLine(l, rt) self.lines[#self.lines + 1] = { text = l, right = rt } end
	function t:NumLines() return #self.lines end
	function t:texts()
		local out = {}
		for i, l in ipairs(self.lines) do out[i] = l.text end
		return out
	end
	function t:find(needle)
		for i, l in ipairs(self.lines) do
			if type(l.text) == "string" and l.text:find(needle, 1, true) then return i, l end
		end
		return nil
	end
	return t
end

local real = {}

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
	real.Bank, real.Price, real.GetItemDB = ns.Bank, ns.Price, ns.GetItemDB
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	tip = fakeTooltip()
	ns.Bank = nil
	ns.Price = nil
	ns.GetItemDB = function() return nil end
	_G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
end)

-- Put back what this file blanks. `ns` is the one addon table the whole suite
-- shares, so anything left nil here is still nil in every LATER spec file --
-- `ns.Bank = nil` reached shoppingbank_spec and turned two of its assertions
-- into `attempt to index field 'Bank'`, a failure with no visible connection to
-- this file. Neither file is wrong on its own; only a whole-suite run shows it.
after_each(function()
	ns.Bank, ns.Price, ns.GetItemDB = real.Bank, real.Price, real.GetItemDB
end)

describe("AllTheThings", function()
	it("asks ItemDB to attach ATT's lines, keyed by SPELL", function()
		-- Keyed by spell deliberately: it is the only one of the three that can
		-- answer for a recipe with no scroll item, which is this whole case.
		local got
		ns.GetItemDB = function()
			return { AttachExternalRecipeInfo = function(_, t, spellID)
				got = { tooltip = t, spellID = spellID }
				return true
			end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)
		assert.same({ tooltip = tip, spellID = SPELL_ID }, got)
	end)

	it("does nothing when ItemDB has no such function", function()
		-- The function lives in LibItemDB, not LibProfessionDB — the
		-- recipe-scroll move left it behind. An older ItemDB simply lacks it.
		ns.GetItemDB = function() return {} end
		assert.has_no.errors(function() IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID) end)
		assert.same({}, tip:texts())
	end)
end)

describe("the wrap-flag shim — the RULE, not a per-integration patch", function()
	-- The regression this exists for: LibItemDB's bridge hands the tooltip to
	-- ATT's renderer, which passes `wrap` only when the entry sets `entry.wrap`
	-- (AllTheThings/src/Modules/Tooltip.lua:665-678). Source breadcrumbs do not,
	-- so they land unwrapped — and an unwrapped line ignores the engine's preset
	-- and stretches the frame. Measured on Advanced Target Dummy: ATT's 583.1px
	-- breadcrumb against a 603.6px frame.
	--
	-- Reimplementing ATT's renderer would fix ATT and nothing else, and would
	-- silently miss every addon reached through ApplyExternalTooltipHooks —
	-- which is a chain we cannot enumerate. So the flag is forced at the tooltip
	-- instead, for the duration of the foreign call. DEPENDENCY_CONTRACTS.md §11.

	local BREADCRUMB =
		"ATT > Zone > Kalimdor > Tanaris > Professions > Engineering > Buzzek Bracketswing"

	it("forces the flag on a line a third party added without it", function()
		ns.GetItemDB = function()
			return { AttachExternalRecipeInfo = function(_, tt)
				tt:AddLine(BREADCRUMB)          -- exactly what ATT emits
				return true
			end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)
		local _, line = tip:find("Kalimdor")
		assert.is_true(line.wrap)
	end)

	it("covers the hook-replay chain too, not just the ATT bridge", function()
		-- The path that reaches addons with no API at all. It is the one a
		-- per-integration fix cannot cover, because there is no list.
		ns.GetItemDB = function()
			return { ApplyExternalTooltipHooks = function(_, tt)
				tt:AddLine("RecipeMaster: known by Alt")
				return true
			end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)
		local _, line = tip:find("RecipeMaster")
		assert.is_true(line.wrap)
	end)

	it("covers TOGBankClassic's own renderer", function()
		_G.TOGBankClassic_TooltipBankerInfo = {
			AppendTo = function(_, tt) tt:AddLine("Bankers: Toglowlthrcp") end,
		}
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)
		local _, line = tip:find("Bankers")
		assert.is_true(line.wrap)
		_G.TOGBankClassic_TooltipBankerInfo = nil
	end)

	it("keeps the caller's colours — it forces the flag and nothing else", function()
		ns.GetItemDB = function()
			return { AttachExternalRecipeInfo = function(_, tt)
				tt:AddLine("coloured", 0.4, 0.8, 1)
				return true
			end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)
		local _, line = tip:find("coloured")
		assert.equal(0.4, line.r)
	end)

	it("puts the tooltip's own methods back afterwards", function()
		-- The whole safety argument. GameTooltip is shared; a shim left installed
		-- would force the flag on Blizzard's, ATT's and TSM's own tooltips for
		-- the rest of the session.
		local before = tip.AddLine
		ns.GetItemDB = function()
			return { AttachExternalRecipeInfo = function(_, tt) tt:AddLine("x") end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)
		assert.equal(before, tip.AddLine)
	end)

	it("puts them back even when the third party RAISES mid-render", function()
		local before = tip.AddLine
		ns.GetItemDB = function()
			return { AttachExternalRecipeInfo = function(_, tt)
				tt:AddLine("first")
				error("ATT blew up")
			end }
		end
		assert.has_no.errors(function() IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID) end)
		assert.equal(before, tip.AddLine)
		-- and what did land before the raise still wrapped
		local _, line = tip:find("first")
		assert.is_true(line.wrap)
	end)

	it("reports whether the call completed", function()
		assert.is_true(IL.WithWrappedLines(tip, function() end))
		assert.is_false(IL.WithWrappedLines(tip, function() error("nope") end))
	end)

	it("answers false rather than raising on bad arguments", function()
		assert.is_false(IL.WithWrappedLines(nil, function() end))
		assert.is_false(IL.WithWrappedLines(tip, "not a function"))
	end)
end)

describe("TOGBankClassic — the fallback, for a build older than the AppendTo contract", function()
	before_each(function()
		-- Pin these to the fallback. Without this the preferred path could satisfy
		-- them from a global some earlier spec left behind, and the branch these
		-- assertions are named for would never run.
		_G.TOGBankClassic_TooltipBankerInfo = nil
		ns.Bank = { GetBanksWithItem = function()
			return { { name = "Toglowlthrcp", count = 6 }, { name = "Zzz", count = 2 } }
		end }
	end)
	after_each(function() _G.TOGBankClassic_TooltipBankerInfo = nil end)

	it("renders the banker block in TOGBankClassic's own shape", function()
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		assert.is_truthy(tip:find("TOGBankClassic"))
		assert.is_truthy(tip:find("Bankers:"))
		local _, row = tip:find("Toglowlthrcp")
		assert.equal("6", row.right)
	end)

	it("puts a blank spacer before the heading", function()
		-- Without it the block runs straight into the reagent line above.
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		local i = tip:find("TOGBankClassic")
		assert.equal(" ", tip.lines[i - 1].text)
	end)

	it("adds nothing at all when no banker holds the item", function()
		-- Not an empty heading — nothing. An empty "Bankers:" block reads as
		-- data still loading.
		ns.Bank.GetBanksWithItem = function() return {} end
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		assert.same({}, tip:texts())
	end)

	it("is skipped entirely when TOGBankClassic is not loaded", function()
		ns.Bank = nil
		assert.has_no.errors(function() IL.AppendIntegrations(tip, nil, CRAFTED_ID) end)
		assert.same({}, tip:texts())
	end)
end)

describe("TOGBankClassic — the renderer it now exposes", function()
	-- DEPENDENCY_CONTRACTS.md §1. TOGBank owns the layout; we call it rather than
	-- keeping a copy, because the copy's DATA had already drifted from theirs in
	-- four ways while the layout still matched.
	local calls

	before_each(function()
		calls = {}
		ns.Bank = { GetBanksWithItem = function()
			error("the fallback must not run when the real renderer is available")
		end }
		_G.TOGBankClassic_TooltipBankerInfo = {
			AppendTo = function(self, t, itemId)
				calls[#calls + 1] = { self = self, tooltip = t, itemId = itemId }
				t:AddLine("Bankers:", 0.4, 0.8, 1, true)
				return true
			end,
		}
	end)

	after_each(function() _G.TOGBankClassic_TooltipBankerInfo = nil end)

	it("calls AppendTo with the crafted item id, as a method", function()
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		assert.equal(1, #calls)
		assert.equal(CRAFTED_ID, calls[1].itemId)
		assert.equal(tip, calls[1].tooltip)
		-- Passed as `self`, not dropped: AppendTo is declared with a colon and
		-- indexes `self` for nothing today, but a pcall'd dot-call would break
		-- silently the day it does.
		assert.equal(_G.TOGBankClassic_TooltipBankerInfo, calls[1].self)
		assert.is_truthy(tip:find("Bankers:"))
	end)

	it("does not also run our copy of the block", function()
		-- The fallback errors if reached; a second "Bankers:" would mean both ran.
		assert.has_no.errors(function() IL.AppendIntegrations(tip, nil, CRAFTED_ID) end)
		local n = 0
		for _, line in ipairs(tip.lines) do
			if line.text == "Bankers:" then n = n + 1 end
		end
		assert.equal(1, n)
	end)

	it("survives AppendTo raising, and still renders what comes after it", function()
		-- Another addon's code inside our render. Without the pcall a raise here
		-- aborts the rest of the block — the v1.0.7 failure shape.
		_G.TOGBankClassic_TooltipBankerInfo.AppendTo = function() error("boom") end
		local priced
		ns.GetItemDB = function()
			return {
				GetLink = function() return "|Hitem:1234:|h[Thing]|h" end,
				GetExternalPrices = function() priced = true; return nil end,
			}
		end
		assert.has_no.errors(function() IL.AppendIntegrations(tip, nil, CRAFTED_ID) end)
		assert.is_true(priced)
	end)

	it("falls back to our copy when the installed TOGBank predates the contract", function()
		_G.TOGBankClassic_TooltipBankerInfo = {}  -- loaded, but no AppendTo
		ns.Bank = { GetBanksWithItem = function()
			return { { name = "Toglowlthrcp", count = 6 } }
		end }
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		assert.is_truthy(tip:find("TOGBankClassic"))
		local _, row = tip:find("Toglowlthrcp")
		assert.equal("6", row.right)
	end)
end)

describe("the universal hook bridge", function()
	-- For addons that expose no API at all. RecipeMaster keeps its whole
	-- namespace private, so the only way to reach it is to replay GameTooltip's
	-- hook chain against our tooltip -- every handler in that chain operates on
	-- the tooltip it is passed.
	it("replays the SPELL chain, not the item one", function()
		-- The spell half is what can answer for a recipe with no teaching item,
		-- which is the entire population this function exists for. Asking for
		-- the item chain would miss exactly them.
		local asked
		ns.GetItemDB = function()
			return { ApplyExternalTooltipHooks = function(_, t, scriptType)
				asked = { tooltip = t, scriptType = scriptType }
				return true
			end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)
		assert.same({ tooltip = tip, scriptType = "OnTooltipSetSpell" }, asked)
	end)

	it("carries on when no chain exists or a handler declines", function()
		-- false is the documented "nothing happened" answer, not an error.
		ns.GetItemDB = function()
			return { ApplyExternalTooltipHooks = function() return false end }
		end
		assert.has_no.errors(function() IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID) end)
	end)

	it("is skipped by an ItemDB too old to have the bridge", function()
		ns.GetItemDB = function() return {} end
		assert.has_no.errors(function() IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID) end)
	end)
end)

describe("prices, through ItemDB's integration registry", function()
	-- This block used to reach into addon.Price and lay the rows out here,
	-- which meant duplicating TSM's labels and guessing at its shape. ItemDB
	-- owns every third-party bridge now, so we ask once and render whatever
	-- providers the player actually has.
	local LINK = "|cffffffff|Hitem:4394::::::::|h[Big Iron Bomb]|h|r"

	local function idbWith(prices)
		ns.GetItemDB = function()
			return {
				GetLink = function() return LINK end,
				GetExternalPrices = function() return prices end,
			}
		end
	end

	it("renders a row per provider, headed by the provider's name", function()
		idbWith({ TradeSkillMaster = { { label = "Market Value", value = 4500 } } })
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		assert.is_truthy(tip:find("TradeSkillMaster"))
		local _, row = tip:find("Market Value")
		assert.equal("4500c", row.right)
	end)

	it("prefers the provider's own formatting when it supplies it", function()
		-- TSM formats its own money; Auctionator does not. Re-formatting TSM's
		-- number would show the player a different string to the one TSM shows
		-- them everywhere else.
		idbWith({ TradeSkillMaster = { { label = "Market Value", value = 4500,
		                                 formatted = "45s 00c" } } })
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		local _, row = tip:find("Market Value")
		assert.equal("45s 00c", row.right)
	end)

	it("orders providers stably", function()
		-- pairs() over the provider table would reorder the block between
		-- hovers, which reads as flicker.
		idbWith({ Zeta = { { label = "z", value = 1 } },
		          Alpha = { { label = "a", value = 2 } } })
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		assert.is_true(tip:find("Alpha") < tip:find("Zeta"))
	end)

	it("adds nothing when no provider has anything", function()
		-- The registry returns nil rather than an empty table, so absence is
		-- one check and not two.
		idbWith(nil)
		IL.AppendIntegrations(tip, nil, CRAFTED_ID)
		assert.same({}, tip:texts())
	end)

	it("adds nothing when the item has no resolvable link", function()
		-- The registry keys off LINKS: passing an id silently returns nothing,
		-- so a missing link must stop us before we ask.
		ns.GetItemDB = function()
			return {
				GetLink = function() return nil end,
				GetExternalPrices = function() error("must not be reached") end,
			}
		end
		assert.has_no.errors(function() IL.AppendIntegrations(tip, nil, CRAFTED_ID) end)
		assert.same({}, tip:texts())
	end)

	it("is skipped entirely by an ItemDB without the registry", function()
		ns.GetItemDB = function() return { GetLink = function() return LINK end } end
		assert.has_no.errors(function() IL.AppendIntegrations(tip, nil, CRAFTED_ID) end)
		assert.same({}, tip:texts())
	end)
end)

describe("crafted-item quality colour", function()
	-- Recipe rows coloured themselves from the cached itemLink alone, so the
	-- colour depended on what the client had recently seen: the same recipe was
	-- coloured on one login and plain on the next, and one armour set rendered
	-- its pieces in different colours. Quality is a fixed property of the item
	-- and must never depend on cache state.
	local EPIC = "|cffa335ee|Hitem:19019::::::::|h[Thunderfury]|h|r"

	it("prefers a real link when there is one", function()
		assert.equal("ffa335ee", IL.QualityHex(EPIC, 19019))
	end)

	it("falls back to ItemDB when the link is not cached", function()
		-- The case that was broken. ItemDB ships quality for every item, so
		-- this answers offline on a cold client.
		ns.GetItemDB = function()
			return { GetLink = function(_, id)
				return id == 19019 and EPIC or nil
			end }
		end
		assert.equal("ffa335ee", IL.QualityHex(nil, 19019))
	end)

	it("does not let a cold GetItemInfo mask ItemDB's answer", function()
		-- Ordering matters: GetItemInfo returns nil for an uncached item, so
		-- asking it first would discard a perfectly good shipped quality.
		ns.GetItemDB = function()
			return { GetLink = function() return EPIC end }
		end
		_G.GetItemInfo = function() return nil end
		assert.equal("ffa335ee", IL.QualityHex(nil, 19019))
	end)

	it("returns nil rather than a wrong colour when nothing knows", function()
		ns.GetItemDB = function() return { GetLink = function() return nil end } end
		_G.GetItemInfo = function() return nil end
		assert.is_nil(IL.QualityHex(nil, 19019))
	end)

	it("returns nil for a recipe that crafts no item", function()
		-- Every enchant. Must not error on the nil id.
		assert.is_nil(IL.QualityHex(nil, nil))
	end)
end)

describe("guards", function()
	it("does nothing without a crafted item, but still runs ATT", function()
		-- An enchant produces no item, so bank and price have nothing to key
		-- on — but ATT is keyed by spell and must still be asked.
		local asked = false
		ns.GetItemDB = function()
			return { AttachExternalRecipeInfo = function() asked = true return true end }
		end
		ns.Bank = { GetBanksWithItem = function() error("must not be reached") end }
		IL.AppendIntegrations(tip, SPELL_ID, nil)
		assert.is_true(asked)
	end)

	it("tolerates a nil or line-less tooltip", function()
		assert.has_no.errors(function() IL.AppendIntegrations(nil, SPELL_ID, CRAFTED_ID) end)
		assert.has_no.errors(function() IL.AppendIntegrations({}, SPELL_ID, CRAFTED_ID) end)
	end)
end)
