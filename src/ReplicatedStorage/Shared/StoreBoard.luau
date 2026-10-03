--!strict
-- StoreBoard: the town bulletin board that opens the Robux store.
-- West of the spawn walk and of Old Bram's route, south of the street,
-- north of the tutorial grove and clear of Murph's camp. Persistent so
-- the prompt still works with StreamingEnabled. Pure placement so tests
-- can check it doesn't stand on a road.

local Kit = require(script.Parent.Art.Kit)
local StoreData = require(script.Parent.StoreData)

local StoreBoard = {}

-- Local size of the board (X wide, Y tall, Z thick) before it's turned
-- to face +X (toward the spawn walk).
StoreBoard.BoardSize = Vector3.new(4.6, 4.6, 0.4)
-- Centre of the board. Base sits on y = 0. Facing +X.
StoreBoard.CFrame = CFrame.new(-22, StoreBoard.BoardSize.Y / 2, 59) * CFrame.Angles(0, -math.pi / 2, 0)

-- World XZ of the board (its corners), for clearance tests.
function StoreBoard.Footprint(): (number, number, number, number)
	local size = StoreBoard.BoardSize
	local hx, hz = size.X / 2, size.Z / 2
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

local function poster(parent: Instance, item: { name: string, description: string, image: number }, order: number)
	local card = Instance.new("Frame")
	card.Name = item.name
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -8, 0, 72)
	card.BackgroundColor3 = Color3.fromRGB(255, 246, 230)
	card.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card
	local image = Instance.new("ImageLabel")
	image.Name = "Art"
	image.BackgroundColor3 = Color3.fromRGB(90, 62, 36)
	image.Size = UDim2.fromOffset(56, 56)
	image.Position = UDim2.fromOffset(8, 8)
	image.BorderSizePixel = 0
	if item.image > 0 then
		image.Image = "rbxassetid://" .. tostring(item.image)
	else
		image.Image = ""
	end
	image.Parent = card
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(72, 6)
	title.Size = UDim2.new(1, -80, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(62, 42, 24)
	title.Text = item.name
	title.Parent = card
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(72, 28)
	body.Size = UDim2.new(1, -80, 0, 38)
	body.Font = Enum.Font.Gotham
	body.TextSize = 12
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = Color3.fromRGB(90, 64, 40)
	body.Text = item.description
	body.Parent = card
	card.Parent = parent
end

-- The wooden board, posts, posters for whatever is for sale, and the
-- prompt. An id of 0 is left off the board. With nothing for sale, a
-- "coming soon" label; the prompt stays either way.
function StoreBoard.Build(): Model
	local model = Instance.new("Model")
	model.Name = "StoreBoard"
	local size = StoreBoard.BoardSize
	local board = Kit.part(model, "Board", size, CFrame.new(0, 0, 0), Color3.fromRGB(92, 58, 32), Enum.Material.Wood)
	model.PrimaryPart = board
	for _, x in ipairs({ -size.X / 2 + 0.2, size.X / 2 - 0.2 }) do
		Kit.part(
			model,
			"Post",
			Vector3.new(0.28, size.Y + 0.4, 0.28),
			CFrame.new(x, -0.2, 0.15),
			Color3.fromRGB(62, 40, 22),
			Enum.Material.Wood
		)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Posters"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, 460)
	gui.Parent = board
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = list
	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.Size = UDim2.new(1, 0, 0, 28)
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 22
	heading.TextColor3 = Color3.fromRGB(255, 244, 220)
	heading.Text = "TIMBERLINE STORE"
	heading.LayoutOrder = 0
	heading.Parent = list
	local n = 0
	for _, pass in ipairs(StoreData.ListedPasses()) do
		n += 1
		poster(list, pass, n)
	end
	for _, product in ipairs(StoreData.ListedProducts()) do
		n += 1
		poster(list, product, n)
	end
	if n == 0 then
		local soon = Instance.new("TextLabel")
		soon.Name = "ComingSoon"
		soon.BackgroundTransparency = 1
		soon.Size = UDim2.new(1, 0, 0, 80)
		soon.Font = Enum.Font.GothamBold
		soon.TextSize = 20
		soon.TextWrapped = true
		soon.TextColor3 = Color3.fromRGB(255, 236, 200)
		soon.Text = "Coming soon"
		soon.LayoutOrder = 1
		soon.Parent = list
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StorePrompt"
	prompt.ActionText = "Browse"
	prompt.ObjectText = "Store"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.Parent = board
	prompt:AddTag("StorePrompt")
	return model
end

return StoreBoard
