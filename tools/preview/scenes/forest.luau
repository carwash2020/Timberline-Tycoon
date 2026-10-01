--!nocheck
-- The Living Forest (GAME_DESIGN §16): a tree wearing each bark clue, a
-- planted tree with its name stake, an Elder in its aura, a storm-struck
-- tree, Heartseeds sprouting on a birch, a pine and a small oak's stump,
-- and a figured log of each figure.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local ForestArt = ctx.art("ForestArt")
		local ForestData = ctx.shared("ForestData")
		local ForestLogic = ctx.shared("ForestLogic")
		local TreeLogic = ctx.shared("TreeLogic")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 260, C3.fromRGB(110, 160, 80), V3.new(40, -0.5, 30))

		local function label(text, at)
			local sign = Kit.part(
				root,
				"Label",
				V3.new(9, 2, 0.3),
				CF.new(at),
				C3.fromRGB(120, 80, 50),
				roblox.Enum.Material.Wood
			)
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { roblox.Enum.NormalId.Front })
		end

		local function tree(woodId, seed, at, scale)
			local def = WoodData.Get(woodId)
			local model = TreeArt.Build(def, seed, scale or 1)
			Kit.placeAt(model, CF.new(at) * CF.Angles(0, 0.4, 0))
			model.Parent = root
			return model, def
		end

		-- Row 1: one tree per clue (oak shows them best; birch and pine for
		-- the pale and the hidden trunks).
		local clues = {
			{ "curly", "oak" },
			{ "birdseye", "oak" },
			{ "quilted", "oak" },
			{ "burl", "oak" },
			{ "starfall", "lumenwood" },
			{ "stormgrain", "pine" },
			{ "birdseye", "birch" },
			{ "quilted", "pine" },
		}
		for i, pair in ipairs(clues) do
			local x = (i - 1) * 22
			local model, def = tree(pair[2], 10 + i, V3.new(x, 0, 0))
			ForestArt.BarkClue(model, model.PrimaryPart, def, pair[1], i)
			local f = ForestLogic.Figure(pair[1])
			label(
				string.format("%s %s x%s", f.displayName, def.displayName, tostring(f.multiplier)),
				V3.new(x, 1.5, -10)
			)
		end

		-- Row 2: planted, Elder, storm-struck, sprouting.
		local planted, oak = tree("oak", 77, V3.new(0, 0, 50))
		local stake = ForestArt.NameStake("Connor", 3)
		local trunk = planted.PrimaryPart
		Kit.placeAt(stake, CF.new(trunk.Size.Y / 2 + 1.4, 0, 50 - 1.2) * CF.Angles(0, math.rad(20), 0))
		stake.Parent = root
		label("Planted by Connor", V3.new(0, 1.5, 38))

		local maple = WoodData.Get("maple")
		local elderSize = ForestLogic.ElderSize(maple)
		local elder = tree("maple", 91, V3.new(48, 0, 58), elderSize.scale)
		ForestArt.BarkClue(elder, elder.PrimaryPart, maple, "burl", 9)
		local aura = ForestArt.ElderAura(elder.PrimaryPart.Size.Y * 1.6 + 2)
		Kit.placeAt(aura, CF.new(48, 0, 58))
		aura.Parent = root
		label("Elder Maple (1.7x, burl)", V3.new(48, 1.5, 40))

		local struck, pine = tree("pine", 55, V3.new(92, 0, 50))
		ForestArt.StormGlow(struck, struck.PrimaryPart, pine, 4)
		label("Storm-struck pine", V3.new(92, 1.5, 38))

		-- Sprouts at full size on a birch, a pine and a small oak's stump
		-- (the smallest cuts): the mound and halo stay on the stump.
		local function sprouting(woodId, seed, scale, x, z)
			local def = WoodData.Get(woodId)
			local stump = TreeArt.Stump(def, seed, scale)
			Kit.placeAt(stump, CF.new(x, 0, z))
			stump.Parent = root
			local part = stump.PrimaryPart
			local sprout = ForestArt.Sprout(def, seed, part.Size.Y)
			Kit.placeAt(sprout, CF.new(x, part.Size.X, z))
			sprout.Parent = root
		end
		sprouting("birch", 5, 1, 122, 50)
		sprouting("pine", 6, 1, 117, 51)
		sprouting("oak", 7, TreeLogic.Sizes[1].scale, 112, 52)
		local orb = ForestArt.SeedOrb()
		orb.CFrame = CF.new(126, 4, 47)
		orb.Parent = root
		label("Heartseed sprouting", V3.new(122, 1.5, 40))

		-- Row 3: a figured log of each figure, then a plain one.
		for i, f in ipairs(ForestData.Figures) do
			local wood = if f.id == "starfall" then WoodData.Get("lumenwood") else oak
			local log = TreeArt.Log(wood, 3, 1.2)
			log:PivotTo(CF.new(-6 + i * 6, 0.6, -26) * CF.Angles(0, 0.25, 0))
			log.Parent = root
			ForestArt.FigureBand(log.PrimaryPart, f.id)
		end
		local plain = TreeArt.Log(oak, 3, 1.2)
		plain:PivotTo(CF.new(-6 + (#ForestData.Figures + 1) * 6, 0.6, -26) * CF.Angles(0, 0.25, 0))
		plain.Parent = root
		label("Figured logs: curly, birdseye, quilted, stormgrain, burl, starfall, plain", V3.new(20, 1.5, -32))

		return {
			root = root,
			shadowRadius = 200,
			cameras = {
				{ pos = { 77, 30, -70 }, target = { 77, 6, 0 }, label = "every bark clue" },
				{ pos = { 4, 7, -22 }, target = { 20, 4, 0 }, label = "curly + birdseye" },
				{ pos = { 48, 7, -22 }, target = { 60, 4, 0 }, label = "quilted + burl" },
				{ pos = { 96, 9, -24 }, target = { 115, 5, 0 }, label = "starfall + storm" },
				{ pos = { 128, 9, -22 }, target = { 150, 4, 0 }, label = "birch + pine" },
				{ pos = { -14, 6, 32 }, target = { 2, 3, 50 }, label = "planted + stake" },
				{ pos = { 48, 30, 0 }, target = { 48, 14, 58 }, label = "elder" },
				{ pos = { 106, 8, 30 }, target = { 115, 3, 50 }, label = "storm + sprout" },
				{ pos = { 20, 7, -40 }, target = { 20, 0.6, -26 }, label = "figured logs" },
			},
		}
	end,
}
