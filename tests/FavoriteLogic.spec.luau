--!nocheck
-- The one-time favorite reminder: the pure rule, and the server check with mocks.
return function(t)
	local Logic = t.shared("FavoriteLogic")

	local function state(over)
		local s = { playSeconds = 600, shownBefore = false, tutorialDone = true, talking = false }
		for k, v in pairs(over or {}) do
			s[k] = v
		end
		return s
	end

	t.test("due after ten minutes of play, once", function()
		t.ok(not Logic.Due(state({ playSeconds = 599 })))
		t.ok(Logic.Due(state()))
		t.ok(Logic.Due(state({ playSeconds = 5000 })))
		t.ok(not Logic.Due(state({ shownBefore = true })), "once ever")
	end)

	t.test("never during a tutorial step or a dialogue", function()
		t.ok(not Logic.Due(state({ tutorialDone = false })))
		t.ok(not Logic.Due(state({ talking = true })))
		t.ok(Logic.Due(state()), "and it shows when they are over")
	end)

	t.test("the text points at the star and promises nothing", function()
		t.ok(string.find(Logic.Text, "star", 1, true))
		t.ok(#Logic.Text <= 120, "short enough for a toast")
		t.eq(string.find(string.lower(Logic.Text), "robux", 1, true), nil)
	end)

	local function setup(profileOver)
		local clock = { now = 0 }
		local toasts = {}
		local state = { talking = false }
		local profile = { onboarding = {}, tutorialDone = true }
		for k, v in pairs(profileOver or {}) do
			profile[k] = v
		end
		local player = { Name = "A", UserId = 1 }
		local loader = t.loader({
			services = { Players = {} },
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				NPCTalkService = {
					IsTalking = function()
						return state.talking
					end,
				},
			},
		})
		local Service = loader:server("FavoriteService")
		Service.SetClock(function()
			return clock.now
		end)
		Service.Init(function(_, message)
			table.insert(toasts, message)
		end)
		Service.Begin(player)
		return Service, player, profile, toasts, clock, state
	end

	t.test("the service toasts once after ten minutes and saves the flag", function()
		local Service, player, profile, toasts, clock = setup()
		clock.now = 599
		t.ok(not Service.Check(player))
		clock.now = 600
		t.ok(Service.Check(player))
		t.eq(#toasts, 1)
		t.eq(toasts[1], Logic.Text)
		t.eq(profile.onboarding[Logic.Key], true)
		clock.now = 5000
		t.ok(not Service.Check(player), "not again")
		t.eq(#toasts, 1)
	end)

	t.test("blocked by the tutorial or a dialogue it waits, then shows when clear", function()
		local Service, player, profile, toasts, clock, state = setup({ tutorialDone = false })
		clock.now = 700
		t.ok(not Service.Check(player), "tutorial step running")
		profile.tutorialDone = true
		state.talking = true
		t.ok(not Service.Check(player), "dialogue open")
		t.eq(profile.onboarding[Logic.Key], nil, "still not used up")
		state.talking = false
		t.ok(Service.Check(player))
		t.eq(#toasts, 1)
	end)

	t.test("a player who saw it in an earlier session never gets it again", function()
		local Service, player, _, toasts, clock = setup({ onboarding = { [Logic.Key] = true } })
		clock.now = 9999
		t.ok(not Service.Check(player))
		t.eq(#toasts, 0)
	end)
end
