--!nocheck
-- BadgeData: ids stay 0, 0 is not awarded, and the list matches the world.
return function(t)
	local Enum = t.roblox.Enum
	local BadgeData = t.shared("BadgeData")
	local GameConfig = t.shared("GameConfig")
	local InputKit = t.shared("InputKit")

	local function keys()
		local list = {}
		for _, def in ipairs(BadgeData.All()) do
			table.insert(list, def.key)
		end
		return list
	end

	t.test("every badge id is 0 until it is pasted, and 0 is not live", function()
		for _, key in ipairs(keys()) do
			t.eq(BadgeData.Ids[key], 0, key)
			t.eq(BadgeData.RobloxId(key), 0, key)
		end
		t.eq(BadgeData.IsLive(0), false)
		t.eq(BadgeData.IsLive(-1), false)
		t.eq(BadgeData.IsLive(1.5), false)
		t.eq(BadgeData.IsLive(0 / 0), false)
		t.eq(BadgeData.IsLive(math.huge), false)
		t.eq(BadgeData.IsLive(1), true)
	end)

	t.test("the list is the three firsts, eight places, and the rare woods", function()
		t.eq(keys(), {
			"FirstSale",
			"FirstTruck",
			"FirstPlank",
			"AreaStarter",
			"AreaHills",
			"AreaSnow",
			"AreaVolcano",
			"AreaGrove",
			"AreaSky",
			"AreaFerry",
			"AreaCave",
			"WoodFrostwood",
			"WoodEmberwood",
			"WoodGloamwood",
			"WoodLumenwood",
			"WoodNightGlow",
		})
		t.eq(BadgeData.Get("WoodGloamwood").woodId, "phantomwood")
		t.eq(GameConfig.NightGlowWoodId, "lumenwood")
		t.eq(BadgeData.Get("WoodNightGlow").woodId, GameConfig.NightGlowWoodId)
		t.eq(BadgeData.ForWood("lumenwood"), { "WoodLumenwood", "WoodNightGlow" })
		t.eq(BadgeData.ForWood("oak"), {})
	end)

	t.test("rows show locked and earned, and the wire form drops unknown keys", function()
		local locked = BadgeData.Rows({})
		t.eq(locked[1].status, "Locked")
		t.eq(locked[1].unlocked, false)
		t.eq(#locked, #keys())
		local earned = BadgeData.Rows({ FirstSale = true, NotABadge = true, AreaSnow = false })
		t.eq(earned[1].status, "Earned")
		t.eq(earned[1].unlocked, true)
		t.eq(BadgeData.Count({ FirstSale = true }), 1, #keys())
		t.eq(BadgeData.Encode({ FirstSale = true, AreaSnow = true, Bogus = true }), "AreaSnow,FirstSale")
		t.eq(BadgeData.Decode("AreaSnow,FirstSale,Bogus"), { AreaSnow = true, FirstSale = true })
		t.eq(BadgeData.Decode(nil), {})
	end)

	t.test("marks, events, and places map onto badge keys", function()
		t.eq(BadgeData.ForMark("First sale"), "FirstSale")
		t.eq(BadgeData.ForMark("Bought a truck"), "FirstTruck")
		t.eq(BadgeData.ForMark("Joined"), nil)
		t.eq(BadgeData.KeysFor("mark", { name = "First sale" }), { "FirstSale" })
		t.eq(BadgeData.KeysFor("plank", nil), { "FirstPlank" })
		t.eq(BadgeData.KeysFor("truck", nil), { "FirstTruck" })
		t.eq(BadgeData.KeysFor("wood", { woodId = "frostwood" }), { "WoodFrostwood" })
		t.eq(BadgeData.KeysFor("area", { id = "snow" }), { "AreaSnow" })
		t.eq(BadgeData.KeysFor("area", { id = "AreaCave" }), { "AreaCave" })
		t.eq(BadgeData.KeysFor("nope", nil), {})
		t.eq(BadgeData.AreasAt(0, 30, 1240), { "AreaSnow" })
		t.eq(BadgeData.AreasAt(0, 20, -110), { "AreaStarter" })
		t.eq(BadgeData.AreasAt(-420, 20, 110), { "AreaHills" })
		t.eq(BadgeData.AreasAt(-565, 20, -455), { "AreaGrove" })
		t.eq(BadgeData.AreasAt(-1050, 700, 1050), { "AreaSky" })
		t.eq(BadgeData.AreasAt(-1050, 0, 1050), {})
		t.eq(BadgeData.AreasAt(1395, 12, -760), { "AreaFerry" })
		local cave = BadgeData.AreasAt(1010, 40, 1110)
		t.eq(cave, { "AreaVolcano", "AreaCave" })
		t.eq(BadgeData.AreasAt(9000, 0, 9000), {})
	end)

	t.test("the open bind is a 44 px menu key, not world interact", function()
		t.eq(BadgeData.MinTapPx, 44)
		t.ok(InputKit.TouchOk(BadgeData.MinTapPx))
		t.ok(InputKit.PlacerSafe({
			{
				action = "Badges",
				keyboard = BadgeData.OpenKeyboard,
				gamepad = BadgeData.OpenGamepad,
			},
		}, true))
		t.ok(InputKit.KeysUnique({
			{ action = "Badges", keyboard = BadgeData.OpenKeyboard, gamepad = BadgeData.OpenGamepad },
			{ action = "CloseBadges", keyboard = BadgeData.CloseKeyboard, gamepad = Enum.KeyCode.ButtonB },
		}))
		t.eq(BadgeData.OpenKeyboard, Enum.KeyCode.B)
		t.eq(BadgeData.OpenGamepad, Enum.KeyCode.ButtonL3)
		t.eq(BadgeData.CloseKeyboard, Enum.KeyCode.Escape)
	end)
end
