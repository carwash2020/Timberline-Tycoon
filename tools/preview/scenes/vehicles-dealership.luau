--!nocheck
-- The Dealership's display copies (DealershipLot.Build: each truck and each
-- trailer on its plinth, the models the player walks past), real meshes where
-- the code dresses them. Four views per copy: three-quarter, the near side,
-- a wheel close up, and a low ground-level view. Views run in the order the
-- copies are listed in `order`.
-- DEALER_ONLY=Truck:Pickup (or Trailer:RanchTrailer ...) keeps only that copy
-- on its plinth and drops the other vehicles, so a close camera is not blocked
-- by the next bay (the lot, plinths, signs and lamps all stay). Without it the
-- whole row stands and every copy gets its four views.
local process = require("@lune/process")
local Vehicles = require("./_vehicles")
local only = process.env.DEALER_ONLY

local ORDER = {
	{ "Truck", "Rustbucket" },
	{ "Truck", "Pickup" },
	{ "Truck", "ScoutATV" },
	{ "Truck", "Flatbed" },
	{ "Truck", "LoggingRig" },
	{ "Trailer", "PonyTrailer" },
	{ "Trailer", "RanchTrailer" },
	{ "Trailer", "HeavyHauler" },
}

return {
	build = function(ctx)
		Vehicles.init(ctx)
		local roblox = ctx.roblox
		local V3, CF = roblox.Vector3, roblox.CFrame
		local Kit = ctx.art("Kit")
		local DealershipLot = ctx.art("DealershipLot")
		local root = roblox.Instance.new("Model")
		local lot = DealershipLot.Build()
		Kit.placeAt(lot, CF.new(0, 0, 0))
		lot.Parent = root

		local copies = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d:IsA("Model") and d:GetAttribute("Category") ~= nil then
				local key = tostring(d:GetAttribute("Category")) .. ":" .. tostring(d:GetAttribute("ItemId"))
				if only ~= nil and only ~= "" and key ~= only then
					d:Destroy()
				else
					copies[key] = d
				end
			end
		end
		local cameras = {}
		for _, entry in ipairs(ORDER) do
			local copy = copies[entry[1] .. ":" .. entry[2]]
			if copy then
				local lo, hi = Vehicles.boundsOf(copy)
				local c = (lo + hi) / 2
				local size = hi - lo
				local reach = math.max(size.X, size.Z)
				local label = "dealership " .. entry[2]
				-- The copy is turned on its plinth (any yaw): use its own frame.
				local pivot = copy:GetPivot()
				local side = pivot.RightVector * -1
				local along = pivot.LookVector
				local function view(pos, target, name, fov)
					table.insert(cameras, {
						pos = { pos.X, pos.Y, pos.Z },
						target = { target.X, target.Y, target.Z },
						label = label .. " - " .. name,
						fov = fov or 36,
					})
				end
				local ground = lo.Y -- the plinth's top: the copy stands on it
				local base = V3.new(c.X, ground + 4, c.Z)
				view(base + side * (reach * 0.9 + 12) - along * (reach * 0.55) + V3.new(0, 9, 0), base, "three-quarter")
				view(base + side * (reach * 1.1 + 12), base, "near side")
				-- The wheel farthest from the middle line (either side), shot from outside it.
				local wheel, out = nil, side
				for _, w in ipairs(copy:GetDescendants()) do
					if w.Name == "Wheel" and w:IsA("BasePart") then
						local p = w.CFrame.Position
						local off = (p - base):Dot(side)
						if wheel == nil or math.abs(off) > math.abs((wheel - base):Dot(side)) then
							wheel = p
							out = if off < 0 then side * -1 else side
						end
					end
				end
				wheel = wheel or c
				view(wheel + out * 9 + V3.new(0, 2.2, 0) - along * 4, wheel, "wheel close up", 40)
				view(
					V3.new(base.X, ground + 1.7, base.Z) - side * (reach * 0.55 + 9) - along * (reach * 0.4),
					V3.new(base.X, ground + 2.5, base.Z),
					"low",
					40
				)
			end
		end
		return {
			root = root,
			shadowRadius = 48,
			shadowFollow = true,
			fov = 36,
			hud = false,
			cameras = cameras,
		}
	end,
}
