--!strict
-- NewsLogic: the "What's new in V1" lines, and when the panel shows itself.
-- The seen flag is profile.onboarding["News:V1"] (ProfileSchema already
-- stores that table). No new save field.

local NewsData = require(script.Parent.NewsData)

local NewsLogic = {}

NewsLogic.Key = "News:V1"

export type Entry = NewsData.Entry

-- The lines are in Shared/NewsData (content only, one place to edit).
NewsLogic.Entries = NewsData.Entries

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
