--!strict
-- TownFX: small motions that make the town feel worked in, all local.
--   * The sawmill's big blade ("SawBlade" tag, MapBuilder) spins about its
--     own X axis (BuildingArt: its teeth are welded to it and follow).
--   * Campfire flames ("Flame" tag) flicker: they breathe in size and
--     brightness, each on its own phase.
-- Only what's near the camera moves. Streaming-safe: tagged parts come and
-- go through CollectionService signals.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TownFX = {}

local BLADE_SPEED = 7 -- radians per second
local NEAR = 260 -- studs from the camera

type Flame = { part: BasePart, size: Vector3, phase: number }

local blades: { [BasePart]: boolean } = {}
local flames: { [BasePart]: Flame } = {}

local function track(tag: string, add: (BasePart) -> (), remove: (BasePart) -> ())
	local function added(inst: Instance)
		if inst:IsA("BasePart") then
			add(inst)
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		added(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
		if inst:IsA("BasePart") then
			remove(inst)
		end
	end)
end

function TownFX.Start()
	track("SawBlade", function(part)
		blades[part] = true
	end, function(part)
		blades[part] = nil
	end)
	track("Flame", function(part)
		flames[part] = { part = part, size = part.Size, phase = (part.Position.X + part.Position.Z) % 6.28 }
	end, function(part)
		flames[part] = nil
	end)

	local t = 0
	RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		for blade in pairs(blades) do
			if blade.Parent and (blade.Position - eye).Magnitude < NEAR then
				blade.CFrame *= CFrame.Angles(BLADE_SPEED * dt, 0, 0)
			end
		end
		for part, flame in pairs(flames) do
			if part.Parent and (part.Position - eye).Magnitude < NEAR then
				local breathe = 1 + 0.14 * math.sin(t * 9 + flame.phase) + 0.06 * math.sin(t * 23 + flame.phase * 2)
				part.Size = flame.size * breathe
				part.Transparency = 0.08 + 0.12 * (0.5 + 0.5 * math.sin(t * 13 + flame.phase))
			end
		end
	end)
end

return TownFX
