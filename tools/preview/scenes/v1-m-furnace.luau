--!nocheck
-- The furnace pad: smelter, ore chute, craft bench. The sawmill stays out of frame.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		Kit.part(root, "Pad", V3.new(36, 1, 28), CF.new(1, -0.5, -1), C3.fromRGB(150, 146, 138), Enum.Material.Slate)
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
		local function cam(x, y, z, tx, ty, tz, label, fov)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label, fov = fov }
		end
		return {
			root = root,
			shadowRadius = 40,
			fov = 36,
			cameras = {
				cam(16, 9, 20, 1, 3, -1, "furnace pad", 36),
			},
		}
	end,
}
