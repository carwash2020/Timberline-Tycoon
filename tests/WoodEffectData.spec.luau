--!nocheck
-- The wood effect table (WOODFX-T316): exactly five woods have a row, every
-- colour name resolves in Palette, only ember, gloam and lantern are neon,
-- only ember and gloam have an emitter, and the night gate and the lantern
-- constants the older specs read are untouched.
return function(t)
	local WoodData = t.shared("WoodData")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
	local GameConfig = t.shared("GameConfig")

	local FIVE = { "frostwood", "emberwood", "phantomwood", "lumenwood", "lanternwood" }

	t.test("exactly the five effect woods have a row; every other wood has none", function()
		local n = 0
		for id in pairs(WoodData.Effect) do
			n += 1
			t.ok(table.find(FIVE, id) ~= nil, id .. " is one of the five")
		end
		t.eq(n, 5)
		for _, def in ipairs(WoodData.All()) do
			t.eq(WoodData.EffectOf(def.id) ~= nil, table.find(FIVE, def.id) ~= nil, def.id)
		end
		for _, plain in ipairs({ "oak", "birch", "pine", "maple" }) do
			t.eq(WoodData.EffectOf(plain), nil, plain .. " gets no effect")
		end
		t.eq(WoodData.EffectOf(nil), nil)
		t.eq(WoodData.EffectOf(42), nil)
		t.ok(table.isfrozen(WoodData.Effect) and table.isfrozen(WoodData.Effect.emberwood), "frozen")
	end)

	t.test("every accent and glow name resolves in Palette (a hex only for the lantern's own glow)", function()
		for id, row in pairs(WoodData.Effect) do
			for _, name in ipairs({ row.accent or "", row.glow or "" }) do
				if name ~= "" then
					if string.sub(name, 1, 1) == "#" then
						t.eq(id, WoodData.LanternId, "only the lantern stores a hex")
						t.eq(name, WoodData.LanternGlow)
					else
						t.ok(pcall(Palette.Get, name), id .. " " .. name .. " is a Palette name")
					end
				end
			end
			t.ok(row.accent ~= "LumenGlow" and row.glow ~= "LumenGlow", id .. " never uses the sky gate's colour")
		end
	end)

	t.test("the rows say what the brief says", function()
		local E = WoodData.Effect
		t.eq(E.frostwood.accent, "FrostTrim")
		t.eq(E.frostwood.glow, "FrostGlow")
		t.eq(E.frostwood.neon, false)
		t.eq(E.frostwood.emitter, nil)
		t.eq(E.emberwood.accent, "EmberGlow")
		t.eq(E.emberwood.neon, true)
		t.eq(E.emberwood.emitter, "ember")
		t.eq(E.phantomwood.accent, "GloamGlow")
		t.eq(E.phantomwood.neon, true)
		t.eq(E.phantomwood.emitter, "gloam")
		t.eq(E.lumenwood.accent, "LumenCream")
		t.eq(E.lumenwood.glow, nil)
		t.eq(E.lumenwood.neon, false)
		t.eq(E.lanternwood.accent, nil, "lantern keeps its core colour")
		t.eq(E.lanternwood.neon, true)
		t.eq(E.lanternwood.emitter, nil)
	end)

	t.test("neon only on ember, gloam and lantern; an emitter only on ember and gloam", function()
		for id, row in pairs(WoodData.Effect) do
			local neon = id == "emberwood" or id == "phantomwood" or id == "lanternwood"
			t.eq(row.neon, neon, id .. " neon")
			local emits = id == "emberwood" or id == "phantomwood"
			t.eq(row.emitter ~= nil, emits, id .. " emitter")
		end
		t.eq(Palette.Hex("FrostTrim"), "#E8F2FF")
		t.eq(Palette.Hex("LumenCream"), "#F2E6C8")
	end)

	t.test("what the older specs read is untouched", function()
		t.eq(GameConfig.NightGlowWoodId, "lumenwood")
		t.eq(WoodData.LanternId, "lanternwood")
		t.eq(WoodData.LanternGlow, "#FFC45C")
		t.eq(WoodData.Get("phantomwood").displayName, "Gloamwood")
	end)
end
