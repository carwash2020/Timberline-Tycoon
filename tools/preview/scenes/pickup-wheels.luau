--!nocheck
-- The Pickup's wheels, with the real uploaded meshes. The gameplay Pickup
-- (TruckArt.Build, what VehicleService stands on a pad) at the origin, a
-- Rustbucket beside it at x 60 for comparison, and the Dealership's display
-- copy of the Pickup on its own plinth (DealershipLot.Build) far off at x 500.
-- Views: 1 front, 2 side, 3 three-quarter, 4 the front-left wheel close up,
-- 5 from under the arch (low), 6 Rustbucket side (the reference), 7 the
-- dealership plinth, 8 the dealership copy's wheel close up.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local DealershipLot = ctx.art("DealershipLot")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local function floor(x, z, w, d)
			Kit.part(
				root,
				"Floor",
				V3.new(w, 0.2, d),
				CF.new(x, -0.1, z),
				C3.fromRGB(232, 228, 220),
				Enum.Material.SmoothPlastic
			)
		end

		floor(30, 0, 120, 50)
		local pickup = TruckArt.Build(ItemCatalog.GetTruck("Pickup"))
		Kit.placeAt(pickup, CF.new(0, 0, 0))
		pickup.Parent = root
		local rust = TruckArt.Build(ItemCatalog.GetTruck("Rustbucket"))
		Kit.placeAt(rust, CF.new(60, 0, 0))
		rust.Parent = root

		-- The dealership display copy, on its plinth.
		local lot = DealershipLot.Build()
		Kit.placeAt(lot, CF.new(500, 0, 0))
		lot.Parent = root
		local display
		for _, d in ipairs(lot:GetChildren()) do
			if d:IsA("Model") and d:GetAttribute("ItemId") == "Pickup" and d:GetAttribute("Category") == "Truck" then
				display = d
			end
		end
		local dp = display and display:GetPivot().Position or V3.new(500, 0, 0)
		-- Keep only the Pickup's plinth and display in view: drop the other vehicles' parts
		-- so the render shows nothing else.
		for _, d in ipairs(lot:GetChildren()) do
			if d:IsA("Model") and d ~= display and d:GetAttribute("Category") ~= nil then
				d:Destroy()
			end
		end
		for _, d in ipairs(lot:GetDescendants()) do
			if d.Name == "BoxSpot" then
				d:Destroy()
			end
		end

		local wheels = {}
		for _, d in ipairs(pickup:GetDescendants()) do
			if d.Name == "Wheel" and d:IsA("BasePart") then
				table.insert(wheels, d)
			end
		end
		local fl = wheels[1].CFrame.Position
		for _, w in ipairs(wheels) do
			if
				w.CFrame.Position.X < fl.X - 0.1
				or (math.abs(w.CFrame.Position.X - fl.X) < 0.1 and w.CFrame.Position.Z < fl.Z)
			then
				fl = w.CFrame.Position
			end
		end

		-- The display copy's near-side front wheel (smallest world Z, then smallest X).
		local dw = dp
		if display then
			local best
			for _, d in ipairs(display:GetDescendants()) do
				if d.Name == "Wheel" and d:IsA("BasePart") then
					local c = d.CFrame.Position
					if best == nil or c.Z < best.Z - 0.1 or (math.abs(c.Z - best.Z) < 0.1 and c.X < best.X) then
						best = c
					end
				end
			end
			dw = best or dp
		end

		local cameras = {
			{ pos = { 0, 4.5, -34 }, target = { 0, 4.2, 0 }, fov = 34, label = "front" },
			{ pos = { -50, 5, 0 }, target = { 0, 4.5, 0 }, fov = 34, label = "side" },
			{ pos = { -36, 12, -38 }, target = { 0, 4.2, 0 }, fov = 34, label = "three-quarter" },
			{
				pos = { fl.X - 12, fl.Y + 2, fl.Z - 10 },
				target = { fl.X, fl.Y, fl.Z },
				fov = 40,
				label = "front-left wheel close up",
			},
			{
				pos = { fl.X - 10, 0.6, fl.Z },
				target = { fl.X, fl.Y, fl.Z },
				fov = 45,
				label = "wheel from the ground",
			},
			{ pos = { 10, 5, 0 }, target = { 60, 4.5, 0 }, fov = 34, label = "rustbucket side" },
			{
				pos = { dp.X - 38, dp.Y + 12, dp.Z - 34 },
				target = { dp.X, dp.Y + 4, dp.Z },
				fov = 36,
				label = "dealership plinth",
			},
			{
				pos = { dw.X - 7, dw.Y + 2.5, dw.Z - 10 },
				target = { dw.X, dw.Y, dw.Z },
				fov = 45,
				label = "dealership wheel close up",
			},
			{ pos = { 50, 5, 0 }, target = { 0, 4.5, 0 }, fov = 34, label = "side, the +X (right) side" },
			{ pos = { 110, 5, 0 }, target = { 60, 4.5, 0 }, fov = 34, label = "rustbucket, the +X (right) side" },
		}

		return {
			root = root,
			shadowRadius = 40,
			fov = 34,
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
				fogNear = 600,
				fogFar = 1200,
				exposure = 1.12,
				bloom = 0.05,
			},
			cameras = cameras,
		}
	end,
}
