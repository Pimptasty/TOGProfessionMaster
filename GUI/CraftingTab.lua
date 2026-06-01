-- TOG Profession Master — Crafting tab (view)
--
-- A single-character crafting UI that REPLACES the native profession window
-- (see Modules/Crafting/CraftingEngine.lua for the window-hijack engine and
-- Modules/Crafting/CraftQueue.lua for the queue model + completion tracking).
--
-- Recipe list: virtual-scroll raw-frame pool (35 reused frames, manual content
-- height, no-op scroll LayoutFinished) like BrowserTab — near-instant, no
-- AceGUI relayout thrash. Columns: Recipe Name | Skill | Craft, all sortable
-- (click a header: none → asc → desc → none); recipe names are tinted by the
-- crafted item's QUALITY colour (white/green/blue/purple); hovering a row shows
-- the in-game item tooltip, shift-click links it in chat.
--
-- LAYOUT (TSM-style, manual anchoring via container.LayoutFinished — the
-- TabGroup container is not pool-recycled across tabs): toolbar on top; recipe
-- list (left) + Queue panel (right); detail panel pinned across the bottom.

local _, addon = ...
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local CraftingTab = {}
addon.CraftingTab = CraftingTab

-- Resizable (shares the saved "resizable" size with the Browser tab via
-- MainWindow). minWidth holds the known-good width so the recipe columns + the
-- fixed-width queue panel never overlap; height can shrink a little and grow
-- freely. The layout itself is responsive — AnchorAll pins the detail panel to
-- the bottom edge, the queue panel to the right edge, and lets the recipe list
-- fill the rest, so it reflows to any size (re-run via container.LayoutFinished
-- on the AceGUI resize cascade + the WINDOW_RESIZED handler below).
CraftingTab.WINDOW_SIZE = { minWidth = 820, minHeight = 540 }

-- Recipe list geometry — shared by the header and the row pool so columns line
-- up. Offsets are measured from the left edge of both (header frame and the
-- scroll content share that left edge), so the scrollbar on the right doesn't
-- affect alignment.
local ROW_HEIGHT = 16
local POOL_SIZE  = 35
local ICON_X     = 4
local NAME_X     = 22
local NAME_W     = 250
local SKILL_X    = 280     -- Skill column shows 4 colored tiers (orange/yellow/green/grey)
local SKILL_W    = 104
local COUNT_X    = 392
local COUNT_W    = 48

local DETAIL_H    = 120   -- fallback; the panel auto-sizes to its content (self._detailH)
local QUEUE_W     = 250
local QROW_H      = 18
local Q_TITLE_H   = 24
local Q_FOOTER_H  = 32
local Q_PAD       = 8
local QUEUE_POOL  = 60
local GAP         = 8

CraftingTab._search   = ""
CraftingTab._haveOnly = false
CraftingTab._selIndex = nil
CraftingTab._selId    = nil
CraftingTab._qty      = 1
CraftingTab._sortCol  = nil    -- nil = native category tree; "name"|"skill"|"craft"
CraftingTab._sortAsc  = true

local function Brand(text) return "|c" .. (addon.BrandColor or "ffFF8000") .. text .. "|r" end
local function Color(hex, text) return "|c" .. hex .. text .. "|r" end

local Ace = addon.lib
local function savedProf() return Ace.db and Ace.db.char and Ace.db.char.craftSelProf or nil end
local function setSavedProf(name) if Ace.db and Ace.db.char then Ace.db.char.craftSelProf = name end end

local function findProf(professions, name)
    for _, p in ipairs(professions) do
        if p.name == name then return p end
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

    local list, order = {}, {}
    for _, p in ipairs(professions) do
        list[p.name]    = ("%s (%d/%d)"):format(p.name, p.rank, p.max)
        order[#order+1] = p.name
    end
    local profDD = AceGUI:Create("Dropdown")
    profDD:SetWidth(230)
    profDD:SetList(list, order)
    profDD:SetValue(active)
    profDD:SetCallback("OnValueChanged", function(_w, _e, name)
        setSavedProf(name)
        if not (info and info.name == name) then
            -- Queue is kept across profession switches by design (bounce between
            -- professions toward one goal). Opt-in setting clears it on switch.
            if Ace.db and Ace.db.profile and Ace.db.profile.clearQueueOnProfSwitch
               and addon.CraftQueue then
                addon.CraftQueue:Clear()
            end
            local p = findProf(professions, name)
            if Engine then Engine:OpenProfession(p and p.castName or name) end
        end
    end)
    addon.GUI.AttachTooltip(profDD, L["CraftColRecipe"], L["CraftProfessionDesc"])
    toolbar:AddChild(profDD)

    if not info then
        -- No profession window is open yet, but the player deliberately navigated
        -- to the Crafting tab — that IS "I want to craft in TOGPM", so just open
        -- their (selected) profession for them instead of making them click the
        -- button below. OpenProfession forces the resulting window into the TOGPM
        -- tab (not Blizzard) regardless of the default-to-Blizzard takeover
        -- setting, since they asked for it here. Can't cast in combat, so the
        -- prompt + button below stay as the fallback. The button is also there if
        -- the auto-open is somehow suppressed.
        local activeEntry = active and findProf(professions, active) or nil
        if Engine and activeEntry
           and not (UnitAffectingCombat and UnitAffectingCombat("player")) then
            Engine:OpenProfession(activeEntry.castName or active)
        end

        local prompt = AceGUI:Create("Label")
        prompt:SetFullWidth(true)
        prompt:SetText("\n" .. Color("ffffffff", L["CraftOpenToView"]:format(active or "")))
        container:AddChild(prompt)

        local openBtn = AceGUI:Create("Button")
        openBtn:SetWidth(220)
        openBtn:SetText(L["CraftOpenButton"]:format(active or ""))
        openBtn:SetCallback("OnClick", function()
            if Engine and activeEntry then Engine:OpenProfession(activeEntry.castName or active) end
        end)
        container:AddChild(openBtn)
        return
    end

    local search = AceGUI:Create("EditBox")
    search:SetWidth(165)
    search:SetText(self._search or "")
    search:DisableButton(true)
    search:SetCallback("OnTextChanged", function(_w, _e, text)
        self._search = text or ""
        self:FillList()
    end)
    addon.GUI.AttachTooltip(search, L["SearchPlaceholder"], L["CraftSearchDesc"])
    toolbar:AddChild(search)

    local haveBtn = AceGUI:Create("CheckBox")
    haveBtn:SetLabel(L["CraftHaveMaterials"])
    haveBtn:SetWidth(130)
    haveBtn:SetValue(self._haveOnly and true or false)
    haveBtn:SetCallback("OnValueChanged", function(_w, _e, val)
        self._haveOnly = val and true or false
        self:FillList()
    end)
    addon.GUI.AttachTooltip(haveBtn, L["CraftHaveMaterials"], L["CraftHaveMaterialsDesc"])
    toolbar:AddChild(haveBtn)

    -- Scan AH for the selected recipe's reagents → the per-reagent [AH] buttons
    -- light up. Self-attaches to the toolbar (between Have Materials and WoW UI).
    addon.GUI.MakeScanAHButton({
        parent        = toolbar,
        tabName       = "crafting",
        label         = L["CraftScanAH"],
        progressLabel = L["CraftScanAHProgress"],
        tooltipTitle  = L["CraftScanAH"],
        tooltipDesc   = L["CraftScanAHDesc"],
        width         = 110,
        noItemsError  = L["CraftScanAHNoItems"],
        getItems      = function()
            local items = {}
            if self._selIndex and Engine then
                for _, r in ipairs(Engine:GetReagents(self._selIndex)) do
                    if r.itemId and r.name and r.name ~= "" then
                        items[#items + 1] = { itemId = r.itemId, itemName = r.name }
                    end
                end
            end
            return items
        end,
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

    local cContent = container.content or container.frame

    -- Column headers (raw, sortable, aligned with the row columns).
    if not self._headerFrame then self:BuildHeaders(cContent) else
        self._headerFrame:SetParent(cContent); self._headerFrame:Show()
    end
    self:UpdateHeaderText()

    -- Recipe list (virtual scroll).
    local scroll = addon.GUI.PersistentScroll.Acquire(self, {
        layout = "List", fullWidth = true, fullHeight = true,
        onRelease = function() self:DetachPool() end,
    })
    container:AddChild(scroll)
    self._scroll = scroll
    scroll.LayoutFinished = function() end

    if not self._pool then
        self:BuildPool(scroll.content)
    else
        for _, f in ipairs(self._pool) do f:SetParent(scroll.content) end
    end
    if scroll.scrollbar then
        scroll.scrollbar:SetScript("OnValueChanged", function(bar, value)
            if bar.obj and bar.obj.SetScroll then bar.obj:SetScroll(value) end
            self:UpdateVirtualRows()
        end)
    end

    -- Detail panel (bottom) — persistent raw frame for precise alignment.
    if not self._detailPanel then self:BuildDetailPanel(cContent) else
        self._detailPanel:SetParent(cContent); self._detailPanel:Show()
    end

    -- Queue panel (right).
    if not self._queuePanel then self:BuildQueuePanel(cContent) else
        self._queuePanel:SetParent(cContent); self._queuePanel:Show()
    end

    local function AnchorAll()
        local cc = container.content or container.frame
        if not (cc and self._scroll and self._scroll.frame and self._detailPanel
                and self._headerFrame and self._queuePanel) then return end

        local d = self._detailPanel
        d:ClearAllPoints()
        d:SetPoint("LEFT", cc, "LEFT", 0, 0); d:SetPoint("RIGHT", cc, "RIGHT", 0, 0)
        d:SetPoint("BOTTOM", cc, "BOTTOM", 0, 4); d:SetHeight(self._detailH or DETAIL_H)

        local qp = self._queuePanel
        qp:ClearAllPoints()
        qp:SetPoint("TOP", toolbar.frame, "BOTTOM", 0, -4)
        qp:SetPoint("RIGHT", cc, "RIGHT", 0, 0)
        qp:SetPoint("BOTTOM", d, "TOP", 0, 4)
        qp:SetWidth(QUEUE_W)

        local h = self._headerFrame
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", toolbar.frame, "BOTTOMLEFT", 0, -4)
        h:SetPoint("RIGHT", qp, "LEFT", -GAP, 0)

        local s = self._scroll.frame
        s:ClearAllPoints()
        s:SetPoint("TOP", h, "BOTTOM", 0, -2)
        s:SetPoint("LEFT", cc, "LEFT", 0, 0)
        s:SetPoint("RIGHT", qp, "LEFT", -GAP, 0)
        s:SetPoint("BOTTOM", d, "TOP", 0, 4)
    end
    self._anchorAll = AnchorAll
    container.LayoutFinished = function() AnchorAll() end

    AnchorAll()
    self:FillList()
    self:RefreshDetail()
    self:RefreshQueue()
end

-- ===========================================================================
-- Column headers (raw, sortable)
-- ===========================================================================
function CraftingTab:BuildHeaders(parent)
    local hf = CreateFrame("Frame", nil, parent)
    hf:SetHeight(18)
    self._headerFrame = hf
    self._headerBtns  = {}

    local function mk(x, w, justify, col, base)
        local b = CreateFrame("Button", nil, hf)
        b:SetPoint("TOPLEFT", hf, "TOPLEFT", x, 0)
        b:SetSize(w, 18)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetAllPoints()
        fs:SetJustifyH(justify)
        b._fs, b._col, b._base = fs, col, base
        b:SetScript("OnClick", function() CraftingTab:OnHeaderClick(col) end)
        b:SetScript("OnEnter", function()
            addon.Tooltip.Owner(b)
            GameTooltip:SetText(base, 1, 1, 1)
            GameTooltip:AddLine(L["CraftSortHint"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self._headerBtns[#self._headerBtns + 1] = b
    end

    mk(NAME_X,  NAME_W,  "LEFT",  "name",  L["CraftColRecipe"])
    mk(SKILL_X, SKILL_W, "LEFT",  "skill", L["CraftColSkill"])
    mk(COUNT_X, COUNT_W, "RIGHT", "craft", L["CraftColCount"])
end

function CraftingTab:UpdateHeaderText()
    if not self._headerBtns then return end
    for _, b in ipairs(self._headerBtns) do
        local arrow = ""
        if self._sortCol == b._col then arrow = self._sortAsc and "  ^" or "  v" end
        b._fs:SetText(Brand(b._base .. arrow))
    end
end

function CraftingTab:OnHeaderClick(col)
    if self._sortCol == col then
        if self._sortAsc then self._sortAsc = false else self._sortCol = nil end
    else
        self._sortCol, self._sortAsc = col, true
    end
    self:UpdateHeaderText()
    self:FillList()
end

-- ===========================================================================
-- Recipe list (virtual-scroll raw-frame pool)
-- ===========================================================================
function CraftingTab:BuildPool(parent)
    self._pool = {}
    for _ = 1, POOL_SIZE do
        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:Hide()
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        local sel = f:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(1, 1, 1, 0.12)
        sel:Hide()
        f.selTex = sel

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", ICON_X, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", f, "LEFT", NAME_X, 0)
        nameLbl:SetWidth(NAME_W)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        local skillLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        skillLbl:SetPoint("LEFT", f, "LEFT", SKILL_X, 0)
        skillLbl:SetWidth(SKILL_W)
        skillLbl:SetJustifyH("LEFT")
        f.skillLbl = skillLbl

        local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countLbl:SetPoint("LEFT", f, "LEFT", COUNT_X, 0)
        countLbl:SetWidth(COUNT_W)
        countLbl:SetJustifyH("RIGHT")
        f.countLbl = countLbl

        f:SetScript("OnClick", function(rf)
            if rf._kind ~= "recipe" then return end
            if IsShiftKeyDown() and rf._link and HandleModifiedItemClick then
                HandleModifiedItemClick(rf._link)
                return
            end
            CraftingTab._selIndex = rf._index
            CraftingTab._selId    = rf._recipeId
            CraftingTab._qty      = 1
            CraftingTab:UpdateVirtualRows()
            CraftingTab:RefreshDetail()
        end)
        -- No hover tooltip on list rows on purpose — it popped over the list
        -- and made it hard to see/select. The full item tooltip lives on the
        -- detail panel's recipe name instead (see BuildDetail). Shift-click a
        -- row still links the item in chat.

        self._pool[#self._pool + 1] = f
    end
end

-- Full in-game item tooltip, anchored to the given frame. Prefers the crafted
-- item's hyperlink (the plain item tooltip); falls back to the trade-skill /
-- craft tooltip when no link is available.
function CraftingTab:ShowItemTooltip(anchorFrame, index, link)
    addon.Tooltip.Owner(anchorFrame)
    local Engine = addon.CraftingEngine
    local info = Engine and Engine:GetOpenInfo()
    if link and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(link)
    elseif info and info.isCraftWindow and GameTooltip.SetCraftItem then
        GameTooltip:SetCraftItem(index)
    elseif GameTooltip.SetTradeSkillItem then
        GameTooltip:SetTradeSkillItem(index)
    end
    GameTooltip:Show()
end

function CraftingTab:UpdateVirtualRows()
    local scroll, rows, pool = self._scroll, self._rows, self._pool
    if not scroll or not rows or not pool then return end

    local status   = scroll.status or scroll.localstatus
    local offset   = (status and status.offset) or 0
    local firstIdx = math.floor(offset / ROW_HEIGHT)
    local diffMap  = (addon.CraftingEngine and addon.CraftingEngine.DIFFICULTY_COLOR) or {}

    for i = 1, POOL_SIZE do
        local f = pool[i]
        local e = rows[firstIdx + i]
        if e then
            f._kind = e.kind
            if e.kind == "header" then
                f._index, f._recipeId, f._link = nil, nil, nil
                f.icon:Hide(); f.skillLbl:Hide(); f.countLbl:Hide(); f.selTex:Hide()
                f.nameLbl:SetPoint("LEFT", f, "LEFT", 8, 0)
                f.nameLbl:SetWidth(0)  -- let category headers run full width
                f.nameLbl:SetText(Brand(e.name))
            else
                f._index, f._recipeId, f._link = e.index, e.recipeId, e.link
                f.icon:SetTexture(e.icon or 134400); f.icon:Show()
                f.nameLbl:SetPoint("LEFT", f, "LEFT", NAME_X, 0)
                f.nameLbl:SetWidth(NAME_W)
                local selected = (self._selIndex == e.index)
                f.nameLbl:SetText(Color(selected and "ffffffff" or (diffMap[e.difficulty] or "ffffffff"), e.name))
                -- Skill column = the recipe's authoritative difficulty
                -- breakpoints (orange→yellow→green→grey), coloured by
                -- FormatSkillTiers. Pattern-recipe orange is corrected in the
                -- data pipeline (build_authoritative_data.py), not here.
                f.skillLbl:SetText(addon.FormatSkillTiers(e.tiers, e.requiredSkill))
                f.skillLbl:Show()
                f.countLbl:SetText((e.num and e.num > 0) and Color("ff40c040", tostring(e.num))
                                   or Color("ff808080", "0"))
                f.countLbl:Show()
                if selected then f.selTex:Show() else f.selTex:Hide() end
            end
            local y = -((firstIdx + i - 1) * ROW_HEIGHT)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT",  scroll.content, "TOPLEFT",  0, y)
            f:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, y)
            f:Show()
        else
            f._kind, f._index, f._recipeId, f._link = nil, nil, nil, nil
            f:Hide()
        end
    end
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

function CraftingTab:FillList()
    local scroll = self._scroll
    if not scroll then return end

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

    scroll.content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
    if scroll.FixScroll then scroll:FixScroll() end
    self:UpdateVirtualRows()
end

-- ===========================================================================
-- Detail panel (bottom) — raw frame, TSM-style: reagents stacked on the left
-- (icon · name · have/need at the right of the column), controls stacked on the
-- right (− [n] + MAX / Craft / Queue). Built once and reused; RefreshDetail
-- repopulates it for the current selection. Tooltips on every element route
-- through the global addon.Tooltip.Owner anchor helper.
-- ===========================================================================
local DREAG_POOL = 12      -- reagent rows (most recipes have ≤ 8)
local DCTRL_W    = 230     -- right-hand controls column width
local DREAG_H    = 13      -- reagent row height (tight, ~ font height)
local DREAG_TOP  = 42      -- y-offset of the first reagent row from the panel top
local DCTRL_BOT  = 114     -- controls block bottom offset (Craft Max button bottom: stepper -6, Craft -34, Queue -62, Craft Max -90..-114)
local DREAG_COST_W = 96    -- per-reagent cost column width (fits "NNNg NNs NNc" coin string)

local function rawTip(frame, getTitle, getDesc)
    frame:SetScript("OnEnter", function()
        addon.Tooltip.Owner(frame)
        GameTooltip:SetText(getTitle(), 1, 1, 1)
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
        GameTooltip:SetText(title, 1, 1, 1)
        if desc then GameTooltip:AddLine(desc, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return hit
end

function CraftingTab:SetQty(n)
    self._qty = math.max(1, math.floor(n or 1))
    if self._dpQty then self._dpQty:SetText(tostring(self._qty)) end
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
        if sel then CraftingTab:ShowItemTooltip(nameBtn, sel.index, sel.link) end
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
    -- addon.Price (Auctionator → TOGPM AH scan → vendor).
    local cost = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cost:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(DCTRL_W + 16), -8)
    cost:SetJustifyH("RIGHT")
    self._dpCost = cost
    headerTip(cost, true, 110, L["CraftCostLabel"], L["CraftCostDesc"])

    local reHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -26)
    reHdr:SetText(Brand(L["CraftReagents"]))
    self._dpReagHdr = reHdr
    headerTip(reHdr, false, nil, L["CraftReagents"], L["CraftReagentsDesc"])

    -- "Cost" column header — right edge aligns with the per-reagent cost values,
    -- which sit just left of the [Bank]/[AH] buttons. The buttons/count occupy a
    -- fixed 148px on the right of each row (bank 44 + ah 30 + count 60 + gaps);
    -- the count column is 60 wide to fit a bags/bank pair with 3-digit counts —
    -- so the cost column's right edge is the row's right inset (DCTRL_W+14) + 148.
    local costHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    costHdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(DCTRL_W + 162), -26)
    costHdr:SetWidth(DREAG_COST_W)
    costHdr:SetJustifyH("RIGHT")
    costHdr:SetText(Brand(L["CraftColCostHdr"]))
    self._dpCostHdr = costHdr
    headerTip(costHdr, true, DREAG_COST_W, L["CraftColCostHdr"], L["CraftColCostHdrDesc"])

    -- Reagent row pool (icon · name · have/need). Icons sized to the font.
    self._dpReagPool = {}
    for _ = 1, DREAG_POOL do
        local row = CreateFrame("Button", nil, panel)
        row:SetHeight(DREAG_H)
        row:Hide()

        local ri = row:CreateTexture(nil, "ARTWORK")
        ri:SetSize(12, 12)
        ri:SetPoint("LEFT", row, "LEFT", 0, 0)
        ri:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon = ri

        -- Count column shows the bags/bank inventory pair (the needed count is a
        -- prefix on the name instead). 60 wide to fit 3-digit values comfortably;
        -- kept in sync with the costHdr offset above.
        local cnt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cnt:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        cnt:SetWidth(60)
        cnt:SetJustifyH("RIGHT")
        cnt:SetWordWrap(false)
        row.cnt = cnt

        -- [AH] / [Bank] just left of the count (no header, compact). Shown only
        -- when the reagent has AH listings / guild-bank stock.
        local ahBtn = CreateFrame("Button", nil, row)
        ahBtn:SetSize(30, 13)
        ahBtn:SetPoint("RIGHT", cnt, "LEFT", -6, 0)
        ahBtn:SetNormalFontObject(GameFontNormalSmall)
        ahBtn:SetText("|cFF88CCFF[AH]|r")
        ahBtn:Hide()
        ahBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(ahBtn)
            GameTooltip:SetText(L["TooltipAHTitle"], 1, 1, 1)
            GameTooltip:AddLine(L["CraftAHReagentDesc"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.ahBtn = ahBtn

        local bankBtn = CreateFrame("Button", nil, row)
        bankBtn:SetSize(44, 13)
        bankBtn:SetPoint("RIGHT", ahBtn, "LEFT", -2, 0)
        bankBtn:SetNormalFontObject(GameFontNormalSmall)
        bankBtn:SetText("|cFF88FF88[Bank]|r")
        bankBtn:Hide()
        bankBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(bankBtn)
            GameTooltip:SetText(L["TooltipBankTitle"], 1, 1, 1)
            GameTooltip:AddLine(L["CraftBankReagentDesc"], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.bankBtn = bankBtn

        -- Per-reagent line cost (unit price × needed), sitting just left of the
        -- [Bank]/[AH] buttons and the have/need count. Filled by RefreshDetail
        -- from addon.Price; right-aligned under the "Cost" column header.
        local rcost = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rcost:SetPoint("RIGHT", bankBtn, "LEFT", -4, 0)
        rcost:SetWidth(DREAG_COST_W)
        rcost:SetJustifyH("RIGHT")
        rcost:SetWordWrap(false)   -- keep coin strings on one right-aligned line (no wrap into row 2)
        row.cost = rcost

        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nm:SetPoint("LEFT", ri, "RIGHT", 4, 0)
        nm:SetPoint("RIGHT", rcost, "LEFT", -4, 0)
        nm:SetJustifyH("LEFT")
        nm:SetWordWrap(false)
        row.nm = nm

        row:SetScript("OnEnter", function(rf)
            if not rf._link then return end
            addon.Tooltip.Owner(rf)
            GameTooltip:SetHyperlink(rf._link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self._dpReagPool[#self._dpReagPool + 1] = row
    end

    -- Controls (right). The stepper row sits at the TOP (no dead space above),
    -- then Craft, then Queue — all the same width (CW) so the column reads as a
    -- tidy full stack. The qty box stretches to fill the stepper row between the
    -- − and + buttons so the row looks full.
    local CR, CW = 12, DCTRL_W - 12

    local craftBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    craftBtn:SetSize(CW, 24)
    craftBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -CR, -34)
    craftBtn:SetText(L["CraftButton"])
    craftBtn:SetScript("OnClick", function()
        local sel = CraftingTab._dpSel
        if sel and addon.CraftingEngine then
            addon.CraftingEngine:Craft(sel.recipeId, sel.index, CraftingTab._qty or 1)
        end
    end)
    rawTip(craftBtn, function() return L["CraftButton"] end, function() return L["CraftButtonDesc"] end)
    self._dpCraft = craftBtn

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

    -- Stepper row, aligned to the Craft button's edges (full width): − [qty] + MAX
    local minusBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    minusBtn:SetSize(24, 22)
    minusBtn:SetPoint("TOPLEFT", craftBtn, "TOPLEFT", 0, 28)
    minusBtn:SetText("-")
    minusBtn:SetScript("OnClick", function() CraftingTab:SetQty((CraftingTab._qty or 1) - 1) end)
    rawTip(minusBtn, function() return L["CraftDecrease"] end)
    self._dpMinus = minusBtn

    local maxBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    maxBtn:SetSize(46, 22)
    maxBtn:SetPoint("TOPRIGHT", craftBtn, "TOPRIGHT", 0, 28)
    maxBtn:SetText(L["CraftMax"])
    maxBtn:SetScript("OnClick", function()
        local sel = CraftingTab._dpSel
        CraftingTab:SetQty(sel and sel.num or 1)
    end)
    rawTip(maxBtn, function() return L["CraftMax"] end, function() return L["CraftMaxDesc"] end)
    self._dpMax = maxBtn

    local plusBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    plusBtn:SetSize(24, 22)
    plusBtn:SetPoint("RIGHT", maxBtn, "LEFT", -4, 0)
    plusBtn:SetText("+")
    plusBtn:SetScript("OnClick", function() CraftingTab:SetQty((CraftingTab._qty or 1) + 1) end)
    rawTip(plusBtn, function() return L["CraftIncrease"] end)
    self._dpPlus = plusBtn

    local qty = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    qty:SetHeight(20)
    qty:SetPoint("LEFT",  minusBtn, "RIGHT", 7, 0)
    qty:SetPoint("RIGHT", plusBtn,  "LEFT",  -7, 0)
    qty:SetPoint("TOP",   minusBtn, "TOP",   0, -1)
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(4)
    qty:SetJustifyH("CENTER")
    qty:SetScript("OnEnterPressed", function(s) CraftingTab:SetQty(tonumber(s:GetText()) or 1); s:ClearFocus() end)
    qty:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    self._dpQty = qty
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

    local widgets = { self._dpIcon, self._dpNameBtn, self._dpReagHdr, self._dpCostHdr,
                      self._dpMinus, self._dpQty, self._dpPlus, self._dpMax,
                      self._dpCraft, self._dpQueue, self._dpCraftMax }
    if not sel then
        self._dpHint:Show()
        self._dpMiss:Hide()
        if self._dpCost then self._dpCost:Hide() end
        for _, w in ipairs(widgets) do w:Hide() end
        for _, row in ipairs(self._dpReagPool) do row:Hide() end
        self._detailH = 56          -- compact: just the hint
        if self._anchorAll then self._anchorAll() end
        return
    end
    self._dpHint:Hide()
    for _, w in ipairs(widgets) do w:Show() end

    self._dpIcon:SetTexture(sel.icon or 134400)
    self._dpNameBtn._fs:SetText(Color(sel.color or (addon.BrandColor or "ffFF8000"), sel.name))
    self._dpQty:SetText(tostring(self._qty or 1))
    local canCraft = (sel.num or 0) > 0
    if self._dpCraft.SetEnabled    then self._dpCraft:SetEnabled(canCraft)    end
    if self._dpCraftMax.SetEnabled then self._dpCraftMax:SetEnabled(canCraft) end

    local reagents = Engine:GetReagents(self._selIndex)
    local missing, shown = false, 0
    for i = 1, #self._dpReagPool do
        local row = self._dpReagPool[i]
        local r   = reagents[i]
        if r then
            shown = i
            -- The recipe's required count is shown as a "<n>x " PREFIX on the
            -- name (reads "12x Greater Eternal Essence") — it used to be a third
            -- number in the count column, which looked like an inventory figure.
            -- The count column is now just your inventory: bags / bank — bags is
            -- live (GetItemCount), bank is the cached snapshot from your last bank
            -- visit (ReagentWatch persists it on BANKFRAME_CLOSED). "Enough" (and
            -- the Missing-Materials flag) counts bags + bank together, so a
            -- reagent stashed in the bank doesn't read as missing.
            local need = r.need or 0
            local bags = (r.itemId and GetItemCount and GetItemCount(r.itemId)) or r.have or 0
            local bankq = (r.itemId and addon.ReagentWatch and addon.ReagentWatch:GetBankCount(r.itemId)) or 0
            local enough = (bags + bankq) >= need
            if not enough then missing = true end
            row._link = r.link
            row.icon:SetTexture(r.texture or 134400)
            row.nm:SetText(Color("ffa0a0a0", need .. "x ") .. (r.name or "?"))
            row.cnt:SetText(Color(enough and "ff40c040" or "ffff4040",
                ("%d/%d"):format(bags, bankq)))

            -- Per-reagent line cost: unit price × needed. "—" when unpriced.
            if addon.Price and r.itemId then
                local p = addon.Price.Get(r.itemId)
                if p then
                    row.cost:SetText(addon.Price.Money(p * (r.need or 1)))
                else
                    row.cost:SetText(Color("ff888888", "—"))
                end
            else
                row.cost:SetText("")
            end

            -- [Bank] when a guild-bank character has stock; [AH] when a scan
            -- found live listings (mirrors Browser/Missing). Both reuse the
            -- shared addon.Bank / addon.AH integrations.
            local id = r.itemId
            if id and addon.Bank and addon.Bank.GetStock and addon.Bank.GetStock(id) > 0 then
                row.bankBtn:SetScript("OnClick", function()
                    if addon.Bank.ShowRequestDialog then addon.Bank.ShowRequestDialog(id, r.name, r.link) end
                end)
                row.bankBtn:Show()
            else
                row.bankBtn:Hide()
            end
            local listings = id and addon.AH and addon.AH.GetListingsFor and addon.AH.GetListingsFor(id)
            if listings and (listings.count or 0) > 0 then
                row.ahBtn:SetScript("OnClick", function()
                    if addon.AH.SearchFor then addon.AH.SearchFor(r.name) end
                end)
                row.ahBtn:Show()
            else
                row.ahBtn:Hide()
            end

            local y = -(DREAG_TOP + (i - 1) * DREAG_H)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  panel, "TOPLEFT",  12,              y)
            row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(DCTRL_W + 14), y)
            row:Show()
        else
            row._link = nil
            row:Hide()
        end
    end
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

            -- AH sale price of the CRAFTED item (lowest buyout) + profit/loss vs the
            -- crafting cost. Only when there's an actual AH price for the product
            -- (a vendor price isn't a sale price), and — for profit — the craft cost
            -- is fully known. Profit = sell price − craft cost: green = you'd make
            -- coin, red = you'd lose it. (Assumes one craft yields one item and
            -- ignores the AH cut — a first cut; refine later.)
            local craftedId = sel.link and tonumber(sel.link:match("item:(%d+)"))
            local ah
            if craftedId and Pr.Get then
                local p, src = Pr.Get(craftedId)
                if p and (src == "auctionator" or src == "togpm-ah") then ah = p end
            end
            if ah then
                segs[#segs + 1] = Color("ffaaaaaa", L["CraftAHPriceLabel"] .. ": ") .. Pr.Money(ah)
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
    local reagentsBottom = DREAG_TOP + shown * DREAG_H
    self._detailH = math.max(math.max(reagentsBottom, DCTRL_BOT) + 10, 96)
    if self._anchorAll then self._anchorAll() end
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

    local line = panel:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(1, 0.5, 0, 0.9)
    line:SetHeight(2)
    line:Hide()
    self._insertLine = line

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

    self._queueRowPool = {}
    for _ = 1, QUEUE_POOL do
        local f = CreateFrame("Button", nil, panel)
        f:SetHeight(QROW_H)
        f:Hide()
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
        f:RegisterForDrag("LeftButton")

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", 2, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        local removeBtn = CreateFrame("Button", nil, f)
        removeBtn:SetSize(16, 16)
        removeBtn:SetPoint("RIGHT", f, "RIGHT", -2, 0)
        removeBtn:SetNormalFontObject(GameFontNormalSmall)
        removeBtn:SetText("|cffff5555x|r")
        removeBtn:SetScript("OnClick", function()
            if f._qindex and addon.CraftQueue then addon.CraftQueue:Remove(f._qindex) end
        end)
        f.removeBtn = removeBtn

        local qtyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qtyLbl:SetPoint("RIGHT", removeBtn, "LEFT", -2, 0)
        qtyLbl:SetWidth(34)
        qtyLbl:SetJustifyH("RIGHT")
        qtyLbl:SetTextColor(0.9, 0.9, 0.9)
        f.qtyLbl = qtyLbl

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT",  icon,   "RIGHT", 3, 0)
        nameLbl:SetPoint("RIGHT", qtyLbl, "LEFT",  -3, 0)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        f:SetScript("OnDragStart", function(rf) CraftingTab:_StartDrag(rf) end)
        f:SetScript("OnDragStop",  function(rf) CraftingTab:_StopDrag(rf) end)

        self._queueRowPool[#self._queueRowPool + 1] = f
    end
end

function CraftingTab:QueueEntryDisplay(e)
    local Engine = addon.CraftingEngine
    local live = Engine and Engine:GetRecipeEntry(e.recipeId)
    if live then return live.name, live.icon end
    local meta = addon.recipeDB and addon.recipeDB[e.profId] and addon.recipeDB[e.profId][e.recipeId]
    local name = (meta and meta.name)
              or (GetSpellInfo and GetSpellInfo(e.recipeId))
              or ("#" .. tostring(e.recipeId))
    local icon = (meta and meta.icon)
              or (meta and meta.craftedItemId and GetItemIcon and GetItemIcon(meta.craftedItemId))
              or (GetSpellTexture and GetSpellTexture(e.recipeId))
    return name, icon
end

function CraftingTab:RefreshQueue()
    local panel = self._queuePanel
    if not panel then return end

    local q = addon.CraftQueue and addon.CraftQueue:Get() or {}
    self._queueTitle:SetText(Brand(L["CraftQueueTitle"]:format(#q)))

    local Engine = addon.CraftingEngine
    local info   = Engine and Engine:GetOpenInfo()

    local panelH = panel:GetHeight()
    if not panelH or panelH <= 0 then panelH = 360 end
    local maxVisible = math.max(0, math.floor((panelH - Q_TITLE_H - Q_FOOTER_H) / QROW_H))

    for i = 1, #self._queueRowPool do
        local row = self._queueRowPool[i]
        local e   = q[i]
        if e and i <= maxVisible then
            row._qindex = i
            local name, icon = self:QueueEntryDisplay(e)
            row.icon:SetTexture(icon or 134400)
            row.qtyLbl:SetText("x" .. e.qty)

            local craftable = false
            if info and e.profId == info.profId then
                local live = Engine:GetRecipeEntry(e.recipeId)
                craftable = live and (live.num or 0) > 0 or false
            end
            row.nameLbl:SetText(Color(craftable and "ffffffff" or "ff888888", name))

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", Q_PAD, -(Q_TITLE_H + (i - 1) * QROW_H))
            row:SetPoint("RIGHT",   panel, "RIGHT",   -Q_PAD, 0)
            row:SetHeight(QROW_H)
            row:Show()
        else
            row._qindex = nil
            row:Hide()
        end
    end

    local canCraftNext = addon.CraftQueue and addon.CraftQueue:CanCraftNext()
    if self._craftNextBtn then
        if canCraftNext then self._craftNextBtn:Enable() else self._craftNextBtn:Disable() end
    end
    if self._craftAllBtn then
        if canCraftNext then self._craftAllBtn:Enable() else self._craftAllBtn:Disable() end
    end
end

-- ---- Drag-to-reorder ------------------------------------------------------
local function rowsTopScreenY(panel)
    local top = panel:GetTop()
    if not top then return nil end
    return top - Q_TITLE_H
end

function CraftingTab:_StartDrag(rf)
    if not rf._qindex then return end
    self._dragFrom, self._dragTarget = rf._qindex, rf._qindex
    rf:SetFrameStrata("TOOLTIP")
    rf:SetAlpha(0.85)
    self._insertLine:Show()
    rf:SetScript("OnUpdate", function(s) CraftingTab:_DragUpdate(s) end)
end

function CraftingTab:_DragUpdate(rf)
    local panel = self._queuePanel
    if not panel then return end
    local scale = UIParent:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    cy = cy / scale

    rf:ClearAllPoints()
    rf:SetPoint("LEFT",  panel, "LEFT",  Q_PAD, 0)
    rf:SetPoint("RIGHT", panel, "RIGHT", -Q_PAD, 0)
    rf:SetPoint("TOP",   UIParent, "BOTTOM", 0, cy + QROW_H / 2)

    local count = addon.CraftQueue and addon.CraftQueue:Count() or 0
    local top = rowsTopScreenY(panel)
    if top and count > 0 then
        local slot = math.floor((top - cy) / QROW_H) + 1
        slot = math.max(1, math.min(count, slot))
        self._dragTarget = slot
        self._insertLine:ClearAllPoints()
        self._insertLine:SetPoint("TOPLEFT", panel, "TOPLEFT", Q_PAD, -(Q_TITLE_H + (slot - 1) * QROW_H))
        self._insertLine:SetPoint("RIGHT",   panel, "RIGHT",   -Q_PAD, 0)
    end
end

function CraftingTab:_StopDrag(rf)
    rf:SetScript("OnUpdate", nil)
    rf:SetAlpha(1)
    rf:SetFrameStrata(self._queuePanel:GetFrameStrata())
    self._insertLine:Hide()
    if self._dragFrom and self._dragTarget and addon.CraftQueue then
        addon.CraftQueue:Move(self._dragFrom, self._dragTarget)
    end
    self._dragFrom, self._dragTarget = nil, nil
    self:RefreshQueue()
end

-- ===========================================================================
-- Cleanup + refresh hooks
-- ===========================================================================
function CraftingTab:DetachPool()
    addon.GUI.DetachPool(self._pool)
    addon.GUI.DetachPool(self._queuePanel)
    addon.GUI.DetachPool(self._headerFrame)
    addon.GUI.DetachPool(self._detailPanel)
    self._scroll = nil
    self._rows   = nil
end

function CraftingTab:OnQueueChanged()
    local mw = addon.MainWindow
    if mw and mw.frame and mw.activeTab == "crafting" and self._queuePanel then
        self:RefreshQueue()
    end
end

function CraftingTab:OnLiveRefresh()
    local mw = addon.MainWindow
    if not (mw and mw.frame and mw.activeTab == "crafting" and self._scroll) then return end
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

    -- Window resized: the panels re-anchor automatically (they're pinned to the
    -- container edges), but the virtual-scroll row pool sizes itself to the
    -- visible height, so recompute it once the resize settles. AnchorAll is a
    -- cheap, idempotent re-pin done first as a belt-and-suspenders alongside the
    -- LayoutFinished cascade. MainWindow fires this debounced (~150ms).
    addon.RegisterCallback(CraftingTab, "WINDOW_RESIZED", function()
        local mw = addon.MainWindow
        if mw and mw.frame and mw.activeTab == "crafting" then
            if CraftingTab._anchorAll then CraftingTab._anchorAll() end
            CraftingTab:UpdateVirtualRows()
        end
    end)
end
