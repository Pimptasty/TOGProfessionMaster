-- TOG Profession Master — Profession & Cooldown Scanner
-- Author: Pimptasty
--
-- Responsibilities:
--   • Listen for trade-skill / craft window events and scan the open profession.
--   • Scan all known profession cooldown spells on login and on window events.
--   • Store results in AceDB (factionrealm scope, keyed by "Name-Realm").
--   • Broadcast own data to the guild via DeltaSync-1.0.
--   • Receive and merge incoming guild-member data back into AceDB.

local _, addon = ...
local Ace = addon.lib   -- the AceAddon object created in TOGProfessionMaster.lua

-- ---------------------------------------------------------------------------
-- Module object
-- ---------------------------------------------------------------------------

local Scanner = {}
addon.Scanner = Scanner

-- Broadcast state
Scanner._pendingBroadcast = false
Scanner._lastBroadcastAt  = 0
Scanner._broadcastSeconds = 30       -- hard minimum between guild broadcasts (seconds)

-- DeltaSync instance (assigned in InitDeltaSync)
Scanner.DS = nil

-- ---------------------------------------------------------------------------
-- English profession name → skill line ID
-- Used as a fallback for linked professions that aren't in GetProfessions().
-- Game-data facts; locale-specific servers share the same IDs but may have
-- different string keys.  Additional locale strings can be appended without
-- affecting logic.
-- ---------------------------------------------------------------------------

local PROF_NAME_TO_ID = {
    ["Alchemy"]        = 171,
    ["Blacksmithing"]  = 164,
    ["Cooking"]        = 185,
    ["Enchanting"]     = 333,
    ["Engineering"]    = 202,
    ["Fishing"]        = 356,
    ["Herbalism"]      = 182,
    ["Inscription"]    = 773,
    ["Jewelcrafting"]  = 755,
    ["Leatherworking"] = 165,
    ["Mining"]         = 186,
    ["Skinning"]       = 393,
    ["Tailoring"]      = 197,
}

-- Known specialisation spells per profession (TBC+).
-- { [profId] = { spellId, ... } } — first match wins.
local SPEC_SPELLS = {
    [171] = { 28677, 28682, 28683 },   -- Alchemy: Potionmaster, Elixir, Transmutation
    [202] = { 20219, 20222 },          -- Engineering: Gnomish, Goblin
    [197] = { 26797, 26801, 26802 },   -- Tailoring: Mooncloth, Shadoweave, Spellfire
}

-- ---------------------------------------------------------------------------
-- DeltaSync initialisation
-- Called on PLAYER_ENTERING_WORLD (initial login or UI reload only).
-- ---------------------------------------------------------------------------

function Scanner:InitDeltaSync()
    local DS = LibStub("DeltaSync-1.0", true)
    if not DS then
        addon:DebugPrint("Scanner: DeltaSync-1.0 not found — guild sync disabled")
        return
    end

    DS:Initialize({
        namespace = "TOGPmv1",

        -- A guild member is asking for our full data set.
        onDataRequest = function(sender, _baseline)
            Scanner:SendDataTo(sender)
        end,

        -- Incoming guild-member data (full payload or delta).
        onDataReceived = function(sender, data)
            Scanner:OnGuildDataReceived(sender, data)
        end,

        -- Another member broadcast their version token; we can request data
        -- if we have no record for them yet (or their data is older than 1 week).
        onVersionReceived = function(sender, _version, _hash)
            local gdb  = addon:GetGuildDb()
            local norm = DS:NormalizeName(sender)
            if norm and gdb and not (gdb.guildData and gdb.guildData[norm]) then
                DS:RequestData(sender)
            end
        end,
    })

    self.DS = DS
    addon:DebugPrint("Scanner: DeltaSync initialized for", DS.namespace)
end

-- ---------------------------------------------------------------------------
-- Event wiring — hooked into the Ace lifecycle via hooksecurefunc
-- ---------------------------------------------------------------------------

function Scanner:Init()
    -- Trade skill window (TBC+/Wrath/Cata/MoP — most professions)
    Ace:RegisterEvent("TRADE_SKILL_SHOW",   function() Scanner:OnTradeSkillEvent() end)
    Ace:RegisterEvent("TRADE_SKILL_UPDATE", function() Scanner:OnTradeSkillEvent() end)

    -- Craft window (Vanilla enchanting and weapon crafting)
    Ace:RegisterEvent("CRAFT_SHOW",   function() Scanner:OnCraftEvent() end)
    Ace:RegisterEvent("CRAFT_UPDATE", function() Scanner:OnCraftEvent() end)

    -- Item-based cooldowns (Salt Shaker in Vanilla leatherworking)
    Ace:RegisterEvent("BAG_UPDATE_COOLDOWN", function() Scanner:OnBagCooldownEvent() end)

    -- Scan cooldowns on login after the server is ready
    Ace:ScheduleTimer(function()
        Scanner:ScanCooldowns()
        Scanner:ScheduleBroadcast()
    end, 2)

    addon:DebugPrint("Scanner: Init complete")
end

-- Hook into Ace OnEnable so Init() runs after AceDB is ready.
hooksecurefunc(Ace, "OnEnable", function(_self)
    Scanner:Init()
end)

-- Hook into OnPlayerEnteringWorld to initialise DeltaSync once per session.
hooksecurefunc(Ace, "OnPlayerEnteringWorld", function(_self, _event, isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        Scanner:InitDeltaSync()
    end
end)

-- Override the ForceSync stub from the main file.
function addon:ForceSync()
    Scanner:ScanCooldowns()
    Scanner._lastBroadcastAt = 0   -- bypass debounce
    Scanner:BroadcastOwnData()
    addon:Print("Force sync sent.")
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

function Scanner:OnTradeSkillEvent()
    if UnitAffectingCombat("player") then return end

    local isLinked, linkedPlayer = IsTradeSkillLinked()
    if isLinked then
        -- Only store linked data if the player is a guildmate.
        if linkedPlayer and self.DS then
            local normKey = self.DS:NormalizeName(linkedPlayer)
            if normKey and self.DS:IsInGuild(normKey) then
                self:ScanTradeSkillInto(normKey, true)
            end
        end
        return
    end

    local charKey = addon:GetCharacterKey()
    if not addon:GetGuildKey() then return end
    self:ScanTradeSkillInto(charKey, false)
    self:ScanCooldowns()
    self:ScheduleBroadcast()
end

function Scanner:OnCraftEvent()
    if UnitAffectingCombat("player") then return end

    local charKey = addon:GetCharacterKey()
    if not addon:GetGuildKey() then return end
    self:ScanCraftSkillInto(charKey)
    self:ScanCooldowns()
    self:ScheduleBroadcast()
end

function Scanner:OnBagCooldownEvent()
    if not addon.isVanilla then return end
    self:ScanCooldowns()
    self:ScheduleBroadcast()
end

-- ---------------------------------------------------------------------------
-- Profession scanning — TradeSkill frame
-- ---------------------------------------------------------------------------

--- Build a name → spellId lookup from the player's spellbook.
-- GetSpellInfo() does not return spellID on Classic Era clients (that return
-- value was added in retail patch 7.1).  GetSpellBookItemInfo() always returns
-- the spellID as its 2nd value and works on all Classic builds.
-- Only covers spells the local player knows; linked scans get spellId = nil.
function Scanner:BuildSpellNameCache()
    local cache = {}
    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for j = 1, numSpells do
            local idx = offset + j
            local _, spellId = GetSpellBookItemInfo(idx, "spell")
            if spellId then
                local spellName = GetSpellInfo(spellId)
                if spellName then
                    cache[spellName] = spellId
                end
            end
        end
    end
    return cache
end

--- Scan the currently open trade-skill window and store the result in AceDB.
-- @param charKey   "Name-Realm" string for the character being scanned
-- @param isLinked  true when viewing another player's linked trade skill
function Scanner:ScanTradeSkillInto(charKey, isLinked)  --luacheck: ignore isLinked
    local skillName, _, skillRank, skillMax = GetTradeSkillLine()
    if not skillName or skillName == "UNKNOWN" then return end

    local profId = self:ResolveProfessionId(skillName)
    if not profId then
        addon:DebugPrint("Scanner: unrecognised profession name:", skillName)
        return
    end

    -- Build name → spellId map from local spellbook once per scan.
    -- Works for local scans; linked profession scans leave spellId nil.
    local spellNameCache = (not isLinked) and self:BuildSpellNameCache() or {}

    -- Collect all recipe spell IDs.  Only include rows with a real difficulty
    -- rating; "header" separators and any other non-recipe rows are skipped.
    local recipes = {}
    local total   = GetNumTradeSkills()
    for i = 1, total do
        local recipeName, tradeSkillType = GetTradeSkillInfo(i)
        if tradeSkillType == "optimal" or tradeSkillType == "medium"
        or tradeSkillType == "easy"    or tradeSkillType == "trivial" then
            local recipeId, isSpell = self:ExtractTradeSkillId(i)
            if recipeId then
                -- [1]=name [2]=icon [3]=isSpell [4]=spellId [5]=recipeLink [6]=itemLink [7]=reagents
                local spellId    = spellNameCache[recipeName]
                local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
                local itemLink   = GetTradeSkillItemLink(i)
                -- Capture reagents while the trade skill window is open.
                local reagents = {}
                local numReagents = GetTradeSkillNumReagents(i) or 0
                for r = 1, numReagents do
                    local rName, _, rCount = GetTradeSkillReagentInfo(i, r)
                    if rName then
                        table.insert(reagents, { name = rName, count = rCount or 1 })
                    end
                end
                recipes[recipeId] = { recipeName, GetTradeSkillIcon(i), isSpell, spellId, recipeLink, itemLink, reagents }
            end
        end
    end

    local gdb = addon:GetGuildDb()
    if not gdb then return end
    self:MergeRecipesIntoGdb(gdb, charKey, profId, skillRank, skillMax, recipes)

    -- Spec detection is own-character only and only available from TBC onwards.
    if not isLinked and not addon.isVanilla then
        self:DetectSpecializations(charKey)
    end

    addon:DebugPrint("Scanner: scanned", skillName, "for", charKey,
        "—", (function() local n = 0; for _ in pairs(recipes) do n = n + 1 end; return n end)(), "recipes")
end

--- Merge a scanned recipe table into the recipe-centric guild DB.
-- Stores recipe metadata once; adds charKey to each recipe's crafters set.
-- Removes charKey from recipes for this prof that are no longer known.
function Scanner:MergeRecipesIntoGdb(gdb, charKey, profId, skillRank, skillMax, recipes)
    -- Ensure new-structure fields exist (backwards-compat for old saved vars).
    if not gdb.recipes   then gdb.recipes   = {} end
    if not gdb.skills    then gdb.skills    = {} end
    if not gdb.guildData then gdb.guildData = {} end

    -- Mark member as known (membership index only).
    gdb.guildData[charKey] = gdb.guildData[charKey] or {}

    -- Update skill rank/max.
    if not gdb.skills[charKey] then gdb.skills[charKey] = {} end
    gdb.skills[charKey][profId] = { skillRank = skillRank or 0, skillMax = skillMax or 300 }

    -- Remove charKey from any existing recipe crafters for this prof
    -- (covers recipes they may have unlearned).
    if gdb.recipes[profId] then
        for _, rd in pairs(gdb.recipes[profId]) do
            if rd.crafters then rd.crafters[charKey] = nil end
        end
    else
        gdb.recipes[profId] = {}
    end

    -- Add/update recipe entries.
    for recipeId, rd in pairs(recipes) do
        local existing = gdb.recipes[profId][recipeId]
        if existing then
            existing.name    = rd[1]
            existing.icon    = rd[2]
            existing.isSpell = rd[3]
            -- [4]=spellId, [5]=recipeLink, [6]=itemLink — only present from local scans
            -- (wire data only carries [1]-[4]); only overwrite when non-nil.
            if rd[4] ~= nil then existing.spellId    = rd[4] end
            if rd[5] ~= nil then existing.recipeLink = rd[5] end
            if rd[6] ~= nil then existing.itemLink   = rd[6] end
            if rd[7] ~= nil then existing.reagents   = rd[7] end
            existing.crafters[charKey] = true
        else
            gdb.recipes[profId][recipeId] = {
                name       = rd[1],
                icon       = rd[2],
                isSpell    = rd[3],
                spellId    = rd[4],
                recipeLink = rd[5],
                itemLink   = rd[6],
                reagents   = rd[7],
                crafters   = { [charKey] = true },
            }
        end
    end
end

--- Extract a numeric recipe key from a trade-skill row.
-- Returns id, isSpell where isSpell=true means id is a spell/enchant ID,
-- false means id is the crafted item ID.
function Scanner:ExtractTradeSkillId(index)
    -- Retail / modern Classic: recipe link always has enchant:SPELLID.
    local link = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(index)
    if link then
        local id = tonumber(link:match("enchant:(%d+)"))
        if id then return id, true end
    end
    -- Classic Era: GetTradeSkillItemLink returns enchant:SPELLID for Enchanting,
    -- or item:ITEMID (the crafted product) for all other professions.
    link = GetTradeSkillItemLink(index)
    if link then
        local id = tonumber(link:match("enchant:(%d+)"))
        if id then return id, true end
        id = tonumber(link:match("item:(%d+)"))
        if id then return id, false end
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Profession scanning — Craft frame (Vanilla enchanting / weapon crafting)
-- ---------------------------------------------------------------------------

function Scanner:ScanCraftSkillInto(charKey)
    if not GetCraftDisplaySkillLine then return end

    local skillName = GetCraftDisplaySkillLine()
    if not skillName then return end

    local profId = self:ResolveProfessionId(skillName)
    if not profId then
        addon:DebugPrint("Scanner: unrecognised craft skill:", skillName)
        return
    end

    local recipes = {}
    local total   = GetNumCrafts and GetNumCrafts() or 0
    for i = 1, total do
        local craftName, _, craftType = GetCraftInfo(i)
        if craftType == "optimal" or craftType == "medium"
        or craftType == "easy"    or craftType == "trivial" then
            local link    = GetCraftItemLink and GetCraftItemLink(i)
            local spellId = link and tonumber(link:match("enchant:(%d+)"))
            if spellId then
                local craftIcon = GetCraftIcon and GetCraftIcon(i)
                recipes[spellId] = { craftName, craftIcon }
            end
        end
    end

    local gdb = addon:GetGuildDb()
    if not gdb then return end
    self:MergeRecipesIntoGdb(gdb, charKey, profId, 0, 300, recipes)

    addon:DebugPrint("Scanner: scanned craft", skillName, "for", charKey,
        "—", (function() local n = 0; for _ in pairs(recipes) do n = n + 1 end; return n end)(), "recipes")
end

-- ---------------------------------------------------------------------------
-- Profession ID resolution
-- Primary path: match the open window's name against GetProfessions() entries.
-- Fallback: static English name map (covers linked professions and all locales
-- where the skill name happens to match the English key).
-- ---------------------------------------------------------------------------

function Scanner:ResolveProfessionId(name)
    if not name then return nil end

    -- Walk the character's own profession slots first.
    local slots = { GetProfessions() }
    for _, idx in ipairs(slots) do
        if idx then
            local pName, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if pName == name then
                return skillLine
            end
        end
    end

    -- Fall back to the static English map.
    return PROF_NAME_TO_ID[name]
end

-- ---------------------------------------------------------------------------
-- Specialisation detection (TBC+, own character only)
-- ---------------------------------------------------------------------------

function Scanner:DetectSpecializations(charKey)
    local gdb = addon:GetGuildDb()
    if not gdb then return end
    local specs = {}
    for profId, spellList in pairs(SPEC_SPELLS) do
        for _, spellId in ipairs(spellList) do
            if IsSpellKnown(spellId, false) then
                specs[profId] = spellId
                break
            end
        end
    end
    gdb.specializations[charKey] = specs
    addon:DebugPrint("Scanner: specs for", charKey, "—",
        (function() local n = 0; for _ in pairs(specs) do n = n + 1 end; return n end)())
end

-- ---------------------------------------------------------------------------
-- Cooldown scanning
-- ---------------------------------------------------------------------------

function Scanner:ScanCooldowns()
    local charKey = addon:GetCharacterKey()
    local gdb     = addon:GetGuildDb()
    if not gdb then return end
    local now     = GetServerTime()
    local data    = addon:GetCooldownData()

    if not gdb.cooldowns[charKey] then gdb.cooldowns[charKey] = {} end
    local stored = gdb.cooldowns[charKey]

    -- ---- Transmutes --------------------------------------------------------
    -- All transmutes share one cooldown bucket.  Find the active expiry by
    -- querying every spell until we find one that is on CD, then stamp every
    -- *known* transmute with that same expiry.

    local transmuteExpiry = nil
    for spellId in pairs(data.transmutes) do
        local start, duration = GetSpellCooldown(spellId)
        if start and start > 0 and duration and duration > 1.5 then
            local remaining = (start + duration) - GetTime()
            if remaining > 0 and remaining < 691200 then
                transmuteExpiry = math.floor(now + remaining)
                break
            end
        end
    end

    for spellId in pairs(data.transmutes) do
        if IsSpellKnown(spellId, false) then
            if transmuteExpiry then
                stored[spellId] = transmuteExpiry
            elseif not stored[spellId] or (stored[spellId] - now) > 691200 then
                stored[spellId] = now - 1  -- Ready
            end
        end
    end

    -- ---- Non-transmute cooldowns -------------------------------------------

    for spellId in pairs(data.cooldowns) do
        local start, duration = GetSpellCooldown(spellId)
        if start and start > 0 and duration and duration > 1.5 then
            local remaining = (start + duration) - GetTime()
            if remaining > 0 and remaining < 2592000 then
                stored[spellId] = math.floor(now + remaining)
            end
            -- If remaining <= 0 the GCD fired; leave the existing stored entry alone
            -- so "Ready" state (past timestamp) is preserved.
        else
            -- Spell is not on CD.  Seed "Ready" if the character knows it.
            if not stored[spellId] or (stored[spellId] - now) > 2592000 then
                if IsSpellKnown(spellId, false) then
                    stored[spellId] = now - 1  -- past timestamp means Ready
                end
            end
        end
    end

    -- ---- Salt Shaker (Vanilla Leatherworking item) -------------------------

    if addon.isVanilla then
        self:ScanSaltShaker(stored, now, data.saltShakerItem)
    end

    gdb.syncTimes[charKey] = now
    addon:DebugPrint("Scanner: cooldown scan complete for", charKey)
end

function Scanner:ScanSaltShaker(stored, now, itemId)
    local start, duration

    -- Try C_Container first (Cata+), then legacy GetItemCooldown
    if C_Container and C_Container.GetItemCooldown then
        start, duration = C_Container.GetItemCooldown(itemId)
    elseif GetItemCooldown then
        start, duration = GetItemCooldown(itemId)
    end

    if start and start > 0 and duration and duration > 1.5 then
        local remaining = (start + duration) - GetTime()
        if remaining > 0 then
            stored[itemId] = math.floor(now + remaining)
            return
        end
    end

    -- Seed Ready entry if the player carries the Salt Shaker.
    if not stored[itemId] then
        local count = GetItemCount and GetItemCount(itemId, true) or 0
        if count > 0 then
            stored[itemId] = now - 1
        end
    end
end

-- ---------------------------------------------------------------------------
-- Broadcast helpers
-- ---------------------------------------------------------------------------

--- Schedule a debounced broadcast (0.5 s coalesce window).
function Scanner:ScheduleBroadcast()
    if self._pendingBroadcast then return end
    self._pendingBroadcast = true
    Ace:ScheduleTimer(function()
        self._pendingBroadcast = false
        self:BroadcastOwnData()
    end, 0.5)
end

--- Build and broadcast the local player's full record to the guild.
-- Suppressed if a broadcast was sent less than _broadcastSeconds ago.
function Scanner:BroadcastOwnData()
    local DS = self.DS
    if not DS then return end

    local now = GetServerTime()
    if (now - self._lastBroadcastAt) < self._broadcastSeconds then
        addon:DebugPrint("Scanner: broadcast suppressed (debounce)")
        return
    end

    local payload = self:BuildPayload()
    DS:BroadcastData(payload)
    self._lastBroadcastAt = now
    addon:DebugPrint("Scanner: broadcast sent for", payload.charKey)
    if addon.callbacks then
        addon.callbacks:Fire("SYNC_SENT", "guild", 0)
    end
end

--- Send our full data directly to a single player (response to onDataRequest).
function Scanner:SendDataTo(target)
    local DS = self.DS
    if not DS then return end
    DS:SendData(target, self:BuildPayload(), false)
    if addon.callbacks then
        addon.callbacks:Fire("SYNC_SENT", target, 0)
    end
end

--- Assemble the wire payload from AceDB.
-- Cooldowns are expressed as relative seconds-remaining (0 = Ready).
function Scanner:BuildPayload()
    local charKey  = addon:GetCharacterKey()
    local guildKey = addon:GetGuildKey()
    local gdb      = addon:GetGuildDb()
    local now      = GetServerTime()

    if not gdb then
        return { charKey = charKey, guildKey = guildKey, professions = {},
                 cooldowns = {}, specializations = {}, timestamp = now }
    end

    -- Convert stored absolute expiry → relative seconds for the wire.
    local cdPayload = {}
    for spellId, expiresAt in pairs(gdb.cooldowns[charKey] or {}) do
        local remaining = expiresAt - now
        cdPayload[spellId] = remaining > 0 and remaining or 0
    end

    -- Reconstruct per-char professions from the inverted recipe index.
    local professions = {}
    if gdb.recipes then
        for profId, profRecipes in pairs(gdb.recipes) do
            local myRecipes = {}
            for recipeId, rd in pairs(profRecipes) do
                if rd.crafters and rd.crafters[charKey] then
                    -- Wire format: [1]=name [2]=icon [3]=isSpell [4]=spellId
                    myRecipes[recipeId] = { rd.name, rd.icon, rd.isSpell, rd.spellId }
                end
            end
            if next(myRecipes) then
                local skill = gdb.skills and gdb.skills[charKey] and gdb.skills[charKey][profId] or {}
                professions[profId] = {
                    skillRank = skill.skillRank or 0,
                    skillMax  = skill.skillMax  or 300,
                    recipes   = myRecipes,
                }
            end
        end
    end

    return {
        charKey         = charKey,
        guildKey        = guildKey,
        professions     = professions,
        cooldowns       = cdPayload,
        specializations = gdb.specializations[charKey] or {},
        timestamp       = now,
    }
end

-- ---------------------------------------------------------------------------
-- Receive & merge guild data
-- ---------------------------------------------------------------------------

--- Called by DeltaSync when a guild member's data arrives.
-- @param sender  normalised "Name-Realm" string from DeltaSync
-- @param data    table as built by BuildPayload() on the sender's machine
function Scanner:OnGuildDataReceived(sender, data)
    if not data or type(data) ~= "table" then
        addon:DebugPrint("Scanner: malformed data from", sender)
        return
    end

    local charKey  = data.charKey
    local guildKey = data.guildKey
    if not charKey  or type(charKey)  ~= "string" then return end
    if not guildKey or type(guildKey) ~= "string" then return end

    -- Ignore echoes of our own broadcast.
    if charKey == addon:GetCharacterKey() then return end

    -- Resolve (and lazily create) the guild-scoped storage bucket.
    -- We use the sender's composite guildKey directly so data is always stored
    -- under the guild it came from, even if the receiver is temporarily guildless.
    local g = Ace.db.global.guilds
    if not g[guildKey] then
        g[guildKey] = {
            recipes = {}, skills = {}, guildData = {}, cooldowns = {},
            syncTimes = {}, specializations = {}, factions = {},
        }
    end
    local gdb = g[guildKey]
    -- Lazy-init new fields for buckets created before this version.
    if not gdb.recipes then gdb.recipes = {} end
    if not gdb.skills  then gdb.skills  = {} end
    local now = GetServerTime()

    -- Merge profession records into the recipe-centric index.
    if type(data.professions) == "table" then
        for profId, profInfo in pairs(data.professions) do
            if type(profInfo) == "table" then
                local wireRecipes = type(profInfo.recipes) == "table" and profInfo.recipes or {}
                self:MergeRecipesIntoGdb(gdb, charKey, profId,
                    profInfo.skillRank, profInfo.skillMax, wireRecipes)
            end
        end
    end

    -- Merge cooldowns: convert relative seconds → absolute server timestamp.
    if type(data.cooldowns) == "table" then
        if not gdb.cooldowns[charKey] then gdb.cooldowns[charKey] = {} end
        for spellId, remaining in pairs(data.cooldowns) do
            if type(remaining) == "number" and remaining >= 0 and remaining < 2592000 then
                gdb.cooldowns[charKey][spellId] = now + remaining
            end
        end
    end

    -- Merge specialisations.
    if type(data.specializations) == "table" then
        gdb.specializations[charKey] = data.specializations
    end

    -- Record sync time.
    if type(data.timestamp) == "number" then
        gdb.syncTimes[charKey] = data.timestamp
    end

    addon:DebugPrint("Scanner: merged data for", charKey, "guild:", guildKey, "from", sender)

    if addon.callbacks then
        addon.callbacks:Fire("SYNC_RECV", sender, 0)
        addon.callbacks:Fire("GUILD_DATA_UPDATED", charKey)
    end
end
