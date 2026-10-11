--!strict
-- RobuxBoxArt: the gold box look for a Robux item (Lane P, the Game Art
-- Director's cash box): an open PlankHoney crate with two IronBlack bands,
-- a SignCream tag naming the item, and a pile of CoinGold coins you can
-- see over the low front wall. Nothing reads as a closed or mystery box:
-- every crate shows exactly what is in it, and the tag says what it is.
-- The Small and Large Cash Packs differ only by the pile.
-- The body part keeps the class S size (it is the collider, invisible);
-- the crate is 8 welded shell parts (BoxLogic.ShellPartCap is 9) plus 3
-- coin parts in Contents. No price is ever printed on it: the hover tag
-- shows the player's own Robux price.

local BacklogModels = require(script.Parent.BacklogModels)
local Kit = require(script.Parent.Kit)
local MeshKit = require(script.Parent.MeshKit)

local RobuxBoxArt = {}

RobuxBoxArt.PlankHoney = Color3.fromHex("#C49A63")
RobuxBoxArt.IronBlack = Color3.fromHex("#2B2B2E")
RobuxBoxArt.CoinGold = Color3.fromHex("#F2C14E")
RobuxBoxArt.CoinEdge = Color3.fromHex("#C9A24A")
RobuxBoxArt.SignCream = Color3.fromHex("#F3E7C9")
RobuxBoxArt.SignInk = Color3.fromHex("#2A2420")

RobuxBoxArt.Floor = 0.2
RobuxBoxArt.Wall = 0.15
RobuxBoxArt.WallH = 1.3 -- back and sides, over the floor
RobuxBoxArt.FrontH = 0.85 -- the low front, so the coins show
RobuxBoxArt.ShellParts = 8
RobuxBoxArt.CoinParts = 3

export type Spec = { name: string, key: string? }

local function weldTo(body: BasePart, p: BasePart)
	Kit.decor(p, false)
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = "Weld"
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
end

local function plate(
	parent: Instance,
	body: BasePart,
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Kit.part(parent, name, size, body.CFrame * CFrame.new(offset), color, material)
	weldTo(body, p)
	return p
end

-- How high the coin pile stands over the crate floor, by item.
function RobuxBoxArt.PileHeight(key: string?): number
	if key == "Cash10k" then
		return 1.15
	elseif key == "Cash1k" then
		return 0.6
	end
	return 0.8
end

-- The uploaded crate (BacklogModels "RobuxBox": Body, Glow, Badge). Its
-- Collision piece is the box it was modelled in (2.7 x 2.5 x 2.7); the three
-- pieces are scaled so that box is `body`, which keeps the shelf spacing.
-- The item's name goes on the cream window pane. Nil (and nothing made)
-- when any mesh is missing, so the part-built crate below stays.
local function dressMesh(parent: Instance, body: BasePart, spec: Spec): { BasePart }?
	local asset = BacklogModels.Get("RobuxBox")
	if not asset then
		return nil
	end
	local fit = asset.pieces[#asset.pieces]
	for _, piece in ipairs(asset.pieces) do
		if piece.name == "Collision" then
			fit = piece
		end
	end
	local k = Vector3.new(body.Size.X / fit.size.X, body.Size.Y / fit.size.Y, body.Size.Z / fit.size.Z)
	local made: { MeshPart } = {}
	for _, piece in ipairs(asset.pieces) do
		if piece.name ~= "Collision" then
			local size = Vector3.new(piece.size.X * k.X, piece.size.Y * k.Y, piece.size.Z * k.Z)
			local part = MeshKit.Create(piece.meshId, piece.name, size)
			if not part then
				for _, old in ipairs(made) do
					old:Destroy()
				end
				return nil
			end
			MeshKit.Visual(part, piece.meshId)
			MeshKit.Fidelity(
				part,
				if piece.name == "Body" then Enum.RenderFidelity.Automatic else Enum.RenderFidelity.Performance
			)
			table.insert(made, part)
		end
	end
	if #made == 0 then
		return nil
	end
	body.Transparency = 1
	body.CastShadow = false
	local root = body.CFrame * CFrame.new(0, -body.Size.Y / 2, 0)
	local added: { BasePart } = {}
	for _, part in ipairs(made) do
		if part:GetAttribute("MeshPivot") == "authored" then
			part:PivotTo(root)
		else
			part.CFrame = root * CFrame.new(0, part.Size.Y / 2, 0)
		end
		part.Anchored = body.Anchored
		part.Parent = parent
		local weld = Instance.new("WeldConstraint")
		weld.Name = "Weld"
		weld.Part0 = body
		weld.Part1 = part
		weld.Parent = part
		if part.Name == "Glow" then
			part.Material = Enum.Material.Neon
			part.Color = RobuxBoxArt.SignCream
			part:SetAttribute("MeshGlow", true)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "NameMark"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 80
			gui.LightInfluence = 0
			gui.Parent = part
			local label = Instance.new("TextLabel")
			label.Name = "Name"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.FredokaOne
			label.Text = spec.name
			label.TextScaled = true
			label.TextColor3 = RobuxBoxArt.SignInk
			label.Parent = gui
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0.06, 0)
			pad.PaddingRight = UDim.new(0.06, 0)
			pad.PaddingTop = UDim.new(0.12, 0)
			pad.PaddingBottom = UDim.new(0.12, 0)
			pad.Parent = label
		end
		table.insert(added, part)
	end
	return added
end

-- Dresses `body` (a class S box part) as the crate. Returns every part
-- added (shell, then coins). The body becomes invisible. The uploaded crate
-- mesh when it loads; otherwise the open crate of coins built from parts.
function RobuxBoxArt.Dress(parent: Instance, body: BasePart, spec: Spec): { BasePart }
	local meshed = dressMesh(parent, body, spec)
	if meshed then
		return meshed
	end
	local size = body.Size
	local W, H, D = size.X, size.Y, size.Z
	local f, t = RobuxBoxArt.Floor, RobuxBoxArt.Wall
	local bottom = -H / 2
	body.Transparency = 1
	body.CastShadow = false
	local added: { BasePart } = {}
	local function add(p: Part): Part
		table.insert(added, p)
		return p
	end
	local wood = Enum.Material.WoodPlanks
	add(
		plate(
			parent,
			body,
			"Base",
			Vector3.new(W, f, D),
			Vector3.new(0, bottom + f / 2, 0),
			RobuxBoxArt.PlankHoney,
			wood
		)
	)
	local wallY = bottom + f + RobuxBoxArt.WallH / 2
	for _, sign in ipairs({ -1, 1 }) do
		add(
			plate(
				parent,
				body,
				if sign == -1 then "Left" else "Right",
				Vector3.new(t, RobuxBoxArt.WallH, D),
				Vector3.new(sign * (W / 2 - t / 2), wallY, 0),
				RobuxBoxArt.PlankHoney,
				wood
			)
		)
	end
	add(
		plate(
			parent,
			body,
			"Back",
			Vector3.new(W - 2 * t, RobuxBoxArt.WallH, t),
			Vector3.new(0, wallY, D / 2 - t / 2),
			RobuxBoxArt.PlankHoney,
			wood
		)
	)
	local frontY = bottom + f + RobuxBoxArt.FrontH / 2
	add(
		plate(
			parent,
			body,
			"Front",
			Vector3.new(W - 2 * t, RobuxBoxArt.FrontH, t),
			Vector3.new(0, frontY, -(D / 2 - t / 2)),
			RobuxBoxArt.PlankHoney,
			wood
		)
	)
	local bandY = bottom + f + 0.22
	for _, z in ipairs({ -1, 1 }) do
		add(
			plate(
				parent,
				body,
				if z == -1 then "BandFront" else "BandBack",
				Vector3.new(W + 0.04, 0.14, 0.04),
				Vector3.new(0, bandY, z * (D / 2 + 0.02)),
				RobuxBoxArt.IronBlack,
				Enum.Material.Metal
			)
		)
	end
	-- The tag: a cream card on the front wall naming the item.
	local tag = add(
		plate(
			parent,
			body,
			"Tag",
			Vector3.new(math.min(2.0, W - 0.5), 0.42, 0.04),
			Vector3.new(0, frontY + 0.12, -(D / 2 + 0.03)),
			RobuxBoxArt.SignCream,
			Enum.Material.SmoothPlastic
		)
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NameMark"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = 0.4
	gui.Parent = tag
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = spec.name
	label.TextScaled = true
	label.TextColor3 = RobuxBoxArt.SignInk
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = label

	-- The coins: a level bed of coins filling the crate to the pile height,
	-- and two loose coins standing on it.
	local contents = Instance.new("Model")
	contents.Name = "Contents"
	local pile = RobuxBoxArt.PileHeight(spec.key)
	local floorTop = bottom + f
	local heap = Kit.part(
		contents,
		"CoinHeap",
		Vector3.new(W - 2 * t - 0.05, pile, D - 2 * t - 0.05),
		body.CFrame * CFrame.new(0, floorTop + pile / 2, 0),
		RobuxBoxArt.CoinEdge,
		Enum.Material.SmoothPlastic
	)
	weldTo(body, heap)
	table.insert(added, heap)
	-- Two big coins leaning back on the heap, faces to the front, so the
	-- crate reads as coins from the aisle.
	for i, dx in ipairs({ -0.42, 0.38 }) do
		local lean = math.rad(if i == 1 then 28 else 20)
		local coin = Kit.part(
			contents,
			"Coin",
			Vector3.new(0.14, 0.8, 0.8),
			body.CFrame
				* CFrame.new(dx, floorTop + pile + 0.3, -0.25 + i * 0.2)
				* CFrame.Angles(lean, 0, 0)
				* CFrame.Angles(0, math.pi / 2, 0),
			RobuxBoxArt.CoinGold,
			Enum.Material.Metal
		)
		coin.Shape = Enum.PartType.Cylinder
		weldTo(body, coin)
		table.insert(added, coin)
	end
	contents.Parent = parent
	return added
end

return RobuxBoxArt
