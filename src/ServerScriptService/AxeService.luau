--!strict
-- AxeService: axes are items.
--
-- Every axe a player owns is its own item in profile.axes (with a uid), so
-- players can collect several, keep older ones for special jobs (the Inferno
-- Axe on volcano trees), and pick which to use from the hotbar.
--   * On spawn, every owned axe that isn't lying in the world goes into the
--     Backpack, and the one the player last held is equipped.
--   * Drop() lays an axe on the ground with a "Pick up" prompt. It stays
--     owned: only its owner can pick it up (unless
--     GameConfig.AxePickupByOthers is on, which makes a dropped axe a gift),
--     and if the owner leaves it's simply back in their inventory next time.
--     Dying doesn't lose axes either. Axes are never lost.
--   * GetEquippedAxe() is what ChopTree trusts: only a server-made tool
--     whose uid is in the player's inventory counts.
--   * In Studio, typing "/giveaxe <name>" in chat grants a temporary axe
--     (never saved) so switching can be tested before the shop exists.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

type AxeItem = ProfileService.AxeItem
type AxeDef = ItemCatalog.AxeDef

local AxeService = {}

local HANDLE_COLOR = Color3.fromRGB(122, 82, 48)

type Dropped = { model: Model, owner: Player, item: AxeItem, temporary: boolean }

local temporary: { [Player]: { AxeItem } } = {} -- Studio test axes, never saved
local dropped: { [string]: Dropped } = {} -- [uid]
local lastCommand: { [Player]: number } = {} -- Studio /giveaxe debounce
local notify: (Player, string) -> () = function() end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------

-- Returns the item and whether it's a temporary (unsaved) one.
local function findItem(player: Player, uid: string): (AxeItem?, boolean)
	local profile = ProfileService.GetProfile(player)
	if profile then
		for _, item in ipairs(profile.axes) do
			if item.uid == uid then
				return item, false
			end
		end
	end
	for _, item in ipairs(temporary[player] or {}) do
		if item.uid == uid then
			return item, true
		end
	end
	return nil, false
end

local function allItems(player: Player): { AxeItem }
	local out: { AxeItem } = {}
	local profile = ProfileService.GetProfile(player)
	if profile then
		for _, item in ipairs(profile.axes) do
			table.insert(out, item)
		end
	end
	for _, item in ipairs(temporary[player] or {}) do
		table.insert(out, item)
	end
	return out
end

local function removeItem(player: Player, uid: string)
	local profile = ProfileService.GetProfile(player)
	local lists = { temporary[player] or {} }
	if profile then
		table.insert(lists, profile.axes)
	end
	for _, list in ipairs(lists) do
		for i, item in ipairs(list) do
			if item.uid == uid then
				table.remove(list, i)
				return
			end
		end
	end
end

local function addItem(player: Player, item: AxeItem, isTemporary: boolean)
	if isTemporary then
		local list = temporary[player] or {}
		temporary[player] = list
		table.insert(list, item)
		return
	end
	local profile = ProfileService.GetProfile(player)
	if profile then
		table.insert(profile.axes, item)
		profile.bestAxeTier = math.max(profile.bestAxeTier, ItemCatalog.AxeTier(item.id) or 1)
	end
end

---------------------------------------------------------------------------
-- Building axes (tool in hand, or lying in the world)
---------------------------------------------------------------------------

local function buildParts(def: AxeDef): (Part, Part)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 3, 0.5)
	handle.Color = HANDLE_COLOR
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false -- a colliding tool can trip or fling its holder
	handle.Massless = true

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.4, 1.2, 2)
	head.Color = Color3.fromHex(def.look.headColor)
	head.Material = Enum.Material:FromName(def.look.material) or Enum.Material.Metal
	head.CanCollide = false
	head.Massless = true
	if def.look.glow then
		local light = Instance.new("PointLight")
		light.Color = head.Color
		light.Brightness = 1.5
		light.Range = 8
		light.Parent = head
	end
	return handle, head
end

local function findTool(player: Player, uid: string): Tool?
	local containers: { Instance } = {}
	if player.Character then
		table.insert(containers, player.Character)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	for _, container in ipairs(containers) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("AxeUid") == uid then
				return child
			end
		end
	end
	return nil
end

-- Puts a tool for `item` in the player's Backpack (unless it's already there).
local function giveTool(player: Player, item: AxeItem): Tool?
	local def = ItemCatalog.GetAxe(item.id)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not def or not backpack or dropped[item.uid] then
		return nil
	end
	local existing = findTool(player, item.uid)
	if existing then
		return existing
	end
	local tool = Instance.new("Tool")
	tool.Name = def.displayName -- what the hotbar shows
	tool.ToolTip = string.format("%s: %d damage", def.displayName, def.damage)
	tool.RequiresHandle = true
	tool.CanBeDropped = false -- dropping goes through Drop(), not Roblox's built-in drop
	tool:SetAttribute("AxeId", def.id)
	tool:SetAttribute("AxeUid", item.uid)
	local handle, head = buildParts(def)
	handle.Parent = tool
	head.Position = Vector3.new(0, 1.8, 0)
	head.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle
	tool.Parent = backpack
	return tool
end

local function removeDropped(uid: string)
	local d = dropped[uid]
	if d then
		dropped[uid] = nil
		d.model:Destroy()
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- The axe the player is holding, if it's a real, owned one.
function AxeService.GetEquippedAxe(player: Player): AxeDef?
	local char = player.Character
	local tool = if char then char:FindFirstChildOfClass("Tool") else nil
	local uid = if tool then tool:GetAttribute("AxeUid") else nil
	if type(uid) ~= "string" or dropped[uid] then
		return nil
	end
	local item = findItem(player, uid)
	return if item then ItemCatalog.GetAxe(item.id) else nil
end

-- Fills a fresh character's Backpack with every axe the player owns (that
-- isn't lying somewhere) and equips the one they last held.
function AxeService.GiveLoadout(player: Player, character: Model)
	local profile = ProfileService.GetProfile(player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not profile or not humanoid then
		return
	end
	local toEquip: Tool? = nil
	for _, item in ipairs(allItems(player)) do
		local tool = giveTool(player, item)
		if tool and (toEquip == nil or item.uid == profile.equippedAxe) then
			toEquip = tool
		end
	end
	if toEquip then
		humanoid:EquipTool(toEquip) -- spawn with an axe in hand (GAME_DESIGN §11)
	end
	-- Remember which axe they hold, for next spawn.
	character.ChildAdded:Connect(function(child)
		local uid = child:GetAttribute("AxeUid")
		if child:IsA("Tool") and type(uid) == "string" then
			profile.equippedAxe = uid
		end
	end)
end

-- Adds a new axe to the player's inventory and Backpack. For the shop
-- (Phase 2) and the Studio test command.
function AxeService.Grant(player: Player, axeId: string, isTemporary: boolean?): AxeItem?
	if not ItemCatalog.GetAxe(axeId) then
		return nil
	end
	local item: AxeItem = { uid = Util.guid(), id = axeId }
	addItem(player, item, isTemporary == true)
	giveTool(player, item)
	return item
end

local function onPickUp(player: Player, uid: string)
	if not RateLimiter.Allow(player, "PickUpAxe") then
		return
	end
	local d = dropped[uid]
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not d or not hrp then
		return
	end
	if
		(hrp.Position - d.model:GetPivot().Position).Magnitude
		> GameConfig.PickupPromptRange + GameConfig.RangeTolerance
	then
		return
	end
	local def = ItemCatalog.GetAxe(d.item.id)
	local name = if def then def.displayName else "axe"
	if d.owner ~= player then
		if not GameConfig.AxePickupByOthers then
			notify(player, string.format("That's %s's %s.", d.owner.DisplayName, name))
			return
		end
		-- A gift: the axe moves from the dropper's inventory to the picker's.
		removeItem(d.owner, uid)
		addItem(player, d.item, d.temporary)
		notify(d.owner, string.format("%s picked up your %s.", player.DisplayName, name))
	end
	removeDropped(uid)
	giveTool(player, d.item)
	notify(player, "Picked up the " .. name .. ".")
end

-- Lays one of the player's axes on the ground in front of them.
function AxeService.Drop(player: Player, uid: unknown)
	if type(uid) ~= "string" or not RateLimiter.Allow(player, "DropAxe") then
		return
	end
	local item, isTemporary = findItem(player, uid)
	local tool = findTool(player, uid)
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local def = if item then ItemCatalog.GetAxe(item.id) else nil
	if not item or not def or not tool or not char or not hrp or dropped[uid] then
		return
	end
	local mine = 0
	for _, d in pairs(dropped) do
		if d.owner == player then
			mine += 1
		end
	end
	if mine >= GameConfig.MaxDroppedAxes then
		notify(player, string.format("You already have %d axes lying around. Pick some up first.", mine))
		return
	end
	tool:Destroy()

	-- Find the ground just in front of the player.
	local spot = (hrp.CFrame * CFrame.new(0, 0, -3)).Position
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -80, 0), params)
	local groundY = if hit then hit.Position.Y else spot.Y - 3

	-- Lying flat: the handle along the ground, the head beside it.
	local model = Instance.new("Model")
	model.Name = "DroppedAxe"
	local handle, head = buildParts(def)
	handle.Anchored = true
	head.Anchored = true
	local base = CFrame.new(spot.X, groundY + 0.25, spot.Z)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
		* CFrame.Angles(0, 0, math.rad(90))
	handle.CFrame = base
	head.CFrame = base * CFrame.new(0, 1.8, 0)
	handle.Parent = model
	head.Parent = model
	model.PrimaryPart = handle
	model:SetAttribute("AxeUid", uid)
	model:SetAttribute("OwnerId", player.UserId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = string.format("%s (%s)", def.displayName, player.DisplayName)
	prompt.MaxActivationDistance = GameConfig.PickupPromptRange
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle
	prompt.Triggered:Connect(function(who: Player)
		onPickUp(who, uid)
	end)

	local map = workspace:FindFirstChild("TimberlineMap")
	model.Parent = map or workspace
	dropped[uid] = { model = model, owner = player, item = item, temporary = isTemporary }
end

-- Clears the player's world axes when they leave. They're still in the
-- save, so they're back in the Backpack next session.
function AxeService.PlayerRemoving(player: Player)
	for uid, d in pairs(dropped) do
		if d.owner == player then
			removeDropped(uid)
		end
	end
	temporary[player] = nil
	lastCommand[player] = nil
end

-- Studio only: "/giveaxe inferno" (any part of an axe's name) grants a
-- temporary axe that's never saved.
local function giveAxeCommand(player: Player, message: string)
	local query = string.match(string.lower(message), "^/giveaxe%s+(.+)$")
	if not query then
		return
	end
	-- Both chat hooks below can fire for one message; only act once.
	local now = os.clock()
	if now - (lastCommand[player] or 0) < 0.5 then
		return
	end
	lastCommand[player] = now
	for _, def in ipairs(ItemCatalog.AxeLadder()) do
		if string.find(string.lower(def.displayName), query, 1, true) then
			AxeService.Grant(player, def.id, true)
			notify(player, string.format("Gave you a test %s (Studio only, not saved).", def.displayName))
			return
		end
	end
	notify(player, "No axe matches '" .. query .. "'.")
end

local function setupStudioCommands()
	-- Current chat (TextChatService): a registered command.
	local command = Instance.new("TextChatCommand")
	command.Name = "GiveAxeCommand"
	command.PrimaryAlias = "/giveaxe"
	command.Triggered:Connect(function(source: TextSource, message: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			giveAxeCommand(player, message)
		end
	end)
	command.Parent = TextChatService
	-- Legacy chat fallback.
	local function watch(player: Player)
		player.Chatted:Connect(function(message: string)
			giveAxeCommand(player, message)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
end

-- `notifyFn` shows a toast to one player (GameServer's notify).
function AxeService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
	if RunService:IsStudio() then
		setupStudioCommands()
	end
end

return AxeService
