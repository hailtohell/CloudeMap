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
-- (the same size at every zoom, set by its own slider: Options, party pin size)
P.RegisterCategory("party", { name = "Party and raid members", order = 7, minScale = 0, size = 16, always = true,
    absolute = true, scaleKey = "partySize",
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
    C_Timer.NewTicker(1 / 12, function()
        local f = _G.CloudeMapFrame
        if f and f.IsShown and f:IsShown() then
            local ok, err = ns.prof.Time("every 1/12 s: party markers", pcall, ReadParty)
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
local bstat = { paints = 0, errors = 0 }      -- quest area draws, for /cmap status
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

function B.BlobCount()
    local n, on = 0, 0
    for k in pairs(blobs) do n = n + 1; if bstate[k] and bstate[k].shown then on = on + 1 end end
    local ago = bstat.at and GetTime and ("%.1f s ago"):format(GetTime() - bstat.at) or "never"
    return n, on, bstat.paints, ago, bstat.errors, bstat.err and (" (" .. tostring(bstat.err) .. ")") or ""
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

-- (no combat pause: the frame is the addon's own and the game's map draws its quest areas in
-- combat too; skipping it left the areas stuck where they were while the map moved on)
local function Paint(f, st, view)
    bstat.paints, bstat.at = bstat.paints + 1, GetTime and GetTime()
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
    last.canvas, last.level, last.mode = canvas, canvas:GetFrameLevel(), mode
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
                        -- one quest's failure must not stop the others from following the map
                        local ok, err = pcall(Paint, f, st, view)
                        if not ok then bstat.errors, bstat.err = bstat.errors + 1, err end
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

-- Pointing at a quest marker lights up its quest's area, as on the game's map: the area drawn
-- the game's way (as its active quest) above the others, whether quest areas are on or not.
local hl, hlSt
function B.QuestHover(q, n)
    if hl then hl:Hide() end
    hlSt = nil
    if not (q and n and last.view and last.scale) or blobOK == false then return end
    if not hl then
        hl = NewBlob(last.view, last.canvas)
        if not hl then return end
    end
    local st = { mapID = n.mapID, quest = q, node = n }
    Style(hl, st, last.mode or "map", "active", 1, last.level or 0)
    hl:SetFrameLevel((last.level or 0) + 5)      -- above the other areas, under the markers
    st.s = n.w * last.scale / BLOB_W
    st.x, st.y = last.ox + n.x * last.scale, last.oy + n.y * last.scale
    st.shown = true
    hlSt = st
    pcall(Paint, hl, st, last.view)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() if hlSt == st then pcall(Paint, hl, st, last.view) end end)
    end
end

local function NewPoi(view, canvas)
    local ok, f = pcall(CreateFrame, "Button", nil, view, "POIButtonTemplate")
    if not ok or type(f) ~= "table" or type(f.SetQuestID) ~= "function" then
        poiOK = false
        return
    end
    f:SetFrameLevel(canvas:GetFrameLevel() + 8)
    f:HookScript("OnEnter", function(self)
        if self.smQuest and QuestTip then QuestTip(self.smQuest, self) end
        if self.smQuest then B.QuestHover(self.smQuest, self.smNode) end
    end)
    f:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end; B.QuestHover() end)
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
                    f.smNode = n
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
                            pins[#pins + 1] = { map = n.mapID, x = p[1], y = p[2], size = 22, quest = q, node = n,
                                texture = QuestDone(q) and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\IncompleteQuestIcon",
                                onEnter = function(btn, pin)
                                    if QuestTip then QuestTip(pin.quest, btn) end
                                    B.QuestHover(pin.quest, pin.node)
                                end,
                                onLeave = function() B.QuestHover() end }
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
    if B.viewState then
        local v = B.viewState
        v.view = (...)
        v.ox, v.oy, v.scale = select(3, ...)
    end
    if select(9, ...) then
        if blobOK ~= false then
            local ok, err = T("pins: quest areas", pcall, DrawBlobs, ...)
            if not ok then B.blobErr = err end
        end
        return
    end
    if B.PluginRedraw then T("pins: plugins", B.PluginRedraw, select(5, ...)) end
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
-- The tooltip of a quest, made the way the game's own map makes it for its quest markers
-- (QuestPinMixin:OnMouseEnter): the title with the quest's level and difficulty colour ("[21]
-- Eight-Legged Menaces"), its type and time left, then what is still to do. Whatever the game
-- or another addon (Questie) adds to that tooltip of the game's comes along. Where the game's
-- helpers are missing, the plain title and every objective.
local function Try(fn, ...) if type(fn) == "function" then local ok, v = pcall(fn, ...); if ok then return v end end end
function QuestTip(q, view)
    if not GameTooltip then return end
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then title = Try(C_QuestLog.GetTitleForQuestID, q) end
    title = title or ("Quest " .. q)
    title = Try(_G.SetQuestTitleLevelAndDifficultyColor, q, title) or title
    if not pcall(GameTooltip.SetOwner, GameTooltip, view, "ANCHOR_CURSOR_RIGHT", 5, 2) then
        GameTooltip:SetOwner(view, "ANCHOR_CURSOR")
    end
    GameTooltip:SetText(title)
    Try(_G.QuestUtils_AddQuestTypeToTooltip, GameTooltip, q, _G.NORMAL_FONT_COLOR)
    Try(_G.GameTooltip_CheckAddQuestTimeToTooltip, GameTooltip, q)
    local dash = _G.QUEST_DASH or "- "
    local index = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and Try(C_QuestLog.GetLogIndexForQuestID, q)
    local done = QuestDone(q)
    local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Try(C_SuperTrack.GetSuperTrackedQuestID) == q
    local way = tracked and C_QuestLog.GetNextWaypointText and Try(C_QuestLog.GetNextWaypointText, q)
    if type(way) == "string" and way ~= "" then
        GameTooltip:AddLine(dash .. way, 1, 1, 1, true)
    elseif index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        if not done then
            local drops = GetNumQuestItemDrops and Try(GetNumQuestItemDrops, index) or 0
            local count, get = drops, GetQuestLogItemDrop
            if not (type(count) == "number" and count > 0 and get) then
                count, get = Try(GetNumQuestLeaderBoards, index) or 0, GetQuestLogLeaderBoard
            end
            for i = 1, count do
                local ok, text, _, finished = pcall(get, i, index)
                if ok and text and not finished then GameTooltip:AddLine(dash .. text, 1, 1, 1, true) end
            end
        end
    else
        local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and Try(C_QuestLog.GetQuestObjectives, q)
        if type(objs) == "table" then
            for _, o in ipairs(objs) do
                if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
                    if o.finished then GameTooltip:AddLine(dash .. o.text, 0.6, 0.6, 0.6, true)
                    else GameTooltip:AddLine(dash .. o.text, 1, 1, 1, true) end
                end
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
        .. ("ley lines %d, convergences %d (%d learned by LeyLines)%s | "):format(B.leyCount or 0, B.convCount or 0, B.leyLearned or 0, B.leyErr and (", error: " .. tostring(B.leyErr)) or "")
        .. ("party pins %d%s | "):format(#party.list, B.partyErr and (", error: " .. tostring(B.partyErr)) or "")
        .. ("pings: minimap pings %s, last %s%s | "):format(B.mmHooked and "heard" or "not available", tostring(B.mmLast or "none"),
            (B.pingErr and (", send error " .. tostring(B.pingErr)) or "") .. (B.blocked and (", blocked: " .. B.blocked) or ""))
        .. (B.PluginStatus and B.PluginStatus() or "")
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
-- Dungeon Journal (ForeverDungeonJournal): its dungeon maps, drawn in CloudeMap's window as a
-- mode of its own, from the journal's data (see "The journal's map" below). Nothing of the
-- journal is moved or replaced; its functions are only called to read its data and, with sync
-- on, to show in its window the dungeon or floor picked here. Nothing is asked of the journal's
-- version: every piece used is looked for by name, and the button only shows while the
-- journal's maps are there.
---------------------------------------------------------------------------
do
    local ui                    -- what CloudeMap.lua hands over when its window is built
    local dj = { on = false }   -- on: the mode; name, floor: the dungeon and floor shown
    local bg = { on = false, tiles = {}, pins = {} }    -- the battleground map (further down)
    local host, djBtn, pickBtn, pickMenu, bgBtn
    local BGSet

    local function Parts()
        local FDJ = _G.ForeverDungeonJournal_NS
        if type(FDJ) ~= "table" or type(FDJ.DUNGEON_MAPS) ~= "table" then return end
        return FDJ
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
        local sync = not (_G.CloudeMapDB and _G.CloudeMapDB.djSync == false)
        return Good(Call(FDJ, "CurrentDungeon")) or (sync and Good((Call(FDJ, "GetSelectedDungeon")))) or Good(dj.name)
            or Good((Call(FDJ, "GetSelectedDungeon")))
            or (function() for _, name in ipairs(List(FDJ)) do if Good(name) then return name end end end)()
    end

    -----------------------------------------------------------------------
    -- The journal's map, drawn by CloudeMap itself from the journal's data: the game's art for
    -- each floor, the bosses (with the journal's portraits where it has them), the entrances, the
    -- ladders between floors, the quest spots and a hand-in marked from its tracker. Nothing of
    -- the journal is borrowed, so its own window shows its map at the same time. With "Sync with
    -- Dungeon Journal" on (Options), the two follow each other: a dungeon or floor picked in one
    -- is shown in the other.
    -----------------------------------------------------------------------
    local v = { zoom = 1, px = 0, py = 0, tiles = {}, boss = {}, ent = {}, tr = {}, obj = {}, flb = {} }
    local DJ_MEDIA = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\"
    local EN = { MAP_FLOOR = "Level %d", MAP_ENTRANCE = "Entrance", MAP_QUEST_TARGET = "Quest target",
        TURN_IN_HERE = "Turn in here", QUEST_STARTS_HERE = "Quest starts here", MAP_RIGHT_REMOVE = "Right-click to remove" }
    local function L(key, ...)
        local FDJ = Parts()
        if FDJ and type(FDJ.L) == "function" then
            local ok, s = pcall(FDJ.L, key, ...)
            if ok and type(s) == "string" and s ~= key then return s end
        end
        local en = EN[key]
        if en then local ok, s = pcall(string.format, en, ...); if ok then return s end end
        return tostring(key)
    end
    local function Font(big)
        local n = big and "ForeverDJ_SystemFont_Shadow_Large_Outline" or "ForeverDJ_SystemFont_Outline"
        return _G[n] and n or (big and "GameFontNormalLarge" or "GameFontNormal")
    end
    local function Sync() return not (_G.CloudeMapDB and _G.CloudeMapDB.djSync == false) end

    -- the game map a floor is drawn from: the journal's map ID, or, when this client has no art
    -- under it, the one the journal finds by the dungeon's name
    function dj.FloorMap(FDJ, data, level)
        local floor = data and data.floors and data.floors[level]
        local id = floor and tonumber(floor.uiMapID)
        if not id then return end
        local ok, layers = pcall(C_Map.GetMapArtLayers, id)
        if not (ok and type(layers) == "table" and layers[1]) and type(FDJ.FindMapArtID) == "function" then
            local ok2, alt = pcall(FDJ.FindMapArtID, dj.name, floor)
            if ok2 and tonumber(alt) then id = tonumber(alt) end
        end
        return id
    end

    -- the art frame: the map at its size, inside the cover (which clips it), dragged and zoomed
    local function Position()
        local maxX, maxY = 0, 0
        if v.zoom > 1.001 then maxX, maxY = (v.aw or 0) / 2, (v.ah or 0) / 2 end
        v.px = math.max(-maxX, math.min(maxX, v.px))
        v.py = math.max(-maxY, math.min(maxY, v.py))
        v.art:ClearAllPoints()
        v.art:SetPoint("CENTER", host, "CENTER", v.px, v.py)
    end

    local function Tile(n)
        local t = v.tiles[n]
        if not t then t = v.art:CreateTexture(nil, "ARTWORK"); v.tiles[n] = t end
        t:ClearAllPoints()
        t:SetTexCoord(0, 1, 0, 1)
        t:SetAlpha(1)
        t:SetDrawLayer("ARTWORK", 0)
        t:Show()
        return t
    end

    -- the floor's picture: the game's art (by the journal's map ID, or the one it finds by name),
    -- else the journal's own texture or its copy of the map; and its patches over the title banner
    local function Art(FDJ, data, level, fd, aw, ah)
        local n, copy = 0, nil
        if fd.texture then
            n = 1
            local t = Tile(1)
            t:SetAllPoints(v.art)
            t:SetTexture(fd.texture)
            t:SetTexCoord(0, fd.texRight or 1, 0, fd.texBottom or 1)
        else
            local map = dj.FloorMap(FDJ, data, level)
            local layer, tex
            if map then
                local ok, layers = pcall(C_Map.GetMapArtLayers, map)
                if ok and type(layers) == "table" and layers[1] then
                    local ok2, t = pcall(C_Map.GetMapArtLayerTextures, map, 1)
                    if ok2 and type(t) == "table" and #t > 0 then layer, tex = layers[1], t end
                end
            end
            if tex then
                local lw, lh = tonumber(layer.layerWidth) or 1002, tonumber(layer.layerHeight) or 668
                local tw, th = tonumber(layer.tileWidth) or 256, tonumber(layer.tileHeight) or 256
                local cols = math.max(1, math.ceil(lw / tw))
                local sx, sy = aw / lw, ah / lh
                local unloaded = false
                for i = 1, #tex do
                    local col, row = (i - 1) % cols, floor((i - 1) / cols)
                    local t = Tile(i)
                    t:SetSize(tw * sx, th * sy)
                    t:SetPoint("TOPLEFT", v.art, "TOPLEFT", col * tw * sx, -row * th * sy)
                    local loaded = t:SetTexture(tex[i])
                    if loaded == false and fd.tiles then loaded = t:SetTexture(fd.tiles .. i) end
                    if loaded == false then unloaded = true end
                end
                n = #tex
                if unloaded then copy = Call(FDJ, "MapArtCopy", fd) end
            elseif fd.tiles then
                local s = aw / 1002
                for i = 1, 12 do
                    local col, row = (i - 1) % 4, floor((i - 1) / 4)
                    local t = Tile(i)
                    t:SetSize(256 * s, 256 * s)
                    t:SetPoint("TOPLEFT", v.art, "TOPLEFT", col * 256 * s, -row * 256 * s)
                    t:SetTexture(fd.tiles .. i)
                end
                n = 12
                local first = v.tiles[1]
                if first and first.GetTextureFileID and not first:GetTextureFileID() then copy = Call(FDJ, "MapArtCopy", fd) end
            end
            if copy then
                n = 1
                local t = Tile(1)
                t:SetAllPoints(v.art)
                t:SetTexture(copy)
                t:SetTexCoord(0, 1002 / 1024, 0, 668 / 1024)
            elseif n > 0 then
                for _, p in ipairs(type(fd.patches) == "table" and fd.patches or {}) do
                    n = n + 1
                    local t = Tile(n)
                    t:SetDrawLayer("ARTWORK", 1)
                    t:SetPoint("TOPLEFT", v.art, "TOPLEFT", p.x0 * aw, -p.y0 * ah)
                    t:SetPoint("BOTTOMRIGHT", v.art, "TOPLEFT", p.x1 * aw, -p.y1 * ah)
                    t:SetTexture(p.tex)
                    t:SetAlpha(p.alpha or 1)
                end
            end
        end
        for i = n + 1, #v.tiles do v.tiles[i]:Hide() end
        v.empty = n == 0
    end

    -- a boss's picture: the journal's own (FDJ.SetBossPortrait, the one its map, list and run
    -- log use: its bundled pictures, the game's journal data, its saved and resolved display IDs,
    -- from its pool so no black square shows while a model loads); with an older journal
    -- without it, the same from the boss record and the saved display IDs. False: none.
    local function Portrait(FDJ, tex, rec)
        if type(rec) ~= "table" then return false end
        if type(FDJ.SetBossPortrait) == "function" then
            local ok, shown = pcall(FDJ.SetBossPortrait, tex, dj.name, rec)
            if ok then return shown and true or false end
        end
        if FDJ.ReleasePortrait then pcall(FDJ.ReleasePortrait, tex) end
        tex:SetTexture(nil)
        tex:SetTexCoord(0, 1, 0, 1)
        if type(rec) ~= "table" then return false end
        if rec.recipeTab then tex:SetTexture("Interface\\Icons\\INV_Scroll_05") return true end
        if rec.lootChest then tex:SetTexture("Interface\\Icons\\INV_Box_01") return true end
        if rec.trash then tex:SetTexture(DJ_MEDIA .. "TrashDropsIcon") return true end
        if rec.customIcon then tex:SetTexture(rec.customIcon) return true end
        local id = tonumber(rec.displayID)
        local npc = tonumber(rec.npcID) or tonumber(rec.portraitNpcID)
        local cache = type(_G.ForeverDungeonJournalDB) == "table" and _G.ForeverDungeonJournalDB.displayIDs
        if not id and npc and type(cache) == "table" then id = tonumber(cache[npc]) end
        if id and type(FDJ.AcquirePortrait) == "function" then
            local ok, shown = pcall(FDJ.AcquirePortrait, tex, id)
            if ok and shown then return true end
        end
        return false
    end

    local function Tip(self)
        if not (self.tipTitle and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle, self.tipR or 1, self.tipG or 1, self.tipB or 1)
        for _, l in ipairs(self.tipLines or {}) do GameTooltip:AddLine(l[1], l[2], l[3], l[4], true) end
        GameTooltip:Show()
    end
    local function NoTip() if GameTooltip then GameTooltip:Hide() end end
    local function Pin(list, i, kind)
        local b = list[i]
        if b then return b end
        b = CreateFrame("Button", nil, v.art)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        if kind == "boss" then
            b.border = b:CreateTexture(nil, "OVERLAY")
            b.border:SetPoint("CENTER")
            b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            b.border:SetTexCoord(0, 0.6, 0, 0.6)
        end
        if kind == "ent" or kind == "tr" then
            b.label = b:CreateFontString(nil, "OVERLAY", Font(kind == "ent"))
            b.label:SetShadowColor(0, 0, 0, 1)
            b.label:SetShadowOffset(1, -1)
        end
        b:SetScript("OnEnter", Tip)
        b:SetScript("OnLeave", NoTip)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        list[i] = b
        return b
    end

    local SelectFloor   -- (below)
    local function Pins(FDJ, data, level, aw, ah, bh)
        local base = v.art:GetFrameLevel()
        local dname = dj.name
        local book = type(FDJ.DB) == "table" and FDJ.DB[dname] or nil
        -- bosses (a quest's target only with its quest, as the journal shows them)
        local size = floor(math.max(26, floor(bh * 0.095)) * (Call(FDJ, "MapBossScale") or 1))
        local nb, missing = 0, 0
        for _, mb in ipairs(type(data.bosses) == "table" and data.bosses or {}) do
            local qe
            if mb.quest then
                for _, q in ipairs(book and book.quests or {}) do if type(q) == "table" and q.id == mb.quest then qe = q break end end
            end
            local hidden = mb.quest and (not qe or Call(FDJ, "RPGQuestHidden", dname, qe))
            if (mb.floor or 1) == level and not hidden and size > 0 then
                nb = nb + 1
                local b = Pin(v.boss, nb, "boss")
                b:SetSize(size, size)
                b.border:SetSize(size * 1.55, size * 1.55)
                b:SetFrameLevel(base + 10)
                local rec, idx
                for i, c in ipairs(book and book.bosses or {}) do if c.name == mb.name then rec, idx = c, i break end end
                local rpg = Call(FDJ, "RPGMapBossHidden", dname, rec) and true or false
                local who = (not rpg) and (rec or (mb.npcID and { name = mb.name, npcID = mb.npcID })) or nil
                if not Portrait(FDJ, b.icon, who) then
                    if who then missing = missing + 1 end
                    b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                local name = rpg and "???" or (rec and (Call(FDJ, "LocalizeBossName", rec.name) or rec.name))
                    or Call(FDJ, "LocalizeFreeText", mb.name) or mb.name
                b.tipTitle, b.tipR, b.tipG, b.tipB, b.tipLines = tostring(name or ""), 1, 1, 1, nil
                if mb.quest then
                    local title = Call(FDJ, "LocalizeQuestField", mb.quest, "name", qe and qe.name or "") or (qe and qe.name) or ""
                    b.tipLines = { { title, 1, 0.82, 0 }, { L("MAP_QUEST_TARGET"), 0.92, 0.92, 0.92 } }
                end
                local quest = (not rec) and mb.quest or nil
                b:SetScript("OnClick", function(_, button)
                    if button ~= "LeftButton" then return end
                    if quest then Call(FDJ, "OpenQuestPage", dname, quest)
                    elseif idx then Call(FDJ, "OpenBossPage", dname, idx) end
                end)
                b:ClearAllPoints()
                b:SetPoint("CENTER", v.art, "TOPLEFT", mb.x * aw, -mb.y * ah)
                b:Show()
            end
        end
        for i = nb + 1, #v.boss do v.boss[i]:Hide() end
        -- the journal works out some portraits in the background: drawn again a little later
        -- (a few times at most for one map)
        local key = tostring(dname) .. ":" .. level
        if missing > 0 and C_Timer and C_Timer.After and (v.retryKey ~= key or (v.retries or 0) < 4) then
            if v.retryKey ~= key then v.retryKey, v.retries = key, 0 end
            if not v.retryDue then
                v.retryDue = true
                v.retries = v.retries + 1
                C_Timer.After(3, function() v.retryDue = nil; if dj.on and v.retryKey == tostring(dj.name) .. ":" .. tostring(dj.floor) then pcall(dj.Draw, false) end end)
            end
        end

        -- entrances, with their label
        local ne = 0
        local ents = type(data.entrances) == "table" and data.entrances or (type(data.entrance) == "table" and { data.entrance }) or {}
        for _, e in ipairs(ents) do
            if (e.floor or 1) == level then
                ne = ne + 1
                local b = Pin(v.ent, ne, "ent")
                local s = math.max(22, floor(bh * 0.075))
                b:SetSize(s, s)
                b:SetFrameLevel(base + 15)
                if not (b.icon.SetAtlas and pcall(b.icon.SetAtlas, b.icon, "Dungeon", false)) then
                    b.icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
                    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                b.label:SetText(L(e.labelKey or "MAP_ENTRANCE"))
                local c = e.color
                if type(c) == "table" then b.label:SetTextColor(c[1], c[2], c[3]) else b.label:SetTextColor(1, 0.82, 0) end
                b.label:ClearAllPoints()
                if e.labelPos == "top" then b.label:SetPoint("BOTTOM", b, "TOP", 0, 1)
                elseif math.cos(math.rad(e.angle or 0)) < -0.3 then b.label:SetPoint("RIGHT", b, "LEFT", -3, 0)
                else b.label:SetPoint("LEFT", b, "RIGHT", 3, 0) end
                b.tipTitle = nil
                b:SetScript("OnClick", nil)
                b:ClearAllPoints()
                b:SetPoint("CENTER", v.art, "TOPLEFT", e.x * aw, -e.y * ah)
                b:Show()
            end
        end
        for i = ne + 1, #v.ent do v.ent[i]:Hide() end

        -- the ladders to the other floors (a click goes there) and notes
        local nt = 0
        local floors = data.floors or {}
        for _, t in ipairs(type(data.transitions) == "table" and data.transitions or {}) do
            if t.floor == level and (floors[t.to] or t.note) then
                nt = nt + 1
                local b = Pin(v.tr, nt, "tr")
                local s = math.max(28, floor(bh * 0.10))
                b:SetSize(s, s)
                b:SetFrameLevel(base + 14)
                b.icon:SetTexture(DJ_MEDIA .. "LevelLadder")
                b.label:SetTextColor(0.35, 1, 0.35)
                b.label:ClearAllPoints()
                b.label:SetPoint("BOTTOM", b, "TOP", 0, 1)
                b.label:SetText(t.note and "" or L(t.labelKey or "MAP_FLOOR", t.to))
                b.tipTitle = t.to and L("MAP_FLOOR", t.to) or (t.note and L(t.labelKey)) or ""
                b.tipR, b.tipG, b.tipB, b.tipLines = 0.35, 1, 0.35, nil
                local to = (not t.note) and t.to or nil
                b:SetScript("OnClick", function(_, button) if button == "LeftButton" and to then SelectFloor(to, true) end end)
                b:ClearAllPoints()
                b:SetPoint("CENTER", v.art, "TOPLEFT", t.x * aw, -t.y * ah)
                b:Show()
            end
        end
        for i = nt + 1, #v.tr do v.tr[i]:Hide() end

        -- quest spots ("?" where an objective is picked up), unless the journal hides quests
        local no = 0
        if not Call(FDJ, "MapQuestsHidden", dname) then
            for _, ob in ipairs(type(data.objectives) == "table" and data.objectives or {}) do
                if (ob.floor or 1) == level then
                    no = no + 1
                    local b = Pin(v.obj, no, "obj")
                    local s = math.max(22, floor(bh * 0.07))
                    b:SetSize(s, s)
                    b:SetFrameLevel(base + 15)
                    b.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
                    b.tipTitle = Call(FDJ, "LocalizeQuestField", ob.questID, "name", ob.quest) or ob.quest or ""
                    b.tipR, b.tipG, b.tipB = 1, 0.82, 0
                    b.tipLines = ob.textKey and { { L(ob.textKey), 1, 1, 1 } } or nil
                    b:SetScript("OnClick", nil)
                    b:ClearAllPoints()
                    b:SetPoint("CENTER", v.art, "TOPLEFT", ob.x * aw, -ob.y * ah)
                    b:Show()
                end
            end
        end
        -- the hand-in (or pick-up) marked from the journal's quest tracker
        local ti = type(FDJ.dungeonTurnIns) == "table" and FDJ.dungeonTurnIns[data] or nil
        if type(ti) == "table" and ti.floor == level and ti.x and ti.y then
            no = no + 1
            local b = Pin(v.obj, no, "obj")
            local s = math.max(24, floor(bh * 0.08))
            b:SetSize(s, s)
            b:SetFrameLevel(base + 16)
            b.icon:SetTexture(ti.start and "Interface\\GossipFrame\\AvailableQuestIcon" or "Interface\\GossipFrame\\ActiveQuestIcon")
            local text = Call(FDJ, "LocalizeFreeText", ti.npc) or ti.npc or ""
            if type(ti.title) == "string" and ti.title ~= "" then text = text .. " - " .. ti.title end
            b.tipTitle, b.tipR, b.tipG, b.tipB = text, 1, 1, 1
            b.tipLines = { { L(ti.start and "QUEST_STARTS_HERE" or "TURN_IN_HERE"), 1, 0.82, 0.05 } }
            b:SetScript("OnClick", nil)
            b:ClearAllPoints()
            b:SetPoint("CENTER", v.art, "TOPLEFT", ti.x * aw, -ti.y * ah)
            b:Show()
        end
        for i = no + 1, #v.obj do v.obj[i]:Hide() end
    end

    -- the floors, as buttons in the top left corner (only for a dungeon of several)
    local function FloorButtons(floors, level)
        local n = (#floors > 1) and #floors or 0
        for i = 1, n do
            local b = v.flb[i]
            if not b then
                b = ui.MakeButton(host, "", 70, function() SelectFloor(i, true) end, function()
                    local f = dj.data and dj.data.floors and dj.data.floors[i]
                    return f and f.label or L("MAP_FLOOR", i)
                end)
                v.flb[i] = b
            end
            b.text:SetText(L("MAP_FLOOR", i))
            b:SetSize(math.max(60, floor((b.text:GetStringWidth() or 40) + 16)), 18)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", host, "TOPLEFT", 6, -6 - (i - 1) * 20)
            b:SetFrameLevel(v.art:GetFrameLevel() + 40)
            if b.SetOn then b.SetOn(i == level) end
            b.text:SetTextColor(i == level and 1 or 0.85, i == level and 0.82 or 0.85, i == level and 0 or 0.85)
            b:Show()
        end
        for i = n + 1, #v.flb do v.flb[i]:Hide() end
    end

    -- the whole map: fit (zoom 1x, centred) or as it was
    function dj.Draw(fit)
        local FDJ = Parts()
        if not (FDJ and dj.on and dj.name and host and v.art) then return end
        local data = FDJ.DUNGEON_MAPS[dj.name]
        if not data then return end
        dj.data = data
        local floors = data.floors or {}
        if fit then v.zoom, v.px, v.py = 1, 0, 0 end
        local level = tonumber(dj.floor) or Call(FDJ, "SavedMapFloor", dj.name, data) or (type(data.entrance) == "table" and data.entrance.floor) or 1
        level = math.max(1, math.min(#floors, level))
        dj.floor = level
        local fd = floors[level]
        if not fd then return end
        local W, H = host:GetWidth() or 0, host:GetHeight() or 0
        if W < 40 or H < 40 then return end
        local bw, bh = W - 16, (W - 16) / 1.5
        if bh > H - 16 then bh = H - 16; bw = bh * 1.5 end
        v.bw, v.bh = floor(bw), floor(bh)
        v.aw, v.ah = floor(v.bw * v.zoom), floor(v.bh * v.zoom)
        v.art:SetSize(v.aw, v.ah)
        Position()
        Art(FDJ, data, level, fd, v.aw, v.ah)
        Pins(FDJ, data, level, v.aw, v.ah, v.bh)
        FloorButtons(floors, level)
        if ui and ui.barText then
            local lbl = #floors > 1 and (fd.label or L("MAP_FLOOR", level)) or nil
            ui.barText:SetText(Title(FDJ, dj.name) .. (lbl and ("  |cffbbbbbb" .. lbl .. "|r") or ""))
        end
        if dj.Units then dj.Units() end
    end

    -- the journal's dungeon and floor: what its map shows (or would open on)
    local function JournalState(FDJ)
        local sel = Call(FDJ, "GetSelectedDungeon")
        local jr = _G.ForeverDungeonJournalFrame
        local panel = type(jr) == "table" and jr.dungeonMapPanel
        local fl
        if type(panel) == "table" and panel.IsVisible and panel:IsVisible() then fl = jr.dungeonMapFloor end
        if type(fl) ~= "number" then
            local mf = type(_G.ForeverDungeonJournalDB) == "table" and _G.ForeverDungeonJournalDB.mapFloors
            fl = type(mf) == "table" and type(sel) == "string" and tonumber(mf[sel]) or nil
        end
        return sel, fl
    end
    local function Seen(FDJ) local s, f = JournalState(FDJ); dj.seen = tostring(s) .. ":" .. tostring(f) end

    -- ours to the journal: the dungeon and floor picked here, shown there (its map open: at once;
    -- closed: it opens there). A journal open on another page is left alone.
    local function Push()
        local FDJ = Parts()
        if not (FDJ and Sync() and dj.name) then return end
        local data = FDJ.DUNGEON_MAPS[dj.name]
        local jdb = _G.ForeverDungeonJournalDB
        if type(jdb) == "table" then
            jdb.mapFloors = type(jdb.mapFloors) == "table" and jdb.mapFloors or {}
            jdb.mapFloors[dj.name] = dj.floor
        end
        local jr = _G.ForeverDungeonJournalFrame
        local panel = type(jr) == "table" and jr.dungeonMapPanel
        local mapOpen = type(panel) == "table" and panel.IsVisible and panel:IsVisible()
        local sel = Call(FDJ, "GetSelectedDungeon")
        if sel ~= dj.name then
            if mapOpen or not (type(jr) == "table" and jr.IsShown and jr:IsShown()) then
                Call(FDJ, "SetMapDungeon", dj.name)
                if mapOpen then Call(FDJ, "ReopenDungeonMap", dj.name) end
            end
        elseif mapOpen and data then
            Call(FDJ, "RenderCustomDungeonMap", data, dj.floor)
        end
        Seen(FDJ)
    end

    -- the journal to ours: whatever it changed to since last looked at
    function dj.Pull()
        local FDJ = Parts()
        if not (FDJ and dj.on and Sync()) then return end
        local sel, fl = JournalState(FDJ)
        local key = tostring(sel) .. ":" .. tostring(fl)
        if key == dj.seen then return end
        dj.seen = key
        if type(sel) == "string" and FDJ.DUNGEON_MAPS[sel] and not Locked(FDJ, sel) then
            local other = sel ~= dj.name
            if not other and fl == dj.floor then return end
            dj.name = sel
            dj.floor = fl
            dj.Draw(other)
        end
    end

    SelectFloor = function(i, byHand)
        if i == dj.floor then return end
        dj.floor = i
        dj.Draw(false)
        if byHand then Push() end
    end

    -- the cover over the map view, with the art frame inside: wheel zoom (1x to 5x) round the
    -- pointer, drag when zoomed in; a new window size fits the map again at its zoom
    local function Host()
        if host then return end
        host = CreateFrame("Frame", nil, ui.view)
        host:SetAllPoints(ui.view)
        if host.SetClipsChildren then host:SetClipsChildren(true) end
        local tex = host:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetColorTexture(0.03, 0.025, 0.02, 1)
        host:EnableMouse(true)          -- nothing of the map underneath is reached
        host:EnableMouseWheel(true)
        v.art = CreateFrame("Frame", nil, host)
        host:SetScript("OnMouseWheel", function(self, d)
            local old = v.zoom
            local new = math.max(1, math.min(5, old * (d > 0 and 1.25 or 0.8)))
            if math.abs(new - old) < 0.001 then return end
            local s = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local mx = cx / s - (self:GetLeft() or 0) - (self:GetWidth() or 0) / 2
            local my = cy / s - (self:GetBottom() or 0) - (self:GetHeight() or 0) / 2
            local k = new / old
            v.px, v.py = mx - (mx - v.px) * k, my - (my - v.py) * k
            if new <= 1.001 then v.px, v.py = 0, 0 end
            v.zoom = new
            dj.Draw(false)
        end)
        host:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" or v.zoom <= 1.001 then return end
            local s = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            v.drag = { x = cx / s, y = cy / s, px = v.px, py = v.py }
        end)
        host:SetScript("OnMouseUp", function() v.drag = nil end)
        host:SetScript("OnHide", function() v.drag = nil end)
        host:SetScript("OnUpdate", function(self)
            local d = v.drag
            if not d then return end
            if not IsMouseButtonDown("LeftButton") then v.drag = nil return end
            local s = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            v.px, v.py = d.px + (cx / s - d.x), d.py + (cy / s - d.y)
            Position()
        end)
        host:SetScript("OnSizeChanged", function()
            if dj.on and not dj.sizing and C_Timer and C_Timer.After then
                dj.sizing = true
                C_Timer.After(0, function() dj.sizing = false; pcall(dj.Draw, false) end)
            end
        end)
    end

    -- the floor the hero is on, when the game says (most of Forever's dungeons it does not)
    function dj.FollowFloor()
        local FDJ = Parts()
        if not (FDJ and dj.on and dj.name) then return end
        local inside = IsInInstance and IsInInstance()
        if Secret(inside) or not inside then dj.lastBest = nil; return end
        local ok, best = pcall(C_Map.GetBestMapForUnit, "player")
        if not ok or Secret(best) or not tonumber(best) or best == dj.lastBest then return end
        dj.lastBest = best
        dj.unitRect = nil
        local data = FDJ.DUNGEON_MAPS[dj.name]
        for i = 1, data and data.floors and #data.floors or 0 do
            if dj.FloorMap(FDJ, data, i) == best then SelectFloor(i, false) return end
        end
    end

    -- The hero (and the group) on the map, drawn by the game itself (inside, addons get no position):
    -- a UnitPositionFrame over the floor's art, told which map it covers.
    function dj.Units()
        local holder = v.art
        local f = dj.units
        if not (dj.on and dj.name and holder) then
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
            local acc = 0
            f:SetScript("OnUpdate", function(self, el)
                local cap = CloudeMapDB and CloudeMapDB.cap
                if cap then acc = acc + (el or 0); if acc < 1 / cap then return end; acc = 0 end
                if not dj.lastBest then return end
                dj.Place(self)
                if dj.unitMap then pcall(self.UpdatePlayerPins, self) end
            end)
        end
        if not f then return end
        dj.unitRect = nil
        f:SetFrameLevel(holder:GetFrameLevel() + 60)     -- the hero above the pins
        f:Show()
    end

    function dj.Place(f)
        local D = Parts()
        local holder = v.art
        local fl = dj.on and D and dj.FloorMap(D, D.DUNGEON_MAPS[dj.name], dj.floor)
        local best = dj.lastBest
        local map, rect = fl, nil
        if fl and best and best ~= fl then
            local ok, x1, x2, y1, y2 = pcall(C_Map.GetMapRectOnMap, best, fl)
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

    -- show the journal's map in the window (fit: fitted, the floor it opens on)
    local function Take(fit)
        if not (ui and dj.on) then return false end
        Host()
        host:SetFrameLevel(ui.view:GetFrameLevel() + 500)       -- above every layer of the map, the death marker included
        v.art:SetFrameLevel(host:GetFrameLevel() + 1)
        if ui.grip then ui.grip:SetFrameLevel(host:GetFrameLevel() + 60) end
        host:Show()
        if not ui.frame:IsShown() then dj.needFit = dj.needFit or fit; return true end
        fit = fit or dj.needFit
        dj.needFit = nil
        dj.Draw(fit)
        if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(dj.Draw, false) end) end
        return true
    end
    local function Release()
        if dj.units then dj.units:Hide() end
        if host then host:Hide() end
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
                if name ~= dj.name then dj.floor = nil end
                dj.name = name
            end
        end
        dj.on = on
        Pause()
        if pickMenu then pickMenu:Hide() end
        Style()
        if on then
            Seen(FDJ)                                   -- the journal's state now: only later changes are followed
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
            local back = pickMenu:CreateTexture(nil, "BACKGROUND")
            back:SetAllPoints()
            back:SetColorTexture(0.06, 0.06, 0.07, 0.96)
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
                    if self.name ~= dj.name then dj.floor = nil end
                    dj.name = self.name
                    if dj.on then pcall(Take, true); Push() end
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
        -- the window closed: the menu goes; opened again: the mode carries on, drawn for the window's size
        t.frame:HookScript("OnHide", function() if pickMenu then pickMenu:Hide() end end)
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
            if name ~= dj.name then dj.floor = nil end
            dj.name = name
            if dj.on then pcall(Take, true) else SetOn(true, true) end
        elseif not inside and dj.auto then
            -- walked out: our map again (switched off by hand inside, it stays off)
            dj.auto = nil
            if dj.on then SetOn(false, true) end
        end
    end

    -- twice a second while the window is open: the button comes and goes with the journal, and
    -- what the journal changed (with sync on) is shown here
    function B.DungeonTick()
        if not (ui and djBtn) then return end
        -- the BG button comes with the battleground and goes with it, the mode too
        local inBG = InBG()
        if inBG ~= bgBtn:IsShown() then
            if inBG then bgBtn:Show() else bgBtn:Hide() end
            if not inBG and bg.on then BGSet(false, true) else Style() end
        end
        local FDJ = Parts()
        local have = FDJ and true or false
        if have ~= djBtn:IsShown() then
            if not have and dj.on then SetOn(false, true) end
            if have then djBtn:Show() else djBtn:Hide() end
            Style()
        end
        if not (have and dj.on) then return end
        pcall(dj.Pull)                                  -- the journal changed dungeon or floor: shown here too
        pcall(dj.FollowFloor)
    end

    -- what the hero arrow on the journal's map is doing (for /cmap status)
    function dj.UnitStatus()
        local f = dj.units
        local D = Parts()
        local data = D and D.DUNGEON_MAPS[dj.name]
        local floors = {}
        for i = 1, data and data.floors and #data.floors or 0 do floors[#floors + 1] = tostring((dj.FloorMap(D, data, i))) end
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
            tostring(dj.floor), table.concat(floors, "/"), tostring(dj.lastBest), name(dj.lastBest), tostring(hide))
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
            FDJ and (dj.on and ("map shown: %s, floor %s, zoom %.2f, sync %s%s"):format(tostring(dj.name), tostring(dj.floor), v.zoom,
                Sync() and "on" or "off", v.empty and ", no art for this floor" or "") or "found")
                or (_G.ForeverDungeonJournal_NS and "loaded, but its maps were not found" or "not loaded"),
            dj.err and (", error: " .. tostring(dj.err)) or "")
            .. (dj.units == false and (" | hero arrow: no UnitPositionFrame (" .. tostring(dj.unitsErr) .. ")")
                or dj.units and dj.on and dj.UnitStatus() or "")
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

---------------------------------------------------------------------------
-- Pings for the group. Alt+click on the map sends the spot to the party or raid (a hidden addon
-- message, seen only by CloudeMap); every member with CloudeMap sees it pulse on their map the
-- way the minimap shows a ping (the game's own three ping pictures: the glow, the expanding
-- ring and the turning ring), at the minimap's size whatever the zoom. A ping outside the part
-- of the map in view shows at the window's edge, where the line from the middle of the view to
-- it leaves the view, with an arrow pointing to it. A sound (five to choose from, or none) and a
-- line in chat go with it. Options -> Pings. Nothing runs while no ping is shown.
---------------------------------------------------------------------------
do
local PREFIX = "CloudeMap"
local PING_LIFE, PING_FADE = 5, 0.5
local PING_SOUNDS = {
    { "Map ping", 3175 }, { "Whisper", 3081 }, { "Boss warning", 37666 }, { "Ready check", 8960 }, { "Raid warning", 8959 },
}
B.PING_SOUNDS = PING_SOUNDS
local pings, pingLayer = {}, nil
local vs = {}                   -- the view as last drawn: frame, offset, scale (ns.afterUpdate)
B.viewState = vs
local lastSent = 0

local function PingOn() return not (CloudeMapDB and CloudeMapDB.ping == false) end
local function Me() local n = UnitName and UnitName("player"); return (not Secret(n)) and n or nil end

-- the parts of one ping: the glow, the expanding ring, the turning ring, a name, and (at the
-- window's edge) an arrow
local function NewPing()
    local f = CreateFrame("Frame", nil, pingLayer)
    f:SetSize(1, 1)
    f.center = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.center:SetTexture("Interface\\minimap\\UI-Minimap-Ping-Center")
    f.center:SetPoint("CENTER")
    f.expand = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.expand:SetTexture("Interface\\minimap\\UI-Minimap-Ping-Expand")
    f.expand:SetPoint("CENTER")
    f.rotate = f:CreateTexture(nil, "OVERLAY", nil, 0)
    f.rotate:SetTexture("Interface\\minimap\\UI-Minimap-Ping-Rotate")
    f.rotate:SetPoint("CENTER")
    f.arrow = f:CreateTexture(nil, "OVERLAY", nil, 3)
    f.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.arrow:SetVertexColor(1, 0.85, 0.2)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.name:SetShadowColor(0, 0, 0, 1)
    f.name:SetShadowOffset(1, -1)
    return f
end

local function PingUpdate()
    local now = GetTime()
    local view = vs.view
    local live = false
    -- the minimap's size on screen, in the map's units (scale-invariant: the zoom plays no part)
    local k = 1
    if _G.Minimap and pingLayer then
        local a, b = Minimap:GetEffectiveScale(), pingLayer:GetEffectiveScale()
        if a and b and b > 0 then k = a / b end
    end
    for who, p in pairs(pings) do
        local age = now - p.t0
        local f = p.f
        if age > PING_LIFE + PING_FADE or not (view and vs.scale) then
            f:Hide()
            pings[who] = nil
        else
            live = true
            local n = ns.NodeOf and ns.NodeOf(p.map)
            if not n then
                f:Hide()
            else
                -- where it is in the view, and whether that is in sight
                local x = vs.ox + (n.x + p.x * n.w) * vs.scale
                local y = vs.oy + (n.y + p.y * n.h) * vs.scale
                local W, H = view:GetWidth() or 0, view:GetHeight() or 0
                local M = 22 * k
                local edge = x < M or x > W - M or y < M or y > H - M
                local s = 1
                if edge then
                    -- the nearest point of the border, on the line from the middle of the view
                    local cx, cy = W / 2, H / 2
                    local dx, dy = x - cx, y - cy
                    local tx = dx ~= 0 and (((dx > 0) and (W - M - cx) or (M - cx)) / dx) or math.huge
                    local ty = dy ~= 0 and (((dy > 0) and (H - M - cy) or (M - cy)) / dy) or math.huge
                    local t = math.min(tx, ty, 1)
                    x, y = cx + dx * t, cy + dy * t
                    s = 0.6
                    local ang = math.atan2(-dy, dx)          -- screen up is +
                    f.arrow:SetSize(22 * k, 22 * k)
                    f.arrow:ClearAllPoints()
                    f.arrow:SetPoint("CENTER", f, "CENTER", math.cos(ang) * 16 * k, math.sin(ang) * 16 * k)
                    f.arrow:SetRotation(ang - math.pi / 2)
                    f.arrow:Show()
                else
                    f.arrow:Hide()
                end
                f:ClearAllPoints()
                f:SetPoint("CENTER", view, "TOPLEFT", x, -y)
                -- the minimap ping: a steady glow, a ring growing and fading once a second, a
                -- ring turning; all fading out at the end
                local fade = age > PING_LIFE and (1 - (age - PING_LIFE) / PING_FADE) or 1
                f.center:SetSize(32 * k * s, 32 * k * s)
                local e = (age % 1)
                f.expand:SetSize((32 + 48 * e) * k * s, (32 + 48 * e) * k * s)
                f.expand:SetAlpha((1 - e) * fade)
                f.rotate:SetSize(70 * k * s, 70 * k * s)
                f.rotate:SetRotation(-age * math.pi * 1.2)
                f.center:SetAlpha(fade)
                f.rotate:SetAlpha(fade)
                f.name:SetAlpha(fade)
                f.arrow:SetAlpha(fade)
                f.name:ClearAllPoints()
                f.name:SetPoint("TOP", f, "CENTER", 0, -22 * k * s)
                f:Show()
            end
        end
    end
    if not live and pingLayer then pingLayer:SetScript("OnUpdate", nil) end
end

local function ShowPing(who, map, x, y)
    if not (vs.view and ns.NodeOf and ns.NodeOf(map)) then return end
    if not pingLayer then
        pingLayer = CreateFrame("Frame", nil, vs.view)
        pingLayer:SetAllPoints(vs.view)
    end
    pingLayer:SetFrameLevel(vs.view:GetFrameLevel() + 450)    -- above every pin, under another map's cover
    local p = pings[who] or {}
    pings[who] = p
    p.map, p.x, p.y, p.t0 = map, x, y, GetTime()
    p.f = p.f or NewPing()
    p.f.name:SetText(who)
    pingLayer:SetScript("OnUpdate", PingUpdate)
end

local function Announce(who, map, x, y, quiet)
    local db = CloudeMapDB or {}
    local n = ns.NodeOf and ns.NodeOf(map)
    do
        local snd = PING_SOUNDS[tonumber(db.pingSound) or 1]
        if not quiet and db.pingSound ~= 0 and snd and PlaySound then pcall(PlaySound, snd[2], "SFX") end
        if db.pingChat == true and ns.Say then
            ns.Say(("%s pinged %s (%.1f, %.1f)"):format(who, n and n.name or ("map " .. map), x * 100, y * 100))
        end
    end
end

local function Channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

-- The minimap: its pings drawn here, ours sent to it (so the whole group sees them on their
-- minimaps, CloudeMap or not). A minimap ping is given as a fraction of the minimap's width
-- from its middle (the hero); the minimap's width in yards depends on its zoom and on being
-- indoors, and a turning minimap is turned by the hero's facing.
local MM_YARDS = {
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}
local function MinimapYards()
    if not (_G.Minimap and Minimap.GetZoom) then return end
    local ok, z = pcall(Minimap.GetZoom, Minimap)
    if not ok or Secret(z) then return end
    local inside = IsIndoors and IsIndoors()
    if Secret(inside) then return end
    return (inside and MM_YARDS.indoor or MM_YARDS.outdoor)[z or 0]
end
local function Facing()
    local rot = GetCVar and GetCVar("rotateMinimap")
    if rot ~= "1" then return 0 end
    local f = GetPlayerFacing and GetPlayerFacing()
    return (type(f) == "number" and not Secret(f)) and f or 0
end
-- a minimap ping (fractions of its width, right and up from the hero) as a point of our canvas
local function FromMinimap(fx, fy)
    local hx, hy, ypc
    if ns.HeroCanvas then hx, hy, ypc = ns.HeroCanvas() end
    local yd = MinimapYards()
    if not (hx and ypc and yd) then return end
    local x, y = fx * yd, fy * yd
    local f = Facing()
    local ex, ny = x * math.cos(f) - y * math.sin(f), x * math.sin(f) + y * math.cos(f)    -- east, north
    return hx + ex / ypc, hy - ny / ypc
end
-- our ping on the minimap too, when it lies within the minimap's circle
local function ToMinimap(cx, cy)
    local hx, hy, ypc
    if ns.HeroCanvas then hx, hy, ypc = ns.HeroCanvas() end
    local yd = MinimapYards()
    if B.noMMSend or not (hx and ypc and yd and Minimap.PingLocation) then return end
    local ex, ny = (cx - hx) * ypc, (hy - cy) * ypc
    local f = -Facing()
    local x, y = ex * math.cos(f) - ny * math.sin(f), ex * math.sin(f) + ny * math.cos(f)
    local w = Minimap:GetWidth() or 0
    local px, py = x / yd * w, y / yd * w
    if w <= 0 or math.sqrt(px * px + py * py) >= w / 2 then return end
    B.mmOwnAt = GetTime()
    pcall(Minimap.PingLocation, Minimap, px, py)
end

-- Alt+click on the map (CloudeMap.lua): the spot, by zone and position in it, to the group
function ns.onAltClick(px, py)
    if not PingOn() then return end
    local now = GetTime()
    if now - lastSent < 1 then return end                    -- one ping a second at most
    local n = ns.PickAt and ns.PickAt(px, py)
    if not (n and n.mapID and n.w and n.w > 0) then return end
    local x, y = (px - n.x) / n.w, (py - n.y) / n.h
    lastSent = now
    ShowPing(Me() or "You", n.mapID, x, y)
    ToMinimap(px, py)
    local ch = Channel()
    if not ch then
        if not B.pingSoloSaid and ns.Say then ns.Say("not in a group: only you see this ping"); B.pingSoloSaid = true end
        return
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local msg = ("P:%d:%.4f:%.4f"):format(n.mapID, x, y)
        B.sentMsg, B.sentAt = msg, now
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
        if not ok or res == false or (type(res) == "number" and res ~= 0) then
            B.pingErr = tostring(res)
            if ns.Say then ns.Say("the game did not send the ping (addon messages may be blocked here, e.g. in combat in an instance)") end
        end
    end
end

do
    local ev = CreateFrame("Frame")
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    ev:RegisterEvent("CHAT_MSG_ADDON")
    local heard = {}
    ev:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
        if Secret(prefix) or prefix ~= PREFIX or Secret(text) or type(text) ~= "string" or not PingOn() then return end
        -- the group channel sends our own message back to us: that one is drawn already (known by
        -- its text, as the sender's name may come hidden)
        if text == B.sentMsg and B.sentAt and GetTime() - B.sentAt < 5 then return end
        local map, x, y = text:match("^P:(%d+):([%d%.]+):([%d%.]+)")
        map, x, y = tonumber(map), tonumber(x), tonumber(y)
        if not (map and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
        local who = "Party member"
        if not Secret(sender) and type(sender) == "string" then
            who = Ambiguate and Ambiguate(sender, "none") or sender
            if who == Me() then return end                      -- our own, drawn already
        end
        local now = GetTime()
        if heard[who] and now - heard[who] < 0.5 then return end
        heard[who] = now
        -- the sender's minimap ping came too: the game played its sound; ours replaces its spot
        local mm = B.mmHeard[who]
        ShowPing(who, map, x, y)
        Announce(who, map, x, y, mm and now - mm < 1.5)
    end)
    -- the game's minimap pings (anyone in the group, CloudeMap or not; ours from a minimap click
    -- too), drawn on our map unless the same ping came from CloudeMap with its exact spot
    B.mmHeard = {}
    local function OnMinimapPing(...)
        -- (the arguments: the unit, then y, then x; anything before the unit (the event's name,
        -- a frame) is skipped)
        local args, i = { ... }, 1
        while i <= select("#", ...) and (type(args[i]) ~= "string" or args[i] == "MINIMAP_PING") and not Secret(args[i]) do i = i + 1 end
        local unit, fy, fx = args[i], args[i + 1], args[i + 2]
        if not PingOn() or Secret(unit) or Secret(fx) or Secret(fy) or type(unit) ~= "string" or type(fx) ~= "number" or type(fy) ~= "number" then return end
        B.mmLast = ("%s x %.3f y %.3f"):format(unit, fx, fy)
        -- (given as fractions of the minimap's width; should a client give pixels, they are turned into that)
        if math.abs(fx) > 1 or math.abs(fy) > 1 then
            local w = _G.Minimap and Minimap:GetWidth() or 0
            if w <= 0 then return end
            fx, fy = fx / w, fy / w
        end
        local now = GetTime()
        local own = UnitIsUnit and UnitIsUnit(unit, "player")
        if Secret(own) then own = false end
        if own and B.mmOwnAt and now - B.mmOwnAt < 1.5 then return end      -- sent from our map: drawn already
        local who = own and (Me() or "You") or "Party member"
        local name = (not own) and UnitName and UnitName(unit)
        if name and not Secret(name) then who = name end
        B.mmHeard[who] = now
        if not own and heard[who] and now - heard[who] < 1.5 then return end -- CloudeMap's exact spot is shown
        local cx, cy = FromMinimap(fx, fy)
        if not cx then return end
        local n = ns.PickAt and ns.PickAt(cx, cy)
        if not (n and n.mapID and n.w and n.w > 0) then return end
        ShowPing(who, n.mapID, (cx - n.x) / n.w, (cy - n.y) / n.h)
        if not own then Announce(who, n.mapID, (cx - n.x) / n.w, (cy - n.y) / n.h, true) end
    end
    -- MINIMAP_PING is a callback event in this client and registering for it from an addon is
    -- blocked (protected), so only the plain RegisterEvent route is tried, and only where the
    -- client says it is an ordinary event; otherwise minimap pings are not shown here
    local mmf = CreateFrame("Frame")
    local hooked = false
    local isCb = C_EventUtils and C_EventUtils.IsCallbackEvent and select(2, pcall(C_EventUtils.IsCallbackEvent, "MINIMAP_PING"))
    if not isCb and not (C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid("MINIMAP_PING")) then
        hooked = pcall(mmf.RegisterEvent, mmf, "MINIMAP_PING")
        if hooked then mmf:SetScript("OnEvent", function(_, _, ...) OnMinimapPing(...) end) end
    end
    -- remember what the game blocked for us (shown in /cmap status); a blocked minimap ping
    -- turns sending to the minimap off for the session
    mmf:RegisterEvent("ADDON_ACTION_BLOCKED")
    mmf:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    local prev = mmf:GetScript("OnEvent")
    mmf:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            local who, fn = ...
            if who == ADDON then
                B.blocked = tostring(fn)
                if tostring(fn):find("PingLocation") then B.noMMSend = true end
            end
            return
        end
        if prev then prev(self, event, ...) end
    end)
    B.mmHooked, B.OnMinimapPing = hooked, OnMinimapPing
end

-- Options -> Pings: on/off, chat line, sound (each sound plays when picked). Built (and filled
-- again) in the Options lists' common look (CloudeMap.lua: ns.FillMenu); the Options menu shows
-- it beside its entry.
function ns.PingMenu()
    local m = B.pingMenu
    if not m then
        m = ns.MenuPanel()
        B.pingMenu = m
    end
    local db = CloudeMapDB
    local items = {
        { kind = "check", text = "Pings", on = PingOn, click = function() if db.ping == false then db.ping = nil else db.ping = false end end,
          tip = "Alt+click the map to ping a spot for your party or raid. Group members with CloudeMap see it on their map, and the spot is placed on your own minimap. Off: no pings sent or shown." },
        { kind = "check", text = "Chat line for pings", on = function() return db.pingChat == true end,
          click = function() db.pingChat = (db.pingChat ~= true) or nil end, tip = "A line in chat with who pinged where." },
        { kind = "head", text = "Sound" },
        { kind = "radio", text = "None", on = function() return db.pingSound == 0 end, click = function() db.pingSound = 0 end },
    }
    for i, snd in ipairs(PING_SOUNDS) do
        items[#items + 1] = { kind = "radio", text = snd[1],
            on = function() return (tonumber(db.pingSound) or 1) == i and db.pingSound ~= 0 end,
            click = function() db.pingSound = i; if PlaySound then pcall(PlaySound, snd[2], "SFX") end end }
    end
    ns.FillMenu(m, items)
    m:Show()
    return m
end
end


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
