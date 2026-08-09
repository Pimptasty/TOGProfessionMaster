-- TOG Profession Master — Recipe client-validity gate
--
-- THE single implementation of "can this recipe exist on the running client?".
-- Every list that shows recipes calls this and nothing else re-implements it.
--
-- Why this file exists. The chain used to be written out twice — once in
-- GUI/BrowserTab.lua and once in GUI/MissingRecipesTab.lua — with a comment in
-- the Browser copy saying "pull the rules in here so the Browser tab agrees
-- with it". Two copies of one rule drift, and they did: the First Aid blacklist
-- (Netherweave / Heavy Netherweave Bandage, TBC recipes that survive every
-- generic Era gate) reached only the Browser, so both bandages showed as
-- "missing" on a Classic Era character. The TBC phase gate had drifted the
-- other way — Missing Recipes had it, the Browser did not. There is now one
-- copy and no way for a caller to apply a subset.
--
-- Structure matters as much as content: every check is an INDEPENDENT early
-- return, never an `elseif` chain. The old Missing Recipes version was a chain,
-- and its untagged-`spellId > 25000` branch could evaluate true without setting
-- `skip` — which short-circuited the branches below it and silently bypassed
-- the season, requiredSkill and phase gates. That failure mode is not
-- expressible here.
--
-- SCOPE. This answers "is this recipe real on this client", nothing else.
-- Per-character context — already known, rank-book consumed, spec can't learn
-- it, "can learn now" — stays in the calling tab, because it depends on which
-- character is being viewed and not on the client.

local _, addon = ...

local RecipeGate = {}
addon.RecipeGate = RecipeGate

-- Recipes at or above this ID on a Vanilla client are Season of Discovery /
-- Anniversary additions carried by the 1.15 client's shared tables. Every SoD
-- formula observed is 400k+; real Vanilla recipes are under ~30k.
local SOD_RECIPE_ID_MIN = 200000

-- Above this ID on a Vanilla client, an UNTAGGED recipe (no minExpansion) is
-- assumed post-Vanilla unless both its spell and its item resolve on the client.
local ERA_UNTAGGED_ID_MIN = 25000

-- Recipes that exist in the 1.15 client's spell tables — so they survive the
-- generic "does the spell resolve" gate — but cannot be learned on Era or
-- Anniversary. Keyed by profession, because the IDs are only wrong in context.
local ERA_BLACKLIST = {
	[185] = {                    -- Cooking
		[30047] = true,          -- Crystal Throat Lozenge (TBC)
	},
	[129] = {                    -- First Aid
		[27032] = true,          -- Netherweave Bandage (TBC)
		[27033] = true,          -- Heavy Netherweave Bandage (TBC)
	},
}

--- Expansion index (1=Vanilla … 5=MoP) and profession skill cap for the running
--- client. Unknown/newer clients fall through to the highest known profile
--- rather than hiding everything.
function RecipeGate:Client()
	if     addon.isVanilla then return 1, 300
	elseif addon.isTBC     then return 2, 375
	elseif addon.isWrath   then return 3, 450
	elseif addon.isCata    then return 4, 525
	elseif addon.isMoP     then return 5, 600
	end
	return 5, 600
end

--- TBC content-phase ceiling, or nil when the filter does not apply.
--- Only TBC ships `phase` tags, and the user sets the live phase in Settings.
local function tbcPhaseLimit()
	local Ace = addon.lib
	if addon.isTBC and Ace and Ace.db and Ace.db.profile then
		return Ace.db.profile.tbcAnniversaryPhase or 2
	end
	return nil
end

--- Recipes AllTheThings files under "Never Implemented" — present in the
--- client's spell tables but never obtainable by any means, in any expansion.
--- Feature-detected: LibProfessionDB gained IsHiddenRecipe in MINOR 9, and an
--- older ProfessionDB simply leaves this check inert rather than erroring.
local function isNeverImplemented(recipeId)
	local pdb = LibStub and LibStub("LibProfessionDB-1.0", true)
	return pdb and pdb.IsHiddenRecipe and pdb:IsHiddenRecipe(recipeId) or false
end

--- Is `recipeId` valid on the running client?
---
--- @param profId   number  profession id (the blacklists are per-profession)
--- @param recipeId number  recipe spell id
--- @param meta     table   the recipe's row from the recipe DB
--- @return boolean ok, string|nil reason  -- reason names the gate that rejected
function RecipeGate:IsValidOnClient(profId, recipeId, meta)
	if not meta then return false, "nometa" end

	local clientExp, clientMaxSkill = self:Client()
	-- Era means "a Vanilla client that is not running Season of Discovery".
	-- IsSoD() only ever RELAXES these gates; this addon does not support SoD.
	local isEra = (clientExp == 1) and not addon:IsSoD()

	if isEra and recipeId >= SOD_RECIPE_ID_MIN then
		return false, "sod"
	end
	if meta.minExpansion and meta.minExpansion > clientExp then
		return false, "minExpansion"
	end
	if isEra and GetSpellInfo and not GetSpellInfo(recipeId) then
		return false, "nospell"
	end
	if isEra then
		local byProf = ERA_BLACKLIST[profId]
		if byProf and byProf[recipeId] then return false, "blacklist" end
	end
	if isEra and (not meta.minExpansion) and recipeId > ERA_UNTAGGED_ID_MIN then
		-- Untagged high-ID recipe on Era: require BOTH the spell and an item to
		-- resolve. TBC recipes such as Crystal Throat Lozenge carry items in the
		-- shared 1.15 tables while having no spell on an Era client.
		local spellExists = GetSpellInfo and GetSpellInfo(recipeId) ~= nil
		local itemExists  = GetItemInfoInstant and (
			(meta.itemId        and GetItemInfoInstant(meta.itemId)) or
			(meta.craftedItemId and GetItemInfoInstant(meta.craftedItemId)))
		if not (spellExists and itemExists) then return false, "untagged" end
	end
	if meta.requiredSkill and meta.requiredSkill > clientMaxSkill then
		return false, "skillcap"
	end
	local phaseLimit = tbcPhaseLimit()
	if phaseLimit and meta.phase and meta.phase > phaseLimit then
		return false, "phase"
	end
	if meta.season then
		return false, "season"
	end
	if isNeverImplemented(recipeId) then
		return false, "nyi"
	end
	return true, nil
end
