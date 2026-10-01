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
local DailyService = require(script.Parent.DailyService)
local EconomyService = require(script.Parent.EconomyService)
local FieldGuideService = require(script.Parent.FieldGuideService)
local ForestService = require(script.Parent.ForestService)
local GondolaService = require(script.Parent.GondolaService)
local MilestoneService = require(script.Parent.MilestoneService)
local MonetizationService = require(script.Parent.MonetizationService)
local NodeService = require(script.Parent.NodeService)
local NPCService = require(script.Parent.NPCService)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local ShopService = require(script.Parent.ShopService)
local TreeService = require(script.Parent.TreeService)
local VehicleService = require(script.Parent.VehicleService)
local WeatherService = require(script.Parent.WeatherService)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)

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

EconomyService.Init(remotes)

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
	-- Grace period: only the feller can grab these for the first few seconds.
	if log.ownerId ~= player.UserId and os.time() - log.fellTime < GameConfig.PickupGraceSec then
		notify(player, "Someone else felled this tree. Their logs are up for grabs in a few seconds.")
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
	pp.CFrame = torso.CFrame * CFrame.new(0, 0.4 + slot * 1.3, -1.7)
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
	local moved = 0
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
		end
	end
	player:SetAttribute("CarriedLogs", countHands(hands))
	if moved > 0 then
		MilestoneService.Mark(player, "First log loaded")
		QuestService.Event(player, "logsLoaded", moved)
		DailyService.Event(player, "logsLoaded", moved)
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
	-- The truck bed only sells if the truck is actually at the mill.
	local truck = VehicleService.GetVehicle(player)
	local truckPP = if truck then truck.PrimaryPart else nil
	if truckPP and flatDistance(truckPP.Position, sellZone.Position) <= GameConfig.SellTruckRange then
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

MilestoneService.Init(notify)
AxeService.Init(notify)
ShopService.Init(mapFolder, remote.BuyItem, remote.EquipItem, notify)
VehicleService.Init(notify)
QuestService.Init(remote.SkipTutorial, notify)
DailyService.Init(notify)
BiomeService.Init(notify)
MonetizationService.Init(remote.BuyRobuxItem, notify)
FieldGuideService.Init(notify)
NodeService.Init(notify)
AetherService.Init(notify)
GondolaService.Init(mapFolder, notify)
PlotService.Init(mapFolder, {
	PlaceBlueprint = remote.PlaceBlueprint,
	MoveBlueprint = remote.MoveBlueprint,
	SellPlaced = remote.SellPlaced,
	UpgradePlot = remote.UpgradePlot,
}, notify)
ForestService.Init({ PlantSeed = remote.PlantSeed, WorldFX = remote.WorldFX }, notify)
WeatherService.Init(remote.WorldFX)
NPCService.Init(mapFolder)
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

-- Runs one service's join or leave hook on its own: an error in one is
-- logged with a traceback and doesn't stop the player's other systems.
local function safely(name: string, fn: (...any) -> ...any, ...: any)
	local args = table.pack(...)
	local ok, err = xpcall(function(): any
		fn(table.unpack(args, 1, args.n))
		return nil
	end, debug.traceback)
	if not ok then
		warn(string.format("[GameServer] %s failed:\n%s", name, tostring(err)))
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

print("[GameServer] Online: chop -> carry -> sell -> buy a better axe.")
