--!strict
-- PropArt: nature's small things, so the world never looks empty: rocks,
-- bushes, flowers, mushrooms, grass tufts, fallen logs, crystals, reeds,
-- lily pads, snow piles, lava rocks. Pure (see Kit). Clients scatter most
-- of these around the player (AmbientLife); MapBuilder places landmarks.
--
-- Every builder returns a Model on the ground at the origin, decoration
-- only (no collisions, clicks or touches) unless noted.
--
-- (First pass: simple shapes. The nature workstream replaces the insides;
-- keep the signatures.)

local Kit = require(script.Parent.Kit)

local PropArt = {}

local STONE = { Color3.fromRGB(140, 134, 126), Color3.fromRGB(120, 116, 110), Color3.fromRGB(158, 150, 140) }

-- A faceted boulder about `size` studs across. Collides (you can climb it).
function PropArt.Rock(size: number, seed: number, colors: { Color3 }?): Model
	local model = Kit.model("Rock")
	local parts = Kit.rock(model, CFrame.identity, size, Kit.rng(seed), colors or STONE)
	for _, p in ipairs(parts) do
		p.CanCollide = true
	end
	return model
end

-- A leafy bush about `size` studs across in the given greens.
function PropArt.Bush(size: number, seed: number, colors: { Color3 }): Model
	local model = Kit.model("Bush")
	Kit.blob(
		model,
		"Bush",
		CFrame.new(0, size * 0.35, 0),
		Vector3.new(size, size * 0.7, size),
		4,
		Kit.rng(seed),
		colors
	)
	return model
end

-- A small patch of flowers (petal colours from the list).
function PropArt.Flowers(seed: number, colors: { Color3 }): Model
	local model = Kit.model("Flowers")
	local rng = Kit.rng(seed)
	for _ = 1, 5 do
		local x, z = rng:range(-1.5, 1.5), rng:range(-1.5, 1.5)
		Kit.decor(
			Kit.part(model, "Stem", Vector3.new(0.1, 0.8, 0.1), CFrame.new(x, 0.4, z), Color3.fromRGB(80, 140, 60)),
			false
		)
		Kit.decor(Kit.ball(model, "Petals", 0.45, CFrame.new(x, 0.85, z), rng:pick(colors)), false)
	end
	return model
end

-- A mushroom (glowing ones for the Phantom Grove).
function PropArt.Mushroom(seed: number, glowing: boolean): Model
	local model = Kit.model("Mushroom")
	local rng = Kit.rng(seed)
	local h = rng:range(0.8, 1.6)
	Kit.decor(
		Kit.post(model, "Stalk", Vector3.zero, h, 0.35, Color3.fromRGB(235, 228, 210), Enum.Material.SmoothPlastic),
		false
	)
	local cap = Kit.ellipsoid(
		model,
		"Cap",
		Vector3.new(1.4, 0.7, 1.4) * (h / 1.2),
		CFrame.new(0, h, 0),
		if glowing then Color3.fromRGB(80, 230, 210) else Color3.fromRGB(196, 72, 56),
		if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic
	)
	Kit.decor(cap, false)
	return model
end

-- A crystal cluster (Sky Shard look, ice in the snow, embers by lava).
function PropArt.Crystal(seed: number, color: Color3, size: number): Model
	local model = Kit.model("Crystal")
	local rng = Kit.rng(seed)
	for _ = 1, 4 do
		local h = rng:range(0.6, 1.2) * size
		Kit.decor(
			Kit.part(
				model,
				"Shard",
				Vector3.new(size * 0.25, h, size * 0.25),
				CFrame.new(rng:range(-0.3, 0.3) * size, h / 2, rng:range(-0.3, 0.3) * size)
					* CFrame.Angles(rng:range(-0.4, 0.4), rng:range(0, 3), rng:range(-0.4, 0.4)),
				color,
				Enum.Material.Glass
			),
			false
		)
	end
	return model
end

return PropArt
