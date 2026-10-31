--!strict
-- RoadCritters (T414d-2): a deer, a rabbit or a bird beside the road that
-- moves off as you pass. Client only: no remote, no server part, nothing saved,
-- nothing replicated.
--   * Templates (one per kind, CritterArt.RoadTemplate) live in
--     ReplicatedStorage "CritterTemplates", built on this client.
--   * One RunService.Heartbeat loop walks one table of live critters. A
--     critter past RoadCritterLogic.ActiveRange of the camera is skipped; one
--     past DespawnRange (its region has streamed out) is removed.
--   * At most CritterArt.RoadCapFor(tier) are alive (12 on a phone, 40 on high).
--   * They appear on the verge (Scatter's own grass spots, so never on the
--     road) a long way off, sit still, and flee a player inside the kind's
--     radius by RoadCritterLogic.Flee: never toward a spot Scatter.KeepOut
--     refuses (a road, lane, door, belt box, the town, water).
--   * Only task.spawn / task.wait; no per-critter loop or tween.
-- Everything lives in the workspace folder "RoadCritters".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CritterArt = require(ReplicatedStorage.Shared.Art.CritterArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local Logic = require(ReplicatedStorage.Shared.World.RoadCritterLogic)
local Scatter = require(ReplicatedStorage.Shared.World.Scatter)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local Quality = require(script.Parent.Quality)
local ScatterCover = require(script.Parent.ScatterCover)

local RoadCritters = {}

type Critter = {
	model: Model,
	kind: string,
	x: number,
	z: number,
	y: number,
	dx: number,
	dz: number,
	fleeing: boolean,
	phase: number,
}

local SPAWN_EVERY = 1.5
local THREAT_EVERY = 0.25
local live: { Critter } = {}
local spots: { Scatter.Item } = {} -- the verge's grass: where a critter may sit
local templates: { [string]: Model } = {}
local folder: Folder? = nil
local rng = Kit.rng(4141)

local function root(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "RoadCritters"
	made.Parent = workspace
	folder = made
	return made
end

local function template(kind: string): Model
	local t = templates[kind]
	if t then
		return t
	end
	local home = ReplicatedStorage:FindFirstChild("CritterTemplates")
	if not home then
		local made = Instance.new("Folder")
		made.Name = "CritterTemplates"
		made.Parent = ReplicatedStorage
		home = made
	end
	local made = CritterArt.RoadTemplate(kind, 7)
	made.Name = kind
	made.Parent = home
	templates[kind] = made
	return made
end

local function blocked(x: number, z: number): boolean
	return Scatter.KeepOut(x, z, 1) ~= nil
end

local function threats(): { Vector3 }
	local out: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			table.insert(out, hrp.Position)
		end
	end
	return out
end

local function place(c: Critter, lift: number)
	c.model:PivotTo(CFrame.new(c.x, c.y + lift, c.z) * CFrame.Angles(0, math.atan2(-c.dx, -c.dz), 0))
end

local function remove(i: number)
	local c = live[i]
	live[i] = live[#live]
	live[#live] = nil
	c.model:Destroy()
end

local function spawnOne(camera: Vector3)
	if #spots == 0 then
		return
	end
	-- A few tries at a verge spot between SpawnMin and the active range.
	for _ = 1, 12 do
		local spot = spots[rng:int(1, #spots)]
		local d = math.sqrt((spot.x - camera.X) ^ 2 + (spot.z - camera.Z) ^ 2)
		if d >= Logic.SpawnMin and d <= Logic.ActiveRange - 10 then
			local kind = Logic.KindFor(spot.region, rng:next())
			local model = template(kind):Clone()
			local c: Critter = {
				model = model,
				kind = kind,
				x = spot.x,
				z = spot.z,
				y = spot.y,
				dx = 0,
				dz = -1,
				fleeing = false,
				phase = rng:next() * 6,
			}
			place(c, if kind == "Bird" then 0.2 else 0)
			model.Parent = root()
			table.insert(live, c)
			return
		end
	end
end

function RoadCritters.Start()
	task.spawn(function()
		ScatterCover.WaitUntilPlaying()
		for _, item in ipairs(Scatter.Cover()) do
			if item.kind == "grass" and item.road then
				table.insert(spots, item)
			end
		end
		local sinceSpawn, sinceThreat = 0, 0
		local near: { Vector3 } = {}
		RunService.Heartbeat:Connect(function(dt: number)
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local cam = camera.CFrame.Position
			sinceSpawn += dt
			sinceThreat += dt
			local refresh = sinceThreat >= THREAT_EVERY
			if refresh then
				sinceThreat = 0
				near = threats()
			end
			if sinceSpawn >= SPAWN_EVERY then
				sinceSpawn = 0
				if #live < CritterArt.RoadCapFor(Quality.Tier()) then
					spawnOne(cam)
				end
			end
			-- Backwards, so a removal does not skip the next critter.
			for i = #live, 1, -1 do
				local c = live[i]
				local away = math.sqrt((c.x - cam.X) ^ 2 + (c.z - cam.Z) ^ 2)
				if away > Logic.DespawnRange or live[i] ~= c then
					remove(i)
				elseif away <= Logic.ActiveRange then
					if refresh and not c.fleeing then
						for _, p in ipairs(near) do
							if (c.x - p.X) ^ 2 + (c.z - p.Z) ^ 2 < Logic.FleeRadius(c.kind) ^ 2 then
								local dx, dz = Logic.Flee(c.x, c.z, p.X, p.Z, blocked)
								if dx and dz then
									c.dx, c.dz, c.fleeing = dx, dz, true
								end
								break
							end
						end
					end
					if c.fleeing then
						local step = Logic.Speed(c.kind) * dt
						c.x += c.dx * step
						c.z += c.dz * step
						c.phase += dt * 14
						if c.kind == "Bird" then
							c.y += step * 0.9
							place(c, 0)
						else
							c.y = TerrainGen.HeightAt(c.x, c.z)
							place(c, if c.kind == "Rabbit" then math.abs(math.sin(c.phase)) * 0.7 else 0)
						end
					end
				end
			end
		end)
	end)
end

return RoadCritters
