--!strict
-- NewsLogic: the "What's new in V1" lines, and when the panel shows itself.
-- The seen flag is profile.onboarding["News:V1"] (ProfileSchema already
-- stores that table). No new save field.

local NewsLogic = {}

NewsLogic.Key = "News:V1"

export type Entry = { line: string, icon: string }

-- Short lines and a frame-drawn icon name. No uploaded images.
NewsLogic.Entries = {
	{ line = "Trees you can chop now stand around the spawn.", icon = "tree" },
	{ line = "Unload your base from SAVES, then pick a pad.", icon = "base" },
	{ line = "Drop the axe with B, Q, or a long press.", icon = "axe" },
	{ line = "Shop boxes show the real item in a window.", icon = "box" },
	{ line = "Choose Lower or Higher quality when you join.", icon = "gear" },
	{ line = "Talk opens a box, and folks turn to face you.", icon = "talk" },
} :: { Entry }

-- True only after the tutorial is finished (TutorialStep 0) and this save
-- has not closed the panel yet. A new player (step above 0, or still
-- loading) skips it. Opening from Settings does not use this.
function NewsLogic.ShouldAutoShow(step: unknown, seen: boolean): boolean
	if seen then
		return false
	end
	return type(step) == "number" and step == 0
end

-- Idempotent. `onboarding` is the save's existing table.
function NewsLogic.Mark(onboarding: { [string]: boolean })
	onboarding[NewsLogic.Key] = true
end

return NewsLogic
