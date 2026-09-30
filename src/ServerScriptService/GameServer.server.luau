--!strict
-- GameServer: bootstrap + remote handlers for the Phase 1 vertical slice.
--   * Creates ReplicatedStorage/Remotes (names listed in Shared/Net).
--   * PlayerAdded: load save -> spawn Rustbucket -> hand over every owned axe
--     (AxeService; axes are items the player can switch, drop and pick up).
--   * PlayerRemoving: drop carried logs, final save + release the session.
--   * Every remote is rate-limited and server-validated. The client only
--     sends intents; TreeService/EconomyService own the truth.
-- Autosave, shutdown flushing and session locks are ProfileStore's job
-- (see ProfileService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AxeService = require(script.Parent.AxeService)
local EconomyService = require(script.Parent.EconomyService)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local TreeService = require(script.Parent.TreeService)
local VehicleService = require(script.Parent.VehicleService)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)

-- Wait for the code-built world (MapBuilder runs at server start).
local mapFolder = workspace:WaitForChild("TimberlineMap", 60)
assert(mapFolder, "[GameServer] TimberlineMap was not built (MapBuilder failed?)")
local sellArea = mapFolder:WaitForChild("SellArea", 30)
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
local carriedLogs: { [number]: { [string]: boolean } } = {} -- [userId] -> { [logUid] = true }
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
	local newHp, err = TreeService.ApplyChop(player, treeUid, axe)
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
	if newHp <= 0 then
		profile.stats.treesChopped += 1
		MilestoneService.Mark(player, "First tree felled")
	end
end

local function serverPickupLog(player: Player, logUid: unknown)
	if type(logUid) ~= "string" or not RateLimiter.Allow(player, "PickupLog") then
		return
	end
	local char, hrp = getCharacterParts(player)
	local hands = carriedLogs[player.UserId]
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
	pp.CFrame = torso.CFrame * CFrame.new(0, 0.4 + already * 1.1, -1.7)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = pp
	weld.Parent = pp
	hands[logUid] = true
	player:SetAttribute("CarriedLogs", already + 1)
	MilestoneService.Mark(player, "First log picked up")
end

-- ProximityPrompts on logs call the same validated path.
TreeService.PickupCallback = serverPickupLog

local function onLoadToTruck(player: Player)
	if not RateLimiter.Allow(player, "LoadToTruck") then
		return
	end
	local _char, hrp = getCharacterParts(player)
	local truck = VehicleService.GetVehicle(player)
	local hands = carriedLogs[player.UserId]
	if not hrp or not truck or not hands then
		return
	end
	local truckPP = truck.PrimaryPart
	if not truckPP or (hrp.Position - truckPP.Position).Magnitude > GameConfig.TruckLoadRange then
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
		elseif VehicleService.AddBedLog(player, { woodId = log.def.id, value = log.def.pricePerLog }) then
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

local function onSellLogs(player: Player)
	if not RateLimiter.Allow(player, "SellLogs") then
		return
	end
	local _char, hrp = getCharacterParts(player)
	local profile = ProfileService.GetProfile(player)
	local hands = carriedLogs[player.UserId]
	if not hrp or not profile or not hands then
		return
	end
	if not Util.pointInPart(sellZone, hrp.Position) then
		notify(player, "Stand on the sawmill's sell pad to sell.")
		return
	end
	local total, count = 0, 0
	local byWood: { [string]: number } = {} -- for the stopwatch's calibration line
	-- Logs in hands: valued from SERVER records, then destroyed.
	for uid in pairs(hands) do
		local log = TreeService.TakeLog(uid)
		if log then
			total += log.def.pricePerLog
			count += 1
			byWood[log.def.id] = (byWood[log.def.id] or 0) + 1
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
		end
	end
	player:SetAttribute("CarriedLogs", 0)
	if count == 0 then
		notify(player, "Nothing to sell. Bring logs, or park your truck by the mill.")
		return
	end
	profile.stats.logsSold += count
	local credited, overflow = EconomyService.AddCash(player, total, string.format("sold %d logs", count), "logs")
	MilestoneService.Mark(player, "First sale")
	MilestoneService.CashEarned(player, credited)
	MilestoneService.LogsSold(player, byWood)
	notify(player, string.format("Sold %d log%s for %s", count, count == 1 and "" or "s", Util.formatCash(total)))
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
end

MilestoneService.Init(notify)
AxeService.Init(notify)

remote.ChopTree.OnServerEvent:Connect(onChopTree)
remote.PickupLog.OnServerEvent:Connect(serverPickupLog)
remote.LoadToTruck.OnServerEvent:Connect(onLoadToTruck)
remote.SellLogs.OnServerEvent:Connect(onSellLogs)
remote.DropAxe.OnServerEvent:Connect(AxeService.Drop)

-- Player lifecycle --------------------------------------------------------

local function dropCarriedLogs(player: Player)
	local hands = carriedLogs[player.UserId]
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
	carriedLogs[player.UserId] = {}
	lastNotice[player.UserId] = {}

	local profile, err = ProfileService.LoadProfile(player)
	if not profile then
		if err == "failed" then
			player:Kick("Timberline Tycoon couldn't load your save right now. Your progress is safe. Please rejoin.")
		end
		return -- "left": they're already gone
	end

	-- A save naming a truck that no longer exists falls back to the starter.
	if not ItemCatalog.GetTruck(profile.equippedTruck) then
		profile.equippedTruck = "Rustbucket"
	end

	player:SetAttribute("Cash", profile.cash)
	VehicleService.SpawnTruck(player, profile.equippedTruck)

	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	local existing = player.Character
	if existing then
		task.spawn(onCharacterAdded, player, existing)
	end

	player:SetAttribute("ProfileLoaded", true)
	remote.CashChanged:FireClient(player, profile.cash)
	MilestoneService.Start(player, profile)
	print(string.format("[GameServer] %s joined (cash $%d)", player.Name, profile.cash))
end

local function onPlayerRemoving(player: Player)
	dropCarriedLogs(player) -- back into the world for others, before the character goes
	MilestoneService.Stop(player) -- before the final save, so playtime is included
	AxeService.PlayerRemoving(player) -- dropped axes go back to the save's inventory
	ProfileService.ReleaseProfile(player)
	VehicleService.DespawnTruck(player)
	RateLimiter.Forget(player)
	carriedLogs[player.UserId] = nil
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

print("[GameServer] Phase 1 online: chop -> carry -> sell.")
