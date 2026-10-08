--!strict
-- HazardService: deep water at the map edge, and the dark of the Secret
-- Cave. Frost and the volcano drain stay with their own batches. No remote.
-- Init starts the tick.
--
-- Fair and readable (HazardLogic): a toast when a player nears the deep
-- water, another when they are in it, and the first damage tick only after
-- GameConfig.SeaGraceSec. The damage and tick are the existing WaterDamage
-- and WaterTickSec. Damage never overkills. The toast works the same on a
-- phone, a computer and an Xbox pad. The cave is dark, never harmful: one
-- toast per entry when the player has no Lantern.

local RunService = game:GetService("RunService")

local ClimateLogic = require(game:GetService("ReplicatedStorage").Shared.ClimateLogic)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local HazardLogic = require(game:GetService("ReplicatedStorage").Shared.HazardLogic)

local HazardService = {}

-- Stand-in for Remotes.Notify (set by Init, or by a spec).
HazardService.Notify = nil :: ((Player, string) -> ())?
-- Stand-in for the profile lookup (a spec's gear list).
HazardService.GearOf = nil :: ((Player) -> { string }?)?

local STEP_SEC = 0.5 -- how often positions are sampled; ticks accrue inside HazardLogic

local elapsed = 0
local seaState: { [Player]: HazardLogic.SeaState } = {}
local inCave: { [Player]: boolean } = {}
local exposureOf: { [Player]: number } = {}

local function notify(player: Player, text: string)
	local send = HazardService.Notify
	if send then
		send(player, text)
	end
end

local function gearOf(player: Player): { string }?
	local custom = HazardService.GearOf
	if custom then
		return custom(player)
	end
	local ok, service = pcall(function()
		return require(script.Parent.ProfileService)
	end)
	if not ok or type(service) ~= "table" then
		return nil
	end
	local profile = service.GetProfile(player)
	return if profile then profile.gear else nil
end

function HazardService.Forget(player: Player)
	seaState[player] = nil
	inCave[player] = nil
	exposureOf[player] = nil
	pcall(function()
		player:SetAttribute("Exposure", 0)
		player:SetAttribute("ClimateKind", "")
	end)
end

-- One climate step. BiomeService decides the hazard (gear, crater, biome)
-- and whether a seat is sheltering the player. This owns the meter, the
-- attributes, and the damage number. A nil hazard, or a respawn, clears it.
function HazardService.ApplyClimate(
	player: Player,
	hazard: ClimateLogic.Hazard?,
	sheltered: boolean,
	dt: number
): number
	local exposure, damage = ClimateLogic.Tick(exposureOf[player] or 0, dt, hazard ~= nil, sheltered, hazard)
	exposureOf[player] = exposure
	player:SetAttribute("Exposure", exposure)
	player:SetAttribute("ClimateKind", if hazard then hazard.kind else "")
	return damage
end

-- One player's pass at (x, z) for `dt` seconds. Exposed for specs.
function HazardService.Check(player: Player, x: number, z: number, health: number, dt: number): number
	local state = seaState[player]
	if state == nil then
		state = HazardLogic.NewSea()
		seaState[player] = state
	end
	local result = HazardLogic.StepSea(state, HazardLogic.SeaZone(x, z), dt, health)
	local text = HazardLogic.NoticeText(result.notice)
	if text then
		notify(player, text)
	end
	local dark = HazardLogic.InCave(x, z)
	if dark and not inCave[player] then
		if HazardLogic.CaveNeedsLight(x, z, gearOf(player)) then
			notify(player, HazardLogic.CaveDarkText)
		end
	end
	inCave[player] = dark
	return result.damage
end

function HazardService.Step(dt: number)
	elapsed += dt
	if elapsed < STEP_SEC then
		return
	end
	local span = elapsed
	elapsed = 0
	local Players = game:GetService("Players")
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local pos = root.Position
			local damage = HazardService.Check(player, pos.X, pos.Z, humanoid.Health, span)
			if damage > 0 then
				humanoid:TakeDamage(damage)
			end
		end
	end
end

function HazardService.Init(notifyFn: ((Player, string) -> ())?)
	if notifyFn then
		HazardService.Notify = notifyFn
	end
	pcall(function()
		game:GetService("Players").PlayerRemoving:Connect(HazardService.Forget)
		RunService.Heartbeat:Connect(function(dt: number)
			local ok, err = pcall(function()
				HazardService.Step(dt)
			end)
			if not ok then
				warn("[HazardService] " .. tostring(err))
			end
		end)
	end)
end

-- The tick the old service used, kept readable for the specs and the docs.
HazardService.TickSec = GameConfig.WaterTickSec

return HazardService
