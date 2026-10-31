--!strict
-- ScatterBuilder (T414d-2): the roadside stumps, large rocks, saplings and
-- snags Scatter plans, built once at boot. One template per kind, region and
-- variant, cloned for every item (Anchored by Kit). Stumps and rocks collide;
-- the rest are looks only. Pure decor, so streaming is Default (nothing here
-- is interactive). Ground cover under 4 studs is not built here: each client
-- builds it from the same seed (StarterPlayerScripts/ScatterCover).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Greenery = require(ReplicatedStorage.Shared.Art.Greenery)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local Scatter = require(ReplicatedStorage.Shared.World.Scatter)

local ScatterBuilder = {}

-- Returns the folder, and how many of each kind it holds.
function ScatterBuilder.Build(parent: Instance, slice: (() -> ())?): (Folder, { [string]: number })
	local folder = Instance.new("Folder")
	folder.Name = "Scatter"
	local templates: { [string]: Model } = {}
	local counts: { [string]: number } = {}
	local n = 0
	for _, item in ipairs(Scatter.Built(slice)) do
		local key = string.format("%s|%s|%d", item.kind, item.region, item.variant)
		local template = templates[key]
		if not template then
			local made = Greenery.Item(item.kind, item.region, item.variant, item.size)
			assert(made, "[ScatterBuilder] no model for " .. item.kind)
			made.Name = item.kind
			made:SetAttribute("Scatter", item.kind)
			templates[key] = made
			template = made
		end
		local model = template:Clone()
		Kit.placeAt(model, CFrame.new(item.x, item.y, item.z) * CFrame.Angles(0, item.yaw, 0))
		model.ModelStreamingMode = Enum.ModelStreamingMode.Default
		model.Parent = folder
		counts[item.kind] = (counts[item.kind] or 0) + 1
		n += 1
		if slice and n % 16 == 0 then
			slice()
		end
	end
	folder.Parent = parent
	return folder, counts
end

return ScatterBuilder
