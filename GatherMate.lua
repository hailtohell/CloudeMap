-- CloudeMap | GatherMate2: its gathering nodes.

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

---------------------------------------------------------------------------
-- GatherMate2: its nodes for the zones drawn in detail (a zone can hold thousands, so never
-- the whole world at once). One category per kind of node.
---------------------------------------------------------------------------
local gmKey
local function GatherPins(shown)
    local GM = _G.GatherMate2
    if not (type(GM) == "table" and type(GM.GetNodesForZone) == "function" and type(GM.db_types) == "table") then return end
    local parts = { tostring(floor(Now() / 20)) }
    for _, n in ipairs(shown) do parts[#parts + 1] = n.mapID end
    for _, t in ipairs(GM.db_types) do
        local id = "gm:" .. t
        if not P.cats[id] then
            P.RegisterCategory(id, { name = "GatherMate: " .. t, addon = "GatherMate", bulk = true, order = 400, minScale = 2.0, size = 13, scaleKey = "gmSize" })
        end
        parts[#parts + 1] = P.IsEnabled(id) and "1" or "0"
    end
    local key = table.concat(parts, ":")
    if key == gmKey then return end
    gmKey = key
    local filter = GM.db and GM.db.profile and GM.db.profile.filter
    local steps = {}
    for _, t in ipairs(GM.db_types) do
        local id = "gm:" .. t
        if P.IsEnabled(id) then steps[#steps + 1] = function()        -- one kind of node per frame
            local list = {}
            local tex = type(GM.nodeTextures) == "table" and GM.nodeTextures[t]
            local f = type(filter) == "table" and filter[t]
            for _, n in ipairs(shown) do
                pcall(function()
                    for coord, nodeID in GM:GetNodesForZone(n.mapID, t, true) do
                        if #list >= 1500 then break end
                        if not (type(f) == "table" and f[nodeID] == false) then
                            local x, y
                            if GM.DecodeLoc then x, y = GM:DecodeLoc(coord)
                            else x, y = floor(coord / 1000000) / 10000, floor(coord % 1000000 / 100) / 10000 end
                            if type(x) == "number" and type(y) == "number" then
                                local name = GM.GetNameForNode and GM:GetNameForNode(t, nodeID)
                                list[#list + 1] = { map = n.mapID, x = x, y = y, texture = type(tex) == "table" and tex[nodeID] or nil,
                                    name = type(name) == "string" and name or t, color = (type(tex) ~= "table" or not tex[nodeID]) and { 0.4, 1, 0.4, 1 } or nil }
                            end
                        end
                    end
                end)
            end
            local c = P.cats[id]
            if #list > 0 or (c and #c.pins > 0) then P.SetPins(id, list) end
        end end
    end
    Spread("gm", steps)
    B.gm = true
    return true         -- (read again: the caller spreads what else is heavy over the next frames)
end
B.GatherPins = GatherPins
