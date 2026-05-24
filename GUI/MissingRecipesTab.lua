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
-- client (Jewelcrafting on Vanilla, Inscription on Vanilla / TBC) is
-- hidden even if the character somehow has stale skill data for it cached.

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
    -- No source data at all → the recipe is in the universe (wago.tools knows
    -- about it) but no emulator we ship from catalogs where it comes from.
    -- Surface it with an explicit "Unknown" tag so the user still sees the
    -- recipe is missing and can look it up externally. Used heavily for
    -- MoP-introduced recipes since we don't have a MoP emulator source yet.
    if not srcEntry then return L["MissingSrcUnknown"] end
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
    -- srcEntry exists but every kind in it is filtered (e.g. trainer-only
    -- with the toggle off): fall through to "Unknown" so the row still
    -- displays something rather than an empty cell.
    if #parts == 0 then return L["MissingSrcUnknown"] end
    return table.concat(parts, ", ")
end

local function CharShortName(charKey)
    return charKey:match("^([^%-]+)") or charKey
end

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

-- Return list of charKeys that belong to this account and have any tracked
-- profession data, regardless of which guild bucket the data lives in. The
-- currently-logged-in toon is always included even if it has not opened a
-- trade-skill window yet.
local function GetCharactersWithProfessions()
    local list, seen = {}, {}
    addon:ForEachGuildBucket(function(bucket)
        if not bucket.skills then return end
        for charKey, profMap in pairs(bucket.skills) do
            if not seen[charKey]
               and addon:IsMyCharacter(charKey)
               and profMap and next(profMap) then
                table.insert(list, charKey)
                seen[charKey] = true
            end
        end
    end)
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
    local bucket = addon:FindBucketForChar(charKey, "skills")
    if not bucket then return {} end
    local out = {}
    for profId in pairs(bucket.skills[charKey]) do
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

-- Skill cap each rank-up book grants. Used to filter rank books out of
-- the missing list when the character's skillMax is already at or above
-- that cap — the only way the character could have raised their cap
-- past a rank's threshold is to have consumed the book. There's no WoW
-- API to detect "did the player use this item" so skillMax is the proxy.
--
-- Currently only Cooking, First Aid, and Fishing have rank-book entries
-- in our static recipe DB (other professions advance via trainer); the
-- map is exhaustive across all expansion ranks anyway in case future
-- data files add more.
local RANK_CAPS = {
    ["Journeyman"]               = 150,
    ["Expert"]                   = 225,
    ["Artisan"]                  = 300,
    ["Master"]                   = 375,
    ["Grand Master"]             = 450,
    ["Illustrious Grand Master"] = 525,
    ["Zen Master"]               = 600,
}

-- Build the missing-recipe list for (charKey, profId). Returns the full
-- unfiltered set sorted by required skill — search filtering is applied at
-- render time via GetItemInfoInstant (which does NOT trigger an async load),
-- and the row count is capped during render. Item-name resolution itself
-- happens per-row inside FillList so we only ever pay for the visible slice.
local function BuildMissingList(charKey, profId, includeTrainer)
    if not charKey or not profId or profId == 0 then return {} end
    local recipes = addon.recipeDB and addon.recipeDB[profId]
    if not recipes then return {} end

    -- Hoist sources / spec lookups out of the per-recipe loop.
    local sources     = (addon.sourceDB and addon.sourceDB[profId]) or {}

    -- Pre-build a set of every spell-id the character is known to craft for
    -- this profession. There are TWO independent reasons the previous
    -- per-call lookup `bucket.recipes[profId][recipeId]` returned false for
    -- recipes the player actually knew:
    --
    --   1. (v0.4.7 fix) cross-bucket scatter: a character's scanned recipes
    --      live in whichever guild bucket was active at scan time, which
    --      may not be the bucket their skills are cached in. We walk all
    --      buckets here.
    --
    --   2. (v0.5.0 fix) keyspace mismatch: Scanner:ScanTradeSkill at
    --      Scanner.lua:776 stores each recipe row keyed by what
    --      ExtractTradeSkillId returns, which is the SPELL id for Enchanting
    --      (whose recipe links carry enchant:SPELLID) but the CRAFTED ITEM
    --      id for every other profession (whose links carry item:ITEMID for
    --      the produced item). Meanwhile our v0.5.0 recipeDB is uniformly
    --      keyed by recipe SPELL id (from wago.tools SkillLineAbility.Spell).
    --      A direct `profRecipes[spellId]` lookup misses every non-Enchanting
    --      recipe because the stored key is the item id, not the spell id.
    --      Scanner DOES populate rd.spellId as a field on every entry (line
    --      743 + 856 — looked up via spellNameCache during the scan), so we
    --      index both the table KEY and the rd.spellId FIELD into one set.
    --      Lookup against that set is O(1) and works for all professions.
    local knownSpells = {}
    for _, bucket in pairs(addon.guildDb.global.guilds or {}) do
        local profRecipes = bucket.recipes and bucket.recipes[profId]
        if profRecipes then
            for recipeKey, rd in pairs(profRecipes) do
                if rd and rd.crafters and rd.crafters[charKey] then
                    -- Index the table key (Enchanting hits via this path).
                    knownSpells[recipeKey] = true
                    -- Also index by the stored spellId field if present
                    -- (non-Enchanting professions hit via this path because
                    -- the table key is the crafted item id, not the spell).
                    if rd.spellId then
                        knownSpells[rd.spellId] = true
                    end
                end
            end
        end
    end
    local function knownByChar(recipeId)
        return knownSpells[recipeId] == true
    end

    -- skillMax for the rank-book filter below — also walks all buckets and
    -- takes the maximum value, for the same reason as knownByChar. The
    -- specialisations lookup uses the bucket where the char's skills live
    -- (specialisations are stored alongside skills by the scanner, so they
    -- share the same bucket).
    local skillMax = 0
    for _, bucket in pairs(addon.guildDb.global.guilds or {}) do
        local se = bucket.skills and bucket.skills[charKey] and bucket.skills[charKey][profId]
        if se and (se.skillMax or 0) > skillMax then
            skillMax = se.skillMax
        end
    end
    local skillsBucket = addon:FindBucketForChar(charKey, "skills")
    local specs       = skillsBucket and skillsBucket.specializations and skillsBucket.specializations[charKey]
    local playerSpec  = specs and specs[profId]

    local out = {}

    -- Per-client max profession skill. Our shipped recipeDB is a UNION across
    -- every expansion's data (one Data/Recipes/*.lua file is loaded by every
    -- TOC variant), so a TBC Anniversary player would otherwise see MoP-
    -- introduced recipes that require ~600 skill — recipes they can never
    -- learn on their client. Filter on requiredSkill > this cap so each
    -- client only surfaces recipes within reach of its own progression.
    --
    -- Caps are identical across the crafting + secondary professions per
    -- expansion (Vanilla 300, TBC 375, Wrath 450, Cata 525, MoP 600). When
    -- the client's expansion can't be identified, default to MoP's cap (no
    -- filtering) so we degrade to showing everything rather than hiding
    -- recipes we shouldn't.
    local clientMaxSkill
    if     addon.isVanilla then clientMaxSkill = 300
    elseif addon.isTBC     then clientMaxSkill = 375
    elseif addon.isWrath   then clientMaxSkill = 450
    elseif addon.isCata    then clientMaxSkill = 525
    elseif addon.isMoP     then clientMaxSkill = 600
    else                        clientMaxSkill = 600
    end

    for spellId, data in pairs(recipes) do
        local skip = false
        if data.requiredSkill and data.requiredSkill > clientMaxSkill then
            -- Recipe is from a future expansion the current client can't
            -- support. Hide it; the player will see it once they're on a
            -- later TOC variant.
            skip = true
        elseif data.specialization and data.specialization ~= playerSpec then
            skip = true
        elseif data.season then
            skip = true
        elseif knownByChar(spellId) then
            skip = true
        elseif data.teaches and data.teaches ~= spellId and knownByChar(data.teaches) then
            skip = true
        elseif type(data.teaches) == "string" and RANK_CAPS[data.teaches] then
            -- Rank-up book (e.g. "Expert First Aid" raises max from 150
            -- to 225, "Artisan First Aid" from 225 to 300). The character's
            -- skillMax is the only proxy we have for "did they consume
            -- this book" — there's no WoW API to detect that. If their
            -- skillMax is already at or above the rank's cap they must
            -- have used the book to get there.
            if skillMax >= RANK_CAPS[data.teaches] then
                skip = true
            end
        end

        if not skip then
            local srcEntry = sources[spellId]
            -- v0.5.0: surface every recipe in the universe, even those without
            -- a known source entry. Previously we filtered out anything without
            -- a srcEntry on the assumption that the recipe wasn't actually
            -- obtainable; v0.5.0's authoritative recipeDB makes that assumption
            -- wrong (we know the recipe exists from Blizzard's DBC even when
            -- no emulator catalogs the NPC). Show the row anyway with an
            -- "Unknown" source tag (handled in FormatSources). Users still get
            -- the value of "I'm missing this recipe" even when we can't tell
            -- them where to get it. This is the main lever closing the
            -- visibility gap on MoP-introduced recipes for now.
            --
            -- The includeTrainer toggle still hides recipes whose ONLY known
            -- source is a trainer — those add noise to the "AH-hunting"
            -- workflow the tab is built around (a trainer is always
            -- available). The toggle is unchanged in scope and effect.
            local isTrainerOnly = srcEntry and not HasNonTrainerSource(srcEntry)
            if isTrainerOnly and not includeTrainer then
                -- skip — trainer-only entries are hidden when the toggle is off
            else
                table.insert(out, {
                    spellId       = spellId,
                    itemId        = data.itemId,  -- recipe-scroll item id (nil for trainer-only)
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
            -- re-scan after scrolling has populated more entries. Trainer-
            -- only recipes (entry.itemId == nil) have no scroll item and
            -- can't be auctioned, so we skip them here.
            local items = {}
            for _, entry in ipairs(self._list or {}) do
                local iid = entry.itemId
                if iid then
                    local name = GetItemInfo and GetItemInfo(iid)
                    if type(name) == "string" and name ~= "" then
                        items[#items + 1] = { itemId = iid, itemName = name }
                    end
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
        -- Item-id path renders the recipe-scroll tooltip (reagents, prof
        -- requirement). For trainer-only recipes (no scroll item exists),
        -- fall back to the spell tooltip so the row still has SOMETHING on
        -- hover instead of nothing — and so we never pass nil into
        -- SetItemByID (Blizzard silently sets an empty tooltip, but
        -- addons that hook SetItemByID such as LoonBestInSlot then crash
        -- on the empty state).
        f:SetScript("OnEnter", function()
            if not (f._itemId or f._spellId) then return end
            addon.Tooltip.Owner(f)
            -- Decide between item tooltip and spell tooltip. Item is
            -- preferred (shows reagents + profession requirement) but
            -- ONLY when the item is already in the WoW client's cache.
            -- Calling GameTooltip:SetItemByID on a cache-cold item ID
            -- silently sets an empty tooltip on our side, but LoonBestInSlot
            -- (and other addons that hook SetItemByID via AceHook) then
            -- read back nil from GameTooltip:GetItem() and crash trying to
            -- ContinueOnItemLoad(nil). GetItemInfo doubles as the
            -- cache-presence check and the async cache load trigger: nil
            -- return means not cached, but the call queues the fetch so
            -- the NEXT mouseover succeeds.
            local useItem = false
            if f._itemId and GetItemInfo then
                local cachedName = GetItemInfo(f._itemId)
                useItem = cachedName ~= nil
            end
            if useItem then
                GameTooltip:SetItemByID(f._itemId)
            elseif f._spellId and GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(f._spellId)
            else
                local name = (f._spellId and GetSpellInfo and GetSpellInfo(f._spellId))
                             or (f._itemId and ("Item #" .. f._itemId))
                             or "?"
                GameTooltip:SetText(name, 1, 1, 1, 1, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["MissingRowTooltipShift"], 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" or not IsShiftKeyDown() then return end
            local link
            if f._itemId then
                _, link = GetItemInfo(f._itemId)
            elseif f._spellId and GetSpellLink then
                link = GetSpellLink(f._spellId)
            end
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
    addon.GUI.DetachPool(self._pool)
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
            -- v0.5.0 keyed recipeDB by spell id; the row's entry.itemId is the
            -- recipe-scroll item that teaches the spell (when one exists —
            -- trainer-taught recipes have no scroll item). Use entry.itemId
            -- for any item-id API call (GameTooltip:SetItemByID, GetItemInfo,
            -- GetItemIcon, GetItemQualityColor). When nil, fall back to
            -- spell-based display via GetSpellInfo. Never pass the spell id
            -- to item APIs — silently sets an empty tooltip and (worse)
            -- breaks downstream addons like LoonBestInSlot that hook
            -- SetItemByID and then crash on the empty result.
            local itemId = entry.itemId
            f._itemId = itemId
            f._spellId = entry.spellId

            local displayName, itemName, itemLink, itemQuality
            if itemId then
                -- Lazy item-name resolution. GetItemInfo returns nil for
                -- items not yet in the WoW cache and triggers an async
                -- load; the GET_ITEM_INFO_RECEIVED handler debounces a
                -- RefreshList so placeholders fill in once items finish
                -- loading. Bounded to POOL_SIZE rows so the cache-miss
                -- volume stays small. When the item never resolves (some
                -- recipe items legitimately don't exist on the current
                -- client even after expansion-cap filtering — e.g. Vanilla
                -- recipes whose scroll items were removed from the game),
                -- fall back to the spell name + icon so the row still
                -- shows SOMETHING meaningful instead of a permanent
                -- "#22430 (loading…)" placeholder.
                itemName, itemLink, itemQuality = GetItemInfo(itemId)
                if itemName then
                    displayName = itemName
                    f.icon:SetTexture((GetItemIcon and GetItemIcon(itemId)) or 134400)
                else
                    -- Item not in cache yet OR item id genuinely doesn't
                    -- exist on this client. Show the spell name as the
                    -- visible label; if the item later loads, the cache
                    -- event triggers a refresh and we render properly.
                    local spellName = (GetSpellInfo and GetSpellInfo(entry.spellId))
                                      or (entry.name)
                    displayName = spellName
                                  or ("|cffaaaaaa#" .. itemId .. " (loading\226\128\166)|r")
                    local spellIcon = GetSpellTexture and GetSpellTexture(entry.spellId)
                    f.icon:SetTexture(spellIcon or 134400)
                end
            else
                -- Trainer-only recipe with no scroll item. Fall back to the
                -- spell's name + icon. No item link / quality colour
                -- available — recipes are uncoloured in this branch.
                local spellName = (GetSpellInfo and GetSpellInfo(entry.spellId))
                                  or (entry.name)
                                  or ("|cffaaaaaaspell:" .. entry.spellId .. "|r")
                displayName = spellName
                local spellIcon = GetSpellTexture and GetSpellTexture(entry.spellId)
                f.icon:SetTexture(spellIcon or 134400)
            end

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
            -- Trainer-only recipes (itemId == nil) have no scroll to bank.
            if itemId and addon.Bank and addon.Bank.GetStock(itemId) > 0 then
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
            -- a chat message so a stale-results click is harmless. Trainer-
            -- only recipes (itemId == nil) have no scroll to find on the AH.
            local listings = itemId and addon.AH and addon.AH.GetListingsFor(itemId)
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
            -- Search both the recipe-scroll item name (when one exists) AND
            -- the spell name as a fallback. The OR keeps trainer-only
            -- recipes searchable by their spell name even though they have
            -- no scroll item; lets the user find e.g. "Brown Linen Vest"
            -- regardless of whether the recipe is taught by a pattern or
            -- only by a trainer.
            local name = (entry.itemId and GetItemInfo and GetItemInfo(entry.itemId))
                         or (GetSpellInfo and GetSpellInfo(entry.spellId))
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
    -- rendering. Shared PersistentScroll helper captures the saved scroll
    -- position so sync-triggered Refresh / RefreshList rebuilds don't yank
    -- the user back to the top mid-scroll (matches the BrowserTab and
    -- CooldownsTab fixes from v0.3.5).
    local scroll, savedScroll = addon.GUI.PersistentScroll.Acquire(self, {
        layout     = "List",
        fullWidth  = true,
        fullHeight = true,
        onRelease  = function() self:DetachPool() end,
    })
    section:AddChild(scroll)
    self._scroll = scroll

    -- Virtual-scroll trick (matches BrowserTab:FillList): install a no-op
    -- LayoutFinished on the scroll instance so AceGUI's class default
    -- doesn't overwrite our manual content.height. Required because
    -- FixScroll calls DoLayout on every scrollbar visibility transition
    -- (AceGUIContainer-ScrollFrame.lua:108/118), and DoLayout fires the
    -- "List" layout function which calls scroll.LayoutFinished(_, _, 0)
    -- when scroll.children is empty (Missing parents raw frames to
    -- scroll.content directly, so AceGUI sees no children). The class
    -- default would then set content:SetHeight(0 or 20) — collapsing
    -- our virtual list to 0 px and hiding every row. Pre-v0.4.0 this
    -- silently worked because BrowserTab's no-op override leaked through
    -- the shared AceGUI ScrollFrame pool; Missing was free-riding on
    -- it. PersistentScroll.Acquire now restores the class default on
    -- every acquire (so Cooldowns' AceGUI-children auto-size works
    -- correctly), so Missing has to install its own no-op explicitly.
    scroll.LayoutFinished = function() end

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

    -- Restore saved scroll position now that content height + scrollbar
    -- are wired up. afterFn re-positions the raw-frame pool to the
    -- restored offset (without it, the scrollbar shows the right value
    -- but the rows underneath stay anchored to row 0).
    addon.GUI.PersistentScroll.Restore(scroll, savedScroll, function()
        self:UpdateVirtualRows()
    end)

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
