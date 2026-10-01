--!strict
-- HudRules: when the HUD's optional pieces show, as plain rules (no
-- Instances), so tests can check them. Each controller reads the rule for
-- its own piece:
--   * TutorialRunning(): Murph's tutorial is on. TutorialStep is 0 once
--     it's done or skipped; nil while the save loads counts as on (as
--     NPCController has it).
--   * DailyButton() (DailyUI): Daily Goals waits until the tutorial's done.
--   * Pouch() (ForestUI): the Heartseed pouch shows from the tutorial's
--     plant step on, and after it, once you hold a seed.
--   * SendHome() (VehicleController): "Send truck home" only while you're
--     on foot, away from your truck, and it's away from its parking spot.
-- The server stays in charge of what any of them do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TruckHome = require(ReplicatedStorage.Shared.TruckHome)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)

local HudRules = {}

HudRules.SendHomeNear = 40 -- studs: closer to your truck than this, you'd drive it rather than send it

-- The tutorial step the pouch waits for (step ids never change: they're
-- save keys). Without it, the pouch shows from the start.
local PLANT_STEP = (function(): number
	for i, step in ipairs(TutorialData.Steps) do
		if step.id == "plant" then
			return i
		end
	end
	return 1
end)()

-- `step` is the TutorialStep attribute as read (any type).
function HudRules.TutorialRunning(step: unknown): boolean
	return type(step) ~= "number" or step > 0
end

-- The Daily Goals button: once there are goals and the tutorial's over.
function HudRules.DailyButton(step: unknown, goals: number): boolean
	return goals > 0 and not HudRules.TutorialRunning(step)
end

-- The Heartseed pouch: you hold `seeds`, and the tutorial has reached its
-- plant step (or is over).
function HudRules.Pouch(step: unknown, seeds: number): boolean
	return seeds > 0 and type(step) == "number" and (step == 0 or step >= PLANT_STEP)
end

-- "Send truck home": `onFoot` (you have a character and aren't driving),
-- `fromYou` studs between you and your truck (nil when it isn't streamed
-- in, which means it's far), and the server's TruckSlotDistance.
function HudRules.SendHome(onFoot: boolean, fromYou: number?, slotDistance: unknown): boolean
	return onFoot and (fromYou == nil or fromYou > HudRules.SendHomeNear) and TruckHome.Far(slotDistance)
end

return HudRules
