--!strict
-- LoadingScreen (WLD-03): the branded card between Roblox's own loader and
-- the spawn, so a new server's 10-20 s build never shows a grey screen.
-- ReplicatedFirst runs this before anything else replicates, so it can't
-- use UITheme or Shared (they aren't here yet): the colours and fonts are
-- inlined, and it builds its own GUI.
--   * Puts one plaque in PlayerGui over an Ink backdrop (45% transparent, so
--     the world shows through): the title and one tip that changes every few
--     seconds. No buttons. Only then does it remove Roblox's default loading
--     screen, so there's no gap between the two.
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
--     14 px or more; bigger screens scale it up (scaleFor). The plaque is
--     min(280, 72% of the width) wide and 132 high, at (0.5, 0.45).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local LoadingTips = require(script.Parent.LoadingTips)

local MAX_SECONDS = 30 -- the card never stays up longer than this
local FADE_SECONDS = 0.6
local BACKSTOP_SECONDS = MAX_SECONDS + FADE_SECONDS + 5
local TIP_SECONDS = 5 -- each tip shows this long
local TIP_FADE = 0.3 -- and fades in and out over this
local PLAYERGUI_WAIT = 5 -- seconds per WaitForChild try (a timeout, so no infinite-yield warning)
local PLAYERGUI_TRIES = 6
local PLAYER_WAIT = 10 -- seconds to wait for Players.LocalPlayer, should it not be set yet

-- UITheme's palette (UITheme isn't loaded yet; LoadingScreen.spec checks
-- these match UITheme.Colors). The GAD round 3 plaque.
local INK = Color3.fromHex("#3C2814")
local CREAM = Color3.fromHex("#F5EBD7")
local PAPER = Color3.fromHex("#F0E1C3")
local PAPER_DARK = Color3.fromHex("#E2CFAA")
local BARK = Color3.fromHex("#583A22")

-- The card: one plaque, 132 high, 16 px padding, a 4 px drop edge; as wide
-- as 280 px, or 72% of the screen if that is narrower.
local CARD_WIDTH = 280
local CARD_HEIGHT = 132
local CARD_SHARE = 0.72
local PADDING = 16
local DROP = 4
local BACKDROP_TRANSPARENCY = 0.45

local TITLE = "Timberline Tycoon"

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

-- The plaque's width for a screen `safeWidth` wide (in the plaque's units).
local function cardWidth(safeWidth: number): number
	return math.floor(math.min(CARD_WIDTH, CARD_SHARE * safeWidth))
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

	-- Ink at 45% transparency over the world (not a scene of its own).
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = INK
	backdrop.BackgroundTransparency = BACKDROP_TRANSPARENCY
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen

	-- One plaque (GAD round 3): Bark behind (the 4 px drop edge), a Paper
	-- face on it with a Bark 2 px stroke and the Cream-Paper-PaperDark
	-- gradient. No buttons.
	local plaque = Instance.new("Frame")
	plaque.Name = "Plaque"
	plaque.AnchorPoint = Vector2.new(0.5, 0.5)
	plaque.Position = UDim2.fromScale(0.5, 0.45)
	plaque.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	plaque.BackgroundColor3 = BARK
	plaque.BorderSizePixel = 0
	corner(plaque, UDim.new(0, 12))
	local scale = Instance.new("UIScale")
	scale.Parent = plaque

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.new(1, 0, 1, -DROP)
	face.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient multiplies it: white shows the keypoints as they are
	face.BorderSizePixel = 0
	corner(face, UDim.new(0, 12))
	local rim = Instance.new("UIStroke")
	rim.Color = BARK
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = face
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CREAM),
		ColorSequenceKeypoint.new(0.18, PAPER),
		ColorSequenceKeypoint.new(1, PAPER_DARK),
	})
	shade.Parent = face
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PADDING)
	pad.PaddingBottom = UDim.new(0, PADDING)
	pad.PaddingLeft = UDim.new(0, PADDING)
	pad.PaddingRight = UDim.new(0, PADDING)
	pad.Parent = face
	face.Parent = plaque
	plaque.Parent = backdrop

	local title = textLabel(face, "Title", TITLE, Enum.Font.FredokaOne, 20, INK)
	title.Size = UDim2.new(1, 0, 0, 26)

	-- One line of tip (it wraps to as many as it needs), GothamMedium 14, never smaller.
	local tip = textLabel(face, "Tip", "", Enum.Font.GothamMedium, 14, BARK)
	tip.Position = UDim2.fromOffset(0, 32)
	tip.Size = UDim2.new(1, 0, 1, -32)
	tip.TextWrapped = true
	tip.TextYAlignment = Enum.TextYAlignment.Top
	local tipFit = Instance.new("UITextSizeConstraint")
	tipFit.MinTextSize = 14
	tipFit.MaxTextSize = 14
	tipFit.Parent = tip

	-- Shuffled once, then again only after every line has been shown.
	local cycle = LoadingTips.Begin(math.random)

	local function draw(elapsed: number, fade: number)
		local function mix(base: number): number
			return base + (1 - base) * fade
		end
		local camera = workspace.CurrentCamera
		if camera then
			local view = camera.ViewportSize
			local s = scaleFor(view)
			if scale.Scale ~= s then
				scale.Scale = s
			end
			-- Width = min(280, 72% of the screen's width), in the card's own units.
			local width = cardWidth(view.X / s)
			if plaque.Size.X.Offset ~= width then
				plaque.Size = UDim2.fromOffset(width, CARD_HEIGHT)
			end
		end
		local slot = math.floor(elapsed / TIP_SECONDS)
		local text = LoadingTips.LineAt(cycle, slot)
		if tip.Text ~= text then
			tip.Text = text
		end
		local into = elapsed - slot * TIP_SECONDS
		local tipHidden = math.clamp(1 - math.min(into, TIP_SECONDS - into) / TIP_FADE, 0, 1)
		backdrop.BackgroundTransparency = mix(BACKDROP_TRANSPARENCY)
		plaque.BackgroundTransparency = mix(0)
		face.BackgroundTransparency = mix(0)
		rim.Transparency = mix(0)
		title.TextTransparency = mix(0)
		tip.TextTransparency = mix(tipHidden)
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
