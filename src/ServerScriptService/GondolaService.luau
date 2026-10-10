--!strict
-- GondolaService: the Skyroot Gondola up to the Aether Isles (BiomeData
-- "sky": rideSec, fee). Three stations, built by MapBuilder: GondolaTown by
-- the sawmill and GondolaBase at the Skyroot's foot ride up; GondolaTop on
-- the isles rides down to town. Each ride costs the fee (a money sink) and
-- takes rideSec: the player sits in a cabin that glides along the cable
-- (WorldPlan.GondolaPath: out of the station, up past the main isle's rim,
-- in under the top station's roof). Jumping out ends the ride early (and
-- you fall). The Riding attribute is set for the whole ride, so the isles
-- don't count it as a fall.
--
-- How the cabin moves (WLD-07). It is one rigid body: unanchored parts
-- welded to its Floor, the only part with mass, none of them colliding or
-- touching anything. Two rigid constraints on the Floor hold it, and its
-- seated rider, on the route: RidePosition (an AlignPosition: where) and
-- RideFacing (an AlignOrientation: level, facing along the route). Like a
-- truck (VehicleService), its physics goes to the rider's device, where
-- GondolaController moves RidePosition along the route every physics step
-- (Shared/GondolaRide: the same clock and the same easing as here). So the
-- rider glides at their own frame rate, and everyone else, the server too,
-- sees the cabin through Roblox's interpolated physics replication: nobody
-- sees it step. The server never moves the cabin itself, so nothing fights
-- over it. What the server keeps: the fee, when the ride sets off and when
-- it ends (by its own clock), the route (published on the cabin), a jump
-- out ending the ride, and the landing. If the cabin's physics ever stays
-- with the server (the handover failed), the server moves RidePosition
-- itself every Heartbeat (smooth on every screen the same way), and hands
-- the rider's character back to their device when the ride ends.
--   * Each rider has a cabin of their own. Riders are in the GondolaRider
--     collision group for the ride, which doesn't collide with itself, so
--     two cabins passing on the cable go through each other. Riders still
--     collide with everything else (the routes are clear of the stations,
--     the isle and the Skyroot: WorldPlan.spec, GondolaService.spec), so a
--     rider who jumps out lands on whatever is below.
--   * At the start, the rider's device is asked to stream in the station at
--     the other end (and the route on the way), so the isles are there when
--     they arrive.
--   * The seat can't be taken: nothing touches it, so only the rider sits
--     in it. A rider who is never seated ends the ride and gets the fee
--     back.
--   * Leaving, dying or being removed mid-ride ends it: the cabin goes, the
--     Heartbeat stops.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local BuildingArt = require(ReplicatedStorage.Shared.Art.BuildingArt)
local GondolaRide = require(ReplicatedStorage.Shared.GondolaRide)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local SkyQuestLogic = require(ReplicatedStorage.Shared.SkyQuestLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local GondolaService = {}

local CABIN_COLOR = Color3.fromRGB(122, 90, 60)
local RIDER_GROUP = "GondolaRider"
local BOARDING = 0.5 -- seconds the seat weld gets before an empty seat means the rider got out
local STREAM_SPACING = 120 -- studs between the points streamed in along a route
local STREAM_TIMEOUT = 10 -- seconds one of those requests may take
local STATION_RANGE = 20 -- studs from a station's platform a ride can start (its prompt reaches 10)

type Ride = {
	cabin: Model,
	conn: RBXScriptConnection?,
	groups: { [BasePart]: string }, -- the rider's parts' own collision groups, put back after
	serverDrove: boolean, -- the cabin's physics stayed with the server
}

local rides: { [Player]: Ride } = {}
local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local riderGroup = false -- RIDER_GROUP is registered

local function sky(): BiomeData.BiomeDef
	return BiomeData.Get("sky") :: BiomeData.BiomeDef
end

-- The cabin around its pivot (the Floor's middle), facing -Z, rigged: the
-- Floor is the only part with mass and everything else is welded to it;
-- nothing collides, touches or sits anyone down by touch. The body (floor,
-- posts, roof, seat) stays within 2.7 studs of the middle sideways and from
-- 0.2 below the pivot to 5.6 above it (the box WorldPlan.spec proves clear
-- of the stations, the isle and the Skyroot); the Hanger rod reaches up
-- toward the cable. RidePosition and RideFacing are left for the ride to aim.
local function buildCabin(): (Model, Seat, AlignPosition, AlignOrientation)
	local model = Instance.new("Model")
	model.Name = "GondolaCabin"
	local function part(name: string, size: Vector3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = CABIN_COLOR
		p.Material = Enum.Material.Wood
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = model
		return p
	end
	local floor = part("Floor", Vector3.new(5, 0.4, 5), Vector3.zero)
	floor.Massless = false
	for _, x in ipairs({ -2.3, 2.3 }) do
		for _, z in ipairs({ -2.3, 2.3 }) do
			part("Post", Vector3.new(0.3, 5, 0.3), Vector3.new(x, 2.7, z))
		end
	end
	part("Roof", Vector3.new(5.4, 0.4, 5.4), Vector3.new(0, 5.4, 0))
	part("Hanger", Vector3.new(0.3, 3, 0.3), Vector3.new(0, 7, 0))
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = CFrame.new(0, 0.7, 0)
	seat.Color = Color3.fromRGB(90, 60, 40)
	seat.Anchored = false
	seat.CanCollide = false
	seat.CanTouch = false -- nobody sits down in it by walking into it
	seat.Massless = true
	seat.Parent = model
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child ~= floor then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = floor
			weld.Part1 = child
			weld.Parent = child
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RideAttachment"
	attachment.Parent = floor
	-- Rigid: the constraints hold the cabin and its rider exactly where they
	-- say, whatever they weigh, so it never sags, swings or lags behind.
	local position = Instance.new("AlignPosition")
	position.Name = "RidePosition"
	position.Mode = Enum.PositionAlignmentMode.OneAttachment
	position.Attachment0 = attachment
	position.RigidityEnabled = true
	position.MaxForce = math.huge
	position.Responsiveness = 200
	position.Parent = floor
	local facing = Instance.new("AlignOrientation")
	facing.Name = "RideFacing"
	facing.Mode = Enum.OrientationAlignmentMode.OneAttachment
	facing.Attachment0 = attachment
	facing.RigidityEnabled = true
	facing.MaxTorque = math.huge
	facing.Responsiveness = 200
	facing.Parent = floor
	model.PrimaryPart = floor
	return model, seat, position, facing
end

-- Puts the rider's parts in RIDER_GROUP, and returns their own groups.
local function joinRiders(char: Model): { [BasePart]: string }
	local groups: { [BasePart]: string } = {}
	if not riderGroup then
		return groups
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			groups[d] = d.CollisionGroup
			d.CollisionGroup = RIDER_GROUP
		end
	end
	return groups
end

local function leaveRiders(groups: { [BasePart]: string })
	for part, group in pairs(groups) do
		if part.Parent and part.CollisionGroup == RIDER_GROUP then
			part.CollisionGroup = group
		end
	end
end

-- Whether the server still simulates the cabin (the handover didn't happen).
local function keptByServer(root: BasePart): boolean
	local ok, owner = pcall(function(): Player?
		return root:GetNetworkOwner()
	end)
	return ok and owner == nil
end

-- The rider's character back to their device, once the cabin has gone.
local function handBack(player: Player)
	task.defer(function()
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if player.Parent and root and root:IsA("BasePart") then
			pcall(function(): any
				root:SetNetworkOwner(player)
				return nil
			end)
		end
	end)
end

local function endRide(player: Player)
	local current = rides[player]
	rides[player] = nil
	if current then
		if current.conn then
			current.conn:Disconnect()
		end
		current.cabin:Destroy()
		leaveRiders(current.groups)
		if current.serverDrove then
			handBack(player)
		end
	end
	if player.Parent then
		player:SetAttribute("Riding", false)
	end
end

-- Asks the rider's device to stream in where `current` goes: the far
-- station first, then along the route. Never holds the ride up; stops when
-- it ends.
local function streamAhead(player: Player, current: Ride, path: { Vector3 })
	task.spawn(function()
		for _, point in ipairs(GondolaRide.StreamPoints(path, STREAM_SPACING)) do
			if rides[player] ~= current then
				return
			end
			pcall(function(): any
				player:RequestStreamAroundAsync(point, STREAM_TIMEOUT)
				return nil
			end)
		end
	end)
end

-- Rides `player` along `path` (where the cabin goes, start to end) and sets
-- them down at `landing`.
local function ride(player: Player, path: { Vector3 }, landing: CFrame)
	if rides[player] or not RateLimiter.Allow(player, "Gondola") then
		return
	end
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not char or not humanoid or humanoid.Health <= 0 then
		return
	end
	if humanoid.SeatPart then
		notify(player, "Hop out of your seat first. The gondola has room for you alone.")
		return
	end
	local gondola = sky().gondola
	if not gondola then
		return
	end
	if not EconomyService.SpendCash(player, gondola.fee, "gondola ride", "gondola") then
		notify(player, string.format("A gondola ride costs %s.", Util.formatCash(gondola.fee)))
		return
	end
	local rideSec = gondola.rideSec
	local cabin, seat, position, facing = buildCabin()
	local root = cabin.PrimaryPart :: BasePart
	local turn = GondolaRide.Facing(path)
	position.Position = path[1]
	facing.CFrame = turn
	cabin:PivotTo(CFrame.new(path[1]) * turn)
	local started = workspace:GetServerTimeNow()
	GondolaRide.Publish(cabin, { riderId = player.UserId, start = started, rideSec = rideSec, path = path })
	CollectionService:AddTag(cabin, GondolaRide.Tag)
	-- Always there on the rider's device; streamed in whole for everyone else.
	cabin.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	pcall(function(): any
		cabin:AddPersistentPlayer(player)
		return nil
	end)
	cabin.Parent = workspace
	pcall(function(): any
		seat:Sit(humanoid)
		return nil
	end)
	local current: Ride = { cabin = cabin, conn = nil, groups = joinRiders(char), serverDrove = false }
	rides[player] = current
	player:SetAttribute("Riding", true)
	pcall(function(): any
		root:SetNetworkOwner(player) -- the rider's device simulates it, and them in it
		return nil
	end)
	streamAhead(player, current, path)

	local boarded = false
	current.conn = RunService.Heartbeat:Connect(function()
		local elapsed = workspace:GetServerTimeNow() - started
		if seat.Occupant == humanoid then
			boarded = true
		end
		if (seat.Occupant ~= humanoid and elapsed > BOARDING) or humanoid.Health <= 0 then
			endRide(player) -- they jumped out (or died, or left)
			if not boarded and player.Parent then
				EconomyService.Refund(player, gondola.fee, "gondola ride (never seated)", "gondola")
				notify(player, "The gondola couldn't seat you, so your fare is back.")
			end
			return
		end
		local alpha = GondolaRide.Alpha(elapsed, rideSec)
		if keptByServer(root) then
			current.serverDrove = true
			position.Position = WorldPlan.AlongPath(path, alpha)
		end
		if alpha >= 1 then
			humanoid.Sit = false
			local seatWeld = seat:FindFirstChild("SeatWeld")
			if seatWeld then
				seatWeld:Destroy()
			end
			endRide(player)
			task.defer(function()
				if char.Parent then
					char:PivotTo(landing)
				end
			end)
		end
	end)
end

-- `map` is TimberlineMap, with the three stations; `notifyFn` shows a toast.
function GondolaService.Init(map: Instance, notifyFn: (Player, string) -> ())
	notify = notifyFn
	riderGroup = pcall(function(): any
		if not PhysicsService:IsCollisionGroupRegistered(RIDER_GROUP) then
			PhysicsService:RegisterCollisionGroup(RIDER_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, RIDER_GROUP, false)
		return nil
	end)
	Players.PlayerRemoving:Connect(endRide)
	task.spawn(function() -- MapBuilder may still be building the stations
		GondolaService._setup(map)
	end)
end

-- Whether this ride may set off: up needs the Gondola Pass, down never
-- does (nobody is stranded on the isles). A refusal toasts why and charges
-- nothing.
function GondolaService.MayRide(player: Player, direction: "up" | "down"): boolean
	local profile = ProfileService.GetProfile(player)
	local pass = profile ~= nil and ((profile :: any).gondolaPass == true or (profile :: any).skyPass == true)
	if SkyQuestLogic.CanRide(direction, pass) then
		return true
	end
	notify(player, SkyQuestLogic.RefuseText)
	return false
end

-- The gate sign by a station that rides up: the requirement in words
-- (GateWords; the fare is on the prompt). It stands off the platform's
-- front-left corner, past the steps, facing the way players walk in, and
-- collides with nothing.
GondolaService.GateSignOffset = CFrame.new(-10.5, -0.5, -8.5)

function GondolaService.GateSign(platform: BasePart): Model
	local sign = BuildingArt.Signpost("SKYROOT GONDOLA\n" .. SkyQuestLogic.GateWords)
	sign.Name = "GondolaGateSign"
	-- Built around the origin with its feet at y = 0, so move that frame (a
	-- bare PivotTo would put the sign's middle there and sink it).
	sign:PivotTo(platform.CFrame * GondolaService.GateSignOffset * sign:GetPivot())
	for _, d in ipairs(sign:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	sign.Parent = platform.Parent
	return sign
end

function GondolaService._setup(map: Instance)
	local function station(name: string): BasePart
		local model = map:WaitForChild(name, 30)
		local platform = if model then model:WaitForChild("Platform", 30) else nil
		assert(platform and platform:IsA("BasePart"), "[GondolaService] Missing station " .. name)
		return platform
	end
	local town, base, top = station("GondolaTown"), station("GondolaBase"), station("GondolaTop")
	local plan = WorldPlan.Sky()
	assert(plan, "[GondolaService] No sky biome")
	-- The cabin rides 1 stud above the platforms' centres, hanging from the
	-- cable 7.5 above that (MapBuilder draws it along the same route).
	local function upFrom(platform: BasePart): { Vector3 }
		local path = WorldPlan.GondolaPath(plan, platform.Position, platform.CFrame.ZVector, top.Position)
		for i, p in ipairs(path) do
			path[i] = p + Vector3.new(0, 1, 0)
		end
		return path
	end
	local townUp, baseUp = upFrom(town), upFrom(base)
	local townDown: { Vector3 } = {}
	for i = #townUp, 1, -1 do
		table.insert(townDown, townUp[i])
	end
	local function landingOn(platform: BasePart): CFrame
		return CFrame.new(platform.Position + Vector3.new(0, 4, 0))
	end
	local fee = Util.formatCash((sky().gondola :: { rideSec: number, fee: number }).fee)
	-- The prompt's own reach is checked by Roblox; this is the server's own
	-- look at where the player really is.
	local function near(player: Player, platform: BasePart): boolean
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		return root ~= nil and root:IsA("BasePart") and (root.Position - platform.Position).Magnitude <= STATION_RANGE
	end
	local function addPrompt(platform: BasePart, action: string, go: (Player) -> (), objectText: string?)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = action .. " (" .. fee .. ")"
		prompt.ObjectText = objectText or "Skyroot Gondola"
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		InputKit.PromptDefaults(prompt, "Interact")
		prompt.Parent = platform
		prompt.Triggered:Connect(function(player: Player)
			if near(player, platform) then
				go(player)
			end
		end)
	end
	-- Up needs the Gondola Pass (Gus's Charter); the words are on the
	-- prompt, the fare is in its action text.
	local upText = "Skyroot Gondola · " .. SkyQuestLogic.GateWords
	for _, platform in ipairs({ town, base }) do
		local ok, err = pcall(GondolaService.GateSign, platform)
		if not ok then
			warn("[GondolaService] gate sign: " .. tostring(err))
		end
	end
	addPrompt(town, "Ride up", function(player)
		if GondolaService.MayRide(player, "up") then
			ride(player, townUp, landingOn(top))
		end
	end, upText)
	addPrompt(base, "Ride up", function(player)
		if GondolaService.MayRide(player, "up") then
			ride(player, baseUp, landingOn(top))
		end
	end, upText)
	addPrompt(top, "Ride down", function(player)
		ride(player, townDown, landingOn(town))
	end)
end

-- For the tests (tests/GondolaService.spec.luau).
GondolaService._ride = ride
GondolaService._buildCabin = buildCabin

return GondolaService
