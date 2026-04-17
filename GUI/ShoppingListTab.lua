-- TOG Profession Master — Shopping List / Reagents Tab
-- Draws the "Reagents" tab inside the main window.
--
-- Two sub-panels:
--   Top: Shopping List — spells the player wants crafted, with quantity.
--   Bottom: Missing Reagents — aggregated shortfall across the shopping list.
--
-- Each row has:
--   Shopping list row: [x] SpellName  qty[-][+]  [Bank]
--   Reagent row:       ItemName  have / need  [Bank]  (shift-click → chat link)

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local ShoppingListTab = {}
addon.ShoppingListTab = ShoppingListTab

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Scan bags and return { [itemId] = count } for all items in the player's bags.
local function ScanBags()
    local counts = {}
    local numBags = addon:GetNumBagSlots()
    for bag = 0, numBags do
        local slots = addon:GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = addon:GetContainerItemInfo(bag, slot)
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

--- Aggregate reagent requirements across the shopping list.
-- Returns array of { itemId, itemName, needed, have, shortfall }
local function BuildReagentList()
    local bl   = Ace.db.char.shoppingList
    local data = addon:GetCooldownData()
    local need = {}   -- [itemId] = totalNeeded

    for spellId, entry in pairs(bl) do
        local qty     = (entry and entry.quantity) or 1
        local reagent = data.reagents[spellId] or data.transReagents[spellId]
        if reagent then
            local id = reagent.id
            need[id] = (need[id] or 0) + (reagent.qty * qty)
        end
    end

    local bags = ScanBags()
    local list = {}
    for itemId, totalNeeded in pairs(need) do
        local have      = bags[itemId] or 0
        local shortfall = math.max(0, totalNeeded - have)
        local itemName  = GetItemInfo(itemId) or "|cffaaaaaa(loading…)|r"
        table.insert(list, {
            itemId    = itemId,
            itemName  = itemName,
            needed    = totalNeeded,
            have      = have,
            shortfall = shortfall,
        })
    end
    table.sort(list, function(a, b) return a.itemName < b.itemName end)
    return list
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function ShoppingListTab:Draw(container)
    container:SetLayout("List")
    self._container = container

    -- ---- Shopping List section ---------------------------------------------
    local blSection = AceGUI:Create("InlineGroup")
    blSection:SetTitle(L["SectionShoppingList"])
    blSection:SetLayout("List")
    blSection:SetFullWidth(true)
    container:AddChild(blSection)
    self._blSection = blSection

    self:FillShoppingList(blSection)

    -- ---- Missing Reagents section ------------------------------------------
    local mrSection = AceGUI:Create("InlineGroup")
    mrSection:SetTitle(L["SectionMissingReagents"])
    mrSection:SetLayout("List")
    mrSection:SetFullWidth(true)
    container:AddChild(mrSection)
    self._mrSection = mrSection

    self:FillMissingReagents(mrSection)

    -- ---- Reagent Watch section ---------------------------------------------
    local rwSection = AceGUI:Create("InlineGroup")
    rwSection:SetTitle(L["SectionReagentWatch"])
    rwSection:SetLayout("List")
    rwSection:SetFullWidth(true)
    container:AddChild(rwSection)
    self._rwSection = rwSection

    self:FillReagentWatch(rwSection)

    -- Subscribe to bag-change notifications so the watch list stays current
    if not self._watchCallbackRegistered then
        addon:RegisterCallback("REAGENT_WATCH_UPDATED", function()
            if self._rwSection then
                self._rwSection:ReleaseChildren()
                self:FillReagentWatch(self._rwSection)
            end
        end, self)
        self._watchCallbackRegistered = true
    end
end

-- ---------------------------------------------------------------------------
-- Shopping List panel
-- ---------------------------------------------------------------------------

function ShoppingListTab:FillShoppingList(container)
    local bl = Ace.db.char.shoppingList

    local empty = true
    for _ in pairs(bl) do empty = false; break end

    if empty then
        local lbl = AceGUI:Create("Label")
        lbl:SetText("|cffaaaaaa(empty — use the + button in the Professions tab to add items to your shopping list)|r")
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
        return
    end

    for spellId, entry in pairs(bl) do
        local spellName = GetSpellInfo(spellId) or tostring(spellId)
        local qty       = (entry and entry.quantity) or 1

        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        container:AddChild(row)

        -- [x] remove
        local removeBtn = AceGUI:Create("Button")
        removeBtn:SetText("x")
        removeBtn:SetWidth(28)
        local sid = spellId
        removeBtn:SetCallback("OnClick", function()
            bl[sid] = nil
            if addon.ReagentWatch then
                addon.ReagentWatch:ClearAlert(sid)
            end
            self:Redraw()
        end)
        row:AddChild(removeBtn)

        -- Spell name
        local lbl = AceGUI:Create("InteractiveLabel")
        lbl:SetText(spellName)
        lbl:SetWidth(200)
        lbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetSpellByID(sid)
            GameTooltip:Show()
        end)
        lbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        row:AddChild(lbl)

        -- qty [-] [N] [+]
        local minusBtn = AceGUI:Create("Button")
        minusBtn:SetText("-")
        minusBtn:SetWidth(28)
        minusBtn:SetCallback("OnClick", function()
            if bl[sid] then
                bl[sid].quantity = math.max(1, (bl[sid].quantity or 1) - 1)
                self:Redraw()
            end
        end)
        row:AddChild(minusBtn)

        local qtyLbl = AceGUI:Create("Label")
        qtyLbl:SetText(tostring(qty))
        qtyLbl:SetWidth(24)
        row:AddChild(qtyLbl)

        local plusBtn = AceGUI:Create("Button")
        plusBtn:SetText("+")
        plusBtn:SetWidth(28)
        plusBtn:SetCallback("OnClick", function()
            if bl[sid] then
                bl[sid].quantity = (bl[sid].quantity or 1) + 1
                self:Redraw()
            end
        end)
        row:AddChild(plusBtn)

        -- [Bank] button
        if addon:IsAddOnLoaded("TOGBankClassic") then
            local data    = addon:GetCooldownData()
            local reagent = data.reagents[spellId] or data.transReagents[spellId]
            if reagent then
                local bankBtn = AceGUI:Create("Button")
                bankBtn:SetText(L["BankBtn"])
                bankBtn:SetWidth(60)
                local itemId = reagent.id
                bankBtn:SetCallback("OnClick", function()
                    if TOGBankClassic and TOGBankClassic.RequestItem then
                        TOGBankClassic.RequestItem(itemId)
                    end
                end)
                row:AddChild(bankBtn)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Missing Reagents panel
-- ---------------------------------------------------------------------------

function ShoppingListTab:FillMissingReagents(container)
    local list = BuildReagentList()

    if #list == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["MissingReagentsEmpty"])
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
        return
    end

    -- Header
    local hdr = AceGUI:Create("SimpleGroup")
    hdr:SetLayout("Flow")
    hdr:SetFullWidth(true)
    container:AddChild(hdr)

    local function Hdr(text, width)
        local l = AceGUI:Create("Label")
        l:SetText("|cffffd100" .. text .. "|r")
        l:SetWidth(width)
        hdr:AddChild(l)
    end
    Hdr(L["ColItem"],     200)
    Hdr(L["ColHave"],      50)
    Hdr(L["ColNeed"],      50)
    Hdr(L["ColShort"],     50)

    -- Rows
    for _, entry in ipairs(list) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        container:AddChild(row)

        local itemColour = entry.shortfall > 0 and "|cffff4444" or "|cff00ff00"
        local itemLbl = AceGUI:Create("InteractiveLabel")
        itemLbl:SetText(itemColour .. entry.itemName .. "|r")
        itemLbl:SetWidth(200)
        local itemId = entry.itemId
        itemLbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetItemByID(itemId)
            GameTooltip:Show()
        end)
        itemLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        -- Shift-click → insert item link into chat
        itemLbl:SetCallback("OnClick", function(_widget, _event, button)
            if button == "LeftButton" and IsShiftKeyDown() then
                local _, link = GetItemInfo(itemId)
                if link and ChatEdit_GetActiveWindow then
                    local editBox = ChatEdit_GetActiveWindow()
                    if editBox then
                        editBox:Insert(link)
                    end
                end
            end
        end)
        row:AddChild(itemLbl)

        local function Num(val, width, colour)
            local l = AceGUI:Create("Label")
            l:SetText((colour or "") .. tostring(val) .. (colour ~= "" and "|r" or ""))
            l:SetWidth(width)
            row:AddChild(l)
        end
        Num(entry.have,      50, "")
        Num(entry.needed,    50, "")
        Num(entry.shortfall, 50, entry.shortfall > 0 and "|cffff4444" or "|cff00ff00")

        -- [Bank] button
        if addon:IsAddOnLoaded("TOGBankClassic") then
            local bankBtn = AceGUI:Create("Button")
            bankBtn:SetText(L["BankBtn"])
            bankBtn:SetWidth(60)
            bankBtn:SetCallback("OnClick", function()
                if TOGBankClassic and TOGBankClassic.RequestItem then
                    TOGBankClassic.RequestItem(itemId)
                end
            end)
            row:AddChild(bankBtn)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Reagent Watch panel
-- ---------------------------------------------------------------------------

function ShoppingListTab:FillReagentWatch(container)
    local RW = addon.ReagentWatch

    -- Add-item row: text box + [Watch] button
    local addRow = AceGUI:Create("SimpleGroup")
    addRow:SetLayout("Flow")
    addRow:SetFullWidth(true)
    container:AddChild(addRow)

    local inputBox = AceGUI:Create("EditBox")
    inputBox:SetLabel(L["WatchInputLabel"])
    inputBox:SetWidth(200)
    addRow:AddChild(inputBox)

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText(L["WatchBtn"])
    addBtn:SetWidth(70)
    addBtn:SetCallback("OnClick", function()
        local text = strtrim(inputBox:GetText() or "")
        -- Accept a numeric ID or extract from a hyperlink
        local itemId = tonumber(text) or tonumber(text:match("item:(%d+)"))
        if itemId and RW then
            RW:Watch(itemId)
            inputBox:SetText("")
        end
    end)
    addRow:AddChild(addBtn)

    -- Allow pasting a link directly into the edit box
    inputBox:SetCallback("OnEnterPressed", function(widget)
        local text = strtrim(widget:GetText() or "")
        local itemId = tonumber(text) or tonumber(text:match("item:(%d+)"))
        if itemId and RW then
            RW:Watch(itemId)
            widget:SetText("")
        end
    end)

    -- Divider
    local sep = AceGUI:Create("Heading")
    sep:SetText(L["WatchedItemsHeading"])
    sep:SetFullWidth(true)
    container:AddChild(sep)

    if not RW then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["ReagentWatchModuleMissing"])
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
        return
    end

    local list = RW:GetWatchedItems()
    if #list == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["ReagentWatchEmpty"])
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
        return
    end

    for _, entry in ipairs(list) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        container:AddChild(row)

        -- [x] remove
        local removeBtn = AceGUI:Create("Button")
        removeBtn:SetText("x")
        removeBtn:SetWidth(28)
        local iid = entry.itemId
        removeBtn:SetCallback("OnClick", function()
            RW:Unwatch(iid)
        end)
        row:AddChild(removeBtn)

        -- Item name (tooltip on hover)
        local lbl = AceGUI:Create("InteractiveLabel")
        lbl:SetText(entry.itemName)
        lbl:SetWidth(220)
        lbl:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetItemByID(iid)
            GameTooltip:Show()
        end)
        lbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        row:AddChild(lbl)

        -- Bag count
        local countLbl = AceGUI:Create("Label")
        local colour = entry.count > 0 and "|cff00ff00" or "|cffaaaaaa"
        countLbl:SetText(colour .. "x" .. entry.count .. "|r")
        countLbl:SetWidth(60)
        row:AddChild(countLbl)
    end
end

-- ---------------------------------------------------------------------------
-- Redraw (called after shopping list changes)
-- ---------------------------------------------------------------------------

function ShoppingListTab:Redraw()
    if not self._container then return end
    -- Unsubscribe before releasing so we re-subscribe cleanly in Draw()
    if self._watchCallbackRegistered then
        addon:UnregisterCallback("REAGENT_WATCH_UPDATED", self)
        self._watchCallbackRegistered = false
    end
    self._container:ReleaseChildren()
    self:Draw(self._container)
end
