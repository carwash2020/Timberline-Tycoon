--!strict
-- DialogueUI: the dialogue box. Whoever you talk to, their words come here,
-- near the bottom of the screen and ABOVE Roblox's tool hotbar
-- (DialogueData.CardBottom), about 40% of the screen wide (DialogueFlow):
-- the speaker's name and role, the line, and a continue prompt. Press the
-- interact button for the next line; the press on the last line closes it:
-- E on a keyboard (or click the box), X on a gamepad, a tap on the box or
-- its Continue button on a phone. Walking is never blocked; walking more
-- than DialogueFlow.CloseDistance away, the speaker leaving, or another
-- panel taking over closes it.
--
-- Two ways in, both only a presentation of words someone else chose:
--   * DialogueUI.Talk(...): a conversation built on this client (NPCController's
--     townsfolk, QuestUI's Murph): a list of lines, paged in order.
--   * the server's Dialogue remote (DialogueService: the shopkeepers' counter
--     talk, with its Yes / No offers, and the Hermit): one line, or an offer.
--     A Yes or No still goes to the server, which decides what it grants.
-- While it is open: every other prompt is off (ProximityPromptService), so
-- the press that continues cannot also buy, open or talk to something
-- else; the player's TalkOpen attribute is true (HUD holds back toasts,
-- NoticePolicy hold); and on a gamepad the selection sits in the box and is
-- handed back to the HUD button it came from (GamepadNav). The HUD already
-- owns the D-pad shortcuts, so this box does not bind those keys.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DialogueData = require(ReplicatedStorage.Shared.DialogueData)
local DialogueFlow = require(ReplicatedStorage.Shared.DialogueFlow)
local NPCData = require(ReplicatedStorage.Shared.NPCData)
local Net = require(ReplicatedStorage.Shared.Net)
local GamepadNav = require(script.Parent.GamepadNav)
local HudRules = require(script.Parent.HudRules)
local PromptSwitch = require(script.Parent.PromptSwitch)
local UITheme = require(script.Parent.UITheme)

local DialogueUI = {}

export type Talk = {
	id: string?, -- NPCData id (the name and role come from it when not given)
	name: string?,
	role: string?,
	lines: { unknown }, -- in order; DialogueFlow.Pages splits and de-duplicates them
	model: Model?, -- the speaker, for the distance and "gone" checks
	onClose: (() -> ())?,
}

local ACTION = "ShopChoice"
local BUTTON_W = 140
local TEXT_SIZE = 17

-- What Start builds fills these in; the functions below are safe before it.
local impl: {
	talk: ((Talk) -> boolean)?,
	close: (() -> ())?,
	isOpen: (() -> boolean)?,
	talkingTo: ((Instance?) -> boolean)?,
	pageChars: (() -> number)?,
} =
	{}

-- Opens a conversation. Returns false when the box is not ready or there is
-- nothing to say.
function DialogueUI.Talk(talk: Talk): boolean
	local open = impl.talk
	return open ~= nil and open(talk)
end

function DialogueUI.Close()
	local close = impl.close
	if close then
		close()
	end
end

function DialogueUI.IsOpen(): boolean
	local isOpen = impl.isOpen
	return isOpen ~= nil and isOpen()
end

-- Whether the box is open with this model as the speaker: its bubbles stay
-- quiet meanwhile.
function DialogueUI.IsTalkingTo(model: Instance?): boolean
	local f = impl.talkingTo
	return f ~= nil and f(model)
end

-- How many characters a page may hold at the box's live width.
function DialogueUI.PageChars(): number
	local f = impl.pageChars
	if f then
		return f()
	end
	return DialogueFlow.PageChars(DialogueFlow.MinWidth, TEXT_SIZE)
end

-- The tagged NPC model with this id nearest `from` (a server line names its
-- speaker by id only).
local function findSpeaker(id: string, from: Vector3?): Model?
	local best: Model? = nil
	local bestDist = math.huge
	for _, inst in ipairs(CollectionService:GetTagged("NPC")) do
		if inst:IsA("Model") and inst:GetAttribute("NPCId") == id then
			local root = inst.PrimaryPart
			local d = if root and from then (root.Position - from).Magnitude else 0
			if best == nil or d < bestDist then
				best, bestDist = inst, d
			end
		end
	end
	return best
end

function DialogueUI.Start()
	local player = Players.LocalPlayer
	local C = UITheme.Colors
	local F = UITheme.Fonts
	local gui = UITheme.Screen("ShopTalk", UITheme.Layers.Dialogue)
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	-- The box is itself a button: a click or a tap anywhere on it continues.
	local column = Instance.new("TextButton")
	column.Name = "Card"
	column.AutoButtonColor = false
	column.Text = ""
	column.Selectable = false
	column.AnchorPoint = Vector2.new(0.5, 1)
	local function place()
		column.Position = UDim2.new(0.5, 0, 1, -DialogueData.CardBottom(UITheme.Bottom()))
	end
	place()
	UITheme.WatchLayout(place)
	column.Size = UDim2.fromScale(DialogueFlow.WidthFraction, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundColor3 = C.Bark
	column.BorderSizePixel = 0
	column.Parent = holder
	UITheme.corner(column, 12)
	UITheme.stroke(column, C.Ink, 3)
	UITheme.texture(column, "Wood", 12)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(DialogueFlow.MinWidth, 0)
	limit.MaxSize = Vector2.new(DialogueFlow.MaxWidth, math.huge)
	limit.Parent = column
	UITheme.padding(column, DialogueFlow.Pad, DialogueFlow.Pad, DialogueFlow.Pad, DialogueFlow.Pad)
	UITheme.list(column, 6)

	-- Who is speaking.
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.LayoutOrder = 1
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 0)
	head.AutomaticSize = Enum.AutomaticSize.Y
	head.Parent = column
	local headRow = UITheme.list(head, 8, true)
	headRow.VerticalAlignment = Enum.VerticalAlignment.Bottom
	local nameLabel = UITheme.label(head, "", F.Heading, 22, C.Amber)
	nameLabel.Name = "Name"
	nameLabel.LayoutOrder = 1
	nameLabel.Size = UDim2.new()
	nameLabel.AutomaticSize = Enum.AutomaticSize.XY
	local roleLabel = UITheme.label(head, "", F.Bold, 14, C.PaperDark)
	roleLabel.Name = "Role"
	roleLabel.LayoutOrder = 2
	roleLabel.Size = UDim2.new()
	roleLabel.AutomaticSize = Enum.AutomaticSize.XY

	-- The line: at least two lines tall so the box does not jump between pages.
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.LayoutOrder = 2
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, math.ceil(TEXT_SIZE * 2.5))
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.Font = F.Body
	line.TextSize = TEXT_SIZE
	line.TextColor3 = C.Cream
	line.TextWrapped = true
	line.TextTruncate = Enum.TextTruncate.None
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.Parent = column

	-- The foot: the page count, and the continue prompt (or Yes / No).
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.LayoutOrder = 3
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, DialogueData.ButtonPx)
	foot.Parent = column
	local counter = UITheme.label(foot, "", F.Bold, 14, C.PaperDark)
	counter.Name = "Count"
	counter.AnchorPoint = Vector2.new(0, 0.5)
	counter.Position = UDim2.fromScale(0, 0.5)
	counter.Size = UDim2.fromOffset(48, 20)
	counter.TextXAlignment = Enum.TextXAlignment.Left

	local function button(name: string, text: string, color: Color3, ink: Color3): TextButton
		local face = Instance.new("TextButton")
		face.Name = name
		face.AutoButtonColor = true
		face.AnchorPoint = Vector2.new(1, 0.5)
		face.Position = UDim2.fromScale(1, 0.5)
		face.Size = UDim2.fromOffset(BUTTON_W, DialogueData.ButtonPx)
		face.BackgroundColor3 = color
		face.BorderSizePixel = 0
		face.Font = F.Black
		face.Text = text
		face.TextSize = 18
		face.TextColor3 = ink
		face.Selectable = true
		face.ZIndex = 3
		face.Parent = foot
		UITheme.corner(face, 10)
		return face
	end

	local yes = button("Yes", "Yes", C.Green, C.Cream)
	local no = button("No", "No", C.Ink, C.Cream)
	yes.Position = UDim2.new(1, -(BUTTON_W + 12), 0.5, 0)
	yes.NextSelectionRight = no
	no.NextSelectionLeft = yes
	-- Continue / Close: a key cap (E, the pad's X, or nothing on a touch
	-- screen) and the word. Amber, so it reads as the one thing to press.
	local nextBtn = button("Next", "", C.Amber, C.Ink)
	nextBtn.Size = UDim2.fromOffset(BUTTON_W + 20, DialogueData.ButtonPx)
	local nextRow = UITheme.list(nextBtn, 8, true)
	nextRow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	nextRow.VerticalAlignment = Enum.VerticalAlignment.Center

	local state: DialogueFlow.State? = nil
	local choosing = false
	local boxUid: string? = nil
	local speakerModel: Model? = nil
	local asleepAtOpen = false
	local onClose: (() -> ())? = nil
	local openedAt = 0
	local bound = false
	local watching = false
	local promptToken = 0

	local function screenUnits(): number
		return holder.AbsoluteSize.X / math.max(UITheme.Scale(), 0.1)
	end

	local function pageChars(): number
		return DialogueFlow.PageChars(DialogueFlow.Width(screenUnits()), TEXT_SIZE)
	end
	impl.pageChars = pageChars

	-- The continue prompt: the key (by device) and the word (by page).
	local function paintPrompt()
		for _, child in ipairs(nextBtn:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local current = state
		if current == nil then
			return
		end
		local device = UITheme.Device()
		local key = DialogueFlow.Key(device)
		if device == "console" then
			local glyph = UITheme.Glyph(Enum.KeyCode.ButtonX, 30)
			glyph.LayoutOrder = 1
			glyph.Parent = nextBtn
		elseif device == "desktop" then
			local cap = Instance.new("Frame")
			cap.Name = "Key"
			cap.LayoutOrder = 1
			cap.Size = UDim2.fromOffset(30, 30)
			cap.BackgroundColor3 = C.Paper
			cap.BorderSizePixel = 0
			UITheme.corner(cap, 8)
			UITheme.stroke(cap, C.Ink, 2)
			cap.Parent = nextBtn
			local letter = UITheme.label(cap, key, F.Heading, 20, C.Ink)
			letter.Size = UDim2.fromScale(1, 1)
			letter.TextXAlignment = Enum.TextXAlignment.Center
		end
		local word = UITheme.label(nextBtn, DialogueFlow.PromptWord(current), F.Black, 18, C.Ink)
		word.Name = "Word"
		word.LayoutOrder = 2
		word.Size = UDim2.new()
		word.AutomaticSize = Enum.AutomaticSize.XY
	end

	local function render()
		local current = state
		if current == nil then
			return
		end
		nameLabel.Text = current.name
		roleLabel.Text = current.role or ""
		roleLabel.Visible = current.role ~= nil
		line.Text = DialogueFlow.Current(current)
		counter.Text = DialogueFlow.Counter(current) or ""
		yes.Visible = choosing
		no.Visible = choosing
		nextBtn.Visible = not choosing
		paintPrompt()
	end

	-- Tells the server this conversation is over, so the NPC stops facing
	-- you and goes back to what it was doing (NPCTalkService also lets go by
	-- itself when you walk off, go down or leave).
	local function sendEnd(speaker: string)
		if speaker == "" then
			return
		end
		pcall(function()
			Net.Remote("Dialogue"):FireServer("end", speaker)
		end)
	end

	local function hide(why: string?)
		local was = state ~= nil
		local spoke = if state then state.speaker else ""
		holder.Visible = false
		choosing = false
		boxUid = nil
		state = nil
		speakerModel = nil
		if bound then
			ContextActionService:UnbindAction(ACTION)
			bound = false
		end
		if was then
			print(string.format("[Talk] box closed: %s (%s)", spoke, why or "dismissed"))
			player:SetAttribute("TalkOpen", false)
			-- Every other prompt comes back a moment later, so the press that
			-- closed the box does not also fire one. Scheduled before anything
			-- below that could throw: prompts must never stay off.
			promptToken += 1
			local token = promptToken
			task.delay(DialogueFlow.ReenableDelay, function()
				if promptToken == token then
					PromptSwitch.Release("dialogue")
				end
			end)
		end
		-- The box's own selection goes; the HUD button it came from gets it back.
		local restored, restoreErr = (pcall :: any)(function()
			GamepadNav.Restore(column)
		end)
		if not restored then
			warn("[Talk] GamepadNav.Restore failed: " .. tostring(restoreErr))
		end
		if was then
			sendEnd(spoke)
		end
		local after = onClose
		onClose = nil
		if after then
			after()
		end
	end

	local function choose(which: string, why: string?)
		local uid = boxUid
		local offer = choosing
		hide(why or which)
		if offer and uid ~= nil then
			Net.Remote("Dialogue"):FireServer("pick", which, uid)
		end
	end

	-- One press of continue (E, X, a click or a tap): the next page, or the
	-- end. An offer's Yes / No is not this: those go to the server.
	local function advance()
		local current = state
		if current == nil or choosing then
			return
		end
		if os.clock() - openedAt < DialogueFlow.IgnoreSeconds then
			return -- the press that opened the box is not a press to continue
		end
		local nextState, done = DialogueFlow.Advance(current)
		if done then
			hide()
		else
			state = nextState
			render()
		end
	end

	local function bind()
		if bound then
			return
		end
		bound = true
		-- High priority: while the box is up, X and E mean this and nothing
		-- else (the other prompts are off, but a bound key would not be).
		ContextActionService:BindActionAtPriority(
			ACTION,
			function(_name: string, inputState: Enum.UserInputState, input: InputObject)
				if not holder.Visible or inputState ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				local key = input.KeyCode
				if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
					if choosing then
						choose("no")
					else
						hide()
					end
					return Enum.ContextActionResult.Sink
				end
				if key == Enum.KeyCode.ButtonX or key == Enum.KeyCode.E then
					if choosing then
						choose("yes")
					else
						advance()
					end
					return Enum.ContextActionResult.Sink
				end
				return Enum.ContextActionResult.Pass
			end,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.Escape,
			Enum.KeyCode.ButtonX,
			Enum.KeyCode.E
		)
	end

	-- Whether the plot picker is really on this screen. The server's Picking
	-- attribute says a picker was offered; it is only a reason to close this
	-- box while the picker itself is up (a Picking left set must not make
	-- every box close the moment it opens).
	local function pickerShowing(): boolean
		local playerGui = player:FindFirstChild("PlayerGui")
		local picker = if playerGui then playerGui:FindFirstChild("PlotPicker") else nil
		return picker ~= nil and picker:IsA("ScreenGui") and picker.Enabled
	end

	-- Close when the talk is over by walking: a few times a second.
	local function watch()
		if watching then
			return
		end
		watching = true
		task.spawn(function()
			while state ~= nil do
				task.wait(0.2)
				local current = state
				if current == nil then
					break
				end
				local char = player.Character
				local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
				local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
				local model = speakerModel
				local root = if model then model.PrimaryPart else nil
				local distance: number? = nil
				if hrp and hrp:IsA("BasePart") and root then
					distance = (hrp.Position - root.Position).Magnitude
				end
				local reason = DialogueFlow.ShouldClose({
					distance = distance,
					gone = model ~= nil and not model:IsDescendantOf(workspace),
					asleep = model ~= nil and not asleepAtOpen and model:GetAttribute("Asleep") == true,
					playerDown = hrp == nil or (humanoid ~= nil and humanoid.Health <= 0),
					panelOpen = player:GetAttribute("Picking") == true and pickerShowing(),
					openFor = os.clock() - openedAt,
				})
				if reason ~= nil then
					if choosing then
						choose("no", reason) -- walked away from an offer: a No, and the box is put back
					else
						hide(reason)
					end
				end
			end
			watching = false
		end)
	end

	-- Puts `next` on screen (replacing any box up now).
	local function open(convo: DialogueFlow.State, isChoice: boolean, uid: string?, model: Model?, after: (() -> ())?)
		local previous = onClose
		onClose = nil
		if state ~= nil and previous ~= nil then
			previous() -- the box being replaced is over
		end
		if state ~= nil and state.speaker ~= convo.speaker then
			sendEnd(state.speaker) -- and its speaker is let go
		end
		print(
			string.format(
				"[Talk] box open: %s (%d page%s%s)",
				convo.speaker,
				#convo.pages,
				if #convo.pages == 1 then "" else "s",
				if isChoice then ", offer" else ""
			)
		)
		state = convo
		choosing = isChoice
		boxUid = uid
		speakerModel = model
		asleepAtOpen = model ~= nil and model:GetAttribute("Asleep") == true
		onClose = after
		openedAt = os.clock()
		render()
		place() -- the hotbar or window may have changed since the last box
		holder.Visible = true
		player:SetAttribute("TalkOpen", true)
		promptToken += 1 -- a pending release from the last box must not undo this
		PromptSwitch.Hold("dialogue")
		bind()
		watch()
		if HudRules.PadSelects(UITheme.Device()) then
			if isChoice then
				GamepadNav.Focus(yes, column) -- Yes is selected, and the stick stays on the box
			else
				GamepadNav.Focus(nextBtn, column) -- A continues too
			end
		end
	end

	impl.talk = function(talk: Talk): boolean
		local npc = if talk.id then NPCData.Get(talk.id) else nil
		local pages = DialogueFlow.Pages(talk.lines, pageChars())
		local convo = DialogueFlow.New(
			talk.id,
			talk.name or (if npc then npc.name else nil),
			talk.role or (if npc then npc.role else nil),
			pages
		)
		if convo == nil then
			return false
		end
		open(convo, false, nil, talk.model, talk.onClose)
		return true
	end
	impl.close = function()
		if state ~= nil then
			if choosing then
				choose("no")
			else
				hide()
			end
		end
	end
	impl.isOpen = function(): boolean
		return state ~= nil
	end
	impl.talkingTo = function(model: Instance?): boolean
		return state ~= nil and model ~= nil and speakerModel == model
	end

	-- The server's line (a keeper at the counter, the Hermit).
	local function show(payload: any)
		if type(payload) ~= "table" or type(payload.text) ~= "string" then
			return
		end
		-- The Robux shelf's yes: ask Roblox for that pass or pack with the
		-- intent the Store screen sends. The server checks it again.
		local robux = payload.robux
		if type(robux) == "table" and type(robux.kind) == "string" and type(robux.key) == "string" then
			Net.Remote("BuyRobuxItem"):FireServer(robux.kind, robux.key)
		end
		local isChoice = payload.choice == true
		local uid = if type(payload.boxUid) == "string" then payload.boxUid else nil
		local speakerId = if type(payload.speaker) == "string" then payload.speaker else nil
		local npc = if speakerId then NPCData.Get(speakerId) else nil
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local from = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
		local model = if speakerId then findSpeaker(speakerId, from) else nil
		-- An offer is one short card; any other talk is its lines (a keeper's
		-- greeting, the shop's line, a line of their own), paged to fit.
		local pages = if isChoice
			then { payload.text }
			else DialogueFlow.Pages(DialogueFlow.ServerLines(payload), pageChars())
		local convo = DialogueFlow.New(speakerId, if npc then npc.name else nil, if npc then npc.role else nil, pages)
		if convo == nil then
			return
		end
		local cancel = if type(payload.noLabel) == "string" then payload.noLabel else "No"
		no.Text = cancel
		open(convo, isChoice, uid, model, nil)
	end

	yes.Activated:Connect(function()
		choose("yes")
	end)
	no.Activated:Connect(function()
		choose("no")
	end)
	nextBtn.Activated:Connect(advance)
	column.Activated:Connect(advance)
	-- The prompt's key follows the device in use.
	UserInputService.LastInputTypeChanged:Connect(function()
		if state ~= nil and not choosing then
			paintPrompt()
		end
	end)

	Net.Remote("Dialogue").OnClientEvent:Connect(show)
	gui.Parent = player:WaitForChild("PlayerGui")
	-- A respawn or a leave never strands the box (or the prompts).
	player.CharacterRemoving:Connect(function()
		DialogueUI.Close()
	end)
end

return DialogueUI
