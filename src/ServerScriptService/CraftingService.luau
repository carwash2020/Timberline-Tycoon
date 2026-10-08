--!strict
-- CraftingService: the bench. One server transaction consumes the ingots
-- and, in the same block, the owned log through WoodService. Furniture
-- recipes stay disabled.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local WoodService = require(script.Parent.WoodService)
local CraftData = require(ReplicatedStorage.Shared.Mining.CraftData)
local CraftLogic = require(ReplicatedStorage.Shared.Mining.CraftLogic)
local MiningSchema = require(ReplicatedStorage.Shared.Mining.MiningSchema)
local MiningService = require(script.Parent.MiningService)

local CraftingService = {}

local started = false

local function toast(player: Player, text: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("Notify")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, text)
	end
end

local function miningOf(player: Player): MiningSchema.Mining?
	local profile = ProfileService.GetProfile(player)
	if profile == nil then
		return nil
	end
	local raw = profile :: any
	local mining = MiningSchema.Migrate(raw.mining)
	raw.mining = mining
	return mining
end

local function truckWelded(model: Model): boolean
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") then
			local other = if d.Part0 and d.Part0:IsDescendantOf(model) then d.Part1 else d.Part0
			if other and CraftLogic.IsTruckWeld(other.Name) then
				return true
			end
		end
	end
	return false
end

local function oreModels(player: Player): { Model }
	local folder = Workspace:FindFirstChild("Mining")
	local list: { Model } = {}
	if folder == nil then
		return list
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OwnerId") == player.UserId then
			if child.Name == "OreChunk" or child.Name == "Ingot" then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function stockFrom(player: Player): (CraftLogic.Stock, { [string]: { Model } }, { [string]: { Model } })
	local stock: CraftLogic.Stock = { ingots = {}, chunks = {} }
	local ingotModels: { [string]: { Model } } = {}
	local chunkModels: { [string]: { Model } } = {}
	for _, model in ipairs(oreModels(player)) do
		if not truckWelded(model) then
			local ore = model:GetAttribute("Ore")
			if type(ore) == "string" then
				local bag = if model.Name == "Ingot" then stock.ingots else stock.chunks
				local pile = if model.Name == "Ingot" then ingotModels else chunkModels
				bag[ore] = (bag[ore] or 0) + 1
				local list = pile[ore]
				if list == nil then
					list = {}
					pile[ore] = list
				end
				table.insert(list, model)
			end
		end
	end
	return stock, ingotModels, chunkModels
end

-- A loose log near the player. Owner and Volume are the server attributes.
-- A log welded into a truck bed does not count.
local function findLog(player: Player): (Model?, CraftLogic.LogFacts?)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	local tagged = CollectionService:GetTagged("Wood")
	local best: Model? = nil
	local bestDist = 16
	for _, inst in ipairs(tagged) do
		if inst:IsA("Model") and not truckWelded(inst) then
			local owner = inst:GetAttribute("Owner")
			local volume = inst:GetAttribute("Volume")
			if type(owner) == "number" and type(volume) == "number" then
				local dist = (inst:GetPivot().Position - root.Position).Magnitude
				if dist < bestDist then
					best = inst
					bestDist = dist
				end
			end
		end
	end
	if best == nil then
		return nil, nil
	end
	local uid = best:GetAttribute("Uid")
	return best,
		{
			uid = if type(uid) == "string" then uid else best.Name,
			owner = best:GetAttribute("Owner") :: number,
			volume = best:GetAttribute("Volume") :: number,
			welded = false,
		}
end

local function take(pile: { Model }?, n: number)
	local left = n
	for _, model in ipairs(pile or {}) do
		if left <= 0 then
			break
		end
		if model.Parent then
			model:Destroy()
			left -= 1
		end
	end
	return left == 0
end

function CraftingService.Craft(player: Player, recipeId: string): boolean
	local mining = miningOf(player)
	local recipe = CraftData.Get(recipeId)
	if mining == nil or recipe == nil then
		return false
	end
	if not recipe.enabled then
		toast(player, CraftData.Soon)
		return false
	end
	local stock, ingots, chunks = stockFrom(player)
	local logModel, log = findLog(player)
	local still = logModel ~= nil and logModel.Parent ~= nil
	local plan = CraftLogic.Commit(recipeId, stock, log, player.UserId, still)
	if not plan.ok or plan.gives == nil then
		if plan.reason == "log" then
			toast(player, "Needs a log you own")
		elseif plan.reason == "short" then
			toast(player, "Missing materials")
		end
		return false
	end
	-- One block: ingots and chunks, then the log. No wait between them.
	-- A grab that already took the log fails the commit above.
	if logModel ~= nil and logModel.Parent == nil then
		return false
	end
	for _, step in ipairs(plan.steps) do
		if step.kind == "ingot" then
			take(ingots[step.ore or ""], step.n or 0)
		elseif step.kind == "chunk" then
			take(chunks[step.ore or ""], step.n or 0)
		elseif step.kind == "log" and logModel ~= nil then
			local piece = WoodService.FromModel(logModel)
			if piece then
				WoodService.Remove(piece, "craft")
			else
				logModel:Destroy()
			end
		end
	end
	local granted = CraftLogic.Grant({
		bombs = mining.bombs,
		ropes = mining.ropes,
		lamp = mining.lamp,
		hardhat = mining.hardhat,
		crafted = mining.crafted,
	}, plan.gives, recipeId)
	mining.bombs = granted.bombs
	mining.ropes = granted.ropes
	mining.lamp = granted.lamp
	mining.hardhat = granted.hardhat
	mining.crafted = granted.crafted
	MiningService.Refresh(player)
	if granted.lamp then
		toast(player, "Miner's Lamp crafted")
	elseif granted.hardhat then
		toast(player, "Hardhat crafted")
	elseif (plan.gives.bombs or 0) > 0 then
		toast(player, "Bomb bundle crafted")
	elseif (plan.gives.ropes or 0) > 0 then
		toast(player, "Rope ladder crafted")
	end
	return true
end

function CraftingService.Init()
	if started then
		return
	end
	started = true
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local Net = require(shared:WaitForChild("Net") :: ModuleScript) :: any
	local remote = Net.Remote("CraftAction")
	remote.OnServerEvent:Connect(function(player: Player, recipeId: unknown)
		if type(recipeId) ~= "string" or not RateLimiter.Allow(player, "CraftAction") then
			return
		end
		CraftingService.Craft(player, recipeId)
	end)
end

return CraftingService
