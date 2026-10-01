--!nocheck
-- The world-eye preview's cameras (tools/preview/scenes/_eye.luau, WLD-19):
-- nine views (the viewer's keys 1 to 9), each eye 5.5 studs above what a
-- player stands on there, at the places the backlog names, and view 9 is
-- view 1 at night.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local path = "tools/preview/scenes/_eye.luau"
	local Eye = luau.load(fs.readFile(path), { debugName = path })()
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local town, sky = WorldPlan.Town(), WorldPlan.Sky()
	local cameras = Eye.cameras({ roblox = roblox, load = t.load })

	local function v(list)
		return Vector3.new(list[1], list[2], list[3])
	end
	local function flat(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function ground(p)
		return math.max(TerrainGen.HeightAt(p.X, p.Z), TerrainGen.WaterLevelAt(p.X, p.Z) or -math.huge)
	end
	local function roadEnd(name)
		for _, r in ipairs(WorldLayout.Roads) do
			if r.name == name then
				local last = r.points[#r.points]
				return Vector3.new(last.X, 0, last.Y)
			end
		end
		error("no road called " .. name)
	end

	t.test("nine eye-level views, each with a label, Roblox's field of view and somewhere to look", function()
		t.eq(#cameras, 9)
		for i, cam in ipairs(cameras) do
			t.ok(type(cam.label) == "string" and cam.label ~= "", "view " .. i .. " has a label")
			t.eq(cam.fov, 70, "view " .. i .. "'s fov")
			t.ok((v(cam.target) - v(cam.pos)).Magnitude > 20, "view " .. i .. " looks somewhere")
			local p = v(cam.pos)
			local half = WorldLayout.WorldHalf
			t.ok(math.abs(p.X) < half and math.abs(p.Z) < half, "view " .. i .. " is inside the world")
		end
	end)

	t.test("every eye is 5.5 studs above what a player stands on there", function()
		local padTop = town.spawn.Y + 0.5 -- MapBuilder's spawn pad is 1 stud tall
		for i, cam in ipairs(cameras) do
			local p = v(cam.pos)
			local floor = ground(p)
			if i == 1 or i == 2 or i == 9 then
				t.ok(flat(p, town.spawn) < 1e-6, "view " .. i .. " stands on the spawn")
				floor = math.max(floor, padTop)
			elseif i == 6 then
				t.ok(flat(p, sky.main.center) < sky.main.radius - 5, "view 6 stands on the main isle")
				floor = sky.main.center.Y -- the isle's top
			end
			t.ok(math.abs(p.Y - floor - 5.5) < 1e-6, string.format("view %d: eye %.2f above its floor", i, p.Y - floor))
		end
	end)

	t.test("the places WLD-19 names", function()
		local function at(i)
			return v(cameras[i].pos)
		end
		t.ok(v(cameras[1].target).Z > at(1).Z + 50, "1 looks north")
		t.ok(flat(v(cameras[1].target), town.sawmill.Position) < 1e-6, "1 looks at the sawmill")
		local se = v(cameras[2].target) - at(2)
		t.ok(se.X > 0 and se.Z < 0 and math.abs(math.abs(se.X) - math.abs(se.Z)) < 1e-3, "2 looks south-east")
		t.ok(flat(at(3), Vector3.new(30, 0, 450)) < 1e-6, "3 on the Snow Road at (30, 450)")
		t.ok(flat(at(4), Vector3.new(1150, 0, 0)) < 1e-6, "4 on the beach at (1150, 0)")
		t.ok(flat(at(5), town.gondola.Position) < 30, "5 by the town gondola station")
		t.ok(flat(at(7), roadEnd("HillsRoad")) < 50, "7 near the Hills Road's end")
		t.ok(flat(at(8), roadEnd("VolcanoRoad")) < 20, "8 at the Volcano Road's end")
	end)

	t.test("view 9 is view 1 at night", function()
		t.eq(cameras[9].night, true)
		t.eq(cameras[1].night, nil, "view 1 is by day")
		t.eq(cameras[9].pos, cameras[1].pos)
		t.eq(cameras[9].target, cameras[1].target)
		t.eq(cameras[9].fov, cameras[1].fov)
	end)
end
