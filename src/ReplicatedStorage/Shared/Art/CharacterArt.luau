--!strict
-- CharacterArt: the townsfolk (GAME_DESIGN §13: "blocky lumberjack
-- archetypes; Murph = big beard, red flannel, beanie"). Chunky toy figures
-- about the size of a Roblox avatar, dressed from a Spec: skin, a shirt
-- (flannel checks optional), pants or overalls, boots, hair, beard, hat,
-- glasses, apron, vest, scarf, gloves, toolbelt, and something in the left
-- hand. The face is small parts (eyes with a shine, brows, nose, smile,
-- rosy cheeks), no decals. Pure (see Kit): the preview draws exactly what
-- NPCService spawns.
--
-- Contract (NPCService, NPCController, QuestUI):
--   * Build(spec) returns a Model around the origin: feet at y = 0, facing
--     -Z, about 5.3 studs tall (plus hat) at scale 1.
--   * PrimaryPart "HumanoidRootPart": invisible, anchored, centred on the
--     Torso (RootHeight above the feet). Every other part is unanchored,
--     massless and hangs off it by joints, so setting the root's CFrame
--     moves the whole figure (walkers), and Motor6D.Transform animates it
--     on a client without replicating.
--   * Direct children (BaseParts): HumanoidRootPart, Torso, Head, LeftArm,
--     RightArm, LeftLeg, RightLeg; "Beard" for any beard; the hat named for
--     its style (Beanie, Cap, HardHat, ConductorCap, Bandana, FlatCap).
--     Murph wears a big beard and a beanie, so QuestUI's portrait finds
--     Head, Beard, Beanie, Torso, LeftArm and RightArm, and its Talk prompt
--     goes on Torso.
--   * Details (face, hair, stripes, hands, boots, the held item) are
--     children of the part they move with and welded to it, so cloning the
--     Head clones the face too. Hat and beard sub-parts are children of the
--     hat / beard and welded to the Head.
--   * Motor6Ds named like a Roblox rig: RootJoint (in HumanoidRootPart:
--     root -> Torso, at the torso's centre) and Neck, LeftShoulder,
--     RightShoulder, LeftHip, RightHip (in Torso). Each joint's frame sits
--     at its pivot (base of the neck, top of each arm and leg), lined up
--     with the model's axes, so with Motor6D.Transform:
--       CFrame.Angles(a, 0, 0), a > 0   swings a limb forward / tips the
--                                        head back (looks up)
--       CFrame.Angles(0, y, 0), y > 0   turns the head to its left (-X)
--       CFrame.Angles(0, 0, z), z > 0   raises the RIGHT arm out sideways
--                                        (z < 0 for the left arm)
--   * Head children named "Eye" (each with an "EyeShine" child) for
--     blinking. The held item's parts are children of LeftArm.
--   * Head has a BillboardGui "NameTag" (name, then role), MaxDistance 60.
--   * Model attributes: Scale, RootHeight (feet to root centre), Height
--     (feet to the top of the hat), TopOffset (head centre to hat top).

local Kit = require(script.Parent.Kit)

local CharacterArt = {}

export type HairStyle = "short" | "bun" | "long" | "curly" | "ponytail" | "bald" | "none"
export type BeardStyle = "big" | "stubble" | "mustache" | "handlebar" | "goatee" | "none"
export type HatStyle = "beanie" | "cap" | "capBack" | "hardhat" | "conductor" | "bandana" | "flatcap" | "none"
export type Carry = "mug" | "clipboard" | "wrench" | "basket" | "cane" | "scroll" | "lantern" | "sapling" | "none"

export type Spec = {
	name: string,
	role: string?,
	seed: number?,
	scale: number?, -- 1 = a Roblox avatar; a kid is about 0.8
	stout: boolean?, -- a wider, deeper torso
	skin: Color3,
	shirt: Color3,
	stripe: Color3?, -- flannel: checks in this colour
	undershirt: Color3?, -- the tee at the collar
	pants: Color3,
	cuffs: boolean?, -- rolled jeans cuffs over the boots
	boots: Color3?,
	hair: Color3?,
	hairStyle: HairStyle?,
	brows: Color3?, -- defaults to the hair (or beard) colour
	beard: BeardStyle?,
	beardColor: Color3?,
	hat: HatStyle?,
	hatColor: Color3?,
	hatTrim: Color3?, -- cuff, band or dots
	glasses: Color3?, -- frame colour
	apron: Color3?,
	overalls: Color3?,
	suspenders: Color3?,
	vest: Color3?,
	scarf: Color3?,
	gloves: Color3?,
	toolbelt: boolean?,
	rolledSleeves: boolean?,
	kneePatch: Color3?,
	carry: Carry?,
	accent: Color3?, -- the held item's main colour, where it has one
	tag: boolean?, -- false: no name tag
}

-- Body proportions at scale 1 (studs).
local LEG_W, LEG_H, LEG_D = 0.96, 2.0, 1.0
local ARM_W, ARM_H, ARM_D = 0.92, 2.0, 0.96
local HEAD_W, HEAD_H, HEAD_D = 1.36, 1.25, 1.2
local TORSO_H = 2.0
local ROOT_Y = LEG_H + TORSO_H / 2 -- 3: the torso's centre

local INK = Color3.fromRGB(43, 29, 22) -- eyes
local MOUTH = Color3.fromRGB(110, 48, 38)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLUSH = Color3.fromRGB(240, 128, 112)
local LEATHER = Color3.fromRGB(70, 44, 26)
local BRASS = Color3.fromRGB(214, 168, 72)
local IRON = Color3.fromRGB(70, 70, 76)
local TEE = Color3.fromRGB(238, 228, 210)
local DEFAULT_HAIR = Color3.fromRGB(96, 62, 36)
local DEFAULT_BOOTS = Color3.fromRGB(104, 66, 38)

local FABRIC = Enum.Material.Fabric
local SMOOTH = Enum.Material.SmoothPlastic

type Ctx = {
	model: Model,
	spec: Spec,
	rng: Kit.Rng,
	welds: { { part: BasePart, to: BasePart } },
	top: number, -- highest point above the head's centre (unscaled)
}

type Shape = "block" | "ball" | "cylinder" | "wedge"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- A detail on `limb`: `offset` is in the limb's own frame (its centre;
-- front -Z). Parented under `parent` (the limb unless given) and welded to
-- the limb once the figure is finished. Small parts cast no shadow.
local function bit(
	ctx: Ctx,
	limb: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance?,
	shape: Shape?
): BasePart
	local cf = limb.CFrame * offset
	local into = parent or limb
	local mat = material or SMOOTH
	local p: BasePart
	if shape == "ball" then
		p = Kit.ball(into, name, size.X, cf, color, mat)
	elseif shape == "cylinder" then
		p = Kit.cylinder(into, name, size.X, size.Y, cf, color, mat)
	elseif shape == "wedge" then
		p = Kit.wedge(into, name, size, cf, color, mat)
	else
		p = Kit.part(into, name, size, cf, color, mat)
	end
	Kit.decor(p, if size.X * size.Y * size.Z < 0.4 then false else nil)
	table.insert(ctx.welds, { part = p, to = limb })
	return p
end

-- A core body part (a direct child of the model).
local function limbPart(
	ctx: Ctx,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.part(ctx.model, name, size, cf, color, material or SMOOTH)
	Kit.decor(p)
	return p
end

local function sides(): { number }
	return { -1, 1 }
end

---------------------------------------------------------------------------
-- The head: face, hair, beard, hat, glasses
---------------------------------------------------------------------------

local function face(ctx: Ctx, head: BasePart)
	local spec = ctx.spec
	local fz = -HEAD_D / 2
	local bigBeard = spec.beard == "big"
	local eyeZ = if spec.glasses then fz - 0.075 else fz - 0.02
	local browColor = spec.brows or spec.hair or spec.beardColor or DEFAULT_HAIR
	for _, side in ipairs(sides()) do
		local eye = bit(ctx, head, "Eye", Vector3.new(0.15, 0.26, 0.05), CFrame.new(side * 0.29, 0.06, eyeZ), INK)
		bit(
			ctx,
			head,
			"EyeShine",
			Vector3.new(0.06, 0.07, 0.02),
			CFrame.new(side * 0.29 + 0.035, 0.12, eyeZ - 0.03),
			WHITE,
			nil,
			eye
		)
		-- Brows: chunky, the outer end a touch lower (a kind face).
		bit(
			ctx,
			head,
			"Brow",
			Vector3.new(0.36, if bigBeard then 0.13 else 0.085, 0.06),
			CFrame.new(side * 0.3, if bigBeard then 0.33 else 0.32, fz - 0.025) * CFrame.Angles(0, 0, side * -0.13),
			browColor,
			if bigBeard then FABRIC else nil
		)
		bit(
			ctx,
			head,
			"Cheek",
			Vector3.new(0.2, 0.11, 0.03),
			CFrame.new(side * 0.45, if bigBeard then -0.04 else -0.17, fz - 0.012),
			spec.skin:Lerp(BLUSH, 0.55)
		)
		bit(
			ctx,
			head,
			"Ear",
			Vector3.new(0.12, 0.32, 0.26),
			CFrame.new(side * (HEAD_W / 2 + 0.05), -0.03, 0.05),
			Kit.shade(spec.skin, -0.05)
		)
	end
	bit(ctx, head, "Nose", Vector3.new(0.2, 0.22, 0.15), CFrame.new(0, -0.1, fz - 0.065), Kit.shade(spec.skin, -0.07))
	-- The smile: a bar with its corners turned up. On a big beard it sits on
	-- the beard, under the moustache.
	local mouthY = if bigBeard then -0.45 else -0.33
	local mouthZ = if bigBeard then fz - 0.11 else fz - 0.02
	bit(ctx, head, "Mouth", Vector3.new(0.26, 0.065, 0.04), CFrame.new(0, mouthY, mouthZ), MOUTH)
	for _, side in ipairs(sides()) do
		bit(
			ctx,
			head,
			"Mouth",
			Vector3.new(0.1, 0.065, 0.04),
			CFrame.new(side * 0.16, mouthY + 0.03, mouthZ) * CFrame.Angles(0, 0, side * 0.6),
			MOUTH
		)
	end
end

local function glasses(ctx: Ctx, head: BasePart, frame: Color3)
	local fz = -HEAD_D / 2
	for _, side in ipairs(sides()) do
		bit(ctx, head, "GlassesFrame", Vector3.new(0.44, 0.4, 0.03), CFrame.new(side * 0.29, 0.06, fz - 0.03), frame)
		bit(
			ctx,
			head,
			"GlassesLens",
			Vector3.new(0.34, 0.3, 0.03),
			CFrame.new(side * 0.29, 0.06, fz - 0.045),
			Color3.fromRGB(222, 238, 244),
			Enum.Material.Glass
		)
		bit(
			ctx,
			head,
			"GlassesArm",
			Vector3.new(0.04, 0.05, HEAD_D * 0.6),
			CFrame.new(side * (HEAD_W / 2 + 0.03), 0.16, fz + HEAD_D * 0.3),
			frame
		)
	end
	bit(ctx, head, "GlassesBridge", Vector3.new(0.16, 0.05, 0.03), CFrame.new(0, 0.13, fz - 0.03), frame)
end

local function hair(ctx: Ctx, head: BasePart, hatted: boolean)
	local spec = ctx.spec
	local style: HairStyle = spec.hairStyle or "short"
	if style == "none" then
		return
	end
	local c = spec.hair or DEFAULT_HAIR
	local hh, hd = HEAD_H, HEAD_D
	if style == "bald" then
		for _, side in ipairs(sides()) do
			bit(ctx, head, "Hair", Vector3.new(0.14, 0.32, 0.6), CFrame.new(side * (HEAD_W / 2 + 0.04), 0.08, 0.2), c)
		end
		bit(ctx, head, "Hair", Vector3.new(HEAD_W + 0.08, 0.3, 0.14), CFrame.new(0, 0.05, hd / 2 + 0.04), c)
		ctx.top = math.max(ctx.top, hh / 2)
		return
	end
	-- Back and sides: they show under any hat.
	local long = style == "long"
	local backH = if long then hh * 0.72 + 0.75 else hh * 0.72
	bit(
		ctx,
		head,
		"Hair",
		Vector3.new(HEAD_W + 0.1, backH, 0.18),
		CFrame.new(0, hh * 0.14 + hh * 0.36 - backH / 2, hd / 2 + 0.05),
		c
	)
	for _, side in ipairs(sides()) do
		bit(
			ctx,
			head,
			"Hair",
			Vector3.new(0.13, if long then hh * 0.8 else hh * 0.42, hd * 0.62),
			CFrame.new(side * (HEAD_W / 2 + 0.045), if long then hh * 0.1 else hh * 0.27, hd * 0.17),
			c
		)
	end
	if not hatted then
		if style == "curly" then
			-- A mop of tilted cubes.
			for i = 1, 7 do
				local a = (i - 1) / 7 * math.pi * 2
				local r = if i == 1 then 0 else 0.38
				local s = ctx.rng:range(0.5, 0.62)
				bit(
					ctx,
					head,
					"Hair",
					Vector3.new(s, s * 0.8, s),
					CFrame.new(math.cos(a) * r, hh / 2 + 0.1 + ctx.rng:range(-0.04, 0.06), math.sin(a) * r * 0.9 + 0.04)
						* CFrame.Angles(ctx.rng:range(-0.4, 0.4), ctx.rng:range(0, 3), ctx.rng:range(-0.4, 0.4)),
					Kit.vary(c, ctx.rng, 0.04)
				)
			end
			ctx.top = math.max(ctx.top, hh / 2 + 0.45)
		else
			bit(ctx, head, "Hair", Vector3.new(HEAD_W + 0.1, 0.26, hd + 0.1), CFrame.new(0, hh / 2 + 0.08, 0.02), c)
			-- A chunky fringe.
			for i, x in ipairs({ -0.42, 0.02, 0.44 }) do
				bit(
					ctx,
					head,
					"Hair",
					Vector3.new(0.5, 0.22, 0.16),
					CFrame.new(x, hh / 2 - 0.06 - (if i == 2 then 0.04 else 0), -hd / 2 - 0.02)
						* CFrame.Angles(0, 0, (i - 2) * -0.18),
					c
				)
			end
			ctx.top = math.max(ctx.top, hh / 2 + 0.21)
		end
	end
	if style == "bun" then
		local y = if hatted then hh * 0.25 else hh / 2 + 0.3
		local z = if hatted then hd / 2 + 0.28 else hd * 0.2
		bit(ctx, head, "HairBun", Vector3.one * 0.6, CFrame.new(0, y, z), c, nil, nil, "ball")
		ctx.top = math.max(ctx.top, y + 0.3)
	elseif style == "ponytail" then
		bit(
			ctx,
			head,
			"Hair",
			Vector3.new(0.34, 0.95, 0.32),
			CFrame.new(0, -0.15, hd / 2 + 0.27) * CFrame.Angles(0.25, 0, 0),
			c
		)
		bit(
			ctx,
			head,
			"HairTie",
			Vector3.new(0.4, 0.12, 0.38),
			CFrame.new(0, 0.28, hd / 2 + 0.17),
			spec.hatTrim or Color3.fromRGB(216, 72, 72)
		)
	end
end

local function beard(ctx: Ctx, head: BasePart)
	local spec = ctx.spec
	local style: BeardStyle = spec.beard or "none"
	if style == "none" then
		return
	end
	local c = spec.beardColor or spec.hair or DEFAULT_HAIR
	local fz = -HEAD_D / 2
	local hh = HEAD_H
	if style == "big" then
		-- Murph's: a bushy block over the jaw that steps down onto the
		-- chest, sideburns, and a big moustache with drooping ends.
		local main = bit(
			ctx,
			head,
			"Beard",
			Vector3.new(HEAD_W * 0.98, 0.8, 0.5),
			CFrame.new(0, -hh / 2 + 0.11, fz + 0.16),
			c,
			FABRIC,
			ctx.model
		)
		local light = Kit.shade(c, 0.3)
		local dark = Kit.shade(c, -0.08)
		bit(
			ctx,
			head,
			"BeardStep",
			Vector3.new(HEAD_W * 0.8, 0.42, 0.46),
			CFrame.new(0, -hh / 2 - 0.42, fz + 0.1) * CFrame.Angles(0.12, 0, 0),
			dark,
			FABRIC,
			main
		)
		bit(
			ctx,
			head,
			"BeardStep",
			Vector3.new(HEAD_W * 0.5, 0.3, 0.4),
			CFrame.new(0, -hh / 2 - 0.72, fz + 0.06) * CFrame.Angles(0.2, 0, 0),
			c,
			FABRIC,
			main
		)
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				head,
				"Sideburn",
				Vector3.new(0.17, 0.66, HEAD_D * 0.55),
				CFrame.new(side * (HEAD_W / 2 + 0.035), -0.13, -0.12),
				c,
				FABRIC,
				main
			)
			-- The moustache's drooping ends.
			bit(
				ctx,
				head,
				"Moustache",
				Vector3.new(0.26, 0.4, 0.2),
				CFrame.new(side * 0.42, -0.36, fz - 0.15) * CFrame.Angles(0, 0, side * 0.22),
				light,
				FABRIC,
				main
			)
		end
		bit(ctx, head, "Moustache", Vector3.new(0.72, 0.24, 0.22), CFrame.new(0, -0.24, fz - 0.15), light, FABRIC, main)
	elseif style == "stubble" then
		local shadow = ctx.spec.skin:Lerp(c, 0.4)
		local main = bit(
			ctx,
			head,
			"Beard",
			Vector3.new(HEAD_W * 0.94, 0.4, 0.03),
			CFrame.new(0, -hh / 2 + 0.2, fz - 0.01),
			shadow,
			nil,
			ctx.model
		)
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				head,
				"Stubble",
				Vector3.new(0.03, 0.5, HEAD_D * 0.5),
				CFrame.new(side * (HEAD_W / 2 + 0.01), -hh / 2 + 0.25, -0.2),
				shadow,
				nil,
				main
			)
		end
	elseif style == "mustache" or style == "handlebar" then
		local main =
			bit(ctx, head, "Beard", Vector3.new(0.72, 0.2, 0.18), CFrame.new(0, -0.24, fz - 0.1), c, FABRIC, ctx.model)
		for _, side in ipairs(sides()) do
			local turn = if style == "handlebar" then 0.55 else -0.35
			bit(
				ctx,
				head,
				"Moustache",
				Vector3.new(0.34, 0.15, 0.16),
				CFrame.new(side * 0.44, if style == "handlebar" then -0.17 else -0.3, fz - 0.09)
					* CFrame.Angles(0, 0, side * turn),
				c,
				FABRIC,
				main
			)
		end
	elseif style == "goatee" then
		bit(
			ctx,
			head,
			"Beard",
			Vector3.new(0.42, 0.42, 0.24),
			CFrame.new(0, -hh / 2 - 0.05, fz + 0.02),
			c,
			FABRIC,
			ctx.model
		)
	end
end

-- The hat; returns nothing but raises ctx.top.
local function hat(ctx: Ctx, head: BasePart)
	local spec = ctx.spec
	local style: HatStyle = spec.hat or "none"
	if style == "none" then
		return
	end
	local c = spec.hatColor or Color3.fromRGB(176, 60, 48)
	local trim = spec.hatTrim or Kit.shade(c, -0.22)
	local hh, hw, hd = HEAD_H, HEAD_W, HEAD_D
	local top = hh / 2
	if style == "beanie" then
		local b = bit(
			ctx,
			head,
			"Beanie",
			Vector3.new(hw + 0.16, 0.52, hd + 0.16),
			CFrame.new(0, top + 0.13, 0),
			c,
			FABRIC,
			ctx.model
		)
		bit(ctx, head, "BeanieTop", Vector3.new(hw * 0.78, 0.2, hd * 0.78), CFrame.new(0, top + 0.47, 0), c, FABRIC, b)
		bit(
			ctx,
			head,
			"BeanieCuff",
			Vector3.new(hw + 0.27, 0.27, hd + 0.27),
			CFrame.new(0, top - 0.07, 0),
			trim,
			FABRIC,
			b
		)
		-- Knit ribs on the cuff's front.
		for i = -2, 2 do
			bit(
				ctx,
				head,
				"BeanieRib",
				Vector3.new(0.07, 0.27, 0.03),
				CFrame.new(i * 0.27, top - 0.07, -(hd + 0.27) / 2 - 0.01),
				Kit.shade(trim, -0.12),
				FABRIC,
				b
			)
		end
		bit(
			ctx,
			head,
			"Pompom",
			Vector3.one * 0.46,
			CFrame.new(0, top + 0.7, 0),
			Color3.fromRGB(240, 230, 210),
			FABRIC,
			b,
			"ball"
		)
		ctx.top = math.max(ctx.top, top + 0.93)
	elseif style == "cap" or style == "capBack" then
		local dir = if style == "cap" then -1 else 1
		local cap = bit(
			ctx,
			head,
			"Cap",
			Vector3.new(hw + 0.1, 0.38, hd + 0.1),
			CFrame.new(0, top + 0.1, 0),
			c,
			FABRIC,
			ctx.model
		)
		bit(
			ctx,
			head,
			"CapBrim",
			Vector3.new(hw * 0.86, 0.08, 0.62),
			CFrame.new(0, top - 0.05, dir * (hd / 2 + 0.27)) * CFrame.Angles(dir * 0.1, 0, 0),
			trim,
			FABRIC,
			cap
		)
		bit(ctx, head, "CapButton", Vector3.new(0.18, 0.08, 0.18), CFrame.new(0, top + 0.32, 0), trim, FABRIC, cap)
		bit(
			ctx,
			head,
			"CapPatch",
			Vector3.new(0.46, 0.24, 0.03),
			CFrame.new(0, top + 0.12, dir * ((hd + 0.1) / 2 + 0.01)),
			Color3.fromRGB(240, 230, 210),
			nil,
			cap
		)
		ctx.top = math.max(ctx.top, top + 0.36)
	elseif style == "hardhat" then
		local hard = Kit.ellipsoid(
			ctx.model,
			"HardHat",
			Vector3.new(hw + 0.34, 0.95, hd + 0.34),
			head.CFrame * CFrame.new(0, top + 0.02, 0),
			c,
			SMOOTH
		)
		Kit.decor(hard)
		table.insert(ctx.welds, { part = hard :: BasePart, to = head })
		bit(
			ctx,
			head,
			"HardHatBrim",
			Vector3.new(0.08, hw + 0.72, hw + 0.72),
			CFrame.new(0, top - 0.14, -0.06) * CFrame.Angles(0, 0, math.pi / 2),
			c,
			SMOOTH,
			hard,
			"cylinder"
		)
		bit(
			ctx,
			head,
			"HardHatRidge",
			Vector3.new(0.22, 0.14, hd + 0.2),
			CFrame.new(0, top + 0.43, 0),
			trim,
			SMOOTH,
			hard
		)
		ctx.top = math.max(ctx.top, top + 0.52)
	elseif style == "conductor" then
		local cap = bit(
			ctx,
			head,
			"ConductorCap",
			Vector3.new(hw + 0.14, 0.46, hd + 0.14),
			CFrame.new(0, top + 0.13, 0),
			c,
			FABRIC,
			ctx.model
		)
		bit(
			ctx,
			head,
			"CapCrown",
			Vector3.new(hw + 0.26, 0.12, hd + 0.26),
			CFrame.new(0, top + 0.38, 0),
			c,
			FABRIC,
			cap
		)
		bit(
			ctx,
			head,
			"CapBand",
			Vector3.new(hw + 0.18, 0.13, hd + 0.18),
			CFrame.new(0, top - 0.02, 0),
			trim,
			Enum.Material.Metal,
			cap
		)
		bit(
			ctx,
			head,
			"CapVisor",
			Vector3.new(hw * 0.84, 0.07, 0.44),
			CFrame.new(0, top - 0.1, -hd / 2 - 0.2) * CFrame.Angles(-0.12, 0, 0),
			Color3.fromRGB(30, 30, 34),
			SMOOTH,
			cap
		)
		bit(
			ctx,
			head,
			"CapBadge",
			Vector3.new(0.24, 0.18, 0.03),
			CFrame.new(0, top + 0.2, -(hd + 0.14) / 2 - 0.01),
			trim,
			Enum.Material.Metal,
			cap
		)
		ctx.top = math.max(ctx.top, top + 0.44)
	elseif style == "bandana" then
		local b = bit(
			ctx,
			head,
			"Bandana",
			Vector3.new(hw + 0.1, 0.36, hd + 0.1),
			CFrame.new(0, top + 0.04, 0),
			c,
			FABRIC,
			ctx.model
		)
		bit(
			ctx,
			head,
			"BandanaKnot",
			Vector3.new(0.32, 0.26, 0.22),
			CFrame.new(0, top - 0.04, hd / 2 + 0.14),
			c,
			FABRIC,
			b
		)
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				head,
				"BandanaTail",
				Vector3.new(0.2, 0.44, 0.06),
				CFrame.new(side * 0.12, top - 0.3, hd / 2 + 0.2) * CFrame.Angles(0.2, 0, side * 0.3),
				c,
				FABRIC,
				b
			)
		end
		-- Polka dots.
		for i, x in ipairs({ -0.42, 0, 0.42 }) do
			bit(
				ctx,
				head,
				"BandanaDot",
				Vector3.new(0.12, 0.12, 0.03),
				CFrame.new(x, top + 0.04 + (if i == 2 then 0.06 else -0.04), -(hd + 0.1) / 2 - 0.01),
				trim,
				nil,
				b
			)
		end
		ctx.top = math.max(ctx.top, top + 0.22)
	elseif style == "flatcap" then
		local cap = bit(
			ctx,
			head,
			"FlatCap",
			Vector3.new(hw + 0.18, 0.26, hd + 0.22),
			CFrame.new(0, top + 0.06, 0.02) * CFrame.Angles(-0.08, 0, 0),
			c,
			FABRIC,
			ctx.model
		)
		bit(
			ctx,
			head,
			"FlatCapBrim",
			Vector3.new(hw * 0.8, 0.07, 0.36),
			CFrame.new(0, top - 0.05, -hd / 2 - 0.2) * CFrame.Angles(-0.12, 0, 0),
			trim,
			FABRIC,
			cap
		)
		bit(
			ctx,
			head,
			"FlatCapButton",
			Vector3.new(0.14, 0.06, 0.14),
			CFrame.new(0, top + 0.21, -0.1),
			trim,
			FABRIC,
			cap
		)
		ctx.top = math.max(ctx.top, top + 0.24)
	end
end

---------------------------------------------------------------------------
-- The body: shirt, overalls, apron, vest, scarf, belts
---------------------------------------------------------------------------

local function torsoDetails(ctx: Ctx, torso: BasePart, tw: number, td: number)
	local spec = ctx.spec
	local th = TORSO_H
	local fz, bz = -td / 2, td / 2
	local covered = spec.overalls ~= nil or spec.apron ~= nil or spec.vest ~= nil

	-- Flannel checks: two bands each way, front and back, one down each side.
	local plaid = spec.stripe
	if plaid then
		for _, back in ipairs({ false, true }) do
			local zs = if back then 1 else -1
			local skipFront = not back and (spec.vest ~= nil)
			if not skipFront then
				for _, side in ipairs(sides()) do
					bit(
						ctx,
						torso,
						"Stripe",
						Vector3.new(0.24, th, 0.03),
						CFrame.new(side * tw * 0.24, 0, zs * (td / 2 + 0.015)),
						plaid,
						FABRIC
					)
				end
				for _, y in ipairs({ th * 0.17, -th * 0.23 }) do
					bit(
						ctx,
						torso,
						"Stripe",
						Vector3.new(tw, 0.2, 0.05),
						CFrame.new(0, y, zs * (td / 2 + 0.025)),
						Kit.shade(plaid, 0.06),
						FABRIC
					)
				end
			end
		end
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				torso,
				"Stripe",
				Vector3.new(0.03, th, 0.24),
				CFrame.new(side * (tw / 2 + 0.015), 0, 0),
				plaid,
				FABRIC
			)
		end
	end

	-- Collar and the tee under it.
	local collar = Kit.shade(spec.shirt, -0.14)
	for _, side in ipairs(sides()) do
		bit(
			ctx,
			torso,
			"Collar",
			Vector3.new(0.5, 0.14, 0.42),
			CFrame.new(side * 0.33, th / 2 - 0.03, fz + 0.17) * CFrame.Angles(0, 0, side * -0.3),
			collar,
			FABRIC
		)
	end
	if spec.undershirt or plaid then
		bit(
			ctx,
			torso,
			"Undershirt",
			Vector3.new(0.42, 0.34, 0.03),
			CFrame.new(0, th / 2 - 0.17, fz - 0.016),
			spec.undershirt or TEE,
			FABRIC
		)
	end
	if not covered then
		-- Button placket.
		bit(
			ctx,
			torso,
			"Placket",
			Vector3.new(0.16, th * 0.72, 0.03),
			CFrame.new(0, -th * 0.12, fz - 0.03),
			Kit.shade(spec.shirt, -0.08),
			FABRIC
		)
		for i = 0, 2 do
			bit(
				ctx,
				torso,
				"Button",
				Vector3.new(0.1, 0.1, 0.03),
				CFrame.new(0, th * 0.18 - i * 0.42, fz - 0.055),
				Color3.fromRGB(236, 224, 200)
			)
		end
	end

	-- Overalls: bib, waist, straps, brass buttons, a pocket with a pencil.
	local ov = spec.overalls
	if ov then
		bit(
			ctx,
			torso,
			"Overalls",
			Vector3.new(tw * 0.62, th * 0.58, 0.05),
			CFrame.new(0, -th * 0.12, fz - 0.035),
			ov,
			FABRIC
		)
		bit(
			ctx,
			torso,
			"Overalls",
			Vector3.new(tw + 0.04, th * 0.3, td + 0.04),
			CFrame.new(0, -th / 2 + th * 0.15, 0),
			ov,
			FABRIC
		)
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				torso,
				"OverallStrap",
				Vector3.new(0.22, th * 0.33, 0.05),
				CFrame.new(side * tw * 0.25, th * 0.34, fz - 0.035),
				ov,
				FABRIC
			)
			bit(
				ctx,
				torso,
				"OverallStrap",
				Vector3.new(0.22, 0.05, td + 0.1),
				CFrame.new(side * tw * 0.25, th / 2 + 0.02, 0),
				ov,
				FABRIC
			)
			bit(
				ctx,
				torso,
				"OverallStrap",
				Vector3.new(0.22, th * 0.8, 0.05),
				CFrame.new(side * tw * 0.12, th * 0.05, bz + 0.035) * CFrame.Angles(0, 0, side * 0.32),
				ov,
				FABRIC
			)
			bit(
				ctx,
				torso,
				"OverallButton",
				Vector3.new(0.14, 0.14, 0.04),
				CFrame.new(side * tw * 0.25, th * 0.17, fz - 0.07),
				BRASS,
				Enum.Material.Metal
			)
		end
		bit(
			ctx,
			torso,
			"Pocket",
			Vector3.new(0.6, 0.38, 0.03),
			CFrame.new(0, -th * 0.04, fz - 0.07),
			Kit.shade(ov, -0.1),
			FABRIC
		)
		bit(
			ctx,
			torso,
			"Pencil",
			Vector3.new(0.07, 0.36, 0.07),
			CFrame.new(0.15, th * 0.1, fz - 0.08) * CFrame.Angles(0, 0, -0.15),
			Color3.fromRGB(242, 196, 62)
		)
	end

	-- Suspenders.
	local sus = spec.suspenders
	if sus then
		for _, side in ipairs(sides()) do
			for _, zs in ipairs({ -1, 1 }) do
				bit(
					ctx,
					torso,
					"Suspender",
					Vector3.new(0.18, th - 0.22, 0.04),
					CFrame.new(side * tw * 0.27, 0.11, zs * (td / 2 + 0.06)),
					sus,
					Enum.Material.Leather
				)
			end
			bit(
				ctx,
				torso,
				"Suspender",
				Vector3.new(0.18, 0.04, td + 0.14),
				CFrame.new(side * tw * 0.27, th / 2 + 0.02, 0),
				sus,
				Enum.Material.Leather
			)
			bit(
				ctx,
				torso,
				"SuspenderClip",
				Vector3.new(0.22, 0.14, 0.04),
				CFrame.new(side * tw * 0.27, -th / 2 + 0.32, fz - 0.09),
				BRASS,
				Enum.Material.Metal
			)
		end
	end

	-- Vest: two front panels with a gap, a back, a watch chain.
	local vest = spec.vest
	if vest then
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				torso,
				"Vest",
				Vector3.new(tw * 0.4, th * 0.97, 0.05),
				CFrame.new(side * tw * 0.29, -0.01, fz - 0.03),
				vest,
				FABRIC
			)
			bit(
				ctx,
				torso,
				"Vest",
				Vector3.new(0.05, th * 0.97, td),
				CFrame.new(side * (tw / 2 + 0.03), -0.01, 0),
				vest,
				FABRIC
			)
		end
		bit(ctx, torso, "Vest", Vector3.new(tw + 0.02, th * 0.97, 0.05), CFrame.new(0, -0.01, bz + 0.03), vest, FABRIC)
		for i = 0, 2 do
			bit(
				ctx,
				torso,
				"Button",
				Vector3.new(0.1, 0.1, 0.03),
				CFrame.new(tw * 0.11, th * 0.12 - i * 0.36, fz - 0.065),
				BRASS,
				Enum.Material.Metal
			)
		end
		bit(
			ctx,
			torso,
			"WatchChain",
			Vector3.new(0.55, 0.05, 0.03),
			CFrame.new(-tw * 0.2, -th * 0.18, fz - 0.065) * CFrame.Angles(0, 0, 0.25),
			BRASS,
			Enum.Material.Metal
		)
	end

	-- Apron: bib and skirt (it hangs in front of the legs), neck strap,
	-- a pocket with a ruler in it.
	local apron = spec.apron
	if apron then
		bit(
			ctx,
			torso,
			"Apron",
			Vector3.new(tw * 0.7, th * 0.74, 0.05),
			CFrame.new(0, -th * 0.13, fz - 0.035),
			apron,
			FABRIC
		)
		bit(
			ctx,
			torso,
			"Apron",
			Vector3.new(tw * 0.78, 1.1, 0.05),
			CFrame.new(0, -th / 2 - 0.5, fz - 0.17),
			apron,
			FABRIC
		)
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				torso,
				"ApronStrap",
				Vector3.new(0.12, 0.6, 0.05),
				CFrame.new(side * tw * 0.27, th * 0.36, fz - 0.035) * CFrame.Angles(0, 0, side * 0.35),
				Kit.shade(apron, -0.15),
				FABRIC
			)
		end
		bit(
			ctx,
			torso,
			"ApronTie",
			Vector3.new(tw + 0.04, 0.1, td + 0.04),
			CFrame.new(0, -th * 0.27, 0),
			Kit.shade(apron, -0.15),
			FABRIC
		)
		bit(
			ctx,
			torso,
			"Pocket",
			Vector3.new(0.9, 0.36, 0.03),
			CFrame.new(0, -th / 2 - 0.2, fz - 0.21),
			Kit.shade(apron, -0.12),
			FABRIC
		)
		bit(
			ctx,
			torso,
			"Ruler",
			Vector3.new(0.12, 0.5, 0.04),
			CFrame.new(-0.25, -th / 2 - 0.05, fz - 0.23) * CFrame.Angles(0, 0, 0.12),
			Color3.fromRGB(236, 200, 120)
		)
	end

	-- Belt (or a toolbelt with pouches and a hammer).
	if not ov then
		bit(
			ctx,
			torso,
			"Belt",
			Vector3.new(tw + 0.05, 0.22, td + 0.05),
			CFrame.new(0, -th / 2 + 0.11, 0),
			LEATHER,
			Enum.Material.Leather
		)
		if not apron then
			bit(
				ctx,
				torso,
				"Buckle",
				Vector3.new(0.32, 0.2, 0.04),
				CFrame.new(0, -th / 2 + 0.11, fz - 0.045),
				BRASS,
				Enum.Material.Metal
			)
		end
	end
	if spec.toolbelt then
		for _, side in ipairs(sides()) do
			bit(
				ctx,
				torso,
				"Pouch",
				Vector3.new(0.46, 0.5, 0.3),
				CFrame.new(side * tw * 0.36, -th / 2 - 0.08, fz - 0.06),
				Color3.fromRGB(150, 98, 54),
				Enum.Material.Leather
			)
		end
		-- A screwdriver poking out of the left pouch, a hammer on the right hip.
		bit(
			ctx,
			torso,
			"Screwdriver",
			Vector3.new(0.08, 0.34, 0.08),
			CFrame.new(-tw * 0.32, -th / 2 + 0.3, fz - 0.06) * CFrame.Angles(0, 0, 0.2),
			Color3.fromRGB(220, 70, 60)
		)
		bit(
			ctx,
			torso,
			"Hammer",
			Vector3.new(0.13, 0.8, 0.13),
			CFrame.new(tw / 2 + 0.08, -th / 2 - 0.2, 0.15),
			Color3.fromRGB(160, 112, 66),
			Enum.Material.Wood
		)
		bit(
			ctx,
			torso,
			"Hammer",
			Vector3.new(0.18, 0.18, 0.46),
			CFrame.new(tw / 2 + 0.08, -th / 2 + 0.26, 0.15),
			IRON,
			Enum.Material.Metal
		)
	end

	-- Scarf: a wrap at the neck and a tail down the front.
	local scarf = spec.scarf
	if scarf then
		bit(
			ctx,
			torso,
			"Scarf",
			Vector3.new(HEAD_W + 0.16, 0.34, HEAD_D + 0.16),
			CFrame.new(0, th / 2 + 0.05, 0),
			scarf,
			FABRIC
		)
		local tail = CFrame.new(-tw * 0.2, th / 2 - 0.5, fz - 0.07) * CFrame.Angles(0, 0, 0.1)
		bit(ctx, torso, "Scarf", Vector3.new(0.36, 0.95, 0.08), tail, scarf, FABRIC)
		for _, y in ipairs({ -0.12, -0.32 }) do
			bit(
				ctx,
				torso,
				"ScarfStripe",
				Vector3.new(0.37, 0.08, 0.09),
				tail * CFrame.new(0, y, 0),
				Kit.shade(scarf, 0.35),
				FABRIC
			)
		end
	end
end

local function armDetails(ctx: Ctx, arm: BasePart, side: number)
	local spec = ctx.spec
	local ah = ARM_H
	-- Hands (or gloves), and rolled-up sleeves showing the forearm.
	local hand = spec.gloves or spec.skin
	if spec.rolledSleeves then
		bit(
			ctx,
			arm,
			"Forearm",
			Vector3.new(ARM_W + 0.01, 0.5, ARM_D + 0.01),
			CFrame.new(0, -ah / 2 + 0.72, 0),
			spec.skin
		)
		bit(
			ctx,
			arm,
			"SleeveRoll",
			Vector3.new(ARM_W + 0.08, 0.24, ARM_D + 0.08),
			CFrame.new(0, -ah / 2 + 1.06, 0),
			Kit.shade(spec.shirt, 0.18),
			FABRIC
		)
	end
	bit(ctx, arm, "Hand", Vector3.new(ARM_W + 0.02, 0.5, ARM_D + 0.02), CFrame.new(0, -ah / 2 + 0.25, 0), hand)
	if spec.gloves then
		bit(
			ctx,
			arm,
			"GloveCuff",
			Vector3.new(ARM_W + 0.1, 0.2, ARM_D + 0.1),
			CFrame.new(0, -ah / 2 + 0.56, 0),
			Kit.shade(spec.gloves, -0.15),
			Enum.Material.Leather
		)
	end
	-- Flannel checks on the sleeve.
	local plaid = spec.stripe
	if plaid then
		bit(
			ctx,
			arm,
			"Stripe",
			Vector3.new(ARM_W + 0.03, 0.2, ARM_D + 0.03),
			CFrame.new(0, ah * 0.3, 0),
			Kit.shade(plaid, 0.06),
			FABRIC
		)
		bit(
			ctx,
			arm,
			"Stripe",
			Vector3.new(0.03, if spec.rolledSleeves then ah * 0.45 else ah * 0.7, 0.22),
			CFrame.new(side * (ARM_W / 2 + 0.015), if spec.rolledSleeves then ah * 0.27 else ah * 0.1, 0),
			plaid,
			FABRIC
		)
	end
end

local function legDetails(ctx: Ctx, leg: BasePart, side: number)
	local spec = ctx.spec
	local lh = LEG_H
	local boots = spec.boots or DEFAULT_BOOTS
	bit(
		ctx,
		leg,
		"Boot",
		Vector3.new(LEG_W + 0.06, 0.56, LEG_D + 0.12),
		CFrame.new(0, -lh / 2 + 0.28, -0.06),
		boots,
		Enum.Material.Leather
	)
	bit(
		ctx,
		leg,
		"Sole",
		Vector3.new(LEG_W + 0.08, 0.12, LEG_D + 0.16),
		CFrame.new(0, -lh / 2 + 0.06, -0.08),
		Kit.shade(boots, -0.45)
	)
	bit(
		ctx,
		leg,
		"Lace",
		Vector3.new(0.34, 0.05, 0.02),
		CFrame.new(0, -lh / 2 + 0.42, -LEG_D / 2 - 0.13),
		Kit.shade(boots, 0.35)
	)
	if spec.cuffs then
		bit(
			ctx,
			leg,
			"Cuff",
			Vector3.new(LEG_W + 0.07, 0.2, LEG_D + 0.07),
			CFrame.new(0, -lh / 2 + 0.66, 0),
			Kit.shade(spec.overalls or spec.pants, 0.22),
			FABRIC
		)
	end
	local patch = spec.kneePatch
	if patch and side > 0 then
		bit(
			ctx,
			leg,
			"KneePatch",
			Vector3.new(0.5, 0.42, 0.03),
			CFrame.new(0.05, 0.05, -LEG_D / 2 - 0.015) * CFrame.Angles(0, 0, 0.1),
			patch,
			FABRIC
		)
	end
end

---------------------------------------------------------------------------
-- Things to hold (left hand)
---------------------------------------------------------------------------

local function carry(ctx: Ctx, arm: BasePart)
	local spec = ctx.spec
	local kind: Carry = spec.carry or "none"
	local hy = -ARM_H / 2 + 0.25 -- the hand's centre
	local fz = -ARM_D / 2
	local inward = 1 -- toward the body's centre (+X for the left arm)
	if kind == "mug" then
		local body = spec.accent or Color3.fromRGB(64, 112, 170)
		local at = CFrame.new(inward * 0.12, hy + 0.05, fz - 0.24)
		bit(
			ctx,
			arm,
			"Mug",
			Vector3.new(0.5, 0.44, 0),
			at * CFrame.Angles(0, 0, math.pi / 2),
			body,
			SMOOTH,
			nil,
			"cylinder"
		)
		bit(
			ctx,
			arm,
			"MugRim",
			Vector3.new(0.06, 0.47, 0),
			at * CFrame.new(0, 0.24, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(240, 236, 226),
			SMOOTH,
			nil,
			"cylinder"
		)
		bit(
			ctx,
			arm,
			"Coffee",
			Vector3.new(0.02, 0.36, 0),
			at * CFrame.new(0, 0.26, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(70, 42, 24),
			SMOOTH,
			nil,
			"cylinder"
		)
		bit(ctx, arm, "MugHandle", Vector3.new(0.1, 0.3, 0.14), at * CFrame.new(0, 0, 0.27), body)
		-- White speckles: an enamel camp mug.
		for i = 0, 1 do
			local a = i * 2.6 - 0.9
			bit(
				ctx,
				arm,
				"MugSpeckle",
				Vector3.new(0.06, 0.06, 0.02),
				at * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.1 + i * 0.09, -0.225),
				WHITE
			)
		end
		local coffee = arm:FindFirstChild("Coffee")
		if coffee then
			local steam = Instance.new("ParticleEmitter")
			steam.Name = "Steam"
			steam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			steam.LightEmission = 0.2
			steam.Rate = 1.5
			steam.Lifetime = NumberRange.new(1.2, 2)
			steam.Speed = NumberRange.new(0.6, 1)
			steam.SpreadAngle = Vector2.new(10, 10)
			steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.45) })
			steam.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
			steam.Parent = coffee
		end
	elseif kind == "clipboard" then
		local at = CFrame.new(inward * 0.3, hy - 0.1, fz - 0.07)
		bit(ctx, arm, "Clipboard", Vector3.new(0.85, 1.1, 0.07), at, Color3.fromRGB(150, 104, 60), Enum.Material.Wood)
		bit(
			ctx,
			arm,
			"ClipboardPaper",
			Vector3.new(0.7, 0.86, 0.02),
			at * CFrame.new(0, -0.06, -0.045),
			Color3.fromRGB(246, 240, 226)
		)
		for i = 0, 2 do
			bit(
				ctx,
				arm,
				"ClipboardLine",
				Vector3.new(0.5, 0.04, 0.01),
				at * CFrame.new(-0.04, 0.12 - i * 0.18, -0.06),
				Color3.fromRGB(120, 140, 170)
			)
		end
		bit(
			ctx,
			arm,
			"ClipboardClip",
			Vector3.new(0.34, 0.12, 0.06),
			at * CFrame.new(0, 0.5, -0.05),
			IRON,
			Enum.Material.Metal
		)
	elseif kind == "wrench" then
		local at = CFrame.new(0, hy - 0.62, fz + 0.1)
		local steel = Color3.fromRGB(168, 172, 180)
		bit(ctx, arm, "Wrench", Vector3.new(0.14, 1.0, 0.08), at, steel, Enum.Material.Metal)
		bit(ctx, arm, "Wrench", Vector3.new(0.46, 0.12, 0.08), at * CFrame.new(0, -0.52, 0), steel, Enum.Material.Metal)
		for _, s in ipairs(sides()) do
			bit(
				ctx,
				arm,
				"Wrench",
				Vector3.new(0.12, 0.24, 0.08),
				at * CFrame.new(s * 0.17, -0.68, 0),
				steel,
				Enum.Material.Metal
			)
		end
	elseif kind == "basket" then
		local wicker = spec.accent or Color3.fromRGB(176, 128, 72)
		local at = CFrame.new(0, hy - 0.78, 0)
		bit(ctx, arm, "Basket", Vector3.new(0.9, 0.5, 0.7), at, wicker, Enum.Material.WoodPlanks)
		bit(
			ctx,
			arm,
			"BasketRim",
			Vector3.new(0.98, 0.1, 0.78),
			at * CFrame.new(0, 0.26, 0),
			Kit.shade(wicker, -0.18),
			Enum.Material.Wood
		)
		bit(
			ctx,
			arm,
			"BasketHandle",
			Vector3.new(0.08, 0.62, 0.08),
			at * CFrame.new(-0.4, 0.55, 0),
			Kit.shade(wicker, -0.18),
			Enum.Material.Wood
		)
		bit(
			ctx,
			arm,
			"BasketHandle",
			Vector3.new(0.08, 0.62, 0.08),
			at * CFrame.new(0.4, 0.55, 0),
			Kit.shade(wicker, -0.18),
			Enum.Material.Wood
		)
		bit(
			ctx,
			arm,
			"BasketHandle",
			Vector3.new(0.88, 0.08, 0.08),
			at * CFrame.new(0, 0.86, 0),
			Kit.shade(wicker, -0.18),
			Enum.Material.Wood
		)
		-- Forage: berries and a red-capped mushroom.
		for i, p in ipairs({ { -0.22, 0.12 }, { 0.0, -0.15 }, { 0.2, 0.1 } }) do
			bit(
				ctx,
				arm,
				"Berry",
				Vector3.one * 0.2,
				at * CFrame.new(p[1], 0.32 + (i % 2) * 0.03, p[2]),
				if i == 2 then Color3.fromRGB(80, 60, 150) else Color3.fromRGB(205, 46, 60),
				SMOOTH,
				nil,
				"ball"
			)
		end
		bit(ctx, arm, "MushroomStem", Vector3.new(0.1, 0.2, 0.1), at * CFrame.new(0.26, 0.38, -0.12), WHITE)
		bit(
			ctx,
			arm,
			"MushroomCap",
			Vector3.new(0.3, 0.14, 0.3),
			at * CFrame.new(0.26, 0.5, -0.12),
			Color3.fromRGB(214, 64, 48)
		)
	elseif kind == "cane" then
		local wood = spec.accent or Color3.fromRGB(122, 82, 50)
		local len = ROOT_Y + ARM_H / 2 - 0.55 -- the fist's top down to the ground
		bit(
			ctx,
			arm,
			"Cane",
			Vector3.new(0.15, len, 0.15),
			CFrame.new(0, -ARM_H / 2 + 0.55 - len / 2, fz - 0.12),
			wood,
			Enum.Material.Wood
		)
		bit(
			ctx,
			arm,
			"Cane",
			Vector3.new(0.15, 0.15, 0.5),
			CFrame.new(0, -ARM_H / 2 + 0.62, fz - 0.3),
			wood,
			Enum.Material.Wood
		)
		bit(
			ctx,
			arm,
			"CaneTip",
			Vector3.new(0.2, 0.16, 0.2),
			CFrame.new(0, -ARM_H / 2 + 0.55 - len + 0.08, fz - 0.12),
			Color3.fromRGB(40, 36, 34)
		)
	elseif kind == "scroll" then
		local blue = spec.accent or Color3.fromRGB(58, 110, 165)
		local at = CFrame.new(0, hy + 0.05, fz - 0.17)
		bit(
			ctx,
			arm,
			"Blueprint",
			Vector3.new(1.5, 0.3, 0),
			at * CFrame.Angles(0, 0, math.pi / 2),
			blue,
			SMOOTH,
			nil,
			"cylinder"
		)
		for _, s in ipairs(sides()) do
			bit(
				ctx,
				arm,
				"BlueprintEnd",
				Vector3.new(0.04, 0.24, 0),
				at * CFrame.new(0, s * 0.76, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(226, 236, 248),
				SMOOTH,
				nil,
				"cylinder"
			)
		end
		bit(
			ctx,
			arm,
			"BlueprintTie",
			Vector3.new(0.32, 0.08, 0.32),
			at * CFrame.new(0, 0.28, 0),
			Color3.fromRGB(196, 60, 52)
		)
	elseif kind == "lantern" then
		local at = CFrame.new(0, hy - 0.72, 0)
		bit(
			ctx,
			arm,
			"LanternHandle",
			Vector3.new(0.06, 0.34, 0.06),
			at * CFrame.new(0, 0.6, 0),
			IRON,
			Enum.Material.Metal
		)
		bit(ctx, arm, "LanternCap", Vector3.new(0.5, 0.14, 0.5), at * CFrame.new(0, 0.38, 0), IRON, Enum.Material.Metal)
		local glow = bit(
			ctx,
			arm,
			"LanternGlow",
			Vector3.new(0.36, 0.5, 0.36),
			at,
			Color3.fromRGB(255, 200, 110),
			Enum.Material.Neon
		)
		bit(
			ctx,
			arm,
			"LanternBase",
			Vector3.new(0.46, 0.12, 0.46),
			at * CFrame.new(0, -0.3, 0),
			IRON,
			Enum.Material.Metal
		)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Range = 10
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = glow
	elseif kind == "sapling" then
		local at = CFrame.new(inward * 0.22, hy + 0.02, fz - 0.36)
		local pot = spec.accent or Color3.fromRGB(196, 104, 64)
		bit(ctx, arm, "Pot", Vector3.new(0.56, 0.5, 0.56), at, pot, SMOOTH)
		bit(ctx, arm, "PotRim", Vector3.new(0.66, 0.12, 0.66), at * CFrame.new(0, 0.26, 0), Kit.shade(pot, -0.12))
		bit(ctx, arm, "Soil", Vector3.new(0.5, 0.04, 0.5), at * CFrame.new(0, 0.3, 0), Color3.fromRGB(84, 58, 40))
		bit(
			ctx,
			arm,
			"SaplingStem",
			Vector3.new(0.07, 0.56, 0.07),
			at * CFrame.new(0, 0.58, 0),
			Color3.fromRGB(110, 78, 44)
		)
		for i, p in ipairs({ { -0.14, 0.78, 0.4 }, { 0.15, 0.92, -0.5 }, { 0, 1.02, 0 } }) do
			bit(
				ctx,
				arm,
				"SaplingLeaf",
				Vector3.new(0.3, 0.12, 0.2),
				at * CFrame.new(p[1], p[2], 0) * CFrame.Angles(0, i * 1.1, p[3]),
				if i == 3 then Color3.fromRGB(120, 196, 88) else Color3.fromRGB(92, 168, 72)
			)
		end
	end
end

---------------------------------------------------------------------------
-- The name tag
---------------------------------------------------------------------------

local function nameTag(head: BasePart, name: string, role: string?, offsetY: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(220, if role then 50 else 30)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 30)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 24
	label.TextColor3 = Color3.fromRGB(245, 235, 215)
	label.TextStrokeColor3 = Color3.fromRGB(60, 40, 20)
	label.TextStrokeTransparency = 0.2
	label.Text = name
	label.Parent = gui
	if role then
		local r = Instance.new("TextLabel")
		r.Name = "Role"
		r.BackgroundTransparency = 1
		r.Position = UDim2.fromOffset(0, 28)
		r.Size = UDim2.new(1, 0, 0, 20)
		r.Font = Enum.Font.GothamBold
		r.TextSize = 14
		r.TextColor3 = Color3.fromRGB(255, 184, 64)
		r.TextStrokeColor3 = Color3.fromRGB(60, 40, 20)
		r.TextStrokeTransparency = 0.3
		r.Text = role
		r.Parent = gui
	end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function motor(name: string, parent: Instance, part0: BasePart, part1: BasePart, pivot: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * pivot
	m.C1 = part1.CFrame:Inverse() * pivot
	m.Parent = parent
end

local function weld(part: BasePart, to: BasePart)
	local w = Instance.new("Weld")
	w.Name = "Weld"
	w.Part0 = to
	w.Part1 = part
	w.C0 = to.CFrame:Inverse() * part.CFrame
	w.Parent = part
end

-- The joints, in the order they're made: { name, parent, part0, part1, pivot }.
local JOINTS = { "RootJoint", "Neck", "LeftShoulder", "RightShoulder", "LeftHip", "RightHip" }
CharacterArt.Joints = JOINTS

-- How high the root's centre stands above the feet, without building the
-- figure.
function CharacterArt.RootHeight(spec: Spec): number
	return ROOT_Y * (spec.scale or 1)
end

function CharacterArt.Build(spec: Spec): Model
	local s = spec.scale or 1
	local model = Kit.model(spec.name)
	local ctx: Ctx = {
		model = model,
		spec = spec,
		rng = Kit.rng(spec.seed or #spec.name * 977),
		welds = {},
		top = HEAD_H / 2,
	}
	local tw = if spec.stout then 2.3 else 2.0
	local td = if spec.stout then 1.18 else 1.04
	local legX = if spec.stout then 0.56 else 0.5
	local armX = tw / 2 + ARM_W / 2 + 0.01
	local pants = spec.overalls or spec.pants
	local headY = LEG_H + TORSO_H + HEAD_H / 2

	-- The root: invisible, anchored, the model's PrimaryPart.
	local root = Kit.part(
		model,
		"HumanoidRootPart",
		Vector3.new(tw, TORSO_H, td),
		CFrame.new(0, ROOT_Y, 0),
		Color3.fromRGB(163, 162, 165),
		SMOOTH
	)
	root.Transparency = 1
	root.CanTouch = false
	root.CastShadow = false
	model.PrimaryPart = root

	local torso = limbPart(ctx, "Torso", Vector3.new(tw, TORSO_H, td), CFrame.new(0, ROOT_Y, 0), spec.shirt, FABRIC)
	local head = limbPart(ctx, "Head", Vector3.new(HEAD_W, HEAD_H, HEAD_D), CFrame.new(0, headY, 0), spec.skin, SMOOTH)
	local arms: { [number]: Part } = {}
	local legs: { [number]: Part } = {}
	for _, side in ipairs(sides()) do
		arms[side] = limbPart(
			ctx,
			if side < 0 then "LeftArm" else "RightArm",
			Vector3.new(ARM_W, ARM_H, ARM_D),
			CFrame.new(side * armX, ROOT_Y, 0),
			spec.shirt,
			FABRIC
		)
		legs[side] = limbPart(
			ctx,
			if side < 0 then "LeftLeg" else "RightLeg",
			Vector3.new(LEG_W, LEG_H, LEG_D),
			CFrame.new(side * legX, LEG_H / 2, 0),
			pants,
			FABRIC
		)
	end

	-- Dress up.
	local hatted = (spec.hat or "none") ~= "none" and spec.hat ~= "bandana"
	face(ctx, head)
	if spec.glasses then
		glasses(ctx, head, spec.glasses)
	end
	hair(ctx, head, hatted or spec.hat == "bandana")
	beard(ctx, head)
	hat(ctx, head)
	torsoDetails(ctx, torso, tw, td)
	for _, side in ipairs(sides()) do
		armDetails(ctx, arms[side], side)
		legDetails(ctx, legs[side], side)
	end
	carry(ctx, arms[-1])

	-- Scale everything about the origin (feet), then join it up.
	if s ~= 1 then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local cf = d.CFrame
				d.Size *= s
				d.CFrame = CFrame.new(cf.Position * s) * cf.Rotation
			end
		end
	end
	for _, w in ipairs(ctx.welds) do
		weld(w.part, w.to)
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * s, y * s, z * s)
	end
	motor("RootJoint", root, root, torso, at(0, ROOT_Y, 0))
	motor("Neck", torso, torso, head, at(0, LEG_H + TORSO_H, 0))
	motor("LeftShoulder", torso, torso, arms[-1], at(-armX, ROOT_Y + 0.55, 0))
	motor("RightShoulder", torso, torso, arms[1], at(armX, ROOT_Y + 0.55, 0))
	motor("LeftHip", torso, torso, legs[-1], at(-legX, LEG_H, 0))
	motor("RightHip", torso, torso, legs[1], at(legX, LEG_H, 0))

	-- Everything but the root hangs off it: unanchored, weightless.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.Massless = true
		end
	end

	if spec.tag ~= false then
		nameTag(head, spec.name, spec.role, (ctx.top + 1.0) * s)
	end
	model:SetAttribute("Scale", s)
	model:SetAttribute("RootHeight", ROOT_Y * s)
	model:SetAttribute("TopOffset", ctx.top * s)
	model:SetAttribute("Height", (headY + ctx.top) * s)
	return model
end

return CharacterArt
