# Lumber Tycoon 2 research: world design and trees

What Connor wants (3 Oct 2026): "style it closer to that experience, mostly
world design and how trees are". This is what Lumber Tycoon 2 (LT2) does,
gathered from its wikis and guides (fandom wiki, NamuWiki, fan map guides;
the pages themselves are blocked from this environment, so this is from
search extracts). Our own names stay ours (V2_PLAN §2g): no LT2 names in
`src/`.

## Trees

- **A tree is a hierarchy of boxes.** Each section is a square-section box;
  the trunk is a stack of them, each angled a little from the last; limbs
  branch off as thinner boxes. Chopping a section "unparents" everything
  above it, which falls as one piece. Each piece is visibly an individual
  section you can chop again.
- **Bark and core.** A log has an outer bark layer and an inner core. The
  core is usually lighter than the bark (dark woods like walnut are the
  exception) and is the plank colour. It shows only at cut ends. Woods are
  told apart by bark colour and Roblox material: Wood, Concrete, Granite,
  Pebble, SmoothPlastic, Ice, Neon.
- **Leaves are crisp cubes.** Big cubic or rectangular leaf blocks at branch
  tips and over the upper sections, often alternating light and dark shades
  (koa: "massive rectangular cubic leaves, alternating light-green and
  dark-green, covering the upper logs so the tree looks taller"). Leaf
  blocks keep their size as a tree grows; a sapling is a small cube, and the
  shape changes when the first branches form.
- **Each wood has its own silhouette**, for example:
  - oak: small, rarely taller than birch, brown bark, nougat core
  - birch: tall and skinny, tan bark, big green cube leaves
  - pine and fir: tall and straight, rust or yellow-brown
  - cherry: dark bark, pinkish-white pebble-textured leaves
  - palm: a slanted trunk, fronds jutting from the top, no branches
  - frost: smooth white bark, translucent teal leaves, ice-textured core
  - volcano: thick and large, angular branches, bright red bark, a few
    brown leaves
  - gold: tall, no leaves, a few narrow branches
  - zombie: sea-green concrete bark, grey granite leaves, grows sideways
  - snowglow: neon yellow glowing bark
- **Growth.** Trees grow in many small stages (60 to 75 stages, one every
  150 to 200 s), live several hours, then die. Rare trees have per-biome
  caps (Phantom: one at a time).
- **Placement is sparse.** Individual trees with open grass between them,
  loose groves of one species, and a pink cherry meadow as a colour pop.

## World

- **One landmass along an ocean**, made of large regions. Each region is
  sealed by cliffs, a river or the sea, and has one landmark gate:
  - Main Biome (spawn): a large expanse of dark green grass with brown rocks
    scattered across it, mostly flat. Oak most common, plus cherry and elm.
    It holds the wood store, the dropoff and the land store.
  - The River and the Bridge: a big blue-grey lift bridge with toll booths,
    lowered for 3 minutes for $100, leads to the Safari.
  - Safari: a large flat expanse of light-green grass with large brown rocks.
    Walnut (only here), elm and cherry. Furniture, car and gear shops.
  - Taiga: a flat expanse of snow enclosed by brown cliffs (dynamite opens
    the way). Pine and fir. Taiga Peak on the cliffs has a frosty mist and
    frost trees, with thin paths that are obstacles for big trucks.
  - Mountainside and the Volcano: a gravel road climbs to the volcano at the
    top. Red fog inside (about 15 studs of sight), boulders roll down the
    path, lava, volcano wood at the peak.
  - Swamp: small, brown grass around a shallow river, low mist. Gold
    (leafless) and zombie trees. Reached through a cavern or a mountain
    passage.
  - Tropics: across the ocean by ferry ($400). Palm and koa, sand.
  - Cherry Meadow: an enclosed pink mini-biome.
- **Roads**: wide (32 to 48 studs), straight runs with angled joints, light
  grey concrete or pebble. Paths: a beige gravel path up the mountainside, a
  stony lava trail.
- **Buildings**: big boxy stores with huge colourful name signs; rustic
  wooden shacks and cabins.
- **Look and feel**: a muted natural palette (dark green, brown rock, grey
  concrete, white snow, beige sand), colour from signs and rare glowing
  trees. Fog thickens at night (about 23:00) and lifts in the morning
  (about 09:00); low mist in the swamp, frosty mist on peaks; nights are
  genuinely dark.

## What that means for Timberline (the plan)

1. **Trees (TREE slice, under way):**
   - visible square box sections with bark material and a lighter core at
     cut ends
   - crisp cube leaves in alternating shades
   - a distinct silhouette per wood
   - sparse groves with open grass between them, at least 775 trees
2. **World (WORLD slice, after TREE and VEH land):**
   - Roads: wide, pale grey roads sized for the bigger trucks.
   - The town region: open dark-green grass with scattered brown boulders.
   - Each region sealed by cliffs, the river or the sea, with one landmark
     gate:
     - a big lift bridge where the road crosses the river
     - the Snowfields as a flat snow basin ringed by brown cliffs, entered
       through a pass
     - a gravel road climbing to the Volcano, with red fog inside
     - the Gloam Hollow as a misty brown-grass swamp
   - Bigger, bolder shop signs.
   - Darker nights with fog.
3. **Later, gameplay:** a toll on the bridge, a ferry to the island, gates
   you open (V2_PLAN M5 "gates").

Sources: search extracts of the Lumber Tycoon 2 fandom wiki (Main Biome,
Safari, Taiga, Swamp, Volcano, Bridge, Ferry, Lumberland, Koa, Palm, Frost,
Gold, Zombie, Volcano, Cherry, Oak, Birch, Spooky and Phantom Wood pages),
NamuWiki's Lumber Tycoon 2 pages, lumbertycoon2.site/map, and a Roblox
developer forum post on LT2-style tree generators.
