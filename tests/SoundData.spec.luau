--!nocheck
-- The river and the waterfall used to play a private upload. Studio
-- refused it ("experience doesn't have access permission") and printed a
-- red load error as soon as AmbientSound parented the sounds.
return function(t)
	local SoundData = t.loader({
		services = { SoundService = {}, Debris = { AddItem = function() end } },
	}):shared("SoundData")
	local PRIVATE = "rbxassetid://6564308795"

	t.test("river and waterfall are public sounds, not the private upload", function()
		-- Verified 3 Oct 2026 via economy.roblox.com asset details:
		-- 9118187543 "River Water 1 (SFX)", 9120549564 "Waterfall Background
		-- Water Roar 1 (SFX)", both Pro Sound Effects, IsPublicDomain true.
		-- Same flag as the music already in this file.
		local want = {
			River = "rbxassetid://9118187543",
			WaterfallRoar = "rbxassetid://9120549564",
		}
		for name, id in pairs(want) do
			local def = SoundData.Sounds[name]
			t.eq(def.id, id, name)
			t.ok(def.id ~= PRIVATE, name .. " is still the private upload")
			t.eq(def.looped, true, name .. " loops")
		end
	end)

	t.test("the procedural fell sound has a creak, a crack and a whoosh, then a thud, all positional", function()
		local FellSound = t.shared("FellSound")
		local start = FellSound.Start(40, 2)
		local names = {}
		for _, l in ipairs(start) do
			table.insert(names, l.name)
			t.ok(l.id:sub(1, 13) == "rbxasset://so", l.name .. " uses a built-in sound")
			t.ok(l.rolloff > 50, l.name .. " rolls off in 3D")
			t.ok(l.volume > 0 and l.volume <= 1 and l.speed > 0, l.name .. " sane")
		end
		t.eq(names, { "FellCreak", "FellCrack", "FellWhoosh" })
		t.ok(start[1].at < start[2].at and start[2].at < start[3].at, "creak, then crack, then whoosh")
		t.eq(start[3].maxSec, 2, "the whoosh lasts the fall")
		local land = FellSound.Land(40)
		t.eq(land[1].name, "FellThud")
		t.ok(land[1].reverb ~= nil, "the thud has a tail")
		t.ok(#land + #start <= FellSound.MaxLayers * 2)
	end)

	t.test("heavier trees sound lower and louder", function()
		local FellSound = t.shared("FellSound")
		local light, heavy = FellSound.Land(2), FellSound.Land(80)
		t.ok(heavy[1].speed < light[1].speed, "lower")
		t.ok(heavy[1].volume > light[1].volume, "louder")
		t.eq(FellSound.Weight(0 / 0), 0.5)
		t.eq(FellSound.Weight(1e9), 1)
	end)
end
