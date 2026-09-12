-- addon:ResolveReagentName and the reagent tables addon:GetRecipeReagents builds.
--
-- Reported in game 2026-09-11: the Professions detail pane for Devilsaur
-- Gauntlets listed "Rugged Leather", "Rune Thread" and **"Item #15417"** --
-- Devilsaur Leather, drawn with its real icon beside the placeholder. The
-- reagent table was built while GetItemInfo was cold for that one item, the
-- placeholder was written into `r.name` for good, and the icon (re-fetched at
-- draw time) was the only part of the row that noticed the cache warming up.
-- The shopping list then persisted that table into SavedVariables, and the
-- [AH] button would have searched for the literal string.
--
-- Three promises, each pinned here: LibItemDB's shipped name is tried before
-- the placeholder, so a name the library knows never renders as a number; a
-- placeholder that DID get written heals the next time it is resolved; and the
-- client's own (localized) name still wins whenever the cache has it.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local PROF, SPELL = 165, 23799            -- Leatherworking, Devilsaur Gauntlets
local DEVILSAUR, RUGGED = 15417, 8170
local LINK = "|cffffffff|Hitem:15417::::::::60:::::|h[Devilsaur Leather]|h|r"

local ns, savedIdb

setup(function()
	ns = env.initDb()
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	savedIdb = ns._itemDB
	ns._itemDB = false                    -- no LibItemDB unless a case installs one
	env.setRecipeDB({
		[PROF] = { [SPELL] = { name = "Devilsaur Gauntlets",
		                       reagents = { [DEVILSAUR] = 8, [RUGGED] = 30 } } },
	})
end)

after_each(function()
	ns._itemDB = savedIdb
end)

local function itemDB(names)
	return {
		GetName = function(_, id) return names[id] end,
		GetLink = function(_, id) return names[id] and ("|Hitem:" .. id .. "|h[" .. names[id] .. "]|h") or nil end,
	}
end

local function reagent(list, id)
	for _, r in ipairs(list) do
		if r.itemId == id then return r end
	end
	error("reagent " .. id .. " not in list")
end

describe("GetRecipeReagents with a cold item cache", function()
	it("takes the name from LibItemDB rather than writing a placeholder", function()
		ns._itemDB = itemDB({ [DEVILSAUR] = "Devilsaur Leather", [RUGGED] = "Rugged Leather" })
		local list = ns:GetRecipeReagents(PROF, SPELL)
		assert.equal("Devilsaur Leather", reagent(list, DEVILSAUR).name)
		assert.equal("Rugged Leather",    reagent(list, RUGGED).name)
	end)

	it("takes the link from LibItemDB too, so the row is clickable before the cache warms", function()
		ns._itemDB = itemDB({ [DEVILSAUR] = "Devilsaur Leather" })
		local r = reagent(ns:GetRecipeReagents(PROF, SPELL), DEVILSAUR)
		assert.is_truthy(r.itemLink)
		assert.is_truthy(r.itemLink:find("|Hitem:15417|h", 1, true))
	end)

	it("falls back to the placeholder only when neither source knows the item", function()
		local r = reagent(ns:GetRecipeReagents(PROF, SPELL), DEVILSAUR)
		assert.equal("Item #15417", r.name)
		assert.is_nil(r.itemLink)
	end)

	it("falls back to the placeholder when LibItemDB is present but has no entry", function()
		ns._itemDB = itemDB({})
		assert.equal("Item #15417", reagent(ns:GetRecipeReagents(PROF, SPELL), DEVILSAUR).name)
	end)
end)

describe("ResolveReagentName on a table built cold", function()
	it("heals a placeholder once the client cache has the item, and writes it back", function()
		local r = reagent(ns:GetRecipeReagents(PROF, SPELL), DEVILSAUR)
		assert.equal("Item #15417", r.name)   -- built cold, as in the report

		env.wow.items[DEVILSAUR] = { name = "Devilsaur Leather", link = LINK }
		assert.equal("Devilsaur Leather", ns:ResolveReagentName(r))
		-- Written back: every consumer that reads r.name after this draw --
		-- the [AH] search, the bank dialog, the shopping-list SavedVariable --
		-- sees the real name, not the placeholder it was built with.
		assert.equal("Devilsaur Leather", r.name)
		assert.equal(LINK, r.itemLink)
	end)

	it("heals a placeholder from LibItemDB when the client cache is still cold", function()
		local r = reagent(ns:GetRecipeReagents(PROF, SPELL), DEVILSAUR)
		assert.equal("Item #15417", r.name)
		ns._itemDB = itemDB({ [DEVILSAUR] = "Devilsaur Leather" })
		assert.equal("Devilsaur Leather", ns:ResolveReagentName(r))
		assert.equal("Devilsaur Leather", r.name)
	end)

	it("stays a placeholder while nothing can resolve it, without erroring", function()
		local r = reagent(ns:GetRecipeReagents(PROF, SPELL), DEVILSAUR)
		assert.equal("Item #15417", ns:ResolveReagentName(r))
	end)
end)

describe("ResolveReagentName precedence", function()
	it("prefers the client's name over LibItemDB's when both answer", function()
		-- The client's is localized; LibItemDB's is the shipped-locale name.
		env.wow.items[DEVILSAUR] = { name = "Cuir de diablosaure", link = LINK }
		ns._itemDB = itemDB({ [DEVILSAUR] = "Devilsaur Leather" })
		assert.equal("Cuir de diablosaure", reagent(ns:GetRecipeReagents(PROF, SPELL), DEVILSAUR).name)
	end)

	it("never re-resolves a real name, even with a cold cache", function()
		local r = { itemId = DEVILSAUR, count = 8, name = "Devilsaur Leather" }
		assert.equal("Devilsaur Leather", ns:ResolveReagentName(r))
		assert.equal("Devilsaur Leather", r.name)
	end)

	it("keeps an existing link rather than replacing it with LibItemDB's", function()
		ns._itemDB = itemDB({ [DEVILSAUR] = "Devilsaur Leather" })
		local r = { itemId = DEVILSAUR, count = 8, name = "Item #15417", itemLink = LINK }
		ns:ResolveReagentName(r)
		assert.equal(LINK, r.itemLink)
	end)

	it("returns what it can for a reagent with no item id", function()
		assert.equal("",        ns:ResolveReagentName({ count = 1 }))
		assert.equal("Thread",  ns:ResolveReagentName({ count = 1, name = "Thread" }))
		assert.equal("",        ns:ResolveReagentName(nil))
	end)
end)
