-- TOG Profession Master — Guild Tab
-- A read-only overview of the guild's crafting capacity: how many characters
-- hold each profession, broken down by specialization (Dragonscale / Elemental
-- / Tribal Leatherworking, Armorsmith / Weaponsmith Blacksmithing, etc.).
--
-- Data sources (both already synced across the guild — no new sync traffic):
--   gdb.skills[charKey][profId]           → who has each profession
--   gdb.specializations[charKey][profId]  → that character's spec spellId
-- Spec display names resolve at runtime via GetSpellInfo(specSpellId).
--
-- Coverage note: professions are only tracked once their recipe window has been
-- scanned by an addon user, so counts reflect characters KNOWN to the addon
-- (guildmates running TOGPM + their synced alts), not the whole roster, and
-- gathering professions (no recipe window) don't appear.

local _, addon = ...
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local GuildTab = {}
addon.GuildTab = GuildTab

-- Locked to the same dimensions as Cooldowns / Missing so tab switches don't
-- resize the window.
GuildTab.WINDOW_SIZE = { width = 720, height = 500, locked = true }

local NAME_W  = 320   -- profession / spec name column
local COUNT_W = 80    -- character-count column

-- Blacksmithing sub-spec → parent (Weaponsmith). A swordsmith knows both the
-- parent Weaponsmith recipes AND the finer Swordsmith recipes, so when inferring
-- a spec from known recipes we prefer the more specific sub-spec. Mirrors the
-- SPEC_PARENT table in MissingRecipesTab (kept local — tiny, BS-only).
local SPEC_PARENT = {
    [17039] = 9787,  -- Master Swordsmith  → Weaponsmith
    [17040] = 9787,  -- Master Hammersmith → Weaponsmith
    [17041] = 9787,  -- Master Axesmith    → Weaponsmith
}

-- Count entries in a set-style table (charKey → true).
-- Shared, not a private copy: this one raised on nil where the other two
-- copies of the same function returned 0. addon.UI.Count takes the safe form.
-- Resolved at call time, not captured at file scope — audit finding 6; see the
-- note in CraftingTab.lua.
local function countSet(t) return addon.UI.Count(t) end

-- EVERY profession available on this client is shown even at 0 — the Guild tab is
-- a COMPLETE, guild-wide "who has what", not a "what do I have" list, so a
-- profession nobody has must still appear (with a 0) so the gap is visible. Covers
-- all crafting professions plus the recipe-less gathering ones (Herbalism /
-- Skinning / Fishing / Archaeology). Smelting (374) is excluded — it's Mining's
-- window, not a standalone profession. Version-gated via IsProfessionAvailable and
-- the is* flags (Compat + TOGProfessionMaster.lua both load before this file).
local ALWAYS_SHOW_PROFS = {}
do
    local function add(p)
        if (not addon.IsProfessionAvailable) or addon.IsProfessionAvailable(p) then
            ALWAYS_SHOW_PROFS[#ALWAYS_SHOW_PROFS + 1] = p
        end
    end
    for p in pairs(addon.CRAFTING_PROFS or {}) do add(p) end
    add(182); add(393); add(356)                       -- Herbalism / Skinning / Fishing
    if addon.isCata or addon.isMoP or addon.isRetail then add(794) end   -- Archaeology (Cata+)
end

-- Canonical specialization list per profession, so the Guild tab can list EVERY
-- spec — even at 0 — letting officers spot "nobody covers this". VERSION-GATED:
-- the proc/bonus specializations were removed in Cata 4.0.1 (so Cata/Mists get
-- none), and Alchemy/Tailoring specs only arrived in TBC — we surface only the
-- ones that actually exist on this client. Spell IDs match SPEC_SPELLS in
-- Scanner and the requiredSpec values in the recipe DB, so 0-fill entries land
-- in the same buckets as detected/inferred ones.
local ALL_SPECS = {}
do
    if addon.isVanilla or addon.isTBC or addon.isWrath then
        ALL_SPECS[202] = { 20219, 20222 }                     -- Engineering: Gnomish / Goblin
        ALL_SPECS[165] = { 10656, 10658, 10660 }              -- Leatherworking: Dragonscale / Elemental / Tribal
        -- Blacksmithing: Armorsmith / Weaponsmith / Swordsmith / Hammersmith / Axesmith
        ALL_SPECS[164] = { 9788, 9787, 17039, 17040, 17041 }
    end
    if addon.isTBC or addon.isWrath then
        -- Alchemy: Transmutation / Potion / Elixir Master (TBC+; DBC-verified)
        ALL_SPECS[171] = { 28672, 28675, 28677 }
        -- Tailoring: Spellfire / Mooncloth / Shadoweave (TBC+; 26802 was
        -- "Detect Amore", 26798 is Mooncloth)
        ALL_SPECS[197] = { 26797, 26798, 26801 }
    end
end

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

-- Returns (sortedProfList, totalTrackedCharacters).
-- Each prof entry: { profId, name, total, specs = { { name, count } ... } }.
-- specs is empty for professions with no recorded specialization; when a
-- profession has at least one specced character, an "Unspecialized" bucket is
-- appended for the remainder.
function GuildTab:BuildCounts()
    local gdb = addon:GetGuildDb()

    -- Per profession, the SET of characters who HAVE that profession. Sourced
    -- from the union of two signals, because neither alone is complete:
    --   • gdb.skills[ck][profId]                     — recorded when that char
    --       opens their profession window with the addon watching. Direct, but
    --       many crafters never trigger it, so it undercounts.
    --   • gdb.recipes[profId][*].crafters[ck]        — anyone known to craft any
    --       recipe in the profession. Richly synced (this is what the Sync Log's
    --       "crafters:<profId>" traffic carries), so it fills the gaps.
    -- Every crafter necessarily has the profession, so the union is a valid —
    -- and far more complete — "who is a <profession>" count.
    local members = {}   -- [profId] = { [charKey] = true }
    local function addMember(profId, charKey)
        local set = members[profId]
        if not set then set = {}; members[profId] = set end
        set[charKey] = true
    end

    -- Inferred specs: a crafter who knows a spec-GATED recipe must hold that spec
    -- (a Tribal-only pattern can only be learned by a Tribal leatherworker). This
    -- recovers specs for EVERY synced crafter — not just addon users whose locally
    -- IsSpellKnown-detected spec synced — using the requiredSpec shipped in
    -- addon.recipeDB (the same field the Missing tab filters with).
    local inferred = {}   -- [profId] = { [charKey] = specSpellId }
    local function noteInferred(profId, charKey, spec)
        local m = inferred[profId]
        if not m then m = {}; inferred[profId] = m end
        -- Prefer a sub-spec over its parent (a swordsmith knows both Weaponsmith
        -- and Swordsmith recipes → classify as Swordsmith). SPEC_PARENT[spec]
        -- being set means `spec` is the finer sub-spec, so always take it.
        if not m[charKey] or SPEC_PARENT[spec] then m[charKey] = spec end
    end

    -- Both signals are account-wide (skills + crafters are keyed by charKey
    -- across every guild), so scope each character to the current guild before
    -- counting — otherwise your own cross-guild alts (and any not-yet-purged
    -- foreign crafters) inflate this guild's profession headcounts.
    --
    -- Memoized per call, by charKey: a crafter appears under every recipe they
    -- know, so the unmemoized check ran once per recipe-crafter pair (~37k on a
    -- large guild, each a roster lookup plus a guild-key / character-key build)
    -- to answer ~700 distinct questions. The answer cannot change within one
    -- BuildCounts pass, which reads the roster and nothing writes it meanwhile.
    local scopeMemo = {}
    local function inScope(charKey)
        local v = scopeMemo[charKey]
        if v == nil then
            v = addon:IsInCurrentGuildScope(charKey) and true or false
            scopeMemo[charKey] = v
        end
        return v
    end
    if gdb then
        if gdb.skills then
            for charKey, profs in pairs(gdb.skills) do
                if inScope(charKey) then
                    for profId in pairs(profs) do addMember(profId, charKey) end
                end
            end
        end
        if gdb.recipes then
            for profId, recps in pairs(gdb.recipes) do
                local profMeta = addon.recipeDB and addon.recipeDB[profId]
                for recipeId, rd in pairs(recps) do
                    if rd.crafters then
                        local meta = profMeta and profMeta[recipeId]
                        local req  = meta and meta.requiredSpec
                        for charKey in pairs(rd.crafters) do
                            if inScope(charKey) then
                                addMember(profId, charKey)
                                if req then noteInferred(profId, charKey, req) end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Force a row for the recipe-less gathering professions even when nobody has
    -- one recorded yet, so the guild can see the coverage gap. Crafting professions
    -- surface themselves through recipe/skill data; these have neither until synced.
    for _, profId in ipairs(ALWAYS_SHOW_PROFS) do
        if not members[profId] then members[profId] = {} end
    end

    local specs    = gdb and gdb.specializations
    local out      = {}
    local allChars = {}
    for profId, set in pairs(members) do
        local total  = 0
        local bySpec = {}   -- specSpell → { charKey set }
        local noSpec = {}   -- charKey set (no known/inferred spec)
        for charKey in pairs(set) do
            total = total + 1
            allChars[charKey] = true
            -- Prefer the synced (IsSpellKnown-detected) spec; fall back to the spec
            -- inferred from the crafter's spec-gated recipes so non-addon-users are
            -- categorised too. Both use the same spell IDs (requiredSpec == the
            -- IsSpellKnown spell), so they land in the same bySpec bucket.
            local specSpell = specs and specs[charKey] and specs[charKey][profId]
            if not specSpell then
                specSpell = inferred[profId] and inferred[profId][charKey]
            end
            if specSpell then
                local b = bySpec[specSpell]
                if not b then b = {}; bySpec[specSpell] = b end
                b[charKey] = true
            else
                noSpec[charKey] = true
            end
        end

        -- Each spec entry keeps its OWN member set so the spec row can expand to
        -- show its people (second-level [+] under the profession).
        local specList = {}
        for specSpell, memberSet in pairs(bySpec) do
            specList[#specList + 1] = {
                key       = specSpell,
                name      = addon.Spell.GetInfo(specSpell) or ("Spell " .. specSpell),
                count     = countSet(memberSet),
                memberSet = memberSet,
            }
        end
        -- List every canonical spec for this profession, even at 0, so a coverage
        -- gap ("nobody does Axesmith") is visible. Only for professions that HAVE
        -- specs on this client version (ALL_SPECS is version-gated).
        local canon = ALL_SPECS[profId]
        if canon then
            local present = {}
            for _, e in ipairs(specList) do present[e.key] = true end
            for _, specSpell in ipairs(canon) do
                if not present[specSpell] then
                    specList[#specList + 1] = {
                        key       = specSpell,
                        name      = addon.Spell.GetInfo(specSpell) or ("Spell " .. specSpell),
                        count     = 0,
                        memberSet = {},
                    }
                end
            end
        end
        table.sort(specList, function(a, b) return a.name < b.name end)
        -- Only surface an "Unspecialized" bucket when the profession actually has
        -- specializations recorded — otherwise (Enchanting, Cooking, ...) the
        -- total line alone is the whole story and the profession expands to a flat
        -- member list instead.
        local noSpecCount = countSet(noSpec)
        if #specList > 0 and noSpecCount > 0 then
            specList[#specList + 1] = {
                key       = "unspec",
                name      = L["GuildUnspecialized"],
                count     = noSpecCount,
                memberSet = noSpec,
            }
        end

        out[#out + 1] = {
            profId    = profId,
            name      = addon.PROF_NAMES[profId] or ("Profession " .. profId),
            total     = total,
            specs     = specList,
            memberSet = set,   -- full set — used for professions with NO specs
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)

    local totalChars = 0
    for _ in pairs(allChars) do totalChars = totalChars + 1 end
    return out, totalChars
end

-- Build the online/offline-sorted display list of everyone who HAS a profession,
-- reusing the Professions-tab conventions verbatim: your own characters render as
-- "You" (brand colour) and count as online; online guildmates are white, offline
-- grey; an offline main whose ALT is online shows as "altName (mainName)" and
-- counts as online. Online-first, then alphabetical. The member SET comes straight
-- from BuildCounts, so this list always matches the profession's headcount.
function GuildTab:BuildMemberList(memberSet, profId)
    local GuildRoster = addon.Scanner and addon.Scanner.GuildRoster
    local gdb         = addon:GetGuildDb()
    local myKey       = addon:GetCharacterKey()
    local objs = {}
    for ck in pairs(memberSet) do
        local shortName = ck:match("^(.-)%-") or ck
        local isYou     = addon:IsMyCharacter(ck)
        local online, displayName
        if isYou then
            online      = true
            displayName = (ck == myKey) and L["You"]
                          or (L["You"] .. " (" .. shortName .. ")")
        else
            online      = (GuildRoster and GuildRoster:IsOnline(ck)) or false
            displayName = shortName
            -- Offline main whose alt is online → show the alt, count as online.
            if not online and gdb and gdb.altGroups and gdb.altGroups[ck] then
                for _, altCk in ipairs(gdb.altGroups[ck]) do
                    if altCk ~= ck and GuildRoster and GuildRoster:IsOnline(altCk) then
                        displayName = (altCk:match("^(.-)%-") or altCk)
                                      .. " (" .. shortName .. ")"
                        online = true
                        break
                    end
                end
            end
        end
        -- Enrich with this character's skill level for the profession, e.g.
        -- "You (300/300)". Rendered separately (own grey colour) so it doesn't
        -- disturb the online/offline colouring of the name. Skills sync via the
        -- crafters: leaf (recipe profs) and the skills: leaf (gathering profs).
        local skillText = ""
        local sk = profId and gdb and gdb.skills and gdb.skills[ck] and gdb.skills[ck][profId]
        if sk and sk.skillRank and sk.skillRank > 0 then
            -- Show against this expansion's real cap (addon.SKILL_CAP: TBC 375,
            -- Wrath 450, …) rather than the per-character skillMax, which is often a
            -- stale Vanilla-era 300 and renders the impossible "375/300". Clamped to
            -- at least the rank as a final guard against odd data.
            local cap = math.max(sk.skillRank, addon.SKILL_CAP or sk.skillMax or sk.skillRank)
            skillText = " |cff888888(" .. sk.skillRank .. "/" .. cap .. ")|r"
        end
        objs[#objs + 1] = { name = displayName, online = online, isYou = isYou, skillText = skillText }
    end
    table.sort(objs, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return objs
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function GuildTab:FillContent(scroll)
    local data, totalChars = self:BuildCounts()

    -- Tracked-character count goes in the window status bar (same pattern as the
    -- Profit Planner's row count), so the list isn't topped by a redundant title
    -- — the "Guild" tab label already names the view.
    if addon.MainWindow and addon.MainWindow.SetStatusText then
        addon.MainWindow:SetStatusText("|c" .. (addon.BrandColor or "ffFF8000")
            .. string.format(L["GuildTabChars"], totalChars) .. "|r")
    end

    if #data == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetText(L["GuildTabEmpty"])
        scroll:AddChild(empty)
        self:SetTree({})
        return
    end

    -- Column headers via the shared factory — brand colour, no-wrap, and the
    -- hover tooltips the CLAUDE.md header rule calls for.
    local hdr = AceGUI:Create("SimpleGroup")
    hdr:SetFullWidth(true)
    hdr:SetLayout("Flow")
    scroll:AddChild(hdr)
    addon.GUI.MakeColumnHeader({
        parent = hdr, width = NAME_W, label = L["GuildColProfession"],
        tooltipTitle = L["GuildColProfession"], tooltipDesc = L["GuildColProfessionDesc"],
    })
    addon.GUI.MakeColumnHeader({
        parent = hdr, width = COUNT_W, label = L["GuildColCount"],
        tooltipTitle = L["GuildColCount"], tooltipDesc = L["GuildColCountDesc"],
    })

    self:SetTree(self:BuildTree(data))
end

-- "ffRRGGBB" -> { r, g, b } for the expandable list's `color`.
local function rgb(hex)
    hex = hex or "ffffffff"
    return { tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
             tonumber(hex:sub(7, 8), 16) / 255 }
end

--- The profession -> specialisation -> member tree as LibAceGUIWidgets'
--- CreateExpandableList nodes (MINOR 36, TOGPM contract 7ab1cb56). Keys are the
--- profession id and the spec key, and the list keys its expand state by the
--- PATH, so two specs sharing a name under two professions keep their own state.
---   * A 0-count profession (a gathering one nobody has yet) is a dimmed leaf:
---     the coverage gap is visible, and there is nothing to drill into.
---   * A 0-count spec is a dimmed leaf too ("no one does that thing").
---   * A profession with no specialisations recorded expands straight to its
---     members.
---   * Members are coloured like the Professions tab: white online, grey
---     offline, brand colour for You; the skill level follows in grey.
function GuildTab:BuildTree(data)
    local cOnline  = rgb(addon.ColorOnline  or "ffffffff")
    local cOffline = rgb(addon.ColorOffline or "ff888888")
    local cYou     = rgb(addon.ColorYou     or addon.BrandColor or "ffFF8000")
    local DIM, DIMMER, SPEC = rgb("ff888888"), rgb("ff666666"), rgb("ffaaaaaa")

    local function members(memberSet, profId)
        local out = {}
        for _, m in ipairs(self:BuildMemberList(memberSet, profId)) do
            out[#out + 1] = {
                label = m.name .. (m.skillText or ""),
                color = m.isYou and cYou or (m.online and cOnline or cOffline),
            }
        end
        return out
    end

    local tree = {}
    for _, prof in ipairs(data) do
        local node = { key = prof.profId, label = prof.name, valueText = tostring(prof.total) }
        if prof.total == 0 then
            node.color = DIM
        elseif #prof.specs > 0 then
            node.children = {}
            for _, spec in ipairs(prof.specs) do
                local s = { key = spec.key, label = spec.name, valueText = tostring(spec.count) }
                if spec.count > 0 and spec.memberSet then
                    s.color, s.children = SPEC, members(spec.memberSet, prof.profId)
                else
                    s.color = DIMMER
                end
                node.children[#node.children + 1] = s
            end
        elseif prof.memberSet then
            node.children = members(prof.memberSet, prof.profId)
        end
        tree[#tree + 1] = node
    end
    return tree
end

--- Hand the tree to the list. The list is built ONCE per session and parked in
--- each draw's host group: its rows are pooled and its expand state survives a
--- redraw, so a guild-data refresh keeps what the player had open, and a toggle
--- re-lays the rows without rebuilding the tab.
function GuildTab:SetTree(tree)
    if self._list then self._list:SetData(tree) end
end

function GuildTab:Draw(container)
    self._container = container
    container:SetLayout("Flow")

    -- Column headers first (FillContent), then the tree in a group that fills
    -- the rest of the tab.
    local top = AceGUI:Create("SimpleGroup")
    top:SetFullWidth(true)
    top:SetLayout("List")
    container:AddChild(top)

    local host = AceGUI:Create("SimpleGroup")
    host:SetFullWidth(true)
    host:SetFullHeight(true)
    host:SetLayout("Fill")
    container:AddChild(host)

    if addon.W then
        if not self._list then
            self._list = addon.W:CreateExpandableList(host.content, { indent = 14 })
        end
        local frame = self._list.frame
        frame:SetParent(host.content)
        frame:ClearAllPoints()
        frame:SetAllPoints(host.content)
        frame:Show()
        -- The list's frame is ours on a pooled widget: handed back to UIParent
        -- when this group is released (a tab switch or the window closing).
        addon.W:AttachRawFrames(host, frame)
    end

    self:FillContent(top)
end

-- Kept for callers that redraw the tab after its data changed.
function GuildTab:Refresh()
    if not self._container then return end
    self._container:ReleaseChildren()
    self:Draw(self._container)
end
