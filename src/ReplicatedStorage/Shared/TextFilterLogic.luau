--!strict
-- TextFilterLogic: the pure rules behind ServerScriptService/TextFilter.
-- Text a player typed may only reach another player after Roblox's
-- TextService has filtered it, so every rule here fails closed: when a
-- filter call did not come back with a string, what others see is the
-- placeholder, never the raw text. Pure, so a spec can run every failure.

local TextFilterLogic = {}

-- What others see when filtering failed or the text had nothing to show.
TextFilterLogic.Placeholder = "####"

-- The longest text one filter call takes (TextService's own limit is 1024
-- characters; the game's fields are far shorter, this is the hard stop).
TextFilterLogic.MaxChars = 200

-- Typed text made safe to send to TextService: a string, no control
-- characters, no runs of spaces, trimmed, at most `maxChars` characters.
-- Nil when nothing usable is left (not a string, empty, or too long to cut
-- fairly: over-long text is refused, not silently truncated into a
-- different message).
function TextFilterLogic.Clean(text: unknown, maxChars: number?): string?
	if type(text) ~= "string" then
		return nil
	end
	local limit = if type(maxChars) == "number" and maxChars >= 1
		then math.floor(maxChars)
		else TextFilterLogic.MaxChars
	limit = math.min(limit, TextFilterLogic.MaxChars)
	local cleaned = string.gsub(text, "[%c]", " ")
	cleaned = string.gsub(cleaned, "%s+", " ")
	cleaned = string.match(cleaned, "^%s*(.-)%s*$") :: string
	if cleaned == "" then
		return nil
	end
	local ok, length = pcall(utf8.len, cleaned)
	if not ok or length == nil or length > limit then
		return nil
	end
	return cleaned
end

-- What to show for a filter answer. `answer` is what TextService gave back
-- (a string) or anything else when the call failed. A failure, an empty
-- string, or a non-string is the placeholder.
function TextFilterLogic.Resolve(answer: unknown): string
	if type(answer) ~= "string" or answer == "" then
		return TextFilterLogic.Placeholder
	end
	return answer
end

-- Same, for callers that would rather store a default than the placeholder:
-- nil when the filter failed.
function TextFilterLogic.Strict(answer: unknown): string?
	if type(answer) ~= "string" or answer == "" then
		return nil
	end
	return answer
end

return TextFilterLogic
