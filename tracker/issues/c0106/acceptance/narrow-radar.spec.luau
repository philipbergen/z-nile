--!strict
-- c0106 AC1: tests/acceptance/d0105/radar.spec.luau accepts f0029's layout and still fails for a real regression.
-- The promoted spec is read as text and loaded with a fake require (a Hud whose layout table may carry f0029's
-- safe-area fields); its narrowed case is run against witnesses it must accept and mutants it must reject.
local Hud = require("@logic/Hud")
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

-- radar.spec --------------------------------------------------------------------------------------------------

local LAYOUT_CASE = "layout's numbers are unchanged"
local FIVE = { "textSize", "margin", "iconSize", "barWidth", "barHeight" }

-- Hud whose layout(w, h) is the real one with `fields` set on top and `drop` removed, over the real radarBox.
local function hudWith(fields: { [string]: number? }, drop: string?): any
	local hud: { [string]: any } = table.clone(Hud :: any)
	hud.layout = function(width: number, height: number): any
		local out: { [string]: any } = table.clone(Hud.layout(width, height) :: any)
		for k, v in fields do
			out[k] = v
		end
		if drop ~= nil then
			out[drop] = nil
		end
		return out
	end
	return hud
end

local function radarSpec(hud: any): Spec
	return loadSpec("radar.spec.luau", { ["@logic/Hud"] = hud, ["@tests/lib/t"] = t })
end

local F0029_LAYOUT: { [string]: number? } = { safeX = 0, safeY = 0, safeW = 1280, safeH = 720 }

local function layoutPasses(fields: { [string]: number? }, drop: string?): boolean
	return passes(caseNamed(radarSpec(hudWith(fields, drop)), LAYOUT_CASE))
end

local REGION_FROM = "\t\tlocal l = Hud.layout(1280, 720)\n"
local REGION_TO = "\n\tend)\n"

return t.spec("c0106 the narrowed d0105 radar spec", function(it)
	it("radar.spec accepts today's layout, so main stays green before f0029", function()
		t.expect(layoutPasses({})).toBe(true)
	end)

	it("radar.spec accepts f0029's layout: the same five numbers plus the safe-area fields", function()
		t.expect(layoutPasses(F0029_LAYOUT)).toBe(true)
	end)

	it("radar.spec still fails when any one of the five layout numbers changes", function()
		for _, field in FIVE do
			local fields: { [string]: number? } = table.clone(F0029_LAYOUT)
			fields[field] = (Hud.layout(1280, 720) :: any)[field] + 1
			t.expect(layoutPasses(fields)).toBe(false)
			fields[field] = (Hud.layout(1280, 720) :: any)[field] - 1
			t.expect(layoutPasses(fields)).toBe(false)
		end
	end)

	it("radar.spec still fails when one of the five numbers is missing", function()
		for _, field in FIVE do
			t.expect(layoutPasses(F0029_LAYOUT, field)).toBe(false)
		end
	end)

	it("radar.spec keeps its seven cases, in order", function()
		t.expect(hasExactly(radarSpec(Hud), {
			"layout's numbers are unchanged",
			"on a 1280 by 720 screen",
			"on a 1920 by 1080 screen",
			"on a 480 by 320 screen",
			"a zero, negative or non-finite size",
			"its right edge matches the margin",
			"the 120-pixel radar is inside the screen",
		})).toBe(true)
	end)

	it("radar.spec is exactly today's file outside the narrowed layout assertion", function()
		local sum, len = fingerprint(fs.readFile(DIR .. "radar.spec.luau"), REGION_FROM, REGION_TO)
		t.expect(sum .. ":" .. len).toBe("331565424:3322")
	end)

	it("the radar fingerprint ignores tracker ids, so a compaction does not move it", function()
		local text = fs.readFile(DIR .. "radar.spec.luau")
		local renumbered = string.gsub(text, "f0019", "f0123")
		t.expect(renumbered ~= text).toBe(true)
		local sum, len = fingerprint(renumbered, REGION_FROM, REGION_TO)
		t.expect(sum .. ":" .. len).toBe("331565424:3322")
	end)
end)
