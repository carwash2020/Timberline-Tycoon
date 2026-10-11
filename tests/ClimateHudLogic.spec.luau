--!nocheck
return function(t)
	local C = t.shared("ClimateHudLogic")

	t.test("no vignette when safe or unknown", function()
		t.eq(C.Alpha("", 1), 0)
		t.eq(C.Alpha(nil, 1), 0)
		t.eq(C.Alpha("lava", 1), 0)
		t.eq(C.Color(""), nil)
	end)

	t.test("it grows with exposure, never past the max", function()
		t.ok(C.Alpha("cold", 0) > 0, "shows at once")
		t.ok(C.Alpha("cold", 0.5) > C.Alpha("cold", 0.1))
		t.eq(C.Alpha("cold", 1), C.MaxAlpha)
		t.eq(C.Alpha("heat", 9), C.MaxAlpha)
		t.eq(C.Alpha("heat", 0 / 0), C.Alpha("heat", 0))
		t.ok(C.Color("cold")[3] > C.Color("cold")[1], "frost is blue")
		t.ok(C.Color("heat")[1] > C.Color("heat")[3], "heat is orange")
	end)

	t.test("the tip shows the first time only, per kind", function()
		local seen = {}
		local tip = C.Tip("cold", seen)
		t.ok(tip and string.find(tip.text, "campfire", 1, true) and string.find(tip.text, "Coat", 1, true))
		seen[tip.key] = true
		t.eq(C.Tip("cold", seen), nil)
		t.ok(C.Tip("heat", seen) ~= nil, "heat has its own")
		t.eq(C.Tip("", seen), nil)
		t.ok(#tip.text <= 60, "one short line")
	end)
end
