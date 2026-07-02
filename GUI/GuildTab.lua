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
local function countSet(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Recipe-less GATHERING professions that should ALWAYS appear on the Guild tab,
-- even at 0, so the guild can see coverage ("who herbs" — and that nobody does X).
-- Unlike crafting professions (which only appear once someone has one), these
-- have no recipes to surface them, so we force a row. Version-gated: Herbalism /
-- Skinning / Fishing exist on every client; Archaeology is Cata+.
local ALWAYS_SHOW_PROFS = { 182, 393, 356 }  -- Herbalism, Skinning, Fishing
if addon.isCata or addon.isMoP then
    ALWAYS_SHOW_PROFS[#ALWAYS_SHOW_PROFS + 1] = 794  -- Archaeology
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
        ALL_SPECS[164] = { 9788, 9787, 17039, 17040, 17041 }  -- Blacksmithing: Armorsmith / Weaponsmith / Swordsmith / Hammersmith / Axesmith
    end
    if addon.isTBC or addon.isWrath then
        ALL_SPECS[171] = { 28677, 28682, 28683 }              -- Alchemy: Potion / Elixir / Transmutation Master (TBC+)
        ALL_SPECS[197] = { 26797, 26801, 26802 }              -- Tailoring: Mooncloth / Shadoweave / Spellfire (TBC+)
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

    if gdb then
        if gdb.skills then
            for charKey, profs in pairs(gdb.skills) do
                for profId in pairs(profs) do addMember(profId, charKey) end
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
                            addMember(profId, charKey)
                            if req then noteInferred(profId, charKey, req) end
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
                name      = GetSpellInfo(specSpell) or ("Spell " .. specSpell),
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
                        name      = GetSpellInfo(specSpell) or ("Spell " .. specSpell),
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
            skillText = " |cff888888(" .. sk.skillRank
                        .. "/" .. (sk.skillMax or sk.skillRank) .. ")|r"
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

    local brand        = "|c" .. (addon.BrandColor or "ffFF8000")
    local colorOnline  = "|c" .. (addon.ColorOnline  or "ffffffff")
    local colorOffline = "|c" .. (addon.ColorOffline or "ff888888")
    local colorYou     = "|c" .. (addon.ColorYou     or addon.BrandColor or "ffFF8000")

    -- One expandable [+]/[-] row: name (indented, coloured) + right-aligned count,
    -- clickable across the name to toggle. Both the profession and each spec use it.
    local function addExpandRow(isOpen, indent, nameColor, name, count, onClick)
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        local nameLbl = AceGUI:Create("InteractiveLabel")
        nameLbl:SetWidth(NAME_W)
        nameLbl:SetText(indent .. brand .. (isOpen and "[-]" or "[+]") .. "|r "
                        .. nameColor .. name .. "|r")
        nameLbl:SetCallback("OnClick", onClick)
        row:AddChild(nameLbl)
        local countLbl = AceGUI:Create("Label")
        countLbl:SetWidth(COUNT_W)
        countLbl:SetText(nameColor .. count .. "|r")
        row:AddChild(countLbl)
        scroll:AddChild(row)
    end

    -- A non-expandable row (name + count), aligned under the expandable rows by
    -- padding where their "[+] " marker sits. Used for 0-count specs so an empty
    -- specialization is visible without a misleading expand affordance.
    local function addPlainRow(indent, nameColor, name, count)
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        local nameLbl = AceGUI:Create("Label")
        nameLbl:SetWidth(NAME_W)
        nameLbl:SetText(indent .. "     " .. nameColor .. name .. "|r")
        row:AddChild(nameLbl)
        local countLbl = AceGUI:Create("Label")
        countLbl:SetWidth(COUNT_W)
        countLbl:SetText(nameColor .. count .. "|r")
        row:AddChild(countLbl)
        scroll:AddChild(row)
    end

    -- Member leaf rows, coloured online/offline exactly like the Professions tab
    -- (white online, grey offline, brand-colour "You"; an online alt surfaces its
    -- offline main). indent sets the tree depth.
    local function addMemberRows(memberSet, indent, profId)
        for _, m in ipairs(self:BuildMemberList(memberSet, profId)) do
            local col = m.isYou and colorYou or (m.online and colorOnline or colorOffline)
            local lbl = AceGUI:Create("Label")
            lbl:SetFullWidth(true)
            lbl:SetText(indent .. col .. m.name .. "|r" .. (m.skillText or ""))
            scroll:AddChild(lbl)
        end
    end

    for _, prof in ipairs(data) do
        local pOpen = self._expanded and self._expanded[prof.profId]

        -- A 0-count profession (a gathering profession nobody has yet) renders
        -- dimmed and non-expandable — the coverage gap is visible, but there's
        -- nothing to drill into.
        if prof.total == 0 then
            addPlainRow("", "|cff888888", prof.name, prof.total)
        else
        -- Level 1: profession. Expands to show its specs (or, for spec-less
        -- professions like First Aid, a flat member list).
        addExpandRow(pOpen, "", "|cffffffff", prof.name, prof.total, function()
            self._expanded = self._expanded or {}
            self._expanded[prof.profId] = not self._expanded[prof.profId]
            self:Refresh()
        end)

        if pOpen then
            if #prof.specs > 0 then
                for _, spec in ipairs(prof.specs) do
                    if spec.count > 0 then
                        -- Level 2: spec. Its own [+]/[-] expands to the people in it.
                        local sKey  = tostring(prof.profId) .. ":" .. tostring(spec.key)
                        local sOpen = self._specExpanded and self._specExpanded[sKey]
                        addExpandRow(sOpen, "      ", "|cffaaaaaa", spec.name, spec.count,
                            function()
                                self._specExpanded = self._specExpanded or {}
                                self._specExpanded[sKey] = not self._specExpanded[sKey]
                                self:Refresh()
                            end)
                        -- Level 3: the members of this spec.
                        if sOpen and spec.memberSet then
                            addMemberRows(spec.memberSet, "            ", prof.profId)
                        end
                    else
                        -- Nobody has this spec: show it dimmed and non-expandable so
                        -- the coverage gap is visible ("no one does that thing").
                        addPlainRow("      ", "|cff666666", spec.name, spec.count)
                    end
                end
            elseif prof.memberSet then
                -- No specializations recorded — expand straight to the member list.
                addMemberRows(prof.memberSet, "      ", prof.profId)
            end
        end
        end  -- close the `else` (prof.total > 0) branch
    end
end

-- Re-render in place after an expand/collapse toggle. Mirrors MainWindow's
-- tab-switch path (ReleaseChildren + Draw) so PersistentScroll restores the
-- scroll position across the rebuild.
function GuildTab:Refresh()
    if not self._container then return end
    self._container:ReleaseChildren()
    self:Draw(self._container)
end

function GuildTab:Draw(container)
    self._container = container   -- kept so Refresh() (expand toggle) can rebuild
    container:SetLayout("Fill")

    local scroll, saved = addon.GUI.PersistentScroll.Acquire(self, {
        key = "guild", layout = "List", fullWidth = true, fullHeight = true,
    })
    container:AddChild(scroll)
    self._scroll = scroll

    self:FillContent(scroll)

    if scroll.DoLayout then scroll:DoLayout() end
    addon.GUI.PersistentScroll.Restore(scroll, saved)
end
