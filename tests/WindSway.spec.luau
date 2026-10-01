--!nocheck
-- WindSway (StarterPlayerScripts/WindSway): the canopies' sway, against
-- fakes for the camera, the frame clock (Heartbeat, os.clock), tags and
-- workspace:BulkMoveTo. It proves what Studio can't show us by reading code:
--   * PLAY-04: WindSway.PlanFrame never plans more than the frame's part
--     budget, and walks the trees round-robin so every swaying tree gets
--     its turn within a few frames. In a frostwood stand (96 canopy parts a
--     tree, the worst wood) the real module moves at most 900 parts a frame
--     and every one of the nearest 32 trees at least every 4 frames; on
--     low quality (PLAY-05) at most 400 parts, the nearest 16 within 80
--     studs, and the switch takes effect while playing.
--   * The pose is a function of the time alone: a tree that sat out a few
--     frames lands exactly where a tree that never skipped one is.
--   * NAT-09: each canopy part's rest offset is read once per tree
--     instance, before WindSway ever moves it. A tree felled (or wobbling)
--     as you walk away is put back at rest once it's idle again, and a
--     canopy left leaning is never read back as its rest pose. Felled and
--     busy trees are never moved.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	---------------------------------------------------------------------------
	-- PlanFrame, the pure planner
	---------------------------------------------------------------------------

	local WindSway = t.loader({
		mocks = {
			LightingController = {},
			Quality = {},
			TreeFX = {},
		},
		services = { RunService = {}, CollectionService = {} },
	}):load("StarterPlayer/StarterPlayerScripts/WindSway")

	-- Runs PlanFrame for `frames` frames over fixed costs. Returns, per
	-- frame, the parts spent and the trees taken, and per tree the frames
	-- it was taken on.
	local function plan(costs, budget, frames)
		local cursor = 1
		local spentBy, takenBy, when = {}, {}, {}
		for i = 1, #costs do
			when[i] = {}
		end
		for f = 1, frames do
			local spent, taken = 0, {}
			cursor = WindSway.PlanFrame(#costs, cursor, budget, function(i)
				return costs[i]
			end, function(i)
				spent += costs[i]
				table.insert(taken, i)
				table.insert(when[i], f)
			end)
			spentBy[f], takenBy[f] = spent, taken
		end
		return spentBy, takenBy, when
	end

	-- The longest wait between two turns (and before the first), in frames.
	local function longestGap(frames)
		local gap, last = 0, 0
		for _, f in ipairs(frames) do
			gap = math.max(gap, f - last)
			last = f
		end
		return gap
	end

	-- The promise PlanFrame keeps: a frame that stops early has spent more
	-- than budget - the dearest tree, so a full lap takes at most this many
	-- frames.
	local function bound(costs, budget)
		local total, dearest = 0, 0
		for _, c in ipairs(costs) do
			if c > 0 and c <= budget then
				total += c
				dearest = math.max(dearest, c)
			end
		end
		return math.ceil(total / (budget - dearest + 1)) + 1
	end

	t.test("PlanFrame: a frostwood stand stays inside the budget and every tree gets a turn every 4 frames", function()
		for _, case in ipairs({ { trees = 32, budget = 900 }, { trees = 16, budget = 400 } }) do
			local costs = table.create(case.trees, 96)
			local spentBy, _, when = plan(costs, case.budget, 120)
			for f, spent in ipairs(spentBy) do
				t.ok(spent <= case.budget, string.format("frame %d spent %d of %d", f, spent, case.budget))
				t.ok(spent > case.budget - 96, "and never leaves a tree's worth of budget unused")
			end
			for i, frames in ipairs(when) do
				t.ok(longestGap(frames) <= 4, string.format("tree %d waited %d frames", i, longestGap(frames)))
			end
		end
	end)

	t.test("PlanFrame: mixed woods, never over budget, every tree within the bound", function()
		-- Canopy part counts of the nine woods (TreeArt), drawn at random.
		local woods = { 10, 11, 12, 14, 18, 21, 24, 48, 96 }
		local state = 7
		local function roll(lo, hi)
			state = (state * 1103515245 + 12345) % 2147483648
			return lo + state % (hi - lo + 1)
		end
		for _ = 1, 40 do
			local budget = roll(150, 1000)
			local costs = {}
			for i = 1, roll(1, 48) do
				costs[i] = woods[roll(1, #woods)]
			end
			local spentBy, _, when = plan(costs, budget, 60)
			for _, spent in ipairs(spentBy) do
				t.ok(spent <= budget, "over budget")
			end
			local n = bound(costs, budget)
			for _, frames in ipairs(when) do
				t.ok(longestGap(frames) <= n, string.format("waited %d > %d frames", longestGap(frames), n))
			end
		end
	end)

	t.test("PlanFrame: when everything fits, every tree updates every frame", function()
		local costs = table.create(32, 18) -- the Starter Forest's oaks: 576 parts
		local spentBy, takenBy = plan(costs, 900, 10)
		for f = 1, 10 do
			t.eq(spentBy[f], 576)
			t.eq(#takenBy[f], 32)
		end
	end)

	t.test("PlanFrame: idle-less trees cost nothing, and an oversized one never stalls the walk", function()
		-- Tree 2 is busy (0), tree 4 is bigger than the whole budget.
		local costs = { 96, 0, 96, 5000, 96, 96 }
		local spentBy, _, when = plan(costs, 200, 30)
		for _, spent in ipairs(spentBy) do
			t.ok(spent <= 200)
		end
		t.eq(#when[2], 0, "a busy tree is never moved")
		t.eq(#when[4], 0, "nor one that could never fit")
		for _, i in ipairs({ 1, 3, 5, 6 }) do
			t.ok(longestGap(when[i]) <= 2, "the rest share the frames")
		end
	end)

	t.test("PlanFrame: no trees, or a cursor past a shrunken list, starts over at 1", function()
		local calls = 0
		local cursor = WindSway.PlanFrame(0, 5, 900, function()
			calls += 1
			return 1
		end, function() end)
		t.eq(cursor, 1)
		t.eq(calls, 0)
		local first
		WindSway.PlanFrame(3, 9, 900, function(i)
			first = first or i
			return 1
		end, function() end)
		t.eq(first, 1)
	end)

	---------------------------------------------------------------------------
	-- The real module, frame by frame
	---------------------------------------------------------------------------

	-- A fake world: a camera at the origin looking down -Z, a Heartbeat to
	-- step, and a BulkMoveTo that records each call.
	local QualityBudgets = t.shared("QualityBudgets")

	local function world()
		local w = {
			clock = 100,
			heartbeat = {},
			calls = {}, -- this frame's BulkMoveTo calls: { parts }
			tagged = { Tree = {} },
			added = {},
			removed = {},
			busy = {},
			wind = 0.4,
			tier = "high", -- Quality's tier
			owner = {}, -- canopy part -> its tree
		}
		local folder = Instance.new("Folder")
		w.camera = { CFrame = CFrame.new(0, 6, 0) }
		w.workspace = {
			CurrentCamera = w.camera,
			GlobalWind = Vector3.zero,
			BulkMoveTo = function(_, parts, frames)
				assert(#parts == #frames, "a CFrame for every part")
				for i, p in ipairs(parts) do
					p.CFrame = frames[i]
				end
				table.insert(w.calls, table.clone(parts))
			end,
		}
		local function store(list)
			return {
				Connect = function(_, fn)
					table.insert(list, fn)
				end,
			}
		end
		local loader = t.loader({
			services = {
				CollectionService = {
					GetTagged = function(_, tag)
						return w.tagged[tag] or {}
					end,
					GetInstanceAddedSignal = function(_, tag)
						w.added[tag] = w.added[tag] or {}
						return store(w.added[tag])
					end,
					GetInstanceRemovedSignal = function(_, tag)
						w.removed[tag] = w.removed[tag] or {}
						return store(w.removed[tag])
					end,
				},
				RunService = {
					Heartbeat = store(w.heartbeat),
				},
			},
			mocks = {
				LightingController = {
					Environment = function()
						return { wind = w.wind }
					end,
				},
				TreeFX = {
					IsBusy = function(tree)
						return w.busy[tree] == true
					end,
				},
				Quality = {
					Budget = function()
						return QualityBudgets.For(w.tier)
					end,
				},
			},
			globals = {
				workspace = w.workspace,
				os = {
					clock = function()
						return w.clock
					end,
				},
			},
		})
		w.WindSway = loader:load("StarterPlayer/StarterPlayerScripts/WindSway")
		local TreeArt = loader:shared("Art/TreeArt")
		local WoodData = loader:shared("WoodData")
		local Kit = loader:shared("Art/Kit")

		-- A tree standing at (x, 0, z), as TreeService sets it up.
		function w.tree(woodId, x, z, seed)
			local tree = TreeArt.Build(WoodData.Get(woodId), seed or 7, 1)
			Kit.placeAt(tree, CFrame.new(x, 0, z))
			tree:SetAttribute("WoodId", woodId)
			tree:SetAttribute("HP", 10)
			tree:SetAttribute("HomePivot", tree:GetPivot())
			tree:SetAttribute("Felled", false)
			tree.Parent = folder
			for _, d in ipairs(tree:GetDescendants()) do
				if d:IsA("BasePart") then
					w.owner[d] = tree
				end
			end
			table.insert(w.tagged.Tree, tree)
			return tree
		end

		-- One frame, dt seconds long. Returns the parts moved and, per
		-- tree, whether it moved.
		function w.frame(dt)
			dt = dt or 1 / 60
			w.clock += dt
			table.clear(w.calls)
			for _, fn in ipairs(w.heartbeat) do
				fn(dt)
			end
			local parts, moved = 0, {}
			for _, call in ipairs(w.calls) do
				parts += #call
				for _, p in ipairs(call) do
					local tree = w.owner[p]
					if tree then
						moved[tree] = true
					end
				end
			end
			return parts, moved
		end
		return w
	end

	-- 40 frostwoods ahead of the camera, all within 120 studs. Returns them
	-- nearest the camera first, and the spot and seed each was built from.
	local function frostStand(w)
		local trees, made = {}, {}
		for k = 1, 40 do
			local x = ((k % 5) - 2) * 9
			local z = -12 - k * 2.4
			local tree = w.tree("frostwood", x, z, k)
			table.insert(trees, tree)
			made[tree] = { x = x, z = z, seed = k }
		end
		local eye = w.camera.CFrame.Position
		table.sort(trees, function(a, b)
			return (a:GetPivot().Position - eye).Magnitude < (b:GetPivot().Position - eye).Magnitude
		end)
		return trees, made
	end

	t.test("in a frostwood stand: at most 900 parts a frame, the nearest 32 sway every 4 frames or less", function()
		local w = world()
		local trees = frostStand(w)
		w.WindSway.Start()
		local when = {}
		for f = 1, 120 do
			local parts, moved = w.frame()
			t.ok(parts <= 900, string.format("frame %d moved %d parts", f, parts))
			t.ok(parts >= 900 - 96, "and uses the budget")
			for tree in pairs(moved) do
				when[tree] = when[tree] or {}
				table.insert(when[tree], f)
			end
		end
		for i, tree in ipairs(trees) do
			if i <= 32 then
				t.ok(when[tree] ~= nil, string.format("tree %d sways", i))
				t.ok(longestGap(when[tree]) <= 4, string.format("tree %d waited %d frames", i, longestGap(when[tree])))
			else
				t.eq(when[tree], nil, "only the nearest 32 sway")
			end
		end
	end)

	-- Runs `frames` frames; returns the most parts a frame moved and, per
	-- tree, the frames it moved on.
	local function watch(w, frames)
		local most, when = 0, {}
		for f = 1, frames do
			local parts, moved = w.frame()
			most = math.max(most, parts)
			for tree in pairs(moved) do
				when[tree] = when[tree] or {}
				table.insert(when[tree], f)
			end
		end
		return most, when
	end

	t.test("on low quality: at most 400 parts a frame, the nearest 16 within 80 studs, each every 4 frames", function()
		local w = world()
		w.tier = "low"
		local trees = frostStand(w)
		w.WindSway.Start()
		local most, when = watch(w, 120)
		t.ok(most <= 400, string.format("a frame moved %d parts", most))
		local eye = w.camera.CFrame.Position
		local swaying = 0
		for i, tree in ipairs(trees) do
			if i <= 16 then
				t.ok((tree:GetPivot().Position - eye).Magnitude <= 80, "the nearest 16 are inside 80 studs")
				t.ok(
					when[tree] ~= nil and longestGap(when[tree]) <= 4,
					string.format("tree %d sways every 4 frames", i)
				)
				swaying += 1
			else
				t.eq(when[tree], nil, "nothing past the nearest 16")
			end
		end
		t.eq(swaying, 16)
	end)

	t.test("lowering the quality while playing takes effect, and the trees let go are put back at rest", function()
		local w = world()
		local trees = frostStand(w)
		local rest = {}
		for _, tree in ipairs(trees) do
			for _, d in ipairs(tree:GetDescendants()) do
				if d:IsA("BasePart") then
					rest[d] = d.CFrame
				end
			end
		end
		w.WindSway.Start()
		local most = watch(w, 60)
		t.ok(most > 400 and most <= 900, "high: up to 900 parts")
		w.tier = "low"
		watch(w, 30) -- the next scan picks 16 trees
		local after, when = watch(w, 60)
		t.ok(after <= 400, string.format("low: %d parts a frame", after))
		for i = 17, #trees do
			local tree = trees[i]
			t.eq(when[tree], nil, "only 16 sway now")
			for _, d in ipairs(tree:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok((d.CFrame.Position - rest[d].Position).Magnitude < 1e-5, "and the rest stand at rest")
				end
			end
		end
	end)

	t.test("a tree that sits out frames is posed from the time alone, like one that never does", function()
		-- The same frostwood in a crowded stand (updates every few frames)
		-- and standing alone (updates every frame), on the same clock.
		local crowded, alone = world(), world()
		local trees, made = frostStand(crowded)
		local watched = trees[20]
		local spot = made[watched]
		local twin = alone.tree("frostwood", spot.x, spot.z, spot.seed)
		crowded.WindSway.Start()
		alone.WindSway.Start()
		local function canopy(tree)
			local out = {}
			for _, d in ipairs(tree:GetDescendants()) do
				if d:IsA("BasePart") and d ~= tree.PrimaryPart then
					table.insert(out, d)
				end
			end
			return out
		end
		local a, b = canopy(watched), canopy(twin)
		t.eq(#a, #b)
		local compared, skipped = 0, 0
		for _ = 1, 90 do
			local _, movedCrowded = crowded.frame()
			local _, movedAlone = alone.frame()
			t.ok(movedAlone[twin], "alone, it moves every frame")
			if movedCrowded[watched] then
				compared += 1
				for k = 1, #a do
					local da = (a[k].CFrame.Position - b[k].CFrame.Position).Magnitude
					t.ok(da < 1e-4, string.format("part %d is %.6f studs off", k, da))
				end
			else
				skipped += 1
			end
		end
		t.ok(compared > 10 and skipped > 10, "it both moved and sat out frames")
	end)

	---------------------------------------------------------------------------
	-- NAT-09: rest offsets for the tree instance's lifetime
	---------------------------------------------------------------------------

	-- A tree's canopy parts, by WindSway's rule.
	local CANOPY = { Leaves = true, Frond = true }
	local function canopyOf(tree)
		local out = {}
		for _, d in ipairs(tree:GetDescendants()) do
			if d:IsA("BasePart") then
				local parent = d.Parent
				local inTier = parent ~= tree and parent:IsA("Model") and parent.Name == "Tier"
				if CANOPY[d.Name] or inTier or (d.Name == "Facet" and parent == tree) then
					table.insert(out, d)
				end
			end
		end
		return out
	end
	local function snapshot(parts)
		local out = {}
		for _, p in ipairs(parts) do
			out[p] = p.CFrame
		end
		return out
	end
	-- How far the furthest part is from where `from` had it (position, plus
	-- its axes' drift so a pure turn counts too).
	local function drift(parts, from)
		local worst = 0
		for _, p in ipairs(parts) do
			local a, b = p.CFrame, from[p]
			worst = math.max(
				worst,
				(a.Position - b.Position).Magnitude,
				(a.LookVector - b.LookVector).Magnitude,
				(a.UpVector - b.UpVector).Magnitude
			)
		end
		return worst
	end
	local function run(w, frames)
		local movedEver = {}
		for _ = 1, frames do
			local _, moved = w.frame()
			for tree in pairs(moved) do
				movedEver[tree] = true
			end
		end
		return movedEver
	end
	local NEAR = CFrame.new(0, 6, 0)
	local FAR = CFrame.new(0, 6, 400) -- well past RANGE

	t.test("NAT-09: a tree felled as you walk away is put back at rest once it regrows", function()
		local w = world()
		local tree = w.tree("oak", 0, -20)
		local parts = canopyOf(tree)
		local server = snapshot(parts) -- as it streamed in
		w.WindSway.Start()
		run(w, 30)
		t.ok(drift(parts, server) > 1e-3, "it sways")
		tree:SetAttribute("Felled", true) -- TreeFX fells it; WindSway lets go
		local atFell = snapshot(parts)
		w.camera.CFrame = FAR
		run(w, 30)
		t.eq(drift(parts, atFell), 0, "WindSway leaves a felled tree alone, even to restore it")
		tree:SetAttribute("Felled", false) -- regrown while you were away
		run(w, 30)
		t.ok(drift(parts, server) < 1e-5, string.format("back at rest (off by %.6f)", drift(parts, server)))
	end)

	t.test("NAT-09: a canopy left leaning is never read back as its rest pose", function()
		for _, woodId in ipairs({ "oak", "pine", "frostwood" }) do
			local w = world()
			local tree = w.tree(woodId, 0, -20)
			local parts = canopyOf(tree)
			local server = snapshot(parts)
			w.WindSway.Start()
			run(w, 30)
			tree:SetAttribute("Felled", true)
			w.camera.CFrame = FAR
			run(w, 30) -- dropped while felled: still leaning
			w.camera.CFrame = NEAR
			run(w, 30) -- back in range, still down
			t.ok(drift(parts, server) > 1e-3, woodId .. ": still leaning when it regrows")
			tree:SetAttribute("Felled", false) -- regrows next to you
			local moved = run(w, 60)
			t.ok(moved[tree], woodId .. ": sways again")
			w.camera.CFrame = FAR
			run(w, 30)
			t.ok(
				drift(parts, server) < 1e-5,
				string.format("%s: back at the server's pose, not the lean (off by %.6f)", woodId, drift(parts, server))
			)
		end
	end)

	t.test("WindSway never moves a felled tree or one TreeFX is animating", function()
		local w = world()
		local tree = w.tree("oak", 0, -20)
		local parts = canopyOf(tree)
		w.WindSway.Start()
		t.ok(run(w, 10)[tree], "a standing tree sways")
		tree:SetAttribute("Felled", true)
		local before = snapshot(parts)
		t.eq(run(w, 30)[tree], nil, "not while felled")
		t.eq(drift(parts, before), 0)
		tree:SetAttribute("Felled", false)
		t.ok(run(w, 30)[tree], "again once it stands")
		w.busy[tree] = true -- TreeFX.IsBusy: a regrow spring, say
		before = snapshot(parts)
		t.eq(run(w, 30)[tree], nil, "not while TreeFX is busy with it")
		t.eq(drift(parts, before), 0)
		w.busy[tree] = nil
		t.ok(run(w, 30)[tree], "and again after")
	end)
end
