--!nocheck
-- Smelting furnace on the pad, sawmill beside it.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		Kit.part(root, "Pad", V3.new(36, 1, 28), CF.new(0, -0.5, 0), C3.fromRGB(140, 136, 128), Enum.Material.Slate)
		local layout = MiningArt.PadLayout()
		local furnace = MiningArt.SmeltingFurnace()
		furnace:PivotTo(layout.furnace)
		furnace.Parent = root
		local stall = MiningArt.Prospector()
		stall:PivotTo(layout.prospector)
		stall.Parent = root
		local bench = MiningArt.CraftBench()
		bench:PivotTo(layout.bench)
		bench.Parent = root
		local mill = BuildingArt.Sawmill(1)
		mill:PivotTo(CF.new(-40, 0, 0))
		mill.Parent = root
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 80,
			fov = 40,
			cameras = {
				cam(18, 16, 36, -10, 4, 0, "furnace with the sawmill"),
				cam(8, 8, 18, -6, 3, -2, "smelting furnace"),
			},
		}
	end,
}
