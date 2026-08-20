-- TOG Profession Master — Tooltip hook
-- Appends crafters to any item tooltip (SetItem / SetHyperlink).
-- Uses AceHook-3.0 (mixed into Ace in TOGProfessionMaster.lua).
-- Only runs when the player is in a guild with data.

local _, addon = ...
local Ace = addon.lib

-- Attempt to locate AceHook-3.0 on the addon object.
-- AceAddon-3.0 mixes it in if listed in the :NewAddon() call; we rely on
-- that rather than require the lib directly.
if not Ace.HookScript then
    addon:DebugPrint("Tooltip: AceHook-3.0 not mixed in — tooltip hooks disabled")
    return
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Extract numeric item ID from a hyperlink, e.g. "|cff...|Hitem:1234:...|h".
local function ItemIdFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Extract item ID from a link or plain itemstring returned by GetItem().
local function ItemIdFromTooltip(tooltip)
    local _, link = tooltip:GetItem()
    return link and ItemIdFromLink(link)
end

-- Return true when the item flags indicate Bind-on-Pickup so we skip BOPs.
local function IsBOP(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = addon.Item.GetInfo(itemID)
    return bindType == 1  -- LE_ITEM_BIND_ON_ACQUIRE
end

-- ---------------------------------------------------------------------------
-- Core lookup
-- ---------------------------------------------------------------------------

-- Returns ordered list {name, profession, skillLevel, maxLevel, online}
-- for every guild member who can craft itemID.
-- Resolve every recipe entry in a profession's recipe table whose crafted
-- item ID equals `itemID`. Has to handle two storage shapes:
--
--   1. Item-keyed (Classic Era pattern): `profRecipes[itemID]` exists with
--      `isSpell=false`. Direct table lookup wins.
--
--   2. Spell-keyed with itemLink (TBC Anniversary pattern): on TBC,
--      `GetTradeSkillRecipeLink` returns `|Henchant:SPELLID|h[...]|h|r` for
--      EVERY profession (not just Enchanting). Scanner.lua's
--      ExtractTradeSkillId matches the `enchant:` prefix first and returns
--      `(spellId, true)`, so the recipe lands under the SPELL ID key with
--      `isSpell=true`. The crafted item ID is still preserved in
--      `rd.itemLink` (the `|Hitem:NNN:` part) — parse it out and match on
--      that. Without this branch, FindCrafters returned nil for every item
--      hover on TBC and the [TOGPM] crafters line silently never appeared.
--
-- Returns the matching `rd`, or nil. Caller (FindCrafters) handles the
-- crafters list extraction.
-- v0.7.0: find every recipe (profId, recipeId) whose craftedItemId matches
-- itemID. Searches the shipped addon.recipeDB (authoritative metadata) —
-- crafter membership for any hits is then looked up in gdb.recipes.
local function ResolveRecipesForItem(itemID)
    local hits = {}
    if not addon.recipeDB then return hits end
    for profId, profRecipes in pairs(addon.recipeDB) do
        for recipeId, meta in pairs(profRecipes) do
            if meta.craftedItemId == itemID then
                hits[#hits + 1] = { profId = profId, recipeId = recipeId }
            end
        end
    end
    return hits
end

local function FindCrafters(itemID)
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.recipes then return nil end

    local GuildRoster = addon.Scanner and addon.Scanner.GuildRoster
    local roster     = {}
    local seen       = {}  -- dedup same (charKey, profId) appearing via multiple recipe matches

    for _, hit in ipairs(ResolveRecipesForItem(itemID)) do
        local profId   = hit.profId
        local recipeId = hit.recipeId
        local profRow  = gdb.recipes[profId]
        local rd       = profRow and profRow[recipeId]
        if rd and rd.crafters then
            for charKey, tag in pairs(rd.crafters) do
                local seenKey = charKey .. "@" .. profId
                if not seen[seenKey] and addon:IsVisibleCrafter(charKey, tag) then
                    seen[seenKey] = true
                    local name      = charKey:match("^(.-)%-") or charKey
                    local skillData = gdb.skills and gdb.skills[charKey] and gdb.skills[charKey][profId]
                    local online    = GuildRoster and GuildRoster:IsOnline(charKey) or false
                    if not online and gdb.altGroups and gdb.altGroups[charKey] then
                        for _, altCk in ipairs(gdb.altGroups[charKey]) do
                            if altCk ~= charKey and GuildRoster and GuildRoster:IsOnline(altCk) then
                                online = true
                                break
                            end
                        end
                    end
                    roster[#roster + 1] = {
                        name       = name,
                        profession = addon.PROF_NAMES[profId] or tostring(profId),
                        skillLevel = skillData and skillData.skillRank or 0,
                        maxLevel   = skillData and skillData.skillMax  or 0,
                        online     = online,
                    }
                end
            end
        end
    end

    if #roster == 0 then return nil end

    -- Online first, then alpha by name
    table.sort(roster, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return roster
end

-- ---------------------------------------------------------------------------
-- Append lines to a GameTooltip frame
-- ---------------------------------------------------------------------------

local HEADER_COLOR  = "|c" .. (addon.BrandColor  or "ffDA8CFF")
local ONLINE_COLOR  = "|c" .. (addon.ColorOnline  or "ffffffff")
local OFFLINE_COLOR = "|c" .. (addon.ColorOffline or "ff888888")
local RESET_COLOR   = "|r"

-- The actual line-appending half of the tooltip hook. Split out from the
-- outer AppendCrafters so the outer can dedup + defer, while this one runs
-- the work after a C_Timer.After(0, ...) — landing AFTER every other
-- addon's same-frame hook (Pawn, Wowhead Looter, AtlasLoot, Auctionator,
-- etc.) so the TOGPM lines sit at the BOTTOM of the tooltip instead of
-- mid-stack between other addons' contributions.
local function AppendCraftersAndIds(tooltip, itemID)
    -- The deferred call may fire after the user has hovered off the
    -- original item. Re-verify the tooltip is still showing the same
    -- item before polluting the new content. Cheap: one GetItem call.
    local _, currentLink = tooltip:GetItem()
    if not currentLink or ItemIdFromLink(currentLink) ~= itemID then return end

    -- Read settings each call — cheap (one table lookup per toggle) and
    -- keeps the toggles reactive without needing to rebuild the hook when
    -- the user flips them. Defaults to false via SETTINGS_DEFAULTS — the
    -- addon stays silent on tooltips until the user opts in via
    -- ESC → Game Menu → Interface → AddOns → TOG Profession Master.
    local showCrafters = Ace.db and Ace.db.profile and Ace.db.profile.tooltipShowCrafters
    local showIds      = Ace.db and Ace.db.profile and Ace.db.profile.tooltipShowIds
    if showCrafters == nil then showCrafters = false end
    if showIds      == nil then showIds      = false end
    if not showCrafters and not showIds then return end

    -- ---- Crafters line (existing) -----------------------------------
    -- Lists every guild crafter who can make this item, online-first.
    -- BOP filter applies here only: BOPs can't be traded/mailed so the
    -- crafters list isn't actionable. IDs line below DOES fire for BOP
    -- items though — useful for debugging "why does TOGPM not show this
    -- item?" (paste the IDs into Wowhead, confirm whether a recipe exists
    -- in the addon's data, etc.).
    local crafters = nil
    if showCrafters and not IsBOP(itemID) then
        crafters = FindCrafters(itemID)
    end
    if crafters then
        local parts = {}
        for _, c in ipairs(crafters) do
            local col = c.online and ONLINE_COLOR or OFFLINE_COLOR
            parts[#parts + 1] = col .. c.name .. RESET_COLOR
        end
        -- |n embeds the blank line inside a single AddLine so it can't be
        -- reordered by the tooltip's internal build order.
        tooltip:AddLine("|n" .. HEADER_COLOR .. "[TOGPM]" .. RESET_COLOR .. " " .. table.concat(parts, ", "),
            1, 1, 1, true)
    end

    -- ---- IDs line (new) ---------------------------------------------
    -- Diagnostic footer in brand colour. Mirrors the grey ID footer added
    -- to BrowserTab row tooltips, but here it's the canonical home: the
    -- global item tooltip fires on every item the user hovers (bags, AH,
    -- chat links, vendor, mailbox, etc.), so the IDs are visible wherever
    -- they're useful for troubleshooting "this icon/link looks wrong".
    -- Shown even when there are no crafters — that case is the most useful
    -- one to debug (paste the itemId into Wowhead, confirm whether the
    -- recipe exists in TOGPM's data, etc.).
    -- The `|n` prefix only fires when there's no crafters line above; with
    -- a crafters line, this sits flush below it (no extra blank in middle).
    if showIds then
        local idParts = { "itemId=" .. itemID }
        -- Best-effort lookup of the matching recipe's spellId from gdb.recipes
        -- — when the item IS a craftable, gdb keys non-spell recipes by the
        -- crafted-item ID, so profRecipes[itemID] gives us the recipe entry.
        -- Also record diagnostic state so we can surface WHY no crafters
        -- line appears when one was expected:
        --   recipe-not-found  : itemID isn't a key in any gdb.recipes[prof]
        --   recipe-isSpell    : key matched but rd.isSpell=true (Enchanting
        --                       recipes are keyed by spell ID, not item ID,
        --                       so an item-ID hover legitimately misses)
        --   recipe-no-crafters: rd exists with isSpell=false but rd.crafters
        --                       is empty (sync hasn't filled it yet, or the
        --                       sole crafter unlearned the recipe)
        --   bop-skipped       : crafters line was suppressed because item is
        --                       Bind-on-Pickup (can't be traded/mailed anyway)
        -- v0.7.0: walk ResolveRecipesForItem (which mines the shipped
        -- addon.recipeDB by craftedItemId) and cross-reference each hit
        -- against gdb.recipes for the crafter count.
        local gdb = addon:GetGuildDb()
        local diag = "recipe-not-found"
        local crafterCount = 0
        -- FIRST hit only, and written as an index rather than a `for ... break`
        -- so that is legible: this is a diagnostic line, and reporting one
        -- recipe's crafter count is the whole intent. luacheck called the old
        -- shape out ("loop is executed at most once") and it was right --
        -- a loop that always breaks reads as if it might not.
        local hit = ResolveRecipesForItem(itemID)[1]
        if hit then
            local meta = addon.recipeDB[hit.profId][hit.recipeId]
            if meta.teaches then table.insert(idParts, "spellId=" .. meta.teaches) end
            local profRow = gdb and gdb.recipes and gdb.recipes[hit.profId]
            local rd      = profRow and profRow[hit.recipeId]
            for _ in pairs((rd and rd.crafters) or {}) do crafterCount = crafterCount + 1 end
            diag = (crafterCount > 0) and ("crafters=" .. crafterCount) or "recipe-no-crafters"
        end
        if not showCrafters then
            diag = "crafters-disabled"
        elseif crafterCount > 0 and not crafters and IsBOP(itemID) then
            -- Crafters exist in gdb but the line was suppressed because BOP.
            diag = "bop-skipped (crafters=" .. crafterCount .. ")"
        end
        table.insert(idParts, diag)
        local idPrefix = crafters and "" or "|n"
        tooltip:AddLine(idPrefix .. HEADER_COLOR .. "[TOGPM]" .. RESET_COLOR
            .. " " .. HEADER_COLOR .. table.concat(idParts, "  ") .. RESET_COLOR,
            1, 1, 1, true)
    end
end

-- ---------------------------------------------------------------------------
-- Recipe-detail block (difficulty + sources) on GAME-BUILT item tooltips
-- ---------------------------------------------------------------------------

-- itemId -> { { profId, recipeId }, ... }, covering BOTH ways an item relates to
-- a recipe: the item a recipe PRODUCES, and the scroll that TEACHES it. A player
-- hovering either one is asking about the same recipe.
--
-- Built once and cached, deliberately. ResolveRecipesForItem above walks every
-- shipped recipe (~1,565 on Vanilla) on each call, which was tolerable while the
-- only caller was the opt-in IDs line -- this block runs on every item tooltip in
-- the game, so an O(n) scan per hover is not. The data is static shipped content
-- loaded at startup, so one build is enough and there is nothing to invalidate.
-- Held on the addon table, not as a file-local, so it invalidates the same way
-- `_craftedItemMap` does when recipeDB is replaced. In game that happens once at
-- load; in the test suite a spec swaps recipeDB per case, and a file-local would
-- cache the first spec's data for the whole run.
local function RecipesForItem(itemID)
    if not addon._recipeItemIndex then
        local index = {}
        addon._recipeItemIndex = index
        local function add(itemId, profId, recipeId)
            if type(itemId) ~= "number" or itemId <= 0 then return end
            local list = index[itemId]
            if not list then list = {}; index[itemId] = list end
            list[#list + 1] = { profId = profId, recipeId = recipeId }
        end
        for profId, profRecipes in pairs(addon.recipeDB or {}) do
            for recipeId, meta in pairs(profRecipes) do
                add(meta.craftedItemId, profId, recipeId)
                -- The teaching scroll. Resolved through ItemLink.TeachingItem so
                -- this index cannot disagree with what the browser's own tooltip
                -- resolves -- it is the same lookup, ProfessionDB first and the
                -- recipe's own meta.itemId second (the latter being the ONLY
                -- source on Wrath / Cata / Mists).
                local scrollId = addon.ItemLink and addon.ItemLink.TeachingItem
                                 and addon.ItemLink.TeachingItem(profId, recipeId)
                if scrollId ~= meta.craftedItemId then add(scrollId, profId, recipeId) end
            end
        end
    end
    return addon._recipeItemIndex[itemID]
end
addon.Tooltip._RecipesForItem = RecipesForItem   -- exposed for specs

--- Should the block render on a tooltip the GAME built?
---
--- The coverage rule, and it is one line: **if we built the tooltip we render
--- the block; if the game built it, RecipeMaster does -- unless RM is not there,
--- in which case we do that too.** RM covers 100% of what it can see (it hooks
--- OnTooltipSetItem) and 0% of ours (a tooltip assembled from AddLine calls
--- carries no item, so its hook never fires), which is why this is a
--- tooltip-TYPE split and needs no per-profession logic.
---
--- **Loaded is not the same as contributing, and we cannot tell.** RM's handlers
--- are gated on its own `showAltsTooltipInfo` / `showSourcesTooltipInfo`
--- settings, which are addon-private -- it writes nothing to `_G`
--- (`local addonName, rm = ...`), so nothing can read them. A player with RM
--- installed and both switched off would get the block from neither addon. That
--- is what "always" is for.
local function RecipeDetailsMode()
    local mode = Ace.db and Ace.db.profile and Ace.db.profile.tooltipRecipeDetails
    return mode or "auto"
end

local function ShouldRenderOnGameTooltip()
    local mode = RecipeDetailsMode()
    if mode == "never"  then return false end
    if mode == "always" then return true  end
    -- Detected by ADDON NAME, not namespace: RM exports nothing to _G.
    return not (addon.IsAddOnLoaded and addon:IsAddOnLoaded("RecipeMaster"))
end
addon.Tooltip._ShouldRenderOnGameTooltip = ShouldRenderOnGameTooltip

local function AppendRecipeDetailsForItem(tooltip, itemID)
    if not ShouldRenderOnGameTooltip() then return end

    -- Gate on recipe-ness FIRST. Every item tooltip in the game reaches here,
    -- so the common case -- grey vendor trash -- must cost one hash lookup and
    -- nothing more.
    local hits = RecipesForItem(itemID)
    if not hits then return end

    -- Same re-verify the crafters path does: a deferred call can land after the
    -- user has hovered off, and appending then writes onto the wrong item.
    local _, currentLink = tooltip:GetItem()
    if not currentLink or ItemIdFromLink(currentLink) ~= itemID then return end

    -- One block, even when several recipes produce this item (different
    -- professions making the same reagent). Rendering the block twice reads as
    -- a bug; the first hit is the one the browser would also have shown.
    local hit = hits[1]
    addon.ItemLink.AppendRecipeDetails(tooltip, hit.profId, hit.recipeId)
end

-- Everything the GLOBAL hook appends, in tooltip order: crafters, IDs, then the
-- recipe block at the bottom.
--
-- Deliberately NOT what `addon.Tooltip.AppendCrafters` points at below. That is
-- BrowserTab's entry point for tooltips WE built, and those must render the
-- recipe block unconditionally -- the RecipeMaster gate applies only to tooltips
-- the game built, which RM can actually see. Routing our own tooltips through
-- here would hand a RecipeMaster user an addon window with the block missing.
local function AppendCraftersNow(tooltip, itemID)
    AppendCraftersAndIds(tooltip, itemID)
    -- Has its own toggle and its own gate, so it must not sit behind the
    -- crafters/IDs early-return: a player with both of those off still gets it.
    AppendRecipeDetailsForItem(tooltip, itemID)
    -- Vendor buy/sell, LAST and unconditional on item type. Every other block
    -- here answers a question about a RECIPE and renders nothing on the vast
    -- majority of items; this one answers a question about the ITEM, so it is
    -- the only part of the TOGPM block that appears on ordinary loot. It has its
    -- own toggle and its own dedup, hence its own call rather than folding into
    -- either of the two above.
    if addon.ItemLink and addon.ItemLink.AppendVendorPrices then
        addon.ItemLink.AppendVendorPrices(tooltip, itemID)
    end
    -- No width capping here. Width is handled by passing the `wrap` flag on
    -- every line we append, which opts into the engine's own preset -- see the
    -- note in GUI/SharedWidgets.lua.
end

-- Dedup wrapper: a single tooltip Show can trigger multiple hook paths
-- (modern PostCall, legacy OnTooltipSetItem, fallback Show-hook). The
-- _togpmAppended==itemID guard collapses them to one append per item per
-- tooltip frame.
--
-- (We previously tried C_Timer.After(0, ...) here to land the lines AFTER
-- any other addon that hooked the same events — Pawn / Wowhead Looter /
-- AtlasLoot — so our content sat at the bottom of the tooltip. In
-- practice that broke rendering entirely: on this client the deferred
-- AddLine fired after the tooltip was already laid out and the new lines
-- never became visible. Reverted to immediate. Tooltip ordering can be
-- revisited later via a different mechanism, e.g. registering the hooks
-- on PLAYER_ENTERING_WORLD with a delay so we're last in the chain.)
local function AppendCrafters(tooltip, itemID)
    if tooltip._togpmAppended == itemID then return end
    tooltip._togpmAppended = itemID
    AppendCraftersNow(tooltip, itemID)
end

-- Exposed so BrowserTab can call it directly on its custom-built tooltips
-- (those paths bypass SetHyperlink so the global hook never fires).
--
-- Points at the crafters/IDs half ONLY, not the composite above. BrowserTab adds
-- the recipe block itself, ungated, because a tooltip we built is one
-- RecipeMaster cannot see.
addon.Tooltip.AppendCrafters = AppendCraftersAndIds

-- Append just the brand-coloured `[TOGPM] itemId=N spellId=N` line, without
-- any crafters lookup. For BrowserTab's spell-only tooltip branches
-- (SetSpellByID, SetText) where the global hook can't fire because there's
-- no item context to extract — but the BrowserTab entry still has the IDs
-- and the user wants them surfaced for troubleshooting just like on item
-- tooltips. Respects the same tooltipShowIds toggle as the global hook so
-- disabling it via Settings hides IDs everywhere consistently.
local function AppendBrandIdsLine(tooltip, itemID, spellID)
    local showIds = Ace.db and Ace.db.profile and Ace.db.profile.tooltipShowIds
    if showIds == nil then showIds = false end
    if not showIds then return end
    local idParts = {}
    if itemID  then table.insert(idParts, "itemId="  .. tostring(itemID))  end
    if spellID then table.insert(idParts, "spellId=" .. tostring(spellID)) end
    if #idParts == 0 then return end
    tooltip:AddLine("|n" .. HEADER_COLOR .. "[TOGPM]" .. RESET_COLOR
        .. " " .. HEADER_COLOR .. table.concat(idParts, "  ") .. RESET_COLOR,
        1, 1, 1, true)
end
addon.Tooltip.AppendBrandIds = AppendBrandIdsLine

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

local function OnTooltipSetItem(tooltip)
    if tooltip._togpmAppended then return end
    local itemID = ItemIdFromTooltip(tooltip)
    if itemID then AppendCrafters(tooltip, itemID) end
end

local function OnTooltipCleared(tooltip)
    tooltip._togpmAppended    = nil
    -- Without this the recipe block renders once and then never again on that
    -- frame -- GameTooltip is reused for every hover in the game, so the flag
    -- would outlive the item it was set for.
    tooltip._togpmRecipeBlock = nil
    -- Same reasoning, and it matters MORE for this one: the vendor block renders
    -- on nearly every item in the game rather than only on recipes, so a flag
    -- left set would suppress it on every subsequent hover of the session.
    tooltip._togpmVendorBlock = nil
end
addon.Tooltip._OnTooltipCleared = OnTooltipCleared   -- exposed for specs

-- Register after PLAYER_LOGIN so SavedVariables are loaded
Ace:RegisterEvent("PLAYER_LOGIN", function()
    -- Branch diagnostic — surface which tooltip path the client supports so
    -- /togpm debug can confirm what was wired up. The two paths share the
    -- AppendCrafters function; the difference is how it gets invoked.
    local hasModern = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
                  and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    addon:DebugPrint("Tooltip: PLAYER_LOGIN hooking; modern path available =",
        tostring(hasModern),
        "TooltipDataProcessor =", tostring(TooltipDataProcessor),
        "Enum.TooltipDataType.Item =", tostring(Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item))

    if hasModern then
        -- MoP Classic+ / Retail / modern-engine Classic flavors: single
        -- post-call fires for every item tooltip.
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            addon:DebugPrint("Tooltip: modern PostCall fired, data.id =", tostring(data and data.id))
            if data and data.id then AppendCrafters(tooltip, data.id) end
        end)
        addon:DebugPrint("Tooltip: registered modern TooltipDataProcessor handler")
    end

    -- Legacy OnTooltipSetItem hook — register UNCONDITIONALLY (not in an
    -- else branch). The modern PostCall path was supposed to replace this
    -- but TBC Anniversary specifically advertises TooltipDataProcessor
    -- (so hasModern=true) without actually firing the PostCall on item
    -- hovers. Without this fallback the entire TOGPM tooltip extension is
    -- silent on TBC Ann. The Show-hook below is a third layer of safety
    -- but it fires after the tooltip is already constructed and uses
    -- GetItem() which has its own client-flavour quirks. The
    -- _togpmAppended dedup in AppendCrafters keeps all three paths from
    -- double-appending the lines.
    local frames = { GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, ShoppingTooltip3 }
    local count = 0
    for _, tt in ipairs(frames) do
        if tt then
            tt:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            tt:HookScript("OnTooltipCleared", OnTooltipCleared)
            count = count + 1
        end
    end
    addon:DebugPrint("Tooltip: registered legacy OnTooltipSetItem hook on", count, "tooltip frames")

    -- Universal fallback: on the modern client engine, OnTooltipSetItem was
    -- deprecated and the modern TooltipDataProcessor enum may not be exposed
    -- on every Classic flavor (TBC Anniversary specifically appears not to fire
    -- the modern path even though it ships TooltipDataProcessor). Hook each
    -- tooltip frame's Show method via hooksecurefunc and use GetItem() to
    -- recover the link — fires AFTER the tooltip has been populated, works
    -- on every client. The _togpmAppended dedup in AppendCrafters keeps us
    -- from doubling up when both this and a primary path fire.
    --
    -- Registration is DEFERRED by ~2 seconds so other tooltip-modifying
    -- addons (Wowhead_Looter, Pawn, AtlasLoot, Auctionator, ...) get to
    -- register THEIR Show-hooks first. hooksecurefunc chains by registration
    -- order — last registered fires last — so this delay ensures TOGPM's
    -- AddLine calls land AT THE BOTTOM of the chain output, below every
    -- other addon's contribution, instead of mid-stack. TOGProfessionMaster
    -- loads alphabetically before Wowhead_Looter (T < W), so without this
    -- delay TOGPM registered first and Wowhead's lines appeared below ours
    -- — exactly what the user reported on TBC Anniversary.
    --
    -- Tradeoff: items hovered in the first ~2 seconds after login won't
    -- get TOGPM lines through this fallback. Modern PostCall and legacy
    -- OnTooltipSetItem (registered immediately above) still fire for early
    -- hovers on clients where those paths work.
    local function RegisterShowHookFallback()
        local fallbackFrames = { GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, ShoppingTooltip3 }
        local fallbackCount = 0
        for _, tt in ipairs(fallbackFrames) do
            if tt and tt.Show then
                hooksecurefunc(tt, "Show", function(self)
                    -- PER-FRAME re-entry guard, on the frame itself. Audit
                    -- finding 11: this was one shared upvalue while the hook is
                    -- installed on FIVE frames, so while GameTooltip was
                    -- re-showing the guard was true for the shopping tooltips
                    -- too and a genuine Show on one of them was dropped. The
                    -- comparison tooltips are exactly the case where two of these
                    -- frames are visible at once.
                    if self._togpmReshowing then return end
                    local _, link = self:GetItem()
                    if not link then return end
                    local itemID = ItemIdFromLink(link)
                    if not itemID then return end
                    -- Dedup against THIS item specifically. The previous check
                    -- (`if self._togpmAppended then return end`) was buggy because
                    -- on the modern client engine, OnTooltipCleared may not fire
                    -- between tooltips — leaving the flag set from a previous item
                    -- and silently swallowing every subsequent hover.
                    if self._togpmAppended == itemID then return end
                    addon:DebugPrint("Tooltip: fallback Show-hook fired for itemID =", itemID)
                    AppendCrafters(self, itemID)
                    -- RE-SHOW, OR THE LINES ARE INVISIBLE.
                    --
                    -- This is a `hooksecurefunc` on Show, so it runs AFTER the
                    -- tooltip has already sized and laid itself out. AddLine
                    -- appends to the tooltip's data but does not re-run layout,
                    -- so on every path where this fallback is the ONLY hook that
                    -- fires -- which on Classic Era 1.15.9 is every bag item --
                    -- our lines were added and never drawn. The addon looked
                    -- completely absent from game tooltips while the debug log
                    -- cheerfully reported the hook firing five times per hover.
                    --
                    -- The comment above about `C_Timer.After(0, ...)` describes
                    -- the identical failure and was written about a different
                    -- call site; the same trap caught this one. Appending after
                    -- layout requires an explicit re-layout, always.
                    self._togpmReshowing = true
                    self:Show()
                    self._togpmReshowing = nil
                end)
                fallbackCount = fallbackCount + 1
            end
        end
        addon:DebugPrint("Tooltip: registered Show-hook fallback on", fallbackCount, "tooltip frames (delayed)")
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(2, RegisterShowHookFallback)
    else
        RegisterShowHookFallback()
    end
end)
