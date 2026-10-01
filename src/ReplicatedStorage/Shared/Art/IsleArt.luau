--!strict
-- IsleArt: the Skyroot (the colossal tree the whole map points at) and the
-- floating Aether Isles above it (GAME_DESIGN §10, §13: white-gold light,
-- cloud banks, Lumenwood motes). Pure (see Kit).
--
-- (First pass: simple shapes. The isles workstream replaces the insides;
-- keep the signatures and named parts.)

local Kit = require(script.Parent.Kit)

local IsleArt = {}

-- The Skyroot: trunk from the ground (y = 0 at the origin) up to `height`,
-- with roots flaring out and a canopy under the isles. Keep it under about
-- 150 parts: it is Persistent (seen from anywhere on the map).
function IsleArt.Skyroot(height: number): Model
	local model = Kit.model("Skyroot")
	local trunk = Kit.cylinder(
		model,
		"SkyrootTrunk",
		height,
		56,
		CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(107, 74, 46),
		Enum.Material.Wood
	)
	Kit.decor(
		Kit.cylinder(
			model,
			"SkyrootRoots",
			8,
			84,
			CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(95, 66, 40),
			Enum.Material.Wood
		)
	)
	model.PrimaryPart = trunk
	return model
end

-- A floating isle: its walkable top at y = 0 (a part named "IsleTop" that
-- collides), a rocky underside hanging below. `radius` in studs.
function IsleArt.Isle(radius: number, seed: number): Model
	local model = Kit.model("Isle")
	local top = Kit.cylinder(
		model,
		"IsleTop",
		8,
		radius * 2,
		CFrame.new(0, -4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(168, 216, 110),
		Enum.Material.Grass
	)
	local rng = Kit.rng(seed)
	for i, shrink in ipairs({ 0.7, 0.4 }) do
		Kit.decor(
			Kit.cylinder(
				model,
				"IsleRock",
				10,
				radius * shrink * 2,
				CFrame.new(0, -8 - i * 9, 0) * CFrame.Angles(0, rng:range(0, 3), math.pi / 2),
				Color3.fromRGB(201, 195, 184),
				Enum.Material.Slate
			)
		)
	end
	model.PrimaryPart = top
	return model
end

return IsleArt
