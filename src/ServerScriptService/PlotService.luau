--!strict
-- PlotService: plots and building on them (data in Shared/PlotData, rules
-- in Shared/PlotLogic, GAME_DESIGN §9).
--   * Builds the plot district: one pad and signpost per PlotData slot.
--   * Nobody is given a plot. A new player buys the first at the Land
--     Office (a counter in town, next to the plot district's sign): its
--     prompt opens the picker with the price, ClaimPlot names a pad, and
--     the server takes GameConfig.PlotPrice (EconomyService.SpendCash)
--     before it assigns. From then on, each time they join they pick a
--     free pad again (free: the save already owns a plot) and their saved
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
--
-- Streaming (radius 640): the plot shell (pad, sign, claim prompt) is one
-- Atomic model, so the sign never arrives without its prompt. Placed
-- items are their own Atomic models beside that shell. A model that is
-- already Atomic does not keep children added later atomic, and a cabin
-- streaming part by part is how Move/Sell prompts (they need Root) vanish.

local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BlueprintModels = require(ReplicatedStorage.Shared.BlueprintModels)
local ChopSawLogic = require(ReplicatedStorage.Shared.ChopSawLogic)
local EditLogic = require(ReplicatedStorage.Shared.EditLogic)
local FillLogic = require(ReplicatedStorage.Shared.FillLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local PermissionLogic = require(ReplicatedStorage.Shared.PermissionLogic)
local ItemMeshes = require(ReplicatedStorage.Shared.ItemMeshes)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local PlotFill = require(script.Parent.PlotFill)
local PlotDoors = require(script.Parent.PlotDoors)
local LogicService = require(script.Parent.LogicService)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local PlotPickerLogic = require(ReplicatedStorage.Shared.PlotPickerLogic)
local SpotRescue = require(ReplicatedStorage.Shared.SpotRescue)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)

type Profile = ProfileService.Profile

local PlotService = {}

local BUILD_REACH = 40 -- studs past your plot's edge you can still build from
local LAND_OFFICE_RANGE = 12 -- studs from the Land Office counter; its prompt uses the same distance
local UNDO_SECONDS = 60 -- selling something this soon after placing it refunds it all
PlotService.UndoSeconds = UNDO_SECONDS

type Slot = {
	index: number,
	cframe: CFrame, -- the plot's centre on the ground
	placeName: string,
	region: string,
	model: Model,
	pad: Part,
	post: Part,
	board: Part,
	border: Folder,
	items: Folder,
	signLabels: { TextLabel }, -- both faces of the sign
	office: ProximityPrompt, -- Land panel: plot size and expanding onto squares
	spawn: SpawnLocation,
	owner: Player?,
}

local slots: { Slot } = {}
local slotOf: { [Player]: Slot } = {}
local placedAt: { [string]: number } = {} -- uid -> os.clock() when placed this session
-- Last 10 blueprint edits, per player. Memory only: leaving clears it.
local undoStacks: { [Player]: { EditLogic.Entry } } = {}
local pickingUntil: { [Player]: number } = {} -- a returning owner's join picker (a timeout takes a free pad)
local buying: { [Player]: boolean } = {} -- the Land Office picker is open (no timeout: nothing is given away)
local claiming: { [Player]: boolean } = {} -- a claim is being charged and assigned right now
local officePos: Vector3 = Vector3.zero
local lastOffer: { [Player]: PlotPickerLogic.Offer } = {}
local watching: { [Player]: boolean } = {}
local offerRemote: RemoteEvent? = nil
local notify: (Player, string) -> () = function(_player: Player, _message: string) end
-- Fill runs at about 5 Hz, not every Heartbeat. A refusal toasts once, and
-- only for wood this player let go of in the last two seconds.
local FILL_EVERY = 0.2
local FILL_WINDOW = 2
local lastFillAt = -math.huge
-- userId:woodUid -> os.clock() when this player released that piece.
local releasedAt: { [string]: number } = {}
-- userId:blueprintUid:reason -> os.clock() of the last toast.
local fillTold: { [string]: number } = {}

local function fillKey(userId: number, uid: string): string
	return tostring(userId) .. ":" .. uid
end

local function forgetFill(player: Player)
	local prefix = tostring(player.UserId) .. ":"
	local n = #prefix
	for key in pairs(fillTold) do
		if string.sub(key, 1, n) == prefix then
			fillTold[key] = nil
		end
	end
	for key in pairs(releasedAt) do
		if string.sub(key, 1, n) == prefix then
			releasedAt[key] = nil
		end
	end
end

-- GrabService's onRelease. A drop is the only moment a refusal is worth a toast.
function PlotService.NoteRelease(player: Player, piece: any)
	local uid = if type(piece) == "table" then piece.uid else nil
	if type(uid) ~= "string" then
		return
	end
	releasedAt[fillKey(player.UserId, uid)] = os.clock()
end

local function releasedJustNow(player: Player, uid: string, now: number): boolean
	local at = releasedAt[fillKey(player.UserId, uid)]
	return at ~= nil and now - at <= FILL_WINDOW
end

-- `wood` and `logs` only, and only for a piece this player just released.
local function tellFill(player: Player, itemUid: string, why: string, text: string, woodUid: string, now: number)
	if why ~= "wood" and why ~= "logs" then
		return
	end
	if not releasedJustNow(player, woodUid, now) then
		return
	end
	local key = fillKey(player.UserId, itemUid) .. ":" .. why
	local prev = fillTold[key]
	if not prev or now - prev >= FILL_WINDOW then
		fillTold[key] = now
		notify(player, text)
	end
end

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
-- outside the north edge, off to the west, so a driveway up the middle
-- stays clear. Rails and corner posts show even when the plot is free:
-- a faint pad alone was easy to miss, and easy to drive through.
local function drawBounds(slot: Slot, size: number, claimed: boolean, ownedSquares: { string }?)
	local look = PlotData.Look(slot.index)
	slot.pad.Size = Vector3.new(size, 0.2, size)
	slot.pad.Transparency = if claimed then 0 else 0.25
	slot.pad.Color = Color3.fromRGB(look.ground[1], look.ground[2], look.ground[3])
	slot.pad.Material = (Enum.Material :: any)[look.material]
	local signAt = slot.cframe * CFrame.new(-10, 0, size / 2 + 3)
	slot.post.CFrame = signAt * CFrame.new(0, 3, 0)
	slot.board.CFrame = signAt * CFrame.new(0, 6.5, 0)
	-- One mesh for the post and the board, pivot on the ground at the sign.
	-- The board part stays (prompt + both SurfaceGuis) and goes invisible.
	if ItemMeshes.AttachTo(slot.board, "PlotSign", { hostOffset = CFrame.new(0, -6.5, 0) }) then
		slot.post.Transparency = 1
	end
	slot.border:ClearAllChildren()
	local squares = if claimed then ownedSquares else nil
	if squares then
		for _, key in ipairs(squares) do
			local ix, iz = PlotLogic.ParseKey(key)
			if ix and iz and not PlotLogic.SquareInsideTier(ix, iz, size) then
				local x0, x1, z0, z1 = PlotLogic.SquareBox(ix, iz)
				local tile = part(
					"Square",
					Vector3.new(GameConfig.PlotSquare - 1, 0.15, GameConfig.PlotSquare - 1),
					slot.cframe * CFrame.new((x0 + x1) / 2, 0.2, (z0 + z1) / 2),
					Color3.fromRGB(196, 164, 110),
					Enum.Material.Sand,
					slot.border
				)
				tile.CanCollide = false
				tile.CanQuery = false
			end
		end
	end
	local half = size / 2
	local rail = if claimed
		then Color3.fromRGB(look.rail[1], look.rail[2], look.rail[3])
		else Color3.fromRGB(196, 168, 120)
	local postColor = Color3.fromRGB(90, 62, 36)
	for _, side in ipairs({
		{ 0, half, size, 0.4 },
		{ 0, -half, size, 0.4 },
		{ half, 0, 0.4, size },
		{ -half, 0, 0.4, size },
	}) do
		local x, z, w, d = side[1], side[2], side[3], side[4]
		local fence = part(
			"Rail",
			Vector3.new(w, 0.35, d),
			slot.cframe * CFrame.new(x, 0.5, z),
			rail,
			Enum.Material.Wood,
			slot.border
		)
		fence.CanCollide = false -- a marker, not a wall
		local alongZ = d > w
		ItemMeshes.AttachTo(fence, "PlotRail", {
			scaleX = if alongZ then d else w,
			yaw = if alongZ then math.pi / 2 else 0,
			color = rail,
			hostOffset = CFrame.new(0, -0.5, 0),
		})
	end
	for _, corner in ipairs({
		{ half, half },
		{ half, -half },
		{ -half, half },
		{ -half, -half },
	}) do
		local post = part(
			"Corner",
			Vector3.new(0.8, 3.2, 0.8),
			slot.cframe * CFrame.new(corner[1], 1.6, corner[2]),
			postColor,
			Enum.Material.Wood,
			slot.border
		)
		post.CanCollide = false
		ItemMeshes.AttachTo(post, "PlotCorner", { hostOffset = CFrame.new(0, -1.6, 0) })
	end
	-- A short gravel apron off the north edge, toward the lane or the road.
	local apron = part(
		"Apron",
		Vector3.new(16, 0.15, 10),
		slot.cframe * CFrame.new(0, 0.12, half + 5),
		Color3.fromRGB(look.apron[1], look.apron[2], look.apron[3]),
		Enum.Material.Ground,
		slot.border
	)
	apron.CanCollide = false
	apron.CanQuery = false
end

local function refreshSign(slot: Slot)
	local owner = slot.owner
	local text = string.format("%s\nOPEN PLOT", string.upper(slot.placeName))
	if owner then
		local profile = ProfileService.GetProfile(owner)
		local tier = if profile then PlotData.Tier(profile.plot.tier) else nil
		local tierName = string.upper(if tier then tier.name else "CAMPSITE")
		text = string.format("PLOT %d\n%s\n%s", slot.index, tierName, owner.DisplayName)
	end
	for _, label in ipairs(slot.signLabels) do
		label.Text = text
	end
	slot.office.Enabled = owner ~= nil
end

local function buildSlot(index: number, center: Vector2, parent: Instance): Slot
	local home = PlotData.Home(index)
	local placeName = if home then home.name else ("Plot " .. index)
	local region = if home then home.region else ""
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("PlaceName", placeName)
	model:SetAttribute("Region", region)
	-- Before anything is parented into the world: an Atomic model only
	-- streams its initial descendants together.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local ground = TerrainGen.HeightAt(center.X, center.Y)
	local cframe = CFrame.new(center.X, ground, center.Y)
	local pad = part(
		"Pad",
		Vector3.new(PlotData.Tiers[1].size, 0.2, PlotData.Tiers[1].size),
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
	-- Beside the shell, not inside it: items are built when someone claims
	-- or places, after the shell has already streamed to whoever is nearby.
	local items = Instance.new("Folder")
	items.Name = "PlotItems_" .. index
	items.Parent = parent

	-- The signpost (drawBounds puts it at the north edge).
	local post =
		part("SignPost", Vector3.new(0.6, 6, 0.6), cframe, Color3.fromRGB(70, 45, 22), Enum.Material.Wood, model)
	post.CanCollide = false
	local board = part("Sign", Vector3.new(8, 3.5, 0.4), cframe, Color3.fromRGB(101, 67, 33), Enum.Material.Wood, model)
	board.CanCollide = false
	local labels: { TextLabel } = {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud -- the canvas takes the board's shape
		sg.PixelsPerStud = 40
		sg.Parent = board
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Fantasy
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(245, 235, 215)
		l.Text = ""
		l.Parent = sg
		table.insert(labels, l)
	end
	local office = Instance.new("ProximityPrompt")
	office.Name = "LandOffice"
	office.ActionText = "Open Land"
	office.ObjectText = "Your plot"
	office.MaxActivationDistance = 12
	office.HoldDuration = 0
	office.Enabled = false
	InputKit.PromptDefaults(office, "Interact")
	office.Parent = board

	-- Not Neutral: only the player whose RespawnLocation this is wakes up
	-- here. Everyone else still uses the town spawn.
	local plotSpawn = Instance.new("SpawnLocation")
	plotSpawn.Name = "PlotSpawn"
	plotSpawn.Size = Vector3.new(6, 1, 6)
	plotSpawn.Anchored = true
	plotSpawn.Neutral = false
	plotSpawn.Enabled = true
	plotSpawn.Duration = 0
	plotSpawn.CanCollide = false
	plotSpawn.Transparency = 1
	plotSpawn.CFrame = cframe * CFrame.new(0, 2, -18) * CFrame.Angles(0, math.pi, 0)
	plotSpawn.Parent = model

	local slot: Slot = {
		index = index,
		cframe = cframe,
		placeName = placeName,
		region = region,
		model = model,
		pad = pad,
		post = post,
		board = board,
		border = border,
		items = items,
		signLabels = labels,
		office = office,
		spawn = plotSpawn,
		owner = nil,
	}
	drawBounds(slot, PlotData.Tiers[1].size, false)
	refreshSign(slot)
	model.Parent = parent
	return slot
end

---------------------------------------------------------------------------
-- Owning a plot
---------------------------------------------------------------------------

local function placeModel(slot: Slot, model: Model, item: PlotLogic.Placed)
	BlueprintModels.Place(model, slot.cframe, item.x, item.z, item.rot, item.y)
	model:SetAttribute("X", item.x)
	model:SetAttribute("Y", item.y or 0)
	model:SetAttribute("Z", item.z)
	model:SetAttribute("Rot", item.rot)
	model:SetAttribute("Open", false)
end

local function buildItem(slot: Slot, owner: Player, item: PlotLogic.Placed)
	local bp = PlotLogic.Blueprint(item.blueprintId)
	if not bp then
		return
	end
	local model = if SawmillLogic.Blueprint(item.blueprintId)
		then MachineArt.Build(item.blueprintId, false)
		elseif ChopSawLogic.Blueprint(item.blueprintId) then MachineArt.BuildChopSaw(false)
		else BlueprintModels.Build(bp, false)
	if not model then
		return
	end
	model.Name = item.uid
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("OwnerId", owner.UserId)
	model:SetAttribute("Uid", item.uid)
	model:SetAttribute("BlueprintId", item.blueprintId)
	if bp.kit then
		model:SetAttribute("Kit", true)
		if item.fill then
			model:SetAttribute("FillUnits", item.fill.units)
		end
		if item.len then
			model:SetAttribute("Len", item.len)
		end
		if item.lenX then
			model:SetAttribute("LenX", item.lenX)
		end
		if item.lenZ then
			model:SetAttribute("LenZ", item.lenZ)
		end
		local size = (BlueprintModels :: any).ApplySize
		if type(size) == "function" then
			size(model, bp, item.len, item.lenX, item.lenZ)
		end
	end
	local mill = ItemCatalog.GetSawmill(item.blueprintId)
	if mill then
		local saved = item.data
		local settings = SawmillLogic.ClampSettings(
			mill,
			if saved and type(saved.x) == "number" then saved.x else 1,
			if saved and type(saved.y) == "number" then saved.y else 0.6
		)
		item.data = settings
		model:SetAttribute("CutX", settings.x)
		model:SetAttribute("CutY", settings.y)
		MachineArt.SetCut(model, settings.x, settings.y)
	end
	if ChopSawLogic.Blueprint(item.blueprintId) then
		local saved = item.data
		local cut = ChopSawLogic.Clamp(if saved and type(saved.x) == "number" then saved.x else ChopSawLogic.DefaultCut)
		item.data = { x = cut, y = 0 }
		model:SetAttribute("CutU", cut)
		MachineArt.SetLength(model, cut)
	end
	placeModel(slot, model, item)
	if bp.kit then
		local apply = (BlueprintModels :: any).ApplyWood
		local fade = (BlueprintModels :: any).SetFaded
		if type(apply) == "function" then
			apply(model, item.wood)
		end
		if type(fade) == "function" and not PlotLogic.IsBuilt(bp, item) then
			fade(model, true)
		end
	end
	if bp.opens and PlotLogic.IsBuilt(bp, item) and type(model.GetDescendants) == "function" then
		local host: Instance = model
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("Leaf") == true then
				host = d
				break
			end
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = bp.displayName
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		InputKit.PromptDefaults(prompt, "Interact")
		prompt.Parent = host
		prompt.Triggered:Connect(function(who: Player)
			local hostOwner = slot.owner
			if not hostOwner then
				return
			end
			local ownerProfile = ProfileService.GetProfile(hostOwner)
			if not ownerProfile then
				return
			end
			local allowed = who.UserId == hostOwner.UserId
				or PermissionLogic.Allows(ownerProfile.permissions, who.UserId, "interact")
			if not allowed then
				notify(who, "The owner hasn't let you use that.")
				return
			end
			local _, hint = PlotDoors.Toggle(
				who,
				model,
				item,
				ownerProfile.plot.placed,
				slot.cframe,
				slot.items,
				os.clock(),
				allowed
			)
			if hint then
				notify(who, hint)
			end
		end)
	end
	CollectionService:AddTag(model, "PlacedItem")
	model.Parent = slot.items
	-- Switches get their prompts and lamps their light (LogicService).
	LogicService.Attach({
		slot = slot :: any,
		model = model,
		item = item,
		ownerOf = function()
			return owner, ProfileService.GetProfile(owner)
		end,
	})
end

local function mirrorPlot(player: Player, profile: Profile)
	local squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	player:SetAttribute("PlotSquares", table.concat(squares, ";"))
	player:SetAttribute("PlotPermissions", PermissionLogic.Encode(profile.permissions))
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
	local owned = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	drawBounds(slot, tier.size, true, owned)
	mirrorPlot(player, profile)
	for _, item in ipairs(profile.plot.placed) do
		buildItem(slot, player, item)
	end
	LogicService.Restore(slot :: any, profile, player)
	refreshSign(slot)
end

-- Far from the pad (the picker, or a join at town): stand on it. Already
-- at the sign: don't yank them off the prompt. The owner is already set.
-- Streaming and the pivot wait, so the claim itself does not yield.
local function adoptSpawn(player: Player, slot: Slot, moveIfFar: boolean)
	player.RespawnLocation = slot.spawn
	if not moveIfFar then
		return
	end
	local pos = slot.spawn.CFrame.Position
	local function arrive()
		local ask = (player :: any).RequestStreamAroundAsync
		if type(ask) == "function" then
			pcall(function()
				ask(player, pos, 5)
			end)
		end
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		local pivotTo = if char then (char :: any).PivotTo else nil
		if not root or type(pivotTo) ~= "function" then
			return
		end
		local here = root.Position
		local dx, dz = here.X - pos.X, here.Z - pos.Z
		if dx * dx + dz * dz > 80 * 80 then
			pivotTo(char, slot.spawn.CFrame + Vector3.new(0, 3, 0))
		end
	end
	task.spawn(arrive)
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
	player:SetAttribute("PlotSlot", nil)
	player:SetAttribute("PlotTier", nil)
	player:SetAttribute("Picking", nil)
	-- Back to the town's Neutral spawn. The property's type won't take nil.
	local who: any = player
	who.RespawnLocation = nil
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

local function takenFlags(): { boolean }
	local flags: { boolean } = {}
	for index, slot in ipairs(slots) do
		flags[index] = slot.owner ~= nil
	end
	return flags
end

-- A save that already owns a plot picks a pad for free; a new player pays.
local function ownedBefore(profile: Profile?): boolean
	return profile ~= nil and profile.plot ~= nil and profile.plot.claimed == true
end

local function priceFor(profile: Profile?): number
	return PlotPickerLogic.Price(ownedBefore(profile), GameConfig.PlotPrice)
end

local function offerFor(player: Player): PlotPickerLogic.Offer
	local plots: { PlotPickerLogic.OfferPlot } = {}
	for _, slot in ipairs(slots) do
		local owner = slot.owner
		table.insert(plots, {
			index = slot.index,
			name = slot.placeName,
			region = slot.region,
			x = slot.cframe.Position.X,
			z = slot.cframe.Position.Z,
			y = slot.cframe.Position.Y,
			taken = owner ~= nil,
			owner = if owner then owner.DisplayName else "",
		})
	end
	return {
		timeout = PlotPickerLogic.TimeoutSeconds,
		price = priceFor(ProfileService.GetProfile(player)),
		plots = plots,
	}
end

local function fireOffer(player: Player, notice: string?)
	local payload = offerFor(player)
	payload.notice = notice
	lastOffer[player] = payload
	local remote = offerRemote
	if remote and remote.FireClient then
		remote:FireClient(player, payload)
	end
end

local function refreshPickers()
	for player in pairs(pickingUntil) do
		fireOffer(player)
	end
	for player in pairs(buying) do
		fireOffer(player)
	end
end

-- A saved world spot that the new ground swallowed, drowned, or built a
-- pad on, moved onto this player's plot (`rescue` is where). Memory only: no yield.
local function rescueProfile(profile: Profile, rescue: CFrame)
	local function land(x: number, y: number, z: number): (number, number, number)
		local move = SpotRescue.ShouldMove(
			y,
			TerrainGen.HeightAt(x, z),
			TerrainGen.WaterLevelAt(x, z) ~= nil,
			WorldLayout.OnPlotPad(x, z)
		)
		if not move then
			return x, y, z
		end
		local p = rescue.Position
		return p.X, p.Y + 2, p.Z
	end
	local truck = profile.truckAt
	if
		type(truck) == "table"
		and type(truck.x) == "number"
		and type(truck.y) == "number"
		and type(truck.z) == "number"
	then
		truck.x, truck.y, truck.z = land(truck.x :: number, truck.y :: number, truck.z :: number)
	end
	if type(profile.leftLoad) == "table" then
		for _, log in ipairs(profile.leftLoad) do
			log.x, log.y, log.z = land(log.x, log.y, log.z)
		end
	end
	if type(profile.groundLoad) ~= "table" then
		return
	end
	for _, piece in ipairs(profile.groundLoad) do
		if type(piece) == "table" then
			local g = (piece :: any).g
			if type(g) == "table" and type(g[1]) == "number" and type(g[2]) == "number" and type(g[3]) == "number" then
				g[1], g[2], g[3] = land(g[1], g[2], g[3])
			end
		end
	end
end

local function grant(player: Player, slot: Slot, profile: Profile, moveIfFar: boolean, told: string)
	pickingUntil[player] = nil
	buying[player] = nil
	lastOffer[player] = nil
	player:SetAttribute("Picking", nil)
	local first = profile.plot.claimed ~= true
	profile.plot.claimed = true
	-- Owner is set here, before any quest, analytics, or save work.
	assign(player, slot, profile)
	adoptSpawn(player, slot, moveIfFar)
	rescueProfile(profile, slot.cframe * CFrame.new(0, 2, 0))
	if first then
		QuestService.Event(player, "plotClaimed")
		MilestoneService.Mark(player, "Claimed a plot")
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "PlotClaimed")
		end)
	end
	notify(player, told)
	refreshPickers()
end

local FULL = "This server's plot district is full, so your plot isn't out today. Try another server!"
local TOLD_PICKER = "It's yours! This pad is your spawn. Press BUILD to start building."

-- The Land Office counter: the player has to be standing at it.
local function nearOffice(player: Player): boolean
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not root then
		return false
	end
	return (root.Position - officePos).Magnitude <= LAND_OFFICE_RANGE + GameConfig.RangeTolerance
end

-- The server's decision on one ClaimPlot. A new player pays GameConfig.PlotPrice
-- (EconomyService.SpendCash) and only then gets the pad; the check, the
-- charge and the assign share one breath, and `claiming` keeps a second
-- fire from this player out until the first has finished, so one claim is
-- one charge. A save that already owned a plot picks a pad for free from
-- its join picker (pickingUntil), with no range check.
local function tryClaim(player: Player, index: number): boolean
	if claiming[player] then
		return false
	end
	local profile = ProfileService.GetProfile(player)
	local slot = slots[index]
	if not profile or not profile.plot or not slot then
		return false
	end
	local returning = ownedBefore(profile)
	local price = priceFor(profile)
	local inRange = (returning and pickingUntil[player] ~= nil) or nearOffice(player)
	local cash = if price > 0 then EconomyService.GetCash(player) else 0
	local verdict, short = PlotPickerLogic.Decide(slotOf[player] ~= nil, inRange, slot.owner ~= nil, price, cash)
	if verdict == "owned" then
		notify(player, "You already have a plot here.")
		return false
	elseif verdict == "range" then
		notify(player, "Walk up to the Land Office in town to buy a plot.")
		return false
	elseif verdict == "taken" then
		notify(player, "Someone else claimed that plot. Pick another.")
		if pickingUntil[player] or buying[player] then
			fireOffer(player, "taken")
		end
		return false
	elseif verdict == "cash" then
		notify(player, PlotPickerLogic.ShortText(short))
		return false
	end
	claiming[player] = true
	slot.owner = player -- reserved: nobody else can take this pad while we charge
	if price > 0 and not EconomyService.SpendCash(player, price, "bought a plot", "PlotPurchase") then
		slot.owner = nil
		claiming[player] = nil
		notify(player, PlotPickerLogic.ShortText(math.max(1, price - EconomyService.GetCash(player))))
		return false
	end
	local ok, err: any = (pcall :: any)(grant, player, slot, profile, true, TOLD_PICKER)
	claiming[player] = nil
	if not ok then
		-- The plot did not build: undo the pad and give the money back.
		release(player)
		slot.owner = nil
		if price > 0 then
			EconomyService.Refund(player, price, "plot purchase failed", "PlotPurchase")
		end
		error(err)
	end
	return true
end

-- A returning owner's join picker timed out, or they asked for any pad:
-- the first free one, no charge. Anyone else gets nothing here.
local function autoAssign(player: Player)
	if slotOf[player] then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or not ownedBefore(profile) then
		return
	end
	pickingUntil[player] = nil
	local index = PlotPickerLogic.FirstFree(takenFlags())
	if not index then
		player:SetAttribute("Picking", nil)
		warn("[PlotService] No free plot for " .. player.Name .. "; add slots in PlotData")
		notify(player, FULL)
		return
	end
	if claiming[player] then
		return
	end
	claiming[player] = true
	local slot = slots[index]
	slot.owner = player
	local ok, err: any = (pcall :: any)(grant, player, slot, profile, true, TOLD_PICKER)
	claiming[player] = nil
	if not ok then
		error(err)
	end
end

-- The Land Office prompt: opens the picker with the price. Nothing is
-- charged or assigned here.
local function onOfficeOpened(player: Player)
	if slotOf[player] then
		notify(player, "You already have a plot. Plots are bought here, one each.")
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or not profile.plot then
		return
	end
	if not nearOffice(player) then
		notify(player, "Walk up to the Land Office counter to buy a plot.")
		return
	end
	if not freeSlot() then
		notify(player, FULL)
		return
	end
	buying[player] = true
	pickingUntil[player] = nil -- no timer: this picker waits for you
	player:SetAttribute("Picking", true)
	fireOffer(player)
end

local function actorOn(player: Player, slot: Slot, profile: Profile): boolean
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not root then
		return false
	end
	local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
	local squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	local reach = PlotLogic.Extent(tier.size, squares) / 2 + BUILD_REACH
	local localPos = slot.cframe:PointToObjectSpace(root.Position)
	return math.abs(localPos.X) <= reach and math.abs(localPos.Z) <= reach
end

-- The player's slot, if they stand on (or next to) their plot.
local function nearOwnPlot(player: Player, profile: Profile): Slot?
	local slot = slotOf[player]
	if not slot or not actorOn(player, slot, profile) then
		return nil
	end
	return slot
end

-- (slot, host profile, host owner, denied). Denied means they are standing
-- on someone else's yard without `flag`.
local function hostFor(player: Player, flag: string): (Slot?, Profile?, Player?, boolean)
	local mine = slotOf[player]
	local mineProfile = ProfileService.GetProfile(player)
	if mine and mineProfile and actorOn(player, mine, mineProfile) then
		return mine, mineProfile, player, false
	end
	local denied = false
	for _, slot in ipairs(slots) do
		local owner = slot.owner
		if owner and owner ~= player then
			local profile = ProfileService.GetProfile(owner)
			if profile and actorOn(player, slot, profile) then
				if PermissionLogic.Allows(profile.permissions, player.UserId, flag) then
					return slot, profile, owner, false
				end
				denied = true
			end
		end
	end
	return nil, nil, nil, denied
end

local function onlinePlayers(): { Player }
	local ok, service = pcall(function()
		return game:GetService("Players")
	end)
	if not ok or service == nil or type(service.GetPlayers) ~= "function" then
		return {}
	end
	return service:GetPlayers()
end

-- B15: the ground at a plot-local spot, found with a raycast that skips
-- the visitor and anything you can walk through (decor), so the hit is
-- the terrain or a floor. The spot is bad on a road (the town's
-- layout) or in the water (the lake and river layout, or a water
-- terrain hit). groundY is where the ray landed, so the visitor is put
-- on the ground and not inside a hill. `noRoofs` also calls a spot bad
-- when the ray lands on a placed piece (a visit never lands on a roof).
local function groundProbe(
	slot: Slot,
	char: Instance,
	noRoofs: boolean
): ((number, number) -> boolean, (number, number) -> CFrame)
	local groundY: { [string]: number } = {}
	local function spotBad(lx: number, lz: number): boolean
		local world = (slot.cframe * CFrame.new(lx, 0, lz)).Position
		local materialName = ""
		local onPiece = false
		local ok, hit = pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }
			params.RespectCanCollide = true
			return workspace:Raycast(Vector3.new(world.X, world.Y + 60, world.Z), Vector3.new(0, -120, 0), params)
		end)
		if ok and typeof(hit) == "RaycastResult" then
			local result = hit :: RaycastResult
			local mat = result.Material
			if mat then
				materialName = mat.Name
			end
			groundY[lx .. "," .. lz] = result.Position.Y
			local inst = result.Instance
			onPiece = noRoofs and inst:IsDescendantOf(slot.items)
		end
		local wet = PlotLogic.InWater(world.X, world.Z) or materialName == "Water"
		return PlotLogic.GroundBad(wet, PlotLogic.OnRoad(world.X, world.Z)) or onPiece
	end
	local function cframeAt(lx: number, lz: number): CFrame
		local ground = groundY[lx .. "," .. lz]
		local lift = if ground then ground - slot.cframe.Position.Y + 4 else 4
		return slot.cframe * CFrame.new(lx, math.max(lift, 4), lz)
	end
	return spotBad, cframeAt
end

local function rootOf(player: Player): (Instance?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil, nil
	end
	local humanoid = if type((char :: any).FindFirstChildOfClass) == "function"
		then (char :: any):FindFirstChildOfClass("Humanoid")
		else nil
	if humanoid and humanoid.SeatPart ~= nil then
		humanoid.Sit = false
	end
	return char, root
end

local function nudgeOff(visitor: Player, slot: Slot, profile: Profile)
	local char, root = rootOf(visitor)
	if not char or not root then
		return
	end
	local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
	local squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	local spotBad, cframeAt = groundProbe(slot, char, false)
	local lx, lz = PlotLogic.EjectSpot(tier.size, squares, spotBad)
	local cf = cframeAt(lx, lz)
	root.CFrame = cf
	root.Position = cf.Position
end

-- A visit: `visitor` asked to go to `ownerId`'s plot. The server checks it
-- all again (the Settings list is only a convenience): the owner is in
-- the server with a plot, is not the visitor, and their visit flag lets
-- this player in. The landing is a raycast-checked spot on the plot, never
-- water, a road or a roof. No cash is involved.
function PlotService.Visit(visitor: Player, ownerIdRaw: unknown): boolean
	if not RateLimiter.Allow(visitor, "VisitPlot") then
		return false
	end
	local ownerId = PermissionLogic.VisitTarget(ownerIdRaw)
	if not ownerId then
		return false
	end
	local owner: Player? = nil
	for _, other in ipairs(onlinePlayers()) do
		if other.UserId == ownerId then
			owner = other
		end
	end
	local slot = if owner then slotOf[owner] else nil
	local profile = if owner then ProfileService.GetProfile(owner) else nil
	if not owner or not slot or not profile then
		notify(visitor, "That player has no plot to visit right now.")
		return false
	end
	if owner == visitor then
		return false
	end
	if not PermissionLogic.CanVisit(profile.permissions, visitor.UserId, owner.UserId) then
		notify(visitor, "That plot isn't open to visitors.")
		return false
	end
	local char, root = rootOf(visitor)
	if not char or not root then
		return false
	end
	local humanoid = if type((char :: any).FindFirstChildOfClass) == "function"
		then (char :: any):FindFirstChildOfClass("Humanoid")
		else nil
	if humanoid and humanoid.Health <= 0 then
		return false
	end
	local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
	local spotBad, cframeAt = groundProbe(slot, char, true)
	local lx, lz = PlotLogic.VisitSpot(tier.size, spotBad)
	local cf = cframeAt(lx, lz)
	root.CFrame = cf
	root.Position = cf.Position
	notify(visitor, string.format("Visiting %s's plot.", owner.DisplayName))
	return true
end

local lastVisitAt = -math.huge
local VISIT_EVERY = 0.5
-- One expand at a time per player. A second tap while the first is in
-- flight does not spend, and a tap that still quotes the old square count
-- does not spend either.
local expanding: { [Player]: boolean } = {}

-- Visitors with visit off are set down just north of the yard.
function PlotService.VisitStep(list: { Player }?)
	local now = os.clock()
	if list == nil then
		if now - lastVisitAt < VISIT_EVERY then
			return
		end
		lastVisitAt = now
	end
	local everyone: { Player } = if list ~= nil then list else onlinePlayers()
	for _, slot in ipairs(slots) do
		local owner = slot.owner
		if owner then
			local profile = ProfileService.GetProfile(owner)
			if profile then
				for _, visitor in ipairs(everyone) do
					if
						visitor ~= owner
						and PermissionLogic.MustLeave(profile.permissions, visitor.UserId, owner.UserId)
					then
						if actorOn(visitor, slot, profile) then
							nudgeOff(visitor, slot, profile)
						end
					end
				end
			end
		end
	end
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
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function PlotService.Place(player: Player, blueprintId: unknown, x: unknown, z: unknown, rot: unknown, y: unknown)
	if
		type(blueprintId) ~= "string"
		or not isNumber(x)
		or not isNumber(z)
		or not isNumber(rot)
		or not RateLimiter.Allow(player, "PlaceBlueprint")
	then
		return
	end
	local bp = PlotLogic.Blueprint(blueprintId)
	if not bp then
		return
	end
	local slot, profile, owner, denied = hostFor(player, "build")
	if not slot or not profile or not owner then
		notify(player, if denied then "You can't build on this plot." else "Stand on your plot to build.")
		return
	end
	local payer = if player == owner then profile else ProfileService.GetProfile(player)
	if not payer then
		return
	end
	local px, pz = PlotLogic.Snap(x :: number), PlotLogic.Snap(z :: number)
	local py = if isNumber(y) then PlotLogic.SnapY(y :: number) else 0
	local squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	local ok, why = PlotLogic.Check(bp, px, pz, rot :: number, profile.plot.tier, profile.plot.placed, nil, py, squares)
	if not ok then
		if why ~= "bad" then -- only a tampered client sends nonsense
			notify(player, (why or "Can't build there") .. ".")
		end
		return
	end
	-- A sawmill or the chop saw bought at the Tool Shed is already paid for:
	-- placing takes one out of stock. With boxed shelves on (the default),
	-- that is the only way to get one: the counter sells them, the build
	-- palette does not. Stock is spent only after the cash check, so a
	-- refused place leaves it.
	local stock = if type(payer.sawmillStock) == "table" then payer.sawmillStock else nil
	local fromShop = ItemCatalog.GetSawmill(bp.id) ~= nil or ItemCatalog.GetMachine(bp.id) ~= nil
	local stockAt = if fromShop and stock then table.find(stock, bp.id) else nil
	local fromStock = stockAt ~= nil
	local unlocked = bp.unlock == true
		and type(payer.furnitureBlueprints) == "table"
		and payer.furnitureBlueprints[bp.id] == true
	local source = PlotLogic.Source(bp, if fromStock then 1 else 0, unlocked, ShopLogic.ShelfMenusHidden())
	if source == "store" then
		notify(player, string.format("Buy the %s at the General Store first.", bp.displayName))
		return
	elseif source == "toolShed" then
		notify(player, string.format("Buy the %s at the Tool Shed first.", bp.displayName))
		return
	end
	local price = if source == "place" then 0 else PlotData.Price(bp)
	if payer.cash < price then
		notify(
			player,
			string.format("You need %s more for the %s.", Util.formatCash(price - payer.cash), bp.displayName)
		)
		return
	end
	if price > 0 and not EconomyService.SpendCash(player, price, "placed " .. bp.displayName, bp.id) then
		return
	end
	if fromStock and stock and stockAt then
		table.remove(stock, stockAt)
		player:SetAttribute("SawmillStock", SawmillLogic.EncodeStock(stock))
	end
	local item: PlotLogic.Placed = {
		uid = Util.guid(),
		blueprintId = bp.id,
		x = px,
		z = pz,
		rot = rot :: number,
		y = if py ~= 0 then py else nil,
	}
	if bp.kit then
		item.paid = price
		item.fill = { units = 0 }
	end
	table.insert(profile.plot.placed, item)
	placedAt[item.uid] = os.clock()
	buildItem(slot, owner, item)
	if fromStock then
		notify(player, string.format("Placed your %s.", bp.displayName))
	end
	QuestService.Event(player, "itemPlaced")
end

function PlotService.Move(player: Player, uid: unknown, x: unknown, z: unknown, rot: unknown, y: unknown)
	if
		type(uid) ~= "string"
		or not isNumber(x)
		or not isNumber(z)
		or not isNumber(rot)
		or not RateLimiter.Allow(player, "MoveBlueprint")
	then
		return
	end
	local slot, profile, _owner, denied = hostFor(player, "build")
	if not profile or not slot then
		if denied then
			notify(player, "You can't build on this plot.")
		end
		return
	end
	local item = findPlaced(profile, uid :: string)
	local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
	if not item or not bp then
		return
	end
	if bp.kit and EditLogic.Locked(item) then
		notify(player, EditLogic.Message("filled") or "This piece already has wood in it.")
		return
	end
	local px, pz = PlotLogic.Snap(x :: number), PlotLogic.Snap(z :: number)
	local py = if isNumber(y) then PlotLogic.SnapY(y :: number) else (item.y or 0)
	local squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	local ok, why =
		PlotLogic.Check(bp, px, pz, rot :: number, profile.plot.tier, profile.plot.placed, item.uid, py, squares)
	if not ok then
		if why ~= "bad" then
			notify(player, (why or "Can't move it there") .. ".")
		end
		return
	end
	item.x, item.z, item.rot = px, pz, rot :: number
	item.y = if py ~= 0 then py else nil
	local model = slot.items:FindFirstChild(item.uid)
	if model and model:IsA("Model") then
		placeModel(slot, model, item)
	end
end

-- What selling gives back: cash, plank units, and which wood those planks are.
-- An unlock bought at the store refunds nothing. Within a minute a finished
-- piece (or an empty kit piece) gives the whole fee back.
local function sellPlan(item: PlotLogic.Placed, bp: PlotData.Blueprint): (number, number, string?)
	local plan = PlotLogic.SellPlan(bp, item)
	if plan.planks > 0 then
		return 0, plan.planks, plan.wood
	end
	local at = placedAt[item.uid]
	if at and os.clock() - at <= UNDO_SECONDS then
		if bp.unlock then
			return 0, 0, nil
		end
		if bp.kit then
			return item.paid or PlotData.Price(bp), 0, nil
		end
		return bp.priceCash, 0, nil
	end
	return plan.cash, 0, nil
end

local woodMod: any = nil
local woodTried = false

local function woodModule(): any
	if woodTried then
		return woodMod
	end
	woodTried = true
	local ok, mod = pcall(function()
		return require(script.Parent.WoodService)
	end)
	if ok then
		woodMod = mod
	end
	return woodMod
end

local function givePlanks(player: Player, slot: Slot, item: PlotLogic.Placed, units: number, woodId: string?): boolean
	local wood = woodModule()
	if not wood or type(woodId) ~= "string" or units <= 0 or type(wood.SpawnPlank) ~= "function" then
		return false
	end
	local u = GameConfig.WoodUnit
	local spawned = wood.SpawnPlank({
		woodId = woodId,
		size = Vector3.new(u, math.max(units, 0.05) * u, u),
		cf = slot.cframe * CFrame.new(item.x, (item.y or 0) + 2, item.z),
		ownerId = player.UserId,
	})
	return spawned ~= nil
end

function PlotService.Sell(player: Player, uid: unknown)
	if type(uid) ~= "string" or not RateLimiter.Allow(player, "SellPlaced") then
		return
	end
	local slot, profile, owner, denied = hostFor(player, "destroy")
	if not profile or not slot or not owner then
		if denied then
			notify(player, "You can't take that apart.")
		end
		return
	end
	local item, index = findPlaced(profile, uid)
	local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
	if not item or not bp then
		return
	end
	local refund, planks, woodId = sellPlan(item, bp)
	if refund > 0 and profile.cash + refund > GameConfig.CashCap then
		notify(
			player,
			if owner == player
				then "Your wallet is too full to sell that. Spend some first."
				else "The owner's wallet is too full for that."
		)
		return
	end
	if planks > 0 and not givePlanks(owner, slot, item, planks, woodId) then
		notify(player, "Those planks had nowhere to go. Try again in a moment.")
		return
	end
	table.remove(profile.plot.placed, index)
	placedAt[item.uid] = nil
	local model = slot.items:FindFirstChild(item.uid)
	if model then
		model:Destroy()
	end
	LogicService.Sync(slot :: any, profile, player)
	if refund > 0 then
		EconomyService.Refund(owner, refund, "sold " .. bp.displayName, bp.id)
	end
	local full = if bp.kit then (item.paid or PlotData.Price(bp)) else bp.priceCash
	if bp.unlock then
		full = 0
	end
	local text = if planks > 0
		then string.format("Took apart the %s. The planks are on the ground.", bp.displayName)
		elseif refund == full and refund > 0 then string.format(
			"Took back the %s: %s refunded.",
			bp.displayName,
			Util.formatCash(refund)
		)
		else string.format("Sold the %s for %s.", bp.displayName, Util.formatCash(refund))
	notify(player, text)
end

local function samePiece(a: PlotLogic.Placed, b: PlotLogic.Placed): boolean
	return a.x == b.x
		and a.z == b.z
		and a.rot == b.rot
		and a.y == b.y
		and a.len == b.len
		and a.lenX == b.lenX
		and a.lenZ == b.lenZ
		and a.paid == b.paid
end

local function syncEdits(
	slot: Slot,
	player: Player,
	before: { [string]: PlotLogic.Placed },
	placed: { PlotLogic.Placed }
)
	local now: { [string]: PlotLogic.Placed } = {}
	for _, item in ipairs(placed) do
		now[item.uid] = item
	end
	for uid in pairs(before) do
		if not now[uid] then
			local model = slot.items:FindFirstChild(uid)
			if model then
				model:Destroy()
			end
		end
	end
	for uid, item in pairs(now) do
		local prev = before[uid]
		if not prev then
			buildItem(slot, player, item)
		elseif not samePiece(prev, item) then
			local model = slot.items:FindFirstChild(uid)
			local resized = prev.len ~= item.len or prev.lenX ~= item.lenX or prev.lenZ ~= item.lenZ
			if resized or not (model and model:IsA("Model")) then
				if model then
					model:Destroy()
				end
				buildItem(slot, player, item)
			else
				placeModel(slot, model :: Model, item)
			end
		end
	end
end

-- One remote for an unfilled kit ghost: rotate, move, resize, copy, delete, undo.
function PlotService.Edit(player: Player, request: unknown)
	if type(request) ~= "table" then
		return
	end
	if not RateLimiter.Allow(player, "BlueprintEdit") then
		notify(player, EditLogic.Message("rate") or "Slow down a little.")
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local slot = nearOwnPlot(player, profile)
	if not slot or slot.owner ~= player then
		notify(player, EditLogic.Message("owner") or "That piece isn't on your plot.")
		return
	end
	local stack = undoStacks[player]
	if not stack then
		stack = {}
		undoStacks[player] = stack
	end
	-- Cash can still refuse after the edit succeeds. Undo is the wrong
	-- way back: undoing an undo would touch an older entry. Put the pieces
	-- and the stack back exactly as they were.
	local placedSnap: { PlotLogic.Placed } = {}
	for _, item in ipairs(profile.plot.placed) do
		table.insert(placedSnap, EditLogic.Snapshot(item))
	end
	local stackSnap = table.clone(stack)
	local before: { [string]: PlotLogic.Placed } = {}
	for _, item in ipairs(profile.plot.placed) do
		before[item.uid] = {
			uid = item.uid,
			blueprintId = item.blueprintId,
			x = item.x,
			z = item.z,
			rot = item.rot,
			y = item.y,
			len = item.len,
			lenX = item.lenX,
			lenZ = item.lenZ,
			paid = item.paid,
		}
	end
	local world: EditLogic.World = {
		cash = profile.cash,
		tier = profile.plot.tier,
		ownerId = player.UserId,
		playerId = player.UserId,
		placed = profile.plot.placed,
		undo = stack,
		squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {},
	}
	local cashBefore = profile.cash
	local ok, why = EditLogic.Run(world, request :: { [string]: any }, function()
		return Util.guid()
	end)
	profile.plot.placed = world.placed
	if not ok then
		local text = EditLogic.Message(why)
		if text then
			notify(player, text)
		end
		return
	end
	local function restore()
		profile.plot.placed = placedSnap
		undoStacks[player] = stackSnap
	end
	local delta = world.cash - cashBefore
	if delta > 0 and profile.cash + delta > GameConfig.CashCap then
		restore()
		notify(player, "Your wallet is too full for that. Spend some first.")
		return
	end
	if delta < 0 and not EconomyService.SpendCash(player, -delta, "changed a blueprint", "kit") then
		restore()
		notify(player, EditLogic.Message("cash") or "You don't have enough for that.")
		return
	elseif delta > 0 then
		EconomyService.Refund(player, delta, "changed a blueprint", "kit")
	end
	syncEdits(slot, player, before, profile.plot.placed)
	LogicService.Sync(slot :: any, profile, player)
end

function PlotService.Upgrade(player: Player)
	if not RateLimiter.Allow(player, "UpgradePlot") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local slot = nearOwnPlot(player, profile)
	if not slot then
		notify(player, "Stand on your plot to raise its size.")
		return
	end
	local nextTier = PlotData.Tier(profile.plot.tier + 1)
	if not nextTier then
		notify(player, "Your plot size is already the biggest.")
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
	local grown = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	drawBounds(slot, nextTier.size, true, grown)
	refreshSign(slot)
	notify(
		player,
		string.format("Plot size up: your plot is now a %s (%d × %d)!", nextTier.name, nextTier.size, nextTier.size)
	)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "PlotTier", profile.plot.tier)
	end)
end

-- Buy one plot square (expand). The rate limit lives on the ExpandLand handler.
-- `expected` is how many squares the button was drawn for. Check, spend,
-- then grant, with no yield: a failed spend leaves the plot and the wallet
-- as they were. A second call for that same count buys nothing.
function PlotService.Expand(player: Player, x: unknown, z: unknown, expected: unknown)
	if expanding[player] then
		return
	end
	expanding[player] = true
	local ok, err = pcall(function(): any
		if
			type(x) ~= "number"
			or type(z) ~= "number"
			or x ~= x
			or z ~= z
			or x ~= math.floor(x)
			or z ~= math.floor(z)
		then
			return nil
		end
		if type(expected) ~= "number" or expected ~= expected or expected ~= math.floor(expected) or expected < 0 then
			return nil
		end
		local profile = ProfileService.GetProfile(player)
		if not profile or not profile.plot then
			return nil
		end
		if type(profile.plot.squares) ~= "table" then
			profile.plot.squares = {}
		end
		if #profile.plot.squares ~= expected then
			notify(player, "The price changed. The Land panel shows the new one.")
			return nil
		end
		local slot = nearOwnPlot(player, profile)
		if not slot then
			notify(player, "Stand on your plot to expand it.")
			return nil
		end
		local before = profile.cash
		local bought, why, price = PlotLogic.TryExpand(profile.plot, x, z, {
			cash = function()
				return profile.cash
			end,
			spend = function(amount: number)
				return EconomyService.SpendCash(player, amount, "expanded the plot", "PlotSquare")
			end,
			refund = function(amount: number)
				EconomyService.Refund(player, amount, "plot expansion returned", "PlotSquare")
			end,
		})
		if not bought then
			local message = PlotLogic.ExpansionMessage(why, price)
			if message then
				notify(player, message)
			end
			return nil
		end
		local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
		drawBounds(slot, tier.size, true, profile.plot.squares)
		mirrorPlot(player, profile)
		local paid = price or (before - profile.cash)
		local nextPrice = PlotLogic.ExpansionPrice(#profile.plot.squares)
		if nextPrice then
			notify(
				player,
				string.format(
					"You expanded your plot for %s. The next square is %s.",
					Util.formatCash(paid),
					Util.formatCash(nextPrice)
				)
			)
		else
			notify(player, string.format("You expanded your plot for %s.", Util.formatCash(paid)))
		end
		return nil
	end)
	expanding[player] = nil
	if not ok then
		error(err)
	end
end

-- Call once the save has loaded. A save that already owns a plot gets the
-- free picker (nothing is assigned until they pick, close it, or the timer
-- runs out). A save that never bought one gets nothing: no picker, no
-- plot, until it buys one at the Land Office. A pad they already hold this
-- session (a save-slot swap) is left alone: call Reload.
local function watchSpawn(player: Player)
	if watching[player] then
		return
	end
	local added = (player :: any).CharacterAdded
	if type(added) ~= "table" or type(added.Connect) ~= "function" then
		return
	end
	watching[player] = true
	added:Connect(function()
		local slot = slotOf[player]
		if slot then
			adoptSpawn(player, slot, true)
		end
	end)
end

-- Before the truck and the loose logs spawn. A saved world spot that the
-- new ground swallowed, drowned, or built a pad on goes to the town truck
-- lot. Claiming still moves a bad spot onto that player's plot.
function PlotService.ParkStrays(profile: Profile)
	local lot = WorldLayout.ParkingLot
	local x = (lot.x0 + lot.x1) / 2
	local z = (lot.z0 + lot.z1) / 2
	local y = TerrainGen.HeightAt(x, z) + 2
	rescueProfile(profile, CFrame.new(x, y, z))
end

function PlotService.PlayerJoined(player: Player, profile: Profile)
	watchSpawn(player)
	if profile.plot then
		mirrorPlot(player, profile)
	end
	if slotOf[player] or not PlotPickerLogic.ShouldPick(slotOf[player] ~= nil) then
		return
	end
	buying[player] = nil
	-- Never bought a plot: no free pad. They spawn in town; the Land Office sells one.
	if profile.plot == nil or not ownedBefore(profile) then
		pickingUntil[player] = nil
		player:SetAttribute("Picking", nil)
		return
	end
	-- profile is the save that will load onto whichever pad they pick.
	if not freeSlot() then
		warn("[PlotService] No free plot for " .. player.Name .. "; add slots in PlotData")
		notify(player, FULL)
		player:SetAttribute("Picking", nil)
		return
	end
	pickingUntil[player] = os.clock() + PlotPickerLogic.TimeoutSeconds
	player:SetAttribute("Picking", true)
	fireOffer(player)
end

function PlotService.OfferOf(player: Player): PlotPickerLogic.Offer?
	return lastOffer[player]
end

function PlotService.Claim(player: Player, index: unknown)
	if not RateLimiter.Allow(player, "ClaimPlot") then
		return
	end
	local slotIndex = PlotPickerLogic.ClaimIndex(index, #slots)
	if not slotIndex then
		return
	end
	-- Range and price are checked inside: the client only names a pad.
	tryClaim(player, slotIndex)
end

-- Closes the picker. A returning owner's join picker takes a free pad (as
-- it always did); a Land Office picker just closes, and nothing is given.
function PlotService.Pass(player: Player)
	if not RateLimiter.Allow(player, "PlotPass") then
		return
	end
	if buying[player] then
		buying[player] = nil
		lastOffer[player] = nil
		player:SetAttribute("Picking", nil)
		return
	end
	autoAssign(player)
end

function PlotService.Sweep()
	local now = os.clock()
	for player, deadline in pairs(pickingUntil) do
		if now >= deadline then
			autoAssign(player)
		end
	end
end

-- The same pad, the other save's buildings. Returns false when they
-- haven't picked yet, so the caller can open the picker instead.
function PlotService.Reload(player: Player, profile: Profile): boolean
	local slot = slotOf[player]
	if not slot or not profile.plot then
		return false
	end
	-- Another save that never bought a plot does not inherit this pad.
	if not ownedBefore(profile) then
		release(player)
		return false
	end
	for _, model in ipairs(slot.items:GetChildren()) do
		placedAt[model.Name] = nil
	end
	slot.items:ClearAllChildren()
	slot.model:SetAttribute("Tier", profile.plot.tier)
	player:SetAttribute("PlotTier", profile.plot.tier)
	local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
	local owned = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	drawBounds(slot, tier.size, true, owned)
	mirrorPlot(player, profile)
	for _, item in ipairs(profile.plot.placed) do
		buildItem(slot, player, item)
	end
	LogicService.Restore(slot :: any, profile, player)
	refreshSign(slot)
	rescueProfile(profile, slot.cframe * CFrame.new(0, 2, 0))
	return true
end

function PlotService.PlayerRemoving(player: Player)
	-- Drop the timer first, so a timeout can't assign a pad after they leave.
	pickingUntil[player] = nil
	buying[player] = nil
	claiming[player] = nil
	lastOffer[player] = nil
	watching[player] = nil
	undoStacks[player] = nil
	forgetFill(player)
	expanding[player] = nil
	release(player)
end

local releaseHooked = false

-- Chain GrabService's onRelease so a drop can toast. TruckLoad wraps whatever
-- is installed when it starts, and PlotService.Init runs first.
local function watchReleases()
	if releaseHooked then
		return
	end
	local ok, grab = pcall(function(): any
		return require(script.Parent.GrabService)
	end)
	if not ok or type(grab) ~= "table" or type((grab :: any).Hooks) ~= "table" then
		return
	end
	releaseHooked = true
	local hooks = (grab :: any).Hooks
	local prior = hooks.onRelease
	hooks.onRelease = function(player: Player, piece: any, reason: string)
		PlotService.NoteRelease(player, piece)
		if type(prior) == "function" then
			prior(player, piece, reason)
		end
	end
end

-- The Land Office: a counter in town, beside the plot district's sign (see
-- WorldPlan.Town signs). Its prompt opens the picker; the server charges.
PlotService.LandOfficeAt = Vector2.new(147, 86)

local function buildLandOffice(parent: Instance)
	local at = PlotService.LandOfficeAt
	local ground = TerrainGen.HeightAt(at.X, at.Y)
	officePos = Vector3.new(at.X, ground + 2, at.Y)
	-- Front (-Z) toward the town spawn, like the sign beside it.
	local facing = CFrame.lookAt(Vector3.new(at.X, ground, at.Y), Vector3.new(0, ground, 40))
	local model = Instance.new("Model")
	model.Name = "LandOffice"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local wood = Color3.fromRGB(101, 67, 33)
	local dark = Color3.fromRGB(70, 45, 22)
	local counter =
		part("Counter", Vector3.new(7, 3.4, 2.6), facing * CFrame.new(0, 1.7, 0), wood, Enum.Material.Wood, model)
	model.PrimaryPart = counter
	for _, x in ipairs({ -3.2, 3.2 }) do
		part("Post", Vector3.new(0.6, 8, 0.6), facing * CFrame.new(x, 4, 1.4), dark, Enum.Material.Wood, model)
	end
	part("Roof", Vector3.new(8.4, 0.5, 4.2), facing * CFrame.new(0, 8.2, 0.6), dark, Enum.Material.Wood, model)
	local board =
		part("Sign", Vector3.new(7.4, 2, 0.3), facing * CFrame.new(0, 6.6, -1.5), wood, Enum.Material.Wood, model)
	board.CanCollide = false
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Fantasy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245, 235, 215)
	label.Text = string.format("LAND OFFICE\nPlots $%d", GameConfig.PlotPrice)
	label.Parent = sg
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LandOfficePrompt"
	prompt.ActionText = "Buy a plot"
	prompt.ObjectText = "Land Office"
	prompt.MaxActivationDistance = LAND_OFFICE_RANGE
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.Parent = counter
	prompt.Triggered:Connect(onOfficeOpened)
	model.Parent = parent
end

-- `map` is TimberlineMap; the remotes are PlaceBlueprint, MoveBlueprint,
-- SellPlaced and UpgradePlot.
function PlotService.Init(map: Instance, remotes: { [string]: RemoteEvent }, notifyFn: (Player, string) -> ())
	notify = notifyFn
	LogicService.Bind(hostFor :: any, notifyFn)
	ItemMeshes.LoadAsync()
	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = map
	for i, center in ipairs(PlotData.Slots) do
		table.insert(slots, buildSlot(i, center, folder))
	end
	buildLandOffice(map)
	remotes.PlaceBlueprint.OnServerEvent:Connect(PlotService.Place)
	remotes.MoveBlueprint.OnServerEvent:Connect(PlotService.Move)
	remotes.SellPlaced.OnServerEvent:Connect(PlotService.Sell)
	if remotes.BlueprintEdit then
		remotes.BlueprintEdit.OnServerEvent:Connect(function(player: Player, request: unknown)
			PlotService.Edit(player, request)
		end)
	end
	remotes.UpgradePlot.OnServerEvent:Connect(PlotService.Upgrade)
	if remotes.VisitPlot then
		remotes.VisitPlot.OnServerEvent:Connect(function(player: Player, ownerId: unknown)
			PlotService.Visit(player, ownerId)
		end)
	end
	offerRemote = remotes.PlotOffer
	if remotes.ClaimPlot then
		remotes.ClaimPlot.OnServerEvent:Connect(function(player: Player, index: unknown)
			PlotService.Claim(player, index)
		end)
	end
	if remotes.PlotPass then
		remotes.PlotPass.OnServerEvent:Connect(function(player: Player)
			PlotService.Pass(player)
		end)
	end
	local heartbeat = (RunService :: any).Heartbeat
	if typeof(heartbeat) == "RBXScriptSignal" or (type(heartbeat) == "table" and heartbeat.Connect) then
		heartbeat:Connect(function()
			PlotService.Sweep()
			PlotService.FillStep()
			PlotService.VisitStep()
		end)
	end
	watchReleases()
end

local function woodRoot(piece: any): BasePart?
	local root = piece.root
	if piece.dead == true or typeof(root) ~= "Instance" or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function woodHeld(piece: any): boolean
	local model = piece.model
	if typeof(model) ~= "Instance" then
		return false
	end
	local by = model:GetAttribute("HeldBy")
	return type(by) == "number" and by ~= 0
end

-- Plot square, grown by FillLogic.Reach, in the plot's own axes.
local function onPlot(slot: Slot, size: number, pos: Vector3): boolean
	local half = size / 2 + FillLogic.Reach
	local p = slot.cframe:PointToObjectSpace(pos)
	return math.abs(p.X) <= half and math.abs(p.Z) <= half
end

function PlotService.FillStep()
	local now = os.clock()
	if now - lastFillAt < FILL_EVERY then
		return
	end
	lastFillAt = now
	local wood = woodModule()
	if not wood or type(wood.All) ~= "function" then
		return
	end
	local pieces = wood.All()
	if type(pieces) ~= "table" then
		return
	end
	local api = {
		Get = function(id: string)
			return wood.Get(id)
		end,
		Remove = function(got: any, reason: string)
			wood.Remove(got, reason)
		end,
		SpawnPlank = function(info: any)
			return wood.SpawnPlank(info)
		end,
	}
	for player, slot in pairs(slotOf) do
		local profile = ProfileService.GetProfile(player)
		local placed = if profile and profile.plot then profile.plot.placed else nil
		if profile and placed then
			-- Built pieces keep `fill` set, so IsBuilt is the gate. Anything
			-- already built never reaches the wood.
			local pending: { { item: PlotLogic.Placed, bp: PlotData.Blueprint } } = {}
			for _, item in ipairs(placed) do
				if item.fill then
					local bp = PlotLogic.Blueprint(item.blueprintId)
					if bp and not PlotLogic.IsBuilt(bp, item) then
						table.insert(pending, { item = item, bp = bp })
					end
				end
			end
			if #pending > 0 then
				local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
				local planks: { { piece: any, root: BasePart } } = {}
				local logs: { { piece: any, root: BasePart } } = {}
				for _, piece in pairs(pieces) do
					local root = woodRoot(piece)
					if
						root
						and not woodHeld(piece)
						and piece.ownerId == player.UserId
						and piece.ownerId ~= 0
						and onPlot(
							slot,
							PlotLogic.Extent(
								tier.size,
								if type(profile.plot.squares) == "table" then profile.plot.squares else {}
							),
							root.Position
						)
					then
						if piece.kind == "plank" then
							table.insert(planks, { piece = piece, root = root })
						elseif
							piece.kind == "log"
							and type(piece.uid) == "string"
							and releasedJustNow(player, piece.uid, now)
						then
							-- A log can't fill anything. It only exists here so a
							-- drop onto a blueprint can say to saw it first.
							table.insert(logs, { piece = piece, root = root })
						end
					end
				end
				for _, job in ipairs(pending) do
					local item = job.item
					local bp = job.bp
					local origin = (slot.cframe * CFrame.new(item.x, item.y or 0, item.z)).Position
					for _, near in ipairs(planks) do
						local piece = near.piece
						local root = near.root
						if FillLogic.InRange((root.Position - origin).Magnitude) then
							local changed, why = PlotFill.Apply(item, {
								uid = piece.uid,
								kind = piece.kind,
								woodId = piece.woodId,
								volume = piece.volume,
								ownerId = piece.ownerId,
								held = false,
								size = root.Size,
								cf = root.CFrame,
								figure = piece.figure,
								boost = piece.boost,
								lux = piece.lux,
							}, player.UserId, api)
							if changed then
								local model = slot.items:FindFirstChild(item.uid)
								if model and model:IsA("Model") and type(BlueprintModels.ApplyWood) == "function" then
									BlueprintModels.ApplyWood(model, item.wood)
									BlueprintModels.SetFaded(model, not PlotLogic.IsBuilt(bp, item))
								end
							elseif type(why) == "string" and type(piece.uid) == "string" then
								local woodName = nil
								if type(item.wood) == "string" then
									local def = WoodData.Get(item.wood)
									woodName = if def then def.displayName else item.wood
								end
								local text = FillLogic.Message(why, bp.displayName, woodName)
								if text then
									tellFill(player, item.uid, why, text, piece.uid, now)
								end
							end
						end
					end
					for _, near in ipairs(logs) do
						local piece = near.piece
						if FillLogic.InRange((near.root.Position - origin).Magnitude) then
							local text = FillLogic.Message("logs", bp.displayName, nil)
							if text then
								tellFill(player, item.uid, "logs", text, piece.uid, now)
							end
						end
					end
				end
			end
		end
	end
end

return PlotService
