--!nocheck
-- Lane G rain, drawn as parts because the preview does not export particles.
-- "blobs" is today's soft puff. "streaks" is the thin angled fall, shorter
-- and thinner on low, and missing under a shop roof when sheltered.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local root = roblox.Instance.new("Model")

		local function yard(name, x, color)
			Kit.part(root, name, V3.new(24, 1, 20), CF.new(x, -0.5, 0), color, Enum.Material.Grass)
		end

		yard("Before", 0, C3.fromRGB(90, 120, 78))
		yard("High", 36, C3.fromRGB(90, 120, 78))
		yard("Low", 72, C3.fromRGB(90, 120, 78))

		-- A small shop: walls, a roof at y = 4 (RainField shelters y < 12
		-- inside |x|<4.2 and |z|<3.2, in the field's own space).
		local shopX = 108
		Kit.part(
			root,
			"ShopFloor",
			V3.new(10, 0.4, 8),
			CF.new(shopX, 0.2, 0),
			C3.fromRGB(120, 96, 72),
			Enum.Material.WoodPlanks
		)
		Kit.part(
			root,
			"ShopWall",
			V3.new(0.4, 4, 8),
			CF.new(shopX - 4.8, 2.2, 0),
			C3.fromRGB(92, 70, 52),
			Enum.Material.Wood
		)
		Kit.part(
			root,
			"ShopWall",
			V3.new(10, 4, 0.4),
			CF.new(shopX, 2.2, -3.8),
			C3.fromRGB(92, 70, 52),
			Enum.Material.Wood
		)
		Kit.part(
			root,
			"ShopWall",
			V3.new(0.4, 4, 8),
			CF.new(shopX + 4.8, 2.2, 0),
			C3.fromRGB(86, 66, 48),
			Enum.Material.Wood
		)
		local roof = Kit.part(
			root,
			"ShopRoof",
			V3.new(11, 0.35, 9),
			CF.new(shopX, 4.3, 0),
			C3.fromRGB(70, 62, 58),
			Enum.Material.Slate
		)
		roof.CastShadow = true

		local function field(style, tier, sheltered, x)
			local rain = NatureArt.RainField(style, tier, sheltered)
			Kit.placeAt(rain, CF.new(x, 0, 0))
			rain.Parent = root
		end

		field("blobs", "high", false, 0)
		field("streaks", "high", false, 36)
		field("streaks", "low", false, 72)
		field("streaks", "high", true, shopX)

		local function label(text, x, z)
			local sign = Kit.part(root, "Label", V3.new(8, 1.4, 0.25), CF.new(x, 0.8, z), C3.fromRGB(110, 74, 44))
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end
		label("BEFORE BLOBS", 0, -8)
		label("HIGH STREAKS", 36, -8)
		label("LOW STREAKS", 72, -8)
		label("INSIDE SHOP", shopX, -8)

		return {
			root = root,
			shadowRadius = 40,
			fov = 40,
			cameras = {
				{ pos = { 0, 10, -16 }, target = { 0, 6, 0 }, label = "blobs high before" },
				{ pos = { 36, 10, -16 }, target = { 36, 6, 0 }, label = "streaks high" },
				{ pos = { 72, 10, -16 }, target = { 72, 6, 0 }, label = "streaks low" },
				{ pos = { shopX, 2.2, 6 }, target = { shopX, 2.4, 0 }, label = "inside shop" },
				{ pos = { shopX - 14, 8, 12 }, target = { shopX, 3, 0 }, label = "shop outside" },
			},
		}
	end,
}
