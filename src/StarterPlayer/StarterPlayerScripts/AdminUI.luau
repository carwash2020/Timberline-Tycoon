--!strict
-- AdminUI: the owner hub. Only the owner sees it: the server sets the
-- IsOwner attribute on the owner's player, and this module builds nothing
-- without it. That is a convenience, not the lock: every press fires the
-- AdminRun remote with a small request, and AdminService refuses it unless
-- the sender is the owner (and AdminLogic.FromRequest whitelists the
-- request). A modified client gets nothing and is not even answered.
--
-- Open it with the OWNER side button, or click both thumbsticks (L3 + R3).
-- Close it with the X, B or Esc.
--
--   PLAYERS  pick a player once (the bar at the top of every tab), then go
--            to them, bring them, heal, freeze, stats, reset tutorial, kick, ban
--   GIVE     cash (give / take / set), unlock every building, free items
--            (type, search, picked item, recents)
--   WORLD    clock speed, set hour, reset time, announce, shut down server
--   SELF     super run, god mode, go to spawn, and the last actions
--
-- The search box in the title finds any tool by name. Every tool has a one
-- line hint under it. Kick, ban, take cash, set cash and shut down need a
-- second press. The strip at the bottom says what just happened or why the
-- server refused. On a pad: D-pad / stick move in the order AdminHubLogic.NavGrid
-- lays out, A presses, LB / RB change tab, and the list scrolls to keep the
-- selected row in view.
-- All rules (tabs, confirmations, filters, navigation) live in
-- Shared/AdminHubLogic, which is tested.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Hub = require(ReplicatedStorage.Shared.AdminHubLogic)
local AdminLogic = require(ReplicatedStorage.Shared.AdminLogic)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local Util = require(ReplicatedStorage.Shared.Util)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local HUD = require(script.Parent.HUD)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local L = Hub.Layout
local C = UITheme.Colors
local player = Players.LocalPlayer

local AdminUI = {}

local CLOSE_ACTION = "AdminClose"
local TAB_PREV = "AdminTabPrev"
local TAB_NEXT = "AdminTabNext"

-- What is picked (shared by every tab).
local state = {
	tabId = "players",
	roleIndex = 1,
	expiryIndex = 2,
	powers = {} :: { [string]: boolean },
	who = nil :: string?,
	amountIndex = 2,
	custom = "",
	banIndex = 2,
	speedIndex = 2,
	hourIndex = 2,
	category = "All",
	query = "",
	item = nil :: Hub.Item?,
	recents = {} :: { Hub.Item },
	announce = "",
	toolQuery = "",
	audit = {} :: { string },
}

local panel: Frame? = nil
local body: ScrollingFrame? = nil
local sideButton: UITheme.Button? = nil
local statusLabel: TextLabel? = nil
local pickedLabel: TextLabel? = nil
local auditLabel: TextLabel? = nil
local amountLabel: TextLabel? = nil
local tabButtons: { UITheme.Button } = {}
local objById: { [string]: GuiObject } = {}
local idOf: { [GuiObject]: string } = {}
local rows: { { string } } = {}
local headerRows: { { string } } = { { "search", "close" }, { "tab1", "tab2", "tab3", "tab4" } }
local listHolder: Frame? = nil
local listRowStart = 0
local pending: Hub.Pending? = nil
local statusOk: boolean? = nil
local statusText = ""
local allItemsCache: { Hub.Item }? = nil
local render: (string?) -> ()
local syncHub: () -> ()
local titleLabel: TextLabel? = nil

-- What the server says this hub may show (AdminAccess). The owner sees
-- everything; a delegate only the tools of their grant. A client-side word:
-- every request is checked again on the server against its own table.
type Access = {
	role: string, -- "owner" | "delegate" | "none"
	label: string,
	tester: boolean,
	allowed: { [string]: boolean }?, -- nil: everything (the owner)
	grantRole: string,
	delegates: { { [string]: any } },
	secondsLeft: number?,
}
local access: Access = {
	role = "none",
	label = "OWNER",
	tester = false,
	allowed = nil,
	grantRole = "",
	delegates = {},
	secondsLeft = nil,
}

local function isOwner(): boolean
	return player:GetAttribute("IsOwner") == true
end

-- Whether to show the OWNER / DELEGATE button and build the hub at all.
local function hasHub(): boolean
	return access.role == "delegate" or (access.role ~= "revoked" and isOwner())
end

local function allowedNow(id: string): boolean
	return Hub.Allows(access.allowed, id)
end

local function anyAllowed(ids: { string }): boolean
	for _, id in ipairs(ids) do
		if allowedNow(id) then
			return true
		end
	end
	return false
end

local function visibleTabs(): { Hub.Tab }
	return Hub.VisibleTabs(access.allowed)
end

local function currentTab(): Hub.Tab
	local tabs = visibleTabs()
	for _, tab in ipairs(tabs) do
		if tab.id == state.tabId then
			return tab
		end
	end
	return tabs[1] or Hub.Tabs[1]
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function names(): { string }
	local out: { string } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(out, p.Name)
	end
	return out
end

local function allItems(): { Hub.Item }
	if allItemsCache then
		return allItemsCache
	end
	local out: { Hub.Item } = {}
	local function add(kind: string, list: { any })
		for _, def in ipairs(list) do
			table.insert(out, { id = def.id, name = def.displayName, kind = kind })
		end
	end
	add("Axe", ItemCatalog.AxeLadder())
	add("Gear", ItemCatalog.GearList())
	add("Sawmill", ItemCatalog.SawmillList())
	add("Machine", ItemCatalog.MachineList())
	add("Blueprint", PlotData.Blueprints) -- any building: a rolled plan for the hammer
	allItemsCache = out
	return out
end

local function currentWho(): string?
	state.who = Hub.Pick(names(), state.who, player.Name)
	return state.who
end

local function currentAmount(): number?
	if state.custom ~= "" then
		return Hub.ParseAmount(state.custom)
	end
	return Hub.Amounts[state.amountIndex]
end

local function chosenPowers(): { string }
	local out: { string } = {}
	for _, power in ipairs(AdminLogic.DelegablePowers) do
		if state.powers[power] then
			table.insert(out, power)
		end
	end
	return out
end

local function chosenExpiry(): string
	local choices = Hub.ExpiriesFor(AdminLogic.RoleList[state.roleIndex])
	return choices[math.clamp(state.expiryIndex, 1, #choices)].id
end

local function context(): Hub.Context
	local item = state.item
	return {
		who = currentWho(),
		amount = currentAmount(),
		kind = if item then item.kind else nil,
		itemId = if item then item.id else nil,
		hours = Hub.BanChoices[state.banIndex].hours,
		speed = WorldTime.Speeds[state.speedIndex],
		hour = AdminLogic.TimePresetOrder[state.hourIndex],
		text = state.announce,
		role = AdminLogic.RoleList[state.roleIndex],
		powers = chosenPowers(),
		expiry = chosenExpiry(),
	}
end

---------------------------------------------------------------------------
-- Status strip and sending
---------------------------------------------------------------------------

local function paintStatus()
	local label = statusLabel
	if label then
		label.Text = if statusText ~= "" then statusText else currentTab().hint
		label.TextColor3 = if statusOk == true then C.Money elseif statusOk == false then C.Danger else C.Ink
	end
	local picked = pickedLabel
	if picked then
		picked.Text = "Player: " .. (currentWho() or "nobody")
	end
end

local function setStatus(ok: boolean?, text: string)
	statusOk = ok
	statusText = Hub.StatusText(text)
	paintStatus()
end

local function send(request: { [string]: any })
	Net.Remote("AdminRun"):FireServer(request)
end

local function toolKey(id: string): string
	local req = Hub.Request(id, context())
	if not req then
		return id
	end
	return string.format(
		"%s:%s:%s:%s",
		id,
		tostring(req.target),
		tostring(req.amount or req.hours or ""),
		tostring(req.role or "")
	)
end

local function runTool(id: string)
	local req = Hub.Request(id, context())
	if not req then
		return
	end
	local reason = Hub.Check(req, player.Name)
	if reason then
		pending = nil
		setStatus(false, reason)
		render(nil)
		return
	end
	local needsTwo = Hub.NeedsConfirmFor(id, req, access.tester)
	local fire, nextPending = Hub.Press(id, toolKey(id), os.clock(), pending, needsTwo)
	pending = nextPending
	if not fire then
		local tool = Hub.Tool(id)
		if id == "delegate" and req.role == "TESTER" then
			setStatus(false, AdminLogic.TesterWarning .. " Press again to confirm.")
		else
			setStatus(nil, "Press again within a few seconds to confirm: " .. (if tool then tool.label else id) .. ".")
		end
		render(nil)
		local mine = nextPending
		task.delay(Hub.ConfirmWindow + 0.1, function()
			if pending == mine and mine ~= nil then
				pending = nil
				render(nil)
			end
		end)
		return
	end
	if id == "gift" and state.item then
		state.recents = Hub.PushRecent(state.recents, state.item)
	end
	if needsTwo then
		req.confirmed = true -- "I pressed twice": the server asks for it from a TESTER, never as a permission
	end
	setStatus(nil, "Sending...")
	send(req)
	render(nil)
end

---------------------------------------------------------------------------
-- Widgets (everything below builds into the scrolling body)
---------------------------------------------------------------------------

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function register(id: string, obj: GuiObject)
	objById[id] = obj
	idOf[obj] = id
end

local function makeButton(
	parent: Instance,
	id: string,
	text: string,
	style: string,
	size: UDim2,
	onPress: () -> ()
): UITheme.Button
	local b = UITheme.Button({ text = text, size = Vector2.new(100, L.Row), style = style, textSize = 16, name = id })
	b.root.Size = size
	b.root.Parent = parent
	register(id, b.face)
	b.face.Activated:Connect(onPress)
	return b
end

local function container(height: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.LayoutOrder = nextOrder()
	if height then
		f.Size = UDim2.new(1, 0, 0, height)
	else
		f.Size = UDim2.fromScale(1, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
	end
	return f
end

local function hintLabel(parent: Instance, text: string)
	local h = UITheme.label(parent, text, UITheme.Fonts.Body, L.HintText, C.Bark)
	h.Size = UDim2.fromScale(1, 0)
	h.AutomaticSize = Enum.AutomaticSize.Y
	h.TextWrapped = true
	h.TextXAlignment = Enum.TextXAlignment.Left
	return h
end

local function section(text: string, hint: string?)
	local f = container(nil)
	UITheme.list(f, 2)
	local t = UITheme.label(f, text, UITheme.Fonts.Heading, 17, C.Ink)
	t.Size = UDim2.new(1, 0, 0, 24)
	t.LayoutOrder = 1
	if hint then
		hintLabel(f, hint).LayoutOrder = 2
	end
	f.Parent = body
end

-- One tool: a full-width button with its hint under it.
local function toolBlock(toolId: string, labelOverride: string?)
	local tool = Hub.Tool(toolId)
	if not tool or not allowedNow(toolId) then
		return
	end
	local f = container(nil)
	UITheme.list(f, 4)
	local text = labelOverride or tool.label
	if pending and pending.key == toolKey(toolId) and Hub.StillPending(pending, os.clock()) then
		text = if toolId == "delegate" then "SURE? GIVE FULL POWER" else Hub.SureText(toolId, currentWho())
	end
	local style = tool.style
	if text ~= (labelOverride or tool.label) then
		style = "amber"
	end
	local b = makeButton(f, "tool_" .. toolId, text, style, UDim2.new(1, 0, 0, L.Row + 3), function()
		runTool(toolId)
	end)
	b.root.LayoutOrder = 1
	hintLabel(f, tool.hint).LayoutOrder = 2
	f.Parent = body
	table.insert(rows, { "tool_" .. toolId })
end

-- caption  ‹ value ›
local function stepper(id: string, caption: string, value: string, onStep: (number) -> ())
	local f = container(L.Row + 3)
	UITheme.list(f, L.Gap, true)
	local cap = UITheme.label(f, caption, UITheme.Fonts.Black, 15, C.Ink)
	cap.Size = UDim2.new(0, 64, 1, -3)
	cap.LayoutOrder = 1
	local left = makeButton(f, id .. "_prev", "‹", "bark", UDim2.fromOffset(L.Chip + 8, L.Row + 3), function()
		onStep(-1)
	end)
	left.root.LayoutOrder = 2
	local v = UITheme.label(f, value, UITheme.Fonts.Heading, 18, C.Ink)
	v.Size = UDim2.new(1, -(64 + 2 * (L.Chip + 8) + 3 * L.Gap), 1, -3)
	v.TextXAlignment = Enum.TextXAlignment.Center
	v.TextTruncate = Enum.TextTruncate.AtEnd
	v.LayoutOrder = 3
	local right = makeButton(f, id .. "_next", "›", "bark", UDim2.fromOffset(L.Chip + 8, L.Row + 3), function()
		onStep(1)
	end)
	right.root.LayoutOrder = 4
	f.Parent = body
	table.insert(rows, { id .. "_prev", id .. "_next" })
end

-- A row of choices; the chosen one is green.
local function chips(prefix: string, labels: { string }, selected: number, onPick: (number) -> ())
	local f = container(L.Chip + 3)
	UITheme.list(f, L.Gap, true)
	local n = #labels
	local ids: { string } = {}
	for i, label in ipairs(labels) do
		local id = prefix .. i
		local b = makeButton(
			f,
			id,
			label,
			if i == selected then "buy" else "skip",
			UDim2.new(1 / n, -math.ceil(L.Gap * (n - 1) / n), 0, L.Chip + 3),
			function()
				onPick(i)
			end
		)
		b.root.LayoutOrder = i
		table.insert(ids, id)
	end
	f.Parent = body
	table.insert(rows, ids)
end

local function textBox(id: string, placeholder: string, text: string, onChanged: (string) -> ()): TextBox
	local f = container(L.Row)
	local box = Instance.new("TextBox")
	box.Name = id
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = C.Cream
	box.BorderSizePixel = 0
	box.Font = UITheme.Fonts.Body
	box.TextSize = 16
	box.TextColor3 = C.Ink
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = C.Muted
	box.Text = text
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	UITheme.corner(box, 10)
	UITheme.stroke(box, C.Bark, 2)
	UITheme.padding(box, 0, 10, 0, 10)
	box.Parent = f
	register(id, box)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		onChanged(box.Text)
	end)
	f.Parent = body
	table.insert(rows, { id })
	return box
end

---------------------------------------------------------------------------
-- Navigation: the pad's order, and scrolling that follows it
---------------------------------------------------------------------------

-- A neighbour for NextSelection*, or nil (the engine types it as never nil).
local function link(id: string?): any
	return if id then objById[id] else nil
end

local function applyNav()
	local all: { { string } } = {}
	for _, r in ipairs(headerRows) do
		table.insert(all, r)
	end
	for _, r in ipairs(rows) do
		table.insert(all, r)
	end
	local grid = Hub.NavGrid(all)
	for id, nav in pairs(grid) do
		local obj = objById[id]
		if obj then
			obj.NextSelectionUp = link(nav.up)
			obj.NextSelectionDown = link(nav.down)
			obj.NextSelectionLeft = link(nav.left)
			obj.NextSelectionRight = link(nav.right)
		end
	end
end

local function followSelection()
	local b = body
	local sel = GuiService.SelectedObject
	if not b or not sel or not sel:IsDescendantOf(b) or not sel:IsA("GuiObject") then
		return
	end
	local ui = b:FindFirstAncestorOfClass("ScreenGui")
	local scaleObj = if ui then ui:FindFirstChildOfClass("UIScale") else nil
	local scale = if scaleObj then scaleObj.Scale else 1
	local top = (sel.AbsolutePosition.Y - b.AbsolutePosition.Y) / scale + b.CanvasPosition.Y
	local viewH = b.AbsoluteSize.Y / scale
	local canvasH = b.AbsoluteCanvasSize.Y / scale
	local target = Hub.ScrollTarget(b.CanvasPosition.Y, viewH, top, sel.AbsoluteSize.Y / scale, 12, canvasH)
	if math.abs(target - b.CanvasPosition.Y) > 0.5 then
		b.CanvasPosition = Vector2.new(0, target)
	end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function playerBar()
	local who = currentWho()
	stepper("pick", "PLAYER", who or "(nobody)", function(d)
		state.who = Hub.StepName(names(), state.who, d, player.Name)
		pending = nil
		render("pick_" .. (if d < 0 then "prev" else "next"))
	end)
end

local function amountSection()
	section("AMOUNT", "Pick a size, or type your own (2500, 10k, 1.5m).")
	local labels: { string } = {}
	for _, a in ipairs(Hub.Amounts) do
		table.insert(labels, Util.formatCash(a))
	end
	chips("amt", labels, if state.custom == "" then state.amountIndex else 0, function(i)
		state.amountIndex = i
		state.custom = ""
		pending = nil
		render("amt" .. i)
	end)
	textBox("custom", "Custom amount", state.custom, function(text)
		state.custom = text
		pending = nil
		local label = amountLabel
		if label then
			local n = currentAmount()
			label.Text = if n then "Amount: " .. Util.formatCash(n) else "Not an amount I understand."
		end
	end)
	local n = currentAmount()
	local label = UITheme.label(
		body :: ScrollingFrame,
		if n then "Amount: " .. Util.formatCash(n) else "Not an amount I understand.",
		UITheme.Fonts.Bold,
		15,
		C.Ink
	)
	label.Size = UDim2.new(1, 0, 0, 22)
	label.LayoutOrder = nextOrder()
	amountLabel = label
end

local function fillList()
	local holder = listHolder
	if not holder then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	-- Everything after the fixed rows is the list, so drop its old rows.
	while #rows >= listRowStart do
		table.remove(rows)
	end
	local found = Hub.Filter(allItems(), state.query, state.category, state.recents)
	local shown, more = Hub.Limit(found, L.MaxListRows)
	if #shown == 0 then
		local none = hintLabel(
			holder,
			if state.category == "Recent"
				then "Nothing gifted yet this session."
				else "No items match. Clear the search or change the type."
		)
		none.LayoutOrder = 1
	end
	for i, item in ipairs(shown) do
		local picked = state.item ~= nil and state.item.id == item.id and state.item.kind == item.kind
		local id = "item" .. i
		local b = makeButton(
			holder,
			id,
			(if picked then "✓ " else "") .. item.name .. "  (" .. item.kind .. ")",
			if picked then "buy" else "skip",
			UDim2.new(1, 0, 0, L.Row + 3),
			function()
				state.item = item
				setStatus(nil, "Picked " .. item.name .. ". Press GIFT to hand it over.")
				render(id)
			end
		)
		b.root.LayoutOrder = i + 1
		table.insert(rows, { id })
	end
	if more > 0 then
		local label = hintLabel(holder, string.format("%d more. Type in the search box to narrow it down.", more))
		label.LayoutOrder = #shown + 2
	end
	applyNav()
end

local function playersTab()
	section("PLAYERS ON THIS SERVER", "Tap a name to pick them. The pick is kept on every tab.")
	local list = names()
	for i, name in ipairs(Hub.SortNames(list, player.Name)) do
		local id = "player" .. i
		local f = container(L.Row + 3)
		local picked = name == state.who
		local label = name .. (if name == player.Name then " (you)" else "")
		makeButton(
			f,
			id,
			(if picked then "✓ " else "") .. label,
			if picked then "buy" else "skip",
			UDim2.fromScale(1, 1),
			function()
				state.who = name
				pending = nil
				render(id)
			end
		)
		f.Parent = body
		table.insert(rows, { id })
	end
	local actionIds = { "goto", "bring", "heal", "freeze", "stats", "resettutorial" }
	if anyAllowed(actionIds) then
		section("ACTIONS ON " .. string.upper(state.who or "NOBODY"))
		for _, id in ipairs(actionIds) do
			toolBlock(id)
		end
	end
	if allowedNow("kick") then
		section("DANGEROUS", "These need a second press.")
		toolBlock("kick")
	end
	if allowedNow("ban") then
		section("BAN LENGTH")
		local labels: { string } = {}
		for _, choice in ipairs(Hub.BanChoices) do
			table.insert(labels, choice.label)
		end
		chips("ban", labels, state.banIndex, function(i)
			state.banIndex = i
			pending = nil
			render("ban" .. i)
		end)
		toolBlock("ban")
	end
end

local function giveTab()
	if allowedNow("give") or allowedNow("take") or allowedNow("setcash") then
		amountSection()
		section("CASH", "Cash only moves through the economy, so the wallet cap still applies.")
		toolBlock("give")
		toolBlock("take")
		toolBlock("setcash")
	end
	toolBlock("unlockbp")
	if not allowedNow("gift") then
		return
	end
	section("FREE ITEMS", "Pick a type, search, pick an item, then press GIFT.")
	stepper("kind", "TYPE", state.category, function(d)
		state.category = Hub.NextCategory(state.category, d)
		render("kind_" .. (if d < 0 then "prev" else "next"))
	end)
	textBox("search_items", "Search items", state.query, function(text)
		state.query = text
		fillList()
	end)
	local item = state.item
	toolBlock("gift", if item then "GIFT: " .. string.upper(item.name) else nil)
	local holder = container(nil)
	UITheme.list(holder, 6)
	holder.Parent = body
	listHolder = holder
	listRowStart = #rows + 1
	fillList()
end

local function worldTab()
	if allowedNow("timespeed") or allowedNow("settime") or allowedNow("timereset") then
		section("CLOCK", "Changes this server only and is never saved.")
	end
	if allowedNow("timespeed") then
		local speeds: { string } = {}
		for _, s in ipairs(WorldTime.Speeds) do
			table.insert(speeds, string.format("%dx", s))
		end
		chips("speed", speeds, state.speedIndex, function(i)
			state.speedIndex = i
			render("speed" .. i)
		end)
		toolBlock("timespeed")
	end
	if allowedNow("settime") then
		local hours: { string } = {}
		for _, h in ipairs(AdminLogic.TimePresetOrder) do
			table.insert(hours, Hub.HourNames[h] or h)
		end
		chips("hour", hours, state.hourIndex, function(i)
			state.hourIndex = i
			render("hour" .. i)
		end)
		toolBlock("settime")
	end
	toolBlock("timereset")
	if allowedNow("announce") then
		section("ANNOUNCE", "Type a message, or fill one in. Everyone on this server sees it.")
		local box = textBox("announce_text", "Message to everyone", state.announce, function(text)
			state.announce = text
		end)
		for i, preset in ipairs(Hub.AnnouncePresets) do
			local id = "preset" .. i
			local f = container(L.Row + 3)
			makeButton(f, id, preset, "skip", UDim2.fromScale(1, 1), function()
				state.announce = preset
				box.Text = preset
				setStatus(nil, "Message filled in. Press ANNOUNCE to send it.")
			end)
			f.Parent = body
			table.insert(rows, { id })
		end
		toolBlock("announce")
	end
	if allowedNow("shutdown") then
		section("SERVER", "Dangerous: needs a second press.")
		toolBlock("shutdown")
	end
end

local function selfTab()
	toolBlock("superrun")
	toolBlock("god")
	toolBlock("tospawn")
	if access.allowed == nil then
		-- The owner's own list: what they did, and what their delegates did.
		section("LAST ACTIONS", "Newest first. The server also logs each one with both ids in Output.")
		local audit =
			UITheme.label(body :: ScrollingFrame, table.concat(state.audit, "\n"), UITheme.Fonts.Body, 14, C.Ink)
		audit.Size = UDim2.fromScale(1, 0)
		audit.AutomaticSize = Enum.AutomaticSize.Y
		audit.TextWrapped = true
		audit.LayoutOrder = nextOrder()
		if #state.audit == 0 then
			audit.Text = "Nothing yet."
		end
		auditLabel = audit
	end
	section("CHAT COMMANDS", "Type /admin in chat for the whole list.")
end

-- A coloured banner: who you are here, and for how long.
local function accessBanner()
	if access.role ~= "delegate" then
		return
	end
	local f = container(nil)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = if access.tester then C.Danger else C.Bark
	UITheme.corner(f, 10)
	UITheme.padding(f, 6, 10, 6, 10)
	local text = if access.tester then "TESTER (full power)" else "DELEGATE: " .. access.grantRole
	local left = access.secondsLeft
	if left then
		text ..= string.format("  |  %d min left", math.ceil(left / 60))
	end
	local label = hintLabel(f, text)
	label.TextColor3 = C.Cream
	label.Font = UITheme.Fonts.Black
	label.TextSize = 15
	f.Parent = body
end

local function delegateRow(i: number, row: { [string]: any })
	local id = "revoke" .. i
	local f = container(L.Row + 3)
	UITheme.list(f, L.Gap, true)
	local left = row.secondsLeft
	local lasts = if type(left) == "number"
		then string.format("%d min left", math.ceil(left / 60))
		elseif row.session == true then "this session"
		else "until the server closes"
	local info = UITheme.label(
		f,
		string.format("%s: %s (%s)", tostring(row.name), tostring(row.role), lasts),
		UITheme.Fonts.Bold,
		14,
		C.Ink
	)
	info.Size = UDim2.new(1, -(110 + L.Gap), 1, -3)
	info.TextWrapped = true
	info.LayoutOrder = 1
	local b = makeButton(f, id, "REVOKE", "skip", UDim2.fromOffset(110, L.Row + 3), function()
		setStatus(nil, "Sending...")
		send({ action = "undelegate", target = tostring(row.name) })
	end)
	b.root.LayoutOrder = 2
	f.Parent = body
	table.insert(rows, { id })
end

local function delegatesTab()
	local role = AdminLogic.RoleList[state.roleIndex]
	section("ROLE", AdminLogic.RoleHints[role])
	chips("role", AdminLogic.RoleList, state.roleIndex, function(i)
		state.roleIndex = i
		pending = nil
		render("role" .. i)
	end)
	if role == "TESTER" then
		local warning = container(nil)
		warning.BackgroundTransparency = 0
		warning.BackgroundColor3 = C.Danger
		UITheme.corner(warning, 10)
		UITheme.padding(warning, 8, 10, 8, 10)
		local text = hintLabel(warning, "WARNING: " .. AdminLogic.TesterWarning)
		text.TextColor3 = C.Cream
		text.Font = UITheme.Fonts.Black
		text.TextSize = 15
		warning.Parent = body
	elseif role == "CUSTOM" then
		section(
			"POWERS",
			"Tick what they may do. Cash, shutdown, super run, saves and delegation are never on this list."
		)
		for _, power in ipairs(AdminLogic.DelegablePowers) do
			local id = "power_" .. power
			local on = state.powers[power] == true
			local f = container(L.Row + 3)
			makeButton(
				f,
				id,
				(if on then "✓ " else "") .. (Hub.PowerLabels[power] or power),
				if on then "buy" else "skip",
				UDim2.fromScale(1, 1),
				function()
					state.powers[power] = (if on then nil else true) :: any
					pending = nil
					render(id)
				end
			)
			f.Parent = body
			table.insert(rows, { id })
		end
	end
	local choices = Hub.ExpiriesFor(role)
	state.expiryIndex = math.clamp(state.expiryIndex, 1, #choices)
	section("LASTS", "Grants live in server memory only. They end when the server closes, and always when you revoke.")
	local labels: { string } = {}
	for _, choice in ipairs(choices) do
		table.insert(labels, choice.label)
	end
	chips("exp", labels, state.expiryIndex, function(i)
		state.expiryIndex = i
		pending = nil
		render("exp" .. i)
	end)
	toolBlock("delegate", "GRANT " .. role .. " TO " .. string.upper(currentWho() or "NOBODY"))
	toolBlock("undelegate")
	section("CURRENT DELEGATES", "Tap REVOKE to take every power back at once.")
	if #access.delegates == 0 then
		hintLabel(body :: ScrollingFrame, "Nobody has powers right now.").LayoutOrder = nextOrder()
	end
	for i, row in ipairs(access.delegates) do
		delegateRow(i, row)
	end
	toolBlock("delegates")
end

local function searchResults()
	local found = Hub.FilterTools(state.toolQuery, access.allowed)
	section(
		'TOOLS MATCHING "' .. state.toolQuery .. '"',
		"They use the player, amount and item you picked on the other tabs."
	)
	if #found == 0 then
		hintLabel(body :: ScrollingFrame, "No tool matches that.").LayoutOrder = nextOrder()
	end
	for _, tool in ipairs(found) do
		toolBlock(tool.id)
	end
end

local function currentFocusId(): string?
	local sel = GuiService.SelectedObject
	return if sel then idOf[sel] else nil
end

render = function(focus: string?)
	local b = body
	if not b then
		return
	end
	local keep = focus or currentFocusId()
	local savedY = b.CanvasPosition.Y
	for _, child in ipairs(b:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for id, obj in pairs(objById) do
		if string.sub(id, 1, 3) ~= "tab" and id ~= "close" and id ~= "search" then
			objById[id] = nil
			idOf[obj] = nil
		end
	end
	rows = {}
	order = 0
	listHolder = nil
	amountLabel = nil
	auditLabel = nil
	local tabs = visibleTabs()
	local tab = currentTab()
	state.tabId = tab.id
	local tabIds: { string } = {}
	for i, def in ipairs(Hub.Tabs) do
		local button = tabButtons[i]
		local shown = false
		for _, v in ipairs(tabs) do
			if v.id == def.id then
				shown = true
			end
		end
		button.root.Visible = shown
		if shown then
			table.insert(tabIds, "tab" .. i)
			button.root.Size = UDim2.new(1 / #tabs, -math.ceil(L.Gap * (#tabs - 1) / #tabs), 0, L.TabHeight + 3)
		end
		button:SetStyle(if def.id == tab.id and state.toolQuery == "" then "amber" else "bark")
	end
	headerRows[2] = tabIds
	accessBanner()
	if state.toolQuery ~= "" then
		playerBar()
		searchResults()
	else
		if tab.id ~= "world" and tab.id ~= "self" then
			playerBar()
		end
		if tab.id == "players" then
			playersTab()
		elseif tab.id == "give" then
			giveTab()
		elseif tab.id == "world" then
			worldTab()
		elseif tab.id == "delegates" then
			delegatesTab()
		else
			selfTab()
		end
	end
	applyNav()
	paintStatus()
	task.defer(function()
		local bb = body
		if not bb then
			return
		end
		bb.CanvasPosition = Vector2.new(0, savedY)
		if keep and UITheme.Device() == "console" then
			local obj = objById[keep]
			if obj then
				GuiService.SelectedObject = obj
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Open, close, build
---------------------------------------------------------------------------

local function setTab(id: string)
	state.tabId = id
	state.toolQuery = ""
	pending = nil
	statusText = ""
	statusOk = nil
	local searchBox = objById["search"]
	if searchBox and searchBox:IsA("TextBox") then
		searchBox.Text = ""
	end
	render(nil)
	local b = body
	if b then
		b.CanvasPosition = Vector2.new(0, 0)
	end
	if id == "delegates" and access.allowed == nil then
		send({ action = "delegates" }) -- refresh the list (the owner only; the server ignores anyone else)
	end
end

local function stepTab(dir: number)
	local tabs = visibleTabs()
	local at = 1
	for i, tab in ipairs(tabs) do
		if tab.id == state.tabId then
			at = i
		end
	end
	setTab(tabs[Hub.TabStep(at, dir, #tabs)].id)
end

local function setOpen(on: boolean)
	local p = panel
	if not p then
		return
	end
	if on and not hasHub() then
		return
	end
	p.Visible = on
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(TAB_PREV)
	ContextActionService:UnbindAction(TAB_NEXT)
	if not on then
		MenuPad.Close(p)
		return
	end
	pending = nil
	render(nil)
	local priority = Enum.ContextActionPriority.High.Value + 30
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_name, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		setOpen(false)
		return Enum.ContextActionResult.Sink
	end, false, priority, InputKit.Actions.Cancel.keyboard, InputKit.Actions.Cancel.gamepad)
	ContextActionService:BindActionAtPriority(TAB_PREV, function(_name, inputState)
		if inputState == Enum.UserInputState.Begin then
			stepTab(-1)
		end
		return Enum.ContextActionResult.Sink
	end, false, priority, Enum.KeyCode.ButtonL1)
	ContextActionService:BindActionAtPriority(TAB_NEXT, function(_name, inputState)
		if inputState == Enum.UserInputState.Begin then
			stepTab(1)
		end
		return Enum.ContextActionResult.Sink
	end, false, priority, Enum.KeyCode.ButtonR1)
	if UITheme.Device() == "console" then
		MenuPad.Open(objById[headerRows[2][1] or "close"])
	end
end

local function toggle()
	local p = panel
	setOpen(not (p ~= nil and p.Visible))
end

-- Everything below exists only on the owner's client: nothing is built for
-- anyone else (the attribute only ever arrives on the owner's player).
local function build()
	local gui = UITheme.Screen("AdminUI", UITheme.Layers.Admin)
	gui.Parent = UITheme.PlayerGui()

	local outer = Instance.new("Frame")
	outer.Name = "Owner"
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.new(1, -16, 1, -16)
	outer.BackgroundColor3 = C.Paper
	outer.BorderSizePixel = 0
	outer.Visible = false
	UITheme.corner(outer, 14)
	UITheme.stroke(outer, C.Bark, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(L.PanelMaxW, L.PanelMaxH)
	limit.Parent = outer
	-- A pad's stick never walks out of the panel.
	outer.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	outer.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	outer.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	outer.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	outer.Parent = gui
	panel = outer

	-- Title, tool search, close.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(L.Pad, 8)
	header.Size = UDim2.new(1, -2 * L.Pad, 0, L.Row)
	header.Parent = outer
	UITheme.list(header, L.Gap, true)
	local title = UITheme.label(header, "OWNER", UITheme.Fonts.Heading, 22, C.Ink)
	title.Size = UDim2.new(0, 104, 1, 0)
	titleLabel = title
	title.LayoutOrder = 1
	local searchWrap = Instance.new("Frame")
	searchWrap.BackgroundTransparency = 1
	searchWrap.LayoutOrder = 2
	searchWrap.Size = UDim2.new(1, -(104 + L.Chip + 2 * L.Gap), 1, 0)
	searchWrap.Parent = header
	local search = Instance.new("TextBox")
	search.Name = "search"
	search.Size = UDim2.new(1, 0, 0, L.Row)
	search.BackgroundColor3 = C.Cream
	search.BorderSizePixel = 0
	search.Font = UITheme.Fonts.Body
	search.TextSize = 16
	search.TextColor3 = C.Ink
	search.PlaceholderText = "Find a tool..."
	search.PlaceholderColor3 = C.Muted
	search.Text = ""
	search.ClearTextOnFocus = false
	search.TextXAlignment = Enum.TextXAlignment.Left
	UITheme.corner(search, 10)
	UITheme.stroke(search, C.Bark, 2)
	UITheme.padding(search, 0, 10, 0, 10)
	search.Parent = searchWrap
	register("search", search)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		state.toolQuery = string.match(search.Text, "^%s*(.-)%s*$") or ""
		render(nil)
	end)
	local close = UITheme.Button({
		text = "X",
		size = Vector2.new(L.Chip, L.Chip),
		style = "skip",
		textSize = 20,
		name = "Close",
	})
	close.root.LayoutOrder = 3
	close.root.Parent = header
	register("close", close.face)
	close.face.Activated:Connect(function()
		setOpen(false)
	end)

	-- Tabs.
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(L.Pad, 8 + L.Row + L.Gap)
	tabs.Size = UDim2.new(1, -2 * L.Pad, 0, L.TabHeight + 3)
	tabs.Parent = outer
	UITheme.list(tabs, L.Gap, true)
	for i, tab in ipairs(Hub.Tabs) do
		local b = UITheme.Button({
			text = tab.label,
			size = Vector2.new(60, L.TabHeight),
			style = "bark",
			textSize = 15,
			name = "Tab" .. tab.id,
		})
		b.root.Size = UDim2.new(1 / #Hub.Tabs, -math.ceil(L.Gap * (#Hub.Tabs - 1) / #Hub.Tabs), 0, L.TabHeight + 3)
		b.root.LayoutOrder = i
		b.root.Parent = tabs
		register("tab" .. i, b.face)
		b.face.Activated:Connect(function()
			setTab(tab.id)
		end)
		table.insert(tabButtons, b)
	end

	-- Status strip: who is picked, and what just happened.
	local footer = Instance.new("Frame")
	footer.Name = "Status"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, L.Pad, 1, -8)
	footer.Size = UDim2.new(1, -2 * L.Pad, 0, 60)
	footer.BackgroundColor3 = C.PaperDark
	footer.BorderSizePixel = 0
	UITheme.corner(footer, 10)
	UITheme.padding(footer, 4, 10, 4, 10)
	footer.Parent = outer
	local picked = UITheme.label(footer, "", UITheme.Fonts.Black, 13, C.Bark)
	picked.Size = UDim2.new(1, 0, 0, 16)
	pickedLabel = picked
	local status = UITheme.label(footer, "", UITheme.Fonts.Bold, 15, C.Ink)
	status.Position = UDim2.fromOffset(0, 18)
	status.Size = UDim2.new(1, 0, 1, -18)
	status.TextWrapped = true
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel = status

	-- The scrolling body; the pad's selection scrolls it along.
	local top = 8 + L.Row + L.Gap + L.TabHeight + 3 + L.Gap
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(L.Pad, top)
	scroll.Size = UDim2.new(1, -2 * L.Pad, 1, -(top + 60 + 16))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = outer
	local layout = UITheme.list(scroll, 10)
	layout.Padding = UDim.new(0, 10)
	UITheme.padding(scroll, 0, 12, 0, 0)
	body = scroll

	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(followSelection)

	Players.PlayerAdded:Connect(function()
		if outer.Visible then
			render(nil)
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if outer.Visible then
				render(nil)
			end
		end)
	end)

	-- What the server did (or why it refused), for the status strip.
	Net.Remote("AdminResult").OnClientEvent:Connect(function(ok: unknown, text: unknown)
		local line = Hub.StatusText(text)
		setStatus(ok == true, line)
		state.audit = Hub.PushAudit(state.audit, (if ok == true then "OK: " else "NO: ") .. line)
		local label = auditLabel
		if label then
			label.Text = table.concat(state.audit, "\n")
		end
	end)

	-- The side button and the L3 + R3 chord exist only for the owner.
	local side = HUD.SideButton({
		name = "Owner",
		text = "OWNER",
		style = "bark",
		order = 0,
		onPress = toggle,
	})
	side.root.Visible = false
	sideButton = side
	player:GetAttributeChangedSignal("IsOwner"):Connect(syncHub)
	syncHub()

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if
			hasHub()
			and (input.KeyCode == Enum.KeyCode.ButtonL3 or input.KeyCode == Enum.KeyCode.ButtonR3)
			and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3)
			and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR3)
		then
			toggle()
		end
	end)
end

-- The server's word on what this player's hub may show (AdminAccess): an
-- owner's list of delegates, a delegate's grant, the audit lines, or the end
-- of a grant (the hub closes at once). It only shapes the UI; every request is
-- re-checked on the server.
local built = false
local function ensureBuilt()
	if not built and hasHub() then
		built = true
		build()
	end
end

syncHub = function()
	local can = hasHub()
	local side = sideButton
	if side then
		side.root.Visible = can
		side:SetText(if access.role == "delegate" then (if access.tester then "TESTER" else "DELEGATE") else "OWNER")
	end
	local title = titleLabel
	if title then
		title.Text = if access.role == "delegate" then (if access.tester then "TESTER" else "DELEGATE") else "OWNER"
		title.TextColor3 = if access.tester then C.Danger else C.Ink
	end
	if not can then
		setOpen(false)
	end
end

local function onAccess(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local p = payload :: { [string]: any }
	if p.kind == "audit" then
		if type(p.text) == "string" then
			state.audit = Hub.PushAudit(state.audit, "> " .. Hub.StatusText(p.text))
			local label = auditLabel
			if label then
				label.Text = table.concat(state.audit, "\n")
			end
		end
		return
	end
	if p.kind == "revoked" then
		access.role = "revoked"
		access.allowed = nil
		access.tester = false
		access.delegates = {}
		syncHub()
		setOpen(false)
		return
	end
	if p.kind ~= "access" then
		return
	end
	if p.role == "owner" then
		access.role = "owner"
		access.allowed = nil
		access.tester = false
		access.label = "OWNER"
		if type(p.delegates) == "table" then
			access.delegates = p.delegates
		end
	elseif p.role == "delegate" and type(p.actions) == "table" then
		local set: { [string]: boolean } = {}
		for _, action in ipairs(p.actions) do
			if type(action) == "string" then
				set[action] = true
			end
		end
		access.role = "delegate"
		access.allowed = set
		access.tester = p.tester == true
		access.label = if type(p.label) == "string" then p.label else "DELEGATE"
		access.grantRole = if type(p.grantRole) == "string" then p.grantRole else ""
		access.secondsLeft = if type(p.secondsLeft) == "number" then p.secondsLeft else nil
		state.tabId = "players"
	else
		return
	end
	ensureBuilt()
	syncHub()
	local panelNow = panel
	if panelNow and panelNow.Visible then
		render(nil)
	end
end

function AdminUI.Start()
	player:GetAttributeChangedSignal("IsOwner"):Connect(function()
		if access.role == "revoked" and isOwner() then
			access.role = "none"
		end
		ensureBuilt()
	end)
	ensureBuilt()
	task.spawn(function()
		Net.Remote("AdminAccess").OnClientEvent:Connect(onAccess)
	end)
end

return AdminUI
