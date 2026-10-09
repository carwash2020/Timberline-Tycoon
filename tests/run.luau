--!nocheck
-- Test runner. From the repo root:   lune run tests/run
-- Optional filter:                   lune run tests/run Shop
-- One shard of N (CI splits the tests across runners this way):
--                                     TEST_SHARD=2/4 lune run tests/run
--   Specs are dealt out slowest first, each to the shard with the least
--   work so far, so every shard takes about the same time. The split is
--   deterministic, every spec lands in exactly one shard, and with no
--   TEST_SHARD set every spec runs.
--
-- Runs every tests/*.spec.luau. A spec file returns a function that gets a
-- `t` with:
--   t.test(name, fn)        a test; it fails if fn errors
--   t.eq(actual, expected)  equal (deep for tables)
--   t.ok(value, message?)   truthy
--   t.fails(fn, pattern?)   fn must error (optionally matching pattern)
--   t.loader(options?)      a fresh module Loader (see tools/loader.luau)
--   t.shared(name), t.server(name)  load a module with a shared Loader
--   t.load(path)            any module by its path under src/ (e.g. "ReplicatedStorage/Shared/World/TerrainGen")
--   t.roblox                @lune/roblox (Enum, Vector3, ...)
-- Exits non-zero if anything fails, so CI can gate on it.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tests/run")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()

local filter = process.args[1]

-- Rough CI seconds for the slow specs, used only to balance TEST_SHARD.
-- Any spec not listed counts as 1 second. Stale numbers only make the shards
-- uneven; they never skip or repeat a spec. Refresh from a CI log if one
-- shard starts taking much longer than the others.
local SLOW_SPECS: { [string]: number } = {
	["AetherServiceV2.spec.luau"] = 6,
	["BoxService.spec.luau"] = 5,
	["DailyService.spec.luau"] = 20,
	["DecorCover.spec.luau"] = 13,
	["DriveMath.spec.luau"] = 24,
	["Forest.spec.luau"] = 25,
	["ForestFiller.spec.luau"] = 47,
	["ForestService.spec.luau"] = 12,
	["ForestServiceV2.spec.luau"] = 3,
	["LandscapeStyle.spec.luau"] = 17,
	["LogicService.spec.luau"] = 3,
	["MapBuilder.spec.luau"] = 66,
	["MonetizationService.spec.luau"] = 6,
	["NPCService.spec.luau"] = 3,
	["Phase12World.spec.luau"] = 7,
	["PlanPause.spec.luau"] = 14,
	["PlotLogic.spec.luau"] = 6,
	["PlotPlatform.spec.luau"] = 5,
	["PlotService.spec.luau"] = 32,
	["ProfileSchema.spec.luau"] = 7,
	["QualityBudgets.spec.luau"] = 8,
	["QuestService.spec.luau"] = 5,
	["RegionLogic.spec.luau"] = 6,
	["SectionTrees.spec.luau"] = 21,
	["ShopService.spec.luau"] = 10,
	["TerrainFit.spec.luau"] = 6,
	["TownMesh.spec.luau"] = 16,
	["TownTrees.spec.luau"] = 22,
	["TreeArtSections.spec.luau"] = 16,
	["TreeFill.spec.luau"] = 79,
	["TreeGen.spec.luau"] = 38,
	["TruckArt.spec.luau"] = 3,
	["WorldPlan.spec.luau"] = 69,
}

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for k in pairs(value) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in ipairs(keys) do
		table.insert(parts, string.format("%s = %s", tostring(k), show(value[k])))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local passed, failed = 0, 0
local failures = {}

local specs = {}
for _, file in ipairs(fs.readDir("tests")) do
	if string.match(file, "%.spec%.luau$") then
		table.insert(specs, file)
	end
end
table.sort(specs)

local shardSpec = process.env.TEST_SHARD
local inShard: { [string]: boolean }? = nil
if shardSpec and shardSpec ~= "" then
	local index, count = string.match(shardSpec, "^(%d+)/(%d+)$")
	local shardIndex, shardCount = tonumber(index), tonumber(count)
	if not shardIndex or not shardCount or shardCount < 1 or shardIndex < 1 or shardIndex > shardCount then
		print(string.format("TEST_SHARD must look like 2/4 (shard 1..N of N), got %q", shardSpec))
		process.exit(1)
	end
	local bySlowest = table.clone(specs)
	table.sort(bySlowest, function(a, b)
		local wa, wb = SLOW_SPECS[a] or 1, SLOW_SPECS[b] or 1
		if wa ~= wb then
			return wa > wb
		end
		return a < b
	end)
	local loads = table.create(shardCount, 0)
	local mine = {}
	for _, file in ipairs(bySlowest) do
		local best = 1
		for k = 2, shardCount do
			if loads[k] < loads[best] then
				best = k
			end
		end
		loads[best] += SLOW_SPECS[file] or 1
		if best == shardIndex then
			mine[file] = true
		end
	end
	inShard = mine
	print(string.format("Shard %d/%d", shardIndex, shardCount))
end

for _, file in ipairs(specs) do
	if filter and not string.find(file, filter, 1, true) then
		continue
	end
	if inShard and not inShard[file] then
		continue
	end
	local shared = Loader.new()
	local tests = {}
	local t = { roblox = roblox }
	function t.test(name: string, fn: () -> ())
		table.insert(tests, { name = name, fn = fn })
	end
	function t.eq(actual: any, expected: any, message: string?)
		if not deepEqual(actual, expected) then
			error(
				string.format(
					"%sexpected %s, got %s",
					if message then message .. ": " else "",
					show(expected),
					show(actual)
				),
				2
			)
		end
	end
	function t.ok(value: any, message: string?)
		if not value then
			error(message or "expected a truthy value", 2)
		end
	end
	function t.fails(fn: () -> (), pattern: string?)
		local ok, err = pcall(fn)
		if ok then
			error("expected an error", 2)
		end
		if pattern and not string.find(tostring(err), pattern) then
			error(string.format("error %q doesn't match %q", tostring(err), pattern), 2)
		end
	end
	function t.loader(options)
		return Loader.new(options)
	end
	function t.shared(name: string)
		return shared:shared(name)
	end
	function t.server(name: string)
		return shared:server(name)
	end
	function t.load(path: string)
		return shared:load(path)
	end

	local specStart = os.clock()
	local path = "tests/" .. file
	local ok, err = pcall(function()
		luau.load(fs.readFile(path), { debugName = path })()(t)
	end)
	if not ok then
		failed += 1
		table.insert(failures, string.format("%s (loading): %s", file, tostring(err)))
		continue
	end
	for _, case in ipairs(tests) do
		local caseStart = os.clock()
		local caseOk, caseErr = pcall(case.fn)
		if os.clock() - caseStart > 30 then
			print(string.format("  slow test (%.0fs): %s", os.clock() - caseStart, case.name))
		end
		if caseOk then
			passed += 1
		else
			failed += 1
			table.insert(failures, string.format("%s > %s: %s", file, case.name, tostring(caseErr)))
		end
	end
	print(string.format("%-28s %d tests  %.1fs", file, #tests, os.clock() - specStart))
end

for _, line in ipairs(failures) do
	print("FAIL " .. line)
end
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 or passed == 0 then
	process.exit(1)
end
