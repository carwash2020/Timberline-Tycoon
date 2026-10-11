--!nocheck
-- Murph's tutorial on the server: progress, rewards, skipping.
return function(t)
	-- `loop`: the core loop GameServer passes to Init (nil: v1, as before).
	local function setup(profileOverrides, loop, openLimiter)
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
		if openLimiter then
			mocks.RateLimiter = {
				Allow = function()
					return true
				end,
			}
		end
		loader = t.loader({ mocks = mocks })
		local Quest = loader:server("QuestService")
		local skipHandler, seenHandler
		Quest.Init(
			{
				OnServerEvent = {
					Connect = function(_, fn)
						skipHandler = fn
					end,
				},
			},
			function(_, message)
				table.insert(toasts, message)
			end,
			loop,
			nil,
			{
				OnServerEvent = {
					Connect = function(_, fn)
						seenHandler = fn
					end,
				},
			}
		)
		return {
			seen = function(what)
				seenHandler(player, what)
			end,
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
		t.eq(s.Steps[2].id, "fell")
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
		t.eq(s.toasts, {
			"Murph chipped in $25!",
			"Murph chipped in $8!",
			"Murph chipped in $8!",
			"Murph chipped in $9!",
		})
	end)

	t.test("the first sale pays Murph's $25 and the next step is the truck", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "sell")
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
		local cashBefore = s.profile.cash
		s.event("logsSold", 1)
		t.eq(s.Steps[s.profile.tutorialStep].id, "truck")
		t.eq(s.profile.cash, cashBefore + 25)
		t.eq(s.toasts, { "Murph chipped in $25!" })
	end)

	t.test("buying the Steel Axe finishes it; the plot was the first step", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		t.eq(s.Steps[1].id, "plot")
		playUntil(s, "steel")
		s.profile.bestAxeTier = 2
		t.ok(not s.profile.tutorialDone)
		s.event("axeBought")
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
		t.ok(s.profile.tutorialDone, "the axe was the last step, and it was already done")
		t.eq(s.player.attrs.TutorialStep, 0)
	end)

	t.test("owning a truck already skips that step when the sale is done", function()
		local s = setup({ ownedTrucks = { "Rustbucket" } })
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "sell")
		s.event("logsSold", 1)
		t.eq(s.Steps[s.profile.tutorialStep].id, "load", "the truck step was already done")
		t.ok(not s.profile.tutorialDone)
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

	t.test("reset tutorial is not bypassed on the next join", function()
		local s = setup({ bestAxeTier = 4, tutorialDone = true, tutorialStep = 1, tutorialProgress = 0 })
		s.Quest.Reset(s.player)
		t.eq(s.profile.tutorialDone, false)
		t.eq(s.profile.tutorialReplay, true)
		s.Quest.Start(s.player, s.profile)
		t.ok(not s.profile.tutorialDone, "a better axe doesn't skip a replay")
		t.eq(s.profile.tutorialReplay, true)
	end)

	-- V1 (Connor): a skipper still gets the starter cash of the steps they skipped, once.
	t.test("Skip ends it, pays the skipped steps' starter cash once; a finished tutorial stays finished", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		local TutorialData = t.shared("TutorialData")
		local expected = TutorialData.SkipCash(1, s.profile.tutorialStep)
		s.skip()
		t.ok(s.profile.tutorialDone)
		t.eq(s.profile.tutorialSkipped, true, "saved")
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.profile.cash, expected)
		s.skip()
		t.eq(s.profile.cash, expected, "a second skip pays nothing")
		local again = setup({ tutorialDone = true })
		again.Quest.Start(again.player, again.profile)
		t.eq(again.player.attrs.TutorialStep, 0)
	end)

	t.test("the mill is followed by the sell-more loads", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		playUntil(s, "loads")
		t.eq(s.Steps[s.profile.tutorialStep].id, "loads")
		t.eq(s.Steps[s.profile.tutorialStep - 1].id, "mill", "right after the haul to the mill")
		s.event("treeFelled")
		t.eq(s.Steps[s.profile.tutorialStep].id, "loads", "felling doesn't sell a load")
	end)

	t.test("saves from before a later beat keep their place", function()
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
		t.eq(e.Steps[e.profile.tutorialStep].id, "load", "the truck lesson is later than the first sale")
		e.event("logsSold", 3)
		t.eq(e.Steps[e.profile.tutorialStep].id, "load", "a sale doesn't load the truck")
		e.event("logsLoaded", 1)
		t.eq(e.Steps[e.profile.tutorialStep].id, "mill")
	end)

	t.test("stumps are not held for any tutorial step", function()
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
		t.eq(v2.Steps[1].event, "treeFelled")
		t.eq(v2.Steps[1].id, "fell")
		t.eq(v2.Steps[4].id, "plot")
		local v1 = setup()
		t.eq(v1.Steps, TutorialData.Steps)
	end)

	t.test("v2: the walk on the wired events: fell, grab, load, sold, sold cash, buy", function()
		local s = setup(nil, 2)
		local function at()
			return s.Steps[s.profile.tutorialStep].id
		end
		s.Quest.Start(s.player, s.profile)
		t.eq(at(), "fell")
		s.event("treeFelled") -- the chop path (SectionTrees' OnFelled from M1.3)
		t.eq(at(), "pickup")
		s.event("logPickedUp")
		t.eq(at(), "pickup", "v1's pickup counts for nothing under v2")
		s.event("woodGrabbed") -- GrabService.Hooks.onGrab
		t.eq(at(), "sell")
		s.event("woodLoaded")
		t.eq(at(), "sell", "a load doesn't sell the first load")
		local cash = s.profile.cash
		s.Quest.WoodSold(s.player, 1, 30)
		t.eq(at(), "plot", "the first piece moves the sell step on")
		t.eq(s.profile.cash, cash + 25, "Murph's share on that sale")
		s.event("plotClaimed")
		t.eq(at(), "place", "the plot is bought; one build lesson follows")
		s.event("itemPlaced")
		t.eq(at(), "truck")
		t.eq(s.player.attrs.TutorialProgress, 0, "and its cash doesn't count toward the truck")
		s.event("truckBought")
		t.eq(at(), "pad", "the box is bought; the pad comes next")
		s.event("padPlaced") -- VehicleService, from the box
		t.eq(at(), "spawn")
		s.event("truckSpawned") -- VehicleService, the pad's button
		t.ok(s.profile.tutorialDone, "the truck rolling out is the last step")
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.toasts, {
			string.format("Murph chipped in $%d!", s.Steps[4].rewardCash), -- the plot step: toward the Rustbucket
		}, "the first sale's thank-you is on the next card, not a second pop-up")
		t.eq(s.marks, { "Finished the tutorial", "Saw a next goal" })
	end)

	t.test("v2: a sale's junk numbers count for nothing; a sale the wallet cap ate counts its pieces", function()
		local s = setup(nil, 2)
		s.Quest.Start(s.player, s.profile)
		for _, event in ipairs({ "treeFelled", "woodGrabbed" }) do
			s.event(event)
		end
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
		s.Quest.WoodSold(s.player, 0, 30)
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell", "no pieces")
		s.Quest.WoodSold(s.player, 1, 0)
		t.eq(s.Steps[s.profile.tutorialStep].id, "plot", "nothing credited (a full wallet): still a sale")
		s.event("plotClaimed")
		t.eq(s.Steps[s.profile.tutorialStep].id, "place")
		for _, junk in ipairs({ 0, -5, 0 / 0, math.huge, 0.6 }) do
			s.Quest.WoodSold(s.player, 1, junk)
		end
		t.eq(s.profile.tutorialProgress, 0, "no sale counts toward placing")
		t.eq(s.player.attrs.TutorialProgress, 0)
	end)

	t.test("v2: BUILD and LAND are no longer lessons: the client's reports count for nothing", function()
		local s = setup({ plot = { claimed = true, tier = 1, placed = {}, squares = {} } }, 2, true)
		s.Quest.Start(s.player, s.profile)
		local function at()
			return s.Steps[s.profile.tutorialStep].id
		end
		playUntil(s, "place")
		t.eq(at(), "place")
		s.seen("land")
		s.seen("build")
		s.seen("junk")
		s.seen(42)
		s.seen(nil)
		t.eq(at(), "place", "only placing an item counts")
		s.event("itemPlaced")
		t.eq(at(), "truck")
	end)

	t.test("v2: a placed item skips the place step", function()
		local placed = setup({
			plot = { claimed = true, tier = 1, placed = { { uid = "a" } }, squares = {} },
		}, 2, true)
		placed.Quest.Start(placed.player, placed.profile)
		for _, event in ipairs({ "treeFelled", "woodGrabbed", "woodSold" }) do
			placed.event(event)
		end
		t.eq(placed.Steps[placed.profile.tutorialStep].id, "truck", "plot and place are both already done")
	end)

	t.test("v2: a save that was midway through a retired step moves forward or finishes", function()
		local TutorialData = t.shared("TutorialData")
		local long = TutorialData.OrderV2BeforeShort
		local function at(name)
			for i, id in ipairs(long) do
				if id == name then
					return i
				end
			end
		end
		local onBuild = setup({
			tutorialStep = at("build"),
			tutorialOrder = 5,
			plot = { claimed = true, tier = 1, placed = {} },
		}, 2)
		onBuild.Quest.Start(onBuild.player, onBuild.profile)
		t.eq(onBuild.Steps[onBuild.profile.tutorialStep].id, "place", "build is retired: on to the build lesson")
		local onLand = setup({
			tutorialStep = at("land"),
			tutorialOrder = 5,
			plot = { claimed = true, tier = 1, placed = { { uid = "a" } } },
		}, 2)
		onLand.Quest.Start(onLand.player, onLand.profile)
		t.eq(onLand.Steps[onLand.profile.tutorialStep].id, "truck", "land is retired: on to the truck")
		for _, name in ipairs({ "load", "mill", "loads", "loads2", "loads3", "steel" }) do
			local s = setup({ tutorialStep = at(name), tutorialOrder = 5, tutorialProgress = 17 }, 2)
			s.Quest.Start(s.player, s.profile)
			t.ok(s.profile.tutorialDone, name .. ": past the truck, the tutorial is done")
			t.eq(s.player.attrs.TutorialStep, 0)
			t.eq(s.profile.tutorialProgress, 0)
			t.eq(s.marks[1], "Finished the tutorial")
		end
		-- A save already on the short order is not touched, and finished ones stay finished.
		local fresh = setup({ tutorialStep = 5, tutorialOrder = TutorialData.OrderV2 }, 2)
		fresh.Quest.Start(fresh.player, fresh.profile)
		t.eq(fresh.Steps[fresh.profile.tutorialStep].id, "place")
		local done = setup({ tutorialDone = true, tutorialStep = 16, tutorialOrder = 5 }, 2)
		done.Quest.Start(done.player, done.profile)
		t.ok(done.profile.tutorialDone)
		t.eq(done.player.attrs.TutorialStep, 0)
		t.eq(done.marks[1], "Saw a next goal", "no second 'Finished the tutorial'")
	end)

	t.test("v2: Skip works on a short step and pays the starter cash of the steps still ahead", function()
		local s = setup(nil, 2, true)
		s.Quest.Start(s.player, s.profile)
		s.event("treeFelled")
		local cash = s.profile.cash
		local ahead = t.shared("TutorialData").SkipCash(2, s.profile.tutorialStep)
		s.skip()
		t.ok(s.profile.tutorialDone)
		t.eq(s.player.attrs.TutorialStep, 0)
		t.eq(s.profile.cash, cash + ahead)
		t.eq(s.profile.tutorialSkipped, true)
	end)

	t.test("v1 is untouched: the v2 events count for nothing under loop 1", function()
		local s = setup()
		s.Quest.Start(s.player, s.profile)
		s.event("plotClaimed")
		t.eq(s.Steps[s.profile.tutorialStep].id, "fell")
		s.event("treeFelled")
		t.eq(s.Steps[s.profile.tutorialStep].id, "pickup")
		s.event("woodGrabbed")
		s.Quest.WoodSold(s.player, 3, 90)
		t.eq(s.Steps[s.profile.tutorialStep].id, "pickup")
		t.eq(s.profile.tutorialProgress, 0)
		s.event("logPickedUp")
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
	end)

	t.test("v2: stumps are not held", function()
		local s = setup(nil, 2)
		s.Quest.Start(s.player, s.profile)
		t.eq(s.trees.StumpHold(s.player), 0)
		t.eq(s.Steps[1].id, "fell")
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
		t.eq(s.Steps[1].id, "fell")
		t.eq(s.player.attrs.TutorialRefresher, true)
		s.event("plotClaimed")
		s.event("treeFelled")
		s.event("woodGrabbed")
		s.event("woodLoaded")
		t.eq(s.profile.tutorialStep, TutorialData.RefresherLast)
		t.eq(s.Steps[s.profile.tutorialStep].id, "sell")
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
		t.eq(s.Steps[2].id, "pickup")
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
		local fell = TutorialData.StepsV2[1]
		t.eq(fell.id, "fell")
		t.eq(TutorialData.MurphLine(fell, false, 0), fell.murph)
		t.ok(string.find(TutorialData.MurphLine(fell, true), "Welcome back", 1, true) ~= nil)
		local pickup = TutorialData.StepsV2[2]
		t.eq(TutorialData.MurphLine(pickup, true), pickup.murph, "no special line: the usual one")
		local plot = TutorialData.StepsV2[4]
		t.eq(plot.id, "plot")
		t.eq(TutorialData.MurphLine(plot, true), plot.murph, "the claim has no welcome-back line")
		t.eq(TutorialData.StepsV2[TutorialData.RefresherLast].id, "sell")
		t.ok(#TutorialData.FarewellBack > 0)
	end)

	t.test("v2 S11: a save past plot, or one that already claimed, skips the claim and keeps the plot", function()
		local function claimed()
			return { claimed = true, tier = 1, placed = {} }
		end
		local past = setup({
			tutorialStep = 2, -- the old order's fell, already past the claim
			tutorialProgress = 0,
			tutorialOrder = 0,
			plot = claimed(),
			onboarding = { ["Tutorial:plot"] = true, ["Tutorial:fell"] = true },
		}, 2)
		past.Quest.Start(past.player, past.profile)
		t.eq(past.Steps[past.profile.tutorialStep].id, "fell")
		t.eq(past.profile.plot.claimed, true)
		past.event("treeFelled")
		past.event("woodGrabbed")
		past.event("woodSold")
		t.eq(past.Steps[past.profile.tutorialStep].id, "place", "reaching plot completes it")
		t.eq(past.profile.plot.claimed, true, "the plot is not released")

		local owned = setup({
			tutorialStep = 1,
			tutorialOrder = 0,
			plot = claimed(),
		}, 2)
		owned.Quest.Start(owned.player, owned.profile)
		t.eq(owned.Steps[owned.profile.tutorialStep].id, "fell")
		owned.event("treeFelled")
		owned.event("woodGrabbed")
		owned.event("woodSold")
		t.eq(owned.Steps[owned.profile.tutorialStep].id, "place")
		t.eq(owned.profile.plot.claimed, true)

		local later = setup({
			tutorialStep = 5,
			tutorialOrder = 0,
			plot = claimed(),
			onboarding = { ["Tutorial:plot"] = true, ["Tutorial:truck"] = true },
		}, 2)
		later.Quest.Start(later.player, later.profile)
		t.eq(later.Steps[later.profile.tutorialStep].id, "truck", "already past the new plot step")
		t.eq(later.profile.plot.claimed, true)
	end)
end
