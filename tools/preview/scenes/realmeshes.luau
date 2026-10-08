--!nocheck
-- The custom axes and one truck, as the uploaded meshes, for the review
-- shots in previews/meshes. Plain light background. Cameras 1-3 are the ten
-- axes (at most four each), camera 4 is the Pickup. A part-built axe only
-- remains when its mesh id is not in assets/meshes/manifest.json.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local AxeArt = ctx.art("AxeArt")
		local TruckArt = ctx.art("TruckArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local ids = {
			"RustyAxe",
			"SteelAxe",
			"HardenedAxe",
			"SilverAxe",
			"CobaltAxe",
			"GoldAxe",
			"ObsidianAxe",
			"InfernoAxe",
			"StarfallAxe",
			"LuxAxe",
		}
		-- 4 + 3 + 3, each row far enough that the next camera cannot see it.
		local rows = { { 1, 4 }, { 5, 7 }, { 8, 10 } }
		local yaw = math.rad(-48)
		local turn = CF.Angles(0, yaw, 0)
		local ahead = turn * V3.new(0, 0, -1)
		local gap = 4.6
		local rowX = 500

		local function placeAxe(def, x, z)
			local axe = AxeArt.Build(def)
			axe:PivotTo(CF.new(x, 0, z) * turn * axe:GetPivot())
			local handle = axe:FindFirstChild("Handle", true)
			local mesh = axe:FindFirstChild("MeshHandle", true)
			if handle and mesh and handle:IsA("BasePart") and mesh:GetAttribute("VisualMesh") == true then
				handle.Transparency = 1
			end
			axe.Parent = root
			local sign = Kit.part(
				root,
				"NamePlate",
				V3.new(3.1, 0.55, 0.08),
				CF.new(x, 0.34, z - 1.7),
				C3.fromRGB(244, 241, 234),
				Enum.Material.SmoothPlastic
			)
			Kit.signText(sign, def.displayName, C3.fromRGB(42, 38, 34), { Enum.NormalId.Front })
		end

		local cameras = {}
		for row, span in ipairs(rows) do
			local x0 = (row - 1) * rowX
			local count = span[2] - span[1] + 1
			local width = (count - 1) * gap
			for i = span[1], span[2] do
				local def = ItemCatalog.GetAxe(ids[i])
				placeAxe(def, x0 + (i - span[1]) * gap - width / 2, 0)
			end
			Kit.part(
				root,
				"Floor",
				V3.new(width + 8, 0.2, 8),
				CF.new(x0, -0.1, 0),
				C3.fromRGB(232, 228, 220),
				Enum.Material.SmoothPlastic
			)
			-- Far enough that the end axes and their plates stay inside the frame.
			-- Camera sits on the row's centre line so the near axe is not huge
			-- and the far one is not clipped. The axes stay turned, so each
			-- one is still a 3/4 view.
			local dist = if count == 4 then 22 else 15.5
			table.insert(cameras, {
				pos = { x0, 2.55, -dist },
				target = { x0, 2.05, 0 },
				label = "axes " .. tostring(row),
				fov = 32,
			})
		end

		local truckX = #rows * rowX
		local truck = TruckArt.Build(ItemCatalog.GetTruck("Pickup"))
		Kit.placeAt(truck, CF.new(truckX, 0, 0) * CF.Angles(0, yaw, 0))
		truck.Parent = root
		Kit.part(
			root,
			"Floor",
			V3.new(36, 0.2, 40),
			CF.new(truckX, -0.1, 0),
			C3.fromRGB(232, 228, 220),
			Enum.Material.SmoothPlastic
		)
		local side = turn * V3.new(-1, 0, 0)
		local truckEye = V3.new(truckX, 8, 0) + ahead * 34 + side * 20
		table.insert(cameras, {
			pos = { truckEye.X, truckEye.Y, truckEye.Z },
			target = { truckX, 3.4, 0 },
			label = "Pickup",
			fov = 30,
		})

		return {
			root = root,
			shadowRadius = 30,
			fov = 30,
			background = "#f3f0e8",
			hud = false,
			lighting = {
				sunDir = { -0.35, 0.9, -0.25 },
				sunColor = "#fff4e4",
				sunIntensity = 1.7,
				skyTop = "#f3f0e8",
				skyBottom = "#f7f4ee",
				ground = "#e4dfd4",
				hemiIntensity = 1.15,
				ambient = 0.72,
				fog = "#f3f0e8",
				fogNear = 400,
				fogFar = 900,
				exposure = 1.12,
				bloom = 0.05,
			},
			cameras = cameras,
		}
	end,
}
