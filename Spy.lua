-- CloudeMap | Spy: enemy players, its fights and its users' reports.

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

---------------------------------------------------------------------------
-- Spy, read from its own data rather than from the icons it gives HereBeDragons (those stay
-- registered after Spy hides them, so they were drawn long after they were gone, and they
-- landed under "Other addons"):
--   spy        the enemy players in its Nearby list, where it last saw them: a red dot like the
--              party's (kill on sight brighter and larger, no longer active dimmed)
--   spyfights  its fights (Forever's combat map): its skull, green a win, red a loss, yellow a
--              probable win, as its options choose
--   spynotes   enemies other Spy users reported, while Spy shows them (its faction icon)
---------------------------------------------------------------------------
local spySig = {}
local HbdEnter, HbdLeave = B.HbdEnter, B.HbdLeave        -- (Bridge.lua: a pin's own frame answers the pointer)
local SPY_DOT = { "WhiteCircle-RaidBlips", "WhiteDotCircle-RaidBlips" }
local SPY_FIGHT = { W = { 0.25, 1, 0.25, 1 }, L = { 1, 0.25, 0.25, 1 }, P = { 1, 0.85, 0.2, 1 } }

-- Spy's own icons: left out of the HereBeDragons reading (RebuildHBD), drawn from its data here
function B.SpyIcon(ref, icon)
    local S = _G.Spy
    if type(S) ~= "table" then return false end
    if ref == S or (ref ~= nil and ref == rawget(S, "EncounterRef")) then return true end
    local notes = rawget(S, "MapNoteList")
    if type(notes) == "table" and ref == _G.WorldMapFrame then
        for _, n in pairs(notes) do if type(n) == "table" and n.worldIcon == icon then return true end end
    end
    return false
end

-- Where we last saw each enemy, exactly. Spy keeps the hero's position only from the first
-- sighting, cut down to whole percent; its Active list gets a new time stamp every time it sees
-- the enemy again (Forever's Spy scans the visible units once a second), so the hero's position
-- is taken here whenever a stamp changes. Twice a second, map open or not; nothing is read while
-- nobody is active.
local spySeen = {}      -- name -> { stamp, map, x, y }
function B.SpySample()
    local S = _G.Spy
    local act = type(S) == "table" and rawget(S, "ActiveList")
    if type(act) ~= "table" or next(act) == nil then return end
    local map, x, y
    for name, stamp in pairs(act) do
        local e = spySeen[name]
        if not e or e[1] ~= stamp then
            if not map then
                local m = C_Map.GetBestMapForUnit("player")
                if not m or Secret(m) then return end
                local pos = C_Map.GetPlayerMapPosition(m, "player")
                if not pos then return end
                local px, py = pos.x, pos.y
                if not px and pos.GetXY then px, py = pos:GetXY() end
                if not (px and py) or Secret(px) or Secret(py) or (px == 0 and py == 0) then return end
                map, x, y = m, px, py
            end
            if not e then e = {}; spySeen[name] = e; B.spyDue = true end      -- a new enemy: drawn at the next tick
            e[1], e[2], e[3], e[4] = stamp, map, x, y
        end
    end
end

local spyPin = {}       -- name -> its pin, kept between readings
local function SpySet(id, list, sig)
    table.sort(sig)
    local s = table.concat(sig, "|")
    if s ~= spySig[id] then
        spySig[id] = s
        P.SetPins(id, list)
        return true
    end
end

local function SpyPins(known)
    local S, DB = _G.Spy, _G.SpyPerCharDB
    if not (type(S) == "table" and type(S.NearbyList) == "table" and type(DB) == "table" and type(DB.PlayerData) == "table") then return end
    if not P.cats.spy then
        P.RegisterCategory("spy", { name = "Spy: enemy players", addon = "Spy", order = 420, minScale = 0.5, size = 16, always = true,
            atlas = SPY_DOT, color = { 1, 0.15, 0.15, 1 } })
        P.RegisterCategory("spyfights", { name = "Spy: fights", addon = "Spy", order = 421, minScale = 0.5, size = 14,
            texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" })
        P.RegisterCategory("spynotes", { name = "Spy: enemies reported by others", addon = "Spy", order = 422, minScale = 0.5, size = 18,
            texture = "Interface\\WorldStateFrame\\" .. tostring(rawget(S, "EnemyFactionName") or "Horde") .. "Icon" })
    end

    if P.IsEnabled("spy") then
        -- the pins are kept from one reading to the next: an enemy who only moved (we kept seeing
        -- him while walking) is moved in place, without rebuilding every pin of the map
        local list, sig, moved = {}, {}, false
        for name in pairs(spySeen) do if S.NearbyList[name] == nil then spySeen[name] = nil end end
        for name in pairs(spyPin) do if S.NearbyList[name] == nil then spyPin[name] = nil end end
        for name, ts in pairs(S.NearbyList) do
            local d = DB.PlayerData[name]
            -- our own exact sighting first, Spy's rounded one when we have none (seen by another user)
            local e = spySeen[name]
            local map, x, y
            if e then map, x, y = e[2], e[3], e[4]
            elseif type(d) == "table" then map, x, y = d.mapID, d.mapX, d.mapY end
            if type(d) == "table" and not (type(DB.IgnoreData) == "table" and DB.IgnoreData[name])
                and known[map] and type(x) == "number" and type(y) == "number" and (x ~= 0 or y ~= 0) then
                local kos = type(DB.KOSData) == "table" and DB.KOSData[name] ~= nil
                local active = type(S.ActiveList) == "table" and S.ActiveList[name] ~= nil
                local state = tostring(name) .. "@" .. map .. (kos and "k" or "") .. (active and "a" or "")
                    .. tostring(d.level) .. tostring(d.class) .. tostring(d.guild)
                local p = spyPin[name]
                if not p or p.state ~= state then
                    local lines = { ("Level %s %s %s"):format((type(d.level) == "number" and d.level > 0) and tostring(d.level) or "?", tostring(d.race or ""), tostring(d.class or "")) }
                    if d.guild and d.guild ~= "" then lines[#lines + 1] = "<" .. tostring(d.guild) .. ">" end
                    if kos then lines[#lines + 1] = "|cffff2020Kill on sight|r" end
                    if not active then lines[#lines + 1] = "|cff999999no longer active|r" end
                    lines[#lines + 1] = "|cff999999where you were when you last saw them|r"
                    -- a little up and to the right of the point: it is where the hero stood, so the
                    -- dot shows beside the hero's arrow (32 px) at once instead of under it
                    p = { map = map, x = x, y = y, level = 30, state = state, dx = 13, dy = 13,
                        name = (kos and "|cffff2020" or "|cffff8080") .. tostring(name) .. "|r", text = lines,
                        atlas = kos and "WhiteDotCircle-RaidBlips" or nil, size = kos and 20 or 16,
                        color = kos and { 1, 0, 0, 1 } or (active and { 1, 0.15, 0.15, 1 } or { 0.65, 0.2, 0.2, 0.75 }) }
                    spyPin[name] = p
                elseif p.x ~= x or p.y ~= y then
                    p.x, p.y, moved = x, y, true
                end
                list[#list + 1] = p
                sig[#sig + 1] = state
            end
        end
        if not SpySet("spy", list, sig) and moved and P.onChange then P.onChange() end
    end

    -- the fights Spy put on the map last (it keeps the entry on each icon it shows)
    local icons = rawget(S, "EncounterIcons")
    if P.IsEnabled("spyfights") and type(icons) == "table" then
        local list, sig = {}, {}
        for i, icon in ipairs(icons) do
            local e = type(icon) == "table" and rawget(icon, "entry")
            if type(e) == "table" and known[e.m] and type(e.x) == "number" and type(e.y) == "number" then
                list[#list + 1] = { map = e.m, x = e.x, y = e.y, src = icon, onEnter = HbdEnter, onLeave = HbdLeave,
                    name = tostring(e.n), color = SPY_FIGHT[e.r] or SPY_FIGHT.W }
                sig[#sig + 1] = i .. tostring(e.n) .. tostring(e.t) .. tostring(e.r)
            end
        end
        SpySet("spyfights", list, sig)
    end

    local notes = rawget(S, "MapNoteList")
    if P.IsEnabled("spynotes") and type(notes) == "table" then
        local list, sig = {}, {}
        for i, n in pairs(notes) do
            if type(n) == "table" and n.displayed and known[n.mapID] and type(n.mapX) == "number" and type(n.mapY) == "number" then
                list[#list + 1] = { map = n.mapID, x = n.mapX, y = n.mapY, level = 30, src = n.worldIcon, onEnter = HbdEnter, onLeave = HbdLeave,
                    name = "Enemy reported by another Spy user" }
                sig[#sig + 1] = tostring(i) .. floor(n.mapX * 1000) .. floor(n.mapY * 1000)
            end
        end
        SpySet("spynotes", list, sig)
    end
end
B.SpyPins = SpyPins
