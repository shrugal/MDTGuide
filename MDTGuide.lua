local Name, Addon = ...

MDTG = Addon
MDTGuideActive = false
MDTGuideRoute = ""

local HEIGHT = 200
local WIDTH_SIDE = 200
local ZOOM = 1.8

local COLOR_CURR = {0.13, 1, 1}
local COLOR_DEAD = {0.55, 0.13, 0.13}

-- Use route estimation
Addon.BFS = true
-- # of hops before limiting branching
Addon.BFS_BRANCH = 2
-- # of hops to track back from previous result
Addon.BFS_TRACK_BACK = 15
-- Distance weight to same pull
Addon.BFS_WEIGHT_PULL = 0.1
-- Distance weight to a following pull
Addon.BFS_WEIGHT_FORWARD = 0.3
-- Distance weight to a previous pull
Addon.BFS_WEIGHT_ROUTE = 0.5
-- Distance weight to same group
Addon.BFS_WEIGHT_GROUP = 0.7
-- Weight by path length
Addon.BFS_WEIGHT_LENGTH = 0.99
-- Max rounds per frame
Addon.BFS_MAX_FRAME = 15
-- Scale MAX_FRAME with elapsed time
Addon.BFS_MAX_FRAME_SCALE = 0.5
-- Total time to spend on route estimation (in s)
Addon.BFS_MAX_TOTAL = 5
-- Max queue index for new candidates paths
Addon.BFS_QUEUE_INSERT = 300
-- Max # of path candidates in the queue
Addon.BFS_QUEUE_MAX = 1000

Addon.PATTERN_INSTANCE_RESET = "^" .. INSTANCE_RESET_SUCCESS:gsub("%%s", ".+") .. "$"

Addon.hits, Addon.kills = {}, {}

local toggleButton, frames
local currentDungeon
local queue, weights, pulls = {}, {}, {}
local co, rerun, zoom, retry
local bfs = true

Addon.DEBUG = false
local debug = function (...)
    if Addon.DEBUG then print(...) end
end

-- ---------------------------------------
--              Toggle mode
-- ---------------------------------------

function Addon.EnableGuideMode(noZoom)
    if MDTGuideActive then return end
    MDTGuideActive = true

    local mdt, main = Addon.GetMDT()

    -- Hide frames
    for _,f in pairs(Addon.GetFramesToHide()) do
       (f.frame or f):Hide()
    end

    -- Resize
    mdt:StartScaling()
    mdt:SetScale(HEIGHT / 555)
    mdt:UpdateMap(true)

    -- Zoom
    if not noZoom and main.mapPanelFrame:GetScale() > 1 then
        Addon.ZoomBy(ZOOM)
    end

    -- Adjust top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", WIDTH_SIDE, 0)
    f:SetHeight(25)

    -- Adjust side panel
    f = main.sidePanel
    f:SetWidth(WIDTH_SIDE)
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, 25)
    f:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT")
    main.closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 7, 4)
    toggleButton:SetPoint("RIGHT", main.closeButton, "LEFT")

    -- Adjust enemy info
    f = main.sidePanel.PullButtonScrollGroup
    f.frame:ClearAllPoints()
    f.frame:SetPoint("TOPLEFT", main.scrollFrame, "TOPRIGHT")
    f.frame:SetPoint("BOTTOMLEFT", main.scrollFrame, "BOTTOMRIGHT")
    f.frame:SetWidth(WIDTH_SIDE)

    -- Hide some special frames
    if main.toolbar:IsShown() then
        main.toolbar.toggleButton:GetScript("OnClick")()
    end

    mdt:ToggleFreeholdSelector()
    mdt:ToggleBoralusSelector()

    -- Adjust enemy info frame
    if mdt.EnemyInfoFrame and mdt.EnemyInfoFrame:IsShown() then
        Addon.AdjustEnemyInfo(mdt)
    end

    -- Prevent closing with esc
    for i,v in pairs(UISpecialFrames) do
        if v == "MethodDungeonToolsFrame" then tremove(UISpecialFrames, i) break end
    end

    return true
end

function Addon.DisableGuideMode()
    if not MDTGuideActive then return end
    MDTGuideActive = false

    local mdt, main = Addon.GetMDT()

    for _,f in pairs(Addon.GetFramesToHide()) do
        (f.frame or f):Show()
    end

    -- Reset top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT")
    f:SetHeight(30)

    -- Adjust side panel
    f = main.sidePanel
    f:SetWidth(251)
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, 30)
    f:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", 0, -30)
    main.closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    toggleButton:SetPoint("RIGHT", main.maximizeButton, "LEFT", 10, 0)

    -- Reset enemy info
    f = main.sidePanel.PullButtonScrollGroup.frame
    f:ClearAllPoints()
    f:SetWidth(248)
    f:SetHeight(410)
    f:SetPoint("TOPLEFT", main.sidePanel.WidgetGroup.frame, "BOTTOMLEFT", -4, -32)
    f:SetPoint("BOTTOMLEFT", main.sidePanel, "BOTTOMLEFT", 0, 30)

    -- Reset size
    Addon.ZoomBy(1 / ZOOM)
    mdt:GetDB().nonFullscreenScale = 1
    mdt:Minimize()

    -- Adjust enemy info frame
    if mdt.EnemyInfoFrame and mdt.EnemyInfoFrame:IsShown() then
        Addon.AdjustEnemyInfo(mdt)
    end

    -- Allow closing with esc
    local found
    for _,v in pairs(UISpecialFrames) do
        if v == "MethodDungeonToolsFrame" then found = true break end
    end
    if not found then
        tinsert(UISpecialFrames, "MethodDungeonToolsFrame")
    end

     return true
end

function Addon.ToggleGuideMode()
    if MDTGuideActive then
        Addon.DisableGuideMode()
    else
        Addon.EnableGuideMode()
    end
end

function Addon.AdjustEnemyInfo(mdt)
    local f = mdt.EnemyInfoFrame
    if f then
        if not MDTGuideActive then
            f.frame:ClearAllPoints()
            f.frame:SetAllPoints(MethodDungeonToolsScrollFrame)
            f:EnableResize(false)
            f.frame:SetMovable(false)
            f.frame.StartMoving = function () end
        elseif f:GetPoint(2) then
            f:ClearAllPoints()
            f:SetPoint("CENTER")
            f.frame:SetMovable(true)
            f.frame.StartMoving = UIParent.StartMoving
            f:SetWidth(800)
            f:SetHeight(550)
        end

        mdt:UpdateEnemyInfoFrame()
        f.enemyDataContainer.stealthCheckBox:SetWidth((f.enemyDataContainer.frame:GetWidth()/2)-40)
        f.enemyDataContainer.stealthDetectCheckBox:SetWidth((f.enemyDataContainer.frame:GetWidth()/2))
        f.spellScroll:SetWidth(f.spellScrollContainer.content:GetWidth() or 0)
    end
end

-- ---------------------------------------
--                 Zoom
-- ---------------------------------------

function Addon.Zoom(scale, scrollX, scrollY)
    local mdt, main = Addon.GetMDT()
    local scroll, map = main.scrollFrame, main.mapPanelFrame

    map:SetScale(scale)
    scroll:SetHorizontalScroll(scrollX)
    scroll:SetVerticalScroll(scrollY)
    mdt:ZoomMap(0)
end

function Addon.ZoomBy(z)
    local _, main = Addon.GetMDT()
    local scroll, map = main.scrollFrame, main.mapPanelFrame

    local scale = z * map:GetScale()
    local n = (z-1)/2 / scale
    local scrollX = scroll:GetHorizontalScroll() + n * scroll:GetWidth()
    local scrollY = scroll:GetVerticalScroll() + n * scroll:GetHeight()

    Addon.Zoom(scale, scrollX, scrollY)
end

function Addon.ZoomTo(minX, maxY, maxX, minY)
    local mdt, main = Addon.GetMDT()

    local s = mdt:GetScale()
    local w = main:GetWidth()
    local h = main:GetHeight()

    minX, maxY, maxX, minY = s*minX, s*maxY, s*maxX, s*minY

    local diffX = maxX - minX
    local diffY = maxY - minY
    local scale = 0.8 * min(10, w / diffX, h / diffY)
    local scrollX = minX + diffX/2 - w/2 / scale
    local scrollY = -maxY + diffY/2 - h/2 / scale

    Addon.Zoom(scale, scrollX, scrollY)
end

function Addon.ZoomToPull(n)
    local mdt = Addon.GetMDT()
    n = n or mdt:GetCurrentPull()
    local pull = Addon.GetCurrentPulls()[n]

    if pull then
        -- Get best sublevel
        local currSub, minDiff = mdt:GetCurrentSubLevel()
        Addon.IteratePull(pull, function (clone)
            local diff = clone.sublevel - currSub
            if not minDiff or abs(diff) < abs(minDiff) or abs(diff) == abs(minDiff) and diff < minDiff then
                minDiff = diff
            end
            return minDiff == 0
        end)

        if not minDiff then return end
        local bestSub = currSub + minDiff

        -- Get rect to zoom to
        local minX, minY, maxX, maxY
        Addon.IteratePull(pull, function (clone)
            local sub, x, y = clone.sublevel, clone.x, clone.y
            if sub == bestSub then
                minX, minY = min(minX or x, x), min(minY or y, y)
                maxX, maxY = max(maxX or x, x), max(maxY or y, y)
            end
        end)

        -- Change sublevel (if required) and zoom to rect
        if bestSub and minX and maxY and maxX and minY then
            if bestSub ~= currSub then
                mdt:SetCurrentSubLevel(bestSub)
                mdt:UpdateMap(true)
            end
            Addon.ZoomTo(minX, maxY, maxX, minY)
        end

        -- Scroll pull list
        Addon.ScrollToPull(n)
    end
end

function Addon.ScrollToPull(n, center)
    local mdt, main = Addon.GetMDT()
    local scroll = main.sidePanel.pullButtonsScrollFrame
    local pull = main.sidePanel.newPullButtons[n]

    local height = scroll.scrollframe:GetHeight()
    local offset = (scroll.status or scroll.localstatus).offset
    local top = - select(5, pull.frame:GetPoint(1))
    local bottom = top + pull.frame:GetHeight()

    local diff, scrollTo = scroll.content:GetHeight() - height

    if center then
        scrollTo = max(0, min(top + (bottom - top) / 2 - height / 2, diff))
    elseif top < offset then
        scrollTo = top
    elseif bottom > offset + height then
        scrollTo = bottom - height
    end

    if scrollTo then
        scroll:SetScroll(scrollTo / diff * 1000)
        scroll:FixScroll()
    end
end

-- ---------------------------------------
--             Enemy forces
-- ---------------------------------------

function Addon.GetEnemyForces()
    local n = select(3, C_Scenario.GetStepInfo())
    if not n or n == 0 then return end

    local total, _, _, curr = select(5, C_Scenario.GetCriteriaInfo(n))
    return tonumber((curr:gsub("%%", ""))), total
end

function Addon.IsEncounterDefeated(encounterID)
    -- The asset ID seems to be the only thing connecting scenario steps
    -- and journal encounters, other than trying to match the name :/
    local assetID = select(7, EJ_GetEncounterInfo(encounterID))
    local n = select(3, C_Scenario.GetStepInfo())
    if not assetID or not n or n == 0 then return end

    for i=1,n-1 do
        local isDead, _, _, _, stepAssetID = select(3, C_Scenario.GetCriteriaInfo(i))
        if stepAssetID == assetID then
            return isDead
        end
    end
end

function Addon.GetCurrentPullByEnemyForces()
    local ef = Addon.GetEnemyForces()
    if not ef then return end

    return Addon.IteratePulls(function (_, enemy, _, _, pull, i)
        ef = ef - enemy.count
        if ef < 0 or enemy.isBoss and not Addon.IsEncounterDefeated(enemy.encounterID) then
            return i, pull
        end
    end)
end

-- ---------------------------------------
--                 Route
-- ---------------------------------------

local function Node(enemyId, cloneId)
    return "e" .. enemyId .. "c" .. cloneId
end

local function Distance(ax, ay, bx, by, from, to)
    from, to = from or 1, to or 1
    if from == to then
        return math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2))
    else
        local POIs = Addon.GetMDT().mapPOIs[Addon.GetCurrentDungeonId()]
        local p = Addon.FindWhere(POIs[from], "type", "mapLink", "target", to)
        local t = p and Addon.FindWhere(POIs[to], "type", "mapLink", "connectionIndex", p.connectionIndex)
        return t and Distance(ax, ay, p.x, p.y) + Distance(t.x, t.y, bx, by) or math.huge
    end
end

local function Path(path, node)
    return path .. "-" .. node .. "-"
end

local function Sub(path, n)
    for _=1,n or 1 do
       path = path:gsub("%-[^-]+-$", "")
    end
    return path
end

local function Contains(path, node)
    return path:find("%-" .. node .. "%-") ~= nil
end

local function Last(path, enemies)
    local enemyId, cloneId = path:match("-e(%d+)c(%d+)-$")
    if enemyId and cloneId then
        if enemies then
            return enemies[tonumber(enemyId)].clones[tonumber(cloneId)]
        else
            return Node(enemyId, cloneId)
        end
    end
end

local function Length(path)
    return path:gsub("e%d+c%d+", ""):len() / 2
end

local function Weight(path, weight, length, prev, curr, prevNode, currNode)
    if weight then
        local prevPull, currPull = prevNode and pulls[prevNode], currNode and pulls[currNode]
        local dist =
            -- Base distance
            Distance(prev.x, prev.y, curr.x, curr.y, prev.sublevel, curr.sublevel)
            -- Weighted by group
            * (prev.g and curr.g and prev.g == curr.g and Addon.BFS_WEIGHT_GROUP or 1)
            -- Weighted by direction
            * (currPull and (prevPull and (prevPull == currPull and Addon.BFS_WEIGHT_PULL or prevPull < currPull and Addon.BFS_WEIGHT_FORWARD) or Addon.BFS_WEIGHT_ROUTE) or 1)

            weights[path] = (weight * length * Addon.BFS_WEIGHT_LENGTH + dist) / (length + 1)
    end
    return weights[path]
end

local function Insert(path, length, weight)
    length, weight = length or Length(path), weight or Weight(path)
    local lft, rgt = 1, #queue+1

    while rgt > lft do
        local m = math.floor(lft + (rgt - lft) / 2)
        local p = queue[m]
        local w, l = Weight(p), Length(p)

        if l ~= length and (length <= Addon.BFS_BRANCH or l <= Addon.BFS_BRANCH) then
            if length < l then
                rgt = m
            else
                lft = m+1
            end
        elseif weight < w then
            rgt = m
        else
            lft = m+1
        end
    end

    if lft <= Addon.BFS_QUEUE_INSERT then
        table.insert(queue, lft, path)
        if queue[Addon.BFS_QUEUE_MAX+1] then
            table.remove(queue)
        end
    end
end

function Addon.CalculateRoute()
    local mdt = Addon.GetMDT()
    local dungeon = Addon.GetCurrentDungeonId()
    local enemies = Addon.GetCurrentEnemies()
    local t, i, n, g = GetTime(), 1, 1, {}

    -- Start route
    local start = Sub(MDTGuideRoute, Addon.BFS_TRACK_BACK)
    queue[1] = start
    weights[start] = 0

    -- Start POI
    if start == "" then
        for _,poi in ipairs(mdt.mapPOIs[dungeon][1]) do
            if poi.type == "graveyard" then
                start = poi
                break
            end
        end
    end

    while true do
        local total = GetTime() - t

        -- Limit runtime
        if total >= Addon.BFS_MAX_TOTAL then
            print("|cff00bbbb[MDTGuide]|r Route calculation took too long, switching to enemy forces mode!")
            bfs, rerun = false, false
            break
        elseif i > Addon.BFS_MAX_FRAME * (1 - total * Addon.BFS_MAX_FRAME_SCALE / Addon.BFS_MAX_TOTAL) then
            i = 1
            coroutine.yield()
        end

        local path = table.remove(queue, 1)
        if not path then
            debug("No path found!")
            break
        end

        local weight, length, last, lastNode = Weight(path), Length(path), Last(path, enemies) or start, Last(path)
        local enemyId = Addon.kills[length+1]

        -- Success
        if length == #Addon.kills then
            debug(n)
            MDTGuideRoute = path
            break
        end

        -- Next step
        local found
        for cloneId,clone in ipairs(enemies[enemyId].clones) do
            local node = Node(enemyId, cloneId)
            if not Contains(path, node) then
                local p = Path(path, node)
                local w = Weight(p, weight, length, last, clone, lastNode, node)
                if w < math.huge then
                    found = true
                    if not clone.g then
                        Insert(p, length+1, w)
                    elseif not g[clone.g] or w < Weight(g[clone.g]) then
                        g[clone.g] = p
                    end
                end
            end
        end

        -- Insert grouped and proceed or retry with next enemy
        if found then
            for _,p in pairs(g) do Insert(p, length+1) end
            weights[path] = nil
        else
            table.remove(Addon.kills, length+1)
            table.insert(queue, 1, path)
        end

        i, n = i+1, n+1
        wipe(g)
    end

    debug("N", n)
    debug("Time", GetTime() - t)
    debug("Queue", #queue)

    wipe(queue)
    wipe(weights)

    Addon.ColorEnemies()

    if zoom then
        zoom = rerun
        Addon.ZoomToCurrentPull()
    end
    if rerun then
        Addon.UpdateRoute()
    end
end

function Addon.UpdateRoute(z)
    zoom = zoom or z
    rerun = false
    if Addon.IsCurrentInstance() then
        if co and coroutine.status(co) == "running" then
            rerun = true
        else
            co = coroutine.create(Addon.CalculateRoute)
            coroutine.resume(co)
        end
    end
end

function Addon.AddKill(npcId)
    for i,enemy in ipairs(Addon.GetMDT().dungeonEnemies[currentDungeon]) do
        if enemy.id == npcId then
            debug("ADD")
            table.insert(Addon.kills, i)
            return i
        end
    end
end

function Addon.ClearKills()
    wipe(Addon.hits)
    wipe(Addon.kills)
    MDTGuideRoute = ""
    bfs = true
end

function Addon.GetCurrentPullByRoute()
    local path = MDTGuideRoute
    while path and path:len() > 0 do
        local node = Last(path)
        local n = pulls[node]
        if n then
            return Addon.IteratePull(n, function (_, _, cloneId, enemyId, pull)
                if not Contains(path, Node(enemyId, cloneId)) then
                    return n, pull
                end
            end) or n + 1
        end
        path = path:sub(1, -node:len() - 3)
    end
end

-- ---------------------------------------
--               Progress
-- ---------------------------------------

function Addon.GetCurrentPull()
    if Addon.IsCurrentInstance() then
        if Addon.IsBFS() then
            return Addon.GetCurrentPullByRoute()
        else
            return Addon.GetCurrentPullByEnemyForces()
        end
    end
end

function Addon.ZoomToCurrentPull(refresh)
    local mdt = Addon.GetMDT()
    if Addon.IsBFS() and refresh then
        Addon.UpdateRoute(true)
    elseif Addon.IsActive() then
        local n = Addon.GetCurrentPull()
        if n then
            mdt:SetSelectionToPull(n)
            Addon.ScrollToPull(n, true)
        end
    end
end

function Addon.ColorEnemy(enemyId, cloneId, color)
    local r, g, b = unpack(color)
    local blip = Addon.GetMDT():GetBlip(enemyId, cloneId)
    if blip then
        blip.texture_SelectedHighlight:SetVertexColor(r, g, b, 0.7)
        blip.texture_Portrait:SetVertexColor(r, g, b, 1)
    end
end

function Addon.ColorEnemies()
    if Addon.IsActive() and Addon.IsCurrentInstance() then
        if Addon.IsBFS() then
            local n = Addon.GetCurrentPullByRoute()
            if n and n > 0 then
                Addon.IteratePull(n, function (_, _, cloneId, enemyId)
                    Addon.ColorEnemy(enemyId, cloneId, COLOR_CURR)
                end)
            end
            for enemyId, cloneId in MDTGuideRoute:gmatch("-e(%d+)c(%d+)-") do
                Addon.ColorEnemy(tonumber(enemyId), tonumber(cloneId), COLOR_DEAD)
            end
        else
            local n = Addon.GetCurrentPullByEnemyForces()
            if n and n > 0 then
                Addon.IteratePulls(function (_, _, cloneId, enemyId, _, i)
                    if i > n then
                        return true
                    else
                        Addon.ColorEnemy(enemyId, cloneId, i == n and COLOR_CURR or COLOR_DEAD)
                    end
                end)
            end
        end
    end
end

-- ---------------------------------------
--                 Util
-- ---------------------------------------

function Addon.GetMDT()
    local mdt = MethodDungeonTools
    return mdt, mdt and mdt.main_frame
end

function Addon.IsActive()
    local _, main = Addon.GetMDT()
    return MDTGuideActive and main and main:IsShown()
end

function Addon.IsBFS()
    return Addon.BFS and bfs
end

function Addon.GetCurrentDungeonId()
    return Addon.GetMDT():GetDB().currentDungeonIdx
end

function Addon.IsCurrentInstance()
    return currentDungeon == Addon.GetCurrentDungeonId()
end

function Addon.GetCurrentEnemies()
    local mdt = Addon.GetMDT()
    return mdt.dungeonEnemies[Addon.GetCurrentDungeonId()]
end

function Addon.GetCurrentPulls()
    return Addon.GetMDT():GetCurrentPreset().value.pulls
end

function Addon.IteratePull(pull, fn, ...)
    local mdt = Addon.GetMDT()
    local enemies = Addon.GetCurrentEnemies()

    if type(pull) == "number" then
        pull = Addon.GetCurrentPulls()[pull]
    end

    for enemyId,clones in pairs(pull) do
        local enemy = enemies[enemyId]
        if enemy then
            for _,cloneId in pairs(clones) do
                if mdt:IsCloneIncluded(enemyId, cloneId) then
                    local a, b = fn(enemy.clones[cloneId], enemy, cloneId, enemyId, pull, ...)
                    if a then return a, b end
                end
            end
        end
    end
end

function Addon.IteratePulls(fn, ...)
    for i,pull in ipairs(Addon.GetCurrentPulls()) do
        local a, b = Addon.IteratePull(pull, fn, i, ...)
        if a then return a, b end
    end
end

function Addon.GetFramesToHide()
    local _, main = Addon.GetMDT()

    frames = frames or {
        main.bottomPanel,
        main.sidePanel.WidgetGroup,
        main.sidePanel.ProgressBar,
        main.toolbar.toggleButton,
        main.maximizeButton,
        main.HelpButton,
        main.DungeonSelectionGroup
    }
    return frames
end

function Addon.IsNPC(guid)
    return guid and guid:sub(1, 8) == "Creature"
end

function Addon.GetNPCId(guid)
    return tonumber(select(6, ("-"):split(guid)), 10)
end

function Addon.GetInstanceDungeonId(instance)
    if instance then
        for id,enemies in pairs(Addon.GetMDT().dungeonEnemies) do
            for _,enemy in pairs(enemies) do
                if enemy.instanceID == instance then
                    return id
                end
            end
        end
    end
end

function Addon.FindWhere(tbl, key1, val1, key2, val2)
    for i,v in pairs(tbl) do
        if v[key1] == val1 and (not key2 or v[key2] == val2) then
            return v, i
        end
    end
end

-- ---------------------------------------
--             Events, Hooks
-- ---------------------------------------

function Addon.SetDungeon()
    wipe(pulls)
    Addon.IteratePulls(function (_, _, cloneId, enemyId, _, pullId)
        pulls[Node(enemyId, cloneId)] = pullId
    end)
    Addon.UpdateRoute()
end

function Addon.SetInstanceDungeon(dungeon)
    currentDungeon = dungeon
    Addon.ClearKills()
    Addon.UpdateRoute()
end

local Frame = CreateFrame("Frame")

-- Event listeners
local OnEvent = function (_, ev, ...)
    if ev == "ADDON_LOADED" then
        if ... == Name then
            Frame:UnregisterEvent("ADDON_LOADED")

            local mdt = MethodDungeonTools

            -- Insert toggle button
            hooksecurefunc(mdt, "ShowInterface", function ()
                if not toggleButton then
                    local main = mdt.main_frame

                    toggleButton = CreateFrame("Button", nil, mdt.main_frame, "MaximizeMinimizeButtonFrameTemplate")
                    toggleButton[MDTGuideActive and "Minimize" or "Maximize"](toggleButton)
                    toggleButton:SetOnMaximizedCallback(function () Addon.DisableGuideMode() end)
                    toggleButton:SetOnMinimizedCallback(function () Addon.EnableGuideMode() end)
                    toggleButton:Show()

                    main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT", 10, 0)
                    toggleButton:SetPoint("RIGHT", main.maximizeButton, "LEFT", 10, 0)
                end

                if MDTGuideActive then
                    MDTGuideActive = false
                    Addon.EnableGuideMode(true)
                end
            end)

            -- Hook maximize/minimize
            hooksecurefunc(mdt, "Maximize", function ()
                local main = mdt.main_frame

                Addon.DisableGuideMode()
                if toggleButton then
                    toggleButton:Hide()
                    main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT")
                end
            end)
            hooksecurefunc(mdt, "Minimize", function ()
                local main = mdt.main_frame

                Addon.DisableGuideMode()
                if toggleButton then
                    toggleButton:Show()
                    main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT", 10, 0)
                end
            end)

            -- Hook dungeon selection
            hooksecurefunc(mdt, "UpdateToDungeon", function ()
                Addon.SetDungeon()
            end)

            -- Hook pull selection
            hooksecurefunc(mdt, "SetSelectionToPull", function (_, pull)
                if Addon.IsActive() and tonumber(pull) then
                    Addon.ZoomToPull(pull)
                end
            end)

            -- Hook pull tooltip
            hooksecurefunc(mdt, "ActivatePullTooltip", function ()
                if Addon.IsActive() then
                    local tooltip = mdt.pullTooltip
                    local y2, _, frame, pos, _, y1 = select(5, tooltip:GetPoint(2)), tooltip:GetPoint(1)
                    local w = frame:GetWidth() + tooltip:GetWidth()

                    tooltip:SetPoint("TOPRIGHT", frame, pos, w, y1)
                    tooltip:SetPoint("BOTTOMRIGHT", frame, pos, 250 + w, y2)
                end
            end)

            -- Hook enemy blips
            hooksecurefunc(mdt, "DungeonEnemies_UpdateSelected", Addon.ColorEnemies)

            -- Hook enemy info frame
            hooksecurefunc(mdt, "ShowEnemyInfoFrame", Addon.AdjustEnemyInfo)
        end
    elseif ev == "PLAYER_ENTERING_WORLD" then
        local _, instanceType = IsInInstance()
        if instanceType == "party" then
            local map = C_Map.GetBestMapForUnit("player")
            if map then
                local dungeon = Addon.GetInstanceDungeonId(EJ_GetInstanceForMap(map))

                if dungeon ~= currentDungeon then
                    Addon.SetInstanceDungeon(dungeon)

                    if dungeon then
                        debug("REGISTER")
                        Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                    else
                        debug("UNREGISTER")
                        Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                    end
                end
            else
                retry = {ev, ...}
            end
        else
            if instanceType then
                Addon.SetInstanceDungeon()
            end
            Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    elseif ev == "SCENARIO_COMPLETED" or ev == "CHAT_MSG_SYSTEM" and (...):match(PATTERN_INSTANCE_RESET) then
        debug("RESET")
        Addon.SetInstanceDungeon()
        Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    elseif ev == "SCENARIO_CRITERIA_UPDATE" and not Addon.IsBFS() then
        Addon.ZoomToCurrentPull(true)
    elseif ev == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, event, _, _, _, sourceFlags, _, destGUID, _, destFlags = CombatLogGetCurrentEventInfo()

        if event == "UNIT_DIED" then
            if Addon.hits[destGUID] then
                debug("KILL")
                Addon.hits[destGUID] = nil
                local npcId = Addon.GetNPCId(destGUID)
                if Addon.AddKill(npcId) and Addon.IsBFS() then
                    Addon.ZoomToCurrentPull(true)
                end
            end
        elseif event:match("DAMAGE") or event:match("AURA_APPLIED") then
            local sourceIsParty = bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) == 0
            local destIsEnemy = bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) == 0
            if sourceIsParty and destIsEnemy and not Addon.hits[destGUID] then
                debug("HIT")
                Addon.hits[destGUID] = true
            end
        end
    end
end

-- Resume route calculation
local OnUpdate = function ()
    if co and coroutine.status(co) == "suspended" then
        coroutine.resume(co)
    end

    if retry then
        local args = retry
        retry = nil
        OnEvent(nil, unpack(args))
    end
end

Frame:SetScript("OnEvent", OnEvent)
Frame:SetScript("OnUpdate", OnUpdate)
Frame:RegisterEvent("ADDON_LOADED")
Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
Frame:RegisterEvent("SCENARIO_COMPLETED")
Frame:RegisterEvent("CHAT_MSG_SYSTEM")

-- ---------------------------------------
--                  CLI
-- ---------------------------------------

SLASH_MDTG1 = "/mdtg"
SLASH_MDTG2 = "/methoddungeontoolsguide"
SLASH_MDTG2 = "/mplusguide"

function SlashCmdList.MDTG(args)
    local cmd, arg1, arg2 = strsplit(' ', args)

    if cmd == "route" then
        arg1 = arg1 or not Addon.BFS and "enable"
        Addon.BFS = arg1 == "enable"
        print("|cff00bbbb[MDTGuide]|r Route predition " .. (Addon.BFS and "enabled" or "disabled"))
    else
        print("|cff00bbbb[MDTGuide]|r Usage:")
        print("|cffbbbbbb/mdtg route [enable/disable]|r: Enable/Disable/Toggle route estimation.")
        print("|cffbbbbbb/mdtg|r: Print this help message.")
    end
end
