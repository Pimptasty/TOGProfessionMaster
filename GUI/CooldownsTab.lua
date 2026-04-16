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
CooldownsTab._sortCol   = "time"    -- "char" | "cd" | "reagent" | "time"
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
-- { charKey, shortName, spellId, cdName, reagentItemId, expiresAt, isGroup, group }
local function BuildRows(readyOnly)
    local gdb = addon:GetGuildDb()
    if not gdb then return {} end

    local data = addon:GetCooldownData()
    local now  = GetServerTime()
    local rows = {}

    -- Collect all spellIds that belong to a group so we can skip them as
    -- individual rows and only emit one group-header row per character.
    -- (Group rows are expanded interactively.)

    for charKey, charCds in pairs(gdb.cooldowns) do
        local shortName = charKey:match("^(.-)%-") or charKey

        -- Track which group keys we've already emitted for this character.
        local emittedGroups = {}

        -- Iterate every stored cooldown for this character.
        for spellId, expiresAt in pairs(charCds) do
            local remaining = expiresAt - now
            if readyOnly and remaining > 0 then
                -- skip
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
                                charKey      = charKey,
                                shortName    = shortName,
                                spellId      = spellId,
                                cdName       = group.label,
                                reagentItemId = nil,
                                expiresAt    = groupExpiry,
                                isGroup      = true,
                                group        = group,
                            })
                        end
                    end
                else
                    -- Regular single-spell cooldown row.
                    local cdName = (data.cooldowns[spellId] or data.transmutes[spellId]) or tostring(spellId)
                    local reagentItemId = nil
                    if data.reagents[spellId] then
                        reagentItemId = data.reagents[spellId].id
                    elseif data.transReagents[spellId] then
                        reagentItemId = data.transReagents[spellId].id
                    end
                    -- Icon override for display
                    local iconItemId = (data.iconOverrides and data.iconOverrides[spellId]) or nil
                    table.insert(rows, {
                        charKey       = charKey,
                        shortName     = shortName,
                        spellId       = spellId,
                        cdName        = cdName,
                        reagentItemId = reagentItemId,
                        iconItemId    = iconItemId,
                        expiresAt     = expiresAt,
                        isGroup       = false,
                        group         = nil,
                    })
                end
            end
        end
    end

    return rows
end

local function SortRows(rows, col, asc)
    local now = GetServerTime()
    table.sort(rows, function(a, b)
        local va, vb
        if col == "char" then
            va, vb = a.shortName, b.shortName
        elseif col == "cd" then
            va, vb = a.cdName, b.cdName
        elseif col == "reagent" then
            va = a.reagentItemId and (GetItemInfo(a.reagentItemId) or "") or ""
            vb = b.reagentItemId and (GetItemInfo(b.reagentItemId) or "") or ""
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
    local cols = {
        { key = "char",    label = L["ColCharacter"], width = 130 },
        { key = "cd",      label = L["ColCooldown"],  width = 160 },
        { key = "reagent", label = L["ColReagent"],   width = 140 },
        { key = "time",    label = L["ColTimeLeft"],  width = 90  },
    }
    for _, col in ipairs(cols) do
        local btn = AceGUI:Create("InteractiveLabel")
        local arrow = ""
        if self._sortCol == col.key then
            arrow = self._sortAsc and " ▲" or " ▼"
        end
        btn:SetText("|cffffd100" .. col.label .. arrow .. "|r")
        btn:SetWidth(col.width)
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

    -- Reagent name (item info may not be in cache — that's fine, shows nil gracefully)
    local reagentName = ""
    if row.reagentItemId then
        reagentName = GetItemInfo(row.reagentItemId) or "|cffaaaaaa(loading…)|r"
    end

    local rowGroup = AceGUI:Create("SimpleGroup")
    rowGroup:SetLayout("Flow")
    rowGroup:SetFullWidth(true)
    parent:AddChild(rowGroup)

    -- Character
    local charLbl = AceGUI:Create("InteractiveLabel")
    local DS = addon.Scanner and addon.Scanner.DS
    local online = DS and DS:IsPlayerOnline(row.charKey) or false
    local nameColour = online and "|cffffffff" or "|cffaaaaaa"
    charLbl:SetText(nameColour .. row.shortName .. "|r")
    charLbl:SetWidth(130)
    -- Right-click → whisper
    charLbl:SetCallback("OnClick", function(_widget, _event, button)
        if button == "RightButton" then
            ChatFrame_OpenChat("/w " .. row.shortName .. " ")
        end
    end)
    rowGroup:AddChild(charLbl)

    -- Cooldown name
    local cdLbl = AceGUI:Create("InteractiveLabel")
    local cdText = row.isGroup and ("|cffffd100[+] |r" .. row.cdName) or row.cdName
    cdLbl:SetText(cdText)
    cdLbl:SetWidth(160)
    if not row.isGroup then
        cdLbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetSpellByID(row.spellId)
            GameTooltip:Show()
        end)
        cdLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    else
        -- Group row expand popup
        cdLbl:SetCallback("OnClick", function()
            self:ShowGroupPopup(row, now)
        end)
    end
    rowGroup:AddChild(cdLbl)

    -- Reagent
    local reagentLbl = AceGUI:Create("InteractiveLabel")
    reagentLbl:SetText(reagentName)
    reagentLbl:SetWidth(140)
    if row.reagentItemId then
        local itemId = row.reagentItemId
        reagentLbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetItemByID(itemId)
            GameTooltip:Show()
        end)
        reagentLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end
    rowGroup:AddChild(reagentLbl)

    -- Time Left
    local timeLbl = AceGUI:Create("Label")
    timeLbl:SetText(timeStr)
    timeLbl:SetWidth(90)
    rowGroup:AddChild(timeLbl)

    -- [Bank] button — shown when TOGBankClassic is loaded and has the reagent
    if row.reagentItemId and addon:IsAddOnLoaded("TOGBankClassic") then
        local bankBtn = AceGUI:Create("Button")
        bankBtn:SetText(L["BankBtn"])
        bankBtn:SetWidth(60)
        bankBtn:SetCallback("OnClick", function()
            if TOGBankClassic and TOGBankClassic.RequestItem then
                TOGBankClassic.RequestItem(row.reagentItemId)
            end
        end)
        rowGroup:AddChild(bankBtn)
    end
end

--- Show a small popup listing all individual spells inside a cooldown group.
function CooldownsTab:ShowGroupPopup(row, now)
    local popup = AceGUI:Create("Window")
    popup:SetTitle(row.cdName)
    popup:SetWidth(280)
    popup:SetHeight(200)
    popup:SetLayout("List")
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    local gdb      = addon:GetGuildDb()
    local charCds  = gdb and gdb.cooldowns[row.charKey] or {}

    for spellId, spellName in pairs(row.group.spells) do
        local expiresAt = charCds[spellId]
        local timeStr   = expiresAt and SecondsToString(expiresAt - now) or "|cffaaaaaa(unknown)|r"
        local lbl = AceGUI:Create("Label")
        lbl:SetText(string.format("%s  %s", spellName, timeStr))
        lbl:SetFullWidth(true)
        popup:AddChild(lbl)
    end

    local closeBtn = AceGUI:Create("Button")
    closeBtn:SetText(L["CloseBtn"])
    closeBtn:SetFullWidth(true)
    closeBtn:SetCallback("OnClick", function() AceGUI:Release(popup) end)
    popup:AddChild(closeBtn)
end
