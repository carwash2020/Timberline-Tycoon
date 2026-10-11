--!nocheck
-- Lane F: LooseService, over a faked world. Unloading a base keeps every
-- unheld log, plank, board, slab and ingot of the owner's (or nobody's) that
-- lies on the plot; loading it on another pad brings each back once, with no
-- copies; wood the map remake parked comes back at the plot within the cap.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function world(opts)
		opts = opts or {}
		local state = {
			pieces = {}, -- uid -> piece (WoodService.All)
			removed = {},
			slabs = {}, -- { uid, kind, ore, held, position }
			taken = {},
			built = {},
			slabsBack = {},
			ingotsBack = {},
			slabRoom = if opts.slabRoom == nil then 24 else opts.slabRoom,
			buildFails = opts.buildFails == true,
		}
		local loader = t.loader({
			mocks = {
				WoodService = {
					All = function()
						return state.pieces
					end,
					Remove = function(piece, why)
						state.removed[piece.uid] = why
						state.pieces[piece.uid] = nil
					end,
				},
				TruckLoad = {
					SnapshotAt = function(model, ref, bed)
						local rec = model:GetAttribute("Record")
						if rec == nil then
							return nil
						end
						-- plot-relative place: the model sits at its Position
						local rel = ref:ToObjectSpace(CFrame.new(model.PrimaryPart.Position))
						local p = rel.Position
						return {
							w = "oak",
							k = rec,
							bed = bed,
							at = { p.X, p.Y, p.Z, 0, 0, 0 },
							s = { { 1, 4, 1, 0, 0, 0, 0, 0, 0, 0 } },
						}
					end,
					Build = function(piece, owner, cf)
						if state.buildFails then
							return nil
						end
						table.insert(state.built, { piece = piece, owner = owner, cf = cf })
						return {}
					end,
				},
				BuildMaterials = {
					Of = function()
						return state.slabs
					end,
					Take = function(uid)
						state.taken[uid] = true
						return true
					end,
					ReturnSlab = function(userId, cf)
						if #state.slabsBack >= state.slabRoom then
							return false
						end
						table.insert(state.slabsBack, { userId = userId, cf = cf })
						return true
					end,
					ReturnIngot = function(_, ore, cf)
						table.insert(state.ingotsBack, { ore = ore, cf = cf })
						return true
					end,
				},
			},
		})
		return loader:server("LooseService"), state
	end

	local PAD = CFrame.new(100, 5, 100)

	local function player(userId)
		return { UserId = userId }
	end

	local function piece(state, uid, at, opts)
		opts = opts or {}
		local model = roblox.Instance.new("Model")
		model.Name = uid
		local root = roblox.Instance.new("Part")
		root.Position = at
		root.Parent = model
		model.PrimaryPart = root
		model:SetAttribute("Record", if opts.record == nil then "log" else opts.record)
		if opts.heldBy then
			model:SetAttribute("HeldBy", opts.heldBy)
		end
		local p = {
			uid = uid,
			model = model,
			root = root,
			kind = opts.kind or "log",
			ownerId = if opts.ownerId == nil then 1 else opts.ownerId,
		}
		state.pieces[uid] = p
		return p
	end

	local function profile(extra)
		local p = { plot = { tier = 1, squares = {}, placed = {}, loose = {} } }
		for k, v in pairs(extra or {}) do
			p[k] = v
		end
		return p
	end

	local inside = Vector3.new(104, 6, 98)

	t.test("collect keeps the owner's and unowned loose wood on the plot, and leaves the rest", function()
		local svc, st = world()
		piece(st, "mine", inside)
		piece(st, "nobody", Vector3.new(96, 6, 100), { ownerId = 0, kind = "plank" })
		piece(st, "theirs", inside, { ownerId = 2 })
		piece(st, "held", inside, { heldBy = 1 })
		piece(st, "away", Vector3.new(900, 6, 900))
		local prof = profile()
		local ok, why = svc.Collect(player(1), { cframe = PAD }, prof, true)
		t.eq({ ok, why }, { true, nil })
		t.eq(#prof.plot.loose, 2, "mine and nobody's")
		t.eq(st.removed.mine, "unload")
		t.eq(st.removed.nobody, "unload")
		t.eq(st.removed.theirs, nil, "someone else's wood stays")
		t.eq(st.removed.held, nil, "held wood stays in the hand")
		t.eq(st.removed.away, nil, "off the plot stays")
		local rec = prof.plot.loose[1]
		t.eq(rec.bed, "Plot")
		t.ok(math.abs(rec.at[1] - 4) < 1e-6 and math.abs(rec.at[3] - -2) < 1e-6, "saved relative to the pad's pivot")
	end)

	t.test("slabs and ingots go too; a plain leave keeps ingots for Lane M's own save", function()
		local svc, st = world()
		st.slabs = {
			{ uid = "s1", kind = "slab", held = false, position = Vector3.new(102, 6, 100) },
			{ uid = "s2", kind = "slab", held = true, position = Vector3.new(102, 6, 100) },
			{ uid = "i1", kind = "ingot", ore = "Copper", held = false, position = Vector3.new(98, 6, 100) },
			{ uid = "far", kind = "slab", held = false, position = Vector3.new(700, 6, 700) },
		}
		local prof = profile()
		local ok = svc.Collect(player(1), { cframe = PAD }, prof, false)
		t.eq(ok, true)
		t.eq(#prof.plot.loose, 1, "leave: only the slab")
		t.eq(prof.plot.loose[1].slab, true)
		t.eq(st.taken.s1, true)
		t.eq(st.taken.i1, nil)
		local prof2 = profile()
		st.taken = {}
		svc.Collect(player(1), { cframe = PAD }, prof2, true)
		t.eq(#prof2.plot.loose, 2, "unload: the slab and the ingot")
		t.eq(prof2.plot.loose[2].ingot, "Copper")
		t.eq(st.taken.s2, nil, "a held slab stays held")
	end)

	t.test("over the cap: nothing is touched and the refusal names the count", function()
		local svc, st = world()
		for i = 1, 151 do
			piece(st, "p" .. i, inside)
		end
		local prof = profile()
		local ok, why = svc.Collect(player(1), { cframe = PAD }, prof, true)
		t.eq(ok, false)
		t.ok(why:find("151") ~= nil and why:find("1 first") ~= nil, why)
		t.eq(next(st.removed), nil, "no wood was destroyed")
		t.eq(#prof.plot.loose, 0)
		local scan = svc.Scan(player(1), { cframe = PAD }, prof)
		t.eq(scan.pieces, 151)
	end)

	t.test("a piece the save cannot hold stops the unload and stays in the world", function()
		local svc, st = world()
		piece(st, "ok", inside)
		piece(st, "odd", inside, { record = nil })
		st.pieces.odd.model:SetAttribute("Record", nil)
		local prof = profile()
		local ok, why = svc.Collect(player(1), { cframe = PAD }, prof, true)
		t.eq(ok, false)
		t.ok(why:find("can't be saved") ~= nil, why)
		t.eq(next(st.removed), nil)
	end)

	t.test("restore puts everything back on the new pad once: no copies", function()
		local svc, st = world()
		piece(st, "a", inside)
		local prof = profile()
		st.slabs = { { uid = "s1", kind = "slab", held = false, position = Vector3.new(101, 6, 101) } }
		svc.Collect(player(1), { cframe = PAD }, prof, true)
		t.eq(#prof.plot.loose, 2)
		local other = CFrame.new(-300, 8, 40)
		local back, waiting = svc.Restore(player(1), { cframe = other }, prof)
		t.eq({ back, waiting }, { 2, 0 })
		t.eq(#st.built, 1, "the log was rebuilt")
		t.eq(#st.slabsBack, 1, "and the slab")
		local at = st.built[1].cf.Position
		t.ok(math.abs(at.X - (-300 + 4)) < 1e-3 and math.abs(at.Z - (40 - 2)) < 1e-3, "relative to the NEW pad")
		t.eq(#prof.plot.loose, 0, "the list is cleared")
		local again = svc.Restore(player(1), { cframe = other }, prof)
		t.eq(again, 0, "a second load brings nothing back twice")
		t.eq(#st.built, 1)
	end)

	t.test("a record that cannot be rebuilt right now stays saved", function()
		local svc, st = world({ slabRoom = 1 })
		local prof = profile()
		prof.plot.loose = {
			{ slab = true, at = { 1, 0, 1, 0, 0, 0 } },
			{ slab = true, at = { 2, 0, 1, 0, 0, 0 } },
			{ ingot = "Gold", at = { 3, 0, 1, 0, 0, 0 } },
			{ slab = true, at = { 9999, 0, 1, 0, 0, 0 } },
		}
		local back, waiting = svc.Restore(player(1), { cframe = PAD }, prof)
		t.eq(back, 3, "one slab, the ingot, and the junk record dropped")
		t.eq(waiting, 1, "the second slab had no room and waits")
		t.eq(#prof.plot.loose, 1)
		t.eq(prof.plot.loose[1].at[1], 2)
		local failing, st2 = world({ buildFails = true })
		local p2 = profile()
		p2.plot.loose = {
			{ w = "oak", k = "log", bed = "Plot", at = { 1, 2, 3, 0, 0, 0 }, s = { { 1, 4, 1, 0, 0, 0, 0, 0, 0, 0 } } },
		}
		local b2, w2 = failing.Restore(player(1), { cframe = PAD }, p2)
		t.eq({ b2, w2 }, { 0, 1 })
		t.eq(#p2.plot.loose, 1, "wood that could not be built is kept, never lost")
		t.eq(#st2.built, 0)
	end)

	t.test("strandedLoad comes back at the plot within the cap, over-cap pieces stay parked, then it clears", function()
		local svc, st = world()
		local function stranded(i)
			return {
				w = "oak",
				k = "log",
				bed = "Ground",
				at = { 0, 0, 0, 0, 0, 0 },
				g = { 10 + i, 4, 20 },
				s = { { 1, 4, 1, 0, 0, 0, 0, 0, 0, 0 } },
			}
		end
		local prof = profile({ strandedLoad = { stranded(1), stranded(2), "junk", stranded(3) } })
		local back, left = svc.RestoreStranded(player(1), { cframe = PAD }, prof)
		t.eq({ back, left }, { 3, 0 })
		t.eq(#st.built, 3)
		t.eq(#prof.strandedLoad, 0, "cleared")
		-- Idempotent: a second pass finds nothing.
		t.eq({ svc.RestoreStranded(player(1), { cframe = PAD }, prof) }, { 0, 0 })
		t.eq(#st.built, 3)
		-- Room is what the plot's loose list leaves of the cap.
		local full = profile({ strandedLoad = { stranded(1), stranded(2), stranded(3) } })
		for i = 1, 149 do
			full.plot.loose[i] = { slab = true, at = { 0, 0, 0, 0, 0, 0 } }
		end
		local b2, l2 = svc.RestoreStranded(player(1), { cframe = PAD }, full)
		t.eq({ b2, l2 }, { 1, 2 }, "one fits under 150; two stay parked with a count")
		t.eq(#full.strandedLoad, 2)
		t.eq(full.strandedLoad[1].g[1], 12, "the parked ones keep their saved place")
	end)
end
