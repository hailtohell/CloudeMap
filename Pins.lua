-- CloudeMap | pins: one registry that everything drawn on top of the map goes through.
--
-- CloudeMap's own categories (flight masters, dungeon entrances ...) use it, and so can
-- any other addon: it is exposed as the global `CloudeMap`.
--
--   CloudeMap.RegisterCategory(id, {
--       name     = "Herb locations",        -- shown in the Pins menu
--       default  = true,                    -- on or off until the player changes it
--       addon    = "Name",                  -- drawn for another addon: listed under "Other addons" in the menu
--       bulk     = true,                    -- hundreds at once (gathering nodes): drawn after every other category
--       minScale = 0.3,                     -- map zoom (title bar) below which it is hidden
--       size     = 18,                      -- icon size in screen pixels
--       atlas    = "...", texture = "...",  -- default icon, a pin can bring its own
--       texCoord = { l, r, t, b },
--       order    = 100,                     -- position in the menu (lower first)
--   })
--   CloudeMap.SetPins(id, { pin, pin, ... })   -- replaces every pin of the category
--   CloudeMap.AddPin(id, pin)                  -- one more pin
--   CloudeMap.ClearPins(id)
--   CloudeMap.IsEnabled(id) / CloudeMap.SetEnabled(id, bool)
--
--   pin = {
--       map = uiMapID, x = 0..1, y = 0..1,     -- the place, on that map (what C_Map hands out)
--       atlas = "..." (or a list of names: the first the client has), texture = "...", texCoord = { l, r, t, b }, textureIndex = n (POIIcons),
--       size = 18, color = { r, g, b, a },     -- all optional
--       name = "Tooltip title", text = "line" or { "line", "line" },
--       onTooltip = function(tooltip, pin) end,    -- replaces the default tooltip
--       onClick = function(pin, button) end,
--       onEnter = function(frame, pin) end,        -- takes the hover over entirely (with onLeave)
--   }
--
-- The icon is the first one that exists of: atlas, texture, textureIndex, the category's
-- own, a coloured square. Pins on a map CloudeMap does not show are skipped.

local ADDON, ns = ...

local P = { cats = {}, order = {}, rev = 0, menuRev = 0 }
ns.pins = P
-- The public face for other addons: the same registry, except that what they register is listed
-- under "Other addons" in the Pins menu (under the addon name they give, else the category's).
_G.CloudeMap = setmetatable({
    RegisterCategory = function(id, def)
        def = type(def) == "table" and def or {}
        if def.addon == nil then def.addon = def.name or tostring(id) end
        return P.RegisterCategory(id, def)
    end,
}, { __index = P, __newindex = P })

-- /cmap prof: time spent in each part of CloudeMap, from the moment it is switched on.
-- Off, it costs one table look-up per measured call.
local prof = { on = false, sum = {}, max = {}, n = {}, frames = 0, since = 0 }
ns.prof = prof
function prof.Add(name, ms)
    prof.sum[name] = (prof.sum[name] or 0) + ms
    prof.n[name] = (prof.n[name] or 0) + 1
    if not prof.max[name] or ms > prof.max[name] then prof.max[name] = ms end
end
function prof.Time(name, fn, ...)
    if not prof.on then return fn(...) end
    local t = debugprofilestop()
    local a, b, c = fn(...)
    prof.Add(name, debugprofilestop() - t)
    return a, b, c
end
function prof.Start()
    prof.on, prof.sum, prof.max, prof.n, prof.frames, prof.since = true, {}, {}, {}, 0, GetTime()
end
function prof.Report()
    local names = {}
    for k in pairs(prof.sum) do names[#names + 1] = k end
    table.sort(names, function(a, b) return prof.sum[a] > prof.sum[b] end)
    local f = math.max(prof.frames, 1)
    local out = { ("%d frames in %.1f s (frames counted while the map is open)"):format(prof.frames, GetTime() - prof.since),
        "part | ms per frame | total ms | calls | worst call ms" }
    for _, k in ipairs(names) do
        out[#out + 1] = ("%s | %.3f | %.1f | %d | %.2f"):format(k, prof.sum[k] / f, prof.sum[k], prof.n[k] or 0, prof.max[k] or 0)
    end
    return out
end

local db
local function Changed() P.rev = P.rev + 1; if P.onChange then P.onChange() end end

local function SafeNum(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == "number" and v == v and v > -math.huge and v < math.huge then return v end
end
local function Str(s)
    if issecretvalue and issecretvalue(s) then return nil end
    if type(s) == "string" and s ~= "" then return s end
end
local function XY(pos)
    if type(pos) ~= "table" then return end
    local x, y = pos.x, pos.y
    if (x == nil or y == nil) and type(pos.GetXY) == "function" then
        local ok, a, b = pcall(pos.GetXY, pos)
        if ok then x, y = a, b end
    end
    x, y = SafeNum(x), SafeNum(y)
    if x and y and (x > 0 or y > 0) then return x, y end
end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
local function SortOrder()
    table.sort(P.order, function(a, b)
        local ca, cb = P.cats[a], P.cats[b]
        if ca.order ~= cb.order then return ca.order < cb.order end
        return ca.name < cb.name
    end)
end

function P.RegisterCategory(id, def)
    if type(id) ~= "string" then return end
    def = def or {}
    local c = P.cats[id]
    if not c then
        c = { id = id, pins = {}, order = 100, name = id, default = true, minScale = 0, size = 18 }
        P.cats[id] = c
        P.order[#P.order + 1] = id
    end
    for _, k in ipairs({ "name", "default", "minScale", "size", "atlas", "texture", "texCoord", "order", "color", "always", "noCount", "scaleKey", "addon", "bulk" }) do
        if def[k] ~= nil then c[k] = def[k] end
    end
    SortOrder()
    P.menuRev = P.menuRev + 1
    Changed()
    return c
end

function P.SetPins(id, pins)
    local c = P.cats[id]
    if not c then c = P.RegisterCategory(id) end
    c.pins = type(pins) == "table" and pins or {}
    c.idx = nil
    P.menuRev = P.menuRev + 1
    Changed()
end

-- A category's pins grouped by map (built when first asked for, dropped when the pins change),
-- so drawing looks only at the maps on screen
function P.ByMap(c)
    local idx = c.idx
    if idx then return idx end
    idx = {}
    for _, p in ipairs(c.pins) do
        local m = p.map
        if m then
            local t = idx[m]
            if not t then t = {}; idx[m] = t end
            t[#t + 1] = p
        end
    end
    c.idx = idx
    return idx
end

function P.AddPin(id, pin)
    local c = P.cats[id] or P.RegisterCategory(id)
    c.pins[#c.pins + 1] = pin
    c.idx = nil
    P.menuRev = P.menuRev + 1
    Changed()
end

function P.ClearPins(id) P.SetPins(id, {}) end

-- Its own switch, kept apart from the "all pins" switch: what the Pins menu ticks
function P.IsChecked(id)
    local c = P.cats[id]
    if not c then return false end
    local v = db and db.pins and db.pins[id]
    if v == nil then return c.default end
    return v
end

-- Drawn at all: its own switch, unless every pin is switched off (P.SetAllOff). Each one's own
-- switch is left as it was, so switching all back on brings back just the ones that were on.
-- While all are off, a few can be shown for the time being (P.SetTemp): only those draw, and
-- they are forgotten when all are switched back on (or off again).
function P.IsEnabled(id)
    if db and db.pinsAllOff then return db.pinsTemp and db.pinsTemp[id] and P.cats[id] and true or false end
    return P.IsChecked(id)
end

function P.AllOff() return db and db.pinsAllOff and true or false end
function P.SetAllOff(off)
    if db then
        db.pinsAllOff = off and true or nil
        db.pinsTemp = nil
    end
    Changed()
end

function P.IsTemp(id) return db and db.pinsTemp and db.pinsTemp[id] and true or false end
function P.SetTemp(id, on)
    if not (db and P.cats[id]) then return end
    db.pinsTemp = db.pinsTemp or {}
    db.pinsTemp[id] = on and true or nil
    Changed()
end

function P.SetEnabled(id, on)
    if not P.cats[id] then return end
    if db then db.pins = db.pins or {}; db.pins[id] = on and true or false end
    Changed()
end

function P.Init(savedVars)
    db = savedVars
    db.pins = db.pins or {}
end

---------------------------------------------------------------------------
-- CloudeMap's own categories. Flight masters come from the game; the rest from
-- Carbonite's Classic data (Guide.lua), which uses the map ids WoW Forever uses.
---------------------------------------------------------------------------
local ICONS = "Interface\\Icons\\"
local CROP = { 0.08, 0.92, 0.08, 0.92 }       -- trims the border of an icon, as Carbonite does

P.RegisterCategory("flight",   { name = "Flight masters",       order = 10, minScale = 0.3, size = 22,
                                 texture = "Interface\\AddOns\\CloudeMap\\Gfx\\ability_mount_wyvern_01", texCoord = CROP })
P.RegisterCategory("instance", { name = "Dungeons and raids",   order = 20, minScale = 0.3, size = 22,
                                 atlas = "dungeon", color = { 0.4, 0.7, 1, 1 } })
P.RegisterCategory("classtrainer", { name = "Class trainers",       order = 30, minScale = 1.0, size = 16, texCoord = CROP, color = { 1, 0.82, 0.2, 1 } })
P.RegisterCategory("proftrainer",  { name = "Profession trainers",  order = 31, minScale = 1.0, size = 16, texCoord = CROP, color = { 1, 0.82, 0.2, 1 } })
P.RegisterCategory("innkeeper",    { name = "Innkeepers",           order = 40, minScale = 0.8, size = 16, texCoord = CROP, color = { 1, 0.82, 0.2, 1 } })
P.RegisterCategory("mailbox",      { name = "Mailboxes",            order = 41, minScale = 0.8, size = 16, texCoord = CROP, color = { 1, 0.82, 0.2, 1 } })
P.RegisterCategory("auction",      { name = "Auctioneers",          order = 42, minScale = 0.8, size = 16, texCoord = CROP, color = { 1, 0.82, 0.2, 1 } })
P.RegisterCategory("bank",         { name = "Bankers",              order = 43, minScale = 0.8, size = 16, texCoord = CROP, color = { 1, 0.82, 0.2, 1 } })
P.RegisterCategory("forge",        { name = "Anvils and forges",    order = 44, minScale = 1.0, size = 16, texCoord = CROP, color = { 1, 0.82, 0.2, 1 } })
P.RegisterCategory("link",         { name = "Zone links",           order = 50, minScale = 1.0, size = 18, color = { 0.6, 1, 0.6, 1 } })

local RAIDS = { ["Zul'Gurub"] = true, ["Naxxramas"] = true, ["Molten Core"] = true, ["Blackwing Lair"] = true,
                ["Ruins of Ahn'Qiraj"] = true, ["Temple of Ahn'Qiraj"] = true, ["Onyxia's Lair"] = true }
local FACTION = { [1] = "Alliance", [2] = "Horde" }

local function Each(list, fn)
    for _, id in ipairs(list) do fn(id) end
end

local function MapName(id)
    local mi = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return mi and Str(mi.name) or tostring(id)
end


---------------------------------------------------------------------------
-- Townsfolk from Questie's database (when Questie is installed): it is kept up to date
-- for WoW Forever, so it replaces Carbonite's older coordinates for these categories.
---------------------------------------------------------------------------
local QKINDS = {
    { cat = "innkeeper",    flag = "INNKEEPER" },
    { cat = "bank",         flag = "BANKER" },
    { cat = "auction",      flag = "AUCTIONEER" },
    { cat = "classtrainer", flag = "TRAINER", class = true },
    { cat = "proftrainer",  flag = "TRAINER", profession = true },
    { cat = "mailbox",      mailbox = true },
}
local QTEX = {
    innkeeper = ICONS .. "Spell_Shadow_Twilight", bank = ICONS .. "INV_Misc_Coin_02", auction = ICONS .. "Racial_Dwarf_FindTreasure",
    mailbox = ICONS .. "INV_Letter_15",
}
local ENGLISH_CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local qBusy, qTries, qDone = false, 0, false

local function Questie()
    local loader = _G.QuestieLoader
    if not loader then return end
    local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
    local ok2, zones = pcall(loader.ImportModule, loader, "ZoneDB")
    if ok and ok2 and db and db.NPCPointers and db.QueryNPCSingle and zones and zones.GetUiMapIdByAreaId then return db, zones, loader end
end

function P.ReadQuestie(known)
    if qBusy or qDone or not C_Timer then return end
    if not _G.QuestieLoader then return end
    local QDB, ZoneDB, loader = Questie()
    if not QDB then
        qTries = qTries + 1
        if qTries <= 12 then C_Timer.After(5, function() P.ReadQuestie(known) end) end
        return
    end
    qBusy = true
    local faction = UnitFactionGroup and UnitFactionGroup("player") == "Horde" and "H" or "A"
    local myClass = select(2, UnitClass("player"))
    local flags = QDB.npcFlags or {}
    local names = {}
    for _, n in ipairs(ENGLISH_CLASSES) do names[#names + 1] = n:lower() end
    for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for _, n in pairs(t) do if type(n) == "string" then names[#names + 1] = n:lower() end end
    end
    local mine = {}
    for _, t in ipairs({ { _G.LOCALIZED_CLASS_NAMES_MALE, 1 }, { _G.LOCALIZED_CLASS_NAMES_FEMALE, 1 } }) do
        local n = t[1] and t[1][myClass]
        if n then mine[#mine + 1] = n:lower() end
    end
    mine[#mine + 1] = (myClass or ""):lower()
    local lists = {}
    for _, k in ipairs(QKINDS) do lists[k.cat] = {} end

    local function Add(cat, spawns, name, text)
        for areaID, coords in pairs(spawns) do
            local mapID = ZoneDB:GetUiMapIdByAreaId(areaID)
            if mapID and known[mapID] then
                local out = lists[cat]
                -- a walker has every point of its path as a spawn: one pin, the first
                local n = 0
                for _, c in ipairs(coords) do
                    if c[1] and c[1] >= 0 then
                        out[#out + 1] = { map = mapID, x = c[1] / 100, y = c[2] / 100, texture = QTEX[cat],
                            texCoord = QTEX[cat] and CROP or nil, name = name, text = text }
                        n = n + 1
                        if n >= 6 then break end
                    end
                end
            end
        end
    end

    local function Mailboxes()
        local ok, folk = pcall(loader.ImportModule, loader, "Townsfolk")
        if not ok or type(folk) ~= "table" or not folk.GetMailboxes or not QDB.QueryObjectSingle then return end
        local list
        if folk.GetFactionSpecificMailboxes then
            local ok2, a, h = pcall(folk.GetFactionSpecificMailboxes)
            if ok2 then list = faction == "H" and h or a end
        end
        list = (type(list) == "table" and #list > 0) and list or folk.GetMailboxes() or {}
        for _, id in ipairs(list) do
            local spawns = QDB.QueryObjectSingle(id, "spawns")
            if spawns then Add("mailbox", spawns, "Mailbox") end
        end
    end
    pcall(Mailboxes)

    local ids = {}
    for id in pairs(QDB.NPCPointers) do ids[#ids + 1] = id end
    local i = 0
    local function Finish()
        qBusy, qDone = false, true
        for cat, list in pairs(lists) do
            if #list > 0 then
                P.SetPins(cat, list)
                if P.counts then P.counts[cat] = #list end
            end
        end
        P.questie = true
    end
    local function Step()
        local ok, finished = pcall(function()
            for _ = 1, 400 do
                i = i + 1
                local id = ids[i]
                if not id then return true end
                local f = QDB.QueryNPCSingle(id, "npcFlags") or 0
                if f ~= 0 then
                    for _, k in ipairs(QKINDS) do
                        local fl = k.flag and flags[k.flag]
                        if fl and bit.band(f, fl) ~= 0 then
                            local friendly = QDB.QueryNPCSingle(id, "friendlyToFaction") or ""
                            local spawns = QDB.QueryNPCSingle(id, "spawns")
                            local hit = friendly:find(faction, 1, true) and spawns
                            local sub = QDB.QueryNPCSingle(id, "subName") or ""
                            if hit and (k.class or k.profession) then
                                local low, isClass = sub:lower(), false
                                for _, n in ipairs(names) do if low:find(n, 1, true) then isClass = true break end end
                                if k.class then
                                    local mineHit = false
                                    for _, n in ipairs(mine) do if n ~= "" and low:find(n, 1, true) then mineHit = true break end end
                                    hit = isClass and mineHit
                                else
                                    hit = not isClass
                                end
                            end
                            if hit then
                                local nm = QDB.QueryNPCSingle(id, "name") or "?"
                                Add(k.cat, spawns, nm, sub ~= "" and sub or nil)
                            end
                        end
                    end
                end
            end
        end)
        if not ok then qBusy = false return end
        if finished then return Finish() end
        C_Timer.After(0, Step)
    end
    Step()
end

-- ids = { conts = { mapID ... }, zones = { mapID ... } }, the maps CloudeMap shows
function P.ReadGame(ids, known)
    known = known or {}
    P.known, P.zoneIDs = known, ids.zones          -- (Bridge.lua: other addons' icons)
    local all = {}
    Each(ids.conts, function(id) all[#all + 1] = id end)
    Each(ids.zones, function(id) all[#all + 1] = id end)
    local counts = {}

    -- flight masters (C_TaxiMap), continent first so a node keeps its continent position
    local flights, seen = {}, {}
    if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local F = Enum and Enum.FlightPathFaction
        Each(all, function(mapID)
            local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
            if not ok or type(list) ~= "table" then return end
            for _, info in ipairs(list) do
                local x, y = XY(info.position)
                local nid = SafeNum(info.nodeID)
                if x and nid and not seen[nid] then
                    seen[nid] = true
                    local who
                    if F and info.faction == F.Alliance then who = "Alliance"
                    elseif F and info.faction == F.Horde then who = "Horde" end
                    local f = who or "Neutral"      -- the winged boots of the game's own map, by faction
                    flights[#flights + 1] = { map = mapID, x = x, y = y,
                        atlas = { "TaxiNode_" .. f, "TaxiNode_Continent_" .. f },
                        name = Str(info.name) or "Flight master", text = who and (who .. " flight master") or "Flight master" }
                end
            end
        end)
    end
    counts.flight = #flights
    P.SetPins("flight", flights)

    local guide = ns.guide
    if not guide then P.counts = counts return end

    -- the other side's services stay off the map, as in Carbonite
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    local hide = (mine == "Horde" and 1) or (mine == "Alliance" and 2) or nil

    local cats = {}
    for _, g in ipairs(guide.services) do
        local list = cats[g.cat] or {}
        cats[g.cat] = list
        local tex = ICONS .. g.icon
        for mapID, str in pairs(g.d) do
            if known[mapID] then
                for facStr, x, y in str:gmatch("(%d+),([%d.]+),([%d.]+)") do
                    local fac = tonumber(facStr)
                    if fac ~= hide then
                        list[#list + 1] = { map = mapID, x = tonumber(x) / 100, y = tonumber(y) / 100, texture = tex,
                            name = g.label, text = FACTION[fac] }
                    end
                end
            end
        end
    end
    for cat, list in pairs(cats) do counts[cat] = #list; P.SetPins(cat, list) end

    -- dungeon and raid entrances; the game's own list adds the ones Carbonite does not know
    local inst, names = {}, {}
    for _, e in ipairs(guide.instances) do
        local name, lo, hi, size, mapID, x, y = e[1], e[2], e[3], e[4], e[5], e[6], e[7]
        if known[mapID] then
            local raid = RAIDS[name] or size >= 20
            names[name:lower()] = true
            inst[#inst + 1] = { map = mapID, x = x / 100, y = y / 100, atlas = raid and "raid" or "dungeon", name = name,
                text = (lo > 0 and ("Level %d-%d, %s"):format(lo, hi, raid and ("raid of " .. size) or ("group of " .. size)) or nil) }
        end
    end
    local entrances = C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap
    if entrances then
        Each(all, function(mapID)
            local ok, list = pcall(entrances, mapID)
            if not ok or type(list) ~= "table" then return end
            for _, e in ipairs(list) do
                local x, y = XY(e.position)
                local name = Str(e.name)
                if x and name and not names[name:lower()] then
                    names[name:lower()] = true
                    inst[#inst + 1] = { map = mapID, x = x, y = y, atlas = Str(e.atlasName) or "dungeon",
                        name = name, text = Str(e.description) }
                end
            end
        end)
    end
    counts.instance = #inst
    P.SetPins("instance", inst)

    -- where one zone runs into the next, a pin on each side
    local links = {}
    for _, l in ipairs(guide.links) do
        local a, ax, ay, b, bx, by = l[1], l[2], l[3], l[4], l[5], l[6]
        if known[a] and known[b] then
            links[#links + 1] = { map = a, x = ax / 100, y = ay / 100, name = "To " .. MapName(b), texture = ICONS .. "Spell_Arcane_PortalOrgrimmar", texCoord = CROP }
            links[#links + 1] = { map = b, x = bx / 100, y = by / 100, name = "To " .. MapName(a), texture = ICONS .. "Spell_Arcane_PortalOrgrimmar", texCoord = CROP }
        end
    end
    counts.link = #links
    P.SetPins("link", links)

    P.counts = counts
    -- (P.ReadQuestie exists but is not used: Carbonite's Forever data is the one that matches the game)
end
