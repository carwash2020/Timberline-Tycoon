--!strict
-- ScatterCover (T414d-2): the roadside ground cover (grass, ferns, shrubs,
-- flowers, pebbles, reeds, scrub), built on this client only from Scatter's
-- seeded plan. Nothing is replicated: every player works out the same
-- meadow. Within Scatter.CoverRadius of the camera (160 on high) a 32-stud
-- cell holds its models, thinning in two steps to nothing at the radius;
-- the rest is unloaded.
--   * It starts after the player can play and the deferred controllers have
--     started, plans on a time slice, then builds cells nearest first within
--     the frame budget (like GrassTufts).
--   * One template per kind, region and variant (Greenery.Cover), cloned for
--     every item. Cover never collides, is not queried or touched, casts no
--     shadow (Greenery), and so cannot block a truck, a log or a door.
-- Everything lives in the workspace folder "ScatterCover".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientBoot = require(ReplicatedStorage.Shared.ClientBoot)
local FrameBudget = require(ReplicatedStorage.Shared.FrameBudget)
local Greenery = require(ReplicatedStorage.Shared.Art.Greenery)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local Scatter = require(ReplicatedStorage.Shared.World.Scatter)
local TimeSlice = require(ReplicatedStorage.Shared.TimeSlice)
local Quality = require(script.Parent.Quality)

local ScatterCover = {}

local CELL = 32
local SCAN_EVERY = 0.5
local MOVED_FAR = 24
local UNLOADS_PER_FRAME = 8
local HYSTERESIS = 24 -- studs a loaded cell keeps past the radius
local FADE = { 0, 0.45, 0.8 } -- transparency by band: inside the fade, the first half of it, the rest

type Cell = { items: { Scatter.Item }, folder: Folder?, band: number }

local cells: { [number]: Cell } = {}
local templates: { [string]: Model } = {}
local queue: { { key: number, d: number } } = {}
local unloads: { number } = {}
local lastScanAt: Vector3? = nil
local planned = false
local container: Folder? = nil

local function root(): Folder
	local f = container
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "ScatterCover"
	made.Parent = workspace
	container = made
	return made
end

local function keyOf(cx: number, cz: number): number
	return (cx + 512) * 1024 + (cz + 512)
end

local function centreOf(key: number): (number, number)
	local cx, cz = math.floor(key / 1024) - 512, key % 1024 - 512
	return (cx + 0.5) * CELL, (cz + 0.5) * CELL
end

local function template(item: Scatter.Item): Model?
	local k = string.format("%s|%s|%d", item.kind, item.region, item.variant)
	local t = templates[k]
	if t then
		return t
	end
	local made = Greenery.Cover(item.kind, item.region, item.variant)
	if made then
		templates[k] = made
	end
	return made
end

local function setBand(cell: Cell, band: number)
	cell.band = band
	local f = cell.folder
	if not f then
		return
	end
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = FADE[band]
		end
	end
end

local function build(key: number, band: number)
	local cell = cells[key]
	if not cell or cell.folder then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "cover " .. key
	for _, item in ipairs(cell.items) do
		local t = template(item)
		if t then
			local m = t:Clone()
			Kit.placeAt(m, CFrame.new(item.x, item.y, item.z) * CFrame.Angles(0, item.yaw, 0))
			m.Parent = f
		end
	end
	f.Parent = root()
	cell.folder = f
	setBand(cell, band)
end

local function bandFor(d: number, radius: number): number
	local from = radius * Scatter.FadeFrom
	if d <= from then
		return 1
	elseif d <= from + (radius - from) / 2 then
		return 2
	end
	return 3
end

local function scan()
	local camera = workspace.CurrentCamera
	if not camera or not planned then
		return
	end
	local p = camera.CFrame.Position
	lastScanAt = p
	local radius = Scatter.CoverRadius[Quality.Tier()] or Scatter.CoverRadius.high
	table.clear(queue)
	table.clear(unloads)
	for key, cell in pairs(cells) do
		local cx, cz = centreOf(key)
		local d = math.sqrt((cx - p.X) ^ 2 + (cz - p.Z) ^ 2) - CELL * 0.7 -- to the cell's near edge, about
		if d > radius + HYSTERESIS then
			if cell.folder then
				table.insert(unloads, key)
			end
		elseif d <= radius then
			local band = bandFor(math.max(d, 0), radius)
			if not cell.folder then
				table.insert(queue, { key = key, d = d })
			elseif band ~= cell.band then
				setBand(cell, band)
			end
		end
	end
	table.sort(queue, function(a, b)
		return a.d > b.d
	end)
end

local function work(frameDt: number)
	local n = 0
	while #unloads > 0 and n < UNLOADS_PER_FRAME do
		local key = table.remove(unloads) :: number
		local cell = cells[key]
		if cell and cell.folder then
			cell.folder:Destroy()
			cell.folder = nil
		end
		n += 1
	end
	local shape = Quality.Budget()
	local budget = FrameBudget.Adapt(shape.TuftBuildMs, frameDt, 1 / math.max(shape.CosmeticHz, 1)) / 1000
	local started = os.clock()
	local built = 0
	local camera = workspace.CurrentCamera
	local radius = Scatter.CoverRadius[Quality.Tier()] or Scatter.CoverRadius.high
	while #queue > 0 and (built == 0 or os.clock() - started < budget) do
		built += 1
		local job = table.remove(queue) :: { key: number, d: number }
		local cx, cz = centreOf(job.key)
		local d = if camera
			then math.sqrt((cx - camera.CFrame.Position.X) ^ 2 + (cz - camera.CFrame.Position.Z) ^ 2)
			else 0
		build(job.key, bandFor(math.max(d - CELL * 0.7, 0), radius))
	end
end

-- Waits until the player is in the game (the loading card gone) and the deferred controllers have
-- started, so nothing here lands on the load (at most WAIT_READY seconds). Shared with RoadCritters.
local WAIT_READY = 40
local BOOT_WAIT = 10
function ScatterCover.WaitUntilPlaying()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	local startedWaiting = os.clock()
	while os.clock() - startedWaiting < WAIT_READY do
		if player:GetAttribute("ProfileLoaded") == true and player.Character ~= nil then
			break
		end
		task.wait(0.25)
	end
	local boot = ClientBoot.Default
	local bootWaited = os.clock()
	while boot.Released() and not boot.Drained() and os.clock() - bootWaited < BOOT_WAIT do
		task.wait()
	end
	task.wait(1.5)
end

function ScatterCover.Start()
	task.spawn(function()
		ScatterCover.WaitUntilPlaying()
		local slice = TimeSlice.new({ budget = 0.008 })
		local ok, err = pcall(function()
			for _, item in ipairs(Scatter.Cover(slice.step)) do
				local key = keyOf(math.floor(item.x / CELL), math.floor(item.z / CELL))
				local cell = cells[key]
				if not cell then
					cell = { items = {}, folder = nil, band = 1 }
					cells[key] = cell
				end
				table.insert(cell.items, item)
			end
		end)
		slice.finish()
		if not ok then
			warn("[ScatterCover] the plan failed, no roadside cover: " .. tostring(err))
			return
		end
		planned = true
		local sinceScan = math.huge
		local sinceCosmetic = 0
		RunService.Heartbeat:Connect(function(dt: number)
			sinceCosmetic += dt
			local hz = Quality.Budget().CosmeticHz
			if sinceCosmetic < 1 / math.max(hz, 1) - 1e-3 and hz < 60 then
				return
			end
			local step = sinceCosmetic
			sinceCosmetic = 0
			sinceScan += step
			local camera = workspace.CurrentCamera
			local moved = if camera and lastScanAt
				then (camera.CFrame.Position - lastScanAt).Magnitude > MOVED_FAR
				else true
			if sinceScan >= SCAN_EVERY or moved then
				sinceScan = 0
				scan()
			end
			work(dt)
		end)
	end)
end

return ScatterCover
