--!nocheck
-- T415 shadows: scatter, critters and small props cast no shadow. A part whose largest side is under
-- PerfPolicy.NoShadowSize is too small for its shadow to read; big rocks and stumps keep theirs.
return function(t)
	local PerfPolicy = t.shared("PerfPolicy")
	local Greenery = t.load("ReplicatedStorage/Shared/Art/Greenery")
	local CritterArt = t.load("ReplicatedStorage/Shared/Art/CritterArt")
	local Scatter = t.load("ReplicatedStorage/Shared/World/Scatter")
	local roblox = t.roblox

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function biggest(p)
		return math.max(p.Size.X, p.Size.Y, p.Size.Z)
	end

	t.test("the size rule is a number and a function", function()
		t.ok(PerfPolicy.NoShadowSize > 0 and PerfPolicy.NoShadowSize <= 4)
		local small = roblox.Instance.new("Part")
		small.Size = roblox.Vector3.new(0.4, 1, 0.4)
		t.eq(PerfPolicy.ShadowOff(small), true)
		local big = roblox.Instance.new("Part")
		big.Size = roblox.Vector3.new(6, 1, 6)
		t.eq(PerfPolicy.ShadowOff(big), false)
	end)

	t.test("every built scatter kind: parts under the size rule cast no shadow, in every region", function()
		local checked, kept = 0, 0
		for _, region in ipairs(Scatter.Regions) do
			for _, kind in ipairs({
				"stump",
				"rock",
				"sapling",
				"snag",
				"grass",
				"fern",
				"shrub",
				"scrub",
				"reed",
				"flower",
				"pebble",
			}) do
				for variant = 1, 3 do
					for _, size in ipairs({ 1.5, 3, 6 }) do
						local model = Greenery.Item(kind, region, variant, size)
						if model then
							for _, p in ipairs(parts(model)) do
								checked += 1
								if biggest(p) < PerfPolicy.NoShadowSize then
									t.eq(p.CastShadow, false, region .. " " .. kind .. " " .. p.Name)
								else
									kept += 1
								end
							end
						end
					end
				end
			end
		end
		t.ok(checked > 500, "checked " .. checked)
		t.ok(kept > 0, "large parts are left alone (no blanket switch-off)")
	end)

	t.test("every critter part casts no shadow", function()
		local made = {
			CritterArt.Bird(1),
			CritterArt.Butterfly(1),
			CritterArt.Rabbit(1),
			CritterArt.Deer(1),
			CritterArt.Duck(1),
			CritterArt.Fish(1),
			CritterArt.Gull(1),
			CritterArt.SnowFox(1),
		}
		for _, model in ipairs(made) do
			for _, p in ipairs(parts(model)) do
				t.eq(p.CastShadow, false, model.Name .. " " .. p.Name)
			end
		end
	end)
end
