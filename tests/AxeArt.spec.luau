--!nocheck
-- AxeArt (Shared/Art): every axe in ItemCatalog has a Tool-ready model (a
-- "Handle" with everything welded to it), a grip that puts the hand near
-- the foot with the blade forward, a dropped version lying on the ground,
-- its own silhouette, and a small part count.

return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local AxeArt = t.load("ReplicatedStorage/Shared/Art/AxeArt")
	local ItemCatalog = t.shared("ItemCatalog")

	local MAX_PARTS = 40

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function each(fn)
		for _, def in ipairs(ItemCatalog.AxeLadder()) do
			fn(def)
		end
	end

	local function bounds(model)
		local lo, hi
		for _, p in ipairs(parts(model)) do
			local cf, h = p.CFrame, p.Size / 2
			for _, x in ipairs({ -1, 1 }) do
				for _, y in ipairs({ -1, 1 }) do
					for _, z in ipairs({ -1, 1 }) do
						local c = cf * Vector3.new(h.X * x, h.Y * y, h.Z * z)
						lo = if lo then lo:Min(c) else c
						hi = if hi then hi:Max(c) else c
					end
				end
			end
		end
		return lo, hi
	end

	t.test("every axe has its own design", function()
		each(function(def)
			t.ok(AxeArt.Designed(def.id), def.id .. " uses the generic look")
		end)
	end)

	t.test("a Handle as PrimaryPart, every other part welded to it in place", function()
		each(function(def)
			local m = AxeArt.Build(def)
			local handle = m.PrimaryPart
			t.ok(handle and handle.Name == "Handle", def.id .. ": PrimaryPart Handle")
			t.eq(m:FindFirstChild("Handle"), handle)
			for _, p in ipairs(parts(m)) do
				if p ~= handle then
					local w = p:FindFirstChild("Weld")
					t.ok(w and w.Part0 == handle and w.Part1 == p, def.id .. ": " .. p.Name .. " not welded")
					local at = handle.CFrame * w.C0
					t.ok((at.Position - p.CFrame.Position).Magnitude < 1e-3, def.id .. ": " .. p.Name .. " weld offset")
				end
			end
		end)
	end)

	t.test("part budget: at most " .. MAX_PARTS .. " parts an axe", function()
		each(function(def)
			local n = #parts(AxeArt.Build(def))
			t.ok(n <= MAX_PARTS, string.format("%s has %d parts", def.id, n))
		end)
	end)

	t.test("standing on its foot, blade forward (-Z), a sensible size", function()
		each(function(def)
			local m = AxeArt.Build(def)
			local lo, hi = bounds(m)
			t.ok(math.abs(lo.Y) < 0.02, def.id .. ": foot at y = 0")
			local height = hi.Y - lo.Y
			t.ok(height > 2.8 and height < 4.4, string.format("%s is %.2f long", def.id, height))
			-- The bit reaches further forward than anything behind the haft.
			t.ok(-lo.Z > 0.9, def.id .. ": no blade in front")
			if def.id ~= "GoldAxe" then -- the labrys is double-bitted
				t.ok(-lo.Z > hi.Z + 0.1, def.id .. ": the blade should face -Z")
			end
		end)
	end)

	t.test("held: nothing anchored, collides or weighs anything", function()
		each(function(def)
			for _, p in ipairs(parts(AxeArt.Held(def))) do
				t.ok(not p.Anchored and p.Massless and not p.CanCollide, def.id .. ": " .. p.Name)
			end
		end)
	end)

	t.test("dropped: lying on the ground, anchored, still a Handle to prompt on", function()
		each(function(def)
			local m = AxeArt.Dropped(def)
			t.eq(m.PrimaryPart.Name, "Handle")
			local lo, hi = bounds(m)
			t.ok(math.abs(lo.Y) < 1e-3, def.id .. ": resting on y = 0")
			t.ok(hi.Y - lo.Y < 1.2, string.format("%s stands %.2f tall: not lying flat", def.id, hi.Y - lo.Y))
			for _, p in ipairs(parts(m)) do
				t.ok(p.Anchored and not p.CanCollide, def.id .. ": " .. p.Name)
			end
		end)
	end)

	t.test("grip: the hand near the foot of the haft, the blade forward", function()
		each(function(def)
			local m = AxeArt.Build(def)
			local handle = m.PrimaryPart
			local grip = AxeArt.Grip(def)
			-- Grip's position is where the hand is, in the Handle's space.
			local fromFoot = grip.Position.Y + handle.Size.Y / 2
			t.ok(math.abs(fromFoot - AxeArt.GripFromFoot) < 1e-3, def.id .. ": hand at the foot")
			t.ok(fromFoot < handle.Size.Y * 0.35, def.id .. ": hand too high up the haft")
			-- In the hand's frame (its -Z is the way the raised arm points) the
			-- haft's own -Z, toward the blade, points forward too.
			local handleInHand = grip:Inverse()
			t.ok(handleInHand.LookVector.Z < -0.9, def.id .. ": blade not forward")
			t.ok(handleInHand.UpVector.Y > 0.9, def.id .. ": haft not upright")
		end)
	end)

	t.test("glowing axes glow (a light and particles)", function()
		each(function(def)
			local m = AxeArt.Build(def)
			local light = m:FindFirstChildWhichIsA("PointLight", true)
			local particles = m:FindFirstChildWhichIsA("ParticleEmitter", true)
			if def.look.glow then
				t.ok(light and particles, def.id .. " should glow")
			else
				t.ok(light == nil, def.id .. " shouldn't glow")
			end
		end)
	end)

	t.test("silhouettes differ: no two axes the same size", function()
		local seen = {}
		each(function(def)
			local lo, hi = bounds(AxeArt.Build(def))
			local size = hi - lo
			local key = string.format("%.2f/%.2f", size.Y, size.Z)
			t.ok(not seen[key], def.id .. " has the same outline as " .. tostring(seen[key]))
			seen[key] = def.id
		end)
	end)

	-- ACT-08: Starfall's crescent reads as one unbroken band with one
	-- unbroken glowing rim, on a deep indigo haft, with Neon only on the rim.
	t.test("Starfall: a continuous crescent and rim, an indigo haft, Neon only on the rim", function()
		local def = ItemCatalog.Axes.StarfallAxe
		local m = AxeArt.Build(def)
		local haft = m.PrimaryPart.Color
		t.ok(
			math.abs(haft.R * 255 - 0x2B) < 0.5
				and math.abs(haft.G * 255 - 0x3A) < 0.5
				and math.abs(haft.B * 255 - 0x6B) < 0.5,
			"the haft is deep indigo #2B3A6B"
		)
		local rims, band, middles = {}, {}, {}
		for _, p in ipairs(parts(m)) do
			if p.Name == "Rim" then
				table.insert(rims, p)
			elseif p.Material.Name == "Neon" then
				t.ok(false, "Starfall " .. p.Name .. " is Neon (only the rim glows)")
			end
			if p.Name == "Crescent" or p.Name == "Horn" then
				table.insert(band, p)
			end
			if p.Name == "Crescent" then
				table.insert(middles, p)
			end
		end
		t.ok(#rims >= 3 and #middles == 3, "a rim and three crescent segments")
		-- The arc's centre: the circle (in the side view, y and z) through the
		-- three middle segments.
		local function yz(p)
			local at = p.CFrame.Position
			return at.Y, at.Z
		end
		local ay, az = yz(middles[1])
		local by, bz = yz(middles[2])
		local cy, cz = yz(middles[3])
		local d = 2 * (ay * (bz - cz) + by * (cz - az) + cy * (az - bz))
		local a2, b2, c2 = ay * ay + az * az, by * by + bz * bz, cy * cy + cz * cz
		local oy = (a2 * (bz - cz) + b2 * (cz - az) + c2 * (az - bz)) / d
		local oz = (a2 * (cy - by) + b2 * (ay - cy) + c2 * (by - ay)) / d
		local radius = math.sqrt((ay - oy) ^ 2 + (az - oz) ^ 2)
		local function angleOf(p)
			local y, z = yz(p)
			return math.atan2(y - oy, oz - z)
		end
		local function radiusOf(p)
			local y, z = yz(p)
			return math.sqrt((y - oy) ^ 2 + (z - oz) ^ 2)
		end
		local function isIn(p, y, z)
			local l = p.CFrame:Inverse() * Vector3.new(0, y, z)
			local h = p.Size / 2 + Vector3.new(1e-3, 1e-3, 1e-3)
			return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z
		end
		-- Two neighbouring pieces join when some point on the line halfway
		-- between them (in angle), between radii r0 and r1, is inside both.
		local function joined(a, b, r0, r1)
			local mid = (angleOf(a) + angleOf(b)) / 2
			for i = 0, 200 do
				local r = r0 + (r1 - r0) * i / 200
				local y, z = oy + r * math.sin(mid), oz - r * math.cos(mid)
				if isIn(a, y, z) and isIn(b, y, z) then
					return true
				end
			end
			return false
		end
		local function byAngle(list)
			table.sort(list, function(a, b)
				return angleOf(a) < angleOf(b)
			end)
			return list
		end
		byAngle(rims)
		byAngle(band)
		t.ok(#band == #rims, "a rim piece on every crescent piece")
		-- The rim: every joint closes, so it glows as one unbroken curve.
		for i = 1, #rims - 1 do
			local r = radiusOf(rims[i])
			t.ok(
				joined(rims[i], rims[i + 1], r - 0.2, r + 0.2),
				string.format("a gap in the rim at %.0f degrees", math.deg(angleOf(rims[i])))
			)
		end
		-- The band: every joint closes right out to its outer edge (no notch
		-- under the rim), the horns' joints included.
		for i = 1, #band - 1 do
			t.ok(
				joined(band[i], band[i + 1], radius + 0.12, radius + 0.4),
				string.format("a gap in the crescent at %.0f degrees", math.deg(angleOf(band[i])))
			)
		end
	end)

	t.test("an axe without a design still gets a Handle (the generic look)", function()
		local def = {
			id = "TestAxe",
			displayName = "Test Axe",
			look = { headColor = "#888888", material = "NotAMaterial", glow = true },
			damage = 1,
			priceCash = 1,
		}
		local m = AxeArt.Build(def)
		t.eq(m.PrimaryPart.Name, "Handle")
		t.ok(m:FindFirstChildWhichIsA("PointLight", true), "glow")
		t.ok(AxeArt.Grip(def), "a grip")
	end)
end
