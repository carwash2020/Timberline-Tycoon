--!nocheck
-- VehicleService's parking bays (phase 12): the real VehicleService
-- spawning real TruckArt rigs into the real lot (WorldPlan.Town()'s 13
-- bays, as MapBuilder builds them) over a faked world (no terrain, no
-- physics). It proves:
--   * each rig takes the smallest free bay it fits, the lowest Index on a
--     tie (VehicleLogic.BayChoices), centred in it;
--   * a switch at the Dealership moves the rig to a bay that fits it (a
--     bigger rig to a bigger bay, a smaller one back to a small bay) and
--     gives the old bay up; a recall keeps a bay that's still as good a fit
--     as any, and moves to a better one that's come free; each move is told;
--   * with no bay it fits free, a rig parks with its tail at a bay's tail,
--     its nose out over the pull-out; with none that takes it, in an
--     overflow spot.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	-- Lune's instances lack these; VehicleService only needs them to exist.
	-- A method registers once a process (VehicleHooks.spec adds the same).
	local function stub(class, method, fn)
		pcall(roblox.implementMethod, class, method, fn)
	end
	stub("VehicleSeat", "GetPropertyChangedSignal", function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end)
	stub("WorldModel", "GetPartBoundsInBox", function()
		return {}
	end)
	stub("WorldModel", "Raycast", function()
		return nil
	end)

	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end

	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local town = WorldPlan.Town()

	local function setup()
		local ws = Instance.new("WorldModel")
		-- The lot as MapBuilder builds it.
		for index, cf in ipairs(town.parkingSlots) do
			local slot = Instance.new("Part")
			slot.Name = "ParkingSlot_" .. index
			slot.Size = town.parkingSizes[index]
			slot.CFrame = cf
			slot.Position = cf.Position -- Lune's parts read Position only once it's set
			slot:AddTag("ParkingSlot")
			slot:SetAttribute("Index", index)
			slot.Parent = ws
		end
		local w = { profiles = {}, toasts = {}, players = {} }
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						w.profiles[player] = w.profiles[player] or { truckBed = {}, truckAt = {}, leftLoad = {} }
						return w.profiles[player]
					end,
				},
				TreeService = { LogDiameter = 0.9 },
				TerrainBuilder = {
					LiftOnto = function(_, y)
						return y
					end,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					GetPlayerFromCharacter = function()
						return nil
					end,
				},
				CollectionService = {
					AddTag = function(_, inst, tag)
						inst:AddTag(tag)
					end,
					GetTagged = function(_, tag)
						local out = {}
						for _, d in ipairs(ws:GetDescendants()) do
							if d:HasTag(tag) then
								table.insert(out, d)
							end
						end
						return out
					end,
				},
				RunService = {
					IsStudio = function()
						return false
					end,
					Heartbeat = signal(),
				},
			},
			globals = {
				workspace = ws,
				task = {
					spawn = function() end,
					defer = function() end,
					delay = function() end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				Instance = {
					new = function(class)
						if class == "ProximityPrompt" then
							return {
								Triggered = signal(),
								SetAttribute = function() end,
							}
						end
						return Instance.new(class)
					end,
				},
			},
		})
		w.VehicleService = loader:server("VehicleService")
		w.VehicleService.Init(function(player, message)
			table.insert(w.toasts, { player = player, message = message })
		end)
		w.ItemCatalog = loader:shared("ItemCatalog")
		w.TruckLayout = loader:shared("TruckLayout")
		w.VehicleLogic = loader:shared("VehicleLogic")
		function w.player(id)
			local p = { UserId = id, Name = "P" .. id, DisplayName = "P" .. id, SetAttribute = function() end }
			table.insert(w.players, p)
			return p
		end
		-- The bay BayChoices picks for a rig with only `free` bays free (all
		-- of them when nil).
		function w.expected(truckId, trailerId, free)
			local layout = w.TruckLayout.For(w.ItemCatalog.GetTruck(truckId))
			local trailer = if trailerId then w.ItemCatalog.GetTrailer(trailerId) else nil
			local tl = if trailer then w.TruckLayout.ForTrailer(trailer, layout) else nil
			local length, width = w.TruckLayout.RigSize(layout, tl)
			local infos = {}
			for index, size in ipairs(town.parkingSizes) do
				if free == nil or free[index] then
					table.insert(infos, { index = index, length = size.Z, width = size.X })
				end
			end
			return w.VehicleLogic.BayChoices(infos, length, width, nil)[1], length
		end
		return w
	end

	-- Where a rig's pivot (its truck's middle) should be in bay `index`:
	-- the rig centred on the bay, or its tail at the bay's tail.
	local function homePivot(w, index, truckId, trailerId)
		local layout = w.TruckLayout.For(w.ItemCatalog.GetTruck(truckId))
		local trailer = if trailerId then w.ItemCatalog.GetTrailer(trailerId) else nil
		local tl = if trailer then w.TruckLayout.ForTrailer(trailer, layout) else nil
		local length = w.TruckLayout.RigSize(layout, tl)
		local size = town.parkingSizes[index]
		local shift = (if tl then tl.length / 2 else 0) + w.VehicleLogic.OverhangShift(size.Z, length)
		local cf = town.parkingSlots[index]
		return (cf * CFrame.new(0, 0, -shift)).Position
	end

	local function flatNear(a, b)
		return math.abs(a.X - b.X) < 1e-4 and math.abs(a.Z - b.Z) < 1e-4
	end

	t.test("each rig takes the smallest free bay it fits, nearest the spawn first, centred in it", function()
		local w = setup()
		local VS = w.VehicleService
		local taken = {}
		local function free()
			local out = {}
			for index in ipairs(town.parkingSlots) do
				out[index] = not taken[index]
			end
			return out
		end
		local rigs = {
			{ "Rustbucket" },
			{ "Pickup" },
			{ "Flatbed" },
			{ "LoggingRig" },
			{ "LoggingRig", "HeavyHauler" },
			{ "Pickup", "PonyTrailer" },
			{ "ScoutATV" },
		}
		for i, r in ipairs(rigs) do
			local p = w.player(i)
			local want = w.expected(r[1], r[2], free())
			local model = VS.SpawnTruck(p, r[1], nil, r[2])
			local label = r[1] .. (if r[2] then " + " .. r[2] else "")
			t.eq(VS.GetBayIndex(p), want, label .. " takes bay " .. tostring(want))
			t.ok(flatNear(model:GetPivot().Position, homePivot(w, want, r[1], r[2])), label .. " parks centred in it")
			t.ok(
				model:GetPivot().LookVector:Dot(town.parkingSlots[want].LookVector) > 0.9999,
				label .. " faces the way its bay does"
			)
			taken[want] = true
		end
		t.eq(VS.GetBayIndex(w.players[1]), 1, "the first small truck: bay 1, nearest the spawn")
		t.eq(VS.GetBayIndex(w.players[2]), 2, "the next: bay 2")
		t.eq(VS.GetBayIndex(w.players[5]), 11, "the Rig with the Heavy Hauler: the longest bay")
		t.eq(#w.toasts, 0, "joining says nothing")
	end)

	t.test("a switch moves the rig to a bay that fits, gives the old one up, and says so", function()
		local w = setup()
		local VS = w.VehicleService
		local dale = w.player(1)
		VS.SpawnTruck(dale, "Rustbucket")
		t.eq(VS.GetBayIndex(dale), 1)
		-- Up to the biggest rig there is: the longest bay.
		t.ok(VS.Equip(dale, "LoggingRig", "HeavyHauler"))
		t.eq(VS.GetBayIndex(dale), 11, "the Rig with the Heavy Hauler parks in the longest bay")
		t.ok(
			flatNear(VS.GetVehicle(dale):GetPivot().Position, homePivot(w, 11, "LoggingRig", "HeavyHauler")),
			"centred on it, trailer and all"
		)
		t.eq(#w.toasts, 1)
		t.ok(string.find(w.toasts[1].message, "bay 11", 1, true), "told where it parks: " .. w.toasts[1].message)
		-- Bay 1 was given up: the next player gets it.
		local pat = w.player(2)
		VS.SpawnTruck(pat, "Pickup")
		t.eq(VS.GetBayIndex(pat), 1, "the old bay is free again")
		-- Back down to a small truck: a small bay (bay 1 is Pat's now), and
		-- the longest bay is free for the next big rig.
		t.ok(VS.Equip(dale, "Rustbucket", ""))
		t.eq(VS.GetBayIndex(dale), 2, "back in a small bay")
		local sam = w.player(3)
		VS.SpawnTruck(sam, "LoggingRig", nil, "HeavyHauler")
		t.eq(VS.GetBayIndex(sam), 11, "the longest bay was given up")
	end)

	t.test("a recall keeps a bay that's as good a fit as any, and moves to a better one that's come free", function()
		local w = setup()
		local VS = w.VehicleService
		-- Fill the small bays (1-8), so the ninth small truck gets the next
		-- best: a Flatbed bay.
		for i = 1, 8 do
			VS.SpawnTruck(w.player(i), "Pickup")
			t.eq(VS.GetBayIndex(w.players[i]), i)
		end
		local late = w.player(9)
		VS.SpawnTruck(late, "Pickup")
		local flatbedBay = VS.GetBayIndex(late)
		t.ok(town.parkingSizes[flatbedBay] == WorldPlan.ParkingBays.flatbed, "the ninth Pickup gets a Flatbed bay")
		-- A recall with the small bays still full keeps it, quietly.
		t.ok(VS.Recall(late))
		t.eq(VS.GetBayIndex(late), flatbedBay, "kept: still as good a fit as any free bay")
		t.eq(#w.toasts, 0, "nothing to say")
		-- Someone in bay 3 leaves; the next recall moves to it, and says so.
		local early = w.player(10)
		VS.SpawnTruck(early, "Pickup") -- takes the other Flatbed bay
		VS.DespawnTruck(w.players[3])
		t.ok(VS.Recall(early))
		t.eq(VS.GetBayIndex(early), 3, "moved to the small bay that came free")
		t.eq(#w.toasts, 1)
		t.ok(string.find(w.toasts[1].message, "bay 3", 1, true), w.toasts[1].message)
	end)

	t.test("no bay it fits free: tail at a bay's tail, nose out; none that takes it: an overflow spot", function()
		local w = setup()
		local VS = w.VehicleService
		local VehicleLogic = w.VehicleLogic
		-- Two biggest rigs: the second finds the longest bay taken.
		VS.SpawnTruck(w.player(1), "LoggingRig", nil, "HeavyHauler")
		t.eq(VS.GetBayIndex(w.players[1]), 11)
		local second = w.player(2)
		local model = VS.SpawnTruck(second, "LoggingRig", nil, "HeavyHauler")
		local index = VS.GetBayIndex(second)
		local _, length = w.expected("LoggingRig", "HeavyHauler")
		local size = town.parkingSizes[index]
		t.ok(index ~= nil and index ~= 11, "it takes another bay")
		if length > size.Z then
			t.ok(length - size.Z <= VehicleLogic.MaxOverhang, "a nose out no further than MaxOverhang")
		end
		t.ok(
			flatNear(model:GetPivot().Position, homePivot(w, index, "LoggingRig", "HeavyHauler")),
			"tail at the bay's tail (or centred if it fits)"
		)
		-- Its back end sits on the bay's tail end when it's longer.
		if length > size.Z then
			local cf = town.parkingSlots[index]
			local layout = w.TruckLayout.For(w.ItemCatalog.GetTruck("LoggingRig"))
			local back = model:GetPivot() * Vector3.new(0, 0, layout.length / 2 + (length - layout.length))
			local tail = cf * Vector3.new(0, 0, size.Z / 2)
			t.ok(flatNear(back, tail), "its back on the bay's tail")
		end
		-- Fill every bay, then one more: an overflow spot.
		for i = 3, #town.parkingSlots do
			VS.SpawnTruck(w.player(i), "ScoutATV")
		end
		local last = w.player(99)
		local extra = VS.SpawnTruck(last, "ScoutATV")
		t.eq(VS.GetBayIndex(last), nil, "every bay taken: an overflow spot")
		local spot = VehicleLogic.OverflowSpot(0)
		t.ok(flatNear(extra:GetPivot().Position, spot), "the first overflow spot, west of the spawn")
	end)
end
