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

	local function near(a, b)
		return math.abs(a - b) < 1e-3
	end

	local function nearHex(color, hex)
		local want = roblox.Color3.fromHex(hex)
		return math.abs(color.R - want.R) < 0.01
			and math.abs(color.G - want.G) < 0.01
			and math.abs(color.B - want.B) < 0.01
	end

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

	t.test("the haft is 0.26 by the gameplay length by 0.32, the grip 0.31 x 0.95 x 0.37", function()
		local AxeModels = t.load("ReplicatedStorage/Shared/Art/AxeModels")
		each(function(def)
			local m = AxeArt.Build(def)
			local handle = m.PrimaryPart
			t.ok(near(handle.Size.X, 0.26), def.id .. " haft width")
			t.ok(near(handle.Size.Z, 0.32), def.id .. " haft depth")
			t.ok(near(handle.Size.Y, AxeModels.GameplayLength(def.id)), def.id .. " haft length")
			local grip = m:FindFirstChild("Grip")
			t.ok(near(grip.Size.X, 0.31) and near(grip.Size.Y, 0.95) and near(grip.Size.Z, 0.37), def.id .. " grip")
		end)
	end)

	-- Starfall: a cream haft, a star-tipped head in front of a smaller one,
	-- pale neon, a spark. The front head reaches further than the back.
	t.test("Starfall: a cream haft, a star-tipped double head, a pale neon spark", function()
		local def = ItemCatalog.Axes.StarfallAxe
		local m = AxeArt.Build(def)
		t.ok(nearHex(m.PrimaryPart.Color, "#F2E6C8"), "the haft is cream #F2E6C8")
		local star, back = false, false
		local starZ, backZ = 0, 0
		for _, p in ipairs(parts(m)) do
			if p.Name == "Star" then
				star = true
				starZ = math.max(starZ, p.Size.Z)
				t.eq(p.Material.Name, "Neon", "the star is Neon")
				t.ok(nearHex(p.Color, "#BFD8FF"), "pale blue head")
			elseif p.Name == "StarBack" then
				back = true
				backZ = math.max(backZ, p.Size.Z)
			end
		end
		t.ok(star and back, "a front star and a back star")
		t.ok(starZ > backZ + 0.05, "the front head is the larger one")
		local spark = m:FindFirstChild("Spark", true)
		t.ok(spark and spark:IsA("ParticleEmitter"), "named Spark")
		t.ok(m:FindFirstChildWhichIsA("PointLight", true) ~= nil, "a spark light")
		local lo, hi = bounds(m)
		t.ok(-lo.Z > hi.Z + 0.1, "the front head reaches past the back one")
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

	t.test("the Lux Axe: a gold haft, a readable bit, a fan behind it, the 3.5 gameplay haft", function()
		local def = ItemCatalog.GetAxe("LuxAxe")
		t.ok(AxeArt.Designed("LuxAxe"))
		local m = AxeArt.Build(def)
		t.eq(m.PrimaryPart.Name, "Handle")
		t.eq(m.PrimaryPart.Size.Y, 3.5, "the gameplay haft, not the 4.0 design length")
		t.ok(#parts(m) <= MAX_PARTS, "part budget")
		local lo, hi = bounds(m)
		t.ok(math.abs(lo.Y) < 0.05, "foot on the ground")
		t.ok(hi.Y - lo.Y >= 2.8 and hi.Y - lo.Y <= 4.4, "a sensible height")
		t.ok(lo.Z < -0.5, "blade toward -Z")
		t.ok(nearHex(m.PrimaryPart.Color, "#F2D36B"), "gold haft")
		local fan = false
		local bladeY = 0
		for _, p in ipairs(parts(m)) do
			if p.Name == "Fan" then
				fan = true
				t.ok(nearHex(p.Color, "#F2D36B"), "gold fan")
			elseif p.Name == "Blade" then
				bladeY += p.Size.Y
			end
		end
		t.ok(fan, "a fan behind the head")
		t.ok(bladeY >= 1.4, "an axe head, not only a glow")
		local glint = m:FindFirstChild("Glint", true)
		t.ok(glint and glint:IsA("ParticleEmitter"), "named Glint")
		local light = m:FindFirstChildWhichIsA("PointLight", true)
		t.ok(light ~= nil, "a glint light")
		t.ok(light.Range <= 4, "the glow stays on the head")
	end)

	t.test("the Hermit's Maul is a heavy wedge, twice a Steel blade, and it does not glow", function()
		local AxeModels = t.load("ReplicatedStorage/Shared/Art/AxeModels")
		t.ok(AxeArt.Designed("HermitsMaul"))
		local m = AxeArt.Build(ItemCatalog.GetAxe("HermitsMaul"))
		local steel = AxeModels.Look("SteelAxe")
		local spanY, thick, heads = 0, 0, 0
		for _, p in ipairs(parts(m)) do
			if p.Name == "Head" then
				heads += 1
				spanY += p.Size.Y
				thick = math.max(thick, p.Size.X)
			end
		end
		t.ok(heads >= 2, "a wedge, not one box")
		local blade = math.max(steel.head.Y, steel.head.Z)
		t.ok(spanY + 1e-3 >= blade * 2, string.format("head %.2f vs twice a Steel blade %.2f", spanY, blade * 2))
		t.ok(thick < 1.15, "thin enough to lie flat")
		t.ok(m:FindFirstChild("Poll") ~= nil, "a hammer poll")
		t.ok(m:FindFirstChild("Rope") ~= nil, "rope wrap")
		t.eq(m:FindFirstChildWhichIsA("PointLight", true), nil)
		-- Lying down, the thick head is the height. It has to stay low.
		local dropped = AxeArt.Dropped(ItemCatalog.GetAxe("HermitsMaul"))
		local dlo, dhi = bounds(dropped)
		t.ok(dhi.Y - dlo.Y < 1.2, string.format("maul stands %.2f tall", dhi.Y - dlo.Y))
	end)

	t.test("a temper dresses the axe, and a nil prefix changes nothing", function()
		local def = ItemCatalog.GetAxe("SteelAxe")
		local m = AxeArt.Build(def)
		local before = #parts(m)
		AxeArt.ApplyTemper(m, nil, 3)
		t.eq(#parts(m), before, "nil prefix adds nothing")
		t.eq(m:FindFirstChild("TemperTrim", true), nil)
		AxeArt.ApplyTemper(m, "", 1)
		t.eq(m:FindFirstChild("TemperTrim", true), nil)
		AxeArt.ApplyTemper(m, "Bogus", 2)
		t.eq(m:FindFirstChild("TemperTrim", true), nil)

		AxeArt.ApplyTemper(m, "Keen", 1)
		local trim = m:FindFirstChild("TemperTrim")
		t.ok(trim and trim:IsA("BasePart"), "tier 1 trim")
		t.ok(nearHex(trim.Color, "#6FB7E8"), "SkyBlue speed trim")
		t.eq(m:FindFirstChild("TemperEdge", true), nil, "tier 1 has no edge")
		t.eq(m:FindFirstChild("TemperFx", true), nil, "tier 1 has no particle")
		local weld = trim:FindFirstChild("Weld")
		t.ok(weld and weld.Part0 == m.PrimaryPart and weld.Part1 == trim, "trim welded to the Handle")

		AxeArt.ApplyTemper(m, "Heavy", 2)
		local trims = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d.Name == "TemperTrim" then
				trims += 1
			end
		end
		t.eq(trims, 1, "applying again replaces the trim")
		local edge = m:FindFirstChild("TemperEdge")
		t.ok(edge and edge.Material.Name == "Neon", "tier 2 neon edge")
		t.ok(nearHex(edge.Color, "#FFFFFF"), "white sheen")
		t.eq(m:FindFirstChild("TemperFx", true), nil)

		AxeArt.ApplyTemper(m, "Prosperous", 3)
		local fx = m:FindFirstChild("TemperFx", true)
		t.ok(fx and fx:IsA("ParticleEmitter"), "tier 3 particle")
		t.eq(fx.Rate, 3)
		t.eq(fx:GetAttribute("Kind"), "Sparkle")
		local goldTrim = m:FindFirstChild("TemperTrim")
		t.ok(nearHex(goldTrim.Color, "#F2C14E"), "CoinGold")
		t.ok(#parts(m) <= MAX_PARTS, "a temper stays inside the part budget")

		-- A nil prefix does not strip a temper that is already there.
		AxeArt.ApplyTemper(m, nil, 1)
		t.ok(m:FindFirstChild("TemperTrim") ~= nil, "nil leaves the temper")
	end)
end
