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

	t.test("Buy plays on a completed purchase notice, never on a refusal", function()
		t.eq(SoundData.ForNotice("Bought the Steel Axe! It's in your hotbar."), "Buy")
		t.eq(SoundData.ForNotice("Bought the Rustbucket! The Rustbucket can't tow, so hitch it here."), "Buy")
		t.eq(SoundData.ForNotice("You need $40 more for the Steel Axe."), nil, "can't afford")
		t.eq(SoundData.ForNotice("You already own the Rustbucket."), nil)
		t.eq(SoundData.ForNotice("Sold 3 logs for $120."), nil)
		t.eq(SoundData.ForNotice(nil), nil)
		t.ok(SoundData.Sounds.Buy.id ~= "", "Buy has a real id, so it is audible")
		t.ok(SoundData.Sounds.Equip.id ~= "", "Equip has a real id")
	end)

	t.test("Equip plays for a tool in hand, not a spawn's own; the tutorial ticks only on advancing", function()
		t.eq(SoundData.EquipPlays(true, 10), true)
		t.eq(SoundData.EquipPlays(true, 0.1), false, "a respawn equip is quiet")
		t.eq(SoundData.EquipPlays(false, 10), false, "not a tool")
		t.eq(SoundData.StepTick(-1, 1), nil, "first sight of the tutorial at join")
		t.eq(SoundData.StepTick(1, 2), "UIClick")
		t.eq(SoundData.StepTick(3, 4), "UIClick")
		t.eq(SoundData.StepTick(3, 3), nil)
		t.eq(SoundData.StepTick(8, 0), nil, "the end has its own joy beat")
		t.eq(SoundData.StepTick(0, 1), nil, "a replay starting")
		t.ok(SoundData.Sounds.UIClick.id ~= "", "the tick has an id")
	end)

	t.test("Buy, Equip and the tick play through SoundData.Play, which honours the sound settings", function()
		local fs = require("@lune/fs")
		local hud = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HUD.luau")
		t.ok(string.find(hud, "SoundData.ForNotice(message)", 1, true))
		local axe = fs.readFile("src/StarterPlayer/StarterPlayerScripts/AxeController.luau")
		t.ok(string.find(axe, 'SoundData.Play("Equip")', 1, true))
		local quest = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		t.ok(string.find(quest, "SoundData.StepTick(lastStep, index)", 1, true))
		local sound = fs.readFile("src/ReplicatedStorage/Shared/SoundData.luau")
		t.ok(string.find(sound, "SoundData.SfxEnabled", 1, true) and string.find(sound, "SoundData.SfxVolume", 1, true))
	end)
	t.test("PlayAt takes an optional pitch that multiplies the sound's playback speed", function()
		-- PlayAt parents its sound under workspace.Terrain, which a headless run does
		-- not have, so the rule is read from the source: a trailing, optional
		-- `pitch` that is multiplied into PlaybackSpeed (callers without it unchanged).
		local src = require("@lune/fs").readFile("src/ReplicatedStorage/Shared/SoundData.luau")
		t.ok(string.find(src, "function SoundData.PlayAt(name: string, position: Vector3, pitch: number?)", 1, true))
		t.ok(string.find(src, "s.PlaybackSpeed *= pitch", 1, true))
		t.ok(SoundData.Sounds.TreeCreak ~= nil, "the creak has an entry")
		t.eq(SoundData.Sounds.TreeCreak.id, "rbxassetid://140235385729394", "the creak is the uploaded original sound")
	end)
	t.test("every sound has a non-empty id, rbxasset or rbxassetid", function()
		for key, def in pairs(SoundData.Sounds) do
			t.ok(def.id ~= "", key .. " has an id")
			t.ok(
				string.sub(def.id, 1, 11) == "rbxasset://" or string.sub(def.id, 1, 13) == "rbxassetid://",
				key .. " id is a rbxasset or rbxassetid"
			)
		end
	end)

	t.test("the original sounds are exactly the uploaded ids, loops where they are loops", function()
		local want = {
			TreeCreak = { "rbxassetid://140235385729394", false },
			LogThud = { "rbxassetid://71299239323730", false },
			Engine = { "rbxassetid://79105838138081", true },
			CricketsNight = { "rbxassetid://98495708270834", true },
			WindHowl = { "rbxassetid://135011285595785", true },
			LavaRumble = { "rbxassetid://126238204708501", true },
			Wings = { "rbxassetid://133814424706029", false },
			Quack = { "rbxassetid://87844016813752", false },
			StormCrackle = { "rbxassetid://88410345542803", false },
		}
		for key, row in pairs(want) do
			t.eq(SoundData.Sounds[key].id, row[1], key)
			t.eq(SoundData.Sounds[key].looped == true, row[2], key .. " looped")
		end
		t.ok(SoundData.Sounds.LogThud.speed ~= nil and SoundData.Sounds.LogThud.rolloff == 80)
		t.ok(SoundData.Sounds.TreeCreak.id ~= "rbxassetid://124981481503824", "never the older TreeFall upload")
	end)

	t.test("an uploaded fall sound plays the whole fall at the start and nothing at the landing", function()
		t.eq(SoundData.FellStageSound("start", true), "TreeFall")
		t.eq(SoundData.FellStageSound("land", true), nil)
		t.eq(SoundData.FellStageSound("start", false), nil, "the procedural layers play when nothing is uploaded")
		t.eq(SoundData.FellStageSound("land", false), nil)
	end)
end
