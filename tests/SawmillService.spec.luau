--!nocheck
-- A placed mill takes a rested straight log and gives its volume back as planks.
return function(t)
	local V3 = t.roblox.Vector3
	local CFrame = t.roblox.CFrame
	local Instance = t.roblox.Instance
	local owner = nil
	local toastPlayer = nil
	local profile = { plot = { placed = {} } }
	local loader = t.loader({
		services = {
			Players = {
				GetPlayers = function()
					return {}
				end,
				GetPlayerByUserId = function(_, id)
					if toastPlayer and toastPlayer.UserId == id then
						return toastPlayer
					end
					return nil
				end,
			},
			PhysicsService = {},
		},
		mocks = {
			RateLimiter = {
				Allow = function()
					return true
				end,
			},
			ProfileService = {
				GetProfile = function(p)
					return if p == owner then profile else nil
				end,
			},
		},
	})
	local Sawmill = loader:server("SawmillService")
	local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
	local Logic = loader:shared("SawmillLogic")
	local Sell = loader:shared("SellLogic")
	local Catalog = loader:shared("ItemCatalog")
	local Config = loader:shared("GameConfig")

	local function logPart(size, cf)
		local part = Instance.new("Part")
		part.Name = "Section"
		part.Size = size
		part.CFrame = cf
		local model = Instance.new("Model")
		part.Parent = model
		model.PrimaryPart = part
		return model, part
	end

	t.test("a rested oak log becomes planks of the same volume, and those planks mill again", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local volume = Sell.VolumeU3(size.X, size.Y, size.Z)
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = volume,
			ownerId = 7,
			figure = "curly",
			boost = 1.2,
			lux = true,
			lastHolderId = 4,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		local spawned = {}
		local removed = 0
		local now = 0
		Sawmill._use({
			notify = function() end,
			now = function()
				return now
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				removed += 1
				p.dead = true
			end,
			spawn = function(info)
				table.insert(spawned, info)
				return nil
			end,
			moved = function() end,
		})
		Sawmill.Tick()
		t.eq(#spawned, 0, "it has to rest")
		t.eq(piece.selling, nil)
		now = Sawmill.Settle
		Sawmill.Tick()
		t.eq(piece.selling, true)
		t.eq(part.Anchored, true)
		-- Snapped onto the belt: length along the feed, centred, not still
		-- wherever it was dropped.
		local belt = mill:FindFirstChild("Conveyor")
		t.ok(part.CFrame.UpVector:Dot(belt.CFrame.LookVector) > 0.99, "the log lies along the belt")
		t.ok(math.abs(part.CFrame.X) < 0.2, "centred, clear of the walls")
		t.ok(part.CFrame.Y > belt.CFrame.Position.Y, "sitting on the belt")
		local before = part.CFrame.Position
		now += Logic.ProcessSeconds(volume) / 2
		Sawmill.Tick()
		local moved = part.CFrame.Position - before
		t.ok(moved.Z > 0.2 and math.abs(moved.X) < 1e-3, "it feeds along the belt, not through a wall")
		local expect = Logic.Cut(
			volume,
			Logic.DefaultSettings(Catalog.GetSawmill("SawmillRickety")),
			Catalog.GetSawmill("SawmillRickety")
		)
		now += Logic.ProcessSeconds(volume)
		for _ = 1, #expect + 2 do
			Sawmill.Tick()
			now += Sawmill.PlankGap
		end
		t.eq(removed, 1, "the log is gone once")
		t.eq(#spawned, #expect)
		local back = 0
		for _, info in ipairs(spawned) do
			t.eq(info.woodId, "oak")
			t.eq(info.ownerId, 7)
			t.eq(info.figure, "curly")
			t.eq(info.boost, 1.2)
			t.eq(info.lux, true, "planks keep the Lux tag, they don't add another")
			t.eq(info.lastHolderId, 4)
			back += Sell.VolumeU3(info.size.X, info.size.Y, info.size.Z)
		end
		t.ok(math.abs(back - volume) < 1e-3, "the planks add up to the log")
		-- Those planks, fed back at a smaller cut, come out thinner. The
		-- volume is the same and they are still planks (the spawn path).
		piece.kind = "plank"
		piece.dead = nil
		piece.selling = nil
		part.Anchored = false
		mill:SetAttribute("CutX", 0.6)
		mill:SetAttribute("CutY", 0.4)
		local before = #spawned
		now += 5
		Sawmill.Tick()
		t.eq(#spawned, before, "a plank rests before the second cut")
		now += 1
		Sawmill.Tick()
		t.eq(piece.selling, true, "the plank is taken")
		now += Logic.ProcessSeconds(volume)
		local again = Logic.Cut(volume, { x = 0.6, y = 0.4 }, Catalog.GetSawmill("SawmillRickety"))
		for _ = 1, #again + 2 do
			Sawmill.Tick()
			now += Sawmill.PlankGap
		end
		t.eq(#spawned, before + #again, "the plank was cut again")
		local back2 = 0
		for i = before + 1, #spawned do
			local info = spawned[i]
			t.eq(info.woodId, "oak")
			t.eq(info.figure, "curly")
			t.eq(info.boost, 1.2)
			t.ok(math.abs(info.size.X - 0.6 * Config.WoodUnit) < 1e-6, "thinner across X")
			t.ok(math.abs(info.size.Z - 0.4 * Config.WoodUnit) < 1e-6, "thinner across Y")
			back2 += Sell.VolumeU3(info.size.X, info.size.Y, info.size.Z)
		end
		t.ok(math.abs(back2 - volume) < 1e-3, "re-milling loses no volume")
		mill:Destroy()
		Sawmill._reset()
	end)

	t.test("only the owner, standing at the mill, can step the cut", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill:SetAttribute("Uid", "mill-1")
		mill:SetAttribute("OwnerId", 1)
		mill:PivotTo(CFrame.new())
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		local function player(userId, at)
			root.Position = at
			return {
				UserId = userId,
				Character = {
					FindFirstChild = function(_, name)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
			}
		end
		profile.plot.placed = {
			{ uid = "mill-1", blueprintId = "SawmillRickety", x = 0, z = 0, rot = 0 },
		}
		Sawmill._use({
			notify = function() end,
			mills = function()
				return { mill }
			end,
		})
		owner = player(1, V3.zero)
		toastPlayer = owner -- Players:GetPlayerByUserId(1): the plot's owner is online
		Sawmill.Set(owner, "mill-1", "x", 1)
		t.eq(mill:GetAttribute("CutX"), 1.2)
		t.eq(mill:GetAttribute("CutY"), 0.6)
		t.eq(profile.plot.placed[1].data, { x = 1.2, y = 0.6 })
		local other = player(2, V3.zero)
		Sawmill.Set(other, "mill-1", "x", 1)
		t.eq(mill:GetAttribute("CutX"), 1.2, "someone else can't change it")
		-- Lane F: PlotService.CanEdit's rule. A friend with Interact may; it is saved on the owner's plot.
		profile.permissions = { ["2"] = { interact = true } }
		Sawmill.Set(other, "mill-1", "x", 1)
		t.eq(mill:GetAttribute("CutX"), 1.4, "a friend with Interact may step the cut")
		t.eq(profile.plot.placed[1].data.x, 1.4, "saved on the owner's plot")
		profile.permissions = { ["2"] = { grab = true } }
		Sawmill.Set(other, "mill-1", "x", -1)
		t.eq(mill:GetAttribute("CutX"), 1.4, "a friend without Interact may not")
		profile.permissions = nil
		Sawmill.Set(owner, "mill-1", "x", -1)
		t.eq(mill:GetAttribute("CutX"), 1.2)
		owner = player(1, V3.new(80, 0, 0))
		Sawmill.Set(owner, "mill-1", "y", 1)
		t.eq(mill:GetAttribute("CutY"), 0.6, "too far away")
		owner = player(1, V3.zero)
		Sawmill.Set(owner, "mill-1", "z", 1)
		Sawmill.Set(owner, "mill-1", "x", 2)
		t.eq(mill:GetAttribute("CutX"), 1.2, "only one step, on x or y")
		mill:Destroy()
		owner = nil
		Sawmill._reset()
	end)

	local function useMill(mill, piece, part, nowFn)
		local notes = {}
		Sawmill._use({
			notify = function(_, text)
				table.insert(notes, text)
			end,
			now = nowFn,
			partsIn = function()
				return if part.Parent then { part } else {}
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				p.dead = true
			end,
			spawn = function()
				return nil
			end,
			moved = function() end,
		})
		return notes
	end

	t.test("a pine base is refused with the blockage board and a toast that names the width", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2.6, 9, 2.6)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "pine",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = Sell.VolumeU3(size.X, size.Y, size.Z),
			ownerId = 7,
			boost = 1,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		toastPlayer = { UserId = 7 }
		local now = 0
		local notes = useMill(mill, piece, part, function()
			return now
		end)
		local sign = mill:FindFirstChild("Blockage", true)
		t.eq(sign.Transparency, 1, "the board starts hidden")
		Sawmill.Tick()
		t.eq(piece.selling, nil, "a pine base is not taken")
		t.eq(sign.Transparency, 0, "BLOCKAGE shows")
		t.eq(sign:FindFirstChildWhichIsA("SurfaceGui").Enabled, true)
		t.eq(sign:FindFirstChildWhichIsA("TextLabel", true).Text, "BLOCKAGE")
		t.eq(notes, { "Too big for this mill (max 1.4 u wide)" })
		now = 5
		Sawmill.Tick()
		t.eq(#notes, 1, "the toast is once")
		part.Parent = nil
		Sawmill.Tick()
		t.eq(sign.Transparency, 1, "the board drops when the log leaves")
		mill:Destroy()
		toastPlayer = nil
		Sawmill._reset()
	end)

	t.test("a teleported log and a flung log are refused", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local volume = Sell.VolumeU3(size.X, size.Y, size.Z)
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = volume,
			ownerId = 7,
			boost = 1,
			verdictOk = false,
			selling = nil,
			dead = nil,
			shopItem = nil,
			lastGood = intake.CFrame,
			lastGoodAt = 0,
		}
		local spawned = 0
		local now = 0
		Sawmill._use({
			notify = function() end,
			now = function()
				return now
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				p.dead = true
			end,
			spawn = function()
				spawned += 1
				return nil
			end,
			moved = function() end,
		})
		now = Sawmill.Settle + 1
		Sawmill.Tick()
		Sawmill.Tick()
		t.eq(piece.selling, nil, "WoodWatch said no")
		t.eq(spawned, 0)
		piece.verdictOk = true
		piece.lastGood = CFrame.new(0, 0, 400)
		piece.lastGoodAt = now
		now += 1
		Sawmill.Tick()
		now += 2
		Sawmill.Tick()
		t.eq(piece.selling, nil, "it appeared far from where it was last accepted")
		piece.lastGood = part.CFrame
		piece.lastGoodAt = now
		part.AssemblyLinearVelocity = V3.new(0, 0, 200)
		now += 1
		Sawmill.Tick()
		now += 2
		Sawmill.Tick()
		t.eq(piece.selling, nil, "still flying")
		t.eq(spawned, 0)
		part.AssemblyLinearVelocity = V3.zero
		piece.lastGood = part.CFrame
		piece.lastGoodAt = now
		Sawmill.Tick()
		t.eq(piece.selling, nil, "it has to rest after the fling")
		now += 1
		Sawmill.Tick()
		t.eq(piece.selling, true, "once it has actually rested, the mill takes it")
		mill:Destroy()
		Sawmill._reset()
	end)

	t.test("the mill cuts the parts it measured, not a larger recorded volume", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = 80,
			ownerId = 7,
			boost = 1,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		toastPlayer = { UserId = 7 }
		local notes = {}
		local now = 0
		Sawmill._use({
			notify = function(_, text)
				table.insert(notes, text)
			end,
			now = function()
				return now
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function() end,
			spawn = function()
				return nil
			end,
			moved = function() end,
		})
		now = Sawmill.Settle
		Sawmill.Tick()
		now += 1
		Sawmill.Tick()
		t.eq(piece.selling, nil)
		t.eq(notes, { "That piece isn't the size the mill measured." })
		mill:Destroy()
		toastPlayer = nil
		Sawmill._reset()
	end)

	t.test("each plank fires the plank milestone for its owner", function()
		local Milestone = loader:server("MilestoneService")
		local events = {}
		Milestone.Listen(function(p, kind)
			table.insert(events, { id = p.UserId, kind = kind })
		end)
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local volume = Sell.VolumeU3(size.X, size.Y, size.Z)
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = volume,
			ownerId = 7,
			boost = 1,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		toastPlayer = { UserId = 7, Name = "Ada" }
		local spawned = {}
		local now = 0
		Sawmill._use({
			notify = function() end,
			now = function()
				return now
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				p.dead = true
			end,
			spawn = function(info)
				table.insert(spawned, info)
				return nil
			end,
			moved = function() end,
		})
		Sawmill.Tick()
		now = Sawmill.Settle
		Sawmill.Tick()
		local expect = Logic.Cut(
			volume,
			Logic.DefaultSettings(Catalog.GetSawmill("SawmillRickety")),
			Catalog.GetSawmill("SawmillRickety")
		)
		now += Logic.ProcessSeconds(volume)
		for _ = 1, #expect + 2 do
			Sawmill.Tick()
			now += Sawmill.PlankGap
		end
		t.eq(#spawned, #expect)
		t.eq(#events, #spawned, "one milestone per plank")
		for _, event in ipairs(events) do
			t.eq(event.kind, "plank")
			t.eq(event.id, 7)
		end
		toastPlayer = nil
		mill:Destroy()
		Sawmill._reset()
	end)

	-- A log in a mill's intake, rested, ready for the next tick.
	local function intakeLog(millId, extra)
		local mill = MachineArt.Build(millId, false)
		mill.Parent = Instance.new("Folder")
		mill:SetAttribute("OwnerId", 7)
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = Sell.VolumeU3(size.X, size.Y, size.Z),
			ownerId = 7,
			boost = 1,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		for k, v in pairs(extra or {}) do
			piece[k] = v
		end
		return mill, piece, part
	end

	-- Runs one piece through a mill and returns what it spawned.
	local function run(millId, extra, ctxExtra)
		local mill, piece, part = intakeLog(millId, extra)
		local spawned, now = {}, 0
		local ctx = {
			notify = function() end,
			now = function()
				return now
			end,
			partsIn = function()
				return if part.Parent and not piece.dead then { part } else {}
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				p.dead = true
			end,
			spawn = function(info)
				table.insert(spawned, info)
				return nil
			end,
			moved = function() end,
		}
		for k, v in pairs(ctxExtra or {}) do
			ctx[k] = v
		end
		Sawmill._use(ctx)
		return {
			mill = mill,
			piece = piece,
			spawned = spawned,
			tick = function(at)
				now = at
				Sawmill.Tick()
			end,
			finish = function()
				for _ = 1, 40 do
					now += Sawmill.PlankGap + 0.5
					Sawmill.Tick()
				end
			end,
		}
	end

	t.test("every mill stamps its tier's plank bonus on the planks it cuts (a piece keeps its mill's bonus)", function()
		local last = 0
		for _, def in ipairs(Catalog.SawmillList()) do
			t.ok(def.plankBonus >= last, def.id .. " bonus never drops")
			last = def.plankBonus
			local r = run(def.id)
			r.tick(0)
			r.tick(Sawmill.Settle)
			r.finish()
			t.ok(#r.spawned > 0, def.id .. " cut planks")
			for _, info in ipairs(r.spawned) do
				t.eq(info.mill, def.plankBonus, def.id .. " stamps its own bonus")
			end
			r.mill:Destroy()
			Sawmill._reset()
		end
		-- A plank cut again by a worse mill keeps the better stamp; by a better one, takes it.
		local r = run("SawmillRickety", { kind = "plank", mill = 1.5 })
		r.tick(0)
		r.tick(Sawmill.Settle)
		r.finish()
		t.ok(#r.spawned > 0)
		t.eq(r.spawned[1].mill, 1.5, "a 1.5 plank through a Rickety stays 1.5")
		r.mill:Destroy()
		Sawmill._reset()
		local r2 = run("Millmaster100", { kind = "plank", mill = 1 })
		r2.tick(0)
		r2.tick(Sawmill.Settle)
		r2.finish()
		t.eq(
			r2.spawned[1].mill,
			Catalog.GetSawmill("Millmaster100").plankBonus,
			"an old plank takes the better mill's bonus"
		)
		r2.mill:Destroy()
		Sawmill._reset()
	end)

	t.test("a belt-fed log is capped by the tier's rate; a hand-fed one never is", function()
		-- Hand-fed (touched a moment ago): in at once.
		local hand = run("SawmillRickety", { lastInteracted = 0 })
		hand.tick(0)
		hand.tick(Sawmill.Settle)
		t.eq(hand.piece.selling, true, "hand-fed goes straight in")
		hand.mill:Destroy()
		Sawmill._reset()
		-- Belt-fed (untouched for ages): the bucket starts full, so the first goes in...
		local belt = run("SawmillRickety", { lastInteracted = -100 })
		belt.tick(0)
		belt.tick(Sawmill.Settle)
		t.eq(belt.piece.selling, true, "the first belt-fed log goes in")
		-- ...and leaves the bucket in debt (about 8.8 u³ against a 1 u³ bucket).
		belt.finish()
		belt.piece.dead = nil
		belt.piece.selling = nil
		local base = 40 * (Sawmill.PlankGap + 0.5) + 1
		belt.tick(base)
		belt.tick(base + Sawmill.Settle + 0.1)
		t.eq(belt.piece.selling, nil, "still in debt half a minute later: the belt waits")
		-- Minutes later the debt is paid and the next one goes in.
		belt.tick(base + 200)
		t.eq(belt.piece.selling, true, "the next one goes in once the bucket has refilled")
		belt.mill:Destroy()
		Sawmill._reset()
	end)

	t.test(
		"belts refuse rare wood, someone else's wood, an offline owner and a full plot; hand work is fine",
		function()
			local function taken(extra, ctx)
				local r = run("Millmaster200", extra, ctx)
				r.tick(0)
				r.tick(Sawmill.Settle)
				local yes = r.piece.selling == true
				r.mill:Destroy()
				Sawmill._reset()
				return yes
			end
			local old = { lastInteracted = -100 }
			t.eq(taken(old), true, "an ordinary belt-fed log goes in")
			t.eq(taken({ lastInteracted = -100, woodId = "lumenwood" }), false, "lumenwood stays manual")
			t.eq(taken({ lastInteracted = -100, figure = "curly" }), false, "figured wood stays manual")
			t.eq(taken({ lastInteracted = -100, ownerId = 9 }), false, "only the owner's own wood")
			t.eq(
				taken(old, {
					online = function()
						return false
					end,
				}),
				false,
				"no production while the owner is away"
			)
			t.eq(
				taken(old, {
					outputs = function()
						return 60
					end,
				}),
				false,
				"a full plot stops the line"
			)
			t.eq(taken({ lastInteracted = 0, woodId = "lumenwood" }), true, "hand-fed lumenwood is fine")
			t.eq(taken({ lastInteracted = 0, ownerId = 9 }), true, "hand-fed, anyone's")
		end
	)

	t.test("a log's temper t is stamped onto every plank the mill cuts", function()
		local r = run("SawmillRickety", { temper = 1.07 })
		r.tick(0)
		r.tick(Sawmill.Settle)
		r.finish()
		t.ok(#r.spawned > 0)
		for _, info in ipairs(r.spawned) do
			t.eq(info.temper, 1.07)
			local volume = Sell.VolumeU3(info.size.X, info.size.Y, info.size.Z)
			local priced = Sell.PieceValue("oak", "plank", volume, nil, 1, false, info.mill, nil, 1.07)
			local untinted = Sell.PieceValue("oak", "plank", volume, nil, 1, false, info.mill, nil, 1)
			t.ok(
				math.abs(priced - untinted * 1.07) < 1e-6 or priced == untinted * Sell.BonusCap,
				"the sale uses t, capped with the mill"
			)
		end
		r.mill:Destroy()
		Sawmill._reset()
	end)

	t.test("Lane W: power off mid-cut pauses the log and resumes with power, nothing lost or made twice", function()
		Sawmill._reset()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local volume = Sell.VolumeU3(size.X, size.Y, size.Z)
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = volume,
			ownerId = 7,
			verdictOk = true,
		}
		local spawned = {}
		local removed = 0
		local now = 0
		Sawmill._use({
			notify = function() end,
			now = function()
				return now
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				removed += 1
				p.dead = true
			end,
			spawn = function(info)
				table.insert(spawned, info)
				return nil
			end,
			moved = function() end,
		})
		-- Unpowered mill never takes a log.
		mill:SetAttribute("PowerIn", false)
		now = Sawmill.Settle + 1
		Sawmill.Tick()
		t.eq(piece.selling, nil, "an unpowered mill does not take the log")
		mill:SetAttribute("PowerIn", nil)
		Sawmill.Tick()
		now += Sawmill.Settle
		Sawmill.Tick()
		t.eq(piece.selling, true, "power on: it takes the log once it rests")
		now += Logic.ProcessSeconds(volume) / 3
		Sawmill.Tick()
		mill:SetAttribute("PowerIn", false)
		Sawmill.Tick()
		local held = part.CFrame.Position
		now += Logic.ProcessSeconds(volume) * 5
		Sawmill.Tick()
		t.eq(#spawned, 0, "no planks while unpowered")
		t.eq(removed, 0, "the log is not lost")
		t.ok((part.CFrame.Position - held).Magnitude < 1e-4, "the log holds still")
		mill:SetAttribute("PowerIn", true)
		Sawmill.Tick()
		t.eq(#spawned, 0, "the clock resumes, it does not jump ahead")
		local expect = Logic.Cut(
			volume,
			Logic.DefaultSettings(Catalog.GetSawmill("SawmillRickety")),
			Catalog.GetSawmill("SawmillRickety")
		)
		now += Logic.ProcessSeconds(volume)
		for _ = 1, #expect + 2 do
			Sawmill.Tick()
			now += Sawmill.PlankGap
		end
		t.eq(removed, 1, "the log is used once")
		t.eq(#spawned, #expect, "the same planks as an unbroken cut")
		mill:Destroy()
		Sawmill._reset()
	end)
end
