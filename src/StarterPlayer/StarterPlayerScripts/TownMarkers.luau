--!strict
-- TownMarkers (TWN-04): a sign in the sky over each service, so a new
-- player can tell them apart from the spawn, on a phone too:
--   SELL LOGS over the sell zone, AXES over the Tool Shed's counter, TRUCKS
--   over the Dealership's, BLUEPRINTS & GEAR over Hearth & Home's, GONDOLA
--   over the town station's platform.
-- Each is a BillboardGui (in PlayerGui, adorned to its part): an icon chip
-- drawn from Frames (no uploaded images) beside its label (over it, for a
-- two-line label, which keeps it narrow), in the UI's look:
-- cream on bark with an ink drop edge, in the world signs' FredokaOne. It
-- is sized in studs with a pixel floor (Size's Scale is studs, its Offset
-- pixels), so it reads from the spawn on a phone and still shrinks with
-- distance; unlit (LightInfluence 0), not drawn through walls (AlwaysOnTop
-- off), hidden past MaxDistance.
-- It fades out within FadeWithin studs of you (checked every Check
-- seconds; walk up to a shop and the shop's own sign takes over) and
-- while a shop screen is open (ShopUI's ScreenGui is enabled).
-- The marked parts are in Persistent models that reach a client after it
-- starts, so each marker is set up when its part appears (ChildAdded, no
-- WaitForChild): nothing here waits forever or warns.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent.UITheme)

local C = UITheme.Colors

local TownMarkers = {}

export type Marker = {
	name: string,
	path: { string }, -- from TimberlineMap down to the part it floats over
	text: string, -- one line, or two ("\n")
	icon: string, -- "logs", "axe", "truck", "blueprint" or "gondola"
	chip: Color3, -- the icon chip's fill (a shop's accent)
	offset: Vector3, -- StudsOffsetWorldSpace: from the part's middle to the marker's bottom edge
}

-- The shops' chips are their accents (WorldPlan.Town().shops). Each
-- stands on a point 16-19 studs over its part (its bottom edge there:
-- SizeOffset), clear of its building's roof whatever its size, over its
-- own building: nudged east or toward the street (the 1.5x buildings of
-- TWN-13: over a low part of the roof, and so that from the spawn, on a
-- phone, the three on the right (gondola, Tool Shed, Hearth & Home) stand
-- side by side), and SELL LOGS sits back over the pad, under the sawmill's
-- crest, not over it (TownMarkers.spec).
TownMarkers.Markers = {
	{
		name = "SellLogs",
		path = { "SellArea", "SellZone" },
		text = "SELL LOGS",
		icon = "logs",
		chip = C.Money,
		-- The zone's middle is 6 up, 4 south of the pad's (M1.5 deepened it
		-- over the street); back toward the mill, under its crest, at z 95.
		offset = Vector3.new(0, 16, 13),
	},
	{
		name = "Axes",
		path = { "ToolShed", "Counter" },
		text = "AXES",
		icon = "axe",
		chip = Color3.fromRGB(150, 62, 44),
		offset = Vector3.new(14, 19, -14),
	},
	{
		name = "Trucks",
		path = { "Dealership", "Counter" },
		text = "TRUCKS",
		icon = "truck",
		chip = Color3.fromRGB(47, 109, 181),
		offset = Vector3.new(16, 16, 0),
	},
	{
		name = "Gear",
		path = { "HearthAndHome", "Counter" },
		text = "GENERAL\nSTORE",
		icon = "blueprint",
		chip = Color3.fromRGB(122, 90, 60),
		offset = Vector3.new(9, 18.3, 2),
	},
	{
		name = "Gondola",
		path = { "GondolaTown", "Platform" },
		text = "GONDOLA",
		icon = "gondola",
		chip = C.Sky,
		offset = Vector3.new(4, 17.5, 0),
	},
} :: { Marker }

TownMarkers.FadeWithin = 25 -- studs (flat) from you to the marked part: it fades out
TownMarkers.ShowBeyond = 27 -- and back in past this, so it never flickers on the line
TownMarkers.Check = 0.25 -- seconds between checks
TownMarkers.FadeTime = 0.35 -- seconds
TownMarkers.MaxDistance = 350 -- studs from the camera

-- A one-line marker's height: studs (it shrinks with distance) plus a
-- pixel floor (what it keeps far away); a bit more floor on a phone.
TownMarkers.LineStuds = 1.8
TownMarkers.LinePixels = 20
TownMarkers.PhonePixels = 22
TownMarkers.Stacked = 2.3 -- a two-line marker (chip over label) is this much taller

-- The layouts, in fractions of the face's height (the face is the marker
-- above its ink drop edge, EDGE of its height).
local EDGE = 0.12
-- One line: the chip a square at the left, the label beside it.
local PAD = 0.12
local CHIP = 1 - PAD * 2
local CHAR = 0.42 -- a FredokaOne capital's width, with room, for a label CHIP tall
-- Two lines: the chip a square at the top, the label under it.
local S_PAD = 0.06
local S_CHIP = 0.34
local S_GAP = 0.02
local S_LABEL = 0.54
local S_SIDE = 0.07
local S_CHAR = 0.19 -- a capital's width, with room, for a line S_LABEL / 2 tall

-- How many lines `text` has, and its longest line's length.
function TownMarkers.Lines(text: string): (number, number)
	local lines, longest = 0, 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		lines += 1
		longest = math.max(longest, utf8.len(line) or #line)
	end
	return math.max(lines, 1), longest
end

-- The face's width over its height.
local function faceAspect(marker: Marker): number
	local lines, longest = TownMarkers.Lines(marker.text)
	if lines > 1 then
		return S_SIDE * 2 + math.max(S_CHIP, S_CHAR * longest)
	end
	return PAD + CHIP + PAD + CHAR * longest + PAD
end

-- The BillboardGui's Size: studs plus pixels, the same shape in both.
function TownMarkers.Size(marker: Marker, phone: boolean): UDim2
	local lines = TownMarkers.Lines(marker.text)
	local tall = if lines > 1 then TownMarkers.Stacked else 1
	local studs = TownMarkers.LineStuds * tall
	local pixels = math.floor((if phone then TownMarkers.PhonePixels else TownMarkers.LinePixels) * tall + 0.5)
	local aspect = faceAspect(marker) * (1 - EDGE) -- width over the whole marker's height
	return UDim2.new(studs * aspect, math.floor(pixels * aspect + 0.5), studs, pixels)
end

-- Should a marker show? Not while a shop screen is open, and not within
-- FadeWithin studs of you (back past ShowBeyond, from where it `was`). No
-- distance (no character yet): it shows.
function TownMarkers.Visible(distance: number?, shopOpen: boolean, was: boolean): boolean
	if shopOpen then
		return false
	end
	if distance == nil then
		return true
	end
	if was then
		return distance >= TownMarkers.FadeWithin
	end
	return distance > TownMarkers.ShowBeyond
end

---------------------------------------------------------------------------
-- Building one
---------------------------------------------------------------------------

-- A frame centred at (x, y) in its parent, w x h of it (Scale).
local function piece(
	parent: GuiObject,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	rotation: number?,
	round: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rotation or 0
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(round, 0)
		corner.Parent = f
	end
	f.Parent = parent
	return f
end

local function outline(f: GuiObject, color: Color3, thickness: number)
	UITheme.stroke(f, color, thickness)
end

local HEART = Color3.fromRGB(228, 189, 131) -- fresh-cut wood (BuildingArt)

-- The icon, drawn in the chip (a square: 0..1 both ways).
local ICONS: { [string]: (GuiObject) -> () } = {
	-- Three log ends stacked.
	logs = function(chip)
		for _, at in ipairs({ { 0.31, 0.64 }, { 0.69, 0.64 }, { 0.5, 0.33 } }) do
			local log = piece(chip, "LogEnd", at[1], at[2], 0.36, 0.36, HEART, 0, 0.5)
			outline(log, C.Bark, 1.5)
			piece(log, "Ring", 0.5, 0.5, 0.3, 0.3, C.AmberDeep, 0, 0.5)
		end
	end,
	-- An axe: a handle with a head at its top.
	axe = function(chip)
		piece(chip, "Handle", 0.46, 0.56, 0.13, 0.8, HEART, 40, 0.4)
		local head = piece(chip, "Head", 0.66, 0.31, 0.42, 0.26, C.Cream, 40, 0.25)
		outline(head, C.Ink, 1.5)
	end,
	-- A pickup: bed, cab with a window, two wheels.
	truck = function(chip)
		piece(chip, "Bed", 0.36, 0.55, 0.46, 0.22, C.Cream, 0, 0.15)
		piece(chip, "Cab", 0.7, 0.49, 0.26, 0.34, C.Cream, 0, 0.2)
		piece(chip, "Window", 0.73, 0.43, 0.14, 0.12, C.Ink, 0, 0.2)
		for _, x in ipairs({ 0.3, 0.7 }) do
			local wheel = piece(chip, "Wheel", x, 0.71, 0.22, 0.22, C.Ink, 0, 0.5)
			piece(wheel, "Hub", 0.5, 0.5, 0.36, 0.36, C.Cream, 0, 0.5)
		end
	end,
	-- A blueprint: a blue sheet with a house drawn on it.
	blueprint = function(chip)
		local sheet = piece(chip, "Sheet", 0.5, 0.52, 0.7, 0.58, C.Blue, -6, 0.1)
		outline(sheet, C.Cream, 1.5)
		piece(sheet, "Wall", 0.5, 0.66, 0.42, 0.04, C.Cream)
		piece(sheet, "Wall", 0.31, 0.53, 0.04, 0.3, C.Cream)
		piece(sheet, "Wall", 0.69, 0.53, 0.04, 0.3, C.Cream)
		piece(sheet, "Roof", 0.4, 0.3, 0.27, 0.05, C.Cream, -32)
		piece(sheet, "Roof", 0.6, 0.3, 0.27, 0.05, C.Cream, 32)
	end,
	-- A cabin hanging from its cable.
	gondola = function(chip)
		piece(chip, "Cable", 0.5, 0.27, 0.9, 0.06, C.Ink, -16)
		piece(chip, "Hanger", 0.5, 0.36, 0.06, 0.16, C.Ink)
		piece(chip, "Roof", 0.5, 0.45, 0.5, 0.08, C.Ink, 0, 0.3)
		local cabin = piece(chip, "Cabin", 0.5, 0.63, 0.44, 0.3, C.Bark, 0, 0.15)
		outline(cabin, C.Ink, 1.5)
		piece(cabin, "Window", 0.5, 0.4, 0.7, 0.32, C.Cream, 0, 0.2)
	end,
}

-- The marker's BillboardGui, hidden (Enabled false) until it's placed.
function TownMarkers.Build(marker: Marker, phone: boolean): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "TownMarker_" .. marker.name
	gui.ResetOnSpawn = false -- it lives in PlayerGui: a respawn would destroy it for good
	gui.Size = TownMarkers.Size(marker, phone)
	gui.StudsOffsetWorldSpace = marker.offset
	gui.SizeOffset = Vector2.new(0, 0.5) -- it stands on that point: its bottom edge there
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = TownMarkers.MaxDistance
	gui.ClipsDescendants = false
	gui.Enabled = false

	-- The ink drop edge, the face on it.
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.Size = UDim2.fromScale(1, 1)
	edge.BackgroundColor3 = C.Ink
	edge.BorderSizePixel = 0
	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(0.3, 0)
	edgeCorner.Parent = edge
	edge.Parent = gui
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1 - EDGE)
	face.BackgroundColor3 = C.Bark
	face.BorderSizePixel = 0
	local faceCorner = Instance.new("UICorner")
	faceCorner.CornerRadius = UDim.new(0.3, 0)
	faceCorner.Parent = face
	outline(face, C.Ink, 2)
	face.Parent = edge

	-- Lengths in the face's height, as fractions of its width.
	local aspect = faceAspect(marker)
	local function across(h: number): number
		return h / aspect
	end
	local lines = TownMarkers.Lines(marker.text)
	local stacked = lines > 1
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	if stacked then
		chip.AnchorPoint = Vector2.new(0.5, 0)
		chip.Position = UDim2.fromScale(0.5, S_PAD)
		chip.Size = UDim2.fromScale(across(S_CHIP), S_CHIP)
	else
		chip.Position = UDim2.fromScale(across(PAD), PAD)
		chip.Size = UDim2.fromScale(across(CHIP), CHIP)
	end
	chip.BackgroundColor3 = marker.chip
	chip.BorderSizePixel = 0
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0.25, 0)
	chipCorner.Parent = chip
	outline(chip, C.Cream, 1.5)
	chip.Parent = face
	local draw = ICONS[marker.icon]
	if draw then
		draw(chip)
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	if stacked then
		label.Position = UDim2.fromScale(across(S_SIDE), S_PAD + S_CHIP + S_GAP)
		label.Size = UDim2.fromScale(1 - across(S_SIDE * 2), S_LABEL)
		label.TextXAlignment = Enum.TextXAlignment.Center
	else
		label.Position = UDim2.fromScale(across(PAD + CHIP + PAD), PAD)
		label.Size = UDim2.fromScale(1 - across(PAD + CHIP + PAD + PAD), CHIP)
		label.TextXAlignment = Enum.TextXAlignment.Left
	end
	label.Font = Enum.Font.FredokaOne -- the world signs' face (Kit.signText)
	label.Text = marker.text
	label.TextColor3 = C.Cream
	label.TextScaled = true
	label.TextWrapped = false
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.LineHeight = 0.95
	label.Parent = face
	return gui
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

-- One transparency a fade moves: `prop` of `inst`, from `base` (shown).
type Look = { inst: Instance, prop: string, base: number }

type Live = {
	marker: Marker,
	gui: BillboardGui,
	part: BasePart?,
	shown: boolean,
	alpha: NumberValue, -- 0 shown, 1 gone (tweened)
	looks: { Look },
	tween: Tween?,
}

local live: { Live } = {}

-- Every surface's own transparency, so a fade can go from it to gone.
local function looksOf(gui: BillboardGui): { Look }
	local out: { Look } = {}
	local function add(inst: Instance, prop: string, base: number)
		table.insert(out, { inst = inst, prop = prop, base = base })
	end
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") then
			add(d, "TextTransparency", d.TextTransparency)
			add(d, "BackgroundTransparency", d.BackgroundTransparency)
		elseif d:IsA("GuiObject") then
			add(d, "BackgroundTransparency", d.BackgroundTransparency)
		elseif d:IsA("UIStroke") then
			add(d, "Transparency", d.Transparency)
		end
	end
	return out
end

local function apply(entry: Live, alpha: number)
	for _, look in ipairs(entry.looks) do
		(look.inst :: any)[look.prop] = look.base + (1 - look.base) * alpha
	end
end

local function fade(entry: Live, show: boolean)
	if entry.shown == show then
		return
	end
	entry.shown = show
	local old = entry.tween
	if old then
		old:Cancel()
	end
	if show then
		entry.gui.Enabled = entry.part ~= nil
	end
	local tween = TweenService:Create(
		entry.alpha,
		TweenInfo.new(TownMarkers.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = if show then 0 else 1 }
	)
	entry.tween = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and not entry.shown then
			entry.gui.Enabled = false -- gone: nothing left to draw
		end
	end)
	tween:Play()
end

-- Calls `fn` with `parent`'s child `name` now if it's there, and whenever
-- one arrives (it streams in, or is replaced). Never yields, so it never
-- waits forever (and never warns that it might).
local function whenChild(parent: Instance, name: string, fn: (Instance) -> ())
	local found = parent:FindFirstChild(name)
	if found then
		fn(found)
	end
	parent.ChildAdded:Connect(function(child: Instance)
		if child.Name == name then
			fn(child)
		end
	end)
end

-- Follows `path` down from `root`, calling `fn` with each part found at
-- its end (as it streams in).
local function follow(root: Instance, path: { string }, depth: number, fn: (BasePart) -> ())
	whenChild(root, path[depth], function(child: Instance)
		if depth < #path then
			follow(child, path, depth + 1, fn)
		elseif child:IsA("BasePart") then
			fn(child)
		end
	end)
end

-- Is a shop screen open? (ShopUI shows its ScreenGui only while one is.)
local function shopOpen(playerGui: Instance): boolean
	local shop = playerGui:FindFirstChild("ShopUI")
	return shop ~= nil and shop:IsA("ScreenGui") and shop.Enabled
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function TownMarkers.Start()
	local player = Players.LocalPlayer
	local playerGui = UITheme.PlayerGui()
	local phone = UITheme.IsPhone()

	for _, marker in ipairs(TownMarkers.Markers) do
		local gui = TownMarkers.Build(marker, phone)
		local alpha = Instance.new("NumberValue")
		alpha.Value = 0
		local entry: Live = {
			marker = marker,
			gui = gui,
			part = nil,
			shown = true,
			alpha = alpha,
			looks = looksOf(gui),
			tween = nil,
		}
		alpha.Changed:Connect(function(value: number)
			apply(entry, value)
		end)
		gui.Parent = playerGui
		table.insert(live, entry)
	end

	-- Each marker goes up when its part streams in (TimberlineMap first).
	whenChild(workspace, "TimberlineMap", function(map: Instance)
		for _, entry in ipairs(live) do
			follow(map, entry.marker.path, 1, function(part: BasePart)
				entry.part = part
				entry.gui.Adornee = part
				entry.gui.Enabled = entry.shown
			end)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < TownMarkers.Check then
			return
		end
		elapsed = 0
		-- A phone turned (or a window resized) gets its own pixel floor.
		local nowPhone = UITheme.IsPhone()
		local resize = nowPhone ~= phone
		phone = nowPhone
		local open = shopOpen(playerGui)
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local from = if root and root:IsA("BasePart") then root.Position else nil
		for _, entry in ipairs(live) do
			if resize then
				entry.gui.Size = TownMarkers.Size(entry.marker, phone)
			end
			local part = entry.part
			if part and part.Parent == nil then
				-- Gone (it streams back in through whenChild).
				entry.part = nil
				local gui: any = entry.gui -- Adornee's type has no nil
				gui.Adornee = nil
				gui.Enabled = false
				part = nil
			end
			if part then
				local distance = if from then flatDistance(from, part.Position) else nil
				fade(entry, TownMarkers.Visible(distance, open, entry.shown))
			end
		end
	end)
end

return TownMarkers
