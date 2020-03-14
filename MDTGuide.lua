local Name, Addon = ...

MDTG = Addon
MDTGuideActive = false

local HEIGHT = 200
local WIDTH_SIDE = 200
local ZOOM = 1.8

local COLOR_CURR = {0.13, 1, 1}
local COLOR_DEAD = {0.55, 0.13, 0.13}

local BFS = true
local BFS_WEIGHT_BRANCH = 0
local BFS_WEIGHT_GROUP = 0.1
local BFS_WEIGHT_ROUTE = 0.5
local BFS_MAX_FRAME = 20
local BFS_MAX_TOTAL = 5
local BFS_MAX_QUEUE = 1000

local toggleButton, frames
local currentDungeon
local hits, kills, queue, weights, pulls = {}, {}, {}, {}, {}
local route = ""
local co, rerun, zoom

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

    if mdt.EnemyInfoFrame and mdt.EnemyInfoFrame:IsShown() then
        Addon.AdjustEnemyInfo(mdt)
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

    if mdt.EnemyInfoFrame and mdt.EnemyInfoFrame:IsShown() then
        Addon.AdjustEnemyInfo(mdt)
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
    local pull = Addon.GetCurrentPulls()[n or mdt:GetCurrentPull()]

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

local function Distance(a, b)
    -- TODO: Different map levels
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2))
end

local function Path(path, node)
    return path .. "-" .. node .. "-"
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

local function Weight(path, weight, length, prev, curr, node)
    if weight then
        local dist = Distance(prev, curr)
            * (prev.g and curr.g and prev.g == curr.g and BFS_WEIGHT_GROUP or 1)
            * (pulls[node] and BFS_WEIGHT_ROUTE or 1)
            * (1 + BFS_WEIGHT_BRANCH * length)
        weights[path] = (weight * length + dist) / (length + 1)
    end
    return weights[path]
end

local function Insert(path, weight)
    local l, r = 1, #queue+1

    while r > l do
        local m = math.floor(l + (r - l) / 2)
        local w = Weight(queue[m])
        if weight < w then
            r = m
        else
            l = m+1
        end
    end

    if l <= BFS_MAX_QUEUE then
        table.insert(queue, l, path)
    end
end

function Addon.CalculateRoute()
    local mdt = Addon.GetMDT()
    local dungeon = Addon.GetCurrentDungeonId()
    local enemies = Addon.GetCurrentEnemies()
    local t, n = GetTime(), 1

    local start
    for _,poi in ipairs(mdt.mapPOIs[dungeon][1]) do
        if poi.type == "graveyard" then
            start = poi
            break
        end
    end

    queue[1] = ""
    weights[""] = 0

    while true do
        local path = table.remove(queue, 1)

        -- Failure
        if not path then
            print("No valid path", GetTime() - t, n)
            break
        end

        local weight, length, last = Weight(path), Length(path), Last(path, enemies) or start
        local enemyId = kills[length+1]

        -- Success
        if length == #kills then
            print("Success", path, GetTime() - t, n)
            route = path

            Addon.ColorEnemies()
            if zoom then
                zoom = rerun
                Addon.ZoomToCurrentPull()
            end

            break
        end

        -- Next step
        local node, p
        for cloneId,clone in ipairs(enemies[enemyId].clones) do
            node = Node(enemyId, cloneId)
            if not Contains(path, node) then
                p = Path(path, node)
                Insert(p, Weight(p, weight, length, last, clone, node))
            end
        end

        if not p then
            wipe(queue)
        end

        -- Limit runtime
        if GetTime() - t >= BFS_MAX_TOTAL then
            print("Too long!", GetTime() - t, n)
            -- TODO: Switch to EF temporarily
            break
        elseif n % BFS_MAX_FRAME == 0 then
            coroutine.yield()
        end

        n = n + 1
    end

    wipe(queue)
    wipe(weights)

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
    for i,enemy in pairs(Addon.GetMDT().dungeonEnemies[currentDungeon]) do
        if enemy.id == npcId then
            table.insert(kills, i)
            return i
        end
    end
end

function Addon.ClearKills()
    wipe(hits)
    wipe(kills)
    route = ""
end

function Addon.GetCurrentPullByRoute()
    local path = route
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
        if BFS then
            return Addon.GetCurrentPullByRoute()
        else
            return Addon.GetCurrentPullByEnemyForces()
        end
    end
end

function Addon.ZoomToCurrentPull(refresh)
    local mdt = Addon.GetMDT()
    if BFS and refresh then
        Addon.UpdateRoute(true)
    else
        local n = Addon.GetCurrentPull()
        if n then
            mdt:SetSelectionToPull(n)
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
    if MDTGuideActive and Addon.IsCurrentInstance() then
        if BFS then
            local n = Addon.GetCurrentPullByRoute()
            if n and n > 0 then
                Addon.IteratePull(n, function (_, _, cloneId, enemyId)
                    Addon.ColorEnemy(enemyId, cloneId, COLOR_CURR)
                end)
            end
            for enemyId, cloneId in route:gmatch("-e(%d+)c(%d+)-") do
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

    wipe(hits)
    wipe(kills)
    route = ""

    Addon.UpdateRoute()
end

local Frame = CreateFrame("Frame")

-- Resume route calculation
Frame:SetScript("OnUpdate", function ()
    if co and coroutine.status(co) == "suspended" then
        coroutine.resume(co)
    end
end)

-- Event listeners
Frame:SetScript("OnEvent", function (_, ev, ...)
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
                if MDTGuideActive and tonumber(pull) then
                    Addon.ZoomToPull(pull)
                end
            end)

            -- Hook pull tooltip
            hooksecurefunc(mdt, "ActivatePullTooltip", function ()
                if not MDTGuideActive then return end

                local tooltip = mdt.pullTooltip
                local y2, _, frame, pos, _, y1 = select(5, tooltip:GetPoint(2)), tooltip:GetPoint(1)
                local w = frame:GetWidth() + tooltip:GetWidth()

                tooltip:SetPoint("TOPRIGHT", frame, pos, w, y1)
                tooltip:SetPoint("BOTTOMRIGHT", frame, pos, 250 + w, y2)
            end)

            -- Hook enemy blips
            hooksecurefunc(mdt, "DungeonEnemies_UpdateSelected", Addon.ColorEnemies)

            -- Hook enemy info frame
            hooksecurefunc(mdt, "ShowEnemyInfoFrame", Addon.AdjustEnemyInfo)
        end
    elseif ev == "PLAYER_ENTERING_WORLD" then
        local _, instanceType = IsInInstance()
        if instanceType == "party" then
            local instance = EJ_GetInstanceForMap(C_Map.GetBestMapForUnit("player"))
            local dungeon = Addon.GetInstanceDungeonId(instance)

            if dungeon ~= currentDungeon then
                Addon.SetInstanceDungeon(dungeon)

                if dungeon then
                    Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                else
                    Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                end
            end
        else
            if instanceType then
                Addon.SetInstanceDungeon()
            end
            Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    elseif ev == "SCENARIO_CRITERIA_UPDATE" then
        local _, main = Addon.GetMDT()
        if MDTGuideActive and main and main:IsShown() then
            Addon.ZoomToCurrentPull(true)
        end
    elseif ev == "SCENARIO_COMPLETED" then
        Addon.SetInstanceDungeon()
        Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    elseif ev == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, event, _, _, _, sourceFlags, _, destGUID, _, destFlags = CombatLogGetCurrentEventInfo()

        if event == "UNIT_DIED" then
            if hits[destGUID] then
                hits[destGUID] = nil
                local npcId = Addon.GetNPCId(destGUID)
                for i,enemy in pairs(Addon.GetMDT().dungeonEnemies[currentDungeon]) do
                    if enemy.id == npcId then
                        table.insert(kills, i)
                        Addon.ZoomToCurrentPull(true)
                        break
                    end
                end
            end
        elseif event:match("DAMAGE") or event:match("AURA_APPLIED") then
            local sourceIsParty = bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY)
            local destIsEnemy = bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) and not bit.band(destFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY)
            if sourceIsParty and destIsEnemy and not hits[destGUID] then
                hits[destGUID] = true
            end
        end
    end
end)
Frame:RegisterEvent("ADDON_LOADED")
Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
Frame:RegisterEvent("SCENARIO_COMPLETED")
