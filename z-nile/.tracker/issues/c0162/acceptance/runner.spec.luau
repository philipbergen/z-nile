--!strict
-- c0162 AC2 and AC3: the spec runner runs on the Lune rokit.toml pins, and says which. A copy of the runner, its harness
-- and the guards is set up under .cache/c0162-pin with a rokit.toml of its own; it is run by the real Lune binary
-- (rokit's shim would resolve the fixture's pin, which is not installed), with `lune` on PATH being that binary too.
-- On the pinned Lune the outermost run prints `tests/run: lune <v> (rokit.toml pins <v>)` first and runs. On another
-- Lune, the outermost run first tries rokit's (`$HOME/.rokit/bin` first on PATH, probed with `lune --version`) and says
-- so; when that is not the pin either it refuses before any spec runs, naming both versions, the rokit.toml and the
-- fix. Every inner run (the guarded child, a worker, a nested run) checks its own version and refuses on another. A
-- rokit.toml that is ambiguous refuses; a fixture with none takes the pin of the folder above it (the repository's).
local fs = require("@lune/fs")
local lunepin = require("@tests/lib/lunepin")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0162-pin`
local PIN = assert((lunepin.pinned(fs.readFile(`{root}/rokit.toml`))), "the repository pins a lune")
local HOME = process.env.HOME or ""
-- the pinned Lune itself, as rokit stores it (CI installs it the same way: z-nile/setup.sh)
local REAL = `{HOME}/.rokit/tool-storage/lune-org/lune/{PIN}/lune`
local R = "req" .. "uire"

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function copy(rel: string)
	fs.writeDir(string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string)
	t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{base}/{rel}` }).ok).toBe(true)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- a planted spec that leaves a mark when it runs
local MARK = `{base}/z-nile/.cache/ran`
local SPEC = table.concat({
	"--!strict",
	`local fs = {R}("@lune/fs")`,
	`return \{ name = "planted", cases = \{ \{ name = "marks", fn = function()`,
	`\tfs.writeDir("{base}/z-nile/.cache")`,
	`\tfs.writeFile("{MARK}", "x")`,
	"end } } }",
	"",
}, "\n")

-- the fixture's bin: `lune` is the pinned binary itself, not rokit's shim
local BIN = `{base}/bin`
local function setup(rokit: string?)
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
	for _, rel in { "z-nile/tests/run.luau", "z-nile/tests/lib", "z-nile/lib", "z-nile/.luaurc", ".luaurc" } do
		copy(rel)
	end
	write("z-nile/.tracker/.gitkeep", "")
	write("z-nile/tests/tooling/a.spec.luau", SPEC)
	write("z-nile/tests/tooling/b.spec.luau", SPEC)
	if rokit then
		write("rokit.toml", rokit)
	end
	fs.writeDir(BIN)
	t.expect(process.exec("ln", { "-s", REAL, `{BIN}/lune` }).ok).toBe(true)
end
local function pins(v: string): string
	return `[tools]\nlune = "lune-org/lune@{v}"\n`
end

type Run = { code: number, out: string, err: string }
local function run(env: { [string]: string }?, args: { string }?): Run
	local e: { [string]: string } = {
		PATH = `{BIN}:/usr/bin:/bin:/usr/sbin:/sbin`,
		HOME = `{base}/home`, -- no rokit here unless a case puts one
		PICKMAN_OPEN_GUARD = "",
		PICKMAN_JOBS = "",
	}
	local extra: { [string]: string } = env or {}
	for k, v in extra do
		e[k] = v
	end
	local argv = { "run", "tests/run", "--" }
	local files: { string } = args or { "tests/tooling/a.spec.luau" }
	for _, a in files do
		table.insert(argv, a)
	end
	local r = process.exec(REAL, argv, { cwd = `{base}/z-nile`, env = e })
	return { code = r.code, out = r.stdout, err = r.stderr }
end

-- a rokit bin in the fixture's HOME whose `lune` logs each call, says `--version` is `version`, and runs the pinned one
local LOG = `{base}/home/calls.log`
local function rokitBin(version: string)
	fs.writeDir(`{base}/home/.rokit/bin`)
	local script = table.concat({
		"#!/bin/sh",
		`echo "$*" >> "{LOG}"`,
		`if [ "$1" = "--version" ]; then echo "lune {version}"; exit 0; fi`,
		`exec "{REAL}" "$@"`,
		"",
	}, "\n")
	fs.writeFile(`{base}/home/.rokit/bin/lune`, script)
	t.expect(process.exec("chmod", { "+x", `{base}/home/.rokit/bin/lune` }).ok).toBe(true)
end

return t.spec("c0162 the runner runs on the pinned Lune", function(it)
	it("the pinned Lune is where rokit keeps it (the fixture's precondition)", function()
		t.expect(fs.isFile(REAL)).toBe(true)
	end)

	it("on the pinned Lune the outermost run names the version first, and runs", function()
		setup(pins(PIN))
		local r = run()
		t.expect(r.code).toBe(0)
		t.expect(string.match(r.out, "^[^\n]*")).toBe(`tests/run: lune {PIN} (rokit.toml pins {PIN})`)
		t.expect(fs.isFile(MARK)).toBe(true)
	end)

	it("the version line comes once per run: workers and the guarded child print none", function()
		setup(pins(PIN))
		local r = run(nil, { "--jobs", "2", "tests/tooling/a.spec.luau", "tests/tooling/b.spec.luau" })
		t.expect(r.code).toBe(0)
		local n = 0
		for _ in string.gmatch(r.out, "tests/run: lune ") do
			n += 1
		end
		t.expect(n).toBe(1)
		t.expect(has(r.out, "2 passed, 0 failed, 2 spec files")).toBe(true)
	end)

	it(
		"on another Lune with no rokit Lune to try, it refuses before any spec, naming both and the fix",
		function()
			setup(pins("9.9.9"))
			local r = run()
			t.expect(r.code).toBe(2)
			t.expect(fs.isFile(MARK)).toBe(false)
			t.expect(has(r.err, `Lune {PIN}`)).toBe(true)
			t.expect(has(r.err, "pins 9.9.9")).toBe(true)
			t.expect(has(r.err, `{base}/rokit.toml`)).toBe(true)
			t.expect(has(r.err, 'PATH="$HOME/.rokit/bin:$PATH"')).toBe(true)
			t.expect(has(r.out, "passed,")).toBe(false)
		end
	)

	it(
		"on another Lune it first tries rokit's: the probe and the run go through $HOME/.rokit/bin, and it says so",
		function()
			setup(pins("9.9.9"))
			rokitBin("9.9.9")
			local r = run()
			local calls = if fs.isFile(LOG) then fs.readFile(LOG) else ""
			t.expect(has(calls, "--version")).toBe(true)
			t.expect(has(calls, "run tests/run")).toBe(true)
			t.expect(has(r.out, `tests/run: lune 9.9.9 (rokit.toml pins 9.9.9; this shell's lune is {PIN}`))
				.toBe(true)
			-- rokit's `lune` here is the same binary underneath, so the guarded child finds itself on {PIN} and refuses
			t.expect(r.code).toBe(2)
			t.expect(has(r.err, `this is Lune {PIN}, but rokit.toml`)).toBe(true)
			t.expect(fs.isFile(MARK)).toBe(false)
		end
	)

	it("a rokit Lune that is not the pin either is refused, naming the one it found", function()
		setup(pins("9.9.9"))
		rokitBin("0.11.1")
		local r = run()
		t.expect(r.code).toBe(2)
		t.expect(has(r.err, "this is Lune 0.11.1")).toBe(true)
		t.expect(has(r.err, "pins 9.9.9")).toBe(true)
		local calls = fs.readFile(LOG)
		t.expect(has(calls, "run tests/run")).toBe(false) -- never relaunched on it
	end)

	it("an inner run on another Lune refuses, and tries nothing", function()
		setup(pins("9.9.9"))
		rokitBin("9.9.9")
		fs.writeDir(`{base}/guard`)
		fs.writeFile(`{base}/guard/open`, "")
		local r = run({ PICKMAN_OPEN_GUARD = `{base}/guard` })
		t.expect(r.code).toBe(2)
		t.expect(has(r.err, `this is Lune {PIN}, but rokit.toml`)).toBe(true)
		t.expect(fs.isFile(LOG)).toBe(false)
		t.expect(fs.isFile(MARK)).toBe(false)
	end)

	it("an ambiguous rokit.toml refuses, naming the problem", function()
		setup(pins(PIN) .. `lune = "lune-org/lune@{PIN}"\n`)
		local r = run()
		t.expect(r.code).toBe(2)
		t.expect(has(r.err, "cannot check the Lune version")).toBe(true)
		t.expect(has(r.err, "twice")).toBe(true)
		t.expect(fs.isFile(MARK)).toBe(false)
	end)

	it("a copy with no rokit.toml takes the pin of the folder above it", function()
		setup(nil)
		local r = run()
		t.expect(r.code).toBe(0)
		t.expect(string.match(r.out, "^[^\n]*")).toBe(`tests/run: lune {PIN} (rokit.toml pins {PIN})`)
		fs.removeDir(base)
	end)
end)
