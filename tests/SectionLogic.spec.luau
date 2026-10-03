--!nocheck
-- SectionLogic (Shared): the v2 cut maths (V2_PLAN.md §2a, §2c, §3d).
--   * The hits table: swings to cut a mature trunk at its base,
--     ceil(hardness * (t/1.6)^2 / damage), for every axe and wood. The
--     emberwood column is recomputed for its v2 hardness 11 (the plan's
--     table predates emberwood taking the swamp-gold row).
--   * Required damage, the cut window (hits within 0.6 add to one cut,
--     the nearest), at most 2 cuts a section (a third replaces the least
--     damaged), heights kept CutEdge from the ends.
--   * Splitting a section conserves its volume; cutting any section of a
--     tree's graph leaves exactly two pieces, every section in one of them.
--   * Offcuts under MinPieceVolume are chips; a freed piece belongs to the
--     cut's top contributor (the feller's rule).
return function(t)
	local SectionLogic = t.shared("SectionLogic")
	local GameConfig = t.shared("GameConfig")
	local ItemCatalog = t.shared("ItemCatalog")
	local WoodData = t.shared("WoodData")
	local TreeGen = t.shared("TreeGen")
	local CFrame, Vector3 = t.roblox.CFrame, t.roblox.Vector3

	local WOODS = { "oak", "birch", "pine", "maple", "palmwood", "frostwood", "emberwood", "phantomwood", "lumenwood" }
	-- Rows: axes; columns: WOODS. (V2_PLAN §2c; emberwood recomputed.)
	local HITS = {
		RustyAxe = { 16, 35, 73, 68, 19, 95, 124, 180, 397 },
		SteelAxe = { 6, 13, 27, 25, 7, 35, 45, 66, 145 },
		HardenedAxe = { 4, 8, 16, 15, 4, 21, 27, 39, 86 },
		SilverAxe = { 3, 5, 11, 10, 3, 14, 18, 25, 55 },
		CobaltAxe = { 2, 5, 10, 9, 3, 12, 16, 23, 50 },
		GoldAxe = { 2, 4, 8, 7, 2, 10, 13, 18, 39 },
		ObsidianAxe = { 2, 3, 6, 6, 2, 8, 10, 15, 32 },
		InfernoAxe = { 1, 2, 5, 4, 2, 6, 6, 11, 23 },
		StarfallAxe = { 1, 2, 4, 4, 1, 5, 5, 9, 12 },
	}

	t.test("the hits table: every axe against every wood's mature trunk", function()
		t.eq(GameConfig.WoodUnit, 1.6)
		t.eq(GameConfig.CutK, 1)
		for axeId, row in pairs(HITS) do
			local axe = ItemCatalog.GetAxe(axeId)
			t.ok(axe and axe.v2, axeId .. " has v2 stats")
			for i, woodId in ipairs(WOODS) do
				local wood = WoodData.Get(woodId)
				local damage = ItemCatalog.AxeStats(axe, woodId)
				local hits = SectionLogic.HitsToCut(wood.v2.hardness, wood.v2.shape.trunkThickness, damage)
				t.eq(hits, row[i], string.format("%s on %s", axeId, woodId))
			end
		end
		-- Every axe on the ladder is in the table.
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			t.ok(HITS[axe.id], axe.id .. " is in the hits table")
		end
	end)

	t.test("required damage is hardness times the cut's area in u²", function()
		t.eq(SectionLogic.Required(2, 1.6, 1.6), 2)
		t.ok(math.abs(SectionLogic.Required(2, 2.0, 2.0) - 3.125) < 1e-9, "oak's trunk")
		t.ok(math.abs(SectionLogic.Required(7, 3.2, 0.8) - 7) < 1e-9, "a flat plank cut")
		t.eq(SectionLogic.HitsToCut(7, 1.6, 0), math.huge, "no damage, no cut")
		t.eq(SectionLogic.HitsToCut(7, 1.6, 100), 1, "at least one swing")
		t.eq(SectionLogic.CutSeconds(16, 0.65), 15 * 0.65, "the first swing lands at once")
		t.eq(SectionLogic.CutSeconds(1, 0.65), 0)
	end)

	t.test("hits near a cut add to it; farther ones start a new one", function()
		local cuts = {}
		local a = SectionLogic.AddHit(cuts, 2.0, 1, 11)
		local b = SectionLogic.AddHit(cuts, 2.5, 1, 11) -- 0.5 away: same cut
		t.eq(a, b)
		t.eq(#cuts, 1)
		t.eq(a.damage, 2)
		local c = SectionLogic.AddHit(cuts, 2.0 + GameConfig.CutWindow + 0.05, 1, 12) -- just outside
		t.ok(c ~= a, "a new cut")
		t.eq(#cuts, 2)
		-- Two cuts in reach: the nearest takes it.
		t.eq(SectionLogic.FindCut(cuts, 2.3), 1)
		t.eq(SectionLogic.FindCut(cuts, 2.6), 2)
		t.eq(SectionLogic.FindCut(cuts, 9), nil)
		-- Damage by player, per cut.
		SectionLogic.AddHit(cuts, 2.1, 0.5, 12)
		t.eq(a.damageBy[11], 2)
		t.eq(a.damageBy[12], 0.5)
		t.eq(GameConfig.CutWindow, 0.6)
	end)

	t.test("at most two cuts a section; a third replaces the least damaged", function()
		t.eq(GameConfig.MaxCutsPerSection, 2)
		local cuts = {}
		SectionLogic.AddHit(cuts, 1, 5, 1)
		SectionLogic.AddHit(cuts, 3, 2, 1)
		local third, replaced = SectionLogic.AddHit(cuts, 5, 1, 1)
		t.ok(replaced, "it replaced one")
		t.eq(#cuts, 2)
		t.eq(cuts[1].height, 1, "the most damaged cut stays")
		t.eq(cuts[2], third)
		t.eq(third.damage, 1)
		local _, again = SectionLogic.AddHit(cuts, 5.2, 1, 1)
		t.ok(not again, "a hit on an existing cut replaces nothing")
		t.ok(SectionLogic.IsThrough({ height = 1, damage = 3.125, damageBy = {} }, 3.125))
		t.ok(not SectionLogic.IsThrough({ height = 1, damage = 3.1, damageBy = {} }, 3.125))
	end)

	t.test("cut heights stay CutEdge from a section's ends", function()
		t.eq(GameConfig.CutEdge, 0.3)
		t.eq(SectionLogic.ClampHeight(0, 6), 3, "the middle")
		t.eq(SectionLogic.ClampHeight(-3, 6), 0.3, "at the bottom")
		t.eq(SectionLogic.ClampHeight(-9, 6), 0.3, "past the bottom")
		t.eq(SectionLogic.ClampHeight(2.95, 6), 5.7, "at the top")
		t.eq(SectionLogic.ClampHeight(1, 6), 4)
		t.eq(SectionLogic.ClampHeight(0.2, 0.5), 0.25, "too short: its middle")
	end)

	t.test("a split section keeps its volume, its low half its id and parent", function()
		local s = {
			id = 4,
			parent = 2,
			children = { 5, 6 },
			cf = CFrame.new(1, 2, 3) * CFrame.Angles(0.3, 0.2, 0.1),
			length = 7,
			thickness = 1.3,
		}
		for _, h in ipairs({ 0.3, 1, 3.5, 6.7 }) do
			local low, high = SectionLogic.SplitSection(s, h, 9)
			local whole = SectionLogic.NodeVolume(s)
			t.ok(math.abs(SectionLogic.NodeVolume(low) + SectionLogic.NodeVolume(high) - whole) < 1e-9, "volume kept")
			t.eq(low.id, 4)
			t.eq(low.parent, 2)
			t.eq(low.length, h)
			t.eq(#low.children, 0)
			t.eq(high.id, 9)
			t.eq(high.parent, nil, "the cut parted them")
			t.eq(high.children, { 5, 6 })
			t.eq(high.thickness, 1.3)
			t.ok((high.cf.Position - (s.cf * Vector3.new(0, h, 0))).Magnitude < 1e-5, "the high half starts at the cut")
			t.ok((low.cf.Position - s.cf.Position).Magnitude < 1e-9, "the low half's bottom stays")
		end
		t.ok(math.abs(SectionLogic.Volume(1.6, 1.6, 1.6) - 1) < 1e-9, "one u³")
		t.ok(math.abs(SectionLogic.Value(26, 1.5) - 39) < 1e-9, "26 u³ of oak is $39")
	end)

	t.test("cutting any section of a tree leaves exactly two pieces", function()
		for _, woodId in ipairs(WOODS) do
			for _, seed in ipairs({ 1, 2, 3 }) do
				local skel = TreeGen.Skeleton(woodId, seed, 1)
				local graph = {}
				for _, s in ipairs(skel.sections) do
					graph[s.id] = s
				end
				local total = SectionLogic.GraphVolume(graph)
				local n = #skel.sections
				for _, s in ipairs(skel.sections) do
					local newId = n + 1
					local a, b = SectionLogic.SplitGraph(graph, s.id, s.length * 0.4, newId)
					local count, inBoth = 0, false
					for id in pairs(a) do
						count += 1
						inBoth = inBoth or b[id] ~= nil
					end
					for _ in pairs(b) do
						count += 1
					end
					t.ok(not inBoth, woodId .. ": a section in both pieces")
					t.eq(count, n + 1, woodId .. ": every section and the new half in one piece")
					t.ok(a[s.id] and b[newId], woodId .. ": the low half and the high half")
					t.ok(
						math.abs(SectionLogic.GraphVolume(a) + SectionLogic.GraphVolume(b) - total) < 1e-6,
						woodId .. ": volume kept"
					)
					-- The root stays with the low piece; the cut section's
					-- descendants all go with the high one.
					t.ok(a[1], woodId .. ": the root stays with the low piece")
					local stack = table.clone(s.children)
					while #stack > 0 do
						local id = table.remove(stack)
						t.ok(b[id], woodId .. ": a descendant left behind")
						for _, c in ipairs(graph[id].children) do
							table.insert(stack, c)
						end
					end
					for _, c in ipairs(s.children) do
						t.eq(b[c].parent, newId, woodId .. ": children hang on the high half")
					end
					-- Each piece holds together.
					local reachA = SectionLogic.Reach(a, s.id)
					local reachB = SectionLogic.Reach(b, newId)
					for id in pairs(a) do
						t.ok(reachA[id], woodId .. ": piece A in bits")
					end
					for id in pairs(b) do
						t.ok(reachB[id], woodId .. ": piece B in bits")
					end
				end
				-- The graph given is untouched.
				t.eq(SectionLogic.GraphVolume(graph), total)
				t.eq(graph[1].parent, nil)
			end
		end
		t.fails(function()
			SectionLogic.SplitGraph({}, 1, 1, 2)
		end, "no section")
	end)

	t.test("a piece splits again the same way (cut a fallen trunk in two)", function()
		local skel = TreeGen.Skeleton("pine", 1, 1)
		local graph = {}
		for _, s in ipairs(skel.sections) do
			graph[s.id] = s
		end
		-- Fell it: cut section 1 at 1.2.
		local stub, felled = SectionLogic.SplitGraph(graph, 1, 1.2, 100)
		t.ok(stub[1] and not stub[2], "the stub is just the low half")
		-- Buck the felled piece at its third section.
		local a, b = SectionLogic.SplitGraph(felled, 3, 2, 101)
		t.ok(a[100] and a[2] and a[3], "the butt end")
		t.ok(b[101] and b[4], "the top end")
		t.eq(SectionLogic.Largest(a) ~= nil, true)
	end)

	t.test("offcuts under MinPieceVolume are chips", function()
		t.eq(GameConfig.MinPieceVolume, 0.05)
		t.ok(SectionLogic.IsChips(0.049))
		t.ok(not SectionLogic.IsChips(0.05))
		-- A 0.3-stud slice of a birch twig is chips; of an oak trunk, it isn't.
		t.ok(SectionLogic.IsChips(SectionLogic.Volume(0.5, 0.3, 0.5)))
		t.ok(not SectionLogic.IsChips(SectionLogic.Volume(2, 0.3, 2)))
	end)

	t.test("a freed piece is the top contributor's, the swinger keeping a tie", function()
		local cut = { height = 1, damage = 10, damageBy = { [1] = 6, [2] = 4 } }
		t.eq(SectionLogic.Owner(cut, 2), 1, "the last swing can't steal it")
		t.eq(SectionLogic.Owner(cut, 1), 1)
		local tie = { height = 1, damage = 10, damageBy = { [1] = 5, [2] = 5 } }
		t.eq(SectionLogic.Owner(tie, 2), 2, "a tie stays with the swinger")
		t.eq(
			SectionLogic.Owner(cut, 2, function(id)
				return id ~= 1
			end),
			2,
			"someone who left doesn't count"
		)
		t.eq(SectionLogic.Owner({ height = 1, damage = 0, damageBy = {} }, 7), 7)
	end)

	t.test("the biggest section of a piece", function()
		local g = {
			[1] = { id = 1, children = { 2 }, cf = CFrame.identity, length = 2, thickness = 1 },
			[2] = { id = 2, parent = 1, children = {}, cf = CFrame.identity, length = 5, thickness = 1 },
		}
		t.eq(SectionLogic.Largest(g), 2)
		t.eq(SectionLogic.Largest({}), nil)
	end)

	-- M1.3: where a swing lands (CutController aims, SectionTrees checks).
	t.test("a swing at a standing trunk goes in between knee and chest, on the side facing you", function()
		local trunk = CFrame.new(0, 2.25, 0) -- a 2 x 4.5 x 2 section, its bottom on the ground
		local size = Vector3.new(2, 4.5, 2)
		local root = Vector3.new(5, 3, 0) -- the root part 3 studs above the feet
		local hit, normal = SectionLogic.AimAt(trunk, size, root, nil, nil)
		t.ok(math.abs(hit.Y - 3) < 1e-5, "no pointer: the root part's height")
		t.ok((normal - Vector3.xAxis).Magnitude < 1e-5, "the face toward you")
		t.ok(math.abs(hit.X - 1) < 1e-5, "on the bark")
		-- Pointing at your feet or over your head is kept knee to chest.
		local low = SectionLogic.AimAt(trunk, size, root, Vector3.new(1, 0.2, 0), Vector3.xAxis)
		t.ok(math.abs(low.Y - (3 + SectionLogic.KneeAbove)) < 1e-5, "knee: " .. low.Y)
		local high = SectionLogic.AimAt(trunk, size, root, Vector3.new(1, 4.4, 0), Vector3.xAxis)
		t.ok(math.abs(high.Y - (3 + SectionLogic.ChestAbove)) < 1e-5, "chest")
		-- Inside the band the pointer's height counts, so different heights stay apart.
		local a = SectionLogic.AimAt(trunk, size, root, Vector3.new(1, 2.0, 0), Vector3.xAxis)
		local b = SectionLogic.AimAt(trunk, size, root, Vector3.new(1, 3.6, 0), Vector3.xAxis)
		t.ok(math.abs(a.Y - b.Y) > 1.2, "a different height each swing")
		-- Standing on a slope above the trunk: kept CutEdge inside its ends.
		local edge = SectionLogic.AimAt(trunk, size, Vector3.new(5, 12, 0), nil, nil)
		t.ok(math.abs(edge.Y - (4.5 - 0.3)) < 1e-5, "never past the end")
		-- The pointer's side face wins over the side toward you.
		local _, side = SectionLogic.AimAt(trunk, size, root, Vector3.new(0, 3, -1), Vector3.new(0, 0, -1))
		t.ok((side - Vector3.new(0, 0, -1)).Magnitude < 1e-5)
	end)

	t.test("a log on the ground is cut where you point; the box check allows 0.6", function()
		local log = CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.pi / 2) -- length along world X
		local size = Vector3.new(2, 8, 2)
		local hit, normal = SectionLogic.AimAt(log, size, Vector3.new(0, 3, 4), Vector3.new(2.5, 2, 0), Vector3.yAxis)
		t.ok(math.abs(hit.X - 2.5) < 1e-6, "along the log where you pointed")
		t.ok(normal.Magnitude > 0.99)
		local h = SectionLogic.HeightOn(log, size, hit)
		t.ok(h > 0 and h < 8, "a height up the section")
		t.ok(SectionLogic.InBox(log, size, Vector3.new(0, 2.5, 0)))
		t.ok(not SectionLogic.InBox(log, size, Vector3.new(0, 2.7, 0)), "past the 0.6 margin")
		t.eq(SectionLogic.Message("far"), "Too far away. Walk closer to cut.")
		t.eq(SectionLogic.Message("cooldown"), nil, "a swing too soon is quiet")
	end)

	t.test("a claim keeps others off a tree while its holder is here and has hit it within TreeClaimSec", function()
		local GameConfig = t.shared("GameConfig")
		t.eq(GameConfig.TreeClaimSec, 60)
		local here = { [1] = true, [2] = true }
		local function isHere(id)
			return here[id] == true
		end
		local claim = { userId = 1, at = 100 }
		t.eq(SectionLogic.ClaimBlocks(nil, 2, 100, false, isHere), nil, "no claim: anyone")
		t.eq(SectionLogic.ClaimBlocks(claim, 1, 150, false, isHere), nil, "your own")
		t.eq(SectionLogic.ClaimBlocks(claim, 2, 150, false, isHere), 1, "someone else's, fresh")
		t.eq(SectionLogic.ClaimBlocks(claim, 2, 159.9, false, isHere), 1, "just inside")
		t.eq(SectionLogic.ClaimBlocks(claim, 2, 160, false, isHere), nil, "lapsed at TreeClaimSec")
		t.eq(SectionLogic.ClaimBlocks(claim, 2, 101, true, isHere), nil, "an Elder is everyone's")
		here[1] = nil
		t.eq(SectionLogic.ClaimBlocks(claim, 2, 101, false, isHere), nil, "its holder left")
		t.eq(SectionLogic.Message("claimed", "Dale"), "Dale is cutting this tree. Find another one.")
		t.eq(SectionLogic.Message("claimed"), "Someone is cutting this tree. Find another one.")
	end)
end
