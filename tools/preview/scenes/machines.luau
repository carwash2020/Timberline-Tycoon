--!nocheck
-- The mill tiers, the planer tiers and the belt kit side by side, so each
-- tier can be seen to be bigger and better than the one before it.
--   view 1  the five sawmills, Rickety to Industrial
--   view 2  the four planers
--   view 3  a belt line: straight, turn, funnel into a planer

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MachineArt = ctx.art("MachineArt")
		local Catalog = ctx.shared("ItemCatalog")
		local PlanerLogic = ctx.shared("PlanerLogic")
		local root = roblox.Instance.new("Model")

		Kit.part(
			root,
			"Ground",
			V3.new(260, 1, 120),
			CF.new(0, -0.5, 0),
			C3.fromRGB(196, 176, 140),
			Enum.Material.Grass
		)

		-- Mills along z = -30, planers along z = 10, belts along z = 40.
		local x = -90
		for _, mill in ipairs(Catalog.SawmillList()) do
			local model = MachineArt.Build(mill.id, false)
			x += mill.width / 2 + 3
			model:PivotTo(CF.new(x, 0, -30))
			model.Parent = root
			x += mill.width / 2 + 3
		end
		x = -60
		for _, machine in ipairs(PlanerLogic.List()) do
			local def = machine.planer
			local model = MachineArt.BuildPlaner(machine.id, false)
			x += def.width / 2 + 3
			model:PivotTo(CF.new(x, 0, 10))
			model.Parent = root
			x += def.width / 2 + 3
		end
		-- A line: straight, straight, turn, straight, funnel, planer.
		local line = {
			{ "ConveyorStraight", 0, 0, 0 },
			{ "ConveyorStraight", 0, 8, 0 },
			{ "ConveyorTurn", 0, 14, 0 },
			{ "ConveyorStraight", 8, 14, 1 },
		}
		for _, entry in ipairs(line) do
			local model = MachineArt.BuildBelt(entry[1], false)
			model:PivotTo(CF.new(-20 + entry[2], 0, 36 + entry[3]) * CF.Angles(0, -math.pi / 2 * entry[4], 0))
			model.Parent = root
		end
		local funnel = MachineArt.BuildBelt("ConveyorFunnel", false)
		funnel:PivotTo(CF.new(20, 0, 36))
		funnel.Parent = root

		local function cam(cx, cy, cz, tx, ty, tz, label)
			return { pos = { cx, cy, cz }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 200,
			fov = 40,
			cameras = {
				cam(-10, 40, 40, -10, 4, -30, "the five sawmills"),
				cam(-20, 28, 50, -20, 3, 10, "the four planers"),
				cam(-5, 30, 70, -5, 1, 40, "belts"),
			},
		}
	end,
}
