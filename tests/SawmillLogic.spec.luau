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

	local function rect(length, sx, sz, dir)
		return {
			length = length,
			sx = sx,
			sz = sz,
			dir = dir or V3.yAxis,
			children = 0,
			root = true,
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

	t.test("a crooked log is refused, a plank is taken, and a tiny scrap is too small", function()
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
		-- A 4-stud plank, 1 stud across, is inside the Rickety and thick enough.
		t.eq(Logic.Accepts(piece("plank", { section(4, 1) }), rickety), true)
		local dust = piece("log", { section(0.05, 1) })
		t.eq({ Logic.Accepts(dust, rickety) }, { false, "small" })
	end)

	t.test("a sheet thinner than the plank minimums is refused", function()
		local minLo = math.min(Config.PlankMinX, Config.PlankMinY) * u
		local minHi = math.max(Config.PlankMinX, Config.PlankMinY) * u
		t.eq(Logic.Accepts(piece("plank", { rect(6, minHi, minLo) }), rickety), true)
		t.eq({ Logic.Accepts(piece("log", { rect(6, 2, minLo - 0.05) }), rickety) }, { false, "thin" })
		t.eq({ Logic.Accepts(piece("plank", { rect(6, minHi - 0.05, minLo) }), rickety) }, { false, "thin" })
		t.eq(Logic.Toast("thin", rickety), "Too thin for this mill.")
	end)

	t.test("a plank milled twice keeps its volume, and five re-mills keep the sale value", function()
		local volume = Sell.VolumeU3(2, 9, 2)
		local settings = Logic.DefaultSettings(rickety)
		local planks = Logic.Cut(volume, settings, rickety)
		t.eq(Logic.OutputKind, "plank")
		local smaller = { x = Config.PlankMinX, y = Config.PlankMinY }
		local function recut(list, cut)
			local out = {}
			local back = 0
			for _, plank in ipairs(list) do
				local view = piece("plank", { rect(plank.sy, plank.sx, plank.sz) })
				t.eq({ Logic.Accepts(view, rickety) }, { true, nil })
				local vol = Logic.PlankVolume({ plank })
				local nextPlanks = Logic.Cut(vol, cut, rickety)
				for _, p in ipairs(nextPlanks) do
					table.insert(out, p)
					back += Logic.PlankVolume({ p })
				end
			end
			return out, back
		end
		local once, onceVol = recut(planks, smaller)
		t.ok(#once >= #planks, "a smaller cut makes thinner planks, not fewer")
		for _, plank in ipairs(once) do
			t.ok(math.abs(plank.sx - smaller.x * u) < 1e-6, "the new width")
			t.ok(math.abs(plank.sz - smaller.y * u) < 1e-6, "the new thickness")
		end
		t.ok(math.abs(onceVol - volume) < 1e-3, string.format("one re-mill %s vs %s", onceVol, volume))
		local figure, boost = "curly", 1.2
		local worth = Sell.PieceValue("oak", "plank", volume, figure, boost)
		local current = planks
		for i = 1, 5 do
			local cut = if i % 2 == 1 then smaller else settings
			local again, back = recut(current, cut)
			t.ok(math.abs(back - volume) < 1e-2, "re-mill " .. i)
			current = again
		end
		local endVol = Logic.PlankVolume(current)
		local endWorth = Sell.PieceValue("oak", "plank", endVol, figure, boost)
		t.ok(math.abs(endWorth - worth) < 0.05, string.format("sale value %s vs %s", endWorth, worth))
		t.eq(Logic.OutputKind, "plank", "a plank never comes back as a log")
	end)

	t.test("the Millmaster 200 Long takes an 18 u log the 200 refuses", function()
		local short = Catalog.GetSawmill("Millmaster200")
		local long = Catalog.GetSawmill("Millmaster200L")
		local log = piece("log", { section(18 * u, 2) })
		t.eq({ Logic.Accepts(log, short) }, { false, "long" })
		t.eq(Logic.Accepts(log, long), true)
		t.eq(Logic.Toast("long", short), "Too big for this mill (max 10.9 u long)")
		t.eq(Logic.Toast("thick", rickety), "Too big for this mill (max 1.4 u wide)")
		t.eq(Logic.ShowsBlockage("thick"), true)
		t.eq(Logic.ShowsBlockage("long"), true)
		t.eq(Logic.ShowsBlockage("branch"), false)
	end)

	t.test("a recorded volume that isn't the parts is refused, and a rested speed is not a fling", function()
		local view = piece("log", { section(9, 2) })
		local measured = Logic.MeasuredVolume(view)
		t.eq(Logic.VolumeMatches(measured, measured), true)
		t.eq(Logic.VolumeMatches(measured * 4, measured), false)
		t.eq(Logic.VolumeMatches(0, measured), true)
		t.eq(Logic.MeasuredVolume(piece("log", { rect(9, 0, 2) })), -1)
		t.eq(Logic.Rested(0), true)
		t.eq(Logic.Rested(Logic.RestSpeed), true)
		t.eq(Logic.Rested(Logic.RestSpeed + 1), false)
		t.eq(Logic.Rested(0 / 0), false)
	end)

	t.test("the cut panel's buttons clear a phone and the D-pad isn't a world prompt", function()
		local Input = loader:shared("InputKit")
		t.eq(Input.TouchOk(Logic.PanelFace(false)), true)
		t.eq(Input.TouchOk(Logic.PanelFace(true)), true)
		t.ok(Logic.PanelFace(false) * 0.7 >= Input.MinTouchPx, "still 44 px at the smallest phone scale")
		t.eq(Input.TagOk(Logic.PanelTextPx), true)
		t.eq(Input.TouchOk(Logic.SurfaceButtonPx), true)
		t.eq(Input.PlacerSafe(Logic.PanelBinds, true), true, "no ButtonX or E while world prompts are on")
		t.eq(Input.KeysUnique(Logic.PanelBinds), true)
		t.eq({ Logic.PadStep(t.roblox.Enum.KeyCode.DPadLeft) }, { "x", -1 })
		t.eq({ Logic.PadStep(t.roblox.Enum.KeyCode.DPadRight) }, { "x", 1 })
		t.eq({ Logic.PadStep(t.roblox.Enum.KeyCode.DPadUp) }, { "y", 1 })
		t.eq({ Logic.PadStep(t.roblox.Enum.KeyCode.DPadDown) }, { "y", -1 })
		t.eq({ Logic.PadStep(t.roblox.Enum.KeyCode.Left) }, { "x", -1 })
		t.eq({ Logic.PadStep(t.roblox.Enum.KeyCode.Right) }, { "x", 1 })
		t.eq(Logic.PanelCloses(t.roblox.Enum.KeyCode.ButtonB), true)
		t.eq(Logic.PanelCloses(t.roblox.Enum.KeyCode.Escape), true)
		t.eq(Logic.PadStep(t.roblox.Enum.KeyCode.ButtonX), nil)
		t.eq(Logic.PadStep(t.roblox.Enum.KeyCode.E), nil)
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
		t.eq(
			Logic.DecodeStock("SawmillRickety,ChopSaw,nope"),
			{ "SawmillRickety", "ChopSaw" },
			"the chop saw waits here too"
		)
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
