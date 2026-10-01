--!nocheck
-- WorldClock keeps the IsNight attribute and the night-only grove, and
-- leaves Lighting.ClockTime to the clients (it doesn't replicate).
return function(t)
	local GameConfig = t.shared("GameConfig")
	local cycle = GameConfig.DayCycleMinutes * 60
	local BASE = 1790000000 - (1790000000 % cycle) -- a midnight

	local function setup(now)
		local lightingWrites = {}
		local lighting = setmetatable({}, {
			__newindex = function(_, k, v)
				table.insert(lightingWrites, k)
				rawset(lightingWrites, "last_" .. k, v)
			end,
		})
		local attributes = {}
		local dormant = {}
		local clock = { now = now }
		local fakeWorkspace = {
			SetAttribute = function(_, name, value)
				attributes[name] = value
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
		end
	end

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
end
