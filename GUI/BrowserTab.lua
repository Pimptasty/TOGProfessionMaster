-- TOG Profession Master — Profession Browser Tab
-- Draws the "Professions" tab inside the main window.
--
-- Layout:
--   [Search box]  [Profession dropdown]  [View: Guild / Mine]
--   ┌────────────────────────────────────────────────────────┐
--   │ Left (professions list)  │ Right (characters/recipes)  │
--   └────────────────────────────────────────────────────────┘
--
-- Selecting a profession row populates the right panel with characters
-- who know it and their skill level.  Selecting a character row expands
-- their known recipes for that profession (filtered by search text).

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local BrowserTab = {}
addon.BrowserTab = BrowserTab

-- State persisted within a single window session (cleared on tab redraw).
BrowserTab._selectedProfId = nil
BrowserTab._selectedChar   = nil
BrowserTab._searchText     = ""
BrowserTab._viewMode       = "guild"   -- "guild" | "mine"

-- ---------------------------------------------------------------------------
-- Helpers — data access
-- ---------------------------------------------------------------------------

local function GetGuildDb()
    return addon:GetGuildDb()
end

--- Return a sorted list of {profId, name, icon} for professions found
--- in the current guild data that match the current view mode.
local function GetProfessionList(viewMode)
    local gdb = GetGuildDb()
    if not gdb then return {} end

    local myKey  = addon:GetCharacterKey()
    local found  = {}
    local seen   = {}

    for charKey, charData in pairs(gdb.guildData) do
        if viewMode == "mine" and charKey ~= myKey then
            -- skip
        elseif type(charData.professions) == "table" then
            for profId in pairs(charData.professions) do
                if not seen[profId] then
                    seen[profId] = true
                    local icon = addon.ProfessionIcons and
                                 (addon.ProfessionIcons[profId] or addon.ProfessionIcons._fallback)
                    local info = charData.professions[profId]
                    table.insert(found, {
                        profId = profId,
                        name   = (info and info.name) or tostring(profId),
                        icon   = icon,
                    })
                end
            end
        end
    end

    table.sort(found, function(a, b) return a.name < b.name end)
    return found
end

--- Return sorted list of {charKey, skillRank, skillMax} for a given profId.
local function GetCharactersForProf(profId, viewMode)
    local gdb = GetGuildDb()
    if not gdb then return {} end

    local myKey = addon:GetCharacterKey()
    local DS    = addon.Scanner and addon.Scanner.DS
    local list  = {}

    for charKey, charData in pairs(gdb.guildData) do
        if viewMode == "mine" and charKey ~= myKey then
            -- skip
        elseif charData.professions and charData.professions[profId] then
            local prof   = charData.professions[profId]
            local online = DS and DS:IsPlayerOnline(charKey) or false
            table.insert(list, {
                charKey   = charKey,
                skillRank = prof.skillRank or 0,
                skillMax  = prof.skillMax  or 300,
                online    = online,
            })
        end
    end

    -- Online first, then alphabetical.
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.charKey < b.charKey
    end)
    return list
end

--- Return sorted list of recipe spell IDs for a character+profession,
--- filtered by search text (matched against GetSpellInfo name).
local function GetRecipes(charKey, profId, searchText)
    local gdb = GetGuildDb()
    if not gdb then return {} end

    local charData = gdb.guildData[charKey]
    if not charData or not charData.professions then return {} end
    local prof = charData.professions[profId]
    if not prof or not prof.recipes then return {} end

    local filter = searchText and searchText:lower() or ""
    local list   = {}

    for spellId in pairs(prof.recipes) do
        local spellName = GetSpellInfo(spellId) or tostring(spellId)
        if filter == "" or spellName:lower():find(filter, 1, true) then
            table.insert(list, { spellId = spellId, name = spellName })
        end
    end

    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function BrowserTab:Draw(container)
    container:SetLayout("Flow")

    -- ---- Toolbar row -------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    -- Search box
    local search = AceGUI:Create("EditBox")
    search:SetLabel("")
    search:SetPlaceholderText("Search recipes…")
    search:SetWidth(200)
    search:SetText(self._searchText)
    search:SetCallback("OnTextChanged", function(_widget, _event, text)
        self._searchText = text
        self:RefreshRight(container)
    end)
    toolbar:AddChild(search)

    -- Spacer
    local sp = AceGUI:Create("Label")
    sp:SetWidth(8)
    toolbar:AddChild(sp)

    -- View mode dropdown
    local viewDD = AceGUI:Create("Dropdown")
    viewDD:SetLabel("")
    viewDD:SetWidth(130)
    viewDD:SetList({ guild = L["ViewGuild"], mine = L["ViewMine"] })
    viewDD:SetValue(self._viewMode)
    viewDD:SetCallback("OnValueChanged", function(_widget, _event, value)
        self._viewMode = value
        self._selectedProfId = nil
        self._selectedChar   = nil
        self:RedrawSplit(container)
    end)
    toolbar:AddChild(viewDD)

    -- ---- Split pane --------------------------------------------------------
    self:DrawSplit(container)
end

--- Draw the two-column split.  Stored on self so RefreshRight can rebuild
--- only the right pane without tearing down the profession list.
function BrowserTab:DrawSplit(container)
    -- Remove any existing split group.
    if self._splitGroup then
        self._splitGroup:Release()
        self._splitGroup = nil
    end

    local split = AceGUI:Create("SimpleGroup")
    split:SetLayout("Flow")
    split:SetFullWidth(true)
    split:SetFullHeight(true)
    container:AddChild(split)
    self._splitGroup    = split
    self._splitContainer = container

    self:DrawLeft(split)
    self:DrawRight(split)
end

--- Redraw just the right pane (search filter changed, character selected, etc.)
function BrowserTab:RefreshRight(container)
    if not self._rightGroup then return end
    self._rightGroup:ReleaseChildren()
    self:FillRight(self._rightGroup)
end

--- Redraw both panes (prof selection or view mode changed).
function BrowserTab:RedrawSplit(container)
    if not self._splitGroup then
        self:DrawSplit(container or self._splitContainer)
        return
    end
    self._splitGroup:ReleaseChildren()
    self:DrawLeft(self._splitGroup)
    self:DrawRight(self._splitGroup)
end

-- ---------------------------------------------------------------------------
-- Left pane — profession list
-- ---------------------------------------------------------------------------

function BrowserTab:DrawLeft(parent)
    local leftGroup = AceGUI:Create("InlineGroup")
    leftGroup:SetTitle(L["PanelProfessions"])
    leftGroup:SetLayout("List")
    leftGroup:SetWidth(180)
    leftGroup:SetFullHeight(true)
    parent:AddChild(leftGroup)
    self._leftGroup = leftGroup

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    leftGroup:AddChild(scroll)

    local profs = GetProfessionList(self._viewMode)
    if #profs == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetText(L["NoDataYet"])
        empty:SetFullWidth(true)
        scroll:AddChild(empty)
        return
    end

    for _, entry in ipairs(profs) do
        local btn = AceGUI:Create("InteractiveLabel")
        local isSelected = (entry.profId == self._selectedProfId)
        local colour = isSelected and "|cffffd100" or "|cffffffff"
        btn:SetText(colour .. entry.name .. "|r")
        btn:SetImage(entry.icon or 134400, 0, 1, 0, 1)
        btn:SetImageSize(16, 16)
        btn:SetFullWidth(true)
        local profId = entry.profId
        btn:SetCallback("OnClick", function()
            self._selectedProfId = profId
            self._selectedChar   = nil
            self:RedrawSplit(self._splitContainer)
        end)
        scroll:AddChild(btn)
    end
end

-- ---------------------------------------------------------------------------
-- Right pane — character list or recipe list
-- ---------------------------------------------------------------------------

function BrowserTab:DrawRight(parent)
    local rightGroup = AceGUI:Create("InlineGroup")
    rightGroup:SetTitle(self._selectedProfId and L["PanelCharacters"] or L["SelectProfession"])
    rightGroup:SetLayout("Fill")
    rightGroup:SetFullHeight(true)
    rightGroup:SetRelativeWidth(1)   -- fills remaining width
    parent:AddChild(rightGroup)
    self._rightGroup = rightGroup

    self:FillRight(rightGroup)
end

function BrowserTab:FillRight(container)
    if not self._selectedProfId then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["SelectProfHint"])
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
        return
    end

    if self._selectedChar then
        self:DrawRecipes(container)
    else
        self:DrawCharacters(container)
    end
end

function BrowserTab:DrawCharacters(container)
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    local chars = GetCharactersForProf(self._selectedProfId, self._viewMode)
    if #chars == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["NoProfMembers"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    for _, entry in ipairs(chars) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        scroll:AddChild(row)

        -- Online dot
        local dot = AceGUI:Create("Label")
        dot:SetWidth(14)
        dot:SetText(entry.online and "|cff00ff00●|r" or "|cffaaaaaa●|r")
        row:AddChild(dot)

        -- Character name + skill
        local shortName = entry.charKey:match("^(.-)%-") or entry.charKey
        local btn = AceGUI:Create("InteractiveLabel")
        btn:SetText(string.format("%s  |cffaaaaaa(%d/%d)|r", shortName,
                    entry.skillRank, entry.skillMax))
        btn:SetFullWidth(true)
        local charKey  = entry.charKey
        local profId   = self._selectedProfId
        btn:SetCallback("OnClick", function()
            self._selectedChar = charKey
            self._selectedProfId = profId
            container:ReleaseChildren()
            -- Back button header
            local back = AceGUI:Create("InteractiveLabel")
            back:SetText(L["BackToCharacters"])
            back:SetFullWidth(true)
            back:SetCallback("OnClick", function()
                self._selectedChar = nil
                container:ReleaseChildren()
                self:FillRight(container)
            end)
            container:AddChild(back)
            self:DrawRecipes(container)
        end)
        row:AddChild(btn)
    end
end

function BrowserTab:DrawRecipes(container)
    local profId  = self._selectedProfId
    local charKey = self._selectedChar
    if not profId or not charKey then return end

    local shortName = charKey:match("^(.-)%-") or charKey
    local header = AceGUI:Create("Label")
    header:SetText(string.format("|cffffd100%s — recipes|r", shortName))
    header:SetFullWidth(true)
    container:AddChild(header)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    local recipes = GetRecipes(charKey, profId, self._searchText)
    if #recipes == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["NoMatchingRecipes"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    for _, entry in ipairs(recipes) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        scroll:AddChild(row)

        local lbl = AceGUI:Create("InteractiveLabel")
        lbl:SetText(entry.name)
        lbl:SetFullWidth(true)

        -- Hover: spell tooltip
        lbl:SetCallback("OnEnter", function(_widget)
            GameTooltip:SetOwner(_widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetSpellByID(entry.spellId)
            GameTooltip:Show()
        end)
        lbl:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- + button to add to shopping list
        local addBtn = AceGUI:Create("Button")
        addBtn:SetText("+")
        addBtn:SetWidth(30)
        addBtn:SetCallback("OnClick", function()
            local bl = Ace.db.char.shoppingList
            if not bl[entry.spellId] then
                bl[entry.spellId] = { quantity = 1 }
                addon:Print("Added |cffffd100" .. entry.name .. "|r to reagent list.")
            end
        end)

        row:AddChild(lbl)
        row:AddChild(addBtn)
    end
end
