--!strict
-- BuilderTools: edit an unfilled kit ghost before any wood goes in.
-- One row along the bottom: Rotate, Move, Shorter, Longer, Copy, Delete,
-- Undo, Done. A tap adds a piece, up to 20. Keys do the same on a keyboard,
-- and they stay quiet while a new blueprint is being placed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BlueprintModels = require(ReplicatedStorage.Shared.BlueprintModels)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local BuilderBar = require(ReplicatedStorage.Shared.BuilderBar)
local EditLogic = require(ReplicatedStorage.Shared.EditLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local HUD = require(script.Parent.HUD)

local BuilderTools = {}

local player = Players.LocalPlayer

local REFUSE = Color3.fromRGB(BuilderBar.Refuse[1], BuilderBar.Refuse[2], BuilderBar.Refuse[3])
local WOOD = Color3.fromRGB(101, 67, 33)
local BARK = Color3.fromRGB(88, 58, 34)
local CREAM = Color3.fromRGB(245, 235, 215)
local MUTED = Color3.fromRGB(160, 145, 120)
local INK = Color3.fromRGB(60, 40, 20)

type Pick = { uid: string, model: Model }

local selected: { Pick } = {}
local boxes: { SelectionBox } = {}
local copyMode = false
local copyGhosts: { Model } = {}
local copyDx = 0
local copyDz = 0
local copyOk = false

local cluster: Frame? = nil
local readoutLabel: TextLabel? = nil
local buttons: { [string]: TextButton } = {}

local function tier(): number
	return (player:GetAttribute("PlotTier") :: number?) or 1
end

local function woodColor(model: Model): Color3
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Role") == "Wood" and d.Transparency < 1 then
			return d.Color
		end
	end
	return WOOD
end

local function itemOf(model: Model): PlotLogic.Placed?
	local uid = model:GetAttribute("Uid")
	local id = model:GetAttribute("BlueprintId")
	local x = model:GetAttribute("X")
	local z = model:GetAttribute("Z")
	local rot = model:GetAttribute("Rot")
	if
		type(uid) ~= "string"
		or type(id) ~= "string"
		or type(x) ~= "number"
		or type(z) ~= "number"
		or type(rot) ~= "number"
	then
		return nil
	end
	local y = model:GetAttribute("Y")
	local fillUnits = model:GetAttribute("FillUnits")
	local len = model:GetAttribute("Len")
	local lenX = model:GetAttribute("LenX")
	local lenZ = model:GetAttribute("LenZ")
	local paid = model:GetAttribute("Paid")
	return {
		uid = uid,
		blueprintId = id,
		x = x,
		z = z,
		rot = rot,
		y = if type(y) == "number" then y else nil,
		fill = if type(fillUnits) == "number" then { units = fillUnits } else nil,
		len = if type(len) == "number" then len else nil,
		lenX = if type(lenX) == "number" then lenX else nil,
		lenZ = if type(lenZ) == "number" then lenZ else nil,
		paid = if type(paid) == "number" then paid else nil,
	}
end

local function clearBoxes()
	for _, box in ipairs(boxes) do
		box:Destroy()
	end
	table.clear(boxes)
end

local function paint(red: boolean)
	for i, pick in ipairs(selected) do
		local box = boxes[i]
		if box then
			local color = if red then REFUSE else woodColor(pick.model)
			box.Color3 = color
			box.SurfaceColor3 = color
		end
	end
end

local function rebind()
	clearBoxes()
	for _, pick in ipairs(selected) do
		if pick.model.Parent then
			local box = Instance.new("SelectionBox")
			box.Name = "KitSelect"
			box.Adornee = pick.model
			box.LineThickness = 0.05
			box.SurfaceTransparency = 0.75
			local color = woodColor(pick.model)
			box.Color3 = color
			box.SurfaceColor3 = color
			box.Parent = pick.model
			table.insert(boxes, box)
		end
	end
end

local function gate(): BuilderBar.Gate
	local filled = false
	local shorter = false
	local longer = false
	for _, pick in ipairs(selected) do
		local item = itemOf(pick.model)
		if not item or EditLogic.Locked(item) then
			filled = true
		end
	end
	if #selected == 1 then
		local item = itemOf(selected[1].model)
		local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
		if item and bp then
			local shortLen, shortX = EditLogic.Step(bp, item, -1)
			local longLen, longX = EditLogic.Step(bp, item, 1)
			shorter = shortLen ~= nil or shortX ~= nil
			longer = longLen ~= nil or longX ~= nil
		end
	end
	return { count = #selected, filled = filled, shorter = shorter, longer = longer }
end

local function feeOf(picks: { Pick }): number
	local total = 0
	for _, pick in ipairs(picks) do
		local item = itemOf(pick.model)
		local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
		if item and bp then
			total += EditLogic.Fee(bp, item)
		end
	end
	return total
end

local function refresh()
	local bar = cluster
	if bar then
		bar.Visible = #selected > 0
	end
	local info = gate()
	for name, button in pairs(buttons) do
		local on = BuilderBar.Enabled(name, info)
		button.Active = on
		button.AutoButtonColor = on
		button.BackgroundColor3 = if on then BARK else MUTED
		button.TextColor3 = if on then CREAM else INK
	end
	local label = readoutLabel
	if not label then
		return
	end
	if copyMode or #selected > 1 then
		label.Text = EditLogic.GroupReadout(#selected, feeOf(selected))
	elseif #selected == 1 then
		local item = itemOf(selected[1].model)
		local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
		label.Text = if item and bp then EditLogic.Readout(bp, item) else ""
	else
		label.Text = ""
	end
end

local function layout()
	local bar = cluster
	local camera = workspace.CurrentCamera
	if not bar or not camera then
		return
	end
	local size = camera.ViewportSize
	local place = BuilderBar.Layout(size.X, size.Y)
	bar.Position = UDim2.fromOffset(place.x, place.y)
	bar.Size = UDim2.fromOffset(place.w, place.h)
	local label = readoutLabel
	if label then
		label.Size = UDim2.fromOffset(place.w, place.readout)
	end
	for i, name in ipairs(BuilderBar.Names) do
		local button = buttons[name]
		if button then
			button.Size = UDim2.fromOffset(place.button, place.button)
			button.Position = UDim2.fromOffset((i - 1) * (place.button + place.gap), place.readout + place.gap)
		end
	end
end

local function stopCopy()
	copyMode = false
	for _, ghost in ipairs(copyGhosts) do
		ghost:Destroy()
	end
	table.clear(copyGhosts)
	paint(false)
end

local function tintGhost(ghost: Model, red: boolean)
	for _, d in ipairs(ghost:GetDescendants()) do
		if
			d:IsA("BasePart")
			and d.Name ~= "Root"
			and d:GetAttribute("Span") ~= true
			and d:GetAttribute("TileSource") ~= true
		then
			d.Color = if red then REFUSE else WOOD
		end
	end
end

local function previewCopy()
	local plot = BlueprintPlacer.PlotCFrame()
	if not plot then
		return
	end
	local working = BlueprintPlacer.MyPlaced()
	copyOk = true
	local fee = 0
	for i, pick in ipairs(selected) do
		local item = itemOf(pick.model)
		local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
		local ghost = copyGhosts[i]
		if item and bp and ghost then
			local x, z = item.x + copyDx, item.z + copyDz
			BlueprintModels.Place(ghost, plot, x, z, item.rot, item.y)
			local shaped = EditLogic.Shape(bp, item)
			local ok = PlotLogic.Check(shaped, x, z, item.rot, tier(), working, nil, item.y or 0)
			if not ok then
				copyOk = false
			else
				fee += EditLogic.Fee(bp, item)
				table.insert(working, {
					uid = "preview" .. tostring(i),
					blueprintId = item.blueprintId,
					x = x,
					z = z,
					rot = item.rot,
					y = item.y,
					len = item.len,
					lenX = item.lenX,
					lenZ = item.lenZ,
					fill = { units = 0 },
				})
			end
		else
			copyOk = false
		end
	end
	local cash = player:GetAttribute("Cash")
	if type(cash) == "number" and cash < fee then
		copyOk = false
	end
	for _, ghost in ipairs(copyGhosts) do
		tintGhost(ghost, not copyOk)
	end
	paint(not copyOk)
end

local function startCopy()
	stopCopy()
	if #selected < 1 then
		return
	end
	copyMode = true
	local plot = BlueprintPlacer.PlotCFrame() or CFrame.identity
	for _, pick in ipairs(selected) do
		local item = itemOf(pick.model)
		local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
		if item and bp then
			local ghost = BlueprintModels.Build(bp, true)
			BlueprintModels.ApplySize(ghost, bp, item.len, item.lenX, item.lenZ)
			BlueprintModels.SetFaded(ghost, true)
			ghost.Name = "CopyGhost"
			ghost.Parent = workspace
			BlueprintModels.Place(ghost, plot, item.x, item.z, item.rot, item.y)
			table.insert(copyGhosts, ghost)
		end
	end
	local item = itemOf(selected[1].model)
	local bp = if item then PlotLogic.Blueprint(item.blueprintId) else nil
	copyDx = 2
	if item and bp then
		local len = item.len or bp.footprint.X
		copyDx = PlotLogic.Snap(math.max(2, len))
	end
	copyDz = 0
	previewCopy()
	refresh()
end

local function confirmCopy()
	if not copyMode or not copyOk then
		if copyMode then
			HUD.Toast(EditLogic.Message("overlap") or "Something's in the way.")
		end
		return
	end
	local uids = {}
	for _, pick in ipairs(selected) do
		table.insert(uids, pick.uid)
	end
	Net.Remote("BlueprintEdit"):FireServer({ op = "copy", uids = uids, dx = copyDx, dz = copyDz })
	stopCopy()
	refresh()
end

local function primary(): (Model?, PlotLogic.Placed?)
	local pick = selected[#selected]
	if not pick then
		return nil, nil
	end
	return pick.model, itemOf(pick.model)
end

local function rotate()
	local _, item = primary()
	if not item then
		return
	end
	local bp = PlotLogic.Blueprint(item.blueprintId)
	if not bp then
		return
	end
	local rot = (item.rot + 1) % 4
	local shaped = EditLogic.Shape(bp, item)
	local ok = PlotLogic.Check(shaped, item.x, item.z, rot, tier(), BlueprintPlacer.MyPlaced(), item.uid, item.y or 0)
	if not ok then
		paint(true)
		HUD.Toast(EditLogic.Message("overlap") or "Something's in the way.")
		return
	end
	paint(false)
	Net.Remote("BlueprintEdit"):FireServer({ op = "rotate", uid = item.uid, rot = rot })
end

local function resize(dir: number)
	local _, item = primary()
	if not item then
		return
	end
	local bp = PlotLogic.Blueprint(item.blueprintId)
	if not bp then
		return
	end
	local len, lenX, lenZ = EditLogic.Step(bp, item, dir)
	if len == nil and lenX == nil then
		paint(true)
		HUD.Toast(EditLogic.Message("len") or "That length isn't on the 2-stud grid.")
		return
	end
	local nextItem = table.clone(item)
	if len ~= nil then
		nextItem.len = len
	end
	if lenX ~= nil then
		nextItem.lenX = lenX
		nextItem.lenZ = lenZ
	end
	local shaped = EditLogic.Shape(bp, nextItem)
	local ok =
		PlotLogic.Check(shaped, item.x, item.z, item.rot, tier(), BlueprintPlacer.MyPlaced(), item.uid, item.y or 0)
	if not ok then
		paint(true)
		HUD.Toast(EditLogic.Message("overlap") or "Something's in the way.")
		return
	end
	paint(false)
	Net.Remote("BlueprintEdit"):FireServer({
		op = "resize",
		uid = item.uid,
		len = len,
		lenX = lenX,
		lenZ = lenZ,
	})
end

local function move()
	local _, item = primary()
	if not item then
		return
	end
	local bp = PlotLogic.Blueprint(item.blueprintId)
	if not bp then
		return
	end
	stopCopy()
	BlueprintPlacer.Begin(bp, { moveUid = item.uid })
end

local function deleteOne()
	local _, item = primary()
	if not item or EditLogic.Locked(item) then
		paint(true)
		HUD.Toast(EditLogic.Message("filled") or "This piece already has wood in it.")
		return
	end
	Net.Remote("BlueprintEdit"):FireServer({ op = "delete", uid = item.uid })
	table.remove(selected)
	rebind()
	refresh()
end

local function undo()
	Net.Remote("BlueprintEdit"):FireServer({ op = "undo" })
end

local function done()
	stopCopy()
	table.clear(selected)
	rebind()
	refresh()
end

local function toggle(model: Model)
	if model:GetAttribute("Kit") ~= true or model:GetAttribute("FillUnits") ~= 0 then
		HUD.Toast(EditLogic.Message("filled") or "This piece already has wood in it.")
		return
	end
	if model:GetAttribute("OwnerId") ~= player.UserId then
		HUD.Toast(EditLogic.Message("owner") or "That piece isn't on your plot.")
		return
	end
	local uid = model:GetAttribute("Uid")
	if type(uid) ~= "string" then
		return
	end
	for i, pick in ipairs(selected) do
		if pick.uid == uid then
			table.remove(selected, i)
			rebind()
			refresh()
			return
		end
	end
	if #selected >= EditLogic.MaxGroup then
		HUD.Toast(EditLogic.Message("group") or "You can copy 20 pieces at a time.")
		return
	end
	table.insert(selected, { uid = uid, model = model })
	rebind()
	refresh()
end

local function modelFrom(target: Instance?): Model?
	local inst: Instance? = target
	while inst and inst ~= workspace do
		if CollectionService:HasTag(inst, "PlacedItem") and inst:IsA("Model") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local function onGround(origin: Vector3, direction: Vector3): Vector3?
	if direction.Y >= -1e-4 then
		return nil
	end
	local t = -origin.Y / direction.Y
	if t <= 0 or t > 2000 then
		return nil
	end
	return origin + direction * t
end

local function aimCopy(screenX: number, screenY: number)
	if not copyMode then
		return
	end
	local camera = workspace.CurrentCamera
	local plot = BlueprintPlacer.PlotCFrame()
	local item = if selected[1] then itemOf(selected[1].model) else nil
	if not camera or not plot or not item then
		return
	end
	local ray = camera:ViewportPointToRay(screenX, screenY)
	local hit = onGround(ray.Origin, ray.Direction)
	if not hit then
		return
	end
	local localPoint = plot:PointToObjectSpace(hit)
	copyDx = PlotLogic.Snap(localPoint.X) - item.x
	copyDz = PlotLogic.Snap(localPoint.Z) - item.z
	previewCopy()
end

local function press(which: string)
	if BlueprintPlacer.Active() then
		if which == "Done" then
			done()
		end
		return
	end
	local name = which
	if name == "Rotate" then
		rotate()
	elseif name == "Move" then
		move()
	elseif name == "Shorter" then
		resize(-1)
	elseif name == "Longer" then
		resize(1)
	elseif name == "Copy" then
		if copyMode then
			confirmCopy()
		else
			startCopy()
		end
	elseif name == "Delete" then
		deleteOne()
	elseif name == "Undo" then
		undo()
	elseif name == "Done" then
		done()
	end
end

local function keysOpen(): boolean
	return #selected > 0 and cluster ~= nil and cluster.Visible and not BlueprintPlacer.Active()
end

function BuilderTools.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuilderTools"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bar = Instance.new("Frame")
	bar.Name = "BuildBar"
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = gui
	cluster = bar

	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(40, 28, 16)
	label.TextColor3 = CREAM
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.Text = ""
	label.Parent = bar
	readoutLabel = label

	for _, name in ipairs(BuilderBar.Names) do
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = name
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextWrapped = true
		button.AutoButtonColor = true
		button.BackgroundColor3 = BARK
		button.TextColor3 = CREAM
		button.Parent = bar
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingRight = UDim.new(0, 2)
		pad.Parent = button
		button.Activated:Connect(function()
			if button.Active then
				press(name)
			end
		end)
		buttons[name] = button
	end

	gui.Parent = player:WaitForChild("PlayerGui")
	layout()

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local nextCamera = workspace.CurrentCamera
		if nextCamera then
			nextCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
		end
		layout()
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not keysOpen() then
			return
		end
		local key = input.KeyCode
		if copyMode and key == Enum.KeyCode.C then
			confirmCopy()
			return
		end
		if key == Enum.KeyCode.R then
			press("Rotate")
		elseif key == Enum.KeyCode.M then
			press("Move")
		elseif key == Enum.KeyCode.LeftBracket then
			press("Shorter")
		elseif key == Enum.KeyCode.RightBracket then
			press("Longer")
		elseif key == Enum.KeyCode.C then
			press("Copy")
		elseif key == Enum.KeyCode.Delete then
			press("Delete")
		elseif key == Enum.KeyCode.Z then
			if
				UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			then
				press("Undo")
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not copyMode or BlueprintPlacer.Active() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local mouse = UserInputService:GetMouseLocation()
			aimCopy(mouse.X, mouse.Y)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or BlueprintPlacer.Active() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and copyMode then
			confirmCopy()
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local mouse = player:GetMouse()
		local model = modelFrom(mouse.Target)
		if model then
			toggle(model)
		end
	end)

	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		if processedByUI or BlueprintPlacer.Active() then
			return
		end
		if copyMode then
			aimCopy(position.X, position.Y)
			return
		end
		local cameraNow = workspace.CurrentCamera
		if not cameraNow then
			return
		end
		local ray = cameraNow:ViewportPointToRay(position.X, position.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local char = player.Character
		if char then
			params.FilterDescendantsInstances = { char }
		end
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		local model = if hit then modelFrom(hit.Instance) else nil
		if model then
			toggle(model)
		end
	end)

	CollectionService:GetInstanceRemovedSignal("PlacedItem"):Connect(function(inst: Instance)
		for i = #selected, 1, -1 do
			if selected[i].model == inst then
				table.remove(selected, i)
			end
		end
		rebind()
		refresh()
	end)

	RunService.RenderStepped:Connect(function()
		if copyMode then
			previewCopy()
		end
	end)
end

return BuilderTools
