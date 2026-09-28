--[[
	GuardAreasAnalyzer.lua

	สคริปต์นี้ไม่ได้แก้ไข/ปิดอะไรใน GuardAreas เลย มีหน้าที่ "อ่านและพิมพ์" โครงสร้างทั้งหมด
	ออกมาใน Output/Console เพื่อให้เราดูว่าแต่ละมอนสเตอร์มีอะไรอยู่บ้าง (Instance, Class,
	Property สำคัญของ Part, Attribute, Tag, และ Remote ที่มองเห็นได้จากฝั่ง client)

	ข้อจำกัดสำคัญ: LocalScript มองไม่เห็น Script (server script) ธรรมดาเลย เพราะ Roblox
	ไม่ replicate มันมาให้ client ดังนั้นตรรกะดาเมจจริงที่รันอยู่ฝั่งเซิร์ฟเวอร์จะไม่ถูกพิมพ์ออกมา
	สคริปต์นี้ช่วยได้แค่ "เห็นโครงสร้างข้อมูล" ไม่ใช่ "เห็นโค้ดที่คำนวณดาเมจ"
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local guardAreasFolder = Workspace
	:WaitForChild("__OBJECTS")
	:WaitForChild("Areas")
	:WaitForChild("GuardAreas")

-- Property ที่น่าสนใจสำหรับ BasePart (เกี่ยวกับการชน/ตรวจจับ)
local BASEPART_PROPERTIES = {
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"Anchored",
	"Massless",
	"Position",
	"Size",
	"Material",
}

-- Property ที่น่าสนใจสำหรับ Humanoid (เกี่ยวกับดาเมจ/พลังชีวิต)
local HUMANOID_PROPERTIES = {
	"Health",
	"MaxHealth",
	"WalkSpeed",
	"DisplayDistanceType",
	"HealthDisplayType",
}

local function safeGet(instance, propName)
	local ok, value = pcall(function()
		return instance[propName]
	end)
	if ok then
		return value
	end
	return nil
end

local function describeInstance(instance, depth)
	local indent = string.rep("    ", depth)
	print(string.format("%s[%s] %s", indent, instance.ClassName, instance.Name))

	-- Attributes (ค่าที่ผู้พัฒนาเกมตั้งเองผ่าน SetAttribute)
	local attributes = instance:GetAttributes()
	for attrName, attrValue in pairs(attributes) do
		print(string.format("%s  Attribute: %s = %s", indent, attrName, tostring(attrValue)))
	end

	-- Tags (CollectionService) มักใช้ผูกกับระบบ เช่น "Monster", "Hitbox"
	local tags = CollectionService:GetTags(instance)
	if #tags > 0 then
		print(string.format("%s  Tags: %s", indent, table.concat(tags, ", ")))
	end

	-- Property สำคัญของ BasePart
	if instance:IsA("BasePart") then
		for _, propName in ipairs(BASEPART_PROPERTIES) do
			local value = safeGet(instance, propName)
			if value ~= nil then
				print(string.format("%s  %s = %s", indent, propName, tostring(value)))
			end
		end
	end

	-- Property สำคัญของ Humanoid
	if instance:IsA("Humanoid") then
		for _, propName in ipairs(HUMANOID_PROPERTIES) do
			local value = safeGet(instance, propName)
			if value ~= nil then
				print(string.format("%s  %s = %s", indent, propName, tostring(value)))
			end
		end
	end

	-- ชี้เป้า Remote / Script ที่ client มองเห็นได้ (เผื่อเกี่ยวกับระบบดาเมจ/สั่งงาน)
	if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
		print(string.format("%s  >>> พบ %s ชื่อ \"%s\" (อาจเกี่ยวกับระบบโจมตี/ดาเมจ)", indent, instance.ClassName, instance.Name))
	elseif instance:IsA("LocalScript") or instance:IsA("ModuleScript") then
		print(string.format("%s  >>> พบ %s ชื่อ \"%s\"", indent, instance.ClassName, instance.Name))
	end
end

local function walk(instance, depth)
	describeInstance(instance, depth)
	for _, child in ipairs(instance:GetChildren()) do
		walk(child, depth + 1)
	end
end

print("========== เริ่มวิเคราะห์ Workspace.__OBJECTS.Areas.GuardAreas ==========")
walk(guardAreasFolder, 0)
print("========== จบการวิเคราะห์ (ดู Output/Console ด้านบนทั้งหมด) ==========")

--[[
	วิธีอ่านผลลัพธ์:
	- ดูว่ามี RemoteEvent/RemoteFunction ชื่ออะไรบ้างใกล้ๆ ตัวมอนสเตอร์ (เช่น "Attack",
	  "DealDamage", "Hit") — ถ้าเจอ แปลว่าดาเมจอาจถูกส่งผ่าน Remote ซึ่งควบคุมฝั่งเซิร์ฟเวอร์
	  ทั้งหมด เราแก้ไขค่าจากฝั่ง client ไม่ได้
	- ดูว่า Part ไหนมี CanTouch/CanCollide = true อยู่ (ตัวที่ยังไม่ถูกเราปิด) เผื่อมีการ
	  เพิ่ม/ลบ Part แบบไดนามิก
	- ถ้าไม่เจอ Script/RemoteEvent อะไรเกี่ยวข้องเลย แปลว่าตรรกะดาเมจไม่ได้อยู่ใต้โฟลเดอร์นี้
	  อาจอยู่ในโฟลเดอร์ระบบอื่น หรือรันจาก ServerScriptService (ซึ่ง client มองไม่เห็นเลย)
]]