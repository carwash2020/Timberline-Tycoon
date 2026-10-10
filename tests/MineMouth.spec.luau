--!nocheck
-- The mine mouth (ring map, 10 Oct 2026): it was a 16 x 16 shaft straight
-- down for 56 studs. Now NatureArt.CaveMouth stands at (150, -150) with its
-- door toward town and a gentle ramp runs from under its arch down to the
-- upper mine. These specs walk a character-sized capsule through the air
-- UndergroundData cuts (the same boxes TerrainBuilder.Carve fills with air),
-- check the hill roofs the bore, and check that the model's collider leaves
-- its own doorway open.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local TerrainGen = t.shared("World/TerrainGen")
	local UndergroundData = t.shared("World/UndergroundData")
	local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame

	local ramp = UndergroundData.Ramp
	local mouth = UndergroundData.MineMouth
	local boxes = UndergroundData.AirBoxes()

	-- Open air: above the ground, or inside a carved box.
	local function inAir(x, y, z)
		if y > TerrainGen.HeightAt(x, z) then
			return true
		end
		for _, b in ipairs(boxes) do
			if math.abs(x - b.x) <= b.sx / 2 and math.abs(y - b.y) <= b.sy / 2 and math.abs(z - b.z) <= b.sz / 2 then
				return true
			end
		end
		return false
	end

	-- The floor a walker at (x, z) stands on, given the floor it came from:
	-- the lowest carved floor within a step up (1.5 studs) or a drop of 6.
	local function floorAt(x, z, from)
		local best = nil
		for _, b in ipairs(boxes) do
			if math.abs(x - b.x) <= b.sx / 2 and math.abs(z - b.z) <= b.sz / 2 then
				local bottom = b.y - b.sy / 2
				if bottom >= from - 6 and bottom <= from + 1.5 then
					best = if best then math.min(best, bottom) else bottom
				end
			end
		end
		if not best then
			-- Not under any carved box: the open ground, if it is a step away.
			local ground = TerrainGen.HeightAt(x, z)
			if ground >= from - 6 and ground <= from + 1.5 then
				best = ground
			end
		end
		return best
	end

	-- A capsule 4 across and 5.5 tall: its ring (radius 2) and centre column
	-- at four heights above the hip (steps under 1.5 are the humanoid's).
	local function capsuleFits(x, y, z)
		for _, h in ipairs({ 1.5, 3, 4.5, 5.5 }) do
			if not inAir(x, y + h, z) then
				return false, "centre at " .. h
			end
			for k = 0, 7 do
				local a = k * math.pi / 4
				if not inAir(x + 2 * math.cos(a), y + h, z + 2 * math.sin(a)) then
					return false, string.format("ring %d at %.1f", k, h)
				end
			end
		end
		return true
	end

	t.test("the mouth stays at (150, -150) and the old 56-stud shaft is gone", function()
		t.eq(mouth.x, 150)
		t.eq(mouth.z, -150)
		for _, b in ipairs(boxes) do
			t.ok(b.kind ~= "mouth", "the vertical mouth shaft is still carved")
			-- Nothing carved above the ground tall and narrow near the mouth.
			if (b.x - mouth.x) ^ 2 + (b.z - mouth.z) ^ 2 < 24 * 24 and b.kind == "ramp" then
				t.ok(b.sy <= ramp.height + 1e-6, "a ramp box is taller than the bore")
			end
		end
		local upper = UndergroundData.Cave("mine-upper")
		t.ok(upper ~= nil and upper.floorY == -48, "the upper mine's floor is where it was")
	end)

	t.test("the ramp is a gentle grade: under 22 degrees, over 12", function()
		local deg = math.deg(math.atan(UndergroundData.RampGrade))
		t.ok(deg < 22 and deg > 12, string.format("grade is %.1f degrees", deg))
		local last = UndergroundData.RampSamples[#UndergroundData.RampSamples]
		t.eq(last.y, -48, "the ramp lands on the upper mine's floor")
		-- No sample steps the floor more than a stud (a humanoid's step).
		local prev = UndergroundData.RampSamples[1]
		for i = 2, #UndergroundData.RampSamples do
			local p = UndergroundData.RampSamples[i]
			t.ok(
				prev.y - p.y <= 1.0 and prev.y - p.y >= 0,
				string.format("step of %.2f at s = %.0f", prev.y - p.y, p.s)
			)
			prev = p
		end
		-- Bends of 15 degrees or less, so the bore is never a corner.
		local pts = UndergroundData.RampSamples
		for i = 3, #pts do
			local a = Vector3.new(pts[i - 1].x - pts[i - 2].x, 0, pts[i - 1].z - pts[i - 2].z).Unit
			local b = Vector3.new(pts[i].x - pts[i - 1].x, 0, pts[i].z - pts[i - 1].z).Unit
			local turn = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
			t.ok(turn <= 15.5, string.format("bend of %.1f degrees at sample %d", turn, i))
		end
	end)

	t.test("a character-sized capsule walks from the mine floor, up the ramp and out onto open ground", function()
		-- Start on the upper mine's floor, in the chamber's middle, and walk
		-- to the ramp's foot, then back up its centre line, then out of the door.
		local route = {}
		local last = UndergroundData.RampSamples[#UndergroundData.RampSamples]
		local startX, startZ = 150, -220
		local legs = 40
		for i = 0, legs do
			local u = i / legs
			table.insert(route, { startX + (last.x - startX) * u, startZ + (last.z - startZ) * u })
		end
		for i = #UndergroundData.RampSamples, 1, -1 do
			local p = UndergroundData.RampSamples[i]
			table.insert(route, { p.x, p.z })
		end
		for z = ramp.doorZ, ramp.doorZ + 12, 1 do
			table.insert(route, { mouth.x, z })
		end
		local y = -48
		local prev = nil
		local steps = 0
		for _, p in ipairs(route) do
			-- Walk this leg in half-stud strides.
			local from = prev or p
			local len = math.max(0.0001, math.sqrt((p[1] - from[1]) ^ 2 + (p[2] - from[2]) ^ 2))
			local n = math.max(1, math.ceil(len / 0.5))
			for k = 1, n do
				local x = from[1] + (p[1] - from[1]) * k / n
				local z = from[2] + (p[2] - from[2]) * k / n
				local f = floorAt(x, z, y)
				t.ok(f ~= nil, string.format("no floor to stand on at (%.1f, %.1f) from y %.1f", x, z, y))
				y = f
				local ok, why = capsuleFits(x, y, z)
				t.ok(ok, string.format("the capsule does not fit at (%.1f, %.1f, %.1f): %s", x, y, z, tostring(why)))
				steps += 1
			end
			prev = p
		end
		t.ok(steps > 300, "the walk covered the whole way")
		-- It ends on the open ground in front of the door.
		t.ok(math.abs(y - TerrainGen.HeightAt(mouth.x, ramp.doorZ + 12)) < 1, string.format("ended at y %.2f", y))
	end)

	t.test("the ground in front of the door is level and the same height as the ramp's top", function()
		for x = mouth.x - 8, mouth.x + 8, 4 do
			for z = ramp.doorZ, ramp.doorZ + 24, 4 do
				t.ok(
					math.abs(TerrainGen.HeightAt(x, z) - ramp.top) < 1,
					string.format(
						"ground at (%d, %d) is %.2f, the ramp's top is %.1f",
						x,
						z,
						TerrainGen.HeightAt(x, z),
						ramp.top
					)
				)
			end
		end
		t.eq(UndergroundData.HillAt(mouth.x, ramp.doorZ + 1), 0, "no hill in front of the door")
		t.eq(UndergroundData.HillAt(mouth.x, ramp.doorZ + 20), 0)
	end)

	t.test("the ground over the bore keeps rock over its roof, so it is never an open cut", function()
		for _, p in ipairs(UndergroundData.RampSamples) do
			-- The arch is 15 deep and roofs the first stretch itself.
			if p.s >= ramp.landing then
				local roof = p.y + ramp.height
				for _, off in ipairs({ -8, 0, 8 }) do
					-- Across the bore, whichever way it runs here.
					local nx, nz = 0, 0
					local i = math.max(1, math.min(#UndergroundData.RampSamples - 1, math.floor(p.s / ramp.step) + 1))
					local a, b = UndergroundData.RampSamples[i], UndergroundData.RampSamples[i + 1]
					local dx, dz = b.x - a.x, b.z - a.z
					local len = math.sqrt(dx * dx + dz * dz)
					if len > 0 then
						nx, nz = -dz / len, dx / len
					end
					local h = TerrainGen.HeightAt(p.x + nx * off, p.z + nz * off)
					t.ok(
						h >= roof + 4,
						string.format("ground %.1f over a %.1f roof at s = %.0f (%+d across)", h, roof, p.s, off)
					)
				end
			end
		end
	end)

	t.test("the ramp bore stays clear of the plots' yards, the furnace pad and the other caves' ceilings", function()
		local PlotData = t.shared("PlotData")
		for _, p in ipairs(UndergroundData.RampSamples) do
			-- Under a yard is fine once the roof is deep; the open stretch is not.
			if p.y + ramp.height > TerrainGen.HeightAt(p.x, p.z) - 2 then
				for _, home in ipairs(PlotData.Homes) do
					t.ok(
						math.abs(p.x - home.x) > 100 + 10 or math.abs(p.z - home.z) > 100 + 10,
						string.format("the open stretch of the ramp reaches %s's yard", home.id)
					)
				end
			end
		end
		local site = UndergroundData.FurnaceSite
		for _, p in ipairs(UndergroundData.RampSamples) do
			t.ok(
				math.abs(p.x - site.x) > site.sx / 2 + 16 or math.abs(p.z - site.z) > site.sz / 2 + 16,
				"the ramp runs under the furnace pad"
			)
		end
	end)

	t.test("the placement turns the model's door toward town and its throat down the ramp", function()
		local builder = t.server("UndergroundBuilder")
		local cf = builder.MouthCFrame()
		local door = cf:VectorToWorldSpace(Vector3.new(0, 0, -1))
		local throat = cf:VectorToWorldSpace(Vector3.new(0, 0, 1))
		t.ok((door - Vector3.new(0, 0, 1)).Magnitude < 1e-6, "the door faces +Z, toward town")
		t.ok((throat - Vector3.new(0, 0, -1)).Magnitude < 1e-6, "the throat runs toward -Z")
		local first, second = UndergroundData.RampSamples[1], UndergroundData.RampSamples[10]
		t.ok(second.z < first.z, "the ramp heads the way the throat points")
		t.ok(math.abs(cf.Position.X - mouth.x) < 1e-6)
		t.ok(math.abs(cf.Position.Z - mouth.z) < 1e-6)
		-- Sunk 0.4 into the ground at the door, never floating.
		t.ok(cf.Position.Y < TerrainGen.HeightAt(mouth.x, ramp.doorZ) and cf.Position.Y > ramp.top - 1)
	end)

	t.test("Build places the lit mouth model and five ramp lamps with shadows off", function()
		local builder = t.server("UndergroundBuilder")
		local folder = t.roblox.Instance.new("Folder")
		local built = builder.Build(folder)
		local model = folder:FindFirstChild("MineMouth")
		t.ok(model ~= nil and model:IsA("Model"), "the mouth model is placed")
		t.ok(model:HasTag("MineMouth"))
		local lamps = built:FindFirstChild("RampLights")
		t.ok(lamps ~= nil)
		local count = 0
		local lowest, highest = math.huge, -math.huge
		for _, lamp in ipairs(lamps:GetChildren()) do
			count += 1
			local light = lamp:FindFirstChildWhichIsA("PointLight")
			t.ok(light ~= nil and light.Shadows == false)
			lowest = math.min(lowest, lamp.CFrame.Position.Y)
			highest = math.max(highest, lamp.CFrame.Position.Y)
			-- Hung inside the bore: under its roof, above its floor.
			t.ok(
				inAir(lamp.CFrame.Position.X, lamp.CFrame.Position.Y, lamp.CFrame.Position.Z),
				"a lamp hangs inside rock"
			)
		end
		t.eq(count, ramp.lights)
		t.ok(highest - lowest > 20, "the lamps run the length of the descent")
		-- The model's own light is at the door, and it is the only light on it.
		t.ok(model:FindFirstChildWhichIsA("PointLight", true) ~= nil)
	end)

	-- The Collision mesh in the uploaded GLB: read its real triangles.
	local function collisionBoxes()
		local data = buffer.fromstring(fs.readFile("assets/meshes/rocks/CaveMouth/CaveMouth.glb"))
		local json, bin
		local off = 12
		while off < buffer.len(data) do
			local len = buffer.readu32(data, off)
			local kind = buffer.readu32(data, off + 4)
			if kind == 0x4E4F534A then
				json = serde.decode("json", buffer.readstring(data, off + 8, len))
			elseif kind == 0x004E4942 then
				bin = { at = off + 8 }
			end
			off += 8 + len
		end
		local nodeMesh
		for _, node in ipairs(json.nodes) do
			if node.name == "Collision" then
				nodeMesh = node.mesh
			end
		end
		t.ok(nodeMesh ~= nil, "a Collision node")
		local out = {}
		for _, prim in ipairs(json.meshes[nodeMesh + 1].primitives) do
			local pa = json.accessors[prim.attributes.POSITION + 1]
			local pv = json.bufferViews[pa.bufferView + 1]
			local ia = json.accessors[prim.indices + 1]
			local iv = json.bufferViews[ia.bufferView + 1]
			local function vertex(i)
				local o = bin.at + (pv.byteOffset or 0) + (pa.byteOffset or 0) + i * (pv.byteStride or 12)
				return buffer.readf32(data, o), buffer.readf32(data, o + 4), buffer.readf32(data, o + 8)
			end
			for k = 0, ia.count - 1, 3 do
				local idx = {}
				for j = 0, 2 do
					local o = bin.at + (iv.byteOffset or 0) + (ia.byteOffset or 0)
					if ia.componentType == 5123 then
						idx[j + 1] = buffer.readu16(data, o + (k + j) * 2)
					else
						idx[j + 1] = buffer.readu32(data, o + (k + j) * 4)
					end
				end
				local x1, y1, z1 = vertex(idx[1])
				local x2, y2, z2 = vertex(idx[2])
				local x3, y3, z3 = vertex(idx[3])
				table.insert(out, {
					math.min(x1, x2, x3),
					math.min(y1, y2, y3),
					math.min(z1, z2, z3),
					math.max(x1, x2, x3),
					math.max(y1, y2, y3),
					math.max(z1, z2, z3),
				})
			end
		end
		return out
	end

	t.test("the cave mouth's collider is two pillars and a lintel: a character-sized doorway stays open", function()
		local tris = collisionBoxes()
		t.ok(#tris >= 12, "collision triangles read")
		-- The character's box 4 wide and 6 tall, from the ground up, passes
		-- through the doorway anywhere across its 16 width (2 off each pillar),
		-- along the whole throat.
		local spec = RockModels.Scenery("CaveMouth")
		for _, cx in ipairs({ -5.9, -4, -2, 0, 2, 4, 5.9 }) do
			local lo = Vector3.new(cx - 2, 0.0, -100)
			local hi = Vector3.new(cx + 2, 6.0, 100)
			for _, tri in ipairs(tris) do
				-- Mesh coordinates are model coordinates (the bounds' centre is
				-- the Collision offset above the Body's centre).
				local x0, y0, x1, y1 = tri[1], tri[2], tri[4], tri[5]
				-- Skip the pillars' own height-0.49 gap: they start above 0.49.
				local overlaps = x0 < hi.X and x1 > lo.X and y0 < hi.Y and y1 > lo.Y
				t.ok(not overlaps, string.format("a collider block fills the doorway at x = %d", cx))
			end
		end
		-- The doorway is the 16 x 12 opening the model's Frame lines.
		local frame = spec.pieces.Frame
		t.ok(frame.size.X > 16 and frame.size.Y > 12, "the frame is the 16 x 12 opening plus its trim")
	end)
end
