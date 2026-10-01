--!nocheck
-- Murph's tutorial on the server: progress, rewards, skipping.
return function(t)
	local function setup(profileOverrides)
		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local profile = loader:shared("Util").deepCopy(Schema.Template)
		for k, v in pairs(profileOverrides or {}) do
			profile[k] = v
		end
		local player = {
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
		}
		local toasts, marks = {}, {}
		local trees = {} -- TreeService: QuestService sets its StumpHold hook
		local mocks = {
			TreeService = trees,
			ProfileService = {
				GetProfile = function(p)
					return if p == player then profile else nil
				end,
			},
			MilestoneService = {
				Mark = function(_, name)
					table.insert(marks, name)
				end,
			},
		}
		loader = t.loader({ mocks = mocks })
		local Quest = loader:server("QuestService")
		local skipHandler
		Quest.Init({
			OnServerEvent = {
				Connect = function(_, fn)
					skipHandler = fn
				end,
			},
		}, function(_, message)
			table.insert(toasts, message)
		end)
		return {
			Quest = Quest,
			Steps = loader:shared("TutorialData").Steps,
			profile = profile,
			player = player,
			toasts = toasts,
			marks = marks,
			trees = trees,
			skip = function()
				skipHandler(player)
			end,
			event = function(name, n)
				Quest.Event(player, name, n)
			end,
		}
	end

	-- Walks through the steps before `id`.
	local function playUntil(s, id)
		for _, step in ipairs(s.Steps) do
			if step.id == id then
				return
			end
			s.event(step.event, step.count)
		end
	end

	t.test("a new player starts at step 1, shown on attributes", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		t.eq(s.player.attrs.TutorialStep, 1)
		t.eq(s.player.attrs.TutorialProgress, 0)
	end)

	t.test("only the current step's event counts", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		s.event("logsSold", 6)
		t.eq(s.profile.tutorialStep, 1)
		s.event("treeFelled")
		t.eq(s.profile.tutorialStep, 2)
		t.eq(s.player.attrs.TutorialStep, 2)
	end)

	t.test("counted steps track progress, then pay their reward", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "loads")
		t.eq(s.Steps[s.profile.tutorialStep].id, "loads")
		local cashBefore = s.profile.cash
		s.event("logsSold", 6)
		t.eq(s.player.attrs.TutorialProgress, 6)
		t.eq(s.profile.cash, cashBefore, "no reward yet")
		s.event("logsSold", 14)
		t.eq(s.Steps[s.profile.tutorialStep].id, "steel")
		t.eq(s.profile.cash, cashBefore + 25)
		t.eq(s.toasts, { "Murph chipped in $25!" })
	end)

	t.test("buying the Steel Axe finishes it", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "steel")
		s.profile.bestAxeTier = 2
		s.event("axeBought")
		t.ok(s.profile.tutorialDone)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.marks, { "Finished the tutorial" })
		s.event("treeFelled") -- nothing happens after the end
		t.eq(s.player.attrs.TutorialStep, 0)
	end)

	t.test("buying the Steel Axe early skips that step when it comes up", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "loads")
		s.profile.bestAxeTier = 2 -- bought it with their own cash
		s.event("logsSold", 18)
		t.ok(s.profile.tutorialDone, "the last step was already done")
	end)

	t.test("progress survives a rejoin", function()
		local s = setup({ tutorialStep = 5, tutorialProgress = 7 })
		s.Quest.Start(s.player, s.profile)
		t.eq(s.player.attrs.TutorialStep, 5)
		t.eq(s.player.attrs.TutorialProgress, 7)
	end)

	t.test("old saves with a better axe skip it; mid-tutorial players don't", function()
		local old = setup({ bestAxeTier = 3 })
		old.Quest.Start(old.player, old.profile)
		t.ok(old.profile.tutorialDone)
		t.eq(old.marks, {}, "bypassing isn't finishing")
		local mid = setup({ bestAxeTier = 2, tutorialStep = 5, tutorialProgress = 3 })
		mid.Quest.Start(mid.player, mid.profile)
		t.ok(not mid.profile.tutorialDone)
	end)

	t.test("Skip ends it without rewards; a finished tutorial stays finished", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		s.skip()
		t.ok(s.profile.tutorialDone)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.profile.cash, 0)
		local again = setup({ tutorialDone = true })
		again.Quest.Start(again.player, again.profile)
		t.eq(again.player.attrs.TutorialStep, 0)
	end)

	t.test("the Heartseed beat: planting a seed in a stump moves it on", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "plant")
		t.eq(s.Steps[s.profile.tutorialStep].id, "plant")
		t.eq(s.Steps[s.profile.tutorialStep - 1].id, "sell", "right after the first sale")
		s.event("logsSold", 5)
		s.event("treeFelled")
		t.eq(s.Steps[s.profile.tutorialStep].id, "plant", "only planting counts")
		s.event("seedPlanted")
		t.eq(s.Steps[s.profile.tutorialStep].id, "loads")
		t.eq(s.player.attrs.TutorialProgress, 0)
	end)

	t.test("saves from before the Heartseed beat keep their place", function()
		-- Steps those saves reached, logged by the funnel.
		local reached = {}
		for _, id in ipairs({ "fell", "pickup", "load", "sell", "loads" }) do
			reached["Tutorial:" .. id] = true
		end
		-- On "loads" (then step 5, now 6), 7 logs in.
		local mid = setup({ tutorialStep = 5, tutorialProgress = 7, onboarding = table.clone(reached) })
		mid.Quest.Start(mid.player, mid.profile)
		t.eq(mid.Steps[mid.profile.tutorialStep].id, "loads")
		t.eq(mid.player.attrs.TutorialProgress, 7, "progress kept")
		-- On "steel" (then 6, now 7).
		local late = table.clone(reached)
		late["Tutorial:steel"] = true
		local s = setup({ tutorialStep = 6, tutorialProgress = 0, onboarding = late })
		s.Quest.Start(s.player, s.profile)
		t.eq(s.Steps[s.profile.tutorialStep].id, "steel")
		-- Just sold for the first time: planting is next, as for everyone.
		local early = {}
		for _, id in ipairs({ "fell", "pickup", "load", "sell" }) do
			early["Tutorial:" .. id] = true
		end
		local e = setup({ tutorialStep = 4, tutorialProgress = 0, onboarding = early })
		e.Quest.Start(e.player, e.profile)
		e.event("logsSold", 3)
		t.eq(e.Steps[e.profile.tutorialStep].id, "plant")
	end)

	t.test("stumps a player fells wait for the plant step, and only until then", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		t.eq(s.trees.StumpHold, s.Quest.StumpHoldFor, "Init hands TreeService the hook")
		local held = {}
		for _, step in ipairs(s.Steps) do
			held[step.id] = s.trees.StumpHold(s.player)
			s.event(step.event, step.count)
		end
		for _, id in ipairs({ "fell", "pickup", "load", "sell", "plant" }) do
			t.eq(held[id], 240, id .. ": up to the plant step the stump waits 4 minutes")
		end
		t.eq(held.loads, 0, "planted: trees regrow as usual")
		t.eq(held.steel, 0)
		t.ok(s.profile.tutorialDone)
		t.eq(s.trees.StumpHold(s.player), 0, "finished")
		t.eq(s.trees.StumpHold({}), 0, "no profile (left)")
	end)

	t.test("a skipped tutorial holds no stumps", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		t.eq(s.Quest.StumpHoldFor(s.player), 240)
		s.skip()
		t.eq(s.Quest.StumpHoldFor(s.player), 0)
	end)

	t.test("a broken step index restarts cleanly", function()
		local s = setup({ tutorialStep = 99 })
		s.Quest.Start(s.player, s.profile)
		t.eq(s.player.attrs.TutorialStep, 1)
	end)
end
