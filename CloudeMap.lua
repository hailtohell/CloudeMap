local ADDON, ns = ...

local floor, ceil, min, max, abs, log = math.floor, math.ceil, math.min, math.max, math.abs, math.log
local tinsert, tremove, sort = table.insert, table.remove, table.sort

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local CW, CH = 4096, 2731              -- world canvas, in canvas units
local MAX_MAP, MAX_SAT = 24, 14        -- zoom limit in map mode / satellite mode
local TILE_YARDS = 533.33333333        -- one ADT / minimap tile
local DEF_W, DEF_H = 520, 340          -- default window size (small)
local MIN_W, MIN_H = 300, 200
local BAR_H, PAD = 16, 4
local MARK = 32                        -- player arrow size in pixels (Carbonite's default)
local ARROW = "Interface\\Minimap\\MinimapArrow"     -- the stock minimap arrow, same as Carbonite

-- Draw sub-levels (higher draws on top). Everything shares one canvas.
local SUB_WORLD, SUB_CONT, SUB_ZONE, SUB_FOG, SUB_OVER, SUB_MINI, SUB_CITY = -3, -2, -1, 0, 1, 2, 3

-- Zone parchment fades in when the zone is this wide on screen (pixels); a
-- city's own map comes in sooner, since a city is small next to its zone.
local ZONE_PX0, ZONE_PX1 = 110, 220
local CITY_PX0, CITY_PX1 = 70, 140

-- Maps whose own map art is a complete picture (cities). A city's map is shown
-- on top of the zone parchment whenever you are inside the city (see
-- UpdateFocus); every other zone is drawn by focus.
-- WoW Forever numbers its maps the Classic way (Stormwind City 1453, Elwynn
-- Forest 1429) and has the six vanilla capitals only: no Blood Elves, no
-- Draenei, so no Silvermoon, Exodar or Shattrath. Its new city, Dalaran, is a
-- dungeon map (City of Dalaran), not a zone map, so it is not in this list.
local CITY = {}
for _, id in ipairs({
    1453, 1454, 1455, 1456, 1457, 1458,          -- Stormwind, Orgrimmar, Ironforge, Thunder Bluff, Darnassus, Undercity
    }) do CITY[id] = true end

-- The zone whose land lies under each city (WoW Forever ids). It stays drawn
-- under the city's map while you are inside the city.
local CITY_HOST = {
    [1453] = 1429,   -- Stormwind City in Elwynn Forest
    [1454] = 1411,   -- Orgrimmar in Durotar
    [1455] = 1426,   -- Ironforge in Dun Morogh
    [1456] = 1412,   -- Thunder Bluff in Mulgore
    [1457] = 1438,   -- Darnassus in Teldrassil
    [1458] = 1420,   -- Undercity in Tirisfal Glades
}


---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local db
local nodes, byMap, conts = {}, {}, {}
local zoneList, labelNodes = {}, {}      -- zones that have art / zones that get a name label
ns.zoneList = zoneList                  -- (Bridge.lua: the zones round the ones on screen)
local cityList = {}                      -- cities with art (always drawn on top, see Build)
local lists = { base = {}, zone = { mode = "map" }, over = { mode = "map" }, mini = { mode = "sat" } }
local built, uiReady = false, false
local scale, ox, oy, minScale = 0.15, 0, 0, 0.15
local dirty = true
-- (zone picking caches; and the redraw state: pan = only moved since the last redraw, cull =
-- the canvas rect last drawn for, a margin round the view, layer = the frame pins ride on)
local tcache = { f = {}, h = {}, p = {} }
local frame, view, canvas, top, info, player, grip, followBtn, zoomText
local pinsFrame, playerFrame, pinMenu, pinsBtn
local pinBtns = {}
local pinsShown, dragMoved = 0, false
local VW, VH = DEF_W - 2 * PAD, DEF_H - BAR_H - 2 * PAD
local drag
local bx1, by1, bx2, by2 = 0, 0, CW, CH     -- pan limits (the land plus a margin)
local texPool, featPool, labelPool = {}, {}, {}
local texCreated = 0
local needOverlays = true
local focus                                  -- zone node that is currently drawn in detail
local cityFocus                              -- city node whose own map is showing (or about to)
local plX, plY, plNode                       -- player position on the canvas (nil while unknown), and the map node the game puts the player on
local unitMode                               -- which UnitPosition axis order fits (learned)
local lastPX, lastPY
local following = true                       -- keep the view on the player (on at every login)
local nExplored, nUnexplored, nRevealZones = 0, 0, 0   -- overlay pieces drawn, for /cmap debug
local nBase, nNoBase = 0, 0                     -- zones whose base art is optional / always drawn

local function Say(msg)
    print("|cff66ccffCloudeMap:|r " .. tostring(msg))
    if ns.capture then ns.capture[#ns.capture + 1] = tostring(msg) end      -- /cmap debug: also into the copy window
end
ns.Say = Say
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function SafeNum(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function F4(v) v = SafeNum(v); return v and ("%.4f"):format(v) or "-" end

local DEFAULTS = { shown = true, w = DEF_W, h = DEF_H, mode = "map" }
local FOG = 0.5                         -- brightness of unexplored areas
local function InitDB()
    -- settings from the time it was called StitchMap: kept when the old saved file is renamed
    -- (WTF\Account\<account>\SavedVariables\StitchMap.lua to CloudeMap.lua)
    if CloudeMapDB == nil and type(StitchMapDB) == "table" then CloudeMapDB = StitchMapDB end
    StitchMapDB = nil
    CloudeMapDB = CloudeMapDB or {}
    db = CloudeMapDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    -- settings of removed features (layers, fog brightness, base parchment, dot marker, quest
    -- area border width): dropped
    db.off, db.fog, db.base, db.dot, db.blobBorder = nil, nil, nil, nil, nil
    if ns.pins then ns.pins.Init(db) end
    if db.mode ~= "map" and db.mode ~= "sat" then db.mode = "map" end
    if db.blobMode ~= "tracked" then db.blobMode = "dim" end
    if db.cap60 then db.cap = 60 end                 -- (the old 60 Hz switch)
    db.cap60 = nil
    if db.cap ~= 60 and db.cap ~= 30 then db.cap = nil end       -- (the colour mode is gone)
end

local function MaxScale() return db.mode == "sat" and MAX_SAT or MAX_MAP end

local function Run(fn)
    local ok, err = xpcall(fn, function(e)
        return tostring(e) .. "\n" .. ((debugstack and debugstack(2, 8, 0)) or "")
    end)
    if not ok then Say("error: " .. err) end
end

---------------------------------------------------------------------------
-- Texture pools. Feathered pieces carry a gradient, so they use their own
-- pool and never mix with plain textures.
---------------------------------------------------------------------------
local function AcquireTex(sub, feather)
    local pool = feather and featPool or texPool
    local t = tremove(pool)
    if not t then
        t = canvas:CreateTexture(nil, "ARTWORK")
        t.feather = feather and true or false
        texCreated = texCreated + 1
    end
    t:SetDrawLayer("ARTWORK", sub)
    t:Show()
    return t
end

local function ReleaseTex(t)
    t:Hide()
    t:ClearAllPoints()
    tinsert(t.feather and featPool or texPool, t)
end

local function AcquireLabel()
    local f = tremove(labelPool) or top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:Show()
    return f
end
local function ReleaseLabel(f) f:Hide(); f:ClearAllPoints(); tinsert(labelPool, f) end

---------------------------------------------------------------------------
-- Sprites: plain descriptions of "this texture goes in this canvas rect".
-- Update() gives textures only to the ones that are visible.
--   o.sub            draw sub-level
--   o.minS / o.maxS  zoom range where the sprite exists
--   o.fi0 / o.fi1    fade in between these zoom values
--   o.fo0 / o.fo1    fade out between these zoom values
--   o.rel            zoom values are relative to the fully zoomed-out view
--   o.owner          zone node whose focus fade (alpha * zoomA) scales the sprite
--   o.layer          which layer it belongs to (world, cont, zone, fog, over, mini, city)
--   o.shade          dim with the unexplored-area brightness (FOG)
--   o.mode           only in this map mode ("map" parchment or "sat" satellite); nil = both
---------------------------------------------------------------------------
local function NewSprite(list, id, x, y, w, h, u1, u2, v1, v2, o, grad)
    local s = { tex = id, x = x, y = y, w = w, h = h, u1 = u1, u2 = u2, v1 = v1, v2 = v2,
                sub = o.sub, minS = o.minS or 0, maxS = o.maxS, fi0 = o.fi0, fi1 = o.fi1,
                fo0 = o.fo0, fo1 = o.fo1, rel = o.rel, owner = o.owner, layer = o.layer or "base",
                shade = o.shade, mode = o.mode, grad = grad }
    list[#list + 1] = s
    return s
end

local function ShowSprite(s)
    local t = AcquireTex(s.sub, s.grad)
    t:SetTexture(s.tex)
    t:SetTexCoord(s.u1, s.u2, s.v1, s.v2)
    t:SetSize(s.w, s.h)
    t:SetPoint("TOPLEFT", canvas, "TOPLEFT", s.x, -s.y)
    if s.grad then
        local g = s.grad
        pcall(t.SetGradient, t, g[1], CreateColor(1, 1, 1, g[2]), CreateColor(1, 1, 1, g[3]))
    else
        t:SetVertexColor(1, 1, 1, 1)      -- pooled textures may still be dimmed from an earlier sprite
    end
    s.tx = t
    s.a, s.sv = nil, nil      -- force alpha and shade to be applied
end

local function HideSprite(s)
    if s.tx then ReleaseTex(s.tx); s.tx = nil end
    s.warm = nil
end

local function ClearList(list)
    for i = #list, 1, -1 do
        HideSprite(list[i])
        list[i] = nil
    end
    list.live = 0
end

local function UpdateList(list, vx1, vy1, vx2, vy2, off)
    -- a list of the other mode (satellite tiles in map mode, parchment in satellite) costs nothing
    -- once its textures are given back
    if list.mode and list.mode ~= db.mode and (list.live or 0) == 0 then return end
    local rs = scale / minScale
    local live = 0
    for i = 1, #list do
        local s = list[i]
        local a = 0
        local here      -- in the drawn area, at a zoom where the sprite exists
        if not off and (not s.mode or s.mode == db.mode) then
            local sc = s.rel and rs or scale
            if sc >= s.minS and (not s.maxS or sc <= s.maxS)
               and s.x < vx2 and s.x + s.w > vx1 and s.y < vy2 and s.y + s.h > vy1 then
                here = true
                a = 1
                local o = s.owner
                if o then a = o.alpha * o.zoomA end
                if a > 0 and s.fi0 then a = a * clamp((sc - s.fi0) / (s.fi1 - s.fi0), 0, 1) end
                if a > 0 and s.fo0 then a = a * clamp((s.fo1 - sc) / (s.fo1 - s.fo0), 0, 1) end
            end
        end
        if a >= 0.01 then
            if not s.tx then ShowSprite(s) end
            if s.warm then s.tx:Show(); s.warm = nil end
            live = live + 1
            if s.a ~= a then s.tx:SetAlpha(a); s.a = a end
            if s.shade and s.sv ~= FOG then
                local b = FOG
                s.tx:SetVertexColor(b, b, b, 1)
                s.sv = b
            end
        elseif here and s.owner and s.owner.warm and s.owner.zoomA > 0 then
            -- the art of a zone round the pointer or the hero, not uncovered: its texture is kept,
            -- hidden, so the picture is loaded already when the zone is uncovered (else it pops in
            -- a few times as the game loads it, while the zone fades in). (UpdateFocus: n.warm)
            if not s.tx then ShowSprite(s) end
            if not s.warm then s.tx:Hide(); s.warm = true end
            live = live + 1
        elseif s.tx then
            HideSprite(s)
        end
    end
    list.live = live
end

---------------------------------------------------------------------------
-- Map art API (12.0.5+ wraps both calls one table deeper; accept both shapes)
---------------------------------------------------------------------------
local function GetLayers(id)
    local ok, L = pcall(C_Map.GetMapArtLayers, id)
    if not ok or type(L) ~= "table" then return nil end
    if L[1] and L[1].layerWidth == nil and type(L[1][1]) == "table" then L = L[1] end
    return L
end

local function GetTextures(id, layer)
    local ok, T = pcall(C_Map.GetMapArtLayerTextures, id, layer)
    if not ok or type(T) ~= "table" then return nil end
    if type(T[1]) == "table" then T = T[1] end
    return T
end

ns.GetLayers, ns.GetTextures = GetLayers, GetTextures      -- (Bridge.lua: the battleground map)

local function ValidDim(v)
    if issecretvalue and issecretvalue(v) then return false end
    return type(v) == "number" and v > 0 and v < math.huge
end

---------------------------------------------------------------------------
-- Node tree: world map -> continents -> zones
---------------------------------------------------------------------------
local function AddNode(mapID, x, y, w, h, level, parent)
    local mi = C_Map.GetMapInfo(mapID)
    local n = { mapID = mapID, name = mi and mi.name or tostring(mapID), level = level,
                x = x, y = y, w = w, h = h, parent = parent, zones = {},
                alpha = 0, zoomA = 0 }       -- focus fade (zones only)
    local layers = GetLayers(mapID)
    local L = layers and layers[1]
    if L and ValidDim(L.layerWidth) and ValidDim(L.layerHeight)
         and ValidDim(L.tileWidth) and ValidDim(L.tileHeight) then
        local files = GetTextures(mapID, 1)
        if files and files[1] then
            n.files = files
            n.layerW, n.layerH, n.tileW, n.tileH = L.layerWidth, L.layerHeight, L.tileWidth, L.tileHeight
            n.cols, n.rows = ceil(L.layerWidth / L.tileWidth), ceil(L.layerHeight / L.tileHeight)
            n.kx, n.ky = w / n.layerW, h / n.layerH     -- canvas units per art pixel
        end
    end
    nodes[#nodes + 1] = n
    byMap[mapID] = n
    return n
end

local function AddChild(mapID, parent, level)
    local l, r, t, b = C_Map.GetMapRectOnMap(mapID, parent.mapID)
    if not l or r <= l or b <= t then return end
    return AddNode(mapID, parent.x + l * parent.w, parent.y + t * parent.h,
                   (r - l) * parent.w, (b - t) * parent.h, level, parent)
end

---------------------------------------------------------------------------
-- Art tiles -> sprites. A crop rect limits the art, and the crop edge is
-- feathered with alpha gradients so no rectangle shows.
---------------------------------------------------------------------------
local function EmitPiece(list, id, x1, y1, x2, y2, fc, fr, o)
    local cr, F = o.crop, o.F
    local ax1, ay1, ax2, ay2 = x1, y1, x2, y2
    if cr then
        ax1, ay1 = max(x1, cr[1]), max(y1, cr[2])
        ax2, ay2 = min(x2, cr[3]), min(y2, cr[4])
        if ax1 >= ax2 or ay1 >= ay2 then return end
    end
    local feather = cr and F and F > 0
    local xs, ys = { ax1 }, { ay1 }
    if feather then
        for _, b in ipairs({ cr[1] + F, cr[3] - F }) do if b > ax1 and b < ax2 then xs[#xs + 1] = b end end
        for _, b in ipairs({ cr[2] + F, cr[4] - F }) do if b > ay1 and b < ay2 then ys[#ys + 1] = b end end
    end
    xs[#xs + 1] = ax2
    ys[#ys + 1] = ay2
    sort(xs); sort(ys)

    local function AX(x) return clamp(min((x - cr[1]) / F, (cr[3] - x) / F), 0, 1) end
    local function AY(y) return clamp(min((y - cr[2]) / F, (cr[4] - y) / F), 0, 1) end

    local tw, th = x2 - x1, y2 - y1
    for i = 1, #xs - 1 do
        for j = 1, #ys - 1 do
            local sx1, sx2, sy1, sy2 = xs[i], xs[i + 1], ys[j], ys[j + 1]
            if sx2 - sx1 > 0.01 and sy2 - sy1 > 0.01 then
                local grad
                if feather then
                    local a1, a2 = AX(sx1), AX(sx2)
                    local b1, b2 = AY(sy1), AY(sy2)
                    local xc, yc = abs(a1 - a2) < 1e-4, abs(b1 - b2) < 1e-4
                    if xc and yc then
                        local a = a1 * b1
                        if a < 0.999 then grad = { "HORIZONTAL", a, a } end
                    elseif yc then
                        grad = { "HORIZONTAL", a1 * b1, a2 * b1 }
                    elseif xc then
                        grad = { "VERTICAL", b2 * a1, b1 * a1 }       -- bottom, top
                    else
                        local bc = AY((sy1 + sy2) / 2)
                        grad = { "HORIZONTAL", a1 * bc, a2 * bc }
                    end
                end
                NewSprite(list, id, sx1, sy1, sx2 - sx1, sy2 - sy1,
                          fc * (sx1 - x1) / tw, fc * (sx2 - x1) / tw,
                          fr * (sy1 - y1) / th, fr * (sy2 - y1) / th, o, grad)
            end
        end
    end
end

local function AddArtSprites(list, n, o)
    if not n.files then return end
    local tw, th = n.tileW * n.kx, n.tileH * n.ky
    for r = 0, n.rows - 1 do
        for c = 0, n.cols - 1 do
            local id = n.files[r * n.cols + c + 1]
            if id then
                -- the last column/row is only partly art
                local fc = min(1, (n.layerW - c * n.tileW) / n.tileW)
                local fr = min(1, (n.layerH - r * n.tileH) / n.tileH)
                local x1, y1 = n.x + c * tw, n.y + r * th
                EmitPiece(list, id, x1, y1, x1 + tw * fc, y1 + th * fr, fc, fr, o)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Explored-area overlays: this is where a zone's colour detail lives.
-- Same layout rules as Blizzard's own exploration provider. They belong to
-- their zone, so they only show while that zone has the focus.
---------------------------------------------------------------------------
-- Unexplored pieces (from the reveal data) go under the explored ones and are
-- dimmed, the way Carbonite draws unexplored areas.
local function AddOverlay(n, W, H, offX, offY, ids, unexplored)
    if not (ValidDim(W) and ValidDim(H) and type(ids) == "table") then return end
    local e = { fileDataIDs = ids, offsetX = offX, offsetY = offY }
    local TW, TH = n.tileW, n.tileH
    local nw, nh = ceil(W / TW), ceil(H / TH)
    local o = { sub = unexplored and SUB_FOG or SUB_OVER, minS = 100 / n.w, owner = n,
                layer = unexplored and "fog" or "over", shade = unexplored, mode = "map" }
    for j = 1, nh do
        local ph, fh
        if j < nh then
            ph, fh = TH, TH
        else
            ph = H % TH
            if ph == 0 then ph = TH end
            fh = 16
            while fh < ph do fh = fh * 2 end
        end
        for k = 1, nw do
            local pw, fw
            if k < nw then
                pw, fw = TW, TW
            else
                pw = W % TW
                if pw == 0 then pw = TW end
                fw = 16
                while fw < pw do fw = fw * 2 end
            end
            local id = e.fileDataIDs[(j - 1) * nw + k]
            if id then
                local px = n.x + ((e.offsetX or 0) + TW * (k - 1)) * n.kx
                local py = n.y + ((e.offsetY or 0) + TH * (j - 1)) * n.ky
                NewSprite(lists.over, id, px, py, pw * n.kx, ph * n.ky, 0, pw / fw, 0, ph / fh, o)
                local cv = n.cover
                cv[#cv + 1] = { px, py, px + pw * n.kx, py + ph * n.ky }
            end
        end
    end
    return true
end

local function BuildOverlays()
    needOverlays = false
    ClearList(lists.over)
    nExplored, nUnexplored, nRevealZones = 0, 0, 0
    if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return end
    for _, n in ipairs(zoneList) do
        n.nExp, n.nUnexp = 0, 0
        n.cover = {}
        -- explored pieces come from the game; a piece is identified by "w:h:x:y"
        local seen = {}
        local ok, list = pcall(C_MapExplorationInfo.GetExploredMapTextures, n.mapID)
        if ok and type(list) == "table" then
            for _, e in ipairs(list) do
                local W, H, X, Y = SafeNum(e.textureWidth), SafeNum(e.textureHeight), SafeNum(e.offsetX), SafeNum(e.offsetY)
                if W and H and X and Y then
                    seen[W .. ":" .. H .. ":" .. X .. ":" .. Y] = true
                    -- pieces the map only shows while the cursor is over them are not part of the picture
                    if not e.isShownByMouseOver then
                        local okO, added = pcall(AddOverlay, n, W, H, X, Y, e.fileDataIDs, false)
                        if okO and added then nExplored = nExplored + 1; n.nExp = (n.nExp or 0) + 1 end
                    end
                end
            end
        end
        -- everything else the zone has is unexplored
        local okA, artID = pcall(C_Map.GetMapArtID, n.mapID)
        local reveal = okA and ns.reveal and ns.reveal[artID or 0]
        if reveal then
            nRevealZones = nRevealZones + 1
            for key, idStr in pairs(reveal) do
                if not seen[key] then
                    local W, H, X, Y = key:match("^(%d+):(%d+):(%-?%d+):(%-?%d+)$")
                    local ids = {}
                    for id in idStr:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
                    if W and #ids > 0 then
                        local okO, added = pcall(AddOverlay, n, tonumber(W), tonumber(H), tonumber(X), tonumber(Y), ids, true)
                        if okO and added then nUnexplored = nUnexplored + 1; n.nUnexp = (n.nUnexp or 0) + 1 end
                    end
                end
            end
        end
    end
    dirty, tcache.pan = true, false
end

---------------------------------------------------------------------------
-- World <-> map conversion. The game's own GetWorldPosFromMapPos gives the
-- corner coordinates of a continent map; everything else follows from them.
---------------------------------------------------------------------------
local function Vec(mapID, u, v)
    local ok, a, b = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(u, v))
    if not ok then return end
    local vec = (type(b) == "table" and b) or (type(a) == "table" and a)
    if not vec then return end
    local x, y = vec.x, vec.y
    if x == nil and vec.GetXY then x, y = vec:GetXY() end
    x, y = SafeNum(x), SafeNum(y)
    if not (x and y) then return end
    return x, y, SafeNum(a)
end

-- Work out which world-position component runs along the map's horizontal
-- axis, and which way each axis increases. The continent art is 3:2, so the
-- component that changes ~1.5x as much across the map is the horizontal one.
local function Calibrate(cn)
    local a0, b0, inst = Vec(cn.mapID, 0, 0)
    local a1, b1 = Vec(cn.mapID, 1, 1)
    if not (a0 and a1) then return nil, "no world position for the map" end
    local da, db_ = a1 - a0, b1 - b0
    if da == 0 or db_ == 0 then return nil, "degenerate world position" end
    local want = log(cn.w / cn.h)
    local ra = log(abs(da) / abs(db_))
    local aIsH = abs(ra - want) <= abs(ra + want)
    local H0, H1, V0, V1
    if aIsH then H0, H1, V0, V1 = a0, a1, b0, b1 else H0, H1, V0, V1 = b0, b1, a0, a1 end
    return { H0 = H0, H1 = H1, V0 = V0, V1 = V1, inst = inst,
             sH = (H0 > H1) and 1 or -1, sV = (V0 > V1) and 1 or -1, aIsH = aIsH }
end

-- world position (the two vector components) -> map fractions
local function WorldToMap(cal, wx, wy)
    local H, V
    if cal.aIsH then H, V = wx, wy else H, V = wy, wx end
    return (H - cal.H0) / (cal.H1 - cal.H0), (V - cal.V0) / (cal.V1 - cal.V0)
end

---------------------------------------------------------------------------
-- Minimap detail tiles (the "zoom in further" level). Tile positions are
-- derived from the game's own world<->map conversion, so no hand-tuned
-- offsets are needed.
---------------------------------------------------------------------------
local function BuildMini(cn)
    local data = ns.tiles and ns.tiles[cn.mapID]
    cn.mini = nil
    if not data then return end
    local cal = cn.cal
    if not cal then cn.mini = { err = cn.calErr or "no calibration" }; return end

    local function U(c) return (cal.sH * (32 - c) * TILE_YARDS - cal.H0) / (cal.H1 - cal.H0) end
    local function V(r) return (cal.sV * (32 - r) * TILE_YARDS - cal.V0) / (cal.V1 - cal.V0) end

    -- Tile keys are column*100+row. Check that reading against the map and
    -- fall back to the swapped reading if it fits clearly worse.
    local total, inA, inB = 0, 0, 0
    for k in pairs(data) do
        local a, b = floor(k / 100), k % 100
        total = total + 1
        local ua, va = U(a + 0.5), V(b + 0.5)
        if ua >= 0 and ua <= 1 and va >= 0 and va <= 1 then inA = inA + 1 end
        local ub, vb = U(b + 0.5), V(a + 0.5)
        if ub >= 0 and ub <= 1 and vb >= 0 and vb <= 1 then inB = inB + 1 end
    end
    local swap = inB > inA + total * 0.15      -- keep the standard reading unless the swap is clearly better
    local inb = swap and inB or inA
    cn.mini = { total = total, inb = inb, swap = swap, aIsH = cal.aIsH, sH = cal.sH, sV = cal.sV }
    if total == 0 or inb < total * 0.5 then cn.mini.err = "tiles do not fit the map"; return end

    local tilePx = abs(U(1) - U(0)) * cn.w          -- canvas units per tile
    -- satellite mode only: the tiles fade in between ~40 and ~90 px per tile on screen
    local f0, f1 = 40 / tilePx, 90 / tilePx
    local o = { sub = SUB_MINI, minS = f0, fi0 = f0, fi1 = f1, layer = "mini", mode = "sat" }
    local count = 0
    for k, id in pairs(data) do
        local a, b = floor(k / 100), k % 100
        local col, row = a, b
        if swap then col, row = b, a end
        local u1, u2, v1, v2 = U(col), U(col + 1), V(row), V(row + 1)
        local x, y, w, h = cn.x + u1 * cn.w, cn.y + v1 * cn.h, (u2 - u1) * cn.w, (v2 - v1) * cn.h
        if w > 0 and h > 0 and u2 > 0 and u1 < 1 and v2 > 0 and v1 < 1 then
            NewSprite(lists.mini, id, x, y, w, h, 0, 1, 0, 1, o)
            count = count + 1
        end
    end
    cn.mini.count = count
end

---------------------------------------------------------------------------
-- Build everything
---------------------------------------------------------------------------
local function ComputeCrops()
    -- the land of a continent is the union of its zone rects
    for _, cn in ipairs(conts) do
        local x1, y1, x2, y2
        for _, z in ipairs(cn.zones) do
            x1 = min(x1 or z.x, z.x); y1 = min(y1 or z.y, z.y)
            x2 = max(x2 or z.x + z.w, z.x + z.w); y2 = max(y2 or z.y + z.h, z.y + z.h)
        end
        if x1 then cn.land = { x1, y1, x2, y2 }
        else cn.land = { cn.x, cn.y, cn.x + cn.w, cn.y + cn.h } end
        local L = cn.land
        -- the painting reaches a good way into the sea so the coast has room to feather out
        local mx, my = (L[3] - L[1]) * 0.14, (L[4] - L[2]) * 0.08
        cn.crop = { max(cn.x, L[1] - mx), max(cn.y, L[2] - my),
                    min(cn.x + cn.w, L[3] + mx), min(cn.y + cn.h, L[4] + my) }
    end
    -- two continents side by side: split the sea between them so the paintings never overlap
    for i = 1, #conts do
        for j = i + 1, #conts do
            local a, b = conts[i], conts[j]
            local A, B = a.land, b.land
            local yOver = A[2] < B[4] and B[2] < A[4]
            local xOver = A[1] < B[3] and B[1] < A[3]
            if yOver and not xOver then
                local l, r = a, b
                if B[3] <= A[1] then l, r = b, a end
                local mid = (l.land[3] + r.land[1]) / 2
                l.crop[3] = min(l.crop[3], mid); r.crop[1] = max(r.crop[1], mid)
            elseif xOver and not yOver then
                local u, d = a, b
                if B[4] <= A[2] then u, d = b, a end
                local mid = (u.land[4] + d.land[2]) / 2
                u.crop[4] = min(u.crop[4], mid); d.crop[2] = max(d.crop[2], mid)
            end
        end
    end
    local ux1, uy1, ux2, uy2
    for _, cn in ipairs(conts) do
        local c = cn.crop
        ux1 = min(ux1 or c[1], c[1]); uy1 = min(uy1 or c[2], c[2])
        ux2 = max(ux2 or c[3], c[3]); uy2 = max(uy2 or c[4], c[4])
    end
    if ux1 then
        local mx, my = (ux2 - ux1) * 0.03, (uy2 - uy1) * 0.03
        bx1, by1, bx2, by2 = ux1 - mx, uy1 - my, ux2 + mx, uy2 + my
    else
        bx1, by1, bx2, by2 = 0, 0, CW, CH
    end
end

local function Build()
    built = true
    -- Zephras Isle [2521]: Carbonite's scale 11.125 against Duskwood's [1431] 5.4
    local EXTRA_MAPS = { { id = 2521, ref = 1431, refScale = 5.4, scale = 11.125, cx = 0.522, cy = 0.5 } }
    wipe(nodes); wipe(byMap); wipe(conts); wipe(zoneList); wipe(labelNodes); wipe(cityList)
    focus, cityFocus = nil, nil
    ClearList(lists.base); ClearList(lists.zone); ClearList(lists.over); ClearList(lists.mini)

    local rootID = C_Map.GetFallbackWorldMapID() or 947
    local root = AddNode(rootID, 0, 0, CW, CH, 0)
    for _, c in ipairs(C_Map.GetMapChildrenInfo(rootID, Enum.UIMapType.Continent) or {}) do
        local cn = AddChild(c.mapID, root, 1)
        if cn then
            conts[#conts + 1] = cn
            for _, z in ipairs(C_Map.GetMapChildrenInfo(c.mapID, Enum.UIMapType.Zone, true) or {}) do
                if not byMap[z.mapID] then
                    local zn = AddChild(z.mapID, cn, 2)
                    if zn then cn.zones[#cn.zones + 1] = zn end
                end
            end
        end
    end
    -- maps the game keeps on an instance of their own, off both continents: set between the
    -- continents, as Carbonite does, sized against a zone of known size
    for _, ex in ipairs(EXTRA_MAPS) do
        local ref = byMap[ex.ref]
        if not byMap[ex.id] and ref and C_Map.GetMapInfo(ex.id) then
            local w = ref.w * ex.scale / ex.refScale
            local h = w * ref.h / ref.w
            local n = AddNode(ex.id, CW * ex.cx - w / 2, CH * ex.cy - h / 2, w, h, 2, root)
            n.extra = true
        end
    end
    if #conts == 0 then   -- zones hanging directly off the root
        for _, z in ipairs(C_Map.GetMapChildrenInfo(rootID, Enum.UIMapType.Zone, true) or {}) do
            AddChild(z.mapID, root, 2)
        end
    end
    ComputeCrops()
    for _, cn in ipairs(conts) do cn.cal, cn.calErr = Calibrate(cn) end

    for _, n in ipairs(nodes) do
        if n.level == 2 then
            labelNodes[#labelNodes + 1] = n
            if CITY[n.mapID] then
                if n.files then n.isCity = true; cityList[#cityList + 1] = n end
            elseif n.files then
                zoneList[#zoneList + 1] = n      -- cities stay out of the focus pick
            end
        end
    end

    -- 1. the world painting: it is all you see fully zoomed out, and it gives way to the continents
    local haveWorld = root.files ~= nil
    AddArtSprites(lists.base, root, { sub = SUB_WORLD, rel = true, fo0 = 2.8, fo1 = 5.0, maxS = 5.0, layer = "world" })
    -- 2. each continent painting cropped to its land and its coast
    for _, cn in ipairs(conts) do
        local c = cn.crop
        local o = { sub = SUB_CONT, crop = c, F = min(c[3] - c[1], c[4] - c[2]) * 0.07, layer = "cont" }
        if haveWorld then o.rel, o.fi0, o.fi1, o.minS = true, 1.6, 2.8, 1.6 end
        AddArtSprites(lists.base, cn, o)
    end
    -- 3. zone parchment base, one zone at a time (the focus decides which one shows).
    -- The base art is the zone's whole rectangle, with its neighbours' land as filler
    -- around the real zone, which shows up as a patch that does not blend with the map.
    -- A zone that has its exploration pieces (explored from the game, unexplored from
    -- the reveal data) is drawn from those alone, like Carbonite does. Only a zone without
    -- any of that keeps its base art.
    nBase, nNoBase = 0, 0
    for _, n in ipairs(zoneList) do
        local okA, artID = pcall(C_Map.GetMapArtID, n.mapID)
        local hasPieces = okA and ns.reveal and ns.reveal[artID or 0] ~= nil
        if hasPieces then nBase = nBase + 1 else nNoBase = nNoBase + 1 end
        if not hasPieces then
            AddArtSprites(lists.zone, n, { sub = SUB_ZONE, crop = { n.x, n.y, n.x + n.w, n.y + n.h },
                F = 0.07 * min(n.w, n.h), minS = ZONE_PX0 / n.w, owner = n, layer = "zone", mode = "map" })
        end
    end
    -- 4. cities carry their own complete art. They sit above the zone parchment and
    -- are shown whenever you (or the pointer) are inside the city (see UpdateFocus).
    for _, n in ipairs(cityList) do
        AddArtSprites(lists.base, n, { sub = SUB_CITY, crop = { n.x, n.y, n.x + n.w, n.y + n.h },
            F = 0.07 * min(n.w, n.h), minS = CITY_PX0 / n.w, owner = n, layer = "city", mode = "map" })
    end
    -- 5. explored-area overlays (follow their zone), 6. minimap detail tiles
    BuildOverlays()
    for _, cn in ipairs(conts) do BuildMini(cn) end
    -- pins the game itself knows about (flight masters, dungeon entrances ...)
    if ns.pins then
        local ids = { conts = {}, zones = {} }
        for _, cn in ipairs(conts) do ids.conts[#ids.conts + 1] = cn.mapID end
        for _, n in ipairs(nodes) do if n.level == 2 then ids.zones[#ids.zones + 1] = n.mapID end end
        local okP, errP = pcall(ns.pins.ReadGame, ids, byMap)
        if not okP then Say("pins: " .. tostring(errP)) end
    end

    minScale = min(VW / (bx2 - bx1), VH / (by2 - by1))
    dirty, tcache.pan = true, false
end


---------------------------------------------------------------------------
-- Pins: icons from the pin registry (Pins.lua), drawn in screen space above the
-- map so they keep their size at every zoom. A category is hidden below its own
-- zoom, and only the pins inside the window get a frame.
---------------------------------------------------------------------------
local MAX_PINS, PIN_MARGIN = 1000, 20
local atlasOK = {}

local function HaveAtlas(a)
    local v = atlasOK[a]
    if v == nil then
        v = true
        if C_Texture and C_Texture.GetAtlasInfo then v = C_Texture.GetAtlasInfo(a) ~= nil end
        atlasOK[a] = v
    end
    return v
end

local function SetPinIcon(tex, p, c)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetBlendMode(p.blend or "BLEND")
    local col = p.color
    local atlas = p.atlas or (not p.texture and not p.textureIndex and c.atlas)
    if type(atlas) == "table" then
        local pick
        for _, a in ipairs(atlas) do if HaveAtlas(a) then pick = a break end end
        atlas = pick
    end
    if atlas and HaveAtlas(atlas) and pcall(tex.SetAtlas, tex, atlas, false) then
        if col then tex:SetVertexColor(col[1], col[2], col[3], col[4] or 1) end
        return
    end
    local file = p.texture or ((not p.textureIndex) and c.texture)
    if file then
        tex:SetTexture(file)
        local tc = p.texCoord or (not p.texture and c.texCoord)
        if tc then
            if tc[8] then tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
            else tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        end
        if col then tex:SetVertexColor(col[1], col[2], col[3], col[4] or 1) end
        return
    end
    if p.textureIndex and GetPOITextureCoords then
        tex:SetTexture("Interface\\Minimap\\POIIcons")
        tex:SetTexCoord(GetPOITextureCoords(p.textureIndex))
        return
    end
    local cc = col or c.color or { 1, 1, 1, 1 }
    tex:SetColorTexture(cc[1], cc[2], cc[3], cc[4] or 1)
end

local function PinTooltip(b)
    local p, c = b.pin, b.cat
    if not p or not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if p.onTooltip then
        pcall(p.onTooltip, GameTooltip, p)
    else
        GameTooltip:SetText(p.name or c.name or "")
        local t = p.text
        if type(t) == "string" then GameTooltip:AddLine(t, 1, 1, 1, true)
        elseif type(t) == "table" then for _, l in ipairs(t) do GameTooltip:AddLine(tostring(l), 1, 1, 1, true) end end
    end
    GameTooltip:AddLine(c.name, 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

local function NewPinBtn(i)
    local b = CreateFrame("Button", nil, pinsFrame)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    -- a click that is really the start of a drag goes on to the map underneath
    if b.SetPropagateMouseClicks then pcall(b.SetPropagateMouseClicks, b, true) end
    b:SetScript("OnEnter", function(self)
        local p = self.pin
        self.hover = p
        if p and p.onEnter then pcall(p.onEnter, self, p) else PinTooltip(self) end
        if ns.StackTips then pcall(ns.StackTips, self, pinBtns) end       -- the pins lying under this one
    end)
    b:SetScript("OnLeave", function(self)
        local p = self.hover
        self.hover = nil
        if p and p.onLeave then pcall(p.onLeave, self, p) end
        if ns.HideStack then ns.HideStack() end
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self, btn)
        local p = self.pin
        if p and p.onClick and not dragMoved then Run(function() p.onClick(p, btn, self) end) end
    end)
    pinBtns[i] = b
    return b
end

-- A pin belongs to the map it was given for. It shows while that map's detailed art is the one
-- in view (the zone or city under the pointer), as on the game's own map; one given on a continent
-- belongs to the zone it lies in, and shows on the continent alone when no zone is in detail.
local function ZoneAt(px, py)
    local best, bd
    for _, z in ipairs(zoneList) do
        if px >= z.x and px <= z.x + z.w and py >= z.y and py <= z.y + z.h then
            local dx, dy = (px - (z.x + z.w / 2)) / z.w, (py - (z.y + z.h / 2)) / z.h
            local d = dx * dx + dy * dy
            if not bd or d < bd then best, bd = z, d end
        end
    end
    return best
end

-- Whose ground a point is: the game's own hit test on the continent map (what its world map uses
-- when the pointer hovers a zone). The zone rectangles overlap, so they cannot say.
local terrOK
-- Whose ground a point of the canvas is (for the pointer and the middle of the view; the hero's
-- own zone comes straight from the game). The zone rectangles overlap and the game's continent
-- hit test is coarse, so the zones' real terrain decides: the overlay pieces. Of the zones with a
-- piece on the point, the one whose centre is nearest (in its own proportions) has it; the zone
-- already shown (inc) gets a head start, so a border does not flicker.
-- cache: one table per asker.
-- The zone whose land a canvas point is, by the game's own continent map, or nil where it says
-- nothing (or names something that is not a zone here)
local function GameZoneAt(px, py)
    if not (C_Map and C_Map.GetMapInfoAtPosition) then return end
    for _, cn in ipairs(conts) do
        if px >= cn.x and px <= cn.x + cn.w and py >= cn.y and py <= cn.y + cn.h then
            local ok, info = pcall(C_Map.GetMapInfoAtPosition, cn.mapID, (px - cn.x) / cn.w, (py - cn.y) / cn.h)
            local z = ok and type(info) == "table" and byMap[SafeNum(info.mapID) or 0]
            if z and z.level == 2 and z.files and not z.isCity then return z end
            return
        end
    end
end

-- The zone under a canvas point. The game's word first; where it says nothing, the zone whose art
-- pieces reach the point (several: the one whose middle is nearest). No zone is favoured for
-- being shown already (art pieces are squares and spill past borders: a favoured zone stuck).
-- (inc is kept for the callers; it no longer counts)
local function Territory(px, py, inc, cache)
    if cache.q and abs(px - cache.px) + abs(py - cache.py) < 1.5 / max(scale, 0.01) then return cache.node end
    cache.q, cache.px, cache.py = true, px, py
    local pick = GameZoneAt(px, py)
    if pick then
        terrOK = true
        cache.node = pick
        return pick
    end
    local pd
    for _, z in ipairs(zoneList) do
        local cv = z.cover
        if cv and px >= z.x and px <= z.x + z.w and py >= z.y and py <= z.y + z.h then
            for i = 1, #cv do
                local r = cv[i]
                if px >= r[1] and px <= r[3] and py >= r[2] and py <= r[4] then
                    local dx, dy = (px - (z.x + z.w / 2)) / z.w, (py - (z.y + z.h / 2)) / z.h
                    local d = dx * dx + dy * dy
                    if not pd or d < pd then pick, pd = z, d end
                    break
                end
            end
        end
    end
    if pick then terrOK = true end
    cache.node = pick
    return pick
end

-- /cmap where: who claims the point in the middle of the view (or under the pointer)
function ns.probe(say, px, py)
    say(("point %.0f,%.0f | game hit test: %s"):format(px, py, (function()
        for _, cn in ipairs(conts) do
            if px >= cn.x and px <= cn.x + cn.w and py >= cn.y and py <= cn.y + cn.h then
                local ok, info = pcall(C_Map.GetMapInfoAtPosition, cn.mapID, (px - cn.x) / cn.w, (py - cn.y) / cn.h)
                return ok and type(info) == "table" and ("%s [%s]"):format(tostring(info.name), tostring(info.mapID)) or "no answer"
            end
        end
        return "no continent"
    end)()))
    for _, z in ipairs(zoneList) do
        if px >= z.x - z.w * 0.05 and px <= z.x + z.w * 1.05 and py >= z.y - z.h * 0.05 and py <= z.y + z.h * 1.05 then
            local inRect = px >= z.x and px <= z.x + z.w and py >= z.y and py <= z.y + z.h
            local cov = false
            for _, r in ipairs(z.cover or {}) do
                if px >= r[1] and px <= r[3] and py >= r[2] and py <= r[4] then cov = true break end
            end
            say(("  %s [%d]: in rect %s | terrain here %s | pieces %d+%d | rect %.0f,%.0f %.0fx%.0f%s"):format(
                z.name, z.mapID, tostring(inRect), tostring(cov), z.nExp or 0, z.nUnexp or 0, z.x, z.y, z.w, z.h,
                z == focus and " | FOCUS" or ""))
        end
    end
end

local function UpdatePins()
    local P = ns.pins
    if not (P and pinsFrame) then return end
    local used = 0
    -- the zone in detail: the focus (map mode), or the zone in the middle of the view (satellite)
    local detail = focus
    if db.mode == "sat" then
        local cx, cy = (VW / 2 - ox) / scale, (VH / 2 - oy) / scale
        detail = Territory(cx, cy, detail, tcache.p) or ZoneAt(cx, cy)
        tcache.satDetail = detail
    end
    if detail and detail.w * scale < ZONE_PX0 then detail = nil end
    local city = cityFocus
    if city and city.w * scale < CITY_PX0 then city = nil end
    -- icons grow with the map, as Carbonite's do: small when zoomed out, large up close
    -- in step with the zoom: at the start zoom (3.73) a pin has its own size, half the zoom half of it
    local zf = clamp(scale / 3.73, 0.2, 4) * (db.pinSize or 1)
    -- the maps whose pins can show now: the world and the continents, the zone and city in
    -- detail, and (map mode) every zone or city drawn in detail; pins of other maps are not looked at
    local maps, seen = tcache.pinMaps or {}, tcache.pinSeen or {}
    tcache.pinMaps, tcache.pinSeen = maps, seen
    for i = #maps, 1, -1 do maps[i] = nil end
    for k in pairs(seen) do seen[k] = nil end
    local function AddMap(n) if n and not seen[n.mapID] then seen[n.mapID] = true; maps[#maps + 1] = n.mapID end end
    for _, n in ipairs(nodes) do if n.level < 2 then AddMap(n) end end
    AddMap(detail); AddMap(city)
    if db.mode ~= "sat" then
        for _, n in ipairs(zoneList) do if (n.alpha or 0) * (n.zoomA or 0) > 0.5 then AddMap(n) end end
        for _, n in ipairs(cityList) do if (n.alpha or 0) * (n.zoomA or 0) > 0.5 then AddMap(n) end end
    end
    local function Draw(c, list, sz)
        for i = 1, #list do
            local p = list[i]
            local n = p.map and byMap[p.map]
            local px, py = p.x, p.y
            if n and px and py then
                local show
                if c.always then show = true
                elseif n.level and n.level < 2 then
                    local owner
                    if n.level == 1 then
                        if p.ownRev ~= P.rev then
                            p.ownRev, p.owner = P.rev, ZoneAt(n.x + px * n.w, n.y + py * n.h) or false
                        end
                        owner = p.owner or nil
                    end
                    show = (detail == nil and city == nil) or (owner ~= nil and (owner == detail or owner == city))
                else
                    show = (n == detail) or (n == city) or (db.mode ~= "sat" and (n.alpha or 0) * (n.zoomA or 0) > 0.5)
                end
                if not show then px = nil end
            end
            if n and px and py then
                local sx = (n.x + px * n.w) * scale         -- on the layer (which moves with the map)
                local sy = (n.y + py * n.h) * scale
                local qx, qy = sx + ox, sy + oy             -- on screen: drawn within half a view round it
                if qx > -VW * 0.5 - PIN_MARGIN and qx < VW * 1.5 + PIN_MARGIN and qy > -VH * 0.5 - PIN_MARGIN and qy < VH * 1.5 + PIN_MARGIN then
                    used = used + 1
                    local b = pinBtns[used] or NewPinBtn(used)
                    if b.pin ~= p or b.rev ~= P.rev then
                        b.pin, b.cat, b.rev = p, c, P.rev
                        SetPinIcon(b.icon, p, c)
                        -- extra layers drawn on the pin (Bridge.lua: Dungeon Journal's X), and away again
                        if (p.deco or b.decoOn) and ns.PinDeco then pcall(ns.PinDeco, b, p) end
                        b.base = p.size or sz
                        b:SetFrameLevel(pinsFrame:GetFrameLevel() + 1 + (p.level or 0))     -- (level: what lies on top)
                    end
                    -- (a pin can size itself from how wide its zone is on screen: RareScanner's spots)
                    local s = p.sizeFn and p.sizeFn(n.w * scale) or b.base * zf * (c.scaleKey and db[c.scaleKey] or 1)
                    if b.sz ~= s then b.sz = s; b:SetSize(s, s) end
                    b:ClearAllPoints()
                    -- (a pin can sit a few pixels off its point, dx right / dy up: Spy's enemies, kept
                    -- clear of the hero's arrow they were seen from)
                    b:SetPoint("CENTER", tcache.layer, "TOPLEFT", sx + (p.dx or 0), -sy + (p.dy or 0))
                    b:Show()
                    if used >= MAX_PINS then return end
                end
            end
        end
    end
    -- two passes: every category first, then the bulk ones (gathering nodes, hundreds at once), so
    -- that if the limit is reached it is the bulk that runs short, never a rare or a quest
    for pass = 1, 2 do
    for _, id in ipairs(P.order) do
        local c = P.cats[id]
        if c and used < MAX_PINS and (c.bulk and 2 or 1) == pass and scale >= (c.minScale or 0) and P.IsEnabled(id) then
            local sz = c.size or 18
            if c.always then
                Draw(c, c.pins, sz)             -- (few, and they move between maps: all of them)
            else
                local idx = P.ByMap(c)
                for _, m in ipairs(maps) do
                    local list = idx[m]
                    if list and used < MAX_PINS then Draw(c, list, sz) end
                end
            end
        end
    end
    end
    for i = used + 1, pinsShown do
        local b = pinBtns[i]
        if b then b:Hide(); b.pin = nil end
    end
    pinsShown = used
    -- what is drawn in detail right now, for whoever lays things over the zones (quest areas)
    if ns.afterUpdate then
        local shown = ns.shownZones or {}
        ns.shownZones = shown
        for i = #shown, 1, -1 do shown[i] = nil end
        if db.mode == "sat" then
            if detail then shown[1] = detail end
        else
            for _, z in ipairs(zoneList) do
                if (z.alpha or 0) * (z.zoomA or 0) > 0.5 then shown[#shown + 1] = z end
            end
        end
        -- the zones whose pins can show, for the addons that read pins per zone (GatherMate,
        -- RareScanner): the zone in detail shows its pins from the moment it starts to fade in,
        -- before it counts as drawn above, so it is read from then on too
        local pz = ns.pinZones or {}
        ns.pinZones = pz
        for i = #pz, 1, -1 do pz[i] = nil end
        local hasDetail
        for i, z in ipairs(shown) do pz[i] = z; if z == detail then hasDetail = true end end
        if detail and not hasDetail then pz[#pz + 1] = detail end
        ns.prof.Time("pins: overlays of other parts (quest areas, markers, GatherMate, RareScanner)", ns.afterUpdate, view, canvas, ox, oy, scale, db.mode, shown, db)
    end
end

---------------------------------------------------------------------------
-- Drawing pass
---------------------------------------------------------------------------
local function Update()
    dirty = false
    local vx1, vy1 = -ox / scale, -oy / scale
    local vx2, vy2 = vx1 + VW / scale, vy1 + VH / scale
    local T = ns.prof.Time
    -- only moved, and still inside what was drawn last time (the view and half of it again on
    -- every side): the tiles, pins and labels are all there already; only what is laid over the
    -- zones by other parts (quest areas, quest markers) follows the map by hand
    local cr, pan = tcache.cull, tcache.pan
    tcache.pan = nil
    if pan and db.mode == "sat" then
        -- satellite: the zone in detail is the one in the middle of the view, which moving changes
        local cx, cy = (VW / 2 - ox) / scale, (VH / 2 - oy) / scale
        if (Territory(cx, cy, nil, tcache.p) or ZoneAt(cx, cy)) ~= tcache.satDetail then pan = nil end
    end
    if pan and cr and cr.s == scale and cr.mode == db.mode and vx1 >= cr[1] and vy1 >= cr[2] and vx2 <= cr[3] and vy2 <= cr[4] then
        if ns.prof.on then ns.prof.Add("frame: redraws, light (only moved)", 0) end
        if ns.afterUpdate and ns.shownZones then
            T("pins: overlays of other parts, light (quest areas only)", ns.afterUpdate, view, canvas, ox, oy, scale, db.mode, ns.shownZones, db, true)
        end
        return
    end
    local mx, my = (vx2 - vx1) * 0.5, (vy2 - vy1) * 0.5
    vx1, vy1, vx2, vy2 = vx1 - mx, vy1 - my, vx2 + mx, vy2 + my
    tcache.cull = { vx1, vy1, vx2, vy2, s = scale, mode = db.mode }
    T("draw: base tiles", UpdateList, lists.base, vx1, vy1, vx2, vy2)
    T("draw: zone tiles", UpdateList, lists.zone, vx1, vy1, vx2, vy2)
    T("draw: overlay pieces", UpdateList, lists.over, vx1, vy1, vx2, vy2)
    T("draw: satellite tiles", UpdateList, lists.mini, vx1, vy1, vx2, vy2)
    local t0 = ns.prof.on and debugprofilestop()

    -- zone name labels (screen space so the text stays readable); in map mode
    -- they step aside once the zone's own parchment is showing
    local sat = db.mode == "sat"
    for _, n in ipairs(labelNodes) do
        local px = n.w * scale
        local cx, cy = n.x + n.w / 2, n.y + n.h / 2
        local la = sat and 1 or (1 - n.alpha * n.zoomA)
        if la > 0.05 and px >= 90 and px <= VW * 0.7 and cx > vx1 and cx < vx2 and cy > vy1 and cy < vy2 then
            n.label = n.label or AcquireLabel()
            n.label:SetText(n.name)
            n.label:SetAlpha(la)
            n.label:ClearAllPoints()
            n.label:SetPoint("CENTER", tcache.layer, "TOPLEFT", cx * scale, -cy * scale)
        elseif n.label then
            ReleaseLabel(n.label); n.label = nil
        end
    end
    if t0 then ns.prof.Add("draw: zone labels", debugprofilestop() - t0) end
    T("draw: pins (all)", UpdatePins)
end

---------------------------------------------------------------------------
-- Pan / zoom
---------------------------------------------------------------------------
local function Apply()
    local bw, bh = (bx2 - bx1) * scale, (by2 - by1) * scale
    if bw <= VW then ox = (VW - bw) / 2 - bx1 * scale
    else ox = min(-bx1 * scale, max(VW - bx2 * scale, ox)) end
    if bh <= VH then oy = (VH - bh) / 2 - by1 * scale
    else oy = min(-by1 * scale, max(VH - by2 * scale, oy)) end
    canvas:SetScale(scale)
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", view, "TOPLEFT", ox / scale, -oy / scale)
    -- pins and labels ride on this layer: moving the map moves them all at once
    local layer = tcache.layer
    if layer then layer:ClearAllPoints(); layer:SetPoint("TOPLEFT", view, "TOPLEFT", ox, -oy) end
    -- the zoom figure: shown while zooming, gone a second after (onUpdate)
    if zoomText and ns.zoomBox and ns.zoomLast ~= scale then
        zoomText:SetText(tcache.ZoomLabel(scale / minScale))
        local box = ns.zoomBox
        box:SetSize((zoomText:GetStringWidth() or 50) + 10, 16)
        if ns.zoomLast then box:Show(); ns.zoomAt = GetTime() end      -- (not for the first draw)
        ns.zoomLast = scale
    end
    if not dirty then tcache.pan = true end
    dirty = true
    if db then   -- remember the view: centre in canvas units and zoom
        db.vc, db.vx, db.vy, db.vs = true, (VW / 2 - ox) / scale, (VH / 2 - oy) / scale, scale
    end
end

local function CursorInView()
    local x, y = GetCursorPosition()
    local s = view:GetEffectiveScale()
    return x / s - view:GetLeft(), view:GetTop() - y / s
end

-- Zoom as people read it: x1 is the whole world fitted to the window, and the wheel steps
-- through round figures (x1, x1.25, x1.5, x2 ... x24, x32 ...), each about a fifth to a third
-- more than the last. The deepest zoom (the mode's limit) need not be one of them.
tcache.ZOOMS = { 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128, 160,
    192, 256, 320, 384, 512, 640, 768, 1024 }
function tcache.ZoomLabel(rel)
    if rel >= 10 then return ("x%d"):format(floor(rel + 0.5)) end
    local t = ("%.2f"):format(rel):gsub("0+$", ""):gsub("%.$", "")
    return "x" .. t
end
-- the next step in (d > 0) or out from the zoom now
function tcache.ZoomStep(d)
    local rel, z = scale / minScale, tcache.ZOOMS
    if d > 0 then
        for i = 1, #z do if z[i] > rel * 1.001 then return z[i] end end
        return z[#z]
    end
    for i = #z, 1, -1 do if z[i] < rel * 0.999 then return z[i] end end
    return 1
end

local function ZoomAt(factor, cx, cy)
    local ns_ = clamp(scale * factor, minScale, MaxScale())
    local px, py = (cx - ox) / scale, (cy - oy) / scale
    scale = ns_
    ox, oy = cx - px * ns_, cy - py * ns_
    Apply()
end

local function CenterOn(px, py, s)
    scale = clamp(s or scale, minScale, MaxScale())
    ox, oy = VW / 2 - px * scale, VH / 2 - py * scale
    Apply()
end

---------------------------------------------------------------------------
-- Focus: only the zone under the cursor (or the view centre) is drawn in
-- detail. Hysteresis keeps it from flickering between overlapping zone
-- rects, and every zone fades in and out instead of popping.
---------------------------------------------------------------------------
local function PickZone(px, py)
    local best, bd
    for _, n in ipairs(zoneList) do
        if px >= n.x and px <= n.x + n.w and py >= n.y and py <= n.y + n.h then
            local dx, dy = (px - (n.x + n.w / 2)) / n.w, (py - (n.y + n.h / 2)) / n.h
            local d = dx * dx + dy * dy
            if not bd or d < bd then best, bd = n, d end
        end
    end
    return best, bd
end

-- Cities take precedence over the zone parchment: whoever is inside a city
-- (the player while following, otherwise the pointer or the view centre) gets
-- that city's own map. Once in, it takes a clear step out of the city to leave.
local function InRect(n, px, py, m)
    local mx, my = n.w * m, n.h * m
    return px >= n.x - mx and px <= n.x + n.w + mx and py >= n.y - my and py <= n.y + n.h + my
end

local function CityAt(px, py)
    if cityFocus and InRect(cityFocus, px, py, 0.1) then return cityFocus end
    for _, n in ipairs(cityList) do
        if InRect(n, px, py, 0) then return n end
    end
end

-- one fade step for a zone or city: 5/s in, 2.5/s out, and by its width on screen
local function FadeStep(n, on, p0, p1, dt)
    local changed = false
    local a, target = n.alpha, on and 1 or 0
    if a ~= target then
        -- uncovering is instant (a fade-in showed the art half-loaded: it flickered while the
        -- game read it from disk, as Carbonite never fades in either); leaving still fades out
        if target == 1 then a = 1 else a = max(0, a - 2.5 * dt) end
        n.alpha = a
        changed = true
    end
    local za = clamp((n.w * scale - p0) / (p1 - p0), 0, 1)
    if za ~= n.zoomA then n.zoomA = za; changed = true end
    return changed
end

-- Ctrl+click: drop (or lift) the game's own map pin, the one the world map's "Map Pin" button places
function ns.onCtrlClick(px, py, sc)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
    local n
    if cityFocus and px >= cityFocus.x and px <= cityFocus.x + cityFocus.w and py >= cityFocus.y and py <= cityFocus.y + cityFocus.h then
        n = cityFocus
    elseif focus and px >= focus.x and px <= focus.x + focus.w and py >= focus.y and py <= focus.y + focus.h then
        n = focus
    else
        n = ZoneAt(px, py)
    end
    local cur = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if cur and cur.uiMapID and byMap[cur.uiMapID] and cur.position then
        local wn = byMap[cur.uiMapID]
        local wx, wy = wn.x + cur.position.x * wn.w, wn.y + cur.position.y * wn.h
        if abs(wx - px) * sc < 14 and abs(wy - py) * sc < 14 then
            C_Map.ClearUserWaypoint()
            if ns.bridge then pcall(ns.bridge.ReadWaypoint) end
            return
        end
    end
    if not n then return end
    local x, y = (px - n.x) / n.w, (py - n.y) / n.h
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(n.mapID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    if ns.bridge then pcall(ns.bridge.ReadWaypoint) end
end

local prevFocus, lastFocus, hoverZone, hoverCity, hoverPrev
-- The zone the hero came from stays drawn while the hero is within BAND_YD yards of its land
-- (asked of the game at eight points round the hero, four times a second); the pointer gets no
-- such band. tcache.band: when it was last checked.
tcache.BAND_YD = 50
function tcache.HeroNear(z)
    if not (z and following and plX) then return false end
    if UnitOnTaxi and UnitOnTaxi("player") then return false end     -- flying: the zone behind goes at once
    local ypc       -- yards per canvas unit, from the zone's size in the world
    if C_Map and C_Map.GetMapWorldSize then
        local ok, w = pcall(C_Map.GetMapWorldSize, z.mapID)
        w = ok and SafeNum(w)
        if w and w > 0 then ypc = w / z.w end
    end
    local r = ypc and tcache.BAND_YD / ypc or z.w * 0.03
    if GameZoneAt(plX, plY) == z then return true end
    for k = 0, 7 do
        local a = k * math.pi / 4
        if GameZoneAt(plX + r * math.cos(a), plY + r * math.sin(a)) == z then return true end
    end
    return false
end
-- /cmap fade: every map update for a few seconds, what is uncovered and how far each fade is
function tcache.FadeLog(dt, over, tag)
    local fl = ns.fadeLog
    local now = GetTime()
    if now > fl.till then
        ns.fadeLog = nil
        if ns.ShowCopy then ns.ShowCopy(table.concat(fl, "\n")) end
    elseif now >= fl.from then
        local parts = {}
        for _, n in ipairs(zoneList) do
            if (n.alpha or 0) > 0 then
                parts[#parts + 1] = ("%s=%.2f%s%s%s%s"):format(n.name or n.mapID, n.alpha, n == focus and " F" or "", n == hoverZone and " H" or "",
                    n == prevFocus and " P" or "", n == plNode and " Me" or "")
            end
        end
        fl[#fl + 1] = ("%.3f dt=%.3f %s%s | %s"):format(now - fl.from, dt or 0, over and "pointer" or "-", tag, table.concat(parts, ", "))
    end
end

-- The pointer uncovers a zone only after resting on it for a moment (DWELL seconds): sweeping
-- across the map no longer flashes every zone on the way. dw[key]: the zone under the pointer
-- now (cand), for how long (t), and the one uncovered (cur). Off the window: at once.
tcache.dw, tcache.DWELL = {}, 0.12
function tcache.Dwell(key, cand, dt, now)
    local d = tcache.dw[key]
    if not d then d = { t = 0 }; tcache.dw[key] = d end
    if cand ~= d.cand then d.cand, d.t = cand, 0 else d.t = d.t + (dt or 0) end
    if now or d.t >= tcache.DWELL or d.cur == nil and cand ~= nil and d.first then d.cur = cand end
    d.first = nil
    if d.cand ~= d.cur then tcache.dwPending = true end
    return d.cur
end

function ns.dbgView() return ox, oy, scale, focus, hoverZone, prevFocus end     -- (tests)

local function UpdateFocus(dt)
    if not built or (#zoneList == 0 and #cityList == 0) or db.mode == "sat" then return end   -- parchment is a map-mode thing
    -- nothing moved (pointer, hero, map), nothing fading, no zone held by the band: nothing to decide
    local gx, gy = GetCursorPosition()
    local over = view:IsMouseOver()
    local fk = tcache.fk
    local pend = tcache.dwPending
    tcache.dwPending = nil
    if fk and not fk.fading and not pend and not prevFocus and not drag and fk[1] == gx and fk[2] == gy and fk[3] == over
       and fk[4] == plX and fk[5] == plY and fk[6] == scale and fk[7] == ox and fk[8] == oy and fk[9] == following
       and fk[10] == #zoneList then
        if ns.fadeLog then tcache.FadeLog(dt, over, " (unchanged)") end
        return
    end
    fk = fk or {}
    tcache.fk = fk
    fk[1], fk[2], fk[3], fk[4], fk[5], fk[6], fk[7], fk[8], fk[9], fk[10] = gx, gy, over, plX, plY, scale, ox, oy, following, #zoneList
    local cx, cy
    local pointer = view:IsMouseOver() or drag ~= nil
    if pointer then cx, cy = CursorInView() else cx, cy = VW / 2, VH / 2 end
    local px, py = (cx - ox) / scale, (cy - oy) / scale
    -- not following: only the pointer uncovers a map. With the pointer elsewhere, what is shown stays
    -- (the middle of the window decides nothing, so dragging the map does not uncover what passes it)
    local hold = not pointer and not (following and plX)
    if not hold then

    -- a player inside a city keeps the city, wherever the pointer wanders
    local city
    local heroZone
    if following and plX then
        px, py = plX, plY           -- following: the map in detail is the hero's, wherever the pointer is
        -- the game itself says which map the hero is on: no guessing at borders
        if plNode and plNode.level == 2 and plNode.files then
            if plNode.isCity then city = plNode else heroZone = plNode end
        end
        city = city or CityAt(plX, plY)
    end
    city = city or CityAt(px, py)
    cityFocus = city

    -- following: the pointer still uncovers the map it hovers (besides the hero's)
    hoverZone, hoverCity = nil, nil
    if following and plX and view:IsMouseOver() then
        local hx, hy = (cx - ox) / scale, (cy - oy) / scale
        hoverCity = tcache.Dwell("hc", CityAt(hx, hy), dt)
        if hoverCity == cityFocus then hoverCity = nil end
        hoverZone = tcache.Dwell("hz", Territory(hx, hy, hoverPrev, tcache.h) or PickZone(hx, hy), dt)
        hoverPrev = hoverZone
        if hoverZone == focus then hoverZone = nil end
    else
        tcache.Dwell("hz", nil, dt, true); tcache.Dwell("hc", nil, dt, true)
    end

    -- the zone under the city (Elwynn under Stormwind) stays as its backdrop
    local host = city and CITY_HOST[city.mapID] and byMap[CITY_HOST[city.mapID]]
    if host and host.files and not CITY[host.mapID] then
        focus = host
    elseif heroZone then
        focus = heroZone
    else
        local land = Territory(px, py, focus, tcache.f)
        local want = focus
        local best, bd
        if land then
            want = land
        else
            best, bd = PickZone(px, py)
        end
        if best and best ~= focus then
            local dc
            if focus and px >= focus.x and px <= focus.x + focus.w and py >= focus.y and py <= focus.y + focus.h then
                local dx, dy = (px - (focus.x + focus.w / 2)) / focus.w, (py - (focus.y + focus.h / 2)) / focus.h
                dc = dx * dx + dy * dy
            end
            if not dc or bd < dc * 0.64 then want = best end     -- switch only when clearly closer
        end
        -- (the pointer: after the pause; nothing shown yet: at once)
        focus = tcache.Dwell("f", want, dt, not focus or not pointer) or want
    end

    end     -- (not hold)
    if focus ~= lastFocus then
        -- the hero walked (or flew) out of a zone: it may stay a while (the band); the pointer: gone
        -- (on a flight path: gone at once too, the band is for walking and riding)
        local byHero = following and plX and plNode == focus and not (UnitOnTaxi and UnitOnTaxi("player"))
        prevFocus = (byHero and lastFocus) or nil
        lastFocus = focus
        tcache.band = nil
    end
    if prevFocus then
        local now = GetTime()
        if not tcache.band or now - tcache.band > 0.25 then
            tcache.band = now
            if not tcache.HeroNear(prevFocus) then prevFocus = nil end
        end
    end
    local changed = false
    -- the zones whose art is kept loaded (hidden): those within ~250 px of the pointer, and those
    -- touching the hero's zone; a change of that set has the art redrawn
    local px1, py1, px2, py2
    if over then
        local mx, my = CursorInView()
        local r = 250 / scale
        mx, my = (mx - ox) / scale, (my - oy) / scale
        px1, py1, px2, py2 = mx - r, my - r, mx + r, my + r
    end
    local hz = plNode and plNode.level == 2 and plNode
    for _, n in ipairs(zoneList) do
        local w = (px1 and n.x < px2 and n.x + n.w > px1 and n.y < py2 and n.y + n.h > py1)
            or (hz and n.x < hz.x + hz.w * 1.1 and n.x + n.w > hz.x - hz.w * 0.1 and n.y < hz.y + hz.h * 1.1 and n.y + n.h > hz.y - hz.h * 0.1)
            or false
        if n.warm ~= w then n.warm = w; changed = true end
    end
    for _, n in ipairs(zoneList) do
        -- the zone you are on and the one you came from stay drawn, nothing else
        local want = n == focus or n == prevFocus or n == hoverZone or n == plNode or n.extra   -- (the hero's own zone always; an island off the continents too, nothing else shows it)
        if FadeStep(n, want, ZONE_PX0, ZONE_PX1, dt) then changed = true end
    end
    for _, n in ipairs(cityList) do
        if FadeStep(n, n == cityFocus or n == hoverCity or n == plNode, CITY_PX0, CITY_PX1, dt) then changed = true end
    end
    tcache.fk.fading = changed
    if changed then dirty, tcache.pan = true, false end
    if ns.fadeLog then tcache.FadeLog(dt, over, "") end
end

---------------------------------------------------------------------------
-- Player position. Sources, in order: the map position on the best map and
-- its parents, any continent map, then UnitPosition converted with the same
-- corner calibration the minimap tiles use.
---------------------------------------------------------------------------
local function PosOnMap(mapID)
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return end
    local ok2, x, y = pcall(pos.GetXY, pos)
    x, y = SafeNum(x), SafeNum(y)
    if not (ok2 and x and y) then return end
    if x <= 0 and y <= 0 then return end
    return x, y
end

local function UnitRaw()
    if not UnitPosition then return end
    local p1, p2, _, inst = UnitPosition("player")
    p1, p2 = SafeNum(p1), SafeNum(p2)
    if not (p1 and p2) then return end
    return p1, p2, SafeNum(inst)
end

-- mode 2 (default): UnitPosition returns the vector's x, y in that order, the
-- way Blizzard feeds it to GetMapPosFromWorldPos. Mode 1: the other way round.
local function UnitMapFrac(cal, p1, p2, mode)
    if mode == 1 then return WorldToMap(cal, p2, p1) end
    return WorldToMap(cal, p1, p2)
end

-- Compare UnitPosition with a position the map API gave us, to learn which
-- axis order UnitPosition uses.
local function LearnUnit(cn, px, py)
    if unitMode or not cn or not cn.cal then return end
    local p1, p2, inst = UnitRaw()
    if not p1 then return end
    if inst and cn.cal.inst and inst ~= cn.cal.inst then return end
    local bestMode, bestD
    for mode = 1, 2 do
        local u, v = UnitMapFrac(cn.cal, p1, p2, mode)
        local d = abs(cn.x + u * cn.w - px) + abs(cn.y + v * cn.h - py)
        if not bestD or d < bestD then bestMode, bestD = mode, d end
    end
    if bestD and bestD < 0.03 * cn.w then unitMode = bestMode end
end

local function UnitCanvasPos()
    local p1, p2, inst = UnitRaw()
    if not p1 then return end
    for _, cn in ipairs(conts) do
        local cal = cn.cal
        if cal and (not inst or not cal.inst or inst == cal.inst) then
            for _, mode in ipairs(unitMode and { unitMode } or { 2, 1 }) do
                local u, v = UnitMapFrac(cal, p1, p2, mode)
                if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
                    return cn.x + u * cn.w, cn.y + v * cn.h, cn
                end
            end
        end
    end
end

local function PlayerCanvasPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    local first
    local m, guard = mapID, 0
    while m and guard < 8 do
        guard = guard + 1
        local n = byMap[m]
        if n then
            first = first or n
            local x, y = PosOnMap(m)
            if x then
                local px, py = n.x + x * n.w, n.y + y * n.h
                local cn = n
                while cn and cn.level > 1 do cn = cn.parent end
                if cn and cn.level == 1 then LearnUnit(cn, px, py) end
                return px, py, first, "map"
            end
        end
        local mi = C_Map.GetMapInfo(m)
        m = mi and mi.parentMapID
        if m == 0 then m = nil end
    end
    for _, cn in ipairs(conts) do
        local x, y = PosOnMap(cn.mapID)
        if x then return cn.x + x * cn.w, cn.y + y * cn.h, first or cn, "continent" end
    end
    local ux, uy, cn = UnitCanvasPos()
    if ux then return ux, uy, first or cn, "unit" end
end

local function PlayerReport()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local mapID = C_Map.GetBestMapForUnit("player")
    local mi = mapID and C_Map.GetMapInfo(mapID)
    add(("best map %s %s, in map tree: %s"):format(tostring(mapID), mi and mi.name or "?",
        tostring(mapID ~= nil and byMap[mapID] ~= nil)))
    local m, g = mapID, 0
    while m and g < 8 do
        g = g + 1
        local info_ = C_Map.GetMapInfo(m)
        local x, y = PosOnMap(m)
        add(("  map %d %s%s: position %s, %s"):format(m, info_ and info_.name or "?",
            byMap[m] and "" or " (not in tree)", F4(x), F4(y)))
        m = info_ and info_.parentMapID
        if m == 0 then m = nil end
    end
    for _, cn in ipairs(conts) do
        local x, y = PosOnMap(cn.mapID)
        add(("  continent %d %s: position %s, %s"):format(cn.mapID, cn.name, F4(x), F4(y)))
    end
    local p1, p2, inst = UnitRaw()
    add(("UnitPosition: %s, %s instance %s | axis order learned: %s"):format(F4(p1), F4(p2),
        tostring(inst), tostring(unitMode)))
    if p1 then
        for _, cn in ipairs(conts) do
            if cn.cal then
                local u1, v1 = UnitMapFrac(cn.cal, p1, p2, 1)
                local u2, v2 = UnitMapFrac(cn.cal, p1, p2, 2)
                add(("  %s (instance %s): first=y -> %s, %s | first=x -> %s, %s"):format(cn.name,
                    tostring(cn.cal.inst), F4(u1), F4(v1), F4(u2), F4(v2)))
            else
                add(("  %s: no calibration (%s)"):format(cn.name, tostring(cn.calErr)))
            end
        end
    end
    local px, py, n, src = PlayerCanvasPos()
    if px then
        add(("result: canvas %.0f, %.0f on %s via %s"):format(px, py, n and n.name or "?", src))
    else
        add("result: no position from any source")
    end
    local f = GetPlayerFacing and GetPlayerFacing()
    add(("facing %s | follow %s"):format(F4(f), tostring(following)))
    return lines
end

local function GotoPlayer(keepScale)
    local px, py, n = PlayerCanvasPos()
    if not px then return false end
    local s = scale
    if not keepScale and n and n.w > 0 then s = VW * 0.9 / n.w end
    CenterOn(px, py, s)
    if n and n.level == 2 and n.files then
        if n.isCity then cityFocus = n else focus = n end
    end
    return true
end

local function StyleFollow()
    if not followBtn then return end
    local on = following
    if followBtn.SetOn then followBtn.SetOn(on) end
end

local function SetFollow(on)
    following = on and true or false
    lastPX, lastPY = nil, nil
    StyleFollow()
    if on and not GotoPlayer(scale >= 0.5) then
        Say("follow is on, but the player position is not available yet (/cmap debug)")
    end
end


local function ApplyMarker()
    if not player then return end
    player:SetTexture(ARROW)
    player:SetSize(MARK, MARK)
end

-- A zone's level range as " (10-20)", coloured as Carbonite does by whose land it is: green your
-- faction's, orange shared, red the other faction's; "" when there is none (cities)
function ns.ZoneLevels(n)
    if not n then return "" end
    local lv = tcache.lv or {}
    tcache.lv = lv
    local r = lv[n.mapID]
    if r == nil then
        local lo, hi
        if C_Map and C_Map.GetMapLevels then
            local ok, a, b = pcall(C_Map.GetMapLevels, n.mapID)
            if ok then lo, hi = SafeNum(a), SafeNum(b) end
        end
        if not (lo and hi and lo > 0 and hi >= lo) then
            local t = ns.ZONE_LEVELS and ns.ZONE_LEVELS[n.mapID]
            lo, hi = t and t[1], t and t[2]
        end
        local t = ns.ZONE_LEVELS and ns.ZONE_LEVELS[n.mapID]
        r = lo and { lo, hi, t and t[3] or 2 } or false
        lv[n.mapID] = r
    end
    if not r then return "" end
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    mine = (mine == "Alliance" and 0) or (mine == "Horde" and 1) or nil
    local c = (r[3] == 2 or mine == nil) and "ff9933" or (r[3] == mine and "40d040") or "ff3030"
    return (" |cff%s(%s)|r"):format(c, r[1] == r[2] and r[1] or (r[1] .. "-" .. r[2]))
end

-- yards per canvas unit on a continent (the canvas keeps each continent in proportion)
local function Yards(cn)
    if not cn.ypc then          -- (asked again until the game answers)
        if C_Map and C_Map.GetMapWorldSize then
            local ok, w = pcall(C_Map.GetMapWorldSize, cn.mapID)
            w = ok and SafeNum(w)
            if w and w > 0 then cn.ypc = w / cn.w end
        end
    end
    return cn.ypc
end

local function UpdateCursor()
    if not view:IsMouseOver() then info:SetText("") return end
    local cx, cy = CursorInView()
    local px, py = (cx - ox) / scale, (cy - oy) / scale
    local best, bestD
    for _, n in ipairs(nodes) do
        if n.level > 0 and px >= n.x and px <= n.x + n.w and py >= n.y and py <= n.y + n.h then
            -- a city map wins anywhere on it (the smallest, if two overlap); otherwise zone rects
            -- overlap their neighbours: take the one whose centre is nearest
            local d
            if n.isCity then
                d = -1e6 + n.w * n.h
            else
                local dx, dy = (px - (n.x + n.w / 2)) / n.w, (py - (n.y + n.h / 2)) / n.h
                d = dx * dx + dy * dy + (n.level == 1 and 10 or 0)
            end
            if not bestD or d < bestD then best, bestD = n, d end
        end
    end
    if best then
        -- name (and level range), the position below it, and how far it is from the hero
        local text = best.name .. ns.ZoneLevels(best) .. ("\n%.1f, %.1f"):format(100 * (px - best.x) / best.w, 100 * (py - best.y) / best.h)
        local cn, hn = best, plNode
        while cn and cn.level > 1 do cn = cn.parent end
        while hn and hn.level > 1 do hn = hn.parent end
        local ypc = cn and cn == hn and plX and Yards(cn)
        if ypc then
            local dx, dy = (px - plX) * ypc, (py - plY) * ypc
            text = text .. ("\n|cffbbbbbb%d yd|r"):format(floor(math.sqrt(dx * dx + dy * dy) + 0.5))
        end
        info:SetText(text)
    else
        info:SetText(nodes[1] and nodes[1].name or "")
    end
end

-- The title bar: where the hero is (zone, level range, position), a few times a second
function ns.HeroTitle(title)
    local now = GetTime()
    if tcache.tAt and now - tcache.tAt < 0.2 then return end
    tcache.tAt = now
    local n = plNode
    if n and n.level and n.level >= 2 and plX then
        title:SetText(("%s%s  |cffffffff%.1f, %.1f|r"):format(n.name, ns.ZoneLevels(n), 100 * (plX - n.x) / n.w, 100 * (plY - n.y) / n.h))
    elseif n and n.name then
        title:SetText(n.name)
    else
        title:SetText("")
    end
end

local function UpdatePlayer()
    -- standing still, facing the same way, the map not moved: the arrow is where it was. (The
    -- world position is cheap to ask; working out the map position is not.)
    local wy, wx
    if UnitPosition then
        local a, b = UnitPosition("player")
        wy, wx = SafeNum(a), SafeNum(b)
    end
    local f0 = SafeNum(GetPlayerFacing and GetPlayerFacing())
    local k = tcache.pk
    if wx and k and k[1] == wx and k[2] == wy and k[3] == f0 and k[4] == ox and k[5] == oy and k[6] == scale
       and plX and (not following or (lastPX == plX and lastPY == plY)) then
        return
    end
    if k then k[1] = nil end
    -- Moving: between the game's map look-ups (four a second, and at once in another instance)
    -- the arrow follows the world position through the continent's calibration, corrected by
    -- what the last look-up said, so the two never disagree
    local px, py, node
    local h = tcache.hero
    local now = GetTime()
    if h and unitMode and now - h.at < 0.25 then
        local p1, p2, inst = UnitRaw()
        if p1 and (not inst or not h.inst or inst == h.inst) then
            local u, v = UnitMapFrac(h.cn.cal, p1, p2, unitMode)
            px, py, node = h.cn.x + u * h.cn.w + h.dx, h.cn.y + v * h.cn.h + h.dy, plNode
        end
    end
    if not px then
        px, py, node = PlayerCanvasPos()
        tcache.hero = nil
        local cn = node
        while cn and cn.level and cn.level > 1 do cn = cn.parent end
        if px and unitMode and cn and cn.level == 1 and cn.cal then
            local p1, p2, inst = UnitRaw()
            if p1 then
                local u, v = UnitMapFrac(cn.cal, p1, p2, unitMode)
                local dx, dy = px - (cn.x + u * cn.w), py - (cn.y + v * cn.h)
                -- (only when the calibration is close: a large correction would mean it is off here)
                if abs(dx) < 0.02 * cn.w and abs(dy) < 0.02 * cn.h then
                    tcache.hero = { at = now, cn = cn, inst = inst, dx = dx, dy = dy }
                end
            end
        end
    end
    plX, plY, plNode = px, py, node
    if not px then player:Hide() return end
    -- Follow recentres when the hero moves - but not while the pointer is on the window (you are
    -- looking at something): it catches up the moment the pointer leaves
    if following and not drag and (lastPX ~= px or lastPY ~= py) and not frame:IsMouseOver() then
        lastPX, lastPY = px, py
        CenterOn(px, py)          -- recentre first so the arrow lands where the view now is
    end
    player:ClearAllPoints()
    player:SetPoint("CENTER", view, "TOPLEFT", ox + px * scale, -(oy + py * scale))
    local f = SafeNum(GetPlayerFacing and GetPlayerFacing())
    if f then player:SetRotation(f) end
    player:Show()
    if wx then
        k = k or {}
        tcache.pk = k
        k[1], k[2], k[3], k[4], k[5], k[6] = wx, wy, f0, ox, oy, scale
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SavePosition()
    local p, _, rp, x, y = frame:GetPoint()
    if p then db.pos = { p, rp, x, y } end
end

local function OnResize(w, h)
    if not uiReady then return end
    local oldCX, oldCY = (VW / 2 - ox) / scale, (VH / 2 - oy) / scale
    VW, VH = max(50, w - 2 * PAD), max(50, h - BAR_H - 2 * PAD)
    minScale = min(VW / (bx2 - bx1), VH / (by2 - by1))
    scale = clamp(scale, minScale, MaxScale())
    ox, oy = VW / 2 - oldCX * scale, VH / 2 - oldCY * scale
    db.w, db.h = floor(w + 0.5), floor(h + 0.5)
    Apply()
end

-- A text button (menu rows), or with `icon` a square icon button for the toolbar inside the map.
-- An icon button has SetOn(bool): lit and gold-edged, or grey.
local function MakeButton(parent, text, w, onClick, tip, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(icon and 22 or w, icon and 22 or 18)
    b:SetFrameLevel(parent:GetFrameLevel() + 6)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local base = icon and { 0, 0, 0, 0.6 } or { 1, 1, 1, 0.08 }
    local over = icon and { 0.35, 0.35, 0.35, 0.8 } or { 1, 1, 1, 0.22 }
    bg:SetColorTexture(base[1], base[2], base[3], base[4])
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(icon and "" or text)
    b.text = fs
    if icon then
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 2, -2); tex:SetPoint("BOTTOMRIGHT", -2, 2)
        tex:SetTexture(icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = tex
        function b.SetOn(on)
            b.on = on and true or false
            if tex.SetDesaturated then tex:SetDesaturated(not on) end
            tex:SetVertexColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
            base = on and { 1, 0.82, 0, 0.9 } or { 0, 0, 0, 0.6 }
            bg:SetColorTexture(base[1], base[2], base[3], base[4])
        end
    end
    b:SetScript("OnClick", function() Run(onClick) end)
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(over[1], over[2], over[3], over[4])
        if tip and GameTooltip then
            GameTooltip:SetOwner(b, icon and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
            GameTooltip:SetText(type(tip) == "function" and tip() or tip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(base[1], base[2], base[3], base[4])
        if tip and GameTooltip then GameTooltip:Hide() end
    end)
    return b
end

-- Map mode shows the parchment maps (zoom right in); satellite mode shows the
-- terrain from the minimap tiles. The button names the view you get by clicking.
-- Quest areas: how the quests that are not the active one are drawn (the button cycles)
local QM = {
    next = { dim = "tracked", tracked = "dim" },
    label = { dim = "Quests: all, others dimmed", tracked = "Quests: tracked only" },
    tip = { dim = "Quest areas: the tracked quest as on the game's map, the others dimmed",
            tracked = "Quest areas: only the tracked quest" },
}
local function SetQuestMode(m)
    db.blobMode = QM.label[m] and m or "dim"
    if ns.menuRefresh then ns.menuRefresh() end
    if ns.bridge and ns.bridge.RestyleBlobs then ns.bridge.RestyleBlobs() end
    if ns.bridge and ns.bridge.QuestsChanged then ns.bridge.QuestsChanged() end
    dirty, tcache.pan = true, false
end
local modeBtn
local function StyleMode()
    -- the icon is the view a click gives
    if modeBtn and modeBtn.icon then
        modeBtn.icon:SetTexture(db.mode == "sat" and "Interface\\Icons\\INV_Misc_Map_01" or "Interface\\Icons\\INV_Misc_Spyglass_03")
    end
end

local function SetMode(m)
    if m ~= "map" and m ~= "sat" then return end
    local cx, cy = (VW / 2 - ox) / scale, (VH / 2 - oy) / scale
    db.mode = m
    StyleMode()
    CenterOn(cx, cy, scale)       -- re-applies the zoom limit of the new mode and redraws
end


---------------------------------------------------------------------------
-- Pins menu: one checkbox per category in the registry. Categories drawn for other addons go in
-- a list of their own, opened from the "Other addons" entry at the bottom: one checkbox each,
-- under the addon's name when it has more than one.
---------------------------------------------------------------------------
local menuRows, menuRev = { sub = {} }, -1

local function RefreshMenu()
    local P = ns.pins
    if not (pinMenu and P) then return end
    local function Row(list, i, parent)
        local row = list[i]
        if row then return row end
        row = CreateFrame("Button", nil, parent)
        row:SetHeight(20)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        row.box = row:CreateTexture(nil, "ARTWORK")
        row.box:SetSize(18, 18)
        row.box:SetPoint("LEFT", 6, 0)
        row.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        row.check = row:CreateTexture(nil, "OVERLAY")
        row.check:SetSize(18, 18)
        row.check:SetPoint("CENTER", row.box, "CENTER", 0, 0)
        row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetScript("OnClick", function(self)
            if self.open then self.open() return end
            if self.all then P.SetAllOff(not P.AllOff()); RefreshMenu() return end
            if not self.id then return end
            if P.AllOff() then P.SetTemp(self.id, not P.IsTemp(self.id))     -- shown for now, the saved choice untouched
            else P.SetEnabled(self.id, not P.IsChecked(self.id)) end
            RefreshMenu()
        end)
        row:SetScript("OnEnter", function(self)
            local sub = menuRows.panel
            if self.open then self.open() elseif sub and self:GetParent() == pinMenu then sub:Hide() end
        end)
        list[i] = row
        return row
    end
    -- kind: "pin" (a checkbox), "all" (the switch for every pin), "head" (an addon's name),
    -- "more" (opens the addons list). With every pin off, the ticks are the ones shown for now
    -- (the saved choices wait, untouched, for all to be switched back on).
    local allOff = P.AllOff()
    local function Put(row, parent, y, kind, id, text, indent)
        row.id, row.open, row.all = kind == "pin" and id or nil, nil, kind == "all" or nil
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
        row:SetHeight(kind == "head" and 16 or (kind == "all" and allOff) and 30 or 20)
        row.label:ClearAllPoints()
        row:EnableMouse(kind ~= "head")
        if kind == "pin" or kind == "all" then
            row.box:SetPoint("LEFT", 6 + (indent or 0), 0)
            row.box:Show()
            row.label:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
            local on = kind == "all" and not allOff or (kind == "pin" and (allOff and P.IsTemp(id) or not allOff and P.IsChecked(id)))
            if on then row.check:Show() else row.check:Hide() end
            if kind == "pin" and allOff and on then row.label:SetTextColor(0.6, 0.85, 1)       -- shown for now
            else row.label:SetTextColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6) end
        else
            row.box:Hide(); row.check:Hide()
            row.label:SetPoint("LEFT", 8, 0)
            if kind == "head" then row.label:SetTextColor(1, 0.82, 0) else row.label:SetTextColor(1, 1, 1) end
        end
        row.label:SetText(text)
        row.label:SetJustifyH("LEFT")
        row:Show()
        return (row.label:GetStringWidth() or 0) + (kind == "pin" and 40 + (indent or 0) or 24)
    end
    local function Label(c, short)
        local name = c.name
        if short and c.addon and name:sub(1, #c.addon + 2) == c.addon .. ": " then name = name:sub(#c.addon + 3) end
        return c.noCount and name or ("%s |cff888888(%d)|r"):format(name, #c.pins)
    end

    -- the main list, under the switch for every pin
    local y, widest, n = -8, 150, 1
    widest = max(widest, Put(Row(menuRows, 1, pinMenu), pinMenu, y, "all", nil,
        allOff and "All pins |cff888888(off: tick any to show just those for now;\nyour saved choices come back when this is on)|r" or "All pins"))
    y = y - (allOff and 34 or 24)
    local addons, byAddon = {}, {}
    for _, id in ipairs(P.order) do
        local c = P.cats[id]
        if c.addon then
            if not byAddon[c.addon] then byAddon[c.addon] = {}; addons[#addons + 1] = c.addon end
            local t = byAddon[c.addon]
            t[#t + 1] = id
        else
            n = n + 1
            widest = max(widest, Put(Row(menuRows, n, pinMenu), pinMenu, y, "pin", id, Label(c)))
            y = y - 20
        end
    end
    local more
    if #addons > 0 then
        n = n + 1
        more = Row(menuRows, n, pinMenu)
        widest = max(widest, Put(more, pinMenu, y - 4, "more", nil, "Other addons   >"))
        y = y - 24
    end
    for i = n + 1, #menuRows do menuRows[i]:Hide() end
    pinMenu:SetSize(widest + 8, -y + 8)
    menuRev = P.menuRev

    -- the addons list, beside its entry: to the right if the screen has room, else to the left
    local sub = menuRows.panel
    if not more then if sub then sub:Hide() end return end
    if not sub then
        sub = CreateFrame("Frame", nil, pinMenu)
        sub:SetFrameStrata("DIALOG")
        sub:SetFrameLevel(pinMenu:GetFrameLevel() + 10)
        sub:SetClampedToScreen(true)
        sub:EnableMouse(true)
        local bg = sub:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
        sub:Hide()
        menuRows.panel = sub
    end
    table.sort(addons)
    local sy, sw, k = -6, 150, 0
    for _, name in ipairs(addons) do
        local ids = byAddon[name]
        if #ids > 1 then
            k = k + 1
            sw = max(sw, Put(Row(menuRows.sub, k, sub), sub, sy, "head", nil, name))
            sy = sy - 16
        end
        for _, id in ipairs(ids) do
            k = k + 1
            sw = max(sw, Put(Row(menuRows.sub, k, sub), sub, sy, "pin", id, Label(P.cats[id], #ids > 1), #ids > 1 and 10 or 0))
            sy = sy - 20
        end
        sy = sy - 4
    end
    for i = k + 1, #menuRows.sub do menuRows.sub[i]:Hide() end
    sub:SetSize(sw + 8, -sy + 4)
    more.open = function()
        local es = pinMenu:GetEffectiveScale()
        local room = (UIParent:GetRight() or 0) * UIParent:GetEffectiveScale() - (pinMenu:GetRight() or 0) * es
        sub:ClearAllPoints()
        if room >= (sub:GetWidth() + 6) * es then
            sub:SetPoint("TOPLEFT", more, "TOPRIGHT", 8, 4)
        else
            sub:SetPoint("TOPRIGHT", more, "TOPLEFT", -8, 4)
        end
        sub:Show()
    end
end

local function TogglePinMenu()
    if not pinMenu then
        pinMenu = CreateFrame("Frame", nil, frame)
        pinMenu:SetFrameStrata("DIALOG")
        pinMenu:SetPoint("TOPRIGHT", view, "TOPRIGHT", -2, -2)        -- (its Options entry puts it beside itself)
        if pinMenu.SetIgnoreParentAlpha then pinMenu:SetIgnoreParentAlpha(true) end
        pinMenu:SetClampedToScreen(true)
        local bg = pinMenu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
        pinMenu:EnableMouse(true)
        pinMenu:Hide()
    end
    if pinMenu:IsShown() then
        pinMenu:Hide()
    else
        RefreshMenu()
        pinMenu:Show()
    end
end

-- Options: a drop-down like the Pins list, holding the window's transparency, the Pins list and
-- the quest area mode
local optMenu
local function ApplyAlpha()
    if frame then frame:SetAlpha(clamp(db.alpha or 1, 0.2, 1)) end
end
-- A context menu: the Options list, and every entry of it that has more to choose opens its own
-- list beside it (to the left: the menu hangs from the right end of the title bar).
local function CreateOptions(anchor)
    local questMenu
    local function CloseSubs()
        if pinMenu then pinMenu:Hide() end
        if questMenu then questMenu:Hide() end
    end
    local optBtn = MakeButton(anchor, "Options", 52, function()
        if optMenu:IsShown() then
            optMenu:Hide()
            CloseSubs()
        else
            optMenu:Show()
        end
    end, "Options: transparency, pins and quest areas", "Interface\\Icons\\Trade_Engineering")

    local function Panel(w, h)
        local f = CreateFrame("Frame", nil, frame)
        f:SetFrameStrata("DIALOG")
        f:SetSize(w, h)
        if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end     -- the menus stay readable
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)                  -- a list never runs off the screen
        f:Hide()
        return f
    end

    optMenu = Panel(200, 146)
    optMenu:SetPoint("BOTTOMRIGHT", optBtn, "TOPRIGHT", 0, 6)          -- inside the window, above its button
    optMenu:SetScript("OnHide", CloseSubs)

    -- a labelled slider; set() stores the value, text() names it
    local function Slider(lo, hi, step, value, set, text)
        local label = optMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetText(text(value))
        local s = CreateFrame("Slider", nil, optMenu)
        s:SetOrientation("HORIZONTAL")
        s:SetSize(180, 14)
        s.label = label
        local track = s:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
        track:SetColorTexture(1, 1, 1, 0.2)
        local thumb = s:CreateTexture(nil, "ARTWORK")
        thumb:SetSize(10, 14)
        thumb:SetColorTexture(1, 0.82, 0, 1)
        s:SetThumbTexture(thumb)
        s:SetMinMaxValues(lo, hi)
        s:SetValueStep(step)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        s:SetValue(clamp(value, lo, hi))
        s:EnableMouse(true)
        s:SetScript("OnValueChanged", function(_, v)
            v = clamp(floor(v / step + 0.5) * step, lo, hi)
            set(v)
            label:SetText(text(v))
        end)
        s:SetScript("OnEnter", CloseSubs)
        return s
    end
    local items = {}                -- top to bottom; laid out whenever the menu opens
    items[1] = Slider(0.2, 1, 0.05, db.alpha or 1,
        function(v) db.alpha = v; ApplyAlpha() end,
        function(v) return ("Window opacity: %d%%"):format(floor(v * 100 + 0.5)) end)
    items[2] = Slider(0.5, 2.5, 0.1, db.pinSize or 1,
        function(v) db.pinSize = v; dirty, tcache.pan = true, false end,
        function(v) return ("Pin size: %d%%"):format(floor(v * 100 + 0.5)) end)
    -- only with GatherMate2 around (it may load after the map was first opened: looked for at every opening)
    local gmSlider
    local function Layout()
        if not gmSlider and _G.GatherMate2 then
            gmSlider = Slider(0.1, 1, 0.05, clamp(db.gmSize or 1, 0.1, 1),
                function(v) db.gmSize = v; dirty, tcache.pan = true, false end,
                function(v) return ("GatherMate pin size: %d%%"):format(floor(v * 100 + 0.5)) end)
            table.insert(items, 3, gmSlider)
        end
        local y = -8
        local firstEntry
        for _, it in ipairs(items) do
            it:ClearAllPoints()
            if rawget(it, "label") then
                it.label:ClearAllPoints()
                it.label:SetPoint("TOPLEFT", optMenu, "TOPLEFT", 10, y)
                it:SetPoint("TOPLEFT", optMenu, "TOPLEFT", 10, y - 18)
                y = y - 42
            else
                -- the entries (Pins, Quest areas) sit right of the 60 Hz square, which spans both
                firstEntry = firstEntry or y
                it:SetPoint("TOPLEFT", optMenu, "TOPLEFT", 10 + 48, y)
                y = y - 24
            end
        end
        if firstEntry and optMenu.hzBtn then
            optMenu.hzBtn:ClearAllPoints()
            optMenu.hzBtn:SetPoint("TOPLEFT", optMenu, "TOPLEFT", 10, firstEntry)
        end
        optMenu:SetHeight(-y + 4)
    end
    optMenu:SetScript("OnShow", Layout)

    -- a list of an entry opens beside the menu: to the right if the screen has the room, else to the left
    local function Beside(sub, entry)
        local es = optMenu:GetEffectiveScale()
        local room = (UIParent:GetRight() or 0) * UIParent:GetEffectiveScale() - (optMenu:GetRight() or 0) * es
        sub:ClearAllPoints()
        if room >= (sub:GetWidth() + 6) * es then
            sub:SetPoint("TOPLEFT", entry, "TOPRIGHT", 12, 4)
        else
            sub:SetPoint("TOPRIGHT", entry, "TOPLEFT", -12, 4)
        end
    end

    -- an entry with a list of its own: opens on hover and on click, beside the entry
    local function Entry(text, open)
        local b = MakeButton(optMenu, text .. "   >", 180 - 48, open)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 6, 0)
        b:HookScript("OnEnter", function() Run(open) end)
        items[#items + 1] = b
        return b
    end

    pinsBtn = Entry("Pins", function()
        if questMenu then questMenu:Hide() end
        if not (pinMenu and pinMenu:IsShown()) then TogglePinMenu() end
        Beside(pinMenu, pinsBtn)
    end)

    local questRows = {}
    local questEntry
    questEntry = Entry("Quest areas", function()
        if pinMenu then pinMenu:Hide() end
        if not questMenu then
            questMenu = Panel(210, 52)
            local y = -6
            for _, mode in ipairs({ "dim", "tracked" }) do
                local row = MakeButton(questMenu, "", 198, function() SetQuestMode(mode) end, QM.tip[mode])
                row:SetPoint("TOPLEFT", 6, y)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", 6, 0)
                row.mode = mode
                questRows[#questRows + 1] = row
                y = y - 22
            end
        end
        ns.menuRefresh()
        Beside(questMenu, questEntry)
        questMenu:Show()
    end)
    -- 60 Hz mode: a square left of the two entries, as tall as both
    -- the update cap: off, 60 or 30 times a second; each click moves to the next
    local function ShowCap(b)
        b.text:SetText(db.cap and (db.cap .. " Hz") or "Off")
        if b.SetOn then b.SetOn(db.cap ~= nil) end
    end
    local hzBtn = MakeButton(optMenu, "", 42, function()
        db.cap = (db.cap == nil and 60) or (db.cap == 60 and 30) or nil
        ShowCap(optMenu.hzBtn)
    end, function()
        local now = db.cap and ("on, at most %d times a second"):format(db.cap) or "off, every frame"
        return "Map update cap: " .. now .. ".\nClick: " .. (db.cap == nil and "60 Hz" or db.cap == 60 and "30 Hz" or "off")
            .. ".\nLess work at high frame rates; 30 Hz is the lightest, with slightly less smooth movement."
    end, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    hzBtn:SetSize(42, 42)
    hzBtn.text:ClearAllPoints()
    hzBtn.text:SetPoint("BOTTOM", 0, 3)
    hzBtn.text:SetFontObject("GameFontHighlightSmall")
    ShowCap(hzBtn)
    optMenu.hzBtn = hzBtn
    function ns.menuRefresh()
        for _, row in ipairs(questRows) do
            local on = (db.blobMode or "dim") == row.mode
            row.text:SetText((on and "|cffffd100> |r" or "   ") .. QM.label[row.mode])
        end
    end
    Layout()
    ApplyAlpha()
    return optBtn
end

-- pins and the player arrow, stacked above the zone names (a function of its own:
-- Lua allows a function only 60 upvalues, and CreateUI was at the limit)
local function CreateTopLayers()
    pinsFrame = CreateFrame("Frame", nil, view)
    pinsFrame:SetAllPoints(view)
    tcache.layer = CreateFrame("Frame", nil, view)
    ns.pinLayer = tcache.layer
    tcache.layer:SetSize(1, 1)
    tcache.layer:SetPoint("TOPLEFT", view, "TOPLEFT", ox, -oy)
    pinsFrame:SetFrameLevel(canvas:GetFrameLevel() + 6)
    pinsFrame:EnableMouse(false)

    playerFrame = CreateFrame("Frame", nil, view)
    playerFrame:SetAllPoints(view)
    playerFrame:SetFrameLevel(canvas:GetFrameLevel() + 40)
    playerFrame:EnableMouse(false)

    player = playerFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    player:Hide()
    ApplyMarker()

    if ns.pins then
        ns.pins.onChange = function()
            dirty, tcache.pan = true, false
            if pinMenu and pinMenu:IsShown() and menuRev ~= ns.pins.menuRev then RefreshMenu() end
        end
    end
end

-- The frame fades like Carbonite's: while the pointer is away from the window, the title bar's
-- background, the edges round the map, the close button, the resize grip and the toolbar fade
-- out; the map, the title text (zone, levels, position) and the readouts stay as they are. They
-- come back as soon as the pointer is over the window, and stay while a menu is open or the
-- window is being moved or resized.
function ns.ChromeFade(frame, bar, barBg, close, grip, tools)
    local parts = { barBg }
    -- a strip from a point of the frame (its top left corner) to another (its bottom right corner)
    local function Edge(p1, x1, y1, p2, x2, y2)
        local t = frame:CreateTexture(nil, "BACKGROUND")
        t:SetPoint("TOPLEFT", frame, p1, x1, y1)
        t:SetPoint("BOTTOMRIGHT", frame, p2, x2, y2)
        t:SetColorTexture(0.04, 0.04, 0.05, 0.92)
        parts[#parts + 1] = t
    end
    Edge("TOPLEFT", 0, -BAR_H, "BOTTOMLEFT", PAD, 0)                    -- left
    Edge("TOPRIGHT", -PAD, -BAR_H, "BOTTOMRIGHT", 0, 0)                 -- right
    Edge("BOTTOMLEFT", PAD, PAD, "BOTTOMRIGHT", -PAD, 0)                -- bottom
    Edge("TOPLEFT", PAD, -BAR_H, "TOPRIGHT", -PAD, -(BAR_H + PAD))      -- between the bar and the map
    for _, f in ipairs({ close, grip, tools }) do parts[#parts + 1] = f end
    local busy, a, away = false, 1, 0
    local function Busy() busy = true end
    local function Free() busy = false end
    bar:HookScript("OnDragStart", Busy); bar:HookScript("OnDragStop", Free)
    grip:HookScript("OnMouseDown", Busy); grip:HookScript("OnMouseUp", Free)
    local fader = CreateFrame("Frame", nil, frame)
    fader:SetScript("OnUpdate", function(_, dt)
        local want = busy or frame:IsMouseOver() or (optMenu and optMenu:IsShown())
        if want then
            away = 0
            if a >= 1 then return end
            a = math.min(1, a + dt * 6)                 -- back in about 0.15 s
        else
            away = away + dt
            if a <= 0 or away < 0.5 then return end     -- half a second before it starts going
            a = math.max(0, a - dt * 2)                 -- gone in half a second
        end
        for _, p in ipairs(parts) do p:SetAlpha(a) end
    end)
end

local function CreateUI()
    frame = CreateFrame("Frame", nil, UIParent)
    _G.CloudeMapFrame = frame
    frame:SetSize(db.w, db.h)
    if db.pos then
        frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        frame:SetPoint("CENTER", 0, 0)
    end
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, floor(UIParent:GetWidth()), floor(UIParent:GetHeight()))
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, MIN_H)
    end
    frame:Hide()

    -- the background under the map only: the edges around it belong to the frame, which fades
    -- (ns.ChromeFade)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", PAD, -(BAR_H + PAD))
    bg:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    bg:SetColorTexture(0.04, 0.04, 0.05, 0.92)

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(BAR_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePosition() end)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.12, 0.12, 0.14, 1)

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 6, 0)
    title:SetText("")           -- (where the hero is: ns.HeroTitle)

    -- a small close button that stays inside the title bar
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(BAR_H - 4, BAR_H - 4)
    close:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    close:SetFrameLevel(bar:GetFrameLevel() + 6)
    close:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    close:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    close:SetScript("OnClick", function() db.shown = false; frame:Hide() end)

    -- names the map shown when it is not ours (Bridge.lua: a dungeon, a battleground)
    local barText = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    barText:SetPoint("LEFT", title, "RIGHT", 10, 0)
    barText:SetPoint("RIGHT", close, "LEFT", -6, 0)
    barText:SetJustifyH("LEFT")
    barText:SetWordWrap(false)

    VW, VH = db.w - 2 * PAD, db.h - BAR_H - 2 * PAD
    view = CreateFrame("Frame", nil, frame)
    view:SetPoint("TOPLEFT", PAD, -(BAR_H + PAD))
    view:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    view:SetClipsChildren(true)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)

    canvas = CreateFrame("Frame", nil, view)
    canvas:SetSize(CW, CH)

    -- Regions of a frame draw under its child frames, so anything that has to
    -- stay visible above the map (player arrow, zone names) lives on its own
    -- frame stacked above the canvas.
    top = CreateFrame("Frame", nil, view)
    top:SetAllPoints(view)
    top:SetFrameLevel(canvas:GetFrameLevel() + 5)
    top:EnableMouse(false)

    CreateTopLayers()

    grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(view:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); SavePosition() end)

    -- The buttons: icons in the bottom right corner of the map, on a frame of the window (not of
    -- the clipped view) so they also stay above a map shown over ours (Bridge.lua). tools.list
    -- is their order; tools.Layout() packs the ones that are shown.
    local tools = CreateFrame("Frame", nil, frame)
    tools:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -20, 6)      -- clear of the resize grip
    tools:SetSize(22, 22)
    tools:SetFrameLevel(view:GetFrameLevel() + 520)
    local options = CreateOptions(tools)
    modeBtn = MakeButton(tools, "", 22, function() SetMode(db.mode == "sat" and "map" or "sat") end,
        function() return db.mode == "sat" and "Switch to the parchment map" or "Switch to the satellite view" end,
        "Interface\\Icons\\INV_Misc_Map_01")
    StyleMode()
    followBtn = MakeButton(tools, "", 22, function() SetFollow(not following) end,
        "Follow: keep the map on your hero. Click it again after switching it off to come back to the hero.",
        "Interface\\Icons\\Ability_Tracking")
    StyleFollow()
    tools.list = { options, modeBtn, followBtn }
    function tools.Layout()
        local x = 0
        for _, b in ipairs(tools.list) do
            if b:IsShown() then
                b:ClearAllPoints()
                b:SetPoint("RIGHT", tools, "RIGHT", -x, 0)      -- from the corner inwards
                x = x + b:GetWidth() + 3
            end
        end
        tools:SetWidth(max(x, 1))
    end
    tools.Layout()

    -- where the pointer is: top right inside the map, on a faint box, only while there is something to say
    local infoBox = CreateFrame("Frame", nil, view)
    infoBox:SetPoint("TOPRIGHT", view, "TOPRIGHT", -6, -6)
    infoBox:SetFrameLevel(canvas:GetFrameLevel() + 60)
    infoBox:EnableMouse(false)
    local ibg = infoBox:CreateTexture(nil, "BACKGROUND")
    ibg:SetAllPoints()
    ibg:SetColorTexture(0, 0, 0, 0.45)
    info = infoBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 5, -4)
    info:SetJustifyH("LEFT")
    info:SetSpacing(2)
    -- current zoom level (the same number the fade thresholds are written in): top left inside the map
    local zoomBox = CreateFrame("Frame", nil, view)
    zoomBox:SetPoint("TOPLEFT", view, "TOPLEFT", 6, -6)
    zoomBox:SetFrameLevel(canvas:GetFrameLevel() + 60)
    zoomBox:SetSize(60, 16)
    zoomBox:EnableMouse(false)
    local zbg = zoomBox:CreateTexture(nil, "BACKGROUND")
    zbg:SetAllPoints()
    zbg:SetColorTexture(0, 0, 0, 0.45)
    zoomText = zoomBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoomText:SetPoint("CENTER")
    zoomBox:Hide()
    ns.zoomBox = zoomBox

    function ns.infoFit()
        local t = info:GetText()
        if t and t ~= "" then
            infoBox:SetSize((info:GetStringWidth() or 0) + 10, (info:GetStringHeight() or 12) + 8)
            infoBox:Show()
        else
            infoBox:Hide()
        end
    end
    infoBox:Hide()

    view:SetScript("OnMouseWheel", function(_, d)
        -- following or not, the wheel zooms on the pointer: Follow recentres only when the hero moves
        local cx, cy = CursorInView()
        ZoomAt(tcache.ZoomStep(d) * minScale / scale, cx, cy)
    end)
    view:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            local cx, cy = CursorInView()
            drag = { cx = cx, cy = cy, ox = ox, oy = oy }
            dragMoved = false
        end
    end)
    view:SetScript("OnMouseUp", function(_, btn)
        local d = drag
        drag = nil
        -- Ctrl+right click: the game's map pin (Ctrl+left is left to the pins, Questie uses it)
        if IsControlKeyDown() and ns.onCtrlClick and btn == "RightButton" then
            local cx, cy = CursorInView()
            Run(function() ns.onCtrlClick((cx - ox) / scale, (cy - oy) / scale, scale) end)
        end
    end)

    local acc = 0
    local prof = ns.prof
    local function onUpdate(_, dt)
        if ns.paused then drag = nil return end       -- another map is shown in the window (Bridge.lua: Dungeon Journal)
        local T = prof.Time
        if prof.on then prof.frames = prof.frames + 1 end
        if drag then
            local cx, cy = CursorInView()
            if abs(cx - drag.cx) > 4 or abs(cy - drag.cy) > 4 then
                dragMoved = true
            end
            ox, oy = drag.ox + (cx - drag.cx), drag.oy + (cy - drag.cy)
            T("frame: drag", Apply)
        end
        T("frame: hero arrow and Follow", UpdatePlayer)          -- every frame, before the map is drawn: the arrow moves with the map and the hero, no lag
        T("frame: which zones are uncovered", UpdateFocus, dt)
        if dirty then
            T("frame: redraw (all)", Update)
            if prof.on then prof.Add("frame: redraws, all (count is the number)", 0) end
        end
        acc = acc + dt
        if acc > 0.05 then acc = 0; T("frame: pointer readout", UpdateCursor); ns.infoFit(); ns.HeroTitle(title) end
        if ns.zoomAt and GetTime() - ns.zoomAt > 1 then ns.zoomAt = nil; ns.zoomBox:Hide() end
    end
    local errShown
    -- 60 Hz mode (Options): the map's own work at most 60 times a second, whatever the frame rate
    local hz = { acc = 0, pend = 0 }
    view:SetScript("OnUpdate", function(self, dt)
        local cap = db.cap
        if cap then
            local step = 1 / cap
            hz.acc, hz.pend = hz.acc + dt, hz.pend + dt
            if hz.acc < step then return end
            hz.acc = hz.acc - step
            if hz.acc > step then hz.acc = 0 end
            dt, hz.pend = hz.pend, 0
        end
        local t = prof.on and debugprofilestop()
        local ok, e = pcall(onUpdate, self, dt)
        if t then prof.Add("CloudeMap total, map window", debugprofilestop() - t) end
        if not ok and not errShown then errShown = true; Say("update error: " .. tostring(e)) end
    end)

    ns.ChromeFade(frame, bar, barBg, close, grip, tools)
    frame:SetScript("OnSizeChanged", function(_, w, h) OnResize(w, h) end)
    frame:SetScript("OnShow", function()
        if needOverlays and built then BuildOverlays() end
    end)
    if ns.onUI then
        Run(function() ns.onUI({ frame = frame, view = view, grip = grip, tools = tools, followBtn = followBtn, modeBtn = modeBtn,
            barText = barText, info = info, MakeButton = MakeButton }) end)
    end
    uiReady = true
end

local first = { view = true, zoom = 3.73 }
local function RestoreView()
    minScale = min(VW / (bx2 - bx1), VH / (by2 - by1))
    local hadView = db.vc and db.vx
    -- the first time the map opens after the game starts, it starts zoomed in
    if first.view then
        first.view = false
        -- (the round zoom figure nearest to it, so the readout starts on one of the wheel's steps)
        local rel, best = first.zoom / minScale, 1
        for _, z in ipairs(tcache.ZOOMS) do if math.abs(math.log(z / rel)) < math.abs(math.log(best / rel)) then best = z end end
        db.vs = clamp(best * minScale, minScale, MaxScale())
        if not hadView then
            scale = db.vs
            Apply()
            lastPX, lastPY = nil, nil
            if following then GotoPlayer(true) end
            return
        end
    end
    if hadView then
        CenterOn(db.vx, db.vy, db.vs or minScale)
    else
        scale = minScale
        Apply()
    end
    -- following is on at every login: start on the player, keeping the saved zoom if there is one
    -- (if the position is not known yet, the first position update recentres)
    lastPX, lastPY = nil, nil
    if following then GotoPlayer(hadView and true or false) end
end

local function OpenImpl()
    if not uiReady then CreateUI() end
    if not built then Build() end
    frame:Show()
    RestoreView()
end

local function SetShown(on)
    db.shown = on
    if on then
        Run(OpenImpl)
    elseif frame then
        frame:Hide()
    end
end
ns.Toggle = function() SetShown(not (frame and frame:IsShown())) end      -- (Bridge.lua: the minimap button)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Active(list)
    local n = 0
    for i = 1, #list do if list[i].tx then n = n + 1 end end
    return n
end

local function Debug()
    if not built then Run(function() if not uiReady then CreateUI() end Build() end) end
    Say(("%d nodes, %d zones with art | sprites (total/on screen): world+continents+cities %d/%d, zone %d/%d, overlays %d/%d, minimap %d/%d | textures created %d"):format(
        #nodes, #zoneList, #lists.base, Active(lists.base), #lists.zone, Active(lists.zone),
        #lists.over, Active(lists.over), #lists.mini, Active(lists.mini), texCreated))
    Say(("pan bounds %.0f,%.0f to %.0f,%.0f | window %dx%d | mode %s | scale %.3f (min %.3f, max %.0f, relative %.2f)"):format(
        bx1, by1, bx2, by2, db.w, db.h, db.mode == "sat" and "satellite" or "map", scale, minScale, MaxScale(), scale / minScale))
    for _, cn in ipairs(conts) do
        local c = cn.crop
        local m = cn.mini
        local ms = "no tile data"
        if m then
            ms = m.err and ("detail OFF: " .. m.err .. (m.total and (" (" .. m.inb .. "/" .. m.total .. " fit)") or ""))
                  or ("%d tiles placed, %d/%d fit%s, horizontal=%s"):format(
                        m.count or 0, m.inb, m.total, m.swap and ", columns/rows swapped" or "", m.aIsH and "x" or "y")
        end
        Say(("[%d] %s: %d zones, art %s, crop %.0f,%.0f-%.0f,%.0f | %s"):format(
            cn.mapID, cn.name, #cn.zones, cn.files and (cn.cols .. "x" .. cn.rows) or "none",
            c[1], c[2], c[3], c[4], ms))
    end
    Say(("overlay pieces: %d explored (from the game), %d unexplored (from reveal data, %d zones have it)"):format(
        nExplored, nUnexplored, nRevealZones))
    Say(("zone base parchment: %d zones draw their real terrain only, %d have no overlay data and keep the base"):format(
        nBase, nNoBase))
    do
        local names = {}
        for _, n in ipairs(cityList) do names[#names + 1] = ("%s [%d]"):format(n.name, n.mapID) end
        Say("cities with their own map: " .. (#names > 0 and table.concat(names, ", ") or "none found"))
        Say(cityFocus and ("city focus: [%d] %s, fade %.2f, zoom %.2f"):format(cityFocus.mapID, cityFocus.name,
            cityFocus.alpha, cityFocus.zoomA) or "city focus: none")
    end
    if focus then
        local okA, art = pcall(C_Map.GetMapArtID, focus.mapID)
        Say(("focus zone: [%d] %s, art %s, fade %.2f, zoom %.2f"):format(focus.mapID, focus.name,
            tostring(okA and art), focus.alpha, focus.zoomA))
    else
        Say("focus zone: none")
    end
    do
        local bare = {}
        for _, n in ipairs(zoneList) do
            if (n.nExp or 0) + (n.nUnexp or 0) == 0 then bare[#bare + 1] = ("%s [%d]"):format(n.name, n.mapID) end
        end
        if focus then
            local okA, art = pcall(C_Map.GetMapArtID, focus.mapID)
            Say(("focus pieces: %d explored, %d unexplored | reveal data for art %s: %s | rect %.0f,%.0f %.0fx%.0f"):format(
                focus.nExp or 0, focus.nUnexp or 0, tostring(okA and art),
                tostring(okA and ns.reveal and ns.reveal[art or 0] ~= nil), focus.x, focus.y, focus.w, focus.h))
        end
        Say("zone picking by terrain (pointer) / the game's map for the hero (Follow): " .. (terrOK and "terrain answering" or "terrain not answering yet") .. " | hero on " .. (plNode and ("%s [%d]"):format(plNode.name, plNode.mapID) or "unknown"))
        Say("zones without any overlay piece: " .. (#bare > 0 and table.concat(bare, ", ") or "none"))
        local at = ZoneAt((VW / 2 - ox) / scale, (VH / 2 - oy) / scale)
        Say("zone at the middle of the view: " .. (at and ("%s [%d], pieces %d+%d, fade %.2f, zoom %.2f"):format(at.name, at.mapID,
            at.nExp or 0, at.nUnexp or 0, at.alpha or 0, at.zoomA or 0) or "none"))
    end
    if ns.pins then
        local parts = {}
        for _, id in ipairs(ns.pins.order) do
            local c = ns.pins.cats[id]
            parts[#parts + 1] = ("%s %d%s"):format(id, #c.pins, ns.pins.IsEnabled(id) and "" or " (off)")
        end
        Say(("pins: %s | drawn now %d"):format(table.concat(parts, ", "), pinsShown))
        if ns.bridge then Say(ns.bridge.Status()) end
    end
    if frame then
        local l, b, w, h = frame:GetRect()
        Say(("window shown=%s rect=%s,%s %sx%s"):format(
            tostring(frame:IsShown()), tostring(l and floor(l)), tostring(b and floor(b)),
            tostring(w and floor(w)), tostring(h and floor(h))))
    end
    for _, l in ipairs(PlayerReport()) do Say(l) end
end

SLASH_CLOUDEMAP1 = "/cmap"
SLASH_CLOUDEMAP2 = "/cloudemap"
SlashCmdList.CLOUDEMAP = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    if msg == "debug" or msg == "status" then
        ns.capture = {}
        Debug()
        local text = table.concat(ns.capture, "\n")
        ns.capture = nil
        if ns.ShowCopy then ns.ShowCopy(text) end
    elseif msg == "fade" then
        -- 2 s to put the pointer where it should be, then 3 s of every map update, into the copy window
        local t = GetTime()
        ns.fadeLog = { from = t + 2, till = t + 5 }
        Say("fade log: in 2 seconds, for 3 seconds. Move the pointer onto a zone that is not uncovered.")
    elseif msg == "prof" then
        -- first time: start measuring; next time: the report (in the copy window), and stop
        local prof = ns.prof
        if not prof.on then
            prof.Start()
            Say("profiling: on. Play as usual (move, pan, zoom), then /cmap prof again for the report.")
        else
            prof.on = false
            if ns.ShowCopy then ns.ShowCopy(table.concat(prof.Report(), "\n")) end
            Say("profiling: off")
        end
    elseif cmd == "mode" or cmd == "detail" or cmd == "sat" or cmd == "map" then
        Run(function()
            if not uiReady then OpenImpl() end
            local want
            if cmd == "sat" or arg:find("^sat") then want = "sat"
            elseif cmd == "map" or arg:find("^map") or arg:find("^parch") then want = "map"
            else want = (db.mode == "sat") and "map" or "sat" end
            SetMode(want)
            Say("mode: " .. (db.mode == "sat" and "satellite" or "map"))
        end)
    elseif cmd == "quests" then
        SetQuestMode(QM.label[arg] and arg or (QM.next[db.blobMode] or "tracked"))
        Say((QM.tip[db.blobMode] or "") .. " (/cmap quests dim | tracked, or Options)")
    elseif msg == "follow" then
        Run(function() if not uiReady then OpenImpl() end SetFollow(not following) end)
    elseif msg == "reset" then
        db.pos, db.w, db.h, db.vc = nil, DEF_W, DEF_H, nil
        if frame then
            frame:ClearAllPoints(); frame:SetPoint("CENTER"); frame:SetSize(DEF_W, DEF_H)
        end
        SetShown(true)
        Say("window reset")
    elseif msg == "me" then
        Run(function() if not uiReady then OpenImpl() end SetFollow(true) end)      -- back to the hero, following
    elseif msg == "where" then
        if ns.probe then
            local cx, cy = (VW / 2 - ox) / scale, (VH / 2 - oy) / scale
            ns.capture = {}
            ns.probe(Say, cx, cy)
            local text = table.concat(ns.capture, "\n")
            ns.capture = nil
            if ns.ShowCopy then ns.ShowCopy(text) end
        end
    elseif msg == "help" or msg == "?" then
        for _, l in ipairs({
            "commands (/cmap or /cloudemap):",
            "  /cmap - show or hide the map    show / hide",
            "  me - back to your hero, Follow on    follow - Follow on or off",
            "  map / sat / mode - parchment, satellite, or switch",
            "  quests dim / tracked - quest areas: all (others dimmed) or tracked only",
            "  reset - window back to the middle, default size",
            "  status - status report    where - what is under the middle of the view",
            "  prof - profiler on / report    fade - zone uncovering log",
        }) do Say(l) end
    elseif msg == "show" then
        SetShown(true)
    elseif msg == "hide" then
        SetShown(false)
    else
        SetShown(not (frame and frame:IsShown()))
    end
end

---------------------------------------------------------------------------
-- Events: open at login (unless the window was closed last time)
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "MAP_EXPLORATION_UPDATED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if db and db.shown then Run(OpenImpl) end
    else   -- exploration changed or a loading screen ended: overlays need a refresh
        needOverlays = true
        if built and frame and frame:IsShown() then Run(BuildOverlays) end
    end
end)
