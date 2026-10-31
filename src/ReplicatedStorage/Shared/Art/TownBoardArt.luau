--!strict
-- TownBoardArt: the town leaderboard board (Lane X). A SignCream face in a
-- TimberBrown frame with Brass corners, on two timber posts, its front (-Z) turned to the street, with
-- one server-owned SurfaceGui on it: the title, then the top ten in two
-- columns of five (rank medal, name, "$X earned"), or one message line when
-- there is nothing to list. A plaque under it says how to get on the board.
--   * Fourteen parts: Board, two frame rails, two stiles, four brass corners,
--     two posts, two post caps, the plaque. No light. Only the posts, the
--     field and the plaque collide.
--   * Every label is a direct child of the SurfaceGui with a scale position,
--     so the preview renderer can place each one.
--   * T414e look (Palette names): TimberBrown frame, posts and plaque,
--     SignCream face with SignInk lettering, Brass corners and caps. The
--     ten rows sit on dark SignInk plates in cream, CoinGold for the top three.
-- Build() makes the model around the origin (ground at y = 0, front toward
-- -Z); the service places it. Fill() writes a TownBoardLogic.View into it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local Palette = require(ReplicatedStorage.Shared.Art.Palette)
local TownBoardLogic = require(ReplicatedStorage.Shared.TownBoardLogic)

local TownBoardArt = {}

TownBoardArt.Look = {
	Walnut = Palette.SignCream, -- the face (the old name stays for callers)
	Ink = Palette.SignInk, -- title, message and the back's lettering on the cream
	Plate = Palette.SignInk, -- a row's plate
	Brass = Palette.Brass, -- corners, caps, the rule under the title
	Cream = Palette.SignCream, -- names on the plates
	Dim = Palette.PlankHoney, -- the cash line
	Amber = Palette.CoinGold, -- ranks 1 to 3
	Medal = Palette.WetMud, -- rank 4 and under
	MedalTop = Palette.TimberBrown, -- ranks 1 to 3
	TimberBrown = Palette.TimberBrown, -- frame, posts, plaque
}
local L = TownBoardArt.Look

local TITLE_FONT = Enum.Font.FredokaOne
local TEXT_FONT = Enum.Font.GothamBold

local function rect(obj: GuiObject, r: TownBoardLogic.Rect)
	local canvas = TownBoardLogic.CanvasSize
	obj.Position = UDim2.fromScale(r.x / canvas.X, r.y / canvas.Y)
	obj.Size = UDim2.fromScale(r.w / canvas.X, r.h / canvas.Y)
end

local function label(
	parent: Instance,
	name: string,
	r: TownBoardLogic.Rect,
	font: Enum.Font,
	px: number,
	color: Color3,
	align: Enum.TextXAlignment
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextColor3 = color
	text.TextXAlignment = align
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextScaled = true
	text.TextWrapped = true
	text.Text = ""
	rect(text, r)
	-- TextScaled shrinks a long name to fit its box; this caps the big end.
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = px
	cap.MinTextSize = 8
	cap.Parent = text
	text.Parent = parent
	return text
end

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

local function frame(parent: Instance, name: string, r: TownBoardLogic.Rect, color: Color3, radius: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	rect(f, r)
	corner(f, radius)
	f.Parent = parent
	return f
end

-- The SurfaceGui and everything on it (blank until Fill).
local function buildFace(board: Part): SurfaceGui
	local canvas = TownBoardLogic.CanvasSize
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0.25
	gui.MaxDistance = TownBoardLogic.MaxDistance
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ClipsDescendants = true
	gui.Parent = board

	local title = label(
		gui,
		"Title",
		TownBoardLogic.TitleRect(),
		TITLE_FONT,
		TownBoardLogic.TitleTextPx,
		L.Ink,
		Enum.TextXAlignment.Center
	)
	title.Text = TownBoardLogic.Title
	local ruleW = 760
	frame(gui, "Rule", { x = (canvas.X - ruleW) // 2, y = TownBoardLogic.HeaderH + 4, w = ruleW, h = 6 }, L.Brass, 3)

	for i = 1, TownBoardLogic.Rows do
		local slot = TownBoardLogic.Slot(i)
		local plate = frame(gui, "Plate" .. i, slot.plate, L.Plate, 14)
		plate.Visible = false
		local medal = frame(gui, "Medal" .. i, slot.medal, L.Medal, slot.medal.w // 2)
		medal.Visible = false
		label(gui, "Rank" .. i, slot.rank, TEXT_FONT, 52, L.Cream, Enum.TextXAlignment.Center)
		label(gui, "Name" .. i, slot.name, TEXT_FONT, TownBoardLogic.NameTextPx, L.Cream, Enum.TextXAlignment.Left)
		label(gui, "Cash" .. i, slot.cash, TEXT_FONT, TownBoardLogic.CashTextPx, L.Dim, Enum.TextXAlignment.Left)
	end
	label(
		gui,
		"Message",
		TownBoardLogic.MessageRect(),
		TEXT_FONT,
		TownBoardLogic.MessageTextPx,
		L.Ink,
		Enum.TextXAlignment.Center
	)
	return gui
end

-- Writes a view onto the board: the rows, or the one message line. A row
-- with nothing to say is blank and its plate hidden, so no stale name shows.
function TownBoardArt.Fill(model: Model, view: TownBoardLogic.View)
	local board = model:FindFirstChild("Board")
	local gui = if board then board:FindFirstChild("Face") else nil
	if gui == nil then
		return
	end
	local function text(name: string): TextLabel?
		local found = gui:FindFirstChild(name)
		return if found and found:IsA("TextLabel") then found else nil
	end
	local function visible(name: string, on: boolean)
		local found = gui:FindFirstChild(name)
		if found and found:IsA("GuiObject") then
			found.Visible = on
		end
	end
	for i = 1, TownBoardLogic.Rows do
		local line = view.lines[i]
		local rank, name, cash = text("Rank" .. i), text("Name" .. i), text("Cash" .. i)
		visible("Plate" .. i, line ~= nil)
		visible("Medal" .. i, line ~= nil)
		if rank and name and cash then
			if line then
				rank.Text = line.rank
				name.Text = line.name
				cash.Text = line.cash
				rank.TextColor3 = if line.top then L.Amber else L.Cream
				name.TextColor3 = if line.top then L.Amber else L.Cream
			else
				rank.Text = ""
				name.Text = ""
				cash.Text = ""
			end
		end
		local medal = gui:FindFirstChild("Medal" .. i)
		if medal and medal:IsA("Frame") and line then
			medal.BackgroundColor3 = if line.top then L.MedalTop else L.Medal
		end
	end
	local message = text("Message")
	if message then
		message.Text = view.message
	end
	model:SetAttribute("State", view.state)
end

-- The whole board, at the origin, ground at y = 0, front toward -Z.
function TownBoardArt.Build(): Model
	local model = Instance.new("Model")
	model.Name = "TownBoard"
	local size = TownBoardLogic.BoardSize
	local f = TownBoardLogic.Frame
	local fieldY = TownBoardLogic.OuterBottom + f + size.Y / 2
	local outerTop = fieldY + size.Y / 2 + f

	local board = Kit.part(model, "Board", size, CFrame.new(0, fieldY, 0), L.Walnut, Enum.Material.SmoothPlastic)
	buildFace(board)
	-- The back reads as a sign too (the title in brass), not a blank slab.
	Kit.signText(board, TownBoardLogic.Title, L.Ink, { Enum.NormalId.Back }, TITLE_FONT, 0.25)

	local outerW = size.X + f * 2
	for _, y in ipairs({ fieldY + size.Y / 2 + f / 2, fieldY - size.Y / 2 - f / 2 }) do
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
			CFrame.new(side * (size.X / 2 + f / 2), fieldY, 0),
			L.TimberBrown,
			Enum.Material.Wood
		)
		stile.CanCollide = false
	end
	-- Brass corner pieces, a hair bigger than the frame all round (no shared face).
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			local bracket = Kit.part(
				model,
				"FrameCorner",
				Vector3.new(f + 0.16, f + 0.16, size.Z + 0.24),
				CFrame.new(sx * (size.X / 2 + f / 2), fieldY + sy * (size.Y / 2 + f / 2), 0),
				L.Brass,
				Enum.Material.Metal
			)
			bracket.CanCollide = false
		end
	end

	local top = outerTop + TownBoardLogic.PostOver
	local bottom = -TownBoardLogic.PostSink
	local w = TownBoardLogic.PostWidth
	for _, side in ipairs({ -1, 1 }) do
		local x = side * TownBoardLogic.PostX
		Kit.part(
			model,
			"Post",
			Vector3.new(w, top - bottom, w),
			CFrame.new(x, (top + bottom) / 2, 0),
			L.TimberBrown,
			Enum.Material.Wood
		)
		local cap = Kit.part(
			model,
			"PostCap",
			Vector3.new(w + 0.2, 0.2, w + 0.2),
			CFrame.new(x, top + 0.1, 0),
			L.Brass,
			Enum.Material.Metal
		)
		cap.CanCollide = false
	end

	local plaque = Kit.part(
		model,
		"Plaque",
		TownBoardLogic.PlaqueSize,
		CFrame.new(0, TownBoardLogic.PlaqueY, 0),
		L.TimberBrown,
		Enum.Material.WoodPlanks
	)
	Kit.signText(plaque, TownBoardLogic.SignText, L.Cream, { Enum.NormalId.Front }, TEXT_FONT, 0.25)

	TownBoardArt.Fill(model, TownBoardLogic.View(nil, false))
	return model
end

return TownBoardArt
