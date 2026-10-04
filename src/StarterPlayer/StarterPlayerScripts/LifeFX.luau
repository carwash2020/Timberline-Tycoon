--!strict
-- LifeFX: a few client-only bits the world was missing. Nothing collides,
-- and Low gets none of it (EnvironmentData.LeafRate / RiverMotes are 0).
--   * Leaves drifting past the camera in leafy places by day.
--   * A handful of glints sliding along the river when you're beside it.
-- Birds, the night owl and the river's sound are AmbientSound. Chimney
-- smoke is TownFX. Other players' chops already play through WoodFX.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnvironmentData = require(ReplicatedStorage.Shared.EnvironmentData)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local Quality = require(script.Parent.Quality)
local LightingController = require(script.Parent.LightingController)

local LifeFX = {}

local LEAFY: { [string]: boolean } = { [""] = true, starter = true, hills = true, grove = true }

local function flowAt(x: number, z: number): (Vector3, Vector3)
	local points = WorldLayout.River.points
	local best, bx, bz, bnx, bnz = math.huge, 0, 0, 0, -1
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local abx, abz = b.X - a.X, b.Y - a.Y
		local len2 = abx * abx + abz * abz
		local t = if len2 > 1e-6 then math.clamp(((x - a.X) * abx + (z - a.Y) * abz) / len2, 0, 1) else 0
		local px, pz = a.X + abx * t, a.Y + abz * t
		local d = (x - px) ^ 2 + (z - pz) ^ 2
		if d < best then
			local len = math.sqrt(len2)
			best = d
			bx, bz = px, pz
			if len > 1e-3 then
				bnx, bnz = abx / len, abz / len
			end
		end
	end
	return Vector3.new(bx, WorldLayout.LakeLevel + 0.4, bz), Vector3.new(bnx, 0, bnz)
end

function LifeFX.Start()
	local folder = Instance.new("Folder")
	folder.Name = "LifeFX"
	folder.Parent = workspace

	local leafPart = Instance.new("Part")
	leafPart.Name = "Leaves"
	leafPart.Size = Vector3.new(1, 1, 1)
	leafPart.Transparency = 1
	leafPart.Anchored = true
	leafPart.CanCollide = false
	leafPart.CanQuery = false
	leafPart.CanTouch = false
	leafPart.Parent = folder

	local leaves = Instance.new("ParticleEmitter")
	leaves.Name = "Drift"
	leaves.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	leaves.Color = ColorSequence.new(Color3.fromRGB(168, 124, 52), Color3.fromRGB(120, 86, 40))
	leaves.Size = NumberSequence.new(0.35)
	leaves.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	leaves.Lifetime = NumberRange.new(3.5, 5.5)
	leaves.Speed = NumberRange.new(1, 3)
	leaves.SpreadAngle = Vector2.new(30, 30)
	leaves.Acceleration = Vector3.new(1.5, -0.8, 0.4)
	leaves.Rate = 0
	leaves.LightEmission = 0
	leaves.Parent = leafPart

	local motes: { Part } = {}
	local function moteCount(n: number)
		while #motes < n do
			local p = Instance.new("Part")
			p.Name = "RiverMote"
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(0.45, 0.45, 0.45)
			p.Color = Color3.fromRGB(210, 220, 230)
			p.Material = Enum.Material.SmoothPlastic
			p.Transparency = 0.35
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = folder
			table.insert(motes, p)
		end
		for i = n + 1, #motes do
			motes[i].Transparency = 1
		end
	end

	local along = 0
	local sinceCosmetic = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCosmetic += dt
		if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
			return
		end
		local step = sinceCosmetic
		sinceCosmetic = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local tier = Quality.Budget().Tier
		local env = LightingController.Environment()
		local at = camera.CFrame.Position
		local leafy = LEAFY[env.biomeId] == true
		local day = env.daylight > 0.35
		local wet = env.weather == "Rain" or env.weather == "Storm"
		leaves.Rate = if leafy and day and not wet then EnvironmentData.LeafRate(tier) else 0
		leafPart.CFrame = CFrame.new(at + camera.CFrame.LookVector * 18 + Vector3.new(0, 6, 0))

		local want = EnvironmentData.RiverMotes(tier)
		moteCount(want)
		if want == 0 then
			return
		end
		local point, distance, kind = EnvironmentData.NearestWater(at.X, at.Z)
		local _, dir = flowAt(point.X, point.Z)
		if kind ~= "river" or distance > 50 then
			for i = 1, want do
				motes[i].Transparency = 1
			end
			return
		end
		along += step
		for i = 1, want do
			local t = (along * 4 + i * 7) % 28
			local side = (i - 1.5) * 3
			local sideDir = Vector3.new(-dir.Z, 0, dir.X)
			motes[i].Transparency = 0.4
			motes[i].CFrame = CFrame.new(point + dir * (t - 10) + sideDir * side)
		end
	end)
end

return LifeFX
