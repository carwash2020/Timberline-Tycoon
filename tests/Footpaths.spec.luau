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

	t.test("each footpath piece: TrailDirt, Ground, 6 wide, 0.1 over the graded ground at both ends", function()
		for _, p in ipairs(paths()) do
			t.eq(p.color:ToHex(), "8E6C4A", p.name)
			t.eq(p.material, "Ground", p.name)
			t.eq(p.width, 6, p.name)
			t.ok(p.collide, p.name)
			t.ok(math.abs(p.ya - (TerrainGen.HeightAt(p.a.X, p.a.Y) + 0.1)) < 1e-6, p.name .. " start on the ground")
			t.ok(math.abs(p.yb - (TerrainGen.HeightAt(p.b.X, p.b.Y) + 0.1)) < 1e-6, p.name .. " end on the ground")
		end
	end)

	t.test("built: six visible parts, Transparency 0, 6 wide, TrailDirt, in TownPaths", function()
		local root = TownGroundArt.Build()
		local group = root:FindFirstChild("TownPaths")
		t.ok(group, "the TownPaths model exists")
		local parts = group:GetChildren()
		t.eq(#parts, 6)
		for _, part in ipairs(parts) do
			t.eq(part.Transparency, 0, part.Name)
			t.eq(part.Color:ToHex(), "8E6C4A", part.Name)
			t.eq(part.Size.X, 6, part.Name .. " is 6 wide")
			t.eq(part.Material, t.roblox.Enum.Material.Ground, part.Name)
			t.ok(part.Size.Z >= 3, part.Name .. " has length")
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
