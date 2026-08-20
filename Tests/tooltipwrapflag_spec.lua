-- Every line this addon appends to a tooltip opts into the engine's wrap preset.
--
-- THIS IS THE ONLY TOOLTIP-WIDTH ASSERTION WORTH HAVING, and it is not about
-- pixels. Rounds 5-10 of `docs/AUDIT.md` cost an evening to establish why:
--
--   * WoW gives a tooltip a MINIMUM width and no maximum. The frame sizes to its
--     widest NON-WRAPPING line, so one long unwrapped line from any addon drags
--     the whole tooltip -- and everyone else's content -- out with it.
--   * There is an engine-side PRESET wrap width, and a line opts into it by
--     passing `wrap` as the LAST argument to `AddLine` / `SetText`. The Warcraft
--     Wiki on SetText: "the tooltip width is set to a preset value, which is
--     about the width of the ability tooltips on spells."
--   * `Default = false` is the trap: omit it and the line ignores the preset.
--
-- CITATION, corrected (audit round 10). `FrameAPITooltipDocumentation.lua:72`
-- carries `{ Name = "wrap", Type = "bool", Default = false }`, but that line is
-- inside the **SetText** entry -- `AddLine` is not in that file at all, and
-- Classic Era's generated docs describe only five tooltip methods. `AddLine`'s
-- fifth-argument wrap is evidenced by Blizzard's own call sites in
-- `wow-ui-source-classic_era` and by the Warcraft Wiki, not by that line.
--
-- WHAT THIS CANNOT DO: assert a width. The harness pins its text metrics as
-- deliberately unfaithful and no offline model can know an engine-side preset.
-- It asserts the PROPERTY that makes the width correct.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path

--- Source with comments stripped, so prose about the flag is not read as code.
local function code(path)
	local f = assert(io.open(path, "r"), "missing source file: " .. path)
	local body = f:read("*a")
	f:close()
	body = body:gsub("%-%-%[%[.-%]%]", " ")
	body = body:gsub("%-%-[^\n]*", " ")
	return body
end

-- Every file that appends to a tooltip, with a PER-FILE floor for how many calls
-- the matcher must still find. Audit finding 19: a single `total >= 10` against a
-- real count of 98 let the matcher silently lose 90% of the calls and stay green.
-- Per-file floors mean one file dropping out of the sweep is caught rather than
-- absorbed by the other ten -- BrowserTab alone is ~28 calls, so its whole file
-- could vanish under a global floor without tripping it.
--
-- Floors are set below the measured count so ordinary editing does not trip them.
local SOURCES = {
	{ path = "Tooltip.lua",                 min = 2 },
	{ path = "GUI/SharedWidgets.lua",       min = 8 },
	{ path = "GUI/BrowserTab.lua",          min = 22 },
	{ path = "GUI/CooldownsTab.lua",        min = 14 },
	{ path = "GUI/MissingRecipesTab.lua",   min = 5 },
	{ path = "GUI/CraftingTab.lua",         min = 8 },
	{ path = "GUI/AHProfitTab.lua",         min = 6 },
	{ path = "GUI/ShoppingListTab.lua",     min = 0 },
	{ path = "GUI/ReagentTracker.lua",      min = 2 },
	{ path = "GUI/MainWindow.lua",          min = 3 },
	{ path = "GUI/MinimapButton.lua",       min = 4 },
	{ path = "Modules/AHScanner.lua",       min = 3 },
}

--- Every `.lua` the addon SHIPS, taken from the TOCs rather than from disk.
---
--- Audit finding 20: `SOURCES` was a hand-written list with nothing asserting it
--- was complete, and `GUI/MinimapButton.lua` had sat outside the sweep since the
--- sweep was written -- four of its five lines did not wrap. `#SOURCES == 11`
--- pinned the list's LENGTH, which is the opposite guard: it fails when someone
--- adds a file to the sweep and passes forever while one is missing from it.
---
--- The TOC is the right corpus and a disk walk is not. A disk walk needs a shell,
--- catches files that ship to nobody, and would have to exclude `Tests/` and
--- `libs/` by hand. What ships is exactly what the TOCs load, and a production
--- file missing from every TOC is already a failure in `loadorder_spec`.
local TOCS = {
	"TOGProfessionMaster.toc",
	"TOGProfessionMaster_TBC.toc",
	"TOGProfessionMaster_Wrath.toc",
	"TOGProfessionMaster_Cata.toc",
	"TOGProfessionMaster_Mists.toc",
}

--- Union of the `.lua` files every TOC loads, repo-relative with forward slashes.
--- Libraries are excluded: `libs/` is vendored third-party code whose tooltip
--- calls are not ours to change, and LibDBIcon in particular has its own.
local function shippedLuaFiles()
	local seen, out = {}, {}
	for _, toc in ipairs(TOCS) do
		local f = assert(io.open(toc, "r"), "missing TOC: " .. toc)
		local body = f:read("*a")
		f:close()
		for line in body:gmatch("[^\r\n]+") do
			line = line:match("^%s*(.-)%s*$")
			if line ~= "" and not line:match("^#") and line:lower():match("%.lua$") then
				local rel = line:gsub("\\", "/")
				if not rel:lower():match("^libs/") and not seen[rel] then
					seen[rel] = true
					out[#out + 1] = rel
				end
			end
		end
	end
	table.sort(out)
	-- A TOC read that found nothing would make the completeness check pass
	-- vacuously, which is the same class of bug the check exists to catch.
	assert(#out > 20, "read only " .. #out .. " shipped .lua files from the TOCs")
	return out
end

--- Receivers that are a tooltip. `SetText` is NOT tooltip-specific -- buttons,
--- labels, editboxes and fontstrings all have one, and an unfiltered sweep
--- reported forty of those as offenders. `AddLine` and `AddDoubleLine` need no
--- filter: nothing else in this addon's surface has either.
local TOOLTIP_RECEIVER = {
	GameTooltip = true, tooltip = true, tip = true,
	ItemRefTooltip = true,
	ShoppingTooltip1 = true, ShoppingTooltip2 = true, ShoppingTooltip3 = true,
}

--- Number of TOP-LEVEL arguments in a `%b()` capture.
---
--- Audit finding 17. The previous check was `args:find("true%s*%)$")` -- "does
--- this end with `true)`" -- which is a SPELLING, not an argument position. It
--- passes `AddLine(text, true)`, where `true` lands in the `r` colour slot and
--- the line does not wrap at all. That is the exact mistake the forty-site sweep
--- invited: appending the flag without supplying the colour arguments it sits
--- behind. Counting arity distinguishes the two; matching the tail cannot.
---
--- Commas inside nested parens, braces, brackets and string literals do not
--- count, or `string.format("a,b", x)` would read as two arguments.
local function argCount(args)
	if args:match("^%(%s*%)$") then return 0 end
	local depth, count, i = 0, 1, 1
	local inStr, quote = false, nil
	while i <= #args do
		local c = args:sub(i, i)
		if inStr then
			if c == "\\" then i = i + 1
			elseif c == quote then inStr = false end
		elseif c == '"' or c == "'" then
			inStr, quote = true, c
		elseif c == "(" or c == "{" or c == "[" then depth = depth + 1
		elseif c == ")" or c == "}" or c == "]" then depth = depth - 1
		elseif c == "," and depth == 1 then count = count + 1
		end
		i = i + 1
	end
	return count
end

--- EXACT arity for the wrap flag to land in the wrap slot.
---   AddLine(text, r, g, b, wrap)              -> 5
---   SetText(text, r, g, b, alpha, wrap)       -> 6
---
--- Audit finding 21: this was `>=`, which bounds the arity only from below. The
--- wrap parameter's position is FIXED and it is the last one either method has,
--- so a sixth argument to `AddLine` pushes `true` past the wrap slot and the line
--- does not wrap -- while still ending in `true)` and still clearing a `>= 5`
--- test. Too many arguments is as wrong as too few; both are checked.
local WRAP_ARITY = { AddLine = 5, SetText = 6 }

--- `AddDoubleLine` HAS NO WRAP PARAMETER. Audit finding 18.
---
--- Its signature is `(leftText, rightText [, lR,lG,lB [, rR,rG,rB]])` -- eight
--- arguments, all colour. Verified against the Warcraft Wiki and ~25 call sites
--- in `wow-ui-source-classic_era`, none of which passes a boolean. NOT verified
--- by absence from `*Documentation.lua`: `AddLine` is absent from those too and
--- certainly exists, so absence proves nothing here.
---
--- So these three lines are STRUCTURALLY unable to opt in. They are enumerated
--- rather than skipped, because the spec's own title claims every appended line
--- wraps, and an exception living in the gap between a matcher and its title is
--- the least visible place to keep one. A FOURTH `AddDoubleLine` fails this spec
--- until someone adds it here with a reason.
local DOUBLELINE_EXEMPT = {
	-- Scraped from a real item tooltip; both halves come from the game's own
	-- fontstrings. Takes this branch whenever right-hand text exists, NOT when
	-- the line is short — audit finding 18 flags the comment beside it as false.
	["GUI/BrowserTab.lua"]    = 1,
	-- TOGBankClassic banker rows (name + count) and price-provider rows
	-- (`row.label` + value). The label comes from TSM / Auctionator via ItemDB,
	-- so it is the one string here not bounded by inspection.
	["GUI/SharedWidgets.lua"] = 2,
}

--- The ONE line that must NOT wrap, per file, and why.
---
--- Wrapping a line is how it opts into the engine's preset -- but the preset is
--- the width long lines wrap TO, not the width every tooltip ends up at. A
--- tooltip in which *every* line wraps has nothing claiming a natural width, so
--- the frame collapses to the bare preset and comes out NARROWER than the
--- game's own tooltip for the same item. That shipped and was seen in game:
--- "Schematic: Advanced Target Dummy" broke onto two lines, which Blizzard's
--- item tooltip never does with an item name.
---
--- So exactly one line per hand-built tooltip is left unwrapped -- the title,
--- matching where the game puts its own -- and it sizes the frame. A SECOND
--- unwrapped line in any of these files fails the sweep, because that is a line
--- of unbounded content setting the width again, which is the original defect.
local TITLE_EXEMPT = {
	-- `GameTooltip:AddLine("|cffffff00" .. (header or entry.name) .. "|r")` --
	-- the recipe-scroll title in the row tooltip.
	["GUI/BrowserTab.lua"] = 1,
}

--- Every tooltip call in a file, flattened so a call split across source lines is
--- examined whole.
local function tooltipCalls(body)
	local out = {}
	local flat = body:gsub("%s+", " ")
	for _, method in ipairs({ "AddLine", "AddDoubleLine", "SetText" }) do
		local pat = "([%w_]+)[:%.]" .. method .. "%s*(%b())"
		for recv, args in flat:gmatch(pat) do
			-- Audit finding 22: the comment that stood here described a
			-- name-collision defence -- "match the longer name first, skip a
			-- receiver that is really a suffix" -- which this loop does not
			-- implement and does not need. `AddLine` is not a substring of
			-- `AddDoubleLine`, so the two patterns cannot cross-match whatever
			-- order they run in. A documented guard that does not exist is worse
			-- than none: the next reader trusts it and stops checking.
			--
			-- The one filter that IS real: `SetText` is not tooltip-specific, so
			-- it is kept only for a known tooltip receiver. `AddLine` and
			-- `AddDoubleLine` need no filter -- nothing else in this addon's
			-- surface has either.
			if method ~= "SetText" or TOOLTIP_RECEIVER[recv] then
				out[#out + 1] = { method = method, recv = recv, args = args }
			end
		end
	end
	return out
end

--- A blank spacer adds nothing that can be long.
local function isBlankSpacer(args)
	return args:match('^%(%s*"%s*"%s*%)$') ~= nil
		or args:match('^%(%s*" "%s*%)$') ~= nil
end

describe("every tooltip line this addon appends opts into the wrap preset", function()
	it("enumerates the sources", function()
		assert.equal(12, #SOURCES)
		for _, src in ipairs(SOURCES) do
			assert.is_truthy(#code(src.path) > 0, "empty source: " .. src.path)
		end
	end)

	it("sweeps EVERY shipped file that touches a tooltip, not a hand-kept list", function()
		-- Finding 20. `#SOURCES == 12` above pins the list's length; it cannot
		-- notice a file that appends tooltip lines and was never added. This
		-- walks what the TOCs actually ship and fails on any file carrying a
		-- tooltip call that SOURCES does not name.
		local listed = {}
		for _, src in ipairs(SOURCES) do listed[src.path] = true end

		local missing = {}
		for _, path in ipairs(shippedLuaFiles()) do
			if not listed[path] then
				local n = #tooltipCalls(code(path))
				if n > 0 then
					missing[#missing + 1] = ("%s has %d tooltip call(s)"):format(path, n)
				end
			end
		end
		table.sort(missing)
		assert.equal("", table.concat(missing, " | "),
			"these shipped files append tooltip lines and are outside the sweep — "
			.. "add each to SOURCES with a floor, then fix whatever it reports")
	end)

	it("still finds the calls, PER FILE", function()
		-- Guards the guard. Finding 19: a single global floor of 10 against a real
		-- 98 could lose 90% of the sweep silently.
		local short = {}
		for _, src in ipairs(SOURCES) do
			local n = #tooltipCalls(code(src.path))
			if n < src.min then
				short[#short + 1] = ("%s found %d, floor %d"):format(src.path, n, src.min)
			end
		end
		assert.equal("", table.concat(short, " | "),
			"the matcher lost calls in these files — it broke, the addon did not")
	end)

	it("passes the wrap flag, in the wrap POSITION, on every line that can", function()
		local offenders, unwrapped = {}, {}
		for _, src in ipairs(SOURCES) do
			for _, call in ipairs(tooltipCalls(code(src.path))) do
				if call.method ~= "AddDoubleLine" and not isBlankSpacer(call.args) then
					local need = WRAP_ARITY[call.method]
					-- Round 15 asked for a deliberate decision here and two
					-- earlier rounds passed over it. DECISION: both spellings
					-- count as wrapping. The client takes any truthy value, and
					-- Blizzard's own Blizzard_AchievementUI_Shared.lua:238 is
					-- `AddLine(self.text, nil, nil, nil, 1)` -- so `1` is the
					-- spelling someone copies in, and accepting only `true`
					-- would report a genuinely-wrapping line as an offender.
					-- Loud rather than silent, but still wrong. The arity check
					-- below is what guards the POSITION (finding 17); the tail
					-- match only identifies the flag. This addon writes `true`
					-- everywhere today and nothing here pushes anyone off that.
					local tail = call.args:find("true%s*%)$") ~= nil
					             or call.args:find("[^%w_]1%s*%)$") ~= nil
					local ok = tail and argCount(call.args) == need
					if not ok then
						local shown = call.args
						if #shown > 80 then shown = shown:sub(1, 80) .. "…" end
						local entry = ("%s %s%s (arity %d, needs %d)"):format(
							src.path, call.method, shown, argCount(call.args), need)
						-- The title is allowed to be unwrapped, and counted so a
						-- SECOND one in the same file still fails. See TITLE_EXEMPT.
						unwrapped[src.path] = (unwrapped[src.path] or 0) + 1
						if unwrapped[src.path] > (TITLE_EXEMPT[src.path] or 0) then
							offenders[#offenders + 1] = entry
						end
					end
				end
			end
		end
		table.sort(offenders)
		assert.equal("", table.concat(offenders, "\n"),
			"these lines do not wrap — either no flag, or the flag is not in the "
			.. "wrap slot because the colour arguments before it are missing")

		-- The exemption is a BUDGET, not a licence: a file that stops having its
		-- unwrapped title has lost the line that sizes its frame, and would
		-- collapse to the bare preset again. Assert the budget is actually spent.
		local stale = {}
		for path, allowed in pairs(TITLE_EXEMPT) do
			if (unwrapped[path] or 0) ~= allowed then
				stale[#stale + 1] = ("%s has %d unwrapped, TITLE_EXEMPT says %d")
					:format(path, unwrapped[path] or 0, allowed)
			end
		end
		table.sort(stale)
		assert.equal("", table.concat(stale, " | "),
			"TITLE_EXEMPT no longer matches the source — either the title started "
			.. "wrapping (the frame collapses to the preset) or a second line stopped")
	end)

	it("has exactly the enumerated AddDoubleLine exceptions, and no more", function()
		-- Finding 18: AddDoubleLine cannot wrap, so its call sites are named here
		-- rather than silently skipped. A new one fails until it is justified.
		local counts = {}
		for _, src in ipairs(SOURCES) do
			for _, call in ipairs(tooltipCalls(code(src.path))) do
				if call.method == "AddDoubleLine" then
					counts[src.path] = (counts[src.path] or 0) + 1
				end
			end
		end
		-- Audit finding 23: walk the UNION of the two tables, not just `counts`.
		-- `counts` only gains a key for a file where an AddDoubleLine was FOUND,
		-- so iterating it alone checks the exemption list for growth and never
		-- for shrinkage: delete the last AddDoubleLine from an exempt file and
		-- its entry is never visited again, sitting there permanently claiming
		-- cover for a call site that no longer exists. A fourth site failed as
		-- designed; a deleted third did not. This is live rather than
		-- hypothetical -- finding 18's own remedy proposes converting
		-- SharedWidgets.lua's AddDoubleLine to a wrapped AddLine, which would
		-- turn `= 2` into a lie nothing reports.
		local paths = {}
		for path in pairs(counts) do paths[path] = true end
		for path in pairs(DOUBLELINE_EXEMPT) do paths[path] = true end

		local unexpected = {}
		for path in pairs(paths) do
			local n       = counts[path] or 0
			local allowed = DOUBLELINE_EXEMPT[path] or 0
			if n ~= allowed then
				unexpected[#unexpected + 1] = ("%s has %d AddDoubleLine, expected %d")
					:format(path, n, allowed)
			end
		end
		table.sort(unexpected)
		assert.equal("", table.concat(unexpected, " | "),
			"AddDoubleLine has no wrap parameter -- a new one is a line that cannot "
			.. "opt into the preset, and needs a reason recorded in DOUBLELINE_EXEMPT; "
			.. "an entry whose count has DROPPED is a stale exemption and must be "
			.. "removed or lowered")
	end)
end)
