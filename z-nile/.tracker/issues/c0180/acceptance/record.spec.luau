--!strict
-- c0180: the spec runner gives each spec file of a multi-file run its own trace directory and records, for every spec
-- that passed, the commands it ran in <home>/.cache/spec-commands.tsv, keyed through z-nile/recordkey (the spec's
-- test-side closure and the tooling that launches ./zn), merging by union while the key holds. Run on a copy of the
-- runner under .cache/c0180-record (its own repository root, as c0154 does for durations), whose specs call a stub
-- `zn` that writes <dir>/<command> for each directory ZN_SPEC_TRACE lists, so the runner is checked apart from the
-- engine. One case keys the real tree, read only.
local cr = require("@znile/lib/commandrecord")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0180-record`
local home = `{base}/z-nile`
local RECORD = `{home}/.cache/spec-commands.tsv`
local STUB = `{base}/zn-stub`
local E_COMMANDS = `{base}/e-commands.txt`
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function copy(rel: string)
	fs.writeDir(string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string)
	t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{base}/{rel}` }).ok).toBe(true)
end

-- a fixture spec: one case that calls the stub once per command, then passes or fails
local function spec(commands: { string }, fails: boolean?, helper: boolean?): string
	local lines = {
		"--!strict",
		`local process = {R}("@lune/process")`,
		`local t = {R}("@tests/lib/t")`,
	}
	if helper then
		table.insert(lines, `local helper = {R}("@tests/helper")`)
	end
	table.insert(lines, 'return t.spec("fixture", function(it)')
	table.insert(lines, '\tit("runs", function()')
	for _, c in commands do
		table.insert(lines, `\t\tassert(process.exec("bash", \{ "{STUB}", "{c}" \}).ok)`)
	end
	if helper then
		table.insert(lines, "\t\thelper.run()")
	end
	if fails then
		table.insert(lines, '\t\terror("fails on purpose")')
	end
	table.insert(lines, "\tend)")
	table.insert(lines, "end)")
	return table.concat(lines, "\n") .. "\n"
end
-- a fixture spec whose commands come from a file outside its closure: they change while its key holds
local function fromFile(): string
	return table.concat({
		"--!strict",
		`local fs = {R}("@lune/fs")`,
		`local process = {R}("@lune/process")`,
		`local t = {R}("@tests/lib/t")`,
		'return t.spec("fixture", function(it)',
		'\tit("runs", function()',
		`\t\tfor c in string.gmatch(fs.readFile("{E_COMMANDS}"), "%a+") do`,
		`\t\t\tassert(process.exec("bash", \{ "{STUB}", c \}).ok)`,
		"\t\tend",
		"\tend)",
		"end)",
	}, "\n") .. "\n"
end
local function helperText(extra: string): string
	return table.concat({
		"--!strict",
		`local process = {R}("@lune/process")`,
		"local helper = {}",
		"function helper.run()",
		`\tassert(process.exec("bash", \{ "{STUB}", "status" \}).ok)`,
		"end",
		extra,
		"return helper",
	}, "\n") .. "\n"
end

local function run(args: { string }, trace: string?): (boolean, string)
	local argv = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r =
		process.exec("lune", argv, { cwd = home, env = { PICKMAN_JOBS = "", ZN_SPEC_TRACE = trace or "" } })
	return r.ok, r.stdout .. r.stderr
end
local function record(): cr.Records
	local records, problem = cr.parse(fs.readFile(RECORD))
	assert(records, problem)
	return records
end
local function commandsOf(records: cr.Records, path: string): { string }?
	local entry = records[path]
	return if entry then entry.commands else nil
end
local function freshOuter(name: string): string
	local dir = `{base}/.cache/spec-trace/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	return dir
end

return t.spec("c0180 the runner records the commands each spec ran", function(it)
	it(
		"a multi-file run records each passing spec's commands, - for none, nothing for a failing spec",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			t.expect(process.exec("git", { "init", "-q", "-b", "main", base }).ok).toBe(true)
			for _, rel in
				{
					"z-nile/tests/run.luau",
					"z-nile/tests/lib",
					"z-nile/lib",
					"z-nile/recordkey.luau",
					"z-nile/roots.luau",
					"z-nile/engine/projects.luau",
					"z-nile/.luaurc",
					".luaurc",
				}
			do
				copy(rel)
			end
			write("z-nile/projects.toml", '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n')
			write("z-nile/.tracker/.gitkeep", "")
			write(".gitignore", ".cache/\n")
			write("zn", "#!/usr/bin/env bash\n# the fixture's launcher: part of every key\n")
			fs.writeDir(`{home}/.cache`)
			write(
				"zn-stub",
				'#!/usr/bin/env bash\nIFS=: read -r -a dirs <<< "${ZN_SPEC_TRACE:-}"\n'
					.. 'for d in "${dirs[@]}"; do\n\t[[ -n $d ]] || continue\n\t: > "$d/$1"\n'
					.. '\tif [[ $1 == litter ]]; then : > "$d/.list.pickman-tmp.1.abcdef"; : > "$d/Foo"; fi\n'
					.. "done\nexit 0\n"
			)
			write("e-commands.txt", "list\n")
			write("z-nile/tests/a.spec.luau", spec({ "new", "list", "new" }))
			write("z-nile/tests/b.spec.luau", spec({}))
			write("z-nile/tests/c.spec.luau", spec({ "find" }, true))
			write("z-nile/tests/helper.luau", helperText(""))
			write("z-nile/tests/d.spec.luau", spec({}, false, true))
			write("z-nile/tests/e.spec.luau", fromFile())
			write("z-nile/tests/f.spec.luau", spec({ "litter" }))
			local ok, out = run({ "--jobs", "2" })
			t.expect(ok).toBe(false) -- c fails
			t.expect((string.find(out, "fails on purpose", 1, true)) ~= nil).toBe(true)
			local records = record()
			t.expect(commandsOf(records, "tests/a.spec.luau")).toEqual({ "list", "new" })
			t.expect(commandsOf(records, "tests/b.spec.luau")).toEqual({})
			t.expect(commandsOf(records, "tests/c.spec.luau")).toBe(nil)
			t.expect(commandsOf(records, "tests/d.spec.luau")).toEqual({ "status" })
			t.expect(commandsOf(records, "tests/e.spec.luau")).toEqual({ "list" })
			for _, s in { "tests/a.spec.luau", "tests/b.spec.luau", "tests/d.spec.luau" } do
				t.expect(string.match(records[s].key, "^%x+$") ~= nil and #records[s].key == 64).toBe(true)
			end
		end
	)

	it("a leftover temporary file and a stray name never reach the record, and are removed", function()
		t.expect(commandsOf(record(), "tests/f.spec.luau")).toEqual({ "litter" })
	end)

	it("no trace directory is left behind", function()
		local dir = `{home}/.cache/spec-trace`
		t.expect(not fs.isDir(dir) or #fs.readDir(dir) == 0).toBe(true)
	end)

	it("a rerun keeps every key; editing d's helper changes d's key alone", function()
		local before = record()
		run({ "--jobs", "2" })
		local again = record()
		for _, s in { "tests/a.spec.luau", "tests/b.spec.luau", "tests/d.spec.luau" } do
			t.expect(again[s].key).toBe(before[s].key)
		end
		write("z-nile/tests/helper.luau", helperText("-- edited"))
		run({ "--jobs", "2" })
		local edited = record()
		t.expect(edited["tests/d.spec.luau"].key ~= before["tests/d.spec.luau"].key).toBe(true)
		t.expect(edited["tests/a.spec.luau"].key).toBe(before["tests/a.spec.luau"].key)
		t.expect(edited["tests/b.spec.luau"].key).toBe(before["tests/b.spec.luau"].key)
	end)

	it("editing the launching tooling (the fixture's zn) changes every key", function()
		local before = record()
		write("zn", "#!/usr/bin/env bash\n# the fixture's launcher: part of every key, edited\n")
		run({ "--jobs", "2" })
		local after = record()
		for _, s in { "tests/a.spec.luau", "tests/b.spec.luau", "tests/d.spec.luau" } do
			t.expect(after[s].key ~= before[s].key).toBe(true)
		end
	end)

	it("a spec that runs other commands under the same key keeps the union", function()
		write("e-commands.txt", "status\n")
		run({ "--jobs", "2" })
		t.expect(commandsOf(record(), "tests/e.spec.luau")).toEqual({ "list", "status" })
	end)

	it("a spec that fails keeps the line an earlier passing run wrote", function()
		write("z-nile/tests/c.spec.luau", spec({ "find" }))
		t.expect((run({ "--jobs", "2" }))).toBe(true)
		local passing = record()["tests/c.spec.luau"]
		t.expect(passing.commands).toEqual({ "find" })
		write("z-nile/tests/c.spec.luau", spec({ "list" }, true))
		t.expect((run({ "--jobs", "2" }))).toBe(false)
		t.expect(record()["tests/c.spec.luau"]).toEqual(passing)
	end)

	it("a --jobs 1 run and a one-file run leave the record byte for byte", function()
		write("z-nile/tests/c.spec.luau", spec({ "find" }))
		t.expect((run({ "--jobs", "2" }))).toBe(true)
		write("z-nile/tests/a.spec.luau", spec({ "worktree" }))
		-- a line no multi-file full run would keep (its spec is gone): any rewrite of the record changes its bytes
		fs.writeFile(RECORD, fs.readFile(RECORD) .. `tests/gone.spec.luau\t{string.rep("a", 64)}\tlist\n`)
		local before = fs.readFile(RECORD)
		t.expect((run({ "--jobs", "1" }))).toBe(true)
		t.expect(fs.readFile(RECORD)).toBe(before)
		t.expect((run({ "tests/a.spec.luau" }))).toBe(true)
		t.expect(fs.readFile(RECORD)).toBe(before)
	end)

	it("an inherited ZN_SPEC_TRACE directory also receives the commands, in either path", function()
		local outer = freshOuter("outer")
		t.expect((run({ "--jobs", "2" }, outer))).toBe(true)
		local names = fs.readDir(outer)
		table.sort(names)
		t.expect(names)
			.toEqual({ ".list.pickman-tmp.1.abcdef", "Foo", "find", "litter", "status", "worktree" })
		-- the new record holds a's new command (a new key: its text changed), and the inherited directory took nothing
		t.expect(commandsOf(record(), "tests/a.spec.luau")).toEqual({ "worktree" })
		local inProcess = freshOuter("outer-one")
		t.expect((run({ "--jobs", "1", "tests/c.spec.luau" }, inProcess))).toBe(true)
		t.expect(fs.readDir(inProcess)).toEqual({ "find" })
	end)

	it("a full run drops the line of a deleted spec; a run naming files keeps the others", function()
		fs.removeFile(`{home}/tests/b.spec.luau`)
		t.expect((run({ "--jobs", "2", "tests/a.spec.luau", "tests/c.spec.luau" }))).toBe(true)
		t.expect(commandsOf(record(), "tests/b.spec.luau")).toEqual({})
		t.expect((run({ "--jobs", "2" }))).toBe(true)
		local records = record()
		t.expect(records["tests/b.spec.luau"]).toBe(nil)
		t.expect(records["tests/gone.spec.luau"]).toBe(nil)
		t.expect(commandsOf(records, "tests/d.spec.luau")).toEqual({ "status" })
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)

	it("on the real tree, z-nile/recordkey keys every spec of every home, read only", function()
		local listed = process.exec("git", { "ls-files", "*.spec.luau" }, { cwd = root })
		t.expect(listed.ok).toBe(true)
		local specs: { string } = {}
		for line in string.gmatch(listed.stdout, "[^\n]+") do
			if string.match(line, "^[^/]+/tests/") then
				table.insert(specs, line)
			end
		end
		t.expect(#specs > 300).toBe(true)
		local argv = { "run", "z-nile/recordkey", "--" }
		for _, s in specs do
			table.insert(argv, s)
		end
		local r = process.exec("lune", argv, { cwd = root })
		t.expect(r.ok).toBe(true)
		local keyed = 0
		for line in string.gmatch(r.stdout, "[^\n]+") do
			local s, key = string.match(line, "^(.-)\t(%x+)$")
			t.expect(s ~= nil and #(key :: string) == 64).toBe(true)
			keyed += 1
		end
		t.expect(keyed).toBe(#specs)
	end)
end)
