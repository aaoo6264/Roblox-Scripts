-- ============================================================
--  Stage Warp + AutoFarm GUI (Added Auto Heal)
--  วางเป็น LocalScript หรือรันผ่าน executor
--  [-] พับหน้าต่าง | [X] ปิดโปรแกรม | RightShift = ซ่อน/แสดง
-- ============================================================

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer

-- ===================== ตั้งค่า (แก้ได้) =====================
local CONFIG = {
	RefreshInterval = 2,
	SpawnDelay      = 2,
	SpawnMaxWait    = 8,
	ReturnWait      = 4,
	ReturnMinMove   = 20,
	ReturnFallbackSpawn = true,
	ClearConfirm    = 1.5,
	RespawnTime     = 30,
	RespawnGiveUp   = 45,
	EnemyRadius     = 80,
	AttackRange     = 10,
	TeleportDistance = 10,
	WalkToEnemy     = true,
	WalkTimeout     = 2,
	InfiniteAttack  = false,
	InfiniteHitbox  = Vector3.new(60, 60, 60),
	InfiniteCooldown = 0.05,
	FreezeDuration  = 2,
	InfiniteDamage  = 100,
	Loot            = true,
	LootTries       = 3,
}

-- ===================== อ้างอิงใน workspace =====================
local AreaPart = workspace:WaitForChild("WorldModel"):WaitForChild("StageMap"):WaitForChild("AreaPart")

local State = {
	alive = true, farming = false, target = 1, status = "พร้อม",
	cleared = false,
	noEnemySince = nil,
	clearedAt = nil,
	autoHeal = false, -- [เพิ่มใหม่] สถานะโหมดฮีล
}
local function resetCycle()
	State.cleared, State.noEnemySince, State.clearedAt = false, nil, nil
end
local blacklist = setmetatable({}, { __mode = "k" })
local attempts = setmetatable({}, { __mode = "k" })

-- ===================== ฟังก์ชันช่วย =====================
local function getHRP()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local function posOf(o)
	if o:IsA("BasePart") then
		return o.Position
	elseif o:IsA("Model") then
		return o:GetPivot().Position
	end
end

local function tpTo(pos)
	local hrp = getHRP()
	if not hrp then return false end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = CFrame.new(pos)
	return true
end

local function getStages()
	local list = {}
	for _, obj in ipairs(AreaPart:GetChildren()) do
		local num = obj.Name:match("^Stage_(%d+)$")
		if num then table.insert(list, { num = tonumber(num), obj = obj }) end
	end
	table.sort(list, function(a, b) return a.num < b.num end)
	return list
end

local function stageWarpPos(obj)
	local p = posOf(obj)
	local h = 0
	if obj:IsA("BasePart") then
		h = obj.Size.Y / 2
	elseif obj:IsA("Model") then
		h = select(2, obj:GetBoundingBox()).Y / 2
	end
	return p + Vector3.new(0, h + 4, 0)
end

-- แปลงข้อความราคา เช่น "$1,250" "1.5K" "2M" เป็นตัวเลข
local SUFFIX = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }
local function parsePrice(text)
	text = (tostring(text):gsub(",", ""))
	local num, suf = text:match("([%d%.]+)%s*(%a?)")
	local n = tonumber(num) or 0
	return n * (SUFFIX[(suf or ""):upper()] or 1)
end

-- ===================== กระเป๋า =====================
local function getBag()
	local ok, txt = pcall(function()
		return player.PlayerGui.Hud.LeftInfos.OrePack.Title.Text
	end)
	if not ok then return nil end
	local a, b = tostring(txt):match("(%d+)%s*/%s*(%d+)")
	if a then return tonumber(a), tonumber(b) end
end

local function bagFull()
	local c, m = getBag()
	return c ~= nil and m ~= nil and c >= m
end

-- ===================== ของดรอป (OreCache) =====================
local function getLootList()
	local list = {}
	local cache = workspace:FindFirstChild("OreCache")
	if not cache then return list end
	for _, ore in ipairs(cache:GetChildren()) do
		if ore.Name:match("^Ore_%d+$") and not blacklist[ore] then
			local main = ore:FindFirstChild("MAIN")
			if main then
				local ok, txt = pcall(function()
					return main.OreLoot.BillboardGui.Frame.Price.Price.Text
				end)
				table.insert(list, { ore = ore, price = ok and parsePrice(txt) or 0 })
			end
		end
	end
	table.sort(list, function(a, b) return a.price > b.price end)
	return list
end

local function pickup(ore)
	local main = ore:FindFirstChild("MAIN")
	local prompt = main and main:FindFirstChild("ProximityPrompt")
	if not prompt then return false end

	tpTo(posOf(main) + Vector3.new(0, 3, 0))
	task.wait(0.15)
	pcall(function() prompt.HoldDuration = 0 end)

	if fireproximityprompt then
		pcall(fireproximityprompt, prompt)
	else
		pcall(function()
			prompt:InputHoldBegin()
			task.wait(0.1)
			prompt:InputHoldEnd()
		end)
	end

	local t = tick()
	while ore.Parent and tick() - t < 1 do task.wait(0.1) end
	return ore.Parent == nil
end

-- ===================== มอนเตอร์ =====================
local function isEnemyInTargetStage(enemy, stageObj, radius)
	if not enemy or not stageObj then return false end
	local p = posOf(enemy)
	local stagePos = posOf(stageObj)
	if not p or not stagePos then return false end
	return (p - stagePos).Magnitude <= radius
end

local function findEnemy(stageObj, radius)
	local folder = workspace:FindFirstChild("EnemyFolder")
	local hrp = getHRP()
	if not folder or not hrp or not stageObj then return nil end
	local stagePos = posOf(stageObj)
	if not stagePos then return nil end

	local best, bestD
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local p = posOf(m)
				if p and (p - stagePos).Magnitude <= radius then
					local d = (p - hrp.Position).Magnitude
					if not bestD or d < bestD then best, bestD = m, d end
				end
			end
		end
	end
	return best
end

local function getAttackPosition(enemy)
	local ep = posOf(enemy)
	local myHrp = getHRP()
	if not ep or not myHrp then return nil end
	local delta = myHrp.Position - ep
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, 1)
	else
		flat = flat.Unit
	end
	return ep + flat * CONFIG.TeleportDistance + Vector3.new(0, 2, 0)
end

local function attack()
	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		local bp = player:FindFirstChildOfClass("Backpack")
		local t = bp and bp:FindFirstChildOfClass("Tool")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if t and hum then
			hum:EquipTool(t)
			tool = t
		end
	end
	if tool then pcall(function() tool:Activate() end) end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton1(Vector2.new(0, 0))
	end)
end

-- ===================== Infinite Attack =====================
local freezeStates = setmetatable({}, { __mode = "k" })

local function infiniteAttack(stageObj)
	if not CONFIG.InfiniteAttack then return 0 end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not hrp or not stageObj then return 0 end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local partsInBox = workspace:GetPartBoundsInBox(hrp.CFrame, CONFIG.InfiniteHitbox, overlapParams)
	local hitMonsters = {}
	local hitCount = 0

	for _, part in ipairs(partsInBox) do
		local monsterModel = part:FindFirstAncestorOfClass("Model")
		if monsterModel and not hitMonsters[monsterModel] then
			local monsterHumanoid = monsterModel:FindFirstChildOfClass("Humanoid")
			local monsterHrp = monsterModel:FindFirstChild("HumanoidRootPart")
			if monsterHumanoid and monsterHrp and monsterHumanoid.Health > 0
				and isEnemyInTargetStage(monsterModel, stageObj, CONFIG.EnemyRadius) then
				hitMonsters[monsterModel] = true
				hitCount += 1

				pcall(function()
					monsterHumanoid:TakeDamage(CONFIG.InfiniteDamage)
				end)

				local freeze = freezeStates[monsterModel]
				if not freeze then
					freeze = {
						oldSpeed = monsterHumanoid.WalkSpeed,
						oldAnchored = monsterHrp.Anchored,
						token = 0,
					}
					freezeStates[monsterModel] = freeze
				end
				freeze.token += 1
				local myToken = freeze.token

				pcall(function() monsterHumanoid.WalkSpeed = 0 end)
				pcall(function() monsterHrp.Anchored = true end)

				task.delay(CONFIG.FreezeDuration, function()
					local current = freezeStates[monsterModel]
					if current ~= freeze or current.token ~= myToken then return end

					if monsterHumanoid and monsterHumanoid.Parent and monsterHumanoid.Health > 0 then
						pcall(function() monsterHumanoid.WalkSpeed = current.oldSpeed end)
						if monsterHrp and monsterHrp.Parent then
							pcall(function() monsterHrp.Anchored = current.oldAnchored end)
						end
					end
					freezeStates[monsterModel] = nil
				end)
			end
		end
	end
	return hitCount
end

-- ===================== ปุ่ม Return =====================
local function getReturnButton()
	local ok, obj = pcall(function()
		return player.PlayerGui.Hud.Top.Return
	end)
	if not ok or not obj then return nil end
	if obj:IsA("GuiButton") then return obj end
	return obj:FindFirstChildWhichIsA("GuiButton", true) or obj
end

local function fireButton(btn)
	local used = false
	for _, sig in ipairs({ "MouseButton1Down", "MouseButton1Up", "MouseButton1Click", "Activated" }) do
		pcall(function()
			local signal = btn[sig]
			if firesignal then
				firesignal(signal)
				used = true
			elseif getconnections then
				for _, c in ipairs(getconnections(signal)) do c:Fire() end
				used = true
			end
		end)
	end
	return used
end

local function clickButton(btn)
	local ok, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
	if not ok or not VIM then return false end
	return pcall(function()
		local inset = GuiService:GetGuiInset()
		local sg = btn:FindFirstAncestorWhichIsA("ScreenGui")
		if sg and sg.IgnoreGuiInset then inset = Vector2.zero end
		local p = btn.AbsolutePosition + btn.AbsoluteSize / 2 + inset
		VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
		task.wait(0.05)
		VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 1)
	end)
end

local function movedFrom(startPos, timeout)
	local t = tick()
	while tick() - t < timeout do
		local hrp = getHRP()
		if hrp and (hrp.Position - startPos).Magnitude > CONFIG.ReturnMinMove then
			return true
		end
		task.wait(0.2)
	end
	return false
end

local function goReturn()
	local hrp = getHRP()
	if not hrp then return false end
	local startPos = hrp.Position

	local btn = getReturnButton()
	if btn then
		fireButton(btn)
		if movedFrom(startPos, CONFIG.ReturnWait) then return true end
		clickButton(btn)
		if movedFrom(startPos, CONFIG.ReturnWait) then return true end
		warn("[Return] กดแล้วตัวละครไม่ขยับ")
	else
		warn("[Return] ไม่พบ PlayerGui.Hud.Top.Return")
	end

	if CONFIG.ReturnFallbackSpawn then
		local sp = workspace:FindFirstChild("SpawnLocation")
		if sp then
			tpTo(posOf(sp) + Vector3.new(0, 5, 0))
			return true
		end
	end
	return false
end

-- ===================== GUI (ประกาศก่อนเพื่อให้ setStatus ใช้ได้) =====================
local statusLabel, infoLabel, targetBox
local function setStatus(t)
	State.status = t
	if statusLabel then statusLabel.Text = "สถานะ: " .. t end
end

local function ensureStage(n)
	local lastBest, same = nil, 0
	for _ = 1, 40 do
		if not (State.farming and State.alive) then return nil end
		local obj = AreaPart:FindFirstChild("Stage_" .. n)
		if obj then return obj end

		local list = getStages()
		if #list == 0 then return nil end
		local best
		for _, s in ipairs(list) do
			if not best or math.abs(s.num - n) < math.abs(best.num - n) then best = s end
		end

		if best.num == lastBest then
			same += 1
			if same >= 4 then
				setStatus(("ไม่พบ Stage %d"):format(n))
				return nil
			end
		else
			lastBest, same = best.num, 0
		end

		setStatus(("Stage %d ยังไม่โหลด → ไป Stage %d"):format(n, best.num))
		tpTo(stageWarpPos(best.obj))
		task.wait(1.2)
	end
	return nil
end

local function engage(enemy, stageObj)
	local t0 = tick()
	while State.farming and State.alive and enemy.Parent do
		local hum = enemy:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then break end
		if not isEnemyInTargetStage(enemy, stageObj, CONFIG.EnemyRadius) then break end

		local hrp, myHum = getHRP()
		if not hrp then break end
		local ep = posOf(enemy)
		if not ep then break end
		local dist = (hrp.Position - ep).Magnitude

		if CONFIG.InfiniteAttack then
			local maxHitDistance = math.max(CONFIG.InfiniteHitbox.X, CONFIG.InfiniteHitbox.Y, CONFIG.InfiniteHitbox.Z) / 2
			if dist > maxHitDistance then
				local safePos = getAttackPosition(enemy)
				if safePos then tpTo(safePos) end
			end

			local lookPos = posOf(enemy)
			if lookPos then
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(lookPos.X, hrp.Position.Y, lookPos.Z))
			end

			local hitCount = infiniteAttack(stageObj)
			if hitCount > 0 then setStatus(("Infinite Attack: โดน %d ตัว"):format(hitCount)) end
			if CONFIG.Loot and bagFull() then break end
			task.wait(CONFIG.InfiniteCooldown)
		else
			if dist > CONFIG.AttackRange then
				if CONFIG.WalkToEnemy and myHum and tick() - t0 < CONFIG.WalkTimeout then
					myHum:MoveTo(ep)
				else
					local safePos = getAttackPosition(enemy)
					if safePos then tpTo(safePos) end
				end
			else
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(ep.X, hrp.Position.Y, ep.Z))
			end
			attack()
			if CONFIG.Loot and bagFull() then break end
			task.wait(0.15)
		end
	end
end

local function farmStep()
	local hrp = getHRP()
	if not hrp then
		setStatus("รอตัวละคร...")
		task.wait(1)
		return
	end

	if bagFull() then
		resetCycle()
		setStatus("กระเป๋าเต็ม → กด Return")
		goReturn()
		task.wait(CONFIG.SpawnDelay)

		local t = tick()
		while State.farming and bagFull() and tick() - t < CONFIG.SpawnMaxWait do
			task.wait(0.3)
		end

		setStatus(("กลับไป Stage %d"):format(State.target))
		local obj = ensureStage(State.target)
		if obj then tpTo(stageWarpPos(obj)) end
		return
	end

	if CONFIG.Loot then
		local list = getLootList()
		if #list > 0 then
			local item = list[1]
			setStatus(("เก็บ %s (ราคา %s)"):format(item.ore.Name, tostring(item.price)))
			attempts[item.ore] = (attempts[item.ore] or 0) + 1
			if not pickup(item.ore) and attempts[item.ore] >= CONFIG.LootTries then
				blacklist[item.ore] = true
			end
			return
		end
	end

	local obj = ensureStage(State.target)
	if not obj then
		task.wait(1)
		return
	end

	local stagePos = posOf(obj)
	local enemy = findEnemy(obj, CONFIG.EnemyRadius)

	if enemy then
		resetCycle()
		setStatus(("ตีมอน %s"):format(enemy.Name))
		engage(enemy, obj)
		return
	end

	if not State.cleared then
		State.noEnemySince = State.noEnemySince or tick()
		if tick() - State.noEnemySince < CONFIG.ClearConfirm then
			setStatus(("เช็คมอนใน Stage %d..."):format(State.target))
			task.wait(0.3)
			return
		end

		setStatus(("มอน Stage %d ตายหมด → กด Return"):format(State.target))
		goReturn()
		task.wait(CONFIG.SpawnDelay)
		if not (State.farming and State.alive) then return end

		local o = ensureStage(State.target)
		if o then tpTo(stageWarpPos(o)) end
		State.cleared = true
		State.clearedAt = State.noEnemySince
		return
	end

	local elapsed = tick() - (State.clearedAt or tick())
	if elapsed >= CONFIG.RespawnGiveUp then
		State.cleared, State.noEnemySince = false, nil
		return
	end
	if (hrp.Position - stagePos).Magnitude > CONFIG.EnemyRadius then
		tpTo(stageWarpPos(obj))
	end
	setStatus(("รอมอนเกิดที่ Stage %d (เหลือ ~%d วิ)"):format(
		State.target, math.max(0, math.ceil(CONFIG.RespawnTime - elapsed))))
	task.wait(0.5)
end

task.spawn(function()
	while State.alive do
		if State.farming then
			local ok, err = pcall(farmStep)
			if not ok then
				warn("[AutoFarm] " .. tostring(err))
				task.wait(1)
			end
		else
			task.wait(0.3)
		end
	end
end)

-- Anti-AFK
local idleConn = player.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton1(Vector2.new(0, 0))
	end)
end)

-- ===================== [เพิ่มใหม่] ลูปสำหรับ Auto Heal =====================
task.spawn(function()
	while State.alive do
		if State.autoHeal then
			pcall(function()
				-- ดึงโฟลเดอร์ตามชื่อ aaoo626465 หรือชื่อตัวละครของคุณ
				local targetName = "aaoo626465"
				local playerFolder = workspace:FindFirstChild("PlayerFolder")
				
				if playerFolder then
					-- หาโฟลเดอร์ aaoo626465 หรือหาจากชื่อผู้เล่นปัจจุบันแทนเผื่อกรณีชื่อเปลี่ยน
					local myFolder = playerFolder:FindFirstChild(targetName) or playerFolder:FindFirstChild(player.Name)
					
					if myFolder then
						local hpValue = myFolder:FindFirstChild("Health")
						local maxHpValue = myFolder:FindFirstChild("MaxHealth")
						
						if hpValue and (hpValue:IsA("IntValue") or hpValue:IsA("NumberValue")) then
							-- เพิ่ม 50% ของ MaxHealth ถ้ามี หากไม่มีจะเพิ่ม 50% ของเลือดปัจจุบัน
							local increaseAmount = maxHpValue and (maxHpValue.Value * 0.5) or (hpValue.Value * 0.5)
							
							hpValue.Value = hpValue.Value + increaseAmount
							
							-- จำกัดเลือดไม่ให้เกิน Max (ถ้าอ้างอิง MaxHealth ได้)
							if maxHpValue and hpValue.Value > maxHpValue.Value then
								hpValue.Value = maxHpValue.Value
							end
						end
					end
				end
				
				-- สำรอง: กรณีฮีลเข้า Humanoid ปกติ (เผื่อเกมใช้คู่กัน)
				local char = player.Character
				if char then
					local hum = char:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
						hum.Health = math.min(hum.MaxHealth, hum.Health + (hum.MaxHealth * 0.5))
					end
				end
			end)
		end
		-- หน่วงเวลา 2 วินาที ตามที่คุณระบุ
		task.wait(2)
	end
end)

-- ============================================================
--                            GUI
-- ============================================================
local parent
pcall(function() parent = (gethui and gethui()) or game:GetService("CoreGui") end)
parent = parent or player:WaitForChild("PlayerGui")

local old = parent:FindFirstChild("StageWarpGUI")
if old then old:Destroy() end

local COL = {
	bg = Color3.fromRGB(30, 30, 38),
	top = Color3.fromRGB(45, 45, 58),
	btn = Color3.fromRGB(50, 50, 64),
	on = Color3.fromRGB(46, 160, 90),
	off = Color3.fromRGB(90, 90, 110),
	blue = Color3.fromRGB(60, 120, 200),
	red = Color3.fromRGB(200, 60, 60),
	text = Color3.fromRGB(230, 230, 240),
}

local function corner(o, r) Instance.new("UICorner", o).CornerRadius = UDim.new(0, r or 6) end

local gui = Instance.new("ScreenGui")
gui.Name = "StageWarpGUI"
gui.ResetOnSpawn = false
gui.Parent = parent

-- เพิ่มความสูง GUI เผื่อปุ่มฮีล
local FULL_H = 535 
local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(300, FULL_H)
main.Position = UDim2.new(0.5, -150, 0.5, -FULL_H / 2)
main.BackgroundColor3 = COL.bg
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 10)

-- แถบหัว
local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 34)
top.BackgroundColor3 = COL.top
top.BorderSizePixel = 0
top.Parent = main
corner(top, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Text = "Stage Warp + AutoFarm"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.new(1, 1, 1)
title.Parent = top

local function topButton(text, xOffset, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(26, 24)
	b.Position = UDim2.new(1, xOffset, 0, 5)
	b.BackgroundColor3 = color
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Parent = top
	corner(b)
	return b
end
local hideBtn = topButton("-", -64, COL.off)
local closeBtn = topButton("X", -32, COL.red)

-- เนื้อหา
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -34)
body.Position = UDim2.fromOffset(0, 34)
body.BackgroundTransparency = 1
body.Parent = main

local pad = Instance.new("UIPadding", body)
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 8)
pad.PaddingTop = UDim.new(0, 8)

local bodyLayout = Instance.new("UIListLayout", body)
bodyLayout.Padding = UDim.new(0, 5)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder

local order = 0
local function nextOrder() order += 1 return order end

local function makeLabel(text, h)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, h)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = COL.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.LayoutOrder = nextOrder()
	l.Parent = body
	return l
end

local function makeToggle(text, default, onText, offText, onChange)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 28)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.LayoutOrder = nextOrder()
	b.Parent = body
	corner(b)
	local state = default
	local function paint()
		b.BackgroundColor3 = state and COL.on or COL.off
		b.Text = text .. ": " .. (state and onText or offText)
	end
	b.MouseButton1Click:Connect(function()
		state = not state
		paint()
		onChange(state)
	end)
	paint()
	return b
end

local function makeInput(text, default, onChange)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundTransparency = 1
	row.LayoutOrder = nextOrder()
	row.Parent = body

	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0.55, 0, 1, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = COL.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = row

	local tb = Instance.new("TextBox")
	tb.Size = UDim2.new(0.45, 0, 1, 0)
	tb.Position = UDim2.new(0.55, 0, 0, 0)
	tb.BackgroundColor3 = COL.btn
	tb.Text = tostring(default)
	tb.Font = Enum.Font.Gotham
	tb.TextSize = 13
	tb.TextColor3 = Color3.new(1, 1, 1)
	tb.ClearTextOnFocus = false
	tb.BorderSizePixel = 0
	tb.Parent = row
	corner(tb)

	tb.FocusLost:Connect(function()
		local n = tonumber(tb.Text)
		if n then
			onChange(n)
		else
			tb.Text = tostring(default)
		end
	end)
	return tb
end

-- สถานะ
statusLabel = makeLabel("สถานะ: " .. State.status, 18)
infoLabel = makeLabel("-", 18)

-- ปุ่มเปิด/ปิด AutoFarm
makeToggle("AutoFarm", false, "เปิด", "ปิด", function(v)
	State.farming = v
	resetCycle()
	setStatus(v and "เริ่มฟาร์ม" or "หยุด")
end)

-- [เพิ่มใหม่] ปุ่มเปิด/ปิด Heal Mode
makeToggle("โหมดฮีล (เพิ่ม HP 50% ทุก 2 วิ)", false, "เปิด", "ปิด", function(v)
	State.autoHeal = v
	setStatus(v and "เปิดโหมดฮีล" or "ปิดโหมดฮีล")
end)

targetBox = makeInput("Stage เป้าหมาย", State.target, function(n)
	State.target = math.max(1, math.floor(n))
	targetBox.Text = tostring(State.target)
	resetCycle()
end)

makeInput("รัศมีหามอน (studs)", CONFIG.EnemyRadius, function(n)
	CONFIG.EnemyRadius = math.max(5, n)
end)

makeToggle("เก็บของ (ราคามาก→น้อย)", CONFIG.Loot, "เปิด", "ปิด", function(v) CONFIG.Loot = v end)
makeToggle("เข้าหามอน", CONFIG.WalkToEnemy, "เดิน", "วาป 10 studs", function(v) CONFIG.WalkToEnemy = v end)

makeToggle("Infinite Attack", CONFIG.InfiniteAttack, "เปิด (ไกล/ล็อก/ตีไว)", "ปิด", function(v)
	CONFIG.InfiniteAttack = v
	setStatus(v and "Infinite Attack เปิด" or "Infinite Attack ปิด")
end)

makeInput("ระยะวาปจากมอน (studs)", CONFIG.TeleportDistance, function(n)
	CONFIG.TeleportDistance = math.max(5, n)
end)

-- ปุ่มทดสอบกด Return
local testBtn = Instance.new("TextButton")
testBtn.Size = UDim2.new(1, 0, 0, 28)
testBtn.BackgroundColor3 = COL.blue
testBtn.Text = "ทดสอบกด Return"
testBtn.Font = Enum.Font.GothamMedium
testBtn.TextSize = 13
testBtn.TextColor3 = Color3.new(1, 1, 1)
testBtn.BorderSizePixel = 0
testBtn.LayoutOrder = nextOrder()
testBtn.Parent = body
corner(testBtn)
testBtn.MouseButton1Click:Connect(function()
	task.spawn(function()
		setStatus("ทดสอบกด Return...")
		local ok = goReturn()
		setStatus(ok and "Return สำเร็จ" or "Return ไม่สำเร็จ (ดู Output)")
	end)
end)

makeLabel("รายการ Stage (รีเฟรชทุก " .. CONFIG.RefreshInterval .. " วิ)", 16)

-- รายการ Stage
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 0, 140)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.LayoutOrder = nextOrder()
scroll.Parent = body

local scrollLayout = Instance.new("UIListLayout", scroll)
scrollLayout.Padding = UDim.new(0, 4)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder

local lastSig = ""
local function buildStageList(force)
	local stages = getStages()
	local names = {}
	for _, s in ipairs(stages) do names[#names + 1] = s.num end
	local sig = table.concat(names, ",")
	if sig == lastSig and not force then return end 
	lastSig = sig

	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	for _, s in ipairs(stages) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 28)
		row.BackgroundColor3 = COL.btn
		row.BorderSizePixel = 0
		row.LayoutOrder = s.num
		row.Parent = scroll
		corner(row)

		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(0.4, 0, 1, 0)
		l.Position = UDim2.fromOffset(8, 0)
		l.BackgroundTransparency = 1
		l.Text = "Stage " .. s.num
		l.Font = Enum.Font.Gotham
		l.TextSize = 13
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = row

		local function rowBtn(text, x, color)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0, 56, 0, 22)
			b.Position = UDim2.new(1, x, 0, 3)
			b.BackgroundColor3 = color
			b.Text = text
			b.Font = Enum.Font.GothamMedium
			b.TextSize = 12
			b.TextColor3 = Color3.new(1, 1, 1)
			b.BorderSizePixel = 0
			b.Parent = row
			corner(b, 5)
			return b
		end

		rowBtn("วาป", -122, COL.blue).MouseButton1Click:Connect(function()
			if s.obj.Parent then tpTo(stageWarpPos(s.obj)) end
		end)
		rowBtn("ฟาร์ม", -62, COL.on).MouseButton1Click:Connect(function()
			State.target = s.num
			targetBox.Text = tostring(s.num)
			resetCycle()
		end)
	end
end
buildStageList(true)

task.spawn(function()
	while State.alive do
		pcall(buildStageList)
		task.wait(CONFIG.RefreshInterval)
	end
end)

task.spawn(function()
	while State.alive do
		local c, m = getBag()
		local bag = c and (c .. "/" .. m) or "?"
		local loot = #getLootList()
		infoLabel.Text = ("กระเป๋า %s | ของดรอป %d | เป้าหมาย Stage %d"):format(bag, loot, State.target)
		task.wait(0.5)
	end
end)

local minimized = false
hideBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	body.Visible = not minimized
	main.Size = minimized and UDim2.fromOffset(300, 34) or UDim2.fromOffset(300, FULL_H)
	hideBtn.Text = minimized and "+" or "-"
end)

local conns = { idleConn }
closeBtn.MouseButton1Click:Connect(function()
	State.alive = false
	State.farming = false
	for _, c in ipairs(conns) do c:Disconnect() end
	gui:Destroy()
end)

table.insert(conns, UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
end))

local dragging, dragStart, startPos
top.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging, dragStart, startPos = true, input.Position, main.Position
	end
end)
table.insert(conns, UIS.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end))
table.insert(conns, UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end))