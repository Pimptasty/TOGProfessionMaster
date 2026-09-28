-- TOG Profession Master — Reagent Tracker
-- Standalone floating window with no backdrop or border.
-- Shows every reagent consolidated from the shopping list with live counts:
--   have = player bags (live) + TOGBankClassic guild stock
--   need = sum of (reagent × qty) across all shopping list entries
--
-- Open: RMB on minimap button, or /togpm reagents

local _, addon = ...
local Ace = addon.lib
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local RT = {}
addon.ReagentTracker = RT

-- Layout constants
local WIN_W   = 320
local ROW_H   = 16
local ICON_SZ = 13
local HDR_H   = 20
local COUNT_W = 90       -- room for "30/30 +99999" worst case
local BANK_W  = 58   -- [Bank] plus TOGBank's staleness dot in front of it

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

--- "What I personally have" total: bags + cached personal bank + cached mail.
-- TOGBankClassic guild-bank stock is intentionally excluded — that's surfaced
-- separately as a "+N" annotation in the row.  Bank/mail counts are cached
-- by ReagentWatch on BANKFRAME_CLOSED / MAIL_CLOSED so they persist between
-- visits to the bank or mailbox.
-- Methods rather than file-locals so they can be tested directly: these two are
-- the numbers the tracker exists to show ("need" and "have"), and everything
-- else in this file is rendering. Covered by Tests/reagenttracker_spec.lua.
function RT:GetPlayerBagCount(itemId)
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
    local bank = Ace.db.char.bankCounts
    if bank and bank[itemId] then total = total + bank[itemId] end
    local mail = Ace.db.char.mailCounts
    if mail and mail[itemId] then total = total + mail[itemId] end
    return total
end

-- Consolidate all reagents from the shopping list into a sorted array.
function RT:BuildReagentList()
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

--- The count cell: have / need, plus the guild bank's stock. The bag count's
--- colour reflects what the player can craft:
---   green  = bags alone satisfy the recipe
---   yellow = bags don't, but bags + bank do (request from the bank)
---   orange = bags + bank still short, but there is something
---   red    = nothing in bags or bank
--- The bank's stock is always shown (light blue) when there is any, so the
--- player can see what the guild bank can add without mistaking it for their own.
function RT:CountText(entry)
    local have, need, bank = entry.have or 0, entry.need or 0, entry.bank or 0
    local total = have + bank
    local col
    if have >= need then       col = "|cff00ff00"
    elseif total >= need then  col = "|cffffff00"
    elseif total > 0 then      col = "|cffff8800"
    else                       col = "|cffff4444"
    end
    local bankText = bank > 0 and (" |cff88ccff+" .. bank .. "|r") or ""
    return col .. have .. "|r/" .. need .. bankText
end

-- ---------------------------------------------------------------------------
-- The list: LibAceGUIWidgets RowList (MINOR 36)
-- ---------------------------------------------------------------------------
-- One row per reagent: the item's cropped icon, its name in the item's rarity
-- colour, a [Bank] button shown only when the guild bank holds some, and the
-- count. The list sizes the window to its rows (fitContent) -- the host is
-- anchored by its top alone, and the window follows the height the list reports.
-- Hovering a row shows the item; a left click links it (addon.ItemLink.Click,
-- which honours the player's modified-click bindings).
function RT:BuildList()
    local host = CreateFrame("Frame", nil, self.frame)
    host:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",  0, -HDR_H)
    host:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -HDR_H)
    host:SetHeight(ROW_H)
    self._host = host

    self._list = addon.W.RowList:New(host, {
        rowHeight      = ROW_H,
        hoverHighlight = true,
        fitContent     = true,
        onHeightChanged = function(_, h)
            if self.frame then self.frame:SetHeight(HDR_H + h + 6) end
        end,
        columns = {
            { key = "icon", width = ICON_SZ + 4, iconSize = ICON_SZ, iconTexCoord = true,
              sortable = false,
              icon = function(e) return select(10, addon.Item.GetInfo(e.id)) end },
            { key = "name", sortable = false,
              format = function(value, e)
                  local hex = e.itemLink and e.itemLink:match("|c(ff%x%x%x%x%x%x)|H") or "ffffffff"
                  return "|c" .. hex .. (value or "") .. "|r"
              end },
            { key = "bankBtn", width = BANK_W, button = true, sortable = false,
              show = function(e) return (e.bank or 0) > 0 end,
              text = function(e) return addon.Bank.ButtonText(e.id) end,
              tip  = function(e)
                  local body = L["TooltipBankDescGeneric"]
                  local status = addon.Bank.StatusText(e.id)
                  if status then body = body .. "\n\n" .. status end
                  return L["TooltipBankTitle"], body
              end,
              onClick = function(e) addon.Bank.ShowRequestDialog(e.id, e.name, e.itemLink) end },
            { key = "count", width = COUNT_W, align = "RIGHT", sortable = false,
              format = function(_, e) return RT:CountText(e) end },
        },
        onRowEnter = function(e, _, _, rowFrame)
            if not e.itemLink then return end
            addon.Tooltip.Owner(rowFrame)
            addon.ItemLink.SetItem(GameTooltip, e.itemLink)
            GameTooltip:Show()
        end,
        onRowLeave = function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end,
        onRowClick = function(e, _, _, button)
            if button == "LeftButton" then addon.ItemLink.Click(e.itemLink) end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

function RT:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    local list = self:BuildReagentList()
    for _, item in ipairs(list) do
        item.have = self:GetPlayerBagCount(item.id)
        item.bank = addon.Bank and addon.Bank.GetStock(item.id) or 0
        item.count = item.have
    end

    if #list == 0 then
        self._emptyLbl:Show()
        self._host:Hide()
        self.frame:SetHeight(HDR_H + ROW_H + 8)
        return
    end
    self._emptyLbl:Hide()
    self._host:Show()
    self._list:SetData(list, true)
    -- onHeightChanged fires only when the list's height CHANGES, so coming back
    -- from the empty state with the same row count would leave the window at
    -- the empty state's height. Size it from the host every time.
    self.frame:SetHeight(HDR_H + self._host:GetHeight() + 6)
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

    self:BuildList()
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
_bagWatcher:RegisterEvent("BANKFRAME_CLOSED")  -- ReagentWatch refreshes the bank cache here
_bagWatcher:RegisterEvent("MAIL_CLOSED")       -- ReagentWatch refreshes the mail cache here
_bagWatcher:SetScript("OnEvent", function()
    RT:QueueRefresh()
end)

-- ---------------------------------------------------------------------------
-- Override OpenReagents (minimap RMB + /togpm reagents)
-- ---------------------------------------------------------------------------

function addon:OpenReagents()
    RT:Toggle()
end
