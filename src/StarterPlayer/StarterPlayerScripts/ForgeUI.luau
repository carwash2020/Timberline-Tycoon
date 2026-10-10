--!strict
-- ForgeUI: the Sky Forge window (Lane A2). Opened by the server's ForgeOpen
-- (the anvil's "Open the Sky Forge" prompt, or Old Bram), with the view the
-- server built (SkyForgeService.View). Four tabs:
--   * Starfall: the Starfall Axe's recipe and progress, and Forge.
--   * Relics: the four relics, what each takes and pays, and Forge.
--   * Order: this week's order, its progress and pay, and Deliver.
--   * Temper: each axe you own, its temper, and Keen / Heavy / Prosperous.
--     Picking one shows the exact cost and result first; Temper confirms.
-- Every button only sends ForgeAction; the server checks everything and
-- answers with a toast and a fresh view.
-- Layout: 44 px targets. On a phone the panel stays right of the
-- thumbstick zone, left of the jump button and under the cash row
-- (ForgeUI.Rects). While it is open you can't walk; B, Escape or Close shut
-- it. A gamepad lands on the first button (GamepadNav).
-- Relic sockets: the Relics attribute (server) lights the anvil sockets
-- Socket_<RelicId> for this player; the rest stay dim.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamepadNav = require(script.Parent.GamepadNav)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)
local Util = require(ReplicatedStorage.Shared.Util)

local ForgeUI = {}

local C = UITheme.Colors
local K = UITheme.Skin
local F = UITheme.Fonts

export type Rect = { x: number, y: number, w: number, h: number }

ForgeUI.Tabs = { "Starfall", "Relics", "Order", "Temper" }
ForgeUI.Target = 44 -- every button's face is at least this tall

-- Where a phone's thumbs rest (Roblox's touch controls) and the HUD's cash
-- row; the panel keeps clear of all three.
function ForgeUI.Zones(w: number, h: number): { stick: Rect, jump: Rect, cash: Rect }
	return {
		stick = { x = 0, y = h * 0.5, w = w * 0.4, h = h * 0.5 },
		jump = { x = w - 120, y = h - 140, w = 120, h = 140 },
		cash = { x = w - 170, y = 0, w = 170, h = 56 },
	}
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end
ForgeUI.Overlaps = overlaps

-- The panel's box for a `w` x `h` screen (after UIScale). A phone gets a
-- tall column between the thumbstick and the jump button, under the cash
-- row; a bigger screen a centred panel.
function ForgeUI.Rects(w: number, h: number, phone: boolean?): Rect
	local isPhone = if phone ~= nil then phone else math.min(w, h) < UITheme.CompactEdge
	if isPhone then
		local z = ForgeUI.Zones(w, h)
		local left = math.floor(z.stick.x + z.stick.w + 8)
		local right = math.floor(z.jump.x - 8)
		local top = math.floor(z.cash.y + z.cash.h + 4)
		return { x = left, y = top, w = right - left, h = math.floor(h - 8 - top) }
	end
	local pw = math.min(600, w - 24)
	local ph = math.min(520, h - 120)
	return { x = math.floor((w - pw) / 2), y = math.floor((h - ph) / 2 + 20), w = pw, h = ph }
end

-- Lines a `text` takes at `px` in `width` (Gotham's average glyph is
-- about 0.52 em). Rows size from this, so a long cost wraps, never clips.
function ForgeUI.Lines(text: string, px: number, width: number): number
	local perLine = math.max(8, math.floor(width / (px * 0.52)))
	local lines = 0
	for para in string.gmatch(text .. "\n", "(.-)\n") do
		local n, len = 1, 0
		for word in string.gmatch(para, "%S+") do
			local add = utf8.len(word) or #word
			if len > 0 and len + 1 + add > perLine then
				n += 1
				len = add
			else
				len += (if len > 0 then 1 else 0) + add
			end
		end
		lines += n
	end
	return math.max(1, lines)
end

-- The view the server sends (SkyForgeService.View); every field is
-- optional here so an older server can't break the window.
export type TemperOption = {
	prefix: string,
	tier: number?,
	grade: string,
	effect: string,
	cost: string,
	refusal: string?,
}
export type AxeRow = { uid: string, id: string, name: string, label: string, options: { TemperOption } }
export type View = {
	cash: number?,
	shards: number?,
	starfall: { name: string, cost: string, progress: string, owned: number, refusal: string? }?,
	axes: { AxeRow }?,
	relics: { { id: string, name: string, cost: string, pays: number, owned: boolean, color: string, refusal: string? } }?,
	order: { text: string, pays: number, shards: number, claimed: boolean, endsIn: number }?,
}

-- One row's words and button, before it is drawn (pure: the specs and the
-- preview read these).
export type RowSpec = {
	name: string,
	lines: { { text: string, tone: "body" | "warn" | "good" } },
	button: string?,
	style: string?,
	action: { kind: string, a: string?, b: string? }?,
	swatch: string?, -- a hex colour (relics)
	choices: { { text: string, style: string, pick: { uid: string, prefix: string } } }?,
}

local function endsText(sec: number): string
	local days = math.floor(sec / 86400)
	local hours = math.floor((sec % 86400) / 3600)
	if days > 0 then
		return string.format("New order in %dd %dh (Monday 00:00 UTC)", days, hours)
	end
	return string.format("New order in %dh (Monday 00:00 UTC)", hours)
end

function ForgeUI.RowsFor(view: View, tab: string): { RowSpec }
	local rows: { RowSpec } = {}
	if tab == "Starfall" then
		local s = view.starfall
		if s then
			local lines: { { text: string, tone: "body" | "warn" | "good" } } = {
				{ text = s.cost, tone = "body" },
				{ text = s.progress, tone = "body" },
			}
			if s.owned > 0 then
				table.insert(lines, { text = string.format("You own %d.", s.owned), tone = "good" })
			end
			if s.refusal then
				table.insert(lines, { text = s.refusal, tone = "warn" })
			end
			table.insert(rows, {
				name = s.name,
				lines = lines,
				button = "Forge",
				style = if s.refusal then "cant" else "confirm",
				action = { kind = "starfall" },
			})
		end
	elseif tab == "Relics" then
		for _, r in ipairs(view.relics or {}) do
			local lines: { { text: string, tone: "body" | "warn" | "good" } } = {
				{ text = r.cost, tone = "body" },
				{ text = "Pays " .. Util.formatCash(r.pays) .. " once and lights its socket.", tone = "body" },
			}
			if r.owned then
				lines[2] = { text = "Forged. Its socket glows and it stands by your plot sign.", tone = "good" }
			elseif r.refusal then
				table.insert(lines, { text = r.refusal, tone = "warn" })
			end
			table.insert(rows, {
				name = r.name,
				lines = lines,
				button = if r.owned then "Done" else "Forge",
				style = if r.owned then "forged" elseif r.refusal then "cant" else "confirm",
				action = if r.owned then nil else { kind = "relic", a = r.id },
				swatch = r.color,
			})
		end
	elseif tab == "Order" then
		local o = view.order
		if o then
			local lines: { { text: string, tone: "body" | "warn" | "good" } } = {
				{ text = "Lay planks by the anvil: " .. o.text, tone = "body" },
				{
					text = string.format("Pays %s + %d Sky Shards, once a week.", Util.formatCash(o.pays), o.shards),
					tone = "body",
				},
				{ text = endsText(o.endsIn), tone = "body" },
			}
			if o.claimed then
				lines[1] = { text = "Filled. " .. o.text, tone = "good" }
			end
			table.insert(rows, {
				name = "Old Bram's weekly order",
				lines = lines,
				button = if o.claimed then "Done" else "Deliver",
				style = if o.claimed then "forged" else "confirm",
				action = if o.claimed then nil else { kind = "order" },
			})
		end
	elseif tab == "Temper" then
		for _, axe: AxeRow in ipairs(view.axes or {}) do
			local choices = {}
			for _, opt: TemperOption in ipairs(axe.options) do
				table.insert(choices, {
					text = if opt.tier then opt.prefix .. " " .. opt.grade else opt.prefix .. " III",
					style = if opt.tier == nil then "forged" elseif opt.refusal then "cant" else "primary",
					pick = { uid = axe.uid, prefix = opt.prefix },
				})
			end
			table.insert(rows, {
				name = if axe.label ~= "" then axe.name .. " · " .. axe.label else axe.name,
				lines = {
					{
						text = if axe.label ~= ""
							then "One temper per axe. A new family replaces it."
							else "Untempered. Pick one; you can change it later.",
						tone = "body",
					},
				},
				choices = choices,
			})
		end
		if #rows == 0 then
			table.insert(rows, {
				name = "No axe to temper",
				lines = { { text = "The Lux Axe can't be tempered. Buy or forge another axe.", tone = "body" } },
			})
		end
	end
	return rows
end

-- The confirm card for tempering axe `uid` with `prefix`: the exact cost
-- and the result, before anything is spent.
function ForgeUI.ConfirmFor(view: View, uid: string, prefix: string): RowSpec?
	for _, axe: AxeRow in ipairs(view.axes or {}) do
		if axe.uid == uid then
			for _, opt: TemperOption in ipairs(axe.options) do
				if opt.prefix == prefix then
					if opt.tier == nil then
						return {
							name = axe.name .. " is already " .. prefix .. " III",
							lines = { { text = "That is the top grade.", tone = "body" } },
						}
					end
					local lines: { { text: string, tone: "body" | "warn" | "good" } } = {
						{ text = "Result: " .. opt.effect .. ".", tone = "good" },
						{ text = "Costs " .. opt.cost .. ".", tone = "body" },
					}
					if axe.label ~= "" and not string.find(axe.label, prefix, 1, true) then
						table.insert(lines, { text = "Replaces " .. axe.label .. ".", tone = "warn" })
					end
					if opt.refusal then
						table.insert(lines, { text = opt.refusal, tone = "warn" })
					end
					return {
						name = string.format("%s: %s %s", axe.name, prefix, opt.grade),
						lines = lines,
						button = "Temper",
						style = if opt.refusal then "cant" else "confirm",
						action = { kind = "temper", a = uid, b = prefix },
					}
				end
			end
		end
	end
	return nil
end

-- Drawing ------------------------------------------------------------------

local NAME_PX, LINE_PX, LINE_H = 16, 13, 16

local gui: ScreenGui? = nil
local panel: Frame? = nil
local rowsFrame: ScrollingFrame? = nil
local tabButtons: { [string]: UITheme.Button } = {}
local purse: TextLabel? = nil
local current: View = {}
local tab = "Starfall"
local confirm: { uid: string, prefix: string }? = nil
local isOpen = false
local rect: Rect = { x = 0, y = 0, w = 600, h = 520 }

-- Temper choices side by side while each is at least ChoiceMin wide
-- ("Prosperous II" at 14 px); otherwise one per line (a phone's narrow panel).
ForgeUI.ChoiceMin = 104
function ForgeUI.ChoicesPerRow(width: number, count: number): number
	local gap = 8
	if count <= 1 or (width - 20 - gap * (count - 1)) / count >= ForgeUI.ChoiceMin then
		return math.max(count, 1)
	end
	return 1
end

local function toneColor(tone: string): Color3
	if tone == "warn" then
		return C.Danger
	elseif tone == "good" then
		return C.Green
	end
	return K.Bark
end

local function fire(kind: string, a: string?, b: string?)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("ForgeAction")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(kind, a, b)
	end
end

local redraw: () -> ()

local function drawRow(parent: Instance, spec: RowSpec, order: number, width: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Row" .. order
	row.LayoutOrder = order
	row.BackgroundColor3 = K.PaperDark
	row.BorderSizePixel = 0
	UITheme.corner(row, 8)
	local textLeft = if spec.swatch then 40 else 10
	local textW = width - textLeft - 10
	local y = 8
	if spec.swatch then
		local gem = Instance.new("Frame")
		gem.Name = "Swatch"
		gem.BackgroundColor3 = Color3.fromHex(spec.swatch)
		gem.Size = UDim2.fromOffset(22, 22)
		gem.Position = UDim2.fromOffset(10, 8)
		gem.BorderSizePixel = 0
		gem.Parent = row
		UITheme.corner(gem, 11)
		UITheme.stroke(gem, K.Ink, 2)
	end
	local name = UITheme.label(row, spec.name, F.Title, NAME_PX, K.Ink)
	name.Name = "Name"
	name.TextScaled = false
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(textLeft, y)
	name.Size = UDim2.fromOffset(textW, 20)
	y += 22
	for i, line in ipairs(spec.lines) do
		local n = ForgeUI.Lines(line.text, LINE_PX, textW)
		local label = UITheme.label(row, line.text, F.Body, LINE_PX, toneColor(line.tone))
		label.Name = "Line" .. i
		label.TextScaled = false
		label.TextWrapped = true
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Position = UDim2.fromOffset(textLeft, y)
		label.Size = UDim2.fromOffset(textW, n * LINE_H)
		y += n * LINE_H + 2
	end
	y += 4
	local target = ForgeUI.Target
	if spec.choices then
		local gap = 8
		local perRow = ForgeUI.ChoicesPerRow(width, #spec.choices)
		local bw = math.floor((width - 20 - gap * (perRow - 1)) / perRow)
		for i, choice in ipairs(spec.choices) do
			local col, line = (i - 1) % perRow, (i - 1) // perRow
			local b = UITheme.Button({
				text = choice.text,
				size = Vector2.new(bw, target),
				style = choice.style,
				textSize = 14,
				name = "Choice" .. i,
			})
			b.root.Position = UDim2.fromOffset(10 + col * (bw + gap), y + line * (target + UITheme.ButtonDrop + gap))
			b.root.Parent = row
			b.face.Activated:Connect(function()
				confirm = { uid = choice.pick.uid, prefix = choice.pick.prefix }
				redraw()
			end)
		end
		local lines = math.ceil(#spec.choices / perRow)
		y += lines * (target + UITheme.ButtonDrop) + (lines - 1) * gap + 8
	elseif spec.button then
		local bw = 112
		local b = UITheme.Button({
			text = spec.button,
			size = Vector2.new(bw, target),
			style = spec.style or "confirm",
			textSize = 15,
			name = "Action",
		})
		b.root.Position = UDim2.fromOffset(width - 10 - bw, y)
		b.root.Parent = row
		local action = spec.action
		b.face.Activated:Connect(function()
			if action then
				fire(action.kind, action.a, action.b)
				if action.kind == "temper" then
					confirm = nil
				end
			end
		end)
		if confirm and spec.action and spec.action.kind == "temper" then
			local back = UITheme.Button({
				text = "Back",
				size = Vector2.new(bw, target),
				style = "bark",
				textSize = 15,
				name = "Back",
			})
			back.root.Position = UDim2.fromOffset(width - 10 - bw * 2 - 8, y)
			back.root.Parent = row
			back.face.Activated:Connect(function()
				confirm = nil
				redraw()
			end)
		end
		y += target + UITheme.ButtonDrop + 8
	end
	row.Size = UDim2.fromOffset(width, y)
	row.Parent = parent
	return row
end

function ForgeUI.Draw()
	local list = rowsFrame
	if not list then
		return
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for name, b in pairs(tabButtons) do
		b:SetStyle(if name == tab then "primary" else "bark")
	end
	if purse then
		purse.Text = string.format("%s · %d Sky Shards", Util.formatCash(current.cash or 0), current.shards or 0)
	end
	local width = rect.w - 16 - 8
	local specs: { RowSpec }
	local c = confirm
	if tab == "Temper" and c then
		local card = ForgeUI.ConfirmFor(current, c.uid, c.prefix)
		specs = if card then { card } else ForgeUI.RowsFor(current, tab)
	else
		specs = ForgeUI.RowsFor(current, tab)
	end
	for i, spec in ipairs(specs) do
		drawRow(list, spec, i, width)
	end
end
redraw = ForgeUI.Draw

-- Builds the screen for a `viewport` (the preview builds it too).
function ForgeUI.Ensure(viewport: Vector2, phone: boolean?): ScreenGui
	if gui then
		return gui :: ScreenGui
	end
	local g = UITheme.Screen("ForgeUI", UITheme.Layers.Shop, "device")
	g.Enabled = false
	rect = ForgeUI.Rects(viewport.X, viewport.Y, phone)
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.BackgroundColor3 = K.Bark
	edge.BorderSizePixel = 0
	edge.Position = UDim2.fromOffset(rect.x, rect.y + K.PlaqueDrop)
	edge.Size = UDim2.fromOffset(rect.w, rect.h)
	edge.Parent = g
	UITheme.corner(edge, K.PlaqueCorner)
	local p = Instance.new("Frame")
	p.Name = "Forge"
	p.BackgroundColor3 = K.Paper
	p.BorderSizePixel = 0
	p.Position = UDim2.fromOffset(rect.x, rect.y)
	p.Size = UDim2.fromOffset(rect.w, rect.h)
	p.Parent = g
	UITheme.corner(p, K.PlaqueCorner)
	UITheme.stroke(p, K.Bark, K.PlaqueStroke)
	local title = UITheme.label(p, "Sky Forge", F.Title, 20, K.Ink)
	title.Name = "Title"
	title.TextScaled = false
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.fromOffset(rect.w - 80, 24)
	local wallet = UITheme.label(p, "", F.Body, 13, K.Bark)
	wallet.Name = "Purse"
	wallet.TextScaled = false
	wallet.Position = UDim2.fromOffset(10, 30)
	wallet.Size = UDim2.fromOffset(rect.w - 80, 16)
	purse = wallet
	local close =
		UITheme.Button({ text = "X", size = Vector2.new(44, 44), style = "primary", textSize = 18, name = "Close" })
	close.root.Position = UDim2.fromOffset(rect.w - 52, 6)
	close.root.Parent = p
	close.face.Activated:Connect(function()
		ForgeUI.Close()
	end)
	local gap = 6
	local tw = math.floor((rect.w - 16 - gap * (#ForgeUI.Tabs - 1)) / #ForgeUI.Tabs)
	for i, name in ipairs(ForgeUI.Tabs) do
		local b = UITheme.Button({
			text = name,
			size = Vector2.new(tw, ForgeUI.Target),
			style = if name == tab then "primary" else "bark",
			textSize = 14,
			name = "Tab" .. name,
		})
		b.root.Position = UDim2.fromOffset(8 + (i - 1) * (tw + gap), 56)
		b.root.Parent = p
		b.face.Activated:Connect(function()
			tab = name
			confirm = nil
			ForgeUI.Draw()
		end)
		tabButtons[name] = b
	end
	local top = 56 + ForgeUI.Target + UITheme.ButtonDrop + 8
	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(8, top)
	list.Size = UDim2.fromOffset(rect.w - 16, rect.h - top - 8)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = p
	UITheme.list(list, 8)
	rowsFrame = list
	panel = p
	gui = g
	return g
end

-- For the preview and specs: show `view` on `whichTab`, confirm optional.
function ForgeUI.Show(view: View, whichTab: string?, pick: { uid: string, prefix: string }?)
	current = view
	tab = whichTab or tab
	confirm = pick
	ForgeUI.Draw()
end

local function holdStill(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function onClose(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		ForgeUI.Close()
	end
	return Enum.ContextActionResult.Sink
end

function ForgeUI.Open(view: View)
	if gui == nil then
		local camera = workspace.CurrentCamera
		local vp = if camera then camera.ViewportSize / UITheme.Scale() else Vector2.new(1280, 720)
		local made = ForgeUI.Ensure(vp)
		made.Parent = UITheme.PlayerGui()
	end
	local g = gui :: ScreenGui
	current = view
	ForgeUI.Draw()
	if isOpen then
		return
	end
	isOpen = true
	(g :: ScreenGui).Enabled = true
	HUD.SetModal({ left = rect.x, top = rect.y, right = rect.x + rect.w, bottom = rect.y + rect.h })
	ContextActionService:BindAction("CloseForge", onClose, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	ContextActionService:BindActionAtPriority(
		"ForgeHoldStill",
		holdStill,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
	local first = tabButtons[tab]
	GamepadNav.Focus(if first then first.face else nil, panel)
end

function ForgeUI.Close()
	if not isOpen then
		return
	end
	isOpen = false
	confirm = nil
	if gui then
		(gui :: ScreenGui).Enabled = false
	end
	HUD.SetModal(nil)
	ContextActionService:UnbindAction("CloseForge")
	ContextActionService:UnbindAction("ForgeHoldStill")
	GamepadNav.Restore(panel)
end

function ForgeUI.IsOpen(): boolean
	return isOpen
end

-- Relic sockets on the anvils: lit for the relics this player forged.
function ForgeUI.LightSockets(owned: { [string]: boolean })
	local map = workspace:FindFirstChild("TimberlineMap")
	if not map then
		return
	end
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("Attachment") and string.sub(d.Name, 1, 7) == "Socket_" then
			local gem = d.Parent
			if gem and gem:IsA("BasePart") then
				local lit = owned[string.sub(d.Name, 8)] == true
				gem.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
				gem.Transparency = if lit then 0 else 0.45
			end
		end
	end
end

local function ownedRelics(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local raw = (Players.LocalPlayer :: Player):GetAttribute("Relics")
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			out[id] = true
		end
	end
	return out
end

function ForgeUI.Start()
	local player = Players.LocalPlayer :: Player
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", 60)
		local remote = folder and folder:WaitForChild("ForgeOpen", 60)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(function(view: unknown)
				if type(view) == "table" then
					ForgeUI.Open(view :: any)
				end
			end)
		end
	end)
	player:GetAttributeChangedSignal("Relics"):Connect(function()
		ForgeUI.LightSockets(ownedRelics())
	end)
	task.spawn(function()
		local map = workspace:WaitForChild("TimberlineMap", 120)
		if map then
			ForgeUI.LightSockets(ownedRelics())
			map.DescendantAdded:Connect(function(d: Instance)
				if d:IsA("Attachment") and string.sub(d.Name, 1, 7) == "Socket_" then
					ForgeUI.LightSockets(ownedRelics())
				end
			end)
		end
	end)
	-- Walking away closes it, like the shops.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if isOpen then
				local char = player.Character
				local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
				if not root then
					ForgeUI.Close()
				end
			end
		end
	end)
end

return ForgeUI
