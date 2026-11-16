--!strict
-- c0106 AC2: tests/acceptance/d0105/adapter.spec.luau accepts f0029's DangerHud and still fails for a real regression.
-- The promoted spec is read as text and loaded with a fake require (a place whose DangerHud source is a given
-- string); its narrowed case is run against witnesses it must accept and mutants it must reject.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local DIR = "tests/" .. "acceptance/" .. renamed.id("d0105") .. "/"

type Case = { name: string, fn: () -> () }
type Spec = { name: string, cases: { Case } }

local GLOBALS: { [string]: any } = {
	string = string,
	table = table,
	math = math,
	type = type,
	tostring = tostring,
	tonumber = tonumber,
	pairs = pairs,
	ipairs = ipairs,
	pcall = pcall,
	error = error,
	assert = assert,
	select = select,
	next = next,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	rawget = rawget,
	rawequal = rawequal,
	print = print,
}

-- Loads one promoted spec with `modules` standing in for its requires and returns its spec table.
local function loadSpec(file: string, modules: { [string]: any }): Spec
	local env = table.clone(GLOBALS)
	env.require = function(path: string): any
		local found = modules[path]
		if found == nil then
			error(`unexpected require of {path}`, 0)
		end
		return found
	end
	local chunk = luau.load(fs.readFile(DIR .. file), { environment = env, debugName = file })
	return chunk() :: Spec
end

local function caseNamed(spec: Spec, prefix: string): Case
	for _, c in spec.cases do
		if string.sub(c.name, 1, #prefix) == prefix then
			return c
		end
	end
	error(`no case starting "{prefix}" in {spec.name}`, 0)
end

local function passes(c: Case): boolean
	return (pcall(c.fn))
end

-- The cases a spec must keep, so narrowing one case cannot drop the others.
local function hasExactly(spec: Spec, prefixes: { string }): boolean
	if #spec.cases ~= #prefixes then
		return false
	end
	for i, prefix in prefixes do
		if string.sub(spec.cases[i].name, 1, #prefix) ~= prefix then
			return false
		end
	end
	return true
end

-- A fingerprint of a text with its replaced region cut out (from `from` up to, not including, the first `upTo`
-- after it) and tracker ids normalised, so any other change to the file moves it and a compaction doesn't.
local function fingerprint(source: string, from: string, upTo: string): (number, number)
	local text = string.gsub(source, "[fdcR]%d%d%d%d", "X")
	local a = string.find(text, from, 1, true)
	assert(a ~= nil, `no region starts with {from}`)
	local b = string.find(text, upTo, a :: number, true)
	assert(b ~= nil, `no region ends before {upTo}`)
	local kept = string.sub(text, 1, (a :: number) - 1) .. string.sub(text, b :: number)
	local sum = 0
	for i = 1, #kept do
		sum = (sum * 31 + string.byte(kept, i)) % 2147483629
	end
	return sum, #kept
end

-- adapter.spec ------------------------------------------------------------------------------------------------

local ADAPTER_CASE = "places the radar from the current screen size"

local OPEN = "\tRunService.RenderStepped:Connect(function()\n"
local VIEW = "\t\tlocal view = gui.AbsoluteSize\n"
local BOX = "\t\tlocal box = Hud.radarBox(view.X, view.Y, radarSize)\n"
local BOX5 =
	"\t\tlocal box = Hud.radarBox(view.X, view.Y, radarSize, UserInputService.TouchEnabled, bandTop())\n"
local POSITION = "\t\tradar.Position = UDim2.fromOffset(box.x, box.y)\n"
local GUARD = "\t\tlocal snap = latest\n\t\tif snap == nil then\n\t\t\treturn\n\t\tend\n"
local CLOSE = "\tend)\n"

local function hudSource(lines: { string }): string
	return "-- DangerHud\nlocal DangerHud = {}\nfunction DangerHud.start()\n"
		.. table.concat(lines)
		.. CLOSE
		.. "end\nreturn DangerHud\n"
end

-- The adapter source with `box` as its radarBox line.
local function withBox(box: string): string
	return hudSource({ OPEN, VIEW, box, POSITION, GUARD })
end

local function adapterPasses(source: string): boolean
	local node = { ClassName = "ModuleScript", Source = source }
	local fake: any = {}
	fake.FindFirstChild = function(_: any, name: string): any
		if name == "DangerHud" then
			return node
		end
		return fake
	end
	local spec = loadSpec("adapter.spec.luau", {
		["@tests/lib/place"] = {
			load = function(): any
				return fake
			end,
		},
		["@tests/lib/t"] = t,
	})
	return passes(caseNamed(spec, ADAPTER_CASE))
end

-- The fingerprint below is of adapter.spec as c0159 narrowed it (2026-10-31: its last case no longer requires
-- Awareness.edgePoint, for f0158's danger ring); before that it was 732226448:2134.
local REGION_FROM = "\t\t\t-- the radarBox call may take"
local REGION_TO = "\t\t\tlocal function count("

return t.spec("c0106 the narrowed d0105 adapter spec", function(it)
	it(
		"adapter.spec accepts today's three-argument radarBox line, so main stays green before f0029",
		function()
			t.expect(adapterPasses(withBox(BOX))).toBe(true)
		end
	)

	it("adapter.spec accepts f0029's final line, with the nested bandTop() call", function()
		t.expect(adapterPasses(withBox(BOX5))).toBe(true)
	end)

	it("adapter.spec rejects a radarBox that takes other first arguments or another size", function()
		for _, call in
			{
				"Hud.radarBox(view.Y, view.X, radarSize)",
				"Hud.radarBox(view.X, view.Y, 120)",
				"Hud.radarBox(view.X, view.Y, radarSizes)",
				"Hud.radarBox(view.X, view.Y)",
				"Hud.radarBox(1280, 720, radarSize)",
				"Hud.radarBox(view.X, view.Y, radarSize, bandTop())",
			}
		do
			local ok = adapterPasses(withBox("\t\tlocal box = " .. call .. "\n"))
			-- the last one is f0029's shape without the touch argument: a prefix match accepts any tail
			t.expect(ok).toBe(call == "Hud.radarBox(view.X, view.Y, radarSize, bandTop())")
		end
	end)

	it("adapter.spec rejects a block whose box is not the local the Position line reads", function()
		t.expect(adapterPasses(withBox("\t\tlocal b = Hud.radarBox(view.X, view.Y, radarSize)\n")))
			.toBe(false)
	end)

	it("adapter.spec rejects a missing, altered or detached radar.Position line", function()
		local altered = "\t\tradar.Position = UDim2.fromOffset(box.y, box.x)\n"
		t.expect(adapterPasses(hudSource({ OPEN, VIEW, BOX5, GUARD }))).toBe(false)
		t.expect(adapterPasses(hudSource({ OPEN, VIEW, BOX5, altered, GUARD }))).toBe(false)
		t.expect(adapterPasses(hudSource({ OPEN, VIEW, BOX5, GUARD, POSITION }))).toBe(false)
		t.expect(adapterPasses(hudSource({ OPEN, VIEW, BOX5, "\t\tlocal x = 1\n", POSITION, GUARD })))
			.toBe(false)
	end)

	it("adapter.spec rejects a block that is not first in the render step", function()
		t.expect(adapterPasses(hudSource({ OPEN, GUARD, VIEW, BOX5, POSITION }))).toBe(false)
		t.expect(adapterPasses(hudSource({ OPEN, VIEW, "\t\tlocal x = 1\n", BOX5, POSITION, GUARD })))
			.toBe(false)
	end)

	it("adapter.spec still counts exactly one radar.Position and one local view", function()
		t.expect(adapterPasses(hudSource({ OPEN, VIEW, BOX5, POSITION, GUARD, POSITION }))).toBe(false)
		t.expect(adapterPasses(hudSource({ OPEN, VIEW, BOX5, POSITION, GUARD, VIEW }))).toBe(false)
	end)

	it("adapter.spec keeps its four cases, in order", function()
		local spec = loadSpec("adapter.spec.luau", {
			["@tests/lib/place"] = {
				load = function(): any
					return {}
				end,
			},
			["@tests/lib/t"] = t,
		})
		t.expect(hasExactly(spec, {
			ADAPTER_CASE,
			"the old top-right corner is gone",
			"the chat stays on",
			"it still draws the radar Awareness computes",
		})).toBe(true)
	end)

	it("adapter.spec is exactly today's file outside the narrowed radarBox assertion", function()
		local sum, len = fingerprint(fs.readFile(DIR .. "adapter.spec.luau"), REGION_FROM, REGION_TO)
		t.expect(sum .. ":" .. len).toBe("1671723699:2275")
	end)

	it("the adapter fingerprint ignores tracker ids, so a compaction does not move it", function()
		local text = fs.readFile(DIR .. "adapter.spec.luau")
		local renumbered = string.gsub(text, "d0105", "d0123")
		t.expect(renumbered ~= text).toBe(true)
		local sum, len = fingerprint(renumbered, REGION_FROM, REGION_TO)
		t.expect(sum .. ":" .. len).toBe("1671723699:2275")
	end)
end)
