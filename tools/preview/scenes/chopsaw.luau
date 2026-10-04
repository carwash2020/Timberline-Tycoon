--!nocheck
-- The chop saw with the client cut line at the default 8 u, from the side
-- so the line reads against the infeed table.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MachineArt = ctx.art("MachineArt")
		local Logic = ctx.shared("ChopSawLogic")
		local root = roblox.Instance.new("Model")

		local fp = Logic.Footprint()
		Kit.part(
			root,
			"Ground",
			V3.new(fp.X + 16, 1, fp.Y + 16),
			CF.new(0, -0.5, 0),
			C3.fromRGB(196, 176, 140),
			Enum.Material.Grass
		)
		local saw = MachineArt.BuildChopSaw(false)
		saw.Parent = root
		local line = MachineArt.PreviewLine(saw, Logic.DefaultCut)
		local at = line.CFrame.Position

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 80,
			fov = 32,
			cameras = {
				cam(at.X + 18, at.Y + 5, at.Z + 8, at.X, at.Y, at.Z, "8 u cut line"),
				cam(22, 10, 8, 0, 2, 4, "the saw from the side"),
			},
		}
	end,
}
