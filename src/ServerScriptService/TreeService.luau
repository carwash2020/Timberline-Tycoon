--!strict
-- TreeService: owns every tree and log in the world.
--   * Builds low-poly tree Models (cylinder trunk + ball foliage).
--   * Server-side HP; ApplyChop validates range and applies axe damage.
--     Hit feedback (shake, chips, sound) is drawn on each client by TreeFX,
--     so the server never fights the fall animation over the trunk.
--   * Felling hinges the tree over at its base in a random direction, then
--     swaps it for exactly logsPerTree logs laid along the fallen trunk, and
--     respawns the tree after the wood's respawnSec.
--   * Night-only woods (the Phantom Grove): SetBiomeDormant hides a biome's
--     trees by day and brings them back at night (WorldClock).
--   * Log records: state "world" | "carried". Ownership: PickupGraceSec to
--     the feller, then free-for-all. Logs left in the world despawn after
--     LogDespawnSec.
-- GameServer assigns TreeService.PickupCallback for ProximityPrompt pickups.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)

type WoodDef = WoodData.WoodDef

local TreeService = {}

local TREE_TAG = "Tree"
local LOG_TAG = "Log"
local FALL_ANGLE = math.rad(84) -- nearly flat; a full 90 would sink the trunk into the ground
local FALL_TIME = 0.6
local LOG_LENGTH = 3
local LOG_DIAMETER = 1.2
local LOG_GAP = 0.2

export type TreeRecord = {
	model: Model,
	def: WoodDef,
	hp: number,
	alive: boolean,
	pivot: CFrame, -- upright pivot (trunk centre)
	base: Vector3, -- ground point under the trunk
	collide: { [BasePart]: boolean }, -- each part's original CanCollide
	felled: boolean, -- down and waiting to regrow
	dormant: boolean, -- hidden for now (night-only woods by day)
}

export type LogRecord = {
	model: Model,
	def: WoodDef,
	ownerId: number,
	fellTime: number,
	state: "world" | "carried",
	despawnToken: number,
}

local trees: { [string]: TreeRecord } = {}
local logs: { [string]: LogRecord } = {}
local treeCounters: { [string]: number } = {}

local folders: { [string]: Folder } = {}
local function getFolder(name: string): Folder
	local cached = folders[name]
	if cached then
		return cached
	end
	local map = workspace:WaitForChild("TimberlineMap", 30)
	assert(map, "[TreeService] TimberlineMap not found")
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = map
	folders[name] = folder
	return folder
end

-- Assigned by GameServer: (player, logUid) -> (). Server-validated pickup.
TreeService.PickupCallback = nil :: ((Player, string) -> ())?
-- Assigned by GameServer: how many times logsPerTree a player's fell drops
-- (2 during a 2x Wood boost).
TreeService.LogMultiplier = nil :: ((Player) -> number)?

local function addPickupPrompt(logPart: BasePart, uid: string, def: WoodDef)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = def.displayName .. " Log"
	prompt.MaxActivationDistance = GameConfig.PickupPromptRange
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
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- trunk + leaves stream in together

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
	local pivot = model:GetPivot()
	model:SetAttribute("WoodId", woodId)
	model:SetAttribute("MaxHP", def.treeHP)
	model:SetAttribute("HP", def.treeHP)
	model:SetAttribute("Uid", uid)
	model:SetAttribute("BarOffset", def.trunkHeight / 2 + def.foliageSize * 0.95)
	model:SetAttribute("HomePivot", pivot) -- clients shake the tree around this
	CollectionService:AddTag(model, TREE_TAG)
	model.Parent = getFolder("Trees")

	trees[uid] = {
		model = model,
		def = def,
		hp = def.treeHP,
		alive = true,
		pivot = pivot,
		base = cframe.Position,
		collide = { [trunk] = trunk.CanCollide, [foliage] = foliage.CanCollide },
		felled = false,
		dormant = false,
	}
	return model
end

local function setTreeVisible(rec: TreeRecord, visible: boolean)
	for part, collides in pairs(rec.collide) do
		part.Transparency = if visible then 0 else 1
		part.CanTouch = visible
		if visible then
			part.CanQuery = true
			part.CanCollide = collides
		else
			-- CanCollide must go false before CanQuery can.
			part.CanCollide = false
			part.CanQuery = false -- clicks and raycasts pass through the hidden tree
		end
	end
end

-- Log despawn: each (re)entry into the world gets a fresh token, so an old
-- timer can't delete a log that was picked up and dropped again since.
local function scheduleDespawn(uid: string, rec: LogRecord)
	rec.despawnToken += 1
	local token = rec.despawnToken
	task.delay(GameConfig.LogDespawnSec, function()
		if logs[uid] == rec and rec.state == "world" and rec.despawnToken == token then
			logs[uid] = nil
			rec.model:Destroy()
		end
	end)
end

-- Spawns one pickup-able log at `cframe` (cylinder axis = the CFrame's X).
function TreeService.SpawnLog(def: WoodDef, cframe: CFrame, ownerId: number): (Model, string)
	local uid = Util.guid()

	local model = Instance.new("Model")
	model.Name = "Log_" .. def.id

	local part = Instance.new("Part")
	part.Name = "LogPart"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(LOG_LENGTH, LOG_DIAMETER, LOG_DIAMETER)
	part.Color = def.trunkColor
	part.Material = Enum.Material.Wood
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = cframe
	part.Parent = model

	model.PrimaryPart = part
	model:SetAttribute("WoodId", def.id)
	model:SetAttribute("Value", def.pricePerLog)
	model:SetAttribute("Uid", uid)
	CollectionService:AddTag(model, LOG_TAG)
	model.Parent = getFolder("Logs")

	local rec: LogRecord = {
		model = model,
		def = def,
		ownerId = ownerId,
		fellTime = os.time(),
		state = "world",
		despawnToken = 0,
	}
	logs[uid] = rec
	addPickupPrompt(part, uid, def)
	scheduleDespawn(uid, rec)
	return model, uid
end

-- CFrames for n logs lying end to end along `dir` from the stump, in
-- side-by-side rows when the trunk is too short to hold them in one line.
local function logLayout(base: Vector3, dir: Vector3, trunkHeight: number, n: number): { CFrame }
	local step = LOG_LENGTH + LOG_GAP
	local perRow = math.max(1, math.floor(trunkHeight / step))
	local rows = math.ceil(n / perRow)
	local side = dir:Cross(Vector3.yAxis)
	local out: { CFrame } = {}
	for i = 0, n - 1 do
		local row = i // perRow
		local col = i % perRow
		local pos = base
			+ dir * (1.8 + col * step)
			+ side * ((row - (rows - 1) / 2) * (LOG_DIAMETER + 0.3))
			+ Vector3.new(0, LOG_DIAMETER / 2, 0)
		table.insert(out, CFrame.fromMatrix(pos, dir, Vector3.yAxis))
	end
	return out
end

local function fellTree(player: Player, uid: string)
	local rec = trees[uid]
	if not rec or not rec.alive then
		return
	end
	rec.alive = false
	rec.felled = true
	local model = rec.model
	local fellerId = player.UserId

	-- Hinge at the base of the trunk, facing a random direction, and tip the
	-- whole tree over around that hinge's X axis.
	local hinge = CFrame.new(rec.base) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local offset = hinge:ToObjectSpace(rec.pivot)
	local fallenUp = (hinge * CFrame.Angles(FALL_ANGLE, 0, 0)).UpVector
	local fallDir = Vector3.new(fallenUp.X, 0, fallenUp.Z).Unit -- where the treetop lands

	task.spawn(function()
		local alpha = Instance.new("NumberValue")
		local conn = alpha.Changed:Connect(function(a: number)
			model:PivotTo(hinge * CFrame.Angles(FALL_ANGLE * a, 0, 0) * offset)
		end)
		local tween = TweenService:Create(
			alpha,
			TweenInfo.new(FALL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		conn:Disconnect()
		alpha:Destroy()
		task.wait(0.15)

		-- Swap the fallen tree for exactly logsPerTree logs where it landed.
		setTreeVisible(rec, false)
		local multiplier = if TreeService.LogMultiplier then TreeService.LogMultiplier(player) else 1
		local count = rec.def.logsPerTree * multiplier
		for _, cf in ipairs(logLayout(rec.base, fallDir, rec.def.trunkHeight, count)) do
			TreeService.SpawnLog(rec.def, cf, fellerId)
		end
	end)

	task.delay(rec.def.respawnSec, function()
		if trees[uid] ~= rec then
			return
		end
		model:PivotTo(rec.pivot)
		rec.hp = rec.def.treeHP
		model:SetAttribute("HP", rec.hp)
		rec.felled = false
		if not rec.dormant then
			setTreeVisible(rec, true)
			rec.alive = true
		end
	end)
end

-- Hides (or brings back) every tree of a biome, e.g. the Phantom Grove by
-- day. A tree that's down stays down until it regrows.
function TreeService.SetBiomeDormant(biomeId: string, dormant: boolean)
	for _, rec in pairs(trees) do
		if rec.def.biome == biomeId and rec.dormant ~= dormant then
			rec.dormant = dormant
			rec.model:SetAttribute("Dormant", dormant) -- clients don't aim at hidden trees
			if dormant and rec.alive then
				rec.alive = false
				rec.hp = rec.def.treeHP -- a half-chopped tree is whole again tomorrow night
				rec.model:SetAttribute("HP", rec.hp)
				setTreeVisible(rec, false)
			elseif not dormant and not rec.felled then
				setTreeVisible(rec, true)
				rec.alive = true
			end
		end
	end
end

-- The wood of a standing tree, or nil if there's no such tree up right now.
function TreeService.GetTreeWood(uid: string): WoodDef?
	local rec = trees[uid]
	return if rec and rec.alive then rec.def else nil
end

-- Validates range server-side, applies the axe's damage for this tree's
-- biome, returns new HP (nil + reason on reject).
function TreeService.ApplyChop(player: Player, treeUid: string, axe: ItemCatalog.AxeDef): (number?, string?)
	local rec = trees[treeUid]
	if not rec or not rec.alive then
		return nil, "gone"
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hrp then
		return nil, "nochar"
	end
	local offset = hrp.Position - rec.base
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if
		horizontal > GameConfig.ChopRange + GameConfig.RangeTolerance
		or math.abs(offset.Y) > rec.def.trunkHeight + 10
	then
		return nil, "far"
	end
	local damage = ItemCatalog.AxeDamage(axe, rec.def)
	if damage <= 0 then
		return nil, "tooHard"
	end
	rec.hp = math.max(0, rec.hp - damage)
	rec.model:SetAttribute("HP", rec.hp)
	if rec.hp <= 0 then
		fellTree(player, treeUid)
	end
	return rec.hp, nil
end

function TreeService.GetLog(uid: string): LogRecord?
	return logs[uid]
end

-- Marks a world log as carried (caller welds the model). False if unavailable.
function TreeService.ClaimLog(uid: string): boolean
	local rec = logs[uid]
	if not rec or rec.state ~= "world" then
		return false
	end
	rec.state = "carried"
	local pp = rec.model.PrimaryPart
	if pp then
		local prompt = pp:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
	end
	return true
end

-- Removes the log record entirely (sold / loaded). The caller destroys the model.
function TreeService.TakeLog(uid: string): LogRecord?
	local rec = logs[uid]
	logs[uid] = nil
	return rec
end

-- Drops a carried log back onto the ground near `nearPos` (player died or
-- left). The dropper gets the pickup grace window again.
function TreeService.DropLog(uid: string, nearPos: Vector3, dropper: Player)
	local rec = logs[uid]
	if not rec or rec.state ~= "carried" then
		return
	end
	local pp = rec.model.PrimaryPart
	if pp then
		for _, child in ipairs(pp:GetChildren()) do
			if child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end
		local spot = nearPos + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
		local params = RaycastParams.new()
		params.RespectCanCollide = true -- skip invisible zones, foliage, other logs
		if dropper.Character then
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { dropper.Character }
		end
		local hit = workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -80, 0), params)
		local groundY = if hit then hit.Position.Y else spot.Y - 3
		pp.Anchored = true
		pp.Massless = false
		pp.CFrame = CFrame.new(spot.X, groundY + LOG_DIAMETER / 2, spot.Z)
			* CFrame.Angles(0, math.random() * math.pi, 0)
		addPickupPrompt(pp, uid, rec.def)
	end
	rec.state = "world"
	rec.ownerId = dropper.UserId
	rec.fellTime = os.time()
	scheduleDespawn(uid, rec)
end

return TreeService
