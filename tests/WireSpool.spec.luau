--!nocheck
-- WireSpool (T420): the wire is its own tool, not part of the hammer. A spool of
-- parts (no mesh id, no asset id) is handed to every player with the Hammer; the
-- Hammer's bar, its picker and its sheet carry no wiring.
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

	t.test("the spool is a Tool-ready model: a Handle with everything welded to it, a small budget", function()
		local model = WireArt.Build()
		local handle = model.PrimaryPart
		t.ok(handle ~= nil and handle.Name == "Handle")
		local all = parts(model)
		t.ok(#all >= 4 and #all <= 14, "part budget: " .. #all)
		for _, p in ipairs(all) do
			if p ~= handle then
				local weld = p:FindFirstChildOfClass("Weld")
				t.ok(weld ~= nil and weld.Part0 == handle and weld.Part1 == p, p.Name .. " is welded")
			end
		end
		for _, p in ipairs(parts(WireArt.Held())) do
			t.ok(not p.Anchored and not p.CanCollide and p.Massless, p.Name .. " is inert in hand")
		end
		t.ok(WireArt.Grip() ~= nil)
	end)

	t.test("the art is built from parts only: no asset id, no mesh", function()
		local source = fs.readFile("src/ReplicatedStorage/Shared/Art/WireArt.luau")
		t.eq(string.find(source, "rbxassetid", 1, true), nil)
		t.eq(string.find(source, "MeshId", 1, true), nil)
		t.eq(string.find(source, "%d%d%d%d%d%d%d%d"), nil, "no long numbers that look like ids")
	end)

	local function setup(hasWallet)
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
			globals = { workspace = {}, OverlapParams = {
				new = function()
					return {}
				end,
			} },
		})
		return { Service = loader:server("LogicService"), player = player, backpack = backpack, attrs = attrs }
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
end
