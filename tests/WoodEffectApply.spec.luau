--!nocheck
-- BlueprintModels.ApplyWood on a cabin for the five effect woods and oak
-- (WOODFX-T316): only Door parts take the accent; only the allowed tag and
-- attributes appear; no light, no emitter, the same part count as oak; a normal
-- wood leaves no mark; cost and sell value do not depend on the wood; paint
-- removes the effect.
return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local BuildCost = t.shared("BuildCost")
	local BlueprintModels = t.shared("BlueprintModels")
	local WoodData = t.shared("WoodData")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local Net = t.shared("Net")
	local KitPaint = t.shared("KitPaint")

	local EFFECT = { "frostwood", "emberwood", "phantomwood", "lumenwood" }
	local ALLOWED_ATTRS = { NightGlow = true, WoodId = true, NightHost = true }
	local ALLOWED_PART_ATTRS = { NightGlow = true }

	local function bp(id)
		return PlotData.Blueprint(id)
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Every kit piece with a Door-role part, for the PR.
	local function doorPieces()
		local out = {}
		for _, b in ipairs(PlotData.Blueprints) do
			local ok, model = pcall(BlueprintModels.Build, b, false)
			if ok and model then
				for _, p in ipairs(parts(model)) do
					if p:GetAttribute("Role") == "Door" then
						table.insert(out, b.id)
						break
					end
				end
			end
		end
		return out
	end

	t.test("pieces with a Door part (the effect shows there)", function()
		local ids = doorPieces()
		print("kit pieces with a Door part: " .. table.concat(ids, ", "))
		t.ok(table.find(ids, "Door") ~= nil, "the door")
		t.ok(table.find(ids, "Cabin") ~= nil or #ids > 0, "some piece has one")
	end)

	t.test("only Door parts take the accent; Wood parts keep the core colour", function()
		local sawDoor = false
		for _, id in ipairs(EFFECT) do
			local def = WoodData.Get(id)
			local core = TreeArt.Core(def)
			local accent = Palette.Get(WoodData.EffectOf(id).accent)
			for _, pieceId in ipairs({ "Cabin", "Door" }) do
				local model = BlueprintModels.Build(bp(pieceId), false)
				BlueprintModels.ApplyWood(model, id)
				for _, p in ipairs(parts(model)) do
					local role = p:GetAttribute("Role")
					if role == "Door" then
						sawDoor = true
						t.eq(p.Color, accent, id .. " door takes the accent")
					elseif role == "Wood" then
						t.eq(p.Color, core, id .. " wall keeps the core colour")
						t.eq(p:GetAttribute("NightGlow"), nil, "a wall has no mark")
					end
				end
			end
		end
		t.ok(sawDoor, "a Door part was checked")
	end)

	t.test("lantern keeps marking Wood and Door parts, with its core colour, as on main", function()
		local model = BlueprintModels.Build(bp("Door"), false)
		BlueprintModels.ApplyWood(model, "lanternwood")
		t.ok(model:HasTag("Lanternwood"))
		t.ok(not model:HasTag("WoodEffect"))
		t.eq(model:GetAttribute("NightHost"), "plank")
		local core = TreeArt.Core(WoodData.Get("lanternwood"))
		for _, p in ipairs(parts(model)) do
			local role = p:GetAttribute("Role")
			if role == "Wood" or role == "Door" then
				t.eq(p.Color, core)
				t.eq(p:GetAttribute("NightGlow"), true)
			end
		end
	end)

	t.test("the tag and attributes set are exactly the allowed ones; neon marks only ember and gloam doors", function()
		for _, id in ipairs(EFFECT) do
			local model = BlueprintModels.Build(bp("Door"), false)
			local before = #parts(model)
			local attrsBefore = model:GetAttributes()
			BlueprintModels.ApplyWood(model, id)
			t.ok(model:HasTag("WoodEffect"), id .. " tagged WoodEffect")
			t.ok(not model:HasTag("Lanternwood"), id .. " is not a lantern")
			t.eq(model:GetAttribute("NightHost"), "plank")
			t.eq(model:GetAttribute("WoodId"), id)
			for name in pairs(model:GetAttributes()) do
				t.ok(
					attrsBefore[name] ~= nil or ALLOWED_ATTRS[name] ~= nil,
					"ApplyWood added only an allowed attribute: " .. name
				)
			end
			t.eq(#parts(model), before, "no part added")
			for _, d in ipairs(model:GetDescendants()) do
				t.ok(
					not d:IsA("PointLight") and not d:IsA("ParticleEmitter") and not d:IsA("SurfaceLight"),
					"no light or emitter"
				)
				if d:IsA("BasePart") then
					for name in pairs(d:GetAttributes()) do
						if name == "NightGlow" then
							t.ok(ALLOWED_PART_ATTRS[name], "only the NightGlow mark")
							t.eq(d:GetAttribute("Role"), "Door", "only a Door part is marked")
						end
					end
					if d:GetAttribute("Role") == "Door" then
						t.eq(
							d:GetAttribute("NightGlow") == true,
							WoodData.EffectOf(id).neon,
							id .. " marks only when neon"
						)
					end
				end
			end
		end
	end)

	t.test(
		"the same part count as oak for every wood, and oak and the other normal woods get no tag and no mark",
		function()
			local oak = BlueprintModels.Build(bp("Cabin"), false)
			BlueprintModels.ApplyWood(oak, "oak")
			local baseline = #parts(oak)
			for _, id in ipairs({
				"frostwood",
				"emberwood",
				"phantomwood",
				"lumenwood",
				"lanternwood",
				"birch",
				"pine",
				"maple",
			}) do
				local model = BlueprintModels.Build(bp("Cabin"), false)
				BlueprintModels.ApplyWood(model, id)
				t.eq(#parts(model), baseline, id .. " part count equals oak")
			end
			for _, id in ipairs({ "oak", "birch", "pine", "maple", "palmwood", "bogcypress", "ironwood" }) do
				local model = BlueprintModels.Build(bp("Door"), false)
				BlueprintModels.ApplyWood(model, id)
				t.ok(not model:HasTag("WoodEffect") and not model:HasTag("Lanternwood"), id .. " gets no tag")
				t.eq(model:GetAttribute("WoodId"), nil, id .. " keeps no WoodId")
				for _, p in ipairs(parts(model)) do
					t.eq(p:GetAttribute("NightGlow"), nil, id .. " no mark")
				end
			end
		end
	)

	t.test("cost and sell value are the same for the same piece in every wood", function()
		for _, pieceId in ipairs({ "Cabin", "Door", "Wall" }) do
			local piece = bp(pieceId)
			local cost = BuildCost.Of(piece)
			local sell = PlotLogic.SellValue(piece)
			for _, def in ipairs(WoodData.All()) do
				local model = BlueprintModels.Build(piece, false)
				BlueprintModels.ApplyWood(model, def.id)
				t.eq(BuildCost.Of(piece), cost, pieceId .. " cost in " .. def.id)
				t.eq(PlotLogic.SellValue(piece), sell, pieceId .. " sell in " .. def.id)
			end
		end
	end)

	t.test("paint wins: after ApplyPaint no Door part is NightGlow; natural or nil leaves the wood look", function()
		local paintId = "brick"
		t.ok(KitPaint.Valid(paintId), "a real KitPaint id")
		for _, id in ipairs({ "emberwood", "phantomwood", "frostwood", "lumenwood", "lanternwood" }) do
			local model = BlueprintModels.Build(bp("Door"), false)
			BlueprintModels.ApplyWood(model, id)
			local look = {}
			for _, p in ipairs(parts(model)) do
				look[p] = p.Color
			end
			BlueprintModels.ApplyPaint(model, nil)
			BlueprintModels.ApplyPaint(model, "natural")
			for _, p in ipairs(parts(model)) do
				t.eq(p.Color, look[p], id .. " no paint leaves the wood alone")
			end
			BlueprintModels.ApplyPaint(model, paintId)
			for _, p in ipairs(parts(model)) do
				if p:GetAttribute("Role") == "Door" then
					t.eq(p:GetAttribute("NightGlow"), nil, id .. " door is no longer glowing")
					t.eq(p:GetAttribute("Painted"), true)
				end
			end
		end
	end)

	t.test("the chop feel and wood effects added no remote", function()
		t.eq(#Net.RemoteNames, 74)
	end)
end
