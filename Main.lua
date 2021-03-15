local Name, Addon = ...

MDTG = Addon
MDTGuideActive = false
MDTGuideRoute = ""
MDTGuideOptions = {
    height = 200,
    widthSide = 200,
    zoom = 1.8
}

Addon.WIDTH = 840
Addon.HEIGHT = 555
Addon.RATIO = Addon.WIDTH / Addon.HEIGHT
Addon.MIN_HEIGHT = 150
Addon.MIN_Y, Addon.MAX_Y = 180, 270
Addon.MIN_X, Addon.MAX_X = Addon.MIN_Y * Addon.RATIO, Addon.MAX_Y * Addon.RATIO
Addon.ZOOM_BORDER = 15
Addon.COLOR_CURR = {0.13, 1, 1}
Addon.COLOR_DEAD = {0.55, 0.13, 0.13}
Addon.DEBUG = false
Addon.PATTERN_INSTANCE_RESET = "^" .. INSTANCE_RESET_SUCCESS:gsub("%%s", ".+") .. "$"

Addon.currentDungeon = nil

local toggleBtn, currentPullBtn, announceBtn = nil
local frames = nil

-- ---------------------------------------
--              Toggle mode
-- ---------------------------------------

function Addon.EnableGuideMode(noZoom)
    if MDTGuideActive then return end
    MDTGuideActive = true

    local main = MDT.main_frame

    -- Hide frames
    for _,f in pairs(Addon.GetFramesToHide()) do
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
        Addon.ZoomBy(MDTGuideOptions.zoom)
    end

    -- Adjust top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", MDTGuideOptions.widthSide, 0)
    f:SetHeight(25)

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

    return true
end

function Addon.DisableGuideMode()
    if not MDTGuideActive then return end
    MDTGuideActive = false

    local main = MDT.main_frame

    for _,f in pairs(Addon.GetFramesToHide()) do
        (f.frame or f):Show()
    end

    -- Reset top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT")
    f:SetHeight(30)

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

    -- Reset enemy info
    f = main.sidePanel.PullButtonScrollGroup.frame
    f:ClearAllPoints()
    f:SetWidth(248)
    f:SetHeight(410)
    f:SetPoint("TOPLEFT", main.sidePanel.WidgetGroup.frame, "BOTTOMLEFT", -4, -32)
    f:SetPoint("BOTTOMLEFT", main.sidePanel, "BOTTOMLEFT", 0, 30)

    -- Reset size
    Addon.ZoomBy(1 / MDTGuideOptions.zoom)
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

-- ---------------------------------------
--                 Zoom
-- ---------------------------------------

function Addon.Zoom(scale, scrollX, scrollY)
    local main = MDT.main_frame
    local scroll, map = main.scrollFrame, main.mapPanelFrame
    
    map:SetScale(scale)
    scroll:SetHorizontalScroll(scrollX)
    scroll:SetVerticalScroll(scrollY)
    MDT:ZoomMap(0)
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

function Addon.ZoomTo(minX, minY, maxX, maxY)
    local main = MDT.main_frame

    local diffX, diffY = maxX - minX, maxY - minY

    -- Ensure min rect size
    local scale = MDT:GetScale()
    local sizeScale = scale * Addon.GetDungeonScale()
    local sizeX, sizeY = Addon.MIN_X * sizeScale, Addon.MIN_Y * sizeScale
    
    if diffX < sizeX then
        minX, maxX, diffX = minX - (sizeX - diffX)/2, maxX + (sizeX - diffX)/2, sizeX
    end    
    if diffY < sizeY then
        minY, maxY, diffY = minY - (sizeY - diffY)/2, maxY + (sizeY - diffY)/2, sizeY
    end
    
    -- Get zoom and scroll values
    local s = min(15, Addon.WIDTH / diffX, Addon.HEIGHT / diffY)
    local scrollX = (minX + diffX/2 - Addon.WIDTH/s/2) * scale
    local scrollY = (-maxY + diffY/2 - Addon.HEIGHT/s/2) * scale
    
    Addon.Zoom(s, scrollX, scrollY)
end

function Addon.ZoomToPull(n)
    n = n or MDT:GetCurrentPull()
    local pulls = Addon.GetCurrentPulls() 
    local pull = pulls[n]

    local dungeonScale = Addon.GetDungeonScale()
    local sizeScale = MDT:GetScale() * dungeonScale
    local sizeX, sizeY = Addon.MAX_X * sizeScale, Addon.MAX_Y * sizeScale
    
    if pull then
        -- Get best sublevel
        local currSub, minDiff = MDT:GetCurrentSubLevel()
        Addon.IteratePull(pull, function (clone)
                local diff = clone.sublevel - currSub
                if not minDiff or abs(diff) < abs(minDiff) or abs(diff) == abs(minDiff) and diff < minDiff then
                    minDiff = diff
                end
                return minDiff == 0
        end)
        
        if minDiff then
            local bestSub = currSub + minDiff
            
            -- Get rect to zoom to
            local minX, minY, maxX, maxY = Addon.GetPullRect(n, bestSub)
            
            -- Border
            minX, minY, maxX, maxY = Addon.ExtendRect(minX, minY, maxX, maxY, Addon.ZOOM_BORDER * dungeonScale)
            
            -- Try to include prev/next pulls
            for i=1,3 do
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
            
            -- Change sublevel (if required)
            if bestSub ~= currSub then
                MDT:SetCurrentSubLevel(bestSub)
                MDT:UpdateMap(true)
            end
            
            -- Zoom to rect
            Addon.ZoomTo(minX, minY, maxX, maxY)
            
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
--             Announce
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
        if Addon.IsBFS() then
            return Addon.GetCurrentPullByRoute()
        else
            return Addon.GetCurrentPullByEnemyForces()
        end
    end
end

function Addon.ZoomToCurrentPull(refresh)
    if Addon.IsBFS() and refresh then
        Addon.UpdateRoute(true)
    elseif Addon.IsActive() then
        local n = Addon.GetCurrentPull()
        if n then
            MDT:SetSelectionToPull(n)
            Addon.ScrollToPull(n, true)
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
        if Addon.IsBFS() then
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

function Addon.GetFramesToHide()
    local main = MDT.main_frame

    frames = frames or {
        main.bottomPanelString,
        main.sidePanel.WidgetGroup,
        main.sidePanel.ProgressBar,
        main.toolbar.toggleButton,
        main.maximizeButton,
        main.HelpButton,
        main.DungeonSelectionGroup
    }

    return frames
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

                -- TODO:DEBUG
                Addon.currentPullBtn = currentPullBtn
                Addon.announceBtn = announceBtn

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

            -- Hook pull selection
            hooksecurefunc(MDT, "SetSelectionToPull", function (_, pull)
                if Addon.IsActive() and tonumber(pull) then
                    Addon.ZoomToPull(pull)
                end
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
    elseif ev == "SCENARIO_CRITERIA_UPDATE" and not Addon.IsBFS() then
        Addon.ZoomToCurrentPull(true)
    end
end

Frame:SetScript("OnEvent", OnEvent)
Frame:RegisterEvent("ADDON_LOADED")
Frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")

-- ---------------------------------------
--                  CLI
-- ---------------------------------------

SLASH_MDTG1 = "/mdtg"

function SlashCmdList.MDTG(args)
    local cmd, arg1 = strsplit(' ', args)

    if cmd == "height" then
        arg1 = tonumber(arg1)
        if not arg1 then
            Addon.Echo(cmd, "First parameter must be a number.")
        else
            Addon.ReloadGuideMode(function ()
                MDTGuideOptions.height = tonumber(arg1)
            end)
            Addon.Echo(cmd, "Height set to " .. arg1 .. ".")
        end
    elseif cmd == "route" then
        arg1 = arg1 or not Addon.BFS and "enable"
        Addon.BFS = arg1 == "enable"
        Addon.Echo(cmd, "Route predition " .. (Addon.BFS and "enabled" or "disabled"))
    else
        Addon.Echo("Usage")
        print("|cffbbbbbb/mdtg height [height]|r: Adjust the guide window size by setting the height, default is 200.")
        print("|cffbbbbbb/mdtg route [enable/disable]|r: Enable/Disable/Toggle route estimation.")
        print("|cffbbbbbb/mdtg|r: Print this help message.")
    end
end
