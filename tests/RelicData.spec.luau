--!nocheck
-- The four relics: figured wood of their biome plus Sky Shards; they pay
-- $22.5k, $37.5k, $60k, $90k once.
return function(t)
	local R = t.shared("RelicData")

	t.test("four relics, the Designer's pay, the sockets BuildingArt names", function()
		local ids, pays = {}, {}
		for _, r in ipairs(R.List) do
			table.insert(ids, r.id)
			pays[r.id] = r.pays
			t.ok(r.shards > 0, r.id .. " takes shards")
			t.ok(string.match(r.color, "^#%x%x%x%x%x%x$") ~= nil, r.id .. " colour")
		end
		t.eq(table.concat(ids, ","), "FrostRelic,EmberRelic,GloamRelic,LumenRelic")
		t.eq(pays.FrostRelic, 22500)
		t.eq(pays.EmberRelic, 37500)
		t.eq(pays.GloamRelic, 60000)
		t.eq(pays.LumenRelic, 90000)
		t.eq(R.Get("GloamRelic").woodId, "phantomwood")
		t.eq(R.Get("Nope"), nil)
	end)

	t.test("refusals: owned, no figured piece, too few shards; nil when it can be forged", function()
		local frost = R.Get("FrostRelic")
		t.ok(R.Refusal(frost, { FrostRelic = true }, 99, 9) ~= nil, "once only")
		t.ok(string.find(R.Refusal(frost, {}, 99, 0), "figured", 1, true) ~= nil)
		t.eq(R.Refusal(frost, {}, 1, 1), "3 more Sky Shards needed.")
		t.eq(R.Refusal(frost, {}, 4, 1), nil)
		t.eq(R.CostText(frost), "Figured Frostwood + 4 Sky Shards")
	end)
	t.test("plot trophies: one stand and gem per relic, beside the post, colliding with nothing", function()
		local CFrame = t.roblox.CFrame
		local post = CFrame.new(50, 3, 80)
		t.eq(R.Trophies({}, post, 6), nil, "none forged, nothing built")
		local model = R.Trophies({ "FrostRelic", "Nope", "LumenRelic" }, post, 6)
		local gems, stands = 0, 0
		for _, p in ipairs(model:GetChildren()) do
			t.eq(p.CanCollide, false, p.Name)
			t.eq(p.Anchored, true, p.Name)
			if p.Material == t.roblox.Enum.Material.Neon then
				gems += 1
			else
				stands += 1
			end
		end
		t.eq(gems, 2)
		t.eq(stands, 2)
		local a, b = R.TrophySpot(post, 6, 1), R.TrophySpot(post, 6, 2)
		t.ok(math.abs(a.Position.Y - 0) < 1e-6, "on the post's foot")
		t.ok(math.abs((b.Position - a.Position).Magnitude - 2.6) < 1e-4, "2.6 apart")
		t.ok((a.Position - post.Position).Magnitude > 2, "beside the post, not in it")
	end)
end
