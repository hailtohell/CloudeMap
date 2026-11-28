-- CloudeMap | pings for the group.

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

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
local PING_SOUND = 3175         -- the game's map ping sound (MAP_PING), for every ping
local pings, pingLayer = {}, nil
local vs = {}                   -- the view as last drawn: frame, offset, scale (ns.afterUpdate)
B.viewState = vs
local lastSent = 0

local function PingOn() return true end        -- (pings are always on: there is no setting)
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

local waiting = {}
local function ShowPing(who, map, x, y)
    if not vs.view then
        -- the map was not drawn yet this session: kept for when it is (B.pingWaiting)
        waiting[who] = { map, x, y, GetTime() }
        B.pingStat.waited = B.pingStat.waited + 1
        return
    end
    if not (ns.NodeOf and ns.NodeOf(map)) then
        B.pingStat.offmap = B.pingStat.offmap + 1     -- (a map this one does not draw, e.g. inside a dungeon)
        return
    end
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

B.pingStat = { heard = 0, shown = 0, waited = 0, offmap = 0, off = 0, last = nil }
function B.pingWaiting()
    if not next(waiting) then return end
    local now = GetTime()
    for who, w in pairs(waiting) do
        waiting[who] = nil
        if now - w[4] < PING_LIFE then
            ShowPing(who, w[1], w[2], w[3])
            if pings[who] then pings[who].t0 = w[4] end         -- (its age kept: it fades on time)
        end
    end
end

-- a ping's sound, and (when its sender asked for it: Left Alt+right click) a line in chat with who and where
local function Announce(who, map, x, y, quiet, chat)
    if not quiet and PlaySound then pcall(PlaySound, PING_SOUND, "SFX") end
    if chat and ns.Say then
        local n = ns.NodeOf and ns.NodeOf(map)
        ns.Say(("%s pinged %s (%.1f, %.1f)"):format(who, n and n.name or ("map " .. map), x * 100, y * 100))
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
    if InCombatLockdown and InCombatLockdown() then return end     -- (the minimap's own ping: not in a fight)
    local ex, ny = (cx - hx) * ypc, (hy - cy) * ypc
    local f = -Facing()
    local x, y = ex * math.cos(f) - ny * math.sin(f), ex * math.sin(f) + ny * math.cos(f)
    local w = Minimap:GetWidth() or 0
    local px, py = x / yd * w, y / yd * w
    if w <= 0 or math.sqrt(px * px + py * py) >= w / 2 then return end
    B.mmOwnAt = GetTime()
    pcall(Minimap.PingLocation, Minimap, px, py)
end

-- Left Alt+left click on the map (CloudeMap.lua): the spot, by zone and position in it, to the
-- group, with the map ping sound. Left Alt+right click: and a line in chat with who pinged where,
-- for everyone in the group (and you)
function ns.onAltClick(px, py, chat)
    local now = GetTime()
    if now - lastSent < 1 then return end                    -- one ping a second at most
    local n = ns.PickAt and ns.PickAt(px, py)
    if not (n and n.mapID and n.w and n.w > 0) then return end
    local x, y = (px - n.x) / n.w, (py - n.y) / n.h
    lastSent = now
    ShowPing(Me() or "You", n.mapID, x, y)
    ToMinimap(px, py)
    Announce(Me() or "You", n.mapID, x, y, false, chat)
    local ch = Channel()
    if not ch then
        if not B.pingSoloSaid and ns.Say then ns.Say("not in a group: only you see this ping"); B.pingSoloSaid = true end
        return
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local msg = ("P:%d:%.4f:%.4f%s"):format(n.mapID, x, y, chat and ":c" or "")
        B.sentMsg, B.sentAt = msg, now
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
        B.pingSent = (B.pingSent or 0) + 1
        B.pingSentLast = ("%s via %s: %s"):format(msg, ch, ok and tostring(res) or ("error " .. tostring(res)))
        if not ok or res == false or (type(res) == "number" and res ~= 0) then
            B.pingErr = tostring(res)
            if ns.Say then ns.Say("the game did not send the ping (addon messages may be blocked here, e.g. in combat in an instance)") end
        end
    end
end

do
    local ev = CreateFrame("Frame")
    -- (the game delivers another addon's messages only for a prefix registered here: what it said is
    -- kept for /cmap status)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        B.pingPrefix = ok and tostring(res) or ("error " .. tostring(res))
    else
        B.pingPrefix = "no API"
    end
    ev:RegisterEvent("CHAT_MSG_ADDON")
    local heard = {}
    ev:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
        if Secret(prefix) or prefix ~= PREFIX or Secret(text) or type(text) ~= "string" then return end
        -- the group channel sends our own message back to us: that one is drawn already (known by
        -- its text, as the sender's name may come hidden)
        if text == B.sentMsg and B.sentAt and GetTime() - B.sentAt < 5 then return end
        local map, x, y, flag = text:match("^P:(%d+):([%d%.]+):([%d%.]+):?(%a*)")
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
        B.pingStat.heard = B.pingStat.heard + 1
        B.pingStat.last, B.pingStat.at = ("%s on map %d"):format(who, map), now
        ShowPing(who, map, x, y)
        Announce(who, map, x, y, mm and now - mm < 1.5, flag == "c")
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
                local fight = InCombatLockdown and InCombatLockdown()
                B.blockedN = (B.blockedN or 0) + 1
                B.blocked = tostring(fn) .. (fight and " in a fight" or " out of a fight")
                if tostring(fn):find("PingLocation") then B.noMMSend = true end
            end
            return
        end
        if prev then prev(self, event, ...) end
    end)
    B.mmHooked, B.OnMinimapPing = hooked, OnMinimapPing
end

end
