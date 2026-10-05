--!nocheck
-- EventData (B14, the Halloween event): the date gate with the Studio
-- override, the two themed goals, the cosmetic (no cash anywhere), and
-- EventArt's builders (cheap, decoration only, deterministic).
return function(t)
	local EventData = t.shared("EventData")
	local EventArt = t.load("ReplicatedStorage/Shared/Art/EventArt")
	local DAY = 86400

	-- The unix time of 12:00 UTC on a civil date (days from 1970-01-01).
	local function at(year, month, day)
		local y = if month <= 2 then year - 1 else year
		local era = math.floor(y / 400)
		local yoe = y - era * 400
		local mp = if month > 2 then month - 3 else month + 9
		local doy = math.floor((153 * mp + 2) / 5) + day - 1
		local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
		return (era * 146097 + doe - 719468) * DAY + DAY / 2
	end

	t.test("the date maths reads UTC civil dates", function()
		t.eq({ EventData.Date(0) }, { 1970, 1, 1 })
		t.eq({ EventData.Date(at(2026, 10, 5)) }, { 2026, 10, 5 })
		t.eq({ EventData.Date(at(2024, 2, 29)) }, { 2024, 2, 29 })
		t.eq({ EventData.Date(at(2026, 12, 31)) }, { 2026, 12, 31 })
	end)

	t.test("Halloween runs 1 October up to 1 November, and the override beats the date", function()
		t.eq(EventData.Active(at(2026, 9, 30)), nil)
		t.eq(EventData.Active(at(2026, 10, 1)), "halloween")
		t.eq(EventData.Active(at(2026, 10, 31) + DAY / 2 - 1), "halloween", "all of the 31st")
		t.eq(EventData.Active(at(2026, 11, 1)), nil)
		t.eq(EventData.Active(at(2027, 6, 1)), nil)
		t.eq(EventData.Active(at(2027, 6, 1), "halloween"), "halloween", "Studio override on")
		t.eq(EventData.Active(at(2026, 10, 5), "off"), nil, "Studio override off")
		t.eq(EventData.Active(at(2026, 10, 5), 42), "halloween", "an unknown override falls back to the date")
		t.eq(EventData.Active(at(2026, 5, 5), "nonsense"), nil, "an unknown override falls back to the date")
	end)

	t.test("themed goals count their own moments and finish the day once", function()
		local state = EventData.Fresh("halloween", 100)
		local finished, newDay = EventData.Apply(state, "treeFelled", 3)
		t.eq(#finished, 0)
		t.eq(state.progress, { 3, 0 })
		finished, newDay = EventData.Apply(state, "treeFelled", 99)
		t.eq(finished, { 1 })
		t.eq(state.progress[1], EventData.Goals[1].target, "never past the target")
		t.ok(not newDay, "one goal is not the day")
		EventData.Apply(state, "piecesSold", -5)
		EventData.Apply(state, "piecesSold", 0 / 0)
		t.eq(state.progress[2], 0, "junk amounts count nothing")
		finished, newDay = EventData.Apply(state, "piecesSold", 100)
		t.eq(finished, { 2 })
		t.ok(newDay, "both done: the day counts")
		t.eq(state.daysDone, 1)
		_, newDay = EventData.Apply(state, "treeFelled", 5)
		t.ok(not newDay and state.daysDone == 1, "a day is counted once")
	end)

	t.test("a new day clears progress and keeps the days done; the cosmetic needs three", function()
		local state = EventData.Roll(nil, "halloween", 10)
		for day = 10, 12 do
			state = EventData.Roll(state, "halloween", day)
			t.eq(state.progress, { 0, 0 }, "fresh each day")
			EventData.Apply(state, "treeFelled", 50)
			EventData.Apply(state, "piecesSold", 50)
			t.eq(EventData.Earned(state), day == 12, "earned on the third day")
		end
		t.eq(state.daysDone, 3)
		local other = EventData.Roll(state, "somethingElse", 13)
		t.eq(other.daysDone, 0, "another event starts over")
		t.eq(
			EventData.Roll({ id = "halloween", progress = "bad" }, "halloween", 5).daysDone,
			0,
			"a damaged state resets"
		)
	end)

	t.test("nothing in an event pays cash", function()
		for key in pairs(EventData.Halloween) do
			t.ok(not string.find(string.lower(key), "cash") and not string.find(string.lower(key), "robux"), key)
		end
		for _, goal in ipairs(EventData.Goals) do
			t.eq(goal.reward, nil, "a themed goal has no reward field")
		end
	end)

	t.test("the attributes round trip", function()
		local state = EventData.Fresh("halloween", 1)
		state.progress[1] = 2
		local rows = EventData.DecodeGoals(EventData.EncodeGoals(state))
		t.eq(#rows, #EventData.Goals)
		t.eq(rows[1].progress, 2)
		t.eq(rows[1].text, EventData.Goals[1].text)
		for _, goal in ipairs(EventData.Goals) do
			t.ok(not string.find(goal.text, "[|;]"), "text is safe for the attribute")
		end
		local info = EventData.EncodeInfo(EventData.Halloween, state, true)
		t.eq(info, "Halloween|0|3|Pumpkin Hat|1")
	end)

	t.test("the Halloween art builds small, decoration only, and the same every time", function()
		local function count(model)
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
					t.ok(not d.CanCollide and not d.CanQuery and not d.CanTouch, d.Name .. " is decoration")
				end
			end
			return n
		end
		for seed = 1, 5 do
			t.ok(count(EventArt.Pumpkin(seed)) <= 10, "pumpkin budget")
			t.ok(count(EventArt.PumpkinPatch(seed)) <= 20, "patch budget")
		end
		t.eq(count(EventArt.PumpkinPatch(3)), count(EventArt.PumpkinPatch(3)))
		local hat = EventArt.Hat()
		t.ok(count(hat) <= 10, "hat budget")
		t.ok(hat.PrimaryPart ~= nil and hat.PrimaryPart.Name == "HatBase", "the hat welds at HatBase")
	end)
end
