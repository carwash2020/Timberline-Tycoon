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
--   * Prints a ready-to-paste command that calibrates the economy model
--     from what you actually did: time from first chop to last sale, and
--     the logs sold by wood ("lune run tools/economy1 --calibrate ...").
--     Under the v2 core loop (GameServer passes CoreLoop.Active() to Init)
--     it's the live model's command, with the u³ sold by wood (WoodSold):
--     "lune run tools/economy --calibrate 612 birch=16 oak=24", and
--     "could afford" uses the v2 prices (ShopLogic.Price).
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
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
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
	"First upgrade bought",
	"Finished the tutorial",
	"Saw a next goal",
}
local STEP_NUMBER: { [string]: number } = {}
for i, name in ipairs(FUNNEL) do
	STEP_NUMBER[name] = i
end
-- The same list, for the specs. New names go at the end only.
MilestoneService.Funnel = FUNNEL

local IS_STUDIO = RunService:IsStudio()
local REPORT_EVERY = 60 -- seconds, Studio only
local CALIBRATE_MIN_LOGS = 10 -- don't suggest calibrating from less than this
local CALIBRATE_MIN_PIECES = 10 -- (v2: pieces sold)
local CALIBRATE_MIN_SECONDS = 120

type Session = {
	profile: Profile,
	startedAt: number,
	earned: number,
	earnedAtLastReport: number,
	seen: { [string]: boolean },
	-- For calibrating the economy model (tools/economy.luau).
	firstChopAt: number?,
	lastSaleAt: number?,
	soldByWood: { [string]: number },
	-- The same for the v2 model (tools/economy): u³ by wood, pieces sold.
	volumeByWood: { [string]: number },
	piecesSold: number,
}

local sessions: { [Player]: Session } = {}
local notify: ((Player, string) -> ())? = nil
local loop = 1 -- the core loop that runs (Init)

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

-- The calibrate command for `seconds` from first chop to last sale and
-- what was sold by wood (`byWood`: logs under v1, u³ under v2, rounded to
-- whole numbers), or nil from too little (`count`: logs under v1, pieces
-- under v2; or too short a session):
-- "lune run tools/economy1 --calibrate 612 birch=16 oak=24" (v1),
-- "lune run tools/economy --calibrate 612 birch=16 oak=24" (v2, u³).
function MilestoneService.CalibrateLine(
	seconds: number,
	byWood: { [string]: number },
	count: number,
	activeLoop: number
): string?
	local v2 = activeLoop == 2
	local parts, total = {}, 0
	for woodId, amount in pairs(byWood) do
		local n = if v2 then math.floor(amount + 0.5) else amount
		if not v2 or n >= 1 then
			table.insert(parts, string.format("%s=%d", woodId, n))
		end
		total += amount
	end
	local enough = if v2 then count >= CALIBRATE_MIN_PIECES and #parts > 0 else total >= CALIBRATE_MIN_LOGS
	if not enough or seconds < CALIBRATE_MIN_SECONDS then
		return nil
	end
	table.sort(parts)
	return string.format(
		"lune run tools/%s --calibrate %d %s",
		if v2 then "economy" else "economy1",
		math.floor(seconds),
		table.concat(parts, " ")
	)
end

-- The session's calibrate command, or nil if it doesn't have enough sales
-- yet.
local function calibrationCommand(session: Session): string?
	local first, last = session.firstChopAt, session.lastSaleAt
	if not first or not last then
		return nil
	end
	local seconds = math.floor(last - first)
	if loop == 2 then
		return MilestoneService.CalibrateLine(seconds, session.volumeByWood, session.piecesSold, 2)
	end
	return MilestoneService.CalibrateLine(seconds, session.soldByWood, 0, 1)
end

-- `player`'s calibrate command this session so far, or nil.
function MilestoneService.CalibrationFor(player: Player): string?
	local session = sessions[player]
	return if session then calibrationCommand(session) else nil
end

local function printCalibration(player: Player, session: Session)
	local command = calibrationCommand(session)
	if command then
		print(string.format("[Stopwatch] %s: to calibrate the economy model, run in the repo folder:", player.Name))
		print("    " .. command)
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

-- `notifyFn` shows a toast to one player (GameServer's notify);
-- `activeLoop` is the core loop that runs (CoreLoop.Active(); 1 when not
-- given).
function MilestoneService.Init(notifyFn: (Player, string) -> (), activeLoop: number?)
	notify = notifyFn
	loop = if activeLoop == 2 then 2 else 1
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
					printCalibration(player, session)
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
		soldByWood = {},
		volumeByWood = {},
		piecesSold = 0,
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
	if name == "First chop" then
		session.firstChopAt = os.clock()
	end
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
	local price = if axe then ShopLogic.Price(axe, loop) else 0
	if axe and not session.seen["afford:" .. axe.id] and profile.cash >= price then
		session.seen["afford:" .. axe.id] = true
		stopwatch(player, session, string.format("Could afford the %s (%s)", axe.displayName, Util.formatCash(price)))
		MilestoneService.Mark(player, "Could afford an upgrade")
	end
end

-- Call after a sale with the logs sold, counted by wood id.
function MilestoneService.LogsSold(player: Player, byWood: { [string]: number })
	local session = sessions[player]
	if not session then
		return
	end
	session.lastSaleAt = os.clock()
	for woodId, count in pairs(byWood) do
		session.soldByWood[woodId] = (session.soldByWood[woodId] or 0) + count
	end
end

-- Call after a v2 sale: `pieces` sold, their u³ by wood id (the v2
-- model's calibrate line).
function MilestoneService.WoodSold(player: Player, pieces: number, volumeByWood: { [string]: number })
	local session = sessions[player]
	if not session then
		return
	end
	session.lastSaleAt = os.clock()
	session.piecesSold += math.max(0, math.floor(pieces))
	for woodId, volume in pairs(volumeByWood) do
		if type(volume) == "number" and volume == volume and volume > 0 and volume ~= math.huge then
			session.volumeByWood[woodId] = (session.volumeByWood[woodId] or 0) + volume
		end
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
		printCalibration(player, session)
	end
end

return MilestoneService
