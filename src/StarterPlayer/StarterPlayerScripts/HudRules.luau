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
--   * DropAxe() (AxeController): "Drop axe" only while you hold an axe and
--     either carry another or hold one better than the starter.
--   * DropPress(): dropping takes two presses (a tap, a click, the pad's
--     button or Backspace), the second 0.3 to 3 s after the first.
-- The server stays in charge of what any of them do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TruckHome = require(ReplicatedStorage.Shared.TruckHome)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)

local HudRules = {}

HudRules.SendHomeNear = 40 -- studs: closer to your truck than this, you'd drive it rather than send it
HudRules.DropConfirmSeconds = 3 -- the second press must come this soon after the first...
HudRules.DropConfirmGap = 0.3 -- ...but not sooner than this (a double tap or a mashed button isn't a yes)

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

-- "Drop axe": you hold an axe (`heldId`, nil if you don't) and carry
-- `carried` axes in all (in hand and in the Backpack, so not counting any
-- lying on the ground): two or more, or the one in hand isn't the starter
-- (the ladder's first rung). A new player with just the Rusty Axe never
-- sees it. The server refuses to drop your last axe either way.
function HudRules.DropAxe(carried: number, heldId: string?): boolean
	if heldId == nil then
		return false
	end
	return carried >= 2 or (ItemCatalog.AxeTier(heldId) or 1) > 1
end

-- A press of "Drop axe" when the first press was at `armedAt` (nil: none
-- waiting) and it's `now` (os.clock). Returns whether to drop, and when
-- the press waiting for a second one was made (nil once it's dropped):
--   * no press waiting, or it's too old: this one waits ("Confirm drop");
--   * the waiting one is less than DropConfirmGap old: nothing (it still
--     waits, from the first press);
--   * else: drop.
function HudRules.DropPress(armedAt: number?, now: number): (boolean, number?)
	if armedAt == nil or now - armedAt > HudRules.DropConfirmSeconds then
		return false, now
	end
	if now - armedAt < HudRules.DropConfirmGap then
		return false, armedAt
	end
	return true, nil
end

return HudRules
