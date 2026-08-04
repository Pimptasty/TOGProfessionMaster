-- Scanner's merge / normalise half — where scanned and received data becomes
-- database state. Every guild-data bug of the last several releases landed
-- here: recipes keyed by the wrong id, crafters who kept their profession
-- forever after dropping it, cross-guild data leaking into the home guild,
-- an un-updated peer flipping a sister crafter's attribution back and forth.
--
-- The addon core is booted for real (real Ace3, real AceDB, real guild-tag
-- hashing), so a tag in these specs is the same FNV-1a value the game computes.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Scanner, HashManager
local HOME, PERSONAL

-- A tag for a guild we are NOT federated with.
local FOREIGN = "ffffff"

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	HashManager = env.loadModule("Modules/HashManager.lua").HashManager
	Scanner     = env.loadModule("Scanner.lua").Scanner
	HOME        = ns:GetCurrentGuildTag()
	PERSONAL    = ns.PersonalTag
end)

before_each(function()
	env.install()
	-- Recipe universe under test. The real shipped DB is version-scoped and
	-- enormous; a small explicit one keeps the "recipe we don't know" gate
	-- assertions exact. Installed through the env so the addon's lazily-built
	-- craftedItemId → spellId index is dropped with it.
	env.setRecipeDB({
		[171] = { [2330] = { name = "Minor Healing Potion", craftedItemId = 118 } },
	})
	Scanner.DS = nil
end)

local function gdbWith(recipes)
	local gdb = env.newGdb()
	gdb.recipes = recipes or {}
	return gdb
end

describe("ExtractTradeSkillId", function()
	before_each(function()
		_G.GetTradeSkillRecipeLink = function(_index) return nil end
		_G.GetTradeSkillItemLink   = function(_index) return nil end
	end)

	it("prefers the recipe link's enchant id — always the spell", function()
		_G.GetTradeSkillRecipeLink = function(_index) return "|cffffd000|Henchant:2330|h[x]|h|r" end
		_G.GetTradeSkillItemLink   = function(_index) return "|cffffffff|Hitem:118|h[x]|h|r" end
		local id, isSpell = Scanner:ExtractTradeSkillId(1)
		assert.equal(2330, id)
		assert.is_true(isSpell)
	end)

	it("reads an enchant id off the item link when there is no recipe link", function()
		_G.GetTradeSkillItemLink = function(_index) return "|cffffd000|Henchant:13937|h[x]|h|r" end
		local id, isSpell = Scanner:ExtractTradeSkillId(1)
		assert.equal(13937, id)
		assert.is_true(isSpell)
	end)

	it("falls back to the crafted item id, flagged as NOT a spell", function()
		_G.GetTradeSkillItemLink = function(_index) return "|cffffffff|Hitem:118|h[x]|h|r" end
		local id, isSpell = Scanner:ExtractTradeSkillId(1)
		assert.equal(118, id)
		assert.is_false(isSpell)
	end)

	it("returns nothing when the client hands back no link at all", function()
		local id, isSpell = Scanner:ExtractTradeSkillId(1)
		assert.is_nil(id)
		assert.is_nil(isSpell)
	end)

	it("copes with the recipe-link API being absent on older clients", function()
		_G.GetTradeSkillRecipeLink = nil
		_G.GetTradeSkillItemLink   = function(_index) return "|cffffffff|Hitem:118|h[x]|h|r" end
		assert.equal(118, Scanner:ExtractTradeSkillId(1))
	end)
end)

describe("MergeRecipesIntoGdb", function()
	it("records the character's rank and cap", function()
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 267, 300, { [2330] = true })
		assert.same({ skillRank = 267, skillMax = 300 }, gdb.skills["Alice-Realm"][171])
	end)

	it("falls the cap back to the RANK, never a hard-coded 300", function()
		-- Hard-coding 300 produced the impossible "375/300" on TBC/Wrath and then
		-- synced that bad value guild-wide.
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 375, nil, {})
		assert.same({ skillRank = 375, skillMax = 375 }, gdb.skills["Alice-Realm"][171])
	end)

	it("treats a missing rank as 0 rather than erroring", function()
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, nil, nil, {})
		assert.same({ skillRank = 0, skillMax = 0 }, gdb.skills["Alice-Realm"][171])
	end)

	it("tags the crafter with the current guild", function()
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true })
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Alice-Realm"])
	end)

	it("tags a guildless character as personal so their own alts still see them", function()
		env.guildName = nil
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true })
		env.guildName = "Testguild"
		assert.equal(PERSONAL, gdb.recipes[171][2330].crafters["Alice-Realm"])
	end)

	it("drops the character from recipes they have unlearned", function()
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true })
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, {})
		assert.is_nil(gdb.recipes[171][2330].crafters["Alice-Realm"])
	end)

	it("leaves OTHER crafters of an unlearned recipe alone", function()
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Bob-Realm", 171, 300, 300, { [2330] = true })
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, {})
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)

	it("reports a change on first scan and NO change on an identical re-scan", function()
		-- WoW fires TRADE_SKILL_UPDATE repeatedly while crafting; a redraw per
		-- event is pure churn, so the caller gates on this return value.
		local gdb = gdbWith()
		assert.is_true(Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true }))
		assert.is_false(Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true }))
	end)

	it("reports a change when a recipe is learned and when one is lost", function()
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true })
		assert.is_true(Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300,
			{ [2330] = true, [2331] = true }))
		assert.is_true(Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true }))
	end)

	it("remaps a crafted-item id onto the spell id the rest of the addon reads", function()
		-- Vanilla / Hardcore scans hand back Hitem:N links; addon.recipeDB is
		-- keyed by spell id universally, so storing the item id would make the
		-- recipe invisible everywhere else.
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [118] = true })
		assert.is_true(gdb.recipes[171][2330] ~= nil)
		assert.is_nil(gdb.recipes[171][118])
	end)

	it("stores an unmappable id as-is rather than dropping the recipe", function()
		local gdb = gdbWith()
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [99999] = true })
		assert.is_true(gdb.recipes[171][99999] ~= nil)
	end)

	it("builds the recipes and skills tables when they are missing", function()
		local gdb = env.newGdb()
		gdb.recipes, gdb.skills = nil, nil
		Scanner:MergeRecipesIntoGdb(gdb, "Alice-Realm", 171, 300, 300, { [2330] = true })
		assert.is_true(gdb.recipes[171][2330] ~= nil)
		assert.is_true(gdb.skills["Alice-Realm"] ~= nil)
	end)
end)

describe("MergeCraftersIntoGdb", function()
	it("ignores a malformed payload", function()
		local gdb = gdbWith()
		assert.is_false(Scanner:MergeCraftersIntoGdb(gdb, 171, "not a table"))
		assert.is_false(Scanner:MergeCraftersIntoGdb(gdb, 171, { [2330] = "not a table" }))
	end)

	it("stores a crafter with the sender's origin tag", function()
		local gdb = gdbWith()
		assert.is_true(Scanner:MergeCraftersIntoGdb(gdb, 171,
			{ [2330] = { ["Bob-Realm"] = true } }, nil, nil, HOME))
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)

	it("reports no change when the peer re-sends what we already hold", function()
		local gdb = gdbWith()
		local payload = { [2330] = { ["Bob-Realm"] = true } }
		Scanner:MergeCraftersIntoGdb(gdb, 171, payload, nil, nil, HOME)
		assert.is_false(Scanner:MergeCraftersIntoGdb(gdb, 171, payload, nil, nil, HOME))
	end)

	it("hides recipes our own addon data doesn't know", function()
		-- The sender may ship newer/SoD content we don't carry; the UI would hide
		-- it anyway, so storing it only bloats the database.
		local gdb = gdbWith()
		Scanner:MergeCraftersIntoGdb(gdb, 171, { [999999] = { ["Bob-Realm"] = true } }, nil, nil, HOME)
		assert.is_nil(gdb.recipes[171][999999])
	end)

	it("accepts everything for a profession we ship no data for", function()
		local gdb = gdbWith()
		Scanner:MergeCraftersIntoGdb(gdb, 202, { [12345] = { ["Bob-Realm"] = true } }, nil, nil, HOME)
		assert.equal(HOME, gdb.recipes[202][12345].crafters["Bob-Realm"])
	end)

	it("remaps an item-keyed crafter set from a Vanilla peer onto the spell id", function()
		local gdb = gdbWith()
		Scanner:MergeCraftersIntoGdb(gdb, 171, { [118] = { ["Bob-Realm"] = true } }, nil, nil, HOME)
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Bob-Realm"])
		assert.is_nil(gdb.recipes[171][118])
	end)

	it("honours an explicitly shipped origin tag over the sender's own", function()
		-- Cross-guild attribution has to survive a relay: the crafter belongs to
		-- the guild the tag says, not to whoever passed the message along.
		local gdb = gdbWith()
		ns:GetGuildTagFor("Horde-Sisterguild", "Horde", "Sisterguild")
		local sister = ns:GuildTagFromKey("Horde-Sisterguild")
		local prev = ns.GetAllowedGuildTagSet
		ns.GetAllowedGuildTagSet = function() return { [PERSONAL] = true, [HOME] = true, [sister] = true } end
		Scanner:MergeCraftersIntoGdb(gdb, 171, { [2330] = { ["Sis-Realm"] = sister } }, nil, nil, HOME)
		ns.GetAllowedGuildTagSet = prev
		assert.equal(sister, gdb.recipes[171][2330].crafters["Sis-Realm"])
	end)

	it("never lets a legacy bare `true` clobber an attribution we already hold", function()
		-- An un-updated guildmate re-broadcasting a relayed sister crafter strips
		-- the tag. Without this guard one old client flips the crafter back to the
		-- home guild, the federation gate purges it, and it churns forever.
		local gdb = gdbWith()
		ns:GetGuildTagFor("Horde-Sisterguild", "Horde", "Sisterguild")
		local sister = ns:GuildTagFromKey("Horde-Sisterguild")
		gdb.recipes[171] = { [2330] = { crafters = { ["Sis-Realm"] = sister } } }
		assert.is_false(Scanner:MergeCraftersIntoGdb(gdb, 171,
			{ [2330] = { ["Sis-Realm"] = true } }, nil, nil, HOME))
		assert.equal(sister, gdb.recipes[171][2330].crafters["Sis-Realm"])
	end)

	it("does let a legacy `true` re-tag a crafter we only hold as personal", function()
		local gdb = gdbWith()
		gdb.recipes[171] = { [2330] = { crafters = { ["Bob-Realm"] = PERSONAL } } }
		Scanner:MergeCraftersIntoGdb(gdb, 171, { [2330] = { ["Bob-Realm"] = true } }, nil, nil, HOME)
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)

	it("drops data for a guild we do not federate with", function()
		local gdb = gdbWith()
		assert.is_false(Scanner:MergeCraftersIntoGdb(gdb, 171,
			{ [2330] = { ["Stranger-Realm"] = FOREIGN } }, nil, nil, HOME))
		assert.is_nil(gdb.recipes[171][2330] and gdb.recipes[171][2330].crafters["Stranger-Realm"])
	end)

	it("skips falsy and non-string crafter keys", function()
		local gdb = gdbWith()
		Scanner:MergeCraftersIntoGdb(gdb, 171,
			{ [2330] = { ["Ghost-Realm"] = false, [42] = true } }, nil, nil, HOME)
		local crafters = gdb.recipes[171][2330].crafters
		assert.is_nil(crafters["Ghost-Realm"])
		assert.is_nil(crafters[42])
	end)

	it("does NOT resurrect a crafter who dropped the profession", function()
		-- We hold their complete authoritative snapshot and it has no Alchemy, so
		-- a stale relay of an old crafters leaf must not re-add them.
		local gdb = gdbWith()
		gdb.skills["Bob-Realm"]   = { [197] = { skillRank = 300, skillMax = 300 } }
		gdb.lastScan["Bob-Realm"] = { professions = 500 }
		assert.is_false(Scanner:MergeCraftersIntoGdb(gdb, 171,
			{ [2330] = { ["Bob-Realm"] = true } }, nil, nil, HOME))
		assert.is_nil(gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)

	it("still accepts a crafter whose snapshot DOES include the profession", function()
		local gdb = gdbWith()
		gdb.skills["Bob-Realm"]   = { [171] = { skillRank = 300, skillMax = 300 } }
		gdb.lastScan["Bob-Realm"] = { professions = 500 }
		assert.is_true(Scanner:MergeCraftersIntoGdb(gdb, 171,
			{ [2330] = { ["Bob-Realm"] = true } }, nil, nil, HOME))
	end)

	it("accepts a crafter we hold NO snapshot for", function()
		-- No snapshot means no evidence they dropped it — absence of data is not
		-- evidence of absence, and blocking here would stall a first sync.
		local gdb = gdbWith()
		assert.is_true(Scanner:MergeCraftersIntoGdb(gdb, 171,
			{ [2330] = { ["Newbie-Realm"] = true } }, nil, nil, HOME))
	end)

	it("clears the sender's own rows first when they claim a fresh scan", function()
		-- Their scan is authoritative for themselves, so a recipe missing from it
		-- is a recipe they unlearned.
		local gdb = gdbWith({ [171] = { [2330] = { crafters = { ["Bob-Realm"] = HOME } } } })
		assert.is_true(Scanner:MergeCraftersIntoGdb(gdb, 171, {}, "Bob-Realm", true, HOME))
		assert.is_nil(gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)

	it("does not clear the sender's rows on a plain relay", function()
		local gdb = gdbWith({ [171] = { [2330] = { crafters = { ["Bob-Realm"] = HOME } } } })
		Scanner:MergeCraftersIntoGdb(gdb, 171, {}, "Bob-Realm", false, HOME)
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)

	it("falls back to our own guild tag for a payload with no origin", function()
		local gdb = gdbWith()
		Scanner:MergeCraftersIntoGdb(gdb, 171, { [2330] = { ["Bob-Realm"] = true } })
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)
end)

describe("ReconcileCraftersAgainstSkills", function()
	it("does nothing without an authoritative snapshot for the owner", function()
		local gdb = gdbWith({ [171] = { [2330] = { crafters = { ["Alice-Realm"] = HOME } } } })
		assert.is_false(Scanner:ReconcileCraftersAgainstSkills(gdb, "Alice-Realm"))
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Alice-Realm"])
	end)

	it("prunes the owner from professions their snapshot no longer lists", function()
		local gdb = gdbWith({ [171] = { [2330] = { crafters = { ["Alice-Realm"] = HOME } } } })
		gdb.skills["Alice-Realm"]   = { [197] = { skillRank = 300, skillMax = 300 } }
		gdb.lastScan["Alice-Realm"] = { professions = 500 }
		assert.is_true(Scanner:ReconcileCraftersAgainstSkills(gdb, "Alice-Realm"))
		assert.is_nil(gdb.recipes[171][2330].crafters["Alice-Realm"])
	end)

	it("keeps professions the snapshot still lists", function()
		local gdb = gdbWith({ [171] = { [2330] = { crafters = { ["Alice-Realm"] = HOME } } } })
		gdb.skills["Alice-Realm"]   = { [171] = { skillRank = 300, skillMax = 300 } }
		gdb.lastScan["Alice-Realm"] = { professions = 500 }
		assert.is_false(Scanner:ReconcileCraftersAgainstSkills(gdb, "Alice-Realm"))
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Alice-Realm"])
	end)

	it("never touches anyone else's rows", function()
		local gdb = gdbWith({ [171] = { [2330] = { crafters = {
			["Alice-Realm"] = HOME, ["Bob-Realm"] = HOME } } } })
		gdb.skills["Alice-Realm"]   = {}
		gdb.lastScan["Alice-Realm"] = { professions = 500 }
		Scanner:ReconcileCraftersAgainstSkills(gdb, "Alice-Realm")
		assert.equal(HOME, gdb.recipes[171][2330].crafters["Bob-Realm"])
	end)

	it("invalidates the profession hash for each profession it pruned", function()
		local gdb = gdbWith({ [171] = { [2330] = { crafters = { ["Alice-Realm"] = HOME } } } })
		gdb.skills["Alice-Realm"]   = {}
		gdb.lastScan["Alice-Realm"] = { professions = 500 }
		Scanner.DS = env.deltaSync()
		Scanner:ReconcileCraftersAgainstSkills(gdb, "Alice-Realm")
		Scanner.DS = nil
		assert.is_true(gdb.hashes["crafters:171"] ~= nil)
	end)

	it("guards against a missing database or owner", function()
		assert.is_false(Scanner:ReconcileCraftersAgainstSkills(nil, "Alice-Realm"))
		assert.is_false(Scanner:ReconcileCraftersAgainstSkills(gdbWith(), nil))
		local noRecipes = env.newGdb()
		noRecipes.recipes = nil
		assert.is_false(Scanner:ReconcileCraftersAgainstSkills(noRecipes, "Alice-Realm"))
	end)
end)

describe("RebuildAltGroups", function()
	it("indexes every member of every claimed alt group", function()
		local gdb = env.newGdb()
		gdb.altClaims["Alice-Realm"] = { "Alice-Realm", "Alt-Realm" }
		Scanner:RebuildAltGroups(gdb)
		assert.equal(gdb.altGroups["Alice-Realm"], gdb.altGroups["Alt-Realm"])
		assert.same({ "Alice-Realm", "Alt-Realm" }, gdb.altGroups["Alice-Realm"])
	end)

	it("replaces the previous index rather than accumulating", function()
		local gdb = env.newGdb()
		gdb.altGroups["Stale-Realm"] = { "Stale-Realm" }
		gdb.altClaims["Alice-Realm"] = { "Alice-Realm" }
		Scanner:RebuildAltGroups(gdb)
		assert.is_nil(gdb.altGroups["Stale-Realm"])
	end)

	it("ignores malformed claims and an absent claim table", function()
		local gdb = env.newGdb()
		gdb.altClaims["Bad-Realm"] = "not a table"
		Scanner:RebuildAltGroups(gdb)
		assert.same({}, gdb.altGroups)

		gdb.altClaims = nil
		Scanner:RebuildAltGroups(gdb)
		assert.same({}, gdb.altGroups)
	end)
end)

describe("ResolveProfessionId", function()
	before_each(function()
		_G.GetProfessions    = function() return nil end
		_G.GetProfessionInfo = function() return nil end
	end)

	it("prefers the character's own profession slots", function()
		_G.GetProfessions    = function() return 1 end
		_G.GetProfessionInfo = function() return "Alchemy", nil, nil, nil, nil, nil, 171 end
		assert.equal(171, Scanner:ResolveProfessionId("Alchemy"))
	end)

	it("falls back to the static name map", function()
		assert.equal(171, Scanner:ResolveProfessionId("Alchemy"))
		assert.equal(333, Scanner:ResolveProfessionId("Enchanting"))
	end)

	it("returns nil for nothing and for an unknown name", function()
		assert.is_nil(Scanner:ResolveProfessionId(nil))
		assert.is_nil(Scanner:ResolveProfessionId("Basket Weaving"))
	end)
end)
