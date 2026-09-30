--!nocheck
-- How trucks speed up, slow down and turn (physics and arcade driving).
return function(t)
	local DriveMath = t.shared("DriveMath")
	local GameConfig = t.shared("GameConfig")

	local function run(speed, throttle, top, seconds, actual)
		local dt = 1 / 60
		for _ = 1, math.floor(seconds / dt + 0.5) do
			speed = DriveMath.Speed(speed, throttle, top, dt, if actual then speed else nil)
		end
		return speed
	end

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	t.test("full throttle reaches top speed and stays there", function()
		local seconds = 26 / GameConfig.VehicleAccel
		t.ok(near(run(0, 1, 26, seconds + 0.5), 26))
		t.ok(run(0, 1, 26, seconds / 2) < 26, "not instantly")
		t.ok(near(run(0, 1, 26, 30), 26))
	end)

	t.test("half throttle, half speed; reverse is slower", function()
		t.ok(near(run(0, 0.5, 26, 10), 13))
		t.ok(near(run(0, -1, 26, 10), -26 * GameConfig.ReverseFactor))
	end)

	t.test("letting go coasts to a stop; braking is quicker", function()
		local coasted = run(20, 0, 26, 1)
		local braked = run(20, -1, 26, 1)
		t.ok(coasted < 20 and coasted > 0)
		t.ok(braked < coasted, "braking beats coasting")
		t.ok(near(run(20, 0, 26, 10), 0), "stops, doesn't roll backwards")
	end)

	t.test("a blocked truck doesn't wind up speed", function()
		local speed = 0
		for _ = 1, 120 do
			speed = DriveMath.Speed(speed, 1, 26, 1 / 60, 0) -- a tree in the way: it isn't moving
		end
		t.ok(speed <= 6 + 1e-6)
	end)

	t.test("turning: right is negative yaw, flipped in reverse, none standing still", function()
		t.ok(DriveMath.Turn(20, 1, 1.4, 1) < 0)
		t.ok(DriveMath.Turn(20, -1, 1.4, 1) > 0)
		t.ok(DriveMath.Turn(-10, 1, 1.4, 1) > 0)
		t.eq(DriveMath.Turn(0, 1, 1.4, 1), 0)
		t.ok(math.abs(DriveMath.Turn(20, 1, 1.4, 1) + 1.4) < 1e-9, "full grip above 10 studs/s")
	end)
end
