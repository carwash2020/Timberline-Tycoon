--!strict
-- PlotDoors: the owner, or someone they allowed to interact, toggles a door
-- or a gate. The server moves the leaf
-- collider and sets Open. Clients tween the visual. A placed piece in the
-- open quarter refuses the open. A character in the doorway refuses the shut.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorLogic = require(ReplicatedStorage.Shared.DoorLogic)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)

local PlotDoors = {}

local lastAt: { [string]: number } = {}

function PlotDoors.Reset()
	table.clear(lastAt)
end

local function nums(part: BasePart): (number, number, number)
	local ox = part:GetAttribute("OX")
	local oy = part:GetAttribute("OY")
	local oz = part:GetAttribute("OZ")
	return if type(ox) == "number" then ox else 0,
		if type(oy) == "number" then oy else 0,
		if type(oz) == "number" then oz else 0
end

function PlotDoors.Apply(model: Model, blueprintId: string, open: boolean)
	local hinge = DoorLogic.HingeX
	local bp = PlotLogic.Blueprint(blueprintId)
	if bp and bp.hinge then
		hinge = bp.hinge
	end
	local pivot = model:GetPivot()
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") and child:GetAttribute("Leaf") == true then
			local ox, oy, oz = nums(child)
			child.CFrame = DoorLogic.WorldCF(pivot, Vector3.new(ox, oy, oz), hinge, open)
		end
	end
	model:SetAttribute("Open", open)
end

local function hostWall(item: PlotLogic.Placed, placed: { PlotLogic.Placed }): PlotLogic.Placed?
	if item.blueprintId ~= "Door" then
		return nil
	end
	for _, other in ipairs(placed) do
		if
			PlotLogic.DoorHosts[other.blueprintId] == true
			and other.x == item.x
			and other.z == item.z
			and other.rot == item.rot
			and (other.y or 0) == (item.y or 0)
		then
			return other
		end
	end
	return nil
end

-- Solids of other placed pieces. Skips this piece and, for a door, the
-- wall it hangs in (that wall's jambs are not "in the way").
function PlotDoors.Blockers(item: PlotLogic.Placed, placed: { PlotLogic.Placed }): { DoorLogic.Solid }
	local host = hostWall(item, placed)
	local out: { DoorLogic.Solid } = {}
	for _, other in ipairs(placed) do
		if other.uid ~= item.uid and other ~= host then
			local bp = PlotLogic.Blueprint(other.blueprintId)
			if bp then
				for _, box in ipairs(bp.boxes) do
					local vol = PlotLogic.OverlapBox(bp, box)
					table.insert(
						out,
						DoorLogic.WorldSolid(other.x, other.y or 0, other.z, other.rot, vol.offset, vol.size)
					)
				end
			end
		end
	end
	return out
end

export type Query = (cf: CFrame, size: Vector3, include: { Instance }) -> { BasePart }

-- Tests replace this. The default asks the world, then drops a hit that
-- only touches the box (a floor or a ceiling).
PlotDoors.Query = nil :: Query?

local function partSolid(part: BasePart): DoorLogic.Solid
	local pos = part.Position
	local size = part.Size
	local look = part.CFrame.LookVector
	local sx, sz = size.X, size.Z
	if math.abs(look.X) > math.abs(look.Z) then
		sx, sz = size.Z, size.X
	end
	return { pos.X, pos.Y, pos.Z, sx, size.Y, sz }
end

local function askWorld(cf: CFrame, size: Vector3, include: { Instance }): { BasePart }
	local custom = PlotDoors.Query
	if custom then
		return custom(cf, size, include)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local ok, hits = pcall(function()
		return workspace:GetPartBoundsInBox(cf, size, params)
	end)
	if not ok or type(hits) ~= "table" then
		return {}
	end
	return hits
end

function PlotDoors.ArcBlocked(
	item: PlotLogic.Placed,
	placed: { PlotLogic.Placed },
	plotCFrame: CFrame,
	include: { Instance }
): boolean
	if
		DoorLogic.ArcBlocked(item.blueprintId, item.x, item.y or 0, item.z, item.rot, PlotDoors.Blockers(item, placed))
	then
		return true
	end
	local centre, size = DoorLogic.Arc(item.blueprintId)
	if size.X <= 0 or #include == 0 then
		return false
	end
	local cf = plotCFrame
		* CFrame.new(item.x, item.y or 0, item.z)
		* CFrame.Angles(0, item.rot * math.pi / 2, 0)
		* CFrame.new(centre)
	local mine = DoorLogic.WorldSolid(item.x, item.y or 0, item.z, item.rot, centre, size)
	for _, part in ipairs(askWorld(cf, size, include)) do
		if DoorLogic.SolidsHit(mine, partSolid(part)) then
			return true
		end
	end
	return false
end

local function humanoid(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- True when a character stands in the closed doorway.
function PlotDoors.Occupied(item: PlotLogic.Placed, plotCFrame: CFrame): boolean
	local centre, size = DoorLogic.Doorway(item.blueprintId)
	local cf = plotCFrame
		* CFrame.new(item.x, item.y or 0, item.z)
		* CFrame.Angles(0, item.rot * math.pi / 2, 0)
		* CFrame.new(centre)
	local mine = DoorLogic.WorldSolid(item.x, item.y or 0, item.z, item.rot, centre, size)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ok, hits = pcall(function()
		return workspace:GetPartBoundsInBox(cf, size, params)
	end)
	if not ok or type(hits) ~= "table" then
		return false
	end
	for _, part in ipairs(hits) do
		if part:IsA("BasePart") and humanoid(part) and DoorLogic.SolidsHit(mine, partSolid(part)) then
			return true
		end
	end
	return false
end

function PlotDoors.Colliders(folder: Instance, skip: { [Instance]: boolean }): { Instance }
	local list: { Instance } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and not skip[child] then
			for _, part in ipairs(child:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					table.insert(list, part)
				end
			end
		end
	end
	return list
end

-- Toggles `item`. Returns (changed, hint).
function PlotDoors.Toggle(
	player: Player,
	model: Model,
	item: PlotLogic.Placed,
	placed: { PlotLogic.Placed },
	plotCFrame: CFrame,
	folder: Instance,
	now: number,
	allowed: boolean?
): (boolean, string?)
	local owner = model:GetAttribute("OwnerId")
	local ok, why = DoorLogic.MayToggle(
		if type(owner) == "number" then owner else -1,
		player.UserId,
		now,
		lastAt[item.uid],
		allowed
	)
	if not ok then
		return false, if why == "owner" then nil else nil
	end
	local open = model:GetAttribute("Open") == true
	if not open then
		local skip: { [Instance]: boolean } = { [model] = true }
		local host = hostWall(item, placed)
		if host then
			local hostModel = folder:FindFirstChild(host.uid)
			if hostModel then
				skip[hostModel] = true
			end
		end
		if PlotDoors.ArcBlocked(item, placed, plotCFrame, PlotDoors.Colliders(folder, skip)) then
			return false, DoorLogic.Hint
		end
	elseif PlotDoors.Occupied(item, plotCFrame) then
		return false, nil
	end
	lastAt[item.uid] = now
	PlotDoors.Apply(model, item.blueprintId, not open)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		prompt.ActionText = if not open then "Close" else "Open"
	end
	return true, nil
end

return PlotDoors
