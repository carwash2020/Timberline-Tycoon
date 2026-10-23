--!nocheck
-- Buying a trailer while driving a truck that can't tow (the Scout ATV):
-- the purchase goes through, but it isn't hitched, and the toast says why.
return function(t)
	local Vector3 = t.roblox.Vector3
	local COUNTER = Vector3.new(-45, 2.5, 99.5)

	local function node(children)
		local n = {}
		function n:FindFirstChild(name)
			return children[name]
		end
		return n
	end

	local function setup(equippedTruck)
		local profile = {
			cash = 5000,
			totalEarned = 0,
			bestAxeTier = 1,
			ownedTrucks = { "Rustbucket", "ScoutATV" },
			equippedTruck = equippedTruck,
			ownedTrailers = {},
			equippedTrailer = "",
			gear = {},
		}
		local toasts, switched = {}, {}
		local character = node({ HumanoidRootPart = { Position = COUNTER + Vector3.new(0, 0, -4) } })
		function character:FindFirstChildOfClass()
			return nil
		end
		local player = { Name = "Tester", Character = character, SetAttribute = function() end }
		local point = {
			WorldPosition = COUNTER,
			IsA = function(_, class)
				return class == "Attachment"
			end,
		}
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
					Equip = function(_, truckId, trailerId)
						table.insert(switched, truckId .. "+" .. (trailerId or ""))
						return true, nil
					end,
				},
			},
		})
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
			switched = switched,
		}
	end

	t.test("on the Scout ATV: bought, not hitched, and told why", function()
		local s = setup("ScoutATV")
		s.buy("Trailer", "PonyTrailer")
		t.eq(s.profile.ownedTrailers, { "PonyTrailer" })
		t.eq(s.profile.cash, 4400)
		t.eq(s.profile.equippedTrailer, "", "not hitched to a truck that can't tow")
		t.eq(s.switched, {}, "the rig isn't rebuilt")
		t.eq(s.toasts, {
			"Bought the Pony Trailer! The Scout ATV can't tow, so hitch it here once you drive a truck with a bed.",
		})
	end)

	t.test("on a truck with a bed: bought and hitched as before", function()
		local s = setup("Rustbucket")
		s.buy("Trailer", "PonyTrailer")
		t.eq(s.profile.equippedTrailer, "PonyTrailer")
		t.eq(s.switched, { "Rustbucket+PonyTrailer" })
	end)

	-- The hitch on the bigger trucks (M1.5): every trailer couples at its
	-- truck's back, its bed a tongue (2.6 studs) behind, and nothing of one
	-- runs into the other: the skids leave a gap and the trailer's tyres
	-- stand clear of the truck's.
	t.test("every trailer hitches to every truck with a bed, clear of it", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local TruckLayout = t.shared("TruckLayout")
		local TruckArt = t.shared("Art/TruckArt")
		for truckId, def in pairs(ItemCatalog.Trucks) do
			if def.bedCapacity > 0 then
				local lay = TruckLayout.For(def)
				local lastAxle = -math.huge
				for _, z in ipairs(lay.wheelZ) do
					lastAxle = math.max(lastAxle, z)
				end
				for trailerId, trailer in pairs(ItemCatalog.Trailers) do
					local label = truckId .. " + " .. trailerId
					local tl = TruckLayout.ForTrailer(trailer, lay)
					t.eq(tl.hitchZ, lay.length / 2, label .. ": hitched at the truck's back")
					t.ok(math.abs(tl.bedStart - tl.hitchZ - TruckLayout.Tongue) < 1e-9, label .. ": a tongue behind it")
					local model = TruckArt.Build(def, lay, trailer, tl)
					local coupler = model:FindFirstChild("Coupler")
					t.ok(coupler, label .. " has a coupler")
					local front = coupler.CFrame.Z - coupler.Size.Z / 2
					t.ok(math.abs(front - tl.hitchZ) < 0.2, label .. ": the coupler meets the truck's back")
					local skid, trailerSkid = model:FindFirstChild("Skid"), model:FindFirstChild("TrailerSkid")
					local skidBack = skid.CFrame.Z + skid.Size.Z / 2 + TruckArt.SkidRampRun
					local trailerFront = trailerSkid.CFrame.Z - trailerSkid.Size.Z / 2 - TruckArt.SkidRampRun
					t.ok(trailerFront - skidBack >= 1, label .. ": the skids don't meet")
					for _, z in ipairs(tl.axleZ) do
						t.ok(
							z - tl.wheelRadius >= lastAxle + lay.wheelRadius + 1,
							label .. ": the trailer's tyres clear the truck's"
						)
					end
				end
			end
		end
	end)
	-- T421: every wheel of every one of the 15 combos (3 trailers x the 5 towing trucks, the Timber Classic among
	-- them) has its tyre's bottom on the ground, parked and with the whole rig pitched 15 degrees onto a slope.
	-- The engine's physics cannot run here: the 3 seconds of towing (a rig that bounces or sinks) are a Studio check
	-- (tests/TrailerTow.spec cannot see them). What this pins is the geometry the physics starts from: each wheel
	-- centre is one radius above the ground plane, so a rigid rig on any plane touches with all of them.
	t.test(
		"all 15 combos: every wheel's tyre bottom is within 0.05 of the ground, flat and on a 15 degree slope",
		function()
			local roblox = t.roblox
			local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
			local ItemCatalog = t.shared("ItemCatalog")
			local TruckLayout = t.shared("TruckLayout")
			local TruckArt = t.shared("Art/TruckArt")
			local Gate = t.shared("VehicleMeshGate")
			local combos = Gate.Combos()
			t.eq(#combos, 15)
			local pitch = math.rad(15)
			for _, combo in ipairs(combos) do
				local def = ItemCatalog.GetTruck(combo.truck)
				local trailer = ItemCatalog.GetTrailer(combo.trailer)
				local lay = TruckLayout.For(def)
				local model = TruckArt.Build(def, lay, trailer, TruckLayout.ForTrailer(trailer, lay))
				local label = combo.truck .. " + " .. combo.trailer
				-- The slope: the rig tilted about its first contact (the front wheels'), the plane through that point.
				local rotate = CFrame.Angles(-pitch, 0, 0)
				local up = rotate:VectorToWorldSpace(Vector3.new(0, 1, 0))
				local wheels = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Wheel" and type(d:GetAttribute("Radius")) == "number" then
						table.insert(wheels, d)
					end
				end
				t.ok(#wheels >= 6, label .. " has wheels")
				local origin = rotate:PointToWorldSpace(Vector3.new(0, 0, lay.wheelZ[1]))
				for _, w in ipairs(wheels) do
					local r = w:GetAttribute("Radius")
					t.ok(
						math.abs(w.CFrame.Position.Y - r) <= 0.05,
						label .. " wheel at z " .. w.CFrame.Position.Z .. " is on the ground"
					)
					local centre = rotate:PointToWorldSpace(w.CFrame.Position)
					local gap = (centre - origin):Dot(up) - r
					t.ok(math.abs(gap) <= 0.05, label .. " wheel at z " .. w.CFrame.Position.Z .. " is on the slope")
				end
			end
		end
	)
end
