--!strict
-- PickerMotion: the numbers behind the blueprint picker's motion (T420). Pure.
-- The picker slides up while its backdrop fades in, tabs and cards answer a hover and a press
-- with a small scale, a selected tab or card warms up, and the cards of a tab
-- pop in one after another. Everything is a short one-shot tween (no loops, no
-- per-frame work) and at most MaxAnimated cards animate. With the player's
-- "calm the screen" setting on (SettingsLogic.ReduceFlashing: Reduce flashing,
-- or camera shake off) nothing moves: every duration, slide and delay is zero and
-- the scale stays 1, so the picker simply appears.

local SettingsLogic = require(script.Parent.SettingsLogic)

local PickerMotion = {}

export type Effect = { seconds: number, slide: number?, scale: number?, fromScale: number? }

PickerMotion.Open = { seconds = 0.22, slide = 28 } :: Effect -- the panel rises 28 px and fades in
PickerMotion.Close = { seconds = 0.14, slide = 18 } :: Effect -- and sinks 18 px as it goes
PickerMotion.Hover = { seconds = 0.12, scale = 1.04 } :: Effect
PickerMotion.Press = { seconds = 0.07, scale = 0.97 } :: Effect
PickerMotion.Select = { seconds = 0.14 } :: Effect -- the edge and fill of a selected tab or card
PickerMotion.TabIn = { seconds = 0.16, slide = 10 } :: Effect -- a tab's label nudges when it is chosen
PickerMotion.CardIn = { seconds = 0.18, fromScale = 0.9 } :: Effect -- a card pops in from 90%

PickerMotion.Stagger = 0.03 -- seconds between one card and the next
PickerMotion.MaxStagger = 0.24 -- the last animated card is never later than this
PickerMotion.MaxAnimated = 9 -- cards past this just appear

function PickerMotion.Reduced(reduceAttr: unknown, shakeAttr: unknown): boolean
	return SettingsLogic.ReduceFlashing(reduceAttr, shakeAttr)
end

function PickerMotion.Seconds(effect: Effect, reduced: boolean): number
	return if reduced then 0 else effect.seconds
end

function PickerMotion.Slide(effect: Effect, reduced: boolean): number
	return if reduced then 0 else (effect.slide or 0)
end

-- The size multiplier of a tab or card: 1 at rest, a little up under the
-- pointer, a little down while pressed. Always 1 on a calm screen.
function PickerMotion.Scale(hovering: boolean, pressed: boolean, reduced: boolean): number
	if reduced then
		return 1
	end
	if pressed then
		return PickerMotion.Press.scale :: number
	end
	return if hovering then PickerMotion.Hover.scale :: number else 1
end

-- Whether card number `index` (1-based) animates in.
function PickerMotion.Animates(index: number, reduced: boolean): boolean
	return not reduced and index >= 1 and index <= PickerMotion.MaxAnimated
end

-- Seconds to wait before card `index` starts: 0 for the first, one stagger more
-- for each after it, never past MaxStagger.
function PickerMotion.Delay(index: number, reduced: boolean): number
	if reduced or index <= 1 then
		return 0
	end
	return math.min((index - 1) * PickerMotion.Stagger, PickerMotion.MaxStagger)
end

-- From the picker starting to open until the last animated card has landed.
function PickerMotion.OpenTotal(reduced: boolean): number
	if reduced then
		return 0
	end
	-- The cards start as the panel starts, so the two overlap.
	return math.max(
		PickerMotion.Open.seconds,
		PickerMotion.Delay(PickerMotion.MaxAnimated, false) + PickerMotion.CardIn.seconds
	)
end

return PickerMotion
