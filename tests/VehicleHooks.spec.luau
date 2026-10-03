--!nocheck
-- VehicleService's three hooks for the v2 loop's loose wood (M1.6,
-- V2_PLAN §4b): the real VehicleService spawning and recalling real
-- TruckArt trucks over a faked world (one parking slot, no terrain, no
-- physics). It proves:
--   * with no hooks (the v1 loop) a truck spawns and recalls as before;
--   * onRebuild hears the first truck after joining (no old truck; whether
--     the saved spot was in town, and where), and a recall or a switch
--     (the old truck, still there; in town or not; where it stands), and
--     what it returns gets the new truck once it's built and parked;
--   * Recall's warning before leaving a load out of town counts loose
--     pieces (loadCount) as it counts the v1 bed's logs;
--   * a hook that errors never breaks spawning.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	-- Lune's instances lack these; VehicleService only needs them to exist.
	-- A method registers once a process (VehicleBays.spec adds the same).
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

	local SLOT_AT = Vector3.new(40, 0.1, 30)

	local function setup()
		local ws = Instance.new("WorldModel")
		local slot = Instance.new("Part")
		slot.Name = "ParkingSlot"
		slot.Size = Vector3.new(10, 0.2, 60)
		slot.CFrame = CFrame.new(SLOT_AT)
		slot.Position = SLOT_AT
		slot:AddTag("ParkingSlot")
		slot:SetAttribute("Index", 1)
		slot.Parent = ws
		local w = { profile = { truckBed = {}, truckAt = {}, leftLoad = {} }, toasts = {} }
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function()
						return w.profile
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
				-- @lune/roblox instances have no events: a stand-in prompt.
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
		w.world = ws
		w.VehicleService = loader:server("VehicleService")
		w.VehicleService.Init(function(player, message)
			table.insert(w.toasts, { player = player, message = message })
		end)
		w.loader = loader
		w.player = {
			UserId = 7,
			Name = "Dale",
			DisplayName = "Dale",
			SetAttribute = function() end,
		}
		return w
	end

	t.test("no hooks (the v1 loop): a truck spawns and recalls as before", function()
		local w = setup()
		local VehicleService = w.VehicleService
		t.eq(VehicleService.Hooks.onRebuild, nil)
		local model = VehicleService.SpawnTruck(w.player, "Rustbucket")
		t.ok(model and model.Parent ~= nil, "spawned")
		t.ok(model:FindFirstChild("BedFloor"):FindFirstChild("BedZone"), "with its BedZone (inert)")
		local ok = VehicleService.Recall(w.player)
		t.ok(ok, "recalled")
		t.eq(model.Parent, nil, "the old one is gone")
		t.ok(VehicleService.GetVehicle(w.player) ~= model, "a new one")
	end)

	t.test("onRebuild: joining, then a recall; the new truck is handed over once built", function()
		local w = setup()
		local VehicleService = w.VehicleService
		local heard = {}
		VehicleService.Hooks.onRebuild = function(player, old, keepsLoad, at)
			local call = { player = player, old = old, keepsLoad = keepsLoad, at = at, oldParent = old and old.Parent }
			table.insert(heard, call)
			return function(new)
				call.new = new
				call.newParked = new.PrimaryPart.Anchored
				call.newIsTheirs = VehicleService.GetVehicle(player) == new
			end
		end
		-- Joining, the save saying the truck was far out in the Snowfields.
		w.profile.truckAt = { x = 900, y = 40, z = -700 }
		local first = VehicleService.SpawnTruck(w.player, "Pickup")
		t.eq(#heard, 1)
		t.eq(heard[1].old, nil, "the first truck since joining")
		t.eq(heard[1].keepsLoad, false, "the saved spot wasn't in town")
		t.ok((heard[1].at.Position - Vector3.new(900, 40, -700)).Magnitude < 1e-6, "where it stood")
		t.eq(heard[1].new, first, "handed the new truck")
		t.ok(heard[1].newParked and heard[1].newIsTheirs, "built, parked and theirs by then")
		-- A recall from the lot: in town.
		VehicleService.Recall(w.player)
		t.eq(#heard, 2)
		t.eq(heard[2].old, first, "told about the old truck")
		t.ok(heard[2].oldParent ~= nil, "while it's still there")
		t.eq(heard[2].keepsLoad, true, "in town: the load comes along")
		t.ok(heard[2].new ~= first and heard[2].new == VehicleService.GetVehicle(w.player))
	end)

	t.test("joining with an old save that doesn't say where the truck was keeps the load", function()
		local w = setup()
		local seen
		w.VehicleService.Hooks.onRebuild = function(_, _, keepsLoad, at)
			seen = { keepsLoad = keepsLoad, at = at }
			return nil
		end
		w.VehicleService.SpawnTruck(w.player, "Rustbucket")
		t.eq(seen.keepsLoad, true)
		t.eq(seen.at, nil)
	end)

	t.test("Recall warns before leaving loose pieces out of town (loadCount)", function()
		local w = setup()
		local VehicleService = w.VehicleService
		VehicleService.Hooks.loadCount = function(truck)
			t.eq(truck, VehicleService.GetVehicle(w.player))
			return 3
		end
		local truck = VehicleService.SpawnTruck(w.player, "Rustbucket")
		truck:PivotTo(CFrame.new(900, 40, -700)) -- parked far out
		local ok, why = VehicleService.Recall(w.player)
		t.eq(ok, false)
		t.eq(why, "Your 3 logs will be left where your truck stands. Press Send truck home again to go ahead.")
		t.ok(VehicleService.Recall(w.player), "the second press goes ahead")
	end)

	t.test("the Dealership won't swap a truck with loose wood riding on it in town", function()
		local w = setup()
		local VehicleService = w.VehicleService
		local riding = 2
		VehicleService.Hooks.loadCount = function()
			return riding
		end
		local truck = VehicleService.SpawnTruck(w.player, "Rustbucket")
		local ok, why = VehicleService.Equip(w.player, "Pickup", "")
		t.eq(ok, false)
		t.eq(why, VehicleService.UnloadFirstText)
		t.eq(VehicleService.GetVehicle(w.player), truck, "the same truck")
		riding = 0
		t.ok(VehicleService.Equip(w.player, "Pickup", ""), "an empty bed swaps")
		-- Out of town the load stays where it is, so the swap goes ahead.
		riding = 2
		VehicleService.GetVehicle(w.player):PivotTo(CFrame.new(900, 40, -700))
		t.ok(VehicleService.Equip(w.player, "Rustbucket", ""), "out of town: swapped, the load stays")
	end)

	t.test("without hooks, Recall's warning still counts the v1 bed's logs", function()
		local w = setup()
		local VehicleService = w.VehicleService
		local truck = VehicleService.SpawnTruck(w.player, "Rustbucket")
		t.ok(VehicleService.AddBedLog(w.player, { woodId = "oak", value = 7 }))
		t.eq(VehicleService.GetBedCount(w.player), 1)
		truck:PivotTo(CFrame.new(900, 40, -700))
		local ok, why = VehicleService.Recall(w.player)
		t.eq(ok, false)
		t.eq(why, "Your 1 log will be left where your truck stands. Press Send truck home again to go ahead.")
	end)

	t.test("a hook that errors never stops a truck spawning", function()
		local w = setup()
		w.VehicleService.Hooks.onRebuild = function()
			error("boom")
		end
		w.VehicleService.Hooks.loadCount = function()
			error("boom")
		end
		local model = w.VehicleService.SpawnTruck(w.player, "Flatbed")
		t.ok(model and model.Parent ~= nil, "spawned anyway")
		local warned = false
		for _, line in ipairs(w.loader.warnings) do
			if string.find(line, "hook onRebuild failed", 1, true) then
				warned = true
			end
		end
		t.ok(warned, "and the error is logged")
	end)

	t.test("painting a truck parked outside town leaves it there with its cargo", function()
		local w = setup()
		local VehicleService = w.VehicleService
		local truck = VehicleService.SpawnTruck(w.player, "Rustbucket")
		local spot = CFrame.new(900, 40, -700)
		truck:PivotTo(spot)
		t.ok(VehicleService.AddBedLog(w.player, { woodId = "oak", value = 7 }))
		local cargo = truck:FindFirstChild("BedVisuals"):GetChildren()[1]
		t.ok(cargo ~= nil, "a log is on the bed")
		w.profile.truckPaint = { Rustbucket = "#8E3B2F" }
		VehicleService.Repaint(w.player, "Rustbucket")
		t.eq(VehicleService.GetVehicle(w.player), truck, "the same truck, not a new one")
		t.eq(truck.Parent, w.world, "still in the world")
		t.ok((truck:GetPivot().Position - spot.Position).Magnitude < 1e-4, "still parked outside town")
		t.eq(truck:GetPivot(), spot, "the same spot")
		t.eq(cargo.Parent, truck:FindFirstChild("BedVisuals"), "the load is still on the bed")
		t.eq(VehicleService.GetBedCount(w.player), 1)
		local hood = truck:FindFirstChild("Hood", true)
		t.eq(hood.Color, roblox.Color3.fromHex("#8E3B2F"), "the body took the new color")
		t.eq(truck:GetAttribute("PaintHex"), "#8E3B2F")
	end)

	t.test("a failed respawn doesn't charge", function()
		local w = setup()
		local CoreLoop = w.loader:shared("CoreLoop")
		w.world:SetAttribute(CoreLoop.ActiveAttribute, 2)
		w.profile.cash = 100
		w.profile.totalEarned = 0
		w.profile.ownedTrucks = { "Pickup" }
		w.profile.equippedTruck = "Pickup"
		w.VehicleService.Hooks.blockSpawn = true
		local ok = w.VehicleService.Recall(w.player)
		t.eq(ok, false, "the truck never appeared")
		t.eq(w.profile.cash, 100, "the 2% fee is refunded")
		t.eq(w.profile.totalEarned, 0)
		t.eq(w.VehicleService.GetVehicle(w.player), nil, "nothing was left behind")
		w.VehicleService.Hooks.blockSpawn = false
		t.ok(w.VehicleService.Recall(w.player), "a later recall works")
		t.eq(w.profile.cash, 92, "Pickup is 2% of $400, and at least $2")
	end)

	t.test("despawn keeps the saved load, and a recall with no truck puts it back", function()
		local w = setup()
		w.profile.ownedTrucks = { "Rustbucket" }
		w.profile.equippedTruck = "Rustbucket"
		w.profile.cash = 0
		local VehicleService = w.VehicleService
		local model = VehicleService.SpawnTruck(w.player, "Rustbucket")
		t.ok(model and model.Parent ~= nil, "spawned")
		t.ok(VehicleService.AddBedLog(w.player, { woodId = "oak", value = 7 }))
		t.eq(#w.profile.truckBed, 1, "AddBedLog writes the save")
		VehicleService.DespawnTruck(w.player)
		t.eq(model.Parent, nil, "the truck is gone")
		t.eq(VehicleService.GetVehicle(w.player), nil)
		t.eq(#w.profile.truckBed, 1, "the log is still saved")
		t.eq(w.profile.truckBed[1].woodId, "oak")
		local ok = VehicleService.Recall(w.player)
		t.ok(ok, "recalled from the save")
		t.eq(VehicleService.GetBedCount(w.player), 1, "the load came back")
		t.eq(w.profile.truckBed[1].woodId, "oak")
	end)
end
