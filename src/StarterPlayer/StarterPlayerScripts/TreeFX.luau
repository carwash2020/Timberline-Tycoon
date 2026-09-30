--!strict
-- TreeFX: per-hit feedback, drawn locally on every client from the server's
-- HP attribute, so everyone nearby sees every hit: the tree wobbles around
-- its base, wood chips fly, and an optional thunk plays (GameConfig sound ids).
-- The wobble always settles back on the server's HomePivot and stops the
-- moment HP reaches 0, so it can never fight the server's fall animation.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local WoodData = require(ReplicatedStorage.Shared.WoodData)

type WoodDef = WoodData.WoodDef

local TreeFX = {}

local FX_RANGE = 90 -- studs from the camera; farther hits aren't drawn
local WOBBLE_DEGREES = { 2.2, -1.2, 0.5, 0 }
local WOBBLE_STEP = 0.05
local CHIP_COUNT = 5

local lastHp: { [Model]: number } = {}
local shakeToken: { [Model]: number } = {}
local connections: { [Model]: RBXScriptConnection } = {}

local function homeOf(tree: Model): CFrame?
	local home = tree:GetAttribute("HomePivot")
	return if typeof(home) == "CFrame" then home else nil
end

local function playSound(parent: BasePart, soundId: string)
	if soundId == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.RollOffMaxDistance = 80
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 3)
end

-- Horizontal unit vector from the local player toward `point` (or +Z).
local function awayFromPlayer(point: Vector3): Vector3
	local char = Players.LocalPlayer.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if hrp then
		local v = Vector3.new(point.X - hrp.Position.X, 0, point.Z - hrp.Position.Z)
		if v.Magnitude > 0.1 then
			return v.Unit
		end
	end
	return Vector3.zAxis
end

local function wobble(tree: Model, def: WoodDef, home: CFrame)
	local token = (shakeToken[tree] or 0) + 1
	shakeToken[tree] = token
	local base = home.Position - Vector3.new(0, def.trunkHeight / 2, 0)
	local axis = Vector3.new(0, 1, 0):Cross(awayFromPlayer(base)) -- tips the top away from you
	task.spawn(function()
		for _, degrees in ipairs(WOBBLE_DEGREES) do
			if shakeToken[tree] ~= token or tree.Parent == nil then
				return
			end
			local tilt = CFrame.new(base) * CFrame.fromAxisAngle(axis, math.rad(degrees)) * CFrame.new(-base)
			tree:PivotTo(tilt * home)
			task.wait(WOBBLE_STEP)
		end
	end)
end

local function chips(def: WoodDef, home: CFrame)
	local base = home.Position - Vector3.new(0, def.trunkHeight / 2, 0)
	local toward = -awayFromPlayer(base)
	local origin = base + Vector3.new(0, 2.5, 0) + toward * 1.1
	local inner = def.trunkColor:Lerp(Color3.fromRGB(240, 215, 170), 0.55) -- fresh-cut wood is paler
	for i = 1, CHIP_COUNT do
		local chip = Instance.new("Part")
		chip.Name = "WoodChip"
		chip.Size = Vector3.new(0.25 + math.random() * 0.2, 0.15, 0.35 + math.random() * 0.25)
		chip.Color = if i % 2 == 0 then def.trunkColor else inner
		chip.Material = Enum.Material.Wood
		chip.CanQuery = false
		chip.CanTouch = false
		chip.Massless = true
		chip.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chip.Parent = workspace
		local spread = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 10
		chip.AssemblyLinearVelocity = toward * 7 + spread + Vector3.new(0, 10 + math.random() * 6, 0)
		Debris:AddItem(chip, 1.2)
	end
end

local function nearCamera(point: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - point).Magnitude <= FX_RANGE
end

local function attach(tree: Model)
	if connections[tree] then
		return
	end
	local def = WoodData.Get(tostring(tree:GetAttribute("WoodId")))
	if not def then
		return
	end
	local woodDef: WoodDef = def
	lastHp[tree] = (tree:GetAttribute("HP") :: number?) or 0
	connections[tree] = tree:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = (tree:GetAttribute("HP") :: number?) or 0
		local prev = lastHp[tree] or hp
		lastHp[tree] = hp
		if hp >= prev then
			return -- respawned
		end
		local home = homeOf(tree)
		local trunk = tree.PrimaryPart
		if hp <= 0 then
			shakeToken[tree] = (shakeToken[tree] or 0) + 1 -- stop wobbling; the server fells it now
		end
		if not home or not nearCamera(home.Position) then
			return
		end
		chips(woodDef, home)
		if hp > 0 then
			wobble(tree, woodDef, home)
		end
		if trunk then
			playSound(trunk, if hp > 0 then GameConfig.ChopSoundId else GameConfig.FellSoundId)
		end
	end)
end

local function detach(tree: Model)
	local conn = connections[tree]
	if conn then
		conn:Disconnect()
	end
	connections[tree] = nil
	lastHp[tree] = nil
	shakeToken[tree] = nil
end

function TreeFX.Start()
	for _, inst in ipairs(CollectionService:GetTagged("Tree")) do
		if inst:IsA("Model") then
			attach(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal("Tree"):Connect(function(inst)
		if inst:IsA("Model") then
			attach(inst)
		end
	end)
	-- Fires when a tree streams out of range, too.
	CollectionService:GetInstanceRemovedSignal("Tree"):Connect(function(inst)
		if inst:IsA("Model") then
			detach(inst)
		end
	end)
end

return TreeFX
