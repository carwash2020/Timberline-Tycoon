--!strict
-- GamepadNav: one way for every panel to take, hold and give back the
-- gamepad's selection (GuiService.SelectedObject), so a panel does not carry
-- its own version:
--   * Focus(first, root): opening a panel. Selects its first control (so A
--     works at once), traps the selection in `root` (SelectionGroup, and
--     Stop on every side, so the stick can't drift out onto the HUD behind
--     it), and remembers the button that opened it.
--   * Restore(root): closing it. The selection goes back to that button, or
--     is let go (walking again) when there was none. If the player moved
--     the selection elsewhere meanwhile, it is left alone.
--   * Trap(root): the trap alone, for a panel that picks its own first
--     control.
--   * ReturnTo(button) / WithReturn(button, fn): the quick menu opens a
--     destination on the player's behalf and names the HUD button the
--     panel should return to, instead of the (closed) menu.
-- It never reads the device: callers that only want a ring on a gamepad
-- check HudRules.PadSelects first, as before. The decisions are
-- Shared/GamepadNavLogic's. B and Esc close panels through MenuPad.Closes.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamepadNavLogic = require(ReplicatedStorage.Shared.GamepadNavLogic)

local GamepadNav = {}

type Entry = { root: GuiObject?, first: GuiObject?, opener: GuiObject? }

local stack: { Entry } = {}
local returnTo: GuiObject? = nil

local function alive(obj: Instance?): boolean
	return obj ~= nil and obj.Parent ~= nil
end

-- True when `inst` is `root` or inside it.
local function within(inst: Instance?, root: Instance?): boolean
	if inst == nil or root == nil then
		return false
	end
	return inst == root or inst:IsDescendantOf(root)
end

-- Whether `obj` can be landed on now: still in the tree, itself and all it
-- sits in visible and enabled.
function GamepadNav.Landable(obj: GuiObject): boolean
	if not alive(obj) then
		return false
	end
	local node: Instance? = obj
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("ScreenGui") and not node.Enabled then
			return false
		end
		node = node.Parent
	end
	return obj.Selectable
end

-- A panel's selection stays in it: a group, and no way out on any side.
function GamepadNav.Trap(root: GuiObject?)
	if not root then
		return
	end
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
end

-- Names the HUD button the next Focus remembers as the way back.
function GamepadNav.ReturnTo(button: GuiObject?)
	returnTo = button
end

-- Runs `fn` (which opens a panel) with `button` as the way back.
function GamepadNav.WithReturn(button: GuiObject?, fn: () -> ())
	returnTo = button
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	returnTo = nil
	if not ok then
		warn("[GamepadNav] " .. tostring(err))
	end
end

-- Panels that were torn down without a Restore (a rebuilt screen) leave
-- nothing behind.
local function prune()
	for i = #stack, 1, -1 do
		local entry = stack[i]
		local gone = (entry.root ~= nil and not alive(entry.root)) or (entry.root == nil and not alive(entry.first))
		if gone then
			table.remove(stack, i)
		end
	end
end

local function find(root: Instance?, first: Instance?): number?
	for i = #stack, 1, -1 do
		local entry = stack[i]
		if root ~= nil and (entry.root == root or within(entry.first, root) or within(entry.root, root)) then
			return i
		end
		if root == nil and first ~= nil and entry.first == first then
			return i
		end
	end
	return nil
end

-- Opens a panel for the gamepad: select `first`, hold the selection inside
-- `root` (when given), and remember what opened it. Calling it again for
-- a panel that is already open (a redraw) only moves the selection.
function GamepadNav.Focus(first: GuiObject?, root: GuiObject?)
	if root then
		GamepadNav.Trap(root)
	end
	prune()
	local at = find(root, first)
	if at then
		stack[at].first = first
	else
		local selected = GuiService.SelectedObject
		local panel: Instance? = root or first
		local opener = GamepadNavLogic.Opener(returnTo, selected, within(selected, panel))
		table.insert(stack, { root = root, first = first, opener = opener })
	end
	returnTo = nil
	if first then
		GuiService.SelectedObject = first
	end
end

-- Closes a panel for the gamepad. `root` is the panel (or the control that
-- was focused, or nil for the most recent): the selection goes back to the
-- button that opened it when it was inside, else is let go.
function GamepadNav.Restore(root: Instance?)
	local at = find(root, nil)
	if at == nil and root == nil then
		at = #stack
		if at == 0 then
			at = nil
		end
	end
	local entry: Entry? = if at then table.remove(stack, at) else nil
	local selected = GuiService.SelectedObject
	local panel: Instance? = root
	if entry then
		panel = entry.root or entry.first or root
	end
	-- Closing with no panel named lets go of whatever is selected.
	local inside = selected ~= nil and (root == nil or within(selected, panel) or within(selected, root))
	local opener = if entry then entry.opener else nil
	local verdict = GamepadNavLogic.Restore(
		if opener then { shown = GamepadNav.Landable(opener), selectable = true } else nil,
		inside,
		selected == nil
	)
	if verdict == "opener" and opener then
		GuiService.SelectedObject = opener
	elseif verdict == "clear" then
		GuiService.SelectedObject = nil
	end
end

-- Whether a panel opened through Focus is still open (tests, and callers
-- that must not open a second one).
function GamepadNav.Depth(): number
	return #stack
end

-- Forgets every open panel (a respawn, a test).
function GamepadNav.Reset()
	table.clear(stack)
	returnTo = nil
end

return GamepadNav
