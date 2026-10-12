--!nocheck
-- StoreEvents: the pure rules for scheduled store events. The clock is
-- injected (`now`), so every case below walks a fake clock: before the start,
-- during, after the end, disabled, bad dates, overlapping events, a toggle
-- off mid-event, a clock that jumps, and a "restart" (a fresh Loader that
-- recomputes from the same config and the same time).
return function(t)
	local StoreEvents = t.shared("StoreEvents")
	local StoreData = t.shared("StoreData")
	local DAY = 86400

	local function date(text)
		return StoreEvents.ParseDate(text)
	end

	-- A sample table of event slots (the committed ones are all unset on purpose).
	local function slot(id, store, index, approved, kind, itemId, price)
		return {
			id = id,
			store = store,
			index = index,
			eventSlot = true,
			visible = false,
			approved = approved,
			itemKind = kind,
			itemId = itemId,
			price = price,
		}
	end
	local SLOTS = {
		slot("event-hearth-1", "HearthAndHome", 1, true, "Cosmetic", "TestHat", 250), -- sellable
		slot("event-hearth-2", "HearthAndHome", 2, true, "Cosmetic", "TestScarf", nil), -- approved, no price
		slot("event-hearth-3", "HearthAndHome", 3, false, "Cosmetic", "TestCoat", 100), -- not approved
		slot("event-hearth-4", "HearthAndHome", 4, true, "Cosmetic", "TestFree", 0), -- price 0 is not a price
		slot("event-toolshed-1", "ToolShed", 1, true, "Cosmetic", "TestPin", 80), -- sellable, other store
	}

	local GONE = {} -- config({ field = GONE }) leaves that field out
	local function config(over)
		local c = {
			store = "HearthAndHome",
			startsAt = "2026-12-01",
			endsAt = "2026-12-15",
			enabled = true,
			items = { "event-hearth-1" },
		}
		for k, v in pairs(over or {}) do
			c[k] = if v == GONE then nil else v
		end
		return c
	end

	local START = date("2026-12-01")
	local END = date("2026-12-15")

	t.test("dates parse as UTC, in unix seconds or text, and bad ones are refused", function()
		t.eq(date("2026-10-05 01:00"), 20731 * DAY + 3600)
		t.eq(date("2026-10-05T01:00:00Z"), 20731 * DAY + 3600)
		t.eq(date("2026-10-05"), 20731 * DAY)
		t.eq(date(1700000000), 1700000000)
		t.eq(date("2028-02-29") - date("2028-02-28"), DAY, "a leap day")
		t.eq(date("2027-02-29"), nil, "no 29 February in 2027")
		t.eq(date("2026-13-01"), nil)
		t.eq(date("2026-06-31"), nil)
		t.eq(date("2026-12-01 24:00"), nil)
		t.eq(date("soon"), nil)
		t.eq(date(""), nil)
		t.eq(date(nil), nil)
		t.eq(date(true), nil)
		t.eq(date(-5), nil)
		t.eq(date(0 / 0), nil)
		t.eq(date(1e15), nil, "a typo far in the future")
	end)

	t.test("Sanitize keeps a good config and names why it refuses a bad one", function()
		local c = StoreEvents.Sanitize(config(), SLOTS)
		t.eq(c.store, "HearthAndHome")
		t.eq(c.startsAt, START)
		t.eq(c.endsAt, END)
		t.eq(c.enabled, true)
		t.eq(c.items, { "event-hearth-1" })
		t.eq(c.bannerText, "COMING SOON")
		local function why(over)
			local clean, reason = StoreEvents.Sanitize(config(over), SLOTS)
			t.eq(clean, nil)
			return reason
		end
		t.eq(why({ store = "Casino" }), "unknown store")
		t.eq(why({ store = GONE }), "unknown store")
		t.eq(why({ startsAt = "nope" }), "bad startsAt")
		t.eq(why({ endsAt = "2026-02-30" }), "bad endsAt")
		t.eq(why({ endsAt = "2026-12-01" }), "endsAt is not after startsAt")
		t.eq(why({ endsAt = "2026-11-30" }), "endsAt is not after startsAt")
		t.eq(why({ endsAt = "2027-01-31" }), "longer than 60 days")
		t.eq(StoreEvents.Sanitize("a string"), nil)
		t.eq(StoreEvents.Sanitize(nil), nil)
		local sixty = StoreEvents.Sanitize(config({ endsAt = "2026-12-31" }), SLOTS)
		t.eq(sixty.endsAt - sixty.startsAt, 30 * DAY)
		t.ok(
			StoreEvents.Sanitize(config({ startsAt = "2026-11-01", endsAt = "2026-12-31" }), SLOTS),
			"exactly 60 days is fine"
		)
		t.eq(StoreEvents.Sanitize(config({ enabled = "yes" }), SLOTS).enabled, false, "only true turns it on")
		t.eq(StoreEvents.Sanitize(config({ enabled = GONE }), SLOTS).enabled, false, "missing means off")
	end)

	t.test("an item is kept only if its slot is real, in that store, approved, with an explicit price", function()
		local c = StoreEvents.Sanitize(
			config({
				items = {
					"event-hearth-1",
					"event-hearth-1", -- twice
					"event-hearth-2", -- no price
					"event-hearth-3", -- not approved
					"event-hearth-4", -- price 0
					"event-toolshed-1", -- another store's slot
					"event-nope", -- not a slot
					42,
				},
			}),
			SLOTS
		)
		t.eq(c.items, { "event-hearth-1" })
		t.eq(#c.dropped, 7)
		t.eq(StoreEvents.SlotSellable(SLOTS[1]), true)
		t.eq(StoreEvents.SlotSellable(SLOTS[2]), false)
		t.eq(StoreEvents.SlotSellable(SLOTS[3]), false)
		t.eq(StoreEvents.SlotSellable(SLOTS[4]), false)
		t.eq(StoreEvents.SlotSellable(nil), false)
		t.eq(
			StoreEvents.SlotSellable(slot("x", "ToolShed", 1, true, "Cosmetic", "A", 12.5)),
			false,
			"whole dollars only"
		)
		t.eq(StoreEvents.SlotSellable(slot("x", "ToolShed", 1, true, "", "A", 12)), false, "no item kind")
		t.eq(StoreEvents.SlotSellable(slot("x", "ToolShed", 1, true, "Cosmetic", nil, 12)), false, "no item id")
	end)

	t.test("the banner text is tidied, capped, and defaults to COMING SOON", function()
		t.eq(StoreEvents.Sanitize(config({ bannerText = "  winter fair " }), SLOTS).bannerText, "WINTER FAIR")
		t.eq(StoreEvents.Sanitize(config({ bannerText = "" }), SLOTS).bannerText, "COMING SOON")
		t.eq(StoreEvents.Sanitize(config({ bannerText = string.rep("A", 25) }), SLOTS).bannerText, "COMING SOON")
		t.eq(StoreEvents.Sanitize(config({ bannerText = 5 }), SLOTS).bannerText, "COMING SOON")
	end)

	t.test("it is active from the start up to, not including, the end", function()
		local c = config()
		t.eq(StoreEvents.IsActive(c, START - 1, SLOTS), false, "before")
		t.eq(StoreEvents.IsActive(c, START, SLOTS), true, "the first second")
		t.eq(StoreEvents.IsActive(c, START + 7 * DAY, SLOTS), true, "during")
		t.eq(StoreEvents.IsActive(c, END - 1, SLOTS), true, "the last second")
		t.eq(StoreEvents.IsActive(c, END, SLOTS), false, "over")
		t.eq(StoreEvents.IsActive(c, END + 400 * DAY, SLOTS), false, "long after")
		t.eq(StoreEvents.IsActive(c, nil, SLOTS), false, "no clock")
		t.eq(StoreEvents.IsActive(c, 0 / 0, SLOTS), false, "a broken clock")
		t.eq(StoreEvents.IsActive(c, "later", SLOTS), false)
	end)

	t.test("a disabled, missing or broken config is never active", function()
		local during = START + DAY
		t.eq(StoreEvents.IsActive(config({ enabled = false }), during, SLOTS), false)
		t.eq(StoreEvents.IsActive(config({ enabled = GONE }), during, SLOTS), false)
		t.eq(StoreEvents.IsActive(config({ startsAt = "garbage" }), during, SLOTS), false)
		t.eq(StoreEvents.IsActive(config({ endsAt = "2026-12-01" }), during, SLOTS), false)
		t.eq(StoreEvents.IsActive(config({ endsAt = "2030-01-01" }), during, SLOTS), false, "over 60 days")
		t.eq(StoreEvents.IsActive(config({ store = "Nowhere" }), during, SLOTS), false)
		t.eq(StoreEvents.IsActive({}, during, SLOTS), false)
		t.eq(StoreEvents.IsActive(nil, during, SLOTS), false)
	end)

	t.test("with no configs every store is closed and no slot is live", function()
		local states = StoreEvents.StatesAt({}, START + DAY, SLOTS)
		for _, store in ipairs(StoreEvents.Stores) do
			t.eq(states[store].active, false, store)
			t.eq(states[store].slotIds, {}, store)
			t.eq(states[store].bannerText, "", store)
		end
		t.eq(next(StoreEvents.LiveSlots(states, SLOTS)), nil)
		t.eq(StoreEvents.Normalize(nil), {})
		t.eq(StoreEvents.Normalize("x"), {})
		t.eq(StoreEvents.Normalize({}), {})
	end)

	t.test("an active config opens only its own store", function()
		local configs = StoreEvents.Normalize(config())
		local states = StoreEvents.StatesAt(configs, START + DAY, SLOTS)
		t.eq(states.HearthAndHome.active, true)
		t.eq(states.HearthAndHome.slotIds, { "event-hearth-1" })
		for _, store in ipairs({ "ToolShed", "Sparkworks", "Dealership" }) do
			t.eq(states[store].active, false, store)
			t.eq(states[store].slotIds, {}, store)
		end
		local live = StoreEvents.LiveSlots(states, SLOTS)
		t.ok(live["event-hearth-1"])
		t.eq(live["event-hearth-1"].price, 250)
		t.eq(next(live, "event-hearth-1"), nil, "nothing else is live")
	end)

	t.test("overlapping events of one store join, and other stores are untouched", function()
		local configs = {
			config({ startsAt = "2026-12-01", endsAt = "2026-12-10", bannerText = "first" }),
			config({
				startsAt = "2026-12-05",
				endsAt = "2026-12-20",
				items = { "event-hearth-1" },
				bannerText = "second",
			}),
			config({ store = "ToolShed", items = { "event-toolshed-1" } }),
		}
		local function at(text)
			return StoreEvents.StatesAt(configs, date(text), SLOTS)
		end
		t.eq(at("2026-12-02").HearthAndHome.bannerText, "FIRST")
		local both = at("2026-12-07")
		t.eq(both.HearthAndHome.bannerText, "SECOND", "the latest start shows")
		t.eq(both.HearthAndHome.slotIds, { "event-hearth-1" }, "an id listed by both is one slot")
		t.eq(#StoreEvents.ActiveFor("HearthAndHome", configs, date("2026-12-07"), SLOTS), 2)
		local late = at("2026-12-12")
		t.eq(late.HearthAndHome.bannerText, "SECOND", "the first has ended, the second runs on")
		t.eq(at("2026-12-20").HearthAndHome.active, false, "both over")
		t.eq(both.ToolShed.slotIds, { "event-toolshed-1" })
		t.eq(both.Sparkworks.active, false)
	end)

	t.test("one bad config among good ones changes nothing else", function()
		local configs = { config(), { store = "HearthAndHome" }, "junk", 7, config({ store = "ToolShed", items = {} }) }
		local states = StoreEvents.StatesAt(configs, START + DAY, SLOTS)
		t.eq(states.HearthAndHome.active, true)
		t.eq(states.ToolShed.active, true)
		t.eq(states.ToolShed.slotIds, {})
	end)

	t.test(
		"a toggle off mid-event closes the store and takes its slots off sale; bought items are not touched",
		function()
			local mid = START + 3 * DAY
			local on = StoreEvents.StatesAt({ config() }, mid, SLOTS)
			t.ok(StoreEvents.LiveSlots(on, SLOTS)["event-hearth-1"], "live while on")
			local off = StoreEvents.StatesAt({ config({ enabled = false }) }, mid, SLOTS)
			t.eq(off.HearthAndHome.active, false)
			t.eq(next(StoreEvents.LiveSlots(off, SLOTS)), nil, "off sale the moment it is off")
			-- (nothing in StoreEvents reads or writes a save: owned items stay owned)
			local back = StoreEvents.StatesAt({ config() }, mid, SLOTS)
			t.eq(back.HearthAndHome.active, true, "flipping it back on is the same as never having turned it off")
		end
	)

	t.test("a clock that jumps is followed: the state only depends on the time it is given", function()
		local configs = { config() }
		local function active(now)
			return StoreEvents.StateFor("HearthAndHome", configs, now, SLOTS).active
		end
		t.eq(active(START - DAY), false)
		t.eq(active(START + DAY), true)
		t.eq(active(START - DAY), false, "the clock went back before the start")
		t.eq(active(END + DAY), false, "and forward past the end")
		t.eq(active(START + 2 * DAY), true, "and back inside")
	end)

	t.test("a server restart recomputes the same answer from the config and the time", function()
		local configs = { config() }
		local now = START + 5 * DAY
		local before = StoreEvents.StatesAt(configs, now, SLOTS)
		local fresh = t.loader({ isolated = true }):shared("StoreEvents")
		t.eq(fresh.StatesAt(configs, now, SLOTS), before)
		local later = fresh.StatesAt(configs, END + 1, SLOTS)
		t.eq(later.HearthAndHome.active, false, "a restart after the end finds it closed")
	end)

	t.test("the committed data: nothing scheduled, every event slot unset and hidden", function()
		local data = t.shared("StoreEventData")
		t.eq(data.Events, {}, "no event is scheduled in the repo")
		local seen = {}
		for _, store in ipairs(StoreEvents.Stores) do
			local rows = StoreData.EventSlots[store]
			t.eq(#rows, 3, store .. " has three event slots")
			for i, row in ipairs(rows) do
				t.eq(row.store, store)
				t.eq(row.index, i)
				t.eq(row.eventSlot, true)
				t.eq(row.visible, false)
				t.eq(row.approved, false, row.id .. " is not approved")
				t.eq(row.price, nil, row.id .. " has no price")
				t.eq(row.itemId, nil)
				t.eq(row.itemKind, nil)
				t.eq(seen[row.id], nil, row.id .. " is a duplicate")
				seen[row.id] = true
				t.eq(StoreEvents.SlotSellable(row), false)
				t.ok(StoreEvents.IsSlotId(row.id))
			end
		end
		t.eq(#StoreData.EventSlotList(), 12)
		-- Even an event that lists every slot, running now, sells nothing.
		local all = {}
		for _, row in ipairs(StoreData.EventSlotList()) do
			table.insert(all, row.id)
		end
		for _, store in ipairs(StoreEvents.Stores) do
			local states = StoreEvents.StatesAt({
				config({ store = store, items = all }),
			}, START + DAY)
			t.eq(states[store].active, true, "the zone still opens")
			t.eq(states[store].slotIds, {}, "but no item can be listed")
			t.eq(next(StoreEvents.LiveSlots(states)), nil)
		end
	end)

	t.test("event slots never leak into the store lists, shelves or the Robux store", function()
		local StoreStock = t.shared("StoreStock")
		local events = {}
		for _, row in ipairs(StoreData.EventSlotList()) do
			events[row.id] = true
		end
		for _, entry in ipairs(StoreStock.All()) do
			t.eq(events[entry.slotId], nil, entry.slotId)
			t.eq(events[entry.itemId], nil, entry.itemId)
		end
		for _, entry in ipairs(StoreData.Ordered()) do
			t.eq(events[entry.key], nil)
		end
		t.eq(StoreStock.Find("Cosmetic", "event-hearth-1"), nil)
	end)
end
