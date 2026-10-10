--!strict
-- AxeService: axes are items.
--
-- Every axe a player owns is its own item in profile.axes (with a uid), so
-- players can collect several, keep older ones for special jobs (the Inferno
-- Axe on volcano trees), and pick which to use from the hotbar.
--   * On spawn, every owned axe that isn't lying in the world goes into the
--     Backpack, and the one the player last held is equipped.
--   * Drop() lays an axe on the ground with a "Pick up" prompt, unless it's
--     the last one the player has to hand (every other owned axe is lying
--     somewhere): "You need an axe to chop!". Judged from the save and the
--     server's own list of dropped axes, never from what the client says.
--     A dropped axe stays owned: only its owner can pick it up (unless
--     GameConfig.AxePickupByOthers is on, which makes a dropped axe a gift),
--     and if the owner leaves it's simply back in their inventory next time.
--     Dying doesn't lose axes either. Axes are never lost.
--   * GetEquippedAxe() is what ChopTree trusts: only a server-made tool
--     whose uid is in the player's inventory counts.
--   * Grant() adds a new axe (the Tool Shed, ShopService). Player
--     attributes OwnedAxes and BestAxeTier mirror the saved inventory for
--     the shop screen.
--   * In Studio, typing "/giveaxe <name>" in chat grants a temporary axe
--     (never saved) so any axe can be tried without buying it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local AxeArt = require(ReplicatedStorage.Shared.Art.AxeArt)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TemperLogic = require(ReplicatedStorage.Shared.TemperLogic)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local PaidItems = require(ReplicatedStorage.Shared.PaidItems)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

type AxeItem = ProfileService.AxeItem
type AxeDef = ItemCatalog.AxeDef

local AxeService = {}

type Dropped = { model: Model, owner: Player, item: AxeItem, temporary: boolean }

local temporary: { [Player]: { AxeItem } } = {} -- Studio test axes, never saved
local dropped: { [string]: Dropped } = {} -- [uid]
local lastCommand: { [Player]: number } = {} -- Studio /giveaxe debounce
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

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

-- Saved axes only (temporary test axes don't count): how many of each id,
-- and in total.
local function ownedCounts(player: Player): ({ [string]: number }, number)
	local counts: { [string]: number } = {}
	local profile = ProfileService.GetProfile(player)
	local items = if profile then profile.axes else {}
	for _, item in ipairs(items) do
		counts[item.id] = (counts[item.id] or 0) + 1
	end
	return counts, #items
end

-- Mirrors the saved inventory on player attributes for the shop screen.
local function publishOwned(player: Player)
	local profile = ProfileService.GetProfile(player)
	if profile then
		player:SetAttribute("OwnedAxes", ShopLogic.EncodeOwned((ownedCounts(player))))
		player:SetAttribute("BestAxeTier", profile.bestAxeTier)
	end
end

-- Whether the player has an axe to chop with besides `uid`: one they own
-- (saved, or a Studio test axe) that isn't lying in the world.
local function keepsAnAxe(player: Player, uid: string): boolean
	for _, item in ipairs(allItems(player)) do
		if item.uid ~= uid and not dropped[item.uid] and ItemCatalog.GetAxe(item.id) then
			return true
		end
	end
	return false
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
				publishOwned(player)
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
		publishOwned(player)
	end
end

---------------------------------------------------------------------------
-- Building axes (tool in hand, or lying in the world)
---------------------------------------------------------------------------

-- The models come from Shared/Art/AxeArt: a "Handle" (the haft) with the
-- head and its details welded to it. In hand everything is massless and
-- non-colliding (a colliding tool can trip or fling its holder).

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

-- Copies the axe's temper onto its tool (TemperPrefix, TemperTier) so the
-- client paces its swings with Keen. Clears both when it has none.
function AxeService.StampTemper(player: Player, uid: string, tool: Tool?)
	local target = tool or findTool(player, uid)
	if target == nil then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local all = if profile then (profile :: any).temper else nil
	local rec = if type(all) == "table" then all[uid] else nil
	if type(rec) == "table" and TemperLogic.Known(rec.prefix) then
		target:SetAttribute("TemperPrefix", rec.prefix)
		target:SetAttribute("TemperTier", rec.tier)
	else
		target:SetAttribute("TemperPrefix", nil)
		target:SetAttribute("TemperTier", nil)
	end
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
	local tip = string.format("%s: %d damage", def.displayName, def.damage)
	if def.robux then
		tip ..= "\n" .. GameConfig.LuxPerkLine()
	end
	tool.ToolTip = tip
	tool.RequiresHandle = true
	tool.CanBeDropped = false -- dropping goes through Drop(), not Roblox's built-in drop
	tool:SetAttribute("AxeId", def.id)
	tool:SetAttribute("AxeUid", item.uid)
	AxeService.StampTemper(player, item.uid, tool)
	-- The hand holds near the foot of the haft, the blade facing forward.
	tool.Grip = AxeArt.Grip(def)
	local art = AxeArt.Held(def)
	for _, child in ipairs(art:GetChildren()) do
		child.Parent = tool -- each part carries its own weld to the Handle
	end
	art:Destroy()
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
	local def = if item then ItemCatalog.GetAxe(item.id) else nil
	if not def then
		return nil
	end
	-- A tempered axe swings with its temper (Keen: cooldown, Heavy: damage).
	-- The catalog entry is never changed; Apply returns a copy.
	local profile = ProfileService.GetProfile(player)
	local temper = if profile and type((profile :: any).temper) == "table" then (profile :: any).temper[uid] else nil
	return if temper then TemperLogic.Apply(def, temper) else def
end

-- Fills a fresh character's Backpack with every axe the player owns (that
-- isn't lying somewhere) and equips the one they last held.
function AxeService.GiveLoadout(player: Player, character: Model)
	local profile = ProfileService.GetProfile(player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not profile or not humanoid then
		return
	end
	publishOwned(player)
	-- A pass axe comes back on every spawn, from the save (and the attribute
	-- the ownership check sets). Ensure won't add a second copy.
	local passes = profile.passes
	-- (an owner grant counts: PaidItems.SaveHasPass reads passes and ownerGrants)
	if
		(passes and passes[GameConfig.LuxAxeId] == true)
		or PaidItems.SaveHasPass(profile, GameConfig.LuxAxeId)
		or player:GetAttribute("Pass_" .. GameConfig.LuxAxeId) == true
	then
		AxeService.Ensure(player, GameConfig.LuxAxeId)
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

-- Makes sure the player has exactly one saved `axeId` (a pass axe), and
-- that its tool is in the Backpack when it isn't lying in the world.
-- A second call does not add another item.
function AxeService.Ensure(player: Player, axeId: string)
	if not ItemCatalog.GetAxe(axeId) then
		return
	end
	local counts = ownedCounts(player)
	if (counts[axeId] or 0) > 0 then
		for _, item in ipairs(allItems(player)) do
			if item.id == axeId then
				giveTool(player, item)
			end
		end
		return
	end
	AxeService.Grant(player, axeId, false)
end

-- Adds a new axe to the player's inventory and Backpack, and returns it
-- with its Tool (nil while the player has no Backpack, e.g. mid-respawn:
-- the next spawn hands it over). For the shop and the Studio test command.
function AxeService.Grant(player: Player, axeId: string, isTemporary: boolean?): (AxeItem?, Tool?)
	if not ItemCatalog.GetAxe(axeId) then
		return nil, nil
	end
	local item: AxeItem = { uid = Util.guid(), id = axeId }
	addItem(player, item, isTemporary == true)
	return item, giveTool(player, item)
end

-- Takes every copy of a pass axe away (the owner hub revoking a granted
-- pass): from the save, the account list, the parked slots, the Backpack and
-- the ground. A player is never left without an axe: if that was their last,
-- they get a Rusty Axe. Returns how many saved copies went.
function AxeService.RemoveAll(player: Player, axeId: string): number
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return 0
	end
	local uids: { string } = {}
	for _, item in ipairs(allItems(player)) do
		if item.id == axeId then
			table.insert(uids, item.uid)
		end
	end
	for _, uid in ipairs(uids) do
		removeDropped(uid)
		local tool = findTool(player, uid)
		if tool then
			tool:Destroy()
		end
		if profile.equippedAxe == uid then
			profile.equippedAxe = ""
		end
	end
	local list = temporary[player]
	if list then
		for i = #list, 1, -1 do
			if list[i].id == axeId then
				table.remove(list, i)
			end
		end
	end
	local removed = SaveSlotLogic.ForgetAccountAxe(profile, axeId)
	if #profile.axes == 0 then
		AxeService.Grant(player, "RustyAxe", false)
	end
	publishOwned(player)
	return removed
end

-- How many saved axes the player owns: per axe id, and in total.
function AxeService.OwnedCounts(player: Player): ({ [string]: number }, number)
	return ownedCounts(player)
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
	if def.robux or def.quest then
		notify(player, string.format("The %s can't be dropped or sold.", def.displayName))
		return
	end
	if not keepsAnAxe(player, uid) then
		notify(player, "You need an axe to chop!")
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

	-- Lying on its side on the ground, turned any which way. Its
	-- PrimaryPart is the Handle (the prompt goes there).
	local model = AxeArt.Dropped(def)
	model.Name = "DroppedAxe"
	Kit.placeAt(model, CFrame.new(spot.X, groundY, spot.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	local handle = model.PrimaryPart :: BasePart
	model:SetAttribute("AxeUid", uid)
	model:SetAttribute("OwnerId", player.UserId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = string.format("%s (%s)", def.displayName, player.DisplayName)
	prompt.MaxActivationDistance = GameConfig.PickupPromptRange
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	InputKit.PromptDefaults(prompt, "Interact")
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
