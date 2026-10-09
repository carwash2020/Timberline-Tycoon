--!strict
-- NewsLogic: the "What's new in V1" lines, and when the panel shows itself.
-- The seen flag is profile.onboarding["News:V1"] (ProfileSchema already
-- stores that table). No new save field.

local NewsLogic = {}

NewsLogic.Key = "News:V1"

export type Entry = { line: string, detail: string, icon: string }

-- Headline, a short second line, and a frame-drawn icon name. No uploaded
-- images. One table, so a later pass can edit the copy in one place.
NewsLogic.Entries = {
	{
		line = "A new island map, with the Bayou and Red Mesa.",
		detail = "Two regions past the old town.",
		icon = "map",
	},
	{ line = "Mine the cave for ore.", detail = "Clear rubble, then follow the vein.", icon = "mine" },
	{ line = "Build from blueprints.", detail = "Place a plan, then raise the walls.", icon = "blueprint" },
	{
		line = "Foreman Rook's daily jobs, with streaks.",
		detail = "Three jobs a day. A streak pays more.",
		icon = "daily",
	},
	{ line = "Temper your axe.", detail = "A hotter edge bites harder.", icon = "temper" },
	{ line = "Sparkworks logic pieces.", detail = "Wire switches, gates and lamps.", icon = "spark" },
	{
		line = "A sky island, reached by the gondola pass.",
		detail = "Ride the line up from the pass.",
		icon = "gondola",
	},
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
