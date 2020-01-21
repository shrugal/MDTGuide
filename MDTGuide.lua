local Name, Addon = ...

-- TODO:DEBUG
MDTG = Addon

local HEIGHT = 200
local SIDE_WIDTH = 200
local ZOOM = 1.8

MDTGuideActive = false

local toggleButton, frames

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
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", SIDE_WIDTH, 0)
    f:SetHeight(25)

    -- Adjust side panel
    f = main.sidePanel
    f:SetWidth(SIDE_WIDTH)
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, 25)
    f:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT")
    main.closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 7, 4)
    toggleButton:SetPoint("RIGHT", main.closeButton, "LEFT")

    -- Adjust enemy info
    f = main.sidePanel.PullButtonScrollGroup
    f.frame:ClearAllPoints()
    f.frame:SetPoint("TOPLEFT", main.scrollFrame, "TOPRIGHT")
    f.frame:SetPoint("BOTTOMLEFT", main.scrollFrame, "BOTTOMRIGHT")
    f.frame:SetWidth(SIDE_WIDTH)

    -- Hide some special frames
    if main.toolbar:IsShown() then
        main.toolbar.toggleButton:GetScript("OnClick")()
    end

    mdt:ToggleFreeholdSelector()
    mdt:ToggleBoralusSelector()

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

     return true
end

function Addon.ToggleGuideMode()
    if MDTGuideActive then
        Addon.DisableGuideMode()
    else
        Addon.EnableGuideMode()
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

    local pull = mdt:GetCurrentPreset().value.pulls[n]

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
--             Path estimation
-- ---------------------------------------

function Addon.GetCurrentPull()
    return Addon.GetCurrentPullByEnemyForces()
end

-- By enemy forces
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

-- By kills
local BRANCH_FACTOR = 0
local kills, queue, weights = {}, {}, {}

local function Node(enemyId, cloneId)
    return "e" .. enemyId .. "c" .. cloneId
end

local function Distance(a, b)
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2))
end

local function Path(path, node)
    return path .. "-" .. node .. "-"
end

local function Contains(path, node)
    return path:find("%-" .. node .. "%-") ~= nil
end

local function Last(enemies, path)
    local enemyId, cloneId = path:match("-e(%d+)c(%d+)-$")
    return enemyId and cloneId and enemies[enemyId].clones[cloneId]
end

local function Length(path)
    return path:gsub("e%d+c%d+", ""):len() / 2
end

local function Weight(path, weight, length, dist)
    if weight and length and dist then
        weights[path] = (weight * length + dist * (1 + BRANCH_FACTOR * length)) / (length + 1)
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

    table.insert(queue, l, path)
end

function Addon.GetCurrentPullByKills()
    local mdt = Addon.GetMDT()
    local dungeon = mdt:GetCurrentPreset().value.currentDungeonIdx
    local enemies = mdt.dungeonEnemies[dungeon]
    local n, t = 0, GetTime()

    local start
    for _,poi in ipairs(mdt.mapPOIs[dungeon][1]) do
        if poi.type == "graveyard" then
            start = poi break
        end
    end

    queue[1] = ""
    weights[""] = 0

    while true do
        local path = table.remove(queue, 1)

        -- Failure
        if not path then
            print("No valid path")
            break
        elseif GetTime() - t > 5 then
            print("Too long!", n)
            break
        end

        local weight, length, last = Weight(path), Length(path), Last(enemies, path) or start
        local enemyId = kills[length+1]

        -- Success
        if length == #kills then
            print(path, GetTime() - t, n)
            break
        end

        -- Next step
        for cloneId,clone in ipairs(enemies[enemyId].clones) do
            local node = Node(enemyId, cloneId)
            if not Contains(path, node) then
                local p = Path(path, node)
                Insert(p, Weight(p, weight, length, Distance(last, clone)))
            end
        end

        n = n + 1
    end

    wipe(queue)
    wipe(weights)
end

-- ---------------------------------------
--                 Util
-- ---------------------------------------

function Addon.GetMDT()
    local mdt = MethodDungeonTools
    return mdt, mdt and mdt.main_frame
end

function Addon.IteratePull(pull, fn, ...)
    local mdt = Addon.GetMDT()
    local db = mdt:GetDB()
    local enemies = mdt.dungeonEnemies[db.currentDungeonIdx]

    for enemyID,clones in pairs(pull) do
        local enemy = enemies[enemyID]
        if enemy then
            for _,cloneID in pairs(clones) do
                if mdt:IsCloneIncluded(enemyID, cloneID) then
                    local a, b = fn(enemy.clones[cloneID], enemy, cloneID, enemyID, ...)
                    if a then return a, b end
                end
            end
        end
    end
end

function Addon.IteratePulls(fn, ...)
    local mdt = Addon.GetMDT()
    local pulls = mdt:GetCurrentPreset().value.pulls

    for i,pull in ipairs(pulls) do
        local a, b = Addon.IteratePull(pull, fn, pull, i)
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

function Addon.ColorEnemies()
    local mdt = Addon.GetMDT()
    local n = Addon.GetCurrentPull()
    if not n or n == 0 then return end

    Addon.IteratePulls(function (_, _, cloneID, enemyID, _, i)
        local r, g, b
        if i > n then
            return true
        elseif i == n then
            r, g, b = 0.13, 1, 1
        else
            r, g, b = 0.55, 0.13, 0.13
        end

        local blip = mdt:GetBlip(enemyID, cloneID)
        if blip then
            blip.texture_SelectedHighlight:SetVertexColor(r, g, b, 0.7)
            blip.texture_Portrait:SetVertexColor(r, g, b, 1)
        end
    end)
end

-- ---------------------------------------
--             Events, Hooks
-- ---------------------------------------

local Events = CreateFrame("Frame")
Events:SetScript("OnEvent", function (_, ev, ...)
    if ev == "ADDON_LOADED" then
        if ... == Name then
            Events:UnregisterEvent("ADDON_LOADED")

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
            hooksecurefunc(mdt, "DungeonEnemies_UpdateSelected", function ()
                if MDTGuideActive then Addon.ColorEnemies() end
            end)
        end
    elseif ev == "SCENARIO_CRITERIA_UPDATE" then
        local mdt, main = Addon.GetMDT()
        if MDTGuideActive and main and main:IsShown() then
            local n = Addon.GetCurrentPull()
            if n then
                mdt:SetSelectionToPull(n)
            end
        end
    end
end)
Events:RegisterEvent("ADDON_LOADED")
Events:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
