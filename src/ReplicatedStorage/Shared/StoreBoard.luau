--!strict
-- StoreBoard: the town bulletin board that opens the Robux store.
-- West of the spawn walk and of Old Bram's route, south of the street,
-- north of the tutorial grove and clear of Murph's camp. Persistent so
-- the prompt still works with StreamingEnabled. Pure placement so tests
-- can check it doesn't stand on a road.

local InputKit = require(script.Parent.InputKit)
local Kit = require(script.Parent.Art.Kit)
local StoreData = require(script.Parent.StoreData)
local TownMeshes = require(script.Parent.Art.TownMeshes)
local TownModels = require(script.Parent.Art.TownModels)

local StoreBoard = {}

-- The mesh and the old board were 4.6 studs square. The board is taller
-- (7 studs, an arch and banner over it) and a little wider (5.4): Murph's
-- camp and the street leave only about 7.6 studs of ground along Z here,
-- so it grows up, not out. The banner (no collider) may overhang more.
StoreBoard.MeshSize = Vector3.new(4.6, 4.6, 0.4)
-- Local size of the board (X wide, Y tall, Z thick) before it's turned
-- to face +X (toward the spawn walk).
StoreBoard.BoardSize = Vector3.new(5.4, 7, 0.5)
-- What the board mesh is stretched by (its frame is 2.85 studs a side).
StoreBoard.MeshScale = Vector3.new(
	StoreBoard.BoardSize.X / StoreBoard.MeshSize.X,
	StoreBoard.BoardSize.Y / StoreBoard.MeshSize.Y,
	StoreBoard.BoardSize.Z / StoreBoard.MeshSize.Z
)
-- The arch's two posts stand this far either side of the board's middle:
-- on the outer edge of the board mesh's frame.
StoreBoard.ArchHalf = 2.85 * StoreBoard.MeshScale.X + 0.1
StoreBoard.PostWidth = 0.4
-- The banner spans the posts and overhangs them by BannerOverhang a side
-- (it is far over any walker's head, so it doesn't count in the
-- footprint); its middle is BannerRise over the board's top.
StoreBoard.BannerRise = 2.4
StoreBoard.BannerHeight = 2.2
StoreBoard.BannerOverhang = 1
StoreBoard.BannerText = "STORE"
-- Centre of the board. Base sits on y = 0. Facing +X. West of the spawn
-- walk and Bram's route, south of the street, just clear of Murph's camp's
-- ring (radius 12 round (-28, 45)).
StoreBoard.CFrame = CFrame.new(-20.5, StoreBoard.BoardSize.Y / 2, 58.3) * CFrame.Angles(0, -math.pi / 2, 0)

-- World XZ of the board and its arch (its corners), for clearance tests.
function StoreBoard.Footprint(): (number, number, number, number)
	local size = StoreBoard.BoardSize
	local hx, hz = StoreBoard.ArchHalf + StoreBoard.PostWidth / 2, size.Z / 2
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

-- The board names what is for sale. The Robux number is not stored here
-- (Creator Hub owns it; the store screen reads it live), so the line is
-- "R$" and nothing else. Descriptions stay on the store screen.
StoreBoard.PriceLine = "R$"

local function poster(parent: Instance, item: { name: string, description: string, image: number }, order: number)
	local card = Instance.new("Frame")
	card.Name = item.name
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -8, 0, 52)
	card.BackgroundColor3 = Color3.fromRGB(255, 246, 230)
	card.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card
	local image = Instance.new("ImageLabel")
	image.Name = "Art"
	image.BackgroundColor3 = Color3.fromRGB(90, 62, 36)
	image.Size = UDim2.fromOffset(40, 40)
	image.Position = UDim2.fromOffset(6, 6)
	image.BorderSizePixel = 0
	if item.image > 0 then
		image.Image = "rbxassetid://" .. tostring(item.image)
	else
		image.Image = ""
	end
	image.Parent = card
	local ink = Color3.fromHex("#2A2420") -- SignInk
	-- Y scale is a hair, so a preview that sorts lines by it keeps name
	-- then price. The card is what you see in Studio; the scale does not move it.
	local title = Instance.new("TextLabel")
	title.Name = "Name"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 52, order * 0.02, 2)
	title.Size = UDim2.new(1, -58, 0, 26)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextWrapped = true
	title.TextTruncate = Enum.TextTruncate.None
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextColor3 = ink
	title.Text = item.name
	title.Parent = card
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.Position = UDim2.new(0, 52, order * 0.02 + 0.01, 28)
	price.Size = UDim2.new(1, -58, 0, 20)
	price.Font = Enum.Font.GothamBold
	price.TextScaled = true
	price.TextWrapped = true
	price.TextTruncate = Enum.TextTruncate.None
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.TextYAlignment = Enum.TextYAlignment.Center
	price.TextColor3 = ink
	price.Text = StoreBoard.PriceLine
	price.Parent = card
	card.Parent = parent
end

-- Two tall posts either side, a banner board across them reading STORE,
-- and a lantern on each post that lights at night (LanternGlow). It reads
-- from the spawn walk and from the street. Only the posts collide.
function StoreBoard.BuildArch(model: Model)
	local size = StoreBoard.BoardSize
	local top = size.Y / 2 + StoreBoard.BannerRise + StoreBoard.BannerHeight / 2 + 0.3
	local bottom = -size.Y / 2 - 0.4
	local bark = Color3.fromRGB(62, 40, 22)
	local half = StoreBoard.ArchHalf
	local w = StoreBoard.PostWidth
	for _, side in ipairs({ -1, 1 }) do
		local x = side * half
		Kit.part(
			model,
			"ArchPost",
			Vector3.new(w, top - bottom, w),
			CFrame.new(x, (top + bottom) / 2, 0.2),
			bark,
			Enum.Material.Wood
		)
		local cap = Kit.part(
			model,
			"ArchCap",
			Vector3.new(w + 0.3, 0.3, w + 0.3),
			CFrame.new(x, top + 0.15, 0.2),
			Color3.fromRGB(46, 30, 16),
			Enum.Material.Wood
		)
		cap.CanCollide = false
		local lamp = Kit.part(
			model,
			"LanternGlow",
			Vector3.new(0.7, 0.9, 0.7),
			CFrame.new(x, top + 0.75, 0.2),
			Color3.fromRGB(246, 213, 138),
			Enum.Material.Neon
		)
		lamp.CanCollide = false
		lamp.CanQuery = false
		lamp.CanTouch = false
	end
	local bannerY = size.Y / 2 + StoreBoard.BannerRise
	local banner = Kit.part(
		model,
		"Banner",
		Vector3.new(half * 2 + w + StoreBoard.BannerOverhang * 2, StoreBoard.BannerHeight, 0.4),
		CFrame.new(0, bannerY, 0.2),
		Color3.fromRGB(62, 106, 58),
		Enum.Material.WoodPlanks
	)
	banner.CanCollide = false
	banner.CanQuery = false
	banner.CanTouch = false
	Kit.signText(
		banner,
		StoreBoard.BannerText,
		Color3.fromRGB(255, 236, 190),
		{ Enum.NormalId.Front, Enum.NormalId.Back },
		Enum.Font.FredokaOne,
		0
	)
	local trim = Kit.part(
		model,
		"BannerTrim",
		Vector3.new(half * 2 + w + StoreBoard.BannerOverhang * 2 + 0.4, 0.25, 0.55),
		CFrame.new(0, bannerY + StoreBoard.BannerHeight / 2 + 0.12, 0.2),
		Color3.fromRGB(46, 30, 16),
		Enum.Material.Wood
	)
	trim.CanCollide = false
	trim.CanQuery = false
	trim.CanTouch = false
end

-- The wooden board, posts, posters for whatever is for sale, and the
-- prompt. An id of 0 is left off the board. With nothing for sale, a
-- "coming soon" label; the prompt stays either way.
function StoreBoard.Build(): Model
	local model = Instance.new("Model")
	model.Name = "StoreBoard"
	local size = StoreBoard.BoardSize
	local cream = Color3.fromHex("#F3E7C9") -- SignCream
	local ink = Color3.fromHex("#2A2420") -- SignInk
	local board = Kit.part(model, "Board", size, CFrame.new(0, 0, 0), cream, Enum.Material.SmoothPlastic)
	model.PrimaryPart = board
	for _, x in ipairs({ -size.X / 2 + 0.3, size.X / 2 - 0.3 }) do
		Kit.part(
			model,
			"Post",
			Vector3.new(0.4, size.Y + 0.4, 0.4),
			CFrame.new(x, -0.2, 0.2),
			Color3.fromRGB(62, 40, 22),
			Enum.Material.Wood
		)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Posters"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, math.floor(400 * StoreBoard.BoardSize.Y / StoreBoard.BoardSize.X + 0.5))
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
	heading.Size = UDim2.new(1, 0, 0, 44)
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 34
	heading.TextColor3 = ink
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
		soon.TextColor3 = ink
		soon.Text = "Coming soon"
		soon.LayoutOrder = 1
		soon.Parent = list
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StorePrompt"
	prompt.ActionText = "Browse"
	prompt.ObjectText = "Store"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.HoldDuration = 0
	prompt.Parent = board
	-- The board's centre is the game's position. The mesh sits 2.3 lower
	-- so that centre still lands on this part.
	TownMeshes.Dress(model, "StoreBoard", {
		scale = StoreBoard.MeshScale,
		pivot = CFrame.new(0, -TownModels.StoreBoardDrop * StoreBoard.MeshScale.Y, 0),
	})
	-- The arch goes up after the meshes, so they never retire it.
	StoreBoard.BuildArch(model)
	-- A brass frame on the face, added after the meshes for the same reason.
	-- Four bars keep the board at 15 parts (the cap is 16).
	local brass = Color3.fromHex("#C9A24A") -- Brass
	local bar = 0.12
	local faceZ = -size.Z / 2 - 0.05
	Kit.part(
		model,
		"Frame",
		Vector3.new(size.X, bar, 0.08),
		CFrame.new(0, size.Y / 2 - bar / 2, faceZ),
		brass,
		Enum.Material.Metal
	)
	Kit.part(
		model,
		"Frame",
		Vector3.new(size.X, bar, 0.08),
		CFrame.new(0, -size.Y / 2 + bar / 2, faceZ),
		brass,
		Enum.Material.Metal
	)
	Kit.part(
		model,
		"Frame",
		Vector3.new(bar, size.Y - bar * 2, 0.08),
		CFrame.new(-size.X / 2 + bar / 2, 0, faceZ),
		brass,
		Enum.Material.Metal
	)
	Kit.part(
		model,
		"Frame",
		Vector3.new(bar, size.Y - bar * 2, 0.08),
		CFrame.new(size.X / 2 - bar / 2, 0, faceZ),
		brass,
		Enum.Material.Metal
	)
	prompt:AddTag("StorePrompt")
	return model
end

return StoreBoard
