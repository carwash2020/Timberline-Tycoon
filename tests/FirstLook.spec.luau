--!nocheck
-- What a new player sees first (phase-2/fix-world-first-look): every board
-- in the first screen's town carries its words (no blank dark board), and
-- a new server opens in the morning.
return function(t)
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local GameConfig = t.shared("GameConfig")
	local WorldTime = t.shared("WorldTime")

	local function labels(part)
		local out = {}
		for _, gui in ipairs(part:GetChildren()) do
			if gui:IsA("SurfaceGui") then
				for _, child in ipairs(gui:GetChildren()) do
					if child:IsA("TextLabel") then
						table.insert(out, child.Text)
					end
				end
			end
		end
		return out
	end

	t.test("every town signpost board has its text on both faces", function()
		for _, sign in ipairs(WorldPlan.Town().signs) do
			local model = BuildingArt.Signpost(sign.text, sign.lit)
			local board = model:FindFirstChild("Board", true)
			t.ok(board, "a board for " .. string.match(sign.text, "^[^\n]+"))
			local found = labels(board)
			t.eq(#found, 2, "front and back")
			for _, text in ipairs(found) do
				t.eq(text, sign.text)
			end
		end
	end)

	t.test("the sawmill's crest board (top centre of the spawn view) is not blank", function()
		local sawmill = BuildingArt.Sawmill()
		local crest = nil
		for _, d in ipairs(sawmill:GetDescendants()) do
			if d.Name == "Sign" and d:IsA("BasePart") then
				local found = labels(d)
				if found[1] == "TIMBERLINE SAWMILL" then
					crest = d
				end
			end
		end
		t.ok(crest, "the crest board says TIMBERLINE SAWMILL")
	end)

	t.test("a fresh server's first look is daylight, on the first world day's morning", function()
		t.ok(not WorldTime.IsNight(GameConfig.StartClockHour))
		t.ok(GameConfig.StartClockHour >= 6 and GameConfig.StartClockHour <= 10, "a morning")
		t.ok(
			GameConfig.StartClockHour > GameConfig.NightEndsAt and GameConfig.StartClockHour < GameConfig.NightStartsAt
		)
	end)
end
