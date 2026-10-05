--!nocheck
-- Loads game modules outside Roblox, so tests (tests/run.luau) and tools
-- (tools/economy.luau) can run them with Lune.
--
-- Each module is loaded from src/ with a small fake of what Roblox gives it:
--   * `script.Parent.X` and `game:GetService("ReplicatedStorage").Shared.X`
--     resolve to files under src/, and `require` loads them (once each, like
--     Roblox, per Loader).
--   * `game:GetService` returns stubs for the few services the testable
--     modules touch (HttpService, RunService, AnalyticsService); pass more
--     in `services`.
--   * Roblox datatypes (Vector3, Color3, CFrame, Enum, Instance, ...) come
--     from @lune/roblox, plus the few Model/Part methods it lacks (GetPivot,
--     PivotTo, GetBoundingBox, ...) so the art modules (Shared/Art) can build
--     real Models here (tests, tools/preview).
--   * `mocks` replaces whole modules by name, e.g. { ProfileService = fake }.
--   * `globals` overrides globals, e.g. { os = { clock = fakeClock } }.
--   * `loader:run(path)` runs a Script (Name.server.luau) the same way, e.g.
--     MapBuilder with its heavy modules mocked (tests/MapBuilder.spec.luau).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

-- Roblox methods that @lune/roblox doesn't have, so art modules that build
-- Models (Shared/Art) can run here too. Applied once per process; they
-- cover what the art code uses, not the whole API.
local function boundingBox(model)
	local minV, maxV
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = cf * roblox.Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
						minV = if minV then minV:Min(p) else p
						maxV = if maxV then maxV:Max(p) else p
					end
				end
			end
		end
	end
	if not minV then
		return roblox.CFrame.identity, roblox.Vector3.zero
	end
	return roblox.CFrame.new((minV + maxV) / 2), maxV - minV
end
local function modelPivot(model)
	local primary = model.PrimaryPart
	if primary then
		return primary.CFrame
	end
	return model:GetAttribute("__pivot") or (boundingBox(model))
end
-- A seated character is welded into the truck. PivotTo on that character
-- has to carry the seat's assembly, or a spec can't see the second shove.
-- Only seat joints: ordinary welds (a log on a bed, an axe head) stay put.
local function isSeatJoint(joint)
	if joint.Name == "SeatWeld" then
		return true
	end
	local a, b = joint.Part0, joint.Part1
	return (typeof(a) == "Instance" and a:IsA("VehicleSeat")) or (typeof(b) == "Instance" and b:IsA("VehicleSeat"))
end

local function carrySeat(joint, delta, moved, queue)
	for _, other in ipairs({ joint.Part0, joint.Part1 }) do
		if typeof(other) == "Instance" and other:IsA("BasePart") and not moved[other] and not other.Anchored then
			other.CFrame = delta * other.CFrame
			moved[other] = true
			table.insert(queue, other)
		end
	end
end

roblox.implementMethod("Model", "GetPivot", modelPivot)
roblox.implementMethod("Model", "PivotTo", function(model, target)
	local delta = target * modelPivot(model):Inverse()
	local moved = {}
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
			moved[d] = true
		elseif (d:IsA("Weld") or d:IsA("WeldConstraint")) and isSeatJoint(d) then
			table.insert(joints, d)
		end
	end
	-- Parts of this model are already placed. A seat joint inside it must
	-- not move them again; it only pulls parts that live outside.
	local queue = {}
	for _, joint in ipairs(joints) do
		carrySeat(joint, delta, moved, queue)
	end
	local head = 1
	while head <= #queue do
		local part = queue[head]
		head += 1
		for _, d in ipairs(part:GetDescendants()) do
			if (d:IsA("Weld") or d:IsA("WeldConstraint")) and isSeatJoint(d) then
				carrySeat(d, delta, moved, queue)
			end
		end
	end
	if not model.PrimaryPart then
		model:SetAttribute("__pivot", target)
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", boundingBox)
roblox.implementMethod("Model", "GetExtentsSize", function(model)
	local _, size = boundingBox(model)
	return size
end)
roblox.implementMethod("BasePart", "GetPivot", function(part)
	return part.CFrame
end)
roblox.implementMethod("BasePart", "PivotTo", function(part, target)
	part.CFrame = target
end)
roblox.implementMethod("Instance", "WaitForChild", function(inst, name)
	return inst:FindFirstChild(name)
end)

local SRC = "src"
local SERVICE_FOLDERS = {
	ReplicatedStorage = SRC .. "/ReplicatedStorage",
	ServerScriptService = SRC .. "/ServerScriptService",
}

export type Options = {
	mocks: { [string]: any }?,
	services: { [string]: any }?,
	globals: { [string]: any }?,
	isolated: boolean?,
}

local Loader = {}
Loader.__index = Loader

-- Stand-ins for the folders and ModuleScripts under src/, built once up
-- front (Lune's file calls can't run inside the __index metamethod).
-- Folders index their children by name; a missing child is an error, as a
-- typo in `script.Parent.X` would be in Roblox.
local nodes: { [string]: any } = {} -- [path] -> folder node
local pathsByName: { [string]: { string } } = {} -- module name -> its path(s)
local function scan(dir: string, parent: any?)
	local node = { __path = dir, Parent = parent }
	for _, entry in ipairs(fs.readDir(dir)) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			node[entry] = scan(full, node)
		else
			-- ModuleScripts only: Name.luau, not Name.server.luau / Name.client.luau.
			local name = string.match(entry, "^([^%.]+)%.luau$")
			if name then
				node[name] = { __module = full, Name = name }
				local same = pathsByName[name]
				if not same then
					same = {}
					pathsByName[name] = same
				end
				table.insert(same, full)
			end
		end
	end
	nodes[dir] = node
	-- A folder's own lookups (a script waiting for its siblings): the child,
	-- or nil.
	local function lookup(self: any, name: string): any
		return rawget(self, name)
	end
	return setmetatable(node, {
		__index = function(_, key)
			if key == "WaitForChild" or key == "FindFirstChild" then
				return lookup
			end
			error(string.format("[loader] %s has no child %q", dir, tostring(key)), 2)
		end,
	})
end
scan(SRC)

-- Sharing built modules between Loaders.
--
-- Building the world is the slow part of most specs (WorldLayout plans
-- every homestead's lane; WorldPlan places thousands of trees), and a spec
-- that makes a Loader per test would pay for it each time. So the world's
-- own modules (SHARED_MODULES) are built once per process and handed to
-- every Loader that would build them the same way. A Loader takes the
-- shared one only when all of these hold:
--   * the module's whole require closure (found from the sources) lies
--     under ReplicatedStorage/Shared, uses game only as
--     game:GetService("X") and never calls warn (a Loader keeps its own
--     warnings), and
--   * the Loader overrides no globals, gives no service the closure asks
--     for, and mocks nothing in the closure, so the module sees exactly
--     what it would see in a fresh Loader.
-- Nothing else is shared: a spec that sets fields on a module (WorldTime's
-- NightSpeed, MeshKit.Override) keeps that to its own Loader.
-- Pass `isolated = true` in the options to build everything fresh.
local SHARED_ROOT = SRC .. "/ReplicatedStorage/Shared/"
local FORBIDDEN = { "game", "warn" } -- (workspace, task and the like only matter when a Loader gives globals)

local sourceOf: { [string]: string } = {}
local function sourceText(path: string): string
	local cached = sourceOf[path]
	if cached then
		return cached
	end
	local text = fs.readFile(path)
	sourceOf[path] = text
	return text
end

type Closure = {
	names: { [string]: boolean },
	paths: { [string]: boolean },
	services: { [string]: boolean }, -- game:GetService("X") names the closure asks for
	ok: boolean,
	why: string?,
}
local closures: { [string]: Closure } = {}
local function closureOf(root: string): Closure
	local known = closures[root]
	if known then
		return known
	end
	local closure: Closure = { names = {}, paths = {}, services = {}, ok = true, why = nil }
	local queue = { root }
	closure.paths[root] = true
	local head = 1
	while head <= #queue do
		local path = queue[head]
		head += 1
		closure.names[string.match(path, "([^/]+)%.luau$")] = true
		if string.sub(path, 1, #SHARED_ROOT) ~= SHARED_ROOT then
			closure.ok = false
			closure.why = closure.why or ("outside Shared: " .. path)
			continue
		end
		-- Comments out, so a word in one doesn't count.
		local text = string.gsub(sourceText(path), "%-%-[^\n]*", "")
		-- game:GetService("X") is fine (the Loader's stubs, unless it is
		-- given its own X: see canShare); any other use of game is not.
		local servicePattern = 'game%s*:%s*GetService%s*%(%s*"([%w_]+)"%s*%)'
		for service in string.gmatch(text, servicePattern) do
			closure.services[service] = true
		end
		text = string.gsub(text, servicePattern, "")
		for _, word in ipairs(FORBIDDEN) do
			if string.find(text, "%f[%w_]" .. word .. "%f[^%w_]") then
				closure.ok = false
				closure.why = closure.why or (path .. " uses " .. word)
			end
		end
		for target in string.gmatch(text, "require%s*%(([^%)]*)%)") do
			local name = string.match(target, "([%w_]+)%s*$")
			local found = name and pathsByName[name]
			if not found then
				closure.ok = false
				continue
			end
			for _, dep in ipairs(found) do
				if not closure.paths[dep] then
					closure.paths[dep] = true
					table.insert(queue, dep)
				end
			end
		end
	end
	closures[root] = closure
	return closure
end

-- The world's modules: pure plans and terrain, built from fixed data.
local SHARED_MODULES = { "WorldLayout", "TerrainGen", "TreeFill", "WorldPlan" }
local shareable: { [string]: boolean } = {}
for _, name in ipairs(SHARED_MODULES) do
	shareable[SHARED_ROOT .. "World/" .. name .. ".luau"] = true
end

-- A module that is handed its dependencies (TreeFill.Bind, run by
-- WorldPlan) is only shared along with the module that binds it: shared
-- with a WorldPlan this Loader doesn't share, it would end up bound to
-- the wrong one.
local binders: { [string]: { string } } = {}
for path in pairs(shareable) do
	for target in string.gmatch(sourceText(path), "([%w_]+)%.Bind%s*%(") do
		for _, bound in ipairs(pathsByName[target] or {}) do
			if shareable[bound] and bound ~= path then
				binders[bound] = binders[bound] or {}
				table.insert(binders[bound], path)
			end
		end
	end
end

local sharedCache: { [string]: any } = {}

local function ref(path: string)
	return assert(nodes[path], "[loader] no folder " .. path)
end

local guidCounter = 0
local function defaultServices()
	return {
		HttpService = {
			GenerateGUID = function()
				guidCounter += 1
				return string.format("guid-%04d", guidCounter)
			end,
		},
		RunService = {
			IsStudio = function()
				return false
			end,
			IsServer = function()
				return true
			end,
		},
		AnalyticsService = setmetatable({}, {
			__index = function()
				return function() end -- every Log* call is a no-op
			end,
		}),
		-- Tags live on the instances themselves (@lune/roblox supports them).
		CollectionService = {
			AddTag = function(_, inst, tag)
				inst:AddTag(tag)
			end,
			HasTag = function(_, inst, tag)
				return inst:HasTag(tag)
			end,
			RemoveTag = function(_, inst, tag)
				inst:RemoveTag(tag)
			end,
		},
		-- Skinned cards preload their image. A real client reports Success
		-- or Failure; here the image loads, and a spec can pass its own.
		ContentProvider = {
			PreloadAsync = function(_, _, callback)
				if callback then
					callback("", roblox.Enum.AssetFetchStatus.Success)
				end
			end,
		},
	}
end

function Loader.new(options: Options?)
	local self = setmetatable({}, Loader)
	self.options = options or {}
	self.cache = {}
	self.warnings = {}
	self.services = defaultServices()
	for name, folder in pairs(SERVICE_FOLDERS) do
		self.services[name] = ref(folder)
	end
	for name, service in pairs(self.options.services or {}) do
		self.services[name] = service
	end
	return self
end

-- Lune 0.10.5 builds CFrame.lookAt and CFrame.new(pos, lookAt) wrong (the
-- look direction comes out flipped, diagonal targets lose their pitch), so
-- modules get a CFrame with Roblox's behaviour for those two.
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return roblox.CFrame.new(at)
	end
	look = look.Unit
	up = up or roblox.Vector3.new(0, 1, 0)
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.new(0, 0, 1)) -- looking straight up or down
	end
	right = right.Unit
	return roblox.CFrame.fromMatrix(at, right, right:Cross(look), -look)
end

local CFrameShim = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return roblox.CFrame.new(...)
	end,
}, { __index = roblox.CFrame })

function Loader:environment(modulePath: string)
	local dir, name = string.match(modulePath, "^(.*)/([^/]+)%.luau$")
	name = string.match(name, "^([^%.]+)") -- a Script's Name drops .server / .client
	local services = self.services
	local env = {
		-- Luau standard library
		assert = assert,
		error = error,
		getmetatable = getmetatable,
		ipairs = ipairs,
		next = next,
		pairs = pairs,
		pcall = pcall,
		print = function() end, -- modules' logging stays out of test output
		rawequal = rawequal,
		rawget = rawget,
		rawlen = rawlen,
		rawset = rawset,
		select = select,
		setmetatable = setmetatable,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		typeof = typeof,
		unpack = table.unpack,
		xpcall = xpcall,
		bit32 = bit32,
		buffer = buffer,
		coroutine = coroutine,
		debug = debug,
		math = math,
		os = os,
		string = string,
		table = table,
		utf8 = utf8,
		-- Roblox datatypes
		BrickColor = roblox.BrickColor,
		CFrame = CFrameShim,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		Enum = roblox.Enum,
		Font = roblox.Font,
		Instance = roblox.Instance,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		Rect = roblox.Rect,
		Region3 = roblox.Region3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		-- Roblox globals
		warn = function(...)
			table.insert(self.warnings, table.concat({ ... }, " "))
		end,
		script = { Name = name, Parent = ref(dir) },
		game = {
			GetService = function(_, serviceName)
				local service = services[serviceName]
				if service == nil then
					error("[loader] no stub for game:GetService(" .. tostring(serviceName) .. ")", 2)
				end
				return service
			end,
		},
		require = function(module)
			if type(module) ~= "table" or module.__module == nil then
				error("[loader] require() expects a module reference, got " .. tostring(module), 2)
			end
			return self:require(module.__module)
		end,
	}
	for key, value in pairs(self.options.globals or {}) do
		env[key] = value
	end
	return env
end

-- Whether this Loader may take `modulePath` from, and add it to, the shared
-- cache (see "Sharing built modules between Loaders" above).
function Loader:canShare(modulePath: string): boolean
	if not shareable[modulePath] or self.options.isolated or next(self.options.globals or {}) ~= nil then
		return false
	end
	local closure = closureOf(modulePath)
	if not closure.ok then
		return false
	end
	for name in pairs(self.options.mocks or {}) do
		if closure.names[name] then
			return false
		end
	end
	for name in pairs(self.options.services or {}) do
		if closure.services[name] then
			return false
		end
	end
	for _, binder in ipairs(binders[modulePath] or {}) do
		if not self:canShare(binder) then
			return false
		end
	end
	return true
end

-- Why a module's closure can't be shared (for debugging), or nil.
function Loader.whyNot(modulePath: string): string?
	return closureOf(modulePath).why
end

function Loader:require(modulePath: string)
	local name = string.match(modulePath, "([^/]+)%.luau$")
	local mock = self.options.mocks and self.options.mocks[name]
	if mock ~= nil then
		return mock
	end
	local cached = self.cache[modulePath]
	if cached ~= nil then
		return cached
	end
	local shareable = self:canShare(modulePath)
	if shareable then
		local global = sharedCache[modulePath]
		if global ~= nil then
			self.cache[modulePath] = global
			return global
		end
	end
	local chunk = luau.load(fs.readFile(modulePath), {
		debugName = modulePath,
		environment = self:environment(modulePath),
		injectGlobals = false,
	})
	local result = chunk()
	self.cache[modulePath] = result
	if shareable then
		sharedCache[modulePath] = result
	end
	return result
end

-- Loads a module by its path under src/, e.g. "ReplicatedStorage/Shared/Util".
function Loader:load(path: string)
	return self:require(SRC .. "/" .. path .. ".luau")
end

-- Runs a Script by its path under src/, e.g. "ServerScriptService/MapBuilder.server".
-- Scripts return nothing; their effects land on the fakes passed in
-- (services, globals, mocks). Each call runs the script again.
function Loader:run(path: string)
	local scriptPath = SRC .. "/" .. path .. ".luau"
	local chunk = luau.load(fs.readFile(scriptPath), {
		debugName = scriptPath,
		environment = self:environment(scriptPath),
		injectGlobals = false,
	})
	chunk()
end

-- Shorthand for a module in ReplicatedStorage/Shared.
function Loader:shared(name: string)
	return self:load("ReplicatedStorage/Shared/" .. name)
end

-- Shorthand for a module in ServerScriptService.
function Loader:server(name: string)
	return self:load("ServerScriptService/" .. name)
end

return Loader
