--!strict
-- BiomeService: what the world's biomes do to players (rules in
-- Shared/BiomeData, gear in ItemCatalog.Gear).
--   * Tracks the biome each player stands in, on the Biome attribute (the
--     client names it when they arrive).
--   * Snowfields: walking is slower without the Insulated Coat.
--   * The Volcano: the ground burns without Heat Boots.
--   * Chopping a biome's trees needs that biome's gear (CanChop, called by
--     GameServer's ChopTree): Heat Boots on the Volcano, a Lantern in the
--     Gloam Hollow.
--   * At night a Lantern glows on whoever owns one.
-- Gear lives in profile.gear (bought at Hearth & Home, ShopService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ProfileService = require(script.Parent.ProfileService)
local RegionLogic = require(ReplicatedStorage.Shared.RegionLogic)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldClock = require(script.Parent.WorldClock)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)

local BiomeService = {}

local TICK = 0.5 -- seconds between checks
local LANTERN_LIGHT = "LanternLight"

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local burningWarned: { [Player]: boolean } = {}

local function gearSet(player: Player): { [string]: boolean }
	local set: { [string]: boolean } = {}
	local profile = ProfileService.GetProfile(player)
	if profile then
		for _, id in ipairs(profile.gear) do
			set[id] = true
		end
	end
	return set
end

local function gearName(id: string?): string
	local gear = if id then ItemCatalog.GetGear(id) else nil
	return if gear then gear.displayName else "the right gear"
end

-- Whether the player may chop a tree of `wood`, and what to tell them if not.
function BiomeService.CanChop(player: Player, wood: { biome: string, displayName: string }): (boolean, string?)
	local rules = BiomeData.Rules(BiomeData.Get(wood.biome), gearSet(player))
	if rules.canChop then
		return true, nil
	end
	return false,
		string.format(
			"You need %s to chop %s. Get it at Hearth & Home, by the sawmill.",
			gearName(rules.needs),
			string.lower(wood.displayName)
		)
end

local function setLantern(root: BasePart, on: boolean)
	local light = root:FindFirstChild(LANTERN_LIGHT)
	if on and not light then
		local l = Instance.new("PointLight")
		l.Name = LANTERN_LIGHT
		l.Color = Color3.fromRGB(255, 214, 140)
		l.Range = 24
		l.Brightness = 2
		l.Shadows = true
		l.Parent = root
	elseif not on and light then
		light:Destroy()
	end
end

local function update(player: Player)
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local pos = root.Position
	local biome = BiomeData.At(pos.X, pos.Z, pos.Y)
	local biomeId = if biome then biome.id else ""
	if biomeId == "" and WorldLayout.InNorthStrip(pos.X, pos.Z) then
		biomeId = "strip"
	end
	-- The named region (a meadow, the beach, the hidden reach) is finer
	-- than the biome disc. Set it first so the arrival toast names the
	-- place before any gear warning.
	local place = RegionLogic.At(pos.X, pos.Z, pos.Y)
	local regionId = if place then place.id else ""
	if player:GetAttribute("Region") ~= regionId then
		player:SetAttribute("Region", regionId)
	end
	if player:GetAttribute("Biome") ~= biomeId then
		player:SetAttribute("Biome", biomeId)
		burningWarned[player] = nil
	end

	local gear = gearSet(player)
	local rules = BiomeData.Rules(biome, gear)
	local speed = StarterPlayer.CharacterWalkSpeed * rules.speedFactor
	if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
		humanoid.WalkSpeed = speed
	end
	-- Only feet on the ground burn, and only in the crater column: riding
	-- in a truck, jumping, or standing elsewhere in the biome is safe.
	local grounded = humanoid.SeatPart == nil and humanoid.FloorMaterial ~= Enum.Material.Air
	local cone = WorldLayout.VolcanoCone
	local floorY = TerrainGen.HeightAt(cone.x, cone.z)
	local inHeat = WorldLayout.InHeatColumn(pos.X, pos.Z) and math.abs(pos.Y - floorY) < WorldLayout.HeatHeight
	if rules.burning and grounded and inHeat then
		humanoid:TakeDamage(GameConfig.LavaDamagePerSecond * TICK)
		if not burningWarned[player] then
			burningWarned[player] = true
			notify(player, string.format("The ground is scorching! %s keep you safe here.", gearName(rules.needs)))
		end
	end
	setLantern(root, gear.Lantern == true and WorldClock.IsNight())
end

-- `notifyFn` shows a toast (GameServer's notify).
function BiomeService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		for _, player in ipairs(Players:GetPlayers()) do
			update(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		burningWarned[player] = nil
	end)
end

return BiomeService
