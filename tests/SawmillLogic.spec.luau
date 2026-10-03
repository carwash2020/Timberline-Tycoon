--!nocheck
-- Which logs a sawmill takes, and the planks it cuts (V2_PLAN.md §2e, §7).
return function(t)
	local V3 = t.roblox.Vector3
	local loader = t.loader()
	local Logic = loader:shared("SawmillLogic")
	local Catalog = loader:shared("ItemCatalog")
	local Config = loader:shared("GameConfig")
	local Sell = loader:shared("SellLogic")

	local rickety = Catalog.GetSawmill("SawmillRickety")
	local u = Config.WoodUnit

	local function section(length, thick, dir, children, root)
		return {
			length = length,
			sx = thick,
			sz = thick,
			dir = dir or V3.yAxis,
			children = children or 0,
			root = if root == nil then true else root,
		}
	end

	local function piece(kind, sections)
		return { kind = kind or "log", sections = sections }
	end

	t.test("a straight oak trunk fits the Rickety; a pine base and a branch do not", function()
		local oak = piece("log", { section(9, 2) })
		t.eq({ Logic.Accepts(oak, rickety) }, { true, nil })
		local pine = piece("log", { section(9, 2.6) })
		t.eq({ Logic.Accepts(pine, rickety) }, { false, "thick" })
		local branched = piece("log", { section(9, 2, V3.yAxis, 2, true) })
		t.eq({ Logic.Accepts(branched, rickety) }, { false, "branch" })
	end)

	t.test("a crooked log and a plank are refused, and a tiny scrap is too small", function()
		local lean = math.rad(20)
		local crooked = piece("log", {
			section(6, 2, V3.yAxis, 1, true),
			section(4, 1.5, V3.new(math.sin(lean), math.cos(lean), 0), 0, false),
		})
		t.eq({ Logic.Accepts(crooked, rickety) }, { false, "crooked" })
		local straight = piece("log", {
			section(6, 2, V3.yAxis, 1, true),
			section(4, 1.5, V3.yAxis, 0, false),
		})
		t.eq(Logic.Accepts(straight, rickety), true)
		t.eq({ Logic.Accepts(piece("plank", { section(4, 1) }), rickety) }, { false, "plank" })
		local dust = piece("log", { section(0.05, 0.2) })
		t.eq({ Logic.Accepts(dust, rickety) }, { false, "small" })
	end)

	t.test("length and thickness use the mill's limits in studs", function()
		local limit = rickety.maxLength * u
		t.eq(Logic.Accepts(piece("log", { section(limit, rickety.maxWidth * u) }), rickety), true)
		t.eq({ Logic.Accepts(piece("log", { section(limit + 0.05, 2) }), rickety) }, { false, "long" })
		t.eq({ Logic.Accepts(piece("log", { section(8, rickety.maxWidth * u + 0.05) }), rickety) }, { false, "thick" })
	end)

	t.test("the cut keeps the log's volume and the last plank takes the rest", function()
		local volume = Sell.VolumeU3(2, 9, 2)
		local settings = Logic.DefaultSettings(rickety)
		t.eq(settings, { x = 1, y = 0.6 })
		local planks = Logic.Cut(volume, settings, rickety)
		t.ok(#planks >= 2, "a 9-stud log is more than one plank at 1 by 0.6")
		local back = Logic.PlankVolume(planks)
		t.ok(math.abs(back - volume) < 1e-3, string.format("volume %s came back %s", volume, back))
		for _, plank in ipairs(planks) do
			t.ok(plank.sy <= rickety.maxLength * u + 1e-3, "no plank longer than the mill")
			t.ok(math.abs(plank.sx - u) < 1e-6 and math.abs(plank.sz - 0.6 * u) < 1e-6, "the cut's cross section")
		end
	end)

	t.test("the buttons step 0.2 u and stop at the mill's cut", function()
		local settings = Logic.DefaultSettings(rickety)
		settings = Logic.Step(rickety, settings, "x", 1)
		t.eq(settings.x, 1.2)
		settings = Logic.Step(rickety, settings, "y", -1)
		t.eq(settings.y, 0.4)
		settings = Logic.Step(rickety, settings, "y", -1)
		t.eq(settings.y, 0.4, "the plank minimum")
		local wide = Logic.ClampSettings(rickety, 9, 9)
		t.eq(wide, { x = rickety.maxX, y = rickety.maxY })
		t.eq(Logic.Step(rickety, wide, "x", 1).x, rickety.maxX)
	end)

	t.test("stock is a list of mill ids, and a mill places like a blueprint", function()
		t.eq(Logic.DecodeStock(Logic.EncodeStock({ "SawmillRickety", "nope", "SawmillRickety" })), {
			"SawmillRickety",
			"SawmillRickety",
		})
		t.eq(Logic.CountStock({ "SawmillRickety", "SawmillSturdy", "SawmillRickety" }, "SawmillRickety"), 2)
		local bp = Logic.Blueprint("SawmillRickety")
		t.eq(bp.category, "Sawmill")
		t.eq(bp.priceCash, 130)
		t.eq(bp.footprint, t.roblox.Vector2.new(12, 8))
		t.eq(#bp.boxes, 0)
		t.eq(Logic.Blueprint("Bench"), nil)
	end)
end
