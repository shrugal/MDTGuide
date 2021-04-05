local Name, Addon = ...

MDTG = Addon
MDTGuideActive = false
MDTGuideRoute = ""
MDTGuideOptions = {
    height = 200,
    widthSide = 200,
    zoomMin = 1,
    zoomMax = 1,
    fade = false,
    route = false
}

Addon.WIDTH = 840
Addon.HEIGHT = 555
Addon.RATIO = Addon.WIDTH / Addon.HEIGHT
Addon.MIN_HEIGHT = 150
Addon.MIN_Y, Addon.MAX_Y = 200, 270
Addon.MIN_X, Addon.MAX_X = Addon.MIN_Y * Addon.RATIO, Addon.MAX_Y * Addon.RATIO
Addon.ZOOM = 1.8
Addon.ZOOM_BORDER = 15
Addon.COLOR_CURR = {0.13, 1, 1}
Addon.COLOR_DEAD = {0.55, 0.13, 0.13}
Addon.DEBUG = false
Addon.PATTERN_INSTANCE_RESET = "^" .. INSTANCE_RESET_SUCCESS:gsub("%%s", ".+") .. "$"

Addon.currentDungeon = nil

local toggleBtn, currentPullBtn, announceBtn
local hideFrames, hoverFrames
local zoomAnimGrp
local fadeTicker, isFaded

-- ---------------------------------------
--              Toggle mode
-- ---------------------------------------

function Addon.EnableGuideMode(noZoom)
    if MDTGuideActive then return end
    MDTGuideActive = true

    local main = MDT.main_frame

    -- Hide frames
    for _,f in pairs(Addon.GetHideFrames()) do
       (f.frame or f):Hide()
    end

    -- Resize
    main:SetMinResize(Addon.MIN_HEIGHT * Addon.RATIO, Addon.MIN_HEIGHT)
    MDT:StartScaling()
    MDT:SetScale(MDTGuideOptions.height / Addon.HEIGHT)
    MDT:UpdateMap(true)
    MDT:DrawAllHulls()

    -- Zoom
    if not noZoom and main.mapPanelFrame:GetScale() > 1 then
        Addon.ZoomBy(Addon.ZOOM)
    end

    -- Adjust top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", MDTGuideOptions.widthSide, 0)
    f:SetHeight(25)
    f = main.topPanelLogo
    f:SetWidth(16)
    f:SetHeight(16)


    -- Adjust bottom panel
    main.bottomPanel:SetHeight(20)

    -- Adjust side panel
    f = main.sidePanel
    f:SetWidth(MDTGuideOptions.widthSide)
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, 25)
    f:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", 0, -20)
    main.closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 7, 4)
    toggleBtn:SetPoint("RIGHT", main.closeButton, "LEFT")
    currentPullBtn:Show()
    announceBtn:Show()

    -- Adjust enemy info
    f = main.sidePanel.PullButtonScrollGroup
    f.frame:ClearAllPoints()
    f.frame:SetPoint("TOPLEFT", main.scrollFrame, "TOPRIGHT")
    f.frame:SetPoint("BOTTOMLEFT", main.scrollFrame, "BOTTOMRIGHT")
    f.frame:SetWidth(MDTGuideOptions.widthSide)

    -- Hide some special frames
    if main.toolbar:IsShown() then
        main.toolbar.toggleButton:GetScript("OnClick")()
    end

    MDT:ToggleFreeholdSelector()
    MDT:ToggleBoralusSelector()

    -- Adjust enemy info frame
    if MDT.EnemyInfoFrame and MDT.EnemyInfoFrame:IsShown() then
        Addon.AdjustEnemyInfo()
    end

    -- Prevent closing with esc
    for i,v in pairs(UISpecialFrames) do
        if v == "MDTFrame" then tremove(UISpecialFrames, i) break end
    end

    -- Set fade
    Addon.SetFade()

    return true
end

function Addon.DisableGuideMode()
    if not MDTGuideActive then return end
    MDTGuideActive = false

    local main = MDT.main_frame

    for _,f in pairs(Addon.GetHideFrames()) do
        (f.frame or f):Show()
    end

    -- Reset top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT")
    f:SetHeight(30)
    f = main.topPanelLogo
    f:SetWidth(24)
    f:SetHeight(24)

    -- Reset bottom panel
    main.bottomPanel:SetHeight(30)

    -- Reset side panel
    f = main.sidePanel
    f:SetWidth(251)
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, 30)
    f:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", 0, -30)
    main.closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    toggleBtn:SetPoint("RIGHT", main.maximizeButton, "LEFT", 10, 0)
    currentPullBtn:Hide()
    announceBtn:Hide()

    -- Reset enemy info
    f = main.sidePanel.PullButtonScrollGroup.frame
    f:ClearAllPoints()
    f:SetWidth(248)
    f:SetHeight(410)
    f:SetPoint("TOPLEFT", main.sidePanel.WidgetGroup.frame, "BOTTOMLEFT", -4, -32)
    f:SetPoint("BOTTOMLEFT", main.sidePanel, "BOTTOMLEFT", 0, 30)

    -- Reset size
    Addon.ZoomBy(1 / Addon.ZOOM)
    MDT:GetDB().nonFullscreenScale = 1
    MDT:Minimize()
    main:SetMinResize(Addon.WIDTH * 0.75, Addon.HEIGHT * 0.75)

    -- Reset enemy info frame
    if MDT.EnemyInfoFrame and MDT.EnemyInfoFrame:IsShown() then
        Addon.AdjustEnemyInfo()
    end

    -- Allow closing with esc
    local found
    for _,v in pairs(UISpecialFrames) do
        if v == "MDTFrame" then found = true break end
    end
    if not found then
        tinsert(UISpecialFrames, "MDTFrame")
    end

    -- Disable fade
    Addon.SetFade()

     return true
end

function Addon.ToggleGuideMode()
    if MDTGuideActive then
        Addon.DisableGuideMode()
    else
        Addon.EnableGuideMode()
    end
end

function Addon.ReloadGuideMode(fn)
    if Addon.IsActive() then
        Addon.ToggleGuideMode()
        fn()
        Addon.ToggleGuideMode()
    else
        fn()
    end
end

function Addon.AdjustEnemyInfo()
    local f = MDT.EnemyInfoFrame
    if f then
        if not MDTGuideActive then
            f.frame:ClearAllPoints()
            f.frame:SetAllPoints(MDTScrollFrame)
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

        MDT:UpdateEnemyInfoFrame()
        f.enemyDataContainer.stealthCheckBox:SetWidth((f.enemyDataContainer.frame:GetWidth()/2)-40)
        f.enemyDataContainer.stealthDetectCheckBox:SetWidth((f.enemyDataContainer.frame:GetWidth()/2))
        f.spellScroll:SetWidth(f.spellScrollContainer.content:GetWidth() or 0)
    end
end

function Addon.GetHideFrames()
    local main = MDT.main_frame

    hideFrames = hideFrames or {
        main.bottomPanelString,
        main.sidePanel.WidgetGroup,
        main.sidePanel.ProgressBar,
        main.toolbar.toggleButton,
        main.maximizeButton,
        main.HelpButton,
        main.DungeonSelectionGroup
    }

    return hideFrames
end

-- ---------------------------------------
--                 Zoom
-- ---------------------------------------

function Addon.Zoom(s, x, y, smooth)
    local main = MDT.main_frame
    local scroll, map = main.scrollFrame, main.mapPanelFrame

    -- Don't go out of bounds
    local scale = MDT:GetScale()
    local width, height = Addon.WIDTH * scale, Addon.HEIGHT * scale

    if x > width * (1 - 1/s) then
        local diff = x + width * (1/s - 1)
        x, y, s = x + diff, y + diff * (1 / Addon.RATIO), 1 / (1 - (x + diff) / width)
    end
    if y > height * (1 - 1/s) then
        local diff = y + height * (1/s - 1)
        y, x, s = y + diff, x + diff * Addon.RATIO, 1 / (1 - (y + diff) / height)
    end

    if zoomAnimGrp then
        zoomAnimGrp = zoomAnimGrp:Stop()
    end

    if smooth then
        local fromS = map:GetScale()
        local fromX = scroll:GetHorizontalScroll()
        local fromY = scroll:GetVerticalScroll()
        zoomAnimGrp = main:CreateAnimationGroup()
        local anim = zoomAnimGrp:CreateAnimation("Animation")
        anim:SetDuration(0.4)
        anim:SetSmoothing("IN_OUT")
        anim:SetScript("OnUpdate", function ()
            local p = anim:GetSmoothProgress()
            map:SetScale(fromS + (s - fromS) * p)
            scroll:SetHorizontalScroll(fromX + (x - fromX) * p)
            scroll:SetVerticalScroll(fromY + (y - fromY) * p)
        end)
        anim:SetScript("OnFinished", function ()
            zoomAnimGrp = nil
            MDT:ZoomMap(0)
        end)
        zoomAnimGrp:Play()
    else
        map:SetScale(s)
        scroll:SetHorizontalScroll(x)
        scroll:SetVerticalScroll(y)
        MDT:ZoomMap(0)
    end
end

function Addon.ZoomBy(factor)
    local main = MDT.main_frame
    local scroll, map = main.scrollFrame, main.mapPanelFrame

    local scale = factor * map:GetScale()
    local n = (factor-1)/2 / scale
    local scrollX = scroll:GetHorizontalScroll() + n * scroll:GetWidth()
    local scrollY = scroll:GetVerticalScroll() + n * scroll:GetHeight()

    Addon.Zoom(scale, scrollX, scrollY)
end

function Addon.ZoomTo(minX, minY, maxX, maxY, subLevel, fromSub)
    -- Change sublevel if required
    local currSub = MDT:GetCurrentSubLevel()
    subLevel, fromSub = subLevel or currSub, fromSub or currSub
    if subLevel ~= currSub then
        MDT:SetCurrentSubLevel(subLevel)
        MDT:UpdateMap(true, true, true)
        MDT:DungeonEnemies_UpdateSelected()
    end

    local diffX, diffY = maxX - minX, maxY - minY

    -- Ensure min rect size
    local scale = MDT:GetScale()
    local sizeScale = scale * Addon.GetDungeonScale()
    local sizeX = Addon.MIN_X * sizeScale * MDTGuideOptions.zoomMin
    local sizeY = Addon.MIN_Y * sizeScale * MDTGuideOptions.zoomMin

    if diffX < sizeX then
        minX, maxX, diffX = minX - (sizeX - diffX)/2, maxX + (sizeX - diffX)/2, sizeX
    end
    if diffY < sizeY then
        minY, maxY, diffY = minY - (sizeY - diffY)/2, maxY + (sizeY - diffY)/2, sizeY
    end

    -- Get zoom and scroll values
    local s = min(15, Addon.WIDTH / diffX, Addon.HEIGHT / diffY)
    local scrollX = minX + diffX/2 - Addon.WIDTH/s/2
    local scrollY = -maxY + diffY/2 - Addon.HEIGHT/s/2

    Addon.Zoom(s, scrollX * scale, scrollY * scale, subLevel == fromSub)
end

function Addon.ZoomToPull(n, fromSub)
    n = n or MDT:GetCurrentPull()
    local pulls = Addon.GetCurrentPulls()
    local pull = pulls[n]

    local dungeonScale = Addon.GetDungeonScale()
    local sizeScale = MDT:GetScale() * dungeonScale
    local sizeX = Addon.MAX_X * sizeScale * MDTGuideOptions.zoomMax
    local sizeY = Addon.MAX_Y * sizeScale * MDTGuideOptions.zoomMax

    if pull then
        local bestSub = Addon.GetBestSubLevel(pull)

        if bestSub then
            -- Get rect to zoom to
            local minX, minY, maxX, maxY = Addon.GetPullRect(n, bestSub)

            -- Border
            minX, minY, maxX, maxY = Addon.ExtendRect(minX, minY, maxX, maxY, Addon.ZOOM_BORDER * dungeonScale)

            -- Try to include prev/next pulls
            for i=1,4 do
                for p=-i,i,2*i do
                    pull = pulls[n+p]

                    if pull then
                        local pMinX, pMinY, pMaxX, pMaxY = Addon.CombineRects(minX, minY, maxX, maxY, Addon.GetPullRect(pull, bestSub))

                        if pMinX and pMaxX - pMinX <= sizeX and pMaxY - pMinY <= sizeY then
                            minX, minY, maxX, maxY = pMinX, pMinY, pMaxX, pMaxY
                        end
                    end
                end
            end

            -- Zoom to rect
            Addon.ZoomTo(minX, minY, maxX, maxY, bestSub, fromSub)

            -- Scroll pull list
            Addon.ScrollToPull(n)
        end
    end
end

function Addon.ScrollToPull(n, center)
    local main = MDT.main_frame
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
--                 Fade
-- ---------------------------------------

function Addon.SetFade(fade)
    if fade ~= nil then
        MDTGuideOptions.fade = fade
    end

    if Addon.IsActive() and MDTGuideOptions.fade then
        if not fadeTicker then
            fadeTicker = C_Timer.NewTicker(0.5, Addon.Fade)

            for _,f in pairs(Addon.GetHoverFrames()) do
                f:SetScript("OnEnter", Addon.Fade)
                f:SetScript("OnLeave", Addon.Fade)
            end

            Addon.Fade()
        end
    elseif fadeTicker then
        fadeTicker = fadeTicker:Cancel()

        for _,f in pairs(Addon.GetHoverFrames()) do
            f:SetScript("OnEnter", nil)
            f:SetScript("OnLeave", nil)
        end

        Addon.FadeIn()
    end
end

function Addon.Fade(fadeIn)
    if Addon.MouseIsOver() then
        Addon.FadeIn()
    elseif not isFaded then
        isFaded = true
        C_Timer.After(0.5, Addon.FadeOut)
    end
end

function Addon.FadeIn()
    if isFaded then
        isFaded = false
        Addon.SetAlpha(1)
    end
end

function Addon.FadeOut()
    if isFaded and not Addon.MouseIsOver() then
        Addon.SetAlpha(MDTGuideOptions.fade)
    end
end

function Addon.SetAlpha(alpha, smooth)
    MDT.main_frame:SetAlpha(alpha)

    local i = 1
    while _G["MDTPullButton" .. i]  do
        _G["MDTPullButton" .. i]:SetAlpha(alpha)
        i = i+1
    end
end

function Addon.MouseIsOver()
    for _,f in pairs(Addon.GetHoverFrames()) do
       if f:IsMouseOver() then return true end
    end
    return false
end

function Addon.GetHoverFrames()
    local main = MDT.main_frame

    hoverFrames = hoverFrames or {
        main,
        main.topPanel,
        main.bottomPanel,
        main.sidePanel
    }

    return hoverFrames
end

-- ---------------------------------------
--                Announce
-- ---------------------------------------

function Addon.AnnouncePull(n)
    n = n or MDT:GetCurrentPreset().value.currentPull
    if not n then return end

    local enemies = Addon.GetCurrentEnemies()

    local pull = Addon.GetCurrentPulls()[n]
    if not pull then return end

    Addon.Chat("---------- Pull " .. n .. " ----------")

    for enemyId,clones in pairs(pull) do
        local enemy = enemies[enemyId]
        if #clones > 0 and enemy and enemy.name then
            Addon.Chat(#clones .. "x " .. enemy.name)
        end
    end

    local forces = MDT:CountForces(n, true)
    if forces > 0 then
        Addon.Chat("Forces: " .. forces .. " => " ..  MDT:FormatEnemyForces(MDT:CountForces(n, false)))
    end
end

function Addon.AnnounceSelectedPulls(selection)
    selection = selection or MDT:GetCurrentPreset().value.selection
    if not selection then return end

    for _,i in ipairs(selection) do
        Addon.AnnouncePull(i)
    end
end

function Addon.AnnounceNextPulls(n)
    n = n or MDT:GetCurrentPreset().value.currentPull
    if not n then return end

    for i=n,#Addon.GetCurrentPulls() do
        Addon.AnnouncePull(i)
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
--               Progress
-- ---------------------------------------

function Addon.GetCurrentPull()
    if Addon.IsCurrentInstance() then
        if Addon.UseRoute() then
            return Addon.GetCurrentPullByRoute()
        else
            return Addon.GetCurrentPullByEnemyForces()
        end
    end
end

function Addon.ZoomToCurrentPull(refresh)
    if Addon.UseRoute() and refresh then
        Addon.UpdateRoute(true)
    elseif Addon.IsActive() then
        local n, pull = Addon.GetCurrentPull()
        if n then
            local fromSub = MDT:GetCurrentSubLevel()
            MDT:SetSelectionToPull(n)
            if MDT:GetCurrentSubLevel() ~= Addon.GetBestSubLevel(pull) then
                Addon.ZoomToPull(n, fromSub)
            end
        end
    end
end

function Addon.ColorEnemy(enemyId, cloneId, color)
    local r, g, b = unpack(color)
    local blip = MDT:GetBlip(enemyId, cloneId)
    if blip then
        blip.texture_SelectedHighlight:SetVertexColor(r, g, b, 0.7)
        blip.texture_Portrait:SetVertexColor(r, g, b, 1)
    end
end

function Addon.ColorEnemies()
    if Addon.IsActive() and Addon.IsCurrentInstance() then
        if Addon.UseRoute() then
            local n = Addon.GetCurrentPullByRoute()
            if n and n > 0 then
                Addon.IteratePull(n, function (_, _, cloneId, enemyId)
                    Addon.ColorEnemy(enemyId, cloneId, Addon.COLOR_CURR)
                end)
            end
            for enemyId, cloneId in MDTGuideRoute:gmatch("-e(%d+)c(%d+)-") do
                Addon.ColorEnemy(tonumber(enemyId), tonumber(cloneId), Addon.COLOR_DEAD)
            end
        else
            local n = Addon.GetCurrentPullByEnemyForces()
            if n and n > 0 then
                Addon.IteratePulls(function (_, _, cloneId, enemyId, _, i)
                    if i > n then
                        return true
                    else
                        Addon.ColorEnemy(enemyId, cloneId, i == n and Addon.COLOR_CURR or Addon.COLOR_DEAD)
                    end
                end)
            end
        end
    end
end

-- ---------------------------------------
--                 State
-- ---------------------------------------

function Addon.IsActive()
    local main = MDT.main_frame
    return MDTGuideActive and main and main:IsShown()
end

function Addon.IsInRun()
    return Addon.IsActive() and Addon.IsCurrentInstance() and Addon.GetEnemyForces() and true
end

-- ---------------------------------------
--              Events/Hooks
-- ---------------------------------------

local Frame = CreateFrame("Frame")

-- Event listeners
local OnEvent = function (_, ev, ...)
    if not MDT or MDT:GetDB().devMode then return end

    if ev == "ADDON_LOADED" then
        if ... == Name then
            Frame:UnregisterEvent("ADDON_LOADED")

            Addon.MigrateOptions()

            -- Hook showing interface
            hooksecurefunc(MDT, "ShowInterface", function ()
                local main = MDT.main_frame

                -- Insert toggle button
                if not toggleBtn then
                    toggleBtn = CreateFrame("Button", nil, MDT.main_frame, "MaximizeMinimizeButtonFrameTemplate")
                    toggleBtn[MDTGuideActive and "Minimize" or "Maximize"](toggleBtn)
                    toggleBtn:SetOnMaximizedCallback(function () Addon.DisableGuideMode() end)
                    toggleBtn:SetOnMinimizedCallback(function () Addon.EnableGuideMode() end)
                    toggleBtn:Show()

                    main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT", 10, 0)
                    toggleBtn:SetPoint("RIGHT", main.maximizeButton, "LEFT", 10, 0)
                end

                -- Insert current pull button
                if not currentPullBtn then
                    currentPullBtn = CreateFrame("Button", nil, MDT.main_frame, "SquareIconButtonTemplate")
                    currentPullBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                    currentPullBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
                    currentPullBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
                    currentPullBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
                    currentPullBtn:SetFrameLevel(4)
                    currentPullBtn:SetHeight(21)
                    currentPullBtn:SetWidth(21)
                    currentPullBtn:SetScript("OnClick", function () Addon.ZoomToCurrentPull() end)
                    currentPullBtn:SetScript("OnEnter", function ()
                        GameTooltip:SetOwner(currentPullBtn, "ANCHOR_BOTTOM", 0, 0)
                        GameTooltip:AddLine("Go to current pull")
                        GameTooltip:Show()
                    end)
                    currentPullBtn:SetScript("OnLeave", function () GameTooltip:Hide() end)

                    currentPullBtn:SetPoint("RIGHT", toggleBtn, "LEFT", 0, 0.5)
                end

                if not announceBtn then
                    announceBtn = CreateFrame("Button", nil, MDT.main_frame, "SquareIconButtonTemplate")
                    announceBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-MOTD-Up")
                    announceBtn:SetDisabledTexture("Interface\\Buttons\\UI-GuildButton-MOTD-Disabled")
                    announceBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
                    announceBtn:SetFrameLevel(4)
                    announceBtn:SetHeight(13)
                    announceBtn:SetWidth(13)
                    announceBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    announceBtn:SetScript("OnClick", function (_, btn)
                        if btn == "RightButton" then
                            Addon.AnnounceNextPulls()
                        else
                            Addon.AnnounceSelectedPulls()
                        end
                    end)
                    announceBtn:SetScript("OnEnter", function ()
                        GameTooltip:SetOwner(announceBtn, "ANCHOR_BOTTOM", 0, 0)
                        GameTooltip:AddLine("Announce selected pulls")
                        GameTooltip:AddLine("Right click: Also announce following pulls", 1, 1, 1, true)
                        if not IsInGroup() then
                            GameTooltip:AddLine("(Shows preview while not in a group)", 0.7, 0.7, 0.7, true)
                        end
                        GameTooltip:Show()
                    end)
                    announceBtn:SetScript("OnLeave", function () GameTooltip:Hide() end)

                    announceBtn:SetPoint("RIGHT", currentPullBtn, "LEFT", -8, 0)
                end

                if MDTGuideActive then
                    MDTGuideActive = false
                    Addon.EnableGuideMode(true)
                end
            end)

            -- Hook maximize/minimize
            hooksecurefunc(MDT, "Maximize", function ()
                local main = MDT.main_frame

                Addon.DisableGuideMode()
                if toggleBtn then
                    toggleBtn:Hide()
                    main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT")
                end
            end)
            hooksecurefunc(MDT, "Minimize", function ()
                local main = MDT.main_frame

                Addon.DisableGuideMode()
                if toggleBtn then
                    toggleBtn:Show()
                    main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT", 10, 0)
                end
            end)

            -- Hook dungeon selection
            hooksecurefunc(MDT, "UpdateToDungeon", function ()
                Addon.SetDungeon()
            end)

            -- Hook sublevel selection
            local fromSub
            local origFn = MDT.SetMapSublevel
            MDT.SetMapSublevel = function (...)
                fromSub = MDT:GetCurrentSubLevel()
                origFn(...)
            end
            local origFn = MDT.SetCurrentSubLevel
            MDT.SetCurrentSubLevel = function (...)
                fromSub = MDT:GetCurrentSubLevel()
                origFn(...)
            end

            -- Hook pull selection
            hooksecurefunc(MDT, "SetSelectionToPull", function (_, pull)
                if  Addon.IsActive() and tonumber(pull) and Addon.GetLastSubLevel(pull) == MDT:GetCurrentSubLevel() then
                    Addon.ZoomToPull(pull, fromSub)
                end
                fromSub = nil
            end)

            -- Hook pull tooltip
            hooksecurefunc(MDT, "ActivatePullTooltip", function ()
                if Addon.IsActive() then
                    local tooltip = MDT.pullTooltip
                    local y2, _, frame, pos, _, y1 = select(5, tooltip:GetPoint(2)), tooltip:GetPoint(1)
                    local w = frame:GetWidth() + tooltip:GetWidth()

                    tooltip:SetPoint("TOPRIGHT", frame, pos, w, y1)
                    tooltip:SetPoint("BOTTOMRIGHT", frame, pos, 250 + w, y2)
                end
            end)

            -- Hook enemy blips
            hooksecurefunc(MDT, "DungeonEnemies_UpdateSelected", Addon.ColorEnemies)

            -- Hook enemy info frame
            hooksecurefunc(MDT, "ShowEnemyInfoFrame", Addon.AdjustEnemyInfo)

            -- Hook menu creation
            hooksecurefunc(MDT, "CreateMenu", function ()
                local main = MDT.main_frame

                -- Hook size change
                main.resizer:HookScript("OnMouseUp", function ()
                    if MDTGuideActive then
                        MDTGuideOptions.height = main:GetHeight()
                    end
                end)
            end)

            -- Hook hull drawing
            local origFn = MDT.DrawHull
            MDT.DrawHull = function (...)
                if MDTGuideActive then
                    local scale = MDT:GetScale() or 1
                    for i=1,MDT:GetNumDungeons() do MDT.scaleMultiplier[i] = (MDT.scaleMultiplier[i] or 1) * scale end
                    origFn(...)
                    for i,v in pairs(MDT.scaleMultiplier) do MDT.scaleMultiplier[i] = v / scale end
                else
                    origFn(...)
                end
            end
        end
    elseif ev == "SCENARIO_CRITERIA_UPDATE" and not Addon.UseRoute() then
        Addon.ZoomToCurrentPull(true)
    end
end

Frame:SetScript("OnEvent", OnEvent)
Frame:RegisterEvent("ADDON_LOADED")
Frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")

-- ---------------------------------------
--                Options
-- ---------------------------------------

SLASH_MDTG1 = "/mdtg"

function SlashCmdList.MDTG(args)
    local cmd, arg1, arg2 = strsplit(' ', args)

    -- Height
    if cmd == "height" then
        arg1 = tonumber(arg1)
        if not arg1 then
            return Addon.Echo(cmd, "First parameter must be a number.")
        end

        Addon.ReloadGuideMode(function ()
            MDTGuideOptions.height = tonumber(arg1)
        end)
        Addon.Echo(cmd, "Height set to " .. arg1 .. ".")

    -- Route
    elseif cmd == "route" then
        Addon.UseRoute(arg1 ~= "off")
        Addon.Echo("Route predition", MDTGuideOptions.route and "enabled" or "disabled")

    -- Zoom
    elseif cmd == "zoom" then
        arg1 = tonumber(arg1)
        if not arg1 then
            return Addon.Echo(cmd, "First parameter must be a number.")
        end
        arg2 = not arg2 and arg1 or tonumber(arg2)
        if not arg2 then
            return Addon.Echo(cmd, "Second parameter must be a number if set.")
        end

        MDTGuideOptions.zoomMin = arg1
        MDTGuideOptions.zoomMax = arg2
        Addon.Echo("Zoom scale", "Set to " .. arg1 .. " / " .. arg2)

    -- Fade
    elseif cmd == "fade" then
        Addon.SetFade(tonumber(arg1) or arg1 ~= "off" and 0.3)
        Addon.Echo("Fade", MDTGuideOptions.fade and "enabled" or "disabled")

    -- Help
    else
        Addon.Echo("Usage")
        print("|cffcccccc/mdtg height <height>|r: Adjust the guide window size by setting the height. (current: " .. math.floor(MDTGuideOptions.height) .. ", default: 200)")
        print("|cffcccccc/mdtg route [on/off]|r: Enable/Disable route estimation. (current: " .. (MDTGuideOptions.route and "on" or "off") .. ", default: off)")
        print("|cffcccccc/mdtg zoom <min-or-both> [<max>]|r: Scale default min and max visible area size when zooming. (current: " .. MDTGuideOptions.zoomMin .. " / " .. MDTGuideOptions.zoomMax .. ", default: 1 / 1)")
        print("|cffcccccc/mdtg fade [on/off/<opacity>]|r: Enable/Disable fading or set opacity. (current: " .. (MDTGuideOptions.fade or "off") .. ", default: 0.3)")
        print("|cffcccccc/mdtg|r: Print this help message.")
        print("Legend: <...> = number, [...] = optional, .../... = either or")
    end
end

function Addon.MigrateOptions()
    if not MDTGuideOptions.version then
        MDTGuideOptions.zoom = nil
        MDTGuideOptions.zoomMin = 1
        MDTGuideOptions.zoomMax = 1
        MDTGuideOptions.route = false
        MDTGuideOptions.version = 1
    end
end
