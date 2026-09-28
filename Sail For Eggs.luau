--[[
    EggListGui.lua (v5 - GUI Settings & Lift Before Teleport - Cleaned)
    วาง Script นี้เป็น LocalScript ไว้ใน StarterPlayer > StarterPlayerScripts
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG: Path และการตั้งค่าต่าง ๆ
----------------------------------------------------------------
local CONFIG = {
    WorldsPath = {"Terrain", "World", "Main", "Worlds"},
    SafeZonePath = {"Terrain", "World", "Zones", "Safe"},
    SpawnedEggsName = "SpawnedEggs",
    NameAttribute = "EggName",
    ImageAttribute = "EggImage",
    DefaultImage = "rbxasset://textures/ui/GuiImagePlaceholder.png",
    DedupeRadius = 8,
    ScanInterval = 1,
    WindowTitle = "รายการไข่ทั้งหมด",
    
    -- ตั้งค่าการวาป
    UseTweenTeleport = true,
    TeleportSpeed = 150,     -- ค่าเริ่มต้น (เปลี่ยนผ่าน GUI ได้)
    LiftHeight = 50,         -- ความสูงที่ยกตัวขึ้นก่อนวาป (Studs)
}

local isTeleporting = false -- ป้องกันการกดวาปรัว ๆ

----------------------------------------------------------------
-- หา Folder ต่าง ๆ
----------------------------------------------------------------
local worldsFolder = workspace
for _, name in ipairs(CONFIG.WorldsPath) do
    worldsFolder = worldsFolder:WaitForChild(name)
end

local function getSafeCFrame()
    local current = workspace
    for _, name in ipairs(CONFIG.SafeZonePath) do
        current = current:FindFirstChild(name)
        if not current then return nil end
    end
    if current:IsA("BasePart") then return current.CFrame
    elseif current:IsA("Model") then return current:GetPivot() end
    return nil
end

----------------------------------------------------------------
-- ฟังก์ชันเทเลพอร์ตผู้เล่น: ยกตัว -> บินไปเป้าหมาย -> ลดตัวลง
----------------------------------------------------------------
local function teleportTo(targetCFrame)
    if isTeleporting then return end
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    
    if hrp and targetCFrame then
        isTeleporting = true
        local startPos = hrp.CFrame
        local endPos = targetCFrame * CFrame.new(0, 3, 0)
        
        if CONFIG.UseTweenTeleport then
            local originalAnchor = hrp.Anchored
            hrp.Anchored = true
            
            -- 1. ยกตัวขึ้นเหนือพื้น
            local liftCFrame = startPos + Vector3.new(0, CONFIG.LiftHeight, 0)
            local liftTween = TweenService:Create(hrp, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {CFrame = liftCFrame})
            liftTween:Play()
            liftTween.Completed:Wait() -- รอจนกว่าจะยกตัวเสร็จ
            
            -- 2. บินไปยังจุดหมาย (บนอากาศ)
            local targetHighCFrame = endPos + Vector3.new(0, CONFIG.LiftHeight, 0)
            local dist = (liftCFrame.Position - targetHighCFrame.Position).Magnitude
            local flyTime = dist / CONFIG.TeleportSpeed
            
            local flyTween = TweenService:Create(hrp, TweenInfo.new(flyTime, Enum.EasingStyle.Linear), {CFrame = targetHighCFrame})
            flyTween:Play()
            flyTween.Completed:Wait()
            
            -- 3. ลดตัวลงพื้น
            local dropTween = TweenService:Create(hrp, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {CFrame = endPos})
            dropTween:Play()
            dropTween.Completed:Wait()
            
            hrp.Anchored = originalAnchor
        else
            hrp.CFrame = endPos
        end
        
        isTeleporting = false
    end
end

----------------------------------------------------------------
-- สร้าง ScreenGui + หน้าต่างหลัก
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EggListGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 360, 0, 460)
mainFrame.Position = UDim2.new(0.5, -180, 0.5, -230)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

-- TopBar
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 48)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 12)
topCorner.Parent = topBar

local topBarFix = Instance.new("Frame")
topBarFix.Size = UDim2.new(1, 0, 0, 12)
topBarFix.Position = UDim2.new(0, 0, 1, -12)
topBarFix.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
topBarFix.BorderSizePixel = 0
topBarFix.Parent = topBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.Size = UDim2.new(0, 130, 1, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = CONFIG.WindowTitle
titleLabel.Parent = topBar

-- ปุ่มปิด
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.Position = UDim2.new(1, -40, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 14
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Parent = topBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

-- ปุ่มกลับ Safe Zone (ต้องครอบด้วย task.spawn เพราะ teleportTo ตอนนี้ถูกสั่งให้ Wait() เป็นจังหวะ)
local safeBtn = Instance.new("TextButton")
safeBtn.Name = "SafeButton"
safeBtn.Size = UDim2.new(0, 100, 0, 32)
safeBtn.Position = UDim2.new(1, -145, 0, 8)
safeBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 200)
safeBtn.Text = "🏠 Safe Zone"
safeBtn.Font = Enum.Font.GothamBold
safeBtn.TextSize = 12
safeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
safeBtn.Parent = topBar

local safeCorner = Instance.new("UICorner")
safeCorner.CornerRadius = UDim.new(0, 8)
safeCorner.Parent = safeBtn

safeBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        local safeCF = getSafeCFrame()
        if safeCF then
            teleportTo(safeCF)
        else
            warn("[EggListGui] ไม่พบจุด Safe Zone")
        end
    end)
end)

----------------------------------------------------------------
-- แถบตั้งค่า GUI (สำหรับความเร็ว)
----------------------------------------------------------------
local settingsBar = Instance.new("Frame")
settingsBar.Name = "SettingsBar"
settingsBar.Size = UDim2.new(1, 0, 0, 36)
settingsBar.Position = UDim2.new(0, 0, 0, 48)
settingsBar.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
settingsBar.BorderSizePixel = 0
settingsBar.Parent = mainFrame

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.BackgroundTransparency = 1
speedLabel.Position = UDim2.new(0, 16, 0, 0)
speedLabel.Size = UDim2.new(0, 100, 1, 0)
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextSize = 13
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Text = "ความเร็วบิน (Studs/s):"
speedLabel.Parent = settingsBar

local speedBox = Instance.new("TextBox")
speedBox.Name = "SpeedBox"
speedBox.Size = UDim2.new(0, 60, 0, 24)
speedBox.Position = UDim2.new(0, 140, 0.5, -12)
speedBox.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.Font = Enum.Font.Gotham
speedBox.TextSize = 13
speedBox.Text = tostring(CONFIG.TeleportSpeed)
speedBox.Parent = settingsBar

local speedCorner = Instance.new("UICorner")
speedCorner.CornerRadius = UDim.new(0, 6)
speedCorner.Parent = speedBox

-- อัปเดตค่าความเร็วเมื่อพิมพ์เสร็จ
speedBox.FocusLost:Connect(function()
    local newSpeed = tonumber(speedBox.Text)
    if newSpeed and newSpeed > 0 then
        CONFIG.TeleportSpeed = newSpeed
    else
        speedBox.Text = tostring(CONFIG.TeleportSpeed)
    end
end)

----------------------------------------------------------------
-- ช่องแสดงรายการไข่ (ปรับตำแหน่งลงมาหลบ SettingsBar)
----------------------------------------------------------------
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name = "EggList"
scrollFrame.Position = UDim2.new(0, 8, 0, 88)
scrollFrame.Size = UDim2.new(1, -16, 1, -96)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 6
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 4)
listPadding.PaddingBottom = UDim.new(0, 4)
listPadding.Parent = scrollFrame

-- ปุ่มลอย เปิด/ปิดหน้าต่าง
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.new(0, 50, 0, 50)
toggleButton.Position = UDim2.new(1, -66, 1, -66)
toggleButton.BackgroundColor3 = Color3.fromRGB(45, 130, 90)
toggleButton.Text = "🥚"
toggleButton.TextSize = 24
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(1, 0)
toggleCorner.Parent = toggleButton

toggleButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = not mainFrame.Visible
end)

----------------------------------------------------------------
-- ฟังก์ชันช่วยอ่านข้อมูลไข่
----------------------------------------------------------------
local function getEggPart(eggInstance)
    local root = eggInstance:FindFirstChild("Root")
    if root then
        if root:IsA("BasePart") then return root end
        local prim = root:IsA("Model") and root.PrimaryPart
        if prim then return prim end
        local anyPart = root:FindFirstChildWhichIsA("BasePart", true)
        if anyPart then return anyPart end
    end
    if eggInstance:IsA("BasePart") then return eggInstance end
    if eggInstance:IsA("Model") then return eggInstance.PrimaryPart or eggInstance:FindFirstChildWhichIsA("BasePart", true) end
    return nil
end

local function getEggName(eggInstance)
    local n = eggInstance:GetAttribute(CONFIG.NameAttribute)
    if n and n ~= "" then return tostring(n) end
    local root = eggInstance:FindFirstChild("Root")
    if root then
        local n2 = root:GetAttribute(CONFIG.NameAttribute)
        if n2 and n2 ~= "" then return tostring(n2) end
        local prompt = root:FindFirstChild("InteractionPromptAttachment", true)
        if prompt then
            local ip = prompt:FindFirstChild("InteractionPrompt")
            if ip and ip:IsA("ProximityPrompt") and ip.ObjectText ~= "" then return ip.ObjectText end
        end
    end
    return eggInstance.Name
end

local function getEggImage(eggInstance)
    local img = eggInstance:GetAttribute(CONFIG.ImageAttribute)
    if img == nil or img == "" then
        local root = eggInstance:FindFirstChild("Root")
        if root then img = root:GetAttribute(CONFIG.ImageAttribute) end
    end
    
    if img == nil or img == "" then
        local part = getEggPart(eggInstance)
        if part then
            if part:IsA("MeshPart") and part.TextureID ~= "" then img = part.TextureID
            else
                local decal = part:FindFirstChildWhichIsA("Decal") or part:FindFirstChildWhichIsA("Texture")
                if decal then img = decal.Texture end
            end
        end
    end

    if img == nil or img == "" then return CONFIG.DefaultImage end
    if type(img) == "number" then return "rbxassetid://" .. tostring(img) end
    img = tostring(img)
    if img:match("^rbxassetid://") or img:match("^rbxasset://") or img:match("^http") then return img end
    if img:match("^%d+$") then return "rbxassetid://" .. img end
    
    return CONFIG.DefaultImage
end

----------------------------------------------------------------
-- สแกนไข่จากทุก World แล้ว dedupe
----------------------------------------------------------------
local function scanAllEggs()
    local rawEggs = {}
    for _, world in ipairs(worldsFolder:GetChildren()) do
        local spawnedEggs = world:FindFirstChild(CONFIG.SpawnedEggsName)
        if spawnedEggs then
            for _, eggInstance in ipairs(spawnedEggs:GetChildren()) do
                local part = getEggPart(eggInstance)
                if part then
                    table.insert(rawEggs, { instance = eggInstance, position = part.Position })
                end
            end
        end
    end

    local groups = {}
    for _, eggData in ipairs(rawEggs) do
        local placed = false
        for _, group in ipairs(groups) do
            if (group.position - eggData.position).Magnitude <= CONFIG.DedupeRadius then
                table.insert(group.members, eggData.instance)
                placed = true
                break
            end
        end
        if not placed then
            table.insert(groups, { position = eggData.position, members = {eggData.instance} })
        end
    end
    return groups
end

----------------------------------------------------------------
-- สร้าง/อัปเดต แถวรายการไข่
----------------------------------------------------------------
local entryPool = {}

local function getOrCreateEntry(index)
    local e = entryPool[index]
    if e then return e end

    local entry = Instance.new("Frame")
    entry.Name = "Entry_" .. index
    entry.LayoutOrder = index
    entry.Size = UDim2.new(1, 0, 0, 64)
    entry.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
    entry.BorderSizePixel = 0
    entry.Parent = scrollFrame

    local entryCorner = Instance.new("UICorner")
    entryCorner.CornerRadius = UDim.new(0, 8)
    entryCorner.Parent = entry

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 48, 0, 48)
    icon.Position = UDim2.new(0, 8, 0, 8)
    icon.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Parent = entry

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0, 6)
    iconCorner.Parent = icon

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0, 64, 0, 6)
    nameLabel.Size = UDim2.new(1, -145, 0, 24)
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.TextSize = 15
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = entry

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.BackgroundTransparency = 1
    distLabel.Position = UDim2.new(0, 64, 0, 32)
    distLabel.Size = UDim2.new(1, -145, 0, 20)
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = 12
    distLabel.TextColor3 = Color3.fromRGB(160, 200, 170)
    distLabel.TextXAlignment = Enum.TextXAlignment.Left
    distLabel.Parent = entry

    local tpBtn = Instance.new("TextButton")
    tpBtn.Name = "TPButton"
    tpBtn.Size = UDim2.new(0, 65, 0, 36)
    tpBtn.Position = UDim2.new(1, -73, 0.5, -18)
    tpBtn.BackgroundColor3 = Color3.fromRGB(45, 160, 95)
    tpBtn.Text = "วาปเก็บ"
    tpBtn.Font = Enum.Font.GothamBold
    tpBtn.TextSize = 12
    tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    tpBtn.Parent = entry

    local tpCorner = Instance.new("UICorner")
    tpCorner.CornerRadius = UDim.new(0, 6)
    tpCorner.Parent = tpBtn

    e = {frame = entry, icon = icon, nameLabel = nameLabel, distLabel = distLabel, tpBtn = tpBtn, connection = nil}
    entryPool[index] = e
    return e
end

local function hideUnusedEntries(fromIndex)
    for i, e in pairs(entryPool) do
        if i >= fromIndex then e.frame.Visible = false end
    end
end

local function formatDistance(dist)
    if dist == nil then return "-" end
    return string.format("%.0f studs", dist)
end

----------------------------------------------------------------
-- Loop หลัก
----------------------------------------------------------------
local running = true

local function refresh()
    local groups = scanAllEggs()

    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")

    for i, group in ipairs(groups) do
        local e = getOrCreateEntry(i)
        e.frame.Visible = true

        local representative = group.members[1]
        e.nameLabel.Text = getEggName(representative)
        e.icon.Image = getEggImage(representative)

        if hrp then
            local dist = (hrp.Position - group.position).Magnitude
            e.distLabel.Text = formatDistance(dist) .. (#group.members > 1 and (" • " .. #group.members .. " W") or "")
        else
            e.distLabel.Text = #group.members > 1 and (#group.members .. " Worlds") or ""
        end

        if e.connection then e.connection:Disconnect() end

        e.connection = e.tpBtn.MouseButton1Click:Connect(function()
            -- ใช้ task.spawn เพื่อแยกการทำงานเพราะฟังก์ชันวาปมีการ Wait()
            task.spawn(function()
                teleportTo(CFrame.new(group.position))
                
                -- สั่งกด ProximityPrompt เมื่อถึงเป้าหมายและลดตัวลงพื้นเสร็จแล้ว
                for _, eggInst in ipairs(group.members) do
                    local prompt = eggInst:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and fireproximityprompt then
                        fireproximityprompt(prompt)
                    end
                end
            end)
        end)
    end

    hideUnusedEntries(#groups + 1)
end

task.spawn(function()
    while running do
        local ok, err = pcall(refresh)
        if not ok then warn("[EggListGui] refresh error:", err) end
        task.wait(CONFIG.ScanInterval)
    end
end)

closeButton.MouseButton1Click:Connect(function()
    running = false
    screenGui:Destroy()
end)