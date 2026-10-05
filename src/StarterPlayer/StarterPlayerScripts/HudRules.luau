--!strict
-- HudRules: when the HUD's optional pieces show, as plain rules (no
-- Instances), so tests can check them. Each controller reads the rule for
-- its own piece:
--   * TutorialRunning(): Murph's tutorial is on. TutorialStep is 0 once
--     it's done or skipped; nil while the save loads counts as on (as
--     NPCController has it).
--   * DailyButton() (DailyUI): Daily Goals waits until the tutorial's done;
--     DailyLabel() is what its button says.
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
--   * ClockText() (WorldUI): the corner clock, "Day 14:05" / "Night 22:10".
--   * PadKeys, PadShortcut() (HUD.PadShortcut): the D-pad opens Daily
--     Goals, the Field Guide and Settings, only while nothing else has the
--     pad; PadGlyphs() and PadSelects(): their glyph chips show, and a
--     popup takes the selection, only while you're on a gamepad (or a TV).
-- The v2 core loop (V2_PLAN.md §4, Shared/CoreLoop) has no hands to
-- count (ShowsHands): what you hold or point at gets a tooltip instead
-- (WoodTooltip, "Oak log · 26 u³ · $39"), and the bed chip reads in u³
-- (BedChip, "Bed 41 / 96 u³ · $61"); LoadChipV2 picks which the HUD's
-- chip shows (ChipTooltip fits a phone). VolumeText, PriceText and CashText
-- are how u³ and dollars read everywhere (FieldGuide's, so the server's
-- toasts and the shop agree).
-- The server stays in charge of what any of them do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FieldGuide = require(ReplicatedStorage.Shared.FieldGuide)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TruckHome = require(ReplicatedStorage.Shared.TruckHome)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)

local HudRules = {}

HudRules.SendHomeNear = 40 -- studs: closer to your truck than this, you'd drive it rather than send it
HudRules.DropConfirmSeconds = 3 -- the second press must come this soon after the first...
HudRules.DropConfirmGap = 0.3 -- ...but not sooner than this (a double tap or a mashed button isn't a yes)
HudRules.ToastMinSeconds = 2.5 -- the shortest toast...
HudRules.ToastMaxSeconds = 6 -- ...and the longest one, by its length
HudRules.ConfirmToastSeconds = 6 -- a toast that asks for a second press (the server waits 6 s for it)

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
-- streak". DailyMark is the compact icon: just "1/3".
function HudRules.DailyMark(done: number, total: number): string
	local n = if done == done then math.floor(done) else 0
	local of = if total == total then math.floor(total) else 0
	return string.format("%d/%d", n, of)
end

function HudRules.DailyLabel(done: number, total: number, streak: number, phone: boolean): string
	local days = math.floor(streak)
	if not (days > 0) or days == math.huge then -- no streak (or not a count: NaN, infinity)
		return string.format("DAILY GOALS  %d/%d", done, total)
	end
	local name = if phone then "DAILY " else "DAILY GOALS  "
	return string.format("%s%d/%d  ·  %d-day streak", name, done, total, days)
end

-- "Send truck home": `onFoot` (you have a character and aren't driving),
-- `fromYou` studs between you and your truck (nil when it isn't streamed
-- in, which means it's far), and the server's TruckSlotDistance.
function HudRules.SendHome(onFoot: boolean, fromYou: number?, slotDistance: unknown): boolean
	return onFoot and (fromYou == nil or fromYou > HudRules.SendHomeNear) and TruckHome.Far(slotDistance)
end

-- The side button: "Send truck home" while SendHome would show it. With no
-- truck there is no button (the dealership sign says where to buy one).
function HudRules.TruckButton(ownsTruck: boolean, sendHome: boolean): (boolean, string)
	if not ownsTruck then
		return false, "Send truck home"
	end
	return sendHome, "Send truck home"
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
	local def = ItemCatalog.GetAxe(heldId)
	if def and (def.robux or def.quest) then
		return false -- a pass or quest axe stays in the inventory
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

-- The corner clock (WorldUI) for `clockTime`, an hour from 0 to 24
-- (Lighting.ClockTime): "Day 14:05", or "Night 22:10" while Gloam
-- Hollow's trees are out (WorldTime.IsNight).
function HudRules.ClockText(clockTime: number): string
	return string.format("%s %s", if WorldTime.IsNight(clockTime) then "Night" else "Day", WorldTime.Format(clockTime))
end

-- The gamepad's D-pad shortcuts (KeyCode names), one direction each.
-- DPadDown is "Drop axe" (AxeController's side button, UI-06). None of
-- them is a button anything else binds: ButtonA/B/X/Y, the shoulders,
-- the triggers and the thumbsticks belong to Roblox's controls, the world
-- prompts, the shops (B closes), the placer and the truck.
HudRules.PadKeys = {
	daily = "DPadUp", -- Daily Goals (DailyUI)
	guide = "DPadLeft", -- the Field Guide (FieldGuideUI), once you have it
	settings = "DPadRight", -- Settings (SettingsUI)
	dropAxe = "DPadDown", -- Drop axe (AxeController)
}

-- What's going on when a D-pad shortcut is pressed.
export type PadState = {
	available: boolean, -- what it opens is there for you (Daily after the tutorial, the guide once Murph gave it)
	typing: boolean, -- a text box has focus (the chat)
	selecting: boolean, -- a menu has the pad (GuiService.SelectedObject is set)
	modal: boolean, -- a shop panel is open (HUD.SetModal: the shops, the Store, the Field Guide)
	seated: boolean, -- you're in a seat (driving a truck)
	prompt: boolean, -- a world prompt on screen uses the same button
}

-- Whether a D-pad shortcut does its thing: only when it's available and
-- nothing else holds the pad.
function HudRules.PadShortcut(state: PadState): boolean
	return state.available and not (state.typing or state.selecting or state.modal or state.seated or state.prompt)
end

-- The glyph chips beside the corner buttons (which D-pad direction opens
-- what): only while you're on a gamepad, or on a TV (UITheme.Device()).
function HudRules.PadGlyphs(device: string): boolean
	return device == "console"
end

-- Whether opening a popup puts the gamepad's selection on its first
-- button (so A works at once): the same, so a mouse never gets a ring.
function HudRules.PadSelects(device: string): boolean
	return device == "console"
end

---------------------------------------------------------------------------
-- The v2 loop
---------------------------------------------------------------------------

-- How u³ and dollars read on the HUD (the rounding rules live in
-- FieldGuide, shared with the server's toasts): "26 u³" / "4.4 u³",
-- "$1.50/u³", "$39" (whole dollars, rounded as the sell pad pays them).
HudRules.VolumeText = FieldGuide.VolumeText
HudRules.VolumeNumber = FieldGuide.VolumeNumber
HudRules.PriceText = FieldGuide.PriceText
HudRules.CashText = FieldGuide.CashText

-- Whether the load chip counts logs in your hands ("Hands 1/2"): only in
-- the v1 loop. Under v2 you drag one piece at a time and its tooltip says
-- what it is.
function HudRules.ShowsHands(loop: number): boolean
	return loop ~= 2
end

-- A piece's tooltip, with or without its kind ("Oak log" or "Oak") and
-- its volume.
local function tooltipText(
	wood: WoodData.WoodDef,
	kind: unknown,
	volume: unknown,
	value: unknown,
	withKind: boolean,
	withVolume: boolean
): string
	local name = if withKind
		then string.format("%s %s", wood.displayName, if kind == "plank" then "plank" else "log")
		else wood.displayName
	local parts = { name }
	if withVolume and type(volume) == "number" and volume == volume then
		table.insert(parts, FieldGuide.VolumeText(volume))
	end
	if type(value) == "number" and value == value then
		table.insert(parts, FieldGuide.CashText(value))
	end
	return table.concat(parts, " · ")
end

-- The tooltip for a piece of wood you hold or point at, from its
-- attributes as read (any type): WoodId, Kind ("log" or "plank"), Volume
-- (u³) and Value ($): "Oak log · 26 u³ · $39". A part that isn't known
-- wood gets none (nil); a missing Volume or Value leaves that part out.
function HudRules.WoodTooltip(woodId: unknown, kind: unknown, volume: unknown, value: unknown): string?
	local wood = if type(woodId) == "string" then WoodData.Get(woodId) else nil
	if not wood then
		return nil
	end
	return tooltipText(wood, kind, volume, value, true, true)
end

export type BedChip = {
	shown: boolean,
	text: string, -- "Bed 41 / 96 u³ · $61"
	full: boolean, -- at or over the bed's room: the chip turns amber
}

-- The longest the bed chip's text gets, in characters: the v1 chip's
-- longest ("Hands 2/2 · Bed 12/12"), which HudLayout.spec fits beside the
-- hint on a small phone.
HudRules.BedChipMaxChars = 21

-- The v2 bed chip (HUD), from the truck's BedVolume (u³), the bed's room
-- (u³; nil or 0 when there's no figure for it) and BedValue ($), as read
-- (any type), and whether a panel is open (`modal`):
--   * "Bed 41 / 96 u³" with a room, "Bed 41 u³" without, then " · $61"
--     once the load is worth anything (CashText: what the pad would pay),
--     unless that would make it longer than BedChipMaxChars;
--   * amber (`full`) once the load reaches the room;
--   * hidden while the bed is empty (no noise from minute one, as the v1
--     chip) and while a panel is open.
function HudRules.BedChip(volume: unknown, room: unknown, value: unknown, modal: boolean): BedChip
	local function amount(n: unknown): number
		return if type(n) == "number" and n == n and n > 0 and n ~= math.huge then n else 0
	end
	local inBed, space, worth = amount(volume), amount(room), amount(value)
	local text = if space > 0
		then string.format("Bed %s / %s", FieldGuide.VolumeNumber(inBed), FieldGuide.VolumeText(space))
		else "Bed " .. FieldGuide.VolumeText(inBed)
	if worth > 0 then
		local withValue = text .. " · " .. FieldGuide.CashText(worth)
		if (utf8.len(withValue) or #withValue) <= HudRules.BedChipMaxChars then
			text = withValue
		end
	end
	return {
		shown = not modal and inBed > 0,
		text = text,
		full = space > 0 and inBed >= space,
	}
end

-- A piece you hold, as its attributes read (any type; HUD finds it by
-- its HeldBy attribute being you).
export type Held = { woodId: unknown, kind: unknown, volume: unknown, value: unknown }

-- The held piece's tooltip in the load chip: WoodTooltip, and on a phone
-- no longer than BedChipMaxChars (where HudLayout.spec fits the chip
-- beside the hint): first without its kind ("Frostwood · 4.4 u³ · $40"),
-- then without its volume too ("Frostwood · $40"). nil when it isn't
-- known wood.
function HudRules.ChipTooltip(held: Held, phone: boolean): string?
	local full = HudRules.WoodTooltip(held.woodId, held.kind, held.volume, held.value)
	if not full or not phone or (utf8.len(full) or #full) <= HudRules.BedChipMaxChars then
		return full
	end
	local wood = WoodData.Get(held.woodId :: string) :: WoodData.WoodDef -- known: it has a tooltip
	local shorter = tooltipText(wood, held.kind, held.volume, held.value, false, true)
	if (utf8.len(shorter) or #shorter) <= HudRules.BedChipMaxChars then
		return shorter
	end
	return tooltipText(wood, held.kind, held.volume, held.value, false, false)
end

-- The v2 load chip (HUD), where v1's reads "Hands 1/2 · Bed 4/6":
--   * while you hold a piece (`held`), its tooltip (ChipTooltip);
--   * else the bed chip (BedChip) from the BedVolume, the bed's room and
--     BedValue as read: it shows once TruckLoad (M1.6) publishes a
--     volume above 0, so until then nothing does;
--   * hidden while a panel is open, as the hint is.
-- `full` (amber) only for a bed at its room.
function HudRules.LoadChipV2(
	held: Held?,
	bedVolume: unknown,
	bedRoom: unknown,
	bedValue: unknown,
	modal: boolean,
	phone: boolean
): BedChip
	local tooltip = if held then HudRules.ChipTooltip(held, phone) else nil
	if tooltip then
		return { shown = not modal, text = tooltip, full = false }
	end
	return HudRules.BedChip(bedVolume, bedRoom, bedValue, modal)
end

return HudRules
