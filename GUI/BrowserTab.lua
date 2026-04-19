-- TOG Profession Master â€” Profession Browser Tab
-- Draws the "Professions" tab inside the main window.
--
-- Layout:
--   [Profession â–¼]  [Search .................]  [Guild â–¼]
--   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
--   â”‚ [icon] Recipe Name            Crafter1, Crafter2, Crafter3  [+] â”‚
--   â”‚ [icon] Recipe Name 2          Crafter1                      [+] â”‚
--   â”‚ ...                                                             â”‚
--   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
--
-- One row per unique recipe in the selected profession.  Every guild
-- member who knows that recipe is listed on the right side of the row.
-- Hover for the spell/item tooltip.  Left-click a row to open the
-- recipe detail popup where you can manage the shopping-list quantity.

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
local ROW_HEIGHT  = 14
local POOL_SIZE   = 35  -- enough rows to fill any window height

-- ---------------------------------------------------------------------------
-- TOGBankClassic integration helpers
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
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
BrowserTab._selectedProfId = 0        -- 0 = All Professions (default)
BrowserTab._searchText     = ""
BrowserTab._viewMode       = "guild"  -- "guild" | "mine"
BrowserTab._scroll         = nil      -- active ScrollFrame widget
BrowserTab._container      = nil      -- the tab container
BrowserTab._pool           = nil      -- raw-frame row pool
BrowserTab._recipes        = nil      -- current filtered recipe list
BrowserTab._popup          = nil      -- recipe detail AceGUI Frame (if open)
BrowserTab._slSection      = nil      -- shopping list InlineGroup (if visible)

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

local function GetGuildDb()
    return addon:GetGuildDb()
end

-- Static list of all Vanilla crafting professions, sorted A->Z.
-- Always shown in the dropdown regardless of whether guild data exists.
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

--- Returns AceGUI dropdown entries: "All Professions" (profId=0) first,
--- then every profession in ALL_PROFESSIONS order (A->Z).
local function GetProfDropdownEntries()
    local entries = { { profId = 0, name = L["AllProfessions"] } }
    for _, p in ipairs(ALL_PROFESSIONS) do
        table.insert(entries, p)
    end
    return entries
end

--- Build the recipe list for the selected profession/viewmode/filter.
-- profId == 0   -> all professions combined.
-- profId == nil -> returns {} (nothing selected yet).
-- Returns sorted array of { id, name, icon, isSpell, crafters = {shortName,...} }.
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
        local profIconId = addon.ProfessionIcons and addon.ProfessionIcons[thisProfId] or (addon.ProfessionIconFallback or 134400)
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
                        -- Check if any crafter in this recipe belongs to our account.
                        local isYou = false
                        for ck in pairs(rd.crafters) do
                            if addon:IsMyCharacter(ck) then
                                isYou = true
                                break
                            end
                        end
                        local DS     = addon.Scanner and addon.Scanner.DS
                        -- crafters: array of {name=shortName, online=bool}
                        local crafterObjs = {}
                        for ck in pairs(rd.crafters) do
                            if not addon:IsMyCharacter(ck) then
                                local shortName = ck:match("^(.-)%-") or ck
                                local online = DS and DS:IsPlayerOnline(ck) or false
                                local displayName = shortName
                                -- If the crafter is offline, check whether one of their alts
                                -- is online so we can show "OnlineAlt (CrafterName)".
                                if not online and gdb.altGroups and gdb.altGroups[ck] then
                                    for _, altCk in ipairs(gdb.altGroups[ck]) do
                                        if altCk ~= ck and DS and DS:IsPlayerOnline(altCk) then
                                            local altShort = altCk:match("^(.-)%-") or altCk
                                            displayName = altShort .. " (" .. shortName .. ")"
                                            online = true   -- reachable via alt
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
                        -- Insert self at front with distinct color
                        if isYou then
                            table.insert(crafterObjs, 1, { name = L["You"], online = true, isYou = true })
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

    -- ---- Shopping list and toolbar placed below (see after header bar) ----
    self._slSection = nil
    local slData = Ace.db.char.shoppingList
    local hasSL = false
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

    -- Profession dropdown — static list, always full A→Z + "All" at top.
    local profEntries = GetProfDropdownEntries()
    local profList    = {}
    local profOrder   = {}
    for _, p in ipairs(profEntries) do
        profList[p.profId]  = p.name
        table.insert(profOrder, p.profId)
    end

    -- Restore persisted filter on first draw (only while setting is on)
    if Ace.db.profile.persistProfFilter and self._selectedProfId == 0 then
        local saved = Ace.db.profile.savedProfFilter or 0
        -- Only restore if a valid entry exists in the list
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

    -- Spacer
    local sp = AceGUI:Create("Label")
    sp:SetWidth(8)
    toolbar:AddChild(sp)

    -- Search box
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

    -- Spacer
    local sp2 = AceGUI:Create("Label")
    sp2:SetWidth(8)
    toolbar:AddChild(sp2)

    -- View mode dropdown
    local viewDD = AceGUI:Create("Dropdown")
    viewDD:SetLabel("")
    viewDD:SetWidth(130)
    viewDD:SetList({ guild = L["ViewGuild"], mine = L["ViewMine"] })
    viewDD:SetValue(self._viewMode)
    viewDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._viewMode       = value
        self._selectedProfId = 0   -- reset to "All Professions"
        -- Defer one frame so the dropdown callback completes before we
        -- release its parent container.
        C_Timer.After(0, function()
            if self._container then
                self._container:ReleaseChildren()
                self:Draw(self._container)
            end
        end)
    end)
    toolbar:AddChild(viewDD)

    -- ---- Shopping list (below dropdowns, above column headers) -------------
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

    -- ---- Column headers (raw frame – not managed by AceGUI layout) ---------
    -- Anchor to the shopping list section when present, otherwise to toolbar.
    local anchorFrame = (self._slSection and self._slSection.frame) or toolbar.frame
    local headerBar = CreateFrame("Frame", nil, container.content)
    headerBar:SetHeight(18)
    headerBar:SetPoint("TOPLEFT",  anchorFrame, "BOTTOMLEFT",  0, 0)
    headerBar:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    self._headerBar = headerBar

    -- Positions match the pool row layout: icon(4+14+4=22), crafterLbl at 290.
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
    craftersHdr:SetPoint("LEFT", headerBar, "LEFT", 292, 0)
    craftersHdr:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. "Crafters|r")

    local craftersHdrHit = CreateFrame("Frame", nil, headerBar)
    craftersHdrHit:SetPoint("LEFT",  craftersHdr, "LEFT",  -2, 0)
    craftersHdrHit:SetPoint("RIGHT", craftersHdr, "RIGHT",  2, 0)
    craftersHdrHit:SetHeight(18)
    craftersHdrHit:SetScript("OnEnter", function(f)
        addon.Tooltip.Owner(f)
        GameTooltip:SetText("Crafters", 1, 1, 1)
        GameTooltip:AddLine("Guild members who know this recipe.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    craftersHdrHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ---- Recipe scroll list ------------------------------------------------
    -- Pool cleanup if Draw() is being called a second time (e.g. view mode change).
    if self._pool then
        self:DestroyPool()
    end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    -- When AceGUI recycles this ScrollFrame (tab switch / ReleaseChildren),
    -- destroy the pool so its frames are not still parented to content.
    scroll:SetCallback("OnRelease", function()
        self:DestroyPool()
        -- headerBar is a raw WoW frame not tracked by AceGUI; hide and detach
        -- it here so it doesn't bleed onto other tabs that share container.content.
        if self._headerBar then
            self._headerBar:Hide()
            self._headerBar:SetParent(UIParent)
            self._headerBar = nil
        end
    end)
    container:AddChild(scroll)
    self._scroll = scroll

    -- AceGUI List layout has no fill-remaining-height support, so we anchor
    -- the scroll's raw frame directly below the header row and pin its bottom to
    -- the container.  container.LayoutFinished re-applies the anchors after
    -- every DoLayout pass (window resize, tab redraw, etc.).
    local function AnchorScrollToFill()
        if not (self._scroll and self._scroll.frame) then return end
        self._scroll.frame:ClearAllPoints()
        self._scroll.frame:SetPoint("TOPLEFT",     headerBar, "BOTTOMLEFT",  0, 0)
        self._scroll.frame:SetPoint("BOTTOMRIGHT", container.content, "BOTTOMRIGHT", 0, 0)
    end
    container.LayoutFinished = function() AnchorScrollToFill() end
    AnchorScrollToFill()

    self:FillList()
end

-- ---------------------------------------------------------------------------
-- Shopping list helpers
-- ---------------------------------------------------------------------------

--- Fill the shopping list InlineGroup with expandable recipe rows.
-- Clicking a recipe row toggles its reagent sub-rows open/closed.
function BrowserTab:FillShoppingListSection(container)
    local bl = Ace.db.char.shoppingList

    local parent = container.content or container.frame

    if not self._slPool        then self._slPool        = {} end
    if not self._slReagentPool then self._slReagentPool = {} end
    if not self._slExpanded    then self._slExpanded    = {} end

    -- Build sorted list of recipe rows.
    local rows = {}
    for sid, entry in pairs(bl) do
        table.insert(rows, { sid = sid, entry = entry })
    end
    table.sort(rows, function(a, b)
        local na = (a.entry and a.entry.name) or tostring(a.sid)
        local nb = (b.entry and b.entry.name) or tostring(b.sid)
        return na < nb
    end)

    -- Re-parent existing pool frames to current container (handles full redraws).
    for _, f in ipairs(self._slPool)        do f:SetParent(parent) end
    for _, f in ipairs(self._slReagentPool) do f:SetParent(parent) end

    -- ── Recipe row pool ──────────────────────────────────────────────────────
    local function GetRecipeFrame(idx)
        if self._slPool[idx] then return self._slPool[idx] end

        local f = CreateFrame("Button", nil, parent)
        f:SetHeight(ROW_HEIGHT)
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        -- Arrow glyph (+ collapsed / - expanded)
        local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrow:SetPoint("LEFT", f, "LEFT", 2, 0)
        arrow:SetWidth(12)
        arrow:SetJustifyH("CENTER")
        f.arrow = arrow

        -- Icon: 14×14 after the arrow
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", f, "LEFT", 16, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.icon = icon

        -- Name label
        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(210)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        -- Qty controls anchored to the right edge
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

        self._slPool[idx] = f
        return f
    end

    -- ── Reagent row pool ─────────────────────────────────────────────────────
    local INDENT = 18   -- pixels to indent reagent rows
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

        -- [Bank] button: shown only when TOGBankClassic has this reagent in stock.
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

    -- ── Hide everything first ────────────────────────────────────────────────
    for _, f in ipairs(self._slPool)        do f:Hide() end
    for _, f in ipairs(self._slReagentPool) do f:Hide() end

    -- ── Layout pass ─────────────────────────────────────────────────────────
    local yOffset     = 0
    local reagentIdx  = 0

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

        -- Arrow: ▶ if has reagents and collapsed, ▼ if expanded, blank if no reagents.
        if hasReagents then
            f.arrow:SetText(expanded and "|cFFFFD100-|r" or "|cFFFFD100+|r")
        else
            f.arrow:SetText("")
        end

        -- Icon
        if ent and ent.icon then
            f.icon:SetTexture(ent.icon)
        else
            f.icon:SetTexture(nil)
        end

        -- Name with quality color
        local colorHex = ent and ent.itemLink and ent.itemLink:match("|c(ff%x%x%x%x%x%x)|H")
        f.nameLbl:SetText(colorHex and ("|c" .. colorHex .. name .. "|r") or name)

        f.qtyLbl:SetText(tostring(qty))

        -- Toggle expand on row click (but not on the control buttons).
        f:SetScript("OnClick", function(btn)
            -- Ignore if a child button captured the click.
            if f.minusBtn:IsMouseOver() or f.plusBtn:IsMouseOver() or f.removeBtn:IsMouseOver() then
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
            if self._popup and self._popup._entryId == sid and self._popup._refreshQty then
                self._popup._refreshQty()
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
            if self._popup and self._popup._entryId == sid and self._popup._refreshQty then
                self._popup._refreshQty()
            end
            self:RefreshShoppingList()
        end)
        f.removeBtn:SetScript("OnClick", function()
            bl[sid] = nil
            self._slExpanded[sid] = nil
            if self._popup and self._popup._entryId == sid and self._popup._refreshQty then
                self._popup._refreshQty()
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
        f:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        f:Show()

        -- Reagent sub-rows (only when expanded)
        if expanded and hasReagents then
            for _, r in ipairs(reagents) do
                reagentIdx = reagentIdx + 1
                local rf = GetReagentFrame(reagentIdx)
                rf:ClearAllPoints()
                rf:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -yOffset)
                rf:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
                yOffset = yOffset + ROW_HEIGHT

                -- Reagent icon via item ID if available, else blank
                if r.itemId and r.itemId > 0 then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(r.itemId)
                    rf.icon:SetTexture(itemTexture or nil)
                else
                    rf.icon:SetTexture(nil)
                end

                rf.nameLbl:SetText(r.name or "")

                local rItemLink = r.itemLink
                rf:SetScript("OnEnter", function()
                    if rItemLink then
                        addon.Tooltip.Owner(rf)
                        GameTooltip:SetHyperlink(rItemLink)
                        GameTooltip:Show()
                    end
                end)
                rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
                -- Total needed = reagent count × recipe quantity
                local needed = (r.count or 1) * qty
                rf.countLbl:SetText("|cffffffff x" .. needed .. "|r")

                -- [Bank] button: show when TOGBankClassic has this reagent in stock.
                local rItemId = rItemLink and tonumber(rItemLink:match("|Hitem:(%d+)"))
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

    -- Resize the InlineGroup to fit all visible rows.
    local totalH = math.max(yOffset, ROW_HEIGHT)
    container:SetHeight(totalH + 40)
end

--- Refresh the shopping list section without touching the recipe scroll list.
-- If _slSection already exists, just refill it in place.
-- If it didn't exist (list was empty, now has an item), do a full redraw.
function BrowserTab:RefreshShoppingList()
    if not self._container then return end

    if self._slSection then
        -- Section already visible — refill it in place.
        local bl = Ace.db.char.shoppingList
        local hasSL = false
        for _ in pairs(bl) do hasSL = true; break end

        if hasSL then
            self:FillShoppingListSection(self._slSection)
            -- Re-layout the parent so the resized InlineGroup is positioned correctly.
            if self._container then self._container:DoLayout() end
        else
            -- List is now empty; hide and queue a clean full redraw next frame.
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
        -- Section wasn't shown (list was empty). Needs a full redraw.
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
    -- Hide pool rows; empty-state AceGUI labels are handled by ReleaseChildren.
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

    -- Reset so hint / empty-state AceGUI labels use normal AceGUI sizing.
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

    -- Prevent AceGUI's LayoutFinished from resetting our manually-set content height.
    -- When FixScroll shows the scrollbar for the first time it calls DoLayout() →
    -- LayoutFinished(nil, nil) → content:SetHeight(20), wiping our real height.
    scroll.LayoutFinished = function() end

    -- Set the true total height so the scrollbar range is correct, then fix scroll.
    scroll.content:SetHeight(#recipes * ROW_HEIGHT)
    scroll:FixScroll()

    -- Build the raw-frame pool the first time (reuse across RefreshList calls).
    if not self._pool then
        self:BuildPool(scroll.content)
    end

    self:UpdateVirtualRows()

    -- Hook scrollbar so virtual rows update whenever the scroll position changes.
    scroll.scrollbar:SetScript("OnValueChanged", function(bar, value)
        bar.obj:SetScroll(value)
        self:UpdateVirtualRows()
    end)
end

-- Build POOL_SIZE raw WoW frames parented to the scroll content frame.
-- Each frame represents one visible recipe row.
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

        local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameLbl:SetWidth(210)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        -- [Bank] button: visible only when TOGBankClassic holds the crafted item.
        local bankBtn = CreateFrame("Button", nil, f)
        bankBtn:SetSize(52, 14)
        bankBtn:SetPoint("LEFT", nameLbl, "RIGHT", 4, 0)
        bankBtn:SetNormalFontObject(GameFontNormalSmall)
        bankBtn:SetText("|cFF88FF88[Bank]|r")
        bankBtn:Hide()
        bankBtn:SetScript("OnClick", function()
            local entry = f._entry
            if not entry or not entry._bankItemId then return end
            local name = entry.itemLink and entry.itemLink:match("%[(.-)%]") or entry.name
            addon.Bank.ShowRequestDialog(entry._bankItemId, name, entry.itemLink)
        end)
        bankBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(bankBtn)
            GameTooltip:SetText("Request from Bank", 1, 1, 1)
            GameTooltip:AddLine("Send a request to a TOGBankClassic guild banker.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.bankBtn = bankBtn

        local crafterLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        crafterLbl:SetPoint("LEFT", f, "LEFT", 290, 0)
        crafterLbl:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        crafterLbl:SetJustifyH("LEFT")
        crafterLbl:SetWordWrap(false)
        f.crafterLbl = crafterLbl

        f:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local entry = f._entry
            if not entry then return end
            self:OpenRecipePopup(entry)
        end)

        f:SetScript("OnEnter", function()
            local entry = f._entry
            if not entry then return end
            addon.Tooltip.Owner(f)
            if entry.recipeLink then
                -- Recipe scroll item link (scroll-taught recipes have a real item).
                GameTooltip:SetHyperlink(entry.recipeLink)
            elseif entry.spellId then
                GameTooltip:SetSpellByID(entry.spellId)
            elseif entry.reagents and #entry.reagents > 0 then
                local parts = {}
                for _, r in ipairs(entry.reagents) do
                    table.insert(parts, r.name .. " (" .. r.count .. ")")
                end
                local reagentLine = (SPELL_REAGENTS or "Reagents:") .. " " .. table.concat(parts, ", ")
                local header = (entry.profName and entry.profName ~= "")
                    and (entry.profName .. ": " .. entry.name) or entry.name
                local nameStr = "|cffffff00" .. header .. "|r"
                GameTooltip:ClearLines()
                GameTooltip:AddLine(nameStr)
                GameTooltip:AddLine(reagentLine, 1, 1, 1, true)
                if entry.itemLink then
                    local scraper = GetItemScraper()
                    scraper:ClearLines()
                    scraper:SetHyperlink(entry.itemLink)
                    local n = scraper:NumLines()
                    if n > 1 then
                        GameTooltip:AddLine(" ")
                        for i = 1, n do  -- include line 1 (item name with quality color)
                            local lt = _G["TOGPMItemScraperTextLeft"  .. i]
                            local rt = _G["TOGPMItemScraperTextRight" .. i]
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
                if entry.crafters and #entry.crafters > 0 then
                    GameTooltip:AddLine(" ")
                    local iconStr    = entry.profIconId and ("|T" .. entry.profIconId .. ":14:14:0:0|t ") or ""
                    local brandColor = "|c" .. (addon.BrandColor or "ffDA8CFF")
                    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
                    local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
                    local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF")
                    local parts = {}
                    for _, c in ipairs(entry.crafters) do
                        local col = c.isYou and colorYou or (c.online and colorOnline or colorOffline)
                        table.insert(parts, col .. c.name .. "|r")
                    end
                    GameTooltip:AddLine(iconStr .. brandColor .. "[TOGPM]|r " .. table.concat(parts, ", "), 1, 1, 1, true)
                end
                GameTooltip:Show()
                return
            elseif entry.itemLink then
                GameTooltip:SetHyperlink(entry.itemLink)
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

-- Permanently destroy the pool frames so they are not orphaned on content
-- when AceGUI recycles the ScrollFrame for the next tab.
function BrowserTab:DestroyPool()
    -- Close the popup if it was opened for a row in this list.
    if self._popup then
        self._popup:Release()
        self._popup = nil
    end
    if self._pool then
        for _, f in ipairs(self._pool) do
            f:Hide()
            f:SetParent(UIParent)  -- unparent first so it won't linger on content
            f:SetScript("OnMouseDown", nil)
            f:SetScript("OnEnter",     nil)
            f:SetScript("OnLeave",     nil)
        end
        self._pool    = nil
        self._recipes = nil
    end
    self._scroll = nil
end

-- ---------------------------------------------------------------------------
-- Recipe detail popup
-- ---------------------------------------------------------------------------

--- Open (or replace) the recipe detail popup.
-- Shows the recipe name/icon, the list of crafters who know it (with
-- online/offline/you coloring), reagents, and [–] qty [+/x] controls
-- for managing the shopping-list quantity.
-- @param entry  table: { id, name, icon, isSpell, crafters={...}, reagents={...} }
function BrowserTab:OpenRecipePopup(entry)
    -- Lazy-create the popup frame once and keep it alive forever (never Released).
    -- This is the same pattern PersonalShopper uses for its main window:
    -- a stable raw WoW frame means _G["TOGPMRecipePopup"] never goes stale, so
    -- UISpecialFrames + ESC works reliably.
    if not self._popup then
        local popup = AceGUI:Create("Frame")
        popup:SetWidth(480)
        popup:SetHeight(340)
        popup:SetLayout("List")
        -- OnClose fires from frame:SetScript("OnHide") — frame is already hidden.
        -- We just clear the entry id; do NOT call Release().
        popup:SetCallback("OnClose", function(_w)
            self._popup._entryId    = nil
            self._popup._refreshQty = nil
        end)
        -- Register ESC support once — the global always points to the same stable frame.
        _G["TOGPMRecipePopup"] = popup.frame
        tinsert(UISpecialFrames, "TOGPMRecipePopup")
        self._popup = popup
    end

    local popup = self._popup

    -- Toggle: clicking the same row while the popup is visible hides it.
    if popup._entryId == entry.id and popup.frame:IsShown() then
        popup:Hide()
        return
    end

    -- Clear previous AceGUI children; rebuild for this entry.
    popup:ReleaseChildren()
    popup:SetTitle(entry.name)
    popup:SetStatusText("")
    popup._entryId = entry.id

    -- Snap to top-right of the main window if available, otherwise screen centre.
    local mainWowFrame = addon.MainWindow
                      and addon.MainWindow.frame
                      and addon.MainWindow.frame.frame
    popup.frame:ClearAllPoints()
    if mainWowFrame and mainWowFrame:IsShown() then
        popup.frame:SetPoint("TOPLEFT", mainWowFrame, "TOPRIGHT", 4, 0)
    else
        popup.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- ── Icon + name ──────────────────────────────────────────────────────────
    -- Use nameLbl:SetFont() (the AceGUI method), NOT nameLbl.label:SetFont().
    -- The AceGUI method stores the font on the widget table so OnAcquire can
    -- properly reset it to GameFontHighlightSmall when the widget is recycled.
    -- Bypassing it via the raw fontstring leaks the 24px size into every label
    -- that AceGUI later hands that pooled widget to.
    local titleColor = entry.itemLink and entry.itemLink:match("|c(ff%x%x%x%x%x%x)|H") or "ffffd100"
    local nameLbl = AceGUI:Create("InteractiveLabel")
    nameLbl:SetImage(entry.icon)
    nameLbl:SetImageSize(24, 24)
    nameLbl:SetText("|c" .. titleColor .. entry.name .. "|r")
    -- Fixed width: popup content = 480-34 = 446px. Buttons = 12+22+12+12 = 58px.
    -- 375px for the name leaves ~13px gap before the buttons.
    nameLbl:SetWidth(375)
    do
        local fontPath, _, fontFlags = GameFontNormal:GetFont()
        nameLbl:SetFont(fontPath, 24, fontFlags or "")  -- AceGUI method; safe to recycle
    end
    local nameLink = entry.itemLink or entry.recipeLink
    if nameLink then
        nameLbl:SetCallback("OnEnter", function(_widget)
            addon.Tooltip.Owner(_widget.frame)
            GameTooltip:SetHyperlink(nameLink)
            GameTooltip:Show()
        end)
        nameLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        nameLbl:SetCallback("OnClick", function(_widget, _event, button)
            if button == "LeftButton" and IsShiftKeyDown() then
                ChatEdit_InsertLink(nameLink)
            end
        end)
    end

    -- ── Shopping list controls ────────────────────────────────────────────────
    -- All plain AceGUI widgets — they get cleaned up by ReleaseChildren() each open.
    local qtyLbl = AceGUI:Create("Label")
    qtyLbl:SetWidth(22)
    qtyLbl:SetJustifyH("CENTER")

    local countLbls = {}
    local function RefreshQty()
        local qty = (Ace.db.char.shoppingList[entry.id] and Ace.db.char.shoppingList[entry.id].quantity) or 0
        qtyLbl:SetText(tostring(qty))
        local mult = math.max(1, qty)
        for _, cl in ipairs(countLbls) do
            cl.lbl:SetText("|cffffffff\195\151" .. cl.base * mult .. "|r")
        end
    end

    local minusBtn = AceGUI:Create("InteractiveLabel")
    minusBtn:SetText("|cFFFFD100-|r")
    minusBtn:SetWidth(12)
    minusBtn:SetJustifyH("CENTER")
    minusBtn:SetCallback("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity = sl[entry.id].quantity - 1
            if sl[entry.id].quantity <= 0 then sl[entry.id] = nil end
        end
        RefreshQty()
        self:RefreshShoppingList()
    end)

    local plusBtn = AceGUI:Create("InteractiveLabel")
    plusBtn:SetText("|cFFFFD100+|r")
    plusBtn:SetWidth(12)
    plusBtn:SetJustifyH("CENTER")
    plusBtn:SetCallback("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity = sl[entry.id].quantity + 1
            sl[entry.id].name     = entry.name
            sl[entry.id].icon     = entry.icon
            sl[entry.id].itemLink = entry.itemLink
            sl[entry.id].reagents = entry.reagents
        else
            sl[entry.id] = { name = entry.name, quantity = 1, icon = entry.icon, itemLink = entry.itemLink, reagents = entry.reagents }
        end
        RefreshQty()
        self:RefreshShoppingList()
    end)

    local removeBtn = AceGUI:Create("InteractiveLabel")
    removeBtn:SetText("|cFFFF4444x|r")
    removeBtn:SetWidth(12)
    removeBtn:SetJustifyH("CENTER")
    removeBtn:SetCallback("OnClick", function()
        Ace.db.char.shoppingList[entry.id] = nil
        RefreshQty()
        self:RefreshShoppingList()
    end)

    -- Expose RefreshQty on the popup so FillShoppingListSection can call it
    -- when its own +/-/remove buttons change qty for this same entry.
    popup._refreshQty = RefreshQty

    RefreshQty()

    -- Lay out: [icon+name ..................... - qty + x]
    -- nameLbl is full-width so the buttons float right via a right-aligned row group.
    local ctrlRow = AceGUI:Create("SimpleGroup")
    ctrlRow:SetLayout("Flow")
    ctrlRow:SetFullWidth(true)
    ctrlRow:AddChild(nameLbl)
    ctrlRow:AddChild(minusBtn)
    ctrlRow:AddChild(qtyLbl)
    ctrlRow:AddChild(plusBtn)
    ctrlRow:AddChild(removeBtn)
    popup:AddChild(ctrlRow)

    -- ── Reagents ─────────────────────────────────────────────────────────────
    local reagents = entry.reagents or {}
    if #reagents > 0 then
        local reagentHeading = AceGUI:Create("Heading")
        reagentHeading:SetText("Reagents")
        reagentHeading:SetFullWidth(true)
        popup:AddChild(reagentHeading)

        for _, r in ipairs(reagents) do
            local rowGrp = AceGUI:Create("SimpleGroup")
            rowGrp:SetLayout("Flow")
            rowGrp:SetFullWidth(true)

            -- Name column (fixed 200px so counts align across rows)
            local nameLbl = AceGUI:Create("InteractiveLabel")
            nameLbl:SetText(r.name)
            nameLbl:SetWidth(200)
            if nameLbl.label then nameLbl.label:SetWordWrap(false) end
            rowGrp:AddChild(nameLbl)

            -- Count column (right-justified inside 44px so the × symbol
            -- always lands at the same x, giving a clean column of numbers)
            local countLbl = AceGUI:Create("Label")
            local baseCount = r.count or 1
            local initMult = math.max(1, (Ace.db.char.shoppingList[entry.id] and Ace.db.char.shoppingList[entry.id].quantity) or 0)
            countLbl:SetText("|cffffffff\195\151" .. baseCount * initMult .. "|r")
            countLbl:SetWidth(44)
            countLbl:SetJustifyH("RIGHT")
            countLbls[#countLbls + 1] = { lbl = countLbl, base = baseCount }
            rowGrp:AddChild(countLbl)

            -- Item link callbacks (on the name widget)
            local rLink = r.itemLink
            if rLink then
                nameLbl:SetCallback("OnEnter", function(_widget)
                    addon.Tooltip.Owner(_widget.frame)
                    GameTooltip:SetHyperlink(rLink)
                    GameTooltip:Show()
                end)
                nameLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
                nameLbl:SetCallback("OnClick", function(_widget, _event, button)
                    if button == "LeftButton" and IsShiftKeyDown() then
                        ChatEdit_InsertLink(rLink)
                    end
                end)
            end

            -- [Bank] button — shown only when TOGBankClassic has this reagent in stock
            if addon.Bank and addon.Bank.GetStock and addon.Bank.ShowRequestDialog then
                local rItemId = rLink and tonumber(rLink:match("item:(%d+)"))
                if rItemId then
                    local stock = addon.Bank.GetStock(rItemId)
                    if stock and stock > 0 then
                        local bankSp = AceGUI:Create("Label")
                        bankSp:SetWidth(5)
                        bankSp:SetText("")
                        rowGrp:AddChild(bankSp)

                        local bankLbl = AceGUI:Create("InteractiveLabel")
                        bankLbl:SetText("|cFF88FF88[Bank]|r")
                        bankLbl:SetWidth(52)
                        bankLbl:SetCallback("OnEnter", function(_widget)
                            addon.Tooltip.Owner(_widget.frame)
                            GameTooltip:SetText("Request from Bank", 1, 1, 1)
                            GameTooltip:AddLine("Send a request to a TOGBankClassic guild banker.", nil, nil, nil, true)
                            GameTooltip:Show()
                        end)
                        bankLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
                        bankLbl:SetCallback("OnClick", function()
                            addon.Bank.ShowRequestDialog(rItemId, r.name, rLink, popup.frame)
                        end)
                        rowGrp:AddChild(bankLbl)
                    end
                end
            end

            popup:AddChild(rowGrp)
        end
    end

    -- ── Known By ─────────────────────────────────────────────────────────────
    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
    local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
    local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF")

    local crafterHeading = AceGUI:Create("Heading")
    crafterHeading:SetText(L["PopupCrafters"])
    crafterHeading:SetFullWidth(true)
    popup:AddChild(crafterHeading)

    local crafters = entry.crafters or {}
    if #crafters > 0 then
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

        for _, c in ipairs(crafters) do
            local col = c.isYou and colorYou or (c.online and colorOnline or colorOffline)
            local cLbl = AceGUI:Create("InteractiveLabel")
            cLbl:SetText(col .. c.name .. "|r")
            cLbl:SetFullWidth(true)
            if not c.isYou then
                local charKey = c.charKey or c.name
                local shortName = c.name
                local function doWhisper(anchorFrame)
                    if Menu and Menu.CreateContextMenu then
                        Menu.CreateContextMenu(anchorFrame, function(_, root)
                            root:CreateTitle(shortName)
                            root:CreateButton(shortName, function() openWhisper(charKey) end)
                        end)
                    else
                        openWhisper(charKey)
                    end
                end
                cLbl:SetCallback("OnEnter", function(_widget)
                    addon.Tooltip.Owner(_widget.frame)
                    GameTooltip:SetText(c.name, 1, 1, 1)
                    GameTooltip:AddLine("Right-click to whisper", 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                cLbl:SetCallback("OnLeave", function() GameTooltip:Hide() end)
                cLbl:SetCallback("OnClick", function(_widget, _event, button)
                    if button == "RightButton" then doWhisper(_widget.frame) end
                end)
            end
            popup:AddChild(cLbl)
        end
    else
        local noDataLbl = AceGUI:Create("Label")
        noDataLbl:SetText("|cffaaaaaa" .. L["NoDataYet"] .. "|r")
        noDataLbl:SetFullWidth(true)
        popup:AddChild(noDataLbl)
    end

    popup:Show()
end

-- Recalculate which recipe indices are visible and update pool frames.
function BrowserTab:UpdateVirtualRows()
    local scroll   = self._scroll
    local recipes  = self._recipes
    if not scroll or not recipes or not self._pool then return end

    local status   = scroll.status or scroll.localstatus
    local offset   = status.offset or 0
    local firstIdx = math.floor(offset / ROW_HEIGHT)  -- 0-based

    for i = 1, POOL_SIZE do
        local f         = self._pool[i]
        local recipeIdx = firstIdx + i  -- 1-based into recipes
        local entry     = recipes[recipeIdx]
        if entry then
            f._entry = entry
            f.icon:SetTexture(entry.icon)
            -- Apply item-quality color when available (stored from itemLink at scan
            -- time; nil for wire-received entries → plain white name).
            local colorHex = entry.itemLink and entry.itemLink:match("|c(ff%x%x%x%x%x%x)|H")
            f.nameLbl:SetText(colorHex and ("|c" .. colorHex .. entry.name .. "|r") or entry.name)
            local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
            local colorOffline = "|c" .. (addon.ColorOffline or "ffaaaaaa")
            local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffDA8CFF")
            local parts = {}
            for _, c in ipairs(entry.crafters) do
                local col = c.isYou and colorYou or (c.online and colorOnline or colorOffline)
                table.insert(parts, col .. c.name .. "|r")
            end
            f.crafterLbl:SetText(table.concat(parts, ", "))
            -- [Bank] button: extract numeric item ID from itemLink, check TOGBankClassic stock.
            local bankItemId = entry.itemLink and tonumber(entry.itemLink:match("item:(%d+)"))
            if bankItemId and _G["TOGBankClassic_Guild"] and addon.Bank.GetStock(bankItemId) > 0 then
                entry._bankItemId = bankItemId
                f.bankBtn:Show()
            else
                entry._bankItemId = nil
                f.bankBtn:Hide()
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
