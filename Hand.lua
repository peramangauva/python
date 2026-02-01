-- Global cleanup
if getgenv().HandScriptConnection then
    getgenv().HandScriptConnection:Disconnect()
    getgenv().HandScriptConnection = nil
end
if getgenv().HandGUI then
    getgenv().HandGUI:Destroy()
    getgenv().HandGUI = nil
end

-- Services
local HttpService = game:GetService('HttpService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local Workspace = game:GetService('Workspace')
local UserInputService = game:GetService('UserInputService')
local CoreGui = game:GetService('CoreGui')

-- Constants
local PORT = 'http://127.0.0.1:5000/webcam'
local ME = Players.LocalPlayer

-- // JOINT ORDER: Thumb -> Pinky -> Wrist //
local JOINT_ORDER = {}
local FINGER_NAMES = { "Thumb", "Index", "Middle", "Ring", "Pinky" }

for _, finger in ipairs(FINGER_NAMES) do
    for i = 1, 4 do
        table.insert(JOINT_ORDER, finger .. "_" .. i)
    end
end
table.insert(JOINT_ORDER, "Wrist") 

-- Configuration
local Config = {
    Scale = 60,
    Sensitivity = 200,
    OffsetX = 0,
    OffsetY = 245,
    OffsetZ = 7,
    InvertedX = false,
    Paused = false,
    
    -- Colors: Start 160. Cycle B 160->165 (6 steps). Then Reset B, Inc G.
    Colors = {
        ["Thumb_1"]   = Color3.fromRGB(160, 160, 160),
        ["Thumb_2"]   = Color3.fromRGB(160, 160, 161),
        ["Thumb_3"]   = Color3.fromRGB(160, 160, 162),
        ["Thumb_4"]   = Color3.fromRGB(160, 160, 163),
        
        ["Index_1"]   = Color3.fromRGB(160, 160, 164),
        ["Index_2"]   = Color3.fromRGB(160, 160, 165),
        ["Index_3"]   = Color3.fromRGB(160, 161, 160),
        ["Index_4"]   = Color3.fromRGB(160, 161, 161),
        
        ["Middle_1"]  = Color3.fromRGB(160, 161, 162),
        ["Middle_2"]  = Color3.fromRGB(160, 161, 163),
        ["Middle_3"]  = Color3.fromRGB(160, 161, 164),
        ["Middle_4"]  = Color3.fromRGB(160, 161, 165),
        
        ["Ring_1"]    = Color3.fromRGB(160, 162, 160),
        ["Ring_2"]    = Color3.fromRGB(160, 162, 161),
        ["Ring_3"]    = Color3.fromRGB(160, 162, 162),
        ["Ring_4"]    = Color3.fromRGB(160, 162, 163),
        
        ["Pinky_1"]   = Color3.fromRGB(160, 162, 164),
        ["Pinky_2"]   = Color3.fromRGB(160, 162, 165),
        ["Pinky_3"]   = Color3.fromRGB(160, 163, 160),
        ["Pinky_4"]   = Color3.fromRGB(160, 163, 161),
        
        ["Wrist"]     = Color3.fromRGB(160, 163, 162)
    }
}

-- State
local currentAircraft = nil
local activeParts = {} 

--------------------------------------------------------------------------------
-- Logic Helper Functions
--------------------------------------------------------------------------------

local function cleanupPart(part)
    if not part then return end
    local bp = part:FindFirstChild("HandBP")
    local bg = part:FindFirstChild("HandBG")
    if bp then bp:Destroy() end
    if bg then bg:Destroy() end
end

local function fullCleanup()
    if getgenv().HandScriptConnection then
        getgenv().HandScriptConnection:Disconnect()
        getgenv().HandScriptConnection = nil
    end
    for _, part in pairs(activeParts) do cleanupPart(part) end
    activeParts = {}
    currentAircraft = nil
    if getgenv().HandGUI then
        getgenv().HandGUI:Destroy()
        getgenv().HandGUI = nil
    end
end

local function areColorsSimilar(c1, c2)
    local diff = math.abs(c1.R - c2.R) + math.abs(c1.G - c2.G) + math.abs(c1.B - c2.B)
    return diff < 0.002
end

local function scanAircraft()
    if not currentAircraft then return {} end
    local found = {}
    local usedPartsSet = {} -- To track used parts for collision logic
    
    local descendants = currentAircraft:GetDescendants()
    
    -- 1. Identify Hand Parts
    for _, part in ipairs(descendants) do
        if part:IsA("BasePart") then
            for jointName, targetColor in pairs(Config.Colors) do
                if areColorsSimilar(part.Color, targetColor) then
                    found[jointName] = part
                    usedPartsSet[part] = true
                    
                    -- Setup Physics for Hand Parts
                    part.CanCollide = true 
                    part.Anchored = false
                    
                    local bp = part:FindFirstChild("HandBP") or Instance.new("BodyPosition")
                    bp.Name = "HandBP"
                    bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    bp.D = 1000
                    bp.P = 100000
                    bp.Parent = part
                    
                    local bg = part:FindFirstChild("HandBG") or Instance.new("BodyGyro")
                    bg.Name = "HandBG"
                    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                    bg.D = 750
                    bg.P = 35000
                    bg.Parent = part
                    
                    break -- Found a match, move to next part
                end
            end
        end
    end

    -- 2. Disable Collision for Unused Parts
    for _, part in ipairs(descendants) do
        if part:IsA("BasePart") and not usedPartsSet[part] then
            part.CanCollide = false
        end
    end
    
    return found
end

--------------------------------------------------------------------------------
-- MegaHack-like GUI Construction
--------------------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HandControlGUI"
ScreenGui.ResetOnSpawn = false
if syn and syn.protect_gui then syn.protect_gui(ScreenGui) ScreenGui.Parent = CoreGui elseif getgenv().gethui then ScreenGui.Parent = getgenv().gethui() else ScreenGui.Parent = CoreGui end
getgenv().HandGUI = ScreenGui

local UI_WIDTH = 320
local HEADER_HEIGHT = 40
local ITEM_HEIGHT = 32

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, UI_WIDTH, 0, 480)
MainFrame.Position = UDim2.new(0.02, 0, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(0, 0, 0)
Stroke.Thickness = 2
Stroke.Parent = MainFrame

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
Header.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Text = "Hand Control v3"
TitleLabel.Size = UDim2.new(1, -10, 1, 0)
TitleLabel.Position = UDim2.new(0, 10, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 16
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT)
ScrollContainer.Position = UDim2.new(0, 0, 0, HEADER_HEIGHT)
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.ScrollBarThickness = 4
ScrollContainer.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
ScrollContainer.Parent = MainFrame

local UIList = Instance.new("UIListLayout")
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Padding = UDim.new(0, 0)
UIList.Parent = ScrollContainer

-- UI Components
local function createSection(text, layoutOrder)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 25)
    Frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    Frame.BorderSizePixel = 0
    Frame.LayoutOrder = layoutOrder
    Frame.Parent = ScrollContainer
    
    local Label = Instance.new("TextLabel")
    Label.Text = text
    Label.Size = UDim2.new(1, -10, 1, 0)
    Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1
    Label.TextColor3 = Color3.fromRGB(150, 150, 150)
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = 11
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame
end

local function createInput(text, configKey, layoutOrder)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, ITEM_HEIGHT)
    Frame.BackgroundTransparency = 1
    Frame.LayoutOrder = layoutOrder
    Frame.Parent = ScrollContainer

    local Label = Instance.new("TextLabel")
    Label.Text = text
    Label.Size = UDim2.new(0.6, 0, 1, 0)
    Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1
    Label.TextColor3 = Color3.fromRGB(220, 220, 220)
    Label.Font = Enum.Font.GothamSemibold
    Label.TextSize = 14
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame

    local TextBox = Instance.new("TextBox")
    TextBox.Text = tostring(Config[configKey])
    TextBox.Size = UDim2.new(0, 60, 0, 22)
    TextBox.Position = UDim2.new(1, -70, 0.5, -11)
    TextBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    TextBox.BorderColor3 = Color3.fromRGB(60, 60, 60)
    TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    TextBox.Font = Enum.Font.Gotham
    TextBox.TextSize = 13
    TextBox.Parent = Frame
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 4)
    Corner.Parent = TextBox

    TextBox.FocusLost:Connect(function()
        local n = tonumber(TextBox.Text)
        if n then Config[configKey] = n else TextBox.Text = tostring(Config[configKey]) end
    end)
end

local function createColorRow(jointName, layoutOrder)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, ITEM_HEIGHT)
    Frame.BackgroundTransparency = 1
    Frame.LayoutOrder = layoutOrder
    Frame.Parent = ScrollContainer

    local Preview = Instance.new("Frame")
    Preview.Size = UDim2.new(0, 10, 0, 10)
    Preview.Position = UDim2.new(0, 10, 0.5, -5)
    Preview.BackgroundColor3 = Config.Colors[jointName]
    Preview.BorderSizePixel = 0
    Preview.Parent = Frame
    local PCorner = Instance.new("UICorner")
    PCorner.CornerRadius = UDim.new(1, 0)
    PCorner.Parent = Preview

    local Label = Instance.new("TextLabel")
    Label.Text = jointName
    Label.Size = UDim2.new(0.5, 0, 1, 0)
    Label.Position = UDim2.new(0, 28, 0, 0)
    Label.BackgroundTransparency = 1
    Label.TextColor3 = Color3.fromRGB(200, 200, 200)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame

    local TextBox = Instance.new("TextBox")
    local c = Config.Colors[jointName]
    TextBox.Text = string.format("%d,%d,%d", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
    TextBox.Size = UDim2.new(0, 80, 0, 22)
    TextBox.Position = UDim2.new(1, -90, 0.5, -11)
    TextBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    TextBox.BorderColor3 = Color3.fromRGB(60, 60, 60)
    TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    TextBox.Font = Enum.Font.Gotham
    TextBox.TextSize = 11
    TextBox.Parent = Frame
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 4)
    Corner.Parent = TextBox

    TextBox.FocusLost:Connect(function()
        local r, g, b = TextBox.Text:match("(%d+),%s*(%d+),%s*(%d+)")
        if r then
            local newC = Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
            Config.Colors[jointName] = newC
            Preview.BackgroundColor3 = newC
            if currentAircraft then activeParts = scanAircraft() end
        end
    end)
end

-- Build Layout
local order = 0
local function inc() order = order + 1 return order end

createSection("CONFIGURATION", inc())
createInput("Scale (Size)", "Scale", inc())
createInput("Sensitivity", "Sensitivity", inc())
createInput("Offset X", "OffsetX", inc())
createInput("Offset Y", "OffsetY", inc())
createInput("Offset Z", "OffsetZ", inc())

createSection("COLOR MAPPING (RGB)", inc())
for _, joint in ipairs(JOINT_ORDER) do
    createColorRow(joint, inc())
end

createSection("ACTIONS", inc())

-- Pause Toggle
local ActionFrame = Instance.new("Frame")
ActionFrame.Size = UDim2.new(1, 0, 0, 40)
ActionFrame.BackgroundTransparency = 1
ActionFrame.LayoutOrder = inc()
ActionFrame.Parent = ScrollContainer

local PauseBtn = Instance.new("TextButton")
PauseBtn.Text = "Running"
PauseBtn.Size = UDim2.new(0.45, 0, 0, 30)
PauseBtn.Position = UDim2.new(0, 10, 0, 5)
PauseBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
PauseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
PauseBtn.Font = Enum.Font.GothamBold
PauseBtn.TextSize = 14
PauseBtn.Parent = ActionFrame
local PCorner = Instance.new("UICorner")
PCorner.CornerRadius = UDim.new(0, 4)
PCorner.Parent = PauseBtn

PauseBtn.MouseButton1Click:Connect(function()
    Config.Paused = not Config.Paused
    if Config.Paused then
        PauseBtn.Text = "Paused"
        PauseBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
    else
        PauseBtn.Text = "Running"
        PauseBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    end
end)

local StopBtn = Instance.new("TextButton")
StopBtn.Text = "Terminate"
StopBtn.Size = UDim2.new(0.45, 0, 0, 30)
StopBtn.Position = UDim2.new(0.5, 5, 0, 5)
StopBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.Font = Enum.Font.GothamBold
StopBtn.TextSize = 14
StopBtn.Parent = ActionFrame
local SCorner = Instance.new("UICorner")
SCorner.CornerRadius = UDim.new(0, 4)
SCorner.Parent = StopBtn
StopBtn.MouseButton1Click:Connect(fullCleanup)

ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, order * 35)

--------------------------------------------------------------------------------
-- Main Loop
--------------------------------------------------------------------------------

local function getHandData()
    local success, response = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(PORT))
    end)
    if success and response and response.data then
        return response.data
    end
    return nil
end

local function rawToVec(dataPoint)
    local x = dataPoint.x
    if Config.InvertedX then x = 1 - x end
    return Vector3.new(x - 0.5, (-dataPoint.y - 0.5), dataPoint.z)
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.Home then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

getgenv().HandScriptConnection = RunService.Heartbeat:Connect(function()
    -- Check Pause
    if Config.Paused then return end

    local aircraftName = ME.Name .. ' Aircraft'
    local found = Workspace:FindFirstChild(aircraftName)
    
    -- Auto-detect / Auto-scan
    if found ~= currentAircraft then
        for _, part in pairs(activeParts) do cleanupPart(part) end
        activeParts = {}
        currentAircraft = found
        if currentAircraft then activeParts = scanAircraft() end
    elseif found and next(activeParts) == nil then
        activeParts = scanAircraft()
    end

    if not currentAircraft then return end

    local character = ME.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    
    local handData = getHandData()
    if not handData then return end

    local rootPart = character.HumanoidRootPart
    local currentOffset = Vector3.new(Config.OffsetX, Config.OffsetY, Config.OffsetZ)
    local originCF = rootPart.CFrame * CFrame.new(currentOffset)
    
    local rawWrist = rawToVec(handData.Wrist)
    local wristWorldPos = originCF:PointToWorldSpace(rawWrist * Config.Sensitivity)

    local targetCFrames = {} 

    local function getScaledPos(rawPoint)
        local vec = rawToVec(rawPoint)
        local delta = vec - rawWrist
        return wristWorldPos + (originCF:VectorToWorldSpace(delta) * Config.Scale) 
    end

    -- Calculations
    local middleBasePos = getScaledPos(handData.Finger3[1]) 
    targetCFrames["Wrist"] = CFrame.lookAt(wristWorldPos, middleBasePos)

    local apiFingerNames = {"Finger1", "Finger2", "Finger3", "Finger4", "Finger5"}
    local logicFingerNames = {"Thumb", "Index", "Middle", "Ring", "Pinky"}

    for fIdx, apiName in ipairs(apiFingerNames) do
        local points = handData[apiName]
        local baseName = logicFingerNames[fIdx]

        if points then
            for i = 1, 4 do
                local jointName = baseName .. "_" .. i
                local currentPos = getScaledPos(points[i])
                local rotation
                if i < 4 then
                    local nextPos = getScaledPos(points[i+1])
                    if (currentPos - nextPos).Magnitude < 0.001 then
                        rotation = CFrame.new(currentPos)
                    else
                        rotation = CFrame.lookAt(currentPos, nextPos)
                    end
                else
                    local prevPos = getScaledPos(points[i-1])
                    if (currentPos - prevPos).Magnitude < 0.001 then
                        rotation = CFrame.new(currentPos)
                    else
                        rotation = CFrame.lookAt(currentPos, currentPos + (currentPos - prevPos))
                    end
                end
                targetCFrames[jointName] = rotation
            end
        end
    end

    -- Apply
    for jointName, targetCFrame in pairs(targetCFrames) do
        local part = activeParts[jointName]
        if part and part.Parent then
            local bp = part:FindFirstChild("HandBP")
            local bg = part:FindFirstChild("HandBG")
            if bp and bg then
                bp.Position = targetCFrame.Position
                bg.CFrame = targetCFrame
            end
        else
            activeParts[jointName] = nil
        end
    end
end)