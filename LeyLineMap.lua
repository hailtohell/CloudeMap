-- CloudeMap | ley lines and elemental convergences (data: Leylines.lua).

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

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
        -- last, the places still waiting for review by LeyLines' maintainer (Leylines.lua): only
        -- where nothing confirmed or learned in play is already known, and said to be unconfirmed
        local unconfirmed = 0
        for kind, maps in pairs(type(ns.LEYLINES_UNCONFIRMED) == "table" and ns.LEYLINES_UNCONFIRMED or {}) do
            for map, xyr in pairs(maps) do
                for i = 1, #xyr - 2, 3 do
                    local r = tonumber(xyr[i + 2]) or 1
                    local note = ("|cffff8040Unconfirmed|r: a player report to the LeyLines addon not yet reviewed (%d %s); may be off or missing")
                        :format(r, r == 1 and "report" or "reports")
                    if Add(kind, map, xyr[i], xyr[i + 1], note) then unconfirmed = unconfirmed + 1 end
                end
            end
        end
        B.leyCount, B.convCount, B.leyLearned, B.leyUnconfirmed = #lists.L, #lists.V, learned, unconfirmed
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
