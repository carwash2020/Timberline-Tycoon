--!nocheck
-- Display models on the dealership lot: anchored, no scripts, a price that
-- matches the server, and off the street, plaza and shop paths.
return function(t)
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local ShopLogic = t.shared("ShopLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local Util = t.shared("Util")
	local GameConfig = t.shared("GameConfig")
	local CoreLoop = t.shared("CoreLoop")

	-- Same rule as DealershipLot's signs: the published loop when MapBuilder
	-- has set it, otherwise the configured one (tests have no workspace).
	local function priceLoop()
		local ok, n = pcall(function()
			return CoreLoop.Active()
		end)
		if
			ok
			and (n == 1 or n == 2)
			and workspace ~= nil
			and workspace:GetAttribute(CoreLoop.ActiveAttribute) ~= nil
		then
			return n
		end
		return if GameConfig.CoreLoop == 2 then 2 else 1
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("every display is anchored, scriptless, and priced like the server", function()
		local lot = DealershipLot.Build()
		local displays = 0
		for _, child in ipairs(lot:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("ItemId") then
				displays += 1
				t.eq(child.ModelStreamingMode, t.roblox.Enum.ModelStreamingMode.Atomic, child.Name)
				local sign = child:FindFirstChild("PriceSign", true)
				t.ok(sign and sign:IsA("BasePart"), child.Name .. " price sign")
				t.ok(sign:FindFirstChild("BuyPrompt", true), child.Name .. " buy prompt")
				local id = child:GetAttribute("ItemId")
				local item = ItemCatalog.GetTruck(id) or ItemCatalog.GetTrailer(id)
				local price = ShopLogic.Price(item, priceLoop())
				local text = nil
				for _, d in ipairs(sign:GetDescendants()) do
					if d:IsA("TextLabel") then
						text = d.Text
					end
				end
				t.ok(
					text and string.find(text, Util.formatCash(price), 1, true),
					child.Name .. " tag " .. Util.formatCash(price)
				)
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then
						t.eq(d.Anchored, true, child.Name .. " " .. d.Name)
					end
					t.eq(d.ClassName == "Script" or d.ClassName == "LocalScript", false, child.Name)
				end
			end
		end
		t.eq(displays, 8, "5 trucks and 3 trailers")
		local facing = nil
		for _, child in ipairs(lot:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("ItemId") then
				local look = child:GetPivot().LookVector
				if facing == nil then
					facing = look
				else
					t.ok(look:Dot(facing) > 0.99, child.Name .. " faces with the row")
				end
				local sign = child:FindFirstChild("PriceSign", true)
				local localPos = child:GetPivot():PointToObjectSpace(sign.CFrame.Position)
				t.ok(localPos.Z < -1, child.Name .. " price sign is in front of the model")
				t.ok(math.abs(localPos.X) < 3, child.Name .. " price sign is on this model, not an empty spot")
			end
		end
	end)

	t.test("the store and the dealership lot stay off the street, plaza and paths", function()
		local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local town = WorldPlan.Town()
		local models = {}
		for _, spot in ipairs(town.shops) do
			if spot.kind == "HearthAndHome" or spot.kind == "Dealership" then
				local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
				Kit.placeAt(model, spot.cframe)
				table.insert(models, model)
			end
		end
		local lot = DealershipLot.Build()
		Kit.placeAt(lot, town.displayLot)
		table.insert(models, lot)
		local banned = {
			Plaza = true,
			MainStreet = true,
			HearthAndHomePath = true,
			ToolShedPath = true,
			DealershipPath = true,
			SpawnWalk = true,
			GondolaPath = true,
		}
		local function hits(part, area)
			local p = part.CFrame.Position
			local h = part.Size / 2
			return p.X + h.X > area.x0 and p.X - h.X < area.x1 and p.Z + h.Z > area.z0 and p.Z - h.Z < area.z1
		end
		for _, model in ipairs(models) do
			for _, part in ipairs(parts(model)) do
				if part.CanCollide then
					for _, area in ipairs(WorldLayout.TownPaint) do
						if banned[area.name] then
							-- The showroom meets the end of its own path (the
							-- ramp). The lot and the store stay off every one.
							local ownPath = model.Name == "Dealership" and area.name == "DealershipPath"
							if not ownPath then
								t.eq(hits(part, area), false, model.Name .. " " .. part.Name .. " on " .. area.name)
							end
						end
					end
				end
			end
		end
	end)
end
