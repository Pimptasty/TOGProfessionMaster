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

-- Audit finding 33: `addon.GetAddOnMetadata`, `addon:GetSpellInfo` and
-- `addon:GetItemInfo` were shims with NO production caller, and three cases
-- here vouched for them -- a green spec about dead code. Those
-- three cases are gone because the shims were deleted on purpose (the only
-- GetAddOnMetadata resolution that runs is TOGProfessionMaster.lua's own,
-- which loads before Compat; GetSpellInfo is the real function on every
-- flavour and is called bare; the item path is addon.Item.GetInfo, specced
-- below). What replaces them asserts the copy that actually runs.
describe("addon-info shims", function()
	it("prefers the C_AddOns namespace when present", function()
		_G.C_AddOns = {
			IsAddOnLoaded    = function(n) return n == "Yes" end,
			GetAddOnMetadata = function() return "9.9.9" end,
		}
		local ns = compatAt(11508)
		assert.is_true(ns:IsAddOnLoaded("Yes"))
		assert.is_false(ns:IsAddOnLoaded("No"))
	end)

	it("falls back to the bare globals on older clients", function()
		_G.C_AddOns = nil
		_G.IsAddOnLoaded    = function(n) return n == "Old" end
		local ns = compatAt(11508)
		assert.is_true(ns:IsAddOnLoaded("Old"))
	end)

	it("addon.Version is the product of the main file's own resolution, not of a Compat shim", function()
		-- The main file loads before Compat.lua, so it cannot use a shim here;
		-- this pins that the value the /togpm version command prints is the one
		-- the harness's TOC metadata carried at boot (env_togpm seeds it before
		-- loading the core -- the PACKAGED branch of that line). The "dev"
		-- fallback branch is NOT pinned: addon.Version is resolved once at load
		-- and AceAddon refuses a second NewAddon, so the main file cannot be
		-- booted again with the metadata absent. Said so it is not read as
		-- covered.
		local ns = env.boot()
		assert.equal(env.VERSION, ns.Version)
		assert.is_nil(ns.GetAddOnMetadata)
		assert.is_nil(ns.GetSpellInfo)
		assert.is_nil(ns.GetItemInfo)
	end)
end)

-- The item API resolver. Audit findings 26 and 27.
--
-- Every bare name it covers is a DEPRECATION FALLBACK that
-- Blizzard_DeprecatedItemScript.lua assigns from C_Item only when the
-- `loadDeprecationFallbacks` CVar is on -- so on a client with it off the bare
-- global is nil, an unguarded call raises and a presence-guarded one silently
-- skips. Both shapes shipped here.
--
-- Finding 27's point, and the reason each case sets the two spellings to
-- DIFFERENT functions: the harness env installs both names as the SAME function
-- object, so a spec that stubs one name and asserts the answer cannot tell which
-- one was called. Different answers per spelling is the only shape that can.
describe("item API resolver", function()
	local ns

	before_each(function()
		ns = compatAt(11508)
	end)

	it("prefers the C_Item namespace over the bare deprecation fallback", function()
		_G.C_Item = _G.C_Item or {}
		_G.C_Item.GetItemInfo = function() return "namespaced" end
		_G.GetItemInfo        = function() return "fallback" end
		assert.equal("namespaced", ns.Item.GetInfo(1))
	end)

	it("falls back to the bare global when the namespace lacks the function", function()
		_G.C_Item = {}
		_G.GetItemInfo = function() return "fallback" end
		assert.equal("fallback", ns.Item.GetInfo(1))
	end)

	it("answers nil when NEITHER spelling exists, instead of raising", function()
		-- This is the CVar-off client. The old code either raised here or, worse,
		-- skipped its whole branch behind `if GetItemInfo and ... then`.
		_G.C_Item = {}
		_G.GetItemInfo = nil
		assert.is_nil(ns.Item.GetInfo(1))
	end)

	it("resolves at CALL time, so a later stub is honoured", function()
		-- Early binding would capture whatever was installed when Compat loaded
		-- and ignore every later assignment -- specs would pass while measuring
		-- the env's function rather than their own.
		_G.C_Item = {}
		_G.GetItemInfo = function() return "first" end
		assert.equal("first", ns.Item.GetInfo(1))
		_G.GetItemInfo = function() return "second" end
		assert.equal("second", ns.Item.GetInfo(1))
	end)

	it("maps GetItemIcon to GetItemIconByID, which is NOT the same name", function()
		-- The bare-to-namespaced mapping is not one-to-one. A mechanical rename
		-- to C_Item.GetItemIcon produces a nil that only shows up in game as a
		-- missing texture.
		_G.C_Item = { GetItemIconByID = function() return 4242 end,
		              GetItemIcon     = function() return "WRONG" end }
		assert.equal(4242, ns.Item.GetIcon(1))
	end)

	it("covers every fallback name this addon calls", function()
		_G.C_Item = {
			GetItemInfo         = function() return "info" end,
			GetItemInfoInstant  = function() return "instant" end,
			GetItemIconByID     = function() return "icon" end,
			GetItemCount        = function() return "count" end,
			GetItemQualityColor = function() return "quality" end,
			GetItemCooldown     = function() return "cooldown" end,
		}
		assert.equal("info",     ns.Item.GetInfo(1))
		assert.equal("instant",  ns.Item.GetInfoInstant(1))
		assert.equal("icon",     ns.Item.GetIcon(1))
		assert.equal("count",    ns.Item.GetCount(1))
		assert.equal("quality",  ns.Item.GetQualityColor(1))
		-- Findings 29/31: the one name the sweep left out, and the one bare
		-- unguarded call left in the addon (ScanSaltShaker's second tier).
		assert.equal("cooldown", ns.Item.GetCooldown(1))
	end)

	it("passes every argument and return through untouched", function()
		_G.C_Item = { GetItemCount = function(a, b, c) return a, b, c end }
		local x, y, z = ns.Item.GetCount(1, true, "third")
		assert.equal(1, x)
		assert.is_true(y)
		assert.equal("third", z)
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

-- WoW Forever (in game 2026-09-27): no bare GetSpellCooldown, and IsSpellKnown
-- only as an off-by-default deprecation fallback. The helpers must answer the
-- classic shape from the namespaced API there, and the bare one elsewhere.
describe("the spell API helpers", function()
	local ns, saved
	local NAMES = { "C_Spell", "C_SpellBook", "GetSpellCooldown", "IsSpellKnown", "Enum",
	                "GetSpellInfo", "GetSpellTexture", "GetSpellLink" }

	before_each(function()
		ns = compatAt(11508)
		saved = {}
		for _, n in ipairs(NAMES) do saved[n] = _G[n] end
	end)
	after_each(function()
		for _, n in ipairs(NAMES) do _G[n] = saved[n] end
	end)

	it("unpacks C_Spell.GetSpellCooldown's table into start, duration, enabled, modRate", function()
		_G.GetSpellCooldown = nil
		_G.C_Spell = { GetSpellCooldown = function()
			return { startTime = 100, duration = 3600, isEnabled = true, modRate = 1 }
		end }
		local start, duration, enabled, modRate = ns.Spell.GetCooldown(11479)
		assert.equal(100, start)
		assert.equal(3600, duration)
		assert.is_true(enabled)
		assert.equal(1, modRate)
	end)

	it("falls back to the bare GetSpellCooldown where there is no C_Spell", function()
		_G.C_Spell = nil
		_G.GetSpellCooldown = function() return 5, 10, 1, 1 end
		local start, duration = ns.Spell.GetCooldown(1)
		assert.equal(5, start)
		assert.equal(10, duration)
	end)

	it("answers nil, not an error, on a client with neither", function()
		_G.C_Spell, _G.GetSpellCooldown = nil, nil
		assert.is_nil((ns.Spell.GetCooldown(1)))
	end)

	-- The Guild tab, in game on Forever: bare GetSpellInfo is nil there.
	it("unpacks C_Spell.GetSpellInfo's table into the classic list where the bare one is gone", function()
		_G.GetSpellInfo = nil
		_G.C_Spell = { GetSpellInfo = function(id)
			return { name = "Axesmith", iconID = 99, originalIconID = 98, castTime = 0,
			         minRange = 0, maxRange = 5, spellID = id }
		end }
		local name, rank, icon, castTime, minRange, maxRange, spellID = ns.Spell.GetInfo(17041)
		assert.equal("Axesmith", name)
		assert.is_nil(rank)
		assert.equal(99, icon)
		assert.equal(0, castTime)
		assert.equal(0, minRange)
		assert.equal(5, maxRange)
		assert.equal(17041, spellID)
	end)

	it("prefers the bare GetSpellInfo where it exists", function()
		_G.GetSpellInfo = function() return "bare", nil, 1 end
		_G.C_Spell = { GetSpellInfo = function() return { name = "namespaced" } end }
		assert.equal("bare", (ns.Spell.GetInfo(1)))
	end)

	it("answers nil for an unknown spell or a nil id, on either path", function()
		_G.GetSpellInfo = nil
		_G.C_Spell = { GetSpellInfo = function() return nil end }
		assert.is_nil((ns.Spell.GetInfo(1)))
		assert.is_nil((ns.Spell.GetInfo(nil)))
	end)

	it("reaches C_Spell for the texture and the link when the bare ones are gone", function()
		_G.GetSpellTexture, _G.GetSpellLink = nil, nil
		_G.C_Spell = {
			GetSpellTexture = function() return 1234 end,
			GetSpellLink    = function(id) return "|Hspell:" .. id .. "|h[x]|h" end,
		}
		assert.equal(1234, ns.Spell.GetTexture(5))
		assert.equal("|Hspell:5|h[x]|h", ns.Spell.GetLink(5))
	end)

	it("uses the bare IsSpellKnown where it exists", function()
		_G.IsSpellKnown = function(id, isPet) return id == 7 and not isPet end
		assert.is_true(ns.Spell.IsKnown(7, false))
		assert.is_false(ns.Spell.IsKnown(8, false))
	end)

	it("does what Forever's fallback does when the bare one is gone", function()
		_G.IsSpellKnown = nil
		local asked
		_G.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
		_G.C_SpellBook = { IsSpellInSpellBook = function(id, bank, overrides)
			asked = { id, bank, overrides }
			return id == 7
		end }
		assert.is_true(ns.Spell.IsKnown(7, false))
		assert.same({ 7, 0, false }, asked)
		assert.is_false(ns.Spell.IsKnown(9, true))
		assert.same({ 9, 1, false }, asked)
	end)
end)

-- Tooltip.AnchorFrame's specs left with the function: popup placement is
-- LibAceGUIWidgets' AnchorPopup now, specced in that library.

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
		}, { "Bank1", "Bank2" })
		assert.equal(32, ns.Bank.GetStock(2589))
		assert.equal(0, ns.Bank.GetStock(4444))
	end)

	it("does not count an EX-banker whose stored inventory TOGBank still holds", function()
		-- TOGBank keeps a record for a character whose bank note was removed
		-- (its TOOLTIP-002 class); it is in Info.alts but not in GetBanks().
		-- Counting it lit the [Bank] button against stock nobody could send.
		-- TOGBankClassic's finding, thread 5eef0788 F2.
		installBank({
			Bank1 = { items = { { ID = 2589, Count = 20 } } },
			Retired = { items = { { ID = 2589, Count = 20 } } },
		}, { "Bank1" })
		assert.equal(20, ns.Bank.GetStock(2589))
		installBank({
			Retired = { items = { { ID = 2589, Count = 20 } } },
		}, {})
		assert.equal(0, ns.Bank.GetStock(2589))
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
		-- GetStock IS the sum of GetBanksWithItem since v1.1.0; this pins that
		-- the composition holds rather than two walks happening to agree.
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

	-- TOGBankClassic v1.4.2, INV2-RETIRE-003 (peer-review thread 18f6cc11):
	-- the per-alt `items` rows are gone -- not written, stripped on load -- and
	-- the inventory is read through `Guild:GetAltItemTotal(altName, itemId)`.
	-- These install THAT shape: an alt record with no `items` at all, and the
	-- accessor answering.
	describe("against a TOGBankClassic where alt.items is nil and GetAltItemTotal exists", function()
		--- `store[altName][itemId] = count`, the way the V2 store answers.
		local function installV2(store, banks, opts)
			_G.TOGBankClassic_Guild = {
				Info = { alts = {} },
				GetBanks = function() return banks or {} end,
				IsBank = function() return true end,
				GetAltItemTotal = function(_, altName, itemId)
					return store[altName] and store[altName][itemId] or 0
				end,
				NormalizeName = opts and opts.normalize,
			}
			for altName in pairs(store) do
				_G.TOGBankClassic_Guild.Info.alts[altName] = { lastScan = 1 }   -- no items field
			end
		end

		it("totals stock through the accessor when the rows are gone", function()
			installV2({ Bank1 = { [2589] = 20 }, Bank2 = { [2589] = 12 } }, { "Bank1", "Bank2" })
			assert.equal(32, ns.Bank.GetStock(2589))
			assert.equal(0,  ns.Bank.GetStock(4444))
		end)

		it("lists bankers through the accessor when the rows are gone", function()
			installV2({ Zed = { [2589] = 3 }, Abe = { [2589] = 7 }, None = { [2589] = 0 } },
			          { "Zed", "Abe", "None", "Ghost" })
			local out = ns.Bank.GetBanksWithItem(2589)
			assert.equal(2, #out)
			assert.equal("Abe", out[1].name)
			assert.equal(7,     out[1].count)
			assert.equal("Zed", out[2].name)
		end)

		it("would have reported EMPTY everywhere on the old reader -- the failure the finding describes", function()
			-- Same fixture, read the old way: nothing.
			installV2({ Bank1 = { [2589] = 20 } }, { "Bank1" })
			local legacy = 0
			for _, alt in pairs(_G.TOGBankClassic_Guild.Info.alts) do
				for _, e in ipairs(alt.items or {}) do if e.ID == 2589 then legacy = legacy + e.Count end end
			end
			assert.equal(0,  legacy)
			assert.equal(20, ns.Bank.GetStock(2589))
		end)

		it("prefers the accessor over stale rows when a record carries both", function()
			-- An older SavedVariable read by a newer client before the strip ran,
			-- or a shim answering `items`: the accessor is the truth either way.
			installV2({ Bank1 = { [2589] = 20 } }, { "Bank1" })
			_G.TOGBankClassic_Guild.Info.alts.Bank1.items = { { ID = 2589, Count = 999 } }
			assert.equal(20, ns.Bank.GetStock(2589))
			assert.equal(20, ns.Bank.GetBanksWithItem(2589)[1].count)
		end)

		it("normalizes the roster name before asking the store, and reports the roster name back", function()
			-- GetBanks hands out roster names; the store is keyed by TOGBank's
			-- normalized form. The player sees the name GetBanks gave.
			installV2({ ["Abe-Testrealm"] = { [2589] = 7 } }, { "Abe" },
			          { normalize = function(_, n) return n .. "-Testrealm" end })
			local out = ns.Bank.GetBanksWithItem(2589)
			assert.equal(1,     #out)
			assert.equal("Abe", out[1].name)
			assert.equal(7,     out[1].count)
		end)

		it("still opens the request dialog's gate on accessor-reported stock", function()
			-- ShowRequestDialog sums GetBanksWithItem into totalStock; with the
			-- rows gone that sum was 0 and the dialog refused every request.
			local said
			_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) said = msg end }
			installV2({ Bank1 = { [111] = 1 } }, { "Bank1" })
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.is_true(said:find("No bankers", 1, true) ~= nil)
			said = nil
			installV2({ Bank1 = { [2589] = 5 } }, { "Bank1" })
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.is_nil(said)
		end)
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

	-- TOGBank SETTINGS-CANON-001 (peer-review thread 17a1f2c9): Guild:AddRequest
	-- ENFORCES the officer's maximum request %, per bank, less the requester's open
	-- orders there. The dialog used to offer a percent of the WHOLE GUILD's stock,
	-- so it offered quantities Send was then refused for, and printed "Check that
	-- TOGBankClassic is synced" in place of the reason AddRequest gave.
	describe("the request dialog against TOGBank's enforced allowance", function()
		local said, added

		after_each(function() _G.TOGBankClassic_Options = nil end)

		--- Two bankers (Abe 10, Zed 30) at `pct`, with `open[bank]` already on order,
		--- modelled on TOGBank's own RequestAllowance/RequestLimitText shapes.
		local function installLimited(pct, open, addResult, addWhy)
			installBank({
				Abe = { items = { { ID = 2589, Count = 10 } } },
				Zed = { items = { { ID = 2589, Count = 30 } } },
			}, { "Abe", "Zed" })
			local G = _G.TOGBankClassic_Guild
			G.GetNormalizedPlayer = function() return "Me-Testrealm" end
			G.RequestAllowance = function(_, requester, bank, itemID, count)
				assert.equal("Me-Testrealm", requester)
				assert.equal(2589, itemID)
				local cap = math.floor(count * pct / 100)
				local o = (open and open[bank]) or 0
				return math.max(0, cap - o), cap, o, pct, count
			end
			G.RequestLimitText = function(_, left, cap, o)
				return ("LIMIT left=%d cap=%d open=%d"):format(left, cap, o)
			end
			G.AddRequest = function(_, req)
				added = req
				return addResult, addWhy
			end
			said = {}
			added = nil
			_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) said[#said + 1] = msg end }
		end

		local function dialog() return _G.TOGPMBankRequestDialog end
		local function send(qty)
			dialog().qtyBox:SetText(tostring(qty))
			dialog().sendBtn:GetScript("OnClick")(dialog().sendBtn)
		end

		it("offers the selected bank's allowance, not a percent of the guild's stock", function()
			installLimited(50, { Abe = 2 }, true)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			-- Abe (sorted first) holds 10: 50% is 5, less 2 on order. The old
			-- whole-guild figure was floor(40 * 50%) = 20.
			assert.equal(3, dialog().maxRequestable)
			assert.equal("/ max 3", dialog().maxLbl:GetText())
		end)

		it("recomputes the allowance when the player picks another banker", function()
			installLimited(50, { Abe = 2 }, true)
			_G.UIDROPDOWNMENU_ADDED = {}
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			local zed
			for _, b in ipairs(_G.UIDROPDOWNMENU_ADDED) do
				if b.info.value == "Zed" then zed = b.info end
			end
			assert(zed, "the banker dropdown lists Zed")
			zed.func()
			assert.equal("Zed", dialog().selectedBank)
			assert.equal(15, dialog().maxRequestable)
			assert.equal("/ max 15", dialog().maxLbl:GetText())
		end)

		it("refuses over the allowance with TOGBank's sentence and never places the order", function()
			installLimited(50, { Abe = 2 }, true)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			send(4)
			assert.is_nil(added)
			assert.is_truthy(said[#said]:find("LIMIT left=3 cap=5 open=2", 1, true))
		end)

		it("says why when the open orders have used the whole allowance", function()
			installLimited(50, { Abe = 5 }, true)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.equal(0, dialog().maxRequestable)
			send(1)
			assert.is_nil(added)
			assert.is_truthy(said[#said]:find("LIMIT left=0 cap=5 open=5", 1, true))
		end)

		it("places an order within the allowance", function()
			installLimited(50, nil, true)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			send(5)
			assert.equal(5, added.quantity)
			assert.equal("Abe", added.bank)
			assert.is_truthy(said[#said]:find("Bank request sent", 1, true))
		end)

		it("prints the reason AddRequest refused with, not a guess about syncing", function()
			installLimited(50, nil, false, "Ordering is closed.")
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			send(1)
			assert.is_truthy(added)
			assert.is_truthy(said[#said]:find("Ordering is closed.", 1, true))
			assert.is_nil(said[#said]:find("synced", 1, true))
		end)

		it("keeps the old message when AddRequest gives no reason", function()
			installLimited(50, nil, false)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			send(1)
			assert.is_truthy(said[#said]:find("Check that TOGBankClassic is synced", 1, true))
		end)

		it("caps at the bank's own stock when the officer sets no limit", function()
			-- At 100% AddRequest gates nothing; the order is from one bank.
			installLimited(100, { Abe = 9 }, true)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.equal(10, dialog().maxRequestable)
			assert.equal("Bank stock: 10", dialog().stockLbl:GetText())
		end)

		it("pairs the selected banker's stock with that banker's cap on the stock line", function()
			-- Independent review, finding 3: "Bank stock: 40 | Max requestable: 5
			-- (50%)" read as a wrong sum -- 5 is 50% of Abe's 10, not of the guild's 40.
			installLimited(50, nil, true)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.equal("Bank stock: 10  |  Max requestable: 5 (50%)", dialog().stockLbl:GetText())
		end)

		it("re-checks the allowance at Send, keeping the quantity typed", function()
			-- Independent review, finding 2: an open order filled while the dialog
			-- sat open raised the allowance, and the stale figure refused an order
			-- TOGBank would have taken.
			local open = { Abe = 2 }
			installLimited(50, open, true)
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.equal(3, dialog().maxRequestable)
			open.Abe = 0
			send(5)
			assert(added, "the order was placed")
			assert.equal(5, added.quantity)
			assert.equal("5", dialog().qtyBox:GetText())
		end)

		it("never offers a view-only banker, even as the alphabetical first", function()
			-- Independent review, finding 4: VIEWBANK-001 refuses them in AddRequest.
			installLimited(50, nil, true)
			_G.TOGBankClassic_Guild.IsViewOnlyBank = function(_, n) return n == "Abe" end
			_G.UIDROPDOWNMENU_ADDED = {}
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.equal("Zed", dialog().selectedBank)
			assert.equal(15, dialog().maxRequestable)
			send(1)
			assert.equal("Zed", added.bank)
		end)

		it("says so when only view-only bankers hold the item", function()
			installLimited(50, nil, true)
			_G.TOGBankClassic_Guild.IsViewOnlyBank = function() return true end
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.is_truthy(said[#said]:find("view-only", 1, true))
		end)

		describe("while TOGBank's shop is on", function()
			-- Independent review, finding 1: AddRequest refuses any order without
			-- shopOrder = true while the shop sells (SHOP-NOFREE-001), so every
			-- [Bank] order failed. Guild:ShopOrderFields is TOGBank's builder for
			-- other addons: merge every field but `prompt`, show `prompt`.
			local function installShop(fields)
				installLimited(50, nil, true)
				_G.TOGBankClassic_Guild.ShopOrderFields = function(_, itemID)
					assert.equal(2589, itemID)
					return fields
				end
			end

			it("marks the order a shop order carrying the estimate, without the prompt", function()
				installShop({ shopOrder = true, estimate = 1234, estimateBase = 2468, discount = 50,
					estimateSource = "min buyout, Auctionator", prompt = "Shop order -- estimated ~12s 34c each." })
				ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
				send(2)
				assert.is_true(added.shopOrder)
				assert.equal(1234, added.estimate)
				assert.equal(2468, added.estimateBase)
				assert.equal(50, added.discount)
				assert.equal("min buyout, Auctionator", added.estimateSource)
				assert.is_nil(added.prompt)
				assert.equal(2, added.quantity)
			end)

			it("shows TOGBank's shop line in the dialog", function()
				installShop({ shopOrder = true, prompt = "Shop order -- no estimate for this item yet." })
				ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
				assert.equal("Shop order -- no estimate for this item yet.", dialog().shopLbl:GetText())
				assert.is_true(dialog().shopLbl:IsShown())
				assert.equal(205, dialog():GetHeight())
			end)

			it("adds nothing and hides the line when the shop is off", function()
				installShop(nil)
				ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
				assert.is_false(dialog().shopLbl:IsShown())
				assert.equal(165, dialog():GetHeight())
				send(1)
				assert.is_nil(added.shopOrder)
			end)
		end)

		it("keeps the whole-guild percent against a TOGBank without the accessor", function()
			installBank({
				Abe = { items = { { ID = 2589, Count = 10 } } },
				Zed = { items = { { ID = 2589, Count = 30 } } },
			}, { "Abe", "Zed" })
			_G.TOGBankClassic_Options = { GetMaxRequestPercent = function() return 50 end }
			ns.Bank.ShowRequestDialog(2589, "Linen Cloth")
			assert.equal(20, dialog().maxRequestable)
			assert.equal("Bank stock: 40  |  Max requestable: 20 (50%)", dialog().stockLbl:GetText())
		end)
	end)

	-- The user, 2026-09-14, of TOGBank's green dots: "i would like to add those
	-- dots next to the items in TOGPM as well if they have the bank button
	-- available, so folks can tell at a glance if it's stale or not." The
	-- state per banker is TOGBank's `Guild:GetAltStaleness`; the colours are
	-- read from its Browse window's tables when present.
	describe("the staleness dot on [Bank]", function()
		local DOT = "\226\128\162"

		--- TOGBank with the staleness accessor: `states[altName] = state`.
		local function installStale(alts, banks, states)
			installBank(alts, banks)
			_G.TOGBankClassic_Guild.GetAltStaleness = function(_, norm)
				return states[norm], 0, 0
			end
		end

		after_each(function() _G.TOGBankClassic_UI_Browse = nil end)

		it("carries each banker's state on GetBanksWithItem", function()
			installStale({ Abe = { items = { { ID = 2589, Count = 1 } } },
			               Zed = { items = { { ID = 2589, Count = 1 } } } },
			             { "Abe", "Zed" }, { Abe = "current", Zed = "behind" })
			local out = ns.Bank.GetBanksWithItem(2589)
			assert.equal("current", out[1].state)
			assert.equal("behind",  out[2].state)
		end)

		it("carries no state against a TOGBank that predates the accessor, and draws no dot", function()
			installBank({ Abe = { items = { { ID = 2589, Count = 1 } } } }, { "Abe" })
			assert.is_nil(ns.Bank.GetBanksWithItem(2589)[1].state)
			assert.is_nil(ns.Bank.ItemState(2589))
			assert.equal("|cFF88FF88[Bank]|r", ns.Bank.ButtonText(2589))
		end)

		it("is the WORST state across the bankers holding the item", function()
			-- One dot stands for every banker; a red among greens is what the
			-- glance is for.
			installStale({ Abe = { items = { { ID = 2589, Count = 1 } } },
			               Bob = { items = { { ID = 2589, Count = 1 } } },
			               Zed = { items = { { ID = 2589, Count = 1 } } } },
			             { "Abe", "Bob", "Zed" }, { Abe = "current", Bob = "offered", Zed = "current" })
			assert.equal("offered", ns.Bank.ItemState(2589))
			_G.TOGBankClassic_Guild.GetAltStaleness = function(_, n)
				return ({ Abe = "current", Bob = "offered", Zed = "behind" })[n], 0, 0
			end
			assert.equal("behind", ns.Bank.ItemState(2589))
		end)

		it("is green for a banker whose copy is current, and nothing for an item nobody holds", function()
			installStale({ Abe = { items = { { ID = 2589, Count = 1 } } } }, { "Abe" }, { Abe = "current" })
			assert.equal("|cff00ff00" .. DOT .. "|r |cFF88FF88[Bank]|r", ns.Bank.ButtonText(2589))
			assert.is_nil(ns.Bank.ItemState(4444))
			assert.is_nil(ns.Bank.ItemState(nil))
		end)

		it("paints the dot in TOGBank's own colour when its Browse window publishes one", function()
			-- The palette is read from TOGBankClassic_UI_Browse.STATE_COLOR so a
			-- change there reaches these dots; the local table is only the
			-- fallback for a TOGBank that has the accessor but not the window.
			installStale({ Abe = { items = { { ID = 2589, Count = 1 } } } }, { "Abe" }, { Abe = "current" })
			_G.TOGBankClassic_UI_Browse = {
				STATE_COLOR = { current = "ff123456" },
				STATE_TEXT  = { current = "Up to date" },
			}
			assert.equal("ff123456", ns.Bank.StateColor("current"))
			assert.equal("Up to date", ns.Bank.StateText("current"))
			assert.is_truthy(ns.Bank.ButtonText(2589):find("|cff123456" .. DOT, 1, true))
		end)

		it("falls back to TOGBank's shipped palette, verbatim, and to grey for a state it does not know", function()
			assert.equal("ffff0000", ns.Bank.StateColor("behind"))
			assert.equal("ffffff00", ns.Bank.StateColor("offered"))
			assert.equal("ffa0a0a0", ns.Bank.StateColor("refused"))
			assert.equal("ff808080", ns.Bank.StateColor("something-new"))
			assert.equal("Behind",   ns.Bank.StateText("behind"))
			assert.equal("something-new", ns.Bank.StateText("something-new"))
		end)

		it("labels a raw button and remembers its item; an AceGUI widget gets the text only", function()
			installStale({ Abe = { items = { { ID = 2589, Count = 1 } } } }, { "Abe" }, { Abe = "current" })
			local raw = { SetText = function(self, t) self.text = t end }
			ns.Bank.Decorate(raw, 2589)
			assert.equal(ns.Bank.ButtonText(2589), raw.text)
			assert.equal(2589, raw._bankItemId)
			-- A widget is pooled account-wide: no field may ride into its next owner.
			local widget = { frame = {}, SetText = function(self, t) self.text = t end }
			ns.Bank.Decorate(widget, 2589, nil, "Bank")
			assert.equal("|cff00ff00" .. DOT .. "|r Bank", widget.text)
			assert.is_nil(widget._bankItemId)
			-- A button whose text lives on a separate FontString.
			local fs, btn = { SetText = function(self, t) self.text = t end }, {}
			ns.Bank.Decorate(btn, 2589, fs)
			assert.equal(ns.Bank.ButtonText(2589), fs.text)
			assert.equal(2589, btn._bankItemId)
			ns.Bank.Decorate(nil, 2589)   -- tolerated
		end)

		it("adds one tooltip line per banker, name, count and status, in TOGBank's colour", function()
			installStale({ Abe = { items = { { ID = 2589, Count = 7 } } },
			               Zed = { items = { { ID = 2589, Count = 3 } } } },
			             { "Abe", "Zed" }, { Abe = "current", Zed = "behind" })
			local lines = {}
			_G.GameTooltip = {
				AddLine = function(_, t) lines[#lines + 1] = t end,
				AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end,
			}
			local btn = {}
			ns.Bank.Decorate(btn, 2589)
			ns.Bank.AddStatusLines(btn)
			assert.equal(3, #lines)
			assert.equal(" ", lines[1])
			assert.equal("|cff00ff00" .. DOT .. "|r Abe (7) | |cff00ff00Current|r", lines[2])
			assert.equal("|cffff0000" .. DOT .. "|r Zed (3) | |cffff0000Behind|r",  lines[3])
		end)

		it("adds nothing for a button with no item, or when TOGBank reports no state", function()
			local lines = {}
			_G.GameTooltip = {
				AddLine = function(_, t) lines[#lines + 1] = t end,
				AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. r end,
			}
			ns.Bank.AddStatusLines({})
			ns.Bank.AddStatusLines(nil)
			installBank({ Abe = { items = { { ID = 2589, Count = 7 } } } }, { "Abe" })
			ns.Bank.AddStatusLines({ _bankItemId = 2589 })
			assert.same({}, lines)
		end)
	end)
end)
