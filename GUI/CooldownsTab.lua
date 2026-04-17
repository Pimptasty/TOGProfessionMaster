-- TOG Profession Master — Cooldowns Tab
-- Draws the "Cooldowns" tab inside the main window.
--
-- Columns: Character · Cooldown · Reagent · Time Left
-- Features:
--   • Sort by any column (click header; toggle asc/desc; state saved in AceDB)
--   • "Ready Only" toggle filter
--   • Grouped rows for multi-spell cooldowns (Transmute, Dreamcloth, etc.)
--   • Spell tooltip on cooldown name hover
--   • Item tooltip on reagent name hover
--   • Right-click row → whisper character

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local CooldownsTab = {}
addon.CooldownsTab = CooldownsTab

-- Sort state persisted across redraws (but not saved to AceDB for now).
CooldownsTab._sortCol   = "time"    -- "char" | "cd" | "time"
CooldownsTab._sortAsc   = true
CooldownsTab._readyOnly = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function SecondsToString(secs)
    if secs <= 0 then return L["Ready"] end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

--- Build the flat list of rows to render.
-- Returns array of:
-- { charKey, shortName, spellId, cdName, reagentItemId, expiresAt,
--   isGroup, group, isTransmuteGroup, transmutes, transmuteReagents }
local function BuildRows(readyOnly)
    local gdb = addon:GetGuildDb()
    if not gdb then return {} end

    local data = addon:GetCooldownData()
    local now  = GetServerTime()
    local rows = {}

    -- Accumulate transmute spells per player before emitting rows.
    -- All transmutes for one player collapse into a single "Transmute" group row.
    local transmuteGroups = {}  -- [charKey] = { spellIds={}, expiresAt }

    for charKey, charCds in pairs(gdb.cooldowns) do
        local shortName = charKey:match("^(.-)%-") or charKey

        -- Track which non-transmute group keys we've already emitted.
        local emittedGroups = {}

        for spellId, expiresAt in pairs(charCds) do
            local remaining = expiresAt - now

            if data.transmutes[spellId] then
                -- Accumulate into this player's transmute group.
                if not transmuteGroups[charKey] then
                    transmuteGroups[charKey] = { shortName = shortName, spellIds = {}, expiresAt = now - 1 }
                end
                local tg = transmuteGroups[charKey]
                tg.spellIds[#tg.spellIds + 1] = spellId
                -- Track the active expiry (past = ready; keep the most-future value).
                if expiresAt > now and expiresAt > tg.expiresAt then
                    tg.expiresAt = expiresAt
                end

            else
                local group = data.groupBySpell and data.groupBySpell[spellId]
                if group then
                    -- Emit a single group row the first time we see any spell from this group.
                    if not emittedGroups[group.groupKey] then
                        emittedGroups[group.groupKey] = true
                        -- Find the longest remaining CD in the group for this char.
                        local groupExpiry = expiresAt
                        for groupSpellId in pairs(group.spells) do
                            local ge = charCds[groupSpellId]
                            if ge and ge > groupExpiry then groupExpiry = ge end
                        end
                        local groupRemaining = groupExpiry - now
                        if not readyOnly or groupRemaining <= 0 then
                            table.insert(rows, {
                                charKey       = charKey,
                                shortName     = shortName,
                                spellId       = spellId,
                                cdName        = group.label,
                                reagentItemId = nil,
                                expiresAt     = groupExpiry,
                                isGroup       = true,
                                group         = group,
                            })
                        end
                    end
                else
                    -- Regular single-spell cooldown row.
                    if not readyOnly or remaining <= 0 then
                        local cdName = data.cooldowns[spellId] or tostring(spellId)
                        local reagentItemId = data.reagents[spellId] and data.reagents[spellId].id
                        local reagentQty    = data.reagents[spellId] and data.reagents[spellId].qty or 1
                        local iconItemId    = data.iconOverrides and data.iconOverrides[spellId]
                        table.insert(rows, {
                            charKey       = charKey,
                            shortName     = shortName,
                            spellId       = spellId,
                            cdName        = cdName,
                            reagentItemId = reagentItemId,
                            reagentQty    = reagentQty,
                            iconItemId    = iconItemId,
                            expiresAt     = expiresAt,
                            isGroup       = false,
                        })
                    end
                end
            end
        end
    end

    -- Emit one transmute row per player.
    for charKey, tg in pairs(transmuteGroups) do
        local remaining = tg.expiresAt - now
        if not readyOnly or remaining <= 0 then
            -- Sort transmute spell IDs by name for a stable popup order.
            table.sort(tg.spellIds, function(a, b)
                return (GetSpellInfo(a) or tostring(a)) < (GetSpellInfo(b) or tostring(b))
            end)
            table.insert(rows, {
                charKey           = charKey,
                shortName         = tg.shortName,
                spellId           = tg.spellIds[1],
                cdName            = L["Transmute"],
                reagentItemId     = nil,
                expiresAt         = tg.expiresAt,
                isGroup           = true,
                isTransmuteGroup  = true,
                transmutes        = tg.spellIds,
                transmuteReagents = data.transReagents,
            })
        end
    end

    return rows
end

local function SortRows(rows, col, asc)
    local now = GetServerTime()
    table.sort(rows, function(a, b)
        local va, vb
        if col == "char" then
            va, vb = a.shortName:lower(), b.shortName:lower()
        elseif col == "cd" then
            va, vb = a.cdName:lower(), b.cdName:lower()
        else  -- "time"
            va, vb = a.expiresAt - now, b.expiresAt - now
            -- Ready (<=0) sorts to the top when ascending.
            if va <= 0 then va = -math.huge end
            if vb <= 0 then vb = -math.huge end
        end
        if asc then return va < vb else return va > vb end
    end)
end

-- ---------------------------------------------------------------------------
-- Supply mail helpers (ported from reference cooldowns-panel.lua)
-- ---------------------------------------------------------------------------

--- Scan bags 0-4 for all stacks of itemId.
-- Returns total (number), stacks ({ {bag,slot,count}, ... })
local function CdMail_CountItemInBags(itemId)
    local total, stacks = 0, {}
    for bag = 0, 4 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag)
                         or GetContainerNumSlots(bag)
        for slot = 1, (numSlots or 0) do
            local info = C_Container and C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            local stackCount = info and info.stackCount
            if not info then
                -- classic-era fallback
                local link = GetContainerItemLink(bag, slot)
                itemID    = link and tonumber(link:match("item:(%d+)")) or nil
                stackCount = link and (select(2, GetContainerItemInfo(bag, slot))) or 0
            end
            if itemID == itemId and (stackCount or 0) > 0 then
                total = total + stackCount
                table.insert(stacks, { bag = bag, slot = slot, count = stackCount })
            end
        end
    end
    return total, stacks
end

--- Greedy fulfillment plan — returns { canFulfill, reason, stacksToAttach, splitStack, totalAttachable }.
local function CdMail_CalculateFulfillmentPlan(items, qtyNeeded, totalInBags)
    if not items or #items == 0 then
        return { canFulfill = false, reason = "No items found in bags.", stacksToAttach = {}, totalAttachable = 0 }
    end
    for i, item in ipairs(items) do item.originalIndex = i end
    table.sort(items, function(a, b)
        if a.count == b.count then return a.originalIndex < b.originalIndex end
        return a.count > b.count
    end)
    local accumulated, attachList = 0, {}
    for _, item in ipairs(items) do
        local remaining = qtyNeeded - accumulated
        if item.count <= remaining then
            accumulated = accumulated + item.count
            table.insert(attachList, { bag = item.bag, slot = item.slot, count = item.count, originalIndex = item.originalIndex })
        end
    end
    if accumulated == qtyNeeded then
        return { canFulfill = true, stacksToAttach = attachList, totalAttachable = accumulated }
    end
    if accumulated < qtyNeeded and totalInBags >= qtyNeeded then
        local bestAcc, bestList = accumulated, attachList
        for skipIdx = 1, math.min(5, #items) do
            local testAcc, testList = 0, {}
            for i, item in ipairs(items) do
                if i ~= skipIdx then
                    local rem = qtyNeeded - testAcc
                    if item.count <= rem then
                        testAcc = testAcc + item.count
                        table.insert(testList, { bag = item.bag, slot = item.slot, count = item.count, originalIndex = item.originalIndex })
                    end
                end
            end
            if testAcc == qtyNeeded then
                return { canFulfill = true, stacksToAttach = testList, totalAttachable = testAcc }
            end
            if testAcc > bestAcc and testAcc < qtyNeeded then bestAcc, bestList = testAcc, testList end
        end
        accumulated, attachList = bestAcc, bestList
    end
    if accumulated < qtyNeeded and totalInBags >= qtyNeeded then
        local remaining = qtyNeeded - accumulated
        for _, item in ipairs(items) do
            if item.count >= remaining then
                local alreadyIn = false
                for _, a in ipairs(attachList) do
                    if a.originalIndex == item.originalIndex then alreadyIn = true; break end
                end
                if not alreadyIn then
                    return { canFulfill = true,
                             reason = string.format("Split %d from stack of %d.", remaining, item.count),
                             stacksToAttach = attachList,
                             splitStack = { bag = item.bag, slot = item.slot, count = item.count, amount = remaining },
                             totalAttachable = accumulated }
                end
            end
        end
    end
    if accumulated == 0 and totalInBags >= qtyNeeded then
        local s = items[1]
        return { canFulfill = true,
                 reason = string.format("Split from stack of %d.", s.count),
                 stacksToAttach = {},
                 splitStack = { bag = s.bag, slot = s.slot, count = s.count, amount = qtyNeeded },
                 totalAttachable = 0 }
    end
    return { canFulfill = false,
             reason = string.format("Need %d more.", qtyNeeded - totalInBags),
             stacksToAttach = {}, totalAttachable = totalInBags }
end

if not StaticPopupDialogs["TOGPM_SPLIT_STACK"] then
    StaticPopupDialogs["TOGPM_SPLIT_STACK"] = {
        text = "%s",
        button1 = "Split",
        button2 = "Cancel",
        OnAccept = function(self, data)
            if not data then return end
            ClearCursor()
            local emptyBag, emptySlot
            for bag = 0, 4 do
                local n = (C_Container and C_Container.GetContainerNumSlots(bag)) or GetContainerNumSlots(bag)
                for slot = 1, (n or 0) do
                    local hasItem = C_Container and C_Container.GetContainerItemInfo(bag, slot)
                                    or GetContainerItemLink(bag, slot)
                    if not hasItem then emptyBag, emptySlot = bag, slot; break end
                end
                if emptyBag then break end
            end
            if not emptyBag then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r No empty bag slot to split into.")
                return
            end
            if C_Container then
                C_Container.SplitContainerItem(data.bag, data.slot, data.amount)
                C_Timer.After(0.1, function()
                    C_Container.PickupContainerItem(emptyBag, emptySlot)
                    C_Timer.After(0.05, function()
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(
                            "|cFF88CCCCTOG Profession Master:|r Split %d x %s — click Mail again to attach.",
                            data.amount, (data.itemName or "items")))
                    end)
                end)
            else
                SplitContainerItem(data.bag, data.slot, data.amount)
                C_Timer.After(0.1, function()
                    PickupContainerItem(emptyBag, emptySlot)
                end)
            end
        end,
        OnCancel = function() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

--- Open mailbox, attach reagents, pre-fill recipient/subject/body.
local function CdMail_PrepareSupplyMail(playerName, cooldownName, reagentId, reagentQty)
    if not MailFrame or not MailFrame:IsShown() then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r Open a mailbox first.")
        return
    end
    if GetSendMailItem(1) then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r Mail already has items attached — send or clear them first.")
        return
    end
    local reagentName = GetItemInfo(reagentId) or ("item:" .. reagentId)
    local totalInBags, stacks = CdMail_CountItemInBags(reagentId)
    if totalInBags == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFF4444TOG Profession Master:|r You have no %s in your bags.", reagentName))
        return
    end
    local plan = CdMail_CalculateFulfillmentPlan(stacks, reagentQty, totalInBags)
    if not plan.canFulfill then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r " .. (plan.reason or "Cannot fulfill."))
        return
    end
    if plan.splitStack then
        local s = plan.splitStack
        local dialog = StaticPopup_Show("TOGPM_SPLIT_STACK",
            string.format("Split %d from stack of %d %s?", s.amount, s.count, reagentName))
        if dialog then
            dialog.data = { bag = s.bag, slot = s.slot, amount = s.amount, itemName = reagentName }
        end
        return
    end
    local attached, attachSlot = 0, 1
    local maxSlots = ATTACHMENTS_MAX_SEND or 12
    for _, stack in ipairs(plan.stacksToAttach) do
        if attached >= reagentQty or attachSlot > maxSlots then break end
        ClearCursor()
        if C_Container then
            C_Container.PickupContainerItem(stack.bag, stack.slot)
        else
            PickupContainerItem(stack.bag, stack.slot)
        end
        ClickSendMailItemButton(attachSlot)
        attached = attached + stack.count
        attachSlot = attachSlot + 1
    end
    if attached == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444TOG Profession Master:|r Could not attach items.")
        return
    end
    local baseName = playerName:match("^([^%-]+)") or playerName
    if SendMailNameEditBox then SendMailNameEditBox:SetText(baseName) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Cooldown supply: " .. cooldownName) end
    if SendMailBodyEditBox then
        SendMailBodyEditBox:SetText(string.format(
            "Hi %s! Here are your %s for the %s cooldown. Please send me what you craft — thanks!",
            baseName, reagentName, cooldownName))
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cFF88CCCCTOG Profession Master:|r Attached %dx %s for %s.", attached, reagentName, baseName))
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function CooldownsTab:Draw(container)
    container:SetLayout("List")

    -- ---- Toolbar -----------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    local readyBtn = AceGUI:Create("Button")
    readyBtn:SetText(self._readyOnly and L["ShowAll"] or L["ReadyOnly"])
    readyBtn:SetWidth(100)
    readyBtn:SetCallback("OnClick", function(_widget)
        self._readyOnly = not self._readyOnly
        _widget:SetText(self._readyOnly and L["ShowAll"] or L["ReadyOnly"])
        self:RedrawTable(container)
    end)
    toolbar:AddChild(readyBtn)

    -- ---- Column headers ----------------------------------------------------
    local headers = AceGUI:Create("SimpleGroup")
    headers:SetLayout("Flow")
    headers:SetFullWidth(true)
    container:AddChild(headers)
    self:DrawHeaders(headers, container)

    -- ---- Scrollable rows ---------------------------------------------------
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)
    self._scroll       = scroll
    self._container    = container

    self:FillRows(scroll)
end

function CooldownsTab:DrawHeaders(parent, container)
    -- 3 columns matching reference: Character (190) | Cooldown (306) | Remaining (80)
    -- The Cooldown header spans both icon+name (220px) and reagent (86px) = 306px total.
    local cols = {
        { key = "char", label = L["ColCharacter"], width = 190 },
        { key = "cd",   label = L["ColCooldown"],  width = 306 },
        { key = "time", label = L["ColTimeLeft"],  width = 80  },
    }
    local texTop    = self._sortAsc and 0.6875 or 0.0
    local texBottom = self._sortAsc and 0.0    or 0.6875

    for _, col in ipairs(cols) do
        local isActive = (self._sortCol == col.key)
        local btn = AceGUI:Create("InteractiveLabel")
        btn:SetText(col.label)
        btn:SetWidth(col.width)

        -- Arrow texture: show only on the active sort column.
        -- Position is deferred via C_Timer so GetStringWidth() is valid after layout.
        local arrow = btn.frame:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture("Interface\\Calendar\\MoreArrow")
        arrow:SetSize(12, 9)
        if isActive then
            arrow:SetTexCoord(0.0, 0.9375, texTop, texBottom)
            arrow:Show()
        else
            arrow:Hide()
        end
        C_Timer.After(0, function()
            if btn.label then
                local sw = btn.label:GetStringWidth()
                arrow:ClearAllPoints()
                arrow:SetPoint("LEFT", btn.frame, "LEFT", sw + 4, 0)
            end
        end)

        local key = col.key
        btn:SetCallback("OnClick", function()
            if self._sortCol == key then
                self._sortAsc = not self._sortAsc
            else
                self._sortCol = key
                self._sortAsc = true
            end
            self:RedrawTable(container)
        end)
        parent:AddChild(btn)
    end
end

function CooldownsTab:RedrawTable(container)
    container:ReleaseChildren()
    self:Draw(container)
end

function CooldownsTab:FillRows(scroll)
    local rows = BuildRows(self._readyOnly)
    SortRows(rows, self._sortCol, self._sortAsc)
    local now = GetServerTime()

    if #rows == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["NoCooldownData"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    for _, row in ipairs(rows) do
        self:DrawRow(scroll, row, now)
    end
end

function CooldownsTab:DrawRow(parent, row, now)
    local remaining = row.expiresAt - now
    local timeStr   = SecondsToString(remaining)
    local timeColor = remaining <= 0 and "|cff00ff00" or
                      (remaining < 7200 and "|cffffff00" or "|cffaaaaaa")

    local rowGroup = AceGUI:Create("SimpleGroup")
    rowGroup:SetLayout("Flow")
    rowGroup:SetFullWidth(true)
    parent:AddChild(rowGroup)

    -- Shared whisper helper (right-click on char label OR anywhere on the row)
    local function openWhisper(target)
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
    local function doWhisper(anchorFrame)
        local shortName = row.shortName
        local fullKey   = row.charKey
        if Menu and Menu.CreateContextMenu then
            Menu.CreateContextMenu(anchorFrame, function(_, root)
                root:CreateTitle(shortName)
                root:CreateButton(shortName, function() openWhisper(fullKey) end)
            end)
        else
            openWhisper(fullKey)
        end
    end
    rowGroup.frame:EnableMouse(true)
    rowGroup.frame:SetScript("OnMouseDown", function(f, button)
        if button == "RightButton" then doWhisper(f) end
    end)

    -- ── Column 1: Character (190px) — online=white, offline=grey ─────────────
    local charLbl = AceGUI:Create("InteractiveLabel")
    local DS = addon.Scanner and addon.Scanner.DS
    local online = DS and DS:IsPlayerOnline(row.charKey) or false
    local nameColor = online and "|cffffffff" or "|cffaaaaaa"
    charLbl:SetText(nameColor .. row.shortName .. "|r")
    charLbl:SetWidth(190)
    charLbl:SetCallback("OnClick", function(_widget, _event, button)
        if button == "RightButton" then doWhisper(_widget.frame) end
    end)
    rowGroup:AddChild(charLbl)

    -- ── Column 2: fixed 306px container — ALL cooldown content lives inside here ──
    -- This SimpleGroup acts as a hard column boundary: charLbl ends at 190px,
    -- col2 spans 190–496px, timeLbl starts at 496px regardless of inner content.

    -- Pre-check bank stock now so we can compute exact inner widths before
    -- creating any widgets (avoids dynamic resize after layout).
    local itemId   = row.reagentItemId
    local hasBank  = false
    if itemId and addon:IsAddOnLoaded("TOGBankClassic") then
        local TOG = _G["TOGBankClassic_Guild"]
        if TOG and TOG.Info and TOG.Info.alts then
            for _, alt in pairs(TOG.Info.alts) do
                for _, entry in ipairs(alt.items or {}) do
                    if entry.ID == itemId and (entry.Count or 0) > 0 then
                        hasBank = true; break
                    end
                end
                if hasBank then break end
            end
        end
    end

    -- Width budget inside col2 (306px):
    --   With reagent + bank : cdLblW = 306-64-42-20 = 180px
    --   With reagent only   : cdLblW = 306-64-20    = 222px
    --   No reagent          : cdLblW = 306px
    local mailW    = itemId and 20 or 0
    local bankW    = (itemId and hasBank) and 42 or 0
    local reagentW = itemId and 64 or 0
    local cdLblW   = 306 - reagentW - bankW - mailW

    local col2 = AceGUI:Create("SimpleGroup")
    col2:SetLayout("Flow")
    col2:SetWidth(306)
    rowGroup:AddChild(col2)

    -- Cooldown icon + name
    local cdLbl = AceGUI:Create("InteractiveLabel")
    cdLbl:SetWidth(cdLblW)

    -- Resolve icon texture
    local iconTexture
    if row.isTransmuteGroup then
        iconTexture = "Interface\\Icons\\Trade_Alchemy"
    elseif row.isGroup then
        iconTexture = row.spellId and GetSpellTexture(row.spellId)
    elseif row.iconItemId then
        iconTexture = select(10, GetItemInfo(row.iconItemId))
        if not iconTexture then
            local iconItem = Item:CreateFromItemID(row.iconItemId)
            iconItem:ContinueOnItemLoad(function()
                local t = select(10, GetItemInfo(row.iconItemId))
                if t and cdLbl.image then
                    cdLbl.image:SetTexture(t)
                    cdLbl.image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    cdLbl.imageshown = true
                end
            end)
            iconTexture = row.spellId and GetSpellTexture(row.spellId)
        end
    else
        iconTexture = row.spellId and GetSpellTexture(row.spellId)
    end
    if iconTexture then
        cdLbl:SetImage(iconTexture)
        cdLbl.image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cdLbl:SetImageSize(14, 14)
    end
    local cdText = row.isGroup and ("[+] " .. row.cdName) or row.cdName
    cdLbl:SetText(cdText)
    if row.isGroup then
        cdLbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            if row.isTransmuteGroup then
                GameTooltip:AddLine("Click to see transmutes", 1, 1, 1)
            else
                GameTooltip:AddLine("Click to see " .. (row.cdName or "details"), 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        cdLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        cdLbl:SetCallback("OnClick", function(_widget, _event, button)
            if button == "LeftButton" then self:ShowGroupPopup(row, now) end
        end)
    else
        cdLbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            if row.spellId then
                if GetSpellInfo(row.spellId) then
                    GameTooltip:SetHyperlink("spell:" .. row.spellId)
                else
                    GameTooltip:SetHyperlink("item:" .. row.spellId)
                end
            end
            GameTooltip:Show()
        end)
        cdLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end
    col2:AddChild(cdLbl)

    -- Reagent + [Bank] + mail — all inside col2, only when a reagent exists
    if itemId then
        -- Reagent name
        local reagentLbl = AceGUI:Create("InteractiveLabel")
        reagentLbl:SetWidth(reagentW)
        local reagentName = GetItemInfo(itemId)
        if reagentName then
            reagentLbl:SetText("|cffaaaaaa" .. reagentName .. "|r")
        else
            reagentLbl:SetText("")
            local rItem = Item:CreateFromItemID(itemId)
            rItem:ContinueOnItemLoad(function()
                local name = rItem:GetItemName()
                if name then reagentLbl:SetText("|cffaaaaaa" .. name .. "|r") end
            end)
        end
        reagentLbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetHyperlink("item:" .. itemId)
            GameTooltip:Show()
        end)
        reagentLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        reagentLbl:SetCallback("OnClick", function(_widget, _event, button)
            if button == "LeftButton" and IsShiftKeyDown() then
                local link = select(2, GetItemInfo(itemId))
                if link then HandleModifiedItemClick(link) end
            end
        end)
        col2:AddChild(reagentLbl)

        -- [Bank] button
        if hasBank then
            local bankBtn = AceGUI:Create("InteractiveLabel")
            bankBtn:SetText("|cFF88FF88[Bank]|r")
            bankBtn:SetWidth(bankW)
            bankBtn:SetCallback("OnClick", function()
                if TOGBankClassic and TOGBankClassic.RequestItem then
                    TOGBankClassic.RequestItem(itemId)
                end
            end)
            bankBtn:SetCallback("OnEnter", function(_widget)
                GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
                GameTooltip:SetText("Request from Bank", 1, 1, 1)
                GameTooltip:AddLine("Send a request to a TOGBankClassic guild banker.", nil, nil, nil, true)
                GameTooltip:Show()
            end)
            bankBtn:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            col2:AddChild(bankBtn)
        end

        -- Mail icon
        local mailBtn = AceGUI:Create("InteractiveLabel")
        mailBtn:SetImage("Interface\\Icons\\INV_Letter_15")
        mailBtn:SetImageSize(16, 16)
        mailBtn:SetText("")
        mailBtn:SetWidth(mailW)
        mailBtn:SetCallback("OnClick", function()
            local cdName = row.isTransmuteGroup and L["Transmute"] or row.cdName
            CdMail_PrepareSupplyMail(row.charKey, cdName, itemId, row.reagentQty or 1)
        end)
        mailBtn:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetText(L["MailBtnTooltip"] or "Send Supply Mail", 1, 1, 1)
            GameTooltip:AddLine(L["MailBtnTooltipDesc"] or "Open a mailbox, then click to attach reagents.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        mailBtn:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        col2:AddChild(mailBtn)
    end

    -- ── Column 3: Time Remaining (80px) — always at 496px, never displaced ───
    local timeLbl = AceGUI:Create("Label")
    timeLbl:SetText(timeColor .. timeStr .. "|r")
    timeLbl:SetWidth(80)
    rowGroup:AddChild(timeLbl)
end

--- Show a popup listing all individual spells inside a cooldown group.
-- For transmute groups: shows each spell with its per-spell reagent and a mail button.
-- For other groups: shows spell name and time remaining.
-- Clicking the same row again or clicking outside closes the popup.
function CooldownsTab:ShowGroupPopup(row, now)
    -- Toggle off if the same row was clicked again.
    if self._groupPopup then
        local wasRow = self._groupPopup._sourceRow == row
        self._groupPopup:Hide()
        self._groupPopup = nil
        if wasRow then return end
    end

    local spells = row.transmutes or (row.group and row.group.spells and
        (function()
            local t = {}
            for id in pairs(row.group.spells) do t[#t + 1] = id end
            table.sort(t, function(a, b)
                return (GetSpellInfo(a) or tostring(a)) < (GetSpellInfo(b) or tostring(b))
            end)
            return t
        end)())
    if not spells or #spells == 0 then return end

    local reagentsMap = row.transmuteReagents  -- nil for non-transmute groups
    local charKey     = row.charKey
    local gdb         = addon:GetGuildDb()
    local charCds     = gdb and gdb.cooldowns[charKey] or {}

    local rowH   = 20
    local pad    = 6
    local popupW = 340
    local totalH = pad + #spells * rowH + pad

    local popup = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    popup:SetWidth(popupW)
    popup:SetHeight(totalH)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetBackdrop({
        bgFile   = [[Interface\Tooltips\UI-Tooltip-Background]],
        edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    popup:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    popup:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup._sourceRow = row

    -- Click-outside-to-close overlay
    local closeOnClick = CreateFrame("Frame", nil, UIParent)
    closeOnClick:SetAllPoints(UIParent)
    closeOnClick:SetFrameStrata("DIALOG")
    closeOnClick:EnableMouse(true)
    closeOnClick:SetScript("OnMouseDown", function()
        popup:Hide(); closeOnClick:Hide()
        if CooldownsTab._groupPopup == popup then CooldownsTab._groupPopup = nil end
    end)
    popup:EnableMouse(true)
    popup:SetScript("OnMouseDown", function() end)  -- block click-through
    popup:SetScript("OnHide", function() closeOnClick:Hide() end)

    local mailW    = reagentsMap and 20 or 0
    local reagentW = reagentsMap and 110 or 0
    local timeW    = 70
    local nameW    = popupW - pad * 2 - reagentW - mailW - timeW - 4

    for i, spellId in ipairs(spells) do
        local expiresAt = charCds[spellId]
        local timeStr   = expiresAt and SecondsToString(expiresAt - now) or "|cffaaaaaa?|r"
        local timeColor = (expiresAt and (expiresAt - now) <= 0) and "|cff00ff00" or "|cffaaaaaa"
        local reagentEntry = reagentsMap and reagentsMap[spellId]
        local reagentId    = reagentEntry and reagentEntry.id
        local reagentQty   = reagentEntry and reagentEntry.qty or 1

        local yOff = -(pad + (i - 1) * rowH)

        local entry = CreateFrame("Frame", nil, popup)
        entry:SetHeight(rowH)
        entry:SetPoint("TOPLEFT",  popup, "TOPLEFT",  pad, yOff)
        entry:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -pad, yOff)

        -- Spell name
        local nameLbl = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", 0, 0)
        nameLbl:SetWidth(nameW)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetText(GetSpellInfo(spellId) or ("Spell " .. spellId))

        local nameZone = CreateFrame("Frame", nil, entry)
        nameZone:SetPoint("TOPLEFT",     entry, "TOPLEFT",    0, 0)
        nameZone:SetPoint("BOTTOMRIGHT", entry, "BOTTOMLEFT", nameW, 0)
        nameZone:EnableMouse(true)
        nameZone:SetScript("OnEnter", function()
            nameLbl:SetTextColor(1, 1, 0, 1)
            GameTooltip:SetOwner(nameZone, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. spellId)
            GameTooltip:Show()
        end)
        nameZone:SetScript("OnLeave", function()
            nameLbl:SetTextColor(1, 1, 1, 1)
            GameTooltip:Hide()
        end)

        -- Time remaining
        local timeLbl = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeLbl:SetPoint("LEFT", nameW + 4, 0)
        timeLbl:SetWidth(timeW)
        timeLbl:SetJustifyH("LEFT")
        timeLbl:SetText(timeColor .. timeStr .. "|r")

        -- Reagent and mail button (transmute groups only)
        if reagentId then
            local reagentLbl = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            reagentLbl:SetPoint("RIGHT", entry, "RIGHT", -(mailW + 2), 0)
            reagentLbl:SetWidth(reagentW)
            reagentLbl:SetJustifyH("RIGHT")
            reagentLbl:SetTextColor(0.65, 0.65, 0.65, 1)
            local rName = GetItemInfo(reagentId)
            if rName then
                reagentLbl:SetText(rName)
            else
                reagentLbl:SetText("")
                local rItem = Item:CreateFromItemID(reagentId)
                rItem:ContinueOnItemLoad(function()
                    reagentLbl:SetText(rItem:GetItemName() or "")
                end)
            end

            local reagentZone = CreateFrame("Frame", nil, entry)
            reagentZone:SetPoint("TOPLEFT",     entry, "TOPRIGHT",    -(reagentW + mailW + 2), 0)
            reagentZone:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", -(mailW + 2), 0)
            reagentZone:EnableMouse(true)
            reagentZone:SetScript("OnEnter", function()
                reagentLbl:SetTextColor(1, 1, 0, 1)
                GameTooltip:SetOwner(reagentZone, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. reagentId)
                GameTooltip:Show()
            end)
            reagentZone:SetScript("OnLeave", function()
                reagentLbl:SetTextColor(0.65, 0.65, 0.65, 1)
                GameTooltip:Hide()
            end)
            reagentZone:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" and IsShiftKeyDown() then
                    local link = select(2, GetItemInfo(reagentId))
                    if link then HandleModifiedItemClick(link) end
                end
            end)

            -- Mail icon button
            local mailBtn = CreateFrame("Button", nil, entry)
            mailBtn:SetSize(16, 16)
            mailBtn:SetPoint("RIGHT", entry, "RIGHT", 0, 0)
            mailBtn:SetNormalTexture("Interface\\Icons\\INV_Letter_15")
            mailBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            mailBtn:SetScript("OnClick", function()
                local spellName = GetSpellInfo(spellId) or ("Spell " .. spellId)
                CdMail_PrepareSupplyMail(charKey, spellName, reagentId, reagentQty)
            end)
            mailBtn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(mailBtn, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["MailBtnTooltip"] or "Send Supply Mail", 1, 1, 1)
                GameTooltip:AddLine(L["MailBtnTooltipDesc"] or "Open a mailbox, then click to mail reagents to this player.", nil, nil, nil, true)
                GameTooltip:Show()
            end)
            mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    popup:Show()
    self._groupPopup = popup
end
