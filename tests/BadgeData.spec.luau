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

	t.test("the list is the three firsts, the places, and the rare woods", function()
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
			"AreaToll",
			"WoodFrostwood",
			"WoodEmberwood",
			"WoodGloamwood",
			"WoodLumenwood",
			"WoodLanternwood",
		})
		t.eq(BadgeData.Get("WoodGloamwood").woodId, "phantomwood")
		-- Lanternwood is its own wood. The glow placeholder stays lumenwood.
		t.eq(GameConfig.NightGlowWoodId, "lumenwood")
		t.eq(BadgeData.Get("WoodLanternwood").name, "Lanternwood")
		t.eq(BadgeData.Get("WoodLanternwood").woodId, "lanternwood")
		t.eq(BadgeData.ForWood("lumenwood"), { "WoodLumenwood" })
		t.eq(BadgeData.ForWood("lanternwood"), { "WoodLanternwood" })
		t.eq(BadgeData.ForWood("oak"), {})
		t.eq(BadgeData.Get("AreaHills").name, "The Hills")
		t.eq(BadgeData.Get("AreaVolcano").name, "The Volcano")
		t.eq(BadgeData.Get("AreaToll").name, "North Strip")
		t.eq(BadgeData.Get("AreaToll").detail, "Cross Old Tolly's bridge into the North Strip.")
		t.eq(BadgeData.NotBuilt, { "AreaFerry" })
		t.eq(BadgeData.Ids.AreaCave, 0, "the cave badge id waits for a PASTE")
		for _, key in ipairs(BadgeData.NotBuilt) do
			t.eq(BadgeData.Ids[key], 0, key)
			t.eq(BadgeData.IsLive(BadgeData.RobloxId(key)), false, key)
		end
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
		t.eq(BadgeData.KeysFor("area", { id = "toll" }), { "AreaToll" })
		t.eq(BadgeData.KeysFor("nope", nil), {})
		t.eq(BadgeData.AreasAt(0, 30, 1240), { "AreaSnow" })
		t.eq(BadgeData.AreasAt(0, 20, -110), { "AreaStarter" })
		t.eq(BadgeData.AreasAt(-420, 20, 110), { "AreaHills" })
		t.eq(BadgeData.AreasAt(-565, 20, -455), { "AreaGrove" })
		t.eq(BadgeData.AreasAt(-1050, 700, 1050), { "AreaSky" })
		t.eq(BadgeData.AreasAt(-1050, 0, 1050), {})
		-- The cave on the Volcano is Cinder Cave, not the Secret Cave.
		t.eq(BadgeData.AreasAt(1010, 40, 1110), { "AreaVolcano" })
		-- The Secret Cave room is built, so standing in it records the visit.
		t.eq(BadgeData.AreasAt(-765, 20, -655), { "AreaCave" })
		-- Ferry Island earns nothing while it is unbuilt.
		t.eq(BadgeData.AreasAt(1395, 12, -760), {})
		t.eq(BadgeData.AreasAt(9000, 0, 9000), {})
		-- The North Strip trigger is the box north of the bridge, not the deck.
		t.eq(BadgeData.AreasAt(0, 40, 1700), { "AreaToll" })
		t.eq(BadgeData.AreasAt(0, 40, 1590), {})
		t.eq(BadgeData.AreasAt(22, 20, 1566), {})
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
