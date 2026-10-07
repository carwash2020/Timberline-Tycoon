--!strict
-- GameServer: bootstrap + remote handlers.
--   * Creates ReplicatedStorage/Remotes (names listed in Shared/Net).
--   * PlayerAdded: load save -> restore spawn pads (a truck only comes out of its pad) -> hand over every owned axe
--     (AxeService; axes are items the player can switch, drop and pick up).
--   * PlayerRemoving: drop carried logs, final save + release the session.
--   * Every remote is rate-limited and server-validated. The client only
--     sends intents; TreeService/EconomyService own the truth. BuyItem is
--     handled by ShopService.
-- Autosave and session locks are ProfileStore's job (see ProfileService).
-- The final save also commits playtime, the truck load and left-behind
-- wood (LeaveCommit), including when the server shuts down.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AetherService = require(script.Parent.AetherService)
local AxeService = require(script.Parent.AxeService)
local BlueprintService = require(script.Parent.BlueprintService)
local CarryService = require(script.Parent.CarryService)
local BiomeService = require(script.Parent.BiomeService)
local BadgeService = require(script.Parent.BadgeService)
local BlastService = require(script.Parent.BlastService)
local BootReport = require(script.Parent.BootReport)
local BoxService = require(script.Parent.BoxService)
local DialogueService = require(script.Parent.DialogueService)
local EventService = require(script.Parent.EventService)
local FerryService = require(script.Parent.FerryService)
local GateService = require(script.Parent.GateService)
local HazardService = require(script.Parent.HazardService)
local HermitService = require(script.Parent.HermitService)
local LogicService = require(script.Parent.LogicService)
local PermissionService = require(script.Parent.PermissionService)
local DailyService = require(script.Parent.DailyService)
local AdminService = require(script.Parent.AdminService)
local DevCommands = require(script.Parent.DevCommands)
local EconomyService = require(script.Parent.EconomyService)
local FieldGuideService = require(script.Parent.FieldGuideService)
local ForestService = require(script.Parent.ForestService)
local GondolaService = require(script.Parent.GondolaService)
local GrabService = require(script.Parent.GrabService)
local SectionTrees = require(script.Parent.SectionTrees)
local LeaderboardService = require(script.Parent.LeaderboardService)
local SaveSlotService = require(script.Parent.SaveSlotService)
local ChopSawService = require(script.Parent.ChopSawService)
local BeltService = require(script.Parent.BeltService)
local PlanerService = require(script.Parent.PlanerService)
local SawmillService = require(script.Parent.SawmillService)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local SellService = require(script.Parent.SellService)
local LeaveCommit = require(script.Parent.LeaveCommit)
local LeftLoad = require(script.Parent.LeftLoad)
local MilestoneService = require(script.Parent.MilestoneService)
local MonetizationService = require(script.Parent.MonetizationService)
local PaintService = require(script.Parent.PaintService)
local NodeService = require(script.Parent.NodeService)
local NPCService = require(script.Parent.NPCService)
local PickupGrace = require(script.Parent.PickupGrace)
local LoadState = require(script.Parent.LoadState)
local PlaceCheck = require(script.Parent.PlaceCheck)
local PlotService = require(script.Parent.PlotService)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local SprintLogic = require(ReplicatedStorage.Shared.SprintLogic)
local RegionWake = require(script.Parent.RegionWake)
local ShopService = require(script.Parent.ShopService)
local TreeService = require(script.Parent.TreeService)
local TruckLoad = require(script.Parent.TruckLoad)
local VehicleService = require(script.Parent.VehicleService)
local WeatherService = require(script.Parent.WeatherService)
local WoodService = require(script.Parent.WoodService)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local PlotSalesmanData = require(ReplicatedStorage.Shared.PlotSalesmanData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local Util = require(ReplicatedStorage.Shared.Util)

-- Runs one service's Init, join or leave hook on its own: an error in one
-- is logged with a traceback and doesn't stop the others (a broken Init
-- must never keep players out). tostring first: debug.traceback itself
-- errors on a non-string error.
-- Filled in once leave-commit helpers exist. A slot change calls these.
local commitSlot: (Player) -> () = function(_player: Player) end
local rebuildSlot: (Player) -> () = function(_player: Player) end

local SLOW_STEP = 0.1 -- a service hook slower than this prints a [Load] line

local function safely(name: string, fn: (...any) -> ...any, ...: any)
	local args = table.pack(...)
	local startedAt = os.clock()
	local ok, err = xpcall(function(): any
		fn(table.unpack(args, 1, args.n))
		return nil
	end, function(e: any): string
		return debug.traceback(tostring(e), 2)
	end)
	if not ok then
		warn(string.format("[GameServer] %s failed:\n%s", name, tostring(err)))
	end
	local took = os.clock() - startedAt
	if took >= SLOW_STEP then
		print(string.format("[Load] GameServer %s took %.2fs", name, took))
	end
end

-- Does the live place match default.project.json (and, in Studio, can it
-- save)? A warning names each fix; "[PlaceCheck] OK" when all match. Its
-- own thread: in Studio it waits a moment for ProfileStore's access probe.
task.spawn(function()
	safely("PlaceCheck.Run", PlaceCheck.Run)
end)

-- Wait for the code-built world. MapBuilder writes the terrain first (a few
-- seconds to a minute) and adds the SellArea last, once everything exists.
local mapFolder = workspace:WaitForChild("TimberlineMap", 60)
assert(mapFolder, "[GameServer] TimberlineMap was not built (MapBuilder failed?)")
local waitedFor = os.clock()
local initStart = os.clock() -- the [Load] lines time the services from here
local sellArea = mapFolder:WaitForChild("SellArea", 600)
print(string.format("[Load] GameServer waited %.1fs for the world (SellArea)", os.clock() - waitedFor))
initStart = os.clock()
assert(sellArea, "[GameServer] SellArea missing")
local sellZoneInst = sellArea:WaitForChild("SellZone", 30)
assert(sellZoneInst and sellZoneInst:IsA("BasePart"), "[GameServer] SellZone missing")
local sellZone = sellZoneInst :: BasePart
-- Remotes -----------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local remote: { [string]: RemoteEvent } = {}
for _, name in ipairs(Net.RemoteNames) do
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = remotes
	remote[name] = re
end
remotes.Parent = ReplicatedStorage

safely("EconomyService.Init", EconomyService.Init, remotes)

-- Per-player state ---------------------------------------------------------
local nextSwingAt: { [number]: number } = {}
local lastNotice: { [number]: { [string]: number } } = {}

-- Short on-screen message. The same text at most once a second, so
-- spam-clicking can't spam toasts.
local function notify(player: Player, message: string)
	local seen = lastNotice[player.UserId]
	if not seen then
		return
	end
	local now = os.clock()
	local last = seen[message]
	if last and now - last < 1 then
		return
	end
	seen[message] = now
	-- Most messages are one-offs (cash amounts, counts): forget old ones so
	-- the table doesn't grow for as long as the player stays.
	if math.random() < 0.05 then
		for text, at in pairs(seen) do
			if now - at > 2 then
				seen[text] = nil
			end
		end
	end
	remote.Notify:FireClient(player, message)
end

local function getCharacterParts(player: Player): (Model?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return char, hrp
end

local function countHands(hands: { [string]: boolean }): number
	local n = 0
	for _ in pairs(hands) do
		n += 1
	end
	return n
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Remote handlers ----------------------------------------------------------

local function onChopTree(player: Player, treeUid: unknown)
	if type(treeUid) ~= "string" or not RateLimiter.Allow(player, "ChopTree") then
		return
	end
	local char = getCharacterParts(player)
	local profile = ProfileService.GetProfile(player)
	if not char or not profile then
		return
	end
	local axe = AxeService.GetEquippedAxe(player) -- only a real, owned axe counts
	if not axe then
		return
	end
	-- A swing may arrive up to SwingTolerance early (network jitter), but the
	-- schedule advances from when it was due, so over time nobody can swing
	-- faster than once per SwingCooldown.
	local now = os.clock()
	local due = nextSwingAt[player.UserId] or 0
	if now < due - GameConfig.SwingTolerance then
		return
	end
	-- Some woods need gear: Heat Boots on the Volcano, a Lantern in the Grove.
	local wood = TreeService.GetTreeWood(treeUid)
	if wood then
		local ok, why = BiomeService.CanChop(player, wood)
		if not ok then
			if why then
				notify(player, why)
			end
			return
		end
	end
	local newHp, err, feller = TreeService.ApplyChop(player, treeUid, axe)
	if newHp == nil then
		if err == "far" then
			notify(player, "Too far away. Walk closer to chop.")
		elseif err == "tooHard" then
			notify(
				player,
				string.format("This wood is too hard for your %s. You need a stronger axe.", axe.displayName)
			)
		end
		return
	end
	nextSwingAt[player.UserId] = math.max(now, due) + GameConfig.SwingCooldown
	MilestoneService.Mark(player, "First chop")
	-- The felling counts for whoever chopped the most of the tree (its logs
	-- are theirs too), not just whoever landed the last swing.
	local credited = if newHp <= 0 then feller or player else nil
	local creditedProfile = if credited then ProfileService.GetProfile(credited) else nil
	if credited and creditedProfile then
		creditedProfile.stats.treesChopped += 1
		MilestoneService.Mark(credited, "First tree felled")
		QuestService.Event(credited, "treeFelled")
		DailyService.Event(credited, "treeFelled", 1)
		if wood then
			FieldGuideService.Discover(credited, wood.id)
			QuestService.RefreshNextGoal(credited)
		end
	end
end

-- One swing at a crystal node (any axe; the same swing cooldown as chopping).
local function onMineNode(player: Player, nodeUid: unknown)
	if type(nodeUid) ~= "string" or not RateLimiter.Allow(player, "MineNode") then
		return
	end
	local char = getCharacterParts(player)
	if not char or not AxeService.GetEquippedAxe(player) then
		return
	end
	local now = os.clock()
	local due = nextSwingAt[player.UserId] or 0
	if now < due - GameConfig.SwingTolerance then
		return
	end
	local result = NodeService.Hit(player, nodeUid)
	if result == "far" then
		notify(player, "Too far away. Walk closer to mine.")
	elseif result then
		nextSwingAt[player.UserId] = math.max(now, due) + GameConfig.SwingCooldown
	end
end

local function serverPickupLog(player: Player, logUid: unknown)
	if type(logUid) ~= "string" or not RateLimiter.Allow(player, "PickupLog") then
		return
	end
	local char, hrp = getCharacterParts(player)
	local hands = CarryService.Hands(player)
	if not char or not hrp or not hands or not ProfileService.GetProfile(player) then
		return
	end
	local log = TreeService.GetLog(logUid)
	if not log or log.state ~= "world" then
		return
	end
	local pp = log.model.PrimaryPart
	if not pp then
		return
	end
	if (hrp.Position - pp.Position).Magnitude > GameConfig.PickupPromptRange + GameConfig.RangeTolerance then
		return
	end
	-- Grace period: only the feller can grab these for PickupGraceSec (a
	-- load left behind by a truck stays its owner's for longer).
	local graceLeft = PickupGrace.WaitFor(log, player.UserId, os.time())
	if graceLeft > 0 then
		notify(player, PickupGrace.Message(log, graceLeft))
		return
	end
	local already = countHands(hands)
	if already >= GameConfig.HandCapacity then
		notify(
			player,
			string.format("Hands full (%d/%d). Load them into your truck.", already, GameConfig.HandCapacity)
		)
		return
	end
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	if not torso or not TreeService.ClaimLog(logUid) then
		return
	end
	pp.Anchored = false
	pp.CanCollide = false
	pp.Massless = true
	-- The lowest free spot in the stack, so a log never lands inside another
	-- after one was sold or loaded out of the middle.
	local used: { [number]: boolean } = {}
	for uid in pairs(hands) do
		local held = TreeService.GetLog(uid)
		local slot = if held and held.model.PrimaryPart then held.model.PrimaryPart:GetAttribute("CarrySlot") else nil
		if type(slot) == "number" then
			used[slot] = true
		end
	end
	local slot = 0
	while used[slot] do
		slot += 1
	end
	pp:SetAttribute("CarrySlot", slot)
	pp.CFrame = torso.CFrame * CFrame.new(0, 0.35 - slot * 1.25, -1.35) -- = CarryLayout.LogOffset(slot)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = pp
	weld.Parent = pp
	hands[logUid] = true
	player:SetAttribute("CarriedLogs", already + 1)
	MilestoneService.Mark(player, "First log picked up")
	QuestService.Event(player, "logPickedUp")
end

-- ProximityPrompts on logs call the same validated path.
TreeService.PickupCallback = serverPickupLog
TreeService.LogMultiplier = MonetizationService.LogMultiplier

local function onLoadToTruck(player: Player)
	if not RateLimiter.Allow(player, "LoadToTruck") then
		return
	end
	local _char, hrp = getCharacterParts(player)
	local truck = VehicleService.GetVehicle(player)
	local hands = CarryService.Hands(player)
	if not hrp or not truck or not hands then
		return
	end
	local loadPoint = VehicleService.GetLoadPoint(player)
	if not loadPoint then
		notify(player, "This truck has no bed. Switch trucks at the Dealership.")
		return
	end
	if (hrp.Position - loadPoint).Magnitude > GameConfig.LoadPromptRange + GameConfig.RangeTolerance then
		notify(player, "Get closer to your truck's tailgate.")
		return
	end
	local uids: { string } = {}
	for uid in pairs(hands) do
		table.insert(uids, uid)
	end
	if #uids == 0 then
		return
	end
	local capacity = VehicleService.GetBedCapacity(player)
	if VehicleService.GetBedCount(player) >= capacity then
		notify(player, "Truck bed full. Sell at the sawmill.")
		return
	end
	local moved, fresh = 0, 0 -- fresh: not a left-behind load being picked up again
	for _, uid in ipairs(uids) do
		local log = TreeService.GetLog(uid)
		if not log then
			hands[uid] = nil -- stale entry; drop it
		elseif
			VehicleService.AddBedLog(player, { woodId = log.def.id, value = log.value, figure = log.tags.figure })
		then
			-- Only destroy the carried log once it's safely in the bed.
			TreeService.TakeLog(uid)
			log.model:Destroy()
			hands[uid] = nil
			moved += 1
			if log.tags.leftBehind ~= true then
				fresh += 1
			end
		end
	end
	player:SetAttribute("CarriedLogs", countHands(hands))
	if moved > 0 then
		MilestoneService.Mark(player, "First log loaded")
		if fresh > 0 then
			QuestService.Event(player, "logsLoaded", fresh)
			DailyService.Event(player, "logsLoaded", fresh)
		end
		notify(
			player,
			string.format(
				"Loaded %d log%s. Bed %d/%d.",
				moved,
				moved == 1 and "" or "s",
				VehicleService.GetBedCount(player),
				capacity
			)
		)
	end
end

-- Pays for `count` logs worth `total` and reports the sale everywhere:
-- stats, the stopwatch, the tutorial, daily goals, the Living Forest's
-- figure reveals. 2x Cash applies here.
local function completeSale(
	player: Player,
	profile: ProfileService.Profile,
	total: number,
	count: number,
	byWood: { [string]: number },
	figures: { [string]: number }
)
	total *= MonetizationService.SaleMultiplier(player)
	profile.stats.logsSold += count
	local credited, overflow = EconomyService.AddCash(player, total, string.format("sold %d logs", count), "logs")
	MilestoneService.Mark(player, "First sale")
	MilestoneService.CashEarned(player, credited)
	MilestoneService.LogsSold(player, byWood)
	-- Report what was actually paid (the wallet cap may have taken some).
	notify(player, string.format("Sold %d log%s for %s", count, count == 1 and "" or "s", Util.formatCash(credited)))
	if next(figures) then
		local ok, err = pcall(function(): any
			ForestService.OnSale(player, figures)
			return nil
		end)
		if not ok then
			warn("[GameServer] ForestService.OnSale failed: " .. tostring(err))
		end
	end
	if overflow > 0 then
		notify(
			player,
			string.format(
				"Wallet full at %s: %s didn't fit. Spend some!",
				Util.formatCash(GameConfig.CashCap),
				Util.formatCash(overflow)
			)
		)
	end
	-- After the sale's toasts, so rewards read last.
	QuestService.Event(player, "logsSold", count)
	DailyService.Event(player, "logsSold", count, byWood, credited)
end

local function onSellLogs(player: Player)
	if not RateLimiter.Allow(player, "SellLogs") then
		return
	end
	local _char, hrp = getCharacterParts(player)
	local profile = ProfileService.GetProfile(player)
	local hands = CarryService.Hands(player)
	if not hrp or not profile or not hands then
		return
	end
	if not Util.pointInPart(sellZone, hrp.Position) then
		notify(player, "Stand on the sawmill's sell pad to sell.")
		return
	end
	local total, count = 0, 0
	local byWood: { [string]: number } = {} -- for the stopwatch's calibration line
	local figures: { [string]: number } = {} -- figured logs, for the reveal
	-- Logs in hands: valued from SERVER records, then destroyed.
	for uid in pairs(hands) do
		local log = TreeService.TakeLog(uid)
		if log then
			total += log.value
			count += 1
			byWood[log.def.id] = (byWood[log.def.id] or 0) + 1
			local figure = log.tags.figure
			if type(figure) == "string" then
				figures[figure] = (figures[figure] or 0) + 1
			end
			log.model:Destroy()
		end
	end
	table.clear(hands)
	-- The truck bed only sells if the truck is actually at the mill: where
	-- the server vouches it is, judged right now (its driver's device moves
	-- it, and could have teleported it onto the pad a moment ago).
	local truckAt = VehicleService.TrustedTruckPosition(player)
	if truckAt and flatDistance(truckAt, sellZone.Position) <= GameConfig.SellTruckRange then
		for _, entry in ipairs(VehicleService.TakeBedLogs(player)) do
			total += entry.value
			count += 1
			byWood[entry.woodId] = (byWood[entry.woodId] or 0) + 1
			if entry.figure then
				figures[entry.figure] = (figures[entry.figure] or 0) + 1
			end
		end
	end
	-- The v1 loop's Sky Bin logs (a rollback only: under v2 the bin is an item
	-- on your plot, sold from its own prompt) sell with the pad.
	for _, entry in ipairs(AetherService.TakeSkyBin(player)) do
		total += entry.value
		count += 1
		byWood[entry.woodId] = (byWood[entry.woodId] or 0) + 1
		if entry.figure then
			figures[entry.figure] = (figures[entry.figure] or 0) + 1
		end
	end
	player:SetAttribute("CarriedLogs", 0)
	if count == 0 then
		notify(player, "Nothing to sell. Bring logs, or park your truck by the mill.")
		return
	end
	completeSale(player, profile, total, count, byWood, figures)
end

-- Instant Delivery (a Robux product): sells the truck bed from anywhere.
-- The v2 loop sells the loose wood on the beds instead (SellService.SellBed:
-- the same wallet check, then one use).
local function onInstantDelivery(player: Player)
	if not RateLimiter.Allow(player, "UseInstantDelivery") then
		return
	end
	if CoreLoop.V2() then
		SellService.SellBed(player, function(): boolean
			return MonetizationService.UseInstantDelivery(player)
		end)
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or VehicleService.GetBedCount(player) == 0 then
		return
	end
	-- A load the wallet cap would eat (some or all of it) isn't worth a
	-- paid use: say so before one is spent.
	local worth = math.floor(VehicleService.GetBedValue(player) * MonetizationService.SaleMultiplier(player))
	local room = GameConfig.CashCap - profile.cash
	if worth > room then
		notify(
			player,
			if room <= 0
				then string.format(
					"Your wallet is full (%s). Spend some before using Instant Delivery.",
					Util.formatCash(GameConfig.CashCap)
				)
				else string.format(
					"This load is worth %s but your wallet only has room for %s. Spend some before using Instant Delivery.",
					Util.formatCash(worth),
					Util.formatCash(room)
				)
		)
		return
	end
	if not MonetizationService.UseInstantDelivery(player) then
		notify(player, "You have no Instant Deliveries left.")
		return
	end
	local total, count = 0, 0
	local byWood: { [string]: number } = {}
	local figures: { [string]: number } = {}
	for _, entry in ipairs(VehicleService.TakeBedLogs(player)) do
		total += entry.value
		count += 1
		byWood[entry.woodId] = (byWood[entry.woodId] or 0) + 1
		if entry.figure then
			figures[entry.figure] = (figures[entry.figure] or 0) + 1
		end
	end
	completeSale(player, profile, total, count, byWood, figures)
end

-- A v2 sale (SellService, per payee per tick), which SellService has paid
-- and toasted: what the stopwatch, the Living Forest's reveals, the
-- tutorial and the daily goals hear about, as completeSale tells them of
-- a v1 sale.
local function onWoodSold(sale: SellService.Sale)
	local player = sale.payee
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return -- left meanwhile: nothing was credited
	end
	profile.stats.volumeSold = (profile.stats.volumeSold or 0) + sale.volume
	local credited = sale.credited
	MilestoneService.Mark(player, "First sale")
	MilestoneService.CashEarned(player, credited)
	MilestoneService.WoodSold(player, sale.pieces, sale.woods)
	if #sale.figures > 0 then
		local figures: { [string]: number } = {}
		for _, figure in ipairs(sale.figures) do
			figures[figure] = (figures[figure] or 0) + 1
		end
		safely("ForestService.OnSale", ForestService.OnSale, player, figures)
	end
	local overflow = sale.paid - credited
	if overflow > 0 then
		notify(
			player,
			string.format(
				"Wallet full at %s: %s didn't fit. Spend some!",
				Util.formatCash(GameConfig.CashCap),
				Util.formatCash(overflow)
			)
		)
	end
	-- After the sale's toasts, so rewards read last.
	safely("QuestService.WoodSold", QuestService.WoodSold, player, sale.pieces, credited)
	safely("DailyService.WoodSold", DailyService.WoodSold, player, {
		volume = sale.volume,
		cash = credited,
		byWood = sale.woods,
		pieces = sale.pieceVolumes,
		figured = sale.figured,
	})
end

-- Each Init on its own (safely): one failing leaves that service broken
-- but the server, the other services and spawning carry on. The services
-- that read v2 data (prices, tutorial steps, daily goals) get the core
-- loop that runs (MapBuilder published it before the map was built).
local activeLoop = CoreLoop.Active()
safely("MilestoneService.Init", MilestoneService.Init, notify, activeLoop)
safely("AxeService.Init", AxeService.Init, notify)
safely("BlueprintService.Init", BlueprintService.Init, notify, {
	UseBlueprint = remote.UseBlueprint,
	DropBlueprint = remote.DropBlueprint,
})
safely("ShopService.Init", ShopService.Init, mapFolder, remote.BuyItem, remote.EquipItem, notify, activeLoop)
-- The tutorial's pad steps: the pad went down, the truck rolled out.
VehicleService.Hooks.padEvent = function(player: Player, event: string)
	if event == "padPlaced" then
		QuestService.Event(player, "padPlaced")
	elseif event == "truckSpawned" then
		QuestService.Event(player, "truckSpawned")
	end
end
safely("VehicleService.Init", VehicleService.Init, notify)
safely(
	"QuestService.Init",
	QuestService.Init,
	remote.SkipTutorial,
	notify,
	activeLoop,
	remote.ResetTutorial,
	remote.TutorialSeen
)
safely("DailyService.Init", DailyService.Init, notify, nil, activeLoop)
safely("EventService.InitEvent", EventService.InitEvent, notify)
safely("BiomeService.Init", BiomeService.Init, notify)
safely("MonetizationService.Init", MonetizationService.Init, remote.BuyRobuxItem, notify)
safely("MonetizationService.SetPassListener", MonetizationService.SetPassListener, function(player: Player, key: string)
	if key == GameConfig.LuxAxeId then
		AxeService.Ensure(player, GameConfig.LuxAxeId)
	elseif key == "TimberClassic" then
		ShopService.GrantPassTruck(player)
	end
end)
VehicleService.Hooks.freeRecall = function(player: Player): boolean
	return MonetizationService.HasPass(player, "TowService")
end
VehicleService.Hooks.saleMultiplier = function(player: Player): number
	return MonetizationService.SaleMultiplier(player)
end
safely("PaintService.Init", PaintService.Init, remote.PaintTruck, notify)
safely("FieldGuideService.Init", FieldGuideService.Init, notify)
safely("NodeService.Init", NodeService.Init, notify)
safely("AetherService.Init", AetherService.Init, notify)
safely("GondolaService.Init", GondolaService.Init, mapFolder, notify)
safely("LeaderboardService.Init", LeaderboardService.Init, remote.BoardRequest, remote.BoardData)
safely("SaveSlotService.Init", SaveSlotService.Init, remote.SlotAction, remote.SlotState, notify, {
	commit = function(player: Player)
		commitSlot(player)
	end,
	rebuild = function(player: Player)
		rebuildSlot(player)
	end,
})
safely("PlotService.Init", PlotService.Init, mapFolder, {
	PlaceBlueprint = remote.PlaceBlueprint,
	MoveBlueprint = remote.MoveBlueprint,
	SellPlaced = remote.SellPlaced,
	PaintPiece = remote.PaintPiece,
	UpgradePlot = remote.UpgradePlot,
	PlotOffer = remote.PlotOffer,
	ClaimPlot = remote.ClaimPlot,
	PlotPass = remote.PlotPass,
	VisitPlot = remote.VisitPlot,
}, notify, { gates = LoadState.Gates })
safely("ForestService.Init", ForestService.Init, { WorldFX = remote.WorldFX }, notify)
safely("WeatherService.Init", WeatherService.Init, remote.WorldFX)
safely("RegionWake.Init", RegionWake.Init)
-- Murph is built now (the tutorial starts at his camp); every other
-- townsperson is a step of the deferred build, nearest the player first, once
-- their meshes are in (NPCService, LoadState.Queue). Old Hank's Talk prompt
-- opens the plot sale, so it is hooked when the last one is built.
safely("NPCService.Init", NPCService.Init, mapFolder, {
	defer = LoadState.Queue.Add,
	onBuilt = function(id: string)
		if id == PlotSalesmanData.Id then
			safely("PlotService.HookSalesman", PlotService.HookSalesman, mapFolder)
		end
	end,
	onDone = function()
		LoadState.Gates.Set("npcs")
	end,
})
-- The v2 core loop (V2_PLAN.md M1.4), dormant on live (CoreLoop 1): grab
-- and drag loose wood, and Studio's /spawnwood to try it.
if CoreLoop.V2() then
	-- Grabbing a piece: the tutorial's drag step and the funnel's pickup.
	GrabService.Hooks.onGrab = function(player: Player, _piece: GrabService.Piece)
		safely("woodGrabbed", function()
			MilestoneService.Mark(player, "First log picked up")
			QuestService.Event(player, "woodGrabbed")
		end)
	end
	-- The sell pad sells loose wood by volume (M1.7).
	local woodFolder = mapFolder:FindFirstChild("Wood")
	if not woodFolder then
		local made = Instance.new("Folder")
		made.Name = "Wood"
		made.Parent = mapFolder
		woodFolder = made
	end
	-- Loose wood (M1.3): every piece a cut frees, its despawn and caps, and
	-- WoodWatch (which judges held wood too, so GrabService doesn't).
	safely("WoodService.Init", WoodService.Init, { worldFx = remote.WorldFX, folder = woodFolder })
	GrabService.SetResolver(function(part: BasePart): GrabService.Piece?
		return WoodService.FromPart(part) :: any
	end)
	GrabService.JudgeMoves = false
	safely("GrabService.Init", GrabService.Init, { Grab = remote.Grab, Release = remote.Release }, notify)
	-- Placed sawmills (M2.2): a straight log in the intake comes out as planks.
	safely("SawmillService.Init", SawmillService.Init, notify, remote.SawmillSet)
	-- Planers (a plank in, a finished board out) and the conveyor belts that feed
	-- and carry from them (V2_PLAN.md §2h, §10).
	safely("PlanerService.Init", PlanerService.Init, notify, remote.PlanerSet)
	safely("BeltService.Init", BeltService.Init)
	safely("ChopSawService.Init", ChopSawService.Init, notify, remote.ChopSawSet)
	safely("DevCommands.Init", DevCommands.Init, notify)
	safely("AdminService.Init", AdminService.Init, notify)
	AdminService.SetReply(function(owner: Player, ok: boolean, text: string)
		remote.AdminResult:FireClient(owner, ok, text)
	end)
	AdminService.SetAccessSend(function(who: Player, payload: { [string]: any })
		remote.AdminAccess:FireClient(who, payload)
	end)
	AdminService.SetHooks({
		resetTutorial = QuestService.Reset,
		publishBlueprints = BlueprintService.Publish,
		placeSample = PlotService.PlaceSample,
		clearSamples = PlotService.ClearSamples,
	})
	-- A sold piece's "+$" pop on the pad: what its payee is paid for it.
	local function saleFx(model: Model)
		local piece = WoodService.FromModel(model)
		if not piece then
			return
		end
		local payeeId = SellLogic.Payee(piece.ownerId, piece.lastHolderId, function(userId: number): boolean
			return Players:GetPlayerByUserId(userId) ~= nil
		end)
		local payee = if payeeId then Players:GetPlayerByUserId(payeeId) else nil
		if payee then
			WoodService.SaleFx(model, SellLogic.Payout(piece.value, MonetizationService.SaleMultiplier(payee)))
		end
	end
	safely("SellService.Init", SellService.Init, {
		zone = sellZone,
		woodFolder = woodFolder :: Instance,
		resolve = function(model: Model): SellService.Piece?
			-- Only wood WoodWatch last found where it should be (no teleports to the pad).
			local piece = WoodService.FromModel(model)
			if piece and not WoodService.VerdictOk(piece) then
				return nil
			end
			return piece :: any
		end,
		addCash = function(player: Player, amount: number, reason: string, sku: string): number?
			local credited = EconomyService.AddCash(player, amount, reason, sku)
			return credited
		end,
		saleMultiplier = MonetizationService.SaleMultiplier,
		notify = notify,
		release = function(model: Model)
			TruckLoad.ReleaseWeld(model) -- the weld goes before the piece is sold
			GrabService.ReleasePiece(model, "sold")
		end,
		forget = function(model: Model)
			saleFx(model)
			WoodService.Forget(model)
			GrabService.Unregister(model)
		end,
		onSold = onWoodSold,
		-- Instant Delivery v2: the wood riding on the player's beds.
		bedPieces = function(player: Player): { Model }
			return TruckLoad.PiecesOn(player)
		end,
		walletRoom = function(player: Player): number
			local profile = ProfileService.GetProfile(player)
			return if profile then GameConfig.CashCap - profile.cash else 0
		end,
	})
	-- Loose wood rides on the truck beds (M1.6): by friction, simulated by
	-- the driver's device while they drive, saved in profile.truckLoad.
	safely("TruckLoad.Init", TruckLoad.Init, {
		woodFolder = woodFolder :: Instance,
		truckOf = VehicleService.GetVehicle,
		profileOf = function(player: Player): any
			return ProfileService.GetProfile(player)
		end,
		notify = notify,
		-- A saved load comes back as WoodService pieces (its sections
		-- linked by contact), so they cut, grab and sell like any other.
		build = function(saved: any, owner: Player, cf: CFrame, graceSec: number): Model?
			local model = TruckLoad.Build(saved, owner, cf, graceSec)
			if model then
				GrabService.Unregister(model)
				WoodService.Register(model, {
					woodId = saved.w,
					nodes = {},
					parts = {},
					ownerId = owner.UserId,
					figure = saved.f,
					boost = saved.x,
					lux = saved.l == true,
					mill = saved.m,
					board = saved.d,
					createdAt = os.clock() - GameConfig.PickupGraceSec + math.max(0, graceSec),
				})
			end
			return model
		end,
		forget = function(model: Model)
			WoodService.Forget(model)
			GrabService.Unregister(model)
		end,
		moved = WoodService.Moved,
	})
	VehicleService.Hooks.onDriverChanged = TruckLoad.OnDriverChanged
	VehicleService.Hooks.onRebuild = TruckLoad.OnRebuild
	VehicleService.Hooks.loadCount = TruckLoad.LoadCount
	VehicleService.Hooks.onDespawn = function(_player: Player, truck: Model)
		TruckLoad.DropWelds(truck)
	end
	-- A piece of yours came to rest on your own bed: the tutorial's "load"
	-- step (TutorialData.StepsV2) and the funnel.
	TruckLoad.Hooks.saleMultiplier = function(player: Player): number
		return MonetizationService.SaleMultiplier(player)
	end
	TruckLoad.Hooks.onLoaded = function(player: Player)
		MilestoneService.Mark(player, "First log loaded")
		QuestService.Event(player, "woodLoaded")
	end
	-- The section trees (M1.3): the Living Forest moves onto them, and the
	-- Chop remote cuts them (and loose pieces) wherever you swing.
	SectionTrees.StumpHold = QuestService.StumpHoldFor
	SectionTrees.LogMultiplier = MonetizationService.LogMultiplier
	safely("ForestService.UseV2", ForestService.UseV2, SectionTrees, WoodService.SetFigure)
	-- A felling counts for whoever cut the most of the tree (stats, the
	-- tutorial's treeFelled, dailies, the Field Guide), as in v1.
	SectionTrees.Hooks.onFelled = function(feller: Player, rec: SectionTrees.TreeRecord)
		local profile = ProfileService.GetProfile(feller)
		if not profile then
			return
		end
		profile.stats.treesChopped += 1
		MilestoneService.Mark(feller, "First tree felled")
		QuestService.Event(feller, "treeFelled")
		DailyService.Event(feller, "treeFelled", 1)
		FieldGuideService.Discover(feller, rec.def.id)
		QuestService.RefreshNextGoal(feller)
	end
	SectionTrees.Hooks.onSwing = function(player: Player)
		MilestoneService.Mark(player, "First chop")
	end
	safely("SectionTrees.Init", SectionTrees.Init, {
		notify = notify,
		worldFx = remote.WorldFX,
		getAxe = AxeService.GetEquippedAxe,
		canChop = BiomeService.CanChop,
		swingDue = function(player: Player): number
			return nextSwingAt[player.UserId] or 0
		end,
		setSwingDue = function(player: Player, at: number)
			nextSwingAt[player.UserId] = at
		end,
	})
	remote.Chop.OnServerEvent:Connect(function(player: Player, part: unknown, hitPos: unknown, normal: unknown)
		local ok, why = SectionTrees.Chop(player, part, hitPos, normal)
		-- One line per swing, matching the client's [Chop] note, so Output
		-- shows whether the server cut or why it refused. Not inside
		-- SectionTrees.Chop: the specs call that directly.
		if ok then
			print("[Chop] cut")
		else
			print("[Chop] rejected: " .. tostring(why))
		end
	end)
	-- The isles take loose wood (M1.7b): the Cloud Chutes and the Starfall
	-- Forge are hoppers found the way the pad finds pieces, the Sky Bin you
	-- place on your plot (a tagged model, AetherService) sells through
	-- SellService.PayEntries, and wood that falls off the isles is lost.
	safely("AetherService.InitV2", AetherService.InitV2, {
		woodFolder = woodFolder :: Instance,
		resolve = function(model: Model): SellService.Piece?
			-- As the pad: only wood WoodWatch last found where it should be.
			local piece = WoodService.FromModel(model)
			if piece and not WoodService.VerdictOk(piece) then
				return nil
			end
			return piece :: any
		end,
		release = function(model: Model)
			GrabService.ReleasePiece(model, "taken")
		end,
		forget = function(model: Model)
			WoodService.Forget(model)
			GrabService.Unregister(model)
		end,
		heldBy = GrabService.HeldBy,
	})
end

-- Wave 0 stubs. Each client -> server remote reserved here is connected
-- once, inside the service that owns it (RateLimiter.Allow, then drop).
-- if Module.Init is its own pcall: a throw is a BootReport warning and the
-- later stubs still start. BadgeSync is server -> client, so nothing connects it.
BootReport.StartStubs({
	{
		name = "DialogueService",
		init = function()
			if DialogueService.Init then
				DialogueService.Init(remote.Dialogue)
			end
		end,
	},
	{
		name = "BoxService",
		init = function()
			if BoxService.Init then
				BoxService.Init(remote.BoxOpen)
				-- Opening a sawmill, planer or belt box starts the one-time placement ghost.
				BoxService.OnPlace = function(player: Player, uid: string, itemId: string)
					remote.WorldFX:FireClient(player, "PlaceBox", { uid = uid, itemId = itemId })
				end
			end
		end,
	},
	{
		name = "GateService",
		init = function()
			if GateService.Init then
				GateService.Init(remote.TollPay)
				GateService.SetupWorld(mapFolder)
			end
		end,
	},
	{
		name = "FerryService",
		init = function()
			if FerryService.Init then
				FerryService.Init(remote.FerryBoard)
				FerryService.SetupWorld(mapFolder, notify)
			end
		end,
	},
	{
		name = "PermissionService",
		init = function()
			if PermissionService.Init then
				PermissionService.Init(remote.SetPermission)
			end
		end,
	},
	{
		name = "LogicService",
		init = function()
			if LogicService.Init then
				LogicService.Init(remote.Wire)
			end
		end,
	},
	{
		name = "EventService",
		init = function()
			if EventService.Init then
				EventService.Init({
					ExpandLand = remote.ExpandLand,
					SpawnPadPress = remote.SpawnPadPress,
				})
			end
		end,
	},
	{
		name = "BlastService",
		init = function()
			if BlastService.Init then
				BlastService.Init(notify)
			end
		end,
	},
	{
		name = "HazardService",
		init = function()
			if HazardService.Init then
				HazardService.Init(notify)
			end
		end,
	},
	{
		name = "HermitService",
		init = function()
			HermitService.Init({
				profile = function(player: Player): any
					return ProfileService.GetProfile(player)
				end,
				notify = notify,
				say = function(player: Player, text: string)
					remote.Dialogue:FireClient(
						player,
						{ line = "hermit", text = text, speaker = "Hermit", choice = false, noLabel = "Close" }
					)
				end,
				grantAxe = function(player: Player, axeId: string)
					AxeService.Grant(player, axeId, false)
				end,
				ownsAxe = function(player: Player, axeId: string): boolean
					local counts = AxeService.OwnedCounts(player)
					return (counts[axeId] or 0) > 0
				end,
			}, mapFolder)
		end,
	},
	{
		name = "BadgeService",
		init = function()
			if BadgeService.Init then
				BadgeService.Init()
			end
		end,
	},
})

-- The pose only. Damage stays on Chop / ChopTree / MineNode, which still
-- arm the next swing when they arrive (setSwingDue is unchanged). SwingLen
-- is that axe's cooldown so the clip finishes when the next press is allowed.
local function onSwing(player: Player, woodId: unknown, cancel: unknown)
	if not RateLimiter.Allow(player, "Swing") then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	if cancel == true then
		char:SetAttribute("SwingLen", 0)
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.Sit or humanoid.SeatPart ~= nil then
		return
	end
	local carried = player:GetAttribute("CarriedLogs")
	if type(carried) == "number" and carried > 0 then
		return
	end
	local axe = AxeService.GetEquippedAxe(player)
	if not axe then
		return
	end
	local len = GameConfig.SwingCooldown
	if woodId ~= "node" and woodId ~= "v1" then
		if type(woodId) ~= "string" then
			return
		end
		local _, cooldown = ItemCatalog.AxeStats(axe, woodId)
		if type(cooldown) == "number" then
			len = cooldown
		end
	end
	char:SetAttribute("SwingAt", workspace:GetServerTimeNow())
	char:SetAttribute("SwingLen", len)
end
remote.Swing.OnServerEvent:Connect(onSwing)
remote.MineNode.OnServerEvent:Connect(onMineNode)
remote.UseInstantDelivery.OnServerEvent:Connect(onInstantDelivery)

-- The v1 loop's remotes (whole trees, carried logs, bed slots, the sell
-- button). The live game is v2: Chop, Grab and the sell pad own those
-- intents, so a client can't drive the old handlers. A Studio override
-- back to loop 1 still connects them.
if not CoreLoop.V2() then
	remote.ChopTree.OnServerEvent:Connect(onChopTree)
	remote.PickupLog.OnServerEvent:Connect(serverPickupLog)
	remote.LoadToTruck.OnServerEvent:Connect(onLoadToTruck)
	remote.SellLogs.OnServerEvent:Connect(onSellLogs)
end
remote.DropAxe.OnServerEvent:Connect(AxeService.Drop)
remote.AdminRun.OnServerEvent:Connect(function(player: Player, request: unknown)
	if RateLimiter.Allow(player, "AdminRun") then
		AdminService.RunRequest(player, request)
	end
end)
remote.Sprint.OnServerEvent:Connect(function(player: Player, on: unknown)
	if RateLimiter.Allow(player, "Sprint") then
		player:SetAttribute("Sprinting", SprintLogic.Wants(on))
	end
end)
remote.CallTruck.OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.Allow(player, "CallTruck") then
		return
	end
	local ok, why = VehicleService.Recall(player)
	if ok then
		notify(player, "Your truck is back on its pad.")
	elseif why then
		notify(player, why)
	end
end)

-- Settings (SettingsLogic), mirrored on player attributes so the client
-- applies them when the save loads.
remote.SaveSetting.OnServerEvent:Connect(function(player: Player, key: unknown, value: unknown)
	if not RateLimiter.Allow(player, "SaveSetting") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or type(key) ~= "string" then
		return
	end
	if not SettingsLogic.Set(profile.settings, key, value) then
		return
	end
	local attr = SettingsLogic.Attributes[key :: SettingsLogic.Key]
	if attr then
		player:SetAttribute(attr, (profile.settings :: any)[key])
	end
	if key == "showOnBoard" then
		safely(
			"LeaderboardService.SettingChanged",
			LeaderboardService.SettingChanged,
			player,
			profile.settings.showOnBoard
		)
	end
end)

-- Player lifecycle --------------------------------------------------------

-- PlayerAdded and the "already here" loop can both see the same player
-- (they join while the loop is running). A second pass would start a
-- second save session and hand them a second plot.
local joining: { [Player]: boolean } = {}

local function dropCarriedLogs(player: Player)
	local hands = CarryService.Hands(player)
	if not hands then
		return
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local dropPos = if hrp then hrp.Position else Vector3.new(0, 3, 40)
	for uid in pairs(hands) do
		TreeService.DropLog(uid, dropPos, player)
	end
	table.clear(hands)
	player:SetAttribute("CarriedLogs", 0)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		dropCarriedLogs(player)
	end)
	if player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10) then
		AxeService.GiveLoadout(player, character)
		BlueprintService.GiveLoadout(player, character) -- the Hammer, then any plans you carry
	end
end

-- An owned truck stays equipped. No owned truck means no id and no spawn
-- (the old Rustbucket fallback is gone). A trailer that isn't owned comes off.
local function ownedEquipped(profile: ProfileSchema.Profile): string
	if profile.equippedTrailer ~= "" and not table.find(profile.ownedTrailers, profile.equippedTrailer) then
		profile.equippedTrailer = ""
	end
	local id = profile.equippedTruck
	if ItemCatalog.GetTruck(id) and table.find(profile.ownedTrucks, id) then
		return id
	end
	local first = profile.ownedTrucks[1]
	if type(first) == "string" and ItemCatalog.GetTruck(first) then
		profile.equippedTruck = first
		return first
	end
	profile.equippedTruck = ""
	return ""
end

local function onPlayerAdded(player: Player)
	if joining[player] then
		return
	end
	joining[player] = true
	player:SetAttribute("ProfileLoaded", false) -- the HUD shows "Loading your save..."
	player:SetAttribute("CarriedLogs", 0)
	CarryService.Start(player)
	lastNotice[player.UserId] = {}

	-- Timing lines for the join: a stall shows as the first one that never
	-- prints (the HUD says "Loading your save..." until ProfileLoaded).
	local joinStart = os.clock()
	local function joinLap(what: string)
		print(string.format("[GameServer] %s: %s (%.1fs)", player.Name, what, os.clock() - joinStart))
	end
	joinLap("loading the save")
	local profile, err = ProfileService.LoadProfile(player)
	if profile then
		joinLap("save loaded")
	end
	if not profile then
		if err == "failed" then
			player:Kick("Timberline Tycoon couldn't load your save right now. Your progress is safe. Please rejoin.")
		end
		return -- "left": they're already gone
	end

	local truckId = ownedEquipped(profile)
	player:SetAttribute("OwnsTruck", truckId ~= "")
	player:SetAttribute("EquippedTruck", truckId)

	-- The v2 loop: v1 logs still on hand are bought back (and a first join
	-- topped up to StartingCash) into v2Credit, before the truck spawns or
	-- left-behind logs come back (V2_PLAN.md §14).
	local boughtBack = 0
	if CoreLoop.V2() then
		safely("ProfileSchema.MigrateV2", function()
			local moved = ProfileSchema.MigrateV2(profile)
			boughtBack = moved.boughtBack
			if moved.migrated then
				print(
					string.format(
						"[GameServer] %s's save is now on the v2 loop (bought back $%d, topped up $%d)",
						player.Name,
						moved.boughtBack,
						moved.toppedUp
					)
				)
			end
		end)
	end

	player:SetAttribute("Cash", profile.cash)
	profile.settings = SettingsLogic.Sanitize(profile.settings)
	for key, attr in pairs(SettingsLogic.Attributes) do
		player:SetAttribute(attr, (profile.settings :: any)[key])
	end
	if profile.pendingCash > 0 then
		player:SetAttribute("PendingCash", profile.pendingCash)
		EconomyService.PayPending(player)
	end
	-- What MigrateV2 left owed, through the wallet (overflow banked).
	if CoreLoop.V2() and profile.v2Credit > 0 then
		safely("pay v2Credit", function()
			local owed = math.floor(profile.v2Credit)
			profile.v2Credit = 0
			local credited, banked = EconomyService.AddOwedCash(player, owed, "v2 buy-back", "v2BuyBack")
			local text = ProfileSchema.CreditText(credited + banked, boughtBack)
			if text then
				notify(player, text)
			end
		end)
	end
	-- Before the truck and the left-behind logs come back. A spot on a new
	-- pad, under the ground, or in the water waits in the town truck lot
	-- instead of appearing on somebody's yard. Claiming still moves it onto
	-- the plot. No truck is built here: a truck only ever exists on its own
	-- spawn pad, so it comes out when its pad's button is pressed (the pads
	-- are restored in ShopService.PlayerJoined).
	joinLap("account set up")
	safely("PlotService.ParkStrays", PlotService.ParkStrays, profile)
	-- Logs left behind (Truck to lot from afar) that were still lying out
	-- when the player last left: back where they lay, at most MaxLeftLogs
	-- of them (saves made under the old cap can hold 150).
	if #profile.leftLoad > 0 and not CoreLoop.V2() then
		safely("VehicleService.RestoreLeftLoad", function()
			local saved = LeftLoad.ToRestore(profile.leftLoad)
			if #saved < #profile.leftLoad then
				warn(
					string.format(
						"[GameServer] %s: %d saved left-behind log(s) over MaxLeftLogs (%d) not restored",
						player.Name,
						#profile.leftLoad - #saved,
						GameConfig.MaxLeftLogs
					)
				)
			end
			local n = VehicleService.RestoreLeftLoad(player, saved)
			profile.leftLoad = {}
			if n > 0 then
				notify(
					player,
					string.format(
						"Your %d left-behind log%s are still where you left them.",
						n,
						if n == 1 then "" else "s"
					)
				)
			end
		end)
	end

	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	local existing = player.Character
	if existing then
		task.spawn(onCharacterAdded, player, existing)
	end

	player:SetAttribute("ProfileLoaded", true)
	joinLap("ready (ProfileLoaded)")
	LoadState.PlayerCanPlay(player.Name)
	print(
		string.format(
			"[Load] %s can play: %.1fs after joining, server up %.0fs",
			player.Name,
			os.clock() - joinStart,
			workspace.DistributedGameTime
		)
	)
	remote.CashChanged:FireClient(player, profile.cash)
	safely("MilestoneService.Start", MilestoneService.Start, player, profile)
	safely("QuestService.Start", QuestService.Start, player, profile)
	safely("DailyService.Start", DailyService.Start, player, profile)
	safely("EventService.Start", EventService.Start, player, profile)
	safely("ShopService.PlayerJoined", ShopService.PlayerJoined, player, profile)
	safely("MonetizationService.PlayerJoined", MonetizationService.PlayerJoined, player, profile)
	safely("FieldGuideService.Refresh", FieldGuideService.Refresh, player)
	safely("NodeService.Publish", NodeService.Publish, player)
	safely("AetherService.PlayerJoined", AetherService.PlayerJoined, player, profile)
	safely("PlotService.PlayerJoined", PlotService.PlayerJoined, player, profile)
	safely("ForestService.PlayerJoined", ForestService.PlayerJoined, player, profile)
	safely("SaveSlotService.PlayerJoined", SaveSlotService.PlayerJoined, player)
	safely("LeaderboardService.PlayerJoined", LeaderboardService.PlayerJoined, player, profile.settings.showOnBoard)
	print(string.format("[GameServer] %s joined (cash $%d)", player.Name, profile.cash))
end

-- Into the profile before the final save. Also run from OnLastSave
-- (ProfileService), so a shutdown save that beats PlayerRemoving still
-- gets them. Once only: the truck save destroys the wood, and a second
-- pass would write an empty load.
local function savePlaytime(player: Player)
	MilestoneService.Stop(player)
end

local function saveTruckLoad(player: Player)
	if CoreLoop.V2() then
		TruckLoad.PlayerRemoving(player)
	end
end

local function saveLeftBehind(player: Player)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local left = TreeService.TakeLeftBehind(player.UserId)
	for _, entry in ipairs(left) do
		if #profile.leftLoad >= GameConfig.MaxLeftLogs then
			break
		end
		table.insert(profile.leftLoad, entry)
	end
end

LeaveCommit.Add("playtime", savePlaytime)
LeaveCommit.Add("truckLoad", saveTruckLoad)
LeaveCommit.Add("leftBehind", saveLeftBehind)

-- A slot change uses the leave path to pull wood into the profile, then
-- builds the other slot the way a join does. Commit runs before the swap.
local function commitSlotNow(player: Player)
	dropCarriedLogs(player)
	if CoreLoop.V2() then
		TruckLoad.PlayerRemoving(player)
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local left = TreeService.TakeLeftBehind(player.UserId)
	for _, entry in ipairs(left) do
		if #profile.leftLoad >= GameConfig.MaxLeftLogs then
			break
		end
		table.insert(profile.leftLoad, entry)
	end
end

local function rebuildSlotNow(player: Player)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local truckId = ownedEquipped(profile)
	player:SetAttribute("OwnsTruck", truckId ~= "")
	player:SetAttribute("EquippedTruck", truckId)
	AxeService.PlayerRemoving(player)
	BlueprintService.PlayerRemoving(player)
	VehicleService.DespawnTruck(player)
	-- A different save, same pad: the buildings are pad-relative, and they
	-- already picked a homestead this visit.
	if not PlotService.Reload(player, profile) then
		-- No pad yet, so a bad saved spot must not spawn on one.
		PlotService.ParkStrays(profile)
		PlotService.PlayerJoined(player, profile)
	end
	ShopService.PlayerJoined(player, profile)
	ForestService.PlayerJoined(player, profile)
	DailyService.Start(player, profile)
	safely("EventService.Start", EventService.Start, player, profile)
	QuestService.Start(player, profile)
	player:SetAttribute("Cash", profile.cash)
	remote.CashChanged:FireClient(player, profile.cash)
	-- Settings and the Robux passes live on the account. A slot swap does
	-- not change them; mirror them again so the client stays in step.
	profile.settings = SettingsLogic.Sanitize(profile.settings)
	for key, attr in pairs(SettingsLogic.Attributes) do
		player:SetAttribute(attr, (profile.settings :: any)[key])
	end
	if type(profile.passes) == "table" then
		for key, on in pairs(profile.passes) do
			if on == true then
				player:SetAttribute("Pass_" .. key, true)
			end
		end
	end
	player:SetAttribute("DoubleWoodUntil", profile.doubleWoodUntil)
	player:SetAttribute("InstantDeliveries", profile.instantDeliveries)
	pcall(function()
		player:LoadCharacterAsync()
	end)
end

commitSlot = commitSlotNow
rebuildSlot = rebuildSlotNow

local function onPlayerRemoving(player: Player)
	joining[player] = nil
	safely("dropCarriedLogs", dropCarriedLogs, player) -- back into the world for others, before the character goes
	safely("AxeService.PlayerRemoving", AxeService.PlayerRemoving, player) -- world models go; the axes stay in the save
	safely("BlueprintService.PlayerRemoving", BlueprintService.PlayerRemoving, player) -- dropped plans stay in the save too
	safely("MonetizationService.PlayerRemoving", MonetizationService.PlayerRemoving, player)
	safely("PaintService.PlayerRemoving", PaintService.PlayerRemoving, player)
	safely("PlotService.PlayerRemoving", PlotService.PlayerRemoving, player)
	safely("SaveSlotService.PlayerRemoving", SaveSlotService.PlayerRemoving, player)
	safely("ForestService.PlayerRemoving", ForestService.PlayerRemoving, player)
	safely("GateService.PlayerRemoving", GateService.PlayerRemoving, player)
	safely("LeaderboardService.PlayerRemoving", LeaderboardService.PlayerRemoving, player) -- reads the score now, before the release
	-- Playtime, the truck's loose wood and left-behind logs. Before the
	-- release, and again (as a no-op) from the final save if shutdown
	-- already committed them.
	safely("LeaveCommit.Flush", LeaveCommit.Flush, player)
	ProfileService.ReleaseProfile(player)
	VehicleService.DespawnTruck(player)
	RateLimiter.Forget(player)
	CarryService.Stop(player)
	nextSwingAt[player.UserId] = nil
	lastNotice[player.UserId] = nil
	print(string.format("[GameServer] %s left (saving)", player.Name))
end

-- Every service that a player's first minute needs has started; the rest of
-- the world (the townsfolk, the scenery, the sky) builds in the background.
LoadState.Gates.Set("services")
LoadState.Stage("services")
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
-- Catch players who joined before this script ran.
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- The boot report (PLAY-01): how long the world took, trees, players.
-- The same timings go to Creator Hub as custom events. LogCustomEvent
-- needs a player, so if the server is still empty they ride the first join.
print(
	string.format(
		"[Load] GameServer init done in %.1fs (all services started, listening for players)",
		os.clock() - initStart
	)
)
LoadState.Seal() -- "fully built" can now be declared once the queue and forest are done
print(BootReport.Line(workspace, #Players:GetPlayers()))
if not BootReport.Log(workspace, Players:GetPlayers(), AnalyticsService) then
	local bootConn: RBXScriptConnection? = nil
	bootConn = Players.PlayerAdded:Connect(function(player: Player)
		if BootReport.Log(workspace, { player }, AnalyticsService) and bootConn then
			bootConn:Disconnect()
			bootConn = nil
		end
	end)
end
