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

-- The smallest window this tab's content fits. MainWindow:ApplyTabSize gives
-- every tab one shared size whose floor is the largest such minimum.
GuildTab.WINDOW_SIZE = { minWidth = 720, minHeight = 500 }

-- At scale 1.0. The list scales its count column by LibAceGUIWidgets' scale
-- (one setting shared by every addon on the client), so the headers go through
-- GuildTab:ColumnWidths to stay over it. At the 2.0 maximum the two come to
-- 800px in a 720px window. Neither column shrinks for it, so the count column
-- overruns the right edge at that scale (arithmetic, not seen in game).
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
-- Filter
-- ---------------------------------------------------------------------------

-- The filter strip's state, kept for the session so a tab switch or a data
-- refresh does not clear what the player typed. `text` is lower-cased; the
-- bounds are CRAFTING skill in the profession being counted, and a nil bound
-- means no limit on that side.
---@type { text: string, rawText: string|nil, minSkill: integer|nil, maxSkill: integer|nil }
GuildTab._filter = { text = "", rawText = nil, minSkill = nil, maxSkill = nil }

-- "ffRRGGBB" -> { r, g, b } for the expandable list's `color`.
local function rgb(hex)
    hex = hex or "ffffffff"
    return { tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
             tonumber(hex:sub(7, 8), 16) / 255 }
end

function GuildTab:IsFiltering()
    local f = self._filter
    return f.text ~= "" or f.minSkill ~= nil or f.maxSkill ~= nil
end

-- The top of the skill-range steppers: this expansion's profession cap
-- (addon.SKILL_CAP: 300 Classic Era, 375 TBC, 450 Wrath, 525 Cata, 600 MoP).
-- Retail has no single cap, so it takes the highest skillMax anyone in the
-- guild DB has recorded, and 100 (a Retail expansion line's cap) before any.
function GuildTab:SkillCap()
    if addon.SKILL_CAP then return addon.SKILL_CAP end
    local best = 0
    local gdb = addon:GetGuildDb()
    for _, profs in pairs(gdb and gdb.skills or {}) do
        for _, sk in pairs(profs) do
            local m = tonumber(sk.skillMax)
            if m and m > best then best = m end
        end
    end
    return best > 0 and best or 100
end

-- A character's recorded skill in one profession, or nil when it was never
-- recorded (a crafter known only from the recipes they make).
local function memberSkill(charKey, profId)
    local gdb = addon:GetGuildDb()
    local sk = gdb and gdb.skills and gdb.skills[charKey] and gdb.skills[charKey][profId]
    local rank = sk and tonumber(sk.skillRank)
    if rank and rank > 0 then return rank end
    return nil
end

-- Does `text` (lower-cased) occur in this label, ignoring colour codes?
local function textHit(label, text)
    return label ~= nil and tostring(label):lower():find(text, 1, true) ~= nil
end

--- Does the search text match this CHARACTER? A plain, case-insensitive
--- substring of the character's name (realm excluded); "You" for your own
--- characters, as the list labels them; and any account-mate's name, because
--- an offline main is listed under its online alt's name ("Alt (Main)").
function GuildTab:NameMatches(charKey)
    local text = self._filter.text
    if text == "" then return true end
    local function hit(ck) return textHit(ck:match("^(.-)%-") or ck, text) end
    if hit(charKey) then return true end
    if addon:IsMyCharacter(charKey) and textHit(L["You"], text) then return true end
    local gdb  = addon:GetGuildDb()
    local alts = gdb and gdb.altGroups and gdb.altGroups[charKey]
    for _, altCk in ipairs(alts or {}) do
        if hit(altCk) then return true end
    end
    return false
end

--- Does this character's skill in `profId` pass the SKILL range? It needs a
--- recorded skill: while a range is set, a character with none recorded for
--- that profession is hidden rather than guessed into it. The search text is
--- not tested here: it can match a profession or specialisation as well as a
--- name, so BuildTree applies it, where it can see all three.
function GuildTab:MemberPasses(charKey, profId)
    local f = self._filter
    if f.minSkill or f.maxSkill then
        local rank = memberSkill(charKey, profId)
        if not rank then return false end
        if f.minSkill and rank < f.minSkill then return false end
        if f.maxSkill and rank > f.maxSkill then return false end
    end
    return true
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
    -- The skill range is per profession, so it is tested here rather than in
    -- the per-character scope memo: a character can be inside it for one
    -- profession and outside it for another.
    local function addMember(profId, charKey)
        if not self:MemberPasses(charKey, profId) then return end
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
    -- A character the skill range hides is simply not counted (addMember), so
    -- every headcount reads "how many MATCHING characters have this".
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
            displayName = displayName .. addon:CharGuildSuffix(ck)
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

-- Recount and re-hand the tree to the list. A filter change runs only this,
-- never a redraw, so the box being typed in keeps its caret. Returns the
-- profession list so the first draw can tell an empty guild from an empty
-- filter.
function GuildTab:Update()
    local data, totalChars = self:BuildCounts()

    -- Tracked-character count goes in the window status bar (same pattern as the
    -- Profit Planner's row count), so the list isn't topped by a redundant title
    -- — the "Guild" tab label already names the view.
    if addon.MainWindow and addon.MainWindow.SetStatusText then
        addon.MainWindow:SetStatusText("|c" .. (addon.BrandColor or "ffFF8000")
            .. string.format(L["GuildTabChars"], totalChars) .. "|r")
    end

    local tree = self:BuildTree(data)
    if #tree == 0 and self:IsFiltering() then
        tree[1] = { key = "nomatch", label = L["GuildNoMatches"], color = rgb("ff888888") }
    end
    self:SetTree(tree)
    return data
end

-- The filter strip: a search and a crafting-skill range. Every change
-- re-runs Update, which recounts with the filter applied.
function GuildTab:DrawFilterBar(parent)
    local bar = AceGUI:Create("SimpleGroup")
    bar:SetFullWidth(true)
    bar:SetLayout("Flow")
    parent:AddChild(bar)

    local f = self._filter
    -- This draw's token. The search is debounced, so its timer can fire after
    -- a tab switch has released this strip; Update would then write the Guild
    -- count into another tab's status bar. A released strip clears the token.
    local token = {}
    self._drawToken = token
    if addon.W then
        addon.W:OnWidgetRelease(bar, "togpm:guildFilter", function()
            if self._drawToken == token then self._drawToken = nil end
        end)
    end
    addon.GUI.ToolbarSearch(bar, {
        width       = 260,
        aligned     = true,
        text        = f.rawText or "",
        placeholder = L["GuildSearchPlaceholder"],
        tipTitle    = L["GuildSearchPlaceholder"],
        tipBody     = L["GuildSearchTip"],
        debounce    = 0.2,
        onChanged   = function(text)
            -- Shown back as typed on the next draw; matched lower-cased.
            f.rawText = text or ""
            f.text = strtrim(f.rawText):lower()
            if self._drawToken == token then self:Update() end
        end,
    })

    -- The crafting-skill range is two of the library's steppers, parked in
    -- toolbar slots like every other toolbar control, so they persist across
    -- draws: a guild sync landing while the player types a skill re-parks the
    -- same box rather than rebuilding it. The full range (1 to the skill cap)
    -- is "no limit"; a bound only filters once the player moves it off its end.
    local cap = self:SkillCap()
    local function skillStepper(key, label, field, default)
        return addon.GUI.ToolbarStepper(self, key, bar, {
            label    = label,
            width    = 130,
            min      = 1,
            max      = cap,
            value    = f[field] or default,
            tipTitle = label,
            tipBody  = string.format(L["GuildSkillTip"], cap),
            onChange = function(v)
                f[field] = (v ~= default) and v or nil
                if self._drawToken == token then self:Update() end
            end,
        })
    end
    skillStepper("minSkill", L["GuildMinSkill"], "minSkill", 1)
    local _, maxRec = skillStepper("maxSkill", L["GuildMaxSkill"], "maxSkill", cap)
    -- The cap is re-read every draw, and on Retail it grows as skills sync in.
    -- A Max left at "no limit" follows it, so the box never shows an old cap
    -- that a click on + would then turn into a real bound. Not while the
    -- player is typing in it: SetValue rewrites the box.
    local step = maxRec and maxRec.stepper
    if step and f.maxSkill == nil and step:GetValue() ~= cap
       and not (step.edit and step.edit:HasFocus()) then
        step:SetValue(cap)
    end
end

function GuildTab:FillContent(scroll)
    local data = self:Update()

    if #data == 0 and not self:IsFiltering() then
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
    local nameW, countW = self:ColumnWidths()
    addon.GUI.MakeColumnHeader({
        parent = hdr, width = nameW, label = L["GuildColProfession"],
        tooltipTitle = L["GuildColProfession"], tooltipDesc = L["GuildColProfessionDesc"],
    })
    addon.GUI.MakeColumnHeader({
        parent = hdr, width = countW, label = L["GuildColCount"], justify = "CENTER",
        tooltipTitle = L["GuildColCount"], tooltipDesc = L["GuildColCountDesc"],
    })
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
---   * While the filter strip is in use, the 0-count rows are left out: they
---     say "nobody matches here", which is noise when looking for someone.
function GuildTab:BuildTree(data)
    local filtering = self:IsFiltering()
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

    -- The search text matches every label on the page. A profession whose
    -- name matches keeps everything under it, a specialisation whose name
    -- matches keeps all its members, and otherwise only the characters whose
    -- name matches are kept -- with the counts recomputed from what is kept.
    local text = self._filter.text
    local function nameSubset(memberSet)
        if text == "" then return memberSet, countSet(memberSet) end
        local kept, n = {}, 0
        for ck in pairs(memberSet or {}) do
            if self:NameMatches(ck) then kept[ck] = true; n = n + 1 end
        end
        return kept, n
    end

    local tree = {}
    for _, prof in ipairs(data) do
        local profHit = text == "" or textHit(prof.name, text)
        local total = prof.total
        local node = { key = prof.profId, label = prof.name }
        if prof.total == 0 then
            node.color = DIM
        elseif #prof.specs > 0 then
            node.children = {}
            -- Recounted only when the search cut members out; otherwise the
            -- headcount from BuildCounts stands.
            local kept = 0
            for _, spec in ipairs(prof.specs) do
                local set, count = spec.memberSet or {}, spec.count
                if not (profHit or textHit(spec.name, text)) then
                    set, count = nameSubset(set)
                end
                local s = { key = spec.key, label = spec.name, valueText = tostring(count) }
                if count > 0 then
                    s.color, s.children = SPEC, members(set, prof.profId)
                else
                    s.color = DIMMER
                end
                if count > 0 or not filtering then
                    node.children[#node.children + 1] = s
                end
                kept = kept + count
            end
            if not profHit then total = kept end
        elseif prof.memberSet then
            local set = prof.memberSet
            if not profHit then set, total = nameSubset(set) end
            node.children = members(set, prof.profId)
        end
        node.valueText = tostring(total)
        if total > 0 or not filtering then
            tree[#tree + 1] = node
        end
    end
    return tree
end

--- Hand the tree to the list. The list is built ONCE per session and parked in
--- each draw's host group: its rows are pooled and its expand state survives a
--- redraw, so a guild-data refresh keeps what the player had open, and a toggle
--- re-lays the rows without rebuilding the tab.
--- A name search opens every branch, so the matching characters are on screen
--- without the player hunting through each profession for them; clearing the
--- search closes them again rather than leaving the whole tree open.
function GuildTab:SetTree(tree)
    if not self._list then return end
    self._tree = tree
    self._list:SetData(tree)
    -- Only on the transitions: a refresh or a level keystroke mid-search
    -- must not reopen a branch the player has just collapsed.
    local searching = self._filter.text ~= ""
    if searching and not self._expandedBySearch then
        self._list:SetAllExpanded(true)
    elseif not searching and self._expandedBySearch then
        self._list:SetAllExpanded(false)
    end
    self._expandedBySearch = searching
end

--- Does the loaded LibAceGUIWidgets predate MINOR 42, whose expandable list
--- follows its scroll box's width on its own?
function GuildTab:NeedsRelayoutHook()
    local minor = LibStub.minors and LibStub.minors["LibAceGUIWidgets-1.0"]
    return not (minor and minor >= 42)
end

--- The name and count header widths, at LibAceGUIWidgets' current scale --
--- the same rounding the list applies to its valueColumn.
function GuildTab:ColumnWidths()
    local W = addon.W
    if W and W.ScaledSize then
        return W:ScaledSize(NAME_W), W:ScaledSize(COUNT_W)
    end
    return NAME_W, COUNT_W
end

function GuildTab:Draw(container)
    self._container = container
    -- The list re-places its count column on a scale change by itself; the
    -- headers are ours and only move on a redraw. One listener, keyed on this
    -- table, redraws the window only while the Guild tab is the one showing.
    local W = addon.W
    if W and W.OnScaleChanged and not self._scaleHooked then
        self._scaleHooked = true
        W:OnScaleChanged(GuildTab, function()
            local mw = addon.MainWindow
            if mw and mw.activeTab == "guild" and mw.frame then mw:Refresh() end
        end)
    end
    container:SetLayout("Flow")

    -- Filter strip and column headers first, then the tree in a group that
    -- fills the rest of the tab.
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
            -- The counts form one column under the "Characters" header,
            -- centred, starting where the header's own column starts; the
            -- rest of the row is left free for later columns. valueColumn is
            -- LibAceGUIWidgets contract a79b0269; an older copy ignores it
            -- and keeps the counts at the row's right edge.
            local list = addon.W:CreateExpandableList(host.content, {
                indent      = 14,
                valueColumn = { offset = NAME_W, width = COUNT_W, justify = "CENTER" },
            })
            self._list = list
            -- Only for a LibAceGUIWidgets older than MINOR 42. Those size the
            -- rows from a read of the scroll box's width and re-lay only when
            -- the OUTER frame resizes. In game every row was laid out at the
            -- 40px minimum (names shrank to "..") while the scrollbar sat at
            -- full width, so the last layout read the scroll box before it had
            -- its width (inferred from that screenshot, not instrumented).
            -- MINOR 42 anchors the rows to the scroll box and re-lays on its
            -- resize itself (contract 0f350cea), so hooking it there too would
            -- only run every layout twice.
            if self:NeedsRelayoutHook() and list.box and list.box.scroll and list._relayout then
                list.box.scroll:HookScript("OnSizeChanged", function() list._relayout() end)
            end
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

    self:DrawFilterBar(top)
    self:FillContent(top)
    -- The tree's group was laid out while the top group was still empty, so it
    -- sat at the top of the tab with the headers drawn over its first rows.
    -- Lay the tab out again now the top group has its real height.
    container:DoLayout()
end

-- Kept for callers that redraw the tab after its data changed.
function GuildTab:Refresh()
    if not self._container then return end
    self._container:ReleaseChildren()
    self:Draw(self._container)
end
