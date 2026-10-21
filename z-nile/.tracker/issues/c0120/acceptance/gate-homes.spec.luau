--!strict
-- c0120 AC6: each project has its own gate. `z-nile/check.sh --project <name>` runs one project's stages and specs,
-- no --project runs every project's, and `pickman/check.sh` is pickman's. Each stage's folders come from the projects'
-- homes: format and lint read every home's src/, tests/, scripts/ and root (each .tracker/ named, stylua skips hidden
-- folders), Roblox types read a home's src/ from that home (a sourcemap is relative to its project file), Lune types
-- read tests/ and scripts/ and never a .tracker/, the places are a home's project files, and a project's specs run from
-- its home. `--plan` prints all of it and runs and writes nothing. Fixture under .cache/c0120-gate (stub tools).
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0120-gate`
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\nhome = "pickman"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\nhome = "."\n'

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function plan(dir: string, args: { string }): (boolean, string)
	local argv = { "z-nile/check.sh", "--plan" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, { cwd = dir })
	return r.ok, r.stdout .. r.stderr
end
local function lineOf(text: string, label: string): string
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, #label + 2) == label .. ": " then
			return string.sub(line, #label + 3)
		end
	end
	return ""
end
local function words(s: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for w in string.gmatch(s, "%S+") do
		out[w] = true
	end
	return out
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

-- a copy of the tooling with two homes and stub tools that log their working folder and arguments
local function stubbed(name: string): string
	local dir = `{base}/{name}`
	fs.writeDir(dir)
	engine.copy(root, dir)
	fs.writeFile(`{dir}/z-nile/projects.toml`, REGISTRY)
	for _, rel in
		{ "pickman/src/shared", "pickman/tests/unit", "tests/tooling", "z-nile/.tracker", "pickman/.tracker" }
	do
		fs.writeDir(`{dir}/{rel}`)
	end
	write(`{dir}/pickman/default.project.json`, '{ "name": "g", "tree": { "$className": "DataModel" } }\n')
	write(`{dir}/pickman/lobby.project.json`, '{ "name": "l", "tree": { "$className": "DataModel" } }\n')
	fs.writeDir(`{dir}/bin`)
	fs.writeDir(`{dir}/home/.lune/.typedefs/0.10.5`)
	local log = 'printf "%s|%s|%s\\n" "$(pwd -P)" "$(basename "$0")" "$*" >> "$STUB_LOG"\n'
	for _, tool in { "stylua", "selene", "luau-lsp" } do
		write(`{dir}/bin/{tool}`, "#!/bin/sh\n" .. log .. "exit 0\n")
	end
	write(
		`{dir}/bin/rojo`,
		"#!/bin/sh\n" .. log .. 'o=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done\necho "built" > "$o"\n'
	)
	write(
		`{dir}/bin/curl`,
		'#!/bin/sh\no=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "-- defs" > "$o"\n'
	)
	-- lune: a spec run is logged; z-nile/roots (the registry's reader for the shell, which AC1 pins) answers as it would
	-- for this fixture's registry and folders
	write(
		`{dir}/bin/lune`,
		'#!/bin/sh\nif [ "$1" = --version ]; then echo "lune 0.10.5"; exit 0; fi\n'
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --projects ]; then\n'
			.. '  printf "pickman\\tpickman\\tpickman/.tracker\\nz-nile\\t.\\tz-nile/.tracker\\n"; exit 0\nfi\n'
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --luau-dirs ]; then\n'
			.. '  if [ "$5" = pickman ]; then echo "pickman/src pickman/tests pickman/.tracker"; exit 0; fi\n'
			.. '  echo "pickman/src pickman/tests pickman/.tracker tests z-nile z-nile/.tracker"; exit 0\nfi\n'
			.. log
			.. "exit 0\n"
	)
	for _, tool in { "stylua", "selene", "luau-lsp", "rojo", "curl", "lune" } do
		process.exec("chmod", { "+x", `{dir}/bin/{tool}` })
	end
	return dir
end
local function gate(dir: string, args: { string }): (boolean, string, string)
	local argv = { "z-nile/check.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, {
		cwd = dir,
		env = {
			PATH = `{dir}/bin:{process.env.PATH or ""}`,
			HOME = `{dir}/home`,
			STUB_LOG = `{dir}/calls.log`,
		},
	})
	local log = if fs.isFile(`{dir}/calls.log`) then fs.readFile(`{dir}/calls.log`) else ""
	if not r.ok then
		print(`gate {table.concat(args, " ")} failed ({r.code}):\n{r.stdout}{r.stderr}`)
	end
	return r.ok, r.stdout .. r.stderr, log
end

return t.spec("c0120 each project has its own gate", function(it)
	it(
		"the plan of the real tree: every home's folders, pickman's places and both projects' specs",
		function()
			local ok, out = plan(root, {})
			t.expect(ok).toBe(true)
			local format = words(lineOf(out, "format"))
			for _, d in
				{
					"pickman/src",
					"pickman/tests",
					"pickman/scripts",
					"pickman/.tracker",
					"tests",
					"scripts",
					"z-nile",
					"z-nile/.tracker",
				}
			do
				t.expect(format[d]).toBe(true)
			end
			t.expect(format.src or format.tracker or false).toBe(false)
			t.expect(lineOf(out, "lint")).toBe(lineOf(out, "format"))
			t.expect(lineOf(out, "types (Roblox)")).toBe("pickman/src, from pickman")
			local lune = lineOf(out, "types (Lune)")
			for _, d in { "pickman/tests", "pickman/scripts", "tests", "scripts", "z-nile" } do
				t.expect(words(lune)[d]).toBe(true)
			end
			t.expect(has(lune, ".tracker")).toBe(false)
			t.expect(has(out, "build: pickman/default.project.json\nbuild: pickman/lobby.project.json\n"))
				.toBe(true)
			t.expect(has(out, "specs: pickman, from pickman\nspecs: z-nile, from .\n")).toBe(true)
		end
	)

	it(
		"--project keeps one project's stages; pickman/check.sh is --project pickman; an unknown name exits 2",
		function()
			local _, p = plan(root, { "--project", "pickman" })
			t.expect(has(p, "specs: pickman, from pickman")).toBe(true)
			t.expect(has(p, "specs: z-nile")).toBe(false)
			t.expect(words(lineOf(p, "format"))["z-nile"]).toBe(nil)
			local _, z = plan(root, { "--project", "z-nile" })
			t.expect(has(z, "build:")).toBe(false)
			t.expect(has(z, "types (Roblox)")).toBe(false)
			t.expect(has(z, "pickman")).toBe(false)
			local r = process.exec("bash", { "pickman/check.sh", "--plan" })
			t.expect(r.stdout).toBe(p)
			local bad = process.exec("bash", { "z-nile/check.sh", "--plan", "--project", "nope" })
			t.expect(bad.code).toBe(2)
			t.expect(has(bad.stderr, "no project nope")).toBe(true)
		end
	)

	it("--plan writes nothing", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		local dir = stubbed("plan")
		local ok = gate(dir, { "--plan" })
		t.expect(ok).toBe(true)
		t.expect(fs.isDir(`{dir}/.cache`) or fs.isDir(`{dir}/pickman/.cache`)).toBe(false)
		t.expect(fs.isFile(`{dir}/pickman/sourcemap.json`)).toBe(false)
		t.expect(fs.isFile(`{dir}/calls.log`)).toBe(false)
	end)

	it(
		"the full gate runs each project's stages from the right folder, and each project's specs from its home",
		function()
			local dir = stubbed("full")
			local ok, out, log = gate(dir, { "--full" })
			t.expect(ok).toBe(true)
			t.expect(has(out, "GATE PASSED (full)")).toBe(true)
			local here = (string.gsub(process.exec("pwd", { "-P" }, { cwd = dir }).stdout, "%s+$", ""))
			-- the sourcemap and the Roblox types from pickman/, the builds of its two project files from the root
			t.expect(has(log, `{here}/pickman|rojo|sourcemap default.project.json -o sourcemap.json`))
				.toBe(true)
			t.expect(has(log, `{here}/pickman|luau-lsp|analyze`)).toBe(true)
			t.expect(has(log, "--sourcemap=sourcemap.json")).toBe(true)
			t.expect(has(log, `{here}|rojo|build pickman/default.project.json -o`)).toBe(true)
			t.expect(has(log, `{here}|rojo|build pickman/lobby.project.json -o`)).toBe(true)
			-- the gate's places in the fixture home's own .cache (spelled in two parts: not a fixture folder of this run)
			local built = `{dir}/pickman/.` .. "cache/"
			t.expect(fs.readFile(`{built}check.rbxl`)).toBe("built\n")
			t.expect(fs.readFile(`{built}check-lobby.rbxl`)).toBe("built\n")
			-- each project's specs from its home
			t.expect(has(log, `{here}/pickman|lune|run tests/run --`)).toBe(true)
			t.expect(has(log, `{here}|lune|run tests/run --`)).toBe(true)
		end
	)

	it("--project pickman runs pickman's specs alone, from pickman/", function()
		local dir = stubbed("one")
		local ok, _, log = gate(dir, { "--full", "--project", "pickman" })
		t.expect(ok).toBe(true)
		local here = (string.gsub(process.exec("pwd", { "-P" }, { cwd = dir }).stdout, "%s+$", ""))
		t.expect(has(log, `{here}/pickman|lune|run tests/run --`)).toBe(true)
		t.expect(has(log, `{here}|lune|run tests/run --`)).toBe(false)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
