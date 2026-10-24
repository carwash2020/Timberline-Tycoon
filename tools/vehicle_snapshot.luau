--!nocheck
-- Prints the colliding parts TruckArt builds for every truck and for every trailer behind each towing truck: name,
-- size and CFrame, rounded to 3 places, as JSON. tests/vehicle_collision_baseline.json is this output from main before
-- T421; tests/VehicleVisualParts.spec.luau compares a fresh build with it.
--   lune run tools/vehicle_snapshot > tests/vehicle_collision_baseline.json
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

assert(fs.isFile("rokit.toml"), "Run this from the repo root")
local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local ItemCatalog = modules:shared("ItemCatalog")
local TruckArt = modules:load("ReplicatedStorage/Shared/Art/TruckArt")
local TruckLayout = modules:shared("TruckLayout")

local function r(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end

local function snapshot(model: Instance): { string }
	local rows = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			local c = { d.CFrame:GetComponents() }
			local nums = {}
			for _, v in ipairs(c) do
				table.insert(nums, string.format("%.3f", r(v)))
			end
			table.insert(
				rows,
				string.format(
					"%s|%.3f,%.3f,%.3f|%s",
					d.Name,
					r(d.Size.X),
					r(d.Size.Y),
					r(d.Size.Z),
					table.concat(nums, ",")
				)
			)
		end
	end
	table.sort(rows)
	return rows
end

local out = {}
for _, truck in ipairs(ItemCatalog.TruckList()) do
	local lay = TruckLayout.For(truck)
	out["Truck/" .. truck.id] = snapshot(TruckArt.Build(truck, lay))
	for _, trailer in ipairs(ItemCatalog.TrailerList()) do
		if truck.look.bedLength > 0 then
			out["Rig/" .. truck.id .. "/" .. trailer.id] =
				snapshot(TruckArt.Build(truck, lay, trailer, TruckLayout.ForTrailer(trailer, lay)))
		end
	end
end
print(serde.encode("json", out, true))
