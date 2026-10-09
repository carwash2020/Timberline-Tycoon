--!strict
-- MachineArt: the sawmills you place on a plot (V2_PLAN.md §7). Each one is
-- a low-poly shed with an Intake box (the log goes in the back), an Output
-- attachment (planks leave the front) and a Panel of X/Y buttons. The
-- SawBlade is tagged so the town's blade spin picks it up. A ghost is the
-- same model, see-through, for the plot preview.
--
-- Collision (three groups, registered in WoodService):
--   * "Mill" — the roof and the invisible FeedGuard / BladeGuard. Players
--     bump them and can't walk into the saw. Loose and carried logs do not,
--     so a feed can pass the blade without jamming on it.
--   * "MillBelt" — the Conveyor. It collides with loose logs and its
--     AssemblyLinearVelocity (AimBelt) runs along the belt, toward +Z.
--     Players, held logs and falling trees do not ride it.
--   * Default — the deck, the walls and the guard rails. Logs bump the
--     walls instead of sliding through them; the belt is wide enough for
--     this mill's thickest log, and the rails sit just outside that, so a
--     log snapped to the belt never meets a wall.

local CollectionService = game:GetService("CollectionService")

local ChopSawLogic = require(script.Parent.Parent.ChopSawLogic)
local GameConfig = require(script.Parent.Parent.GameConfig)
local InputKit = require(script.Parent.Parent.InputKit)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local AutomationLogic = require(script.Parent.Parent.AutomationLogic)
local PlanerLogic = require(script.Parent.Parent.PlanerLogic)
local BuildingArt = require(script.Parent.BuildingArt)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local SawmillLogic = require(script.Parent.Parent.SawmillLogic)
local SkyBinLogic = require(script.Parent.Parent.SkyBinLogic)
local Util = require(script.Parent.Parent.Util)

local MachineArt = {}

-- Keep these equal to WoodService.MillGroup / MillBeltGroup.
local MILL_GROUP = "Mill"
local BELT_GROUP = "MillBelt"

local WOOD = Palette.TimberBrown
local WOOD_DARK = Kit.shade(Palette.TimberBrown, -0.35)
local BLADE = Kit.hex("#D5D8DC")
local PANEL = Kit.hex("#2C241C")
local BELT = Kit.hex("#3A342F")

local function touchless(p: BasePart): BasePart
	p.CanTouch = false
	return p
end

local function inGroup(p: BasePart, group: string): BasePart
	p.CollisionGroup = group
	p.CanTouch = false
	return p
end

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	ghost: boolean,
	collide: boolean
): Part
	local p = Kit.part(model, name, size, cf, color, material)
	if ghost then
		p.Transparency = if name == "Root" or name == "Intake" then 1 else 0.45
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	elseif not collide then
		Kit.decor(p)
	end
	return p
end

-- Offset pixels on the surface canvas. 48 px is past a 44 px fingertip
-- even before the screen panel (SawmillLogic.PanelFacePx) is open.
local function button(parent: Instance, name: string, text: string, x: number, axis: string, dir: number)
	local px = SawmillLogic.SurfaceButtonPx
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(px, px)
	b.Position = UDim2.fromOffset(x, 52)
	b.BackgroundColor3 = Kit.hex("#C4A574")
	b.TextColor3 = Kit.hex("#2C241C")
	b.Font = Enum.Font.GothamBold
	b.TextSize = SawmillLogic.PanelTextPx
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Active = true
	b.Selectable = true
	b:SetAttribute("Axis", axis)
	b:SetAttribute("Dir", dir)
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = SawmillLogic.PanelTextPx
	fit.MinTextSize = 14
	fit.Parent = b
	b.Parent = parent
end

-- The cut board on the +X side of a sawmill or a planer: the size readout,
-- the limit under it, four 48 px buttons (X-, X+, Y-, Y+) and the prompt
-- that opens the screen panel. Front is the big face (5.6 x 2.8 studs).
function MachineArt.AddPanel(model: Model, w: number, objectText: string, actionText: string, limit: string)
	local panel = part(
		model,
		"Panel",
		Vector3.new(5.6, 2.8, 0.25),
		CFrame.lookAt(Vector3.new(w / 2 + 0.3, 3.4, 0.2), Vector3.new(w / 2 + 8, 3.4, 0.2)),
		PANEL,
		Enum.Material.Wood,
		false,
		false
	)
	panel.CanQuery = true
	panel.CanTouch = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PanelGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SawmillLogic.SurfacePixelsPerStud
	gui.Parent = panel
	local function line(name: string, y: number, h: number, text: string)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Size = UDim2.fromOffset(208, h)
		label.Position = UDim2.fromOffset(8, y)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = SawmillLogic.PanelTextPx
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Kit.hex("#F3E6C8")
		label.Text = text
		label.Parent = gui
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = SawmillLogic.PanelTextPx
		fit.MinTextSize = if name == "LimitReadout" then 10 else 14
		fit.Parent = label
	end
	line("CutReadout", 2, 26, "1.00 × 0.60 u")
	line("LimitReadout", 28, 20, limit)
	-- 48 px buttons, 6 px apart, inside a 5.6-stud face at 40 px/stud.
	button(gui, "XMinus", "X-", 8, "x", -1)
	button(gui, "XPlus", "X+", 62, "x", 1)
	button(gui, "YMinus", "Y-", 116, "y", -1)
	button(gui, "YPlus", "Y+", 170, "y", 1)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CutPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = SawmillLogic.PromptRange
	prompt.HoldDuration = 0
	prompt.ClickablePrompt = true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.Parent = panel
end

-- Materials by tier (1 Rickety to 5 Industrial): the roof and walls get
-- better as the mill does.
local WALL_MATERIAL = {
	Enum.Material.Wood,
	Enum.Material.Wood,
	Enum.Material.WoodPlanks,
	Enum.Material.Metal,
	Enum.Material.DiamondPlate,
} :: { Enum.Material }
local ROOF_MATERIAL = {
	Enum.Material.WoodPlanks,
	Enum.Material.WoodPlanks,
	Enum.Material.CorrodedMetal,
	Enum.Material.Metal,
	Enum.Material.DiamondPlate,
} :: { Enum.Material }
local ROOF_COLOR = {
	Palette.BarnRed,
	Palette.TimberBrown,
	Palette.WeatheredPlank,
	Palette.RoofSlate,
	Palette.PineTrim,
} :: { Color3 }
local BRASS = Palette.Brass
local IRON = Palette.IronBlack

local function lookPart(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material,
	ghost: boolean
): Part
	return part(model, name, size, cf, color, mat, ghost, false)
end

-- The detail each tier adds on top of the same shed (more per tier, inside a
-- part budget MachineArt.Budget(tier)): 2 braces and posts, 3 a stack and a
-- plate, 4 a boiler with a dome and gauge, 5 a gantry and lamps. Every tier
-- also carries a TierSign with its name. Looks only; nothing here collides.
function MachineArt.TierDetail(
	model: Model,
	tier: number,
	w: number,
	d: number,
	roofBottom: number,
	name: string,
	ghost: boolean
)
	local top = roofBottom + 0.28
	if tier >= 2 then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				lookPart(
					model,
					"Post",
					Vector3.new(0.55, roofBottom, 0.55),
					CFrame.new(sx * (w / 2 - 0.3), roofBottom / 2, sz * (d / 2 - 0.45)),
					WOOD_DARK,
					Enum.Material.Wood,
					ghost
				)
			end
		end
	end
	if tier >= 3 then
		local stack = Kit.cylinder(
			model,
			"Stack",
			3,
			0.9,
			CFrame.new(w / 4, top + 1.5, -d / 4) * CFrame.Angles(0, 0, math.pi / 2),
			IRON,
			Enum.Material.Metal
		)
		local cap = Kit.cylinder(
			model,
			"StackCap",
			0.4,
			1.3,
			CFrame.new(w / 4, top + 3.1, -d / 4) * CFrame.Angles(0, 0, math.pi / 2),
			IRON,
			Enum.Material.Metal
		)
		for _, p in ipairs({ stack, cap }) do
			if ghost then
				p.Transparency = 0.45
			end
			Kit.decor(p)
		end
		lookPart(
			model,
			"MakerPlate",
			Vector3.new(1.6, 0.8, 0.12),
			CFrame.new(0, roofBottom - 0.6, d / 2 - 0.5),
			BRASS,
			Enum.Material.Metal,
			ghost
		)
	end
	if tier >= 4 then
		local boiler = Kit.cylinder(
			model,
			"Boiler",
			math.max(3, d - 3),
			1.9,
			CFrame.new(-w / 4, top + 0.95, 0) * CFrame.Angles(0, math.pi / 2, 0),
			BRASS,
			Enum.Material.Metal
		)
		local dome = Kit.cylinder(
			model,
			"BoilerDome",
			0.7,
			1.1,
			CFrame.new(-w / 4, top + 2.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
			BRASS,
			Enum.Material.Metal
		)
		for _, p in ipairs({ boiler, dome }) do
			if ghost then
				p.Transparency = 0.45
			end
			Kit.decor(p)
		end
		lookPart(
			model,
			"Gauge",
			Vector3.new(0.5, 0.5, 0.15),
			CFrame.new(-w / 4, top + 1.0, -(d - 3) / 2 - 0.15),
			Kit.hex("#F3E6C8"),
			Enum.Material.SmoothPlastic,
			ghost
		)
	end
	if tier >= 5 then
		lookPart(
			model,
			"Gantry",
			Vector3.new(w - 1, 0.5, 0.5),
			CFrame.new(0, top + 3.3, 0),
			Kit.hex("#E0A030"),
			Enum.Material.DiamondPlate,
			ghost
		)
		for _, sx in ipairs({ -1, 1 }) do
			lookPart(
				model,
				"GantryLeg",
				Vector3.new(0.45, 3.3, 0.45),
				CFrame.new(sx * (w / 2 - 0.8), top + 1.65, 0),
				Kit.hex("#E0A030"),
				Enum.Material.DiamondPlate,
				ghost
			)
			local lamp = lookPart(
				model,
				"Lamp",
				Vector3.new(0.5, 0.5, 0.5),
				CFrame.new(sx * (w / 2 - 0.8), top + 3.0, 0.6),
				Kit.hex("#FFE2A0"),
				Enum.Material.Neon,
				ghost
			)
			if not ghost then
				local light = Instance.new("PointLight")
				light.Range = 14
				light.Brightness = 1.2
				light.Shadows = false
				light.Color = Kit.hex("#FFD59A")
				light.Parent = lamp
			end
		end
	end
	local sign = lookPart(
		model,
		"TierSign",
		Vector3.new(3.4, 0.9, 0.2),
		CFrame.new(0, top + 0.5, d / 2 - 0.5),
		PANEL,
		Enum.Material.Wood,
		ghost
	)
	if not ghost then
		Kit.signText(sign, string.upper(name), Kit.hex("#F3E6C8"))
	end
end

-- The most parts a machine of this tier may have (specs hold the art to it).
function MachineArt.Budget(tier: number): number
	return 20 + 7 * (math.clamp(tier, 1, 5) - 1) + 1
end

-- The BLOCKAGE board. Hidden until a piece won't fit the opening.
function MachineArt.SetBlockage(model: Model, on: boolean)
	local sign = model:FindFirstChild("Blockage", true)
	if not sign or not sign:IsA("BasePart") then
		return
	end
	sign.Transparency = if on then 0 else 1
	for _, d in ipairs(sign:GetChildren()) do
		if d:IsA("SurfaceGui") then
			d.Enabled = on
		end
	end
end

-- The cut readout, "1.00 × 0.60 u", and (when given) the limit under it,
-- "up to 1.8 × 1.2 u, steps of 0.2". Two decimals: the top tier steps by 0.05.
function MachineArt.SetCut(model: Model, x: number, y: number, limit: string?)
	local label = model:FindFirstChild("CutReadout", true)
	if label and label:IsA("TextLabel") then
		label.Text = string.format("%.2f × %.2f u", x, y)
	end
	if limit then
		local lim = model:FindFirstChild("LimitReadout", true)
		if lim and lim:IsA("TextLabel") then
			lim.Text = limit
		end
	end
end

-- Points every belt part's conveyor velocity along its own front (+Z of the
-- part; a turn piece has three, each its own way). `speed` is studs a second
-- (BeltService passes 0 while a belt is off; the default is the sawmill's
-- ConveyorSpeed). A ghost has nothing to push. Safe to call every poll;
-- placement can turn the machine, and the velocity is in world space.
-- A negative speed runs the belt backwards (Lane W reverse). A Switch
-- Belt's cross bands (attribute Cross) run toward the model's Side (+1 is
-- +X as built, -1 is -X), and the diverter turns to match.
function MachineArt.AimBelt(model: Model, speed: number?)
	local v = if speed == nil then GameConfig.ConveyorSpeed else speed
	local sideAttr = model:GetAttribute("Side")
	local side = if sideAttr == -1 then -1 else 1
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "Conveyor" and d:IsA("BasePart") and d.CanCollide then
			local look = d.CFrame.LookVector
			if look.Magnitude >= 1e-4 then
				local sign = if d:GetAttribute("Cross") == true then side else 1
				d.AssemblyLinearVelocity = look.Unit * (v * sign)
			end
		end
	end
	if model:GetAttribute("BeltShape") == "switch" and model:GetAttribute("GateSide") ~= side then
		MachineArt.SetSwitchSide(model, side)
	end
end

-- `ghost` is the placement preview: nothing collides and there are no buttons.
function MachineArt.Build(millId: string, ghost: boolean?): Model?
	local mill = ItemCatalog.GetSawmill(millId)
	if not mill then
		return nil
	end
	local preview = ghost == true
	local w, d = mill.width, mill.depth
	local frame = Kit.hex(mill.color)
	local model = Kit.model(mill.id)
	-- Thickest log this mill accepts, in studs. The belt is that wide plus
	-- a margin; the rails stand just outside it.
	local logDia = mill.maxWidth * GameConfig.WoodUnit
	local beltTop = 0.72
	local beltH = 0.32
	local beltY = beltTop - beltH / 2
	local beltW = logDia + 0.55
	local beltLen = math.max(3, d - 1.8)

	local root =
		part(model, "Root", Vector3.new(w, 0.2, d), CFrame.new(0, 0.1, 0), WOOD, Enum.Material.Wood, true, false)
	root.Transparency = 1
	model.PrimaryPart = root

	local deck = part(
		model,
		"Deck",
		Vector3.new(w - 0.4, 0.4, d - 0.4),
		CFrame.new(0, 0.2, 0),
		WOOD,
		Enum.Material.WoodPlanks,
		preview,
		true
	)
	if not preview then
		touchless(deck)
	end

	-- LookVector +Z (a half turn; Lune's lookAt disagrees with Roblox).
	-- Length runs along Z, from the infeed to the outfeed.
	local belt = part(
		model,
		"Conveyor",
		Vector3.new(beltW, beltH, beltLen),
		CFrame.new(0, beltY, 0) * CFrame.Angles(0, math.pi, 0),
		BELT,
		Enum.Material.Metal,
		preview,
		true
	)
	if not preview then
		inGroup(belt, BELT_GROUP)
		MachineArt.AimBelt(model)
	end

	local tier = math.clamp(mill.tier, 1, 5)
	local roofBottom = math.max(beltTop + logDia + 2.4, 5.4)
	local wallH = roofBottom - 0.4
	local wallY = 0.4 + wallH / 2
	for _, side in ipairs({ -1, 1 }) do
		local wall = part(
			model,
			"Wall",
			Vector3.new(0.65, wallH, d - 1.2),
			CFrame.new(side * (w / 2 - 0.5), wallY, 0),
			frame,
			WALL_MATERIAL[tier],
			preview,
			true
		)
		local rail = part(
			model,
			"GuardRail",
			Vector3.new(0.28, 1.35, beltLen - 0.4),
			CFrame.new(side * (logDia / 2 + 0.55), 0.4 + 0.75, 0),
			WOOD_DARK,
			Enum.Material.Wood,
			preview,
			true
		)
		if not preview then
			touchless(wall)
			touchless(rail)
		end
	end

	-- Invisible end walls: players stop, a log on the belt passes through
	-- (Mill group). They meet the roof so there is no gap to jump.
	for _, endZ in ipairs({ -(d / 2 - 0.85), d / 2 - 0.85 }) do
		local gate = part(
			model,
			"FeedGuard",
			Vector3.new(w - 1.7, wallH, 0.45),
			CFrame.new(0, wallY, endZ),
			WOOD,
			Enum.Material.Wood,
			preview,
			true
		)
		gate.Transparency = 1
		gate.CastShadow = false
		if not preview then
			inGroup(gate, MILL_GROUP)
		end
	end

	local roof = part(
		model,
		"Roof",
		Vector3.new(w, 0.36, d - 0.2),
		CFrame.new(0, roofBottom + 0.1, 0),
		if tier >= 3 then ROOF_COLOR[tier] else frame,
		ROOF_MATERIAL[tier],
		preview,
		true
	)
	if not preview then
		inGroup(roof, MILL_GROUP)
	end

	-- Disc in the XY plane (its X axis, the axle, runs along Z) so a log
	-- fed along the belt passes through it once. TownFX spins that axle.
	local bladeD = math.max(logDia + 1.2, 3.4)
	local bladeCf = CFrame.new(0, beltTop + bladeD / 2, 0.35) * CFrame.Angles(0, math.pi / 2, 0)
	local blade = Kit.cylinder(model, "SawBlade", 0.22, bladeD, bladeCf, BLADE, Enum.Material.Metal)
	if preview then
		blade.Transparency = 0.45
		blade.CanCollide = false
		blade.CanQuery = false
		blade.CanTouch = false
	else
		Kit.decor(blade)
		CollectionService:AddTag(blade, "SawBlade")
	end
	local guard = part(
		model,
		"BladeGuard",
		Vector3.new(bladeD + 0.8, bladeD + 0.6, 1.3),
		CFrame.new(0, beltTop + bladeD / 2, 0.35),
		WOOD,
		Enum.Material.SmoothPlastic,
		preview,
		true
	)
	guard.Transparency = 1
	guard.CastShadow = false
	if not preview then
		inGroup(guard, MILL_GROUP)
	end

	-- The log is pushed in from the back (-Z). The box is tall enough that a
	-- log lying on the ground overlaps it.
	local intake = part(
		model,
		"Intake",
		Vector3.new(math.max(4, w - 3), 5, 5),
		CFrame.new(0, 2.6, -d / 2 + 0.4),
		WOOD,
		Enum.Material.SmoothPlastic,
		true,
		false
	)
	intake.Transparency = 1
	intake.CanCollide = false
	intake.CanTouch = false
	intake.CanQuery = false

	local output = Instance.new("Attachment")
	output.Name = "Output"
	-- LookVector points out the front (+Z), where the planks spawn.
	output.CFrame = CFrame.lookAt(Vector3.new(0, 1.6, d / 2 + 1), Vector3.new(0, 1.6, d / 2 + 6))
	output.Parent = root

	if not preview then
		MachineArt.AddPanel(model, w, mill.displayName, "Set the cut", SawmillLogic.RangeText(mill))
		-- Above the roof, facing the infeed and the outfeed. Hidden until
		-- a piece won't fit; the text stays off with the board.
		local sign = part(
			model,
			"Blockage",
			Vector3.new(3.6, 1.15, 0.2),
			CFrame.new(0, roofBottom + 1.05, 0),
			Kit.hex("#7A2A22"),
			Enum.Material.Wood,
			false,
			false
		)
		Kit.decor(sign)
		sign.Transparency = 1
		sign.CastShadow = false
		local labels = Kit.signText(sign, SawmillLogic.BlockageLabel, Kit.hex("#F4E2C2"))
		for _, label in ipairs(labels) do
			local board = label.Parent
			if board and board:IsA("SurfaceGui") then
				board.Enabled = false
			end
		end
		CollectionService:AddTag(model, "Sawmill")
	end

	MachineArt.TierDetail(model, tier, w, d, roofBottom, mill.tierName, preview)
	model:SetAttribute("MillId", mill.id)
	model:SetAttribute("Tier", mill.tier)
	model:SetAttribute("TierName", mill.tierName)
	return model
end

local YELLOW = Kit.hex("#F5C518")
local BLACK = Kit.hex("#1A1A1A")
local CREAM = Kit.hex("#F3E6C8")

local function ghostPart(p: BasePart)
	p.Transparency = if p.Name == "Root" or p.Name == "Intake" then 1 else 0.45
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- The cut readout, "8 u".
function MachineArt.SetLength(model: Model, u: number)
	local label = model:FindFirstChild("LengthReadout", true)
	if label and label:IsA("TextLabel") then
		label.Text = string.format("%d u", u)
	end
end

-- Client-only neon line at the cut. The server build does not call this.
function MachineArt.PreviewLine(model: Model, cutU: number): BasePart?
	local plane = model:FindFirstChild("BladePlane", true)
	if not plane or not plane:IsA("Attachment") then
		return nil
	end
	local host = plane.Parent
	if not host or not host:IsA("BasePart") then
		return nil
	end
	local studs = ChopSawLogic.PreviewStuds(cutU)
	local cf = host.CFrame * plane.CFrame * CFrame.new(0, 0, -studs)
	local size = ChopSawLogic.PreviewSize()
	local existing = model:FindFirstChild("CutPreview", true)
	local line: BasePart
	if existing and existing:IsA("BasePart") then
		line = existing
	else
		line = Kit.part(model, "CutPreview", size, cf, YELLOW, Enum.Material.Neon)
	end
	line.Size = size
	line.CFrame = cf
	line.Material = Enum.Material.Neon
	line.Color = YELLOW
	Kit.decor(line)
	return line
end

-- `ghost` is the placement preview: nothing collides and there are no buttons.
function MachineArt.BuildChopSaw(ghost: boolean?): Model?
	local machine = ItemCatalog.GetMachine("ChopSaw")
	if not machine then
		return nil
	end
	local preview = ghost == true
	local model = Kit.model(machine.id)
	local fp = ChopSawLogic.Footprint()
	local baseAt = ChopSawLogic.BaseCenter()
	local bladeAt = ChopSawLogic.BladeCenter()
	local tableAt = ChopSawLogic.TableCenter()

	local root = Kit.part(
		model,
		"Root",
		Vector3.new(fp.X, ChopSawLogic.RootY, fp.Y),
		CFrame.new(0, ChopSawLogic.RootY / 2, 0),
		WOOD,
		Enum.Material.Wood
	)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	model.PrimaryPart = root

	local base = Kit.part(
		model,
		"Base",
		Vector3.new(ChopSawLogic.BaseX, ChopSawLogic.BaseY, ChopSawLogic.BaseZ),
		CFrame.new(baseAt),
		Kit.hex(machine.color),
		Enum.Material.Metal
	)
	if preview then
		ghostPart(base)
	end

	local infeed = Kit.part(
		model,
		"Infeed",
		Vector3.new(ChopSawLogic.TableWidth, ChopSawLogic.TableThick, ChopSawLogic.TableLength()),
		CFrame.new(tableAt),
		WOOD,
		Enum.Material.Wood
	)
	if preview then
		ghostPart(infeed)
	end

	local legH = tableAt.Y - ChopSawLogic.TableThick / 2
	local inset = ChopSawLogic.Leg
	local halfW = ChopSawLogic.TableWidth / 2 - inset
	local halfL = ChopSawLogic.TableLength() / 2 - inset
	for _, x in ipairs({ -halfW, halfW }) do
		for _, z in ipairs({ -halfL, halfL }) do
			local leg = Kit.part(
				model,
				"Leg",
				Vector3.new(ChopSawLogic.Leg, legH, ChopSawLogic.Leg),
				CFrame.new(tableAt.X + x, legH / 2, tableAt.Z + z),
				WOOD_DARK,
				Enum.Material.Wood
			)
			if preview then
				ghostPart(leg)
			end
		end
	end

	local intake = Kit.part(
		model,
		"Intake",
		Vector3.new(ChopSawLogic.TableWidth, ChopSawLogic.IntakeHeight, ChopSawLogic.TableLength()),
		CFrame.new(tableAt.X, tableAt.Y + ChopSawLogic.TableThick / 2 + ChopSawLogic.IntakeHeight / 2, tableAt.Z),
		WOOD,
		Enum.Material.SmoothPlastic
	)
	intake.Transparency = 1
	intake.CanCollide = false
	intake.CanQuery = false
	intake.CanTouch = false
	intake.CastShadow = false

	local guard = Kit.part(
		model,
		"BladeGuard",
		Vector3.new(ChopSawLogic.GuardX, ChopSawLogic.GuardY, ChopSawLogic.GuardZ),
		CFrame.new(bladeAt),
		YELLOW,
		Enum.Material.SmoothPlastic
	)
	guard.CanCollide = false
	guard.CanTouch = false
	if preview then
		ghostPart(guard)
	else
		guard.CanQuery = true
		guard:SetAttribute("Damage", true)
	end

	local stripeZ = -ChopSawLogic.GuardZ / 2 - ChopSawLogic.StripeThick / 2
	for _, y in ipairs({ -ChopSawLogic.GuardY / 4, ChopSawLogic.GuardY / 4 }) do
		local stripe = Kit.part(
			model,
			"Stripe",
			Vector3.new(
				ChopSawLogic.GuardX + ChopSawLogic.StripeThick,
				ChopSawLogic.StripeBand,
				ChopSawLogic.StripeThick
			),
			CFrame.new(bladeAt) * CFrame.new(0, y, stripeZ),
			BLACK,
			Enum.Material.SmoothPlastic
		)
		Kit.decor(stripe)
		if preview then
			stripe.Transparency = 0.45
		end
	end

	local blade = Kit.cylinder(
		model,
		"SawBlade",
		ChopSawLogic.BladeThick,
		ChopSawLogic.BladeDiameter,
		CFrame.new(bladeAt) * CFrame.Angles(0, math.pi / 2, 0),
		BLADE,
		Enum.Material.Metal
	)
	if preview then
		ghostPart(blade)
	else
		Kit.decor(blade)
		CollectionService:AddTag(blade, "SawBlade")
	end

	local plane = Instance.new("Attachment")
	plane.Name = "BladePlane"
	plane.Parent = guard

	local output = Instance.new("Attachment")
	output.Name = "Output"
	-- LookVector points out the back of the base (+Z), through the blade.
	output.CFrame = CFrame.new(0, 0, ChopSawLogic.BaseZ / 2) * CFrame.Angles(0, math.pi, 0)
	output.Parent = base

	local runIn = Instance.new("Attachment")
	runIn.Name = "Run"
	runIn:SetAttribute("LogicInput", ChopSawLogic.RunInput)
	runIn.Parent = base

	local runFlag = Instance.new("BoolValue")
	runFlag.Name = "Run"
	runFlag.Value = true
	runFlag.Parent = model

	if not preview then
		local panelCf = CFrame.new(baseAt.X + ChopSawLogic.BaseX / 2 + ChopSawLogic.PanelBoardX / 2, baseAt.Y, baseAt.Z)
		local panel = Kit.part(
			model,
			"Panel",
			Vector3.new(ChopSawLogic.PanelBoardX, ChopSawLogic.PanelBoardY, ChopSawLogic.PanelBoardZ),
			panelCf,
			PANEL,
			Enum.Material.Wood
		)
		panel.CanQuery = true
		panel.CanTouch = false
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PanelGui"
		gui.Face = Enum.NormalId.Right
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = ChopSawLogic.SurfacePixels
		gui.Parent = panel
		local readout = Instance.new("TextLabel")
		readout.Name = "LengthReadout"
		readout.Size = UDim2.fromOffset(ChopSawLogic.ReadoutPx, ChopSawLogic.HintPx)
		readout.Position = UDim2.fromOffset(ChopSawLogic.PanelGapPx, ChopSawLogic.PanelGapPx)
		readout.BackgroundTransparency = 1
		readout.Font = Enum.Font.GothamBold
		readout.TextSize = ChopSawLogic.PanelTextPx
		readout.TextColor3 = CREAM
		readout.Text = string.format("%d u", ChopSawLogic.DefaultCut)
		readout.Parent = gui
		local px = ChopSawLogic.PanelFacePx
		local function boardButton(name: string, text: string, x: number, dir: number)
			local b = Instance.new("TextButton")
			b.Name = name
			b.Size = UDim2.fromOffset(px, px)
			b.Position = UDim2.fromOffset(x, ChopSawLogic.PanelFacePx)
			b.BackgroundColor3 = Kit.hex("#C4A574")
			b.TextColor3 = PANEL
			b.Font = Enum.Font.GothamBold
			b.TextSize = ChopSawLogic.PanelTextPx
			b.Text = text
			b.AutoButtonColor = true
			b.Active = true
			b.Selectable = true
			b:SetAttribute("Axis", "x")
			b:SetAttribute("Dir", dir)
			local fit = Instance.new("UITextSizeConstraint")
			fit.MaxTextSize = ChopSawLogic.PanelTextPx
			fit.MinTextSize = InputKit.MinTagPx
			fit.Parent = b
			b.Parent = gui
		end
		local gap = ChopSawLogic.PanelGapPx
		boardButton("LengthMinus", "-", gap, -1)
		boardButton("LengthPlus", "+", gap + px + gap, 1)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CutPrompt"
		prompt.ActionText = "Set the length"
		prompt.ObjectText = machine.displayName
		prompt.MaxActivationDistance = ChopSawLogic.PromptRange
		prompt.HoldDuration = 0
		prompt.ClickablePrompt = true
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		InputKit.PromptDefaults(prompt, "Interact")
		prompt.Parent = panel

		local signX = baseAt.X + ChopSawLogic.BaseX / 2 + ChopSawLogic.PanelBoardX / 2
		local signCf = CFrame.new(signX, baseAt.Y + ChopSawLogic.SignLift, baseAt.Z) * CFrame.Angles(0, -math.pi / 2, 0)
		local sign = Kit.part(
			model,
			"PriceSign",
			Vector3.new(ChopSawLogic.SignW, ChopSawLogic.SignH, ChopSawLogic.RootY),
			signCf,
			PANEL,
			Enum.Material.Wood
		)
		Kit.decor(sign)
		Kit.signText(sign, Util.formatCash(machine.priceCash), CREAM)

		CollectionService:AddTag(model, "ChopSaw")
	end

	model:SetAttribute("MachineId", machine.id)
	model:SetAttribute("Shop", machine.shop)
	model:SetAttribute("Price", machine.priceCash)
	model:SetAttribute("CutU", ChopSawLogic.DefaultCut)
	model:SetAttribute("Run", true)
	return model
end

-- The Sky Bin you place on your plot (SkyBinLogic): BuildingArt's bin, with
-- its flume and cloud behind (+Z), on an invisible pivot slab the size of
-- its footprint. The bin part keeps its name "SkyBin" (AetherService hangs
-- the "Sell Sky Bin" prompt on it, WorldUI labels its SurfaceGuis) and the
-- model is tagged SkyBinLogic.Tag. `ghost` is the placement preview.
function MachineArt.BuildSkyBin(ghost: boolean?): Model?
	local machine = ItemCatalog.GetMachine(SkyBinLogic.Id)
	if not machine then
		return nil
	end
	local preview = ghost == true
	local model = BuildingArt.SkyBin()
	model.Name = machine.id
	local fp = SkyBinLogic.Footprint()
	local root = Kit.part(
		model,
		"Root",
		Vector3.new(fp.X, ChopSawLogic.RootY, fp.Y),
		CFrame.new(0, ChopSawLogic.RootY / 2, 0),
		WOOD,
		Enum.Material.Wood
	)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	model.PrimaryPart = root
	if preview then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				ghostPart(d)
			end
		end
	else
		CollectionService:AddTag(model, SkyBinLogic.Tag)
	end
	model:SetAttribute("MachineId", machine.id)
	model:SetAttribute("Shop", machine.shop)
	model:SetAttribute("Price", machine.priceCash)
	return model
end

-- The planer you place on your plot (PlanerLogic): a low shed over a belt
-- with a pair of rollers and a cutter head. Plank in at the back (-Z, the
-- Intake), board out at the front (+Z, the Output), a cut board on the +X
-- side like the sawmill's. It is tagged "Planer" with PlanerId; the tier adds
-- detail (more per tier, inside MachineArt.Budget) and a TierSign. `ghost` is
-- the placement preview.
local PLANER_BODY = {
	Kit.hex("#B08A55"),
	Kit.hex("#7C6A4F"),
	Kit.hex("#5A6B73"),
	Kit.hex("#3B4452"),
} :: { Color3 }
local PLANER_MATERIAL = {
	Enum.Material.Wood,
	Enum.Material.WoodPlanks,
	Enum.Material.Metal,
	Enum.Material.DiamondPlate,
} :: { Enum.Material }

function MachineArt.BuildPlaner(planerId: string, ghost: boolean?): Model?
	local machine, def = PlanerLogic.Get(planerId)
	if not machine or not def then
		return nil
	end
	local preview = ghost == true
	local tier = math.clamp(def.tier, 1, 4)
	local w, d = def.width, def.depth
	local frame = PLANER_BODY[tier]
	local model = Kit.model(machine.id)
	local u = GameConfig.WoodUnit
	local widest = math.max(def.maxX, def.maxY) * u
	local beltTop = 0.72
	local beltH = 0.32
	local beltW = widest + 0.55
	local beltLen = math.max(3, d - 1.2)
	local hoodBottom = beltTop + widest + 0.8

	local root =
		part(model, "Root", Vector3.new(w, 0.2, d), CFrame.new(0, 0.1, 0), WOOD, Enum.Material.Wood, true, false)
	root.Transparency = 1
	model.PrimaryPart = root

	local deck = part(
		model,
		"Deck",
		Vector3.new(w - 0.4, 0.4, d - 0.4),
		CFrame.new(0, 0.2, 0),
		WOOD,
		Enum.Material.WoodPlanks,
		preview,
		true
	)
	if not preview then
		touchless(deck)
	end
	local belt = part(
		model,
		"Conveyor",
		Vector3.new(beltW, beltH, beltLen),
		CFrame.new(0, beltTop - beltH / 2, 0) * CFrame.Angles(0, math.pi, 0),
		BELT,
		Enum.Material.Metal,
		preview,
		true
	)
	if not preview then
		inGroup(belt, BELT_GROUP)
		MachineArt.AimBelt(model)
	end
	for _, side in ipairs({ -1, 1 }) do
		local wall = part(
			model,
			"Wall",
			Vector3.new(0.6, hoodBottom + 0.6 - 0.4, d - 1.2),
			CFrame.new(side * (beltW / 2 + 0.5), 0.4 + (hoodBottom + 0.6 - 0.4) / 2, 0),
			frame,
			PLANER_MATERIAL[tier],
			preview,
			true
		)
		local rail = part(
			model,
			"GuardRail",
			Vector3.new(0.25, 0.9, beltLen - 0.4),
			CFrame.new(side * (beltW / 2 + 0.1), beltTop + 0.35, 0),
			WOOD_DARK,
			Enum.Material.Wood,
			preview,
			true
		)
		if not preview then
			touchless(wall)
			touchless(rail)
		end
	end
	-- The hood over the rollers: players stop at it, a plank on the belt passes under.
	local hood = part(
		model,
		"Roof",
		Vector3.new(beltW + 2.0, 0.4, d - 1.0),
		CFrame.new(0, hoodBottom + 0.8, 0),
		ROOF_COLOR[math.min(tier + 1, 5)],
		PLANER_MATERIAL[tier],
		preview,
		true
	)
	if not preview then
		inGroup(hood, MILL_GROUP)
	end
	-- Two feed rollers and the cutter head, axles across the belt (X).
	for i, z in ipairs({ -d * 0.22, 0, d * 0.22 }) do
		local roller = Kit.cylinder(
			model,
			if i == 2 then "CutterHead" else "Roller",
			beltW,
			if i == 2 then 1.1 else 0.8,
			CFrame.new(0, beltTop + (if i == 2 then widest + 0.45 else widest + 0.3), z),
			if i == 2 then BLADE else IRON,
			Enum.Material.Metal
		)
		if preview then
			roller.Transparency = 0.45
		end
		Kit.decor(roller)
	end
	local gate = part(
		model,
		"BladeGuard",
		Vector3.new(beltW + 1.0, hoodBottom + 0.2, 1.2),
		CFrame.new(0, (hoodBottom + 0.2) / 2 + 0.4, 0),
		WOOD,
		Enum.Material.SmoothPlastic,
		preview,
		true
	)
	gate.Transparency = 1
	gate.CastShadow = false
	if not preview then
		inGroup(gate, MILL_GROUP)
	end
	for _, endZ in ipairs({ -(d / 2 - 0.6), d / 2 - 0.6 }) do
		local feed = part(
			model,
			"FeedGuard",
			Vector3.new(beltW + 1.6, hoodBottom + 0.8, 0.4),
			CFrame.new(0, 0.4 + (hoodBottom + 0.8) / 2, endZ),
			WOOD,
			Enum.Material.Wood,
			preview,
			true
		)
		feed.Transparency = 1
		feed.CastShadow = false
		if not preview then
			inGroup(feed, MILL_GROUP)
		end
	end
	local intake = part(
		model,
		"Intake",
		Vector3.new(math.max(3, beltW), 4, 4),
		CFrame.new(0, 2.2, -d / 2 + 0.4),
		WOOD,
		Enum.Material.SmoothPlastic,
		true,
		false
	)
	intake.Transparency = 1
	intake.CanCollide = false
	intake.CanTouch = false
	intake.CanQuery = false
	local output = Instance.new("Attachment")
	output.Name = "Output"
	output.CFrame = CFrame.lookAt(Vector3.new(0, 1.6, d / 2 + 1), Vector3.new(0, 1.6, d / 2 + 6))
	output.Parent = root

	-- Tier detail: 2 posts, 3 a steam pipe and a plate, 4 a gantry and lamps.
	local top = hoodBottom + 1.0
	if tier >= 2 then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				lookPart(
					model,
					"Post",
					Vector3.new(0.5, hoodBottom + 0.6, 0.5),
					CFrame.new(sx * (beltW / 2 + 1.1), (hoodBottom + 0.6) / 2, sz * (d / 2 - 0.4)),
					WOOD_DARK,
					Enum.Material.Wood,
					preview
				)
			end
		end
	end
	if tier >= 3 then
		local pipe = Kit.cylinder(
			model,
			"SteamPipe",
			2.4,
			0.7,
			CFrame.new(0, top + 0.6, d / 5) * CFrame.Angles(0, 0, math.pi / 2),
			BRASS,
			Enum.Material.Metal
		)
		if preview then
			pipe.Transparency = 0.45
		end
		Kit.decor(pipe)
		lookPart(
			model,
			"MakerPlate",
			Vector3.new(1.4, 0.7, 0.12),
			CFrame.new(0, hoodBottom + 0.3, d / 2 - 0.45),
			BRASS,
			Enum.Material.Metal,
			preview
		)
	end
	if tier >= 4 then
		lookPart(
			model,
			"Gantry",
			Vector3.new(beltW + 2.8, 0.45, 0.45),
			CFrame.new(0, top + 2.6, 0),
			Kit.hex("#E0A030"),
			Enum.Material.DiamondPlate,
			preview
		)
		for _, sx in ipairs({ -1, 1 }) do
			lookPart(
				model,
				"GantryLeg",
				Vector3.new(0.4, 2.6, 0.4),
				CFrame.new(sx * (beltW / 2 + 1.3), top + 1.3, 0),
				Kit.hex("#E0A030"),
				Enum.Material.DiamondPlate,
				preview
			)
			local lamp = lookPart(
				model,
				"Lamp",
				Vector3.new(0.45, 0.45, 0.45),
				CFrame.new(sx * (beltW / 2 + 1.3), top + 2.3, 0.6),
				Kit.hex("#FFE2A0"),
				Enum.Material.Neon,
				preview
			)
			if not preview then
				local light = Instance.new("PointLight")
				light.Range = 12
				light.Brightness = 1.1
				light.Shadows = false
				light.Color = Kit.hex("#FFD59A")
				light.Parent = lamp
			end
		end
	end
	local sign = lookPart(
		model,
		"TierSign",
		Vector3.new(3.0, 0.8, 0.2),
		CFrame.new(0, hoodBottom + 1.4, d / 2 - 0.4),
		PANEL,
		Enum.Material.Wood,
		preview
	)
	if not preview then
		Kit.signText(sign, string.upper(machine.tierName or machine.displayName), Kit.hex("#F3E6C8"))
		MachineArt.AddPanel(model, w, machine.displayName, "Set the planing size", PlanerLogic.RangeText(def))
		CollectionService:AddTag(model, PlanerLogic.Tag)
	end
	model:SetAttribute("PlanerId", machine.id)
	model:SetAttribute("MachineId", machine.id)
	model:SetAttribute("Shop", machine.shop)
	model:SetAttribute("Price", machine.priceCash)
	model:SetAttribute("Tier", def.tier)
	model:SetAttribute("TierName", machine.tierName)
	return model
end

-- A piece of the conveyor kit (AutomationLogic): straight, turn (a quarter
-- turn to the right when you look along the belt) and funnel (a wide mouth
-- narrowing to a belt). Every belt part is named "Conveyor", anchored, in the
-- MillBelt group (wood rides, players walk through), and aimed along its own
-- front by BeltService / MachineArt.AimBelt; entry at the back (-Z), exit at
-- the front (+Z), or +X for a turn. Rails keep wood on. Looks and rails are
-- the only other parts. `ghost` is the placement preview.
local BELT_WOOD = Kit.hex("#6B5B45")

-- TLD-1 line deck (reference LINE-STANDARD.md): a 6.0 wide concrete plate,
-- a 5.0 channel between steel rails (top 1.32), a dark pan, rollers 0.44
-- across at 1.0 pitch (the first 0.5 from each port face), deck top 0.72,
-- brass collars on the rail ends. The Conveyor is the invisible collider
-- whose top face is the deck top. Colours from the GAD Lane W notes.
local TLD = {
	plate = Kit.hex("#B3ABA0"),
	rail = Kit.hex("#2B2B2E"),
	cap = Kit.hex("#3E4148"),
	roller = Kit.hex("#C9CED3"),
	pan = Kit.hex("#2A2420"),
	brass = Kit.hex("#C9A24A"),
	timber = Kit.hex("#7A5230"),
	cream = Kit.hex("#F3E7C9"),
	iron = Kit.hex("#2B2B2E"),
}
MachineArt.LineColors = TLD

local DECK_TOP = AutomationLogic.DeckTop
local PLATE_W = AutomationLogic.PlateWidth
local CHANNEL = AutomationLogic.Channel
local RAIL_X = CHANNEL / 2 + 0.2 -- 2.7, the rail centre
local RAIL_TOP = 1.32
local PLATE_T = 0.16

type DeckOptions = {
	rails: boolean?, -- false leaves the rails off (the Switch Belt's cross run has its own)
	alongX: boolean?, -- rollers and the run go along X instead of Z
	cross: boolean?, -- the collider follows the model's Side (Switch Belt)
	width: number?, -- plate width across the run (default 6.0)
	rollers: boolean?, -- false leaves the rollers off (a short flat lip)
	collars: { number }?, -- which ends get brass port collars (-1, 1); default both
	-- A pitched run's tan(pitch). Each part slides along the run so its own
	-- centre line meets the vertical seams with the flat lips (not only the
	-- deck top), and grows by height * shear so no corner leaves a notch.
	shear: number?,
}

-- One straight run of deck, `length` along the frame's +Z (or +X with
-- alongX), its ground centre at `frame`.
local function deck(model: Model, frame: CFrame, length: number, preview: boolean, opts: DeckOptions?)
	local o: DeckOptions = opts or ({} :: DeckOptions)
	local alongX = o.alongX == true
	local plateW = o.width or PLATE_W
	local function sized(across: number, height: number, along: number): Vector3
		return if alongX then Vector3.new(along, height, across) else Vector3.new(across, height, along)
	end
	local shear = if alongX then 0 else (o.shear or 0)
	local function at(across: number, y: number, along: number): CFrame
		local a = along + (y - DECK_TOP) * shear
		return frame * (if alongX then CFrame.new(a, y, across) else CFrame.new(across, y, a))
	end
	local function len(height: number): number
		return length + height * shear
	end
	local plate = part(
		model,
		"Plate",
		sized(plateW, PLATE_T, len(PLATE_T)),
		-- (Pitched, the plate rides 0.05 up so its low corner stays above ground.)
		at(0, PLATE_T / 2 + (if shear ~= 0 then 0.05 else 0), 0),
		TLD.plate,
		Enum.Material.Concrete,
		preview,
		true
	)
	if not preview then
		touchless(plate)
	end
	local pan =
		part(model, "Pan", sized(CHANNEL, 0.1, len(0.1)), at(0, 0.33, 0), TLD.pan, Enum.Material.Metal, preview, false)
	pan.CastShadow = false
	local n = if o.rollers == false then 0 else math.max(1, math.floor(length / AutomationLogic.RollerPitch + 1e-6))
	for i = 0, n - 1 do
		local along = -length / 2 + 0.5 + i * AutomationLogic.RollerPitch
		local cf = at(0, 0.5, along) * (if alongX then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity)
		local roller = Kit.cylinder(model, "Roller", 4.9, 0.44, cf, TLD.roller, Enum.Material.Metal)
		roller.CanCollide = false
		roller.CanQuery = false
		roller.CanTouch = false
		roller.CastShadow = false
		if preview then
			roller.Transparency = 0.45
		end
	end
	if o.rails ~= false then
		for _, sideX in ipairs({ -1, 1 }) do
			local r = part(
				model,
				"GuardRail",
				sized(0.4, RAIL_TOP - PLATE_T, len(RAIL_TOP - PLATE_T)),
				at(sideX * RAIL_X, (RAIL_TOP + PLATE_T) / 2, 0),
				TLD.rail,
				Enum.Material.Metal,
				preview,
				true
			)
			if not preview then
				touchless(r)
			end
			local cap = part(
				model,
				"RailCap",
				sized(0.44, 0.06, len(0.06)),
				at(sideX * RAIL_X, RAIL_TOP + 0.03, 0),
				TLD.cap,
				Enum.Material.Metal,
				preview,
				false
			)
			cap.CastShadow = false
			local collarEnds: { number } = o.collars or { -1, 1 }
			for _, endZ: number in ipairs(collarEnds) do
				local collar = part(
					model,
					"PortCollar",
					sized(0.48, RAIL_TOP - PLATE_T + 0.04, 0.06),
					at(sideX * RAIL_X, (RAIL_TOP + PLATE_T) / 2, endZ * (length / 2 - 0.03)),
					TLD.brass,
					Enum.Material.Metal,
					preview,
					false
				)
				collar.CastShadow = false
			end
		end
	end
	-- The collider: top face on the deck top, flush to both port faces.
	local band = part(
		model,
		"Conveyor",
		Vector3.new(CHANNEL, 0.32, len(0.32)),
		at(0, DECK_TOP - 0.16, 0) * CFrame.Angles(0, if alongX then -math.pi / 2 else math.pi, 0),
		BELT,
		Enum.Material.Metal,
		preview,
		true
	)
	band.Transparency = 1
	if o.cross then
		band:SetAttribute("Cross", true)
	end
	if not preview then
		inGroup(band, BELT_GROUP)
	end
	return band
end

-- Turns the Switch Belt's brass diverter to throw wood toward `side`
-- (+1 is +X). Flip mirrors it; there is no second texture.
function MachineArt.SetSwitchSide(model: Model, side: number)
	local gate = model:FindFirstChild("Gate")
	local root = model.PrimaryPart
	if not gate or not gate:IsA("BasePart") or not root then
		return
	end
	local s = if side == -1 then -1 else 1
	-- Hinge at the back rail; the paddle runs back toward the infeed on the
	-- side it throws away from, at 45 degrees.
	local hinge = CFrame.new(0, DECK_TOP + 0.5, 3.35)
	local yaw = s * math.rad(45)
	local local_ = hinge * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -1.4)
	gate.CFrame = root.CFrame * CFrame.new(0, -0.1, 0) * local_
	model:SetAttribute("GateSide", s)
end

-- The Lane W line pieces (TLD-1 footprints): Switch Belt 12 x 8, Tilted
-- Belt 6 x 8 rising 2.0, Belt Support 6 x 2, Wood Detector 8 x 4.
local function buildLinePiece(model: Model, def: ItemCatalog.BeltDef, preview: boolean)
	local origin = CFrame.new(0, 0, 0)
	if def.shape == "switch" then
		-- Entry run on -Z (z -4 to -1.5), then the cross run (x -6 to 6,
		-- z -1.5 to 3.5) that carries wood out of whichever side is set.
		deck(model, origin * CFrame.new(0, 0, -2.75), 2.5, preview)
		local crossFrame = origin * CFrame.new(0, 0, 1.0)
		local left =
			deck(model, crossFrame * CFrame.new(-3, 0, 0), 6, preview, { rails = false, alongX = true, cross = true })
		local right =
			deck(model, crossFrame * CFrame.new(3, 0, 0), 6, preview, { rails = false, alongX = true, cross = true })
		left.Name = "Conveyor"
		right.Name = "Conveyor"
		-- A strip of plate behind the cross run, under the back rail.
		part(
			model,
			"Plate",
			Vector3.new(12, PLATE_T, 0.5),
			CFrame.new(0, PLATE_T / 2, 3.75),
			TLD.plate,
			Enum.Material.Concrete,
			preview,
			false
		)
		-- Back rail full width; front rails from the channel out to each side.
		local back = part(
			model,
			"GuardRail",
			Vector3.new(12, RAIL_TOP - PLATE_T, 0.4),
			CFrame.new(0, (RAIL_TOP + PLATE_T) / 2, 3.7),
			TLD.rail,
			Enum.Material.Metal,
			preview,
			true
		)
		if not preview then
			touchless(back)
		end
		for _, sx in ipairs({ -1, 1 }) do
			local front = part(
				model,
				"GuardRail",
				Vector3.new(3.1, RAIL_TOP - PLATE_T, 0.4),
				CFrame.new(sx * 4.45, (RAIL_TOP + PLATE_T) / 2, -1.7),
				TLD.rail,
				Enum.Material.Metal,
				preview,
				true
			)
			if not preview then
				touchless(front)
			end
		end
		local gate = part(
			model,
			"Gate",
			Vector3.new(0.14, 1.0, 2.8),
			CFrame.new(),
			TLD.brass,
			Enum.Material.Metal,
			preview,
			false
		)
		gate.CastShadow = true
		MachineArt.SetSwitchSide(model, 1)
	elseif def.shape == "tilted" then
		-- A flat lip at each port face (deck top 0.72 at the low end, 0.72 +
		-- rise at the high end, vertical end faces flush with the footprint)
		-- and the pitched run between them. A pitched run alone would poke
		-- its end faces past the footprint into the next belt.
		local rise = def.rise or AutomationLogic.Lift
		local run = def.depth
		local lip = AutomationLogic.TiltLip
		local slopeRun = run - 2 * lip
		local theta = math.atan2(rise, slopeRun)
		local up = Vector3.new(0, math.cos(theta), -math.sin(theta))
		local forward = Vector3.new(0, math.sin(theta), math.cos(theta))
		local mid = (DECK_TOP + DECK_TOP + rise) / 2
		local pos = Vector3.new(0, mid, 0) - up * DECK_TOP
		local frame = CFrame.fromMatrix(pos, Vector3.new(1, 0, 0), up, forward)
		deck(model, frame, slopeRun / math.cos(theta), preview, { collars = {}, shear = math.tan(theta) })
		local low = origin * CFrame.new(0, 0, -run / 2 + lip / 2)
		local high = origin * CFrame.new(0, rise, run / 2 - lip / 2)
		deck(model, low, lip, preview, { rollers = false, collars = { -1 } })
		deck(model, high, lip, preview, { rollers = false, collars = { 1 } })
		-- An iron rail clamp over each seam where the pitched rails meet the
		-- lips' rails, so the joint reads as one rail with no lip or step.
		for _, seam in ipairs({ { z = -slopeRun / 2, y = 0 }, { z = slopeRun / 2, y = rise } }) do
			for _, sx in ipairs({ -1, 1 }) do
				local clamp = part(
					model,
					"RailClamp",
					Vector3.new(0.52, RAIL_TOP - PLATE_T + 0.22, 0.3),
					CFrame.new(sx * RAIL_X, seam.y + (RAIL_TOP + PLATE_T) / 2 + 0.03, seam.z),
					TLD.cap,
					Enum.Material.Metal,
					preview,
					false
				)
				clamp.CastShadow = false
			end
		end
		-- Trestle: timber posts under the plate, the high lip and the middle.
		for _, z in ipairs({ 0, run / 2 - lip / 2 }) do
			-- The pitched plate's underside at z (it runs through `pos`).
			-- (The post reaches the high edge of its top, so it never shows a gap.)
			-- (+ the pitched plate's 0.05 lift, measured upright.)
			local bottom = if z == 0 then pos.Y - math.tan(theta) * (pos.Z - 0.25) + 0.05 / math.cos(theta) else rise
			if bottom > 0.2 then
				for _, sx in ipairs({ -1, 1 }) do
					lookPart(
						model,
						"Leg",
						Vector3.new(0.5, bottom, 0.5),
						CFrame.new(sx * 2.6, bottom / 2, z),
						TLD.timber,
						Enum.Material.Wood,
						preview
					)
				end
			end
		end
	elseif def.shape == "support" then
		local lift = AutomationLogic.Lift
		for _, sx in ipairs({ -1, 1 }) do
			local post = part(
				model,
				"Post",
				Vector3.new(0.6, lift - 0.2, 0.6),
				CFrame.new(sx * 2.6, (lift - 0.2) / 2, 0),
				TLD.timber,
				Enum.Material.Wood,
				preview,
				true
			)
			if not preview then
				touchless(post)
			end
		end
		part(
			model,
			"Saddle",
			Vector3.new(PLATE_W, 0.2, 1.06),
			CFrame.new(0, lift - 0.1, 0),
			TLD.iron,
			Enum.Material.Metal,
			preview,
			false
		)
		local brace = part(
			model,
			"Brace",
			Vector3.new(0.18, 0.18, 1.0),
			CFrame.new(0, 0, 0),
			TLD.iron,
			Enum.Material.Metal,
			preview,
			false
		)
		local len = math.sqrt(5.2 * 5.2 + 1.4 * 1.4)
		brace.Size = Vector3.new(len, 0.18, 0.18)
		brace.CFrame = CFrame.new(0, 1.0, 0) * CFrame.Angles(0, 0, math.atan2(1.4, 5.2))
	elseif def.shape == "detector" then
		deck(model, origin, def.depth, preview)
		-- The arch: iron legs outside the plate, a beam with a brass rim and
		-- a SignCream face, a small brass filter pip, a lamp under the beam.
		for _, sx in ipairs({ -1, 1 }) do
			part(
				model,
				"ArchLeg",
				Vector3.new(0.5, 7.9, 0.6),
				CFrame.new(sx * 3.55, 3.95, 0),
				TLD.iron,
				Enum.Material.Metal,
				preview,
				true
			)
		end
		part(
			model,
			"ArchBeam",
			Vector3.new(7.6, 0.55, 0.7),
			CFrame.new(0, 8.15, 0),
			TLD.iron,
			Enum.Material.Metal,
			preview,
			true
		)
		part(
			model,
			"ArchRim",
			Vector3.new(3.3, 1.5, 0.08),
			CFrame.new(0, 8.15, -0.39),
			TLD.brass,
			Enum.Material.Metal,
			preview,
			false
		)
		part(
			model,
			"Face",
			Vector3.new(3.0, 1.2, 0.06),
			CFrame.new(0, 8.15, -0.45),
			TLD.cream,
			Enum.Material.SmoothPlastic,
			preview,
			false
		)
		part(
			model,
			"FilterPip",
			Vector3.new(0.3, 0.3, 0.06),
			CFrame.new(1.15, 8.15, -0.5),
			TLD.brass,
			Enum.Material.Metal,
			preview,
			false
		)
		part(
			model,
			"Lamp",
			Vector3.new(0.42, 0.3, 0.42),
			CFrame.new(0, 7.73, 0),
			TLD.iron,
			Enum.Material.SmoothPlastic,
			preview,
			false
		)
		-- Where the detector looks: over the deck, inside the arch.
		local eye = part(
			model,
			"Eye",
			Vector3.new(CHANNEL, 5, def.depth - 0.4),
			CFrame.new(0, DECK_TOP + 2.5, 0),
			TLD.cream,
			Enum.Material.SmoothPlastic,
			preview,
			false
		)
		eye.Transparency = 1
	end
end

function MachineArt.BuildBelt(beltId: string, ghost: boolean?): Model?
	local machine, def = AutomationLogic.Get(beltId)
	if not machine or not def then
		return nil
	end
	local preview = ghost == true
	local w, d = def.width, def.depth
	local model = Kit.model(machine.id)
	local beltTop = 0.72
	local beltH = 0.32
	local beltY = beltTop - beltH / 2
	local root =
		part(model, "Root", Vector3.new(w, 0.2, d), CFrame.new(0, 0.1, 0), BELT_WOOD, Enum.Material.Wood, true, false)
	root.Transparency = 1
	model.PrimaryPart = root

	local function band(name: string, size: Vector3, at: Vector3, turn: number)
		local cf = CFrame.new(at) * CFrame.Angles(0, turn, 0)
		local b = part(model, name, size, cf, BELT, Enum.Material.Metal, preview, true)
		if not preview then
			inGroup(b, BELT_GROUP)
		end
		return b
	end
	local function rail(size: Vector3, at: Vector3, turn: number)
		local r = part(
			model,
			"GuardRail",
			size,
			CFrame.new(at) * CFrame.Angles(0, turn, 0),
			BELT_WOOD,
			Enum.Material.Wood,
			preview,
			true
		)
		if not preview then
			touchless(r)
		end
		return r
	end
	local function leg(at: Vector3)
		lookPart(
			model,
			"Leg",
			Vector3.new(0.35, beltY - 0.15, 0.35),
			CFrame.new(at.X, (beltY - 0.15) / 2, at.Z),
			WOOD_DARK,
			Enum.Material.Wood,
			preview
		)
	end
	local FRONT = math.pi -- LookVector +Z (see MachineArt.Build)
	local RIGHT = -math.pi / 2 -- LookVector +X
	local line = def.shape == "switch" or def.shape == "tilted" or def.shape == "support" or def.shape == "detector"
	if line then
		buildLinePiece(model, def, preview)
	elseif def.shape == "straight" then
		local bw = w - 1.0
		band("Conveyor", Vector3.new(bw, beltH, d - 0.2), Vector3.new(0, beltY, 0), FRONT)
		for _, side in ipairs({ -1, 1 }) do
			rail(Vector3.new(0.25, 0.9, d - 0.2), Vector3.new(side * (bw / 2 + 0.12), beltTop + 0.3, 0), 0)
			leg(Vector3.new(side * (bw / 2), 0, d / 2 - 0.6))
			leg(Vector3.new(side * (bw / 2), 0, -d / 2 + 0.6))
		end
	elseif def.shape == "turn" then
		-- Entry stub (+Z), the corner square (+X) and the exit stub (+X), 4 x 4.
		local bw = 3
		band("Conveyor", Vector3.new(bw, beltH, 0.6), Vector3.new(0, beltY, -w / 2 + 0.3), FRONT)
		band("Conveyor", Vector3.new(bw, beltH, bw), Vector3.new(0, beltY, 0), RIGHT)
		band("Conveyor", Vector3.new(bw, beltH, 0.6), Vector3.new(w / 2 - 0.3, beltY, 0), RIGHT)
		-- Rails: the two outer sides of the bend.
		rail(Vector3.new(0.25, 0.9, bw + 0.2), Vector3.new(-bw / 2 - 0.12, beltTop + 0.3, 0), 0)
		rail(Vector3.new(bw + 0.2, 0.9, 0.25), Vector3.new(0, beltTop + 0.3, bw / 2 + 0.12), 0)
		leg(Vector3.new(-bw / 2, 0, -bw / 2))
		leg(Vector3.new(bw / 2, 0, bw / 2))
	else
		-- Funnel: an 8-wide mouth for the first half, narrowing to 3 over the
		-- second, with two angled walls that squeeze the wood onto the narrow belt.
		local mouthLen = d / 2
		band("Conveyor", Vector3.new(w - 0.6, beltH, mouthLen), Vector3.new(0, beltY, -d / 4), FRONT)
		band("Conveyor", Vector3.new(3, beltH, d / 2), Vector3.new(0, beltY, d / 4), FRONT)
		local run = d / 2
		local across = w / 2 - 0.3 - 1.6
		local length = math.sqrt(run * run + across * across)
		local angle = math.atan2(across, run)
		for _, side in ipairs({ -1, 1 }) do
			rail(
				Vector3.new(0.25, 1.1, length),
				Vector3.new(side * ((w / 2 + 1.5) / 2 - 0.1), beltTop + 0.4, d / 4),
				-side * angle
			)
			rail(Vector3.new(0.25, 0.9, mouthLen), Vector3.new(side * (w / 2 - 0.2), beltTop + 0.3, -d / 4), 0)
		end
		leg(Vector3.new(-w / 2 + 0.6, 0, -d / 2 + 0.6))
		leg(Vector3.new(w / 2 - 0.6, 0, -d / 2 + 0.6))
	end
	if not preview then
		MachineArt.AimBelt(model)
		CollectionService:AddTag(model, AutomationLogic.Tag)
	end
	model:SetAttribute("BeltShape", def.shape)
	model:SetAttribute("MachineId", machine.id)
	model:SetAttribute("Shop", machine.shop)
	model:SetAttribute("Price", machine.priceCash)
	return model
end

-- The model for any plot machine by id, or nil: a sawmill, a planer, a belt
-- piece, the chop saw or the Sky Bin. PlotService builds with it and the
-- placement ghost shows the same shape.
function MachineArt.BuildAny(id: string, ghost: boolean?): Model?
	if ItemCatalog.GetSawmill(id) then
		return MachineArt.Build(id, ghost)
	elseif PlanerLogic.IsPlaner(id) then
		return MachineArt.BuildPlaner(id, ghost)
	elseif AutomationLogic.IsBelt(id) then
		return MachineArt.BuildBelt(id, ghost)
	elseif SkyBinLogic.IsBin(id) then
		return MachineArt.BuildSkyBin(ghost)
	elseif ItemCatalog.GetMachine(id) then
		return MachineArt.BuildChopSaw(ghost)
	end
	return nil
end

return MachineArt
