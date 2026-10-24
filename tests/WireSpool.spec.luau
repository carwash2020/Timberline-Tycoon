--!nocheck
-- WireSpool (T420): the wire is its own tool, not part of the hammer. A spool Tool is handed to
-- every player with the Hammer; its look is the uploaded spool model (five MeshParts, loaded once at
-- boot by WireSpoolMeshes), never parts; the Hammer's bar, its picker and its sheet carry no wiring.
return function(t)
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame
	local fs = require("@lune/fs")
	local WireArt = t.load("ReplicatedStorage/Shared/Art/WireArt")

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local IDS = {
		Band = 80844007658561,
		Coil = 94852981021651,
		FlangeLeft = 136255398985840,
		FlangeRight = 105703432161770,
		Hub = 131695301504197,
	}
	local SIZES = {
		Band = Vector3.new(0.18, 0.98, 0.98),
		Coil = Vector3.new(0.944, 1.315, 1.07),
		FlangeLeft = Vector3.new(0.14, 1.5, 1.5),
		FlangeRight = Vector3.new(0.14, 1.5, 1.5),
		Hub = Vector3.new(0.88, 0.6, 0.6),
	}
	local MODEL_ID = 139086937634351

	-- The uploaded model as the engine hands it over: five MeshParts, each with its MeshId and an
	-- InitialSize (and Size) 100 times the real size (centimetres).
	local function fakeModel(scale)
		local model = t.roblox.Instance.new("Model")
		for name, id in pairs(IDS) do
			local mesh = t.roblox.Instance.new("MeshPart")
			mesh.Name = name
			mesh.MeshId = "rbxassetid://" .. id
			mesh.InitialSize = SIZES[name] * (scale or 100)
			mesh.Size = SIZES[name] * (scale or 100)
			mesh.Parent = model
		end
		return model
	end

	-- The server's loader with LoadAsset stubbed: returns it, with the ids it was asked for.
	local function loaderWith(load)
		local loader = t.loader({
			globals = { task = {
				wait = function() end,
				spawn = function(f, ...)
					f(...)
				end,
			} },
		})
		local Meshes = loader:server("WireSpoolMeshes")
		Meshes.Wait = function() end
		local asked = {}
		Meshes.LoadModel = function(id)
			table.insert(asked, id)
			return load(id)
		end
		return Meshes, asked, loader
	end

	local function loadedTemplates()
		local Meshes = loaderWith(function()
			return fakeModel()
		end)
		Meshes.Load()
		return Meshes.Get(), Meshes
	end

	local function boxOf(model)
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in ipairs(parts(model)) do
			if p:IsA("MeshPart") then
				local h = p.Size / 2
				local c = p.CFrame.Position
				lo = Vector3.new(math.min(lo.X, c.X - h.X), math.min(lo.Y, c.Y - h.Y), math.min(lo.Z, c.Z - h.Z))
				hi = Vector3.new(math.max(hi.X, c.X + h.X), math.max(hi.Y, c.Y + h.Y), math.max(hi.Z, c.Z + h.Z))
			end
		end
		return hi - lo
	end

	t.test("the config is ONE table: the model id and the five MeshParts by name, and nowhere else in src", function()
		local C = WireArt.Config
		t.eq(C.ModelId, MODEL_ID)
		t.eq(#C.Pieces, 5)
		for _, piece in ipairs(C.Pieces) do
			t.eq(piece.meshId, IDS[piece.name], piece.name .. " mesh id")
			t.ok((piece.size - SIZES[piece.name]).Magnitude < 1e-6, piece.name .. " size")
		end
		t.eq(C.SizeDivisor, 100)
		-- No other file holds any of the six ids.
		local function walk(dir)
			for _, name in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					walk(path)
				elseif string.match(name, "%.luau$") and path ~= "src/ReplicatedStorage/Shared/Art/WireArt.luau" then
					local text = fs.readFile(path)
					for _, id in pairs(IDS) do
						t.eq(string.find(text, tostring(id), 1, true), nil, path .. " holds " .. id)
					end
					t.eq(string.find(text, tostring(MODEL_ID), 1, true), nil, path .. " holds the model id")
				end
			end
		end
		walk("src")
	end)

	t.test("the server loads the model ONCE, with the listed model id, and sets Size = InitialSize / 100", function()
		local Meshes, asked = loaderWith(function()
			return fakeModel(100)
		end)
		Meshes.Load()
		Meshes.Load() -- a second call does nothing
		t.eq(asked, { MODEL_ID }, "one LoadAsset, for the model")
		t.eq(Meshes.State(), "ready")
		local got = Meshes.Get()
		for name, size in pairs(SIZES) do
			t.ok(got[name] ~= nil and got[name]:IsA("MeshPart"), name .. " template")
			t.ok((got[name].Size - size).Magnitude < 1e-4, name .. " is " .. tostring(got[name].Size))
		end
	end)

	t.test("a load that fails is retried, then the spool is not shown and nothing is built from parts", function()
		local Meshes, asked = loaderWith(function()
			error("HTTP 403: not approved for this experience")
		end)
		local waits = {}
		Meshes.Wait = function(s)
			table.insert(waits, s)
		end
		local answered = {}
		Meshes.OnReady(function(templates)
			table.insert(answered, templates == nil)
		end)
		t.eq(#asked, Meshes.Attempts, "retried to the limit")
		t.eq(#waits, Meshes.Attempts - 1, "with a wait between tries")
		t.ok(waits[2] > waits[1], "backing off")
		t.eq(Meshes.State(), "failed")
		t.eq(Meshes.Get(), nil)
		t.eq(answered, { true }, "waiting spools are told it failed")
		-- A flaky load: the second try works.
		local tries = 0
		local flaky = loaderWith(function()
			tries += 1
			if tries == 1 then
				error("timeout")
			end
			return fakeModel()
		end)
		flaky.Load()
		t.eq(flaky.State(), "ready", "the retry got it")
		-- No model came back with the five parts: failed, and not retried (it will not change).
		local wrong, askedWrong = loaderWith(function()
			return t.roblox.Instance.new("Model")
		end)
		wrong.Load()
		t.eq(wrong.State(), "failed")
		t.eq(#askedWrong, 1)
	end)

	t.test("five MeshParts with the listed names and MeshIds, welded to a Handle, each non-colliding", function()
		local templates = loadedTemplates()
		local model = WireArt.Build(templates)
		local handle = model.PrimaryPart
		t.ok(handle ~= nil and handle.Name == "Handle")
		local seen = 0
		for name, id in pairs(IDS) do
			local mesh = model:FindFirstChild(name)
			t.ok(mesh ~= nil and mesh:IsA("MeshPart"), name .. " is a MeshPart")
			t.eq(mesh.MeshId, "rbxassetid://" .. id, name .. " MeshId")
			t.eq(mesh.CanCollide, false, name .. " does not collide")
			local weld = mesh:FindFirstChildOfClass("Weld")
			t.ok(weld ~= nil and weld.Part0 == handle and weld.Part1 == mesh, name .. " is welded")
			seen += 1
		end
		t.eq(seen, 5)
		local meshParts = 0
		for _, p in ipairs(parts(model)) do
			if p:IsA("MeshPart") then
				meshParts += 1
			end
		end
		t.eq(meshParts, 5, "exactly five MeshParts")
		t.eq(#parts(model), 7, "the five, the Handle and the SpoolCollider: nothing else")
	end)

	t.test("colours and materials: flanges and hub TimberBrown Wood, coil #C47A42 Metal, band Brass Metal", function()
		local model = WireArt.Build((loadedTemplates()))
		local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
		local Enum = t.roblox.Enum
		for _, name in ipairs({ "FlangeLeft", "FlangeRight", "Hub" }) do
			t.eq(model[name].Color:ToHex(), "7A5230", name)
			t.eq(model[name].Material, Enum.Material.Wood, name)
		end
		t.eq(model.Coil.Color:ToHex(), "C47A42")
		t.eq(model.Coil.Material, Enum.Material.Metal)
		t.eq(model.Band.Color, Palette.Brass)
		t.eq(model.Band.Color:ToHex(), "C9A24A")
		t.eq(model.Band.Material, Enum.Material.Metal)
	end)

	t.test("the assembled bounding box is 1.0 (X) x 1.5 x 1.5 within 0.05 (a wrong /100 scale fails)", function()
		local box = boxOf(WireArt.Build((loadedTemplates())))
		t.ok(math.abs(box.X - 1.0) <= 0.05, "X " .. box.X)
		t.ok(math.abs(box.Y - 1.5) <= 0.05, "Y " .. box.Y)
		t.ok(math.abs(box.Z - 1.5) <= 0.05, "Z " .. box.Z)
		-- The control: a spool scaled by the wrong divisor is far outside it.
		local wrong = loaderWith(function()
			return fakeModel(10) -- the engine had reported 10x: dividing by 100 leaves it 10x too small
		end)
		wrong.Load()
		local tooSmall = boxOf(WireArt.Build(wrong.Get()))
		t.ok(
			math.abs(tooSmall.Y - 1.5) > 0.05,
			"a wrongly scaled spool is " .. tooSmall.Y .. " tall and fails the check"
		)
	end)

	t.test(
		"SpoolCollider: invisible, 1.0 x 1.5 x 1.5, at the spool's middle, with its reason, and the world lint passes it",
		function()
			local Geometry = t.load("ReplicatedStorage/Shared/Lint/Geometry")
			local model = WireArt.Build((loadedTemplates()))
			local collider = model:FindFirstChild("SpoolCollider")
			t.ok(collider ~= nil, "SpoolCollider")
			t.eq(collider.Transparency, 1)
			t.ok((collider.Size - Vector3.new(1.0, 1.5, 1.5)).Magnitude < 1e-6, "its size")
			t.ok(collider.CFrame.Position.Magnitude < 1e-6, "at the middle")
			t.eq(collider:GetAttribute("InvisibleBlocker"), true)
			local reason = collider:GetAttribute("InvisibleBlockerReason")
			t.ok(type(reason) == "string" and #reason > 10, "a stated reason")
			local weld = collider:FindFirstChildOfClass("Weld")
			t.ok(weld ~= nil and weld.Part0 == model.PrimaryPart, "welded")
			-- The world collision lint (rules 2b and 2c), with an EMPTY allowlist.
			local root = t.roblox.Instance.new("Folder")
			root.Name = "TimberlineMap"
			model.Parent = root
			local result = Geometry.Run(root, {}, nil, { skipStale = true })
			t.eq(result.failures, {}, "the lint passes")
			-- The control: the same collider without its reason is a rule 2c hit.
			collider:SetAttribute("InvisibleBlockerReason", nil)
			t.ok(#Geometry.Run(root, {}, nil, { skipStale = true }).failures > 0, "without the reason it fails 2c")
			-- And geometry_allow.json gains nothing for it.
			local allow = require("@lune/serde").decode("json", fs.readFile("tests/geometry_allow.json"))
			for _, entry in ipairs(allow) do
				t.eq(string.find(entry.a .. entry.b, "Spool", 1, true), nil, "no spool entry in the allowlist")
			end
		end
	)

	t.test("held in a Tool nothing collides and nothing is anchored", function()
		local model = WireArt.Held((loadedTemplates()))
		for _, p in ipairs(parts(model)) do
			t.ok(not p.Anchored and not p.CanCollide and p.Massless, p.Name .. " is inert in hand")
		end
		t.ok(WireArt.Grip() ~= nil)
	end)

	t.test(
		"a Tool handed over before the meshes arrive is dressed when they do; one handed over after is dressed at once",
		function()
			local Meshes = loaderWith(function()
				return fakeModel()
			end)
			local tool = t.roblox.Instance.new("Tool")
			local art = WireArt.Held()
			for _, child in ipairs(art:GetChildren()) do
				child.Parent = tool
			end
			t.eq(#parts(tool), 1, "the Handle alone")
			Meshes.Load()
			t.ok(WireArt.Dress(tool, Meshes.Get()))
			t.eq(#parts(tool), 7, "dressed")
			for name in pairs(IDS) do
				local mesh = tool:FindFirstChild(name)
				t.ok(mesh ~= nil, name)
				local weld = mesh:FindFirstChildOfClass("Weld")
				t.eq(weld.Part0, tool.Handle, name .. " is welded to the Tool's own Handle")
			end
			t.ok(not WireArt.Dress(tool, Meshes.Get()), "never twice")
			t.ok(not WireArt.Dress(t.roblox.Instance.new("Tool"), Meshes.Get()), "a Tool with no Handle is left alone")
		end
	)

	t.test("no part-built spool is left: WireArt has no builder for one and names none of its old pieces", function()
		local source = fs.readFile("src/ReplicatedStorage/Shared/Art/WireArt.luau")
		t.eq(string.find(source, "Kit.cylinder", 1, true), nil)
		t.eq(string.find(source, "CoilBand", 1, true), nil)
		t.eq(string.find(source, "CoilLow", 1, true), nil)
		t.eq(string.find(source, "WireEnd", 1, true), nil)
		t.eq(string.find(source, "UsesMesh", 1, true), nil)
		t.eq(string.find(source, "WireSpoolMeshId", 1, true), nil)
		t.eq(string.find(source, "Kit.part(", 1, true), nil, "no part is built with Kit.part")
		for _, p in ipairs(parts(WireArt.Build((loadedTemplates())))) do
			t.ok(
				p:IsA("MeshPart") or p.Name == "Handle" or p.Name == "SpoolCollider",
				p.Name .. " is not a mesh, the invisible Handle or the collider"
			)
			if not p:IsA("MeshPart") then
				t.eq(p.Transparency, 1, p.Name .. " is invisible")
			end
		end
	end)

	local function setup(load)
		local backpack = t.roblox.Instance.new("Folder")
		local attrs = {}
		local player = {
			UserId = 1,
			SetAttribute = function(_, k, v)
				attrs[k] = v
			end,
			FindFirstChildOfClass = function(_, class)
				return if class == "Backpack" then backpack else nil
			end,
		}
		local loader = t.loader({
			mocks = { RateLimiter = {
				Allow = function()
					return true
				end,
			} },
			globals = {
				workspace = {},
				task = {
					wait = function() end,
					spawn = function(f, ...)
						f(...)
					end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
			},
		})
		local meshes = loader:server("WireSpoolMeshes")
		meshes.Wait = function() end
		meshes.LoadModel = load or function()
			error("offline")
		end
		return {
			Service = loader:server("LogicService"),
			player = player,
			backpack = backpack,
			attrs = attrs,
			Meshes = meshes,
		}
	end

	t.test("GiveSpool hands over one Wire tool, flagged WireSpool, not droppable, and never a second", function()
		local s = setup()
		local tool = s.Service.GiveSpool(s.player)
		t.ok(tool ~= nil)
		t.eq(tool.Name, "Wire")
		t.eq(tool:GetAttribute("WireSpool"), true)
		t.eq(tool.CanBeDropped, false)
		t.eq(tool.RequiresHandle, true)
		t.eq(tool.Parent, s.backpack)
		t.eq(s.Service.GiveSpool(s.player), tool, "the same tool comes back")
		t.eq(#s.backpack:GetChildren(), 1)
	end)

	t.test("the Hammer's bar, picker and sheet carry no wiring; the controller starts nothing wire", function()
		local plot = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlotUI.luau")
		t.eq(string.find(plot, "WireTool.Begin", 1, true), nil)
		local hammer = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HammerController.luau")
		t.eq(string.find(string.lower(hammer), "wire", 1, true), nil, "HammerController never mentions wire")
		local menu = fs.readFile("src/StarterPlayer/StarterPlayerScripts/BuildMenuUI.luau")
		t.eq(string.find(menu, "WireTool", 1, true), nil)
		t.eq(string.find(menu, "WireSupply", 1, true), nil)
	end)

	t.test("the server hands the spool over with the Hammer on every spawn", function()
		local game = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		local at = string.find(game, "BlueprintService.GiveLoadout(player, character)", 1, true)
		t.ok(at ~= nil)
		t.ok(
			string.find(string.sub(game, at, at + 400), "LogicService.GiveSpool(player)", 1, true),
			"right after the loadout"
		)
	end)

	t.test("the wire box count is published as the WireUnits attribute at join", function()
		local game = fs.readFile("src/ServerScriptService/BlueprintService.luau")
		t.ok(string.find(game, '"WireUnits"', 1, true))
	end)

	t.test("the wire tool starts from the spool in hand and ends when it is put away", function()
		local tool = fs.readFile("src/StarterPlayer/StarterPlayerScripts/WireTool.luau")
		t.ok(string.find(tool, 'GetAttribute("WireSpool")', 1, true))
		t.ok(string.find(tool, "SetSpool", 1, true))
		local from = string.find(tool, "function WireTool.Begin(", 1, true)
		local to = string.find(tool, "-- BUILD mode (the hammer) on or off", 1, true)
		t.ok(from ~= nil and to ~= nil and to > from, "found Begin")
		t.eq(string.find(string.sub(tool, from, to), "UnequipTools", 1, true), nil, "starting keeps the tool in hand")
		t.ok(string.find(tool, "function WireTool.PutAway", 1, true), "DONE and B put the spool away")
		t.ok(
			string.find(tool, 'FireServer("buy"', 1, true) or string.find(tool, '"buy"', 1, true),
			"buys through the Wire remote"
		)
	end)
	t.test(
		"a failed load leaves NO part-built spool: the Tool keeps only its invisible Handle, and wiring still works",
		function()
			local Meshes = loaderWith(function()
				error("offline")
			end)
			Meshes.Load()
			local model = WireArt.Held(Meshes.Get())
			local all = parts(model)
			t.eq(#all, 1, "one part")
			t.eq(all[1].Name, "Handle")
			t.eq(all[1].Transparency, 1, "invisible")
			for _, name in ipairs({
				"Band",
				"Coil",
				"FlangeLeft",
				"FlangeRight",
				"Hub",
				"SpoolCollider",
				"CoilBand",
				"CoilLow",
				"WireEnd",
			}) do
				t.eq(model:FindFirstChild(name, true), nil, name .. " is not shown")
			end
			-- The Tool is still handed over, flagged, and the wire tool starts from the flag.
			local s = setup()
			local tool = s.Service.GiveSpool(s.player)
			t.ok(tool ~= nil and tool:GetAttribute("WireSpool") == true)
			t.ok(tool:FindFirstChild("Handle") ~= nil, "a Handle, so the Tool equips")
			for _, p in ipairs(parts(tool)) do
				t.eq(p.Transparency, 1, p.Name .. " is invisible")
			end
		end
	)

	t.test("GiveSpool dresses the Tool with the five meshes once they have loaded", function()
		local s = setup(function()
			return fakeModel()
		end)
		local tool = s.Service.GiveSpool(s.player)
		t.eq(#parts(tool), 7, "Handle, five meshes and the collider")
		t.ok(tool:FindFirstChild("SpoolCollider") ~= nil)
		t.eq(tool:FindFirstChild("Coil").MeshId, "rbxassetid://94852981021651")
	end)
end
