--!strict
-- NewsData: the lines of the "What's new" panel (NewsUI), the in-game
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
		line = "New vehicles with wheels on both sides.",
		detail = "Every truck rebuilt. See the Dealership.",
		icon = "gondola",
	},
	{ line = "New items in the stores.", detail = "Fresh stock at Hearth, Sparkworks and the shed.", icon = "spark" },
	{ line = "Refreshed shop icons.", detail = "Clearer pictures on every shelf and sign.", icon = "blueprint" },
	{
		line = "Axes are held the right way round.",
		detail = "Every head points forward in your hand.",
		icon = "temper",
	},
	{ line = "Faster first load.", detail = "The world builds in the background as you go.", icon = "daily" },
	{ line = "The Bayou and Red Mesa regions.", detail = "Two regions past the old town.", icon = "map" },
	{ line = "Mine the cave for ore.", detail = "Clear rubble, then follow the vein.", icon = "mine" },
} :: { Entry }

return NewsData
