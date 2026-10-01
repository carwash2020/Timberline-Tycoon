--!strict
-- CameraShake: a short, decaying shake added on top of whatever the camera
-- is doing (a tree landing nearby, lightning close by). Applied as an
-- offset after Roblox's camera update each frame, so it never fights the
-- camera scripts. Phones get a light haptic buzz too.

local HapticService = game:GetService("HapticService")
local RunService = game:GetService("RunService")

local CameraShake = {}

local amplitude = 0 -- degrees
local decay = 1 -- per second
local bound = false
local t = 0

local function step(dt: number)
	if amplitude <= 0.01 then
		amplitude = 0
		return
	end
	t += dt
	local camera = workspace.CurrentCamera
	if camera then
		local a = math.rad(amplitude)
		camera.CFrame *= CFrame.Angles(
			math.noise(t * 22, 1.3) * a,
			math.noise(t * 22, 7.1) * a,
			math.noise(t * 22, 3.7) * a * 0.5
		)
	end
	amplitude = math.max(0, amplitude - decay * dt)
end

-- Shakes the camera by up to `strength` (about 0.2 subtle .. 1 big) for
-- `duration` seconds.
function CameraShake.Shake(strength: number, duration: number)
	if not bound then
		bound = true
		RunService:BindToRenderStep("TimberlineShake", Enum.RenderPriority.Camera.Value + 1, step)
	end
	local degrees = strength * 2.2
	if degrees > amplitude then
		amplitude = degrees
		decay = degrees / math.max(0.05, duration)
	end
	pcall(function()
		if HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1) then
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, strength * 0.6)
			task.delay(duration, function()
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
			end)
		end
	end)
end

return CameraShake
