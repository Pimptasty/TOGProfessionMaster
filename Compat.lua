-- TOG Profession Master — Compatibility shims
-- Loaded immediately after TOGProfessionMaster.lua.
-- Sets version flags and wraps APIs that differ across Classic versions so
-- no other module ever needs to branch on C_Container, C_AddOns, etc.

local _, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Version flags
-- Detected once at load time from GetBuildInfo().
-- Other modules read e.g. `addon.isVanilla` directly.
-- ---------------------------------------------------------------------------
local build = select(4, GetBuildInfo())  -- integer, e.g. 11508, 20504, 30403 …

addon.isVanilla = (build >= 11000 and build < 20000)
addon.isTBC     = (build >= 20000 and build < 30000)
addon.isWrath   = (build >= 30000 and build < 40000)
addon.isCata    = (build >= 40000 and build < 50000)
addon.isMoP     = (build >= 50000 and build < 60000)

-- Max profession skill for this expansion (Vanilla 300 / TBC 375 / Wrath 450 /
-- Cata 525 / MoP 600). Used as the authoritative "out of N" cap on skill readouts
-- so a stale or missing skillMax never renders a wrong cap like "375/300". A
-- per-expansion constant, not a PDB lookup: PDB ships recipes (not caps) and has
-- nothing for gathering professions, whereas the cap is uniform across every
-- profession in an expansion.
addon.SKILL_CAP =
    addon.isMoP     and 600 or
    addon.isCata    and 525 or
    addon.isWrath   and 450 or
    addon.isTBC     and 375 or
    300  -- Vanilla / Classic Era

-- Classic Era / Vanilla has no timeline-based expansion at all.
-- `addon.isClassic` is true for vanilla-protocol builds (Classic Era, Anniversary).
addon.isClassic = addon.isVanilla

-- Season of Discovery runs on the same Vanilla (1.15) client/build as Era,
-- Hardcore and Anniversary, so the build number can't tell them apart — but SoD
-- is the only one with the rune-engraving system enabled. Live check (engraving
-- state is reliable after login); used to gate SoD-only recipes that the shared
-- 1.15 client tables (and thus LibProfessionDB's Vanilla set) carry but regular
-- Era/HC/Anniversary realms can't learn.
function addon:IsSoD()
    return (C_Engraving and C_Engraving.IsEngravingEnabled and C_Engraving.IsEngravingEnabled()) and true or false
end

-- ---------------------------------------------------------------------------
-- Bag / container API
-- GetContainerItemInfo signature also changed, so we normalise the return
-- into a plain table: { texture, count, locked, quality, readable,
--                       lootable, link, filtered, noValue, itemId }
-- ---------------------------------------------------------------------------
-- Which branch actually runs: the C_Container one, on EVERY flavour this addon
-- supports. Checked against Blizzard's per-flavour source rather than assumed —
-- classic_era, classic_anniversary and classic (Cata/MoP) each ship
-- ContainerDocumentation.lua defining the namespace, each has zero bare
-- GetContainerItemInfo call sites under Interface/, and none of them has a
-- deprecation fallback file for the container family (unlike Item and
-- SpellBook, which do). The else branch below is kept as insurance for a build
-- I cannot check, but nothing reaches it today — so do not treat it as the
-- Classic path, and do not put a fix there expecting players to get it.
if C_Container and C_Container.GetContainerItemInfo then
    -- Every supported client takes this branch.
    function addon:GetContainerItemInfo(bag, slot)
        return C_Container.GetContainerItemInfo(bag, slot)
    end
    function addon:GetContainerNumSlots(bag)
        return C_Container.GetContainerNumSlots(bag)
    end
    function addon:GetContainerItemLink(bag, slot)
        return C_Container.GetContainerItemLink(bag, slot)
    end
    function addon:GetNumBagSlots()
        return NUM_BAG_SLOTS or 4
    end
else
    -- Unreachable on every live flavour (see the note above). Kept, not trusted.
    function addon:GetContainerItemInfo(bag, slot)
        local texture, count, locked, quality, readable,
              lootable, link, filtered, noValue, itemId =
              GetContainerItemInfo(bag, slot)
        if not texture then return nil end
        -- Older Classic/TBC builds return only the first 7 values here (no itemID),
        -- so `itemId` comes back nil. Callers that key on .itemID — e.g. the cooldown
        -- supply-mail bag scan (CdMail_CountItemInBags) — then match nothing and report
        -- "you have no <item> in your bags" even when you do. Derive the id from the
        -- item link so .itemID is always populated on every supported client.
        if not itemId and link then
            itemId = tonumber(link:match("item:(%d+)"))
        end
        return {
            iconFileID  = texture,
            stackCount  = count,
            isLocked    = locked,
            quality     = quality,
            isReadable  = readable,
            hasLoot     = lootable,
            hyperlink   = link,
            isFiltered  = filtered,
            hasNoValue  = noValue,
            itemID      = itemId,
        }
    end
    function addon:GetContainerNumSlots(bag)
        return GetContainerNumSlots(bag)
    end
    function addon:GetContainerItemLink(bag, slot)
        return GetContainerItemLink(bag, slot)
    end
    function addon:GetNumBagSlots()
        return NUM_BAG_SLOTS or 4
    end
end

--- Every item in the player's bags as { [itemId] = count }.
---
--- Lives here, next to the container shims it is built from, because it was
--- previously written out twice — `ScanBags` in GUI/ShoppingListTab.lua and
--- `ScanBagsOnly` in Modules/ReagentWatch.lua — with byte-identical bodies on
--- opposite sides of the GUI/Modules layer boundary. Two owners for one rule,
--- and in particular two places to remember the `info.itemID or info.itemId`
--- shim, which exists because the two GetContainerItemInfo branches above
--- spell the field differently.
function addon:ScanBagCounts()
    local counts = {}
    for bag = 0, self:GetNumBagSlots() do
        for slot = 1, self:GetContainerNumSlots(bag) do
            local info = self:GetContainerItemInfo(bag, slot)
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

-- ---------------------------------------------------------------------------
-- AddOn loaded check
-- The C_AddOns branch is the one that runs, on every flavour this addon
-- supports — not just retail, as this comment used to claim. Classic Era ships
-- C_AddOns.IsAddOnLoaded and has ZERO bare call sites for the old global under
-- Interface/, so the `or IsAddOnLoaded` tail is a fallback for a client I cannot
-- point at. Kept, not relied on.
-- ---------------------------------------------------------------------------
local _IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

function addon:IsAddOnLoaded(name)
    return _IsAddOnLoaded(name)
end

-- ---------------------------------------------------------------------------
-- GetAddOnMetadata
-- Same split as above.
-- ---------------------------------------------------------------------------
addon.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- ---------------------------------------------------------------------------
-- Spell info
-- GetSpellInfo was split into multiple C_Spell.* calls on retail 10.1 but the
-- old signature still works on all Classic builds, so no shim needed yet.
-- This placeholder keeps the pattern consistent if it ever changes.
-- ---------------------------------------------------------------------------
function addon:GetSpellInfo(spellId)
    return GetSpellInfo(spellId)
end

-- ---------------------------------------------------------------------------
-- Item info (no API change on Classic — plain wrapper for consistency)
-- ---------------------------------------------------------------------------
function addon:GetItemInfo(itemId)
    return GetItemInfo(itemId)
end

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Tooltip anchor helper
-- Always use this instead of a raw GameTooltip:SetOwner call.
-- Anchors below the frame when in the top half of the screen (BOTTOMLEFT),
-- above when in the bottom half (TOPLEFT), so it never clips off screen.
-- ---------------------------------------------------------------------------
addon.Tooltip = {}

function addon.Tooltip.Owner(frame)
    local _, y = frame:GetCenter()
    local anchor = (y and y > GetScreenHeight() / 2) and "ANCHOR_BOTTOMLEFT" or "ANCHOR_TOPLEFT"
    GameTooltip:SetOwner(frame, anchor)
end

--- Anchor an arbitrary frame relative to a source row using the same
--- screen-half logic as Tooltip.Owner — popup appears just below the source
--- when the source is in the top half of the screen, just above when in the
--- bottom half.  Use this for click-popups (transmute group expansion, etc.)
--- so they sit adjacent to the row that opened them and the user can mouse
--- onto the popup without losing context.  Accepts either a raw Frame or an
--- AceGUI widget (unwraps via the widget's .frame member).
function addon.Tooltip.AnchorFrame(frame, source)
    -- Unwrap AceGUI widgets — they aren't Frames themselves; the underlying
    -- frame is at widget.frame.  Raw Frames have GetCenter directly.
    local sourceFrame = source.GetCenter and source or source.frame
    if not sourceFrame or not sourceFrame.GetCenter then return end
    frame:ClearAllPoints()
    local _, y = sourceFrame:GetCenter()
    if y and y > GetScreenHeight() / 2 then
        -- Source in upper half: place popup below source.
        frame:SetPoint("TOPLEFT", sourceFrame, "BOTTOMLEFT", 0, 0)
    else
        -- Source in lower half: place popup above source.
        frame:SetPoint("BOTTOMLEFT", sourceFrame, "TOPLEFT", 0, 0)
    end
end

-- TOGBankClassic integration helpers
-- Shared by BrowserTab and CooldownsTab (and any future caller).
-- All three functions are no-ops when TOGBankClassic is not loaded.
-- ---------------------------------------------------------------------------
addon.Bank = {}

--- Returns the total item count held across all banker alts.
function addon.Bank.GetStock(itemId)
    local TOG = _G["TOGBankClassic_Guild"]
    if not TOG or not TOG.Info or not TOG.Info.alts then return 0 end
    local total = 0
    for _, alt in pairs(TOG.Info.alts) do
        for _, entry in ipairs(alt.items or {}) do
            if entry.ID == itemId then
                total = total + (entry.Count or 0)
            end
        end
    end
    return total
end

--- Returns sorted array of { name, count } for bankers that hold itemId.
-- The per-banker count SUMS every matching entry, because a bank holds an item
-- as one entry per stack -- 60 Copper Bars in a 20-stack bank is three entries,
-- not one. Taking the first match and breaking (what this did until v1.0.7)
-- under-reported every multi-stack reagent, which is most of them. It was wrong
-- in two visible places: the tooltip's "Bankers:" count, and `ShowRequestDialog`,
-- which sums these counts into `totalStock` and caps `maxRequestable` from it --
-- so a player could not request more than the first stack. `GetStock` above and
-- TOGBankClassic's own renderer both sum; this is the one that disagreed.
function addon.Bank.GetBanksWithItem(itemId)
    local TOG = _G["TOGBankClassic_Guild"]
    if not TOG then return {} end
    local banks = TOG:GetBanks()
    if not banks or #banks == 0 then return {} end
    local alts   = TOG.Info and TOG.Info.alts or {}
    local result = {}
    for _, bankName in ipairs(banks) do
        local alt = alts[bankName]
        if alt and alt.items then
            local total = 0
            for _, entry in ipairs(alt.items) do
                if entry.ID == itemId then
                    total = total + (entry.Count or 0)
                end
            end
            if total > 0 then
                table.insert(result, { name = bankName, count = total })
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--- Returns true if charKey belongs to a TOGBankClassic banker alt.
-- Delegates to TOGBankClassic's own canonical check (`TOG:IsBank`) which
-- normalizes the input via `NormalizeName` and does an O(1) memberRoster
-- lookup. Earlier rolling-our-own implementation that walked `GetBanks()`
-- and string-compared against `charKey:match("^([^-]+)")` was broken on
-- connected-realm guilds: `GetBanks()` returns `member.name` from the
-- guild roster, which is `"Name-Realm"` on cross-realm clusters, while
-- our short-name match stripped the realm — so no entry ever matched
-- and every banker fell through as non-banker. `TOG:IsBank` accepts
-- any format and handles normalization itself.
-- Returns false when TOGBank isn't loaded so callers degrade gracefully.
function addon.Bank.IsBanker(charKey)
    if type(charKey) ~= "string" then return false end
    local TOG = _G["TOGBankClassic_Guild"]
    if not TOG or not TOG.IsBank then return false end
    return TOG:IsBank(charKey)
end

-- Persistent bank-request dialog shared across all UI callers (lazy-created).
local _bankDialog

--- Open the "Request from Guild Bank" dialog.
-- itemId   numeric item ID
-- itemName display name (used in the request payload)
-- itemLink full hyperlink (shown in the dialog; may be nil)
function addon.Bank.ShowRequestDialog(itemId, itemName, itemLink, anchorBelow)
    local TOG = _G["TOGBankClassic_Guild"]
    if not TOG then return end

    local banksWithItem = addon.Bank.GetBanksWithItem(itemId)
    if #banksWithItem == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFDA8CFF[TOGPM]|r No bankers currently have this item in stock.")
        return
    end

    local totalStock = 0
    for _, b in ipairs(banksWithItem) do totalStock = totalStock + b.count end

    local opts = _G["TOGBankClassic_Options"]
    local pct  = (opts and opts.GetMaxRequestPercent and opts:GetMaxRequestPercent()) or 100
    local maxRequestable = math.max(1, math.floor(totalStock * pct / 100))
    local defaultQty     = math.min(1, maxRequestable)

    if not _bankDialog then
        local d = CreateFrame("Frame", "TOGPMBankRequestDialog", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        d:SetSize(280, 165)
        d:SetFrameStrata("DIALOG")
        d:SetMovable(true)
        d:EnableMouse(true)
        d:RegisterForDrag("LeftButton")
        d:SetScript("OnDragStart", function(f) f:StartMoving() end)
        d:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
        if d.SetBackdrop then
            d:SetBackdrop({
                bgFile   = [[Interface\DialogFrame\UI-DialogBox-Background]],
                edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        table.insert(UISpecialFrames, "TOGPMBankRequestDialog")

        local titleText = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", 0, -16)
        titleText:SetText(L["BankDialogTitle"])

        local closeBtn = CreateFrame("Button", nil, d, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function() d:Hide() end)

        local itemBtn = CreateFrame("Button", nil, d)
        itemBtn:SetPoint("TOPLEFT",  18, -36)
        itemBtn:SetPoint("TOPRIGHT", -18, -36)
        itemBtn:SetHeight(16)
        local itemLbl = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemLbl:SetAllPoints()
        itemLbl:SetJustifyH("LEFT")
        itemBtn:SetScript("OnEnter", function()
            if d.currentItemLink then
                addon.Tooltip.Owner(itemBtn)
                addon.ItemLink.SetItem(GameTooltip, d.currentItemLink)
                GameTooltip:Show()
            end
        end)
        itemBtn:SetScript("OnLeave", function()
            addon.ItemLink.EndHover(GameTooltip)
            GameTooltip:Hide()
        end)
        -- Was a bare ChatEdit_InsertLink, which is deaf to a rebound CHATLINK
        -- modifier and offers no ctrl-click dressing room.
        itemBtn:SetScript("OnClick", function()
            addon.ItemLink.Click(d.currentItemLink)
        end)
        d.itemLbl = itemLbl

        local stockLbl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        stockLbl:SetPoint("TOPLEFT", 18, -52)
        stockLbl:SetTextColor(0.6, 0.6, 0.6)
        d.stockLbl = stockLbl

        local bankLbl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bankLbl:SetPoint("TOPLEFT", 18, -70)
        bankLbl:SetText(L["BankDialogBanker"])
        bankLbl:SetTextColor(0.8, 0.8, 0.8)
        d.bankLbl = bankLbl

        local bankDisplay = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bankDisplay:SetPoint("LEFT", bankLbl, "RIGHT", 6, 0)
        bankDisplay:SetJustifyH("LEFT")
        d.bankDisplay = bankDisplay

        local bankDropdown = CreateFrame("Frame", "TOGPMBankRequestDropdown", d, "UIDropDownMenuTemplate")
        bankDropdown:SetPoint("LEFT", bankLbl, "RIGHT", -10, -2)
        UIDropDownMenu_SetWidth(bankDropdown, 150)
        d.bankDropdown = bankDropdown

        local qtyLbl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qtyLbl:SetPoint("TOPLEFT", 18, -102)
        qtyLbl:SetText(L["BankDialogQty"])
        qtyLbl:SetTextColor(0.8, 0.8, 0.8)

        local qtyBox = CreateFrame("EditBox", "TOGPMBankQtyBox", d, "InputBoxTemplate")
        qtyBox:SetSize(50, 20)
        qtyBox:SetPoint("LEFT", qtyLbl, "RIGHT", 6, 0)
        qtyBox:SetAutoFocus(false)
        qtyBox:SetNumeric(true)
        qtyBox:SetMaxLetters(5)
        d.qtyBox = qtyBox

        local maxLbl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        maxLbl:SetPoint("LEFT", qtyBox, "RIGHT", 8, 0)
        maxLbl:SetTextColor(0.6, 0.6, 0.6)
        d.maxLbl = maxLbl

        local sendBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
        sendBtn:SetSize(120, 22)
        sendBtn:SetPoint("BOTTOMLEFT", 18, 14)
        sendBtn:SetText(L["BankDialogSend"])
        d.sendBtn = sendBtn

        local cancelBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 22)
        cancelBtn:SetPoint("BOTTOMRIGHT", -18, 14)
        cancelBtn:SetText(L["BankDialogCancel"])
        cancelBtn:SetScript("OnClick", function() d:Hide() end)

        _bankDialog = d
    end

    local d = _bankDialog
    d.currentItemId   = itemId
    d.currentItemName = itemName
    d.currentBanks    = banksWithItem
    d.selectedBank    = banksWithItem[1].name
    d.maxRequestable  = maxRequestable

    d.currentItemLink = itemLink
    d.itemLbl:SetText(itemLink or itemName or ("Item #" .. tostring(itemId)))
    d.qtyBox:SetText(tostring(defaultQty))
    if pct < 100 then
        d.stockLbl:SetText(string.format("Bank stock: %d  |  Max requestable: %d (%d%%)", totalStock, maxRequestable, pct))
    else
        d.stockLbl:SetText(string.format("Bank stock: %d", totalStock))
    end
    d.maxLbl:SetText("/ max " .. maxRequestable)

    if #banksWithItem == 1 then
        local n = banksWithItem[1].name:match("^([^%-]+)") or banksWithItem[1].name
        d.bankDisplay:SetText(n .. " (" .. banksWithItem[1].count .. ")")
        d.bankDisplay:Show()
        d.bankDropdown:Hide()
    else
        d.bankDisplay:Hide()
        local banks = banksWithItem
        UIDropDownMenu_Initialize(d.bankDropdown, function(_, level)
            for _, b in ipairs(banks) do
                local info  = UIDropDownMenu_CreateInfo()
                local n     = b.name:match("^([^%-]+)") or b.name
                info.text   = n .. " (" .. b.count .. ")"
                info.value  = b.name
                info.func   = function()
                    d.selectedBank = b.name
                    UIDropDownMenu_SetText(d.bankDropdown, info.text)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local fn = banksWithItem[1].name:match("^([^%-]+)") or banksWithItem[1].name
        UIDropDownMenu_SetText(d.bankDropdown, fn .. " (" .. banksWithItem[1].count .. ")")
        d.bankDropdown:Show()
    end

    d.sendBtn:SetScript("OnClick", function()
        local reqTOG = _G["TOGBankClassic_Guild"]
        if not reqTOG then return end
        local qty = tonumber(d.qtyBox:GetText()) or 0
        if qty < 1 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[TOGPM] Quantity must be at least 1.|r")
            return
        end
        if qty > d.maxRequestable then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFF4444[TOGPM] Maximum requestable quantity is %d.|r", d.maxRequestable))
            return
        end
        if not d.selectedBank or d.selectedBank == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[TOGPM] Please select a banker.|r")
            return
        end
        local reqName = d.currentItemName
            or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(d.currentItemId))
            or "Unknown"
        local ok = reqTOG:AddRequest({
            item      = reqName,
            itemID    = d.currentItemId,
            quantity  = qty,
            requester = reqTOG:GetNormalizedPlayer(),
            bank      = d.selectedBank,
            notes     = "",
        })
        if ok then
            local dispBank = d.selectedBank:match("^([^%-]+)") or d.selectedBank
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFFDA8CFF[TOGPM]|r Bank request sent: %dx %s \226\134\146 %s", qty, reqName, dispBank))
            d:Hide()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[TOGPM] Request failed. Check that TOGBankClassic is synced.|r")
        end
    end)

    -- Snap to top-right of the main addon window each time we open.
    local mainWowFrame = addon.MainWindow
                      and addon.MainWindow.frame
                      and addon.MainWindow.frame.frame
    d:ClearAllPoints()
    if anchorBelow and anchorBelow:IsShown() then
        d:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -4)
    elseif mainWowFrame and mainWowFrame:IsShown() then
        d:SetPoint("TOPLEFT", mainWowFrame, "TOPRIGHT", 4, 0)
    else
        d:SetPoint("CENTER")
    end

    d:Show()
end

addon:DebugPrint(
    "Compat loaded. build:", build,
    "Vanilla:", tostring(addon.isVanilla),
    "TBC:",     tostring(addon.isTBC),
    "Wrath:",   tostring(addon.isWrath),
    "Cata:",    tostring(addon.isCata),
    "MoP:",     tostring(addon.isMoP)
)
