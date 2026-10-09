--!strict
-- LoadingTips: 12 or more short lines, shuffled, no repeat until the list cycles.
return function(t)
	local Tips = t.load("ReplicatedFirst/LoadingTips")

	local EXAMPLES = {
		"Planks sell for more than logs.",
		"Rook at the main sawmill hands out 3 daily jobs.",
		"Bombs clear cave rubble to deeper, richer ore.",
		"Wear the Insulated Coat before heading into the snow.",
		"Back your truck up to the furnace to sell a whole load.",
		"Hover over an ore rock to see what's inside.",
	}

	t.test("twelve or more short lines, with the early-path examples", function()
		t.ok(#Tips.Lines >= 12, "count " .. #Tips.Lines)
		local have = {}
		for _, line in ipairs(Tips.Lines) do
			t.ok(#line <= Tips.MaxLength, "over " .. Tips.MaxLength .. ": " .. line)
			t.ok(not string.find(line, "$", 1, true), "no price: " .. line)
			t.ok(not string.find(string.lower(line), "robux", 1, true), "no Robux: " .. line)
			t.eq(have[line], nil, "listed twice: " .. line)
			have[line] = true
		end
		for _, line in ipairs(EXAMPLES) do
			t.ok(have[line], "missing: " .. line)
		end
		local all = string.lower(table.concat(Tips.Lines, " "))
		for _, word in ipairs({ "tree", "truck", "sell", "figured" }) do
			t.ok(string.find(all, word, 1, true), "a line mentions " .. word)
		end
	end)

	t.test("one cycle shows every line once, then a new shuffle starts", function()
		local n = #Tips.Lines
		local rolls = {}
		local rng = function(limit: number): number
			table.insert(rolls, limit)
			return 1
		end
		local cycle = Tips.Begin(rng)
		local seen: { [string]: boolean } = {}
		for slot = 0, n - 1 do
			local line = Tips.LineAt(cycle, slot)
			t.eq(seen[line], nil, "repeat inside the cycle: " .. line)
			seen[line] = true
		end
		local count = 0
		for _ in seen do
			count += 1
		end
		t.eq(count, n)
		local before = #rolls
		Tips.LineAt(cycle, n) -- the next cycle reshuffles
		t.ok(#rolls > before, "a new cycle shuffles again")
		local wild = Tips.Begin(function(_limit: number): number
			return 1000
		end)
		local again: { [string]: boolean } = {}
		for slot = 0, n - 1 do
			again[Tips.LineAt(wild, slot)] = true
		end
		local wildCount = 0
		for _ in again do
			wildCount += 1
		end
		t.eq(wildCount, n, "a wild roll is clamped and still covers the list")
	end)
end
