-- TOG Profession Master — Profession Browser Tab
-- Draws the "Professions" tab inside the main window.
--
-- Layout:
--   [Profession ▼]  [Search .................]  [Guild ▼]
--   ┌──────────────────────────────┬────────────────────────────┐
--   │ [icon] Recipe   Crafter, +N  │ [icon] Selected Recipe     │
--   │ [icon] Recipe 2 You          │ Shopping: [-] 1 [+] [x]   │
--   │ ...                          │ Reagents ──────────────    │
--   │                              │  [i] Iron Ore      ×5      │
--   │                              │ Known By ──────────────    │
--   │                              │  |cff..You|r               │
--   └──────────────────────────────┴────────────────────────────┘
--
-- Clicking a recipe row populates the right-hand detail panel.
-- The left list uses virtual scrolling (raw frame pool, 35 rows).

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local BrowserTab = {}
addon.BrowserTab = BrowserTab

-- Virtual scroll constants
local ROW_HEIGHT = 14
local POOL_SIZE  = 35

-- Detail panel constants
local DP_W    = 268   -- outer width of the right detail panel
local DP_PAD  = 6     -- inner padding
local DP_GAP  = 4     -- gap between left list and detail panel
local DP_ROW  = 14    -- row height inside the detail panel
local DP_ICON = 18    -- recipe icon size in detail header

-- ---------------------------------------------------------------------------
-- TOGBankClassic integration helpers
-- ---------------------------------------------------------------------------

-- Resolve a reagent's item ID, falling back through itemLink → name lookup.
-- On Classic Era, GetTradeSkillReagentItemLink returns nil for many reagents
-- so the scan path can't always populate itemLink — without this helper the
-- bank-stock lookup at render time silently fails for older scanned recipes
-- and for peer broadcasts predating v0.1.5. Cached back onto the reagent
-- table so subsequent renders are O(1).
local function ResolveReagentItemId(r)
    if not r then return nil end
    if r.itemId and r.itemId > 0 then return r.itemId end
    if type(r.itemLink) == "string" then
        local id = tonumber(r.itemLink:match("item:(%d+)"))
        if id then r.itemId = id; return id end
    end
    if r.name and GetItemInfoInstant then
        local id = GetItemInfoInstant(r.name)
        if id then r.itemId = id; return id end
    end
    return nil
end

-- Resolve a reagent's item link, reconstructing it from itemId via GetItemInfo
-- when the original link is missing.  GetItemInfo returns nil for items not
-- yet in the local cache; callers should treat a nil result as "unavailable
-- this frame, try again next render."
local function ResolveReagentItemLink(r)
    if type(r.itemLink) == "string" and r.itemLink ~= "" then return r.itemLink end
    local id = ResolveReagentItemId(r)
    if id then
        local _, link = GetItemInfo(id)
        if link then r.itemLink = link; return link end
    end
    return nil
end

-- Hidden tooltip used to scrape raw item data without triggering other addon hooks.
local _itemScraper
local function GetItemScraper()
    if not _itemScraper then
        _itemScraper = CreateFrame("GameTooltip", "TOGPMItemScraper", nil, "GameTooltipTemplate")
        _itemScraper:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return _itemScraper
end

-- State persisted across tab switches (reset on UI reload).
BrowserTab._selectedProfId    = 0        -- 0 = All Professions (default)
BrowserTab._searchText        = ""
BrowserTab._viewMode          = "guild"  -- "guild" | "mine"
BrowserTab._scroll            = nil      -- active AceGUI ScrollFrame widget
BrowserTab._container         = nil      -- the tab container widget
BrowserTab._pool              = nil      -- raw-frame row pool (left list)
BrowserTab._recipes           = nil      -- current filtered recipe list
BrowserTab._detailOuter       = nil      -- persistent right-panel raw frame
BrowserTab._selectedEntry     = nil      -- recipe currently shown in detail panel
BrowserTab._slSection         = nil      -- shopping list InlineGroup (if visible)

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

local function GetGuildDb()
    return addon:GetGuildDb()
end

-- Static list of all Vanilla crafting professions, sorted A->Z.
local ALL_PROFESSIONS = {
    { profId = 171, name = "Alchemy"        },
    { profId = 164, name = "Blacksmithing"  },
    { profId = 185, name = "Cooking"        },
    { profId = 333, name = "Enchanting"     },
    { profId = 202, name = "Engineering"    },
    { profId = 129, name = "First Aid"      },
    { profId = 165, name = "Leatherworking" },
    { profId = 186, name = "Mining"         },
    { profId = 197, name = "Tailoring"      },
}

local function GetProfDropdownEntries()
    local entries = { { profId = 0, name = L["AllProfessions"] } }
    for _, p in ipairs(ALL_PROFESSIONS) do
        table.insert(entries, p)
    end
    return entries
end

local PROF_ID_TO_NAME = {}
for _, p in ipairs(ALL_PROFESSIONS) do
    PROF_ID_TO_NAME[p.profId] = p.name
end

local function BuildRecipeList(profId, viewMode, searchText)
    if profId == nil then return {} end
    local gdb = GetGuildDb()
    if not gdb or not gdb.recipes then return {} end

    local myKey = addon:GetCharacterKey()
    local filter = searchText and searchText:lower() or ""
    local list   = {}

    local function processProf(thisProfId, profRecipes)
        if not profRecipes then return end
        local profName   = PROF_ID_TO_NAME[thisProfId] or ""
        local profIconId = addon.ProfessionIcons and addon.ProfessionIcons[thisProfId]
                        or (addon.ProfessionIconFallback or 134400)
        for recipeId, rd in pairs(profRecipes) do
            if rd.crafters then
                local mineVisible = false
                if viewMode == "mine" then
                    for ck in pairs(rd.crafters) do
                        if addon:IsMyCharacter(ck) then mineVisible = true; break end
                    end
                end
                local visible = mineVisible or (viewMode ~= "mine" and next(rd.crafters))
                if visible then
                    local name = rd.name or tostring(recipeId)
                    if filter == "" or name:lower():find(filter, 1, true) then
                        local GuildCache  = addon.Scanner and addon.Scanner.GuildCache
                        local crafterObjs = {}
                        local youSelf, youAlts = nil, {}
                        for ck in pairs(rd.crafters) do
                            if addon:IsMyCharacter(ck) then
                                -- Each of your characters that crafts this recipe gets its own
                                -- entry: "You" for the currently-logged-in character, "You (Alt)"
                                -- for every other own alt, so the user can tell them apart.
                                if ck == myKey then
                                    youSelf = { name = L["You"], online = true, isYou = true }
                                else
                                    local altShort = ck:match("^(.-)%-") or ck
                                    table.insert(youAlts, {
                                        name   = L["You"] .. " (" .. altShort .. ")",
                                        online = true,
                                        isYou  = true,
                                    })
                                end
                            else
                                local shortName   = ck:match("^(.-)%-") or ck
                                local online      = GuildCache and GuildCache:IsPlayerOnline(ck) or false
                                local displayName = shortName
                                if not online and gdb.altGroups and gdb.altGroups[ck] then
                                    for _, altCk in ipairs(gdb.altGroups[ck]) do
                                        if altCk ~= ck and GuildCache and GuildCache:IsPlayerOnline(altCk) then
                                            local altShort = altCk:match("^(.-)%-") or altCk
                                            displayName = altShort .. " (" .. shortName .. ")"
                                            online = true
                                            break
                                        end
                                    end
                                end
                                table.insert(crafterObjs, { name = displayName, online = online })
                            end
                        end
                        table.sort(crafterObjs, function(a, b)
                            if a.online ~= b.online then return a.online end
                            return a.name < b.name
                        end)
                        -- Insert You entries at the front: own alts (sorted by alt name)
                        -- first, then logged-in self at position 1 so it stays on top.
                        table.sort(youAlts, function(a, b) return a.name < b.name end)
                        for i = #youAlts, 1, -1 do
                            table.insert(crafterObjs, 1, youAlts[i])
                        end
                        if youSelf then
                            table.insert(crafterObjs, 1, youSelf)
                        end
                        table.insert(list, {
                            id         = recipeId,
                            name       = name,
                            profName   = profName,
                            profIconId = profIconId,
                            icon       = rd.icon or 134400,
                            isSpell    = rd.isSpell,
                            spellId    = rd.spellId,
                            recipeLink = rd.recipeLink,
                            itemLink   = rd.itemLink,
                            reagents   = rd.reagents,
                            crafters   = crafterObjs,
                        })
                    end
                end
            end
        end
    end

    if profId == 0 then
        for pid, profRecipes in pairs(gdb.recipes) do
            processProf(pid, profRecipes)
        end
    else
        processProf(profId, gdb.recipes[profId])
    end

    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function BrowserTab:Draw(container)
    self._container = container
    container:SetLayout("List")

    -- Clean up a raw headerBar left over from a previous Draw() or tab switch.
    if self._headerBar then
        self._headerBar:Hide()
        self._headerBar:SetParent(UIParent)
        self._headerBar = nil
    end

    self._slSection = nil
    local slData = Ace.db.char.shoppingList
    local hasSL  = false
    for _ in pairs(slData) do hasSL = true; break end
    local slCount = 0
    if hasSL then
        for _ in pairs(slData) do slCount = slCount + 1 end
    end

    -- ---- Toolbar -----------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    local profEntries = GetProfDropdownEntries()
    local profList    = {}
    local profOrder   = {}
    for _, p in ipairs(profEntries) do
        profList[p.profId]  = p.name
        table.insert(profOrder, p.profId)
    end

    if Ace.db.profile.persistProfFilter and self._selectedProfId == 0 then
        local saved = Ace.db.profile.savedProfFilter or 0
        if saved ~= 0 and profList[saved] then
            self._selectedProfId = saved
        end
    end

    local profDD = AceGUI:Create("Dropdown")
    profDD:SetLabel("|c" .. (addon.BrandColor or "ffFF8000") .. L["PanelProfessions"] .. "|r")
    profDD:SetWidth(180)
    profDD:SetList(profList, profOrder)
    profDD:SetValue(self._selectedProfId or 0)
    profDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._selectedProfId = value
        if Ace.db.profile.persistProfFilter then
            Ace.db.profile.savedProfFilter = value
        end
        self:RefreshList()
    end)
    profDD.frame:SetScript("OnEnter", function(f)
        addon.Tooltip.Owner(f)
        GameTooltip:SetText("Profession Filter", 1, 1, 1)
        GameTooltip:AddLine("Filter the recipe list to a single profession, or show all.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    profDD.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toolbar:AddChild(profDD)

    local sp = AceGUI:Create("Label")
    sp:SetWidth(8)
    toolbar:AddChild(sp)

    local search = AceGUI:Create("EditBox")
    search:SetLabel("|c" .. (addon.BrandColor or "ffFF8000") .. L["SearchPlaceholder"] .. "|r")
    search:SetWidth(220)
    search:SetText(self._searchText)
    search:SetCallback("OnTextChanged", function(_w, _e, text)
        self._searchText = text
        self:RefreshList()
    end)
    search.frame:SetScript("OnEnter", function(f)
        addon.Tooltip.Owner(f)
        GameTooltip:SetText("Search Recipes", 1, 1, 1)
        GameTooltip:AddLine("Type to filter recipes by name.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    search.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toolbar:AddChild(search)

    local sp2 = AceGUI:Create("Label")
    sp2:SetWidth(8)
    toolbar:AddChild(sp2)

    local viewDD = AceGUI:Create("Dropdown")
    viewDD:SetLabel("")
    viewDD:SetWidth(130)
    viewDD:SetList({ guild = L["ViewGuild"], mine = L["ViewMine"] })
    viewDD:SetValue(self._viewMode)
    viewDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._viewMode       = value
        self._selectedProfId = 0
        self._selectedEntry  = nil
        C_Timer.After(0, function()
            if self._container then
                self._container:ReleaseChildren()
                self:Draw(self._container)
            end
        end)
    end)
    toolbar:AddChild(viewDD)

    -- ---- Shopping list (below toolbar) -------------------------------------
    if hasSL then
        local slSection = AceGUI:Create("InlineGroup")
        slSection:SetTitle("")
        slSection:SetLayout("List")
        slSection:SetFullWidth(true)
        slSection.noAutoHeight = true
        slSection:SetHeight(slCount * ROW_HEIGHT + 40)
        container:AddChild(slSection)
        self._slSection = slSection
        self:FillShoppingListSection(slSection)
    end

    -- ---- Column headers (raw frame) ----------------------------------------
    local anchorFrame = (self._slSection and self._slSection.frame) or toolbar.frame
    local headerBar   = CreateFrame("Frame", nil, container.content)
    headerBar:SetHeight(18)
    headerBar:SetPoint("TOPLEFT",  anchorFrame, "BOTTOMLEFT",  0, 0)
    headerBar:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    self._headerBar = headerBar

    local recipeHdr = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipeHdr:ClearAllPoints()
    recipeHdr:SetPoint("LEFT", headerBar, "LEFT", 24, 0)
    recipeHdr:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Recipes|r")

    local recipeHdrHit = CreateFrame("Frame", nil, headerBar)
    recipeHdrHit:SetPoint("LEFT",  recipeHdr, "LEFT",  -2, 0)
    recipeHdrHit:SetPoint("RIGHT", recipeHdr, "RIGHT",  2, 0)
    recipeHdrHit:SetHeight(18)
    recipeHdrHit:SetScript("OnEnter", function(f)
        addon.Tooltip.Owner(f)
        GameTooltip:SetText("Recipe", 1, 1, 1)
        GameTooltip:AddLine("The name of the craftable item or spell.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    recipeHdrHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local craftersHdr = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftersHdr:ClearAllPoints()
    craftersHdr:SetPoint("LEFT", headerBar, "LEFT", 186, 0)
    craftersHdr:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Crafters|r")

    local craftersHdrHit = CreateFrame("Frame", nil, headerBar)
    craftersHdrHit:SetPoint("LEFT",  craftersHdr, "LEFT",  -2, 0)
    craftersHdrHit:SetPoint("RIGHT", craftersHdr, "RIGHT",  2, 0)
    craftersHdrHit:SetHeight(18)
    craftersHdrHit:SetScript("OnEnter", function(f)
        addon.Tooltip.Owner(f)
        GameTooltip:SetText("Crafters", 1, 1, 1)
        GameTooltip:AddLine("Guild members who know this recipe. Click a recipe for the full list.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    craftersHdrHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ---- Recipe scroll list (left column) ----------------------------------
    if self._pool then
        self:DestroyPool()
    end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetCallback("OnRelease", function()
        self:DestroyPool()
        if self._headerBar then
            self._headerBar:Hide()
            self._headerBar:SetParent(UIParent)
            self._headerBar = nil
        end
        -- Detach the persistent detail panel from container.content
        if self._detailOuter then
            self._detailOuter:Hide()
            self._detailOuter:SetParent(UIParent)
        end
    end)
    container:AddChild(scroll)
    self._scroll = scroll

    -- ---- Detail panel (right column, persistent) ---------------------------
    self:EnsureDetailPanel(container.content)
    local rp = self._detailOuter
    rp:SetParent(container.content)
    rp:SetWidth(DP_W)
    rp:ClearAllPoints()
    rp:SetPoint("TOPRIGHT",    headerBar, "BOTTOMRIGHT",         0, 0)
    rp:SetPoint("BOTTOMRIGHT", container.content, "BOTTOMRIGHT", 0, 0)
    rp:Show()

    if self._selectedEntry then
        self:DrawDetail(self._selectedEntry)
    else
        self:ClearDetail()
    end

    -- Anchor scroll frame to fill the left column (right edge = detail panel left - gap).
    local function AnchorScrollToFill()
        if not (self._scroll and self._scroll.frame) then return end
        if not self._detailOuter then return end
        self._scroll.frame:ClearAllPoints()
        self._scroll.frame:SetPoint("TOPLEFT",     headerBar, "BOTTOMLEFT",  0, 0)
        self._scroll.frame:SetPoint("BOTTOMRIGHT", self._detailOuter, "BOTTOMLEFT", -DP_GAP, 0)
    end
    container.LayoutFinished = function() AnchorScrollToFill() end
    AnchorScrollToFill()

    self:FillList()
end

-- ---------------------------------------------------------------------------
-- Shopping list helpers
-- ---------------------------------------------------------------------------

function BrowserTab:FillShoppingListSection(container)
    local bl = Ace.db.char.shoppingList

    local parent = container.content or container.frame

    if not self._slPool        then self._slPool        = {} end
    if not self._slReagentPool then self._slReagentPool = {} end
    if not self._slExpanded    then self._slExpanded    = {} end

    local rows = {}
    for sid, entry in pairs(bl) do
        table.insert(rows, { sid = sid, entry = entry })
    end
    table.sort(rows, function(a, b)
        local na = (a.entry and a.entry.name) or tostring(a.sid)
        local nb = (b.entry and b.entry.name) or tostring(b.sid)
        return na < nb
    end)

    for _, f in ipairs(self._slPool)        do f:SetParent(parent) end
    for _, f in ipairs(self._slReagentPool) do f:SetParent(parent) end

    local function GetRecipeFrame(idx)
        if self._slPool[idx] then return self._slPool[idx] end

        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrow:SetPoint("LEFT", f, "LEFT", 2, 0)
        arrow:SetWidth(12)
        arrow:SetJustifyH("CENTER")
        f.arrow = arrow

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", 16, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(210)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        local removeBtn = CreateFrame("Button", nil, f)
        removeBtn:SetSize(12, 18)
        removeBtn:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        local removeLbl = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        removeLbl:SetAllPoints()
        removeLbl:SetJustifyH("CENTER")
        removeLbl:SetText("|cFFFF4444x|r")
        f.removeBtn = removeBtn

        local plusBtn = CreateFrame("Button", nil, f)
        plusBtn:SetSize(12, 18)
        plusBtn:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
        local plusLbl = plusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        plusLbl:SetAllPoints()
        plusLbl:SetJustifyH("CENTER")
        plusLbl:SetText("|cFFFFD100+|r")
        f.plusBtn = plusBtn

        local qtyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qtyLbl:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)
        qtyLbl:SetWidth(22)
        qtyLbl:SetJustifyH("CENTER")
        f.qtyLbl = qtyLbl

        local minusBtn = CreateFrame("Button", nil, f)
        minusBtn:SetSize(12, 18)
        minusBtn:SetPoint("RIGHT", qtyLbl, "LEFT", -4, 0)
        local minusLbl = minusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        minusLbl:SetAllPoints()
        minusLbl:SetJustifyH("CENTER")
        minusLbl:SetText("|cFFFFD100-|r")
        f.minusBtn = minusBtn

        local alertBtn = CreateFrame("Button", nil, f)
        alertBtn:SetSize(12, 18)
        alertBtn:SetPoint("RIGHT", minusBtn, "LEFT", -4, 0)
        local alertLbl = alertBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        alertLbl:SetAllPoints()
        alertLbl:SetJustifyH("CENTER")
        alertLbl:SetText("|cff666666!|r")
        alertBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(alertBtn)
            local enabled = alertBtn._sid and Ace.db.char.shoppingAlerts[alertBtn._sid]
            GameTooltip:SetText(enabled and L["ShoppingAlertDisable"] or L["ShoppingAlertEnable"], 1, 1, 1)
            GameTooltip:Show()
        end)
        alertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.alertBtn  = alertBtn
        f.alertLbl  = alertLbl

        self._slPool[idx] = f
        return f
    end

    local INDENT = 18
    local function GetReagentFrame(idx)
        if self._slReagentPool[idx] then return self._slReagentPool[idx] end

        local f = CreateFrame("Frame", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:EnableMouse(true)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("LEFT", f, "LEFT", INDENT + 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(200)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        nameLbl:SetTextColor(1, 1, 1)
        f.nameLbl = nameLbl

        local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countLbl:SetPoint("LEFT", nameLbl, "RIGHT", 4, 0)
        countLbl:SetWidth(44)
        countLbl:SetJustifyH("RIGHT")
        countLbl:SetTextColor(1, 1, 1)
        f.countLbl = countLbl

        local bankBtn = CreateFrame("Button", nil, f)
        bankBtn:SetSize(52, 14)
        bankBtn:SetPoint("LEFT", countLbl, "RIGHT", 4, 0)
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

        self._slReagentPool[idx] = f
        return f
    end

    for _, f in ipairs(self._slPool)        do f:Hide() end
    for _, f in ipairs(self._slReagentPool) do f:Hide() end

    local yOffset    = 0
    local reagentIdx = 0

    for recipeIdx, rowData in ipairs(rows) do
        local sid      = rowData.sid
        local ent      = rowData.entry
        local qty      = (ent and ent.quantity) or 1
        local name     = (ent and ent.name) or tostring(sid)
        local reagents = (ent and ent.reagents) or {}
        local hasReagents = #reagents > 0
        local expanded = self._slExpanded[sid]

        local f = GetRecipeFrame(recipeIdx)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -yOffset)
        f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
        yOffset = yOffset + ROW_HEIGHT

        if hasReagents then
            f.arrow:SetText(expanded and "|cFFFFD100-|r" or "|cFFFFD100+|r")
        else
            f.arrow:SetText("")
        end

        if ent and ent.icon then
            f.icon:SetTexture(ent.icon)
        else
            f.icon:SetTexture(nil)
        end

        local colorHex = ent and type(ent.itemLink) == "string" and ent.itemLink:match("|c(ff%x%x%x%x%x%x)|H")
        f.nameLbl:SetText(colorHex and ("|c" .. colorHex .. name .. "|r") or name)
        f.qtyLbl:SetText(tostring(qty))

        -- Alert toggle button state
        f.alertBtn._sid = sid
        local alertOn = Ace.db.char.shoppingAlerts[sid]
        f.alertLbl:SetText(alertOn and "|cffFFD700!|r" or "|cff666666!|r")
        f.alertBtn:SetScript("OnClick", function()
            if Ace.db.char.shoppingAlerts[sid] then
                Ace.db.char.shoppingAlerts[sid] = nil
            else
                Ace.db.char.shoppingAlerts[sid] = true
            end
            f.alertLbl:SetText(Ace.db.char.shoppingAlerts[sid] and "|cffFFD700!|r" or "|cff666666!|r")
        end)

        f:SetScript("OnClick", function(btn)
            if f.minusBtn:IsMouseOver() or f.plusBtn:IsMouseOver() or f.removeBtn:IsMouseOver()
            or f.alertBtn:IsMouseOver() then
                return
            end
            if hasReagents then
                self._slExpanded[sid] = not self._slExpanded[sid]
                self:RefreshShoppingList()
            end
        end)

        f.minusBtn:SetScript("OnClick", function()
            local cur = (bl[sid] and bl[sid].quantity) or 1
            if cur <= 1 then
                bl[sid] = nil
                self._slExpanded[sid] = nil
            else
                bl[sid].quantity = cur - 1
            end
            -- Sync detail panel if this recipe is currently selected
            if self._selectedEntry and self._selectedEntry.id == sid then
                self:DrawDetail(self._selectedEntry)
            end
            self:RefreshShoppingList()
        end)
        f.plusBtn:SetScript("OnClick", function()
            if bl[sid] then
                bl[sid].quantity = (bl[sid].quantity or 1) + 1
                if ent then
                    bl[sid].name     = ent.name     or bl[sid].name
                    bl[sid].icon     = ent.icon     or bl[sid].icon
                    bl[sid].itemLink = ent.itemLink or bl[sid].itemLink
                    bl[sid].reagents = ent.reagents or bl[sid].reagents
                end
            else
                bl[sid] = { name = name, quantity = 1,
                            icon = ent and ent.icon, itemLink = ent and ent.itemLink,
                            reagents = ent and ent.reagents }
            end
            if self._selectedEntry and self._selectedEntry.id == sid then
                self:DrawDetail(self._selectedEntry)
            end
            self:RefreshShoppingList()
        end)
        f.removeBtn:SetScript("OnClick", function()
            bl[sid] = nil
            self._slExpanded[sid] = nil
            Ace.db.char.shoppingAlerts[sid] = nil
            if self._selectedEntry and self._selectedEntry.id == sid then
                self:DrawDetail(self._selectedEntry)
            end
            self:RefreshShoppingList()
        end)

        f:SetScript("OnEnter", function()
            local link = ent and (ent.itemLink or ent.recipeLink)
            if link then
                addon.Tooltip.Owner(f)
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:Show()

        if expanded and hasReagents then
            for _, r in ipairs(reagents) do
                reagentIdx = reagentIdx + 1
                local rf = GetReagentFrame(reagentIdx)
                rf:ClearAllPoints()
                rf:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -yOffset)
                rf:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
                yOffset = yOffset + ROW_HEIGHT

                if r.itemId and r.itemId > 0 then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(r.itemId)
                    rf.icon:SetTexture(itemTexture or nil)
                else
                    rf.icon:SetTexture(nil)
                end

                rf.nameLbl:SetText(r.name or "")

                local rItemId   = ResolveReagentItemId(r)
                local rItemLink = ResolveReagentItemLink(r)
                rf:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(rf)
                    if rItemLink then
                        GameTooltip:SetHyperlink(rItemLink)
                        GameTooltip:Show()
                    elseif rItemId and GameTooltip.SetItemByID then
                        GameTooltip:SetItemByID(rItemId)
                        GameTooltip:Show()
                    end
                end)
                rf:SetScript("OnLeave", function() GameTooltip:Hide() end)

                local needed = (r.count or 1) * qty
                rf.countLbl:SetText("|cffffffff x" .. needed .. "|r")

                if rItemId and addon.Bank and addon.Bank.GetStock(rItemId) > 0 then
                    rf.bankBtn:SetScript("OnClick", function()
                        addon.Bank.ShowRequestDialog(rItemId, r.name or "", rItemLink)
                    end)
                    rf.bankBtn:Show()
                else
                    rf.bankBtn:Hide()
                end

                rf:Show()
            end
        end
    end

    local totalH = math.max(yOffset, ROW_HEIGHT)
    container:SetHeight(totalH + 40)
end

function BrowserTab:RefreshShoppingList()
    if not self._container then return end
    if addon.ReagentTracker then addon.ReagentTracker:QueueRefresh() end

    if self._slSection then
        local bl    = Ace.db.char.shoppingList
        local hasSL = false
        for _ in pairs(bl) do hasSL = true; break end

        if hasSL then
            self:FillShoppingListSection(self._slSection)
            if self._container then self._container:DoLayout() end
        else
            self._slSection.frame:Hide()
            self._slSection = nil
            C_Timer.After(0, function()
                if self._container then
                    self._container:ReleaseChildren()
                    self:Draw(self._container)
                end
            end)
        end
    else
        C_Timer.After(0, function()
            if self._container then
                self._container:ReleaseChildren()
                self:Draw(self._container)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Recipe list helpers
-- ---------------------------------------------------------------------------

function BrowserTab:RefreshList()
    local scroll = self._scroll
    if not scroll then return end
    if self._pool then
        for _, f in ipairs(self._pool) do f:Hide() end
    end
    self._recipes = nil
    scroll:ReleaseChildren()
    self:FillList()
end

function BrowserTab:FillList()
    local scroll = self._scroll
    if not scroll then return end

    scroll.LayoutFinished = nil

    if self._selectedProfId == nil then
        local hint = AceGUI:Create("Label")
        hint:SetText(L["SelectProfHint"])
        hint:SetFullWidth(true)
        scroll:AddChild(hint)
        return
    end

    local recipes = BuildRecipeList(self._selectedProfId, self._viewMode, self._searchText)
    if #recipes == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(self._searchText ~= "" and L["NoMatchingRecipes"] or L["NoDataYet"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    self._recipes = recipes

    scroll.LayoutFinished = function() end
    scroll.content:SetHeight(#recipes * ROW_HEIGHT)
    scroll:FixScroll()

    if not self._pool then
        self:BuildPool(scroll.content)
    end

    self:UpdateVirtualRows()

    scroll.scrollbar:SetScript("OnValueChanged", function(bar, value)
        bar.obj:SetScroll(value)
        self:UpdateVirtualRows()
    end)

    -- If TOGBankClassic is loaded but not yet initialized (Info is nil on first
    -- login before GUILD_RANKS_UPDATE fires), watch for it and refresh bank buttons.
    if _G["TOGBankClassic_Guild"] and not _G["TOGBankClassic_Guild"].Info
       and not self._bankRefreshPending then
        self._bankRefreshPending = true
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("GUILD_RANKS_UPDATE")
        watcher:SetScript("OnEvent", function(f)
            f:UnregisterEvent("GUILD_RANKS_UPDATE")
            f:SetScript("OnEvent", nil)
            C_Timer.After(0.5, function()
                self._bankRefreshPending = nil
                if self._pool then self:UpdateVirtualRows() end
                -- Bank buttons live in the detail panel; redraw it too.
                if self._selectedEntry then self:DrawDetail(self._selectedEntry) end
                -- Refresh shopping list bank buttons as well.
                if self._slSection then self:FillShoppingListSection(self._slSection) end
            end)
        end)
    end
end

-- Build POOL_SIZE raw WoW frames parented to the scroll content frame.
function BrowserTab:BuildPool(parent)
    self._pool = {}
    for i = 1, POOL_SIZE do
        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:Hide()
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        -- Name column
        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(160)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        -- Crafter column: truncated summary; narrowed to leave room for bank button
        local crafterLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        crafterLbl:SetPoint("LEFT",  f, "LEFT",  186, 0)
        crafterLbl:SetPoint("RIGHT", f, "RIGHT",  -56, 0)
        crafterLbl:SetJustifyH("LEFT")
        crafterLbl:SetWordWrap(false)
        f.crafterLbl = crafterLbl

        -- Bank button at far right
        local bankBtn = CreateFrame("Button", nil, f)
        bankBtn:SetSize(50, 12)
        bankBtn:SetPoint("RIGHT", f, "RIGHT", -2, 0)
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

        f:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local entry = f._entry
            if not entry then return end
            self:DrawDetail(entry)
        end)

        f:SetScript("OnEnter", function()
            local entry = f._entry
            if not entry then return end
            addon.Tooltip.Owner(f)
            -- Only use recipeLink if it is a real item link; enchanting stores
            -- enchant:SPELLID here which produces an unhelpful tooltip.
            if entry.recipeLink and entry.recipeLink:find("|Hitem:") then
                GameTooltip:SetHyperlink(entry.recipeLink)
            elseif entry.reagents and #entry.reagents > 0 then
                local parts = {}
                for _, r in ipairs(entry.reagents) do
                    table.insert(parts, r.name .. " (" .. r.count .. ")")
                end
                local reagentLine = (SPELL_REAGENTS or "Reagents:") .. " " .. table.concat(parts, ", ")
                local header = (entry.profName and entry.profName ~= "")
                    and (entry.profName .. ": " .. entry.name) or entry.name
                GameTooltip:ClearLines()
                GameTooltip:AddLine("|cffffff00" .. header .. "|r")
                GameTooltip:AddLine(reagentLine, 1, 1, 1, true)
                -- Only scrape crafted-item tooltip for real item links (not enchant:).
                if type(entry.itemLink) == "string" and entry.itemLink:find("|Hitem:") then
                    local scraper = GetItemScraper()
                    scraper:ClearLines()
                    scraper:SetHyperlink(entry.itemLink)
                    local n = scraper:NumLines()
                    if n > 1 then
                        GameTooltip:AddLine(" ")
                        for li = 1, n do
                            local lt = _G["TOGPMItemScraperTextLeft"  .. li]
                            local rt = _G["TOGPMItemScraperTextRight" .. li]
                            local lStr = (lt and lt:GetText()) or ""
                            local rStr = (rt and rt:GetText()) or ""
                            if lStr ~= "" or rStr ~= "" then
                                local lr, lg, lb = 1, 1, 1
                                local rr, rg, rb = 1, 1, 1
                                if lt then lr, lg, lb = lt:GetTextColor() end
                                if rt then rr, rg, rb = rt:GetTextColor() end
                                if rStr ~= "" then
                                    GameTooltip:AddDoubleLine(lStr, rStr, lr, lg, lb, rr, rg, rb)
                                else
                                    GameTooltip:AddLine(lStr, lr, lg, lb)
                                end
                            end
                        end
                    end
                end
                if not entry.isSpell then
                    addon.Tooltip.AppendCrafters(GameTooltip, entry.id)
                end
                GameTooltip:Show()
                return
            elseif type(entry.itemLink) == "string" and entry.itemLink:find("|Hitem:") then
                GameTooltip:SetHyperlink(entry.itemLink)
            elseif entry.spellId then
                GameTooltip:SetSpellByID(entry.spellId)
            elseif entry.isSpell then
                GameTooltip:SetSpellByID(entry.id)
            else
                GameTooltip:SetHyperlink("item:" .. entry.id)
            end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self._pool[i] = f
    end
end

function BrowserTab:DestroyPool()
    if self._pool then
        for _, f in ipairs(self._pool) do
            f:Hide()
            f:SetParent(UIParent)
            f:SetScript("OnMouseDown", nil)
            f:SetScript("OnEnter",     nil)
            f:SetScript("OnLeave",     nil)
        end
        self._pool    = nil
        self._recipes = nil
    end
    self._scroll             = nil
    self._bankRefreshPending = nil
end

-- ---------------------------------------------------------------------------
-- Detail panel (right column)
-- ---------------------------------------------------------------------------

-- Lazily create all detail-panel sub-frames the first time; subsequent Draw()
-- calls just re-parent the outer frame to the new container.content.
function BrowserTab:EnsureDetailPanel(parent)
    if self._detailOuter then return end

    local rp = CreateFrame("Frame", nil, parent)
    rp:SetWidth(DP_W)
    self._detailOuter = rp

    -- Subtle backdrop to visually separate the panel from the list.
    if rp.SetBackdrop then
        rp:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, tileSize = 1, edgeSize = 8,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        rp:SetBackdropColor(0, 0, 0, 0.22)
        rp:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end

    -- Placeholder text shown when no recipe is selected.
    local ph = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ph:SetPoint("CENTER", rp, "CENTER", 0, 0)
    ph:SetText("|cffaaaaaa>> Select a recipe|r")
    ph:SetJustifyH("CENTER")
    self._dpPH = ph

    -- Native WoW ScrollFrame for the detail content.
    local sf = CreateFrame("ScrollFrame", nil, rp)
    sf:SetPoint("TOPLEFT",     rp, "TOPLEFT",     DP_PAD, -DP_PAD)
    sf:SetPoint("BOTTOMRIGHT", rp, "BOTTOMRIGHT", -(DP_PAD + 16), DP_PAD)
    sf:Hide()
    self._dpSF = sf

    local cw = DP_W - DP_PAD * 2 - 18
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(cw)
    content:SetHeight(10)
    sf:SetScrollChild(content)
    self._dpContent = content

    -- Scrollbar (sits in the right margin of the outer panel).
    local sb = CreateFrame("Slider", nil, rp, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT",    2, -16)
    sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2,  16)
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(8)
    if sb.SetObeyStepOnDrag then sb:SetObeyStepOnDrag(true) end
    sf:SetScript("OnScrollRangeChanged", function(_, _, yr)
        local m = math.max(0, yr or 0)
        sb:SetMinMaxValues(0, m)
        if m > 0 then sb:Show() else sb:Hide() end
    end)
    sf:SetScript("OnMouseWheel", function(_, delta)
        sb:SetValue(sb:GetValue() - delta * 20)
    end)
    sb:SetScript("OnValueChanged", function(_, val)
        sf:SetVerticalScroll(val)
    end)
    self._dpSB = sb

    -- ── Persistent header widgets ──────────────────────────────────────────

    -- Button wrapper so the icon+name row can show an item tooltip and
    -- accept shift-click to insert the item link into chat.
    local hdrBtn = CreateFrame("Button", nil, content)
    hdrBtn:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, 0)
    hdrBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    hdrBtn:SetHeight(DP_ICON)
    hdrBtn:RegisterForClicks("AnyUp")
    self._dpHdrBtn = hdrBtn

    local dpIcon = hdrBtn:CreateTexture(nil, "ARTWORK")
    dpIcon:SetSize(DP_ICON, DP_ICON)
    dpIcon:SetPoint("TOPLEFT", hdrBtn, "TOPLEFT", 0, 0)
    dpIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    self._dpIcon = dpIcon

    local dpName = hdrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dpName:SetPoint("TOPLEFT",  dpIcon, "TOPRIGHT", 4, -2)
    dpName:SetPoint("TOPRIGHT", hdrBtn, "TOPRIGHT", 0, -2)
    dpName:SetWordWrap(true)
    dpName:SetJustifyH("LEFT")
    self._dpName = dpName

    -- Shopping list row (below the icon/name block)
    local shopRow = CreateFrame("Frame", nil, content)
    shopRow:SetHeight(DP_ROW)
    shopRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(DP_ICON + 4))
    shopRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(DP_ICON + 4))
    self._dpShopRow = shopRow

    local shopLbl = shopRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shopLbl:SetPoint("LEFT", shopRow, "LEFT", 0, 0)
    shopLbl:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Shopping List:|r")

    -- Controls right-justified: [x] at right edge, then [+] [qty] [-] leftward
    local dpRemove = CreateFrame("Button", nil, shopRow)
    dpRemove:SetSize(14, 14)
    dpRemove:SetPoint("RIGHT", shopRow, "RIGHT", 0, 0)
    local dpRemoveT = dpRemove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpRemoveT:SetAllPoints(); dpRemoveT:SetJustifyH("CENTER"); dpRemoveT:SetText("|cFFFF4444x|r")
    self._dpRemove = dpRemove

    local dpPlus = CreateFrame("Button", nil, shopRow)
    dpPlus:SetSize(14, 14)
    dpPlus:SetPoint("RIGHT", dpRemove, "LEFT", -4, 0)
    local dpPlusT = dpPlus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpPlusT:SetAllPoints(); dpPlusT:SetJustifyH("CENTER"); dpPlusT:SetText("|cFFFFD100+|r")
    self._dpPlus = dpPlus

    local dpQty = shopRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpQty:SetPoint("RIGHT", dpPlus, "LEFT", -4, 0)
    dpQty:SetWidth(20)
    dpQty:SetJustifyH("CENTER")
    self._dpQty = dpQty

    local dpMinus = CreateFrame("Button", nil, shopRow)
    dpMinus:SetSize(14, 14)
    dpMinus:SetPoint("RIGHT", dpQty, "LEFT", -4, 0)
    local dpMinusT = dpMinus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpMinusT:SetAllPoints(); dpMinusT:SetJustifyH("CENTER"); dpMinusT:SetText("|cFFFFD100-|r")
    self._dpMinus = dpMinus

    -- Dynamic-position headings (repositioned each DrawDetail call)
    local dpReagHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpReagHdr:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Reagents|r")
    self._dpReagHdr = dpReagHdr

    local dpCraftHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpCraftHdr:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Known By|r")
    self._dpCraftHdr = dpCraftHdr

    -- Pools for reagent and crafter rows (grow as needed, never shrink)
    self._dpReagPool  = {}
    self._dpCraftPool = {}
end

-- Get-or-create a reagent row frame inside the detail content.
function BrowserTab:GetDetailReagRow(idx)
    if self._dpReagPool[idx] then return self._dpReagPool[idx] end

    local content = self._dpContent
    local f = CreateFrame("Button", nil, content)
    f:SetHeight(DP_ROW)
    f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameLbl:SetWidth(120)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetWordWrap(false)
    f.nameLbl = nameLbl

    local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLbl:SetPoint("LEFT", nameLbl, "RIGHT", 4, 0)
    countLbl:SetWidth(36)
    countLbl:SetJustifyH("RIGHT")
    f.countLbl = countLbl

    local bankBtn = CreateFrame("Button", nil, f)
    bankBtn:SetSize(46, 12)
    bankBtn:SetPoint("LEFT", countLbl, "RIGHT", 4, 0)
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

    self._dpReagPool[idx] = f
    return f
end

-- Get-or-create a crafter row frame inside the detail content.
function BrowserTab:GetDetailCraftRow(idx)
    if self._dpCraftPool[idx] then return self._dpCraftPool[idx] end

    local content = self._dpContent
    local f = CreateFrame("Button", nil, content)
    f:SetHeight(DP_ROW)
    f:RegisterForClicks("AnyUp")  -- enables right-click for whisper
    f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT",  f, "LEFT",  0, 0)
    lbl:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    f.lbl = lbl

    self._dpCraftPool[idx] = f
    return f
end

-- Populate the detail panel for the given recipe entry.
function BrowserTab:DrawDetail(entry)
    self:EnsureDetailPanel(
        self._container and self._container.content or UIParent)
    self._selectedEntry = entry

    local content = self._dpContent

    self._dpPH:Hide()
    self._dpSF:Show()
    self._dpSB:SetValue(0)
    self._dpSF:SetVerticalScroll(0)

    -- Header: icon + name
    self._dpIcon:SetTexture(entry.icon)
    local titleColor = type(entry.itemLink) == "string" and entry.itemLink:match("|c(ff%x%x%x%x%x%x)|H") or "ffffd100"
    self._dpName:SetText("|c" .. titleColor .. entry.name .. "|r")

    -- Tooltip + shift-click to insert link on the header button
    local nameLink = (type(entry.itemLink)   == "string" and entry.itemLink:find("|Hitem:")   and entry.itemLink)
                 or (type(entry.recipeLink) == "string" and entry.recipeLink:find("|Hitem:") and entry.recipeLink)
    if nameLink then
        self._dpHdrBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(self._dpHdrBtn)
            GameTooltip:SetHyperlink(nameLink)
            GameTooltip:Show()
        end)
        self._dpHdrBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self._dpHdrBtn:SetScript("OnClick", function(_, btn)
            if btn == "LeftButton" and IsShiftKeyDown() then
                ChatEdit_InsertLink(nameLink)
            end
        end)
    else
        self._dpHdrBtn:SetScript("OnEnter", nil)
        self._dpHdrBtn:SetScript("OnLeave", nil)
        self._dpHdrBtn:SetScript("OnClick", nil)
    end

    -- Shopping list qty display and controls
    local function RefreshQty()
        local qty = (Ace.db.char.shoppingList[entry.id]
                    and Ace.db.char.shoppingList[entry.id].quantity) or 0
        self._dpQty:SetText(tostring(qty))
        -- Also refresh reagent counts if panel is showing this entry
        if self._selectedEntry and self._selectedEntry.id == entry.id then
            for ri, r in ipairs(entry.reagents or {}) do
                local rf = self._dpReagPool[ri]
                if rf and rf:IsShown() then
                    local mult = math.max(1, qty)
                    rf.countLbl:SetText("|cffffffff\195\151" .. (r.count or 1) * mult .. "|r")
                end
            end
        end
    end
    RefreshQty()

    self._dpMinus:SetScript("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity = sl[entry.id].quantity - 1
            if sl[entry.id].quantity <= 0 then sl[entry.id] = nil end
        end
        RefreshQty()
        self:RefreshShoppingList()
    end)
    self._dpPlus:SetScript("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity    = sl[entry.id].quantity + 1
            sl[entry.id].name        = entry.name
            sl[entry.id].icon        = entry.icon
            sl[entry.id].itemLink    = entry.itemLink
            sl[entry.id].reagents    = entry.reagents
        else
            sl[entry.id] = { name = entry.name, quantity = 1,
                             icon = entry.icon, itemLink = entry.itemLink,
                             reagents = entry.reagents }
        end
        RefreshQty()
        self:RefreshShoppingList()
    end)
    self._dpRemove:SetScript("OnClick", function()
        Ace.db.char.shoppingList[entry.id] = nil
        RefreshQty()
        self:RefreshShoppingList()
    end)

    -- Running y-offset (negative = downward from content top)
    local yOff = -(DP_ICON + 4 + DP_ROW + 4)

    -- ── Reagents ──────────────────────────────────────────────────────────
    local reagents    = entry.reagents or {}
    local hasReagents = #reagents > 0

    if hasReagents then
        self._dpReagHdr:ClearAllPoints()
        self._dpReagHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        self._dpReagHdr:Show()
        yOff = yOff - DP_ROW

        local slQty = (Ace.db.char.shoppingList[entry.id]
                      and Ace.db.char.shoppingList[entry.id].quantity) or 0
        local mult  = math.max(1, slQty)

        for i, r in ipairs(reagents) do
            local rf = self:GetDetailReagRow(i)
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
            rf:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
            yOff = yOff - DP_ROW

            local rItemId = ResolveReagentItemId(r)
            local rLink   = ResolveReagentItemLink(r)
            if rItemId and rItemId > 0 then
                local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(rItemId)
                rf.icon:SetTexture(tex or nil)
            else
                rf.icon:SetTexture(nil)
            end
            rf.nameLbl:SetText(r.name or "")
            rf.countLbl:SetText("|cffffffff\195\151" .. (r.count or 1) * mult .. "|r")

            if rLink or rItemId then
                rf:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(rf)
                    if rLink then
                        GameTooltip:SetHyperlink(rLink)
                    elseif GameTooltip.SetItemByID then
                        GameTooltip:SetItemByID(rItemId)
                    else
                        return
                    end
                    GameTooltip:Show()
                end)
                rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
                rf:SetScript("OnClick", function(_, btn)
                    if btn == "LeftButton" and IsShiftKeyDown() and rLink then
                        ChatEdit_InsertLink(rLink)
                    end
                end)
            else
                rf:SetScript("OnEnter", nil)
                rf:SetScript("OnLeave", nil)
                rf:SetScript("OnClick", nil)
            end

            if rItemId and addon.Bank and addon.Bank.GetStock(rItemId) > 0 then
                rf.bankBtn:SetScript("OnClick", function()
                    addon.Bank.ShowRequestDialog(rItemId, r.name or "", rLink)
                end)
                rf.bankBtn:Show()
            else
                rf.bankBtn:Hide()
            end

            rf:Show()
        end
        for i = #reagents + 1, #self._dpReagPool do
            self._dpReagPool[i]:Hide()
        end
    else
        self._dpReagHdr:Hide()
        for _, f in ipairs(self._dpReagPool) do f:Hide() end
    end

    -- ── Known By ──────────────────────────────────────────────────────────
    yOff = yOff - 4
    self._dpCraftHdr:ClearAllPoints()
    self._dpCraftHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
    self._dpCraftHdr:Show()
    yOff = yOff - DP_ROW

    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
    local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
    local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF")

    for _, f in ipairs(self._dpCraftPool) do f:Hide() end

    local crafters = entry.crafters or {}

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

    if #crafters > 0 then
        for i, c in ipairs(crafters) do
            local cf = self:GetDetailCraftRow(i)
            cf:ClearAllPoints()
            cf:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
            cf:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
            yOff = yOff - DP_ROW

            local col = c.isYou and colorYou or (c.online and colorOnline or colorOffline)
            cf.lbl:SetText(col .. c.name .. "|r")

            if not c.isYou then
                local charKey   = c.charKey or c.name
                local shortName = c.name
                cf:SetScript("OnEnter", function()
                    addon.Tooltip.Owner(cf)
                    GameTooltip:SetText(shortName, 1, 1, 1)
                    GameTooltip:AddLine("Right-click to whisper", 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                cf:SetScript("OnLeave", function() GameTooltip:Hide() end)
                cf:SetScript("OnClick", function(_, btn)
                    if btn == "RightButton" then
                        if Menu and Menu.CreateContextMenu then
                            Menu.CreateContextMenu(cf, function(_, root)
                                root:CreateTitle(shortName)
                                root:CreateButton(shortName, function() openWhisper(charKey) end)
                            end)
                        else
                            openWhisper(charKey)
                        end
                    end
                end)
            else
                cf:SetScript("OnEnter", nil)
                cf:SetScript("OnLeave", nil)
                cf:SetScript("OnClick", nil)
            end
            cf:Show()
        end
        for i = #crafters + 1, #self._dpCraftPool do
            self._dpCraftPool[i]:Hide()
        end
    else
        local cf = self:GetDetailCraftRow(1)
        cf:ClearAllPoints()
        cf:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOff)
        cf:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        cf.lbl:SetText("|cffaaaaaa" .. L["NoDataYet"] .. "|r")
        cf:SetScript("OnEnter", nil)
        cf:SetScript("OnLeave", nil)
        cf:SetScript("OnClick", nil)
        cf:Show()
        yOff = yOff - DP_ROW
        for i = 2, #self._dpCraftPool do self._dpCraftPool[i]:Hide() end
    end

    -- Resize content to fit all rows so the scrollbar range is correct.
    content:SetHeight(math.abs(yOff) + DP_PAD)
end

-- Show the "select a recipe" placeholder.
function BrowserTab:ClearDetail()
    if not self._detailOuter then return end
    if self._dpSF  then self._dpSF:Hide() end
    if self._dpPH  then self._dpPH:Show() end
    self._selectedEntry = nil
end

-- ---------------------------------------------------------------------------
-- Virtual row update
-- ---------------------------------------------------------------------------

function BrowserTab:UpdateVirtualRows()
    local scroll   = self._scroll
    local recipes  = self._recipes
    if not scroll or not recipes or not self._pool then return end

    local status   = scroll.status or scroll.localstatus
    local offset   = status.offset or 0
    local firstIdx = math.floor(offset / ROW_HEIGHT)

    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
    local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
    local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF")

    for i = 1, POOL_SIZE do
        local f         = self._pool[i]
        local recipeIdx = firstIdx + i
        local entry     = recipes[recipeIdx]
        if entry then
            f._entry = entry
            f.icon:SetTexture(entry.icon)

            local colorHex = type(entry.itemLink) == "string" and entry.itemLink:match("|c(ff%x%x%x%x%x%x)|H")
            f.nameLbl:SetText(colorHex and ("|c" .. colorHex .. entry.name .. "|r") or entry.name)

            -- Truncated crafter summary: show up to 2 names + "+N more"
            local crafters = entry.crafters
            local total    = #crafters
            local MAX_SHOW = 2
            local parts    = {}
            for ci = 1, math.min(MAX_SHOW, total) do
                local c   = crafters[ci]
                local col = c.isYou and colorYou or (c.online and colorOnline or colorOffline)
                table.insert(parts, col .. c.name .. "|r")
            end
            local suffix = (total > MAX_SHOW)
                and (" |cffaaaaaa+" .. (total - MAX_SHOW) .. "|r") or ""
            f.crafterLbl:SetText(table.concat(parts, ", ") .. suffix)

            -- Bank button: show if the crafted item itself has bank stock
            local craftedId = not entry.isSpell and entry.id or nil
            if addon.Bank and craftedId and addon.Bank.GetStock(craftedId) > 0 then
                f.bankBtn:SetScript("OnClick", function()
                    addon.Bank.ShowRequestDialog(craftedId, entry.name or "", entry.itemLink)
                end)
                f.bankBtn:Show()
            else
                f.bankBtn:Hide()
            end

            -- Highlight selected recipe
            if self._selectedEntry and self._selectedEntry.id == entry.id then
                f:LockHighlight()
            else
                f:UnlockHighlight()
            end

            local y = -((recipeIdx - 1) * ROW_HEIGHT)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT",  scroll.content, "TOPLEFT",  0, y)
            f:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, y)
            f:Show()
        else
            f._entry = nil
            f:Hide()
        end
    end
end
