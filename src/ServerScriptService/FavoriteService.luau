--!strict
-- FavoriteService: the one-time favorite reminder (rules in
-- Shared/FavoriteLogic). Each joined player is checked every few seconds; the
-- toast shows once ever, after 10 minutes of play, never during a tutorial
-- step or a dialogue. The flag is marked when the toast is sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FavoriteLogic = require(ReplicatedStorage.Shared.FavoriteLogic)
local NPCTalkService = require(script.Parent.NPCTalkService)
local ProfileService = require(script.Parent.ProfileService)

local FavoriteService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local clock: () -> number = os.clock
local started: { [Player]: number } = {}

-- Specs: a fake clock.
function FavoriteService.SetClock(fn: () -> number)
	clock = fn
end

-- One look at `player`: shows the toast if it is due. True when it showed.
function FavoriteService.Check(player: Player): boolean
	local began = started[player]
	local profile = ProfileService.GetProfile(player)
	if began == nil or profile == nil then
		return false
	end
	if type(profile.onboarding) ~= "table" then
		profile.onboarding = {}
	end
	local due = FavoriteLogic.Due({
		playSeconds = clock() - began,
		shownBefore = FavoriteLogic.WasShown(profile.onboarding),
		tutorialDone = profile.tutorialDone == true,
		talking = NPCTalkService.IsTalking(player),
	})
	if not due then
		return false
	end
	FavoriteLogic.Mark(profile.onboarding)
	notify(player, FavoriteLogic.Text)
	return true
end

-- Starts the player's play clock (no loop: Start adds that; specs call this).
function FavoriteService.Begin(player: Player)
	started[player] = clock()
end

-- Call once the player's save has loaded. A player who already saw it needs no loop.
function FavoriteService.Start(player: Player, profile: ProfileService.Profile)
	if type(profile.onboarding) == "table" and FavoriteLogic.WasShown(profile.onboarding) then
		return
	end
	FavoriteService.Begin(player)
	local at = started[player]
	task.spawn(function()
		while started[player] == at and player.Parent == Players do
			task.wait(FavoriteLogic.CheckEvery)
			if started[player] ~= at then
				return
			end
			if FavoriteService.Check(player) then
				started[player] = nil
				return
			end
		end
	end)
end

function FavoriteService.Stop(player: Player)
	started[player] = nil
end

function FavoriteService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
end

return FavoriteService
