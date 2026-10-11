--!strict
-- NewsData: the lines of the "What's new in V1" panel (NewsUI), the in-game
-- update log. Content only; NewsLogic holds the rules. Edit here to change
-- the notes.
--
-- Keep each line SHORT: the phone card (667 x 375) fits seven rows and
-- truncates a headline or detail longer than about 50 characters (the spec
-- enforces both). Icons are frame-drawn names NewsUI knows; no uploads.

local NewsData = {}

export type Entry = { line: string, detail: string, icon: string }

NewsData.MaxLine = 52 -- characters, headline and detail alike
NewsData.MaxEntries = 7 -- what the phone card shows without running off the screen

-- Headline, a short second line, and a frame-drawn icon name. No uploaded
-- images. One table, so a later pass can edit the copy in one place.
NewsData.Entries = {
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
	{
		line = "Sparkworks sells logic pieces, belts and lasers.",
		detail = "Up the road past the Land Office. A plot first.",
		icon = "spark",
	},
	{
		line = "A sky island, reached by the gondola pass.",
		detail = "Ride the line up from the pass.",
		icon = "gondola",
	},
} :: { Entry }

return NewsData
