--!nocheck
-- The gondola ride (WLD-07): GondolaService on the server and
-- GondolaController on the rider's device, against fakes (the clock,
-- Heartbeat, the seat, network ownership, streaming). It proves what Studio
-- can't show us by reading code:
--   * the cabin is one rigid, unanchored body on two rigid constraints,
--     with mass only in its Floor, that collides with and touches nothing;
--     its body, and a rider seated in it, stay inside the box the clearance
--     specs (WorldPlan.spec) trace along every route;
--   * a ride charges the fee once, seats the rider, hands the cabin's
--     physics to the rider's device, writes the ride on the cabin, streams
--     the far station in first, and puts the rider in a collision group
--     that passes through other riders;
--   * the server never moves a cabin the rider's device has; it ends the
--     ride at rideSec by its own clock and lands the rider on the platform;
--     a jump ends it where they are; leaving or dying ends it with nothing
--     left behind; a rider never seated gets the fare back; two riders get
--     a cabin each; a cabin the server kept, it moves itself;
--   * the rider's device moves only its own cabin, to where the ride says
--     it is on the server's clock, and stops when the cabin goes.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local GondolaRide = t.shared("GondolaRide")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local BiomeData = t.shared("BiomeData")
	local GONDOLA = BiomeData.Get("sky").gondola

	-- Methods @lune/roblox lacks. They're shared by the whole test run, so
	-- they reach the running fake world through `current`, and each class
	-- can have a method registered only once: the fake workspace here is a
	-- Folder, because TreeFX.spec registers Workspace's GetServerTimeNow.
	local current
	roblox.implementMethod("Folder", "GetServerTimeNow", function()
		return current.now
	end)
	roblox.implementMethod("Seat", "Sit", function(seat, humanoid)
		if current.sitFails then
			return
		end
		seat.Occupant = humanoid
		local weld = Instance.new("Weld")
		weld.Name = "SeatWeld"
		weld.Parent = seat
	end)
	roblox.implementMethod("BasePart", "SetNetworkOwner", function(part, owner)
		table.insert(current.ownerCalls, { part = part, owner = owner })
		if not current.handoverFails then
			current.owners[part] = owner
		end
	end)
	roblox.implementMethod("BasePart", "GetNetworkOwner", function(part)
		return current.owners[part]
	end)
	roblox.implementMethod("Model", "AddPersistentPlayer", function(model, player)
		table.insert(current.persistent, { model = model, player = player })
	end)

	local function signal()
		local list = {}
		local s = { list = list }
		function s:Connect(fn)
			local entry = { fn = fn }
			table.insert(list, entry)
			return {
				Disconnect = function()
					local i = table.find(list, entry)
					if i then
						table.remove(list, i)
					end
				end,
			}
		end
		function s:Fire(...)
			for _, entry in ipairs(table.clone(list)) do
				entry.fn(...)
			end
		end
		return s
	end

	local function nearV(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-4)
	end

	-- The rider jumps out: the seat lets go of them. (@lune/roblox can't set
	-- a Ref property to nil, so an empty seat holds a stand-in; the server
	-- only asks whether the seat still holds its rider.)
	local function jumpOut(seat)
		seat.Occupant = Instance.new("Humanoid")
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end

	-- The real route up from town, as GondolaService builds it.
	local sky = WorldPlan.Sky()
	local function platform(cf)
		local station = BuildingArt.GondolaStation()
		Kit.placeAt(station, cf)
		return station.PrimaryPart
	end
	local topPlatform = platform(sky.gondolaTop)
	local townPlatform = platform(WorldPlan.Town().gondola)
	local townUp = WorldPlan.GondolaPath(
		sky,
		townPlatform.CFrame.Position,
		townPlatform.CFrame.ZVector,
		topPlatform.CFrame.Position
	)
	for i, v in ipairs(townUp) do
		townUp[i] = v + Vector3.new(0, 1, 0)
	end
	local LANDING = CFrame.new(topPlatform.CFrame.Position + Vector3.new(0, 4, 0))

	-- A fresh fake world with GondolaService (Init run) and its fakes.
	local function world(options)
		options = options or {}
		local w = {
			now = 1000,
			ownerCalls = {},
			owners = {},
			persistent = {},
			spent = {},
			refunds = {},
			toasts = {},
			deferred = {},
			spawnErrors = {},
			groupCalls = {},
			canPay = options.canPay ~= false,
			sitFails = options.sitFails,
			handoverFails = options.handoverFails,
		}
		current = w
		w.workspace = Instance.new("Folder")
		w.workspace.Name = "Workspace"
		w.heartbeat = signal()
		w.removing = signal()
		local registered = {}
		local loader = t.loader({
			mocks = {
				EconomyService = {
					SpendCash = function(player, amount)
						if not w.canPay then
							return false
						end
						table.insert(w.spent, { player = player, amount = amount })
						return true
					end,
					Refund = function(player, amount)
						table.insert(w.refunds, { player = player, amount = amount })
						return amount, 0
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
			services = {
				Players = { PlayerRemoving = w.removing },
				RunService = { Heartbeat = w.heartbeat },
				PhysicsService = {
					IsCollisionGroupRegistered = function(_, name)
						return registered[name] == true
					end,
					RegisterCollisionGroup = function(_, name)
						registered[name] = true
						table.insert(w.groupCalls, { "register", name })
					end,
					CollisionGroupSetCollidable = function(_, a, b, collides)
						table.insert(w.groupCalls, { "collidable", a, b, collides })
					end,
				},
			},
			globals = {
				workspace = w.workspace,
				task = {
					spawn = function(fn, ...)
						local ok, err = pcall(fn, ...)
						if not ok then
							table.insert(w.spawnErrors, tostring(err))
						end
					end,
					defer = function(fn, ...)
						table.insert(w.deferred, { fn = fn, args = { ... } })
					end,
				},
			},
		})
		w.G = loader:server("GondolaService")
		-- An empty map: the station setup (prompts) fails here and only here.
		w.G.Init(Instance.new("Folder"), function(player, message)
			table.insert(w.toasts, { player = player, message = message })
		end)
		function w.flush()
			local list = w.deferred
			w.deferred = {}
			for _, d in ipairs(list) do
				d.fn(table.unpack(d.args))
			end
		end
		function w.at(seconds) -- the server's clock, `seconds` after the start
			w.now = 1000 + seconds
			w.heartbeat:Fire(1 / 60)
		end
		return w
	end

	-- A player standing on a platform, with a character the way Roblox
	-- builds one (the parts that matter here).
	local userIds = 0
	local function player(name)
		userIds += 1
		local char = Instance.new("Model")
		char.Name = name
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Sit = false
		humanoid.Parent = char
		for _, partName in ipairs({ "HumanoidRootPart", "UpperTorso", "Head", "LeftFoot" }) do
			local p = Instance.new("Part")
			p.Name = partName
			p.CFrame = townPlatform.CFrame * CFrame.new(0, 3.5, 0)
			p.Parent = char
		end
		char.PrimaryPart = char:FindFirstChild("HumanoidRootPart")
		char.Parent = current.workspace
		local p = {
			Name = name,
			UserId = userIds,
			Character = char,
			Parent = true,
			attrs = {},
			streamed = {},
			humanoid = humanoid,
		}
		function p:SetAttribute(key, value)
			self.attrs[key] = value
		end
		function p:RequestStreamAroundAsync(position, timeout)
			table.insert(self.streamed, { position = position, timeout = timeout })
		end
		return p
	end

	local function cabins(w)
		local out = {}
		for _, child in ipairs(w.workspace:GetChildren()) do
			if child:HasTag(GondolaRide.Tag) then
				table.insert(out, child)
			end
		end
		return out
	end
	local function cabinOf(w, p)
		for _, cabin in ipairs(cabins(w)) do
			if cabin:GetAttribute("RiderId") == p.UserId then
				return cabin
			end
		end
		return nil
	end
	local function groupsOf(p)
		local out = {}
		for _, d in ipairs(p.Character:GetDescendants()) do
			if d:IsA("BasePart") then
				out[d.Name] = d.CollisionGroup
			end
		end
		return out
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
	-- The world-space corners of a part.
	local function corners(p)
		local out = {}
		local h = p.Size / 2
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					table.insert(out, p.CFrame * Vector3.new(h.X * x, h.Y * y, h.Z * z))
				end
			end
		end
		return out
	end

	-- The cabin box WorldPlan.spec traces along every route ("the gondola
	-- cabin never passes through a station, the main isle or the Skyroot",
	-- "the gondola cable never runs through a cabin"), about the pivot.
	local BOX = { half = 2.7, low = -0.2, high = 5.6 }
	local function inBox(v)
		return math.abs(v.X) <= BOX.half + 1e-6
			and math.abs(v.Z) <= BOX.half + 1e-6
			and v.Y >= BOX.low - 1e-6
			and v.Y <= BOX.high + 1e-6
	end

	t.test("the cabin is one rigid body that collides with and touches nothing", function()
		world()
		local cabin, seat, position, facing = current.G._buildCabin()
		local floor = cabin.PrimaryPart
		t.eq(floor.Name, "Floor")
		t.ok(nearV(floor.CFrame.Position, Vector3.zero), "the Floor's middle is the pivot")
		for _, p in ipairs(parts(cabin)) do
			t.eq(p.Anchored, false, p.Name .. " unanchored")
			t.eq(p.CanCollide, false, p.Name .. " collides with nothing")
			t.eq(p.CanTouch, false, p.Name .. " touches nothing")
			t.eq(p.Massless, p ~= floor, p.Name .. ": only the Floor has mass")
			if p ~= floor then
				local weld = p:FindFirstChildOfClass("WeldConstraint")
				t.ok(weld and weld.Part0 == floor and weld.Part1 == p, p.Name .. " welded to the Floor")
			end
		end
		t.ok(seat:IsA("Seat") and seat.Parent == cabin, "the seat")
		t.eq(position.ClassName, "AlignPosition")
		t.eq(position.Mode, roblox.Enum.PositionAlignmentMode.OneAttachment)
		t.ok(position.RigidityEnabled, "rigid: no sag under a rider")
		t.eq(position.Attachment0.Parent, floor)
		t.eq(position.Parent, floor)
		t.eq(position.Name, "RidePosition")
		t.eq(facing.ClassName, "AlignOrientation")
		t.eq(facing.Mode, roblox.Enum.OrientationAlignmentMode.OneAttachment)
		t.ok(facing.RigidityEnabled, "rigid: no swing")
		t.eq(facing.Attachment0, position.Attachment0)
		t.ok(nearV(position.Attachment0.CFrame.Position, Vector3.zero), "on the Floor's middle")
	end)

	t.test("the cabin's body, and a rider seated in it, stay inside the box the clearance specs trace", function()
		world()
		local cabin, seat = current.G._buildCabin()
		for _, p in ipairs(parts(cabin)) do
			if p.Name == "Hanger" then
				-- The rod up to the cable: thin, straight up from the roof.
				for _, c in ipairs(corners(p)) do
					t.ok(math.abs(c.X) <= 0.2 and math.abs(c.Z) <= 0.2 and c.Y >= 5.4, "the hanger at " .. tostring(c))
				end
			else
				for _, c in ipairs(corners(p)) do
					t.ok(inBox(c), p.Name .. " reaches out to " .. tostring(c))
				end
			end
		end
		-- A seated avatar's colliding body (root, torso, head) sits on the
		-- seat: no more than 4.3 studs above its top (a tall R15 or Rthro),
		-- 0.4 below it (the hips), and 1.5 studs from its middle any way.
		-- Limbs and accessories don't collide; carried logs and axes neither.
		local seatTop = seat.CFrame.Position.Y + seat.Size.Y / 2
		t.ok(math.abs(seatTop - 1.2) < 1e-4, "the seat's top is 1.2 above the pivot")
		for _, c in ipairs({
			Vector3.new(1.5, seatTop - 0.4, 1.5),
			Vector3.new(-1.5, seatTop + 4.3, -1.5),
			Vector3.new(1.5, seatTop + 4.3, -1.5),
			Vector3.new(-1.5, seatTop - 0.4, 1.5),
		}) do
			t.ok(inBox(c), "a seated rider reaches " .. tostring(c))
		end
	end)

	t.test("a ride: the fee once, the rider seated, the cabin on their device, the ride written on it", function()
		local w = world()
		local ann = player("Ann")
		w.G._ride(ann, townUp, LANDING)
		t.eq(#w.spent, 1)
		t.eq(w.spent[1].amount, GONDOLA.fee)
		t.eq(ann.attrs.Riding, true)
		local cabin = cabinOf(w, ann)
		t.ok(cabin, "a cabin in the workspace, tagged " .. GondolaRide.Tag)
		t.eq(GondolaRide.Read(cabin), { riderId = ann.UserId, start = 1000, rideSec = GONDOLA.rideSec, path = townUp })
		local floor = cabin.PrimaryPart
		local seat = cabin:FindFirstChild("Seat")
		t.eq(seat.Occupant, ann.humanoid, "seated")
		t.eq(w.owners[floor], ann, "its physics on the rider's device")
		t.eq(cabin.ModelStreamingMode, roblox.Enum.ModelStreamingMode.PersistentPerPlayer)
		t.eq(#w.persistent, 1)
		t.ok(w.persistent[1].model == cabin and w.persistent[1].player == ann, "always there on the rider's device")
		-- It starts at the station, facing along the route, and is held there.
		local turn = GondolaRide.Facing(townUp)
		t.ok(nearV(floor.CFrame.Position, townUp[1]), "at the start")
		t.ok(nearV(floor.CFrame.LookVector, turn.LookVector), "facing along the route")
		t.ok(nearV(floor:FindFirstChild("RidePosition").Position, townUp[1]), "held at the start")
		t.ok(nearV(floor:FindFirstChild("RideFacing").CFrame.LookVector, turn.LookVector), "held facing")
		-- The far station streams in first, then the route.
		t.ok(nearV(ann.streamed[1].position, townUp[#townUp]), "the far station first")
		t.eq(#ann.streamed, #GondolaRide.StreamPoints(townUp, 120))
		-- Riders pass through riders, and nothing else changes.
		t.eq(w.groupCalls, {
			{ "register", "GondolaRider" },
			{ "collidable", "GondolaRider", "GondolaRider", false },
		})
		t.eq(groupsOf(ann), {
			HumanoidRootPart = "GondolaRider",
			UpperTorso = "GondolaRider",
			Head = "GondolaRider",
			LeftFoot = "GondolaRider",
		})
		t.eq(#w.spawnErrors, 1, "only the station setup fails (no stations here)")
		t.ok(string.find(w.spawnErrors[1], "Missing station GondolaTown", 1, true), w.spawnErrors[1])
	end)

	t.test("the server never moves a cabin the rider's device has", function()
		local w = world()
		local ann = player("Ann")
		w.G._ride(ann, townUp, LANDING)
		local cabin = cabinOf(w, ann)
		local floor = cabin.PrimaryPart
		local pivot = floor.CFrame
		for _, at in ipairs({ 0.1, 5, 20, 39.9 }) do
			w.at(at)
			t.eq(floor.CFrame, pivot, "no CFrame from the server at " .. at)
			t.ok(nearV(floor:FindFirstChild("RidePosition").Position, townUp[1]), "no target from it at " .. at)
		end
		t.eq(cabin.Parent, w.workspace, "still riding just before rideSec")
		t.eq(#w.ownerCalls, 1, "handed over once")
	end)

	t.test("at rideSec the server ends the ride and lands the rider on the platform", function()
		local w = world()
		local ann = player("Ann")
		w.G._ride(ann, townUp, LANDING)
		local cabin = cabinOf(w, ann)
		local seat = cabin:FindFirstChild("Seat")
		w.at(GONDOLA.rideSec)
		t.eq(ann.humanoid.Sit, false, "stood up")
		t.eq(cabin.Parent, nil, "the cabin is gone")
		t.eq(#cabins(w), 0)
		t.eq(ann.attrs.Riding, false)
		t.eq(#w.heartbeat.list, 0, "the Heartbeat stopped")
		w.flush()
		t.ok(nearV(ann.Character.PrimaryPart.CFrame.Position, LANDING.Position), "on the platform")
		t.eq(groupsOf(ann).HumanoidRootPart, "Default", "collisions back")
		t.eq(#w.refunds, 0)
		t.eq(seat.Parent, nil)
		-- And can ride again.
		w.G._ride(ann, townUp, LANDING)
		t.eq(#w.spent, 2)
	end)

	t.test("jumping out mid-ride ends it there: no landing, no refund", function()
		local w = world()
		local ann = player("Ann")
		local before = ann.Character.PrimaryPart.CFrame
		w.G._ride(ann, townUp, LANDING)
		local cabin = cabinOf(w, ann)
		local seat = cabin:FindFirstChild("Seat")
		w.at(0.2)
		jumpOut(seat) -- the seat weld goes too
		w.at(0.3)
		t.eq(cabin.Parent, w.workspace, "still waiting out the boarding moment")
		w.at(12)
		t.eq(cabin.Parent, nil, "the cabin is gone")
		t.eq(ann.attrs.Riding, false)
		t.eq(#w.heartbeat.list, 0)
		w.flush()
		t.eq(ann.Character.PrimaryPart.CFrame, before, "not moved to the landing")
		t.eq(groupsOf(ann).UpperTorso, "Default")
		t.eq(#w.refunds, 0, "they were seated: no refund")
		t.eq(#w.toasts, 0)
	end)

	t.test("leaving or dying mid-ride leaves nothing behind", function()
		local w = world()
		local ann, ben = player("Ann"), player("Ben")
		w.G._ride(ann, townUp, LANDING)
		w.G._ride(ben, townUp, LANDING)
		w.at(5)
		ann.Parent = nil
		w.removing:Fire(ann)
		t.eq(cabinOf(w, ann), nil, "Ann's cabin went with her")
		t.eq(#w.heartbeat.list, 1, "her Heartbeat stopped")
		ben.humanoid.Health = 0
		w.at(6)
		t.eq(cabinOf(w, ben), nil, "Ben's went when he died")
		t.eq(#w.heartbeat.list, 0)
		t.eq(#w.refunds, 0)
	end)

	t.test("a rider who is never seated gets the fare back", function()
		local w = world({ sitFails = true })
		local ann = player("Ann")
		w.G._ride(ann, townUp, LANDING)
		w.at(0.2)
		t.eq(#cabins(w), 1, "waits out the boarding moment")
		w.at(0.6)
		t.eq(#cabins(w), 0)
		t.eq(#w.refunds, 1)
		t.ok(w.refunds[1].player == ann and w.refunds[1].amount == GONDOLA.fee, "the fare back")
		t.eq(#w.toasts, 1)
		t.eq(ann.attrs.Riding, false)
	end)

	t.test("no ride while riding, while seated, or without the fare", function()
		local w = world()
		local ann = player("Ann")
		w.G._ride(ann, townUp, LANDING)
		w.G._ride(ann, townUp, LANDING)
		t.eq(#w.spent, 1, "one ride at a time")
		t.eq(#cabins(w), 1)
		local ben = player("Ben")
		ben.humanoid.Sit = true
		ben.humanoid.SeatPart = Instance.new("Seat")
		w.G._ride(ben, townUp, LANDING)
		t.eq(#w.spent, 1, "not from a truck seat")
		local broke = world({ canPay = false })
		local cal = player("Cal")
		broke.G._ride(cal, townUp, LANDING)
		t.eq(#cabins(broke), 0)
		t.eq(broke.toasts[1].message, "A gondola ride costs $250.")
	end)

	t.test("two riders at once: a cabin each, and one jumping out leaves the other riding", function()
		local w = world()
		local ann, ben = player("Ann"), player("Ben")
		w.G._ride(ann, townUp, LANDING)
		w.at(3)
		w.G._ride(ben, townUp, LANDING)
		local a, b = cabinOf(w, ann), cabinOf(w, ben)
		t.ok(a and b and a ~= b, "a cabin each")
		t.eq(a:FindFirstChild("Seat").Occupant, ann.humanoid)
		t.eq(b:FindFirstChild("Seat").Occupant, ben.humanoid)
		t.eq(w.owners[b.PrimaryPart], ben)
		t.eq(groupsOf(ben).Head, "GondolaRider")
		jumpOut(a:FindFirstChild("Seat"))
		w.at(4)
		t.eq(cabinOf(w, ann), nil)
		t.eq(cabinOf(w, ben), b, "Ben rides on")
		w.at(3 + GONDOLA.rideSec)
		t.eq(cabinOf(w, ben), nil, "until his own rideSec")
		t.eq(ben.attrs.Riding, false)
	end)

	t.test("a cabin whose physics stays with the server, it moves itself, then hands the rider back", function()
		local w = world({ handoverFails = true })
		local ann = player("Ann")
		w.G._ride(ann, townUp, LANDING)
		local floor = cabinOf(w, ann).PrimaryPart
		local target = floor:FindFirstChild("RidePosition")
		for _, at in ipairs({ 1, 20, 33 }) do
			w.at(at)
			t.ok(nearV(target.Position, GondolaRide.Target(townUp, at, GONDOLA.rideSec)), "on the route at " .. at)
		end
		w.at(GONDOLA.rideSec)
		w.flush()
		local last = w.ownerCalls[#w.ownerCalls]
		t.eq(last.part, ann.Character.PrimaryPart, "the character...")
		t.eq(last.owner, ann, "...back to the rider's device")
		t.ok(nearV(ann.Character.PrimaryPart.CFrame.Position, LANDING.Position), "and landed")
	end)

	-- The rider's device: GondolaController with its own fakes.
	local function device(userId)
		local build = world().G._buildCabin -- the server's cabin
		local d = { clock = 500, serverNow = 2000, added = signal(), removed = signal(), steps = signal(), tagged = {} }
		local ws = Instance.new("Folder")
		ws.Name = "Workspace"
		current = { now = 0 }
		local loader = t.loader({
			services = {
				Players = { LocalPlayer = { UserId = userId } },
				RunService = { PreSimulation = d.steps },
				CollectionService = {
					GetTagged = function()
						return d.tagged
					end,
					GetInstanceAddedSignal = function()
						return d.added
					end,
					GetInstanceRemovedSignal = function()
						return d.removed
					end,
				},
			},
			globals = {
				workspace = ws,
				os = {
					clock = function()
						return d.clock
					end,
				},
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		d.C = loader:load("StarterPlayer/StarterPlayerScripts/GondolaController")
		d.workspace = ws
		-- A cabin the server built for `riderId`, set off at server time `start`.
		function d.cabin(riderId, start)
			local cabin = build()
			GondolaRide.Publish(cabin, { riderId = riderId, start = start, rideSec = GONDOLA.rideSec, path = townUp })
			cabin.Parent = ws
			return cabin
		end
		-- Steps the device's physics at its clock + `seconds`, the server's
		-- clock having moved on as much.
		function d.step(seconds)
			d.clock += seconds
			current.now = d.serverNow + (d.clock - 500)
			d.steps:Fire(1 / 60)
		end
		return d
	end

	t.test("the rider's device moves its own cabin along the route, by the server's clock", function()
		local d = device(7)
		local mine = d.cabin(7, 1990) -- set off 10 s ago, by the server's clock
		local theirs = d.cabin(8, 1990)
		current.now = 2000
		d.C.Start()
		d.added:Fire(mine)
		d.added:Fire(theirs)
		local target = mine.PrimaryPart:FindFirstChild("RidePosition")
		local other = theirs.PrimaryPart:FindFirstChild("RidePosition")
		local still = other.Position
		d.step(5) -- 15 s in
		t.ok(nearV(target.Position, GondolaRide.Target(townUp, 15, GONDOLA.rideSec)), "where the ride is at 15 s")
		d.step(1 / 60)
		t.ok(nearV(target.Position, GondolaRide.Target(townUp, 15 + 1 / 60, GONDOLA.rideSec)), "and a frame on")
		t.eq(other.Position, still, "another rider's cabin is theirs to move")
		-- The server's clock correcting itself mid-ride doesn't make it jump.
		current.now += 0.25
		d.clock += 1 / 60
		d.steps:Fire(1 / 60)
		t.ok(nearV(target.Position, GondolaRide.Target(townUp, 15 + 2 / 60, GONDOLA.rideSec)), "steady on os.clock")
		-- Gone: no more aiming (and no error).
		local last = target.Position
		mine.Parent = nil
		d.removed:Fire(mine)
		d.step(1)
		t.eq(target.Position, last)
	end)

	t.test("a cabin already there when the device starts is picked up too", function()
		local d = device(9)
		local mine = d.cabin(9, 2000)
		d.tagged = { mine }
		current.now = 2000
		d.C.Start()
		d.step(GONDOLA.rideSec + 5)
		t.ok(nearV(mine.PrimaryPart:FindFirstChild("RidePosition").Position, townUp[#townUp]), "held at the end")
	end)
end
