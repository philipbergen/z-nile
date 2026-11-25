--!strict
-- c0257 AC13 (G1, ruled): the gate runs an app project's node tests and none of the Luau stages for it. The plan of
-- the real tree names the app's test file on a `node:` line and keeps the app's home out of the format, lint and Lune
-- type stages and the spec stage; in a fixture (a copy of the tooling under .cache/c0257-gate with an app `board`),
-- a run of `--project board` passes when its tests pass and fails when one fails or there are none.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local BASE = `{HERE}/.cache/c0257-gate`
local REGISTRY = '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n'
	.. '[[project]]\nname = "board"\nroot = "board/.tracker"\nkind = "app"\n'
local PASS = 'import { test } from "node:test"\ntest("ok", () => {})\n'
local FAIL =
	'import { test } from "node:test"\nimport assert from "node:assert"\ntest("no", () => assert.equal(1, 2))\n'

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function lineOf(text: string, label: string): string?
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, #label + 2) == label .. ": " then
			return string.sub(line, #label + 3)
		end
	end
	return nil
end
local function words(s: string?): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for w in string.gmatch(s or "", "%S+") do
		out[w] = true
	end
	return out
end
local function fixture(name: string, tests: { [string]: string }): string
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	engine.copy(TOP, dir)
	fs.writeFile(`{dir}/z-nile/projects.toml`, REGISTRY)
	fs.writeDir(`{dir}/z-nile/.tracker`)
	write(
		`{dir}/board/check.sh`,
		'#!/usr/bin/env bash\nexec bash "$(dirname "$0")/../z-nile/check.sh" --project board "$@"\n'
	)
	write(`{dir}/board/.tracker/issues/.gitkeep`, "")
	write(`{dir}/board/.tracker/rafts/.gitkeep`, "")
	for rel, text in tests do
		write(`{dir}/board/app/tests/{rel}`, text)
	end
	-- stub tools: the Luau stages read only the fixture's roots and must not fetch anything; `./zn reap --auto` (the
	-- gate's first step) must not signal this machine's processes from a spec. node and lune are the real ones.
	write(`{dir}/zn`, "#!/bin/sh\nexit 0\n")
	write(
		`{dir}/bin/curl`,
		'#!/bin/sh\no=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "-- defs" > "$o"\n'
	)
	for _, tool in { "stylua", "selene", "luau-lsp", "rojo" } do
		write(`{dir}/bin/{tool}`, "#!/bin/sh\nexit 0\n")
	end
	for _, f in { "zn", "bin/curl", "bin/stylua", "bin/selene", "bin/luau-lsp", "bin/rojo" } do
		process.exec("chmod", { "+x", `{dir}/{f}` })
	end
	process.exec("git", { "init", "-q", dir })
	return dir
end
local function gate(dir: string, args: { string }): (boolean, string)
	local argv = { "z-nile/check.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, { cwd = dir, env = { PATH = `{dir}/bin:{process.env.PATH or ""}` } })
	return r.ok, r.stdout .. r.stderr
end

return t.spec("c0257 AC13: the gate's node stage for an app", function(it)
	it("AC13: the real tree's plan runs the app's node tests and no Luau stage over its home", function()
		local r = process.exec("bash", { "z-nile/check.sh", "--full", "--plan" }, { cwd = TOP })
		t.expect(r.ok).toBe(true)
		local out = r.stdout
		t.expect(words(lineOf(out, "node"))["z-nile-omarchy/znile.board/tests/model.test.mjs"]).toBe(true)
		for _, label in { "format", "lint", "types (Lune)" } do
			local w = words(lineOf(out, label))
			t.expect(w["z-nile-omarchy"]).toBe(nil)
			t.expect(w["z-nile-omarchy/znile.board"]).toBe(nil)
		end
		t.expect((string.find(out, "specs: z-nile-omarchy", 1, true))).toBe(nil)
		local only = process.exec(
			"bash",
			{ "z-nile/check.sh", "--project", "z-nile-omarchy", "--plan" },
			{ cwd = TOP }
		)
		t.expect(only.ok).toBe(true)
		t.expect(lineOf(only.stdout, "node")).toBe("z-nile-omarchy/znile.board/tests/model.test.mjs")
		t.expect((string.find(only.stdout, "specs:", 1, true))).toBe(nil)
		t.expect((string.find(only.stdout, "build:", 1, true))).toBe(nil)
	end)

	it("AC13: a run of the app passes on passing tests, every file run, sorted", function()
		local dir = fixture("pass", { ["b.test.mjs"] = PASS, ["a.test.mjs"] = PASS })
		local _, plan = gate(dir, { "--project", "board", "--plan" })
		t.expect(lineOf(plan, "node")).toBe("board/app/tests/a.test.mjs board/app/tests/b.test.mjs")
		local ok, out = gate(dir, { "--project", "board" })
		if not ok then
			print(out)
		end
		t.expect(ok).toBe(true)
	end)

	it("AC13: a run of the app fails when a test fails, and when there are none", function()
		local ok =
			gate(fixture("fail", { ["a.test.mjs"] = PASS, ["b.test.mjs"] = FAIL }), { "--project", "board" })
		t.expect(ok).toBe(false)
		local none = gate(fixture("none", {}), { "--project", "board" })
		t.expect(none).toBe(false)
	end)
end)
