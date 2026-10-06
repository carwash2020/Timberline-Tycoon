--!strict
-- HudNav: the HUD's persistent buttons (STORE, SAVES, BADGES, the Daily
-- Goals pill, the Field Guide, Settings, the clock, the side column, the
-- tutorial's Skip ...) as one set a gamepad can walk, and the list the
-- quick menu draws its tiles from.
--
-- Roblox starts a gamepad's selection from its own core UI or the topmost
-- object, so with no help it hops across the screen. Here every HUD button
-- registers once (HudNav.Add). Whenever the selection lands on one, the
-- visible ones are linked to each other (NextSelectionUp/Down/Left/Right)
-- by where they are on screen right now (Shared/GamepadNavLogic.Links:
-- nearest neighbour, wrapping round the edges), and HudNav.Focus puts the
-- selection on the first one in reading order. The links are rebuilt from
-- the layout each time, so a button that appears, hides or moves is
-- handled the same way. Panels keep the selection inside themselves
-- (GamepadNav.Focus), so these links only matter on the HUD.
--
-- A button that opens something registers a label and a `press` too, which
-- makes it a tile in the quick menu (QuickMenuUI).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamepadNavLogic = require(ReplicatedStorage.Shared.GamepadNavLogic)
local QuickMenuLogic = require(ReplicatedStorage.Shared.QuickMenuLogic)
local GamepadNav = require(script.Parent.GamepadNav)

local HudNav = {}

export type Options = {
	id: string?, -- a stable name ("saves"); defaults to the object's name
	label: string?, -- the quick menu's tile text; none = not a tile
	labelOf: (() -> string)?, -- or read it when the menu opens (a button whose text changes)
	press: (() -> ())?, -- what the tile does (what pressing the button does)
	shown: (() -> boolean)?, -- an extra "is it there" test (default: it is on screen)
}

type Item = {
	obj: GuiObject,
	id: string,
	label: string?,
	labelOf: (() -> string)?,
	press: (() -> ())?,
	shown: (() -> boolean)?,
}

export type Entry = { id: string, label: string, press: () -> (), obj: GuiObject }

local items: { Item } = {}
local byObject: { [GuiObject]: Item } = {}

local DIRECTIONS: { [string]: string } = {
	up = "NextSelectionUp",
	down = "NextSelectionDown",
	left = "NextSelectionLeft",
	right = "NextSelectionRight",
}

-- Registers a HUD button: `obj` must be the Selectable object a press lands
-- on (a Button's `face`), not its frame.
function HudNav.Add(obj: GuiObject, options: Options?)
	if byObject[obj] then
		return
	end
	local opts: Options = options or {}
	local base = opts.id or string.lower(obj.Name)
	local id = base
	local n = 1
	for _, other in ipairs(items) do
		if other.id == id then
			n += 1
			id = base .. tostring(n)
		end
	end
	local item: Item = {
		obj = obj,
		id = id,
		label = opts.label,
		labelOf = opts.labelOf,
		press = opts.press,
		shown = opts.shown,
	}
	table.insert(items, item)
	byObject[obj] = item
	-- A button that is destroyed leaves the set (guarded: a stand-in object in a
	-- test may have no Destroying signal).
	pcall(function()
		obj.Destroying:Connect(function()
			HudNav.Remove(obj)
		end)
	end)
end

function HudNav.Remove(obj: GuiObject)
	local item = byObject[obj]
	if not item then
		return
	end
	byObject[obj] = nil
	local at = table.find(items, item)
	if at then
		table.remove(items, at)
	end
end

function HudNav.Contains(obj: Instance?): boolean
	return obj ~= nil and byObject[obj :: GuiObject] ~= nil
end

local function present(item: Item): boolean
	if not GamepadNav.Landable(item.obj) then
		return false
	end
	local extra = item.shown
	return extra == nil or extra()
end

-- The buttons on screen now, as rectangles (and which item each is).
local function nodes(): ({ GamepadNavLogic.Node }, { [string]: Item })
	local list: { GamepadNavLogic.Node } = {}
	local byId: { [string]: Item } = {}
	for _, item in ipairs(items) do
		if present(item) then
			local pos, size = item.obj.AbsolutePosition, item.obj.AbsoluteSize
			table.insert(list, { id = item.id, x = pos.X, y = pos.Y, w = size.X, h = size.Y })
			byId[item.id] = item
		end
	end
	return list, byId
end

-- Links the visible buttons to each other by where they are on screen, and
-- clears the links of the ones that are not there.
function HudNav.Relink()
	local list, byId = nodes()
	local links = GamepadNavLogic.Links(list, true)
	for _, item in ipairs(items) do
		local link = links[item.id]
		for dir, property in pairs(DIRECTIONS) do
			local target: GuiObject? = nil
			if link and byId[item.id] then
				local id = (link :: any)[dir]
				local other = if id then byId[id] else nil
				target = if other then other.obj else nil
			end
			-- (A property write is a no-op when it is unchanged.)
			(item.obj :: any)[property] = target
		end
	end
end

-- The first visible button in reading order, or nil.
function HudNav.First(): GuiObject?
	local list, byId = nodes()
	local first = GamepadNavLogic.First(list)
	local item = if first then byId[first.id] else nil
	return if item then item.obj else nil
end

-- Puts the selection on the first HUD button (linking them first).
-- Returns whether there was one.
function HudNav.Focus(): boolean
	HudNav.Relink()
	local first = HudNav.First()
	if first then
		GuiService.SelectedObject = first
		return true
	end
	return false
end

-- Lets go of the selection when it is on a HUD button: walking again.
function HudNav.Release(): boolean
	local selected = GuiService.SelectedObject
	if selected and HudNav.Contains(selected) then
		GuiService.SelectedObject = nil
		return true
	end
	return false
end

-- Whether the selection is on a HUD button right now.
function HudNav.OnHud(): boolean
	return HudNav.Contains(GuiService.SelectedObject)
end

-- The quick menu's destinations: every visible button that gave a label and
-- a press, in tile order.
function HudNav.Entries(): { Entry }
	local found: { Entry } = {}
	local plain: { QuickMenuLogic.Entry } = {}
	local byId: { [string]: Entry } = {}
	for _, item in ipairs(items) do
		local press = item.press
		local label = if item.labelOf then item.labelOf() else item.label
		if label and label ~= "" and press and present(item) then
			local entry: Entry = { id = item.id, label = label, press = press, obj = item.obj }
			byId[item.id] = entry
			table.insert(plain, { id = item.id, label = label })
		end
	end
	for _, sorted in ipairs(QuickMenuLogic.Sort(plain)) do
		table.insert(found, byId[sorted.id])
	end
	return found
end

-- Starts watching the selection: whenever it lands on a HUD button, the
-- links are rebuilt from where the buttons are now. Called once (Client).
local started = false
function HudNav.Start()
	if started then
		return
	end
	started = true
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		if HudNav.OnHud() then
			HudNav.Relink()
		end
	end)
end

return HudNav
