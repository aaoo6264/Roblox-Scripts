local Players = game:GetService("Players")
local player = Players.LocalPlayer

--== ตั้งค่า ==--
local CHECK_INTERVAL = 5     -- เช็คทุกกี่วินาที
local CLOSE_DISTANCE = 5     -- ใกล้กว่านี้ (studs) = ถึงแล้ว
local SPAWN_SETTLE   = 1     -- รอให้ตัวละครเกิดนิ่งก่อนหา Plot (วินาที)
local AUTO_START     = true

--== Helper ==--
local function getPosition(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	local part = inst:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position
end

-- หา Plot ที่ SpawnPoint ใกล้ตำแหน่ง pos ที่สุด
local function detectMyPlot(pos)
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	local bestIndex, bestDist
	for i = 1, 7 do
		local plot = plots:FindFirstChild(tostring(i))
		local spawnPos = plot and getPosition(plot:FindFirstChild("SpawnPoint"))
		if spawnPos then
			local d = (spawnPos - pos).Magnitude
			if not bestDist or d < bestDist then
				bestIndex, bestDist = i, d
			end
		end
	end
	return bestIndex
end

--== GUI (กลางจอ) ==--
local gui = Instance.new("ScreenGui")
gui.Name = "AutoTreadmillGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.new(0, 240, 0, 95)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -30, 0, 26)
title.Position = UDim2.new(0, 8, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Auto Treadmill"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 22, 0, 22)
closeButton.Position = UDim2.new(1, -26, 0, 3)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 12
closeButton.BorderSizePixel = 0
closeButton.Parent = frame
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 6)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 22)
status.Position = UDim2.new(0, 8, 0, 28)
status.BackgroundTransparency = 1
status.Text = "สถานะ: -"
status.TextColor3 = Color3.fromRGB(200, 200, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.new(1, -20, 0, 28)
button.Position = UDim2.new(0, 10, 0, 57)
button.Font = Enum.Font.GothamBold
button.TextSize = 13
button.TextColor3 = Color3.new(1, 1, 1)
button.BorderSizePixel = 0
button.Parent = frame
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)

local function setStatus(t) status.Text = "สถานะ: " .. t end

--== Logic ==--
local running = false
local runToken = 0
local myPlot = nil          -- ลำดับ Plot ของเรา
local needDetect = true     -- ต้องหา Plot ใหม่ (ตอนเริ่ม / ตอนเกิดใหม่)

local function updateButton()
	if running then
		button.Text = "หยุด"
		button.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	else
		button.Text = "เริ่ม"
		button.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
	end
end

local function haltWalking()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp then hum:MoveTo(hrp.Position) end
end

-- เกิดใหม่ทุกครั้ง = เกิดที่ SpawnPoint ของเราอีก -> หา Plot ใหม่ตอนนั้น
local respawnConn = player.CharacterAdded:Connect(function()
	needDetect = true
end)

local function tick(hum, hrp)
	-- 1) หา Plot ของเราจาก SpawnPoint (ทำตอนเกิด)
	if needDetect then
		setStatus("กำลังหา Plot ของเรา...")
		task.wait(SPAWN_SETTLE)
		local plotIndex = detectMyPlot(hrp.Position)
		if not plotIndex then
			setStatus("ไม่พบ SpawnPoint ใน Plots")
			return
		end
		myPlot = plotIndex
		needDetect = false
	end

	-- 2) หา TreadmillBottom ของ Plot เรา
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(tostring(myPlot))
	local bottom = plot and plot:FindFirstChild("TreadmillBottom")
	local target = getPosition(bottom)
	if not target then
		setStatus(("Plot %d: ไม่พบ TreadmillBottom"):format(myPlot))
		return
	end

	-- 3) เดินไป / หยุดถ้าถึงแล้ว
	local dist = (hrp.Position - target).Magnitude
	if dist > CLOSE_DISTANCE then
		setStatus(("Plot %d: กำลังเดิน (%.0f studs)"):format(myPlot, dist))
		hum:MoveTo(target)
	else
		setStatus(("Plot %d: ถึงแล้ว วิ่งบนลู่ ✔"):format(myPlot))
		hum:MoveTo(hrp.Position)
	end
end

local function start()
	if running then return end
	running = true
	runToken += 1
	local myToken = runToken
	updateButton()

	task.spawn(function()
		while running and myToken == runToken do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then
				local ok, err = pcall(tick, hum, hrp)
				if not ok then setStatus("error: " .. tostring(err)) end
			else
				setStatus("รอตัวละคร...")
			end

			local waited = 0
			while running and myToken == runToken and waited < CHECK_INTERVAL do
				task.wait(0.25)
				waited += 0.25
			end
		end
	end)
end

local function stop()
	running = false
	runToken += 1
	haltWalking()
	setStatus("หยุดทำงาน")
	updateButton()
end

button.MouseButton1Click:Connect(function()
	if running then stop() else start() end
end)

-- ปุ่มปิดโปรแกรม: หยุดทำงาน + ลบ GUI
closeButton.MouseButton1Click:Connect(function()
	stop()
	respawnConn:Disconnect()
	gui:Destroy()
end)

updateButton()
if AUTO_START then start() else setStatus("หยุดทำงาน") end