--!nocheck
-- The world's wildlife (Shared/Art/CritterArt): songbirds perched and in
-- flight, butterflies, rabbits (and a winter hare), a doe and a buck,
-- ducks on a pond, a fish mid-leap, Phantom Grove wisps and Volcano ember
-- sprites. Particle clouds (fireflies, motes) don't show in the preview.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local CritterArt = ctx.art("CritterArt")
		local PropArt = ctx.art("PropArt")
		local root = roblox.Instance.new("Model")

		-- Meadow, pond, and a dark strip for the night critters.
		Kit.part(root, "Ground", V3.new(120, 1, 70), CF.new(20, -0.5, 6), C3.fromRGB(116, 170, 74), Enum.Material.Grass)
		Kit.part(root, "Pond", V3.new(26, 0.2, 16), CF.new(52, 0.02, 14), C3.fromRGB(70, 150, 190), Enum.Material.Glass)
		Kit.part(
			root,
			"Night",
			V3.new(34, 0.2, 16),
			CF.new(-22, 0.02, 30),
			C3.fromRGB(64, 50, 72),
			Enum.Material.Ground
		)
		Kit.part(root, "Basalt", V3.new(20, 0.2, 16), CF.new(5, 0.02, 30), C3.fromRGB(52, 46, 44), Enum.Material.Basalt)

		local function label(text, x, z)
			local sign = Kit.part(root, "Label", V3.new(7, 1.6, 0.3), CF.new(x, 0.8, z), C3.fromRGB(120, 80, 50))
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		local function put(model, cf)
			model:PivotTo(cf * model:GetPivot())
			model.Parent = root
		end

		-- Songbirds: perched on the grass and in flight above.
		for i = 1, 5 do
			local bird = CritterArt.Bird(i - 1, 1)
			CritterArt.FoldWings(bird)
			put(bird, CF.new(-30 + (i - 1) * 2.2, 0, -6) * CF.Angles(0, math.rad(-20 + i * 8), 0))
			local flyer = CritterArt.Bird(i - 1, 1.6, true)
			put(
				flyer,
				CF.new(-30 + (i - 1) * 3.2, 7 + (i % 2) * 1.2, -2) * CF.Angles(0, math.rad(25), math.rad(-10 + i * 4))
			)
		end
		label("SONGBIRDS", -26, -10)

		-- Butterflies over flowers.
		for i = 1, 5 do
			local flowers =
				PropArt.Flowers(i, { C3.fromRGB(250, 214, 80), C3.fromRGB(240, 140, 180), C3.fromRGB(255, 255, 245) })
			put(flowers, CF.new(-14 + (i - 1) * 2.4, 0, -6))
			local b = CritterArt.Butterfly(i - 1)
			put(b, CF.new(-14 + (i - 1) * 2.4, 1.8 + (i % 3) * 0.5, -6.5) * CF.Angles(0, math.rad(i * 30), 0))
		end
		label("BUTTERFLIES", -9, -10)

		-- Rabbits and a winter hare.
		for i = 1, 3 do
			put(CritterArt.Rabbit(i), CF.new(-1 + (i - 1) * 3.6, 0, -6) * CF.Angles(0, math.rad(-30 + i * 25), 0))
		end
		put(CritterArt.Rabbit(9, true), CF.new(9, 0, -6) * CF.Angles(0, math.rad(40), 0))
		label("RABBITS", 4.5, -10)

		-- A doe and a buck.
		put(CritterArt.Deer(2), CF.new(16, 0, -4) * CF.Angles(0, math.rad(-35), 0))
		put(CritterArt.Deer(3), CF.new(24, 0, -2) * CF.Angles(0, math.rad(-60), 0))
		label("DEER", 20, -10)

		-- Ducks on the pond, and a trout leaping.
		for i = 1, 3 do
			put(
				CritterArt.Duck(i),
				CF.new(46 + (i - 1) * 3.5, 0.1, 12 + (i % 2) * 2) * CF.Angles(0, math.rad(i * 70), 0)
			)
		end
		put(CritterArt.Fish(1), CF.new(56, 2.2, 16) * CF.Angles(math.rad(35), math.rad(90), 0))
		put(CritterArt.Fish(3), CF.new(59, 1.4, 12) * CF.Angles(math.rad(-25), math.rad(-60), 0))
		label("DUCKS + FISH", 52, 4)

		-- Night magic: wisps over the grove floor, ember sprites on basalt.
		for i = 1, 4 do
			put(
				CritterArt.Wisp(i),
				CF.new(-32 + (i - 1) * 5, 2.2 + (i % 2) * 0.8, 30) * CF.Angles(0, math.rad(i * 50), 0)
			)
			put(PropArt.Mushroom(i, true), CF.new(-30 + (i - 1) * 5, 0, 33))
		end
		label("WISPS", -22, 23)
		for i = 1, 3 do
			put(CritterArt.EmberSprite(i), CF.new(0 + (i - 1) * 3, 0.6, 30) * CF.Angles(0, math.rad(-20 + i * 20), 0))
		end
		label("EMBER SPRITES", 3, 23)

		return {
			root = root,
			shadowRadius = 90,
			fov = 45,
			cameras = {
				{ pos = { 10, 26, -48 }, target = { 10, 1, 8 }, label = "everyone" },
				{ pos = { -24, 5, -18 }, target = { -24, 2.5, -4 }, label = "songbirds" },
				{ pos = { -33, 2.2, -3 }, target = { -27, 0.4, -6 }, label = "perched, from behind" },
				{ pos = { -9, 4, -14 }, target = { -9, 1.5, -6 }, label = "butterflies" },
				{ pos = { 4, 4, -14 }, target = { 4, 0.8, -6 }, label = "rabbits" },
				{ pos = { 20, 6, -16 }, target = { 20, 2.8, -3 }, label = "deer" },
				{ pos = { 52, 6, 0 }, target = { 52, 1, 13 }, label = "pond" },
				{ pos = { -22, 6, 18 }, target = { -22, 2, 30 }, label = "wisps" },
				{ pos = { 3, 3.5, 23 }, target = { 3, 0.8, 30 }, label = "ember sprites" },
			},
		}
	end,
}
