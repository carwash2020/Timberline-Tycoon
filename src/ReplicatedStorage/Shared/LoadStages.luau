--!strict
-- LoadStages: the milestones of a server start, in order, with the share of
-- the loading bar each one fills. The server publishes the latest milestone
-- it has reached as the workspace attribute "LoadStage" (LoadState); the
-- client's loading card turns that into a bar and a line of text, so the
-- player sees the world filling in instead of a frozen "Building..." line.
--
--   starting  the server script is running
--   terrain   the ground is written
--   town      the sawmill, shops and sell area are built
--   world     the world is ready for players (SellArea is in)
--   services  every service has started and the server listens for players
--   save      this player's save is loaded (the HUD's own milestone)
--
-- Pure and tested. Unknown or missing stages read as the start.

local LoadStages = {}

export type Stage = { id: string, bar: number, text: string }

-- `bar` is the fraction of the bar that is full once the stage is reached.
LoadStages.List = {
	{ id = "starting", bar = 0.02, text = "Starting the server..." },
	{ id = "terrain", bar = 0.4, text = "Shaping the land..." },
	{ id = "town", bar = 0.65, text = "Building the town..." },
	{ id = "world", bar = 0.8, text = "Opening the gates..." },
	{ id = "services", bar = 0.9, text = "Waking the townsfolk..." },
	{ id = "save", bar = 1, text = "Loading your save..." },
} :: { Stage }

local INDEX: { [string]: number } = {}
for i, stage in ipairs(LoadStages.List) do
	INDEX[stage.id] = i
end

-- The stage for an attribute value (any type), nil-safe.
function LoadStages.Get(stage: unknown): Stage
	local i = if type(stage) == "string" then INDEX[stage] else nil
	return LoadStages.List[i or 1]
end

-- True when `candidate` is later than `current` (the server only moves on).
function LoadStages.IsLater(candidate: string, current: unknown): boolean
	local a = INDEX[candidate]
	local b = if type(current) == "string" then INDEX[current] else nil
	if a == nil then
		return false
	end
	return b == nil or a > b
end

-- What the card shows: the bar's fill (0..1) and its text. `remotes` is
-- whether the server's Remotes folder exists (it appears at "world").
-- Once the save is in, nothing shows (nil text, full bar).
function LoadStages.Describe(stage: unknown, remotes: boolean, profileLoaded: unknown): (number, string?)
	if profileLoaded == true then
		return 1, nil
	end
	local current = LoadStages.Get(stage)
	-- The remotes folder is proof the world is up even if the attribute is late.
	if remotes and INDEX[current.id] < INDEX.world then
		current = LoadStages.List[INDEX.world]
	end
	-- Once the world is up, what the player waits for is their own save.
	if INDEX[current.id] >= INDEX.world then
		return current.bar, "Loading your save..."
	end
	return current.bar, current.text
end

-- Percent text for a bar value, 0 to 100.
function LoadStages.Percent(fill: number): string
	local clamped = math.min(1, math.max(0, fill))
	return string.format("%d%%", math.floor(clamped * 100 + 0.5))
end

return LoadStages
