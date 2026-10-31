--!nocheck
-- T414d-2 close-ups on a studio pad west of the map (staged, not the world): 1 the square Block stumps
-- (bark, cut face, crack, moss cap), 2 a deer, a rabbit and a bird, 3 a stump beside the town mill's slip
-- lane, kept clear of it by the plan's 2 studs (the real keep-out is the whole town zone, so none is
-- planned there), 4 the cover kinds and a large rock.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local Greenery = ctx.art("Greenery")
		local CritterArt = ctx.art("CritterArt")
		local BuildingArt = ctx.art("BuildingArt")
		local root = roblox.Instance.new("Model")
		local x0 = -2400
		Kit.part(
			root,
			"Ground",
			V3.new(160, 1, 120),
			CF.new(x0, -0.5, 0),
			C3.fromRGB(110, 150, 76),
			roblox.Enum.Material.Grass
		)
		local function put(model, x, z, yaw)
			Kit.placeAt(model, CF.new(x0 + x, 0, z) * CF.Angles(0, yaw or 0, 0))
			model.Parent = root
		end
		-- Stumps.
		for i, v in ipairs({ 0, 1, 2, 3 }) do
			put(Greenery.Stump("starter", v, 2.2 + v * 0.3), (i - 2.5) * 4.5, 0, 0.4 * i)
		end
		for i, region in ipairs({ "hills", "snow", "gloam" }) do
			put(Greenery.Stump(region, i, 2.6), (i - 2) * 4.5, 8, 0.7 * i)
		end
		-- Critters.
		put(CritterArt.RoadTemplate("Deer", 7), -10, 30, 0.5)
		put(CritterArt.RoadTemplate("Rabbit", 7), 0, 30, -0.4)
		put(CritterArt.RoadTemplate("Bird", 7), 6, 30, 0.9)
		-- The mill's slip lane with a stump 2 studs clear of its box.
		local mill = BuildingArt.Sawmill()
		Kit.placeAt(mill, CF.new(x0 + 20, 0, 70) * CF.Angles(0, 0, 0))
		mill.Parent = root
		local stump = Greenery.Stump("starter", 3, 2.6)
		Kit.placeAt(stump, CF.new(x0 + 20 + 25, 0, 70 + 1.2 + 2 + 1.3))
		stump.Parent = root
		-- Cover and a large rock.
		for i, kind in ipairs({ "grass", "fern", "shrub", "pebble", "flower" }) do
			put(Greenery.Cover(kind, "starter", 2), 30 + (i - 3) * 4, -2, i)
		end
		put(Greenery.Cover("shrub", "snow", 3), 30, 6, 0)
		put(Greenery.Rock("hills", 3, 5.5), 40, 8, 0.3)
		put(Greenery.Cover("reed", "bayou", 1), 22, 12, 0)
		put(Greenery.Cover("scrub", "mesa", 2), 26, 12, 0)
		put(Greenery.Sapling("starter", 2, 4), 48, 2, 0)
		put(Greenery.Snag("hills", 2, 6), 54, 2, 0)
		local function at(x, y, z)
			return { x0 + x, y, z }
		end
		return {
			root = root,
			shadowRadius = 90,
			lighting = { fogNear = 600, fogFar = 2500 },
			fov = 50,
			cameras = {
				{
					pos = at(-1, 4.5, 11),
					target = at(-1, 0.8, 0),
					label = "square Block stumps: bark, cut face, crack, moss",
					fov = 45,
				},
				{
					pos = at(-3, 3.6, 40),
					target = at(-3, 1.8, 30),
					label = "deer, rabbit and bird (client-only critters)",
					fov = 45,
				},
				{
					pos = at(40, 7, 84),
					target = at(45, 1, 71),
					label = "a stump 2 studs clear of the town mill's slip lane (staged)",
					fov = 50,
				},
				{
					pos = at(36, 7, 16),
					target = at(36, 1.5, 3),
					label = "cover kinds, region looks and a large rock",
					fov = 55,
				},
			},
		}
	end,
}
