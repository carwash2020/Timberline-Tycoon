--!nocheck
-- NearGrove (WORLD-SPREAD, T349): oak clumps round the spawn. They come after
-- every older tree, stand where the town allows them, keep the walking
-- corridors and the spawn view clear, and add to what a new player meets.
return function(t)
	local roblox = t.roblox
	local Vector2 = roblox.Vector2
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local NearGrove = t.load("ReplicatedStorage/Shared/World/NearGrove")
	local TreeFill = t.load("ReplicatedStorage/Shared/World/TreeFill")
	local TutorialGrove = t.shared("TutorialGrove")
	local PlotData = t.shared("PlotData")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TreeSpread = t.load("ReplicatedStorage/Shared/World/TreeSpread")

	local grove = WorldPlan.NearGrove()

	local function dist(x, z, ox, oz)
		return math.sqrt((x - ox) ^ 2 + (z - oz) ^ 2)
	end

	-- Every choppable tree on the ground that is not in Trees(): Murph's oaks and the clumps.
	local function nearSpawn(radius)
		local n = 0
		local function count(x, z)
			if dist(x, z, NearGrove.SpawnX, NearGrove.SpawnZ) <= radius then
				n += 1
			end
		end
		for _, spot in ipairs(WorldPlan.Trees()) do
			count(spot.position.X, spot.position.Z)
		end
		for _, spot in ipairs(WorldPlan.StripTrees()) do
			count(spot.position.X, spot.position.Z)
		end
		for _, spot in ipairs(TutorialGrove.Trees) do
			count(spot.x, spot.z)
		end
		for _, spot in ipairs(grove) do
			count(spot.position.X, spot.position.Z)
		end
		return n
	end

	t.test("at least 8 choppable trees stand within 70 studs of the spawn pad", function()
		t.ok(nearSpawn(70) >= 8, "trees within 70: " .. nearSpawn(70))
		print(string.format("NearGrove: %d new trees; %d trees within 70 studs of the pad", #grove, nearSpawn(70)))
	end)

	t.test("at least 4 trees stand within 40 studs of the first plot pad's footprint", function()
		-- The pad's biggest footprint, the box TreeFill keeps its distance from.
		local pad = PlotData.Slots[1]
		local half = PlotData.Tiers[#PlotData.Tiers].size / 2
		local n = 0
		for _, spot in ipairs(WorldPlan.Trees()) do
			local dx = math.max(math.abs(spot.position.X - pad.X) - half, 0)
			local dz = math.max(math.abs(spot.position.Z - pad.Y) - half, 0)
			if math.sqrt(dx * dx + dz * dz) <= 40 then
				n += 1
			end
		end
		t.ok(n >= 4, "trees within 40 of the first pad's footprint: " .. n)
	end)

	t.test("the clumps are oak, odd (3 or 5), each in its own zone capped at its count", function()
		t.ok(#grove >= 3, "at least one clump")
		local byZone, order = {}, {}
		for _, spot in ipairs(grove) do
			t.eq(spot.woodId, "oak")
			t.eq(spot.biome, "wild")
			t.ok(spot.zone ~= nil)
			local id = spot.zone.id
			if not byZone[id] then
				byZone[id] = { zone = spot.zone, n = 0 }
				table.insert(order, id)
			end
			byZone[id].n += 1
			t.ok(TreeSpread.WoodsNear(spot.position.X, spot.position.Z)[1].woodId == "oak", "oak by the spawn rule")
		end
		for _, id in ipairs(order) do
			local entry = byZone[id]
			t.ok(entry.n == 3 or entry.n == 5, id .. " has " .. entry.n)
			t.eq(entry.zone.cap, entry.n)
			t.ok(string.sub(id, 1, 10) == "neargrove:")
		end
	end)

	t.test("every tree is on legal ground: clear of plots and doors, town ground, 10 studs from the others", function()
		local others = {}
		for _, spot in ipairs(WorldPlan.Trees()) do
			table.insert(others, spot.position)
		end
		for _, spot in ipairs(TutorialGrove.Trees) do
			table.insert(others, roblox.Vector3.new(spot.x, 0, spot.z))
		end
		for i, spot in ipairs(grove) do
			local p = spot.position
			t.ok(TreeFill.Clear(p.X, p.Z), "TreeFill.Clear")
			t.ok(TreeFill.TownGround(p.X, p.Z), "TownGround")
			t.ok(TreeFill.GroundFor(spot.zone, p.X, p.Z), "GroundFor the zone")
			t.ok(not TreeFill.TakenNearScan(others, p.X, p.Z, NearGrove.Gap), "10 studs from every older tree")
			for j = 1, i - 1 do
				t.ok((grove[j].position - p).Magnitude >= NearGrove.Gap, "10 studs between clump trees")
			end
			local d = dist(p.X, p.Z, NearGrove.SpawnX, NearGrove.SpawnZ)
			t.ok(d >= NearGrove.Inner and d <= NearGrove.Outer, "inside the ring")
		end
	end)

	t.test("the walking corridors stay 24 wide and the middle of the spawn view stays open", function()
		local pad = Vector2.new(NearGrove.SpawnX, NearGrove.SpawnZ)
		local plot = PlotData.Slots[1]
		local sell = Vector2.new(NearGrove.SellStand.x, NearGrove.SellStand.z)
		for _, spot in ipairs(grove) do
			local p = Vector2.new(spot.position.X, spot.position.Z)
			t.ok((WorldLayout.SegmentDistance(p, pad, plot)) >= 12, "pad to the first plot")
			t.ok((WorldLayout.SegmentDistance(p, pad, sell)) >= 12, "pad to the sell stand")
			local off = p - pad
			local angle = math.deg(math.acos(math.clamp(off.Y / off.Magnitude, -1, 1)))
			t.ok(angle > NearGrove.ConeDegrees, "outside the middle 40 percent of the phone frame")
		end
	end)

	t.test("planning twice gives the same trees, and Trees() itself is untouched", function()
		local standing = {}
		for _, spot in ipairs(WorldPlan.FirstTrees()) do
			table.insert(standing, spot.position)
		end
		for _, spot in ipairs(WorldPlan.Trees()) do
			if spot.zone and string.sub(spot.zone.id, 1, 5) == "town:" then
				table.insert(standing, spot.position)
			end
		end
		local again = NearGrove.Plan(standing)
		t.eq(#again, #grove)
		for i, spot in ipairs(grove) do
			t.eq(again[i].position, spot.position)
			t.eq(again[i].zone.id, spot.zone.id)
		end
		for _, spot in ipairs(WorldPlan.Trees()) do
			t.ok(not spot.zone or string.sub(spot.zone.id, 1, 10) ~= "neargrove:", "none of them is in Trees()")
		end
	end)
end
