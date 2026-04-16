-- TOG Profession Master — Compatibility shims
-- Loaded immediately after TOGProfessionMaster.lua.
-- Sets version flags and wraps APIs that differ across Classic versions so
-- no other module ever needs to branch on C_Container, C_AddOns, etc.

local _, addon = ...

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

-- Classic Era / Vanilla has no timeline-based expansion at all.
-- `addon.isClassic` is true for vanilla-protocol builds (Classic Era, Anniversary).
addon.isClassic = addon.isVanilla

-- ---------------------------------------------------------------------------
-- Bag / container API
-- GetContainerItemInfo signature also changed, so we normalise the return
-- into a plain table: { texture, count, locked, quality, readable,
--                       lootable, link, filtered, noValue, itemId }
-- ---------------------------------------------------------------------------
if C_Container and C_Container.GetContainerItemInfo then
    -- Shadowlands+ / Dragonflight builds
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
    -- Classic Era / TBC / Wrath / Cata / MoP — old globals
    function addon:GetContainerItemInfo(bag, slot)
        local texture, count, locked, quality, readable,
              lootable, link, filtered, noValue, itemId =
              GetContainerItemInfo(bag, slot)
        if not texture then return nil end
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
        return GetContainerNumSlots(bag)
    end
    function addon:GetContainerItemLink(bag, slot)
        return GetContainerItemLink(bag, slot)
    end
    function addon:GetNumBagSlots()
        return NUM_BAG_SLOTS or 4
    end
end

-- ---------------------------------------------------------------------------
-- AddOn loaded check
-- C_AddOns.IsAddOnLoaded exists on Dragonflight+ retail only.
-- ---------------------------------------------------------------------------
local _IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

function addon:IsAddOnLoaded(name)
    return _IsAddOnLoaded(name)
end

-- ---------------------------------------------------------------------------
-- GetAddOnMetadata
-- Same split as above.
-- ---------------------------------------------------------------------------
addon.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- ---------------------------------------------------------------------------
-- Spell info
-- GetSpellInfo was split into multiple C_Spell.* calls on retail 10.1 but the
-- old signature still works on all Classic builds, so no shim needed yet.
-- This placeholder keeps the pattern consistent if it ever changes.
-- ---------------------------------------------------------------------------
function addon:GetSpellInfo(spellId)
    return GetSpellInfo(spellId)
end

-- ---------------------------------------------------------------------------
-- Item info (no API change on Classic — plain wrapper for consistency)
-- ---------------------------------------------------------------------------
function addon:GetItemInfo(itemId)
    return GetItemInfo(itemId)
end

addon:DebugPrint(
    "Compat loaded. build:", build,
    "Vanilla:", tostring(addon.isVanilla),
    "TBC:",     tostring(addon.isTBC),
    "Wrath:",   tostring(addon.isWrath),
    "Cata:",    tostring(addon.isCata),
    "MoP:",     tostring(addon.isMoP)
)
