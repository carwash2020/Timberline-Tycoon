--!nocheck
-- Cave mouth, sealed then open. The fill light is preview-only.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local root = roblox.Instance.new("Model")
		local stone = C3.fromRGB(78, 74, 70)
		local dark = C3.fromRGB(42, 40, 38)
		local function cave(ox, sealed)
			Kit.part(root, "Floor", V3.new(22, 1, 28), CF.new(ox, -0.5, 2), stone, Enum.Material.Slate)
			Kit.part(root, "Left", V3.new(2, 12, 22), CF.new(ox - 10, 6, 0), stone, Enum.Material.Slate)
			Kit.part(root, "Right", V3.new(2, 12, 22), CF.new(ox + 10, 6, 0), stone, Enum.Material.Slate)
			Kit.part(root, "Lintel", V3.new(22, 2, 8), CF.new(ox, 12, 4), stone, Enum.Material.Slate)
			Kit.part(root, "Inside", V3.new(18, 10, 1), CF.new(ox, 5, -8), dark, Enum.Material.Slate)
			if sealed then
				local wall = MiningArt.Rubble("mine-mid", 2)
				wall:PivotTo(CF.new(ox, 0, 1))
				wall.Parent = root
				local bomb = MiningArt.Bomb(true)
				bomb:PivotTo(CF.new(ox + 1.2, 0, 6.5))
				bomb.Parent = root
			else
				for i = 1, 4 do
					local rock = Kit.part(
						root,
						"Loose",
						V3.new(1.4, 0.9, 1.1),
						CF.new(ox - 3 + i * 1.6, 0.4, 3 + (i % 2)) * CF.Angles(0.2, i, 0.15),
						C3.fromRGB(110, 104, 96),
						Enum.Material.Slate
					)
					Kit.decor(rock, false)
				end
			end
			local bulb = Kit.part(
				root,
				"Fill",
				V3.new(0.4, 0.4, 0.4),
				CF.new(ox, 7, 10),
				C3.fromRGB(255, 236, 210),
				Enum.Material.Neon
			)
			local light = roblox.Instance.new("PointLight")
			light.Color = C3.fromRGB(255, 228, 196)
			light.Range = 36
			light.Brightness = 2.4
			light.Shadows = false
			light.Parent = bulb
		end
		cave(0, true)
		cave(48, false)
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label, fov = 38 }
		end
		return {
			root = root,
			shadowRadius = 30,
			fov = 38,
			lighting = { ambient = 0.85, hemiIntensity = 1.6, exposure = 1.15, sunIntensity = 1.6 },
			cameras = {
				cam(-7, 6, 18, 0, 4, 2, "sealed cave, lit bomb"),
				cam(41, 6, 18, 48, 4, 2, "opened passage"),
			},
		}
	end,
}
