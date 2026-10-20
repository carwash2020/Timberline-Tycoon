--!nocheck
-- Tree cover (T400): plans the real trees that fill the gaps between the groves
-- and relocates the movable wild trees that break a rule, keeping the count.
-- Run from the repo root:
--   lune run tools/tree_cover            plan and print the report
--   lune run tools/tree_cover --write    and write TreeSpreadData.Relocated and .Cover
-- The plan depends on the world only (WorldPlan.Trees and the other lists, the
-- thinning in TreeSpreadData.Skipped), never on the data it writes, so running
-- it twice gives the same answer. Slow (minutes): it is a tool, not boot code.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/tree_cover")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local WorldPlan = modules:shared("World/WorldPlan")
local TreeCover = modules:shared("World/TreeCover")
local TreeCoverWorld = modules:shared("World/TreeCoverWorld")

local WRITE = false
for _, a in ipairs(process.args) do
	if a == "--write" then
		WRITE = true
	end
end

-- The refill this replaces planted 132 trees: the count stays.
local OLD_SPREAD = 132

local started = os.clock()
local items = TreeCoverWorld.BaseItems(WorldPlan)
local total = #items + OLD_SPREAD
print(string.format("standing before the plan: %d trees (+ %d spread = %d)", #items, OLD_SPREAD, total))

local env = TreeCoverWorld.Env(total, nil, WorldPlan)
env.log = function(message)
	print(string.format("[%5.0fs] %s", os.clock() - started, message))
end
local result = TreeCover.Plan(env, items)
local r = result.report
print(
	string.format(
		"planned %d new trees in %d clumps (%d lone), relocated %d (legacy: gap %d, road %d, keep-out %d; extra %d), padded %d",
		#result.trees,
		r.clumps,
		r.singles,
		#result.relocated,
		r.legacy.gap,
		r.legacy.road,
		r.legacy.keepout,
		r.extraDrops,
		r.padded
	)
)
print(
	string.format(
		"unfilled: %d empty squares, %d road samples; no lane: %d tries; %.0f s",
		r.unfilledSquares,
		r.unfilledRoad,
		r.noLane,
		os.clock() - started
	)
)
assert(#items - #result.relocated + #result.trees == total, "the count moved")

if WRITE then
	local path = "src/ReplicatedStorage/Shared/World/TreeSpreadData.luau"
	local source = fs.readFile(path)
	local reloc = { "TreeSpreadData.Relocated = {" }
	for _, e in ipairs(result.relocated) do
		table.insert(reloc, string.format("\t{ index = %d, x = %.2f, z = %.2f },", e.index, e.x, e.z))
	end
	table.insert(reloc, "} :: { Relocation }")
	local cover = { "TreeSpreadData.Cover = {" }
	for _, e in ipairs(result.trees) do
		table.insert(
			cover,
			string.format('\t{ clump = %d, x = %.2f, z = %.2f, wood = "%s" },', e.clump, e.x, e.z, e.wood)
		)
	end
	table.insert(cover, "} :: { CoverTree }")
	local function replaceBlock(text, head, block)
		local a = string.find(text, head, 1, true)
		assert(a, "no " .. head)
		local _, b = string.find(text, "} :: { [%a]+ }", a)
		assert(b, "no end for " .. head)
		-- the empty form: `TreeSpreadData.X = {} :: { T }`
		local line = string.match(string.sub(text, a), "^[^\n]*")
		if string.find(line, "= {} ::", 1, true) then
			return string.sub(text, 1, a - 1) .. table.concat(block, "\n") .. string.sub(text, a + #line)
		end
		return string.sub(text, 1, a - 1) .. table.concat(block, "\n") .. string.sub(text, b + 1)
	end
	source = replaceBlock(source, "TreeSpreadData.Relocated =", reloc)
	source = replaceBlock(source, "TreeSpreadData.Cover =", cover)
	fs.writeFile(path, source)
	print("wrote " .. path)
end
