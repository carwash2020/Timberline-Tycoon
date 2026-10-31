--!nocheck
-- Road critters (T414d-2): client-only, looks only, capped per quality, one Heartbeat loop, never into a
-- road, lane, door or belt box.
return function(t)
	local fs = require("@lune/fs")
	local CritterArt = t.load("ReplicatedStorage/Shared/Art/CritterArt")
	local Logic = t.load("ReplicatedStorage/Shared/World/RoadCritterLogic")
	local Scatter = t.load("ReplicatedStorage/Shared/World/Scatter")
	local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/RoadCritters.luau")

	t.test("every road critter template is looks only: no collide, no query, no touch", function()
		for _, kind in ipairs(CritterArt.RoadKinds) do
			local model = CritterArt.RoadTemplate(kind, 7)
			t.eq(model:GetAttribute("Critter"), kind)
			local parts = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					parts += 1
					t.ok(not d.CanCollide and not d.CanQuery and not d.CanTouch, kind .. "/" .. d.Name)
				end
			end
			t.ok(parts > 5, kind .. " has parts")
			t.ok(CritterArt.IsSilent(model))
		end
	end)

	t.test("the cap is 12 on a phone and 40 on high, and never more", function()
		t.eq(CritterArt.RoadCapFor("low"), 12)
		t.eq(CritterArt.RoadCapFor("high"), 40)
		t.ok(CritterArt.RoadCapFor("medium") > 12 and CritterArt.RoadCapFor("medium") < 40)
		t.eq(CritterArt.RoadCapFor("nonsense"), 40)
		t.ok(string.find(source, "RoadCapFor(Quality.Tier())", 1, true), "the spawn is gated by the tier's cap")
		t.ok(string.find(source, "#live < ", 1, true), "and only below it")
	end)

	t.test("the client module is one Heartbeat loop with no remote, tween, server part or save", function()
		local _, loops = string.gsub(source, "Heartbeat:Connect", "")
		t.eq(loops, 1)
		for _, banned in ipairs({ "RemoteEvent", "RemoteFunction", "FireServer", "TweenService", "DataStore", "wait(" }) do
			local first = string.find(source, banned, 1, true)
			-- task.wait( is allowed; a bare wait( is not.
			if banned == "wait(" then
				first = string.find(string.gsub(source, "task%.wait%(", ""), "wait(", 1, true)
			end
			t.ok(first == nil, "RoadCritters uses " .. banned)
		end
		t.ok(
			string.find(source, "ActiveRange", 1, true) and string.find(source, "DespawnRange", 1, true),
			"range gates"
		)
	end)

	t.test("a critter flees straight away, turns round what it may not enter, and freezes when boxed in", function()
		local dx, dz = Logic.Flee(0, 0, -10, 0, function()
			return false
		end)
		t.ok(math.abs(dx - 1) < 1e-9 and math.abs(dz) < 1e-9, "straight away from the threat")
		-- A wall to the east: it turns.
		local tx, tz = Logic.Flee(0, 0, -10, 0, function(x)
			return x > 3
		end)
		t.ok(tx and tx < 0.8, "it turns away from the wall")
		-- Boxed in: none.
		local nx = Logic.Flee(0, 0, -10, 0, function()
			return true
		end)
		t.eq(nx, nil)
	end)

	t.test("on the real verge no heading it picks enters a keep-out (road, door, lane, town, water)", function()
		local checked = 0
		local blocked = function(x, z)
			return Scatter.KeepOut(x, z, 1) ~= nil
		end
		for i, item in ipairs(Scatter.Cover()) do
			if item.kind == "grass" and item.road and i % 40 == 0 then
				-- A player on the road side of the spot, so the critter runs along and away.
				local dx, dz = Logic.Flee(item.x, item.z, item.x + 12, item.z - 9, blocked)
				if dx then
					for _, d in ipairs(Logic.Probes) do
						t.ok(not blocked(item.x + dx * d, item.z + dz * d), "heading enters a keep-out at probe " .. d)
					end
					checked += 1
				end
			end
		end
		t.ok(checked > 5, "checked " .. checked)
	end)

	t.test("kinds follow the region and every kind is a template", function()
		local seen = {}
		for _, region in ipairs({ "hills", "country", "snow", "bayou" }) do
			for roll = 0, 0.99, 0.05 do
				seen[Logic.KindFor(region, roll)] = true
			end
		end
		for _, kind in ipairs(CritterArt.RoadKinds) do
			t.ok(seen[kind], kind)
		end
		for kind in pairs(seen) do
			t.ok(table.find(CritterArt.RoadKinds, kind), kind)
		end
	end)
end
