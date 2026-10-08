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
		t.eq(BadgeData.NotBuilt, {})
		-- Built triggers keep id 0 until the owner pastes the Creator Hub id.
		t.eq(BadgeData.Ids.AreaFerry, 0)
		t.eq(BadgeData.Ids.AreaToll, 0)
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
		local BiomeData = t.shared("BiomeData")
		local WorldLayout = t.shared("World/WorldLayout")
		local RegionLogic = t.shared("RegionLogic")
		local function disc(id, y)
			local area = BiomeData.Get(id).area
			return BadgeData.AreasAt(area.x, y or 30, area.z)
		end
		t.eq(disc("snow"), { "AreaSnow" })
		t.eq(disc("starter"), { "AreaStarter" })
		t.eq(disc("hills"), { "AreaHills" })
		t.eq(disc("grove"), { "AreaGrove" })
		t.eq(disc("sky", 700), { "AreaSky" })
		t.eq(disc("sky", 0), {})
		t.eq(disc("volcano"), { "AreaVolcano" })
		local rx, rz = RegionLogic.ReachCenter()
		t.eq(BadgeData.AreasAt(rx, 20, rz), { "AreaCave" })
		local island = WorldLayout.Island
		t.eq(BadgeData.AreasAt(island.x, 12, island.z), { "AreaFerry" })
		t.eq(BadgeData.AreasAt(island.x + island.radius + 20, 12, island.z), {}, "past the island's edge")
		t.eq(BadgeData.AreasAt(9000, 0, 9000), {})
		-- The North Strip trigger is the box north of the bridge, not the deck.
		t.eq(BadgeData.AreasAt(0, 40, 960), { "AreaToll" })
		t.eq(BadgeData.AreasAt(0, 40, WorldLayout.BridgeCenterZ), {})
		t.eq(BadgeData.AreasAt(WorldLayout.BoothX, 20, WorldLayout.BoothZ), {})
	end)

	t.test("the open bind is a 44 px menu key, not world interact", function()
		t.eq(BadgeData.MinTapPx, 44)
		t.ok(InputKit.TouchOk(BadgeData.MinTapPx))
		t.ok(InputKit.PlacerSafe({
			{ action = "Badges", keyboard = BadgeData.OpenKeyboard },
		}, true))
		t.ok(InputKit.KeysUnique({
			{ action = "Badges", keyboard = BadgeData.OpenKeyboard },
			{ action = "CloseBadges", keyboard = BadgeData.CloseKeyboard, gamepad = Enum.KeyCode.ButtonB },
		}))
		t.eq(BadgeData.OpenKeyboard, Enum.KeyCode.B)
		t.eq(BadgeData.CloseKeyboard, Enum.KeyCode.Escape)
	end)

	t.test("a gamepad opens Badges from the quick menu, which owns the View button", function()
		t.eq(BadgeData.OpenGamepad, nil, "no bind of its own: the View button is the quick menu's")
		local QuickMenuLogic = t.shared("QuickMenuLogic")
		t.eq(QuickMenuLogic.OpenGamepad, Enum.KeyCode.ButtonSelect)
		local rank
		for i, id in ipairs(QuickMenuLogic.Order) do
			if id == "badges" then
				rank = i
			end
		end
		t.ok(rank, "Badges is a tile in the quick menu's order")
	end)
end
