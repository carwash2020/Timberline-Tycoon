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
			t.eq(data, once, "a second migrate changes nothing")
			local bytes = #serde.encode("json", data)
			t.ok(bytes <= MB, string.format("%s is %d bytes", name, bytes))
		end)
	end
end
