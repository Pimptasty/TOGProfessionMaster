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
local ROW_HEIGHT  = 22
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

    local profDD = AceGUI:Create("Dropdown")
    profDD:SetLabel("|c" .. (addon.BrandColor or "ffFF8000") .. L["PanelProfessions"] .. "|r")
    profDD:SetWidth(180)
    profDD:SetList(profList, profOrder)
    profDD:SetValue(self._selectedProfId or 0)
    profDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._selectedProfId = value
        self:RefreshList()
    end)
    profDD.frame:SetScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_BOTTOMLEFT")
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
        GameTooltip:SetOwner(f, "ANCHOR_BOTTOMLEFT")
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

    -- ---- Column headers (raw frame – not managed by AceGUI layout) ---------
    -- Anchoring to toolbar.frame directly means AceGUI layout passes cannot
    -- override the font-string positions.
    local headerBar = CreateFrame("Frame", nil, container.content)
    headerBar:SetHeight(18)
    headerBar:SetPoint("TOPLEFT",  toolbar.frame, "BOTTOMLEFT",  0, 0)
    headerBar:SetPoint("TOPRIGHT", toolbar.frame, "BOTTOMRIGHT", 0, 0)
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
        GameTooltip:SetOwner(f, "ANCHOR_BOTTOMLEFT")
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
        GameTooltip:SetOwner(f, "ANCHOR_BOTTOMLEFT")
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
-- List helpers
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
            GameTooltip:SetOwner(bankBtn, "ANCHOR_TOPRIGHT")
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
            -- Anchor to the left edge of the row; flip above/below based on screen space.
            local _, rowTop    = f:GetCenter()
            local screenHeight = GetScreenHeight()
            if rowTop and rowTop > screenHeight / 2 then
                GameTooltip:SetOwner(f, "ANCHOR_BOTTOMLEFT")
            else
                GameTooltip:SetOwner(f, "ANCHOR_TOPLEFT")
            end
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
-- Shows the recipe name/icon, the list of crafters who know it, and
-- [–] qty [+] controls for managing the shopping-list quantity.
-- @param entry  table: { id, name, icon, isSpell, crafters = {...} }
function BrowserTab:OpenRecipePopup(entry)
    -- Release any previously open popup first.
    if self._popup then
        self._popup:Release()
        self._popup = nil
    end

    local popup = AceGUI:Create("Frame")
    popup:SetTitle(entry.name)
    popup:SetStatusText("")
    popup:SetWidth(400)
    popup:SetHeight(280)
    popup:SetLayout("List")
    popup:SetCallback("OnClose", function(w)
        w:Release()
        self._popup = nil
    end)

    -- Center on the main window frame if available, otherwise screen centre.
    local anchor = (addon.MainWindow
                    and addon.MainWindow.frame
                    and addon.MainWindow.frame.frame)
                   or UIParent
    popup.frame:ClearAllPoints()
    popup.frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)

    self._popup = popup

    -- ── Icon + name ──────────────────────────────────────────────────────────
    local headerGroup = AceGUI:Create("SimpleGroup")
    headerGroup:SetLayout("Flow")
    headerGroup:SetFullWidth(true)
    popup:AddChild(headerGroup)

    local iconLbl = AceGUI:Create("Label")
    iconLbl:SetImage(entry.icon)
    iconLbl:SetImageSize(24, 24)
    iconLbl:SetText("  ")      -- padding so the image is visible
    iconLbl:SetWidth(32)
    headerGroup:AddChild(iconLbl)

    local nameLbl = AceGUI:Create("Label")
    nameLbl:SetText("|cffffd100" .. entry.name .. "|r")
    nameLbl:SetWidth(320)
    headerGroup:AddChild(nameLbl)

    -- ── Crafters ─────────────────────────────────────────────────────────────
    local crafterHeading = AceGUI:Create("Heading")
    crafterHeading:SetText(L["PopupCrafters"])
    crafterHeading:SetFullWidth(true)
    popup:AddChild(crafterHeading)

    local craftersText = #entry.crafters > 0
        and table.concat(entry.crafters, ", ")
        or  "|cffaaaaaa" .. L["NoDataYet"] .. "|r"
    local crafterLbl = AceGUI:Create("Label")
    crafterLbl:SetText(craftersText)
    crafterLbl:SetFullWidth(true)
    popup:AddChild(crafterLbl)

    -- ── Shopping list quantity ────────────────────────────────────────────────
    local slHeading = AceGUI:Create("Heading")
    slHeading:SetText(L["SectionShoppingList"])
    slHeading:SetFullWidth(true)
    popup:AddChild(slHeading)

    local qtyRow = AceGUI:Create("SimpleGroup")
    qtyRow:SetLayout("Flow")
    qtyRow:SetFullWidth(true)
    popup:AddChild(qtyRow)

    local statusLbl = AceGUI:Create("Label")
    statusLbl:SetWidth(190)
    qtyRow:AddChild(statusLbl)

    local minusBtn = AceGUI:Create("Button")
    minusBtn:SetText("-")
    minusBtn:SetWidth(44)
    qtyRow:AddChild(minusBtn)

    local qtyLbl = AceGUI:Create("Label")
    qtyLbl:SetWidth(36)
    qtyRow:AddChild(qtyLbl)

    local plusBtn = AceGUI:Create("Button")
    plusBtn:SetText("+")
    plusBtn:SetWidth(44)
    qtyRow:AddChild(plusBtn)

    local function RefreshQty()
        local sl  = Ace.db.char.shoppingList
        local qty = sl[entry.id] and sl[entry.id].quantity or 0
        qtyLbl:SetText(tostring(qty))
        if qty == 0 then
            statusLbl:SetText("|cffaaaaaa" .. L["PopupNotOnList"] .. "|r")
            minusBtn:SetDisabled(true)
        else
            statusLbl:SetText("|cff00ff00" .. L["PopupOnList"] .. "|r")
            minusBtn:SetDisabled(false)
        end
    end

    plusBtn:SetCallback("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity = sl[entry.id].quantity + 1
        else
            sl[entry.id] = { name = entry.name, quantity = 1 }
        end
        RefreshQty()
    end)

    minusBtn:SetCallback("OnClick", function()
        local sl = Ace.db.char.shoppingList
        if sl[entry.id] then
            sl[entry.id].quantity = sl[entry.id].quantity - 1
            if sl[entry.id].quantity <= 0 then
                sl[entry.id] = nil
            end
        end
        RefreshQty()
    end)

    RefreshQty()
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
