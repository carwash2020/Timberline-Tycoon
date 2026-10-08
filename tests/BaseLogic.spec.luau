--!nocheck
-- BaseLogic: unloading your base (LT2 style) and loading it back. Pure rules:
-- when an unload is allowed, which button the SAVES panel shows.
return function(t)
	local Base = t.shared("BaseLogic")
	local Util = t.shared("Util")
	local Schema = t.loader():server("ProfileSchema")

	local function profileWith(placed, pads)
		local data = Util.deepCopy(Schema.Template)
		data.plot =
			{ claimed = true, tier = 2, placed = placed or {}, squares = {}, wires = {}, switches = {}, pads = pads }
		data.baseCooldownUntil = 0
		return data
	end

	local function ctx(over)
		local c = { now = 1000, hasPad = true, busy = false, looseWood = 0 }
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end

	t.test("unload: the order of refusals, and what each says", function()
		local p = profileWith({ { uid = "a" } })
		t.eq({ Base.CheckUnload(p, ctx()) }, { true, nil })
		t.eq({ Base.CheckUnload(p, ctx({ busy = true })) }, { false, Base.Reasons.busy })
		p.plot.claimed = false
		t.eq({ Base.CheckUnload(p, ctx()) }, { false, Base.Reasons.noPlot })
		p.plot.claimed = true
		t.eq({ Base.CheckUnload(p, ctx({ hasPad = false })) }, { false, Base.Reasons.nopad })
		p.baseCooldownUntil = 1030
		local ok, why = Base.CheckUnload(p, ctx())
		t.eq(ok, false)
		t.eq(why, "Give it 30 more seconds before unloading again.")
		t.eq({ Base.CheckUnload(p, ctx({ now = 1030 })) }, { true, nil }, "the cooldown ends exactly on time")
		p.baseCooldownUntil = 0
		t.eq({ Base.CheckUnload(p, ctx({ looseWood = 2 })) }, { false, Base.Reasons.wood })
		t.eq({ Base.CheckUnload(nil, ctx()) }, { false, "bad" })
	end)

	t.test("an empty base can be unloaded too: it is still a plot you own", function()
		local p = profileWith({})
		p.plot.tier = 1
		t.eq({ Base.CheckUnload(p, ctx()) }, { true, nil })
	end)

	t.test("load: only for a save that owns a plot and has no pad", function()
		local p = profileWith({})
		t.eq({ Base.CanLoad(p, false) }, { true, nil })
		t.eq({ Base.CanLoad(p, true) }, { false, "bad" })
		p.plot.claimed = false
		t.eq({ Base.CanLoad(p, false) }, { false, Base.Reasons.noPlot })
		t.eq({ Base.CanLoad(nil, false) }, { false, Base.Reasons.noPlot })
	end)

	t.test("the cooldown is stamped by Stamp and is the configured length", function()
		local p = profileWith({})
		Base.Stamp(p, 100)
		t.eq(p.baseCooldownUntil, 100 + t.shared("GameConfig").BaseCooldownSec)
		t.eq(Base.Cooldown, t.shared("GameConfig").BaseCooldownSec)
	end)

	t.test(
		"the SAVES panel's base button: unload on a pad, load while it waits, nothing while choosing a save",
		function()
			t.eq(Base.ButtonFor(true, true, false), "unload")
			t.eq(Base.ButtonFor(false, true, false), "load")
			t.eq(Base.ButtonFor(false, false, false), nil, "no plot, nothing to load")
			t.eq(Base.ButtonFor(true, true, true), nil, "the save picker is up")
			t.eq(Base.ButtonText("unload"), "UNLOAD BASE")
			t.eq(Base.ButtonText("load"), "LOAD BASE")
		end
	)

	t.test("uids: each piece and pad once, sorted", function()
		local p = profileWith({ { uid = "b" }, { uid = "a" } }, { { uid = "pad1" } })
		t.eq(Base.Uids(p), { "a", "b", "pad1" })
	end)

	t.test("the shelf of crated bases is gone", function()
		t.eq(Base.Swap, nil)
		t.eq(Base.Cap, nil)
		t.eq(t.shared("GameConfig").BaseShelfCap, nil)
	end)

	t.test(
		"wiring: the SAVES panel button, the remote and the pad clean-up are in place; Old Hank is untouched",
		function()
			local fs = require("@lune/fs")
			local function read(path)
				return fs.readFile(path)
			end
			local ui = read("src/StarterPlayer/StarterPlayerScripts/SaveSlotUI.luau")
			t.ok(string.find(ui, 'Net.Remote("BaseAction"):FireServer("unload")', 1, true))
			t.ok(string.find(ui, 'Net.Remote("BaseAction"):FireServer("load")', 1, true))
			t.ok(string.find(ui, 'showConfirm("unload"', 1, true), "a confirm card first")
			t.ok(string.find(ui, "BaseLogic.ButtonFor", 1, true))
			t.ok(string.find(ui, "math.max(48, UITheme.Size.Tap)", 1, true), "tap sized")
			local plot = read("src/ServerScriptService/PlotService.luau")
			t.ok(string.find(plot, 'RateLimiter.Allow(player, "BaseAction")', 1, true), "rate limited")
			t.ok(string.find(plot, "BaseLogic.CheckUnload(profile, ctx)", 1, true), "validated on the server")
			t.ok(
				string.find(plot, "pcall(PlotService.Hooks.clearPads, leaving.plot)", 1, true),
				"no orphan pad models on leave"
			)
			t.eq(string.find(plot, "HankPick", 1, true), nil, "Old Hank has no bases offer")
			t.eq(string.find(read("src/ServerScriptService/DialogueService.luau"), "hank", 1, true), nil)
			t.eq(string.find(read("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau"), "hankOffer", 1, true), nil)
			t.ok(
				string.find(
					read("src/ServerScriptService/VehicleService.luau"),
					"function VehicleService.ClearPads",
					1,
					true
				)
			)
			local net = read("src/ReplicatedStorage/Shared/Net.luau")
			for _, name in ipairs({ "BaseAction", "PlotShown" }) do
				t.ok(string.find(net, '"' .. name .. '"', 1, true), name)
			end
			t.eq(string.find(net, "BaseState", 1, true), nil)
		end
	)
end
