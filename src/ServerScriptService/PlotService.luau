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

local BaseLogic = require(ReplicatedStorage.Shared.BaseLogic)
local BlueprintBook = require(ReplicatedStorage.Shared.BlueprintBook)
local BuildCost = require(ReplicatedStorage.Shared.BuildCost)
local BlueprintModels = require(ReplicatedStorage.Shared.BlueprintModels)
local AutomationLogic = require(ReplicatedStorage.Shared.AutomationLogic)
local ChopSawLogic = require(ReplicatedStorage.Shared.ChopSawLogic)
local EditLogic = require(ReplicatedStorage.Shared.EditLogic)
local FallenLogic = require(ReplicatedStorage.Shared.FallenLogic)
local FurnitureData = require(ReplicatedStorage.Shared.FurnitureData)
local EditRights = require(script.Parent.EditRights)
local FillLogic = require(ReplicatedStorage.Shared.FillLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HammerLogic = require(ReplicatedStorage.Shared.HammerLogic)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local KitPaint = require(ReplicatedStorage.Shared.KitPaint)
local LooseSave = require(ReplicatedStorage.Shared.LooseSave)
local SlabData = require(ReplicatedStorage.Shared.SlabData)
local PermissionLogic = require(ReplicatedStorage.Shared.PermissionLogic)
local ItemMeshes = require(ReplicatedStorage.Shared.ItemMeshes)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local PlanerLogic = require(ReplicatedStorage.Shared.PlanerLogic)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local PlotFill = require(script.Parent.PlotFill)
local PlotDoors = require(script.Parent.PlotDoors)
local LogicService = require(script.Parent.LogicService)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local SampleBuilds = require(ReplicatedStorage.Shared.SampleBuilds)
local PlotPickerLogic = require(ReplicatedStorage.Shared.PlotPickerLogic)
local PlotPlatform = require(ReplicatedStorage.Shared.PlotPlatform)
local PlotRedraw = require(ReplicatedStorage.Shared.PlotRedraw)
local PlotSalesmanData = require(ReplicatedStorage.Shared.PlotSalesmanData)
local ReadyGates = require(ReplicatedStorage.Shared.ReadyGates)
local SpotRescue = require(ReplicatedStorage.Shared.SpotRescue)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local SkyBinLogic = require(ReplicatedStorage.Shared.SkyBinLogic)
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
-- GameServer sets this: Old Hank's replies as the dialogue box (else a toast).
PlotService.Speak = nil :: ((Player, string) -> ())?
-- GameServer wires the other services in (this file does not require them):
--   commit   pull wood, the truck's load and carried logs into the save (the
--            slot swap's path), run before a base is unloaded;
--   despawn  take the player's truck off the world;
--   clearPads  take a base's vehicle-pad models down (the records stay);
--   assigned a base now stands on the player's pad (restore its pads, shop).
PlotService.Hooks = {
	commit = function(_player: Player) end,
	despawn = function(_player: Player) end,
	clearPads = function(_plot: any) end,
	assigned = function(_player: Player, _profile: any) end,
}

type Slot = {
	index: number,
	cframe: CFrame, -- the plot's centre on the platform's top (plot-local y = 0), PlatformHeight above the grass
	placeName: string,
	region: string,
	model: Model,
	pad: Part,
	post: Part,
	board: Part,
	border: Folder,
	platform: Folder, -- the Land slabs and the ramps (the Pad is the model's PrimaryPart)
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
local switching: { [Player]: boolean } = {} -- a base is being packed or swapped right now (BaseLogic)
local officePos: Vector3 = Vector3.zero
local lastOffer: { [Player]: PlotPickerLogic.Offer } = {}
local watching: { [Player]: boolean } = {}
local offerRemote: RemoteEvent? = nil
local worldFx: RemoteEvent? = nil -- WorldFX: the hammer's knock (optional)
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
	if why ~= "wood" and why ~= "logs" and why ~= "noslab" and why ~= "noingot" then
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

-- LooseService (the loose wood, slabs and ingots a base keeps when it is
-- unloaded) pulls in TruckLoad and WoodService, so it is loaded when first
-- needed, and a spec swaps it.
local looseMod: any = nil
local looseTried = false

local function looseService(): any
	if looseTried then
		return looseMod
	end
	looseTried = true
	local ok, mod = pcall(function(): any
		return require(script.Parent.LooseService)
	end)
	if ok then
		looseMod = mod
	end
	return looseMod
end

-- A base just stood up on a pad: the loose things it was saved with come
-- back, once, and wood a map remake parked comes back at the plot.
local function restoreLoose(player: Player, slot: Slot, profile: Profile)
	local loose = looseService()
	if loose == nil then
		return
	end
	local ok, back, waiting = pcall(function(): (number, number)
		return loose.Restore(player, slot, profile)
	end)
	if ok and type(back) == "number" and back > 0 then
		notify(player, LooseSave.RestoredText(back, waiting :: number))
	elseif not ok then
		warn("[PlotService] loose wood not restored: " .. tostring(back))
	end
	local okStranded, strandedBack = pcall(function(): number
		local n = loose.RestoreStranded(player, slot, profile)
		return n
	end)
	if okStranded and type(strandedBack) == "number" and strandedBack > 0 then
		notify(player, "Wood that was left out on the old map is back on your plot.")
	elseif not okStranded then
		warn("[PlotService] stranded wood not restored: " .. tostring(strandedBack))
	end
end

-- Slabs and ingots live in the world as parts (BuildMaterials). It is
-- loaded when first needed, and a spec swaps it.
local materialsMod: any = nil
local materialsTried = false

local function materials(): any
	if materialsTried then
		return materialsMod
	end
	materialsTried = true
	local ok, mod = pcall(function(): any
		return require(script.Parent.BuildMaterials)
	end)
	if ok then
		materialsMod = mod
	end
	return materialsMod
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

-- Platform, rails and sign for the plot's current size and squares. The
-- build platform is the buildable area exactly (Shared/PlotPlatform): the
-- tier's Pad slab, a Land slab for each bought square past the tier, and a
-- ramp along every exposed edge. `slot.cframe` is the platform's top, so a
-- saved piece at plot-local y = 0 sits on it. The sign stands past the
-- ramps, on the grass, off to the west so a driveway up the middle stays
-- clear. Rails and corner posts show even when the plot is free: a bare
-- platform alone was easy to miss, and easy to drive through.
local function drawBounds(slot: Slot, size: number, claimed: boolean, ownedSquares: { string }?)
	local look = PlotData.Look(slot.index)
	local squares = if claimed then ownedSquares else nil
	local layout = PlotPlatform.Layout(size, squares)
	PlotPlatform.FitPad(slot.pad, layout, slot.cframe, look)
	slot.platform:ClearAllChildren()
	PlotPlatform.BuildEdges(slot.platform, layout, slot.cframe, look)
	-- Past the farthest ramp, standing on the grass (the mesh's pivot is on the ground).
	local reach = layout.extent / 2 + PlotData.PlatformRamp + 2
	local signAt = slot.cframe * CFrame.new(-10, -PlotData.PlatformHeight, reach)
	slot.post.CFrame = signAt * CFrame.new(0, 3, 0)
	slot.board.CFrame = signAt * CFrame.new(0, 6.5, 0)
	-- One mesh for the post and the board, pivot on the ground at the sign.
	-- The board part stays (prompt + both SurfaceGuis) and goes invisible.
	if ItemMeshes.AttachTo(slot.board, "PlotSign", { hostOffset = CFrame.new(0, -6.5, 0) }) then
		slot.post.Transparency = 1
	end
	slot.border:ClearAllChildren()
	local half = size / 2
	local rail = if claimed
		then Color3.fromRGB(look.rail[1], look.rail[2], look.rail[3])
		else Color3.fromRGB(196, 168, 120)
	local postColor = Color3.fromRGB(90, 62, 36)
	-- Rails mark the base yard (the tier) a hair above the platform's top,
	-- never on its face: PlatformEdgeClear studs of air under them.
	local lift = 0.5
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
			slot.cframe * CFrame.new(x, lift, z),
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
			hostOffset = CFrame.new(0, -lift, 0),
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
			slot.cframe * CFrame.new(corner[1], 1.5, corner[2]), -- sunk 0.1 into the platform: no flat face on its top
			postColor,
			Enum.Material.Wood,
			slot.border
		)
		post.CanCollide = false
		ItemMeshes.AttachTo(post, "PlotCorner", { hostOffset = CFrame.new(0, -1.5, 0) })
	end
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
	-- The platform's top: the grass under the pad plus PlatformHeight.
	local cframe = CFrame.new(center.X, TerrainGen.HeightAt(center.X, center.Y) + PlotData.PlatformHeight, center.Y)
	local pad = PlotPlatform.NewPad(PlotPlatform.Layout(PlotData.Tiers[1].size, nil), cframe, PlotData.Look(index))
	pad.Parent = model -- collides: it is the floor of the plot
	model.PrimaryPart = pad
	local border = Instance.new("Folder")
	border.Name = "Border"
	border.Parent = model
	local platform = Instance.new("Folder")
	platform.Name = "Platform"
	platform.Parent = model
	-- Beside the shell, not inside it: items are built when someone claims
	-- or places, after the shell has already streamed to whoever is nearby.
	local items = Instance.new("Folder")
	items.Name = "PlotItems_" .. index
	items.Parent = parent

	-- The signpost (drawBounds puts it past the ramps on the north side).
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
		platform = platform,
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
		elseif SkyBinLogic.IsBin(item.blueprintId) then MachineArt.BuildSkyBin(false)
		elseif PlanerLogic.IsPlaner(item.blueprintId) then MachineArt.BuildPlaner(item.blueprintId, false)
		elseif AutomationLogic.IsBelt(item.blueprintId) then MachineArt.BuildBelt(item.blueprintId, false)
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
			-- Anything in the ghost (planks, slabs, ingots) locks it, so the
			-- client reads one number: zero means still empty.
			model:SetAttribute("FillUnits", BuildCost.TakenOf(bp, item))
			model:SetAttribute("Needs", BuildCost.MissingText(BuildCost.Missing(bp, item)))
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
		MachineArt.SetCut(model, settings.x, settings.y, SawmillLogic.RangeText(mill))
	end
	local _planerMachine, planer = PlanerLogic.Get(item.blueprintId)
	if planer then
		-- A saved setting is clamped to its tier on every load (a hand-edited or
		-- older save can't exceed the range); none saved means the default.
		local saved = item.data
		local settings = if saved
				and type(saved.x) == "number"
				and type(saved.y) == "number"
			then PlanerLogic.Clamp(planer, saved.x, saved.y)
			else PlanerLogic.Default(planer)
		item.data = settings
		model:SetAttribute("CutX", settings.x)
		model:SetAttribute("CutY", settings.y)
		MachineArt.SetCut(model, settings.x, settings.y, PlanerLogic.RangeText(planer))
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
		if item.paint ~= nil then
			model:SetAttribute("Paint", item.paint)
			if type(BlueprintModels.ApplyPaint) == "function" then
				BlueprintModels.ApplyPaint(model, item.paint)
			end
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
			local allowed = PlotLogic.CanEdit(ownerProfile.permissions, who.UserId, hostOwner.UserId, "interact")
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
	-- The vehicle pads of this base stand in the world, not in the items
	-- folder: take them down too, or they would be orphans on the next owner's yard.
	local leaving = ProfileService.GetProfile(player)
	if leaving and leaving.plot then
		pcall(PlotService.Hooks.clearPads, leaving.plot)
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
	pcall(PlotService.Hooks.assigned, player, profile) -- its vehicle pads stand up on this pad
	restoreLoose(player, slot, profile)
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
local TOLD_PICKER = "It's yours! This pad is your spawn. Take out your hammer to start building."

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

-- What Old Hank can do for a player, by offer id (PlotSalesmanData.Offers).
-- Each handler is the real server-validated flow: it checks range and
-- ownership itself, and the charge happens only in tryClaim, at the price
-- from GameConfig. To sell something new through him, add its handler here.
local SALESMAN_OFFERS: { [string]: (Player) -> () } = {
	buyPlot = function(player: Player)
		onOfficeOpened(player)
	end,
}

-- Talking to Old Hank (his Talk prompt, or the counter's, both end up in
-- the same place). Rate-limited like the other prompts' handlers; the
-- client names nothing, so there is no price or offer to spoof.
-- What Old Hank says back: the dialogue box when GameServer has wired it
-- (PlotService.Speak), a toast otherwise (the specs).
local function salesmanSay(player: Player, text: string)
	local speak = PlotService.Speak
	if speak then
		speak(player, text)
	else
		notify(player, text)
	end
end

local function onSalesmanTalk(player: Player)
	if not RateLimiter.Allow(player, "PlotSalesman") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or not profile.plot then
		return
	end
	local choice = PlotSalesmanData.Choose({
		ownsPlot = slotOf[player] ~= nil,
		full = freeSlot() == nil,
	})
	local offer = choice.offer
	if not offer then
		salesmanSay(player, choice.line)
		return
	end
	if not nearOffice(player) then
		salesmanSay(player, PlotSalesmanData.FarLine)
		return
	end
	local handler = SALESMAN_OFFERS[offer.id]
	if handler then
		handler(player)
	end
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
				if PlotLogic.CanEdit(profile.permissions, player.UserId, owner.UserId, flag) then
					return slot, profile, owner, false
				end
				denied = true
			end
		end
	end
	return nil, nil, nil, denied
end

-- Lane F: one edit-rights check. The owner always; anyone else needs the
-- flag in the owner's permissions. flag: "build" | "destroy" | "interact" |
-- "paint" | "grab". Other lanes call this instead of PermissionLogic.
function PlotService.CanEdit(player: Player?, owner: Player?, flag: string): boolean
	return EditRights.Can(player, owner, flag)
end

-- Whose plot a world position is on, or nil (off every plot). Lane F: the
-- services that act at a spot (a dropped blueprint) ask this, then CanEdit.
function PlotService.OwnerAt(position: Vector3): Player?
	for _, slot in ipairs(slots) do
		local owner = slot.owner
		local profile = if owner then ProfileService.GetProfile(owner) else nil
		if owner and profile then
			local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
			local squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
			local half = PlotLogic.Extent(tier.size, squares) / 2
			local p = slot.cframe:PointToObjectSpace(position)
			if math.abs(p.X) <= half and math.abs(p.Z) <= half then
				return owner
			end
		end
	end
	return nil
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

-- The knock and the dust: told to everyone near the piece (the player who
-- swung already showed theirs the moment they pressed). Nothing here is
-- trusted by anything else; it is only a picture.
local function tellHammer(slot: Slot, who: Player, item: PlotLogic.Placed)
	local remote = worldFx
	if not remote then
		return
	end
	local pos = (slot.cframe * CFrame.new(item.x, item.y or 0, item.z)).Position
	for _, other in ipairs(onlinePlayers()) do
		if other ~= who then
			-- Not rootOf: that one stands a seated player up.
			local char = other.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if root and HammerLogic.Hears((root.Position - pos).Magnitude) then
				remote:FireClient(other, "Hammer", { pos = pos, by = who.UserId })
			end
		end
	end
end

-- Where a box's placing is checked and spent. BoxService by default; a spec
-- swaps it (PlotService does not require BoxService at load).
PlotService.Boxes = {
	ready = function(player: Player, uid: unknown, itemId: string): boolean
		local ok, boxes = pcall(function(): any
			return require(script.Parent.BoxService)
		end)
		return ok and boxes ~= nil and boxes.ReadyForPlacement(player, uid, itemId) == true
	end,
	spend = function(player: Player, uid: unknown, itemId: string): boolean
		local ok, boxes = pcall(function(): any
			return require(script.Parent.BoxService)
		end)
		return ok and boxes ~= nil and boxes.SpendForPlacement(player, uid, itemId) == true
	end,
}

function PlotService.Place(
	player: Player,
	blueprintId: unknown,
	x: unknown,
	z: unknown,
	rot: unknown,
	y: unknown,
	boxUid: unknown
)
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
	-- A Sky Bin is the owner's, one per plot: a visitor can't spend theirs here.
	local binRefusal = SkyBinLogic.PlaceRefusal(bp.id, player == owner, profile.plot.placed)
		or AutomationLogic.PlaceRefusal(bp.id, player == owner, profile.plot.placed)
	if binRefusal then
		notify(player, binRefusal)
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
	-- that is the only way to get one: the counter sells them, the hammer's
	-- list does not. Everything else must be in your blueprint book (a
	-- starter plan, a store unlock you learned from its physical blueprint).
	-- Stock is spent only after the cash check, so a refused place leaves it.
	local stock = if type(payer.sawmillStock) == "table" then payer.sawmillStock else nil
	local fromShop = BlueprintBook.IsFromStock(bp.id)
	local stockAt = if fromShop and stock then table.find(stock, bp.id) else nil
	-- A sawmill, planer or belt comes out of the box you opened (boxUid): one
	-- use, the box is spent below once everything has passed. An old save may
	-- still hold a sawmill in stock, which places as before (the legacy path).
	local fromBox = AutomationLogic.PlacedFromBox(bp.id) and PlotService.Boxes.ready(player, boxUid, bp.id)
	local fromStock = stockAt ~= nil and not fromBox
	local owned = BlueprintBook.Owns(payer, bp.id)
	local boxed = ShopLogic.ShelfMenusHidden()
	local allowed, refusal = BlueprintBook.Allowed(bp.id, owned, if fromStock then 1 else 0, boxed)
	if fromBox then
		allowed, refusal = true, nil
	end
	if not allowed then
		notify(player, BlueprintBook.Message(refusal, bp))
		return
	end
	local source = if fromBox
		then "place"
		else PlotLogic.Source(bp, if fromStock then 1 else 0, bp.unlock == true and owned, boxed)
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
	if fromBox and not PlotService.Boxes.spend(player, boxUid, bp.id) then
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
		item.fill = BuildCost.NewFill(bp)
	end
	table.insert(profile.plot.placed, item)
	placedAt[item.uid] = os.clock()
	if SkyBinLogic.IsBin(bp.id) then
		profile.skyBinOwned = true -- one per player, whichever way it came out
		owner:SetAttribute("SkyBinOwned", true)
	end
	buildItem(slot, owner, item)
	if fromStock or fromBox then
		notify(player, string.format("Placed your %s.", bp.displayName))
	end
	tellHammer(slot, player, item)
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
	tellHammer(slot, player, item)
end

-- What selling gives back. An unlock bought at the store refunds nothing.
-- Within a minute of placing it (UndoSeconds) a piece gives the whole fee
-- back, and a kit piece also gives back every plank, slab and ingot it took
-- (PlotLogic.SellPlan says what). After that, SellBack; slabs and ingots
-- only ever come back as slabs and ingots, never as cash.
local function sellPlan(item: PlotLogic.Placed, bp: PlotData.Blueprint): PlotLogic.SellPlan
	local at = placedAt[item.uid]
	local within = at ~= nil and os.clock() - at <= UNDO_SECONDS
	if bp.kit then
		return PlotLogic.SellPlan(bp, item, within)
	end
	if within then
		if bp.unlock then
			return { cash = 0, planks = 0, wood = nil }
		end
		return { cash = bp.priceCash, planks = 0, wood = nil }
	end
	return PlotLogic.SellPlan(bp, item)
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

local function ingotCount(ingots: { [string]: number }?): number
	local n = 0
	if ingots then
		for _, count in pairs(ingots) do
			n += count
		end
	end
	return n
end

-- Can the owner take these slabs and ingots back as parts? A refusal names
-- how many do not fit; nothing is dropped and nothing is taken.
local function materialsRoom(owner: Player, plan: PlotLogic.SellPlan): string?
	local slabs = math.ceil(plan.slabs or 0)
	local ingots = ingotCount(plan.ingots)
	if slabs <= 0 and ingots <= 0 then
		return nil
	end
	local mats = materials()
	if mats == nil then
		return "Those slabs and ingots have nowhere to go. Try again in a moment."
	end
	if slabs > 0 then
		local room = mats.SlabRoom(owner.UserId)
		if room < slabs then
			return string.format(
				"Pick up or use %d loose slab%s first: %d come back and you can only carry %d.",
				slabs - room,
				if slabs - room == 1 then "" else "s",
				slabs,
				SlabData.MaxLoose
			)
		end
	end
	if ingots > 0 then
		local room = mats.IngotRoom(owner)
		if room < ingots then
			return string.format(
				"Pick up or use %d loose ore piece%s first: %d ingot%s come back.",
				ingots - room,
				if ingots - room == 1 then "" else "s",
				ingots,
				if ingots == 1 then "" else "s"
			)
		end
	end
	return nil
end

-- Puts the slabs and ingots a piece took back in the world beside where it
-- stood. materialsRoom has already said yes.
local function giveMaterials(owner: Player, slot: Slot, item: PlotLogic.Placed, plan: PlotLogic.SellPlan)
	local mats = materials()
	if mats == nil then
		return
	end
	local base = slot.cframe * CFrame.new(item.x, (item.y or 0) + 2, item.z)
	local n = 0
	for _ = 1, math.ceil(plan.slabs or 0) do
		local col, row = n % 3, n // 3
		n += 1
		mats.ReturnSlab(owner.UserId, base * CFrame.new((col - 1) * 4.5, row * 2.2, 3))
	end
	local ores: { string } = {}
	for ore in pairs(plan.ingots or {}) do
		table.insert(ores, ore)
	end
	table.sort(ores)
	local m = 0
	for _, ore in ipairs(ores) do
		for _ = 1, (plan.ingots :: any)[ore] do
			local col, row = m % 4, m // 4
			m += 1
			mats.ReturnIngot(owner, ore, base * CFrame.new((col - 1.5) * 1.8, row * 0.5, -3))
		end
	end
end

-- Pays out a Sky Bin's wood before the bin is sold: true when the bin is
-- empty or its wood was paid in full (AetherService.PayOutBin; the wallet must
-- have room for it plus `extra`). A spec swaps it.
PlotService.SkyBinPayout = function(owner: Player, extra: number): boolean
	local ok, aether = pcall(function(): any
		return require(script.Parent.AetherService)
	end)
	return ok and aether ~= nil and aether.PayOutBin(owner, extra) == true
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
	local isBin = SkyBinLogic.IsBin(item.blueprintId)
	if isBin and player ~= owner then
		notify(player, SkyBinLogic.OnlyOwnerSellLine)
		return
	end
	local plan = sellPlan(item, bp)
	local refund, planks, woodId = plan.cash, plan.planks, plan.wood
	if refund > 0 and profile.cash + refund > GameConfig.CashCap then
		notify(
			player,
			if owner == player
				then "Your wallet is too full to sell that. Spend some first."
				else "The owner's wallet is too full for that."
		)
		return
	end
	local roomRefusal = materialsRoom(owner, plan)
	if roomRefusal then
		notify(player, roomRefusal)
		return
	end
	if planks > 0 and not givePlanks(owner, slot, item, planks, woodId) then
		notify(player, "Those planks had nowhere to go. Try again in a moment.")
		return
	end
	if isBin then
		-- The wood inside is paid out first (the "Sell Sky Bin" sale) and only
		-- then is the bin removed. If the wood can't be paid in full the bin
		-- stays and nothing is lost.
		if not PlotService.SkyBinPayout(owner, refund) then
			notify(player, SkyBinLogic.WoodStaysLine)
			return
		end
		profile.skyBinOwned = false -- gone for good: no re-boxing, no free copy at the next load
		owner:SetAttribute("SkyBinOwned", false)
	end
	table.remove(profile.plot.placed, index)
	placedAt[item.uid] = nil
	local model = slot.items:FindFirstChild(item.uid)
	if model then
		model:Destroy()
	end
	giveMaterials(owner, slot, item, plan)
	LogicService.Sync(slot :: any, profile, player)
	if refund > 0 then
		EconomyService.Refund(owner, refund, "sold " .. bp.displayName, bp.id)
	end
	local full = if bp.kit then (item.paid or PlotData.Price(bp)) else bp.priceCash
	if bp.unlock and not bp.kit then
		full = 0
	end
	local gaveBack = planks > 0 or (plan.slabs or 0) > 0 or plan.ingots ~= nil
	local text = if gaveBack and refund > 0
		then string.format(
			"Took back the %s: %s refunded, and what went into it is on the ground.",
			bp.displayName,
			Util.formatCash(refund)
		)
		elseif gaveBack then string.format(
			"Took apart the %s. What went into it is on the ground.",
			bp.displayName
		)
		elseif refund == full and refund > 0 then string.format(
			"Took back the %s: %s refunded.",
			bp.displayName,
			Util.formatCash(refund)
		)
		else string.format("Sold the %s for %s.", bp.displayName, Util.formatCash(refund))
	notify(player, text)
end

-- /sample: one of SampleBuilds' test buildings on the OWNER's plot, free, at the
-- spot the owner faces (in front of their character, turned to face them).
-- AdminService has already checked the speaker is the owner; this checks the
-- plot and the fit. All or nothing: every piece must pass PlotLogic.Check (in
-- order, with the plot's caps and the pieces already there), else nothing is
-- placed. The pieces are built, painted and cost nothing, and `paid` is 0, so
-- they also sell for nothing; their uids start "sample-" so ClearSamples can
-- take them down. Returns (ok, the line to tell the owner).
function PlotService.PlaceSample(player: Player, name: unknown): (boolean, string)
	local sample = SampleBuilds.Get(name)
	if not sample then
		return false, "No such sample. Try: " .. table.concat(SampleBuilds.List, ", ") .. "."
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or not profile.plot.claimed then
		return false, "Claim a plot first."
	end
	local slot = nearOwnPlot(player, profile)
	if not slot or slot.owner ~= player then
		return false, "Stand on your own plot."
	end
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not root then
		return false, "No character to aim from."
	end
	local here = slot.cframe:PointToObjectSpace(root.Position)
	local look = slot.cframe:VectorToObjectSpace(root.CFrame.LookVector)
	local flat = math.sqrt(look.X * look.X + look.Z * look.Z)
	local dx, dz = 0, 1
	if flat > 1e-3 then
		dx, dz = look.X / flat, look.Z / flat
	end
	local squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
	local items, why = SampleBuilds.Find(
		sample,
		SampleBuilds.FacingRot(dx, dz),
		here.X + dx * sample.reach,
		here.Z + dz * sample.reach,
		profile.plot.tier,
		profile.plot.placed,
		squares,
		function(i: number): string
			return SampleBuilds.UidPrefix .. tostring(i)
		end
	)
	if not items then
		return false,
			string.format("The %s doesn't fit there (%s). Face open ground.", sample.displayName, why or "no room")
	end
	for _, item in ipairs(items) do
		item.uid = SampleBuilds.UidPrefix .. Util.guid()
		table.insert(profile.plot.placed, item)
		buildItem(slot, player, item)
	end
	LogicService.Sync(slot :: any, profile, player)
	return true, string.format("Built the %s (%d pieces, free).", sample.displayName, #items)
end

-- Takes down every sample piece on the owner's plot. Free, and they were free.
function PlotService.ClearSamples(player: Player): number
	local profile = ProfileService.GetProfile(player)
	local slot = slotOf[player]
	if not profile or not slot then
		return 0
	end
	local removed = 0
	for i = #profile.plot.placed, 1, -1 do
		local item = profile.plot.placed[i]
		if SampleBuilds.IsSampleUid(item.uid) then
			table.remove(profile.plot.placed, i)
			placedAt[item.uid] = nil
			local model = slot.items:FindFirstChild(item.uid)
			if model then
				model:Destroy()
			end
			removed += 1
		end
	end
	if removed > 0 then
		LogicService.Sync(slot :: any, profile, player)
	end
	return removed
end

-- Paints a placed kit piece. Cosmetic and free: no cash moves, and the fee
-- paid, the planks in it, its size, its hit points and what it sells for stay
-- exactly as they were. Whoever may build on the plot may paint it (the owner,
-- or a visitor with the `build` permission), standing within KitPaint.Reach.
-- The piece is rebuilt from its saved data, so natural brings the wood back.
function PlotService.Paint(player: Player, uid: unknown, paintId: unknown)
	if type(uid) ~= "string" or type(paintId) ~= "string" or not RateLimiter.Allow(player, "PaintPiece") then
		return
	end
	local slot, profile, owner, denied = hostFor(player, "build")
	if not slot or not profile or not owner then
		if denied then
			notify(player, "You can't build on this plot.")
		end
		return
	end
	local item = findPlaced(profile, uid)
	local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
	if not item or not bp then
		return
	end
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not root then
		return
	end
	local spot = (slot.cframe * CFrame.new(item.x, item.y or 0, item.z)).Position
	local ok, why = KitPaint.Check(bp, item.paint, paintId, (root.Position - spot).Magnitude)
	if not ok then
		local text = KitPaint.Message(why)
		if text then
			notify(player, text)
		end
		return
	end
	item.paint = KitPaint.Clean(paintId)
	local old = slot.items:FindFirstChild(item.uid)
	if old then
		old:Destroy()
	end
	buildItem(slot, owner, item)
	LogicService.Sync(slot :: any, profile, owner)
end

-- Paint all of this type (Lane F). Repaints every piece with that blueprint
-- id on the plot the player stands on and may edit (CanEdit "paint"), takes
-- the summed paint price once (paint is free today), and is one undo step
-- for the plot's owner. The client asks for a confirm first; the server
-- only checks the rules.
function PlotService.PaintAllType(player: Player, pieceId: unknown, paintId: unknown)
	if type(pieceId) ~= "string" or type(paintId) ~= "string" or not RateLimiter.Allow(player, "PaintAllType") then
		return
	end
	local slot, profile, owner, denied = hostFor(player, "paint")
	if not slot or not profile or not owner then
		if denied then
			notify(player, "You can't paint on this plot.")
		end
		return
	end
	local payer = if player == owner then profile else ProfileService.GetProfile(player)
	if not payer then
		return
	end
	local isOwner = player == owner
	local stack = if isOwner then undoStacks[player] else nil
	if isOwner and not stack then
		stack = {}
		undoStacks[player] = stack
	end
	local world: EditLogic.World = {
		cash = payer.cash,
		tier = profile.plot.tier,
		ownerId = owner.UserId,
		playerId = player.UserId,
		placed = profile.plot.placed,
		undo = stack or {},
		squares = if type(profile.plot.squares) == "table" then profile.plot.squares else {},
	}
	local stackSnap = if stack then table.clone(stack) else nil
	local oldPaint: { [string]: string? } = {}
	for _, item in ipairs(profile.plot.placed) do
		oldPaint[item.uid] = item.paint
	end
	local ok, why, uids = EditLogic.PaintAll(world, pieceId, paintId, isOwner)
	if not ok then
		local bp = PlotLogic.Blueprint(pieceId)
		local text = if why == "cash"
			then EditLogic.Message("cash")
			else KitPaint.AllMessage(why, if bp then bp.displayName else nil)
		if text then
			notify(player, text)
		end
		return
	end
	local price = payer.cash - world.cash
	if price > 0 and not EconomyService.SpendCash(player, price, "painted all", "kit") then
		-- Put every colour and the stack back as they were.
		for _, item in ipairs(profile.plot.placed) do
			item.paint = oldPaint[item.uid]
		end
		if stack and stackSnap then
			table.clear(stack)
			for i, entry in ipairs(stackSnap) do
				stack[i] = entry
			end
		end
		notify(player, EditLogic.Message("cash") or "You don't have enough for that.")
		return
	end
	for _, uid in ipairs(uids) do
		local item = findPlaced(profile, uid)
		if item then
			local old = slot.items:FindFirstChild(uid)
			if old then
				old:Destroy()
			end
			buildItem(slot, owner, item)
		end
	end
	LogicService.Sync(slot :: any, profile, owner)
	local bp = PlotLogic.Blueprint(pieceId)
	notify(
		player,
		string.format("Painted %d %s%s.", #uids, if bp then bp.displayName else "piece", if #uids == 1 then "" else "s")
	)
end

-- BaseBoot binds the remote (GameServer's remote list is not edited).
function PlotService.BindPaintAll(remote: RemoteEvent?)
	if remote then
		remote.OnServerEvent:Connect(function(player: Player, pieceId: unknown, paintId: unknown)
			PlotService.PaintAllType(player, pieceId, paintId)
		end)
	end
end

-- Where a piece that fell out of the world comes back to: a spot over the
-- player's own plot, a little different each time so rescues do not stack
-- (FallenLogic.Offset). nil when they have no pad (a base unloaded).
local rescues: { [Player]: number } = {}

function PlotService.RecoverSpot(player: Player): CFrame?
	local slot = slotOf[player]
	if slot == nil then
		return nil
	end
	local n = ((rescues[player] or 0) % 16) + 1
	rescues[player] = n
	local x, y, z = FallenLogic.Offset(n)
	return slot.cframe * CFrame.new(x, y, z)
end

-- A base change is running for this player (a claim, an expansion, an
-- unload or a swap). Save now waits for it.
function PlotService.IsBusy(player: Player): boolean
	return switching[player] == true or claiming[player] == true or expanding[player] == true
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
		and a.paint == b.paint
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
			paint = item.paint,
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

-- Crafted furniture (Lane M's Copper Lamp Post and Gold-banded Chest recipes):
-- GrantPiece puts one placeable piece in the player's stock, where it shows in
-- the hammer's list like a boxed machine and is spent when placed (free). It is
-- a from-stock entry, not a learned plan, so the book does not grow. Returns
-- whether it was granted, and why not (a name, or "full"). `source` is a short
-- label for the log ("craft").
function PlotService.CanGrant(player: Player, pieceId: unknown): (boolean, string?)
	if type(pieceId) ~= "string" or not FurnitureData.IsGranted(pieceId) then
		return false, "unknown"
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return false, "missing"
	end
	if type(profile.sawmillStock) == "table" and #profile.sawmillStock >= FurnitureData.MaxStock then
		return false, "full"
	end
	return true, nil
end

function PlotService.GrantPiece(player: Player, pieceId: unknown, source: unknown): (boolean, string?)
	local ok, why = PlotService.CanGrant(player, pieceId)
	if not ok then
		return false, why
	end
	local profile = ProfileService.GetProfile(player) :: Profile
	if type(profile.sawmillStock) ~= "table" then
		profile.sawmillStock = {}
	end
	table.insert(profile.sawmillStock, pieceId :: string)
	player:SetAttribute("SawmillStock", SawmillLogic.EncodeStock(profile.sawmillStock))
	local bp = PlotData.Blueprint(pieceId :: string)
	if bp then
		notify(player, string.format("%s is in your hammer's list. Place it on your plot.", bp.displayName))
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "PieceGranted", if type(source) == "string" then source else "grant")
	end)
	return true, nil
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

-- At profile load: watch the spawn and mirror the plot's attributes. It opens
-- no picker: a save is chosen by hand first (SaveSlotService), and only the
-- chosen save's PlayerJoined asks for a pad.
function PlotService.Prepare(player: Player, profile: Profile)
	watchSpawn(player)
	if profile.plot then
		mirrorPlot(player, profile)
	end
end

-- The chosen save is loaded: a save that owns a plot now picks a pad for it.
-- The 60 s timer does not start here but when the picker is on the player's
-- screen (PlotService.Shown), so a screen in front of it never eats the time.
function PlotService.PlayerJoined(player: Player, profile: Profile)
	PlotService.Prepare(player, profile)
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
	pickingUntil[player] = math.huge -- armed by Shown
	player:SetAttribute("Picking", true)
	fireOffer(player)
end

-- The client says the join picker is really on its screen. Only then does the
-- timeout that takes a free pad start; asking twice never restarts it.
function PlotService.Shown(player: Player)
	if not RateLimiter.Allow(player, "PlotShown") then
		return
	end
	if pickingUntil[player] == math.huge then
		pickingUntil[player] = os.clock() + PlotPickerLogic.TimeoutSeconds
	end
end

function PlotService.HasPad(player: Player): boolean
	return slotOf[player] ~= nil
end

-- Sends the picker's offer again (JoinSync, when the client says ClientReady):
-- only to a player whose picker is still waiting, and freshly built, so the
-- taken pads are current.
function PlotService.Resend(player: Player)
	if pickingUntil[player] ~= nil or buying[player] then
		fireOffer(player)
	end
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
	restoreLoose(player, slot, profile)
	return true
end

function PlotService.PlayerRemoving(player: Player)
	-- Drop the timer first, so a timeout can't assign a pad after they leave.
	pickingUntil[player] = nil
	buying[player] = nil
	claiming[player] = nil
	switching[player] = nil
	lastOffer[player] = nil
	watching[player] = nil
	undoStacks[player] = nil
	forgetFill(player)
	expanding[player] = nil
	rescues[player] = nil
	-- Leaving with the base on its pad: the loose wood and slabs go into the
	-- save the same way an unload does (ingots stay with Lane M's own save). If
	-- the pile is too big to hold, it is left alone and the older ground-load
	-- save keeps the wood.
	local slot = slotOf[player]
	local profile = ProfileService.GetProfile(player)
	local loose = looseService()
	if slot and profile and profile.plot and loose ~= nil then
		local ok, err = (pcall :: any)(loose.Collect, player, slot, profile, false)
		if not ok then
			warn("[PlotService] loose wood not saved on leave: " .. tostring(err))
		end
	end
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
	-- Old Hank's props: a pitchfork leaning on the counter's end and a hay
	-- bale beside it. The fork is not solid; the bale is, so it also keeps
	-- people from cutting round the counter's end.
	local steel = Color3.fromRGB(150, 150, 156)
	local haft = part(
		"Pitchfork",
		Vector3.new(0.25, 6.2, 0.25),
		facing * CFrame.new(-4.4, 3.0, 0.3) * CFrame.Angles(0, 0, math.rad(-8)),
		Color3.fromRGB(140, 100, 58),
		Enum.Material.Wood,
		model
	)
	haft.CanCollide = false
	for _, x in ipairs({ -0.35, 0, 0.35 }) do
		local tine = part(
			"Tine",
			Vector3.new(0.1, 1.1, 0.1),
			haft.CFrame * CFrame.new(x, 3.6, 0),
			steel,
			Enum.Material.Metal,
			model
		)
		tine.CanCollide = false
	end
	local bar = part(
		"TineBar",
		Vector3.new(0.85, 0.12, 0.12),
		haft.CFrame * CFrame.new(0, 3.1, 0),
		steel,
		Enum.Material.Metal,
		model
	)
	bar.CanCollide = false
	part(
		"HayBale",
		Vector3.new(2.6, 1.8, 1.6),
		facing * CFrame.new(-5.4, 0.9, 1.2) * CFrame.Angles(0, math.rad(12), 0),
		Color3.fromRGB(214, 183, 92),
		Enum.Material.Fabric,
		model
	)
	model.Parent = parent
end

-- Wire Old Hank's Talk prompt to the sales flow. NPCService builds him after
-- PlotService.Init, so GameServer calls this once both have run. He is in
-- the Townsfolk folder (Atomic), found by his id.
function PlotService.HookSalesman(map: Instance)
	local folder = map:FindFirstChild("Townsfolk")
	local model = if folder then folder:FindFirstChild(PlotSalesmanData.Id) else nil
	local talk = if model then model:FindFirstChild("Talk") else nil
	if not (talk and talk:IsA("ProximityPrompt")) then
		warn("[PlotService] Old Hank's Talk prompt is missing; talking to him won't open the plot sale")
		return
	end
	talk.Triggered:Connect(onSalesmanTalk)
end

-- `map` is TimberlineMap; the remotes are PlaceBlueprint, MoveBlueprint,
-- SellPlaced and UpgradePlot.
-- Draws a pad's platform, rails and sign again from its owner's save (or as a
-- free pad). Used when the plot kit's meshes land after the pads were built.
local function redrawSlot(slot: Slot)
	local owner = slot.owner
	local profile = if owner then ProfileService.GetProfile(owner) else nil
	if owner and profile and profile.plot then
		local tier = PlotData.Tier(profile.plot.tier) or PlotData.Tiers[1]
		local owned = if type(profile.plot.squares) == "table" then profile.plot.squares else {}
		drawBounds(slot, tier.size, true, owned)
	else
		drawBounds(slot, PlotData.Tiers[1].size, false)
	end
end

-- The plot kit's meshes landed after the pads were built (PlotService.Init
-- gave up waiting): dress every pad now. A redraw clears and rebuilds the
-- pad's platform slabs and ramps, which drops a player standing on them, so
-- a pad with a player near it waits (PlotRedraw) and is tried again.
function PlotService.RedrawLate()
	local pending: { number } = {}
	for _, slot in ipairs(slots) do
		table.insert(pending, slot.index)
	end
	local tries = 0
	while #pending > 0 and tries < PlotRedraw.MaxRetries do
		tries += 1
		local pads: { PlotRedraw.Pad } = {}
		for _, index in ipairs(pending) do
			local at = slots[index].cframe.Position
			table.insert(pads, { index = index, x = at.X, z = at.Z })
		end
		local players: { PlotRedraw.Point } = {}
		for _, who in ipairs(game:GetService("Players"):GetPlayers()) do
			local char = who.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				table.insert(players, { x = root.Position.X, z = root.Position.Z })
			end
		end
		local now, later = PlotRedraw.Split(pads, players)
		for _, index in ipairs(now) do
			local ok, err = (pcall :: any)(redrawSlot, slots[index])
			if not ok then
				warn(string.format("[PlotService] redrawing plot %d failed: %s", index, tostring(err)))
			end
		end
		pending = later
		if #pending > 0 then
			task.wait(PlotRedraw.RetrySeconds)
		end
	end
	print(
		string.format(
			"[Load] PlotService: the plot kit's meshes landed late; the pads were dressed (%d held back for a player)",
			#pending
		)
	)
end

-- `options.gates` (GameServer passes LoadState.Gates) gets "itemMeshes" when
-- the plot kit's meshes are in.
function PlotService.Init(
	map: Instance,
	remotes: { [string]: RemoteEvent },
	notifyFn: (Player, string) -> (),
	options: { gates: ReadyGates.Gates? }?
)
	notify = notifyFn
	LogicService.Bind(hostFor :: any, notifyFn)
	-- The kit's meshes load side by side in the background (Studio, 7 October
	-- 2026: loading them one at a time held this Init for 10.7 s). With the
	-- start-up preload they are already cached and this is instant. If they
	-- are late the pads are built part-built after a short bounded wait and
	-- dressed when the meshes land: the server never waits on an asset fetch.
	local gates = (options and options.gates) or ReadyGates.new()
	local lateShells = false
	task.spawn(function()
		ItemMeshes.LoadAsync()
		gates.Set("itemMeshes")
		if lateShells then
			PlotService.RedrawLate()
		end
	end)
	if not gates.Wait("itemMeshes", 3) then
		lateShells = true
		print("[Load] PlotService: the plot kit's meshes are not in after 3 s; the pads are built part-built for now")
	end
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
	if remotes.PaintPiece then
		remotes.PaintPiece.OnServerEvent:Connect(function(player: Player, uid: unknown, paintId: unknown)
			PlotService.Paint(player, uid, paintId)
		end)
	end
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
	worldFx = remotes.WorldFX
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
	if remotes.PlotShown then
		remotes.PlotShown.OnServerEvent:Connect(function(player: Player)
			PlotService.Shown(player)
		end)
	end
	if remotes.BaseAction then
		remotes.BaseAction.OnServerEvent:Connect(function(player: Player, action: unknown)
			PlotService.BaseAction(player, action)
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
								mill = piece.mill,
								board = piece.board,
								temper = piece.temper,
							}, player.UserId, api)
							if changed then
								local model = slot.items:FindFirstChild(item.uid)
								if model and model:IsA("Model") and type(BlueprintModels.ApplyWood) == "function" then
									BlueprintModels.ApplyWood(model, item.wood)
									BlueprintModels.ApplyPaint(model, item.paint)
									BlueprintModels.SetFaded(model, not PlotLogic.IsBuilt(bp, item))
									model:SetAttribute("FillUnits", BuildCost.TakenOf(bp, item))
									model:SetAttribute("Needs", BuildCost.MissingText(BuildCost.Missing(bp, item)))
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
					-- Sandstone slabs and ingots: the pieces that take them (BuildCost)
					-- ask for each part within reach. One part fills once.
					if BuildCost.NeedsSlabsOrIngots(BuildCost.Of(bp)) and item.fill then
						local mats = materials()
						if mats and type(mats.Of) == "function" then
							local matApi = {
								Take = function(uid: string): boolean
									return mats.Take(uid) == true
								end,
							}
							for _, m in ipairs(mats.Of(player.UserId)) do
								if item.fill == nil then
									break
								end
								if FillLogic.InRange((m.position - origin).Magnitude) then
									local changed, why = PlotFill.ApplyMaterial(item, m, player.UserId, matApi)
									if changed then
										local model = slot.items:FindFirstChild(item.uid)
										if model and model:IsA("Model") then
											model:SetAttribute("FillUnits", BuildCost.TakenOf(bp, item))
											model:SetAttribute(
												"Needs",
												BuildCost.MissingText(BuildCost.Missing(bp, item))
											)
											if type(BlueprintModels.SetFaded) == "function" then
												BlueprintModels.SetFaded(model, not PlotLogic.IsBuilt(bp, item))
											end
										end
									elseif type(why) == "string" then
										local text = FillLogic.Message(why, bp.displayName, m.ore)
										if text then
											tellFill(player, item.uid, why, text, m.uid, now)
										end
									end
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

---------------------------------------------------------------------------
-- Unload base / load base (Shared/BaseLogic)
---------------------------------------------------------------------------

-- What lies loose on their own plot (LooseService.Scan): the unload saves it
-- with the base and refuses only when the save cannot hold it.
local function looseOn(player: Player, slot: Slot, profile: Profile): LooseSave.Found
	local loose = looseService()
	if loose == nil then
		return { pieces = 0, sections = 0, unsaveable = 0 }
	end
	local ok, found = pcall(function(): LooseSave.Found
		return loose.Scan(player, slot, profile)
	end)
	if ok and type(found) == "table" then
		return found
	end
	return { pieces = 0, sections = 0, unsaveable = 0 }
end

-- Everyone but the owner who stands on or beside the yard is set down just
-- outside it, so nobody falls out of a house that is about to come down.
local function ejectOthers(owner: Player, slot: Slot, profile: Profile)
	for _, other in ipairs(onlinePlayers()) do
		if other ~= owner and actorOn(other, slot, profile) then
			nudgeOff(other, slot, profile)
		end
	end
end

local FAILED = "Something went wrong and your base is still on its pad. Try again."

-- The world lets go (wood, the truck, visitors, pad models), then the pad is
-- released. The save is NOT edited: profile.plot stays exactly as it is, so
-- nothing is moved, copied or lost. If the release throws, the base is built
-- back on its pad. A save written before this runs, or after, is whole.
local function unloadBase(player: Player, profile: Profile, slot: Slot): boolean
	-- The loose wood, slabs and ingots on the plot go into the save first, in
	-- one step, so the commit below does not also save them as ground wood.
	local loose = looseService()
	if loose ~= nil then
		local okCollect, saved, why = (pcall :: any)(loose.Collect, player, slot, profile, true)
		if not okCollect or saved ~= true then
			if okCollect and type(why) == "string" then
				notify(player, why)
			end
			return false
		end
	end
	pcall(PlotService.Hooks.commit, player)
	pcall(PlotService.Hooks.despawn, player)
	-- The commit may have yielded: still the same save, still on that pad?
	if ProfileService.GetProfile(player) ~= profile or slotOf[player] ~= slot then
		return false
	end
	ejectOthers(player, slot, profile)
	pcall(PlotService.Hooks.clearPads, profile.plot)
	undoStacks[player] = nil
	local ok = pcall(release, player)
	if not ok then
		slot.items:ClearAllChildren()
		slot.owner = player
		pcall(assign, player, slot, profile)
		pcall(PlotService.Hooks.assigned, player, profile)
		restoreLoose(player, slot, profile) -- what was just saved off the plot comes straight back
		return false
	end
	return true
end

-- Intents from the SAVES panel: "unload" (the base comes off the pad) and
-- "load" (the free plot picker opens for it). The server checks it all: one
-- change at a time, cooldown, loose wood, an owned plot, a free pad.
function PlotService.BaseAction(player: Player, action: unknown)
	if not RateLimiter.Allow(player, "BaseAction") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or not profile.plot then
		return
	end
	local slot = slotOf[player]
	if action == "unload" then
		local ctx: BaseLogic.Context = {
			now = os.time(),
			hasPad = slot ~= nil,
			busy = switching[player] == true or claiming[player] == true or expanding[player] == true,
			loose = if slot then looseOn(player, slot, profile) else { pieces = 0, sections = 0, unsaveable = 0 },
		}
		local ok, why = BaseLogic.CheckUnload(profile, ctx)
		if not ok or not slot then
			if why and why ~= BaseLogic.Reasons.bad then
				notify(player, why)
			end
			return
		end
		switching[player] = true
		local done, result = (pcall :: any)(unloadBase, player, profile, slot)
		switching[player] = nil
		if not done or result ~= true then
			if not done then
				warn("[PlotService] unload failed: " .. tostring(result))
			end
			notify(player, FAILED)
			return
		end
		BaseLogic.Stamp(profile, os.time())
		player:SetAttribute("BaseCooldownUntil", profile.baseCooldownUntil)
		local save = ProfileService.Save
		if type(save) == "function" then
			pcall(save, player) -- the save is written with the base in it
		end
		notify(player, BaseLogic.UnloadedToast)
	elseif action == "load" then
		local ok = BaseLogic.CanLoad(profile, slot ~= nil)
		if not ok or switching[player] or claiming[player] then
			return
		end
		if pickingUntil[player] ~= nil or buying[player] then
			PlotService.Resend(player) -- the picker is already up: show it again
			return
		end
		PlotService.PlayerJoined(player, profile) -- the same free picker as a join, timer and all
	end
end

return PlotService
