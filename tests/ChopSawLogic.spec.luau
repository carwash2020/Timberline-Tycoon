--!nocheck
-- Chop saw price, cut length, volume, and the phone panel's place on screen.
return function(t)
	local Enum = t.roblox.Enum
	local Vector3 = t.roblox.Vector3
	local Catalog = t.shared("ItemCatalog")
	local Config = t.shared("GameConfig")
	local Input = t.shared("InputKit")
	local Logic = t.shared("ChopSawLogic")
	local Sawmill = t.shared("SawmillLogic")
	local Section = t.shared("SectionLogic")
	local Wood = t.shared("WoodData")
	local MachineArt = t.load("ReplicatedStorage/Shared/Art/MachineArt")
	local fs = require("@lune/fs")

	local function find(model, name, class)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name and (not class or d:IsA(class)) then
				return d
			end
		end
		return nil
	end

	t.test("the chop saw is $7,500 at the Tool Shed and off the economy ladder", function()
		local saw = Catalog.GetMachine("ChopSaw")
		t.eq(saw.priceCash, 7500)
		t.eq(saw.priceCash, Catalog.ChopSawPrice)
		t.eq(saw.shop, "ToolShed")
		t.eq(saw.displayName, "Chop Saw")
		t.eq(Catalog.GetSawmill("ChopSaw"), nil)
		local listed = false
		for _, mill in ipairs(Catalog.SawmillList()) do
			if mill.id == "ChopSaw" then
				listed = true
			end
		end
		t.eq(listed, false)
		local config = fs.readFile("src/ReplicatedStorage/Shared/GameConfig.luau")
		t.eq(string.find(config, "ChopSawPrice", 1, true), nil)
		local econ = fs.readFile("tools/economy.luau")
		t.eq(string.find(econ, "ChopSaw", 1, true), nil, "the chop saw is not a rung")
		t.ok(string.find(econ, "ItemCatalog.Machines", 1, true) ~= nil, "planers are bought from Machines")
		local catalog = fs.readFile("src/ReplicatedStorage/Shared/ItemCatalog.luau")
		t.ok(string.find(catalog, "ItemCatalog.ChopSawPrice = 7500", 1, true))
	end)

	t.test("length clamps to 1..32 by 1, and y is not a step", function()
		t.eq(Logic.DefaultCut, 8)
		t.eq(Logic.Clamp(0), 1)
		t.eq(Logic.Clamp(40), 32)
		t.eq(Logic.Clamp(8.4), 8)
		t.eq(Logic.Clamp(1.6), 2)
		t.eq(Logic.Step(8, "x", 1), 9)
		t.eq(Logic.Step(8, "x", -1), 7)
		t.eq(Logic.Step(32, "x", 1), 32)
		t.eq(Logic.Step(1, "x", -1), 1)
		t.eq(Logic.Step(8, "y", 1), nil)
		t.eq(Logic.Step(8, "x", 2), nil)
		t.eq(Logic.MayUse(4, 4, nil), true)
		t.eq(Logic.MayUse(9, 4, nil), false)
		t.eq(Logic.MayUse(9, 4, { anyone = { interact = true } }), true)
		t.eq(Logic.MayUse(0, 0, nil), true, "user 0 is the owner of a 0 saw")
		t.eq(Logic.MayUse(9, 0, nil), false, "owner 0 is not a free pass")
		t.eq(Logic.MayUse(1, 0, nil), false)
	end)

	t.test("a 20 u pine set to 10 comes out as 10 u pieces that keep the volume and fit the Millmaster 100", function()
		local u = Config.WoodUnit
		local pine = Wood.Get("pine")
		local thick = pine.v2.shape.trunkThickness
		local trunk = Logic.Trunk(20 * u, thick)
		local before = Section.GraphVolume(trunk)
		local pieces = Logic.Dice(trunk, 10 * u)
		t.eq(#pieces, 2)
		local sum = 0
		local mill = Catalog.GetSawmill("Millmaster100")
		for _, graph in ipairs(pieces) do
			local length = 0
			local sections = {}
			for _, node in pairs(graph) do
				length += node.length
				table.insert(sections, {
					length = node.length,
					sx = node.thickness,
					sz = node.thickness,
					dir = Vector3.yAxis,
					children = #node.children,
					root = node.parent == nil,
				})
			end
			t.ok(math.abs(length - 10 * u) < 1e-4, "10 u")
			sum += Section.GraphVolume(graph)
			t.eq(Sawmill.Accepts({ kind = "log", sections = sections }, mill), true)
		end
		t.ok(math.abs(sum - before) < 1e-4, "volume is kept")
		t.eq(Section.GraphVolume(trunk), before, "the original graph is unchanged")
	end)

	t.test("phantomwood is refused by name, and the blade never kills", function()
		local why = Logic.Refusal("phantomwood")
		t.ok(string.find(why, "Gloamwood", 1, true))
		t.eq(Logic.Refusal("pine"), nil)
		t.eq(Logic.Hurt(5), 4)
		t.eq(Logic.Hurt(1), 0)
		t.eq(Logic.Hurt(100), 10)
		t.eq(Logic.Hurt(0), 0)
	end)

	t.test("the housing is a 6x4x4 base, a 32 u table, and a guard that is the only damage box", function()
		local saw = MachineArt.BuildChopSaw(false)
		local base = find(saw, "Base", "BasePart")
		local tablePart = find(saw, "Infeed", "BasePart")
		local guard = find(saw, "BladeGuard", "BasePart")
		t.eq(base.Size, Vector3.new(Logic.BaseX, Logic.BaseY, Logic.BaseZ))
		t.ok(math.abs(tablePart.Size.Z - Logic.TableLength()) < 1e-3, "infeed is 32 u")
		t.eq(guard.Size, Vector3.new(Logic.GuardX, Logic.GuardY, Logic.GuardZ))
		t.eq(guard.CanCollide, false)
		t.eq(guard:GetAttribute("Damage"), true)
		local boxes = 0
		for _, d in ipairs(saw:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("Damage") == true then
				boxes += 1
				t.eq(d.Name, "BladeGuard")
			end
			if d.Name == "Stripe" and d:IsA("BasePart") then
				t.eq(d.CanQuery, false)
				t.eq(d:GetAttribute("Damage"), nil)
			end
		end
		t.eq(boxes, 1)
		t.eq(find(saw, "CutPreview"), nil, "the server model has no preview line")
		local plane = find(saw, "BladePlane", "Attachment")
		local host = plane.Parent
		local origin = (host.CFrame * plane.CFrame).Position
		local line = MachineArt.PreviewLine(saw, Logic.DefaultCut)
		t.eq(line.Material, Enum.Material.Neon)
		t.ok(math.abs(line.Size.Y - Logic.PreviewThickness) < 1e-3, "0.2 studs thick")
		t.ok(math.abs(line.Size.Z - Logic.PreviewThickness) < 1e-3, "0.2 studs thick")
		local dist = (line.CFrame.Position - origin).Magnitude
		t.ok(math.abs(dist - Logic.PreviewStuds(Logic.DefaultCut)) < 1e-3, "8 u from the blade")
		local prompt = find(saw, "CutPrompt", "ProximityPrompt")
		t.eq(prompt.ActionText, "Set the length")
		t.eq(prompt.KeyboardKeyCode, Enum.KeyCode.E)
		t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonX)
		t.eq(prompt.RequiresLineOfSight, false)
		local priced = false
		for _, d in ipairs(saw:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == "$7,500" then
				priced = true
			end
			if d:IsA("TextButton") then
				t.ok(d.Size.X.Offset >= Input.MinTouchPx and d.Size.Y.Offset >= Input.MinTouchPx, d.Name)
				t.eq(d:GetAttribute("Axis"), "x")
			end
		end
		t.eq(priced, true)
		local ghost = MachineArt.BuildChopSaw(true)
		for _, d in ipairs(ghost:GetDescendants()) do
			t.eq(d:IsA("TextButton"), false)
			if d:IsA("BasePart") then
				t.eq(d:GetAttribute("Damage"), nil)
			end
		end
		local run = find(saw, "Run", "Attachment")
		t.eq(run:GetAttribute("LogicInput"), "Run")
		t.eq(find(saw, "Run", "BoolValue").Value, true)
	end)

	t.test("the card stays clear of the left column, the hotbar and the jump button", function()
		local Vector2 = t.roblox.Vector2
		t.eq(Logic.PanelFace(false), 48)
		t.eq(Input.TouchOk(Logic.PanelFace(false)), true)
		t.eq(Input.PlacerSafe(Logic.PanelBinds, true), true)
		local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
		t.ok(string.find(net, '"ChopSawSet", -- client -> server: (uid, "x" | "y", 1 | -1)', 1, true))
		local plot = fs.readFile("src/ServerScriptService/PlotService.luau")
		t.ok(string.find(plot, "ChopSawLogic.Blueprint(item.blueprintId)", 1, true))
		t.eq(string.find(plot, "ItemCatalog.GetMachine(item.blueprintId)", 1, true), nil)
		local logic = fs.readFile("src/ReplicatedStorage/Shared/ChopSawLogic.luau")
		t.eq(string.find(logic, "ownerId == 0", 1, true), nil)

		-- UITheme.Bottom is 12 + 58 on a phone (viewport height under 600) and
		-- 12 + 70 otherwise. ScaleFor is the screen's UIScale. The left column
		-- is 280 offsets wide at the 12 px margin (QuestUI). During the
		-- tutorial it is the tracker (92) plus Murph's card (106). Its top is
		-- max(top bar, 36) + 8, in screen pixels.
		local function theme(w, h, handheld)
			return t.loader({
				services = {
					GuiService = {
						IsTenFootInterface = function()
							return false
						end,
						TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
						GetGuiInset = function()
							return Vector2.zero, Vector2.zero
						end,
					},
					Players = { LocalPlayer = {} },
					TextChatService = {},
					UserInputService = { TouchEnabled = handheld, KeyboardEnabled = not handheld },
				},
				globals = {
					workspace = { CurrentCamera = { ViewportSize = Vector2.new(w, h) } },
				},
			}):load("StarterPlayer/StarterPlayerScripts/UITheme")
		end
		local TRACKER, SPEECH = 92, 106
		local cases = {
			{ "667 x 375", 667, 375, true },
			{ "375 x 667", 375, 667, true },
			{ "1920 x 1080", 1920, 1080, false },
		}
		for _, case in ipairs(cases) do
			local name, w, h, handheld = case[1], case[2], case[3], case[4]
			local UITheme = theme(w, h, handheld)
			local screen = Vector2.new(w, h)
			local scale = UITheme.ScaleFor(screen, handheld, false)
			local hotbar = UITheme.Bottom()
			local phone = handheld and h < 600
			t.eq(hotbar, 12 + (if phone then 58 else 70), name .. ": UITheme.Bottom")
			local jump = if handheld then Logic.JumpRect(screen) else nil
			local card = Logic.PanelRect(screen, scale, hotbar, jump, false)
			local columnTop = math.max(36, 58) + 8
			local column = {
				left = 12 * scale,
				top = columnTop,
				right = (12 + 280) * scale,
				bottom = columnTop + (TRACKER + SPEECH) * scale,
			}
			local band = { left = 0, top = h - hotbar * scale, right = w, bottom = h }
			local obstacles = { column, band }
			if jump then
				table.insert(obstacles, jump)
			end
			t.eq(Logic.Clears(card, obstacles), true, name)
			t.ok(card.left >= 0 and card.top >= 0 and card.right <= w and card.bottom <= h, name .. ": on screen")
			t.ok(card.bottom <= band.top, name .. ": above the hotbar")
		end
	end)
end
