--!strict
-- LogicItems: the wired pieces of a plot (V2_PLAN.md §10). PlotData appends
-- this list to its blueprints. WireLogic joins them; LogicService runs them.
--
-- Bought once, boxed, then placed free. The two originals (Wall Switch,
-- Spark Lamp) stay Hearth & Home unlocks until Sparkworks is stocked from
-- SparkworksStock. Every new piece is gated so it is not a free starter
-- plan. Cash only: no gathered material.
--
-- Hex values are BuildingArt palette names (comments). Part budget: at most
-- five boxes, and at most one light.

local V2 = Vector2.new
local V3 = Vector3.new

-- Palette (BuildingArt): IRON, STEEL, STEEL_DARK, BRASS, GLOW, EMBER,
-- TIMBER, ANVIL, BRICK. The Wall Switch and Spark Lamp keep the
-- colours they already shipped with.

local IRON = "#3B3634"
local STEEL = "#C9CED3"
local BRASS = "#C9A24A"
local GLOW = "#FFC872"
local EMBER = "#FF7A2E"
local TIMBER = "#5B3920"
local ANVIL = "#3C3F48"
local BRICK = "#A8553D"

local METAL = "#3C3C41" -- the shipped switch post

-- The same hexes as UITheme.Colors. Lane U owns that module, so the plate
-- and the strips quote the tokens instead of requiring it.
local INK = "#3C2814" -- Ink
local CREAM = "#F5EBD7" -- Cream
local ACCENT = {
	GateAnd = "#4C8C40", -- Green
	GateOr = "#FFB840", -- Amber
	GateXor = "#2F6DB5", -- Blue
	GateNot = "#C0503A", -- Danger
	Delay = "#8FD3F2", -- Sky
	Sustain = "#D08F1F", -- AmberDeep
	Clock = "#BFE8FF", -- Ice
}
local MARK = {
	GateAnd = "AND",
	GateOr = "OR",
	GateXor = "XOR",
	GateNot = "NOT",
	Delay = "DLY",
	Sustain = "HOLD",
	Clock = "CLK",
}

type Box = {
	size: Vector3,
	offset: Vector3,
	color: string,
	material: string,
	light: boolean?,
	leaf: boolean?,
}

local function strip(color: string, z: number, width: number?): Box
	return {
		size = V3(width or 1.4, 0.14, 0.16),
		offset = V3(0, 0.22, z),
		color = color,
		material = "SmoothPlastic",
	}
end

type Item = {
	id: string,
	displayName: string,
	category: string,
	priceCash: number,
	tier: number,
	footprint: Vector2,
	boxes: { Box },
	note: string?,
	unlock: boolean?,
	gated: boolean?,
}

local items: { Item } = {
	{
		id = "SparkSwitch",
		displayName = "Wall Switch",
		category = "Decor",
		priceCash = 100,
		unlock = true,
		tier = 1,
		footprint = V2(2, 2),
		-- Box 3 is the lever. LogicService tips it when the switch is on.
		boxes = {
			{ size = V3(0.4, 3.2, 0.4), offset = V3(0, 1.6, 0), color = METAL, material = "Metal" },
			{ size = V3(1.2, 1.4, 0.3), offset = V3(0, 3.4, 0), color = "#9AA0A6", material = "Metal" },
			{ size = V3(0.25, 1, 0.25), offset = V3(0, 3.4, 0.25), color = "#C8402F", material = "Metal" },
		},
		note = "Flip it. Wire it to a lamp, a door or a gate",
	},
	{
		id = "SparkLamp",
		displayName = "Spark Lamp",
		category = "Decor",
		priceCash = 150,
		unlock = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(0.4, 5, 0.4), offset = V3(0, 2.5, 0), color = METAL, material = "Metal" },
			{
				size = V3(1.4, 1.1, 1.4),
				offset = V3(0, 5.5, 0),
				color = "#FFE9A8",
				material = "Neon",
				light = true,
			},
		},
		note = "Lit until you wire it, then it follows the wire",
	},
	{
		id = "Button",
		displayName = "Button",
		category = "Decor",
		priceCash = 320,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 0.3, 1.4), offset = V3(0, 0.15, 0), color = STEEL, material = "Metal" },
			{ size = V3(0.4, 0.6, 0.4), offset = V3(0, 0.6, 0), color = IRON, material = "Metal" },
			{ size = V3(1, 0.35, 1), offset = V3(0, 1.05, 0), color = EMBER, material = "Metal" },
		},
		note = "On for one second when you press it",
	},
	{
		id = "Lever",
		displayName = "Lever",
		category = "Decor",
		priceCash = 520,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		-- Box 3 is the handle. LogicService tips it when the lever is on.
		boxes = {
			{ size = V3(0.4, 2.2, 0.4), offset = V3(0, 1.1, 0), color = IRON, material = "Metal" },
			{ size = V3(1.2, 1.2, 0.3), offset = V3(0, 2.4, 0), color = STEEL, material = "Metal" },
			{ size = V3(0.25, 0.9, 0.25), offset = V3(0, 2.4, 0.25), color = BRASS, material = "Metal" },
		},
		note = "Stays on or off until you flip it again",
	},
	{
		id = "PressurePlate",
		displayName = "Pressure Plate",
		category = "Decor",
		priceCash = 640,
		gated = true,
		tier = 1,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(3.6, 0.25, 3.6), offset = V3(0, 0.125, 0), color = ANVIL, material = "Metal" },
			{ size = V3(3.2, 0.2, 3.2), offset = V3(0, 0.35, 0), color = STEEL, material = "Metal" },
			{
				size = V3(0.4, 0.3, 0.4),
				offset = V3(0, 0.55, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "On while a player or a piece of wood rests on it",
	},
	{
		id = "GateAnd",
		displayName = "AND Gate",
		category = "Decor",
		priceCash = 260,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = INK, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(-0.45, 1.15, 0.4), color = STEEL, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0.45, 1.15, 0.4), color = STEEL, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
			strip(ACCENT.GateAnd, 0.64),
		},
		note = "On only when both inputs are on",
	},
	{
		id = "GateOr",
		displayName = "OR Gate",
		category = "Decor",
		priceCash = 260,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = INK, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(-0.45, 1.15, 0.4), color = BRASS, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0.45, 1.15, 0.4), color = BRASS, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
			strip(ACCENT.GateOr, 0.64),
		},
		note = "On when either input is on",
	},
	{
		id = "GateXor",
		displayName = "XOR Gate",
		category = "Decor",
		priceCash = 260,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = INK, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(-0.45, 1.15, 0.4), color = BRICK, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0.45, 1.15, 0.4), color = BRICK, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
			strip(ACCENT.GateXor, 0.64),
		},
		note = "On when the inputs disagree",
	},
	{
		id = "GateNot",
		displayName = "NOT Gate",
		category = "Decor",
		priceCash = 200,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = INK, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0, 1.15, 0.4), color = STEEL, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
			strip(ACCENT.GateNot, 0.64),
		},
		note = "On when its input is off",
	},
	{
		id = "Delay",
		displayName = "Delay",
		category = "Decor",
		priceCash = 520,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.5, 1.1, 1.2), offset = V3(0, 0.55, 0), color = INK, material = "Wood" },
			strip(ACCENT.Delay, 0.58, 1.5),
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0.55, 1.25, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "Passes a signal through after the time you set",
	},
	{
		id = "Sustain",
		displayName = "Sustain",
		category = "Decor",
		priceCash = 520,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.5, 1.1, 1.2), offset = V3(0, 0.55, 0), color = INK, material = "Wood" },
			strip(ACCENT.Sustain, 0.58, 1.5),
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0.55, 1.25, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "Stays on for the time you set after the signal drops",
	},
	{
		id = "Clock",
		displayName = "Clock",
		category = "Decor",
		priceCash = 902,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 0.8, 1.4), offset = V3(0, 0.4, 0), color = INK, material = "Metal" },
			strip(ACCENT.Clock, 0.64),
			{
				size = V3(0.35, 0.35, 0.3),
				offset = V3(0, 1.05, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "Blinks on and off over the period you set",
	},
	{
		id = "GlowWire",
		displayName = "Glow Wire",
		category = "Decor",
		priceCash = 720,
		gated = true,
		tier = 1,
		footprint = V2(4, 2),
		boxes = {
			{
				size = V3(3.4, 0.28, 0.28),
				offset = V3(0, 0.55, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
			{ size = V3(0.3, 0.5, 0.3), offset = V3(-1.7, 0.25, 0), color = IRON, material = "Metal" },
			{ size = V3(0.3, 0.5, 0.3), offset = V3(1.7, 0.25, 0), color = IRON, material = "Metal" },
		},
		note = "A wire that lights while its input is on",
	},
	{
		id = "Hatch",
		displayName = "Hatch",
		category = "Decor",
		priceCash = 830,
		gated = true,
		tier = 1,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(3.8, 0.2, 3.8), offset = V3(0, 0.1, 0), color = TIMBER, material = "Wood" },
			{
				size = V3(3.2, 0.16, 3.2),
				offset = V3(0, 0.28, 0),
				color = BRASS,
				material = "Metal",
				leaf = true,
			},
			{ size = V3(3.4, 0.2, 0.25), offset = V3(0, 0.4, 1.5), color = IRON, material = "Metal" },
		},
		note = "A floor door that opens while it is on",
	},
}

-- Lane K ships one MeshTemplates model per piece id. The named slots are
-- the look; the boxes stay the collider when a slot is missing.
local SLOTS = { "Body", "Indicator", "Moving", "LabelFace" }

local MeshKit = require(script.Parent.Art.MeshKit)

local known: { [string]: boolean } = {}
for _, item in ipairs(items) do
	known[item.id] = true
end

local installed: { [string]: Model } = {}
local logged: { [string]: boolean } = {}

local function logMiss(id: string)
	if logged[id] then
		return
	end
	logged[id] = true
	warn(string.format("[LogicItems] %s has no MeshTemplates model; keeping the part build", id))
end

local function findTemplate(id: string): Model?
	local held = installed[id]
	if held then
		return held
	end
	local ok, folder = pcall(function()
		return game:GetService("ReplicatedStorage"):FindFirstChild("MeshTemplates")
	end)
	if not ok or folder == nil then
		return nil
	end
	local inst = (folder :: Instance):FindFirstChild(id)
	if inst and inst:IsA("Model") then
		return inst
	end
	return nil
end

-- Clones Body, Indicator, Moving and LabelFace from the piece's
-- MeshTemplates model. Indicator is the lamp or LED. Moving is the lever
-- handle, button cap, hatch door or plate top. LabelFace carries the gate
-- label. A missing model, or one with none of those slots, keeps the part
-- build and is logged once.
local function applyMeshes(model: Model, id: string, ghost: boolean?): boolean
	if not known[id] then
		return false
	end
	local template = findTemplate(id)
	local root = model:FindFirstChild("Root")
	if template == nil or root == nil or not root:IsA("BasePart") then
		logMiss(id)
		return false
	end
	local pivot = template:GetPivot()
	local made: { BasePart } = {}
	for _, slot in ipairs(SLOTS) do
		local src = template:FindFirstChild(slot)
		if src and src:IsA("BasePart") then
			local part = src:Clone()
			part.Name = slot
			part:SetAttribute("LogicMesh", true)
			if part:IsA("MeshPart") then
				local raw = part:GetAttribute("MeshId")
				local meshId = 0
				if type(raw) == "string" then
					meshId = tonumber(raw) or 0
				elseif type(raw) == "number" then
					meshId = raw
				end
				MeshKit.Visual(part, meshId)
			else
				part.Massless = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
			part.Anchored = true
			if ghost then
				part.Transparency = 0.45
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
			part.CFrame = root.CFrame * pivot:ToObjectSpace(src.CFrame)
			part.Parent = model
			if slot == "Moving" or slot == "Indicator" then
				part:SetAttribute("RestOffset", root.CFrame:ToObjectSpace(part.CFrame))
			end
			if slot == "Indicator" then
				part:SetAttribute("LitColor", part.Color)
			end
			table.insert(made, part)
		end
	end
	if #made == 0 then
		logMiss(id)
		return false
	end
	local indicator = model:FindFirstChild("Indicator")
	if indicator and indicator:IsA("BasePart") then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child:GetAttribute("LogicMesh") ~= true then
				local light = child:FindFirstChildOfClass("PointLight")
				if light and light.Parent ~= indicator then
					light.Parent = indicator
				end
			end
		end
	end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child ~= root and child:GetAttribute("LogicMesh") ~= true then
			child.Transparency = 1
		end
	end
	return true
end

-- Tests hand a stand-in model. Nil id forgets every stand-in.
local function installMesh(id: string?, model: Model?)
	if id == nil then
		table.clear(installed)
		table.clear(logged)
		return
	end
	installed[id] = model :: Model
	logged[id] = nil
end

local function fellBack(id: string): boolean
	return logged[id] == true
end

-- A readable name on the dark top of a gate, in cream GothamBold.
-- BlueprintModels calls this for every build, ghost included.
-- The label sits on LabelFace when the mesh supplied one.
local function dress(model: Model, id: string)
	local text = MARK[id]
	if text == nil then
		return
	end
	local host = model:FindFirstChild("LabelFace")
	if host == nil or not host:IsA("BasePart") then
		host = model:FindFirstChild("Part1")
	end
	if host == nil or not host:IsA("BasePart") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Mark"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 70
	gui.LightInfluence = 0
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromHex(CREAM)
	label.Text = text
	label.Parent = gui
end

local api = items :: any
api.Dress = dress
api.ApplyMeshes = applyMeshes
api.InstallMesh = installMesh
api.FellBack = fellBack
api.Slots = SLOTS
api.Mark = MARK
api.Accent = ACCENT

return items
