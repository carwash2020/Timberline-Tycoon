--!nocheck
-- StandIn (T420): meshed art ships its mesh or nothing. The check (Shared/Lint/StandIn) fails a
-- visible part-built piece under a registered meshed-art name (today the wire spool) or under an
-- instance flagged MeshedArt. This spec runs it over the spool as built, over the Tool the server hands
-- over (meshes loaded, and the load failed), over the town, and over deliberate stand-ins, which it
-- must catch.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local StandIn = t.load("ReplicatedStorage/Shared/Lint/StandIn")
	local WireArt = t.load("ReplicatedStorage/Shared/Art/WireArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")

	local function templates()
		local out = {}
		for _, piece in ipairs(WireArt.Config.Pieces) do
			local mesh = Instance.new("MeshPart")
			mesh.Name = piece.name
			mesh.MeshId = "rbxassetid://" .. piece.meshId
			mesh.Size = piece.size
			out[piece.name] = mesh
		end
		return out
	end

	local function show(lines)
		return "\n" .. table.concat(lines, "\n")
	end

	t.test("the registry names the wire spool", function()
		t.ok(table.find(StandIn.Registry, "WireSpool") ~= nil)
		t.eq(StandIn.Attribute, "MeshedArt")
	end)

	t.test("the spool as built (meshes, nothing, held) has no visible stand-in", function()
		for label, model in pairs({
			meshes = WireArt.Build(templates()),
			nothing = WireArt.Build(),
			held = WireArt.Held(templates()),
			heldNothing = WireArt.Held(),
		}) do
			local lines = StandIn.Find(model)
			t.eq(#lines, 0, label .. show(lines))
		end
	end)

	t.test("the Tool LogicService hands over has none, loaded or not", function()
		for _, loads in ipairs({ true, false }) do
			local backpack = Instance.new("Folder")
			local player = {
				UserId = 1,
				SetAttribute = function() end,
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
			meshes.LoadModel = function()
				if not loads then
					error("offline")
				end
				local model = Instance.new("Model")
				for name, mesh in pairs(templates()) do
					mesh.Parent = model
				end
				return model
			end
			local tool = loader:server("LogicService").GiveSpool(player)
			t.eq(tool:GetAttribute("MeshedArt"), true, "the Tool is flagged")
			local lines = StandIn.Find(tool)
			t.eq(#lines, 0, show(lines))
			local shown = 0
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("MeshPart") then
					shown += 1
				end
			end
			t.eq(shown, if loads then 5 else 0, "five meshes, or nothing at all")
		end
	end)

	t.test("the built town has none (no registered meshed art in it is part-built)", function()
		local TownBuild = t.load("ReplicatedStorage/Shared/Lint/TownBuild")
		local lines = StandIn.Find(TownBuild.Build())
		t.eq(#lines, 0, show(lines))
	end)

	-- Deliberate failing controls: the check must catch each.
	t.test("control: a part-built spool (the old one) is caught, one line per visible part", function()
		local model = Kit.model("WireSpool")
		Kit.cylinder(
			model,
			"FlangeLeft",
			0.12,
			1.5,
			CFrame.new(-0.5, 0, 0),
			roblox.Color3.new(0.5, 0.3, 0.2),
			roblox.Enum.Material.Wood
		)
		Kit.cylinder(
			model,
			"Coil",
			0.9,
			1.15,
			CFrame.new(0, 0, 0),
			roblox.Color3.new(0.8, 0.5, 0.3),
			roblox.Enum.Material.Metal
		)
		local hidden = Kit.part(
			model,
			"Handle",
			Vector3.new(1, 0.3, 0.3),
			CFrame.new(0, 0, 0),
			roblox.Color3.new(0, 0, 0),
			roblox.Enum.Material.Wood
		)
		hidden.Transparency = 1
		local lines = StandIn.Find(model)
		t.eq(#lines, 2, "the two visible parts, not the invisible Handle" .. show(lines))
		t.ok(string.find(lines[1], "part-built", 1, true) ~= nil)
	end)

	t.test("control: a MeshPart with no MeshId is caught", function()
		local model = Kit.model("WireSpool")
		local mesh = Instance.new("MeshPart")
		mesh.Name = "Coil"
		mesh.MeshId = "" -- (the engine's default; Lune has none)
		mesh.Parent = model
		local lines = StandIn.Find(model)
		t.eq(#lines, 1, show(lines))
		t.ok(string.find(lines[1], "no MeshId", 1, true) ~= nil)
	end)

	t.test(
		"control: a part-built piece under an instance flagged MeshedArt is caught; an unflagged one is not looked at",
		function()
			local flagged = Kit.model("Anything")
			flagged:SetAttribute("MeshedArt", true)
			Kit.part(
				flagged,
				"Box",
				Vector3.new(1, 1, 1),
				CFrame.new(0, 0, 0),
				roblox.Color3.new(1, 1, 1),
				roblox.Enum.Material.Wood
			)
			t.eq(#StandIn.Find(flagged), 1)
			local plain = Kit.model("Anything")
			Kit.part(
				plain,
				"Box",
				Vector3.new(1, 1, 1),
				CFrame.new(0, 0, 0),
				roblox.Color3.new(1, 1, 1),
				roblox.Enum.Material.Wood
			)
			t.eq(#StandIn.Find(plain), 0, "part-built things that are not registered are the town's business")
			-- Found when nested too.
			local root = Instance.new("Folder")
			local spool = Kit.model("WireSpool")
			spool.Parent = root
			Kit.part(
				spool,
				"Box",
				Vector3.new(1, 1, 1),
				CFrame.new(0, 0, 0),
				roblox.Color3.new(1, 1, 1),
				roblox.Enum.Material.Wood
			)
			t.eq(#StandIn.Find(root), 1, "found under a root")
		end
	)
end
