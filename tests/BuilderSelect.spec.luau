--!nocheck
-- Gamepad select (R2, screen centre) and a mouse click hit the same piece.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local Vector2 = t.roblox.Vector2
	local Vector3 = t.roblox.Vector3
	local fs = require("@lune/fs")

	local model = Instance.new("Model")
	model:AddTag("PlacedItem")
	model:SetAttribute("Uid", "piece-1")
	model:SetAttribute("Kit", true)
	model:SetAttribute("FillUnits", 0)
	model:SetAttribute("OwnerId", 7)
	local part = Instance.new("Part")
	part.Parent = model

	local seen = {}
	local function raycast(_, origin, _direction)
		table.insert(seen, tostring(typeof(origin)) .. ":" .. tostring(origin))
		if origin and origin.X == 100 and origin.Y == 50 then
			return { Instance = part }
		end
		return nil
	end

	local camera = {
		ViewportSize = Vector2.new(200, 100),
		ViewportPointToRay = function(_, x, y)
			return { Origin = Vector3.new(x, y, 5), Direction = Vector3.new(0, -1, 0) }
		end,
	}

	local loader = t.loader({
		services = {
			Players = { LocalPlayer = { UserId = 7 } },
			GuiService = {
				IsTenFootInterface = function()
					return false
				end,
				TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
				GetGuiInset = function()
					return Vector2.zero, Vector2.zero
				end,
			},
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
			ContextActionService = {},
			RunService = {},
		},
		globals = {
			workspace = {
				Raycast = raycast,
				CurrentCamera = camera,
			},
			RaycastParams = {
				new = function()
					return {}
				end,
			},
		},
		mocks = {
			HUD = { Toast = function() end },
			BlueprintPlacer = {
				Active = function()
					return false
				end,
			},
		},
	})
	local Tools = loader:load("StarterPlayer/StarterPlayerScripts/BuilderTools")

	t.test("the centre ray and a click on that point select the same piece", function()
		local cx, cy = Tools.Center(camera.ViewportSize)
		t.eq(cx, 100)
		t.eq(cy, 50)
		local aimed = Tools.Aim(camera, cx, cy)
		if aimed ~= model then
			error("aim " .. tostring(aimed) .. " rays " .. table.concat(seen, " | "))
		end
		t.eq(aimed, model)
		t.eq(Tools.Aim(camera, 100, 50), Tools.Aim(camera, cx, cy))
		t.eq(Tools.Aim(camera, 1, 1), nil)
		t.eq(Tools.OnSelect("BuilderSelect", Enum.UserInputState.Begin), Enum.ContextActionResult.Sink)
		if Tools.PrimarySelected() ~= model then
			error("selected " .. tostring(Tools.PrimarySelected()) .. " rays " .. table.concat(seen, " | "))
		end
		t.eq(Tools.PrimarySelected(), model)
		t.eq(Tools.SelectedCount(), 1)
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/BuilderTools.luau")
		t.ok(string.find(src, "Enum.ScreenInsets.CoreUISafeInsets", 1, true))
		t.ok(string.find(src, "UITheme.Bottom()", 1, true))
		t.ok(string.find(src, "BuilderBar.Layout", 1, true))
		t.ok(string.find(src, "Enum.KeyCode.ButtonR2", 1, true))
	end)
end
