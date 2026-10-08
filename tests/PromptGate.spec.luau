--!nocheck
-- PromptGate / PromptSwitch: world prompts (Talk, Buy, Open, Pick up) are on
-- exactly when nobody holds them off. Reproduces the stuck switch that made
-- every Talk and Buy prompt dead after PRs #107-#111: the dialogue box and a
-- held shop box each saved "what Enabled was" and put it back, so when they
-- overlapped the saved value was "off" and nothing turned prompts on again.
return function(t)
	local fs = require("@lune/fs")
	local Gate = t.shared("PromptGate")

	-- The old way, exactly as DialogueUI / DragController / WireTool /
	-- BlueprintPlacer did it: each saves Enabled, sets it off, restores it.
	local function legacy()
		local world = { enabled = true }
		local saved = {}
		local api = {}
		function api.world()
			return world.enabled
		end
		-- DragController.hidePrompts / WireTool / BlueprintPlacer
		function api.saveAndOff(who)
			if saved[who] == nil then
				saved[who] = world.enabled
			end
			world.enabled = false
		end
		function api.restore(who)
			if saved[who] ~= nil then
				world.enabled = saved[who]
				saved[who] = nil
			end
		end
		-- DialogueUI: off on open, plain "on" a moment after it closes.
		function api.dialogueOpen()
			world.enabled = false
		end
		function api.dialogueClosedAfterDelay()
			world.enabled = true
		end
		return api
	end

	local function newGate()
		local world = { enabled = true, sets = 0 }
		local gate = Gate.New(function(on)
			world.enabled = on
			world.sets += 1
		end)
		return gate, world
	end

	t.test("the old save-and-restore leaves prompts off for good (the regression)", function()
		-- A dialogue box is up; a box is grabbed under it; the dialogue closes
		-- and prompts come back; the box is let go: the drag puts back "off".
		local old = legacy()
		old.dialogueOpen()
		old.saveAndOff("drag") -- saved: false
		old.dialogueClosedAfterDelay()
		t.eq(old.world(), true, "the dialogue's own re-enable")
		old.restore("drag")
		t.eq(old.world(), false, "and the drag's restore turns them off again: Talk and Buy are dead")
	end)

	t.test("the same sequence through the gate leaves prompts on", function()
		local gate, world = newGate()
		Gate.Hold(gate, "dialogue", 1)
		Gate.Hold(gate, "drag", 2)
		t.eq(world.enabled, false)
		Gate.Release(gate, "dialogue")
		t.eq(world.enabled, false, "still held by the drag")
		Gate.Release(gate, "drag")
		t.eq(world.enabled, true, "nobody holds them: on")
	end)

	t.test("every order of holds and releases ends with prompts on once all have let go", function()
		local reasons = { "dialogue", "drag", "placer", "wire" }
		local steps = {}
		for _, r in ipairs(reasons) do
			table.insert(steps, { true, r })
			table.insert(steps, { false, r })
		end
		local checked = 0
		-- Every sequence of 4 steps over four reasons (8 choices a step).
		local function walk(held, depth)
			local gate, world = newGate()
			for k in pairs(held) do
				Gate.Hold(gate, k, 1)
			end
			t.eq(world.enabled, next(held) == nil, "the switch always matches who holds")
			t.eq(Gate.Open(gate), next(held) == nil)
			if depth == 0 then
				checked += 1
				for _, r in ipairs(reasons) do
					Gate.Release(gate, r)
				end
				t.eq(world.enabled, true, "everyone let go: prompts are on")
				return
			end
			for _, step in ipairs(steps) do
				local copy = {}
				for k, v in pairs(held) do
					copy[k] = v
				end
				if step[1] then
					copy[step[2]] = true
				else
					copy[step[2]] = nil
				end
				walk(copy, depth - 1)
			end
		end
		walk({}, 4)
		t.ok(checked > 1000, "a wide sweep: " .. checked)
	end)

	t.test("a holder that ends twice, or never began, cannot switch anyone else's hold off", function()
		local gate, world = newGate()
		Gate.Release(gate, "placer") -- never began
		t.eq(world.enabled, true)
		Gate.Hold(gate, "dialogue", 1)
		Gate.Release(gate, "drag") -- someone else's
		t.eq(world.enabled, false, "the dialogue still holds")
		Gate.Hold(gate, "dialogue", 5) -- twice is one hold
		Gate.Release(gate, "dialogue")
		Gate.Release(gate, "dialogue")
		t.eq(world.enabled, true)
		t.eq(world.sets, 2, "one off, one on: nothing flickers")
	end)

	t.test("a switch moved by something else is put right, and a long hold is named", function()
		local gate, world = newGate()
		Gate.Hold(gate, "drag", 10)
		world.enabled = true -- something else turned them on
		t.eq(Gate.Heal(gate, true), true)
		t.eq(world.enabled, false)
		t.eq(Gate.Heal(gate, false), false, "already right")
		t.eq(Gate.Stale(gate, 12, 60), {}, "two seconds is nothing")
		t.eq(Gate.Stale(gate, 100, 60), { "drag (90s)" })
		Gate.Release(gate, "drag")
		world.enabled = false -- stuck off with nobody holding
		t.eq(Gate.Heal(gate, false), true)
		t.eq(world.enabled, true, "nobody holds them: back on")
	end)

	t.test("PromptSwitch drives the engine's switch through the gate", function()
		local service = { Enabled = true }
		local loader = t.loader({
			services = { ProximityPromptService = service },
			globals = {
				task = {
					spawn = function() end,
					wait = function() end,
				},
			},
		})
		local Switch = loader:load("StarterPlayer/StarterPlayerScripts/PromptSwitch")
		Switch.Hold("dialogue")
		Switch.Hold("drag")
		t.eq(service.Enabled, false)
		t.eq(Switch.Reasons(), { "dialogue", "drag" })
		Switch.Release("dialogue")
		t.eq(service.Enabled, false)
		Switch.Release("drag")
		t.eq(service.Enabled, true)
		t.eq(Switch.Reasons(), {})
	end)

	t.test("only PromptSwitch touches ProximityPromptService.Enabled in the client scripts", function()
		local dir = "src/StarterPlayer/StarterPlayerScripts"
		local offenders = {}
		for _, name in ipairs(fs.readDir(dir)) do
			if string.sub(name, -5) == "luau" and name ~= "PromptSwitch.luau" then
				local src = fs.readFile(dir .. "/" .. name)
				if string.find(src, "ProximityPromptService.Enabled", 1, true) then
					table.insert(offenders, name)
				end
			end
		end
		t.eq(offenders, {}, "save-and-restore of the global switch is how prompts got stuck off")
		for _, name in ipairs({ "DialogueUI", "DragController", "BlueprintPlacer", "WireTool" }) do
			local src = fs.readFile(dir .. "/" .. name .. ".luau")
			t.ok(string.find(src, "PromptSwitch.Hold", 1, true), name .. " holds")
			t.ok(string.find(src, "PromptSwitch.Release(", 1, true), name .. " releases")
		end
	end)

	t.test("DialogueUI releases prompts before anything that can throw; drop releases first", function()
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		local from = string.find(ui, "local function hide(why", 1, true)
		local hide = string.sub(ui, from, string.find(ui, "local function choose", 1, true))
		local release = string.find(hide, 'PromptSwitch.Release("dialogue")', 1, true)
		local restore = string.find(hide, "GamepadNav.Restore", 1, true)
		t.ok(release and restore and release < restore, "the release is scheduled before the gamepad restore")
		t.ok(string.find(hide, "(pcall :: any)(function()", 1, true), "and the restore cannot abort the hide")
		local drag = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DragController.luau")
		local dropFrom = string.find(drag, "local function drop(tell", 1, true)
		local drop = string.sub(drag, dropFrom, string.find(drag, "-- What the pull is sized by", 1, true))
		t.ok(
			string.find(drop, "hidePrompts(false)", 1, true) < string.find(drop, "ghostBeds(false)", 1, true),
			"prompts back before the rest of the clean-up"
		)
		t.ok(string.find(drag, '"[Drag] could not start the hold', 1, true), "a failed start ends the hold")
	end)

	t.test("a Picking left set cannot close the box unless the picker is on screen", function()
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		t.ok(string.find(ui, 'player:GetAttribute("Picking") == true and pickerShowing()', 1, true))
	end)
end
