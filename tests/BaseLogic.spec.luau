--!nocheck
-- BaseLogic: packing a base away and bringing one back. Pure rules: what can
-- change when, and that a change only MOVES a record (no copy, no loss).
return function(t)
	local Base = t.shared("BaseLogic")
	local Util = t.shared("Util")
	local Schema = t.loader():server("ProfileSchema")

	local function piece(uid)
		return { uid = uid, blueprintId = "Bench", x = 0, z = 0, rot = 0 }
	end

	local function profileWith(placed, pads)
		local data = Util.deepCopy(Schema.Template)
		data.plot = {
			claimed = true,
			tier = 2,
			placed = placed or {},
			squares = {},
			wires = {},
			switches = {},
			pads = pads,
		}
		data.bases = {}
		data.baseCooldownUntil = 0
		return data
	end

	local function ctx(over)
		local c = { now = 1000, hasPad = true, nearOffice = true, busy = false, looseWood = 0 }
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end

	local seq = 0
	local function guid()
		seq += 1
		return "g" .. seq
	end

	t.test("a base is a plot record; empty means nothing worth keeping, and a bought tier is never empty", function()
		t.eq(Base.IsEmpty(Base.FreshPlot()), true)
		t.eq(Base.IsEmpty({ tier = 1, placed = {}, squares = {}, pads = {} }), true)
		t.eq(Base.IsEmpty({ tier = 2, placed = {}, squares = {} }), false, "a bought size")
		t.eq(Base.IsEmpty({ tier = 1, placed = {}, squares = { "1,0" } }), false, "a bought square")
		t.eq(Base.IsEmpty({ tier = 1, placed = {}, pads = { { uid = "p" } } }), false, "a vehicle pad")
		t.eq(Base.Pieces({ placed = { piece("a"), piece("b") }, pads = { { uid = "p" } } }), 3)
		t.eq(Base.Pieces(nil), 0)
	end)

	t.test("check: the order of refusals, and what each says", function()
		local p = profileWith({ piece("a") })
		t.eq({ Base.Check(p, "pack", nil, ctx()) }, { true, nil })
		t.eq({ Base.Check(p, "fly", nil, ctx()) }, { false, "bad" })
		t.eq({ Base.Check(p, "pack", nil, ctx({ busy = true })) }, { false, Base.Reasons.busy })
		t.eq({ Base.Check(p, "pack", nil, ctx({ nearOffice = false })) }, { false, Base.Reasons.office })
		p.plot.claimed = false
		t.eq({ Base.Check(p, "pack", nil, ctx()) }, { false, Base.Reasons.noPlot })
		p.plot.claimed = true
		p.baseCooldownUntil = 1030
		local ok, why = Base.Check(p, "pack", nil, ctx())
		t.eq(ok, false)
		t.eq(why, "Give it 30 more seconds before changing bases.")
		t.eq({ Base.Check(p, "pack", nil, ctx({ now = 1030 })) }, { true, nil }, "the cooldown ends exactly on time")
		p.baseCooldownUntil = 0
		t.eq({ Base.Check(p, "pack", nil, ctx({ looseWood = 2 })) }, { false, Base.Reasons.wood })
		t.eq({ Base.Check(p, "pack", nil, ctx({ hasPad = false })) }, { false, Base.Reasons.nopad })
		p.plot = Base.FreshPlot()
		t.eq({ Base.Check(p, "pack", nil, ctx()) }, { false, Base.Reasons.empty })
		t.eq({ Base.Check(p, "new", nil, ctx()) }, { false, Base.Reasons.empty })
	end)

	t.test("check: the shelf has a cap, and bring needs a real shelf number", function()
		local p = profileWith({ piece("a") })
		for i = 1, Base.Cap do
			p.bases[i] = { placed = { piece("s" .. i) }, tier = 1 }
		end
		t.eq({ Base.Check(p, "pack", nil, ctx()) }, { false, Base.Reasons.full })
		t.eq({ Base.Check(p, "new", nil, ctx()) }, { false, Base.Reasons.full })
		t.eq({ Base.Check(p, "bring", 1, ctx()) }, { true, nil }, "a swap needs no room")
		for _, junk in ipairs({ 0, -1, 1.5, "1", {}, true, 0 / 0, math.huge }) do
			t.eq({ Base.Check(p, "bring", junk, ctx()) }, { false, "bad" }, tostring(junk))
		end
		t.eq({ Base.Check(p, "bring", Base.Cap + 1, ctx()) }, { false, Base.Reasons.gone })
		-- Without a pad the loose-wood rule has nothing to guard.
		t.eq({ Base.Check(p, "bring", 1, ctx({ hasPad = false, looseWood = 5 })) }, { true, nil })
	end)

	t.test("pack moves the record: nothing copied, every uid once, a fresh claimed plot behind it", function()
		local p = profileWith({ piece("a"), piece("b") }, { { uid = "pad1", id = "Rustbucket" } })
		local record = p.plot
		local before = Base.Uids(p)
		local live = Base.Swap(p, "pack", nil, 500, guid)
		t.ok(p.bases[1] == record)
		t.ok(p.plot == live and p.plot ~= record)
		t.eq(p.plot.claimed, true)
		t.eq(Base.IsEmpty(p.plot), true)
		t.eq(Base.Uids(p), before)
		t.eq(record.name, "Base 1")
		t.eq(record.savedAt, 500)
		t.eq(type(record.id), "string")
	end)

	t.test("bring swaps: the base on the pad is crated in the same shelf slot; an empty one just goes", function()
		local p = profileWith({ piece("a") })
		Base.Swap(p, "new", nil, 1, guid) -- A is crated; the pad has a fresh base
		p.plot.placed = { piece("b") } -- the player built B
		local a, b = p.bases[1], p.plot
		local before = Base.Uids(p)
		Base.Swap(p, "bring", 1, 2, guid)
		t.ok(p.plot == a and p.bases[1] == b, "A is out, B is crated in A's slot")
		t.eq(#p.bases, 1)
		t.eq(Base.Uids(p), before)
		-- Bring A's twin back out onto an EMPTY live base: the empty one is dropped, the shelf shrinks.
		Base.Swap(p, "pack", nil, 3, guid)
		t.eq(#p.bases, 2)
		Base.Swap(p, "bring", 1, 4, guid)
		t.eq(#p.bases, 1, "the empty base did not take a shelf slot")
		t.ok(p.plot == b)
		t.eq(Base.Uids(p), before)
	end)

	t.test("names stay with a base and do not repeat on the shelf", function()
		local p = profileWith({ piece("a") })
		Base.Swap(p, "new", nil, 1, guid)
		p.plot.placed = { piece("b") }
		Base.Swap(p, "new", nil, 2, guid)
		t.eq(p.bases[1].name, "Base 1")
		t.eq(p.bases[2].name, "Base 2")
		p.plot.placed = { piece("c") }
		local before = Base.Uids(p)
		Base.Swap(p, "bring", 1, 3, guid)
		t.eq(p.bases[1].name, "Base 3", "the live base got the next free number when it was crated")
		t.eq(p.plot.name, "Base 1")
		t.eq(Base.Uids(p), before)
	end)

	t.test("snapshot and restore undo a swap exactly", function()
		local p = profileWith({ piece("a") })
		Base.Swap(p, "new", nil, 1, guid)
		p.plot.placed = { piece("b") }
		local live, shelf = p.plot, p.bases[1]
		local snap = Base.Snapshot(p)
		Base.Swap(p, "bring", 1, 2, guid)
		Base.Stamp(p, 2)
		Base.Restore(p, snap)
		t.ok(p.plot == live and p.bases[1] == shelf and #p.bases == 1)
		t.eq(p.baseCooldownUntil, 0)
	end)

	t.test("the cooldown is stamped by Stamp and is the configured length", function()
		local p = profileWith({})
		Base.Stamp(p, 100)
		t.eq(p.baseCooldownUntil, 100 + t.shared("GameConfig").BaseCooldownSec)
		t.eq(Base.Cooldown, t.shared("GameConfig").BaseCooldownSec)
		t.eq(Base.Cap, t.shared("GameConfig").BaseShelfCap)
	end)

	t.test("the shelf summary and the confirm words", function()
		local p = profileWith({ piece("a") }, { { uid = "pad1" } })
		Base.Swap(p, "pack", nil, 77, guid)
		local rows = Base.Summary(p)
		t.eq(#rows, 1)
		t.eq(rows[1], { index = 1, name = "Base 1", tier = 2, pieces = 2, savedAt = 77 })
		t.ok(string.find(Base.ConfirmText("pack", "x", true), "Nothing is lost", 1, true) ~= nil)
		t.ok(string.find(Base.ConfirmText("bring", "Base 1", false), "pick a pad", 1, true) ~= nil)
		t.ok(string.find(Base.ConfirmText("bring", "Base 1", true), "Swap your base for Base 1", 1, true) ~= nil)
	end)

	t.test("positions are plot-local: a base carries no world coordinates", function()
		local p = profileWith({ { uid = "a", blueprintId = "Bench", x = 12, z = -4, rot = 1, y = 0.4 } })
		Base.Swap(p, "pack", nil, 1, guid)
		local item = p.bases[1].placed[1]
		t.eq({ item.x, item.z, item.rot, item.y }, { 12, -4, 1, 0.4 }, "untouched, so it loads the same on any pad")
		t.eq(item.worldX, nil)
	end)

	t.test("wiring: the panel, Old Hank's Yes / No and the pad clean-up are all in place", function()
		local fs = require("@lune/fs")
		local function read(path)
			return fs.readFile(path)
		end
		local ui = read("src/StarterPlayer/StarterPlayerScripts/BasesUI.luau")
		t.ok(string.find(ui, 'Net.Remote("BaseAction"):FireServer(action, index)', 1, true), "intents only")
		t.ok(string.find(ui, "BaseLogic.ConfirmText", 1, true), "every change asks first")
		t.ok(string.find(ui, "MenuPad.Open(pick, p)", 1, true), "the pad lands on a button")
		t.ok(string.find(ui, "math.max(44, UITheme.Size.Tap)", 1, true), "buttons are tap sized")
		local dialogue = read("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		t.ok(string.find(dialogue, 'FireServer("hank", which, hank)', 1, true), "Hank's Yes / No go to him")
		local service = read("src/ServerScriptService/DialogueService.luau")
		t.ok(string.find(service, 'action == "hank"', 1, true))
		t.ok(string.find(service, "DialogueService.HankPick", 1, true))
		local plot = read("src/ServerScriptService/PlotService.luau")
		t.ok(string.find(plot, 'RateLimiter.Allow(player, "BaseAction")', 1, true), "rate limited")
		t.ok(string.find(plot, "BaseLogic.Check(profile, action, index, ctx)", 1, true), "validated on the server")
		t.ok(
			string.find(plot, "pcall(PlotService.Hooks.clearPads, leaving.plot)", 1, true),
			"no orphan pad models on leave"
		)
		local vehicles = read("src/ServerScriptService/VehicleService.luau")
		t.ok(string.find(vehicles, "function VehicleService.ClearPads", 1, true))
		local net = read("src/ReplicatedStorage/Shared/Net.luau")
		for _, name in ipairs({ "BaseAction", "BaseState", "PlotShown" }) do
			t.ok(string.find(net, '"' .. name .. '"', 1, true), name)
		end
		local layers = t.shared("PickerSequence")
		t.eq(layers.Order[2], "slot")
	end)
end
