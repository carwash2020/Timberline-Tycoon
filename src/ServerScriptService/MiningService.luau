--!strict
-- MiningService: nodes, picks, bombs, the furnace, the ore chute, danger
-- and the mining save. Cash goes through EconomyService. The profile's
-- `mining` table is MiningSchema; ProfileSchema's hook lands with A1.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EconomyService = require(script.Parent.EconomyService)
local LeaveCommit = require(script.Parent.LeaveCommit)
local PaidItems = require(ReplicatedStorage.Shared.PaidItems)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local MineSites = require(ReplicatedStorage.Shared.Mining.MineSites)
local MiningArt = require(ReplicatedStorage.Shared.Mining.MiningArt)
local MiningLogic = require(ReplicatedStorage.Shared.Mining.MiningLogic)
local MiningSchema = require(ReplicatedStorage.Shared.Mining.MiningSchema)
local OreData = require(ReplicatedStorage.Shared.Mining.OreData)
local PickaxeData = require(ReplicatedStorage.Shared.Mining.PickaxeData)

local MiningService = {}

type NodeRec = {
	uid: string,
	oreId: string,
	tier: number,
	model: Model?,
	state: MiningLogic.Node,
	cf: CFrame,
	respawnAt: number?,
}

type RubbleRec = {
	id: string,
	tier: number,
	model: Model,
	sealedUntil: number?,
	warned: boolean,
	exit: Vector3,
}

local nodes: { NodeRec } = {}
local rubble: { RubbleRec } = {}
local claimed: { [string]: string } = {}
local swingAt: { [Player]: number } = {}
local warned: { [Player]: { [string]: boolean } } = {}
local fuseMem: MiningLogic.FuseMem = {}
local frame = 0
local restored: { [Player]: MiningLogic.RestoreFlag } = {}
local smeltQueue: { { uid: string, model: Model, owner: Player, oreId: string, ready: number } } = {}
local folder: Folder? = nil
local chute: BasePart? = nil
local intake: BasePart? = nil
local started = false

local function toast(player: Player, text: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("Notify")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, text)
	end
end

local function profileOf(player: Player): any?
	return ProfileService.GetProfile(player) :: any
end

local function miningOf(player: Player): MiningSchema.Mining?
	local profile = profileOf(player)
	if profile == nil then
		return nil
	end
	local mining = MiningSchema.Migrate(profile.mining)
	profile.mining = mining
	return mining
end

local function cashOf(player: Player): number
	local profile = profileOf(player)
	if profile and type(profile.cash) == "number" then
		return profile.cash
	end
	return 0
end

local function gearOf(player: Player): { string }
	local profile = profileOf(player)
	if profile and type(profile.gear) == "table" then
		return profile.gear
	end
	return {}
end

local function luxOwned(player: Player): boolean
	local profile = profileOf(player)
	return profile ~= nil and PaidItems.SaveHasPass(profile, PickaxeData.LuxPassKey)
end

local function publishLevel(player: Player, mining: MiningSchema.Mining)
	player:SetAttribute(PickaxeData.LevelAttribute, MiningLogic.BestOwnedLevel(mining.picks, luxOwned(player)))
end

local function ownedList(picks: { [string]: boolean }): string
	local ids: { string } = {}
	for id, owned in pairs(picks) do
		if owned == true then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

-- Pick level for the hover tag, plus the chip (name, bombs, lamp, hat)
-- and the shop's owned list. Same idea as OwnedGear: the server writes it.
local function publishGear(player: Player, mining: MiningSchema.Mining)
	publishLevel(player, mining)
	player:SetAttribute("MiningBombs", mining.bombs)
	player:SetAttribute("MiningLamp", mining.lamp == true)
	player:SetAttribute("MiningHardhat", mining.hardhat == true)
	local pick = PickaxeData.Get(mining.pick)
	player:SetAttribute("MiningPick", if pick then pick.name else "Rusty Pick")
	player:SetAttribute("MiningOwned", ownedList(mining.picks))
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function worldFolder(): Folder
	local found = folder
	if found and found.Parent then
		return found
	end
	local existing = Workspace:FindFirstChild("Mining")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "Mining"
	made.Parent = Workspace
	folder = made
	return made
end

-- buildWorld sets these. A test that parents SmeltIntake under Mining
-- is picked up the same way, so a chunk can be settled without Init.
local function bindSinks()
	if intake ~= nil and chute ~= nil then
		return
	end
	local root = worldFolder()
	if intake == nil then
		local part = root:FindFirstChild("SmeltIntake", true)
		if part and part:IsA("BasePart") then
			intake = part
		end
	end
	if chute == nil then
		local part = root:FindFirstChild("OreChute", true)
		if part and part:IsA("BasePart") then
			chute = part
		end
	end
end

local function liveChunks(player: Player): number
	local n = 0
	for _, child in ipairs(worldFolder():GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OwnerId") == player.UserId then
			local kind = child.Name
			if kind == "OreChunk" or kind == "Ingot" then
				n += 1
			end
		end
	end
	return n
end

local function stamp(model: Model, ore: OreData.Ore, kind: string, value: number, ownerId: number): string
	local uid = HttpService:GenerateGUID(false)
	model:SetAttribute("Ore", ore.id)
	model:SetAttribute("Value", value)
	model:SetAttribute("Uid", uid)
	model:SetAttribute("OwnerId", ownerId)
	model:SetAttribute("Kind", kind)
	pcall(function()
		CollectionService:AddTag(model, if kind == "ingot" then "Ingot" else "OreChunk")
	end)
	return uid
end

local function pickupPrompt(model: Model, host: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpOre"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = model:GetAttribute("Ore") :: string
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = host
	prompt.Triggered:Connect(function(who: Player)
		if model.Parent == nil then
			return
		end
		local owner = model:GetAttribute("OwnerId")
		if owner ~= 0 and owner ~= who.UserId then
			return
		end
		local root = rootOf(who)
		if root == nil then
			return
		end
		model:PivotTo(root.CFrame * CFrame.new(0, 0, -2.2))
		local primary = model.PrimaryPart
		if primary then
			local weld = Instance.new("Weld")
			weld.Name = "CarryWeld"
			weld.Part0 = root
			weld.Part1 = primary
			weld.C0 = root.CFrame:Inverse() * primary.CFrame
			weld.Parent = primary
			primary.Anchored = false
		end
	end)
end

local function spawnPiece(player: Player, ore: OreData.Ore, kind: string, cf: CFrame): Model?
	if liveChunks(player) >= MiningLogic.LiveChunks then
		toast(player, "1 piece didn't fit (40 on you)")
		return nil
	end
	local model = if kind == "ingot" then MiningArt.Ingot(ore) else MiningArt.Chunk(ore)
	if model == nil then
		return nil
	end
	local value = if kind == "ingot" then ore.ingotValue or ore.chunkValue else ore.chunkValue
	stamp(model, ore, kind, value, player.UserId)
	model:PivotTo(cf)
	local host = model.PrimaryPart
	if host then
		host.Anchored = false
		pickupPrompt(model, host)
	end
	model.Parent = worldFolder()
	return model
end

-- Lane F (building): an ingot a build gave back, put at `cf` for its owner.
-- IngotRoom says how many fit under the live-piece cap, so a caller can
-- refuse up front and never drop one.
function MiningService.IngotRoom(player: Player): number
	return math.max(0, MiningLogic.LiveChunks - liveChunks(player))
end

function MiningService.ReturnIngot(player: Player, oreId: string, cf: CFrame): boolean
	local ore = OreData.Get(oreId)
	if ore == nil or MiningService.IngotRoom(player) < 1 then
		return false
	end
	return spawnPiece(player, ore, "ingot", cf) ~= nil
end

local function nearestNode(pos: Vector3): NodeRec?
	local best: NodeRec? = nil
	local bestDist = MiningLogic.SwingReach
	for _, node in ipairs(nodes) do
		if node.model and not node.state.broken then
			local dist = (node.cf.Position - pos).Magnitude
			if dist <= bestDist then
				best = node
				bestDist = dist
			end
		end
	end
	return best
end

local function breakNode(player: Player, node: NodeRec)
	local ore = OreData.Get(node.oreId)
	if ore == nil or node.model == nil then
		return
	end
	local result = MiningLogic.Hit(node.state, MiningLogic.HitDamage)
	if result ~= "break" then
		return
	end
	local cf = node.cf * CFrame.new(0, 1.2, 2)
	spawnPiece(player, ore, "chunk", cf)
	MiningArt.ClearNode(node.model)
	node.model:Destroy()
	node.model = nil
	node.respawnAt = os.clock() + ore.respawnSec
end

local function onSwing(player: Player, tool: Tool)
	local mining = miningOf(player)
	local pickId = tool:GetAttribute("PickId")
	local pick = if type(pickId) == "string" then PickaxeData.Get(pickId) else nil
	if mining == nil or pick == nil then
		return
	end
	if pick.id == PickaxeData.LuxId and not luxOwned(player) then
		return
	end
	local now = os.clock()
	if not MiningLogic.SwingReady(swingAt[player] or 0, now, pick.speed) then
		return
	end
	local root = rootOf(player)
	if root == nil then
		return
	end
	local node = nearestNode(root.Position)
	if node == nil then
		return
	end
	local ore = OreData.Get(node.oreId)
	if ore == nil then
		return
	end
	local reason = MiningLogic.BlockReason(
		pick.level,
		ore.hardness,
		ore.tier,
		MiningLogic.HasMineLight(mining.lamp, gearOf(player))
	)
	if reason ~= nil then
		local seen = warned[player]
		if seen == nil then
			seen = {}
			warned[player] = seen
		end
		if seen[node.uid] ~= true then
			seen[node.uid] = true
			toast(player, reason)
		end
		return
	end
	swingAt[player] = now
	breakNode(player, node)
end

local function toolFrom(model: Model, name: string, attr: string, value: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute(attr, value)
	local handle = model.PrimaryPart
	for _, child in ipairs(model:GetChildren()) do
		child.Parent = tool
	end
	model:Destroy()
	if handle then
		tool.Grip = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-80), 0, 0)
	end
	return tool
end

local function stripTools(player: Player, attr: string)
	local function scan(container: Instance?)
		if container == nil then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute(attr) ~= nil then
				child:Destroy()
			end
		end
	end
	scan(player:FindFirstChildOfClass("Backpack"))
	scan(player.Character)
end

local function givePick(player: Player, mining: MiningSchema.Mining)
	local pickId = mining.pick
	if pickId == PickaxeData.LuxId and not luxOwned(player) then
		pickId = MiningLogic.BestFreeId(mining.picks)
		mining.pick = pickId
	end
	local pick = PickaxeData.Get(pickId)
	if pick == nil then
		return
	end
	stripTools(player, "PickId")
	local tool = toolFrom(MiningArt.Pickaxe(pick), pick.name, "PickId", pick.id)
	tool.Activated:Connect(function()
		onSwing(player, tool)
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	tool.Parent = backpack or player
end

local function giveBomb(player: Player)
	stripTools(player, "Bomb")
	local tool = toolFrom(MiningArt.Bomb(false), "Bomb", "Bomb", "1")
	tool.Activated:Connect(function()
		MiningService.Fuse(player, rootOf(player))
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	tool.Parent = backpack or player
end

local function giveLamp(player: Player, mining: MiningSchema.Mining)
	stripTools(player, "MinersLamp")
	if not mining.lamp then
		return
	end
	local tool = toolFrom(MiningArt.MinersLamp(), "Miner's Lamp", "MinersLamp", "1")
	tool.Equipped:Connect(function()
		local light = tool:FindFirstChild("LampLight", true)
		if light and light:IsA("PointLight") then
			light.Enabled = true
		end
	end)
	tool.Unequipped:Connect(function()
		local light = tool:FindFirstChild("LampLight", true)
		if light and light:IsA("PointLight") then
			light.Enabled = false
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	tool.Parent = backpack or player
end

local function wearHat(player: Player, mining: MiningSchema.Mining)
	local character = player.Character
	if character == nil then
		return
	end
	local old = character:FindFirstChild("Hardhat")
	if old then
		old:Destroy()
	end
	if not mining.hardhat then
		return
	end
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local hat = MiningArt.Hardhat()
	hat.Parent = character
	local shell = hat.PrimaryPart
	local joint = hat:FindFirstChild("HeadWeld", true)
	if shell and joint and joint:IsA("Weld") then
		shell.Anchored = false
		joint.Part0 = head
		joint.C0 = CFrame.new(0, 0.6, 0)
		joint.C1 = CFrame.new()
	end
end

function MiningService.Fuse(player: Player, root: BasePart?)
	local mining = miningOf(player)
	if mining == nil or root == nil then
		return
	end
	if not RateLimiter.Allow(player, "MineAction") then
		return
	end
	local target: RubbleRec? = nil
	local best = MiningLogic.BombReach
	for _, wall in ipairs(rubble) do
		if wall.sealedUntil == nil then
			local dist = (wall.model:GetPivot().Position - root.Position).Magnitude
			if dist <= best then
				target = wall
				best = dist
			end
		end
	end
	if target == nil then
		return
	end
	if not MiningLogic.TryFuse(fuseMem, tostring(player.UserId), frame, mining.bombs) then
		return
	end
	mining.bombs -= 1
	local wall = target
	local spark = MiningArt.Bomb(true)
	spark:PivotTo(wall.model:GetPivot() * CFrame.new(0, 2, 3))
	spark.Parent = worldFolder()
	task.delay(MiningLogic.FuseSec, function()
		if spark.Parent then
			spark:Destroy()
		end
		MiningService.Seal(wall)
	end)
end

local function hideWall(model: Model, hidden: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = not hidden
			d.Transparency = if hidden then 1 else 0
		end
	end
end

function MiningService.Seal(wall: RubbleRec)
	wall.sealedUntil = os.clock() + MiningLogic.SealSec
	wall.warned = false
	hideWall(wall.model, true)
end

local function playerInside(wall: RubbleRec): boolean
	local cf, size = wall.model:GetBoundingBox()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and MiningLogic.InBox(root.Position, cf, size) then
			return true
		end
	end
	return false
end

local function wallExit(wall: RubbleRec): Vector3
	if wall.exit.Magnitude > 1e-4 then
		return wall.exit
	end
	return Vector3.new(0, 0, 1)
end

-- Open wall: anyone inside the box. Closed wall: anyone within FarReach of
-- the face that points away from the mine mouth, so a reseal cannot trap them.
local function crawlOk(wall: RubbleRec, pos: Vector3): boolean
	local cf, size = wall.model:GetBoundingBox()
	local exit = wallExit(wall)
	if wall.sealedUntil ~= nil and MiningLogic.InBox(pos, cf, size) then
		return true
	end
	return MiningLogic.OnFarSide(pos, cf, size, exit, MiningLogic.FarReach)
end

function MiningService.Crawl(player: Player): boolean
	local root = rootOf(player)
	if root == nil then
		return false
	end
	for _, wall in ipairs(rubble) do
		local cf, size = wall.model:GetBoundingBox()
		if crawlOk(wall, root.Position) then
			local spot = MiningLogic.CrawlTarget(cf, size, wallExit(wall))
			local character = player.Character
			if character then
				character:PivotTo(CFrame.new(spot))
			end
			for _, child in ipairs(worldFolder():GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("OwnerId") == player.UserId then
					local carry = child:FindFirstChild("CarryWeld", true)
					if carry then
						child:PivotTo(CFrame.new(spot) * CFrame.new(1, 1, 0))
					end
				end
			end
			return true
		end
	end
	return false
end

local function prospector(): Model?
	local folderNow = Workspace:FindFirstChild("Mining")
	local stall = folderNow and folderNow:FindFirstChild("Prospector")
	if stall and stall:IsA("Model") then
		return stall
	end
	return nil
end

local function nearPrimary(player: Player, model: Model?): boolean
	local root = rootOf(player)
	local host = model and model.PrimaryPart
	if root == nil or host == nil then
		return false
	end
	return (root.Position - host.Position).Magnitude <= MiningLogic.ShopReach
end

local function buyPick(player: Player, id: string)
	local mining = miningOf(player)
	local pick = PickaxeData.Get(id)
	if mining == nil or pick == nil or pick.robux == true then
		return
	end
	if not nearPrimary(player, prospector()) then
		return
	end
	if mining.picks[id] then
		toast(player, "You already own this")
		return
	end
	-- The save key stays HeartstoneTurnIn so an old turn-in still counts.
	local need = pick.opalIngots or 0
	if need > 0 and (mining.crafted.HeartstoneTurnIn or 0) < 1 then
		toast(player, "Needs 5 Timber Opal ingots")
		return
	end
	if pick.price > 0 and not EconomyService.SpendCash(player, pick.price, "pickaxe", pick.id) then
		toast(player, "Not enough cash")
		return
	end
	mining.picks[id] = true
	mining.pick = id
	publishGear(player, mining)
	givePick(player, mining)
end

local function buyBombs(player: Player, n: number)
	local mining = miningOf(player)
	if mining == nil or not nearPrimary(player, prospector()) then
		return
	end
	local bought, cost = MiningLogic.BuyBombs(mining.bombs, cashOf(player), MiningLogic.BombPrice(), n)
	if bought < 1 then
		return
	end
	if not EconomyService.SpendCash(player, cost, "bomb", "Bomb") then
		return
	end
	mining.bombs += bought
	publishGear(player, mining)
	giveBomb(player)
end

local function turnIn(player: Player)
	local mining = miningOf(player)
	local pick = PickaxeData.Get("ObsidianPick")
	local need = if pick and pick.opalIngots then pick.opalIngots else 5
	if mining == nil or not nearPrimary(player, prospector()) then
		return
	end
	if (mining.crafted.HeartstoneTurnIn or 0) >= 1 then
		toast(player, "Already turned in")
		return
	end
	local stall = prospector()
	local host = stall and stall.PrimaryPart
	if host == nil then
		return
	end
	-- CraftingService requires this module, so look it up by name at call
	-- time (a static require would be a cycle the type checker rejects).
	local craftingModule = script.Parent:FindFirstChild("CraftingService")
	if craftingModule == nil then
		return
	end
	local CraftingService = require(craftingModule :: any) :: any
	local _, ingotModels = CraftingService.StockNear(player, host)
	local found = ingotModels.TimberOpal or {}
	if #found < need then
		toast(player, "Needs 5 Timber Opal ingots")
		return
	end
	for i = 1, need do
		found[i]:Destroy()
	end
	mining.crafted.HeartstoneTurnIn = 1
	toast(player, "Timber Opal turned in")
end

local function equip(player: Player, id: string)
	local mining = miningOf(player)
	if mining == nil then
		return
	end
	if id == PickaxeData.LuxId then
		if not luxOwned(player) then
			return
		end
	elseif mining.picks[id] ~= true then
		return
	end
	mining.pick = id
	publishGear(player, mining)
	givePick(player, mining)
end

local function useRope(player: Player)
	local mining = miningOf(player)
	local root = rootOf(player)
	if mining == nil or root == nil or mining.ropes < 1 then
		return
	end
	local sites = MineSites.Current()
	for _, ledge in ipairs(sites.ledges) do
		local pos = Vector3.new(ledge.x, ledge.y, ledge.z)
		if ledge.tier >= 2 and (pos - root.Position).Magnitude <= 10 then
			mining.ropes -= 1
			publishGear(player, mining)
			local ladder = MiningArt.RopeLadder()
			ladder:PivotTo(CFrame.new(pos))
			ladder.Parent = worldFolder()
			task.delay(MiningLogic.SealSec, function()
				if ladder.Parent then
					ladder:Destroy()
				end
			end)
			return
		end
	end
end

local function onMineAction(player: Player, op: unknown, id: unknown, n: unknown)
	if type(op) ~= "string" or not RateLimiter.Allow(player, "MineAction") then
		return
	end
	if type(n) == "number" and n ~= n then
		return
	end
	if op == "buyPick" and type(id) == "string" then
		buyPick(player, id)
	elseif op == "buyBomb" then
		buyBombs(player, if type(n) == "number" then n else 1)
	elseif op == "equip" and type(id) == "string" then
		equip(player, id)
	elseif op == "turnIn" then
		turnIn(player)
	elseif op == "crawl" then
		MiningService.Crawl(player)
	elseif op == "rope" then
		useRope(player)
	end
end

local function inPart(part: BasePart, pos: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

local function pieceModels(): { Model }
	local list: { Model } = {}
	for _, child in ipairs(worldFolder():GetChildren()) do
		if child:IsA("Model") and (child.Name == "OreChunk" or child.Name == "Ingot") then
			table.insert(list, child)
		end
	end
	return list
end

local function settle()
	bindSinks()
	local sinkIntake = intake
	local sinkChute = chute
	if sinkIntake == nil and sinkChute == nil then
		return
	end
	for _, model in ipairs(pieceModels()) do
		local uid = model:GetAttribute("Uid")
		local pos = model:GetPivot().Position
		local oreId = model:GetAttribute("Ore")
		local ownerId = model:GetAttribute("OwnerId")
		if type(uid) ~= "string" or type(oreId) ~= "string" or type(ownerId) ~= "number" then
			continue
		end
		local owner = Players:GetPlayerByUserId(ownerId)
		local inIntake = false
		if sinkIntake and model.Name == "OreChunk" and oreId ~= "Coal" then
			inIntake = inPart(sinkIntake, pos)
		end
		local inChute = false
		if sinkChute then
			inChute = inPart(sinkChute, pos)
		end
		if inIntake and owner then
			if claimed[uid] ~= nil then
				continue
			end
			if not MiningLogic.Claim(claimed, uid, "smelt") then
				continue
			end
			local coal = 0
			for _, other in ipairs(pieceModels()) do
				if other:GetAttribute("Ore") == "Coal" and other:GetAttribute("OwnerId") == ownerId then
					coal += 1
				end
			end
			local use, pay = MiningLogic.SmeltCost(1, coal)
			if pay > 0 and not EconomyService.SpendCash(owner, pay, "smelt", oreId) then
				claimed[uid] = nil
				toast(owner, "Not enough cash to smelt")
				continue
			end
			if use > 0 then
				for _, other in ipairs(pieceModels()) do
					if use > 0 and other:GetAttribute("Ore") == "Coal" and other:GetAttribute("OwnerId") == ownerId then
						other:Destroy()
						use -= 1
					end
				end
			end
			table.insert(
				smeltQueue,
				{ uid = uid, model = model, owner = owner, oreId = oreId, ready = os.clock() + MiningLogic.SmeltSec }
			)
		elseif inChute and owner then
			if MiningLogic.Claim(claimed, uid, "paid") then
				local value = MiningLogic.SellValue(tonumber(model:GetAttribute("Value") :: any) or 0)
				EconomyService.AddCash(owner, value, "ore", oreId)
				model:Destroy()
			end
		end
	end
	local now = os.clock()
	for i = #smeltQueue, 1, -1 do
		local job = smeltQueue[i]
		if now >= job.ready then
			table.remove(smeltQueue, i)
			local ore = OreData.Get(job.oreId)
			if ore and job.model.Parent and job.owner.Parent then
				local cf = job.model:GetPivot()
				job.model:Destroy()
				spawnPiece(job.owner, ore, "ingot", cf * CFrame.new(0, 1, 4))
			end
		end
	end
end

local function components(cf: CFrame): { number }
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function plotOrigin(player: Player): CFrame
	local slot = player:GetAttribute("PlotSlot")
	if type(slot) ~= "number" then
		return CFrame.identity
	end
	local plots = Workspace:FindFirstChild("Plots")
	local pad = plots and plots:FindFirstChild("Plot_" .. tostring(slot))
	if pad and pad:IsA("Model") then
		return pad:GetPivot()
	end
	return CFrame.identity
end

local function onPlotOrTruck(player: Player, model: Model): boolean
	local slot = player:GetAttribute("PlotSlot")
	if type(slot) == "number" then
		local plots = Workspace:FindFirstChild("Plots")
		local items = plots and plots:FindFirstChild("PlotItems_" .. tostring(slot))
		if items and model:IsDescendantOf(items) then
			return true
		end
		local origin = plotOrigin(player)
		local delta = origin:PointToObjectSpace(model:GetPivot().Position)
		if math.abs(delta.X) < 120 and math.abs(delta.Z) < 120 and math.abs(delta.Y) < 40 then
			return true
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") then
			local other = if d.Part0 and d.Part0:IsDescendantOf(model) then d.Part1 else d.Part0
			if other and (other.Name == "BedFloor" or other.Name == "TrailerBed") then
				return true
			end
		end
	end
	return false
end

local function placedCount(player: Player): number
	local slot = player:GetAttribute("PlotSlot")
	if type(slot) ~= "number" then
		return 0
	end
	local plots = Workspace:FindFirstChild("Plots")
	local items = plots and plots:FindFirstChild("PlotItems_" .. tostring(slot))
	local n = 0
	if items then
		for _, child in ipairs(items:GetChildren()) do
			if child:IsA("Model") then
				n += 1
			end
		end
	end
	return n + liveChunks(player)
end

function MiningService.Commit(player: Player)
	local mining = miningOf(player)
	if mining == nil then
		return
	end
	local rows: { MiningLogic.StashRow } = {}
	local origin = plotOrigin(player)
	for _, model in ipairs(pieceModels()) do
		if model:GetAttribute("OwnerId") == player.UserId and onPlotOrTruck(player, model) then
			local uid = model:GetAttribute("Uid")
			local ore = model:GetAttribute("Ore")
			local kind = if model.Name == "Ingot" then "ingot" else "chunk"
			if type(uid) == "string" and type(ore) == "string" then
				table.insert(rows, {
					kind = kind,
					ore = ore,
					uid = uid,
					value = tonumber(model:GetAttribute("Value") :: any) or 0,
					cf = components(origin:ToObjectSpace(model:GetPivot())),
				})
			end
		end
	end
	local packed = MiningLogic.PackStash(rows, MiningLogic.StashCap)
	mining.stash = packed.kept
	if packed.refused > 0 then
		toast(player, string.format("%d didn't fit (stash holds %d)", packed.refused, MiningLogic.StashCap))
	end
end

function MiningService.Restore(player: Player)
	local mining = miningOf(player)
	if mining == nil then
		return
	end
	local flag = restored[player]
	if flag == nil then
		flag = { done = false }
		restored[player] = flag
	end
	if not MiningLogic.ClaimRestore(flag) then
		return
	end
	local allowed, refused = MiningLogic.FitPlot(#mining.stash, placedCount(player), PlotData.MaxItems)
	if refused > 0 then
		toast(player, string.format("%d didn't fit (plot holds %d)", refused, PlotData.MaxItems))
	end
	local origin = plotOrigin(player)
	for i = 1, allowed do
		local row = mining.stash[i]
		local ore = OreData.Get(row.ore)
		local c = row.cf
		if ore and #c == 12 then
			local cf = origin * CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
			spawnPiece(player, ore, row.kind, cf)
		end
	end
	mining.stash = {}
end

local function oreSequence(tier: number): { string }
	local list: { string } = {}
	for _, slot in ipairs(MiningLogic.Mix[tier] or {}) do
		for _ = 1, slot.n do
			table.insert(list, slot.id)
		end
	end
	return list
end

-- Glow stays inside the cave budget. Count lights already in the chamber
-- and strip this node's light when the chamber is at the cap.
local function trimLights(model: Model)
	local lights = 0
	for _, other in ipairs(nodes) do
		if other.model and other.model ~= model then
			lights += MiningArt.LightCount(other.model)
		end
	end
	if lights >= MiningArt.MaxNodeLights then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") then
				d:Destroy()
			end
		end
	end
end

local function spawnNode(oreId: string, cf: CFrame)
	local ore = OreData.Get(oreId)
	if ore == nil then
		return
	end
	local model = MiningArt.Node(ore)
	model:PivotTo(cf)
	model.Parent = worldFolder()
	trimLights(model)
	table.insert(nodes, {
		uid = HttpService:GenerateGUID(false),
		oreId = oreId,
		tier = ore.tier,
		model = model,
		state = { hp = ore.hp, broken = false },
		cf = cf,
		respawnAt = nil,
	})
end

local function buildWorld()
	local sites = MineSites.Current()
	local liveAnchors: { MineSites.LiveAnchor } = {}
	local liveRubble: { MineSites.LiveRubble } = {}
	for _, inst in ipairs(CollectionService:GetTagged("MineAnchor")) do
		if inst:IsA("BasePart") then
			local tier = inst:GetAttribute("Tier")
			table.insert(liveAnchors, {
				tier = if type(tier) == "number" then tier else 1,
				x = inst.Position.X,
				y = inst.Position.Y,
				z = inst.Position.Z,
			})
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("Rubble")) do
		if inst:IsA("Model") then
			local id = inst:GetAttribute("RubbleId")
			local tier = inst:GetAttribute("Tier")
			if type(id) == "string" then
				table.insert(liveRubble, {
					id = id,
					tier = if type(tier) == "number" then tier else 1,
					x = inst:GetPivot().Position.X,
					y = inst:GetPivot().Position.Y,
					z = inst:GetPivot().Position.Z,
				})
				local ex, ez = MineSites.Exit(inst:GetPivot().Position.X, inst:GetPivot().Position.Z, sites.mouth)
				table.insert(rubble, {
					id = id,
					tier = if type(tier) == "number" then tier else 1,
					model = inst,
					sealedUntil = nil,
					warned = false,
					exit = Vector3.new(ex, 0, ez),
				})
			end
		end
	end
	sites = MineSites.MergeLive(sites, liveAnchors, liveRubble)
	local used = { [1] = 0, [2] = 0, [3] = 0 }
	local seq = { oreSequence(1), oreSequence(2), oreSequence(3) }
	for _, anchor in ipairs(sites.anchors) do
		local count = used[anchor.tier] or 0
		local list = seq[anchor.tier]
		if list and count < #list then
			used[anchor.tier] = count + 1
			spawnNode(list[count + 1], CFrame.new(anchor.x, anchor.y, anchor.z))
		end
	end
	if #liveRubble == 0 then
		for _, spec in ipairs(sites.rubble) do
			local model = MiningArt.Rubble(spec.id, spec.tier)
			model:PivotTo(CFrame.new(spec.x, spec.y, spec.z))
			model.Parent = worldFolder()
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "CrawlOut"
			prompt.ActionText = "Crawl out"
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Enabled = false
			prompt.Parent = model.PrimaryPart or model
			prompt.Triggered:Connect(function(who: Player)
				local whoRoot = rootOf(who)
				if whoRoot == nil then
					return
				end
				for _, wall in ipairs(rubble) do
					if wall.model == model and crawlOk(wall, whoRoot.Position) then
						MiningService.Crawl(who)
						return
					end
				end
			end)
			table.insert(rubble, {
				id = spec.id,
				tier = spec.tier,
				model = model,
				sealedUntil = nil,
				warned = false,
				exit = Vector3.new(spec.ex, 0, spec.ez),
			})
		end
	end
	local padCf = CFrame.new(sites.furnace.x, sites.furnace.y, sites.furnace.z)
	local layout = MiningArt.PadLayout()
	local furnace = MiningArt.SmeltingFurnace()
	furnace:PivotTo(padCf * layout.furnace)
	furnace.Parent = worldFolder()
	local intakePart = furnace:FindFirstChild("SmeltIntake", true)
	if intakePart and intakePart:IsA("BasePart") then
		intake = intakePart
	end
	local stall = MiningArt.Prospector()
	stall:PivotTo(padCf * layout.prospector)
	stall.Parent = worldFolder()
	local chutePart = stall:FindFirstChild("OreChute", true)
	if chutePart and chutePart:IsA("BasePart") then
		chute = chutePart
	end
	local shopHost = stall.PrimaryPart
	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.Name = "ProspectorShop"
	shopPrompt.ActionText = "Shop"
	shopPrompt.ObjectText = "Prospector"
	shopPrompt.MaxActivationDistance = 10
	shopPrompt.RequiresLineOfSight = false
	shopPrompt.KeyboardKeyCode = Enum.KeyCode.E
	shopPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	shopPrompt.Parent = shopHost or stall
	shopPrompt.Triggered:Connect(function(who: Player)
		local mining = miningOf(who)
		if mining and not mining.starterGiven then
			mining.starterGiven = true
			mining.picks.RustyPick = true
			if mining.pick == "" then
				mining.pick = "RustyPick"
			end
			givePick(who, mining)
			publishGear(who, mining)
		end
		who:SetAttribute("MiningShop", os.clock())
	end)
	local bench = MiningArt.CraftBench()
	bench:PivotTo(padCf * layout.bench)
	bench.Parent = worldFolder()
	local craftPrompt = Instance.new("ProximityPrompt")
	craftPrompt.Name = "Craft"
	craftPrompt.ActionText = "Craft"
	craftPrompt.MaxActivationDistance = 10
	craftPrompt.RequiresLineOfSight = false
	craftPrompt.KeyboardKeyCode = Enum.KeyCode.E
	craftPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	craftPrompt.Parent = bench.PrimaryPart
	craftPrompt.Triggered:Connect(function(who: Player)
		who:SetAttribute("OpenCraft", os.clock())
	end)
end

local function respawnDue(now: number)
	for _, node in ipairs(nodes) do
		if node.model == nil and node.respawnAt ~= nil and now >= node.respawnAt then
			local ore = OreData.Get(node.oreId)
			if ore then
				local model = MiningArt.Node(ore)
				model:PivotTo(node.cf)
				trimLights(model)
				model.Parent = worldFolder()
				node.model = model
				node.state = { hp = ore.hp, broken = false }
				node.respawnAt = nil
			end
		end
	end
end

local function danger(now: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		local mining = miningOf(player)
		if root and mining then
			local tier = 0
			local nearest = 40
			for _, node in ipairs(nodes) do
				local dist = (node.cf.Position - root.Position).Magnitude
				if dist < nearest then
					nearest = dist
					tier = node.tier
				end
			end
			player:SetAttribute("InMine", nearest < 40)
			local last = player:GetAttribute("RockAt")
			local lastN = if type(last) == "number" then last else 0
			local damage = MiningLogic.RockDamage(tier, mining.hardhat, lastN, now)
			if damage > 0 then
				player:SetAttribute("RockAt", now + MiningLogic.RockWarn)
				local dust = MiningArt.Dust()
				dust:PivotTo(root.CFrame * CFrame.new(0, 6, 0))
				dust.Parent = worldFolder()
				task.delay(MiningLogic.RockWarn, function()
					if dust.Parent then
						dust:Destroy()
					end
					local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid and not mining.hardhat then
						humanoid:TakeDamage(damage)
					end
				end)
			end
		end
	end
	for _, wall in ipairs(rubble) do
		if wall.sealedUntil ~= nil then
			local left = wall.sealedUntil - now
			if left <= MiningLogic.WarnSec and not wall.warned then
				wall.warned = true
				local dust = MiningArt.Dust()
				dust:PivotTo(wall.model:GetPivot())
				dust.Parent = worldFolder()
				task.delay(2, function()
					if dust.Parent then
						dust:Destroy()
					end
				end)
			end
			if left <= 0 then
				if playerInside(wall) then
					wall.sealedUntil = now + 5
				else
					wall.sealedUntil = nil
					wall.warned = false
					hideWall(wall.model, false)
				end
			end
			local prompt = wall.model:FindFirstChild("CrawlOut", true)
			if prompt and prompt:IsA("ProximityPrompt") then
				local open = false
				for _, player in ipairs(Players:GetPlayers()) do
					local root = rootOf(player)
					if root and crawlOk(wall, root.Position) then
						open = true
						break
					end
				end
				prompt.Enabled = open
			end
		end
	end
end

local function onDeath(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local carried: { MiningLogic.Carried } = {}
	local byUid: { [string]: Model } = {}
	for _, model in ipairs(pieceModels()) do
		if model:GetAttribute("OwnerId") == player.UserId and model:FindFirstChild("CarryWeld", true) then
			local uid = model:GetAttribute("Uid")
			if type(uid) == "string" then
				table.insert(carried, { kind = if model.Name == "Ingot" then "ingot" else "chunk", uid = uid })
				byUid[uid] = model
			end
		end
	end
	for _, uid in ipairs(MiningLogic.DeathDrop(carried)) do
		local model = byUid[uid]
		local weld = model and model:FindFirstChild("CarryWeld", true)
		if weld then
			weld:Destroy()
		end
	end
end

local function attach(player: Player)
	local mining = miningOf(player)
	if mining == nil then
		return
	end
	publishGear(player, mining)
	givePick(player, mining)
	if mining.bombs > 0 then
		giveBomb(player)
	end
	giveLamp(player, mining)
	wearHat(player, mining)
	if player:GetAttribute("PlotSlot") ~= nil then
		MiningService.Restore(player)
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("ProfileLoaded"):Connect(function()
		if player:GetAttribute("ProfileLoaded") == true then
			attach(player)
		end
	end)
	player:GetAttributeChangedSignal("PlotSlot"):Connect(function()
		if player:GetAttribute("PlotSlot") == nil then
			restored[player] = { done = false }
		else
			MiningService.Restore(player)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				onDeath(player)
			end)
		end
		local mining = miningOf(player)
		if mining then
			publishGear(player, mining)
			givePick(player, mining)
			giveLamp(player, mining)
			wearHat(player, mining)
		end
	end)
	if player:GetAttribute("ProfileLoaded") == true then
		attach(player)
	end
end

-- After a craft (or any save change) the worn lamp, hat, bomb and chip
-- attributes match the profile again. CraftingService calls this.
function MiningService.Refresh(player: Player)
	local mining = miningOf(player)
	if mining == nil then
		return
	end
	publishGear(player, mining)
	givePick(player, mining)
	giveLamp(player, mining)
	wearHat(player, mining)
	if mining.bombs > 0 then
		giveBomb(player)
	else
		stripTools(player, "Bomb")
	end
end

function MiningService.Handle(player: Player, op: unknown, id: unknown, n: unknown)
	onMineAction(player, op, id, n)
end

function MiningService.SettleNow()
	settle()
end

function MiningService.TrackRubble(id: string, model: Model, exit: Vector3, sealedUntil: number?)
	table.insert(rubble, {
		id = id,
		tier = 2,
		model = model,
		sealedUntil = sealedUntil,
		warned = false,
		exit = exit,
	})
end

function MiningService.Init()
	if started then
		return
	end
	started = true
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local Net = require(shared:WaitForChild("Net") :: ModuleScript) :: any
	LeaveCommit.Add("mining", function(player: Player)
		MiningService.Commit(player)
	end)
	buildWorld()
	local remote = Net.Remote("MineAction")
	remote.OnServerEvent:Connect(onMineAction)
	RunService.Heartbeat:Connect(function()
		frame += 1
		if frame % 20 == 0 then
			settle()
			respawnDue(os.clock())
			danger(os.clock())
		end
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		swingAt[player] = nil
		warned[player] = nil
		restored[player] = nil
	end)
end

return MiningService
