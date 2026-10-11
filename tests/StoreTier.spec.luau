--!nocheck
-- StoreTier: the one tier colour ramp for every store's stands. Each tier is
-- a distinct colour, its badge ink clears WCAG AA on it, the tiers come from
-- the catalogs (display only), and the locks follow the rules the shop and
-- the server already use.
return function(t)
	local StoreTier = t.shared("StoreTier")
	local StoreStock = t.shared("StoreStock")
	local ItemCatalog = t.shared("ItemCatalog")
	local StageOf = t.shared("StageOf")

	local function dist(a, b)
		local dr, dg, db = (a.R - b.R) * 255, (a.G - b.G) * 255, (a.B - b.B) * 255
		return math.sqrt(2 * dr * dr + 4 * dg * dg + 3 * db * db) -- the "redmean-ish" weighting
	end

	t.test("the ramp has nine tiers and every tier is its own colour", function()
		t.eq(StoreTier.Count, 9)
		t.eq(#StoreTier.Ramp, 9)
		for i = 1, StoreTier.Count do
			for j = i + 1, StoreTier.Count do
				t.ok(
					dist(StoreTier.Color(i), StoreTier.Color(j)) >= 100,
					string.format("T%d and T%d are too alike", i, j)
				)
				t.ok(StoreTier.Name(i) ~= StoreTier.Name(j), "tier names differ")
			end
			-- none is the locked stand's grey
			t.ok(dist(StoreTier.Color(i), StoreTier.LockedColor) >= 90, "T" .. i .. " is not the locked grey")
		end
	end)

	t.test("every tier's badge text passes WCAG AA (4.5:1) on its colour", function()
		for i = 1, StoreTier.Count do
			local ratio = StoreTier.Contrast(StoreTier.Color(i), StoreTier.Ink(i))
			t.ok(ratio >= 4.5, string.format("T%d badge contrast is only %.2f", i, ratio))
		end
		t.ok(StoreTier.Contrast(StoreTier.LockedColor, StoreTier.LockedInk) >= 4.5, "the locked chip reads")
		t.ok(StoreTier.Contrast(StoreTier.Cream, StoreTier.Dark) > 12)
		t.eq(StoreTier.Contrast(StoreTier.Dark, StoreTier.Dark), 1)
	end)

	t.test("labels and clamping", function()
		t.eq(StoreTier.Label(1), "T1")
		t.eq(StoreTier.Label(7), "T7")
		t.eq(StoreTier.Label(0), "T1")
		t.eq(StoreTier.Label(40), "T9")
		t.eq(StoreTier.Color(0), StoreTier.Color(1))
	end)

	t.test("tiers come from the catalogs, and untiered goods have none", function()
		for i, axe in ipairs(ItemCatalog.AxeLadder()) do
			t.eq(StoreTier.Of("Axe", axe.id), i, axe.id)
		end
		for _, mill in ipairs(ItemCatalog.SawmillList()) do
			t.eq(StoreTier.Of("Sawmill", mill.id), mill.tier, mill.id)
		end
		t.eq(StoreTier.Of("Machine", "PlanerHand"), 1)
		t.eq(StoreTier.Of("Machine", "PlanerIndustrial"), 4)
		t.eq(StoreTier.Of("Machine", "ChopSaw"), nil)
		t.eq(StoreTier.Of("Machine", "ConveyorStraight"), nil)
		t.eq(StoreTier.Of("Logic", "GateAnd"), nil)
		t.eq(StoreTier.Of("Cosmetic", "LampPost"), nil)
		t.eq(StoreTier.Of("Gear", "HeatBoots"), 4)
		t.eq(StoreTier.Of("Gear", "Flashlight"), nil)
		t.eq(StoreTier.Of("Blueprint", "Wall"), nil, "a tier-1 plan has no badge")
		-- vehicles: the price order within the kind, 1 up, no gaps
		local seen = {}
		for _, v in ipairs(t.shared("ItemBox").Showroom) do
			local tier = StoreTier.Of(v.kind, v.id)
			t.ok(tier ~= nil and tier >= 1, v.id .. " has a tier")
			seen[v.kind] = seen[v.kind] or {}
			t.eq(seen[v.kind][tier], nil, v.id .. " shares a tier")
			seen[v.kind][tier] = true
		end
		for kind, tiers in pairs(seen) do
			local n = 0
			for _ in pairs(tiers) do
				n += 1
			end
			for i = 1, n do
				t.ok(tiers[i], kind .. " tiers have no gap at " .. i)
			end
		end
		t.ok(StoreTier.Of("Truck", "Rustbucket") < StoreTier.Of("Truck", "LoggingRig"), "dearer trucks rank higher")
		-- every tier a shop item has is on the ramp
		for _, shop in ipairs({ "ToolShed", "HearthAndHome", "Sparkworks" }) do
			for _, slot in ipairs(StoreStock.ForShop(shop)) do
				local tier = StoreTier.Of(slot.itemKind, slot.itemId)
				if tier ~= nil then
					t.ok(tier >= 1 and tier <= StoreTier.Count, slot.slotId .. " tier " .. tier)
				end
			end
		end
	end)

	t.test("locks follow the shop's own rules: axes in order, gear by stage", function()
		-- Axes are sold in order (ItemCatalog.CanBuyAxe): rung n needs rung n-1 owned.
		for i, axe in ipairs(ItemCatalog.AxeLadder()) do
			if axe.sold ~= false then
				for best = 1, 9 do
					t.eq(
						StoreTier.IsLocked("Axe", axe.id, 1, best),
						not ItemCatalog.CanBuyAxe(axe.id, best),
						axe.id .. " at best " .. best
					)
				end
			end
			local lock = StoreTier.LockOf("Axe", axe.id)
			if i == 1 then
				t.eq(lock, nil, "the starter axe has no lock line")
			else
				t.ok(lock and lock.rung == i and string.find(lock.text, "NEEDS"), axe.id .. " names the axe it needs")
			end
		end
		t.eq(StoreTier.LockOf("Axe", "SteelAxe").text, "NEEDS RUSTY")
		-- Gear that is for a later stage.
		for id, stage in pairs(StageOf.GearStage) do
			t.eq(StoreTier.IsLocked("Gear", id, stage - 1, 1), true, id .. " is locked a stage early")
			t.eq(StoreTier.IsLocked("Gear", id, stage, 1), false, id .. " opens at its stage")
			local lock = StoreTier.LockOf("Gear", id)
			t.eq(lock.stage, stage)
			t.ok(string.find(lock.text, "S" .. stage), "the chip names the stage")
		end
		t.eq(StoreTier.IsLocked("Gear", "Flashlight", 1, 1), false)
		t.eq(StoreTier.IsLocked("Sawmill", "SawmillSturdy", 1, 1), false, "nothing else locks")
		t.eq(StoreTier.LockOf("Sawmill", "SawmillSturdy"), nil)
	end)
end
