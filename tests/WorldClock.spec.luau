--!nocheck
-- WorldClock keeps the IsNight attribute and the night-only grove, and
-- leaves Lighting.ClockTime to the clients (it doesn't replicate).
return function(t)
	local GameConfig = t.shared("GameConfig")
	local cycle = GameConfig.DayCycleMinutes * 60
	local BASE = 1790000000 - (1790000000 % cycle) -- a midnight

	local function setup(now, loop2)
		local lightingWrites = {}
		local lighting = setmetatable({}, {
			__newindex = function(_, k, v)
				table.insert(lightingWrites, k)
				rawset(lightingWrites, "last_" .. k, v)
			end,
		})
		local attributes = { CoreLoopActive = if loop2 then 2 else 1 }
		local dormant = {}
		local sectionDormant = {}
		local clock = { now = now }
		local fakeWorkspace = {
			SetAttribute = function(_, name, value)
				attributes[name] = value
			end,
			GetAttribute = function(_, name)
				return attributes[name]
			end,
			GetServerTimeNow = function()
				return clock.now
			end,
		}
		local loop
		local loader = t.loader({
			services = { Lighting = lighting },
			mocks = {
				TreeService = {
					SetBiomeDormant = function(id, isDormant)
						dormant[id] = isDormant
					end,
				},
				-- The v2 loop's trees (M1.3): the same call.
				SectionTrees = {
					SetBiomeDormant = function(id, isDormant)
						sectionDormant[id] = isDormant
					end,
				},
			},
			globals = {
				workspace = fakeWorkspace,
				task = {
					spawn = function(fn)
						loop = fn
					end,
					wait = function() end,
				},
			},
		})
		local WorldClock = loader:server("WorldClock")
		return WorldClock, lightingWrites, attributes, dormant, clock, function()
			return loop
		end, sectionDormant
	end

	t.test(
		"v2 loop (M1.3): the night-only grove's section trees sleep and wake, TreeService's are left alone",
		function()
			local WorldClock, _, attributes, dormant, _, _, sectionDormant = setup(BASE + cycle / 2, true) -- noon
			WorldClock.Start()
			t.eq(attributes.IsNight, false)
			t.eq(sectionDormant.grove, true)
			t.eq(dormant.grove, nil, "TreeService isn't asked under v2")
			local Night, _, _, nightDormant, _, _, nightSections = setup(BASE, true) -- midnight
			Night.Start()
			t.ok(Night.IsNight())
			t.eq(nightSections.grove, false, "the grove wakes at night")
			t.eq(nightDormant.grove, nil)
		end
	)

	t.test("Refresh puts the night-only grove's state on trees planted after the first tick (LOAD-01)", function()
		local WorldClock, _, _, _, _, _, sectionDormant = setup(BASE + cycle / 2, true) -- noon
		WorldClock.Refresh() -- before Start: nothing to apply
		t.eq(sectionDormant.grove, nil)
		WorldClock.Start()
		t.eq(sectionDormant.grove, true)
		sectionDormant.grove = nil -- trees planted later missed that call
		WorldClock.Refresh()
		t.eq(sectionDormant.grove, true, "asleep by day, again")
	end)

	t.test("never writes Lighting.ClockTime", function()
		local WorldClock, writes = setup(BASE + cycle / 2)
		WorldClock.Start()
		t.eq(#writes, 0)
	end)

	t.test("night: IsNight is set and the Phantom Grove wakes", function()
		local WorldClock, _, attributes, dormant = setup(BASE) -- midnight
		WorldClock.Start()
		t.eq(attributes.IsNight, true)
		t.eq(dormant.grove, false)
		t.ok(WorldClock.IsNight())
		t.ok(math.abs(WorldClock.ClockTime()) < 1e-9)
	end)

	t.test("day: IsNight is false and the grove sleeps", function()
		local WorldClock, _, attributes, dormant = setup(BASE + cycle / 2) -- noon
		WorldClock.Start()
		t.eq(attributes.IsNight, false)
		t.eq(dormant.grove, true)
		t.ok(not WorldClock.IsNight())
		t.ok(math.abs(WorldClock.ClockTime() - 12) < 1e-9)
	end)

	t.test("the grove still sleeps at dusk's lamps and wakes at NightStartsAt", function()
		local WorldTime = t.shared("WorldTime")
		local lamps, _, lampAttr, lampDormant = setup(BASE + WorldTime.SecondsFromMidnight(18.7))
		lamps.Start()
		t.eq(lampAttr.IsNight, false)
		t.eq(lampDormant.grove, true, "asleep while the lamps are coming on")
		t.ok(math.abs(lamps.ClockTime() - 18.7) < 1e-6)

		local night, _, nightAttr, nightDormant = setup(BASE + WorldTime.SecondsFromMidnight(GameConfig.NightStartsAt))
		night.Start()
		t.eq(nightAttr.IsNight, true)
		t.eq(nightDormant.grove, false, "awake at NightStartsAt")
		t.ok(math.abs(night.ClockTime() - GameConfig.NightStartsAt) < 1e-6)
	end)
end
