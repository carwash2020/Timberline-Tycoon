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
		for i, kind in ipairs({ "ToolShed", "Dealership", "HearthAndHome" }) do
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
		part(sell, "SellZone", Vector3.new(24, 12, 40), CFrame.new(0, 6, 82)) -- as MapBuilder builds it (phase 12)
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
				t.ok(math.abs(feet - (counter.CFrame.Position.Y - counter.Size.Y / 2)) < 1e-3, npc.id .. "'s feet")
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
		t.eq(tink:GetAttribute("Asleep"), false, "the Tool Shed does not sleep")
		t.eq(map.ToolShed:GetAttribute("DoorLocked"), false)
		t.eq(counters.ToolShed:FindFirstChild("Zzz"), nil)

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
end
