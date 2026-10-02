-- TOG Profession Master — Shared GUI widget factories
--
-- Anywhere we'd otherwise hand-roll the same widget pattern across
-- Browser / Cooldowns / Missing tabs, the factory lives here. Tabs
-- become call-sites (~10 lines) instead of containing ~80 lines of
-- copy-pasted plumbing each.

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

addon.GUI = addon.GUI or {}
addon.UI  = addon.UI or {}
local UI = addon.UI

function UI.Brand(text)
    return "|c" .. (addon.BrandColor or "ffFF8000") .. tostring(text or "") .. "|r"
end

--- Number of entries in a set/map. Tolerates nil, because two of the three
--- private copies this replaced already did and the third (GuildTab's
--- `countSet`) raised — the divergence recorded a concern that had been had
--- twice and not propagated, so the safe behaviour is the one that wins.
function UI.Count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

--- "Name-Realm" → "Name". Falls back to the input, then to "?", so a nil or
--- realmless key renders rather than raising: the AHProfitTab copy guarded and
--- the MissingRecipesTab copy did not.
function UI.ShortName(charKey)
    return (charKey and charKey:match("^([^%-]+)")) or charKey or "?"
end

--- THE SCOPE FILTER — "whose data am I looking at" — as one definition.
---
--- The Professions and Cooldowns tabs each own a `_viewMode` field and each
--- build a View dropdown from it. `CooldownsTab`'s comment said *"Mirrors the
--- Browser tab's `_viewMode` dropdown"*, which is a maintenance contract with
--- nothing enforcing it, and `docs/AUDIT.md` finding 2 predicted the exact way
--- it would break: **one of them gaining a third mode.** That happened — the
--- Browser grew `missing` — and nothing failed, which is the point of the
--- finding. The two are now one base set, one default and one construction.
---
--- `SCOPE_DEFAULT` is deliberately a value rather than a per-tab literal: the
--- prediction was "different default" as well, and a shared constant is what
--- makes both tabs open on the same view by construction instead of by
--- coincidence.
UI.SCOPE_DEFAULT = "guild"

--- Build the `(items, order)` pair an AceGUI Dropdown's `SetList` takes, from
--- the shared base plus whatever extra modes this tab supports.
---
--- BOTH HALVES ARE BUILT TOGETHER, AND THAT IS THE WHOLE POINT. AceGUI walks
--- the ORDER array and calls `AddListItem(key, list[key])` with no existence
--- check (`AceGUIWidget-DropDown.lua:609-611`), and the item's `SetText` does
--- `SetText(text or "")` (`AceGUIWidget-DropDown-Items.lua:101`) — so a key
--- present in the order but missing from the items renders a BLANK, CLICKABLE
--- row rather than erroring. The Browser tab shipped exactly that: a hardcoded
--- `{ "guild", "mine", "missing" }` order against an item table that only gained
--- `missing` when "Show All Recipes" was ticked. A caller of this function
--- cannot reproduce that, because it never writes an order at all.
---
--- @param extra table|nil array of `{ key = "...", label = "..." }`, appended in order
--- @return table items  key → label, for `SetList`'s first argument
--- @return table order  array of keys, for `SetList`'s second argument
function UI.ScopeList(extra)
    local items = { guild = L["ViewGuild"], mine = L["ViewMine"] }
    local order = { "guild", "mine" }
    for _, mode in ipairs(extra or {}) do
        -- Skipped rather than added blank if a caller passes a label-less mode:
        -- the failure this function exists to prevent is precisely a keyed row
        -- with no text, and re-introducing it here would be the worst place for
        -- it — every tab would inherit it at once.
        if mode.key and mode.label then
            items[mode.key] = mode.label
            order[#order + 1] = mode.key
        end
    end
    return items, order
end

--- Put "/w <target> " in the chat box, ready to type.
---
--- Prefers the already-open edit box and falls back to ChatFrame_OpenChat.
--- Shared because BrowserTab and CooldownsTab carried byte-identical copies
--- nested inside their row handlers — chat plumbing with a real fallback path,
--- which is exactly the kind of thing that gets fixed in one copy only.
function UI.OpenWhisper(target)
    if ChatEdit_GetActiveWindow then
        local box = ChatEdit_GetActiveWindow()
        if box then
            box:SetText("/w " .. target .. " ")
            box:SetFocus()
            box:SetCursorPosition(#box:GetText())
            return
        end
    end
    ChatFrame_OpenChat("/w " .. target .. " ", DEFAULT_CHAT_FRAME)
end

-- ---------------------------------------------------------------------------
-- Item links: ONE implementation of clicking and hovering an item, for every
-- surface in the addon.
--
-- There used to be three, and they were not equivalent — which is why a
-- shift-click worked on the Cooldowns tab and did nothing on the Browser tab:
--
--   HandleModifiedItemClick(link)  Cooldowns, Crafting, AH Profit
--   ChatEdit_InsertLink(link)      Browser x3, Reagent Tracker, Compat
--   editBox:Insert(link)           Missing Recipes, Shopping List
--
-- They are not equivalent, and that is what made the addon feel inconsistent.
-- `ChatEdit_InsertLink` and `editBox:Insert` hard-code a shift check instead of
-- asking `IsModifiedClick("CHATLINK")`, so a rebound link modifier did nothing
-- on those seven surfaces, and ctrl-click for the dressing room existed on three
-- tabs and not the rest.
--
-- CORRECTION, recorded because it was wrong here first: an earlier version of
-- this comment claimed `ChatEdit_InsertLink` does not exist on Classic Era
-- because it sits behind `GetCVarBool("loadDeprecationFallbacks")`. It does
-- sit there, but `CVars.lua:912` documents that CVar defaulting to "1" -- the
-- fallback globals load on a stock client, and this addon's own 14 unguarded
-- calls to it have always worked. Unifying is a behaviour fix, not a crash fix.
--
-- `HandleModifiedItemClick` is Blizzard's own router and is the right answer
-- everywhere: it honours the player's CHATLINK and DRESSUP bindings (which are
-- not necessarily shift and ctrl), routes to the social frame when that is what
-- is up, and fills the auction-house search box or an open macro when those have
-- focus. It does NOT open chat that is closed -- it calls
-- ChatFrameUtil.InsertLink, which returns false when no edit box is active
-- (ChatFrameUtilOverrides.lua:6). An earlier version of this comment claimed
-- otherwise.
-- ---------------------------------------------------------------------------
addon.ItemLink = addon.ItemLink or {}
local ItemLink = addon.ItemLink

-- TOOLTIP WIDTH IS NOT OURS TO SET. Two constants and two functions lived here
-- and are deleted:
--
--   TOOLTIP_FRAME_PADDING, DEFAULT_TOOLTIP_MAX_WIDTH,
--   ItemLink.ConstrainTooltipWidth, ItemLink.ReleaseTooltipWidth
--
-- They measured a tooltip's width and forced over-long lines to wrap at it, by
-- writing `SetWidth`/`SetWordWrap` onto `GameTooltipTextLeft%d`. That was the
-- wrong solution to a real problem, and dangerous besides: those fontstrings are
-- shared by every tooltip in the game, so a missed release would have made
-- Blizzard's tooltips and every addon's wrap at OUR number for the session --
-- strictly worse than the `SetMinimumWidth(480)` leak fixed earlier in the same
-- release, because a floor is recoverable and a forced width is not.
--
-- THE ACTUAL MECHANISM: WoW has an engine-side PRESET wrap width, and a line
-- opts into it by passing the `wrap` flag. `AddLine`/`SetText` take it last and
-- it defaults to FALSE (FrameAPITooltipDocumentation.lua:72) -- an unwrapped
-- line ignores the preset and stretches the frame. Pass it on every line we
-- append and the engine applies the right width on every player's machine, at
-- every UI scale, with nothing measured, nothing cached and nothing to release.
--
-- Full write-up, including the misdiagnosis chain, in the harness's
-- `docs/TOOLTIPS.md` (`1e44d10`).
--
-- THE RULE, and there is a spec for it: every line this addon appends passes
-- the wrap flag. Never measure, cap, or hardcode a tooltip width.

--- Route a modified click on an item link exactly as Blizzard's own item
--- buttons do. Returns true when the click was consumed.
---
--- The fallback chain exists for the case where a stripped-down client (or a
--- broken addon) has removed the router; it is deliberately ordered so the
--- deprecated global is LAST and is never assumed to exist.
function ItemLink.Click(link)
    if not link then return false end
    if HandleModifiedItemClick then
        return HandleModifiedItemClick(link) and true or false
    end
    if not IsShiftKeyDown or not IsShiftKeyDown() then return false end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        return ChatFrameUtil.InsertLink(link) and true or false
    end
    if ChatEdit_InsertLink then
        return ChatEdit_InsertLink(link) and true or false
    end
    local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if box then box:Insert(link); return true end
    return false
end

--- Does the player currently want an item comparison shown?
---
--- `IsModifiedClick("COMPAREITEMS")` rather than `IsShiftKeyDown()`, because
--- the compare modifier is a rebindable setting — assuming shift would ignore
--- anyone who has changed it. `alwaysCompareItems` is the CVar that pins the
--- comparison on permanently, and Blizzard checks both together
--- (Blizzard_GameTooltip/Classic/GameTooltip.lua:511).
function ItemLink.WantsCompare()
    if IsModifiedClick and IsModifiedClick("COMPAREITEMS") then return true end
    if GetCVarBool and GetCVarBool("alwaysCompareItems") then return true end
    return false
end

--- Show or hide the side-by-side comparison on `tip` to match the current
--- modifier state. Safe to call repeatedly; that is what makes hold-to-compare
--- work rather than press-before-hover-to-compare.
function ItemLink.SyncCompare(tip)
    if not tip then return false end
    if ItemLink.WantsCompare() then
        if GameTooltip_ShowCompareItem then
            -- The LSP annotation declares no parameters; classic_era's
            -- Blizzard_GameTooltip/Classic/GameTooltip.lua:680 is
            -- GameTooltip_ShowCompareItem(self, anchorFrame).
            ---@diagnostic disable-next-line: redundant-parameter
            GameTooltip_ShowCompareItem(tip)
            return true
        end
        return false
    end
    -- classic_era GameTooltip.lua:492 is GameTooltip_HideShoppingTooltips(self);
    -- the LSP annotation declares no parameters.
    ---@diagnostic disable-next-line: redundant-parameter
    if GameTooltip_HideShoppingTooltips then GameTooltip_HideShoppingTooltips(tip) end
    return false
end

-- `ItemLink.Tooltip(privateTip)` lived here until v1.0.7. It picked between a
-- caller's private tooltip frame and the global one, and existed solely because
-- Missing Recipes had a private frame. That frame is gone, so the function had
-- one caller passing nothing and a body that read `return GameTooltip`. Every
-- surface uses `_G.GameTooltip` directly now — there is no choice left to make,
-- and a named seam over a single global is a decision point pretending to exist.
--
-- Worth keeping the note it carried, because the reasoning still applies: an
-- earlier `useStockItemTooltips` setting was built on the premise that the game
-- has a stock tooltip for a RECIPE. It does not. A trade-skill recipe is a
-- spell, and the only stock recipe tooltips (`SetTradeSkillItem` /
-- `SetCraftItem`) are index-based and valid only while the profession window is
-- open. What the game does have a tooltip for is the recipe's teaching ITEM,
-- which is what `RecipeTooltipSource` below resolves.

--- What a recipe's hover should be built from. Returns one of:
---
---   "item", itemId       -- a real teaching scroll exists; show ITS tooltip and
---                           other addons' hooks contribute for free
---   "synthetic", record  -- no such item exists (trainer-taught); draw the same
---                           scroll SHAPE ourselves from the record's fields
---   nil                  -- a skill-rank book, or a recipe we know nothing about
---
--- The two are exact complements, asserted by ItemDB's builder on every run, so
--- every recipe takes exactly one branch and the list has no seam at the point
--- where real scrolls run out. Roughly two thirds are "item" and one third
--- "synthetic" -- 1,073 vs 572 on Vanilla, 1,453 vs 814 on TBC.
---
--- The synthetic record carries NO item id, by design and by spec upstream: a
--- fabricated id is the field something eventually hands to GetItemInfo or an
--- auction search, and it fails silently because a fictional id is permanently
--- cache-cold. Branch on the returned kind, never on a missing id.
---
--- `record.name` is composed by LibItemDB as its localized prefix plus the
--- client's own spell name, so it is nil for a spell this client does not know
--- and for the gathering lines, which have no real scroll to derive a prefix
--- from. Callers already holding the recipe name should prefer `record.prefix`
--- and compose it themselves.
function ItemLink.RecipeTooltipSource(profId, recipeId)
    if not recipeId then return nil end

    local itemId, isRankBook = ItemLink.TeachingItem(profId, recipeId)
    if isRankBook then return nil end
    if itemId then return "item", itemId end

    local pdb = addon.GetProfessionDB and addon:GetProfessionDB()
    if pdb and pdb.GetSyntheticRecipeScroll then
        local rec = pdb:GetSyntheticRecipeScroll(recipeId)
        if rec then return "synthetic", rec end
    end
    return nil
end

--- The two header lines a recipe-scroll tooltip opens with, for a recipe that
--- has no real scroll — so the tooltip we draw ourselves opens the same way the
--- game's would.
---
--- Returns `title, requiresLine`, either of which may be nil:
---
---   "Plans: Barbaric Shoulders"
---   "Requires Leatherworking (200)"
---
--- The prefix comes from LibItemDB's derived, localized table — never a
--- hardcoded "Plans: ". That mattered more than it looks: frFR is `"Plans : "`
--- with a space before the colon and zhCN uses a full-width colon, so an English
--- table would have been visibly wrong in two locales on day one.
---
--- Falls back to the profession-name form this addon used before ("Tailoring:
--- Azure Silk Gloves") when no prefix is available — the gathering lines have no
--- real scroll for one to be derived from, and Wrath/Cata/Mists have no data yet.
function ItemLink.ScrollHeader(profId, recipeId, recipeName, profName)
    if not recipeName then return nil, nil end

    local pdb  = addon.GetProfessionDB and addon:GetProfessionDB()
    local rec  = (pdb and pdb.GetSyntheticRecipeScroll and recipeId)
                 and pdb:GetSyntheticRecipeScroll(recipeId) or nil
    local prefix = rec and rec.prefix
    if not prefix and pdb and pdb.GetRecipeScrollPrefix and profId then
        prefix = pdb:GetRecipeScrollPrefix(profId)
    end

    local title
    if prefix then
        title = prefix .. recipeName
    elseif profName and profName ~= "" then
        title = profName .. ": " .. recipeName
    else
        title = recipeName
    end

    -- requiredSkill comes from ProfessionDB, NOT from the synthetic record.
    -- LibItemDB MINOR 18 ships it as 1 for every recipe on 8 of 12 skill lines
    -- -- all 104 Tailoring, all 82 Engineering, all 79 Enchanting, all 22 Mining
    -- -- which rendered "Requires Mining (1)" on Smelt Truesilver, a recipe that
    -- needs 230. Raised as a defect on the contract. ProfessionDB has the real
    -- per-recipe value and always has; there was never a reason to prefer the
    -- other one. Omit the line entirely rather than print a number we cannot
    -- stand behind.
    local meta  = addon.GetRecipeMeta and profId and addon:GetRecipeMeta(profId, recipeId)
    local skill = meta and meta.requiredSkill
    local requires
    if skill and skill > 1 and profName and profName ~= "" then
        requires = ("Requires %s (%d)"):format(profName, skill)
    end

    -- Fourth return: whether THIS character meets that skill requirement.
    -- The game colours an unmet requirement red, and it is the single most
    -- useful thing the line says -- "Requires Engineering (190)" in white reads
    -- as satisfied whether or not it is. Read from our own scanned skills
    -- rather than a client API so it is right for the character the tooltip is
    -- about; nil skill data means "cannot say", which renders as met rather
    -- than crying wolf in red on a profession we simply have not scanned.
    local metRequirement = true
    if skill and skill > 1 then
        local gdb     = addon.GetGuildDb and addon:GetGuildDb()
        local charKey = addon.GetCharacterKey and addon:GetCharacterKey()
        local mine    = gdb and gdb.skills and charKey and gdb.skills[charKey]
                        and gdb.skills[charKey][profId]
        if mine and mine.skillRank then metRequirement = mine.skillRank >= skill end
    end

    -- Third return: the scroll's own "Use: Teaches you how to craft X." line.
    -- The game's scroll tooltip always carries one and ours did not, which is
    -- one of the visible differences between the two. Localized and derived
    -- from the TEACHING SPELL's description at build time -- not the scroll
    -- item's, whose Description field is populated for only 60 of 1,073.
    -- Added as a THIRD return rather than folded into the header so existing
    -- two-value call sites keep working unchanged.
    return title, requires, rec and rec.useText or nil, metRequirement
end

--- The quality colour for a crafted item, as an "ffRRGGBB" hex, or nil.
---
--- Recipe rows used to read this out of the cached `itemLink` alone, which is
--- populated only when the client happened to have that item cached when the
--- row was built. So the same recipe was coloured or not depending on what the
--- player had recently seen, and one armour set could render its pieces in
--- different colours -- quality is a fixed property of the item and must never
--- depend on cache state.
---
--- Order matters: a real link is authoritative when present, ItemDB answers
--- offline for everything else, and GetItemInfo is last because it returns nil
--- for a cold item and would otherwise mask ItemDB's shipped answer.
--- @return string|nil hex like "ffa335ee"
function ItemLink.QualityHex(itemLink, itemId)
    if type(itemLink) == "string" then
        local hex = itemLink:match("|c(ff%x%x%x%x%x%x)|H")
        if hex then return hex end
    end
    if type(itemId) ~= "number" then return nil end

    local idb = addon.GetItemDB and addon:GetItemDB()
    if idb and idb.GetLink then
        local link = idb:GetLink(itemId)
        local hex = type(link) == "string" and link:match("|c(ff%x%x%x%x%x%x)|H")
        if hex then return hex end
    end

    -- Last resort, and only useful for an item the client already has cached.
    --
    -- Audit finding 26. BOTH bare names here are DEPRECATION FALLBACKS, assigned
    -- from their C_Item counterparts in Blizzard_DeprecatedItemScript.lua (`:9`
    -- and `:42`) inside a block that returns early unless the
    -- `loadDeprecationFallbacks` CVar is on. With it off both are nil, this
    -- presence guard is false, and the branch is skipped -- so the function
    -- quietly returns nil and a row renders with no quality colour. That is
    -- worse than the raise this same defect caused in MissingRecipesTab,
    -- because it is silent, and it defeats the docstring above: the last resort
    -- never running is another way for the colour to depend on cache state.
    --
    -- Routed through Compat's single resolver rather than resolved again here,
    -- so there is one place that knows which spelling is real. It dispatches at
    -- CALL time and answers nil when neither spelling exists, which is what the
    -- old presence guard was for.
    local Item = addon.Item
    if Item then
        local _, _, quality = Item.GetInfo(itemId)
        if quality then
            local _, _, _, hex = Item.GetQualityColor(quality)
            -- The fourth return is already "ffRRGGBB" on Classic; guard anyway
            -- rather than trusting the shape.
            if type(hex) == "string" and hex:match("^ff%x%x%x%x%x%x$") then return hex end
        end
    end
    return nil
end

--- Source-kind key -> locale key, and the order they display in.
---
--- Canonical: `MissingRecipesTab` and the recipe-detail block below both read
--- these, so adding a kind or changing the order happens in one place. The
--- locale keys keep their `MissingSrc*` names -- they were written for that tab
--- and renaming them would churn twelve locale files to no effect.
ItemLink.SOURCE_LABELS = {
    vendor    = "MissingSrcVendor",
    drop      = "MissingSrcDrop",
    quest     = "MissingSrcQuest",
    crafted   = "MissingSrcCrafted",
    container = "MissingSrcContainer",
    fishing   = "MissingSrcFishing",
    trainer   = "MissingSrcTrainer",
}
ItemLink.SOURCE_ORDER = { "vendor", "drop", "quest", "crafted", "container", "fishing", "trainer" }

--- The recipe-detail block's DATA: skill-up difficulty, and where the recipe
--- comes from. Pure -- returns values, renders nothing -- so the shape can be
--- asserted without a tooltip.
---
--- @return string|nil difficulty  the four colour-coded breakpoints, e.g. the
---         `FormatSkillTiers` string "300 320 330 340" in orange/yellow/green/grey
--- @return table|nil  sources     localized labels, in `SOURCE_ORDER`, or nil
---
--- **`sources` is keyed by RECIPE SPELL, not by item, and that is the whole
--- reason this reads `addon.sourceDB` rather than `LibItemDB:GetSources`.** An
--- item-keyed lookup can only answer for a recipe that HAS a teaching scroll,
--- which excludes every trainer-taught recipe -- 31% of the Vanilla set, and the
--- population most in need of a "where does this come from" line, since there is
--- no scroll to inspect. Measured against the shipped Vanilla data: item-keyed
--- answers for 44.6% of recipes, `sourceDB` for 74.9% (1172 of 1565), and its
--- single largest kind is `trainer` at 508 recipes -- precisely the set the
--- item-keyed lookup structurally cannot see.
---
--- Either return may be nil independently. A recipe with no source data gets no
--- Sources heading rather than a heading over nothing: 25% of recipes have none,
--- and "Sources: (blank)" reads as a bug in the addon rather than a gap in the
--- data. Same reasoning as the `Requires` line, which omits rather than printing
--- a number it cannot stand behind.
function ItemLink.RecipeDetails(profId, recipeId)
    if not profId or not recipeId then return nil, nil end

    local difficulty
    local meta = addon.GetRecipeMeta and addon:GetRecipeMeta(profId, recipeId)
    if meta and (meta.difficulty or meta.requiredSkill) and addon.FormatSkillTiers then
        local tiers = addon.FormatSkillTiers(meta.difficulty, meta.requiredSkill)
        -- FormatSkillTiers answers "-" when it has nothing worth printing; that
        -- is a placeholder for a table cell, not something to head a block with.
        if tiers and tiers ~= "-" then difficulty = tiers end
    end

    local sources
    local entry = addon.sourceDB and addon.sourceDB[profId] and addon.sourceDB[profId][recipeId]
    if entry then
        for _, kind in ipairs(ItemLink.SOURCE_ORDER) do
            local npcs = entry[kind]
            -- A kind present but EMPTY is a real state in this data (the porter
            -- emits the key before it knows any npc), and it must not produce a
            -- label -- that would assert a source we cannot name.
            if npcs and next(npcs) ~= nil then
                local key   = ItemLink.SOURCE_LABELS[kind]
                local label = (key and L[key]) or kind
                sources = sources or {}
                sources[#sources + 1] = label
            end
        end
    end

    return difficulty, sources
end

--- Which of YOUR characters know the profession but not this recipe.
---
--- RecipeMaster's "Unlearned:" section, and the one place we are structurally
--- better placed than it is: RM's spell path covers four skill lines (Mining,
--- Poisons, Engineering, Enchanting) and adds nothing on the rest, silently.
--- This reads our own synced store, which has skills, specialisations and alt
--- groups for **every** profession, so the section answers everywhere.
---
--- Scoped to YOUR characters, not the guild, and deliberately: "who in the guild
--- can make this" is already the crafters line, and a guild-wide unlearned list
--- would be forty names of no use to anyone. The actionable question this
--- answers is "which of my toons could still learn it".
---
--- @return table|nil { { name, skill, spec }, ... } sorted by name, or nil
function ItemLink.UnlearnedBy(profId, recipeId)
    if not profId or not recipeId then return nil end
    local gdb = addon.GetGuildDb and addon:GetGuildDb()
    if not gdb or not gdb.skills then return nil end

    local rd       = gdb.recipes and gdb.recipes[profId] and gdb.recipes[profId][recipeId]
    local crafters = (rd and rd.crafters) or {}

    local out
    for charKey, profs in pairs(gdb.skills) do
        -- Has the profession, is mine, and has NOT learned this recipe. All
        -- three matter: without the skills check every alt would be listed as
        -- "unlearned" on a profession it does not even have.
        if profs[profId] and not crafters[charKey]
           and addon.IsMyCharacter and addon:IsMyCharacter(charKey) then
            local spec
            local specId = gdb.specializations and gdb.specializations[charKey]
                           and gdb.specializations[charKey][profId]
            -- Resolved at runtime, as the Guild tab does. Returns nil for a spell
            -- this client does not know, which is why the name is optional below
            -- rather than assumed.
            if specId then spec = (addon.Spell.GetInfo(specId)) end
            out = out or {}
            out[#out + 1] = {
                name  = charKey:match("^(.-)%-") or charKey,
                skill = profs[profId].skillRank,
                spec  = spec,
            }
        end
    end
    if out then table.sort(out, function(a, b) return a.name < b.name end) end
    return out
end

-- `ItemLink.VendorSellPrice(profId, recipeId)` lived here and is DELETED in
-- v1.0.7, along with the recipe-block row it fed. It answered "what does a vendor
-- pay for this recipe's teaching SCROLL", which was the wrong question twice
-- over: it only ever fired on recipes, and it priced the scroll rather than the
-- item under the cursor.
--
-- `ItemLink.AppendVendorPrices` replaces it and is strictly larger: buy AND sell,
-- for ANY item, on any tooltip. Keeping both printed the same number twice on
-- every recipe-scroll tooltip, which is how it was caught — in game, not here.
--
-- The two facts it recorded are still true and still load-bearing, so they move
-- rather than disappear:
--
--   * SELL and BUY differ by roughly 4x (Schematic: Accurate Scope is 500 to
--     sell, 2000 to buy). Printing one where the other is meant is wrong by a
--     factor of four, not by a rounding error.
--   * `GetItemInfo` returns nil for a cache-cold item, so the sell row went
--     missing exactly when a player met an item for the first time. Reading it
--     starts the client's async fetch, so a second hover lands warm — a
--     mitigation, not a fix. FIXED as of v1.0.7: `LibItemDB:GetVendorSellPrice`
--     IS implemented (LibItemDB-1.0.lua:793, MINOR 22) and is now the second
--     tier of `Price.GetVendorSell`. Three earlier revisions of this comment
--     said it was "designed but not implemented" and told the next reader not
--     to wire it — that claim was repeated for weeks without anyone opening
--     ItemDB's source, which is the actual lesson worth keeping here.

--- Render the recipe-detail block onto a tooltip, in RecipeMaster's shape:
---
---     TOGPM
---     Difficulty
---       300 320 330 340
---     Sources
---       Trainer
---
--- Headings sit flush and the values indent by two spaces. Deliberately NOT
--- `AddDoubleLine` -- that right-aligns the value against the tooltip's widest
--- line, so the numbers jump around depending on what else is on the tooltip.
---
--- Adds nothing at all when there is nothing to say, so a caller can invoke it
--- unconditionally without having to pre-check.
---
--- EVERY line in the block goes through here, so the wrap decision is made in
--- ONE place instead of at fourteen call sites.
---
--- `AddLine`'s fifth argument is `wrapText`, and OMITTING IT MEANS FALSE. A
--- non-wrapping line cannot break, so the tooltip frame grows to fit it — which
--- is how an addon silently makes its tooltip wider than the game's.
---
--- BE HONEST ABOUT THE SIZE OF THIS: most of the block is short and was never
--- going to widen anything. Difficulty is four numbers, the vendor price is a
--- coin string, and a source label is a single localized WORD — "Vendor",
--- "Trainer" — because `RecipeDetails` renders the source KIND and never the NPC
--- names, even though the shipped data has them. The one line that can genuinely
--- run long is an unlearned character: name, realm, skill and specialisation
--- concatenated, one per alt.
---
--- So this is a latent-bug fix, not the answer to a wide tooltip. Wrapping never
--- makes a tooltip narrower — it only stops US being the cause. When the widest
--- line belongs to another addon, this changes nothing, and it was measured
--- doing exactly that.
local function BlockLine(tooltip, text, r, g, b)
    tooltip:AddLine(text, r, g, b, true)
end

--- @param tooltip table the tooltip being built
--- @param profId number|nil the profession that owns the recipe
--- @param recipeId number|nil the recipe's craft SPELL id
--- @return boolean whether any line was added
function ItemLink.AppendRecipeDetails(tooltip, profId, recipeId)
    if not tooltip or not tooltip.AddLine then return false end

    -- "never" is honoured HERE rather than at each call site, so it holds for
    -- our own windows too. The RecipeMaster / "auto" half is not here: it asks
    -- whether the tooltip is one RM can see, which only the caller knows.
    local mode = Ace and Ace.db and Ace.db.profile and Ace.db.profile.tooltipRecipeDetails
    if mode == "never" then return false end

    -- ONE block per tooltip, whatever recipe asked for it. Several paths reach
    -- here for a single hover -- BrowserTab appends explicitly, AND the global
    -- hook fires again on Show() for a tooltip built by SetHyperlink.
    --
    -- Keyed on "has a block been drawn", NOT on the recipe id, and that
    -- distinction is load-bearing: **seven Vanilla items are produced by more
    -- than one recipe** (Gold Bar comes from Alchemy's Transmute Iron to Gold
    -- *and* Mining's Smelt Gold; the Gordok Ogre Suit from both Leatherworking
    -- and Tailoring). On such a row BrowserTab passes the row's own recipe while
    -- the global hook independently resolves the first recipe indexed for that
    -- item -- a different id -- so an id-keyed guard matches neither and draws
    -- the block twice. A tooltip describes one thing; two blocks is always wrong.
    --
    -- Cleared by OnTooltipCleared, which the client fires on SetOwner at the
    -- start of every hover, so a genuinely new hover still renders.
    if tooltip._togpmRecipeBlock then return false end

    local difficulty, sources = ItemLink.RecipeDetails(profId, recipeId)
    local unlearned = ItemLink.UnlearnedBy(profId, recipeId)
    -- `vendorPrice` was a fourth term here. It has to come OUT of this test as
    -- well as out of the render below: leaving it in would let a recipe whose
    -- only fact is a vendor price get past the guard, write the "TOGPM" header,
    -- and then render nothing under it — a heading over an empty section, which
    -- is exactly the failure the sources branch avoids by omitting itself.
    if not difficulty and not sources and not unlearned then
        return false
    end
    tooltip._togpmRecipeBlock = recipeId

    local brand = addon.BrandColor or "ffFF8000"
    BlockLine(tooltip, "|n|c" .. brand .. "TOGPM|r")

    if difficulty then
        BlockLine(tooltip, L["TooltipDifficulty"])
        -- Already colour-coded per tier by FormatSkillTiers, so the line's own
        -- r/g/b must be white or it would tint the escape sequences' fallback.
        BlockLine(tooltip, "  " .. difficulty, 1, 1, 1)
    end

    if sources then
        BlockLine(tooltip, L["TooltipSources"])
        for _, label in ipairs(sources) do
            -- A single localized kind word — see RecipeDetails. Short, and
            -- wrapped only so every line in the block goes through one helper.
            BlockLine(tooltip, "  " .. label, 1, 1, 1)
        end
    end

    -- Directly under Sources on purpose: "Vendor" as a source and "what the
    -- vendor charges" are halves of one answer, and splitting them across the
    -- block would make a reader hunt for the second half.
    -- The scroll-specific "Vendor Sell Price" row that used to sit here is GONE
    -- as of v1.0.7. `AppendVendorPrices` renders Buy and Sell for the item the
    -- player is actually hovering, on EVERY item rather than only on recipes, so
    -- keeping this printed the same number twice on any recipe-scroll tooltip:
    --
    --     Vendor Sell Price        <- this row, the scroll's sellPrice
    --       17s 50c
    --     Vendor                   <- AppendVendorPrices, the same item
    --       Sell  17s 50c
    --
    -- Observed in game, not reasoned about. The surviving one is strictly better:
    -- it answers for the hovered item rather than for the teaching scroll, and it
    -- carries the buy price too.

    if unlearned then
        -- The trailing colon is RecipeMaster's, on this heading only -- its own
        -- Difficulty and Sources headings have none. Matched rather than
        -- normalised: the point of the block is that a player reads one coherent
        -- section whichever addon drew it, and our tidier version would be the
        -- thing that looked out of place.
        -- Red, and the same red as "Already known" one block up (Blizzard's
        -- RED_FONT_COLOR, 1/0.13/0.13) rather than a second hand-picked one.
        -- The two lines are opposites -- known here, not known there -- so a
        -- player reading both should see one palette, not two.
        BlockLine(tooltip, L["TooltipUnlearned"], 1, 0.13, 0.13)
        for _, c in ipairs(unlearned) do
            local detail = c.skill and L["TooltipSkill"]:format(c.skill) or nil
            if detail and c.spec then detail = detail .. ", " .. c.spec
            elseif c.spec         then detail = c.spec end
            -- Name + realm + skill + specialisation: the ONLY line in this block
            -- long enough to widen a tooltip on its own, and the reason the wrap
            -- flag is worth having at all.
            BlockLine(tooltip, "  " .. c.name .. (detail and (" (" .. detail .. ")") or ""), 1, 1, 1)
        end
    end

    return true
end


--- Vendor BUY and SELL price for ANY item, on any tooltip.
---
--- Not part of the recipe block, and that is the point. `AppendRecipeDetails`
--- answers a question about a RECIPE and renders nothing for the other 99% of
--- items in the game; this answers a question about an ITEM, so it fires on
--- Roasted Quail and grey trash and a sword, wherever the tooltip came from.
---
--- WHY THIS IS WORTH SHIPPING: no other addon shows both halves.
---   * TradeSkillMaster shows `Vendor Sell Price` and no buy price.
---   * AllTheThings shows neither.
---   * The game itself shows neither on a bag tooltip.
--- Buy and sell together is the pair a player actually reasons with — "can I
--- buy this cheaper than making it" needs buy, "is this worth bag space" needs
--- sell — and we already hold both.
---
--- THE TWO NUMBERS COME FROM DIFFERENT PLACES AND ARE NOT INTERCHANGEABLE:
---   * SELL is `Price.GetVendorSell`, two tiers: `GetItemInfo`'s eleventh
---     return, then LibItemDB's static `GetVendorSellPrice`. The client value
---     is nil on a cache-cold item — the hole that used to blank this row on
---     first acquaintance with an item — and the static table has no such
---     state, so the row now renders on the first hover. Nil only for an item
---     with no sell value at all (a quest item, a token).
---   * BUY is `Price.GetVendorBuy`, a three-tier ladder: Auctionator's vendor
---     cache, then our own live MERCHANT_SHOW capture, then LibItemDB's static
---     base price. The first two reflect what THIS player is actually charged
---     including reputation discount; the static tier is the Neutral base and
---     is deliberately last. Nil for anything no vendor sells, which is most
---     drops and quest rewards — and nil is the correct answer there, not zero.
---
--- Deliberately NOT stack-multiplied. TSM prints `Vendor Sell Price x20` by
--- reading the hovered bag slot's stack count; a tooltip hook is handed an item
--- id and no slot, so the count is not available here without hooking the bag
--- frames as well. Unit price is honest; a wrong multiplier would not be.
---
--- @return boolean whether any line was added
function ItemLink.AppendVendorPrices(tooltip, itemId)
    if not tooltip or not tooltip.AddLine or type(itemId) ~= "number" then return false end

    local show = Ace and Ace.db and Ace.db.profile and Ace.db.profile.tooltipVendorPrices
    if show == false then return false end

    -- One block per tooltip. Several paths reach a single hover (the modern
    -- post-call, the legacy OnTooltipSetItem, the Show fallback), and the same
    -- dedup reasoning as the recipe block applies: two price blocks is a bug.
    if tooltip._togpmVendorBlock then return false end

    local money = addon.Price and addon.Price.Money
    if not money then return false end

    local buy  = addon.Price.GetVendorBuy and addon.Price.GetVendorBuy(itemId)
    -- Both halves now go through `Price`, which is the point: the sell number
    -- used to be read straight off `GetItemInfo` HERE, so a cache-cold item
    -- rendered no sell row at all. `Price.GetVendorSell` tries the same client
    -- value first and falls through to LibItemDB's static table, which is
    -- always populated. Feature-detected, so this is nil-safe against an older
    -- Price module the same way `GetVendorBuy` already was.
    local sell = addon.Price.GetVendorSell and addon.Price.GetVendorSell(itemId)
    -- 0 is a real answer for an item a vendor will not buy and must not render
    -- as a price, hence a type check rather than a truthiness test. Both
    -- accessors already screen it; this is the belt to their braces, and cheap.
    if type(sell) ~= "number" or sell <= 0 then sell = nil end
    if type(buy)  ~= "number" or buy  <= 0 then buy  = nil end
    if not buy and not sell then return false end

    tooltip._togpmVendorBlock = itemId

    local brand = addon.BrandColor or "ffFF8000"
    -- ATTRIBUTION, and it is conditional on purpose. On a recipe the block sits
    -- under the "TOGPM" header `AppendRecipeDetails` already wrote, and a second
    -- one would read as two separate addons. On ordinary loot -- Roasted Quail, a
    -- sword, grey trash -- the recipe block renders NOTHING, so this section is
    -- the whole of our contribution and would otherwise appear as an unattributed
    -- "Vendor" heading from nowhere. `_togpmRecipeBlock` is set by that function
    -- and is exactly the "did we already brand this tooltip" signal.
    if not tooltip._togpmRecipeBlock then
        BlockLine(tooltip, "|n|c" .. brand .. "TOGPM|r")
    end

    -- TWO INDEPENDENT HEADINGS, each with its value indented beneath — the same
    -- shape as Difficulty and Sources, because these are siblings of those
    -- rather than a nested pair. Either can be absent on its own: a drop has a
    -- sell price and no buy price, and a cache-cold item has the reverse.
    --
    -- Deliberately NOT `AddDoubleLine`, matching the rest of the block: a double
    -- line right-aligns its value against the tooltip's widest line, so the
    -- numbers would jump around depending on what ATT or TSM put above them.
    if buy then
        BlockLine(tooltip, L["TooltipVendorBuyPrice"])
        BlockLine(tooltip, "  " .. money(buy), 1, 1, 1)
    end
    if sell then
        BlockLine(tooltip, L["TooltipVendorPrice"])
        BlockLine(tooltip, "  " .. money(sell), 1, 1, 1)
    end
    return true
end

--- The full TOGPM block for a recipe tooltip, wherever that tooltip was built.
---
--- One entry point so every tab renders the same thing in the same order. The
--- tabs disagreed for a structural reason rather than an oversight: the global
--- `OnTooltipSetItem` hook fires only on `GameTooltip` and only when it carries
--- an ITEM, so a recipe shown as a **spell** (`SetSpellByID`, `spell:` link), as
--- plain **text**, or on a tab's own **private** tooltip frame inherited nothing.
--- That is four of the seven tabs.
---
--- Safe to call on `GameTooltip` even though the hook also fires there:
--- `AppendRecipeDetails` renders at most one block per tooltip. It does NOT
--- reset that guard -- a caller drawing into a private frame must clear
--- `tooltip._togpmRecipeBlock` itself, because nothing else will (the reset
--- lives on the `OnTooltipCleared` hook, which private frames deliberately
--- do not have).
---
--- `profId` and `craftedItemId` are both OPTIONAL and resolved from the recipe
--- when omitted, so a caller holding only a spell id -- which is all the
--- Cooldowns, Shopping List, Crafting and Profit Planner rows carry -- can call
--- this without plumbing a profession through four tabs' row builders. Pass them
--- when you have them; it skips the lookup.
---
--- @param tooltip table the tooltip being built
--- @param profId number|nil profession that owns the recipe (resolved if nil)
--- @param recipeId number|nil the recipe's craft SPELL id
--- @param craftedItemId number|nil what it produces (resolved if nil)
function ItemLink.AppendRecipeBlocks(tooltip, profId, recipeId, craftedItemId)
    if not tooltip or not tooltip.AddLine or not recipeId then return end

    profId = profId or ItemLink.ProfessionForRecipe(recipeId)
    if not craftedItemId then
        local meta = addon.GetRecipeMeta and profId and addon:GetRecipeMeta(profId, recipeId)
        craftedItemId = meta and meta.craftedItemId
    end

    -- INTEGRATIONS FIRST, OUR BLOCK LAST. That is the order a normal game
    -- tooltip produces and the whole point of this function is that ours looks
    -- the same: on GameTooltip the third parties attach during SetItemByID and
    -- our OnTooltipSetItem hook fires after them, so TOGPM lands at the bottom.
    -- Calling ours first here inverted that on every tab that routes through
    -- this function, putting our block above ATT / TSM / RecipeMaster.
    --
    -- Also load-bearing for FAILURE containment, which is how this was found: a
    -- raise inside our block used to abort before the integrations ran, so one
    -- bug in our code silently deleted every other addon's contribution from
    -- the tooltip. With ours last, the third-party content is already on screen
    -- before we can break anything.
    ItemLink.AppendIntegrations(tooltip, recipeId, craftedItemId)
    ItemLink.AppendRecipeDetails(tooltip, profId, recipeId)
end

--- Which profession owns a recipe, given only its craft spell id.
---
--- Built once and cached on the addon table, the same way Tooltip.lua's
--- item -> recipe index is, and invalidated the same way when `recipeDB` is
--- replaced. In game that happens once at load; the test env clears it per spec.
---
--- Returns nil for a spell no shipped recipe uses, which is the normal answer on
--- a cooldown row for something that is not a craft.
function ItemLink.ProfessionForRecipe(recipeId)
    if not recipeId then return nil end
    if not addon._recipeProfIndex then
        local index = {}
        addon._recipeProfIndex = index
        for profId, recipes in pairs(addon.recipeDB or {}) do
            for spellId in pairs(recipes) do
                -- First writer wins. A spell in two professions is real (Smelt
                -- Gold is Mining, Transmute Iron to Gold is Alchemy -- different
                -- spells) but a genuinely shared id would be arbitrary either
                -- way, and the block describes one recipe.
                if index[spellId] == nil then index[spellId] = profId end
            end
        end
    end
    return addon._recipeProfIndex[recipeId]
end

--- Run `fn` with the wrap flag FORCED ON for every line added to `tooltip`,
--- whoever adds it, then put the tooltip's methods back exactly as they were.
---
--- THE RULE THIS ENFORCES: a tooltip's width is an engine-side preset that
--- already accounts for the player's resolution, UI scale and font, and the wrap
--- flag is how a line asks for it. Its documented default is FALSE
--- (`FrameAPITooltipDocumentation.lua:72`), so an unwrapped line does not merely
--- fail to wrap -- it ignores the preset and stretches the frame, dragging every
--- other addon's content out with it. Full write-up in the shared harness at
--- `Tests/wowapi/docs/TOOLTIPS.md`.
---
--- Our own lines all pass the flag and a spec sweeps our source for it
--- (`Tests/tooltipwrapflag_spec.lua`). That spec can only ever read OUR files,
--- and it is structurally blind to the case that actually shipped wide: a THIRD
--- PARTY rendering into a tooltip we own. AllTheThings' row renderer passes the
--- flag only when the entry it is drawing sets `entry.wrap`
--- (`AllTheThings/src/Modules/Tooltip.lua:665-678`), and source breadcrumbs do
--- not set it, so they land as a bare `tooltip:AddLine(left)`. Measured on
--- Advanced Target Dummy by this addon's own width probe and already written
--- down at `TOGProfessionMaster.lua:1370`: ATT's breadcrumb at 583.1px against a
--- 603.6px frame, the difference being the template's 10px inset per side.
---
--- Doing this per integration would mean re-implementing each addon's renderer
--- against internals we do not own, once per addon, forever -- and it silently
--- misses the ones we never enumerate, which is precisely what
--- `ApplyExternalTooltipHooks` replays. A shim on the tooltip is the rule
--- instead: anything that draws while we are inside our block opts into the
--- preset whether it knows the flag exists or not.
---
--- Why this is safe on the SHARED GameTooltip, given that writing to the shared
--- `GameTooltipTextLeft%d` fontstrings is exactly the mistake `docs/AUDIT.md`
--- findings 8-11 deleted:
---
---  * It replaces METHODS ON ONE TOOLTIP TABLE, not properties on fontstrings
---    every tooltip in the game shares. Frame methods resolve through a
---    metatable, so assigning `tooltip.AddLine` shadows it and assigning nil
---    restores the real one -- there is no saved-state to get wrong and nothing
---    to leak into the next tooltip.
---  * It is installed and removed AROUND ONE SYNCHRONOUS CALL. Nothing can
---    observe the shim except the code we invoked, which is the code we want it
---    to apply to.
---  * The restore is in a `pcall` epilogue, so a third party raising mid-render
---    cannot leave the shim installed.
---  * No width is measured, computed or stored. There is no number here at all.
---
--- `AddDoubleLine` is deliberately untouched: it has no wrap parameter (eight
--- arguments, two strings and six colour components -- audit finding 18), so
--- forcing a ninth would be passing a boolean into nothing.
---
--- @param tooltip table the tooltip being built
--- @param fn function called with `tooltip`; may raise, may be third-party code
--- @return boolean ok false when `fn` raised (its error is swallowed, as before)
function ItemLink.WithWrappedLines(tooltip, fn)
    if type(tooltip) ~= "table" or type(fn) ~= "function" then return false end

    local hadAddLine = rawget(tooltip, "AddLine")
    local hadSetText = rawget(tooltip, "SetText")
    local realAddLine = tooltip.AddLine
    local realSetText = tooltip.SetText

    -- The flag is the LAST parameter of each method and its slot is fixed:
    -- `AddLine(text, r, g, b, wrap)` and `SetText(text, r, g, b, a, wrap)`.
    -- Forcing it by position is why a caller passing four colour components to
    -- AddLine cannot push it past the slot.
    -- The `redundant-parameter` disables are the language server reading the
    -- harness's 5-argument stub, not the client. `wrap` is a documented
    -- parameter of both methods -- `FrameAPITooltipDocumentation.lua:72`.
    if type(realAddLine) == "function" then
        tooltip.AddLine = function(self, text, r, g, b)
            ---@diagnostic disable-next-line: redundant-parameter
            return realAddLine(self, text, r, g, b, true)
        end
    end
    if type(realSetText) == "function" then
        tooltip.SetText = function(self, text, r, g, b, a)
            ---@diagnostic disable-next-line: redundant-parameter
            return realSetText(self, text, r, g, b, a, true)
        end
    end

    local ok = pcall(fn, tooltip)

    -- Restore by assigning back what was there, which for a real frame is nil --
    -- i.e. uncover the metatable method rather than pin a Lua copy of it in
    -- front of it forever.
    tooltip.AddLine = hadAddLine
    tooltip.SetText = hadSetText

    return ok
end

--- Everything OTHER addons would have contributed if this tooltip carried an item.
---
--- This is the whole difference between our hand-built recipe tooltip and the
--- game's. A tooltip built from AddLine calls has no item, so `OnTooltipSetItem`
--- never fires -- and that single hook is how AllTheThings, TOGBankClassic and
--- TradeSkillMaster all attach. On the ~65% of recipes with a real teaching
--- scroll we call SetHyperlink and get all three for free; on the trainer-taught
--- third we get none of them, and the two tooltips look nothing alike.
---
--- None of the three offers a "render your block into my tooltip" entry point
--- except ATT, so the other two are re-rendered here from data this addon
--- already reads. That is a deliberate duplication of their layout, and it will
--- drift if they restyle -- the alternative is the trainer-taught third of every
--- profession staying visibly second-class, which is worse.
---
--- Every step is independently guarded: any of the three being absent, disabled
--- or mid-load leaves the tooltip exactly as it was.
---
--- @param tooltip table the tooltip being built (already has lines)
--- @param spellId number|nil the recipe's craft spell id -- ATT is keyed by this
--- @param craftedItemId number|nil the item the recipe produces, for bank + price
function ItemLink.AppendIntegrations(tooltip, spellId, craftedItemId)
    if not tooltip or not tooltip.AddLine then return end
    local brand = addon.BrandColor or "ffFF8000"

    -- 1. AllTheThings. The only one with a real API for this, and it lives in
    -- LibItemDB rather than LibProfessionDB -- the recipe-scroll move left it
    -- behind, which ItemDB caught. Keyed by SPELL, so it also answers for
    -- recipes that have no scroll item at all: exactly this case.
    if type(spellId) == "number" then
        local idb = addon.GetItemDB and addon:GetItemDB()
        if idb and idb.AttachExternalRecipeInfo then
            -- Returns whether it actually added lines; it pcalls into ATT
            -- internally, so a broken/updated ATT cannot take the tooltip down.
            -- Wrapped again here anyway: "the library pcalls internally" is a
            -- guarantee about the library's CURRENT code, and this is the one
            -- place a third-party addon's code runs inside our render.
            --
            -- ⚠ AND WRAPPED IN THE LINE SHIM, which is the actual width fix:
            -- ATT's renderer omits the wrap flag on its breadcrumb lines, and
            -- one unwrapped line stretches the whole frame. Doing that per
            -- integration would mean re-implementing each addon's renderer;
            -- the shim makes it a rule instead. See `WithWrappedLines`.
            ItemLink.WithWrappedLines(tooltip, function(tt)
                idb:AttachExternalRecipeInfo(tt, spellId)
            end)
        end
    end

    -- 1b. Every OTHER addon, via ItemDB's universal bridge. `HookScript`
    -- composes, so GameTooltip's OnTooltipSetSpell chain is one function that
    -- calls every installed addon's handler in turn -- and each handler
    -- operates on the tooltip it is PASSED. Replaying that chain is the only
    -- way to reach an addon that exposes no API at all: RecipeMaster keeps its
    -- entire namespace private (`local addonName, rm = ...`, zero _G writes),
    -- so there is nothing to call into.
    --
    -- Keyed on the SPELL chain, not the item one, because that is the half
    -- that can answer for a recipe with no teaching item -- which is the whole
    -- population this function exists for.
    --
    -- Returns false when no chain exists or a handler declined; that is not an
    -- error and there is nothing to do about it.
    --
    -- ⚠ THIS IS WHERE OTHER ADDONS' CODE RUNS INSIDE OUR RENDER, so it is
    -- pcall'd. Replaying a hook chain means executing handlers we did not write,
    -- against a tooltip they were not expecting — one built from AddLine calls,
    -- carrying no item and no spell. A handler that assumes its own cache is
    -- populated raises, and without the pcall that raise aborts OUR block and
    -- everything after it. That is not hypothetical: it is the same failure
    -- shape as the v1.0.7 bug where a raise inside our block silently deleted
    -- ATT, TSM and RecipeMaster from the tooltip, and it is the reason the
    -- Missing Recipes tab was given a private tooltip frame in v0.7.5.
    --
    -- Isolating the CALL rather than the FRAME is the better answer: it protects
    -- every tab instead of one, it survives a third party changing its code, and
    -- it does not cost a second tooltip frame that then has to be kept the same
    -- width as the game's.
    --
    -- Same shim as the ATT call above, and this path needs it MORE: replaying a
    -- hook chain runs handlers from addons we cannot enumerate, so there is no
    -- list of renderers to fix one at a time. Whatever draws here opts into the
    -- preset whether its author knew the flag existed or not.
    do
        local idb = addon.GetItemDB and addon:GetItemDB()
        if idb and idb.ApplyExternalTooltipHooks then
            ItemLink.WithWrappedLines(tooltip, function(tt)
                idb:ApplyExternalTooltipHooks(tt, "OnTooltipSetSpell")
            end)
        end
    end

    if type(craftedItemId) ~= "number" then return end

    -- 2. TOGBankClassic. It now exposes the renderer itself, so prefer it:
    -- one implementation of the layout, and it cannot drift from what TOGBank
    -- draws on an ordinary item tooltip. (DEPENDENCY_CONTRACTS.md §1, delivered
    -- 2026-08-08.) It pcalls nothing internally, so wrap it here -- this is
    -- another addon's code running inside our render, same rule as ATT above.
    local tbi = _G["TOGBankClassic_TooltipBankerInfo"]
    if tbi and tbi.AppendTo then
        -- Shimmed for the same reason as the two above: it is another addon's
        -- renderer drawing into a tooltip we own.
        ItemLink.WithWrappedLines(tooltip, function(tt)
            tbi:AppendTo(tt, craftedItemId)
        end)

    -- Fallback for a TOGBankClassic older than that contract: rebuild the block
    -- from addon.Bank, which reads the same TOGBankClassic_Guild data. Mirrors
    -- its heading + AddDoubleLine shape. Kept rather than dropped because the
    -- two addons update independently and a player may have either installed.
    elseif addon.Bank and addon.Bank.GetBanksWithItem then
        local banks = addon.Bank.GetBanksWithItem(craftedItemId)
        if banks and #banks > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine("TOGBankClassic", 1, 0.82, 0, true)
            tooltip:AddLine("Bankers:", 0.4, 0.8, 1, true)
            for _, bank in ipairs(banks) do
                tooltip:AddDoubleLine(bank.name, tostring(bank.count), 1, 1, 1, 1, 1, 1)
            end
        end
    end

    -- 3. Prices, through ItemDB's integration registry rather than rendered
    -- here. This used to reach into addon.Price and lay the rows out itself,
    -- which meant duplicating TSM's labels and guessing its shape. ItemDB owns
    -- every third-party bridge now, so this asks once and gets whichever
    -- providers the player actually has -- TSM, Auctionator, or neither.
    local idb = addon.GetItemDB and addon:GetItemDB()
    if not (idb and idb.GetExternalPrices and idb.GetLink) then return end

    -- The registry keys off LINKS, not ids: passing an id silently returns
    -- nothing, so resolve one first and bail if we cannot.
    local link = idb:GetLink(craftedItemId)
    if type(link) ~= "string" then return end

    local byProvider = idb:GetExternalPrices(link)
    if not byProvider then return end

    -- Sorted so the block does not reorder itself between hovers -- pairs()
    -- over the provider table would.
    local providers = {}
    for name in pairs(byProvider) do providers[#providers + 1] = name end
    table.sort(providers)

    local money = _G.GetCoinTextureString
    for _, name in ipairs(providers) do
        tooltip:AddLine(" ")
        tooltip:AddLine("|c" .. brand .. name .. "|r", nil, nil, nil, true)
        for _, row in ipairs(byProvider[name]) do
            -- `formatted` only where the provider supplies its own money
            -- formatting (TSM does, Auctionator does not), so fall back to
            -- ours rather than assuming it is there.
            local shown = row.formatted
                or (money and row.value and money(row.value))
                or tostring(row.value)

            -- `row.label` IS THE ONE STRING HERE WE DO NOT CONTROL. It arrives
            -- from third-party price providers through ItemDB -- TSM and
            -- Auctionator -- so unlike every other line in this file its length
            -- cannot be bounded by reading our own source.
            --
            -- `AddDoubleLine` has no wrap parameter (eight arguments, two strings
            -- and six colour components), so a long label cannot opt into the
            -- engine's preset and would widen the whole tooltip. Audit finding 18.
            --
            -- Above the threshold we drop to the two-line `AddLine` form, which
            -- CAN wrap. The label and value stop sharing a row, which is a small
            -- cosmetic loss and strictly better than a provider we do not own
            -- deciding how wide every tooltip in the game is. 40 characters is
            -- comfortably longer than every label these providers ship today
            -- ("Market Value", "Region Sale Avg", "DBRegionMarketAvg"), so the
            -- branch is inert in practice and exists for the day it is not.
            local label = tostring(row.label or "")
            if #label > 40 then
                tooltip:AddLine(label, 0.4, 0.8, 1, true)
                tooltip:AddLine("  " .. shown, 1, 1, 1, true)
            else
                tooltip:AddDoubleLine(label, shown, 0.4, 0.8, 1, 1, 1, 1)
            end
        end
    end
end

-- Rows register here while hovered, so a modifier pressed DURING the hover
-- re-evaluates. Blizzard's own frames re-check the modifier when the tooltip is
-- built and never again, so without this the comparison only appears if the key
-- was already down before the mouse arrived — which is not what the game does
-- from a bag slot, and not what the request asked for.
local hovered = nil
local modifierWatcher = nil

local function ensureModifierWatcher()
    if modifierWatcher then return modifierWatcher end
    modifierWatcher = CreateFrame("Frame")
    modifierWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    modifierWatcher:SetScript("OnEvent", function()
        if not (hovered and hovered.tip and hovered.tip:IsShown()) then return end
        -- `rebuild` exists for the curated tooltips. A tooltip assembled out of
        -- AddLine calls has no ITEM attached, so GameTooltip_ShowCompareItem has
        -- nothing to compare against and the modifier would appear to do
        -- nothing. Those surfaces hand us a rebuild function that redraws the
        -- row for the current modifier state — showing the real item tooltip
        -- while the key is held, and going back to the trimmed one on release.
        if hovered.rebuild then
            hovered.rebuild()
            return
        end
        ItemLink.SyncCompare(hovered.tip)
    end)
    return modifierWatcher
end

--- Note that `tip` is showing an item so the modifier watcher can update it.
---
--- `rebuild` is optional and only needed by a surface whose tooltip is
--- hand-built; see the comment in the watcher above. It must re-render the
--- tooltip for the CURRENT modifier state and is responsible for calling
--- BeginHover again if it still wants updates.
function ItemLink.BeginHover(tip, rebuild)
    if not tip then return end
    ensureModifierWatcher()
    hovered = { tip = tip, rebuild = rebuild }
    if not rebuild then ItemLink.SyncCompare(tip) end
end

--- Stop tracking; call from OnLeave alongside hiding the tooltip.
function ItemLink.EndHover(tip)
    if tip and GameTooltip_HideShoppingTooltips then
        -- (self) in classic_era GameTooltip.lua:492; the annotation is wrong.
        ---@diagnostic disable-next-line: redundant-parameter
        GameTooltip_HideShoppingTooltips(tip)
    end
    hovered = nil
end

--- Test seam: what the watcher currently considers hovered.
function ItemLink._Hovered() return hovered end

--- Populate `tip` with an item, by link when we have one and by id otherwise,
--- then keep the comparison in sync. Returns true when something was shown.
---
--- Link is preferred over id because a link carries enchants, suffixes and the
--- quality colour; SetItemByID re-resolves the base item and loses them.
function ItemLink.SetItem(tip, link, itemId)
    if not tip then return false end
    if link then
        tip:SetHyperlink(link)
    elseif itemId and tip.SetItemByID then
        tip:SetItemByID(itemId)
    elseif itemId then
        tip:SetHyperlink("item:" .. itemId)
    else
        return false
    end
    ItemLink.BeginHover(tip)
    return true
end

--- The item that TEACHES a recipe — the "Pattern: X" / "Plans: X" scroll — or nil
--- when the recipe is trainer-taught and no such item exists.
---
--- Not wired into any tooltip yet. This is the resolver the scroll-link tooltip
--- would sit on, specced first so the swap is a decision about looks rather than
--- a gamble on whether the data is there.
---
--- **nil is a real and common answer, not missing data.** ItemDB measured it at
--- 572 of 1,645 Vanilla recipes and 814 of 2,267 on TBC — roughly a third are
--- trainer-taught. Any caller MUST have a fallback.
---
--- Two sources, in this order, and both are load-bearing:
---
---   1. `LibItemDB:GetRecipeItem(spellID)` (MINOR 17+). Authoritative: built from
---      `ItemEffect -> SpellEffect[Effect = 36].EffectTriggerSpell`, so it is DBC
---      truth and locale-independent. Ships Vanilla and TBC only, today.
---   2. LibProfessionDB's `meta.itemId`. Covers Wrath / Cata / Mists, which ItemDB
---      has not generated yet — without this the feature would silently do nothing
---      on three of the five flavours this addon supports.
---
--- `isRankBook` is the second return and matters: *Expert Fishing - The Bass and
--- You* genuinely teaches a spell, so the DBC join resolves it correctly, but it
--- is a skill-RANK book rather than a recipe. Callers listing recipes should skip
--- those. Classified from data by ItemDB, so no string-matching on titles.
function ItemLink.TeachingItem(profId, recipeId)
    if not recipeId then return nil, false end

    -- ProfessionDB, not ItemDB. The recipe-scroll mapping moved there at
    -- ProfessionDB MINOR 8 / v1.5.0, because it is keyed by craft spell id
    -- exactly as recipes are. ItemDB still answers GetLink for the resulting id.
    local pdb = addon.GetProfessionDB and addon:GetProfessionDB()
    if pdb and pdb.GetRecipeItem then
        local itemId, isRankBook = pdb:GetRecipeItem(recipeId)
        if itemId then return itemId, isRankBook and true or false end
    end

    local meta = addon.GetRecipeMeta and profId and addon:GetRecipeMeta(profId, recipeId)
    if meta and meta.itemId and meta.itemId > 0 then return meta.itemId, false end

    return nil, false
end

-- ---------------------------------------------------------------------------
-- Saved scroll positions
-- ---------------------------------------------------------------------------
-- Every tab's list survives the sync-triggered ReleaseChildren+Draw cycles
-- (GUILD_DATA_UPDATED fires every few seconds in an active guild) without
-- jumping back to the top: its row offset is kept per character in
-- db.char.frames.scrollTabs, keyed by tab (ListScroll below).
local function _GetScrollStore()
    local db = addon.lib and addon.lib.db
    if not (db and db.char) then return nil end
    db.char.frames = db.char.frames or {}
    db.char.frames.scrollTabs = db.char.frames.scrollTabs or {}
    return db.char.frames.scrollTabs
end

-- ---------------------------------------------------------------------------
-- A LibAceGUIWidgets RowList that lives for the session, inside a pooled tab
-- ---------------------------------------------------------------------------
-- RowList:New HookScripts its parent's OnSizeChanged and OnMouseWheel, and a
-- HookScript cannot be removed -- so the parent must never be a pooled AceGUI
-- frame. Each list gets a raw host frame owned by the tab for the session; every
-- draw parks that host inside the draw's AceGUI group, and AttachRawFrames hands
-- it back to UIParent when the group is released. The list keeps its rows, sort
-- arrow and column widths across redraws and tab switches.
--
-- `owner` is the tab module (the host and list are kept on it under `field`),
-- `group` the AceGUI group to fill, and `build(host)` returns the new RowList
-- the first time only.
function addon.GUI.ParkList(owner, field, group, build)
    local hostField = field .. "Host"
    local host = owner[hostField]
    if not host then
        host = CreateFrame("Frame", nil, UIParent)
        owner[hostField] = host
        owner[field] = build(host)
    end
    host:SetParent(group.content)
    host:ClearAllPoints()
    host:SetAllPoints(group.content)
    host:Show()
    if addon.W then addon.W:AttachRawFrames(group, host) end
    return owner[field]
end

-- The saved scroll position of a RowList, in ROWS, kept in
-- db.char.frames.scrollTabs (under its own field, so the pixel offset an older
-- build saved for the same key is not misread as rows).
-- Read the offset BEFORE SetData: SetData scrolls to the top, and that move is
-- reported through the list's onScroll too.
addon.GUI.ListScroll = {}

function addon.GUI.ListScroll.Get(key)
    local store = _GetScrollStore()
    local rec = store and key and store[key]
    return (rec and rec.rowOffset) or 0
end

function addon.GUI.ListScroll.Set(key, offset)
    local store = _GetScrollStore()
    if not (store and key) then return end
    store[key] = store[key] or {}
    store[key].rowOffset = offset
end

-- ---------------------------------------------------------------------------
-- Persistent UI choices (dropdown selections, active tab, saved filters, ...)
-- ---------------------------------------------------------------------------
-- One place for the "remember this control's value across /reload and relog"
-- pattern every tab used to hand-roll against AceDB. Returns get/set closures
-- bound to a single value in a chosen SavedVariables scope:
--
--   local getProf, setProf = addon.GUI.PersistentChoice("char", "missingProfId", 0)
--   dropdown:SetValue(validate(getProf()))             -- restore (see note)
--   dropdown:SetCallback("OnValueChanged", function(_, _, v)
--       setProf(v)                                     -- persist
--       self:RefreshList()
--   end)
--
-- scope  : AceDB namespace — "char" (per-character, default), "profile"
--          (account-wide, follows the account to every character), or "global".
-- key    : the SavedVariables field name.
-- default: returned by get() when nothing has been saved yet (nil is fine).
--
-- NOTE — validation stays with the caller. Whether a saved value is still a
-- valid choice depends on the CURRENT list (a profession the character no longer
-- has, a character no longer in the roster, ...), which only the tab knows, so
-- callers coerce the restored value against their live list before SetValue —
-- exactly as they did with the old hand-rolled db reads.
function addon.GUI.PersistentChoice(scope, key, default)
    scope = scope or "char"
    local function bucket()
        local root = addon.lib and addon.lib.db
        return root and root[scope]
    end
    local function get()
        local d = bucket()
        local v = d and d[key]
        if v == nil then return default end
        return v
    end
    local function set(v)
        local d = bucket()
        if d then d[key] = v end
    end
    return get, set
end

-- ---------------------------------------------------------------------------
-- Scan AH button
-- ---------------------------------------------------------------------------
-- Replaces the duplicated 80-line block that previously lived in each of
-- BrowserTab / CooldownsTab / MissingRecipesTab. The factory owns:
--   • The Button widget itself, sized + tooltip-attached
--   • The refreshScanBtnLabel closure (4 states: no AH module / scanning /
--     AH open / AH closed) and its calls into addon.AH.IsOpen() etc.
--   • The OnClick handler that cancels in-progress scans or kicks off a
--     new one via addon.AH.StartScan(...) using items the caller provides
--   • Two AH callbacks (AH_OPEN_STATE_CHANGED, AH_SCAN_COMPLETE) registered
--     ONCE at module load — they look up the active tab's current scan
--     button via _activeButtons[tabName] and refresh it. No more N-callback
--     accumulation across redraws.
--
-- Callers pass:
--   parent        — AceGUI container to AddChild into                    REQUIRED
--   tabName       — "browser" / "cooldowns" / "missing" (active-tab guard) REQUIRED
--   label         — button text when idle / closed                       REQUIRED
--   progressLabel — printf format e.g. "Scanning %d/%d"                  REQUIRED
--   tooltipTitle  — first line of tooltip                                REQUIRED
--   tooltipDesc   — body of tooltip                                      REQUIRED
--   getItems      — function() returning { {itemId, itemName}, ... }     REQUIRED
--                   for the current scan's input set
--   onRefresh     — optional function() called after the button refreshes
--                   so the tab can also refresh its row [AH] buttons
--   noItemsError  — optional string shown when getItems returns empty
--                   (defaults to a generic message)
--   width         — optional, defaults to 130

-- One-time global state. Each tab keeps at most one live scan button at
-- a time; redraws replace the entry, releases clear it (see OnRelease).
local _activeButtons = {}

-- Single global refresh entry-point. Called by the AH callbacks below
-- AND by the OnClick handler immediately after kicking off / cancelling
-- a scan, so every state change funnels through one path.
local function refreshTabButton(tabName)
    local btn = _activeButtons[tabName]
    if not btn or not btn._tpmRefresh then return end
    btn._tpmRefresh()
    if btn._tpmOnRefresh then btn._tpmOnRefresh() end
end

-- One-time callback registration — fires for whichever tab is active.
-- Inactive tabs' buttons get refreshed only when their tab redraws (which
-- happens on tab-switch via OnGroupSelected → DrawTab → tab:Draw). That's
-- the same behaviour the per-tab handlers had after we added the active-
-- tab guard, just centralised.
addon:RegisterCallback("AH_OPEN_STATE_CHANGED", function()
    local mw = addon.MainWindow
    if not mw then return end
    refreshTabButton(mw.activeTab)
end)
addon:RegisterCallback("AH_SCAN_COMPLETE", function()
    local mw = addon.MainWindow
    if not mw then return end
    refreshTabButton(mw.activeTab)
end)

function addon.GUI.MakeScanAHButton(opts)
    assert(opts and opts.parent and opts.tabName and opts.label
           and opts.progressLabel and opts.tooltipTitle and opts.tooltipDesc
           and opts.getItems, "MakeScanAHButton: missing required option")

    local btn = AceGUI:Create("Button")
    btn:SetWidth(opts.width or 130)

    -- Label refresh closure. Captures `btn` and `opts` for this specific
    -- factory call. Stored on btn._tpmRefresh so the global AH callbacks
    -- can reach it via _activeButtons[tabName] without a separate registry.
    local function refresh()
        if not addon.AH then
            btn:SetText(opts.label)
            btn:SetDisabled(true)
            return
        end
        if addon.AH.IsScanning() then
            local done, total = addon.AH.GetScanProgress()
            btn:SetText(string.format(opts.progressLabel, done, total))
            btn:SetDisabled(false)  -- click cancels
        elseif addon.AH.IsOpen() then
            btn:SetText(opts.label)
            btn:SetDisabled(false)
        else
            btn:SetText(opts.label)
            btn:SetDisabled(true)
        end
    end
    btn._tpmRefresh   = refresh
    btn._tpmOnRefresh = opts.onRefresh
    refresh()  -- initial state before the button is even shown

    btn:SetCallback("OnClick", function()
        if not addon.AH then return end
        if addon.AH.IsScanning() then
            addon.AH.CancelScan()
            refreshTabButton(opts.tabName)
            return
        end
        local items = opts.getItems() or {}
        local ok, reason = addon.AH.StartScan(items, {
            onProgress = function() refreshTabButton(opts.tabName) end,
            onComplete = function() refreshTabButton(opts.tabName) end,
        })
        if not ok then
            if reason == "ah-closed" then
                addon:Print(L["AHOpenFirst"])
            elseif reason == "no-items" then
                addon:Print(opts.noItemsError or L["AHNoItemsToScan"])
            end
        end
        refreshTabButton(opts.tabName)
    end)

    addon.GUI.AttachTooltip(btn, opts.tooltipTitle, opts.tooltipDesc)
    -- The button is disabled whenever the AH is closed -- exactly when its
    -- tooltip matters -- and a disabled Button fires no OnEnter unless motion
    -- scripts are enabled while disabled (Blizzard does the same for its own
    -- disabled-button tooltips: UIButtonTemplate.lua SetDisabledTooltip,
    -- classic_era). Reset in OnRelease below: the frame is pooled.
    if btn.frame.SetMotionScriptsWhileDisabled then
        btn.frame:SetMotionScriptsWhileDisabled(true)
    end

    -- OnRelease: clear our slot in _activeButtons IF this is still the
    -- registered button. A redraw replaces the entry with a NEW button
    -- BEFORE the old one is released, so this check (==btn) guards
    -- against the old release stomping the new entry.
    btn:SetCallback("OnRelease", function()
        if _activeButtons[opts.tabName] == btn then
            _activeButtons[opts.tabName] = nil
        end
        btn._tpmRefresh   = nil
        btn._tpmOnRefresh = nil
        if btn.frame.SetMotionScriptsWhileDisabled then
            btn.frame:SetMotionScriptsWhileDisabled(false)
        end
    end)

    _activeButtons[opts.tabName] = btn
    opts.parent:AddChild(btn)
    return btn
end

-- ---------------------------------------------------------------------------
-- Tooltip attachment
-- ---------------------------------------------------------------------------
-- Standard "title + body" tooltip on hover of an AceGUI widget, label area
-- included. Delegates to LibAceGUIWidgets' AttachWidgetTooltip (MINOR 36,
-- TOGPM's own contract efe864ec): it answers on widget.frame and the widget's
-- interactive children, runs each frame's existing dispatcher first (so our
-- SetCallback("OnEnter") handlers elsewhere still fire), and on Release puts
-- back every script, the mouse flag and the motion flag. The hand-rolled
-- version this replaces enabled the mouse on a pooled Dropdown/EditBox frame
-- and never turned it back off. Anchored through addon.Tooltip.Owner like
-- every other TOGPM tooltip.
function addon.GUI.AttachTooltip(widget, title, desc)
    if not (widget and addon.W) then return end
    addon.W:AttachWidgetTooltip(widget, title, desc, { owner = addon.Tooltip.Owner })
end

-- ---------------------------------------------------------------------------
-- Toolbar controls on LibAceGUIWidgets (LAGW adoption step 6)
-- ---------------------------------------------------------------------------
-- Every tab's toolbar is an AceGUI Flow group. Its dropdowns, search boxes and
-- check boxes are the library's, not AceGUI's, for one reason above all: the
-- main window must not redraw a tab while the player has one of its menus
-- open, and only the library can say whether one of ITS menus is open
-- (W:IsMenuOpenFor). An AceGUI Dropdown's pullout is invisible to that check.
--
-- Each control sits in a SLOT: a fixed-size SimpleGroup the Flow toolbar lays
-- out like any widget. A labelled control is TOOLBAR_H tall (label on top, the
-- control along the bottom), so an unlabelled one given `aligned = true` lines
-- up with its labelled neighbours. The raw library frames live on the tab for
-- the session (`owner._toolbar[key]`) and are parked in each draw's slot, then
-- handed back to UIParent when the slot is released (AttachRawFrames) -- a tab
-- redraws on every guild sync, and building fresh frames per draw would leak
-- them, since WoW never frees a frame.
local TOOLBAR_H     = 44
local TOOLBAR_CTL_H = 24

local function toolbarSlot(parent, width, height)
    local slot = AceGUI:Create("SimpleGroup")
    slot:SetLayout("Fill")
    slot:SetAutoAdjustHeight(false)
    slot:SetWidth(width)
    slot:SetHeight(height)
    parent:AddChild(slot)
    return slot
end

-- The tab's persistent record for one control, created on first use with a
-- holder frame and (when asked) a brand-coloured label along its top.
local function toolbarRecord(owner, key)
    owner._toolbar = owner._toolbar or {}
    local rec = owner._toolbar[key]
    if not rec then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -2)
        label:SetJustifyH("LEFT")
        rec = { holder = holder, label = label }
        owner._toolbar[key] = rec
    end
    return rec
end

-- Park a record's holder in this draw's slot.
local function parkInSlot(rec, slot)
    local holder = rec.holder
    holder:SetParent(slot.content)
    holder:ClearAllPoints()
    holder:SetAllPoints(slot.content)
    holder:Show()
    if addon.W then addon.W:AttachRawFrames(slot, holder) end
end

-- Run a toolbar handler so an error in it cannot stop the menu closing. The
-- library closes a menu only AFTER a row's onClick returns, so a raising
-- handler left the menu open and the window's deferred redraw waiting on it
-- (Peer Review thread a0cbde36). The error still reaches the player's error
-- display through the client's handler.
local function runHandler(fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        local get = _G.geterrorhandler
        local handler = get and get()
        if handler then handler(err) end
    end
end

local function setSlotLabel(rec, text)
    if text and text ~= "" then
        rec.label:SetText(UI.Brand(text))
        rec.label:Show()
    else
        rec.label:SetText("")
        rec.label:Hide()
    end
end

--- A toolbar dropdown: the library's dropdown box, its menu the library's.
---
--- opts:
---   label      text above the box (brand-coloured); nil for none
---   aligned    with no label, still take a labelled control's height
---   width      the box's width
---   items()    -> { { value = v, text = "..." , action = bool }, ... }, read
---              every time the menu opens
---   value      the selected value (single select)
---   onChange(value)            a different value was picked
---   multi      tick-box menu that stays open; then instead of value/onChange:
---     isChecked(value) -> bool, onToggle(value, checked), and an item with
---     `action = true` (Select All / Clear All) runs onAction(value) and
---     closes the menu
---   text()     the box's own text; default: the selected item's text
---   tipTitle, tipBody
--- Returns the slot widget and the record (`rec.box` is the dropdown box).
function addon.GUI.ToolbarDropdown(owner, key, parent, opts)
    local W = addon.W
    local labelled = opts.label ~= nil and opts.label ~= ""
    local slot = toolbarSlot(parent, opts.width or 180,
        (labelled or opts.aligned) and TOOLBAR_H or TOOLBAR_CTL_H)
    if not W then return slot end
    local rec = toolbarRecord(owner, key)
    rec.opts = opts
    if not rec.box then
        rec.box = W:CreateDropdownBox(rec.holder, {
            height = 22,
            items  = function() return rec.menu() end,
        })
        rec.box:SetPoint("BOTTOMLEFT",  rec.holder, "BOTTOMLEFT",  0, 1)
        rec.box:SetPoint("BOTTOMRIGHT", rec.holder, "BOTTOMRIGHT", 0, 1)
        -- The menu rows, built from the CURRENT opts each time it opens.
        rec.menu = function()
            local o = rec.opts
            local out = {}
            for _, it in ipairs(o.items() or {}) do
                local v = it.value
                if o.multi and it.action then
                    out[#out + 1] = { text = it.text, keepOpen = false, onClick = function()
                        runHandler(rec.opts.onAction, v)
                        rec.Sync()
                    end }
                elseif o.multi then
                    out[#out + 1] = { text = it.text, keepOpen = true,
                        checked = function() return rec.opts.isChecked(v) end,
                        onClick = function()
                            local cur = rec.opts
                            runHandler(cur.onToggle, v, not cur.isChecked(v))
                            rec.Sync()
                        end }
                else
                    out[#out + 1] = { text = it.text, checked = (v == o.value), onClick = function()
                        local cur = rec.opts
                        if v == cur.value then return end
                        cur.value = v
                        rec.Sync()
                        runHandler(cur.onChange, v)
                    end }
                end
            end
            return out
        end
        -- The box's text from the current opts.
        rec.Sync = function()
            local o = rec.opts
            local text = o.text and o.text()
            if text == nil and not o.multi then
                for _, it in ipairs(o.items() or {}) do
                    if it.value == o.value then text = it.text break end
                end
            end
            rec.box.label:SetText(text or "")
        end
    end
    -- Set every draw, so a reused box is never left with the last owner's.
    W:AttachTooltip(rec.box, opts.tipTitle, opts.tipBody, { owner = addon.Tooltip.Owner })
    setSlotLabel(rec, labelled and opts.label or nil)
    rec.Sync()
    parkInSlot(rec, slot)
    return slot, rec
end

--- `labels[key] = text` plus `order = { key, ... }` -- the pair AceGUI's
--- SetList took, and what UI.ScopeList returns -- as ToolbarDropdown items.
--- A key with no label is dropped rather than drawn as a blank row.
function addon.GUI.MenuItems(labels, order)
    local out = {}
    for _, k in ipairs(order or {}) do
        if labels[k] ~= nil then out[#out + 1] = { value = k, text = labels[k] } end
    end
    return out
end

--- A toolbar search box: the library's LAGW-SearchBox (magnifier, placeholder,
--- clear-X). `onChanged(text)` hears the player's typing and the clear-X, not
--- a programmatic SetText. `debounce` (seconds): `onChanged` runs only once
--- the player has paused that long -- a new key cancels the pending call.
--- `aligned` gives it a labelled control's height, the box along the bottom.
--- Returns the slot (or the search widget itself when not aligned), and the
--- search widget.
function addon.GUI.ToolbarSearch(parent, opts)
    local search = AceGUI:Create("LAGW-SearchBox")
    search:SetWidth(opts.width or 200)
    search:SetText(opts.text or "")
    if opts.placeholder then search:SetPlaceholder(opts.placeholder) end
    local timer
    search:SetCallback("OnTextChanged", function(_, _, text)
        -- Continuous typing keeps deferring the window's redraw (which would
        -- rebuild this box and drop the caret); an idle-but-focused box still
        -- reaches the cap and redraws eventually.
        if addon.MainWindow then addon.MainWindow._refreshDeferrals = 0 end
        if not opts.onChanged then return end
        if not opts.debounce then
            opts.onChanged(text)
            return
        end
        if timer then timer:Cancel() end
        -- Keystrokes coalesced into one re-filter of the tab's own list.
        -- writ:internal a debounce of the tab's own list; nothing outside the addon is reached
        timer = C_Timer.NewTimer(opts.debounce, function()
            timer = nil
            opts.onChanged(text)
        end)
    end)
    if opts.tipTitle then addon.GUI.AttachTooltip(search, opts.tipTitle, opts.tipBody) end
    if not opts.aligned then
        parent:AddChild(search)
        return search, search
    end
    local slot = AceGUI:Create("SimpleGroup")
    slot:SetLayout("List")
    slot:SetAutoAdjustHeight(false)
    slot:SetWidth(opts.width or 200)
    slot:SetHeight(TOOLBAR_H)
    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetAutoAdjustHeight(false)
    spacer:SetFullWidth(true)
    spacer:SetHeight(TOOLBAR_H - TOOLBAR_CTL_H)
    slot:AddChild(spacer)
    slot:AddChild(search)
    parent:AddChild(slot)
    return slot, search
end

--- A toolbar check box: the library's, bound to `get()` / `set(checked)`.
--- `aligned` gives it a labelled control's height, the box along the bottom.
function addon.GUI.ToolbarCheckbox(owner, key, parent, opts)
    local W = addon.W
    local slot = toolbarSlot(parent, opts.width or 150, opts.aligned and TOOLBAR_H or TOOLBAR_CTL_H + 2)
    if not W then return slot end
    local rec = toolbarRecord(owner, key)
    rec.opts = opts
    if not rec.check then
        rec.check = W:CreateCheckbox(rec.holder, {
            size = 24,
            get  = function() return rec.opts.get() end,
            set  = function(on) rec.opts.set(on) end,
        })
        rec.check:SetPoint("BOTTOMLEFT", rec.holder, "BOTTOMLEFT", 0, 0)
    end
    rec.check.label:SetText(opts.label or "")
    W:AttachTooltip(rec.check, opts.tipTitle, opts.tipBody, { owner = addon.Tooltip.Owner })
    setSlotLabel(rec, nil)
    rec.check:Refresh()
    parkInSlot(rec, slot)
    return slot, rec
end

-- ---------------------------------------------------------------------------
-- Column header
-- ---------------------------------------------------------------------------
-- Shared factory for "column header" labels above tab tables. Centralises
-- the rules from CLAUDE.md (InteractiveLabel + brand color + no-wrap) so
-- new headers can't drift away from the brand convention by accident.
-- Optional tooltip: pass `tooltipTitle` and/or `tooltipDesc`.
--
-- The Guild tab's headers are its only use: every list with sortable
-- headers is a LibAceGUIWidgets RowList, which draws its own. The sort
-- click, alignment and hover-glow options went with the last AceGUI header
-- row in v1.1.3.
function addon.GUI.MakeColumnHeader(opts)
    assert(opts and opts.parent and opts.label and opts.width,
           "MakeColumnHeader: missing required option (parent / label / width)")

    local lbl = AceGUI:Create("InteractiveLabel")
    lbl:SetText(UI.Brand(opts.label))
    lbl:SetWidth(opts.width)
    -- Headers never wrap to a second line — column widths can be tight,
    -- and a wrapped header doubles the row height and breaks alignment
    -- with the data rows below. The internal fontstring lives at .label;
    -- guard for older clients that lack SetWordWrap.
    if lbl.label and lbl.label.SetWordWrap then
        lbl.label:SetWordWrap(false)
    end

    if opts.tooltipTitle or opts.tooltipDesc then
        addon.GUI.AttachTooltip(lbl, opts.tooltipTitle, opts.tooltipDesc)
    end

    opts.parent:AddChild(lbl)
    return lbl
end

UI.AttachTooltip = addon.GUI.AttachTooltip

-- Suppress unused-warn for L since callers pass strings already localised.
local _ = L
