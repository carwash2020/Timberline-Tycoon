--!nocheck
-- BuiltMoves (T409): the eight pieces the world overlap lint found inside other pieces are moved where they
-- are built, and WorldPlan's own lists (which the pinned tree plan keeps off) stay as they were.
return function(t)
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local BuiltMoves = t.load("ReplicatedStorage/Shared/World/BuiltMoves")
	local Vector3 = t.roblox.Vector3

	local function near(a, b, d)
		return (a - b).Magnitude < d
	end

	t.test("the planning lists are untouched (the tree plan is pinned against them)", function()
		t.ok(near(WorldPlan.Boulders()[58].position, Vector3.new(-730.24, -0.93, -86.47), 0.05))
		t.ok(near(WorldPlan.MeadowBoulders()[16].position, Vector3.new(-196.54, -1.38, 118.06), 0.05))
		t.ok(near(WorldPlan.MeadowBoulders()[9].position, Vector3.new(53.62, 2.76, 266.38), 0.05))
		t.eq(WorldPlan.Town().fences[1].length, 20)
		t.eq(WorldPlan.Town().fences[3].noEndPosts, nil)
	end)

	t.test("the boulders stand on the ground where they are built, clear of what they were in", function()
		local a = BuiltMoves.Boulders(WorldPlan, TerrainGen)[58]
		t.ok(near(Vector3.new(a.position.X, 0, a.position.Z), Vector3.new(-728.5, 0, -79.5), 0.01))
		t.ok(
			math.abs(a.position.Y - (TerrainGen.HeightAt(-728.5, -79.5) - 0.6)) < 1e-6,
			"sunk 0.6 into the ground like every boulder"
		)
		t.ok(a.position.Z > -85 + a.size, "past the Secret Cave's back wall (z -85)")
		local m = BuiltMoves.MeadowBoulders(WorldPlan, TerrainGen)
		t.ok(m[16].position.Z > 118.8 + m[16].size / 2, "south of the ruined cabin (its back wall at z 118.8)")
		t.ok(m[9].position.Z < 265.2 - m[9].size / 2, "south of log pile 3 (its edge at z 265.2)")
		-- every other boulder is the planned one
		local plan = WorldPlan.Boulders()
		local built = BuiltMoves.Boulders(WorldPlan, TerrainGen)
		for i, b in ipairs(plan) do
			if i ~= 58 then
				t.ok(built[i] == b, "boulder " .. i .. " moved")
			end
		end
	end)

	t.test("log pile 32 stands outside the cave, on the ground, resting on its lowest side", function()
		local plan = WorldPlan.Scenery()[32]
		local built = BuiltMoves.Scenery(WorldPlan, TerrainGen)[32]
		t.eq(built.kind, "LogPile")
		t.ok(built.center.Z < -114.5 - 3, "south of the cave's wall (z -114)")
		local lowest = math.huge
		for _, q in ipairs(WorldPlan.SceneryFootprint(built.center.X, built.center.Z, built.radius)) do
			lowest = math.min(lowest, TerrainGen.HeightAt(q.X, q.Y))
		end
		t.ok(
			math.abs(built.center.Y - (lowest - 0.1)) < 1e-6,
			"its base on the lowest ground under it, as the generator sets every piece down"
		)
		local delta = built.center - plan.center
		t.ok(
			near(built.items[1].cframe.Position - plan.items[1].cframe.Position, delta, 1e-6),
			"its items moved with it"
		)
	end)

	t.test("the paddock's rails stop 0.5 clear of Hearth & Home, fence 3 has no corner posts of its own", function()
		local f = BuiltMoves.Fences(WorldPlan.Town().fences)
		t.eq(#f, #WorldPlan.Town().fences)
		for i = 1, 2 do
			t.eq(f[i].length, 2)
			t.ok(math.abs(f[i].cframe.X - -127) < 1e-6)
			-- the end post stands at x -126: its east face, x -125.7, is 0.5 from the wall's west face (-125.2)
			t.ok(f[i].cframe.X + f[i].length / 2 + 0.3 <= -125.2 - 0.5 + 1e-6)
		end
		t.eq(f[3].noEndPosts, true)
		t.eq(f[4].noEndPosts, nil)
	end)

	t.test(
		"the Skyroot sign: clear of the road and level, still facing the road, 5.7 studs from where it was",
		function()
			local text = WorldPlan.BiomeSignText
			local plan = WorldPlan.RoadSigns(text)[4]
			local built = BuiltMoves.RoadSigns(WorldPlan, TerrainGen, text)[4]
			t.eq(built.text, plan.text)
			t.ok(near(Vector3.new(built.cframe.X, 0, built.cframe.Z), Vector3.new(683.09, 0, 305.43), 0.01))
			t.ok(built.cframe.LookVector:Dot(plan.cframe.LookVector) > 0.9999, "facing the same way")
			for _, side in ipairs({ -5.3, 5.3 }) do
				local p = built.cframe * Vector3.new(side, 0, 0)
				t.ok(TerrainGen.RoadClearance(p.X, p.Z) >= 2, "a post at " .. side .. " is clear of the road")
			end
			local signs = BuiltMoves.RoadSigns(WorldPlan, TerrainGen, text)
			for i, s in ipairs(WorldPlan.RoadSigns(text)) do
				if i ~= 4 then
					t.eq(signs[i].text, s.text)
					t.ok(near(signs[i].cframe.Position, s.cframe.Position, 1e-6), "road sign " .. i .. " moved")
				end
			end
		end
	)
end
