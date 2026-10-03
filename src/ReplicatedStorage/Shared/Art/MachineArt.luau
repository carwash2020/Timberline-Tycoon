--!strict
-- MachineArt: the sawmills you place on a plot (V2_PLAN.md §7). Each one is
-- a low-poly shed with an Intake box (the log goes in the back), an Output
-- attachment (planks leave the front) and a Panel of X/Y buttons. The
-- SawBlade is tagged so the town's blade spin picks it up. A ghost is the
-- same model, see-through, for the plot preview.

local CollectionService = game:GetService("CollectionService")

local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Kit)

local MachineArt = {}

local WOOD = Kit.hex("#6B4423")
local WOOD_DARK = Kit.hex("#3C2A1E")
local BLADE = Kit.hex("#D5D8DC")
local PANEL = Kit.hex("#2C241C")

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

local function button(parent: Instance, name: string, text: string, x: number, axis: string, dir: number)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromScale(0.22, 0.42)
	b.Position = UDim2.fromScale(x, 0.5)
	b.BackgroundColor3 = Kit.hex("#C4A574")
	b.TextColor3 = Kit.hex("#2C241C")
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b:SetAttribute("Axis", axis)
	b:SetAttribute("Dir", dir)
	b.Parent = parent
end

-- The cut readout, "1.0 × 0.6 u".
function MachineArt.SetCut(model: Model, x: number, y: number)
	local label = model:FindFirstChild("CutReadout", true)
	if label and label:IsA("TextLabel") then
		label.Text = string.format("%.1f × %.1f u", x, y)
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

	local root =
		part(model, "Root", Vector3.new(w, 0.2, d), CFrame.new(0, 0.1, 0), WOOD, Enum.Material.Wood, true, false)
	root.Transparency = 1
	model.PrimaryPart = root

	part(
		model,
		"Deck",
		Vector3.new(w - 1, 0.45, d - 1.5),
		CFrame.new(0, 0.5, 0.2),
		WOOD,
		Enum.Material.WoodPlanks,
		preview,
		true
	)
	local leg = 0.45
	for _, corner in ipairs({
		Vector3.new(-w / 2 + 0.6, 0, -d / 2 + 0.8),
		Vector3.new(w / 2 - 0.6, 0, -d / 2 + 0.8),
		Vector3.new(-w / 2 + 0.6, 0, d / 2 - 0.8),
		Vector3.new(w / 2 - 0.6, 0, d / 2 - 0.8),
	}) do
		part(
			model,
			"Leg",
			Vector3.new(leg, 0.7, leg),
			CFrame.new(corner + Vector3.new(0, 0.35, 0)),
			WOOD_DARK,
			Enum.Material.Wood,
			preview,
			true
		)
	end

	local postH = 3.4 + mill.maxWidth
	for _, side in ipairs({ -1, 1 }) do
		part(
			model,
			"Post",
			Vector3.new(0.45, postH, 0.45),
			CFrame.new(side * (w / 2 - 0.7), postH / 2, -0.4),
			frame,
			Enum.Material.Wood,
			preview,
			true
		)
	end
	part(
		model,
		"AxleBeam",
		Vector3.new(w - 1.2, 0.4, 0.4),
		CFrame.new(0, postH - 0.3, -0.4),
		frame,
		Enum.Material.Wood,
		preview,
		false
	)

	local bladeD = math.clamp(mill.maxWidth * 2.4, 3.2, 6.5)
	local blade =
		Kit.cylinder(model, "SawBlade", 0.28, bladeD, CFrame.new(0, postH * 0.62, 0.3), BLADE, Enum.Material.Metal)
	if preview then
		blade.Transparency = 0.45
		blade.CanCollide = false
		blade.CanQuery = false
		blade.CanTouch = false
	else
		Kit.decor(blade)
		CollectionService:AddTag(blade, "SawBlade")
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
		-- so the buttons face someone standing beside the mill.
		local panel = part(
			model,
			"Panel",
			Vector3.new(3.2, 2.2, 0.25),
			CFrame.lookAt(Vector3.new(w / 2 + 0.3, 3.1, 0.2), Vector3.new(w / 2 + 8, 3.1, 0.2)),
			PANEL,
			Enum.Material.Wood,
			false,
			false
		)
		panel.CanQuery = true
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PanelGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 36
		gui.Parent = panel
		local readout = Instance.new("TextLabel")
		readout.Name = "CutReadout"
		readout.Size = UDim2.fromScale(0.92, 0.32)
		readout.Position = UDim2.fromScale(0.04, 0.06)
		readout.BackgroundTransparency = 1
		readout.Font = Enum.Font.GothamBold
		readout.TextScaled = true
		readout.TextColor3 = Kit.hex("#F3E6C8")
		readout.Text = "1.0 × 0.6 u"
		readout.Parent = gui
		button(gui, "XMinus", "X-", 0.04, "x", -1)
		button(gui, "XPlus", "X+", 0.28, "x", 1)
		button(gui, "YMinus", "Y-", 0.52, "y", -1)
		button(gui, "YPlus", "Y+", 0.76, "y", 1)
		CollectionService:AddTag(model, "Sawmill")
	end

	model:SetAttribute("MillId", mill.id)
	return model
end

return MachineArt
