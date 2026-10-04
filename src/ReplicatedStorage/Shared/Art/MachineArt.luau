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

local GameConfig = require(script.Parent.Parent.GameConfig)
local InputKit = require(script.Parent.Parent.InputKit)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Kit)
local SawmillLogic = require(script.Parent.Parent.SawmillLogic)

local MachineArt = {}

-- Keep these equal to WoodService.MillGroup / MillBeltGroup.
local MILL_GROUP = "Mill"
local BELT_GROUP = "MillBelt"

local WOOD = Kit.hex("#6B4423")
local WOOD_DARK = Kit.hex("#3C2A1E")
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

-- The cut readout, "1.0 × 0.6 u".
function MachineArt.SetCut(model: Model, x: number, y: number)
	local label = model:FindFirstChild("CutReadout", true)
	if label and label:IsA("TextLabel") then
		label.Text = string.format("%.1f × %.1f u", x, y)
	end
end

-- Points the belt's conveyor velocity out the front (+Z of the belt). A
-- ghost has nothing to push. Safe to call every poll; placement can turn
-- the mill, and the velocity is in world space.
function MachineArt.AimBelt(model: Model)
	local belt = model:FindFirstChild("Conveyor", true)
	if not belt or not belt:IsA("BasePart") or not belt.CanCollide then
		return
	end
	local look = belt.CFrame.LookVector
	if look.Magnitude < 1e-4 then
		return
	end
	belt.AssemblyLinearVelocity = look.Unit * GameConfig.ConveyorSpeed
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
			Enum.Material.Wood,
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
		frame,
		Enum.Material.WoodPlanks,
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
		-- Front is the big face (size X by Y). LookVector points out the +X side
		-- so the buttons face someone standing beside the mill. At
		-- SurfacePixelsPerStud the face holds four 48 px buttons and the readout.
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
		local readout = Instance.new("TextLabel")
		readout.Name = "CutReadout"
		readout.Size = UDim2.fromOffset(208, 40)
		readout.Position = UDim2.fromOffset(8, 6)
		readout.BackgroundTransparency = 1
		readout.Font = Enum.Font.GothamBold
		readout.TextSize = SawmillLogic.PanelTextPx
		readout.TextScaled = true
		readout.TextColor3 = Kit.hex("#F3E6C8")
		readout.Text = "1.0 × 0.6 u"
		readout.Parent = gui
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = SawmillLogic.PanelTextPx
		fit.MinTextSize = 14
		fit.Parent = readout
		-- 48 px buttons, 6 px apart, inside a 5.6-stud face at 40 px/stud.
		button(gui, "XMinus", "X-", 8, "x", -1)
		button(gui, "XPlus", "X+", 62, "x", 1)
		button(gui, "YMinus", "Y-", 116, "y", -1)
		button(gui, "YPlus", "Y+", 170, "y", 1)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CutPrompt"
		prompt.ActionText = "Set the cut"
		prompt.ObjectText = mill.displayName
		prompt.MaxActivationDistance = SawmillLogic.PromptRange
		prompt.HoldDuration = 0
		prompt.ClickablePrompt = true
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		InputKit.PromptDefaults(prompt, "Interact")
		prompt.Parent = panel
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

	model:SetAttribute("MillId", mill.id)
	return model
end

return MachineArt
