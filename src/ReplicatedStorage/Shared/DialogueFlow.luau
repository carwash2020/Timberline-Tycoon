--!strict
-- DialogueFlow: the rules of the dialogue box (DialogueUI), pure so the
-- specs can drive them without a screen.
--
-- Talking to someone (E, X or a tap on their Talk prompt) opens a box near
-- the bottom of the screen: the speaker's name and role, one line, and a
-- continue prompt. Each press of the interact button (E on a keyboard, X on
-- a gamepad, a click or tap on the box) shows the next line, and the press
-- on the last line closes it. Nothing is skipped or granted by pressing:
-- the lines are what the server (DialogueService, QuestUI's step line) or
-- NPCDialogue already picked, and a server offer's Yes / No still goes to
-- the server as before.
--
--   * Pages: a conversation is a list of lines. A line that would not fit
--     in about three lines of the box is split at a sentence, else a space
--     (Split), so the box stays modest: 40% of the screen wide, 2 to 3
--     lines of text.
--   * Advance: pure state in, state out; the last page's Advance closes.
--   * ShouldClose: walking more than CloseDistance away, the speaker going
--     (streamed out, lying down to sleep), the player going down, another
--     panel taking over (the plot picker), or the box being left open far
--     too long. Walking is never blocked while the box is up.
--   * Key: which key the continue prompt shows, by device.

local DialogueFlow = {}

DialogueFlow.WidthFraction = 0.4 -- of the screen's width
DialogueFlow.MinWidth = 300 -- px: a phone still gets a readable box
DialogueFlow.MaxWidth = 560 -- px: a TV does not get a banner
DialogueFlow.MaxTextLines = 3
DialogueFlow.Pad = 12 -- px, the box's padding each side
DialogueFlow.CharWidth = 0.55 -- of the text size: a safe average glyph for GothamMedium
DialogueFlow.MaxPages = 6
-- Talking to someone closes when the player is this far (studs) from them.
-- A Talk prompt reaches NPCData.TalkDistance (12), so this is well outside it
-- and a step back does not close the box.
DialogueFlow.CloseDistance = 24
-- Prompts come back this long (seconds) after the box closes, so the press
-- that closed it does not also open the next talk.
DialogueFlow.ReenableDelay = 0.3
DialogueFlow.IgnoreSeconds = 0.2 -- the press that opened the box does not also continue it
DialogueFlow.MaxOpenSeconds = 90 -- a box nobody answered goes by itself

export type State = {
	speaker: string, -- NPCData id, "" if unknown
	name: string,
	role: string?,
	pages: { string },
	index: number,
}

export type Check = {
	distance: number?, -- studs from the speaker; nil when the speaker's position is unknown
	gone: boolean?, -- the speaker streamed out or was removed
	asleep: boolean?, -- the speaker lay down
	playerDown: boolean?, -- no character, or a dead one
	panelOpen: boolean?, -- another panel (the plot picker) took the screen
	openFor: number?, -- seconds the box has been up
}

-- The box's width in px of the screen it sits in: 40% of it, kept between
-- MinWidth and MaxWidth (and never wider than the screen).
function DialogueFlow.Width(screenWidth: number): number
	local want = math.clamp(screenWidth * DialogueFlow.WidthFraction, DialogueFlow.MinWidth, DialogueFlow.MaxWidth)
	return math.min(want, math.max(screenWidth, 1))
end

-- About how many characters fit on one line of `width` px at `textSize`.
function DialogueFlow.CharsPerLine(width: number, textSize: number): number
	local inner = width - DialogueFlow.Pad * 2
	return math.max(12, math.floor(inner / (textSize * DialogueFlow.CharWidth)))
end

-- The most characters one page may hold: MaxTextLines lines.
function DialogueFlow.PageChars(width: number, textSize: number): number
	return DialogueFlow.CharsPerLine(width, textSize) * DialogueFlow.MaxTextLines
end

local function trim(text: string): string
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

-- Cuts at the last sentence end (. ! ?) at or before `limit`, else the last
-- space, else the limit itself. Returns the head and the rest.
local function cut(text: string, limit: number): (string, string)
	local best = 0
	for i = 1, math.min(limit, #text) do
		local c = string.sub(text, i, i)
		if (c == "." or c == "!" or c == "?") and (i == #text or string.sub(text, i + 1, i + 1) == " ") then
			best = i
		end
	end
	if best < limit * 0.4 then
		-- No sentence end near enough to the limit: the last space.
		best = 0
		for i = math.min(limit, #text), 1, -1 do
			if string.sub(text, i, i) == " " then
				best = i - 1
				break
			end
		end
		if best == 0 then
			best = limit
		end
	end
	return trim(string.sub(text, 1, best)), trim(string.sub(text, best + 1))
end

-- One line of speech as pages of at most `maxChars` characters.
function DialogueFlow.Split(text: string, maxChars: number): { string }
	local out: { string } = {}
	local rest = trim(text)
	local limit = math.max(8, math.floor(maxChars))
	while #rest > limit do
		local head, tail = cut(rest, limit)
		if head == "" then
			break
		end
		table.insert(out, head)
		rest = tail
	end
	if rest ~= "" then
		table.insert(out, rest)
	end
	return out
end

-- A conversation's lines as pages: empty and non-text entries go, a line
-- already said goes, long ones are split, and no more than MaxPages stay.
function DialogueFlow.Pages(lines: { unknown }, maxChars: number): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, line in ipairs(lines) do
		if type(line) == "string" then
			local text = trim(line)
			if text ~= "" and not seen[text] then
				seen[text] = true
				for _, page in ipairs(DialogueFlow.Split(text, maxChars)) do
					if #out < DialogueFlow.MaxPages then
						table.insert(out, page)
					end
				end
			end
		end
	end
	return out
end

-- A box to show, or nil when there is nothing to say.
function DialogueFlow.New(speaker: string?, name: string?, role: string?, pages: { string }): State?
	if #pages == 0 then
		return nil
	end
	return {
		speaker = speaker or "",
		name = if name and name ~= "" then name else "...",
		role = if role and role ~= "" then role else nil,
		pages = pages,
		index = 1,
	}
end

function DialogueFlow.Current(state: State): string
	return state.pages[state.index] or ""
end

function DialogueFlow.IsLast(state: State): boolean
	return state.index >= #state.pages
end

-- One press of continue. Returns the state to show and whether the
-- conversation is over (the press on the last page). The state passed in
-- is not changed.
function DialogueFlow.Advance(state: State): (State, boolean)
	if DialogueFlow.IsLast(state) then
		return state, true
	end
	return {
		speaker = state.speaker,
		name = state.name,
		role = state.role,
		pages = state.pages,
		index = state.index + 1,
	},
		false
end

-- The prompt's word: Continue until the last page, then Close.
function DialogueFlow.PromptWord(state: State): string
	return if DialogueFlow.IsLast(state) then "Close" else "Continue"
end

-- "1/3", or nil for a single page.
function DialogueFlow.Counter(state: State): string?
	if #state.pages <= 1 then
		return nil
	end
	return string.format("%d/%d", state.index, #state.pages)
end

-- The key the prompt shows: E on a keyboard, X (the pad's glyph) on a
-- gamepad, TAP on a touch screen. `device` is UITheme.Device(): "desktop",
-- "console" or "phone".
function DialogueFlow.Key(device: string): string
	if device == "console" then
		return "X"
	elseif device == "phone" then
		return "TAP"
	end
	return "E"
end

-- Why the box should close now, or nil to keep it up.
function DialogueFlow.ShouldClose(check: Check): string?
	if check.playerDown == true then
		return "down"
	end
	if check.panelOpen == true then
		return "panel"
	end
	if check.gone == true then
		return "gone"
	end
	if check.asleep == true then
		return "asleep"
	end
	local distance = check.distance
	if distance ~= nil and distance > DialogueFlow.CloseDistance then
		return "far"
	end
	local open = check.openFor
	if open ~= nil and open > DialogueFlow.MaxOpenSeconds then
		return "timeout"
	end
	return nil
end

-- Whether an NPC's lines come from the server (a keeper's counter talk, the
-- Hermit's quest, Old Hank's land office), which the server sends to the box
-- itself; the client builds no conversation for them.
function DialogueFlow.ServerSpoken(shop: string?, id: string): boolean
	return shop ~= nil or id == "Hermit" or id == "OldHank"
end

-- A keeper's own words around the shop's plain hello: one of their
-- greetings and one of their lines, picked by two rolls in [0, 1). Either is
-- nil when they have none. The keeper's talk then reads like anyone's:
-- greeting, the shop's line, a line of their own.
function DialogueFlow.KeeperExtras(
	greetings: { string }?,
	lines: { string }?,
	rollGreeting: number,
	rollLine: number
): (string?, string?)
	local function pick(list: { string }?, roll: number): string?
		if list == nil or #list == 0 then
			return nil
		end
		local index = math.clamp(math.floor(roll * #list) + 1, 1, #list)
		return list[index]
	end
	return pick(greetings, rollGreeting), pick(lines, rollLine)
end

-- The lines of a server payload (DialogueService), in order: an optional
-- intro, the text, then any more. Anything that is not a string is dropped.
-- An offer (a Yes / No) is its text alone.
function DialogueFlow.ServerLines(payload: any): { string }
	local out: { string } = {}
	if type(payload) ~= "table" or type(payload.text) ~= "string" then
		return out
	end
	if payload.choice == true then
		return { payload.text }
	end
	if type(payload.intro) == "string" then
		table.insert(out, payload.intro)
	end
	table.insert(out, payload.text)
	if type(payload.more) == "table" then
		for _, line in ipairs(payload.more) do
			if type(line) == "string" then
				table.insert(out, line)
			end
		end
	end
	return out
end

return DialogueFlow
