--!nocheck
-- The blueprint book: the plans you own forever, the rolled plans that add
-- to it, the list the hammer opens, and the one rule for "may this be placed".
return function(t)
	local Book = t.shared("BlueprintBook")
	local PlotData = t.shared("PlotData")

	local function copy(list)
		return table.clone(list)
	end

	t.test("the starter plans are what was free to place before: no store unlocks, no boxed machines", function()
		local starter = Book.Starter()
		t.ok(#starter > 10)
		t.ok(Book.Has(starter, "Wall"))
		t.ok(Book.Has(starter, "Cabin"))
		t.ok(Book.Has(starter, "Bench"))
		t.ok(not Book.Has(starter, "Shed"), "Shed is a store unlock")
		t.ok(not Book.Has(starter, "SawmillRickety"), "a sawmill is a box")
		t.ok(not Book.Has(starter, "ChopSaw"))
		for _, id in ipairs(starter) do
			local bp = PlotData.Blueprint(id)
			t.ok(bp ~= nil and bp.unlock ~= true, id)
		end
		local seen = {}
		for _, id in ipairs(starter) do
			t.ok(not seen[id], "duplicate " .. id)
			seen[id] = true
		end
	end)

	t.test("Learn adds an id once and ignores nonsense", function()
		local book = {}
		t.ok(Book.Learn(book, "Shed"))
		t.ok(not Book.Learn(book, "Shed"), "already there")
		t.ok(not Book.Learn(book, "Nope"), "not a blueprint")
		t.ok(not Book.Learn(book, 7))
		t.ok(not Book.Learn(book, nil))
		t.eq(book, { "Shed" })
		t.ok(Book.Learn(book, "SawmillRickety"), "machines can be in the book (a paid-for one)")
	end)

	t.test("Clean keeps real ids, once each, in order", function()
		t.eq(Book.Clean({ "Wall", "Wall", "Nope", 4, "Shed" }), { "Wall", "Shed" })
		t.eq(Book.Clean("x"), {})
		t.eq(Book.Clean(nil), {})
	end)

	t.test("CleanItems keeps real plans with a uid, each uid once, up to the cap", function()
		local raw = {
			{ uid = "a", id = "Shed" },
			{ uid = "a", id = "Shed" },
			{ uid = "", id = "Shed" },
			{ uid = "b", id = "Nope" },
			{ uid = "c", id = "SawmillRickety" },
			"junk",
			{ uid = "d", id = "Mailbox", extra = true },
		}
		t.eq(Book.CleanItems(raw), { { uid = "a", id = "Shed" }, { uid = "d", id = "Mailbox" } })
		local many = {}
		for i = 1, Book.MaxItems + 10 do
			table.insert(many, { uid = "u" .. i, id = "Shed" })
		end
		t.eq(#Book.CleanItems(many), Book.MaxItems)
	end)

	t.test("Redeem consumes the item and teaches the book, once", function()
		local book, items = {}, { { uid = "a", id = "Shed" }, { uid = "b", id = "Mailbox" } }
		local result, id = Book.Redeem(book, items, "a")
		t.eq({ result, id }, { "ok", "Shed" })
		t.eq(book, { "Shed" })
		t.eq(items, { { uid = "b", id = "Mailbox" } })
		-- The same uid again: gone.
		local again, none = Book.Redeem(book, items, "a")
		t.eq(again, "missing")
		t.eq(none, nil)
		t.eq(book, { "Shed" })
	end)

	t.test("Redeem keeps the item when you already know the building", function()
		local book, items = { "Shed" }, { { uid = "a", id = "Shed" } }
		local result, id = Book.Redeem(book, items, "a")
		t.eq({ result, id }, { "known", "Shed" })
		t.eq(#items, 1, "nothing is wasted")
		t.eq(book, { "Shed" })
	end)

	t.test("Redeem refuses a uid that is not yours or not a string", function()
		local book, items = {}, { { uid = "a", id = "Shed" } }
		t.eq((Book.Redeem(book, items, "zzz")), "missing")
		t.eq((Book.Redeem(book, items, 5)), "missing")
		t.eq((Book.Redeem(book, items, nil)), "missing")
		t.eq(#items, 1)
		t.eq(book, {})
	end)

	t.test("Grant adds an item, refuses a bad id, a repeat uid, and a full pack", function()
		local items = {}
		t.eq(Book.Grant(items, "Shed", "a"), "ok")
		t.eq(Book.Grant(items, "Shed", "a"), "uid")
		t.eq(Book.Grant(items, "Shed", ""), "uid")
		t.eq(Book.Grant(items, "Nope", "b"), "unknown")
		t.eq(Book.Grant(items, "SawmillRickety", "b"), "unknown", "a machine is a box, not a plan")
		for i = 1, Book.MaxItems - 1 do
			t.eq(Book.Grant(items, "Mailbox", "m" .. i), "ok")
		end
		t.eq(Book.Grant(items, "Mailbox", "overflow"), "full")
		t.eq(#items, Book.MaxItems)
	end)

	t.test("Owns reads the book and the old furniture set", function()
		t.ok(Book.Owns({ blueprintBook = { "Wall" } }, "Wall"))
		t.ok(not Book.Owns({ blueprintBook = { "Wall" } }, "Shed"))
		t.ok(Book.Owns({ furnitureBlueprints = { Shed = true } }, "Shed"))
		t.ok(not Book.Owns({ furnitureBlueprints = { Shed = false } }, "Shed"))
		t.ok(not Book.Owns(nil, "Shed"))
	end)

	t.test("Migrate: starters, bought unlocks, everything placed, boxes in stock; adds, never removes", function()
		local record = {
			blueprintBook = { "Fence" },
			furnitureBlueprints = { Shed = true, Mailbox = false },
			plot = { placed = { { uid = "1", blueprintId = "SawmillRickety" }, { uid = "2", blueprintId = "Table" } } },
			sawmillStock = { "ChopSaw" },
			blueprintItems = { { uid = "a", id = "Shed" }, "junk" },
		}
		Book.Migrate(record)
		local book = record.blueprintBook
		t.eq(book[1], "Fence", "what was there stays first")
		t.ok(Book.Has(book, "Wall"), "a starter")
		t.ok(Book.Has(book, "Shed"), "a bought unlock")
		t.ok(not Book.Has(book, "Mailbox"), "an unlock they never bought")
		t.ok(Book.Has(book, "SawmillRickety"), "a placed sawmill they paid for")
		t.ok(Book.Has(book, "Table"), "a placed unlock")
		t.ok(Book.Has(book, "ChopSaw"), "a box they hold")
		t.eq(record.blueprintItems, { { uid = "a", id = "Shed" } })
		t.eq(record.hammer, true)
	end)

	t.test("Migrate is idempotent", function()
		local record = {
			furnitureBlueprints = { Shed = true, Table = true, Chair = true },
			plot = { placed = { { uid = "1", blueprintId = "Cabin" } } },
			sawmillStock = {},
		}
		Book.Migrate(record)
		local once = copy(record.blueprintBook)
		local onceCount = #record.blueprintBook
		Book.Migrate(record)
		Book.Migrate(record)
		t.eq(record.blueprintBook, once)
		t.eq(#record.blueprintBook, onceCount)
	end)

	t.test("Migrate copes with a save that has none of the fields", function()
		local record = {}
		Book.Migrate(record)
		t.eq(record.blueprintBook, Book.Starter())
		t.eq(record.blueprintItems, {})
		t.eq(record.hammer, true)
	end)

	t.test("Migrate gives the same order every time (the legacy set has no order)", function()
		local a = { furnitureBlueprints = { Shed = true, Table = true, Chair = true, Rug = true } }
		local b = { furnitureBlueprints = { Rug = true, Chair = true, Shed = true, Table = true } }
		Book.Migrate(a)
		Book.Migrate(b)
		t.eq(a.blueprintBook, b.blueprintBook)
	end)

	t.test(
		"Allowed: learned plans place; a boxed machine needs a box; an unlearned unlock says where to buy",
		function()
			local function allowed(id, owned, stocked, boxed)
				local ok, why = Book.Allowed(id, owned, stocked, boxed)
				return { ok, why }
			end
			-- A learned (or starter) plan.
			t.eq(allowed("Wall", true, 0, true), { true, nil })
			-- Not learned: a store unlock names the General Store, others say not learned.
			t.eq(allowed("Shed", false, 0, true), { false, "store" })
			t.eq(allowed("Wall", false, 0, true), { false, "notOwned" })
			-- Boxed machines: a box in stock places, none says Tool Shed. Ownership is no help.
			t.eq(allowed("SawmillRickety", false, 1, true), { true, nil })
			t.eq(allowed("SawmillRickety", true, 0, true), { false, "toolShed" })
			t.eq(allowed("ChopSaw", false, 0, true), { false, "toolShed" })
			-- With boxed shelves off (the v1 rollback) a machine is paid for as placed.
			t.eq(allowed("SawmillRickety", false, 0, false), { true, nil })
			-- An id that is not a blueprint at all.
			t.eq(allowed("Nope", true, 0, true), { false, "notOwned" })
		end
	)

	t.test("the refusal texts keep the old palette's words", function()
		local shed = PlotData.Blueprint("Shed")
		t.eq(Book.Message("store", shed), "Buy the Small Shed at the General Store first.")
		t.eq(Book.Message("toolShed", shed), "Buy the Small Shed at the Tool Shed first.")
		t.ok(string.find(Book.Message("notOwned", shed), "hammer", 1, true))
	end)

	t.test("Entries: the book plus boxes in stock, grouped, then by tier and price", function()
		local book = Book.Starter()
		local entries = Book.Entries(book, { SawmillRickety = 2 })
		t.eq(#entries, #book + 1, "one more: the sawmill you hold")
		local lastGroup, lastRank = nil, 0
		local rank = { Buildings = 1, Decor = 2, Machines = 3 }
		for _, e in ipairs(entries) do
			t.ok(rank[e.group] >= lastRank, "groups stay in order at " .. e.id)
			lastRank = rank[e.group]
			lastGroup = e.group
		end
		t.eq(lastGroup, "Machines")
		t.eq(entries[#entries].id, "SawmillRickety")
		t.eq(entries[#entries].stock, 2)
		-- No box, no row, even when the id is in the book.
		local without = Book.Entries({ "SawmillRickety", "Wall" }, {})
		t.eq(#without, 1)
		t.eq(without[1].id, "Wall")
	end)

	t.test("Entries is stable: the same book and stock give the same list", function()
		local a = Book.Entries(Book.Starter(), {})
		local b = Book.Entries(Book.Starter(), {})
		for i, e in ipairs(a) do
			t.eq(e.id, b[i].id)
		end
		-- Within a group the cheaper, lower-tier piece comes first.
		local decorCosts = {}
		for _, e in ipairs(a) do
			if e.group == "Decor" then
				table.insert(decorCosts, { e.bp.tier, PlotData.Price(e.bp) })
			end
		end
		for i = 2, #decorCosts do
			local p, q = decorCosts[i - 1], decorCosts[i]
			t.ok(p[1] < q[1] or (p[1] == q[1] and p[2] <= q[2]), "decor order at " .. i)
		end
	end)

	t.test("Filter narrows to a group, and an unknown filter shows everything", function()
		local entries = Book.Entries(Book.Starter(), {})
		local decor = Book.Filter(entries, "Decor")
		t.ok(#decor > 0 and #decor < #entries)
		for _, e in ipairs(decor) do
			t.eq(e.group, "Decor")
		end
		t.eq(#Book.Filter(entries, "All"), #entries)
		t.eq(#Book.Filter(entries, "Whatever"), #entries)
		t.eq(#Book.Filter(entries, "Machines"), 0)
	end)

	t.test("NextFilter cycles through every filter and back", function()
		local at, seen = "All", {}
		for _ = 1, #Book.Filters do
			at = Book.NextFilter(at)
			seen[at] = true
		end
		t.eq(at, "All")
		t.eq(seen.Buildings, true)
		t.eq(seen.Decor, true)
		t.eq(seen.Machines, true)
		t.eq(Book.NextFilter("junk"), "All", "an unknown filter starts over")
	end)

	t.test("every row says its name, its size and what it needs", function()
		local ctx = { tier = 5, cash = 10000000, boxed = true }
		for _, e in ipairs(Book.Entries(Book.Starter(), {})) do
			local row = Book.Row(e, ctx)
			t.eq(row.name, e.bp.displayName)
			t.ok(string.find(row.detail, string.format("%d × %d", e.bp.footprint.X, e.bp.footprint.Y), 1, true), e.id)
			t.ok(
				string.find(row.detail, "planks", 1, true) or string.find(row.detail, "place", 1, true),
				e.id .. " says what it needs: " .. row.detail
			)
			t.ok(row.ready, e.id)
		end
	end)

	t.test("a kit row names its wood and fee; the fee is the price the server charges", function()
		local wall = PlotData.Blueprint("Wall")
		local entry = { id = "Wall", bp = wall, group = "Buildings", stock = 0 }
		local row = Book.Row(entry, { tier = 1, cash = 1000, boxed = true })
		t.ok(string.find(row.detail, "8 u³ of planks", 1, true), row.detail)
		t.ok(string.find(row.detail, "$32", 1, true), row.detail)
		t.eq(row.button, "Place $32")
		t.eq(row.state, "buy")
	end)

	t.test("a row is locked by plot size and greyed when you are short of cash", function()
		local warehouse = PlotData.Blueprint("Warehouse")
		local entry = { id = "Warehouse", bp = warehouse, group = "Buildings", stock = 0 }
		local locked = Book.Row(entry, { tier = 1, cash = 1e9, boxed = true })
		t.eq(locked.state, "locked")
		t.eq(locked.ready, false)
		t.ok(string.find(locked.message, "Homestead", 1, true))
		local broke = Book.Row(entry, { tier = 2, cash = 100, boxed = true })
		t.eq(broke.state, "cant")
		t.eq(broke.ready, false)
		t.ok(string.find(broke.message, "$3,900 more", 1, true), broke.message)
		local fine = Book.Row(entry, { tier = 2, cash = 5000, boxed = true })
		t.eq(fine.ready, true)
	end)

	t.test("an unlock you learned places free; a box in stock places free and shows its count", function()
		local shed = PlotData.Blueprint("Shed")
		local entry = { id = "Shed", bp = shed, group = "Buildings", stock = 0 }
		local row = Book.Row(entry, { tier = 1, cash = 0, boxed = true })
		t.eq(row.ready, true)
		t.eq(row.button, "Place")
		local mill = t.shared("PlotLogic").Blueprint("SawmillRickety")
		local box = { id = "SawmillRickety", bp = mill, group = "Machines", stock = 2 }
		local stocked = Book.Row(box, { tier = 1, cash = 0, boxed = true })
		t.eq(stocked.ready, true)
		t.eq(stocked.own, "· 2 in stock")
		t.ok(string.find(stocked.detail, "Placed from your box", 1, true))
	end)

	t.test("the redeem texts say what happened", function()
		t.ok(string.find(Book.RedeemText("ok", "Shed"), "learned the Small Shed", 1, true))
		t.ok(string.find(Book.RedeemText("known", "Shed"), "already know", 1, true))
		t.ok(string.find(Book.RedeemText("missing", nil), "isn't in your pack", 1, true))
	end)
end
