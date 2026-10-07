--!nocheck
-- NPCService: builds the townsfolk into a map the way GameServer's call
-- finds it (shops with Counters, the sell zone, the gondola platform):
-- Murph Persistent under the map, everyone else Atomic in "Townsfolk",
-- keepers behind their counters, walkers published with their routes.

return function(t)
	local roblox = t.roblox
	local Instance, Vector3, Vector2, CFrame, Color3, Enum =
		roblox.Instance, roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Color3, roblox.Enum

	local function part(parent, name, size, cf)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Parent = parent
		return p
	end

	-- A map with what NPCService looks for (shops turned a little, to prove
	-- keepers follow the counter's own axes).
	local function fakeMap(skip)
		local map = Instance.new("Folder")
		map.Name = "TimberlineMap"
		local counters = {}
		for i, kind in ipairs({ "ToolShed", "Dealership", "HearthAndHome", "LandOffice" }) do
			if kind ~= skip then
				local shop = Instance.new("Model")
				shop.Name = kind
				counters[kind] = part(
					shop,
					"Counter",
					Vector3.new(10, 3, 2),
					CFrame.new(-60 + i * 40, 2.5, 101) * CFrame.Angles(0, 0.2 * i, 0)
				)
				shop.Parent = map
			end
		end
		local station = Instance.new("Model")
		station.Name = "GondolaTown"
		part(station, "Platform", Vector3.new(10, 1, 10), CFrame.new(-40, 0.5, 150))
		station.Parent = map
		local sell = Instance.new("Model")
		sell.Name = "SellArea"
		part(sell, "SellZone", Vector3.new(28, 12, 52), CFrame.new(53, 6, 111)) -- as MapBuilder builds it (the sell station)
		sell.Parent = map
		return map, counters
	end

	local function service()
		local loader = t.loader()
		return loader:server("NPCService"), loader:shared("NPCData"), loader
	end

	t.test("Murph: a Persistent model straight under the map, with QuestUI's parts", function()
		local NPCService = service()
		local map = fakeMap()
		NPCService.Init(map)
		local murph = map:FindFirstChild("Murph")
		t.ok(murph and murph:IsA("Model"), "Murph")
		t.eq(murph.ModelStreamingMode, Enum.ModelStreamingMode.Persistent)
		for _, name in ipairs({ "Head", "Beard", "Beanie", "Torso", "LeftArm", "RightArm" }) do
			t.ok(murph:FindFirstChild(name), name)
		end
		t.ok(murph:HasTag("NPC"), "tagged NPC")
		t.eq(murph:GetAttribute("NPCId"), "Murph")
	end)

	t.test("everyone else: Atomic, tagged, in Townsfolk", function()
		local NPCService, NPCData = service()
		local map = fakeMap()
		NPCService.Init(map)
		local folder = map:FindFirstChild("Townsfolk")
		t.ok(folder, "Townsfolk folder")
		for _, npc in ipairs(NPCData.All()) do
			if npc.id ~= "Murph" then
				local m = folder:FindFirstChild(npc.id)
				t.ok(m, npc.id .. " missing")
				t.eq(m.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
				t.ok(m:HasTag("NPC"), npc.id .. " tagged")
				t.eq(m.PrimaryPart.Name, "HumanoidRootPart")
			end
		end
	end)

	t.test("shopkeepers stand behind their own counter, facing the customers", function()
		local NPCService, NPCData = service()
		local map, counters = fakeMap()
		NPCService.Init(map)
		for _, npc in ipairs(NPCData.All()) do
			if npc.spot.kind == "counter" then
				local counter = counters[npc.spot.model]
				local m = map.Townsfolk:FindFirstChild(npc.id)
				local root = m.PrimaryPart.CFrame
				local rel = counter.CFrame:PointToObjectSpace(root.Position)
				t.ok(rel.Z > counter.Size.Z / 2 + 0.5, npc.id .. " isn't behind the counter")
				t.ok(math.abs(rel.X) < 1e-3, npc.id .. " isn't centred on the counter")
				local feet = root.Position.Y - m:GetAttribute("RootHeight")
				if npc.spot.ground == nil then -- the Land Office is out on the terrain, not y = 0
					t.ok(math.abs(feet - (counter.CFrame.Position.Y - counter.Size.Y / 2)) < 1e-3, npc.id .. "'s feet")
				end
				t.ok(
					(root.LookVector - counter.CFrame.LookVector).Magnitude < 1e-3,
					npc.id .. " faces away from the shop's front"
				)
			end
		end
	end)

	t.test("walkers publish their route and don't collide; the others do", function()
		local NPCService, NPCData = service()
		local map = fakeMap()
		NPCService.Init(map)
		for _, npc in ipairs(NPCData.All()) do
			local m = map:FindFirstChild(npc.id, true)
			if npc.route then
				local route = NPCData.DecodeRoute(m:GetAttribute("Route"))
				t.eq(#route, #npc.route)
				t.eq(m:GetAttribute("Speed"), npc.speed)
				t.eq(m:GetAttribute("RouteOffset"), NPCData.RouteOffset(npc.id))
				t.ok(not m.PrimaryPart.CanCollide, npc.id .. " shouldn't collide")
				local p = m.PrimaryPart.CFrame.Position
				t.ok(
					math.abs(p.X - npc.route[1].x) < 1e-3 and math.abs(p.Z - npc.route[1].z) < 1e-3,
					npc.id .. " starts at waypoint 1"
				)
			else
				t.eq(m:GetAttribute("Route"), nil)
				t.ok(m.PrimaryPart.CanCollide, npc.id .. " should block like a person")
			end
		end
	end)

	t.test("a missing shop: its keeper stands at the fallback, with a warning", function()
		local NPCService, NPCData, loader = service()
		local map = fakeMap("Dealership")
		NPCService.Init(map)
		local dale = map.Townsfolk:FindFirstChild("Dale")
		local feet = dale.PrimaryPart.CFrame.Position - Vector3.new(0, dale:GetAttribute("RootHeight"), 0)
		t.ok((feet - NPCData.Get("Dale").spot.fallback).Magnitude < 1e-3, "Dale at the fallback")
		t.ok(#loader.warnings >= 1 and string.find(loader.warnings[1], "Dale"), "a warning names Dale")
		local _ = Color3
	end)

	t.test("every NPC has a Talk prompt that streams with the model", function()
		local NPCService, NPCData = service()
		local map = fakeMap()
		NPCService.Init(map)
		for _, npc in ipairs(NPCData.All()) do
			local m = map:FindFirstChild(npc.id, true)
			local prompt = m:FindFirstChild("Talk")
			t.ok(prompt and prompt:IsA("ProximityPrompt"), npc.id .. " Talk")
			t.eq(prompt.Parent, m, "on the model, so an Atomic or Persistent stream includes it")
			t.eq(prompt.ActionText, "Talk")
			t.eq(prompt.ObjectText, npc.name)
			t.eq(prompt.RequiresLineOfSight, false)
			t.eq(prompt.ClickablePrompt, true)
			t.eq(prompt.HoldDuration, 0)
			t.eq(prompt.KeyboardKeyCode, Enum.KeyCode.E)
			t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonX)
			t.eq(prompt.MaxActivationDistance, NPCData.TalkDistance)
			t.ok(prompt.MaxActivationDistance > 0, npc.id)
			if npc.promptLift and npc.promptLift ~= 0 then
				t.eq(prompt.UIOffset, Vector2.new(0, npc.promptLift))
			end
			-- Not on the Torso: QuestUI clones that for Murph's portrait.
			t.eq(m.Torso:FindFirstChild("Talk"), nil)
		end
	end)

	t.test("a closed keeper lies under the counter, and the server locks the door", function()
		local NPCService, NPCData = service()
		local ShopHours = t.shared("ShopHoursLogic")
		local map, counters = fakeMap()
		NPCService.Init(map)
		NPCService.Apply(map, 22)
		local counter = counters.HearthAndHome
		local hazel = map.Townsfolk:FindFirstChild("Hazel")
		local root = hazel.PrimaryPart
		local top = counter.CFrame.Position.Y + counter.Size.Y / 2
		t.ok(
			root.CFrame.Position.Y + ShopHours.SleepBodyHalf <= top - ShopHours.SleepClearance + 1e-4,
			"Hazel is at least a stud under the counter top"
		)
		t.ok(math.abs(root.CFrame.UpVector.Y) < 0.05, "she is lying, not standing")
		local rel = counter.CFrame:PointToObjectSpace(root.CFrame.Position)
		t.ok(rel.Z > counter.Size.Z / 2, "she is behind the counter")
		local zzz = counter:FindFirstChild("Zzz")
		t.eq(zzz.MaxDistance, ShopHours.ZzzMaxDistance)
		t.ok(zzz.StudsOffset.Y >= counter.Size.Y / 2 + ShopHours.ZzzAbove - 1e-3, "Zzz is 3 studs above the counter")
		t.eq(hazel:GetAttribute("Asleep"), true)
		t.ok(string.find(hazel:GetAttribute("SleepLine"), "7:00", 1, true) ~= nil, hazel:GetAttribute("SleepLine"))
		t.eq(map.HearthAndHome:GetAttribute("DoorLocked"), true)
		local door = counter:FindFirstChild("ShopDoor")
		t.eq(door.Enabled, true)
		t.eq(door.KeyboardKeyCode, Enum.KeyCode.F)
		t.eq(door.GamepadKeyCode, Enum.KeyCode.ButtonY)
		local tink = map.Townsfolk:FindFirstChild("Tink")
		t.eq(tink:GetAttribute("Asleep"), true, "the Tool Shed keeper sleeps at night too")
		t.eq(map.ToolShed:GetAttribute("DoorLocked"), true)
		t.ok(counters.ToolShed:FindFirstChild("Zzz") ~= nil)

		local look = counter.CFrame.LookVector
		local function person(at)
			local hrp = Instance.new("Part")
			hrp.Name = "HumanoidRootPart"
			hrp.CFrame = CFrame.new(at)
			local char = Instance.new("Model")
			hrp.Parent = char
			return { Character = char }
		end
		local at = counter.CFrame.Position
		NPCService.OnDoor(person(at + look * 40), map.HearthAndHome, "HearthAndHome", 22)
		t.eq(map.HearthAndHome:GetAttribute("DoorLocked"), true, "outside cannot open a closed door")
		NPCService.OnDoor(person(at - look * 6), map.HearthAndHome, "HearthAndHome", 22)
		t.eq(map.HearthAndHome:GetAttribute("DoorLocked"), false, "inside can hold the door")

		NPCService.Apply(map, 8)
		t.eq(hazel:GetAttribute("Asleep"), false)
		t.eq(map.HearthAndHome:GetAttribute("DoorLocked"), false)
		t.eq(counter:FindFirstChild("Zzz"), nil)
		local home = NPCData.BehindCounter(counter.CFrame, counter.Size)
		local feet = root.CFrame.Position.Y - hazel:GetAttribute("RootHeight")
		t.ok(math.abs(feet - home.Position.Y) < 1e-2, "she stands up again at open")
	end)

	t.test("a closed shop's real door blocks the way in, shows the opening time, and opens at opening time", function()
		local NPCService = service()
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local map = fakeMap()
		local doors, counters = {}, {}
		-- The real shops (their counters are axis-aligned, their doors as built).
		for _, kind in ipairs({ "ToolShed", "Dealership", "HearthAndHome" }) do
			map[kind]:Destroy()
			local model = BuildingArt.Shop(kind, kind, Color3.fromRGB(120, 90, 60))
			model.Name = kind
			model.Parent = map
			counters[kind] = model.Counter
			doors[kind] = model.ShopDoor
		end
		NPCService.Init(map)
		NPCService.Apply(map, 12)
		for kind, door in pairs(doors) do
			t.eq(door.DoorBlock.CanCollide, false, kind .. " is open at noon: players walk in")
			t.eq(map[kind]:GetAttribute("DoorOpen"), true)
			t.eq(door.DoorClosedSign.Transparency, 1, kind .. " no sign while open")
		end
		NPCService.Apply(map, 22)
		t.eq(doors.HearthAndHome.DoorBlock.CanCollide, true, "Hearth & Home is shut at 10 PM")
		t.eq(doors.Dealership.DoorBlock.CanCollide, true, "so is the Dealership")
		t.eq(doors.ToolShed.DoorBlock.CanCollide, true, "the Tool Shed is shut at 10 PM")
		t.eq(map.HearthAndHome:GetAttribute("DoorOpen"), false)
		t.eq(map.HearthAndHome:GetAttribute("DoorLocked"), true)
		local sign = doors.HearthAndHome.DoorClosedSign
		t.eq(sign.Transparency, 0)
		t.eq(sign.ClosedGui.Enabled, true)
		t.eq(sign.ClosedGui.ClosedText.Text, "Closed - opens at 7 AM")
		-- Someone outside cannot open it; someone inside is let out.
		local counter = counters.HearthAndHome
		local look = counter.CFrame.LookVector
		local function person(at)
			local hrp = Instance.new("Part")
			hrp.Name = "HumanoidRootPart"
			hrp.CFrame = CFrame.new(at)
			local char = Instance.new("Model")
			hrp.Parent = char
			return { Character = char }
		end
		local at = counter.CFrame.Position
		NPCService.OnDoor(person(at + look * 40), map.HearthAndHome, "HearthAndHome", 22)
		t.eq(doors.HearthAndHome.DoorBlock.CanCollide, true, "outside cannot open it")
		NPCService.OnDoor(person(at - look * 6), map.HearthAndHome, "HearthAndHome", 22)
		t.eq(doors.HearthAndHome.DoorBlock.CanCollide, false, "inside, the door lets you out")
		t.eq(map.HearthAndHome:GetAttribute("DoorOpen"), true)
		-- At opening time it opens for everyone, and the sign goes.
		NPCService.Apply(map, 7)
		t.eq(doors.HearthAndHome.DoorBlock.CanCollide, false)
		t.eq(sign.Transparency, 1)
		t.eq(sign.ClosedGui.Enabled, false)
		t.eq(doors.Dealership.DoorBlock.CanCollide, false, "the Dealership opens at 7 too")
	end)

	t.test("Old Tolly and Cap'n Moss stand on the ground out in the world, not at y = 0", function()
		local NPCService, NPCData = service()
		local map = fakeMap()
		NPCService.Init(map)
		local TerrainGen = t.shared("World/TerrainGen")
		for _, id in ipairs({ "OldTolly", "CapnMoss" }) do
			local npc = NPCData.Get(id)
			local m = map.Townsfolk:FindFirstChild(id)
			t.ok(m, id .. " is built")
			local p = npc.spot.position
			local feet = m.PrimaryPart.CFrame.Position.Y - m:GetAttribute("RootHeight")
			t.ok(math.abs(feet - (TerrainGen.HeightAt(p.X, p.Z) + npc.spot.ground)) < 1e-3, id .. "'s feet")
			t.ok(m:FindFirstChild("Talk"), id .. " has Talk")
		end
	end)

	-- LOAD-02. Studio's log of 7 October 2026: NPCService.Init took 60.00 s,
	-- because every townsperson's meshes (nine of them, 17 pieces each) were
	-- loaded one at a time inside the build. Now the meshes load side by side
	-- up front, Murph is built at once and the rest are steps of the deferred
	-- build, so the server's Init never waits on them.
	t.test("with a deferred queue: Murph now, everyone else as a tier-1 step with a position", function()
		local NPCService, NPCData = service()
		local map = fakeMap()
		local steps, built, done = {}, {}, 0
		NPCService.Init(map, {
			defer = function(step)
				table.insert(steps, step)
			end,
			onBuilt = function(id)
				table.insert(built, id)
			end,
			onDone = function()
				done += 1
			end,
		})
		t.ok(map:FindFirstChild("Murph"), "Murph is in at once")
		t.eq(built, { "Murph" })
		t.eq(done, 0, "not done: the others are still queued")
		t.eq(#steps, #NPCData.All() - 1, "one step per other townsperson")
		local folder = map:FindFirstChild("Townsfolk")
		t.eq(#folder:GetChildren(), 0, "nobody else yet")
		for _, step in ipairs(steps) do
			t.eq(step.tier, 1, step.name .. " is tier 1 (seen soon)")
			t.ok(step.at and type(step.at.x) == "number" and type(step.at.z) == "number", step.name .. " has a spot")
			t.eq(string.find(step.name, "NPC ", 1, true), 1)
		end
		-- Run the steps in a different order than they were given: all get built.
		for i = #steps, 1, -1 do
			steps[i].run(function()
				return false
			end)
		end
		t.eq(done, 1, "onDone fires once, after the last")
		t.eq(#built, #NPCData.All())
		for _, npc in ipairs(NPCData.All()) do
			if npc.id ~= "Murph" then
				local m = folder:FindFirstChild(npc.id)
				t.ok(m, npc.id .. " was built by its step")
				t.eq(m.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
				t.ok(m:FindFirstChild("Talk"), npc.id .. " has Talk")
			end
		end
	end)

	t.test("every mesh is asked for once, side by side up front: building the townsfolk finds them cached", function()
		local NPCService, _, loader = service()
		local MeshKit = loader:shared("Art/MeshKit")
		local asked = {}
		MeshKit.Reset()
		MeshKit.Override = function(id)
			asked[id] = (asked[id] or 0) + 1
			return roblox.Instance.new("MeshPart")
		end
		local map = fakeMap()
		NPCService.Init(map)
		MeshKit.Override = nil
		local count, twice = 0, 0
		for _, n in pairs(asked) do
			count += 1
			if n > 1 then
				twice += 1
			end
		end
		t.ok(count >= 100, count .. " distinct NPC meshes were loaded")
		t.eq(twice, 0, "no mesh was loaded twice")
		MeshKit.Reset()
	end)

	t.test("a townsperson built late (Old Hank) is reported the moment he is in", function()
		local NPCService, NPCData = service()
		local map = fakeMap()
		local steps, built = {}, {}
		NPCService.Init(map, {
			defer = function(step)
				table.insert(steps, step)
			end,
			onBuilt = function(id)
				table.insert(built, id)
			end,
		})
		local PlotSalesmanData = t.shared("PlotSalesmanData")
		t.ok(NPCData.Get(PlotSalesmanData.Id), "the salesman is a townsperson")
		local hank
		for _, step in ipairs(steps) do
			if step.name == "NPC " .. PlotSalesmanData.Id then
				hank = step
			end
		end
		t.ok(hank, "Old Hank has his own step")
		t.eq(built, { "Murph" })
		hank.run(function()
			return false
		end)
		t.eq(built, { "Murph", PlotSalesmanData.Id }, "GameServer hooks his Talk prompt on this")
		t.ok(map.Townsfolk:FindFirstChild(PlotSalesmanData.Id):FindFirstChild("Talk"))
	end)
end
