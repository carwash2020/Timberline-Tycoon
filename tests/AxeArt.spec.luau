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
