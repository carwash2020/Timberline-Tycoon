--!strict
-- LogicService: wiring on a plot (V2_PLAN.md, wiring; rules in
-- Shared/WireLogic, pieces in Shared/LogicItems).
--   * A Wall Switch has two prompts: Flip (Interact: E, ButtonX, tap) and
--     Wire (Open: F, ButtonY, hold). Wire links the switch to the nearest
--     Spark Lamp or Door within WireLogic.Span that it does not feed yet.
--     Press it again for the next one. With nothing left in reach it clears
--     the switch's wires. Prompts are the one input path every device has.
--   * The Wire remote carries the same intent by uid: (fromUid, port,
--     toUid, port) links, ("cut", uid) removes every wire on a piece. It
--     is rate limited, needs the build permission, and the player must
--     stand within WireLogic.Reach of each piece it names.
--   * Wires are saved in profile.plot.wires and the switches that are on
--     in profile.plot.switches, so a rebuilt plot (rejoin) puts each lever
--     back where it was (Restore). A switch model also carries a "Wires"
--     attribute (its targets' uids, comma joined) so the client can draw
--     the lines. A lamp nobody wired stays lit. A wired lamp is lit while any of its switches is on. A wired
--     door opens while any of its switches is on, through PlotDoors, so a
--     blocked door stays shut and the hint says why.
-- PlotService calls Bind once, Attach for each built piece, and Sync after
-- a piece is sold, so nothing here reaches into PlotService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local PermissionLogic = require(ReplicatedStorage.Shared.PermissionLogic)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local WireLogic = require(ReplicatedStorage.Shared.WireLogic)
local PlotDoors = require(script.Parent.PlotDoors)
local RateLimiter = require(script.Parent.RateLimiter)

local LogicService = {}

-- What LogicService needs of a plot slot.
export type Host = { cframe: CFrame, items: Instance }
type Profile = any
export type HostFn = (Player, string) -> (Host?, Profile?, Player?, boolean)
export type Notify = (Player, string) -> ()

export type Context = {
	slot: Host,
	model: Model,
	item: PlotLogic.Placed,
	ownerOf: () -> (Player?, Profile?),
}

local LEVER_BOX = 3
local TIP = 0.7 -- radians the lever leans either way

local hostFn: HostFn? = nil
local function silent(_player: Player, _text: string) end
local notify: Notify = silent
local lastFlip: { [string]: number } = {}
local bound = false

function LogicService.Bind(host: HostFn, notifyFn: Notify)
	hostFn = host
	notify = notifyFn
end

function LogicService.Reset()
	table.clear(lastFlip)
end

local function mayUse(owner: Player, profile: Profile, who: Player, flag: string): boolean
	return who.UserId == owner.UserId or PermissionLogic.Allows(profile.permissions, who.UserId, flag)
end

local function wiresOf(profile: Profile): { WireLogic.Wire }
	local plot = profile.plot
	if type(plot.wires) ~= "table" then
		plot.wires = {}
	end
	return plot.wires
end

local function findItem(profile: Profile, uid: string): PlotLogic.Placed?
	for _, item in ipairs(profile.plot.placed) do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

local function modelOf(host: Host, uid: string): Model?
	local found = host.items:FindFirstChild(uid)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

local function nameOf(item: PlotLogic.Placed): string
	local bp = PlotLogic.Blueprint(item.blueprintId)
	return if bp then bp.displayName else item.blueprintId
end

---------------------------------------------------------------------------
-- What the pieces show
---------------------------------------------------------------------------

local function tip(model: Model, on: boolean)
	local lever = model:FindFirstChild("Part" .. LEVER_BOX)
	local base = model:FindFirstChild("Root")
	local bp = PlotLogic.Blueprint("SparkSwitch")
	local box = if bp then bp.boxes[LEVER_BOX] else nil
	if lever and base and box and lever:IsA("BasePart") and base:IsA("BasePart") then
		-- The model's Root sits 0.1 above the ground centre the offsets use.
		lever.CFrame = base.CFrame
			* CFrame.new(box.offset - Vector3.new(0, 0.1, 0))
			* CFrame.Angles(0, 0, if on then -TIP else TIP)
	end
	model:SetAttribute("On", on)
end

local function setLamp(model: Model, blueprintId: string, lit: boolean)
	local bp = PlotLogic.Blueprint(blueprintId)
	if bp then
		for i, box in ipairs(bp.boxes) do
			local part = model:FindFirstChild("Part" .. i)
			if box.material == "Neon" and part and part:IsA("BasePart") then
				part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
				part.Color = if lit then Color3.fromHex(box.color) else Color3.fromRGB(88, 84, 76)
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("PointLight") then
			d.Enabled = lit
		end
	end
	model:SetAttribute("Lit", lit)
end

-- Opens or shuts a wired door the way its own prompt would. Returns a hint
-- when something is in the way.
local function setDoor(
	host: Host,
	profile: Profile,
	who: Player,
	item: PlotLogic.Placed,
	model: Model,
	open: boolean
): string?
	if (model:GetAttribute("Open") == true) == open then
		return nil
	end
	local _, hint = PlotDoors.Toggle(who, model, item, profile.plot.placed, host.cframe, host.items, os.clock(), true)
	return hint
end

-- Recomputes every wired lamp and door of a plot from its switches.
function LogicService.Refresh(host: Host, profile: Profile, who: Player?)
	local placed: { PlotLogic.Placed } = profile.plot.placed
	local wires = WireLogic.Live(profile.plot.wires, placed :: any)
	local on: { [string]: boolean } = {}
	for _, item in ipairs(placed) do
		if WireLogic.Role(item.blueprintId) == "switch" then
			local model = modelOf(host, item.uid)
			if model then
				if model:GetAttribute("On") == true then
					on[item.uid] = true
				end
				local targets: { string } = {}
				for _, wire in ipairs(wires) do
					if wire.from == item.uid then
						table.insert(targets, wire.to)
					end
				end
				model:SetAttribute("Wires", table.concat(targets, ","))
			end
		end
	end
	local hint: string? = nil
	for _, item in ipairs(placed) do
		local role = WireLogic.Role(item.blueprintId)
		local model = if role == "lamp" or role == "door" then modelOf(host, item.uid) else nil
		if model then
			local fed, powered = WireLogic.Power(wires, item.uid, on)
			if role == "lamp" then
				setLamp(model, item.blueprintId, WireLogic.LampLit(fed, powered))
			elseif fed and who then
				hint = setDoor(host, profile, who, item, model, powered) or hint
			end
		end
	end
	if hint and who then
		notify(who, hint)
	end
end

-- A plot was just rebuilt from the save: lamps and doors follow the saved
-- switch positions (set when each switch was attached). `who` is the owner.
function LogicService.Restore(host: Host, profile: Profile, who: Player?)
	LogicService.Refresh(host, profile, who)
end

-- A piece was sold or deleted: forget wires to nothing, refresh the rest.
function LogicService.Sync(host: Host, profile: Profile, who: Player?)
	if type(profile.plot.wires) == "table" then
		profile.plot.wires = WireLogic.Live(profile.plot.wires, profile.plot.placed)
	end
	if type(profile.plot.switches) == "table" then
		profile.plot.switches = WireLogic.LiveSwitches(profile.plot.switches, profile.plot.placed)
	end
	if type(profile.plot.wires) == "table" then
		LogicService.Refresh(host, profile, who)
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local function addWire(profile: Profile, fromUid: string, toUid: string): (boolean, string?)
	local placed = profile.plot.placed
	profile.plot.wires = WireLogic.Live(wiresOf(profile), placed)
	local ok, why = WireLogic.Check(profile.plot.wires, placed, fromUid, toUid)
	if not ok then
		return false, why
	end
	table.insert(profile.plot.wires, { from = fromUid, to = toUid })
	return true, nil
end

local function cutWires(profile: Profile, uid: string): number
	local rest, cut = WireLogic.Without(wiresOf(profile), uid)
	profile.plot.wires = rest
	return cut
end

local function rootPosition(player: Player): Vector3?
	local char = player.Character
	if not char then
		return nil
	end
	local part = char:FindFirstChild("HumanoidRootPart") :: any
	if part == nil then
		return nil
	end
	return part.Position
end

local function near(player: Player, host: Host, item: PlotLogic.Placed): boolean
	local pos = rootPosition(player)
	if not pos then
		return false
	end
	local local3 = host.cframe:PointToObjectSpace(pos)
	return WireLogic.InReach(local3.X, local3.Y, local3.Z, item :: any)
end

-- Link by uid for `player`, on whichever plot they may build on.
function LogicService.Link(player: Player, fromUid: string, toUid: string): (boolean, string?)
	local get = hostFn
	if not get then
		return false, "bad"
	end
	local host, profile = get(player, "build")
	if not host or not profile then
		return false, "missing"
	end
	local from, to = findItem(profile, fromUid), findItem(profile, toUid)
	if not from or not to then
		return false, "missing"
	end
	if not (near(player, host, from) and near(player, host, to)) then
		return false, "reach"
	end
	local ok, why = addWire(profile, fromUid, toUid)
	if ok then
		LogicService.Refresh(host, profile, player)
	end
	return ok, why
end

-- Removes every wire on one piece, for `player`.
function LogicService.Cut(player: Player, uid: string): (boolean, string?)
	local get = hostFn
	if not get then
		return false, "bad"
	end
	local host, profile = get(player, "build")
	if not host or not profile then
		return false, "missing"
	end
	local item = findItem(profile, uid)
	if not item or WireLogic.Role(item.blueprintId) == nil then
		return false, "missing"
	end
	if not near(player, host, item) then
		return false, "reach"
	end
	local cut = cutWires(profile, uid)
	LogicService.Refresh(host, profile, player)
	return cut > 0, if cut > 0 then nil else "none"
end

-- The Wire remote: (fromUid, port, toUid, port) or ("cut", uid).
function LogicService.OnWire(player: Player, a: unknown, b: unknown, c: unknown, d: unknown)
	if not RateLimiter.Allow(player, "Wire") then
		return
	end
	local ok: boolean, why: string?
	if a == "cut" and type(b) == "string" and c == nil then
		ok, why = LogicService.Cut(player, b)
	elseif
		type(a) == "string"
		and b == WireLogic.Port
		and type(c) == "string"
		and d == WireLogic.Port
		and a ~= "cut"
	then
		ok, why = LogicService.Link(player, a, c)
		if ok then
			notify(player, WireLogic.Message("wired") or "")
			return
		end
	else
		return
	end
	local text = WireLogic.Message(if ok then "cleared" else why)
	if text then
		notify(player, text)
	end
end

---------------------------------------------------------------------------
-- Pieces on the plot
---------------------------------------------------------------------------

-- A switch's Flip prompt, by `who`. Exported so tests can press it.
function LogicService.Flip(ctx: Context, who: Player)
	local owner, profile = ctx.ownerOf()
	if not owner or not profile then
		return
	end
	if not mayUse(owner, profile, who, "interact") then
		notify(who, "The owner hasn't let you use that.")
		return
	end
	local now = os.clock()
	local last = lastFlip[ctx.item.uid]
	if last and now - last < WireLogic.FlipCooldown then
		return
	end
	lastFlip[ctx.item.uid] = now
	local on = ctx.model:GetAttribute("On") ~= true
	tip(ctx.model, on)
	profile.plot.switches = WireLogic.SetOn(profile.plot.switches, ctx.item.uid, on)
	LogicService.Refresh(ctx.slot, profile, who)
end

-- A switch's Wire prompt, by `who`: link the nearest free target, else clear.
function LogicService.WireNearest(ctx: Context, who: Player)
	local owner, profile = ctx.ownerOf()
	if not owner or not profile then
		return
	end
	if not mayUse(owner, profile, who, "build") then
		notify(who, "The owner hasn't let you build here.")
		return
	end
	local uid = ctx.item.uid
	profile.plot.wires = WireLogic.Live(wiresOf(profile), profile.plot.placed)
	local list = WireLogic.Candidates(profile.plot.wires, profile.plot.placed, uid)
	local target = list[1]
	if target then
		local ok, why = addWire(profile, uid, target)
		if ok then
			local other = findItem(profile, target)
			notify(who, string.format("Wired to the %s.", if other then nameOf(other) else "piece"))
			LogicService.Refresh(ctx.slot, profile, who)
		else
			notify(who, WireLogic.Message(why) or "")
		end
		return
	end
	if cutWires(profile, uid) > 0 then
		notify(who, WireLogic.Message("cleared") or "")
		LogicService.Refresh(ctx.slot, profile, who)
	else
		notify(who, WireLogic.Message("none") or "")
	end
end

local function prompt(parent: Instance, name: string, action: string, object: string, input: string, hold: number)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = InputKit.OpenRange
	InputKit.PromptDefaults(p, input)
	p.Parent = parent
	return p
end

-- Lune's Instance has no Triggered event, so tests press the prompts
-- through Flip and WireNearest instead. Studio always has the event.
local function onTriggered(p: ProximityPrompt, handler: (Player) -> ())
	local ok, signal = pcall(function()
		return p.Triggered
	end)
	if ok and signal then
		signal:Connect(handler)
	end
end

-- Dresses a freshly built piece: a switch gets its prompts, a lamp its
-- starting light. Anything else is left alone.
function LogicService.Attach(ctx: Context)
	local role = WireLogic.Role(ctx.item.blueprintId)
	if role == "switch" then
		local _, saved = ctx.ownerOf()
		tip(ctx.model, saved ~= nil and WireLogic.IsOn(saved.plot.switches, ctx.item.uid))
		local host: Instance = ctx.model:FindFirstChild("Part" .. LEVER_BOX) or ctx.model
		local object = nameOf(ctx.item)
		local flipPrompt = prompt(host, "FlipPrompt", "Flip", object, "Interact", 0)
		onTriggered(flipPrompt, function(who: Player)
			LogicService.Flip(ctx, who)
		end)
		local wirePrompt = prompt(host, "WirePrompt", "Wire", object, "Open", 0.4)
		onTriggered(wirePrompt, function(who: Player)
			LogicService.WireNearest(ctx, who)
		end)
	elseif role == "lamp" then
		local _, profile = ctx.ownerOf()
		local lit = true
		if profile then
			local wires = WireLogic.Live(profile.plot.wires, profile.plot.placed)
			local on: { [string]: boolean } = {}
			for _, uid in ipairs(WireLogic.CleanSwitches(profile.plot.switches)) do
				on[uid] = true
			end
			local fed, powered = WireLogic.Power(wires, ctx.item.uid, on)
			lit = WireLogic.LampLit(fed, powered)
		end
		setLamp(ctx.model, ctx.item.blueprintId, lit)
	end
end

function LogicService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(LogicService.OnWire)
end

return LogicService
