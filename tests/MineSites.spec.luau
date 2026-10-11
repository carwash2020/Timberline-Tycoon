--!nocheck
-- MineSites: the fallback constants, and an UndergroundData table when one is passed in.

return function(t)
	local MineSites = t.load("ReplicatedStorage/Shared/Mining/MineSites")

	t.test("the fallback matches the map note", function()
		local sites = MineSites.Fallback()
		t.eq(sites.source, "fallback")
		t.eq(sites.furnace.x, 48)
		t.eq(sites.furnace.z, -110)
		t.eq(sites.furnace.sx, 30)
		t.eq(sites.furnace.sz, 24)
		t.eq(sites.mouth.x, 150)
		t.eq(sites.mouth.z, -150)
		local ids = {}
		for _, wall in ipairs(sites.rubble) do
			table.insert(ids, wall.id .. ":" .. wall.tier)
		end
		t.eq(ids, { "mine-mid:2", "mine-deep:3", "hidden-hills:2", "hidden-peak:3", "hidden-lava:3" })
		local tiers = { 0, 0, 0 }
		for _, anchor in ipairs(sites.anchors) do
			tiers[anchor.tier] += 1
			t.ok(anchor.tier >= 1 and anchor.tier <= 3)
		end
		t.ok(tiers[1] >= 4 and tiers[2] >= 4 and tiers[3] >= 4)
		local mid = nil
		for _, wall in ipairs(sites.rubble) do
			if wall.id == "mine-mid" then
				mid = wall
			end
			t.eq(type(wall.ex), "number")
			t.eq(type(wall.ez), "number")
		end
		t.ok(mid.ez > 0, "mine-mid opens toward the mouth")
	end)

	t.test("an UndergroundData table replaces the fallback", function()
		local sites = MineSites.FromUnderground({
			FurnaceSite = { x = 10, y = -4, z = 20, sx = 30, sz = 24 },
			Mouth = { x = 1, z = 2 },
			MineAnchors = { { tier = 2, x = 3, y = 4, z = 5 } },
			Rubble = { { id = "mine-mid", tier = 2, x = 8, y = 0, z = 9 } },
		})
		t.eq(sites.source, "underground")
		t.eq(sites.furnace.x, 10)
		t.eq(sites.furnace.y, -4)
		t.eq(sites.mouth.x, 1)
		t.eq(#sites.anchors, 1)
		t.eq(sites.anchors[1].tier, 2)
		t.eq(sites.rubble[1].id, "mine-mid")
		t.eq(type(sites.rubble[1].ex), "number")
		t.eq(type(sites.rubble[1].ez), "number")
	end)

	t.test("live anchors and rubble win over the table", function()
		local sites = MineSites.MergeLive(MineSites.Fallback(), {
			{ tier = 1, x = 1, y = 2, z = 3 },
		}, {
			{ id = "hidden-lava", tier = 3, x = 4, y = 5, z = 6 },
		})
		t.eq(sites.source, "live")
		t.eq(#sites.anchors, 1)
		t.eq(sites.anchors[1].x, 1)
		t.eq(sites.rubble[1].id, "hidden-lava")
		t.eq(type(sites.rubble[1].ex), "number")
		t.eq(type(sites.rubble[1].ez), "number")
	end)

	t.test("with no module, Current is the fallback", function()
		-- UndergroundData ships with the ring map (Lane B), so hide it here.
		local find = MineSites.FindModule
		MineSites.FindModule = function()
			return nil
		end
		local sites = MineSites.Current(nil)
		t.eq(sites.source, "fallback")
		t.eq(MineSites.Current("nope").source, "fallback")
		MineSites.FindModule = find
	end)

	t.test("with the ring map's UndergroundData, Current reads it, not the fallback", function()
		local sites = MineSites.Current(nil)
		t.ok(sites.source ~= "fallback", "source " .. tostring(sites.source))
		t.eq(sites.mouth.x, 150)
		t.eq(sites.mouth.z, -150)
	end)
end
