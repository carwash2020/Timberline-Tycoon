--!nocheck
-- V1 hardening (item 3): the low-memory phone profile. A 667 x 375 touch-only
-- phone (the test size) that picks or is given Lower quality runs the "low"
-- budget. These are the ceilings a phone must stay under: dressing parts,
-- meshes (the item copies in shop boxes, the stream-in trees), lights, shadows
-- and effects. Tuning a number up past one of these is a decision, not a drift:
-- change the number here in the same PR and say why.
return function(t)
	local QualityBudgets = t.shared("QualityBudgets")
	local QualityProfile = t.shared("QualityProfile")
	local PhoneHud = t.shared("PhoneHud")
	local GameConfig = t.shared("GameConfig")
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local PHONE = { width = 667, height = 375, touchOnly = true }

	local function phoneTier()
		-- The join screen recommends Lower to a touch-only device; Automatic
		-- graphics on one is "low" too. Either way: low.
		local recommended = QualityProfile.Recommended(PHONE.touchOnly, nil)
		local choice = QualityProfile.Resolve("unset", recommended)
		local device = QualityBudgets.TierFor(nil, PHONE.touchOnly)
		return QualityProfile.TierFor(choice, device), recommended, device
	end

	t.test("a 667 x 375 touch-only phone runs the low tier, however it got there", function()
		local tier, recommended, device = phoneTier()
		t.eq(recommended, "low")
		t.eq(device, "low")
		t.eq(tier, "low")
		t.eq(QualityBudgets.For(tier).Tier, "low")
		-- Roblox's own level 1 to 4 is low on any device; Lower is low on a PC too.
		for level = 1, 4 do
			t.eq(QualityBudgets.TierFor("QualityLevel" .. level, true), "low")
		end
		for _, deviceTier in ipairs({ "low", "medium", "high" }) do
			t.eq(QualityProfile.TierFor("low", deviceTier), "low", "Lower is low on a " .. deviceTier .. " device")
		end
		t.ok(PHONE.width / PHONE.height > 1.7 and PHONE.width == 667, "the test size is landscape 667 x 375")
	end)

	t.test("part budgets: the dressing a phone builds near the camera is capped", function()
		local low = QualityBudgets.For("low")
		t.ok(low.MaxDecor <= 148, "decor models: " .. low.MaxDecor)
		t.ok(low.MaxDecor + low.MaxCritters + 2 + 2 <= 160, "the AmbientLife folder holds 160 models or fewer")
		t.ok(low.MaxCritters <= 8, "critters")
		t.ok(low.SwayParts <= 400 and low.SwayTrees <= 16, "swaying canopy parts")
		t.ok(low.ChipCount <= 24, "wood chips in the air")
		t.ok(low.LeafPool <= 32, "falling leaves")
		t.ok(QualityBudgets.NatureParts("low") <= 148, "nature parts")
		t.ok(QualityBudgets.CritterPartCap("low") <= 120, "critter parts")
		t.ok(low.TuftNear <= 90, "grass tufts are drawn close only")
		-- The sum of what the client builds as dressing, against the high tier's.
		local function dressing(tier)
			local b = QualityBudgets.For(tier)
			return QualityBudgets.NatureParts(tier)
				+ QualityBudgets.CritterPartCap(tier)
				+ b.ChipCount
				+ b.LeafPool
				+ QualityBudgets.GlowLightCap(tier)
		end
		t.ok(dressing("low") <= 350, "a phone's dressing parts: " .. dressing("low"))
		t.ok(dressing("low") * 2 <= dressing("high"), "low is half of high or less")
	end)

	t.test("mesh budgets: no item copies in shop boxes, trees stream in a short ring, a 640 disc at most", function()
		local low = QualityBudgets.For("low")
		t.eq(low.BoxContents, false, "a flat window and the name strip instead of the item mesh")
		t.eq(low.LeafShadows, false, "no shadow from every leaf part")
		t.ok(low.TuftNear <= 90, "grass tufts only within " .. low.TuftNear)
		t.ok(low.TuftBuildMs <= 1.2, "building tuft cells costs a phone 1.2 ms a frame at most")
		t.ok(low.DecorLoadRadius <= 110 and low.DecorUnloadRadius <= 130, "decoration cells load close")
		t.ok(low.NpcAnimateRange <= 70, "townsfolk animate only near")
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local radius = project.tree.Workspace["$properties"].StreamingTargetRadius
		t.ok(low.TuftNear < radius, "the tufts stay inside the stream radius, or they would sit on streamed-out ground")
		t.ok(low.DecorLoadRadius < radius and low.DecorUnloadRadius < radius)
	end)

	t.test(
		"light budgets: no Lanternwood glow, two cave lights, shorter shop lights, no sun rays or far blur",
		function()
			local low = QualityBudgets.For("low")
			t.eq(QualityBudgets.GlowLightCap("low"), 0, "Lanternwood lights on screen")
			t.ok(QualityBudgets.CaveLightCap("low") <= 2, "lights in a cave")
			t.ok(low.LightScale <= 0.6, "shop lights reach 60% as far, with no shadows")
			t.eq(low.SunRays, 0)
			t.eq(low.DepthOfField, 0)
			t.ok(low.Bloom <= 0.5)
			t.ok(low.WeatherRate <= 0.5, "half the rain, snow and ash")
			t.eq(QualityBudgets.GlintRate("low"), 0, "no Lux glint particles")
			t.ok(QualityBudgets.RainLive("low") <= QualityBudgets.RainLive("high") / 2 + 1e-9, "live rain particles")
			t.ok(low.CosmeticHz <= 2, "cosmetic loops run twice a second at most")
		end
	)

	t.test("low is under medium is under high on every count, so no tier is a surprise", function()
		for _, field in ipairs({
			"MaxDecor",
			"MaxCritters",
			"SwayParts",
			"SwayTrees",
			"ChipCount",
			"LeafPool",
			"TuftNear",
		}) do
			local low, medium, high =
				QualityBudgets.For("low")[field], QualityBudgets.For("medium")[field], QualityBudgets.For("high")[field]
			t.ok(low <= medium and medium <= high, field)
		end
		for _, cap in ipairs({ "GlowLightCap", "CaveLightCap", "CritterPartCap", "NatureParts" }) do
			t.ok(QualityBudgets[cap]("low") <= QualityBudgets[cap]("medium"), cap)
			t.ok(QualityBudgets[cap]("medium") <= QualityBudgets[cap]("high"), cap)
		end
	end)

	t.test("the low profile never changes gameplay: the server's caps are the same on every device", function()
		-- The choice trims dressing only. The server's own caps (loose wood, loose parts,
		-- a plot's pieces) apply to a phone exactly as to a PC.
		t.eq(GameConfig.MaxWoodPiecesPerPlayer, 150)
		t.eq(GameConfig.MaxWoodPartsServer, 2500)
		t.eq(GameConfig.MaxLooseMaterialsServer, 400)
		local source = fs.readFile("src/ServerScriptService/WoodService.luau")
		t.eq(string.find(source, "QualityBudgets", 1, true), nil, "WoodService never reads a quality tier")
		local build = fs.readFile("src/ServerScriptService/BuildMaterials.luau")
		t.eq(string.find(build, "QualityBudgets", 1, true), nil, "BuildMaterials never reads a quality tier")
	end)

	t.test("phone taps: the HUD icon buttons are at least 44 px on a 667 x 375 screen", function()
		t.ok(PhoneHud.Size >= 44, "an icon button's face is " .. PhoneHud.Size)
		t.ok(3 * PhoneHud.Size + 2 * PhoneHud.Gap < PHONE.height / 2, "the three-button column leaves room in 375 px")
	end)
end
