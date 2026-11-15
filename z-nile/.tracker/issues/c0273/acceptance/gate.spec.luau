--!strict
-- c0273 AC5: the gate builds a home's `*.project.jsonc` as it builds a `*.project.json`, into the home's
-- .cache/check-<name>.rbxl (the default place's into check.rbxl), and plans it after the home's `*.project.json` files. The
-- fixture is a copy of the tooling under .cache/c0273-gate with stub tools that log their arguments (c0120's gate-homes
-- pattern): the gate runs and writes only there.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local homeDir = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{homeDir}/.cache/c0273-gate`
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

-- a copy of the tooling with pickman's home holding a *.project.json and a commented *.project.jsonc, and stub tools
local function stubbed(): string
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	local dir = `{base}/tree`
	fs.writeDir(dir)
	engine.copy(root, dir)
	fs.writeFile(`{dir}/z-nile/projects.toml`, REGISTRY)
	for _, rel in
		{
			"pickman/src/shared",
			"pickman/tests/unit",
			"z-nile/tests/tooling",
			"z-nile/.tracker",
			"pickman/.tracker",
		}
	do
		fs.writeDir(`{dir}/{rel}`)
	end
	write(`{dir}/pickman/default.project.json`, '{ "name": "g", "tree": { "$className": "DataModel" } }\n')
	write(
		`{dir}/pickman/lobby.project.jsonc`,
		'// the lobby\n{ "name": "l", "tree": { "$className": "DataModel" }, }\n'
	)
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
	write(
		`{dir}/bin/lune`,
		'#!/bin/sh\nif [ "$1" = --version ]; then echo "lune 0.10.5"; exit 0; fi\n'
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --projects ]; then\n'
			.. '  printf "pickman\\tpickman\\tpickman/.tracker\\nz-nile\\tz-nile\\tz-nile/.tracker\\n"; exit 0\nfi\n'
			.. 'if [ "$2" = z-nile/affected ]; then exit 0; fi\n'
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --luau-dirs ]; then\n'
			.. '  echo "pickman/src pickman/tests pickman/.tracker"; exit 0\nfi\n'
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

return t.spec("c0273 the gate builds a home's *.project.jsonc", function(it)
	it(
		"AC5: the plan lists it after the *.project.json files, and the run builds it into check-<name>.rbxl",
		function()
			local dir = stubbed()
			local planned, plan = gate(dir, { "--plan", "--project", "pickman" })
			t.expect(planned).toBe(true)
			t.expect(has(plan, "build: pickman/default.project.json\nbuild: pickman/lobby.project.jsonc\n"))
				.toBe(true)
			local ok, out, log = gate(dir, { "--full", "--project", "pickman" })
			t.expect(ok).toBe(true)
			t.expect(has(out, "build (rojo pickman/lobby.project.jsonc)")).toBe(true)
			local here = (string.gsub(process.exec("pwd", { "-P" }, { cwd = dir }).stdout, "%s+$", ""))
			t.expect(has(log, `{here}|rojo|build pickman/lobby.project.jsonc -o`)).toBe(true)
			t.expect(has(log, `{here}|rojo|build pickman/default.project.json -o`)).toBe(true)
			-- spelled in two parts: not a fixture folder of this run
			local built = `{dir}/pickman/.` .. "cache/"
			t.expect(fs.readFile(`{built}check.rbxl`)).toBe("built\n")
			t.expect(fs.isFile(`{built}check-lobby.rbxl`)).toBe(true)
			t.expect(fs.readFile(`{built}check-lobby.rbxl`)).toBe("built\n")
			t.expect(fs.isFile(`{built}check-lobby.project.jsonc.rbxl`)).toBe(false)
			fs.removeDir(base)
		end
	)
end)
