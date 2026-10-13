--!nocheck
-- Shared by the vehicles-* review scenes: stands each specimen (a truck, or a
-- truck and its trailer, built by TruckArt.Build, the same call VehicleService
-- makes, so the real uploaded meshes dress it) on its own floor, far from the
-- others, and makes a set of cameras round it: front, both sides, the two
-- three-quarters, wheel close-ups and low ground-level views.
local Vehicles = {}
local V3 -- the preview's Vector3, set by build

local LIGHTING = {
	sunDir = { -0.35, 0.9, -0.25 },
	sunColor = "#fff4e4",
	sunIntensity = 1.7,
	skyTop = "#f3f0e8",
	skyBottom = "#f7f4ee",
	ground = "#e4dfd4",
	hemiIntensity = 1.15,
	ambient = 0.72,
	fog = "#f3f0e8",
	fogNear = 300,
	fogFar = 800,
	exposure = 1.12,
	bloom = 0.05,
}

-- Bounds of every part in a model, in world space (corners of each part's box).
local function boundsOf(model)
	local lo, hi = nil, nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Chassis" and d.Name ~= "BedZone" and d.Transparency < 1 then
			local half = d.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = d.CFrame * V3.new(half.X * sx, half.Y * sy, half.Z * sz)
						lo = if lo then lo:Min(p) else p
						hi = if hi then hi:Max(p) else p
					end
				end
			end
		end
	end
	return lo, hi
end
Vehicles.boundsOf = boundsOf

local function wheelsOf(model, trailer)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil then
			local isTrailer = d:GetAttribute("RigHalf") == "trailer" or d:GetAttribute("TrailerBody") == true
			if isTrailer == trailer then
				table.insert(out, d.CFrame.Position)
			end
		end
	end
	return out
end

-- The wheel nearest the given corner: sx -1 left (-X) or +1 right, front true
-- = smallest Z.
local function pick(list, sx, front, cx)
	local best
	for _, p in ipairs(list) do
		if (p.X < cx) == (sx < 0) then
			if best == nil or (front and p.Z < best.Z) or (not front and p.Z > best.Z) then
				best = p
			end
		end
	end
	return best
end

-- `views`: "full" (ten views) or "rig" (six views, a trailer wheel too).
function Vehicles.cameras(model, cx, cz, views)
	local lo, hi = boundsOf(model)
	local length = hi.Z - lo.Z
	local midZ = (lo.Z + hi.Z) / 2
	local top = math.min(hi.Y, 16)
	local D = length * 1.15 + 14 -- side distance for a 34 degree lens
	local tqD = length * 0.95 + 14
	local cams = {}
	local function add(pos, target, label, fov)
		table.insert(cams, { pos = pos, target = target, label = label, fov = fov or 34 })
	end
	local mid = { cx, top * 0.42, midZ }
	local truckWheels = wheelsOf(model, false)
	local trailerWheels = wheelsOf(model, true)
	local fl = pick(truckWheels, -1, true, cx)
	local rr = pick(truckWheels, 1, false, cx)
	local rl = pick(truckWheels, -1, false, cx)
	local fr = pick(truckWheels, 1, true, cx)
	local tw = pick(trailerWheels, -1, false, cx)
	local function close(p, side, label, dz)
		add({ p.X + side * 11, p.Y + 2.2, p.Z + (dz or -7) }, { p.X, p.Y, p.Z }, label, 40)
	end
	if views == "full" then
		add({ cx, 5.5, lo.Z - length * 0.9 - 16 }, { cx, top * 0.42, midZ }, "front")
		add({ cx - D, 5, midZ }, mid, "left side")
		add({ cx + D, 5, midZ }, mid, "right side")
		add({ cx - tqD * 0.75, top + 5, lo.Z - tqD * 0.7 }, mid, "three-quarter front-left")
		add({ cx + tqD * 0.75, top + 5, hi.Z + tqD * 0.7 }, mid, "three-quarter rear-right")
		close(fl, -1, "front-left wheel close up")
		close(rr, 1, "rear-right wheel close up", 7)
		add({ cx - D, 0.8, midZ }, { cx, 3, midZ }, "low side, ground level", 38)
		add({ cx - tqD * 0.7, 0.8, lo.Z - tqD * 0.7 }, { cx, 3, lo.Z + length * 0.3 }, "low front three-quarter", 40)
		add({ fl.X - 10, 0.6, fl.Z }, { fl.X, fl.Y, fl.Z }, "front-left wheel from the ground", 45)
	else
		add({ cx - D, 5, midZ }, mid, "left side")
		add({ cx + D, 5, midZ }, mid, "right side")
		add({ cx - tqD * 0.75, top + 5, lo.Z - tqD * 0.7 }, mid, "three-quarter front-left")
		add({ cx + tqD * 0.75, top + 5, hi.Z + tqD * 0.7 }, mid, "three-quarter rear-right")
		if tw then
			close(tw, -1, "trailer wheel close up", 7)
		else
			close(rl, -1, "rear-left wheel close up", 7)
		end
		add({ cx - D, 0.8, midZ }, { cx, 3, midZ }, "low side, ground level", 38)
	end
	return cams, { fl = fl, fr = fr, rl = rl, rr = rr }
end

function Vehicles.init(ctx)
	V3 = ctx.roblox.Vector3
end

-- specimens: { { id, truck, trailer?, extras? } ... } -> root, cameras
function Vehicles.build(ctx, specimens, views)
	local roblox = ctx.roblox
	local CF, C3 = roblox.CFrame, roblox.Color3
	V3 = roblox.Vector3
	local Enum = roblox.Enum
	local Kit = ctx.art("Kit")
	local TruckArt = ctx.art("TruckArt")
	local ItemCatalog = ctx.shared("ItemCatalog")
	local root = roblox.Instance.new("Model")
	local cameras = {}
	for i, spec in ipairs(specimens) do
		local cx, cz = (i - 1) * 900, (i - 1) * 500
		local def = ItemCatalog.GetTruck(spec.truck)
		local trailer = if spec.trailer then ItemCatalog.GetTrailer(spec.trailer) else nil
		-- partBuilt: no mesh loads, so the part-built art shows (the fallback while
		-- meshes load, and what the Timber Classic always is).
		local MeshKit = ctx.art("MeshKit")
		local saved = MeshKit.Override
		if spec.partBuilt then
			MeshKit.Override = function()
				return nil
			end
		end
		local model = TruckArt.Build(def, nil, trailer, nil, spec.extras)
		MeshKit.Override = saved
		local lo, hi = boundsOf(model)
		local mid = (lo.Z + hi.Z) / 2
		-- Centre the rig's length on the specimen's origin.
		Kit.placeAt(model, CF.new(cx, 0, cz - mid))
		model.Parent = root
		local lo2, hi2 = boundsOf(model)
		Kit.part(
			root,
			"Floor",
			V3.new(math.max(hi2.Z - lo2.Z + 60, 130), 0.2, math.max(hi2.Z - lo2.Z + 60, 130)),
			CF.new(cx, -0.1, cz),
			C3.fromRGB(232, 228, 220),
			Enum.Material.SmoothPlastic
		)
		local cams = Vehicles.cameras(model, cx, cz, views)
		for _, cam in ipairs(cams) do
			cam.label = spec.id .. " - " .. cam.label
			table.insert(cameras, cam)
		end
	end
	return root, cameras
end

function Vehicles.scene(root, cameras)
	return {
		root = root,
		shadowRadius = 48,
		shadowFollow = true,
		fov = 34,
		background = "#f3f0e8",
		hud = false,
		lighting = LIGHTING,
		cameras = cameras,
	}
end

return Vehicles
