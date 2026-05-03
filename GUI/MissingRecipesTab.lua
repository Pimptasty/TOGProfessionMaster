-- TOG Profession Master — Missing Recipes Tab
-- Standalone "what scrolls am I missing?" view, modeled on PersonalShopper's
-- Collector. Compares the static recipe universe (Data/Recipes/<Profession>.lua)
-- against gdb.recipes[profId][recipeId].crafters[charKey] to compute which
-- AH-obtainable scrolls a given character has yet to learn.
--
-- The recipe + source DBs are loaded as plain Lua tables in TOC order; this
-- file consumes them read-only. No new sync traffic, no scanner changes — the
-- "known" half of the comparison reuses the data Scanner.lua already populates.

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local MissingRecipesTab = {}
addon.MissingRecipesTab = MissingRecipesTab

-- Window size policy — locked to the SAME dimensions as CooldownsTab so
-- switching between Missing and Cooldowns produces no visible jump.
-- MainWindow reads this on tab switch and on Open. Keep these in sync
-- with CooldownsTab.WINDOW_SIZE — that's the whole point.
MissingRecipesTab.WINDOW_SIZE = { width = 720, height = 500, locked = true }

-- Profession display names come from the shared addon.PROF_NAMES table
-- in TOGProfessionMaster.lua (covers everything Vanilla through MoP).
-- Per-version filtering happens via addon.IsProfessionAvailable in the
-- dropdown build below — a profession that doesn't exist on the current
-- client (Jewelcrafting on Vanilla, Inscription on Vanilla / TBC,
-- Poisons on Wrath+) is hidden even if the character somehow has stale
-- skill data for it cached.

-- Source key → locale key. Order here drives display order on each row.
local SRC_LABELS = {
    vendor    = "MissingSrcVendor",
    drop      = "MissingSrcDrop",
    quest     = "MissingSrcQuest",
    crafted   = "MissingSrcCrafted",
    container = "MissingSrcContainer",
    fishing   = "MissingSrcFishing",
    trainer   = "MissingSrcTrainer",
}
local SRC_ORDER = { "vendor", "drop", "quest", "crafted", "container", "fishing", "trainer" }

-- Tab state — survives tab switches but resets on UI reload.
MissingRecipesTab._charKey         = nil
MissingRecipesTab._profId          = 0
MissingRecipesTab._searchText      = ""
MissingRecipesTab._includeTrainer  = false
MissingRecipesTab._container       = nil
MissingRecipesTab._listSection     = nil

-- ---------------------------------------------------------------------------
-- Pure helpers
-- ---------------------------------------------------------------------------

local function HasNonTrainerSource(srcEntry)
    if not srcEntry then return false end
    for k in pairs(srcEntry) do
        if k ~= "trainer" then return true end
    end
    return false
end

local function FormatSources(srcEntry, includeTrainer)
    if not srcEntry then return "" end
    local parts, seen = {}, {}
    for _, key in ipairs(SRC_ORDER) do
        if srcEntry[key] and (key ~= "trainer" or includeTrainer) then
            table.insert(parts, L[SRC_LABELS[key]] or key)
            seen[key] = true
        end
    end
    -- Catch any source key not in SRC_ORDER (unknown future sources).
    for k in pairs(srcEntry) do
        if not seen[k] and SRC_LABELS[k] == nil and (k ~= "trainer" or includeTrainer) then
            table.insert(parts, L["MissingSrcOther"])
            break
        end
    end
    return table.concat(parts, ", ")
end

local function CharShortName(charKey)
    return charKey:match("^([^%-]+)") or charKey
end

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

-- Return list of charKeys that belong to this account and have any tracked
-- profession data. The currently-logged-in toon is always included even if
-- it has not opened a trade-skill window yet.
local function GetCharactersWithProfessions()
    local gdb = addon:GetGuildDb()
    local list, seen = {}, {}
    if gdb and gdb.skills then
        for charKey, profMap in pairs(gdb.skills) do
            if addon:IsMyCharacter(charKey) and profMap and next(profMap) then
                table.insert(list, charKey)
                seen[charKey] = true
            end
        end
    end
    local myKey = addon:GetCharacterKey()
    if not seen[myKey] then table.insert(list, myKey) end

    table.sort(list, function(a, b)
        if a == myKey then return true end
        if b == myKey then return false end
        return a < b
    end)
    return list
end

-- Return profIds the given charKey has tracked skills for, restricted to
-- (a) professions we have a static recipe DB for AND (b) professions
-- that exist on the current client version. The version check guards
-- against stale skill data — e.g. a character whose Wrath-era data
-- lingers in the SavedVariables shouldn't surface Inscription on a
-- Vanilla client.
local function GetProfessionsForCharacter(charKey)
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.skills or not gdb.skills[charKey] then return {} end
    local out = {}
    for profId in pairs(gdb.skills[charKey]) do
        if addon.recipeDB and addon.recipeDB[profId]
           and addon.IsProfessionAvailable(profId) then
            table.insert(out, profId)
        end
    end
    table.sort(out, function(a, b)
        return (addon.PROF_NAMES[a] or tostring(a)) < (addon.PROF_NAMES[b] or tostring(b))
    end)
    return out
end

-- Virtual-scroll constants. Mirrors BrowserTab's approach: a raw frame pool
-- of POOL_SIZE rows is reused as the user scrolls, so total widget count
-- stays bounded regardless of list size. AceGUI's layout pass scales badly
-- past a few hundred children, so we pay the layout cost on POOL_SIZE rows
-- only — never on the full result.
local ROW_HEIGHT = 16
local POOL_SIZE  = 35

-- Build the missing-recipe list for (charKey, profId). Returns the full
-- unfiltered set sorted by required skill — search filtering is applied at
-- render time via GetItemInfoInstant (which does NOT trigger an async load),
-- and the row count is capped during render. Item-name resolution itself
-- happens per-row inside FillList so we only ever pay for the visible slice.
local function BuildMissingList(charKey, profId, includeTrainer)
    if not charKey or not profId or profId == 0 then return {} end
    local recipes = addon.recipeDB and addon.recipeDB[profId]
    if not recipes then return {} end

    -- Hoist all gdb / sources / spec lookups out of the per-recipe loop.
    -- A single GetGuildDb() call instead of one-per-iteration makes a real
    -- difference on professions like Tailoring with ~3000 recipes.
    local sources     = (addon.sourceDB and addon.sourceDB[profId]) or {}
    local gdb         = addon:GetGuildDb()
    local profRecipes = gdb and gdb.recipes and gdb.recipes[profId]
    local specs       = gdb and gdb.specializations and gdb.specializations[charKey]
    local playerSpec  = specs and specs[profId]

    local function knownByChar(recipeId)
        if not profRecipes then return false end
        local rd = profRecipes[recipeId]
        return rd and rd.crafters and rd.crafters[charKey] ~= nil
    end

    local out = {}

    for spellId, data in pairs(recipes) do
        local skip = false
        if data.specialization and data.specialization ~= playerSpec then
            skip = true
        elseif data.season then
            skip = true
        elseif knownByChar(spellId) then
            skip = true
        elseif data.teaches and data.teaches ~= spellId and knownByChar(data.teaches) then
            skip = true
        end

        if not skip then
            local srcEntry = sources[spellId]
            -- A srcEntry is required: it's the only thing that proves the
            -- spellId corresponds to an actual obtainable recipe scroll
            -- (PS's curated data only lists sources for things you can
            -- actually go acquire). includeTrainer further gates whether
            -- trainer-only entries are surfaced.
            local hasUsableSource = srcEntry and (includeTrainer or HasNonTrainerSource(srcEntry))
            if hasUsableSource then
                table.insert(out, {
                    spellId       = spellId,
                    teaches       = data.teaches,
                    requiredSkill = data.requiredSkill or 0,
                    sources       = srcEntry,
                    sourcesText   = FormatSources(srcEntry, includeTrainer),
                })
            end
        end
    end

    table.sort(out, function(a, b)
        if a.requiredSkill ~= b.requiredSkill then
            return a.requiredSkill < b.requiredSkill
        end
        return a.spellId < b.spellId
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- Tooltip helpers
-- All tooltip anchoring goes through addon.Tooltip.Owner per CLAUDE.md.
-- ---------------------------------------------------------------------------

-- Thin alias kept for the existing call sites below; the real work
-- (including the Dropdown/EditBox label-area mouse trick) lives in the
-- shared addon.GUI.AttachTooltip in GUI/SharedWidgets.lua.
local function AttachWidgetTooltip(widget, title, desc)
    addon.GUI.AttachTooltip(widget, title, desc)
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function MissingRecipesTab:Draw(container)
    container:SetLayout("List")
    self._container = container

    if not self._charKey then
        self._charKey = addon:GetCharacterKey()
    end

    local chars = GetCharactersWithProfessions()

    -- Validate the persisted selection still exists in our roster.
    local stillValid = false
    for _, ck in ipairs(chars) do
        if ck == self._charKey then stillValid = true; break end
    end
    if not stillValid and #chars > 0 then
        self._charKey = chars[1]
    end

    if #chars == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["MissingNoCharacters"])
        lbl:SetFullWidth(true)
        container:AddChild(lbl)
        return
    end

    -- ---- Toolbar -----------------------------------------------------------
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetLayout("Flow")
    toolbar:SetFullWidth(true)
    container:AddChild(toolbar)

    -- Character dropdown
    local charList, charOrder = {}, {}
    local myKey = addon:GetCharacterKey()
    for _, ck in ipairs(chars) do
        local short = CharShortName(ck)
        local label = (ck == myKey)
            and (short .. " |cffaaaaaa(" .. L["You"] .. ")|r")
            or  short
        charList[ck] = label
        table.insert(charOrder, ck)
    end
    local charDD = AceGUI:Create("Dropdown")
    charDD:SetLabel(L["MissingCharacterLabel"])
    charDD:SetWidth(180)
    charDD:SetList(charList, charOrder)
    charDD:SetValue(self._charKey)
    charDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._charKey = value
        self._profId  = 0  -- reset profession when switching character
        self:Refresh()
    end)
    AttachWidgetTooltip(charDD, L["MissingCharTooltipTitle"], L["MissingCharTooltipDesc"])
    toolbar:AddChild(charDD)

    local sp1 = AceGUI:Create("Label"); sp1:SetWidth(8); toolbar:AddChild(sp1)

    -- Profession dropdown — populated from the selected char's tracked skills.
    local profIds = GetProfessionsForCharacter(self._charKey)
    if #profIds == 0 then
        -- No professions yet — show toolbar without prof dropdown, render a hint below.
        local lblProf = AceGUI:Create("Label")
        lblProf:SetText(L["MissingNoProfessions"])
        lblProf:SetFullWidth(true)
        container:AddChild(lblProf)
        return
    end

    local profList, profOrder = {}, {}
    for _, pid in ipairs(profIds) do
        profList[pid] = addon.PROF_NAMES[pid] or ("Profession " .. pid)
        table.insert(profOrder, pid)
    end
    if (self._profId == 0 or not profList[self._profId]) and #profIds > 0 then
        self._profId = profIds[1]
    end

    local profDD = AceGUI:Create("Dropdown")
    profDD:SetLabel(L["MissingProfessionLabel"])
    profDD:SetWidth(180)
    profDD:SetList(profList, profOrder)
    profDD:SetValue(self._profId)
    profDD:SetCallback("OnValueChanged", function(_w, _e, value)
        self._profId = value
        self:RefreshList()
    end)
    AttachWidgetTooltip(profDD, L["MissingProfTooltipTitle"], L["MissingProfTooltipDesc"])
    toolbar:AddChild(profDD)

    local sp2 = AceGUI:Create("Label"); sp2:SetWidth(8); toolbar:AddChild(sp2)

    -- Search box. OnTextChanged fires on every keystroke; debounce so each
    -- character typed doesn't trigger a full BuildMissingList + 100-row
    -- AceGUI redraw. Cancelling-and-rescheduling means only the final value
    -- after the user pauses ~200ms actually rebuilds.
    local search = AceGUI:Create("EditBox")
    search:SetLabel(L["MissingSearchLabel"])
    search:SetWidth(200)
    search:SetText(self._searchText)
    search:SetCallback("OnTextChanged", function(_w, _e, text)
        self._searchText = text
        if self._searchTimer then self._searchTimer:Cancel() end
        self._searchTimer = C_Timer.NewTimer(0.2, function()
            self._searchTimer = nil
            self:RefreshList()
        end)
    end)
    AttachWidgetTooltip(search, L["MissingSearchTooltipTitle"], L["MissingSearchTooltipDesc"])
    toolbar:AddChild(search)

    local sp3 = AceGUI:Create("Label"); sp3:SetWidth(8); toolbar:AddChild(sp3)

    -- Include trainer-only checkbox
    local trainCb = AceGUI:Create("CheckBox")
    trainCb:SetLabel(L["MissingIncludeTrainer"])
    trainCb:SetValue(self._includeTrainer)
    trainCb:SetWidth(160)
    trainCb:SetCallback("OnValueChanged", function(_w, _e, value)
        self._includeTrainer = value and true or false
        self:RefreshList()
    end)
    AttachWidgetTooltip(trainCb, L["MissingIncludeTrainer"], L["MissingIncludeTrainerDesc"])
    toolbar:AddChild(trainCb)

    -- Scan AH button — kicks off a throttled scan over the currently-displayed
    -- missing-recipes list. After completion, rows whose recipe scroll has
    -- live AH listings get a [AH] button (gated on AH.GetListingsFor — same
    -- pattern as [Bank] gating on Bank.GetStock). Disabled when AH is closed,
    -- displays scan progress while running. Filter changes during a scan
    -- don't affect the in-progress scan; the user can cancel and re-scan
    -- after narrowing the list to fewer items.
    addon.GUI.MakeScanAHButton({
        parent        = toolbar,
        tabName       = "missing",
        label         = L["MissingScanAH"],
        progressLabel = L["MissingScanAHProgress"],
        tooltipTitle  = L["MissingScanAH"],
        tooltipDesc   = L["MissingScanAHDesc"],
        width         = 140,
        noItemsError  = "No scannable items in the current view.",
        getItems      = function()
            -- GetItemInfo (not GetItemInfoInstant — its first return is the
            -- itemID number not the name) gives us the string name. Items
            -- not yet in the WoW cache get skipped silently; the user can
            -- re-scan after scrolling has populated more entries.
            local items = {}
            for _, entry in ipairs(self._list or {}) do
                local name = GetItemInfo and GetItemInfo(entry.spellId)
                if type(name) == "string" and name ~= "" then
                    items[#items + 1] = { itemId = entry.spellId, itemName = name }
                end
            end
            return items
        end,
        onRefresh     = function()
            if MissingRecipesTab._pool and MissingRecipesTab._scroll then
                MissingRecipesTab:UpdateVirtualRows()
            end
        end,
    })

    -- ---- Result section ----------------------------------------------------
    local section = AceGUI:Create("SimpleGroup")
    section:SetLayout("List")
    section:SetFullWidth(true)
    section:SetFullHeight(true)
    container:AddChild(section)
    self._listSection = section

    -- When section is released (tab switch / character switch / Refresh),
    -- clear our four-edge fill anchors so they don't bleed into another
    -- tab's content if AceGUI recycles this SimpleGroup. Also nil
    -- self._listSection so the leftover container.LayoutFinished hook
    -- early-returns on other tabs (BrowserTab uses the same pattern via
    -- self._scroll = nil in DestroyPool).
    section:SetCallback("OnRelease", function()
        if section.frame then section.frame:ClearAllPoints() end
        if self._listSection == section then self._listSection = nil end
    end)

    -- Pin each edge of section.frame to fill the container, AND anchor the
    -- scroll inside section to fill below the column header. Both anchors
    -- live in the same container.LayoutFinished hook because we MUST NOT
    -- override section.LayoutFinished — SimpleGroup defines a class-level
    -- LayoutFinished that auto-resizes the widget to fit its content
    -- (AceGUIContainer-SimpleGroup.lua:25), and that method lives on the
    -- widget table itself, not in widget.events. AceGUI:Release does not
    -- restore class methods on the recycled widget. So if we replace
    -- section.LayoutFinished, the override survives recycling — when the
    -- pooled SimpleGroup is acquired by e.g. Cooldowns' headers group,
    -- AceGUI's layout calls headers:LayoutFinished, hits our (now-orphaned)
    -- override which early-returns on a nil self._scroll, and the headers
    -- frame is never SetHeight'd to fit its column labels. It keeps the
    -- stale ~300px from when it was our fill-anchored section, and Flow
    -- layout positions the next sibling 300px below — the user's "huge
    -- gap." Doing all anchoring through container.LayoutFinished (TabGroup,
    -- which is not pooled across tab uses) avoids that trap entirely.
    local function AnchorAll()
        if not (self._listSection and self._listSection.frame and toolbar.frame) then return end
        local cContent = container.content or container.frame
        if not cContent then return end

        local sf = self._listSection.frame
        sf:ClearAllPoints()
        sf:SetPoint("TOP",    toolbar.frame, "BOTTOM", 0, -4)
        sf:SetPoint("LEFT",   cContent,      "LEFT",   0,  0)
        sf:SetPoint("RIGHT",  cContent,      "RIGHT",  0,  0)
        sf:SetPoint("BOTTOM", cContent,      "BOTTOM", 0,  4)

        if self._scroll and self._scroll.frame and self._headerFrame then
            local f = self._scroll.frame
            f:ClearAllPoints()
            f:SetPoint("TOP",    self._headerFrame, "BOTTOM", 0, -2)
            f:SetPoint("LEFT",   sf,                "LEFT",   0,  0)
            f:SetPoint("RIGHT",  sf,                "RIGHT",  0,  0)
            f:SetPoint("BOTTOM", sf,                "BOTTOM", 0,  4)
        end
    end
    container.LayoutFinished = function() AnchorAll() end
    self._anchorAll = AnchorAll
    AnchorAll()

    self:FillList()
end

-- ---------------------------------------------------------------------------
-- Refresh helpers
-- ---------------------------------------------------------------------------

-- Full redraw — when the character or profession set changes shape.
function MissingRecipesTab:Refresh()
    if not self._container then return end
    self._container:ReleaseChildren()
    self._listSection = nil
    self:Draw(self._container)
end

-- Light refresh — only the result list rebuilds (search, trainer toggle,
-- profession switch within the same character).
function MissingRecipesTab:RefreshList()
    if not self._listSection then return end
    self._listSection:ReleaseChildren()
    self:FillList()
end

-- ---------------------------------------------------------------------------
-- Result list — virtual-scroll using a raw frame pool (35 rows), mirroring
-- BrowserTab's pattern. AceGUI is reserved for the toolbar and a few static
-- header / count widgets above the scrollable list. Without virtual scrolling
-- a profession with several hundred missing recipes spawns thousands of
-- AceGUI widgets and the layout pass freezes the WoW client.
-- ---------------------------------------------------------------------------

-- Build the pool of POOL_SIZE raw Frames, parented to the AceGUI ScrollFrame's
-- content frame so they scroll naturally. Each pool frame holds an icon,
-- name / skill / sources fontstrings, and a small watch-toggle button. Frames
-- are reused as the user scrolls; only the content of each is updated.
function MissingRecipesTab:BuildPool(parent)
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
        nameLbl:SetWidth(240)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetWordWrap(false)
        f.nameLbl = nameLbl

        -- Skill data column shifted 5px left of name's right edge so its
        -- right-justified values align with the column header above it.
        local skillLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        skillLbl:SetPoint("LEFT", nameLbl, "RIGHT", -1, 0)
        skillLbl:SetWidth(40)
        skillLbl:SetJustifyH("RIGHT")
        skillLbl:SetTextColor(0.9, 0.9, 0.9)
        f.skillLbl = skillLbl

        -- 16px gap from the skill column matches the header's 4 + 8 spacer +
        -- 4 (Flow's default child gap) so the column edges line up.
        local srcLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        srcLbl:SetPoint("LEFT", skillLbl, "RIGHT", 16, 0)
        srcLbl:SetWidth(180)
        srcLbl:SetJustifyH("LEFT")
        srcLbl:SetWordWrap(false)
        srcLbl:SetTextColor(0.75, 0.75, 0.75)
        f.srcLbl = srcLbl

        -- [Bank] button — same pattern as BrowserTab/CooldownsTab/ShoppingListTab.
        -- Visible only when TOGBankClassic reports stock for this recipe scroll;
        -- click opens the bank-request dialog. Sized/styled to match the other
        -- [Bank] buttons across the addon for consistency. Sits to the LEFT
        -- of [AH] so the on-row order reads [Bank] [AH] left-to-right (Bank
        -- first, AH after), matching BrowserTab's reagent-row order.
        local bankBtn = CreateFrame("Button", nil, f)
        bankBtn:SetSize(50, 12)
        bankBtn:SetPoint("RIGHT", f, "RIGHT", -42, 0)  -- right edge of [Bank] sits left of [AH]
        bankBtn:SetNormalFontObject(GameFontNormalSmall)
        bankBtn:SetText("|cFF88FF88[Bank]|r")
        bankBtn:Hide()
        bankBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(bankBtn)
            GameTooltip:SetText("Request from Bank", 1, 1, 1)
            GameTooltip:AddLine("Send a request to a TOGBankClassic guild banker for this recipe scroll.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.bankBtn = bankBtn

        -- [AH] button — visible only when the AH scanner has cached listings
        -- for this recipe scroll. Click jumps the AH UI to a Browse search
        -- for the scroll's name so the user can bid/buyout from the standard
        -- Blizzard UI. Sits to the RIGHT of [Bank] so the on-row order reads
        -- [Bank] [AH] left-to-right; when only one is shown the other slot
        -- is empty (small gap acceptable since these are conditionally-
        -- visible action buttons). Width 36 fits "[AH]" comfortably.
        local ahBtn = CreateFrame("Button", nil, f)
        ahBtn:SetSize(36, 12)
        ahBtn:SetPoint("RIGHT", f, "RIGHT", -2, 0)  -- far right of the row
        ahBtn:SetNormalFontObject(GameFontNormalSmall)
        ahBtn:SetText("|cFF88CCFF[AH]|r")
        ahBtn:Hide()
        ahBtn:SetScript("OnEnter", function()
            addon.Tooltip.Owner(ahBtn)
            GameTooltip:SetText("Search Auction House", 1, 1, 1)
            GameTooltip:AddLine("Open this recipe scroll in the AH browse search.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.ahBtn = ahBtn

        -- Row-level mouse handling for hover tooltip + shift-click chat link.
        f:SetScript("OnEnter", function()
            if not f._itemId then return end
            addon.Tooltip.Owner(f)
            GameTooltip:SetItemByID(f._itemId)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["MissingRowTooltipShift"], 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" or not IsShiftKeyDown() or not f._itemId then return end
            local _, link = GetItemInfo(f._itemId)
            if link and ChatEdit_GetActiveWindow then
                local editBox = ChatEdit_GetActiveWindow()
                if editBox then editBox:Insert(link) end
            end
        end)

        self._pool[i] = f
    end
end

-- Detach the pool from a soon-to-be-released parent without throwing the
-- frames away. The ScrollFrame is released on every RefreshList; keeping the
-- pool persistent across releases avoids leaking 35 fresh CreateFrame() calls
-- per refresh (WoW frames are session-lifetime and never GC'd). Pool frames
-- get reparented onto the new ScrollFrame's content in the next FillList.
function MissingRecipesTab:DetachPool()
    if not self._pool then return end
    for _, f in ipairs(self._pool) do
        f:Hide()
        f:SetParent(UIParent)
        f:ClearAllPoints()
    end
    self._scroll = nil
    self._list   = nil
end

-- Reposition + repopulate the pool based on the current scroll offset. Only
-- runs over POOL_SIZE rows regardless of total list size — the scroll math
-- decides which slice of self._list is visible.
function MissingRecipesTab:UpdateVirtualRows()
    local scroll = self._scroll
    local list   = self._list
    if not scroll or not list or not self._pool then return end

    local status   = scroll.status or scroll.localstatus
    local offset   = (status and status.offset) or 0
    local firstIdx = math.floor(offset / ROW_HEIGHT)

    for i = 1, POOL_SIZE do
        local f       = self._pool[i]
        local listIdx = firstIdx + i
        local entry   = list[listIdx]
        if entry then
            local itemId = entry.spellId
            f._itemId = itemId

            -- Lazy item-name resolution. GetItemInfo returns nil for items
            -- not yet in the WoW cache and triggers an async load; the
            -- GET_ITEM_INFO_RECEIVED handler at the bottom of the file
            -- debounces a RefreshList so placeholders fill in once items
            -- finish loading. Bounded to POOL_SIZE rows so the cache-miss
            -- volume is small and well-behaved.
            local itemName, itemLink, itemQuality = GetItemInfo(itemId)
            local displayName = itemName or ("|cffaaaaaa#" .. itemId .. " (loading\226\128\166)|r")

            f.icon:SetTexture((GetItemIcon and GetItemIcon(itemId)) or 134400)

            local color = itemLink and itemLink:match("|c(%x%x%x%x%x%x%x%x)|H")
            if not color and itemQuality then
                local r, g, b = GetItemQualityColor(itemQuality)
                if r and g and b then
                    color = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
                end
            end
            f.nameLbl:SetText(color and ("|c" .. color .. displayName .. "|r") or displayName)

            f.skillLbl:SetText(tostring(entry.requiredSkill or ""))
            f.srcLbl:SetText(entry.sourcesText or "")

            -- [Bank] button: show only when TOGBankClassic reports stock for
            -- this recipe scroll. Click opens the request dialog with the
            -- scroll's name + link. Bank stock is queried fresh per row each
            -- pool refresh — cheap (single table walk in addon.Bank.GetStock).
            if addon.Bank and addon.Bank.GetStock(itemId) > 0 then
                local rowItemId   = itemId
                local rowItemName = itemName or ("Item #" .. itemId)
                local rowItemLink = itemLink
                f.bankBtn:SetScript("OnClick", function()
                    addon.Bank.ShowRequestDialog(rowItemId, rowItemName, rowItemLink)
                end)
                f.bankBtn:Show()
            else
                f.bankBtn:Hide()
            end

            -- [AH] button: show ONLY when a scan has found live listings for
            -- this recipe scroll, mirroring [Bank]'s "show iff stock > 0"
            -- pattern. Click jumps the AH browse search to the scroll's name
            -- so the user can bid/buy from the standard Blizzard UI. The
            -- button stays visible after the scan even if the user clicks
            -- another tab; AH.SearchFor handles "AH closed" gracefully with
            -- a chat message so a stale-results click is harmless.
            local listings = addon.AH and addon.AH.GetListingsFor(itemId)
            if listings and (listings.count or 0) > 0 and itemName then
                local rowItemName = itemName
                f.ahBtn:SetScript("OnClick", function()
                    addon.AH.SearchFor(rowItemName)
                end)
                f.ahBtn:Show()
            else
                f.ahBtn:Hide()
            end

            local y = -((listIdx - 1) * ROW_HEIGHT)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT",  scroll.content, "TOPLEFT",  0, y)
            f:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, y)
            f:Show()
        else
            f._itemId = nil
            f:Hide()
        end
    end
end

function MissingRecipesTab:FillList()
    local section = self._listSection
    if not section then return end

    -- Empty / waiting-for-pick states
    if not self._profId or self._profId == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["MissingPickProfession"])
        lbl:SetFullWidth(true)
        section:AddChild(lbl)
        return
    end

    if not (addon.recipeDB and addon.recipeDB[self._profId]) then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["MissingNoData"])
        lbl:SetFullWidth(true)
        section:AddChild(lbl)
        return
    end

    local fullList = BuildMissingList(self._charKey, self._profId, self._includeTrainer)

    -- Apply search filter using GetItemInfo — its first return IS the item
    -- name (string). NOT GetItemInfoInstant (whose first return is the
    -- itemID number, not the name — using it here previously caused
    -- "attempt to index a number value" crashes). GetItemInfo can trigger
    -- an async load for uncached items; we wrap with a type check so
    -- unloaded items get skipped from the filter rather than crashing on
    -- :lower(). As the user scrolls the list, UpdateVirtualRows calls
    -- GetItemInfo per visible row, populating the WoW item cache, so the
    -- search filter progressively matches more items as more get cached.
    local list = fullList
    local filter = (self._searchText or ""):lower()
    if filter ~= "" then
        list = {}
        for _, entry in ipairs(fullList) do
            local name = GetItemInfo and GetItemInfo(entry.spellId)
            if type(name) == "string" and name:lower():find(filter, 1, true) then
                list[#list + 1] = entry
            end
        end
    end

    self._list = list

    local brand = addon.BrandColor or "ffFF8000"

    -- Empty-state: no column headers, just the "you have everything" line.
    if #list == 0 then
        local empty = AceGUI:Create("InteractiveLabel")
        empty:SetText("|c" .. brand .. L["MissingNoneFound"] .. "|r")
        empty:SetFullWidth(true)
        section:AddChild(empty)
        return
    end

    -- Single header row that doubles as the count line — the first column
    -- shows "X Missing Recipe(s)" instead of a redundant "Recipe" title
    -- (every row IS a recipe, so the column title was tautological and
    -- visually duplicated the count line stacked above it). Column widths
    -- mirror the pool row widths in BuildPool; the 8px spacer between
    -- Skill and Sources plus the pool's 16px skill→source gap keeps the
    -- columns visually distinct.
    local noun = (#list == 1) and L["MissingCountSingular"] or L["MissingCountPlural"]
    local countText = string.format(L["MissingCountFormat"], #list, noun)

    local hdr = AceGUI:Create("SimpleGroup")
    hdr:SetLayout("Flow")
    hdr:SetFullWidth(true)
    section:AddChild(hdr)
    local function H(text, w, justifyH, tipTitle, tipDesc)
        addon.GUI.MakeColumnHeader({
            parent       = hdr,
            label        = text,
            width        = w,
            justifyH     = justifyH,
            tooltipTitle = tipTitle,
            tooltipDesc  = tipDesc,
        })
    end
    H("",                    22)
    H(countText,             240, nil,
        L["MissingHdrCountTitle"], L["MissingHdrCountDesc"])
    H(L["MissingColSkill"],  40, "RIGHT",
        L["MissingHdrSkillTitle"], L["MissingHdrSkillDesc"])
    H("",                    16)  -- 8 + 8 nudge so Sources header sits over its data column
    H(L["MissingColSource"], 180, nil,
        L["MissingHdrSourceTitle"], L["MissingHdrSourceDesc"])
    H("",                    24)

    -- Stash hdr.frame so the AnchorAll function (set on container.LayoutFinished
    -- in Draw) can reference it when anchoring scroll. We do NOT override
    -- hdr.LayoutFinished or section.LayoutFinished — see the comment in Draw
    -- for why that breaks the Cooldowns tab via SimpleGroup recycling.
    self._headerFrame = hdr.frame

    -- Virtual-scroll container. The AceGUI ScrollFrame manages the scrollbar
    -- and clipping; the raw pool inside scroll.content does the actual row
    -- rendering. OnRelease detaches the pool when the tab is switched away.
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetCallback("OnRelease", function()
        self:DetachPool()
    end)
    section:AddChild(scroll)
    self._scroll = scroll

    -- Tell the AceGUI ScrollFrame how tall the virtual content is so the
    -- scrollbar sizes correctly. Then build (or reuse) the pool and slot
    -- the visible rows in.
    scroll.content:SetHeight(#list * ROW_HEIGHT)
    if scroll.FixScroll then scroll:FixScroll() end

    if not self._pool then
        self:BuildPool(scroll.content)
    else
        -- Reparent existing pool frames onto the new scroll content (the
        -- ScrollFrame is recreated on every RefreshList).
        for _, f in ipairs(self._pool) do f:SetParent(scroll.content) end
    end

    self:UpdateVirtualRows()

    if scroll.scrollbar then
        scroll.scrollbar:SetScript("OnValueChanged", function(bar, value)
            if bar.obj and bar.obj.SetScroll then bar.obj:SetScroll(value) end
            self:UpdateVirtualRows()
        end)
    end

    -- Apply scroll anchor now that self._scroll and self._headerFrame are set.
    -- AceGUI will also re-fire container.LayoutFinished as part of section's
    -- own resize cascade, but doing it here means the first paint is correct
    -- without waiting for the next layout pass.
    if self._anchorAll then self._anchorAll() end
end

-- ---------------------------------------------------------------------------
-- Lazy item-name fill-in
-- ---------------------------------------------------------------------------
-- The render path uses placeholder text for any row whose item isn't in the
-- WoW item cache yet. As GET_ITEM_INFO_RECEIVED events fire (one per item
-- that finishes loading), we coalesce them into a single delayed pool refill
-- so visible rows update once after the burst settles — debounced so a flood
-- of cache fills doesn't trigger N redraws. We call UpdateVirtualRows (just
-- repopulates the existing 35 frames) instead of RefreshList (which would
-- tear down and rebuild the AceGUI ScrollFrame) so the cost is bounded to
-- the visible slice. Handler early-outs unless the missing-recipes tab is
-- the active tab and has a live pool, so it costs nothing while closed.
Ace:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if not MissingRecipesTab._pool or not MissingRecipesTab._scroll then return end
    local mw = addon.MainWindow
    if not (mw and mw.activeTab == "missing") then return end
    if MissingRecipesTab._refreshTimer then
        MissingRecipesTab._refreshTimer:Cancel()
    end
    MissingRecipesTab._refreshTimer = C_Timer.NewTimer(0.5, function()
        MissingRecipesTab._refreshTimer = nil
        if MissingRecipesTab._pool and MissingRecipesTab._scroll then
            MissingRecipesTab:UpdateVirtualRows()
        end
    end)
end)

-- Refresh the scan button label whenever the AH opens or closes (it
-- enables/disables based on AH availability). Also refresh pool rows so
-- the [AH] button visibility (gated on cached scan results) correctly
-- clears when the AH closes — addon.AH wipes its results on close, so
-- without this the [AH] buttons would linger on rows until the next
-- pool refresh.
-- (Removed: per-tab AH_OPEN_STATE_CHANGED / AH_SCAN_COMPLETE handlers.
-- The shared addon.GUI.MakeScanAHButton factory in GUI/SharedWidgets.lua
-- owns one global handler that refreshes the active tab's scan button
-- and runs the tab's onRefresh hook — for missing, that hook calls
-- UpdateVirtualRows so [AH] buttons appear/disappear with scan results.)
