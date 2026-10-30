--!nocheck
-- Footpaths (T406): the town's paths and walkways are all built and show.
-- T402 made eight TrailDirt footpaths (TownGround kind "Path"); the count is
-- pinned so one cannot go missing again, each is built as a visible part, and
-- GroundLift keeps a part from being buried by the drawn terrain.
return function(t)
	local TownGround = t.load("ReplicatedStorage/Shared/World/TownGround")
	local TownGroundArt = t.load("ReplicatedStorage/Shared/Art/TownGroundArt")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local GroundLift = t.load("ReplicatedStorage/Shared/World/GroundLift")

	local EXPECTED = {
		SpawnWalk = 1,
		HearthAndHomePath = 3,
		ToolShedPath = 1,
		SparkworksPath = 1,
	}

	local function paths()
		local out = {}
		for _, p in ipairs(TownGround.Pieces()) do
			if p.kind == "Path" then
				table.insert(out, p)
			end
		end
		return out
	end

	t.test("six footpaths, by name, as the town builds them", function()
		local list = paths()
		t.eq(#list, 6)
		local seen = {}
		for _, p in ipairs(list) do
			seen[p.name] = (seen[p.name] or 0) + 1
		end
		t.eq(seen, EXPECTED)
	end)

	t.test("each footpath piece: TrailDirt, Ground, 8 wide, flush with the graded ground at both ends", function()
		for _, p in ipairs(paths()) do
			t.eq(p.color:ToHex(), "8E6C4A", p.name)
			t.eq(p.material, "Ground", p.name)
			t.eq(p.width, 8, p.name)
			t.ok(not p.collide, p.name)
			t.ok(math.abs(p.ya - TerrainGen.HeightAt(p.a.X, p.a.Y)) < 1e-6, p.name .. " start on the ground")
			t.ok(math.abs(p.yb - TerrainGen.HeightAt(p.b.X, p.b.Y)) < 1e-6, p.name .. " end on the ground")
		end
	end)

	t.test("built: TownPaths exists and the walk is terrain, not a flat strip", function()
		local root = TownGroundArt.Build()
		local group = root:FindFirstChild("TownPaths")
		t.ok(group, "the TownPaths model exists")
		local parts = 0
		for _, child in ipairs(group:GetChildren()) do
			if child:IsA("BasePart") then
				parts += 1
			end
		end
		t.eq(parts, 0, "a footpath is paint")
		for _, p in ipairs(paths()) do
			local x, z = (p.a.X + p.b.X) / 2, (p.a.Y + p.b.Y) / 2
			local _, material = TerrainGen.Sample(x, z)
			t.eq(material, "Ground", p.name)
		end
	end)

	t.test("GroundLift: a part the terrain would bury is raised to 0.05 over it; one that shows is left", function()
		t.eq(GroundLift.Needed(1.1, nil), 0, "no hit, no change")
		t.eq(GroundLift.Needed(1.1, 0.5), 0, "the terrain is under it")
		t.eq(GroundLift.Needed(1.1, 1.06), 0, "0.04 clear: it shows")
		t.ok(math.abs(GroundLift.Needed(1.1, 1.08) - 0.03) < 1e-9, "0.02 clear: up to 0.05")
		t.ok(math.abs(GroundLift.Needed(1.1, 1.3) - 0.25) < 1e-9, "buried by 0.2: up 0.25")
		t.ok(math.abs(GroundLift.Needed(1.1, 1.1) - 0.05) < 1e-9, "flush: up 0.05")
		t.eq(GroundLift.Needed(1.1, 9), 0, "a hill 8 studs up is not ours to hide")
		t.eq(GroundLift.Needed(1.1, 0 / 0), 0)
	end)
end
