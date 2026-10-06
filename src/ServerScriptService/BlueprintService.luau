--!strict
-- BlueprintService: the hammer and the rolled plans, as items you hold
-- (BUILD_SYSTEM.md; the rules are in Shared/BlueprintBook, art in
-- Shared/Art/HammerArt and BlueprintArt).
--   * Everyone with profile.hammer has a Hammer Tool, handed over on every
--     spawn after the axes (so it sits in the second hotbar slot). What it
--     does is client side (HammerController): opens the plan list and
--     swings. The server only ever acts on the remotes below.
--   * A blueprint is one item in profile.blueprintItems ({ uid, id }) and a
--     Tool in your hands or Backpack. Grant() adds one (the General Store,
--     the owner's /gift, a world pickup).
--   * UseBlueprint(uid): it must be one of your saved items, in your hand,
--     not lying in the world. BlueprintBook.Redeem consumes it and adds the
--     building to profile.blueprintBook, yours for good. The player
--     attribute "Blueprints" mirrors the book for the hammer's list.
--   * DropBlueprint(uid): lays the item on the ground in front of you with
--     a Pick up prompt. A dropped plan stays yours and only you can pick it
--     up; if you leave it is simply back in your pack next time. Plans
--     placed in the world with Spawn() belong to nobody: anyone may take one.
--   * Nothing here touches cash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlueprintArt = require(ReplicatedStorage.Shared.Art.BlueprintArt)
local BlueprintBook = require(ReplicatedStorage.Shared.BlueprintBook)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HammerArt = require(ReplicatedStorage.Shared.Art.HammerArt)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local BlueprintService = {}

-- Plans lying in the world at once, per player.
BlueprintService.MaxDropped = 10

type Dropped = { model: Model, owner: Player?, item: BlueprintBook.Item }

local dropped: { [string]: Dropped } = {} -- [uid]
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

local function nameOf(id: string): string
	local bp = PlotData.Blueprint(id)
	return if bp then bp.displayName else id
end

local function profileOf(player: Player): ProfileService.Profile?
	local profile = ProfileService.GetProfile(player)
	if profile and type(profile.blueprintItems) ~= "table" then
		profile.blueprintItems = {}
	end
	if profile and type(profile.blueprintBook) ~= "table" then
		profile.blueprintBook = {}
	end
	return profile
end

-- The book on a player attribute (ids, comma separated) for the hammer's list.
function BlueprintService.Publish(player: Player)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local ids: { string } = {}
	for _, id in ipairs(BlueprintBook.Clean(profile.blueprintBook)) do
		table.insert(ids, id)
	end
	-- A save that has not been migrated yet still shows its bought unlocks.
	local legacy = profile.furnitureBlueprints
	if type(legacy) == "table" then
		for id, on in pairs(legacy) do
			if on == true and BlueprintBook.IsPlan(id) and not table.find(ids, id) then
				table.insert(ids, id)
			end
		end
	end
	player:SetAttribute("Blueprints", ShopLogic.EncodeSet(ids))
end

---------------------------------------------------------------------------
-- Tools
---------------------------------------------------------------------------

local function toolsOf(player: Player): { Tool }
	local out: { Tool } = {}
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
			if child:IsA("Tool") then
				table.insert(out, child)
			end
		end
	end
	return out
end

local function findPlanTool(player: Player, uid: string): Tool?
	for _, tool in ipairs(toolsOf(player)) do
		if tool:GetAttribute("BlueprintUid") == uid then
			return tool
		end
	end
	return nil
end

-- Whether that Tool is in the player's hands (the character), not the Backpack.
local function inHand(player: Player, tool: Tool): boolean
	return player.Character ~= nil and tool.Parent == player.Character
end

local function prepare(art: Model, tool: Tool)
	for _, child in ipairs(art:GetChildren()) do
		child.Parent = tool -- each part carries its own weld to the Handle
	end
	art:Destroy()
end

-- The Hammer, once. Returns the Tool (new or already there).
function BlueprintService.GiveHammer(player: Player): Tool?
	local profile = ProfileService.GetProfile(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not profile or profile.hammer ~= true or not backpack then
		return nil
	end
	for _, tool in ipairs(toolsOf(player)) do
		if tool:GetAttribute("Hammer") == true then
			return tool
		end
	end
	local tool = Instance.new("Tool")
	tool.Name = "Hammer"
	tool.ToolTip = "Click to open your blueprints. Aim at something you built to move, turn or sell it."
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("Hammer", true)
	tool.Grip = HammerArt.Grip()
	prepare(HammerArt.Held(), tool)
	tool.Parent = backpack
	return tool
end

local function givePlanTool(player: Player, item: BlueprintBook.Item): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or dropped[item.uid] or not BlueprintBook.IsPlan(item.id) then
		return nil
	end
	local existing = findPlanTool(player, item.uid)
	if existing then
		return existing
	end
	local tool = Instance.new("Tool")
	tool.Name = nameOf(item.id) .. " Blueprint"
	tool.ToolTip = string.format("Use it to learn the %s. You keep what you learn for good.", nameOf(item.id))
	tool.RequiresHandle = true
	tool.CanBeDropped = false -- dropping goes through Drop(), not Roblox's built-in drop
	tool:SetAttribute("BlueprintId", item.id)
	tool:SetAttribute("BlueprintUid", item.uid)
	tool.Grip = BlueprintArt.Grip()
	prepare(BlueprintArt.Held(item.id), tool)
	tool.Parent = backpack
	return tool
end

-- Fills a fresh character's Backpack: the Hammer, then every plan you
-- carry that is not lying in the world. Nothing is equipped for you.
function BlueprintService.GiveLoadout(player: Player, _character: Model)
	local profile = profileOf(player)
	if not profile then
		return
	end
	BlueprintService.Publish(player)
	BlueprintService.GiveHammer(player)
	for _, item in ipairs(profile.blueprintItems) do
		givePlanTool(player, item)
	end
end

---------------------------------------------------------------------------
-- Getting one
---------------------------------------------------------------------------

-- Whether one more plan fits and is not a repeat of something you hold.
function BlueprintService.CanGrant(player: Player, id: string): (boolean, string?)
	local profile = profileOf(player)
	if not profile then
		return false, "missing"
	end
	if not BlueprintBook.IsPlan(id) then
		return false, "unknown"
	end
	if BlueprintBook.Has(profile.blueprintBook, id) or BlueprintBook.Owns(profile, id) then
		return false, "known"
	end
	for _, item in ipairs(profile.blueprintItems) do
		if item.id == id then
			return false, "held"
		end
	end
	if #profile.blueprintItems >= BlueprintBook.MaxItems then
		return false, "full"
	end
	return true, nil
end

-- Adds a rolled plan to your pack and hands you its Tool. Returns the item,
-- or nil and why it could not be (CanGrant's reasons).
function BlueprintService.Grant(player: Player, id: string): (BlueprintBook.Item?, string?)
	local ok, why = BlueprintService.CanGrant(player, id)
	if not ok then
		return nil, why
	end
	local profile = profileOf(player) :: ProfileService.Profile
	local uid = Util.guid()
	local result = BlueprintBook.Grant(profile.blueprintItems, id, uid)
	if result ~= "ok" then
		return nil, result
	end
	local item = profile.blueprintItems[#profile.blueprintItems]
	givePlanTool(player, item)
	return item, nil
end

---------------------------------------------------------------------------
-- Using one
---------------------------------------------------------------------------

function BlueprintService.Use(player: Player, uid: unknown)
	if type(uid) ~= "string" or not RateLimiter.Allow(player, "UseBlueprint") then
		return
	end
	local profile = profileOf(player)
	if not profile then
		return
	end
	local item = BlueprintBook.FindItem(profile.blueprintItems, uid)
	local tool = findPlanTool(player, uid)
	-- Only the plan in your hand, never one lying in the world.
	if not item or dropped[uid] or not tool or not inHand(player, tool) then
		return
	end
	local result, id = BlueprintBook.Redeem(profile.blueprintBook, profile.blueprintItems, uid)
	if result == "ok" then
		tool:Destroy()
		BlueprintService.Publish(player)
	end
	notify(player, BlueprintBook.RedeemText(result, id))
end

---------------------------------------------------------------------------
-- In the world
---------------------------------------------------------------------------

local function groundAt(spot: Vector3, ignore: Instance?): number
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	if ignore then
		params.FilterDescendantsInstances = { ignore }
	end
	local hit = workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position.Y else spot.Y - 3
end

local function removeDropped(uid: string)
	local d = dropped[uid]
	if d then
		dropped[uid] = nil
		d.model:Destroy()
	end
end

local function pickUp(player: Player, uid: string)
	if not RateLimiter.Allow(player, "PickUpBlueprint") then
		return
	end
	local d = dropped[uid]
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not d or not root then
		return
	end
	if
		(root.Position - d.model:GetPivot().Position).Magnitude
		> GameConfig.PickupPromptRange + GameConfig.RangeTolerance
	then
		return
	end
	local id = d.item.id
	if d.owner ~= nil then
		-- Yours, lying where you left it.
		if d.owner ~= player then
			notify(player, string.format("That's %s's blueprint.", d.owner.DisplayName))
			return
		end
		removeDropped(uid)
		givePlanTool(player, d.item)
		notify(player, string.format("Picked up the %s blueprint.", nameOf(id)))
		return
	end
	-- Found in the world: it becomes yours if it fits.
	local ok, why = BlueprintService.CanGrant(player, id)
	if not ok then
		if why == "known" then
			notify(player, string.format("You already know the %s.", nameOf(id)))
		elseif why == "held" then
			notify(player, string.format("You already carry the %s blueprint.", nameOf(id)))
		else
			notify(player, "Your pack is full of blueprints.")
		end
		return
	end
	removeDropped(uid)
	BlueprintService.Grant(player, id)
	notify(player, string.format("Found the %s blueprint!", nameOf(id)))
end

-- Puts a plan model on the ground at `spot` with a Pick up prompt.
local function layDown(spot: Vector3, item: BlueprintBook.Item, owner: Player?): Model
	local model = BlueprintArt.Dropped(item.id)
	model.Name = "DroppedBlueprint"
	Kit.placeAt(
		model,
		CFrame.new(spot.X, groundAt(spot, owner and owner.Character), spot.Z)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
	)
	local handle = model.PrimaryPart :: BasePart
	model:SetAttribute("BlueprintUid", item.uid)
	model:SetAttribute("BlueprintId", item.id)
	if owner then
		model:SetAttribute("OwnerId", owner.UserId)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = nameOf(item.id) .. " Blueprint"
	prompt.MaxActivationDistance = GameConfig.PickupPromptRange
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.Parent = handle
	prompt.Triggered:Connect(function(who: Player)
		pickUp(who, item.uid)
	end)
	local map = workspace:FindFirstChild("TimberlineMap")
	model.Parent = map or workspace
	dropped[item.uid] = { model = model, owner = owner, item = item }
	return model
end

-- A plan for anyone to find, lying at `position` (content calls this).
-- Returns the model, or nil for an id that is not a plan.
function BlueprintService.Spawn(position: Vector3, id: string): Model?
	if not BlueprintBook.IsPlan(id) then
		return nil
	end
	return layDown(position, { uid = "world-" .. Util.guid(), id = id }, nil)
end

function BlueprintService.Drop(player: Player, uid: unknown)
	if type(uid) ~= "string" or not RateLimiter.Allow(player, "DropBlueprint") then
		return
	end
	local profile = profileOf(player)
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not profile or not root then
		return
	end
	local item = BlueprintBook.FindItem(profile.blueprintItems, uid)
	local tool = findPlanTool(player, uid)
	if not item or not tool or dropped[uid] then
		return
	end
	local mine = 0
	for _, d in pairs(dropped) do
		if d.owner == player then
			mine += 1
		end
	end
	if mine >= BlueprintService.MaxDropped then
		notify(player, string.format("You already have %d blueprints lying around. Pick some up first.", mine))
		return
	end
	tool:Destroy()
	local spot = (root.CFrame * CFrame.new(0, 0, -3)).Position
	layDown(spot, item, player)
end

-- The player's world plans go when they leave (or swap slots). They are
-- still in the save, so they are back in the pack next session.
function BlueprintService.PlayerRemoving(player: Player)
	for uid, d in pairs(dropped) do
		if d.owner == player then
			removeDropped(uid)
		end
	end
end

-- How many of this player's plans lie in the world (for tests and the pack).
function BlueprintService.DroppedCount(player: Player): number
	local n = 0
	for _, d in pairs(dropped) do
		if d.owner == player then
			n += 1
		end
	end
	return n
end

-- `notifyFn` shows a toast to one player (GameServer's notify).
function BlueprintService.Init(notifyFn: (Player, string) -> (), remotes: { [string]: RemoteEvent }?)
	notify = notifyFn
	local r = remotes
	if r then
		if r.UseBlueprint then
			r.UseBlueprint.OnServerEvent:Connect(BlueprintService.Use)
		end
		if r.DropBlueprint then
			r.DropBlueprint.OnServerEvent:Connect(BlueprintService.Drop)
		end
	end
end

return BlueprintService
