-- TOG Profession Master — Reagent Tracker
-- Standalone floating window with no backdrop or border.
-- Shows every reagent consolidated from the shopping list with live counts:
--   have = player bags (live) + TOGBankClassic guild stock
--   need = sum of (reagent × qty) across all shopping list entries
--
-- Open: RMB on minimap button, or /togpm reagents

local _, addon = ...
local Ace = addon.lib

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local RT = {}
addon.ReagentTracker = RT

-- Layout constants
local WIN_W   = 280
local ROW_H   = 16
local ICON_SZ = 13
local HDR_H   = 20
local COUNT_W = 48
local BANK_W  = 48

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

local function GetPlayerBagCount(itemId)
    local total = 0
    for bag = 0, addon:GetNumBagSlots() do
        for slot = 1, addon:GetContainerNumSlots(bag) do
            local info = addon:GetContainerItemInfo(bag, slot)
            if info then
                local id = info.itemID or info.itemId
                if id == itemId then
                    total = total + (info.stackCount or 1)
                end
            end
        end
    end
    return total
end

-- Consolidate all reagents from the shopping list into a sorted array.
local function BuildReagentList()
    local sl   = Ace.db.char.shoppingList
    local byId = {}
    for _, entry in pairs(sl) do
        local qty = entry.quantity or 1
        for _, r in ipairs(entry.reagents or {}) do
            local rId = r.itemLink and tonumber(r.itemLink:match("item:(%d+)"))
                     or (r.itemId and r.itemId > 0 and r.itemId or nil)
            if rId then
                if not byId[rId] then
                    byId[rId] = { id = rId, name = r.name or "", itemLink = r.itemLink, need = 0 }
                end
                byId[rId].need = byId[rId].need + (r.count or 1) * qty
            end
        end
    end
    local list = {}
    for _, v in pairs(byId) do table.insert(list, v) end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ---------------------------------------------------------------------------
-- Row pool
-- ---------------------------------------------------------------------------

function RT:GetRow(idx)
    if self._rows[idx] then return self._rows[idx] end

    local f = CreateFrame("Button", nil, self.frame)
    f:SetHeight(ROW_H)
    f:EnableMouse(true)
    f:RegisterForClicks("AnyUp")
    f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", f, "LEFT", 4, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetWordWrap(false)
    f.nameLbl = nameLbl

    local bankBtn = CreateFrame("Button", nil, f)
    bankBtn:SetSize(BANK_W, 12)
    bankBtn:SetPoint("RIGHT", f, "RIGHT", -(COUNT_W + 6), 0)
    bankBtn:SetNormalFontObject(GameFontNormalSmall)
    bankBtn:SetText("|cFF88FF88[Bank]|r")
    bankBtn:Hide()
    bankBtn:SetScript("OnEnter", function()
        addon.Tooltip.Owner(bankBtn)
        GameTooltip:SetText("Request from Bank", 1, 1, 1)
        GameTooltip:AddLine("Send a request to a TOGBankClassic guild banker.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.bankBtn = bankBtn

    local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLbl:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    countLbl:SetWidth(COUNT_W)
    countLbl:SetJustifyH("RIGHT")
    f.countLbl = countLbl

    self._rows[idx] = f
    return f
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

function RT:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    local list = BuildReagentList()

    for i = #list + 1, #self._rows do
        self._rows[i]:Hide()
    end

    if #list == 0 then
        self._emptyLbl:Show()
        self.frame:SetHeight(HDR_H + ROW_H + 8)
        return
    end
    self._emptyLbl:Hide()

    local nameWFull = WIN_W - ICON_SZ - 12 - COUNT_W - 8
    local nameWBank = nameWFull - BANK_W - 4

    for i, item in ipairs(list) do
        local row = self:GetRow(i)

        local bagCount  = GetPlayerBagCount(item.id)
        local bankCount = addon.Bank and addon.Bank.GetStock(item.id) or 0
        local have      = bagCount + bankCount
        local need      = item.need

        -- Icon (may be nil if not cached yet — silently blank)
        row.icon:SetTexture(select(10, GetItemInfo(item.id)))

        -- Name coloured by item rarity
        local colorHex = item.itemLink and item.itemLink:match("|c(ff%x%x%x%x%x%x)|H") or "ffffffff"
        row.nameLbl:SetText("|c" .. colorHex .. item.name .. "|r")

        -- Bank button
        if bankCount > 0 then
            local iId, iName, iLink = item.id, item.name, item.itemLink
            row.bankBtn:SetScript("OnClick", function()
                addon.Bank.ShowRequestDialog(iId, iName, iLink)
            end)
            row.bankBtn:Show()
            row.nameLbl:SetWidth(nameWBank)
        else
            row.bankBtn:Hide()
            row.nameLbl:SetWidth(nameWFull)
        end

        -- Have/need count: green = satisfied, yellow = partial, red = none
        local col = (have >= need) and "|cff00ff00"
                 or (have > 0     and "|cffffff00"
                                  or  "|cffff4444")
        row.countLbl:SetText(col .. have .. "|r/" .. need)

        -- Tooltip + shift-click to link
        local iLink = item.itemLink
        row:SetScript("OnEnter", function()
            if iLink then
                addon.Tooltip.Owner(row)
                GameTooltip:SetHyperlink(iLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(_, btn)
            if btn == "LeftButton" and IsShiftKeyDown() and iLink then
                ChatEdit_InsertLink(iLink)
            end
        end)

        local y = -(HDR_H + (i - 1) * ROW_H)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",  0, y)
        row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, y)
        row:Show()
    end

    self.frame:SetHeight(HDR_H + #list * ROW_H + 6)
end

-- ---------------------------------------------------------------------------
-- Build (once)
-- ---------------------------------------------------------------------------

function RT:Build()
    local f = CreateFrame("Frame", "TOGPMReagentTracker", UIParent)
    f:SetWidth(WIN_W)
    f:SetHeight(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetFrameStrata("HIGH")
    f:SetScript("OnDragStart", function(fr) fr:StartMoving() end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        local pt, _, rpt, x, y = fr:GetPoint()
        Ace.db.char.frames.reagentTracker = { point = pt, relPoint = rpt, x = x, y = y }
    end)

    tinsert(UISpecialFrames, "TOGPMReagentTracker")

    local saved = Ace.db.char.frames and Ace.db.char.frames.reagentTracker
    if saved then
        f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    end

    self.frame = f
    self._rows = {}

    -- Title (also the drag handle)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
    title:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Reagent Tracker|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeLbl:SetAllPoints()
    closeLbl:SetJustifyH("CENTER")
    closeLbl:SetText("|cFFFF4444x|r")
    closeBtn:SetScript("OnClick", function() self:Close() end)

    -- Empty state
    local emptyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  4, -HDR_H)
    emptyLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -HDR_H)
    emptyLbl:SetText("|cffaaaaaa(shopping list is empty)|r")
    emptyLbl:SetJustifyH("LEFT")
    emptyLbl:Hide()
    self._emptyLbl = emptyLbl
end

-- ---------------------------------------------------------------------------
-- Open / Close / Toggle
-- ---------------------------------------------------------------------------

function RT:Open()
    if not self.frame then self:Build() end
    self.frame:Show()
    self:Refresh()
end

function RT:Close()
    if self.frame then self.frame:Hide() end
end

function RT:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

-- ---------------------------------------------------------------------------
-- QueueRefresh — debounced; called by BrowserTab when the shopping list changes
-- ---------------------------------------------------------------------------

function RT:QueueRefresh()
    if self._refreshTimer then self._refreshTimer:Cancel() end
    self._refreshTimer = C_Timer.NewTimer(0.1, function()
        self._refreshTimer = nil
        self:Refresh()
    end)
end

-- ---------------------------------------------------------------------------
-- BAG_UPDATE → refresh have counts
-- ---------------------------------------------------------------------------

local _bagWatcher = CreateFrame("Frame")
_bagWatcher:RegisterEvent("BAG_UPDATE")
_bagWatcher:SetScript("OnEvent", function()
    RT:QueueRefresh()
end)

-- ---------------------------------------------------------------------------
-- Override OpenReagents (minimap RMB + /togpm reagents)
-- ---------------------------------------------------------------------------

function addon:OpenReagents()
    RT:Toggle()
end
