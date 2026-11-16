--!strict
-- c0193 AC3: hostile.finishes runs scanners over hostile texts in a child bounded by c0191's runner. It passes a
-- scanner that returns (or refuses some texts by raising), and fails, within its limit, one that never returns (naming
-- the case and the block of texts it stopped in), one whose call never reaches its work (a witness that fails, or a
-- case that raised on every non-empty text) and a crash (naming its code). Fixtures are written and removed by the
-- helper under this home's .cache. The runner's own behaviour (group kill, signals, CPU limit) is c0191's to spec.
local fs = require("@lune/fs")
local hostile = require("@tests/lib/hostile")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))

-- a scanner shaped like raftcheck's word() when PR #125 shipped: the stop helper returns its start on a backslash
local SPINS = [[
local m = {}
local function stop(text, i)
	local j = i
	while j <= #text and string.sub(text, j, j) ~= " " and string.sub(text, j, j) ~= "\\" do
		j += 1
	end
	return j
end
function m.scan(text)
	local i = 1
	while i <= #text do
		if string.sub(text, i, i) == " " then
			i += 1
		else
			i = stop(text, i)
		end
	end
end
return m
]]

-- the same scanner with the fail-closed step
local CLOSED = [[
local scan = ]] .. "re" .. [[quire("@znile/engine/scan")
local m = {}
local function stop(text, i)
	local j = i
	while j <= #text and string.sub(text, j, j) ~= " " and string.sub(text, j, j) ~= "\\" do
		j += 1
	end
	return j
end
function m.scan(text)
	local i = 1
	while i <= #text do
		if string.sub(text, i, i) == " " then
			i += 1
		else
			i = scan.advance(i, stop(text, i))
		end
	end
end
return m
]]

-- refuses the texts with a backslash, as a scanner that fails closed on what it will not read
local REFUSES = [[
local m = {}
function m.scan(text)
	if string.find(text, "\\", 1, true) then
		error("refused: " .. text)
	end
end
return m
]]

-- raises on every text: its call never reaches the scanner's loop (a typo, a guard on its input)
local NEVER_RUNS = [[
local m = {}
function m.scan(text)
	error("no such thing")
end
return m
]]

-- raises unless the text starts with a header, as raftcheck.judge refuses text without the raft template's head
local NEEDS_HEAD = [[
local m = {}
function m.scan(text)
	if string.sub(text, 1, 5) ~= "HEAD:" then
		error("no head")
	end
	return "ok"
end
return m
]]

-- raises on every non-empty text, returning only for the empty one (an argument of the wrong shape)
local ONLY_EMPTY = [[
local m = {}
function m.scan(text)
	if text ~= "" then
		error("signature changed")
	end
	return ""
end
return m
]]

-- ignores its input: a call that never reaches the scanner's work gives the same result for every text
local IGNORES = [[
local m = {}
function m.scan(text)
	return "x"
end
return m
]]

-- adds one for every word: the witness "a b" gives "2"
local COUNTS = [[
local m = {}
function m.scan(text)
	local n = 0
	for _ in string.gmatch(text, "[^ ]+") do
		n += 1
	end
	return n
end
return m
]]

-- ends the whole process with code 3 on one text (a crash, not a hang); the require text is built in parts
local CRASHES = "local process = "
	.. "re"
	.. 'quire("@lune/process")\n'
	.. "local m = {}\nfunction m.scan(text)\n\tif text == 'x' then process.exit(3) end\nend\nreturn m\n"

local FINE = [[
local m = {}
function m.scan(text)
	local n = 0
	for _ in string.gmatch(text, "[^ ]+") do
		n += 1
	end
	return n
end
return m
]]

local function cases(...: hostile.Case): { hostile.Case }
	return { ... }
end

-- texts of which the 20th is the first with a backslash
local function mostlyPlain(): { string }
	local out: { string } = {}
	for i = 1, 40 do
		table.insert(out, if i == 20 then "ab\\cd" else `t{i}`)
	end
	return out
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0193 hostile.finishes", function(it)
	it(
		"passes scanners that return on the texts, including one that refuses some and one with a witness",
		function()
			local r = hostile.finishes(
				"c0193-fine",
				cases(
					{ name = "fine", call = "m.scan(text)", source = FINE },
					{ name = "refuses", call = "m.scan(text)", source = REFUSES },
					{ name = "closed", call = "m.scan(text)", source = CLOSED },
					{
						name = "counts",
						call = "m.scan(text)",
						source = COUNTS,
						witness = { text = "a b", result = "2" },
					},
					{
						name = "graph.stripComments",
						call = "m.stripComments(text)",
						module = "@znile/lib/graph",
						witness = { text = "a --c\nb", result = "a \nb" },
					}
				)
			)
			t.expect(r.message).toBe("")
			t.expect(r.ok).toBe(true)
			t.expect(fs.isDir(`{root}/.cache/hostile-c0193-fine`)).toBe(false)
		end
	)

	it("fails a scanner that never returns, naming the case and the block of texts it stopped in", function()
		local r = hostile.finishes(
			"c0193-spins",
			cases(
				{ name = "fine", call = "m.scan(text)", source = FINE },
				{ name = "spins", call = "m.scan(text)", source = SPINS }
			),
			mostlyPlain(),
			3
		)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.message, "spins: did not finish within 3 s")).toBe(true)
		t.expect(has(r.message, "texts 17..32 of 40")).toBe(true)
		t.expect(has(r.message, '"ab\\\\cd"')).toBe(true)
		t.expect(has(r.message, "fine: did not")).toBe(false)
		-- the hung child has ended (the call returned) and its folder is gone
		t.expect(fs.isDir(`{root}/.cache/hostile-c0193-spins`)).toBe(false)
	end)

	it("names the witness when a scanner hangs on it, before any text ran", function()
		local r = hostile.finishes(
			"c0193-witspin",
			cases({
				name = "witspin",
				call = "m.scan(text)",
				source = SPINS,
				witness = { text = "ab\\cd", result = "nil" },
			}),
			{ "a", "b" },
			3
		)
		t.expect(r.ok).toBe(false)
		t.expect(
			has(
				r.message,
				'witspin: did not finish within 3 s; it stopped in its witness "ab\\\\cd", before any text ran'
			)
		).toBe(true)
		t.expect(has(r.message, "texts 1..")).toBe(false)
	end)

	it("fails a case that raised on every text, because its scanner never ran", function()
		local r = hostile.finishes(
			"c0193-never",
			cases({ name = "never", call = "m.scan(text)", source = NEVER_RUNS }),
			{ "a", "b" }
		)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.message, "never: raised on every text, so the sweep never ran it")).toBe(true)
		t.expect(has(r.message, "no such thing")).toBe(true)
		local typo = hostile.finishes(
			"c0193-typo",
			cases({ name = "typo", call = "m.stripCommentz(text)", module = "@znile/lib/graph" }),
			{ "a", "b" }
		)
		t.expect(typo.ok).toBe(false)
	end)

	it("fails a case that returned only on the empty text", function()
		local r = hostile.finishes(
			"c0193-empty",
			cases({ name = "only-empty", call = "m.scan(text)", source = ONLY_EMPTY }),
			hostile.texts({ "a", "b" }, 2)
		)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.message, "only-empty: raised on every text")).toBe(true)
	end)

	it("fails a case whose witness gives another result, and one whose call raises on the witness", function()
		local ignores = hostile.finishes(
			"c0193-wit",
			cases({
				name = "ignores",
				call = "m.scan(text)",
				source = IGNORES,
				witness = { text = "a b c", result = "3" },
			}),
			{ "a", "b" }
		)
		t.expect(ignores.ok).toBe(false)
		t.expect(has(ignores.message, 'ignores: its witness gave "x", not "3"')).toBe(true)
		t.expect(has(ignores.message, "does not reach the scanner's work")).toBe(true)
		local raises = hostile.finishes(
			"c0193-wit2",
			cases({
				name = "raises",
				call = "m.stripCommentz(text)",
				module = "@znile/lib/graph",
				witness = { text = "a", result = "a" },
			}),
			{ "a", "b" }
		)
		t.expect(raises.ok).toBe(false)
		t.expect(has(raises.message, "raises: its witness gave")).toBe(true)
	end)

	it("puts a case's prefix before every text, so a scanner with an entry guard is reached", function()
		local without = hostile.finishes(
			"c0193-head",
			cases({ name = "head", call = "m.scan(text)", source = NEEDS_HEAD }),
			{ "a", "b" }
		)
		t.expect(without.ok).toBe(false)
		local with = hostile.finishes(
			"c0193-head2",
			cases({
				name = "head",
				call = "m.scan(text)",
				source = NEEDS_HEAD,
				prefix = "HEAD:",
				witness = { text = "x", result = "ok" },
			}),
			{ "a", "b" }
		)
		t.expect(with.message).toBe("")
		t.expect(with.ok).toBe(true)
	end)

	it("reports a driver that dies with its own code as a crash, not as a timeout", function()
		local r = hostile.finishes(
			"c0193-crash",
			cases({ name = "crash", call = "m.scan(text)", source = CRASHES }),
			{ "a", "x", "b" }
		)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.message, "crash: the driver ended with code 3")).toBe(true)
		t.expect(has(r.message, "did not finish")).toBe(false)
	end)

	it("fails, rather than passes, when the driver cannot run (a module that does not exist)", function()
		local r = hostile.finishes(
			"c0193-nomodule",
			cases({ name = "missing", call = "m.scan(text)", module = "@znile/engine/no-such-module" }),
			{ "a" }
		)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.message, "the sweep driver could not run")).toBe(true)
	end)

	it(
		"refuses, before starting anything, a limit that is not a whole number of seconds from 1 to 3600",
		function()
			local one = cases({ name = "f", call = "m.scan(text)", source = FINE })
			for _, bad in { 0.5, 0, -1, 1.5, 3601, math.huge, 0 / 0 } do
				t.expect(function()
					hostile.finishes("c0193-limit", one, { "a" }, bad)
				end).toThrow("whole number of seconds from 1 to 3600")
			end
			t.expect(fs.isDir(`{root}/.cache/hostile-c0193-limit`)).toBe(false)
		end
	)

	it(
		"refuses an empty list of texts, or only the empty text, and a name that is not a folder name",
		function()
			local one = cases({ name = "f", call = "m.scan(text)", source = FINE })
			t.expect(function()
				hostile.finishes("c0193-none", one, {})
			end).toThrow("no text to run")
			t.expect(function()
				hostile.finishes("c0193-none", one, { "" })
			end).toThrow("no text to run")
			t.expect(function()
				hostile.finishes("../escape", one, { "a" })
			end).toThrow("letters, digits and hyphens")
		end
	)

	it("refuses a case with both or neither of module and source", function()
		t.expect(function()
			hostile.finishes(
				"c0193-both",
				cases({ name = "x", call = "m.f(text)", module = "@znile/engine/scan", source = FINE }),
				{ "a" }
			)
		end).toThrow("exactly one of module and source")
		t.expect(function()
			hostile.finishes("c0193-neither", cases({ name = "x", call = "m.f(text)" }), { "a" })
		end).toThrow("exactly one of module and source")
		t.expect(fs.isDir(`{root}/.cache/hostile-c0193-both`)).toBe(false)
	end)
end)
