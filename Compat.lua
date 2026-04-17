-- TOG Profession Master — Compatibility shims
-- Loaded immediately after TOGProfessionMaster.lua.
-- Sets version flags and wraps APIs that differ across Classic versions so
-- no other module ever needs to branch on C_Container, C_AddOns, etc.

local _, addon = ...

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

-- Classic Era / Vanilla has no timeline-based expansion at all.
-- `addon.isClassic` is true for vanilla-protocol builds (Classic Era, Anniversary).
addon.isClassic = addon.isVanilla

-- ---------------------------------------------------------------------------
-- Bag / container API
-- GetContainerItemInfo signature also changed, so we normalise the return
-- into a plain table: { texture, count, locked, quality, readable,
--                       lootable, link, filtered, noValue, itemId }
-- ---------------------------------------------------------------------------
if C_Container and C_Container.GetContainerItemInfo then
    -- Shadowlands+ / Dragonflight builds
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
    -- Classic Era / TBC / Wrath / Cata / MoP — old globals
    function addon:GetContainerItemInfo(bag, slot)
        local texture, count, locked, quality, readable,
              lootable, link, filtered, noValue, itemId =
              GetContainerItemInfo(bag, slot)
        if not texture then return nil end
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

-- ---------------------------------------------------------------------------
-- AddOn loaded check
-- C_AddOns.IsAddOnLoaded exists on Dragonflight+ retail only.
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
            for _, entry in ipairs(alt.items) do
                if entry.ID == itemId and (entry.Count or 0) > 0 then
                    table.insert(result, { name = bankName, count = entry.Count })
                    break
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- Persistent bank-request dialog shared across all UI callers (lazy-created).
local _bankDialog

--- Open the "Request from Guild Bank" dialog.
-- itemId   numeric item ID
-- itemName display name (used in the request payload)
-- itemLink full hyperlink (shown in the dialog; may be nil)
function addon.Bank.ShowRequestDialog(itemId, itemName, itemLink)
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
        d:SetPoint("CENTER")
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
        titleText:SetText("Request from Guild Bank")

        local closeBtn = CreateFrame("Button", nil, d, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function() d:Hide() end)

        local itemLbl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemLbl:SetPoint("TOPLEFT",  18, -36)
        itemLbl:SetPoint("TOPRIGHT", -18, -36)
        itemLbl:SetJustifyH("LEFT")
        d.itemLbl = itemLbl

        local stockLbl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        stockLbl:SetPoint("TOPLEFT", 18, -52)
        stockLbl:SetTextColor(0.6, 0.6, 0.6)
        d.stockLbl = stockLbl

        local bankLbl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bankLbl:SetPoint("TOPLEFT", 18, -70)
        bankLbl:SetText("Banker:")
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
        qtyLbl:SetText("Qty:")
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
        sendBtn:SetText("Send Request")
        d.sendBtn = sendBtn

        local cancelBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 22)
        cancelBtn:SetPoint("BOTTOMRIGHT", -18, 14)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() d:Hide() end)

        _bankDialog = d
    end

    local d = _bankDialog
    d.currentItemId   = itemId
    d.currentItemName = itemName
    d.currentBanks    = banksWithItem
    d.selectedBank    = banksWithItem[1].name
    d.maxRequestable  = maxRequestable

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
