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
--- Shared with Modules/ReagentWatch.lua via Compat.lua — a GUI tab carrying its
--- own copy of a Module's bag scan gave the rule two owners across a layer
--- boundary. Do not re-inline it.
local function ScanBags()
    return addon:ScanBagCounts()
end

--- Aggregate reagent requirements across the shopping list.
-- Returns array of { itemId, itemName, needed, have, shortfall }
--
-- A method rather than a file-local so it can be tested directly: this is the
-- arithmetic the whole tab exists to present, and everything around it is
-- rendering. Covered by Tests/shoppinglist_spec.lua.
function ShoppingListTab:BuildReagentList()
    local bl   = Ace.db.char.shoppingList
    local data = addon:GetCooldownData()
    local need = {}   -- [itemId] = totalNeeded

    for spellId, entry in pairs(bl) do
        local qty     = (entry and entry.quantity) or 1
        local reagent = data.reagents[spellId] or data.transReagents[spellId]
        if reagent then
            local id = reagent.id
            need[id] = (need[id] or 0) + (reagent.qty * qty)
        else
            -- Multi-reagent cooldowns need EVERY reagent, not a featured one.
            -- This branch was missing entirely: queueing Brilliant Glass,
            -- Primal Mooncloth, Spellcloth or Shadowcloth added nothing to the
            -- shopping list and said nothing about it, because those four live
            -- in multiReagents and the loop only ever read `reagents`. A
            -- shopping list that silently omits what you have to buy is worse
            -- than one that is empty.
            local multi = data.multiReagents and data.multiReagents[spellId]
            if multi then
                for _, rg in ipairs(multi) do
                    need[rg.id] = (need[rg.id] or 0) + (rg.qty * qty)
                end
            end
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

    local rowIndex = 0
    for spellId, entry in pairs(bl) do
        rowIndex = rowIndex + 1
        local spellName = GetSpellInfo(spellId) or tostring(spellId)
        local qty       = (entry and entry.quantity) or 1

        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        container:AddChild(row)
        addon.GUI.ApplyRowStripe(row.frame, rowIndex)

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
            addon.Tooltip.Owner(_widget.frame)
            GameTooltip:SetSpellByID(sid)
            -- A spell tooltip carries no item, so the global OnTooltipSetItem
            -- hook never fires -- these rows ARE recipes and showed none of the
            -- detail the Professions tab gives them.
            addon.ItemLink.AppendRecipeBlocks(GameTooltip, nil, sid)
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
                    -- Routed through addon.Bank, which we own. The old call
                    -- went to a field on `_G.TOGBankClassic` -- that addon's UI
                    -- controller FRAME (Modules/UI.lua), which has never
                    -- carried one -- so the guard was never true and this
                    -- button did nothing, silently, for its whole life.
                    if addon.Bank and addon.Bank.ShowRequestDialog then
                        addon.Bank.ShowRequestDialog(itemId, reagent.name, reagent.link, bankBtn.frame)
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
    local list = self:BuildReagentList()

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
        addon.GUI.MakeColumnHeader({
            parent = hdr,
            label = text,
            width = width,
        })
    end
    Hdr(L["ColItem"],     200)
    Hdr(L["ColHave"],      50)
    Hdr(L["ColNeed"],      50)
    Hdr(L["ColShort"],     50)

    -- Rows
    for rowIndex, entry in ipairs(list) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        container:AddChild(row)
        addon.GUI.ApplyRowStripe(row.frame, rowIndex)

        local itemColour = entry.shortfall > 0 and "|cffff4444" or "|cff00ff00"
        local itemLbl = AceGUI:Create("InteractiveLabel")
        itemLbl:SetText(itemColour .. entry.itemName .. "|r")
        itemLbl:SetWidth(200)
        local itemId = entry.itemId
        itemLbl:SetCallback("OnEnter", function(_widget)
            addon.Tooltip.Owner(_widget.frame)
            addon.ItemLink.SetItem(GameTooltip, select(2, GetItemInfo(itemId)), itemId)
            GameTooltip:Show()
        end)
        itemLbl:SetCallback("OnLeave", function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end)
        itemLbl:SetCallback("OnClick", function(_widget, _event, button)
            if button == "LeftButton" then
                addon.ItemLink.Click((select(2, GetItemInfo(itemId))))
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
                -- See the note on the other [Bank] button above: the old guard
                -- keyed on another addon's global and could never be true.
                if addon.Bank and addon.Bank.ShowRequestDialog then
                    addon.Bank.ShowRequestDialog(itemId, entry.name, entry.link, bankBtn.frame)
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
    addon.GUI.OffsetInputLabel(inputBox)
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

    for rowIndex, entry in ipairs(list) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        container:AddChild(row)
        addon.GUI.ApplyRowStripe(row.frame, rowIndex)

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
            addon.Tooltip.Owner(widget.frame)
            GameTooltip:SetItemByID(iid)
            GameTooltip:Show()
        end)
        lbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        row:AddChild(lbl)

        -- Bag + bank count.  Bag count is coloured (green=present in bags,
        -- yellow=only in bank, grey=nowhere); bank stock is shown separately
        -- in light blue so the player can see what the guild bank can supply
        -- without conflating it with personal possession.
        local bankCount = addon.Bank and addon.Bank.GetStock(iid) or 0
        local countLbl = AceGUI:Create("Label")
        local colour
        if entry.count > 0 then     colour = "|cff00ff00"
        elseif bankCount > 0 then   colour = "|cffffff00"
        else                        colour = "|cffaaaaaa"
        end
        local bankText = bankCount > 0
            and (" |cff88ccff+" .. bankCount .. "|r")
            or  ""
        countLbl:SetText(colour .. "x" .. entry.count .. "|r" .. bankText)
        countLbl:SetWidth(120)
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
