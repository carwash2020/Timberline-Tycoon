--!strict
-- EventService: seasonal events, and the client intents that do not have
-- their own service yet.
--
-- Remotes (Init): each is connected once, the handler budgets the call.
--   ExpandLand     buy the next plot square (PlotService.Expand)
-- SpawnPadPress is VehicleService.BindPad. ChopSawSet lives on
-- ChopSawService. Neither is connected here, so a press is rate-limited
-- once.
--
-- The Halloween event (B14; rules in Shared/EventData, looks in
-- Art/EventArt). It has no remote: the client only reads attributes.
--   * It runs 1 October to 1 November by the server's UTC date. In Studio
--     the Workspace attribute "EventOverride" ("halloween" / "off")
--     overrides the date; a live server ignores it.
--   * Decorations: jack-o'-lanterns by the town's lamps, built while the
--     event runs (a Workspace folder, HalloweenDecor) and removed after.
--   * Two themed daily goals count the daily goals' own moments
--     (DailyService.Listener). They pay no cash: finishing both on three
--     days earns the Pumpkin Hat (profile.cosmetics, account-wide), worn
--     on the head. EventGoals and EventInfo player attributes feed
--     DailyUI.
--   * Nothing here is sold for Robux, random, or an advantage; no badge
--     pays cash or Robux.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventData = require(ReplicatedStorage.Shared.EventData)
local RateLimiter = require(script.Parent.RateLimiter)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local EventService = {}

local expandBound = false

local clock: () -> number = os.time -- tests replace this
local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local overrideValue: (() -> unknown)? = nil -- tests replace this
local decor: Instance? = nil
local started = false
local watching: { [Player]: boolean } = {} -- CharacterAdded is connected once per player

-- The id of the event running now ("halloween") or nil. The Studio
-- override is read only in Studio.
function EventService.Current(): string?
	local override: unknown = nil
	if overrideValue then
		override = overrideValue()
	else
		local ok, value = pcall(function(): unknown
			if game:GetService("RunService"):IsStudio() then
				return game:GetService("Workspace"):GetAttribute(EventData.OverrideAttribute)
			end
			return nil
		end)
		if ok then
			override = value
		end
	end
	return EventData.Active(clock(), override)
end

-- Builds the decorations while the event runs and removes them after.
function EventService.RefreshDecor()
	local id = EventService.Current()
	if id == nil then
		local folder = decor
		if folder then
			decor = nil
			folder:Destroy()
		end
		return
	end
	if decor ~= nil then
		return
	end
	local EventArt = require(ReplicatedStorage.Shared.Art.EventArt)
	local Kit = require(ReplicatedStorage.Shared.Art.Kit)
	local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
	local folder = Instance.new("Folder")
	folder.Name = "HalloweenDecor"
	-- A patch beside every lamp in town (lamps stand on the ground at y 0;
	-- decoration only, so it never blocks a road or a truck).
	for i, lamp in ipairs(WorldPlan.Town().lamps) do
		local patch = EventArt.PumpkinPatch(i * 31)
		-- placeAt, not PivotTo: a Model's pivot is its bounding box centre, so
		-- PivotTo put the patch's middle (half a pumpkin up) on the ground.
		Kit.placeAt(patch, lamp * CFrame.new(2.4, 0, 0.8) * CFrame.Angles(0, math.rad(15 * ((i % 5) - 2)), 0))
		-- The drawn ground can sit above y = 0 (that sank them half into it):
		-- probe under both pumpkins and stand the patch on the highest.
		local lift = 0
		for _, child in ipairs(patch:GetChildren()) do
			if child:IsA("Model") then
				local at = child:GetPivot().Position
				lift = math.max(lift, TerrainBuilder.LiftOnto(at.X, 0, at.Z, 8))
			end
		end
		if lift > 0.05 then
			patch:PivotTo(patch:GetPivot() + Vector3.new(0, lift, 0))
		end
		patch.Parent = folder
	end
	folder.Parent = game:GetService("Workspace")
	decor = folder
end

-- The Pumpkin Hat on `player`'s head (replaces any it wears).
local function wearHat(player: Player)
	local char = player.Character
	local head = if char then char:FindFirstChild("Head") else nil
	if not char or not head or not head:IsA("BasePart") then
		return
	end
	local old = char:FindFirstChild("PumpkinHat")
	if old then
		old:Destroy()
	end
	local hat = require(ReplicatedStorage.Shared.Art.EventArt).Hat()
	local base = hat.PrimaryPart
	if not base then
		hat:Destroy()
		return
	end
	hat:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 - 0.1, 0))
	for _, d in ipairs(hat:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			if d ~= base then
				local w = Instance.new("WeldConstraint")
				w.Part0 = base
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = base
	weld.Parent = base
	hat.Parent = char
end

local function publishEvent(player: Player, profile: any)
	local id = EventService.Current()
	local def = if id then EventData.Def(id) else nil
	if not id or not def then
		player:SetAttribute("EventGoals", "")
		player:SetAttribute("EventInfo", "")
		return
	end
	local state = profile.event :: EventData.State
	local owned = type(profile.cosmetics) == "table" and profile.cosmetics[def.cosmetic] == true
	player:SetAttribute("EventGoals", EventData.EncodeGoals(state))
	player:SetAttribute("EventInfo", EventData.EncodeInfo(def, state, owned))
end

-- Today's event state for `profile` (rolled if the day or event changed).
local function roll(profile: any, id: string): EventData.State
	local day = math.floor(clock() / 86400)
	local state = EventData.Roll(profile.event, id, day)
	profile.event = state
	return state
end

-- Call once the player's save has loaded (and again after a slot swap).
function EventService.Start(player: Player, profile: any)
	local id = EventService.Current()
	if id then
		roll(profile, id)
	end
	publishEvent(player, profile)
	local owned = type(profile.cosmetics) == "table" and profile.cosmetics[EventData.Halloween.cosmetic] == true
	if owned then
		wearHat(player)
	end
	if (id == nil and not owned) or watching[player] then
		return
	end
	watching[player] = true
	player.AncestryChanged:Connect(function()
		if player.Parent == nil then
			watching[player] = nil
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.5) -- the head's accessories load first
		local current: any = require(script.Parent.ProfileService).GetProfile(player)
		if current and type(current.cosmetics) == "table" and current.cosmetics[EventData.Halloween.cosmetic] then
			wearHat(player)
		end
	end)
end

-- A moment the daily goals also count (DailyService.Listener):
-- "treeFelled" or "piecesSold", and how many.
function EventService.Moment(player: Player, moment: string, amount: number)
	local id = EventService.Current()
	local def = if id then EventData.Def(id) else nil
	if not id or not def then
		return
	end
	local profile: any = require(script.Parent.ProfileService).GetProfile(player)
	if not profile then
		return
	end
	local state = roll(profile, id)
	local finished, newDay = EventData.Apply(state, moment, amount)
	for _, index in ipairs(finished) do
		notify(player, string.format("%s goal done: %s", def.name, EventData.Goals[index].text))
	end
	if newDay then
		if EventData.Earned(state) then
			if type(profile.cosmetics) ~= "table" then
				profile.cosmetics = {}
			end
			if not profile.cosmetics[def.cosmetic] then
				profile.cosmetics[def.cosmetic] = true
				notify(player, string.format("You earned the %s! It is on your head.", def.cosmeticName))
				wearHat(player)
			end
		else
			notify(
				player,
				string.format("%s goals done today! %d of %d days.", def.name, state.daysDone, EventData.CosmeticDays)
			)
		end
	end
	publishEvent(player, profile)
end

-- `notifyFn` shows a toast (GameServer's notify); `clockFn` and
-- `overrideFn` are for tests. Starts the decoration check, and connects
-- the daily goals' moments to the event's goals.
function EventService.InitEvent(
	notifyFn: (Player, string) -> (),
	clockFn: (() -> number)?,
	overrideFn: (() -> unknown)?
)
	notify = notifyFn
	if clockFn then
		clock = clockFn
	end
	overrideValue = overrideFn
	if started then
		return
	end
	started = true
	local DailyService = require(script.Parent.DailyService)
	DailyService.Listener = EventService.Moment
	if clockFn == nil then
		task.spawn(function()
			while true do
				local ok, err = pcall(function(): any
					EventService.RefreshDecor()
					return nil
				end)
				if not ok then
					warn("[EventService] decor failed: " .. tostring(err))
				end
				task.wait(60)
			end
		end)
	end
end

function EventService.Init(remotes: {
	ExpandLand: RemoteEvent?,
	SpawnPadPress: RemoteEvent?,
}?)
	if remotes == nil then
		return
	end
	if not expandBound and remotes.ExpandLand ~= nil then
		expandBound = true
		remotes.ExpandLand.OnServerEvent:Connect(function(player: Player, x: unknown, z: unknown, expected: unknown)
			-- The only ExpandLand handler. Foundations counts this Allow once.
			if not RateLimiter.Allow(player, "ExpandLand") then
				return
			end
			-- Budget is spent before the arguments are read. A bare fire
			-- stops here, so the plot module is only loaded for a real tap.
			if type(x) ~= "number" or type(z) ~= "number" then
				return
			end
			local PlotService = require(script.Parent.PlotService)
			PlotService.Expand(player, x, z, expected)
		end)
	end
end

return EventService
