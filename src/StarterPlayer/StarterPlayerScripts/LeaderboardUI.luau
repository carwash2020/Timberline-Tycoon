--!strict
-- LeaderboardUI: the "Leaderboard" tab of the Settings card (SettingsUI
-- owns the card, the tabs and B; this builds what is inside the tab).
--
--   * An opt-in toggle ("Show me on the leaderboard", off by default; it
--     saves through SaveSetting like the other settings).
--   * The top ten (rank, name, "$ earned"), then your own row if you are
--     opted in. Or a state line: loading, "No one is on the board yet", or
--     "Couldn't load the board. Try again soon."
--   * A Refresh button. Every press is a request, but the client asks the
--     server at most once per ten seconds (the server answers from its
--     cache), so Refresh when it is too soon just redraws.
--
-- Pad: the toggle, Refresh and every row are selectable, linked top to
-- bottom with NextSelection (LinkChain), so the D-pad walks the list and
-- the card scrolls to follow. Text is 18 px on a TV, buttons a fingertip
-- tall. Nothing depends on hover. The client sends no score; it only asks.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardLogic = require(ReplicatedStorage.Shared.LeaderboardLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local UITheme = require(script.Parent.UITheme)

local LeaderboardUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local ANSWER_WAIT = 8 -- seconds with no answer before the tab says it failed
local ASK_MARGIN = 1 -- the server counts ten seconds from when the ask arrives; stay clear of that edge
local NAME_WIDTH_RANK = 34

-- Links each button to the next one down (and back up), in order. The
-- first has no Up and the last no Down, so the pad stops at the ends.
function LeaderboardUI.LinkChain(chain: { GuiObject })
	for i, button in ipairs(chain) do
		button.NextSelectionUp = chain[i - 1]
		button.NextSelectionDown = chain[i + 1]
	end
end

local function tenFoot(): boolean
	local ok, ten = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and ten == true
end

export type Panel = {
	root: Frame,
	toggle: UITheme.Button,
	refresh: UITheme.Button,
	rows: { TextButton },
	meRow: TextButton,
	status: TextLabel,
	Show: (self: Panel) -> (),
	Render: (self: Panel, payload: LeaderboardLogic.Payload?) -> (),
	SetOptIn: (self: Panel, on: boolean) -> (),
	Receive: (self: Panel, raw: unknown) -> (),
	Chain: (self: Panel) -> { GuiObject },
	Link: (self: Panel, above: GuiObject?) -> (),
	First: (self: Panel) -> GuiObject,
}

-- Builds the tab's content in `parent` (the card's scroll list: it sits at
-- LayoutOrder `order`, is hidden until Show). `isOn()` says whether you
-- are opted in; `setOn(bool)` saves the choice. `ask` (default: fire
-- BoardRequest) sends the request, so the specs can fake it.
function LeaderboardUI.Build(
	parent: Instance,
	order: number,
	isOn: () -> boolean,
	setOn: (boolean) -> (),
	ask: (() -> ())?
): Panel
	local ten = tenFoot()
	local textPx = LeaderboardLogic.TextPx(ten)
	local rowH = LeaderboardLogic.RowHeight(ten)
	local buttonH = LeaderboardLogic.ButtonHeight(ten)

	local root = Instance.new("Frame")
	root.Name = "Board"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.LayoutOrder = order
	root.Visible = false
	UITheme.list(root, 6)
	root.Parent = parent

	local order_ = 0
	local function nextOrder(): number
		order_ += 1
		return order_
	end

	local function button(name: string, text: string, style: string, height: number, onPress: () -> ()): UITheme.Button
		local b = UITheme.Button({
			name = name,
			text = text,
			size = Vector2.new(170, height),
			style = style,
			textSize = textPx,
		})
		b.root.Size = UDim2.new(1, 0, 0, height + 3)
		b.root.LayoutOrder = nextOrder()
		b.root.Parent = root
		b.face.Activated:Connect(onPress)
		return b
	end

	local heading = UITheme.label(root, string.upper(LeaderboardLogic.Title), F.Black, textPx, C.Bark)
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, 0, 0, rowH)
	heading.LayoutOrder = nextOrder()

	local toggle: UITheme.Button
	toggle = button("OptIn", LeaderboardLogic.ToggleText, "skip", buttonH + 8, function()
		setOn(not isOn())
	end)

	local note = UITheme.label(root, "Everyone can see your name and lifetime earnings.", F.Bold, textPx, C.Ink)
	note.Name = "Note"
	note.Size = UDim2.fromScale(1, 0)
	note.AutomaticSize = Enum.AutomaticSize.Y
	note.TextWrapped = true
	note.LayoutOrder = nextOrder()

	local refresh = button("Refresh", "REFRESH", "bark", buttonH, function() end)

	local status = UITheme.label(root, LeaderboardLogic.LoadingText, F.Bold, textPx, C.Ink)
	status.Name = "Status"
	status.Size = UDim2.fromScale(1, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.TextWrapped = true
	status.LayoutOrder = nextOrder()

	-- A row is a selectable button (so the pad can walk the list and the
	-- card scrolls with it); pressing it does nothing.
	local cashW = if ten then 130 else 104
	local function makeRow(name: string): TextButton
		local row = Instance.new("TextButton")
		row.Name = name
		row.AutoButtonColor = false
		row.Text = ""
		row.BorderSizePixel = 0
		row.BackgroundColor3 = C.PaperDark
		row.BackgroundTransparency = 0.4
		row.Size = UDim2.new(1, 0, 0, rowH)
		row.Selectable = true
		row.LayoutOrder = nextOrder()
		row.Visible = false
		UITheme.corner(row, 6)
		local rank = UITheme.label(row, "", F.Black, textPx, C.Bark)
		rank.Name = "Rank"
		rank.Size = UDim2.new(0, NAME_WIDTH_RANK, 1, 0)
		rank.Position = UDim2.fromOffset(4, 0)
		local who = UITheme.label(row, "", F.Bold, textPx, C.Ink)
		who.Name = "Name"
		who.Position = UDim2.fromOffset(NAME_WIDTH_RANK + 4, 0)
		who.Size = UDim2.new(1, -(NAME_WIDTH_RANK + cashW + 8), 1, 0)
		who.TextTruncate = Enum.TextTruncate.AtEnd
		local cash = UITheme.label(row, "", F.Black, textPx, C.Ink)
		cash.Name = "Cash"
		cash.AnchorPoint = Vector2.new(1, 0)
		cash.Position = UDim2.new(1, -4, 0, 0)
		cash.Size = UDim2.new(0, cashW, 1, 0)
		cash.TextXAlignment = Enum.TextXAlignment.Right
		row.Parent = root
		return row
	end

	local rows: { TextButton } = {}
	for i = 1, LeaderboardLogic.Size do
		rows[i] = makeRow("Row" .. i)
	end
	local meRow = makeRow("You")
	meRow.BackgroundColor3 = C.Amber
	meRow.BackgroundTransparency = 0.2

	local function fill(row: TextButton, text: LeaderboardLogic.RowText)
		(row:FindFirstChild("Rank") :: TextLabel).Text = text.rank;
		(row:FindFirstChild("Name") :: TextLabel).Text = text.name;
		(row:FindFirstChild("Cash") :: TextLabel).Text = text.cash
	end

	local panel: Panel = {
		root = root,
		toggle = toggle,
		refresh = refresh,
		rows = rows,
		meRow = meRow,
		status = status,
		Show = function(_self: Panel) end,
		Render = function(_self: Panel, _payload: LeaderboardLogic.Payload?) end,
		SetOptIn = function(_self: Panel, _on: boolean) end,
		Receive = function(_self: Panel, _raw: unknown) end,
		Chain = function(_self: Panel): { GuiObject }
			local chain: { GuiObject } = { toggle.face, refresh.face }
			for _, row in ipairs(rows) do
				if row.Visible then
					table.insert(chain, row)
				end
			end
			if meRow.Visible then
				table.insert(chain, meRow)
			end
			return chain
		end,
		Link = function(_self: Panel, _above: GuiObject?) end,
		First = function(_self: Panel): GuiObject
			return toggle.face
		end,
	}

	local above: GuiObject? = nil
	local payload: LeaderboardLogic.Payload? = nil
	local lastAskAt: number? = nil
	local waiting = false

	function panel.Link(self: Panel, tab: GuiObject?)
		above = tab
		if not root.Visible then
			-- Hidden: the tab must not point down at buttons nobody can reach.
			if tab then
				(tab :: any).NextSelectionDown = nil
			end
			return
		end
		local chain = self:Chain()
		if tab then
			table.insert(chain, 1, tab)
		end
		LeaderboardUI.LinkChain(chain)
	end

	function panel.SetOptIn(self: Panel, on: boolean)
		toggle:SetStyle(if on then "buy" else "skip")
		toggle:SetText(LeaderboardLogic.ToggleText .. (if on then ": ON" else ": OFF"))
		self:Render(payload)
	end

	function panel.Render(self: Panel, data: LeaderboardLogic.Payload?)
		payload = data
		local state = LeaderboardLogic.State(data)
		status.Visible = state ~= "rows"
		if state == "loading" then
			status.Text = LeaderboardLogic.LoadingText
		elseif state == "failed" then
			status.Text = LeaderboardLogic.FailedText
		elseif state == "empty" then
			status.Text = LeaderboardLogic.EmptyText
		end
		local list = if data and state == "rows" then data.rows else {}
		for i, row in ipairs(rows) do
			local entry = list[i]
			row.Visible = entry ~= nil
			if entry then
				fill(row, LeaderboardLogic.FormatRow(entry.rank, entry.name, entry.score))
			end
		end
		local me = if data and data.ok and isOn() then data.me else nil
		meRow.Visible = me ~= nil
		if me then
			fill(meRow, LeaderboardLogic.FormatRow(me.rank, "You", me.score))
		end
		self:Link(above)
	end

	-- Asks the server unless one went out in the last ten seconds.
	local function request()
		local t = os.clock()
		if not LeaderboardLogic.ClientDue(lastAskAt, t - ASK_MARGIN) then
			panel:Render(payload) -- too soon: show what we have
			return
		end
		lastAskAt = t
		waiting = true
		if payload == nil then
			panel:Render(nil)
		end
		if ask then
			ask()
		else
			Net.Remote("BoardRequest"):FireServer()
		end
		task.delay(ANSWER_WAIT, function()
			if waiting and lastAskAt == t then
				waiting = false
				if payload == nil then
					panel:Render({ ok = false, rows = {}, me = nil })
				end
			end
		end)
	end

	refresh.face.Activated:Connect(request)

	function panel.Show(self: Panel)
		self:SetOptIn(isOn())
		request()
	end

	-- The server's answer (BoardData). Anything odd is dropped.
	function panel.Receive(self: Panel, raw: unknown)
		local parsed = LeaderboardLogic.ParsePayload(raw)
		if parsed == nil then
			return
		end
		waiting = false
		self:Render(parsed)
	end
	panel:Render(nil)
	return panel
end

-- Hooks the server's answers to the panel. Called once by SettingsUI.
function LeaderboardUI.Listen(panel: Panel)
	Net.Remote("BoardData").OnClientEvent:Connect(function(raw: unknown)
		panel:Receive(raw)
	end)
end

return LeaderboardUI
