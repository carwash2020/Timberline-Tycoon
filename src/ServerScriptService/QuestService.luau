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
--   * TutorialSeen (client -> server, "build" or "land") reports opening
--     the hammer's blueprint list or the Land panel; only the current step's event counts.
--   * Each step reached is logged once as a "Tutorial" analytics funnel
--     (which also lets saves made before a new step was inserted find
--     their place again).
--   * Trees regrow on their own timer. Stumps are not held for a plant step.
--   * The steps are TutorialData.ForLoop(loop), for the core loop that
--     runs (GameServer passes CoreLoop.Active() to Init; 1, the v1 steps,
--     when not given). The v2 loop's steps (StepsV2: fell, drag, sell,
--     plot, then the truck) count the v2 events, reported
--     through QuestService.Event like the v1 ones:
--       woodGrabbed   GameServer, from GrabService.Hooks.onGrab
--       woodSold      QuestService.WoodSold (SellService's onSold): pieces
--       woodSoldCash  the same sale's whole dollars credited, right after
--       axeBought     ShopService, as today
--       treeFelled    today the v1 chop path (GameServer); with section
--                     trees (M1.3) SectionTrees' OnFelled must call
--                     QuestService.Event(feller, "treeFelled") once per
--                     tree, for the feller ForestLogic.Feller picks
--       woodLoaded    TruckLoad (M1.6) must call
--                     QuestService.Event(owner, "woodLoaded") when a piece
--                     of the owner's comes to rest in their own BedZone
--       truckBought   ShopService: the truck's box was bought
--       padPlaced     VehicleService (Hooks.padEvent, set by GameServer):
--                     the box's pad went down on the plot
--       truckSpawned  the same hook: a pad's button brought the truck out
--     Under the v1 loop the v2 events count for nothing (no v1 step
--     listens to them), and the other way round.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NextGoal = require(ReplicatedStorage.Shared.NextGoal)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local FieldGuideService = require(script.Parent.FieldGuideService)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local TreeService = require(script.Parent.TreeService)

type Profile = ProfileService.Profile
type TutorialEvent = TutorialData.TutorialEvent

local QuestService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local loop = 1 -- the core loop that runs (Init)

-- The tutorial's steps in the loop that runs.
local function steps(): { TutorialData.Step }
	return TutorialData.ForLoop(loop)
end

local function publish(player: Player, profile: Profile)
	player:SetAttribute("TutorialStep", if profile.tutorialDone then 0 else profile.tutorialStep)
	player:SetAttribute("TutorialProgress", profile.tutorialProgress)
	-- A returning player's refresher (QuestUI shows its length and Murph's
	-- welcome-back line).
	player:SetAttribute(
		"TutorialRefresher",
		if profile.tutorialRefresher and not profile.tutorialDone then true else nil
	)
end

-- Whether `profile` is on the v2 refresher (a save that came into the v2
-- loop with the tutorial finished: ProfileSchema.MigrateV2).
local function onRefresher(profile: Profile): boolean
	return loop == 2 and profile.tutorialRefresher == true
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

-- One objective after the tutorial: the next axe, a Field Guide "???", or
-- the daily streak. Cleared while the tutorial is still running. Logged
-- once on the onboarding funnel, after "Finished the tutorial" when they
-- actually finished (Mark is a no-op the second time).
local function refreshNext(player: Player, profile: Profile)
	if not profile.tutorialDone then
		player:SetAttribute("NextGoal", nil)
		player:SetAttribute("NextGoalBeacon", nil)
		return
	end
	local found = profile.compendium
	if type(found) ~= "table" then
		found = {}
	end
	local streak = 0
	if profile.daily and type(profile.daily.streak) == "number" then
		streak = profile.daily.streak
	end
	local goal = NextGoal.Pick(loop, profile.bestAxeTier or 1, found, streak)
	player:SetAttribute("NextGoal", goal.text)
	player:SetAttribute("NextGoalBeacon", goal.beacon)
	MilestoneService.Mark(player, "Saw a next goal")
end

-- Call when cash, the axe ladder, the Field Guide or the streak changes
-- after the tutorial, so the tracker stays on the one current goal.
function QuestService.RefreshNextGoal(player: Player)
	local profile = ProfileService.GetProfile(player)
	if profile then
		refreshNext(player, profile)
	end
end

local function finish(player: Player, profile: Profile, how: "completed" | "skipped" | "bypassed")
	profile.tutorialDone = true
	profile.tutorialProgress = 0
	profile.tutorialRefresher = false
	profile.tutorialReplay = false
	publish(player, profile)
	FieldGuideService.Refresh(player) -- Murph hands over the Field Guide
	if how == "completed" then
		logFunnelStep(player, profile, #steps() + 1, "Done")
		MilestoneService.Mark(player, "Finished the tutorial")
	end
	analytics(function()
		AnalyticsService:LogCustomEvent(player, "Tutorial_" .. how, profile.tutorialStep)
	end)
	-- After "Finished the tutorial", so the funnel numbers stay in order.
	refreshNext(player, profile)
end

local function claimedPlot(profile: Profile): boolean
	return profile.plot ~= nil and profile.plot.claimed == true
end

local function hasPlacedItem(profile: Profile): boolean
	return profile.plot ~= nil and type(profile.plot.placed) == "table" and #profile.plot.placed > 0
end

-- A spawn pad (from a truck or trailer box) is on the plot.
local function hasPad(profile: Profile): boolean
	local plot: any = profile.plot
	return type(plot) == "table" and type(plot.pads) == "table" and #plot.pads > 0
end

local function ownsTruck(profile: Profile): boolean
	return type(profile.ownedTrucks) == "table" and #profile.ownedTrucks > 0
end

-- Starts step `index`, skipping any the player is already past; finishes
-- the tutorial after the last one.
local function enterStep(player: Player, profile: Profile, index: number)
	local list = steps()
	local step: TutorialData.Step? = list[index]
	while
		step
		and TutorialData.AlreadyDone(
			step,
			profile.bestAxeTier,
			claimedPlot(profile),
			ownsTruck(profile),
			hasPlacedItem(profile),
			hasPad(profile)
		)
	do
		index += 1
		step = list[index]
	end
	if onRefresher(profile) and index > TutorialData.RefresherLast then
		step = nil -- the refresher ends after the first sale
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

-- A save from before a step was inserted points at whatever step now sits
-- at its old index. The funnel remembers every step a player has reached
-- (profile.onboarding, by step id). When that index now holds a different
-- step, move to the latest one they reached, even if its new index is
-- lower (the first sale sits before the truck). Progress toward it is kept.
local function realign(profile: Profile)
	local list = steps()
	local latest = 0
	for i, step in ipairs(list) do
		if profile.onboarding["Tutorial:" .. step.id] then
			latest = i
		end
	end
	if latest == 0 then
		return
	end
	local at = list[profile.tutorialStep]
	local there = list[latest]
	if there and (at == nil or at.id ~= there.id) then
		profile.tutorialStep = latest
	end
end

-- Call once the player's save has loaded.
function QuestService.Start(player: Player, profile: Profile)
	if loop == 2 then
		-- Old v2 saves stored a plot-first index. Once tutorialOrder is
		-- current, the index already names the right step, so the funnel
		-- realign (which assumes later steps have higher indexes) must not
		-- pull a player who already claimed back onto the plot step.
		TutorialData.ApplyOrder(profile)
	end
	if profile.tutorialDone then
		publish(player, profile)
		refreshNext(player, profile)
		return
	end
	if onRefresher(profile) then
		-- No realign or bypass: their v1 funnel and better axe say they've
		-- done it all, and the point is to walk the new steps.
		local index = math.clamp(math.floor(tonumber(profile.tutorialStep) or 1), 1, TutorialData.RefresherLast)
		if index == 1 and profile.tutorialProgress == 0 then
			enterStep(player, profile, 1)
		else
			profile.tutorialStep = index
			publish(player, profile)
		end
		return
	end
	if loop ~= 2 or profile.tutorialOrder ~= TutorialData.OrderV2 then
		realign(profile)
	end
	-- A save that was on a step the short tutorial retired for good
	-- (TutorialData.ApplyOrder points it one past the end) is done.
	if loop == 2 and profile.tutorialStep > #steps() then
		finish(player, profile, "completed")
		return
	end
	if
		profile.tutorialReplay ~= true
		and profile.bestAxeTier >= 2
		and profile.tutorialStep == 1
		and profile.tutorialProgress == 0
	then
		finish(player, profile, "bypassed") -- a save from before the tutorial existed
		return
	end
	local step = steps()[profile.tutorialStep]
	if
		not step
		or TutorialData.AlreadyDone(
			step,
			profile.bestAxeTier,
			claimedPlot(profile),
			ownsTruck(profile),
			hasPlacedItem(profile),
			hasPad(profile)
		)
	then
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
	local step = steps()[profile.tutorialStep]
	if not step then
		return
	end
	local progress, done = TutorialData.Apply(step, profile.tutorialProgress, event, amount or 1)
	if progress == profile.tutorialProgress and not done then
		return
	end
	profile.tutorialProgress = progress
	if not done then
		publish(player, profile)
		return
	end
	local reward = step.rewardCash
	-- A returning player's refresher walks the new steps without the cash
	-- (they already had the first-sale bonus, or never will: it's once).
	if reward and reward > 0 and not onRefresher(profile) then
		EconomyService.AddCash(player, reward, "tutorial: " .. step.id, "tutorial")
		-- The next card already says it (the first sale's thank-you), so a toast
		-- on top would be a second pop-up for the same thing.
		if step.rewardToast ~= false then
			notify(player, string.format("Murph chipped in %s!", Util.formatCash(reward)))
		end
	end
	enterStep(player, profile, profile.tutorialStep + 1)
end

-- A v2 sale paid `player` for `pieces` pieces and `credited` dollars (what
-- reached their wallet: SellService's onSold, per payee per tick). The
-- sell step counts the pieces (woodSold), the dollars step the whole
-- dollars (woodSoldCash), in that order: the first sale moves the sell
-- step on, and its cash doesn't count toward the "more wood" step after
-- the loads that follow the mill.
function QuestService.WoodSold(player: Player, pieces: number, credited: number)
	local profile = ProfileService.GetProfile(player)
	local before = if profile then profile.tutorialStep else nil
	if type(pieces) == "number" and pieces >= 1 then
		QuestService.Event(player, "woodSold", math.floor(pieces))
	end
	-- A sale that just finished a step doesn't also pay the next one.
	-- The mill used to be followed by a plant step, which ate this gap.
	local after = if profile then profile.tutorialStep else nil
	if before ~= after then
		return
	end
	local dollars = if type(credited) == "number" and credited == credited then math.floor(credited) else 0
	if dollars >= 1 and dollars ~= math.huge then
		QuestService.Event(player, "woodSoldCash", dollars)
	end
end

-- Trees regrow on their own timer. The hook stays so TreeService can ask;
-- nothing holds a stump.
function QuestService.StumpHoldFor(_player: Player): number
	return 0
end

-- Settings → Reset tutorial. A player who already owns a better axe would
-- be bypassed on the next join, so tutorialReplay keeps the run alive.
function QuestService.Reset(player: Player)
	if not RateLimiter.Allow(player, "ResetTutorial") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	profile.tutorialDone = false
	profile.tutorialStep = 1
	profile.tutorialProgress = 0
	profile.tutorialRefresher = false
	profile.tutorialReplay = true
	enterStep(player, profile, 1)
	notify(player, "Tutorial reset. Murph is waiting by the spawn.")
end

-- What the client may say it saw, and the tutorial event that is. The
-- client only knows it opened a panel; the server counts it only for a
-- player who has claimed a plot, and only when that is the current step.
local function onSeen(player: Player, what: unknown)
	if type(what) ~= "string" or not RateLimiter.Allow(player, "TutorialSeen") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or not claimedPlot(profile) then
		return
	end
	if what == "build" then
		QuestService.Event(player, "buildOpened")
	elseif what == "land" then
		QuestService.Event(player, "landOpened")
	end
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

-- `notifyFn` shows a toast (GameServer's notify); `activeLoop` is the core
-- loop that runs (CoreLoop.Active(); 1 when not given).
function QuestService.Init(
	skipRemote: RemoteEvent,
	notifyFn: (Player, string) -> (),
	activeLoop: number?,
	resetRemote: RemoteEvent?,
	seenRemote: RemoteEvent?
)
	notify = notifyFn
	loop = if activeLoop == 2 then 2 else 1
	skipRemote.OnServerEvent:Connect(onSkip)
	if resetRemote then
		resetRemote.OnServerEvent:Connect(function(player: Player)
			QuestService.Reset(player)
		end)
	end
	if seenRemote then
		seenRemote.OnServerEvent:Connect(onSeen)
	end
	TreeService.StumpHold = QuestService.StumpHoldFor
end

return QuestService
