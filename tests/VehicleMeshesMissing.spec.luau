--!nocheck
-- T421: a truck or trailer with any empty mesh id is not for sale. It is left out of the Dealership's stock, the buy
-- request is refused, and BootReport logs vehicleMeshesMissing with the missing names. Nothing part-built stands in
-- its place. With every id empty (as mesh_ids.txt is until Connor's uploads) the Dealership sells no T421 vehicle and
-- BootReport lists all 54.
return function(t)
	local fs = require("@lune/fs")
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local COUNTER = Vector3.new(-45, 2.5, 99.5)

	local Gate = t.load("ReplicatedStorage/Shared/VehicleMeshGate")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local TruckLayout = t.shared("TruckLayout")
	local BootReport = t.server("BootReport")
	local Rule = t.shared("VehicleSpawnRule")

	local function emptyIds()
		local ids = Gate.FakeIds()
		for key in pairs(ids) do
			ids[key] = ""
		end
		return ids
	end

	-- The 54 names from the file the id table is made from.
	local function t421Names()
		local out = {}
		for line in string.gmatch(fs.readFile("assets/vehicles/t421/mesh_ids.txt"), "[^\r\n]+") do
			local name = string.match(line, "^%s*([%w_]+)%s*=")
			table.insert(out, (string.gsub(name, "_", "/")))
		end
		return out
	end

	t.test("all ids empty: no T421 vehicle is complete and 54 names are missing", function()
		Gate.SetIds(emptyIds())
		for _, trailer in ipairs(Gate.Trailers) do
			t.eq(Gate.Complete("Trailer", trailer), false, trailer)
			t.eq(#Gate.Missing("Trailer", trailer), 16, trailer .. " needs 16")
		end
		t.eq(Gate.Complete("Truck", "TimberClassic"), false)
		t.eq(#Gate.MissingKeys(), 54)
		t.eq(Gate.MissingKeys(), t421Names(), "in the file's order")
		for _, id in ipairs({ "Rustbucket", "Pickup", "ScoutATV", "Flatbed", "LoggingRig" }) do
			t.eq(Gate.Complete("Truck", id), true, id .. " is never gated")
		end
		Gate.SetIds(nil)
	end)

	t.test("one empty id takes only its own trailer off sale", function()
		local ids = Gate.FakeIds()
		ids["RanchTrailer/Flatbed/Lights"] = ""
		Gate.SetIds(ids)
		t.eq(Gate.Complete("Trailer", "RanchTrailer"), false)
		t.eq(Gate.Missing("Trailer", "RanchTrailer"), { "RanchTrailer/Flatbed/Lights" })
		t.eq(Gate.Complete("Trailer", "PonyTrailer"), true)
		t.eq(Gate.Complete("Trailer", "HeavyHauler"), true)
		Gate.SetIds(nil)
	end)

	t.test("BootReport logs vehicleMeshesMissing with the list of names", function()
		local missing = table.concat(t421Names(), "; ")
		local world = {
			GetAttribute = function(_, name)
				return if name == "vehicleMeshesMissing" then missing else nil
			end,
		}
		local line = BootReport.Line(world, 0)
		t.ok(string.find(line, "vehicleMeshesMissing", 1, true), line)
		t.ok(string.find(line, "54 vehicle meshes missing", 1, true), line)
		for _, name in ipairs(t421Names()) do
			t.ok(string.find(line, name, 1, true), name .. " is listed")
		end
		local none = BootReport.Line({
			GetAttribute = function()
				return nil
			end,
		}, 0)
		t.ok(not string.find(none, "vehicleMeshesMissing", 1, true), "nothing missing, nothing said")
	end)

	t.test("an owned vehicle with missing meshes is logged too", function()
		Gate.SetIds(emptyIds())
		local line = BootReport.OwnedMissingLine("Ann", { "Pickup", "TimberClassic" }, { "PonyTrailer" }, Gate.Missing)
		t.ok(line and string.find(line, "vehicleMeshesMissing", 1, true) ~= nil, tostring(line))
		t.ok(string.find(line, "TimberClassic", 1, true) and string.find(line, "PonyTrailer", 1, true))
		t.ok(
			not string.find(line, "; Pickup (", 1, true) and not string.find(line, "owns Pickup (", 1, true),
			"the Pickup is complete"
		)
		t.eq(BootReport.OwnedMissingLine("Bob", { "Pickup" }, {}, Gate.Missing), nil)
		Gate.SetIds(nil)
	end)

	local function lot()
		DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
		return DealershipLot.Build()
	end

	local function stock(root)
		local boxes, models, signs = {}, {}, {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == "BoxSpot" then
				boxes[d:GetAttribute("ItemId")] = true
			elseif d:IsA("Model") and d:GetAttribute("ItemId") ~= nil then
				models[d:GetAttribute("ItemId")] = d
			end
		end
		return boxes, models
	end

	t.test("with every id empty the Dealership stocks no trailer: no box, no vehicle, a Coming soon sign", function()
		Gate.SetIds(emptyIds())
		local root = lot()
		local boxes, models = stock(root)
		for _, id in ipairs({ "PonyTrailer", "RanchTrailer", "HeavyHauler" }) do
			t.eq(boxes[id], nil, id .. " has no box to buy")
			t.eq(models[id], nil, id .. " has no vehicle on its plinth, part-built or not")
		end
		for _, id in ipairs({ "Rustbucket", "Pickup", "ScoutATV", "Flatbed", "LoggingRig" }) do
			t.eq(boxes[id], true, id .. " is still stocked")
			t.ok(models[id] ~= nil, id .. " is on its plinth")
		end
		local soon = 0
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text and string.find(d.Text, DealershipLot.ComingSoonText, 1, true) then
				soon += 1
			end
		end
		t.ok(soon >= 3, "the empty plinths say so: " .. soon)
		Gate.SetIds(nil)
	end)

	t.test("a missing-mesh vehicle's plinth is dressed COMING SOON, not empty, mesh-free and collision-free", function()
		Gate.SetIds(emptyIds())
		local root = lot()
		local count = function(name)
			local n = 0
			for _, d in ipairs(root:GetDescendants()) do
				if d.Name == name then
					n += 1
					t.ok(d:IsA("Part"), name .. " is a plain part, no mesh")
					t.eq(d.CanCollide, false, name .. " does not collide")
				end
			end
			return n
		end
		t.eq(count("ComingSoonBoard"), 3, "a board per trailer plinth")
		t.eq(count("ComingSoonBoardFrame"), 3)
		t.eq(count("ComingSoonSheet"), 3, "a dust sheet over a vehicle-sized hump")
		t.eq(count("ComingSoonSheetRidge"), 3)
		t.eq(count("StanchionPost"), 12, "four stanchions each")
		t.eq(count("StanchionRope"), 12)
		local texts = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == "ComingSoonBoard" then
				for _, label in ipairs(d:GetDescendants()) do
					if label:IsA("TextLabel") then
						texts[label.Text] = true
					end
				end
			end
		end
		for _, id in ipairs({ "Pony Trailer", "Ranch Trailer", "Heavy Hauler" }) do
			t.ok(texts[id .. "\n" .. DealershipLot.ComingSoonText], id .. " is named over COMING SOON on its board")
		end
		Gate.SetIds(nil)
	end)

	t.test("with the ids in, all eight are stocked (the control)", function()
		Gate.SetIds(Gate.FakeIds())
		local boxes = stock(lot())
		local n = 0
		for _ in pairs(boxes) do
			n += 1
		end
		t.eq(n, 8)
		Gate.SetIds(nil)
	end)

	-- The buy request, on the real ShopService.
	local function setup(ids)
		local profile = {
			cash = 50000,
			totalEarned = 0,
			bestAxeTier = 1,
			ownedTrucks = { "Rustbucket" },
			equippedTruck = "Rustbucket",
			ownedTrailers = {},
			equippedTrailer = "",
			gear = {},
			storage = {},
		}
		local toasts = {}
		local character = {
			FindFirstChild = function(_, name)
				return if name == "HumanoidRootPart" then { Position = COUNTER + Vector3.new(0, 0, -4) } else nil
			end,
			FindFirstChildOfClass = function()
				return nil
			end,
		}
		local player = { Name = "Tester", Character = character, SetAttribute = function() end }
		local point = {
			WorldPosition = COUNTER,
			IsA = function(_, class)
				return class == "Attachment"
			end,
		}
		local function node(children)
			return {
				FindFirstChild = function(_, name)
					return children[name]
				end,
			}
		end
		local map = node({ Dealership = node({ Counter = node({ ShopPoint = point }) }) })
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				AxeService = {},
				MilestoneService = { Mark = function() end },
				QuestService = { Event = function() end },
				VehicleService = {
					Equip = function()
						return true, nil
					end,
				},
			},
		})
		loader:shared("VehicleMeshGate").SetIds(ids)
		local ShopService = loader:server("ShopService")
		local buy
		local function remote(set)
			return {
				OnServerEvent = {
					Connect = function(_, fn)
						set(fn)
					end,
				},
			}
		end
		ShopService.Init(
			map,
			remote(function(fn)
				buy = fn
			end),
			remote(function() end),
			function(_, message)
				table.insert(toasts, message)
			end
		)
		return {
			buy = function(category, id)
				buy(player, category, id)
			end,
			profile = profile,
			toasts = toasts,
		}
	end

	t.test("the buy request for a trailer with a missing mesh is refused: no cash spent, nothing owned", function()
		local s = setup(emptyIds())
		s.buy("Trailer", "RanchTrailer")
		t.eq(s.profile.ownedTrailers, {})
		t.eq(s.profile.cash, 50000)
		t.eq(#s.toasts, 1)
		t.ok(string.find(s.toasts[1], "isn't in stock yet", 1, true), s.toasts[1])
	end)

	t.test("the same request with every id in goes through (the control)", function()
		local s = setup(Gate.FakeIds())
		s.buy("Trailer", "RanchTrailer")
		t.eq(s.profile.ownedTrailers, { "RanchTrailer" })
		t.ok(s.profile.cash < 50000)
	end)

	t.test("the Timber Classic cannot be bought for cash, with the ids in or out", function()
		for _, ids in ipairs({ emptyIds(), Gate.FakeIds() }) do
			local s = setup(ids)
			s.buy("Truck", "TimberClassic")
			t.eq(s.profile.ownedTrucks, { "Rustbucket" })
			t.eq(s.profile.cash, 50000)
		end
	end)

	t.test("an owned trailer with missing meshes still tows, and no part-built hull shows", function()
		Gate.SetIds(emptyIds())
		local truck = ItemCatalog.GetTruck("Rustbucket")
		local trailer = ItemCatalog.GetTrailer("RanchTrailer")
		local lay = TruckLayout.For(truck)
		local model = TruckArt.Build(truck, lay, trailer, TruckLayout.ForTrailer(trailer, lay))
		local wheels, seenHull = 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("TrailerBody") == true then
				if d.Name == "Wheel" then
					wheels += 1
				elseif
					d.Transparency < 1
					and not d:FindFirstAncestor("Wheel")
					and d.Parent
					and d.Parent.Name ~= "Wheel"
				then
					seenHull += 1
				end
			end
		end
		t.eq(wheels, 4, "the wheels are there")
		t.eq(seenHull, 0, "no visible part-built trailer part")
		t.ok(model:FindFirstChild("TrailerBed", true) ~= nil, "the collision bed is still there to tow")
		Gate.SetIds(nil)
	end)

	t.test(
		"the spawn rule: an owner's Timber Classic with missing meshes is not spawned, the other trucks are",
		function()
			Gate.SetIds(emptyIds())
			local ok = Rule.CanSpawn(ItemCatalog.GetTruck("TimberClassic"), true)
			t.eq(ok, false)
			t.eq((Rule.CanSpawn(ItemCatalog.GetTruck("Pickup"), false)), true)
			Gate.SetIds(nil)
		end
	)
end
