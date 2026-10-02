--!strict
-- GameServer: bootstrap + remote handlers.
--   * Creates ReplicatedStorage/Remotes (names listed in Shared/Net).
--   * PlayerAdded: load save -> spawn Rustbucket -> hand over every owned axe
--     (AxeService; axes are items the player can switch, drop and pick up).
--   * PlayerRemoving: drop carried logs, final save + release the session.
--   * Every remote is rate-limited and server-validated. The client only
--     sends intents; TreeService/EconomyService own the truth. BuyItem is
--     handled by ShopService.
-- Autosave, shutdown flushing and session locks are ProfileStore's job
-- (see ProfileService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AetherService = require(script.Parent.AetherService)
local AxeService = require(script.Parent.AxeService)
local CarryService = require(script.Parent.CarryService)
local BiomeService = require(script.Parent.BiomeService)
local BootReport = require(script.Parent.BootReport)
local DailyService = require(script.Parent.DailyService)
local DevCommands = require(script.Parent.DevCommands)
local EconomyService = require(script.Parent.EconomyService)
local FieldGuideService = require(script.Parent.FieldGuideService)
local ForestService = require(script.Parent.ForestService)
local GondolaService = require(script.Parent.GondolaService)
local GrabService = require(script.Parent.GrabService)
local SellService = require(script.Parent.SellService)
local LeftLoad = require(script.Parent.LeftLoad)
local MilestoneService = require(script.Parent.MilestoneService)
local MonetizationService = require(script.Parent.MonetizationService)
local NodeService = require(script.Parent.NodeService)
local NPCService = require(script.Parent.NPCService)
local PickupGrace = require(script.Parent.PickupGrace)
local PlaceCheck = require(script.Parent.PlaceCheck)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local ShopService = require(script.Parent.ShopService)
local TreeService = require(script.Parent.TreeService)
local VehicleService = require(script.Parent.VehicleService)
local WeatherService = require(script.Parent.WeatherService)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)

-- Runs one service's Init, join or leave hook on its own: an error in one
-- is logged with a traceback and doesn't stop the others (a broken Init
-- must never keep players out). tostring first: debug.traceback itself
-- errors on a non-string error.
local function safely(name: string, fn: (...any) -> ...any, ...: any)
	local args = table.pack(...)
	local ok, err = xpcall(function(): any
		fn(table.unpack(args, 1, args.n))
		return nil
	end, function(e: any): string
		return debug.traceback(tostring(e), 2)
	end)
	if not ok then
		warn(string.format("[GameServer] %s failed:\n%s", name, tostring(err)))
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
local sellArea = mapFolder:WaitForChild("SellArea", 600)
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
	-- The Sky Bin sits by the pad: logs sent down the Cloud Chute.
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
local function onInstantDelivery(player: Player)
	if not RateLimiter.Allow(player, "SellLogs") then
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
	if not ProfileService.GetProfile(player) then
		return -- left meanwhile: nothing was credited
	end
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
safely("ShopService.Init", ShopService.Init, mapFolder, remote.BuyItem, remote.EquipItem, notify, activeLoop)
safely("VehicleService.Init", VehicleService.Init, notify)
safely("QuestService.Init", QuestService.Init, remote.SkipTutorial, notify, activeLoop)
safely("DailyService.Init", DailyService.Init, notify, nil, activeLoop)
safely("BiomeService.Init", BiomeService.Init, notify)
safely("MonetizationService.Init", MonetizationService.Init, remote.BuyRobuxItem, notify)
safely("FieldGuideService.Init", FieldGuideService.Init, notify)
safely("NodeService.Init", NodeService.Init, notify)
safely("AetherService.Init", AetherService.Init, notify)
safely("GondolaService.Init", GondolaService.Init, mapFolder, notify)
safely("PlotService.Init", PlotService.Init, mapFolder, {
	PlaceBlueprint = remote.PlaceBlueprint,
	MoveBlueprint = remote.MoveBlueprint,
	SellPlaced = remote.SellPlaced,
	UpgradePlot = remote.UpgradePlot,
}, notify)
safely("ForestService.Init", ForestService.Init, { PlantSeed = remote.PlantSeed, WorldFX = remote.WorldFX }, notify)
safely("WeatherService.Init", WeatherService.Init, remote.WorldFX)
safely("NPCService.Init", NPCService.Init, mapFolder)
-- The v2 core loop (V2_PLAN.md M1.4), dormant on live (CoreLoop 1): grab
-- and drag loose wood, and Studio's /spawnwood to try it.
if CoreLoop.V2() then
	safely("GrabService.Init", GrabService.Init, { Grab = remote.Grab, Release = remote.Release }, notify)
	safely("DevCommands.Init", DevCommands.Init, notify)
	-- Grabbing a piece: the tutorial's drag step and the funnel's pickup.
	GrabService.Hooks.onGrab = function(player: Player, _piece: GrabService.Piece)
		safely("woodGrabbed", function()
			MilestoneService.Mark(player, "First log picked up")
			QuestService.Event(player, "woodGrabbed")
		end)
	end
	-- Still to come, each its own slice's call (QuestService.Event):
	--   SectionTrees (M1.3), once per tree felled, for the feller:
	--     QuestService.Event(feller, "treeFelled") and
	--     DailyService.Event(feller, "treeFelled", 1), as onChopTree does;
	--   TruckLoad (M1.6), when a piece comes to rest in its owner's own
	--     BedZone: QuestService.Event(owner, "woodLoaded") and
	--     MilestoneService.Mark(owner, "First log loaded").
	-- The sell pad sells loose wood by volume (M1.7).
	local woodFolder = mapFolder:FindFirstChild("Wood")
	if not woodFolder then
		local made = Instance.new("Folder")
		made.Name = "Wood"
		made.Parent = mapFolder
		woodFolder = made
	end
	safely("SellService.Init", SellService.Init, {
		zone = sellZone,
		woodFolder = woodFolder :: Instance,
		resolve = function(model: Model): SellService.Piece?
			local root = model.PrimaryPart
			local piece = if root then GrabService.PieceOf(root) else nil
			return piece :: any
		end,
		addCash = function(player: Player, amount: number, reason: string, sku: string): number?
			local credited = EconomyService.AddCash(player, amount, reason, sku)
			return credited
		end,
		saleMultiplier = MonetizationService.SaleMultiplier,
		notify = notify,
		release = function(model: Model)
			GrabService.ReleasePiece(model, "sold")
		end,
		forget = GrabService.Unregister,
		onSold = onWoodSold,
	})
end
remote.MineNode.OnServerEvent:Connect(onMineNode)
remote.UseInstantDelivery.OnServerEvent:Connect(onInstantDelivery)

remote.ChopTree.OnServerEvent:Connect(onChopTree)
remote.PickupLog.OnServerEvent:Connect(serverPickupLog)
remote.LoadToTruck.OnServerEvent:Connect(onLoadToTruck)
remote.SellLogs.OnServerEvent:Connect(onSellLogs)
remote.DropAxe.OnServerEvent:Connect(AxeService.Drop)
remote.CallTruck.OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.Allow(player, "CallTruck") then
		return
	end
	local ok, why = VehicleService.Recall(player)
	if ok then
		notify(player, "Your truck is back in your parking spot.")
	elseif why then
		notify(player, why)
	end
end)

-- Settings toggles (music, sound effects), mirrored on SettingMusic /
-- SettingSfx attributes so the client applies them when the save loads.
local SETTING_ATTRIBUTES = { music = "SettingMusic", sfx = "SettingSfx" }
remote.SaveSetting.OnServerEvent:Connect(function(player: Player, key: unknown, on: unknown)
	if not RateLimiter.Allow(player, "SaveSetting") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or type(key) ~= "string" or type(on) ~= "boolean" or not SETTING_ATTRIBUTES[key] then
		return
	end
	(profile.settings :: any)[key] = on
	player:SetAttribute(SETTING_ATTRIBUTES[key], on)
end)

-- Player lifecycle --------------------------------------------------------

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
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("ProfileLoaded", false) -- the HUD shows "Loading your save..."
	player:SetAttribute("CarriedLogs", 0)
	CarryService.Start(player)
	lastNotice[player.UserId] = {}

	local profile, err = ProfileService.LoadProfile(player)
	if not profile then
		if err == "failed" then
			player:Kick("Timberline Tycoon couldn't load your save right now. Your progress is safe. Please rejoin.")
		end
		return -- "left": they're already gone
	end

	-- A save naming a truck that no longer exists (or isn't owned) falls
	-- back to the starter.
	if
		not ItemCatalog.GetTruck(profile.equippedTruck) or not table.find(profile.ownedTrucks, profile.equippedTruck)
	then
		profile.equippedTruck = "Rustbucket"
	end
	if profile.equippedTrailer ~= "" and not table.find(profile.ownedTrailers, profile.equippedTrailer) then
		profile.equippedTrailer = ""
	end

	player:SetAttribute("Cash", profile.cash)
	player:SetAttribute("SettingMusic", profile.settings.music ~= false)
	player:SetAttribute("SettingSfx", profile.settings.sfx ~= false)
	if profile.pendingCash > 0 then
		player:SetAttribute("PendingCash", profile.pendingCash)
		EconomyService.PayPending(player)
	end
	safely("VehicleService.SpawnTruck", function()
		VehicleService.SpawnTruck(player, profile.equippedTruck, nil, profile.equippedTrailer)
	end)
	-- Logs left behind (Truck to lot from afar) that were still lying out
	-- when the player last left: back where they lay, at most MaxLeftLogs
	-- of them (saves made under the old cap can hold 150).
	if #profile.leftLoad > 0 then
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
	remote.CashChanged:FireClient(player, profile.cash)
	safely("MilestoneService.Start", MilestoneService.Start, player, profile)
	safely("QuestService.Start", QuestService.Start, player, profile)
	safely("DailyService.Start", DailyService.Start, player, profile)
	safely("ShopService.PlayerJoined", ShopService.PlayerJoined, player, profile)
	safely("MonetizationService.PlayerJoined", MonetizationService.PlayerJoined, player, profile)
	safely("FieldGuideService.Refresh", FieldGuideService.Refresh, player)
	safely("NodeService.Publish", NodeService.Publish, player)
	safely("AetherService.PlayerJoined", AetherService.PlayerJoined, player, profile)
	safely("PlotService.PlayerJoined", PlotService.PlayerJoined, player, profile)
	safely("ForestService.PlayerJoined", ForestService.PlayerJoined, player, profile)
	print(string.format("[GameServer] %s joined (cash $%d)", player.Name, profile.cash))
end

local function onPlayerRemoving(player: Player)
	safely("dropCarriedLogs", dropCarriedLogs, player) -- back into the world for others, before the character goes
	safely("MilestoneService.Stop", MilestoneService.Stop, player) -- before the final save, so playtime is included
	safely("AxeService.PlayerRemoving", AxeService.PlayerRemoving, player) -- dropped axes go back to the save
	safely("MonetizationService.PlayerRemoving", MonetizationService.PlayerRemoving, player)
	safely("PlotService.PlayerRemoving", PlotService.PlayerRemoving, player)
	safely("ForestService.PlayerRemoving", ForestService.PlayerRemoving, player)
	-- Left-behind logs still lying out go into the save (put back on rejoin).
	safely("save left-behind logs", function()
		local profile = ProfileService.GetProfile(player)
		if profile then
			local left = TreeService.TakeLeftBehind(player.UserId)
			for _, entry in ipairs(left) do
				if #profile.leftLoad >= GameConfig.MaxLeftLogs then
					break
				end
				table.insert(profile.leftLoad, entry)
			end
		end
	end)
	ProfileService.ReleaseProfile(player)
	VehicleService.DespawnTruck(player)
	RateLimiter.Forget(player)
	CarryService.Stop(player)
	nextSwingAt[player.UserId] = nil
	lastNotice[player.UserId] = nil
	print(string.format("[GameServer] %s left (saving)", player.Name))
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
-- Catch players who joined before this script ran.
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- The boot report (PLAY-01): how long the world took, trees, players.
print(BootReport.Line(workspace, #Players:GetPlayers()))
