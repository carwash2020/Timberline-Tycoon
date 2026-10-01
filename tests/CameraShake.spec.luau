--!nocheck
-- CameraShake against a stand-in for Roblox's camera, which builds each
-- frame from where the camera points now (BaseCamera reads the current
-- LookVector): a shake must leave the view where it was.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

	local steps = {}
	local camera = { CFrame = CFrame.new(0, 10, 0) * CFrame.Angles(-0.3, 0.8, 0) }
	local loader = t.loader({
		services = {
			RunService = {
				BindToRenderStep = function(_, name, priority, fn)
					table.insert(steps, { name = name, priority = priority, fn = fn })
					table.sort(steps, function(a, b)
						return a.priority < b.priority
					end)
				end,
			},
			HapticService = {
				IsVibrationSupported = function()
					return false
				end,
			},
		},
		globals = { workspace = { CurrentCamera = camera } },
	})
	local CameraShake = loader:load("StarterPlayer/StarterPlayerScripts/CameraShake")
	local CAMERA_PRIORITY = roblox.Enum.RenderPriority.Camera.Value

	-- One frame: every bound step in priority order, with Roblox's camera
	-- update at its own priority (it keeps the camera's position and look,
	-- and rebuilds it upright from them: yaw, then pitch, no roll).
	local function frame(dt)
		local cameraDone = false
		local function updateCamera()
			local cf = camera.CFrame
			local look = cf.LookVector
			local yaw = math.atan2(-look.X, -look.Z)
			local pitch = math.asin(math.clamp(look.Y, -1, 1))
			camera.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
			cameraDone = true
		end
		for _, s in ipairs(steps) do
			if not cameraDone and s.priority > CAMERA_PRIORITY then
				updateCamera()
			end
			s.fn(dt)
		end
		if not cameraDone then
			updateCamera()
		end
	end

	t.test("the undo runs before the camera update, the shake after it", function()
		CameraShake.Shake(0.45, 0.35)
		t.eq(#steps, 2)
		t.ok(steps[1].priority < CAMERA_PRIORITY and steps[2].priority > CAMERA_PRIORITY)
	end)

	t.test("after a shake the camera looks where it did before", function()
		for _ = 1, 60 do
			frame(1 / 60) -- the first shake runs out
		end
		local before = camera.CFrame.LookVector
		CameraShake.Shake(1, 0.5)
		local moved = false
		for _ = 1, 60 do
			frame(1 / 60)
			if (camera.CFrame.LookVector - before).Magnitude > 1e-3 then
				moved = true
			end
		end
		t.ok(moved, "it did shake")
		t.ok((camera.CFrame.LookVector - before).Magnitude < 1e-4, "no drift left over")
	end)

	t.test("a camera moved by something else keeps that move", function()
		CameraShake.Shake(1, 0.5)
		frame(1 / 60)
		-- A cutscene (or anything) sets the camera between frames.
		local set = CFrame.new(5, 5, 5) * CFrame.Angles(0, 1, 0)
		camera.CFrame = set
		steps[1].fn(1 / 60) -- the undo leaves it alone
		t.eq(camera.CFrame, set)
		for _ = 1, 60 do
			frame(1 / 60)
		end
		t.ok((camera.CFrame.Position - Vector3.new(5, 5, 5)).Magnitude < 1e-4)
	end)
end
