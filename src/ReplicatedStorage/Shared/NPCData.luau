--!strict
-- NPCData: the townsfolk (GAME_DESIGN §11-§12): who they are, how they look
-- (CharacterArt specs), where they stand or walk, and what they say. Pure
-- data plus the maths everyone shares, so the server (NPCService), every
-- client (NPCController), the preview and the tests agree:
--   * Spots: where each NPC stands. Shopkeepers stand behind the Counter of
--     their shop (found in the built world, so they follow the building);
--     others stand beside a named part (the sell zone, the gondola
--     platform) or at fixed town coordinates.
--   * Routes: walkers loop through town on a list of waypoints. The server
--     never moves them: it publishes the route (EncodeRoute) and clients
--     work out where they are from the shared server clock (RouteState),
--     so everyone sees roughly the same stroll without any replication.
--
-- The town is flat at y = 0 (WorldLayout's Town zone: x -125..140,
-- z -32..205); waypoints are (x, z) on it.

local CharacterArt = require(script.Parent.Art.CharacterArt)

local NPCData = {}

export type Spot = {
	kind: "fixed" | "counter" | "beside" | "route",
	position: Vector3?, -- fixed: where the feet go
	lookAt: Vector3?, -- fixed: what they face
	model: string?, -- counter / beside: the model's name under TimberlineMap
	part: string?, -- beside: the part in it (counter: always "Counter")
	offset: Vector3?, -- beside: X past the part's side edge (+/-), Z from its centre
	turn: number?, -- beside: degrees to turn from the part's front (+ = to the left)
	fallback: Vector3?, -- where to stand if the model isn't there
}

export type Waypoint = {
	x: number,
	z: number,
	pause: number?, -- seconds standing here
	face: number?, -- degrees to face while paused (0 = -Z, 90 = -X, 180 = +Z)
}

export type NPC = {
	id: string, -- also the model's name
	name: string,
	role: string,
	look: CharacterArt.Spec,
	spot: Spot,
	route: { Waypoint }?,
	speed: number?, -- walkers, studs per second
	idle: string?, -- an idle flourish NPCController knows: "sip", "clipboard", "glasses", "wipe", "lookAround"
	tutorialQuiet: boolean?, -- no bubbles while the player's tutorial runs (QuestUI owns Murph's lines)
	greetings: { string },
	lines: { string },
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

---------------------------------------------------------------------------
-- The roster
---------------------------------------------------------------------------

NPCData.List = {
	{
		id = "Murph",
		name = "Murph",
		role = "Retired lumberjack",
		-- In front of his campfire, facing the spawn (WorldPlan.Town().murph:
		-- the camp at (-21, 24) turned toward the spawn, 3 studs out).
		spot = { kind = "fixed", position = Vector3.new(-18.6, 0, 25.8), lookAt = Vector3.new(0, 0, 40) },
		idle = "sip",
		tutorialQuiet = true,
		look = {
			name = "Murph",
			role = "Retired lumberjack",
			seed = 11,
			stout = true,
			skin = hex("#E6B08A"),
			shirt = hex("#B8382E"),
			stripe = hex("#4A1E1A"),
			pants = hex("#3D5A8C"),
			cuffs = true,
			boots = hex("#6B4026"),
			hair = hex("#CFC7BC"),
			hairStyle = "short",
			brows = hex("#E9E2D6"),
			beard = "big",
			beardColor = hex("#DAD1C3"),
			hat = "beanie",
			hatColor = hex("#D98A2B"),
			hatTrim = hex("#B4691C"),
			suspenders = hex("#5A3820"),
			carry = "mug",
			accent = hex("#3F6FAA"),
		},
		greetings = { "Well, look who it is!", "Mornin', kid!", "Howdy, partner." },
		lines = {
			"Back in my day we felled trees uphill. Both ways.",
			"Plant a Heartseed in a fresh stump and the forest remembers who you are.",
			"The Phantom Grove only shows itself after dark. Bring a lantern. And your nerve.",
			"Curly bark, dimpled bark, lumpy bark... that's figure hidin' in the grain. Don't sell it cheap.",
			"See that giant up yonder? The Skyroot. Been growin' since before I was a sapling.",
			"This coffee's older than your truck. Tastes it, too.",
			"When a storm rolls in, watch for the tree that glows. Lightning wood's worth a fortune.",
			"I've retired three times. The forest keeps callin' me back.",
			"Your Field Guide's got empty pages, kid. Go fill 'em.",
		},
	},
	{
		id = "Millie",
		name = "Millie",
		role = "Sawmill keeper",
		spot = {
			kind = "beside",
			model = "SellArea",
			part = "SellZone",
			offset = Vector3.new(2.6, 0, 6.5),
			turn = 40,
			fallback = Vector3.new(14.6, 0, 92.5),
		},
		idle = "clipboard",
		look = {
			name = "Millie",
			role = "Sawmill keeper",
			seed = 23,
			skin = hex("#C98E6A"),
			shirt = hex("#3E8C84"),
			stripe = hex("#24524E"),
			pants = hex("#4F6FA0"),
			overalls = hex("#4F6FA0"),
			cuffs = true,
			boots = hex("#5A3A24"),
			hair = hex("#9A4A2A"),
			hairStyle = "bun",
			hat = "bandana",
			hatColor = hex("#C8403A"),
			hatTrim = hex("#F5EBD7"),
			rolledSleeves = true,
			gloves = hex("#C9965A"),
			carry = "clipboard",
		},
		greetings = { "Hiya, sweetie!", "Fresh logs? Bring 'em here!", "Well hello there!" },
		lines = {
			"Logs on the pad, cash in your pocket. That's the Millie guarantee.",
			"Birdseye, quilted, curly... the saw never lies about what's inside a log.",
			"Mind the blade, sweetie. It's hungry today.",
			"Logs you send down a Cloud Chute wait for you in the Sky Bin, right over there.",
			"Replant a stump and it grows back for you. Anybody fells it, you get a share!",
			"Sawdust in my hair, sawdust in my tea. Wouldn't have it any other way.",
			"Rare wood's worth more at the mill. Lumenwood glows right through the till.",
		},
	},
	{
		id = "Tink",
		name = "Tink",
		role = "Tool Shed",
		spot = { kind = "counter", model = "ToolShed", fallback = Vector3.new(-45, 0, 103.5) },
		idle = "glasses",
		look = {
			name = "Tink",
			role = "Tool Shed",
			seed = 37,
			skin = hex("#F0C8A6"),
			shirt = hex("#8EB5D6"),
			pants = hex("#6A5040"),
			boots = hex("#4E3424"),
			hair = hex("#C8682C"),
			hairStyle = "curly",
			beard = "goatee",
			beardColor = hex("#B85A24"),
			hat = "flatcap",
			hatColor = hex("#6E7A5E"),
			hatTrim = hex("#545E46"),
			glasses = hex("#B88A3A"),
			apron = hex("#8A5A36"),
			rolledSleeves = true,
			carry = "scroll",
		},
		greetings = { "Ah, a customer!", "Welcome to the Tool Shed!", "Mind the sharp bits!" },
		lines = {
			"A sharper axe is a happier axe. I've asked them.",
			"Rusty to Steel is the best upgrade you'll ever make. Until the next one.",
			"Obsidian comes from the volcano. I polish it very, very carefully.",
			"The Inferno Axe laughs at emberwood. I hear it at night. Laughing.",
			"Starfall Axes aren't sold, they're forged. Up on the isles, where the stars land.",
			"Too hard to chop? It's not you, it's your axe. Mostly.",
		},
	},
	{
		id = "Dale",
		name = "Dale",
		role = "Dealership",
		spot = { kind = "counter", model = "Dealership", fallback = Vector3.new(45, 0, 103.5) },
		idle = "wipe",
		look = {
			name = "Dale",
			role = "Dealership",
			seed = 41,
			skin = hex("#8D5A3C"),
			shirt = hex("#E9E2D3"),
			pants = hex("#2F4A6E"),
			overalls = hex("#2F4A6E"),
			kneePatch = hex("#B5462F"),
			boots = hex("#3E2A1E"),
			hair = hex("#2A211C"),
			hairStyle = "short",
			beard = "stubble",
			hat = "capBack",
			hatColor = hex("#C0392B"),
			hatTrim = hex("#8E281E"),
			rolledSleeves = true,
			carry = "wrench",
		},
		greetings = { "Hey hey!", "Lookin' for wheels?", "Yo! Come on in." },
		lines = {
			"The Rustbucket? She's got character. Mostly rust, but character.",
			"Hitch a trailer and you'll haul twice the logs. Your back will thank me.",
			"Every truck here's been road-tested. By me. Once.",
			"Volcano roads eat tires for breakfast. Get Heat Boots before you go stompin' around.",
			"Load your logs at the tailgate, then drive. Don't drive, then load. Trust me.",
			"I can fix anything. Except my sense of direction.",
		},
	},
	{
		id = "Hazel",
		name = "Hazel",
		role = "Hearth & Home",
		spot = { kind = "counter", model = "HearthAndHome", fallback = Vector3.new(-80, 0, 103.5) },
		idle = "lookAround",
		look = {
			name = "Hazel",
			role = "Hearth & Home",
			seed = 53,
			skin = hex("#EAC1A0"),
			shirt = hex("#C27A86"),
			pants = hex("#6E4B3A"),
			boots = hex("#5A3A2A"),
			hair = hex("#BDB6B0"),
			hairStyle = "bun",
			glasses = hex("#6B4A3A"),
			scarf = hex("#E3A93A"),
			carry = "lantern",
		},
		greetings = { "Oh, hello dear!", "Come in, come in, it's cold out!", "Welcome to Hearth & Home." },
		lines = {
			"No lantern, no Phantom Grove, dear. The dark out there is hungry.",
			"Snowfields? You'll want the Insulated Coat. Three layers of wool and a pocket for snacks.",
			"Heat Boots, for the volcano. Unless you like toasted toes.",
			"A Featherfall Cloak turns a fall off the isles into a nice float down.",
			"I knitted this scarf from fireflies. Well, from yarn. But I thought about fireflies.",
			"A well-loved forest gets busier. Deer, butterflies, birdsong. Plant a few seeds, you'll see.",
		},
	},
	{
		id = "Gus",
		name = "Gus",
		role = "Gondola operator",
		spot = {
			kind = "beside",
			model = "GondolaTown",
			part = "Platform",
			offset = Vector3.new(1.8, 0, -3),
			turn = 20,
			fallback = Vector3.new(-33.2, 0, 147),
		},
		idle = "lookAround",
		look = {
			name = "Gus",
			role = "Gondola operator",
			seed = 67,
			skin = hex("#DDA27E"),
			shirt = hex("#EFE9DD"),
			pants = hex("#34405E"),
			boots = hex("#2E2622"),
			hair = hex("#C9C3BA"),
			hairStyle = "short",
			beard = "handlebar",
			beardColor = hex("#D8D2CA"),
			hat = "conductor",
			hatColor = hex("#2B3A5C"),
			hatTrim = hex("#E1B530"),
			vest = hex("#2E3F66"),
			scarf = hex("#B8423A"),
		},
		greetings = { "All aboard!", "Ahoy, groundling!", "Tickets, please! Just kidding." },
		lines = {
			"Up she goes to the Aether Isles! The view's free, the ride isn't.",
			"Lumenwood glows up there. Pretty as a sunrise, heavy as regret.",
			"Fall off an isle? The clouds are soft. The ground is not.",
			"The Skyroot hums at night. I swear it's singing.",
			"Logs from the isles go down a Cloud Chute. Millie catches 'em in the Sky Bin.",
			"Sky Shards up top feed the Starfall Forge. Bring a strong axe.",
		},
	},
	{
		id = "Rosa",
		name = "Rosa",
		role = "Forager",
		spot = { kind = "route" },
		speed = 4.6,
		route = {
			{ x = -32, z = 58 },
			{ x = -50, z = 66 },
			{ x = -78, z = 84, pause = 4, face = 180 }, -- window-shopping at Hearth & Home
			{ x = -60, z = 82 },
			{ x = -45, z = 84, pause = 3, face = 180 }, -- and at the Tool Shed
			{ x = -38, z = 85 }, -- round the well
			{ x = -24, z = 76 },
			{ x = -22, z = 64 }, -- between the street lamps
		},
		idle = "lookAround",
		look = {
			name = "Rosa",
			role = "Forager",
			seed = 71,
			skin = hex("#B7835E"),
			shirt = hex("#4E8A3E"),
			stripe = hex("#2C4E24"),
			pants = hex("#6A4A30"),
			cuffs = true,
			boots = hex("#4E3220"),
			hair = hex("#3A2418"),
			hairStyle = "ponytail",
			hatTrim = hex("#E2574C"),
			rolledSleeves = true,
			carry = "basket",
		},
		greetings = { "Oh! Hi there!", "Lovely day for it!", "Hello, neighbour!" },
		lines = {
			"Found three chanterelles by the river. Don't tell anyone!",
			"Berries taste better after rain. So do mushrooms. Probably.",
			"When the grove's thriving, the deer come out. Replant a stump and watch.",
			"The Phantom Grove's mushrooms glow at night. I only pick the ones that don't hum.",
			"A tree you plant wears your name. Isn't that sweet?",
		},
	},
	{
		id = "Pip",
		name = "Pip",
		role = "Apprentice",
		spot = { kind = "route" },
		speed = 6,
		route = {
			{ x = 20, z = 70 },
			{ x = 36, z = 76 },
			{ x = 45, z = 85, pause = 3, face = 180 }, -- staring at the trucks
			{ x = 38, z = 80 }, -- back along the street
			{ x = 20, z = 82, pause = 2.5, face = 110 }, -- watching the saw
		},
		idle = "lookAround",
		look = {
			name = "Pip",
			role = "Apprentice",
			seed = 83,
			scale = 0.78,
			skin = hex("#F2CDB0"),
			shirt = hex("#F0A030"),
			pants = hex("#5577AA"),
			overalls = hex("#5577AA"),
			boots = hex("#7A4A2A"),
			hair = hex("#7A4A28"),
			hairStyle = "short",
			hat = "hardhat",
			hatColor = hex("#F2C230"),
			hatTrim = hex("#D9A520"),
			carry = "sapling",
		},
		greetings = { "Hi hi hi!", "Whoa, is that YOUR axe?", "Hey! Wanna see my tree?" },
		lines = {
			"When I grow up I'm gonna fell an Elder tree. With everybody!",
			"Murph says if you plant a Heartseed, the tree knows your name.",
			"I'm growing this one myself. Its name is Gerald.",
			"Did you know trees hit by lightning glow? I saw one! Kinda.",
			"Millie says I can work the saw when I'm taller. I'm almost taller!",
		},
	},
	{
		id = "Bram",
		name = "Old Bram",
		role = "Retired logger",
		spot = { kind = "route" },
		speed = 2.6,
		route = {
			{ x = -17, z = 50 },
			{ x = -18, z = 66, pause = 5, face = 104 }, -- watching the saw
			{ x = -15.5, z = 64 },
			{ x = -15, z = 52, pause = 4, face = 270 }, -- watching the street
		},
		idle = "lookAround",
		look = {
			name = "Old Bram",
			role = "Retired logger",
			seed = 97,
			skin = hex("#D9A07A"),
			shirt = hex("#3B5E9A"),
			stripe = hex("#1E2E4E"),
			pants = hex("#5C5040"),
			boots = hex("#4A3020"),
			hair = hex("#E8E2D8"),
			hairStyle = "bald",
			beard = "handlebar",
			beardColor = hex("#ECE6DC"),
			suspenders = hex("#A33A2E"),
			carry = "cane",
		},
		greetings = { "Eh? Oh, hello, youngster.", "Fine day, fine day.", "Ah, another lumberjack!" },
		lines = {
			"Murph? Ha! I out-chopped him in '62. He'll tell you different.",
			"Lightning struck a pine right in front of me once. Stormgrain, they call it. Sold it for a fortune.",
			"My knees creak louder than a falling oak.",
			"Read the bark, youngster. The Field Guide shows you the clues, the forest does the rest.",
			"Big old trees wake up when a grove's well loved. Takes the whole town to fell one.",
		},
	},
} :: { NPC }

local byId: { [string]: NPC } = {}
for _, npc in ipairs(NPCData.List) do
	byId[npc.id] = npc
end

function NPCData.Get(id: string): NPC?
	return byId[id]
end

function NPCData.All(): { NPC }
	return NPCData.List
end

-- The shops that need a keeper behind their Counter.
NPCData.Shops = { "ToolShed", "Dealership", "HearthAndHome" }

---------------------------------------------------------------------------
-- Spots
---------------------------------------------------------------------------

-- How far behind a counter's back face a keeper's centre stands.
NPCData.CounterGap = 1.25

-- Standing behind a shop counter: on the counter's floor (its bottom), on
-- its back (+Z) side, facing the customers (its -Z side, where MapBuilder
-- puts the ShopPoint).
function NPCData.BehindCounter(counter: CFrame, size: Vector3): CFrame
	return counter * CFrame.new(0, -size.Y / 2, size.Z / 2 + NPCData.CounterGap)
end

-- Standing beside a part (a platform, a zone), on the ground under it.
function NPCData.Beside(part: CFrame, size: Vector3, offset: Vector3, turnDegrees: number?): CFrame
	local edge = if offset.X >= 0 then size.X / 2 else -size.X / 2
	return part * CFrame.new(edge + offset.X, -size.Y / 2, offset.Z) * CFrame.Angles(0, math.rad(turnDegrees or 0), 0)
end

-- Where an NPC stands (its feet; facing its LookVector). `find(model,
-- part)` returns that part's CFrame and Size in the built world, or nil.
function NPCData.SpotFor(npc: NPC, find: (model: string, part: string) -> (CFrame?, Vector3?)): CFrame
	local spot = npc.spot
	if spot.kind == "fixed" then
		local pos = spot.position or Vector3.zero
		local look = spot.lookAt or (pos - Vector3.zAxis)
		-- A turn about Y rather than CFrame.lookAt: upright, and the same in
		-- Lune (whose lookAt disagrees with Roblox's) as in the game.
		return CFrame.new(pos) * CFrame.Angles(0, NPCData.YawOf(look.X - pos.X, look.Z - pos.Z), 0)
	elseif spot.kind == "counter" or spot.kind == "beside" then
		local cf, size = find(spot.model or "", if spot.kind == "counter" then "Counter" else (spot.part or ""))
		if cf and size then
			if spot.kind == "counter" then
				return NPCData.BehindCounter(cf, size)
			end
			return NPCData.Beside(cf, size, spot.offset or Vector3.zero, spot.turn)
		end
		return CFrame.new(spot.fallback or Vector3.zero)
	end
	-- A walker starts at its first waypoint, facing the second.
	local route = npc.route or {}
	local x, z, yaw = NPCData.RouteState(route, npc.speed or 4, 0)
	return CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
end

---------------------------------------------------------------------------
-- Routes
---------------------------------------------------------------------------

-- Seconds a walker takes to turn on the spot at a waypoint.
NPCData.TurnTime = 0.6

local function fmt(n: number): string
	local s = string.format("%.2f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

-- "x,z,pause,face;..." for a model attribute (pause and face optional).
function NPCData.EncodeRoute(route: { Waypoint }): string
	local parts: { string } = {}
	for _, w in ipairs(route) do
		local fields = { fmt(w.x), fmt(w.z) }
		if w.pause or w.face then
			table.insert(fields, fmt(w.pause or 0))
		end
		if w.face then
			table.insert(fields, fmt(w.face))
		end
		table.insert(parts, table.concat(fields, ","))
	end
	return table.concat(parts, ";")
end

function NPCData.DecodeRoute(text: string): { Waypoint }
	local out: { Waypoint } = {}
	for chunk in string.gmatch(text, "[^;]+") do
		local nums: { number } = {}
		for field in string.gmatch(chunk, "[^,]+") do
			local n = tonumber(field)
			if n == nil then
				return {}
			end
			table.insert(nums, n)
		end
		if #nums < 2 then
			return {}
		end
		local pause = nums[3]
		table.insert(out, {
			x = nums[1],
			z = nums[2],
			pause = if pause and pause > 0 then pause else nil,
			face = nums[4],
		})
	end
	return out
end

-- The yaw (radians) that faces along (dx, dz): CFrame.Angles(0, yaw, 0)
-- looks that way (0 = -Z).
function NPCData.YawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + d * t
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

type Leg = { x: number, z: number, len: number, yaw: number, stop: number, face: number? }

type Prepared = { legs: { Leg }, cycle: number, total: number, speed: number }

-- Worked-out legs per route table (clients decode a route once and reuse it).
local cache: { [any]: Prepared } = setmetatable({}, { __mode = "k" }) :: any

local function prepare(route: { Waypoint }, speed: number): Prepared
	local key = route :: any
	local hit = cache[key]
	if hit and hit.speed == speed then
		return hit
	end
	local legs: { Leg } = {}
	local n = #route
	local cycle, total = 0, 0
	for i, w in ipairs(route) do
		local nxt = route[i % n + 1]
		local dx, dz = nxt.x - w.x, nxt.z - w.z
		local len = math.sqrt(dx * dx + dz * dz)
		local face = if w.face then math.rad(w.face) else nil
		local stop = math.max(w.pause or 0, if face then NPCData.TurnTime * 2 else NPCData.TurnTime)
		table.insert(legs, { x = w.x, z = w.z, len = len, yaw = NPCData.YawOf(dx, dz), stop = stop, face = face })
		cycle += stop + len / speed
		total += len
	end
	local out = { legs = legs, cycle = math.max(cycle, 0.01), total = total, speed = speed }
	cache[key] = out
	return out
end

-- Where a walker is `t` seconds into its loop (any t; it repeats). Returns
-- x, z, yaw (radians; CFrame.Angles(0, yaw, 0)), whether it's walking, and
-- how far it has walked in total (drives the stride, never jumps).
-- The loop: stop at waypoint 1 (turning to the next leg), walk to 2, stop,
-- walk... and back to 1. At a stop with `face` it turns to face that way,
-- waits, then turns to go on.
function NPCData.RouteState(route: { Waypoint }, speed: number, t: number): (number, number, number, boolean, number)
	local n = #route
	if n == 0 then
		return 0, 0, 0, false, 0
	elseif n == 1 then
		local w = route[1]
		return w.x, w.z, if w.face then math.rad(w.face) else 0, false, 0
	end
	speed = math.max(speed, 0.1)
	local p = prepare(route, speed)
	local laps = math.floor(t / p.cycle)
	local rem = t - laps * p.cycle
	local walked = laps * p.total
	local turn = NPCData.TurnTime
	for i, leg in ipairs(p.legs) do
		local prev = p.legs[(i - 2) % n + 1]
		if rem < leg.stop then
			local yaw
			local face = leg.face
			if face then
				if rem < turn then
					yaw = lerpAngle(prev.yaw, face, smooth(rem / turn))
				elseif rem > leg.stop - turn then
					yaw = lerpAngle(face, leg.yaw, smooth((rem - (leg.stop - turn)) / turn))
				else
					yaw = face
				end
			else
				yaw = lerpAngle(prev.yaw, leg.yaw, smooth((rem - (leg.stop - turn)) / turn))
			end
			return leg.x, leg.z, yaw, false, walked
		end
		rem -= leg.stop
		local walkTime = leg.len / speed
		if rem < walkTime then
			local f = rem / walkTime
			local nxt = p.legs[i % n + 1]
			return leg.x + (nxt.x - leg.x) * f, leg.z + (nxt.z - leg.z) * f, leg.yaw, true, walked + leg.len * f
		end
		rem -= walkTime
		walked += leg.len
	end
	local first = p.legs[1]
	return first.x, first.z, first.yaw, false, walked
end

-- A walker's loop length in seconds.
function NPCData.CycleTime(route: { Waypoint }, speed: number): number
	if #route < 2 then
		return 0
	end
	return prepare(route, math.max(speed, 0.1)).cycle
end

-- A stable offset (seconds) per NPC so walkers don't move in lockstep.
function NPCData.RouteOffset(id: string): number
	local h = 0
	for i = 1, #id do
		h = (h * 131 + string.byte(id, i)) % 9973
	end
	return h % 60
end

return NPCData
