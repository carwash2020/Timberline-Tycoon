--!strict
-- TreeFX: everything a tree does on screen, drawn locally on every client
-- from the server's attributes, so everyone nearby sees it smoothly.
-- One animator per tree, so a wobble, a fall and a regrow never fight:
--   * Hit (HP drops): the tree wobbles around its base, wood chips fly and
--     a thunk plays (Shared/SoundData).
--   * Fall (Felled = true): the tree leans away from the chopper, slowly
--     at first, then thumps down along FallDir (Shared/TreeLogic timing),
--     with a dust and leaf burst, a creak and a crash, and a small camera
--     shake for anyone close. The server hides it once it has landed.
--   * Regrow (Felled = false): the tree springs back up from sapling size.
-- The server never moves a tree, so everything here starts and ends on the
-- HomePivot attribute.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundData = require(ReplicatedStorage.Shared.SoundData)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local CameraShake = require(script.Parent.CameraShake)

type WoodDef = WoodData.WoodDef

local TreeFX = {}

local FX_RANGE = 120 -- studs from the camera; farther trees aren't animated
local WOBBLE_DEGREES = { 2.6, -1.4, 0.6, 0 }
local WOBBLE_STEP = 0.05
local CHIP_COUNT = 6
local REGROW_TIME = 2.2

type State = {
	conns: { RBXScriptConnection },
	lastHp: number,
	token: number, -- bumps whenever a new animation takes over
	busy: boolean, -- falling or regrowing: hits don't wobble it
}

local states: { [Model]: State } = {}

local function homeOf(tree: Model): CFrame?
	local home = tree:GetAttribute("HomePivot")
	return if typeof(home) == "CFrame" then home else nil
end

-- The trunk's length and its ground point, from the trunk cylinder (its X
-- axis runs up the trunk).
local function trunkInfo(tree: Model, home: CFrame): (number, Vector3)
	local trunk = tree.PrimaryPart
	local length = if trunk then trunk.Size.X else 8
	return length, home.Position - home.RightVector * (length / 2)
end

local function nearCamera(point: Vector3, range: number?): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - point).Magnitude <= (range or FX_RANGE)
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

local function wobble(tree: Model, state: State, home: CFrame)
	state.token += 1
	local token = state.token
	local _, base = trunkInfo(tree, home)
	local axis = Vector3.new(0, 1, 0):Cross(awayFromPlayer(base)) -- tips the top away from you
	task.spawn(function()
		for _, degrees in ipairs(WOBBLE_DEGREES) do
			if state.token ~= token or tree.Parent == nil then
				return
			end
			local tilt = CFrame.new(base) * CFrame.fromAxisAngle(axis, math.rad(degrees)) * CFrame.new(-base)
			tree:PivotTo(tilt * home)
			task.wait(WOBBLE_STEP)
		end
	end)
end

local function chips(tree: Model, def: WoodDef, home: CFrame)
	local _, base = trunkInfo(tree, home)
	local trunk = tree.PrimaryPart
	local radius = if trunk then trunk.Size.Y / 2 else 1
	local toward = -awayFromPlayer(base)
	local origin = base + Vector3.new(0, 2.6, 0) + toward * (radius + 0.15)
	local inner = TreeArt.HeartColor(def)
	for i = 1, CHIP_COUNT do
		local chip = Instance.new("Part")
		chip.Name = "WoodChip"
		chip.Size = Vector3.new(0.25 + math.random() * 0.25, 0.14, 0.35 + math.random() * 0.3)
		chip.Color = if i % 3 == 0 then def.trunkColor else inner
		chip.Material = Enum.Material.Wood
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.Massless = true
		chip.CastShadow = false
		chip.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chip.Parent = workspace
		local side = toward:Cross(Vector3.yAxis) * ((math.random() - 0.5) * 12)
		chip.AssemblyLinearVelocity = toward * (6 + math.random() * 4) + side + Vector3.new(0, 9 + math.random() * 7, 0)
		chip.AssemblyAngularVelocity = Vector3.new(math.random() * 20, math.random() * 20, math.random() * 20)
		Debris:AddItem(chip, 1.4)
	end
end

-- A burst of dust (and leaves, for leafy trees) where the tree lands.
local function landingBurst(def: WoodDef, at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "FellBurst"
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Size = Vector3.new(6, 1, 6)
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = workspace
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(196, 174, 140))
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.8, 1.6)
	dust.Speed = NumberRange.new(4, 10)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Drag = 3
	dust.Rate = 0
	dust.Parent = anchor
	dust:Emit(26)
	if def.silhouette ~= "dead" then
		local leaves = Instance.new("ParticleEmitter")
		leaves.Color = ColorSequence.new(TreeArt.Palette(def).leaves[1])
		leaves.LightInfluence = 1
		leaves.Size = NumberSequence.new(0.35)
		leaves.Lifetime = NumberRange.new(1.4, 2.6)
		leaves.Speed = NumberRange.new(6, 14)
		leaves.SpreadAngle = Vector2.new(70, 70)
		leaves.Acceleration = Vector3.new(0, -6, 0)
		leaves.Drag = 1.5
		leaves.RotSpeed = NumberRange.new(-180, 180)
		leaves.Rate = 0
		leaves.Parent = anchor
		leaves:Emit(30)
	end
	Debris:AddItem(anchor, 3)
end

local function fall(tree: Model, def: WoodDef, state: State)
	local home = homeOf(tree)
	local dir = tree:GetAttribute("FallDir")
	local fellAt = tree:GetAttribute("FellAt")
	if not home or typeof(dir) ~= "Vector3" or type(fellAt) ~= "number" then
		return
	end
	local length, base = trunkInfo(tree, home)
	if not nearCamera(base) then
		return
	end
	local started = workspace:GetServerTimeNow() - fellAt
	if started > TreeLogic.FallTime then
		return -- streamed in after it already fell
	end
	state.token += 1
	state.busy = true
	local token = state.token
	local axis = Vector3.new(0, 1, 0):Cross(dir)
	SoundData.PlayAt("TreeCreak", base + Vector3.new(0, length / 2, 0))
	task.spawn(function()
		local landed = false
		local t = math.max(0, started)
		while t <= TreeLogic.FallTime + 0.05 do
			if state.token ~= token or tree.Parent == nil then
				return
			end
			local angle = TreeLogic.FallProgress(t) * TreeLogic.FallAngle
			tree:PivotTo(CFrame.new(base) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-base) * home)
			if not landed and t >= TreeLogic.FallTime * 0.86 then
				landed = true
				local tip = base + dir * (length * 0.85)
				landingBurst(def, tip)
				SoundData.PlayAt("TreeFall", tip)
				if nearCamera(tip, 45) then
					CameraShake.Shake(0.45, 0.35)
				end
			end
			t += RunService.Heartbeat:Wait()
		end
	end)
end

local function regrow(tree: Model, state: State)
	local home = homeOf(tree)
	if not home then
		return
	end
	state.token += 1
	local token = state.token
	local length, base = trunkInfo(tree, home)
	tree:PivotTo(home)
	if not nearCamera(base) then
		state.busy = false
		return
	end
	state.busy = true
	local up = home.RightVector
	task.spawn(function()
		local t = 0
		while t < REGROW_TIME do
			if state.token ~= token or tree.Parent == nil then
				return
			end
			local x = t / REGROW_TIME
			-- Ease out with a little overshoot, like a spring.
			local s = 0.2 + 0.8 * (1 - (1 - x) ^ 3) + math.sin(x * math.pi) * 0.06
			tree:ScaleTo(math.max(0.05, s))
			tree:PivotTo(CFrame.new(base + up * (length * s / 2)) * home.Rotation)
			t += RunService.Heartbeat:Wait()
		end
		tree:ScaleTo(1)
		tree:PivotTo(home)
		state.busy = false
	end)
end

local function attach(tree: Model)
	if states[tree] then
		return
	end
	local def = WoodData.Get(tostring(tree:GetAttribute("WoodId")))
	if not def then
		return
	end
	local woodDef: WoodDef = def
	local state: State = {
		conns = {},
		lastHp = (tree:GetAttribute("HP") :: number?) or 0,
		token = 0,
		busy = false,
	}
	states[tree] = state
	table.insert(
		state.conns,
		tree:GetAttributeChangedSignal("HP"):Connect(function()
			local hp = (tree:GetAttribute("HP") :: number?) or 0
			local prev = state.lastHp
			state.lastHp = hp
			if hp >= prev then
				return -- regrown
			end
			local home = homeOf(tree)
			if not home or not nearCamera(home.Position) then
				return
			end
			chips(tree, woodDef, home)
			local trunk = tree.PrimaryPart
			if trunk then
				SoundData.PlayAt(if hp > 0 then "Chop" else "ChopFinal", trunk.Position)
			end
			if hp > 0 and not state.busy then
				wobble(tree, state, home)
			end
		end)
	)
	table.insert(
		state.conns,
		tree:GetAttributeChangedSignal("Felled"):Connect(function()
			if tree:GetAttribute("Felled") == true then
				fall(tree, woodDef, state)
			else
				regrow(tree, state)
			end
		end)
	)
end

local function detach(tree: Model)
	local state = states[tree]
	if state then
		state.token += 1
		for _, c in ipairs(state.conns) do
			c:Disconnect()
		end
	end
	states[tree] = nil
end

-- True while a tree is falling or regrowing (wind sway leaves it alone).
function TreeFX.IsBusy(tree: Model): boolean
	local state = states[tree]
	return state ~= nil and state.busy
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
