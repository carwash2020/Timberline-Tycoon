--!strict
-- CameraShake: a short, decaying shake added on top of whatever the camera
-- is doing (a tree landing nearby, lightning close by). Applied as an
-- offset after Roblox's camera update each frame and taken back out just
-- before the next one: Roblox's camera builds each frame from where the
-- camera points now, so an offset left in would add up and leave the view
-- turned. Phones get a light haptic buzz too.

local HapticService = game:GetService("HapticService")
local RunService = game:GetService("RunService")

local Quality = require(script.Parent.Quality)

local CameraShake = {}

local amplitude = 0 -- degrees
local decay = 1 -- per second
local enabled = true -- Settings: camera shake on/off
local bound = false
local t = 0
-- The camera as Roblox's camera left it, and as the shake left it, last
-- frame (nil when no offset is in).
local unshaken: CFrame? = nil
local shaken: CFrame? = nil

-- Before the camera update: back to the unshaken view, unless something
-- else has moved the camera since (then there's no offset left in it).
local function undo()
	local camera = workspace.CurrentCamera
	local base, left = unshaken, shaken
	unshaken, shaken = nil, nil
	if camera and base and camera.CFrame == left then
		camera.CFrame = base
	end
end

local function step(dt: number)
	if amplitude <= 0.01 then
		amplitude = 0
		return
	end
	t += dt
	local camera = workspace.CurrentCamera
	if camera then
		local a = math.rad(amplitude)
		local base = camera.CFrame
		camera.CFrame = base
			* CFrame.Angles(math.noise(t * 22, 1.3) * a, math.noise(t * 22, 7.1) * a, math.noise(t * 22, 3.7) * a * 0.5)
		unshaken, shaken = base, camera.CFrame
	end
	amplitude = math.max(0, amplitude - decay * dt)
end

-- Shakes the camera by up to `strength` (about 0.2 subtle .. 1 big) for
-- `duration` seconds.
function CameraShake.SetEnabled(on: boolean)
	enabled = on
	if not on then
		amplitude = 0
	end
end

function CameraShake.Shake(strength: number, duration: number)
	if not enabled then
		amplitude = 0
		return
	end
	local hz = Quality.Budget().CosmeticHz
	if hz <= 2 then
		return -- low: the shake stays off
	end
	if hz < 60 then
		strength *= 0.65 -- medium: a lighter shake
	end
	if not bound then
		bound = true
		-- The undo runs every frame from now on, so the last frame's offset
		-- comes out too.
		RunService:BindToRenderStep("TimberlineShakeUndo", Enum.RenderPriority.Camera.Value - 1, undo)
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
