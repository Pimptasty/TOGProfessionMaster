-- TOG Profession Master — Compatibility shims
-- Loaded immediately after TOGProfessionMaster.lua.
-- Sets version flags and wraps APIs that differ across Classic versions so
-- no other module ever needs to branch on C_Container, C_AddOns, etc.

local _, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Version flags
-- Detected once at load time from GetBuildInfo().
-- Other modules read e.g. `addon.isVanilla` directly.
-- ---------------------------------------------------------------------------
local build = select(4, GetBuildInfo())  -- integer, e.g. 11508, 20504, 30403 …

addon.isVanilla = (build >= 11000 and build < 20000)
addon.isTBC     = (build >= 20000 and build < 30000)
addon.isWrath   = (build >= 30000 and build < 40000)
addon.isCata    = (build >= 40000 and build < 50000)
addon.isMoP     = (build >= 50000 and build < 60000)

-- Max profession skill for this expansion (Vanilla 300 / TBC 375 / Wrath 450 /
-- Cata 525 / MoP 600). Used as the authoritative "out of N" cap on skill readouts
-- so a stale or missing skillMax never renders a wrong cap like "375/300". A
-- per-expansion constant, not a PDB lookup: PDB ships recipes (not caps) and has
-- nothing for gathering professions, whereas the cap is uniform across every
-- profession in an expansion.
addon.SKILL_CAP =
    addon.isMoP     and 600 or
    addon.isCata    and 525 or
    addon.isWrath   and 450 or
    addon.isTBC     and 375 or
    300  -- Vanilla / Classic Era

-- Classic Era / Vanilla has no timeline-based expansion at all.
-- `addon.isClassic` is true for vanilla-protocol builds (Classic Era, Anniversary).
addon.isClassic = addon.isVanilla

-- Season of Discovery runs on the same Vanilla (1.15) client/build as Era,
-- Hardcore and Anniversary, so the build number can't tell them apart — but SoD
-- is the only one with the rune-engraving system enabled. Live check (engraving
-- state is reliable after login); used to gate SoD-only recipes that the shared
-- 1.15 client tables (and thus LibProfessionDB's Vanilla set) carry but regular
-- Era/HC/Anniversary realms can't learn.
function addon:IsSoD()
    return (C_Engraving and C_Engraving.IsEngravingEnabled and C_Engraving.IsEngravingEnabled()) and true or false
end

-- ---------------------------------------------------------------------------
-- Bag / container API
-- GetContainerItemInfo signature also changed, so we normalise the return
-- into a plain table: { texture, count, locked, quality, readable,
--                       lootable, link, filtered, noValue, itemId }
-- ---------------------------------------------------------------------------
-- Which branch actually runs: the C_Container one, on EVERY flavour this addon
-- supports. Checked against Blizzard's per-flavour source rather than assumed —
-- classic_era, classic_anniversary and classic (Cata/MoP) each ship
-- ContainerDocumentation.lua defining the namespace, each has zero bare
-- GetContainerItemInfo call sites under Interface/, and none of them has a
-- deprecation fallback file for the container family (unlike Item and
-- SpellBook, which do). The else branch below is kept as insurance for a build
-- I cannot check, but nothing reaches it today — so do not treat it as the
-- Classic path, and do not put a fix there expecting players to get it.
if C_Container and C_Container.GetContainerItemInfo then
    -- Every supported client takes this branch.
    function addon:GetContainerItemInfo(bag, slot)
        return C_Container.GetContainerItemInfo(bag, slot)
    end
    function addon:GetContainerNumSlots(bag)
        return C_Container.GetContainerNumSlots(bag)
    end
    function addon:GetContainerItemLink(bag, slot)
        return C_Container.GetContainerItemLink(bag, slot)
    end
    function addon:GetNumBagSlots()
        return NUM_BAG_SLOTS or 4
    end
else
    -- Unreachable on every live flavour (see the note above). Kept, not trusted.
    function addon:GetContainerItemInfo(bag, slot)
        -- The editor's stub declares no parameters; the client takes (bag, slot).
        ---@diagnostic disable-next-line: redundant-parameter
        local r = { GetContainerItemInfo(bag, slot) }
        local texture, count, locked, quality, readable = r[1], r[2], r[3], r[4], r[5]
        local lootable, link, filtered, noValue, itemId = r[6], r[7], r[8], r[9], r[10]
        if not texture then return nil end
        -- Older Classic/TBC builds return only the first 7 values here (no itemID),
        -- so `itemId` comes back nil. Callers that key on .itemID — e.g. the cooldown
        -- supply-mail bag scan (CdMail_CountItemInBags) — then match nothing and report
        -- "you have no <item> in your bags" even when you do. Derive the id from the
        -- item link so .itemID is always populated on every supported client.
        if not itemId and link then
            itemId = tonumber(link:match("item:(%d+)"))
        end
        return {
            iconFileID  = texture,
            stackCount  = count,
            isLocked    = locked,
            quality     = quality,
            isReadable  = readable,
            hasLoot     = lootable,
            hyperlink   = link,
            isFiltered  = filtered,
            hasNoValue  = noValue,
            itemID      = itemId,
        }
    end
    function addon:GetContainerNumSlots(bag)
        ---@diagnostic disable-next-line: redundant-parameter
        return GetContainerNumSlots(bag)
    end
    function addon:GetContainerItemLink(bag, slot)
        return GetContainerItemLink(bag, slot)
    end
    function addon:GetNumBagSlots()
        return NUM_BAG_SLOTS or 4
    end
end

--- Every item in the player's bags as { [itemId] = count }.
---
--- Lives here, next to the container shims it is built from, because it was
--- previously written out twice — `ScanBags` in GUI/ShoppingListTab.lua (since
--- deleted, v1.1.2) and
--- `ScanBagsOnly` in Modules/ReagentWatch.lua — with byte-identical bodies on
--- opposite sides of the GUI/Modules layer boundary. Two owners for one rule,
--- and in particular two places to remember the `info.itemID or info.itemId`
--- shim, which exists because the two GetContainerItemInfo branches above
--- spell the field differently.
function addon:ScanBagCounts()
    local counts = {}
    for bag = 0, self:GetNumBagSlots() do
        for slot = 1, self:GetContainerNumSlots(bag) do
            local info = self:GetContainerItemInfo(bag, slot)
            if info then
                local itemId = info.itemID or info.itemId
                if itemId then
                    counts[itemId] = (counts[itemId] or 0) + (info.stackCount or 1)
                end
            end
        end
    end
    return counts
end

-- ---------------------------------------------------------------------------
-- AddOn loaded check
-- The C_AddOns branch is the one that runs, on every flavour this addon
-- supports — not just retail, as this comment used to claim. Classic Era ships
-- C_AddOns.IsAddOnLoaded and has ZERO bare call sites for the old global under
-- Interface/, so the `or IsAddOnLoaded` tail is a fallback for a client I cannot
-- point at. Kept, not relied on.
-- ---------------------------------------------------------------------------
local _IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

function addon:IsAddOnLoaded(name)
    return _IsAddOnLoaded(name)
end

-- GetAddOnMetadata has no shim here. TOGProfessionMaster.lua loads BEFORE this
-- file (.toc order) and resolves it itself for addon.Version; a copy here had
-- no production caller and a spec vouching for it (audit finding 33). Same for
-- GetSpellInfo on the classic flavours (see the guard rule below). WoW Forever
-- is the exception: it has no bare GetSpellInfo (in game 2026-09-27, from the
-- Guild tab), and its 11_0_0_SpellBookAPITransitionGuide.lua also drops the
-- bare GetSpellCooldown / GetSpellTexture / GetSpellLink. Every spell call in
-- the addon goes through addon.Spell below.

-- ---------------------------------------------------------------------------
-- Item API -- ONE resolver, because every bare name here is a DEPRECATION
-- FALLBACK rather than the real function. Audit findings 26/27.
--
-- `Blizzard_DeprecatedItemScript.lua` opens with
--     if not GetCVarBool("loadDeprecationFallbacks") then return end
-- and then assigns ~47 bare globals from their C_Item counterparts. Ours are at
-- `:42` (GetItemInfo), `:10` (GetItemInfoInstant), `:16` (GetItemIcon), `:46`
-- (GetItemCount), `:9` (GetItemQualityColor) and `:52` (GetItemCooldown). With
-- that CVar off, every one of them is nil -- so an unguarded call raises, and
-- a `if GetItemInfo then` guard silently skips the branch instead. Both shapes
-- were live here: the raise in MissingRecipesTab and the silent skip in
-- ItemLink.QualityHex.
--
-- WARNING: `GetItemIcon` maps to `C_Item.GetItemIconByID`, NOT
-- `C_Item.GetItemIcon`. The names do not correspond one-to-one and a mechanical
-- rename would produce a nil that only shows up as a missing texture.
--
-- Every C_Item name below is confirmed present on Classic Era in
-- `GlobalAPI.lua`. The bare tail is kept for a client that genuinely lacks the
-- namespace; it is a fallback, not the preferred path.
--
-- THE GUARD RULE (audit findings 30 and 32), because the presence-guard idiom
-- spread by NAME SHAPE and ended up on the wrong names: a bare global gets a
-- presence guard IF AND ONLY IF it is a deprecation fallback, and a name routed
-- through a resolver here NEVER gets one, because the resolver owns the nil
-- check. (Superseded for the spell API by addon.Spell, for WoW Forever; the
-- rest of this note is the classic reasoning.) So `GetSpellInfo(id)` was called bare -- it is in no `Deprecated_*`
-- file in either Classic tree and Blizzard's own UI calls it bare -- and a
-- guard on it can never be false, while `if GetItemInfo then` above a call to
-- `addon.Item.GetInfo` is WRONG: with the CVar off the guard is false, the
-- resolver would have answered through C_Item, and the branch is skipped
-- anyway. Five such guards vetoed the very calls the resolver exists to make.
--
-- The previous wrapper here said "no API change on Classic -- plain wrapper for
-- consistency", which was wrong in exactly the way that mattered.
-- ---------------------------------------------------------------------------
-- Each entry resolves at CALL time, not at load. Two reasons, and the second is
-- the one that bites:
--
--   1. A client that gains or loses the namespace mid-session is handled for
--      free, and load order stops mattering to consumers.
--   2. THE OFFLINE SUITE STUBS THESE BY NAME. Specs assign `_G.GetItemInfo` in
--      `before_each` to feed a specific answer, and the harness env installs
--      BOTH spellings as the SAME function object. An early-bound alias would
--      capture the env's original at load and quietly ignore every later stub --
--      so the specs would still pass while measuring nothing, which is the exact
--      failure shape this board keeps recording.
addon.Item = addon.Item or {}

local function itemAPI(namespaced, bare)
    return function(...)
        local fn = (C_Item and C_Item[namespaced]) or _G[bare]
        if not fn then return nil end
        return fn(...)
    end
end

addon.Item.GetInfo         = itemAPI("GetItemInfo",         "GetItemInfo")
addon.Item.GetInfoInstant  = itemAPI("GetItemInfoInstant",  "GetItemInfoInstant")
addon.Item.GetIcon         = itemAPI("GetItemIconByID",     "GetItemIcon")
addon.Item.GetCount        = itemAPI("GetItemCount",        "GetItemCount")
addon.Item.GetQualityColor = itemAPI("GetItemQualityColor", "GetItemQualityColor")
-- The item-cooldown tier behind C_Container.GetItemCooldown (a genuinely
-- different function, tried first by its caller). Audit findings 29/31: this
-- name was on the deprecated list and was the one bare, unguarded call left.
addon.Item.GetCooldown     = itemAPI("GetItemCooldown",     "GetItemCooldown")

-- ---------------------------------------------------------------------------
-- Spell API -- WoW Forever (the _Camelot TOC, the 11.x+ engine) has NO bare
-- GetSpellCooldown: its 11_0_0_SpellBookAPITransitionGuide.lua:53 maps it to
-- C_Spell.GetSpellCooldown, which answers ONE TABLE ({ startTime, duration,
-- isEnabled, modRate }, SpellDocumentation.lua:292) rather than the classic
-- `start, duration, enabled, modRate` list. Reported in game 2026-09-27 as
-- "attempt to call a nil value" from ScanCooldowns. This answers the classic
-- shape on every client, resolved at call time like the item API above.
-- ---------------------------------------------------------------------------
addon.Spell = addon.Spell or {}

function addon.Spell.GetCooldown(spellId)
    local ns = C_Spell and C_Spell.GetSpellCooldown
    if ns then
        local info, duration, enabled, modRate = ns(spellId)
        if type(info) == "table" then
            return info.startTime, info.duration, info.isEnabled, info.modRate
        end
        -- A client whose C_Spell form still answers the classic list.
        if info ~= nil then return info, duration, enabled, modRate end
    end
    local bare = _G.GetSpellCooldown
    if bare then return bare(spellId) end
    return nil
end

-- RESOLUTION ORDER: NAMESPACED FIRST, as addon.Item does. Until 2026-09-29 the
-- helpers below preferred the BARE name, for a test-environment reason only:
-- the offline harness had no C_Spell, so specs stubbed the bare name and the
-- C_Spell branch (the one Forever runs) was never exercised offline. The
-- harness now installs C_Spell / C_SpellBook on every flavour and has a Forever
-- build (WoWAPITesting a7675ce, inbox a092c095), so that reason is gone.
-- C_Spell.GetSpellInfo / GetSpellTexture / GetSpellLink / GetSpellCooldown are
-- documented on Classic Era and on Classic (Cata/MoP) too
-- (SpellDocumentation.lua:108/190/221/357 in both trees), so every client takes
-- the same branch. The bare name stays as the fallback for a client without
-- the namespace.
--
-- GetInfo unpacks C_Spell's SpellInfo table (SpellDocumentation.lua:1166 in the
-- forever tree) into the classic list `name, rank, icon, castTime, minRange,
-- maxRange, spellID`. RANK IS NIL on this path: the table carries no rank. No
-- caller reads the second return (checked 2026-09-29: every call site takes the
-- name, the icon, or whether the spell exists at all). Both forms return nil for
-- an unknown spell ("Returns nil if spell is not found"), which RecipeGate's Era
-- filter depends on.
function addon.Spell.GetInfo(spellId)
    local ns = C_Spell and C_Spell.GetSpellInfo
    if ns then
        if not spellId then return nil end
        local info = ns(spellId)
        if type(info) ~= "table" then return nil end
        return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
    end
    local bare = _G.GetSpellInfo
    ---@diagnostic disable-next-line: redundant-parameter
    if bare then return bare(spellId) end
    return nil
end

function addon.Spell.GetTexture(spellId)
    local ns = C_Spell and C_Spell.GetSpellTexture
    if ns then
        if not spellId then return nil end
        return ns(spellId)
    end
    local bare = _G.GetSpellTexture
    if bare then return bare(spellId) end
    return nil
end

function addon.Spell.GetLink(spellId)
    local ns = C_Spell and C_Spell.GetSpellLink
    if ns then
        if not spellId then return nil end
        return ns(spellId)
    end
    local bare = _G.GetSpellLink
    if bare then return bare(spellId) end
    return nil
end

-- Does this client have the CLASSIC trade-skill window API the scanner and the
-- Crafting engine read (GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo)?
-- WoW Forever reaches profession data only through C_TradeSkillUI (its own UI:
-- Blizzard_FrameXMLUtil/ProfessionsUtil.lua:79), and whether the classic
-- globals exist there is not verified. Until they are confirmed, or a Forever
-- recipe scan is built on C_TradeSkillUI, a trade-skill event on a client
-- without them is ignored rather than scanned into a nil-call. Checked at call
-- time, like every resolver here.
function addon:HasClassicTradeSkillAPI()
    return _G.GetTradeSkillLine ~= nil and _G.GetNumTradeSkills ~= nil
       and _G.GetTradeSkillInfo ~= nil
end

-- WoW Forever's trade-skill API: C_TradeSkillUI, used ONLY where the classic
-- globals above are absent, so no classic client ever takes this path. The
-- classic globals are not in Forever's source tree at all, not even as
-- deprecation fallbacks; its own Professions UI reads and crafts through
-- C_TradeSkillUI (Blizzard_Professions.lua:847, Blizzard_ProfessionsTransaction
-- .lua:352). The Scanner and the Crafting engine both branch on this.
function addon:HasModernTradeSkillAPI()
    if self:HasClassicTradeSkillAPI() then return false end
    return C_TradeSkillUI ~= nil and C_TradeSkillUI.GetRecipeInfo ~= nil
end

-- The open profession on the modern API, as a ProfessionInfo table
-- (professionName, skillLevel, maxSkillLevel, professionID, parent* fields;
-- TradeSkillUITypesDocumentation.lua:361-377), or nil when none is open.
-- Blizzard's own read (Professions.GetProfessionInfo, Blizzard_Professions.lua
-- :1665) takes the child profession and falls back to the base one when the
-- child's id is 0.
function addon:GetModernOpenProfession()
    local T = C_TradeSkillUI
    if not T then return nil end
    local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
    if child and child.professionID and child.professionID ~= 0
       and child.professionName and child.professionName ~= "" then
        return child
    end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    if base and base.professionName and base.professionName ~= "" then return base end
    return nil
end

-- The learned recipe ids of the open profession on the modern API.
-- GetAllRecipeIDs (the unfiltered retail call) FIRST: GetFilteredRecipeIDs,
-- the one Blizzard's list uses (Blizzard_Professions.lua:847), honours the
-- player's search box and filters in Blizzard's window, and a partial list fed
-- to the Scanner would drop real recipes from this character's crafter set.
-- Whether Forever has GetAllRecipeIDs is NOT verified (its source tree never
-- calls it), so the filtered call is the fallback. Dummy and gathering entries
-- are not crafts.
function addon:GetModernLearnedRecipeIDs()
    local T = C_TradeSkillUI
    local listFn = T and (T.GetAllRecipeIDs or T.GetFilteredRecipeIDs)
    local out = {}
    if not listFn then return out end
    for _, id in ipairs(listFn() or {}) do
        local r = T.GetRecipeInfo(id)
        if r and r.learned and not r.isDummyRecipe and not r.isGatheringRecipe then
            out[#out + 1] = id
        end
    end
    return out
end

-- IsSpellKnown(spellId, isPet). The bare function is a DEPRECATION FALLBACK on
-- Classic Era as well as on WoW Forever -- Blizzard_DeprecatedSpellBook/
-- Deprecated_SpellBook.lua:16 in the classic_era tree -- so it is nil wherever
-- loadDeprecationFallbacks is off. (This comment said "the real one on the
-- classic clients" until 2026-09-29; the classic_era tree says otherwise.) So
-- this does what that fallback's body does, namespaced FIRST:
-- C_SpellBook.IsSpellInSpellBook(id, bank, includeOverrides = false).
function addon.Spell.IsKnown(spellId, isPet)
    local sb = C_SpellBook and C_SpellBook.IsSpellInSpellBook
    local banks = Enum and Enum.SpellBookSpellBank
    if sb and banks then
        return sb(spellId, isPet and banks.Pet or banks.Player, false) and true or false
    end
    local bare = _G.IsSpellKnown
    if bare then return bare(spellId, isPet) and true or false end
    return false
end

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Tooltip anchor helper
-- Always use this instead of a raw GameTooltip:SetOwner call.
-- Anchors below the frame when in the top half of the screen (BOTTOMLEFT),
-- above when in the bottom half (TOPLEFT), so it never clips off screen.
-- ---------------------------------------------------------------------------
addon.Tooltip = {}

function addon.Tooltip.Owner(frame)
    local _, y = frame:GetCenter()
    local anchor = (y and y > GetScreenHeight() / 2) and "ANCHOR_BOTTOMLEFT" or "ANCHOR_TOPLEFT"
    GameTooltip:SetOwner(frame, anchor)
end

-- (Tooltip.AnchorFrame, the popup-beside-a-row placement, was retired for
-- LibAceGUIWidgets' AnchorPopup -- see the Cooldowns tab's group popup.)

-- TOGBankClassic integration helpers
-- Shared by BrowserTab and CooldownsTab (and any future caller).
-- All three functions are no-ops when TOGBankClassic is not loaded.
-- ---------------------------------------------------------------------------
addon.Bank = {}

--- How many of `itemId` one banker alt holds, summed across stacks.
--
-- TOGBankClassic v1.4.2 (INV2-RETIRE-003, in its working tree) retires the
-- per-alt `alt.items` rows: its scan no longer writes them and it strips
-- them from SavedVariables on load, so the V2 tuple store is the only
-- inventory. The public reader for the question this addon asks is
-- `TOG:GetAltItemTotal(altName, itemId)` -- a number, 0 when unknown, no
-- allocation. Feature-detected on the METHOD, not a version: an older
-- TOGBank still has the rows and lacks the accessor, a newer one has the
-- accessor and lacks the rows, and the two branches cover both. (That tree
-- also answers `alt.items` through a metatable for exactly this reader --
-- INV2-COMPAT-001 -- but a consumer should not depend on a shim written for
-- it when the accessor is public.) Peer-review thread 18f6cc11, relayed from
-- TOGBank's own audit.
local function altItemTotal(TOG, altName, alt, itemId)
    if TOG.GetAltItemTotal then
        return TOG:GetAltItemTotal(altName, itemId) or 0
    end
    local total = 0
    for _, entry in ipairs((alt and alt.items) or {}) do
        if entry.ID == itemId then
            total = total + (entry.Count or 0)
        end
    end
    return total
end

--- Returns sorted array of { name, count } for bankers that hold itemId.
-- The per-banker count SUMS every matching entry, because a bank holds an item
-- as one entry per stack -- 60 Copper Bars in a 20-stack bank is three entries,
-- not one. Taking the first match and breaking (what this did until v1.0.7)
-- under-reported every multi-stack reagent, which is most of them. It was wrong
-- in two visible places: the tooltip's "Bankers:" count, and `ShowRequestDialog`,
-- which sums these counts into `totalStock` and caps `maxRequestable` from it --
-- so a player could not request more than the first stack. `GetStock` above and
-- TOGBankClassic's own renderer both sum; this is the one that disagreed.
function addon.Bank.GetBanksWithItem(itemId)
    local TOG = _G["TOGBankClassic_Guild"]
    if not TOG then return {} end
    local banks = TOG:GetBanks()
    if not banks or #banks == 0 then return {} end
    local alts   = TOG.Info and TOG.Info.alts or {}
    local result = {}
    for _, bankName in ipairs(banks) do
        -- GetBanks returns roster names; the store is keyed by TOGBank's
        -- normalized form, so normalize when it can (Guild.lua:NormalizeName).
        local altName = (TOG.NormalizeName and TOG:NormalizeName(bankName)) or bankName
        local total = altItemTotal(TOG, altName, alts[altName] or alts[bankName], itemId)
        if total > 0 then
            -- How current OUR COPY of that banker's inventory is -- TOGBank's
            -- own per-banker verdict (Guild:GetAltStaleness, the dot beside
            -- every banker in its Browse list). nil against a TOGBank that
            -- predates the accessor, and the callers below draw no dot then.
            local state = TOG.GetAltStaleness and TOG:GetAltStaleness(altName) or nil
            table.insert(result, { name = bankName, count = total, state = state })
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- ---------------------------------------------------------------------------
-- Banker staleness -- the dot on every [Bank] button
-- ---------------------------------------------------------------------------
-- The user, 2026-09-14, of TOGBank's green dots: "i would like to add those
-- dots next to the items in TOGPM as well if they have the bank button
-- available, so folks can tell at a glance if it's stale or not."
--
-- The STATES are TOGBank's (`Guild:GetAltStaleness`): "current" -- nobody has
-- mentioned anything newer; "behind" -- a newer copy is published and being
-- fetched; "offered" -- a peer has offered a newer copy; "refused" -- the only
-- peer with a newer copy cannot send it to this release; "v1" -- an old-format
-- copy; "none" -- nothing held. The COLOURS are read from TOGBank's own
-- `TOGBankClassic_UI_Browse.STATE_COLOR` / `STATE_TEXT` when that table exists,
-- so a palette change there reaches these dots without an edit here; the
-- local copy below is the fallback for a TOGBank that has the accessor but
-- predates the Browse window, and it is TOGBank's values verbatim.
local STATE_COLOR = {
    current = "ff00ff00", behind = "ffff0000", offered = "ffffff00",
    refused = "ffa0a0a0", v1 = "ffff0000", none = "ff808080",
}
local STATE_TEXT = {
    current = "Current", behind = "Behind", offered = "Update offered",
    refused = "Newer copy unreachable", v1 = "Old format", none = "No data",
}
-- Worst first. A [Bank] button stands for EVERY banker holding the item, so
-- its one dot is the worst of theirs: a red among greens is the thing the
-- glance is for.
local STATE_RANK = { behind = 1, v1 = 1, offered = 2, refused = 3, none = 4, current = 5 }

local function bankPalette()
    local B = _G["TOGBankClassic_UI_Browse"]
    return (B and B.STATE_COLOR) or STATE_COLOR, (B and B.STATE_TEXT) or STATE_TEXT
end

--- The colour code (without the leading `|c`) TOGBank paints a state in.
function addon.Bank.StateColor(state)
    local colors = bankPalette()
    return colors[state] or colors.none or STATE_COLOR.none
end

--- The word TOGBank uses for a state ("Current", "Behind", ...).
function addon.Bank.StateText(state)
    local _, texts = bankPalette()
    return texts[state] or STATE_TEXT[state] or tostring(state)
end

--- The worst staleness state across every banker holding `itemId`, or nil when
--- nobody holds it or the TOGBank in play cannot say.
function addon.Bank.ItemState(itemId)
    if not itemId then return nil end
    local worst, worstRank
    for _, b in ipairs(addon.Bank.GetBanksWithItem(itemId)) do
        local rank = b.state and (STATE_RANK[b.state] or STATE_RANK.none)
        if rank and (not worstRank or rank < worstRank) then
            worst, worstRank = b.state, rank
        end
    end
    return worst
end

-- The bullet TOGBank draws (U+2022), coloured; the [Bank] label is the one
-- every site used to hard-code.
local BANK_LABEL = "|cFF88FF88[Bank]|r"
local DOT = "\226\128\162"

--- The [Bank] button's text for `itemId`: TOGBank's staleness dot, then the
--- label -- or the bare label when there is no state to show (no TOGBank,
--- an older one, or no stock). `labelText` replaces the default green
--- "[Bank]" (the Shopping List's AceGUI buttons carry the localised word).
function addon.Bank.ButtonText(itemId, labelText)
    labelText = labelText or BANK_LABEL
    local state = addon.Bank.ItemState(itemId)
    if not state then return labelText end
    return "|c" .. addon.Bank.StateColor(state) .. DOT .. "|r " .. labelText
end

--- Label a [Bank] button for `itemId` and remember the item on it, so its
--- OnEnter can add the per-banker status lines (`AddStatusLines`).
--- `fontString` is the FontString to write when the button does not carry its
--- own text (the Cooldowns tab's main row); a raw frame or an AceGUI widget
--- otherwise. `labelText` as in `ButtonText`.
function addon.Bank.Decorate(btn, itemId, fontString, labelText)
    if not btn then return end
    local text = addon.Bank.ButtonText(itemId, labelText)
    if fontString then fontString:SetText(text) elseif btn.SetText then btn:SetText(text) end
    -- Only a raw frame keeps the id: an AceGUI widget is pooled account-wide
    -- and a field left on it would ride into its next owner.
    if not btn.frame then btn._bankItemId = itemId end
end

--- Append one line per banker holding the button's item -- its name, count and
--- TOGBank's status word in TOGBank's colour -- to the open GameTooltip. Nothing
--- is added for a button with no item, or when TOGBank reports no state.
--- The per-banker status lines for `itemId`, as { left, right } pairs: the
--- banker's dot, name and count, and TOGBank's status word, both in TOGBank's
--- colour. nil when no banker holding it has a state (no TOGBank, an older one,
--- or no stock). ONE source for both renderings below.
local function bankerStatusLines(itemId)
    if not itemId then return nil end
    local banks = addon.Bank.GetBanksWithItem(itemId)
    local any = false
    for _, b in ipairs(banks) do if b.state then any = true break end end
    if not any then return nil end
    local lines = {}
    for _, b in ipairs(banks) do
        local state = b.state or "none"
        local c = addon.Bank.StateColor(state)
        lines[#lines + 1] = {
            ("|c%s%s|r %s (%d)"):format(c, DOT, b.name, b.count),
            "|c" .. c .. addon.Bank.StateText(state) .. "|r",
        }
    end
    return lines
end

function addon.Bank.AddStatusLines(btn)
    local lines = bankerStatusLines(btn and btn._bankItemId)
    if not lines then return end
    GameTooltip:AddLine(" ")
    for _, l in ipairs(lines) do GameTooltip:AddDoubleLine(l[1], l[2]) end
end

--- The same lines as one string, for a tooltip body that is handed text rather
--- than drawn into GameTooltip (a RowList button column's `tip`).
function addon.Bank.StatusText(itemId)
    local lines = bankerStatusLines(itemId)
    if not lines then return nil end
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = l[1] .. " - " .. l[2] end
    return table.concat(out, "\n")
end

--- Returns the total item count held across all banker alts.
--
-- The sum of GetBanksWithItem, so the two cannot disagree. Until v1.1.0 this
-- walked EVERY record in `TOG.Info.alts` -- which carries ex-bankers whose
-- stored inventory TOGBank keeps after their bank note is removed (its
-- TOOLTIP-002 class) -- so a character taken off bank duty still holding 20
-- Linen Cloth lit the [Bank] button and reported 20 in stock, against a
-- request nobody could fill. GetBanksWithItem walks `GetBanks()`, the current
-- banker list, and this now composes it. TOGBankClassic's peer review,
-- thread 5eef0788, finding F2.
function addon.Bank.GetStock(itemId)
    local total = 0
    for _, b in ipairs(addon.Bank.GetBanksWithItem(itemId)) do
        total = total + b.count
    end
    return total
end

--- Returns true if charKey belongs to a TOGBankClassic banker alt.
-- Delegates to TOGBankClassic's own canonical check (`TOG:IsBank`) which
-- normalizes the input via `NormalizeName` and does an O(1) memberRoster
-- lookup. Earlier rolling-our-own implementation that walked `GetBanks()`
-- and string-compared against `charKey:match("^([^-]+)")` was broken on
-- connected-realm guilds: `GetBanks()` returns `member.name` from the
-- guild roster, which is `"Name-Realm"` on cross-realm clusters, while
-- our short-name match stripped the realm — so no entry ever matched
-- and every banker fell through as non-banker. `TOG:IsBank` accepts
-- any format and handles normalization itself.
-- Returns false when TOGBank isn't loaded so callers degrade gracefully.
function addon.Bank.IsBanker(charKey)
    if type(charKey) ~= "string" then return false end
    local TOG = _G["TOGBankClassic_Guild"]
    if not TOG or not TOG.IsBank then return false end
    return TOG:IsBank(charKey)
end

--- How many of `itemId` this player may still order from `bankName`, the
-- percent behind it, and the sentence TOGBank refuses a larger order with.
--
-- Since TOGBank's SETTINGS-CANON-001 (peer-review thread 17a1f2c9),
-- `Guild:AddRequest` ENFORCES the officer's maximum request %: per bank, less
-- this player's OPEN orders of the item from that bank. `Guild:RequestAllowance`
-- is that exact number, so the dialog offers no more than it -- a percent of the
-- whole guild's stock (what this used to compute) offers quantities Send is then
-- refused for. At 100% AddRequest gates nothing, so the ceiling is simply what
-- that bank holds, the same as TOGBank's own request dialog. Against a TOGBank
-- without the accessor nothing enforces anything and the old whole-guild
-- percent stays the only cap.
--
-- Returns max, pct, why, base -- `base` is the stock the percent is OF (that
-- banker's on the enforced path, the whole guild's on the old one), so the
-- dialog's "stock | max (pct)" line never pairs one banker's cap with the
-- guild's total.
function addon.Bank.RequestAllowance(itemId, bankName, bankCount, totalStock)
    local TOG = _G["TOGBankClassic_Guild"]
    if TOG and TOG.RequestAllowance and TOG.GetNormalizedPlayer then
        local left, cap, open, pct = TOG:RequestAllowance(TOG:GetNormalizedPlayer(), bankName, itemId, bankCount)
        pct = pct or 100
        if pct >= 100 then return bankCount, 100, nil, bankCount end
        local why = TOG.RequestLimitText and TOG:RequestLimitText(left, cap, open, pct) or nil
        return left or 0, pct, why, bankCount
    end
    local opts = _G["TOGBankClassic_Options"]
    local pct  = (opts and opts.GetMaxRequestPercent and opts:GetMaxRequestPercent()) or 100
    return math.max(1, math.floor(totalStock * pct / 100)), pct, nil, totalStock
end

-- The bank-request dialog: one LibAceGUIWidgets form dialog (MINOR 36, TOGPM
-- contract 6cf3b4e4) for every [Bank] button, built on first use. Its rows are
-- the item, the banker and the quantity; the hint carries the stock line, a
-- note under the quantity the "/ max N", and the body TOGBank's shop-order
-- line while its shop is on. The fields the rest of this file reads keep the
-- names the hand-built dialog gave them (qtyBox, sendBtn, stockLbl, maxLbl,
-- shopLbl).
local ROW_ITEM, ROW_BANK, ROW_QTY = 1, 2, 3
local _bankDialog

local function bankLabel(b)
    return (b.name:match("^([^%-]+)") or b.name) .. " (" .. b.count .. ")"
end

local function buildBankDialog()
    local d
    d = addon.W:CreateFormDialog({
        name  = "TOGPMBankRequestDialog",
        title = L["BankDialogTitle"],
        -- Built with a hint and a body so the lines they back always exist;
        -- each open sets or hides them.
        hint  = " ",
        body  = " ",
        rows  = {
            -- The item row's hover and click are TOGPM's own (LibAceGUIWidgets
            -- MINOR 39, TOGPM contract 1d7a76ba), so the [Bank] dialog keeps
            -- hold-to-compare and a rebound chat-link modifier like every other
            -- item in the addon. addon.ItemLink loads after this file, so it is
            -- looked up when the event fires; before MINOR 39 the library
            -- ignores these fields and keeps its built-in hover and click.
            { kind = "item", label = "",
              onEnter = function(button, link)
                  local IL = addon.ItemLink
                  if not IL then return end
                  addon.Tooltip.Owner(button)
                  IL.SetItem(GameTooltip, link)
                  GameTooltip:Show()
              end,
              onLeave = function()
                  local IL = addon.ItemLink
                  if IL then IL.EndHover(GameTooltip) end
                  GameTooltip:Hide()
              end,
              onClick = function(_, link)
                  local IL = addon.ItemLink
                  if IL then IL.Click(link) end
              end },
            { kind = "dropdown", label = L["BankDialogBanker"],
              items = function()
                  local out = {}
                  for _, b in ipairs(d.currentBanks or {}) do
                      out[#out + 1] = { text = bankLabel(b), value = b.name }
                  end
                  return out
              end,
              onChanged = function(value)
                  d.selectedBank = value
                  if d.applyLimit then d.applyLimit() end
              end },
            { label = L["BankDialogQty"], numeric = true, digitsOnly = true },
        },
        okText     = L["BankDialogSend"],
        cancelText = L["BankDialogCancel"],
        -- OK does not close the dialog by itself: Send decides, and a refusal
        -- leaves what the player typed in place.
        onAccept   = function() if d.send then d.send() end end,
    })
    d.itemRow  = d.fields[ROW_ITEM]
    d.bankBox  = d.fields[ROW_BANK]
    d.qtyBox   = d.fields[ROW_QTY]
    d.qtyBox:SetMaxLetters(5)
    d.sendBtn  = d.ok
    d.stockLbl = d.hint
    d.shopLbl  = d.body
    d:SetNote(ROW_QTY, " ")
    d.maxLbl   = d.notes[ROW_QTY]
    return d
end

--- Open the "Request from Guild Bank" dialog.
-- itemId   numeric item ID
-- itemName display name (used in the request payload)
-- itemLink full hyperlink (shown in the dialog; may be nil)
function addon.Bank.ShowRequestDialog(itemId, itemName, itemLink, anchorBelow)
    local TOG = _G["TOGBankClassic_Guild"]
    if not (TOG and addon.W) then return end

    local banksWithItem = addon.Bank.GetBanksWithItem(itemId)
    if #banksWithItem == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFDA8CFF[TOGPM]|r No bankers currently have this item in stock.")
        return
    end
    -- A view-only banker's stock is shown (tooltips, the [Bank] dot) but
    -- cannot be requested -- TOGBank's AddRequest refuses it (VIEWBANK-001) --
    -- so it is never offered here, least of all as the pre-selected default.
    if TOG.IsViewOnlyBank then
        local requestable = {}
        for _, b in ipairs(banksWithItem) do
            if not TOG:IsViewOnlyBank(b.name) then requestable[#requestable + 1] = b end
        end
        if #requestable == 0 then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFFDA8CFF[TOGPM]|r Only view-only bankers hold this item, and they do not take requests.")
            return
        end
        banksWithItem = requestable
    end

    local totalStock = 0
    for _, b in ipairs(banksWithItem) do totalStock = totalStock + b.count end

    _bankDialog = _bankDialog or buildBankDialog()
    local d = _bankDialog
    d.currentItemId   = itemId
    d.currentItemName = itemName
    d.currentBanks    = banksWithItem
    d.selectedBank    = banksWithItem[1].name
    d.bankBox:SetValue(banksWithItem[1].name, bankLabel(banksWithItem[1]))

    -- The allowance is per bank, so it is recomputed whenever the banker changes
    -- -- and again at Send (keepQty), since an order filled or placed elsewhere
    -- while the dialog sat open moves it, exactly as TOGBank's own dialog
    -- re-checks on submit.
    local function applyLimit(keepQty)
        local bankCount = 0
        for _, b in ipairs(banksWithItem) do
            if b.name == d.selectedBank then bankCount = b.count end
        end
        local max, pct, why, base = addon.Bank.RequestAllowance(itemId, d.selectedBank, bankCount, totalStock)
        d.maxRequestable = max
        d.limitWhy       = why
        if not keepQty then d.qtyBox:SetText(tostring(math.min(1, max))) end
        if pct < 100 then
            d:SetHint(string.format("Bank stock: %d  |  Max requestable: %d (%d%%)", base, max, pct))
        else
            d:SetHint(string.format("Bank stock: %d", base))
        end
        d:SetNote(ROW_QTY, "/ max " .. max)
    end
    d.applyLimit = applyLimit

    -- The item row shows a link. Without one (an item the client has not
    -- cached), a plain item link built from the id still hovers and links.
    d.currentItemLink = itemLink
    d.itemRow:SetItem(itemLink or ("|Hitem:%d|h[%s]|h"):format(itemId, itemName or ("Item #" .. itemId)),
        addon.Item.GetIcon(itemId))
    applyLimit()

    -- SHOP-NOFREE-001: while TOGBank's shop is on, AddRequest refuses any order
    -- not marked as a shop order. `Guild:ShopOrderFields` (SHOP-ORDER-API-001,
    -- built for this button on thread 17a1f2c9) is TOGBank's one builder: merge
    -- every field but `prompt` into the request, show `prompt`. Taken at open so
    -- the estimate written is the one the player was shown, as TOGBank's dialog
    -- does; nil while the shop is off or on a TOGBank without the API. The
    -- dialog's height follows the line.
    d.shopFields = TOG.ShopOrderFields and TOG:ShopOrderFields(itemId) or nil
    d:SetBody(d.shopFields and d.shopFields.prompt or nil)

    d.send = function()
        local reqTOG = _G["TOGBankClassic_Guild"]
        if not reqTOG then return end
        local qty = tonumber(d.qtyBox:GetText()) or 0
        applyLimit(true)
        -- Over the allowance (including none left at all) says TOGBank's own
        -- sentence when it has one: it names the open orders that used it up.
        if d.maxRequestable < 1 or qty > d.maxRequestable then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[TOGPM] " .. (d.limitWhy or string.format(
                "Maximum requestable quantity is %d.", d.maxRequestable)) .. "|r")
            return
        end
        if qty < 1 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[TOGPM] Quantity must be at least 1.|r")
            return
        end
        if not d.selectedBank or d.selectedBank == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[TOGPM] Please select a banker.|r")
            return
        end
        local reqName = d.currentItemName
            or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(d.currentItemId))
            or "Unknown"
        local request = {
            item      = reqName,
            itemID    = d.currentItemId,
            quantity  = qty,
            requester = reqTOG:GetNormalizedPlayer(),
            bank      = d.selectedBank,
            notes     = "",
        }
        for k, v in pairs(d.shopFields or {}) do
            if k ~= "prompt" then request[k] = v end
        end
        local ok, why = reqTOG:AddRequest(request)
        if ok then
            local dispBank = d.selectedBank:match("^([^%-]+)") or d.selectedBank
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFFDA8CFF[TOGPM]|r Bank request sent: %dx %s \226\134\146 %s", qty, reqName, dispBank))
            d:Hide()
        else
            -- AddRequest returns `false, <sentence>` for every gate it refuses on
            -- (limit, shop closed, view-only bank...), written for the player.
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[TOGPM] Request failed. "
                .. (why or "Check that TOGBankClassic is synced.") .. "|r")
        end
    end

    -- Below the caller's anchor when it gave one, else beside the main window
    -- (the form dialog's default: its TOPLEFT at the owner's TOPRIGHT, 4 px
    -- over), else centred.
    local mainWowFrame = addon.MainWindow
                      and addon.MainWindow.frame
                      and addon.MainWindow.frame.frame
    -- Only a frame anchors: a caller once passed a stray number here
    -- (select() spreading into this slot), and the dialog must still open.
    if type(anchorBelow) == "table" and anchorBelow.IsShown and anchorBelow:IsShown() then
        d:SetAnchor(anchorBelow, "TOPLEFT", "BOTTOMLEFT", 0, -4)
    elseif mainWowFrame and mainWowFrame:IsShown() then
        d:SetAnchor(mainWowFrame)
    else
        d:SetAnchor(nil)
        d:ClearAllPoints()
        d:SetPoint("CENTER")
    end

    d:Show()
    -- With the main window open, Escape closes this dialog before the window
    -- (its name is taken off UISpecialFrames while that window's layer lasts,
    -- so one press no longer closes both).
    if addon.MainWindow then addon.MainWindow:AddEscapeChild(d) end
end

addon:DebugPrint(
    "Compat loaded. build:", build,
    "Vanilla:", tostring(addon.isVanilla),
    "TBC:",     tostring(addon.isTBC),
    "Wrath:",   tostring(addon.isWrath),
    "Cata:",    tostring(addon.isCata),
    "MoP:",     tostring(addon.isMoP)
)
