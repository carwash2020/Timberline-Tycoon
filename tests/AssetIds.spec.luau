--!nocheck
-- Asset id rules (12 October 2026 audit; the inventory is ASSETS.md).
-- Claude cannot reach Roblox from CI or its sandbox, so this pins what can be
-- proven from the source text: id FORMAT, kinds never mixed (an image id used
-- as a MeshId, a Model container used as a mesh), uniqueness, and that the
-- Rojo MeshTemplates fallbacks are well formed. It cannot prove an id exists
-- or that the experience may load it: that is the Creator Hub checklist in
-- ASSETS.md.
--
-- It also pins the behaviour behind Connor's Studio log ("[MachineSkin]
-- SmeltingFurnace piece Body (mesh ...) did not load; keeping the part-built
-- machine"): the mining machines are built at server start, before their
-- meshes can be in, so they must be part-built first and swapped when the mesh
-- lands, never left part-built for good.
return function(t)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local roblox = t.roblox

	local Scan = luau.load(fs.readFile("tools/assetscan.luau"), { debugName = "tools/assetscan.luau" })()
	local records = Scan.Scan()
	local literals = Scan.Literals()

	local function where(r)
		return r.path .. ":" .. tostring(r.line)
	end

	local function byKind(kind)
		local out = {}
		for _, r in ipairs(records) do
			if r.kind == kind then
				table.insert(out, r)
			end
		end
		return out
	end

	t.test("the scan finds the ids it is supposed to (so the rules below are not vacuous)", function()
		t.ok(#byKind("mesh") > 1000, "mesh records")
		t.ok(#byKind("model") >= 200, "model containers")
		t.ok(#byKind("template") >= 990, "MeshTemplates files")
		t.ok(#byKind("sound") >= 9, "sound ids")
		t.ok(#byKind("image") >= 10, "image ids")
		t.ok(#byKind("texture") == 9, "material maps")
		t.ok(#byKind("pass") >= 2 and #byKind("product") >= 2, "store ids")
		t.ok(#literals > 100, "rbxassetid literals")
	end)

	t.test("every rbxassetid:// literal is digits only: no URLs, query strings, zero or empty ids", function()
		for _, lit in ipairs(literals) do
			local text = lit.text
			local where_ = lit.path .. ":" .. tostring(lit.line)
			if string.sub(text, 1, 4) == "http" then
				-- The only web links allowed in source are documentation (comments are stripped)
				-- and never an asset-delivery URL.
				t.ok(
					not string.find(text, "roblox.com/asset", 1, true)
						and not string.find(text, "assetdelivery", 1, true),
					where_ .. " uses an asset-delivery URL: " .. text
				)
			elseif
				string.sub(text, 1, 8) == "rbxthumb"
				and lit.path == "src/ReplicatedStorage/Shared/StoreArt.luau"
				and string.find(text, "type=Asset&id=", 1, true)
			then
				-- The one sanctioned use: StoreArt shows a store card's picture through the
				-- asset thumbnail, which renders a Decal id or an Image id alike (the pasted
				-- store ids are not known to be Image ids). Everywhere else still fails.
				continue
			elseif string.sub(text, 1, 8) == "rbxthumb" then
				t.ok(false, where_ .. " uses rbxthumb, which loads a thumbnail, not the asset: " .. text)
			elseif text == "rbxassetid://" then
				-- A prefix that is joined to an id ("rbxassetid://" .. tostring(id)); fine.
				continue
			else
				local digits = string.match(text, "^rbxassetid://(%d+)$")
				t.ok(digits ~= nil, where_ .. " is not rbxassetid://<digits>: " .. text)
				if digits then
					t.ok(tonumber(digits) > 0, where_ .. " is a zero id")
				end
			end
		end
	end)

	local function placeholder(digits)
		if #digits < 5 then
			return true
		end
		if string.match(digits, "^(%d)%1+$") then
			return true -- 1111111111
		end
		return string.find("0123456789012345678901234567890", digits, 1, true) ~= nil
			or string.find("9876543210987654321098765432109", digits, 1, true) ~= nil
	end

	-- Inclusive digit-length bounds per kind. Studio uploads today are 13 to 16
	-- digits; Roblox's own audio and textures go back to 9 digits and fewer.
	local LENGTHS = {
		mesh = { 13, 16 },
		model = { 13, 16 },
		template = { 13, 16 },
		image = { 9, 16 },
		texture = { 8, 16 },
		sound = { 8, 16 },
		pass = { 9, 11 },
		product = { 9, 11 },
		badge = { 13, 16 }, -- Creator Hub badge ids (BadgeData.Ids), 15 to 16 digits today
	}

	t.test("every id is well formed for its kind: no leading zero, not a placeholder, sane length", function()
		for _, r in ipairs(records) do
			local bounds = LENGTHS[r.kind]
			t.ok(bounds ~= nil, "unknown kind " .. r.kind)
			t.ok(string.sub(r.digits, 1, 1) ~= "0", where(r) .. " has a leading zero")
			t.ok(not placeholder(r.digits), where(r) .. " looks like a placeholder: " .. r.digits)
			t.ok(
				#r.digits >= bounds[1] and #r.digits <= bounds[2],
				where(r) .. " " .. r.kind .. " id " .. r.digits .. " has " .. #r.digits .. " digits"
			)
			t.ok(r.id < 2 ^ 53, where(r) .. " is past exact double range")
			t.eq(tostring(r.id), r.digits, where(r) .. " does not survive a number round trip")
		end
	end)

	local function set(kind)
		local out = {}
		for _, r in ipairs(byKind(kind)) do
			out[r.digits] = r
		end
		return out
	end

	t.test(
		"kinds are never mixed: no id is two kinds (a Model as a MeshId, an image as a mesh, a sound as an image)",
		function()
			local kinds = { "mesh", "model", "image", "texture", "sound", "pass", "product" }
			local sets = {}
			for _, kind in ipairs(kinds) do
				sets[kind] = set(kind)
			end
			for i = 1, #kinds do
				for j = i + 1, #kinds do
					for digits, r in pairs(sets[kinds[i]]) do
						local other = sets[kinds[j]][digits]
						t.ok(
							other == nil,
							digits
								.. " is a "
								.. kinds[i]
								.. " ("
								.. where(r)
								.. ") and a "
								.. kinds[j]
								.. " ("
								.. (other and where(other) or "")
								.. ")"
						)
					end
				end
			end
		end
	)

	t.test("a model container id is written once: two assets never share one", function()
		local seen = {}
		for _, r in ipairs(byKind("model")) do
			local first = seen[r.digits]
			t.ok(
				first == nil,
				r.digits .. " is the container of two assets: " .. (first and where(first) or "") .. " and " .. where(r)
			)
			seen[r.digits] = r
		end
	end)

	t.test("a mesh id is shared between modules only where BlenderAssets mirrors BacklogModels", function()
		local filesOf = {}
		for _, r in ipairs(byKind("mesh")) do
			local name = string.match(r.path, "([^/]+)$")
			filesOf[r.digits] = filesOf[r.digits] or {}
			filesOf[r.digits][name] = true
		end
		local mirrored = 0
		for digits, files in pairs(filesOf) do
			local names = {}
			for name in pairs(files) do
				table.insert(names, name)
			end
			table.sort(names)
			if #names > 1 then
				local key = table.concat(names, "+")
				t.ok(
					key == "BacklogModels.luau+BlenderAssets.luau"
						or key == "BlenderAssets.luau+ModelSlots.luau"
						or key == "BlenderAssets.luau+StoreModelSlots.luau",
					"mesh " .. digits .. " is shared between modules: " .. key
				)
				mirrored += 1
			end
		end
		t.ok(
			mirrored <= 30,
			"the Blender registry mirrors the backlog; more than this is new sharing (" .. mirrored .. ")"
		)
	end)

	t.test(
		"MeshTemplates: each file is <id>.model.json for a MeshPart with exactly that MeshId, and its id is in use",
		function()
			local used = set("mesh")
			local count = 0
			for _, r in ipairs(byKind("template")) do
				count += 1
				local body = fs.readFile(r.path)
				t.ok(string.find(body, '"className": "MeshPart"', 1, true), r.path .. " is not a MeshPart")
				t.ok(
					string.find(body, '"MeshId": "rbxassetid://' .. r.digits .. '"', 1, true),
					r.path .. " MeshId differs from its file name"
				)
				t.ok(used[r.digits] ~= nil, r.path .. " is a template for an id no builder uses")
			end
			t.ok(count > 0)
			-- Nothing else lives in the folder (a stray file would never be a template).
			for _, name in ipairs(fs.readDir("src/ReplicatedStorage/MeshTemplates")) do
				t.ok(string.match(name, "^%d+%.model%.json$") ~= nil, "unexpected file in MeshTemplates: " .. name)
			end
		end
	)

	t.test("ASSETS.md lists every id the code uses", function()
		local text = fs.readFile("ASSETS.md")
		for _, r in ipairs(records) do
			if r.kind ~= "template" then
				t.ok(
					string.find(text, r.digits, 1, true) ~= nil,
					"ASSETS.md is missing " .. r.digits .. " (" .. where(r) .. "); run lune run tools/assets"
				)
			end
		end
	end)

	t.test("MiningArt only asks for a machine skin inside MeshKit.Attempt (never final at build time)", function()
		local text = fs.readFile("src/ReplicatedStorage/Shared/Mining/MiningArt.luau")
		local asks = 0
		for _ in string.gmatch(text, "MachineSkin%.Prepare%(") do
			asks += 1
		end
		local attempts = 0
		for _ in string.gmatch(text, "MeshKit%.Attempt%(model,") do
			attempts += 1
		end
		t.eq(attempts, 3, "furnace, stall and bench each dress through Attempt")
		-- Each Prepare lives in a dress function (a local function above its builder), not in a builder.
		for builder in string.gmatch(text, "function MiningArt%.(%w+)%(%)") do
			if builder == "SmeltingFurnace" or builder == "Prospector" or builder == "CraftBench" then
				local body = string.match(text, "function MiningArt%." .. builder .. "%(%)(.-)\nend\n")
				t.ok(
					body ~= nil and not string.find(body, "MachineSkin.Prepare", 1, true),
					builder .. " calls Prepare outside Attempt"
				)
			end
		end
		t.eq(asks, 4, "furnace, prospector, chute, bench")
	end)

	-- The engine held, as in tests/BuildBudget.spec: a load runs only when the
	-- spec runs the queued job.
	local function held()
		local loader = t.loader()
		local MeshKit = loader:shared("Art/MeshKit")
		local MachineSkin = loader:shared("Art/MachineSkin")
		local MachineMeshes = loader:shared("Art/MachineMeshes")
		local MiningArt = loader:shared("Mining/MiningArt")
		MeshKit.Reset()
		MachineSkin.Reset()
		MeshKit.Override = nil
		MeshKit.Retries = 0
		local jobs = {}
		MeshKit.Scheduler = {
			spawn = function(fn)
				table.insert(jobs, fn)
			end,
			wait = function() end,
			clock = os.clock,
		}
		local failing = {}
		local loads = {}
		MeshKit.EngineLoad = function(meshId)
			table.insert(loads, meshId)
			if failing[meshId] then
				return nil, "no permission"
			end
			local part = roblox.Instance.new("MeshPart")
			part.Name = "Loaded" .. tostring(meshId)
			return part, nil
		end
		local sim = {
			failing = failing,
			loads = loads,
			jobs = jobs,
			runJobs = function()
				while #jobs > 0 do
					table.remove(jobs, 1)()
				end
			end,
			done = function()
				MeshKit.EngineLoad = nil
				MeshKit.Scheduler = {
					spawn = function(fn)
						fn()
					end,
					wait = function() end,
					clock = os.clock,
				}
				MeshKit.Reset()
				MachineSkin.Reset()
			end,
		}
		return MeshKit, MachineSkin, MachineMeshes, MiningArt, sim
	end

	local function find(model, name)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	local function meshCount(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
				n += 1
			end
		end
		return n
	end

	local BUILDERS = { "SmeltingFurnace", "Prospector", "CraftBench" }

	t.test("the mining machines are part-built at once, never yield, and wear their meshes when they land", function()
		for _, name in ipairs(BUILDERS) do
			local MeshKit, MachineSkin, _, MiningArt, sim = held()
			local co = coroutine.create(function()
				return MiningArt[name]()
			end)
			local ok, model = coroutine.resume(co)
			t.ok(ok, tostring(model))
			t.eq(coroutine.status(co), "dead", name .. " built without yielding")
			t.eq(#sim.loads, 0, name .. " did not touch the engine on the building thread")
			t.eq(MachineSkin.Wears(model), false, name .. " is part-built for now")
			t.eq(meshCount(model), 0)
			t.ok(model.PrimaryPart ~= nil, name .. " has its gameplay parts")
			t.eq(MachineSkin.Misses(), 0, name .. " does not log a pending load as a failure")
			-- MiningService parents and moves it after building; the swap needs it in the world.
			local world = roblox.Instance.new("Folder")
			model.Parent = world
			local before = model:GetPivot()
			model:PivotTo(before * roblox.CFrame.new(100, 0, 50))
			local placed = model:GetPivot()
			sim.runJobs()
			MeshKit.Pump(1)
			t.eq(MachineSkin.Wears(model), true, name .. " wears its meshes once they have landed")
			t.ok(meshCount(model) >= 1, name .. " has mesh parts")
			t.ok(
				(model:GetPivot().Position - placed.Position).Magnitude < 1e-3,
				name .. " is where it was placed after the swap"
			)
			sim.done()
		end
	end)

	t.test("the furnace swap keeps its gameplay parts and swaps the part-built roof for the mesh", function()
		local MeshKit, _, _, MiningArt, sim = held()
		local furnace = MiningArt.SmeltingFurnace()
		t.ok(find(furnace, "Roof") ~= nil and find(furnace, "Lantern") ~= nil, "part-built: roof and lanterns")
		local mouth, intake = find(furnace, "FireMouth"), find(furnace, "SmeltIntake")
		furnace.Parent = roblox.Instance.new("Folder")
		sim.runJobs()
		MeshKit.Pump(1)
		t.eq(find(furnace, "Roof"), nil, "the mesh carries the roof")
		t.eq(find(furnace, "Lantern"), nil)
		t.eq(find(furnace, "FireMouth"), mouth, "the same FireMouth part, not a copy")
		t.eq(find(furnace, "SmeltIntake"), intake, "the same intake part, so MiningService's reference is live")
		t.eq(intake.Transparency, 1)
		local lights = 0
		for _, d in ipairs(furnace:GetDescendants()) do
			if d:IsA("PointLight") then
				lights += 1
			end
		end
		t.eq(lights, 1, "one light before and after")
		sim.done()
	end)

	t.test("a mesh that fails leaves the part-built machine working, logs once, and never throws", function()
		for _, name in ipairs(BUILDERS) do
			local MeshKit, MachineSkin, MachineMeshes, MiningArt, sim = held()
			local id = if name == "Prospector" then "Prospector" else name
			for _, piece in ipairs(MachineMeshes.Get(id).pieces) do
				sim.failing[piece.meshId] = true
			end
			local model = MiningArt[name]()
			model.Parent = roblox.Instance.new("Folder")
			sim.runJobs()
			MeshKit.Pump(1)
			t.eq(MachineSkin.Wears(model), false, name .. " stays part-built")
			t.eq(meshCount(model), 0)
			t.ok(model.PrimaryPart ~= nil)
			sim.done()
		end
	end)

	t.test("the Prospector stall and its chute are dressed together or not at all", function()
		local MeshKit, MachineSkin, MachineMeshes, MiningArt, sim = held()
		-- Only the chute fails: the stall must not be left half dressed.
		for _, piece in ipairs(MachineMeshes.Get("OreChute").pieces) do
			sim.failing[piece.meshId] = true
		end
		local model = MiningArt.Prospector()
		model.Parent = roblox.Instance.new("Folder")
		sim.runJobs()
		MeshKit.Pump(1)
		t.eq(MachineSkin.Wears(model), false)
		t.eq(meshCount(model), 0, "no stall mesh without the chute mesh")
		t.ok(find(model, "Awning") ~= nil, "the part-built awning is still there")
		local chute = find(model, "OreChute")
		t.ok(chute ~= nil and chute.Transparency < 1, "the part-built chute is still visible")
		sim.done()
	end)
end
