--!strict
-- FavoriteLogic: the one-time "favorite the game" reminder. Pure.
--
-- Roblox has no API that favorites an EXPERIENCE for a player: the favorite
-- prompt (AvatarEditorService:PromptSetFavorite) is for avatar assets and
-- bundles, and SocialService only prompts game invites. So the reminder is a
-- toast that points at the star on the game's page.
--
--   * Due after 10 minutes of play in the session, once per player ever
--     (the saved flag onboarding["Reminder:Favorite"], account-wide).
--   * Never during a tutorial step (the tutorial is not done) or a dialogue.
--     Blocked at 10 minutes, it simply waits and is checked again.

local FavoriteLogic = {}

FavoriteLogic.Key = "Reminder:Favorite"
FavoriteLogic.AfterSeconds = 600
FavoriteLogic.CheckEvery = 15 -- seconds between checks
FavoriteLogic.Text = "Enjoying Timberline Tycoon? Tap the star on the game's page to favorite it and find it again."

export type State = {
	playSeconds: number, -- seconds played this session
	shownBefore: boolean, -- the saved flag
	tutorialDone: boolean, -- false while a tutorial step is running
	talking: boolean, -- a dialogue box is open
}

-- True when the toast should show now.
function FavoriteLogic.Due(state: State): boolean
	if state.shownBefore then
		return false
	end
	if state.playSeconds < FavoriteLogic.AfterSeconds then
		return false
	end
	return state.tutorialDone and not state.talking
end

-- Idempotent. `onboarding` is the save's existing flag table.
function FavoriteLogic.Mark(onboarding: { [string]: boolean })
	onboarding[FavoriteLogic.Key] = true
end

function FavoriteLogic.WasShown(onboarding: { [string]: boolean }): boolean
	return onboarding[FavoriteLogic.Key] == true
end

return FavoriteLogic
