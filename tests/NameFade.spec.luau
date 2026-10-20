--!nocheck
-- T388: an NPC's nameplate never sits on its Talk card. While a card shows on
-- a head, that head's NameTag fades out (0.15 s) and comes back when the card
-- goes. Rules are in Shared/NameFade, so nothing here depends on a clock:
-- the fade is stepped with whole `dt` numbers.
return function(t)
	local NameFade = t.shared("NameFade")
	local NPCData = t.shared("NPCData")
	local NPCDialogue = t.shared("NPCDialogue")
	local SettingsLogic = t.shared("SettingsLogic")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")

	local function loadPromptUI()
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
				},
				Players = { LocalPlayer = {} },
				TextChatService = {},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
				ProximityPromptService = {},
				TweenService = {},
				CollectionService = {},
				RunService = {},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/PromptUI")
	end

	local VIEW_H = 1080
	local SCALES = { "small", "normal", "large" }
	local WIDTH, HEIGHT = 360, 72 -- PromptUI's card billboard
	local LIFT = 1.55 -- PromptUI.HeadLift

	t.test("every NPC: showing its Talk card hides its NameTag, hiding brings it back within 0.5 s", function()
		for _, npc in ipairs(NPCData.All()) do
			local PromptUI = loadPromptUI()
			local head = CharacterArt.Build(npc.look).Head
			local tag = head:FindFirstChild("NameTag")
			local name, role = tag:FindFirstChild("Name"), tag:FindFirstChild("Role")
			local shown = name.TextTransparency
			local strokeShown = name.TextStrokeTransparency
			PromptUI.HideTag(head)
			PromptUI.FadeStep(NameFade.Duration)
			t.eq(name.TextTransparency, 1, npc.id .. " name hidden")
			t.eq(name.TextStrokeTransparency, 1, npc.id .. " stroke hidden")
			if role then
				t.eq(role.TextTransparency, 1, npc.id .. " role hidden")
			end
			PromptUI.FadeStep(5)
			t.eq(name.TextTransparency, 1, npc.id .. " stays hidden while the card shows")
			PromptUI.ShowTag(head)
			local spent = 0
			while spent < 0.5 and PromptUI.TagTransparency(head) > 0 do
				PromptUI.FadeStep(0.05)
				spent += 0.05
			end
			t.ok(spent <= 0.5 + 1e-9, npc.id .. " name back within 0.5 s: " .. spent)
			t.eq(name.TextTransparency, shown, npc.id .. " name text restored")
			t.eq(name.TextStrokeTransparency, strokeShown, npc.id .. " stroke restored")
			t.eq(PromptUI.TagTransparency(head), 0)
		end
	end)

	t.test("the fade lasts 0.15 s each way and never stays hidden", function()
		local s = NameFade.new()
		local head = {}
		NameFade.Show(s, head)
		NameFade.Step(s, 0.075)
		t.ok(math.abs(NameFade.Transparency(s, head) - 0.5) < 1e-9)
		NameFade.Step(s, 0.075)
		t.eq(NameFade.Transparency(s, head), 1)
		NameFade.Hide(s, head)
		t.ok(math.abs(NameFade.BackWithin(s, head) - 0.15) < 1e-9)
		NameFade.Step(s, 0.15)
		t.eq(NameFade.Transparency(s, head), 0)
		t.eq(next(s.alpha), nil, "forgotten once fully back")
		t.eq(NameFade.Hide(s, head), 0, "a hide with no show stays at zero")
		NameFade.Show(s, head)
		t.eq(NameFade.Count(s, head), 1, "and the next show counts one")
	end)

	t.test("two cards on one head: the name returns only when both are gone", function()
		local PromptUI = loadPromptUI()
		local head = CharacterArt.Build(NPCData.All()[1].look).Head
		PromptUI.HideTag(head)
		PromptUI.HideTag(head)
		PromptUI.FadeStep(1)
		PromptUI.ShowTag(head)
		PromptUI.FadeStep(1)
		t.eq(PromptUI.TagTransparency(head), 1, "one card still showing")
		PromptUI.ShowTag(head)
		PromptUI.FadeStep(1)
		t.eq(PromptUI.TagTransparency(head), 0)
	end)

	t.test("nameplate and card rectangles never overlap at the prompt's reach, half of it and 3 studs", function()
		local PromptUI = loadPromptUI()
		local layout = NPCDialogue.LayoutFor(false, false)
		local overlapWithoutFade = 0
		for _, npc in ipairs(NPCData.All()) do
			local tag = CharacterArt.Build(npc.look).Head:FindFirstChild("NameTag")
			for _, scale in ipairs(SCALES) do
				local mult = SettingsLogic.ScaleMultiplier(scale)
				for _, k in ipairs({ 1, PromptUI.Grow(true, 1.5) }) do
					for _, distance in ipairs({ NPCData.TalkDistance, NPCData.TalkDistance / 2, 3 }) do
						local spp = NameFade.StudsPerPixel(distance, VIEW_H)
						local tagRect = NameFade.TagRect(
							{ x = layout.tagSize.X * mult, y = layout.tagSize.Y * mult },
							tag.StudsOffset.Y,
							spp
						)
						local card = NameFade.CardRect({ x = WIDTH * k, y = HEIGHT * k }, LIFT, spp)
						if NameFade.Overlap(tagRect, card) then
							overlapWithoutFade += 1
						end
						-- the card shows, the name has faded out
						t.ok(
							not NameFade.Overlap(NameFade.Visible(tagRect, 1), card),
							string.format("%s at %.1f studs, %s, card x%.1f", npc.id, distance, scale, k)
						)
						-- the card is gone, the name is back: no card to meet
						t.ok(NameFade.Visible(tagRect, 0) == tagRect)
					end
				end
			end
		end
		t.ok(overlapWithoutFade > 0, "the two do collide without the fade (that is the bug)")
	end)

	t.test("the name keeps its size and stays above the T386 text floors", function()
		local tag = CharacterArt.Build(NPCData.All()[1].look).Head:FindFirstChild("NameTag")
		t.eq(tag.Size.X.Offset, 220)
		t.eq(tag.Size.Y.Offset, 50)
		t.ok(tag:FindFirstChild("Name").TextSize >= SettingsLogic.TextFloorTitle)
		t.ok(tag:FindFirstChild("Role").TextSize >= SettingsLogic.TextFloorBody)
	end)

	t.test("two NPCs 4 studs apart: one prompt, one lost tag, nobody's name under the other's card", function()
		local list = NPCData.All()
		local card = { x = WIDTH, y = HEIGHT }
		for i = 1, #list - 1 do
			local a = CharacterArt.Build(list[i].look).Head
			local b = CharacterArt.Build(list[i + 1].look).Head
			local PromptUI = loadPromptUI()
			-- The player is nearer `a`: the engine shows one Talk card (OnePerButton, nearest wins).
			PromptUI.HideTag(a)
			PromptUI.FadeStep(1)
			t.eq(PromptUI.TagTransparency(a), 1, list[i].id .. " loses its tag")
			t.eq(PromptUI.TagTransparency(b), 0, list[i + 1].id .. " keeps its tag")
			for _, distance in ipairs({ 12, 6, 3 }) do
				local spp = NameFade.StudsPerPixel(distance, VIEW_H)
				local tag = b:FindFirstChild("NameTag")
				local size = { x = tag.Size.X.Offset, y = tag.Size.Y.Offset }
				-- The neighbour's name fades too if the card would cover it.
				local covered = NameFade.Covered(size, tag.StudsOffset.Y, card, LIFT, spp, 4, 0)
				local drawn = NameFade.Visible(NameFade.TagRect(size, tag.StudsOffset.Y, spp, 4, 0), covered and 1 or 0)
				t.ok(
					not NameFade.Overlap(drawn, NameFade.CardRect(card, LIFT, spp)),
					string.format("%s beside %s at %d studs", list[i + 1].id, list[i].id, distance)
				)
			end
		end
		-- Seen from far, a name 4 studs off lies under the card (so it fades); close up it does not.
		local size = { x = 220, y = 50 }
		local function coveredAt(distance)
			return NameFade.Covered(size, 1.9, card, LIFT, NameFade.StudsPerPixel(distance, VIEW_H), 4, 0)
		end
		t.ok(coveredAt(12), "far: the neighbour's name would sit under the card")
		t.ok(not coveredAt(3), "close: well clear")
	end)

	t.test("a Talk card on an NPC still adorns the head at HeadLift studs", function()
		local PromptUI = loadPromptUI()
		local model = CharacterArt.Build(NPCData.All()[1].look)
		local adornee, studs = PromptUI.Adornee(model)
		t.ok(adornee == model.Head)
		t.ok(math.abs(studs.Y - PromptUI.HeadLift) < 1e-4)
		t.eq(PromptUI.HeadLift, LIFT)
	end)
end
