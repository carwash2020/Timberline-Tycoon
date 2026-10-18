--!nocheck
-- Overlap report (WORLD-SPREAD): does anything on the map share space with
-- anything else? Read-only: it prints every hit with ids and coordinates and
-- changes nothing. Run from the repo root:   lune run tools/overlap_report
-- The shapes and rules are in Shared/World/OverlapCheck (tests/Overlap.spec
-- asserts the same pairs).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/overlap_report")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local WorldPlan = modules:shared("World/WorldPlan")
local OverlapCheck = modules:shared("World/OverlapCheck")

local grid, counts = OverlapCheck.Build(WorldPlan)
print(
	string.format(
		"Shapes: %d trees, %d boulders, %d cluster rocks, %d scenery, %d buildings, %d building parts, %d props, %d plot pads",
		counts.tree or 0,
		counts.boulder or 0,
		counts.cluster or 0,
		counts.scenery or 0,
		counts.building or 0,
		counts.part or 0,
		counts.prop or 0,
		counts.plot or 0
	)
)

local function fmt(e): string
	local s = e.shape
	return string.format("%s (%.1f, %.1f)", e.id, (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2)
end

local total = 0
for _, result in ipairs(OverlapCheck.Run(grid)) do
	total += #result.hits
	print("")
	print(string.format("%s: %d", result.title, #result.hits))
	table.sort(result.hits, function(a, b)
		return a.a.id < b.a.id
	end)
	for _, h in ipairs(result.hits) do
		print(string.format("  %s  vs  %s  (gap %.2f)", fmt(h.a), fmt(h.b), h.gap))
	end
end
print("")
print(string.format("Total hits: %d", total))
