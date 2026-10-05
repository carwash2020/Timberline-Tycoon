--!strict
-- FerryController: draws Cap'n Moss's ferry smoothly on your device.
-- FerryService moves the boat with PivotTo on the server, and anchored
-- parts replicate in steps, so everyone saw it jerk across the water. The
-- crossing is a pure function of the server's clock (FerryLogic.PoseAt), so
-- every frame (RenderStepped, just before drawing) each device places the
-- boat itself where the schedule says it is.
--
-- The server stays in charge of everything that matters: fares, boarding,
-- the welds and the landing. It still keeps its own copy of the boat on the
-- schedule, nudged about 5 times a second (FerryLogic.ServerMoveHz) and
-- landed exactly at every departure and arrival, so what it decides about
-- the deck (who is aboard, where the riders are set down) matches what you
-- see within a fraction of a second.
--
-- Riders and loose planks are welded to the deck by the server. The weld
-- joins them into the deck's assembly, so moving the deck here carries them
-- with it on this device, and the server's own coarse steps (which land
-- before RenderStepped and are overwritten by it) never show. The client
-- only ever writes the boat's own CFrame, never a rider's. The boat only
-- follows the schedule when the server marks it ClientDriven; flipping
-- FerryLogic.ClientDriven to false puts the boat back on the server alone.
--
-- The clock offset (server time minus os.clock) is read once and then eased
-- toward fresh readings at FerryLogic.SlewRate, so a clock correction cannot
-- make the boat jump.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FerryLogic = require(ReplicatedStorage.Shared.FerryLogic)

local FerryController = {}

-- Studs: a boat this close to its scheduled spot is left alone.
local REST_EPSILON = 0.01

local boat: Model? = nil
local offset: number? = nil
local lastClock = os.clock()

local function track(inst: Instance)
	if inst:IsA("Model") then
		boat = inst
	end
end

local function untrack(inst: Instance)
	if boat == inst then
		boat = nil
	end
end

-- One frame: place the boat for server time `serverNow`. Returns whether it
-- was moved.
function FerryController.Place(model: Model, serverNow: number): boolean
	if model:GetAttribute(FerryLogic.DrivenAttribute) ~= true then
		return false
	end
	local x, z, yaw = FerryLogic.PoseAt(serverNow)
	local target = CFrame.new(x, FerryLogic.DeckY(), z) * CFrame.Angles(0, yaw, 0)
	local here = model:GetPivot()
	if
		(here.Position - target.Position).Magnitude < REST_EPSILON
		and here.LookVector:Dot(target.LookVector) > 0.99999
	then
		return false
	end
	model:PivotTo(target)
	return true
end

local function step()
	local model = boat
	local now = os.clock()
	local dt = now - lastClock
	lastClock = now
	if not model or not model.Parent then
		return
	end
	local fresh = workspace:GetServerTimeNow() - now
	local current = offset
	if current == nil then
		current = fresh
	else
		current = FerryLogic.SlewOffset(current, fresh, dt)
	end
	offset = current
	FerryController.Place(model, now + (current :: number))
end

function FerryController.Start()
	CollectionService:GetInstanceAddedSignal(FerryLogic.Tag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(FerryLogic.Tag):Connect(untrack)
	for _, inst in ipairs(CollectionService:GetTagged(FerryLogic.Tag)) do
		track(inst)
	end
	RunService.RenderStepped:Connect(step)
end

return FerryController
