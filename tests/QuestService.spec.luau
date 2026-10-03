--!nocheck
-- Murph's tutorial on the server: progress, rewards, skipping.
return function(t)
	-- `loop`: the core loop GameServer passes to Init (nil: v1, as before).
	local function setup(profileOverrides, loop)
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
		end, loop)
		return {
			Quest = Quest,
			Steps = loader:shared("TutorialData").ForLoop(loop or 1),
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
		s.event("logsSold", 5)
		t.eq(s.player.attrs.TutorialProgress, 5)
		t.eq(s.profile.cash, cashBefore, "no reward yet")
		s.event("logsSold", 1)
		t.eq(s.Steps[s.profile.tutorialStep].id, "loads2")
		t.eq(s.profile.cash, cashBefore + 8)
		s.event("logsSold", 6)
		t.eq(s.Steps[s.profile.tutorialStep].id, "loads3")
		s.event("logsSold", 6)
		t.eq(s.Steps[s.profile.tutorialStep].id, "steel")
		t.eq(s.profile.cash, cashBefore + 25)
		t.eq(s.toasts, { "Murph chipped in $8!", "Murph chipped in $8!", "Murph chipped in $9!" })
	end)

	t.test("claiming a plot finishes it, after the Steel Axe", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "steel")
		s.profile.bestAxeTier = 2
		s.event("axeBought")
		t.eq(s.Steps[s.profile.tutorialStep].id, "plot")
		t.ok(not s.profile.tutorialDone)
		s.event("plotClaimed")
		t.ok(s.profile.tutorialDone)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.marks, { "Finished the tutorial", "Saw a next goal" })
		t.ok(type(s.player.attrs.NextGoal) == "string" and #s.player.attrs.NextGoal > 0)
		s.event("treeFelled") -- nothing happens after the end
		t.eq(s.player.attrs.TutorialStep, 0)
	end)

	t.test("buying the Steel Axe early skips that step when it comes up", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "loads")
		s.profile.bestAxeTier = 2 -- bought it with their own cash
		s.event("logsSold", 6)
		s.event("logsSold", 6)
		s.event("logsSold", 6)
		t.eq(s.Steps[s.profile.tutorialStep].id, "plot", "the axe step was already done")
		t.ok(not s.profile.tutorialDone, "the plot is still ahead")
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
		t.eq(old.marks, { "Saw a next goal" }, "bypassing isn't finishing, and one goal still shows")
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
		t.eq(s.Steps[s.profile.tutorialStep - 1].id, "mill", "right after the haul to the mill")
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
		t.eq(e.Steps[e.profile.tutorialStep].id, "load", "the truck lesson is later than the cart")
		e.event("logsSold", 3)
		t.eq(e.Steps[e.profile.tutorialStep].id, "load", "a sale doesn't load the truck")
		e.event("logsLoaded", 1)
		t.eq(e.Steps[e.profile.tutorialStep].id, "mill")
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

	---------------------------------------------------------------------------
	-- The v2 loop (V2_PLAN.md §13): Init with loop 2 runs StepsV2 on the v2
	-- events, as GameServer wires them: woodGrabbed from the grab hook, the
	-- sale through QuestService.WoodSold (pieces, then whole dollars).
	---------------------------------------------------------------------------

	t.test("v2: Init with loop 2 runs StepsV2; without a loop it's v1's steps", function()
		local TutorialData = t.shared("TutorialData")
		local v2 = setup(nil, 2)
		t.eq(v2.Steps, TutorialData.StepsV2)
		v2.Quest.Start(v2.player, v2.profile)
		t.eq(v2.player.attrs.TutorialStep, 1)
		t.eq(v2.Steps[1].event, "treeFelled")
		t.eq(v2.Steps[2].event, "woodGrabbed")
		local v1 = setup()
		t.eq(v1.Steps, TutorialData.Steps)
	end)

	t.test("v2: the walk on the wired events: fell, grab, load, sold, plant, sold cash, buy", function()
		local s = setup(nil, 2)
		local function at()
			return s.Steps[s.profile.tutorialStep].id
		end
		s.Quest.Start(s.player, s.profile)
		s.event("treeFelled") -- the chop path (SectionTrees' OnFelled from M1.3)
		t.eq(at(), "pickup")
		s.event("logPickedUp")
		t.eq(at(), "pickup", "v1's pickup counts for nothing under v2")
		s.event("woodGrabbed") -- GrabService.Hooks.onGrab
		t.eq(at(), "sell")
		s.event("woodLoaded")
		t.eq(at(), "sell", "a load doesn't sell the cart")
		local cash = s.profile.cash
		s.Quest.WoodSold(s.player, 2, 30)
		t.eq(at(), "load", "the first sale moves the cart step on")
		t.eq(s.player.attrs.TutorialProgress, 0, "and its cash doesn't count toward the truck")
		s.event("woodLoaded") -- TruckLoad (M1.6)
		t.eq(at(), "mill")
		s.Quest.WoodSold(s.player, 2, 30)
		t.eq(at(), "plant", "the mill sale, and its cash waits")
		s.event("seedPlanted")
		t.eq(at(), "loads")
		local loads = s.Steps[s.profile.tutorialStep]
		t.eq(loads.unit, "cash")
		local partial = loads.count - 30
		s.Quest.WoodSold(s.player, 3, partial)
		t.eq(s.player.attrs.TutorialProgress, partial, "dollars, not pieces")
		t.eq(s.profile.cash, cash, "no reward yet")
		s.Quest.WoodSold(s.player, 1, 30.7)
		t.eq(at(), "loads2", string.format("%d + 30 whole dollars passes $%d", partial, loads.count))
		t.eq(s.profile.cash, cash + loads.rewardCash)
		t.eq(s.toasts, { string.format("Murph chipped in $%d!", loads.rewardCash) })
		s.Quest.WoodSold(s.player, 1, s.Steps[s.profile.tutorialStep].count)
		s.Quest.WoodSold(s.player, 1, s.Steps[s.profile.tutorialStep].count)
		t.eq(at(), "steel")
		s.profile.bestAxeTier = 2
		s.event("axeBought")
		t.eq(at(), "plot")
		s.event("plotClaimed")
		t.ok(s.profile.tutorialDone)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.marks, { "Finished the tutorial", "Saw a next goal" })
	end)

	t.test("v2: a sale's junk numbers count for nothing; a sale the wallet cap ate counts its pieces", function()
		local s = setup(nil, 2)
		s.Quest.Start(s.player, s.profile)
		for _, event in ipairs({ "treeFelled", "woodGrabbed", "woodLoaded" }) do
			s.event(event)
		end
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
		s.Quest.WoodSold(s.player, 0, 30)
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell", "no pieces")
		s.Quest.WoodSold(s.player, 1, 0)
		t.eq(s.Steps[s.profile.tutorialStep].id, "load", "nothing credited (a full wallet): still a sale")
		s.event("woodLoaded")
		s.Quest.WoodSold(s.player, 1, 0)
		t.eq(s.Steps[s.profile.tutorialStep].id, "plant")
		s.event("seedPlanted")
		for _, junk in ipairs({ 0, -5, 0 / 0, math.huge, 0.6 }) do
			s.Quest.WoodSold(s.player, 1, junk)
		end
		t.eq(s.profile.tutorialProgress, 0, "no whole dollars")
		t.eq(s.player.attrs.TutorialProgress, 0)
	end)

	t.test("v1 is untouched: the v2 events count for nothing under loop 1", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		s.event("treeFelled")
		t.eq(s.Steps[s.profile.tutorialStep].id, "pickup")
		s.event("woodGrabbed")
		s.Quest.WoodSold(s.player, 3, 90)
		t.eq(s.Steps[s.profile.tutorialStep].id, "pickup")
		t.eq(s.profile.tutorialProgress, 0)
		s.event("logPickedUp")
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
	end)

	t.test("v2: stumps wait for the plant step the same way", function()
		local s = setup(nil, 2)
		s.Quest.Start(s.player, s.profile)
		local held = {}
		for _, step in ipairs(s.Steps) do
			held[step.id] = s.trees.StumpHold(s.player)
			s.event(step.event, step.count)
		end
		t.eq(held.fell, 240)
		t.eq(held.plant, 240)
		t.eq(held.loads, 0)
		t.ok(s.profile.tutorialDone)
	end)

	-- A returning player (MigrateV2 reopened their finished tutorial).
	t.test("v2 refresher: a returning veteran walks fell, grab, load, sell, then it's done", function()
		local TutorialData = t.shared("TutorialData")
		local onboarding = {}
		for _, step in ipairs(TutorialData.StepsV2) do
			onboarding["Tutorial:" .. step.id] = true -- they reached every step in v1
		end
		local s = setup({
			tutorialDone = false,
			tutorialStep = 1,
			tutorialProgress = 0,
			tutorialRefresher = true,
			bestAxeTier = 5,
			onboarding = onboarding,
		}, 2)
		s.Quest.Start(s.player, s.profile)
		t.ok(not s.profile.tutorialDone, "no bypass for a better axe, no realign from the v1 funnel")
		t.eq(s.player.attrs.TutorialStep, 1)
		t.eq(s.player.attrs.TutorialRefresher, true)
		s.event("treeFelled")
		s.event("woodGrabbed")
		s.event("woodLoaded")
		t.eq(s.profile.tutorialStep, TutorialData.RefresherLast)
		local cash = s.profile.cash
		s.Quest.WoodSold(s.player, 2, 30)
		t.ok(s.profile.tutorialDone, "done after the first sale")
		t.eq(s.profile.tutorialRefresher, false)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.player.attrs.TutorialRefresher, nil)
		t.eq(s.profile.cash, cash, "no rewards on the refresher")
	end)

	t.test("v2 refresher: Skip ends it; a rejoin mid-way carries on; under v1 it's the normal tutorial", function()
		local s = setup({ tutorialRefresher = true, bestAxeTier = 4 }, 2)
		s.Quest.Start(s.player, s.profile)
		s.event("treeFelled")
		t.eq(s.profile.tutorialStep, 2)
		s.Quest.Start(s.player, s.profile) -- a rejoin
		t.eq(s.profile.tutorialStep, 2, "carries on")
		s.skip()
		t.ok(s.profile.tutorialDone)
		t.eq(s.profile.tutorialRefresher, false)
		local v1 = setup({ tutorialRefresher = true, bestAxeTier = 4 })
		v1.Quest.Start(v1.player, v1.profile)
		t.ok(v1.profile.tutorialDone, "a rollback to v1 bypasses as before (better axe)")
	end)

	t.test("the refresher's texts: Murph's welcome-back line and the tracker title", function()
		local TutorialData = t.shared("TutorialData")
		local first = TutorialData.StepsV2[1]
		t.eq(TutorialData.MurphLine(first, false), first.murph)
		t.ok(string.find(TutorialData.MurphLine(first, true), "Welcome back", 1, true) ~= nil)
		local second = TutorialData.StepsV2[2]
		t.eq(TutorialData.MurphLine(second, true), second.murph, "no special line: the usual one")
		t.eq(TutorialData.StepsV2[TutorialData.RefresherLast].id, "sell")
		t.ok(#TutorialData.FarewellBack > 0)
	end)
end
