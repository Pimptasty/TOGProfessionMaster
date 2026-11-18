-- GUI/MinimapButton.lua — the LDB launcher and its LibDBIcon registration.
--
-- Small file, three things worth pinning:
--
--   * the click routing, which is the only way most users open the addon;
--   * the tooltip, which is the only place those three bindings are written down;
--   * the db table handed to LibDBIcon, which was a real bug (v0.7.1). LibDBIcon
--     writes the new angle into that table when the user DRAGS the button, so
--     passing a throwaway local silently lost the position on every /reload.
--     It has to be the table that persists.
--
-- Runs against the REAL LibDataBroker-1.1 and LibDBIcon-1.0 from the standalone
-- LibDBIcon-1.0 addon in the sibling AddOns folder. Since v1.1.2 that addon is a
-- required dependency and TOGPM no longer embeds either library, so the sibling
-- copy is exactly what players run.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env  = require("env_togpm")
local libs = require("env.libs")

local ns, dataObj, opened

local function haveVendoredLibs()
	return libs.available("LibDBIcon-1.0")
end

setup(function()
	ns = env.initDb()
	-- The harness's own manifest entry (Adoption log 2026-09-25, d57d724) loads
	-- the standalone addon from AddOns/LibDBIcon-1.0 with its LibDataBroker, so
	-- no private registration is needed.
	if haveVendoredLibs() then
		libs.load("LibDBIcon-1.0")
		env.loadModule("GUI/MinimapButton.lua")
		dataObj = LibStub("LibDataBroker-1.1", true)
			and LibStub("LibDataBroker-1.1"):GetDataObjectByName("TOGProfessionMaster")
	end
end)

local saved

before_each(function()
	env.installFrames()
	if not dataObj then return end
	opened = {}
	-- Methods on the ADDON table: env.install() resets globals, not these, so a
	-- spec here would otherwise hand every later spec FILE a stubbed OpenBrowser.
	saved = { OpenBrowser = ns.OpenBrowser, OpenSettings = ns.OpenSettings,
	          OpenReagents = ns.OpenReagents, Print = ns.Print }
	ns.OpenBrowser  = function() opened.browser = true end
	ns.OpenSettings = function() opened.settings = true end
	ns.OpenReagents = function() opened.reagents = true end
	_G.IsShiftKeyDown = function() return false end
end)

after_each(function()
	for name, fn in pairs(saved or {}) do ns[name] = fn end
end)

describe("minimap launcher", function()
	it("registers an LDB launcher object", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		assert.equal("launcher", dataObj.type)
		assert.is_function(dataObj.OnClick)
		assert.is_function(dataObj.OnTooltipShow)
	end)

	it("opens the browser on a plain left-click", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		dataObj.OnClick(nil, "LeftButton")
		assert.is_true(opened.browser)
		assert.is_nil(opened.settings)
	end)

	it("opens settings on shift+left-click, not the browser", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		_G.IsShiftKeyDown = function() return true end
		dataObj.OnClick(nil, "LeftButton")
		assert.is_true(opened.settings)
		assert.is_nil(opened.browser)
	end)

	it("opens the shopping list on right-click", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		dataObj.OnClick(nil, "RightButton")
		assert.is_true(opened.reagents)
	end)

	it("ignores a button it has no binding for", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		dataObj.OnClick(nil, "MiddleButton")
		assert.same({}, opened)
	end)

	it("documents all three bindings in the tooltip", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		local lines = {}
		dataObj.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
		-- Title, blank, and one line per binding.
		assert.equal(5, #lines)
		assert.is_truthy(lines[1]:find("Ultimate Profession Master", 1, true))
		assert.is_falsy(lines[1]:find("TOG Profession Master", 1, true))   -- the old brand is gone after the rename
		-- The title draws in the brand colour, not the old TOG purple.
		assert.is_truthy(lines[1]:find("|c" .. (ns.BrandColor or "ffFF8000") .. "Ultimate Profession Master", 1, true))
		assert.is_falsy(lines[1]:lower():find("da8cff", 1, true))
	end)
end)

describe("LibDBIcon registration", function()
	-- SetupMinimapButton is a file-local, hooked onto Ace:OnEnable — so driving
	-- the real OnEnable is the only way in, and it is worth it: this is the
	-- v0.7.1 fix, and the failure it prevents (a dragged button snapping back on
	-- every /reload) is invisible until a user drags one.
	local function enable()
		-- LibDBIcon errors on a second Register of the same name, correctly — in
		-- game OnEnable runs once. A fresh copy per test is the honest way to run
		-- it repeatedly; SetupMinimapButton looks the library up through LibStub
		-- at call time, so it picks the new one up.
		libs.fresh("LibDBIcon-1.0")
		ns.lib:OnEnable()
	end

	it("hands LibDBIcon the table that PERSISTS, seeded from the legacy field", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap       = nil     -- fresh profile
		ns.lib.db.profile.minimapPos    = 137     -- the pre-v0.7.1 field
		ns.lib.db.profile.minimapButton = true

		enable()

		local md = ns.lib.db.profile.minimap
		-- On the AceDB profile, so LibDBIcon's drag writes survive a reload.
		assert.is_truthy(md)
		assert.equal(137, md.minimapPos)
		assert.is_false(md.hide)
	end)

	it("defaults the angle when there is no legacy position either", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap    = nil
		ns.lib.db.profile.minimapPos = nil
		enable()
		assert.equal(220, ns.lib.db.profile.minimap.minimapPos)
	end)

	it("does not overwrite a position the user has already dragged to", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap    = { minimapPos = 12 }
		ns.lib.db.profile.minimapPos = 137
		enable()
		assert.equal(12, ns.lib.db.profile.minimap.minimapPos)
	end)

	it("mirrors the visibility setting into LibDBIcon's hide flag", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap       = nil
		ns.lib.db.profile.minimapButton = false
		enable()
		assert.is_true(ns.lib.db.profile.minimap.hide)
	end)
end)

-- The icon crop is MEASURED from the art. The old window was tuned by eye for
-- the round minimap slot, where LibDBIcon's ring hides the coin's rim, and cut
-- the coin flat once Ultimate Tools' button bag drew it square with no ring
-- (TOGTools inbox thread a3f29d33, 2026-11-17). Same method as TOGTools'
-- Tests/icon_spec.lua.

-- Uncompressed (type 2) or RLE (type 10) true-colour TGA -> width, height,
-- pixel(x, y) giving r, g, b, a with (0, 0) the TOP-LEFT pixel.
local function readTGA(path)
	local fh = assert(io.open(path, "rb"), path .. " is missing")
	local data = fh:read("*a")
	fh:close()
	local idLen, imgType = data:byte(1), data:byte(3)
	local w = data:byte(13) + data:byte(14) * 256
	local h = data:byte(15) + data:byte(16) * 256
	local bpp, desc = data:byte(17), data:byte(18)
	assert(imgType == 2 or imgType == 10, "unsupported TGA image type " .. imgType)
	assert(bpp == 24 or bpp == 32, "unsupported TGA depth " .. bpp)
	local bytes = bpp / 8
	local pos = 19 + idLen
	local px = {}
	if imgType == 2 then
		for i = 0, w * h - 1 do
			px[i] = { data:byte(pos + i * bytes, pos + i * bytes + bytes - 1) }
		end
	else
		local i = 0
		while i < w * h do
			local head = data:byte(pos); pos = pos + 1
			local n = (head % 128) + 1
			if head >= 128 then
				local p = { data:byte(pos, pos + bytes - 1) }; pos = pos + bytes
				for _ = 1, n do px[i] = p; i = i + 1 end
			else
				for _ = 1, n do
					px[i] = { data:byte(pos, pos + bytes - 1) }; pos = pos + bytes; i = i + 1
				end
			end
		end
	end
	local topOrigin = math.floor(desc / 32) % 2 == 1
	return w, h, function(x, y)
		local row = topOrigin and y or (h - 1 - y)
		local p = px[row * w + x]
		return p[3], p[2], p[1], p[4] or 255
	end
end

-- The drawn part of the icon: every pixel that is neither transparent nor
-- near-white background.
local function contentBounds(w, h, pixel)
	local minX, minY, maxX, maxY = w, h, -1, -1
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local r, g, b, a = pixel(x, y)
			if a >= 128 and not (r > 235 and g > 235 and b > 235) then
				if x < minX then minX = x end
				if x > maxX then maxX = x end
				if y < minY then minY = y end
				if y > maxY then maxY = y end
			end
		end
	end
	return minX, minY, maxX, maxY
end

describe("the minimap icon crop", function()
	local w, h, pixel = readTGA("icons/UPM_MMB_Icon.tga")
	local minX, minY, maxX, maxY = contentBounds(w, h, pixel)
	local measured = string.format("art %dx%d, drawn pixels x %d..%d, y %d..%d", w, h, minX, maxX, minY, maxY)
	local function coords()
		assert.is_truthy(dataObj, "the LDB object did not register (is LibDBIcon-1.0 installed?)")
		return dataObj.iconCoords
	end
	local function crop(c)
		return measured .. string.format("; crop %.4f %.4f %.4f %.4f", c[1], c[2], c[3], c[4])
	end

	-- LibDBIcon and the square bag both draw the window into a square button,
	-- so a non-square window stretches the coin.
	it("is square", function()
		local c = coords()
		local aspect = ((c[2] - c[1]) * w) / ((c[4] - c[3]) * h)
		assert.is_true(math.abs(aspect - 1) < 0.001, crop(c) .. string.format("; aspect %.3f", aspect))
	end)

	it("keeps the coin inside the window, trimming at most a pixel and a half at an edge", function()
		local c, slack = coords(), 1.5 / w
		assert.is_true(c[1] <= minX / w + slack and c[2] >= (maxX + 1) / w - slack
			and c[3] <= minY / h + slack and c[4] >= (maxY + 1) / h - slack, crop(c))
	end)

	-- No wider than the coin needs, or it draws small in the round slot again
	-- (operator, 2026-10-21: "the rest of the icons aren't squished like mine").
	it("shows no more than three pixels of margin outside the coin on any side", function()
		local c, margin = coords(), 3 / w
		assert.is_true(minX / w - c[1] <= margin and c[2] - (maxX + 1) / w <= margin
			and minY / h - c[3] <= margin and c[4] - (maxY + 1) / h <= margin, crop(c))
	end)
end)

describe("ShowMinimapButton", function()
	it("turns the setting on so the button survives a reload", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.Print = function() end
		ns.lib.db.profile.minimapButton = false
		ns:ShowMinimapButton()
		assert.is_true(ns.lib.db.profile.minimapButton)
	end)
end)
