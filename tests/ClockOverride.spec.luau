--!nocheck
-- Studio's ClockOverride (WLD-06): the rule (Shared/ClockOverride), and the
-- two places that read it: WorldClock on the server (IsNight, the Phantom
-- Grove) and LightingController.Environment() on each client (the hour
-- the sky, lamps and windows use). A live server ignores it.
return function(t)
	local ClockOverride = t.shared("ClockOverride")
	local GameConfig = t.shared("GameConfig")
	local cycle = GameConfig.DayCycleMinutes * 60
	local BASE = 1790000000 - (1790000000 % cycle) -- a midnight
	local NOON = BASE + cycle / 2

	local function near(a, b)
		return math.abs(a - b) < 1e-9
	end

	t.test("in Studio, an hour from 0 to 24 replaces the clock", function()
		t.eq(ClockOverride.Apply(12, 23, true), 23)
		t.eq(ClockOverride.Apply(12, 0, true), 0)
		t.eq(ClockOverride.Apply(3, 18.5, true), 18.5)
		t.eq(ClockOverride.Apply(12, 24, true), 0, "24 is midnight")
	end)

	t.test("anything else leaves the shared clock", function()
		for _, bad in ipairs({ -1, 24.5, 230, math.huge, -math.huge, 0 / 0, "23", true }) do
			t.eq(ClockOverride.Apply(12, bad, true), 12, tostring(bad))
		end
		t.eq(ClockOverride.Apply(12, nil, true), 12, "cleared")
	end)

	t.test("outside Studio it is always the shared clock", function()
		for _, value in ipairs({ 23, 0, 12, 24 }) do
			t.eq(ClockOverride.Apply(7.25, value, false), 7.25)
		end
	end)

	---------------------------------------------------------------------------
	-- WorldClock (server)
	---------------------------------------------------------------------------

	local function worldClock(studio, now)
		local s = { attributes = {}, dormant = {}, reads = 0, waits = {} }
		local loop
		local fakeWorkspace = {
			SetAttribute = function(_, name, value)
				s.attributes[name] = value
			end,
			GetAttribute = function(_, name)
				if name == ClockOverride.Attribute then
					s.reads += 1
				end
				return s.attributes[name]
			end,
			GetServerTimeNow = function()
				return now
			end,
		}
		local loader = t.loader({
			services = {
				Lighting = {},
				RunService = {
					IsStudio = function()
						return studio
					end,
				},
			},
			mocks = {
				SectionTrees = {
					SetBiomeDormant = function(id, isDormant)
						s.dormant[id] = isDormant
					end,
				},
			},
			globals = {
				workspace = fakeWorkspace,
				task = {
					spawn = function(fn)
						loop = fn
					end,
					wait = function(seconds)
						table.insert(s.waits, seconds)
						coroutine.yield()
					end,
				},
			},
		})
		s.WorldClock = loader:server("WorldClock")
		function s.start()
			s.WorldClock.Start()
			s.thread = coroutine.create(loop)
			assert(coroutine.resume(s.thread)) -- up to the loop's first wait
		end
		function s.tick() -- one turn of the loop: a wait, then a tick
			assert(coroutine.resume(s.thread))
		end
		return s
	end

	t.test("WorldClock in Studio: night within a second of setting it, day again once cleared", function()
		local s = worldClock(true, NOON)
		s.start()
		t.eq(s.attributes.IsNight, false)
		t.eq(s.dormant.grove, true, "the grove sleeps by day")

		s.attributes.ClockOverride = 23
		s.tick()
		t.eq(s.waits[1], 1, "it looks again every second")
		t.eq(s.attributes.IsNight, true)
		t.eq(s.dormant.grove, false, "the Phantom Grove wakes")
		t.ok(s.WorldClock.IsNight())
		t.eq(s.WorldClock.ClockTime(), 23)

		s.attributes.ClockOverride = nil
		s.tick()
		t.eq(s.attributes.IsNight, false)
		t.eq(s.dormant.grove, true)
		t.ok(near(s.WorldClock.ClockTime(), 12), "back on the shared clock")
	end)

	t.test("WorldClock in Studio: noon at midnight, too", function()
		local s = worldClock(true, BASE) -- midnight
		s.attributes.ClockOverride = 12
		s.start()
		t.eq(s.attributes.IsNight, false)
		t.eq(s.dormant.grove, true)
	end)

	t.test("WorldClock on a live server ignores it and never reads it", function()
		local s = worldClock(false, NOON)
		s.attributes.ClockOverride = 23
		s.start()
		s.tick()
		t.eq(s.attributes.IsNight, false)
		t.eq(s.dormant.grove, true)
		t.ok(near(s.WorldClock.ClockTime(), 12))
		t.eq(s.reads, 0)
	end)

	---------------------------------------------------------------------------
	-- LightingController.Environment() (each client)
	---------------------------------------------------------------------------

	local function lighting(studio, now)
		local s = { attributes = {}, reads = 0 }
		local tick = 0
		local loader = t.loader({
			services = {
				Lighting = {},
				Players = {
					LocalPlayer = {
						GetAttribute = function()
							return nil
						end,
					},
				},
				RunService = {
					IsStudio = function()
						return studio
					end,
				},
			},
			globals = {
				workspace = {
					GetAttribute = function(_, name)
						if name == ClockOverride.Attribute then
							s.reads += 1
						end
						return s.attributes[name]
					end,
					GetServerTimeNow = function()
						return now
					end,
				},
				-- Each reading a moment later, past Environment()'s per-frame cache.
				os = setmetatable({
					clock = function()
						tick += 1
						return tick
					end,
				}, { __index = os }),
			},
		})
		s.LightingController = loader:load("StarterPlayer/StarterPlayerScripts/LightingController")
		s.EnvironmentData = loader:shared("EnvironmentData")
		return s
	end

	t.test("LightingController in Studio: the override is the hour every client effect reads", function()
		local s = lighting(true, NOON)
		local env = s.LightingController.Environment()
		t.ok(near(env.clock, 12), "the shared clock until it's set")

		s.attributes.ClockOverride = 23
		env = s.LightingController.Environment()
		t.eq(env.clock, 23)
		t.eq(env.daylight, s.EnvironmentData.Daylight(23), "night light")

		s.attributes.ClockOverride = nil
		env = s.LightingController.Environment()
		t.ok(near(env.clock, 12), "cleared: back to the shared clock")
	end)

	t.test("LightingController on a live client ignores it and never reads it", function()
		local s = lighting(false, NOON)
		s.attributes.ClockOverride = 23
		local env = s.LightingController.Environment()
		t.ok(near(env.clock, 12))
		t.eq(s.reads, 0)
	end)
end
