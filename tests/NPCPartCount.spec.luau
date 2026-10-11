--!nocheck
-- Part-built NPC budget. The brief wants under 60; today they run 55 to 88
-- (Murph 88, Millie 83, Rosa 77, Old Hank 77, Foreman 76, Cap'n Moss 72). This
-- pins a ceiling so nobody adds to it; the trim to 60 is an art pass that
-- needs Studio eyes (see the PR body).
return function(t)
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local NPCData = t.shared("NPCData")

	t.test("each townsperson stays inside the part ceiling (90 today, 60 is the goal)", function()
		local worst, who = 0, ""
		for _, npc in ipairs(NPCData.All()) do
			local model = CharacterArt.Build(npc.look)
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			if n > worst then
				worst, who = n, npc.id
			end
			t.ok(n <= 90, string.format("%s has %d parts", npc.id, n))
		end
		t.ok(worst > 0, who)
	end)
end
