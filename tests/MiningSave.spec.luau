--!nocheck
-- profile.mining is account-wide. A dirty blob left on a slot is lifted
-- once, cleaned, and stripped. The Obsidian turn-in key is HeartstoneTurnIn.

return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local function sameClock(before, data)
		if type(data.slots) == "table" and type(before.slots) == "table" then
			for key, slot in pairs(data.slots) do
				if type(before.slots[key]) == "table" then
					before.slots[key].lastPlayed = slot.lastPlayed
				end
			end
		end
	end

	t.test("a slot's mining is lifted, the turn-in key survives, and a second migrate is a no-op", function()
		local data = serde.decode("json", fs.readFile("tests/fixtures/saves/new.json"))
		local dirty = serde.decode("json", fs.readFile("tests/fixtures/saves/mining.json"))
		Schema.Migrate(data)
		data.mining = nil
		data.slots[data.activeSlot].mining = dirty
		Schema.Migrate(data)
		t.eq(data.slots[data.activeSlot].mining, nil)
		t.eq(data.mining.v, 1)
		t.eq(data.mining.picks.SteelPick, true)
		t.eq(data.mining.picks.Nope, nil)
		t.eq(data.mining.pick, "SteelPick")
		t.eq(data.mining.bombs, 3)
		t.eq(data.mining.ropes, 0)
		t.eq(data.mining.lamp, true)
		t.eq(data.mining.crafted.HeartstoneTurnIn, 1)
		t.eq(data.mining.crafted.zero, nil)
		local before = Util.deepCopy(data)
		Schema.Migrate(data)
		sameClock(before, data)
		t.eq(data, before)
	end)
end
