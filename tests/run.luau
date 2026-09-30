--!nocheck
-- Test runner. From the repo root:   lune run tests/run
-- Optional filter:                   lune run tests/run Shop
--
-- Runs every tests/*.spec.luau. A spec file returns a function that gets a
-- `t` with:
--   t.test(name, fn)        a test; it fails if fn errors
--   t.eq(actual, expected)  equal (deep for tables)
--   t.ok(value, message?)   truthy
--   t.fails(fn, pattern?)   fn must error (optionally matching pattern)
--   t.loader(options?)      a fresh module Loader (see tests/loader.luau)
--   t.shared(name), t.server(name)  load a module with a shared Loader
--   t.roblox                @lune/roblox (Enum, Vector3, ...)
-- Exits non-zero if anything fails, so CI can gate on it.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tests/run")

local Loader = luau.load(fs.readFile("tests/loader.luau"), { debugName = "tests/loader.luau" })()

local filter = process.args[1]

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

for _, file in ipairs(specs) do
	if filter and not string.find(file, filter, 1, true) then
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
		local caseOk, caseErr = pcall(case.fn)
		if caseOk then
			passed += 1
		else
			failed += 1
			table.insert(failures, string.format("%s > %s: %s", file, case.name, tostring(caseErr)))
		end
	end
	print(string.format("%-28s %d tests", file, #tests))
end

for _, line in ipairs(failures) do
	print("FAIL " .. line)
end
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 or passed == 0 then
	process.exit(1)
end
