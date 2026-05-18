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
    tab._scrollStatus = tab._scrollStatus or { scrollvalue = 0 }
    local saved = tab._scrollStatus.scrollvalue or 0

    -- Reset BOTH fields so any synchronous FixScroll during FillRows
    -- writes back zeroes (harmless) instead of corrupting the saved
    -- value. offset is always recomputed from scrollvalue + the new
    -- content height anyway, so clearing it is mandatory.
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
    return scroll, saved
end

-- Restore the saved scroll position. Must be called AFTER FillRows has
-- written the content height (so SetScroll can derive a correct offset).
-- For AceGUI-native tabs, calling DoLayout before this is sufficient.
-- For virtual-pool tabs, pass `afterFn` so UpdateVirtualRows re-anchors
-- the pool rows to the restored offset.
function addon.GUI.PersistentScroll.Restore(scroll, saved, afterFn)
    if not (saved and saved > 0 and scroll and scroll.SetScroll) then return end
    scroll:SetScroll(saved)
    -- Some AceGUI versions don't auto-sync the scrollbar visual when
    -- SetScroll writes the status table — explicitly nudge it so
    -- virtual-pool tabs' scrollbars track their content position.
    if scroll.scrollbar and scroll.scrollbar.SetValue then
        scroll.scrollbar:SetValue(saved)
    end
    if afterFn then afterFn() end
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
function addon.GUI.IsAnyDropdownPulloutOpen()
    local i = 1
    while true do
        local f = _G["AceGUI30Pullout" .. i]
        if not f then return false end
        if f:IsShown() then return true end
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
                addon:Print("Open the auction house first.")
            elseif reason == "no-items" then
                addon:Print(opts.noItemsError or "No items to scan in the current view.")
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
    lbl:SetText("|c" .. (addon.BrandColor or "ffFF8000") .. opts.label .. "|r")
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

    opts.parent:AddChild(lbl)
    return lbl
end

-- Suppress unused-warn for L since callers pass strings already localised.
local _ = L
