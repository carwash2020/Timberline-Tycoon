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
--
-- Each NPC has a job (`work`: chop, saw, sweep, or carry), a name and a
-- role for the name tag, and a Talk prompt NPCService parents to the
-- model so it streams in with them. `react` is the situational lines
-- (hour, weather, the first sale, the first real axe, a sawmill);
-- `tips` is the short onboarding Murph gives a new player. NPCDialogue
-- picks among them.

local CharacterArt = require(script.Parent.Art.CharacterArt)
local FerryLogic = require(script.Parent.FerryLogic)
local ShopHoursLogic = require(script.Parent.ShopHoursLogic)
local TollLogic = require(script.Parent.TollLogic)

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
	ground: number?, -- fixed, away from the flat town: stand this far above the terrain at (x, z) (NPCService)
}

export type Waypoint = {
	x: number,
	z: number,
	pause: number?, -- seconds standing here
	face: number?, -- degrees to face while paused (0 = -Z, 90 = -X, 180 = +Z)
}

-- Situational lines. NPCDialogue picks one pool; empty fields are skipped.
export type React = {
	morning: { string }?,
	day: { string }?,
	evening: { string }?,
	night: { string }?,
	rain: { string }?,
	storm: { string }?,
	fog: { string }?,
	rusty: { string }?, -- still on the starter axe
	axe: { string }?, -- bought a better one
	unsold: { string }?, -- hasn't sold wood yet
	sale: { string }?, -- has
	sawmill: { string }?, -- bought or placed one
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
	work: ("chop" | "saw" | "sweep" | "carry")?, -- a work clip, client-side (NPCAnim)
	workLoops: number?, -- chops in a row (a saw or a sweep is already a phrase)
	promptLift: number?, -- Talk's UIOffset Y, so it sits above a shop or pad prompt
	shop: string?, -- a counter keeper's shop id (ShopHoursLogic). Nil for everyone else.
	tutorialQuiet: boolean?, -- no chatter while the tutorial runs (QuestUI owns Murph's lines; one tip still plays)
	tips: { string }?, -- onboarding, the first time a new player meets them
	greetings: { string },
	lines: { string },
	react: React?,
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
		-- the camp at (-28, 45) turned toward the spawn, 3 studs out).
		spot = { kind = "fixed", position = Vector3.new(-25.0467, 0, 44.4726), lookAt = Vector3.new(0, 0, 40) },
		idle = "sip",
		work = "chop",
		tutorialQuiet = true,
		promptLift = 0,
		tips = {
			"I'm Murph. Chop a tree, haul the wood, sell it at the mill.",
			"Follow the amber arrow. Press F if you forget the step.",
			"The little oaks just to your left. They're the friendly ones.",
		},
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
			"Fell a tree and it grows back somewhere else in the stand. Give it room.",
			"The Gloam Hollow only shows itself after dark. Bring a lantern. And your nerve.",
			"Curly bark, dimpled bark, lumpy bark... that's figure hidin' in the grain. Don't sell it cheap.",
			"See that giant up yonder? The Skyroot. Been growin' since before I was a sapling.",
			"This coffee's older than your truck. Tastes it, too.",
			"When a storm rolls in, watch for the tree that glows. Lightning wood's worth a fortune.",
			"I've retired three times. The forest keeps callin' me back.",
			"Your Field Guide's got empty pages, kid. Go fill 'em.",
		},
		react = {
			morning = {
				"Mornin'. Coffee first. The woods can wait one sip.",
				"Dawn's the best time to fell. The birds agree.",
			},
			evening = { "Sun's headed down. One more load before dark?" },
			night = {
				"Dark already? The Gloam Hollow wakes up about now.",
				"I keep the fire going. Night chopping is for owls.",
			},
			rain = { "Rain's good for saplings. Slippery for boots, though." },
			storm = { "If a tree glows in the storm, that's lightning wood." },
			fog = { "Fog like this, stay on the road. The hollow can wait." },
			rusty = { "That rusty axe'll do for oaks. The hills want better." },
			axe = { "Now that's an axe. The hills won't know what hit them." },
			unsold = { "Mill's up the road. Green pad. You can't miss it." },
			sale = { "First sale's the sweet one. Don't spend it all on coffee." },
			sawmill = { "Your own saw? Planks pay better than the same log." },
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
			-- From the zone's middle (z 82 since M1.5 deepened it south): she
			-- stands where she always has, (14.6, 92.5), by the pad's east edge.
			offset = Vector3.new(2.6, 0, 10.5),
			turn = 40,
			fallback = Vector3.new(14.6, 0, 92.5),
		},
		idle = "clipboard",
		work = "saw",
		promptLift = 80,
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
			"Wood you lay in a Cloud Chute waits for you in the Sky Bin, right over there.",
			"Replant a stump and it grows back for you. Anybody fells it, you get a share!",
			"Sawdust in my hair, sawdust in my tea. Wouldn't have it any other way.",
			"Rare wood's worth more at the mill. Lumenwood glows right through the till.",
		},
		react = {
			morning = { "Blade's warmed up. I'm ready when you are." },
			night = { "I keep the lamp on. Night loads pay the same." },
			rain = { "Wet logs still sell. I don't mind the mud." },
			storm = { "Blade's loud, but that thunder's louder." },
			unsold = { "Back the truck onto the green, sweetie. She'll sell." },
			sale = { "Heard the till sing. Bring me another load." },
			sawmill = { "A saw of your own? I still buy the planks." },
			rusty = { "Any axe'll do. The pad pays the wood, not the tool." },
		},
	},
	{
		id = "Tink",
		name = "Tink",
		role = "Axe smith",
		shop = "ToolShed",
		spot = { kind = "counter", model = "ToolShed", fallback = Vector3.new(-57, 0, 110) },
		idle = "glasses",
		work = "chop",
		promptLift = 150,
		look = {
			name = "Tink",
			role = "Axe smith",
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
		react = {
			morning = { "Sharpest in the morning. The axes, not me." },
			night = { "Shop's still open. Axes don't sleep." },
			rain = { "Rain rusts an edge. Step inside and I'll look." },
			rusty = { "Rusty to Steel. Best upgrade you'll make. Until the next." },
			axe = { "Look at that edge. I do good work, if I say so." },
			unsold = { "Sell a load at the mill, then come back for a better axe." },
			sale = { "Till's been ringing. Ready for a real edge?" },
			sawmill = { "Saws are on the other board. Axes are my favourite." },
		},
	},
	{
		id = "Dale",
		name = "Dale",
		role = "Truck dealer",
		shop = "Dealership",
		spot = { kind = "counter", model = "Dealership", fallback = Vector3.new(48, 0, 110.4) },
		idle = "wipe",
		promptLift = 80,
		look = {
			name = "Dale",
			role = "Truck dealer",
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
			"Lay your wood flat on the bed before you drive. Take the corners slow. Trust me.",
			"I can fix anything. Except my sense of direction.",
		},
		react = {
			morning = { "Roads are empty this early. Good day for a test drive." },
			day = { "That Rustbucket's got one more hill in her. Probably." },
			rain = { "Wet roads. Take the corners slow. I mean it." },
			storm = { "Don't race a storm in the Rustbucket. She loses." },
			unsold = { "Sell a load first. Then we'll talk about a bigger bed." },
			sale = { "Cash in your pocket? I've got a truck with your name on it." },
			axe = { "Nice axe. It won't haul the logs, though. That's my job." },
		},
	},
	{
		id = "Hazel",
		name = "Hazel",
		role = "Gear keeper",
		shop = "HearthAndHome",
		spot = { kind = "counter", model = "HearthAndHome", fallback = Vector3.new(-93.5, 0, 110.3) },
		idle = "lookAround",
		work = "sweep",
		promptLift = 80,
		look = {
			name = "Hazel",
			role = "Gear keeper",
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
			"No lantern, no Gloam Hollow, dear. The dark out there is hungry.",
			"Snowfields? You'll want the Insulated Coat. Three layers of wool and a pocket for snacks.",
			"Heat Boots, for the volcano. Unless you like toasted toes.",
			"A Featherfall Cloak turns a fall off the isles into a nice float down.",
			"I knitted this scarf from fireflies. Well, from yarn. But I thought about fireflies.",
			"A well-loved forest gets busier. Deer, butterflies, birdsong. Plant a few seeds, you'll see.",
		},
		react = {
			morning = { "I swept the porch at dawn. Try not to track the woods in." },
			evening = { "Getting dark, dear. A lantern is cheaper than a bruise." },
			night = { "Lantern's by the door if you're heading to the hollow." },
			rain = { "Come in, you'll drip on my floor. I just swept it." },
			fog = { "Fog's thick. Take the coat. And a snack." },
			storm = { "Storm weather. The coat stays dry. Mostly." },
			unsold = { "Sell a little wood first, dear. Then we'll fit you out." },
			sale = { "A sale already? Treat yourself to something warm." },
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
		promptLift = 80,
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
		react = {
			morning = { "First car up is the quiet one. Best view, too." },
			evening = { "Evening run turns the isles gold. Worth the fare." },
			night = { "Night ride's the pretty one. The Skyroot glows." },
			storm = { "Cable hums in a storm. She still rides." },
			fog = { "Fog below, stars above. That's the whole ride." },
			unsold = { "Sell a load first. The isles will still be up there." },
			sale = { "A fare, then? The view's free. The ride isn't." },
			axe = { "That axe'll do on the isles. Mind the edge of the cloud." },
		},
	},
	{
		id = "Rosa",
		name = "Rosa",
		role = "Forager",
		spot = { kind = "route" },
		speed = 4.6,
		work = "carry",
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
			"The Gloam Hollow's mushrooms glow at night. I only pick the ones that don't hum.",
			"A tree you plant wears your name. Isn't that sweet?",
		},
		react = {
			morning = { "The deer are out if you walk soft. I always do." },
			day = { "Basket's for berries. And the occasional pinecone." },
			rain = { "Berries taste better after rain. Don't tell a soul." },
			storm = { "I pick nothing that hums. Storm mushrooms hum." },
			unsold = { "New here? The green pad by the mill buys your wood." },
			sale = { "You sold some! The forest notices. So do I." },
			sawmill = { "Your own saw? Save me a curly offcut. For the basket." },
		},
	},
	{
		id = "Pip",
		name = "Pip",
		role = "Apprentice",
		spot = { kind = "route" },
		speed = 6,
		work = "chop",
		workLoops = 2,
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
			"Murph says the forest grows a new tree when you fell one. I named mine Gerald.",
			"Did you know trees hit by lightning glow? I saw one! Kinda.",
			"Millie says I can work the saw when I'm taller. I'm almost taller!",
		},
		react = {
			morning = { "I'm practicing swings before school. Gerald's watching." },
			day = { "Gerald grew a whole inch. I measured. With a stick." },
			rain = { "Rain makes the grip slippery. I still chopped. Kinda." },
			rusty = { "Your axe is bigger than mine. Kinda. Almost." },
			axe = { "Whoa. That axe could fell Gerald. Please don't." },
			unsold = { "Millie pays you at the green pad. I checked. Twice." },
			sale = { "You sold wood! Millie smiled. I saw it." },
			sawmill = { "You got a saw? I'm almost tall enough to help. Almost." },
		},
	},
	{
		id = "Bram",
		name = "Old Bram",
		role = "Retired logger",
		spot = { kind = "route" },
		speed = 2.6,
		work = "carry",
		route = {
			-- The south end sits north of the woods sign's posts. A tighter
			-- line clips the sign (the board and its rocks reach this far).
			{ x = -17, z = 50.35 },
			{ x = -18, z = 66, pause = 5, face = 104 }, -- watching the saw
			{ x = -15.5, z = 64 },
			{ x = -15, z = 52.35, pause = 4, face = 270 }, -- watching the street
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
		react = {
			morning = { "Fine mornin'. Murph still owes me from '62." },
			evening = { "Knees say it's evening. The sun can catch up." },
			night = { "These knees and this dark. One of them should retire." },
			storm = { "Lightning wood. Sold a piece once. Still bragging." },
			rain = { "Rain on a bald head. That's why the young wear hats." },
			unsold = { "Haven't sold yet? The pad is that green bit. Can't miss it." },
			sale = { "A sale. Good. I out-chopped Murph with less." },
			axe = { "Steel, is it? I felled oaks with worse. Don't tell Tink." },
		},
	},
	{
		-- The Secret Cave's keeper (HermitService). Stands inside the room,
		-- facing the open mouth; HermitService sets his feet on the floor.
		-- His quest talk is DialogueData.HermitLines; these are his bubbles.
		id = "Hermit",
		name = "The Hermit",
		role = "Keeper of the cave",
		spot = { kind = "fixed", position = Vector3.new(-755, 0, -652), lookAt = Vector3.new(-755, 0, -700) },
		idle = "lookAround",
		promptLift = 0,
		look = {
			name = "The Hermit",
			role = "Keeper of the cave",
			seed = 131,
			skin = hex("#D2A27E"),
			shirt = hex("#5E6B4A"),
			pants = hex("#4A4034"),
			boots = hex("#3A2A1E"),
			hair = hex("#C9C3B8"),
			hairStyle = "bald",
			beard = "big",
			beardColor = hex("#D6D0C4"),
			brows = hex("#D6D0C4"),
			hat = "flatcap",
			hatColor = hex("#6B5A44"),
			hatTrim = hex("#4F4232"),
			carry = "lantern",
			accent = hex("#F2C14E"),
		},
		greetings = { "Oh. A visitor.", "Mind your head.", "Come in, come in." },
		lines = {
			"Five carvings, five wild places. I made them. My thumbs remember.",
			"It's dark in here by choice. A Lantern helps, if you have one.",
			"Quiet, isn't it? I like it quiet.",
			"The Maul is slow. Slow is not the same as weak.",
			"Sit a while. The cave doesn't hurry.",
		},
		react = {
			night = { "Night out there, night in here. We match." },
			rain = { "Hear the rain? It sounds nicer from in here." },
			storm = { "Thunder. The cave hums back. Listen." },
			morning = { "Morning. I think. It's hard to tell in here." },
			axe = { "A better axe? Then you'll want to see the Maul." },
		},
	},
	{
		-- Old Tolly keeps the toll booth east of the bridge (WorldLayout
		-- BoothX/BoothZ; LandmarkArt.TollBooth). Stands inside it behind the
		-- counter, on the booth floor, facing the road. His price talk is
		-- built from TollLogic, so it follows GameConfig.TollFee.
		id = "OldTolly",
		name = "Old Tolly",
		role = "Toll keeper",
		spot = {
			kind = "fixed",
			position = Vector3.new(22, 0, 1566),
			lookAt = Vector3.new(22, 0, 1500),
			ground = 1, -- the booth floor's thickness
		},
		idle = "clipboard",
		promptLift = 80, -- above the booth counter's toll prompt
		look = {
			name = "Old Tolly",
			role = "Toll keeper",
			seed = 211,
			skin = hex("#D8A47E"),
			shirt = hex("#8A5A3A"),
			pants = hex("#4E4A3E"),
			boots = hex("#3A281C"),
			hair = hex("#D9D3C8"),
			hairStyle = "short",
			beard = "mustache",
			beardColor = hex("#D9D3C8"),
			hat = "cap",
			hatColor = hex("#3E5A44"),
			hatTrim = hex("#2C4032"),
			glasses = hex("#5A4630"),
			vest = hex("#2F4A38"),
			carry = "clipboard",
		},
		greetings = { "Afternoon, traveller.", "Mind the arm, it swings.", "Well met, friend." },
		lines = {
			TollLogic.TalkLines()[1],
			TollLogic.TalkLines()[2],
			TollLogic.TalkLines()[3],
			"A driver who pays takes the truck and a passenger across, too.",
			"The gorge is deep and the bridge is sturdy. Trust the one, mind the other.",
			"I've kept this booth since before the rails went up. Quiet work, good company.",
		},
		react = {
			morning = { "Early start. The bridge likes the quiet hours." },
			day = { "Busy day on the road. Booth's open, as ever." },
			evening = { "Last crossings before dark. Don't dawdle." },
			night = { "Lantern's lit. I'll be here, same as always." },
			rain = { "Wet planks, careful feet. Cross slow." },
			storm = { "Thunder over the gorge. Best wait it out here." },
			fog = { "Can't see the far bank. It's still there, I promise." },
		},
	},
	{
		-- Cap'n Moss captains the ferry from the mainland dock (WorldLayout
		-- FerryDock), at the dock's west end, off the boarding edge, facing
		-- the water. Fare and timetable talk is built from FerryLogic.
		id = "CapnMoss",
		name = "Cap'n Moss",
		role = "Ferry captain",
		spot = {
			kind = "fixed",
			position = Vector3.new(1177, 0, -697),
			lookAt = Vector3.new(1260, 0, -697),
			ground = 1, -- the dock deck's thickness
		},
		idle = "lookAround",
		promptLift = 80, -- above the dock's Board prompt
		look = {
			name = "Cap'n Moss",
			role = "Ferry captain",
			seed = 223,
			stout = true,
			skin = hex("#C98E68"),
			shirt = hex("#2E4F73"),
			stripe = hex("#E8E2D4"),
			pants = hex("#3A3F4A"),
			boots = hex("#2E2218"),
			hair = hex("#B8B2A6"),
			hairStyle = "short",
			beard = "big",
			beardColor = hex("#B8B2A6"),
			hat = "conductor",
			hatColor = hex("#1F3552"),
			hatTrim = hex("#D8B04A"),
			carry = "lantern",
			accent = hex("#F2C14E"),
		},
		greetings = { "Ahoy, landlubber.", "Mind the gap, mate.", "Fair crossing today." },
		lines = {
			FerryLogic.TalkLines()[1],
			FerryLogic.TalkLines()[2],
			FerryLogic.TalkLines()[3],
			"No trucks on deck. She's a boat, not a barge.",
			"Stand on the planks and hold on. The island doesn't move.",
			"Forty years on this water. Never lost a passenger. Misplaced a plank or two.",
		},
		react = {
			morning = { "Morning tide's kind. Good time to cross." },
			day = { "Sun on the water. Hard to beat." },
			evening = { "Last light on the island. Worth the fare." },
			night = { "Lantern on the bow. I know these waters blind." },
			rain = { "A little rain never sank a ferry. Come aboard." },
			storm = { "Swell's up. She'll still sail, mind your feet." },
			fog = { "Fog on the water. I sail by ear and habit." },
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

-- Talk, on every NPC. E and ButtonX, the same Interact key as Buy (InputKit
-- lets Talk and Buy share it; the door uses Open, F / ButtonY, so a closed
-- door never takes the talk button). ClickablePrompt covers a mouse click;
-- PromptUI's card covers a tap. Line of sight stays off: hats, counters,
-- and streaming would hide the prompt otherwise.
NPCData.TalkDistance = 12
NPCData.TalkKeyboard = Enum.KeyCode.E
NPCData.TalkGamepad = Enum.KeyCode.ButtonX

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

-- Lying behind the counter, on the same spot as BehindCounter, low enough
-- that the body's top is SleepClearance under the counter top. Up is the
-- counter's LookVector (flat), so the keeper is not standing. fromMatrix,
-- not lookAt: Lune's lookAt disagrees with Roblox.
function NPCData.SleepCFrame(counter: CFrame, size: Vector3): CFrame
	local stand = NPCData.BehindCounter(counter, size)
	local top = counter.Position.Y + size.Y / 2
	local y = top - ShopHoursLogic.SleepClearance - ShopHoursLogic.SleepBodyHalf
	local pos = Vector3.new(stand.Position.X, y, stand.Position.Z)
	local up = counter.LookVector
	local look = -Vector3.yAxis
	local right = up:Cross(look)
	if right.Magnitude < 1e-4 then
		right = counter.RightVector
	else
		right = right.Unit
	end
	return CFrame.fromMatrix(pos, right, up, -look)
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

-- Turning to face you: within FaceRange studs a standing NPC (and a
-- walker stopped at a waypoint) turns its whole body toward you, at most
-- TurnRate radians a second, and back to where it was facing once you go.
NPCData.FaceRange = 16
NPCData.TurnRate = 3.5

-- `current` turned toward `target` (radians) by at most `maxStep`, the
-- short way round.
function NPCData.TurnToward(current: number, target: number, maxStep: number): number
	local d = (target - current + math.pi) % (math.pi * 2) - math.pi
	if math.abs(d) <= maxStep then
		return target
	end
	return current + (if d > 0 then maxStep else -maxStep)
end

-- Which way an NPC at `pos` wants to face: toward `player` (a position, or
-- nil) when it is within `range` (flat distance), else `home`.
-- The nearest point in `points` within `maxDist` studs (flat), ignoring
-- anyone standing inside half a stud (no spin when you're on their toes).
-- Returns the index, or nil.
function NPCData.NearestIndex(origin: Vector3, points: { Vector3 }, maxDist: number): number?
	local best: number? = nil
	local bestD = maxDist
	for i, p in ipairs(points) do
		local dx, dz = p.X - origin.X, p.Z - origin.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < bestD and d > 0.5 then
			best = i
			bestD = d
		end
	end
	return best
end

function NPCData.FaceYaw(home: number, pos: Vector3, player: Vector3?, range: number): number
	if player then
		local dx, dz = player.X - pos.X, player.Z - pos.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < range and d > 0.5 then
			return NPCData.YawOf(dx, dz)
		end
	end
	return home
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
