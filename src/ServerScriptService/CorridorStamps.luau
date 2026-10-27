--!strict
-- Corridor stamps (T409). Streamed models along the draft roads so a
-- drive is not a blank shoulder. Props are the existing kit (signs,
-- bushes, rocks, fallen logs). They do not collide and they are not
-- trees you can cut. Neon is a tiny apron accent, never a terrain face.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingArt = require(ReplicatedStorage.Shared.Art.BuildingArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local CorridorPlan = require(ReplicatedStorage.Shared.World.CorridorPlan)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldPlanDraft = require(ReplicatedStorage.Shared.World.WorldPlanDraft)

local CorridorStamps = {}

local ACCENT: { [string]: string } = {
	FrostGlow = "BFE3F2",
	EmberGlow = "FF7A1A",
	GloamGlow = "7A4FD0",
	LumenGlow = "FFF4C2",
}

local function place(model: Model, x: number, z: number, yaw: number)
	local y = TerrainGen.HeightAt(x, z)
	Kit.placeAt(model, CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
	Kit.decorAll(model)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
end

local function buildOne(marker: CorridorPlan.Marker, parent: Instance, index: number): Model
	local seed = index * 17 + 3
	local model: Model
	if marker.kind == "sign" then
		model = BuildingArt.Signpost(marker.label or "MILE", false, false, nil, true, true)
	elseif marker.kind == "tree-belt" then
		model = PropArt.Bush(4 + (seed % 3), seed, { Color3.fromRGB(90, 122, 62), Color3.fromRGB(70, 100, 48) })
	elseif marker.kind == "scatter" then
		model = PropArt.Scatter("starter", seed)
	elseif marker.kind == "wood-lot" then
		model = Kit.model("WoodLot")
		local y = TerrainGen.HeightAt(marker.x, marker.z)
		for n = 1, 5 do
			local log = PropArt.FallenLog(seed + n, nil, nil)
			log.Name = "Log"
			local ang = n / 5 * math.pi * 2
			Kit.placeAt(log, CFrame.new(marker.x + math.cos(ang) * 6, y, marker.z + math.sin(ang) * 6))
			Kit.decorAll(log)
			log.Parent = model
		end
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model.Parent = parent
		return model
	elseif marker.kind == "camp" or marker.kind == "boom" then
		model = PropArt.FallenLog(seed, nil, nil)
	else
		local size = if marker.kind == "vista" then 6 elseif marker.kind == "overlook" then 5 else 3
		model = PropArt.Rock(size, seed, nil, nil)
	end
	model.Name = "Corridor" .. marker.kind
	place(model, marker.x, marker.z, (seed % 628) / 100)
	model.Parent = parent
	return model
end

local function apron(parent: Instance)
	for _, belt in ipairs(WorldPlanDraft.Belts) do
		local hex = if belt.accent then ACCENT[belt.accent] else nil
		if hex and belt.accentDepth then
			local dx = belt.edge.x - belt.outer.x
			local dz = belt.edge.z - belt.outer.z
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 1 then
				local nx, nz = -dz / len, dx / len
				local off = belt.width / 2 + 4
				local x = belt.edge.x + nx * off
				local z = belt.edge.z + nz * off
				local model = Kit.model("ApronGlow")
				local part = Kit.part(
					model,
					"Glow",
					Vector3.new(0.6, 0.2, 0.6),
					CFrame.new(0, 0.1, 0),
					Color3.fromHex(hex),
					Enum.Material.Neon
				)
				part.Name = "Glow"
				place(model, x, z, 0)
				model.Parent = parent
			end
		end
	end
end

function CorridorStamps.Build(parent: Instance, slice: (() -> ())?)
	local folder = Instance.new("Model")
	folder.Name = "Corridors"
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	folder.Parent = parent
	for index, marker in ipairs(CorridorPlan.Markers()) do
		buildOne(marker, folder, index)
		if slice and index % 8 == 0 then
			slice()
		end
	end
	apron(folder)
end

return CorridorStamps
