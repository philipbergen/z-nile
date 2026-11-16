--!strict
-- c0180: end to end, on a fixture repository under .cache/c0180-e2e: a small engine (main, cli, store, three command
-- modules, and the real projects.luau, which the copied z-nile/affected requires), the copied runner, selector,
-- recordkey and libraries, four z-nile specs that call a stub `zn`, and a second worktree. The runner records in
-- worktree W1; `z-nile/affected --recorded` then selects by those records in W1 and in W2 (which has none of its own),
-- joins W2's own record, drops a record whose test code or launching tooling changed, forces for a program's engine
-- file, and fails closed on a malformed record file; a bare call is unchanged.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0180-e2e`
local W1 = `{base}/repo`
local W2 = `{base}/w2`
local STUB = `{base}/zn-stub`
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
local A, B, C, D = "tests/a.spec.luau", "tests/b.spec.luau", "tests/c.spec.luau", "tests/d.spec.luau"
local F = "tests/f.spec.luau" -- requires an engine module through a forwarder in scripts/tracker/, and runs no command

local function write(dir: string, rel: string, text: string)
	local path = `{dir}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function copy(rel: string)
	fs.writeDir(string.match(`{W1}/{rel}`, "^(.*)/[^/]+$") :: string)
	t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{W1}/{rel}` }).ok).toBe(true)
end
local function module(requires: { string }): string
	local lines = { "--!strict" }
	for i, r in requires do
		table.insert(lines, `local m{i} = {R}("{r}")`)
	end
	table.insert(lines, "return {}")
	return table.concat(lines, "\n") .. "\n"
end
local function spec(commands: { string }, fails: boolean?, helper: boolean?): string
	local lines = { "--!strict", `local process = {R}("@lune/process")`, `local t = {R}("@tests/lib/t")` }
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
local function helperText(extra: string): string
	return table.concat({
		"--!strict",
		`local process = {R}("@lune/process")`,
		"local helper = {}",
		"function helper.run()",
		`\tassert(process.exec("bash", \{ "{STUB}", "new" \}).ok)`,
		"end",
		extra,
		"return helper",
	}, "\n") .. "\n"
end

-- `z-nile/affected -- [--recorded | --graph-only] --project z-nile <path>` in a worktree: (stdout, stderr); the mode
-- is "recorded" unless given ("bare" passes neither flag)
local function affected(dir: string, path: string, mode: string?): (string, string)
	local argv = { "run", "z-nile/affected", "--" }
	local m = mode or "recorded"
	if m == "recorded" then
		table.insert(argv, "--recorded")
	elseif m == "graph-only" then
		table.insert(argv, "--graph-only")
	end
	for _, a in { "--project", "z-nile", path } do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = dir })
	t.expect(r.ok).toBe(true)
	return r.stdout, r.stderr
end
local function lines(list: { string }): string
	return table.concat(list, "\n") .. "\n"
end

return t.spec("c0180 affected selects by recorded commands, end to end", function(it)
	it("the runner records in W1", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(W1)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", W1 }).ok).toBe(true)
		fixture.git(W1, { "config", "user.name", "c0180-e2e" })
		fixture.git(W1, { "config", "user.email", "c0180-e2e@example.invalid" })
		for _, rel in
			{
				".luaurc",
				"z-nile/.luaurc",
				"z-nile/affected.luau",
				"z-nile/recordkey.luau",
				"z-nile/lib",
				"z-nile/roots.luau",
				"z-nile/engine/projects.luau",
				"z-nile/engine/board.html",
				"z-nile/tests/run.luau",
				"z-nile/tests/lib",
			}
		do
			copy(rel)
		end
		local registry = table.concat({
			"[[project]]",
			'name = "pickman"',
			'root = "pickman/.tracker"',
			"",
			"[[project]]",
			'name = "z-nile"',
			'root = "z-nile/.tracker"',
			"",
		}, "\n")
		write(W1, "z-nile/projects.toml", registry)
		write(W1, "z-nile/.tracker/issues/.gitkeep", "")
		write(W1, "pickman/.tracker/issues/.gitkeep", "")
		write(W1, "pickman/tests/p.spec.luau", "--!strict\nreturn nil\n")
		write(W1, "z-nile/tests/inputs.tsv", "# extra inputs per spec\n")
		write(W1, ".gitignore", ".cache/\n")
		write(
			W1,
			"z-nile/check.sh",
			"#!/usr/bin/env bash\n# the fixture's gate: launching tooling, part of every key\n"
		)
		write(W1, "z-nile/engine/main.luau", module({ "./cli", "./cmd/list", "./cmd/new", "./cmd/find" }))
		write(W1, "z-nile/engine/cli.luau", module({ "../lib/sh" }))
		write(W1, "z-nile/engine/store.luau", module({}))
		write(W1, "z-nile/engine/cmd/list.luau", module({ "../cli", "../store" }))
		write(W1, "z-nile/engine/cmd/new.luau", module({ "../cli" }))
		write(W1, "z-nile/engine/cmd/find.luau", module({ "../cli" }))
		write(
			base,
			"zn-stub",
			'#!/usr/bin/env bash\nIFS=: read -r -a dirs <<< "${ZN_SPEC_TRACE:-}"\n'
				.. 'for d in "${dirs[@]}"; do [[ -n $d ]] && : > "$d/$1"; done\nexit 0\n'
		)
		write(W1, `z-nile/{A}`, spec({ "list" }))
		write(W1, `z-nile/{B}`, spec({}))
		write(W1, `z-nile/{C}`, spec({ "find" }, true))
		write(W1, "z-nile/tests/helper.luau", helperText(""))
		write(W1, `z-nile/{D}`, spec({}, false, true))
		write(W1, "scripts/tracker/store.luau", `--!strict\nreturn {R}("../../z-nile/engine/store")\n`)
		write(
			W1,
			`z-nile/{F}`,
			`--!strict\nlocal store = {R}("@scripts/tracker/store")\nlocal t = {R}("@tests/lib/t")\n`
				.. 'return t.spec("fixture", function(it)\n\tit("runs", function()\n\t\tassert(store ~= nil)\n\tend)\nend)\n'
		)
		fixture.git(W1, { "add", "-A" })
		fixture.git(W1, { "commit", "-q", "-m", "seed" })
		fixture.git(W1, { "update-ref", "refs/remotes/origin/main", "HEAD" }) -- the base every record starts from
		fixture.git(W1, { "worktree", "add", "-q", W2 })
		local r = process.exec(
			"lune",
			{ "run", "tests/run", "--", "--jobs", "2" },
			{ cwd = `{W1}/z-nile`, env = { PICKMAN_JOBS = "", ZN_SPEC_TRACE = "" } }
		)
		t.expect(r.ok).toBe(false) -- c fails
		t.expect(fs.isFile(`{W1}/z-nile/.cache/spec-commands.tsv`)).toBe(true)
	end)

	it(
		"a command module selects the specs that ran it and the unrecorded failing spec, in both worktrees",
		function()
			for _, w in { W1, W2 } do
				t.expect((affected(w, "z-nile/engine/cmd/list.luau"))).toBe(lines({ A, C }))
				t.expect((affected(w, "z-nile/engine/cmd/new.luau"))).toBe(lines({ C, D }))
				-- F reaches store.luau through the forwarder: the graph follows it
				t.expect((affected(w, "z-nile/engine/store.luau"))).toBe(lines({ A, C, F }))
			end
		end
	)

	it("a worktree with no record file of its own is read silently", function()
		local _, err = affected(W2, "z-nile/engine/cmd/list.luau")
		t.expect((string.find(err, "ignoring", 1, true))).toBe(nil)
	end)

	it("a bare call loads no records: engine files force z-nile's run as today", function()
		t.expect((affected(W2, "z-nile/engine/cmd/list.luau", "bare"))).toBe("ALL\n")
	end)

	it(
		"an engine file a program requires (projects.luau, through z-nile/affected) forces z-nile's run",
		function()
			t.expect((affected(W2, "z-nile/engine/projects.luau"))).toBe("ALL\n")
		end
	)

	it("W2's own record for the same key adds its commands to W1's", function()
		local w1 = fs.readFile(`{W1}/z-nile/.cache/spec-commands.tsv`)
		local key = string.match(w1, "\n" .. B .. "\t(%x+)\t") :: string
		t.expect(key ~= nil).toBe(true)
		write(W2, "z-nile/.cache/spec-commands.tsv", `# spec commands v1\n{B}\t{key}\tfind\tclean\n`)
		t.expect((affected(W2, "z-nile/engine/cmd/find.luau"))).toBe(lines({ B, C }))
		t.expect((affected(W1, "z-nile/engine/cmd/find.luau"))).toBe(lines({ B, C }))
		fs.removeFile(`{W2}/z-nile/.cache/spec-commands.tsv`)
		t.expect((affected(W2, "z-nile/engine/cmd/find.luau"))).toBe(lines({ C }))
	end)

	it("the dispatch core selects every spec that ran a command, never one that ran none", function()
		t.expect((affected(W2, "z-nile/engine/main.luau"))).toBe(lines({ A, C, D }))
		t.expect((affected(W2, "z-nile/engine/cli.luau"))).toBe(lines({ A, C, D }))
	end)

	it("a non-Luau engine file, or a selection without records, still forces z-nile's run", function()
		t.expect((affected(W2, "z-nile/engine/board.html"))).toBe("ALL\n")
		t.expect((affected(W2, "z-nile/engine/cmd/list.luau", "graph-only"))).toBe("ALL\n")
	end)

	it(
		"a record whose test code changed no longer counts: the spec is selected by any engine change",
		function()
			write(W2, "z-nile/tests/helper.luau", helperText("-- edited"))
			t.expect((affected(W2, "z-nile/engine/cmd/list.luau"))).toBe(lines({ A, C, D }))
			t.expect((affected(W1, "z-nile/engine/cmd/list.luau"))).toBe(lines({ A, C }))
			write(W2, "z-nile/tests/helper.luau", helperText(""))
		end
	)

	it("a record whose launching tooling changed no longer counts: every spec is selected", function()
		write(W2, "z-nile/check.sh", "#!/usr/bin/env bash\n# the fixture's gate, edited in W2\n")
		t.expect((affected(W2, "z-nile/engine/cmd/list.luau"))).toBe(lines({ A, B, C, D, F }))
		write(
			W2,
			"z-nile/check.sh",
			"#!/usr/bin/env bash\n# the fixture's gate: launching tooling, part of every key\n"
		)
		t.expect((affected(W2, "z-nile/engine/cmd/list.luau"))).toBe(lines({ A, C }))
	end)

	it("another worktree's entry recorded on an edited engine serves only its own worktree", function()
		local record = `{W1}/z-nile/.cache/spec-commands.tsv`
		local before = fs.readFile(record)
		local edited = string.gsub(before, "\n(" .. A .. "\t%x+\t[^\t]+)\tclean\n", "\n%1\tedited\n")
		t.expect(edited ~= before).toBe(true)
		fs.writeFile(record, edited)
		-- W2 can't use A's entry: A has no record there, so cmd/find selects it; W1 still uses its own
		t.expect((affected(W2, "z-nile/engine/cmd/find.luau"))).toBe(lines({ A, C }))
		t.expect((affected(W1, "z-nile/engine/cmd/find.luau"))).toBe(lines({ C }))
		fs.writeFile(record, before)
	end)

	it("a malformed record file is skipped with a warning, and every spec is selected", function()
		local record = `{W1}/z-nile/.cache/spec-commands.tsv`
		local before = fs.readFile(record)
		-- a valid header and A's own line, then one bad line: the whole file is refused, A's line included
		local aLine = string.match(before, "\n(" .. A .. "\t[^\n]+)\n") :: string
		t.expect(aLine ~= nil).toBe(true)
		fs.writeFile(record, `# spec commands v1\n{aLine}\ngarbage\n`)
		-- cmd/find: a reader that kept A's valid line would leave A out
		local out, err = affected(W2, "z-nile/engine/cmd/find.luau")
		t.expect(out).toBe(lines({ A, B, C, D, F }))
		t.expect((string.find(err, `affected: ignoring {record}: line 3`, 1, true)) ~= nil).toBe(true)
		fs.writeFile(record, before)
	end)

	it("records made on another merge base don't count: W2 takes a main whose engine changed", function()
		write(
			W2,
			"z-nile/engine/store.luau",
			"--!strict\nlocal changed = true\nreturn { changed = changed }\n"
		)
		fixture.git(W2, { "commit", "-qam", "engine change on main" })
		fixture.git(W2, { "update-ref", "refs/remotes/origin/main", "HEAD" })
		t.expect((affected(W2, "z-nile/engine/cmd/list.luau"))).toBe(lines({ A, B, C, D, F }))
		-- W1 is still on its old base, where its records hold
		t.expect((affected(W1, "z-nile/engine/cmd/list.luau"))).toBe(lines({ A, C }))
	end)

	it("cleans up", function()
		fixture.git(W1, { "worktree", "remove", "--force", W2 })
		fs.removeDir(base)
	end)
end)
