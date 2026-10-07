--!strict
-- BoxWindows: what a shop box's windows show on the Lower and Higher quality
-- choices (Shared/QualityProfile). Pure over Instances (no services), so the
-- client module that calls it and the tests share the one rule.
--
-- The server builds ONE box for everyone (Shared/Art/BoxArt: the dark shell,
-- the glass windows and, in a model called Contents, a low-detail copy of the
-- real item). Building two versions per player is not possible and not wanted:
-- the server's geometry, sizes, hover marks and attributes stay the same for all.
-- On LOWER the player's own client takes the Contents model OUT of the box and
-- tints the glass in the item's accent colour instead (the strip already says
-- the name), so a phone draws no item copies in shop windows (3 to 32 parts a
-- box, a few hundred on a busy shelf). HIGHER leaves the box exactly as the
-- server made it. Switching the choice back puts the same model back.
--
-- Nothing here touches a part that is aimed at, held, priced or collided:
-- Contents is decor (CanCollide, CanQuery and CanTouch off, Massless), the
-- hover tag, the BoxUid, ForSale and OnShelf attributes live on the box model
-- and body, the walls and windows keep their sizes and collisions, and a
-- tinted pane is the same pane with a colour.

local BoxWindows = {}

BoxWindows.WindowNames = { "Window", "WindowTop", "SideWindow" }

-- A tinted pane: the accent colour, mostly see-through still (0.35 is darker
-- and flatter than the clear glass at 0.5, so an empty window reads as a coloured
-- one, not a hole).
BoxWindows.TintTransparency = 0.35

type Stash = {
	contents: Instance?,
	glass: { [Instance]: { color: Color3, transparency: number } },
}

-- Per box (weak: a box that streams out and is dropped takes its stash with it).
local stashes: { [Instance]: Stash } = setmetatable({}, { __mode = "k" }) :: any

local function accentOf(box: Instance): Color3
	local strip = box:FindFirstChild("Strip")
	if strip and strip:IsA("BasePart") then
		return strip.Color
	end
	local base = box:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		return base.Color
	end
	return Color3.fromRGB(150, 192, 212)
end

local function stashOf(box: Instance): Stash
	local stash = stashes[box]
	if stash == nil then
		stash = { contents = nil, glass = {} }
		stashes[box] = stash
	end
	return stash
end

-- Whether this box is showing its item right now (an opened box, which has no
-- Contents at all, counts as not showing one).
function BoxWindows.ShowsItem(box: Instance): boolean
	return box:FindFirstChild("Contents") ~= nil
end

-- Whether the box's windows are tinted in place of an item.
function BoxWindows.IsTinted(box: Instance): boolean
	local stash = stashes[box]
	if stash == nil then
		return false
	end
	return next(stash.glass) ~= nil
end

-- Dresses one shop box for a choice: `showItems` true = as the server built it,
-- false = no item, accent-tinted glass. Safe to call again with the same value,
-- and on a box that has been opened (BoxArt.Open took its windows and item).
-- Returns true when it changed something.
function BoxWindows.Apply(box: Instance, showItems: boolean): boolean
	local changed = false
	local stash = stashOf(box)
	if showItems then
		-- Put it back as the server made it.
		local contents = stash.contents
		if contents ~= nil then
			stash.contents = nil
			if box:FindFirstChild("Contents") == nil and box:GetAttribute("Open") ~= true then
				contents.Parent = box
				changed = true
			else
				contents:Destroy() -- the box was opened (or re-sent) meanwhile: the item is gone for good
			end
		end
		for pane, was in pairs(stash.glass) do
			stash.glass[pane] = nil
			if pane.Parent ~= nil and pane:IsA("BasePart") then
				pane.Color = was.color
				pane.Transparency = was.transparency
				changed = true
			end
		end
		return changed
	end
	-- LOWER: the item comes out; the glass takes the accent colour.
	local contents = box:FindFirstChild("Contents")
	if contents ~= nil then
		stash.contents = contents
		contents.Parent = nil
		changed = true
	end
	local accent = accentOf(box)
	for _, name in ipairs(BoxWindows.WindowNames) do
		local pane = box:FindFirstChild(name)
		if pane ~= nil and pane:IsA("BasePart") then
			if stash.glass[pane] == nil then
				stash.glass[pane] = { color = pane.Color, transparency = pane.Transparency }
			end
			if pane.Color ~= accent or math.abs(pane.Transparency - BoxWindows.TintTransparency) > 1e-3 then
				pane.Color = accent
				pane.Transparency = BoxWindows.TintTransparency
				changed = true
			end
		end
	end
	return changed
end

-- A box that has left the world (streamed out, destroyed): drop what was kept
-- for it, including the item copy that was taken out, so nothing lingers.
function BoxWindows.Forget(box: Instance)
	local stash = stashes[box]
	if stash == nil then
		return
	end
	stashes[box] = nil
	local contents = stash.contents
	if contents ~= nil then
		contents:Destroy()
	end
end

return BoxWindows
