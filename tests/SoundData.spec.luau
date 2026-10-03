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
end
