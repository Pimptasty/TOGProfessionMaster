-- TOG Profession Master — Main Window
-- Root AceGUI frame with a TabGroup containing two tabs:
--   1. Profession browser (includes shopping list at top)
--   2. Cooldown tracker
--
-- Tab content is delegated to BrowserTab.lua and CooldownsTab.lua.
-- This file owns only the frame lifecycle, tab routing, and window
-- position persistence.

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local MainWindow = {}
addon.MainWindow = MainWindow

-- ---------------------------------------------------------------------------
-- AceGUI shared utility — leak-safe raw frame scripts on AceGUI widgets.
-- ---------------------------------------------------------------------------
-- AceGUI clears widget.events (the SetCallback registry) on Release but
-- does NOT reset raw scripts set via `widget.frame:SetScript(...)`. Since
-- AceGUI pools widgets account-wide and recycles them across every addon
-- that uses AceGUI, leftover scripts keep firing in the new owner's UI —
-- e.g. our cooldown tooltip showing up when the user hovers a Dropdown
-- in a different addon.
--
-- Critical: many AceGUI widget Constructors install internal dispatch
-- scripts on widget.frame themselves (Button's `frame:SetScript("OnEnter",
-- Control_OnEnter)` is the canonical example — that's what fires the
-- widget:SetCallback("OnEnter", ...) handlers). Naively nilling those on
-- release would break the widget for whoever recycles it next. So this
-- helper SAVES the prior script and RESTORES it on release rather than
-- nilling.
--
-- Prefer widget:SetCallback("OnEnter", fn) when the widget supports it
-- (Button, Dropdown, EditBox, etc. all do — Control_OnEnter fires the
-- registry). Use this helper only for widgets without native dispatch
-- (e.g. SimpleGroup) or for events the widget doesn't expose (OnMouseDown).
--
-- Usage:
--   addon.AceGUIFrameScripts(widget, {
--       OnMouseDown = function(f, button) ... end,
--   })
-- Sentinel for "this event had NO handler before we touched it". A plain nil
-- cannot express that: `saved[evt] = nil` stores no key at all, so the restore
-- loop below never visits the event and OUR script stays on the widget — which
-- is precisely the leak this helper exists to prevent, in the commonest case of
-- all (a widget with no prior handler for the event). Found by
-- Tests/gui_pool_spec.lua.
local NO_PRIOR_SCRIPT = {}

function addon.AceGUIFrameScripts(widget, scripts)
    if not (widget and widget.frame and scripts) then return end
    local saved = {}
    for evt, fn in pairs(scripts) do
        saved[evt] = widget.frame:GetScript(evt) or NO_PRIOR_SCRIPT
        widget.frame:SetScript(evt, fn)
    end
    widget:SetCallback("OnRelease", function(self)
        if not self.frame then return end
        for evt, prior in pairs(saved) do
            if prior == NO_PRIOR_SCRIPT then prior = nil end
            self.frame:SetScript(evt, prior)
        end
    end)
end

MainWindow.frame     = nil   -- root AceGUI Frame
MainWindow.tabs      = nil   -- AceGUI TabGroup
MainWindow.activeTab = "browser"

-- v0.7.0: function (not table) so the L["..."] reads happen at tab-build
-- time, after ApplyLocaleOverride has had a chance to mutate the AceLocale
-- table. A file-scope table would freeze the strings at module load.
local function getTabDefs()
    local defs = {
        { value = "browser",   text = L["TabProfessions"]    },
        { value = "cooldowns", text = L["TabCooldowns"]      },
        { value = "missing",   text = L["TabMissingRecipes"] },
        { value = "guild",     text = L["TabGuild"]          },
    }
    -- The Crafting tab is omitted entirely when the user opts out of TOGPM's
    -- crafting UI (profile.hideCraftingTab). Built per-open so toggling it +
    -- /reload reflects immediately.
    if not (Ace.db and Ace.db.profile and Ace.db.profile.hideCraftingTab) then
        defs[#defs + 1] = { value = "crafting", text = L["TabCrafting"] }
    end
    defs[#defs + 1] = { value = "ahprofit", text = L["TabProfitPlanner"] }
    return defs
end

-- ---------------------------------------------------------------------------
-- ESC proxy
-- ---------------------------------------------------------------------------
-- An invisible frame registered in UISpecialFrames at load time intercepts
-- every ESC press while the main window is open.  UIParent_HandleEscape
-- iterates UISpecialFrames FORWARD and stops after hiding the first visible
-- entry — so this proxy (registered before the later-created AceGUI frame)
-- always fires first, giving us full control over close priority.
--
--   First ESC  → close ALL open popups simultaneously, then re-arm
--   Second ESC → close the main window

local _escProxy = CreateFrame("Frame", "TOGPMEscProxy", UIParent)
_escProxy:SetSize(1, 1)
_escProxy:SetAlpha(0)
_escProxy:SetPoint("CENTER")
_escProxy:Hide()
tinsert(UISpecialFrames, "TOGPMEscProxy")

_escProxy:SetScript("OnHide", function()
    if not MainWindow.frame then return end

    local closedAny = false

    -- Group / transmute popup (CooldownsTab) — raw frame, not in UISpecialFrames
    local ct = addon.CooldownsTab
    if ct and ct._groupPopup and ct._groupPopup:IsShown() then
        ct._groupPopup:Hide()
        ct._groupPopup = nil
        closedAny = true
    end

    -- Bank request dialog (Compat.lua)
    local bd = _G["TOGPMBankRequestDialog"]
    if bd and bd:IsShown() then
        bd:Hide()
        closedAny = true
    end

    if closedAny then
        -- Re-arm after one frame so the next ESC closes the main window.
        C_Timer.After(0, function()
            if MainWindow.frame then _escProxy:Show() end
        end)
    else
        MainWindow:Close()
    end
end)

-- ---------------------------------------------------------------------------
-- Open / Close
-- ---------------------------------------------------------------------------

function MainWindow:Open(tabKey)
    if self.frame then
        -- Already open — just switch tab if requested.
        if tabKey then self:SelectTab(tabKey) end
        self.frame.frame:Raise()
        return
    end

    local f = AceGUI:Create("Frame")
    f:SetTitle(L["WindowTitle"])
    f:SetStatusText(addon.Version)
    f:SetLayout("Fill")
    -- Resize is enabled/disabled per-tab in ApplyTabSize below. Start
    -- enabled (matches AceGUI default; ApplyTabSize will tighten it
    -- after the initial tab is selected).
    f:EnableResize(true)

    -- AceGUI position/size persistence. It writes top/left/width/height
    -- into this sub-table on every move/resize. The per-tab size policy
    -- below means width/height get overwritten whenever the user is on
    -- a locked tab, so we keep the user's last Browser size separately
    -- in browserWidth/browserHeight — restored when switching back to
    -- Browser. Position (top/left) is shared across all tabs.
    --
    -- Declared BEFORE the OnSizeChanged hook below because that hook
    -- captures `frames` as an upvalue (used to persist Browser's resized
    -- dimensions); the hook's closure is created at registration time
    -- and the upvalue must already exist by then.
    local frames = Ace.db.char.frames
    frames.mainWindow = frames.mainWindow or { width = 720, height = 500 }
    frames.mainWindow.browserWidth  = frames.mainWindow.browserWidth  or 720
    frames.mainWindow.browserHeight = frames.mainWindow.browserHeight or 500
    -- SetStatusTable triggers SetSize internally → fires our OnSizeChanged
    -- hook with whatever size was last persisted (which might be a locked
    -- tab's size if the user last left on Cooldowns/Missing). Suppress
    -- the browserWidth/Height save during this call so the saved Browser
    -- size isn't overwritten with a locked tab's dimensions.
    self._suppressBrowserSize = true
    f:SetStatusTable(frames.mainWindow)
    self._suppressBrowserSize = false

    -- Fire a cross-tab WINDOW_RESIZED callback (debounced ~150ms) on every
    -- user-driven resize so tabs that compute responsive layouts can re-
    -- render. HookScript chains rather than overriding, so AceGUI's own
    -- size handling continues to run. Also persist Browser's resized
    -- dimensions here — only when Browser is the active tab AND the
    -- resize wasn't programmatic (ApplyTabSize sets _suppressBrowserSize
    -- so the locked-tab SetSize / initial-Open SetStatusTable size
    -- doesn't overwrite Browser's user-chosen size).
    local _resizeTimer
    f.frame:HookScript("OnSizeChanged", function(_self, w, h)
        -- Persist the user-chosen size for the resizable tabs (Browser AND
        -- Crafting). Both share the one browserWidth/browserHeight slot — the
        -- locked tabs never reach here (suppressed via _suppressBrowserSize
        -- during their programmatic snap), so a resizable tab's size is never
        -- clobbered by a locked tab's dimensions.
        if (self.activeTab == "browser" or self.activeTab == "crafting") and w and h
           and not self._suppressBrowserSize then
            frames.mainWindow.browserWidth  = math.floor(w + 0.5)
            frames.mainWindow.browserHeight = math.floor(h + 0.5)
        end
        if _resizeTimer then _resizeTimer:Cancel() end
        _resizeTimer = C_Timer.NewTimer(0.15, function()
            _resizeTimer = nil
            if addon.callbacks then
                addon.callbacks:Fire("WINDOW_RESIZED", w, h)
            end
        end)
    end)

    f:SetCallback("OnClose", function(_widget)
        -- Browser's last user-chosen size is already persisted by the
        -- OnSizeChanged hook above, so no special-case capture needed
        -- on close. All chrome-detach + Release routing lives in the
        -- shared _ReleaseFrame helper below so the X-button path AND
        -- the programmatic Close() path use identical cleanup.
        self:_ReleaseFrame(_widget)
    end)

    -- Shrink the default status bar right edge to create room for the help
    -- icon AND the new settings gear icon. Strip layout, left to right:
    --   [ status text ......(-183) ]-6-[ help 24 ]-3-[ gear 20 ]-3-[ Close 100 (-27) ]
    -- The 24-px help icon keeps its size + tooltip behaviour; the gear is
    -- a 20-px Button anchored to its BOTTOMRIGHT, mirroring FastGuildInvite's
    -- bottom-row icon strip. statusbg's right edge moves from -163 to -183
    -- to make room for the 20-px gear + 3-px gap between gear and helpIcon.
    local statusbg = f.statustext:GetParent()
    statusbg:ClearAllPoints()
    statusbg:SetPoint("BOTTOMLEFT",  f.frame, "BOTTOMLEFT",   15, 15)
    statusbg:SetPoint("BOTTOMRIGHT", f.frame, "BOTTOMRIGHT", -183, 15)

    -- Help "i" icon
    local helpIcon = CreateFrame("Frame", nil, f.frame)
    self._helpIcon = helpIcon
    helpIcon:SetSize(24, 24)
    helpIcon:SetPoint("BOTTOMRIGHT", f.frame, "BOTTOMRIGHT", -153, 15)
    helpIcon:EnableMouse(true)
    -- Above AceGUI's bottom resize strips, or the lower 10px of this 24px icon
    -- is dead to clicks and tooltips. See addon.GUI.LiftAboveSizers.
    addon.GUI.LiftAboveSizers(helpIcon)
    local helpTex = helpIcon:CreateTexture(nil, "OVERLAY")
    helpTex:SetAllPoints(helpIcon)
    helpTex:SetTexture("Interface\\Common\\help-i")

    local brand   = "|c" .. (addon.BrandColor  or "ffFF8000")
    local cYou    = "|c" .. (addon.ColorYou    or addon.BrandColor or "ffFF8000")
    local cOnline = "|c" .. (addon.ColorOnline  or "ffffffff")
    local cOffline= "|c" .. (addon.ColorOffline or "ff888888")
    -- Shared legend (first line of every tab's help) — explains the name
    -- color coding used across the addon. Built from the addon-wide color
    -- constants so a palette change in TOGProfessionMaster.lua propagates
    -- everywhere automatically. \194\183 = middle dot "\u{00B7}".
    local nameColorLegend = brand .. "Name colors:|r " ..
        cYou     .. "You|r (your characters) \194\183 " ..
        cOnline  .. "Online|r \194\183 " ..
        cOffline .. "Offline|r"

    local srcCol = addon.PriceSourceColors or {}
    local sourceLegend = brand .. "Price sources:|r "
        .. "|c" .. (srcCol["togpm-ah"] or (addon.BrandColor or "ffFF8000")) .. "[TOGPM]|r "
        .. "|c" .. (srcCol["auctionator"] or "ff6da9ff") .. "[Auctionator]|r "
        .. "|c" .. (srcCol["auctioneer-live"] or srcCol["auctioneer-app"] or "ff8fcf7f") .. "[Auctioneer Live]|r "
        .. "|c" .. (srcCol["auctioneer-cached"] or "ff6fae61") .. "[Auctioneer Cached]|r "
        .. "|c" .. (srcCol["tsm-live"] or "ff63d2ff") .. "[TSM Live]|r "
        .. "|c" .. (srcCol["tsm-history"] or "ffe0b85a") .. "[TSM App]|r"

    local TAB_HELP = {
        browser = {
            title = "Profession Browser",
            lines = {
                nameColorLegend,
                " ",
                "Recipes known by guild members. Click any recipe to open its details on the right.",
                " ",
                brand .. "Filters:|r Profession dropdown, name search, and " .. brand .. "Guild|r vs " .. brand .. "Mine|r view toggle.",
                " ",
                brand .. "Shopping list (top):|r Click a row to expand its reagents. " .. brand .. "−|r / qty / " .. brand .. "+|r adjust, " .. brand .. "×|r removes, " .. brand .. "!|r (gold = armed) pings you when a crafter for that recipe logs in. Reagent rows show the scaled count with [Bank] when TOGBankClassic has stock.",
                " ",
                brand .. "Recipe area:|r Recipes column shows icon + name. Crafters column is a truncated list (" .. brand .. "You|r first). [Bank] appears when the crafted item itself is in TOGBankClassic stock.",
                " ",
                brand .. "Detail area (right):|r Name hover = item tooltip, shift-click = link in chat. Shopping-list controls mirror the top. Reagents support the same hover/shift-click + per-reagent [Bank]. Full crafters list at the bottom — right-click a name to whisper.",
                " ",
                brand .. "Everywhere else:|r A [TOGPM] line is appended to every item tooltip in the game (bags, AH, chat links, comparison tooltips) listing guild crafters.",
            },
        },
        cooldowns = {
            title = "Cooldowns Tracker",
            lines = {
                nameColorLegend,
                " ",
                "Profession cooldowns for every guild member running the addon.",
                " ",
                brand .. "Columns:|r " .. brand .. "Character|r (right-click to whisper), " .. brand .. "Cooldown|r (hover for spell tooltip, click group rows like transmutes to expand), " .. brand .. "Reagent|r (hover for item tooltip), " .. brand .. "Time Left|r (|cff00ff00green|r = ready, |cffffff00yellow|r = <2h, |cffaaaaaagrey|r = on cooldown).",
                " ",
                brand .. "Row actions:|r [Bank] requests the reagent from TOGBankClassic. Mail icon (visible when a mailbox is open) attaches the reagents and pre-fills the recipient.",
                " ",
                brand .. "Controls:|r Click any column header to sort (click again to reverse). " .. brand .. "Ready Only|r toggle hides cooldowns that aren't ready yet.",
            },
        },
        missing = {
            title = "Missing Recipes",
            lines = {
                "Recipes the selected character has not yet learned for a profession \226\128\148 useful for AH hunting.",
                " ",
                brand .. "Filters:|r " .. brand .. "Character|r (your current toon and any tracked alts), " .. brand .. "Profession|r (only professions that character has learned), name search.",
                " ",
                brand .. "Trainer toggle:|r By default trainer-only recipes are hidden (can't be bought). Tick " .. brand .. "Include trainer-only|r to also see those.",
                " ",
                brand .. "Row actions:|r Hover the recipe name for an item tooltip, shift-click to link in chat. Click " .. brand .. "+|r to add the scroll to your Reagent Watch \226\128\148 you'll be alerted the moment it lands in your bags.",
                " ",
                brand .. "Sources:|r Each row tags how the recipe is obtained: " .. brand .. "Vendor|r, " .. brand .. "Drop|r, " .. brand .. "Quest|r, " .. brand .. "Crafted|r, " .. brand .. "Container|r, " .. brand .. "Fishing|r, or " .. brand .. "Trainer|r when shown.",
            },
        },
        crafting = {
            title = "Crafting",
            lines = {
                nameColorLegend,
                " ",
                "Craft your known recipes, queue batches, and compare cost vs sale value.",
                " ",
                brand .. "Cost rows:|r Reagent and output pricing now include source badges (e.g. [TOGPM], [Auctionator], [TSM]).",
                " ",
                sourceLegend,
            },
        },
        ahprofit = {
            title = L["TabProfitPlanner"],
            lines = {
                nameColorLegend,
                " ",
                "Profit ranking across recipes your own characters can craft.",
                " ",
                brand .. "Live AH Profit:|r Uses currently-available sale prices (Auctionator / TSM / TOGPM AH scan).",
                " ",
                brand .. "Historical Profit:|r Uses historical-style pricing (Auctionator / TSM AppHelper-backed data).",
                " ",
                sourceLegend,
            },
        },
        guild = {
            title = L["GuildHelpTitle"],
            lines = {
                nameColorLegend,
                " ",
                L["GuildHelpIntro"],
                " ",
                L["GuildHelpExpand"],
                " ",
                L["GuildHelpSpecs"],
                " ",
                L["GuildHelpCoverage"],
            },
        },

    }

    helpIcon:SetScript("OnEnter", function(self)
        local tab  = MainWindow.activeTab or "browser"
        local help = TAB_HELP[tab] or TAB_HELP.browser
        -- ANCHOR_TOP (centered above) is intentional here; the helper's
        -- TOPLEFT/BOTTOMLEFT picks look worse for this fixed-position icon.
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- 280 keeps the help text readable as paragraphs without forcing a
        -- tooltip far wider than the game's own. It MUST be put back in
        -- OnLeave — see below.
        --
        -- NOTHING RESETS A MINIMUM WIDTH AUTOMATICALLY. Hiding is not a reset:
        -- `GameTooltip_OnHide` (Blizzard_GameTooltip/Classic/GameTooltip.lua:413)
        -- clears money frames, status bars, inserted frames and the backdrop
        -- style, and sets `needsReset` — which is only read at :541 for the
        -- secondary compare item. Minimum width is untouched by all of it. So
        -- setting it here and only calling Hide() pinned the SHARED GameTooltip
        -- to a 480px floor for the rest of the session — every tooltip in the
        -- game, ours and every other addon's, from one hover of our help icon.
        --
        -- Blizzard DOES lower it; it just always does so explicitly. Its own
        -- idiom is `SetMinimumWidth(N, true)` on show paired with
        -- `SetMinimumWidth(0, false)` on hide (Blizzard_AchievementUI.xml:724,
        -- Mists/InspectTalentFrame.lua:189, Mists/Blizzard_TalentUI.lua:1133).
        -- We restore instead of zeroing, for the reason in OnLeave.
        --
        -- Both return values are captured: `GetMinimumWidth` returns
        -- `width, forced` (FrameAPITooltipDocumentation.lua:24-35) and `force`
        -- is a real second argument (:52-59, Default = false), so restoring the
        -- width alone would silently clear another addon's forced flag.
        if GameTooltip.GetMinimumWidth then
            MainWindow._helpTipMinWidth,
            MainWindow._helpTipMinForced = GameTooltip:GetMinimumWidth()
        end
        MainWindow._helpTipMinWidth  = MainWindow._helpTipMinWidth or 0
        MainWindow._helpTipMinForced = MainWindow._helpTipMinForced or false
        GameTooltip:SetMinimumWidth(280)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(help.title, 1, 0.82, 0, true)
        for _, line in ipairs(help.lines) do
            GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    helpIcon:SetScript("OnLeave", function()
        -- Restore what was there rather than assuming a default: another addon
        -- may legitimately have raised it, and clobbering that to 0 would be
        -- the same bug pointed the other way.
        if GameTooltip.SetMinimumWidth and MainWindow._helpTipMinWidth then
            GameTooltip:SetMinimumWidth(MainWindow._helpTipMinWidth,
                                        MainWindow._helpTipMinForced)
            MainWindow._helpTipMinWidth  = nil
            MainWindow._helpTipMinForced = nil
        end
        GameTooltip:Hide()
    end)

    -- Settings gear icon — opens the AceConfig dialog (same target as
    -- /togpm settings and Shift+left-click on the minimap button).
    -- Anchored to helpIcon's BOTTOMRIGHT + (3, 2): 3-px horizontal gap to
    -- match FastGuildInvite's bottom-row spacing, +2 y to vertically
    -- centre a 20-tall gear against the 24-tall help icon (both bottoms
    -- align with the AceGUI close button's centre y=27). Stashed on self
    -- so OnClose can DetachPool it alongside the help icon — without
    -- that, this gear would ride along when AceGUI recycles the Frame
    -- to another addon (same widget-bleed trap helpIcon had).
    local gearIcon = CreateFrame("Button", nil, f.frame)
    self._gearIcon = gearIcon
    gearIcon:SetSize(20, 20)
    gearIcon:SetPoint("BOTTOMLEFT", helpIcon, "BOTTOMRIGHT", 3, 2)
    gearIcon:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    gearIcon:SetPushedTexture("Interface\\Icons\\Trade_Engineering")
    -- Same fix as helpIcon: 8 of this button's 20px sit inside sizer_s, so
    -- without the lift its lower two-fifths are dead to clicks.
    addon.GUI.LiftAboveSizers(gearIcon)
    local gearPushed = gearIcon:GetPushedTexture()
    if gearPushed then gearPushed:SetVertexColor(0.7, 0.7, 0.7) end
    gearIcon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    gearIcon:SetScript("OnEnter", function(self_)
        addon.Tooltip.Owner(self_)
        local brandColor = addon.BrandColor or "ffFF8000"
        GameTooltip:SetText("|c" .. brandColor .. L["TooltipSettingsTitle"] .. "|r", 1, 1, 1, 1, true)
        GameTooltip:AddLine(L["TooltipSettingsDesc"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    gearIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gearIcon:SetScript("OnClick", function()
        if not addon.OpenSettings then return end
        -- Opening the Blizzard Settings panel triggers CloseSpecialWindows()
        -- on the way in, which hides every entry in UISpecialFrames — including
        -- our TOGPMEscProxy, whose OnHide handler closes the main window when
        -- nothing else is on top. End result without this workaround: the main
        -- window slams shut every time the gear is clicked.
        --
        -- Workaround (mirrors FGI's gear-click pattern): temporarily clear the
        -- proxy's OnHide handler so the proxy can be hidden silently, open
        -- settings, then restore the handler and re-show the proxy on the next
        -- frame so ESC still closes the main window on subsequent presses.
        local proxy = _G["TOGPMEscProxy"]
        local origOnHide = proxy and proxy:GetScript("OnHide")
        if proxy then proxy:SetScript("OnHide", nil) end

        addon:OpenSettings()

        if proxy then
            C_Timer.After(0, function()
                proxy:SetScript("OnHide", origOnHide)
                if MainWindow.frame then proxy:Show() end
            end)
        end
    end)

    -- TabGroup
    local tg = AceGUI:Create("TabGroup")
    tg:SetTabs(getTabDefs())
    tg:SetLayout("Flow")
    tg:SetFullWidth(true)
    tg:SetFullHeight(true)

    tg:SetCallback("OnGroupSelected", function(_widget, _event, group)
        -- Browser's last size is kept current by the OnSizeChanged hook
        -- above (it persists w/h whenever activeTab == "browser"), so by
        -- the time we leave Browser the saved value is already correct.
        self.activeTab = group
        -- A tab SELECTION is a user navigation (hardware event), so it's the one
        -- safe moment to let the Crafting tab auto-cast/open the selected
        -- profession. Event-driven re-draws (FireUpdate → DrawTab) bypass this
        -- callback, so they can't trigger the protected CastSpellByName. The flag
        -- is consumed in CraftingTab:Draw.
        if group == "crafting" and addon.CraftingTab then
            addon.CraftingTab._autoOpenOnUserNav = true
        end
        -- Persist main tab selection so reopening the window returns to the last
        -- used tab (per-character), via the shared addon.GUI.PersistentChoice
        -- helper. Called at runtime (not file scope) because MainWindow loads
        -- before SharedWidgets in the TOC.
        local _, setLastTab = addon.GUI.PersistentChoice("char", "lastMainTab")
        setLastTab(group)
        self:ApplyTabSize(group)
        _widget:ReleaseChildren()
        self:DrawTab(group, _widget)
    end)

    f:AddChild(tg)

    self.frame = f
    self.tabs  = tg

    self:ApplyScale()
    _escProxy:Show()
    -- Apply size BEFORE selecting the tab so the first Draw sees the
    -- correct frame dimensions (some tabs read frame width during Draw).
    -- Load saved tab from db.char, falling back to "browser" if none saved
    local getLastTab = addon.GUI.PersistentChoice("char", "lastMainTab")
    local initialTab = tabKey or getLastTab() or self.activeTab or "browser"
    -- Never select a tab that isn't in the current set (e.g. a saved/forced
    -- "crafting" when the Crafting tab is hidden) — that would render hidden-tab
    -- content with no tab to leave it. Fall back to Browser.
    local valid = false
    for _, def in ipairs(getTabDefs()) do
        if def.value == initialTab then valid = true; break end
    end
    if not valid then initialTab = "browser" end
    self:ApplyTabSize(initialTab)
    tg:SelectTab(initialTab)
end

-- Whole-window UI scale (Settings → Display → "Window scale"). Scaling the root
-- frame shrinks every element proportionally — text, recipe columns, the queue
-- panel — so the window (and the Crafting tab) can take far less screen space
-- than the resize floor allows without the layout overlapping. Independent of
-- size: SetResizeBounds / the persisted width/height are in the frame's own
-- coordinate space, so a scaled window still resizes and remembers its size; the
-- on-screen footprint is size × scale. Clamped 0.5–1.5 (50%–150%).
function MainWindow:ApplyScale()
    if not (self.frame and self.frame.frame) then return end
    local s = tonumber(Ace.db.profile.windowScale) or 1
    if s < 0.5 then s = 0.5 elseif s > 1.5 then s = 1.5 end
    self.frame.frame:SetScale(s)
end

-- ---------------------------------------------------------------------------
-- Per-tab window sizing
-- ---------------------------------------------------------------------------
-- Each tab declares a WINDOW_SIZE table on its module:
--   { width=W, height=H, locked=true }       — resize disabled, snap to W×H
--   { minWidth=W, minHeight=H }              — resizable, with a floor
--
-- Locked tabs (Cooldowns, Missing) use IDENTICAL dimensions so switching
-- between them produces no visible jump. Only switching to/from Browser
-- (the resizable tab) changes the window size, and Browser's last size
-- is restored from frames.mainWindow.browserWidth/browserHeight.
local _TAB_SIZE_LOOKUP = {
    browser   = function() return addon.BrowserTab        and addon.BrowserTab.WINDOW_SIZE        end,
    cooldowns = function() return addon.CooldownsTab      and addon.CooldownsTab.WINDOW_SIZE      end,
    missing   = function() return addon.MissingRecipesTab and addon.MissingRecipesTab.WINDOW_SIZE end,
    guild     = function() return addon.GuildTab          and addon.GuildTab.WINDOW_SIZE          end,
    crafting  = function() return addon.CraftingTab       and addon.CraftingTab.WINDOW_SIZE       end,
    ahprofit  = function() return addon.AHProfitTab       and addon.AHProfitTab.WINDOW_SIZE       end,
}

function MainWindow:ApplyTabSize(tabKey)
    if not (self.frame and self.frame.frame) then return end
    local lookup = _TAB_SIZE_LOOKUP[tabKey]
    local spec = lookup and lookup()
    if not spec then return end
    local f = self.frame
    local frames = Ace.db.char.frames

    -- Suppress the OnSizeChanged hook's browserWidth/Height save during
    -- programmatic SetWidth/SetHeight below — when switching to a locked
    -- tab the snap to spec.width/height fires OnSizeChanged with the
    -- LOCKED size, which would otherwise overwrite Browser's saved size.
    -- For the resizable branch we restore the saved size explicitly so
    -- there's nothing useful for the hook to capture either; suppression
    -- avoids a redundant save-of-the-same-value.
    self._suppressBrowserSize = true

    if spec.locked then
        -- SetResizeBounds with min == max collapses the resize handle
        -- range to zero — the user can still drag the corner but the
        -- frame won't actually change size. Combined with EnableResize
        -- (false) the grip itself is also hidden. Modern API takes
        -- (minW, minH, maxW, maxH); legacy SetMinResize/SetMaxResize
        -- needs both halves separately.
        f:EnableResize(false)
        if f.frame.SetResizeBounds then
            f.frame:SetResizeBounds(spec.width, spec.height, spec.width, spec.height)
        else
            if f.frame.SetMinResize then f.frame:SetMinResize(spec.width, spec.height) end
            if f.frame.SetMaxResize then f.frame:SetMaxResize(spec.width, spec.height) end
        end
        f.frame:SetWidth(spec.width)
        f.frame:SetHeight(spec.height)
    else
        -- Resizable. Restore Browser's last size (saved separately from
        -- AceGUI's status table — see Open() for why) and clamp the
        -- minimum via SetResizeBounds. No max bound.
        f:EnableResize(true)
        local minW = spec.minWidth  or 600
        local minH = spec.minHeight or 350
        if f.frame.SetResizeBounds then
            f.frame:SetResizeBounds(minW, minH)
        elseif f.frame.SetMinResize then
            f.frame:SetMinResize(minW, minH)
        end
        local w = math.max(minW, frames.mainWindow.browserWidth  or minW)
        local h = math.max(minH, frames.mainWindow.browserHeight or minH)
        f.frame:SetWidth(w)
        f.frame:SetHeight(h)
    end

    self._suppressBrowserSize = false
end

--- Shared release-and-cleanup path used by BOTH OnClose (X-button) and
--- the programmatic Close()/Toggle() path. AceGUI:Release does NOT fire
--- OnClose, so any escape route that ends in Release (ESC key, /togpm
--- toggle, etc.) MUST go through here or the help "i" + gear icons stay
--- parented to f.frame and ride the recycled widget into the next
--- AceGUI:Create("Frame") caller (TOGBank, PersonalShopper, Grouper).
function MainWindow:_ReleaseFrame(widget)
    -- DetachPool: Hide + reparent to UIParent + ClearAllPoints. Defined
    -- in GUI/SharedWidgets.lua. Single-frame form, same helper used by
    -- the row-pool detaches in BrowserTab / MissingRecipesTab.
    addon.GUI.DetachPool(self._helpIcon)
    self._helpIcon = nil
    addon.GUI.DetachPool(self._gearIcon)
    self._gearIcon = nil
    self.frame = nil
    self.tabs  = nil
    _escProxy:Hide()
    if widget then AceGUI:Release(widget) end
end

function MainWindow:Close()
    if self.frame then
        self:_ReleaseFrame(self.frame)
    end
end

function MainWindow:Toggle(tabKey)
    if self.frame then
        self:Close()
    else
        self:Open(tabKey)
    end
end

function MainWindow:SelectTab(key)
    if self.tabs then
        self.tabs:SelectTab(key)
    end
end

-- ---------------------------------------------------------------------------
-- Tab routing
-- ---------------------------------------------------------------------------

-- Set the root frame's bottom-left status-bar text. Safe no-op when the window
-- isn't open. Used for the version string (default, reset on every tab switch
-- in DrawTab) and per-tab status lines such as the Profit Planner row count.
function MainWindow:SetStatusText(text)
    if self.frame and self.frame.SetStatusText then
        self.frame:SetStatusText(text or "")
    end
end

-- The canonical left-of-status-bar string: the version, plus a redraw counter to
-- its right that only appears when debug mode is on (`/togpm debug`). `_redrawCount`
-- bumps on every full tab redraw (MainWindow:Refresh — the guild-sync churn path),
-- so with debug on you can watch the rate live and confirm the "only redraw on real
-- data change" fix keeps it low. Hidden in normal play.
function MainWindow:StatusBase()
    local base = (addon.Version or "")
    if addon.debug then
        base = base .. "    |cff888888[redraws: " .. (self._redrawCount or 0) .. "]|r"
    end
    return base
end

-- The version string is canonical and always leads the status bar. Tabs append
-- their own info (e.g. Profit Planner's row count) as a suffix after it; pass
-- nil/empty to show just the version.
function MainWindow:SetStatusSuffix(suffix)
    local base = self:StatusBase()
    if suffix and suffix ~= "" then
        self:SetStatusText(base .. "    " .. suffix)
    else
        self:SetStatusText(base)
    end
end

function MainWindow:DrawTab(group, container)
    -- Clear any container.LayoutFinished override left over from the
    -- previously-active tab. Missing and Browser install their own
    -- overrides (AnchorAll / AnchorScrollToFill) for custom anchoring,
    -- and those overrides survive tab switches because the TabGroup
    -- widget stays alive across switches — only its children get
    -- released. Without this clear, switching Missing → Cooldowns
    -- leaves Missing's AnchorAll on the container; it fires during
    -- Cooldowns' layout pass, references Missing's stale widget refs,
    -- and silently anchors a recycled-from-Missing scroll frame to
    -- hidden/wrong frames — the scroll viewport collapses and the
    -- scrollbar disappears.
    --
    -- We set this to nil (not back to the class default). TabGroup's
    -- class LayoutFinished does `self:SetHeight((height + borderoffset
    -- + 23))` whose OnHeightSet shrinks `content:SetHeight(height -
    -- borderoffset - 23)` based on the partially-laid-out height —
    -- when fired during a tab's intermediate AddChild passes (e.g.
    -- when Missing has only its toolbar attached so far), it collapses
    -- the content frame to ~0px and squashes everything anchored
    -- inside. The TabGroup is sized by its parent Frame's fill anchors
    -- anyway, so the class auto-size is redundant; nil here is correct.
    -- Missing/Browser then re-set this to their own AnchorAll/etc. as
    -- part of their Draw, which is fine — only the inter-tab leftover
    -- needs to be wiped.
    container.LayoutFinished = nil

    -- Reset the status bar to the addon version on every tab switch. Tabs that
    -- want a custom status line (Profit Planner writes its row count here) over-
    -- write it during their own Draw; this guarantees it reverts when you leave.
    -- (StatusBase = version + the TEMP redraw counter.)
    self:SetStatusText(self:StatusBase())

    if group == "browser" then
        if addon.BrowserTab then
            addon.BrowserTab:Draw(container)
        end
    elseif group == "cooldowns" then
        if addon.CooldownsTab then
            addon.CooldownsTab:Draw(container)
        end
    elseif group == "missing" then
        if addon.MissingRecipesTab then
            addon.MissingRecipesTab:Draw(container)
        end
    elseif group == "guild" then
        if addon.GuildTab then
            addon.GuildTab:Draw(container)
        end
    elseif group == "crafting" then
        if addon.CraftingTab then
            addon.CraftingTab:Draw(container)
        end
    elseif group == "ahprofit" then
        if addon.AHProfitTab then
            addon.AHProfitTab:Draw(container)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Refresh current tab (called after GUILD_DATA_UPDATED)
-- ---------------------------------------------------------------------------

function MainWindow:Refresh()
    if not self.frame or not self.tabs then
        addon:DebugPrint("MainWindow:Refresh ABORT — frame=",
            self.frame and "set" or "nil", "tabs=", self.tabs and "set" or "nil")
        return
    end

    -- Defer the refresh while any toolbar dropdown's pullout is open.
    -- Releasing the tab's children tears down the Dropdown widget,
    -- which closes its pullout mid-interaction — annoying when a guild
    -- sync arrives every few seconds and the user is mid-pick. Re-queue
    -- and re-test on a longer cadence; the user closing the pullout
    -- (either by picking a value or clicking elsewhere) is the natural
    -- gating event. addon.GUI.IsAnyDropdownPulloutOpen lives in
    -- GUI/SharedWidgets.lua and walks AceGUI's global pullout pool.
    -- Defer ONLY while one of OUR OWN dropdown pullouts is open (releasing the
    -- tab's children would shut it mid-pick). Two guards against the bug that
    -- froze refreshes indefinitely — purge/sync never redrawing until a manual
    -- tab switch:
    --   1. Scope to our window frame. The AceGUI30PulloutN frames are GLOBAL,
    --      shared across every AceGUI-3.0 addon, so a foreign or leaked-shown
    --      pullout used to make the old global check return true forever.
    --   2. Cap the retries, so even our own open pullout can't hang us.
    local rootFrame = self.frame and self.frame.frame
    local pulloutOpen = rootFrame and addon.GUI and addon.GUI.IsAnyDropdownPulloutOpen
                        and addon.GUI.IsAnyDropdownPulloutOpen(rootFrame)
    local typing      = addon.GUI and addon.GUI.IsAnySearchFocused
                        and addon.GUI.IsAnySearchFocused()
    if (pulloutOpen or typing) and (self._refreshDeferrals or 0) < 8 then
        self._refreshDeferrals = (self._refreshDeferrals or 0) + 1
        addon:DebugPrint("MainWindow:Refresh DEFERRED —",
            typing and "search field focused" or "our dropdown pullout open",
            "(", self._refreshDeferrals, "/8); re-try in 0.25s")
        if self._refreshTimer then self._refreshTimer:Cancel() end
        self._refreshTimer = C_Timer.NewTimer(0.25, function()
            self._refreshTimer = nil
            self:Refresh()
        end)
        return
    end
    self._refreshDeferrals = 0

    self._redrawCount = (self._redrawCount or 0) + 1   -- perf-churn counter (shown in status bar when debug is on)
    addon:DebugPrint("MainWindow:Refresh — ReleaseChildren + DrawTab(", self.activeTab, ")")
    self.tabs:ReleaseChildren()
    self:DrawTab(self.activeTab, self.tabs)
end

-- Debounced refresh — defers the redraw out of the message-handler context
-- so AceGUI layout isn't called mid-callback.  Rapid back-to-back data
-- updates (multiple guild members syncing at once) collapse into one redraw.
function MainWindow:QueueRefresh()
    addon:DebugPrint("MainWindow:QueueRefresh — scheduling Refresh in 0.05s")
    if self._refreshTimer then
        self._refreshTimer:Cancel()
    end
    self._refreshTimer = C_Timer.NewTimer(0.05, function()
        self._refreshTimer = nil
        addon:DebugPrint("MainWindow:QueueRefresh — timer fired -> Refresh()")
        self:Refresh()
    end)
end

-- ---------------------------------------------------------------------------
-- Slash command stubs (override the ones created in TOGProfessionMaster.lua)
-- ---------------------------------------------------------------------------

function addon:OpenBrowser()
    -- Generic "open the addon" entry (minimap click, bare /togpm). Pass NO tab
    -- so Open() restores the last-used tab (db.char.lastMainTab); it falls back
    -- to "browser" only when nothing is saved. Passing "browser" here would
    -- override the saved tab and always force the Professions tab.
    MainWindow:Toggle()
end

-- addon:OpenReagents() is defined in GUI/ReagentTracker.lua

-- ---------------------------------------------------------------------------
-- React to guild data updates from Scanner
-- ---------------------------------------------------------------------------

-- Which change-scopes each tab actually renders. GUILD_DATA_UPDATED carries a
-- scope set describing WHICH kind of data changed (see Scanner's fire sites); a
-- refresh whose scope is disjoint from the active tab's interests is skipped —
-- e.g. a cooldown sync must not tear down and rebuild the 19k-crafter recipe
-- Browser, which renders no cooldown data. A nil/empty scope (legacy or unknown
-- caller) always refreshes, so this can only ever REDUCE redraws, never miss one
-- a tab genuinely needs.
-- `roster` belongs to every GUILD-SCOPED tab, not just the Guild tab. All four
-- of them filter what they render through IsVisibleCrafter / IsInCurrentGuildScope,
-- so a change in roster truth — most importantly the roster becoming ready after
-- login, which is when the "hide nothing yet" cold-start guard lifts — changes
-- what each of them should display. Leaving it only on `guild` is why a departed
-- member kept showing on the Professions and Cooldowns tabs after a reload.
-- crafting / ahprofit are excluded on purpose: they render YOUR OWN craftables
-- and aren't roster-filtered.
local TAB_SCOPES = {
    browser   = { recipes = true, altgroups = true, roster = true },
    cooldowns = { cooldowns = true, roster = true },
    missing   = { recipes = true, altgroups = true, roster = true },
    guild     = { skills = true, recipes = true, altgroups = true, roster = true },
    crafting  = { recipes = true },
    ahprofit  = { recipes = true },
}

local function activeTabCaresAbout(activeTab, scopes)
    if type(scopes) ~= "table" then return true end   -- unknown → refresh
    if not next(scopes) then return true end          -- empty → refresh
    local interests = TAB_SCOPES[activeTab]
    if not interests then return true end             -- unknown tab → refresh
    for scope in pairs(scopes) do
        if interests[scope] then return true end
    end
    return false
end

hooksecurefunc(Ace, "OnEnable", function(_self)
    addon:RegisterCallback("GUILD_DATA_UPDATED", function(_event, _charKey, scopes)
        if not activeTabCaresAbout(MainWindow.activeTab, scopes) then
            addon:DebugPrint("MainWindow: GUILD_DATA_UPDATED skipped — tab",
                MainWindow.activeTab, "renders none of the changed scope")
            return
        end
        MainWindow:QueueRefresh()
    end)
end)
