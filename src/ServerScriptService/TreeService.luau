-- TreeService: owns every tree and log in the world.
--   * Builds low-poly tree Models (cylinder trunk + ball foliage).
--   * Server-side HP; ApplyChop validates range and applies axe damage.
--   * Felling tips the tree over, hides it, spawns exactly logsPerTree logs,
--     and respawns it after the wood's respawnSec.
--   * Log records: state "world" | "carried" | "truck". Ownership: 10s grace
--     to the feller, then free-for-all.
-- GameServer assigns TreeService.PickupCallback for ProximityPrompt pickups.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WoodData = require(ReplicatedStorage.Shared.WoodData)
local Util = require(ReplicatedStorage.Shared.Util)

local TreeService = {}

local TREE_TAG = "Tree"
local LOG_TAG = "Log"
local CHOP_RANGE = 20
local PICKUP_GRACE_SEC = 10

local trees: { [string]: any } = {} -- [uid] -> { model, def, hp, alive, pivot }
local logs: { [string]: any } = {} -- [uid] -> { model, def, ownerId, fellTime, state }
local treeCounters: { [string]: number } = {}

local mapFolder: Folder? = nil
local function getMapFolder(): Folder
	if not mapFolder then
		mapFolder = workspace:WaitForChild("TimberlineMap", 30)
		assert(mapFolder, "[TreeService] TimberlineMap not found")
	end
	return mapFolder :: Folder
end

-- Assigned by GameServer: (player, logUid) -> (). Server-validated pickup.
TreeService.PickupCallback = nil :: ((Player, string) -> ())?

local function addPickupPrompt(logPart: BasePart, uid: string, def: any)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = def.displayName .. " Log"
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = logPart
	prompt.Triggered:Connect(function(player: Player)
		local cb = TreeService.PickupCallback
		if cb then
			cb(player, uid)
		end
	end)
end

-- Builds a tree at a ground-level CFrame. Returns the Model.
function TreeService.SpawnTree(woodId: string, cframe: CFrame): Model
	local def = WoodData.Get(woodId)
	assert(def, "[TreeService] Unknown wood: " .. tostring(woodId))
	treeCounters[woodId] = (treeCounters[woodId] or 0) + 1
	local uid = Util.guid()

	local model = Instance.new("Model")
	model.Name = string.format("Tree_%s_%d", woodId, treeCounters[woodId])

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(def.trunkHeight, 2, 2)
	trunk.Color = def.trunkColor
	trunk.Material = Enum.Material.Wood
	trunk.Anchored = true
	trunk.CanCollide = true
	-- Cylinder axis is X; rotate so it stands upright, then lift by half height.
	trunk.CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)) + Vector3.new(0, def.trunkHeight / 2, 0)
	trunk.Parent = model

	local foliage = Instance.new("Part")
	foliage.Name = "Foliage"
	foliage.Shape = Enum.PartType.Ball
	foliage.Size = Vector3.new(def.foliageSize, def.foliageSize, def.foliageSize)
	foliage.Color = def.leafColor
	foliage.Material = Enum.Material.Grass
	foliage.Anchored = true
	foliage.CanCollide = false
	foliage.CFrame = cframe + Vector3.new(0, def.trunkHeight + def.foliageSize * 0.32, 0)
	foliage.Parent = model

	model.PrimaryPart = trunk
	model:SetAttribute("WoodId", woodId)
	model:SetAttribute("MaxHP", def.treeHP)
	model:SetAttribute("HP", def.treeHP)
	model:SetAttribute("Uid", uid)
	model:SetAttribute("BarOffset", def.trunkHeight + def.foliageSize * 0.95)
	model.Parent = getMapFolder()
	CollectionService:AddTag(model, TREE_TAG)

	trees[uid] = {
		model = model,
		def = def,
		hp = def.treeHP,
		alive = true,
		pivot = model:GetPivot(),
	}
	return model
end

-- Brief wobble so every hit feels like it landed.
function TreeService.ShakeTree(model: Model)
	local pp = model.PrimaryPart
	if not pp then
		return
	end
	task.spawn(function()
		local base = pp.CFrame
		for _ = 1, 3 do
			if pp.Parent == nil then
				return
			end
			pp.CFrame = base * CFrame.Angles(0, 0, math.rad(2.5))
			task.wait(0.05)
			if pp.Parent == nil then
				return
			end
			pp.CFrame = base
			task.wait(0.05)
		end
	end)
end

local function setTreeVisible(rec: any, visible: boolean)
	for _, d in ipairs(rec.model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = visible and 0 or 1
			d.CanCollide = visible
		end
	end
end

-- Spawns one pickup-able log. Returns (Model, uid).
function TreeService.SpawnLog(def: any, position: Vector3, ownerId: number): (Model, string)
	local uid = Util.guid()

	local model = Instance.new("Model")
	model.Name = "Log_" .. def.id

	local part = Instance.new("Part")
	part.Name = "LogPart"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(3, 1.2, 1.2)
	part.Color = def.trunkColor
	part.Material = Enum.Material.Wood
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi, math.rad(90))
	part.Parent = model

	model.PrimaryPart = part
	model:SetAttribute("WoodId", def.id)
	model:SetAttribute("Value", def.pricePerLog)
	model:SetAttribute("Uid", uid)
	model.Parent = getMapFolder()
	CollectionService:AddTag(model, LOG_TAG)

	logs[uid] = {
		model = model,
		def = def,
		ownerId = ownerId,
		fellTime = os.time(),
		state = "world",
	}
	addPickupPrompt(part, uid, def)
	return model, uid
end

local function fellTree(player: Player, uid: string)
	local rec = trees[uid]
	if not rec or not rec.alive then
		return
	end
	rec.alive = false
	local model = rec.model

	-- Tip over, then vanish (respawn timer restores it later).
	task.spawn(function()
		local from = model:GetPivot()
		local yaw = math.random() * math.pi * 2
		local to = from * CFrame.Angles(0, yaw, 0) * CFrame.new(0, -1.5, 0) * CFrame.Angles(math.rad(75), 0, 0)
		local cf = Instance.new("CFrameValue")
		cf.Value = from
		local conn: RBXScriptConnection? = nil
		conn = cf:GetPropertyChangedSignal("Value"):Connect(function()
			if model.Parent then
				model:PivotTo(cf.Value)
			end
		end)
		local tween = TweenService:Create(
			cf,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = to }
		)
		tween:Play()
		tween.Completed:Wait()
		if conn then
			conn:Disconnect()
		end
		cf:Destroy()
		setTreeVisible(rec, false)
	end)

	-- Spawn exactly logsPerTree logs around the stump.
	local base = rec.pivot.Position
	for i = 1, rec.def.logsPerTree do
		local angle = (i / rec.def.logsPerTree) * math.pi * 2 + math.random() * 0.5
		local pos = Vector3.new(
			base.X + math.cos(angle) * 4,
			1.6,
			base.Z + math.sin(angle) * 4
		)
		TreeService.SpawnLog(rec.def, pos, player.UserId)
	end

	task.delay(rec.def.respawnSec, function()
		local r = trees[uid]
		if not r then
			return
		end
		r.hp = r.def.treeHP
		r.alive = true
		r.model:PivotTo(r.pivot)
		setTreeVisible(r, true)
		r.model:SetAttribute("HP", r.hp)
	end)
end

-- Validates range server-side, applies damage, returns new HP (nil + reason on reject).
function TreeService.ApplyChop(player: Player, treeUid: string, damage: number): (number?, string?)
	local rec = trees[treeUid]
	if not rec or not rec.alive then
		return nil, "gone"
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local pp = rec.model.PrimaryPart
	if not hrp or not pp then
		return nil, "nochar"
	end
	if (hrp.Position - pp.Position).Magnitude > CHOP_RANGE then
		return nil, "far"
	end
	rec.hp = math.max(0, rec.hp - damage)
	rec.model:SetAttribute("HP", rec.hp)
	TreeService.ShakeTree(rec.model)
	if rec.hp <= 0 then
		fellTree(player, treeUid)
	end
	return rec.hp, nil
end

function TreeService.GetLog(uid: string): any
	return logs[uid]
end

function TreeService.GetPickupGraceSec(): number
	return PICKUP_GRACE_SEC
end

-- Marks a world log as carried (caller welds the model). False if unavailable.
function TreeService.ClaimLog(uid: string): boolean
	local rec = logs[uid]
	if not rec or rec.state ~= "world" then
		return false
	end
	rec.state = "carried"
	local pp = rec.model and rec.model.PrimaryPart
	if pp then
		local prompt = pp:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
	end
	return true
end

-- Removes the log record entirely (sold / loaded). Returns the record.
function TreeService.TakeLog(uid: string): any
	local rec = logs[uid]
	if not rec then
		return nil
	end
	logs[uid] = nil
	return rec
end

function TreeService.ReturnLogToWorld(uid: string): boolean
	local rec = logs[uid]
	if not rec then
		return false
	end
	rec.state = "world"
	return true
end

-- Drops a carried log back into the world (e.g. player died).
function TreeService.DropLog(uid: string, nearPos: Vector3)
	local rec = logs[uid]
	if not rec or rec.state ~= "carried" then
		return
	end
	local pp = rec.model and rec.model.PrimaryPart
	if pp then
		local weld = pp:FindFirstChildOfClass("WeldConstraint")
		if weld then
			weld:Destroy()
		end
		pp.Massless = false
		pp.Anchored = true
		pp.CFrame = CFrame.new(nearPos + Vector3.new(math.random(-3, 3), 1.6, math.random(-3, 3)))
			* CFrame.Angles(0, math.random() * math.pi, math.rad(90))
		addPickupPrompt(pp, uid, rec.def)
	end
	rec.state = "world"
end

return TreeService
