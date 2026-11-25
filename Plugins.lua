-- CloudeMap | the plugin interface (CloudeMap.Map).

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

---------------------------------------------------------------------------
-- Plugins: what a separate addon needs to draw on this map (CloudeMap_ShortestPath is one), as
-- CloudeMap.Map. Pins go through the registry as for any addon (CloudeMap.RegisterCategory,
-- SetPins); this adds the map itself. Positions on the canvas are CloudeMap's own units: a view
-- point is ox + cx * scale, oy + cy * scale from the view's top left, y down.
--   Map.version                          1
--   Map.View()                           -> view, layer, scale, level: the map frame, the layer the
--                                           pins ride on (moves with the map: anchor to its
--                                           TOPLEFT at cx * scale, -cy * scale), the zoom, and the
--                                           frame level just under the pins (nil until built)
--   Map.ToCanvas(uiMapID, x, y)          -> cx, cy, mapID, x, y: a place (lifted onto a map
--                                           CloudeMap draws when it is a cave or micro map)
--   Map.WorldToCanvas(continent, wx, wy) -> the same, from a world position
--   Map.MapAt(cx, cy)                    -> uiMapID, x, y: the zone or city at a canvas point
--   Map.Hero()                           -> cx, cy of the player, or nil
--   Map.OnRedraw(fn)                     fn(scale) after every full redraw (zoom, zone change)
--   Map.OnClick(fn)                      fn(button, cx, cy, shift, ctrl, alt) on a click (not a
--                                        drag); return true to say it was handled
--   Map.OnToggle(fn)                     fn(categoryID, on) when a pin category is switched
--   Map.Status(fn)                       fn() -> a line for /cmap status
---------------------------------------------------------------------------
do
    local M = { version = 1 }
    local redraw, clicks, toggles, status = {}, {}, {}, {}
    B.plugins = { redraw = redraw, clicks = clicks, status = status }
    local function Known(map, x, y)
        for _ = 1, 6 do
            if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return end
            local n = ns.NodeOf and ns.NodeOf(map)
            if n and n.w and n.w > 0 then return n.x + x * n.w, n.y + y * n.h, map, x, y end
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
            local parent = info and info.parentMapID
            if not parent or parent == 0 or not C_Map.GetMapRectOnMap then return end
            local ok, x1, x2, y1, y2 = pcall(C_Map.GetMapRectOnMap, map, parent)
            if not (ok and x1 and x2 and y1 and y2) then return end
            map, x, y = parent, x1 + x * (x2 - x1), y1 + y * (y2 - y1)
        end
    end
    M.ToCanvas = Known
    function M.WorldToCanvas(c, wx, wy)
        if not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
        local ok, map, pos = pcall(C_Map.GetMapPosFromWorldPos, c, CreateVector2D(wx, wy))
        if not (ok and map and pos) then return end
        local px, py = pos.x, pos.y
        if not px and pos.GetXY then px, py = pos:GetXY() end
        if type(px) ~= "number" or Secret(px) then return end
        return Known(map, px, py)
    end
    function M.MapAt(cx, cy)
        local n = ns.PickAt and ns.PickAt(cx, cy)
        if not (n and n.mapID and n.w and n.w > 0) then return end
        local x, y = (cx - n.x) / n.w, (cy - n.y) / n.h
        if x < 0 or x > 1 or y < 0 or y > 1 then return end
        return n.mapID, x, y
    end
    function M.Hero()
        if ns.HeroCanvas then
            local x, y = ns.HeroCanvas()
            return x, y
        end
    end
    function M.View()
        local v = B.viewState
        if not (v and v.view and v.scale and ns.pinLayer) then return end
        local pf = ns.pinsFrame
        return v.view, ns.pinLayer, v.scale, pf and pf:GetFrameLevel() or (v.view:GetFrameLevel() + 5)
    end
    local function Add(list) return function(fn) if type(fn) == "function" then list[#list + 1] = fn end end end
    M.OnRedraw, M.OnClick, M.OnToggle, M.Status = Add(redraw), Add(clicks), Add(toggles), Add(status)
    P.Map = M                       -- (CloudeMap.Map: the public table reads the registry)

    -- called by ns.afterUpdate and the map's clicks
    function B.PluginRedraw(scale)
        for _, fn in ipairs(redraw) do pcall(fn, scale) end
    end
    function ns.onMapClick(btn, cx, cy, shift, ctrl, alt)
        for _, fn in ipairs(clicks) do
            local ok, done = pcall(fn, btn, cx, cy, shift, ctrl, alt)
            if ok and done then return true end
        end
    end
    function B.PluginStatus()
        local out = {}
        for _, fn in ipairs(status) do
            local ok, line = pcall(fn)
            if ok and type(line) == "string" then out[#out + 1] = line .. " | " end
        end
        return table.concat(out)
    end
    local SetEnabled = P.SetEnabled
    function P.SetEnabled(id, on)
        SetEnabled(id, on)
        for _, fn in ipairs(toggles) do pcall(fn, id, on) end
    end
end
