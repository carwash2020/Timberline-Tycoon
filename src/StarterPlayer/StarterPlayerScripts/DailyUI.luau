--!strict
-- DailyUI: daily goals and the streak (rules in Shared/DailyData).
--   * A "Daily goals 1/3" button under the cash plaque (top right), with
--     the streak.
--   * Tapping it opens the day's goals: progress bars, each goal's reward,
--     the bonus for finishing them all, and the time until new goals.
-- The server owns progress: it sets the DailyGoals, DailyStreak and
-- DailyResetAt attributes, and this redraws from them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyData = require(ReplicatedStorage.Shared.DailyData)
local Util = require(ReplicatedStorage.Shared.Util)

local DailyUI = {}

local player = Players.LocalPlayer

local INK = Color3.fromRGB(60, 40, 20)
local CREAM = Color3.fromRGB(245, 235, 215)
local PAPER = Color3.fromRGB(240, 225, 195)
local PAPER_DARK = Color3.fromRGB(226, 207, 170)
local BARK = Color3.fromRGB(88, 58, 34)
local GREEN = Color3.fromRGB(76, 140, 64)
local AMBER = Color3.fromRGB(255, 184, 64)

type GoalRow = { frame: Frame, text: TextLabel, reward: TextLabel, fill: Frame }

local button: TextButton? = nil
local panel: Frame? = nil
local goalRows: { GoalRow } = {}
local footer: TextLabel? = nil
local countdown: TextLabel? = nil

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

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

local function timeLeft(): string
	local resetAt = (player:GetAttribute("DailyResetAt") :: number?) or 0
	local seconds = math.max(0, resetAt - os.time())
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	return if hours > 0
		then string.format("New goals in %dh %02dm", hours, minutes)
		else string.format("New goals in %dm", math.max(1, minutes))
end

local function refresh()
	local list = goals()
	local done = 0
	for _, goal in ipairs(list) do
		if goal.done then
			done += 1
		end
	end
	local b = button
	if b then
		b.Visible = #list > 0
		local s = streak()
		b.Text = string.format(
			"DAILY GOALS  %d/%d%s",
			done,
			#list,
			if s > 0 then string.format("  ·  %d-day streak", s) else ""
		)
		b.BackgroundColor3 = if done == #list and #list > 0 then GREEN else BARK
	end
	for i, row in ipairs(goalRows) do
		local goal = list[i]
		row.frame.Visible = goal ~= nil
		if goal then
			row.text.Text = (if goal.done then "✓ " else "")
				.. DailyData.GoalText(goal)
				.. string.format("  (%d/%d)", goal.progress, goal.target)
			row.reward.Text = "+" .. Util.formatCash(goal.reward)
			row.fill.Size = UDim2.fromScale(math.clamp(goal.progress / math.max(1, goal.target), 0, 1), 1)
			row.fill.BackgroundColor3 = if goal.done then GREEN else AMBER
		end
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
				Util.formatCash(DailyData.Bonus(bestAxeTier(), nextStreak)),
				nextStreak
			)
	end
	local c = countdown
	if c then
		c.Text = timeLeft()
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DailyUI"
	gui.ResetOnSpawn = false

	local b = Instance.new("TextButton")
	b.Name = "DailyButton"
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -12, 0, 64) -- under the cash plaque
	b.Size = UDim2.fromOffset(200, 30)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.BackgroundColor3 = BARK
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = CREAM
	b.Visible = false
	corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = b
	b.Parent = gui
	button = b

	local p = Instance.new("Frame")
	p.Name = "Goals"
	p.AnchorPoint = Vector2.new(1, 0)
	p.Position = UDim2.new(1, -12, 0, 100)
	p.Size = UDim2.fromOffset(280, 0)
	p.AutomaticSize = Enum.AutomaticSize.Y
	p.BackgroundColor3 = PAPER
	p.Visible = false
	corner(p, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BARK
	stroke.Thickness = 2
	stroke.Parent = p
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

	text(p, "TODAY'S GOALS", 14, Enum.Font.GothamBold, 1)
	for i = 1, DailyData.GoalsPerDay do
		local row = Instance.new("Frame")
		row.LayoutOrder = 1 + i
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundTransparency = 1
		row.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -60, 0, 22)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 14
		label.TextColor3 = INK
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row
		local reward = Instance.new("TextLabel")
		reward.AnchorPoint = Vector2.new(1, 0)
		reward.Position = UDim2.fromScale(1, 0)
		reward.Size = UDim2.fromOffset(60, 22)
		reward.BackgroundTransparency = 1
		reward.Font = Enum.Font.GothamBold
		reward.TextSize = 14
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
	footer = text(p, "", 13, Enum.Font.GothamMedium, 10)
	local c = text(p, "", 12, Enum.Font.Gotham, 11)
	c.TextColor3 = BARK
	countdown = c

	b.Activated:Connect(function()
		p.Visible = not p.Visible
		refresh()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function DailyUI.Start()
	build()
	for _, attribute in ipairs({ "DailyGoals", "DailyStreak", "DailyResetAt", "BestAxeTier" }) do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
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
