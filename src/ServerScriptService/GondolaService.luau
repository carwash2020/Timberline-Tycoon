--!strict
-- GondolaService: the Skyroot Gondola up to the Aether Isles (BiomeData
-- "sky": rideSec, fee). Three stations, built by MapBuilder: GondolaTown by
-- the sawmill and GondolaBase at the Skyroot's foot ride up; GondolaTop on
-- the isles rides down to town. Each ride costs the fee (a money sink) and
-- takes rideSec: the player sits in a cabin that the server glides along
-- the cable. Jumping out ends the ride early (and you fall). The Riding
-- attribute is set for the whole ride, so the isles don't count it as a fall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local RateLimiter = require(script.Parent.RateLimiter)

local GondolaService = {}

local CABIN_COLOR = Color3.fromRGB(122, 90, 60)

type Ride = { cabin: Model, conn: RBXScriptConnection? }

local rides: { [Player]: Ride } = {}
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

local function sky(): BiomeData.BiomeDef
	return BiomeData.Get("sky") :: BiomeData.BiomeDef
end

local function buildCabin(): (Model, Seat)
	local model = Instance.new("Model")
	model.Name = "GondolaCabin"
	local function part(name: string, size: Vector3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = CABIN_COLOR
		p.Material = Enum.Material.Wood
		p.Anchored = true
		p.Parent = model
		return p
	end
	local floor = part("Floor", Vector3.new(5, 0.4, 5), Vector3.zero)
	for _, x in ipairs({ -2.3, 2.3 }) do
		for _, z in ipairs({ -2.3, 2.3 }) do
			local post = part("Post", Vector3.new(0.3, 5, 0.3), Vector3.new(x, 2.7, z))
			post.CanCollide = false
		end
	end
	part("Roof", Vector3.new(5.4, 0.4, 5.4), Vector3.new(0, 5.4, 0))
	local hanger = part("Hanger", Vector3.new(0.3, 3, 0.3), Vector3.new(0, 7, 0))
	hanger.CanCollide = false
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = CFrame.new(0, 0.7, 0)
	seat.Color = Color3.fromRGB(90, 60, 40)
	seat.Anchored = true
	seat.Parent = model
	model.PrimaryPart = floor
	return model, seat
end

local function endRide(player: Player)
	local ride = rides[player]
	rides[player] = nil
	if ride then
		if ride.conn then
			ride.conn:Disconnect()
		end
		ride.cabin:Destroy()
	end
	if player.Parent then
		player:SetAttribute("Riding", false)
	end
end

-- Rides `player` from `from` to `to` (cable points) and sets them down at `landing`.
local function ride(player: Player, from: Vector3, to: Vector3, landing: CFrame)
	if rides[player] or not RateLimiter.Allow(player, "Gondola") then
		return
	end
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not char or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then
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
	local cabin, seat = buildCabin()
	local flatDir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local facing = if flatDir.Magnitude > 1 then CFrame.lookAt(Vector3.zero, flatDir) else CFrame.identity
	cabin:PivotTo(CFrame.new(from) * facing.Rotation)
	cabin.Parent = workspace
	seat:Sit(humanoid)
	player:SetAttribute("Riding", true)
	local current: Ride = { cabin = cabin, conn = nil }
	rides[player] = current

	local started = os.clock()
	current.conn = RunService.Heartbeat:Connect(function()
		if seat.Occupant == nil and os.clock() - started > 0.5 then
			endRide(player) -- they jumped out
			return
		end
		local alpha = math.clamp((os.clock() - started) / gondola.rideSec, 0, 1)
		cabin:PivotTo(CFrame.new(from:Lerp(to, alpha)) * facing.Rotation)
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
	Players.PlayerRemoving:Connect(endRide)
	task.spawn(function() -- MapBuilder may still be building the stations
		GondolaService._setup(map)
	end)
end

function GondolaService._setup(map: Instance)
	local function station(name: string): BasePart
		local model = map:WaitForChild(name, 30)
		local platform = if model then model:WaitForChild("Platform", 30) else nil
		assert(platform and platform:IsA("BasePart"), "[GondolaService] Missing station " .. name)
		return platform
	end
	local town, base, top = station("GondolaTown"), station("GondolaBase"), station("GondolaTop")
	-- The cabin hangs from the cable 8 studs above each platform.
	local function cablePoint(platform: BasePart): Vector3
		return platform.Position + Vector3.new(0, 1, 0)
	end
	local function landingOn(platform: BasePart): CFrame
		return CFrame.new(platform.Position + Vector3.new(0, 4, 0))
	end
	local fee = Util.formatCash((sky().gondola :: { rideSec: number, fee: number }).fee)
	local function addPrompt(platform: BasePart, action: string, go: (Player) -> ())
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = action .. " (" .. fee .. ")"
		prompt.ObjectText = "Skyroot Gondola"
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.Parent = platform
		prompt.Triggered:Connect(go)
	end
	addPrompt(town, "Ride up", function(player)
		ride(player, cablePoint(town), cablePoint(top), landingOn(top))
	end)
	addPrompt(base, "Ride up", function(player)
		ride(player, cablePoint(base), cablePoint(top), landingOn(top))
	end)
	addPrompt(top, "Ride down", function(player)
		ride(player, cablePoint(top), cablePoint(town), landingOn(town))
	end)
end

return GondolaService
