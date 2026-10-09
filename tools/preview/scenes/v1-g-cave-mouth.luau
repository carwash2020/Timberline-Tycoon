--!nocheck
-- The mine mouth (NatureArt.CaveMouth) as the uploaded meshes, lit from
-- outside, opening toward the camera. One camera.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local root = roblox.Instance.new("Model")
		Kit.part(root, "Ground", V3.new(120, 1, 90), CF.new(0, -0.5, 0), C3.fromRGB(116, 170, 74), Enum.Material.Grass)
		local mouth = NatureArt.CaveMouth()
		-- Opening faces model -Z, which is toward the camera at -Z.
		Kit.placeAt(mouth, CF.new(0, 0, 0))
		mouth.Parent = root
		return {
			root = root,
			shadowRadius = 60,
			fov = 40,
			cameras = {
				{ pos = { 14, 12, -52 }, target = { 0, 7, 0 }, fov = 40, label = "cave-mouth" },
			},
		}
	end,
}
