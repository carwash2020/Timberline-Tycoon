--!strict
-- BuildMaterials: the loose slabs and ingots that fill a placed ghost, and
-- the ones a sold or undone piece gives back. Lane F. The rules live in
-- FillLogic / BuildCost / SlabData; this finds the parts in the world.
--
--   Slabs   parts tagged "Slab" (SlabData), attributes OwnerId and Uid.
--   Ingots  models named "Ingot" in Workspace.Mining (Lane M), attributes
--           Ore and OwnerId; a "CarryWeld" under one means someone holds it.
--
-- Nothing here yields. Take destroys the part and says whether it was
-- still there, so two fills in one frame cannot both use it.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SlabData = require(ReplicatedStorage.Shared.SlabData)

local BuildMaterials = {}

export type Entry = {
	uid: string,
	kind: string, -- "slab" | "ingot"
	ore: string?,
	ownerId: number,
	held: boolean,
	position: Vector3,
}

local live: { [string]: Instance } = {}

local function held(inst: Instance): boolean
	local by = inst:GetAttribute("HeldBy")
	if type(by) == "number" and by ~= 0 then
		return true
	end
	return inst:FindFirstChild("CarryWeld", true) ~= nil
end

local function positionOf(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

-- Every slab and ingot in the world that belongs to `userId`.
function BuildMaterials.Of(userId: number): { Entry }
	table.clear(live)
	local out: { Entry } = {}
	for _, inst in ipairs(CollectionService:GetTagged(SlabData.Tag)) do
		local owner = inst:GetAttribute("OwnerId")
		local at = positionOf(inst)
		if owner == userId and at and inst.Parent then
			local uid = inst:GetAttribute("Uid")
			local id = if type(uid) == "string" then uid else inst.Name
			live[id] = inst
			table.insert(out, { uid = id, kind = "slab", ownerId = userId, held = held(inst), position = at })
		end
	end
	local mining = Workspace:FindFirstChild("Mining")
	if mining then
		for _, inst in ipairs(mining:GetChildren()) do
			if inst:IsA("Model") and inst.Name == "Ingot" and inst:GetAttribute("OwnerId") == userId then
				local ore = inst:GetAttribute("Ore")
				local at = positionOf(inst)
				if type(ore) == "string" and at then
					local uid = inst:GetAttribute("Uid")
					local id = if type(uid) == "string" then uid else HttpService:GenerateGUID(false)
					live[id] = inst
					table.insert(out, {
						uid = id,
						kind = "ingot",
						ore = ore,
						ownerId = userId,
						held = held(inst),
						position = at,
					})
				end
			end
		end
	end
	return out
end

-- Destroys the part. False when it is already gone.
function BuildMaterials.Take(uid: string): boolean
	local inst = live[uid]
	live[uid] = nil
	if inst == nil or inst.Parent == nil then
		return false
	end
	inst:Destroy()
	return true
end

-- How many more slabs this player may have lying about.
function BuildMaterials.SlabRoom(userId: number): number
	local n = 0
	for _, inst in ipairs(CollectionService:GetTagged(SlabData.Tag)) do
		if inst:GetAttribute("OwnerId") == userId and inst.Parent then
			n += 1
		end
	end
	return math.max(0, SlabData.MaxLoose - n)
end

local slabFolder: Folder? = nil

-- A slab at `cf` for `userId`, ready to be carried.
function BuildMaterials.ReturnSlab(userId: number, cf: CFrame): boolean
	if BuildMaterials.SlabRoom(userId) < 1 then
		return false
	end
	local part = SlabData.Make(userId, HttpService:GenerateGUID(false))
	part.CFrame = cf
	part.Anchored = false
	local found = slabFolder
	if found == nil or found.Parent == nil then
		local existing = Workspace:FindFirstChild("Slabs")
		if existing and existing:IsA("Folder") then
			found = existing
		else
			local made = Instance.new("Folder")
			made.Name = "Slabs"
			made.Parent = Workspace
			found = made
		end
		slabFolder = found
	end
	part.Parent = found
	return true
end

local function mining(): any
	local ok, mod = pcall(function(): any
		return require(script.Parent.MiningService)
	end)
	return if ok then mod else nil
end

function BuildMaterials.IngotRoom(player: Player): number
	local mod = mining()
	if mod == nil or type(mod.IngotRoom) ~= "function" then
		return 0
	end
	return mod.IngotRoom(player)
end

function BuildMaterials.ReturnIngot(player: Player, ore: string, cf: CFrame): boolean
	local mod = mining()
	if mod == nil or type(mod.ReturnIngot) ~= "function" then
		return false
	end
	return mod.ReturnIngot(player, ore, cf) == true
end

return BuildMaterials
