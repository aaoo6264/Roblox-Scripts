local Players       = game:GetService("Players")
local Workspace     = game:GetService("Workspace")

local player   = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- ⚙️ CONFIG
----------------------------------------------------------------
-- โครงสร้างที่ใช้ (2 ต้นไม้แยกกันเด็ดขาด ไม่ซ้อนกัน):
--
-- Workspace
--  ├─ Worlds
--  │   ├─ World_1
--  │   │   └─ Sell        <-- จุดวาปเข้าโลก (Part หรือ Model)
--  │   ├─ World_2
--  │   │   └─ Sell
--  │   └─ ...
--  └─ Zones
--      ├─ W1
--      │   ├─ Zone_1
--      │   │   └─ SpawnZone
--      │   │       └─ (ไอเทมต่างๆ)
--      │   └─ Zone_2
--      ├─ W2
--      └─ ... W6
--
local WORLDS_FOLDER_NAME = "Worlds"   -- โฟลเดอร์เก็บ World_1, World_2, ...
local ZONES_ROOT_NAME    = "Zones"    -- โฟลเดอร์เก็บ W1..W6 (แยกจาก Worlds เด็ดขาด)
local SELL_NAME          = "Sell"     -- ชื่อ Part/Model จุดวาปเข้าโลก อยู่ใต้ World_N โดยตรง
local ITEMS_FOLDER_NAME  = "SpawnZone" -- ชื่อโฟลเดอร์เก็บไอเทมในแต่ละ Zone_N

----------------------------------------------------------------
-- ⚙️ CRAFT RELICS CONFIG
----------------------------------------------------------------
-- โครงสร้าง: Workspace.Worlds.World_N.Craft_Table.Craft_Table
--                                                 └─ ShopOpenPrompt (ProximityPrompt)
--
-- หมายเหตุ: มีแค่โลกที่เรา "อยู่จริง" ตอนนี้เท่านั้นที่จะมีโฟลเดอร์ Craft_Table
-- โลกอื่นๆ (World_1, World_2, ...) จะไม่มีโฟลเดอร์นี้เลย ดังนั้นจึงใช้การไล่เช็ค
-- ทุกโลกว่าโลกไหนมี Craft_Table เพื่อสรุปว่าเราอยู่โลกนั้น (ไม่ต้องเดาจากตำแหน่งผู้เล่น)
local CRAFT_TABLE_FOLDER_NAME = "Craft_Table" -- ชื่อโฟลเดอร์ + ชื่อ Part/Model ข้างใน (ซ้อนชื่อเดียวกัน)
local SHOP_OPEN_PROMPT_NAME   = "ShopOpenPrompt" -- ชื่อ ProximityPrompt ที่ใช้เปิดเมนู Craft

-- โครงสร้างเมนู Craft (โผล่มาใน PlayerGui หลังเปิดผ่าน ShopOpenPrompt แล้วเท่านั้น):
-- PlayerGui.CraftRelicsGUI.CraftRelics.Background.ScrollingBg.ScrollingFrame   <-- รายการไอเทม Craft ได้
-- PlayerGui.CraftRelicsGUI.CraftRelics.Background.CraftMenu.LootContainer     <-- สูตร/วัตถุดิบของไอเทมที่เลือกอยู่
--   └─ RecipeLoot_01_<ชื่อวัตถุดิบ>.OpenFrame.Count  <-- ข้อความ "current/required" เช่น "0/2"
local CRAFT_GUI_NAME            = "CraftRelicsGUI"
local CRAFT_ROOT_NAME           = "CraftRelics"
local CRAFT_ITEM_LIST_PATH      = {"Background", "ScrollingBg", "ScrollingFrame"}
local CRAFT_GUI_WAIT_TIMEOUT    = 5 -- รอเมนู Craft / สูตร Craft เปิดสูงสุดกี่วินาที

----------------------------------------------------------------
-- ⚙️ AUTO FARM CONFIG
----------------------------------------------------------------
-- ไอเทมแต่ละชิ้นอาจเก็บ "ราคา" ไว้ในรูปแบบใดรูปแบบหนึ่งต่อไปนี้
-- (สคริปต์จะลองหาไล่ตามลำดับ ปรับชื่อให้ตรงกับเกมของคุณได้เลย)
local PRICE_ATTRIBUTE_NAMES   = {"Price", "Value", "Worth", "Cost", "Money"} -- ชื่อ Attribute บนตัวไอเทม
local PRICE_VALUEOBJECT_NAMES = {"Price", "Value", "Worth", "Cost", "Money"} -- ชื่อ NumberValue/IntValue ลูกของไอเทม

-- ชื่อ GUI ที่เก็บป้ายราคา (ตัวไอเทม -> LootGui -> Value(Text))
local LOOT_GUI_NAME      = "LootGui"
local LOOT_VALUE_NAME    = "Value"

-- ตารางแปลง "คำย่อค่าเงิน" -> ตัวคูณ (เรียงจากน้อยไปมาก)
-- K ใส่เผื่อไว้ด้วย (เผื่อบางไอเทมใช้ K) ส่วนที่เหลือตรงตามที่ระบุ
local SUFFIX_MULTIPLIERS = {
    [""]    = 1,
    ["K"]   = 1e3,
    ["M"]   = 1e6,
    ["B"]   = 1e9,
    ["T"]   = 1e12,
    ["Qa"]  = 1e15,
    ["Qi"]  = 1e18,
    ["Sx"]  = 1e21,
    ["Sp"]  = 1e24,
    ["Oc"]  = 1e27,
    ["No"]  = 1e30,
    ["Dc"]  = 1e33,
    ["Ud"]  = 1e36,
    ["Dd"]  = 1e39,
    ["Td"]  = 1e42,
    ["Qad"] = 1e45,
    ["Qid"] = 1e48,
    ["Sxd"] = 1e51,
    ["Spd"] = 1e54,
    ["Ocd"] = 1e57,
    ["Nod"] = 1e60,
    ["V"]   = 1e63,
}

----------------------------------------------------------------
-- Utility: แปลงข้อความค่าเงิน เช่น "$1.2M", "500K", "3.4Qa" -> number จริง
----------------------------------------------------------------
local function parseMoneyText(text)
    if type(text) ~= "string" then return nil end

    -- ตัดสัญลักษณ์ที่ไม่เกี่ยวข้องออก เช่น $, , (comma), เว้นวรรค, +
    local clean = text:gsub("[%$,%s%+]", "")
    if clean == "" then return nil end

    -- ดึงตัวเลข (รองรับทศนิยม) และตัวอักษรต่อท้าย (suffix) เช่น "1.25Qad"
    local numPart, suffix = clean:match("^(%-?%d+%.?%d*)(%a*)$")
    if not numPart then return nil end

    local num = tonumber(numPart)
    if not num then return nil end

    -- suffix ต้องตรงตัวพิมพ์เล็ก/ใหญ่ตามตารางเป๊ะๆ (กันชนกัน เช่น Qa กับ Qad)
    local mult = SUFFIX_MULTIPLIERS[suffix]
    if not mult then
        -- ไม่รู้จัก suffix นี้ -> ลองเทียบแบบไม่สนตัวพิมพ์เล็กใหญ่เป็นทางเลือกสุดท้าย
        for key, value in pairs(SUFFIX_MULTIPLIERS) do
            if key ~= "" and key:lower() == suffix:lower() then
                mult = value
                break
            end
        end
    end
    if not mult then return nil end -- suffix ไม่รู้จักจริงๆ -> ไม่ใช้ค่านี้

    return num * mult
end

----------------------------------------------------------------
-- Utility: ดึงราคาจาก item -> LootGui -> Value (Text) โดยตรง
----------------------------------------------------------------
local function getValueFromLootGui(item)
    local lootGui = item:FindFirstChild(LOOT_GUI_NAME, true)
    if not lootGui then return nil end

    local valueObj = lootGui:FindFirstChild(LOOT_VALUE_NAME, true)
    if not valueObj then return nil end

    local text
    if valueObj:IsA("TextLabel") or valueObj:IsA("TextButton") or valueObj:IsA("TextBox") then
        text = valueObj.Text
    elseif valueObj:IsA("StringValue") then
        text = valueObj.Value
    end

    if not text then return nil end
    return parseMoneyText(text)
end

local AUTO_FARM_POST_COLLECT_DELAY = 0.5  -- ดีเลย์ (วินาที) หลังเก็บของ 1 ชิ้น ก่อนวาปไปชิ้นถัดไป
local AUTO_FARM_COLLECT_TIMEOUT    = 3   -- รอสูงสุดกี่วินาทีให้ไอเทมหายไป (ถือว่าเก็บสำเร็จ) ก่อนไปต่อ
local AUTO_FARM_RESCAN_INTERVAL    = 1   -- ถ้าไม่พบไอเทมเลย รอกี่วินาทีก่อนสแกนใหม่

local AUTO_FARM_CHECK_BACKPACK_INTERVAL = 0.15 -- ตรวจสอบกระเป๋าทุกกี่วินาที
local AUTO_FARM_RETURN_WAIT             = 1    -- รอหลังวาปกลับฐาน ก่อนเริ่มฟาร์มต่อ

local CRAFT_FARM_CHECK_INTERVAL      = 1   -- วินาที: ถ้าไม่ได้เก็บอะไรเลยรอบนี้ รอกี่วินาทีก่อนเช็ค/ลองใหม่
local CRAFT_FARM_POST_COLLECT_DELAY  = 0.5 -- วินาที: ดีเลย์หลังเก็บวัตถุดิบ 1 ชิ้น ก่อนไปชิ้นถัดไป

----------------------------------------------------------------
-- Backpack / Return To Spawn
--
-- GUI ที่ใช้ตรวจสอบ:
-- PlayerGui.MainScreenGui.Currencies.Backpack
--
-- ภายใน Backpack อาจมี TextLabel/TextButton/TextBox ที่แสดง
-- จำนวนของในกระเป๋า เช่น 10/10, 10 / 10 หรือข้อความว่า Full/เต็ม
--
-- เมื่อพบว่ากระเป๋าเต็ม:
-- ReplicatedStorage.Packages._Index["acecateer_knit@1.7.2"]
--   .knit.Services.BaseTeleportService.RF.TeleportToSpawn
----------------------------------------------------------------
local function getBackpackGui()
    local mainScreenGui = playerGui:FindFirstChild("MainScreenGui")
    if not mainScreenGui then
        return nil
    end

    local currencies = mainScreenGui:FindFirstChild("Currencies")
    if not currencies then
        return nil
    end

    return currencies:FindFirstChild("Backpack")
end

local function getBackpackText(backpack)
    if not backpack then
        return nil
    end

    -- ถ้า Backpack เองมี Text property
    if backpack:IsA("TextLabel")
        or backpack:IsA("TextButton")
        or backpack:IsA("TextBox") then
        return backpack.Text
    end

    -- ถ้ามี Value ที่เป็น GUI object ให้ลองอ่าน Text
    for _, obj in ipairs(backpack:GetDescendants()) do
        if obj:IsA("TextLabel")
            or obj:IsA("TextButton")
            or obj:IsA("TextBox") then
            if obj.Text and obj.Text ~= "" then
                return obj.Text
            end
        end
    end

    return nil
end

local function isBackpackFull()
    local backpack = getBackpackGui()
    if not backpack then
        return false
    end

    local text = getBackpackText(backpack)
    if type(text) ~= "string" then
        return false
    end

    local lower = text:lower()

    -- รองรับข้อความตรงๆ ที่เกมอาจใช้บอกว่ากระเป๋าเต็ม
    if lower:find("full", 1, true)
        or lower:find("เต็ม", 1, true)
        or lower:find("max", 1, true) then
        return true
    end

    -- รองรับรูปแบบจำนวน เช่น 10/10, 10 / 10, 10/10 Items
    local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
    if current and maximum then
        return tonumber(current) >= tonumber(maximum)
    end

    -- รองรับรูปแบบเช่น "10 of 10"
    current, maximum = text:match("(%d+)%s*[Oo][Ff]%s*(%d+)")
    if current and maximum then
        return tonumber(current) >= tonumber(maximum)
    end

    return false
end

local function teleportToSpawn()
    local ok, result = pcall(function()
        local replicatedStorage = game:GetService("ReplicatedStorage")
        local packages = replicatedStorage:WaitForChild("Packages", 5)
        local index = packages and packages:WaitForChild("_Index", 5)
        local knitPackage = index and index:WaitForChild("acecateer_knit@1.7.2", 5)
        local knit = knitPackage and knitPackage:WaitForChild("knit", 5)
        local services = knit and knit:WaitForChild("Services", 5)
        local baseTeleportService = services and services:WaitForChild("BaseTeleportService", 5)
        local rf = baseTeleportService and baseTeleportService:WaitForChild("RF", 5)
        local teleportRemote = rf and rf:WaitForChild("TeleportToSpawn", 5)

        if not teleportRemote then
            error("ไม่พบ BaseTeleportService.RF.TeleportToSpawn")
        end

        return teleportRemote:InvokeServer()
    end)

    if not ok then
        warn("[Auto Farm] วาปกลับฐานไม่สำเร็จ: " .. tostring(result))
        return false
    end

    return true
end

local refreshAutoFarmButton -- forward declare (ตัวจริงถูกกำหนดค่าด้านล่าง หลัง UI ถูกสร้าง)
local openCraftPanel -- forward declare (ตัวจริงถูกกำหนดค่าด้านล่าง หลัง Craft Panel UI ถูกสร้าง)

local function checkBackpackAndReturnIfFull()
    if not isBackpackFull() then
        return false
    end

    refreshAutoFarmButton("กระเป๋าเต็ม → กำลังกลับฐาน")

    if teleportToSpawn() then
        task.wait(AUTO_FARM_RETURN_WAIT)
        refreshAutoFarmButton("กลับฐานแล้ว → เริ่มฟาร์มต่อ")
    else
        task.wait(1)
    end

    return true
end

----------------------------------------------------------------
-- ค้นหา Workspace.Worlds และ Workspace.Zones (คนละต้นไม้กัน)
----------------------------------------------------------------
local worldsRoot = Workspace:WaitForChild(WORLDS_FOLDER_NAME)
local zonesRoot  = Workspace:WaitForChild(ZONES_ROOT_NAME)

----------------------------------------------------------------
-- Utility: แปลง Part/Model ให้ได้ BasePart ที่ใช้อ้าง CFrame ได้
----------------------------------------------------------------
local function toBasePart(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

----------------------------------------------------------------
-- Utility: อ่านราคา/มูลค่าของไอเทม (ลองหลายรูปแบบตาม CONFIG ด้านบน)
----------------------------------------------------------------
local function getItemValue(item)
    -- 0) ลองอ่านจาก LootGui -> Value (ข้อความค่าเงิน เช่น "1.2M", "500K") ก่อนเป็นอันดับแรก
    local lootValue = getValueFromLootGui(item)
    if lootValue then
        return lootValue
    end

    -- 1) ลองหาใน Attribute ของตัวไอเทมเอง
    for _, attrName in ipairs(PRICE_ATTRIBUTE_NAMES) do
        local v = item:GetAttribute(attrName)
        if type(v) == "number" then
            return v
        end
    end

    -- 2) ลองหา NumberValue/IntValue ที่เป็นลูกของไอเทม
    for _, objName in ipairs(PRICE_VALUEOBJECT_NAMES) do
        local obj = item:FindFirstChild(objName)
        if obj and (obj:IsA("NumberValue") or obj:IsA("IntValue")) then
            return obj.Value
        end
    end

    -- 3) ลองหา Attribute/ValueObject จากลูกหลานทั้งหมด (เผื่อซ้อนอยู่ลึก)
    for _, d in ipairs(item:GetDescendants()) do
        if d:IsA("NumberValue") or d:IsA("IntValue") then
            for _, objName in ipairs(PRICE_VALUEOBJECT_NAMES) do
                if d.Name == objName then
                    return d.Value
                end
            end
        end
    end

    -- ไม่พบราคา -> ไม่รู้มูลค่า
    return nil
end

----------------------------------------------------------------
-- หา PickupPrompt ของไอเทม
--
-- โครงสร้างของทุกไอเทม:
-- ItemName
--   └─ Base
--       └─ PickupPromptAttachment
--           └─ PickupPrompt
--
-- ใช้ PickupPrompt ตัวนี้ในการเก็บไอเทมทุกชิ้น
----------------------------------------------------------------
local function getPickupPrompt(item)
    if not item then return nil end

    local base = item:FindFirstChild("Base")
    if not base then
        return nil
    end

    local attachment = base:FindFirstChild("PickupPromptAttachment")
    if not attachment then
        return nil
    end

    local prompt = attachment:FindFirstChild("PickupPrompt")
    if prompt and prompt:IsA("ProximityPrompt") then
        return prompt
    end

    return nil
end

----------------------------------------------------------------
-- เรียกใช้ PickupPrompt เพื่อเก็บไอเทม
--
-- วิธีหลัก: fireproximityprompt
-- Fallback: InputHoldBegin / InputHoldEnd
----------------------------------------------------------------
local function collectItem(item)
    local prompt = getPickupPrompt(item)

    if not prompt then
        warn("[Auto Farm] ไม่พบ PickupPrompt ของ: " .. (item and item:GetFullName() or "nil"))
        return false
    end

    if not prompt.Enabled then
        warn("[Auto Farm] PickupPrompt ถูกปิดอยู่: " .. item.Name)
        return false
    end

    local fired = false

    if typeof(fireproximityprompt) == "function" then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)

        if ok then
            fired = true
        end
    end

    if not fired then
        local ok = pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.max(prompt.HoldDuration, 0.05))
            prompt:InputHoldEnd()
        end)

        fired = ok
    end

    return fired
end

----------------------------------------------------------------
-- ฟังก์ชันเทเลพอร์ตไปยังไอเทม
----------------------------------------------------------------
local function teleportToItem(item)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    if not hrp then return false end

    local targetCFrame
    if item:IsA("Model") then
        targetCFrame = item:GetPivot()
    elseif item:IsA("BasePart") then
        targetCFrame = item.CFrame
    end

    if targetCFrame then
        hrp.CFrame = targetCFrame + Vector3.new(0, 3, 0)
        return true
    end

    return false
end

----------------------------------------------------------------
-- เทเลพอร์ตไปหาไอเทม + เรียก PickupPrompt
----------------------------------------------------------------
local function teleportAndCollectItem(item)
    if not item or not item.Parent then
        return false
    end

    local teleported = teleportToItem(item)
    if not teleported then
        return false
    end

    task.wait(0.15)

    if not item.Parent then
        return true
    end

    return collectItem(item)
end

----------------------------------------------------------------
-- รวบรวมไอเทมทั้งหมดจากทุก Zone ใน Workspace.Zones (W1..W6 -> Zone_N -> SpawnZone)
----------------------------------------------------------------
local function getAllItems()
    local items = {}
    for _, wFolder in ipairs(zonesRoot:GetChildren()) do
        if wFolder.Name:match("^[Ww]%d+$") then
            for _, zone in ipairs(wFolder:GetChildren()) do
                local spawnZone = zone:FindFirstChild(ITEMS_FOLDER_NAME)
                if spawnZone then
                    for _, item in ipairs(spawnZone:GetChildren()) do
                        if item:IsA("Model") or item:IsA("BasePart") then
                            table.insert(items, item)
                        end
                    end
                end
            end
        end
    end
    return items
end

----------------------------------------------------------------
-- หาไอเทมที่มีมูลค่า (ราคา) สูงสุดในตอนนี้ จากไอเทมทั้งหมดที่มีอยู่
-- คืนค่า: item, value  (item เป็น nil ถ้าไม่พบไอเทมที่มีราคาเลย)
----------------------------------------------------------------
local function findMostValuableItem()
    local items = getAllItems()
    local bestItem, bestValue = nil, -math.huge

    for _, item in ipairs(items) do
        local value = getItemValue(item)
        if value and value > bestValue then
            bestItem = item
            bestValue = value
        end
    end

    return bestItem, bestItem and bestValue or nil
end

----------------------------------------------------------------
-- หาจุด "Sell" ของโลกหนึ่งๆ ไว้ใช้เดาว่าผู้เล่นอยู่โลกไหน และไว้วาปเข้าโลก
-- (ค้นเฉพาะภายใน worldFolder เท่านั้น ไม่ยุ่งกับ Zones เลย)
----------------------------------------------------------------
local function getWorldSellPart(worldFolder)
    local sell = worldFolder:FindFirstChild(SELL_NAME, true)
    local part = toBasePart(sell)
    if part then return part end

    -- กันพัง: ถ้าโลกนี้ยังไม่มี Sell ให้ fallback ไปหา BasePart แรกที่เจอ
    -- (กันไม่ให้ปุ่มโลกกดแล้วไม่มีอะไรเกิดขึ้นเลย)
    for _, d in ipairs(worldFolder:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function teleportToWorld(worldFolder)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    if not hrp then return end

    local sellPart = getWorldSellPart(worldFolder)
    if sellPart then
        hrp.CFrame = sellPart.CFrame + Vector3.new(0, 4, 0)
    else
        warn("[Teleport GUI] ไม่พบจุด '" .. SELL_NAME .. "' ใน " .. worldFolder:GetFullName())
    end
end

----------------------------------------------------------------
-- หา Craft_Table ของ "โลกที่เราอยู่ตอนนี้"
--
-- ไล่เช็คทุกโลกใน Workspace.Worlds ว่าโลกไหนมีโฟลเดอร์ Craft_Table อยู่บ้าง
-- (เฉพาะโลกที่เรา spawn เข้าไปจริงๆ เท่านั้นที่จะมีโฟลเดอร์นี้โผล่มา)
-- เจอโลกไหนมีก่อน ถือว่าโลกนั้นคือโลกปัจจุบัน แล้วคืนค่า:
--   craftTablePart  -> BasePart ของ Craft_Table (ใช้วาปไปหา)
--   shopOpenPrompt  -> ProximityPrompt ใต้ craftTablePart (ใช้เปิดเมนู Craft)
--   worldFolder     -> โฟลเดอร์ World_N ที่เจอ (ไว้ debug/แจ้งเตือน)
----------------------------------------------------------------
local function findActiveCraftTable()
    for _, worldFolder in ipairs(worldsRoot:GetChildren()) do
        local craftTableFolder = worldFolder:FindFirstChild(CRAFT_TABLE_FOLDER_NAME)
        if craftTableFolder then
            -- โครงสร้างซ้อนชื่อเดียวกัน: Craft_Table (โฟลเดอร์/โมเดล) -> Craft_Table (Part/โมเดลจริง)
            local craftTableInst = craftTableFolder:FindFirstChild(CRAFT_TABLE_FOLDER_NAME)
            local part = toBasePart(craftTableInst)

            if part then
                local prompt = part:FindFirstChild(SHOP_OPEN_PROMPT_NAME, true)
                return part, prompt, worldFolder
            end
        end
    end

    return nil, nil, nil
end

----------------------------------------------------------------
-- Auto Craft Relics
-- วาปไปจุด Craft_Table ของโลกที่เราอยู่ตอนนี้ แล้วเปิดเมนู Craft
-- ผ่าน ShopOpenPrompt (fireproximityprompt, fallback InputHoldBegin/End)
----------------------------------------------------------------
----------------------------------------------------------------
-- ยิง ShopOpenPrompt ตรงๆ (ไม่สน ตัวละครอยู่ใกล้จริงหรือไม่) เพื่อเปิดเมนู Craft
----------------------------------------------------------------
local function fireShopOpenPrompt(shopPrompt)
    if not shopPrompt then return false end

    if not shopPrompt.Enabled then
        warn("[Auto Craft Relics] " .. SHOP_OPEN_PROMPT_NAME .. " ถูกปิดอยู่")
        return false
    end

    if typeof(fireproximityprompt) == "function" then
        local ok = pcall(function()
            fireproximityprompt(shopPrompt)
        end)
        if ok then return true end
    end

    local ok = pcall(function()
        shopPrompt:InputHoldBegin()
        task.wait(math.max(shopPrompt.HoldDuration, 0.05))
        shopPrompt:InputHoldEnd()
    end)

    return ok
end

----------------------------------------------------------------
-- เปิดเมนู Craft โดย "ไม่วาปตัวละคร" ไปที่โต๊ะก่อน (ยิง ShopOpenPrompt ตรงๆ เฉยๆ)
-- ใช้ตอนแค่อยากดูรายการไอเทมที่ Craft ได้ก่อน ยังไม่ได้ตัดสินใจว่าจะ Craft อันไหน
----------------------------------------------------------------
local function openCraftMenuWithoutTeleport()
    local craftPart, shopPrompt, worldFolder = findActiveCraftTable()

    if not craftPart then
        warn("[Auto Craft Relics] ไม่พบ Craft_Table ในโลกไหนเลย (อาจยังไม่ได้อยู่ในโลกที่มี Craft_Table)")
        return false
    end

    if not shopPrompt then
        warn("[Auto Craft Relics] พบ Craft_Table (" .. worldFolder.Name .. ") แต่ไม่พบ " .. SHOP_OPEN_PROMPT_NAME)
        return false
    end

    return fireShopOpenPrompt(shopPrompt)
end

----------------------------------------------------------------
-- วาปตัวละครไปที่โต๊ะ Craft ของโลกปัจจุบัน แล้วเปิดเมนู Craft
-- (ใช้ตอนจะ Craft ไอเทมที่เลือกไว้จริงๆ เท่านั้น)
----------------------------------------------------------------
local function autoCraftRelics()
    local craftPart, shopPrompt, worldFolder = findActiveCraftTable()

    if not craftPart then
        warn("[Auto Craft Relics] ไม่พบ Craft_Table ในโลกไหนเลย (อาจยังไม่ได้อยู่ในโลกที่มี Craft_Table)")
        return false
    end

    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    if not hrp then
        return false
    end

    hrp.CFrame = craftPart.CFrame + Vector3.new(0, 3, 0)
    task.wait(0.15)

    if not shopPrompt then
        warn("[Auto Craft Relics] วาปถึง Craft_Table แล้ว (" .. worldFolder.Name .. ") แต่ไม่พบ " .. SHOP_OPEN_PROMPT_NAME)
        return false
    end

    return fireShopOpenPrompt(shopPrompt)
end

----------------------------------------------------------------
-- Craft Relics GUI: Utility เดินตามลูกทีละชั้นตาม path ที่กำหนด
----------------------------------------------------------------
local function getDescendantByPath(root, pathTable)
    local current = root
    for _, childName in ipairs(pathTable) do
        if not current then return nil end
        current = current:FindFirstChild(childName)
    end
    return current
end

----------------------------------------------------------------
-- หา ScreenGui ของเมนู Craft Relics (ต้องเปิดเมนูค้างอยู่ก่อนถึงจะเจอ)
----------------------------------------------------------------
local function getCraftRelicsGui()
    return playerGui:FindFirstChild(CRAFT_GUI_NAME)
end

-- รอจนกว่าเมนู Craft จะเปิดขึ้นมาจริงๆ (หลังยิง ShopOpenPrompt ไปแล้ว)
local function waitForCraftRelicsGui(timeout)
    timeout = timeout or CRAFT_GUI_WAIT_TIMEOUT
    local start = os.clock()
    local gui = getCraftRelicsGui()
    while not gui and (os.clock() - start) < timeout do
        task.wait(0.1)
        gui = getCraftRelicsGui()
    end
    return gui
end

----------------------------------------------------------------
-- หา ScrollingFrame รายการไอเทมของเมนู Craft
----------------------------------------------------------------
local function getCraftItemListFrame()
    local gui = getCraftRelicsGui()
    if not gui then return nil end
    local root = gui:FindFirstChild(CRAFT_ROOT_NAME)
    if not root then return nil end
    return getDescendantByPath(root, CRAFT_ITEM_LIST_PATH)
end

----------------------------------------------------------------
-- หา CraftMenu.LootContainer (โผล่มาก็ต่อเมื่อเรากดเลือกไอเทมในเมนู Craft แล้ว)
-- ข้างในมี RecipeLoot_01_<ชื่อวัตถุดิบ>, RecipeLoot_02_<ชื่อวัตถุดิบ>, ...
----------------------------------------------------------------
local function getCraftMenuFrame()
    local gui = getCraftRelicsGui()
    if not gui then return nil end
    local root = gui:FindFirstChild(CRAFT_ROOT_NAME)
    if not root then return nil end
    local background = root:FindFirstChild("Background")
    if not background then return nil end
    return background:FindFirstChild("CraftMenu")
end

local function getRecipeLootContainer()
    local craftMenu = getCraftMenuFrame()
    if not craftMenu then return nil end
    return craftMenu:FindFirstChild("LootContainer")
end

----------------------------------------------------------------
-- ดึงข้อความที่แสดงจริงของปุ่ม/การ์ด (ลองหา TextLabel/TextButton ลูกก่อน
-- ถ้าไม่เจอค่อย fallback ไปใช้ชื่อ Instance)
----------------------------------------------------------------
local function getDisplayText(inst)
    local textChild = inst:FindFirstChildWhichIsA("TextLabel", true)
        or inst:FindFirstChildWhichIsA("TextButton", true)
    if textChild and textChild.Text and textChild.Text ~= "" then
        return textChild.Text
    end
    return inst.Name
end

----------------------------------------------------------------
-- คลิกปุ่ม GUI จริงในเกม (ใช้ firesignal ถ้า executor รองรับ, ไม่งั้น fallback
-- เป็นการจำลองคลิกเมาส์จริงตรงกลางปุ่มผ่าน VirtualInputManager)
----------------------------------------------------------------
local function clickGuiButton(btn)
    if not btn then return false end

    if typeof(firesignal) == "function" and btn:IsA("GuiButton") then
        local ok = pcall(function()
            firesignal(btn.MouseButton1Click)
        end)
        if ok then return true end

        ok = pcall(function()
            firesignal(btn.Activated)
        end)
        if ok then return true end
    end

    local ok = pcall(function()
        local virtualInput = game:GetService("VirtualInputManager")
        local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2
        virtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
        task.wait()
        virtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    end)

    return ok
end

----------------------------------------------------------------
-- แปลงข้อความ Count เช่น "0/2" -> current=0, required=2
----------------------------------------------------------------
local function parseRequirementText(text)
    if type(text) ~= "string" then return nil, nil end
    local current, required = text:match("(%d+)%s*/%s*(%d+)")
    if current and required then
        return tonumber(current), tonumber(required)
    end
    return nil, nil
end

----------------------------------------------------------------
-- อ่านสูตร Craft ของไอเทมที่เลือกอยู่ตอนนี้ จาก CraftMenu.LootContainer
-- (โผล่มาก็ต่อเมื่อเรากดเลือกไอเทมในเมนู Craft ของเกมแล้วเท่านั้น)
-- คืนค่าเป็น array ของ {instance, itemName, current, required}
----------------------------------------------------------------
local function getRecipeRequirements()
    local container = getRecipeLootContainer()
    if not container then return {} end

    local requirements = {}
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("GuiObject") and child.Name:match("^RecipeLoot_") then
            local rawName = child.Name:match("^RecipeLoot_%d+_(.+)$") or child.Name
            local openFrame = child:FindFirstChild("OpenFrame")
            local countInst = openFrame and openFrame:FindFirstChild("Count")
            local text = countInst and countInst.Text

            local current, required = parseRequirementText(text)
            if required then
                table.insert(requirements, {
                    instance = child,
                    itemName = rawName:gsub("_", " "),
                    current = current or 0,
                    required = required,
                })
            end
        end
    end
    return requirements
end

----------------------------------------------------------------
-- เทียบชื่อไอเทมแบบไม่สนช่องว่าง/ขีดล่าง/ตัวพิมพ์เล็กใหญ่
-- (ชื่อวัตถุดิบในสูตร Craft อาจเขียนคนละรูปแบบกับชื่อไอเทมจริงใน SpawnZone)
----------------------------------------------------------------
local function normalizeItemName(s)
    return (s or ""):lower():gsub("[%s_]", "")
end

----------------------------------------------------------------
-- หาไอเทมที่วางอยู่ในโลกตอนนี้ (จาก getAllItems) ที่ชื่อตรงกับวัตถุดิบที่ต้องการ
----------------------------------------------------------------
local function findFarmableItemsByName(name)
    local target = normalizeItemName(name)
    local matches = {}
    for _, item in ipairs(getAllItems()) do
        if normalizeItemName(item.Name) == target then
            table.insert(matches, item)
        end
    end
    return matches
end

----------------------------------------------------------------
-- ดึงรายการไอเทมที่ Craft ได้ตอนนี้ (ตามตัวกรองที่เลือกอยู่ในเกม)
-- คืนค่าเป็น array ของ {instance = GuiObject, name = string}
----------------------------------------------------------------
local function getCraftableItemEntries()
    local listFrame = getCraftItemListFrame()
    if not listFrame then return {} end

    local entries = {}
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("GuiObject") and child.Visible then
            table.insert(entries, {
                instance = child,
                name = getDisplayText(child),
            })
        end
    end
    return entries
end

----------------------------------------------------------------
-- เลือก/กด Craft ไอเทมที่เลือกไว้ (คลิกการ์ดไอเทมนั้นในเมนู Craft จริง)
----------------------------------------------------------------
local function craftSelectedItem(entry)
    if not entry or not entry.instance or not entry.instance.Parent then
        warn("[Auto Craft Relics] ไอเทมที่เลือกไม่มีอยู่แล้ว (เมนูอาจถูกปิด/รีเฟรชไปแล้ว)")
        return false
    end

    if entry.instance:IsA("GuiButton") then
        return clickGuiButton(entry.instance)
    end

    local innerBtn = entry.instance:FindFirstChildWhichIsA("TextButton", true)
        or entry.instance:FindFirstChildWhichIsA("ImageButton", true)
    if innerBtn then
        return clickGuiButton(innerBtn)
    end

    warn("[Auto Craft Relics] ไม่พบปุ่มกดใน '" .. entry.name .. "'")
    return false
end

----------------------------------------------------------------
-- เลือกไอเทมที่จะ Craft "ตามชื่อ" (ไม่ใช่ Instance เก่าที่อาจค้าง/เพี้ยนไปแล้ว)
--
-- ลำดับการทำงาน (ตามที่ต้องการ): เลือกชื่อไอเทมไว้ก่อน -> ค่อยวาปไปโต๊ะ Craft
-- + เปิดร้านใหม่เสมอ (กันกรณีเดินออกนอกระยะระหว่างเลือก/farm วัตถุดิบไอเทมก่อนหน้า)
-- -> สแกนรายการไอเทมในเมนู Craft ใหม่ทั้งหมด -> หาตัวที่ชื่อตรงกับที่เลือกไว้
-- -> คลิก (เสมือนใช้เมาส์กด) ไอเทมนั้นในเมนู Craft จริง เพื่อให้ตารางคราฟ (สูตร) โชว์ขึ้นมา
-- -> รอให้ตารางคราฟโผล่ แล้วอ่านวัตถุดิบที่ต้องใช้ทั้งหมด
--
-- คืนค่า: ok (boolean), requirements (array หรือ nil), errorText (string หรือ nil)
----------------------------------------------------------------
local function openCraftItemAndGetRequirements(itemName)
    local teleportOk = autoCraftRelics()
    if not teleportOk then
        return false, nil, "วาปไปโต๊ะ Craft / เปิดเมนูไม่สำเร็จ"
    end

    waitForCraftRelicsGui()

    -- สแกนรายการไอเทมใหม่ทั้งหมด (ห้ามใช้ Instance เก่าที่เก็บไว้ก่อนหน้า เพราะเมนูอาจถูกปิด/เปิดใหม่)
    local entries = getCraftableItemEntries()
    local target = normalizeItemName(itemName)
    local matchedEntry = nil

    for _, e in ipairs(entries) do
        if normalizeItemName(e.name) == target then
            matchedEntry = e
            break
        end
    end

    if not matchedEntry then
        return false, nil, "ไม่พบไอเทม '" .. itemName .. "' ในเมนู Craft ตอนนี้"
    end

    local clicked = craftSelectedItem(matchedEntry)
    if not clicked then
        return false, nil, "กดเลือกไอเทม '" .. itemName .. "' ไม่สำเร็จ"
    end

    -- รอให้ตารางคราฟ (LootContainer) โผล่ขึ้นมาหลังกดเลือกไอเทม
    local requirements = {}
    local start = os.clock()
    while (os.clock() - start) < CRAFT_GUI_WAIT_TIMEOUT do
        requirements = getRecipeRequirements()
        if #requirements > 0 then break end
        task.wait(0.15)
    end

    if #requirements == 0 then
        return false, nil, "ไม่พบสูตร/วัตถุดิบของ '" .. itemName .. "'"
    end

    return true, requirements, nil
end

----------------------------------------------------------------
-- สแกนหาโลกทั้งหมดใน Workspace.Worlds
----------------------------------------------------------------
local function getSortedWorlds()
    local list = {}
    for _, child in ipairs(worldsRoot:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            local numStr = child.Name:match("(%d+)")
            table.insert(list, {
                instance = child,
                index = numStr and tonumber(numStr) or 9999,
                name = child.Name,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.index ~= b.index then return a.index < b.index end
        return a.name < b.name
    end)
    return list
end

----------------------------------------------------------------
-- สแกนหา W1, W2, ... ใน Workspace.Zones โดยตรง
-- (ไม่ขึ้นกับ World ที่เลือกอีกต่อไป เพราะ Zones แยกต้นไม้จาก Worlds)
----------------------------------------------------------------
local function getSortedWFolders()
    local list = {}
    for _, child in ipairs(zonesRoot:GetChildren()) do
        local numStr = child.Name:match("^[Ww](%d+)$")
        if numStr then
            table.insert(list, {
                instance = child,
                index = tonumber(numStr),
                name = child.Name,
            })
        end
    end
    table.sort(list, function(a, b) return a.index < b.index end)
    return list
end

----------------------------------------------------------------
-- สแกนหา Zone_1, Zone_2, ... ภายใน W1/W2 หนึ่งๆ
----------------------------------------------------------------
local function getSortedStages(wFolder)
    local list = {}
    for _, child in ipairs(wFolder:GetChildren()) do
        local numStr = child.Name:match("^Zone_(%d+)$")
        if numStr then
            table.insert(list, {
                instance = child,
                index = tonumber(numStr),
                name = child.Name,
            })
        end
    end
    table.sort(list, function(a, b) return a.index < b.index end)
    return list
end

----------------------------------------------------------------
-- เดาว่าผู้เล่นอยู่โลกไหน (จากระยะห่างไปยังจุด Sell ของแต่ละโลก)
----------------------------------------------------------------
local function detectCurrentWorld(worlds)
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp or #worlds == 0 then
        return worlds[1]
    end

    local best, bestDist = worlds[1], math.huge
    for _, w in ipairs(worlds) do
        local sellPart = getWorldSellPart(w.instance)
        if sellPart then
            local d = (sellPart.Position - hrp.Position).Magnitude
            if d < bestDist then
                bestDist = d
                best = w
            end
        end
    end
    return best
end

----------------------------------------------------------------
-- สร้าง GUI
----------------------------------------------------------------
----------------------------------------------------------------
-- Auto Farm: State
----------------------------------------------------------------
local autoFarmEnabled = false -- true = กำลังฟาร์มอัตโนมัติอยู่

local old = playerGui:FindFirstChild("WorldZoneTeleportGUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WorldZoneTeleportGUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

-- ===== ปุ่มลอย เปิด/ปิดหน้าต่าง =====
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleButton"
toggleBtn.Size = UDim2.new(0, 56, 0, 56)
toggleBtn.Position = UDim2.new(0, 12, 0.5, -28)
toggleBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
toggleBtn.Text = "🗺️"
toggleBtn.TextSize = 24
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextColor3 = Color3.new(1, 1, 1)
toggleBtn.AutoButtonColor = true
toggleBtn.ZIndex = 2
toggleBtn.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(1, 0)
toggleCorner.Parent = toggleBtn

-- ===== หน้าต่างหลัก =====
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 502)
mainFrame.Position = UDim2.new(0, 80, 0.5, -230)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

-- ===== TitleBar =====
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 12)
titleCorner.Parent = titleBar

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 12)
titleFix.Position = UDim2.new(0, 0, 1, -12)
titleFix.BackgroundColor3 = titleBar.BackgroundColor3
titleFix.BorderSizePixel = 0
titleFix.ZIndex = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -46, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Teleport"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -36, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

closeBtn.MouseButton1Click:Connect(function()
    autoFarmEnabled = false
    screenGui:Destroy()
end)

-- ===== แถว Auto Farm (เปิด/ปิดโหมดฟาร์มอัตโนมัติ) =====
local autoFarmBar = Instance.new("Frame")
autoFarmBar.Name = "AutoFarmBar"
autoFarmBar.Size = UDim2.new(1, -16, 0, 34)
autoFarmBar.Position = UDim2.new(0, 8, 0, 46)
autoFarmBar.BackgroundTransparency = 1
autoFarmBar.Parent = mainFrame

local autoFarmBtn = Instance.new("TextButton")
autoFarmBtn.Name = "AutoFarmButton"
autoFarmBtn.Size = UDim2.new(0.6, -3, 1, 0)
autoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
autoFarmBtn.Text = "🚜 Auto Farm: OFF"
autoFarmBtn.TextColor3 = Color3.new(1, 1, 1)
autoFarmBtn.Font = Enum.Font.GothamBold
autoFarmBtn.TextSize = 14
autoFarmBtn.AutoButtonColor = true
autoFarmBtn.Parent = autoFarmBar

local autoFarmBtnCorner = Instance.new("UICorner")
autoFarmBtnCorner.CornerRadius = UDim.new(0, 8)
autoFarmBtnCorner.Parent = autoFarmBtn

-- ===== ปุ่ม Craft Relics (วาปไปโต๊ะ Craft ของโลกปัจจุบัน + เปิดเมนู) =====
local craftRelicsBtn = Instance.new("TextButton")
craftRelicsBtn.Name = "CraftRelicsButton"
craftRelicsBtn.Size = UDim2.new(0.4, -3, 1, 0)
craftRelicsBtn.Position = UDim2.new(0.6, 3, 0, 0)
craftRelicsBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
craftRelicsBtn.Text = "🛠️ Craft"
craftRelicsBtn.TextColor3 = Color3.new(1, 1, 1)
craftRelicsBtn.Font = Enum.Font.GothamBold
craftRelicsBtn.TextSize = 14
craftRelicsBtn.AutoButtonColor = true
craftRelicsBtn.Parent = autoFarmBar

local craftRelicsBtnCorner = Instance.new("UICorner")
craftRelicsBtnCorner.CornerRadius = UDim.new(0, 8)
craftRelicsBtnCorner.Parent = craftRelicsBtn

craftRelicsBtn.MouseButton1Click:Connect(function()
    local originalText = craftRelicsBtn.Text
    craftRelicsBtn.Text = "🛠️ ..."
    task.spawn(function()
        -- แค่เปิดเมนู Craft ดูรายการไอเทมก่อนเฉยๆ "ไม่วาปตัวละคร"
        -- จะวาปไปโต๊ะจริงๆ ก็ต่อเมื่อกดเลือกไอเทมในลิสต์แล้วเท่านั้น
        local ok = openCraftMenuWithoutTeleport()
        craftRelicsBtn.Text = originalText

        if ok then
            craftRelicsBtn.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
            waitForCraftRelicsGui() -- กันเผื่อ GUI ของเกมเปิดช้ากว่า ShopOpenPrompt เล็กน้อย
            if openCraftPanel then
                openCraftPanel()
            end
        else
            craftRelicsBtn.BackgroundColor3 = Color3.fromRGB(170, 70, 70)
        end

        task.wait(0.6)
        craftRelicsBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end)
end)

----------------------------------------------------------------
-- Auto Farm: อัปเดตหน้าตาปุ่มตามสถานะ
----------------------------------------------------------------
refreshAutoFarmButton = function(statusText)
    if autoFarmEnabled then
        autoFarmBtn.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
        autoFarmBtn.Text = "🚜 Auto Farm: ON" .. (statusText and ("  |  " .. statusText) or "")
    else
        autoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        autoFarmBtn.Text = "🚜 Auto Farm: OFF"
    end
end

----------------------------------------------------------------
-- Auto Farm: ลูปหลัก
-- วนหาไอเทมมูลค่าสูงสุดที่มีอยู่ตอนนั้น -> วาปไปเก็บ -> รอเก็บสำเร็จ -> ดีเลย์ 1 วิ -> วนใหม่
----------------------------------------------------------------
local function autoFarmLoop()
    while autoFarmEnabled do
        -- ตรวจสอบกระเป๋าก่อนเริ่มหาไอเทมทุกครั้ง
        if checkBackpackAndReturnIfFull() then
            if not autoFarmEnabled then
                break
            end
        end

        local target, value = findMostValuableItem()

        if not target then
            -- ไม่พบไอเทมที่มีราคาเลยตอนนี้ -> รอแล้วสแกนใหม่
            refreshAutoFarmButton("ไม่พบไอเทม กำลังรอ...")
            task.wait(AUTO_FARM_RESCAN_INTERVAL)
        else
            refreshAutoFarmButton("กำลังไปเก็บ " .. target.Name .. " (" .. tostring(value) .. ")")

            local ok, collected = pcall(function()
                return teleportAndCollectItem(target)
            end)

            if ok and collected then
                -- รอให้ไอเทมหายไปจากเกม หรือจนครบเวลาสูงสุด
                local waited = 0
                while autoFarmEnabled and target.Parent and waited < AUTO_FARM_COLLECT_TIMEOUT do
                    task.wait(AUTO_FARM_CHECK_BACKPACK_INTERVAL)
                    waited += AUTO_FARM_CHECK_BACKPACK_INTERVAL

                    -- ถ้ากระเป๋าเต็ม ให้หยุดรอไอเทมและกลับฐานทันที
                    if checkBackpackAndReturnIfFull() then
                        break
                    end
                end
            elseif ok and not collected then
                refreshAutoFarmButton("ไม่พบ/เรียก PickupPrompt ไม่สำเร็จ")
                task.wait(0.5)
            else
                refreshAutoFarmButton("เก็บไม่สำเร็จ")
                task.wait(0.5)
            end

            -- ตรวจอีกครั้งก่อนดีเลย์ไปชิ้นถัดไป
            if autoFarmEnabled then
                local returnedToBase = checkBackpackAndReturnIfFull()

                if not returnedToBase then
                    task.wait(AUTO_FARM_POST_COLLECT_DELAY)
                end
            end
        end
    end

    refreshAutoFarmButton()
end

autoFarmBtn.MouseButton1Click:Connect(function()
    autoFarmEnabled = not autoFarmEnabled
    refreshAutoFarmButton()
    if autoFarmEnabled then
        task.spawn(autoFarmLoop)
    end
end)

-- ===== หัวข้อ: เลือกโลก (แยกจากโซนโดยสิ้นเชิง) =====
local worldSectionLabel = Instance.new("TextLabel")
worldSectionLabel.Name = "WorldSectionLabel"
worldSectionLabel.Size = UDim2.new(1, -16, 0, 16)
worldSectionLabel.Position = UDim2.new(0, 8, 0, 88)
worldSectionLabel.BackgroundTransparency = 1
worldSectionLabel.Text = "🌍 โลก (วาปไปจุด Sell)"
worldSectionLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
worldSectionLabel.Font = Enum.Font.GothamBold
worldSectionLabel.TextSize = 12
worldSectionLabel.TextXAlignment = Enum.TextXAlignment.Left
worldSectionLabel.Parent = mainFrame

-- ===== แถวเลือกโลก (World Selector) =====
local worldBarBg = Instance.new("Frame")
worldBarBg.Name = "WorldBar"
worldBarBg.Size = UDim2.new(1, -16, 0, 44)
worldBarBg.Position = UDim2.new(0, 8, 0, 106)
worldBarBg.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
worldBarBg.BorderSizePixel = 0
worldBarBg.Parent = mainFrame

local worldBarCorner = Instance.new("UICorner")
worldBarCorner.CornerRadius = UDim.new(0, 10)
worldBarCorner.Parent = worldBarBg

local worldScroll = Instance.new("ScrollingFrame")
worldScroll.Name = "WorldScroll"
worldScroll.Size = UDim2.new(1, -8, 1, -8)
worldScroll.Position = UDim2.new(0, 4, 0, 4)
worldScroll.BackgroundTransparency = 1
worldScroll.BorderSizePixel = 0
worldScroll.ScrollBarThickness = 4
worldScroll.ScrollingDirection = Enum.ScrollingDirection.X
worldScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
worldScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
worldScroll.Parent = worldBarBg

local worldListLayout = Instance.new("UIListLayout")
worldListLayout.FillDirection = Enum.FillDirection.Horizontal
worldListLayout.Padding = UDim.new(0, 6)
worldListLayout.SortOrder = Enum.SortOrder.LayoutOrder
worldListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
worldListLayout.Parent = worldScroll

-- ===== หัวข้อ: โซน & ไอเทม (Workspace.Zones — คนละต้นไม้กับ Worlds) =====
local zoneSectionLabel = Instance.new("TextLabel")
zoneSectionLabel.Name = "ZoneSectionLabel"
zoneSectionLabel.Size = UDim2.new(1, -16, 0, 16)
zoneSectionLabel.Position = UDim2.new(0, 8, 0, 154)
zoneSectionLabel.BackgroundTransparency = 1
zoneSectionLabel.Text = "📦 โซน & ไอเทม (W1 - W6)"
zoneSectionLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
zoneSectionLabel.Font = Enum.Font.GothamBold
zoneSectionLabel.TextSize = 12
zoneSectionLabel.TextXAlignment = Enum.TextXAlignment.Left
zoneSectionLabel.Parent = mainFrame

-- ===== รายการโซน/ไอเทม (ดึงจาก Workspace.Zones ตรงๆ ไม่ขึ้นกับโลกที่เลือก) =====
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name = "ItemList"
scrollFrame.Size = UDim2.new(1, -16, 1, -180)
scrollFrame.Position = UDim2.new(0, 8, 0, 174)
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

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local selectedWorld = nil -- {instance,index,name} ใช้แค่ไฮไลต์ปุ่ม + เดาโลกปัจจุบัน ไม่ยุ่งกับรายการโซน
local worldButtons = {}   -- [worldName] = TextButton

local COLOR_WORLD_NORMAL   = Color3.fromRGB(45, 45, 58)
local COLOR_WORLD_SELECTED = Color3.fromRGB(90, 130, 230)

----------------------------------------------------------------
-- สร้างรายการโซน + ไอเทม จาก Workspace.Zones ทั้งหมด
-- (เป็นอิสระจากโลกที่เลือกเสมอ เพราะ Zones แยกต้นไม้จาก Worlds)
----------------------------------------------------------------
local function buildItemList()
    local currentScroll = scrollFrame.CanvasPosition

    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    local wFolders = getSortedWFolders()

    if #wFolders == 0 then
        local warn_ = Instance.new("TextLabel")
        warn_.Size = UDim2.new(1, 0, 0, 40)
        warn_.BackgroundTransparency = 1
        warn_.Text = "ไม่พบโซน (W1..W6) ใน Workspace." .. ZONES_ROOT_NAME
        warn_.TextColor3 = Color3.fromRGB(255, 120, 120)
        warn_.Font = Enum.Font.Gotham
        warn_.TextSize = 14
        warn_.Parent = scrollFrame
        return
    end

    for _, wData in ipairs(wFolders) do
        local wOrderBase = wData.index * 100000

        local wHeader = Instance.new("TextLabel")
        wHeader.LayoutOrder = wOrderBase
        wHeader.Size = UDim2.new(1, 0, 0, 32)
        wHeader.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        wHeader.Text = " 🌐 " .. wData.name
        wHeader.TextColor3 = Color3.fromRGB(130, 180, 255)
        wHeader.Font = Enum.Font.GothamBold
        wHeader.TextSize = 15
        wHeader.TextXAlignment = Enum.TextXAlignment.Left
        wHeader.Parent = scrollFrame

        local wHeaderCorner = Instance.new("UICorner")
        wHeaderCorner.CornerRadius = UDim.new(0, 6)
        wHeaderCorner.Parent = wHeader

        local stages = getSortedStages(wData.instance)

        if #stages == 0 then
            local emptyLabel = Instance.new("TextLabel")
            emptyLabel.LayoutOrder = wOrderBase + 1
            emptyLabel.Size = UDim2.new(1, 0, 0, 25)
            emptyLabel.BackgroundTransparency = 1
            emptyLabel.Text = "   ไม่มีโซนใน " .. wData.name
            emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
            emptyLabel.Font = Enum.Font.Gotham
            emptyLabel.TextSize = 12
            emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
            emptyLabel.Parent = scrollFrame
        end

        for _, stageData in ipairs(stages) do
            local stageOrder = wOrderBase + (stageData.index * 100)

            local header = Instance.new("TextLabel")
            header.LayoutOrder = stageOrder
            header.Size = UDim2.new(1, -10, 0, 28)
            header.Position = UDim2.new(0, 10, 0, 0)
            header.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
            header.Text = "   📍 " .. stageData.name
            header.TextColor3 = Color3.fromRGB(255, 210, 100)
            header.Font = Enum.Font.GothamBold
            header.TextSize = 13
            header.TextXAlignment = Enum.TextXAlignment.Left
            header.Parent = scrollFrame

            local spawnZone = stageData.instance:FindFirstChild(ITEMS_FOLDER_NAME)
            if spawnZone then
                local items = spawnZone:GetChildren()

                if #items == 0 then
                    local emptyLabel = Instance.new("TextLabel")
                    emptyLabel.LayoutOrder = stageOrder + 1
                    emptyLabel.Size = UDim2.new(1, -20, 0, 25)
                    emptyLabel.Position = UDim2.new(0, 20, 0, 0)
                    emptyLabel.BackgroundTransparency = 1
                    emptyLabel.Text = "      ไม่มีไอเทมในโซนนี้"
                    emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
                    emptyLabel.Font = Enum.Font.Gotham
                    emptyLabel.TextSize = 12
                    emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
                    emptyLabel.Parent = scrollFrame
                else
                    for j, item in ipairs(items) do
                        local btn = Instance.new("TextButton")
                        btn.Name = item.Name
                        btn.LayoutOrder = stageOrder + 1 + j
                        btn.Size = UDim2.new(1, -20, 0, 34)
                        btn.Position = UDim2.new(0, 20, 0, 0)
                        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
                        btn.Text = "      • " .. item.Name
                        btn.TextColor3 = Color3.new(1, 1, 1)
                        btn.Font = Enum.Font.Gotham
                        btn.TextSize = 13
                        btn.TextXAlignment = Enum.TextXAlignment.Left
                        btn.AutoButtonColor = true
                        btn.Parent = scrollFrame

                        local btnCorner = Instance.new("UICorner")
                        btnCorner.CornerRadius = UDim.new(0, 8)
                        btnCorner.Parent = btn

                        btn.MouseButton1Click:Connect(function()
                            task.spawn(function()
                                teleportAndCollectItem(item)
                            end)
                        end)
                    end
                end
            else
                local warnLabel = Instance.new("TextLabel")
                warnLabel.LayoutOrder = stageOrder + 1
                warnLabel.Size = UDim2.new(1, -20, 0, 25)
                warnLabel.Position = UDim2.new(0, 20, 0, 0)
                warnLabel.BackgroundTransparency = 1
                warnLabel.Text = "      ⚠ ไม่พบโฟลเดอร์ " .. ITEMS_FOLDER_NAME
                warnLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
                warnLabel.Font = Enum.Font.Gotham
                warnLabel.TextSize = 12
                warnLabel.TextXAlignment = Enum.TextXAlignment.Left
                warnLabel.Parent = scrollFrame
            end
        end
    end

    task.spawn(function()
        scrollFrame.CanvasPosition = currentScroll
    end)
end

----------------------------------------------------------------
-- อัปเดตสีปุ่มโลกให้ปุ่มที่เลือกอยู่ไฮไลต์
----------------------------------------------------------------
local function refreshWorldButtonColors()
    for name, btn in pairs(worldButtons) do
        if selectedWorld and selectedWorld.name == name then
            btn.BackgroundColor3 = COLOR_WORLD_SELECTED
        else
            btn.BackgroundColor3 = COLOR_WORLD_NORMAL
        end
    end
end

----------------------------------------------------------------
-- สร้างแถวปุ่มเลือกโลก (Workspace.Worlds เท่านั้น — ไม่ยุ่งกับ Zones)
----------------------------------------------------------------
local function buildWorldBar()
    for _, child in ipairs(worldScroll:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    worldButtons = {}

    local worlds = getSortedWorlds()

    if #worlds == 0 then
        selectedWorld = nil
        local warn_ = Instance.new("TextLabel")
        warn_.Size = UDim2.new(1, 0, 1, 0)
        warn_.BackgroundTransparency = 1
        warn_.Text = "ไม่พบโลกใน Worlds"
        warn_.TextColor3 = Color3.fromRGB(255, 120, 120)
        warn_.Font = Enum.Font.Gotham
        warn_.TextSize = 13
        warn_.Parent = worldScroll
        return
    end

    -- ถ้ายังไม่เคยเลือกโลก หรือโลกที่เลือกไว้หายไปแล้ว -> เดาโลกใหม่จากตำแหน่งผู้เล่น
    if not selectedWorld then
        selectedWorld = detectCurrentWorld(worlds)
    else
        local stillExists = false
        for _, w in ipairs(worlds) do
            if w.name == selectedWorld.name then
                stillExists = true
                selectedWorld = w
                break
            end
        end
        if not stillExists then
            selectedWorld = detectCurrentWorld(worlds)
        end
    end

    for i, wData in ipairs(worlds) do
        local btn = Instance.new("TextButton")
        btn.Name = wData.name
        btn.LayoutOrder = i
        btn.Size = UDim2.new(0, 84, 1, 0)
        btn.BackgroundColor3 = COLOR_WORLD_NORMAL
        btn.Text = "🌍 " .. wData.name
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 13
        btn.AutoButtonColor = true
        btn.Parent = worldScroll

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn

        worldButtons[wData.name] = btn

        btn.MouseButton1Click:Connect(function()
            selectedWorld = wData
            teleportToWorld(wData.instance) -- วาปผู้เล่นไปจุด "Sell" ของโลกที่เลือก เท่านั้น
            refreshWorldButtonColors()       -- ไม่ยุ่งกับรายการโซน/ไอเทมด้านล่างเลย
        end)
    end

    refreshWorldButtonColors()
end

----------------------------------------------------------------
-- Craft Panel: หน้าต่างแยกไว้เลือกไอเทมที่จะ Craft
-- (โผล่ขึ้นมาเมื่อกดปุ่ม 🛠️ Craft และเมนู Craft ของเกมเปิดสำเร็จ)
----------------------------------------------------------------
local craftPanel = Instance.new("Frame")
craftPanel.Name = "CraftPanel"
craftPanel.Size = UDim2.new(0, 300, 0, 420)
craftPanel.Position = UDim2.new(0, 80, 0.5, -210)
craftPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
craftPanel.BorderSizePixel = 0
craftPanel.Visible = false
craftPanel.ZIndex = 5
craftPanel.Parent = screenGui

local craftPanelCorner = Instance.new("UICorner")
craftPanelCorner.CornerRadius = UDim.new(0, 12)
craftPanelCorner.Parent = craftPanel

-- ===== TitleBar ของ Craft Panel (ลากย้ายหน้าต่างนี้ได้) =====
local craftTitleBar = Instance.new("Frame")
craftTitleBar.Name = "TitleBar"
craftTitleBar.Size = UDim2.new(1, 0, 0, 36)
craftTitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
craftTitleBar.BorderSizePixel = 0
craftTitleBar.ZIndex = 5
craftTitleBar.Parent = craftPanel

local craftTitleCorner = Instance.new("UICorner")
craftTitleCorner.CornerRadius = UDim.new(0, 12)
craftTitleCorner.Parent = craftTitleBar

local craftTitleFix = Instance.new("Frame")
craftTitleFix.Size = UDim2.new(1, 0, 0, 12)
craftTitleFix.Position = UDim2.new(0, 0, 1, -12)
craftTitleFix.BackgroundColor3 = craftTitleBar.BackgroundColor3
craftTitleFix.BorderSizePixel = 0
craftTitleFix.ZIndex = 5
craftTitleFix.Parent = craftTitleBar

local craftTitleLabel = Instance.new("TextLabel")
craftTitleLabel.Size = UDim2.new(1, -40, 1, 0)
craftTitleLabel.Position = UDim2.new(0, 10, 0, 0)
craftTitleLabel.BackgroundTransparency = 1
craftTitleLabel.Text = "🛠️ เลือกไอเทม Craft"
craftTitleLabel.TextColor3 = Color3.new(1, 1, 1)
craftTitleLabel.Font = Enum.Font.GothamBold
craftTitleLabel.TextSize = 15
craftTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
craftTitleLabel.ZIndex = 5
craftTitleLabel.Parent = craftTitleBar

local craftCloseBtn = Instance.new("TextButton")
craftCloseBtn.Size = UDim2.new(0, 26, 0, 26)
craftCloseBtn.Position = UDim2.new(1, -32, 0, 5)
craftCloseBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
craftCloseBtn.Text = "X"
craftCloseBtn.TextColor3 = Color3.new(1, 1, 1)
craftCloseBtn.Font = Enum.Font.GothamBold
craftCloseBtn.TextSize = 14
craftCloseBtn.ZIndex = 5
craftCloseBtn.Parent = craftTitleBar

local craftCloseCorner = Instance.new("UICorner")
craftCloseCorner.CornerRadius = UDim.new(0, 8)
craftCloseCorner.Parent = craftCloseBtn

craftCloseBtn.MouseButton1Click:Connect(function()
    craftPanel.Visible = false
end)

-- ===== รายการไอเทมที่ Craft ได้ =====
local craftItemLabel = Instance.new("TextLabel")
craftItemLabel.Size = UDim2.new(1, -16, 0, 16)
craftItemLabel.Position = UDim2.new(0, 8, 0, 44)
craftItemLabel.BackgroundTransparency = 1
craftItemLabel.Text = "📜 ไอเทมที่ Craft ได้ (กดเพื่อเลือก)"
craftItemLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
craftItemLabel.Font = Enum.Font.GothamBold
craftItemLabel.TextSize = 12
craftItemLabel.TextXAlignment = Enum.TextXAlignment.Left
craftItemLabel.ZIndex = 5
craftItemLabel.Parent = craftPanel

local craftItemScroll = Instance.new("ScrollingFrame")
craftItemScroll.Size = UDim2.new(1, -16, 0, 170)
craftItemScroll.Position = UDim2.new(0, 8, 0, 64)
craftItemScroll.BackgroundTransparency = 1
craftItemScroll.BorderSizePixel = 0
craftItemScroll.ScrollBarThickness = 6
craftItemScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
craftItemScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
craftItemScroll.ZIndex = 5
craftItemScroll.Parent = craftPanel

local craftItemLayout = Instance.new("UIListLayout")
craftItemLayout.Padding = UDim.new(0, 6)
craftItemLayout.SortOrder = Enum.SortOrder.LayoutOrder
craftItemLayout.Parent = craftItemScroll

-- ===== สถานะ: วัตถุดิบที่ต้องใช้ + ความคืบหน้าการเก็บ =====
local craftStatusLabelHeader = Instance.new("TextLabel")
craftStatusLabelHeader.Size = UDim2.new(1, -16, 0, 16)
craftStatusLabelHeader.Position = UDim2.new(0, 8, 0, 240)
craftStatusLabelHeader.BackgroundTransparency = 1
craftStatusLabelHeader.Text = "📋 สถานะการเก็บวัตถุดิบ"
craftStatusLabelHeader.TextColor3 = Color3.fromRGB(160, 160, 175)
craftStatusLabelHeader.Font = Enum.Font.GothamBold
craftStatusLabelHeader.TextSize = 12
craftStatusLabelHeader.TextXAlignment = Enum.TextXAlignment.Left
craftStatusLabelHeader.ZIndex = 5
craftStatusLabelHeader.Parent = craftPanel

local craftStatusScroll = Instance.new("ScrollingFrame")
craftStatusScroll.Size = UDim2.new(1, -16, 0, 96)
craftStatusScroll.Position = UDim2.new(0, 8, 0, 260)
craftStatusScroll.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
craftStatusScroll.BorderSizePixel = 0
craftStatusScroll.ScrollBarThickness = 6
craftStatusScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
craftStatusScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
craftStatusScroll.ZIndex = 5
craftStatusScroll.Parent = craftPanel

local craftStatusScrollCorner = Instance.new("UICorner")
craftStatusScrollCorner.CornerRadius = UDim.new(0, 8)
craftStatusScrollCorner.Parent = craftStatusScroll

local craftStatusLabel = Instance.new("TextLabel")
craftStatusLabel.Size = UDim2.new(1, -12, 0, 0)
craftStatusLabel.Position = UDim2.new(0, 6, 0, 6)
craftStatusLabel.AutomaticSize = Enum.AutomaticSize.Y
craftStatusLabel.BackgroundTransparency = 1
craftStatusLabel.Text = "เลือกไอเทมที่ต้องการ Craft จากรายการด้านบน"
craftStatusLabel.TextColor3 = Color3.fromRGB(210, 210, 220)
craftStatusLabel.Font = Enum.Font.Gotham
craftStatusLabel.TextSize = 12
craftStatusLabel.TextWrapped = true
craftStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
craftStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
craftStatusLabel.ZIndex = 5
craftStatusLabel.Parent = craftStatusScroll

-- ===== ปุ่มหยุดเก็บ / รีเฟรชรายการไอเทม =====
local craftStopBtn = Instance.new("TextButton")
craftStopBtn.Size = UDim2.new(0.5, -10, 0, 30)
craftStopBtn.Position = UDim2.new(0, 8, 1, -36)
craftStopBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
craftStopBtn.Text = "⏹ หยุดเก็บวัตถุดิบ"
craftStopBtn.TextColor3 = Color3.new(1, 1, 1)
craftStopBtn.Font = Enum.Font.GothamBold
craftStopBtn.TextSize = 12
craftStopBtn.ZIndex = 5
craftStopBtn.Parent = craftPanel

local craftStopCorner = Instance.new("UICorner")
craftStopCorner.CornerRadius = UDim.new(0, 8)
craftStopCorner.Parent = craftStopBtn

local craftRefreshBtn = Instance.new("TextButton")
craftRefreshBtn.Size = UDim2.new(0.5, -10, 0, 30)
craftRefreshBtn.Position = UDim2.new(0.5, 2, 1, -36)
craftRefreshBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
craftRefreshBtn.Text = "🔄 รีเฟรชไอเทม"
craftRefreshBtn.TextColor3 = Color3.new(1, 1, 1)
craftRefreshBtn.Font = Enum.Font.GothamBold
craftRefreshBtn.TextSize = 12
craftRefreshBtn.ZIndex = 5
craftRefreshBtn.Parent = craftPanel

local craftRefreshCorner = Instance.new("UICorner")
craftRefreshCorner.CornerRadius = UDim.new(0, 8)
craftRefreshCorner.Parent = craftRefreshBtn

----------------------------------------------------------------
-- Craft Panel: State
----------------------------------------------------------------
local craftFarmActive = false
local craftFarmToken = 0 -- เปลี่ยนค่าทุกครั้งที่เริ่ม/หยุด farm ใหม่ ใช้ยกเลิก loop เก่าที่ค้างอยู่

local function updateCraftStatus(text)
    craftStatusLabel.Text = text
end

local function formatRequirements(requirements)
    local lines = {}
    for _, req in ipairs(requirements) do
        local mark = (req.current >= req.required) and "✅" or "⏳"
        table.insert(lines, string.format("%s %s: %d/%d", mark, req.itemName, req.current, req.required))
    end
    return table.concat(lines, "\n")
end

local function isAllRequirementsMet(requirements)
    for _, req in ipairs(requirements) do
        if req.current < req.required then
            return false
        end
    end
    return true
end

----------------------------------------------------------------
-- Craft Panel: ลูปเก็บวัตถุดิบตามสูตรที่เลือกไว้ จนครบทุกชิ้น แล้ววาปกลับฐาน
--
-- หมายเหตุสำคัญ: Count ("0/2") ในเมนู Craft อ่านได้ก็ต่อเมื่อยืนอยู่ใกล้โต๊ะ/เมนูเปิดอยู่
-- เท่านั้น พอวาปออกไปเก็บวัตถุดิบที่อื่น เมนูจะถูกปิดไป ทำให้อ่านค่าซ้ำไม่ได้และดูเหมือน
-- ไม่เพิ่มขึ้นเลย (เก็บไม่หยุดเพราะไม่รู้ว่าครบ) จึงเปลี่ยนมา "นับเองในสคริปต์" แทน:
-- เริ่มจากค่า current/required ที่อ่านได้ตอนเปิดสูตรครั้งแรก แล้วทุกครั้งที่เก็บไอเทมสำเร็จ
-- จริง (รอจนไอเทมนั้นหายไปจากโลกเพื่อยืนยัน ไม่ใช่แค่ยิง prompt ผ่าน) ค่อยบวก current ทีละ 1
----------------------------------------------------------------
local function startCraftMaterialFarm(requirements)
    craftFarmToken += 1
    local myToken = craftFarmToken
    craftFarmActive = true

    task.spawn(function()
        updateCraftStatus(formatRequirements(requirements))

        while craftFarmActive and myToken == craftFarmToken do
            if isAllRequirementsMet(requirements) then
                updateCraftStatus(formatRequirements(requirements) .. "\n\n✅ วัตถุดิบครบแล้ว! กำลังวาปกลับฐาน...")
                teleportToSpawn()
                craftFarmActive = false
                break
            end

            -- เช็คกระเป๋าก่อนทุกรอบ กันเก็บของไม่ได้/error เพราะกระเป๋าเต็ม
            -- (ใช้ checkBackpackAndReturnIfFull ตัวเดียวกับระบบ Auto Farm เดิม)
            if checkBackpackAndReturnIfFull() then
                if not craftFarmActive or myToken ~= craftFarmToken then break end
                updateCraftStatus(formatRequirements(requirements)
                    .. "\n\n🎒 กระเป๋าเต็ม -> วาปกลับฐานแล้ว กำลังเก็บวัตถุดิบต่อ...")
                task.wait(AUTO_FARM_RETURN_WAIT)
                continue
            end

            local collectedSomething = false

            for _, req in ipairs(requirements) do
                if myToken ~= craftFarmToken or not craftFarmActive then break end

                if req.current < req.required then
                    -- เช็คกระเป๋าเต็มอีกรอบระหว่างวนแต่ละวัตถุดิบ เผื่อเต็มพอดีกลางทาง
                    if checkBackpackAndReturnIfFull() then
                        updateCraftStatus(formatRequirements(requirements)
                            .. "\n\n🎒 กระเป๋าเต็ม -> วาปกลับฐานแล้ว กำลังเก็บวัตถุดิบต่อ...")
                        break
                    end

                    local matches = findFarmableItemsByName(req.itemName)
                    if #matches > 0 then
                        local target = matches[1]

                        updateCraftStatus(formatRequirements(requirements)
                            .. "\n\n🏃 กำลังไปเก็บ " .. req.itemName)

                        local ok, collected = pcall(function()
                            return teleportAndCollectItem(target)
                        end)

                        if ok and collected then
                            -- รอให้ไอเทมหายไปจากโลกจริงๆ ก่อน ถึงจะนับว่าเก็บสำเร็จ
                            -- (กันนับมั่ว เผื่อกด prompt ไม่ทัน/ไอเทมยังไม่หาย)
                            local waited = 0
                            while myToken == craftFarmToken and craftFarmActive
                                and target.Parent and waited < AUTO_FARM_COLLECT_TIMEOUT do
                                task.wait(AUTO_FARM_CHECK_BACKPACK_INTERVAL)
                                waited += AUTO_FARM_CHECK_BACKPACK_INTERVAL
                            end

                            if not target.Parent then
                                req.current = math.min(req.current + 1, req.required)
                                collectedSomething = true
                                updateCraftStatus(formatRequirements(requirements))
                            end

                            task.wait(CRAFT_FARM_POST_COLLECT_DELAY)
                        end
                    end
                end
            end

            if not collectedSomething and craftFarmActive and myToken == craftFarmToken then
                task.wait(CRAFT_FARM_CHECK_INTERVAL)
            end
        end
    end)
end

local function stopCraftMaterialFarm()
    craftFarmActive = false
    craftFarmToken += 1
    updateCraftStatus("⏹ หยุดเก็บวัตถุดิบแล้ว")
end

craftStopBtn.MouseButton1Click:Connect(function()
    stopCraftMaterialFarm()
end)

----------------------------------------------------------------
-- Craft Panel: วาดรายการไอเทมที่ Craft ได้
-- คลิกไอเทม = คลิกการ์ดไอเทมนั้นในเมนู Craft จริง -> รอสูตรเปิด -> อ่านวัตถุดิบที่ต้องใช้
-- -> เริ่มลูปวาปไปเก็บวัตถุดิบให้ครบอัตโนมัติ แล้ววาปกลับฐานเมื่อครบ
----------------------------------------------------------------
local craftItemButtons = {}

local function highlightSelectedCraftItem(selectedBtn)
    for _, b in ipairs(craftItemButtons) do
        b.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    end
    selectedBtn.BackgroundColor3 = Color3.fromRGB(90, 130, 230)
end

local function refreshCraftItemList()
    for _, child in ipairs(craftItemScroll:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    craftItemButtons = {}

    local entries = getCraftableItemEntries()

    if #entries == 0 then
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, 0, 0, 40)
        emptyLabel.BackgroundTransparency = 1
        emptyLabel.Text = "ไม่พบไอเทมที่ Craft ได้ (เปิดเมนู Craft ค้างไว้ หรือลองกดรีเฟรช)"
        emptyLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.TextSize = 12
        emptyLabel.TextWrapped = true
        emptyLabel.ZIndex = 5
        emptyLabel.Parent = craftItemScroll
        return
    end

    for i, entry in ipairs(entries) do
        local btn = Instance.new("TextButton")
        btn.LayoutOrder = i
        btn.Size = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        btn.Text = "  • " .. entry.name
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 13
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.ZIndex = 5
        btn.Parent = craftItemScroll

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn

        table.insert(craftItemButtons, btn)

        btn.MouseButton1Click:Connect(function()
            -- 1) เลือกไอเทมนี้ไว้ก่อน (ยกเลิกลูปเก็บวัตถุดิบของไอเทมเดิม ถ้ามี) + ไฮไลต์ปุ่มที่เลือก
            stopCraftMaterialFarm()
            highlightSelectedCraftItem(btn)
            updateCraftStatus("🚀 เลือก " .. entry.name .. " แล้ว กำลังวาปไปโต๊ะ Craft...")

            -- 2) ค่อยวาปไปโต๊ะ Craft + เปิดร้านใหม่เสมอ แล้วกด (เสมือนใช้เมาส์) ไอเทมที่ตรง
            --    กับชื่อที่เลือกไว้ในเมนู Craft จริง (สแกนสดใหม่ทุกครั้ง กันเคส Instance เก่าเพี้ยน)
            --    เพื่อให้ตารางคราฟของไอเทมนั้นโชว์ขึ้นมา
            local ok, requirements, err = openCraftItemAndGetRequirements(entry.name)

            if not ok then
                btn.BackgroundColor3 = Color3.fromRGB(170, 70, 70)
                updateCraftStatus("⚠ " .. (err or "ไม่สำเร็จ"))
                return
            end

            btn.BackgroundColor3 = Color3.fromRGB(70, 170, 90)

            -- 3) ตารางคราฟโชว์แล้ว -> auto CraftRelics เริ่มเก็บวัตถุดิบให้เองอัตโนมัติ
            startCraftMaterialFarm(requirements)
        end)
    end
end

craftRefreshBtn.MouseButton1Click:Connect(function()
    refreshCraftItemList()
end)

----------------------------------------------------------------
-- Craft Panel: เปิดหน้าต่าง + โหลดรายการไอเทมใหม่ทุกครั้งที่เปิด
----------------------------------------------------------------
openCraftPanel = function()
    craftPanel.Visible = true
    refreshCraftItemList()
end

----------------------------------------------------------------
-- Build ครั้งแรก (2 ระบบ แยกกันอิสระ)
----------------------------------------------------------------
buildWorldBar()
buildItemList()

----------------------------------------------------------------
-- ลูปอัปเดตอัตโนมัติทุกๆ 3 วินาที (เฉพาะตอนเปิดหน้าต่างอยู่)
----------------------------------------------------------------
task.spawn(function()
    while screenGui.Parent do
        task.wait(3)
        if mainFrame.Visible then
            buildWorldBar()
            buildItemList()
        end
    end
end)

----------------------------------------------------------------
-- Utility: ทำให้ลาก "target" ได้โดยใช้ "dragHandle" เป็นตัวจับลาก
-- คืนค่าฟังก์ชัน wasDragged() ไว้เช็คว่าครั้งล่าสุดมีการ "ลาก" จริงๆ หรือแค่ "คลิก"
-- (ไว้ใช้กับปุ่มที่ต้องลากได้ด้วย แต่ก็ยังต้องกดคลิกปกติได้ด้วย เช่น toggleBtn)
----------------------------------------------------------------
local function makeDraggable(dragHandle, target)
    local dragging = false
    local dragStart, startPos
    local moved = false

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = target.Position

            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    conn:Disconnect()
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart

            if math.abs(delta.X) > 3 or math.abs(delta.Y) > 3 then
                moved = true
            end

            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    return function()
        return moved
    end
end

----------------------------------------------------------------
-- Toggle / ลากหน้าต่าง
-- ลากได้ทั้งไอคอนลอย (toggleBtn), หน้าต่างหลัก (mainFrame ผ่าน titleBar)
-- และ Craft Panel (craftPanel ผ่าน craftTitleBar)
----------------------------------------------------------------
local toggleWasDragged = makeDraggable(toggleBtn, toggleBtn)
makeDraggable(titleBar, mainFrame)
makeDraggable(craftTitleBar, craftPanel)

local isOpen = false
toggleBtn.MouseButton1Click:Connect(function()
    if toggleWasDragged() then
        return -- เพิ่งลากไอคอนอยู่ ไม่ใช่การกดเปิด/ปิดเมนู
    end

    isOpen = not isOpen
    mainFrame.Visible = isOpen
    if isOpen then
        buildWorldBar()
        buildItemList()
    end
end)
