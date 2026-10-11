--!strict
-- ShopInterior: what goes inside a shop once BuildingArt has built and
-- scaled it. It only DISPATCHES: each store's interior is its own module in
-- Shared/Art/ShopInteriors/ (ToolShed, HearthAndHome, Sparkworks, Dealership),
-- all built from the one kit, Shared/Art/ShopKit (signs, tier stands, counter
-- sign, lights, beams, mesh props). Everything is in FINAL studs from the
-- shop's origin (ground y = 0, the door on -Z); nothing here is scaled again.

local ShopKit = require(script.Parent.ShopKit)
local Dealership = require(script.Parent.ShopInteriors.Dealership)
local HearthAndHome = require(script.Parent.ShopInteriors.HearthAndHome)
local Sparkworks = require(script.Parent.ShopInteriors.Sparkworks)
local ToolShed = require(script.Parent.ShopInteriors.ToolShed)

local ShopInterior = {}

export type Frame = ShopKit.Frame
export type Bay = Dealership.Bay

-- Re-exported for the older callers (ShelfLayout.spec reads the rack's gap).
ShopInterior.SteppedUnit = ShopKit.SteppedUnit
ShopInterior.RackGap = ToolShed.RackGap

-- Adds the interior. `frame` is the shop's final-stud frame (see Frame);
-- for the Dealership `extra` is the showroom's inner west x, east x, front
-- z and back z.
function ShopInterior.Add(model: Model, kind: string, frame: Frame, extra: { number }?, bays: { Bay }?)
	if kind == "ToolShed" then
		ToolShed.Build(model, frame)
	elseif kind == "HearthAndHome" then
		HearthAndHome.Build(model, frame)
	elseif kind == "Sparkworks" then
		Sparkworks.Build(model, frame)
	elseif kind == "Dealership" then
		local span = extra or { -frame.halfW, frame.halfW, -frame.halfD, frame.halfD }
		Dealership.Build(model, frame, span[1], span[2], span[3], span[4], bays or {})
	end
end

return ShopInterior
