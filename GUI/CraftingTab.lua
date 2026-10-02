-- TOG Profession Master — Crafting tab (view)
--
-- A single-character crafting UI that REPLACES the native profession window
-- (see Modules/Crafting/CraftingEngine.lua for the window-hijack engine and
-- Modules/Crafting/CraftQueue.lua for the queue model + completion tracking).
--
-- Recipe list: a LibAceGUIWidgets RowList (MINOR 36) with the profession's own
-- category rows as group headers. Columns: Recipe Name | Skill | Craft, all
-- sortable (click a header: asc → desc → back to the category tree); recipe
-- names are tinted by difficulty; shift-click links the item in chat.
--
-- LAYOUT (TSM-style): toolbar on top; under it a LibAceGUIWidgets dock the tab
-- owns for the session -- recipe list in the centre, Queue panel on the right,
-- detail panel across the bottom, sized to its content. Each draw parks the
-- dock under the toolbar; the dock follows a window resize through its anchors.

local _, addon = ...
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local CraftingTab = {}
addon.CraftingTab = CraftingTab

-- Resizable (shares the saved "resizable" size with the Browser tab via
-- MainWindow). minWidth holds the known-good width so the recipe columns + the
-- fixed-width queue panel never overlap; height can shrink a little and grow
-- freely. The layout itself is responsive — the dock pins the detail panel to
-- the bottom edge, the queue panel to the right edge, and lets the recipe list
-- fill the rest, so it reflows to any size.
CraftingTab.WINDOW_SIZE = { minWidth = 820, minHeight = 540 }

-- Recipe list geometry (scale-1.0 values; the list scales them itself).
local ROW_HEIGHT = 16
local SKILL_W    = 104     -- Skill column shows 4 colored tiers (orange/yellow/green/grey)
local COUNT_W    = 48

local DETAIL_H    = 120   -- fallback; the panel auto-sizes to its content (self._detailH)
local QUEUE_W     = 250
local QROW_H      = 18
local Q_TITLE_H   = 24
local Q_FOOTER_H  = 32
local Q_PAD       = 8
local GAP         = 8     -- between the list and the queue panel
local PANEL_GAP   = 4     -- above and below the detail panel

CraftingTab._search   = ""
CraftingTab._haveOnly = false
CraftingTab._selIndex = nil
CraftingTab._selId    = nil
CraftingTab._qty      = 1
CraftingTab._sortCol  = nil    -- nil = native category tree; "name"|"skill"|"craft"
CraftingTab._sortAsc  = true

-- Shared, not a private copy: this file used to carry its own Brand() without
-- the nil guard addon.UI.Brand has.
--
-- RESOLVED AT CALL TIME, not captured at file scope. `local Brand = addon.UI.Brand`
-- reads the value once as this file loads, which made SharedWidgets.lua's TOC
-- position load-bearing for seven aliases: move it below any consumer and the alias
-- is nil at capture, then raises on first use. Audit finding 6. One extra call
-- frame removes the class of bug instead of asserting against it.
local function Brand(text) return addon.UI.Brand(text) end
local function Color(hex, text) return "|c" .. hex .. text .. "|r" end
local function PriceSourceTag(src)
    if not (src and addon.Price and addon.Price.GetSourceColor) then return "" end
    -- ItemDB's source ids (one per provider; the statistic is provenance the
    -- tag does not carry), plus this addon's own two vendor-sell ids.
    local short = {
        ["scan"] = "SCAN",
        ["auctionator"] = "AUC",
        ["auctioneer"] = "AUCN",
        ["tsm"] = "TSM",
        ["auctionator-vendor"] = "AUC-V",
        ["merchant"] = "VEND",
        ["vendor-static"] = "VEND",
        ["vendor-sell-client"] = "SELL",
        ["vendor-sell-static"] = "SELL",
    }
    local col = addon.Price.GetSourceColor(src)
    return " " .. "|c" .. col .. "[" .. (short[src] or src) .. "]|r"
end

local Ace = addon.lib
-- Persisted selected-profession NAME (per-character), via the shared
-- addon.GUI.PersistentChoice helper. (SharedWidgets loads before this file.)
local _craftGetProf, _craftSetProf = addon.GUI.PersistentChoice("char", "craftSelProf", nil)
local function savedProf() return _craftGetProf() end
local function setSavedProf(name) _craftSetProf(name) end

local function findProf(professions, name)
    for _, p in ipairs(professions) do
        if p.name == name then return p end
    end
end

local function findProfById(professions, profId)
    if not profId then return nil end
    for _, p in ipairs(professions) do
        if p.profId == profId then return p end
    end
end

local function activeProfession(professions, info)
    if info then return info.name end
    local saved = savedProf()
    for _, p in ipairs(professions) do
        if p.name == saved then return saved end
    end
    return professions[1] and professions[1].name or nil
end

-- ===========================================================================
-- Draw
-- ===========================================================================
function CraftingTab:Draw(container)
    container:SetLayout("Flow")
    self._container = container

    local Engine = addon.CraftingEngine
    local professions = Engine and Engine:GetKnownProfessions() or {}
    local info = Engine and Engine:GetOpenInfo() or nil

    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    if #professions == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetFullWidth(true)
        lbl:SetText(Brand(L["CraftNoProfessions"]))
        container:AddChild(lbl)
        return
    end

    local active = activeProfession(professions, info)

    -- A pending Profit-Planner jump (CraftingTab:RequestSelect) targets one
    -- recipe's profession. Resolve it up front so the dropdown, the no-window
    -- auto-open, and (if a different profession is open) the SWITCH all use the
    -- target rather than the last-used profession.
    local pend      = self._pendingSelect
    local pendEntry = pend and findProfById(professions, pend.profId) or nil
    if pend and pend.profId and not pendEntry then
        -- The target profession isn't one this character has (the Profit row
        -- belonged to an alt) — drop the request and say so once.
        self._pendingSelect = nil
        if not self._pendingNotified then
            self._pendingNotified = true
            addon:Print(L["ProfitCraftNotKnownHere"])
        end
    elseif pendEntry then
        active = pendEntry.name
        setSavedProf(pendEntry.name)
    end

    -- _autoOpenOnUserNav marks a hardware-event navigation (a Crafting-tab click
    -- or a Profit-Planner jump) — the only context where OpenProfession's
    -- CastSpellByName is allowed. Read+consume it once here so both the no-window
    -- auto-open below and the wrong-profession switch share the one-shot gate.
    local allowAuto = self._autoOpenOnUserNav
    self._autoOpenOnUserNav = nil
    local inCombat  = UnitAffectingCombat and UnitAffectingCombat("player")

    -- Wrong profession already open for a pending jump → switch to the target.
    -- This Draw runs synchronously inside the jump's hardware event, so the cast
    -- is permitted; the async re-show redraws with the target open and FillList →
    -- TrySelectPending resolves the selection then.
    if allowAuto and pendEntry and info and info.profId ~= pendEntry.profId and not inCombat then
        if Engine then Engine:OpenProfession(pendEntry.castName or pendEntry.name, "jump") end
    end

    local profItems = {}
    for _, p in ipairs(professions) do
        profItems[#profItems + 1] = { value = p.name, text = ("%s (%d/%d)"):format(p.name, p.rank, p.max) }
    end
    addon.GUI.ToolbarDropdown(self, "prof", toolbar, {
        width    = 230,
        items    = function() return profItems end,
        value    = active,
        onChange = function(name)
            setSavedProf(name)
            if not (info and info.name == name) then
                -- Queue is kept across profession switches by design (bounce between
                -- professions toward one goal). Opt-in setting clears it on switch.
                if Ace.db and Ace.db.profile and Ace.db.profile.clearQueueOnProfSwitch
                   and addon.CraftQueue then
                    addon.CraftQueue:Clear()
                end
                local p = findProf(professions, name)
                if Engine then Engine:OpenProfession(p and p.castName or name, "dropdown") end
            end
        end,
        tipTitle = L["CraftColRecipe"],
        tipBody  = L["CraftProfessionDesc"],
    })

    if not info then
        -- No profession window is open yet. If the player just NAVIGATED to the
        -- Crafting tab (a user click — MainWindow sets _autoOpenOnUserNav on the
        -- tab callback), auto-open their selected profession so they don't have
        -- to click the button below. This is gated on that flag because
        -- OpenProfession casts a spell (CastSpellByName), a PROTECTED function:
        -- it's allowed from a hardware-event path (the tab click) but BLOCKED
        -- from an event-driven re-draw (e.g. a profession just closed →
        -- FireUpdate → Draw → not info). The prompt + button below are the
        -- always-safe fallback — the button's OnClick is a hardware event — and
        -- cover combat (can't cast) and the suppressed-auto-open case.
        -- allowAuto / inCombat are read+consumed once near the top of Draw so the
        -- pending-jump profession switch and this auto-open share the one-shot gate.
        local activeEntry = active and findProf(professions, active) or nil
        -- A client with no trade-skill API this engine can read (neither the
        -- classic one nor WoW Forever's C_TradeSkillUI): say so instead of
        -- offering a button that cannot work.
        if Engine and not Engine:HasTradeSkillAPI() then
            local note = AceGUI:Create("Label")
            note:SetFullWidth(true)
            note:SetText("\n" .. Color("ffffffff", L["CraftUnsupportedClient"]))
            container:AddChild(note)
            return
        end
        if allowAuto and Engine and activeEntry and not inCombat then
            Engine:OpenProfession(activeEntry.castName or active, "tab")
        end

        local prompt = AceGUI:Create("Label")
        prompt:SetFullWidth(true)
        prompt:SetText("\n" .. Color("ffffffff", L["CraftOpenToView"]:format(active or "")))
        container:AddChild(prompt)
        -- WoW Forever: no Open button (operator, 2026-09-29: "you should not
        -- have added the button"). The tab click and the dropdown open it.
        if Engine and Engine:UsesModernAPI() then return end

        local openBtn = AceGUI:Create("Button")
        openBtn:SetWidth(220)
        openBtn:SetText(L["CraftOpenButton"]:format(active or ""))
        openBtn:SetCallback("OnClick", function()
            if activeEntry then Engine:OpenProfession(activeEntry.castName or active, "button") end
        end)
        container:AddChild(openBtn)
        return
    end

    -- This toolbar has no labelled controls, so nothing here is `aligned`.
    addon.GUI.ToolbarSearch(toolbar, {
        width     = 165,
        text      = self._search or "",
        onChanged = function(text)
            self._search = text or ""
            self:FillList()
        end,
        tipTitle  = L["SearchPlaceholder"],
        tipBody   = L["CraftSearchDesc"],
    })

    addon.GUI.ToolbarCheckbox(self, "haveOnly", toolbar, {
        width    = 130,
        label    = L["CraftHaveMaterials"],
        get      = function() return self._haveOnly and true or false end,
        set      = function(val)
            self._haveOnly = val and true or false
            self:FillList()
        end,
        tipTitle = L["CraftHaveMaterials"],
        tipBody  = L["CraftHaveMaterialsDesc"],
    })

    -- Scan AH for the selected recipe: the CRAFTED item first, so the AH price
    -- and Profit line in the detail panel have a number to show, then every
    -- reagent so the per-reagent [AH] buttons light up. Self-attaches to the
    -- toolbar (between Have Materials and WoW UI).
    --
    -- The crafted item was missing from this list until 2026-09-11 (Discord,
    -- 2026-08-23: "when I select a recipe in the crafting tab and hit scan AH,
    -- it does not search and update the value of the actual crafted item, only
    -- the mats"). Its id comes from the recipe's item link, exactly as the
    -- profit line resolves it (see RefreshDetail).
    addon.GUI.MakeScanAHButton({
        parent        = toolbar,
        tabName       = "crafting",
        label         = L["CraftScanAH"],
        progressLabel = L["CraftScanAHProgress"],
        tooltipTitle  = L["CraftScanAH"],
        tooltipDesc   = L["CraftScanAHDesc"],
        width         = 110,
        noItemsError  = L["CraftScanAHNoItems"],
        getItems      = function() return self:ScanAHItems() end,
        onRefresh     = function()
            local mw = addon.MainWindow
            if mw and mw.activeTab == "crafting" then CraftingTab:RefreshDetail() end
        end,
    })

    local blizBtn = AceGUI:Create("Button")
    blizBtn:SetText(L["CraftBlizzardUI"])
    blizBtn:SetWidth(80)
    blizBtn:SetCallback("OnClick", function()
        if Engine then Engine:ShowDefaultUI() end
    end)
    toolbar:AddChild(blizBtn)

    if not addon.W then return end

    -- The list, the detail panel and the queue live in a dock the tab owns for
    -- the session (EnsureDock). Each draw parks the dock's host under the
    -- toolbar; releasing the toolbar -- the next redraw or a tab switch -- hands
    -- the host back to UIParent, so none of it rides the pooled TabGroup into
    -- another addon's window. The dock follows a resize through its anchors, so
    -- nothing here overrides a LayoutFinished.
    local host = self:EnsureDock()
    local cc = container.content or container.frame
    host:SetParent(cc)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", toolbar.frame, "BOTTOMLEFT", 0, -4)
    host:SetPoint("BOTTOMRIGHT", cc, "BOTTOMRIGHT", 0, 0)
    host:Show()
    addon.W:AttachRawFrames(toolbar, host)
    self._listLive = true
    addon.W:OnWidgetRelease(toolbar, "togpm:craftList", function()
        self._listLive = nil
        self._rows = nil
        GameTooltip:Hide()
    end)

    -- The saved row is read before FillList: its SetData scrolls to the top,
    -- and that move is reported through onScroll too.
    local saved = addon.GUI.ListScroll.Get("crafting")
    self._list:SetSort(self._sortCol, not self._sortAsc)
    self:FillList(saved)
    self:RefreshDetail()
    self:RefreshQueue()
end

-- ===========================================================================
-- The dock, built once per session
-- ===========================================================================
-- A raw host of our own (never a pooled AceGUI frame: RowList and the dock hook
-- scripts on their parents, and a HookScript cannot be removed) holding a
-- LibAceGUIWidgets dock: recipe list in the centre, queue on the right, detail
-- panel across the bottom at the height RefreshDetail measures. The panels are
-- built lazily so a spec can drop one and have it rebuilt on the next draw.
function CraftingTab:EnsureDock()
    local dock = self._dock
    if not dock then
        local host = CreateFrame("Frame", nil, UIParent)
        self._dockHost = host
        dock = addon.W:NewDockLayout(host, { right = QUEUE_W + GAP, bottom = "auto", minCenter = 200 })
        self._dock = dock
        self._list = self:BuildList(dock.center)
    end
    if not self._detailPanel then
        self:BuildDetailPanel(dock.bottom)
        self._detailPanel:SetPoint("TOPLEFT", dock.bottom, "TOPLEFT", 0, -PANEL_GAP)
        self._detailPanel:SetPoint("BOTTOMRIGHT", dock.bottom, "BOTTOMRIGHT", 0, PANEL_GAP)
    end
    if not self._queuePanel then
        self:BuildQueuePanel(dock.right)
        self._queuePanel:SetPoint("TOPLEFT", dock.right, "TOPLEFT", GAP, 0)
        self._queuePanel:SetPoint("BOTTOMRIGHT", dock.right, "BOTTOMRIGHT", 0, 0)
    end
    -- Shown on every draw, as they always were: a panel hidden once must not
    -- stay hidden (the Craft button follows the detail panel's visibility).
    self._detailPanel:Show()
    self._queuePanel:Show()
    self:ApplyDetailHeight()
    return self._dockHost
end

-- The bottom pane is the detail panel plus its gap above and below.
function CraftingTab:ApplyDetailHeight()
    if self._dock then
        self._dock:SetBottomHeight((self._detailH or DETAIL_H) + 2 * PANEL_GAP)
    end
end

-- ===========================================================================
-- Recipe list (LibAceGUIWidgets RowList)
-- ===========================================================================
-- The list is externalSort: FillList builds either the category tree (no sort)
-- or a flat sorted list, and the header only reports the click. sortCycle
-- "three" gives the third click back to the tree, as NextOrNone always did.
function CraftingTab:OnSortChanged(key, desc)
    self._sortCol = key
    self._sortAsc = not desc
    self:FillList()
end

-- The list's highlight follows the selected recipe by its trade-skill index.
function CraftingTab:SyncListSelection()
    local list, idx = self._list, self._selIndex
    if not list then return end
    if idx then
        list:SetSelected(function(e) return e.kind == "recipe" and e.index == idx end)
    else
        list:SetSelected(nil)
    end
end

function CraftingTab:BuildList(parent)
    local diffMap = function()
        return (addon.CraftingEngine and addon.CraftingEngine.DIFFICULTY_COLOR) or {}
    end
    return addon.W.RowList:New(parent, {
        rowHeight      = ROW_HEIGHT,
        hoverHighlight = true,
        externalSort   = true,
        sortCycle      = "three",
        -- The profession's own category rows are group headers.
        isHeader       = function(e) return e.kind == "header" and e.name end,
        onSortChanged  = function(key, desc) self:OnSortChanged(key, desc) end,
        onScroll       = function(_, offset) addon.GUI.ListScroll.Set("crafting", offset) end,
        columns = {
            { key = "_icon", width = 14, iconSize = 14, iconTexCoord = true, sortable = false,
              icon = function(e) return e.icon or 134400 end },
            { key = "name", header = L["CraftColRecipe"], headerTip = L["CraftSortHint"],
              format = function(v, e)
                  local selected = e.index ~= nil and e.index == self._selIndex
                  return Color(selected and "ffffffff" or (diffMap()[e.difficulty] or "ffffffff"), v or "")
              end },
            -- The recipe's authoritative difficulty breakpoints (orange → yellow →
            -- green → grey), coloured by FormatSkillTiers. Pattern-recipe orange
            -- is corrected in the data pipeline (build_authoritative_data.py).
            { key = "skill", header = L["CraftColSkill"], width = SKILL_W, headerTip = L["CraftSortHint"],
              format = function(_, e) return addon.FormatSkillTiers(e.tiers, e.requiredSkill) end },
            { key = "craft", header = L["CraftColCount"], width = COUNT_W, align = "RIGHT",
              headerTip = L["CraftSortHint"],
              format = function(_, e)
                  if e.num and e.num > 0 then return Color("ff40c040", tostring(e.num)) end
                  return Color("ff808080", "0")
              end },
        },
        -- No hover tooltip on list rows on purpose — it popped over the list
        -- and made it hard to see/select. The full item tooltip lives on the
        -- detail panel's recipe name instead. Shift-click links the item.
        onRowClick = function(e, _, _, button)
            if button ~= "LeftButton" or e.kind ~= "recipe" then return end
            if addon.ItemLink.Click(e.link) then return end
            self._selIndex = e.index
            self._selId    = e.recipeId
            self._qty      = 1
            self:SyncListSelection()
            self:RefreshDetail()
        end,
    })
end

-- Full in-game item tooltip, anchored to the given frame. Prefers the crafted
-- item's hyperlink (the plain item tooltip); falls back to the trade-skill /
-- craft tooltip when no link is available.
function CraftingTab:ShowItemTooltip(anchorFrame, index, link, recipeId)
    addon.Tooltip.Owner(anchorFrame)
    local Engine = addon.CraftingEngine
    local info = Engine and Engine:GetOpenInfo()
    if link and GameTooltip.SetHyperlink then
        addon.ItemLink.SetItem(GameTooltip, link)
    elseif info and info.isCraftWindow and GameTooltip.SetCraftItem then
        GameTooltip:SetCraftItem(index)
    elseif Engine and Engine:UsesModernAPI() then
        -- WoW Forever: `index` is the recipe's spell id (CraftingEngine).
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(index) end
    elseif GameTooltip.SetTradeSkillItem then
        GameTooltip:SetTradeSkillItem(index)
    end
    -- The same recipe block the other tabs show. Only the first branch above
    -- carries a real item, so only that one inherits anything from the global
    -- OnTooltipSetItem hook -- the index-based trade-skill and craft tooltips
    -- are exactly the enchant/no-link recipes that got nothing.
    addon.ItemLink.AppendRecipeBlocks(GameTooltip, info and info.profId, recipeId)
    GameTooltip:Show()
end

local function passesFilter(self, e)
    if self._haveOnly and (e.num or 0) <= 0 then return false end
    if self._search and self._search ~= "" then
        -- Search the recipe name AND its effect text together, term by term:
        -- every whitespace-separated term in the query must appear somewhere in
        -- "name effect". Order-independent matching is important because effect
        -- text is formatted stat-first ("Agility +5", "Weapon Damage +5") — a
        -- single whole-string match would miss the natural "5 agi" / "5 agility"
        -- / "agility 5", since "5 agi" isn't a substring of "agility +5". Tokens
        -- fix that: "5" and "agi" each appear, in any order.
        local hay = e.name:lower()
        if e.effect then hay = hay .. " " .. e.effect:lower() end
        -- Fold in the crafted item's full tooltip text so ANY word in it (use/proc
        -- text, durations, requirements, flavor) is searchable — not just the name
        -- and stat line. Cached per item; already lowercased.
        local cid = e.link and tonumber(e.link:match("item:(%d+)"))
        local tt  = cid and addon:GetItemTooltipSearchText(cid)
        if tt then hay = hay .. " " .. tt end
        for term in self._search:lower():gmatch("%S+") do
            if not hay:find(term, 1, true) then return false end
        end
    end
    return true
end

local function comparator(col, asc)
    return function(a, b)
        local av, bv
        if col == "skill" then av, bv = a.requiredSkill or 0, b.requiredSkill or 0
        elseif col == "craft" then av, bv = a.num or 0, b.num or 0
        else av, bv = a.name:lower(), b.name:lower() end
        if av == bv then return a.name:lower() < b.name:lower() end
        if asc then return av < bv else return av > bv end
    end
end

-- Offline-test seam — the frame-free helpers (row filter, sort comparator,
-- profession pickers, price-source tag). See Tests/craftingtab_spec.lua.
CraftingTab._passesFilter      = passesFilter
CraftingTab._comparator        = comparator
CraftingTab._findProf          = findProf
CraftingTab._findProfById      = findProfById
CraftingTab._activeProfession  = activeProfession
CraftingTab._PriceSourceTag    = PriceSourceTag

-- `restoreOffset` (a saved row, from Draw) puts the list back where it was; a
-- refresh without one keeps the current scroll.
function CraftingTab:FillList(restoreOffset)
    local list = self._list
    if not (list and self._listLive) then return end

    local Engine  = addon.CraftingEngine
    local entries = Engine and Engine:GetRecipeList() or {}
    local rows

    if self._sortCol then
        -- Sorted = flat list (no category headers).
        rows = {}
        for _, e in ipairs(entries) do
            if e.kind == "recipe" and passesFilter(self, e) then rows[#rows + 1] = e end
        end
        table.sort(rows, comparator(self._sortCol, self._sortAsc))
    else
        -- Native category tree.
        rows = {}
        local pendingHeader = nil
        for _, e in ipairs(entries) do
            if e.kind == "header" then
                pendingHeader = e.name
            elseif e.kind == "recipe" and passesFilter(self, e) then
                if pendingHeader then
                    rows[#rows + 1] = { kind = "header", name = pendingHeader }
                    pendingHeader = nil
                end
                rows[#rows + 1] = e
            end
        end
    end
    self._rows = rows

    list:SetData(rows, true)
    if restoreOffset then list:SetScrollOffset(restoreOffset) end
    self:SyncListSelection()

    -- Resolve a pending Profit-Planner jump once the (correct) profession's list
    -- is built. No-op when nothing is pending.
    self:TrySelectPending()
end

-- ===========================================================================
-- Cross-tab "open this recipe" (Profit Planner → Crafting)
-- ===========================================================================
-- Arm a request to select a specific recipe once its profession is open. Called
-- from a hardware-event click in the Profit Planner, which then switches to this
-- tab; the selection resolves in FillList — immediately if the right profession
-- is already open, otherwise after OpenProfession's async TRADE_SKILL_SHOW lands
-- and the list rebuilds. profId/recipeId are the Profit Planner's keys (gdb /
-- recipeDB spell id); TrySelectPending bridges them to the live list ids.
function CraftingTab:RequestSelect(profId, recipeId)
    if not recipeId then return end
    self._pendingSelect   = { profId = profId, recipeId = recipeId }
    self._pendingNotified  = nil
    -- Clear list filters that could hide the target row so the jump always lands
    -- on a visible, selected recipe (the toolbar widgets rebuild from these on
    -- the imminent redraw).
    self._search   = ""
    self._haveOnly = false
    -- Safety net: if the profession never opens (cast ignored / window blocked),
    -- don't leave the request armed to fire on an unrelated later open.
    if C_Timer and C_Timer.After then
        local token = self._pendingSelect
        C_Timer.After(3, function()
            if self._pendingSelect == token then self._pendingSelect = nil end
        end)
    end
end

-- Map an engine recipe id (the crafted ITEM id on Vanilla, a spell id elsewhere)
-- to the gdb/spell id the Profit Planner keys on, mirroring CraftingEngine's
-- recipeMeta remap so the two id spaces compare correctly.
local function canonicalRecipeId(profId, rid)
    if not rid then return rid end
    if addon.recipeDB and addon.recipeDB[profId] and addon.recipeDB[profId][rid] then
        return rid
    end
    local sid = addon.GetSpellIdForCraftedItem and addon:GetSpellIdForCraftedItem(profId, rid)
    return sid or rid
end

function CraftingTab:TrySelectPending()
    local pend = self._pendingSelect
    if not (pend and self._rows and self._listLive) then return end

    local Engine = addon.CraftingEngine
    local info = Engine and Engine:GetOpenInfo() or nil
    if not info then return end          -- profession not open yet → wait
    -- A target profession was requested but a different one is open: the switch
    -- is still in flight (OpenProfession → async SHOW). Wait for that redraw.
    if pend.profId and info.profId and pend.profId ~= info.profId then return end

    for _, e in ipairs(self._rows) do
        if e.kind == "recipe"
           and (e.recipeId == pend.recipeId
                or canonicalRecipeId(info.profId, e.recipeId) == pend.recipeId) then
            self._selIndex      = e.index
            self._selId         = e.recipeId
            self._qty           = 1
            self._pendingSelect = nil
            self:SyncListSelection()
            -- Into view with two rows of context, and not at all when it is
            -- already on screen (a jump must not make the list lurch).
            self._list:ScrollToEntry(e, { context = 2, ifNeeded = true })
            self:RefreshDetail()
            return
        end
    end

    -- Right profession open with a populated list, but the recipe isn't in it —
    -- this character doesn't know it (an alt does). Stop retrying and say so
    -- once. An EMPTY list means the window is still populating, so keep waiting.
    if #self._rows > 0 then
        self._pendingSelect = nil
        if not self._pendingNotified then
            self._pendingNotified = true
            addon:Print(L["ProfitCraftNotKnownHere"])
        end
    end
end

-- ===========================================================================
-- Detail panel (bottom) — raw frame, TSM-style: reagents stacked on the left
-- (icon · name · have/need at the right of the column), controls stacked on the
-- right (− [n] + MAX / Craft / Queue). Built once and reused; RefreshDetail
-- repopulates it for the current selection. Tooltips on every element route
-- through the global addon.Tooltip.Owner anchor helper.
-- ===========================================================================
local DCTRL_W    = 230     -- right-hand controls column width
local DREAG_H    = 13      -- reagent row height (tight, ~ font height)
local DREAG_TOP  = 24      -- y-offset of the reagent list (its header bar first) from the panel top
-- controls block bottom offset (Craft Max button bottom:
-- stepper -6, Craft -34, Queue -62, Craft Max -90..-114)
local DCTRL_BOT  = 114
local DREAG_COST_W = 132   -- per-reagent cost/source width (coin string + source tag, expands left)

local function rawTip(frame, getTitle, getDesc)
    frame:SetScript("OnEnter", function()
        addon.Tooltip.Owner(frame)
        GameTooltip:SetText(getTitle(), 1, 1, 1, 1, true)
        local d = getDesc and getDesc()
        if d then GameTooltip:AddLine(d, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Attach a tooltip to a static header fontstring via an invisible overlay
-- mouse frame (fontstrings don't take mouse events themselves). `right` anchors
-- the hit area to the text's right edge; `width` overrides the auto-sized width
-- (handy for headers whose text changes, e.g. "Queue (N)").
local function headerTip(fs, right, width, title, desc)
    local hit = CreateFrame("Frame", nil, fs:GetParent())
    hit:SetPoint(right and "TOPRIGHT" or "TOPLEFT", fs, right and "TOPRIGHT" or "TOPLEFT", 0, 2)
    hit:SetSize(width or math.max(20, (fs:GetStringWidth() or 60) + 4), 16)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function()
        addon.Tooltip.Owner(hit)
        GameTooltip:SetText(title, 1, 1, 1, 1, true)
        if desc then GameTooltip:AddLine(desc, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return hit
end

function CraftingTab:SetQty(n)
    self._qty = math.max(1, math.floor(n or 1))
    if self._dpStepper then self._dpStepper:SetValue(self._qty) end
end

-- The detail panel's reagent list. One row per reagent of the selected recipe:
--   { r = <reagent>, need, enough, cntText, costText }
-- worked out by RefreshDetail, which runs on every bag update. Columns, left to
-- right: icon, "<need>x name", the line cost under the "Cost" heading, [Bank],
-- [AH], and bags/bank (green when bags + bank cover the need, else red).
function CraftingTab:BuildReagentList(host)
    return addon.W.RowList:New(host, {
        rowHeight  = DREAG_H,
        fitContent = true,
        headerFont = "GameFontNormalSmall",
        columns = {
            { key = "_icon", width = 14, iconSize = 12, iconTexCoord = true, sortable = false,
              icon = function(e) return e.r.texture or 134400 end },
            -- The required count is a "<n>x " prefix on the name ("12x Greater
            -- Eternal Essence"): as a third number in the count column it read
            -- as an inventory figure.
            { key = "name", header = L["CraftReagents"], headerTip = L["CraftReagentsDesc"], sortable = false,
              format = function(_, e) return Color("ffa0a0a0", e.need .. "x ") .. (e.r.name or "?") end },
            { key = "cost", width = DREAG_COST_W, align = "RIGHT", sortable = false,
              header = L["CraftColCostHdr"], headerTip = L["CraftColCostHdrDesc"],
              format = function(_, e) return e.costText end },
            { key = "bankBtn", width = 54, button = true, sortable = false, gapBefore = 4,
              show = function(e)
                  local id = e.r.itemId
                  return id and addon.Bank and addon.Bank.GetStock and addon.Bank.GetStock(id) > 0
              end,
              text = function(e) return addon.Bank.ButtonText(e.r.itemId) end,
              tip  = function(e)
                  local body = L["CraftBankReagentDesc"]
                  local status = addon.Bank.StatusText(e.r.itemId)
                  if status then body = body .. "\n\n" .. status end
                  return L["TooltipBankTitle"], body
              end,
              onClick = function(e)
                  if addon.Bank.ShowRequestDialog then
                      addon.Bank.ShowRequestDialog(e.r.itemId, e.r.name, e.r.link)
                  end
              end },
            { key = "ahBtn", width = 30, button = true, sortable = false,
              show = function(e)
                  local id = e.r.itemId
                  local listings = id and addon.AH and addon.AH.GetListingsFor and addon.AH.GetListingsFor(id)
                  return listings and (listings.count or 0) > 0 or false
              end,
              text = function() return "|cFF88CCFF[AH]|r" end,
              tip  = function() return L["TooltipAHTitle"], L["CraftAHReagentDesc"] end,
              onClick = function(e)
                  if addon.AH.SearchFor then addon.AH.SearchFor(e.r.name) end
              end },
            { key = "cnt", width = 60, align = "RIGHT", sortable = false, gapBefore = 2,
              format = function(_, e) return e.cntText end },
        },
        onRowEnter = function(e, _, _, rowFrame)
            if not e.r.link then return end
            addon.Tooltip.Owner(rowFrame)
            addon.ItemLink.SetItem(GameTooltip, e.r.link)
            GameTooltip:Show()
        end,
        onRowLeave = function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end,
    })
end

function CraftingTab:BuildDetailPanel(parent)
    local panel = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        panel:SetBackdropColor(0, 0, 0, 0.4)
    end
    self._detailPanel = panel

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    hint:SetText(L["CraftSelectRecipe"])
    self._dpHint = hint

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -6)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    self._dpIcon = icon

    local nameBtn = CreateFrame("Button", nil, panel)
    nameBtn:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    nameBtn:SetPoint("TOP", panel, "TOP", 0, -5)
    nameBtn:SetSize(240, 16)
    local nameFS = nameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("LEFT")
    nameFS:SetJustifyH("LEFT")
    nameBtn._fs = nameFS
    nameBtn:SetScript("OnEnter", function()
        local sel = CraftingTab._dpSel
        if sel then CraftingTab:ShowItemTooltip(nameBtn, sel.index, sel.link, sel.recipeId) end
    end)
    nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self._dpNameBtn = nameBtn

    -- Sits on the same row / font size as the "Reagents" header, right-aligned
    -- so the trailing "s" lines up with the last digit of the have/need column.
    local miss = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    miss:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(DCTRL_W + 16), -26)
    miss:SetJustifyH("RIGHT")
    miss:SetText(Color("ffff4040", L["CraftMissingMaterials"]))
    self._dpMiss = miss
    headerTip(miss, true, nil, L["CraftMissingMaterials"], L["CraftMissingMaterialsDesc"])

    -- Crafting cost — sits on the recipe-name row, right-aligned directly above
    -- the Missing Materials column label. Filled by RefreshDetail from
    -- addon.Price (vendor price for a vendor-sold reagent, else ItemDB's
    -- price ladder in the order the user set in /itemdb).
    local cost = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cost:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(DCTRL_W + 16), -8)
    cost:SetJustifyH("RIGHT")
    self._dpCost = cost
    headerTip(cost, true, 110, L["CraftCostLabel"], L["CraftCostDesc"])

    -- The reagents: a library RowList whose header bar carries the "Reagents"
    -- and "Cost" headings (each with its tooltip), sized to its rows
    -- (fitContent) so the panel can size itself to the taller column. Its host
    -- is a child of this panel, which lives for the session.
    local host = CreateFrame("Frame", nil, panel)
    host:SetPoint("TOPLEFT",  panel, "TOPLEFT",  10,               -DREAG_TOP)
    host:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(DCTRL_W + 14),  -DREAG_TOP)
    host:SetHeight(1)
    self._dpReagHost = host
    self._dpReagList = self:BuildReagentList(host)
    -- "Missing Materials" sits IN the list's header bar, right-aligned and
    -- vertically centred on it, over the [Bank] / [AH] / count columns that
    -- have no heading of their own (in game 2026-10-01: it floated above the
    -- bar and ran past its right end). 20 = the list's scrollbar lane (16)
    -- plus a 4 px inset, so the label ends where the bar's coloured strip does.
    self._dpMiss:ClearAllPoints()
    self._dpMiss:SetPoint("RIGHT", host, "TOPRIGHT", -20,
        -((self._dpReagList.headerHeight or 20) / 2))

    -- Controls (right). The stepper row sits at the TOP (no dead space above),
    -- then Craft, then Queue — all the same width (CW) so the column reads as a
    -- tidy full stack. The qty box stretches to fill the stepper row between the
    -- − and + buttons so the row looks full.
    local CR, CW = 12, DCTRL_W - 12

    -- Craft is a SECURE action button so Enchanting can work: for the Vanilla/TBC
    -- Craft window we set a "/cast <recipe>" macro on this button per selection
    -- (RefreshDetail) and the click casts it securely; for ordinary trade skills
    -- the macro is cleared and PreClick runs the normal Lua craft (DoTradeSkill,
    -- which also supports batch quantity). PreClick is insecure but runs before
    -- the secure cast, so the trade-skill path is unaffected.
    --
    -- The click registration is set per selection in RefreshDetail, NOT here --
    -- see the note there. "LeftButtonUp" alone is the correct (and only safe)
    -- default for the insecure trade-skill path.
    --
    -- The button is NOT parented into the panel. A frame with a secure child is
    -- itself protected, and so is every ancestor -- and the panel lives inside
    -- AceGUI's pooled window. Up to v1.1.1 that made TOGPM's whole window
    -- protected, so closing it in combat failed with ADDON_ACTION_BLOCKED
    -- "Frame:Hide()" (blamed on Ace3; reported in game 2026-09-26), and the
    -- pooled frame would carry the protection to the next addon given it. So it
    -- lives on a holder of our own, parented to UIParent, only ANCHORED to the
    -- panel. A secure state driver hides the holder for the whole of combat --
    -- nobody can craft in combat, and the driver is Blizzard's secure code, so it
    -- may hide a protected frame then (SecureStateDriver.lua:98, classic_era).
    -- Everything else about the button's visibility, stacking and scale is
    -- synced out of combat by SyncCraftButton.
    local holder = CreateFrame("Frame", "TOGPMCraftButtonHolder", UIParent)
    holder:SetAllPoints(UIParent)
    if RegisterStateDriver then RegisterStateDriver(holder, "visibility", "[combat] hide; show") end
    self._dpCraftHolder = holder
    self._dpCraft = nil
    -- NOT anchored to the panel either: protection also carries to "any frames
    -- they are anchored to" (warcraft.wiki.gg Secure_Execution_and_Tainting,
    -- quoted by Peer Review 2026-09-26). SyncCraftButton places it at the panel's
    -- screen position, relative to the holder only. These are its panel-relative
    -- coordinates: CR in from the right edge, _dpCraftY down from the top.
    self._dpCraftRight, self._dpCraftY, self._dpCraftW = CR, -34, CW
    self:EnsureCraftButton()
    -- Follow the panel: when the window closes, switches tab or reopens, the
    -- button (which is not the panel's child) has to be told.
    panel:HookScript("OnShow", function() CraftingTab:SyncCraftButton() end)
    panel:HookScript("OnHide", function() CraftingTab:SyncCraftButton() end)

    local queueBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    queueBtn:SetSize(CW, 24)
    queueBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -CR, -90)
    queueBtn:SetText(L["CraftQueueButton"])
    queueBtn:SetScript("OnClick", function()
        local sel = CraftingTab._dpSel
        local info = addon.CraftingEngine and addon.CraftingEngine:GetOpenInfo()
        if sel and info and addon.CraftQueue then
            addon.CraftQueue:Add(info.profId, sel.recipeId, CraftingTab._qty or 1)
        end
    end)
    rawTip(queueBtn, function() return L["CraftQueueButton"] end, function() return L["CraftQueueDesc"] end)
    self._dpQueue = queueBtn

    -- Craft Max: queue the most this recipe can make right now AND start crafting
    -- it in one click (Skillet's "Create All"). Sits between Craft and Queue. Lets
    -- you fan across several recipes — Craft Max each — to stack them up fast.
    local craftMaxBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    craftMaxBtn:SetSize(CW, 24)
    craftMaxBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -CR, -62)
    craftMaxBtn:SetText(L["CraftMaxButton"])
    craftMaxBtn:SetScript("OnClick", function()
        local sel  = CraftingTab._dpSel
        local info = addon.CraftingEngine and addon.CraftingEngine:GetOpenInfo()
        if sel and info and addon.CraftQueue then
            local maxQ = math.max(1, sel.num or 1)
            CraftingTab:SetQty(maxQ)
            addon.CraftQueue:Add(info.profId, sel.recipeId, maxQ)
            addon.CraftQueue:CraftNext()
        end
    end)
    rawTip(craftMaxBtn, function() return L["CraftMaxButton"] end, function() return L["CraftMaxButtonDesc"] end)
    self._dpCraftMax = craftMaxBtn

    -- Stepper row, aligned to the Craft button's edges (full width): − [qty] + MAX.
    -- The library's stepper has no upper bound here: Queue deliberately takes
    -- more than the materials on hand make. So its own MAX (which caps at `max`)
    -- is not used; ours sets the quantity to what can be made now.
    local maxBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    maxBtn:SetSize(46, 22)
    maxBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -CR, -6)
    maxBtn:SetText(L["CraftMax"])
    maxBtn:SetScript("OnClick", function()
        local sel = CraftingTab._dpSel
        CraftingTab:SetQty(sel and sel.num or 1)
    end)
    rawTip(maxBtn, function() return L["CraftMax"] end, function() return L["CraftMaxDesc"] end)
    self._dpMax = maxBtn

    -- Anchored to the panel, not the Craft button: the button is placed from
    -- outside the window and does not move while the window is dragged in combat.
    -- Box width: the column less MAX (46 + 4) and the stepper's two 22 px
    -- buttons with their gaps (54).
    local stepper = addon.W:CreateStepper(panel, {
        min = 1, value = self._qty or 1, width = CW - 46 - 4 - 54,
        tipTitle = L["CraftQuantity"],
        onValueChanged = function(v) CraftingTab._qty = v end,
    })
    stepper:SetPoint("TOPLEFT", panel, "TOPRIGHT", -CR - CW, -6)
    self._dpStepper = stepper
end

-- The secure Craft button, on the holder (never the panel -- see
-- BuildDetailPanel). The library's factory returns nil in combat, so this is
-- retried by SyncCraftButton after combat; every use checks for it. Nobody can
-- craft in combat, and the holder's state driver hides it then anyway.
function CraftingTab:EnsureCraftButton()
    if self._dpCraft then return self._dpCraft end
    if not (self._dpCraftHolder and addon.W) then return nil end
    local craftBtn = addon.W:CreateSecureActionButton(self._dpCraftHolder, {
        name     = "TOGPMCraftButton",
        text     = L["CraftButton"],
        width    = self._dpCraftW or 218,
        height   = 24,
        tipTitle = L["CraftButton"],
        tipBody  = L["CraftButtonDesc"],
        preClick = function()
            if CraftingTab._craftIsSecure then return end  -- enchant: the secure /cast macro handles it
            local sel = CraftingTab._dpSel
            if sel and addon.CraftingEngine then
                addon.CraftingEngine:Craft(sel.recipeId, sel.index, CraftingTab._qty or 1)
            end
        end,
    })
    if not craftBtn then return nil end
    -- The factory registers both clicks, which the secure half needs (it acts on
    -- exactly one of them); the insecure trade-skill PreClick would then craft
    -- twice. So up-only until RefreshDetail picks the mode for the recipe.
    craftBtn:RegisterForClicks("LeftButtonUp")
    craftBtn:Hide()
    self._dpCraft = craftBtn
    return craftBtn
end

--- The items Scan AH looks up for the selected recipe: the crafted item first
--- (so the detail panel's AH price and Profit line get a number), then each
--- reagent (so the per-reagent [AH] buttons light up). Empty with nothing
--- selected. An enchant has no crafted item and contributes only reagents.
function CraftingTab:ScanAHItems()
    local items = {}
    local Engine = addon.CraftingEngine
    if not (self._selIndex and Engine) then return items end

    local sel
    for _, e in ipairs(Engine:GetRecipeList()) do
        if e.kind == "recipe" and e.index == self._selIndex then sel = e; break end
    end
    local craftedId = sel and sel.link and tonumber(sel.link:match("item:(%d+)"))
    local craftedName = sel and sel.link and sel.link:match("%[(.-)%]")
    if craftedId and craftedName and craftedName ~= "" then
        items[#items + 1] = { itemId = craftedId, itemName = craftedName }
    end

    for _, r in ipairs(Engine:GetReagents(self._selIndex)) do
        if r.itemId and r.name and r.name ~= "" and r.itemId ~= craftedId then
            items[#items + 1] = { itemId = r.itemId, itemName = r.name }
        end
    end
    return items
end

function CraftingTab:RefreshDetail()
    local panel = self._detailPanel
    if not panel then return end
    local Engine = addon.CraftingEngine

    local sel
    if self._selIndex and Engine then
        for _, e in ipairs(Engine:GetRecipeList()) do
            if e.kind == "recipe" and e.index == self._selIndex then sel = e; break end
        end
        if not sel then self._selIndex = nil end
    end
    self._dpSel = sel

    -- The secure Craft button is NOT in this list: showing or hiding it is
    -- protected in combat, so SyncCraftButton owns its visibility.
    local widgets = { self._dpIcon, self._dpNameBtn, self._dpReagHost,
                      self._dpStepper, self._dpMax,
                      self._dpQueue, self._dpCraftMax }
    if not sel then
        self._dpHint:Show()
        self._dpMiss:Hide()
        if self._dpCost then self._dpCost:Hide() end
        for _, w in ipairs(widgets) do w:Hide() end
        self:SyncCraftButton()
        self._detailH = 56          -- compact: just the hint
        self:ApplyDetailHeight()
        return
    end
    self._dpHint:Hide()
    for _, w in ipairs(widgets) do w:Show() end

    self._dpIcon:SetTexture(sel.icon or 134400)
    self._dpNameBtn._fs:SetText(Color(sel.color or (addon.BrandColor or "ffFF8000"), sel.name))
    -- SetValue rewrites the box even while the player is typing in it, and this
    -- runs on every bag update; only a changed quantity (a new selection, MAX)
    -- is set, and otherwise the non-forcing Refresh leaves a half-typed number.
    if self._dpStepper:GetValue() ~= (self._qty or 1) then
        self._dpStepper:SetValue(self._qty or 1)
    else
        self._dpStepper:Refresh()
    end
    local canCraft = (sel.num or 0) > 0
    -- The Craft button is SECURE (enchant /cast), so Enable/Disable is protected
    -- during combat lockdown — guard it. _dpCraftMax is a normal button (safe).
    -- It does not exist yet when the panel was first built in combat.
    local craft = self:EnsureCraftButton()
    if craft and not (InCombatLockdown and InCombatLockdown()) then
        craft:SetEnabled(canCraft)
    end
    if self._dpCraftMax.SetEnabled then self._dpCraftMax:SetEnabled(canCraft) end

    -- Point the (secure) Craft button at this recipe. Enchanting (Craft window)
    -- must be cast via a secure /cast macro since Lua DoCraft is protected; the
    -- recipe name IS the spell name. Trade skills clear the macro and let the
    -- PreClick do the normal Lua craft. SetAttribute is forbidden in combat, so
    -- guard it (you can't craft in combat anyway).
    self._craftIsSecure = (Engine._isCraftWindow and sel.name and sel.name ~= "") and true or false
    if craft and not (InCombatLockdown and InCombatLockdown()) then
        if self._craftIsSecure then
            craft:SetAttribute("type", "macro")
            craft:SetAttribute("macrotext", "/cast " .. sel.name)
        else
            craft:SetAttribute("type", nil)
            craft:SetAttribute("macrotext", nil)
        end
        -- The secure half of this button ONLY fires if the registered click
        -- matches Blizzard's key-down/key-up gate. SecureActionButton_OnClick
        -- runs the action only when
        --   (down and useOnKeyDown) or (not down and not useOnKeyDown)
        -- where useOnKeyDown falls back to the `ActionButtonUseKeyDown` CVar
        -- (ElvUI / Bartender4 and Blizzard's own "use key down" option set it).
        -- Registered for "LeftButtonUp" ONLY, the button was therefore DEAD for
        -- every player with that CVar on: the click dispatched, the secure gate
        -- discarded it, and no enchant was ever cast — while trade skills kept
        -- working because they craft from the insecure PreClick, which isn't
        -- gated. That is exactly the reported "Enchanting is the only profession
        -- that doesn't work". TSM's SecureMacroActionButton branches on the same
        -- CVar for the same reason.
        --
        -- Registering BOTH clicks satisfies the gate whichever way the CVar is
        -- set (and whichever variant of the gate the client ships), and exactly
        -- one of the two passes it, so the enchant casts once. Only do it in
        -- secure/enchant mode: PreClick fires on every registered click, so with
        -- both registered the trade-skill path would craft twice per click.
        if self._craftIsSecure then
            craft:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
        else
            craft:RegisterForClicks("LeftButtonUp")
        end
    end

    -- Enchanting is applied one item at a time, so present a single "Enchant"
    -- button: hide the quantity stepper, Craft Max and Queue, and pull Enchant up
    -- to the top of the controls column. Trade skills keep "Craft" plus the full
    -- stepper / Craft Max / Queue stack at their normal positions.
    local isEnchant = Engine._isCraftWindow and true or false
    if craft then craft:SetText(isEnchant and L["CraftEnchantButton"] or L["CraftButton"]) end
    -- Where the (secure) button sits in the panel; SyncCraftButton places it
    -- there, out of combat only.
    self._dpCraftY = isEnchant and -6 or -34
    if isEnchant then
        self._dpStepper:Hide(); self._dpMax:Hide()
        self._dpCraftMax:Hide(); self._dpQueue:Hide()
    end
    self:SyncCraftButton()

    local reagents = Engine:GetReagents(self._selIndex)
    local missing, rows = false, {}
    for _, r in ipairs(reagents) do
        -- The count column is your inventory, bags / bank: bags is live
        -- (GetItemCount), bank is the snapshot from your last bank visit
        -- (ReagentWatch persists it on BANKFRAME_CLOSED). "Enough" (and the
        -- Missing-Materials flag) counts both, so a reagent stashed in the bank
        -- doesn't read as missing.
        local need = r.need or 0
        local bags = (r.itemId and addon.Item.GetCount(r.itemId)) or r.have or 0
        local bankq = (r.itemId and addon.ReagentWatch and addon.ReagentWatch:GetBankCount(r.itemId)) or 0
        local enough = (bags + bankq) >= need
        if not enough then missing = true end

        -- Per-reagent line cost: unit price × needed. "—" when unpriced.
        -- GetReagentCost, not Get: a vendor-sold reagent is costed at the
        -- vendor price, so this line agrees with the total below it.
        local costText = ""
        if addon.Price and r.itemId then
            local p, src = addon.Price.GetReagentCost(r.itemId)
            costText = p and (addon.Price.Money(p * (r.need or 1)) .. PriceSourceTag(src))
                or Color("ff888888", "—")
        end

        rows[#rows + 1] = {
            r = r, need = need, enough = enough, costText = costText,
            cntText = Color(enough and "ff40c040" or "ffff4040", ("%d/%d"):format(bags, bankq)),
        }
    end
    self._dpReagList:SetData(rows)
    if missing then self._dpMiss:Show() else self._dpMiss:Hide() end

    -- Crafting cost (per single craft, matching the reagent have/need rows).
    -- "*" = one or more reagents unpriced (total is a lower bound); "~" = a
    -- contributing price is stale. "—" when nothing could be priced.
    if self._dpCost then
        local Pr = addon.Price
        if Pr then
            local label = Color("ffaaaaaa", L["CraftCostLabel"] .. ": ")
            local total, priced, count, stale = Pr.CraftCostForReagents(reagents, 1)
            local fullyPriced = (priced == count and count > 0)
            local segs = {}
            if priced == 0 or count == 0 then
                segs[#segs + 1] = label .. Color("ff888888", L["CraftCostNone"])
            else
                local money = Pr.Money(total)
                local marks = (priced < count and " *" or "") .. (stale and " ~" or "")
                if marks ~= "" then money = money .. Color("ffffd100", marks) end
                segs[#segs + 1] = label .. money
            end

            -- AH sale price of the CRAFTED item + profit/loss vs the crafting
            -- cost. `GetSaleLive` is the auction ladder only -- every enabled
            -- ItemDB source, never a vendor price, because a vendor price isn't
            -- a sale price. (Until v1.1.0 this read `Pr.Get` and then accepted
            -- only Auctionator's or the own scan's id, so an Auctioneer or TSM
            -- price never showed here.) Profit only when the craft cost is fully
            -- known: sell − cost, green = you'd make coin, red = you'd lose it.
            -- (Assumes one craft yields one item and ignores the AH cut.)
            local craftedId = sel.link and tonumber(sel.link:match("item:(%d+)"))
            local ah, ahSrc
            if craftedId and Pr.GetSaleLive then
                ah, ahSrc = Pr.GetSaleLive(craftedId)
            end
            if ah then
                segs[#segs + 1] = Color("ffaaaaaa", L["CraftAHPriceLabel"] .. ": ")
                    .. Pr.Money(ah) .. PriceSourceTag(ahSrc)
                if fullyPriced then
                    local profit = ah - total
                    local col  = profit >= 0 and "ff40c040" or "ffff4040"
                    local sign = profit >= 0 and "+" or "-"
                    segs[#segs + 1] = Color("ffaaaaaa", L["CraftProfitLabel"] .. ": ")
                        .. Color(col, sign .. Pr.Money(math.abs(profit)))
                end
            end

            self._dpCost:SetText(table.concat(segs, "   "))
            self._dpCost:Show()
        else
            self._dpCost:Hide()
        end
    end

    -- Auto-size the panel to its taller column (reagents vs controls) so there's
    -- no dead space below — the recipe list above grows into the freed room.
    -- The list sized its host to its header plus its rows (fitContent).
    local reagentsBottom = DREAG_TOP + (self._dpReagHost:GetHeight() or 0)
    -- Enchanting shows only the single Enchant button (top of the column), so its
    -- controls block is short; trade skills use the full stepper/Craft/Max/Queue.
    local ctrlBottom = isEnchant and 30 or DCTRL_BOT
    self._detailH = math.max(math.max(reagentsBottom, ctrlBottom) + 10, 96)
    self:ApplyDetailHeight()
end

-- ===========================================================================
-- Queue panel (right column)
-- ===========================================================================
function CraftingTab:BuildQueuePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        panel:SetBackdropColor(0, 0, 0, 0.4)
    end
    self._queuePanel = panel

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", Q_PAD, -6)
    self._queueTitle = title
    headerTip(title, false, 120, L["CraftQueueHeaderTitle"], L["CraftQueueHeaderDesc"])

    -- Craft Next | Clear All side by side, each taking half the width.
    -- Three buttons on one row at the same total width as before: Craft Next |
    -- Craft All | Clear All. Craft Next and Clear All take a fixed third at each
    -- end; Craft All fills the middle between them.
    local QBW = math.floor((QUEUE_W - 2 * Q_PAD - 2 * 4) / 3)

    local craftNext = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    craftNext:SetSize(QBW, 24)
    craftNext:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", Q_PAD, Q_PAD)
    craftNext:SetText(L["CraftCraftNext"])
    craftNext:SetScript("OnClick", function() if addon.CraftQueue then addon.CraftQueue:CraftNext() end end)
    self._craftNextBtn = craftNext

    local clearAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearAll:SetSize(QBW, 24)
    clearAll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -Q_PAD, Q_PAD)
    clearAll:SetText(L["CraftClearAll"])
    clearAll:SetScript("OnClick", function() if addon.CraftQueue then addon.CraftQueue:Clear() end end)
    self._clearAllBtn = clearAll

    -- Craft All: work down the whole queue, crafting each eligible recipe in turn.
    local craftAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    craftAll:SetHeight(24)
    craftAll:SetPoint("BOTTOMLEFT",  craftNext, "BOTTOMRIGHT", 4, 0)
    craftAll:SetPoint("BOTTOMRIGHT", clearAll,  "BOTTOMLEFT", -4, 0)
    craftAll:SetText(L["CraftCraftAll"])
    craftAll:SetScript("OnClick", function() if addon.CraftQueue then addon.CraftQueue:CraftAll() end end)
    self._craftAllBtn = craftAll

    -- The rows: a reorderable LibAceGUIWidgets RowList between the title and the
    -- footer buttons. Dragging a row lifts it and draws the insert line; the drop
    -- is handed to CraftQueue:Move, whose (from, to) is the list's own contract
    -- ("the index it should have after the move"), and _Changed redraws it.
    local listHost = CreateFrame("Frame", nil, panel)
    listHost:SetPoint("TOPLEFT", panel, "TOPLEFT", Q_PAD, -Q_TITLE_H)
    listHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -Q_PAD, Q_FOOTER_H)
    self._queueList = addon.W.RowList:New(listHost, {
        rowHeight      = QROW_H,
        hoverHighlight = true,
        reorderable    = true,
        onReorder      = function(from, to)
            if addon.CraftQueue then addon.CraftQueue:Move(from, to) end
        end,
        columns = {
            { key = "icon", width = 14, iconSize = 14, iconTexCoord = true, sortable = false,
              icon = function(r) return r.icon or 134400 end },
            { key = "name", format = function(v, r)
                  return Color(r.craftable and "ffffffff" or "ff888888", v or "")
              end },
            { key = "qty", width = 34, align = "RIGHT",
              format = function(v) return Color("ffe6e6e6", "x" .. tostring(v or 0)) end },
            { key = "remove", width = 16, button = true, sortable = false,
              text = function() return "|cffff5555x|r" end,
              -- Left-click only, as the old [x] button was: a stray right-click
              -- must not delete a queue entry.
              onClick = function(_, idx, _, mouseButton)
                  if mouseButton ~= "LeftButton" then return end
                  if addon.CraftQueue then addon.CraftQueue:Remove(idx) end
              end },
        },
    })
end

function CraftingTab:QueueEntryDisplay(e)
    local Engine = addon.CraftingEngine
    local live = Engine and Engine:GetRecipeEntry(e.recipeId)
    if live then return live.name, live.icon end
    local meta = addon.recipeDB and addon.recipeDB[e.profId] and addon.recipeDB[e.profId][e.recipeId]
    local name = (meta and meta.name)
              or addon.Spell.GetInfo(e.recipeId)
              or ("#" .. tostring(e.recipeId))
    local icon = (meta and meta.icon)
              or (meta and meta.craftedItemId and addon.Item.GetIcon(meta.craftedItemId))
              or addon.Spell.GetTexture(e.recipeId)
    return name, icon
end

function CraftingTab:RefreshQueue()
    local panel = self._queuePanel
    if not panel then return end

    local q = addon.CraftQueue and addon.CraftQueue:Get() or {}
    self._queueTitle:SetText(Brand(L["CraftQueueTitle"]:format(#q)))

    local Engine = addon.CraftingEngine
    local info   = Engine and Engine:GetOpenInfo()

    -- One display row per queue entry, in queue order (the list is unsorted, so
    -- its index IS the queue index Move and Remove take). Built fresh: the queue
    -- entries are saved variables and get no display fields written onto them.
    local rows = {}
    for i, e in ipairs(q) do
        local name, icon = self:QueueEntryDisplay(e)
        local craftable = false
        if info and e.profId == info.profId then
            local live = Engine:GetRecipeEntry(e.recipeId)
            craftable = live and (live.num or 0) > 0 or false
        end
        rows[i] = { name = name, icon = icon, qty = e.qty, craftable = craftable }
    end
    if self._queueList then self._queueList:SetData(rows, true) end

    local canCraftNext = addon.CraftQueue and addon.CraftQueue:CanCraftNext()
    if self._craftNextBtn then
        if canCraftNext then self._craftNextBtn:Enable() else self._craftNextBtn:Disable() end
    end
    if self._craftAllBtn then
        if canCraftNext then self._craftAllBtn:Enable() else self._craftAllBtn:Disable() end
    end
end

-- ===========================================================================
-- Cleanup + refresh hooks
-- ===========================================================================
-- Show the secure Craft button exactly when the detail panel is on screen with a
-- recipe selected, placed over the panel at the window's strata and scale. The
-- button lives on TOGPMCraftButtonHolder (UIParent) and is anchored to nothing
-- but that holder -- see BuildDetailPanel -- so it does not follow the panel by
-- itself: this reads the panel's rect and places it. The holder's scale is set
-- to the panel's, so the panel's own coordinates are the holder's coordinates
-- (the holder fills UIParent from the screen's bottom-left).
--
-- Everything here is protected on a secure frame, so it runs only out of combat.
-- In combat the holder's state driver has hidden the button; PLAYER_REGEN_ENABLED
-- re-syncs it, so a window closed mid-fight does not leave the button behind.
-- KNOWN GAP (not verified in a client): if the driver re-shows the holder before
-- PLAYER_REGEN_ENABLED fires, a button for a window closed in combat can show
-- until that event, expected to be the same frame.
-- How far above the panel the button is stacked: the panel's own children (the
-- reagent list's rows and header) sit a few levels above it. Same margin the
-- Cooldowns popup uses over the window.
local CRAFT_BTN_LEVEL_ABOVE = 100

-- Where and how the button was last placed: position, scale and stacking. Any
-- change re-places it.
local function craftBtnKey(panel, right, top)
    return string.format("%.2f:%.2f:%.4f:%d", right, top,
        panel:GetEffectiveScale(), panel:GetFrameLevel())
end

function CraftingTab:SyncCraftButton()
    if InCombatLockdown and InCombatLockdown() then return end
    local btn, holder, panel = self._dpCraft, self._dpCraftHolder, self._detailPanel
    if not btn and holder then
        -- The panel was built in combat, when the factory refuses: build it now,
        -- and give it the selected recipe's attributes (RefreshDetail calls back).
        btn = self:EnsureCraftButton()
        if btn and self._dpSel then return self:RefreshDetail() end
    end
    if not (btn and holder and panel) then return end
    local want = panel:IsVisible() and self._dpSel ~= nil
    local right, top = panel:GetRight(), panel:GetTop()
    if want and right and top then
        holder:SetFrameStrata(panel:GetFrameStrata())
        local uiScale = UIParent:GetEffectiveScale()
        if uiScale and uiScale > 0 then holder:SetScale(panel:GetEffectiveScale() / uiScale) end
        -- The window is Toplevel (AceGUIContainer-Frame.lua:194): every click on
        -- it Raises it within FULLSCREEN_DIALOG, above this button, which is not
        -- its descendant. The button then sat dimmed under the panel and took no
        -- clicks (Discord, 2026-09-29, Enchanting). So the level is part of the
        -- watcher's key, and the margin clears the panel's own children.
        btn:SetFrameLevel(panel:GetFrameLevel() + CRAFT_BTN_LEVEL_ABOVE)
        btn:ClearAllPoints()
        btn:SetPoint("TOPRIGHT", holder, "BOTTOMLEFT",
            right - (self._dpCraftRight or 12), top + (self._dpCraftY or -34))
        btn:Show()
        self._craftBtnPlacedAt = craftBtnKey(panel, right, top)
    else
        btn:Hide()
        self._craftBtnPlacedAt = nil
    end
    -- The watcher runs whenever the button is WANTED, not only while it is
    -- shown: a panel not laid out yet has no rect, the button stays hidden, and
    -- only the watcher will notice the rect arriving and place it.
    if self._craftBtnWatcher then
        if want then self._craftBtnWatcher:Show() else self._craftBtnWatcher:Hide() end
    end
end

-- The panel moves with the window (a drag, a resize, a window-scale change) and
-- nothing tells the button. While the button is shown, this plain frame checks
-- the panel's rect each frame and re-places the button when it changed -- out of
-- combat only; in combat the button is hidden and need not follow.
local watcher = CreateFrame("Frame")
watcher:Hide()
watcher:SetScript("OnUpdate", function()
    if InCombatLockdown and InCombatLockdown() then return end
    local panel = CraftingTab._detailPanel
    local right, top = panel and panel:GetRight(), panel and panel:GetTop()
    if not (right and top) then return end
    local key = craftBtnKey(panel, right, top)
    if key ~= CraftingTab._craftBtnPlacedAt then CraftingTab:SyncCraftButton() end
end)
CraftingTab._craftBtnWatcher = watcher

local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function() CraftingTab:SyncCraftButton() end)

function CraftingTab:OnQueueChanged()
    local mw = addon.MainWindow
    if mw and mw.frame and mw.activeTab == "crafting" and self._queuePanel then
        self:RefreshQueue()
    end
end

function CraftingTab:OnLiveRefresh()
    local mw = addon.MainWindow
    if not (mw and mw.frame and mw.activeTab == "crafting" and self._listLive) then return end
    self:FillList()
    self:RefreshDetail()
    self:RefreshQueue()
end

function CraftingTab:OnSessionChanged()
    local mw = addon.MainWindow
    if mw and mw.frame and mw.tabs and mw.activeTab == "crafting" then
        mw.tabs:ReleaseChildren()
        mw:DrawTab("crafting", mw.tabs)
    end
end

-- Refresh cost-to-craft (and per-row [AH] buttons) when an AH scan finishes —
-- so prices populate live after the auto full-scan on AH open, with no need to
-- re-select the recipe. Distinct receiver (CraftingTab) so this coexists with
-- the addon-keyed AH_SCAN_COMPLETE handler in GUI/SharedWidgets.lua.
if addon.RegisterCallback then
    addon.RegisterCallback(CraftingTab, "AH_SCAN_COMPLETE", function()
        if addon.CraftingTab then addon.CraftingTab:OnLiveRefresh() end
    end)
    -- No WINDOW_RESIZED handler: the dock re-lays itself from its own size, and
    -- each RowList re-sizes its pool from its parent's.
end
