--!nocheck
-- BoxUnpack: how a box opens, who may take what comes out, and what a save
-- does with a box that is paid but not yet opened.
return function(t)
	local BoxUnpack = t.shared("BoxUnpack")

	t.test("small things come out as a pickup, plot items go to stock, vehicles go to a pad", function()
		for _, kind in ipairs({ "Axe", "Gear", "Cosmetic" }) do
			t.eq(BoxUnpack.Mode(kind), "pickup", kind)
		end
		for _, kind in ipairs({ "Sawmill", "Machine", "Blueprint" }) do
			t.eq(BoxUnpack.Mode(kind), "stock", kind)
		end
		t.eq(BoxUnpack.Mode("Truck"), "vehicle")
		t.eq(BoxUnpack.Mode("Trailer"), "vehicle")
		t.eq(BoxUnpack.Mode("Whatever"), "pickup")
	end)

	t.test("only the buyer, up close, once, may take the pickup", function()
		local function facts(over)
			local f = { userId = 7, buyerId = 7, distance = 3, taken = false }
			for k, v in pairs(over or {}) do
				f[k] = v
			end
			return f
		end
		t.eq(BoxUnpack.CanTake(facts()), true)
		local ok, why = BoxUnpack.CanTake(facts({ userId = 8 }))
		t.eq(ok, false)
		t.eq(why, "owner")
		ok, why = BoxUnpack.CanTake(facts({ distance = BoxUnpack.TakeRange + 0.01 }))
		t.eq(why, "far")
		t.eq(BoxUnpack.CanTake(facts({ distance = BoxUnpack.TakeRange })), true, "the edge counts")
		ok, why = BoxUnpack.CanTake(facts({ taken = true }))
		t.eq(why, "taken", "a second take is refused")
		t.eq(BoxUnpack.TakeMessage("taken"), nil)
		t.ok(BoxUnpack.TakeMessage("owner") ~= nil)
	end)

	t.test("an unclaimed pickup converts after its time; a stored box keeps what is owed", function()
		t.eq(BoxUnpack.Expired(100 + BoxUnpack.PickupSeconds - 1, 100), false)
		t.eq(BoxUnpack.Expired(100 + BoxUnpack.PickupSeconds, 100), true)
		local owed = BoxUnpack.StoredEntry("u1", "SteelAxe", "ToolShed", true)
		t.eq(owed.pending, true)
		local old = BoxUnpack.StoredEntry("u2", "SteelAxe", "ToolShed", false)
		t.eq(old.pending, nil, "a box with nothing owed has no mark, like a save from before")
		t.eq(BoxUnpack.Owed(true), true)
		t.eq(BoxUnpack.Owed(nil), false)
		t.eq(BoxUnpack.OneAtATime("Gear"), true)
		t.eq(BoxUnpack.OneAtATime("Axe"), false)
		t.ok(string.find(BoxUnpack.OpenedLine("pickup", "Steel Axe"), "Steel Axe", 1, true) ~= nil)
	end)
end
