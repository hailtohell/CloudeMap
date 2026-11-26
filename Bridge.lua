-- CloudeMap | bridge: other addons' map icons, drawn on CloudeMap.
--
-- Two sources, each addon becoming a category of its own in the Pins menu:
--
--   * HereBeDragons-Pins: the library most addons put their world map icons through
--     (Questie, TomTom, RXPGuides, Spy, gatherers ...). Every copy of it is read, the
--     one inside Questie too. The icon's look is copied from the addon's own frame, and
--     its tooltip and clicks are handed back to that frame.
--   * HandyNotes: every plugin's notes, asked for zone by zone, with the plugin's own
--     tooltip and click handling.
--
-- Nothing here changes what those addons do on the game's own map.

local ADDON, ns = ...
local P = ns.pins
if not P then return end

local B = {}
ns.bridge = B

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- Heavy reads in steps, one per frame (a zone change would otherwise do them all in one frame).
-- A newer run of the same name drops what is left of the older one.
local spreadGen = {}
local function Spread(name, steps)
    local gen = (spreadGen[name] or 0) + 1
    spreadGen[name] = gen
    local i = 0
    local function Next()
        if spreadGen[name] ~= gen then return end
        i = i + 1
        local f = steps[i]
        if not f then return end
        pcall(f)
        if steps[i + 1] then
            if C_Timer and C_Timer.After then C_Timer.After(0, Next) else Next() end
        end
    end
    Next()
end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function Now() return GetTime and GetTime() or 0 end

local function Secret(v) return issecretvalue and issecretvalue(v) end
-- shared with the other files of the bridge (QuestAreas.lua, Spy.lua, DungeonJournal.lua, ...)
B.Spread, B.clamp, B.Now, B.Secret = Spread, clamp, Now, Secret

local ORDER_HBD, ORDER_HN = 200, 300
local MAX_PER_SOURCE = 4000

---------------------------------------------------------------------------
-- HereBeDragons-Pins
---------------------------------------------------------------------------
local libs = {}                                     -- name -> the library (a copy of HereBeDragons-Pins)
local hbdDirty, hbdLast, hbdCats = true, 0, {}
local KNOWN_GLOBALS = { "Questie", "TomTom", "RXP", "RXPGuides", "Spy", "GatherMate2", "GatherLite", "Routes", "Gatherer", "ZGV" }

-- a cheap fingerprint of a list of pins (where each is, which picture, which name): a read that
-- comes out the same is not handed on, so it costs no redraw
function B.PinsSig(list)
    local h = #list
    for i = 1, #list do
        local p = list[i]
        local pic = p.atlas or p.texture
        h = (h * 31 + (p.map or 0) * 7 + floor((p.x or 0) * 100000) * 13 + floor((p.y or 0) * 100000) * 17
            + (type(pic) == "number" and pic or (type(pic) == "string" and #pic * 101 + pic:byte(-1) or 0))
            + (type(p.name) == "string" and #p.name * 3 or 0)) % 2147483647
    end
    return h
end
function B.SetIfChanged(id, list)
    local c = P.cats[id]
    local sig = B.PinsSig(list)
    if c and c.srcSig == sig then return end
    if c or #list > 0 then
        P.SetPins(id, list)
        P.cats[id].srcSig = sig
    end
end

-- a copy of the library, noted to be read (nothing of it is hooked or changed: its pin list is
-- read every few seconds, RebuildHBD)
local function HookLib(name, lib)
    if name:find("Questie", 1, true) then return end     -- (read from Questie's own frames, below)
    if libs[name] or type(lib) ~= "table" or type(lib.worldmapPinRegistry) ~= "table" then return end
    libs[name] = lib
    hbdDirty = true
end

local function FindLibs()
    local stub = _G.LibStub
    local list = type(stub) == "table" and rawget(stub, "libs")
    if type(list) == "table" then
        for name, lib in pairs(list) do
            if type(name) == "string" and name:find("HereBeDragons", 1, true) and name:find("Pins", 1, true) then
                HookLib(name, lib)
            end
        end
    end
    -- Questie 12.8 and later keeps its copy as one of its own modules
    local loader = _G.QuestieLoader
    local modules = type(loader) == "table" and rawget(loader, "_modules")
    local qpins = type(modules) == "table" and rawget(modules, "HBDPins")
    if type(qpins) == "table" then HookLib("Questie's HBDPins", qpins) end
end

-- who an icon set belongs to: the addon's name where it can be told
local function RefName(ref, libName)
    if type(ref) == "string" then return ref end
    if type(ref) == "table" then
        for _, g in ipairs(KNOWN_GLOBALS) do
            if _G[g] == ref then return g == "RXP" and "RXPGuides" or g end
        end
        local ok, n = pcall(function() return rawget(ref, "name") or rawget(ref, "moduleName") end)
        if ok and type(n) == "string" and n ~= "" then return n end
        local ok2, s = pcall(tostring, ref)
        if ok2 and type(s) == "string" and not s:find("^table:") then return s end
    end
    if libName:find("Questie", 1, true) then return "Questie" end
    if libName:find("ZGV", 1, true) then return "Zygor" end
    return "Other addons"
end

-- the texture an addon's icon frame shows
local function Region(icon)
    for _, k in ipairs({ "texture", "icon", "Texture", "Icon", "tex" }) do
        local t = icon[k]
        if type(t) == "table" and type(t.GetTexture) == "function" then return t end
    end
    if icon.GetRegions then
        for _, r in ipairs({ icon:GetRegions() }) do
            if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture" then return r end
        end
    end
end

local function HbdEnter(btn, pin)
    local f = pin.src
    local s = f and f.GetScript and f:GetScript("OnEnter")
    if s then
        pcall(s, f)
        -- the addon anchored its tooltip to its own (hidden) frame: bring it to ours
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == f and GameTooltip:IsShown() then
            pcall(function()
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("BOTTOMLEFT", btn, "TOPRIGHT", 2, 2)
            end)
        end
    elseif GameTooltip then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(pin.name or "")
        GameTooltip:Show()
    end
end
B.HbdEnter = HbdEnter
local function HbdLeave(_, pin)
    local f = pin.src
    local s = f and f.GetScript and f:GetScript("OnLeave")
    if s then pcall(s, f) end
end
B.HbdLeave = HbdLeave
local function HbdClick(pin, button)
    local f = pin.src
    if not (f and f.GetScript) then return end
    local s = f:GetScript("OnClick")
    if s then pcall(s, f, button, false) return end
    s = f:GetScript("OnMouseUp")
    if s then pcall(s, f, button) end
end

-- data: the library's record of the icon (worldmapPins[icon]: its world position, instance and
-- map); the registry itself only says which icons an addon has
local function IconPin(icon, data, known, hbd)
    if type(icon) ~= "table" or type(data) ~= "table" then return end
    if icon.type == "line" or icon.hidden or icon.miniMapIcon then return end     -- (Questie: path lines, hidden ones)
    local mapID, x, y
    if type(data.mapX) == "number" and type(data.mapY) == "number" then
        mapID, x, y = data.uiMapID, data.mapX, data.mapY
    end
    -- Questie keeps the map point on the icon, in percent
    if not x and type(icon.UiMapID) == "number" and type(icon.x) == "number" and type(icon.y) == "number" then
        mapID, x, y = icon.UiMapID, icon.x / 100, icon.y / 100
    end
    -- last resort: back from the library's world position
    if not x and hbd and type(data.uiMapID) == "number" and type(data.x) == "number" and type(data.y) == "number"
        and type(hbd.GetZoneCoordinatesFromWorld) == "function" then
        local ok, zx, zy = pcall(hbd.GetZoneCoordinatesFromWorld, hbd, data.x, data.y, data.uiMapID, true)
        if ok and type(zx) == "number" and type(zy) == "number" then mapID, x, y = data.uiMapID, zx, zy end
    end
    if not (x and y and mapID and known[mapID]) then return end

    local pin = { map = mapID, x = x, y = y, src = icon, onEnter = HbdEnter, onLeave = HbdLeave, onClick = HbdClick }
    local tex = Region(icon)
    if tex then
        local atlas = tex.GetAtlas and tex:GetAtlas()
        if type(atlas) == "string" and atlas ~= "" then
            pin.atlas = atlas
        else
            local file = tex:GetTexture()
            if file then
                pin.texture = file
                local c = { tex:GetTexCoord() }
                if #c == 8 then pin.texCoord = c end
            end
        end
        local r, g, b, al = tex:GetVertexColor()
        if type(r) == "number" and (r < 0.99 or g < 0.99 or b < 0.99) then pin.color = { r, g, b, al or 1 } end
    end
    local w = icon.GetWidth and icon:GetWidth() or 0
    local sc = icon.GetScale and icon:GetScale() or 1
    if type(w) == "number" and w > 0 and type(sc) == "number" then pin.size = clamp(w * sc, 12, 26) end
    return pin
end

local function RebuildHBD(known)
    hbdDirty, hbdLast = false, Now()
    local lists = {}
    local stub = _G.LibStub
    local hbd
    if type(stub) == "table" then
        local ok, l = pcall(stub, "HereBeDragons-2.0", true)
        if ok and type(l) == "table" then hbd = l end
    end
    for libName, lib in pairs(libs) do
        for ref, icons in pairs(lib.worldmapPinRegistry) do
            -- Spy's own sets are drawn from its data (SpyPins); its map notes share WorldMapFrame
            -- as their key with other addons, so those are left out one by one below
            local S = _G.Spy
            if type(icons) == "table" and not (type(S) == "table" and (ref == S or ref == rawget(S, "EncounterRef"))) then
                local name = RefName(ref, libName)
                local id = "addon:" .. name
                local list = lists[id]
                if not list then
                    list = {}
                    lists[id] = list
                    if not P.cats[id] then
                        P.RegisterCategory(id, { name = name, addon = name, order = ORDER_HBD, minScale = 0.8, size = 18, color = { 1, 1, 1, 1 } })
                    end
                end
                if P.IsEnabled(id) then
                    local records = type(lib.worldmapPins) == "table" and lib.worldmapPins or {}
                    for icon, data in pairs(icons) do
                        if #list >= MAX_PER_SOURCE then break end
                        if type(data) ~= "table" then data = records[icon] end     -- (version 17: the registry holds true)
                        local ok, pin = true, nil
                        if not (B.SpyIcon and B.SpyIcon(ref, icon)) then ok, pin = pcall(IconPin, icon, data, known, hbd) end
                        if ok and pin then list[#list + 1] = pin end
                    end
                end
            end
        end
    end
    for id, list in pairs(lists) do
        local c = P.cats[id]
        if P.IsEnabled(id) and (#list > 0 or (c and #c.pins > 0)) then B.SetIfChanged(id, list) end
        hbdCats[id] = true
    end
    for id in pairs(hbdCats) do
        if not lists[id] and P.cats[id] and #P.cats[id].pins > 0 then B.SetIfChanged(id, {}) end
    end
end

---------------------------------------------------------------------------
-- HandyNotes
---------------------------------------------------------------------------
local hnDirty, hnLast, hnCats = true, 0, {}

local function HandyNotes()
    local HN = _G.HandyNotes
    if type(HN) == "table" and type(HN.plugins) == "table" then return HN end
end

local function HnEnter(btn, pin)
    local h = pin.handler
    if type(h.OnEnter) == "function" then pcall(h.OnEnter, btn, pin.hnMap, pin.coord) end
end
local function HnLeave(btn, pin)
    local h = pin.handler
    if type(h.OnLeave) == "function" then pcall(h.OnLeave, btn, pin.hnMap, pin.coord) end
end
local function HnClick(pin, button, btn)
    local h = pin.handler
    if type(h.OnClick) == "function" then
        pcall(h.OnClick, btn, button, true, pin.hnMap, pin.coord)
        pcall(h.OnClick, btn, button, false, pin.hnMap, pin.coord)
    end
end

local function HnNodes(handler, mapID, known, list, seen)
    local iter, state, value
    if type(handler.GetNodes2) == "function" then
        iter, state, value = handler:GetNodes2(mapID, false)
    elseif type(handler.GetNodes) == "function" then
        iter, state, value = handler:GetNodes(mapID, false, 0)
    end
    if type(iter) ~= "function" then return end
    local n = 0
    for coord, map2, icon, scale, alpha in iter, state, value do
        n = n + 1
        if n > 2000 or #list >= MAX_PER_SOURCE then break end
        local m = type(map2) == "number" and map2 or mapID
        if type(coord) == "number" and known[m] then
            local key = m * 100000000 + coord
            if not seen[key] then
                seen[key] = true
                local pin = { map = m, x = floor(coord / 10000) / 10000, y = (coord % 10000) / 10000,
                              handler = handler, hnMap = m, coord = coord,
                              onEnter = HnEnter, onLeave = HnLeave, onClick = HnClick }
                if type(icon) == "table" then
                    if type(icon.atlas) == "string" then pin.atlas = icon.atlas end
                    pin.texture = icon.icon
                    if icon.tCoordLeft then
                        pin.texCoord = { icon.tCoordLeft, icon.tCoordRight or 1, icon.tCoordTop or 0, icon.tCoordBottom or 1 }
                    end
                    if icon.r then pin.color = { icon.r, icon.g or 1, icon.b or 1, icon.a or 1 } end
                elseif icon ~= nil then
                    pin.texture = icon
                end
                pin.size = clamp(14 * (type(scale) == "number" and scale or 1), 10, 26)
                if type(alpha) == "number" and alpha < 1 then
                    local c = pin.color or { 1, 1, 1, 1 }
                    pin.color = { c[1], c[2], c[3], max(alpha, 0.35) }
                end
                list[#list + 1] = pin
            end
        end
    end
end

-- The zones HandyNotes is read for: those drawn in detail and the ones touching them (so the next
-- zone over is ready when the map moves on), not the whole world. The key changes with them.
local function HNZones()
    local shown, all = ns.shownZones, ns.zoneList
    local ids, set = {}, {}
    if type(shown) ~= "table" or type(all) ~= "table" then return ids, "" end
    for _, z in ipairs(all) do
        for _, n in ipairs(shown) do
            local mx, my = n.w * 0.15, n.h * 0.15
            if z.x < n.x + n.w + mx and z.x + z.w > n.x - mx and z.y < n.y + n.h + my and z.y + z.h > n.y - my then
                if not set[z.mapID] then set[z.mapID] = true; ids[#ids + 1] = z.mapID end
                break
            end
        end
    end
    table.sort(ids)
    return ids, table.concat(ids, ",")
end

local function RebuildHN(known, zones)
    hnDirty, hnLast = false, Now()
    local HN = HandyNotes()
    if not HN then return end
    local on = true
    if type(HN.IsEnabled) == "function" then
        local ok, v = pcall(HN.IsEnabled, HN)
        if ok then on = v and true or false end
    end
    local enabledPlugins = HN.db and HN.db.profile and HN.db.profile.enabledPlugins
    local live, steps = {}, {}
    for name, handler in pairs(HN.plugins) do
        if type(name) == "string" and type(handler) == "table" then
            local id = "hn:" .. name
            live[id] = true
            hnCats[id] = true
            if not P.cats[id] then
                P.RegisterCategory(id, { name = "HandyNotes: " .. name, addon = "HandyNotes", order = ORDER_HN, minScale = 0.8, size = 14, color = { 1, 1, 1, 1 } })
            end
            steps[#steps + 1] = function()          -- one plugin per frame
                local list = {}
                if on and P.IsEnabled(id) and not (type(enabledPlugins) == "table" and enabledPlugins[name] == false) then
                    local seen = {}
                    for _, mapID in ipairs(zones) do
                        pcall(HnNodes, handler, mapID, known, list, seen)
                    end
                end
                local c = P.cats[id]
                if P.IsEnabled(id) and (#list > 0 or (c and #c.pins > 0)) then B.SetIfChanged(id, list) end
            end
        end
    end
    steps[#steps + 1] = function()
        for id in pairs(hnCats) do
            if not live[id] and P.cats[id] and #P.cats[id].pins > 0 then B.SetIfChanged(id, {}) end
        end
    end
    Spread("hn", steps)
end


---------------------------------------------------------------------------
-- Questie: its icon frames, as Carbonite reads them (QuestieMap.questIdFrames for quests,
-- manualFrames for townsfolk). Each frame carries its map (UiMapID), place (x, y in percent),
-- texture and data, whether or not the game's own map is open.
---------------------------------------------------------------------------
local qLast, qDirty = 0, true
local QTYPES = { complete = "questie", monster = "questie", item = "questie", object = "questie", event = "questie",
                 available = "questie_avail" }

local function QuestieMods()
    local loader = _G.QuestieLoader
    if not (_G.Questie and loader and loader.ImportModule) then return end
    local ok, qm = pcall(loader.ImportModule, loader, "QuestieMap")
    if not (ok and type(qm) == "table") then return end
    local _, lib = pcall(loader.ImportModule, loader, "QuestieLib")
    return qm, type(lib) == "table" and lib or nil
end

local function QuestieTip(data, lib)
    local lines = {}
    if data.Type == "manual" and type(data.ManualTooltipData) == "table" then
        local m = data.ManualTooltipData
        if m.Title then lines[#lines + 1] = { "|cFF33FF33" .. tostring(m.Title) .. "|r" } end
        if type(m.Body) == "table" then
            for _, row in ipairs(m.Body) do
                if type(row) == "table" and row[1] and row[2] then lines[#lines + 1] = { tostring(row[1]) .. " " .. tostring(row[2]) }
                elseif type(row) == "string" then lines[#lines + 1] = { row } end
            end
        end
        return lines
    end
    local giver = data.Type == "available" or data.Type == "complete"
    if giver and data.Name then lines[#lines + 1] = { "|cFF33FF33" .. tostring(data.Name) .. "|r" } end
    local q = data.QuestData
    if q and q.Id then
        local title
        if lib and lib.GetColoredQuestName then
            local ok, r = pcall(lib.GetColoredQuestName, lib, q.Id, true, true)
            if ok and type(r) == "string" and r ~= "" then title = r end
        end
        title = title or tostring(q.name or q.Name or ("Quest " .. q.Id))
        if data.Type == "available" then title = title .. " |cFFAAAAAA(Available)|r"
        elseif data.Type == "complete" then title = title .. " |cFF33FF33(Complete)|r"
        else title = title .. " |cFFFFFF00(Active)|r" end
        lines[#lines + 1] = { title }
    end
    if not giver and data.Name then lines[#lines + 1] = { "|cFFAAAAAA   " .. tostring(data.Name) .. "|r" } end
    if type(data.ObjectiveData) == "table" and data.ObjectiveData.Description then
        lines[#lines + 1] = { "|cFFCCCCCC   " .. tostring(data.ObjectiveData.Description) .. "|r" }
    end
    return lines
end

-- a Questie icon's tooltip lines, worked out on the first hover (not for every icon on every read)
local function QuestieLines(pin)
    if not pin.lines and pin.qdata then
        local ok, lines = pcall(QuestieTip, pin.qdata, pin.qlib)
        pin.lines = ok and lines or {}
        pin.name = pin.lines[1] and pin.lines[1][1] or pin.name
    end
    return pin.lines
end
B.QuestieLines = QuestieLines

local function QuestieEnter(btn, pin)
    if not GameTooltip then return end
    QuestieLines(pin)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local first = true
    for _, l in ipairs(pin.lines or {}) do
        if first then GameTooltip:SetText(l[1]) first = false else GameTooltip:AddLine(l[1], 1, 1, 1, true) end
    end
    if first then GameTooltip:SetText(pin.name or "Questie") end
    GameTooltip:Show()
end

-- (Questie's functions are NOT hooked: Questie hands some of them to C_Timer.NewTicker while it
-- starts, and a hooked one is refused there, which stops Questie from starting at all. Its
-- changes are noticed by counting its icons instead.)

-- How many icon frames Questie holds right now: cheap (no frame is looked at), and it changes
-- whenever Questie adds or takes away icons, whether or not its functions could be hooked
local function QuestieCount(qm)
    if not qm then return 0 end
    local n = 0
    for _, names in pairs(qm.questIdFrames or {}) do
        if type(names) == "table" then for _ in pairs(names) do n = n + 1 end end
    end
    for _, byId in pairs(qm.manualFrames or {}) do
        if type(byId) == "table" then
            for _, list in pairs(byId) do if type(list) == "table" then for _ in pairs(list) do n = n + 1 end end end
        end
    end
    return n
end

-- the end of a read: hand the icons over, unless they are the same as last time (then there is
-- nothing to hand over and nothing to redraw)
local function QuestieDone(st, lists, qm)
    local sig = st.hash .. ":" .. st.taken .. ":" .. (P.IsEnabled("questie") and 1 or 0) .. (P.IsEnabled("questie_avail") and 1 or 0)
        .. (P.IsEnabled("questie_town") and 1 or 0)
    if sig ~= B.qSig then
        B.qSig = sig
        for id, list in pairs(lists) do
            local c = P.cats[id]
            -- a category that is switched off keeps what it had (and its count in the menu)
            if P.IsEnabled(id) and (#list > 0 or (c and #c.pins > 0)) then P.SetPins(id, list) end
        end
    end
    B.questie = qm and true or false
    B.qTaken = st.taken
    -- the icons in the hero's zone, looked at again every 5 s (B.QuestieZoneChanged)
    B.qZone = { map = st.heroMap, names = st.zoneNames, sig = nil }
end

-- what the icons in the hero's zone look like right now: where they are, which picture, shown or
-- not, what kind (a quest turning complete changes it); a few dozen frames
local function ZoneSig(names)
    local h = #names
    for _, name in ipairs(names) do
        local f = _G[name]
        if type(f) == "table" then
            local d = type(f.data) == "table" and f.data
            local t = f.texture
            local file = type(t) == "table" and t.GetTexture and t:GetTexture()
            h = (h * 31 + floor((tonumber(f.x) or 0) * 100) * 13 + floor((tonumber(f.y) or 0) * 100) * 17
                + (f.hidden and 7 or 0) + (d and type(d.Type) == "string" and #d.Type * 3 or 0)
                + (type(file) == "number" and file or (type(file) == "string" and #file * 101 or 0))) % 2147483647
        else
            h = (h * 31 + 5) % 2147483647                  -- (gone)
        end
    end
    return h
end

-- true when the hero's zone has to be read again: the hero went to another zone, or one of the
-- icons there changed since the last full read
function B.QuestieZoneChanged()
    local z = B.qZone
    local hero = ns.HeroMap and ns.HeroMap()
    if not z or not hero then return false end
    if hero ~= z.map then return true end
    local sig = ZoneSig(z.names)
    if z.sig == nil then z.sig = sig return false end
    return sig ~= z.sig
end

local function RebuildQuestie(known)
    qDirty, qLast = false, Now()
    local qm, lib = QuestieMods()
    B.qCount, B.qCountAt = QuestieCount(qm), qLast
    local lists = { questie = {}, questie_avail = {}, questie_town = {} }
    for id, c in pairs({ questie = "Questie: quests and objectives", questie_avail = "Questie: available quests", questie_town = "Questie: townsfolk" }) do
        if not P.cats[id] then
            P.RegisterCategory(id, { name = c, addon = "Questie", order = id == "questie" and 100 or (id == "questie_avail" and 101 or 102),
                minScale = id == "questie_town" and 1.0 or 0.5, size = id == "questie_town" and 14 or 24, color = { 1, 1, 1, 1 } })
        end
    end
    local st = { names = 0, frames = 0, data = 0, unknownMap = 0, hidden = 0, noxy = 0, taken = 0, manual = 0, sample = nil, hash = 0,
        heroMap = ns.HeroMap and ns.HeroMap(), zoneNames = {} }
    B.qstat = st
    if qm then
        local function Take(frame, listID, name)
            st.frames = st.frames + 1
            -- quest icons only (givers, turn-ins, objectives): townsfolk do not change with play
            if listID ~= "questie_town" and type(frame) == "table" and not frame.miniMapIcon and frame.UiMapID == st.heroMap and name then
                st.zoneNames[#st.zoneNames + 1] = name              -- (kept even while hidden: it may show again)
            end
            if type(frame) ~= "table" or frame.miniMapIcon then return end      -- (each icon has a minimap twin)
            if frame.hidden then st.hidden = st.hidden + 1 return end
            local data, mapID = frame.data, frame.UiMapID
            if type(data) ~= "table" then return end
            st.data = st.data + 1
            st.sample = st.sample or tostring(mapID)
            if not known[mapID] then st.unknownMap = st.unknownMap + 1 return end
            if type(frame.x) ~= "number" or type(frame.y) ~= "number" then st.noxy = st.noxy + 1 return end
            local list = lists[listID]
            if #list >= MAX_PER_SOURCE then return end
            local pin = { map = mapID, x = frame.x / 100, y = frame.y / 100, onEnter = QuestieEnter }
            local t = frame.texture
            local file = type(t) == "table" and t.GetTexture and t:GetTexture()
            if file then pin.texture = file else pin.color = { 1, 0.82, 0, 1 } end
            pin.qdata, pin.qlib, pin.name = data, lib, type(data.Name) == "string" and data.Name or "Questie"
            list[#list + 1] = pin
            -- what the read amounts to, cheaply: when it is the same as last time nothing is redrawn
            local h = st.hash
            h = (h * 31 + mapID * 7 + floor(frame.x * 100) * 13 + floor(frame.y * 100) * 17 + #listID) % 2147483647
            if type(file) == "number" then h = (h + file) % 2147483647 elseif type(file) == "string" then h = (h + #file * 101) % 2147483647 end
            st.hash = h
            st.taken = st.taken + 1
        end
        -- the names first (cheap), then the frames themselves a few hundred per frame
        local work = {}
        if P.IsEnabled("questie") or P.IsEnabled("questie_avail") then
            for _, names in pairs(qm.questIdFrames or {}) do
                for _, name in pairs(names) do work[#work + 1] = name end
            end
        end
        local nQuest = #work
        if P.IsEnabled("questie_town") then
            for _, byId in pairs(qm.manualFrames or {}) do
                for _, frameList in pairs(byId) do
                    for _, name in pairs(frameList) do work[#work + 1] = name end
                end
            end
        end
        local CHUNK = 300
        local steps = {}
        for from = 1, #work, CHUNK do
            steps[#steps + 1] = function()
                for i = from, min(from + CHUNK - 1, #work) do
                    local name = work[i]
                    if i <= nQuest then
                        st.names = st.names + 1
                        local frame = _G[name]
                        local data = type(frame) == "table" and frame.data
                        local listID = type(data) == "table" and QTYPES[data.Type]
                        if listID and P.IsEnabled(listID) then Take(frame, listID, name) end
                    else
                        Take(_G[name], "questie_town", name)
                    end
                end
            end
        end
        steps[#steps + 1] = function() QuestieDone(st, lists, qm) end
        Spread("questie", steps)
        return
    end
    QuestieDone(st, lists, qm)
end


---------------------------------------------------------------------------
-- The game's own map pin (what the world map's "Map Pin" button places). It is read back
-- from the game whenever anything sets or clears it, so addons that set it show up too.
---------------------------------------------------------------------------
P.RegisterCategory("waypoint", { name = "Map pin", order = 5, minScale = 0, size = 28, always = true,
    atlas = { "Waypoint-MapPin-Tracked", "Waypoint-MapPin-Untracked" }, texture = "Interface\\Icons\\INV_Misc_Map02" })

-- Ctrl+right click on the map pin lifts it: the click lands on the pin, and the map behind it
-- may not get it (when it does, whichever comes second sees the click as handled)
local function WaypointClick(_, btn)
    if btn ~= "RightButton" or not IsControlKeyDown() then return end
    if ns.wpAt and GetTime() - ns.wpAt < 0.3 then return end
    ns.wpAt = GetTime()
    if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
end
local function ReadWaypoint()
    local w = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if type(w) == "table" and w.uiMapID and type(w.position) == "table" then
        P.SetPins("waypoint", { { map = w.uiMapID, x = w.position.x, y = w.position.y, name = "Map pin",
            text = "Ctrl+right click it to remove", onClick = WaypointClick } })
    else
        P.SetPins("waypoint", {})
    end
end
B.ReadWaypoint = ReadWaypoint
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "USER_WAYPOINT_UPDATED")
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function() pcall(ReadWaypoint) end)
end



---------------------------------------------------------------------------
-- Death marker: where the hero's body lies, while dead or a ghost. Slightly see-through, under the
-- hero's arrow and Spy's enemies and above everything else.
---------------------------------------------------------------------------
P.RegisterCategory("corpse", { name = "Death marker", order = 6, minScale = 0, size = 26, always = true, noCount = true,
    texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" })

local corpse = { on = false }       -- map/x/y of the body once found (it does not move)
local function CorpseOn(map)
    local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, map)
    if not ok or not pos then return end
    local x, y = pos.x, pos.y
    if not x and pos.GetXY then x, y = pos:GetXY() end
    if x and y and x > 0 and x < 1 and y > 0 and y < 1 then return x, y end
end
local function ReadCorpse()
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    if not (dead and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then
        if corpse.on then corpse.on, corpse.map = false, nil; P.SetPins("corpse", {}) end
        return
    end
    if corpse.map then return end
    local x, y
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if map and P.known and P.known[map] then x, y = CorpseOn(map) end
    if not x then
        for _, id in ipairs(P.zoneIDs or {}) do
            x, y = CorpseOn(id)
            if x then map = id break end
        end
    end
    if not x then return end
    corpse.on, corpse.map = true, map
    local pin = { map = map, x = x, y = y, level = 28, color = { 1, 1, 1, 0.85 }, name = "Your corpse" }
    -- the game's own tombstone (cell 8 of its map icon sheet); the skull stays where the client can't say where that is
    local coords = (C_Minimap and C_Minimap.GetPOITextureCoords) or _G.GetPOITextureCoords
    if type(coords) == "function" then
        local ok, l, r, t, b = pcall(coords, 8)
        if ok and type(l) == "number" and type(b) == "number" and r > l and b > t then
            pin.texture, pin.texCoord = "Interface\\Minimap\\POIIcons", { l, r, t, b }
        end
    end
    P.SetPins("corpse", { pin })
end
B.ReadCorpse = ReadCorpse


---------------------------------------------------------------------------
-- Party and raid members: a class-coloured dot each. What lies on top of what, from the top: the hero's
-- arrow, Spy's enemies (level 30), the death marker (28), these (26), every other icon. Positions are refreshed four times a second while the map is open; the pins
-- themselves are only rebuilt when the group (or somebody's state) changes.
---------------------------------------------------------------------------
-- (the same size at every zoom, set by its own slider: Options, party pin size)
P.RegisterCategory("party", { name = "Party and raid members", order = 7, minScale = 0, size = 16, always = true,
    absolute = true, scaleKey = "partySize",
    atlas = { "WhiteCircle-RaidBlips", "WhiteDotCircle-RaidBlips" }, color = { 0.4, 0.6, 1, 1 } })

local party = { pins = {}, list = {}, raidU = {}, partyU = {} }
for i = 1, 40 do party.raidU[i] = "raid" .. i end          -- (unit names made once)
for i = 1, 4 do party.partyU[i] = "party" .. i end
local function ReadParty()
    -- (no strings are built to see what changed: each member's values are compared as they are)
    local list, n = party.list, 0
    local changed, moved = false, false
    local inGroup = IsInGroup and IsInGroup()
    if inGroup and P.known and P.IsEnabled("party") then
        local raid = IsInRaid and IsInRaid()
        local count = raid and 40 or 4
        local units = raid and party.raidU or party.partyU
        for i = 1, count do
            local unit = units[i]
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local map = C_Map.GetBestMapForUnit(unit)
                local pos = map and not Secret(map) and P.known[map] and C_Map.GetPlayerMapPosition(map, unit)
                local x, y
                if pos then
                    x, y = pos.x, pos.y
                    if not x and pos.GetXY then x, y = pos:GetXY() end
                end
                if x and y and not Secret(x) and not Secret(y) and (x ~= 0 or y ~= 0) then
                    local name = UnitName(unit)
                    if Secret(name) or not name then name = unit end
                    local _, class = UnitClass(unit)
                    if Secret(class) then class = nil end
                    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or false
                    if Secret(dead) then dead = false end
                    local level = UnitLevel and UnitLevel(unit)
                    if Secret(level) then level = nil end
                    n = n + 1
                    local p = party.pins[unit]
                    if not p then p = { level = 26 }; party.pins[unit] = p end
                    if list[n] ~= p then changed = true end                 -- someone joined, left or moved up
                    if p.map ~= map then changed = true end                  -- (another map: drawn by a full pass)
                    if p.x ~= x or p.y ~= y then moved = true end
                    p.map, p.x, p.y = map, x, y
                    if p.name ~= name or p.class ~= class or p.dead ~= dead or p.lvl ~= level then
                        changed = true
                        p.name, p.class, p.dead, p.lvl = name, class, dead, level
                        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        p.color = dead and { 0.6, 0.6, 0.6, 1 } or (cc and { cc.r, cc.g, cc.b, 1 }) or nil
                        local cname = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
                        local parts = {}
                        if level and level > 0 then parts[#parts + 1] = "Level " .. level end
                        if cname then parts[#parts + 1] = cname end
                        local line = table.concat(parts, " ")
                        if dead then line = line .. (line ~= "" and " - " or "") .. "dead" end
                        p.text = line ~= "" and line or nil
                    end
                    list[n] = p
                end
            end
        end
    end
    if #list ~= n then changed = true end
    for i = #list, n + 1, -1 do list[i] = nil end
    if changed then
        local copy = {}
        for i = 1, n do copy[i] = list[i] end
        P.SetPins("party", copy)
    elseif moved then
        -- the same members, moved: only their pins are moved (CloudeMap.lua); a full pass only when
        -- one of them is not drawn now (walked into view), and then at most twice a second
        if not (ns.MovePins and ns.MovePins("party")) then
            local now = GetTime()
            if now - (party.fullAt or 0) >= 0.5 and P.onChange then party.fullAt = now; P.onChange() end
        end
    end
end
B.ReadParty = ReadParty
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1 / 12, function()
        local f = _G.CloudeMapFrame
        if f and f.IsShown and f:IsShown() then
            local ok, err = ns.prof.Time("every 1/12 s: party markers", pcall, ReadParty)
            if not ok then B.partyErr = err end
        end
    end)
end


---------------------------------------------------------------------------
-- Pins lying on top of each other: the one under the pointer shows its tooltip as ever, and
-- every other pin under the pointer gets a tooltip of its own, the first to the right of it,
-- the rest below that one.
---------------------------------------------------------------------------
local stackTips = {}

local function StackLines(p, c)
    local lines = {}
    local name = p.name
    if p.qdata and B.QuestieLines then B.QuestieLines(p) end
    if type(p.lines) == "table" then                       -- (Questie)
        for _, l in ipairs(p.lines) do if type(l) == "table" and l[1] then lines[#lines + 1] = tostring(l[1]) end end
    else
        if type(name) == "string" and name ~= "" then lines[#lines + 1] = name end
        if type(p.text) == "string" then lines[#lines + 1] = p.text
        elseif type(p.text) == "table" then for _, t in ipairs(p.text) do lines[#lines + 1] = tostring(t) end end
    end
    if #lines == 0 then lines[1] = c and c.name or "Pin" end
    return lines
end

function ns.HideStack()
    for _, t in ipairs(stackTips) do t:Hide() end
end

function ns.StackTips(btn, pinBtns)
    ns.HideStack()
    local n = 0
    local prev
    for _, b in ipairs(pinBtns) do
        if b ~= btn and b:IsShown() and b.pin and b:IsMouseOver() then
            n = n + 1
            if n > 6 then break end
            local tip = stackTips[n]
            if not tip then
                tip = CreateFrame("GameTooltip", "CloudeMapStackTip" .. n, UIParent, "GameTooltipTemplate")
                stackTips[n] = tip
            end
            tip:SetOwner(UIParent, "ANCHOR_NONE")
            tip:ClearAllPoints()
            if prev then
                tip:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
            elseif GameTooltip and GameTooltip:IsShown() then
                tip:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 2, 0)
            else
                tip:SetPoint("TOPLEFT", btn, "BOTTOMRIGHT", 4, -4)
            end
            local lines = StackLines(b.pin, b.cat)
            tip:SetText(lines[1])
            for i = 2, #lines do tip:AddLine(lines[i], 1, 1, 1, true) end
            tip:Show()
            prev = tip
        end
    end
end

---------------------------------------------------------------------------
-- A window with selectable text (addons cannot write to the clipboard): Ctrl+C copies it.
---------------------------------------------------------------------------
local copyFrame
function ns.ShowCopy(text)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if not copyFrame then
        local f = CreateFrame("Frame", "CloudeMapCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(620, 360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
            f:SetBackdropBorderColor(0, 0, 0, 1)
        end
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText("CloudeMap: Ctrl+C copies the selected text, Esc closes")
        -- the close button hides the window itself: the template's own click goes through the
        -- game's panel manager (HideUIPanel), which errors for a window it does not manage
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() f:Hide() end)
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "CloudeMapCopyFrame") end    -- Esc closes it, focused or not
        f:SetScript("OnHide", function() f.edit:ClearFocus() end)
        local scroll = CreateFrame("ScrollFrame", "CloudeMapCopyScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -30)
        scroll:SetPoint("BOTTOMRIGHT", -30, 10)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        edit:SetWidth(570)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        copyFrame = f
    end
    copyFrame:Show()
    copyFrame.edit:SetText(text)
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Driver: only while the map is open
---------------------------------------------------------------------------
-- copies of HereBeDragons-Pins are looked for when an addon has loaded (that is when one can
-- appear), not on a timer
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function() pcall(FindLibs) end)
end

function B.Refresh() hbdDirty, hnDirty = true, true end

function B.Status()
    local names = {}
    for n in pairs(libs) do names[#names + 1] = n end
    table.sort(names)
    local HN = HandyNotes()
    local plugins = 0
    if HN then for _ in pairs(HN.plugins) do plugins = plugins + 1 end end
    local texLine = ""
    local poiOK, blobOK = B.poiOK, B.blobOK         -- (QuestAreas.lua)
    texLine = texLine .. " | quest markers: " .. (poiOK == nil and "not drawn yet" or (poiOK and "CloudeMap's buttons with the game's art" or "plain icons (the button failed)"))
        .. (B.poiErr and (", error: " .. tostring(B.poiErr)) or "")
    local blobLine = ("quest areas: %s%s%s%s | "):format(
        blobOK == nil and "not drawn yet" or (blobOK and ("game frame working, %d quests in the log, last drawn %s"):format(B.blobQuests or 0, tostring(B.blobLast)) or "the game has no QuestPOIFrame here"),
        (", %d frames, %d shown, %d draws, last %s, %d failed%s"):format(B.BlobCount()),
        B.blobErr and (", error: " .. tostring(B.blobErr)) or "", texLine)
    local q = B.qstat
    local Q = _G.Questie
    local prof = type(Q) == "table" and type(Q.db) == "table" and Q.db.profile
    if q and type(prof) == "table" and (prof.enabled == false or prof.enableMapIcons == false) then
        q = nil
        return blobLine .. "Questie: its icons are switched off in Questie itself (" .. (prof.enabled == false and "icons disabled" or "map icons disabled")
            .. "), so there is nothing to draw. Carbonite's Questie button on its map does this too."
    end
    local qs = q and ("Questie frames: %d names, %d seen, %d with data, %d on unknown maps (e.g. map %s), %d hidden, %d without x/y, %d drawn%s | "):format(
        q.names, q.frames, q.data, q.unknownMap, tostring(q.sample), q.hidden, q.noxy, q.taken,
        (", %d icons counted, read %.0f s ago"):format(B.qCount or 0, Now() - qLast)) or ""
    blobLine = blobLine .. ("GatherMate2 %s | RareScanner %s%s | Spy %s | "):format(
        type(_G.GatherMate2) == "table" and (B.gm and "read" or "loaded, not read yet") or "not loaded",
        type(_G.RareScannerDataProviderMixin) == "table" and ("read, %s pins of which %s spots"):format(tostring(B.rs or 0), tostring(B.rsDots or 0)) or "not loaded",
        (B.rsErr and (", error: " .. tostring(B.rsErr)) or "") .. (B.rsTipErr and (", tooltip error: " .. tostring(B.rsTipErr)) or ""),
        type(_G.Spy) == "table" and "loaded" or "not loaded")
        .. (B.DungeonStatus and (B.DungeonStatus() .. " | ") or "")
        .. ("tracking menu: %s | "):format(B.trackingTypes and table.concat(B.trackingTypes, ", ") or "not read")
        .. ("ley lines %d, convergences %d (Skyborne Leyline & Convergence Marker's list)%s | "):format(B.leyCount or 0, B.convCount or 0, B.leyErr and (", error: " .. tostring(B.leyErr)) or "")
        .. ("party pins %d%s | "):format(#party.list, B.partyErr and (", error: " .. tostring(B.partyErr)) or "")
        .. (B.pingStat and ("pings: group pings heard %d (%d before the map was drawn, %d on maps not drawn here)%s, "):format(
            B.pingStat.heard, B.pingStat.waited, B.pingStat.offmap,
            B.pingStat.at and (", last from %s %.0f s ago"):format(B.pingStat.last, GetTime() - B.pingStat.at) or "") or "")
        .. ("sent %d%s, prefix registration %s, "):format(B.pingSent or 0,
            B.pingSentLast and (" (last " .. B.pingSentLast .. ")") or "", tostring(B.pingPrefix))
        .. ("minimap pings %s, last %s%s | "):format(B.mmHooked and "heard" or "not available", tostring(B.mmLast or "none"),
            (B.pingErr and (", send error " .. tostring(B.pingErr)) or "") .. (B.blocked and (", blocked " .. (B.blockedN or 1) .. "x, last " .. B.blocked) or ""))
        .. (B.PluginStatus and B.PluginStatus() or "")
    return blobLine .. qs .. ("addon icons: Questie %s | pin libraries %s | HandyNotes %s%s"):format(
        B.questie == nil and "not seen" or (B.questie and "read" or "frames not available"),
        #names > 0 and table.concat(names, ", ") or "none found",
        HN and (plugins .. " plugins") or "not loaded",
        B.err and (" | last error: " .. tostring(B.err)) or "")
end

function B.Tick()
    local T = ns.prof.Time
    local now = Now()
    pcall(B.SpySample)
    local f = _G.CloudeMapFrame
    if not (f and f.IsShown and f:IsShown()) then return end
    -- the quest picked in the log (no event says so): its area is highlighted
    if B.QuestsChanged and C_QuestLog and C_QuestLog.GetSelectedQuest then
        local ok, q = pcall(C_QuestLog.GetSelectedQuest)
        if ok and q ~= B.selQuest then B.selQuest = q; B.QuestsChanged() end
    end
    if B.DungeonTick then
        local ok, err = T("every 0.5 s: Dungeon Journal and BG buttons", pcall, B.DungeonTick)
        if not ok then B.err = err end
    end
    if B.DJMarkers then
        local ok, err = T("every 0.5 s: Dungeon Journal map markers", pcall, B.DJMarkers)
        if not ok then B.djxErr = err end
    end
    local known, zones = P.known, P.zoneIDs
    if not (known and zones) then return end
    pcall(ReadCorpse)
    -- every 5 s (the library is not watched: its pin list is read; a switch flipped here reads it
    -- at once)
    if next(libs) and ((hbdDirty and now - hbdLast >= 1) or now - hbdLast >= 5) then
        local ok, err = T("every 0.5 s: HereBeDragons pins", pcall, RebuildHBD, known)
        if not ok then B.err = err end
    end
    -- Questie: read again when the number of its icons changed (counted every 2 s, cheaply) or a
    -- switch was flipped; while it has shown nothing yet (it draws a while after logging in),
    -- every 2 s; when an icon in the hero's zone changed (looked at every 5 s); and every 15 s
    -- regardless
    local qDue
    if _G.QuestieLoader then
        if qDirty and now - qLast >= 1 then qDue = true
        elseif now - qLast >= 15 then qDue = true
        elseif now - qLast >= 2 and (B.qTaken or 0) == 0 then qDue = true
        -- the hero's zone, every 5 s: read again when anything there changed (or the hero moved on)
        elseif now - (B.qZoneAt or 0) >= 5 and now - qLast >= 5 then
            B.qZoneAt = now
            if B.QuestieZoneChanged() then qDue = true end
        elseif now - (B.qCountAt or 0) >= 2 then
            B.qCountAt = now
            local qm = QuestieMods()
            if qm and QuestieCount(qm) ~= B.qCount then qDue = true end
        end
    end
    if qDue then
        local ok, err = T("every 0.5 s: Questie", pcall, RebuildQuestie, known)
        if not ok then B.err = err end
    end
    if B.SpyPins and (now - (B.spyLast or 0) >= 1.5 or B.spyDue) then
        B.spyLast, B.spyDue = now, nil
        T("every 0.5 s: Spy", pcall, B.SpyPins, known)
    end
    local hnZones, hnKey = HNZones()
    if hnKey ~= B.hnKey then B.hnKey = hnKey; hnDirty = true; hnLast = 0 end
    zones = hnZones
    -- (HandyNotes is not watched: read every 5 s, and at once when a switch is flipped here)
    if (hnDirty and now - hnLast >= 1) or now - hnLast >= 5 then
        local ok, err = T("every 0.5 s: HandyNotes", pcall, RebuildHN, known, zones)
        if not ok then B.err = err end
    end
end

-- a switch flipped in the Pins menu: read that source again straight away
local SetEnabled = P.SetEnabled
function P.SetEnabled(id, on)
    SetEnabled(id, on)
    if type(id) == "string" and (id:find("^addon:") or id:find("^hn:") or id:find("^questie")) then
        hbdDirty, hnDirty, hbdLast, hnLast, qLast = true, true, 0, 0, 0
    end
end

pcall(FindLibs)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.5, function() ns.prof.Time("every 0.5 s: addon readers (all)", B.Tick) end)
end


---------------------------------------------------------------------------
-- Minimap button: a click shows or hides the map; dragging moves the button round the minimap
-- (its place is kept in the settings' minimapAngle, in degrees).
---------------------------------------------------------------------------
do
    local btn
    local function Place()
        local db = ns.db
        local a = math.rad(type(db) == "table" and tonumber(db.minimapAngle) or 215)
        local r = (Minimap:GetWidth() or 140) / 2 + 6
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end
    local function Make()
        if btn or not (Minimap and ns.Toggle) then return end
        btn = CreateFrame("Button", "CloudeMapMinimapButton", Minimap)
        btn:SetSize(31, 31)
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
        btn:RegisterForClicks("LeftButtonUp")
        btn:RegisterForDrag("LeftButton")
        btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local back = btn:CreateTexture(nil, "BACKGROUND")
        back:SetSize(20, 20)
        back:SetPoint("TOPLEFT", 7, -5)
        back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(17, 17)
        icon:SetPoint("TOPLEFT", 7, -6)
        icon:SetTexture("Interface\\AddOns\\CloudeMap\\Gfx\\CloudeMap")      -- CloudeMap's own icon
        icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        local ring = btn:CreateTexture(nil, "OVERLAY")
        ring:SetSize(53, 53)
        ring:SetPoint("TOPLEFT")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        btn:SetScript("OnClick", function() ns.Toggle() end)
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("CloudeMap")
            GameTooltip:AddLine("Click to show or hide the map.", 1, 1, 1)
            GameTooltip:AddLine("Drag to move this button.", 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        -- dragging: the button follows the pointer round the minimap's edge
        btn:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local cx, cy = GetCursorPosition()
                local es = Minimap:GetEffectiveScale()
                if not (mx and cx and es and es > 0) then return end
                local deg = math.deg(math.atan2(cy / es - my, cx / es - mx))
                if type(ns.db) == "table" then ns.db.minimapAngle = deg end
                Place()
            end)
        end)
        btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        Place()
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        local ok, err = pcall(Make)
        if not ok then B.minimapErr = err end
    end)
    B.MinimapButton = function() pcall(Make); return btn end
end
