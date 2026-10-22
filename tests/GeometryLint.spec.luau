--!nocheck
-- GeometryLint (T409): nothing solid shares space with anything else, and nothing solid stands in a
-- lane, a door or a path. Rule 2b walks the whole built world (tests/support/WorldBuild) and fails on
-- any two parts of different pieces that overlap by more than 0.05 studs unless tests/geometry_allow.json
-- names the pair with a reason. The lane rule checks the Sawmill's part build against the same lane
-- boxes tools/blender/meshlint.py tests the GLBs with. Every line it prints is one hit, deepest first.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local Geometry = t.load("ReplicatedStorage/Shared/Lint/Geometry")
	local Lanes = t.load("ReplicatedStorage/Shared/Lint/Lanes")
	local LaneData = t.load("ReplicatedStorage/Shared/Lint/LaneData")
	local Clearance = t.load("ReplicatedStorage/Shared/World/Clearance")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local allow = serde.decode("json", fs.readFile("tests/geometry_allow.json"))

	local function show(lines)
		return "\n" .. table.concat(lines, "\n")
	end

	-- A small world: each box is { name, at, size, parent? }; parts with the same `piece` share a Model.
	local function smallWorld(boxes)
		local root = Instance.new("Folder")
		root.Name = "TimberlineMap"
		local models = {}
		for _, b in ipairs(boxes) do
			local model = models[b.piece]
			if not model then
				model = Instance.new("Model")
				model.Name = b.piece
				model.Parent = root
				models[b.piece] = model
			end
			local part = Instance.new("Part")
			part.Name = b.name
			part.Anchored = true
			part.CanCollide = true
			part.Size = b.size or Vector3.new(2, 2, 2)
			part.CFrame = b.cf or CFrame.new(b.at)
			part.Parent = model
			if b.fn then
				b.fn(part)
			end
		end
		return root
	end

	t.test("Clearance.Box: depth along the shallowest SAT axis, Y range, turned boxes", function()
		local a = Clearance.Box(CFrame.new(0, 0, 0), Vector3.new(2, 2, 2))
		local function depth(cf, size)
			return Clearance.BoxDepth(a, Clearance.Box(cf, size or Vector3.new(2, 2, 2)))
		end
		t.ok(math.abs(depth(CFrame.new(1.5, 0, 0)) - 0.5) < 1e-6, "side by side")
		t.eq(depth(CFrame.new(2, 0, 0)), 0, "touching is not an overlap")
		t.eq(depth(CFrame.new(0, 2.5, 0)), 0, "above it: the Y range decides")
		t.eq(depth(CFrame.new(5, 0, 0)), 0)
		t.ok(math.abs(depth(CFrame.new(0, 1.9, 0)) - 0.1) < 1e-6, "stacked, 0.1 into each other")
		-- a box turned 45 degrees: its corner reaches 0.914 into the first
		local turned = depth(CFrame.new(1.5, 0, 0) * CFrame.Angles(0, math.rad(45), 0))
		t.ok(math.abs(turned - 0.9142135) < 1e-4, "turned: " .. turned)
		-- a long thin box crossing a corner: only the cross-product axes separate it
		local rod = Clearance.Box(CFrame.new(1.5, 1.5, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.1, 4, 0.1))
		t.ok(Clearance.BoxDepth(a, rod) >= 0)
		local apart =
			Clearance.Box(CFrame.new(2.6, 2.6, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.1, 1, 0.1))
		t.eq(Clearance.BoxDepth(a, apart), 0, "a rod past the corner is apart")
		-- the 2D shapes have no box: they never overlap in 3D
		t.eq(Clearance.BoxDepth(Clearance.Disc(0, 0, 1), Clearance.Disc(0, 0, 1)), 0)
	end)

	t.test("Clearance.BoxHits: the grid finds what a brute-force scan finds", function()
		local grid = Clearance.NewGrid()
		local seed = 9
		local function rnd(lo, hi)
			seed = (seed * 1103515245 + 12345) % 2147483648
			return lo + (hi - lo) * seed / 2147483648
		end
		local shapes = {}
		for i = 1, 120 do
			local shape = Clearance.Box(
				CFrame.new(rnd(-60, 60), rnd(0, 6), rnd(-60, 60)) * CFrame.Angles(0, rnd(0, 3), 0),
				Vector3.new(rnd(1, 9), rnd(1, 5), rnd(1, 9))
			)
			shapes[i] = shape
			Clearance.Add(grid, "b" .. i, "box", shape)
		end
		local want = 0
		for i = 1, #shapes do
			for j = i + 1, #shapes do
				if Clearance.BoxDepth(shapes[i], shapes[j]) > 0.05 then
					want += 1
				end
			end
		end
		local hits = Clearance.BoxHits(grid, 0.05)
		t.eq(#hits, want)
		t.ok(want > 5, "the scan has something to find")
		for i = 2, #hits do
			t.ok(hits[i - 1].depth >= hits[i].depth, "deepest first")
		end
	end)

	t.test("controls: depth 0.05 passes, 0.06 fails; the same piece never counts", function()
		local function run(gap, samePiece)
			local world = smallWorld({
				{ name = "Crate", piece = "Crate", at = Vector3.new(0, 1, 0) },
				{ name = "Wall", piece = if samePiece then "Crate" else "Wall", at = Vector3.new(2 - gap, 1, 0) },
			})
			return Geometry.Run(world, {})
		end
		t.eq(#run(0.05).hits, 0, "0.05 deep passes")
		t.eq(#run(0.0499).hits, 0)
		local deeper = run(0.06)
		t.eq(#deeper.hits, 1, "0.06 deep fails")
		t.ok(
			string.find(deeper.failures[1], "Crate (Crate) x Wall (Wall)", 1, true)
				or string.find(deeper.failures[1], "Wall (Wall) x Crate (Crate)", 1, true),
			deeper.failures[1]
		)
		t.ok(string.find(deeper.failures[1], "depth 0.06, rule 2b", 1, true), deeper.failures[1])
		t.eq(#run(0.9, true).hits, 0, "parts of one piece may overlap (welded decks and plinths)")
	end)

	t.test("controls: a crate inside a wall, a lamp inside a sign", function()
		local world = smallWorld({
			{ name = "Wall_N", piece = "GeneralStore", at = Vector3.new(0, 4, 0), size = Vector3.new(20, 8, 1) },
			{ name = "Crate", piece = "Crate", at = Vector3.new(3, 1.5, 0), size = Vector3.new(2, 2, 2) },
			{ name = "Lamp", piece = "Lamp", at = Vector3.new(40, 5, 0), size = Vector3.new(1, 1, 1) },
			{ name = "Board", piece = "Sign", at = Vector3.new(40, 5, 0.2), size = Vector3.new(6, 3, 0.4) },
		})
		local r = Geometry.Run(world, {})
		t.eq(#r.hits, 2)
		local text = table.concat(r.failures, "\n")
		t.ok(string.find(text, "Crate (Crate) x Wall_N (GeneralStore)", 1, true), text)
		t.ok(
			string.find(text, "Lamp (Lamp) x Board (Sign)", 1, true)
				or string.find(text, "Board (Sign) x Lamp (Lamp)", 1, true),
			text
		)
		-- the deepest hit is listed first
		t.ok(r.hits[1].depth >= r.hits[2].depth)
		-- an allowlist entry with a reason clears it, in either order
		local ok = Geometry.Run(world, {
			{ a = "Crate", b = "GeneralStore", reason = "test" },
			{ a = "Sign", b = "Lamp", reason = "test" },
		})
		t.eq(ok.failures, {})
	end)

	t.test("controls: an allowlist entry needs a reason, and must still hit something", function()
		local world = smallWorld({
			{ name = "A", piece = "A", at = Vector3.new(0, 1, 0) },
			{ name = "B", piece = "B", at = Vector3.new(1, 1, 0) },
		})
		local noReason = Geometry.Run(world, { { a = "A", b = "B" } })
		t.eq(#noReason.failures, 1, show(noReason.failures))
		t.ok(string.find(noReason.failures[1], "has no reason", 1, true), noReason.failures[1])
		local empty = Geometry.Run(world, { { a = "A", b = "B", reason = "" } })
		t.ok(string.find(empty.failures[1], "has no reason", 1, true), empty.failures[1])
		local stale = Geometry.Run(world, {
			{ a = "A", b = "B", reason = "known" },
			{ a = "A", b = "Gone", reason = "stale" },
		})
		t.eq(#stale.failures, 1, show(stale.failures))
		t.ok(string.find(stale.failures[1], "hits nothing now", 1, true), stale.failures[1])
	end)

	t.test("controls: a transparent part that collides needs InvisibleBlocker and a reason", function()
		local function world(fn)
			return smallWorld({
				{
					name = "Ghost",
					piece = "Ghost",
					at = Vector3.new(0, 1, 0),
					fn = function(p)
						p.Transparency = 1
						if fn then
							fn(p)
						end
					end,
				},
			})
		end
		local bare = Geometry.Run(world(), {})
		t.eq(#bare.failures, 1, show(bare.failures))
		t.ok(string.find(bare.failures[1], "rule 2c", 1, true), bare.failures[1])
		local noReason = Geometry.Run(
			world(function(p)
				p:SetAttribute("InvisibleBlocker", true)
			end),
			{}
		)
		t.eq(#noReason.failures, 1, "the flag alone is not enough")
		local named = Geometry.Run(
			world(function(p)
				p:SetAttribute("InvisibleBlocker", true)
				p:SetAttribute("InvisibleBlockerReason", "keeps people off the pond")
			end),
			{}
		)
		t.eq(named.failures, {})
		local walkable = Geometry.Run(
			world(function(p)
				p.CanCollide = false
			end),
			{}
		)
		t.eq(walkable.failures, {}, "a ghost that does not collide is fine")
	end)

	t.test("a round part counts as its inscribed box, a wedge is not counted", function()
		local world = smallWorld({
			{
				name = "Drum",
				piece = "Drum",
				at = Vector3.new(0, 1, 0),
				size = Vector3.new(2, 2, 2),
				fn = function(p)
					p.Shape = roblox.Enum.PartType.Cylinder
				end,
			},
			-- inside the cylinder's bounding box corner but outside the cylinder
			{ name = "Peg", piece = "Peg", at = Vector3.new(0, 1.9, 0.9), size = Vector3.new(1, 0.5, 0.3) },
		})
		t.eq(#Geometry.Run(world, {}).hits, 0, "the corner of a drum's box is not the drum")
	end)

	t.test("lane rule: a part in a lane fails, 'x lane Sawmill.slip'; riders and named hits do not", function()
		local frame = CFrame.new(0, 0, 100)
		local function sawmill(parts)
			local root = Instance.new("Folder")
			local model = Instance.new("Model")
			model.Name = "Sawmill"
			model.Parent = root
			for _, p in ipairs(parts) do
				local part = Instance.new("Part")
				part.Name = p.name
				part.Anchored = true
				part.Size = p.size or Vector3.new(1, 4, 1)
				part.CFrame = frame * CFrame.new(p.at)
				part.Parent = model
			end
			return root
		end
		local frames = { Sawmill = frame }
		local clean = Lanes.Run(sawmill({ { name = "Post", at = Vector3.new(26, 3, 8) } }), frames)
		t.eq(clean.failures, {})
		t.eq(clean.checked, #LaneData.Boxes.Sawmill)
		local post = Lanes.Run(sawmill({ { name = "Post", at = Vector3.new(25, 3, -0.9) } }), frames)
		t.eq(#post.failures, 1, show(post.failures))
		t.ok(string.find(post.failures[1], "x lane Sawmill.slip", 1, true), post.failures[1])
		local both = Lanes.Run(sawmill({ { name = "Post", at = Vector3.new(-8, 3, -0.9) } }), frames)
		t.eq(#both.failures, 2, "the carriage and the outfeed lane share that stretch: " .. show(both.failures))
		local slipOnly = Lanes.Run(sawmill({ { name = "Post", at = Vector3.new(25, 3, -0.9) } }), frames, {
			Sawmill = { LaneData.Boxes.Sawmill[1] },
		})
		t.ok(string.find(slipOnly.failures[1], "Post (Sawmill) x lane Sawmill.slip", 1, true), slipOnly.failures[1])
		local rider = Lanes.Run(sawmill({ { name = "Carriage", at = Vector3.new(25, 3, -0.9) } }), frames)
		t.eq(rider.failures, {}, "a carriage belongs in the lane")
		-- another piece's part in the lane counts too (a crate dropped on the slip)
		local mixed = sawmill({})
		local crate = Instance.new("Model")
		crate.Name = "Crate"
		crate.Parent = mixed
		local box = Instance.new("Part")
		box.Name = "Crate"
		box.Anchored = true
		box.Size = Vector3.new(2, 2, 2)
		box.CFrame = frame * CFrame.new(25, 3, -0.9)
		box.Parent = crate
		local other = Lanes.Run(mixed, frames)
		t.eq(#other.failures, 1, show(other.failures))
		t.ok(string.find(other.failures[1], "Crate (Crate) x lane Sawmill.slip", 1, true), other.failures[1])
		local missing = Lanes.Run(Instance.new("Folder"), frames)
		t.eq(#missing.failures, 1, "a lane whose model is gone is a failure, not a pass")
	end)

	t.test(
		"LaneData agrees with assets/meshes/lanes.json (one set of lanes for the mesh lint and the part lint)",
		function()
			local json = serde.decode("json", fs.readFile("assets/meshes/lanes.json"))
			for mesh, entries in pairs(json) do
				local data = LaneData.Boxes[mesh]
				t.ok(data, mesh .. " has lane data")
				t.eq(#data, #entries, mesh .. " lane count")
				for i, entry in ipairs(entries) do
					t.eq(data[i].name, entry.name)
					t.eq(data[i].kind, entry.kind)
					for k, axis in ipairs({ "X", "Y", "Z" }) do
						t.ok(math.abs(data[i].min[axis] - entry.min[k]) < 1e-6, entry.name .. " min " .. axis)
						t.ok(math.abs(data[i].max[axis] - entry.max[k]) < 1e-6, entry.name .. " max " .. axis)
					end
				end
			end
			for mesh in pairs(LaneData.Boxes) do
				t.ok(json[mesh], mesh .. " is in lanes.json")
			end
			for _, entry in ipairs(LaneData.Allow) do
				t.ok(type(entry.reason) == "string" and entry.reason ~= "", "every named lane hit has a reason")
			end
			-- the allowlist and every meshlint exemption carry a reason
			for lane, entries in pairs(json) do
				for _, e in ipairs(entries) do
					for _, a in ipairs(e.allow or {}) do
						t.ok(
							type(a.why) == "string" and a.why ~= "",
							lane .. "/" .. e.name .. ": a lane exemption has no reason"
						)
					end
				end
			end
		end
	)

	t.test("the allowlist file: every entry has a reason", function()
		t.ok(#allow > 5)
		for i, entry in ipairs(allow) do
			t.ok(
				type(entry.reason) == "string" and #entry.reason > 20,
				"entry " .. i .. " (" .. entry.a .. " x " .. entry.b .. ") needs a reason"
			)
		end
	end)

	local function world()
		return t.support("WorldBuild").Get(t)
	end

	t.test("2b: the built world has no two pieces sharing space (bar the named hits)", function()
		local w = world()
		t.eq(w.warnings[1] ~= nil and #w.warnings or 0, #w.warnings)
		local r = Geometry.Run(w.map, allow)
		t.ok(r.parts > 1500, r.parts .. " colliding parts walked")
		t.ok(r.pieces > 300, r.pieces .. " pieces")
		t.eq(r.failures, {}, show(r.failures))
	end)

	t.test("the lanes of the built Sawmill are clear (slip, carriage, outfeed, front door)", function()
		local w = world()
		local r = Lanes.Run(w.map, { Sawmill = WorldPlan.Town().sawmill })
		t.eq(r.checked, 4)
		t.eq(r.failures, {}, show(r.failures))
	end)

	t.test("moving the front GuardRail 1.2 studs (design) into the carriage lane fails the lane rule", function()
		local w = world()
		local mill = w.map.Sawmill
		local rails = {}
		for _, d in ipairs(mill:GetChildren()) do
			if d.Name == "GuardRail" then
				table.insert(rails, d)
			end
		end
		t.eq(#rails, 2, "the front and the east guard rail")
		local frame = WorldPlan.Town().sawmill
		local front
		for _, r in ipairs(rails) do
			local at = frame:PointToObjectSpace(r.CFrame.Position)
			if math.abs(at.Z - -4.65) < 0.1 then
				front = r
			end
		end
		t.ok(front, "the front rail stands at z -4.65 (design -3.1 x 1.5)")
		local home = front.CFrame
		front.CFrame = home + frame:VectorToWorldSpace(Vector3.new(0, 0, 1.2 * 1.5))
		local moved = Lanes.Run(w.map, { Sawmill = frame })
		front.CFrame = home
		t.ok(#moved.failures >= 1, "a guard rail in the carriage lane is a failure")
		local text = table.concat(moved.failures, "\n")
		t.ok(string.find(text, "GuardRail (Sawmill) x lane Sawmill.carriage", 1, true), text)
		t.eq(Lanes.Run(w.map, { Sawmill = frame }).failures, {}, "back home it passes again")
	end)
end
