--!nocheck
-- Open meadow at NatureData's surface density (0.4, two pieces a cell,
-- the same rate as the forest discs). The camera is a player's eye,
-- 5 studs off the grass.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local NatureData = ctx.load("ReplicatedStorage/Shared/NatureData")
		local root = roblox.Instance.new("Model")

		Kit.part(
			root,
			"Meadow",
			V3.new(300, 1, 300),
			CF.new(64, -0.5, 64),
			C3.fromRGB(116, 170, 74),
			Enum.Material.Grass
		)

		local zone = {
			id = "meadow-preview",
			kind = "meadow",
			center = roblox.Vector2.new(64, 64),
			radius = 140,
			density = 0.4,
		}
		local function blocked()
			return false
		end
		for cx = -1, 3 do
			for cz = -1, 3 do
				local spots = NatureData.CellSpots(cx, cz, { zone }, blocked, {}, 800)
				for _, spot in ipairs(spots) do
					local sizeName = if spot.variant == 1 then "small" elseif spot.variant == 3 then "large" else "mid"
					local model = NatureArt.Build(spot.kind, spot.seed, sizeName, spot.look)
					Kit.placeAt(model, CF.new(spot.x, 0, spot.z) * CF.Angles(0, spot.yaw, 0))
					model.Parent = root
				end
			end
		end

		return {
			root = root,
			shadowRadius = 90,
			fov = 70,
			cameras = {
				{
					pos = { 28, 5, -48 },
					target = { 6, 1.1, 24 },
					label = "meadow",
					fov = 70,
				},
			},
		}
	end,
}
