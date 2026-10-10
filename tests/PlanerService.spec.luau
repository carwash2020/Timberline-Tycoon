--!nocheck
-- A placed planer takes a rested plank and gives the same piece back as a
-- finished board: planed down to the setting, stamped with the tier's board
-- bonus, nothing lost but the shavings. Only the owner steps the setting.
return function(t)
	local V3 = t.roblox.Vector3
	local CFrame = t.roblox.CFrame
	local Instance = t.roblox.Instance
	local owner = nil
	local profile = { plot = { placed = {} } }
	local loader = t.loader({
		services = {
			Players = {
				GetPlayers = function()
					return {}
				end,
				GetPlayerByUserId = function()
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
	local Planer = loader:server("PlanerService")
	local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
	local Logic = loader:shared("PlanerLogic")
	local Sell = loader:shared("SellLogic")
	local Config = loader:shared("GameConfig")
	local u = Config.WoodUnit

	local function plankPart(size, cf)
		local part = Instance.new("Part")
		part.Name = "Section"
		part.Size = size
		part.CFrame = cf
		local model = Instance.new("Model")
		part.Parent = model
		model.PrimaryPart = part
		return model, part
	end

	-- A planer with a plank resting in its intake.
	local function setup(id, size, extra, ctxExtra)
		local planer = MachineArt.BuildPlaner(id, false)
		planer.Parent = Instance.new("Folder")
		planer:SetAttribute("OwnerId", 7)
		planer:SetAttribute("Uid", "planer-1")
		planer:SetAttribute("PlanerId", id)
		local intake = planer:FindFirstChild("Intake")
		local model, part = plankPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local piece = {
			model = model,
			root = part,
			kind = "plank",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = Sell.VolumeU3(size.X, size.Y, size.Z),
			ownerId = 7,
			boost = 1.2,
			lux = true,
			figure = "curly",
			mill = 1.22,
			board = 1,
			verdictOk = true,
		}
		for k, v in pairs(extra or {}) do
			piece[k] = v
		end
		if piece.plain then
			piece.figure, piece.lux = nil, false
		end
		local now = 0
		local finished = {}
		local notes = {}
		local ctx = {
			notify = function(_, text)
				table.insert(notes, text)
			end,
			now = function()
				return now
			end,
			partsIn = function()
				return if part.Parent then { part } else {}
			end,
			pieceOf = function()
				return piece
			end,
			planers = function()
				return { planer }
			end,
			release = function() end,
			finish = function(p, newSize, board)
				table.insert(finished, { size = newSize, board = board })
				part.Size = V3.new(newSize.sx, newSize.sy, newSize.sz)
				p.board = board
			end,
			moved = function() end,
		}
		for k, v in pairs(ctxExtra or {}) do
			ctx[k] = v
		end
		Planer._use(ctx)
		return {
			planer = planer,
			piece = piece,
			part = part,
			finished = finished,
			notes = notes,
			tick = function(at)
				now = at
				Planer.Tick()
			end,
			advance = function(by)
				now += by
				Planer.Tick()
			end,
			now = function()
				return now
			end,
		}
	end

	local function done(r)
		r.planer:Destroy()
		Planer._reset()
	end

	t.test("a rested plank is planed to the setting and comes out a finished board with the tier's bonus", function()
		local r = setup("PlanerBench", V3.new(2 * u, 8, 1.2 * u))
		r.tick(0)
		t.eq(r.piece.selling, nil, "it has to rest")
		r.tick(Planer.Settle)
		t.eq(r.piece.selling, true)
		t.eq(r.part.Anchored, true)
		-- It rides the belt through, then is planed and let go.
		r.advance(Logic.ProcessSeconds(r.piece.volume) + 0.1)
		t.eq(#r.finished, 1)
		local f = r.finished[1]
		t.eq(f.board, 1.4, "the Bench Planer's boardBonus")
		t.ok(math.abs(f.size.sx - 1.6) < 1e-6 and math.abs(f.size.sz - 0.96) < 1e-6, "planed to 1.0 x 0.6 u")
		t.eq(f.size.sy, 8, "same length")
		t.eq(r.piece.selling, nil, "released")
		t.eq(r.part.Anchored, false)
		t.eq(r.piece.board, 1.4)
		-- The same piece: owner, wood, figure, boost, lux and mill bonus carry.
		t.eq(
			{ r.piece.ownerId, r.piece.woodId, r.piece.figure, r.piece.boost, r.piece.lux, r.piece.mill },
			{ 7, "oak", "curly", 1.2, true, 1.22 }
		)
		-- A finished board is not planed again.
		r.advance(5)
		r.advance(1)
		t.eq(#r.finished, 1, "no second pass, no stacked bonus")
		done(r)
	end)

	t.test("each tier stamps its own bonus; a better stamp is never lowered", function()
		for _, machine in ipairs(Logic.List()) do
			local r = setup(machine.id, V3.new(1 * u, 8, 0.6 * u))
			r.tick(0)
			r.tick(Planer.Settle)
			r.advance(5)
			t.eq(r.finished[1].board, machine.planer.boardBonus, machine.id)
			done(r)
		end
		-- Already stamped at 2.0 (as if from an Industrial) by a Hand planer: stays 2.0. A
		-- finished board is refused, so this is the stamp rule itself.
		local _, hand = Logic.Get("PlanerHand")
		t.eq(Logic.Stamp(2, hand), 2)
	end)

	t.test(
		"a plank smaller than the setting, a log, a branch and a too-big plank are refused with a toast, once",
		function()
			local r = setup("PlanerBench", V3.new(0.8 * u, 8, 0.6 * u))
			r.tick(0)
			r.tick(Planer.Settle)
			t.eq(r.piece.selling, nil, "too small for the setting")
			t.eq(#r.notes, 0, "no player to tell in this spec")
			t.eq(r.piece.model:GetAttribute("MillNote"), "small")
			done(r)
			local big = setup("PlanerHand", V3.new(3 * u, 8, 1 * u))
			big.tick(0)
			big.tick(Planer.Settle)
			t.eq(big.piece.selling, nil, "too big for a Hand Planer")
			done(big)
			local log = setup("PlanerHand", V3.new(1 * u, 8, 0.6 * u), { kind = "log" })
			log.tick(0)
			log.tick(Planer.Settle)
			t.eq(log.piece.selling, nil, "logs go to a sawmill")
			done(log)
			local branched = setup("PlanerHand", V3.new(1 * u, 8, 0.6 * u))
			branched.piece.nodes[1].children = { 2 }
			branched.tick(0)
			branched.tick(Planer.Settle)
			t.eq(branched.piece.selling, nil)
			done(branched)
		end
	)

	t.test("a setting lowered after a refusal lets the plank through (planed down, not refused)", function()
		local r = setup("PlanerBench", V3.new(0.8 * u, 8, 0.6 * u))
		r.tick(0)
		r.tick(Planer.Settle)
		t.eq(r.piece.selling, nil)
		r.planer:SetAttribute("CutX", 0.8)
		r.planer:SetAttribute("CutY", 0.6)
		r.advance(1)
		r.advance(Planer.Settle + 0.1)
		t.eq(r.piece.selling, true, "now it fits the setting")
		r.advance(5)
		t.eq(#r.finished, 1)
		t.ok(math.abs(r.finished[1].size.sx - 0.8 * u) < 1e-6)
		done(r)
	end)

	t.test(
		"a belt-fed plank is capped by the tier's rate; hand-fed is not; rare, others' wood and a full plot are refused",
		function()
			local function taken(extra, ctx, id)
				local r = setup(id or "PlanerSteam", V3.new(1 * u, 8, 0.6 * u), extra, ctx)
				r.tick(0)
				r.tick(Planer.Settle)
				local yes = r.piece.selling == true
				done(r)
				return yes
			end
			local old = { lastInteracted = -100, plain = true }
			t.eq(taken(old), true)
			t.eq(taken({ lastInteracted = -100, plain = true, woodId = "lumenwood" }), false, "rare stays manual")
			t.eq(taken({ lastInteracted = -100, figure = "curly" }), false)
			t.eq(taken({ lastInteracted = -100, plain = true, ownerId = 9 }), false)
			t.eq(
				taken(old, {
					online = function()
						return false
					end,
				}),
				false
			)
			t.eq(
				taken(old, {
					outputs = function()
						return 60
					end,
				}),
				false
			)
			t.eq(
				taken({ lastInteracted = 0, plain = true, woodId = "lumenwood" }),
				true,
				"hand-fed is never capped or refused for rarity"
			)
			-- The cap: a Hand planer's bucket is 8 u³ a minute; one big plank empties it.
			local r = setup("PlanerHand", V3.new(1 * u, 10, 0.6 * u), { lastInteracted = -100, plain = true })
			r.tick(0)
			r.tick(Planer.Settle)
			t.eq(r.piece.selling, true, "the first goes in")
			r.advance(5)
			r.piece.board = 1
			r.piece.selling = nil
			r.advance(1)
			r.advance(Planer.Settle + 0.1)
			t.eq(#r.finished >= 1, true)
			done(r)
		end
	)

	t.test("only the owner, standing at the planer, can step the setting; it is clamped to the tier", function()
		local planer = MachineArt.BuildPlaner("PlanerHand", false)
		planer:SetAttribute("Uid", "planer-1")
		planer:SetAttribute("OwnerId", 1)
		planer:SetAttribute("PlanerId", "PlanerHand")
		planer:PivotTo(CFrame.new())
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
		profile.plot.placed = { { uid = "planer-1", blueprintId = "PlanerHand", x = 0, z = 0, rot = 0 } }
		Planer._use({
			notify = function() end,
			planers = function()
				return { planer }
			end,
		})
		owner = player(1, V3.zero)
		planer:SetAttribute("CutX", 1)
		planer:SetAttribute("CutY", 0.6)
		Planer.Set(owner, "planer-1", "x", 1)
		t.eq(planer:GetAttribute("CutX"), 1.2)
		t.eq(profile.plot.placed[1].data, { x = 1.2, y = 0.6 }, "saved on the placed piece")
		local other = player(2, V3.zero)
		Planer.Set(other, "planer-1", "x", 1)
		t.eq(planer:GetAttribute("CutX"), 1.2, "someone else can't change it")
		owner = player(1, V3.new(80, 0, 0))
		Planer.Set(owner, "planer-1", "y", 1)
		t.eq(planer:GetAttribute("CutY"), 0.6, "too far away")
		owner = player(1, V3.zero)
		Planer.Set(owner, "planer-1", "z", 1)
		Planer.Set(owner, "planer-1", "x", 2)
		Planer.Set(owner, "planer-1", "x", "up")
		Planer.Set(owner, 42, "x", 1)
		t.eq(planer:GetAttribute("CutX"), 1.2, "only one step, on x or y, by a known uid")
		-- Walk it to the top of the Hand tier's range: it stops there, whatever is sent.
		for _ = 1, 30 do
			Planer.Set(owner, "planer-1", "x", 1)
			Planer.Set(owner, "planer-1", "y", 1)
		end
		t.eq(planer:GetAttribute("CutX"), 1.8)
		t.eq(planer:GetAttribute("CutY"), 1.2)
		t.eq(profile.plot.placed[1].data, { x = 1.8, y = 1.2 })
		for _ = 1, 40 do
			Planer.Set(owner, "planer-1", "x", -1)
			Planer.Set(owner, "planer-1", "y", -1)
		end
		t.eq(planer:GetAttribute("CutX"), 0.6)
		t.eq(planer:GetAttribute("CutY"), 0.4)
		planer:Destroy()
		owner = nil
		Planer._reset()
	end)

	t.test("setting steps are rate limited: a refused budget changes nothing", function()
		local limited = t.loader({
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					GetPlayerByUserId = function()
						return nil
					end,
				},
				PhysicsService = {},
			},
			mocks = {
				RateLimiter = {
					Allow = function()
						return false
					end,
				},
				ProfileService = {
					GetProfile = function()
						return profile
					end,
				},
			},
		})
		local P = limited:server("PlanerService")
		local Art = limited:load("ReplicatedStorage/Shared/Art/MachineArt")
		local planer = Art.BuildPlaner("PlanerHand", false)
		planer:SetAttribute("Uid", "planer-1")
		planer:SetAttribute("OwnerId", 1)
		planer:SetAttribute("PlanerId", "PlanerHand")
		planer:SetAttribute("CutX", 1)
		planer:PivotTo(CFrame.new())
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = V3.zero
		local me = {
			UserId = 1,
			Character = {
				FindFirstChild = function(_, name)
					return if name == "HumanoidRootPart" then root else nil
				end,
			},
		}
		P._use({
			notify = function() end,
			planers = function()
				return { planer }
			end,
		})
		P.Set(me, "planer-1", "x", 1)
		t.eq(planer:GetAttribute("CutX"), 1, "no budget: nothing moved")
		planer:Destroy()
		P._reset()
	end)

	t.test("Lane W: power off mid-plane pauses, power on resumes, one pass only", function()
		local r = setup("PlanerBench", V3.new(2 * u, 8, 1.2 * u))
		r.planer:SetAttribute("PowerIn", false)
		r.tick(0)
		r.tick(Planer.Settle + 1)
		t.eq(r.piece.selling, nil, "an unpowered planer does not take the plank")
		r.planer:SetAttribute("PowerIn", nil)
		r.advance(0)
		r.advance(Planer.Settle)
		t.eq(r.piece.selling, true, "powered: it takes the plank")
		r.advance(Logic.ProcessSeconds(r.piece.volume) / 3)
		r.planer:SetAttribute("PowerIn", false)
		r.advance(0)
		r.advance(Logic.ProcessSeconds(r.piece.volume) * 5)
		t.eq(#r.finished, 0, "nothing finishes while unpowered")
		t.eq(r.piece.selling, true, "the plank is still held")
		r.planer:SetAttribute("PowerIn", true)
		r.advance(0)
		t.eq(#r.finished, 0, "the clock resumes, it does not jump ahead")
		r.advance(Logic.ProcessSeconds(r.piece.volume) + 0.1)
		t.eq(#r.finished, 1, "planed once")
		done(r)
	end)

	t.test("Lane W: a reversed belt pushing a board back into the output is never re-planed", function()
		local asked = {}
		local r
		r = setup("PlanerBench", V3.new(2 * u, 8, 1.2 * u), nil, {
			partsIn = function(region)
				asked[region.Name] = true
				return if r.part.Parent then { r.part } else {}
			end,
		})
		r.tick(0)
		r.tick(Planer.Settle)
		r.advance(Logic.ProcessSeconds(r.piece.volume) + 0.1)
		t.eq(#r.finished, 1)
		for _ = 1, 5 do
			r.advance(2)
		end
		t.eq(#r.finished, 1, "a finished board is not planed again")
		for name in pairs(asked) do
			t.eq(name, "Intake", "only the intake takes wood")
		end
		done(r)
	end)
end
