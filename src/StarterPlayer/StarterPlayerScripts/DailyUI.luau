--!strict
-- DailyUI: Rook Calloway's job board: the day's goals, what he owes, and
-- the streak (rules in Shared/DailyData and Shared/ForemanData).
--   * NPCController opens it (DailyUI.OpenForeman) when Rook's talk box
--     closes, so the goals come from the Foreman, not a HUD button. The
--     old corner button is kept off screen (the Foreman replaces it;
--     UITheme no longer has its size). The panel has a "Take $N" button
--     that fires ForemanTurnIn: the server checks he is within reach and
--     pays what is owed once (DailyService.TurnIn).
--   * The goals still count during Murph's tutorial, quietly
--     (DailyService); Rook sends you back to Murph until it ends.
--   * It opens the day's goals (one of the corner's popups, under
--     it): progress bars, each goal's reward, the bonus for finishing them
--     all, and the time until new goals.
--   * On a gamepad, DPadUp opens and closes it too (HUD.PadShortcut), and
--     a glyph chip left of the button says so; B closes it (HUD.Popup)
--     and Esc closes it too. Opening selects Close.
-- The server owns progress: it sets the DailyGoals, DailyStreak and
-- DailyResetAt attributes, and this redraws from them.
-- Under the v2 core loop (CoreLoop.Active()) a goal's progress reads in
-- its units (DailyData.ProgressText: "(12/40 u³)", "($23/$60)") and the
-- bonus is the v2 one (DailyData.Bonus with the loop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local DailyData = require(ReplicatedStorage.Shared.DailyData)
local EventData = require(ReplicatedStorage.Shared.EventData)
local ForemanData = require(ReplicatedStorage.Shared.ForemanData)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local HudNav = require(script.Parent.HudNav)
local HudRules = require(script.Parent.HudRules)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local DailyUI = {}

local player = Players.LocalPlayer
local goalsOpen = false
local foremanMode = false -- opened at Rook: the Take button shows
local focus: GuiObject? = nil

local INK = UITheme.Colors.Ink
local CREAM = UITheme.Colors.Cream
local PAPER = UITheme.Colors.Paper
local PAPER_DARK = UITheme.Colors.PaperDark
local BARK = UITheme.Colors.Bark
local GREEN = UITheme.Colors.Money
local AMBER = UITheme.Colors.Amber

type GoalRow = { frame: Frame, text: TextLabel, reward: TextLabel, fill: Frame }

local button: TextButton? = nil
local takeButton: TextButton? = nil -- "Take $N": hands the finished jobs in to Rook
local buttonSlot: Frame? = nil -- on a phone, what holds the button and its hit area in the corner
local panel: Frame? = nil

function DailyUI._open(first: GuiObject?)
	goalsOpen = true
	focus = first
	local card = panel
	if card then
		card.Visible = true
	end
	MenuPad.Open(first, card)
end

function DailyUI._close()
	goalsOpen = false
	foremanMode = false
	local card = panel
	if card then
		card.Visible = false
	end
	MenuPad.Close(card or focus)
	focus = nil
end

function DailyUI.ApplyKey(key: Enum.KeyCode): string?
	if not goalsOpen or not MenuPad.Closes(key) then
		return nil
	end
	DailyUI._close()
	return "close"
end

local goalRows: { GoalRow } = {}
local calendarCells: { { frame: Frame, label: TextLabel } } = {}
local calendarNote: TextLabel? = nil
local headingLabel: TextLabel? = nil
local calendarFrame: Frame? = nil -- hidden on a phone so the panel fits 375 px
local eventHeading: TextLabel? = nil -- the seasonal event's goals (EventGoals / EventInfo), hidden outside one
local eventLines: TextLabel? = nil
local footer: TextLabel? = nil
local countdown: TextLabel? = nil
local tomorrow: TextLabel? = nil -- tomorrow's first goal, greyed out

local corner = UITheme.corner

local function text(parent: Instance, content: string, size: number, font: Enum.Font, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.fromScale(1, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = INK
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = content
	l.Parent = parent
	return l
end

local function goals(): { DailyData.Goal }
	return DailyData.Decode((player:GetAttribute("DailyGoals") :: string?) or "")
end

local function streak(): number
	return (player:GetAttribute("DailyStreak") :: number?) or 0
end

local function bestAxeTier(): number
	return (player:GetAttribute("BestAxeTier") :: number?) or 1
end

local function bonusOwed(): number
	return (player:GetAttribute("DailyBonusOwed") :: number?) or 0
end

local function timeLeft(): string
	local resetAt = (player:GetAttribute("DailyResetAt") :: number?) or 0
	local seconds = math.max(0, resetAt - os.time())
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	return if hours > 0
		then string.format("New goals in %dh %02dm", hours, minutes)
		else string.format("New goals in %dm", math.max(1, minutes))
end

-- A short cash label for a calendar cell: $15, $1.2k.
local function shortCash(amount: number): string
	if amount >= 1000 then
		local short = string.gsub(string.format("$%.1fk", amount / 1000), "%.0k", "k")
		return short
	end
	return "$" .. tostring(amount)
end

-- The daily-return calendar (DailyData.LoginStep): days up to the one
-- paid today are ticked, today's is green, day 7 is the milestone.
local function refreshCalendar()
	local paidDay = (player:GetAttribute("DailyLoginDay") :: number?) or 0
	local loop = CoreLoop.Active()
	local tier = bestAxeTier()
	for day, cell in ipairs(calendarCells) do
		local reward = DailyData.LoginReward(tier, day, if loop == 2 then 2 else nil)
		local label =
			string.format("%s%d\n%s", if day == DailyData.LoginDays then "★" else "", day, shortCash(reward))
		cell.label.Text = label
		cell.frame.BackgroundColor3 = if day == paidDay
			then GREEN
			elseif day < paidDay then PAPER_DARK
			elseif day == DailyData.LoginDays then AMBER
			else PAPER
		cell.label.TextColor3 = if day == paidDay then CREAM else INK
	end
	local note = calendarNote
	if note then
		local nextDay = paidDay % DailyData.LoginDays + 1
		local nextReward = DailyData.LoginReward(tier, nextDay, if loop == 2 then 2 else nil)
		note.Text = if paidDay == 0
			then "Come back every day: the reward grows to a day-7 milestone."
			else string.format(
				"Daily return: day %d of %d paid. Tomorrow: %s%s. Miss a day and it restarts.",
				paidDay,
				DailyData.LoginDays,
				Util.formatCash(nextReward),
				if nextDay == DailyData.LoginDays then " (milestone)" else ""
			)
	end
end

-- The seasonal event (EventService): its themed goals, and how many days
-- toward the cosmetic. Hidden when no event runs.
local function refreshEvent()
	local heading, lines = eventHeading, eventLines
	if not heading or not lines then
		return
	end
	local info = (player:GetAttribute("EventInfo") :: string?) or ""
	local name, days, needed, cosmetic, owned = string.match(info, "^(.-)|(%d+)|(%d+)|(.-)|(%d)$")
	heading.Visible = name ~= nil
	lines.Visible = name ~= nil
	if not name or not days or not needed or not cosmetic then
		return
	end
	heading.Text = string.upper(name) .. " EVENT"
	local out: { string } = {}
	for _, row in ipairs(EventData.DecodeGoals((player:GetAttribute("EventGoals") :: string?) or "")) do
		table.insert(
			out,
			string.format(
				"%s%s (%d/%d)",
				if row.progress >= row.target then "✓ " else "",
				row.text,
				row.progress,
				row.target
			)
		)
	end
	table.insert(
		out,
		if owned == "1"
			then string.format("You earned the %s!", cosmetic)
			else string.format(
				"Finish both on %s days to earn the %s (%s/%s). No cash: just for fun.",
				needed,
				cosmetic,
				days,
				needed
			)
	)
	lines.Text = table.concat(out, "\n")
end

local function refresh()
	refreshCalendar()
	refreshEvent()
	local roomy = not UITheme.Compact()
	-- On a phone the panel is goals, Close and Take only (about 196 tall), so it
	-- clears the thumbstick and jump zones: no heading, countdown or tomorrow.
	for _, extra in ipairs({ headingLabel, countdown, tomorrow }) do
		if extra then
			extra.Visible = roomy
		end
	end
	for _, row in ipairs(goalRows) do
		row.frame.Size = UDim2.new(1, 0, 0, if roomy then 40 else 34)
		local bar = row.fill.Parent
		if bar and bar:IsA("GuiObject") then
			bar.Position = UDim2.fromOffset(0, if roomy then 26 else 22)
		end
	end
	local cal, note = calendarFrame, calendarNote
	if cal then
		cal.Visible = roomy
	end
	if note then
		note.Visible = roomy
	end
	local list = goals()
	local done = 0
	for _, goal in ipairs(list) do
		if goal.done then
			done += 1
		end
	end
	local b = button
	if b then
		b.Visible = false -- the Foreman's panel replaces the corner button
		local slot = buttonSlot
		if slot then
			slot.Visible = b.Visible
		end
		local p = panel
		if p and not b.Visible then
			p.Visible = false
		end
		local compact = UITheme.Compact()
		b.AutomaticSize = if compact then Enum.AutomaticSize.None else Enum.AutomaticSize.X
		if compact then
			b.Size = UDim2.fromOffset(52, 36)
			b.TextSize = UITheme.Size.TextMin
		else
			b.Size = UDim2.fromOffset(200, 30)
			b.TextSize = UITheme.Size.TextMin
		end
		local holder = buttonSlot
		if holder then
			holder.AutomaticSize = if compact then Enum.AutomaticSize.None else Enum.AutomaticSize.X
			holder.Size = if compact then UDim2.fromOffset(52, 36) else UDim2.fromOffset(0, b.Size.Y.Offset)
		end
		b.Text = if compact
			then HudRules.DailyMark(done, #list)
			else HudRules.DailyLabel(done, #list, streak(), UITheme.IsPhone())
		b.BackgroundColor3 = if done == #list and #list > 0 then GREEN else BARK
	end
	local loop = CoreLoop.Active()
	for i, row in ipairs(goalRows) do
		local goal = list[i]
		row.frame.Visible = goal ~= nil
		if goal then
			local progress = if loop == 2
				then "  " .. DailyData.ProgressText(goal)
				else string.format("  (%d/%d)", goal.progress, goal.target)
			row.text.Text = (if goal.done then "✓ " else "") .. DailyData.GoalText(goal) .. progress
			row.reward.Text = if goal.done and goal.paid ~= false then "paid" else "+" .. Util.formatCash(goal.reward)
			row.reward.TextColor3 = if goal.done and goal.paid ~= false then PAPER_DARK else GREEN
			row.fill.Size = UDim2.fromScale(math.clamp(goal.progress / math.max(1, goal.target), 0, 1), 1)
			row.fill.BackgroundColor3 = if goal.done then GREEN else AMBER
		end
	end
	local owed = ForemanData.Owed(list, bonusOwed())
	local take = takeButton
	if take then
		take.Visible = owed > 0 and foremanMode
		take.Text = "Take " .. Util.formatCash(owed)
	end
	local f = footer
	if f then
		local allDone = done == #list and #list > 0
		-- Finishing today extends the streak by one (or starts it at 1).
		local nextStreak = if allDone then streak() else streak() + 1
		f.Text = if allDone
			then string.format("All done today! Streak: %d day%s.", streak(), if streak() == 1 then "" else "s")
			else string.format(
				"Finish all %d for a bonus of %s (%d-day streak).",
				#list,
				Util.formatCash(DailyData.Bonus(bestAxeTier(), nextStreak, if loop == 2 then 2 else nil)),
				nextStreak
			)
		if UITheme.Compact() then
			-- One short line on a phone (the panel has to clear the jump zone).
			f.Text = if allDone
				then string.format("All done! %d-day streak", streak())
				else string.format(
					"Bonus for all %d: %s",
					#list,
					Util.formatCash(DailyData.Bonus(bestAxeTier(), nextStreak, if loop == 2 then 2 else nil))
				)
		end
	end
	local c = countdown
	if c then
		c.Text = timeLeft()
	end
	local nextDay = tomorrow
	if nextDay then
		-- The roll is a pure function of user id and day, so tomorrow's first
		-- goal is known now (the server rolls the same list at the reset).
		local day = DailyData.Day(os.time()) + 1
		local first = DailyData.Roll(player.UserId, day, bestAxeTier(), if loop == 2 then 2 else nil)[1]
		nextDay.Text = if first then "Tomorrow: " .. DailyData.GoalText(first) else ""
		nextDay.Visible = first ~= nil and not UITheme.Compact()
	end
end

-- Rook's panel: NPCController calls it as his talk box closes. During the
-- tutorial there is nothing to show (his line sent you back to Murph).
function DailyUI.OpenForeman()
	if ((player:GetAttribute("TutorialStep") :: number?) or 0) > 0 then
		return
	end
	local card = panel
	local close = if card then card:FindFirstChild("Close", true) else nil
	if not card or not close or not close:IsA("GuiObject") then
		return
	end
	foremanMode = true
	DailyUI._open(close)
	refresh()
end

local function build()
	-- The goals panel's screen: over the side buttons (it can drop over
	-- them), under the shop.
	local gui = UITheme.Screen("DailyUI", UITheme.Layers.Daily)

	-- A corner pill: on a phone 36 tall, with a fingertip-tall hit area
	-- round it (UITheme.HitPad). It grows with its text, so there the pad
	-- goes beside it, in a slot that holds both in the corner's line.
	local spec: { size: Vector2?, text: number, hit: number? } =
		{ size = Vector2.new(200, 30), text = UITheme.Size.TextMin }
	local size = spec.size or Vector2.new(200, 30)
	local b = Instance.new("TextButton")
	b.Name = "DailyButton"
	b.LayoutOrder = 10 -- at the right margin, under the cash plaque
	b.Size = UDim2.fromOffset(size.X, size.Y) -- at least this wide: it grows with its text
	b.AutomaticSize = Enum.AutomaticSize.X
	b.BackgroundColor3 = BARK
	b.Font = UITheme.Fonts.Black
	b.TextSize = spec.text
	b.TextColor3 = CREAM
	b.AutoButtonColor = true
	b.Visible = false
	corner(b, size.Y / 2)
	UITheme.stroke(b, INK, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = b
	local line = HUD.UnderCash() or gui
	if spec.hit then
		local slot = Instance.new("Frame")
		slot.Name = "DailySlot"
		slot.LayoutOrder = b.LayoutOrder
		slot.Size = UDim2.fromOffset(0, size.Y)
		slot.AutomaticSize = Enum.AutomaticSize.X -- as wide as the button
		slot.BackgroundTransparency = 1
		slot.Visible = false
		slot.Parent = line
		b.Parent = slot
		buttonSlot = slot
	else
		b.Parent = line
	end
	button = b

	local p = Instance.new("Frame")
	p.Name = "Goals"
	p.Size = UDim2.fromOffset(280, 0)
	p.AutomaticSize = Enum.AutomaticSize.Y
	p.BackgroundColor3 = PAPER
	p.Visible = false
	corner(p, 12)
	UITheme.stroke(p, BARK, 3)
	local inner = Instance.new("UIPadding")
	inner.PaddingLeft = UDim.new(0, 10)
	inner.PaddingRight = UDim.new(0, 10)
	inner.PaddingTop = UDim.new(0, 10)
	inner.PaddingBottom = UDim.new(0, 10)
	inner.Parent = p
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = p
	p.Parent = gui
	panel = p
	-- Close and Take share one row, so the panel stays short enough to clear
	-- the phone's jump zone.
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.LayoutOrder = 0
	actions.Size = UDim2.new(1, 0, 0, UITheme.Size.Tap)
	actions.BackgroundTransparency = 1
	actions.Parent = p
	local actionList = Instance.new("UIListLayout")
	actionList.FillDirection = Enum.FillDirection.Horizontal
	actionList.SortOrder = Enum.SortOrder.LayoutOrder
	actionList.Padding = UDim.new(0, 8)
	actionList.Parent = actions
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.LayoutOrder = 1
	close.Size = UDim2.fromOffset(84, UITheme.Size.Tap) -- wide enough for its word
	close.BackgroundColor3 = BARK
	close.TextColor3 = CREAM
	close.Font = UITheme.Fonts.Black
	close.TextSize = 16
	close.Text = "Close"
	close.AutoButtonColor = true
	corner(close, 8)
	close.Parent = actions
	close.Activated:Connect(function()
		DailyUI._close()
	end)
	p:GetPropertyChangedSignal("Visible"):Connect(function()
		if not p.Visible then
			goalsOpen = false
			MenuPad.Close(p)
		end
	end)
	HUD.Popup(p, close)

	local take = Instance.new("TextButton")
	take.Name = "Take"
	take.LayoutOrder = 2 -- beside Close
	take.Size = UDim2.new(1, -92, 0, UITheme.Size.Tap)
	take.BackgroundColor3 = GREEN
	take.TextColor3 = CREAM
	take.Font = UITheme.Fonts.Black
	take.TextSize = 16
	take.AutoButtonColor = true
	take.Visible = false
	corner(take, 8)
	take.Parent = actions
	take.Activated:Connect(function()
		-- The server checks Rook is within reach and pays once; this only asks.
		Net.Remote("ForemanTurnIn"):FireServer()
	end)
	takeButton = take

	local goalsHeading = text(p, "ROOK'S JOBS", UITheme.Sized("DailyHeading").text, UITheme.Fonts.Black, 1)
	goalsHeading.TextColor3 = BARK
	headingLabel = goalsHeading
	for i = 1, DailyData.GoalsPerDay do
		local row = Instance.new("Frame")
		row.LayoutOrder = 1 + i
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundTransparency = 1
		row.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -60, 0, 22)
		label.BackgroundTransparency = 1
		label.Font = UITheme.Fonts.Body
		label.TextSize = UITheme.Sized("DailyFooter").text
		label.TextColor3 = INK
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row
		local reward = Instance.new("TextLabel")
		reward.AnchorPoint = Vector2.new(1, 0)
		reward.Position = UDim2.fromScale(1, 0)
		reward.Size = UDim2.fromOffset(60, 22)
		reward.BackgroundTransparency = 1
		reward.Font = UITheme.Fonts.Bold
		reward.TextSize = UITheme.Sized("DailyFooter").text
		reward.TextColor3 = GREEN
		reward.TextXAlignment = Enum.TextXAlignment.Right
		reward.Parent = row
		local bar = Instance.new("Frame")
		bar.Position = UDim2.fromOffset(0, 26)
		bar.Size = UDim2.new(1, 0, 0, 8)
		bar.BackgroundColor3 = PAPER_DARK
		corner(bar, 4)
		bar.Parent = row
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = AMBER
		corner(fill, 4)
		fill.Parent = bar
		table.insert(goalRows, { frame = row, text = label, reward = reward, fill = fill })
	end
	footer = text(p, "", UITheme.Sized("DailyFooter").text, Enum.Font.GothamMedium, 10)
	local calendar = Instance.new("Frame")
	calendar.Name = "Calendar"
	calendar.LayoutOrder = 12
	calendar.Size = UDim2.new(1, 0, 0, 46)
	calendar.BackgroundTransparency = 1
	calendar.Parent = p
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 3)
	row.Parent = calendar
	for day = 1, DailyData.LoginDays do
		local cell = Instance.new("Frame")
		cell.Name = "Day" .. day
		cell.LayoutOrder = day
		cell.Size = UDim2.new(1 / DailyData.LoginDays, -3, 1, 0)
		cell.BackgroundColor3 = PAPER
		corner(cell, 6)
		UITheme.stroke(cell, BARK, 1)
		cell.Parent = calendar
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = UITheme.Fonts.Black
		label.TextSize = UITheme.Sized("DailyCountdown").text
		label.TextColor3 = INK
		label.Parent = cell
		table.insert(calendarCells, { frame = cell, label = label })
	end
	calendarFrame = calendar
	calendarNote = text(p, "", UITheme.Sized("DailyCountdown").text, UITheme.Fonts.Body, 13)
	local heading = text(p, "", UITheme.Sized("DailyHeading").text, UITheme.Fonts.Black, 14)
	heading.TextColor3 = AMBER
	heading.Visible = false
	eventHeading = heading
	local lines = text(p, "", UITheme.Sized("DailyFooter").text, Enum.Font.GothamMedium, 15)
	lines.Visible = false
	eventLines = lines
	local c = text(p, "", UITheme.Sized("DailyCountdown").text, UITheme.Fonts.Body, 11)
	c.TextColor3 = BARK
	countdown = c
	local tm = text(p, "", UITheme.Sized("DailyCountdown").text, UITheme.Fonts.Body, 12)
	tm.TextColor3 = Color3.fromRGB(140, 128, 110) -- greyed: not today's, not yet
	tomorrow = tm

	local function toggle()
		if p.Visible then
			DailyUI._close()
		else
			DailyUI._open(close)
			refresh()
		end
	end
	b.Activated:Connect(toggle)
	HudNav.Add(b, { id = "daily", label = "DAILY GOALS", press = toggle })
	-- The pad's shortcut, and its glyph just left of the button (UI-15).
	HUD.PadShortcut(Enum.KeyCode.DPadUp, function() -- HudRules.PadKeys.daily
		return b.Visible
	end, toggle)
	local glyph = HUD.PadGlyph(Enum.KeyCode.DPadUp, b)
	glyph.LayoutOrder = b.LayoutOrder - 1
	glyph.Parent = line
	UITheme.Clicks(b) -- a plain button: it clicks like the Buttons (its HitPad does too)
	local slot = buttonSlot
	if spec.hit and slot then
		UITheme.HitPad(b, spec.hit, slot).Activated:Connect(toggle)
	end

	gui.Parent = player:WaitForChild("PlayerGui")
end

function DailyUI.Start()
	build()
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			DailyUI.ApplyKey(input.KeyCode)
		end
	end)
	for _, attribute in ipairs({
		"DailyGoals",
		"DailyStreak",
		"DailyResetAt",
		"DailyBonusOwed",
		"DailyLoginDay",
		"EventGoals",
		"EventInfo",
		"BestAxeTier",
		"TutorialStep",
	}) do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
	UITheme.WatchLayout(refresh)
	-- Keep the countdown ticking while the goals are open.
	task.spawn(function()
		while true do
			task.wait(30)
			local p = panel
			if p and p.Visible then
				refresh()
			end
		end
	end)
end

return DailyUI
