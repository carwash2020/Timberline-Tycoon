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
		t.eq(s.profile.tutorialStep, 1, "chopping waits until the plot is claimed")
		s.event("plotClaimed")
		t.eq(s.profile.tutorialStep, 2)
		t.eq(s.player.attrs.TutorialStep, 2)
	end)

	t.test("the first sale pays Murph's $25 and moves on to the truck", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "sell")
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
		local cashBefore = s.profile.cash
		s.event("treeFelled")
		t.eq(s.profile.cash, cashBefore, "no reward yet")
		s.event("logsSold", 1)
		t.eq(s.Steps[s.profile.tutorialStep].id, "truck")
		t.eq(s.profile.cash, cashBefore + 25)
		t.eq(s.toasts, { "Murph chipped in $25!" })
	end)

	t.test("buying the truck finishes it, after the first sale", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "truck")
		t.eq(s.Steps[s.profile.tutorialStep].id, "truck")
		t.ok(not s.profile.tutorialDone)
		s.event("truckBought")
		t.ok(s.profile.tutorialDone)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.marks, { "Finished the tutorial", "Saw a next goal" })
		t.ok(type(s.player.attrs.NextGoal) == "string" and #s.player.attrs.NextGoal > 0)
		s.event("treeFelled") -- nothing happens after the end
		t.eq(s.player.attrs.TutorialStep, 0)
	end)

	t.test("owning a truck already skips that step when the sale is done", function()
		local s = setup({ ownedTrucks = { "Rustbucket" } })
		s.Quest.Start(s.player, s.profile)
		s.event("plotClaimed")
		s.event("treeFelled")
		t.ok(not s.profile.tutorialDone)
		s.event("logsSold", 1)
		t.ok(s.profile.tutorialDone, "the truck step was already done")
		t.eq(s.marks, { "Finished the tutorial", "Saw a next goal" })
	end)

	t.test("progress survives a rejoin", function()
		local s = setup({ tutorialStep = 3, tutorialProgress = 0 })
		s.Quest.Start(s.player, s.profile)
		t.eq(s.player.attrs.TutorialStep, 3)
		t.eq(s.player.attrs.TutorialProgress, 0)
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
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

	t.test("reset tutorial is not bypassed on the next join", function()
		local s = setup({ bestAxeTier = 4, tutorialDone = true, tutorialStep = 1, tutorialProgress = 0 })
		s.Quest.Reset(s.player)
		t.eq(s.profile.tutorialDone, false)
		t.eq(s.profile.tutorialReplay, true)
		s.Quest.Start(s.player, s.profile)
		t.ok(not s.profile.tutorialDone, "a better axe doesn't skip a replay")
		t.eq(s.profile.tutorialReplay, true)
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

	t.test("a save from the long tutorial lands on the latest step that still exists", function()
		local reached = {}
		for _, id in ipairs({ "fell", "pickup", "load", "sell" }) do
			reached["Tutorial:" .. id] = true
		end
		local mid = setup({ tutorialStep = 6, tutorialProgress = 4, onboarding = table.clone(reached) })
		mid.Quest.Start(mid.player, mid.profile)
		t.eq(
			mid.Steps[mid.profile.tutorialStep].id,
			"sell",
			"pickup and load are gone; the cart sale is the latest that remains"
		)
		t.eq(mid.player.attrs.TutorialProgress, 4, "progress kept")
		mid.event("logsSold", 1)
		t.eq(mid.Steps[mid.profile.tutorialStep].id, "truck")
	end)

	t.test("the short tutorial holds no stumps", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		t.eq(s.trees.StumpHold, s.Quest.StumpHoldFor, "Init hands TreeService the hook")
		for _, step in ipairs(s.Steps) do
			t.eq(s.trees.StumpHold(s.player), 0, step.id)
			s.event(step.event, step.count)
		end
		t.ok(s.profile.tutorialDone)
		t.eq(s.trees.StumpHold(s.player), 0, "finished")
		t.eq(s.trees.StumpHold({}), 0, "no profile (left)")
	end)

	t.test("a skipped tutorial holds no stumps", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		t.eq(s.Quest.StumpHoldFor(s.player), 0)
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
		t.eq(v2.Steps[1].event, "plotClaimed")
		t.eq(v2.Steps[2].event, "treeFelled")
		local v1 = setup()
		t.eq(v1.Steps, TutorialData.Steps)
	end)

	t.test("v2: the walk is plot, chop, first sale, then the truck", function()
		local s = setup(nil, 2)
		local function at()
			return s.Steps[s.profile.tutorialStep].id
		end
		s.Quest.Start(s.player, s.profile)
		t.eq(at(), "plot")
		s.event("treeFelled")
		t.eq(at(), "plot", "chopping waits for the claim")
		s.event("plotClaimed")
		t.eq(at(), "fell")
		s.event("woodGrabbed")
		t.eq(at(), "fell", "dragging isn't its own step")
		s.event("treeFelled")
		t.eq(at(), "sell")
		s.event("woodLoaded")
		t.eq(at(), "sell", "a load doesn't sell the cart")
		local cash = s.profile.cash
		s.Quest.WoodSold(s.player, 2, 30)
		t.eq(at(), "truck", "the first sale, however many pieces")
		t.eq(s.profile.cash, cash + 25, "Murph's share on that sale")
		t.eq(s.toasts, { "Murph chipped in $25!" })
		s.event("axeBought")
		t.eq(at(), "truck", "the Steel Axe is the next goal, not a step")
		s.event("truckBought")
		t.ok(s.profile.tutorialDone)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.marks, { "Finished the tutorial", "Saw a next goal" })
	end)

	t.test("v2: a sale's junk numbers count for nothing; a sale the wallet cap ate counts its pieces", function()
		local s = setup(nil, 2)
		s.Quest.Start(s.player, s.profile)
		s.event("plotClaimed")
		s.event("treeFelled")
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
		s.Quest.WoodSold(s.player, 0, 30)
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell", "no pieces")
		s.Quest.WoodSold(s.player, 1, 0)
		t.eq(s.Steps[s.profile.tutorialStep].id, "truck", "nothing credited (a full wallet): still a sale")
		for _, junk in ipairs({ 0, -5, 0 / 0, math.huge, 0.6 }) do
			s.Quest.WoodSold(s.player, 1, junk)
		end
		t.eq(s.Steps[s.profile.tutorialStep].id, "truck", "dollars don't buy the truck")
		t.eq(s.profile.tutorialProgress, 0)
		t.eq(s.player.attrs.TutorialProgress, 0)
	end)

	t.test("v1 is untouched: the v2 events count for nothing under loop 1", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		s.event("plotClaimed")
		t.eq(s.Steps[s.profile.tutorialStep].id, "fell")
		s.event("woodGrabbed")
		s.Quest.WoodSold(s.player, 3, 90)
		t.eq(s.Steps[s.profile.tutorialStep].id, "fell")
		t.eq(s.profile.tutorialProgress, 0)
		s.event("treeFelled")
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
	end)

	t.test("v2: the short tutorial holds no stumps", function()
		local s = setup(nil, 2)
		s.Quest.Start(s.player, s.profile)
		for _, step in ipairs(s.Steps) do
			t.eq(s.trees.StumpHold(s.player), 0, step.id)
			s.event(step.event, step.count)
		end
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
		s.event("plotClaimed")
		s.event("treeFelled")
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
		s.event("plotClaimed")
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
		local plot = TutorialData.StepsV2[1]
		t.eq(TutorialData.MurphLine(plot, true), plot.murph, "the claim has no welcome-back line")
		local fell = TutorialData.StepsV2[2]
		t.eq(TutorialData.MurphLine(fell, false), fell.murph)
		t.ok(string.find(TutorialData.MurphLine(fell, true), "Welcome back", 1, true) ~= nil)
		local sell = TutorialData.StepsV2[3]
		t.eq(TutorialData.MurphLine(sell, true), sell.murph, "no special line: the usual one")
		t.eq(TutorialData.StepsV2[TutorialData.RefresherLast].id, "sell")
		t.ok(#TutorialData.FarewellBack > 0)
	end)
end
