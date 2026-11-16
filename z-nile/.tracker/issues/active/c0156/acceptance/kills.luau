--!strict
-- c0156 AC7: each whole-file pin's own verdict rejects every comment-join and deleted-assertion mutant of each file it
-- pins, and accepts the file as it is and in its CRLF form. The pins (c0128's golden.spec, c0103's narrowed.spec) are
-- loaded as they are in the checkout and run case by case, with the files they read served by this script: the file under
-- test mutated in memory, every other read answered from the checkout. So the check is outside the pin: a pin whose
-- comparison was weakened, whose "exactly" case was dropped, that compares the wrong file or that answers only a known
-- list of mutants or that measures only a statistic of the text accepts one, and a mutant counts as killed only by an assertion of the pin ("expected true, got false"
-- from any case), not by a helper that raised (a join whose comment is gone). The mutants are derived from each pinned
-- file, not listed, in two families: those that remove a line (every line that holds `t.expect(` deleted, every line that
-- holds `--` joined to a non-blank next line) and those that keep the line count (every assertion line commented out in
-- place, and one same-length edit of every non-blank line: two adjacent characters swapped, or one replaced), all raw LF
-- text, plus the record's join entries (`mutants.py --joins`). The pins run unjailed inside this script, with an
-- explicit environment (no injected globals: only the listed ones and the one `require`), so a pin cannot reach the
-- real modules. Run by check.sh only, as it reads
-- pickman's files (see scripted.luau).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local pin = require("@tests/lib/pin")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local scripted = require("./scripted")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = scripted.top()
local PICKMAN = `{TOP}/pickman`
-- spelled in two parts so a compaction does not rewrite the paths; the ids are mapped through the compaction map
local ACC = "tests/" .. "acceptance/"
local RECORD = `{TOP}/pickman/.tracker/rafts/done/{renamed.id("R0045")}/experiments/mutants.py`

-- the pin spec and the files it pins (home-relative, as the pin reads them)
local PINS = {
	{
		spec = ACC .. renamed.id("c0103") .. "/narrowed.spec.luau",
		files = { ACC .. renamed.id("f0014") .. "/keys.spec.luau" },
	},
	{
		spec = ACC .. renamed.id("c0128") .. "/golden.spec.luau",
		files = {
			ACC .. renamed.id("f0024") .. "/adapter.spec.luau",
			ACC .. renamed.id("f0026") .. "/adapters.spec.luau",
		},
	},
}

type Join = { name: string, path: string, old: string, new: string }
type Run = { total: number, failed: { string } }

local function readPickman(rel: string): string
	return fs.readFile(`{PICKMAN}/{rel}`)
end

-- load a spec's source and run every case of it, with `served` answering reads of the files under test
local function runSource(source: string, name: string, served: { [string]: string }): Run
	local fakeFs = {
		readFile = function(path: string): string
			return served[path] or readPickman(path)
		end,
		isFile = function(path: string): boolean
			return fs.isFile(`{PICKMAN}/{path}`)
		end,
	}
	local modules: { [string]: any } = {
		["@tests/lib/pin"] = pin,
		["@tests/lib/renamed"] = renamed,
		["@tests/lib/t"] = t,
		["@lune/fs"] = fakeFs,
	}
	-- the globals a pin may use; no others are injected (injectGlobals = false), so `getfenv(0).require` is not there
	local env: { [string]: any } = {
		require = function(wanted: string): any
			local module = modules[wanted]
			if module == nil then
				error(
					`the pin requires {wanted}: kills.luau supplies only @tests/lib/pin, renamed, t and @lune/fs`
				)
			end
			return module
		end,
		assert = assert,
		error = error,
		ipairs = ipairs,
		math = math,
		next = next,
		pairs = pairs,
		pcall = pcall,
		select = select,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		string = string,
		table = table,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		typeof = typeof,
		utf8 = utf8,
		xpcall = xpcall,
	}
	local loaded, result = pcall(function(): t.Spec
		local chunk = luau.load(source, { debugName = name, environment = env, injectGlobals = false })
		return chunk() :: t.Spec
	end)
	if not loaded then
		return { total = 0, failed = { `load: {tostring(result)}` } }
	end
	local spec = result :: t.Spec
	local failed: { string } = {}
	for _, case in spec.cases do
		local fn: () -> any = case.fn
		local ok, err = pcall(fn)
		if not ok then
			table.insert(failed, `{case.name}: {tostring(err)}`)
		end
	end
	return { total = #spec.cases, failed = failed }
end

local function run(specPath: string, served: { [string]: string }): Run
	return runSource(readPickman(specPath), specPath, served)
end

local function killedByVerdict(r: Run): boolean
	for _, f in r.failed do
		if scripted.has(f, "expected true, got false") then
			return true
		end
	end
	return false
end

local function crlf(text: string): string
	return (string.gsub(string.gsub(text, "\r\n", "\n"), "\n", "\r\n"))
end

local listed = process.exec("python3", { "-I", RECORD, "--joins" })
scripted.check("the record lists its join entries", listed.code == 0, listed.stderr)
local joins: { Join } = if listed.code == 0 then serde.decode("json", listed.stdout) :: { Join } else {}

-- one same-length edit of a line that its normalised form notices: two adjacent different non-space characters swapped
-- (the multiset of characters stays), else the first non-space character replaced; nil when no edit changes it
local function perturb(line: string): string?
	local base = pin.normalise(line)
	for j = 1, #line - 1 do
		local a, b = string.sub(line, j, j), string.sub(line, j + 1, j + 1)
		if a ~= b and not string.find(a, "%s") and not string.find(b, "%s") then
			local edited = string.sub(line, 1, j - 1) .. b .. a .. string.sub(line, j + 2)
			if pin.normalise(edited) ~= base then
				return edited
			end
		end
	end
	for j = 1, #line do
		local a = string.sub(line, j, j)
		if not string.find(a, "%s") then
			for _, other in { "x", "y", "0", "1", "]", ")" } do
				if other ~= a then
					local edited = string.sub(line, 1, j - 1) .. other .. string.sub(line, j + 1)
					if pin.normalise(edited) ~= base then
						return edited
					end
				end
			end
		end
	end
	return nil
end

-- the mutants of a file's LF text. Line-removing: each assertion line deleted, each line holding `--` joined to a
-- non-blank next line. Line-keeping: each assertion line commented out in place, and one same-length edit of every
-- non-blank line. Also the number of non-blank lines no edit could change (reported, expected none).
local function generated(lf: string): ({ { string } }, number)
	local lines = string.split(lf, "\n")
	local out: { { string } } = {}
	local unchanged = 0
	for i, line in lines do
		if string.find(line, "t.expect(", 1, true) then
			local copy = table.clone(lines)
			table.remove(copy, i)
			table.insert(out, { `delete line {i}`, table.concat(copy, "\n") })
			copy = table.clone(lines)
			copy[i] = string.gsub(line, "^(%s*)", "%1-- ")
			table.insert(out, { `comment out line {i}`, table.concat(copy, "\n") })
		end
		local nextLine = lines[i + 1]
		if string.find(line, "--", 1, true) and nextLine ~= nil and string.find(nextLine, "%S") then
			local copy = table.clone(lines)
			copy[i] = line .. " " .. string.gsub(nextLine, "^%s+", "")
			table.remove(copy, i + 1)
			table.insert(out, { `join line {i}`, table.concat(copy, "\n") })
		end
		if string.find(line, "%S") then
			local edited = perturb(line)
			if edited == nil then
				unchanged += 1
			else
				local copy = table.clone(lines)
				copy[i] = edited
				table.insert(out, { `edit line {i}`, table.concat(copy, "\n") })
			end
		end
	end
	return out, unchanged
end

-- the verdict rule itself, on small pins of a file "x.txt": the sound one compares the digest and kills a changed file
-- by its "exactly" case; the weak one compares only the digest's length, and a helper that raises on a missing comment
-- must not count as a kill (that raise is not the pin's verdict); the probe one asks for one known needle only, so some
-- generated mutant must get past it (a pin that answers a known list of mutants passes every listed one)
local X = "t.expect(a)\nt.expect(b)\n-- c\nd\n-- e\nf"
local SOUND = [[
local pin = require("@tests/lib/pin")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
return t.spec("sound", function(it)
	it("exactly", function()
		t.expect(pin.digest(fs.readFile("x.txt")) == pin.digest("t.expect(a)\nt.expect(b)\n-- c\nd\n-- e\nf")).toBe(true)
	end)
end)
]]
local WEAK = [[
local pin = require("@tests/lib/pin")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
return t.spec("weak", function(it)
	it("exactly", function()
		t.expect(#pin.digest(fs.readFile("x.txt")) == 64).toBe(true)
	end)
	it("a join", function()
		pin.joined("nothing", "-- absent")
	end)
end)
]]
local PROBE = [[
local pin = require("@tests/lib/pin")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
return t.spec("probe", function(it)
	it("exactly", function()
		t.expect(string.find(pin.normalise(fs.readFile("x.txt")), "t.expect(a)", 1, true) ~= nil).toBe(true)
	end)
end)
]]
local SHAPE = [[
local pin = require("@tests/lib/pin")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local function count(text, needle)
	local _, n = string.gsub(text, needle, "")
	return n
end
return t.spec("shape", function(it)
	it("exactly", function()
		local want = pin.normalise("t.expect(a)\nt.expect(b)\n-- c\nd\n-- e\nf")
		local got = pin.normalise(fs.readFile("x.txt"))
		t.expect(#got == #want and count(got, "\n") == count(want, "\n") and count(got, "t%.expect%(") == count(want, "t%.expect%(")).toBe(true)
	end)
end)
]]
local ESCAPE = [[
local grab = getfenv(0).require
local t = require("@tests/lib/t")
return t.spec("escape", function(it) end)
]]
local function survivors(source: string, name: string, text: string): number
	local n = 0
	local mutants = generated(text)
	for _, m in mutants do
		if not killedByVerdict(runSource(source, name, { ["x.txt"] = m[2] })) then
			n += 1
		end
	end
	return n
end
scripted.check(
	"self-test: the sound pin passes on its file",
	#runSource(SOUND, "sound", { ["x.txt"] = X }).failed == 0
)
scripted.check(
	"self-test: a changed file kills the sound pin",
	killedByVerdict(runSource(SOUND, "sound", { ["x.txt"] = "a b" }))
)
scripted.check("self-test: the generator makes mutants", #generated(X) == 12 and select(2, generated(X)) == 0)
scripted.check("self-test: no generated mutant gets past the sound pin", survivors(SOUND, "sound", X) == 0)
scripted.check(
	"self-test: the weak pin is not killed by a changed file (a helper's raise is no kill)",
	not killedByVerdict(runSource(WEAK, "weak", { ["x.txt"] = "a b" }))
		and #runSource(WEAK, "weak", { ["x.txt"] = "a b" }).failed == 1
)
scripted.check("self-test: a generated mutant gets past the probe pin", survivors(PROBE, "probe", X) > 0)
scripted.check("self-test: a generated mutant gets past the shape pin", survivors(SHAPE, "shape", X) > 0)
local escape = runSource(ESCAPE, "escape", {})
scripted.check(
	"self-test: a pin cannot reach getfenv or the real require",
	escape.total == 0 and #escape.failed == 1
)

for _, p in PINS do
	local unmutated = run(p.spec, {})
	scripted.check(
		`{p.spec} passes on the files as they are ({unmutated.total} cases)`,
		#unmutated.failed == 0 and unmutated.total > 0,
		table.concat(unmutated.failed, " | ")
	)
	for _, file in p.files do
		local original = readPickman(file)
		local lf = string.gsub(original, "\r\n", "\n")
		local crlfRun = run(p.spec, { [file] = crlf(original) })
		scripted.check(
			`{p.spec} passes with {file} in CRLF`,
			#crlfRun.failed == 0,
			table.concat(crlfRun.failed, " | ")
		)

		local mutants, unchanged = generated(lf)
		local derived = #mutants
		scripted.check(`{file}: every non-blank line has an edit its pin must notice`, unchanged == 0)
		for _, j in joins do
			if j.path == file then
				local at = string.find(lf, j.old, 1, true)
				scripted.check(`the record's {j.name} applies to {file}`, at ~= nil)
				if at ~= nil then
					table.insert(
						mutants,
						{ j.name, string.sub(lf, 1, at - 1) .. j.new .. string.sub(lf, at + #j.old) }
					)
				end
			end
		end
		scripted.check(
			`{file}: {derived} mutants derived from its text (deletions, joins, comments, one edit per line)`,
			derived >= 2
		)
		local survived: { string } = {}
		for _, m in mutants do
			if not killedByVerdict(run(p.spec, { [file] = m[2] })) then
				table.insert(survived, m[1])
			end
		end
		scripted.check(
			`{p.spec} rejects all {#mutants} mutants of {file} ({derived} derived, {#mutants - derived} from the record)`,
			#survived == 0,
			`accepted: {table.concat(survived, ", ", 1, math.min(#survived, 5))}`
		)
	end
end

scripted.finish()
