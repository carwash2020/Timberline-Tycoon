--!strict
-- FerryService: Cap'n Moss's ferry to Ferry Island (WORLD_DESIGN §1, §11,
-- §15; the rules are FerryLogic's). One boat on the server's clock. It
-- leaves each dock every GameConfig.FerryIntervalSec; a crossing takes
-- FerryLogic.TravelSec.
--
--   * Boarding is a ProximityPrompt on each dock's deck (and the single
--     FerryBoard remote, which carries nothing: the server finds the dock
--     the player is at). It checks the boat is in, the player is on foot
--     and has the fare, then stands them on the deck. Nothing is charged
--     yet.
--   * At departure the server takes GameConfig.FerryFare through
--     EconomyService from each player on the deck, and welds them to it.
--     Someone short is stood back on the dock, uncharged. Loose cargo on
--     the deck (planks, logs, anything unanchored that is not a person or
--     a vehicle) is welded too. Trucks are refused: any vehicle on the deck
--     is moved back to the dock.
--   * On arrival the welds drop and riders and cargo are set down on the
--     dock. A rider who leaves or resets mid-crossing loses nothing but
--     themselves: the cargo stays welded until the boat ties up.
--
-- Only EconomyService changes cash. Robux never pays a fare.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FerryLogic = require(ReplicatedStorage.Shared.FerryLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local LandmarkArt = require(ReplicatedStorage.Shared.Art.LandmarkArt)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local EconomyService = require(script.Parent.EconomyService)
local RateLimiter = require(script.Parent.RateLimiter)

local FerryService = {}

local MAX_CARGO = 60 -- loose parts one crossing carries

type Side = {
	name: FerryLogic.Dock,
	deck: BasePart,
	prompt: ProximityPrompt?,
}

local sides: { [string]: Side } = {}
local boat: Model? = nil
local deckPart: BasePart? = nil
local weldFolder: Folder? = nil
local lastLeg: FerryLogic.Leg? = nil
local textClock = 0
local bound = false
local riders: { [Player]: boolean } = {}
local cargo: { { part: BasePart, rel: CFrame } } = {}
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

-- The server's clock. A spec swaps it.
FerryService.Now = function(): number
	return workspace:GetServerTimeNow()
end

local function standPoint(side: Side): Vector3
	return side.deck.CFrame.Position + Vector3.new(0, side.deck.Size.Y / 2 + FerryLogic.StandHeight, 0)
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function deckFrame(): CFrame?
	local deck = deckPart
	return if deck then deck.CFrame else nil
end

-- A point in the deck's own space (studs from its centre).
local function onDeck(position: Vector3): boolean
	local frame = deckFrame()
	if not frame then
		return false
	end
	local rel = frame:PointToObjectSpace(position)
	return FerryLogic.Aboard(rel.X, rel.Y, rel.Z)
end

local function nearestSide(position: Vector3): Side?
	local best: Side? = nil
	local bestDist = FerryLogic.BoardRange
	for _, side in pairs(sides) do
		local d = (Vector3.new(side.deck.CFrame.Position.X, position.Y, side.deck.CFrame.Position.Z) - position).Magnitude
		if d <= bestDist then
			best = side
			bestDist = d
		end
	end
	return best
end

local function stand(player: Player, point: Vector3)
	local char = player.Character
	local root = rootOf(player)
	if char and root then
		char:PivotTo(CFrame.new(point))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function moveBoat(state: FerryLogic.State)
	local model = boat
	if not model then
		return
	end
	local x, z, yaw = FerryLogic.Pose(state)
	local y = WorldLayout.SeaLevel + FerryLogic.DeckRise
	model:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
end

-- The players on the deck right now (on foot).
local function ridersOnDeck(): { Player }
	local out: { Player } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root, humanoid = rootOf(player)
		if root and humanoid and humanoid.SeatPart == nil and onDeck(root.CFrame.Position) then
			table.insert(out, player)
		end
	end
	return out
end

-- A vehicle model on the deck goes back to the dock: no trucks aboard.
local function clearVehicles(side: Side)
	local frame = deckFrame()
	if not frame then
		return
	end
	for _, model in ipairs(CollectionService:GetTagged("Truck")) do
		if model:IsA("Model") and onDeck(model:GetPivot().Position) then
			model:PivotTo(
				CFrame.new(standPoint(side) + Vector3.new(0, 4, 0)) * (model:GetPivot() - model:GetPivot().Position)
			)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.AssemblyLinearVelocity = Vector3.zero
					d.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	end
end

local function loosePartsOnDeck(): { BasePart }
	local deck, model = deckPart, boat
	if not deck or not model then
		return {}
	end
	local out: { BasePart } = {}
	local ok, parts = pcall(function(): { BasePart }
		return workspace:GetPartBoundsInBox(
			deck.CFrame * CFrame.new(0, FerryLogic.AboardHeight / 2, 0),
			Vector3.new(FerryLogic.DeckWidth, FerryLogic.AboardHeight, FerryLogic.DeckLength)
		)
	end)
	if not ok then
		return out
	end
	for _, part in ipairs(parts) do
		if #out >= MAX_CARGO then
			break
		end
		if part.Anchored or part:IsDescendantOf(model) then
			continue
		end
		local holder = part:FindFirstAncestorOfClass("Model")
		if holder and (holder:FindFirstChildOfClass("Humanoid") or CollectionService:HasTag(holder, "Truck")) then
			continue
		end
		table.insert(out, part)
	end
	return out
end

local function weld(a: BasePart, b: BasePart)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = a
	joint.Part1 = b
	joint.Parent = weldFolder or a
end

-- The boat has just left `dock`: charge and weld whoever is aboard.
local function depart(dock: FerryLogic.Dock)
	local deck = deckPart
	local side = sides[dock]
	if not deck or not side then
		return
	end
	clearVehicles(side)
	riders = {}
	for _, player in ipairs(ridersOnDeck()) do
		local root = rootOf(player)
		if root then
			if EconomyService.SpendCash(player, GameConfig.FerryFare, "ferry fare", "Ferry") then
				weld(deck, root)
				riders[player] = true
				notify(player, FerryLogic.PaidText())
			else
				stand(player, standPoint(side))
				notify(player, FerryLogic.ShortText())
			end
		end
	end
	cargo = {}
	for _, part in ipairs(loosePartsOnDeck()) do
		weld(deck, part)
		-- Where it sits on the deck, so it is set down in the same spot on
		-- the dock whatever the crossing did to it.
		table.insert(cargo, { part = part, rel = deck.CFrame:ToObjectSpace(part.CFrame) })
	end
end

-- The boat has just tied up at `dock`: drop the welds and set everyone down.
local function arrive(dock: FerryLogic.Dock)
	local deck = deckPart
	local side = sides[dock]
	if not deck or not side then
		return
	end
	local folder = weldFolder
	if folder then
		folder:ClearAllChildren()
	end
	local point = standPoint(side)
	local index = 0
	for player in pairs(riders) do
		if player.Parent then
			index += 1
			local sx, sz = FerryLogic.Slot(index)
			stand(player, point + Vector3.new(sx / 2, 0, sz / 2))
		end
	end
	riders = {}
	local landing = CFrame.new(side.deck.CFrame.Position + Vector3.new(0, side.deck.Size.Y / 2 + deck.Size.Y / 2, 0))
	for _, item in ipairs(cargo) do
		local part = item.part
		if part.Parent then
			part.CFrame = landing * item.rel
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	cargo = {}
end

-- Seeing the boat's leg change is how a departure and an arrival are
-- noticed. `now` is injectable.
function FerryService.Step(now: number?)
	local clock = now or FerryService.Now()
	local state = FerryLogic.State(clock)
	local departed = FerryLogic.Departed(lastLeg, state.leg)
	if departed then
		depart(departed)
	end
	if state.docked == nil or lastLeg ~= state.leg then
		moveBoat(state)
	end
	local arrived = FerryLogic.Arrived(lastLeg, state.leg)
	if arrived then
		arrive(arrived)
	end
	lastLeg = state.leg
	if clock - textClock >= 1 then
		textClock = clock
		for _, side in pairs(sides) do
			local prompt = side.prompt
			if prompt then
				local text = FerryLogic.ObjectText(clock, side.name)
				if prompt.ObjectText ~= text then
					prompt.ObjectText = text
				end
			end
		end
	end
end

-- Stands `player` on the boat. Returns "boarded", "aboard" (already on the
-- deck), "gone", "far", "truck", "away" or "short"; nothing is charged yet.
function FerryService.Board(player: Player, now: number?): string
	local root, humanoid = rootOf(player)
	if not root or not humanoid then
		return "gone"
	end
	local clock = now or FerryService.Now()
	-- Already on the deck: nothing to do (and they are no longer within
	-- reach of a dock, so this comes before the dock check).
	if onDeck(root.CFrame.Position) then
		local docked = FerryLogic.State(clock).docked
		if docked then
			notify(player, FerryLogic.AboardText(clock, docked))
		end
		return "aboard"
	end
	local side = nearestSide(root.CFrame.Position)
	local deck = deckPart
	if not side or not deck then
		return "far"
	end
	if humanoid.SeatPart ~= nil then
		notify(player, FerryLogic.TruckText())
		return "truck"
	end
	if not FerryLogic.CanBoard(clock, side.name) then
		notify(player, FerryLogic.AwayText(clock, side.name))
		return "away"
	end
	if EconomyService.GetCash(player) < GameConfig.FerryFare then
		notify(player, FerryLogic.ShortText())
		return "short"
	end
	local index = #ridersOnDeck() + 1
	local sx, sz = FerryLogic.Slot(index)
	local top = deck.Size.Y / 2 + FerryLogic.StandHeight
	stand(player, (deck.CFrame * CFrame.new(sx, top, sz)).Position)
	notify(player, FerryLogic.AboardText(clock, side.name))
	return "boarded"
end

-- One budgeted request to board: the remote and the docks' prompts both come here.
function FerryService.Request(player: Player)
	if RateLimiter.Allow(player, "FerryBoard") then
		FerryService.Board(player)
	end
end

function FerryService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(FerryService.Request)
end

local function addPrompt(side: Side)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FerryPrompt"
	prompt.ActionText = FerryLogic.ActionText()
	prompt.ObjectText = FerryLogic.ObjectText(FerryService.Now(), side.name)
	prompt.MaxActivationDistance = FerryLogic.PromptRange
	prompt.HoldDuration = 0
	InputKit.PromptDefaults(prompt, "Buy")
	prompt.Parent = side.deck
	prompt.Triggered:Connect(FerryService.Request)
	side.prompt = prompt
end

-- Binds the world: the two dock decks (MapBuilder tags both "FerryDock";
-- the one nearer WorldLayout.FerryDock is the mainland's), the boat and the
-- loop. Called with one deck per side in a spec.
function FerryService.Bind(mainDeck: BasePart, islandDeck: BasePart, parent: Instance)
	sides = {
		main = { name = "main", deck = mainDeck, prompt = nil },
		island = { name = "island", deck = islandDeck, prompt = nil },
	}
	local model = LandmarkArt.FerryBoat()
	local deck = model:FindFirstChild("Deck")
	assert(deck and deck:IsA("BasePart"), "[FerryService] The boat has no deck")
	deckPart = deck
	local folder = Instance.new("Folder")
	folder.Name = "FerryWelds"
	folder.Parent = model
	weldFolder = folder
	boat = model
	Players.PlayerRemoving:Connect(function(player: Player)
		riders[player] = nil
	end)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	moveBoat(FerryLogic.State(FerryService.Now()))
	model.Parent = parent
	for _, side in pairs(sides) do
		addPrompt(side)
	end
	lastLeg = FerryLogic.State(FerryService.Now()).leg
end

-- For the tests (tests/FerryService.spec.luau): the toast sink without SetupWorld.
function FerryService._setNotify(fn: (Player, string) -> ())
	notify = fn
end

function FerryService.SetupWorld(map: Instance, notifyFn: (Player, string) -> ())
	notify = notifyFn
	task.spawn(function()
		local decks: { BasePart } = {}
		for _ = 1, 60 do
			decks = {}
			for _, tagged in ipairs(CollectionService:GetTagged("FerryDock")) do
				if tagged:IsA("BasePart") and tagged:IsDescendantOf(map) then
					table.insert(decks, tagged)
				end
			end
			if #decks >= 2 then
				break
			end
			task.wait(0.5)
		end
		if #decks < 2 then
			warn("[FerryService] The ferry docks are missing; no ferry")
			return
		end
		local dock = WorldLayout.FerryDock
		table.sort(decks, function(a: BasePart, b: BasePart): boolean
			local da = (a.CFrame.Position.X - dock.x) ^ 2 + (a.CFrame.Position.Z - dock.z) ^ 2
			local db = (b.CFrame.Position.X - dock.x) ^ 2 + (b.CFrame.Position.Z - dock.z) ^ 2
			return da < db
		end)
		FerryService.Bind(decks[1], decks[2], map)
		local ok = pcall(function()
			RunService.Heartbeat:Connect(function()
				local stepOk, err = pcall(function()
					FerryService.Step()
				end)
				if not stepOk then
					warn("[FerryService] " .. tostring(err))
				end
			end)
		end)
		if not ok then
			warn("[FerryService] No Heartbeat; the ferry will not sail")
		end
	end)
end

return FerryService
