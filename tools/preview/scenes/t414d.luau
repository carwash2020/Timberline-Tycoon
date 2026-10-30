-- T414d shop interiors at midday, each from its door. The roof is off so the
-- aisle reads (a roofed interior renders black in this viewer).

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local Kit = ctx.art("Kit")
		ctx.art("TownMeshes").Enabled = false
		local ShopPlace = ctx.art("ShopPlace")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 900, roblox.Color3.fromRGB(110, 150, 72), roblox.Vector3.new(200, -0.5, 0))

		local roof = {
			Roof = true,
			Shingle = true,
			RidgeCap = true,
			Gable = true,
			Rafter = true,
			TieBeam = true,
			CeilingBoards = true,
			CeilingBeam = true,
		}
		local spots = {
			{ "HearthAndHome", "HEARTH & HOME", { 47, 93, 58 }, 0 },
			{ "ToolShed", "TOOL SHED", { 184, 53, 40 }, 90 },
			{ "Dealership", "DEALERSHIP", { 30, 80, 150 }, 280 },
			{ "CoatKiosk", "COAT KIOSK", { 120, 170, 200 }, 470 },
			{ "OddsAndEnds", "ODDS AND ENDS", { 140, 100, 60 }, 510 },
			{ "SecretShop", "SECRET SHOP", { 90, 80, 70 }, 550 },
		}
		local cameras = {}
		for _, spot in ipairs(spots) do
			local accent = spot[3]
			local model = ShopPlace.Build(spot[1], spot[2], roblox.Color3.fromRGB(accent[1], accent[2], accent[3]))
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and roof[d.Name] then
					d:Destroy()
				end
			end
			Kit.placeAt(model, roblox.CFrame.new(spot[4], 0, 0))
			model.Parent = root
			local door = model:FindFirstChild("DoorBlock", true) or model:FindFirstChild("DoorOpening", true)
			local at = if door and door:IsA("BasePart")
				then door.CFrame.Position
				else roblox.Vector3.new(spot[4], 5, -8)
			table.insert(cameras, {
				pos = { at.X, 6.4, at.Z - 9 },
				target = { at.X, 5.2, at.Z + 12 },
				fov = 58,
				label = spot[1] .. " from the door",
			})
		end

		return {
			root = root,
			shadowRadius = 80,
			fov = 58,
			lighting = {
				sunDir = { -0.12, 0.96, -0.22 },
				sunColor = "#fff4e0",
				sunIntensity = 2.4,
				skyTop = "#8eb4e0",
				skyBottom = "#f3e2c4",
				ground = "#6e8f45",
				hemiIntensity = 1.15,
				ambient = 0.58,
				fog = "#e7eef6",
				fogNear = 500,
				fogFar = 2400,
				bloom = 0.12,
			},
			cameras = cameras,
		}
	end,
}
