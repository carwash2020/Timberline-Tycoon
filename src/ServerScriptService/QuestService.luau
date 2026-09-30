--!strict
-- QuestService: Murph's tutorial (Shared/TutorialData), server side.
--   * The current step lives in the save (tutorialStep, tutorialProgress)
--     and is mirrored on the TutorialStep (0 = finished or skipped) and
--     TutorialProgress player attributes, which QuestUI draws.
--   * Game code reports what happened with QuestService.Event(player,
--     event, amount); only the current step's event counts.
--   * A finished step pays its rewardCash through EconomyService.
--   * The SkipTutorial remote ends it early, without rewards. Saves from
--     before the tutorial that already own a better axe skip it.
--   * Each step reached is logged once as a "Tutorial" analytics funnel.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialData = require(ReplicatedStorage.Shared.TutorialData)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

type Profile = ProfileService.Profile
type TutorialEvent = TutorialData.TutorialEvent

local QuestService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end

local function publish(player: Player, profile: Profile)
	player:SetAttribute("TutorialStep", if profile.tutorialDone then 0 else profile.tutorialStep)
	player:SetAttribute("TutorialProgress", profile.tutorialProgress)
end

-- Analytics must never break gameplay.
local function analytics(fn: () -> ())
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		warn("[QuestService] Analytics failed: " .. tostring(err))
	end
end

-- Logs funnel step `index` ("reached step N") once per player ever.
local function logFunnelStep(player: Player, profile: Profile, index: number, name: string)
	local key = "Tutorial:" .. name
	if profile.onboarding[key] then
		return
	end
	profile.onboarding[key] = true
	analytics(function()
		AnalyticsService:LogFunnelStepEvent(player, "Tutorial", nil, index, name)
	end)
end

local function finish(player: Player, profile: Profile, how: "completed" | "skipped" | "bypassed")
	profile.tutorialDone = true
	profile.tutorialProgress = 0
	publish(player, profile)
	if how == "completed" then
		logFunnelStep(player, profile, #TutorialData.Steps + 1, "Done")
		MilestoneService.Mark(player, "Finished the tutorial")
	end
	analytics(function()
		AnalyticsService:LogCustomEvent(player, "Tutorial_" .. how, profile.tutorialStep)
	end)
end

-- Starts step `index`, skipping any the player is already past; finishes
-- the tutorial after the last one.
local function enterStep(player: Player, profile: Profile, index: number)
	local step = TutorialData.Steps[index]
	while step and TutorialData.AlreadyDone(step, profile.bestAxeTier) do
		index += 1
		step = TutorialData.Steps[index]
	end
	if not step then
		finish(player, profile, "completed")
		return
	end
	profile.tutorialStep = index
	profile.tutorialProgress = 0
	logFunnelStep(player, profile, index, step.id)
	publish(player, profile)
end

-- Call once the player's save has loaded.
function QuestService.Start(player: Player, profile: Profile)
	if profile.tutorialDone then
		publish(player, profile)
		return
	end
	if profile.bestAxeTier >= 2 and profile.tutorialStep == 1 and profile.tutorialProgress == 0 then
		finish(player, profile, "bypassed") -- a save from before the tutorial existed
		return
	end
	local step = TutorialData.Steps[profile.tutorialStep]
	if not step or TutorialData.AlreadyDone(step, profile.bestAxeTier) then
		enterStep(player, profile, if step then profile.tutorialStep + 1 else 1)
	elseif profile.tutorialStep == 1 and profile.tutorialProgress == 0 then
		enterStep(player, profile, 1) -- logs the funnel's first step
	else
		publish(player, profile)
	end
end

-- Something tutorial-worthy happened. `amount` is how many (logs, for the
-- log events); default 1.
function QuestService.Event(player: Player, event: TutorialEvent, amount: number?)
	local profile = ProfileService.GetProfile(player)
	if not profile or profile.tutorialDone then
		return
	end
	local step = TutorialData.Steps[profile.tutorialStep]
	if not step or step.event ~= event then
		return
	end
	profile.tutorialProgress += amount or 1
	if profile.tutorialProgress < step.count then
		publish(player, profile)
		return
	end
	local reward = step.rewardCash
	if reward and reward > 0 then
		EconomyService.AddCash(player, reward, "tutorial: " .. step.id, "tutorial")
		notify(player, string.format("Murph chipped in %s!", Util.formatCash(reward)))
	end
	enterStep(player, profile, profile.tutorialStep + 1)
end

local function onSkip(player: Player)
	if not RateLimiter.Allow(player, "SkipTutorial") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if profile and not profile.tutorialDone then
		finish(player, profile, "skipped")
		notify(player, "Tutorial skipped. Talk to Murph by the spawn any time.")
	end
end

-- `notifyFn` shows a toast (GameServer's notify).
function QuestService.Init(skipRemote: RemoteEvent, notifyFn: (Player, string) -> ())
	notify = notifyFn
	skipRemote.OnServerEvent:Connect(onSkip)
end

return QuestService
