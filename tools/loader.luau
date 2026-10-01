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
roblox.implementMethod("Model", "GetPivot", modelPivot)
roblox.implementMethod("Model", "PivotTo", function(model, target)
	local delta = target * modelPivot(model):Inverse()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
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
}

local Loader = {}
Loader.__index = Loader

-- Stand-ins for the folders and ModuleScripts under src/, built once up
-- front (Lune's file calls can't run inside the __index metamethod).
-- Folders index their children by name; a missing child is an error, as a
-- typo in `script.Parent.X` would be in Roblox.
local nodes: { [string]: any } = {} -- [path] -> folder node
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
			end
		end
	end
	nodes[dir] = node
	return setmetatable(node, {
		__index = function(_, key)
			error(string.format("[loader] %s has no child %q", dir, tostring(key)), 2)
		end,
	})
end
scan(SRC)

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

function Loader:environment(modulePath: string)
	local dir, name = string.match(modulePath, "^(.*)/([^/]+)%.luau$")
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
		math = math,
		os = os,
		string = string,
		table = table,
		utf8 = utf8,
		-- Roblox datatypes
		BrickColor = roblox.BrickColor,
		CFrame = roblox.CFrame,
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
	local chunk = luau.load(fs.readFile(modulePath), {
		debugName = modulePath,
		environment = self:environment(modulePath),
		injectGlobals = false,
	})
	local result = chunk()
	self.cache[modulePath] = result
	return result
end

-- Loads a module by its path under src/, e.g. "ReplicatedStorage/Shared/Util".
function Loader:load(path: string)
	return self:require(SRC .. "/" .. path .. ".luau")
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
