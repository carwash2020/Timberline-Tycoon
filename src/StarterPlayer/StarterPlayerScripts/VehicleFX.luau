--!strict
-- VehicleFX: truck cosmetics on every client, for every truck streamed in
-- (CollectionService "Truck" tag, added and removed as trucks stream in and
-- out or get rebuilt). Nothing here replicates or touches physics:
--   * Wheels roll with the truck's speed and the front ones steer with the
--     seat's SteerFloat, through each wheel's Motor6D "Axle" Transform
--     (TruckArt.Rig), on PreSimulation like an Animator would.
--   * Dust kicks up behind the rearmost wheels when a truck goes fast on
--     dirt, sand, snow or ash (a ray down every quarter second finds the
--     ground's material; Shared/VehicleLogic picks the colour).
--   * Headlights glow while someone drives; at night (workspace attribute
--     "IsNight", WorldClock) they also throw SpotLights. Taillights brighten
--     when braking.
--   * Exhausts puff with the throttle; the Rustbucket's "Smoke" is heavier.
--   * A looping engine sound, if SoundData has an "Engine" entry.
--   * The "Drive" prompt shows only on your own truck (the server refuses
--     anyone else anyway).
-- Trucks further than FX_RANGE from the camera are left still.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local TruckArt = require(ReplicatedStorage.Shared.Art.TruckArt)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local Quality = require(script.Parent.Quality)

local VehicleFX = {}

local player = Players.LocalPlayer

local TRUCK_TAG = "Truck"
local FX_RANGE = 220 -- studs from the camera
local DUST_CHECK = 0.25 -- seconds between ground checks
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local HEAD_ON = TruckArt.HeadlightColor
local HEAD_OFF = Color3.fromRGB(128, 122, 104)
local TAIL_ON = TruckArt.TaillightColor
local TAIL_OFF = Color3.fromRGB(82, 24, 20)
local TAIL_BRAKE = Color3.fromRGB(255, 62, 46)

-- Engine pitch per truck (the Rig rumbles, the ATV buzzes).
local ENGINE_PITCH: { [string]: number } = {
	Rustbucket = 0.8,
	Pickup = 1,
	ScoutATV = 1.35,
	Flatbed = 0.9,
	LoggingRig = 0.65,
}

type Wheel = {
	joint: Motor6D,
	part: BasePart,
	radius: number,
	steer: boolean,
	spin: number,
}

type Puff = { emitter: ParticleEmitter, smoke: number }

type Dust = { emitter: ParticleEmitter, wheel: Wheel, color: Color3? }

type Rig = {
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat?,
	wheels: { Wheel },
	heads: { BasePart },
	tails: { BasePart },
	beams: { SpotLight },
	puffs: { Puff },
	dust: { Dust },
	engine: Sound?,
	pitch: number,
	topSpeed: number,
	lastPos: Vector3,
	speed: number,
	steer: number,
	dustTimer: number,
	wheelsIdle: boolean, -- parked and already drawn at rest: skip the wheels
	lit: boolean?, -- the lights' last state: nil = never set
	braking: boolean,
	night: boolean,
	conns: { RBXScriptConnection },
}

local rigs: { [Model]: Rig } = {}
local isNight = false

local function rayParams(model: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true
	return params
end

-- The face of `part` that looks most along `dir` (world).
local function faceToward(part: BasePart, dir: Vector3): Enum.NormalId
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
		local normal = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
		local d = normal:Dot(dir)
		if d > bestDot then
			best, bestDot = face, d
		end
	end
	return best
end

local function smokeEmitter(parent: Attachment, color: Color3, amount: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "ExhaustSmoke"
	e.Texture = SMOKE_TEXTURE
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0
	e.LightInfluence = 1
	local size = 0.5 + amount
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3 * size),
		NumberSequenceKeypoint.new(1, 1.8 * size),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(1, 1.8)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(14, 14)
	e.Acceleration = Vector3.new(0, 2.5, 0)
	e.Drag = 1.5
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Rotation = NumberRange.new(0, 360)
	e.EmissionDirection = Enum.NormalId.Top -- ExhaustOut's +Y points out of the pipe
	e.Rate = 0
	e.Parent = parent
	return e
end

local function dustEmitter(parent: Attachment): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "WheelDust"
	e.Texture = SMOKE_TEXTURE
	e.LightInfluence = 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 3.6),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(35, 20)
	e.Acceleration = Vector3.new(0, 1.2, 0)
	e.Drag = 2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.EmissionDirection = Enum.NormalId.Back -- behind the truck
	e.Enabled = false
	e.Rate = 12
	e.Parent = parent
	return e
end

local function hidePrompt(prompt: ProximityPrompt, conns: { RBXScriptConnection })
	prompt.Enabled = false
	table.insert(
		conns,
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			if prompt.Enabled then
				prompt.Enabled = false -- the server re-enabled it for its owner
			end
		end)
	)
end

-- The "Drive" prompt is only for the truck's owner: hide it from everyone
-- else (also if it arrives after the truck).
local function hidePromptFromOthers(model: Model, conns: { RBXScriptConnection })
	if model:GetAttribute("OwnerId") == player.UserId then
		return
	end
	local seat = model:FindFirstChild("DriverSeat")
	if not seat then
		return
	end
	local prompt = seat:FindFirstChild("DrivePrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		hidePrompt(prompt, conns)
		return
	end
	table.insert(
		conns,
		seat.ChildAdded:Connect(function(child: Instance)
			if child.Name == "DrivePrompt" and child:IsA("ProximityPrompt") then
				hidePrompt(child, conns)
			end
		end)
	)
end

local function setLights(rig: Rig, on: boolean, night: boolean)
	if rig.lit == on and rig.night == night then
		return
	end
	rig.lit, rig.night = on, night
	for _, lens in ipairs(rig.heads) do
		lens.Color = if on then HEAD_ON else HEAD_OFF
	end
	for _, beam in ipairs(rig.beams) do
		beam.Enabled = on and night
	end
	if not rig.braking then
		for _, lens in ipairs(rig.tails) do
			lens.Color = if on then TAIL_ON else TAIL_OFF
		end
	end
end

local function setBraking(rig: Rig, braking: boolean)
	if rig.braking == braking then
		return
	end
	rig.braking = braking
	for _, lens in ipairs(rig.tails) do
		lens.Color = if braking then TAIL_BRAKE elseif rig.lit then TAIL_ON else TAIL_OFF
	end
end

-- Everything a truck's effects need, found once when it streams in.
local function buildRig(model: Model): Rig?
	local chassis = model.PrimaryPart
	if not chassis then
		return nil
	end
	local seatInst = model:FindFirstChild("DriverSeat")
	local rig: Rig = {
		model = model,
		chassis = chassis,
		seat = if seatInst and seatInst:IsA("VehicleSeat") then seatInst else nil,
		wheels = {},
		heads = {},
		tails = {},
		beams = {},
		puffs = {},
		dust = {},
		engine = nil,
		pitch = ENGINE_PITCH[(model:GetAttribute("TruckId") :: string?) or ""] or 1,
		topSpeed = (model:GetAttribute("TopSpeed") :: number?) or 26,
		lastPos = chassis.Position,
		speed = 0,
		steer = 0,
		dustTimer = 0,
		wheelsIdle = false,
		lit = nil,
		braking = false,
		night = false,
		conns = {},
	}
	local forward = chassis.CFrame.LookVector
	local rearWheels: { Wheel } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Wheel" then
				local joint = d:FindFirstChild("Axle")
				local radius = d:GetAttribute("Radius")
				if joint and joint:IsA("Motor6D") and type(radius) == "number" then
					local wheel: Wheel = {
						joint = joint,
						part = d,
						radius = radius,
						steer = d:GetAttribute("Steer") == true,
						spin = 0,
					}
					table.insert(rig.wheels, wheel)
					if d:GetAttribute("Rear") == true then
						table.insert(rearWheels, wheel)
					end
				end
			elseif d.Name == "Headlight" then
				table.insert(rig.heads, d)
				local beam = Instance.new("SpotLight")
				beam.Name = "HeadlightBeam"
				beam.Face = faceToward(d, forward)
				beam.Range = 42
				beam.Angle = 65
				beam.Brightness = 2.6
				beam.Color = Color3.fromRGB(255, 236, 196)
				beam.Shadows = false
				beam.Enabled = false
				beam.Parent = d
				table.insert(rig.beams, beam)
			elseif d.Name == "Taillight" then
				table.insert(rig.tails, d)
			elseif d.Name == "Exhaust" then
				local out = d:FindFirstChild("ExhaustOut")
				if out and out:IsA("Attachment") then
					local amount = (d:GetAttribute("Smoke") :: number?) or 0.3
					local color = (d:GetAttribute("SmokeColor") :: Color3?) or Color3.fromRGB(130, 125, 120)
					table.insert(rig.puffs, { emitter = smokeEmitter(out, color, amount), smoke = amount })
				end
			end
		end
	end

	-- Dust from the two rearmost wheels (the trailer's when towing).
	table.sort(rearWheels, function(a, b)
		return a.joint.C0.Position.Z > b.joint.C0.Position.Z
	end)
	for i = 1, math.min(2, #rearWheels) do
		local wheel = rearWheels[i]
		local hub = wheel.joint.C0.Position
		local att = Instance.new("Attachment")
		att.Name = "DustPoint"
		att.CFrame = CFrame.new(hub + Vector3.new(0, -wheel.radius + 0.35, wheel.radius * 0.7))
		att.Parent = chassis
		table.insert(rig.dust, { emitter = dustEmitter(att), wheel = wheel, color = nil })
	end

	local engine = SoundData.Make("Engine")
	if engine then
		engine.Looped = true
		engine.Volume = 0
		engine.Parent = chassis
		rig.engine = engine
	end
	hidePromptFromOthers(model, rig.conns)
	return rig
end

local function stopRig(rig: Rig)
	for _, puff in ipairs(rig.puffs) do
		puff.emitter.Rate = 0
	end
	for _, dust in ipairs(rig.dust) do
		dust.emitter.Enabled = false
	end
	local engine = rig.engine
	if engine and engine.IsPlaying then
		engine:Stop()
	end
	setLights(rig, false, isNight)
	setBraking(rig, false)
end

local function updateDust(rig: Rig, dt: number, moving: number)
	rig.dustTimer -= dt
	if rig.dustTimer <= 0 then
		rig.dustTimer = DUST_CHECK
		local params = rayParams(rig.model)
		for _, dust in ipairs(rig.dust) do
			local hit =
				workspace:Raycast(dust.wheel.part.Position, Vector3.new(0, -(dust.wheel.radius + 1.5), 0), params)
			local color = if hit then VehicleLogic.DustColor(hit.Material.Name) else nil
			dust.color = color
			if color then
				dust.emitter.Color = ColorSequence.new(color)
			end
		end
	end
	local fast = moving >= VehicleLogic.DustSpeed
	for _, dust in ipairs(rig.dust) do
		local on = fast and dust.color ~= nil
		dust.emitter.Enabled = on
		if on then
			dust.emitter.Rate = 6 + moving * 0.7
		end
	end
end

local function updateRig(rig: Rig, dt: number, cameraPos: Vector3)
	local chassis = rig.chassis
	local pos = chassis.Position
	-- Speed from how far it moved: works for every truck, whoever simulates it.
	local delta = pos - rig.lastPos
	rig.lastPos = pos
	local forward = VehicleLogic.FlatFacing(chassis.CFrame.LookVector)
	local measured = if dt > 0 and delta.Magnitude < 60 then delta:Dot(forward) / dt else 0
	rig.speed += (measured - rig.speed) * (1 - math.exp(-10 * dt))
	if math.abs(rig.speed) < 0.05 then
		rig.speed = 0
	end
	if (pos - cameraPos).Magnitude > FX_RANGE then
		stopRig(rig)
		return
	end

	local seat = rig.seat
	local occupied = seat ~= nil and seat.Occupant ~= nil
	local steerFloat = if seat and occupied then seat.SteerFloat else 0
	local throttle = if seat and occupied then seat.ThrottleFloat else 0

	-- Wheels (left alone once a parked truck's are drawn at rest).
	rig.steer = VehicleLogic.SteerAngle(rig.steer, steerFloat, dt)
	local still = rig.speed == 0 and math.abs(rig.steer) < 1e-3 and not occupied
	if not (still and rig.wheelsIdle) then
		for _, wheel in ipairs(rig.wheels) do
			wheel.spin = VehicleLogic.SpinAngle(wheel.spin, rig.speed, wheel.radius, dt)
			local turn = if wheel.steer then CFrame.Angles(0, rig.steer, 0) else CFrame.identity
			wheel.joint.Transform = turn * CFrame.Angles(wheel.spin, 0, 0)
		end
		rig.wheelsIdle = still
	end

	-- Lights.
	setLights(rig, occupied, isNight)
	setBraking(rig, occupied and VehicleLogic.IsBraking(throttle, rig.speed))

	-- Exhaust: idle puffs, more on the throttle; a smoky old engine (the
	-- Rustbucket) coughs out an extra cloud now and then.
	for _, puff in ipairs(rig.puffs) do
		puff.emitter.Rate = if occupied then (2 + 10 * math.abs(throttle)) * (0.4 + puff.smoke) else 0
		if occupied and puff.smoke >= 0.9 and math.random() < dt * 0.25 then
			puff.emitter:Emit(6)
		end
	end

	updateDust(rig, dt, math.abs(rig.speed))

	-- Engine.
	local engine = rig.engine
	if engine then
		local running = occupied and SoundData.SfxEnabled
		if running and not engine.IsPlaying then
			engine:Play()
		elseif not running and engine.IsPlaying then
			engine:Stop()
		end
		if running then
			local load = math.clamp(math.abs(rig.speed) / math.max(rig.topSpeed, 1), 0, 1)
			engine.PlaybackSpeed = rig.pitch * (0.85 + load * 0.6 + math.abs(throttle) * 0.12)
			engine.Volume = 0.25 + load * 0.25
		end
	end
end

local function onTruckAdded(inst: Instance)
	if not inst:IsA("Model") or rigs[inst] then
		return
	end
	local model = inst
	local rig = buildRig(model)
	if rig then
		rigs[model] = rig
		return
	end
	-- Not all there yet (trucks stream in whole, so this is rare): try again.
	task.delay(1, function()
		if model.Parent and CollectionService:HasTag(model, TRUCK_TAG) and not rigs[model] then
			local later = buildRig(model)
			if later then
				rigs[model] = later
			end
		end
	end)
end

local function onTruckRemoved(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local rig = rigs[inst]
	if rig then
		for _, conn in ipairs(rig.conns) do
			conn:Disconnect()
		end
		rigs[inst] = nil
	end
end

local sinceCosmetic = 0
local function step(dt: number)
	sinceCosmetic += dt
	if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
		return
	end
	local elapsed = sinceCosmetic
	sinceCosmetic = 0
	local camera = workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
	for model, rig in pairs(rigs) do
		if model.Parent and rig.chassis.Parent then
			updateRig(rig, elapsed, cameraPos)
		end
	end
end

-- PreSimulation where the engine has it (Motor6D transforms are set there,
-- like an Animator's), else Stepped.
local function everyPhysicsStep(fn: (number) -> ())
	local ok, signal = pcall(function(): RBXScriptSignal<number>
		return RunService.PreSimulation
	end)
	if ok and signal then
		signal:Connect(fn)
	else
		RunService.Stepped:Connect(function(_time: number, dt: number)
			fn(dt)
		end)
	end
end

function VehicleFX.Start()
	isNight = workspace:GetAttribute("IsNight") == true
	workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		isNight = workspace:GetAttribute("IsNight") == true
	end)
	CollectionService:GetInstanceAddedSignal(TRUCK_TAG):Connect(onTruckAdded)
	CollectionService:GetInstanceRemovedSignal(TRUCK_TAG):Connect(onTruckRemoved)
	for _, inst in ipairs(CollectionService:GetTagged(TRUCK_TAG)) do
		onTruckAdded(inst)
	end
	everyPhysicsStep(step)
end

return VehicleFX
