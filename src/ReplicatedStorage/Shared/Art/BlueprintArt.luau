--!strict
-- BlueprintArt: a rolled plan, the physical blueprint (BUILD_SYSTEM.md). A
-- cream paper roll with a blue-print edge showing at each end, tied with
-- twine and sealed with a wax dot whose colour says what kind of building
-- it holds (blue for Buildings, green for Decor, amber for anything else),
-- and a curl of sheet poking out of the top. Pure (see Kit).
--
-- Contract (the same shape as AxeArt and HammerArt):
--   * Build(id) returns a Model standing on its foot: the roll upright, its
--     foot at y = 0. PrimaryPart "Handle" (a Tool needs it); every other
--     part is welded to it.
--   * Held(id): unanchored, massless, non-colliding.
--   * Dropped(id): lying on its side on the ground (lowest point y = 0),
--     centred on the origin, anchored and non-colliding.
--   * Grip(): the Tool.Grip that holds the roll in the middle, a little
--     forward of the hand.
--   * SealColor(id): the wax colour, so the shop box and the preview agree.

local PlotData = require(script.Parent.Parent.PlotData)
local Kit = require(script.Parent.Kit)

local BlueprintArt = {}

local LEN = 1.5 -- the roll, studs
local DIAMETER = 0.46

local PAPER = Color3.fromRGB(236, 226, 196)
local PAPER_EDGE = Color3.fromRGB(58, 111, 216)
local TWINE = Color3.fromRGB(140, 104, 62)

local SEALS: { [string]: Color3 } = {
	Buildings = Color3.fromRGB(58, 111, 216),
	Decor = Color3.fromRGB(76, 154, 90),
}
local OTHER_SEAL = Color3.fromRGB(214, 150, 40)

function BlueprintArt.SealColor(id: string): Color3
	local bp = PlotData.Blueprint(id)
	return (bp and SEALS[bp.category]) or OTHER_SEAL
end

local function decor(part: Part): Part
	Kit.decor(part, false)
	return part
end

local function upright(y: number): CFrame
	-- Kit.cylinder runs along X: stand it up.
	return CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2)
end

function BlueprintArt.Build(id: string): Model
	local model = Kit.model("Blueprint_" .. id)
	local handle = Kit.cylinder(model, "Handle", LEN, DIAMETER, upright(LEN / 2), PAPER, Enum.Material.Fabric)
	handle.CanTouch = false
	model.PrimaryPart = handle
	-- The printed edge of the sheet, a slim blue disc just proud of each end.
	for _, y in ipairs({ 0.02, LEN - 0.02 }) do
		decor(Kit.cylinder(model, "Edge", 0.05, DIAMETER + 0.04, upright(y), PAPER_EDGE, Enum.Material.SmoothPlastic))
	end
	-- Twine, twice round.
	for _, y in ipairs({ LEN * 0.3, LEN * 0.7 }) do
		decor(Kit.cylinder(model, "Twine", 0.07, DIAMETER + 0.07, upright(y), TWINE, Enum.Material.Fabric))
	end
	-- The wax seal, on the front (-Z) of the upper twine, with a ribbon tail.
	local seal = Kit.ball(
		model,
		"Seal",
		0.2,
		CFrame.new(0, LEN * 0.7, -(DIAMETER / 2 + 0.07)),
		BlueprintArt.SealColor(id),
		Enum.Material.SmoothPlastic
	)
	decor(seal)
	decor(
		Kit.part(
			model,
			"Tail",
			Vector3.new(0.1, 0.34, 0.03),
			CFrame.new(0.07, LEN * 0.7 - 0.27, -(DIAMETER / 2 + 0.06)) * CFrame.Angles(0, 0, 0.18),
			BlueprintArt.SealColor(id),
			Enum.Material.Fabric
		)
	)
	-- A curl of loose sheet at the top.
	decor(
		Kit.part(
			model,
			"Curl",
			Vector3.new(0.34, 0.03, 0.26),
			CFrame.new(0.05, LEN + 0.07, 0.04) * CFrame.Angles(0.35, 0, 0.12),
			PAPER,
			Enum.Material.Fabric
		)
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

function BlueprintArt.Held(id: string): Model
	local model = BlueprintArt.Build(id)
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

-- Lying on its side, lowest point at y = 0, centred on the origin.
function BlueprintArt.Dropped(id: string): Model
	local model = BlueprintArt.Build(id)
	-- The Handle is a cylinder, whose own axis is X: with no turn on the
	-- pivot the roll lies along X. Sit it on the ground by its radius plus
	-- the twine's thickness.
	model:PivotTo(CFrame.new(0, DIAMETER / 2 + 0.035, 0))
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	return model
end

-- The hand holds the middle of the roll, the roll tipped a little forward.
function BlueprintArt.Grip(): CFrame
	-- The Handle is a cylinder (its axis is local X); a quarter turn about
	-- Z stands that axis up in the hand, like an axe's haft.
	local handleInHand = CFrame.Angles(-0.25, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
	return handleInHand:Inverse()
end

BlueprintArt.Length = LEN

return BlueprintArt
