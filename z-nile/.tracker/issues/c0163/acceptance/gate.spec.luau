--!strict
-- c0163 AC3: the gate fails on a committed conflict marker in every mode. z-nile/check.sh runs for real in a fixture
-- repository (tests/lib/trackerfix, under .cache/c0163-gate) with stub tools, as c0120's gate spec does; the stub
-- `lune` hands only `./zn markers` to the real Lune. A marker fails `--affected` and `--full` alike, with a FAILED
-- markers stage naming `<file>:<line>`; a clean tree passes both. `--plan` lists the stage in both modes.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local LT, GT, EQ = string.rep("<", 7), string.rep(">", 7), string.rep("=", 7)
local CONFLICT = table.concat({ "a", LT .. " HEAD", "b", EQ, "c", GT .. " origin/main", "" }, "\n")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

-- the real Lune, and the HOME its rokit shim finds its tools through (the gate runs with the fixture's HOME)
local REAL_LUNE = (string.gsub(process.exec("sh", { "-c", "command -v lune" }).stdout, "%s+$", ""))
local REAL_HOME = process.env.HOME or ""

local f: trackerfix.Fixture
local function setup()
	f = trackerfix.new("c0163-gate", {
		["pickman/src/shared/keep.luau"] = "--!strict\nreturn {}\n",
		["pickman/default.project.json"] = '{ "name": "g", "tree": { "$className": "DataModel" } }\n',
	})
	local bin = `{f.base}/bin`
	fs.writeDir(`{f.base}/home/.lune/.typedefs/0.10.5`)
	for _, tool in { "stylua", "selene", "luau-lsp" } do
		write(`{bin}/{tool}`, "#!/bin/sh\nexit 0\n")
	end
	write(
		`{bin}/rojo`,
		'#!/bin/sh\no=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done\n[ -n "$o" ] && echo built > "$o"\n'
	)
	write(
		`{bin}/curl`,
		'#!/bin/sh\no=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "-- defs" > "$o"\n'
	)
	write(
		`{bin}/lune`,
		'#!/bin/sh\nif [ "$1" = --version ]; then echo "lune 0.10.5"; exit 0; fi\n'
			.. `if [ "$2" = z-nile/engine/main ] && [ "$4" = markers ]; then HOME="{REAL_HOME}" exec "{REAL_LUNE}" "$@"; fi\n`
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --projects ]; then\n'
			.. '  printf "pickman\\tpickman\\tpickman/.tracker\\nz-nile\\tz-nile\\tz-nile/.tracker\\n"; exit 0\nfi\n'
			.. 'if [ "$2" = z-nile/roots ] && [ "$4" = --luau-dirs ]; then echo "pickman/src z-nile"; exit 0; fi\n'
			.. "exit 0\n"
	)
	for _, tool in { "stylua", "selene", "luau-lsp", "rojo", "curl", "lune" } do
		process.exec("chmod", { "+x", `{bin}/{tool}` })
	end
end
local function gate(args: { string }): (boolean, string)
	local argv = { "z-nile/check.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, {
		cwd = f.main,
		env = { PATH = `{f.base}/bin:{process.env.PATH or ""}`, HOME = `{f.base}/home` },
	})
	return r.ok, r.stdout .. r.stderr
end

return t.spec("c0163 the gate's marker stage", function(it)
	it("--plan lists the marker stage in --affected and --full", function()
		setup()
		for _, mode in { "--affected", "--full" } do
			local ok, out = gate({ mode, "--plan" })
			t.expect(ok).toBe(true)
			t.expect(has(out, "\nmarkers: ")).toBe(true)
		end
	end)

	it("a clean tree passes the gate in both modes", function()
		setup()
		for _, mode in { "--affected", "--full" } do
			local ok, out = gate({ mode })
			if not ok then
				error(`clean {mode} failed:\n{out}`, 0)
			end
			t.expect(has(out, "== markers")).toBe(true)
		end
	end)

	it("a committed marker fails the gate in both modes, naming the file and line", function()
		setup()
		fs.writeFile(`{f.main}/merged.md`, CONFLICT)
		fixture.git(f.main, { "add", "merged.md" })
		fixture.git(f.main, { "commit", "-q", "-m", "a bad merge" })
		for _, mode in { "--affected", "--full" } do
			local ok, out = gate({ mode })
			t.expect(ok).toBe(false)
			t.expect(has(out, "merged.md:2: conflict marker")).toBe(true)
			t.expect(has(out, "GATE PASSED")).toBe(false)
		end
	end)
end)
