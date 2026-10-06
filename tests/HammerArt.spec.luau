--!nocheck
-- HammerArt and BlueprintArt (Shared/Art): the hammer and the rolled plan
-- are Tool-ready models (a "Handle" with everything welded to it), small,
-- and read at a glance. Held pieces are inert; a dropped plan lies on the
-- ground.
return function(t)
	local Vector3 = t.roblox.Vector3
	local HammerArt = t.load("ReplicatedStorage/Shared/Art/HammerArt")
	local BlueprintArt = t.load("ReplicatedStorage/Shared/Art/BlueprintArt")
	local PlotData = t.shared("PlotData")

	local MAX_PARTS = 20

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
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

	local function wellFormed(model, name)
		local handle = model.PrimaryPart
		t.ok(handle ~= nil and handle.Name == "Handle", name .. " has a Handle for a Tool")
		local count = #parts(model)
		t.ok(count >= 4 and count <= MAX_PARTS, name .. " part budget: " .. count)
		for _, p in ipairs(parts(model)) do
			if p ~= handle then
				local weld = p:FindFirstChildOfClass("Weld")
				t.ok(
					weld ~= nil and weld.Part0 == handle and weld.Part1 == p,
					name .. " " .. p.Name .. " is welded to the Handle"
				)
			end
		end
	end

	t.test("the hammer is a Tool-ready model standing on its foot with the face forward", function()
		local model = HammerArt.Build()
		wellFormed(model, "hammer")
		local lo, hi = bounds(model)
		t.ok(math.abs(lo.Y) < 0.01, "the foot is at y = 0: " .. lo.Y)
		t.ok(hi.Y > 1.8 and hi.Y < 2.6, "about two studs tall: " .. hi.Y)
		t.ok(lo.Z < -0.6, "the face sticks out front (-Z): " .. lo.Z)
		t.ok(hi.Z > 0.6, "the claw sticks out behind (+Z): " .. hi.Z)
		t.ok(hi.X - lo.X < 0.8, "slim across")
		-- The face is where the dust goes.
		t.ok(math.abs(HammerArt.StrikePoint.Z - lo.Z) < 0.3)
		t.ok(HammerArt.StrikePoint.Y > 1.5)
	end)

	t.test("a held hammer is inert: nothing anchored, nothing collides, nothing weighs", function()
		for _, p in ipairs(parts(HammerArt.Held())) do
			t.eq(p.Anchored, false, p.Name)
			t.eq(p.CanCollide, false, p.Name)
			t.eq(p.Massless, true, p.Name)
		end
	end)

	t.test("the hammer's grip moves with the swing's pitch and returns when the pitch does", function()
		local rest = HammerArt.Grip()
		t.eq(HammerArt.Grip(0), rest)
		t.ok(HammerArt.Grip(0.8) ~= rest)
		t.ok(HammerArt.Grip(-0.4) ~= rest)
		local back = HammerArt.Grip(0.8) * HammerArt.Grip(0.8):Inverse()
		t.ok((back.Position).Magnitude < 1e-6, "a grip times its inverse is nothing")
	end)

	t.test("every plan builds a Tool-ready roll, in a colour that says what it holds", function()
		local colors = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			local model = BlueprintArt.Build(bp.id)
			t.ok(model.PrimaryPart ~= nil and model.PrimaryPart.Name == "Handle", bp.id)
			colors[bp.category] = BlueprintArt.SealColor(bp.id)
		end
		wellFormed(BlueprintArt.Build("Shed"), "plan")
		t.ok(colors.Buildings ~= colors.Decor, "Buildings and Decor read differently")
		t.eq(BlueprintArt.SealColor("Nope"), BlueprintArt.SealColor("Nope"))
	end)

	t.test("a plan is a small roll: about a stud and a half, under a stud thick", function()
		local lo, hi = bounds(BlueprintArt.Build("Shed"))
		local size = hi - lo
		local long = math.max(size.X, size.Y, size.Z)
		t.ok(long > 1.3 and long < 2, "long: " .. long)
		t.ok(math.abs(lo.Y) < 0.1, "stands on its foot")
	end)

	t.test("a held plan is inert", function()
		for _, p in ipairs(parts(BlueprintArt.Held("Shed"))) do
			t.eq(p.Anchored, false, p.Name)
			t.eq(p.CanCollide, false, p.Name)
			t.eq(p.Massless, true, p.Name)
		end
	end)

	t.test("a dropped plan lies on the ground, anchored and non-colliding", function()
		local model = BlueprintArt.Dropped("Mailbox")
		for _, p in ipairs(parts(model)) do
			t.eq(p.Anchored, true, p.Name)
			t.eq(p.CanCollide, false, p.Name)
		end
		local lo, hi = bounds(model)
		t.ok(math.abs(lo.Y) < 0.06, "lowest point at the ground: " .. lo.Y)
		t.ok(hi.Y < 0.8, "lying flat, not standing: " .. hi.Y)
		t.ok(hi.X - lo.X > 1.3, "the roll runs along X")
	end)

	t.test("the plan's grip is a pure turn and tip (the hand holds the middle)", function()
		local grip = BlueprintArt.Grip()
		t.ok(grip.Position.Magnitude < 1e-6)
	end)
end
