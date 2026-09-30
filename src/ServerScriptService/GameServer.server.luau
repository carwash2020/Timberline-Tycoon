-- GameServer: bootstrap + remote handlers for the Phase 1 vertical slice.
--   * Creates the ReplicatedStorage/Remotes folder (ChopTree, PickupLog,
--     LoadToTruck, SellLogs, CashChanged).
--   * PlayerAdded: load profile -> spawn Rustbucket -> give Rusty Axe.
--   * PlayerRemoving: save + release lock, clean up.
--   * Every remote is rate-limited and server-validated. The client only
--     sends intents; TreeService/EconomyService own the truth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)
local TreeService = require(script.Parent.TreeService)
local VehicleService = require(script.Parent.VehicleService)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Util = require(ReplicatedStorage.Shared.Util)

-- Wait for the code-built world (MapBuilder runs at server start).
local mapFolder = workspace:WaitForChild("TimberlineMap", 60)
assert(mapFolder, "[GameServer] TimberlineMap was not built (MapBuilder failed?)")
local sellZone = mapFolder:WaitForChild("SellZone", 30)
assert(sellZone and sellZone:IsA("BasePart"), "[GameServer] SellZone missing")

-- Remotes -----------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in ipairs({ "ChopTree", "PickupLog", "LoadToTruck", "SellLogs", "CashChanged" }) do
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = remotes
end
remotes.Parent = ReplicatedStorage

EconomyService.Init(remotes)

-- Tuning ------------------------------------------------------------------
local SWING_COOLDOWN = 0.8
local PICKUP_RANGE = 12
local TRUCK_RANGE = 15
local HAND_CAPACITY = 2

-- Per-player state ---------------------------------------------------------
local carriedLogs: { [number]: { [string]: boolean } } = {} -- [userId] -> { [logUid] = true }
local lastSwing: { [number]: number } = {}
local rateBuckets: { [string]: { count: number, windowStart: number } } = {}
local violations: { [number]: number } = {}

local RATE_LIMITS = {
	ChopTree = { max = 4, per = 1 },
	PickupLog = { max = 4, per = 1 },
	LoadToTruck = { max = 2, per = 1 },
	SellLogs = { max = 2, per = 1 },
}

local function checkRate(player: Player, remoteName: string): boolean
	local limits = RATE_LIMITS[remoteName]
	if not limits then
		return false
	end
	local key = player.UserId .. ":" .. remoteName
	local now = os.clock()
	local bucket = rateBuckets[key]
	if not bucket or now - bucket.windowStart >= limits.per then
		rateBuckets[key] = { count = 1, windowStart = now }
		return true
	end
	bucket.count += 1
	if bucket.count > limits.max then
		local v = (violations[player.UserId] or 0) + 1
		violations[player.UserId] = v
		warn(string.format("[AntiExploit] %s exceeded %s rate (%d violations)", player.Name, remoteName, v))
		if v >= 10 then
			player:Kick("Disconnected: suspicious activity detected.")
		end
		return false
	end
	return true
end

local function getCharacterParts(player: Player): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return char, hrp, humanoid
end

local function getEquippedAxe(char: Model, profile: any): any
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	local def = ItemCatalog.GetAxe(tool.Name)
	if not def then
		return nil
	end
	if tool.Name ~= profile.equippedAxe then
		return nil -- client equipped something the server didn't grant
	end
	return def
end

local function countHands(userId: number): number
	local hands = carriedLogs[userId]
	if not hands then
		return 0
	end
	local n = 0
	for _ in pairs(hands) do
		n += 1
	end
	return n
end

-- Remote handlers ----------------------------------------------------------

local function onChopTree(player: Player, treeUid: any)
	if type(treeUid) ~= "string" then
		return
	end
	if not checkRate(player, "ChopTree") then
		return
	end
	local char = getCharacterParts(player)
	if not char then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local now = os.clock()
	if now - (lastSwing[player.UserId] or 0) < SWING_COOLDOWN then
		return
	end
	local axe = getEquippedAxe(char :: Model, profile)
	if not axe then
		return
	end
	lastSwing[player.UserId] = now
	local newHp, _err = TreeService.ApplyChop(player, treeUid, axe.damage)
	if newHp ~= nil and newHp <= 0 then
		profile.stats.treesChopped += 1
	end
end

local function serverPickupLog(player: Player, logUid: any)
	if type(logUid) ~= "string" then
		return
	end
	if not checkRate(player, "PickupLog") then
		return
	end
	local char, hrp = getCharacterParts(player)
	if not char or not hrp then
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
	if (hrp.Position - pp.Position).Magnitude > PICKUP_RANGE then
		return
	end
	-- 10s grace to the feller, then free-for-all.
	if log.ownerId ~= player.UserId and os.time() - log.fellTime < TreeService.GetPickupGraceSec() then
		return
	end
	local hands = carriedLogs[player.UserId]
	if not hands then
		hands = {}
		carriedLogs[player.UserId] = hands
	end
	local alreadyCarrying = countHands(player.UserId)
	if alreadyCarrying >= HAND_CAPACITY then
		return
	end
	if not TreeService.ClaimLog(logUid) then
		return
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then
		TreeService.ReturnLogToWorld(logUid)
		return
	end
	pp.Anchored = false
	pp.CanCollide = false
	pp.Massless = true
	pp.CFrame = torso.CFrame * CFrame.new(0, 0.4 + alreadyCarrying * 1.1, -1.7)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = pp
	weld.Parent = pp
	hands[logUid] = true
	player:SetAttribute("CarriedLogs", alreadyCarrying + 1)
end

-- ProximityPrompts on logs call the same validated path.
TreeService.PickupCallback = serverPickupLog

local function onLoadToTruck(player: Player)
	if not checkRate(player, "LoadToTruck") then
		return
	end
	local _char, hrp = getCharacterParts(player)
	if not hrp then
		return
	end
	local truck = VehicleService.GetVehicle(player)
	if not truck then
		return
	end
	local truckPP = truck.PrimaryPart
	if not truckPP or (hrp.Position - truckPP.Position).Magnitude > TRUCK_RANGE then
		return
	end
	local hands = carriedLogs[player.UserId]
	if not hands then
		return
	end
	local uids: { string } = {}
	for uid in pairs(hands) do
		table.insert(uids, uid)
	end
	if #uids == 0 then
		return
	end
	local space = VehicleService.GetBedCapacity(player) - VehicleService.GetBedCount(player)
	if space <= 0 then
		return
	end
	local moved = 0
	for _, uid in ipairs(uids) do
		if moved >= space then
			break
		end
		local rec = TreeService.TakeLog(uid)
		if rec then
			if rec.model then
				rec.model:Destroy()
			end
			if VehicleService.AddBedLog(player, { woodId = rec.def.id, value = rec.def.pricePerLog }) then
				hands[uid] = nil
				moved += 1
			end
		else
			hands[uid] = nil -- stale entry; drop it
		end
	end
	player:SetAttribute("CarriedLogs", countHands(player.UserId))
end

local function onSellLogs(player: Player)
	if not checkRate(player, "SellLogs") then
		return
	end
	local _char, hrp = getCharacterParts(player)
	if not hrp then
		return
	end
	if not Util.pointInPart(sellZone :: BasePart, hrp.Position) then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local total, count = 0, 0
	-- Logs in hands: valued from SERVER records, then destroyed.
	local hands = carriedLogs[player.UserId]
	if hands then
		for uid in pairs(hands) do
			local rec = TreeService.TakeLog(uid)
			if rec then
				total += rec.def.pricePerLog
				count += 1
				if rec.model then
					rec.model:Destroy()
				end
			end
		end
		carriedLogs[player.UserId] = {}
	end
	-- Logs in the truck bed.
	for _, entry in ipairs(VehicleService.TakeBedLogs(player)) do
		total += entry.value
		count += 1
	end
	if count == 0 then
		return
	end
	profile.stats.logsSold += count
	player:SetAttribute("CarriedLogs", 0)
	EconomyService.AddCash(player, total, string.format("sold %d logs", count))
end

remotes.ChopTree.OnServerEvent:Connect(onChopTree)
remotes.PickupLog.OnServerEvent:Connect(serverPickupLog)
remotes.LoadToTruck.OnServerEvent:Connect(onLoadToTruck)
remotes.SellLogs.OnServerEvent:Connect(onSellLogs)

-- Player lifecycle --------------------------------------------------------

local function buildAxeTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "RustyAxe"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 3, 0.5)
	handle.Color = Color3.fromRGB(122, 82, 48)
	handle.Material = Enum.Material.Wood
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.4, 1.2, 2)
	head.Position = Vector3.new(0, 1.8, 0)
	head.Color = Color3.fromRGB(120, 120, 120) -- dull, pitted, rusty
	head.Material = Enum.Material.Metal
	head.Parent = tool

	local w = Instance.new("WeldConstraint")
	w.Part0 = handle
	w.Part1 = head
	w.Parent = handle

	return tool
end

local function dropCarriedLogs(player: Player)
	local hands = carriedLogs[player.UserId]
	if not hands then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local dropPos = (hrp and hrp.Position) or Vector3.new(0, 5, 40)
	for uid in pairs(hands) do
		TreeService.DropLog(uid, dropPos)
	end
	carriedLogs[player.UserId] = {}
	player:SetAttribute("CarriedLogs", 0)
end

local function onCharacterAdded(player: Player, character: Model)
	local backpack = player:WaitForChild("Backpack", 10)
	if backpack then
		local axe = buildAxeTool()
		axe.Parent = backpack
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			dropCarriedLogs(player)
		end)
	end
end

local function onPlayerAdded(player: Player)
	local profile, err = ProfileService.LoadProfile(player)
	if not profile then
		-- "locked": an active session exists on another server.
		player:Kick("Timberline Tycoon couldn't load your save (it may be open in another server). Please rejoin.")
		return
	end
	if err == "sessionOnly" then
		warn(string.format("[GameServer] %s playing session-only; progress will NOT save", player.Name))
	end

	player:SetAttribute("Cash", profile.cash)
	player:SetAttribute("CarriedLogs", 0)
	carriedLogs[player.UserId] = {}

	-- Spawn their Rustbucket next to spawn.
	VehicleService.SpawnTruck(player, CFrame.new(12, 1, 55))

	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	remotes.CashChanged:FireClient(player, profile.cash)
	print(string.format("[GameServer] %s joined (cash $%d)", player.Name, profile.cash))
end

local function onPlayerRemoving(player: Player)
	ProfileService.SaveProfile(player, true)
	ProfileService.ReleaseProfile(player)
	carriedLogs[player.UserId] = nil
	lastSwing[player.UserId] = nil
	violations[player.UserId] = nil
	VehicleService.DespawnTruck(player)
	print(string.format("[GameServer] %s left (saved)", player.Name))
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
-- Catch players who joined before this script ran.
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- Autosave every 120s.
task.spawn(function()
	while true do
		task.wait(120)
		ProfileService.SaveAll(false)
		print("[GameServer] Autosave complete")
	end
end)

-- Flush saves on server shutdown (matters in Studio Play tests).
game:BindToClose(function()
	ProfileService.SaveAll(true)
end)

print("[GameServer] Phase 1 online: chop -> carry -> sell.")
