--!strict
-- HudRules: when the HUD's optional pieces show, as plain rules (no
-- Instances), so tests can check them. Each controller reads the rule for
-- its own piece:
--   * TutorialRunning(): Murph's tutorial is on. TutorialStep is 0 once
--     it's done or skipped; nil while the save loads counts as on (as
--     NPCController has it).
--   * DailyButton() (DailyUI): Daily Goals waits until the tutorial's done;
--     DailyLabel() is what its button says.
--   * Pouch() (ForestUI): the Heartseed pouch shows from the tutorial's
--     plant step on, and after it, once you hold a seed.
--   * SendHome() (VehicleController): "Send truck home" only while you're
--     on foot, away from your truck, and it's away from its parking spot.
--   * DropAxe() (AxeController): "Drop axe" only while you hold an axe and
--     either carry another or hold one better than the starter.
--   * DropPress(): dropping takes two presses (a tap, a click, the pad's
--     button or Backspace), the second 0.3 to 3 s after the first.
--   * LoadChip() (HUD): the logs in your hands and in your truck's bed,
--     beside the hint.
--   * LoadingText() (HUD): what the HUD's loading card says while you wait.
--   * ToastSeconds() (HUD.Toast): how long a toast stays, by its length.
-- The server stays in charge of what any of them do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TruckHome = require(ReplicatedStorage.Shared.TruckHome)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)

local HudRules = {}

HudRules.SendHomeNear = 40 -- studs: closer to your truck than this, you'd drive it rather than send it
HudRules.DropConfirmSeconds = 3 -- the second press must come this soon after the first...
HudRules.DropConfirmGap = 0.3 -- ...but not sooner than this (a double tap or a mashed button isn't a yes)
HudRules.ToastMinSeconds = 2.5 -- the shortest toast...
HudRules.ToastMaxSeconds = 6 -- ...and the longest one, by its length
HudRules.ConfirmToastSeconds = 6 -- a toast that asks for a second press (the server waits 6 s for it)

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

-- What the Daily Goals button says: `done` of `total` goals and the
-- `streak` (days in a row with every goal done; not shown at 0):
-- "DAILY GOALS  1/3  ·  5-day streak". On a phone, where the corner's
-- second line (the clock, the pouch and this) would reach the Field Guide
-- button on a small screen, a streak drops the GOALS: "DAILY 1/3  ·  5-day
-- streak".
function HudRules.DailyLabel(done: number, total: number, streak: number, phone: boolean): string
	local days = math.floor(streak)
	if not (days > 0) or days == math.huge then -- no streak (or not a count: NaN, infinity)
		return string.format("DAILY GOALS  %d/%d", done, total)
	end
	local name = if phone then "DAILY " else "DAILY GOALS  "
	return string.format("%s%d/%d  ·  %d-day streak", name, done, total, days)
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

-- A count from a Player attribute as read (any type; nil while the save
-- loads): a whole number from 0, else 0.
local function count(value: unknown): number
	if type(value) ~= "number" or value ~= value then
		return 0 -- not a number, or NaN
	end
	return math.clamp(math.floor(value), 0, 999)
end

export type LoadChip = {
	shown: boolean,
	hands: string, -- "Hands 1/2"
	bed: string?, -- "Bed 4/6", "Bed full"; nil with no truck bed
	full: boolean, -- the bed is full: the chip turns amber
}

-- The load chip (HUD), from the Player attributes CarriedLogs, BedCount and
-- BedCapacity as read (any type), `handCapacity` (GameConfig.HandCapacity)
-- and whether a panel is open over the game (`modal`, HUD.SetModal):
--   * "Hands 1/2", then "Bed 4/6" while you have a truck with a bed
--     (BedCapacity above 0; the Scout ATV has none), "Bed full" and amber
--     once it's full;
--   * hidden while there's nothing in your hands or your bed: everyone
--     has an empty truck from the moment they join, and "Hands 0/2 · Bed
--     0/6" from minute one is noise (it shows once you pick up a log);
--     and while a panel is open, as the hint is.
function HudRules.LoadChip(
	carried: unknown,
	bedCount: unknown,
	bedCapacity: unknown,
	handCapacity: number,
	modal: boolean
): LoadChip
	local hands, inBed, room = count(carried), count(bedCount), count(bedCapacity)
	local full = room > 0 and inBed >= room
	local bed: string? = nil
	if room > 0 then
		bed = if full then "Bed full" else string.format("Bed %d/%d", inBed, room)
	end
	return {
		shown = not modal and (hands > 0 or inBed > 0),
		hands = string.format("Hands %d/%d", hands, count(handCapacity)),
		bed = bed,
		full = full,
	}
end

-- The HUD's loading card (under the ReplicatedFirst one, and showing once
-- that gives up): "Building the world..." until the server has made its
-- remotes (`remotes`: ReplicatedStorage has the Remotes folder, which
-- GameServer adds once MapBuilder is done), then "Loading your save..."
-- until the ProfileLoaded attribute (as read, any type) is true; then nil:
-- the card goes.
function HudRules.LoadingText(remotes: boolean, profileLoaded: unknown): string?
	if profileLoaded == true then
		return nil
	end
	return if remotes then "Loading your save..." else "Building the world..."
end

-- `text` as it reads: rich-text tags dropped and each entity (&amp;) one
-- character.
local function plainText(text: string): string
	local noTags = string.gsub(text, "<[^<>]*>", "")
	local plain = string.gsub(noTags, "&#?%w+;", "x")
	return plain
end

-- How many seconds a toast saying `message` stays up (HUD.Toast):
--   * long enough to read it: 1.6 s plus 0.045 s a character of its plain
--     text (rich-text tags stripped), from 2.5 s (20 characters or fewer)
--     to 6 s (98 or more);
--   * a confirm, one that asks for a second press ("... Press Send truck
--     home again to go ahead."), the full 6 s, as long as the server waits
--     for that press (VehicleService's recall);
--   * `seconds`, when the caller gives a number, instead (kept between
--     1 and 15 s).
function HudRules.ToastSeconds(message: string, seconds: number?): number
	if type(seconds) == "number" and seconds == seconds then -- not NaN
		return math.clamp(seconds, 1, 15)
	end
	local plain = plainText(message)
	if string.find(string.lower(plain), "again to ", 1, true) then
		return HudRules.ConfirmToastSeconds
	end
	local length = utf8.len(plain) or #plain -- characters ("·" is one), or bytes if it isn't UTF-8
	return math.clamp(1.6 + 0.045 * length, HudRules.ToastMinSeconds, HudRules.ToastMaxSeconds)
end

return HudRules
