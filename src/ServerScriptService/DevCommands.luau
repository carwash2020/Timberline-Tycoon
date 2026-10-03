--!strict
-- DevCommands: Studio-only chat commands for trying the v2 loop before all
-- of it exists (V2_PLAN.md §4a). Never on a live server: Init does nothing
-- outside Studio or under the v1 loop (and GameServer starts it only under
-- v2).
--   /spawnwood                  a few loose pieces in front of you: an oak
--                               limb, an oak trunk, a birch log and a whole
--                               pine trunk (the oak lifts, the pine drags)
--   /spawnwood <wood> [length]  one trunk of that wood (any part of its
--                               name), `length` studs long (default: the
--                               wood's whole trunk)
-- The pieces are v2-style loose wood, like the ones a felled tree leaves:
-- a Model "Wood_<uid>" tagged Wood under TimberlineMap/Wood, one block
-- section (its length along Y) with a cut face at each end in the wood's
-- core colour, unanchored, CustomPhysicalProperties(WoodDensity,
-- WoodFriction, WoodElasticity), and the attributes Uid, Owner (you),
-- WoodId, Kind, Volume (u³), Value ($), HeldBy. WoodService files them
-- like any cut piece (so GrabService, SellService and the axe know them),
-- and they're yours alone for PickupGraceSec, like freshly cut wood. At
-- most MaxPieces lie around at once: the oldest go first.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Tune = require(ReplicatedStorage.Shared.Tune)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local GrabService = require(script.Parent.GrabService)
local WoodService = require(script.Parent.WoodService)

local DevCommands = {}

DevCommands.MaxPieces = 40
DevCommands.MinLength = 1
DevCommands.MaxLength = 60

-- Each wood's trunk (V2_PLAN.md §3a), until WoodData's v2.shape has it.
local TRUNKS: { [string]: { thickness: number, length: number } } = {
	oak = { thickness = 2.0, length = 9 },
	birch = { thickness = 1.6, length = 15 },
	pine = { thickness = 2.6, length = 46 },
	maple = { thickness = 2.4, length = 8 },
	palmwood = { thickness = 1.8, length = 28 },
	frostwood = { thickness = 2.2, length = 38 },
	emberwood = { thickness = 2.4, length = 10 },
	phantomwood = { thickness = 2.0, length = 8 },
	lumenwood = { thickness = 2.6, length = 20 },
}

export type PieceSpec = { woodId: string, thickness: number, length: number }

-- The plain /spawnwood set: light, liftable, and too heavy to lift.
DevCommands.DefaultSet = {
	{ woodId = "oak", thickness = 0.8, length = 5 }, -- a limb
	{ woodId = "oak", thickness = 2.0, length = 9 }, -- a trunk: lifts
	{ woodId = "birch", thickness = 1.6, length = 7 }, -- a bucked log
	{ woodId = "pine", thickness = 2.6, length = 46 }, -- a whole trunk: only drags
} :: { PieceSpec }

local spawned: { Model } = {} -- oldest first
local lastCommand: { [Player]: number } = {}
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

-- `woodId`'s trunk: thickness and length in studs.
function DevCommands.Trunk(woodId: string): (number, number)
	local wood = WoodData.Get(woodId)
	local shape = if wood and wood.v2 then wood.v2.shape else nil
	local fallback = TRUNKS[woodId] or { thickness = 2, length = 8 }
	local thickness = if shape and type(shape.trunkThickness) == "number"
		then shape.trunkThickness
		else fallback.thickness
	local length = if shape and type(shape.trunkLength) == "number" then shape.trunkLength else fallback.length
	return thickness, length
end

-- The wood a name (any part of an id or display name) means.
local function findWood(query: string): WoodData.WoodDef?
	for _, wood in ipairs(WoodData.All()) do
		if string.find(wood.id, query, 1, true) or string.find(string.lower(wood.displayName), query, 1, true) then
			return wood
		end
	end
	return nil
end

-- What a chat message asks for: the pieces to spawn, or (nil, why not),
-- or (nil, nil) when it isn't this command.
function DevCommands.Parse(message: string): ({ PieceSpec }?, string?)
	local trimmed = string.gsub(message, "^%s*(.-)%s*$", "%1")
	local text = string.lower(trimmed)
	if text == "/spawnwood" then
		return table.clone(DevCommands.DefaultSet), nil
	end
	local query, lengthText = string.match(text, "^/spawnwood%s+(%S+)%s*(%S*)$")
	if not query then
		return nil, nil
	end
	local wood = findWood(query)
	if not wood then
		return nil, string.format("No wood matches '%s'.", query)
	end
	local thickness, length = DevCommands.Trunk(wood.id)
	if lengthText ~= "" then
		local n = tonumber(lengthText)
		if not n or n ~= n then
			return nil, "Usage: /spawnwood <wood> <length in studs>"
		end
		length = math.clamp(n, DevCommands.MinLength, DevCommands.MaxLength)
	end
	return { { woodId = wood.id, thickness = thickness, length = length } }, nil
end

-- A piece's volume in u³ and what it's worth as a log ($).
function DevCommands.Worth(spec: PieceSpec): (number, number)
	local u = GameConfig.WoodUnit
	local volume = spec.thickness * spec.thickness * spec.length / (u * u * u)
	local wood = WoodData.Get(spec.woodId)
	local price = if wood and wood.v2 then wood.v2.logPrice else 0
	return volume, volume * price
end

-- Where each piece lies, in front of `origin` (the character): one behind
-- the other, each across your path (its length along your right).
function DevCommands.Layout(origin: CFrame, pieces: { PieceSpec }): { CFrame }
	local look = origin.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = if forward.Magnitude > 1e-6 then forward.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local up = Vector3.new(0, 1, 0)
	local out: { CFrame } = {}
	local d = 5
	for _, spec in ipairs(pieces) do
		d += spec.thickness / 2
		local at = origin.Position + forward * d
		table.insert(out, CFrame.fromMatrix(at, up, right))
		d += spec.thickness / 2 + 1.5
	end
	return out
end

-- One loose piece, built around the origin (see the header).
function DevCommands.Build(spec: PieceSpec, ownerId: number, uid: string): Model
	local wood = WoodData.Get(spec.woodId)
	assert(wood and wood.v2, "[DevCommands] no v2 wood " .. spec.woodId)
	local v2 = wood.v2
	local t, length = spec.thickness, spec.length
	local physics = PhysicalProperties.new(
		Tune.Get("WoodDensity") :: number,
		Tune.Get("WoodFriction") :: number,
		Tune.Get("WoodElasticity") :: number
	)
	local model = Instance.new("Model")
	model.Name = "Wood_" .. uid
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local section = Instance.new("Part")
	section.Name = "Section"
	section.Size = Vector3.new(t, length, t)
	section.CFrame = CFrame.identity
	section.Material = Enum.Material.Wood
	section.Color = wood.trunkColor
	section.Anchored = false
	section.CanCollide = true
	section.CanQuery = true
	section.CanTouch = false
	section.CustomPhysicalProperties = physics
	section:SetAttribute("Section", 1)
	section.Parent = model
	model.PrimaryPart = section
	local material = (Enum.Material :: any)[v2.coreMaterial] or Enum.Material.Wood
	for _, side in ipairs({ 1, -1 }) do
		local face = Instance.new("Part")
		face.Name = "CutFace"
		face.Size = Vector3.new(0.86 * t, 0.06, 0.86 * t)
		face.CFrame = CFrame.new(0, side * (length / 2 + 0.03), 0)
		face.Material = material
		face.Color = Color3.fromHex(v2.core)
		face.Anchored = false
		face.Massless = true
		face.CanCollide = false
		face.CanQuery = false
		face.CanTouch = false
		face.CastShadow = false
		face.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = section
		weld.Part1 = face
		weld.Parent = face
	end
	local volume, value = DevCommands.Worth(spec)
	CollectionService:AddTag(model, "Wood")
	model:SetAttribute("Uid", uid)
	model:SetAttribute("Owner", ownerId)
	model:SetAttribute("WoodId", wood.id)
	model:SetAttribute("Kind", "log")
	model:SetAttribute("Volume", math.floor(volume * 100 + 0.5) / 100)
	model:SetAttribute("Value", math.floor(value * 100 + 0.5) / 100)
	model:SetAttribute("HeldBy", 0)
	model:SetAttribute("Dev", true)
	return model
end

-- Lays `pieces` on the ground in front of `player`, theirs. Returns how
-- many it spawned.
function DevCommands.Spawn(player: Player, pieces: { PieceSpec }): number
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local map = workspace:FindFirstChild("TimberlineMap")
	if not hrp or not hrp:IsA("BasePart") or not map then
		return 0
	end
	local folder = map:FindFirstChild("Wood")
	if not folder then
		local made = Instance.new("Folder")
		made.Name = "Wood"
		made.Parent = map
		folder = made
	end
	local ignore: { Instance } = { folder :: Instance }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local spots = DevCommands.Layout((hrp :: BasePart).CFrame, pieces)
	for i, spec in ipairs(pieces) do
		local spot = spots[i]
		local hit = workspace:Raycast(spot.Position + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
		local y = if hit then hit.Position.Y + spec.thickness / 2 + 0.25 else spot.Position.Y
		local model = DevCommands.Build(spec, player.UserId, Util.guid())
		model:PivotTo(spot.Rotation + Vector3.new(spot.Position.X, y, spot.Position.Z))
		model.Parent = folder
		WoodService.Register(model, { woodId = spec.woodId, nodes = {}, parts = {}, ownerId = player.UserId })
		table.insert(spawned, model)
	end
	while #spawned > DevCommands.MaxPieces do
		local oldest = table.remove(spawned, 1)
		if oldest then
			GrabService.ReleasePiece(oldest, "despawned")
			WoodService.Forget(oldest)
			oldest:Destroy()
		end
	end
	return #pieces
end

local function onChat(player: Player, message: string)
	local pieces, problem = DevCommands.Parse(message)
	if not pieces and not problem then
		return
	end
	-- Both chat hooks below can fire for one message; act once.
	local now = os.clock()
	if now - (lastCommand[player] or 0) < 0.5 then
		return
	end
	lastCommand[player] = now
	if not pieces then
		notify(player, problem :: string)
		return
	end
	local n = DevCommands.Spawn(player, pieces)
	if n > 0 then
		notify(
			player,
			string.format("Spawned %d piece%s of wood in front of you (Studio only).", n, if n == 1 then "" else "s")
		)
	end
end

-- `notifyFn` shows a toast. Studio and the v2 loop only: anywhere else
-- this does nothing.
function DevCommands.Init(notifyFn: (Player, string) -> ())
	if not RunService:IsStudio() then
		return
	end
	notify = notifyFn
	-- Current chat (TextChatService): a registered command.
	local command = Instance.new("TextChatCommand")
	command.Name = "SpawnWoodCommand"
	command.PrimaryAlias = "/spawnwood"
	command.Triggered:Connect(function(source: TextSource, message: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			onChat(player, message)
		end
	end)
	command.Parent = TextChatService
	-- Legacy chat fallback.
	local function watch(player: Player)
		player.Chatted:Connect(function(message: string)
			onChat(player, message)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCommand[player] = nil
	end)
end

return DevCommands
