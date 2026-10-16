--!strict
-- ChopHaptics: a short rumble on the Small motor for a chop, on a gamepad
-- only (the last input was a pad). Every call is guarded: a pad without that
-- motor, a platform without HapticService, or an engine that rejects the call
-- does nothing, and the motor is always set back to 0. Unverified on real
-- hardware (see PHASE2_NOTES.md CHOP-T325). Does not touch CameraShake's
-- Large-motor buzz.

local ChopFeelLogic = require(game:GetService("ReplicatedStorage").Shared.ChopFeelLogic)

local ChopHaptics = {}

local function padIsLast(): boolean
	local ok, last = pcall(function()
		return game:GetService("UserInputService"):GetLastInputType()
	end)
	return ok and last ~= nil and string.find(last.Name, "Gamepad") ~= nil
end

-- Whether a pulse would play now (a pad is the last input and the pad has the motor).
function ChopHaptics.CanPulse(): boolean
	if not padIsLast() then
		return false
	end
	local ok, supported = pcall(function()
		return game:GetService("HapticService"):IsMotorSupported(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small)
	end)
	return ok and supported == true
end

local function setMotor(value: number)
	pcall(function()
		game:GetService("HapticService"):SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, value)
	end)
end

-- Rumble at `strength` (0..1) for ChopFeelLogic.HapticSeconds, then back to 0.
function ChopHaptics.Pulse(strength: number)
	if not ChopHaptics.CanPulse() then
		return
	end
	setMotor(math.clamp(strength, 0, 1))
	task.delay(ChopFeelLogic.HapticSeconds, function()
		setMotor(0)
	end)
end

function ChopHaptics.Bite()
	ChopHaptics.Pulse(ChopFeelLogic.HapticBite)
end

function ChopHaptics.Final()
	ChopHaptics.Pulse(ChopFeelLogic.HapticFinal)
end

return ChopHaptics
