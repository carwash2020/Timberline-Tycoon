--!nocheck
-- T421: every visual MeshPart VehicleMeshes adds is looks only (Massless, no collide, no query, no touch, Box
-- fidelity), and the colliding parts TruckArt builds are unchanged: tests/vehicle_collision_baseline.json is every
-- truck and every rig as main built them before T421 (tools/vehicle_snapshot.luau); a fresh build must match.
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")
	local Gate = t.load("ReplicatedStorage/Shared/VehicleMeshGate")
	local TruckLayout = t.shared("TruckLayout")
	local ItemCatalog = t.shared("ItemCatalog")

	local function withMeshes(fn)
		MeshKit.Reset()
		VehicleMeshes.ResetWarnings()
		Gate.SetIds(Gate.FakeIds())
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			-- a freshly loaded template: solid, with mass
			part.Massless = false
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = true
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		Gate.SetIds(nil)
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function checkVisual(model, label)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("MeshPart") and d:GetAttribute("VisualMesh") == true then
				n += 1
				local who = label .. " " .. d.Name
				t.eq(d.Massless, true, who .. " Massless")
				t.eq(d.CanCollide, false, who .. " CanCollide")
				t.eq(d.CanQuery, false, who .. " CanQuery")
				t.eq(d.CanTouch, false, who .. " CanTouch")
				t.eq(d.CollisionFidelity, roblox.Enum.CollisionFidelity.Box, who .. " CollisionFidelity")
			end
		end
		return n
	end

	t.test("every visual MeshPart is Massless, CanCollide/CanQuery/CanTouch false, Box fidelity", function()
		withMeshes(function()
			local total = 0
			for _, def in ipairs(ItemCatalog.TruckList()) do
				local lay = TruckLayout.For(def)
				total += checkVisual(TruckArt.Build(def, lay), def.id)
				if def.look.bedLength > 0 then
					for _, trailer in ipairs(ItemCatalog.TrailerList()) do
						local model = TruckArt.Build(def, lay, trailer, TruckLayout.ForTrailer(trailer, lay))
						t.eq(model:GetAttribute("VehicleMesh"), true, def.id .. " + " .. trailer.id .. " is meshed")
						total += checkVisual(model, def.id .. " + " .. trailer.id)
					end
				end
			end
			t.ok(total > 100, "visual meshes were found: " .. total)
		end)
	end)

	t.test("the colliding parts TruckArt builds are unchanged for every truck and rig", function()
		local base = serde.decode("json", fs.readFile("tests/vehicle_collision_baseline.json"))
		local seen = 0
		for _, def in ipairs(ItemCatalog.TruckList()) do
			local lay = TruckLayout.For(def)
			local function rows(model)
				local out = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.CanCollide then
						local nums = {}
						for _, v in ipairs({ d.CFrame:GetComponents() }) do
							table.insert(nums, string.format("%.3f", math.floor(v * 1000 + 0.5) / 1000))
						end
						local s = d.Size
						local function r(n)
							return math.floor(n * 1000 + 0.5) / 1000
						end
						table.insert(
							out,
							string.format(
								"%s|%.3f,%.3f,%.3f|%s",
								d.Name,
								r(s.X),
								r(s.Y),
								r(s.Z),
								table.concat(nums, ",")
							)
						)
					end
				end
				table.sort(out)
				return out
			end
			local function same(key, model)
				local want, got = base[key], rows(model)
				t.ok(want ~= nil, key .. " has a baseline")
				t.eq(#got, #want, key .. " part count")
				for i = 1, math.min(#got, #want) do
					t.eq(got[i], want[i], key .. " part " .. i)
				end
				seen += 1
			end
			same("Truck/" .. def.id, TruckArt.Build(def, lay))
			if def.look.bedLength > 0 then
				for _, trailer in ipairs(ItemCatalog.TrailerList()) do
					same(
						"Rig/" .. def.id .. "/" .. trailer.id,
						TruckArt.Build(def, lay, trailer, TruckLayout.ForTrailer(trailer, lay))
					)
				end
			end
		end
		t.ok(seen >= 8, "compared " .. seen)
	end)
end
