--!nocheck
-- Lane R: the Bayou's mud. 0.6x inside a disc without Wader Boots, 1.0x with
-- them, and always full speed on the road, the landing and the boardwalk.
return function(t)
	local MudLogic = t.load("ReplicatedStorage/Shared/Regions/MudLogic")
	local BayouData = t.load("ReplicatedStorage/Shared/Regions/BayouData")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")

	local none = {}
	local boots = { WaderBoots = true }

	t.test("the middle of a mud disc is 0.6x without boots and 1.0x with them", function()
		for _, z in ipairs(BayouData.MudZones) do
			t.eq(MudLogic.Factor(z.x, z.z, none), 0.6, z.id)
			t.eq(MudLogic.Factor(z.x, z.z, boots), 1, z.id .. " with boots")
		end
		t.eq(MudLogic.Slow, 0.6)
	end)

	t.test("just outside a disc is full speed", function()
		for _, z in ipairs(BayouData.MudZones) do
			t.eq(MudLogic.Factor(z.x + z.radius + 0.5, z.z, none), 1, z.id)
		end
	end)

	t.test("the log landing, the boardwalk ring and the shack are dry, and so is the junction", function()
		local l = BayouData.Landing
		t.eq(MudLogic.IsDry(l.x, l.z), true)
		local b = BayouData.Boardwalk
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			t.eq(MudLogic.IsDry(b.x + math.cos(a) * b.radius, b.z + math.sin(a) * b.radius), true, "plank " .. i)
		end
		local s = BayouData.Shack
		t.eq(MudLogic.IsDry(s.x, s.z), true)
		local j = BayouData.Junction
		t.eq(MudLogic.IsDry(j.x, j.z), true)
	end)

	t.test("a dry footprint wins over a mud disc that overlaps it", function()
		-- A disc laid over the landing: the landing stays full speed.
		local l = BayouData.Landing
		local discs = { { x = l.x, z = l.z, radius = 25 } }
		t.eq(MudLogic.Factor(l.x, l.z, none, discs), 1)
		t.eq(MudLogic.Factor(l.x + 18, l.z, none, discs), 1, "still on the landing")
	end)

	t.test("BayouRoad itself touches no mud disc", function()
		local road = nil
		for _, r in ipairs(WorldLayout.Roads) do
			if r.name == "BayouRoad" then
				road = r
			end
		end
		local a, b = road.points[1], road.points[2]
		for i = 0, 100 do
			local u = i / 100
			local x, z = a.X + (b.X - a.X) * u, a.Y + (b.Y - a.Y) * u
			t.eq(MudLogic.Factor(x, z, none), 1, "the road at " .. i)
		end
	end)

	t.test("outside the Bayou nothing is slow, even over a stray disc", function()
		t.eq(MudLogic.Factor(0, 0, none), 1)
		t.eq(MudLogic.Factor(0 / 0, 0, none), 1)
		t.eq(MudLogic.Factor(0, 0, none, { { x = 0, z = 0, radius = 10 } }), 1, "the boots and the mud are the Bayou's")
		t.eq(MudLogic.InBayou(BayouData.Centre.x, BayouData.Centre.z), true)
		t.eq(MudLogic.InBayou(0, 0), false)
	end)

	t.test("BiomeService applies the factor inside its WalkSpeed step, not a second timer", function()
		local fs = require("@lune/fs")
		local text = fs.readFile("src/ServerScriptService/BiomeService.luau")
		t.ok(string.find(text, "MudLogic.Factor(pos.X, pos.Z, gear)", 1, true), "the disc check is in update")
		t.ok(string.find(text, "rules.speedFactor * mud", 1, true), "it multiplies the walk speed")
		t.ok(not string.find(text, "Touched", 1, true), "no Touched event")
	end)
end
