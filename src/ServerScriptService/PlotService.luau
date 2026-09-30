--!strict
-- PlotService: plots and building on them (data in Shared/PlotData, rules
-- in Shared/PlotLogic, GAME_DESIGN §9).
--   * Builds the plot district: one pad and signpost per PlotData slot.
--   * A new player claims a free plot at its sign ("Claim this plot"). From
--     then on, each time they join they get a free slot and their saved
--     layout (profile.plot) is rebuilt there. Leaving frees the slot.
--   * PlaceBlueprint(blueprintId, x, z, rot): on your own plot, PlotLogic
--     checks it, EconomyService takes the price, the item is built and saved.
--     You pay when you place (the client's ghost preview is free).
--   * MoveBlueprint(uid, x, z, rot): the same checks, free.
--   * SellPlaced(uid): pays back PlotData.SellBack of the price, or all of
--     it within UNDO_SECONDS of placing it (a misclick shouldn't cost you).
--   * UpgradePlot(): the next base tier, for its price; the plot grows.
-- Positions are plot-local studs (PlotData), so a layout rebuilds on
-- whichever slot you get. Each player's slot index and tier are on their
-- PlotSlot and PlotTier attributes; plot models carry OwnerId, OwnerName
-- and Tier; placed items (tag "PlacedItem") carry OwnerId, Uid,
-- BlueprintId, X, Z and Rot, so the client can preview and add prompts.

local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlueprintModels = require(ReplicatedStorage.Shared.BlueprintModels)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

type Profile = ProfileService.Profile

local PlotService = {}

local BUILD_REACH = 40 -- studs past your plot's edge you can still build from
local UNDO_SECONDS = 60 -- selling something this soon after placing it refunds it all
PlotService.UndoSeconds = UNDO_SECONDS

type Slot = {
	index: number,
	cframe: CFrame, -- the plot's centre on the ground
	model: Model,
	pad: Part,
	post: Part,
	board: Part,
	border: Folder,
	items: Folder,
	signLabel: TextLabel,
	claim: ProximityPrompt,
	owner: Player?,
}

local slots: { Slot } = {}
local slotOf: { [Player]: Slot } = {}
local placedAt: { [string]: number } = {} -- uid -> os.clock() when placed this session
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

---------------------------------------------------------------------------
-- The district
---------------------------------------------------------------------------

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Pad, rails and sign for the plot's current size. The sign stands just
-- outside the north edge, facing the road.
local function drawBounds(slot: Slot, size: number, claimed: boolean)
	slot.pad.Size = Vector3.new(size, 0.2, size)
	slot.pad.Transparency = if claimed then 0 else 0.6
	local signAt = slot.cframe * CFrame.new(0, 0, size / 2 + 3)
	slot.post.CFrame = signAt * CFrame.new(0, 3, 0)
	slot.board.CFrame = signAt * CFrame.new(0, 6.5, 0)
	slot.border:ClearAllChildren()
	if not claimed then
		return
	end
	local half = size / 2
	local rail = Color3.fromRGB(130, 90, 50)
	for _, side in ipairs({
		{ 0, half, size, 0.4 },
		{ 0, -half, size, 0.4 },
		{ half, 0, 0.4, size },
		{ -half, 0, 0.4, size },
	}) do
		local x, z, w, d = side[1], side[2], side[3], side[4]
		local fence = part(
			"Rail",
			Vector3.new(w, 0.4, d),
			slot.cframe * CFrame.new(x, 1.5, z),
			rail,
			Enum.Material.Wood,
			slot.border
		)
		fence.CanCollide = false -- a marker, not a wall
	end
end

local function refreshSign(slot: Slot)
	local owner = slot.owner
	if owner then
		local profile = ProfileService.GetProfile(owner)
		local tier = if profile then PlotData.Tier(profile.plot.tier) else nil
		slot.signLabel.Text =
			string.format("%s'S\n%s", string.upper(owner.DisplayName), string.upper(if tier then tier.name else "PLOT"))
	else
		slot.signLabel.Text = "FREE PLOT\nClaim it here"
	end
	slot.claim.Enabled = owner == nil
end

local function buildSlot(index: number, center: Vector2, parent: Instance, onClaim: (Player, Slot) -> ()): Slot
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("Index", index)
	model.Parent = parent
	local cframe = CFrame.new(center.X, 0, center.Y)
	local pad = part(
		"Pad",
		Vector3.new(120, 0.2, 120),
		cframe * CFrame.new(0, 0.1, 0),
		Color3.fromRGB(210, 190, 150),
		Enum.Material.Sand,
		model
	)
	pad.CanCollide = false -- paint on the ground
	pad.CanQuery = false
	model.PrimaryPart = pad
	local border = Instance.new("Folder")
	border.Name = "Border"
	border.Parent = model
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model

	-- The signpost (drawBounds puts it at the north edge).
	local post =
		part("SignPost", Vector3.new(0.6, 6, 0.6), cframe, Color3.fromRGB(70, 45, 22), Enum.Material.Wood, model)
	post.CanCollide = false
	local board = part("Sign", Vector3.new(8, 3.5, 0.4), cframe, Color3.fromRGB(101, 67, 33), Enum.Material.Wood, model)
	board.CanCollide = false
	local label: TextLabel? = nil
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.PixelsPerStud = 40
		sg.Parent = board
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Fantasy
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(245, 235, 215)
		l.Parent = sg
		label = l
	end
	local claim = Instance.new("ProximityPrompt")
	claim.ActionText = "Claim this plot"
	claim.ObjectText = "Free plot"
	claim.MaxActivationDistance = 10
	claim.HoldDuration = 0.5
	claim.RequiresLineOfSight = false
	claim.Parent = board

	local slot: Slot = {
		index = index,
		cframe = cframe,
		model = model,
		pad = pad,
		post = post,
		board = board,
		border = border,
		items = items,
		signLabel = label :: TextLabel,
		claim = claim,
		owner = nil,
	}
	claim.Triggered:Connect(function(player: Player)
		onClaim(player, slot)
	end)
	drawBounds(slot, PlotData.Tiers[1].size, false)
	refreshSign(slot)
	return slot
end

---------------------------------------------------------------------------
-- Owning a plot
---------------------------------------------------------------------------

local function placeModel(slot: Slot, model: Model, item: PlotLogic.Placed)
	BlueprintModels.Place(model, slot.cframe, item.x, item.z, item.rot)
	model:SetAttribute("X", item.x)
	model:SetAttribute("Z", item.z)
	model:SetAttribute("Rot", item.rot)
end

local function buildItem(slot: Slot, owner: Player, item: PlotLogic.Placed)
	local bp = PlotData.Blueprint(item.blueprintId)
	if not bp then
		return
	end
	local model = BlueprintModels.Build(bp, false)
	model.Name = item.uid
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("OwnerId", owner.UserId)
	model:SetAttribute("Uid", item.uid)
	model:SetAttribute("BlueprintId", item.blueprintId)
	placeModel(slot, model, item)
	CollectionService:AddTag(model, "PlacedItem")
	model.Parent = slot.items
end

local function assign(player: Player, slot: Slot, profile: Profile)
	slot.owner = player
	slotOf[player] = slot
	slot.model:SetAttribute("OwnerId", player.UserId)
	slot.model:SetAttribute("OwnerName", player.DisplayName)
	slot.model:SetAttribute("Tier", profile.plot.tier)
	player:SetAttribute("PlotSlot", slot.index)
	player:SetAttribute("PlotTier", profile.plot.tier)
	local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
	drawBounds(slot, tier.size, true)
	for _, item in ipairs(profile.plot.placed) do
		buildItem(slot, player, item)
	end
	refreshSign(slot)
end

local function release(player: Player)
	local slot = slotOf[player]
	slotOf[player] = nil
	if not slot then
		return
	end
	for _, model in ipairs(slot.items:GetChildren()) do
		placedAt[model.Name] = nil
	end
	slot.owner = nil
	slot.items:ClearAllChildren()
	slot.model:SetAttribute("OwnerId", nil)
	slot.model:SetAttribute("OwnerName", nil)
	slot.model:SetAttribute("Tier", nil)
	drawBounds(slot, PlotData.Tiers[1].size, false)
	refreshSign(slot)
end

local function freeSlot(): Slot?
	for _, slot in ipairs(slots) do
		if slot.owner == nil then
			return slot
		end
	end
	return nil
end

local function onClaim(player: Player, slot: Slot)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	if slotOf[player] then
		notify(player, "You already have a plot here.")
		return
	end
	if slot.owner then
		return
	end
	profile.plot.claimed = true
	assign(player, slot, profile)
	notify(player, "It's yours! Stand on your plot and press BUILD to start building.")
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "PlotClaimed")
	end)
end

-- The player's slot, if they stand on (or next to) their plot.
local function nearOwnPlot(player: Player, profile: Profile): Slot?
	local slot = slotOf[player]
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not slot or not root then
		return nil
	end
	local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
	local localPos = slot.cframe:PointToObjectSpace(root.Position)
	local reach = tier.size / 2 + BUILD_REACH
	return if math.abs(localPos.X) <= reach and math.abs(localPos.Z) <= reach then slot else nil
end

local function findPlaced(profile: Profile, uid: string): (PlotLogic.Placed?, number)
	for i, item in ipairs(profile.plot.placed) do
		if item.uid == uid then
			return item, i
		end
	end
	return nil, 0
end

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value
end

function PlotService.Place(player: Player, blueprintId: unknown, x: unknown, z: unknown, rot: unknown)
	if
		type(blueprintId) ~= "string"
		or not isNumber(x)
		or not isNumber(z)
		or not isNumber(rot)
		or not RateLimiter.Allow(player, "PlaceBlueprint")
	then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local bp = PlotData.Blueprint(blueprintId)
	if not profile or not bp then
		return
	end
	local slot = nearOwnPlot(player, profile)
	if not slot then
		notify(player, "Stand on your plot to build.")
		return
	end
	local px, pz = PlotLogic.Snap(x :: number), PlotLogic.Snap(z :: number)
	local ok, why = PlotLogic.Check(bp, px, pz, rot :: number, profile.plot.tier, profile.plot.placed)
	if not ok then
		if why ~= "bad" then -- only a tampered client sends nonsense
			notify(player, (why or "Can't build there") .. ".")
		end
		return
	end
	if profile.cash < bp.priceCash then
		notify(
			player,
			string.format("You need %s more for the %s.", Util.formatCash(bp.priceCash - profile.cash), bp.displayName)
		)
		return
	end
	if bp.priceCash > 0 and not EconomyService.SpendCash(player, bp.priceCash, "placed " .. bp.displayName, bp.id) then
		return
	end
	local item: PlotLogic.Placed = { uid = Util.guid(), blueprintId = bp.id, x = px, z = pz, rot = rot :: number }
	table.insert(profile.plot.placed, item)
	placedAt[item.uid] = os.clock()
	buildItem(slot, player, item)
end

function PlotService.Move(player: Player, uid: unknown, x: unknown, z: unknown, rot: unknown)
	if
		type(uid) ~= "string"
		or not isNumber(x)
		or not isNumber(z)
		or not isNumber(rot)
		or not RateLimiter.Allow(player, "MoveBlueprint")
	then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local slot = if profile then nearOwnPlot(player, profile) else nil
	if not profile or not slot then
		return
	end
	local item = findPlaced(profile, uid :: string)
	local bp = if item then PlotData.Blueprint(item.blueprintId) else nil
	if not item or not bp then
		return
	end
	local px, pz = PlotLogic.Snap(x :: number), PlotLogic.Snap(z :: number)
	local ok, why = PlotLogic.Check(bp, px, pz, rot :: number, profile.plot.tier, profile.plot.placed, item.uid)
	if not ok then
		if why ~= "bad" then
			notify(player, (why or "Can't move it there") .. ".")
		end
		return
	end
	item.x, item.z, item.rot = px, pz, rot :: number
	local model = slot.items:FindFirstChild(item.uid)
	if model and model:IsA("Model") then
		placeModel(slot, model, item)
	end
end

-- What selling `item` pays back right now.
local function sellValue(item: PlotLogic.Placed, bp: PlotData.Blueprint): number
	local at = placedAt[item.uid]
	if at and os.clock() - at <= UNDO_SECONDS then
		return bp.priceCash
	end
	return PlotLogic.SellValue(bp)
end

function PlotService.Sell(player: Player, uid: unknown)
	if type(uid) ~= "string" or not RateLimiter.Allow(player, "SellPlaced") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local slot = if profile then nearOwnPlot(player, profile) else nil
	if not profile or not slot then
		return
	end
	local item, index = findPlaced(profile, uid)
	local bp = if item then PlotData.Blueprint(item.blueprintId) else nil
	if not item or not bp then
		return
	end
	local refund = sellValue(item, bp)
	if refund > 0 and profile.cash + refund > GameConfig.CashCap then
		notify(player, "Your wallet is too full to sell that. Spend some first.")
		return
	end
	table.remove(profile.plot.placed, index)
	placedAt[item.uid] = nil
	local model = slot.items:FindFirstChild(item.uid)
	if model then
		model:Destroy()
	end
	if refund > 0 then
		EconomyService.Refund(player, refund, "sold " .. bp.displayName, bp.id)
	end
	notify(
		player,
		if refund == bp.priceCash
			then string.format("Took back the %s: %s refunded.", bp.displayName, Util.formatCash(refund))
			else string.format("Sold the %s for %s.", bp.displayName, Util.formatCash(refund))
	)
end

function PlotService.Upgrade(player: Player)
	if not RateLimiter.Allow(player, "UpgradePlot") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local slot = slotOf[player]
	if not profile or not slot then
		return
	end
	local nextTier = PlotData.Tier(profile.plot.tier + 1)
	if not nextTier then
		notify(player, "Your plot is as big as it gets.")
		return
	end
	if profile.cash < nextTier.priceCash then
		notify(
			player,
			string.format(
				"You need %s more for a %s.",
				Util.formatCash(nextTier.priceCash - profile.cash),
				nextTier.name
			)
		)
		return
	end
	if not EconomyService.SpendCash(player, nextTier.priceCash, "plot tier " .. nextTier.name, "PlotTier") then
		return
	end
	profile.plot.tier += 1
	slot.model:SetAttribute("Tier", profile.plot.tier)
	player:SetAttribute("PlotTier", profile.plot.tier)
	drawBounds(slot, nextTier.size, true)
	refreshSign(slot)
	notify(player, string.format("Your plot is now a %s (%d × %d)!", nextTier.name, nextTier.size, nextTier.size))
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "PlotTier", profile.plot.tier)
	end)
end

-- Call once the save has loaded: a player who has claimed a plot gets one.
function PlotService.PlayerJoined(player: Player, profile: Profile)
	if not profile.plot.claimed then
		return
	end
	local slot = freeSlot()
	if not slot then
		warn("[PlotService] No free plot for " .. player.Name .. "; add slots in PlotData")
		return
	end
	assign(player, slot, profile)
	notify(player, "Your plot is ready in the plot district, south-east of town.")
end

function PlotService.PlayerRemoving(player: Player)
	release(player)
end

-- `map` is TimberlineMap; the remotes are PlaceBlueprint, MoveBlueprint,
-- SellPlaced and UpgradePlot.
function PlotService.Init(map: Instance, remotes: { [string]: RemoteEvent }, notifyFn: (Player, string) -> ())
	notify = notifyFn
	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = map
	for i, center in ipairs(PlotData.Slots) do
		table.insert(slots, buildSlot(i, center, folder, onClaim))
	end
	remotes.PlaceBlueprint.OnServerEvent:Connect(PlotService.Place)
	remotes.MoveBlueprint.OnServerEvent:Connect(PlotService.Move)
	remotes.SellPlaced.OnServerEvent:Connect(PlotService.Sell)
	remotes.UpgradePlot.OnServerEvent:Connect(PlotService.Upgrade)
end

return PlotService
