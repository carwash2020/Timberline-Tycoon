--!nocheck
-- TemperLook: the prefixes TemperLogic exports, tiers 1 to 3. Look only.
-- Keen is speed (sky blue wind). Heavy is damage (white sheen).
-- Prosperous stays coin gold.
-- Tier 1 is trim (glow 0, no particle). Tier 2 adds a thin edge (glow > 0).
-- Tier 3 names a client particle.

return function(t)
	local TemperLook = t.load("ReplicatedStorage/Shared/Art/TemperLook")
	local TemperLogic = t.load("ReplicatedStorage/Shared/TemperLogic")

	local function hex(color)
		return string.format(
			"#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5)
		)
	end

	t.test("the looks are exactly the prefixes TemperLogic exports", function()
		local exported = {}
		for _, prefix in ipairs(TemperLogic.Prefixes) do
			exported[prefix] = true
			t.eq(TemperLook.Known(prefix), true, prefix)
			t.ok(TemperLook.For(prefix, 1) ~= nil, prefix .. " has a tier 1 look")
			t.eq(TemperLook.For(prefix, 0), nil, prefix .. " tier 0")
			t.eq(TemperLook.For(prefix, 4), nil, prefix .. " tier 4")
		end
		local looks = TemperLook.Prefixes()
		t.eq(#looks, #TemperLogic.Prefixes, "no extra look and none missing")
		for _, prefix in ipairs(looks) do
			t.eq(exported[prefix], true, prefix .. " is a TemperLogic prefix")
		end
		t.eq(TemperLook.Known("Swift"), false, "Swift is not a temper")
		t.eq(TemperLook.For("Bogus", 1), nil)
	end)

	t.test("Keen is sky blue wind, Heavy is a white sheen, Prosperous is gold", function()
		local byName = {}
		for _, prefix in ipairs(TemperLogic.Prefixes) do
			byName[prefix] = TemperLook.For(prefix, 3)
		end
		local keen = byName.Keen
		local heavy = byName.Heavy
		local rich = byName.Prosperous
		t.ok(keen and heavy and rich, "all three looks")
		t.eq(hex(keen.trimColor), "#6FB7E8")
		t.eq(keen.particle, "Wind")
		t.eq(hex(heavy.trimColor), "#FFFFFF")
		t.eq(heavy.particle, "Sheen")
		t.eq(hex(rich.trimColor), "#F2C14E")
		t.eq(rich.particle, "Sparkle")
	end)

	t.test("tier 1 is trim, tier 2 glows, tier 3 names a particle", function()
		local speed = TemperLogic.Prefixes[1]
		for _, prefix in ipairs(TemperLogic.Prefixes) do
			if TemperLook.For(prefix, 3).particle == "Wind" then
				speed = prefix
			end
		end
		local a = TemperLook.For(speed, 1)
		local b = TemperLook.For(speed, 2)
		local c = TemperLook.For(speed, 3)
		t.eq(a.glow, 0)
		t.eq(a.particle, nil)
		t.ok(b.glow > 0, "tier 2 glow")
		t.eq(b.particle, nil)
		t.ok(c.glow > b.glow, "tier 3 glows more")
		t.eq(c.particle, "Wind")
		t.eq(hex(a.trimColor), hex(c.trimColor))
	end)
end
