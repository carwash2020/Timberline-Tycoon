--!nocheck
-- Saves written before this overhaul (schema at v1-pre-overhaul, cc73beb).
-- Migrate may add fields. It must not drop cash, axes, trucks, placed
-- pieces, or saved sections, and a second pass must leave the save as it was.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local MB = 1024 * 1024

	local function axesOf(list)
		local out = {}
		if type(list) ~= "table" then
			return out
		end
		for _, axe in ipairs(list) do
			if type(axe) == "table" then
				table.insert(out, { uid = axe.uid, id = axe.id })
			end
		end
		return out
	end

	local function placedOf(plot)
		local out = {}
		local placed = if type(plot) == "table" then plot.placed else nil
		if type(placed) ~= "table" then
			return out
		end
		for _, item in ipairs(placed) do
			if type(item) == "table" then
				table.insert(out, {
					uid = item.uid,
					blueprintId = item.blueprintId,
					x = item.x,
					z = item.z,
					rot = item.rot,
				})
			end
		end
		return out
	end

	local function sectionsOf(list)
		local out = {}
		if type(list) ~= "table" then
			return out
		end
		for _, piece in ipairs(list) do
			if type(piece) == "table" and type(piece.s) == "table" then
				table.insert(out, piece.s)
			end
		end
		return out
	end

	local function kept(record)
		local trucks = {}
		if type(record.ownedTrucks) == "table" then
			trucks = record.ownedTrucks
		end
		return {
			cash = record.cash,
			axes = axesOf(record.axes),
			trucks = trucks,
			placed = placedOf(record.plot),
			truck = sectionsOf(record.truckLoad),
			-- Ring map (WorldVersion 2): an old save's ground wood moves to
			-- strandedLoad (Lane F puts it back on the plot). It is not lost.
			ground = (function()
				local both = sectionsOf(record.groundLoad)
				for _, piece in ipairs(sectionsOf(record.strandedLoad)) do
					table.insert(both, piece)
				end
				return both
			end)(),
		}
	end

	local function contains(have, want, label)
		for _, item in ipairs(want) do
			local found = false
			for _, got in ipairs(have) do
				if serde.encode("json", got) == serde.encode("json", item) then
					found = true
					break
				end
			end
			t.ok(found, label)
		end
		t.eq(#have, #want, label .. " count")
	end

	for _, name in ipairs({ "new", "mid", "late" }) do
		t.test(name .. ": nothing owned is lost, a second migrate matches, and it fits", function()
			local data = serde.decode("json", fs.readFile("tests/fixtures/saves/" .. name .. ".json"))
			local before = kept(data)
			Schema.Migrate(data)
			local after = kept(data)
			t.eq(after.cash, before.cash, "cash")
			contains(after.axes, before.axes, "axes")
			contains(after.trucks, before.trucks, "trucks")
			contains(after.placed, before.placed, "placed")
			contains(after.truck, before.truck, "truck sections")
			contains(after.ground, before.ground, "ground sections")
			local once = Util.deepCopy(data)
			Schema.Migrate(data)
			-- Migrate stamps the active slot's lastPlayed with the clock, so a second that ticks
			-- between the two runs would differ there (CI flake, 12 October 2026): carry the
			-- stamp across and compare everything else.
			for key, slot in pairs(data.slots) do
				once.slots[key].lastPlayed = slot.lastPlayed
			end
			t.eq(data, once, "a second migrate changes nothing")
			local bytes = #serde.encode("json", data)
			t.ok(bytes <= MB, string.format("%s is %d bytes", name, bytes))
		end)
	end
	-- Lane Z: the whole join chain on a save older than the V1 overhaul
	-- (ProfileStore's Reconcile, the world-version stand-in, Migrate, then
	-- MigrateV2), run twice. A hand-built "cc73beb" save: no mining, temper,
	-- relics or regions, an old map, ground wood, a built plot, the three old
	-- passes, owner grants, a Lux Axe and a half-done tutorial.
	local GameConfig = t.shared("GameConfig")

	local function reconcile(target, template)
		for k, v in pairs(template) do
			if type(k) == "string" then
				if target[k] == nil then
					target[k] = if type(v) == "table" then Util.deepCopy(v) else v
				elseif type(target[k]) == "table" and type(v) == "table" then
					reconcile(target[k], v)
				end
			end
		end
	end

	-- What a join does, in order (ProfileService.LoadProfile, then GameServer's MigrateV2).
	local function join(data)
		local hadWorldVersion = data.worldVersion ~= nil
		reconcile(data, Schema.Template)
		if not hadWorldVersion then
			data.worldVersion = 1
		end
		Schema.Migrate(data)
		Schema.MigrateV2(data, GameConfig.StartingCash)
	end

	-- Migrate stamps the active slot's lastPlayed with the clock.
	local function sameClock(before, data)
		for key, slot in pairs(data.slots) do
			before.slots[key].lastPlayed = slot.lastPlayed
		end
	end

	local function oldSave()
		local lux = "00000a01-4000-8000-8000-000000000a01"
		local steel = "00000a02-4000-8000-8000-000000000a02"
		return {
			schema = 4,
			cash = 31234,
			totalEarned = 90210,
			axes = {
				{ uid = steel, id = "SteelAxe" },
				{ uid = lux, id = "LuxAxe" },
			},
			bestAxeTier = 2,
			equippedAxe = lux,
			accountAxes = { "LuxAxe" },
			ownedTrucks = { "Rustbucket", "Pickup" },
			equippedTruck = "Pickup",
			gear = { "InsulatedCoat" },
			passes = { TowService = true, TimberClassic = true, PaintShop = true },
			purchaseIds = { "receipt-1", "receipt-2" },
			ownerGrants = { DoubleCash = { at = 1750000000, by = 7, byName = "Owner" } },
			tutorialDone = false,
			tutorialStep = 3,
			tutorialProgress = 1,
			plot = {
				claimed = true,
				tier = 2,
				placed = {
					{ uid = "00000b01-4000-8000-8000-000000000b01", blueprintId = "Cabin", x = 8, z = 12, rot = 0 },
					{ uid = "00000b02-4000-8000-8000-000000000b02", blueprintId = "Wall4", x = -16, z = 4, rot = 1 },
				},
				squares = {},
			},
			blueprintBook = { "Cabin", "Wall4" },
			truckLoad = {
				{
					w = "pine",
					k = "log",
					bed = "BedFloor",
					at = { 1.5, 0.6, -2.0, 0.0, 1.5708, 0.0 },
					s = { { 1.25, 2.5, 8.0, -1.875, 0.4, 0.0, 0.0, 0.0, 0.0, 0 } },
				},
			},
			groundLoad = {
				{
					w = "oak",
					k = "log",
					bed = "Ground",
					at = { 0, 0, 0, 0, 0, 0 },
					g = { 40, 1, -60 },
					s = { { 1.25, 2.5, 8.0, 0.0, 0.4, 0.0, 0.0, 0.0, 0.0, 0 } },
				},
			},
			materials = { SkyShard = 3 },
		}
	end

	local function uids(list)
		local out = {}
		for _, item in ipairs(list) do
			table.insert(out, item.uid)
		end
		table.sort(out)
		return out
	end

	t.test("a pre-V1 save joins: nothing owned is lost, nothing is granted twice, V1 fields appear", function()
		local data = oldSave()
		local axesBefore = uids(data.axes)
		join(data)
		t.eq(data.cash, 31234, "cash is untouched (MigrateV2 credits through v2Credit, never cash)")
		t.eq(data.totalEarned, 90210)
		t.eq(uids(data.axes), axesBefore, "the same axes, no duplicate Lux Axe or Rusty Axe grant")
		t.eq(data.accountAxes, { "LuxAxe" }, "the pass axe stays on the account")
		t.eq(data.passes, { TowService = true, TimberClassic = true, PaintShop = true }, "old passes kept")
		t.eq(data.purchaseIds, { "receipt-1", "receipt-2" }, "receipts kept")
		t.ok(data.ownerGrants.DoubleCash ~= nil, "the owner grant kept")
		t.eq(#data.plot.placed, 2, "the built plot kept")
		t.eq(data.plot.placed[1].blueprintId, "Cabin")
		t.ok(table.find(data.blueprintBook, "Cabin") and table.find(data.blueprintBook, "Wall4"), "book kept")
		t.eq(#data.truckLoad, 1, "the truck load kept")
		t.eq(data.worldVersion, GameConfig.WorldVersion, "stamped with the current map")
		t.eq(#data.strandedLoad, 1, "ground wood from the old map waits to go back on the plot")
		t.eq(#data.groundLoad, 0)
		t.ok(type(data.mining) == "table", "the mining section was added")
		t.ok(type(data.temper) == "table" and type(data.relics) == "table", "end-game fields added")
		t.eq(data.materials.SkyShard, 3)
		t.ok(data.tutorialStep >= 1, "a half-done tutorial still has a step")
		t.eq(#data.slots, 3, "three slots")
	end)

	t.test("joining again (a rejoin) changes nothing, and the stranded wood is restored once", function()
		local data = oldSave()
		join(data)
		local once = Util.deepCopy(data)
		join(data)
		sameClock(once, data)
		-- Migrate drops a few empty runtime keys (tipsSeen, truckAt, v2Credit) that the next
		-- Reconcile puts back as the same empty defaults; compare after that.
		reconcile(once, Schema.Template)
		for key, value in pairs(data) do
			if key == "slots" then
				for index, slot in ipairs(value) do
					for field, inner in pairs(slot) do
						-- (the live empty truckAt is copied into the snapshot once Reconcile restores it)
						if not (type(inner) == "table" and next(inner) == nil and once.slots[index][field] == nil) then
							t.eq(inner, once.slots[index][field], "slot " .. index .. " keeps " .. field)
						end
					end
					for field in pairs(once.slots[index]) do
						t.ok(slot[field] ~= nil, "slot " .. index .. " loses " .. field)
					end
				end
			else
				t.eq(value, once[key], "a second join leaves " .. key .. " alone")
			end
		end
		t.eq(#data.strandedLoad, 1, "stranded wood is not appended again")
		join(data)
		t.eq(#data.strandedLoad, 1, "or a third time")
	end)

	t.test("three played slots survive the chain, each keeping its own cash, and the save fits", function()
		local data = oldSave()
		join(data)
		-- Slots 2 and 3 as played saves (a snapshot of the live one with other cash).
		local live = data.slots[data.activeSlot]
		for index, cash in ipairs({ 0, 777, 88888 }) do
			if index ~= data.activeSlot then
				local copy = Util.deepCopy(live)
				copy.cash = cash
				copy.fresh = false
				data.slots[index] = copy
			end
		end
		local before = {}
		for index, slot in ipairs(data.slots) do
			before[index] = slot.cash
		end
		join(data)
		for index, slot in ipairs(data.slots) do
			t.eq(slot.cash, before[index], "slot " .. index .. " cash")
		end
		local bytes = #serde.encode("json", data)
		t.ok(bytes <= MB, "three slots are " .. bytes .. " bytes")
	end)

	t.test("every profile field the services write is in the template (no field outside ProfileSchema)", function()
		local template = Schema.Template
		local written = {}
		local function scan(dir)
			for _, name in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					if name ~= "Vendor" then
						scan(path)
					end
				elseif string.sub(name, -5) == ".luau" and name ~= "ProfileSchema.luau" then
					for line in string.gmatch(fs.readFile(path), "[^\n]+") do
						if not string.match(line, "^%s*%-%-") then
							for field in string.gmatch(line, "[pP]rofile%.([%a_][%w_]*)%s*=[^=]") do
								written[field] = path
							end
						end
					end
				end
			end
		end
		scan("src/ServerScriptService")
		for field, path in pairs(written) do
			t.ok(
				template[field] ~= nil,
				path .. " writes profile." .. field .. " which is not in ProfileSchema.Template"
			)
		end
	end)
end
