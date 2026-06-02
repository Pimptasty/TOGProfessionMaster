-- TOG Profession Master -- AH Profit tab
-- Profit planner across your own characters' known recipes.
-- Subtabs:
--   1) Live AH: items currently priced from Auctionator / TSM / TOGPM AH scan.
--   2) Historical: Auctionator / TSM historical-style sources.

local _, addon = ...
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local ProfitTab = {}
addon.AHProfitTab = ProfitTab

ProfitTab.WINDOW_SIZE = { minWidth = 920, minHeight = 540 }
ProfitTab._sortCol = ProfitTab._sortCol or "profit"
if ProfitTab._sortAsc == nil then ProfitTab._sortAsc = false end

local ROW_H     = 16
local POOL_SIZE = 36

local COL = {
    recipe     = 168,
    profession = 78,
    crafters   = 112,
    source     = 92,
    -- Money columns: wide enough to space the coin values comfortably apart,
    -- but the total row extent must stay inside the window's usable content
    -- width (~840px after the nested frame/tab insets on the 920px minWidth)
    -- so Profit and the scrollbar aren't pushed off the right edge and the
    -- Profit header doesn't wrap. 112 each lands the last column at ~821px,
    -- clear of the scrollbar, while still spacing the coin values well apart
    -- (the original 72 was cramped; Copilot's 142 overflowed the window).
    cost       = 112,
    sell       = 112,
    profit     = 112,
}

local PAD = 2
local ICON_W = 14
local ICON_GAP = 3
local X = {}

local function BuildLayout()
    local x = 4
    X.icon = x
    x = x + ICON_W + ICON_GAP
    X.recipe = x
    x = x + COL.recipe + PAD
    X.profession = x
    x = x + COL.profession + PAD
    X.crafters = x
    x = x + COL.crafters + PAD
    X.source = x
    x = x + COL.source + PAD
    X.cost = x
    x = x + COL.cost + PAD
    X.sell = x
    x = x + COL.sell + PAD
    X.profit = x
end
BuildLayout()

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

local SOURCE_ORDER = {
    "togpm-ah",
    "auctionator",
    "auctionator-history",
    "auctioneer-live",
    "auctioneer-cached",
    "auctioneer-app",
    "tsm-live",
    "tsm-history",
}

local function tsmApiReady()
    local tsm = _G.TSM_API
    return type(tsm) == "table" and type(tsm.GetCustomPriceValue) == "function"
end

local function auctionatorApiReady()
    local auc = _G.Auctionator
    return auc and auc.API and auc.API.v1
       and type(auc.API.v1.GetAuctionPriceByItemID) == "function"
end

local function auctioneerApiReady()
    local auc = _G.AucAdvanced
    return type(auc) == "table"
       and type(auc.API) == "table"
       and type(auc.API.GetMarketValue) == "function"
end

local function enabledSourcesForMode(mode)
    local out = {}
    local profile = addon.lib and addon.lib.db and addon.lib.db.profile or {}
    local tsmEnabled = (profile.useTSM == true or profile.useTSMAppHelper == true) and tsmApiReady()
    local auctioneerEnabled = (profile.useAuctioneer == true) and auctioneerApiReady()
    local auctioneerCachedEnabled = auctioneerEnabled and (profile.useAuctioneerCached ~= false)
    local auctionatorEnabled = (profile.useAuctionator == true) and auctionatorApiReady()
    local auctionatorHistoryEnabled = auctionatorEnabled and (profile.useAuctionatorHistorical ~= false)
    local togpmEnabled = (profile.useTOGPMAH ~= false)
    if mode == "history" then
        if auctionatorHistoryEnabled then
            out["auctionator-history"] = true
        end
        if auctionatorEnabled then
            out["auctionator"] = true
        end
        if auctioneerEnabled then
            out["auctioneer-live"] = true
        end
        if auctioneerCachedEnabled then
            out["auctioneer-cached"] = true
        end
        if tsmEnabled then
            out["tsm-history"] = true
            out["tsm-live"] = true
        end
    else
        if togpmEnabled then
            out["togpm-ah"] = true
        end
        if auctionatorEnabled then
            out["auctionator"] = true
        end
        if auctionatorHistoryEnabled then
            out["auctionator-history"] = true
        end
        if auctioneerEnabled then
            out["auctioneer-live"] = true
        end
        if auctioneerCachedEnabled then
            out["auctioneer-cached"] = true
        end
        if tsmEnabled then
            out["tsm-live"] = true
            out["tsm-history"] = true
        end
    end
    return out
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

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
    for _, src in ipairs(SOURCE_ORDER) do
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

    -- Back-compat for existing SavedVariables that stored the old single
    -- Auctioneer key before live/cached source split.
    if filter.sources["auctioneer-app"] ~= nil then
        if filter.sources["auctioneer-live"] == nil then
            filter.sources["auctioneer-live"] = filter.sources["auctioneer-app"] and true or false
        end
        if filter.sources["auctioneer-cached"] == nil then
            filter.sources["auctioneer-cached"] = filter.sources["auctioneer-app"] and true or false
        end
        filter.sources["auctioneer-app"] = nil
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

    if self._scroll then
        if resetToTop and self._scroll.scrollbar and self._scroll.scrollbar.SetValue then
            self._scroll.scrollbar:SetValue(0)
        end
        if self._scroll.content then
            self._scroll.content:SetHeight(math.max(1, #self._rows * ROW_H))
        end
        if self._scroll.FixScroll then self._scroll:FixScroll() end
        self:UpdateRows()
    end

    self:SetCountText(BRAND .. ("Rows: %d"):format(#self._rows) .. RESET)
end

local function charShort(charKey)
    return (charKey and charKey:match("^([^%-]+)")) or charKey or "?"
end

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
                        local _, itemLink = GetItemInfo(resolvedItemId)
                        local displayItemId = craftedItemId or resolvedItemId
                        local icon = (displayItemId and GetItemIcon and GetItemIcon(displayItemId))
                                  or (resolvedItemId and GetItemIcon and GetItemIcon(resolvedItemId))
                                  or (GetSpellTexture and GetSpellTexture(recipeId))
                        rows[#rows + 1] = {
                            itemId = resolvedItemId,
                            displayItemId = displayItemId,
                            recipeId = recipeId,
                            icon = icon,
                            itemLink = itemLink,
                            recipe = (meta and meta.name) or (itemLink and itemLink:match("%[(.-)%]")) or ("#" .. tostring(recipeId)),
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
        "Filter recipes by profession. Tick multiple professions — the menu stays open. Use Select All / Clear All at the top.")
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

function ProfitTab:BuildHeaders(parent)
    local hdr = AceGUI:Create("SimpleGroup")
    hdr:SetLayout("Flow")
    hdr:SetFullWidth(true)

    -- Leading spacer = the recipe data column's X (left margin + icon + gap), so
    -- the first header column starts exactly over the recipe data column. Using
    -- X.recipe rather than ICON_W+ICON_GAP also accounts for BuildLayout's 4px
    -- left margin — omitting it was the start of the header→row drift.
    local spacer = AceGUI:Create("Label")
    spacer:SetWidth(X.recipe)
    spacer:SetText(" ")
    hdr:AddChild(spacer)

    -- Every header is CENTER-justified over its column, and the sort arrow is
    -- placed just to the right of the (centered) header text by the shared
    -- addon.GUI.Sort.ConfigureCenteredHeaderIcon — not at the column's far edge.
    -- The DATA cells keep their own justification (set in BuildPool): names left,
    -- money right.
    local cols = {
        { key = "recipe",     label = "Recipe",        width = COL.recipe,     tip = "Crafted item." },
        { key = "profession", label = "Profession",    width = COL.profession, tip = "Profession that crafts this recipe." },
        { key = "crafters",   label = "Your Crafters", width = COL.crafters,   tip = "Your characters that know this recipe." },
        { key = "source",     label = "Price Source",  width = COL.source,     tip = "Provider used for sale price." },
        { key = "cost",       label = "Craft Cost",    width = COL.cost,       tip = "Material cost for one craft." },
        { key = "sell",       label = "Sell Price",    width = COL.sell,       tip = "Current or historical sell price for one item." },
        { key = "profit",     label = "Profit",        width = COL.profit,     tip = "Sell minus craft cost." },
    }

    self._headerCols = cols
    self._headerWidgets = {}

    for i, col in ipairs(cols) do
        if i > 1 then
            -- Data columns are separated by PAD px, but Flow places header widgets
            -- edge-to-edge. A PAD-wide spacer before each subsequent header keeps
            -- every header column span aligned with its data column (without it the
            -- headers drift left, cumulatively, one PAD per column).
            local gap = AceGUI:Create("Label")
            gap:SetWidth(PAD)
            gap:SetText(" ")
            hdr:AddChild(gap)
        end
        local w = addon.GUI.MakeColumnHeader({
            parent = hdr,
            label = col.label,
            width = col.width,
            justifyH = "CENTER",
            hoverGlow = true,
            tooltipTitle = col.label,
            tooltipDesc = col.tip .. " Click to sort.",
            onClick = function()
                self:OnHeaderClick(col.key)
            end,
        })
        addon.GUI.Sort.ConfigureCenteredHeaderIcon(w, self._sortCol == col.key, self._sortAsc, col.width)

        -- Clean up sort icon when widget is released back to AceGUI pool
        local prevOnRelease = w.events and w.events.OnRelease
        w:SetCallback("OnRelease", function(widget)
            if widget._sortIcon then
                widget._sortIcon:Hide()
                widget._sortIcon:SetParent(nil)
                widget._sortIcon:ClearAllPoints()
                widget._sortIcon = nil
            end
            if prevOnRelease then prevOnRelease(widget) end
        end)
        
        self._headerWidgets[col.key] = w
    end

    parent:AddChild(hdr)
end

function ProfitTab:UpdateHeaderText()
    if not (self._headerCols and self._headerWidgets) then return end
    for _, col in ipairs(self._headerCols) do
        local w = self._headerWidgets[col.key]
        if w then
            w:SetText(BRAND .. col.label .. RESET)
            addon.GUI.Sort.ConfigureCenteredHeaderIcon(w, self._sortCol == col.key, self._sortAsc, col.width)
        end
    end
end

function ProfitTab:OnHeaderClick(col)
    self._sortCol, self._sortAsc = addon.GUI.Sort.Next(self._sortCol, self._sortAsc, col)
    self:UpdateHeaderText()
    if self._rows then
        self:SortRows(self._rows)
        self:UpdateRows()
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

function ProfitTab:DetachPool()
    -- Hide tooltip if it's showing for this tab's elements.
    if GameTooltip then
        GameTooltip:Hide()
    end

    -- The profession dropdown is now a native AceGUI child of the toolbar and
    -- is released by container:ReleaseChildren(); no manual detach required.
    addon.GUI.DetachPool(self._pool)
    self._scroll = nil
    self._rows = nil
    self._baseRows = nil
end

function ProfitTab:BuildPool(parent)
    self._pool = {}
    for _ = 1, POOL_SIZE do
        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(ROW_H)
        f:Hide()
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", X.icon, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        f.bg = bg

        local recipe = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        recipe:SetPoint("LEFT", f, "LEFT", X.recipe, 0)
        recipe:SetWidth(COL.recipe)
        recipe:SetJustifyH("LEFT")
        recipe:SetWordWrap(false)
        f.recipe = recipe

        local prof = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        prof:SetPoint("LEFT", f, "LEFT", X.profession, 0)
        prof:SetWidth(COL.profession)
        prof:SetJustifyH("LEFT")
        prof:SetWordWrap(false)
        f.prof = prof

        local crafters = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        crafters:SetPoint("LEFT", f, "LEFT", X.crafters, 0)
        crafters:SetWidth(COL.crafters)
        crafters:SetJustifyH("LEFT")
        crafters:SetWordWrap(false)
        f.crafters = crafters

        local source = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        source:SetPoint("LEFT", f, "LEFT", X.source, 0)
        source:SetWidth(COL.source)
        source:SetJustifyH("LEFT")
        source:SetWordWrap(false)
        f.source = source

        local cost = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cost:SetPoint("LEFT", f, "LEFT", X.cost, 0)
        cost:SetWidth(COL.cost)
        cost:SetJustifyH("RIGHT")
        cost:SetWordWrap(false)
        f.cost = cost

        local sell = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sell:SetPoint("LEFT", f, "LEFT", X.sell, 0)
        sell:SetWidth(COL.sell)
        sell:SetJustifyH("RIGHT")
        sell:SetWordWrap(false)
        f.sell = sell

        local profit = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        profit:SetPoint("LEFT", f, "LEFT", X.profit, 0)
        profit:SetWidth(COL.profit)
        profit:SetJustifyH("RIGHT")
        profit:SetWordWrap(false)
        f.profit = profit

        f:SetScript("OnEnter", function(rf)
            if not rf._row then return end
            local row = rf._row
            -- Always anchor tooltip to BOTTOMLEFT (bottom-right of cursor) for profit tab rows
            GameTooltip:SetOwner(rf, "ANCHOR_BOTTOMLEFT")
            
            -- Show actual game item tooltip
            if row.itemLink then
                GameTooltip:SetHyperlink(row.itemLink)
            elseif row.displayItemId then
                GameTooltip:SetItemByID(row.displayItemId)
            elseif row.itemId then
                GameTooltip:SetItemByID(row.itemId)
            else
                -- Fallback if no item info available
                GameTooltip:SetText(row.recipe, 1, 1, 1)
            end
            
            -- Add profit planner details
            GameTooltip:AddLine(" ")  -- Blank line separator
            GameTooltip:AddLine("Profit Planner:", 1, 0.82, 0)
            GameTooltip:AddLine("Profession: " .. row.profession, 0.9, 0.9, 0.9)
            GameTooltip:AddLine("Crafters: " .. row.crafters, 0.9, 0.9, 0.9)
            if row.source then
                GameTooltip:AddLine("Price Source: " .. (addon.Price and addon.Price.ColorizeSource(row.source) or row.source), 1, 1, 1, true)
            else
                GameTooltip:AddLine("Price Source: |cff888888No price|r", 1, 1, 1, true)
            end
            if row.source and row.age and row.age > 14 * 24 * 60 * 60 then
                GameTooltip:AddLine("Price is stale (>14 days old)", 1, 0.82, 0)
            end
            
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnClick", function(rf)
            local row = rf._row
            if not row then return end
            if IsShiftKeyDown() and row.itemLink and HandleModifiedItemClick then
                HandleModifiedItemClick(row.itemLink)
            end
        end)

        self._pool[#self._pool + 1] = f
    end
end

function ProfitTab:UpdateRows()
    if not (self._scroll and self._rows and self._pool) then return end
    local status = self._scroll.status or self._scroll.localstatus
    local offset = (status and status.offset) or 0
    local first = math.floor(offset / ROW_H)

    for i = 1, POOL_SIZE do
        local f = self._pool[i]
        local row = self._rows[first + i]
        if row then
            f._row = row
            addon.GUI.ApplyRowStripe(f, first + i)
            local tex = (row.displayItemId and GetItemIcon and GetItemIcon(row.displayItemId))
                     or (row.itemId and GetItemIcon and GetItemIcon(row.itemId))
                     or row.icon
                     or (row.recipeId and GetSpellTexture and GetSpellTexture(row.recipeId))
            f.icon:SetTexture(tex or 134400)
            f.recipe:SetText(row.recipe)
            f.prof:SetText("|cffaaaaaa" .. row.profession .. RESET)
            f.crafters:SetText("|cffffffff" .. row.crafters .. RESET)
            if row.source and addon.Price and addon.Price.ColorizeSource then
                f.source:SetText(addon.Price.ColorizeSource(row.source))
            elseif row.source then
                f.source:SetText(row.source)
            else
                f.source:SetText("|cff888888No price|r")
            end
            f.cost:SetText(moneyText(row.cost))
            f.sell:SetText(moneyText(row.sell))
            f.profit:SetText(colorProfit(row.profit))

            local y = -((first + i - 1) * ROW_H)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self._scroll.content, "TOPLEFT", 0, y)
            f:SetPoint("TOPRIGHT", self._scroll.content, "TOPRIGHT", 0, y)
            f:Show()
        else
            f._row = nil
            if f.bg then f.bg:SetColorTexture(1, 1, 1, 0) end
            f:Hide()
        end
    end
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

    self:BuildHeaders(container)

    local scroll, savedScroll = addon.GUI.PersistentScroll.Acquire(self, {
        key = (mode == "history") and "ahprofit_history" or "ahprofit_live",
        layout = "List", fullWidth = true, fullHeight = true,
        onRelease = function() self:DetachPool() end,
    })
    container:AddChild(scroll)
    self._scroll = scroll
    -- Virtual-row tabs manage content size/anchors manually; disable
    -- ScrollFrame auto-content layout (same pattern as Crafting/Browser).
    scroll.LayoutFinished = function() end

    if not self._pool then
        self:BuildPool(scroll.content)
    else
        for _, f in ipairs(self._pool) do f:SetParent(scroll.content) end
    end

    if scroll.scrollbar then
        local bar = scroll.scrollbar
        local prev = (bar.GetScript and bar:GetScript("OnValueChanged")) or nil
        if bar.SetScript then
            bar:SetScript("OnValueChanged", function(bar2, value)
            if bar2.obj and bar2.obj.SetScroll then bar2.obj:SetScroll(value) end
            self:UpdateRows()
        end)
        end

        local prevOnRelease = scroll.events and scroll.events.OnRelease
        scroll:SetCallback("OnRelease", function(widget)
            if bar and bar.SetScript then
                bar:SetScript("OnValueChanged", prev)
            end
            if prevOnRelease then prevOnRelease(widget) end
        end)
    end

    self._rows = self:ApplyFilters(baseRows)
    self:SortRows(self._rows)
    scroll.content:SetHeight(math.max(1, #self._rows * ROW_H))
    if scroll.FixScroll then scroll:FixScroll() end
    self:UpdateRows()
    addon.GUI.PersistentScroll.Restore(scroll, savedScroll, function()
        self:UpdateRows()
    end)

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
