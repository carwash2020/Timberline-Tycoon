--!strict
-- LoadingScreen (WLD-03): the branded card between Roblox's own loader and
-- the spawn, so a new server's 10-20 s build never shows a grey screen.
-- ReplicatedFirst runs this before anything else replicates, so it can't
-- use UITheme or Shared (they aren't here yet): the colours and fonts are
-- inlined, and it builds its own GUI.
--   * Puts a full-screen card in PlayerGui: the title, a tip that changes
--     every few seconds, and three pulsing dots. Only then does it remove
--     Roblox's default loading screen, so there's no gap between the two.
--   * Fades out once the LocalPlayer has a Character, the save is in (the
--     "ProfileLoaded" attribute GameServer sets) and the game has loaded,
--     or after MAX_SECONDS whatever happens. Then it destroys itself.
--   * It never leaves the screen blocked: an error removes the card at
--     once, and a backstop removes it a little after MAX_SECONDS even if
--     this script stalls.
--   * It sits over every game screen (DisplayOrder 100). The HUD's own
--     "Loading your save..." card (DisplayOrder 10) is under it, and shows
--     only if the save is still loading when this card gives up.
--   * Sized for an iPhone SE in landscape (667x375) at scale 1, text at
--     14 px or more; bigger screens scale it up (scaleFor).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local MAX_SECONDS = 30 -- the card never stays up longer than this
local FADE_SECONDS = 0.6
local BACKSTOP_SECONDS = MAX_SECONDS + FADE_SECONDS + 5
local TIP_SECONDS = 5 -- each tip shows this long
local TIP_FADE = 0.3 -- and fades in and out over this
local PLAYERGUI_WAIT = 5 -- seconds per WaitForChild try (a timeout, so no infinite-yield warning)
local PLAYERGUI_TRIES = 6
local PLAYER_WAIT = 10 -- seconds to wait for Players.LocalPlayer, should it not be set yet

-- UITheme's palette (UITheme isn't loaded yet).
local INK = Color3.fromHex("#3C2814")
local CREAM = Color3.fromHex("#F5EBD7")
local PAPER = Color3.fromHex("#F0E1C3")
local BARK = Color3.fromHex("#583A22")
local AMBER = Color3.fromHex("#FFB840")

local TITLE = "Timberline Tycoon"
-- Inlined like the colours (ReplicatedFirst runs before Shared arrives).
-- The v2 loop's (GameConfig.CoreLoop 2): cut anywhere, drag, carry loose.
local TIPS = {
	"Swing low on a trunk and keep hitting the same spot. Watch the notch grow until it falls.",
	"Put your axe away, then click and hold a log to drag it onto your truck's bed.",
	"Back your truck onto the green pad by the sawmill: the wood sells itself, by volume.",
	"A felled tree grows back somewhere else in its stand, smaller at first.",
	"Odd-looking bark can hide figured wood. The sawmill pays extra for it.",
	"Elders are giants. Anyone who chops a share of one is paid when it falls.",
}

local started = os.clock()
local player = Players.LocalPlayer
local gui: ScreenGui? = nil

local function removeCard()
	local g = gui
	gui = nil
	if g then
		g:Destroy()
	end
end

-- Content scale for a screen: 1 up to an iPhone SE in landscape, growing
-- with the screen but never wider than it (the content is at most 560 px
-- wide at scale 1, and 560 * W/700 < W).
local function scaleFor(viewport: Vector2): number
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end
	return math.clamp(math.min(viewport.Y / 420, viewport.X / 700), 1, 1.8)
end

local function textLabel(parent: Instance, name: string, text: string, font: Enum.Font, size: number, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = parent
	return label
end

local function corner(parent: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

type Card = {
	gui: ScreenGui,
	draw: (elapsed: number, fade: number) -> (), -- fade: 0 shown .. 1 gone
}

local function build(): Card
	local screen = Instance.new("ScreenGui")
	screen.Name = "LoadingScreen"
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 100
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	-- White, because a UIGradient multiplies its parent's colour rather
	-- than replacing it (UITheme's button shine relies on that too): white
	-- x Bark..Ink shows Bark..Ink. A Bark base would show Bark x Bark,
	-- close to black.
	backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
	backdrop.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(BARK, INK)
	gradient.Rotation = 90 -- Bark at the top, Ink at the bottom
	gradient.Parent = backdrop
	backdrop.Parent = screen

	-- The backdrop stays full-bleed. The words sit inside a 5% margin.
	local inset = Instance.new("Frame")
	inset.Name = "TextInset"
	inset.BackgroundTransparency = 1
	inset.Position = UDim2.fromScale(0.05, 0.05)
	inset.Size = UDim2.fromScale(0.9, 0.9)
	inset.Parent = backdrop

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(560, math.huge)
	maxSize.Parent = content
	local scale = Instance.new("UIScale")
	scale.Parent = content
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.Parent = content
	content.Parent = inset

	local title = textLabel(content, "Title", TITLE, Enum.Font.FredokaOne, 40, CREAM)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 48)
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = INK
	titleStroke.Thickness = 3
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.LayoutOrder = 2
	divider.Size = UDim2.fromOffset(96, 4)
	divider.BackgroundColor3 = AMBER
	divider.BorderSizePixel = 0
	corner(divider, UDim.new(0, 2))
	divider.Parent = content

	local kicker = textLabel(content, "Kicker", "TIP", Enum.Font.GothamBlack, 14, AMBER)
	kicker.LayoutOrder = 3
	kicker.Size = UDim2.new(1, 0, 0, 18)

	local tip = textLabel(content, "Tip", "", Enum.Font.GothamMedium, 18, PAPER)
	tip.LayoutOrder = 4
	-- Room for two lines whatever the tip, so the card doesn't hop as the
	-- tips change (AutomaticSize treats Size as a minimum: a third line,
	-- on a narrow screen, still fits).
	tip.Size = UDim2.new(1, 0, 0, 46)
	tip.AutomaticSize = Enum.AutomaticSize.Y
	tip.TextWrapped = true
	tip.TextYAlignment = Enum.TextYAlignment.Top

	local dotRow = Instance.new("Frame")
	dotRow.Name = "Dots"
	dotRow.LayoutOrder = 5
	dotRow.Size = UDim2.fromOffset(44, 18)
	dotRow.BackgroundTransparency = 1
	dotRow.Parent = content
	local dots: { Frame } = {}
	for i = 1, 3 do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.AnchorPoint = Vector2.new(0, 1)
		dot.Position = UDim2.new(0, (i - 1) * 17, 1, 0)
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = AMBER
		dot.BorderSizePixel = 0
		corner(dot, UDim.new(0.5, 0))
		dot.Parent = dotRow
		dots[i] = dot
	end

	-- A random first tip, so a rejoin doesn't start on the same one.
	local firstTip = math.random(#TIPS)

	local function draw(elapsed: number, fade: number)
		local function mix(base: number): number
			return base + (1 - base) * fade
		end
		local camera = workspace.CurrentCamera
		if camera then
			local s = scaleFor(camera.ViewportSize)
			if scale.Scale ~= s then
				scale.Scale = s
			end
		end
		local slot = math.floor(elapsed / TIP_SECONDS)
		local text = TIPS[(firstTip - 1 + slot) % #TIPS + 1]
		if tip.Text ~= text then
			tip.Text = text
		end
		local into = elapsed - slot * TIP_SECONDS
		local tipHidden = math.clamp(1 - math.min(into, TIP_SECONDS - into) / TIP_FADE, 0, 1)
		backdrop.BackgroundTransparency = mix(0)
		title.TextTransparency = mix(0)
		titleStroke.Transparency = mix(0)
		divider.BackgroundTransparency = mix(0)
		kicker.TextTransparency = mix(0)
		tip.TextTransparency = mix(tipHidden)
		for i, dot in ipairs(dots) do
			local pulse = 0.5 + 0.5 * math.sin(elapsed * 5 - i * 0.9)
			dot.BackgroundTransparency = mix(0.7 - 0.6 * pulse)
		end
	end

	draw(0, 0)
	return { gui = screen, draw = draw }
end

-- Ready to play: a character in the world, the save loaded, the game in.
local function ready(): boolean
	local character = player.Character
	return character ~= nil
		and character.Parent ~= nil
		and player:GetAttribute("ProfileLoaded") == true
		and game:IsLoaded()
end

-- PlayerGui, waiting in short tries (never a bare WaitForChild).
local function findPlayerGui(): PlayerGui?
	for _ = 1, PLAYERGUI_TRIES do
		local found = player:FindFirstChildOfClass("PlayerGui")
		if found then
			return found
		end
		player:WaitForChild("PlayerGui", PLAYERGUI_WAIT)
	end
	return player:FindFirstChildOfClass("PlayerGui")
end

local function run()
	while not player and os.clock() - started < PLAYER_WAIT do
		task.wait()
		player = Players.LocalPlayer
	end
	if not player then
		return -- Roblox's own loader stays up and goes by itself
	end
	local playerGui = findPlayerGui()
	if not playerGui then
		warn("[LoadingScreen] no PlayerGui: leaving Roblox's loading screen up")
		return
	end
	local card = build()
	gui = card.gui
	card.gui.Parent = playerGui
	ReplicatedFirst:RemoveDefaultLoadingScreen() -- only now: the card is already showing
	task.delay(BACKSTOP_SECONDS, removeCard)

	-- (gui goes nil if the backstop takes the card down first.)
	while gui and not ready() and os.clock() - started < MAX_SECONDS do
		card.draw(os.clock() - started, 0)
		task.wait()
	end
	local fadeFrom = os.clock()
	while gui do
		local fade = math.min((os.clock() - fadeFrom) / FADE_SECONDS, 1)
		card.draw(os.clock() - started, fade)
		if fade >= 1 then
			break
		end
		task.wait()
	end
	removeCard()
end

local ok, err = xpcall(function(): any
	run()
	return nil
end, debug.traceback)
if not ok then
	warn("[LoadingScreen] " .. tostring(err))
	removeCard()
end
