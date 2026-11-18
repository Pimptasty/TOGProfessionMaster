-- Tests/tga_bounds.lua -- print each minimap icon's size and the bounds of its
-- drawn pixels (alpha >= 128), so iconCoords can be fitted to the art. Not a
-- spec (busted only runs *_spec.lua); run it with the desk's run_check.
-- With no arguments it compares UPM's icon with the sibling Ultimate addons'
-- icons that share its template -- the comparison Ultimate Tools' square
-- button bag needs. Same reader as Tests/minimap_spec.lua; uncompressed or RLE
-- true-colour only. Paths are relative to the TOGProfessionMaster folder.
local DEFAULTS = {
    "icons/UPM_MMB_Icon.tga",
    "../Ultimate Guild Roster/Textures/UGR_MMB_Icon.tga",
    "../TrackOMatic/textures/UTr_MMB_Icon.tga",
    "../fastguildinvite/img/minimap/UGI_MMB_Icon.tga",
    "../TOGTools/textures/UT_MMB_Icon.tga",
}

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
            local head = data:byte(pos)
            pos = pos + 1
            local n = (head % 128) + 1
            if head >= 128 then
                local p = { data:byte(pos, pos + bytes - 1) }
                pos = pos + bytes
                for _ = 1, n do px[i] = p; i = i + 1 end
            else
                for _ = 1, n do
                    px[i] = { data:byte(pos, pos + bytes - 1) }
                    pos = pos + bytes
                    i = i + 1
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

local files = (arg and #arg > 0) and arg or DEFAULTS
for _, path in ipairs(files) do
    local w, h, pixel = readTGA(path)
    local minX, minY, maxX, maxY = w, h, -1, -1
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local _, _, _, a = pixel(x, y)
            if a >= 128 then
                if x < minX then minX = x end
                if x > maxX then maxX = x end
                if y < minY then minY = y end
                if y > maxY then maxY = y end
            end
        end
    end
    print(string.format("%s: %dx%d, drawn x %d..%d (%d px), y %d..%d (%d px)",
        path, w, h, minX, maxX, maxX - minX + 1, minY, maxY, maxY - minY + 1))
end
