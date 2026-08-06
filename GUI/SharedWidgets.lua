-- TOG Profession Master — Shared GUI widget factories
--
-- Anywhere we'd otherwise hand-roll the same widget pattern across
-- Browser / Cooldowns / Missing tabs, the factory lives here. Tabs
-- become call-sites (~10 lines) instead of containing ~80 lines of
-- copy-pasted plumbing each.

local _, addon = ...
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

addon.GUI = addon.GUI or {}
addon.UI  = addon.UI or {}
local UI = addon.UI

function UI.Brand(text)
    return "|c" .. (addon.BrandColor or "ffFF8000") .. tostring(text or "") .. "|r"
end

-- ---------------------------------------------------------------------------
-- Shared sort helpers
-- ---------------------------------------------------------------------------
addon.GUI.Sort = addon.GUI.Sort or {}

addon.GUI.Sort.Texture = addon.GUI.Sort.Texture or "Interface\\Calendar\\MoreArrow"

-- FGI-style sort arrow: Blizzard's Calendar more-arrow texture, rotated
-- up/down to indicate ascending / descending order.
function addon.GUI.Sort.SetIndicator(texture, isAsc)
    if not texture then return end
    texture:SetTexture(addon.GUI.Sort.Texture)
    if texture.SetTexCoord then
        if isAsc then
            texture:SetTexCoord(0.0, 0.9375, 0.6875, 0.0)
        else
            texture:SetTexCoord(0.0, 0.9375, 0.0, 0.6875)
        end
    end
end

function addon.GUI.Sort.Indicator(isAsc)
    local indicator = "|T" .. addon.GUI.Sort.Texture .. ":14:14|t"
    if isAsc then
        return indicator
    end
    return indicator
end

-- Standard click behavior: same column toggles asc/desc, new column resets to asc.
function addon.GUI.Sort.Next(currentCol, currentAsc, clickedCol)
    if currentCol == clickedCol then
        return clickedCol, not (currentAsc == true)
    end
    return clickedCol, true
end

-- Optional tri-state variant for tabs that support "unsorted" as a third click.
-- click 1: unsorted/new col -> asc, click 2: desc, click 3: unsorted(nil)
function addon.GUI.Sort.NextOrNone(currentCol, currentAsc, clickedCol)
    if currentCol ~= clickedCol then
        return clickedCol, true
    end
    if currentAsc == true then
        return clickedCol, false
    end
    return nil, true
end

-- ---------------------------------------------------------------------------
-- Item links: ONE implementation of clicking and hovering an item, for every
-- surface in the addon.
--
-- There used to be three, and they were not equivalent — which is why a
-- shift-click worked on the Cooldowns tab and did nothing on the Browser tab:
--
--   HandleModifiedItemClick(link)  Cooldowns, Crafting, AH Profit
--   ChatEdit_InsertLink(link)      Browser x3, Reagent Tracker, Compat
--   editBox:Insert(link)           Missing Recipes, Shopping List
--
-- The middle one is the bug. `ChatEdit_InsertLink` is NOT a Classic Era API: it
-- exists only inside Blizzard_DeprecatedChatInfo, behind
-- `GetCVarBool("loadDeprecationFallbacks")`, as an alias for
-- `ChatFrameUtil.InsertLink`. With that CVar off the global is nil — so the
-- guarded call sites silently did nothing (the classic feature-test-disables
-- failure) and the two UNGUARDED ones, the bank request dialog and the reagent
-- tracker row, raised a nil-call error at the click.
--
-- `HandleModifiedItemClick` is Blizzard's own router and is the right answer
-- everywhere: it honours the player's CHATLINK and DRESSUP bindings (which are
-- not necessarily shift and ctrl), opens chat when it is closed, and routes to
-- the social frame when that is what is up.
-- ---------------------------------------------------------------------------
addon.ItemLink = addon.ItemLink or {}
local ItemLink = addon.ItemLink

--- Route a modified click on an item link exactly as Blizzard's own item
--- buttons do. Returns true when the click was consumed.
---
--- The fallback chain exists for the case where a stripped-down client (or a
--- broken addon) has removed the router; it is deliberately ordered so the
--- deprecated global is LAST and is never assumed to exist.
function ItemLink.Click(link)
    if not link then return false end
    if HandleModifiedItemClick then
        return HandleModifiedItemClick(link) and true or false
    end
    if not IsShiftKeyDown or not IsShiftKeyDown() then return false end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        return ChatFrameUtil.InsertLink(link) and true or false
    end
    if ChatEdit_InsertLink then
        return ChatEdit_InsertLink(link) and true or false
    end
    local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if box then box:Insert(link); return true end
    return false
end

--- Does the player currently want an item comparison shown?
---
--- `IsModifiedClick("COMPAREITEMS")` rather than `IsShiftKeyDown()`, because
--- the compare modifier is a rebindable setting — assuming shift would ignore
--- anyone who has changed it. `alwaysCompareItems` is the CVar that pins the
--- comparison on permanently, and Blizzard checks both together
--- (Blizzard_GameTooltip/Classic/GameTooltip.lua:511).
function ItemLink.WantsCompare()
    if IsModifiedClick and IsModifiedClick("COMPAREITEMS") then return true end
    if GetCVarBool and GetCVarBool("alwaysCompareItems") then return true end
    return false
end

--- Show or hide the side-by-side comparison on `tip` to match the current
--- modifier state. Safe to call repeatedly; that is what makes hold-to-compare
--- work rather than press-before-hover-to-compare.
function ItemLink.SyncCompare(tip)
    if not tip then return false end
    if ItemLink.WantsCompare() then
        if GameTooltip_ShowCompareItem then
            GameTooltip_ShowCompareItem(tip)
            return true
        end
        return false
    end
    if GameTooltip_HideShoppingTooltips then GameTooltip_HideShoppingTooltips(tip) end
    return false
end

--- Which tooltip frame a curated surface should draw into.
---
--- Default (setting off) is the caller's own private frame, when it has one.
--- Missing Recipes owns one deliberately: third-party addons hook
--- OnTooltipSetItem onto the GLOBAL GameTooltip instance, and RecipeMaster's
--- handler nil-indexes `recipe.teaches` on a recipe scroll and takes the
--- tooltip down with it. A private frame inheriting the same template never
--- runs those hooks.
---
--- With `useStockItemTooltips` on, the player has asked for the stock tooltip
--- everywhere — which is exactly a request for those third-party hooks to fire,
--- ATT lines included, and therefore also a request to be exposed to them.
function ItemLink.Tooltip(privateTip)
    if not privateTip then return GameTooltip end
    local db = addon.lib and addon.lib.db
    if db and db.profile and db.profile.useStockItemTooltips then
        return GameTooltip
    end
    return privateTip
end

-- Rows register here while hovered, so a modifier pressed DURING the hover
-- re-evaluates. Blizzard's own frames re-check the modifier when the tooltip is
-- built and never again, so without this the comparison only appears if the key
-- was already down before the mouse arrived — which is not what the game does
-- from a bag slot, and not what the request asked for.
local hovered = nil
local modifierWatcher = nil

local function ensureModifierWatcher()
    if modifierWatcher then return modifierWatcher end
    modifierWatcher = CreateFrame("Frame")
    modifierWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    modifierWatcher:SetScript("OnEvent", function()
        if hovered and hovered.tip and hovered.tip:IsShown() then
            ItemLink.SyncCompare(hovered.tip)
        end
    end)
    return modifierWatcher
end

--- Note that `tip` is showing an item so the modifier watcher can update it.
function ItemLink.BeginHover(tip)
    if not tip then return end
    ensureModifierWatcher()
    hovered = { tip = tip }
    ItemLink.SyncCompare(tip)
end

--- Stop tracking; call from OnLeave alongside hiding the tooltip.
function ItemLink.EndHover(tip)
    if tip and GameTooltip_HideShoppingTooltips then
        GameTooltip_HideShoppingTooltips(tip)
    end
    hovered = nil
end

--- Test seam: what the watcher currently considers hovered.
function ItemLink._Hovered() return hovered end

--- Populate `tip` with an item, by link when we have one and by id otherwise,
--- then keep the comparison in sync. Returns true when something was shown.
---
--- Link is preferred over id because a link carries enchants, suffixes and the
--- quality colour; SetItemByID re-resolves the base item and loses them.
function ItemLink.SetItem(tip, link, itemId)
    if not tip then return false end
    if link then
        tip:SetHyperlink(link)
    elseif itemId and tip.SetItemByID then
        tip:SetItemByID(itemId)
    elseif itemId then
        tip:SetHyperlink("item:" .. itemId)
    else
        return false
    end
    ItemLink.BeginHover(tip)
    return true
end

-- Shared header-arrow widget plumbing (FGI-style MoreArrow texture).
-- Works for AceGUI header widgets and raw frame-backed header buttons.
function addon.GUI.Sort.ConfigureHeaderIcon(widgetOrButton, isSorted, isAsc, justify)
    if not widgetOrButton then return end
    local host = widgetOrButton.frame or widgetOrButton
    if not (host and host.CreateTexture) then return end

    local tex = widgetOrButton._sortIcon
    if not tex then
        tex = host:CreateTexture(nil, "OVERLAY")
        tex:SetSize(12, 12)
        widgetOrButton._sortIcon = tex
    end

    tex:ClearAllPoints()
    if justify == "RIGHT" then
        tex:SetPoint("LEFT", host, "LEFT", 2, 0)
    else
        tex:SetPoint("RIGHT", host, "RIGHT", -2, 0)
    end

    if isSorted then
        -- Re-attach to the host before showing. When this column was last
        -- UNsorted we detached the texture (SetParent(nil), see below); a
        -- parentless texture never renders, so tabs that REUSE their header
        -- widgets across sorts (e.g. AHProfitTab's UpdateHeaderText, which
        -- doesn't rebuild the headers) would otherwise lose the arrow the
        -- first time the sort column changes and never get it back.
        tex:SetParent(host)
        addon.GUI.Sort.SetIndicator(tex, isAsc)
        tex:Show()
    else
        tex:Hide()
        -- Detach the texture when hidden to prevent bleeding into other tabs
        -- when AceGUI recycles this widget. ClearAllPoints alone isn't enough —
        -- the texture stays parented and can show up overlapping headers in
        -- tabs that reuse the widget but don't call ConfigureHeaderIcon.
        tex:SetParent(nil)
    end
end

-- Sort-arrow placement for CENTER-justified headers. Unlike ConfigureHeaderIcon
-- (which pins the arrow to the column edge — the left/right convention the
-- Browser/Crafting/Missing tabs use), this places the arrow a few px to the
-- RIGHT of the *visible header text*, measured from the column centre via
-- GetStringWidth. Use it on tabs whose headers are centred over their columns
-- (Profit Planner, Cooldowns) so the arrow hugs the text everywhere alike.
--
-- The widget owns its texture as `widget._sortIcon`; callers must clean it up on
-- the widget's OnRelease / DetachPool (Hide + SetParent(nil) + ClearAllPoints +
-- nil) exactly as they do for ConfigureHeaderIcon, so it doesn't bleed across the
-- pool. Only the asc/desc look is shared, via SetIndicator. `width` is the column
-- width; it falls back to the host frame's current width.
--
-- Works for both AceGUI header widgets (host = widget.frame, text = widget.label)
-- and raw frame-backed headers (host = widget itself, text = widget._fs) — so
-- the Profit/Cooldowns AceGUI headers and the Crafting tab's raw button headers
-- share one centred-arrow implementation.
addon.GUI.Sort.ArrowSize = addon.GUI.Sort.ArrowSize or 12
addon.GUI.Sort.ArrowGap  = addon.GUI.Sort.ArrowGap or 3

function addon.GUI.Sort.ConfigureCenteredHeaderIcon(widget, isSorted, isAsc, width)
    if not widget then return end
    local host = widget.frame or widget
    if not (host and host.CreateTexture) then return end
    local fs = widget.label or widget._fs
    local size = addon.GUI.Sort.ArrowSize
    local tex = widget._sortIcon
    if not tex then
        tex = host:CreateTexture(nil, "OVERLAY")
        tex:SetSize(size, size)
        widget._sortIcon = tex
    end
    if not isSorted then
        tex:Hide()
        return
    end
    -- Re-attach before showing (it may have been detached when last hidden, or
    -- by the caller's OnRelease cleanup); a parentless texture never renders.
    tex:SetParent(host)
    addon.GUI.Sort.SetIndicator(tex, isAsc)

    local hostW = width or (host.GetWidth and host:GetWidth()) or 0
    local textW = (fs and fs.GetStringWidth and fs:GetStringWidth()) or 0
    -- Text is centred in [0, hostW], so its right edge is at hostW/2 + textW/2.
    local x = (hostW / 2) + (textW / 2) + addon.GUI.Sort.ArrowGap
    -- Never let the arrow spill past the column's right edge.
    local maxX = hostW - size
    if maxX < 0 then maxX = 0 end
    if x > maxX then x = maxX end
    tex:ClearAllPoints()
    tex:SetPoint("LEFT", host, "LEFT", x, 0)
    tex:Show()
end

-- Create a brand-coloured hover glow texture on `frame` (returned hidden). It's
-- WoW's UI-QuestTitleHighlight (whose own edges fade, giving the "blended" look)
-- tinted to the brand colour via SetVertexColor — the single source of truth, and
-- no SetGradient (whose API differs across clients). Callers wire show/hide to
-- their own mouseover handling and clean the texture up on release/detach. Shared
-- so AceGUI headers (MakeColumnHeader) and raw frame headers (Crafting) glow the
-- same. Returns nil if `frame` can't host a texture.
function addon.GUI.MakeHeaderHoverGlow(frame)
    if not (frame and frame.CreateTexture) then return nil end
    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    glow:SetBlendMode("ADD")
    glow:SetAllPoints(frame)
    local hex = addon.BrandColor or "ffFF8000"
    local r = (tonumber(hex:sub(3, 4), 16) or 255) / 255
    local g = (tonumber(hex:sub(5, 6), 16) or 128) / 255
    local b = (tonumber(hex:sub(7, 8), 16) or 0) / 255
    glow:SetVertexColor(r, g, b)
    glow:Hide()
    return glow
end

-- ---------------------------------------------------------------------------
-- Pool detach
-- ---------------------------------------------------------------------------
-- Tabs that maintain a pool of raw CreateFrame rows (faster than AceGUI for
-- virtual-scroll lists) parent those frames to an AceGUI widget's content
-- frame. When AceGUI later recycles that widget into another addon's UI,
-- our pool frames stay parented to it and visibly bleed into that addon —
-- the bug the user hit on TBC / Anniversary with the shopping-list rows.
--
-- The fix is always the same three operations: Hide, re-parent to UIParent
-- (a globally-rooted frame the pool can sit under harmlessly), ClearAllPoints
-- so stale anchors don't reach into a destroyed parent. This helper is the
-- single point of truth for that cleanup so we never have to do it inline
-- again.
--
-- Usage: from inside any AceGUI widget's OnRelease / OnClose callback,
--   addon.GUI.DetachPool(self._myPool)   -- array of pooled raw frames
--   addon.GUI.DetachPool(self._helpIcon) -- single raw frame (e.g. a one-off
--                                          decoration parented to f.frame)
-- Frames stay alive for the next attach (raw frames are session-lifetime
-- and never GC'd), they're just safely orphaned for now.
--
-- The single-frame form covers cases like MainWindow's help "i" icon —
-- one CreateFrame parented to the AceGUI Frame, no pool needed, but the
-- same Hide + UIParent + ClearAllPoints cleanup is required so the icon
-- doesn't bleed into the next addon that AceGUI:Create("Frame")s.
function addon.GUI.DetachPool(poolOrFrame)
    if not poolOrFrame then return end
    -- Single-frame form: detect by presence of :Hide. Frames are tables in
    -- the WoW API but they have a Hide method; arrays of frames are bare
    -- Lua tables with no such method.
    if type(poolOrFrame.Hide) == "function" then
        poolOrFrame:Hide()
        poolOrFrame:SetParent(UIParent)
        poolOrFrame:ClearAllPoints()
        return
    end
    for _, f in ipairs(poolOrFrame) do
        if f then
            f:Hide()
            f:SetParent(UIParent)
            f:ClearAllPoints()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Persistent-scroll helper
-- ---------------------------------------------------------------------------
-- Every tab that renders a scrollable list needs to survive sync-triggered
-- ReleaseChildren+Draw cycles (GUILD_DATA_UPDATED fires every few seconds in
-- an active guild) without yanking the user back to the top of the list.
-- The fix is to persist an AceGUI status table on the tab module and
-- re-attach it via SetStatusTable on each acquire, then restore the saved
-- scroll value after FillRows + layout have settled.
--
-- Tabs come in two flavours:
--   1. AceGUI-native scroll (CooldownsTab) — AceGUI's SetScroll() does
--      everything; no virtual rows to update.
--   2. Virtual-pool scroll (BrowserTab, MissingRecipesTab) — raw frame
--      pool parented to scroll.content; restoring scroll also needs to
--      re-position the pool rows (the tab's UpdateVirtualRows hook).
-- Acquire/Restore handles both via the optional afterRestore callback.
--
-- Usage:
--   local scroll, saved = addon.GUI.PersistentScroll.Acquire(self, {
--       key = "browser",
--       layout = "List", fullWidth = true, fullHeight = true,
--       onRelease = function() self:DetachPool() end,
--   })
--   container:AddChild(scroll)
--   self:FillRows(scroll)
--   if scroll.DoLayout then scroll:DoLayout() end
--   addon.GUI.PersistentScroll.Restore(scroll, saved, function()
--       self:UpdateVirtualRows()  -- optional; virtual-pool tabs only
--   end)
--
-- For "jump to top on filter change" call sites, use Reset(self, scroll).

addon.GUI.PersistentScroll = addon.GUI.PersistentScroll or {}

local function _GetScrollStore()
    local db = addon.lib and addon.lib.db
    if not (db and db.char) then return nil end
    db.char.frames = db.char.frames or {}
    db.char.frames.scrollTabs = db.char.frames.scrollTabs or {}
    return db.char.frames.scrollTabs
end

addon.GUI.RowStripe = addon.GUI.RowStripe or {
    evenAlpha   = 0.04,
    headerAlpha = 0.08,
}

function addon.GUI.ApplyRowStripe(frame, rowIndex, alpha)
    if not frame then return end
    local bg = frame._stripeBg
    if not bg and frame.CreateTexture then
        bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        frame._stripeBg = bg
    end
    if not bg then return end
    local useAlpha = alpha
    if useAlpha == nil then
        local stripes = addon.GUI.RowStripe or {}
        useAlpha = ((rowIndex or 0) % 2 == 0) and (stripes.evenAlpha or 0.04) or 0
    end
    bg:SetColorTexture(1, 1, 1, useAlpha)
end

-- The class LayoutFinished is what auto-sizes scroll.content to fit its
-- AceGUI children — without it AceGUI's FixScroll sees viewheight==0 and
-- hides the scrollbar. AceGUI's ScrollFrame stores methods as INSTANCE
-- fields (AceGUIContainer-ScrollFrame.lua : Constructor copies the local
-- `methods` table directly onto each widget instance), so a previous owner
-- like BrowserTab's virtual-scroll trick — `scroll.LayoutFinished =
-- function() end` — survives AceGUI's release pool and follows the
-- recycled widget into whichever tab acquires it next, breaking auto-size
-- there too. Setting it to nil DOESN'T help either: there's no metatable
-- fallback, so nil makes safecall(nil, ...) a silent no-op with the same
-- end result (this was the regression in the previous "fix" — fresh
-- widgets worked but recycled ones broke after a few tab switches).
--
-- The correct fix is to RESTORE the original method on every Acquire.
-- Captured lazily on first Acquire from a freshly-pulled scroll widget;
-- AceGUI:Release doesn't blank widget methods, so the captured reference
-- stays valid for the lifetime of the session.
local _ORIG_SCROLL_LAYOUT_FINISHED
local function _CaptureOrigScrollLayoutFinished(scroll)
    if _ORIG_SCROLL_LAYOUT_FINISHED then return end
    -- Only capture if this looks like a fresh widget (LayoutFinished is a
    -- function, not nil from a prior bad-fix Acquire). If a previously
    -- damaged widget arrives first, skip — the next fresh acquire will
    -- catch the original method.
    if type(scroll.LayoutFinished) == "function" then
        _ORIG_SCROLL_LAYOUT_FINISHED = scroll.LayoutFinished
    end
end

-- Acquire a ScrollFrame with a persistent _scrollStatus attached to `tab`.
-- Captures the saved scrollvalue into a return value BEFORE the caller's
-- FillRows pass can fire FixScroll and clobber it (BrowserTab's bug from
-- v0.3.5 — scrollbar:SetValue(0) during FixScroll writes scrollvalue=0
-- into the status table via the default OnValueChanged handler).
function addon.GUI.PersistentScroll.Acquire(tab, opts)
    opts = opts or {}
    local key = opts.key
    if key then
        local store = _GetScrollStore()
        if store then
            store[key] = store[key] or { scrollvalue = 0 }
            tab._scrollStatus = store[key]
        else
            tab._scrollStatus = tab._scrollStatus or { scrollvalue = 0 }
        end
    else
        tab._scrollStatus = tab._scrollStatus or { scrollvalue = 0 }
    end
    local saved = tab._scrollStatus.scrollvalue or 0
    -- Also capture the exact PIXEL offset the user was scrolled to. Restore
    -- prefers this over the fraction because re-applying a pixel offset needs
    -- NO frame height — so the position survives even when the caller calls
    -- Restore before the scroll frame has been sized/anchored. That call-order
    -- dependency (fraction -> pixels needs the height) is what made the Missing
    -- tab jump ~10 rows on every rebuild; capturing the raw offset here, and
    -- restoring it verbatim below, makes the ordering impossible to get wrong.
    local savedOffset = tab._scrollStatus.offset

    -- Reset BOTH fields so any synchronous FixScroll during FillRows
    -- writes back zeroes (harmless) instead of corrupting the saved value.
    tab._scrollStatus.scrollvalue = 0
    tab._scrollStatus.offset      = nil

    local scroll = AceGUI:Create("ScrollFrame")
    -- Restore the class LayoutFinished, overwriting any leftover override
    -- from a previous owner of this pooled widget (BrowserTab installs a
    -- no-op as part of its virtual-scroll trick — see the long comment
    -- above _ORIG_SCROLL_LAYOUT_FINISHED). Capture from THIS acquisition
    -- if we haven't already; otherwise assign the previously-captured
    -- reference. When the captured reference is still nil (first-ever
    -- acquire returned a damaged recycled widget), the assignment is a
    -- no-op and the bad behaviour persists for THIS draw only — the
    -- next fresh acquire will catch the original and self-heal.
    _CaptureOrigScrollLayoutFinished(scroll)
    if _ORIG_SCROLL_LAYOUT_FINISHED then
        scroll.LayoutFinished = _ORIG_SCROLL_LAYOUT_FINISHED
    end
    scroll:SetLayout(opts.layout or "List")
    if opts.fullWidth  ~= false then scroll:SetFullWidth(true)  end
    if opts.fullHeight then           scroll:SetFullHeight(true) end
    scroll:SetStatusTable(tab._scrollStatus)
    if opts.onRelease then
        scroll:SetCallback("OnRelease", opts.onRelease)
    end
    -- Stash for Restore (exact-pixel-offset restore; see Restore).
    scroll._persistOffset = savedOffset
    return scroll, saved
end

-- Restore the saved scroll position after a rebuild. Robust to call order: it
-- restores the exact PIXEL offset captured in Acquire, which needs no frame
-- height, so it lands on the same row even if the scroll frame hasn't been
-- sized/anchored yet. (Callers therefore do NOT have to size-before-restore —
-- getting that order wrong is what made the Missing tab jump ~10 rows while
-- Browser, which happened to size first, did not.) `afterFn` re-renders a
-- virtual-pool tab's rows from the restored offset.
function addon.GUI.PersistentScroll.Restore(scroll, saved, afterFn)
    if not scroll then return end
    local status = scroll.status or scroll.localstatus
    local off    = scroll._persistOffset

    if off and off > 0 and status and scroll.content then
        local vh = (scroll.scrollframe and scroll.scrollframe:GetHeight()) or 0
        local ch = scroll.content:GetHeight() or 0
        -- Clamp to the scrollable range ONLY when the frame is actually sized
        -- (content may have shrunk since the offset was saved). When it isn't
        -- sized yet (vh ~ 0) restore verbatim; AceGUI's FixScroll re-clamps from
        -- status.offset once the real size arrives, without moving the content.
        if vh > 1 then
            local maxOff = math.max(0, ch - vh)
            if off > maxOff then off = maxOff end
        end
        -- Pin the content at the exact pixel offset — this is what makes it
        -- height-independent and therefore order-independent.
        status.offset = off
        scroll.content:ClearAllPoints()
        scroll.content:SetPoint("TOPLEFT",  0, off)
        scroll.content:SetPoint("TOPRIGHT", 0, off)
        -- Sync the scrollbar thumb from the current size (cosmetic; self-corrects
        -- via FixScroll on the next layout if the frame wasn't sized yet). The
        -- SetValue may round-trip through the caller's OnValueChanged -> SetScroll,
        -- which recomputes the SAME offset (identical height within this call), so
        -- the exact position is preserved.
        local range = ch - vh
        local val   = (range > 0) and math.min(1000, off / range * 1000) or 0
        status.scrollvalue = val
        if scroll.scrollbar and scroll.scrollbar.SetValue then
            scroll.scrollbar:SetValue(val)
        end
        if afterFn then afterFn() end
        return
    end

    -- Fallback: no captured pixel offset (first-ever draw, or after Reset). Use
    -- the fraction; there's nothing to restore precisely to anyway. afterFn runs
    -- only when we actually restore something (matches the pre-refactor behavior,
    -- which returned early and skipped it when saved was 0).
    if saved and saved > 0 and scroll.SetScroll then
        scroll:SetScroll(saved)
        if scroll.scrollbar and scroll.scrollbar.SetValue then
            scroll.scrollbar:SetValue(saved)
        end
        if afterFn then afterFn() end
    end
end

-- Explicit "jump to top" reset for filter-change call sites. A filter
-- change should always show the top of the new result set, not whatever
-- offset the previous list was scrolled to.
function addon.GUI.PersistentScroll.Reset(tab, scroll)
    if tab._scrollStatus then
        tab._scrollStatus.scrollvalue = 0
        tab._scrollStatus.offset      = 0
    end
    if scroll and scroll.SetScroll then scroll:SetScroll(0) end
end

-- ---------------------------------------------------------------------------
-- Persistent UI choices (dropdown selections, active tab, saved filters, ...)
-- ---------------------------------------------------------------------------
-- One place for the "remember this control's value across /reload and relog"
-- pattern every tab used to hand-roll against AceDB. Returns get/set closures
-- bound to a single value in a chosen SavedVariables scope:
--
--   local getProf, setProf = addon.GUI.PersistentChoice("char", "missingProfId", 0)
--   dropdown:SetValue(validate(getProf()))             -- restore (see note)
--   dropdown:SetCallback("OnValueChanged", function(_, _, v)
--       setProf(v)                                     -- persist
--       self:RefreshList()
--   end)
--
-- scope  : AceDB namespace — "char" (per-character, default), "profile"
--          (account-wide, follows the account to every character), or "global".
-- key    : the SavedVariables field name.
-- default: returned by get() when nothing has been saved yet (nil is fine).
--
-- NOTE — validation stays with the caller. Whether a saved value is still a
-- valid choice depends on the CURRENT list (a profession the character no longer
-- has, a character no longer in the roster, ...), which only the tab knows, so
-- callers coerce the restored value against their live list before SetValue —
-- exactly as they did with the old hand-rolled db reads.
function addon.GUI.PersistentChoice(scope, key, default)
    scope = scope or "char"
    local function bucket()
        local root = addon.lib and addon.lib.db
        return root and root[scope]
    end
    local function get()
        local d = bucket()
        local v = d and d[key]
        if v == nil then return default end
        return v
    end
    local function set(v)
        local d = bucket()
        if d then d[key] = v end
    end
    return get, set
end

-- ---------------------------------------------------------------------------
-- Dropdown-open detection
-- ---------------------------------------------------------------------------
-- AceGUI's Dropdown widget renders its pulldown menu as a separate Pullout
-- frame parented to UIParent and globally named "AceGUI30Pullout<N>" (see
-- AceGUIWidget-DropDown.lua : CreateFrame at the pullout module). Pool size
-- grows monotonically as more dropdowns are used, so iterating until we hit
-- a nil global covers every pullout AceGUI has ever created.
--
-- MainWindow:Refresh consults this before releasing the active tab's
-- children — releasing the toolbar would tear down whichever Dropdown
-- widget owns the open pullout, which closes it mid-interaction (the
-- user's complaint that prompted this helper). When this returns true,
-- the refresh re-defers until the user picks a value or clicks away.
-- Walk a frame's parent chain; true if `root` is an ancestor (or is the frame).
local function _frameIsWithin(frame, root)
    local guard = 0
    while frame and guard < 60 do
        if frame == root then return true end
        frame = frame:GetParent()
        guard = guard + 1
    end
    return false
end

-- `root` (optional, a real UI frame): only count pullouts owned by a dropdown
-- INSIDE `root`. The AceGUI30PulloutN frames are GLOBAL — shared by every
-- AceGUI-3.0 addon on the client — so without scoping, ONE other addon's open
-- (or leaked-shown) pullout makes this return true forever. That froze
-- MainWindow:Refresh in an endless 0.25s defer loop: the active tab never redrew
-- on purge / sync until a manual tab switch (which bypasses Refresh entirely).
-- An open pullout is anchored to its dropdown's button, so we accept it only
-- when that anchor frame lives under our window. With no `root`, behaves as the
-- old global check (kept for any caller that genuinely wants any-pullout).
function addon.GUI.IsAnyDropdownPulloutOpen(root)
    local i = 1
    while true do
        local f = _G["AceGUI30Pullout" .. i]
        if not f then return false end
        if f:IsShown() then
            if not root then
                return true
            end
            local _, relativeTo = f:GetPoint(1)
            -- relativeTo is normally a frame; guard the rare string-name form
            -- so the parent-chain walk never errors on a non-frame.
            if type(relativeTo) == "table" and _frameIsWithin(relativeTo, root) then
                return true
            end
        end
        i = i + 1
    end
end

-- ---------------------------------------------------------------------------
-- Scan AH button
-- ---------------------------------------------------------------------------
-- Replaces the duplicated 80-line block that previously lived in each of
-- BrowserTab / CooldownsTab / MissingRecipesTab. The factory owns:
--   • The Button widget itself, sized + tooltip-attached
--   • The refreshScanBtnLabel closure (4 states: no AH module / scanning /
--     AH open / AH closed) and its calls into addon.AH.IsOpen() etc.
--   • The OnClick handler that cancels in-progress scans or kicks off a
--     new one via addon.AH.StartScan(...) using items the caller provides
--   • Two AH callbacks (AH_OPEN_STATE_CHANGED, AH_SCAN_COMPLETE) registered
--     ONCE at module load — they look up the active tab's current scan
--     button via _activeButtons[tabName] and refresh it. No more N-callback
--     accumulation across redraws.
--
-- Callers pass:
--   parent        — AceGUI container to AddChild into                    REQUIRED
--   tabName       — "browser" / "cooldowns" / "missing" (active-tab guard) REQUIRED
--   label         — button text when idle / closed                       REQUIRED
--   progressLabel — printf format e.g. "Scanning %d/%d"                  REQUIRED
--   tooltipTitle  — first line of tooltip                                REQUIRED
--   tooltipDesc   — body of tooltip                                      REQUIRED
--   getItems      — function() returning { {itemId, itemName}, ... }     REQUIRED
--                   for the current scan's input set
--   onRefresh     — optional function() called after the button refreshes
--                   so the tab can also refresh its row [AH] buttons
--   noItemsError  — optional string shown when getItems returns empty
--                   (defaults to a generic message)
--   width         — optional, defaults to 130

-- One-time global state. Each tab keeps at most one live scan button at
-- a time; redraws replace the entry, releases clear it (see OnRelease).
local _activeButtons = {}

-- Single global refresh entry-point. Called by the AH callbacks below
-- AND by the OnClick handler immediately after kicking off / cancelling
-- a scan, so every state change funnels through one path.
local function refreshTabButton(tabName)
    local btn = _activeButtons[tabName]
    if not btn or not btn._tpmRefresh then return end
    btn._tpmRefresh()
    if btn._tpmOnRefresh then btn._tpmOnRefresh() end
end

-- One-time callback registration — fires for whichever tab is active.
-- Inactive tabs' buttons get refreshed only when their tab redraws (which
-- happens on tab-switch via OnGroupSelected → DrawTab → tab:Draw). That's
-- the same behaviour the per-tab handlers had after we added the active-
-- tab guard, just centralised.
addon:RegisterCallback("AH_OPEN_STATE_CHANGED", function()
    local mw = addon.MainWindow
    if not mw then return end
    refreshTabButton(mw.activeTab)
end)
addon:RegisterCallback("AH_SCAN_COMPLETE", function()
    local mw = addon.MainWindow
    if not mw then return end
    refreshTabButton(mw.activeTab)
end)

function addon.GUI.MakeScanAHButton(opts)
    assert(opts and opts.parent and opts.tabName and opts.label
           and opts.progressLabel and opts.tooltipTitle and opts.tooltipDesc
           and opts.getItems, "MakeScanAHButton: missing required option")

    local btn = AceGUI:Create("Button")
    btn:SetWidth(opts.width or 130)

    -- Label refresh closure. Captures `btn` and `opts` for this specific
    -- factory call. Stored on btn._tpmRefresh so the global AH callbacks
    -- can reach it via _activeButtons[tabName] without a separate registry.
    local function refresh()
        if not addon.AH then
            btn:SetText(opts.label)
            btn:SetDisabled(true)
            return
        end
        if addon.AH.IsScanning() then
            local done, total = addon.AH.GetScanProgress()
            btn:SetText(string.format(opts.progressLabel, done, total))
            btn:SetDisabled(false)  -- click cancels
        elseif addon.AH.IsOpen() then
            btn:SetText(opts.label)
            btn:SetDisabled(false)
        else
            btn:SetText(opts.label)
            btn:SetDisabled(true)
        end
    end
    btn._tpmRefresh   = refresh
    btn._tpmOnRefresh = opts.onRefresh
    refresh()  -- initial state before the button is even shown

    btn:SetCallback("OnClick", function()
        if not addon.AH then return end
        if addon.AH.IsScanning() then
            addon.AH.CancelScan()
            refreshTabButton(opts.tabName)
            return
        end
        local items = opts.getItems() or {}
        local ok, reason = addon.AH.StartScan(items, {
            onProgress = function() refreshTabButton(opts.tabName) end,
            onComplete = function() refreshTabButton(opts.tabName) end,
        })
        if not ok then
            if reason == "ah-closed" then
                addon:Print(L["AHOpenFirst"])
            elseif reason == "no-items" then
                addon:Print(opts.noItemsError or L["AHNoItemsToScan"])
            end
        end
        refreshTabButton(opts.tabName)
    end)

    addon.GUI.AttachTooltip(btn, opts.tooltipTitle, opts.tooltipDesc)

    -- OnRelease: clear our slot in _activeButtons IF this is still the
    -- registered button. A redraw replaces the entry with a NEW button
    -- BEFORE the old one is released, so this check (==btn) guards
    -- against the old release stomping the new entry.
    btn:SetCallback("OnRelease", function()
        if _activeButtons[opts.tabName] == btn then
            _activeButtons[opts.tabName] = nil
        end
        btn._tpmRefresh   = nil
        btn._tpmOnRefresh = nil
    end)

    _activeButtons[opts.tabName] = btn
    opts.parent:AddChild(btn)
    return btn
end

-- ---------------------------------------------------------------------------
-- Tooltip attachment
-- ---------------------------------------------------------------------------
-- Standard "title + body" tooltip on hover. Routes through whichever
-- mechanism the widget actually exposes:
--
--   • widget:SetCallback("OnEnter"/"OnLeave", fn) — Button, CheckBox,
--     Dropdown body, EditBox body, InteractiveLabel. AceGUI's per-widget
--     Constructor wires Control_OnEnter to fire the SetCallback registry,
--     and AceGUI clears the registry on Release for free.
--
--   • widget.frame:EnableMouse(true) + raw frame OnEnter — covers the
--     LABEL area above Dropdown / EditBox (those widgets put their label
--     fontstring at the top of widget.frame; the dropdown button or
--     editbox sits below and only it gets Control_OnEnter, so hovering
--     the label produces NO callback). Routed through the leak-safe
--     addon.AceGUIFrameScripts so the script restores on release.
--     Detected by the presence of widget.label (a fontstring) — that
--     attribute exists on Dropdown / EditBox but not Button or CheckBox.
function addon.GUI.AttachTooltip(widget, title, desc)
    if not widget then return end

    local function show(anchor)
        addon.Tooltip.Owner(anchor or widget.frame)
        if title then GameTooltip:SetText(title, 1, 1, 1) end
        if desc  then GameTooltip:AddLine(desc, nil, nil, nil, true) end
        GameTooltip:Show()
    end
    local function hide() GameTooltip:Hide() end

    widget:SetCallback("OnEnter", function(_w) show(_w.frame) end)
    widget:SetCallback("OnLeave", hide)

    -- Dropdown and EditBox put their SetLabel("...") fontstring at the
    -- TOP of widget.frame and the actual interactive body (the dropdown
    -- button / input field) BELOW it. AceGUI only wires Control_OnEnter
    -- to the body, so hovering the label area would never fire OnEnter.
    -- Enable mouse on the wrapper frame and route the same tooltip via
    -- the leak-safe AceGUIFrameScripts so the label area is hoverable.
    --
    -- Type check (NOT widget.label presence) — Label/InteractiveLabel
    -- also expose widget.label as their primary fontstring; installing
    -- a raw OnEnter on their wrapper would replace AceGUI's internal
    -- Control_OnEnter dispatcher and silently break widget:SetCallback
    -- for the rest of the widget's lifetime.
    local needsWrapper = (widget.type == "Dropdown" or widget.type == "EditBox")
    if needsWrapper and widget.frame then
        if widget.frame.EnableMouse then
            widget.frame:EnableMouse(true)
        end
        addon.AceGUIFrameScripts(widget, {
            OnEnter = function(f) show(f) end,
            OnLeave = hide,
        })
    end
end

addon.GUI.InputLabelOffsetX = addon.GUI.InputLabelOffsetX or 4

-- Dropdown/EditBox labels are raw FontStrings anchored by AceGUI above the
-- control body. Several tabs had local +2/+4px nudges to stop those labels
-- visually colliding with the control below. Centralise that here so every
-- labeled input uses the same offset, and restore the original points on
-- release so pooled AceGUI widgets don't leak the tweak into other owners.
function addon.GUI.OffsetInputLabel(widget, dx)
    if not (widget and widget.label and widget.label.GetNumPoints and widget.label.GetPoint) then
        return
    end
    local useDx = dx
    if useDx == nil then
        useDx = addon.GUI.InputLabelOffsetX or 4
    end
    if widget._togpmInputLabelOffset == useDx then
        return
    end

    local originalPoints = {}
    for i = 1, widget.label:GetNumPoints() do
        local point, relativeTo, relativePoint, xOfs, yOfs = widget.label:GetPoint(i)
        originalPoints[#originalPoints + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            xOfs = xOfs or 0,
            yOfs = yOfs or 0,
        }
    end
    if #originalPoints == 0 then return end

    widget.label:ClearAllPoints()
    for _, p in ipairs(originalPoints) do
        widget.label:SetPoint(p.point, p.relativeTo, p.relativePoint, p.xOfs + useDx, p.yOfs)
    end
    widget._togpmInputLabelOffset = useDx

    local prevOnRelease = widget.events and widget.events.OnRelease
    widget:SetCallback("OnRelease", function(self)
        if self.label then
            self.label:ClearAllPoints()
            for _, p in ipairs(originalPoints) do
                self.label:SetPoint(p.point, p.relativeTo, p.relativePoint, p.xOfs, p.yOfs)
            end
        end
        self._togpmInputLabelOffset = nil
        if prevOnRelease then prevOnRelease(self) end
    end)
end

-- Registry of live search-box inner EditBox frames (populated by StyleSearchBox).
-- MainWindow:Refresh consults IsAnySearchFocused() to know when the user is
-- typing in one, and DEFERS the data-refresh — a refresh rebuilds the active
-- tab's toolbar, destroying the focused search box and dropping keyboard focus
-- so keystrokes fall through to keybinds ("unbound"). HasFocus() is the reliable
-- focus test on every client; GetCurrentKeyBoardFocus() isn't available on all
-- Classic flavors, which is why the earlier attempt no-op'd.
addon.GUI._searchBoxes = addon.GUI._searchBoxes or {}

function addon.GUI.IsAnySearchFocused()
    for eb in pairs(addon.GUI._searchBoxes) do
        if eb.IsVisible and eb:IsVisible() and eb.HasFocus and eb:HasFocus() then
            return true
        end
    end
    return false
end

-- Style an AceGUI EditBox as a TSM-style search field: drop the visible text
-- label and place WoW's universal magnifying-glass icon (the texture
-- SearchBoxTemplate itself uses) inside on the left, with the typed text inset
-- to clear it. The icon reads as "search" so no text label is needed.
--
-- keepLabelSpace: when true, keep a BLANK label (a single space) so the box stays
-- on the same control line as LABELED siblings (dropdowns) in a Flow toolbar —
-- SetLabel("") shrinks the EditBox to the unlabeled height and raises it, which
-- would misalign it from those dropdowns. Pass false/nil when the search box's
-- toolbar neighbours are themselves unlabeled (e.g. the Crafting tab, where it
-- sits next to a label-less checkbox) so they stay aligned.
--
-- Call this AFTER AttachTooltip so its OnRelease cleanup chains (not stomps).
-- On release the icon is detached and the text insets restored, so the pooled
-- EditBox never carries a stray magnifying glass into the next addon that
-- recycles it. Safe no-op on non-EditBox widgets.
function addon.GUI.StyleSearchBox(widget, keepLabelSpace)
    if not (widget and widget.type == "EditBox" and widget.editbox) then return widget end
    widget:SetLabel(keepLabelSpace and " " or "")
    local eb = widget.editbox

    -- Register for the focus-aware refresh deferral (see IsAnySearchFocused).
    addon.GUI._searchBoxes[eb] = true
    -- Reset MainWindow's refresh-deferral counter on every keystroke so
    -- CONTINUOUS typing keeps deferring the data-refresh (which would rebuild
    -- and unfocus this box); an idle-but-focused box still hits the cap and
    -- refreshes eventually. Wrap the tab's existing OnTextChanged, which is set
    -- BEFORE this call (StyleSearchBox runs "AFTER AttachTooltip", and tabs wire
    -- OnTextChanged with it) — AceGUI clears widget.events on release, no leak.
    local prevOnText = widget.events and widget.events.OnTextChanged
    widget:SetCallback("OnTextChanged", function(self, event, ...)
        if addon.MainWindow then addon.MainWindow._refreshDeferrals = 0 end
        if prevOnText then prevOnText(self, event, ...) end
    end)

    local icon = widget._searchIcon
    if not icon then
        icon = widget.frame:CreateTexture(nil, "OVERLAY")
        icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        icon:SetVertexColor(0.7, 0.7, 0.7)
        widget._searchIcon = icon
    end
    icon:SetParent(widget.frame)
    icon:SetSize(14, 14)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", eb, "LEFT", 1, -2)
    icon:Show()

    if eb.SetTextInsets and eb.GetTextInsets then
        if not widget._origTextInsets then
            widget._origTextInsets = { eb:GetTextInsets() }
        end
        eb:SetTextInsets(18, 0, 0, 0)
    end

    local prevOnRelease = widget.events and widget.events.OnRelease
    widget:SetCallback("OnRelease", function(self)
        addon.GUI._searchBoxes[eb] = nil
        local i = self._searchIcon
        if i then
            i:Hide()
            i:SetParent(nil)
            i:ClearAllPoints()
            self._searchIcon = nil
        end
        if self.editbox and self.editbox.SetTextInsets and self._origTextInsets then
            self.editbox:SetTextInsets(unpack(self._origTextInsets))
            self._origTextInsets = nil
        end
        if prevOnRelease then prevOnRelease(self) end
    end)
    return widget
end

-- ---------------------------------------------------------------------------
-- Column header
-- ---------------------------------------------------------------------------
-- Shared factory for "column header" labels above tab tables. Centralises
-- the rules from CLAUDE.md (InteractiveLabel + brand color + no-wrap) so
-- new headers can't drift away from the brand convention by accident.
--
-- Optional sort: pass `onClick` and the header becomes clickable. Optional
-- tooltip: pass `tooltipTitle` and/or `tooltipDesc`. Optional alignment:
-- pass `justifyH = "LEFT" | "CENTER" | "RIGHT"`.
--
-- Use cases:
--   • CooldownsTab.DrawHeaders — sortable headers with tooltips
--   • MissingRecipesTab inline HdrLbl — non-sortable, optional alignment
--   • Anywhere else a tab needs a column header above a list — same call
--
-- BrowserTab does NOT use this; it draws raw FontString headers on its
-- custom headerBar (which lives in a virtual-scroll context, not an AceGUI
-- container). Forcing it through the AceGUI factory would mean rebuilding
-- the headerBar around an InteractiveLabel and the gain isn't worth it.
function addon.GUI.MakeColumnHeader(opts)
    assert(opts and opts.parent and opts.label and opts.width,
           "MakeColumnHeader: missing required option (parent / label / width)")

    local lbl = AceGUI:Create("InteractiveLabel")
    lbl:SetText(UI.Brand(opts.label))
    lbl:SetWidth(opts.width)
    if opts.justifyH and lbl.SetJustifyH then
        lbl:SetJustifyH(opts.justifyH)
    end
    -- Headers never wrap to a second line — column widths can be tight,
    -- and a wrapped header doubles the row height and breaks alignment
    -- with the data rows below. The internal fontstring lives at .label;
    -- guard for older clients that lack SetWordWrap.
    if lbl.label and lbl.label.SetWordWrap then
        lbl.label:SetWordWrap(false)
    end

    if opts.tooltipTitle or opts.tooltipDesc then
        addon.GUI.AttachTooltip(lbl, opts.tooltipTitle, opts.tooltipDesc)
    end

    if opts.onClick then
        lbl:SetCallback("OnClick", function() opts.onClick() end)
    end

    -- opts.hoverGlow: a soft brand-coloured glow that fades in behind the header
    -- on mouseover, signalling "click to sort" (modelled on TOGBankClassic's
    -- Requests tab, which tints WoW's UI-QuestTitleHighlight). The texture's own
    -- edge-fade gives the blended look; SetVertexColor tints it to the brand
    -- colour (single source of truth) — no SetGradient, which differs across
    -- clients. Opt-in so only sortable-header tabs (Profit, Cooldowns) light up.
    --
    -- AttachTooltip above already registered OnEnter/OnLeave, so we CHAIN them
    -- (widget.events holds one callback per event). OnRelease hides + detaches
    -- the texture so it can't bleed into another addon that recycles this pooled
    -- widget; tab callers chain their own OnRelease via prevOnRelease, so setting
    -- it here composes rather than conflicts.
    if opts.hoverGlow then
        local glow = lbl._togpmHeaderGlow
        if not glow then
            glow = addon.GUI.MakeHeaderHoverGlow(lbl.frame)
            lbl._togpmHeaderGlow = glow
        else
            -- Recycled widget already has one — re-attach and reset it.
            glow:SetParent(lbl.frame)
            glow:ClearAllPoints()
            glow:SetAllPoints(lbl.frame)
            glow:Hide()
        end

        local prevEnter = lbl.events and lbl.events.OnEnter
        lbl:SetCallback("OnEnter", function(self, ...)
            if self._togpmHeaderGlow then self._togpmHeaderGlow:Show() end
            if prevEnter then prevEnter(self, ...) end
        end)
        local prevLeave = lbl.events and lbl.events.OnLeave
        lbl:SetCallback("OnLeave", function(self, ...)
            if self._togpmHeaderGlow then self._togpmHeaderGlow:Hide() end
            if prevLeave then prevLeave(self, ...) end
        end)
        local prevRelease = lbl.events and lbl.events.OnRelease
        lbl:SetCallback("OnRelease", function(self, ...)
            local tex = self._togpmHeaderGlow
            if tex then
                tex:Hide()
                tex:SetParent(nil)
                tex:ClearAllPoints()
                self._togpmHeaderGlow = nil
            end
            if prevRelease then prevRelease(self, ...) end
        end)
    end

    opts.parent:AddChild(lbl)
    return lbl
end

UI.AttachTooltip = addon.GUI.AttachTooltip

-- Suppress unused-warn for L since callers pass strings already localised.
local _ = L
