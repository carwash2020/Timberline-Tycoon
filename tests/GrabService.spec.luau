--!nocheck
-- GrabService (V2_PLAN.md §4a) against fakes: the clock, players and their
-- characters, PhysicsService, network ownership (Lune has no physics, so
-- GrabService.Physics is swapped for a recorder). Real Lune instances for
-- the wood. It proves:
--   * nothing happens under the v1 loop;
--   * a grab in reach hands the piece's physics to the holder, puts it in
--     WoodHeld (which doesn't collide with Players), marks HeldBy and
--     GrabPoint, and makes unowned wood the holder's;
--   * refusals: too far, a hit point off the part, held by someone else,
--     the cutter's 45 s, someone's truck bed, bad arguments, the rate;
--   * letting go puts groups and attributes back; the dropper keeps the
--     physics for ReleaseKeepOwnerSec, then it goes back to automatic
--     (unless someone grabs it first); leaving hands it back at once;
--   * forced release: death, sitting down, too far from the holder, the
--     piece sold, cut or gone; a teleported piece is put back, stopped,
--     and kept by the server for a moment.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local GameConfig = t.shared("GameConfig")

	local function signal()
		local list = {}
		local s = {}
		function s:Connect(fn)
			table.insert(list, fn)
			return { Disconnect = function() end }
		end
		function s:Fire(...)
			for _, fn in ipairs(list) do
				fn(...)
			end
		end
		return s
	end

	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-4)
	end

	local PIECE_AT = Vector3.new(0, 1, 0)

	local function setup(options)
		options = options or {}
		local now = 100
		local fakeOs = setmetatable({
			clock = function()
				return now
			end,
		}, { __index = os })
		local loop = options.loop or 2
		local fakeWorkspace = {
			GetAttribute = function(_, name)
				return if name == "CoreLoopActive" then loop else nil
			end,
		}
		local registered, collidable = {}, {}
		local physicsService = {
			IsCollisionGroupRegistered = function(_, name)
				return registered[name] == true
			end,
			RegisterCollisionGroup = function(_, name)
				registered[name] = true
			end,
			CollisionGroupSetCollidable = function(_, a, b, on)
				collidable[a .. "/" .. b] = on
			end,
		}
		local here = {} -- [UserId] = player: who's in the server (w.player adds them)
		local players = {
			PlayerAdded = signal(),
			PlayerRemoving = signal(),
			GetPlayers = function()
				return {}
			end,
			GetPlayerByUserId = function(_, userId)
				return here[userId]
			end,
		}
		local loader = t.loader({
			services = {
				Players = players,
				PhysicsService = physicsService,
				RunService = {
					IsStudio = function()
						return false
					end,
					Heartbeat = signal(),
				},
			},
			globals = { os = fakeOs, workspace = fakeWorkspace },
		})
		local GrabService = loader:server("GrabService")
		local realSetOwner = GrabService.Physics.SetOwner
		local w = {
			GrabService = GrabService,
			loader = loader,
			registered = registered,
			collidable = collidable,
			realSetOwner = realSetOwner,
			owners = {}, -- [part] = player, nil (the server) or "auto"
			ownerCalls = {},
			autos = {},
			toasts = {},
			handlers = {},
			released = {},
			grabbed = {},
		}
		GrabService.Physics.SetOwner = function(part, player)
			table.insert(w.ownerCalls, { part = part, player = player })
			w.owners[part] = player
			return not options.stuck
		end
		GrabService.Physics.SetAuto = function(part)
			table.insert(w.autos, part)
			w.owners[part] = "auto"
		end
		local function remote(name)
			return {
				OnServerEvent = {
					Connect = function(_, fn)
						w.handlers[name] = fn
					end,
				},
			}
		end
		GrabService.Init({ Grab = remote("Grab"), Release = remote("Release") }, function(player, message)
			table.insert(w.toasts, { player = player, message = message })
		end)
		GrabService.Hooks.onGrab = function(player, piece)
			table.insert(w.grabbed, { player = player, piece = piece })
		end
		GrabService.Hooks.onRelease = function(player, piece, reason)
			table.insert(w.released, { player = player, piece = piece, reason = reason })
		end

		local world = Instance.new("Folder")
		-- A 2 x 9 x 2 log lying along X at `at` (its length is its Y), with
		-- a cut face; registered with `over` merged into its record.
		function w.piece(at, over)
			local model = Instance.new("Model")
			model.Name = "Wood_test"
			local section = Instance.new("Part")
			section.Name = "Section"
			section.Size = Vector3.new(2, 9, 2)
			section.CFrame = CFrame.new(at or PIECE_AT) * CFrame.Angles(0, 0, math.rad(90))
			section.Parent = model
			local face = Instance.new("Part")
			face.Name = "CutFace"
			face.Parent = model
			model.PrimaryPart = section
			model:AddTag("Wood")
			model:SetAttribute("HeldBy", 0)
			model.Parent = world
			local record = { model = model, ownerId = 0, createdAt = now - 60 }
			for k, v in pairs(over or {}) do
				record[k] = v
			end
			GrabService.Register(record)
			return record, section, face
		end
		-- A player whose character stands at `at`.
		function w.player(id, at)
			local hrp = {
				Position = at or Vector3.new(0, 3, 5),
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
			local player = { UserId = id, Name = "Player" .. id, DisplayName = "Pal" .. id, Character = character }
			here[id] = player
			return player, hrp, humanoid
		end
		-- `id` leaves the server (their wood is no longer guarded as theirs).
		function w.leave(id)
			here[id] = nil
		end
		function w.wait(seconds)
			now += seconds
		end
		function w.watch()
			GrabService.Watch(now)
		end
		function w.now()
			return now
		end
		return w
	end

	-- A point on the log's top face, 3 studs from its middle.
	local HIT = PIECE_AT + Vector3.new(3, 1, 0)

	t.test("under the v1 loop nothing happens", function()
		local w = setup({ loop = 1 })
		local _, section = w.piece()
		local player = w.player(1)
		t.eq({ w.GrabService.Grab(player, section, HIT) }, { false, "off" })
		w.handlers.Grab(player, section, HIT)
		w.handlers.Release(player, section)
		t.eq(#w.ownerCalls, 0)
		t.eq(section.Parent:GetAttribute("HeldBy"), 0)
		t.eq(w.GrabService.Holding(player), nil)
	end)

	t.test("a grab in reach: the holder's device gets the physics, WoodHeld, HeldBy and GrabPoint", function()
		local w = setup()
		local record, section, face = w.piece()
		local model = record.model
		local player = w.player(7)
		w.handlers.Grab(player, section, HIT) -- through the remote
		t.eq(w.GrabService.Holding(player), model)
		t.eq(w.GrabService.HeldBy(model), player)
		t.eq(w.owners[section], player, "network ownership to the holder")
		t.eq(model:GetAttribute("HeldBy"), 7)
		t.ok(near(model:GetAttribute("GrabPoint"), section.CFrame:PointToObjectSpace(HIT)), "where it's held")
		t.eq(section.CollisionGroup, "WoodHeld")
		t.eq(face.CollisionGroup, "WoodHeld", "every part of it")
		t.ok(w.registered.WoodHeld and w.registered.Players, "both groups registered")
		t.eq(w.collidable["WoodHeld/Players"], false, "held wood passes through players")
		-- Unowned wood becomes the holder's; the record is the truth.
		t.eq(record.ownerId, 7)
		t.eq(model:GetAttribute("Owner"), 7)
		t.eq(record.lastHolderId, 7)
		t.eq(record.lastInteracted, w.now())
		t.eq(#w.grabbed, 1, "the onGrab hook hears")
		t.eq(#w.toasts, 0)
	end)

	t.test("too far: refused with a toast; a hit point off the part: refused", function()
		local w = setup()
		local _, section = w.piece()
		local far = w.player(1, Vector3.new(0, 3, 30))
		t.eq({ w.GrabService.Grab(far, section, HIT) }, { false, "far" })
		t.eq(w.toasts[1].message, "Too far away. Walk closer to grab it.")
		local close = w.player(2)
		t.eq({ w.GrabService.Grab(close, section, HIT + Vector3.new(0, 5, 0)) }, { false, "bad" }, "5 studs above it")
		t.eq(#w.ownerCalls, 0)
		-- Just off the face (the piece moved a little since): clamped onto it.
		t.ok(w.GrabService.Grab(close, section, HIT + Vector3.new(0, 1.5, 0)))
		t.ok(near(section.Parent:GetAttribute("GrabPoint"), section.CFrame:PointToObjectSpace(HIT)))
	end)

	t.test("already held by someone else: refused; the holder keeps it", function()
		local w = setup()
		local record, section = w.piece()
		local a = w.player(1)
		local b = w.player(2)
		t.ok(w.GrabService.Grab(a, section, HIT))
		t.eq({ w.GrabService.Grab(b, section, HIT) }, { false, "held" })
		t.eq(w.toasts[1].message, "Someone else is holding that.")
		t.eq(w.GrabService.HeldBy(record.model), a)
		t.eq(w.owners[section], a)
		t.eq(#w.ownerCalls, 1)
	end)

	t.test("someone else's wood is theirs while they're here, however old; once they've left, anyone's", function()
		local w = setup()
		local record, section = w.piece(nil, { ownerId = 1, createdAt = 100 - 10 })
		local owner = w.player(1)
		local other = w.player(2)
		t.eq({ w.GrabService.Grab(other, section, HIT) }, { false, "owned" })
		t.eq(w.toasts[1].message, "That's Pal1's wood.")
		w.wait(3600)
		t.eq({ w.GrabService.Grab(other, section, HIT) }, { false, "owned" }, "still theirs an hour on")
		t.ok(w.GrabService.Grab(owner, section, HIT), "the owner may")
		w.GrabService.Release(owner, section)
		w.leave(1)
		t.ok(w.GrabService.Grab(other, section, HIT), "an owner who left: anyone may")
		t.eq(record.ownerId, 1, "moving it never changes who's paid")
		t.eq(record.model:GetAttribute("Owner"), nil, "the attribute wasn't touched")
		t.eq(record.lastHolderId, 2)
	end)

	t.test("a fresh cut whose owner has left waits out the 45 s, then it's anyone's", function()
		local w = setup()
		local record, section = w.piece(nil, { ownerId = 1, createdAt = 100 - 10 })
		local other = w.player(2)
		-- (player 1 was never here: they've left)
		t.eq({ w.GrabService.Grab(other, section, HIT) }, { false, "grace" })
		t.eq(w.toasts[1].message, "Someone else just cut that. It's free to take in 35 seconds.")
		w.wait(GameConfig.PickupGraceSec)
		t.ok(w.GrabService.Grab(other, section, HIT), "after the grace anyone may")
		t.eq(record.ownerId, 1, "still the cutter's: they're paid for it")
	end)

	t.test("beforeHold runs once a grab has passed every check, before the physics is handed over (M1.6)", function()
		local w = setup()
		local record, section = w.piece(nil, { ownerId = 1, createdAt = 100 - 10 })
		local order = {}
		local setOwner = w.GrabService.Physics.SetOwner
		w.GrabService.Physics.SetOwner = function(part, player)
			table.insert(order, "owner")
			return setOwner(part, player)
		end
		w.GrabService.Hooks.beforeHold = function(player, piece)
			table.insert(order, { player = player, piece = piece })
		end
		local other = w.player(2)
		t.eq({ w.GrabService.Grab(other, section, HIT) }, { false, "grace" })
		t.eq(#order, 0, "a refused grab never reaches it")
		local owner = w.player(1)
		t.ok(w.GrabService.Grab(owner, section, HIT))
		t.eq(#order, 2)
		t.eq(order[1].player, owner)
		t.eq(order[1].piece, record)
		t.eq(order[2], "owner", "then the physics goes to the holder")
		w.GrabService.Hooks.beforeHold = nil
	end)

	t.test("an Elder's piece is anyone's at once; a truck bed is its owner's", function()
		local w = setup()
		local _, elderSection = w.piece(nil, { ownerId = 1, createdAt = 100, elder = true })
		local helper = w.player(2)
		t.ok(w.GrabService.Grab(helper, elderSection, HIT))
		local w2 = setup()
		local record, section = w2.piece(nil, { ownerId = 1, createdAt = 0 })
		local dale = w2.player(1)
		w2.GrabService.Hooks.bedOwner = function(piece)
			return if piece == record then dale else nil
		end
		local me = w2.player(2)
		t.eq({ w2.GrabService.Grab(me, section, HIT) }, { false, "bed" })
		t.eq(w2.toasts[1].message, "That's on Pal1's truck.")
		t.ok(w2.GrabService.Grab(dale, section, HIT), "Dale may")
	end)

	t.test("bad arguments are ignored (they can arrive as anything)", function()
		local w = setup()
		local _, section = w.piece()
		local player = w.player(1)
		local stranger = Instance.new("Part") -- not part of any known piece
		stranger.Parent = Instance.new("Model")
		local cases = {
			{ nil, HIT },
			{ section, nil },
			{ section, "here" },
			{ "Section", HIT },
			{ section, Vector3.new(0 / 0, 0, 0) },
			{ Instance.new("Folder"), HIT },
		}
		for i, case in ipairs(cases) do
			w.wait(1) -- a fresh rate budget
			t.eq({ w.GrabService.Grab(player, case[1], case[2]) }, { false, "bad" }, "case " .. i)
		end
		w.wait(1)
		t.eq({ w.GrabService.Grab(player, stranger, HIT) }, { false, "unknown" })
		t.eq(#w.ownerCalls, 0)
	end)

	t.test("rate: six grabs a second, the seventh is dropped", function()
		local w = setup()
		local _, section = w.piece()
		local player = w.player(1)
		for i = 1, 6 do
			t.ok(w.GrabService.Grab(player, section, HIT), "grab " .. i)
		end
		t.eq({ w.GrabService.Grab(player, section, HIT) }, { false, "rate" })
		t.eq(#w.ownerCalls, 1, "a new grip on the same piece doesn't hand it over again")
	end)

	t.test("a dead or sitting player can't grab; nor can anyone grab a piece the engine won't hand over", function()
		local w = setup()
		local _, section = w.piece()
		local player, _, humanoid = w.player(1)
		humanoid.SeatPart = {}
		t.eq({ w.GrabService.Grab(player, section, HIT) }, { false, "seated" })
		humanoid.SeatPart = nil
		humanoid.Health = 0
		w.wait(1)
		t.eq({ w.GrabService.Grab(player, section, HIT) }, { false, "dead" })
		local stuck = setup({ stuck = true })
		local record, stuckSection = stuck.piece()
		local p = stuck.player(1)
		t.eq({ stuck.GrabService.Grab(p, stuckSection, HIT) }, { false, "stuck" })
		t.eq(record.model:GetAttribute("HeldBy"), 0)
		t.eq(stuckSection.CollisionGroup, "Default")
		-- The engine refuses an anchored part. That false does not flip true.
		local anchored = Instance.new("Part")
		anchored.Anchored = true
		local player = w.player(3)
		local first = w.realSetOwner(anchored, player)
		local second = w.realSetOwner(anchored, player)
		t.eq(first, false)
		t.eq(second, false)
		-- And a loose part the engine still refuses (no physics here) is stuck.
		w.GrabService.Physics.SetOwner = w.realSetOwner
		local _, loose = w.piece()
		loose.Anchored = false
		t.eq({ w.GrabService.Grab(w.player(4), loose, HIT) }, { false, "stuck" })
		t.eq(w.realSetOwner(loose, player), false)
	end)

	t.test("letting go: groups and attributes back; the dropper keeps the physics 2 s, then automatic", function()
		local w = setup()
		local record, section, face = w.piece()
		local model = record.model
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		w.wait(0.5)
		w.handlers.Release(player, section)
		t.eq(w.GrabService.Holding(player), nil)
		t.eq(model:GetAttribute("HeldBy"), 0)
		t.eq(model:GetAttribute("GrabPoint"), nil)
		t.eq(section.CollisionGroup, "Default")
		t.eq(face.CollisionGroup, "Default")
		t.eq(record.lastInteracted, w.now())
		t.eq(w.released[1].reason, "released")
		t.eq(GameConfig.ReleaseKeepOwnerSec, 2)
		w.wait(1.5)
		w.watch()
		t.eq(#w.autos, 0, "still the dropper's")
		t.eq(w.owners[section], player)
		w.wait(0.5)
		w.watch()
		t.eq(w.autos, { section }, "then back to automatic")
	end)

	t.test("grabbed again inside the window: no automatic handover later", function()
		local w = setup()
		-- An Elder's piece, so a second player may take it straight away
		-- (anyone else's wood is its owner's while they're here).
		local _, section = w.piece(nil, { elder = true })
		local a = w.player(1)
		local b = w.player(2)
		t.ok(w.GrabService.Grab(a, section, HIT))
		w.GrabService.Release(a, section)
		w.wait(1)
		t.ok(w.GrabService.Grab(b, section, HIT))
		w.wait(2)
		w.watch()
		t.eq(#w.autos, 0)
		t.eq(w.owners[section], b)
	end)

	t.test("Release only lets go of the piece you hold", function()
		local w = setup()
		local recordA, sectionA = w.piece()
		local _, sectionB = w.piece(Vector3.new(0, 1, 3))
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, sectionA, HIT))
		w.GrabService.Release(player, sectionB)
		w.GrabService.Release(player, "nonsense")
		t.eq(w.GrabService.Holding(player), recordA.model)
		w.GrabService.Release(player, nil) -- streamed out on their device
		t.eq(w.GrabService.Holding(player), nil)
	end)

	t.test("one piece per player: grabbing another lets go of the first", function()
		local w = setup()
		local recordA, sectionA = w.piece()
		local recordB, sectionB = w.piece(Vector3.new(0, 1, 3))
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, sectionA, HIT))
		t.ok(w.GrabService.Grab(player, sectionB, Vector3.new(3, 2, 3)))
		t.eq(w.GrabService.Holding(player), recordB.model)
		t.eq(recordA.model:GetAttribute("HeldBy"), 0)
		t.eq(sectionA.CollisionGroup, "Default")
		t.eq(w.released[1].reason, "switch")
	end)

	t.test("forced release: death and sitting down (the watch, and the events' path)", function()
		local w = setup()
		local record, section = w.piece()
		local player, _, humanoid = w.player(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		humanoid.Health = 0
		w.wait(0.5)
		w.watch()
		t.eq(w.GrabService.Holding(player), nil)
		t.eq(record.model:GetAttribute("HeldBy"), 0)
		t.eq(w.released[1].reason, "died")
		humanoid.Health = 100
		w.wait(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		humanoid.SeatPart = {}
		w.wait(0.5)
		w.watch()
		t.eq(w.GrabService.Holding(player), nil)
		t.eq(w.released[2].reason, "seated")
		humanoid.SeatPart = nil
		w.wait(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		w.GrabService.ReleasePlayer(player, "died") -- Humanoid.Died
		t.eq(w.GrabService.Holding(player), nil)
	end)

	t.test("leaving hands what you hold, or still simulate, straight back", function()
		local w = setup()
		local _, sectionA = w.piece()
		local _, sectionB = w.piece(Vector3.new(0, 1, 3))
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, sectionB, Vector3.new(3, 2, 3)))
		w.GrabService.Release(player, sectionB) -- in the keep window
		t.ok(w.GrabService.Grab(player, sectionA, HIT))
		w.GrabService.PlayerRemoving(player)
		t.eq(w.GrabService.Holding(player), nil)
		t.ok(table.find(w.autos, sectionA) and table.find(w.autos, sectionB), "both back to automatic now")
		t.eq(w.released[#w.released].reason, "left")
	end)

	t.test("too far from its holder: it lets go", function()
		local w = setup()
		local record, section = w.piece()
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		w.wait(0.5)
		section.CFrame = section.CFrame + Vector3.new(0, 0, -25) -- dragged off by a fall, a truck...
		w.watch()
		t.eq(w.GrabService.Holding(player), nil)
		t.eq(w.released[1].reason, "far")
		t.eq(#w.loader.warnings, 0, "a fair move, not a teleport")
		t.eq(record.model:GetAttribute("HeldBy"), 0)
	end)

	t.test("a teleported piece is put back, stopped, and kept by the server a moment", function()
		local w = setup()
		local record, section = w.piece()
		local home = section.CFrame
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		w.wait(0.5)
		w.watch() -- an honest half second: accepted
		section.CFrame = home + Vector3.new(0, 0, 400) -- onto the sell pad, say
		section.AssemblyLinearVelocity = Vector3.new(0, 0, 50)
		w.wait(0.5)
		w.watch()
		t.eq(w.GrabService.Holding(player), nil)
		t.eq(record.model:GetAttribute("HeldBy"), 0)
		t.ok(near(section.CFrame.Position, home.Position), "back where it was")
		t.eq(section.AssemblyLinearVelocity, Vector3.zero, "stopped")
		t.eq(w.owners[section], nil, "the server simulates it")
		t.eq(#w.loader.warnings, 1)
		t.ok(string.find(w.loader.warnings[1], "[AntiExploit]", 1, true) ~= nil, w.loader.warnings[1])
		w.wait(1)
		w.watch()
		t.eq(w.autos, { section }, "then automatic again")
	end)

	t.test(
		"JudgeMoves off (WoodService's WoodWatch judges instead): no put-back here, the hold's checks stay",
		function()
			local w = setup()
			w.GrabService.JudgeMoves = false
			local record, section = w.piece()
			local home = section.CFrame
			local player = w.player(1)
			t.ok(w.GrabService.Grab(player, section, HIT))
			w.wait(0.5)
			w.watch()
			section.CFrame = home + Vector3.new(0, 0, 400)
			w.wait(0.5)
			w.watch()
			w.GrabService.JudgeMoves = true
			t.eq(#w.loader.warnings, 0, "not judged twice")
			t.eq(w.GrabService.Holding(player), nil, "but 400 studs from its holder it still lets go")
			t.eq(w.released[#w.released].reason, "far")
			t.eq(record.model:GetAttribute("HeldBy"), 0)
		end
	)

	t.test("a piece teleported in the dropper's keep window is put back too", function()
		local w = setup()
		local _, section = w.piece()
		local home = section.CFrame
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		w.GrabService.Release(player, section)
		section.CFrame = home + Vector3.new(400, 0, 0)
		w.wait(0.5)
		w.watch()
		t.ok(near(section.CFrame.Position, home.Position))
		t.eq(w.owners[section], nil)
		t.eq(#w.loader.warnings, 1)
	end)

	t.test("sold, cut or gone: the hold ends", function()
		local w = setup()
		local record, section = w.piece()
		local player = w.player(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		w.GrabService.ReleasePiece(record.model, "sold")
		t.eq(w.GrabService.Holding(player), nil)
		t.eq(w.autos, { section })
		t.eq(w.released[1].reason, "sold")
		w.wait(1)
		t.ok(w.GrabService.Grab(player, section, HIT))
		record.model.Parent = nil -- destroyed
		w.wait(0.5)
		w.watch()
		t.eq(w.GrabService.Holding(player), nil)
		t.eq(w.released[2].reason, "gone")
	end)

	t.test("characters join the Players group", function()
		local w = setup()
		local character = Instance.new("Model")
		local hrp = Instance.new("Part")
		hrp.Parent = character
		local hat = Instance.new("Accessory")
		local handle = Instance.new("Part")
		handle.Parent = hat
		hat.Parent = character
		w.GrabService.JoinPlayers(character)
		t.eq(hrp.CollisionGroup, "Players")
		t.eq(handle.CollisionGroup, "Players")
	end)
end
