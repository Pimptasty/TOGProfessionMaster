-- TOG Profession Master -- AH Profit tab
-- Profit planner across your own characters' known recipes.
-- Subtabs:
--   1) Live AH: items currently priced by any ItemDB price source (Auctionator,
--      Auctioneer, TSM, the ItemDB scan) -- the "best" statistic.
--   2) Historical: only the sources that carry a "historical" statistic.
-- The source list, which of them are on and their precedence all come from
-- ItemDB (`/itemdb`); this tab reads `DB:GetPriceSources()` and never decides.

local _, addon = ...
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local ProfitTab = {}
addon.AHProfitTab = ProfitTab

ProfitTab.WINDOW_SIZE = { minWidth = 920, minHeight = 540 }
ProfitTab._sortCol = ProfitTab._sortCol or "profit"
if ProfitTab._sortAsc == nil then ProfitTab._sortAsc = false end

local ROW_H  = 16
local ICON_W = 14

-- Column widths (scale-1.0). The recipe column has none: it is the list's one
-- auto-width column and takes whatever the fixed columns leave. The money
-- columns are wide enough to space the coin values apart.
local COL = {
    icon       = ICON_W + 6,
    profession = 78,
    crafters   = 112,
    source     = 92,
    cost       = 112,
    sell       = 112,
    profit     = 112,
}

local BRAND = "|c" .. (addon.BrandColor or "ffFF8000")
local RESET = "|r"

-- Special keys for the profession dropdown's Select All / Clear All rows.
-- They are real toggle items (so clicking them never closes the pullout),
-- but we reset them to unchecked the instant they fire so they act as
-- one-shot buttons rather than persistent checkboxes.
local SELECT_ALL_KEY = "__togpm_select_all__"
local CLEAR_ALL_KEY  = "__togpm_clear_all__"

local SUBTABS = {
    { value = "live", text = L["ProfitSubtabLive"] },
    { value = "history", text = L["ProfitSubtabHistory"] },
}

ProfitTab._subTab = ProfitTab._subTab or "live"
ProfitTab._filters = ProfitTab._filters or {}

--- ItemDB's price-source registry -- `{ { id, name, detected, enabled,
--- precedence, statistics }, ... }` in the user's precedence -- or an empty
--- list against an ItemDB that predates the price API (the tab then shows
--- whatever sources its rows carry and nothing is pre-ticked).
local function priceSources()
    local DB = addon.GetItemDB and addon:GetItemDB()
    if DB and type(DB.GetPriceSources) == "function" then
        local ok, list = pcall(DB.GetPriceSources, DB)
        if ok and type(list) == "table" then return list end
    end
    return {}
end

--- Source ids in the library's precedence -- the order the Source dropdown
--- lists them in.
local function librarySourceOrder()
    local out = {}
    for _, src in ipairs(priceSources()) do out[#out + 1] = src.id end
    return out
end

--- The sources that can answer a lookup right now (present on this machine
--- AND turned on in ItemDB), as a set. The Historical subtab is answered only
--- by sources carrying a "historical" statistic, which is exactly the rule
--- `Price.GetSaleHistorical` follows, so the filter never pre-ticks a source
--- the rows can never come from.
local function enabledSourcesForMode(mode)
    local out = {}
    for _, src in ipairs(priceSources()) do
        if src.detected and src.enabled then
            local usable = mode ~= "history"
            if not usable then
                for _, stat in ipairs(src.statistics or {}) do
                    if stat == "historical" then usable = true break end
                end
            end
            if usable then out[src.id] = true end
        end
    end
    return out
end

-- Resolved at call time, not captured at file scope — audit finding 6; see the
-- note in CraftingTab.lua.
local function countKeys(t) return addon.UI.Count(t) end

function ProfitTab:GetFilter(mode)
    mode = mode == "history" and "history" or "live"
    local f = self._filters[mode]
    if not f then
        f = {
            professions = nil,
            crafters = nil,
            search = "",
            positiveOnly = false,
            sources = nil,
        }
        self._filters[mode] = f
    end
    return f
end

function ProfitTab:SyncProfessionSelection(filter, options)
    local valid = {}
    for _, p in ipairs(options.professions or {}) do valid[p] = true end

    -- Back-compat with older single-select saved state.
    if filter.professions == nil and filter.profession ~= nil then
        if filter.profession and filter.profession ~= "all" and valid[filter.profession] then
            filter.professions = { [filter.profession] = true }
        else
            filter.professions = {}
        end
        filter.profession = nil
    end

    filter.professions = filter.professions or {}
    for p in pairs(filter.professions) do
        if not valid[p] then
            filter.professions[p] = nil
        end
    end

    -- Apply the "all except Enchanting" default ONLY the first time this filter
    -- is built. After the user has interacted, an empty selection is intentional
    -- (Clear All, or unticking every box) and must not be re-populated on the
    -- next redraw.
    if not filter._professionsInitialized then
        filter._professionsInitialized = true
        local any = false
        for _, p in ipairs(options.professions or {}) do
            if filter.professions[p] then
                any = true
                break
            end
        end
        if not any then
            -- Default to all professions EXCEPT Enchanting (profession ID 333).
            -- Use the localized name so this works on all clients.
            local enchantingName = addon.PROF_NAMES and addon.PROF_NAMES[333]
            for _, p in ipairs(options.professions or {}) do
                if p ~= enchantingName then
                    filter.professions[p] = true
                end
            end
        end
    end
end

function ProfitTab:SyncCrafterSelection(filter, options)
    local valid = {}
    for _, c in ipairs(options.crafters or {}) do valid[c] = true end

    -- Back-compat with older single-select saved state.
    if filter.crafters == nil and filter.crafter ~= nil then
        if filter.crafter and filter.crafter ~= "all" and valid[filter.crafter] then
            filter.crafters = { [filter.crafter] = true }
        else
            filter.crafters = {}
        end
        filter.crafter = nil
    end

    filter.crafters = filter.crafters or {}
    for c in pairs(filter.crafters) do
        if not valid[c] then
            filter.crafters[c] = nil
        end
    end

    local any = false
    for _, c in ipairs(options.crafters or {}) do
        if filter.crafters[c] then
            any = true
            break
        end
    end

    if not any then
        for _, c in ipairs(options.crafters or {}) do
            filter.crafters[c] = true
        end
    end
end

function ProfitTab:BuildFilterOptions(rows)
    local profSet, crafterSet, sourceSet = {}, {}, {}
    for _, row in ipairs(rows or {}) do
        if row.profession and row.profession ~= "" then
            profSet[row.profession] = true
        end
        if row.craftersList then
            for _, short in ipairs(row.craftersList) do
                if short and short ~= "" then
                    crafterSet[short] = true
                end
            end
        end
        if row.source and row.source ~= "" then
            sourceSet[row.source] = true
        end
    end

    local profOrder, crafterOrder, sourceOrder = {}, {}, {}
    for p in pairs(profSet) do profOrder[#profOrder + 1] = p end
    for c in pairs(crafterSet) do crafterOrder[#crafterOrder + 1] = c end
    table.sort(profOrder)
    table.sort(crafterOrder)

    local enabled = enabledSourcesForMode(self._mode)
    for src in pairs(enabled) do sourceSet[src] = true end
    for _, src in ipairs(librarySourceOrder()) do
        if sourceSet[src] then sourceOrder[#sourceOrder + 1] = src end
    end
    for src in pairs(sourceSet) do
        local known = false
        for _, s in ipairs(sourceOrder) do
            if s == src then known = true break end
        end
        if not known then sourceOrder[#sourceOrder + 1] = src end
    end

    return {
        professions = profOrder,
        crafters = crafterOrder,
        sources = sourceOrder,
        enabledSources = enabled,
    }
end

function ProfitTab:SyncSourceSelection(filter, options)
    filter.sources = filter.sources or {}

    -- Back-compat for SavedVariables written before v1.1.0, when this addon
    -- keyed sources by its own per-statistic ids. ItemDB keys by PROVIDER
    -- (one id per addon, the statistic is provenance on the row), so the old
    -- keys fold into their provider: a provider is ticked if ANY of its old
    -- keys was. The old keys are then dropped so they cannot re-fold.
    local FOLD = {
        ["togpm-ah"]            = "scan",
        ["auctionator-history"] = "auctionator",
        ["auctioneer-live"]     = "auctioneer",
        ["auctioneer-cached"]   = "auctioneer",
        ["auctioneer-app"]      = "auctioneer",
        ["tsm-live"]            = "tsm",
        ["tsm-history"]         = "tsm",
    }
    for old, new in pairs(FOLD) do
        local v = filter.sources[old]
        if v ~= nil then
            if v then
                filter.sources[new] = true
            elseif filter.sources[new] == nil then
                filter.sources[new] = false
            end
            filter.sources[old] = nil
        end
    end

    local enabled = options.enabledSources or {}
    for src, isEnabled in pairs(enabled) do
        if isEnabled and filter.sources[src] == nil then
            filter.sources[src] = true
        end
    end
    local any = false
    for _, src in ipairs(options.sources or {}) do
        if filter.sources[src] then
            any = true
            break
        end
    end
    if not any then
        for _, src in ipairs(options.sources or {}) do
            if enabled[src] then
                filter.sources[src] = true
            end
        end
        any = false
        for _, src in ipairs(options.sources or {}) do
            if filter.sources[src] then
                any = true
                break
            end
        end
        if not any then
            for _, src in ipairs(options.sources or {}) do
                filter.sources[src] = true
            end
        end
    end
end

function ProfitTab:ApplyFilters(rows)
    local filter = self:GetFilter(self._mode)
    local out = {}
    local search = (filter.search or ""):lower()
    for _, row in ipairs(rows or {}) do
        local ok = true
        -- Multi-select profession filter. An explicit (non-nil) selection set
        -- always applies; an EMPTY set means "no professions selected" and
        -- intentionally matches no rows (do not treat empty as "show all").
        if filter.professions then
            ok = filter.professions[row.profession] and true or false
        end
        if ok and filter.crafterFilter and filter.crafterFilter ~= "All" then
            local hit = false
            if row._crafterSet then
                if row._crafterSet[filter.crafterFilter] then
                    hit = true
                end
            end
            ok = hit
        end
        if ok and filter.positiveOnly then
            ok = (tonumber(row.profit) or 0) > 0
        end
        if ok and filter.sourceFilter and filter.sourceFilter ~= "All" then
            if row.source then
                ok = (filter.sourceFilter == row.source)
            else
                ok = false
            end
        end
        if ok and search ~= "" then
            local srcLabel
            if row.source and addon.Price and addon.Price.GetSourceLabel then
                srcLabel = addon.Price.GetSourceLabel(row.source)
            else
                srcLabel = row.source or "No price"
            end
            local hay = table.concat({
                tostring(row.recipe or ""),
                tostring(row.profession or ""),
                tostring(row.crafters or ""),
                tostring(srcLabel or ""),
            }, " "):lower()
            ok = hay:find(search, 1, true) ~= nil
        end
        if ok then
            out[#out + 1] = row
        end
    end
    return out
end

function ProfitTab:RedrawCurrentTable()
    if self._tableContainer then
        self:DrawTable(self._tableContainer, self._mode or "live")
    end
end

-- Jump from a profit row to the Crafting tab and open that recipe there. The row
-- click is a hardware event, so the tab switch → CraftingTab:Draw →
-- Engine:OpenProfession (CastSpellByName) chain runs in the allowed protected
-- context, exactly like clicking the Crafting tab header itself.
function ProfitTab:GoToCrafting(row)
    if not (row and row.recipeId) then return end
    local mw = addon.MainWindow
    local CT = addon.CraftingTab
    if not (mw and mw.tabs and CT and CT.RequestSelect) then return end

    -- The Crafting tab can be hidden (profile.hideCraftingTab); without it there's
    -- nowhere to navigate, so tell the user how to re-enable it.
    local profile = addon.lib and addon.lib.db and addon.lib.db.profile
    if profile and profile.hideCraftingTab then
        addon:Print(L["ProfitCraftTabHidden"])
        return
    end

    CT:RequestSelect(row.profId, row.recipeId)
    mw:SelectTab("crafting")
end

-- The row count lives in the main window's bottom-left status bar rather than
-- an in-tab label — it keeps the toolbar area clean and avoids fighting AceGUI
-- Label's fontstring re-anchoring. Only write it while the Profit Planner tab
-- is the active tab so a stray refresh can't clobber another tab's status line;
-- MainWindow:DrawTab restores the version string when you switch away.
function ProfitTab:SetCountText(text)
    local mw = addon.MainWindow
    if mw and mw.activeTab == "ahprofit" and mw.SetStatusSuffix then
        -- Version stays first in the status bar; the row count follows it.
        mw:SetStatusSuffix(text)
    end
end

function ProfitTab:RefreshRowsInPlace(resetToTop)
    if not self._baseRows then
        self:RedrawCurrentTable()
        return
    end

    self._rows = self:ApplyFilters(self._baseRows)
    self:SortRows(self._rows)
    if self._list then self._list:SetData(self._rows, not resetToTop) end

    self:SetCountText(BRAND .. ("Rows: %d"):format(#self._rows) .. RESET)
end

local function charShort(charKey) return addon.UI.ShortName(charKey) end

local function moneyText(copper)
    if not addon.Price or type(copper) ~= "number" then return "" end
    return addon.Price.Money(copper)
end

local function colorProfit(copper)
    if type(copper) ~= "number" then return "" end
    if copper >= 0 then
        return "|cff40c040+" .. moneyText(copper) .. RESET
    end
    return "|cffff4040-" .. moneyText(math.abs(copper)) .. RESET
end

local function knownByMyChars(rd)
    if not (rd and rd.crafters) then return nil end
    local out, seen = {}, {}
    for charKey in pairs(rd.crafters) do
        if addon:IsMyCharacter(charKey) then
            local short = charShort(charKey)
            if not seen[short] then
                seen[short] = true
                out[#out + 1] = short
            end
        end
    end
    if #out == 0 then return nil end
    table.sort(out)
    return out
end

local function itemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function addCandidateItemId(out, seen, value)
    local id = tonumber(value)
    if id and id > 0 and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
    end
end

-- Offline-test seam — the frame-free helpers. BuildRows below is already a
-- method and needs no seam. See Tests/ahprofit_spec.lua.
ProfitTab._charShort            = charShort
ProfitTab._moneyText            = moneyText
ProfitTab._colorProfit          = colorProfit
ProfitTab._knownByMyChars       = knownByMyChars
ProfitTab._itemIdFromLink       = itemIdFromLink
ProfitTab._addCandidateItemId   = addCandidateItemId
ProfitTab._enabledSourcesForMode = enabledSourcesForMode
ProfitTab._countKeys            = countKeys

function ProfitTab:BuildRows(mode)
    local gdb = addon:GetGuildDb()
    if not (gdb and gdb.recipes and addon.recipeDB and addon.Price) then return {} end

    local rows = {}
    for profId, profRecipes in pairs(gdb.recipes) do
        local metaProf = addon.recipeDB[profId]
        if metaProf then
            for recipeId, rd in pairs(profRecipes) do
                local mine = knownByMyChars(rd)
                if mine then
                    local meta = metaProf[recipeId]
                    local candidateIds, seenIds = {}, {}
                    local craftedItemId = tonumber(meta and meta.craftedItemId)
                    local recipeItemId = tonumber(meta and meta.itemId)
                    local scannedItemId = itemIdFromLink(rd and rd.itemLink)

                    -- Profit should be based on the produced item, not the recipe
                    -- scroll item. For recipes that have a crafted output ID,
                    -- explicitly ignore recipe-scroll IDs (for example Savory
                    -- Deviate Delight: crafted 6657 vs recipe scroll 6661).
                    addCandidateItemId(candidateIds, seenIds, craftedItemId)
                    if scannedItemId and scannedItemId ~= recipeItemId then
                        addCandidateItemId(candidateIds, seenIds, scannedItemId)
                    end
                    if not craftedItemId then
                        addCandidateItemId(candidateIds, seenIds, recipeItemId)
                    end

                    local itemId = candidateIds[1]
                    if itemId then
                        local sell, sellSrc, sellAge
                        local resolvedItemId = itemId

                        for i = 1, #candidateIds do
                            local probeId = candidateIds[i]
                            local psell, psrc, page
                            if mode == "history" then
                                psell, psrc = addon.Price.GetSaleHistorical(probeId)
                                if not psell then
                                    -- In historical view, prefer history sources,
                                    -- but fall back to live so rows don't falsely
                                    -- read as unpriced when only live data exists.
                                    psell, psrc, page = addon.Price.GetSaleLive(probeId)
                                end
                            else
                                psell, psrc, page = addon.Price.GetSaleLive(probeId)
                                if not psell then
                                    -- In live view, accept history fallback if
                                    -- live sources are unavailable for this item.
                                    psell, psrc = addon.Price.GetSaleHistorical(probeId)
                                end
                            end
                            if psell then
                                sell, sellSrc, sellAge = psell, psrc, page
                                resolvedItemId = probeId
                                break
                            end
                        end

                        local totalCost, priced, count = addon.Price.CraftCost(profId, recipeId, 1)
                        local cost = (count > 0 and priced == count) and totalCost or nil
                        local profit = (type(sell) == "number" and type(cost) == "number") and (sell - cost) or nil
                        local _, itemLink = addon.Item.GetInfo(resolvedItemId)
                        local displayItemId = craftedItemId or resolvedItemId
                        local icon = (displayItemId and addon.Item.GetIcon(displayItemId))
                                  or (resolvedItemId and addon.Item.GetIcon(resolvedItemId))
                                  or addon.Spell.GetTexture(recipeId)
                        rows[#rows + 1] = {
                            itemId = resolvedItemId,
                            displayItemId = displayItemId,
                            recipeId = recipeId,
                            icon = icon,
                            itemLink = itemLink,
                            recipe = (meta and meta.name)
                                or (itemLink and itemLink:match("%[(.-)%]"))
                                or ("#" .. tostring(recipeId)),
                            profId = profId,
                            profession = addon.PROF_NAMES[profId] or tostring(profId),
                            craftersList = mine,
                            _crafterSet = (function()
                                local set = {}
                                for _, c in ipairs(mine) do set[c] = true end
                                return set
                            end)(),
                            crafters = table.concat(mine, ", "),
                            source = sellSrc,
                            age = sellAge,
                            cost = cost,
                            sell = sell,
                            profit = profit,
                        }
                    end
                end
            end
        end
    end

    return rows
end

function ProfitTab:BuildToolbar(parent, mode, options)
    local filter = self:GetFilter(mode)
    self:SyncProfessionSelection(filter, options)
    self:SyncCrafterSelection(filter, options)
    self:SyncSourceSelection(filter, options)

    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    parent:AddChild(toolbar)

    local brand = addon.BrandColor or "ffFF8000"

    -- Profession multi-select dropdown. Native AceGUI multiselect Dropdown so
    -- it lines up with the Crafters/Sources dropdowns and the checkbox pullout
    -- stays open while ticking professions. Select All / Clear All are added as
    -- toggle rows at the top — toggles never close the pullout, and we reset
    -- them to unchecked the instant they fire so they behave as buttons.
    local profList = {
        [SELECT_ALL_KEY] = "Select All",
        [CLEAR_ALL_KEY]  = "Clear All",
    }
    local profOrder = { SELECT_ALL_KEY, CLEAR_ALL_KEY }
    for _, p in ipairs(options.professions or {}) do
        profList[p] = p
        profOrder[#profOrder + 1] = p
    end

    local profDropdown = AceGUI:Create("Dropdown")
    profDropdown:SetLabel("|c" .. brand .. "Professions|r")
    profDropdown:SetWidth(170)
    addon.GUI.OffsetInputLabel(profDropdown)
    profDropdown:SetMultiselect(true)
    profDropdown:SetList(profList, profOrder)

    -- Apply the saved/defaulted checked state to the profession rows.
    for _, p in ipairs(options.professions or {}) do
        profDropdown:SetItemValue(p, (filter.professions and filter.professions[p]) and true or false)
    end

    profDropdown:SetCallback("OnValueChanged", function(_w, _e, key, checked)
        if key == SELECT_ALL_KEY or key == CLEAR_ALL_KEY then
            -- Reset the action row so it never displays as a checked entry.
            profDropdown:SetItemValue(key, false)
            local want = (key == SELECT_ALL_KEY)
            local sel = {}
            for _, p in ipairs(options.professions or {}) do
                profDropdown:SetItemValue(p, want)
                if want then sel[p] = true end
            end
            filter.professions = sel
            self:RefreshRowsInPlace(true)
            return
        end
        local sel = filter.professions or {}
        if checked then sel[key] = true else sel[key] = nil end
        filter.professions = sel
        self:RefreshRowsInPlace(true)
    end)
    addon.GUI.AttachTooltip(profDropdown, "Professions",
        "Filter recipes by profession. Tick multiple professions -- the menu stays open."
        .. " Use Select All / Clear All at the top.")
    toolbar:AddChild(profDropdown)

    -- Crafter dropdown
    local crafterList = { ["All"] = "All Crafters" }
    local crafterOrder = { "All" }
    for _, c in ipairs(options.crafters or {}) do
        crafterList[c] = c
        crafterOrder[#crafterOrder + 1] = c
    end
    local crafterDropdown = AceGUI:Create("Dropdown")
    crafterDropdown:SetLabel("|c" .. brand .. "Crafters|r")
    crafterDropdown:SetWidth(170)
    addon.GUI.OffsetInputLabel(crafterDropdown)
    crafterDropdown:SetList(crafterList, crafterOrder)
    crafterDropdown:SetValue(filter.crafterFilter or "All")
    crafterDropdown:SetCallback("OnValueChanged", function(_w, _e, value)
        filter.crafterFilter = value
        self:RefreshRowsInPlace(true)
    end)
    addon.GUI.AttachTooltip(crafterDropdown, "Crafters", "Pick a crafter to filter recipes.")
    toolbar:AddChild(crafterDropdown)

    local search = AceGUI:Create("EditBox")
    search:SetWidth(210)
    search:SetText(filter.search or "")
    search:DisableButton(true)
    search:SetCallback("OnTextChanged", function(_w, _e, text)
        filter.search = text or ""
        -- Avoid full redraw while typing; redraw recreates this widget and
        -- steals keyboard focus after the first keypress.
        self:RefreshRowsInPlace(true)
    end)
    addon.GUI.AttachTooltip(search, L["SearchPlaceholder"], L["CraftSearchDesc"])
    -- TSM-style search field: magnifying-glass icon instead of a text label
    -- (call after AttachTooltip so the icon's OnRelease cleanup chains).
    -- keepLabelSpace=true: aligns with the labeled dropdowns in this row.
    addon.GUI.StyleSearchBox(search, true)
    toolbar:AddChild(search)

    local positive = AceGUI:Create("CheckBox")
    positive:SetLabel("+ Profit only")
    positive:SetWidth(110)
    positive:SetValue(filter.positiveOnly and true or false)
    -- Checkboxes carry no top label, so AceGUI's Flow heuristic (alignoffset =
    -- height/2 = 12) rides the box + text a few px above the labeled dropdown
    -- controls. Lowering the alignment point shifts it down onto the same centre
    -- line (Flow anchors at Y = alignoffset - prevAlignoffset, so a smaller value
    -- moves it down). Restored on release so the shared AceGUI pool isn't polluted.
    positive.alignoffset = 10
    positive:SetCallback("OnRelease", function(w) w.alignoffset = nil end)
    positive:SetCallback("OnValueChanged", function(_w, _e, val)
        filter.positiveOnly = val and true or false
        self:RedrawCurrentTable()
    end)
    addon.GUI.AttachTooltip(positive, "+ Profit only", "Show only rows where profit is greater than zero.")
    toolbar:AddChild(positive)

    -- Source dropdown
    local sourceList = { ["All"] = "All Sources" }
    local sourceOrder = { "All" }
    for _, src in ipairs(options.sources or {}) do
        sourceList[src] = (addon.Price and addon.Price.GetSourceLabel and addon.Price.GetSourceLabel(src)) or src
        sourceOrder[#sourceOrder + 1] = src
    end
    local sourceDropdown = AceGUI:Create("Dropdown")
    sourceDropdown:SetLabel("|c" .. brand .. "Sources|r")
    sourceDropdown:SetWidth(190)
    addon.GUI.OffsetInputLabel(sourceDropdown)
    sourceDropdown:SetList(sourceList, sourceOrder)
    sourceDropdown:SetValue(filter.sourceFilter or "All")
    sourceDropdown:SetCallback("OnValueChanged", function(_w, _e, value)
        filter.sourceFilter = value
        self:RefreshRowsInPlace(true)
    end)
    addon.GUI.AttachTooltip(sourceDropdown, "Sources", "Pick a pricing source to filter recipes.")
    toolbar:AddChild(sourceDropdown)
end

-- A header click, reported by the list (onSortChanged) after it has set its
-- own key and arrow: a new column starts ascending, the same column flips.
-- The list is externalSort, so SortRows orders the rows.
function ProfitTab:OnSortChanged(key, desc)
    self._sortCol = key or "profit"
    self._sortAsc = not desc
    if self._rows then
        self:SortRows(self._rows)
        if self._list then self._list:SetData(self._rows, true) end
    end
end

function ProfitTab:SortRows(rows)
    if type(rows) ~= "table" then return end

    local col = self._sortCol or "profit"
    local asc = self._sortAsc == true

    local function sortValue(row)
        if not row then return nil end
        if col == "recipe" then
            return (row.recipe or ""):lower(), row.recipe or ""
        elseif col == "profession" then
            return (row.profession or ""):lower(), row.profession or ""
        elseif col == "crafters" then
            return (row.crafters or ""):lower(), row.crafters or ""
        elseif col == "source" then
            local text
            if row.source and addon.Price and addon.Price.GetSourceLabel then
                text = addon.Price.GetSourceLabel(row.source) or ""
            else
                text = row.source or "No price"
            end
            return text:lower(), text
        elseif col == "cost" then
            return tonumber(row.cost) or 0, tostring(row.recipe or "")
        elseif col == "sell" then
            return tonumber(row.sell) or 0, tostring(row.recipe or "")
        end
        return tonumber(row.profit) or 0, tostring(row.recipe or "")
    end

    local sorted = {}
    for i = 1, #rows do
        local row = rows[i]
        if row then sorted[#sorted + 1] = row end
    end

    local function before(left, right)
        local lk, lt = sortValue(left)
        local rk, rt = sortValue(right)

        if lk == nil and rk == nil then return false end
        if lk == nil then return not asc end
        if rk == nil then return asc end

        if lk ~= rk then
            return asc and (lk < rk) or (lk > rk)
        end
        if lt ~= rt then
            return asc and (lt < rt) or (lt > rt)
        end
        return false
    end

    for i = 2, #sorted do
        local item = sorted[i]
        local j = i - 1
        while j >= 1 and before(item, sorted[j]) do
            sorted[j + 1] = sorted[j]
            j = j - 1
        end
        sorted[j + 1] = item
    end

    for i = 1, #sorted do
        rows[i] = sorted[i]
    end
    for i = #sorted + 1, #rows do
        rows[i] = nil
    end
end

--- The row icon: the crafted item's, else the recipe's, else the question mark.
local function rowIcon(row)
    return (row.displayItemId and addon.Item.GetIcon(row.displayItemId))
        or (row.itemId and addon.Item.GetIcon(row.itemId))
        or row.icon
        or (row.recipeId and addon.Spell.GetTexture(row.recipeId))
        or 134400
end

local function sourceText(source)
    if source and addon.Price and addon.Price.ColorizeSource then
        return addon.Price.ColorizeSource(source)
    end
    return source or "|cff888888No price|r"
end

--- The item tooltip plus the planner's own lines, for the row under the pointer.
function ProfitTab:ShowRowTooltip(row, owner)
    addon.Tooltip.Owner(owner)

    if row.itemLink then
        addon.ItemLink.SetItem(GameTooltip, row.itemLink)
    elseif row.displayItemId then
        GameTooltip:SetItemByID(row.displayItemId)
    elseif row.itemId then
        GameTooltip:SetItemByID(row.itemId)
    else
        -- Fallback if no item info available
        GameTooltip:SetText(row.recipe, 1, 1, 1, 1, true)
    end

    -- Add profit planner details
    GameTooltip:AddLine(" ")  -- Blank line separator
    GameTooltip:AddLine("Profit Planner:", 1, 0.82, 0, true)
    -- wrap = true on both. `row.crafters` is a comma-joined list of every
    -- guildmate who can make the item, so on a popular recipe it is the
    -- longest line on the tooltip by a wide margin — and without the flag
    -- it cannot break, so it sets the width of the whole frame.
    GameTooltip:AddLine("Profession: " .. row.profession, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Crafters: " .. row.crafters, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Price Source: " .. sourceText(row.source), 1, 1, 1, true)
    if row.source and row.age and row.age > 14 * 24 * 60 * 60 then
        GameTooltip:AddLine("Price is stale (>14 days old)", 1, 0.82, 0, true)
    end

    -- The same recipe block every other tab shows. Explicit rather than
    -- inherited: the global hook is OnTooltipSetItem, so the SetText
    -- fallback above (a recipe with no resolvable item) carried nothing
    -- at all, and the block renders once per tooltip either way.
    addon.ItemLink.AppendRecipeBlocks(GameTooltip, row.profId, row.recipeId, row.itemId)

    -- Click hints (the whole tooltip in this tab is intentionally plain
    -- English, matching the lines above).
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to open in the Crafting tab", 0.4, 0.8, 1, true)
    GameTooltip:AddLine("Shift-click to link in chat", 0.6, 0.6, 0.6, true)

    GameTooltip:Show()
end

-- The rows: a LibAceGUIWidgets RowList (MINOR 36), built once per session on a
-- host the tab owns (addon.GUI.ParkList). It draws the header bar, sort arrow,
-- banding, hover highlight and scrollbar. The list is externalSort: a header
-- click comes back through onSortChanged, and SortRows orders the rows by the
-- same rule it always did (source by its label, ties by recipe name).
local function headerTip(text) return text .. " Click to sort." end

function ProfitTab:BuildList(host)
    return addon.W.RowList:New(host, {
        rowHeight      = ROW_H,
        hoverHighlight = true,
        externalSort   = true,
        onSortChanged  = function(key, desc) self:OnSortChanged(key, desc) end,
        onScroll       = function(_, offset) addon.GUI.ListScroll.Set(self._scrollKey, offset) end,
        columns = {
            { key = "_icon", width = COL.icon, iconSize = ICON_W, iconTexCoord = true,
              sortable = false, icon = rowIcon },
            { key = "recipe", header = "Recipe", headerTip = headerTip("Crafted item.") },
            { key = "profession", header = "Profession", width = COL.profession,
              headerTip = headerTip("Profession that crafts this recipe."),
              format = function(v) return "|cffaaaaaa" .. (v or "") .. RESET end },
            { key = "crafters", header = "Your Crafters", width = COL.crafters,
              headerTip = headerTip("Your characters that know this recipe."),
              format = function(v) return "|cffffffff" .. (v or "") .. RESET end },
            { key = "source", header = "Price Source", width = COL.source,
              headerTip = headerTip("Provider used for sale price."),
              format = function(v) return sourceText(v) end },
            { key = "cost", header = "Craft Cost", width = COL.cost, align = "RIGHT",
              headerTip = headerTip("Material cost for one craft."),
              format = function(v) return moneyText(v) end },
            { key = "sell", header = "Sell Price", width = COL.sell, align = "RIGHT",
              headerTip = headerTip("Current or historical sell price for one item."),
              format = function(v) return moneyText(v) end },
            { key = "profit", header = "Profit", width = COL.profit, align = "RIGHT",
              headerTip = headerTip("Sell minus craft cost."),
              format = function(v) return colorProfit(v) end },
        },
        onRowEnter = function(row, _, _, rowFrame) self:ShowRowTooltip(row, rowFrame) end,
        onRowLeave = function() GameTooltip:Hide() end,
        onRowClick = function(row, _, _, button)
            if button ~= "LeftButton" then return end
            -- Shift-click keeps the standard "link item in chat" behaviour.
            if addon.ItemLink.Click(row.itemLink) then return end
            -- Plain click jumps to the Crafting tab and opens this recipe there.
            ProfitTab:GoToCrafting(row)
        end,
    })
end

function ProfitTab:DrawTable(container, mode)
    container:ReleaseChildren()
    container:SetLayout("Flow")
    self._tableContainer = container
    self._mode = mode

    local baseRows = self:BuildRows(mode)
    self._baseRows = baseRows
    local filterOptions = self:BuildFilterOptions(baseRows)
    self:BuildToolbar(container, mode, filterOptions)

    -- Row count is shown in the window status bar (see SetCountText), not here.
    self:SetCountText(BRAND .. "Loading..." .. RESET)

    self._rows = self:ApplyFilters(baseRows)
    self:SortRows(self._rows)

    if addon.W then
        local group = AceGUI:Create("SimpleGroup")
        group:SetFullWidth(true)
        group:SetFullHeight(true)
        group:SetLayout("Fill")
        container:AddChild(group)
        -- Released on a subtab or tab switch: the rows belong to that draw,
        -- and the list's host goes back to UIParent through ParkList.
        addon.W:OnWidgetRelease(group, "togpm:profitList", function()
            GameTooltip:Hide()
            self._rows, self._baseRows = nil, nil
        end)

        local list = addon.GUI.ParkList(self, "_list", group, function(host)
            return self:BuildList(host)
        end)
        -- Each subtab keeps its own scroll position across redraws and
        -- /reload. The key is set before SetData so the scroll-to-top that
        -- SetData reports lands on this subtab, then the saved row goes back.
        local key = (mode == "history") and "ahprofit_history" or "ahprofit_live"
        local saved = addon.GUI.ListScroll.Get(key)
        self._scrollKey = key
        list:SetSort(self._sortCol, not self._sortAsc)
        list:SetData(self._rows)
        list:SetScrollOffset(saved)
    end

    self:SetCountText(BRAND .. ("Rows: %d"):format(#self._rows) .. RESET)
end

function ProfitTab:Draw(container)
    container:SetLayout("Fill")

    -- Load saved subtab selection from persistent storage. The settings DB is
    -- addon.lib.db (there is no addon.db), so the old reference silently failed.
    local db = addon.lib and addon.lib.db and addon.lib.db.char
    local savedSubTab = db and db.profitSubTab or "live"
    self._subTab = savedSubTab

    local tabs = AceGUI:Create("TabGroup")
    tabs:SetFullWidth(true)
    tabs:SetFullHeight(true)
    tabs:SetLayout("Flow")
    tabs:SetTabs(SUBTABS)
    tabs:SetCallback("OnGroupSelected", function(widget, _, group)
        self._subTab = group
        -- Save subtab selection to persist across reloads
        if db then
            db.profitSubTab = group
        end
        widget:ReleaseChildren()
        self:DrawTable(widget, group == "history" and "history" or "live")
    end)

    container:AddChild(tabs)
    tabs:SelectTab(self._subTab)
end
