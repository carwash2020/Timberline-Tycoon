--!nocheck
-- CritterArt (Shared/Art): the rabbit's size, and its eyes (NAT-19). Each eye sits on
-- its own side of the head, just under the head's surface so it shows as
-- a bead, and never pokes out past the head's outline (the far-side eye
-- used to stick out in front of the head).
return function(t)
	local CritterArt = t.load("ReplicatedStorage/Shared/Art/CritterArt")

	local function part(model, name)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == name then
				return d
			end
		end
		return nil
	end

	-- Where `p` lies in the head ellipsoid: < 1 inside, 1 on the surface.
	local function inHead(head, p)
		local rel = p - head.CFrame.Position
		local half = head.Size / 2
		return math.sqrt((rel.X / half.X) ^ 2 + (rel.Y / half.Y) ^ 2 + (rel.Z / half.Z) ^ 2)
	end

	t.test("a rabbit's eyes sit one per side, just inside its head", function()
		for _, snowy in ipairs({ false, true }) do
			for _, seed in ipairs({ 1, 2, 9 }) do
				local rabbit = CritterArt.Rabbit(seed, snowy)
				local head = part(rabbit, "Head")
				local left, right = part(rabbit, "EyeL"), part(rabbit, "EyeR")
				t.ok(head and left and right, "a head and two eyes")
				local l, r = left.CFrame.Position, right.CFrame.Position
				t.ok(l.X < 0 and r.X > 0, "EyeL on the left, EyeR on the right")
				t.ok(math.abs(l.X + r.X) < 1e-4 and math.abs(l.Y - r.Y) < 1e-4, "the eyes mirror each other")
				t.ok(math.abs(l.Z - r.Z) < 1e-4, "the eyes mirror each other")
				for _, eye in ipairs({ left, right }) do
					t.ok(math.abs(eye.Size.X - 0.09 * CritterArt.RabbitScale) < 1e-4, "an eye grows with the rabbit")
					local pos = eye.CFrame.Position
					local depth = inHead(head, pos)
					t.ok(depth < 1, "an eye's centre is inside the head")
					-- Its outer edge breaks the surface, so it shows, but only just.
					local out = pos + (pos - head.CFrame.Position).Unit * eye.Size.X / 2
					local edge = inHead(head, out)
					t.ok(edge > 1 and edge < 1.15, string.format("an eye's edge sits at %.2f of the head", edge))
				end
			end
		end
	end)

	-- Where `model` reaches: the ear tips (its highest point).
	local function topOf(model)
		local top = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				top = math.max(top, d.CFrame.Position.Y + d.Size.Y / 2)
			end
		end
		return top
	end

	t.test("a rabbit is 2x to 2.5x its first, loaf-sized draft, and ears and tail grow with it", function()
		t.ok(CritterArt.RabbitScale >= 2 and CritterArt.RabbitScale <= 2.5, "Connor's 2x to 2.5x")
		local old = CritterArt.Rabbit(1, false, 1)
		local new = CritterArt.Rabbit(1)
		local ratio = topOf(new) / topOf(old)
		t.ok(math.abs(ratio - CritterArt.RabbitScale) < 0.05, string.format("ear tips grew %.2fx", ratio))
		for _, name in ipairs({ "Body", "Head", "EarL", "EarR", "Tail", "Nose" }) do
			local a, b = part(old, name), part(new, name)
			t.ok(a and b, name .. " exists")
			t.ok(math.abs(b.Size.Y / a.Size.Y - CritterArt.RabbitScale) < 1e-3, name .. " is scaled with the rest")
			t.ok(
				math.abs(b.CFrame.Position.Y / a.CFrame.Position.Y - CritterArt.RabbitScale) < 1e-3,
				name .. " sits where the scaled body puts it"
			)
		end
		-- The head still nods about a hinge on the scaled neck.
		local hinge = part(new, "Head"):GetAttribute("Hinge")
		local oldHinge = part(old, "Head"):GetAttribute("Hinge")
		t.ok(math.abs(hinge.Y / oldHinge.Y - CritterArt.RabbitScale) < 1e-3, "the head hinge scales")
		t.ok(math.abs(topOf(new) - 3.8) < 0.3, "ear tips about 3.8 studs: a rabbit next to a 5-stud player")
	end)

	t.test("a rabbit is still decoration: it never collides, is touched or is clicked", function()
		for _, snowy in ipairs({ false, true }) do
			local rabbit = CritterArt.Rabbit(2, snowy)
			for _, d in ipairs(rabbit:GetDescendants()) do
				if d:IsA("BasePart") then
					t.eq(d.CanCollide, false, d.Name .. " does not collide")
					t.eq(d.CanQuery, false, d.Name .. " is not clickable")
					t.eq(d.CanTouch, false, d.Name .. " is not touched")
					t.eq(d.CastShadow, false, d.Name .. " casts no shadow")
				end
			end
		end
	end)

	t.test("a bigger rabbit hops higher but not twice as fast; fleeing is quicker, and slower than a deer", function()
		local small, big = CritterArt.RabbitHop(false, 1), CritterArt.RabbitHop(false)
		t.eq(small.lift, 0.55)
		t.eq(small.length, 1.5)
		t.eq(small.seconds, 0.36)
		t.ok(math.abs(big.lift - 0.55 * CritterArt.RabbitScale) < 1e-6, "the arc grows with the body")
		t.ok(big.length > small.length and big.length < small.length * CritterArt.RabbitScale, "the stride grows less")
		local function speed(hop)
			return hop.length / hop.seconds
		end
		local flee = CritterArt.RabbitHop(true)
		t.ok(speed(flee) > speed(big) * 2, "fleeing is much quicker than a stroll")
		t.ok(speed(flee) < 20, "a fleeing rabbit is slower than AmbientLife's deer (20 studs a second)")
		t.ok(speed(flee) > 10, "but still bounds away from a walking player")
	end)

	t.test("AmbientLife's rabbit rules still hold at the new size", function()
		local fs = require("@lune/fs")
		local life = fs.readFile("src/StarterPlayer/StarterPlayerScripts/AmbientLife.luau")
		local from = string.find(life, "local function stepRabbit", 1, true)
		local to = string.find(life, "local function stepDeer", 1, true)
		local rabbit = string.sub(life, from, to)
		t.ok(string.find(rabbit, "CritterArt.RabbitHop(", 1, true) ~= nil, "the hop comes from CritterArt")
		t.ok(string.find(rabbit, "dist < 25", 1, true) ~= nil, "it still bolts at 25 studs")
		t.ok(string.find(rabbit, "findGround(ctx.player, 30, 70, 6)", 1, true) ~= nil, "it spawns 30 to 70 studs out")
	end)

	local function countParts(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				t.eq(d.CanCollide, false, model.Name .. " " .. d.Name .. " no collide")
				t.eq(d.CanQuery, false, model.Name .. " no query")
				t.eq(d.CanTouch, false, model.Name .. " no touch")
			end
			if d:IsA("PointLight") then
				t.eq(d.Shadows, false, "critter light")
			end
		end
		return n
	end

	t.test("gull, snow fox and sky moth stay under 12 parts", function()
		t.ok(countParts(CritterArt.Gull(1)) <= 12, "gull")
		t.ok(countParts(CritterArt.SnowFox(2)) <= 12, "snow fox")
		t.ok(countParts(CritterArt.SkyMoth(3)) <= 12, "sky moth")
		t.eq(CritterArt.Gull(1):GetAttribute("Critter"), "Gull")
		t.eq(CritterArt.SnowFox(1):GetAttribute("Critter"), "SnowFox")
		t.eq(CritterArt.SkyMoth(1):GetAttribute("Critter"), "SkyMoth")
	end)
end
