--!nocheck
-- AllowlistCap (T409): tests/geometry_allow.json is not a place to park overlaps. Every collision overlap in
-- the world was fixed; what is left are the invisible world-edge walls, which overlap each other and the strip
-- by design and which nobody can reach. This spec fails when the list grows: a new entry means a real overlap
-- somebody chose not to fix, and that is a decision for Builder, not a line in a JSON file.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local list = serde.decode("json", fs.readFile("tests/geometry_allow.json"))

	-- The agreed entries: the three edge-wall pairs, and nothing else.
	local AGREED = {
		["WorldEdge#* x WorldEdge#*"] = true,
		["NorthStrip x WorldEdge#*"] = true,
		["BoulderClusters/BoulderCluster#17 x WorldEdge#*"] = true,
	}
	local CAP = 3 -- the most entries geometry_allow.json may hold

	t.test("geometry_allow.json holds at most the 3 agreed edge-wall entries", function()
		t.ok(
			#list <= CAP,
			string.format("%d entries, the cap is %d: fix the overlap instead of allowlisting it", #list, CAP)
		)
		for _, entry in ipairs(list) do
			t.ok(AGREED[entry.a .. " x " .. entry.b], "not an agreed entry: " .. entry.a .. " x " .. entry.b)
			t.ok(string.find(entry.a .. entry.b, "WorldEdge", 1, true), "only the world-edge walls may be allowlisted")
			t.ok(type(entry.reason) == "string" and #entry.reason > 20, "every entry needs a reason")
		end
	end)

	t.test("the part-build lane lint has no named exemptions either", function()
		local LaneData = t.load("ReplicatedStorage/Shared/Lint/LaneData")
		t.eq(#LaneData.Allow, 0, "LaneData.Allow must stay empty: move or shrink the part instead")
	end)
end
