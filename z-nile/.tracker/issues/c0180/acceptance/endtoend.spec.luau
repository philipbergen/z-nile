--!strict
-- c0180: end to end, on a fixture repository under .cache/c0180-e2e: a small engine (main, cli, store, three command
-- modules), the copied runner, selector and libraries, four z-nile specs that call a stub `zn`, and a second worktree.
-- The runner records in worktree W1; `z-nile/affected` then selects by those records in W1 and in W2 (which has none of
-- its own), drops a record whose test code changed, and fails closed on a malformed record file.
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

-- `z-nile/affected -- [flags] --project z-nile <path>` in a worktree: (stdout, stderr)
local function affected(dir: string, path: string, graphOnly: boolean?): (string, string)
	local argv = { "run", "z-nile/affected", "--" }
	if graphOnly then
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
		fixture.git(W1, { "add", "-A" })
		fixture.git(W1, { "commit", "-q", "-m", "seed" })
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
				t.expect((affected(w, "z-nile/engine/store.luau"))).toBe(lines({ A, C }))
			end
		end
	)

	it("the dispatch core selects every spec that ran a command, never one that ran none", function()
		t.expect((affected(W2, "z-nile/engine/main.luau"))).toBe(lines({ A, C, D }))
		t.expect((affected(W2, "z-nile/engine/cli.luau"))).toBe(lines({ A, C, D }))
	end)

	it("a non-Luau engine file, or a selection without records, still forces z-nile's run", function()
		t.expect((affected(W2, "z-nile/engine/board.html"))).toBe("ALL\n")
		t.expect((affected(W2, "z-nile/engine/cmd/list.luau", true))).toBe("ALL\n")
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

	it("a malformed record file is skipped with a warning, and every spec is selected", function()
		local record = `{W1}/z-nile/.cache/spec-commands.tsv`
		fs.writeFile(record, "garbage\n")
		local out, err = affected(W2, "z-nile/engine/cmd/list.luau")
		t.expect(out).toBe(lines({ A, B, C, D }))
		t.expect((string.find(err, `affected: ignoring {record}: line 1`, 1, true)) ~= nil).toBe(true)
	end)

	it("cleans up", function()
		fixture.git(W1, { "worktree", "remove", "--force", W2 })
		fs.removeDir(base)
	end)
end)
