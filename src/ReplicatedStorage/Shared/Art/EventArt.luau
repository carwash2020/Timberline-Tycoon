--!strict
-- EventArt: the Halloween event's looks (B14). Pure (see Kit): Instance.new
-- and datatypes only. Builders return a Model around the origin, the ground
-- at y = 0 and the face toward -Z, decoration only (no collisions, clicks
-- or touches; small parts cast no shadow).
--   Pumpkin(seed)   a jack-o'-lantern: orange body, stem, glowing face, a
--                   warm light (seed varies size and tint)
--   PumpkinPatch(seed)  a big one with a small one beside it
--   Hat()           the Pumpkin Hat, a small pumpkin sized for a head
--                   (HatBase is the part that welds to the head)

local Kit = require(script.Parent.Kit)

local EventArt = {}

local ORANGE = Color3.fromRGB(232, 118, 28)
local STEM = Color3.fromRGB(86, 104, 48)
local GLOW = Color3.fromRGB(255, 190, 80)
local DARK = Color3.fromRGB(70, 36, 14)

-- A jack-o'-lantern `size` studs across at (0, 0, 0) on the ground.
local function pumpkin(parent: Instance, size: number, rng: Kit.Rng, lit: boolean): Model
	local model = Kit.model("Pumpkin", parent)
	local tint = Kit.vary(ORANGE, rng, 0.06)
	local h = size * 0.82
	Kit.decor(Kit.ellipsoid(model, "Body", Vector3.new(size, h, size), CFrame.new(0, h / 2, 0), tint))
	-- Two ribs, so it reads as a pumpkin and not a ball.
	for _, side in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.ellipsoid(
				model,
				"Rib",
				Vector3.new(size * 0.55, h * 0.96, size * 0.9),
				CFrame.new(side * size * 0.24, h / 2, 0),
				Kit.shade(tint, -0.06)
			),
			false
		)
	end
	Kit.decor(
		Kit.part(
			model,
			"Stem",
			Vector3.new(size * 0.14, size * 0.2, size * 0.14),
			CFrame.new(0, h + size * 0.04, 0) * CFrame.Angles(0, 0, math.rad(8)),
			STEM,
			Enum.Material.Wood
		),
		false
	)
	-- The face on the -Z side: two triangular eyes and a grin, set into the skin.
	local faceZ = -size * 0.47
	local material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local color = if lit then GLOW else DARK
	for _, side in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.part(
				model,
				"Eye",
				Vector3.new(size * 0.15, size * 0.15, size * 0.06),
				CFrame.new(side * size * 0.2, h * 0.6, faceZ) * CFrame.Angles(0, 0, math.rad(45)),
				color,
				material
			),
			false
		)
	end
	Kit.decor(
		Kit.part(
			model,
			"Mouth",
			Vector3.new(size * 0.5, size * 0.1, size * 0.06),
			CFrame.new(0, h * 0.32, faceZ + size * 0.02),
			color,
			material
		),
		false
	)
	for _, side in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.part(
				model,
				"Tooth",
				Vector3.new(size * 0.1, size * 0.1, size * 0.06),
				CFrame.new(side * size * 0.2, h * 0.38, faceZ + size * 0.02),
				color,
				material
			),
			false
		)
	end
	if lit then
		local glow = model:FindFirstChild("Mouth") :: BasePart
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 70)
		light.Range = 9
		light.Brightness = 1.1
		light.Shadows = false
		light.Parent = glow
	end
	return model
end

function EventArt.Pumpkin(seed: number): Model
	local rng = Kit.rng(seed)
	return pumpkin(nil :: any, 2.2 + rng:next() * 0.8, rng, true)
end

-- A big jack-o'-lantern with a small unlit one beside it.
function EventArt.PumpkinPatch(seed: number): Model
	local rng = Kit.rng(seed)
	local patch = Kit.model("PumpkinPatch")
	local big = pumpkin(patch, 2.6 + rng:next() * 0.6, rng, true)
	big.Name = "Big"
	local small = pumpkin(patch, 1.4 + rng:next() * 0.4, rng, false)
	small.Name = "Small"
	local shift = CFrame.new(2.4, 0, -0.6) * CFrame.Angles(0, math.rad(-20), 0)
	for _, d in ipairs(small:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = shift * d.CFrame
		end
	end
	return patch
end

-- The Pumpkin Hat: about 1.3 studs across. HatBase (the stem end, pointing
-- down) is where it welds to the head, so the model's origin is the
-- underside of the hat.
function EventArt.Hat(): Model
	local rng = Kit.rng(2026)
	local model = pumpkin(nil :: any, 1.3, rng, false)
	model.Name = "PumpkinHat"
	local base = Kit.part(
		model,
		"HatBase",
		Vector3.new(0.4, 0.2, 0.4),
		CFrame.new(0, 0.1, 0),
		ORANGE,
		Enum.Material.SmoothPlastic
	)
	Kit.decor(base, false)
	base.Transparency = 1
	model.PrimaryPart = base
	return model
end

return EventArt
