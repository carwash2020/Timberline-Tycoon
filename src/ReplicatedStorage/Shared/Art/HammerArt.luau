--!strict
-- HammerArt: the carpenter's hammer every player carries (BUILD_SYSTEM.md).
-- A wooden haft with a wrapped grip and a knob, a steel head with a flat
-- striking face forward and a short claw behind, and a dark band where the
-- head meets the wood. Chunky and low-poly like the axes, so it reads at
-- hotbar size. Pure (see Kit).
--
-- Contract (the same as AxeArt, so a Tool is built the same way):
--   * Build() returns a Model standing on its foot: the haft's foot at
--     y = 0, the striking face toward -Z (forward). PrimaryPart "Handle"
--     (a Tool needs it); every other part is welded to it.
--   * Held(): Build, then unanchored, massless and non-colliding.
--   * Grip(pitch?): the Tool.Grip that puts the hand near the foot with the
--     face forward. `pitch` (radians, positive = head tipped back) is what
--     the swing animation moves (HammerLogic.Swing).
--   * StrikePoint: where the face is, from the foot of the haft, for the
--     dust and the knock.

local Kit = require(script.Parent.Kit)

local HammerArt = {}

local LEN = 1.9 -- the haft, studs
local GRIP_FROM_FOOT = 0.7
local LEAN = 0.2 -- radians the head leans forward in the hand
local HEAD_Y = LEN - 0.12

HammerArt.Length = LEN
-- The centre of the striking face, relative to the haft's foot.
HammerArt.StrikePoint = Vector3.new(0, HEAD_Y, -0.62)

local WOOD = Color3.fromRGB(150, 98, 56)
local LEATHER = Color3.fromRGB(104, 62, 36)
local STEEL = Color3.fromRGB(128, 134, 142)
local STEEL_DARK = Color3.fromRGB(86, 90, 98)
local STEEL_FACE = Color3.fromRGB(176, 182, 190)

local function add(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Kit.part(model, name, size, cf, color, material)
	Kit.decor(p, false)
	return p
end

function HammerArt.Build(): Model
	local model = Kit.model("Hammer")
	local handle =
		Kit.part(model, "Handle", Vector3.new(0.24, LEN, 0.3), CFrame.new(0, LEN / 2, 0), WOOD, Enum.Material.Wood)
	handle.CanTouch = false
	model.PrimaryPart = handle
	-- Knob, then the wrapped grip with two bands.
	add(
		model,
		"Knob",
		Vector3.new(0.34, 0.24, 0.42),
		CFrame.new(0, 0.12, 0.03),
		Kit.shade(WOOD, -0.12),
		Enum.Material.Wood
	)
	add(model, "Grip", Vector3.new(0.3, 0.85, 0.36), CFrame.new(0, 0.66, 0), LEATHER, Enum.Material.Leather)
	for _, y in ipairs({ 0.3, 1.05 }) do
		add(
			model,
			"GripBand",
			Vector3.new(0.32, 0.07, 0.38),
			CFrame.new(0, y, 0),
			Kit.shade(LEATHER, -0.25),
			Enum.Material.Leather
		)
	end
	-- The head: a block across the top of the haft, a wider flat face in
	-- front (-Z), a claw behind (+Z) that tapers to a point.
	add(model, "Eye", Vector3.new(0.46, 0.5, 0.5), CFrame.new(0, HEAD_Y, 0), STEEL, Enum.Material.Metal)
	add(model, "Band", Vector3.new(0.5, 0.1, 0.54), CFrame.new(0, HEAD_Y - 0.3, 0), STEEL_DARK, Enum.Material.Metal)
	add(model, "Neck", Vector3.new(0.4, 0.4, 0.3), CFrame.new(0, HEAD_Y, -0.38), STEEL, Enum.Material.Metal)
	add(model, "Face", Vector3.new(0.52, 0.52, 0.22), CFrame.new(0, HEAD_Y, -0.62), STEEL_FACE, Enum.Material.Metal)
	-- A wedge is full at its +Z face; turned round it is full where it meets
	-- the eye and tapers toward +Z.
	local claw = Kit.wedge(
		model,
		"Claw",
		Vector3.new(0.3, 0.42, 0.7),
		CFrame.new(0, HEAD_Y - 0.04, 0.6) * CFrame.Angles(0, math.pi, 0),
		STEEL,
		Enum.Material.Metal
	)
	Kit.decor(claw, false)
	add(
		model,
		"ClawSplit",
		Vector3.new(0.07, 0.3, 0.3),
		CFrame.new(0, HEAD_Y - 0.1, 0.78),
		STEEL_DARK,
		Enum.Material.Metal
	)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle then
			local w = Instance.new("Weld")
			w.Name = "Weld"
			w.Part0 = handle
			w.Part1 = d
			w.C0 = handle.CFrame:Inverse() * d.CFrame
			w.Parent = d
		end
	end
	return model
end

-- For a Tool: nothing anchored, nothing collides, nothing weighs anything.
function HammerArt.Held(): Model
	local model = HammerArt.Build()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	return model
end

-- Tool.Grip. `pitch` tips the head back (positive) or forward (negative)
-- about the hand, on top of the resting lean.
function HammerArt.Grip(pitch: number?): CFrame
	local handleInHand = CFrame.Angles(-LEAN + (pitch or 0), 0, 0) * CFrame.new(0, LEN / 2 - GRIP_FROM_FOOT, 0)
	return handleInHand:Inverse()
end

return HammerArt
