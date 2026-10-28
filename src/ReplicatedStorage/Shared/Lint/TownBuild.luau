--!strict
-- TownBuild: the town as MapBuilder builds it, as a plain Folder, for the places that cannot run
-- MapBuilder itself (it is a Script: the cloud test, tests/cloud/entry, can only require modules).
-- Same calls, same WorldPlan places, same names: the sawmill and the sell area in front of it, the
-- three shops and the Dealership with their counters, the spawn, the scenes (the Sky Forge Court),
-- Murph's camp, the lamps, fences, props and signs. No terrain, no trees, no lift onto the ground
-- (the ground is at y = 0 here and in the lune build, which stubs the terrain the same way).
-- tests/TownBuild.spec checks this agrees with a real MapBuilder run, piece by piece, so the two
-- cannot drift apart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingArt = require(ReplicatedStorage.Shared.Art.BuildingArt)
local BuiltMoves = require(ReplicatedStorage.Shared.World.BuiltMoves)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)

local TownBuild = {}

local function place(model: Model, cf: CFrame, parent: Instance): Model
	Kit.placeAt(model, cf)
	model.Parent = parent
	return model
end

-- Returns the Folder "TimberlineMap" with the town in it.
function TownBuild.Build(): Folder
	local map = Instance.new("Folder")
	map.Name = "TimberlineMap"
	local town = WorldPlan.Town()

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = town.spawnFacing
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Parent = map

	place(BuildingArt.Sawmill(), town.sawmill, map)

	local sellArea = Instance.new("Model")
	sellArea.Name = "SellArea"
	local zone = Kit.part(sellArea, "SellZone", WorldPlan.SellZoneSize, town.sellZone, Color3.new(1, 1, 1))
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	place(BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth), town.sellPad, sellArea)
	BuildingArt.PinPivotHeight(sellArea, 6)
	sellArea.Parent = map

	for _, spot in ipairs(town.shops) do
		local shop = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		shop.Name = spot.kind
		local counter = shop:FindFirstChild("Counter")
		assert(counter and counter:IsA("BasePart"), "[TownBuild] " .. spot.kind .. " has no Counter")
		shop.PrimaryPart = counter
		place(shop, spot.cframe, map)
	end

	local scenes = Instance.new("Folder")
	scenes.Name = "TownScenes"
	scenes.Parent = map
	for _, spot in ipairs(town.scenes) do
		local model = if spot.kind == "forge" then BuildingArt.SkyForgeCourt() else PropArt.Scene(spot.kind)
		if spot.kind == "fishing" then
			local sheet = model:FindFirstChild("Water")
			if sheet then
				sheet:Destroy()
			end
		end
		place(model, spot.cframe, scenes)
	end

	place(BuildingArt.Campsite(), town.campsite, map)
	for _, cf in ipairs(town.lamps) do
		place(BuildingArt.LampPost(), cf, map)
	end
	for _, fence in ipairs(BuiltMoves.Fences(town.fences)) do
		place(BuildingArt.Fence(fence.length, fence.noEndPosts), fence.cframe, map)
	end
	for _, prop in ipairs(town.props) do
		place(BuildingArt.Prop(prop.name, prop.seed), prop.cframe, map)
	end
	for _, sign in ipairs(town.signs) do
		place(BuildingArt.Signpost(sign.text, sign.lit, nil, nil, sign.noWrap, sign.panel), sign.cframe, map)
	end
	return map
end

return TownBuild
