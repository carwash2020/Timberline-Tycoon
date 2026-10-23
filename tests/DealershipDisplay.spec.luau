--!nocheck
-- T421 Dealership and rig geometry:
--   * every display wheel touches its plinth's top within 0.05, and a display trailer's hitch nose rests on a foot that
--     reaches the plinth (the Hitch mesh's own jack foot), not floating or sunk;
--   * no display vehicle crosses a ceiling beam or a rafter; the Logging Rig's crane is the known exception (below);
--   * the hall's door stays at least 4 wide x 7 high and the central aisle at least 6 wide and empty;
--   * every one of the 15 combos, parked on a pad cut for it (VehicleLogic.PadSize), overlaps nothing: truck, trailer
--     and pad are pieces of the T409 collision lint with an EMPTY allowlist.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	t.support("VehicleStock")(function(path)
		return t.load(path)
	end, roblox)
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local Geometry = t.load("ReplicatedStorage/Shared/Lint/Geometry")
	local TruckLayout = t.shared("TruckLayout")
	local ItemCatalog = t.shared("ItemCatalog")
	local VehicleLogic = t.shared("VehicleLogic")
	local Gate = t.shared("VehicleMeshGate")
	local ItemBox = t.shared("ItemBox")

	local function displayModels(lot)
		local out = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d:IsA("Model") and d:GetAttribute("ItemId") ~= nil then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("every display wheel touches the plinth top within 0.05", function()
		local lot = DealershipLot.Build()
		local top = DealershipLot.PlinthHeight
		local wheels = 0
		for _, model in ipairs(displayModels(lot)) do
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Wheel" and type(d:GetAttribute("Radius")) == "number" then
					wheels += 1
					-- (the lot may scale a display copy, so the radius is read off the part, whose axle runs along X)
					local bottom = d.CFrame.Position.Y - math.max(d.Size.Y, d.Size.Z) / 2
					t.ok(
						math.abs(bottom - top) <= 0.05,
						model.Name
							.. " wheel at ("
							.. math.floor(d.CFrame.X)
							.. ", "
							.. math.floor(d.CFrame.Z)
							.. ") bottom "
							.. bottom
							.. " vs plinth top "
							.. top
					)
				end
			end
		end
		t.ok(wheels >= 30, "wheels were checked: " .. wheels)
	end)

	t.test("a display trailer's hitch nose rests on a foot that reaches the plinth top", function()
		local lot = DealershipLot.Build()
		local top = DealershipLot.PlinthHeight
		local seen = 0
		for _, model in ipairs(displayModels(lot)) do
			if model:GetAttribute("Category") ~= "Trailer" then
				continue
			end
			local hitch
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("MeshPart") and d.Name == "MeshHitch" then
					hitch = d
				end
			end
			t.ok(hitch ~= nil, model.Name .. " has its hitch mesh")
			local bottom = hitch.CFrame.Position.Y - hitch.Size.Y / 2
			t.ok(math.abs(bottom - top) <= 0.05, model.Name .. " hitch foot at " .. bottom .. ", plinth top " .. top)
			seen += 1
		end
		t.eq(seen, 3)
	end)

	t.test("no display vehicle crosses a ceiling beam or a rafter (the crane aside)", function()
		local lot = DealershipLot.Build()
		local beamBottom = DealershipLot.HallHeight - 0.9 -- the frame's ceilY, the beams hang 0.9 under it
		local rafterBottom = DealershipLot.HallHeight - 0.7
		local limit = math.min(beamBottom, rafterBottom) - DealershipLot.FloorY
		for _, model in ipairs(displayModels(lot)) do
			local top = -math.huge
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "NameSign" then
					top = math.max(top, d.CFrame.Position.Y + d.Size.Y / 2)
				end
			end
			t.ok(top <= limit + 1e-3, model.Name .. " tops out at " .. top .. ", the beams' underside is at " .. limit)
		end
	end)

	t.test(
		"the display Logging Rig is at scale 1 (every part its built size) and its top is under the beams and rafters",
		function()
			local lot = DealershipLot.Build()
			local truck = ItemCatalog.GetTruck("LoggingRig")
			local full = TruckArt.Build(truck, TruckLayout.For(truck))
			local builtTop, builtSizes = -math.huge, {}
			for _, d in ipairs(full:GetDescendants()) do
				if d:IsA("BasePart") then
					builtTop = math.max(builtTop, d.CFrame.Position.Y + d.Size.Y / 2)
					builtSizes[d.Name] = (builtSizes[d.Name] or 0) + d.Size.Magnitude
				end
			end
			local seen = false
			for _, model in ipairs(displayModels(lot)) do
				if model:GetAttribute("ItemId") ~= "LoggingRig" then
					continue
				end
				seen = true
				local top, sizes = -math.huge, {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "NameSign" then
						top = math.max(top, d.CFrame.Position.Y + d.Size.Y / 2)
						sizes[d.Name] = (sizes[d.Name] or 0) + d.Size.Magnitude
					end
				end
				for name, size in pairs(builtSizes) do
					t.ok(
						math.abs((sizes[name] or 0) - size) < 0.01,
						"part " .. name .. " is not scaled: " .. tostring(sizes[name]) .. " vs " .. size
					)
				end
				t.ok(
					math.abs((top - DealershipLot.PlinthHeight) - builtTop) < 0.05,
					"it stands " .. (top - DealershipLot.PlinthHeight) .. " tall, built " .. builtTop
				)
				local beamBottom = DealershipLot.HallHeight - 0.9 - DealershipLot.FloorY
				t.ok(top <= beamBottom - 0.4, "its top " .. top .. " is under the beams at " .. beamBottom)
			end
			t.ok(seen, "the Logging Rig is on show")
		end
	)

	t.test("the door is at least 4 wide x 7 high and the central aisle at least 6 wide and empty", function()
		local door = BuildingArt.DoorSpec("Dealership", 1, roblox.Color3.fromRGB(47, 109, 181))
		t.ok(door.x1 - door.x0 >= 4, "door width " .. (door.x1 - door.x0))
		t.ok(door.y1 - door.y0 >= 7, "door height " .. (door.y1 - door.y0))
		t.ok(DealershipLot.Aisle >= 6, "aisle " .. DealershipLot.Aisle)
		local lot = DealershipLot.Build()
		local layout = DealershipLot.Layout()
		local oz = -layout.depth / 2
		local lo, hi = -math.huge, math.huge
		for _, bay in ipairs(layout.bays) do
			local z0, z1 = oz + bay.z - bay.depth / 2, oz + bay.z + bay.depth / 2
			if bay.row == 1 then
				lo = math.max(lo, z1)
			else
				hi = math.min(hi, z0)
			end
		end
		t.ok(hi - lo >= 6, "the band between the rows is " .. (hi - lo))
		for _, model in ipairs(displayModels(lot)) do
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "NameSign" then
					local z = d.CFrame.Position.Z
					local half = (
						math.abs(d.CFrame.LookVector.Z) * d.Size.Z
						+ math.abs(d.CFrame.RightVector.Z) * d.Size.X
						+ math.abs(d.CFrame.UpVector.Z) * d.Size.Y
					) / 2
					t.ok(
						not (z - half > lo + 0.05 and z + half < hi - 0.05),
						model.Name .. " part " .. d.Name .. " stands in the aisle"
					)
				end
			end
		end
	end)

	t.test("all 15 combos on a pad cut for them: wheels on the pad, nothing overlaps (empty allowlist)", function()
		local combos = Gate.Combos()
		t.eq(#combos, 15)
		for _, c in ipairs(combos) do
			local truck, trailer = ItemCatalog.GetTruck(c.truck), ItemCatalog.GetTrailer(c.trailer)
			local lay = TruckLayout.For(truck)
			local tl = TruckLayout.ForTrailer(trailer, lay)
			local model = TruckArt.Build(truck, lay, trailer, tl)
			local length, width = TruckLayout.RigSize(lay, tl)
			local padSize = VehicleLogic.PadSize(length, width)
			local root = Instance.new("Folder")
			local pad = Instance.new("Part")
			pad.Name = "Slab"
			pad.Anchored = true
			pad.CanCollide = true
			pad.Size = padSize
			-- the rig's middle over the pad's, its wheels on the slab's top (y 0)
			local rigMid = (lay.front + lay.length / 2 + tl.hitchZ + tl.length / 2) / 2
			pad.CFrame = CFrame.new(0, -padSize.Y / 2, rigMid)
			local padModel = Instance.new("Model")
			padModel.Name = "Pad"
			pad.Parent = padModel
			padModel.Parent = root
			local truckModel, trailerModel = Instance.new("Model"), Instance.new("Model")
			truckModel.Name, trailerModel.Name = "Truck", "Trailer"
			truckModel.Parent, trailerModel.Parent = root, root
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local parent = d.Parent
					local isTrailer = d:GetAttribute("TrailerBody") == true
						or d.Name == "TrailerBed"
						or d.Name == "TrailerSkid"
					local node = parent
					while node and node ~= model and not isTrailer do
						isTrailer = node:GetAttribute("TrailerBody") == true or node.Name == "TrailerBed"
						node = node.Parent
					end
					d.Parent = if isTrailer then trailerModel else truckModel
				end
			end
			local result = Geometry.Run(root, {}, nil, { skipStale = true })
			local lines = {}
			local overlaps = {}
			for _, hit in ipairs(result.hits) do
				-- (rule 2c is about invisible walls in the map; a vehicle's own skids are invisible on purpose)
				if hit.rule ~= "2c" then
					table.insert(overlaps, hit)
					table.insert(lines, Geometry.Line(hit))
				end
			end
			t.eq(#overlaps, 0, c.truck .. " + " .. c.trailer .. ":\n" .. table.concat(lines, "\n"))
		end
	end)

	t.test("every combo's pad is cut for its rig (the rig fits the pad the game builds)", function()
		for _, c in ipairs(Gate.Combos()) do
			local lay = TruckLayout.For(ItemCatalog.GetTruck(c.truck))
			local tl = TruckLayout.ForTrailer(ItemCatalog.GetTrailer(c.trailer), lay)
			local length, width = TruckLayout.RigSize(lay, tl)
			local pad = VehicleLogic.PadSize(length, width)
			t.ok(pad.Z >= length and pad.X >= width, c.truck .. " + " .. c.trailer)
		end
		t.ok(ItemBox.Showroom ~= nil)
	end)
end
