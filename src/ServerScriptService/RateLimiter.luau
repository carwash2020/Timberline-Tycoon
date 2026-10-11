--!strict
-- RateLimiter: per-player, per-remote request budgets.
--
-- Requests over budget are dropped silently: mashing a button is normal
-- player behaviour and must never get anyone kicked. Only a burst far beyond
-- what a human can produce (ABUSE_MULTIPLIER x the limit inside one second)
-- earns a strike. Strikes expire after STRIKE_WINDOW seconds, and a player
-- is kicked only after STRIKES_TO_KICK strikes inside that window.

local RateLimiter = {}

local LIMITS: { [string]: number } = { -- max requests per second
	ChopTree = 4,
	PickupLog = 8,
	LoadToTruck = 4,
	SellLogs = 4,
	UseInstantDelivery = 2, -- the Robux bed sale; its own budget, not SellLogs'
	DropAxe = 2,
	PickUpAxe = 4,
	UseBlueprint = 3, -- using a rolled plan (BlueprintService)
	DropBlueprint = 2,
	PickUpBlueprint = 4,
	BuyItem = 3,
	SkipTutorial = 1,
	ForemanTurnIn = 2, -- hand the day's jobs in to the Sawmill Foreman (DailyService)
	ResetTutorial = 1,
	TutorialSeen = 2, -- the hammer's blueprint list or LAND opened, for the tutorial
	EquipItem = 2,
	CallTruck = 1,
	AdminRun = 4, -- the owner menu
	Sprint = 8, -- Shift or L1 down and up
	BuyRobuxItem = 2,
	MineNode = 4,
	Gondola = 1,
	PlaceBlueprint = 2,
	MoveBlueprint = 2,
	BlueprintEdit = 5, -- rotate, move, resize, copy, delete, undo
	SellPlaced = 4,
	PaintPiece = 6, -- the palette stays open while a player tries colours
	BeltReverse = 2, -- Lane W: the Reverse prompt on a belt
	BeltFlip = 2, -- Lane W: the Flip prompt on a Switch Belt
	DetectorFilter = 3, -- Lane W: stepping a Wood Detector's filter
	UpgradePlot = 1,
	ClaimPlot = 4, -- the join picker: next and previous stay on the client
	PlotPass = 2, -- close the picker, or let the timer assign one
	PlotShown = 2, -- the join picker is on screen: starts its timeout (PlotService.Shown)
	BaseAction = 2, -- the Bases panel: pack, bring out, start fresh (PlotService.BaseAction; the change also has a cooldown)
	SaveSetting = 4,
	SetQuality = 2, -- the join screen's choice, or the Settings row (QualityService)
	ClientReady = 2, -- the client's join handshake: once, with a retry (JoinSync)
	Grab = 6, -- v2 loop (V2_PLAN.md §12)
	Release = 6,
	Chop = 6, -- v2 loop: a swing at a section (SectionTrees; the axe's cooldown is checked too)
	Swing = 8, -- the pose stamp. A start and a cancel, at the fastest axe, stay under this
	SellSkyBin = 2, -- v2: the Sky Bin's prompt by the pad (AetherService; a ProximityPrompt, not a remote)
	SawmillSet = 6, -- v2: one step of a placed mill's cut (SawmillService)
	Dialogue = 4, -- shop talk: open, or pick a line
	NPCTalk = 4, -- an NPC's Talk prompt (NPCTalkService; a prompt, not a remote)
	TalkEnd = 6, -- the dialogue box closed (the Dialogue remote's "end"; a box swap sends two)
	BoxOpen = 4, -- open a box you own
	BoxTake = 4, -- pick up the item that came out of a box (a prompt, not a remote)
	SpawnPadPress = 1, -- the button on a vehicle pad
	PlanerSet = 6, -- one step of a placed planer's size setting (PlanerService); same budget as SawmillSet
	ChopSawSet = 6, -- one step of a chop saw's cut; same budget as SawmillSet
	ExpandLand = 1, -- buy the next plot square
	SetPermission = 4, -- one flag for one visitor
	VisitPlot = 1, -- go to a friend's plot (PlotService.Visit)
	Wire = 4, -- connect a port, or cut a wire
	TollPay = 1, -- pay the toll
	FerryBoard = 1, -- board the ferry
	Blast = 1, -- set a blasting charge (BlastService's prompt; not a remote)
	SlotAction = 2, -- load, reset, or save a slot (the confirm is a second call)
	PlotSalesman = 2, -- Old Hank's Talk prompt (PlotService; a prompt, not a remote)
	HermitTalk = 2, -- the Hermit's Talk prompt (HermitService; a prompt, not a remote)
	SecretPress = 2, -- a carving or the cave box prompt (HermitService)
	BoardRequest = 2, -- the Leaderboard tab; the service also answers one per player per 10 s
	PaintTruck = 1, -- Paint Shop: one request a second; the palette rule also waits 2s
	NewsSeen = 2, -- What's new closed (NewsService); a second press in the same second is dropped
	SkyQuest = 2,
	ForgeAction = 4,
	ForgeOpen = 2,
	SaveNow = 1,
	PaintAllType = 4,
	LogicSet = 4,
	MineAction = 8, -- Lane M: a mining intent, about 8 a second
	CraftAction = 2, -- Lane M: a craft intent, about 2 a second
}
local ABUSE_MULTIPLIER = 5
-- Never strike for fewer than this many presses in a second: frantic
-- tapping on a 1-per-second button ("Truck to lot") is still human.
local ABUSE_FLOOR = 15
local STRIKE_WINDOW = 60
local STRIKES_TO_KICK = 5

type Bucket = { windowStart: number, count: number, struck: boolean }

local buckets: { [Player]: { [string]: Bucket } } = {}
local strikes: { [Player]: { number } } = {}

local function addStrike(player: Player, remoteName: string)
	local now = os.clock()
	local list = strikes[player] or {}
	local kept = {}
	for _, t in ipairs(list) do
		if now - t < STRIKE_WINDOW then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	strikes[player] = kept
	warn(
		string.format("[AntiExploit] %s flooded %s (%d strikes in %ds)", player.Name, remoteName, #kept, STRIKE_WINDOW)
	)
	if #kept >= STRIKES_TO_KICK then
		player:Kick("Disconnected: too many requests.")
	end
end

-- True if this request should be processed.
function RateLimiter.Allow(player: Player, remoteName: string): boolean
	local limit = LIMITS[remoteName]
	if limit == nil then
		return false
	end
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[remoteName]
	if bucket == nil or now - bucket.windowStart >= 1 then
		bucket = { windowStart = now, count = 0, struck = false }
		perPlayer[remoteName] = bucket
	end
	bucket.count += 1
	if bucket.count <= limit then
		return true
	end
	if not bucket.struck and bucket.count > math.max(limit * ABUSE_MULTIPLIER, ABUSE_FLOOR) then
		bucket.struck = true -- at most one strike per remote per second
		addStrike(player, remoteName)
	end
	return false
end

function RateLimiter.Forget(player: Player)
	buckets[player] = nil
	strikes[player] = nil
end

return RateLimiter
