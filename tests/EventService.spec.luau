--!nocheck
-- EventService (B14): the Halloween goals on the server. The event gates on
-- the date (or the Studio override), the themed goals count the daily
-- goals' moments, finishing both on three days grants the cosmetic, and no
-- cash moves.
return function(t)
	local DAY = 86400
	local OCT_5 = 20731 * DAY + 3600 -- 2026-10-05 01:00 UTC

	local function setup(now, override)
		local profile = {
			cash = 100,
			cosmetics = {},
			event = { id = "", day = 0, progress = {}, done = {}, daysDone = 0, lastDoneDay = 0 },
		}
		local player = {
			UserId = 7,
			attrs = {},
			Parent = {},
			AncestryChanged = { Connect = function() end },
			CharacterAdded = { Connect = function() end },
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
		}
		local dailyMock = {}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				DailyService = dailyMock,
			},
		})
		local Event = loader:server("EventService")
		local toasts = {}
		local clock = { now = now }
		Event.InitEvent(function(_, message)
			table.insert(toasts, message)
		end, function()
			return clock.now
		end, function()
			return override
		end)
		return { Event = Event, profile = profile, player = player, toasts = toasts, clock = clock, daily = dailyMock }
	end

	t.test("it listens to the daily goals' moments and counts them toward the themed goals", function()
		local s = setup(OCT_5)
		t.eq(s.Event.Current(), "halloween")
		t.eq(s.daily.Listener, s.Event.Moment)
		s.Event.Start(s.player, s.profile)
		t.ok(#s.player.attrs.EventGoals > 0, "the goals are published")
		s.Event.Moment(s.player, "treeFelled", 2)
		t.eq(s.profile.event.progress[1], 2)
		t.eq(s.profile.cash, 100, "no cash")
	end)

	t.test("outside October, and with the override off, nothing counts and nothing shows", function()
		local summer = setup(OCT_5 + 200 * DAY)
		t.eq(summer.Event.Current(), nil)
		summer.Event.Start(summer.player, summer.profile)
		t.eq(summer.player.attrs.EventGoals, "")
		summer.Event.Moment(summer.player, "treeFelled", 50)
		t.eq(summer.profile.event.id, "", "untouched")
		local off = setup(OCT_5, "off")
		off.Event.Moment(off.player, "treeFelled", 50)
		t.eq(off.profile.event.id, "")
		local forced = setup(OCT_5 + 200 * DAY, "halloween")
		forced.Event.Moment(forced.player, "treeFelled", 1)
		t.eq(forced.profile.event.progress[1], 1, "the override turns it on")
	end)

	t.test("both goals on three days earn the hat, once, with no cash", function()
		local s = setup(OCT_5)
		for day = 0, 2 do
			s.clock.now = OCT_5 + day * DAY
			s.Event.Moment(s.player, "treeFelled", 50)
			s.Event.Moment(s.player, "piecesSold", 50)
			t.eq(s.profile.cosmetics.pumpkinHat, if day == 2 then true else nil, "day " .. day)
		end
		s.clock.now = OCT_5 + 3 * DAY
		s.Event.Moment(s.player, "treeFelled", 50)
		s.Event.Moment(s.player, "piecesSold", 50)
		t.eq(s.profile.cash, 100, "no cash at any point")
		local earned = 0
		for _, message in ipairs(s.toasts) do
			if string.find(message, "You earned the Pumpkin Hat", 1, true) then
				earned += 1
			end
		end
		t.eq(earned, 1, "the hat is announced once")
		t.eq(s.player.attrs.EventInfo, "Halloween|3|3|Pumpkin Hat|1")
	end)
end
