--!nocheck
-- Nothing visual follows the player. Connor: remove any effect that trails
-- the player's body; the Lux Axe's effect belongs to the axe (blade/handle)
-- and only while it is held.
--   * Runtime: with LuxFX running against a fake character, no Trail, Beam or
--     ParticleEmitter sits under the character outside the held Lux tool, no
--     Lux effect exists when Lux is not the equipped tool (backpack, other
--     tool, dropped), and the sparkle sits on the blade attachment.
--   * Source: no script parents an emitter, trail or beam it just created to
--     the character, its root part or the camera.
-- The checkers are proven with deliberate failing controls.
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance
	local fs = require("@lune/fs")
	local GameConfig = t.shared("GameConfig")

	-- Lune's ParticleEmitter has no Emit, and TreeFX.spec registers one on the
	-- shared class registry (a second registration throws). So this spec
	-- registers nothing: the fake quality tier is "low", where the sparkle
	-- never emits, and the effects are checked by where they sit, not by Emit.

	local FX_CLASSES = { "ParticleEmitter", "Trail", "Beam" }

	local function isFx(inst)
		for _, class in ipairs(FX_CLASSES) do
			if inst:IsA(class) then
				return true
			end
		end
		return false
	end

	local function insideLuxTool(inst, tool)
		return tool ~= nil and inst:IsDescendantOf(tool)
	end

	-- Returns the effects under `character` that are not on the held Lux tool.
	local function strays(character, heldLux)
		local out = {}
		for _, d in ipairs(character:GetDescendants()) do
			if isFx(d) and not insideLuxTool(d, heldLux) then
				table.insert(out, d:GetFullName())
			end
		end
		return out
	end

	local function luxFxIn(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if isFx(d) and string.sub(d.Name, 1, 3) == "Lux" then
				table.insert(out, d)
			end
		end
		return out
	end

	-- The rule, as an assertion. `equipped` is the Lux tool the player holds, or nil.
	local function assertClean(workspaceRoot, character, equipped)
		local bad = strays(character, equipped)
		if #bad > 0 then
			error("effect follows the player: " .. table.concat(bad, ", "), 2)
		end
		for _, fx in ipairs(luxFxIn(workspaceRoot)) do
			if
				equipped == nil
				or not fx:IsDescendantOf(equipped)
				or fx:FindFirstAncestorOfClass("Tool") ~= equipped
			then
				error("Lux effect exists off the equipped Lux tool: " .. fx:GetFullName(), 2)
			end
		end
	end

	local function makeTool(name, axeId)
		local tool = Instance.new("Tool")
		tool.Name = name
		tool:SetAttribute("AxeId", axeId)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = roblox.Vector3.new(0.3, 3.5, 0.4)
		handle.Parent = tool
		return tool
	end

	local function world(owns)
		local game = Instance.new("DataModel")
		local ws = game:GetService("Workspace")
		local character = Instance.new("Model")
		character.Name = "Character"
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = character
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Parent = character
		character.Parent = ws
		local backpack = Instance.new("Folder")
		backpack.Name = "Backpack"
		backpack.Parent = ws
		local attrs = { Pass_LuxAxe = owns }
		local player = { UserId = 7 }
		function player:GetAttribute(name)
			return attrs[name]
		end
		player.Character = character
		local swing = { clip = nil }
		local loader = t.loader({
			services = {
				Players = {
					LocalPlayer = player,
					GetPlayers = function()
						return { player }
					end,
				},
				RunService = { Heartbeat = { Connect = function() end } },
			},
			mocks = {
				Net = {
					Remote = function()
						return { OnClientEvent = { Connect = function() end } }
					end,
				},
				Quality = {
					Tier = function()
						return "low"
					end,
					Budget = function()
						return { Tier = "low", CosmeticHz = 60 }
					end,
				},
				SwingPose = {
					ClipOf = function()
						return swing.clip
					end,
				},
			},
		})
		local LuxFX = loader:load("StarterPlayer/StarterPlayerScripts/LuxFX")
		return {
			ws = ws,
			character = character,
			backpack = backpack,
			root = root,
			LuxFX = LuxFX,
			swing = swing,
			player = player,
		}
	end

	local function frames(w, n)
		for _ = 1, n do
			w.LuxFX.Step(1 / 30)
		end
	end

	t.test("walking with no Lux: nothing but the body, no effect anywhere", function()
		local w = world(false)
		local rusty = makeTool("RustyAxe", "RustyAxe")
		rusty.Parent = w.character
		frames(w, 120)
		assertClean(w.ws, w.character, nil)
		t.eq(#luxFxIn(w.ws), 0)
	end)

	t.test("a player who owns Lux but has it in the backpack has no Lux effect", function()
		local w = world(true)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		lux.Parent = w.backpack
		frames(w, 120)
		assertClean(w.ws, w.character, nil)
		t.eq(#luxFxIn(w.ws), 0)
	end)

	t.test("equipped Lux: every effect is on the axe, the sparkle on the blade attachment", function()
		local w = world(true)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		lux.Parent = w.character
		frames(w, 120)
		assertClean(w.ws, w.character, lux)
		local found = luxFxIn(w.ws)
		t.eq(#found, 3, "trail, sparkle, burst")
		local handle = lux:FindFirstChild("Handle")
		for _, fx in ipairs(found) do
			t.ok(fx:IsDescendantOf(handle), fx.Name .. " is under the Handle")
			t.ok(fx.Parent == handle or fx.Parent:IsA("Attachment"), fx.Name .. " sits on the handle or an attachment")
		end
		local sparkle = handle:FindFirstChild("LuxSparkle", true)
		t.eq(sparkle.Parent.Name, "LuxBurst", "sparkle on the blade, not the grip")
		t.eq(handle:FindFirstChild("LuxTrail").Enabled, false, "trail is off while only held")
	end)

	t.test("trail runs only during the swing window", function()
		local w = world(true)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		lux.Parent = w.character
		local trail
		frames(w, 2)
		trail = lux.Handle:FindFirstChild("LuxTrail")
		w.swing.clip = 0.0
		frames(w, 1)
		t.eq(trail.Enabled, false, "wind-up")
		w.swing.clip = t.shared("SwingLogic").Impact
		frames(w, 1)
		t.eq(trail.Enabled, true, "impact")
		w.swing.clip = nil
		frames(w, 1)
		t.eq(trail.Enabled, false, "swing over")
	end)

	t.test("unequipping Lux removes every Lux effect", function()
		local w = world(true)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		lux.Parent = w.character
		frames(w, 30)
		t.eq(#luxFxIn(w.ws), 3)
		lux.Parent = w.backpack
		frames(w, 1)
		t.eq(#luxFxIn(w.ws), 0, "gone from the backpacked tool")
		assertClean(w.ws, w.character, nil)
		lux.Parent = w.character
		frames(w, 1)
		t.eq(#luxFxIn(w.ws), 3, "and back on re-equip")
		lux.Parent = nil
		frames(w, 1)
		t.eq(#luxFxIn(lux), 0, "gone when the tool is gone")
	end)

	t.test("switching from Lux to another axe leaves no effect on the body or the new axe", function()
		local w = world(true)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		local rusty = makeTool("RustyAxe", "RustyAxe")
		lux.Parent = w.character
		frames(w, 10)
		lux.Parent = w.backpack
		rusty.Parent = w.character
		frames(w, 10)
		assertClean(w.ws, w.character, nil)
		t.eq(#luxFxIn(w.ws), 0)
	end)

	-- Deliberate failing controls: the checker must catch each of these.
	t.test("control: an aura emitter on the root part is caught", function()
		local w = world(false)
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "Aura"
		aura.Parent = w.root
		t.fails(function()
			assertClean(w.ws, w.character, nil)
		end, "effect follows the player")
	end)

	t.test("control: a trail or beam on the torso is caught, even with Lux held", function()
		local w = world(true)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		lux.Parent = w.character
		frames(w, 5)
		local trail = Instance.new("Trail")
		trail.Parent = w.character.UpperTorso
		t.fails(function()
			assertClean(w.ws, w.character, lux)
		end, "effect follows the player")
		trail:Destroy()
		local beam = Instance.new("Beam")
		beam.Parent = w.character
		t.fails(function()
			assertClean(w.ws, w.character, lux)
		end, "effect follows the player")
	end)

	t.test("control: a non-Lux axe carrying a trail is caught when Lux is not held", function()
		local w = world(false)
		local rusty = makeTool("RustyAxe", "RustyAxe")
		rusty.Parent = w.character
		local trail = Instance.new("Trail")
		trail.Parent = rusty.Handle
		t.fails(function()
			assertClean(w.ws, w.character, nil)
		end, "effect follows the player")
	end)

	t.test("control: Lux effects left on a backpacked tool are caught", function()
		local w = world(false)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		lux.Parent = w.backpack
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "LuxSparkle"
		sparkle.Parent = lux.Handle
		t.fails(function()
			assertClean(w.ws, w.character, nil)
		end, "Lux effect exists off the equipped Lux tool")
	end)

	t.test("control: Lux effects parented to the body, not the tool, are caught", function()
		local w = world(true)
		local lux = makeTool("LuxAxe", GameConfig.LuxAxeId)
		lux.Parent = w.character
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "LuxSparkle"
		sparkle.Parent = w.root
		t.fails(function()
			assertClean(w.ws, w.character, lux)
		end)
	end)

	---------------------------------------------------------------------------
	-- Source scan: no effect created in code is parented to the character,
	-- its root part or the camera.
	---------------------------------------------------------------------------

	local BODY = {
		"character",
		"char",
		"hrp",
		"humanoidrootpart",
		"rootpart",
		"humanoid",
		"camera",
		"workspace.currentcamera",
		"player.character",
		"localplayer.character",
	}

	-- Names assigned `Instance.new("ParticleEmitter" | "Trail" | "Beam" | ...)`
	-- and then parented straight to a body expression. Returns the offending lines.
	local function bodyParented(text)
		local made = {}
		for name, class in string.gmatch(text, 'local%s+([%w_]+)%s*=%s*Instance%.new%("([%w]+)"%)') do
			if class == "ParticleEmitter" or class == "Trail" or class == "Beam" or class == "Attachment" then
				made[name] = class
			end
		end
		local bad = {}
		for name, target in string.gmatch(text, "([%w_]+)%.Parent%s*=%s*([%w_%.]+)") do
			if made[name] then
				local low = string.lower(target)
				for _, body in ipairs(BODY) do
					if low == body or string.sub(low, -#body - 1) == "." .. body then
						table.insert(bad, name .. ".Parent = " .. target)
						break
					end
				end
			end
		end
		return bad
	end

	local function luauFiles(dir, out)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				if entry ~= "Vendor" then
					luauFiles(path, out)
				end
			elseif string.sub(entry, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end

	t.test("source: no script parents an effect it created to the character, root part or camera", function()
		local offenders = {}
		local files = luauFiles("src", {})
		t.ok(#files > 100, "scanned the source tree")
		for _, path in ipairs(files) do
			for _, line in ipairs(bodyParented(fs.readFile(path))) do
				table.insert(offenders, path .. ": " .. line)
			end
		end
		t.eq(#offenders, 0, table.concat(offenders, "\n"))
	end)

	t.test("control: the source scan catches a follow aura", function()
		local aura = [[
local e = Instance.new("ParticleEmitter")
e.Parent = hrp
local tr = Instance.new("Trail")
tr.Parent = character.HumanoidRootPart
local b = Instance.new("Beam")
b.Parent = workspace.CurrentCamera
local ok = Instance.new("ParticleEmitter")
ok.Parent = handle
]]
		local bad = bodyParented(aura)
		t.eq(#bad, 3, "hrp, the root part path and the camera are body targets; handle is not")
		t.eq(#bodyParented('local e = Instance.new("ParticleEmitter")\ne.Parent = player.Character'), 1)
		t.eq(#bodyParented('local e = Instance.new("ParticleEmitter")\ne.Parent = anchor'), 0)
	end)
end
