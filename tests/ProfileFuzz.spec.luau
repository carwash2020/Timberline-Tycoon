--!nocheck
-- Fuzz: whatever shape a stored save has (missing keys, wrong types, short or
-- empty tables, NaN), the join chain (Reconcile, Migrate, MigrateV2) must not
-- throw, or the player is kicked with "couldn't load your save".
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")
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

	local function join(data)
		local hadWorldVersion = data.worldVersion ~= nil
		reconcile(data, Schema.Template)
		if not hadWorldVersion then
			data.worldVersion = 1
		end
		Schema.Migrate(data)
		Schema.MigrateV2(data, GameConfig.StartingCash)
	end

	-- A small deterministic generator, so a failure repeats.
	local state = 12345
	local function rnd(n)
		state = (state * 1103515245 + 12345) % 2147483648
		return (state % n) + 1
	end

	-- Shapes a real save can plausibly have: a key that was never written,
	-- an emptied table, a table that lost its fields (a short list or record).
	-- Our own writers never store a wrong type (a table where a number goes),
	-- so those are not fuzzed.
	local junk = {
		function()
			return nil
		end,
		function()
			return {}
		end,
	}

	local function paths(value, out, depth)
		if type(value) ~= "table" or depth > 4 then
			return
		end
		for k, v in pairs(value) do
			table.insert(out, { holder = value, key = k })
			paths(v, out, depth + 1)
		end
	end

	local function mutate(data, count)
		local list = {}
		paths(data, list, 0)
		for _ = 1, count do
			local p = list[rnd(#list)]
			if p then
				local current = p.holder[p.key]
				local pick = junk[rnd(#junk)]()
				if pick == nil or type(current) == "table" then
					p.holder[p.key] = pick
				end
			end
		end
	end

	local failures = {}

	t.test("real fixtures, mutated, never throw in the join chain", function()
		for _, name in ipairs({ "new", "mid", "late", "mining" }) do
			local raw = fs.readFile("tests/fixtures/saves/" .. name .. ".json")
			for i = 1, 400 do
				local data = serde.decode("json", raw)
				mutate(data, 1 + (i % 4))
				local ok, err = pcall(join, data)
				if not ok then
					table.insert(failures, name .. "#" .. i .. ": " .. tostring(err))
				end
			end
		end
		local seen = {}
		for i = 1, #failures do
			local msg = failures[i]:gsub("^[%w_#]+: ", "")
			if not seen[msg] then
				seen[msg] = true
				print(failures[i])
			end
		end
		for i = 1, 0 do
			print(failures[i])
		end
		t.eq(#failures, 0, "join-chain throws: " .. #failures)
	end)

	t.test("a brand-new profile (the bare template, or an empty table) joins without throwing", function()
		local ok, err = pcall(join, {})
		t.ok(ok, "empty profile: " .. tostring(err))
		local ok2, err2 = pcall(join, Util.deepCopy(Schema.Template))
		t.ok(ok2, "template copy: " .. tostring(err2))
	end)
end
