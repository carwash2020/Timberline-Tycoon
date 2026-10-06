--!strict
-- MenuPad: gamepad focus for a menu. Opening selects the first button.
-- B and Esc close it and give the selection back. Callers own when a menu
-- is open; the selection rules (select, trap in the panel, remember the HUD
-- button that opened it, return to it) are GamepadNav's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local GamepadNav = require(script.Parent.GamepadNav)

local MenuPad = {}

function MenuPad.Closes(key: Enum.KeyCode): boolean
	local cancel = InputKit.Actions.Cancel
	return key == cancel.gamepad or key == cancel.keyboard
end

-- Selects `button`. Give `root` (the panel) and the selection also stays
-- inside it until it closes; leave it off for a bar that sits among the HUD.
function MenuPad.Open(button: GuiObject?, root: GuiObject?)
	if button then
		GamepadNav.Focus(button, root)
	end
end

-- Gives the selection back when it is `root` or inside `root`: to the button
-- that opened the menu, else cleared. A nil root lets go of whatever is
-- selected.
function MenuPad.Close(root: Instance?)
	GamepadNav.Restore(root)
end

return MenuPad
