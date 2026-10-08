--!strict
-- DropControls: how you put down the axe (or rolled plan) in your hand,
-- as plain rules (no Instances), so tests can check them. There is no
-- on-screen Drop button; every device has its own way, the way a Roblox
-- game does it:
--   * gamepad: B (ButtonB);
--   * keyboard: Q, and Backspace (Roblox's own drop key) still works;
--   * phone: Roblox's hotbar is the engine's own, so a slot can't carry a
--     button. A tap on the equipped slot puts the item away (Roblox does
--     that), and a long press on the hotbar's strip drops what is in hand.
-- Dropping needs the same things the button needed (HudRules.DropAxe says
-- an axe may go; a plan always may) and the same two presses
-- (HudRules.DropPress); the server still checks ownership, the rate and
-- that it is not your last axe (AxeService.Drop, BlueprintService.Drop).
--
-- B is also "back" everywhere: menus, dialogue, the placer, the wiring
-- tool, a held piece. Decide() says whose press it is: the drop only gets
-- it when nothing of those is up. A menu that closes on B sinks the press
-- (ContextActionService), and the drop is bound below every menu
-- (DropControls.Priority), so the same press is never handled twice.

local DropControls = {}

export type Device = "phone" | "desktop" | "console"

-- What is going on when a drop key is pressed.
export type State = {
	holding: boolean, -- an axe that may go, or a plan, is in hand
	typing: boolean, -- a text box has focus (the chat)
	menu: boolean, -- a panel, popup, shop, quick menu or the pad's selection is up
	dialogue: boolean, -- an NPC's dialogue box is open
	placing: boolean, -- the placer or the wiring tool is up
	grabbing: boolean, -- a piece of wood or a box is held
	seated: boolean, -- in a seat (driving a truck)
}

export type Verdict = "drop" | "close" | "ignore"

-- Below every menu's own close bind (a plain bind is Medium, 2000; High is 3000, the quick
-- menu High + 200): by the time the drop sees a press, nothing above has
-- sunk it.
DropControls.Priority = Enum.ContextActionPriority.Low.Value
DropControls.PadKey = Enum.KeyCode.ButtonB
DropControls.KeyboardKeys = { Enum.KeyCode.Q, Enum.KeyCode.Backspace } :: { Enum.KeyCode }

-- A long press on the phone's hotbar: the middle of the bottom edge, clear
-- of the thumbstick (left) and the jump button (right).
DropControls.HotbarBand = { left = 0.3, right = 0.7, top = 0.78 }

-- A second press on the same item this long after the first still counts
-- even if the first long press put the item away (the slot is a toggle).
DropControls.RecentSeconds = 3

-- Which device a drop key belongs to (nil: not a drop key).
function DropControls.DeviceOf(key: Enum.KeyCode): Device?
	if key == DropControls.PadKey then
		return "console"
	end
	for _, k in ipairs(DropControls.KeyboardKeys) do
		if key == k then
			return "desktop"
		end
	end
	return nil
end

-- Whether the press is the drop's, belongs to something that is open
-- ("close": B is that layer's back button, let it have the press), or is
-- nothing to do with the drop ("ignore"). Only B is ever "close"; Q and
-- Backspace mean other things in a layer, or nothing.
function DropControls.Decide(key: Enum.KeyCode, state: State): Verdict
	if DropControls.DeviceOf(key) == nil or state.typing then
		return "ignore"
	end
	local layer = state.menu or state.dialogue or state.placing or state.grabbing
	if layer then
		return if key == DropControls.PadKey then "close" else "ignore"
	end
	if state.seated or not state.holding then
		return "ignore"
	end
	return "drop"
end

-- Whether a point (pixels) on a screen of `width` x `height` is on the
-- hotbar's strip.
function DropControls.InHotbarBand(x: number, y: number, width: number, height: number): boolean
	if width <= 0 or height <= 0 then
		return false
	end
	local band = DropControls.HotbarBand
	return x >= width * band.left and x <= width * band.right and y >= height * band.top and y <= height
end

-- A long press on a phone: the drop's when it is on the hotbar strip and
-- the same things that stop a key stop it. `state.holding` is true while
-- the item is in hand or was put away by this very long press (the slot
-- toggles), see RecentSeconds.
function DropControls.TouchDrops(x: number, y: number, width: number, height: number, state: State): boolean
	if not DropControls.InHotbarBand(x, y, width, height) then
		return false
	end
	if state.typing or state.menu or state.dialogue or state.placing or state.grabbing or state.seated then
		return false
	end
	return state.holding
end

-- The line that tells you how, for `device` (the HUD shows it the first
-- time you hold something you may drop).
function DropControls.Hint(device: Device): string
	if device == "console" then
		return "Press B twice to drop it"
	elseif device == "phone" then
		return "Long-press its slot twice to drop it"
	end
	return "Press Q twice to drop it"
end

-- What the first press says while the second is awaited (HudRules.DropPress).
function DropControls.Confirm(device: Device, name: string): string
	local again = if device == "console"
		then "Press B again"
		elseif device == "phone" then "Long-press again"
		else "Press Q again"
	return string.format("%s to drop the %s.", again, name)
end

return DropControls
