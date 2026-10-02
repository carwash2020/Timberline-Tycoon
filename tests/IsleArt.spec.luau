--!nocheck
-- IsleArt: the Skyroot at its real place (WorldPlan.Sky) stays in budget,
-- keeps its canopy under the isles' walkable tops and out of the gondola's
-- way; an isle's top is a flat, colliding disc at y = 0 covering its
-- radius; the waterfall, clouds and lantern posts build as documented.

return function(t)
	local IsleArt = t.load("ReplicatedStorage/Shared/Art/IsleArt")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local Vector3 = t.roblox.Vector3

	local sky = WorldPlan.Sky()
	local rel = { sky.main.center - sky.root }
	local outer = {}
	for _, isle in ipairs(sky.isles) do
		table.insert(rel, isle.center - sky.root)
		table.insert(outer, { center = isle.center - sky.root, radius = isle.radius })
	end
	local fallRel = sky.waterfall.top - sky.root

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function halfHeight(p)
		local cf, s = p.CFrame, p.Size
		return 0.5 * (math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z)
	end
	-- A sphere round the part: an ellipsoid's or ball's longest radius, a
	-- block's half-diagonal.
	local function reach(p)
		local s = p.Size
		if p:FindFirstChildOfClass("SpecialMesh") or (p:IsA("Part") and p.Shape == t.roblox.Enum.PartType.Ball) then
			return math.max(s.X, s.Y, s.Z) / 2
		end
		return s.Magnitude / 2
	end
	local function horizontal(v)
		return Vector3.new(v.X, 0, v.Z)
	end
	local function distToSegment(p, a, b)
		local ab = b - a
		local t0 = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		return (p - (a + ab * t0)).Magnitude
	end
	local function isCylinder(p)
		return p:IsA("Part") and p.Shape == t.roblox.Enum.PartType.Cylinder
	end
	-- A cylinder's two end points (it runs along its X axis).
	local function ends(p)
		local half = p.CFrame.XVector * (p.Size.X / 2)
		return p.CFrame.Position - half, p.CFrame.Position + half
	end
	-- How far a part's surface is from the segment a-b (cylinders by their
	-- axis and radius; anything else by its bounding sphere).
	local function clearance(p, a, b)
		if isCylinder(p) then
			local e1, e2 = ends(p)
			local best = math.huge
			for i = 0, 40 do
				best = math.min(best, distToSegment(e1:Lerp(e2, i / 40), a, b))
			end
			return best - math.min(p.Size.Y, p.Size.Z) / 2
		end
		return distToSegment(p.CFrame.Position, a, b) - reach(p)
	end

	local skyroot = IsleArt.Skyroot(sky.trunkHeight, rel, sky.main.dir, fallRel)

	t.test("the Skyroot stays under its part budget, with or without the isles", function()
		t.ok(#parts(skyroot) <= 180, string.format("%d parts", #parts(skyroot)))
		t.ok(#parts(IsleArt.Skyroot(sky.trunkHeight)) <= 180, "defaults")
		t.ok(#parts(IsleArt.Skyroot(400)) <= 180, "a shorter tree")
	end)

	t.test("the Skyroot's named parts: trunk (primary, collides), roots, leaves", function()
		local trunk = skyroot:FindFirstChild("SkyrootTrunk")
		t.ok(trunk ~= nil and skyroot.PrimaryPart == trunk, "SkyrootTrunk is the PrimaryPart")
		t.ok(trunk.CanCollide, "the trunk collides")
		t.ok(skyroot:FindFirstChild("SkyrootRoots") ~= nil, "SkyrootRoots")
		local leaves = 0
		for _, p in ipairs(parts(skyroot)) do
			if p.Name == "SkyrootLeaves" then
				leaves += 1
				t.ok(not p.CanCollide and not p.CanQuery and not p.CanTouch, "leaves are decoration")
			end
		end
		t.ok(leaves >= 45, string.format("a full canopy (%d leaf parts)", leaves))
	end)

	t.test("the trunk stands on the ground and rises to its height", function()
		local low, high = math.huge, -math.huge
		for _, p in ipairs(parts(skyroot)) do
			if p.Name == "SkyrootTrunk" or p.Name == "SkyrootCore" or p.Name == "SkyrootBark" then
				low = math.min(low, p.CFrame.Y - halfHeight(p))
				high = math.max(high, p.CFrame.Y + halfHeight(p))
			end
		end
		t.ok(low < 0, "the trunk goes into the ground")
		t.ok(high > sky.trunkHeight * 0.8, "the trunk reaches up under the isles")
	end)

	t.test("no leaf rises above the trunk's height or pokes through an isle", function()
		local H = sky.trunkHeight
		for _, p in ipairs(parts(skyroot)) do
			if p.Name == "SkyrootLeaves" then
				local top = p.CFrame.Y + halfHeight(p)
				t.ok(top <= H + 1e-3, string.format("a leaf tops out at %.1f (limit %.1f)", top, H))
				-- Over an isle's footprint, at least 12 under its walkable top.
				local here = horizontal(p.CFrame.Position)
				local mainTop = sky.top - sky.root.Y
				if here.Magnitude - reach(p) < sky.main.radius then
					t.ok(top <= mainTop - 12, "a leaf under the main isle stays 12 below its top")
				end
				for _, isle in ipairs(outer) do
					if (here - horizontal(isle.center)).Magnitude - reach(p) < isle.radius then
						t.ok(top <= isle.center.Y - 12, "a leaf under an outer isle stays 12 below its top")
					end
				end
			end
		end
	end)

	t.test("a limb reaches the underside of every outer isle", function()
		for _, isle in ipairs(outer) do
			local reached = false
			for _, p in ipairs(parts(skyroot)) do
				if p.Name == "SkyrootLimb" then
					for _, e in ipairs({ ends(p) }) do
						local d = (horizontal(e) - horizontal(isle.center)).Magnitude
						local below = isle.center.Y - e.Y
						-- Its end is inside the rock: under the top, over the tip.
						if d < isle.radius * 0.6 and below > 8 and below < isle.radius * 1.2 then
							reached = true
						end
					end
				end
			end
			t.ok(reached, "an outer isle is held up")
		end
	end)

	t.test("nothing of the Skyroot is in the gondola cables' way", function()
		local base = sky.gondolaBase.Position - sky.root + Vector3.new(0, 8.5, 0)
		local top = sky.gondolaTop.Position - sky.root + Vector3.new(0, 8.5, 0)
		local town = WorldPlan.Town().gondola.Position - sky.root + Vector3.new(0, 9.5, 0)
		for _, p in ipairs(parts(skyroot)) do
			local c1 = clearance(p, base, top)
			t.ok(c1 > 4, string.format("%s %.1f studs from the trunk cable", p.Name, c1))
			if horizontal(p.CFrame.Position).Magnitude < 320 then
				local c2 = clearance(p, top, town)
				t.ok(c2 > 4, string.format("%s %.1f studs from the town cable", p.Name, c2))
			end
		end
	end)

	t.test("leaves part round the waterfall", function()
		local column = horizontal(fallRel)
		for _, p in ipairs(parts(skyroot)) do
			if p.Name == "SkyrootLeaves" then
				local d = (horizontal(p.CFrame.Position) - column).Magnitude
				t.ok(d > math.max(p.Size.X, p.Size.Z) / 2, "the waterfall falls clear of the leaves")
			end
		end
	end)

	t.test("the same Skyroot every time", function()
		local a, b = parts(skyroot), parts(IsleArt.Skyroot(sky.trunkHeight, rel, sky.main.dir, fallRel))
		t.eq(#a, #b)
		for i = 1, #a do
			t.ok((a[i].CFrame.Position - b[i].CFrame.Position).Magnitude < 1e-6, "deterministic")
		end
	end)

	local function checkIsle(radius, seed, options)
		local isle = IsleArt.Isle(radius, seed, options)
		local top = isle:FindFirstChild("IsleTop")
		t.ok(top ~= nil and isle.PrimaryPart == top, "IsleTop is the PrimaryPart")
		t.ok(top.CanCollide, "IsleTop collides")
		t.eq(top.Shape, t.roblox.Enum.PartType.Cylinder)
		-- A cylinder runs along its X axis: upright means X points up.
		t.ok(math.abs(top.CFrame.XVector.Y) > 0.9999, "IsleTop is flat")
		t.ok(math.abs(top.CFrame.Y + top.Size.X / 2) < 1e-4, "IsleTop's top is at y = 0")
		t.ok(
			math.abs(top.Size.Y - radius * 2) < 1e-4 and math.abs(top.Size.Z - radius * 2) < 1e-4,
			"it spans the radius"
		)
		t.ok(math.abs(top.CFrame.X) < 1e-4 and math.abs(top.CFrame.Z) < 1e-4, "it's centred")
		local all = parts(isle)
		t.ok(#all <= 120, string.format("r=%d seed %d: %d parts", radius, seed, #all))
		local rockLow, low = math.huge, math.huge
		for _, p in ipairs(all) do
			if p ~= top then
				t.ok(not p.CanCollide and not p.CanQuery and not p.CanTouch, p.Name .. " is decoration")
			end
			local bottom = p.CFrame.Y - halfHeight(p)
			local pTop = p.CFrame.Y + halfHeight(p)
			low = math.min(low, bottom)
			if p.Name == "IsleRock" or p.Name == "Facet" then
				rockLow = math.min(rockLow, bottom)
			end
			t.ok(pTop < 3.5, p.Name .. " doesn't stand tall on the walkable top")
			if p.Name == "IsleRim" or p.Name == "IsleSoil" or p.Name == "IsleRock" then
				t.ok(pTop <= 0.01, p.Name .. " stays under the grass")
			end
		end
		t.ok(
			rockLow < -radius * 1.1 and rockLow > -radius * 1.35,
			string.format("the rock tapers to a point %.1f down", -rockLow)
		)
		t.ok(low > -radius * 1.8, "roots dangle, but not forever")
		return isle, all
	end

	t.test("an isle's top is a flat, colliding disc at y = 0 over its whole radius", function()
		for _, r in ipairs({ 50, 40, 25 }) do
			for seed = 1, 5 do
				checkIsle(r, seed)
			end
		end
		checkIsle(40, 4, { spout = Vector3.new(1, 0, 0.3) })
		checkIsle(50, 1, { clear = { Vector3.new(48, 0, 0), Vector3.new(0, 0, 44) } })
	end)

	t.test("an isle keeps decoration off the points it's asked to keep clear", function()
		local clear = { Vector3.new(38, 0, 0), Vector3.new(-30, 0, 20), Vector3.new(0, 0, -36) }
		for seed = 1, 6 do
			local _, all = checkIsle(40, seed, { clear = clear })
			for _, p in ipairs(all) do
				if p.CFrame.Y > -1 and p.Name ~= "IsleTop" and p.Name ~= "IsleRim" then
					for _, c in ipairs(clear) do
						t.ok((horizontal(p.CFrame.Position) - c).Magnitude > 6.5, p.Name .. " sits on a clear point")
					end
				end
			end
		end
	end)

	t.test("a spout makes a spring and a stream to the rim", function()
		local isle = IsleArt.Isle(40, 4, { spout = Vector3.new(0, 0, -1) })
		local pool, stream = isle:FindFirstChild("SpringPool"), isle:FindFirstChild("Stream")
		t.ok(pool ~= nil and stream ~= nil, "pool and stream")
		t.ok(stream.CFrame.Z < -20, "the stream runs toward the spout")
		t.eq(IsleArt.Isle(40, 4):FindFirstChild("SpringPool"), nil)
	end)

	t.test("the waterfall hangs from its lip down to -height, misty at the bottom", function()
		for _, h in ipairs({ 710, 120, 30 }) do
			local fall = IsleArt.Waterfall(h, 10)
			local low, high = math.huge, -math.huge
			for _, p in ipairs(parts(fall)) do
				t.ok(not p.CanCollide and not p.CanQuery and not p.CanTouch, "decoration")
				low = math.min(low, p.CFrame.Y - halfHeight(p))
				high = math.max(high, p.CFrame.Y + halfHeight(p))
			end
			t.ok(math.abs(low + h) < 2, string.format("reaches the bottom (%.1f)", low))
			t.ok(high < 2.5, "only a little foam above the lip")
			t.ok(#parts(fall) <= 24, "cheap")
			local mist = fall:FindFirstChild("WaterfallMist")
			local emitter = mist and mist:FindFirstChild("Mist")
			t.ok(emitter ~= nil and emitter:IsA("ParticleEmitter"), "mist")
			t.eq(emitter.Texture, "rbxasset://textures/particles/smoke_main.dds")
			t.ok(fall:FindFirstChild("Waterfall") ~= nil, "sheets")
		end
	end)

	t.test("the waterfall moves: a particle curtain, not a glass pole (WLD-05)", function()
		local function emittersOf(inst)
			local out = {}
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("ParticleEmitter") then
					table.insert(out, d)
				end
			end
			return out
		end
		for _, h in ipairs({ 710, 120, 30 }) do
			local fall = IsleArt.Waterfall(h, 10)
			-- Nothing visible is a pole: the one sheet is the top 40 studs only.
			local sheets = 0
			for _, p in ipairs(parts(fall)) do
				if p.Transparency < 1 then
					t.ok(halfHeight(p) * 2 <= IsleArt.FallSheet + 0.01, p.Name .. " is no taller than the top sheet")
				end
				if p.Name == "Waterfall" then
					sheets += 1
					t.ok(p.CFrame.Y - halfHeight(p) >= -IsleArt.FallSheet - 0.01, "the sheet stays in the top 40 studs")
					t.ok(p.Transparency > 0 and p.Transparency < 1, "translucent")
				end
			end
			t.eq(sheets, 1, "one sheet")
			-- The curtain: an invisible part spanning the height, with several
			-- streams at its top pouring down at 50-70 studs/s for as long as
			-- the fall takes.
			local curtain = fall:FindFirstChild("WaterfallCurtain")
			t.ok(curtain ~= nil and curtain:IsA("BasePart"), "a curtain part")
			t.eq(curtain.Transparency, 1, "invisible")
			t.ok(not curtain.CanCollide and not curtain.CanQuery and not curtain.CanTouch, "a ghost")
			t.ok(math.abs(halfHeight(curtain) * 2 - h) < 0.01, "spans the height")
			t.ok(math.abs(curtain.CFrame.Y + h / 2) < 0.01, "from the lip to the foot")
			local streams = {}
			for _, e in ipairs(emittersOf(curtain)) do
				if e.Name == "Curtain" then
					table.insert(streams, e)
				end
			end
			t.ok(#streams >= 3, "several streams across the width")
			local xs = {}
			for _, e in ipairs(streams) do
				t.ok(e.Rate >= 60 and e.Rate <= 100, "Rate 60-100")
				t.ok(e.Speed.Min >= 50 and e.Speed.Max <= 70, "Speed 50-70")
				t.eq(e.EmissionDirection, t.roblox.Enum.NormalId.Bottom)
				t.ok(math.abs(e.LightEmission - 0.3) < 1e-6, "LightEmission 0.3")
				t.ok(e.Squash.Keypoints[1].Value > 0, "squashed into streaks")
				local mean = (e.Speed.Min + e.Speed.Max) / 2
				local reach = mean * e.Lifetime.Max
				t.ok(math.abs(reach - h) <= h * 0.05, string.format("lives as long as the fall (%.0f of %d)", reach, h))
				t.ok(string.find(e.Texture, "^rbxasset://textures/particles/") ~= nil, "a built-in texture")
				local at = e.Parent
				t.ok(at:IsA("Attachment") and at.Parent == curtain, "on the curtain")
				t.ok(math.abs(at.CFrame.Y - (h / 2 - 0.5)) < 0.01, "at its top")
				table.insert(xs, at.CFrame.X)
			end
			table.sort(xs)
			t.ok(xs[#xs] - xs[1] >= 10 * 0.5, "spread across the width")
			-- The mist band at 60-90% of the way down (long falls).
			local spray = fall:FindFirstChild("WaterfallSpray")
			if h > 40 then
				t.ok(spray ~= nil, "a mist band")
				t.eq(spray.Transparency, 1, "the band is particles only")
				local top, bottom = spray.CFrame.Y + halfHeight(spray), spray.CFrame.Y - halfHeight(spray)
				t.ok(math.abs(top + h * 0.6) < 0.01 and math.abs(bottom + h * 0.9) < 0.01, "60-90% of the height")
				t.ok(spray:FindFirstChildOfClass("ParticleEmitter") ~= nil, "mist emitter")
			end
			-- Spray at the foot.
			local mist = fall:FindFirstChild("WaterfallMist")
			t.ok(mist:FindFirstChild("Spray") ~= nil, "spray at the foot")
			-- Every emitter carries its full rate for the client's quality scale,
			-- and the whole fall stays inside a phone-friendly budget (live
			-- particles: rate x the longest life; low quality halves it).
			local live = 0
			for _, e in ipairs(emittersOf(fall)) do
				t.eq(e:GetAttribute(IsleArt.FallRateAttribute), e.Rate, e.Name .. " has its BaseRate")
				live += e.Rate * e.Lifetime.Max
			end
			t.ok(live <= 2400, string.format("about %d live particles (high); half on low", live))
		end
	end)

	t.test("cloud banks are soft, cheap and sit on their base", function()
		for seed = 1, 10 do
			local cloud = IsleArt.CloudBank(100, seed)
			local all = parts(cloud)
			t.ok(#all >= 5 and #all <= 9, "five to nine puffs")
			for _, p in ipairs(all) do
				t.ok(not p.CanCollide and not p.CanQuery and not p.CanTouch and not p.CastShadow, "decoration")
				t.ok(p.Transparency <= 0.15, "modest transparency")
				t.ok(p.CFrame.Y - halfHeight(p) > -1, "flat base at y = 0")
			end
		end
	end)

	t.test("cloud spots drift round the tree, never on the gondola's side", function()
		local spots = IsleArt.CloudSpots(rel, sky.trunkHeight, 99, sky.main.dir)
		t.ok(#spots >= 8, "a sky full of clouds")
		local town = math.atan2(sky.main.dir.Z, sky.main.dir.X)
		for _, s in ipairs(spots) do
			local p = s.cframe.Position
			local a = math.atan2(p.Z, p.X)
			local gap = math.abs((a - town + math.pi) % (math.pi * 2) - math.pi)
			t.ok(gap > math.rad(30), "not in the gondola's way")
			t.ok(s.size > 0 and p.Y > 0, "in the sky")
		end
		t.eq(#IsleArt.CloudSpots(rel, sky.trunkHeight, 99, sky.main.dir), #spots)
	end)

	t.test("a lantern post holds a glowing lantern", function()
		local post = IsleArt.LanternPost(1)
		local glow = post:FindFirstChild("LanternGlow")
		t.ok(glow ~= nil and glow:FindFirstChildWhichIsA("PointLight") ~= nil, "LanternGlow with a light")
		t.ok(#parts(post) <= 8, "cheap")
	end)

	t.test("isle art is placed with CFrame, never Position", function()
		local models = {
			skyroot,
			IsleArt.Isle(40, 4, { spout = Vector3.new(1, 0, 0) }),
			IsleArt.Waterfall(100, 8),
			IsleArt.CloudBank(80, 2),
			IsleArt.LanternPost(2),
		}
		for _, m in ipairs(models) do
			for _, p in ipairs(parts(m)) do
				local setPosition = pcall(function()
					return p.Position
				end)
				t.ok(not setPosition, m.Name .. ": " .. p.Name .. " was placed with .Position")
			end
		end
	end)
end
