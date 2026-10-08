--!nocheck
-- TemperLook: Swift, Keen and Prosperous, tiers 1 to 3. Look only.
-- Tier 1 is trim (glow 0, no particle). Tier 2 adds a thin edge (glow > 0).
-- Tier 3 names a client particle.

return function(t)
	local TemperLook = t.load("ReplicatedStorage/Shared/Art/TemperLook")

	local function hex(color)
		return string.format(
			"#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5)
		)
	end

	t.test("the three prefixes, and nothing else", function()
		t.eq(TemperLook.Known("Swift"), true)
		t.eq(TemperLook.Known("Keen"), true)
		t.eq(TemperLook.Known("Prosperous"), true)
		t.eq(TemperLook.Known("Rusty"), false)
		t.eq(TemperLook.For("Bogus", 1), nil)
		t.eq(TemperLook.For("Swift", 0), nil)
		t.eq(TemperLook.For("Swift", 4), nil)
	end)

	t.test("Swift is sky blue wind, Keen white sheen, Prosperous gold sparkles", function()
		local swift = TemperLook.For("Swift", 3)
		local keen = TemperLook.For("Keen", 3)
		local rich = TemperLook.For("Prosperous", 3)
		t.eq(hex(swift.trimColor), "#6FB7E8")
		t.eq(swift.particle, "Wind")
		t.eq(hex(keen.trimColor), "#FFFFFF")
		t.eq(keen.particle, "Sheen")
		t.eq(hex(rich.trimColor), "#F2C14E")
		t.eq(rich.particle, "Sparkle")
	end)

	t.test("tier 1 is trim, tier 2 glows, tier 3 names a particle", function()
		local a = TemperLook.For("Swift", 1)
		local b = TemperLook.For("Swift", 2)
		local c = TemperLook.For("Swift", 3)
		t.eq(a.glow, 0)
		t.eq(a.particle, nil)
		t.ok(b.glow > 0, "tier 2 glow")
		t.eq(b.particle, nil)
		t.ok(c.glow > b.glow, "tier 3 glows more")
		t.eq(c.particle, "Wind")
		t.eq(hex(a.trimColor), hex(c.trimColor))
	end)
end
