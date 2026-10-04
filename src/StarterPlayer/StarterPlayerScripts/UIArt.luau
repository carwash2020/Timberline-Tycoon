--!strict
-- UIArt: the HUD skins. Asset ids live only here. These are Image ids
-- (a Decal id does not load when a script sets ImageLabel.Image). Each
-- source is 256x256. sliceCenter is the flat Paper (#F0E1C3) center, and
-- the border on screen is that margin times sliceScale (4 px on the
-- plaque, 12 px on the panel and the buttons).

local UIArt = {}

export type Skin = {
	id: string,
	sliceCenter: Rect,
	sliceScale: number,
}

local function entry(id: string, minX: number, minY: number, maxX: number, maxY: number, sliceScale: number): Skin
	return {
		id = id,
		sliceCenter = Rect.new(minX, minY, maxX, maxY),
		sliceScale = sliceScale,
	}
end

local skins: { [string]: Skin } = {
	Plaque = entry("rbxassetid://139841387610705", 24, 24, 232, 232, 1 / 6),
	Panel = entry("rbxassetid://90740664574742", 48, 48, 208, 208, 0.25),
	Button = entry("rbxassetid://72427678124813", 48, 48, 208, 208, 0.25),
	ButtonPressed = entry("rbxassetid://74100852047057", 48, 48, 208, 208, 0.25),
}

UIArt.Plaque = skins.Plaque
UIArt.Panel = skins.Panel
UIArt.Button = skins.Button
UIArt.ButtonPressed = skins.ButtonPressed

UIArt.Names = { "Plaque", "Panel", "Button", "ButtonPressed" }

function UIArt.Get(name: string): Skin?
	return skins[name]
end

-- How far the flat center sits in from the edge, in screen pixels.
function UIArt.Inset(art: Skin): number
	return math.ceil(art.sliceCenter.Min.X * art.sliceScale - 1e-6)
end

-- One preload per id, started below and never from a card build. A card
-- reads Status and returns immediately: Success is already skinned,
-- Pending stays flat until Listen fires, Failure stays flat.
export type LoadStatus = "Pending" | "Success" | "Failure"

local loaded: { [string]: LoadStatus } = {}
local waiters: { [string]: { (LoadStatus) -> () } } = {}

function UIArt.Status(id: string): LoadStatus?
	return loaded[id]
end

local function settle(id: string, nextStatus: LoadStatus)
	local current = loaded[id]
	if current == "Success" or current == "Failure" then
		return
	end
	loaded[id] = nextStatus
	local list = waiters[id]
	waiters[id] = nil
	if list then
		for _, fn in ipairs(list) do
			fn(nextStatus)
		end
	end
end

-- Off the build. `task.spawn` when the runtime has it (the game, and the
-- specs that stub spawn). A stub that replaces `task` and leaves spawn
-- out still preloads, inline, so requiring UIArt does not throw there.
local function later(fn: () -> ())
	local runner = if type(task) == "table" then task.spawn else nil
	if runner ~= nil then
		runner(fn)
	else
		fn()
	end
end

local function preload(id: string)
	if id == "" or loaded[id] ~= nil then
		return
	end
	loaded[id] = "Pending"
	later(function()
		local ContentProvider = game:GetService("ContentProvider")
		ContentProvider:PreloadAsync({ id }, function(_contentId: string, fetchStatus: Enum.AssetFetchStatus)
			local nextStatus: LoadStatus = if fetchStatus == Enum.AssetFetchStatus.Success then "Success" else "Failure"
			settle(id, nextStatus)
		end)
	end)
end

-- Calls `fn` now when this id has already settled, or once when it does.
-- A second result is ignored. Pending never calls `fn` before the preload.
function UIArt.Listen(id: string, fn: (LoadStatus) -> ())
	local current = loaded[id]
	if current == "Success" or current == "Failure" then
		fn(current)
		return
	end
	local list = waiters[id]
	if list == nil then
		list = {}
		waiters[id] = list
	end
	table.insert(list, fn)
	if current == nil then
		preload(id)
	end
end

for _, name in ipairs(UIArt.Names) do
	local art = skins[name]
	if art then
		preload(art.id)
	end
end

return UIArt
