-- CloudeMap | quest areas and quest markers: the game's own quest blobs and buttons, laid over the zones.

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

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
        blobOK = false; B.blobOK = blobOK
        return
    end
    blobOK = true; B.blobOK = blobOK
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
local hl, hlSt      -- the area lit by pointing at a quest marker (B.QuestHover, below)

local function DrawBlobs(view, canvas, ox, oy, scale, mode, shown, db)
    local used = {}
    last.view, last.ox, last.oy, last.scale, last.shown = view, ox, oy, scale, shown
    if not B.hover then B.HoverFrame(view) end
    last.canvas, last.level, last.mode = canvas, canvas:GetFrameLevel(), mode
    -- the lit area follows the map too (it was left at the zoom it was lit at)
    local h = hlSt
    if h and h.node then
        local s, x, y = h.node.w * scale / BLOB_W, ox + h.node.x * scale, oy + h.node.y * scale
        if abs(h.s - s) > 0.0005 or abs(h.x - x) > 0.25 or abs(h.y - y) > 0.25 then
            h.s, h.x, h.y = s, x, y
            pcall(Paint, hl, h, view)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if hlSt == h then pcall(Paint, hl, h, view) end end)
            end
        end
    end
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

-- The quest marker: CloudeMap's own button drawn with the game's own art (the atlases its
-- POIButtonTemplate uses, as in Blizzard_POIButton/POIButton.lua). Not the game's button: one made
-- from its template counts as the game's, and its own code then gets blocked and blamed on us.
local CLASS_ART = {}        -- [classification] = atlas family
do
    local C = Enum and Enum.QuestClassification
    if C then
        if C.Legendary then CLASS_ART[C.Legendary] = "UI-QuestPoiLegendary" end
        if C.Campaign then CLASS_ART[C.Campaign] = "UI-QuestPoiCampaign" end
        if C.Calling then CLASS_ART[C.Calling] = "UI-QuestPoiCampaign" end
        if C.Recurring then CLASS_ART[C.Recurring] = "UI-QuestPoiRecurring" end
        if C.Important then CLASS_ART[C.Important] = "UI-QuestPoiImportant" end
        if C.Meta then CLASS_ART[C.Meta] = "UI-QuestPoiWrapper" end
    end
end
local TURN_IN = {
    ["UI-QuestPoiLegendary"] = "UI-QuestPoiLegendary-QuestBangTurnIn",
    ["UI-QuestPoiCampaign"] = "UI-QuestPoiCampaign-QuestBangTurnIn",
    ["UI-QuestPoiRecurring"] = "UI-QuestPoiRecurring-QuestBangTurnIn",
    ["UI-QuestPoiImportant"] = "UI-QuestPoiImportant-QuestBangTurnIn",
    ["UI-QuestPoiWrapper"] = "UI-QuestPoiWrapper-QuestBangTurnIn",
}

local function Atlas(t, name)
    if t:SetAtlas(name, true) == false then t:SetTexture(nil) end
end

local function PoiDown(self)
    self.down = true
    self.Display:ClearAllPoints(); self.Display:SetPoint("CENTER", 1, -1)
    self.Normal:Hide(); self.Pushed:Show()
end

local function PoiUp(self)
    self.down = nil
    self.Display:ClearAllPoints(); self.Display:SetPoint("CENTER")
    self.Normal:Show(); self.Pushed:Hide()
end

local function NewPoi(view, canvas)
    local f = CreateFrame("Button", nil, view)
    f:SetSize(20, 20)
    f:SetFrameLevel(canvas:GetFrameLevel() + 8)
    f:RegisterForClicks("LeftButtonUp")
    f.Glow = f:CreateTexture(nil, "BACKGROUND")
    f.Glow:SetPoint("CENTER"); f.Glow:SetBlendMode("ADD")
    f.Normal = f:CreateTexture(nil, "BORDER")
    f.Normal:SetPoint("CENTER")
    f.Pushed = f:CreateTexture(nil, "BORDER")
    f.Pushed:SetPoint("CENTER"); f.Pushed:Hide()
    f.Display = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.Display:SetPoint("CENTER")
    f.Light = f:CreateTexture(nil, "OVERLAY")
    f.Light:SetPoint("CENTER"); f.Light:SetBlendMode("ADD"); f.Light:Hide()
    f:SetScript("OnMouseDown", PoiDown)
    f:SetScript("OnMouseUp", PoiUp)
    f:SetScript("OnEnter", function(self)
        self.Light:Show()
        if self.smQuest and QuestTip then QuestTip(self.smQuest, self) end
        if self.smQuest then B.QuestHover(self.smQuest, self.smNode) end
    end)
    f:SetScript("OnLeave", function(self)
        self.Light:Hide()
        if self.down then PoiUp(self) end
        if GameTooltip then GameTooltip:Hide() end
        B.QuestHover()
    end)
    -- a click tracks the quest (the arrow on the screen), or stops tracking it, as the game's does
    f:SetScript("OnClick", function(self)
        local q, ST = self.smQuest, C_SuperTrack
        if not (q and ST) then return end
        if self.smActive then
            if ST.ClearAllSuperTracked then pcall(ST.ClearAllSuperTracked) end
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
        else
            if ST.SetSuperTrackedQuestID then pcall(ST.SetSuperTrackedQuestID, q) end
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        end
        -- (SUPER_TRACKING_CHANGED, below, has the map drawn again with the new look)
    end)
    return f
end

local function SetupPoi(f, q, isActive)
    f.smQuest, f.smActive = q, isActive
    local cls
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local ok, v = pcall(C_QuestInfoSystem.GetQuestClassification, q)
        if ok then cls = v end
    end
    local fam = CLASS_ART[cls]
    local base = fam or "UI-QuestPoi"
    local sel = isActive and "-SuperTracked" or ""
    Atlas(f.Normal, base .. "-QuestNumber" .. sel)
    Atlas(f.Pushed, base .. "-QuestNumber-Pressed" .. sel)
    Atlas(f.Glow, base .. "-OuterGlow")
    Atlas(f.Light, base .. "-InnerGlow")
    f.Glow:SetShown(isActive and true or false)
    if QuestDone(q) then
        Atlas(f.Display, fam and TURN_IN[fam] or "UI-QuestIcon-TurnIn-Normal")
    else
        Atlas(f.Display, isActive and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow")
    end
end

-- after a fight: the quest buttons it held back are made (the map drawn again)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        if B.poiWait then B.poiWait = nil; if P.onChange then P.onChange() end end
    end)
end

local fbKey
local function DrawPois(view, canvas, ox, oy, scale, mode, shown, db)
    local used = {}
    local on = P.IsEnabled("questpoi")
    if on and poiOK ~= false then
        local active = ActiveQuest()
        -- (the buttons are CloudeMap's own, so a fight changes nothing for them)
        local fight = false
        for _, n in ipairs(shown) do
            local xy = poiXY[n.mapID]
            for _, q in ipairs(zoneQuests[n.mapID] or {}) do
                local p = xy and xy[q]
                if p then
                    local key = n.mapID * 1000000 + q
                    local f = pois[key]
                    if not f and fight then B.poiWait = true break end
                    f = f or NewPoi(view, canvas)
                    if not f then break end
                    pois[key] = f
                    used[key] = true
                    f.smNode = n
                    local sig = questRev * 2 + (q == active and 1 or 0)
                    if poiState[key] ~= sig and fight then B.poiWait = true
                    elseif poiState[key] ~= sig then
                        local ok, err = pcall(SetupPoi, f, q, q == active)
                        if not ok then poiOK = false; B.poiOK = false; B.poiErr = err; break end
                        poiOK = true; B.poiOK = poiOK
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
        -- a ping heard before the map was ever drawn: shown now, if it is still young
        if B.pingWaiting then B.pingWaiting() end
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
    B.QuestsChanged = Again
end

-- the quest area under the pointer: looked at by a frame that belongs to the map, so it runs only
-- while the map is open, and only while the pointer is on it (or a tooltip of ours is to be
-- taken down)
function B.HoverFrame(view)
    if B.hover or not view then return end
    local h = CreateFrame("Frame", nil, view)
    B.hover = h
    local acc = 0
    h:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.08 then return end
        acc = 0
        if not (view:IsMouseOver() or tipQuest) then return end
        pcall(HoverCheck)
    end)
end
