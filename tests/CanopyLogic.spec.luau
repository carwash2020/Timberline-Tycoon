--!nocheck
-- CanopyLogic (Shared/CanopyLogic): the rules behind CanopyFade (NAT-02,
-- leaves never hide you).
--   * Canopy parts are exactly WindSway's (Leaves, Frond, the parts of Tier
--     models, top-level Facets) on every wood, and never the trunk,
--     branches or roots. None of them collide (Poppercam and trucks rely on
--     it), and each leafy wood has some a ray can hit.
--   * Reach covers every wood's widest canopy at every size and as an
--     Elder, with room to spare for sway, so the trees CanopyFade leaves
--     out of its rays can't be in the way.
--   * The ray loop finds each tree once, keeps only canopy hits, and stops
--     when the way is clear or after six rays.
--   * The fade: in the way it reaches 0.7 in 0.1 s; 0.3 s after its last
--     hit it eases back to 0; and a part someone else set is never owned
--     (letting a felled tree go, not even one at 0: TreeFX's fade starts
--     there), with the ease back done before TreeFX's fade begins.
return function(t)
	local roblox = t.roblox
	local Vector3, Instance = roblox.Vector3, roblox.Instance
	local CanopyLogic = t.shared("CanopyLogic")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local WoodData = t.shared("WoodData")
	local TreeLogic = t.shared("TreeLogic")
	local ForestLogic = t.shared("ForestLogic")

	local function scales(def)
		local out = {}
		for _, size in ipairs(TreeLogic.Sizes) do
			table.insert(out, size.scale)
		end
		table.insert(out, ForestLogic.ElderSize(def).scale)
		return out
	end

	-- WindSway's own test for a canopy part, written out again.
	local function windSwayCanopy(part, tree)
		local parent = part.Parent
		local inTier = parent ~= nil and parent ~= tree and parent:IsA("Model") and parent.Name == "Tier"
		local snowCap = part.Name == "Facet" and parent == tree
		return part.Name == "Leaves" or part.Name == "Frond" or inTier or snowCap
	end

	t.test("the numbers are the lead's", function()
		t.eq(CanopyLogic.Every, 0.1) -- 10 Hz
		t.eq(CanopyLogic.MaxCasts, 6)
		t.eq(CanopyLogic.Fade, 0.7)
		t.eq(CanopyLogic.Hold, 0.3)
	end)

	t.test("canopy parts are WindSway's, on every wood, never the trunk, branches or roots", function()
		for _, def in ipairs(WoodData.All()) do
			for _, seed in ipairs({ 1, 42 }) do
				local tree = TreeArt.Build(def, seed, 1)
				local canopy = {}
				for _, p in ipairs(CanopyLogic.CanopyParts(tree)) do
					canopy[p] = true
				end
				local count, hittable = 0, 0
				for _, d in ipairs(tree:GetDescendants()) do
					if d:IsA("BasePart") then
						t.eq(CanopyLogic.IsCanopyPart(d, tree), windSwayCanopy(d, tree))
						t.eq(canopy[d] == true, windSwayCanopy(d, tree))
						if canopy[d] then
							count += 1
							t.ok(
								d.Name ~= "Trunk" and d.Name ~= "Branch" and d.Name ~= "Root",
								def.id .. ": a " .. d.Name .. " counted as canopy"
							)
							t.eq(d.CanCollide, false, def.id .. ": a canopy part collides")
							if d.CanQuery then
								hittable += 1
							end
						end
					end
				end
				t.ok(count > 0, def.id .. " has a canopy")
				t.ok(hittable > 0, def.id .. ": a ray can hit its canopy")
				t.eq(CanopyLogic.IsCanopyPart(tree.PrimaryPart, tree), false)
			end
		end
	end)

	t.test("a part outside the tree, or not a part, is never its canopy", function()
		local tree = TreeArt.Build(WoodData.Get("oak"), 1, 1)
		local other = TreeArt.Build(WoodData.Get("oak"), 2, 1)
		local leaf = CanopyLogic.CanopyParts(other)[1]
		t.eq(CanopyLogic.IsCanopyPart(leaf, tree), false)
		t.eq(CanopyLogic.IsCanopyPart(Instance.new("Folder"), tree), false)
		local loose = Instance.new("Part")
		loose.Name = "Leaves"
		t.eq(CanopyLogic.IsCanopyPart(loose, tree), false)
	end)

	t.test("Reach covers every canopy, an Elder's too, with room for sway", function()
		local widest, widestId = 0, ""
		for _, def in ipairs(WoodData.All()) do
			for _, scale in ipairs(scales(def)) do
				for _, seed in ipairs({ 1, 7, 42, 777, 1234 }) do
					local tree = TreeArt.Build(def, seed, scale)
					local axis = tree.PrimaryPart.CFrame.Position -- HomePivot's position
					for _, p in ipairs(CanopyLogic.CanopyParts(tree)) do
						local cf, h = p.CFrame, p.Size / 2
						for _, sx in ipairs({ -1, 1 }) do
							for _, sy in ipairs({ -1, 1 }) do
								for _, sz in ipairs({ -1, 1 }) do
									local c = cf * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
									local d = math.sqrt((c.X - axis.X) ^ 2 + (c.Z - axis.Z) ^ 2)
									if d > widest then
										widest, widestId = d, def.id .. " x" .. scale
									end
								end
							end
						end
					end
				end
			end
		end
		t.ok(
			widest <= CanopyLogic.Reach - 3,
			string.format("%s's canopy reaches %.1f studs out; Reach is %d", widestId, widest, CanopyLogic.Reach)
		)
	end)

	t.test("the distance to the line of sight is measured on the ground plane", function()
		local a, b = Vector3.new(0, 20, 0), Vector3.new(10, 2, 0)
		t.ok(math.abs(CanopyLogic.DistanceXZ(Vector3.new(5, 0, 3), a, b) - 3) < 1e-9, "beside the middle")
		t.ok(math.abs(CanopyLogic.DistanceXZ(Vector3.new(5, 90, -4), a, b) - 4) < 1e-9, "height doesn't count")
		t.ok(math.abs(CanopyLogic.DistanceXZ(Vector3.new(-3, 0, 4), a, b) - 5) < 1e-9, "past the camera's end")
		t.ok(math.abs(CanopyLogic.DistanceXZ(Vector3.new(13, 0, 4), a, b) - 5) < 1e-9, "past your end")
		-- Looking straight down: the line is a point on the ground plane.
		t.ok(math.abs(CanopyLogic.DistanceXZ(Vector3.new(3, 0, 4), a, Vector3.new(0, 2, 0)) - 5) < 1e-9)
		t.eq(CanopyLogic.NearSightline(Vector3.new(5, 0, CanopyLogic.Reach), a, b), true)
		t.eq(CanopyLogic.NearSightline(Vector3.new(5, 0, CanopyLogic.Reach + 0.1), a, b), false)
	end)

	-- A fake ray: it hits the first tree in `line` it isn't told to skip.
	local function caster(line)
		local calls = {}
		local function cast(exclude)
			table.insert(calls, table.clone(exclude))
			for _, hit in ipairs(line) do
				if not exclude[hit.tree] then
					return hit.tree, hit.canopy
				end
			end
			return nil, false
		end
		return cast, calls
	end

	t.test("each ray skips the trees found so far, and only canopy hits count", function()
		local cast, calls = caster({
			{ tree = "a", canopy = true },
			{ tree = "b", canopy = false }, -- its trunk: skipped, never faded
			{ tree = "c", canopy = true },
		})
		t.eq(CanopyLogic.Trace(cast), { "a", "c" })
		t.eq(#calls, 4, "three hits, then a clear ray")
		t.eq(calls[1], {})
		t.eq(calls[2], { a = true })
		t.eq(calls[3], { a = true, b = true })
		t.eq(calls[4], { a = true, b = true, c = true })
	end)

	t.test("at most six rays per target", function()
		local line = {}
		for i = 1, 20 do
			table.insert(line, { tree = i, canopy = true })
		end
		local cast, calls = caster(line)
		t.eq(CanopyLogic.Trace(cast), { 1, 2, 3, 4, 5, 6 })
		t.eq(#calls, 6)
		local cast2, calls2 = caster(line)
		t.eq(#CanopyLogic.Trace(cast2, 2), 2)
		t.eq(#calls2, 2)
	end)

	t.test("a clear way, or a ray that ignores the skip list, stops at once", function()
		local cast, calls = caster({})
		t.eq(CanopyLogic.Trace(cast), {})
		t.eq(#calls, 1)
		local n = 0
		local stuck = function()
			n += 1
			return "a", true -- ignores what it was told to skip
		end
		t.eq(CanopyLogic.Trace(stuck), { "a" })
		t.eq(n, 2, "no endless loop on the same tree")
	end)

	t.test("in the way, a canopy fades to 0.7 in 0.1 s and holds", function()
		local a, dt = 0, 1 / 60
		local steps = 0
		while a < CanopyLogic.Fade do
			a = CanopyLogic.Step(a, 0, dt)
			steps += 1
			t.ok(a <= CanopyLogic.Fade, "never past 0.7")
		end
		t.ok(steps * dt <= CanopyLogic.FadeInTime + 1e-6, "faded within 0.1 s")
		t.eq(CanopyLogic.Step(CanopyLogic.Fade, 0.29, dt), CanopyLogic.Fade)
	end)

	t.test("0.3 s after its last hit it eases back to 0, and stays there", function()
		local a, dt = CanopyLogic.Fade, 1 / 60
		local since = 0
		while since < CanopyLogic.Hold - 1e-9 do
			a = CanopyLogic.Step(a, since, dt)
			t.eq(a, CanopyLogic.Fade, "held for 0.3 s")
			since += dt
		end
		local last = a
		local back = 0
		while a > 0 do
			a = CanopyLogic.Step(a, since, dt)
			t.ok(a < last, "it only comes back")
			last = a
			since += dt
			back += dt
		end
		t.eq(a, 0)
		t.ok(back <= CanopyLogic.FadeOutTime + 1e-6, "back within FadeOutTime")
		t.eq(CanopyLogic.Step(0, 5, dt), 0)
	end)

	t.test("a part someone else set is never owned", function()
		-- What was written reads back as a 32-bit float.
		t.eq(CanopyLogic.Owns(0.699999988079071, 0.7), true)
		t.eq(CanopyLogic.Owns(0, 0.7), true) -- put back by someone (TreeFX's unfade): free
		t.eq(CanopyLogic.Owns(0, 0), true)
		t.eq(CanopyLogic.Owns(1, 0.7), false) -- TreeFX's felled fade
		t.eq(CanopyLogic.Owns(1, 0), false)
		t.eq(CanopyLogic.Owns(0.4, 0.7), false)
	end)

	t.test("letting a felled tree go, a part at 0 is TreeFX's (its fade starts there)", function()
		t.eq(CanopyLogic.Owns(0.3, 0.3, true), true, "still where it was left: still ours to ease back")
		t.eq(CanopyLogic.Owns(0.29999998, 0.3, true), true)
		t.eq(CanopyLogic.Owns(0.0004, 0.3, true), false, "TreeFX's first fade frame")
		t.eq(CanopyLogic.Owns(0, 0.3, true), false)
		t.eq(CanopyLogic.Owns(0.06, 0.3, true), false)
		t.eq(CanopyLogic.Owns(0, 0, true), true, "nothing faded, nothing taken")
		t.eq(CanopyLogic.Owns(0, 0.3, false), true, "otherwise 0 is free, as before")
	end)

	t.test("easing back takes at most FadeOutTime, well before TreeFX's felled fade", function()
		-- CanopyFade lets a felled tree's canopy ease back from Fade over
		-- FadeOutTime; TreeFX starts fading the fallen tree at FellFadeStart.
		t.ok(
			CanopyLogic.FadeOutTime + CanopyLogic.Every < TreeLogic.FellFadeStart,
			"the ease is done before TreeFX's fade begins"
		)
	end)
end
