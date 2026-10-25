--!strict
-- Minimal, dependency-free test library for Lune specs.
-- A spec file returns t.spec(name, function(it) ... end).

export type Case = { name: string, fn: () -> () }
export type Spec = { name: string, cases: { Case } }

local t = {}

function t.spec(name: string, body: (it: (string, () -> ()) -> ()) -> ()): Spec
	local cases: { Case } = {}
	body(function(caseName: string, fn: () -> ())
		table.insert(cases, { name = caseName, fn = fn })
	end)
	return { name = name, cases = cases }
end

local function show(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function t.expect(actual: any)
	local e = {}
	function e.toBe(expected: any)
		if actual ~= expected then
			error(`expected {show(expected)}, got {show(actual)}`, 2)
		end
	end
	function e.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(`expected deep-equal values, got {show(actual)}`, 2)
		end
	end
	function e.toBeNear(expected: number, epsilon: number?)
		local eps = epsilon or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > eps then
			error(`expected {expected} ± {eps}, got {show(actual)}`, 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(`expected truthy, got {show(actual)}`, 2)
		end
	end
	function e.toThrow(pattern: string?)
		local ok, err = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
		if pattern and not string.find(tostring(err), pattern) then
			error(`expected error matching {show(pattern)}, got {show(err)}`, 2)
		end
	end
	return e
end

return t
