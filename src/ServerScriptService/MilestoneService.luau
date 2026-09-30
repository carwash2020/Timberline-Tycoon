--!strict
-- MilestoneService: measures how fast players get through the core loop.
--
-- In Studio playtests (the stopwatch):
--   * Prints each milestone the first time it happens this session, with the
--     time since the save loaded: "[Stopwatch] Connor: First sale at 2:41".
--     The same line pops up as a toast.
--   * Prints "could afford <next axe>" the moment cash first covers each axe
--     you don't own yet: that's the pace check from GAME_DESIGN §14.8.
--   * Once a minute prints cash earned and cash per minute.
--   * On leaving, prints a one-line session summary.
--
-- On live servers:
--   * Logs the steps as Roblox's onboarding funnel (Creator Hub ->
--     Analytics -> Funnels), each step once per player ever (remembered in
--     profile.onboarding). EconomyService logs every cash change separately.
--
-- Also keeps profile.stats.playtimeMin up to date.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local ProfileService = require(script.Parent.ProfileService)

type Profile = ProfileService.Profile

local MilestoneService = {}

-- Onboarding funnel, in order. Steps are logged by name via Mark().
-- Add new steps at the END only: Roblox charts them by their number.
local FUNNEL: { string } = {
	"Joined",
	"First chop",
	"First tree felled",
	"First log picked up",
	"First log loaded",
	"First sale",
	"Could afford an upgrade",
}
local STEP_NUMBER: { [string]: number } = {}
for i, name in ipairs(FUNNEL) do
	STEP_NUMBER[name] = i
end

local IS_STUDIO = RunService:IsStudio()
local REPORT_EVERY = 60 -- seconds, Studio only

type Session = {
	profile: Profile,
	startedAt: number,
	earned: number,
	earnedAtLastReport: number,
	seen: { [string]: boolean },
}

local sessions: { [Player]: Session } = {}
local notify: ((Player, string) -> ())? = nil

local function clock(seconds: number): string
	seconds = math.floor(seconds)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function perMinute(amount: number, seconds: number): string
	if seconds < 1 then
		return "$0/min"
	end
	return Util.formatCash(amount * 60 / seconds) .. "/min"
end

local function stopwatch(player: Player, session: Session, text: string)
	if not IS_STUDIO then
		return
	end
	local line = string.format("%s at %s", text, clock(os.clock() - session.startedAt))
	print(string.format("[Stopwatch] %s: %s", player.Name, line))
	local send = notify
	if send then
		send(player, "⏱ " .. line)
	end
end

local function logFunnelStep(player: Player, session: Session, name: string)
	local step = STEP_NUMBER[name]
	if step == nil or session.profile.onboarding[name] then
		return
	end
	session.profile.onboarding[name] = true
	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
	if not ok then
		warn("[MilestoneService] Analytics funnel step failed: " .. tostring(err))
	end
end

-- `notifyFn` shows a toast to one player (GameServer's notify).
function MilestoneService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
	if IS_STUDIO then
		task.spawn(function()
			while true do
				task.wait(REPORT_EVERY)
				for player, session in pairs(sessions) do
					local elapsed = os.clock() - session.startedAt
					local lastMinute = session.earned - session.earnedAtLastReport
					session.earnedAtLastReport = session.earned
					print(
						string.format(
							"[Stopwatch] %s: %s in, earned %s this session (%s overall, %s in the last minute)",
							player.Name,
							clock(elapsed),
							Util.formatCash(session.earned),
							perMinute(session.earned, elapsed),
							perMinute(lastMinute, REPORT_EVERY)
						)
					)
				end
			end
		end)
	end
end

-- Call once the player's save has loaded.
function MilestoneService.Start(player: Player, profile: Profile)
	local session: Session = {
		profile = profile,
		startedAt = os.clock(),
		earned = 0,
		earnedAtLastReport = 0,
		seen = {},
	}
	sessions[player] = session
	MilestoneService.Mark(player, "Joined")
end

-- Records a milestone (one of the FUNNEL names). Only the first time per
-- session reaches the stopwatch, and only the first time ever reaches the
-- analytics funnel.
function MilestoneService.Mark(player: Player, name: string)
	local session = sessions[player]
	if not session or session.seen[name] then
		return
	end
	session.seen[name] = true
	if name ~= "Joined" then
		stopwatch(player, session, name)
	end
	logFunnelStep(player, session, name)
end

-- Call after cash is added. Tracks session earnings and announces when the
-- player can first afford their next axe (axes are sold in order).
function MilestoneService.CashEarned(player: Player, amount: number)
	local session = sessions[player]
	if not session then
		return
	end
	session.earned += amount
	local profile = session.profile
	local axe = ItemCatalog.NextAxe(profile.bestAxeTier)
	if axe and not session.seen["afford:" .. axe.id] and profile.cash >= axe.priceCash then
		session.seen["afford:" .. axe.id] = true
		stopwatch(
			player,
			session,
			string.format("Could afford the %s (%s)", axe.displayName, Util.formatCash(axe.priceCash))
		)
		MilestoneService.Mark(player, "Could afford an upgrade")
	end
end

-- Call when the player leaves.
function MilestoneService.Stop(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if not session then
		return
	end
	local elapsed = os.clock() - session.startedAt
	session.profile.stats.playtimeMin += math.floor(elapsed / 60 + 0.5)
	if IS_STUDIO then
		print(
			string.format(
				"[Stopwatch] %s: session over after %s. Earned %s (%s).",
				player.Name,
				clock(elapsed),
				Util.formatCash(session.earned),
				perMinute(session.earned, elapsed)
			)
		)
	end
end

return MilestoneService
