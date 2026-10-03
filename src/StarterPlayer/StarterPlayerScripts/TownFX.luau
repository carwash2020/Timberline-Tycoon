--!strict
-- TownFX: small motions that make the town feel worked in, all local.
--   * The sawmill's big blade ("SawBlade" tag, MapBuilder) spins about its
--     own X axis (BuildingArt: its teeth are welded to it and follow).
--   * Campfire flames ("Flame" tag) flicker: they breathe in size and
--     brightness, each on its own phase.
-- Only what's near the camera moves. Streaming-safe: tagged parts come and
-- go through CollectionService signals.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnvironmentData = require(ReplicatedStorage.Shared.EnvironmentData)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local Quality = require(script.Parent.Quality)

local TownFX = {}

local BLADE_SPEED = 7 -- radians per second
-- Only within Quality.Budget().TownFxNear studs of the camera (260, 120 on
-- low quality; Shared/QualityBudgets).

type Flame = { part: BasePart, size: Vector3, phase: number }

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local blades: { [BasePart]: boolean } = {}
local flames: { [BasePart]: Flame } = {}
local chimneys: { [BasePart]: ParticleEmitter } = {}

local function puff(part: BasePart): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "HearthPuff"
	e.Texture = SMOKE_TEXTURE
	e.Color = ColorSequence.new(Color3.fromRGB(210, 206, 198), Color3.fromRGB(160, 156, 148))
	e.LightEmission = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.4),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(2.2, 3.4)
	e.Speed = NumberRange.new(1.2, 2.2)
	e.Acceleration = Vector3.new(0.4, 1.5, 0)
	e.Drag = 1.5
	e.Rate = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Parent = part
	return e
end

local function track(tag: string, add: (BasePart) -> (), remove: (BasePart) -> ())
	local function added(inst: Instance)
		if inst:IsA("BasePart") then
			add(inst)
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		added(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
		if inst:IsA("BasePart") then
			remove(inst)
		end
	end)
end

function TownFX.Start()
	track("SawBlade", function(part)
		blades[part] = true
	end, function(part)
		blades[part] = nil
	end)
	track("Flame", function(part)
		flames[part] = { part = part, size = part.Size, phase = (part.Position.X + part.Position.Z) % 6.28 }
	end, function(part)
		flames[part] = nil
	end)
	track("HearthSmoke", function(part)
		if chimneys[part] then
			return
		end
		chimneys[part] = puff(part)
	end, function(part)
		local e = chimneys[part]
		chimneys[part] = nil
		if e then
			e:Destroy()
		end
	end)

	local t = 0
	local sinceCosmetic = 0
	RunService.RenderStepped:Connect(function(dt: number)
		sinceCosmetic += dt
		if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
			return
		end
		local step = sinceCosmetic
		sinceCosmetic = 0
		t += step
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local near = Quality.Budget().TownFxNear
		local chimneyRate = EnvironmentData.ChimneyRate(Quality.Budget().Tier)
		for part, emitter in pairs(chimneys) do
			if part.Parent then
				local close = (part.Position - eye).Magnitude < near
				emitter.Rate = if close then chimneyRate else 0
			end
		end
		for blade in pairs(blades) do
			if blade.Parent and (blade.Position - eye).Magnitude < near then
				blade.CFrame *= CFrame.Angles(BLADE_SPEED * step, 0, 0)
			end
		end
		for part, flame in pairs(flames) do
			if part.Parent and (part.Position - eye).Magnitude < near then
				local breathe = 1 + 0.14 * math.sin(t * 9 + flame.phase) + 0.06 * math.sin(t * 23 + flame.phase * 2)
				part.Size = flame.size * breathe
				part.Transparency = 0.08 + 0.12 * (0.5 + 0.5 * math.sin(t * 13 + flame.phase))
			end
		end
	end)
end

return TownFX
