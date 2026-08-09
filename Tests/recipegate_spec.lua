-- addon.RecipeGate — the single client-validity gate for recipe lists.
--
-- This file exists because the rule it covers was written out TWICE, in
-- GUI/BrowserTab.lua and GUI/MissingRecipesTab.lua, and each copy grew a gate
-- the other lacked. Specs existed for both tabs and both passed: every gate had
-- a test somewhere, and nothing tested that the two tabs AGREED. So the last
-- describe block here is the important one — it asserts the rule has exactly
-- one implementation, which is the only property that cannot drift.
--
-- Shipped consequence of the drift: Netherweave Bandage (27032) and Heavy
-- Netherweave Bandage (27033) are TBC First Aid recipes whose spells AND items
-- both resolve on a 1.15 Era client, so they survive every generic gate. Only
-- the explicit blacklist stops them, and Missing Recipes never had it.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, MR
local ME       = "Testchar-Testrealm"
local ALCHEMY  = 171
local FIRSTAID = 129
local COOKING  = 185

-- Saved so a flavour flag set by one example cannot leak into a later spec
-- FILE — the whole suite shares one Lua state and one `ns`.
local savedFlags, savedGetItemInfoInstant

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	-- SharedWidgets before the tab, mirroring the TOC — MissingRecipesTab reads
	-- addon.ItemLink at file scope.
	env.loadModule("GUI/SharedWidgets.lua")
	MR = env.loadModule("GUI/MissingRecipesTab.lua").MissingRecipesTab
end)

before_each(function()
	env.install()
	savedFlags = {
		isVanilla = ns.isVanilla, isTBC = ns.isTBC, isWrath = ns.isWrath,
		isCata = ns.isCata, isMoP = ns.isMoP,
	}
	savedGetItemInfoInstant = _G.GetItemInfoInstant
	ns.isVanilla, ns.isTBC, ns.isWrath, ns.isCata, ns.isMoP = true, false, false, false, false
end)

after_each(function()
	for k, v in pairs(savedFlags) do ns[k] = v end
	_G.GetItemInfoInstant = savedGetItemInfoInstant
end)

--- Verdict + reason for a recipe, on whatever client the example has set up.
local function gate(profId, id, meta)
	return ns.RecipeGate:IsValidOnClient(profId, id, meta)
end

describe("RecipeGate:Client", function()
	it("maps each supported client to its expansion index and skill cap", function()
		local cases = {
			{ flag = "isVanilla", exp = 1, cap = 300 },
			{ flag = "isTBC",     exp = 2, cap = 375 },
			{ flag = "isWrath",   exp = 3, cap = 450 },
			{ flag = "isCata",    exp = 4, cap = 525 },
			{ flag = "isMoP",     exp = 5, cap = 600 },
		}
		for _, c in ipairs(cases) do
			ns.isVanilla, ns.isTBC, ns.isWrath, ns.isCata, ns.isMoP = false, false, false, false, false
			ns[c.flag] = true
			local exp, cap = ns.RecipeGate:Client()
			assert.equal(c.exp, exp)
			assert.equal(c.cap, cap)
		end
	end)

	it("falls through to the newest profile on an unrecognised client", function()
		ns.isVanilla, ns.isTBC, ns.isWrath, ns.isCata, ns.isMoP = false, false, false, false, false
		local exp, cap = ns.RecipeGate:Client()
		assert.equal(5, exp)
		assert.equal(600, cap)
	end)
end)

describe("RecipeGate:IsValidOnClient — Classic Era", function()
	it("passes an ordinary Vanilla recipe", function()
		env.spellsExist(2330)
		assert.is_true(gate(ALCHEMY, 2330, { name = "Minor Healing Potion", requiredSkill = 1 }))
	end)

	it("rejects a recipe with no row in the recipe DB", function()
		local ok, why = gate(ALCHEMY, 2330, nil)
		assert.is_false(ok)
		assert.equal("nometa", why)
	end)

	it("rejects Season of Discovery IDs", function()
		env.spellsExist(400001)
		local ok, why = gate(ALCHEMY, 400001, { name = "SoD rune" })
		assert.is_false(ok)
		assert.equal("sod", why)
	end)

	it("rejects a recipe tagged for a later expansion", function()
		env.spellsExist(53771)
		local ok, why = gate(ALCHEMY, 53771, { name = "Wrath transmute", minExpansion = 3 })
		assert.is_false(ok)
		assert.equal("minExpansion", why)
	end)

	it("rejects a recipe whose spell the client does not have", function()
		local ok, why = gate(ALCHEMY, 24238, { name = "Not on this client" })
		assert.is_false(ok)
		assert.equal("nospell", why)
	end)

	it("rejects a recipe above the client's skill cap", function()
		env.spellsExist(2330)
		local ok, why = gate(ALCHEMY, 2330, { name = "Too advanced", requiredSkill = 375 })
		assert.is_false(ok)
		assert.equal("skillcap", why)
	end)

	it("rejects seasonal content", function()
		env.spellsExist(2330)
		local ok, why = gate(ALCHEMY, 2330, { name = "Seasonal", season = 1 })
		assert.is_false(ok)
		assert.equal("season", why)
	end)

	-- Deliberately NOT a blacklisted id: the blacklist returns first, so reusing
	-- one here would assert "blacklist" and leave this path unexercised.
	it("rejects an untagged high-ID recipe whose item does not resolve", function()
		env.spellsExist(26000)
		_G.GetItemInfoInstant = function() return nil end
		local ok, why = gate(COOKING, 26000, { name = "Untagged post-Vanilla", craftedItemId = 22645 })
		assert.is_false(ok)
		assert.equal("untagged", why)
	end)

	it("passes an untagged high-ID recipe when both its spell and item resolve", function()
		env.spellsExist(26000)
		_G.GetItemInfoInstant = function(id) return id end
		assert.is_true(gate(COOKING, 26000, { name = "Untagged but real", craftedItemId = 22645 }))
	end)
end)

-- The regression the drift produced. Each of these resolves as a spell AND as
-- an item on a 1.15 client, so it clears the SoD range, the minExpansion tag,
-- the spell-presence check and the untagged high-ID rule. The blacklist is the
-- only thing standing between it and a "you are missing this" row.
describe("RecipeGate — TBC recipes that survive every generic Era gate", function()
	before_each(function()
		_G.GetItemInfoInstant = function(id) return id end
	end)

	local LEAKS = {
		{ prof = FIRSTAID, id = 27032, name = "Netherweave Bandage" },
		{ prof = FIRSTAID, id = 27033, name = "Heavy Netherweave Bandage" },
		{ prof = COOKING,  id = 30047, name = "Crystal Throat Lozenge" },
	}

	for _, leak in ipairs(LEAKS) do
		it("rejects " .. leak.name .. " on Era", function()
			env.spellsExist(leak.id)
			local ok, why = gate(leak.prof, leak.id, { name = leak.name, craftedItemId = 21877 })
			assert.is_false(ok, leak.name .. " reached an Era recipe list")
			assert.equal("blacklist", why)
		end)

		it("keeps " .. leak.name .. " on a TBC client, where it is real", function()
			ns.isVanilla, ns.isTBC = false, true
			env.spellsExist(leak.id)
			assert.is_true(gate(leak.prof, leak.id, { name = leak.name, craftedItemId = 21877 }))
		end)
	end

	it("blacklists by profession, not by id alone", function()
		env.spellsExist(27032)
		-- The same id under a different profession is not the leaked recipe.
		assert.is_true(gate(ALCHEMY, 27032, { name = "Some alchemy recipe", craftedItemId = 21877 }))
	end)
end)

-- Every check is an independent early return, never an elseif chain. The old
-- Missing Recipes copy WAS a chain, and its untagged-high-ID branch could
-- evaluate true without rejecting — which short-circuited the branches below it
-- and switched off the season, skill-cap and phase gates for that recipe.
describe("RecipeGate — no gate can be short-circuited by an earlier one", function()
	before_each(function()
		_G.GetItemInfoInstant = function(id) return id end
		env.spellsExist(25704)
	end)

	it("still applies the season gate to an untagged high-ID recipe", function()
		local ok, why = gate(ALCHEMY, 25704, { name = "Untagged seasonal", craftedItemId = 21877, season = 1 })
		assert.is_false(ok)
		assert.equal("season", why)
	end)

	it("still applies the skill cap to an untagged high-ID recipe", function()
		local ok, why = gate(ALCHEMY, 25704, { name = "Untagged, too advanced", craftedItemId = 21877, requiredSkill = 375 })
		assert.is_false(ok)
		assert.equal("skillcap", why)
	end)
end)

describe("RecipeGate — TBC content phase", function()
	before_each(function()
		ns.isVanilla, ns.isTBC = false, true
		env.spellsExist(28596)
		ns.lib.db.profile.tbcAnniversaryPhase = 2
	end)

	it("rejects a recipe gated behind a phase that is not live", function()
		local ok, why = gate(ALCHEMY, 28596, { name = "Sunwell pattern", phase = 4 })
		assert.is_false(ok)
		assert.equal("phase", why)
	end)

	it("passes a recipe from the live phase", function()
		assert.is_true(gate(ALCHEMY, 28596, { name = "Launch pattern", phase = 2 }))
	end)

	it("passes a recipe carrying no phase tag at all", function()
		assert.is_true(gate(ALCHEMY, 28596, { name = "Untagged pattern" }))
	end)
end)

describe("RecipeGate — never-implemented recipes", function()
	local savedLib

	before_each(function()
		env.spellsExist(2336)
		savedLib = LibStub.libs["LibProfessionDB-1.0"]
	end)

	after_each(function()
		LibStub.libs["LibProfessionDB-1.0"] = savedLib
	end)

	it("rejects a recipe ProfessionDB reports as never implemented", function()
		LibStub.libs["LibProfessionDB-1.0"] = {
			IsHiddenRecipe = function(_, id) return id == 2336 end,
		}
		local ok, why = gate(ALCHEMY, 2336, { name = "Elixir of Tongues", requiredSkill = 100 })
		assert.is_false(ok)
		assert.equal("nyi", why)
	end)

	it("passes a recipe the same ProfessionDB does not flag", function()
		LibStub.libs["LibProfessionDB-1.0"] = {
			IsHiddenRecipe = function(_, id) return id == 2336 end,
		}
		env.spellsExist(2330)
		assert.is_true(gate(ALCHEMY, 2330, { name = "Minor Healing Potion", requiredSkill = 1 }))
	end)

	-- ProfessionDB gained IsHiddenRecipe in MINOR 9. TOGPM ships against older
	-- copies too, and an absent method must leave the check inert, not error.
	it("stays inert against a ProfessionDB that predates IsHiddenRecipe", function()
		LibStub.libs["LibProfessionDB-1.0"] = { LoadNames = function() end }
		assert.is_true(gate(ALCHEMY, 2336, { name = "Elixir of Tongues", requiredSkill = 100 }))
	end)

	it("stays inert when ProfessionDB is not installed at all", function()
		LibStub.libs["LibProfessionDB-1.0"] = nil
		assert.is_true(gate(ALCHEMY, 2336, { name = "Elixir of Tongues", requiredSkill = 100 }))
	end)
end)

-- The Missing Recipes tab end-to-end, because that is where the leak was seen.
describe("Missing Recipes applies the shared gate", function()
	it("does not offer Netherweave bandages to an Era First Aid character", function()
		_G.GetItemInfoInstant = function(id) return id end
		_G.GetItemInfo = function() return nil end
		_G.GetItemIcon = function() return nil end
		env.spellsExist(3275, 27032, 27033)
		local gdb = env.resetDb()
		env.roster({ { name = "Testchar", isOnline = true } })
		env.setRecipeDB({
			[FIRSTAID] = {
				[3275]  = { name = "Linen Bandage",             craftedItemId = 1251,  requiredSkill = 1 },
				[27032] = { name = "Netherweave Bandage",       craftedItemId = 21990, requiredSkill = 330 },
				[27033] = { name = "Heavy Netherweave Bandage", craftedItemId = 21991, requiredSkill = 360 },
			},
		})
		ns.sourceDB = { [FIRSTAID] = {} }
		gdb.skills[ME] = { [FIRSTAID] = { skillRank = 150, skillMax = 300 } }
		gdb.accountChars[ME] = true

		local seen = {}
		for _, row in ipairs(MR._BuildMissingList(ME, FIRSTAID, true, false, false, "char")) do
			seen[row.spellId] = true
		end
		assert.is_true(seen[3275], "the real Vanilla bandage should still be listed")
		assert.is_nil(seen[27032], "Netherweave Bandage is a TBC recipe and cannot be learned on Era")
		assert.is_nil(seen[27033], "Heavy Netherweave Bandage is a TBC recipe and cannot be learned on Era")
	end)
end)

-- The anti-drift guard. Not a behaviour test — a structural one. Every gate
-- already had a behaviour test in one tab or the other before this file
-- existed, and the bug still shipped, because nothing asserted that the two
-- tabs share an implementation. Coverage cannot see this: both copies ran.
describe("the gate has exactly one implementation", function()
	local TABS = { "GUI/BrowserTab.lua", "GUI/MissingRecipesTab.lua" }

	--- Source with comments removed, so prose describing the gate does not
	--- read as a re-inlined copy of it.
	local function code(path)
		local f = assert(io.open(path, "r"), "missing source file: " .. path)
		local body = f:read("*a")
		f:close()
		body = body:gsub("%-%-%[%[.-%]%]", " ")   -- block comments
		body = body:gsub("%-%-[^\n]*", " ")       -- line comments
		return body
	end

	for _, path in ipairs(TABS) do
		it(path .. " calls the shared gate", function()
			assert.is_truthy(code(path):find("RecipeGate:IsValidOnClient", 1, true),
				path .. " no longer routes through addon.RecipeGate — its recipe list "
				.. "can now disagree with every other list in the addon")
		end)
	end

	-- The literals that used to be duplicated. If one of these reappears in a
	-- tab, someone has started a second copy of the rule.
	local FORBIDDEN = {
		["200000"]      = "the Season of Discovery ID floor",
		["30047"]       = "the Crystal Throat Lozenge blacklist entry",
		["27032"]       = "the Netherweave Bandage blacklist entry",
		["27033"]       = "the Heavy Netherweave Bandage blacklist entry",
		["minExpansion"] = "the cross-expansion tag check",
	}

	for _, path in ipairs(TABS) do
		local body
		setup(function() body = code(path) end)
		for needle, what in pairs(FORBIDDEN) do
			it(path .. " does not re-inline " .. what, function()
				assert.is_nil(body:find(needle, 1, true),
					path .. " mentions `" .. needle .. "` in CODE. That belongs to "
					.. "Modules/RecipeGate.lua alone — a second copy is how the First "
					.. "Aid blacklist came to exist in one tab and not the other.")
			end)
		end
	end
end)
