--!strict
-- c0302 AC3: a fixture that clones a checkout, removes `origin` and runs `./zn start` in the clone names the clone's
-- branch `main` first. Without that, on a stack layer branch (R<NNNN>/<n>/<id>) the clone holds only a layer branch, so
-- `start` finds no main (layergit.mainTip) and refuses with 'no main branch': seven promoted specs were red there for
-- every raft that touched a file they watch. The rule is read from the text of every spec under z-nile/tests (from
-- the checkout's top); that the seven pass on a layer branch is check.sh's one run (AC2), not a promoted case. The
-- needles are built by concatenation so this file is not in its own population. The rule is textual: it sees the two
-- ways today's specs clone (tests/lib/clone's helper and `git clone --no-hardlinks`), whatever the source is called.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local Q = '"'
-- the two ways a spec clones: tests/lib/clone's helper, or git itself; the source's name is not part of the needle
local CLONES = { "clone.isolated" .. "(", Q .. "--no-hardlinks" .. Q .. ", " }
local REMOVES = Q .. "remote" .. Q .. ", " .. Q .. "remove" .. Q .. ", " .. Q .. "origin" .. Q
local STARTS = "{ " .. Q .. "start" .. Q
local NAMES = "{ "
	.. Q
	.. "checkout"
	.. Q
	.. ", "
	.. Q
	.. "-q"
	.. Q
	.. ", "
	.. Q
	.. "-B"
	.. Q
	.. ", "
	.. Q
	.. "main"
	.. Q
	.. " }"

-- the end of a long bracket that opens at `from` (`[[`, `[=[`, …): the index after its close, or nil if none opens
local function long(text: string, from: number): number?
	local eq = string.match(text, "^%[(=*)%[", from)
	if not eq then
		return nil
	end
	local _, to = string.find(text, "]" .. eq .. "]", from + #eq + 2, true)
	return (to or #text) + 1
end

-- the code of a Luau text (pure): line endings made LF and every comment removed, line comments (to the end of the
-- line, the newline kept), block comments (`--[[ ]]`, `--[=[ ]=]`) and trailing ones; strings are kept as they are
local function code(text: string): string
	text = string.gsub(text, "\r\n", "\n")
	local out: { string } = {}
	local i, n = 1, #text
	while i <= n do
		local c = string.sub(text, i, i)
		if string.sub(text, i, i + 1) == "--" then
			local past = long(text, i + 2)
			if past then
				i = past
			else
				i = string.find(text, "\n", i, true) or n + 1
			end
		elseif c == Q or c == "'" or c == "`" then
			local j = i + 1
			while j <= n and string.sub(text, j, j) ~= c and string.sub(text, j, j) ~= "\n" do
				j += if string.sub(text, j, j) == "\\" then 2 else 1
			end
			table.insert(out, string.sub(text, i, j))
			i = j + 1
		else
			local past = if c == "[" then long(text, i) else nil
			if past then
				table.insert(out, string.sub(text, i, past - 1))
				i = past
			else
				table.insert(out, c)
				i += 1
			end
		end
	end
	return table.concat(out)
end

local function after(src: string, needle: string, from: number): number?
	return (string.find(src, needle, from, true))
end

-- where the code clones, in order
local function clones(src: string): { number }
	local found: { number } = {}
	for _, needle in CLONES do
		local from = 1
		while true do
			local at = after(src, needle, from)
			if not at then
				break
			end
			table.insert(found, at)
			from = at + 1
		end
	end
	table.sort(found)
	return found
end

-- whether a spec's text is in the rule's population: it clones, removes origin and runs start (pure)
local function inScope(text: string): boolean
	local src = code(text)
	return #clones(src) > 0 and after(src, REMOVES, 1) ~= nil and after(src, STARTS, 1) ~= nil
end

-- whether a spec in the population names each clone's branch main: for every clone a start follows, a naming stands
-- after that clone and before that start (pure). A naming before the clone, or after the start, is not that clone's.
local function named(text: string): boolean
	local src = code(text)
	for _, at in clones(src) do
		local start = after(src, STARTS, at)
		if start then
			local naming = after(src, NAMES, at)
			if not naming or naming > start then
				return false
			end
		end
	end
	return true
end

-- every .spec.luau under a folder, hidden folders skipped
local function specs(dir: string, out: { string })
	for _, name in fs.readDir(`{root}/{dir}`) do
		if string.sub(name, 1, 1) ~= "." then
			local rel = `{dir}/{name}`
			if fs.isDir(`{root}/{rel}`) then
				specs(rel, out)
			elseif string.match(name, "%.spec%.luau$") then
				table.insert(out, rel)
			end
		end
	end
end

-- the seven this issue fixed, by full path (a compaction rewrites `tests/acceptance/<id>` paths, not a bare id)
local FIXED = {
	"z-nile/tests/acceptance/c0001/tracker-lifecycle.spec.luau",
	"z-nile/tests/acceptance/c0008/done-order.spec.luau",
	"z-nile/tests/acceptance/c0038/deferred.spec.luau",
	"z-nile/tests/acceptance/c0050/start-depends.spec.luau",
	"z-nile/tests/acceptance/c0074/done-gate.spec.luau",
	"z-nile/tests/acceptance/c0080/consequences.spec.luau",
	"z-nile/tests/acceptance/c0120/promote-home.spec.luau",
}

local CLONE = "\t\t" .. CLONES[1] .. "root, dir)\n"
local RAW = "\t\tmust(process.exec("
	.. Q
	.. "git"
	.. Q
	.. ", { "
	.. Q
	.. "clone"
	.. Q
	.. ", "
	.. Q
	.. "-q"
	.. Q
	.. ", "
	.. CLONES[2]
	.. "root, work }))\n"
local REMOVE = "\t\tgit({ " .. REMOVES .. " })\n"
local NAME = "\t\tgit(" .. NAMES .. ")\n"
local START = "\t\tmust(tr(" .. STARTS .. ", " .. Q .. "R0010" .. Q .. " }))\n"

return t.spec("c0302 clone fixtures name their branch main", function(it)
	it("AC3: comments are not code, and strings are", function()
		t.expect(code("a -- b\nc")).toBe("a \nc")
		t.expect(code("a --[[ b\nc ]] d")).toBe("a  d")
		t.expect(code("a --[==[ b ]] c ]==] d")).toBe("a  d")
		t.expect(code('a "--" b -- c')).toBe('a "--" b ')
		t.expect(code("a '\\'--' b")).toBe("a '\\'--' b")
		t.expect(code("a [[ -- b ]] c")).toBe("a [[ -- b ]] c")
		t.expect(code("a\r\nb")).toBe("a\nb")
	end)

	it("AC3: the scan knows a fixture that clones, removes origin and starts", function()
		t.expect(inScope(CLONE .. REMOVE .. START)).toBe(true)
		t.expect(inScope(RAW .. REMOVE .. START)).toBe(true)
		t.expect(inScope((string.gsub(CLONE .. REMOVE .. START, "\n", "\r\n")))).toBe(true)
		-- the checkout by another name is the same fixture
		t.expect(inScope((string.gsub(CLONE, "root", "TOP")) .. REMOVE .. START)).toBe(true)
		t.expect(inScope((string.gsub(RAW, "root", "engine.TOP")) .. REMOVE .. START)).toBe(true)
		-- not the population: no start, no origin removal, or no clone
		t.expect(inScope(CLONE .. REMOVE)).toBe(false)
		t.expect(inScope(CLONE .. START)).toBe(false)
		t.expect(inScope(REMOVE .. START)).toBe(false)
		-- a commented-out line is not code
		t.expect(inScope(CLONE .. REMOVE .. "\t\t-- " .. START)).toBe(false)
		t.expect(inScope(CLONE .. REMOVE .. "--[[\n" .. START .. "]]\n")).toBe(false)
	end)

	it(
		"AC3: the scan passes a named clone and fails an unnamed, a commented-out, a late and an early naming",
		function()
			t.expect(named(CLONE .. REMOVE .. NAME .. START)).toBe(true)
			t.expect(named(CLONE .. NAME .. REMOVE .. START)).toBe(true)
			t.expect(named(RAW .. REMOVE .. NAME .. START .. START)).toBe(true)
			t.expect(named(CLONE .. REMOVE .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. "\t\t-- " .. NAME .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. "\t\t-- why\t" .. NAME .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. "--[[\n" .. NAME .. "]]\n" .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. "--[=[\n" .. NAME .. "]=]\n" .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. "\t\tfs.writeDir(dir) -- " .. NAME .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. START .. NAME)).toBe(false)
			-- a naming in an earlier helper is not this clone's
			t.expect(named(NAME .. CLONE .. REMOVE .. START)).toBe(false)
			-- each clone needs its own: the second fixture here is unnamed
			t.expect(named(CLONE .. REMOVE .. NAME .. START .. RAW .. REMOVE .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. NAME .. START .. RAW .. REMOVE .. NAME .. START)).toBe(true)
			-- a clone no start follows needs none
			t.expect(named(CLONE .. REMOVE .. NAME .. START .. RAW .. REMOVE)).toBe(true)
			-- a naming of another branch, or one that fails when a main exists, is not the rule's
			t.expect(named(CLONE .. REMOVE .. (string.gsub(NAME, "main", "trunk")) .. START)).toBe(false)
			t.expect(named(CLONE .. REMOVE .. (string.gsub(NAME, "%-B", "-b")) .. START)).toBe(false)
		end
	)

	it(
		"AC3: every spec under z-nile/tests that clones, removes origin and starts names its clone's branch main",
		function()
			local files: { string } = {}
			specs("z-nile/tests", files)
			local population: { [string]: boolean } = {}
			local unnamed: { string } = {}
			for _, rel in files do
				local text = fs.readFile(`{root}/{rel}`)
				if inScope(text) then
					population[rel] = true
					if not named(text) then
						table.insert(unnamed, rel)
					end
				end
			end
			table.sort(unnamed)
			t.expect(table.concat(unnamed, " ")).toBe("")
			-- the scan is not blind: the seven fixtures this issue fixed are in its population
			for _, rel in FIXED do
				t.expect(`{rel} {population[rel] == true}`).toBe(`{rel} true`)
			end
		end
	)
end)
