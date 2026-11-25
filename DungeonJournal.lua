-- CloudeMap | Dungeon Journal (ForeverDungeonJournal) maps and battleground maps in the window, and the journal's map markers.

local ADDON, ns = ...
local P, B = ns.pins, ns.bridge
if not (P and B) then return end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Spread, clamp, Now, Secret = B.Spread, B.clamp, B.Now, B.Secret

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
            pickMenu = CreateFrame("Frame", nil, UIParent)       -- (beside the window, hidden with it: CloudeMap.lua ns.Detach)
            if ns.Detach then ns.Detach(pickMenu) end
            pickMenu:SetFrameStrata("DIALOG")
            pickMenu:SetClampedToScreen(true)
            pickMenu:EnableMouse(true)
            local back = pickMenu:CreateTexture(nil, "BACKGROUND")
            back:SetAllPoints()
            back:SetColorTexture(0.06, 0.06, 0.07, 0.96)
            if ns.SkinPanel then ns.SkinPanel(pickMenu, back) end         -- (Looks -> Vanilla style)
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
                local k = CloudeMapDB and CloudeMapDB.heroSize or 1     -- (Options: Player marker size)
                local tex = Put(x, y, 30 * k, 6)
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
