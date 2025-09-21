-- ESPMenu.client.lua
-- CNR-ST: ESP (On/Off + Color), Fly (On/Off + Speed), Noclip (On/Off),
--         Aimbot (Shift basiliyken direkt snap),
--         Unlock Cam (FPS), Insert=minimize, Home=mouse serbest

--// Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer

--// State
local STATE = {
    EspEnabled = true,
    EspColor   = Color3.fromRGB(255,255,255),

    FlyEnabled = false,
    FlySpeed   = 200,
    ShiftMultiplier = 2,

    NoclipEnabled = false,

    AimbotEnabled = false,
    AimbotFOV = 45,        -- derece
    AimbotMaxDist = 300,   -- studs
    AimbotCheckLOS = true, -- duvar arkasi kontrol
    AimbotSmooth = 0,      -- direkt snap (0)

    UnlockCamEnabled = false, -- FPS oyunlarinda kamera kilidini ac
}

local function tween(o, props, t)
    TweenService:Create(o, TweenInfo.new(t or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

----------------------------------------------------------------
-- ESP: Robust Highlight Manager
----------------------------------------------------------------
local espFolder do
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then
        espFolder = core:FindFirstChild("CNRST_ESPF") or Instance.new("Folder")
        espFolder.Name = "CNRST_ESPF"
        espFolder.Parent = core
    else
        local pg = LocalPlayer:WaitForChild("PlayerGui")
        espFolder = pg:FindFirstChild("CNRST_ESPF") or Instance.new("Folder")
        espFolder.Name = "CNRST_ESPF"
        espFolder.Parent = pg
    end
end

-- [Player] -> Highlight
local HLS = {}

local function applyHL(hl)
    if not hl then return end
    hl.Enabled = STATE.EspEnabled
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = STATE.EspColor
    hl.OutlineColor = STATE.EspColor
    hl.FillTransparency = 0.75
    hl.OutlineTransparency = 0.1
end

local function destroyHLFor(plr)
    local old = HLS[plr]
    if old then
        HLS[plr] = nil
        pcall(function() old:Destroy() end)
    end
end

local function ensureHL(plr, char)
    if not plr or plr == LocalPlayer then
        destroyHLFor(plr)
        return
    end
    if not (char and char.Parent) then
        return
    end
    local hl = HLS[plr]
    if hl and hl.Parent == espFolder and hl.Adornee == char then
        applyHL(hl)
        return
    end
    if hl then pcall(function() hl:Destroy() end) end
    hl = Instance.new("Highlight")
    hl.Name = "ESP_" .. plr.Name
    hl.Adornee = char
    hl.Parent = espFolder
    applyHL(hl)
    HLS[plr] = hl
end

local function refreshAllHL()
    for _, p in ipairs(Players:GetPlayers()) do
        if STATE.EspEnabled then
            ensureHL(p, p.Character)
        else
            destroyHLFor(p)
        end
    end
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function hum()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function hrp()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------
-- Character spawn handling
----------------------------------------------------------------
local function onCharAdded(plr, char)
    task.spawn(function()
        local deadline = time() + 5
        while time() < deadline and (not char.Parent) do
            RunService.Heartbeat:Wait()
        end
        if STATE.EspEnabled then ensureHL(plr, char) end
        if STATE.FlyEnabled and plr == LocalPlayer then task.wait(0.1); _G.__CNRST_StartFly() end
        if STATE.NoclipEnabled and plr == LocalPlayer then task.wait(0.1); _G.__CNRST_EnableNoclip() end
        if STATE.UnlockCamEnabled and plr == LocalPlayer then
            task.wait(0.05)
            if _G.__CNRST_SetUnlockCam then _G.__CNRST_SetUnlockCam(true) end
        end
    end)
end

local function onCharRemoving(plr, _char)
    destroyHLFor(plr)
end

for _, p in ipairs(Players:GetPlayers()) do
    p.CharacterAdded:Connect(function(c) onCharAdded(p, c) end)
    p.CharacterRemoving:Connect(function(c) onCharRemoving(p, c) end)
    if p.Character then onCharAdded(p, p.Character) end
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(c) onCharAdded(p, c) end)
    p.CharacterRemoving:Connect(function(c) onCharRemoving(p, c) end)
end)
Players.PlayerRemoving:Connect(function(p)
    destroyHLFor(p)
end)

RunService.Heartbeat:Connect(function()
    if not STATE.EspEnabled then return end
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        local hl = HLS[p]
        if not c then
            if hl then destroyHLFor(p) end
        else
            if (not hl) or hl.Adornee ~= c or hl.Parent ~= espFolder then
                ensureHL(p, c)
            else
                applyHL(hl)
            end
        end
    end
end)

----------------------------------------------------------------
-- Fly (optimized)
----------------------------------------------------------------
local flyBV, flyBG
local moveDir = Vector3.zero
local upHeld, downHeld, shiftHeld = false, false, false
local platformStandWas = nil

local function flyStep()
    if not flyBV or not flyBG then return end
    local root = hrp(); if not root then return end
    local cam = workspace.CurrentCamera
    local look, right, up = cam.CFrame.LookVector, cam.CFrame.RightVector, Vector3.yAxis
    local dir = (look * moveDir.Z) + (right * moveDir.X)
    if upHeld then dir += up end
    if downHeld then dir -= up end
    if dir.Magnitude > 0 then dir = dir.Unit end
    local speed = STATE.FlySpeed * (shiftHeld and STATE.ShiftMultiplier or 1)
    flyBV.Velocity = dir * speed
    flyBG.CFrame  = CFrame.lookAt(root.Position, root.Position + look, up)
end

_G.__CNRST_StartFly = function()
    if flyBV or flyBG then return end
    local root = hrp(); if not root then return end
    local h = hum()
    if h then platformStandWas = h.PlatformStand; h.PlatformStand = true end

    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(9e9,9e9,9e9)
    flyBV.Parent   = root

    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(9e9,9e9,9e9)
    flyBG.P = 3e4
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root

    if not _G.__CNRST_FlyConn then
        _G.__CNRST_FlyConn = RunService.RenderStepped:Connect(flyStep)
    end
end

_G.__CNRST_StopFly = function()
    if _G.__CNRST_FlyConn then _G.__CNRST_FlyConn:Disconnect(); _G.__CNRST_FlyConn=nil end
    if flyBV then flyBV:Destroy(); flyBV=nil end
    if flyBG then flyBG:Destroy(); flyBG=nil end
    local h = hum(); if h and platformStandWas ~= nil then h.PlatformStand = platformStandWas; platformStandWas=nil end
end

UserInputService.InputBegan:Connect(function(i)
    local k=i.KeyCode
    if k==Enum.KeyCode.W then moveDir=Vector3.new(moveDir.X,0,1) end
    if k==Enum.KeyCode.S then moveDir=Vector3.new(moveDir.X,0,-1) end
    if k==Enum.KeyCode.A then moveDir=Vector3.new(-1,0,moveDir.Z) end
    if k==Enum.KeyCode.D then moveDir=Vector3.new(1,0,moveDir.Z) end
    if k==Enum.KeyCode.Space then upHeld=true end
    if k==Enum.KeyCode.LeftControl then downHeld=true end
    if k==Enum.KeyCode.LeftShift or k==Enum.KeyCode.RightShift then shiftHeld=true end
end)
UserInputService.InputEnded:Connect(function(i)
    local k=i.KeyCode
    if k==Enum.KeyCode.W or k==Enum.KeyCode.S then moveDir=Vector3.new(moveDir.X,0,0) end
    if k==Enum.KeyCode.A or k==Enum.KeyCode.D then moveDir=Vector3.new(0,0,moveDir.Z) end
    if k==Enum.KeyCode.Space then upHeld=false end
    if k==Enum.KeyCode.LeftControl then downHeld=false end
    if k==Enum.KeyCode.LeftShift or k==Enum.KeyCode.RightShift then shiftHeld=false end
end)

----------------------------------------------------------------
-- Noclip (fixed)
----------------------------------------------------------------
local noclipConn = nil
local chDescConn = nil
local savedCollide = {} -- [BasePart] = originalCanCollide

local function eachCharacterPart(fn)
    local ch = LocalPlayer.Character
    if not ch then return end
    for _, d in ipairs(ch:GetDescendants()) do
        if d:IsA("BasePart") then fn(d) end
    end
end

_G.__CNRST_EnableNoclip = function()
    if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
    if chDescConn then chDescConn:Disconnect(); chDescConn=nil end
    savedCollide = {}

    eachCharacterPart(function(p)
        savedCollide[p] = p.CanCollide
        p.CanCollide = false
    end)

    local ch = LocalPlayer.Character
    if ch then
        ch.DescendantAdded:Connect(function(d)
            if STATE.NoclipEnabled and d:IsA("BasePart") then
                savedCollide[d] = d.CanCollide
                d.CanCollide = false
            end
        end)
    end

    noclipConn = RunService.Stepped:Connect(function()
        if not STATE.NoclipEnabled then return end
        eachCharacterPart(function(p) p.CanCollide = false end)
    end)
end

_G.__CNRST_DisableNoclip = function()
    if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
    if chDescConn then chDescConn:Disconnect(); chDescConn=nil end

    for part, was in pairs(savedCollide) do
        if part and part.Parent then
            pcall(function() part.CanCollide = was end)
        end
    end
    savedCollide = {}
end

----------------------------------------------------------------
-- Aimbot (snap)
----------------------------------------------------------------
local function getCharacterHead(plr)
    if not plr or plr == LocalPlayer then return nil end
    local ch = plr.Character
    if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local head = ch:FindFirstChild("Head")
    if not hum or hum.Health <= 0 or not head then return nil end
    return head
end

local function isInFOV(cam, worldPos, maxAngleDeg)
    local dir = (worldPos - cam.CFrame.Position)
    if dir.Magnitude <= 0 then return false end
    local angle = math.deg(math.acos((cam.CFrame.LookVector:Dot(dir.Unit))))
    return angle <= (maxAngleDeg or 999)
end

local function hasLineOfSight(origin, targetPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = workspace:Raycast(origin, (targetPos - origin), params)
    if not result then return true end
    return (result.Position - targetPos).Magnitude < 1.5
end

local function isOnScreen(pos3)
    local cam = workspace.CurrentCamera
    local v, onScreen = cam:WorldToViewportPoint(pos3)
    return onScreen, Vector2.new(v.X, v.Y)
end

local currentTarget

local function scoreTarget(head)
    local cam = workspace.CurrentCamera
    local headPos = head.Position
    local dist = (headPos - cam.CFrame.Position).Magnitude
    if dist > STATE.AimbotMaxDist then return math.huge end
    if not isInFOV(cam, headPos, STATE.AimbotFOV) then return math.huge end
    if STATE.AimbotCheckLOS and (not hasLineOfSight(cam.CFrame.Position, headPos)) then return math.huge end

    local onScr, screenPt = isOnScreen(headPos)
    local screenScore = 0
    if onScr then
        local vp = cam.ViewportSize
        local center = Vector2.new(vp.X/2, vp.Y/2)
        screenScore = (screenPt - center).Magnitude * 0.002
    else
        screenScore = 3
    end

    local ang = math.deg(math.acos(cam.CFrame.LookVector:Dot((headPos - cam.CFrame.Position).Unit)))
    local score = ang * 2 + dist * 0.01 + screenScore
    return score
end

local function getBestTarget()
    local bestHead, bestScore = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        local head = getCharacterHead(plr)
        if head then
            local sc = scoreTarget(head)
            if sc < bestScore then
                bestScore = sc
                bestHead = head
            end
        end
    end
    return bestHead
end

local function aimSnap(targetPos)
    local cam = workspace.CurrentCamera
    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, targetPos)
end

RunService.RenderStepped:Connect(function()
    local shiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    if not STATE.AimbotEnabled or not shiftDown then
        currentTarget = nil
        return
    end

    if currentTarget and currentTarget.Parent then
        local sc = scoreTarget(currentTarget)
        if sc == math.huge then currentTarget = nil end
    else
        currentTarget = nil
    end

    if not currentTarget then
        currentTarget = getBestTarget()
    end

    if currentTarget then
        aimSnap(currentTarget.Position)
    end
end)

----------------------------------------------------------------
-- Unlock Cam (only for FPS-forced games)
----------------------------------------------------------------
local SavedCam = { Mode=nil, MinZoom=nil, MaxZoom=nil, MouseBehavior=nil }

local function isFpsForced()
    local plr = LocalPlayer
    if not plr then return false end
    if plr.CameraMode == Enum.CameraMode.LockFirstPerson then return true end
    if math.abs(plr.CameraMaxZoomDistance - plr.CameraMinZoomDistance) < 0.01 and plr.CameraMaxZoomDistance <= 0.6 then
        return true
    end
    if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then return true end
    return false
end

_G.__CNRST_SetUnlockCam = function(on)
    local plr = LocalPlayer
    if not plr then return end

    if on then
        if not isFpsForced() then
            -- FPS'e zorlamayan oyunda etkisiz; UI yine On kalir
        end
        if SavedCam.Mode == nil then
            SavedCam.Mode          = plr.CameraMode
            SavedCam.MinZoom       = plr.CameraMinZoomDistance
            SavedCam.MaxZoom       = plr.CameraMaxZoomDistance
            SavedCam.MouseBehavior = UserInputService.MouseBehavior
        end
        plr.CameraMode = Enum.CameraMode.Classic
        plr.CameraMinZoomDistance = 5
        plr.CameraMaxZoomDistance = 128
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    else
        if SavedCam.Mode ~= nil then
            plr.CameraMode = SavedCam.Mode
            plr.CameraMinZoomDistance = SavedCam.MinZoom or 0.5
            plr.CameraMaxZoomDistance = SavedCam.MaxZoom or 400
            if SavedCam.MouseBehavior then
                UserInputService.MouseBehavior = SavedCam.MouseBehavior
            end
        end
        SavedCam = { Mode=nil, MinZoom=nil, MaxZoom=nil, MouseBehavior=nil }
    end
end

----------------------------------------------------------------
-- UI: sabit sag-alt panel, scrollable icerik
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ESP_Menu"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local POS_BR = UDim2.new(1, -20, 1, -20)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(360, 360)
panel.AnchorPoint = Vector2.new(1,1)
panel.Position = POS_BR
panel.BackgroundColor3 = Color3.fromRGB(18,20,26)
panel.BackgroundTransparency = 0.1
panel.Visible = true
panel.ZIndex = 10
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner", panel); panelCorner.CornerRadius = UDim.new(0,14)
local panelStroke = Instance.new("UIStroke", panel); panelStroke.Color = Color3.fromRGB(200,200,200); panelStroke.Transparency=0.45; panelStroke.Thickness=1.5

-- Title + Minimize
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -80, 0, 28)
title.Position = UDim2.fromOffset(10, 8)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235,235,235)
title.Text = "CNR-ST"
title.ZIndex = 11
title.Parent = panel

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(28,28)
minBtn.Position = UDim2.new(1, -38, 0, 8)
minBtn.BackgroundColor3 = Color3.fromRGB(70,76,92)
minBtn.Text = "-"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 20
minBtn.TextColor3 = Color3.fromRGB(240,240,240)
minBtn.AutoButtonColor = false
minBtn.ZIndex = 12
minBtn.Parent = panel
local mbc = Instance.new("UICorner", minBtn); mbc.CornerRadius = UDim.new(1,0)

-- Scrollable + layout
local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.BackgroundTransparency = 1
content.Position = UDim2.fromOffset(0, 44)
content.Size = UDim2.new(1, 0, 1, -44)
content.ScrollBarThickness = 8
content.ScrollingDirection = Enum.ScrollingDirection.Y
content.CanvasSize = UDim2.fromOffset(0, 0)
content.ZIndex = 10
content.Parent = panel

local vlist = Instance.new("UIListLayout", content)
vlist.Padding = UDim.new(0, 10)
vlist.SortOrder = Enum.SortOrder.LayoutOrder
local function recalcCanvas()
    content.CanvasSize = UDim2.fromOffset(0, vlist.AbsoluteContentSize.Y + 10)
end
vlist:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(recalcCanvas)

-- Row helper (autosize Y)
local function makeRow()
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.Size = UDim2.new(1, -20, 0, 0)
    row.Position = UDim2.fromOffset(10, 0)
    row.Parent = content

    local top = Instance.new("Frame")
    top.BackgroundTransparency = 1
    top.Size = UDim2.new(1, 0, 0, 36)
    top.Parent = row

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -230, 1, 0)
    label.Position = UDim2.fromOffset(10, 0)
    label.Font = Enum.Font.Gotham
    label.TextSize = 16
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(220,220,220)
    label.Text = ""
    label.Parent = top

    local extra = Instance.new("Frame")
    extra.BackgroundTransparency = 1
    extra.Size = UDim2.new(1, 0, 0, 0)
    extra.Parent = row

    local rowList = Instance.new("UIListLayout", row)
    rowList.FillDirection = Enum.FillDirection.Vertical
    rowList.SortOrder = Enum.SortOrder.LayoutOrder
    rowList.Padding = UDim.new(0, 6)

    return row, top, label, extra
end

-- ESP row
local rowESP, espTop, espLabel, espExtra = makeRow()
espLabel.Text = "ESP"

local espToggle = Instance.new("TextButton")
espToggle.Size = UDim2.fromOffset(90, 32)
espToggle.Position = UDim2.new(1, -200, 0.5, -16)
espToggle.BackgroundColor3 = Color3.fromRGB(90,190,110)
espToggle.Font = Enum.Font.GothamBold
espToggle.TextSize = 14
espToggle.TextColor3 = Color3.fromRGB(255,255,255)
espToggle.Text = "On"
espToggle.AutoButtonColor = false
espToggle.Parent = espTop
Instance.new("UICorner", espToggle).CornerRadius = UDim.new(0,10)

local colorBtn = Instance.new("TextButton")
colorBtn.Size = UDim2.fromOffset(90, 32)
colorBtn.Position = UDim2.new(1, -100, 0.5, -16)
colorBtn.BackgroundColor3 = STATE.EspColor
colorBtn.Font = Enum.Font.GothamBold
colorBtn.TextSize = 14
colorBtn.TextColor3 = Color3.fromRGB(20,20,20)
colorBtn.Text = "Color"
colorBtn.AutoButtonColor = false
colorBtn.Parent = espTop
Instance.new("UICorner", colorBtn).CornerRadius = UDim.new(0,10)

-- Palette (Color picker)
local PALETTE_H = 72
local palette = Instance.new("Frame")
palette.Size = UDim2.new(1, -20, 0, PALETTE_H)
palette.Position = UDim2.fromOffset(10, 0)
palette.BackgroundColor3 = Color3.fromRGB(26,28,34)
palette.Visible = false
palette.Parent = espExtra
palette.ZIndex = 20
local palCorner = Instance.new("UICorner", palette); palCorner.CornerRadius = UDim.new(0,10)

local grid = Instance.new("UIGridLayout", palette)
grid.CellSize = UDim2.fromOffset(42, 26)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.FillDirectionMaxCells = 4
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Center

local colors = {
    Color3.fromRGB(255,255,255), Color3.fromRGB(255,0,0),
    Color3.fromRGB(0,255,0),     Color3.fromRGB(0,170,255),
    Color3.fromRGB(255,170,0),   Color3.fromRGB(170,0,255),
    Color3.fromRGB(255,0,170),   Color3.fromRGB(255,255,0),
}
for _, col in ipairs(colors) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(42, 26)
    b.BackgroundColor3 = col
    b.Text = ""
    b.AutoButtonColor = false
    b.Parent = palette
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
    b.MouseButton1Click:Connect(function()
        STATE.EspColor = col
        colorBtn.BackgroundColor3 = col
        for _, hl in pairs(HLS) do applyHL(hl) end
        palette.Visible = false
        espExtra.Size = UDim2.new(1, 0, 0, 0)
        recalcCanvas()
    end)
end

-- Palette ac/kapa
colorBtn.MouseButton1Click:Connect(function()
    local show = not palette.Visible
    palette.Visible = show
    espExtra.Size = show and UDim2.new(1, 0, 0, PALETTE_H) or UDim2.new(1, 0, 0, 0)
    recalcCanvas()
end)

-- Paletin disina tiklayinca kapanir
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if palette.Visible and input.UserInputType == Enum.UserInputType.MouseButton1 then
        local pos = input.Position
        local inPal = pos.X>=palette.AbsolutePosition.X and pos.X<=palette.AbsolutePosition.X+palette.AbsoluteSize.X
            and pos.Y>=palette.AbsolutePosition.Y and pos.Y<=palette.AbsolutePosition.Y+palette.AbsoluteSize.Y
        local inBtn = pos.X>=colorBtn.AbsolutePosition.X and pos.X<=colorBtn.AbsolutePosition.X+colorBtn.AbsoluteSize.X
            and pos.Y>=colorBtn.AbsolutePosition.Y and pos.Y<=colorBtn.AbsolutePosition.Y+colorBtn.AbsoluteSize.Y
        if not inPal and not inBtn then
            palette.Visible = false
            espExtra.Size = UDim2.new(1, 0, 0, 0)
            recalcCanvas()
        end
    end
end)

local function setEspVis()
    if STATE.EspEnabled then
        espToggle.Text = "On"; tween(espToggle, {BackgroundColor3=Color3.fromRGB(90,190,110)}, 0.12)
    else
        espToggle.Text = "Off"; tween(espToggle, {BackgroundColor3=Color3.fromRGB(90,90,100)}, 0.12)
    end
end
setEspVis()

espToggle.MouseButton1Click:Connect(function()
    STATE.EspEnabled = not STATE.EspEnabled
    setEspVis()
    refreshAllHL()
end)

-- Fly row
local rowFly, flyTop, flyLabel = makeRow()
flyLabel.Text = "Fly"

local flyToggle = Instance.new("TextButton")
flyToggle.Size = UDim2.fromOffset(90, 32)
flyToggle.Position = UDim2.new(1, -100, 0.5, -16)
flyToggle.BackgroundColor3 = Color3.fromRGB(90,90,100)
flyToggle.Font = Enum.Font.GothamBold
flyToggle.TextSize = 14
flyToggle.TextColor3 = Color3.fromRGB(255,255,255)
flyToggle.Text = "Off"
flyToggle.AutoButtonColor = false
flyToggle.Parent = flyTop
Instance.new("UICorner", flyToggle).CornerRadius = UDim.new(0,10)

local function setFlyVis()
    if STATE.FlyEnabled then
        flyToggle.Text="On"; tween(flyToggle,{BackgroundColor3=Color3.fromRGB(90,190,110)},0.12)
    else
        flyToggle.Text="Off"; tween(flyToggle,{BackgroundColor3=Color3.fromRGB(90,90,100)},0.12)
    end
end
setFlyVis()

flyToggle.MouseButton1Click:Connect(function()
    STATE.FlyEnabled = not STATE.FlyEnabled
    setFlyVis()
    if STATE.FlyEnabled then _G.__CNRST_StartFly() else _G.__CNRST_StopFly() end
end)

-- Speed row
local rowSpeed, spTop, spLabel = makeRow()
spLabel.Text = "Speed"

local speedLbl = Instance.new("TextLabel")
speedLbl.BackgroundTransparency = 1
speedLbl.Size = UDim2.fromOffset(100, 20)
speedLbl.Position = UDim2.new(1, -100, 0.5, -10)
speedLbl.Font = Enum.Font.GothamBold
speedLbl.TextSize = 14
speedLbl.TextXAlignment = Enum.TextXAlignment.Right
speedLbl.TextColor3 = Color3.fromRGB(220,220,220)
speedLbl.Text = tostring(STATE.FlySpeed)
speedLbl.Parent = spTop

local slider = Instance.new("Frame")
slider.BackgroundColor3 = Color3.fromRGB(60,65,80)
slider.Parent = spTop
Instance.new("UICorner", slider).CornerRadius = UDim.new(0,3)

local knob = Instance.new("Frame")
knob.Size = UDim2.fromOffset(14,14)
knob.Position = UDim2.fromOffset(0,-4)
knob.BackgroundColor3 = Color3.fromRGB(90,190,110)
knob.Parent = slider
Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)

local function layoutSpeedBar()
    local txtW = TextService:GetTextSize(spLabel.Text, 16, Enum.Font.Gotham, Vector2.new(1000,1000)).X
    local leftPad = 10 + txtW + 16
    local rightPad = 100 + 16
    slider.Position = UDim2.new(0, leftPad, 0.5, -3)
    slider.Size     = UDim2.new(1, -(leftPad + rightPad), 0, 6)
end

local SL_MIN, SL_MAX = 50, 1000
local dragging = false
local function setKnobFromSpeed()
    local w = slider.AbsoluteSize.X
    local r = (STATE.FlySpeed - SL_MIN)/(SL_MAX - SL_MIN)
    knob.Position = UDim2.fromOffset(math.clamp(r,0,1)*w - knob.AbsoluteSize.X/2, -4)
    speedLbl.Text = tostring(STATE.FlySpeed)
end
local function setSpeedFromX(x)
    local w = slider.AbsoluteSize.X
    local r = math.clamp(x / w, 0, 1)
    STATE.FlySpeed = math.floor(SL_MIN + r*(SL_MAX - SL_MIN))
    setKnobFromSpeed()
end

slider.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging = true
        setSpeedFromX(i.Position.X - slider.AbsolutePosition.X)
    end
end)
slider.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        setSpeedFromX(i.Position.X - slider.AbsolutePosition.X)
    end
end)
spTop:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    layoutSpeedBar(); setKnobFromSpeed()
end)
speedLbl:GetPropertyChangedSignal("Text"):Connect(layoutSpeedBar)
layoutSpeedBar(); setKnobFromSpeed()

-- Noclip row
local rowNoclip, ncTop, ncLabel = makeRow()
ncLabel.Text = "Noclip"

local noclipToggle = Instance.new("TextButton")
noclipToggle.Size = UDim2.fromOffset(90, 32)
noclipToggle.Position = UDim2.new(1, -100, 0.5, -16)
noclipToggle.BackgroundColor3 = Color3.fromRGB(90,90,100)
noclipToggle.Font = Enum.Font.GothamBold
noclipToggle.TextSize = 14
noclipToggle.TextColor3 = Color3.fromRGB(255,255,255)
noclipToggle.Text = "Off"
noclipToggle.AutoButtonColor = false
noclipToggle.Parent = ncTop
Instance.new("UICorner", noclipToggle).CornerRadius = UDim.new(0,10)

local function setNoclipVis()
    if STATE.NoclipEnabled then
        noclipToggle.Text = "On"; tween(noclipToggle, {BackgroundColor3=Color3.fromRGB(90,190,110)}, 0.12)
    else
        noclipToggle.Text = "Off"; tween(noclipToggle, {BackgroundColor3=Color3.fromRGB(90,90,100)}, 0.12)
    end
end
setNoclipVis()

noclipToggle.MouseButton1Click:Connect(function()
    STATE.NoclipEnabled = not STATE.NoclipEnabled
    setNoclipVis()
    if STATE.NoclipEnabled then _G.__CNRST_EnableNoclip() else _G.__CNRST_DisableNoclip() end
end)

-- Aimbot row
local rowAim, aimTop, aimLabel = makeRow()
aimLabel.Text = "Aimbot"

local aimToggle = Instance.new("TextButton")
aimToggle.Size = UDim2.fromOffset(90, 32)
aimToggle.Position = UDim2.new(1, -100, 0.5, -16)
aimToggle.BackgroundColor3 = Color3.fromRGB(90,90,100)
aimToggle.Font = Enum.Font.GothamBold
aimToggle.TextSize = 14
aimToggle.TextColor3 = Color3.fromRGB(255,255,255)
aimToggle.Text = "Off"
aimToggle.AutoButtonColor = false
aimToggle.Parent = aimTop
Instance.new("UICorner", aimToggle).CornerRadius = UDim.new(0,10)

local function setAimVis()
    if STATE.AimbotEnabled then
        aimToggle.Text = "On"; tween(aimToggle, {BackgroundColor3=Color3.fromRGB(90,190,110)}, 0.12)
    else
        aimToggle.Text = "Off"; tween(aimToggle, {BackgroundColor3=Color3.fromRGB(90,90,100)}, 0.12)
    end
end
setAimVis()

aimToggle.MouseButton1Click:Connect(function()
    STATE.AimbotEnabled = not STATE.AimbotEnabled
    setAimVis()
end)

-- Unlock Cam (FPS) row
local rowFPS, fpsTop, fpsLabel = makeRow()
fpsLabel.Text = "Unlock Cam (FPS)"

local fpsToggle = Instance.new("TextButton")
fpsToggle.Size = UDim2.fromOffset(90, 32)
fpsToggle.Position = UDim2.new(1, -100, 0.5, -16)
fpsToggle.BackgroundColor3 = Color3.fromRGB(90,90,100)
fpsToggle.Font = Enum.Font.GothamBold
fpsToggle.TextSize = 14
fpsToggle.TextColor3 = Color3.fromRGB(255,255,255)
fpsToggle.Text = "Off"
fpsToggle.AutoButtonColor = false
fpsToggle.Parent = fpsTop
-- CRITICAL FIX: UDim.new (dogrusu), eskiden UDim.New yazilinca runtime error yapiyordu
Instance.new("UICorner", fpsToggle).CornerRadius = UDim.new(0,10)

local function setFpsVis()
    if STATE.UnlockCamEnabled then
        fpsToggle.Text = "On"; tween(fpsToggle, {BackgroundColor3=Color3.fromRGB(90,190,110)}, 0.12)
    else
        fpsToggle.Text = "Off"; tween(fpsToggle, {BackgroundColor3=Color3.fromRGB(90,90,100)}, 0.12)
    end
end
setFpsVis()

fpsToggle.MouseButton1Click:Connect(function()
    STATE.UnlockCamEnabled = not STATE.UnlockCamEnabled
    setFpsVis()
    if _G.__CNRST_SetUnlockCam then _G.__CNRST_SetUnlockCam(STATE.UnlockCamEnabled) end
end)

-- Minimize + Insert/Home
local isMin = false
local function miniSize() return UDim2.fromOffset(220, 56) end

local function toggleMinimize()
    isMin = not isMin
    if isMin then
        content.Visible = false
        tween(panel, {Size = miniSize()}, 0.15)
    else
        tween(panel, {Size = UDim2.fromOffset(360, 360)}, 0.15)
        task.delay(0.16, function() if panel.Parent then content.Visible = true end end)
    end
end

local function forceMouseFree()
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true
end

minBtn.MouseButton1Click:Connect(function()
    toggleMinimize()
end)

UserInputService.InputBegan:Connect(function(i)
    if i.KeyCode == Enum.KeyCode.Insert then
        toggleMinimize()
    elseif i.KeyCode == Enum.KeyCode.Home then
        forceMouseFree()
    end
end)
