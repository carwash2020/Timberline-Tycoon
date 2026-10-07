--!strict
-- AdminUI: the owner hub. Only the owner (and anyone the owner delegated
-- powers to) sees it: the server sets the IsOwner attribute on the owner's
-- player and sends a delegate their grant, and this module builds nothing
-- without one of them. That is a convenience, not the lock: every press
-- fires the AdminRun remote with a small request, and AdminService refuses it
-- unless the sender holds the power (and AdminLogic.FromRequest whitelists the
-- request). A modified client gets nothing and is not even answered.
--
-- Open it with the OWNER side button, or click both thumbsticks (L3 + R3).
-- B / Esc go back ONE level (cancel a confirmation, clear a search, leave an
-- item for its list) and close the hub only when there is nothing left to go
-- back from. The X closes at once. LB / RB (and LT / RT) change tab.
--
-- A header that never scrolls away says who you are and your role.
--   PLAYERS      pick a player (search, recents first), go to them, bring
--                them, heal, freeze, stats, reset tutorial, kick, ban, unban;
--                your own tools (super run, god mode, go to spawn)
--   GIFTS        cash (give / take / set), unlock every building, free items
--                (type, search, recents first)
--   PAID ITEMS   everything the Robux store sells (Shared/PaidItems, built
--                from StoreData, so a new store item shows up by itself):
--                what the picked player owns, GIVE, REVOKE, a boost's length
--   WORLD        clock speed, set hour, reset time, announce, shut down server
--   ROLES        give other people some powers, and take them back
--   LOG          what was done, and every chat command (with a search)
--
-- The search box in the header finds any tool by name. Every tool has a one
-- line hint, and a button that can't go says why under it. Kick, ban, take
-- cash, set cash, revoke, reset tutorial, giving paid items and shut down all
-- need a second press. The strip at the bottom says exactly what just
-- happened or why the server refused. On a pad: D-pad / stick move in the
-- order AdminHubLogic.NavGrid lays out, A presses, rows are big, and the list
-- scrolls to keep the selected row in view. All rules (tabs, confirmations,
-- filters, back, navigation) live in Shared/AdminHubLogic, which is tested.

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
local PaidItems = require(ReplicatedStorage.Shared.PaidItems)
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
	recentPlayers = {} :: { string },
	playerQuery = "",
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
	unban = "",
	cmdQuery = "",
	paidQuery = "",
	paidId = nil :: string?, -- the paid item opened (its detail level), nil on the list
	paidRecents = {} :: { string },
	paidHourIndex = 3,
}

-- What the server last said the picked player owns (AdminAccess "paidstate").
local paidState: { target: string?, rows: { [string]: any } } = { target = nil, rows = {} }
local paidAskedAt: { [string]: number } = {}

local panel: Frame? = nil
local body: ScrollingFrame? = nil
local tabsFrame: Frame? = nil
local sideButton: UITheme.Button? = nil
local statusLabel: TextLabel? = nil
local pickedLabel: TextLabel? = nil
local whoLabel: TextLabel? = nil
local whoStrip: Frame? = nil
local auditLabel: TextLabel? = nil
local amountLabel: TextLabel? = nil
local tabButtons: { UITheme.Button } = {}
local objById: { [string]: GuiObject } = {}
local idOf: { [GuiObject]: string } = {}
local rows: { { string } } = {}
local headerRows: { { string } } = { { "search", "close" }, { "tab1", "tab2", "tab3", "tab4" } }
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

-- A delegate with the Gifts power gives paid items to themself only.
local function selfOnly(): boolean
	return access.allowed ~= nil
end

local function device(): string
	return UITheme.Device()
end

-- A list row's height on this device (a pad gets big rows), plus the 3px edge.
local function rh(): number
	return Hub.RowHeight(device()) + 3
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

-- The paid items, built fresh from the store data each time they are read.
local function paidItems(): { PaidItems.Item }
	return PaidItems.All()
end

local function paidItem(id: string?): PaidItems.Item?
	return PaidItems.Find(paidItems(), id)
end

-- The boost length picked for a paid item (nil: the item's own).
local function chosenHours(item: PaidItems.Item?): number?
	if item == nil or item.effect ~= "boost" then
		return nil
	end
	return PaidItems.HourChoices[math.clamp(state.paidHourIndex, 1, #PaidItems.HourChoices)]
end

local function unbanId(): number?
	local n = tonumber(state.unban)
	if n and n > 0 and n % 1 == 0 and n <= 2 ^ 52 then
		return n
	end
	return nil
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
		paidId = state.paidId,
		paidHours = chosenHours(paidItem(state.paidId)),
		userId = unbanId(),
	}
end

---------------------------------------------------------------------------
-- Status strip, header and sending
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

-- The persistent "who am I" line: your name, your role, how long it lasts.
local function paintWho()
	local label, strip = whoLabel, whoStrip
	if label then
		label.Text = Hub.WhoText(
			player.Name,
			if access.role == "delegate" then access.label else "OWNER",
			if access.role == "delegate" then access.grantRole else nil,
			if access.role == "delegate" then access.secondsLeft else nil
		)
	end
	if strip then
		strip.BackgroundColor3 = if access.tester
			then C.Danger
			elseif access.role == "delegate" then C.Bark
			else C.PaperDark
		if label then
			label.TextColor3 = if access.role == "delegate" then C.Cream else C.Ink
		end
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
	return table.concat({
		id,
		tostring(req.target),
		tostring(req.amount or req.hours or ""),
		tostring(req.role or ""),
		tostring(req.itemId or ""),
		tostring(req.userId or ""),
	}, ":")
end

-- Presses with a second-press confirmation: the first press arms it (the
-- button turns amber and says SURE?), a second press for the same thing
-- within the window fires. `force` asks for the second press even for a tool
-- that does not always need it.
local function armOrFire(id: string, key: string, force: boolean, prompt: string, fire: () -> ())
	local go, nextPending = Hub.Press(id, key, os.clock(), pending, force)
	pending = nextPending
	if go then
		fire()
		return
	end
	setStatus(nil, prompt)
	render(nil)
	local mine = nextPending
	task.delay(Hub.ConfirmWindow + 0.1, function()
		if pending == mine and mine ~= nil then
			pending = nil
			render(nil)
		end
	end)
end

local function runTool(id: string)
	local req = Hub.Request(id, context())
	if not req then
		return
	end
	local reason = Hub.ToolDisabled(id, context(), player.Name, selfOnly())
	if reason then
		pending = nil
		setStatus(false, reason)
		render(nil)
		return
	end
	local needsTwo = Hub.NeedsConfirmFor(id, req, access.tester)
	local tool = Hub.Tool(id)
	local prompt = "Press again within a few seconds to confirm: " .. (if tool then tool.label else id) .. "."
	if id == "delegate" and req.role == "TESTER" then
		prompt = AdminLogic.TesterWarning .. " Press again to confirm."
	elseif (id == "paidgive" or id == "paidrevoke") and tool then
		local item = paidItem(state.paidId)
		prompt = string.format(
			"%s %s %s %s? Press again to confirm.",
			if id == "paidgive" then "Give" else "Take back",
			if item then item.name else "this",
			if id == "paidgive" then "to" else "from",
			currentWho() or "them"
		)
	end
	armOrFire(id, toolKey(id), needsTwo, prompt, function()
		if id == "gift" and state.item then
			state.recents = Hub.PushRecent(state.recents, state.item)
		end
		if tool and tool.needsPlayer and req.target then
			state.recentPlayers = Hub.PushName(state.recentPlayers, req.target)
		end
		if (id == "paidgive" or id == "paidrevoke") and state.paidId then
			state.paidRecents = Hub.PushPaidRecent(state.paidRecents, state.paidId)
		end
		if needsTwo then
			req.confirmed = true -- "I pressed twice": the server asks for it from a TESTER, never as a permission
		end
		setStatus(nil, "Sending...")
		send(req)
		render(nil)
	end)
end

-- Asks the server what the picked player owns (the Paid items tab), at most
-- every couple of seconds per player. The answer arrives as a "paidstate".
local function askPaid(force: boolean?)
	if not allowedNow("paidlist") then
		return
	end
	local who = currentWho()
	if not who or (selfOnly() and who ~= player.Name) then
		return -- a Gifts delegate reads only their own
	end
	local now = os.clock()
	local last = paidAskedAt[who]
	if not force and last and now - last < 2 then
		return
	end
	paidAskedAt[who] = now
	send({ action = "paidlist", target = who })
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

local function hintLabel(parent: Instance, text: string): TextLabel
	local h = UITheme.label(parent, text, UITheme.Fonts.Body, Hub.HintSize(device()), C.Bark)
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

-- One tool: a full-width button with its hint under it. When the tool can't
-- go right now, the button is dim and the reason is under it (pressing it
-- shows the same reason in the strip).
local function toolBlock(toolId: string, labelOverride: string?)
	local tool = Hub.Tool(toolId)
	if not tool or not allowedNow(toolId) then
		return
	end
	local f = container(nil)
	UITheme.list(f, 4)
	local text = labelOverride or tool.label
	local armed = pending ~= nil and pending.key == toolKey(toolId) and Hub.StillPending(pending, os.clock())
	if armed then
		text = if toolId == "delegate" then "SURE? GIVE FULL POWER" else Hub.SureText(toolId, currentWho())
	end
	local why = if armed then nil else Hub.ToolDisabled(toolId, context(), player.Name, selfOnly())
	local style = tool.style
	if armed then
		style = "amber"
	elseif why then
		style = "skip"
	end
	local b = makeButton(f, "tool_" .. toolId, text, style, UDim2.new(1, 0, 0, rh()), function()
		runTool(toolId)
	end)
	b.root.LayoutOrder = 1
	if why then
		b.face.TextTransparency = 0.45
	end
	local line = hintLabel(f, tool.hint)
	line.LayoutOrder = 2
	if why then
		local reason = hintLabel(f, "Can't yet: " .. why)
		reason.TextColor3 = C.Danger
		reason.LayoutOrder = 3
	end
	f.Parent = body
	table.insert(rows, { "tool_" .. toolId })
end

-- caption  < value >
local function stepper(id: string, caption: string, value: string, onStep: (number) -> ())
	local f = container(rh())
	UITheme.list(f, L.Gap, true)
	local cap = UITheme.label(f, caption, UITheme.Fonts.Black, 15, C.Ink)
	cap.Size = UDim2.new(0, 64, 1, -3)
	cap.LayoutOrder = 1
	local left = makeButton(f, id .. "_prev", "‹", "bark", UDim2.fromOffset(L.Chip + 8, rh()), function()
		onStep(-1)
	end)
	left.root.LayoutOrder = 2
	local v = UITheme.label(f, value, UITheme.Fonts.Heading, 18, C.Ink)
	v.Size = UDim2.new(1, -(64 + 2 * (L.Chip + 8) + 3 * L.Gap), 1, -3)
	v.TextXAlignment = Enum.TextXAlignment.Center
	v.TextTruncate = Enum.TextTruncate.AtEnd
	v.LayoutOrder = 3
	local right = makeButton(f, id .. "_next", "›", "bark", UDim2.fromOffset(L.Chip + 8, rh()), function()
		onStep(1)
	end)
	right.root.LayoutOrder = 4
	f.Parent = body
	table.insert(rows, { id .. "_prev", id .. "_next" })
end

-- The width the panel has, in the units the layout uses (the screen's scale removed).
local function panelWidth(): number
	local p = panel
	if not p then
		return L.PanelMaxW
	end
	local ui = p:FindFirstAncestorOfClass("ScreenGui")
	local scaleObj = if ui then ui:FindFirstChildOfClass("UIScale") else nil
	local scale = if scaleObj and scaleObj.Scale > 0 then scaleObj.Scale else 1
	local w = p.AbsoluteSize.X / scale
	return if w > 0 then w else L.PanelMaxW
end

-- A row of choices; the chosen one is green. On a narrow panel a long row
-- wraps onto a second line instead of scrolling sideways.
local function chips(prefix: string, labels: { string }, selected: number, onPick: (number) -> ())
	local n = #labels
	local cols = Hub.TabColumns(panelWidth(), n)
	local nrows = math.ceil(n / cols)
	local chipH = L.Chip + 3
	local f = container(nrows * chipH + (nrows - 1) * L.Gap)
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellSize = UDim2.new(1 / cols, -math.ceil(L.Gap * (cols - 1) / cols), 0, chipH)
	grid.CellPadding = UDim2.fromOffset(L.Gap, L.Gap)
	grid.Parent = f
	local lines: { { string } } = {}
	for i, label in ipairs(labels) do
		local id = prefix .. i
		local b = makeButton(
			f,
			id,
			label,
			if i == selected then "buy" else "skip",
			UDim2.fromOffset(60, chipH),
			function()
				onPick(i)
			end
		)
		b.root.LayoutOrder = i
		local line = math.ceil(i / cols)
		lines[line] = lines[line] or {}
		table.insert(lines[line], id)
	end
	f.Parent = body
	for _, ids in ipairs(lines) do
		table.insert(rows, ids)
	end
end

local function textBox(id: string, placeholder: string, text: string, onChanged: (string) -> ()): TextBox
	local f = container(Hub.RowHeight(device()))
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

-- A list that re-draws itself while its search box is being typed in (the
-- box itself is not rebuilt, so it keeps the keyboard). `build` draws the
-- rows into `holder` and calls `add` with the ids of each row of buttons.
local function liveList(build: (holder: Frame, add: ({ string }) -> ()) -> ())
	local holder = container(nil)
	UITheme.list(holder, 6)
	holder.Parent = body
	local startIndex = #rows + 1
	local count = 0
	local function refill()
		for _, child in ipairs(holder:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		for _ = 1, count do
			table.remove(rows, startIndex)
		end
		count = 0
		local at = startIndex
		build(holder, function(ids: { string })
			table.insert(rows, at, ids)
			at += 1
			count += 1
		end)
		applyNav()
	end
	refill()
	return refill
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

local function pickPlayer(name: string)
	state.who = name
	state.recentPlayers = Hub.PushName(state.recentPlayers, name)
	pending = nil
end

local function playersTab()
	section(
		"PLAYERS ON THIS SERVER",
		"Tap a name to pick them. The pick is kept on every tab. Recent picks come first."
	)
	local refill: (() -> ())? = nil
	textBox("search_players", "Find a player", state.playerQuery, function(text)
		state.playerQuery = text
		local fn = refill
		if fn then
			fn()
		end
	end)
	refill = liveList(function(holder, add)
		local list = Hub.PlayerList(names(), player.Name, state.recentPlayers, state.playerQuery)
		if #list == 0 then
			hintLabel(holder, "Nobody here matches. Clear the search.").LayoutOrder = 1
		end
		for i, entry in ipairs(list) do
			local id = "player" .. i
			local name = entry.name
			local picked = name == state.who
			local label = (if entry.recent then "★ " else "")
				.. name
				.. (if name == player.Name then " (you)" else "")
			local b = makeButton(
				holder,
				id,
				(if picked then "✓ " else "") .. label,
				if picked then "buy" else "skip",
				UDim2.new(1, 0, 0, rh()),
				function()
					pickPlayer(name)
					render(id)
				end
			)
			b.root.LayoutOrder = i
			add({ id })
		end
	end)
	local actionIds = { "goto", "bring", "heal", "freeze", "stats", "resettutorial" }
	if anyAllowed(actionIds) then
		section("ACTIONS ON " .. string.upper(state.who or "NOBODY"))
		for _, id in ipairs(actionIds) do
			toolBlock(id)
		end
	end
	if anyAllowed({ "superrun", "god", "tospawn" }) then
		section("ON YOURSELF", "These only change you.")
		toolBlock("superrun")
		toolBlock("god")
		toolBlock("tospawn")
	end
	if anyAllowed({ "kick", "ban", "unban" }) then
		section("DANGEROUS", "These need a second press.")
	end
	toolBlock("kick")
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
	if allowedNow("unban") then
		section("UNBAN", "Their numeric UserId (it is in the ban line in Output, or on their Roblox profile link).")
		textBox("unban_id", "UserId to unban", state.unban, function(text)
			state.unban = string.match(text, "^%s*(.-)%s*$") or ""
			pending = nil
		end)
		toolBlock("unban")
	end
end

local function giftsTab()
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
	section("FREE ITEMS", "Pick a type, search, pick an item, then press GIFT. Items you gave lately come first.")
	stepper("kind", "TYPE", state.category, function(d)
		state.category = Hub.NextCategory(state.category, d)
		render("kind_" .. (if d < 0 then "prev" else "next"))
	end)
	local refill: (() -> ())? = nil
	textBox("search_items", "Search items", state.query, function(text)
		state.query = text
		local fn = refill
		if fn then
			fn()
		end
	end)
	local item = state.item
	toolBlock("gift", if item then "GIFT: " .. string.upper(item.name) else nil)
	refill = liveList(function(holder, add)
		local found = Hub.Filter(allItems(), state.query, state.category, state.recents)
		local nRecent = 0
		if state.category == "All" and state.query == "" then
			found, nRecent = Hub.RecentsFirst(found, state.recents)
		end
		local shown, more = Hub.Limit(found, L.MaxListRows)
		if #shown == 0 then
			hintLabel(
				holder,
				if state.category == "Recent"
					then "Nothing gifted yet this session."
					else "No items match. Clear the search or change the type."
			).LayoutOrder =
				1
		end
		for i, entry in ipairs(shown) do
			local picked = state.item ~= nil and state.item.id == entry.id and state.item.kind == entry.kind
			local id = "item" .. i
			local b = makeButton(
				holder,
				id,
				(if picked then "✓ " elseif i <= nRecent then "★ " else "")
					.. entry.name
					.. "  ("
					.. entry.kind
					.. ")",
				if picked then "buy" else "skip",
				UDim2.new(1, 0, 0, rh()),
				function()
					state.item = entry
					setStatus(nil, "Picked " .. entry.name .. ". Press GIFT to hand it over.")
					render(id)
				end
			)
			b.root.LayoutOrder = i + 1
			add({ id })
		end
		if more > 0 then
			hintLabel(holder, string.format("%d more. Type in the search box to narrow it down.", more)).LayoutOrder = #shown
				+ 2
		end
	end)
end

-- The detail of one paid item: what it is, what the picked player owns of
-- it, and the two buttons. B (back) returns to the list.
local function paidDetail(item: PaidItems.Item)
	local who = currentWho()
	local row = if paidState.target == who then paidState.rows[item.id] else nil
	section(
		string.upper(item.name),
		(PaidItems.KindLabels[item.kind] or item.kind) .. (if item.forSale then "" else "  |  OFF SALE in the store")
	)
	local owns = hintLabel(
		body :: ScrollingFrame,
		(who or "Nobody")
			.. ": "
			.. (if type(row) == "table" and type(row.label) == "string" then row.label else "loading...")
	)
	owns.Font = UITheme.Fonts.Bold
	owns.TextColor3 = if type(row) == "table" and row.owned == true then C.Money else C.Ink
	owns.TextSize = 16
	owns.LayoutOrder = nextOrder()
	local what = hintLabel(body :: ScrollingFrame, item.description)
	what.LayoutOrder = nextOrder()
	local how = hintLabel(body :: ScrollingFrame, "How it is given: " .. item.how)
	how.LayoutOrder = nextOrder()
	if item.effect == "boost" then
		section("BOOST LENGTH", "How long it runs. A purchase gives " .. tostring(item.hours or 0) .. " hours.")
		local labels: { string } = {}
		for _, h in ipairs(PaidItems.HourChoices) do
			table.insert(labels, if h % 24 == 0 then string.format("%d DAYS", h / 24) else string.format("%d HOUR", h))
		end
		chips("hours", labels, state.paidHourIndex, function(i)
			state.paidHourIndex = i
			pending = nil
			render("hours" .. i)
		end)
	end
	local giveWhy = Hub.PaidDisabled(item, row, who, player.Name, false, selfOnly())
	local revokeWhy = Hub.PaidDisabled(item, row, who, player.Name, true, selfOnly())
	local function block(id: string, label: string, why: string?, hint: string)
		if not allowedNow(id) then
			return
		end
		local f = container(nil)
		UITheme.list(f, 4)
		local armed = pending ~= nil and pending.key == toolKey(id) and Hub.StillPending(pending, os.clock())
		local text = if armed then "SURE? " .. label else label
		local tool = Hub.Tool(id)
		local style = if armed then "amber" elseif why then "skip" elseif tool then tool.style else "skip"
		local b = makeButton(f, "tool_" .. id, text, style, UDim2.new(1, 0, 0, rh()), function()
			if why then
				pending = nil
				setStatus(false, why)
				render(nil)
			else
				runTool(id)
			end
		end)
		b.root.LayoutOrder = 1
		if why and not armed then
			b.face.TextTransparency = 0.45
		end
		hintLabel(f, hint).LayoutOrder = 2
		if why and not armed then
			local reason = hintLabel(f, "Can't yet: " .. why)
			reason.TextColor3 = C.Danger
			reason.LayoutOrder = 3
		end
		f.Parent = body
		table.insert(rows, { "tool_" .. id })
	end
	local target = (who or "nobody")
	block(
		"paidgive",
		"GIVE " .. string.upper(item.name) .. " TO " .. string.upper(target),
		giveWhy,
		"Needs a second press."
	)
	block("paidrevoke", "REVOKE FROM " .. string.upper(target), revokeWhy, item.revokeHow)
	local back = container(rh())
	makeButton(back, "paid_back", "BACK TO THE LIST", "bark", UDim2.fromScale(1, 1), function()
		state.paidId = nil
		pending = nil
		render("search_paid")
	end)
	back.Parent = body
	table.insert(rows, { "paid_back" })
end

local function paidTab()
	if not allowedNow("paidgive") then
		return
	end
	askPaid(false)
	local item = paidItem(state.paidId)
	if state.paidId ~= nil and item == nil then
		state.paidId = nil -- it left the store data
	end
	if item then
		paidDetail(item)
		return
	end
	local who = currentWho() or "nobody"
	section(
		"WHAT " .. string.upper(who) .. " OWNS",
		"Every item the Robux store sells, from the store data: a new item shows up here by itself. Tap one to give it or take it back. Recent items come first."
	)
	local refill: (() -> ())? = nil
	textBox("search_paid", "Find a paid item", state.paidQuery, function(text)
		state.paidQuery = text
		local fn = refill
		if fn then
			fn()
		end
	end)
	refill = liveList(function(holder, add)
		local list, nRecent = Hub.PaidList(paidItems(), state.paidQuery, state.paidRecents)
		if #list == 0 then
			hintLabel(holder, "No paid item matches. Clear the search.").LayoutOrder = 1
		end
		local theirs = if paidState.target == currentWho() then paidState.rows else {}
		for i, entry in ipairs(list) do
			local id = "paiditem" .. i
			local row = theirs[entry.id]
			local label = if type(row) == "table" and type(row.label) == "string" then row.label else "..."
			local owned = type(row) == "table" and row.owned == true
			local b = makeButton(
				holder,
				id,
				(if i <= nRecent then "★ " else "") .. entry.name .. "  |  " .. label,
				if owned then "buy" else "skip",
				UDim2.new(1, 0, 0, rh()),
				function()
					state.paidId = entry.id
					state.paidRecents = Hub.PushPaidRecent(state.paidRecents, entry.id)
					pending = nil
					render("tool_paidgive")
				end
			)
			b.root.LayoutOrder = i
			add({ id })
		end
	end)
	toolBlock("paidlist")
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
			local f = container(rh())
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

-- Whether a chat command line (AdminLogic.Help) is one this viewer may run.
local function commandShown(line: string): boolean
	if access.allowed == nil then
		return true
	end
	local name = string.match(line, "^/(%a+)")
	return name == "admin" or (name ~= nil and access.allowed[name] == true)
end

local function logTab()
	-- The owner's list: what they did, and what their delegates did.
	section("LAST ACTIONS", "Newest first. The server also logs each one with both ids in Output.")
	local audit = UITheme.label(body :: ScrollingFrame, table.concat(state.audit, "\n"), UITheme.Fonts.Body, 14, C.Ink)
	audit.Size = UDim2.fromScale(1, 0)
	audit.AutomaticSize = Enum.AutomaticSize.Y
	audit.TextWrapped = true
	audit.LayoutOrder = nextOrder()
	if #state.audit == 0 then
		audit.Text = "Nothing yet."
	end
	auditLabel = audit
	section("CHAT COMMANDS", "Type /admin in chat for the same list. Search to narrow it.")
	local refill: (() -> ())? = nil
	textBox("search_cmds", "Find a command", state.cmdQuery, function(text)
		state.cmdQuery = text
		local fn = refill
		if fn then
			fn()
		end
	end)
	refill = liveList(function(holder, _add)
		local shown: { string } = {}
		for _, line in ipairs(AdminLogic.Help) do
			if commandShown(line) then
				table.insert(shown, line)
			end
		end
		local found = Hub.FilterLines(shown, state.cmdQuery)
		if #found == 0 then
			hintLabel(holder, "No command matches.").LayoutOrder = 1
		end
		for i, line in ipairs(found) do
			local label = hintLabel(holder, line)
			label.LayoutOrder = i
			label.TextColor3 = C.Ink
		end
	end)
end

local function delegateRow(i: number, row: { [string]: any })
	local id = "revoke" .. i
	local f = container(rh())
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
	info.Size = UDim2.new(1, -(130 + L.Gap), 1, -3)
	info.TextWrapped = true
	info.LayoutOrder = 1
	local key = "undelegate:" .. tostring(row.name)
	local armed = pending ~= nil and pending.key == key and Hub.StillPending(pending, os.clock())
	local b = makeButton(
		f,
		id,
		if armed then "SURE?" else "REVOKE",
		if armed then "amber" else "skip",
		UDim2.fromOffset(130, rh()),
		function()
			armOrFire(
				"undelegate",
				key,
				true,
				"Press again within a few seconds to take every power back from " .. tostring(row.name) .. ".",
				function()
					setStatus(nil, "Sending...")
					send({ action = "undelegate", target = tostring(row.name) })
					render(nil)
				end
			)
		end
	)
	b.root.LayoutOrder = 2
	f.Parent = body
	table.insert(rows, { id })
end

local function rolesTab()
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
			"Tick what they may do. Cash, shutdown, super run, saves, revoking paid items and delegation are never on this list."
		)
		for _, power in ipairs(AdminLogic.DelegablePowers) do
			local id = "power_" .. power
			local on = state.powers[power] == true
			local f = container(nil)
			UITheme.list(f, 2)
			local b = makeButton(
				f,
				id,
				(if on then "✓ " else "") .. (Hub.PowerLabels[power] or power),
				if on then "buy" else "skip",
				UDim2.new(1, 0, 0, rh()),
				function()
					state.powers[power] = (if on then nil else true) :: any
					pending = nil
					render(id)
				end
			)
			b.root.LayoutOrder = 1
			local help = Hub.PowerHelp[power]
			if help then
				hintLabel(f, help).LayoutOrder = 2
			end
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
	section("CURRENT DELEGATES", "Tap REVOKE twice to take every power back at once.")
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

-- Sizes the tab block (one or two rows, by the panel's width) and puts the
-- scrolling body under it.
local function relayout()
	local tabs, scroll, p = tabsFrame, body, panel
	if not tabs or not scroll or not p then
		return
	end
	local count = #visibleTabs()
	local cols = Hub.TabColumns(panelWidth(), count)
	local nrows = Hub.TabRows(panelWidth(), count)
	local tabH = if device() == "console" then Hub.RowHeight("console") - 8 else L.TabHeight
	local grid = tabs:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.new(1 / cols, -math.ceil(L.Gap * (cols - 1) / cols), 0, tabH + 3)
	end
	local tabsTop = 8 + L.Row + L.Gap + 30 + L.Gap
	local tabsH = nrows * (tabH + 3) + (nrows - 1) * L.Gap
	tabs.Position = UDim2.fromOffset(L.Pad, tabsTop)
	tabs.Size = UDim2.new(1, -2 * L.Pad, 0, tabsH)
	local top = tabsTop + tabsH + L.Gap
	scroll.Position = UDim2.fromOffset(L.Pad, top)
	scroll.Size = UDim2.new(1, -2 * L.Pad, 1, -(top + 60 + 16))
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
		end
		button:SetStyle(if def.id == tab.id and state.toolQuery == "" then "amber" else "bark")
	end
	-- Tab ids for the pad, one list per row of tabs (two rows on a phone).
	local cols = Hub.TabColumns(panelWidth(), #tabIds)
	local tabRows: { { string } } = {}
	for i, id in ipairs(tabIds) do
		local line = math.ceil(i / cols)
		tabRows[line] = tabRows[line] or {}
		table.insert(tabRows[line], id)
	end
	headerRows = { { "search", "close" } }
	for _, line in ipairs(tabRows) do
		table.insert(headerRows, line)
	end
	relayout()
	paintWho()
	if state.toolQuery ~= "" then
		playerBar()
		searchResults()
	else
		if tab.id ~= "world" and tab.id ~= "log" then
			playerBar()
		end
		if tab.id == "players" then
			playersTab()
		elseif tab.id == "gifts" then
			giftsTab()
		elseif tab.id == "paid" then
			paidTab()
		elseif tab.id == "world" then
			worldTab()
		elseif tab.id == "roles" then
			rolesTab()
		else
			logTab()
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
	if id ~= "paid" then
		state.paidId = nil
	end
	local searchBox = objById["search"]
	if searchBox and searchBox:IsA("TextBox") then
		searchBox.Text = ""
	end
	-- A delegate's Gifts power is for themself: start on themself.
	if id == "paid" and selfOnly() then
		state.who = player.Name
	end
	render(nil)
	local b = body
	if b then
		b.CanvasPosition = Vector2.new(0, 0)
	end
	if id == "roles" and access.allowed == nil then
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

local setOpen: (boolean) -> ()

-- The filter of the list on the tab in front (what B clears first).
local function activeListQuery(): string?
	local id = state.tabId
	if id == "players" then
		return state.playerQuery
	elseif id == "gifts" then
		return state.query
	elseif id == "paid" then
		return state.paidQuery
	elseif id == "log" then
		return state.cmdQuery
	end
	return nil
end

-- B / Esc: one level back; close only when there is none left.
local function goBack()
	local armed = pending ~= nil and Hub.StillPending(pending, os.clock())
	local step = Hub.Back({
		pending = armed,
		toolQuery = state.toolQuery,
		detail = if state.tabId == "paid" then state.paidId else nil,
		listQuery = activeListQuery(),
	})
	if step == "cancel" then
		pending = nil
		setStatus(nil, "Cancelled. Nothing was done.")
		render(nil)
	elseif step == "clearSearch" then
		local box = objById["search"]
		state.toolQuery = ""
		if box and box:IsA("TextBox") then
			box.Text = ""
		end
		render(nil)
	elseif step == "leaveDetail" then
		state.paidId = nil
		render("search_paid")
	elseif step == "clearFilter" then
		local id = state.tabId
		if id == "players" then
			state.playerQuery = ""
		elseif id == "gifts" then
			state.query = ""
		elseif id == "paid" then
			state.paidQuery = ""
		elseif id == "log" then
			state.cmdQuery = ""
		end
		render(nil)
	else
		setOpen(false)
	end
end

setOpen = function(on: boolean)
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
		goBack()
		return Enum.ContextActionResult.Sink
	end, false, priority, InputKit.Actions.Cancel.keyboard, InputKit.Actions.Cancel.gamepad)
	ContextActionService:BindActionAtPriority(TAB_PREV, function(_name, inputState)
		if inputState == Enum.UserInputState.Begin then
			stepTab(-1)
		end
		return Enum.ContextActionResult.Sink
	end, false, priority, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority(TAB_NEXT, function(_name, inputState)
		if inputState == Enum.UserInputState.Begin then
			stepTab(1)
		end
		return Enum.ContextActionResult.Sink
	end, false, priority, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonR2)
	if UITheme.Device() == "console" then
		MenuPad.Open(objById[headerRows[2][1] or "close"], p)
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

	-- Who you are: stays put whatever tab is open.
	local who = Instance.new("Frame")
	who.Name = "Who"
	who.Position = UDim2.fromOffset(L.Pad, 8 + L.Row + L.Gap)
	who.Size = UDim2.new(1, -2 * L.Pad, 0, 30)
	who.BackgroundColor3 = C.PaperDark
	who.BorderSizePixel = 0
	UITheme.corner(who, 8)
	UITheme.padding(who, 0, 10, 0, 10)
	who.Parent = outer
	whoStrip = who
	local whoText = UITheme.label(who, "", UITheme.Fonts.Black, 15, C.Ink)
	whoText.Size = UDim2.fromScale(1, 1)
	whoText.TextTruncate = Enum.TextTruncate.AtEnd
	whoLabel = whoText

	-- Tabs: one row on a roomy panel, two on a phone.
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(L.Pad, 8 + L.Row + L.Gap + 30 + L.Gap)
	tabs.Size = UDim2.new(1, -2 * L.Pad, 0, L.TabHeight + 3)
	tabs.Parent = outer
	local tabGrid = Instance.new("UIGridLayout")
	tabGrid.SortOrder = Enum.SortOrder.LayoutOrder
	tabGrid.CellSize = UDim2.new(1 / #Hub.Tabs, 0, 0, L.TabHeight + 3)
	tabGrid.CellPadding = UDim2.fromOffset(L.Gap, L.Gap)
	tabGrid.Parent = tabs
	tabsFrame = tabs
	for i, tab in ipairs(Hub.Tabs) do
		local b = UITheme.Button({
			text = tab.label,
			size = Vector2.new(60, L.TabHeight),
			style = "bark",
			textSize = 15,
			name = "Tab" .. tab.id,
		})
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

	-- The scrolling body; the pad's selection scrolls it along. Its place
	-- under the tabs is set by relayout().
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(L.Pad, 120)
	scroll.Size = UDim2.new(1, -2 * L.Pad, 1, -200)
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

	-- A rotated phone or a resized window can change the tab rows.
	outer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if outer.Visible then
			render(nil)
		end
	end)

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
-- owner's list of delegates, a delegate's grant, the audit lines, what a
-- player owns of the paid items, or the end of a grant (the hub closes at
-- once). It only shapes the UI; every request is re-checked on the server.
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
	paintWho()
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
	if p.kind == "paidstate" then
		if type(p.target) == "string" and type(p.rows) == "table" then
			paidState = { target = p.target, rows = p.rows }
			local panelNow = panel
			if panelNow and panelNow.Visible and state.tabId == "paid" then
				render(nil)
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
