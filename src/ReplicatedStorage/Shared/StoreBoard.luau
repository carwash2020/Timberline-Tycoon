--!strict
-- StoreBoard: the town bulletin board that opens the Robux store (Lane P
-- redesign, the look Connor approved on 8 Oct 2026:
-- assets/store-board-mockup.jpg in the handoff pack).
--   * Two TimberBrown posts and an outer frame round a cork field, and a
--     PineTrim header plank reading TIMBERLINE in cream FredokaOne.
--   * One SignCream card per item Roblox says is for sale (StoreData
--     order), each with a brass pin, an art disc, the name, one short line
--     and a dark price pill. The server never writes a price: the pill says
--     "R$" and each player's client fills in their own Robux price
--     (StoreUI paints every StorePricePill) or "Owned".
--   * Items that aren't for sale get no card, only one weathered "Coming
--     soon" strip naming them along the bottom.
--   * The posters rebuild when the server's sale answers change
--     (StoreSaleService calls FillPosters on every StoreBoardPosters list).
--   * West of the spawn walk and of Old Bram's route, south of the street,
--     north of the tutorial grove and clear of Murph's camp. Persistent so
--     the prompt still works with StreamingEnabled. Only the posts and the
--     field collide. Two post lanterns light the cards after dark. At most
--     16 parts. Pure placement so tests can check it
--     doesn't stand on a road.

local InputKit = require(script.Parent.InputKit)
local Kit = require(script.Parent.Art.Kit)
local StoreCopy = require(script.Parent.Store.StoreCopy)
local StoreData = require(script.Parent.StoreData)
local StoreSale = require(script.Parent.Store.StoreSale)

local StoreBoard = {}

StoreBoard.Look = {
	TimberBrown = Color3.fromHex("#7A5230"), -- posts and frame (Wood)
	PineTrim = Color3.fromHex("#2F5D3A"), -- header plank (WoodPlanks)
	Cork = Color3.fromHex("#B58A5C"), -- the field (Fabric)
	SignCream = Color3.fromHex("#F3E7C9"), -- cards, header word
	SignInk = Color3.fromHex("#2A2420"), -- card titles
	BodyInk = Color3.fromHex("#5A4636"), -- card lines
	Brass = Color3.fromHex("#C9A24A"), -- pins, bolts
	Pill = Color3.fromHex("#1E1B18"), -- price pill
	CoinGold = Color3.fromHex("#F2C14E"), -- price text
	WeatheredPlank = Color3.fromHex("#9C8466"), -- the Coming soon strip
	PassDisc = Color3.fromHex("#2F5D3A"), -- art disc behind a pass
	ProductDisc = Color3.fromHex("#9E3B2E"), -- art disc behind a product (BarnRed)
	LampDay = Color3.fromHex("#F3E7C9"), -- the lanterns' glass by day
	LampLight = Color3.fromHex("#FFC86E"), -- their light after dark (the town's lantern colour)
}
local L = StoreBoard.Look

StoreBoard.PartCap = 16

-- The cork field (X wide, Y tall, Z thick) before the board is turned to
-- face +X (toward the spawn walk). It carries the posters and the prompt.
StoreBoard.BoardSize = Vector3.new(6.1, 4.6, 0.3)
StoreBoard.FieldBottom = 1.2 -- studs over the ground
StoreBoard.Frame = 0.25 -- the outer frame's width
StoreBoard.PostWidth = 0.6
-- The posts' centres, either side of the field's middle (the footprint
-- stays as wide as the old board's arch: 7.3 studs).
StoreBoard.ArchHalf = 3.35
StoreBoard.HeaderSize = Vector3.new(5.7, 1.1, 0.3)
-- The header plank's middle over the field's top.
StoreBoard.BannerRise = 0.95
StoreBoard.BannerText = StoreCopy.BoardHeader
StoreBoard.PxPerStud = 100
-- Centre of the field. Facing +X. West of the spawn walk and Bram's route,
-- south of the street, just clear of Murph's camp's ring (radius 12 round
-- (-28, 45)).
StoreBoard.CFrame = CFrame.new(-20.5, StoreBoard.FieldBottom + StoreBoard.BoardSize.Y / 2, 58.3)
	* CFrame.Angles(0, -math.pi / 2, 0)

-- World XZ of the board and its posts (its corners), for clearance tests.
function StoreBoard.Footprint(): (number, number, number, number)
	local size = StoreBoard.BoardSize
	local hx = StoreBoard.ArchHalf + StoreBoard.PostWidth / 2
	local hz = math.max(size.Z, StoreBoard.PostWidth) / 2
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, x in ipairs({ -hx, hx }) do
		for _, z in ipairs({ -hz, hz }) do
			local p = StoreBoard.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
			x0 = math.min(x0, p.X)
			x1 = math.max(x1, p.X)
			z0 = math.min(z0, p.Z)
			z1 = math.max(z1, p.Z)
		end
	end
	return x0, x1, z0, z1
end

-- True when the axis-aligned box overlaps the footprint.
function StoreBoard.Overlaps(x0: number, x1: number, z0: number, z1: number): boolean
	local a0, a1, b0, b1 = StoreBoard.Footprint()
	return a0 < x1 and a1 > x0 and b0 < z1 and b1 > z0
end

StoreBoard.TitleTextPx = 20
StoreBoard.DescTextPx = 16
StoreBoard.DescLines = 3
-- Gotham advance as a fraction of TextSize, a little wide of the real face
-- so a fit here still fits in Studio.
StoreBoard.Em = 0.58

-- The posters on the field's canvas: pages of three big cards side by
-- side, as in the mockup, with a Coming soon strip under them. With more
-- than three cards the board turns a page every PageSec seconds
-- (StoreSaleService does it on the server) and shows a dot per page.
StoreBoard.Columns = 3
StoreBoard.GridPad = 10
StoreBoard.CardGap = 12
StoreBoard.CardH = 340
StoreBoard.StripH = 40
StoreBoard.DotsH = 18
StoreBoard.ArtPx = 96
StoreBoard.TitleLines = 2
StoreBoard.PageSec = 8

function StoreBoard.Canvas(): Vector2
	local size = StoreBoard.BoardSize
	return Vector2.new(math.floor(size.X * StoreBoard.PxPerStud), math.floor(size.Y * StoreBoard.PxPerStud))
end

function StoreBoard.CardW(canvasW: number): number
	local inner = canvasW - StoreBoard.GridPad * 2
	return math.floor((inner - (StoreBoard.Columns - 1) * StoreBoard.CardGap) / StoreBoard.Columns)
end

-- The width a card's title has: centred under the art disc.
function StoreBoard.TitleWidth(canvasW: number): number
	return StoreBoard.CardW(canvasW) - 20
end

-- The width a card's line has: the same, under the title.
function StoreBoard.BodyWidth(canvasW: number): number
	return StoreBoard.CardW(canvasW) - 20
end

-- How many pages `count` cards take.
function StoreBoard.PageCount(count: number): number
	return math.max(1, math.ceil(count / StoreBoard.Columns))
end

function StoreBoard.LineCount(text: string, widthPx: number, textPx: number): number
	if text == "" then
		return 1
	end
	if widthPx <= 0 then
		return 99
	end
	local lines = 1
	local used = 0
	local space = textPx * StoreBoard.Em
	for word in string.gmatch(text, "%S+") do
		local w = #word * textPx * StoreBoard.Em
		if used > 0 and used + space + w > widthPx then
			lines += 1
			used = w
		else
			used += (if used > 0 then space else 0) + w
		end
	end
	return lines
end

-- The text, or a prefix plus an ellipsis when it would run past
-- `maxLines` on this board.
function StoreBoard.FitText(text: string, widthPx: number, textPx: number, maxLines: number): string
	if StoreBoard.LineCount(text, widthPx, textPx) <= maxLines then
		return text
	end
	local best = "…"
	local lo, hi = 1, #text
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		local cut = string.gsub(string.sub(text, 1, mid), "%s+$", "")
		local trial = cut .. "…"
		if StoreBoard.LineCount(trial, widthPx, textPx) <= maxLines then
			best = trial
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return best
end

-- The one short line a poster shows (StoreCopy.BoardLines), falling back
-- to the start of the description.
function StoreBoard.LineFor(key: string, description: string): string
	return StoreCopy.BoardLines[key] or description
end

local function text(
	parent: Instance,
	name: string,
	value: string,
	font: Enum.Font,
	px: number,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = px
	label.TextColor3 = color
	label.Text = value
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

local function poster(parent: Instance, entry: StoreData.Entry, order: number, canvasW: number)
	local item = entry.item
	local card = Instance.new("Frame")
	card.Name = item.name
	card.LayoutOrder = order
	card.BackgroundColor3 = L.SignCream
	card.BorderSizePixel = 0
	card:SetAttribute("RobuxKind", entry.kind)
	card:SetAttribute("RobuxKey", entry.key)
	corner(card, 8)
	local pin = Instance.new("Frame")
	pin.Name = "Pin"
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.new(0.5, 0, 0, 10)
	pin.Size = UDim2.fromOffset(14, 14)
	pin.BackgroundColor3 = L.Brass
	pin.BorderSizePixel = 0
	corner(pin, 7)
	pin.Parent = card
	local disc = Instance.new("ImageLabel")
	disc.Name = "Art"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.new(0.5, 0, 0, 26)
	disc.Size = UDim2.fromOffset(StoreBoard.ArtPx, StoreBoard.ArtPx)
	disc.BackgroundColor3 = if entry.kind == "Pass" then L.PassDisc else L.ProductDisc
	disc.BorderSizePixel = 0
	disc.ScaleType = Enum.ScaleType.Fit
	corner(disc, StoreBoard.ArtPx // 2)
	if item.image > 0 then
		disc.Image = "rbxassetid://" .. tostring(item.image)
	else
		disc.Image = ""
		local glyph = text(
			disc,
			"Glyph",
			StoreCopy.BoardGlyphs[entry.key] or string.sub(item.name, 1, 1),
			Enum.Font.FredokaOne,
			40,
			L.CoinGold
		)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
	end
	disc.Parent = card
	local titleY = 26 + StoreBoard.ArtPx + 10
	local titleH = (StoreBoard.TitleTextPx + 4) * StoreBoard.TitleLines
	local title = text(
		card,
		"Title",
		StoreBoard.FitText(item.name, StoreBoard.TitleWidth(canvasW), StoreBoard.TitleTextPx, StoreBoard.TitleLines),
		Enum.Font.GothamBold,
		StoreBoard.TitleTextPx,
		L.SignInk
	)
	title.Position = UDim2.fromOffset(10, titleY)
	title.Size = UDim2.new(1, -20, 0, titleH)
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center
	local body = text(
		card,
		"Description",
		StoreBoard.FitText(
			StoreBoard.LineFor(entry.key, item.description),
			StoreBoard.BodyWidth(canvasW),
			StoreBoard.DescTextPx,
			StoreBoard.DescLines
		),
		Enum.Font.Gotham,
		StoreBoard.DescTextPx,
		L.BodyInk
	)
	body.Position = UDim2.fromOffset(10, titleY + titleH + 4)
	body.Size = UDim2.new(1, -20, 0, (StoreBoard.DescTextPx + 4) * StoreBoard.DescLines)
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.TextYAlignment = Enum.TextYAlignment.Top
	local pill = Instance.new("Frame")
	pill.Name = "PricePill"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -14)
	pill.Size = UDim2.fromOffset(110, 44)
	pill.BackgroundColor3 = L.Pill
	pill.BorderSizePixel = 0
	corner(pill, 10)
	pill.Parent = card
	-- The only text in the pill is the player's own price, painted by their
	-- client. The server writes just "R$".
	local price = text(pill, "Price", StoreCopy.PriceUnknown, Enum.Font.GothamBold, 21, L.CoinGold)
	price.Size = UDim2.fromScale(1, 1)
	price.TextXAlignment = Enum.TextXAlignment.Center
	price:SetAttribute("RobuxKind", entry.kind)
	price:SetAttribute("RobuxKey", entry.key)
	price:AddTag("StorePricePill")
	card.Parent = parent
end

-- What the board shows: the cards (for sale, or not answered yet) and the
-- names on the Coming soon strip (Roblox said no, or the id is 0, and the
-- item's offSale is "soon"). `saleCheck` is Roblox's answer per item.
function StoreBoard.Split(saleCheck: ((string, string) -> boolean?)?): ({ StoreData.Entry }, { string })
	local cards: { StoreData.Entry } = {}
	local soon: { string } = {}
	for _, entry in ipairs(StoreData.Ordered()) do
		local answer = if saleCheck then saleCheck(entry.kind, entry.key) else nil
		if StoreSale.ShowInWorld(entry.item.id, answer) then
			table.insert(cards, entry)
		elseif entry.item.offSale ~= "hidden" then
			table.insert(soon, entry.item.name)
		end
	end
	return cards, soon
end

-- (Re)fills the poster list. Called at build and when sale answers change.
-- Cards go on pages of three ("Page1", "Page2", ...); page 1 shows.
function StoreBoard.FillPosters(list: Instance, saleCheck: ((string, string) -> boolean?)?)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local canvasW = StoreBoard.Canvas().X
	local cards, soon = StoreBoard.Split(saleCheck)
	local pages = StoreBoard.PageCount(#cards)
	-- The cards sit in the middle of the cork over the strip's row.
	local inner = StoreBoard.Canvas().Y - StoreBoard.GridPad * 2
	local below = StoreBoard.DotsH + 10
	local stripRow = if #soon > 0 then StoreBoard.StripH + 10 else 0
	local cardsTop = math.max(0, math.floor((inner - stripRow - StoreBoard.CardH - below) / 2))
	for n = 1, pages do
		local page = Instance.new("Frame")
		page.Name = "Page" .. n
		page.BackgroundTransparency = 1
		page.Position = UDim2.fromOffset(0, cardsTop)
		page.Size = UDim2.new(1, 0, 0, StoreBoard.CardH)
		page.Visible = n == 1
		page:SetAttribute("Page", n)
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(StoreBoard.CardW(canvasW), StoreBoard.CardH)
		layout.CellPadding = UDim2.fromOffset(StoreBoard.CardGap, StoreBoard.CardGap)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Parent = page
		page.Parent = list
		for i = 1, StoreBoard.Columns do
			local entry = cards[(n - 1) * StoreBoard.Columns + i]
			if entry then
				poster(page, entry, i, canvasW)
			end
		end
	end
	list:SetAttribute("Pages", pages)
	list:SetAttribute("Page", 1)
	if pages > 1 then
		local dots = Instance.new("Frame")
		dots.Name = "Dots"
		dots.BackgroundTransparency = 1
		dots.Position = UDim2.fromOffset(0, cardsTop + StoreBoard.CardH + 10)
		dots.Size = UDim2.new(1, 0, 0, StoreBoard.DotsH)
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.HorizontalAlignment = Enum.HorizontalAlignment.Center
		row.Padding = UDim.new(0, 10)
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Parent = dots
		for n = 1, pages do
			local dot = Instance.new("Frame")
			dot.Name = "Dot" .. n
			dot.LayoutOrder = n
			dot.Size = UDim2.fromOffset(StoreBoard.DotsH - 4, StoreBoard.DotsH - 4)
			dot.BackgroundColor3 = if n == 1 then L.Brass else L.WeatheredPlank
			dot.BorderSizePixel = 0
			corner(dot, (StoreBoard.DotsH - 4) // 2)
			dot.Parent = dots
		end
		dots.Parent = list
	end
	if #soon > 0 then
		local strip = Instance.new("Frame")
		strip.Name = "ComingSoon"
		strip.AnchorPoint = Vector2.new(0, 1)
		strip.Position = UDim2.fromScale(0, 1)
		strip.Size = UDim2.new(1, 0, 0, StoreBoard.StripH)
		strip.BackgroundColor3 = L.WeatheredPlank
		strip.BorderSizePixel = 0
		corner(strip, 6)
		local words = text(
			strip,
			"Words",
			StoreBoard.FitText(StoreCopy.Soon .. ": " .. table.concat(soon, ", "), canvasW - 44, 16, 1),
			Enum.Font.GothamBold,
			16,
			L.SignCream
		)
		words.Size = UDim2.new(1, -24, 1, 0)
		words.Position = UDim2.fromOffset(12, 0)
		strip.Parent = list
	end
end

-- Shows page `n` (wrapping) of a poster list, and lights its dot.
function StoreBoard.ShowPage(list: Instance, n: number)
	local pages = list:GetAttribute("Pages")
	if type(pages) ~= "number" or pages < 1 then
		return
	end
	local page = ((math.floor(n) - 1) % pages) + 1
	list:SetAttribute("Page", page)
	for _, child in ipairs(list:GetChildren()) do
		local at = child:GetAttribute("Page")
		if child:IsA("GuiObject") and type(at) == "number" then
			child.Visible = at == page
		end
	end
	local dots = list:FindFirstChild("Dots")
	if dots then
		for _, dot in ipairs(dots:GetChildren()) do
			if dot:IsA("Frame") then
				dot.BackgroundColor3 = if dot.Name == "Dot" .. page then L.Brass else L.WeatheredPlank
			end
		end
	end
end

-- The next page, for the server's page-turn loop.
function StoreBoard.NextPage(list: Instance)
	local page = list:GetAttribute("Page")
	StoreBoard.ShowPage(list, (if type(page) == "number" then page else 0) + 1)
end

-- The posts, frame and header: TimberBrown posts either side, a frame round
-- the field, a lintel post to post and the PineTrim header plank under it
-- reading TIMBERLINE on both faces. Only the posts collide.
function StoreBoard.BuildFrame(model: Model)
	local size = StoreBoard.BoardSize
	local fieldBottom = -size.Y / 2
	local ground = -(StoreBoard.FieldBottom + size.Y / 2)
	local headerY = size.Y / 2 + StoreBoard.BannerRise
	local top = headerY + StoreBoard.HeaderSize.Y / 2 + 0.35
	local w = StoreBoard.PostWidth
	for _, side in ipairs({ -1, 1 }) do
		local x = side * StoreBoard.ArchHalf
		Kit.part(
			model,
			"Post",
			Vector3.new(w, top - ground, w),
			CFrame.new(x, (top + ground) / 2, 0),
			L.TimberBrown,
			Enum.Material.Wood
		)
		local cap = Kit.part(
			model,
			"PostCap",
			Vector3.new(w + 0.2, 0.2, w + 0.2),
			CFrame.new(x, top + 0.1, 0),
			L.TimberBrown,
			Enum.Material.Wood
		)
		cap.CanCollide = false
		-- A small lantern on each cap, lit after dark by LightingController
		-- (LanternGlow), so the cards read at night.
		local lamp = Kit.part(
			model,
			"LanternGlow",
			Vector3.new(0.34, 0.42, 0.34),
			CFrame.new(x, top + 0.2 + 0.21, 0),
			L.LampDay,
			Enum.Material.Glass
		)
		lamp.CanCollide = false
		lamp.CanQuery = false
		lamp.CanTouch = false
		local light = Instance.new("PointLight")
		light.Name = "Light"
		light.Color = L.LampLight
		light.Range = 12
		light.Brightness = 2
		light.Shadows = false
		light.Enabled = false
		light.Parent = lamp
	end
	local f = StoreBoard.Frame
	local outerW = size.X + f * 2
	for _, y in ipairs({ size.Y / 2 + f / 2, fieldBottom - f / 2 }) do
		local rail = Kit.part(
			model,
			"FrameRail",
			Vector3.new(outerW, f, size.Z + 0.12),
			CFrame.new(0, y, 0),
			L.TimberBrown,
			Enum.Material.Wood
		)
		rail.CanCollide = false
	end
	for _, side in ipairs({ -1, 1 }) do
		local stile = Kit.part(
			model,
			"FrameStile",
			Vector3.new(f, size.Y, size.Z + 0.12),
			CFrame.new(side * (size.X / 2 + f / 2), 0, 0),
			L.TimberBrown,
			Enum.Material.Wood
		)
		stile.CanCollide = false
	end
	-- The lintel the header hangs from: post to post over the header, so
	-- the header's back face reads from behind too.
	local rail = Kit.part(
		model,
		"HeaderRail",
		Vector3.new(StoreBoard.ArchHalf * 2, 0.3, 0.36),
		CFrame.new(0, headerY + StoreBoard.HeaderSize.Y / 2 + 0.1, 0),
		L.TimberBrown,
		Enum.Material.Wood
	)
	rail.CanCollide = false
	local header = Kit.part(
		model,
		"Header",
		StoreBoard.HeaderSize,
		CFrame.new(0, headerY, -0.05),
		L.PineTrim,
		Enum.Material.WoodPlanks
	)
	header.CanCollide = false
	header.CanQuery = false
	header.CanTouch = false
	Kit.signText(
		header,
		StoreBoard.BannerText,
		L.SignCream,
		{ Enum.NormalId.Front, Enum.NormalId.Back },
		Enum.Font.FredokaOne,
		0
	)
	for _, side in ipairs({ -1, 1 }) do
		local bolt = Kit.part(
			model,
			"Bolt",
			Vector3.new(0.16, 0.16, 0.1),
			CFrame.new(side * (StoreBoard.HeaderSize.X / 2 - 0.25), headerY + 0.25, -0.24),
			L.Brass,
			Enum.Material.Metal
		)
		bolt.CanCollide = false
		bolt.CanQuery = false
		bolt.CanTouch = false
	end
end

-- The whole board: the cork field (the PrimaryPart, carrying the posters
-- and the prompt), the frame and header, the posters for whatever is for
-- sale, and the prompt. `saleCheck` is Roblox's answer per item (nil: none
-- known yet, so every item with an id gets a card).
function StoreBoard.Build(saleCheck: ((string, string) -> boolean?)?): Model
	local model = Instance.new("Model")
	model.Name = "StoreBoard"
	local size = StoreBoard.BoardSize
	local board = Kit.part(model, "Board", size, CFrame.new(0, 0, 0), L.Cork, Enum.Material.Fabric)
	model.PrimaryPart = board
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Posters"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = StoreBoard.Canvas()
	gui.LightInfluence = 0.6
	gui.Parent = board
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = gui
	local pad = Instance.new("UIPadding")
	local gp = UDim.new(0, StoreBoard.GridPad)
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = gp, gp, gp, gp
	pad.Parent = list
	list:AddTag("StoreBoardPosters")
	StoreBoard.FillPosters(list, saleCheck)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StorePrompt"
	prompt.ActionText = StoreCopy.BoardPrompt
	prompt.ObjectText = StoreCopy.BoardObject
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.HoldDuration = 0
	prompt.Parent = board
	StoreBoard.BuildFrame(model)
	prompt:AddTag("StorePrompt")
	return model
end

return StoreBoard
