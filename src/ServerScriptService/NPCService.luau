--!strict
-- NPCService: the townsfolk (Shared/NPCData; models from Art/CharacterArt).
-- Init(mapFolder) runs once the whole world is built, so it can find the
-- shop Counters, the sell zone and the gondola station to stand beside.
--
--   * Murph: a Persistent Model "Murph" directly under TimberlineMap
--     (QuestUI clones his Head, Beard, Beanie, Torso, LeftArm, RightArm
--     for its portrait and puts its Talk prompt on his Torso).
--   * Everyone else: Atomic models in a Folder "Townsfolk" under
--     TimberlineMap (each streams in whole, so a client never sees half a
--     person).
--   * Every NPC model is tagged "NPC" with attributes NPCId (and, from
--     CharacterArt, RootHeight). NPCController animates them on each
--     client (breathing, blinking, looking at you, waving, speech bubbles).
--   * Walkers: the server never moves them. They start at their route's
--     first waypoint; attributes Route (NPCData.EncodeRoute), Speed and
--     RouteOffset let every client place them from the shared server clock
--     (NPCData.RouteState), so all players see the same stroll for free.
--     Walkers don't collide (they'd shove players about); the others
--     block like a person would.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterArt = require(ReplicatedStorage.Shared.Art.CharacterArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local NPCData = require(ReplicatedStorage.Shared.NPCData)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local NPCService = {}

-- A part's CFrame and Size, looked up by model name (anywhere under the
-- map) and part name (a direct child of that model).
local function finder(map: Instance): (string, string) -> (CFrame?, Vector3?)
	return function(modelName: string, partName: string): (CFrame?, Vector3?)
		local model = map:FindFirstChild(modelName) or map:FindFirstChild(modelName, true)
		local part = if model then model:FindFirstChild(partName) else nil
		if part and part:IsA("BasePart") then
			return part.CFrame, part.Size
		end
		return nil, nil
	end
end

local function build(npc: NPCData.NPC, find: (string, string) -> (CFrame?, Vector3?)): Model
	local model = CharacterArt.Build(npc.look)
	model.Name = npc.id
	model:SetAttribute("NPCId", npc.id)
	local spot = npc.spot
	if spot.kind == "counter" or spot.kind == "beside" then
		local partName = if spot.kind == "counter" then "Counter" else spot.part or ""
		if not find(spot.model or "", partName) then
			warn(
				string.format(
					"[NPCService] %s: no %s.%s, standing at the fallback spot",
					npc.id,
					spot.model or "?",
					partName
				)
			)
		end
	end
	local feet = NPCData.SpotFor(npc, find)
	-- Never buried: if the ground is drawn above their feet, stand on it.
	local p = feet.Position
	local lifted = TerrainBuilder.LiftOnto(p.X, p.Y, p.Z)
	if lifted ~= p.Y then
		feet += Vector3.new(0, lifted - p.Y, 0)
	end
	Kit.placeAt(model, feet)
	local root = model.PrimaryPart
	if npc.route and root then
		model:SetAttribute("Route", NPCData.EncodeRoute(npc.route))
		model:SetAttribute("Speed", npc.speed or 4)
		model:SetAttribute("RouteOffset", NPCData.RouteOffset(npc.id))
		root.CanCollide = false
	end
	CollectionService:AddTag(model, "NPC")
	return model
end

function NPCService.Init(mapFolder: Instance)
	local find = finder(mapFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = mapFolder
	for _, npc in ipairs(NPCData.All()) do
		local ok, err = pcall(function()
			local model = build(npc, find)
			if npc.id == "Murph" then
				model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
				model.Parent = mapFolder
			else
				model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				model.Parent = folder
			end
		end)
		if not ok then
			warn(string.format("[NPCService] couldn't build %s: %s", npc.id, tostring(err)))
		end
	end
end

return NPCService
