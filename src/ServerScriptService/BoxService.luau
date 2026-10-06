--!strict
-- BoxService: boxed shelves. A box on the shelf is anchored. Carrying it
-- uses the same drag as wood (the model is tagged ShopBox). Paying at the
-- counter grants the item; opening only unpacks the box you already own.
-- An unpaid box outside the store for two watches goes back to its shelf.
-- The Tool Shed's gold Robux shelf uses the same boxes: at the counter,
-- Yes sends the client the item (the same BuyRobuxItem intent the Store
-- screen sends; MonetizationService checks it and shows Roblox's prompt)
-- and the box goes back to its shelf. No cash moves here.
--
-- One connection on BoxOpen. The handler budgets the call, then opens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AxeArt = require(ReplicatedStorage.Shared.Art.AxeArt)
local BoxArt = require(ReplicatedStorage.Shared.Art.BoxArt)
local BoxLogic = require(ReplicatedStorage.Shared.BoxLogic)
local BoxSize = require(ReplicatedStorage.Shared.BoxSize)
local BoxUnpack = require(ReplicatedStorage.Shared.BoxUnpack)
local CounterLogic = require(ReplicatedStorage.Shared.CounterLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local RobuxShelf = require(ReplicatedStorage.Shared.RobuxShelf)
local ShopHoursLogic = require(ReplicatedStorage.Shared.ShopHoursLogic)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local StoreStock = require(ReplicatedStorage.Shared.StoreStock)
local Util = require(ReplicatedStorage.Shared.Util)
local LeaveCommit = require(script.Parent.LeaveCommit)
local ProfileSchema = require(script.Parent.ProfileSchema)
local RateLimiter = require(script.Parent.RateLimiter)

local BoxService = {}

type BoxGrant = {
	uid: string,
	kind: string,
	itemId: string,
	limited: boolean?,
	shop: string?,
	free: boolean?,
	deferGrant: boolean?,
}

BoxService.Group = "Boxes"

export type Record = {
	uid: string,
	slotId: string,
	shop: string,
	itemKind: string,
	itemId: string,
	displayName: string,
	limited: boolean,
	price: number,
	paid: boolean,
	buyerId: number,
	opened: boolean,
	onShelf: boolean,
	claimUserId: number,
	claimUntil: number,
	outsideStreak: number,
	noted: boolean,
	equipped: boolean,
	axeUid: string?,
	pendingGrant: boolean?, -- paid, but the item is still in the box (BoxUnpack)
	robux: { kind: string, key: string }?,
	home: CFrame,
	zoneCf: CFrame?,
	zoneSize: Vector3?,
	counter: BasePart?,
	model: Model?,
	part: BasePart?,
}

export type MakeOptions = {
	uid: string?,
	slotId: string?,
	shop: string?,
	itemKind: string?,
	itemId: string?,
	displayName: string?,
	limited: boolean?,
	price: number?,
	cf: CFrame?,
	parent: Instance?,
	counter: BasePart?,
	zoneCf: CFrame?,
	zoneSize: Vector3?,
	onShelf: boolean?,
	size: Vector3?,
	robux: { kind: string, key: string }?,
}

type Home = {
	cf: CFrame,
	parent: Instance?,
	counter: BasePart?,
	zoneCf: CFrame?,
	zoneSize: Vector3?,
	slot: StoreStock.Slot,
	price: number,
}

type ShopAnchor = {
	counter: BasePart?,
	zoneCf: CFrame?,
	zoneSize: Vector3?,
	parent: Instance?,
}

local records: { [string]: Record } = {}

-- An item that has come out of its box and waits to be picked up.
type Pickup = {
	uid: string,
	model: Model,
	buyerId: number,
	kind: string,
	itemId: string,
	shop: string,
	limited: boolean,
	madeAt: number,
	taken: boolean,
}
local pickups: { [string]: Pickup } = {}
local entered: { [string]: { string } } = {}
local respawnAt: { [string]: number } = {}
local homes: { [string]: Home } = {}
local skips: { [number]: { [string]: boolean } } = {}
local restored: { [number]: boolean } = {}
local stocked: { [Instance]: boolean } = {}
local rememberedShops: { [string]: ShopAnchor } = {}
local signStock: TextLabel? = nil
local signClock: TextLabel? = nil
local bound = false
local chained = false
local leftHook = false
local acc = 0

BoxService.Speaker = function(_player: Player, _line: string, _rec: Record?) end
BoxService.OnToast = function(_player: Player, _message: string) end

function BoxService.Toast(player: Player, message: string)
	BoxService.OnToast(player, message)
end

local function speak(player: Player, line: string, rec: Record?)
	BoxService.Speaker(player, line, rec)
end

local function profileOf(player: Player): any
	local ok, service = pcall(function()
		return require(script.Parent.ProfileService)
	end)
	if not ok or service == nil then
		return nil
	end
	return service.GetProfile(player)
end

local function unitPrice(kind: string, itemId: string, limited: boolean): number
	local loop = 2
	local ok, shop = pcall(function()
		return require(script.Parent.ShopService)
	end)
	if ok and shop ~= nil and type(shop.Loop) == "function" then
		loop = shop.Loop()
	end
	return StoreStock.UnitPrice(kind, itemId, limited, loop) or 0
end

local function colorOf(hex: string?): Color3
	if type(hex) ~= "string" then
		return Color3.fromRGB(196, 148, 90)
	end
	local h = string.gsub(hex, "#", "")
	return Color3.fromRGB(
		tonumber(string.sub(h, 1, 2), 16) or 196,
		tonumber(string.sub(h, 3, 4), 16) or 148,
		tonumber(string.sub(h, 5, 6), 16) or 90
	)
end

local function rootPosition(player: Player): Vector3?
	local char = player.Character
	if char == nil then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp == nil then
		return nil
	end
	if typeof(hrp) == "Instance" and hrp:IsA("BasePart") then
		return hrp.CFrame.Position
	end
	local pos = (hrp :: any).Position
	if typeof(pos) == "Vector3" then
		return pos
	end
	return nil
end

local function recordByModel(model: Model): Record?
	local uid = model:GetAttribute("BoxUid")
	if type(uid) ~= "string" then
		return nil
	end
	return records[uid]
end

local function uidFrom(action: unknown): string?
	if type(action) == "string" then
		return action
	end
	if typeof(action) ~= "Instance" then
		return nil
	end
	local inst = action :: Instance
	local attr = inst:GetAttribute("BoxUid")
	if type(attr) == "string" then
		return attr
	end
	local parent = inst.Parent
	if parent then
		local parentAttr = parent:GetAttribute("BoxUid")
		if type(parentAttr) == "string" then
			return parentAttr
		end
	end
	return nil
end

function BoxService.Get(uid: string): Record?
	return records[uid]
end

function BoxService.Each(): { Record }
	local out: { Record } = {}
	for _, rec in pairs(records) do
		table.insert(out, rec)
	end
	return out
end

function BoxService.UnpaidOffShelf(userId: number): (number, number)
	local mine, all = 0, 0
	for _, rec in pairs(records) do
		if not rec.paid and not rec.onShelf and not rec.opened then
			all += 1
			if rec.claimUserId == userId then
				mine += 1
			end
		end
	end
	return mine, all
end

function BoxService.InCounter(rec: Record): boolean
	local counter = rec.counter
	local part = rec.part
	if counter == nil or part == nil then
		return false
	end
	return CounterLogic.InZone(part.CFrame.Position, counter.CFrame, counter.Size)
end

function BoxService.NoteZones()
	for _, rec in pairs(records) do
		if not rec.noted and not rec.paid and BoxService.InCounter(rec) then
			local list = entered[rec.shop]
			if list == nil then
				list = {}
				entered[rec.shop] = list
			end
			table.insert(list, rec.uid)
			rec.noted = true
		end
	end
end

function BoxService.QueueItems(shop: string, userId: number): { CounterLogic.Queued }
	local skip = skips[userId]
	local items: { CounterLogic.Queued } = {}
	for _, uid in ipairs(entered[shop] or {}) do
		local rec = records[uid]
		if rec and not rec.paid and not rec.opened and not (skip ~= nil and skip[uid] == true) then
			table.insert(items, { uid = uid, inZone = BoxService.InCounter(rec) })
		end
	end
	return items
end

function BoxService.Offered(player: Player, shop: string): string?
	BoxService.NoteZones()
	return CounterLogic.Offer(CounterLogic.Queue(BoxService.QueueItems(shop, player.UserId)))
end

function BoxService.Decline(player: Player, uid: string)
	if records[uid] == nil then
		return -- B15: only a box that exists; a made-up id would grow the map
	end
	local map = skips[player.UserId]
	if map == nil then
		map = {}
		skips[player.UserId] = map
	end
	map[uid] = true
end

function BoxService.NoteSold(slotId: string, now: number)
	local slot = StoreStock.Get(slotId)
	if slot ~= nil and slot.limited then
		return
	end
	respawnAt[slotId] = now + GameConfig.BoxRespawnSec
end

function BoxService.ClearRespawn(slotId: string)
	respawnAt[slotId] = nil
end

function BoxService.RespawnDue(now: number): { string }
	local out: { string } = {}
	for id, at in pairs(respawnAt) do
		if now >= at then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

function BoxService.RememberShop(shop: string, anchor: ShopAnchor)
	rememberedShops[shop] = anchor
end

local onBoxOpen: (Player, unknown) -> ()

-- Roblox sets a pass's or pack's price. The server asks once, then the tag
-- over each Robux box says it (until then, only R$).
local robuxPrices: { [string]: number } = {}
local robuxAsked: { [string]: boolean } = {}

function BoxService.RobuxPrice(kind: string, key: string): number?
	return robuxPrices[kind .. ":" .. key]
end

local function refreshRobuxTags(kind: string, key: string, price: number)
	local text = RobuxShelf.Tag(price)
	local tag = BoxLogic.PriceTag(text)
	for _, rec in pairs(records) do
		local part = rec.part
		if part ~= nil and rec.robux ~= nil and rec.robux.kind == kind and rec.robux.key == key then
			local board = part:FindFirstChild("PriceTag")
			if board ~= nil and board:IsA("BillboardGui") then
				board.Size = UDim2.fromOffset(math.max(80, #tag.text * tag.textSize), tag.textSize + 10)
				local label = board:FindFirstChild("Price")
				if label ~= nil and label:IsA("TextLabel") then
					label.Text = text
				end
			end
		end
	end
end

function BoxService.AskRobuxPrice(kind: string, key: string)
	local cacheKey = kind .. ":" .. key
	if robuxAsked[cacheKey] then
		return
	end
	robuxAsked[cacheKey] = true
	local id = 0
	if kind == "Pass" then
		local pass = StoreData.Pass(key)
		id = if pass then pass.id else 0
	else
		local product = StoreData.Product(key)
		id = if product then product.id else 0
	end
	if not StoreData.IsForSale(id) then
		return
	end
	-- Not in tests (no Marketplace there) and never a reason to fail a build.
	pcall(function()
		task.spawn(function()
			local ok, info = pcall(function(): any
				local market = game:GetService("MarketplaceService")
				local infoType = if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
				return market:GetProductInfo(id, infoType)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				robuxPrices[cacheKey] = info.PriceInRobux
				refreshRobuxTags(kind, key, info.PriceInRobux)
			end
		end)
	end)
end

local function dress(rec: Record, part: BasePart, tint: Color3)
	local faces = BoxLogic.LargestFaces(part.Size)
	for _, face in ipairs(faces) do
		local mark = Instance.new("Decal")
		mark.Name = "ItemMark"
		mark.Face = face
		mark.Color3 = tint
		mark.Parent = part
	end
	local tagText = if rec.robux ~= nil
		then RobuxShelf.Tag(BoxService.RobuxPrice(rec.robux.kind, rec.robux.key))
		else Util.formatCash(rec.price)
	local tag = BoxLogic.PriceTag(tagText)
	local board = Instance.new("BillboardGui")
	board.Name = "PriceTag"
	board.AlwaysOnTop = tag.alwaysOnTop
	board.MaxDistance = tag.maxDistance
	board.Size = UDim2.fromOffset(math.max(80, #tag.text * tag.textSize), tag.textSize + 10)
	board.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.2, 0)
	board.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Price"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = tag.text
	label.TextSize = tag.textSize
	label.TextColor3 = Color3.fromRGB(245, 235, 215)
	label.TextScaled = false
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.None
	label.Parent = board

	local buy = Instance.new("ProximityPrompt")
	buy.Name = "BuyPrompt"
	buy.ActionText = "Buy"
	buy.ObjectText = rec.displayName
	buy.MaxActivationDistance = GameConfig.CounterPayReach
	buy.HoldDuration = 0
	buy.Enabled = false
	buy.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	buy:SetAttribute("TapPx", BoxLogic.PayTapPx)
	InputKit.PromptDefaults(buy, "Buy")
	buy.Parent = part
	local uid = rec.uid
	-- Lune's prompt has no Triggered. In the engine it does, and that tap pays.
	pcall(function()
		buy.Triggered:Connect(function(player: Player)
			BoxService.Pay(player, uid)
		end)
	end)

	local open = Instance.new("ProximityPrompt")
	open.Name = "OpenPrompt"
	open.ActionText = "Open"
	open.ObjectText = rec.displayName
	open.MaxActivationDistance = BoxLogic.OpenRange
	open.HoldDuration = 0
	open.Enabled = false
	open.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	InputKit.PromptDefaults(open, "Interact")
	open.RequiresLineOfSight = false
	open.Parent = part
	pcall(function()
		open.Triggered:Connect(function(player: Player)
			onBoxOpen(player, uid)
		end)
	end)
end

function BoxService.Make(opts: MakeOptions): Record
	local kind = opts.itemKind or "Axe"
	local itemId = opts.itemId or "SteelAxe"
	local limited = opts.limited == true
	local slot = if opts.slotId then StoreStock.Get(opts.slotId) else StoreStock.Find(kind, itemId)
	if slot == nil and (opts.shop == "Dealership" or kind == "Truck" or kind == "Trailer") then
		slot = StoreStock.Vehicle(itemId)
	end
	-- A Robux box is a display: no cash unit, no stock. A shelf-like slot
	-- stands in for it so it has a home to go back to.
	local robux = opts.robux
	if robux ~= nil then
		kind = "Robux"
		itemId = robux.key
		limited = false
		slot = {
			slotId = opts.slotId or RobuxShelf.SlotId(robux.kind, robux.key),
			shop = opts.shop or "ToolShed",
			itemKind = "Robux",
			itemId = robux.key,
			displayName = opts.displayName or robux.key,
			respawnSec = GameConfig.BoxRespawnSec,
			limited = false,
			color = RobuxShelf.Gold,
			boxClass = RobuxShelf.Class,
		}
	end
	local uid = opts.uid or Util.guid()
	local cf = opts.cf or CFrame.new()
	local price = opts.price
	if robux ~= nil then
		price = 0
	elseif price == nil then
		price = unitPrice(kind, itemId, limited or (slot ~= nil and slot.limited))
	end
	local model = Instance.new("Model")
	model.Name = "ShopItem"
	local part = Instance.new("Part")
	part.Name = "Box"
	local boxSize = opts.size
	if boxSize == nil then
		if robux ~= nil then
			boxSize = BoxSize.Class(RobuxShelf.Class).size
		elseif slot ~= nil then
			boxSize = StoreStock.BoxSizeOf(slot)
		else
			boxSize = BoxSize.Class(BoxSize.DefaultClass).size
		end
	end
	part.Size = boxSize :: Vector3
	part.Anchored = true
	part.CanCollide = true
	part.CFrame = cf
	local itemColor = colorOf(if slot then slot.color else nil)
	part.Color = itemColor
	part.CollisionGroup = BoxService.Group
	part.Parent = model
	model.PrimaryPart = part
	model:SetAttribute("BoxUid", uid)
	part:SetAttribute("BoxUid", uid)
	local rec: Record = {
		uid = uid,
		slotId = opts.slotId or (if slot then slot.slotId else uid),
		shop = opts.shop or (if slot then slot.shop else "ToolShed"),
		itemKind = kind,
		itemId = itemId,
		displayName = opts.displayName or (if slot then slot.displayName else itemId),
		limited = limited or (slot ~= nil and slot.limited),
		price = price :: number,
		paid = false,
		buyerId = 0,
		opened = false,
		onShelf = opts.onShelf ~= false,
		claimUserId = 0,
		claimUntil = 0,
		outsideStreak = 0,
		noted = false,
		equipped = false,
		robux = robux,
		home = cf,
		zoneCf = opts.zoneCf,
		zoneSize = opts.zoneSize,
		counter = opts.counter,
		model = model,
		part = part,
	}
	records[uid] = rec
	dress(rec, part, if robux ~= nil then colorOf(RobuxShelf.GoldInk) else itemColor)
	-- The packaging: kraft body, tape in the item's colour, a label with its
	-- name, the category stripe, trim, and a label on the aisle side.
	local relX: number? = nil
	if opts.counter ~= nil then
		relX = cf.Position.X - opts.counter.CFrame.Position.X
	end
	BoxArt.Dress(model, part, {
		name = rec.displayName,
		kind = rec.itemKind,
		color = itemColor,
		gold = robux ~= nil,
		side = if relX ~= nil then BoxArt.AisleSide(relX) else nil,
	})
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = BoxService.Group
		end
	end
	if robux ~= nil then
		BoxService.AskRobuxPrice(robux.kind, robux.key)
	end
	if opts.parent then
		model.Parent = opts.parent
	end
	pcall(function()
		game:GetService("CollectionService"):AddTag(model, "ShopBox")
	end)
	if rec.onShelf and homes[rec.slotId] == nil and slot ~= nil then
		homes[rec.slotId] = {
			cf = cf,
			parent = opts.parent,
			counter = opts.counter,
			zoneCf = opts.zoneCf,
			zoneSize = opts.zoneSize,
			slot = slot,
			price = rec.price,
		}
	end
	BoxService.RefreshPrompts()
	return rec
end

local function shopHour(): number
	local okShop, shop = pcall(function()
		return require(script.Parent.ShopService)
	end)
	if okShop and type(shop) == "table" and type(shop.Hour) == "function" then
		return shop.Hour()
	end
	return ShopHoursLogic.FallbackHour
end

function BoxService.RefreshPrompts()
	BoxService.NoteZones()
	local hour = shopHour()
	for _, rec in pairs(records) do
		local part = rec.part
		if part == nil then
			continue
		end
		local buy = part:FindFirstChild("BuyPrompt")
		local openPrompt = part:FindFirstChild("OpenPrompt")
		if buy and buy:IsA("ProximityPrompt") then
			local open = ShopHoursLogic.IsOpen(rec.shop, hour)
			buy.Enabled = not rec.paid and not rec.opened and BoxService.InCounter(rec) and open
		end
		if openPrompt and openPrompt:IsA("ProximityPrompt") then
			openPrompt.Enabled = rec.paid and not rec.opened
		end
	end
end

function BoxService.DestroyRecord(uid: string)
	local rec = records[uid]
	if rec == nil then
		return
	end
	if rec.model then
		rec.model:Destroy()
	end
	records[uid] = nil
end

function BoxService.ReturnHome(rec: Record)
	local model = rec.model
	if model then
		pcall(function()
			require(script.Parent.GrabService).ReleasePiece(model, "returned")
		end)
	end
	rec.onShelf = true
	rec.claimUserId = 0
	rec.claimUntil = 0
	rec.outsideStreak = 0
	rec.noted = false
	local part = rec.part
	if part then
		part.Anchored = true
		part.CFrame = rec.home
		pcall(function()
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end)
	end
	if model then
		model:PivotTo(rec.home)
	end
	if not rec.limited then
		BoxService.ClearRespawn(rec.slotId)
	end
	BoxService.RefreshPrompts()
end

function BoxService.Judge(_now: number)
	for _, rec in pairs(records) do
		if rec.paid or rec.onShelf or rec.part == nil then
			continue
		end
		if rec.zoneCf == nil or rec.zoneSize == nil then
			rec.outsideStreak = 0
			continue
		end
		local inside = BoxLogic.InsideVolume(rec.part.CFrame.Position, rec.zoneCf, rec.zoneSize)
		rec.outsideStreak = BoxLogic.OutsideStreak(inside, rec.outsideStreak)
		if BoxLogic.ShouldReturn(rec.outsideStreak) then
			BoxService.ReturnHome(rec)
		end
	end
	BoxService.RefreshPrompts()
end

local function shelfBusy(slotId: string): boolean
	for _, rec in pairs(records) do
		if rec.slotId == slotId and rec.onShelf and not rec.paid then
			return true
		end
	end
	return false
end

local function spawnHome(slotId: string)
	local home = homes[slotId]
	if home == nil then
		return
	end
	local n = 0
	for _, rec in pairs(records) do
		if rec.slotId == slotId and not rec.opened then
			n += 1
		end
	end
	local slot = home.slot
	local cf = home.cf * CFrame.new(0, 0, (n % 3 - 1) * 1.3)
	BoxService.Make({
		slotId = slotId,
		shop = slot.shop,
		itemKind = slot.itemKind,
		itemId = slot.itemId,
		displayName = slot.displayName,
		limited = slot.limited,
		price = home.price,
		cf = cf,
		parent = home.parent,
		counter = home.counter,
		zoneCf = home.zoneCf,
		zoneSize = home.zoneSize,
		onShelf = true,
	})
end

local function unpaidLimited(): number
	local n = 0
	for _, rec in pairs(records) do
		if rec.limited and not rec.paid and not rec.opened then
			n += 1
		end
	end
	return n
end

function BoxService.Refill(now: number)
	StoreStock.Restock(now)
	for _, slotId in ipairs(BoxService.RespawnDue(now)) do
		if not shelfBusy(slotId) then
			spawnHome(slotId)
			if homes[slotId] ~= nil then
				BoxService.ClearRespawn(slotId)
			end
		end
	end
	local lamp = homes["hearth-LampPost"]
	if lamp ~= nil then
		local need = StoreStock.Left() - unpaidLimited()
		for _ = 1, math.max(0, need) do
			spawnHome("hearth-LampPost")
		end
	end
	BoxService.RefreshSign(now)
end

function BoxService.RefreshSign(now: number)
	if signStock == nil or signClock == nil then
		return
	end
	local left, clock = StoreStock.SignNow(now)
	signStock.Text = left
	signClock.Text = clock
end

local function attachSign(counter: BasePart, host: Attachment)
	local board = Instance.new("BillboardGui")
	board.Name = "LimitedSign"
	board.AlwaysOnTop = false
	board.MaxDistance = 40
	board.Size = UDim2.fromOffset(180, 48)
	local world = counter.CFrame:PointToWorldSpace(host.Position)
	board.StudsOffset = world - counter.CFrame.Position + Vector3.new(0, 2.2, 0)
	board.Parent = counter
	local stock = Instance.new("TextLabel")
	stock.Name = "Stock"
	stock.BackgroundTransparency = 1
	stock.Size = UDim2.fromScale(1, 0.5)
	stock.Font = Enum.Font.GothamBold
	stock.TextSize = 16
	stock.TextColor3 = Color3.fromRGB(245, 235, 215)
	stock.TextXAlignment = Enum.TextXAlignment.Center
	stock.TextTruncate = Enum.TextTruncate.None
	stock.Parent = board
	local clock = Instance.new("TextLabel")
	clock.Name = "Timer"
	clock.BackgroundTransparency = 1
	clock.Position = UDim2.fromScale(0, 0.5)
	clock.Size = UDim2.fromScale(1, 0.5)
	clock.Font = Enum.Font.Gotham
	clock.TextSize = 14
	clock.TextColor3 = Color3.fromRGB(245, 235, 215)
	clock.TextXAlignment = Enum.TextXAlignment.Center
	clock.TextTruncate = Enum.TextTruncate.None
	clock.Parent = board
	signStock = stock
	signClock = clock
	BoxService.RefreshSign(os.clock())
end

local function zoneOf(model: Model): (CFrame?, Vector3?)
	local bx = model:GetAttribute("BuildPivotX")
	local sx = model:GetAttribute("ZoneSizeX")
	if type(bx) ~= "number" or type(sx) ~= "number" then
		return nil, nil
	end
	local by = model:GetAttribute("BuildPivotY")
	local bz = model:GetAttribute("BuildPivotZ")
	local sy = model:GetAttribute("ZoneSizeY")
	local sz = model:GetAttribute("ZoneSizeZ")
	if type(by) ~= "number" or type(bz) ~= "number" or type(sy) ~= "number" or type(sz) ~= "number" then
		return nil, nil
	end
	local cx = model:GetAttribute("ZoneCenterX")
	local cy = model:GetAttribute("ZoneCenterY")
	local cz = model:GetAttribute("ZoneCenterZ")
	local toWorld = BoxLogic.BuildToWorld(model:GetPivot(), Vector3.new(bx, by, bz))
	local center = Vector3.new(
		if type(cx) == "number" then cx else 0,
		if type(cy) == "number" then cy else 0,
		if type(cz) == "number" then cz else 0
	)
	return toWorld * CFrame.new(center), Vector3.new(sx, sy, sz)
end

function BoxService.StockShop(model: Model)
	if stocked[model] then
		return
	end
	local counterInst = model:FindFirstChild("Counter")
	if counterInst == nil or not counterInst:IsA("BasePart") then
		return
	end
	local counter = counterInst :: BasePart
	stocked[model] = true
	local shop = model.Name
	local zoneCf, zoneSize = zoneOf(model)
	rememberedShops[shop] = { counter = counter, zoneCf = zoneCf, zoneSize = zoneSize, parent = model }
	local signHost: Attachment? = nil
	for _, child in ipairs(counter:GetChildren()) do
		if child.Name == "ShelfSlot" and child:IsA("Attachment") then
			local slotId = child:GetAttribute("SlotId")
			local slot = if type(slotId) == "string" then StoreStock.Get(slotId) else nil
			if slot and type(slotId) == "string" then
				local count = if slot.limited then GameConfig.LimitedStockCount else 1
				for i = 1, count do
					local base = counter.CFrame:PointToWorldSpace(child.Position)
					local along = (i - (count + 1) / 2) * BoxSize.Pitch(StoreStock.BoxSizeOf(slot).Z)
					local shift = counter.CFrame:VectorToWorldSpace(Vector3.new(0, 0, along))
					BoxService.Make({
						slotId = slot.slotId,
						shop = slot.shop,
						itemKind = slot.itemKind,
						itemId = slot.itemId,
						displayName = slot.displayName,
						limited = slot.limited,
						cf = CFrame.new(base + shift),
						parent = model,
						counter = counter,
						zoneCf = zoneCf,
						zoneSize = zoneSize,
						onShelf = true,
					})
				end
				if slot.limited then
					signHost = child
				end
			end
		end
	end
	if signHost then
		attachSign(counter, signHost)
	end
	for _, child in ipairs(counter:GetChildren()) do
		if child.Name == "RobuxSlot" and child:IsA("Attachment") then
			local slotId = child:GetAttribute("SlotId")
			local entry = if type(slotId) == "string" then RobuxShelf.Get(slotId) else nil
			if entry then
				BoxService.Make({
					slotId = entry.slotId,
					shop = shop,
					displayName = entry.displayName,
					robux = { kind = entry.kind, key = entry.key },
					cf = CFrame.new(counter.CFrame:PointToWorldSpace(child.Position)),
					parent = model,
					counter = counter,
					zoneCf = zoneCf,
					zoneSize = zoneSize,
					onShelf = true,
				})
			end
		end
	end
end

function BoxService.StockLot(lot: Model, counter: BasePart?)
	if stocked[lot] then
		return
	end
	stocked[lot] = true
	if counter then
		rememberedShops["Dealership"] = {
			counter = counter,
			zoneCf = nil,
			zoneSize = nil,
			parent = lot,
		}
	end
	if type((lot :: any).GetDescendants) ~= "function" then
		return
	end
	for _, child in ipairs(lot:GetDescendants()) do
		if child.Name == "BoxSpot" and child:IsA("BasePart") then
			local itemId = child:GetAttribute("ItemId")
			local kind = child:GetAttribute("Category")
			if type(itemId) == "string" and (kind == "Truck" or kind == "Trailer") then
				local vehicle = StoreStock.Vehicle(itemId)
				BoxService.Make({
					slotId = if vehicle then vehicle.slotId else nil,
					shop = "Dealership",
					itemKind = if vehicle then vehicle.itemKind else kind,
					itemId = itemId,
					displayName = if vehicle then vehicle.displayName else itemId,
					cf = child.CFrame,
					size = child.Size,
					parent = lot,
					counter = counter,
					onShelf = true,
				})
			end
		end
	end
end

function BoxService.StockMap(map: Instance)
	for _, name in ipairs({ "ToolShed", "HearthAndHome" }) do
		local model = map:FindFirstChild(name)
		if model and model:IsA("Model") then
			BoxService.StockShop(model)
		end
	end
	local lot = map:FindFirstChild("DealershipLot")
	if lot and lot:IsA("Model") then
		local deal = map:FindFirstChild("Dealership")
		local counterInst = if deal then deal:FindFirstChild("Counter") else nil
		local counter = if counterInst and counterInst:IsA("BasePart") then counterInst else nil
		BoxService.StockLot(lot, counter)
	end
end

function BoxService.Pay(player: Player, uid: string): (boolean, string)
	local rec = records[uid]
	if rec == nil or rec.opened then
		speak(player, "missing", rec)
		return false, "missing"
	end
	if rec.paid then
		speak(player, "thanks", rec)
		return false, "thanks"
	end
	if not BoxService.InCounter(rec) then
		speak(player, "missing", rec)
		return false, "missing"
	end
	local pos = rootPosition(player)
	local part = rec.part
	local reach = GameConfig.CounterPayReach + GameConfig.RangeTolerance
	if pos == nil or part == nil or (pos - part.CFrame.Position).Magnitude > reach then
		speak(player, "missing", rec)
		return false, "missing"
	end
	if rec.robux ~= nil then
		-- Not for cash. Only an item the shelf lists goes on to Roblox; the
		-- card carries it to the client, which sends BuyRobuxItem, and
		-- MonetizationService does the rest. The box goes back to its shelf.
		if RobuxShelf.Find(rec.robux.kind, rec.robux.key) == nil then
			speak(player, "locked", rec)
			return false, "locked"
		end
		speak(player, "robuxAsk", rec)
		BoxService.ReturnHome(rec)
		return true, "robuxAsk"
	end
	if BoxUnpack.OneAtATime(rec.itemKind, rec.itemId) then
		-- Two unopened boxes of the same gear or blueprint would grant it twice.
		for _, other in pairs(records) do
			if
				other ~= rec
				and other.paid
				and not other.opened
				and other.pendingGrant == true
				and other.buyerId == player.UserId
				and other.itemKind == rec.itemKind
				and other.itemId == rec.itemId
			then
				speak(player, "alreadyOwned", rec)
				return false, "alreadyOwned"
			end
		end
	end
	local shop = require(script.Parent.ShopService)
	local ok, line, axeUid = shop.ChargeAndGrant(player, {
		uid = rec.uid,
		kind = rec.itemKind,
		itemId = rec.itemId,
		limited = rec.limited,
		shop = rec.shop,
		deferGrant = true, -- the buyer is handed the box; the item comes out when it is opened
	})
	if ok then
		rec.pendingGrant = BoxUnpack.Mode(rec.itemKind) ~= "vehicle"
		rec.paid = true
		rec.buyerId = player.UserId
		rec.onShelf = false
		rec.axeUid = axeUid
		if not rec.limited then
			BoxService.NoteSold(rec.slotId, os.clock())
		end
		BoxService.RefreshPrompts()
		BoxService.RefreshSign(os.clock())
	end
	speak(player, line, rec)
	return ok, line
end

local function dropStorage(player: Player, uid: string)
	local profile = profileOf(player)
	if profile == nil or type(profile.storage) ~= "table" then
		return
	end
	local kept = {}
	for _, entry in ipairs(profile.storage) do
		if type(entry) ~= "table" or entry.uid ~= uid then
			table.insert(kept, entry)
		end
	end
	profile.storage = kept
	-- A freed slot can hold a truck that was waiting because storage was full.
	ProfileSchema.MintTruckBoxes(profile)
end

local function findTool(player: Player, axeUid: string?): Tool?
	if axeUid == nil then
		return nil
	end
	local function scan(container: Instance?): Tool?
		if container == nil or type((container :: any).GetChildren) ~= "function" then
			return nil
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("AxeUid") == axeUid then
				return child
			end
		end
		return nil
	end
	local backpack = if type((player :: any).FindFirstChild) == "function"
		then player:FindFirstChild("Backpack")
		else nil
	return scan(backpack) or scan(player.Character)
end

local function equipOnce(player: Player, rec: Record)
	if rec.equipped or rec.itemKind ~= "Axe" then
		return
	end
	rec.equipped = true
	local tool = findTool(player, rec.axeUid)
	if tool == nil then
		return
	end
	local char = player.Character
	if char == nil or type((char :: any).FindFirstChildOfClass) ~= "function" then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid and type((humanoid :: any).EquipTool) == "function" then
		humanoid:EquipTool(tool)
	end
end

-- The empty box folds away: the Poof attribute starts the clients' fold,
-- the prompts go, and the model is destroyed PoofSeconds later.
local function poof(rec: Record)
	local model = rec.model
	rec.model = nil
	rec.part = nil
	if model == nil then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d.Enabled = false
		end
	end
	model:SetAttribute("Poof", true)
	local ok = pcall(function()
		task.delay(BoxUnpack.PoofSeconds, function()
			model:Destroy()
		end)
	end)
	if not ok then
		model:Destroy()
	end
end

local function grantBox(rec: Record): BoxGrant
	return {
		uid = rec.uid,
		kind = rec.itemKind,
		itemId = rec.itemId,
		limited = rec.limited,
		shop = rec.shop,
	}
end

-- The item as a physical object where the box stood: an axe lying there, or
-- a small parcel of goods. The buyer takes it with Interact.
local function pickupModel(rec: Record, at: Vector3): Model
	local model: Model
	local axe = if rec.itemKind == "Axe" then ItemCatalog.GetAxe(rec.itemId) else nil
	if axe then
		model = AxeArt.Dropped(axe)
		model:PivotTo(CFrame.new(at + Vector3.new(0, BoxUnpack.PickupLift, 0)))
	else
		model = Instance.new("Model")
		local item = Instance.new("Part")
		item.Name = "Item"
		item.Size = Vector3.new(1.6, 1.6, 1.6)
		item.Anchored = true
		item.CanCollide = false
		item.CFrame = CFrame.new(at + Vector3.new(0, BoxUnpack.PickupLift, 0)) * CFrame.Angles(0.4, 0.6, 0)
		item.Color = colorOf(if rec.itemKind == "Gear" or rec.itemKind == "Cosmetic" then "#E6C36A" else "#C8A06B")
		item.Material = Enum.Material.SmoothPlastic
		item.Parent = model
		model.PrimaryPart = item
	end
	model.Name = "BoxPickup"
	return model
end

local function spawnPickup(player: Player, rec: Record, at: Vector3)
	local model = pickupModel(rec, at)
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	model:SetAttribute("PickupUid", rec.uid)
	model:SetAttribute("BuyerId", player.UserId)
	if anchor then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TakePrompt"
		prompt.ActionText = "Pick up"
		prompt.ObjectText = rec.displayName
		prompt.MaxActivationDistance = BoxUnpack.TakeRange
		prompt.HoldDuration = 0
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt:SetAttribute("TapPx", BoxLogic.PayTapPx)
		InputKit.PromptDefaults(prompt, "Interact")
		prompt.Parent = anchor
		local uid = rec.uid
		pcall(function()
			prompt.Triggered:Connect(function(who: Player)
				BoxService.TakePickup(who, uid)
			end)
		end)
	end
	model.Parent = if rec.counter ~= nil and rec.counter.Parent ~= nil then rec.counter.Parent else workspace
	pickups[rec.uid] = {
		uid = rec.uid,
		model = model,
		buyerId = player.UserId,
		kind = rec.itemKind,
		itemId = rec.itemId,
		shop = rec.shop,
		limited = rec.limited,
		madeAt = os.clock(),
		taken = false,
	}
end

-- Hands the pickup's item over (once) and removes the object. `who` is the
-- player to give it to; nil converts it for an owner who is gone.
local function finishPickup(pickup: Pickup, who: Player?)
	if pickup.taken then
		return
	end
	pickup.taken = true
	pickups[pickup.uid] = nil
	local target = who
	if target ~= nil then
		local shop = require(script.Parent.ShopService)
		shop.GrantItem(target, {
			uid = pickup.uid,
			kind = pickup.kind,
			itemId = pickup.itemId,
			limited = pickup.limited,
			shop = pickup.shop,
		})
	end
	if pickup.model then
		pickup.model:Destroy()
	end
end

-- The buyer takes the item: validated here (owner, range, rate), granted once.
function BoxService.TakePickup(player: Player, uid: string): (boolean, string?)
	if not RateLimiter.Allow(player, "BoxTake") then
		return false, "rate"
	end
	local pickup = pickups[uid]
	if pickup == nil then
		return false, "gone"
	end
	local distance = math.huge
	local pos = rootPosition(player)
	local anchor = pickup.model.PrimaryPart or pickup.model:FindFirstChildWhichIsA("BasePart")
	if pos ~= nil and anchor ~= nil then
		distance = (pos - anchor.CFrame.Position).Magnitude
	end
	local ok, why = BoxUnpack.CanTake({
		userId = player.UserId,
		buyerId = pickup.buyerId,
		distance = distance,
		taken = pickup.taken,
	})
	if not ok then
		local message = BoxUnpack.TakeMessage(why)
		if message then
			BoxService.Toast(player, message)
		end
		return false, why
	end
	finishPickup(pickup, player)
	return true, nil
end

function BoxService.Pickups(): { [string]: Pickup }
	return pickups
end

-- A player leaves, or a pickup goes unclaimed: the item is converted into
-- the inventory so nothing is lost. Called with the pickup's owner if there.
function BoxService.ConvertPickups(userId: number?, now: number?, owner: Player?)
	local list: { Pickup } = {}
	for _, pickup in pairs(pickups) do
		local mine = userId ~= nil and pickup.buyerId == userId
		local stale = userId == nil and now ~= nil and BoxUnpack.Expired(now, pickup.madeAt)
		if mine or stale then
			table.insert(list, pickup)
		end
	end
	for _, pickup in ipairs(list) do
		local who: Player? = owner
		if who == nil then
			pcall(function()
				who = game:GetService("Players"):GetPlayerByUserId(pickup.buyerId)
			end)
		end
		finishPickup(pickup, who)
	end
end

function BoxService.TryOpen(player: Player, uid: string): (boolean, string?)
	local rec = records[uid]
	local promptUid: string? = nil
	if rec ~= nil and rec.part ~= nil then
		local attr = rec.part:GetAttribute("BoxUid")
		if type(attr) == "string" then
			promptUid = attr
		end
	end
	local distance = math.huge
	if rec ~= nil and rec.part ~= nil then
		local pos = rootPosition(player)
		if pos then
			distance = (pos - rec.part.CFrame.Position).Magnitude
		end
	end
	local ok, why = BoxLogic.CanOpen({
		userId = player.UserId,
		buyerId = if rec then rec.buyerId else 0,
		paid = rec ~= nil and rec.paid,
		opened = rec ~= nil and rec.opened,
		distance = distance,
		uid = if rec then rec.uid else nil,
		promptUid = promptUid,
	})
	if not ok or rec == nil then
		return false, why
	end
	local mode = BoxUnpack.Mode(rec.itemKind)
	if mode == "vehicle" then
		local VehicleService = require(script.Parent.VehicleService)
		local placed = VehicleService.TryPlaceFromBox(player, rec)
		if not placed then
			return false, "plot"
		end
	end
	local at = if rec.part then rec.part.CFrame.Position else Vector3.zero
	rec.opened = true
	dropStorage(player, uid)
	if BoxUnpack.Owed(rec.pendingGrant) then
		rec.pendingGrant = false
		if mode == "stock" then
			-- Plot items unpack straight into the buyer's stock (the hammer places them).
			local shop = require(script.Parent.ShopService)
			shop.GrantItem(player, grantBox(rec))
		elseif mode == "pickup" then
			spawnPickup(player, rec, at)
		end
		BoxService.Toast(player, BoxUnpack.OpenedLine(mode, rec.displayName))
	else
		-- A box paid for before this change: its item was granted at the counter.
		equipOnce(player, rec)
	end
	poof(rec)
	return true, nil
end

function onBoxOpen(player: Player, action: unknown)
	if not RateLimiter.Allow(player, "BoxOpen") then
		return
	end
	if type(action) ~= "string" and typeof(action) ~= "Instance" then
		return
	end
	local uid = uidFrom(action)
	if uid == nil then
		return
	end
	local opened, why = BoxService.TryOpen(player, uid)
	if not opened and why ~= nil then
		local message = BoxLogic.OpenMessage(why :: BoxLogic.OpenReason)
		if message then
			BoxService.Toast(player, message)
		end
	end
end

local function hasStored(storage: { any }, uid: string): boolean
	for _, entry in ipairs(storage) do
		if type(entry) == "table" and entry.uid == uid then
			return true
		end
	end
	return false
end

function BoxService.Commit(player: Player)
	local profile = profileOf(player)
	if profile ~= nil and type(profile.storage) ~= "table" then
		profile.storage = {}
	end
	local leaving: { string } = {}
	BoxService.ConvertPickups(player.UserId, nil, player)
	for uid, rec in pairs(records) do
		if not rec.paid and rec.claimUserId == player.UserId then
			BoxService.ReturnHome(rec)
		elseif rec.paid and not rec.opened and rec.buyerId == player.UserId then
			if profile ~= nil and type(profile.storage) == "table" and not hasStored(profile.storage, uid) then
				if #profile.storage < ProfileSchema.StorageCap then
					table.insert(
						profile.storage,
						BoxUnpack.StoredEntry(uid, rec.itemId, rec.shop, BoxUnpack.Owed(rec.pendingGrant))
					)
				elseif BoxUnpack.Owed(rec.pendingGrant) then
					-- No room to keep the box: hand the item over instead of losing it.
					rec.pendingGrant = false
					local shop = require(script.Parent.ShopService)
					shop.GrantItem(player, grantBox(rec))
				end
			end
			table.insert(leaving, uid)
		end
	end
	for _, uid in ipairs(leaving) do
		BoxService.DestroyRecord(uid)
	end
end

function BoxService.Restore(player: Player, profile: any)
	if restored[player.UserId] then
		return
	end
	restored[player.UserId] = true
	local storage = profile.storage
	if type(storage) ~= "table" then
		return
	end
	for index, entry in ipairs(storage) do
		if type(entry) == "table" and type(entry.uid) == "string" and records[entry.uid] == nil then
			local shop = if type(entry.shop) == "string" then entry.shop else "ToolShed"
			local itemId = if type(entry.itemId) == "string" then entry.itemId else ""
			local slot = StoreStock.FindInShop(shop, itemId)
			if slot == nil and shop == "Dealership" then
				slot = StoreStock.Vehicle(itemId)
			end
			local anchor = rememberedShops[shop]
			local cf = CFrame.new(0, 4, 0)
			local counter = if anchor then anchor.counter else nil
			if counter then
				cf = counter.CFrame * CFrame.new((index - 1) * 1.2, counter.Size.Y / 2 + 1, 0)
			end
			local rec = BoxService.Make({
				uid = entry.uid,
				slotId = if slot then slot.slotId else entry.uid,
				shop = shop,
				itemKind = if slot then slot.itemKind else "Axe",
				itemId = if itemId ~= "" then itemId else "SteelAxe",
				displayName = if slot then slot.displayName else nil,
				limited = slot ~= nil and slot.limited,
				cf = cf,
				parent = if anchor then anchor.parent else nil,
				counter = counter,
				zoneCf = if anchor then anchor.zoneCf else nil,
				zoneSize = if anchor then anchor.zoneSize else nil,
				onShelf = false,
			})
			rec.paid = true
			rec.buyerId = player.UserId
			rec.onShelf = false
			-- Saved with `pending`: the item is still in the box. Older saves
			-- have no mark: their item was granted at the counter.
			rec.pendingGrant = entry.pending == true and BoxUnpack.Mode(rec.itemKind) ~= "vehicle"
		end
	end
	BoxService.RefreshPrompts()
end

function BoxService.FromPart(part: BasePart): any
	local node: Instance? = part
	for _ = 1, 6 do
		if node == nil then
			return nil
		end
		if node:IsA("Model") then
			local rec = recordByModel(node)
			if rec then
				return {
					model = rec.model,
					ownerId = 0,
					createdAt = 0,
					shopBox = true,
				}
			end
		end
		node = node.Parent
	end
	return nil
end

function BoxService.Facts(player: Player, piece: { model: Model }): any
	local rec = recordByModel(piece.model)
	if rec == nil then
		return nil
	end
	local mine, all = BoxService.UnpaidOffShelf(player.UserId)
	return {
		claimUserId = rec.claimUserId,
		claimUntil = rec.claimUntil,
		paid = rec.paid,
		buyerId = rec.buyerId,
		unpaidByPlayer = mine,
		unpaidOnServer = all,
		taking = rec.onShelf and not rec.paid,
	}
end

function BoxService.NoteGrab(player: Player, piece: { model: Model })
	local rec = recordByModel(piece.model)
	if rec == nil then
		return
	end
	rec.onShelf = false
	if not rec.paid then
		rec.claimUserId = player.UserId
		rec.claimUntil = BoxLogic.ClaimUntil(os.clock())
	end
end

function BoxService.ScanProfiles()
	local ok, players = pcall(function()
		return game:GetService("Players")
	end)
	if not ok or type((players :: any).GetPlayers) ~= "function" then
		return
	end
	for _, player in ipairs(players:GetPlayers()) do
		local profile = profileOf(player)
		if profile ~= nil then
			BoxService.Restore(player, profile)
		end
	end
end

function BoxService.Tick(dt: number)
	acc += dt
	if acc < BoxLogic.CheckInterval() then
		return
	end
	acc = 0
	local now = os.clock()
	BoxService.Judge(now)
	BoxService.ConvertPickups(nil, now)
	BoxService.Refill(now)
	BoxService.ScanProfiles()
end

function BoxService.Reset()
	local uids: { string } = {}
	for uid in pairs(records) do
		table.insert(uids, uid)
	end
	for _, uid in ipairs(uids) do
		BoxService.DestroyRecord(uid)
	end
	for _, pickup in pairs(pickups) do
		if pickup.model then
			pickup.model:Destroy()
		end
	end
	table.clear(pickups)
	table.clear(entered)
	table.clear(respawnAt)
	table.clear(homes)
	table.clear(skips)
	table.clear(restored)
	table.clear(stocked)
	table.clear(rememberedShops)
	signStock = nil
	signClock = nil
	acc = 0
end

local function registerGroup()
	local PhysicsService = game:GetService("PhysicsService")
	local isReg = (PhysicsService :: any).IsCollisionGroupRegistered
	local registered = type(isReg) == "function" and isReg(PhysicsService, BoxService.Group) == true
	if not registered then
		PhysicsService:RegisterCollisionGroup(BoxService.Group)
	end
	local set = (PhysicsService :: any).CollisionGroupSetCollidable
	if type(set) == "function" then
		set(PhysicsService, BoxService.Group, "Players", false)
	end
end

local function wire()
	if not chained then
		local ok, GrabService = pcall(function()
			return require(script.Parent.GrabService)
		end)
		if ok and GrabService ~= nil then
			GrabService.ChainResolver(function(part: BasePart): any
				return BoxService.FromPart(part)
			end)
			local prevHold = GrabService.Hooks.beforeHold
			GrabService.Hooks.beforeHold = function(player: Player, piece: any)
				if piece.shopBox and piece.model then
					for _, d in ipairs(piece.model:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Anchored = false
						end
					end
				end
				if prevHold then
					prevHold(player, piece)
				end
			end
			local prevGrab = GrabService.Hooks.onGrab
			GrabService.Hooks.onGrab = function(player: Player, piece: any)
				if piece.shopBox then
					BoxService.NoteGrab(player, piece)
					return
				end
				if prevGrab then
					prevGrab(player, piece)
				end
			end
			GrabService.Hooks.shopFacts = function(player: Player, piece: any)
				return BoxService.Facts(player, piece)
			end
			chained = true
		end
	end
	if chained and not leftHook then
		LeaveCommit.Add("shopBoxes", function(player: Player)
			BoxService.Commit(player)
		end)
		leftHook = true
		local RunService = game:GetService("RunService")
		local heartbeat = (RunService :: any).Heartbeat
		if type(heartbeat) == "table" and type(heartbeat.Connect) == "function" then
			heartbeat:Connect(function(dt: number)
				pcall(function()
					BoxService.Tick(dt)
				end)
			end)
		end
	end
	pcall(function()
		local Workspace = game:GetService("Workspace")
		if type(Workspace.FindFirstChild) ~= "function" then
			return
		end
		local map = Workspace:FindFirstChild("TimberlineMap")
		if map then
			BoxService.StockMap(map)
		end
		if type(Workspace.ChildAdded) == "table" and type(Workspace.ChildAdded.Connect) == "function" then
			Workspace.ChildAdded:Connect(function(child: Instance)
				if child.Name == "TimberlineMap" then
					BoxService.StockMap(child)
				end
			end)
		end
	end)
end

function BoxService.Init(remoteEvent: RemoteEvent?)
	if not bound and remoteEvent ~= nil then
		bound = true
		remoteEvent.OnServerEvent:Connect(onBoxOpen)
	end
	local ok, err = pcall(function()
		registerGroup()
		return nil
	end)
	if not ok then
		warn("[BoxService] Boxes collision group was not registered: " .. tostring(err))
	end
	pcall(wire)
end

return BoxService
