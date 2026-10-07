--!strict
-- QualityProfile: the player's own graphics choice, the screen that asks for
-- it, and how it meets what the device can do. Pure, so the server, the
-- client and the tests read the same rules.
--
-- Connor (7 October 2026), on the phone-versus-Xbox/PC problem: "just let them
-- pick between lower quality (Phone) or higher quality at launch." So there
-- are two choices, saved on the account (SettingsLogic quality: "unset" until
-- chosen, then "low" or "high"), asked once on the join screen and changeable
-- from Settings. The choice changes only how much DRESSING the client builds
-- and draws (QualityBudgets): never a price, a hover tag, a hitbox, a grab or
-- what a box does. The device's own detection (Roblox's graphics level, a
-- touch-only screen: QualityBudgets.TierFor) stays and still sets how often the
-- cosmetic loops run.
--
--   saved "low"    -> the "low" budget, whatever the device.
--   saved "high"   -> the device's own tier, never a heavier one than it
--                     reports, except that a device that reports "low" (a
--                     phone, a tablet, Roblox's own level 1 to 4) is allowed
--                     the "medium" tier: the high WORLD (box windows, decor)
--                     with the calm motion of medium. Picking Higher on a weak
--                     device is allowed; the Roblox graphics level logic is
--                     untouched (it is the device's tier).
--   saved "unset"  -> the device's own tier until the player picks.

local QualityProfile = {}

export type Saved = "unset" | "low" | "high"
export type Choice = "low" | "high"
type Tier = "low" | "medium" | "high"

QualityProfile.Unset = "unset" :: Saved
QualityProfile.Choices = { "low", "high" } :: { Choice }

export type Option = {
	id: Choice,
	title: string, -- the card's heading
	device: string, -- who it suits
	button: string, -- the whole name on one line
	blurb: string, -- one line on what it does
	row: string, -- the Settings row's word
}

-- What the join screen and the Settings row say. One line for each choice.
QualityProfile.Options = {
	low = {
		id = "low" :: Choice,
		title = "Lower quality",
		device = "best for phones",
		button = "Lower quality (best for phones)",
		blurb = "Simpler boxes, less scenery and softer effects. Smoothest on a phone.",
		row = "Lower",
	},
	high = {
		id = "high" :: Choice,
		title = "Higher quality",
		device = "Xbox, PC, tablets",
		button = "Higher quality (Xbox, PC, tablets)",
		blurb = "The full look: see the real item in every shop box, all the scenery.",
		row = "Higher",
	},
} :: { [string]: Option }

QualityProfile.PickerTitle = "How should the game look?"
QualityProfile.PickerHint = "You can change this any time in Settings."
QualityProfile.RecommendedTag = "RECOMMENDED FOR THIS DEVICE"

function QualityProfile.IsChoice(value: unknown): boolean
	return value == "low" or value == "high"
end

-- A value read from a save or an attribute, as a Saved.
function QualityProfile.Sanitize(value: unknown): Saved
	if value == "low" or value == "high" then
		return value :: Saved
	end
	return "unset"
end

-- True when the join screen should show: nothing has been chosen on this account.
function QualityProfile.NeedsPicker(saved: unknown): boolean
	return not QualityProfile.IsChoice(saved)
end

-- What the join screen pre-selects. A touch-only device (a phone, or a tablet
-- with no keyboard) gets Lower; a console or a PC gets Higher. A save that
-- once picked the old Graphics override "low" keeps that leaning.
function QualityProfile.Recommended(touchOnly: boolean, legacyGraphics: unknown?): Choice
	if legacyGraphics == "low" then
		return "low"
	elseif legacyGraphics == "medium" or legacyGraphics == "high" then
		return "high"
	end
	return if touchOnly then "low" else "high"
end

-- The choice in force: what was saved, or the recommendation until then.
function QualityProfile.Resolve(saved: unknown, recommended: Choice): Choice
	if saved == "low" or saved == "high" then
		return saved :: Choice
	end
	return recommended
end

-- The other choice (what a Settings row press switches to).
function QualityProfile.Other(choice: Choice): Choice
	return if choice == "low" then "high" else "low"
end

-- The name of the Settings row's text: "Graphics: Lower" / "Graphics: Higher".
-- An unchosen save shows the device's recommendation, as that is what it follows.
function QualityProfile.RowText(saved: unknown, recommended: Choice): string
	local choice = QualityProfile.Resolve(saved, recommended)
	return "Graphics: " .. QualityProfile.Options[choice].row
end

-- The tier (QualityBudgets) that runs, from the player's saved choice and the
-- tier the device's own detection gave (QualityBudgets.TierFor). See the header.
function QualityProfile.TierFor(saved: unknown, deviceTier: string): Tier
	local device: Tier = if deviceTier == "low" or deviceTier == "medium" then deviceTier :: Tier else "high"
	if saved == "low" then
		return "low"
	elseif saved == "high" then
		return if device == "low" then "medium" else device
	end
	return device
end

return QualityProfile
