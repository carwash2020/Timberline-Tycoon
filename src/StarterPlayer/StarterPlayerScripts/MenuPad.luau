--!strict
-- MenuPad: gamepad focus for a menu. Opening selects the first button.
-- B and Esc close it and clear that selection. Callers own when a menu
-- is open; this only moves GuiService.SelectedObject.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputKit = require(ReplicatedStorage.Shared.InputKit)

local MenuPad = {}

function MenuPad.Closes(key: Enum.KeyCode): boolean
	local cancel = InputKit.Actions.Cancel
	return key == cancel.gamepad or key == cancel.keyboard
end

function MenuPad.Open(button: GuiObject?)
	if button then
		GuiService.SelectedObject = button
	end
end

-- Clears the selection when it is `root` or inside `root`. A nil root
-- clears whatever is selected.
function MenuPad.Close(root: Instance?)
	local selected = GuiService.SelectedObject
	if not selected then
		return
	end
	if root == nil or selected == root or selected:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

return MenuPad
