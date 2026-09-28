local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CONFIG = {
	MinDistance = 8, -- ระยะห่างขั้นต่ำจากตัวผู้เล่นเป้าหมาย (studs) กันวาปทับ
	MaxDistance = 15, -- ระยะห่างสูงสุด
	MaxHeightDifference = 25, -- ต่างระดับพื้นที่ยอมรับได้เทียบกับตำแหน่งเป้าหมาย (studs)
	LandingYOffset = 3, -- ยืนสูงกว่าพื้นเล็กน้อย กันติดพื้น
	MaxAttempts = 20, -- จำนวนครั้งที่ลองหาจุดลงจอดก่อนจะยอมแพ้
	AutoRefreshSeconds = 5, -- รีเฟรชรายชื่อผู้เล่นอัตโนมัติทุกกี่วินาที
	HealthRefreshSeconds = 0.25, -- อัปเดตเลือดที่แสดงใน GUI ทุกกี่วินาที
	SpawnExclusionRadius = 200, -- ถ้าผู้เล่นอยู่ใกล้ Spawn ในระยะนี้ (studs) จะไม่แสดงชื่อในลิสต์
	EspRefreshSeconds = 0.1, -- อัปเดต ESP (เลือด/ชื่อ/ระยะ) ทุกกี่วินาที
	EspMaxDistance = 2000, -- ไกลเกินระยะนี้ (studs) จะไม่แสดง ESP
	EspBoxWidth = 4, -- ความกว้างกรอบ (studs) ที่ตัวละครขนาดปกติ
	EspBoxHeight = 5.5, -- ความสูงกรอบ (studs) ที่ตัวละครขนาดปกติ
	EspBoxYOffset = -0.4, -- ขยับกรอบขึ้น/ลงจาก HumanoidRootPart ให้คลุมตัวพอดี
	EspColor = Color3.fromRGB(255, 70, 70), -- สีกรอบ
}

-- ตำแหน่งจุด Spawn ของล็อบบี้ ใช้เป็นจุดอ้างอิงกรองผู้เล่นที่ยังอยู่แถว Spawn ออกจากลิสต์
local spawnLocation = Workspace:WaitForChild("Lobby"):WaitForChild("SpawnLocation")

-- เก็บ connection ที่ผูกกับ "เซอร์วิส" (ไม่ใช่ผูกกับตัว GUI) ไว้ตรงนี้ เพื่อตัดทิ้งทั้งหมด
-- ตอนกดปิดสคริปต์ ไม่งั้นแม้ลบ GUI ไปแล้วพวกนี้จะยังทำงานค้างอยู่เบื้องหลัง
local activeConnections = {}
local function trackConnection(connection)
	table.insert(activeConnections, connection)
	return connection
end

-- ===================== ลาก GUI ด้วยเมาส์/นิ้ว =====================
local function makeDraggable(guiObject, dragHandle, onClick)
	dragHandle = dragHandle or guiObject

	local dragging = false
	local dragInput
	local dragStart
	local startPos
	local moved = false

	local function update(input)
		local delta = input.Position - dragStart
		guiObject.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
		if delta.Magnitude > 3 then
			moved = true
		end
	end

	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = guiObject.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved and onClick then
						onClick()
					end
				end
			end)
		end
	end)

	dragHandle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	trackConnection(UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			update(input)
		end
	end))
end

-- ===================== หาผู้เล่นที่วาปไปหาได้ =====================
local function getTargetablePlayers()
	local list = {}
	local spawnPosition = spawnLocation.Position

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local character = Workspace:FindFirstChild(otherPlayer.Name)
			local hrp = character and character:FindFirstChild("HumanoidRootPart")

			if hrp then
				local distanceFromSpawn = (hrp.Position - spawnPosition).Magnitude
				if distanceFromSpawn >= CONFIG.SpawnExclusionRadius then
					table.insert(list, { player = otherPlayer, character = character })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.player.Name < b.player.Name
	end)
	return list
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===================== หาจุดลงจอดที่มีพื้นให้ยืน =====================
local groundRaycastParams = RaycastParams.new()
groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function raycastGround(origin, excludeList)
	groundRaycastParams.FilterDescendantsInstances = excludeList or {}
	return Workspace:Raycast(origin, Vector3.new(0, -500, 0), groundRaycastParams)
end

local function findLandingSpot(targetCharacter)
	local targetHRP = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return nil
	end

	local excludeList = { targetCharacter }
	if player.Character then
		table.insert(excludeList, player.Character)
	end

	for _ = 1, CONFIG.MaxAttempts do
		local angle = math.random() * math.pi * 2
		local radius = math.random(CONFIG.MinDistance, CONFIG.MaxDistance)
		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local origin = targetHRP.Position + offset + Vector3.new(0, 50, 0)

		local result = raycastGround(origin, excludeList)
		if result and math.abs(result.Position.Y - targetHRP.Position.Y) <= CONFIG.MaxHeightDifference then
			return result.Position + Vector3.new(0, CONFIG.LandingYOffset, 0)
		end
	end

	return nil
end

-- ===================== การวาปไปหาผู้เล่น =====================
local function teleportToPlayer(entry, statusLabel)
	local myCharacter = player.Character or player.CharacterAdded:Wait()
	local myHRP = myCharacter:FindFirstChild("HumanoidRootPart")
	if not myHRP then
		if statusLabel then statusLabel.Text = "ไม่พบ HumanoidRootPart ของตัวเอง" end
		return
	end

	if not entry.character.Parent then
		if statusLabel then statusLabel.Text = entry.player.Name .. " ไม่อยู่ในเกมแล้ว" end
		return
	end

	local landingPosition = findLandingSpot(entry.character)
	if not landingPosition then
		if statusLabel then statusLabel.Text = "หาจุดยืนใกล้ " .. entry.player.Name .. " ไม่เจอ ลองอีกครั้ง" end
		return
	end

	myHRP.CFrame = CFrame.new(landingPosition)

	if statusLabel then
		statusLabel.Text = "วาปไปหา " .. entry.player.Name .. " แล้ว"
	end
end

-- ===================== การดึงผู้เล่นมาหา =====================
local function bringPlayer(entry, statusLabel)
	local myCharacter = player.Character or player.CharacterAdded:Wait()
	local myHRP = myCharacter:FindFirstChild("HumanoidRootPart")
	if not myHRP then
		if statusLabel then statusLabel.Text = "ไม่พบ HumanoidRootPart ของตัวเอง" end
		return
	end

	if not entry.character.Parent then
		if statusLabel then statusLabel.Text = entry.player.Name .. " ไม่อยู่ในเกมแล้ว" end
		return
	end

	local targetHRP = entry.character:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		if statusLabel then statusLabel.Text = "ไม่พบจุดกึ่งกลางของ " .. entry.player.Name end
		return
	end

	-- ย้าย CFrame ของผู้เล่นอื่นมาด้านหน้าเรา 3 studs
	targetHRP.CFrame = myHRP.CFrame * CFrame.new(0, 0, -3)

	if statusLabel then
		statusLabel.Text = "ดึง " .. entry.player.Name .. " มาหาแล้ว"
	end
end

-- ===================== ระบบเช็คพอย =====================
local checkpointCFrame = nil
local checkpointKeyCode = nil

local DIGIT_KEY_NAMES = {
	["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
	["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine",
}

local function resolveKeyCode(text)
	if not text then return nil end
	local trimmed = text:gsub("%s+", "")
	if trimmed == "" then return nil end

	if DIGIT_KEY_NAMES[trimmed] then return Enum.KeyCode[DIGIT_KEY_NAMES[trimmed]] end

	if #trimmed == 1 then
		local upper = trimmed:upper()
		local ok, keyCode = pcall(function() return Enum.KeyCode[upper] end)
		if ok and keyCode then return keyCode end
	end

	local capitalized = trimmed:sub(1, 1):upper() .. trimmed:sub(2):lower()
	local ok, keyCode = pcall(function() return Enum.KeyCode[capitalized] end)
	if ok and keyCode then return keyCode end

	local ok2, keyCode2 = pcall(function() return Enum.KeyCode[trimmed] end)
	if ok2 and keyCode2 then return keyCode2 end

	return nil
end

local function saveCheckpoint(statusLabel)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		if statusLabel then statusLabel.Text = "ไม่พบตัวละคร บันทึกเช็คพอยไม่ได้" end
		return
	end
	checkpointCFrame = hrp.CFrame
	if statusLabel then statusLabel.Text = "บันทึกเช็คพอยที่ตำแหน่งปัจจุบันแล้ว" end
end

local function teleportToCheckpoint(statusLabel)
	if not checkpointCFrame then
		if statusLabel then statusLabel.Text = "ยังไม่ได้บันทึกเช็คพอย" end
		return
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		if statusLabel then statusLabel.Text = "ไม่พบ HumanoidRootPart ของตัวเอง" end
		return
	end

	hrp.CFrame = checkpointCFrame
	if statusLabel then statusLabel.Text = "วาปไปเช็คพอยแล้ว" end
end

-- ===================== GUI =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TpToPlayerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local showTargetHealth = true

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.fromOffset(96, 36)
toggleButton.Position = UDim2.fromOffset(20, 20)
toggleButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.Text = "TP ผู้เล่น"
toggleButton.AutoButtonColor = false
toggleButton.Parent = screenGui
Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 8)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(350, 500)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
mainFrame.Visible = false
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.Position = UDim2.fromOffset(0, 0)
titleBar.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
titleBar.Active = true
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -280, 1, 0)
titleLabel.Position = UDim2.fromOffset(10, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 16
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "วาปไปหาผู้เล่น (ลากย้ายได้)"
titleLabel.Parent = titleBar

local healthToggleButton = Instance.new("TextButton")
healthToggleButton.Name = "HealthToggleButton"
healthToggleButton.Size = UDim2.fromOffset(76, 26)
healthToggleButton.Position = UDim2.new(1, -198, 0.5, -13)
healthToggleButton.BackgroundColor3 = Color3.fromRGB(70, 120, 80)
healthToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
healthToggleButton.Font = Enum.Font.GothamMedium
healthToggleButton.TextSize = 11
healthToggleButton.Text = "เลือด: ON"
healthToggleButton.Parent = titleBar
Instance.new("UICorner", healthToggleButton).CornerRadius = UDim.new(0, 8)

local refreshButton = Instance.new("TextButton")
refreshButton.Size = UDim2.fromOffset(76, 26)
refreshButton.Position = UDim2.new(1, -118, 0.5, -13)
refreshButton.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshButton.Font = Enum.Font.GothamMedium
refreshButton.TextSize = 12
refreshButton.Text = "รีเฟรช"
refreshButton.Parent = titleBar
Instance.new("UICorner", refreshButton).CornerRadius = UDim.new(0, 8)

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(28, 28)
closeButton.Position = UDim2.new(1, -36, 0.5, -14)
closeButton.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 15
closeButton.Text = "X"
closeButton.Parent = titleBar
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 6)

local WINDOW_GAP = 8
local function syncMainFrameToButton()
	local pos = toggleButton.Position
	local buttonHeight = toggleButton.AbsoluteSize.Y
	mainFrame.Position = UDim2.new(
		pos.X.Scale, pos.X.Offset,
		pos.Y.Scale, pos.Y.Offset + buttonHeight + WINDOW_GAP
	)
end

toggleButton.Active = true
makeDraggable(toggleButton, toggleButton, function()
	mainFrame.Visible = not mainFrame.Visible
end)
makeDraggable(toggleButton, titleBar)

toggleButton:GetPropertyChangedSignal("Position"):Connect(syncMainFrameToButton)
syncMainFrameToButton()

local distanceFrame = Instance.new("Frame")
distanceFrame.Size = UDim2.new(1, -16, 0, 30)
distanceFrame.Position = UDim2.fromOffset(8, 42)
distanceFrame.BackgroundTransparency = 1
distanceFrame.Parent = mainFrame

local distanceLabel = Instance.new("TextLabel")
distanceLabel.Size = UDim2.fromOffset(70, 30)
distanceLabel.Position = UDim2.fromOffset(0, 0)
distanceLabel.BackgroundTransparency = 1
distanceLabel.Font = Enum.Font.GothamMedium
distanceLabel.TextSize = 12
distanceLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
distanceLabel.Text = "ระยะห่าง:"
distanceLabel.Parent = distanceFrame

local minDistanceBox = Instance.new("TextBox")
minDistanceBox.Size = UDim2.fromOffset(44, 28)
minDistanceBox.Position = UDim2.fromOffset(70, 1)
minDistanceBox.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
minDistanceBox.TextColor3 = Color3.fromRGB(255, 255, 255)
minDistanceBox.Font = Enum.Font.GothamMedium
minDistanceBox.TextSize = 12
minDistanceBox.ClearTextOnFocus = false
minDistanceBox.Text = tostring(CONFIG.MinDistance)
minDistanceBox.Parent = distanceFrame
Instance.new("UICorner", minDistanceBox).CornerRadius = UDim.new(0, 6)

local distanceDashLabel = Instance.new("TextLabel")
distanceDashLabel.Size = UDim2.fromOffset(14, 28)
distanceDashLabel.Position = UDim2.fromOffset(116, 1)
distanceDashLabel.BackgroundTransparency = 1
distanceDashLabel.Font = Enum.Font.GothamMedium
distanceDashLabel.TextSize = 12
distanceDashLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
distanceDashLabel.Text = "-"
distanceDashLabel.Parent = distanceFrame

local maxDistanceBox = Instance.new("TextBox")
maxDistanceBox.Size = UDim2.fromOffset(44, 28)
maxDistanceBox.Position = UDim2.fromOffset(132, 1)
maxDistanceBox.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
maxDistanceBox.TextColor3 = Color3.fromRGB(255, 255, 255)
maxDistanceBox.Font = Enum.Font.GothamMedium
maxDistanceBox.TextSize = 12
maxDistanceBox.ClearTextOnFocus = false
maxDistanceBox.Text = tostring(CONFIG.MaxDistance)
maxDistanceBox.Parent = distanceFrame
Instance.new("UICorner", maxDistanceBox).CornerRadius = UDim.new(0, 6)

local distanceUnitLabel = Instance.new("TextLabel")
distanceUnitLabel.Size = UDim2.fromOffset(60, 28)
distanceUnitLabel.Position = UDim2.fromOffset(180, 1)
distanceUnitLabel.BackgroundTransparency = 1
distanceUnitLabel.Font = Enum.Font.GothamMedium
distanceUnitLabel.TextSize = 12
distanceUnitLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
distanceUnitLabel.Text = "studs"
distanceUnitLabel.Parent = distanceFrame

local function applyDistanceInputs()
	local newMin = tonumber(minDistanceBox.Text)
	local newMax = tonumber(maxDistanceBox.Text)

	if newMin then CONFIG.MinDistance = math.clamp(math.floor(newMin + 0.5), 1, 200) end
	if newMax then CONFIG.MaxDistance = math.clamp(math.floor(newMax + 0.5), 1, 200) end
	if CONFIG.MaxDistance < CONFIG.MinDistance then CONFIG.MaxDistance = CONFIG.MinDistance end

	minDistanceBox.Text = tostring(CONFIG.MinDistance)
	maxDistanceBox.Text = tostring(CONFIG.MaxDistance)
end

minDistanceBox.FocusLost:Connect(applyDistanceInputs)
maxDistanceBox.FocusLost:Connect(applyDistanceInputs)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 18)
statusLabel.Position = UDim2.fromOffset(8, 190)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextColor3 = Color3.fromRGB(160, 220, 160)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Text = "เลือกผู้เล่นด้านล่างเพื่อวาปไปหา | เลือด: ON"
statusLabel.Parent = mainFrame

local checkpointFrame = Instance.new("Frame")
checkpointFrame.Size = UDim2.new(1, -16, 0, 30)
checkpointFrame.Position = UDim2.fromOffset(8, 78)
checkpointFrame.BackgroundTransparency = 1
checkpointFrame.Parent = mainFrame

local saveCheckpointButton = Instance.new("TextButton")
saveCheckpointButton.Size = UDim2.fromOffset(80, 28)
saveCheckpointButton.Position = UDim2.fromOffset(0, 1)
saveCheckpointButton.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
saveCheckpointButton.TextColor3 = Color3.fromRGB(255, 255, 255)
saveCheckpointButton.Font = Enum.Font.GothamMedium
saveCheckpointButton.TextSize = 12
saveCheckpointButton.Text = "บันทึกจุด"
saveCheckpointButton.Parent = checkpointFrame
Instance.new("UICorner", saveCheckpointButton).CornerRadius = UDim.new(0, 6)

local goCheckpointButton = Instance.new("TextButton")
goCheckpointButton.Size = UDim2.fromOffset(80, 28)
goCheckpointButton.Position = UDim2.fromOffset(86, 1)
goCheckpointButton.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
goCheckpointButton.TextColor3 = Color3.fromRGB(255, 255, 255)
goCheckpointButton.Font = Enum.Font.GothamMedium
goCheckpointButton.TextSize = 12
goCheckpointButton.Text = "ไปจุดที่จำ"
goCheckpointButton.Parent = checkpointFrame
Instance.new("UICorner", goCheckpointButton).CornerRadius = UDim.new(0, 6)

local checkpointKeyBox = Instance.new("TextBox")
checkpointKeyBox.Size = UDim2.fromOffset(54, 28)
checkpointKeyBox.Position = UDim2.fromOffset(172, 1)
checkpointKeyBox.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
checkpointKeyBox.TextColor3 = Color3.fromRGB(255, 255, 255)
checkpointKeyBox.Font = Enum.Font.GothamMedium
checkpointKeyBox.TextSize = 12
checkpointKeyBox.ClearTextOnFocus = false
checkpointKeyBox.PlaceholderText = "ปุ่ม"
checkpointKeyBox.Text = ""
checkpointKeyBox.Parent = checkpointFrame
Instance.new("UICorner", checkpointKeyBox).CornerRadius = UDim.new(0, 6)

local checkpointKeyHintLabel = Instance.new("TextLabel")
checkpointKeyHintLabel.Size = UDim2.fromOffset(60, 28)
checkpointKeyHintLabel.Position = UDim2.fromOffset(232, 1)
checkpointKeyHintLabel.BackgroundTransparency = 1
checkpointKeyHintLabel.Font = Enum.Font.Gotham
checkpointKeyHintLabel.TextSize = 11
checkpointKeyHintLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
checkpointKeyHintLabel.TextXAlignment = Enum.TextXAlignment.Left
checkpointKeyHintLabel.Text = "ไม่ตั้ง"
checkpointKeyHintLabel.Parent = checkpointFrame

saveCheckpointButton.MouseButton1Click:Connect(function() saveCheckpoint(statusLabel) end)
goCheckpointButton.MouseButton1Click:Connect(function() teleportToCheckpoint(statusLabel) end)

checkpointKeyBox.FocusLost:Connect(function()
	local text = checkpointKeyBox.Text
	if text == "" then
		checkpointKeyCode = nil
		checkpointKeyHintLabel.Text = "ไม่ตั้ง"
		statusLabel.Text = "ยกเลิกปุ่มลัดเช็คพอยแล้ว"
		return
	end

	local resolved = resolveKeyCode(text)
	if resolved then
		checkpointKeyCode = resolved
		checkpointKeyBox.Text = resolved.Name
		checkpointKeyHintLabel.Text = "ปุ่ม: " .. resolved.Name
		statusLabel.Text = "ตั้งปุ่มลัดวาปเช็คพอยเป็น " .. resolved.Name .. " แล้ว"
	else
		checkpointKeyBox.Text = checkpointKeyCode and checkpointKeyCode.Name or ""
		statusLabel.Text = "ไม่รู้จักปุ่มที่พิมพ์ ลองพิมพ์ใหม่ เช่น F, 1, Space"
	end
end)

trackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if checkpointKeyCode and input.KeyCode == checkpointKeyCode then
		teleportToCheckpoint(statusLabel)
	end
end))

local playerRows = {}

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -16, 1, -222)
scrollFrame.Position = UDim2.fromOffset(8, 214)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 6
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = scrollFrame

local function getPlayerHealthText(entry)
	local humanoid = entry.character and entry.character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return "HP: ?" end

	local health = math.max(0, humanoid.Health)
	local maxHealth = math.max(0, humanoid.MaxHealth)

	if maxHealth <= 0 then
		return string.format("HP: %.0f", health)
	end
	return string.format("HP: %.0f / %.0f", health, maxHealth)
end

local function updateHealthToggleButton()
	if showTargetHealth then
		healthToggleButton.Text = "เลือด: ON"
		healthToggleButton.BackgroundColor3 = Color3.fromRGB(70, 120, 80)
	else
		healthToggleButton.Text = "เลือด: OFF"
		healthToggleButton.BackgroundColor3 = Color3.fromRGB(90, 70, 70)
	end
end

healthToggleButton.MouseButton1Click:Connect(function()
	showTargetHealth = not showTargetHealth
	updateHealthToggleButton()
end)

local function createPlayerRow(entry)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -235, 1, 0)
	nameLabel.Position = UDim2.fromOffset(10, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = entry.player.Name
	nameLabel.Parent = row

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "HealthLabel"
	healthLabel.Size = UDim2.fromOffset(92, 26)
	healthLabel.Position = UDim2.new(1, -230, 0.5, -13)
	healthLabel.BackgroundTransparency = 1
	healthLabel.Font = Enum.Font.GothamMedium
	healthLabel.TextSize = 11
	healthLabel.TextColor3 = Color3.fromRGB(120, 230, 130)
	healthLabel.TextXAlignment = Enum.TextXAlignment.Right
	healthLabel.Text = getPlayerHealthText(entry)
	healthLabel.Visible = showTargetHealth
	healthLabel.Parent = row
	
	-- ปุ่มวาปไปหาผู้เล่น (ปรับขนาดเล็กลงเพื่อให้มีที่ว่าง)
	local goButton = Instance.new("TextButton")
	goButton.Size = UDim2.fromOffset(45, 26) 
	goButton.Position = UDim2.new(1, -102, 0.5, -13)
	goButton.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
	goButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	goButton.Font = Enum.Font.GothamBold
	goButton.TextSize = 12
	goButton.Text = "ไปหา"
	goButton.Parent = row
	Instance.new("UICorner", goButton).CornerRadius = UDim.new(0, 6)

	goButton.MouseButton1Click:Connect(function()
		teleportToPlayer(entry, statusLabel)
	end)

	-- ปุ่มดึงผู้เล่นที่เพิ่มใหม่
	local pullButton = Instance.new("TextButton")
	pullButton.Size = UDim2.fromOffset(45, 26)
	pullButton.Position = UDim2.new(1, -52, 0.5, -13)
	pullButton.BackgroundColor3 = Color3.fromRGB(200, 100, 70) -- สีส้ม/แดงเพื่อให้แยกออกง่าย
	pullButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	pullButton.Font = Enum.Font.GothamBold
	pullButton.TextSize = 12
	pullButton.Text = "ดึง"
	pullButton.Parent = row
	Instance.new("UICorner", pullButton).CornerRadius = UDim.new(0, 6)

	pullButton.MouseButton1Click:Connect(function()
		bringPlayer(entry, statusLabel)
	end)

	playerRows[entry.player] = {
		row = row,
		healthLabel = healthLabel,
		entry = entry,
	}

	row.Destroying:Connect(function()
		if playerRows[entry.player] and playerRows[entry.player].row == row then
			playerRows[entry.player] = nil
		end
	end)

	return row
end

local function refreshPlayerList()
	for playerKey, data in pairs(playerRows) do
		if not data.row or not data.row.Parent then
			playerRows[playerKey] = nil
		end
	end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	table.clear(playerRows)

	local targetable = getTargetablePlayers()

	if #targetable == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 34)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextSize = 12
		emptyLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		emptyLabel.Text = "ไม่มีผู้เล่นที่ไกลจาก Spawn พอให้วาปไปหา"
		emptyLabel.Parent = scrollFrame
		return
	end

	for i, entry in ipairs(targetable) do
		local row = createPlayerRow(entry)
		row.LayoutOrder = i
		row.Parent = scrollFrame
	end
end

refreshButton.MouseButton1Click:Connect(refreshPlayerList)

trackConnection(Players.PlayerAdded:Connect(refreshPlayerList))
trackConnection(Players.PlayerRemoving:Connect(function()
	task.defer(refreshPlayerList)
end))

local scriptRunning = true
task.spawn(function()
	while scriptRunning do
		task.wait(CONFIG.AutoRefreshSeconds)
		if scriptRunning then refreshPlayerList() end
	end
end)

task.spawn(function()
	while scriptRunning do
		task.wait(CONFIG.HealthRefreshSeconds)
		if scriptRunning then
			for playerKey, data in pairs(playerRows) do
				if data.row and data.row.Parent and data.healthLabel and data.entry then
					data.healthLabel.Visible = showTargetHealth
					data.healthLabel.Text = getPlayerHealthText(data.entry)

					local humanoid = data.entry.character and data.entry.character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.MaxHealth > 0 then
						local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
						if ratio <= 0.25 then
							data.healthLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
						elseif ratio <= 0.5 then
							data.healthLabel.TextColor3 = Color3.fromRGB(255, 190, 80)
						else
							data.healthLabel.TextColor3 = Color3.fromRGB(120, 230, 130)
						end
					end
				end
			end
		end
	end
end)

-- ===================== ESP (กรอบ + เลือด + ชื่อ) =====================
local espEnabled = true
local espShowBox = true
local espShowName = true
local espShowHealth = true

local espFolder = nil
local espObjects = {}

local function ensureEspFolder()
	local currentPlayerGui = player:FindFirstChildOfClass("PlayerGui") or playerGui
	if espFolder and espFolder.Parent == currentPlayerGui then return end

	if espFolder then pcall(function() espFolder:Destroy() end) end
	table.clear(espObjects)

	espFolder = Instance.new("Folder")
	espFolder.Name = "TpToPlayerEsp"
	espFolder.Parent = currentPlayerGui
end
ensureEspFolder()

local function getPlayerCharacter(otherPlayer)
	local workspaceCharacter = Workspace:FindFirstChild(otherPlayer.Name)
	if workspaceCharacter and workspaceCharacter:FindFirstChild("HumanoidRootPart") then
		return workspaceCharacter
	end

	local character = otherPlayer.Character
	if character and character:IsDescendantOf(Workspace) then
		return character
	end
	return nil
end

local function isEspIntact(data)
	for _, gui in ipairs(data.guis) do
		if not gui.Parent then return false end
	end
	return true
end

local function getHealthColor(ratio)
	if ratio <= 0.25 then return Color3.fromRGB(255, 90, 90)
	elseif ratio <= 0.5 then return Color3.fromRGB(255, 190, 80)
	end
	return Color3.fromRGB(120, 230, 130)
end

local function removeEsp(otherPlayer)
	local data = espObjects[otherPlayer]
	if data then
		espObjects[otherPlayer] = nil
		for _, gui in ipairs(data.guis) do gui:Destroy() end
	end
end

local function newBillboard(name, hrp, size)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Adornee = hrp
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false
	gui.Size = size
	gui.Parent = espFolder
	return gui
end

local function newTextLabel(parent, position, textYAlignment, textSize, font)
	local label = Instance.new("TextLabel")
	label.Position = position
	label.Size = UDim2.fromScale(1, 0.5)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.TextYAlignment = textYAlignment
	label.Text = ""
	label.Parent = parent
	return label
end

local function createEsp(otherPlayer, character, hrp)
	local defaultSize = UDim2.fromScale(CONFIG.EspBoxWidth, CONFIG.EspBoxHeight)

	local boxGui = newBillboard("Box", hrp, defaultSize)
	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Parent = boxGui

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = CONFIG.EspColor
	boxStroke.Thickness = 1.5
	boxStroke.Parent = box

	local healthGui = newBillboard("HealthBar", hrp, UDim2.new(0, 4, CONFIG.EspBoxHeight, 0))
	local healthBackground = Instance.new("Frame")
	healthBackground.Size = UDim2.fromScale(1, 1)
	healthBackground.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	healthBackground.BorderSizePixel = 0
	healthBackground.Parent = healthGui

	local healthFill = Instance.new("Frame")
	healthFill.AnchorPoint = Vector2.new(0, 1)
	healthFill.Position = UDim2.fromScale(0, 1)
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBackground

	local nameGui = newBillboard("Name", hrp, UDim2.fromOffset(260, 40))
	local nameLabel = newTextLabel(nameGui, UDim2.fromScale(0, 0), Enum.TextYAlignment.Bottom, 14, Enum.Font.GothamBold)

	local hpGui = newBillboard("HealthText", hrp, UDim2.fromOffset(260, 40))
	local healthText = newTextLabel(hpGui, UDim2.fromScale(0, 0.5), Enum.TextYAlignment.Top, 13, Enum.Font.GothamMedium)

	return {
		guis = { boxGui, healthGui, nameGui, hpGui },
		boxGui = boxGui,
		healthGui = healthGui,
		healthFill = healthFill,
		nameGui = nameGui,
		nameLabel = nameLabel,
		hpGui = hpGui,
		healthText = healthText,
		character = character,
		hrp = hrp,
	}
end

local function updateEsp()
	ensureEspFolder()

	local myCharacter = player.Character
	local myHRP = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local character = getPlayerCharacter(otherPlayer)
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local distance = myHRP and hrp and (hrp.Position - myHRP.Position).Magnitude

			local shouldShow = espEnabled
				and hrp ~= nil
				and hrp:IsDescendantOf(Workspace)
				and humanoid ~= nil
				and humanoid.Health > 0
				and (not distance or distance <= CONFIG.EspMaxDistance)

			if shouldShow then
				local data = espObjects[otherPlayer]
				if data and (data.character ~= character or data.hrp ~= hrp or not isEspIntact(data)) then
					removeEsp(otherPlayer)
					data = nil
				end
				if not data then
					data = createEsp(otherPlayer, character, hrp)
					espObjects[otherPlayer] = data
				end

				local scale = math.max(hrp.Size.Y / 2, 0.5)
				local boxWidth = CONFIG.EspBoxWidth * scale
				local boxHeight = CONFIG.EspBoxHeight * scale
				local centerY = CONFIG.EspBoxYOffset * scale

				data.boxGui.Size = UDim2.fromScale(boxWidth, boxHeight)
				data.boxGui.StudsOffsetWorldSpace = Vector3.new(0, centerY, 0)

				data.healthGui.Size = UDim2.new(0, 4, boxHeight, 0)
				data.healthGui.StudsOffset = Vector3.new(-(boxWidth / 2 + 0.2), 0, 0)
				data.healthGui.StudsOffsetWorldSpace = Vector3.new(0, centerY, 0)

				data.nameGui.StudsOffsetWorldSpace = Vector3.new(0, centerY + boxHeight / 2 + 0.1, 0)
				data.hpGui.StudsOffsetWorldSpace = Vector3.new(0, centerY - boxHeight / 2 - 0.1, 0)

				data.boxGui.Enabled = espShowBox
				data.nameGui.Enabled = espShowName
				data.healthGui.Enabled = espShowHealth
				data.hpGui.Enabled = espShowHealth

				local health = math.max(0, humanoid.Health)
				local maxHealth = math.max(0, humanoid.MaxHealth)
				local ratio = maxHealth > 0 and math.clamp(health / maxHealth, 0, 1) or 1
				local healthColor = getHealthColor(ratio)

				data.healthFill.Size = UDim2.fromScale(1, ratio)
				data.healthFill.BackgroundColor3 = healthColor
				data.healthText.TextColor3 = healthColor
				if maxHealth > 0 then
					data.healthText.Text = string.format("HP %.0f / %.0f", health, maxHealth)
				else
					data.healthText.Text = string.format("HP %.0f", health)
				end

				local label = otherPlayer.Name
				if distance then label = label .. string.format(" [%.0fm]", distance) end
				data.nameLabel.Text = label
			else
				removeEsp(otherPlayer)
			end
		end
	end

	for otherPlayer in pairs(espObjects) do
		if otherPlayer.Parent ~= Players then removeEsp(otherPlayer) end
	end
end

trackConnection(Players.PlayerRemoving:Connect(removeEsp))

local lastEspError = nil
local function safeUpdateEsp()
	local ok, err = pcall(updateEsp)
	if not ok and err ~= lastEspError then
		lastEspError = err
		warn("[ESP] error: " .. tostring(err))
	end
end

trackConnection(player.CharacterAdded:Connect(function()
	for otherPlayer in pairs(espObjects) do removeEsp(otherPlayer) end
end))

task.spawn(function()
	while scriptRunning do
		task.wait(CONFIG.EspRefreshSeconds)
		if scriptRunning then safeUpdateEsp() end
	end
end)

local espRow = Instance.new("Frame")
espRow.Name = "EspRow"
espRow.Size = UDim2.new(1, -16, 0, 30)
espRow.Position = UDim2.fromOffset(8, 114)
espRow.BackgroundTransparency = 1
espRow.Parent = mainFrame

local function createEspToggle(labelText, xOffset, getState, setState)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(76, 28)
	button.Position = UDim2.fromOffset(xOffset, 1)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 11
	button.Parent = espRow
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)

	local function refreshStyle()
		local isOn = getState()
		button.Text = labelText .. (isOn and ": ON" or ": OFF")
		button.BackgroundColor3 = isOn and Color3.fromRGB(70, 120, 80) or Color3.fromRGB(90, 70, 70)
	end
	refreshStyle()

	button.MouseButton1Click:Connect(function()
		setState(not getState())
		refreshStyle()
		safeUpdateEsp()
	end)
end

createEspToggle("ESP", 0, function() return espEnabled end, function(value)
	espEnabled = value
	statusLabel.Text = value and "เปิด ESP แล้ว" or "ปิด ESP แล้ว"
end)
createEspToggle("กรอบ", 84, function() return espShowBox end, function(value) espShowBox = value end)
createEspToggle("ชื่อ", 168, function() return espShowName end, function(value) espShowName = value end)
createEspToggle("HP", 252, function() return espShowHealth end, function(value) espShowHealth = value end)


-- ============================================================
-- ANIME CHARACTER SELECTOR
-- รวมความสามารถจาก Anime Ability Arena:
-- เลือกตัวละครจากการ์ด/ดาว โดยไม่ต้องพิมพ์ชื่อ
-- ============================================================

local ANIME_CHARACTERS = {
	"Goko",
	"Asto",
	"Michigo",
	"Laffy",
	"Narotu",
	"Jinwu",
	"Mako",
	"Sasukei",
	"Yujin ltadora",
	"Deko",
}

local selectedAnimeCharacter = nil
local characterFrame = nil
local characterStatusLabel = nil
local characterButtons = {}

local CHARACTER_CHANGE_SPAWN_DELAY = 0.35

local function getOwnRootPart()
	local character = player.Character or player.CharacterAdded:Wait()
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- เปลี่ยนตัวละครต้องอยู่ที่ Spawn: จำจุดเดิม -> ไป Spawn -> ส่งคำสั่ง -> กลับจุดเดิม
local function changeCharacterFromSpawn(charName)
	local root = getOwnRootPart()
	if not root then
		return false, "ไม่พบ HumanoidRootPart ของตัวเอง"
	end

	local originalCFrame = root.CFrame
	local spawnPart = Workspace:FindFirstChild("Lobby") and Workspace.Lobby:FindFirstChild("SpawnLocation")
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return false, "ไม่พบ Lobby.SpawnLocation"
	end

	local success, result, extra = pcall(function()
		-- ไป Spawn ก่อน
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 4, 0)
		task.wait(0.15)

		-- ส่งคำสั่งเปลี่ยนตัวขณะที่อยู่ Spawn
		local ok, err = fireCharacterChange(charName)
		if not ok then
			return false, err
		end

		-- เผื่อเวลาให้ server/client อัปเดต Moveset
		task.wait(CHARACTER_CHANGE_SPAWN_DELAY)
		return true
	end)

	-- กลับจุดเดิมเสมอ แม้คำสั่งเปลี่ยนตัวจะล้มเหลว
	local newRoot = getOwnRootPart()
	if newRoot then
		newRoot.CFrame = originalCFrame
	end

	if not success then
		return false, tostring(result)
	end
	if result ~= true then
		return false, tostring(extra or "เปลี่ยนตัวละครไม่สำเร็จ")
	end

	return true
end

local function fireCharacterChange(charName)
	if not charName or charName == "" then
		return false, "ไม่ได้เลือกตัวละคร"
	end

	local ok, err = pcall(function()
		local nameLength = #charName
		local bytesList = {197, nameLength, 0}

		for i = 1, nameLength do
			table.insert(bytesList, string.byte(charName, i, i))
		end

		local byteNetPath = ReplicatedStorage
			.Packages
			._Index["elitriare_bytenet-max@0.2.7"]
			["bytenet-max"]
			.system
			.ByteNetReliable

		local bufferData = buffer.create(#bytesList)
		for i = 1, #bytesList do
			buffer.writeu8(bufferData, i - 1, bytesList[i])
		end

		byteNetPath:FireServer(bufferData, nil)

		-- อัปเดต Client state ถ้า environment รองรับ firesignal
		pcall(function()
			local localEvent = ReplicatedStorage
				.Packages
				._Index["leifstout_networker@0.3.1"]
				.networker
				._remotes
				.DataService
				.RemoteEvent

			if typeof(firesignal) == "function" then
				firesignal(localEvent.OnClientEvent, "set", {"EquippedMoveset"}, charName)
			end
		end)
	end)

	if not ok then
		return false, tostring(err)
	end

	return true
end

local function updateCharacterButtonStyles()
	for name, data in pairs(characterButtons) do
		if data.button then
			if name == selectedAnimeCharacter then
				data.button.BackgroundColor3 = Color3.fromRGB(70, 130, 210)
				data.star.TextColor3 = Color3.fromRGB(255, 220, 80)
				data.selected.Visible = true
			else
				data.button.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
				data.star.TextColor3 = Color3.fromRGB(180, 180, 190)
				data.selected.Visible = false
			end
		end
	end
end

local function createCharacterSelector()
	-- ปุ่มเปิดหน้าเลือกตัวละคร
	local characterToggle = Instance.new("TextButton")
	characterToggle.Name = "CharacterToggleButton"
	characterToggle.Size = UDim2.fromOffset(110, 36)
	characterToggle.Position = UDim2.fromOffset(124, 20)
	characterToggle.BackgroundColor3 = Color3.fromRGB(70, 90, 150)
	characterToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	characterToggle.Font = Enum.Font.GothamBold
	characterToggle.TextSize = 14
	characterToggle.Text = "★ ตัวละคร"
	characterToggle.AutoButtonColor = false
	characterToggle.Parent = screenGui
	Instance.new("UICorner", characterToggle).CornerRadius = UDim.new(0, 8)

	characterFrame = Instance.new("Frame")
	characterFrame.Name = "CharacterSelector"
	characterFrame.Size = UDim2.fromOffset(350, 500)
	characterFrame.Position = UDim2.fromOffset(244, 66)
	characterFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	characterFrame.Visible = false
	characterFrame.Parent = screenGui
	Instance.new("UICorner", characterFrame).CornerRadius = UDim.new(0, 10)

	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 42)
	titleBar.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	titleBar.Active = true
	titleBar.Parent = characterFrame
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -55, 1, 0)
	title.Position = UDim2.fromOffset(12, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "★ Anime Ability Arena"
	title.Parent = titleBar

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(28, 28)
	close.Position = UDim2.new(1, -36, 0.5, -14)
	close.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 15
	close.Text = "X"
	close.Parent = titleBar
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)

	local selectedLabel = Instance.new("TextLabel")
	selectedLabel.Name = "SelectedLabel"
	selectedLabel.Size = UDim2.new(1, -20, 0, 28)
	selectedLabel.Position = UDim2.fromOffset(10, 50)
	selectedLabel.BackgroundTransparency = 1
	selectedLabel.Font = Enum.Font.GothamMedium
	selectedLabel.TextSize = 13
	selectedLabel.TextColor3 = Color3.fromRGB(180, 210, 255)
	selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
	selectedLabel.Text = "ตัวที่เลือก: ยังไม่ได้เลือก"
	selectedLabel.Parent = characterFrame
	characterStatusLabel = selectedLabel

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -20, 0, 22)
	hint.Position = UDim2.fromOffset(10, 77)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = Color3.fromRGB(150, 150, 165)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = "กดการ์ด ★ เพื่อเลือก แล้วกด EQUIP"
	hint.Parent = characterFrame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CharacterList"
	scroll.Size = UDim2.new(1, -20, 1, -160)
	scroll.Position = UDim2.fromOffset(10, 105)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = characterFrame

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(158, 62)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	local function chooseCharacter(name)
		selectedAnimeCharacter = name
		selectedLabel.Text = "ตัวที่เลือก: " .. name
		updateCharacterButtonStyles()
	end

	for index, name in ipairs(ANIME_CHARACTERS) do
		local card = Instance.new("TextButton")
		card.Name = "Character_" .. name:gsub("%W", "_")
		card.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
		card.Text = ""
		card.AutoButtonColor = false
		card.LayoutOrder = index
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 9)

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(70, 70, 85)
		stroke.Thickness = 1
		stroke.Parent = card

		local star = Instance.new("TextLabel")
		star.Size = UDim2.fromOffset(38, 62)
		star.Position = UDim2.fromOffset(4, 0)
		star.BackgroundTransparency = 1
		star.Font = Enum.Font.GothamBold
		star.TextSize = 25
		star.Text = "★"
		star.TextColor3 = Color3.fromRGB(180, 180, 190)
		star.Parent = card

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -50, 1, -8)
		nameLabel.Position = UDim2.fromOffset(44, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.TextWrapped = true
		nameLabel.Text = name
		nameLabel.Parent = card

		local selected = Instance.new("TextLabel")
		selected.Size = UDim2.fromOffset(28, 20)
		selected.Position = UDim2.new(1, -32, 0, 4)
		selected.BackgroundTransparency = 1
		selected.Font = Enum.Font.GothamBold
		selected.TextSize = 12
		selected.TextColor3 = Color3.fromRGB(100, 230, 140)
		selected.Text = "✓"
		selected.Visible = false
		selected.Parent = card

		characterButtons[name] = {
			button = card,
			star = star,
			selected = selected,
		}

		card.MouseButton1Click:Connect(function()
			chooseCharacter(name)
		end)
	end

	local equipButton = Instance.new("TextButton")
	equipButton.Name = "EquipButton"
	equipButton.Size = UDim2.new(1, -20, 0, 42)
	equipButton.Position = UDim2.new(0, 10, 1, -52)
	equipButton.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
	equipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 14
	equipButton.Text = "★ EQUIP ตัวละคร"
	equipButton.Parent = characterFrame
	Instance.new("UICorner", equipButton).CornerRadius = UDim.new(0, 8)

	equipButton.MouseButton1Click:Connect(function()
		if not selectedAnimeCharacter then
			characterStatusLabel.Text = "กรุณาเลือกตัวละครก่อน"
			characterStatusLabel.TextColor3 = Color3.fromRGB(255, 190, 100)
			return
		end

		equipButton.Text = "กำลังเปลี่ยน..."
		equipButton.BackgroundColor3 = Color3.fromRGB(190, 145, 55)

		local ok, err = changeCharacterFromSpawn(selectedAnimeCharacter)
		if ok then
			characterStatusLabel.Text = "✓ เปลี่ยนเป็น " .. selectedAnimeCharacter .. " แล้ว"
			characterStatusLabel.TextColor3 = Color3.fromRGB(120, 230, 140)
			equipButton.Text = "★ EQUIP สำเร็จ"
			equipButton.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
		else
			characterStatusLabel.Text = "เปลี่ยนไม่สำเร็จ: " .. tostring(err)
			characterStatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			equipButton.Text = "★ EQUIP ตัวละคร"
			equipButton.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
		end

		task.delay(1.5, function()
			if equipButton.Parent then
				equipButton.Text = "★ EQUIP ตัวละคร"
				equipButton.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
			end
		end)
	end)

	makeDraggable(characterFrame, titleBar)

	characterToggle.MouseButton1Click:Connect(function()
		characterFrame.Visible = not characterFrame.Visible
		if characterFrame.Visible then
			characterFrame.Position = UDim2.fromOffset(244, 66)
		end
	end)

	close.MouseButton1Click:Connect(function()
		characterFrame.Visible = false
	end)
end

createCharacterSelector()


-- ===================== ปิด/ออกจากสคริปต์ =====================
local function shutdownScript()
	if not scriptRunning then return end
	scriptRunning = false

	for _, connection in ipairs(activeConnections) do connection:Disconnect() end

	espEnabled = false
	table.clear(espObjects)
	if espFolder then espFolder:Destroy() end
	screenGui:Destroy()
end

closeButton.MouseButton1Click:Connect(shutdownScript)

refreshPlayerList()