--!strict
-- Lux Axe swing effect (pass 2005226878). Client only. The server decides
-- who owns it (attribute Pass_LuxAxe, and lux on the existing WorldFX "Cut").
-- One Trail and two emitters are built per axe and reused with Emit.
-- Nothing here changes the swing, the hitbox, or the cut ring.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AxeModels = require(ReplicatedStorage.Shared.Art.AxeModels)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local LuxEffect = require(ReplicatedStorage.Shared.LuxEffect)
local Net = require(ReplicatedStorage.Shared.Net)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local SwingLogic = require(ReplicatedStorage.Shared.SwingLogic)
local Quality = require(script.Parent.Quality)
local SwingPose = require(script.Parent.SwingPose)

local LuxFX = {}

local player = Players.LocalPlayer

type Fx = {
	trail: Trail,
	sparkle: ParticleEmitter,
	burst: ParticleEmitter,
	sparkleElapsed: number,
	cosmeticElapsed: number,
}

local built: { [Tool]: Fx } = {}

local function owns(): boolean
	return player:GetAttribute("Pass_LuxAxe") == true
end

local function handleOf(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end
	return nil
end

local function emitter(name: string, parent: Instance): ParticleEmitter
	local gold = LuxEffect.Gold
	local made = Instance.new("ParticleEmitter")
	made.Name = name
	made.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	made.Color = ColorSequence.new(gold)
	made.LightEmission = 1
	made.LightInfluence = 0
	made.Rate = 0
	made.Enabled = true
	made.Lifetime = NumberRange.new(0.25, 0.45)
	made.Speed = NumberRange.new(0.4, 1.6)
	made.SpreadAngle = Vector2.new(25, 25)
	made.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	made.Parent = parent
	return made
end

-- One trail, one sparkle, one burst. Called again returns the same ones.
local function ensure(tool: Tool): Fx?
	local existing = built[tool]
	if existing and existing.trail.Parent then
		return existing
	end
	local handle = handleOf(tool)
	if not handle then
		return nil
	end
	AxeModels.AddLuxAttachments(handle)
	local top = handle:FindFirstChild("TrailTop")
	local bottom = handle:FindFirstChild("TrailBottom")
	local burstAt = handle:FindFirstChild("LuxBurst")
	if not top or not top:IsA("Attachment") or not bottom or not bottom:IsA("Attachment") then
		return nil
	end
	local trail = Instance.new("Trail")
	trail.Name = "LuxTrail"
	trail.Color = ColorSequence.new(LuxEffect.Gold)
	trail.Lifetime = LuxEffect.TrailFull
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new(0.35)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Parent = handle

	local sparkle = emitter("LuxSparkle", handle)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Speed = NumberRange.new(0.1, 0.4)
	local burstParent: Instance = if burstAt and burstAt:IsA("Attachment") then burstAt else handle
	local burst = emitter("LuxBurst", burstParent)
	burst.Lifetime = NumberRange.new(0.2, 0.4)

	local fx: Fx = {
		trail = trail,
		sparkle = sparkle,
		burst = burst,
		sparkleElapsed = 0,
		cosmeticElapsed = 0,
	}
	built[tool] = fx
	return fx
end

local function equippedLux(): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("AxeId") == GameConfig.LuxAxeId then
			return child
		end
	end
	return nil
end

local function luxTool(character: Model): Tool?
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("AxeId") == GameConfig.LuxAxeId then
			return child
		end
	end
	return nil
end

-- The trail is on from the impact through the follow-through, on this
-- client and on anyone else's Lux axe we can see swinging. Cosmetic only.
local function syncTrails()
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local tool = if character then luxTool(character) else nil
		if not tool then
			continue
		end
		local fx = ensure(tool)
		if not fx then
			continue
		end
		local clip = SwingPose.ClipOf(other)
		local on = clip ~= nil and SwingLogic.TrailOn(clip)
		if on and not fx.trail.Enabled then
			fx.trail.Lifetime = LuxEffect.TrailLifetime(Quality.Tier())
		end
		fx.trail.Enabled = on
	end
end

function LuxFX.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		syncTrails()
		if not owns() then
			return
		end
		local tool = equippedLux()
		if not tool then
			return
		end
		local fx = ensure(tool)
		if not fx then
			return
		end
		fx.cosmeticElapsed += dt
		fx.sparkleElapsed += dt
		local budget = Quality.Budget()
		local due = QualityBudgets.CosmeticDue(budget.CosmeticHz, fx.cosmeticElapsed)
		if due then
			fx.cosmeticElapsed = 0
		end
		if LuxEffect.SparkleDue(budget.Tier, fx.sparkleElapsed, due) then
			fx.sparkleElapsed = 0
			fx.sparkle:Emit(1)
		end
	end)

	Net.Remote("WorldFX").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if kind ~= "Cut" or type(payload) ~= "table" or not owns() then
			return
		end
		local cut = payload :: { [string]: any }
		if cut.lux ~= true or cut.userId ~= player.UserId then
			return
		end
		local tool = equippedLux()
		if not tool then
			return
		end
		local fx = ensure(tool)
		if not fx then
			return
		end
		fx.burst:Emit(LuxEffect.BurstCount(Quality.Tier()))
	end)
end

return LuxFX
