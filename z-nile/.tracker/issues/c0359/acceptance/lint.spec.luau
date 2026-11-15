--!strict
-- c0359 AC4: `z-nile/check.sh --lint` runs the gate's format and lint stages alone, with the real tools, over every
-- project's folders (each `.tracker/` included), never narrowed by what changed; a diff or a lint warning alone fails it
-- and names the file; both stages run and report when the first fails; `--plan` prints the two stages' folders only;
-- a format or lint setting under a `.tracker/` fails it; it writes nothing outside `.cache`, builds, fetches and maps
-- nothing, and reaps nothing.
-- Fixture under .cache/c0359-lint: a copy of the tooling (engine.copy) with the root's format and lint settings, in a
-- repository of its own with everything committed.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HOME = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local BASE = `{HOME}/.cache/c0359-lint`

-- unformatted for the root's stylua.toml (no spaces inside the braces)
local UNFORMATTED = "local x = {1,2}\nreturn x\n"
-- formatted, with one selene warning only (selene.toml: shadowing = "warn")
local SHADOWED = "local a = 1\nlocal function f()\n\tlocal a = 2\n\treturn a\nend\nreturn { a, f }\n"
local CLEAN = "local x = { 1, 2 }\nreturn x\n"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

-- a fresh tree `name` under BASE: the tooling, the root's settings, a game home with a source and a project file
local function tree(name: string): string
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	engine.copy(TOP, dir)
	engine.roots(dir)
	for _, f in { "stylua.toml", "selene.toml", ".luaurc" } do
		fs.writeFile(`{dir}/{f}`, fs.readFile(`{TOP}/{f}`))
	end
	write(`{dir}/pickman/src/shared/ok.luau`, CLEAN)
	write(`{dir}/pickman/default.project.json`, '{ "name": "g", "tree": { "$path": "src" } }\n')
	write(`{dir}/.gitignore`, ".cache/\n")
	local init = process.exec("git", { "init", "-q", "-b", "main", dir })
	if not init.ok then
		error(init.stderr)
	end
	fixture.git(dir, { "config", "user.name", "c0359-lint" })
	fixture.git(dir, { "config", "user.email", "c0359-lint@example.invalid" })
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "commit", "-q", "-m", "seed" })
	return dir
end

local function lint(dir: string, extra: { string }?): (boolean, string)
	local argv = { "z-nile/check.sh", "--lint" }
	local more: { string } = extra or {}
	for _, a in more do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, { cwd = dir })
	return r.ok, r.stdout .. r.stderr
end

-- every file outside .cache and .git, with its size and content, so a write or a new file shows
local function snapshot(dir: string): { [string]: string }
	local out: { [string]: string } = {}
	local function walk(rel: string)
		for _, name in fs.readDir(if rel == "" then dir else `{dir}/{rel}`) do
			local path = if rel == "" then name else `{rel}/{name}`
			if path == ".cache" or path == ".git" then
				continue
			end
			local full = `{dir}/{path}`
			if fs.isDir(full) then
				walk(path)
			else
				out[path] = fs.readFile(full)
			end
		end
	end
	walk("")
	return out
end

return t.spec("c0359 check.sh --lint", function(it)
	local dir = tree("main")

	it("a clean tree passes, and both stages ran", function()
		local ok, out = lint(dir)
		if not ok then
			error(`the clean tree failed --lint:\n{out}`)
		end
		t.expect(has(out, "== format (stylua --check)")).toBe(true)
		t.expect(has(out, "== lint (selene)")).toBe(true)
		t.expect(has(out, "GATE PASSED (lint)")).toBe(true)
	end)

	it("it writes nothing outside .cache, and builds, fetches and maps nothing", function()
		-- a tree no run has touched yet, so a file a first run would write is not already there
		local fresh = tree("fresh")
		local before = snapshot(fresh)
		local ok = lint(fresh)
		t.expect(ok).toBe(true)
		local after = snapshot(fresh)
		local changed: { string } = {}
		for path, text in after do
			if before[path] ~= text then
				table.insert(changed, path)
			end
		end
		for path in before do
			if after[path] == nil then
				table.insert(changed, path)
			end
		end
		table.sort(changed)
		t.expect(changed).toEqual({})
		t.expect(fs.isFile(`{fresh}/.cache/globalTypes.d.luau`)).toBe(false)
		t.expect(fs.isFile(`{fresh}/pickman/.cache/check.rbxl`)).toBe(false)
		t.expect(fs.isFile(`{fresh}/pickman/sourcemap.json`)).toBe(false)
	end)

	it("an unformatted spec in an issue's acceptance folder fails the format stage, named", function()
		local rel = "pickman/.tracker/issues/c9999/acceptance/a.spec.luau"
		write(`{dir}/{rel}`, UNFORMATTED)
		local ok, out = lint(dir)
		fs.removeFile(`{dir}/{rel}`)
		t.expect(ok).toBe(false)
		t.expect(has(out, "format (stylua --check)")).toBe(true)
		t.expect(has(out, "FAILED")).toBe(true)
		t.expect(has(out, "a.spec.luau")).toBe(true)
		t.expect(has(out, "GATE PASSED")).toBe(false)
	end)

	it("a lint warning alone in an experiment fails the lint stage, named", function()
		local rel = "z-nile/.tracker/issues/c9999/experiments/w.luau"
		write(`{dir}/{rel}`, SHADOWED)
		local ok, out = lint(dir)
		fs.removeFile(`{dir}/{rel}`)
		t.expect(ok).toBe(false)
		t.expect(has(out, "== lint (selene)")).toBe(true)
		t.expect(has(out, "shadowing")).toBe(true)
		t.expect(has(out, "w.luau")).toBe(true)
		t.expect(has(out, "GATE PASSED")).toBe(false)
	end)

	it("both stages run and report when the format stage fails", function()
		local a = "pickman/.tracker/issues/c9999/acceptance/a.spec.luau"
		local w = "z-nile/.tracker/issues/c9999/experiments/w.luau"
		write(`{dir}/{a}`, UNFORMATTED)
		write(`{dir}/{w}`, SHADOWED)
		local ok, out = lint(dir)
		fs.removeFile(`{dir}/{a}`)
		fs.removeFile(`{dir}/{w}`)
		t.expect(ok).toBe(false)
		local failed = 0
		for _ in string.gmatch(out, "FAILED%)") do
			failed += 1
		end
		t.expect(failed).toBe(2)
		t.expect(has(out, "a.spec.luau")).toBe(true)
		t.expect(has(out, "w.luau")).toBe(true)
	end)

	it(
		"a format or lint setting under a .tracker/ folder fails it, named, even where it hides a spec",
		function()
			local ignore = "pickman/.tracker/issues/c9999/acceptance/.styluaignore"
			local spec = "pickman/.tracker/issues/c9999/acceptance/a.spec.luau"
			write(`{dir}/{ignore}`, "*\n")
			write(`{dir}/{spec}`, UNFORMATTED)
			local ok, out = lint(dir)
			fs.removeFile(`{dir}/{ignore}`)
			fs.removeFile(`{dir}/{spec}`)
			t.expect(ok).toBe(false)
			t.expect(has(out, "format or lint settings under a .tracker/ folder")).toBe(true)
			t.expect(has(out, ".styluaignore")).toBe(true)
			-- a settings file alone, in any case, fails too
			local settings = "z-nile/.tracker/issues/c9999/Selene.TOML"
			write(`{dir}/{settings}`, 'std = "roblox"\n')
			local ok2, out2 = lint(dir)
			fs.removeFile(`{dir}/{settings}`)
			t.expect(ok2).toBe(false)
			t.expect(has(out2, "Selene.TOML")).toBe(true)
		end
	)

	it("it reaps nothing: the tree's ./zn is never started", function()
		local own = tree("reap")
		write(
			`{own}/zn`,
			'#!/usr/bin/env bash\nmkdir -p "$(dirname "$0")/.cache"\ntouch "$(dirname "$0")/.cache/zn-ran"\n'
		)
		process.exec("chmod", { "+x", `{own}/zn` })
		local ok, out = lint(own)
		if not ok then
			error(`--lint failed:\n{out}`)
		end
		t.expect(fs.isFile(`{own}/.cache/zn-ran`)).toBe(false)
	end)

	it("it is never narrowed by the change: a committed, unchanged file in a game's src fails it", function()
		local bad = tree("unchanged")
		write(`{bad}/pickman/src/shared/bad.luau`, UNFORMATTED)
		fixture.git(bad, { "add", "-A" })
		fixture.git(bad, { "commit", "-q", "-m", "bad source" })
		-- the only change on top of it is a tracker document
		write(`{bad}/z-nile/.tracker/issues/c9998/c9998.md`, "# c9998\n")
		fixture.git(bad, { "add", "-A" })
		fixture.git(bad, { "commit", "-q", "-m", "a document" })
		local ok, out = lint(bad)
		t.expect(ok).toBe(false)
		t.expect(has(out, "bad.luau")).toBe(true)
	end)

	it("--plan prints the two stages' folders, every project's root among them, and nothing else", function()
		local ok, out = lint(dir, { "--plan" })
		t.expect(ok).toBe(true)
		local labels: { string } = {}
		local format = ""
		for line in string.gmatch(out, "[^\n]+") do
			local label, rest = string.match(line, "^([%w ()]+): (.*)$")
			if label and not string.match(line, "^bounded:") then
				table.insert(labels, label)
				if label == "format" then
					format = rest :: string
				end
			end
		end
		t.expect(labels).toEqual({ "format", "lint" })
		local dirs: { [string]: boolean } = {}
		for d in string.gmatch(format, "%S+") do
			dirs[d] = true
		end
		for _, d in { "pickman/src", "pickman/.tracker", "z-nile", "z-nile/.tracker" } do
			t.expect(`{d}: {tostring(dirs[d] == true)}`).toBe(`{d}: true`)
		end
	end)
end)
