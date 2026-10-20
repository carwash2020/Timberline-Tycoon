--!nocheck
-- T385: the town's light posts, round planters, benches and awning posts are
-- solid, and the looks on top of them (bush, awning roof and stripes,
-- lanterns, legs) stay non-colliding. One combined sweep over the shops'
-- street fronts, the lamp, the bench and the region lanterns:
--   1. a named post-like part taller than 1 stud collides (short allow list);
--   2. each lamp post has a solid part over its pole centre from Y 0.5 to 4;
--   3. each bench has a solid seat (top 1.4 to 1.8) and a solid back;
--   4. each planter collides with its top 1.4 to 1.8; each awning post covers
--      its centre from Y 0.5 to 4 and stands 1.5 studs clear of the door;
--   5. a character-sized box at each door centre touches no solid part;
--   6. the part counts are unchanged (the change builds no part; the Dealership is 408 plus the 12 of its event-table cards, T390).
return function(t)
	local roblox = t.roblox
	local Color3, Instance = roblox.Color3, roblox.Instance
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local RegionArt = t.load("ReplicatedStorage/Shared/Art/RegionArt")
	local ShopEventKit = t.load("ReplicatedStorage/Shared/Art/ShopEventKit")

	local ACCENT = Color3.fromRGB(200, 120, 60)
	local KINDS = { "Dealership", "GeneralStore", "ToolShed", "HearthAndHome", "Sparkworks" }
	local DOORS = { "Dealership", "GeneralStore", "ToolShed" } -- the shops whose front the walk to the door crosses

	local function parts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
	end

	local function height(part)
		local _, _, y0, y1 = aabb(part)
		return y1 - y0
	end

	-- Does the part cover the point (x, z) for every Y from lo to hi? (Heights
	-- below are measured up from the shop's ground, the floor's top.)
	local function covers(part, x, z, lo, hi)
		local x0, x1, y0, y1, z0, z1 = aabb(part)
		return part.CanCollide
			and x >= x0 - 0.01
			and x <= x1 + 0.01
			and z >= z0 - 0.01
			and z <= z1 + 0.01
			and y0 <= lo + 0.01
			and y1 >= hi - 0.01
	end

	local function coveredBySolid(root, name, base, lo, hi)
		local n = 0
		lo, hi = lo + base, hi + base
		local all = parts(root)
		for _, p in ipairs(all) do
			if p.Name == name then
				n += 1
				local pos = p.CFrame.Position
				local ok = false
				for _, q in ipairs(all) do
					if covers(q, pos.X, pos.Z, lo, hi) then
						ok = true
						break
					end
				end
				t.ok(ok, name .. " has a solid part over its centre from Y " .. lo .. " to " .. hi)
			end
		end
		return n
	end

	local function flat()
		return 0
	end

	-- Everything this ticket touches, built once.
	local models = {}
	local specs = {}
	for _, kind in ipairs(KINDS) do
		models[kind] = BuildingArt.Shop(kind, kind, ACCENT)
		specs[kind] = BuildingArt.FacadeSpec(kind, 1, ACCENT)
	end
	local lamp = BuildingArt.LampPost()
	local bayou = RegionArt.Lanterns(Instance.new("Folder"), flat, 1.4)
	local mesa = RegionArt.MesaLanterns(Instance.new("Folder"), flat)
	local sceneBench = PropArt.Scene("bench")
	local propBench = BuildingArt.Prop("Bench", 1)

	-- Parts that may stay non-colliding even though they are tall: the
	-- lantern glass and the arm.
	local ALLOW = { LampGlow = true, LanternGlow = true, Arm = true, EventLampHead = true }
	-- Post-like names a body should bump into. (A shop's hung Sign board and
	-- a fence rail are other tickets' parts; the sweep names what this one builds.)
	local MUST =
		{ LampPost = true, PathLampPost = true, AwningPost = true, Planter = true, BenchSeat = true, BenchBack = true }

	t.test("1: post-like parts taller than a stud collide (lamps, benches, planters, awning posts)", function()
		local swept = 0
		local sets = { lamp, bayou, mesa, propBench }
		for _, kind in ipairs(KINDS) do
			table.insert(sets, models[kind])
		end
		for _, root in ipairs(sets) do
			for _, p in ipairs(parts(root)) do
				local name = p.Name
				local named = MUST[name] or name == "Post" or name == "Bench"
				if named and not ALLOW[name] and height(p) > 1 then
					swept += 1
					t.ok(p.CanCollide, root.Name .. "/" .. name .. " collides")
				end
			end
		end
		t.ok(swept >= 12, "the sweep saw the parts (" .. swept .. ")")
	end)

	t.test("1b: the looks on top stay non-colliding", function()
		for _, kind in ipairs(KINDS) do
			for _, p in ipairs(parts(models[kind])) do
				if
					p.Name == "PlanterLeaves"
					or p.Name == "AwningStripe"
					or p.Name == "AwningValance"
					or p.Name == "AwningBracket"
					or p.Name == "BenchLeg"
					or p.Name == "LampGlow"
					or p.Name == "LanternGlow"
				then
					t.eq(p.CanCollide, false, kind .. "/" .. p.Name)
				end
			end
		end
	end)

	t.test("2: every lamp post has a solid part over its pole centre from Y 0.5 to 4", function()
		local n = 0
		for _, kind in ipairs(KINDS) do
			n += coveredBySolid(models[kind], "LampPost", specs[kind].groundY, 0.5, 4)
			n += coveredBySolid(models[kind], "PathLampPost", specs[kind].groundY, 0.5, 4)
		end
		n += coveredBySolid(bayou, "LampPost", 0, 0.5, 4)
		n += coveredBySolid(mesa, "LampPost", 0, 0.5, 4)
		n += coveredBySolid(lamp, "Post", 0, 0.5, 4)
		t.ok(n >= 11, "the lamps were found (" .. n .. ")")
	end)

	t.test("3: every bench has a solid seat (top 1.4 to 1.8) over its centre and a solid back", function()
		local benches = 0
		for _, kind in ipairs(KINDS) do
			local root = models[kind]
			for _, seat in ipairs(parts(root)) do
				if seat.Name == "BenchSeat" then
					benches += 1
					local _, _, _, top = aabb(seat)
					-- measured from the bench's own footing (its legs' feet)
					local foot = math.huge
					for _, leg in ipairs(parts(root)) do
						local lx = leg.CFrame.Position
						if leg.Name == "BenchLeg" and math.abs(lx.X - seat.CFrame.Position.X) < 3 then
							local _, _, ly0 = aabb(leg)
							foot = math.min(foot, ly0)
						end
					end
					t.ok(foot < math.huge, kind .. " bench has legs")
					local rise = top - foot
					t.ok(seat.CanCollide, kind .. " bench seat collides")
					t.ok(rise >= 1.4 and rise <= 1.8, kind .. " seat top " .. rise)
					local pos = seat.CFrame.Position
					t.ok(covers(seat, pos.X, pos.Z, top - 0.1, top), "seat covers its centre")
					local back = false
					for _, b in ipairs(parts(root)) do
						if b.Name == "BenchBack" and b.CanCollide and math.abs(b.CFrame.Position.X - pos.X) < 0.01 then
							back = true
						end
					end
					t.ok(back, kind .. " bench has a solid back")
				end
			end
		end
		-- the scene bench: Seat plus the lower Back (0.7 tall)
		benches += 1
		local seat, back = nil, false
		for _, p in ipairs(parts(sceneBench)) do
			if p.Name == "Seat" then
				seat = p
			elseif p.Name == "Back" and p.Size.Y > 0.5 then
				back = p.CanCollide
			end
		end
		t.ok(seat ~= nil and seat.CanCollide, "the scene bench's seat collides")
		local _, _, _, top = aabb(seat)
		t.ok(top >= 1.4 and top <= 1.8, "scene seat top " .. top)
		t.ok(back, "the scene bench's lower back collides")
		for _, p in ipairs(parts(sceneBench)) do
			if p.Name == "Arm" or p.Name == "Leg" or p.Name == "Stretcher" or (p.Name == "Back" and p.Size.Y < 0.5) then
				t.eq(p.CanCollide, false, "scene bench " .. p.Name .. " is a look")
			end
		end
		-- the control: BuildingArt's own bench was already solid
		local controlSolid = 0
		for _, p in ipairs(parts(propBench)) do
			if p.Name == "Seat" and p.CanCollide then
				controlSolid += 1
			end
		end
		t.ok(controlSolid > 0, "BuildingArt's Bench keeps a solid seat")
		t.ok(benches >= 2, "benches were found (" .. benches .. ")")
	end)

	t.test(
		"4: planters are solid with their top 1.4 to 1.8, awning posts cover Y 0.5 to 4 clear of the door",
		function()
			local planters = 0
			for _, kind in ipairs(KINDS) do
				local spec = specs[kind]
				for _, p in ipairs(parts(models[kind])) do
					if p.Name == "Planter" then
						planters += 1
						local _, _, _, top = aabb(p)
						local _, _, bottom = aabb(p)
						top -= bottom -- (the planters stand on the walk or the plinth, so measure from their own foot)
						t.ok(p.CanCollide, kind .. " planter collides")
						t.ok(top >= 1.4 and top <= 1.8, kind .. " planter top " .. top)
					end
				end
				local posts = coveredBySolid(models[kind], "AwningPost", spec.groundY, 0.5, 4)
				local awnings = kind ~= "Sparkworks"
				for _, p in ipairs(parts(models[kind])) do
					if p.Name == "AwningPost" then
						t.ok(
							math.abs(p.CFrame.Position.X - spec.doorCx) >= spec.doorHalf + 1.5 - 1e-6,
							kind .. " awning post clears the door"
						)
					end
				end
				t.ok(posts == (if awnings then 2 else 0) or posts == 2, kind .. " awning posts (" .. posts .. ")")
			end
			t.ok(planters == 8, "all eight planters were found (" .. planters .. ")")
		end
	)

	t.test("5: a character-sized box at each door centre touches no solid part", function()
		for _, kind in ipairs(DOORS) do
			local spec = specs[kind]
			local cx, cz = spec.doorCx, spec.frontZ - 2
			local bx0, bx1, bz0, bz1 = cx - 1, cx + 1, cz - 1, cz + 1
			local by0, by1 = spec.groundY + 0.35, spec.groundY + 5.35 -- (feet on the floor slab, a step above the street)
			for _, p in ipairs(parts(models[kind])) do
				if p.CanCollide then
					local x0, x1, y0, y1, z0, z1 = aabb(p)
					local hit = x0 < bx1 and x1 > bx0 and y0 < by1 and y1 > by0 and z0 < bz1 and z1 > bz0
					t.ok(not hit, kind .. " door box meets solid " .. p.Name)
				end
			end
		end
	end)

	t.test("6: no part was added (counts match main)", function()
		local want = { Dealership = 420, GeneralStore = 114, ToolShed = 452, HearthAndHome = 456, Sparkworks = 418 }
		for _, kind in ipairs(KINDS) do
			t.eq(#parts(models[kind]), want[kind], kind .. " part count")
		end
		t.eq(#parts(lamp), 6, "town lamp part count")
		t.eq(#parts(bayou), 16, "bayou lanterns part count")
		t.eq(#parts(mesa), 8, "mesa lanterns part count")
		t.eq(#parts(sceneBench), 10, "scene bench part count")
	end)

	t.test("event zone posts collide, the rest of the zone does not", function()
		local m = Instance.new("Model")
		local zone = ShopEventKit.BuildZone(m, "Dealership", roblox.CFrame.new(0, 0, 0))
		local posts = 0
		for _, p in ipairs(parts(zone)) do
			t.eq(p.CanCollide, p.Name == "EventStanchion", p.Name)
			if p.Name == "EventStanchion" then
				posts += 1
			end
		end
		t.eq(posts, 4, "four corner posts")
	end)
end
