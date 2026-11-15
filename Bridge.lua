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

local ORDER_HBD, ORDER_HN = 200, 300
local MAX_PER_SOURCE = 4000

---------------------------------------------------------------------------
-- HereBeDragons-Pins
---------------------------------------------------------------------------
local libs = {}                                     -- name -> the library (a copy of HereBeDragons-Pins)
local at = setmetatable({}, { __mode = "k" })       -- icon frame -> { uiMapID, x, y } as it was added
local hbdDirty, hbdLast, hbdCats = true, 0, {}
local KNOWN_GLOBALS = { "Questie", "TomTom", "RXP", "RXPGuides", "Spy", "GatherMate2", "GatherLite", "Routes", "Gatherer", "ZGV" }

local function HookLib(name, lib)
    if name:find("Questie", 1, true) then return end     -- (read from Questie's own frames, below)
    if libs[name] or type(lib) ~= "table" or type(lib.worldmapPinRegistry) ~= "table" then return end
    libs[name] = lib
    hbdDirty = true
    if not hooksecurefunc then return end
    if type(lib.AddWorldMapIconMap) == "function" then
        hooksecurefunc(lib, "AddWorldMapIconMap", function(_, _, icon, uiMapID, x, y)
            if icon and type(uiMapID) == "number" and type(x) == "number" and type(y) == "number" then
                at[icon] = { uiMapID, x, y }
            end
            hbdDirty = true
        end)
    end
    for _, fn in ipairs({ "AddWorldMapIconWorld", "RemoveWorldMapIcon", "RemoveAllWorldMapIcons" }) do
        if type(lib[fn]) == "function" then
            hooksecurefunc(lib, fn, function(_, _, icon)
                if fn == "RemoveWorldMapIcon" and icon then at[icon] = nil end
                hbdDirty = true
            end)
        end
    end
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
local function HbdLeave(_, pin)
    local f = pin.src
    local s = f and f.GetScript and f:GetScript("OnLeave")
    if s then pcall(s, f) end
end
local function HbdClick(pin, button)
    local f = pin.src
    if not (f and f.GetScript) then return end
    local s = f:GetScript("OnClick")
    if s then pcall(s, f, button, false) return end
    s = f:GetScript("OnMouseUp")
    if s then pcall(s, f, button) end
end

local function IconPin(icon, data, known, hbd)
    if type(icon) ~= "table" or type(data) ~= "table" then return end
    if icon.type == "line" or icon.hidden or icon.miniMapIcon then return end     -- (Questie: path lines, hidden ones)
    local mapID, x, y
    local a = at[icon]
    if a then mapID, x, y = a[1], a[2], a[3] end
    if not x and type(data.mapX) == "number" and type(data.mapY) == "number" then
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
                    for icon, data in pairs(icons) do
                        if #list >= MAX_PER_SOURCE then break end
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
        if P.IsEnabled(id) and (#list > 0 or (c and #c.pins > 0)) then P.SetPins(id, list) end
        hbdCats[id] = true
    end
    for id in pairs(hbdCats) do
        if not lists[id] and P.cats[id] and #P.cats[id].pins > 0 then P.SetPins(id, {}) end
    end
end

---------------------------------------------------------------------------
-- HandyNotes
---------------------------------------------------------------------------
local hnDirty, hnLast, hnHooked, hnCats = true, 0, false, {}

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
    if not hnHooked and hooksecurefunc then
        hnHooked = true
        for _, fn in ipairs({ "UpdateWorldMapPlugin", "UpdateWorldMap", "UpdatePluginMap" }) do
            if type(HN[fn]) == "function" then hooksecurefunc(HN, fn, function() hnDirty = true end) end
        end
    end
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
                if P.IsEnabled(id) and (#list > 0 or (c and #c.pins > 0)) then P.SetPins(id, list) end
            end
        end
    end
    steps[#steps + 1] = function()
        for id in pairs(hnCats) do
            if not live[id] and P.cats[id] and #P.cats[id].pins > 0 then P.SetPins(id, {}) end
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
    local st = { names = 0, frames = 0, data = 0, unknownMap = 0, hidden = 0, noxy = 0, taken = 0, manual = 0, sample = nil, hash = 0 }
    B.qstat = st
    if qm then
        local function Take(frame, listID)
            st.frames = st.frames + 1
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
                        if listID and P.IsEnabled(listID) then Take(frame, listID) end
                    else
                        Take(_G[name], "questie_town")
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

local function ReadWaypoint()
    local w = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if type(w) == "table" and w.uiMapID and type(w.position) == "table" then
        P.SetPins("waypoint", { { map = w.uiMapID, x = w.position.x, y = w.position.y, name = "Map pin",
            text = "Ctrl+right click it to remove" } })
    else
        P.SetPins("waypoint", {})
    end
end
B.ReadWaypoint = ReadWaypoint
if C_Map and hooksecurefunc then
    for _, fn in ipairs({ "SetUserWaypoint", "ClearUserWaypoint" }) do
        if type(C_Map[fn]) == "function" then hooksecurefunc(C_Map, fn, function() pcall(ReadWaypoint) end) end
    end
end
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
P.RegisterCategory("party", { name = "Party and raid members", order = 7, minScale = 0, size = 16, always = true,
    atlas = { "WhiteCircle-RaidBlips", "WhiteDotCircle-RaidBlips" }, color = { 0.4, 0.6, 1, 1 } })

local party = { sig = "", pins = {}, list = {} }
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function ReadParty()
    local list, sig, n = party.list, "", 0
    local inGroup = IsInGroup and IsInGroup()
    if inGroup and P.known and P.IsEnabled("party") then
        local raid = IsInRaid and IsInRaid()
        local count = raid and 40 or 4
        for i = 1, count do
            local unit = (raid and "raid" or "party") .. i
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
                    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
                    if Secret(dead) then dead = false end
                    local level = UnitLevel and UnitLevel(unit)
                    if Secret(level) then level = nil end
                    n = n + 1
                    local p = party.pins[unit]
                    if not p then p = { level = 26 }; party.pins[unit] = p end
                    p.map, p.x, p.y = map, x, y
                    local state = name .. (class or "") .. (dead and "d" or "") .. tostring(level)
                    if p.state ~= state then
                        p.state, p.name = state, name
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
                    sig = sig .. unit .. state
                end
            end
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    if sig ~= party.sig then
        party.sig = sig
        local copy = {}
        for i = 1, n do copy[i] = list[i] end
        P.SetPins("party", copy)
    elseif n > 0 and P.onChange then
        P.onChange()                -- the same pins, moved: only their places are redrawn
    end
end
B.ReadParty = ReadParty
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.25, function()
        local f = _G.CloudeMapFrame
        if f and f.IsShown and f:IsShown() then
            local ok, err = ns.prof.Time("every 0.25 s: party markers", pcall, ReadParty)
            if not ok then B.partyErr = err end
        end
    end)
end


---------------------------------------------------------------------------
-- Quest areas: the game's own quest blobs (the QuestPOIFrame its world map uses). One frame per
-- quest, laid over the quest's zone while that zone is drawn in detail, so every quest can have
-- its own look: the active quest (the one the game's map would show) as on the game's map, the
-- others dimmer ("dim") or each in a colour of its own ("color"); /cmap quests switches.
-- Satellite mode: the outline with a faint inside, as on the minimap.
---------------------------------------------------------------------------
P.RegisterCategory("questarea", { name = "Quest areas", order = 99, noCount = true })

local blobs, bstate, blobOK, questRev = {}, {}, nil, 1
local BLOB_W, BLOB_H = 1002, 668
local FILL, EDGE = "Interface\\WorldMap\\UI-QuestBlob-Inside", "Interface\\WorldMap\\UI-QuestBlob-Outside"
local NCOLORS = 12
local last = {}                 -- the map's view at the last draw, for the hover test
local poiXY = {}                -- mapID -> { [questID] = { x, y } }, where the game puts the quest's marker

local function LogQuests()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, (C_QuestLog.GetNumQuestLogEntries()) do
            local info = C_QuestLog.GetInfo(i)
            if type(info) == "table" and not info.isHeader and type(info.questID) == "number" and info.questID > 0 then
                out[#out + 1] = info.questID
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, (GetNumQuestLogEntries()) do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if not isHeader and type(questID) == "number" and questID > 0 then out[#out + 1] = questID end
        end
    end
    return out
end

-- the quest the game's own map would show: the tracked ("focused") one, else the one selected in the log
local function ActiveQuest()
    local q
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local ok, v = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok and type(v) == "number" and v > 0 then q = v end
    end
    if not q and C_QuestLog and C_QuestLog.GetSelectedQuest then
        local ok, v = pcall(C_QuestLog.GetSelectedQuest)
        if ok and type(v) == "number" and v > 0 then q = v end
    end
    return q
end

local function NewBlob(view, canvas)
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, view)
    if not ok or type(f) ~= "table" or type(f.DrawBlob) ~= "function" or type(f.SetMapID) ~= "function" then
        blobOK = false
        return
    end
    blobOK = true
    f:EnableMouse(false)
    f:SetFrameLevel(canvas:GetFrameLevel() + 2)
    f:SetFillTexture(FILL)
    f:SetBorderTexture(EDGE)
    pcall(function()
        f:EnableSmoothing(true)
        f:EnableMerging(true)
        f:SetMergeThreshold(0.1)
        f:SetNumSplinePoints(30)
    end)
    return f
end

-- look: "active" | "dim" | a colour number
local function Style(f, st, mode, look, border, level)
    local key = mode .. ":" .. tostring(look) .. ":" .. border
    if st.style == key then return end
    st.style = key
    local sat = mode == "sat"
    if look == "active" then
        f:SetFillTexture(FILL)
        f:SetFillAlpha(sat and 36 or 128)
        f:SetBorderAlpha(sat and 255 or 192)
    elseif look == "dim" then
        f:SetFillTexture(FILL)
        f:SetFillAlpha(sat and 16 or 58)
        f:SetBorderAlpha(sat and 120 or 95)
    end
    f:SetBorderScalar(border)
    f:SetFrameLevel(level + (look == "active" and 3 or 2))
end

function B.RestyleBlobs() for _, st in pairs(bstate) do st.style = nil end end

-- The quests of the log whose area is on this map. A blob frame draws whatever quest it is given
-- as if it were on its own map, and the game also lists a neighbour's quests for a map, so a
-- quest goes only to the map the game calls its own.
local function QuestsOn(mapID, quests)
    local listed
    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
        if ok and type(list) == "table" then
            listed = {}
            for _, q in ipairs(list) do
                if type(q) == "table" and type(q.questID) == "number" then listed[q.questID] = true end
            end
        end
    end
    local out = {}
    local xy = {}
    poiXY[mapID] = xy
    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
        if ok and type(list) == "table" then
            for _, q in ipairs(list) do
                if type(q) == "table" and type(q.questID) == "number" and type(q.x) == "number" and type(q.y) == "number" then
                    xy[q.questID] = { q.x, q.y }
                end
            end
        end
    end
    for _, q in ipairs(quests) do
        local home
        if GetQuestUiMapID then
            local ok, m = pcall(GetQuestUiMapID, q)
            if ok and type(m) == "number" and m > 0 then home = m end
        end
        if home then
            if home == mapID then out[#out + 1] = q end
        elseif listed and listed[q] then
            out[#out + 1] = q
        end
    end
    return out
end

-- The frame keeps the size of the game's own map canvas (1002 x 668) and is scaled onto the
-- zone's rectangle, as Carbonite does. The blob is laid out for where the frame IS when it is
-- drawn, so: put the frame in place, have the game work out its rectangle, draw - and draw once
-- more on the next frame, when the new place has certainly taken hold. Any move or zoom of the
-- map draws it again.
local function Place(f, st, view)
    f:SetSize(BLOB_W, BLOB_H)
    f:SetScale(st.s)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", view, "TOPLEFT", st.x / st.s, -st.y / st.s)
    if f.GetLeft then f:GetLeft() end           -- resolves the anchors now
end

local function Paint(f, st, view)
    if InCombatLockdown and InCombatLockdown() then return end
    Place(f, st, view)
    f:DrawNone()
    f:SetMapID(st.mapID)
    f:DrawBlob(st.quest, true)
    f:Show()
    Place(f, st, view)                          -- (SetMapID and Show may move the frame)
end

local zoneQuests, zoneRev = {}, {}

local function DrawBlobs(view, canvas, ox, oy, scale, mode, shown, db)
    local used = {}
    last.view, last.ox, last.oy, last.scale, last.shown = view, ox, oy, scale, shown
    if P.IsEnabled("questarea") then
        local quests
        local active = ActiveQuest()
        local how = (db and db.blobMode) or "dim"
        local border = 1
        local level = canvas:GetFrameLevel()
        for _, n in ipairs(shown) do
            if zoneRev[n.mapID] ~= questRev then
                quests = quests or LogQuests()
                zoneQuests[n.mapID] = QuestsOn(n.mapID, quests)
                table.sort(zoneQuests[n.mapID])
                zoneRev[n.mapID] = questRev
                B.blobQuests = #quests
                B.blobLast = ("%d on map %d"):format(#zoneQuests[n.mapID], n.mapID)
            end
            local s = n.w * scale / BLOB_W
            local x, y = ox + n.x * scale, oy + n.y * scale
            if s > 0.001 then
                local ci = 0
                for _, q in ipairs(zoneQuests[n.mapID]) do
                  if how ~= "tracked" or q == active then
                    if q ~= active then ci = ci % NCOLORS + 1 end      -- each quest of the zone the next colour
                    local key = n.mapID * 1000000 + q
                    local f = blobs[key] or NewBlob(view, canvas)
                    if not f then return end
                    blobs[key] = f
                    used[key] = true
                    local st = bstate[key]
                    if not st then st = { mapID = n.mapID, quest = q, node = n }; bstate[key] = st end
                    st.node = n
                    local look = (q == active and "active") or "dim"
                    Style(f, st, mode, look, border, level)
                    local moved = not st.s or abs(st.s - s) > 0.0005 or abs(st.x - x) > 0.25 or abs(st.y - y) > 0.25
                    if moved or st.rev ~= questRev or not st.shown then
                        st.rev, st.s, st.x, st.y, st.shown = questRev, s, x, y, true
                        Paint(f, st, view)
                        if C_Timer and C_Timer.After and not st.pending then
                            st.pending = true
                            C_Timer.After(0, function()
                                st.pending = nil
                                if st.shown then pcall(Paint, f, st, view) end
                            end)
                        end
                    end
                  end
                end
            end
        end
    end
    for key, f in pairs(blobs) do
        if not used[key] then
            f:Hide()
            if bstate[key] then bstate[key].shown = nil end
        end
    end
end

-- Quest markers: the game's own quest buttons (the "?" and "..." in a circle of its world map),
-- one per quest, where the game puts it. Clicking one tracks the quest, as on the game's map.
P.RegisterCategory("questpoi", { name = "Quest markers", order = 98, noCount = true })
local pois, poiState, poiOK, QuestTip = {}, {}, nil, nil

local function QuestDone(q)
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, v = pcall(C_QuestLog.IsComplete, q)
        if ok then return v and true or false end
    end
    return false
end

local function NewPoi(view, canvas)
    local ok, f = pcall(CreateFrame, "Button", nil, view, "POIButtonTemplate")
    if not ok or type(f) ~= "table" or type(f.SetQuestID) ~= "function" then
        poiOK = false
        return
    end
    f:SetFrameLevel(canvas:GetFrameLevel() + 8)
    f:HookScript("OnEnter", function(self) if self.smQuest and QuestTip then QuestTip(self.smQuest, self) end end)
    f:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return f
end

local function SetupPoi(f, q, isActive)
    f.smQuest = q
    local style
    if POIButtonUtil then
        if POIButtonUtil.GetStyle then style = POIButtonUtil.GetStyle(q) end
        if not style and POIButtonUtil.Style then
            style = QuestDone(q) and POIButtonUtil.Style.QuestComplete or POIButtonUtil.Style.QuestInProgress
        end
    end
    f:SetQuestID(q)
    if style and f.SetStyle then f:SetStyle(style) end
    if f.SetSelected then f:SetSelected(isActive) end
    if f.UpdateButtonStyle then f:UpdateButtonStyle() end
end

local fbKey
local function DrawPois(view, canvas, ox, oy, scale, mode, shown, db)
    local used = {}
    local on = P.IsEnabled("questpoi")
    if on and poiOK ~= false then
        local active = ActiveQuest()
        for _, n in ipairs(shown) do
            local xy = poiXY[n.mapID]
            for _, q in ipairs(zoneQuests[n.mapID] or {}) do
                local p = xy and xy[q]
                if p then
                    local key = n.mapID * 1000000 + q
                    local f = pois[key] or NewPoi(view, canvas)
                    if not f then break end
                    pois[key] = f
                    used[key] = true
                    local sig = questRev * 2 + (q == active and 1 or 0)
                    if poiState[key] ~= sig then
                        local ok, err = pcall(SetupPoi, f, q, q == active)
                        if not ok then poiOK = false; B.poiErr = err; break end
                        poiOK = true
                        poiState[key] = sig
                    end
                    f:ClearAllPoints()
                    if ns.pinLayer then     -- on the layer that moves with the map (as the pins are)
                        f:SetPoint("CENTER", ns.pinLayer, "TOPLEFT", (n.x + p[1] * n.w) * scale, -((n.y + p[2] * n.h) * scale))
                    else
                        f:SetPoint("CENTER", view, "TOPLEFT", ox + (n.x + p[1] * n.w) * scale, -(oy + (n.y + p[2] * n.h) * scale))
                    end
                    f:Show()
                end
            end
            if poiOK == false then break end
        end
    end
    for key, f in pairs(pois) do
        if not used[key] or poiOK == false then f:Hide() end
    end
    -- the game's button is not to be had here: plain icons through the pin layer instead
    if poiOK == false then
        local parts, pins = { tostring(questRev), on and "1" or "0" }, {}
        for _, n in ipairs(shown) do parts[#parts + 1] = n.mapID end
        local key = table.concat(parts, ":")
        if key ~= fbKey then
            fbKey = key
            if on then
                for _, n in ipairs(shown) do
                    local xy = poiXY[n.mapID]
                    for _, q in ipairs(zoneQuests[n.mapID] or {}) do
                        local p = xy and xy[q]
                        if p then
                            pins[#pins + 1] = { map = n.mapID, x = p[1], y = p[2], size = 22, quest = q,
                                texture = QuestDone(q) and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\IncompleteQuestIcon",
                                onEnter = function(btn, pin) if QuestTip then QuestTip(pin.quest, btn) end end }
                        end
                    end
                end
            end
            P.SetPins("questpoi", pins)
        end
    end
end

local function ZoneLists(view, canvas, ox, oy, scale, mode, shown)
    local quests
    for _, n in ipairs(shown) do
        if zoneRev[n.mapID] ~= questRev then
            quests = quests or LogQuests()
            zoneQuests[n.mapID] = QuestsOn(n.mapID, quests)
            table.sort(zoneQuests[n.mapID])
            zoneRev[n.mapID] = questRev
            B.blobQuests = #quests
            B.blobLast = ("%d on map %d"):format(#zoneQuests[n.mapID], n.mapID)
        end
    end
end

-- light: the map only moved (the same zones, zoom and pins): only the quest areas, which the game
-- draws for where their frame is, are laid again; everything else is where it was
function ns.afterUpdate(...)
    local T = ns.prof.Time
    if select(9, ...) then
        if blobOK ~= false then
            local ok, err = T("pins: quest areas", pcall, DrawBlobs, ...)
            if not ok then B.blobErr = err end
        end
        return
    end
    T("pins: quest lists", pcall, ZoneLists, ...)
    if blobOK ~= false then
        local ok, err = T("pins: quest areas", pcall, DrawBlobs, ...)
        if not ok then B.blobErr = err end
    end
    local ok, err = T("pins: quest markers", pcall, DrawPois, ...)
    if not ok then B.poiErr = err end
    local shown = ns.pinZones or select(7, ...)      -- (with the zone in detail even while it fades in)
    -- after a zone change both may have a lot to read: not in the same frame
    local gmRead
    if B.GatherPins then
        local okG, did = T("pins: GatherMate", pcall, B.GatherPins, shown)
        gmRead = okG and did
    end
    if B.RarePins then
        if gmRead and C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() if ns.pinZones then T("pins: RareScanner", pcall, B.RarePins, ns.pinZones) end end)
        else
            T("pins: RareScanner", pcall, B.RarePins, shown)
        end
    end
end

-- Hovering an area: the quest's name and objectives, as on the game's map
local tipQuest, tipOwner
function QuestTip(q, view)
    if not GameTooltip then return end
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then title = C_QuestLog.GetTitleForQuestID(q) end
    if not pcall(GameTooltip.SetOwner, GameTooltip, view, "ANCHOR_CURSOR_RIGHT", 5, 2) then
        GameTooltip:SetOwner(view, "ANCHOR_CURSOR")
    end
    GameTooltip:SetText(title or ("Quest " .. q))
    local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q)
    if type(objs) == "table" then
        for _, o in ipairs(objs) do
            if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
                if o.finished then GameTooltip:AddLine("- " .. o.text, 0.6, 0.6, 0.6, true)
                else GameTooltip:AddLine("- " .. o.text, 1, 1, 1, true) end
            end
        end
    end
    GameTooltip:Show()
    tipQuest, tipOwner = q, view
end

local function HoverCheck()
    local view = last.view
    if not (view and view.IsVisible and view:IsVisible() and P.IsEnabled("questarea")) then
        if tipQuest and GameTooltip and GameTooltip:GetOwner() == tipOwner then GameTooltip:Hide() end
        tipQuest = nil
        return
    end
    local found
    if view:IsMouseOver() then
        -- something else's tooltip (a pin's) has the say
        local owner = GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner()
        if owner and owner ~= view then tipQuest = nil return end
        local cx, cy = GetCursorPosition()
        local es = view:GetEffectiveScale()
        cx, cy = cx / es - view:GetLeft(), view:GetTop() - cy / es
        local px, py = (cx - last.ox) / last.scale, (cy - last.oy) / last.scale
        local active = ActiveQuest()
        for key, st in pairs(bstate) do
            local f, n = blobs[key], st.node
            if st.shown and f and n and type(f.UpdateMouseOverTooltip) == "function" then
                local nx, ny = (px - n.x) / n.w, (py - n.y) / n.h
                if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                    local ok, q = pcall(f.UpdateMouseOverTooltip, f, nx, ny)
                    if ok and q then
                        found = st.quest
                        if st.quest == active then break end        -- the active quest wins an overlap
                    end
                end
            end
        end
    end
    if found then
        if found ~= tipQuest or not (GameTooltip and GameTooltip:IsShown()) then QuestTip(found, view) end
    elseif tipQuest then
        if GameTooltip and GameTooltip:GetOwner() == tipOwner then GameTooltip:Hide() end
        tipQuest = nil
    end
end

do
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
                         "PLAYER_REGEN_ENABLED", "SUPER_TRACKING_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local function Again()
        questRev = questRev + 1
        if P.onChange then P.onChange() end        -- has the map drawn again
    end
    f:SetScript("OnEvent", Again)
    if hooksecurefunc and C_QuestLog and type(C_QuestLog.SetSelectedQuest) == "function" then
        hooksecurefunc(C_QuestLog, "SetSelectedQuest", Again)
    end
    B.QuestsChanged = Again
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.08 then return end
        acc = 0
        pcall(HoverCheck)
    end)
end


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

---------------------------------------------------------------------------
-- RareScanner (written against 1.60: RareScannerMapProvider.lua, RSEntityPinMixin.lua,
-- RSGroupPinMixin.lua, RSOverlayMixin.lua, RSTooltip.lua).
--
-- RareScanner only draws on the game's map, through its own provider: RefreshAllData asks
-- self:GetMap() for the map id, takes RSMap.GetMapPOIs for it and calls AcquirePin for every
-- entity, for the "possible spots" of the entities whose overlay is switched on (pin:ShowOverlay)
-- and for the steps of the active guide. So the provider is run against a stand-in map, zone by
-- zone, and what it acquires is what CloudeMap draws.
--
-- A pin's tooltip and clicks are RareScanner's own (RSEntityPinMixin.OnMouseEnter / OnMouseDown:
-- left click toggles the spots, right click the guide, shift+alt+left filters the entity),
-- called on a hidden frame laid over our pin. Their state lives in RareScanner's database, so
-- what is switched on here shows on the game's map and the other way round.
---------------------------------------------------------------------------
local rsKey, rsProxy
local Null
Null = setmetatable({}, { __index = function() return Null end, __call = function() return nil end, __newindex = function() end })
local function NoPins() return function() return nil end end

local function RSFix(v)
    v = tonumber(v)
    if not v then return end
    if v >= 0 and v <= 1 then return v end
    return v / 10000
end

-- the stand-in map of one zone; got / dots / guides collect what RareScanner acquires
local function RSCanvas(mapID, prov, got, dots, guides)
    local canvas
    canvas = setmetatable({
        mapID = mapID,
        GetMapID = function() return mapID end,
        EnumeratePinsByTemplate = NoPins,
        RemoveAllPinsByTemplate = function() end,
        RemovePin = function() end,
        GetMapFrame = function() return { IsShown = function() return false end } end,
        AcquirePin = function(_, template, a, b, c, d, e, owner)
            if template == "RSOverlayTemplate" then
                if dots then
                    local x, y = RSFix(a), RSFix(b)
                    local poi = type(owner) == "table" and (owner.POI or owner)
                    if x and y then dots[#dots + 1] = { x, y, tonumber(c) or 1, tonumber(d) or 0.3, tonumber(e) or 0.3, type(poi) == "table" and poi.name } end
                end
                return Null
            end
            if template == "RSGuideTemplate" then
                if guides and type(a) == "table" then guides[#guides + 1] = a end
                return Null
            end
            if type(a) ~= "table" then return Null end
            if got then got[#got + 1] = a end
            -- a pin that behaves as RareScanner's own: its ShowOverlay puts the spots on this map
            local mix = (template == "RSGroupPinTemplate" and _G.RSGroupPinMixin) or _G.RSEntityPinMixin
            local pin = { POI = a, dataProvider = prov, GetMap = function() return canvas end }
            return setmetatable(pin, { __index = function(_, k)
                local v = type(mix) == "table" and mix[k]
                if type(v) == "function" then
                    return function(...) local ok, r1, r2 = pcall(v, ...) if ok then return r1, r2 end end
                end
                return Null
            end })
        end,
    }, { __index = function() return Null end })
    return canvas
end

local function RSProvider()
    return setmetatable({}, { __index = _G.RareScannerDataProviderMixin })
end

local function RSCollect(mapID)
    local mixin = _G.RareScannerDataProviderMixin
    if type(mixin) ~= "table" or type(mixin.RefreshAllData) ~= "function" then return end
    local got, dots, guides = {}, {}, {}
    local prov = RSProvider()
    local canvas = RSCanvas(mapID, prov, got, dots, guides)
    prov.GetMap = function() return canvas end
    local ok, err = pcall(prov.RefreshAllData, prov)
    if not ok then B.rsErr = err else B.rsErr = nil end
    return got, dots, guides
end

-- the hidden frame that stands in for RareScanner's pin (its tooltip anchors to it)
local function RSProxy(btn, pin)
    local mix = _G.RSEntityPinMixin
    if type(mix) ~= "table" or type(pin.poi) ~= "table" then return end
    if not rsProxy then
        rsProxy = CreateFrame("Frame", nil, UIParent)
        for k, v in pairs(mix) do                   -- as the game's Mixin() does
            if type(v) == "function" then rsProxy[k] = v end
        end
        for _, k in ipairs({ "Texture", "IconTexture", "HighlightRing", "HighlightRingAnim", "ShowPingAnim", "ShowSearchAnim" }) do
            if rawget(rsProxy, k) == nil then rsProxy[k] = Null end
        end
    end
    local prov = RSProvider()
    local canvas = RSCanvas(pin.map, prov)
    prov.GetMap = function() return canvas end
    rsProxy.POI, rsProxy.dataProvider = pin.poi, prov
    rsProxy.GetMap = function() return canvas end
    rsProxy:SetParent(btn)
    rsProxy:ClearAllPoints()
    rsProxy:SetAllPoints(btn)
    rsProxy:Show()
    return rsProxy, mix
end

-- RareScanner's tooltip, once shown, is held here: fixed where it appeared (so the map moving,
-- or our pin going away when the pointer leaves the window, does not take it along). On its way
-- from the pin the pointer has a quarter of a second to reach it; once on it, the tooltip stays
-- for as long as the pointer does, wherever that is on screen, and goes as soon as it leaves.
local rsHold = CreateFrame("Frame")
rsHold:Hide()
local hold
local function RSOver(r)
    local cx, cy = GetCursorPosition()
    return cx >= r[1] and cx <= r[2] and cy >= r[3] and cy <= r[4]
end
local function RSLet()
    local h = hold
    hold = nil
    rsHold:Hide()
    if not h then return end
    local mix = _G.RSEntityPinMixin
    if rsProxy and rsProxy.tooltip == h.tip and type(mix) == "table" and mix.OnMouseLeave then
        pcall(mix.OnMouseLeave, rsProxy)
    end
end
rsHold:SetScript("OnUpdate", function(_, dt)
    local h = hold
    if not h then rsHold:Hide() return end
    local tip = h.tip
    -- let go by RareScanner meanwhile (another tooltip of its own, or its own leave)
    if tip.key ~= h.key or (rsProxy and rsProxy.tooltip ~= tip) then hold = nil; rsHold:Hide() return end
    if tip:IsShown() then
        local l, r, b, t = tip:GetLeft(), tip:GetRight(), tip:GetBottom(), tip:GetTop()
        local es = tip:GetEffectiveScale()
        if l and r and b and t and es then h.rect = { l * es, r * es, b * es, t * es } end
    end
    local onTip = h.rect and RSOver(h.rect)
    if onTip then
        h.inside, h.away = true, 0
        if not tip:IsShown() then tip:Show() end        -- hidden from under the pointer: back it comes
    elseif h.inside then
        RSLet()                                         -- off the tooltip it was being read on
    elseif h.btn:IsVisible() and h.btn:IsMouseOver() then
        h.away = 0                                      -- still on the pin
    else
        h.away = h.away + dt
        if h.away > 0.25 then RSLet() end
    end
end)

local function RSEnter(btn, pin)
    if hold then RSLet() end
    local proxy, mix = RSProxy(btn, pin)
    local shown
    if proxy and mix.OnMouseEnter then
        local ok, err = pcall(mix.OnMouseEnter, proxy)
        shown = ok
        if not ok then B.rsTipErr = err end
    end
    local tip = shown and proxy.tooltip
    if type(tip) == "table" and tip.IsShown and tip:IsShown() and tip.GetLeft then
        local l, t = tip:GetLeft(), tip:GetTop()
        if l and t then
            tip:ClearAllPoints()
            tip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        hold = { tip = tip, key = tip.key, btn = btn, away = 0 }
        rsHold:Show()
        return
    end
    if not shown and GameTooltip then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(pin.name or "RareScanner")
        GameTooltip:Show()
    end
end
local function RSLeave()
    if hold then return end                         -- the hold decides when it goes
    local mix = _G.RSEntityPinMixin
    if rsProxy and type(mix) == "table" and mix.OnMouseLeave then pcall(mix.OnMouseLeave, rsProxy) end
end
local function RSClick(pin, button, btn)
    local proxy, mix = RSProxy(btn, pin)
    if not (proxy and mix.OnMouseDown) then return end
    local ok, err = pcall(mix.OnMouseDown, proxy, button)
    if not ok then B.rsErr = err end
    rsKey = nil                                     -- read RareScanner again: spots or guide changed
    -- and have RareScanner redraw the game's own map, if that is open (its provider is this very table)
    local real = _G.RareScannerDataProviderMixin
    if _G.WorldMapFrame and _G.WorldMapFrame:IsShown() and type(real) == "table" and real.RefreshAllData then
        pcall(real.RefreshAllData, real)
    end
    if P.onChange then P.onChange() end
end

-- A "possible spot" the size RareScanner gives it on the game's map: its 16-pixel texture scaled
-- from 1.4 (zone map not zoomed) to 2.5 (fully zoomed in), on the screen, whatever the zoom of
-- the canvas (RSOverlayMixin: SetScalingLimits(1, 1.4, 2.5); RSPinMixin:UpdateScale). Here the
-- game's zoom is taken from how wide the zone is on screen: about 700 pixels for the game's map
-- not zoomed in, twice that fully zoomed. Smaller than that, the spot shrinks with the zone, so
-- it covers the same share of the land as on the game's map.
local RS_ZONE_PX = 700
local function RSSpotSize(zonePx)
    local rel = zonePx / RS_ZONE_PX
    if rel < 1 then return 16 * 1.4 * rel end
    local t = min(1, rel - 1)
    return 16 * (1.4 + (2.5 - 1.4) * t)
end

local function RarePins(shown)
    if type(_G.RareScannerDataProviderMixin) ~= "table" then return end
    if not P.cats.rarescanner then
        P.RegisterCategory("rarescanner", { name = "RareScanner", addon = "RareScanner", order = 410, minScale = 0.8, size = 20 })
    end
    -- every few seconds anyway: what is switched on the game's own map shows here too
    local parts = { tostring(floor(Now() / 4)), P.IsEnabled("rarescanner") and "1" or "0" }
    for _, n in ipairs(shown) do parts[#parts + 1] = n.mapID end
    local key = table.concat(parts, ":")
    if key == rsKey then return end
    rsKey = key
    if not P.IsEnabled("rarescanner") then return end
    local list, sig = {}, {}
    local function Add(mapID, poi, gx, gy)
        local x, y = RSFix(poi.x) or gx, RSFix(poi.y) or gy
        if not (x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
        local tex = poi.Texture
        list[#list + 1] = { map = mapID, x = x, y = y, name = type(poi.name) == "string" and poi.name or "RareScanner", poi = poi,
            texture = tex, color = tex == nil and { 1, 0.3, 0.3, 1 } or nil, level = 3,      -- above its spots and guide steps
            onEnter = RSEnter, onLeave = RSLeave, onClick = RSClick }
        sig[#sig + 1] = mapID .. ":" .. tostring(poi.entityID) .. ":" .. floor(x * 1000) .. ":" .. floor(y * 1000) .. tostring(tex)
    end
    local nDots, nGuide = 0, 0
    for _, n in ipairs(shown) do
        local got, dots, guides = RSCollect(n.mapID)
        -- the spots first, so the pins lie on top of them
        for _, d in ipairs(dots or {}) do
            if d[1] >= 0 and d[1] <= 1 and d[2] >= 0 and d[2] <= 1 and #list < 3000 then
                -- soft and glowing, the size RareScanner gives them (additive: they light up the
                -- shaded, unexplored parts too, and neighbouring spots run together)
                list[#list + 1] = { map = n.mapID, x = d[1], y = d[2], size = 22, sizeFn = RSSpotSize, blend = "ADD", color = { d[3], d[4], d[5], 0.9 },
                    texture = "Interface\\AddOns\\RareScanner\\Media\\Icons\\Overlay.blp",
                    name = d[6] and tostring(d[6]) or "RareScanner", text = "Possible spot" }
                nDots = nDots + 1
            end
        end
        for _, g in ipairs(guides or {}) do
            local x, y = RSFix(g.x), RSFix(g.y)
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                local tip = type(g.tooltip) == "table" and g.tooltip or {}
                list[#list + 1] = { map = n.mapID, x = x, y = y, size = 18, texture = g.texture, level = 1,
                    name = tip.title or "RareScanner guide", text = tip.comment }
                nGuide = nGuide + 1
            end
        end
        for _, poi in ipairs(got or {}) do
            if poi.isGroup and type(poi.POIs) == "table" then
                local gx, gy = RSFix(poi.x), RSFix(poi.y)
                for _, sub in ipairs(poi.POIs) do
                    if type(sub) == "table" then Add(n.mapID, sub, gx, gy) end
                end
            else
                Add(n.mapID, poi)
            end
        end
    end
    sig[#sig + 1] = "dots" .. nDots .. "guide" .. nGuide
    local s = table.concat(sig, "|")
    if s ~= B.rsSig then                             -- only when something changed: a hover is not interrupted
        B.rsSig = s
        P.SetPins("rarescanner", list)
    end
    B.rs, B.rsDots = #list, nDots
end

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
B.GatherPins, B.RarePins = GatherPins, RarePins
local spyLast, spySig = 0, {}
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
local lastFind = -100

function B.Refresh() hbdDirty, hnDirty = true, true end

function B.Status()
    local names = {}
    for n in pairs(libs) do names[#names + 1] = n end
    table.sort(names)
    local HN = HandyNotes()
    local plugins = 0
    if HN then for _ in pairs(HN.plugins) do plugins = plugins + 1 end end
    local texLine = ""
    texLine = texLine .. " | quest markers: " .. (poiOK == nil and "not drawn yet" or (poiOK and "the game's own buttons" or "plain icons (the game's button template failed)"))
        .. (B.poiErr and (", error: " .. tostring(B.poiErr)) or "")
    local blobLine = ("quest areas: %s%s%s | "):format(
        blobOK == nil and "not drawn yet" or (blobOK and ("game frame working, %d quests in the log, last drawn %s"):format(B.blobQuests or 0, tostring(B.blobLast)) or "the game has no QuestPOIFrame here"),
        texLine, B.blobErr and (", error: " .. tostring(B.blobErr)) or "")
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
        .. ("ley lines %d, convergences %d (%d learned by LeyLines)%s | "):format(B.leyCount or 0, B.convCount or 0, B.leyLearned or 0, B.leyErr and (", error: " .. tostring(B.leyErr)) or "")
        .. ("party pins %d%s | "):format(#party.list, B.partyErr and (", error: " .. tostring(B.partyErr)) or "")
    return blobLine .. qs .. ("addon icons: Questie %s | pin libraries %s | HandyNotes %s%s"):format(
        B.questie == nil and "not seen" or (B.questie and "read" or "frames not available"),
        #names > 0 and table.concat(names, ", ") or "none found",
        HN and (plugins .. " plugins") or "not loaded",
        B.err and (" | last error: " .. tostring(B.err)) or "")
end

function B.Tick()
    local T = ns.prof.Time
    -- the libraries are looked for all the time (cheap), so icons are noted from the moment
    -- they are added, map open or not
    local now = Now()
    if now - lastFind > 5 then
        lastFind = now
        pcall(FindLibs)
    end
    pcall(B.SpySample)
    local f = _G.CloudeMapFrame
    if not (f and f.IsShown and f:IsShown()) then return end
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
    -- at most once a second while things change, and every few seconds anyway (an icon's
    -- look can change without it being added again)
    if next(libs) and ((hbdDirty and now - hbdLast >= 1) or now - hbdLast >= 5) then
        local ok, err = T("every 0.5 s: HereBeDragons pins", pcall, RebuildHBD, known)
        if not ok then B.err = err end
    end
    -- Questie: read again when the number of its icons changed (counted every 2 s, cheaply) or a
    -- switch was flipped; while it has shown nothing yet (it draws a while after logging in),
    -- every 2 s; and every 15 s regardless
    local qDue
    if _G.QuestieLoader then
        if qDirty and now - qLast >= 1 then qDue = true
        elseif now - qLast >= 15 then qDue = true
        elseif now - qLast >= 2 and (B.qTaken or 0) == 0 then qDue = true
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
    if now - spyLast >= 1.5 or B.spyDue then
        spyLast, B.spyDue = now, nil
        T("every 0.5 s: Spy", pcall, SpyPins, known)
    end
    local hnZones, hnKey = HNZones()
    if hnKey ~= B.hnKey then B.hnKey = hnKey; hnDirty = true; hnLast = 0 end
    zones = hnZones
    if (hnDirty and now - hnLast >= 1) or now - hnLast >= 15 then
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
-- Dungeon Journal (ForeverDungeonJournal): its dungeon map, shown in CloudeMap's window as a
-- mode of its own. The journal already lends its map panel to the game's world map
-- (Systems/WorldMapOverlay.lua); the same is done here: the panel is moved into a cover laid
-- over the whole map view and handed back when the mode ends, when the window closes or when
-- the journal asks for it. Nothing is asked of the journal's version: every piece used is
-- looked for by name, and the button only shows while the needed ones are there.
---------------------------------------------------------------------------
do
    local ui                    -- what CloudeMap.lua hands over when its window is built
    local dj = { on = false }   -- on: the mode; hosting: the panel is in our window right now
    local bg = { on = false, tiles = {}, pins = {} }    -- the battleground map (further down)
    local host, djBtn, pickBtn, pickMenu, bgBtn
    local BGSet

    local function Parts()
        local FDJ = _G.ForeverDungeonJournal_NS
        local journal = _G.ForeverDungeonJournalFrame
        if type(FDJ) ~= "table" or type(journal) ~= "table" then return end
        local panel = journal.dungeonMapPanel
        if type(panel) ~= "table" or type(FDJ.DUNGEON_MAPS) ~= "table" or type(FDJ.RenderCustomDungeonMap) ~= "function" then return end
        return FDJ, journal, panel
    end

    local function Call(FDJ, name, ...)
        local fn = FDJ[name]
        if type(fn) ~= "function" then return end
        local ok, a, b = pcall(fn, ...)
        if ok then return a, b end
        dj.err = name .. ": " .. tostring(a)
    end

    local function Locked(FDJ, name) return Call(FDJ, "IsDungeonMapLocked", name) and true or false end
    local function Title(FDJ, name)
        local t = Call(FDJ, "LocalizeDungeonName", name)
        return type(t) == "string" and t ~= "" and t or name
    end

    -- the dungeons that have a map, in the journal's own order
    local function List(FDJ)
        local out, seen = {}, {}
        for _, name in ipairs(type(FDJ.ORDER) == "table" and FDJ.ORDER or {}) do
            if type(name) == "string" and FDJ.DUNGEON_MAPS[name] and not seen[name] then seen[name] = true; out[#out + 1] = name end
        end
        local rest = {}
        for name in pairs(FDJ.DUNGEON_MAPS) do
            if type(name) == "string" and not seen[name] then rest[#rest + 1] = name end
        end
        table.sort(rest)
        for _, name in ipairs(rest) do out[#out + 1] = name end
        return out
    end

    -- which dungeon to open on: the one the hero is in, else the one picked here, else the
    -- journal's own current one, else the first that is not locked
    local function Choose(FDJ)
        local maps = FDJ.DUNGEON_MAPS
        local function Good(name) return type(name) == "string" and maps[name] and not Locked(FDJ, name) and name end
        return Good(Call(FDJ, "CurrentDungeon")) or Good(dj.name) or Good((Call(FDJ, "GetSelectedDungeon")))
            or (function() for _, name in ipairs(List(FDJ)) do if Good(name) then return name end end end)()
    end

    local function Render(reset)
        local FDJ, journal, panel = Parts()
        if not (FDJ and dj.hosting and dj.name) then return end
        local data = FDJ.DUNGEON_MAPS[dj.name]
        if not data then return end
        local was = Call(FDJ, "GetSelectedDungeon")
        Call(FDJ, "SetMapDungeon", dj.name)
        Call(FDJ, "SetupDungeonMapZoom")           -- the journal's own wheel zoom (1x to 4x) and drag
        local level = journal.dungeonMapFloor
        if reset or was ~= dj.name then
            Call(FDJ, "ResetDungeonMapView")
            level = Call(FDJ, "SavedMapFloor", dj.name, data) or (type(data.entrance) == "table" and data.entrance.floor) or 1
        end
        if type(journal.dungeonMapTitle) == "table" and journal.dungeonMapTitle.SetText then journal.dungeonMapTitle:SetText("") end
        Call(FDJ, "RenderCustomDungeonMap", data, level)
        if ui and ui.barText then ui.barText:SetText(Title(FDJ, dj.name)) end
        if dj.Units then dj.Units() end
    end

    -- The hero (and the group) on the journal's map. Inside instances the game gives addons no
    -- position, but it still draws units itself: a UnitPositionFrame told which map it covers
    -- places the arrow on its own (the way the game's world map and Carbonite do it). Its map is
    -- the floor shown; it covers the journal's art holder, which is exactly that map's 0..1.
    function dj.FloorMap(FDJ, data, level)
        local floor = data and data.floors and data.floors[level]
        local id = floor and tonumber(floor.uiMapID)
        if not id then return end
        -- the journal falls back to a map found by name when this client has no art under the id
        local ok, layers = pcall(C_Map.GetMapArtLayers, id)
        if not (ok and type(layers) == "table" and layers[1]) and type(FDJ.FindMapArtID) == "function" then
            local ok2, alt = pcall(FDJ.FindMapArtID, dj.name, floor)
            if ok2 and tonumber(alt) then id = tonumber(alt) end
        end
        return id
    end

    function dj.Units()
        local FDJ, journal = Parts()
        local holder = journal and journal.dungeonMapArtHolder
        local f = dj.units
        if not (FDJ and dj.hosting and dj.name and type(holder) == "table") then
            if f then f:Hide() end
            return
        end
        if f == nil then
            local ok, made = pcall(CreateFrame, "UnitPositionFrame", nil, holder, "UnitPositionFrameTemplate")
            if not ok or not made then dj.unitsErr = tostring(made); dj.units = false; return end
            f = made
            dj.units = f
            pcall(f.SetPinTexture, f, "player", "UI-WorldMapArrow")
            pcall(f.SetPinSize, f, "player", 26)
            pcall(f.SetPinSize, f, "party", 13)
            pcall(f.SetPinSize, f, "raid", 11)
            if f.SetUseClassColor then
                pcall(f.SetUseClassColor, f, "player", false)
                pcall(f.SetUseClassColor, f, "party", true)
                pcall(f.SetUseClassColor, f, "raid", true)
            end
            if f.SetShouldShowUnits then
                for _, u in ipairs({ "player", "party", "raid" }) do pcall(f.SetShouldShowUnits, f, u, true) end
            end
            if f.SetMouseOverUnitExcluded then pcall(f.SetMouseOverUnitExcluded, f, "player", true) end
            f:EnableMouse(false)
            -- the game moves the units; asked every frame as the game's map does, or at most as often
            -- as the update cap allows
            local acc = 0
            f:SetScript("OnUpdate", function(self, el)
                local cap = CloudeMapDB and CloudeMapDB.cap
                if cap then acc = acc + (el or 0); if acc < 1 / cap then return end; acc = 0 end
                -- nothing to do while the game has no map for the hero (most of Forever's dungeons,
                -- and outside): the game would draw nobody anyway
                if not dj.lastBest then return end
                dj.Place(self)
                if dj.unitMap then pcall(self.UpdatePlayerPins, self) end
            end)
        end
        if not f then return end
        if f:GetParent() ~= holder then f:SetParent(holder) end
        dj.unitRect = nil                                 -- placed again on the next frame
        f:SetFrameLevel(holder:GetFrameLevel() + 60)     -- the hero above the journal's pins
        f:Show()
    end

    -- Which map the unit frame covers and where on the journal's art. The game draws the hero
    -- only on the map it puts the hero on (GetBestMapForUnit). That is normally the floor shown,
    -- covering the whole art; when the game's map for the hero is another one (this client may
    -- number its dungeon maps differently from the journal), the frame takes the hero's map and
    -- covers only the part of the floor that map lies on (C_Map.GetMapRectOnMap).
    function dj.Place(f)
        local D, jr = Parts()
        local holder = jr and jr.dungeonMapArtHolder
        local floor = dj.hosting and D and jr and dj.FloorMap(D, D.DUNGEON_MAPS[dj.name], jr.dungeonMapFloor)
        local best = dj.lastBest
        local map, rect = floor, nil
        if floor and best and best ~= floor then
            local ok, x1, x2, y1, y2 = pcall(C_Map.GetMapRectOnMap, best, floor)
            if ok and tonumber(x1) and tonumber(x2) and tonumber(y1) and tonumber(y2) and not Secret(x1) and x2 > x1 and y2 > y1 then
                map, rect = best, { x1, x2, y1, y2 }
            end
        end
        local key = tostring(map) .. (rect and table.concat(rect, ",") or "") .. tostring(holder and holder:GetWidth())
        if key == dj.unitRect then return end
        dj.unitRect = key
        f:ClearAllPoints()
        if rect and holder then
            local w, h = holder:GetWidth(), holder:GetHeight()
            f:SetPoint("TOPLEFT", holder, "TOPLEFT", rect[1] * w, -rect[3] * h)
            f:SetSize(math.max(1, (rect[2] - rect[1]) * w), math.max(1, (rect[4] - rect[3]) * h))
        elseif holder then
            f:SetAllPoints(holder)
        end
        dj.unitMap = map
        dj.unitArea = rect and ("part %.2f-%.2f x %.2f-%.2f of the floor"):format(rect[1], rect[2], rect[3], rect[4]) or "the whole floor"
        if map then
            if not pcall(f.SetUiMapID, f, map) then dj.unitMap = nil end
            if f.SetNeedsFullUpdate then pcall(f.SetNeedsFullUpdate, f) end
        end
    end

    -- inside, the floor the hero is on is shown whenever the hero changes floor (a floor picked by
    -- hand stays until the hero moves to another one)
    function dj.FollowFloor()
        local FDJ, journal = Parts()
        if not (FDJ and dj.hosting and dj.name and journal) then return end
        local inside = IsInInstance and IsInInstance()
        if Secret(inside) or not inside then dj.lastBest = nil; return end
        local ok, best = pcall(C_Map.GetBestMapForUnit, "player")
        if not ok or Secret(best) or not tonumber(best) or best == dj.lastBest then return end
        dj.lastBest = best
        dj.unitRect = nil                                -- the unit frame is placed again
        local data = FDJ.DUNGEON_MAPS[dj.name]
        for i = 1, data and data.floors and #data.floors or 0 do
            if dj.FloorMap(FDJ, data, i) == best then
                if i ~= journal.dungeonMapFloor then Call(FDJ, "RenderCustomDungeonMap", data, i); dj.Units() end
                return
            end
        end
    end

    local function Release()
        if not dj.hosting then return end
        dj.hosting = false
        if dj.units then dj.units:Hide() end
        local _, journal, panel = Parts()
        local s = dj.saved
        dj.saved = nil
        if panel and s then
            panel:Hide()
            panel:SetParent(s.parent)
            panel:ClearAllPoints()
            for _, p in ipairs(s.points) do panel:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            if s.strata then panel:SetFrameStrata(s.strata) end
            if s.level then panel:SetFrameLevel(s.level) end
            if s.shown and journal and journal:IsShown() then panel:Show() end
        end
        if host then host:Hide() end
    end

    -- fit: the whole map fitted to the window (the journal's zoom back to 1x, its floor the one
    -- it opens on); otherwise the view stays as it is
    local function Take(fit)
        local FDJ, journal, panel = Parts()
        if not (FDJ and ui and dj.on) then return false end
        if not ui.frame:IsShown() then dj.needFit = dj.needFit or fit; return false end      -- taken when the window opens
        fit = fit or dj.needFit
        dj.needFit = nil
        if not dj.hosting then
            -- lent to the game's world map just now: the journal takes it back first
            if dj.detach then pcall(dj.detach) end
            if not host then
                host = CreateFrame("Frame", nil, ui.view)
                host:SetAllPoints(ui.view)
                local tex = host:CreateTexture(nil, "BACKGROUND")
                tex:SetAllPoints()
                tex:SetColorTexture(0.03, 0.025, 0.02, 1)
                host:EnableMouse(true)          -- nothing of the map underneath is reached
                host:EnableMouseWheel(true)
                host:SetScript("OnMouseWheel", function() end)
                host:SetScript("OnSizeChanged", function()
                    if dj.hosting and not dj.sizing and C_Timer and C_Timer.After then
                        dj.sizing = true
                        C_Timer.After(0, function() dj.sizing = false; pcall(Render, false) end)
                    end
                end)
            end
            host:SetFrameLevel(ui.view:GetFrameLevel() + 500)       -- above every layer of the map, the death marker included
            if ui.grip then ui.grip:SetFrameLevel(host:GetFrameLevel() + 20) end
            host:Show()
            local s = { parent = panel:GetParent(), points = {}, strata = panel:GetFrameStrata(), level = panel:GetFrameLevel(),
                shown = panel:IsShown() }
            for i = 1, panel:GetNumPoints() do
                local a, rel, b, x, y = panel:GetPoint(i)
                s.points[#s.points + 1] = { a, rel, b, x, y }
            end
            dj.saved, dj.hosting = s, true
            panel:SetParent(host)
            panel:ClearAllPoints()
            panel:SetAllPoints(host)
            panel:SetFrameStrata(host:GetFrameStrata())
            panel:SetFrameLevel(host:GetFrameLevel() + 1)
            -- the journal's pages hide the map panel when they refresh: while it is here, it comes straight back
            if not panel.cloudeHideHook then
                panel.cloudeHideHook = true
                panel:HookScript("OnHide", function(self)
                    if dj.hosting and C_Timer and C_Timer.After then
                        C_Timer.After(0, function() if dj.hosting and self:GetParent() == host then self:Show() end end)
                    end
                end)
            end
        end
        panel:Show()
        Render(fit)
        -- again once the panel has its size in our window, so the fit is to the window
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() pcall(Render, false) end)
            C_Timer.After(0.1, function() pcall(Render, false) end)
        end
        return true
    end

    -- Another map takes the window over: ours stops being updated (ns.paused, CloudeMap.lua) and
    -- every layer of it is hidden, so nothing of it is drawn under the cover. They come back as
    -- they were when the mode ends.
    local function Pause()
        local on = dj.on or bg.on
        ns.paused = on or nil
        if not ui then return end
        if on then
            dj.hidden = dj.hidden or {}
            for _, child in ipairs({ ui.view:GetChildren() }) do
                if child ~= host and child ~= bg.host and child:IsShown() then
                    child:Hide()
                    dj.hidden[#dj.hidden + 1] = child
                end
            end
        elseif dj.hidden then
            for _, child in ipairs(dj.hidden) do child:Show() end
            dj.hidden = nil
        end
    end

    -- the toolbar and the title bar, for whichever map is shown: ours, the journal's or the battleground's
    local function Style()
        if not (ui and djBtn) then return end
        local on = dj.on or bg.on
        djBtn.SetOn(dj.on)
        bgBtn.SetOn(bg.on)
        for _, b in ipairs({ ui.followBtn, ui.modeBtn }) do if on then b:Hide() else b:Show() end end
        if dj.on then pickBtn:Show() else pickBtn:Hide() end
        ui.tools.Layout()
        -- the title bar names the map shown
        if on then
            ui.info:SetText("")
            if ns.infoFit then ns.infoFit() end
        else
            ui.barText:SetText("")
        end
    end

    local function SetOn(on, quiet)
        local FDJ = Parts()
        on = on and FDJ and true or false
        if on and bg.on then BGSet(false) end
        if on then
            local name = Choose(FDJ)
            if not name then
                if not quiet and ns.Say then ns.Say("Dungeon Journal has no dungeon map to show (in its RPG Mode they are locked until played).") end
                on = false
            else
                dj.name = name
            end
        end
        dj.on = on
        Pause()
        if pickMenu then pickMenu:Hide() end
        Style()
        if on then
            local ok, err = pcall(Take, true)
            if not ok then dj.err = tostring(err); dj.on = false; Pause(); pcall(Release); Style() end
        else
            pcall(Release)
            if P.onChange then P.onChange() end         -- the map is drawn again
        end
    end

    local function Pick()
        local FDJ = Parts()
        if not FDJ then return end
        if pickMenu and pickMenu:IsShown() then pickMenu:Hide() return end
        if not pickMenu then
            pickMenu = CreateFrame("Frame", nil, ui.frame)
            pickMenu:SetFrameStrata("DIALOG")
            pickMenu:SetClampedToScreen(true)
            pickMenu:EnableMouse(true)
            local bg = pickMenu:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.06, 0.07, 0.96)
            pickMenu.rows = {}
        end
        local names = List(FDJ)
        local ROWS, RW, RH = 18, 190, 18
        local cols = math.max(1, math.ceil(#names / ROWS))
        local perCol = math.ceil(#names / cols)
        for i, name in ipairs(names) do
            local r = pickMenu.rows[i]
            if not r then
                r = CreateFrame("Button", nil, pickMenu)
                r:SetSize(RW, RH)
                local hl = r:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.15)
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -4, 0)
                r.text:SetJustifyH("LEFT")
                r.text:SetWordWrap(false)
                r:SetScript("OnClick", function(self)
                    pickMenu:Hide()
                    if self.locked then return end
                    dj.name = self.name
                    if dj.on then pcall(Take, true) end
                end)
                pickMenu.rows[i] = r
            end
            local col, row = floor((i - 1) / perCol), (i - 1) % perCol
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", pickMenu, "TOPLEFT", 4 + col * RW, -4 - row * RH)
            r.name, r.locked = name, Locked(FDJ, name)
            r.text:SetText(Title(FDJ, name))
            if r.locked then r.text:SetTextColor(0.45, 0.45, 0.45)
            elseif name == dj.name then r.text:SetTextColor(1, 0.82, 0)
            else r.text:SetTextColor(1, 1, 1) end
            r:Show()
        end
        for i = #names + 1, #pickMenu.rows do pickMenu.rows[i]:Hide() end
        pickMenu:SetSize(8 + cols * RW, 8 + perCol * RH)
        pickMenu:ClearAllPoints()
        pickMenu:SetPoint("BOTTOMRIGHT", pickBtn, "TOPRIGHT", 0, 6)
        pickMenu:Show()
    end

    -- the journal's own doors: a boss or quest spot clicked here opens the journal the way it
    -- does from the game's map, and its Map tab gets the panel back when it is opened
    local function Wrap(FDJ)
        if dj.wrapped == FDJ then return end
        dj.wrapped = FDJ
        local attached, detach = FDJ.IsWorldMapOverlayAttached, FDJ.DetachWorldMapOverlay
        dj.detach = type(detach) == "function" and detach or nil
        dj.attached = type(attached) == "function" and attached or nil
        FDJ.IsWorldMapOverlayAttached = function(...)
            if dj.hosting then return true end
            if dj.attached then return dj.attached(...) end
            return false
        end
        FDJ.DetachWorldMapOverlay = function(...)
            if dj.hosting and not dj.taking then SetOn(false, true) end
            if dj.detach then return dj.detach(...) end
        end
    end

    -----------------------------------------------------------------------
    -- Battleground map. Battlegrounds are not part of the stitched world, so theirs is a map of
    -- its own, like the journal's: the game's art for the map the hero is on, fitted to the view,
    -- with the game's landmarks (bases, towers, graveyards and their state), its vignettes
    -- (flags, where the client has them), the team, the hero's body and the hero. The BG button
    -- only shows inside a battleground.
    -----------------------------------------------------------------------
    local function InBG()
        if C_PvP and C_PvP.IsBattleground then
            local ok, v = pcall(C_PvP.IsBattleground)
            if ok and not Secret(v) and v then return true end
        end
        if IsInInstance then
            local ok, inside, kind = pcall(IsInInstance)
            if ok and not Secret(kind) and inside and kind == "pvp" then return true end
        end
        return false
    end

    local function XY(pos)
        if type(pos) ~= "table" then return end
        local x, y = pos.x, pos.y
        if x == nil and pos.GetXY then x, y = pos:GetXY() end
        if Secret(x) or Secret(y) or type(x) ~= "number" or type(y) ~= "number" then return end
        if x <= 0 or x >= 1 or y <= 0 or y >= 1 then return end
        return x, y
    end
    local function Plain(v) if not Secret(v) then return v end end
    local function HasAtlas(name)
        if type(name) ~= "string" or name == "" then return false end
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, name)
            return ok and info ~= nil
        end
        return false
    end

    local function BGFit()
        local art = bg.art
        if not (art and bg.lw) then return end
        local W, H = bg.host:GetWidth() or 0, bg.host:GetHeight() or 0
        if W < 10 or H < 10 then return end
        local k = min(W / bg.lw, H / bg.lh)
        bg.k = k
        art:SetSize(bg.lw * k, bg.lh * k)
        local cols = max(1, math.ceil(bg.lw / bg.tw))
        for i, t in ipairs(bg.tiles) do
            if i <= (bg.count or 0) then
                local col, row = (i - 1) % cols, floor((i - 1) / cols)
                t:ClearAllPoints()
                t:SetSize(bg.tw * k, bg.th * k)
                t:SetPoint("TOPLEFT", art, "TOPLEFT", col * bg.tw * k, -row * bg.th * k)
            end
        end
    end

    -- the art of the map the hero is on; true when there is one to show
    local function BGArt()
        local map = Plain(C_Map.GetBestMapForUnit("player"))
        if type(map) ~= "number" then return false end
        if map == bg.map and bg.lw then return true end
        local layers = ns.GetLayers and ns.GetLayers(map)
        local L = type(layers) == "table" and layers[1]
        local tex = ns.GetTextures and ns.GetTextures(map, 1)
        if not (type(L) == "table" and type(tex) == "table" and #tex > 0) then return false end
        bg.map = map
        bg.lw, bg.lh = tonumber(Plain(L.layerWidth)) or 1002, tonumber(Plain(L.layerHeight)) or 668
        bg.tw, bg.th = tonumber(Plain(L.tileWidth)) or 256, tonumber(Plain(L.tileHeight)) or 256
        bg.count = #tex
        for i = 1, #tex do
            local t = bg.tiles[i]
            if not t then t = bg.art:CreateTexture(nil, "ARTWORK"); bg.tiles[i] = t end
            t:SetTexture(tex[i])
            t:Show()
        end
        for i = #tex + 1, #bg.tiles do bg.tiles[i]:Hide() end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        bg.title = type(info) == "table" and Plain(info.name) or "Battleground"
        BGFit()
        return true
    end

    local function BGPin(i)
        local b = bg.pins[i]
        if b then return b end
        b = CreateFrame("Button", nil, bg.over)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:SetScript("OnEnter", function(self)
            if not (self.name and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.name)
            if self.note and self.note ~= "" then GameTooltip:AddLine(self.note, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        bg.pins[i] = b
        return b
    end

    -- every icon again: a handful of them, five times a second
    local function BGUpdate()
        if not (bg.on and bg.host and bg.host:IsVisible()) then return end
        if not BGArt() then return end
        local map, art, k = bg.map, bg.art, bg.k
        if not k then return end
        local n, st = 0, { poi = 0, vig = 0, team = 0 }
        local base = bg.over:GetFrameLevel()
        local function Put(x, y, size, level, name, note)
            n = n + 1
            local b = BGPin(n)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("CENTER", art, "TOPLEFT", x * bg.lw * k, -y * bg.lh * k)
            b:SetFrameLevel(base + level)
            b.name, b.note = name, note
            b.tex:SetTexCoord(0, 1, 0, 1)
            b.tex:SetVertexColor(1, 1, 1, 1)
            if b.tex.SetRotation then b.tex:SetRotation(0) end
            b:EnableMouse(name ~= nil)
            b:Show()
            return b.tex
        end
        local coords = (C_Minimap and C_Minimap.GetPOITextureCoords) or _G.GetPOITextureCoords
        local function Sheet(tex, index)
            if type(coords) ~= "function" or type(index) ~= "number" then return false end
            local ok, l, r, t, b = pcall(coords, index)
            if not (ok and type(l) == "number" and type(b) == "number") then return false end
            tex:SetTexture("Interface\\Minimap\\POIIcons")
            tex:SetTexCoord(l, r, t, b)
            return true
        end

        -- landmarks
        if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIInfo then
            local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, map)
            for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
                local ok2, poi = pcall(C_AreaPoiInfo.GetAreaPOIInfo, map, id)
                local x, y = XY(ok2 and type(poi) == "table" and poi.position or nil)
                if x then
                    local atlas, index = Plain(poi.atlasName), Plain(poi.textureIndex)
                    if HasAtlas(atlas) or type(index) == "number" then
                        local tex = Put(x, y, 22, 1, Plain(poi.name), Plain(poi.description))
                        if not (HasAtlas(atlas) and pcall(tex.SetAtlas, tex, atlas)) and not Sheet(tex, index) then
                            tex:SetColorTexture(1, 0.82, 0, 1)
                        end
                        st.poi = st.poi + 1
                    end
                end
            end
        end
        -- vignettes (flags and the like)
        if C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignettePosition and C_VignetteInfo.GetVignetteInfo then
            local ok, ids = pcall(C_VignetteInfo.GetVignettes)
            for _, guid in ipairs(ok and type(ids) == "table" and ids or {}) do
                local ok2, pos = pcall(C_VignetteInfo.GetVignettePosition, guid, map)
                local x, y = XY(ok2 and pos or nil)
                local ok3, v = pcall(C_VignetteInfo.GetVignetteInfo, guid)
                local atlas = ok3 and type(v) == "table" and Plain(v.atlasName)
                if x and HasAtlas(atlas) then
                    local tex = Put(x, y, 24, 2, Plain(v.name))
                    pcall(tex.SetAtlas, tex, atlas)
                    st.vig = st.vig + 1
                end
            end
        end
        -- the team
        local raid = IsInRaid and IsInRaid()
        for i = 1, (IsInGroup and IsInGroup()) and (raid and 40 or 4) or 0 do
            local unit = (raid and "raid" or "party") .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, unit)
                local x, y = XY(ok and pos or nil)
                if x then
                    local name = Plain(UnitName(unit))
                    local _, class = UnitClass(unit)
                    class = Plain(class)
                    local dead = UnitIsDeadOrGhost and Plain(UnitIsDeadOrGhost(unit))
                    local tex = Put(x, y, 14, 3, name, dead and "dead" or nil)
                    if not (HasAtlas("WhiteCircle-RaidBlips") and pcall(tex.SetAtlas, tex, "WhiteCircle-RaidBlips")) then
                        tex:SetColorTexture(1, 1, 1, 1)
                    end
                    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                    if dead then tex:SetVertexColor(0.6, 0.6, 0.6, 1)
                    elseif cc then tex:SetVertexColor(cc.r, cc.g, cc.b, 1)
                    else tex:SetVertexColor(0.4, 0.6, 1, 1) end
                    st.team = st.team + 1
                end
            end
        end
        -- the hero's body
        if C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and UnitIsDeadOrGhost and Plain(UnitIsDeadOrGhost("player")) then
            local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, map)
            local x, y = XY(ok and pos or nil)
            if x then
                local tex = Put(x, y, 24, 4, "Your corpse")
                if not Sheet(tex, 8) then tex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull") end
                tex:SetVertexColor(1, 1, 1, 0.85)
            end
        end
        -- the hero, on top
        do
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
            local x, y = XY(ok and pos or nil)
            st.hero = x and true or false
            if x then
                local tex = Put(x, y, 30, 6)
                tex:SetTexture("Interface\\Minimap\\MinimapArrow")
                local facing = GetPlayerFacing and Plain(GetPlayerFacing())
                if type(facing) == "number" and tex.SetRotation then tex:SetRotation(facing) end
            end
        end
        for i = n + 1, #bg.pins do bg.pins[i]:Hide() end
        bg.stat = st
    end

    BGSet = function(on, quiet)
        on = on and ui and InBG() and true or false
        if on and dj.on then SetOn(false, true) end
        if on then
            if not bg.host then
                local h = CreateFrame("Frame", nil, ui.view)
                h:SetAllPoints(ui.view)
                local tex = h:CreateTexture(nil, "BACKGROUND")
                tex:SetAllPoints()
                tex:SetColorTexture(0.03, 0.025, 0.02, 1)
                h:EnableMouse(true)             -- nothing of the map underneath is reached
                h:EnableMouseWheel(true)
                h:SetScript("OnMouseWheel", function() end)
                h:SetScript("OnSizeChanged", function() pcall(BGFit) end)
                bg.host = h
                bg.art = CreateFrame("Frame", nil, h)
                bg.art:SetPoint("CENTER")
                if bg.art.SetClipsChildren then bg.art:SetClipsChildren(true) end    -- the last tiles run past the map's edge
                bg.over = CreateFrame("Frame", nil, h)      -- the icons: not clipped by the art
                bg.over:SetAllPoints(h)
            end
            bg.host:SetFrameLevel(ui.view:GetFrameLevel() + 500)
            bg.art:SetFrameLevel(bg.host:GetFrameLevel() + 1)
            bg.over:SetFrameLevel(bg.host:GetFrameLevel() + 5)
            if ui.grip then ui.grip:SetFrameLevel(bg.host:GetFrameLevel() + 20) end
            bg.map = nil
            bg.host:Show()
            bg.on = true
            if not BGArt() then
                bg.on = false
                bg.host:Hide()
                if not quiet and ns.Say then ns.Say("the game gave no map for this battleground (/cmap debug)") end
            end
        else
            bg.on = false
            if bg.host then bg.host:Hide() end
        end
        Pause()
        Style()
        if bg.on then
            ui.barText:SetText(bg.title or "Battleground")
            pcall(BGUpdate)
        elseif not dj.on and P.onChange then
            P.onChange()                        -- our map is drawn again
        end
    end
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.2, function()
            if bg.on then
                local ok, err = pcall(BGUpdate)
                if not ok then bg.err = tostring(err) end
            end
        end)
    end

    function ns.onUI(t)
        ui = t
        djBtn = t.MakeButton(t.tools, "", 22, function() SetOn(not dj.on) end,
            function() return dj.on and "Back to the world map" or "Dungeon Journal: show its dungeon map in this window" end,
            "Interface\\Icons\\INV_Misc_Book_09")
        djBtn:Hide()
        pickBtn = t.MakeButton(t.tools, "", 22, Pick, "Pick the dungeon to show", "Interface\\Icons\\INV_Scroll_03")
        pickBtn.SetOn(true)
        pickBtn:Hide()
        local horde = UnitFactionGroup and UnitFactionGroup("player") == "Horde"
        bgBtn = t.MakeButton(t.tools, "", 22, function() BGSet(not bg.on) end,
            function() return bg.on and "Back to the world map" or "Battleground: show its map in this window" end,
            horde and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02")
        bgBtn:Hide()
        for _, b in ipairs({ djBtn, pickBtn, bgBtn }) do t.tools.list[#t.tools.list + 1] = b end
        Style()
        -- the window closed: the journal has its panel back; opened again: the mode carries on
        t.frame:HookScript("OnHide", function() pcall(Release); if pickMenu then pickMenu:Hide() end end)
        t.frame:HookScript("OnShow", function() if dj.on then pcall(Take, false) end end)
        -- into a dungeon: its map; out again: ours. Checked after each loading screen and zone
        -- change (twice, as the journal may need a moment to know the dungeon) and every two seconds.
        local ev = CreateFrame("Frame")
        pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
        pcall(ev.RegisterEvent, ev, "ZONE_CHANGED_NEW_AREA")
        ev:SetScript("OnEvent", function()
            if not (C_Timer and C_Timer.After) then return end
            C_Timer.After(0.5, function() pcall(B.DungeonAuto) end)
            C_Timer.After(2, function() pcall(B.DungeonAuto) end)
        end)
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() pcall(B.DungeonAuto) end) end
    end

    -- the dungeon the hero is in (by the journal), or nil; and whether the hero is in a dungeon or raid at all
    local function Here(FDJ)
        local ok, inside, kind = pcall(IsInInstance)
        if not ok or Secret(kind) or not inside or (kind ~= "party" and kind ~= "raid") then return nil, false end
        local name = Call(FDJ, "CurrentDungeon")
        if type(name) == "string" and FDJ.DUNGEON_MAPS[name] and not Locked(FDJ, name) then return name, true end
        return nil, true
    end

    function B.DungeonAuto()
        if not (ui and djBtn) then return end
        local FDJ = Parts()
        if not FDJ then return end
        local name, inside = Here(FDJ)
        if name and name ~= dj.auto then
            -- walked in (or on into another wing): that dungeon's map, fitted to the window
            dj.auto = name
            if bg.on then BGSet(false, true) end
            dj.name = name
            if dj.on then pcall(Take, true) else SetOn(true, true) end
        elseif not inside and dj.auto then
            -- walked out: our map again (switched off by hand inside, it stays off)
            dj.auto = nil
            if dj.on then SetOn(false, true) end
        end
    end

    -- twice a second while the window is open: the button comes and goes with the journal,
    -- and the panel is brought back if something else moved it away
    function B.DungeonTick()
        if not (ui and djBtn) then return end
        -- the BG button comes with the battleground and goes with it, the mode too
        local inBG = InBG()
        if inBG ~= bgBtn:IsShown() then
            if inBG then bgBtn:Show() else bgBtn:Hide() end
            if not inBG and bg.on then BGSet(false, true) else Style() end
        end
        local FDJ, journal, panel = Parts()
        if FDJ then Wrap(FDJ) end
        local have = FDJ and true or false
        if have ~= djBtn:IsShown() then
            if not have and dj.on then SetOn(false, true) end
            if have then djBtn:Show() else djBtn:Hide() end
            Style()
        end
        if not (have and dj.on) then return end
        if not dj.hosting then
            pcall(Take, false)
        elseif panel:GetParent() ~= host then
            -- taken to the game's world map: left there until that map lets go of it
            if not (dj.attached and dj.attached()) then dj.hosting = false; dj.saved = nil; pcall(Take, false) end
        elseif not panel:IsShown() then
            panel:Show()
            pcall(Render, false)
        end
        if dj.hosting then pcall(dj.FollowFloor) end
    end

    -- what the hero arrow on the journal's map is doing (for /cmap status)
    function dj.UnitStatus()
        local f = dj.units
        local D, jr = Parts()
        local data = D and D.DUNGEON_MAPS[dj.name]
        local floors = {}
        for i = 1, data and data.floors and #data.floors or 0 do floors[#floors + 1] = tostring(dj.FloorMap(D, data, i)) end
        local hide
        if dj.unitMap and C_Map.GetMapDisplayInfo then
            local ok, h = pcall(C_Map.GetMapDisplayInfo, dj.unitMap)
            hide = ok and tostring(h) or "?"
        end
        local uid
        if f.GetUiMapID then local ok, v = pcall(f.GetUiMapID, f); uid = ok and tostring(v) or "?" end
        local name = function(id)
            local ok, i = pcall(C_Map.GetMapInfo, tonumber(id) or 0)
            return ok and type(i) == "table" and i.name and (" " .. tostring(i.name)) or ""
        end
        return (" | hero arrow: frame on map %s%s (frame says %s, %s, %dx%d, %s), floor %s of maps %s, game puts the hero on %s%s, map hides icons: %s"):format(
            tostring(dj.unitMap), name(dj.unitMap), tostring(uid), tostring(dj.unitArea),
            math.floor((f:GetWidth() or 0) + 0.5), math.floor((f:GetHeight() or 0) + 0.5), f:IsVisible() and "visible" or "not visible",
            tostring(jr and jr.dungeonMapFloor), table.concat(floors, "/"), tostring(dj.lastBest), name(dj.lastBest), tostring(hide))
    end

    function B.DungeonTest(what) if what == "pick" then Pick() elseif what == "bg" then BGSet(not bg.on) else SetOn(what) end end
    -- what the game tells addons about the hero inside (for /cmap status)
    function B.InstancePos()
        local inside = IsInInstance and IsInInstance()
        if Secret(inside) or not inside then return "" end
        local ok, best = pcall(C_Map.GetBestMapForUnit, "player")
        local pos = "none"
        if ok and tonumber(best) and not Secret(best) then
            local ok2, p = pcall(C_Map.GetPlayerMapPosition, best, "player")
            if ok2 and p then
                local x, y = p.x, p.y
                pos = (Secret(x) or Secret(y)) and "secret" or (tonumber(x) and ("%.3f, %.3f"):format(x, y)) or "empty"
            end
        end
        local ok3, wx = pcall(UnitPosition, "player")
        return (" | inside: map %s, map position %s, world position %s"):format(tostring(ok and best),
            pos, (ok3 and wx ~= nil) and (Secret(wx) and "secret" or "given") or "none")
    end
    function B.DungeonStatus()
        local FDJ = Parts()
        return ("Dungeon Journal %s%s"):format(
            FDJ and (dj.on and ("map shown: " .. tostring(dj.name)) or "found") or (_G.ForeverDungeonJournal_NS and "loaded, but its map panel was not found" or "not loaded"),
            dj.err and (", error: " .. tostring(dj.err)) or "")
            .. (dj.units == false and (" | hero arrow: no UnitPositionFrame (" .. tostring(dj.unitsErr) .. ")")
                or dj.units and dj.hosting and dj.UnitStatus() or "")
            .. B.InstancePos()
            .. (" | battleground: %s%s"):format(
                not InBG() and "not in one" or (bg.on and ("map %s shown, %d tiles, %d landmarks, %d vignettes, %d of the team, hero %s"):format(
                    tostring(bg.map), bg.count or 0, bg.stat and bg.stat.poi or 0, bg.stat and bg.stat.vig or 0, bg.stat and bg.stat.team or 0,
                    bg.stat and bg.stat.hero and "placed" or "has no position here") or "inside one, map not shown"),
                bg.err and (", error: " .. tostring(bg.err)) or "")
    end
end


---------------------------------------------------------------------------
-- Minimap button: a click shows or hides the map; dragging moves the button round the minimap
-- (its place is kept in CloudeMapDB.minimapAngle, in degrees).
---------------------------------------------------------------------------
do
    local btn
    local function Place()
        local db = _G.CloudeMapDB
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
                if type(_G.CloudeMapDB) == "table" then _G.CloudeMapDB.minimapAngle = deg end
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


---------------------------------------------------------------------------
-- Ley lines (Leylines.lua), two toggles: the fissures the Alliance absorbs and the elemental
-- convergences (tornadoes) the Horde absorbs. Until switched by hand, the hero's own faction's
-- kind is on and the other off (a character of neither has both on). With the LeyLines addon installed, the
-- places it has learned in play are added to the shipped ones (read from LeyLinesDB by name, any
-- version that keeps nodes[map] = { {x, y, ..., kind}, ... }); a place already known within
-- about a hundredth of the map is not doubled.
---------------------------------------------------------------------------
do
    local ICON = {
        -- the game's own minimap marker for them (an atlas of the minimap icon sheet; the same for both)
        L = { atlas = "MagePortalAlliance", fixed = true, name = "Ley Line" },
        V = { atlas = "MagePortalAlliance", fixed = true, name = "Elemental Convergence" },
    }
    local TC = { 0.08, 0.92, 0.08, 0.92 }

    -- Both kinds: the game's minimap marker (above). The tracking menu is still read, for
    -- /cmap debug, and would only replace a kind not marked fixed.
    local WORDS = { L = { "ley" }, V = { "convergence", "skysight", "elemental" } }
    local function GameIcons()
        local n = C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes()
            or (GetNumTrackingTypes and GetNumTrackingTypes())
        local seen = {}
        for i = 1, tonumber(n) or 0 do
            local ok, a, b = pcall(C_Minimap and C_Minimap.GetTrackingInfo or GetTrackingInfo, i)
            local name, tex
            if ok and type(a) == "table" then name, tex = a.name, a.texture elseif ok then name, tex = a, b end
            if type(name) == "string" and not Secret(name) then
                seen[#seen + 1] = name .. (tex and (" (" .. tostring(tex) .. ")") or "")
                local low = name:lower()
                for kind, words in pairs(WORDS) do
                    for _, w in ipairs(words) do
                        if low:find(w, 1, true) and tex and not Secret(tex) and not ICON[kind].fixed then
                            ICON[kind].texture, ICON[kind].tc, ICON[kind].game = tex, { 0, 1, 0, 1 }, name
                        end
                    end
                end
            end
        end
        B.trackingTypes = seen
    end
    local CAT = { L = "leyline", V = "convergence" }
    P.RegisterCategory("leyline", { name = "Ley lines (Alliance)", order = 8, minScale = 0, size = 18,
        atlas = ICON.L.atlas })
    P.RegisterCategory("convergence", { name = "Elemental convergences (Horde)", order = 9, minScale = 0, size = 18,
        atlas = ICON.V.atlas })

    local seen = ""
    -- the other faction's kind starts switched off (a choice made by hand is kept)
    local function Defaults()
        local f = UnitFactionGroup and UnitFactionGroup("player")
        local cats = P.cats or {}
        if cats.leyline then cats.leyline.default = f ~= "Horde" end
        if cats.convergence then cats.convergence.default = f ~= "Alliance" end
    end
    local function Read()
        local data = ns.LEYLINES
        if type(data) ~= "table" then return end
        Defaults()
        pcall(GameIcons)
        for kind, cat in pairs(CAT) do
            local c = P.cats[cat]
            if c then c.atlas, c.texture, c.texCoord = ICON[kind].atlas, ICON[kind].texture, not ICON[kind].atlas and (ICON[kind].tc or TC) or nil end
        end
        local lists, byMap, learned = { L = {}, V = {} }, { L = {}, V = {} }, 0
        local function Add(kind, map, x, y, note)
            if not (lists[kind] and type(map) == "number" and type(x) == "number" and type(y) == "number") then return end
            if x <= 0 or x >= 1 or y <= 0 or y >= 1 then return end
            local here = byMap[kind][map]
            if not here then here = {}; byMap[kind][map] = here end
            for _, q in ipairs(here) do
                if math.abs(q[1] - x) < 0.01 and math.abs(q[2] - y) < 0.01 then return end
            end
            here[#here + 1] = { x, y }
            local icon, list = ICON[kind], lists[kind]
            list[#list + 1] = { map = map, x = x, y = y, atlas = icon.atlas, texture = not icon.atlas and icon.texture or nil,
                texCoord = not icon.atlas and (icon.tc or TC) or nil, name = icon.name, text = note }
            return true
        end
        for kind, maps in pairs(data) do
            for map, xy in pairs(maps) do
                for i = 1, #xy - 1, 2 do Add(kind, map, xy[i], xy[i + 1]) end
            end
        end
        local db = _G.LeyLinesDB
        if type(db) == "table" and type(db.nodes) == "table" then
            for map, nodes in pairs(db.nodes) do
                if type(nodes) == "table" then
                    for _, n in ipairs(nodes) do
                        if type(n) == "table" then
                            local m = tonumber(n.map or n[3]) or tonumber(map)
                            local kind = n.kind or n[4]
                            if kind ~= "L" and kind ~= "V" then kind = nil end
                            if kind and Add(kind, m, tonumber(n.x or n[1]), tonumber(n.y or n[2]), "learned by the LeyLines addon") then
                                learned = learned + 1
                            end
                        end
                    end
                end
            end
        end
        B.leyCount, B.convCount, B.leyLearned = #lists.L, #lists.V, learned
        P.SetPins(CAT.L, lists.L)
        P.SetPins(CAT.V, lists.V)
    end
    -- at login, then again only when the LeyLines addon has learned something new
    local function Sig()
        local db = _G.LeyLinesDB
        if type(db) ~= "table" or type(db.nodes) ~= "table" then return "" end
        local n = 0
        for _, nodes in pairs(db.nodes) do if type(nodes) == "table" then n = n + #nodes end end
        return tostring(n)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    pcall(ev.RegisterEvent, ev, "MINIMAP_UPDATE_TRACKING")
    ev:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_LOGIN" then pcall(Read) return end
        seen = Sig()
        local ok, err = pcall(Read)
        if not ok then B.leyErr = err end
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(10, function()
                local s = Sig()
                if s ~= seen then seen = s; pcall(Read) end
            end)
        end
    end)
    B.ReadLeylines = Read
end


---------------------------------------------------------------------------
-- Dungeon Journal's "Show on Map" X. The journal keeps its pins to itself, but each marker it
-- lays on the game's world map carries its pin (marker.target: mapID, x, y, label, quest...),
-- and a removed pin leaves its marker without one. So the markers are looked up on the world
-- map's canvas (by their _fdjKey) and their pins drawn here: the same X (pulsing ring, dark disc,
-- glow, outlined gold X), the same tooltip; left click targets and raid-marks the NPC through
-- the journal's own secure macro (when near), right click hands the click to the journal's
-- marker, so the journal removes the pin itself. Its dungeon-entrance pins come too (the game's
-- dungeon icon with a soft glow, as the journal draws them); its turn-in pins are left out: the
-- map has the game's own turn-in markers already.
---------------------------------------------------------------------------
do
    -- (listed in the Pins menu only once the journal is found)
    local registered
    local function Register()
        if registered then return end
        registered = true
        P.RegisterCategory("djx", { name = "Dungeon Journal: Show on Map", addon = "Dungeon Journal", order = 405, minScale = 0,
            size = 44, always = true, noCount = true, color = { 0, 0, 0, 0 } })
        P.RegisterCategory("djd", { name = "Dungeon Journal: dungeon entrances", addon = "Dungeon Journal", order = 406, minScale = 0,
            size = 44, always = true, noCount = true, color = { 0, 0, 0, 0 } })
    end

    local DJ_SIZE = 44
    local function DJSize() return DJ_SIZE end
    local markers, sig, lastScan = {}, { djx = "", djd = "" }, 0

    local function Canvas()
        local W = _G.WorldMapFrame
        if not W then return end
        if type(W.GetCanvas) == "function" then
            local ok, c = pcall(W.GetCanvas, W)
            if ok and c then return c end
        end
        return W.ScrollContainer and (W.ScrollContainer.Child or W.ScrollContainer)
    end

    local function Font()
        return _G.ForeverDJ_GameFontNormalLarge and "ForeverDJ_GameFontNormalLarge" or "GameFontNormalLarge"
    end

    -- the X's layers, made once per pin button
    local function MakeX(b)
        local d = CreateFrame("Frame", nil, b)
        d:SetAllPoints(b)
        d:EnableMouse(false)
        d.pulse = d:CreateTexture(nil, "BACKGROUND", nil, -3)
        d.pulse:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        d.pulse:SetVertexColor(1, 0.30, 0.10, 0.55)
        d.pulse:SetBlendMode("ADD")
        d.pulse:SetSize(32, 32)
        d.pulse:SetPoint("CENTER")
        d.pulse:SetAlpha(0)
        pcall(function()
            local g = d.pulse:CreateAnimationGroup()
            g:SetLooping("REPEAT")
            local grow = g:CreateAnimation("Scale")
            grow:SetDuration(1.8)
            if grow.SetScaleFrom then grow:SetScaleFrom(0.9, 0.9); grow:SetScaleTo(2.0, 2.0) else grow:SetScale(2.0, 2.0) end
            grow:SetOrigin("CENTER", 0, 0)
            grow:SetEndDelay(0.7)
            local fin = g:CreateAnimation("Alpha")
            fin:SetDuration(0.45); fin:SetFromAlpha(0); fin:SetToAlpha(0.55)
            local fout = g:CreateAnimation("Alpha")
            fout:SetStartDelay(0.45); fout:SetDuration(1.35); fout:SetFromAlpha(0.55); fout:SetToAlpha(0); fout:SetEndDelay(0.7)
            d.anim = g
        end)
        d.back = d:CreateTexture(nil, "BACKGROUND", nil, -2)
        d.back:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        d.back:SetVertexColor(0, 0, 0, 0.62)
        d.back:SetSize(32, 32)
        d.back:SetPoint("CENTER")
        d.glow = d:CreateFontString(nil, "BACKGROUND", Font())
        d.glow:SetPoint("CENTER")
        d.glow:SetText("X")
        d.glow:SetTextColor(1, 0.82, 0.20, 0.32)
        d.glow:SetScale(1.80)
        for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
            local sh = d:CreateFontString(nil, "OVERLAY", Font())
            sh:SetPoint("CENTER", o[1], o[2])
            sh:SetText("X")
            sh:SetTextColor(0, 0, 0, 1)
            sh:SetScale(1.35)
        end
        d.x = d:CreateFontString(nil, "OVERLAY", Font())
        d.x:SetPoint("CENTER")
        d.x:SetText("X")
        d.x:SetTextColor(1, 0.88, 0.10, 1)
        d.x:SetScale(1.35)
        return d
    end

    -- a dungeon entrance: the game's dungeon icon, 1.4 times its own size, over a soft gold glow
    local function MakeDungeon(b)
        local d = CreateFrame("Frame", nil, b)
        d:SetAllPoints(b)
        d:EnableMouse(false)
        local size = 24
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Dungeon")
        if type(info) == "table" and tonumber(info.width) and info.width >= 8 then size = floor(info.width * 1.4 + 0.5) end
        d.glow = d:CreateTexture(nil, "BACKGROUND")
        d.glow:SetPoint("CENTER")
        d.glow:SetSize(size + 8, size + 8)
        d.icon = d:CreateTexture(nil, "OVERLAY")
        d.icon:SetPoint("CENTER")
        d.icon:SetSize(size, size)
        for _, t in ipairs({ d.icon, d.glow }) do
            if not (t.SetAtlas and pcall(t.SetAtlas, t, "Dungeon", false)) then
                t:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
                t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
        d.glow:SetBlendMode("ADD")
        d.glow:SetVertexColor(1, 0.86, 0.35, 0.42)
        d.glow:SetAlpha(0.55)
        return d
    end

    local function Label(t)
        local label = t.label
        if type(label) ~= "string" or label == "" then label = rawget(t, "markerType") == "dungeon" and "Dungeon entrance" or "Quest giver" end
        local FDJ = _G.ForeverDungeonJournal_NS
        if FDJ and FDJ.LocalizeFreeText then
            local ok, l = pcall(FDJ.LocalizeFreeText, label)
            if ok and type(l) == "string" then label = l end
        end
        -- "NPC — Quest title", as the journal's own tooltip
        if type(t.questTitle) == "string" and t.questTitle ~= "" then
            local dash = " \226\128\148 "
            local cut = label:find(dash, 1, true)
            label = (cut and label:sub(1, cut - 1) or label) .. dash .. t.questTitle
        end
        return label
    end

    -- the click layer: the journal's targeting macro on left click, its removal on right click
    local function MakeClick(b)
        local ok, c = pcall(CreateFrame, "Button", nil, b, "InsecureActionButtonTemplate")
        if not (ok and c) then c = CreateFrame("Button", nil, b) else c._fdjCanTarget = true end
        c:SetAllPoints(b)
        c:SetFrameLevel(b:GetFrameLevel() + 2)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if c._fdjCanTarget then pcall(c.SetAttribute, c, "useOnKeyDown", false) end
        c:SetScript("OnEnter", function(self)
            local p = rawget(self, "pin")
            local t = p and p.dj
            if not t then return end
            local FDJ = _G.ForeverDungeonJournal_NS
            local conf = FDJ and FDJ.MapMarkers and FDJ.MapMarkers.ConfigureTargetAndMarkAction
            if conf and self._fdjCanTarget then pcall(conf, self, t, true) end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Label(t))
            local detail = t.detail
            if FDJ and FDJ.LocalizeFreeText and type(detail) == "string" then
                local okL, l = pcall(FDJ.LocalizeFreeText, detail)
                if okL then detail = l end
            end
            local dungeon = rawget(t, "markerType") == "dungeon"
            GameTooltip:AddLine((type(detail) == "string" and detail ~= "" and detail) or (dungeon and "Dungeon entrance") or "Quest starts here", 1, 0.82, 0.05)
            if dungeon then
                -- (nobody to target)
            elseif self._fdjTargetEnabled then
                GameTooltip:AddLine("Left Click to target and mark quest giver", 0.35, 1, 0.35)
            elseif t.markerType ~= "location" then
                GameTooltip:AddLine("Left Click to target and mark quest giver if nearby", 0.35, 1, 0.35)
            end
            GameTooltip:AddLine("Right Click to remove marker", 1, 1, 1)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        local function Right(self, button)
            if button ~= "RightButton" then return end
            local p = rawget(self, "pin")
            local m = p and p.djMarker
            if m and m.Click then pcall(m.Click, m, "RightButton") end
            lastScan = 0
            if GameTooltip then GameTooltip:Hide() end
        end
        if c._fdjCanTarget then c:SetScript("PostClick", Right) else c:SetScript("OnClick", Right) end
        return c
    end

    -- CloudeMap.lua calls this when a pin button takes a pin with extra layers, or loses one
    function ns.PinDeco(b, p)
        local x, dg, click = rawget(b, "djX"), rawget(b, "djD"), rawget(b, "djClick")
        if p.deco == "djx" or p.deco == "djd" then
            if p.deco == "djx" then
                if not x then x = MakeX(b); b.djX = x end
                x:Show()
                local anim = rawget(x, "anim")
                if anim and not anim:IsPlaying() then anim:Play() end
                if dg then dg:Hide() end
            else
                if not dg then dg = MakeDungeon(b); b.djD = dg end
                dg:Show()
                if x then x:Hide(); local anim = rawget(x, "anim"); if anim then anim:Stop() end end
            end
            if not click and not (InCombatLockdown and InCombatLockdown()) then click = MakeClick(b); b.djClick = click end
            if click then click.pin = p; click:Show() end
            b.decoOn = true
        else
            if x then x:Hide(); local anim = rawget(x, "anim"); if anim then anim:Stop() end end
            if dg then dg:Hide() end
            if click then click.pin = nil; click:Hide() end
            b.decoOn = nil
        end
    end

    -- twice a second: the journal's live markers (the canvas itself looked through every 2 s)
    function B.DJMarkers()
        if type(_G.ForeverDungeonJournal_NS) ~= "table" then
            for id, v in pairs(sig) do if v ~= "" then sig[id] = ""; P.SetPins(id, {}) end end
            return
        end
        Register()
        local now = Now()
        if now - lastScan >= 2 then
            lastScan = now
            local canvas = Canvas()
            if canvas and canvas.GetChildren then
                for _, ch in ipairs({ canvas:GetChildren() }) do
                    if type(ch) == "table" and rawget(ch, "_fdjKey") then markers[ch] = true end
                end
            end
        end
        local lists, keys = { djx = {}, djd = {} }, { djx = {}, djd = {} }
        local known = P.known or {}
        for m in pairs(markers) do
            local t = rawget(m, "target")
            if type(t) == "table" and not rawget(t, "turnIn") then
                local map, x, y = tonumber(t.mapID), tonumber(t.x), tonumber(t.y)
                if map and x and y and known[map] then
                    local id = rawget(t, "markerType") == "dungeon" and "djd" or "djx"
                    local list = lists[id]
                    list[#list + 1] = { map = map, x = x, y = y, size = DJ_SIZE, sizeFn = DJSize, level = 24, deco = id,
                        dj = t, djMarker = m, name = Label(t) }
                    keys[id][#keys[id] + 1] = tostring(rawget(m, "_fdjKey"))
                end
            end
        end
        for id, k in pairs(keys) do
            table.sort(k)
            local s = table.concat(k, ";")
            if s ~= sig[id] then sig[id] = s; P.SetPins(id, lists[id]) end
        end
    end
end
