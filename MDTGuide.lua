local _, Addon = ...

local WIDTH = 300
local HEIGHT = 0.66 * WIDTH
local ZOOM = 1.8

local hooked, active, toggleButton
local mdt, main, frames

function Addon.GetFrames()
    if not frames then
        frames = {
            main.bottomPanel,
            main.sidePanel,
            main.sidePanel.WidgetGroup,
            main.toolbar.toggleButton,
            main.maximizeButton,
            main.closeButton,
            main.HelpButton,
            main.DungeonSelectionGroup
        }
    end
    return frames
end

function Addon.Zoom(by)
    local z = math.pow(ZOOM, by or 1)
    local scroll = main.scrollFrame
    local map = main.mapPanelFrame

    local scale = z * map:GetScale()
    local n = (z - 1) / (2 * scale)
    local scrollX = scroll:GetHorizontalScroll() + n * scroll:GetWidth()
    local scrollY = scroll:GetVerticalScroll() + n * scroll:GetHeight()

    map:SetScale(scale)
    scroll:SetHorizontalScroll(scrollX)
    scroll:SetVerticalScroll(scrollY)
    mdt:ZoomMap(0)
end

function Addon.EnableGuideMode()
    if active then return end
    active = true


    -- Hide frames
    for _,f in pairs(Addon.GetFrames()) do
       (f.frame or f):Hide()
    end

    if main.toolbar:IsShown() then
        main.toolbar.toggleButton:GetScript("OnClick")()
    end

    -- Resize
    mdt:StartScaling()
    mdt:SetScale(HEIGHT / 555)
    mdt:UpdateMap()

    -- Zoom
    if main.mapPanelFrame:GetScale() > 1 then
        Addon.Zoom()
    end

    -- Adjust top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", HEIGHT, 0)
    f:SetHeight(25)

    -- Adjust enemy info
    f = main.sidePanel.PullButtonScrollGroup
    f.frame:ClearAllPoints()
    f.frame:SetPoint("TOPLEFT", main.scrollFrame, "TOPRIGHT")
    f.frame:SetPoint("BOTTOMLEFT", main.scrollFrame, "BOTTOMRIGHT")
    f.frame:SetWidth(HEIGHT)

    return true
end

function Addon.DisableGuideMode()
    if not active then return end
    active = false

    for _,f in pairs(Addon.GetFrames()) do
        (f.frame or f):Show()
    end

    -- Reset top panel
    local f = main.topPanel
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", main, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT")
    f:SetHeight(30)

    -- Reset enemy info
    f = main.sidePanel.PullButtonScrollGroup.frame
    f:ClearAllPoints()
    f:SetWidth(248)
    f:SetHeight(410)
    f:SetPoint("TOPLEFT", main.sidePanel.WidgetGroup.frame, "BOTTOMLEFT", -4, -32)
    f:SetPoint("BOTTOMLEFT", main.sidePanel, "BOTTOMLEFT", 0, 30)

    -- Reset size
    Addon.Zoom(-1)
    mdt:GetDB().nonFullscreenScale = 1
    mdt:Minimize()

     return true
end

function Addon.ToggleGuideMode()
    if active then
        Addon.DisableGuideMode()
    else
        Addon.EnableGuideMode()
    end
end

function Addon.HookMethodDungeonTools()
    if hooked then return end
    hooked = true

    mdt = MethodDungeonTools

    -- Insert toggle button
    hooksecurefunc(mdt, "ShowInterface", function ()
        if toggleButton then return end

        main = mdt.main_frame

        toggleButton = CreateFrame("Button", nil, mdt.main_frame, "MaximizeMinimizeButtonFrameTemplate")
        toggleButton:Maximize()
        toggleButton:SetOnMaximizedCallback(Addon.DisableGuideMode)
        toggleButton:SetOnMinimizedCallback(Addon.EnableGuideMode)
        toggleButton:Show()

        main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT", 10, 0)
        toggleButton:SetPoint("RIGHT", main.maximizeButton, "LEFT", 10, 0)
    end)

    -- Hook maximize/minimize
    hooksecurefunc(mdt, "Maximize", function ()
        Addon.DisableGuideMode()
        if toggleButton then
            toggleButton:Hide()
            main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT")
        end
    end)
    hooksecurefunc(mdt, "Minimize", function ()
        Addon.DisableGuideMode()
        if toggleButton then
            toggleButton:Show()
            main.maximizeButton:SetPoint("RIGHT", main.closeButton, "LEFT", 10, 0)
        end
    end)
end

local Events = CreateFrame("Frame")
Events:SetScript("OnEvent", function (_, ev, ...)
    if ev == "ADDON_LOADED" and ... == "MethodDungeonTools" then
        Addon.HookMethodDungeonTools()
    end
end)
Events:RegisterEvent("ADDON_LOADED")