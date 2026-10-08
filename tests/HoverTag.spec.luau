--!nocheck
-- HoverTag: the pure rules behind the price tag that appears when you aim at an
-- item (choosing the target per device, the tag's text per state, one tag at a
-- time, the cooldown after a dismissal, the ray test the client aims with).
return function(t)
	local HoverTag = t.shared("HoverTag")
	local StoreStock = t.shared("StoreStock")
	local ItemCatalog = t.shared("ItemCatalog")
	local ShopLogic = t.shared("ShopLogic")
	local Util = t.shared("Util")
	local Instance, Vector3, CFrame = t.roblox.Instance, t.roblox.Vector3, t.roblox.CFrame

	local OPEN = 12 -- noon: every shop is open
	local NIGHT = 23 -- every shop is shut

	local axe = { key = "Rack:SteelAxe", name = "Steel Axe", kind = "Axe", itemId = "SteelAxe", shop = "ToolShed" }

	t.test("the devices", function()
		t.eq(HoverTag.DeviceOf("phone"), "touch")
		t.eq(HoverTag.DeviceOf("console"), "gamepad")
		t.eq(HoverTag.DeviceOf("desktop"), "mouse")
		t.eq(HoverTag.DeviceOf("touch"), "touch")
		t.eq(HoverTag.DeviceOf("pad"), "gamepad")
		t.eq(HoverTag.DeviceOf("gamepad"), "gamepad")
		t.eq(HoverTag.DeviceOf("mouse"), "mouse")
		t.eq(HoverTag.DeviceOf(nil), "mouse")
	end)

	t.test("mouse: the item under the cursor, within range", function()
		local hit = { key = "a", distance = 30 }
		t.eq(HoverTag.Choose({ device = "mouse", now = 0, hit = hit }), "a")
		t.eq(HoverTag.Choose({ device = "mouse", now = 0, hit = nil }), nil, "the cursor is on nothing (or a wall)")
		t.eq(
			HoverTag.Choose({ device = "mouse", now = 0, hit = { key = "a", distance = HoverTag.MouseRange + 1 } }),
			nil
		)
		-- Touch state does not leak into a mouse.
		t.eq(HoverTag.Choose({ device = "mouse", now = 0, tapped = { key = "b", at = 0 } }), nil)
	end)

	t.test("gamepad: the item under the centre aim, within about 12 studs", function()
		t.eq(HoverTag.GamepadRange, 12)
		t.eq(HoverTag.Choose({ device = "gamepad", now = 0, hit = { key = "a", distance = 12 } }), "a")
		t.eq(HoverTag.Choose({ device = "gamepad", now = 0, hit = { key = "a", distance = 12.5 } }), nil)
		t.eq(HoverTag.Choose({ device = "gamepad", now = 0, hit = nil }), nil)
	end)

	t.test("touch: the last tapped item for a few seconds, else the nearest in front within 6 studs", function()
		t.eq(HoverTag.TouchRange, 6)
		local near = {
			{ key = "far", distance = 7, front = 1 },
			{ key = "behind", distance = 2, front = -0.5 },
			{ key = "side", distance = 3, front = 0.1 },
			{ key = "ahead", distance = 5, front = 0.9 },
			{ key = "ahead2", distance = 4, front = 0.8 },
		}
		t.eq(
			HoverTag.Choose({ device = "touch", now = 1, near = near }),
			"ahead2",
			"nearest of those in front, in range"
		)
		t.eq(HoverTag.Choose({ device = "touch", now = 1, near = { near[1], near[2], near[3] } }), nil)
		-- A tap wins while it is fresh, and lapses after TouchSeconds.
		local tapped = { key = "tapped", at = 10 }
		t.eq(HoverTag.Choose({ device = "touch", now = 11, tapped = tapped, near = near }), "tapped")
		t.eq(HoverTag.Choose({ device = "touch", now = 10 + HoverTag.TouchSeconds - 0.1, tapped = tapped }), "tapped")
		t.eq(
			HoverTag.Choose({ device = "touch", now = 10 + HoverTag.TouchSeconds, tapped = tapped, near = near }),
			"ahead2"
		)
		t.eq(HoverTag.Choose({ device = "touch", now = 20, tapped = tapped }), nil)
		t.ok(HoverTag.TouchSeconds >= 3 and HoverTag.TouchSeconds <= 6, "a few seconds")
	end)

	t.test("the tag's text: name and the item's real price", function()
		local facts = { hour = OPEN, loop = 2 }
		local name, line = HoverTag.Lines(axe, facts)
		t.eq(name, "Steel Axe")
		t.eq(line, Util.formatCash(ShopLogic.Price(ItemCatalog.GetAxe("SteelAxe"), 2)))
		-- Every shelf item's tag line is what StoreStock (the counter's price) says, in both loops.
		for _, slot in ipairs(StoreStock.All()) do
			for _, loop in ipairs({ 1, 2 }) do
				local spec = {
					key = slot.slotId,
					name = slot.displayName,
					kind = slot.itemKind,
					itemId = slot.itemId,
					shop = slot.shop,
					limited = slot.limited,
				}
				local expected = StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, loop)
				local _, shown = HoverTag.Lines(spec, { hour = OPEN, loop = loop })
				if expected == nil then
					t.eq(shown, "", slot.slotId)
				else
					t.eq(shown, if expected > 0 then Util.formatCash(expected) else "FREE", slot.slotId)
				end
			end
		end
		-- Vehicles use their v2 price like the server.
		local truck = { key = "v", name = "Pickup", kind = "Truck", itemId = "Pickup", shop = "Dealership" }
		local _, tprice = HoverTag.Lines(truck, facts)
		t.eq(tprice, Util.formatCash(ShopLogic.Price(ItemCatalog.GetTruck("Pickup"), 2)))
	end)

	t.test("a Robux item shows its R$ price, never a cash one", function()
		local spec =
			{ key = "g", name = "2x Cash", kind = "Robux", itemId = "DoubleCash", shop = "ToolShed", robux = "R$ 199" }
		local name, line = HoverTag.Lines(spec, { hour = OPEN, loop = 2 })
		t.eq({ name, line }, { "2x Cash", "R$ 199" })
		t.eq(
			HoverTag.Lines(
				{ key = "g", name = "x", kind = "Robux", itemId = "y", robux = "R$" },
				{ hour = OPEN, loop = 2 }
			),
			"x"
		)
	end)

	t.test("states: Closed, You already own this, Out of stock", function()
		local base = { loop = 2 }
		local function lines(spec, extra)
			local facts = { hour = OPEN, loop = 2, owned = extra.owned, inStock = extra.inStock }
			if extra.hour then
				facts.hour = extra.hour
			end
			local n, l = HoverTag.Lines(spec, facts)
			return { n, l }
		end
		t.ok(base ~= nil)
		t.eq(lines(axe, { owned = true }), { "Steel Axe", "You already own this" })
		t.eq(lines(axe, { inStock = false }), { "Steel Axe", "Out of stock" })
		local closed = lines(axe, { hour = NIGHT })
		t.eq(closed[1], "Steel Axe")
		t.ok(string.find(closed[2], "Closed", 1, true) ~= nil, closed[2])
		-- Closed beats the rest (you can't buy either way), owned beats out of stock.
		t.eq(lines(axe, { hour = NIGHT, owned = true, inStock = false })[2], closed[2])
		t.eq(lines(axe, { owned = true, inStock = false })[2], "You already own this")
		-- Unknown stock counts as in stock; a spec with no shop is never closed.
		t.eq(HoverTag.StateOf(axe, { hour = OPEN, loop = 2 }), "price")
		t.eq(
			HoverTag.StateOf({ key = "k", name = "n", kind = "Axe", itemId = "SteelAxe" }, { hour = NIGHT, loop = 2 }),
			"price"
		)
		-- The dealership has its own hours.
		local truck = { key = "v", name = "Pickup", kind = "Truck", itemId = "Pickup", shop = "Dealership" }
		t.eq(HoverTag.StateOf(truck, { hour = 3, loop = 2 }), "closed")
	end)

	t.test("Mark and SpecOf round-trip through attributes", function()
		local part = Instance.new("Part")
		HoverTag.Mark(part, {
			key = "Box:1",
			name = "Lantern",
			kind = "Gear",
			itemId = "Lantern",
			shop = "HearthAndHome",
			limited = true,
			robux = nil,
			anchor = true,
		})
		local spec = HoverTag.SpecOf(part)
		t.eq(spec.key, "Box:1")
		t.eq(spec.name, "Lantern")
		t.eq(spec.kind, "Gear")
		t.eq(spec.itemId, "Lantern")
		t.eq(spec.shop, "HearthAndHome")
		t.eq(spec.limited, true)
		t.eq(spec.anchor, true)
		t.eq(HoverTag.SpecOf(Instance.new("Part")), nil, "an unmarked thing has no tag")
	end)

	t.test("one tag at a time: a new target waits its turn, a lost one lingers", function()
		local mem = HoverTag.New()
		t.eq(HoverTag.Step(mem, 0, "a"), "a", "the first shows at once")
		t.eq(HoverTag.Step(mem, 0.05, "b"), "a", "b has not held long enough; still only a")
		t.eq(HoverTag.Step(mem, 0.05 + HoverTag.SwitchDelay, "b"), "b", "then it takes over: never both")
		-- The aim leaves: the tag lingers, then goes.
		t.eq(HoverTag.Step(mem, 1, nil), "b")
		t.eq(HoverTag.Step(mem, 1 + HoverTag.HideDelay - 0.01, nil), "b")
		t.eq(HoverTag.Step(mem, 1 + HoverTag.HideDelay, nil), nil)
		-- A flicker across a gap does not change the tag.
		t.eq(HoverTag.Step(mem, 2, "a"), "a")
		t.eq(HoverTag.Step(mem, 2.1, nil), "a")
		t.eq(HoverTag.Step(mem, 2.2, "a"), "a")
		t.eq(HoverTag.Step(mem, 2.3, nil), "a", "the hide clock restarted")
		-- Over many frames of changing aims there is never more than one answer.
		local m2 = HoverTag.New()
		local keys = { "a", "b", "c", nil, "a", "c", "b" }
		for i = 1, 70 do
			local shown = HoverTag.Step(m2, i * 0.05, keys[(i % 7) + 1])
			t.ok(shown == nil or type(shown) == "string", "at most one key")
		end
	end)

	t.test("a dismissed tag stays away for the cooldown, then may come back", function()
		local mem = HoverTag.New()
		t.eq(HoverTag.Step(mem, 0, "a"), "a")
		HoverTag.Dismiss(mem, 1)
		t.eq(HoverTag.Step(mem, 1.1, "a"), nil, "still aimed at, but dismissed")
		t.eq(HoverTag.Step(mem, 1 + HoverTag.DismissCooldown - 0.1, "a"), nil)
		t.eq(HoverTag.Step(mem, 1 + HoverTag.DismissCooldown, "a"), "a", "back after the cooldown")
		-- Another item is not held back by it.
		HoverTag.Dismiss(mem, 5)
		t.eq(HoverTag.Step(mem, 5.1, "b"), "b")
		-- Dismissing with nothing shown does nothing.
		local empty = HoverTag.New()
		HoverTag.Dismiss(empty, 0)
		t.eq(HoverTag.Step(empty, 0.1, "a"), "a")
	end)

	t.test("the price line is gold when you can pay, red when you cannot", function()
		local Color3 = t.roblox.Color3
		local function hex(color)
			return string.format(
				"#%02X%02X%02X",
				math.floor(color.R * 255 + 0.5),
				math.floor(color.G * 255 + 0.5),
				math.floor(color.B * 255 + 0.5)
			)
		end
		t.eq(hex(HoverTag.CoinGold), "#F2C14E")
		t.eq(hex(HoverTag.StopRed), "#D9534F")
		local price = HoverTag.Price(axe, 2)
		t.eq(HoverTag.PriceTone("price", price, price, false), "gold")
		t.eq(HoverTag.PriceTone("price", price, price - 1, false), "red")
		t.eq(HoverTag.PriceTone("price", 0, 0, false), "gold", "FREE is affordable")
		t.eq(HoverTag.PriceTone("price", price, nil, false), "red", "no cash yet")
		t.eq(HoverTag.PriceTone("closed", price, 999999, false), "plain")
		t.eq(HoverTag.PriceTone("owned", price, 999999, false), "plain")
		t.eq(HoverTag.PriceTone("soldOut", price, 999999, false), "plain")
		t.eq(HoverTag.PriceTone("price", price, 999999, true), "plain", "a Robux line is not cash")
		t.eq(HoverTag.PriceTone("price", nil, 999999, false), "plain")
		t.eq(Color3.fromHex("#F2C14E"), HoverTag.CoinGold)
	end)

	t.test("RayBox: where a ray meets a box, nil past it, and a padded box is easier to hit", function()
		local cf = CFrame.new(0, 5, 10)
		local size = Vector3.new(2, 2, 2)
		local hit = HoverTag.RayBox(Vector3.new(0, 5, 0), Vector3.new(0, 0, 1), cf, size, 0)
		t.ok(hit ~= nil and math.abs(hit - 9) < 1e-6, "the near face is 9 studs along")
		t.eq(HoverTag.RayBox(Vector3.new(0, 5, 0), Vector3.new(0, 1, 0), cf, size, 0), nil, "straight up misses")
		t.eq(HoverTag.RayBox(Vector3.new(0, 5, 0), Vector3.new(0, 0, -1), cf, size, 0), nil, "behind the eye")
		t.eq(HoverTag.RayBox(Vector3.new(1.2, 5, 0), Vector3.new(0, 0, 1), cf, size, 0), nil, "just wide")
		t.ok(HoverTag.RayBox(Vector3.new(1.2, 5, 0), Vector3.new(0, 0, 1), cf, size, 0.5) ~= nil, "the pad catches it")
		-- From inside the box the distance is 0.
		t.eq(HoverTag.RayBox(Vector3.new(0, 5, 10), Vector3.new(0, 0, 1), cf, size, 0), 0)
	end)

	-- Final pass: the tag's placement ran on an Adornee the item's removal could have cleared.
	t.test("the tag placement tolerates an item destroyed since the last aim check", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HoverTagUI.luau")
		t.ok(string.find(source, "g.Adornee :: BasePart", 1, true) == nil, "no blind cast of a maybe-nil Adornee")
		t.ok(string.find(source, 'adornee:IsA("BasePart")', 1, true), "the Adornee is checked first")
	end)
end
