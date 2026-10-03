--!nocheck
-- TruckLoad (V2_PLAN.md §4b, §4d; M1.6): loose wood riding on truck beds.
-- Real TruckArt trucks and real GrabService and TruckLoad, over fakes for
-- the world: the clock, players and their characters, the box query (any
-- queryable part in the Wood folder near the box), PhysicsService and
-- network ownership (GrabService.Physics swapped for a recorder: Lune has
-- no physics). It proves:
--   * bed membership: a piece rides when its centre is in a BedZone;
--   * the HUD's BedVolume / BedValue / BedRoom / BedLength;
--   * the driver's device simulates the load while they drive, hands it
--     back as the truck settles and parks; a piece that falls off keeps
--     its driver a moment; teleported cargo is put back; held pieces are
--     never taken;
--   * nobody else can grab your load (GrabService's bedOwner);
--   * BedAutoWeld off by default, on in Studio with Tune_BedAutoWeld = 1,
--     unwelded by a grab or by turning it off;
--   * saving (own and unowned pieces, most valuable first, capped) and the
--     round trip through leaving and rejoining, in town and out of it;
--   * Send truck home: in town the load comes along, out of town it stays;
--   * onLoaded once per piece of yours on your own bed; bed friction.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local function signal()
		local s = {}
		function s:Connect()
			return { Disconnect = function() end }
		end
		return s
	end

	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-3)
	end
	local function sameCF(a, b, eps)
		return near(a.Position, b.Position, eps or 0.01)
			and near(a.LookVector, b.LookVector, 0.002)
			and near(a.UpVector, b.UpVector, 0.002)
	end

	local function setup(options)
		options = options or {}
		local w = {
			clock = 100,
			attrs = { CoreLoopActive = 2 },
			studio = options.studio == true,
			owners = {}, -- [part] = player, nil (the server) or "auto"
			ownerCalls = {},
			autos = {},
			toasts = {},
			forgotten = {},
			moved = {},
			loaded = {},
			players = {},
			trucks = {},
			profiles = {},
		}
		local fakeOs = setmetatable({
			clock = function()
				return w.clock
			end,
		}, { __index = os })
		local fakeWorkspace = {
			GetAttribute = function(_, name)
				return w.attrs[name]
			end,
		}
		local loader = t.loader({
			services = {
				Players = {
					PlayerAdded = signal(),
					PlayerRemoving = signal(),
					GetPlayers = function()
						return w.players
					end,
					GetPlayerByUserId = function(_, userId)
						for _, p in ipairs(w.players) do
							if p.UserId == userId then
								return p
							end
						end
						return nil
					end,
				},
				PhysicsService = {
					IsCollisionGroupRegistered = function()
						return true
					end,
					RegisterCollisionGroup = function() end,
					CollisionGroupSetCollidable = function() end,
				},
				RunService = {
					IsStudio = function()
						return w.studio
					end,
					Heartbeat = signal(),
				},
			},
			globals = { os = fakeOs, workspace = fakeWorkspace },
		})
		local GrabService = loader:server("GrabService")
		local TruckLoad = loader:server("TruckLoad")
		w.GrabService, w.TruckLoad = GrabService, TruckLoad
		w.ItemCatalog = loader:shared("ItemCatalog")
		w.TruckLayout = loader:shared("TruckLayout")
		w.TruckArt = loader:shared("Art/TruckArt")
		w.SellLogic = loader:shared("SellLogic")
		w.GameConfig = loader:shared("GameConfig")
		w.GrabLogic = loader:shared("GrabLogic")
		GrabService.Physics.SetOwner = function(part, player)
			table.insert(w.ownerCalls, { part = part, player = player })
			w.owners[part] = player
			return true
		end
		GrabService.Physics.SetAuto = function(part)
			table.insert(w.autos, part)
			w.owners[part] = "auto"
		end
		local world = Instance.new("Folder")
		w.world = world
		local folder = Instance.new("Folder")
		folder.Name = "Wood"
		folder.Parent = world
		w.folder = folder

		-- Any queryable part in the Wood folder whose middle is within its
		-- own reach of the box (the engine's box query, near enough).
		local function partsInBox(cf, size)
			local out = {}
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BasePart") and d.CanQuery then
					local p = cf:PointToObjectSpace(d.CFrame.Position)
					local r = d.Size.Magnitude / 2
					if
						math.abs(p.X) <= size.X / 2 + r
						and math.abs(p.Y) <= size.Y / 2 + r
						and math.abs(p.Z) <= size.Z / 2 + r
					then
						table.insert(out, d)
					end
				end
			end
			return out
		end
		TruckLoad.Hooks.onLoaded = function(player, piece, volume)
			table.insert(w.loaded, { player = player, piece = piece, volume = volume })
		end
		TruckLoad._use({
			woodFolder = folder,
			truckOf = function(player)
				return w.trucks[player]
			end,
			profileOf = function(player)
				return w.profiles[player]
			end,
			notify = function(player, message)
				table.insert(w.toasts, { player = player, message = message })
			end,
			forget = function(model)
				GrabService.Unregister(model)
				table.insert(w.forgotten, model)
			end,
			moved = function(model)
				table.insert(w.moved, model)
			end,
			partsInBox = partsInBox,
			now = function()
				return w.clock
			end,
			players = function()
				return w.players
			end,
			isStudio = function()
				return w.studio
			end,
		})

		-- A player (online, with a save) whose character stands at `at`.
		function w.player(id, at)
			local attributes = {}
			local hrp = {
				Position = at or Vector3.new(0, 3, 0),
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
			local humanoid = { Health = 100, SeatPart = nil }
			local character = {
				FindFirstChild = function(_, name)
					return if name == "HumanoidRootPart" then hrp else nil
				end,
				FindFirstChildOfClass = function(_, class)
					return if class == "Humanoid" then humanoid else nil
				end,
			}
			local p = {
				UserId = id,
				Name = "Player" .. id,
				DisplayName = "Pal" .. id,
				Character = character,
				hrp = hrp,
				attributes = attributes,
			}
			function p:SetAttribute(name, value)
				attributes[name] = value
			end
			function p:GetAttribute(name)
				return attributes[name]
			end
			table.insert(w.players, p)
			w.profiles[p] = { truckLoad = {}, cash = 0 }
			return p
		end

		-- `player`'s truck (and trailer), rigged and parked at `cf`.
		function w.truck(player, truckId, trailerId, cf)
			local def = w.ItemCatalog.GetTruck(truckId or "Rustbucket")
			local layout = w.TruckLayout.For(def)
			local trailer = if trailerId then w.ItemCatalog.GetTrailer(trailerId) else nil
			local tl = if trailer then w.TruckLayout.ForTrailer(trailer, layout) else nil
			local model = w.TruckArt.Build(def, layout, trailer, tl)
			w.TruckArt.Rig(model)
			model:PivotTo(cf or CFrame.new(0, w.TruckLayout.ChassisY, 0))
			model.Parent = world
			if player then
				w.trucks[player] = model
			end
			return model
		end

		-- A 2 x `length` x 2 log (its length is its Y) of `woodId`, at `cf`,
		-- cut faces on both ends, registered: { model, root, record }.
		function w.piece(cf, over)
			over = over or {}
			local length = over.length or 6
			local thick = over.thick or 1.6
			local model = Instance.new("Model")
			model.Name = "Wood_" .. (over.name or tostring(#folder:GetChildren() + 1))
			local section = Instance.new("Part")
			section.Name = "Section"
			section.Size = Vector3.new(thick, length, thick)
			section.CFrame = cf
			section.Parent = model
			model.PrimaryPart = section
			for _, side in ipairs({ 1, -1 }) do
				local face = Instance.new("Part")
				face.Name = "CutFace"
				face.Size = Vector3.new(thick * 0.86, 0.06, thick * 0.86)
				face.CFrame = cf * CFrame.new(0, side * (length / 2 + 0.03), 0)
				face.Massless = true
				face.CanCollide = false
				face.CanQuery = false
				face.Parent = model
			end
			local woodId = over.woodId or "oak"
			local u = w.GameConfig.WoodUnit
			local volume = thick * thick * length / (u * u * u)
			model:AddTag("Wood")
			model:SetAttribute("Uid", model.Name)
			model:SetAttribute("Owner", over.ownerId or 0)
			model:SetAttribute("WoodId", woodId)
			model:SetAttribute("Kind", "log")
			model:SetAttribute("Volume", volume)
			model:SetAttribute("HeldBy", 0)
			if over.figure then
				model:SetAttribute("Figure", over.figure)
			end
			if over.boost then
				model:SetAttribute("Boost", over.boost)
			end
			model.Parent = folder
			local record = { model = model, ownerId = over.ownerId or 0, createdAt = w.clock - 60 }
			GrabService.Register(record)
			return { model = model, root = section, record = record, volume = volume }
		end

		-- A place on a truck's bed (`bedName`), `at` along it (studs from its
		-- middle), the log lying along the bed.
		function w.onBed(truck, bedName, at, height)
			local bed = truck:FindFirstChild(bedName or "BedFloor")
			return bed.CFrame * CFrame.new(0, 0.25 + (height or 0.8), at or 0) * CFrame.Angles(math.pi / 2, 0, 0)
		end

		function w.tick(dt)
			w.clock += dt or 0
			TruckLoad.Tick()
		end
		return w
	end

	t.test("a piece rides when its centre is in a BedZone; hanging mostly off, it doesn't", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Rustbucket", "PonyTrailer")
		local onBed = w.piece(w.onBed(truck, "BedFloor"), { ownerId = 1 })
		local onTrailer = w.piece(w.onBed(truck, "TrailerBed", 1), { ownerId = 1 })
		-- 6 long, its middle 1 stud past the tailgate: overlaps the zone but
		-- its centre is out.
		local tailgate = truck:FindFirstChild("BedFloor").Size.Z / 2
		local hanging = w.piece(w.onBed(truck, "BedFloor", tailgate + 1), { ownerId = 1 })
		local beside = w.piece(truck:GetPivot() * CFrame.new(8, 1, 0), { ownerId = 1 })
		w.tick()
		t.eq(w.TruckLoad.LoadCount(truck), 2)
		local on = w.TruckLoad.PiecesOn(dale)
		t.eq(#on, 2)
		t.ok(table.find(on, onBed.model) and table.find(on, onTrailer.model), "the truck's bed and the trailer's")
		t.eq(w.TruckLoad.BedOwner(onBed.record), dale)
		t.eq(w.TruckLoad.BedOwner(onTrailer.record), dale)
		t.eq(w.TruckLoad.BedOwner(hanging.record), nil)
		t.eq(w.TruckLoad.BedOwner(beside.record), nil)
		-- The centre test is by volume over solid parts: cut faces don't count.
		local centre = w.TruckLoad.Centre(onBed.model)
		t.ok(near(centre, onBed.root.CFrame.Position), "centre of the section")
	end)

	t.test("the HUD's numbers on the truck and its owner: BedVolume, BedValue, BedRoom, BedLength", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Rustbucket", "PonyTrailer")
		local a = w.piece(w.onBed(truck, "BedFloor"), { ownerId = 1 })
		local b = w.piece(w.onBed(truck, "TrailerBed"), { ownerId = 1, woodId = "pine", figure = "burl" })
		w.tick()
		local value = w.SellLogic.PieceValue("oak", "log", a.volume)
			+ w.SellLogic.PieceValue("pine", "log", b.volume, "burl")
		local volume = a.volume + b.volume
		for _, holder in ipairs({ truck, dale }) do
			t.ok(math.abs(holder:GetAttribute("BedVolume") - volume) < 0.051, "BedVolume")
			t.eq(holder:GetAttribute("BedValue"), math.floor(value + 0.5))
		end
		local room = 0
		for _, z in ipairs(w.TruckArt.BedZones(truck)) do
			room += z.zone:GetAttribute("Room")
		end
		t.ok(math.abs(truck:GetAttribute("BedRoom") - room) < 0.051, "BedRoom: both beds' u³ a trip")
		t.eq(dale:GetAttribute("BedLength"), 13, "the longest bed (Rustbucket 13, Pony 13: phase 12's 1.3x)")
		-- Sold off the bed: the numbers follow (once a second).
		b.model:Destroy()
		w.tick(0.5)
		t.ok(math.abs(dale:GetAttribute("BedVolume") - volume) < 0.051, "not yet: once a second")
		w.tick(0.6)
		t.ok(math.abs(dale:GetAttribute("BedVolume") - a.volume) < 0.051, "now")
	end)

	t.test("bed friction: every bed part of a player's truck grips at BedFriction (Tune in Studio)", function()
		local w = setup({ studio = true })
		local dale = w.player(1)
		local truck = w.truck(dale, "Flatbed")
		local floor = truck:FindFirstChild("BedFloor")
		t.eq(floor.CustomPhysicalProperties, nil, "built as v1 builds it")
		w.tick()
		t.eq(floor.CustomPhysicalProperties.Friction, w.GameConfig.BedFriction)
		for _, d in ipairs(truck:GetDescendants()) do
			if d.Name == "Stake" then
				t.eq(d.CustomPhysicalProperties.Friction, w.GameConfig.BedFriction, "stakes grip too")
			end
		end
		w.attrs.Tune_BedFriction = 0.5
		w.tick(1)
		t.ok(math.abs(floor.CustomPhysicalProperties.Friction - 0.5) < 1e-6, "retuned live in Studio")
	end)

	t.test("driving: the driver's device simulates the load; settling: the server's; parked: automatic", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Pickup")
		local chassis = truck.PrimaryPart
		local a = w.piece(w.onBed(truck, "BedFloor", -2), { ownerId = 1 })
		local b = w.piece(w.onBed(truck, "BedFloor", 2), { ownerId = 0 })
		w.tick()
		t.eq(#w.ownerCalls, 0, "parked: nobody's load is handed out")
		-- Dale sits down: VehicleService has given him the chassis and unanchored it.
		chassis.Anchored = false
		w.TruckLoad.OnDriverChanged(truck, dale)
		t.eq(w.owners[a.root], dale, "at once")
		t.eq(w.owners[b.root], dale, "unowned wood on his bed too")
		-- Driving along: the truck and its load move together, 5 studs in a
		-- quarter second (20 studs/s, inside the speed check).
		local before = truck:GetPivot()
		truck:PivotTo(before * CFrame.new(0, 0, -5))
		local delta = truck:GetPivot() * before:Inverse()
		for _, p in ipairs({ a, b }) do
			p.model:PivotTo(delta * p.model:GetPivot())
		end
		w.tick(0.25)
		t.eq(w.owners[a.root], dale, "still his")
		-- b slides off the side on a bend.
		b.model:PivotTo(b.model:GetPivot() + Vector3.new(6, -2, 0))
		w.tick(0.25)
		t.eq(w.owners[b.root], dale, "fallen off: still his a moment")
		w.tick(w.GameConfig.ReleaseKeepOwnerSec)
		t.eq(w.owners[b.root], "auto", "then automatic")
		t.eq(w.owners[a.root], dale)
		-- He gets out: the truck settles on the server, the load with it.
		w.TruckLoad.OnDriverChanged(truck, nil)
		t.eq(w.owners[a.root], nil, "the server's while it settles")
		w.tick(1)
		t.eq(w.owners[a.root], nil, "still settling")
		chassis.Anchored = true -- parked
		w.tick(1)
		t.eq(w.owners[a.root], "auto", "parked: automatic")
	end)

	t.test("a held piece is never handed to the driver", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Pickup")
		local a = w.piece(w.onBed(truck), { ownerId = 1 })
		dale.hrp.Position = a.root.CFrame.Position + Vector3.new(0, 0, 4)
		t.ok(w.GrabService.Grab(dale, a.root, a.root.CFrame.Position))
		truck.PrimaryPart.Anchored = false
		local calls = #w.ownerCalls
		w.TruckLoad.OnDriverChanged(truck, dale)
		t.eq(#w.ownerCalls, calls, "GrabService has it")
	end)

	t.test("a log that fell off and was picked up stays with whoever holds it", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Pickup")
		local a = w.piece(w.onBed(truck), { ownerId = 0 })
		truck.PrimaryPart.Anchored = false
		w.TruckLoad.OnDriverChanged(truck, dale)
		t.eq(w.owners[a.root], dale)
		-- It slides off onto the road; someone picks it up straight away.
		a.model:PivotTo(a.model:GetPivot() + Vector3.new(7, -2, 0))
		w.tick(0.25)
		local at = a.root.CFrame.Position
		local passer = w.player(2, at + Vector3.new(0, 0, 4))
		t.ok(w.GrabService.Grab(passer, a.root, at), "off the bed: anyone's")
		t.eq(w.owners[a.root], passer)
		w.tick(w.GameConfig.ReleaseKeepOwnerSec + 0.25)
		t.eq(w.owners[a.root], passer, "TruckLoad doesn't take it back")
		w.TruckLoad.OnDriverChanged(truck, nil)
		truck.PrimaryPart.Anchored = true
		w.tick(1)
		t.eq(w.owners[a.root], passer, "nor when the truck parks")
	end)

	t.test("cargo teleported off the truck is put back, kept by the server a moment", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Pickup")
		local a = w.piece(w.onBed(truck), { ownerId = 1 })
		local home = a.root.CFrame
		truck.PrimaryPart.Anchored = false
		w.TruckLoad.OnDriverChanged(truck, dale)
		-- An exploiter's device moves it onto the sell pad in a quarter second.
		a.model:PivotTo(CFrame.new(0, 3, 82))
		w.tick(0.25)
		t.ok(sameCF(a.root.CFrame, home), "put back where it was last accepted")
		t.eq(w.owners[a.root], nil, "the server's")
		w.tick(0.25)
		t.eq(w.owners[a.root], nil, "not handed straight back")
		w.tick(1)
		t.eq(w.owners[a.root], dale, "the driver's again after PutBackHoldSec")
	end)

	t.test("nobody else can grab your load; you can", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Pickup")
		local a = w.piece(w.onBed(truck), { ownerId = 0 })
		local at = a.root.CFrame.Position
		local me = w.player(2, at + Vector3.new(0, 0, 4))
		dale.hrp.Position = at + Vector3.new(0, 0, -4)
		t.eq({ w.GrabService.Grab(me, a.root, at) }, { false, "bed" })
		t.ok(w.GrabService.Grab(dale, a.root, at), "Dale may")
	end)

	t.test("BedAutoWeld: off by default; Tune_BedAutoWeld = 1 in Studio welds resting wood; a grab lets go", function()
		t.eq(t.shared("GameConfig").BedAutoWeld, false)
		local w0 = setup()
		local AutoWeldOn = w0.TruckLoad.AutoWeldOn
		t.eq(AutoWeldOn(false, nil, true), false)
		t.eq(AutoWeldOn(false, 1, true), true)
		t.eq(AutoWeldOn(false, true, true), true)
		t.eq(AutoWeldOn(false, 1, false), false, "a live server ignores the attribute")
		t.eq(AutoWeldOn(true, 0, true), false)
		t.eq(AutoWeldOn(true, nil, false), true)
		-- Off: nothing welds.
		local d0 = w0.player(1)
		local truck0 = w0.truck(d0, "Pickup")
		local p0 = w0.piece(w0.onBed(truck0), { ownerId = 1 })
		w0.tick()
		w0.tick(1)
		w0.tick(1)
		t.eq(p0.root:FindFirstChild("BedWeld"), nil, "off by default")

		local w = setup({ studio = true })
		w.attrs.Tune_BedAutoWeld = 1
		local dale = w.player(1)
		local truck = w.truck(dale, "Pickup")
		local a = w.piece(w.onBed(truck, "BedFloor", -2), { ownerId = 1 })
		local sliding = w.piece(w.onBed(truck, "BedFloor", 2), { ownerId = 1 })
		w.tick()
		t.eq(a.root:FindFirstChild("BedWeld"), nil, "not yet: it has to rest a moment")
		sliding.model:PivotTo(sliding.model:GetPivot() * CFrame.new(0, 0, 0.1) * CFrame.new(1.5, 0, 0))
		w.tick(1)
		local weld = a.root:FindFirstChild("BedWeld")
		t.ok(weld and weld:IsA("WeldConstraint"), "resting: welded")
		t.eq(weld.Part0, truck:FindFirstChild("BedFloor"))
		t.eq(weld.Part1, a.root)
		t.eq(sliding.root:FindFirstChild("BedWeld"), nil, "a piece still sliding isn't")
		-- Driving: a welded piece is part of the truck, never handed out on its own.
		truck.PrimaryPart.Anchored = false
		w.TruckLoad.OnDriverChanged(truck, dale)
		t.eq(w.owners[a.root], nil, "rides with the truck")
		w.TruckLoad.OnDriverChanged(truck, nil)
		truck.PrimaryPart.Anchored = true
		-- A grab lets go of the bed first.
		dale.hrp.Position = a.root.CFrame.Position + Vector3.new(0, 0, 4)
		t.ok(w.GrabService.Grab(dale, a.root, a.root.CFrame.Position))
		t.eq(a.root:FindFirstChild("BedWeld"), nil, "unwelded on grab")
		t.eq(w.owners[a.root], dale)
		-- Turning it off lets go of the rest.
		w.tick(1)
		w.tick(1)
		t.ok(sliding.root:FindFirstChild("BedWeld"), "the other one rested and welded")
		w.attrs.Tune_BedAutoWeld = 0
		w.tick(1)
		t.eq(sliding.root:FindFirstChild("BedWeld"), nil, "off again: unwelded")
	end)

	t.test("saving: your own and unowned pieces, most valuable first; someone else's stays out", function()
		local w = setup()
		local dale = w.player(1)
		w.player(9)
		local truck = w.truck(dale, "Flatbed")
		w.piece(w.onBed(truck, "BedFloor", -6), { ownerId = 1, woodId = "oak", name = "a" })
		w.piece(w.onBed(truck, "BedFloor", 0), { ownerId = 0, woodId = "pine", name = "b", figure = "burl", boost = 2 })
		w.piece(w.onBed(truck, "BedFloor", 6), { ownerId = 9, woodId = "maple", name = "c" })
		w.tick()
		local saved = w.profiles[dale].truckLoad
		t.eq(#saved, 2)
		t.eq(saved[1].w, "pine", "the most valuable first")
		t.eq(saved[1].f, "burl")
		t.eq(saved[1].x, 2)
		t.eq(saved[2].w, "oak")
		t.eq(saved[1].bed, "BedFloor")
		t.eq(#saved[1].s, 1)
		t.eq(saved[1].s[1][10], 3, "cut faces on both ends")
		t.eq(w.TruckLoad.Save(dale), 2)
	end)

	t.test("saving is capped at MaxSavedPieces", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "LoggingRig")
		for i = 1, 45 do
			w.piece(w.onBed(truck, "BedFloor", -12 + (i % 24), 0.8 + (i // 24) * 1.7), { ownerId = 1, length = 1.5 })
		end
		w.tick()
		t.eq(#w.profiles[dale].truckLoad, w.GameConfig.MaxSavedPieces)
	end)

	t.test("leave and rejoin in town: the load is back on the bed, where it lay", function()
		local w = setup()
		local dale = w.player(1)
		w.player(9)
		local truck = w.truck(dale, "Rustbucket", "PonyTrailer", CFrame.new(40, 1.8, 30))
		local a =
			w.piece(w.onBed(truck, "BedFloor", -1.5) * CFrame.Angles(0, 0, 0.2), { ownerId = 1, figure = "curly" })
		local b = w.piece(w.onBed(truck, "TrailerBed", 1), { ownerId = 1, woodId = "pine", boost = 2 })
		local theirs = w.piece(w.onBed(truck, "BedFloor", 2), { ownerId = 9 })
		local floor, trailerBed = truck:FindFirstChild("BedFloor"), truck:FindFirstChild("TrailerBed")
		local relA = floor.CFrame:ToObjectSpace(a.root.CFrame)
		local relB = trailerBed.CFrame:ToObjectSpace(b.root.CFrame)
		w.tick()
		w.TruckLoad.PlayerRemoving(dale)
		t.eq(#w.profiles[dale].truckLoad, 2, "saved")
		t.eq(a.model.Parent, nil, "gone with him")
		t.eq(b.model.Parent, nil)
		t.ok(theirs.model.Parent ~= nil, "someone else's piece stays for them")
		t.eq(#w.forgotten, 2)
		-- Rejoining: a new truck in a new slot, a different way round.
		local profile = w.profiles[dale]
		local newTruck = w.truck(dale, "Rustbucket", "PonyTrailer", CFrame.new(-60, 1.8, 10) * CFrame.Angles(0, 1, 0))
		local onBuilt = w.TruckLoad.OnRebuild(dale, nil, true, CFrame.new(40, 1.8, 30))
		t.ok(onBuilt, "something to rebuild")
		onBuilt(newTruck)
		t.eq(profile.truckLoad, {}, "rebuilt: the save is refreshed as it rides")
		local nf, nt = newTruck:FindFirstChild("BedFloor"), newTruck:FindFirstChild("TrailerBed")
		local found = {}
		for _, model in ipairs(w.folder:GetChildren()) do
			if model ~= theirs.model then
				found[model:GetAttribute("WoodId")] = model
			end
		end
		local ra, rb = found.oak, found.pine
		t.ok(ra and rb, "both rebuilt")
		local lift = CFrame.new(0, w.TruckLoad.Lift, 0)
		t.ok(sameCF(nf.CFrame:ToObjectSpace(ra.PrimaryPart.CFrame), lift * relA), "the oak where it lay on the bed")
		t.ok(sameCF(nt.CFrame:ToObjectSpace(rb.PrimaryPart.CFrame), lift * relB), "the pine on the trailer")
		t.eq(ra:GetAttribute("Owner"), 1)
		t.eq(ra:GetAttribute("Figure"), "curly")
		t.eq(rb:GetAttribute("Boost"), 2)
		t.ok(math.abs(ra:GetAttribute("Volume") - a.volume) < 0.01, "same volume")
		t.ok(
			math.abs(rb:GetAttribute("Value") - w.SellLogic.PieceValue("pine", "log", b.volume, nil, 2)) < 0.02,
			"same worth"
		)
		t.ok(ra:HasTag("Wood"), "tagged Wood: the pad sells it")
		local faces = 0
		for _, d in ipairs(ra:GetChildren()) do
			if d.Name == "CutFace" then
				faces += 1
			end
		end
		t.eq(faces, 2, "with its cut faces")
		t.ok(w.GrabService.PieceOf(ra.PrimaryPart), "grabbable: GrabService knows it")
		-- On the bed it rides, and no tutorial event fires for it again.
		local loadedBefore = #w.loaded -- the first load, before he left
		w.tick(1)
		t.eq(w.TruckLoad.LoadCount(newTruck), 2)
		t.eq(#w.loaded, loadedBefore, "no woodLoaded for a rebuilt load")
		t.eq(#w.profiles[dale].truckLoad, 2, "saved again")
	end)

	t.test("rejoin out of town: the load waits on the ground where the truck stood, yours a while", function()
		local w = setup()
		local dale = w.player(1)
		w.profiles[dale].truckLoad = {
			{
				w = "oak",
				k = "log",
				bed = "BedFloor",
				at = { 0, 1.05, 0, math.pi / 2, 0, 0 },
				s = { { 1.6, 6, 1.6, 0, 0, 0, 0, 0, 0, 3 } },
			},
			"junk",
		}
		local truck = w.truck(dale, "Rustbucket")
		local stood = CFrame.new(900, 41.8, -700)
		local onBuilt = w.TruckLoad.OnRebuild(dale, nil, false, stood)
		onBuilt(truck)
		local model = w.folder:GetChildren()[1]
		t.ok(model, "rebuilt")
		local at = model.PrimaryPart.CFrame.Position
		t.ok(math.abs(at.X - 900) < 8 and math.abs(at.Z + 700) < 8, "where the truck stood")
		t.ok(at.Y > 41.8 and at.Y < 41.8 + 6, "just over the ground there: it settles")
		t.eq(w.toasts[#w.toasts].message, w.TruckLoad.LeftText)
		local record = w.GrabService.PieceOf(model.PrimaryPart)
		local wait = w.GrabLogic.GraceLeft({
			userId = 2,
			ownerId = 1,
			createdAt = record.createdAt,
			now = w.clock,
		})
		t.ok(math.abs(wait - w.GameConfig.LeftLoadGraceSec) < 1e-6, "others wait LeftLoadGraceSec")
	end)

	t.test("Send truck home: in town the load comes along onto the new truck; out of town it stays", function()
		local w = setup()
		local dale = w.player(1)
		local old = w.truck(dale, "Pickup", nil, CFrame.new(30, 1.8, 120))
		local a = w.piece(w.onBed(old, "BedFloor", 2) * CFrame.Angles(0, 0, 0.1), { ownerId = 1 })
		local rel = old:FindFirstChild("BedFloor").CFrame:ToObjectSpace(a.root.CFrame)
		w.tick()
		-- Out of town: nothing comes along, nothing moves; it's his alone a while.
		local before = a.root.CFrame
		t.eq(w.TruckLoad.OnRebuild(dale, old, false, old:GetPivot()), nil)
		t.ok(sameCF(a.root.CFrame, before), "left where it is")
		t.eq(w.toasts[#w.toasts].message, w.TruckLoad.LeftBehindText)
		local wait = w.GrabLogic.GraceLeft({ userId = 2, ownerId = 1, createdAt = a.record.createdAt, now = w.clock })
		t.ok(math.abs(wait - w.GameConfig.LeftLoadGraceSec) < 1e-6, "others wait LeftLoadGraceSec")
		-- In town.
		local carry = w.TruckLoad.OnRebuild(dale, old, true, old:GetPivot())
		t.ok(carry, "the load comes along")
		old:Destroy()
		local new = w.truck(dale, "Pickup", nil, CFrame.new(70, 1.8, 20) * CFrame.Angles(0, math.pi, 0))
		carry(new)
		local lift = CFrame.new(0, w.TruckLoad.Lift, 0)
		t.ok(sameCF(new:FindFirstChild("BedFloor").CFrame:ToObjectSpace(a.root.CFrame), lift * rel), "same place")
		t.eq(w.owners[a.root], "auto", "physics back to automatic")
		t.eq(w.moved[1], a.model, "the moved hook hears")
		w.tick(1)
		t.eq(w.TruckLoad.LoadCount(new), 1)
		t.eq(#w.loaded, 1, "carried pieces aren't loaded again")
		-- Switching to the Scout ATV (no bed): it stays where it was.
		local carry2 = w.TruckLoad.OnRebuild(dale, new, true, new:GetPivot())
		local at = a.root.CFrame
		local atv = w.truck(dale, "ScoutATV", nil, CFrame.new(0, 1.8, 0))
		carry2(atv)
		t.ok(sameCF(a.root.CFrame, at), "nowhere to put it")
	end)

	t.test("onLoaded: once per piece of yours on your own bed", function()
		local w = setup()
		local dale = w.player(1)
		local truck = w.truck(dale, "Pickup")
		local mine = w.piece(w.onBed(truck, "BedFloor", -2), { ownerId = 1 })
		w.piece(w.onBed(truck, "BedFloor", 2), { ownerId = 9 })
		w.tick()
		w.tick(1)
		w.tick(1)
		t.eq(#w.loaded, 1)
		t.eq(w.loaded[1].player, dale)
		t.eq(w.loaded[1].piece, mine.record)
		t.ok(math.abs(w.loaded[1].volume - mine.volume) < 1e-6)
		t.eq(mine.record.lastInteracted, w.clock, "wood on its owner's bed never ages")
	end)

	t.test("ClampOnto keeps a carried piece over a smaller bed, never under its floor", function()
		local w = setup()
		local size = Vector3.new(5, 4, 10)
		local rel = CFrame.new(4, -1, 9) * CFrame.Angles(0.3, 0, 0)
		local out = w.TruckLoad.ClampOnto(rel, size)
		t.ok(near(out.Position, Vector3.new(2.5, 0.25, 5)))
		t.ok(near(out.LookVector, rel.LookVector), "same turn")
		local inside = CFrame.new(1, 1, -2)
		t.ok(sameCF(w.TruckLoad.ClampOnto(inside, size), inside), "inside: unchanged")
	end)
end
