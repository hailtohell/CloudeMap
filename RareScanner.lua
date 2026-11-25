-- CloudeMap | RareScanner: its rares, treasures and events.

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

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
B.RarePins = RarePins
