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
-- has not closed the panel yet. A player still in the tutorial (step above
-- 0, or still loading) waits; a brand-new player never gets it (IsBrandNew,
-- marked seen at join). Opening from Settings does not use this.
function NewsLogic.ShouldAutoShow(step: unknown, seen: boolean): boolean
	if seen then
		return false
	end
	return type(step) == "number" and step == 0
end

-- A brand-new save has nothing new to catch up on: it is still in its
-- first tutorial (tutorialDone false) and is neither a returning player's
-- refresher (a save from before the loop changed: tutorialRefresher) nor a
-- replay of the lessons (tutorialReplay). NewsService marks those seen at
-- join so the panel does not open over the farewell when the tutorial ends.
-- A returning player (tutorialDone true, or a refresher) keeps the panel.
function NewsLogic.IsBrandNew(tutorialDone: unknown, refresher: unknown, replay: unknown): boolean
	return tutorialDone ~= true and refresher ~= true and replay ~= true
end

-- Idempotent. `onboarding` is the save's existing table.
function NewsLogic.Mark(onboarding: { [string]: boolean })
	onboarding[NewsLogic.Key] = true
end

return NewsLogic
