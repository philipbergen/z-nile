--!strict
-- A copy of c0165's gatefix (acceptance/gatefix.luau, sequestered), for the executor's own tooling specs: the gate fixtures (split by mechanism so each file stays short, design
-- reviews 002 F9 and 007 F5: a file holds at most 4 fixture builds and 10 gate runs, about 40 s idle). A fixture is a repository under the calling spec's own .cache folder: a copy of the tooling with a
-- tiny pickman home whose specs append their name to ran.log when they run, so "ran" and "reused" are counted, not
-- inferred from output. Static tools are stubs; lune, git, perl and sqlite3 are real. The fixture's own main checkout
-- holds its db (.claude/.znile_tests.sqlite under the fixture), never the real one.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local gatefix = {} -- (the module is called gatefix inside this copy)

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
local REAL_HOME = process.env.HOME or ""
local REAL_LUNE = (string.gsub(process.exec("sh", { "-c", "command -v lune" }).stdout, "%s+$", ""))
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
-- a hold lasts at most this many 0.1 s polls, so a wrong implementation fails a case instead of hanging the suite
local HOLD_POLLS = 600

gatefix.AB = { "--", "tests/unit/a.spec.luau", "tests/unit/b.spec.luau" }

function gatefix.write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
function gatefix.has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
function gatefix.count(text: string, line: string): number
	local n = 0
	for l in string.gmatch(text, "[^\n]+") do
		if l == line then
			n += 1
		end
	end
	return n
end
function gatefix.trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

-- a fixture spec: logs its name to ran.log, then, as asked, requires a src module, reads a data file, holds, opens a
-- browser, quits its process, writes a file or fails
export type SpecOpts = {
	needs: string?,
	expect: number?,
	reads: string?,
	-- holds while <dir>/hold.marker exists (every run of it)
	hold: boolean?,
	broken: boolean?,
	writes: { path: string, text: string }?,
	opens: boolean?,
	quits: boolean?,
}
function gatefix.specText(dir: string, name: string, o: SpecOpts): string
	local lines = {
		"--!strict",
		`local process = {R}("@lune/process")`,
		`local fs = {R}("@lune/fs")`,
		`local t = {R}("@tests/lib/t")`,
	}
	if o.needs then
		table.insert(lines, `local M = {R}("../../src/{o.needs}")`)
	end
	table.insert(lines, `return t.spec("{name}", function(it)`)
	table.insert(lines, '\tit("runs", function()')
	table.insert(lines, `\t\tprocess.exec("sh", \{ "-c", 'echo {name} >> "$1"', "_", "{dir}/ran.log" })`)
	if o.hold then
		table.insert(
			lines,
			`\t\tfor _ = 1, {HOLD_POLLS} do if not fs.isFile("{dir}/hold.marker") then break end process.exec("sleep", \{ "0.1" }) end`
		)
	end
	if o.needs then
		table.insert(lines, `\t\tt.expect(M.value).toBe({o.expect or 1})`)
	end
	if o.reads then
		table.insert(lines, `\t\tt.expect(fs.readFile("{o.reads}")).toBe("ok\\n")`)
	end
	if o.opens then
		-- the runner's browser guard answers this (its recording stub), and fails the run after the spec passed
		table.insert(lines, '\t\tprocess.exec("open", { "-O", "x" })')
	end
	if o.quits then
		-- ends the runner's process (one job: in process) before it can write its results
		table.insert(lines, "\t\tprocess.exit(0)")
	end
	if o.writes then
		table.insert(lines, `\t\tfs.writeFile("{o.writes.path}", "{o.writes.text}")`)
	end
	if o.broken then
		table.insert(lines, "\t\tt.expect(1).toBe(2)")
	end
	table.insert(lines, "\tend)")
	table.insert(lines, "end)")
	return table.concat(lines, "\n") .. "\n"
end

function gatefix.stubTools(dir: string)
	fs.writeDir(`{dir}/bin`)
	for _, tool in { "stylua", "selene", "luau-lsp" } do
		gatefix.write(`{dir}/bin/{tool}`, "#!/bin/sh\nexit 0\n")
	end
	gatefix.write(
		`{dir}/bin/rojo`,
		'#!/bin/sh\nif [ "$1" = --version ]; then echo "rojo 7.7.0"; exit 0; fi\no=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done\n[ -n "$o" ] && echo built > "$o"\nexit 0\n'
	)
	gatefix.write(
		`{dir}/bin/curl`,
		'#!/bin/sh\no=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "-- defs" > "$o"\n'
	)
	-- the real lune, with the real HOME: the fixture's HOME keeps rokit's real tools from shadowing the stubs, but a
	-- rokit shim finds its tools through HOME (so does lune's own setup)
	gatefix.write(`{dir}/bin/lune`, `#!/bin/sh\nHOME="{REAL_HOME}" exec "{REAL_LUNE}" "$@"\n`)
	for _, tool in { "stylua", "selene", "luau-lsp", "rojo", "curl", "lune" } do
		process.exec("chmod", { "+x", `{dir}/bin/{tool}` })
	end
end

-- The fixture repository `<base>/<name>`: the tooling and a pickman home with specs a (needs A), b (needs B), text
-- (reads data/x.txt), slow1 (holds while hold.marker exists), plus `extra`'s specs; `setup` adds files before
-- the base commit. Committed on main, then checked out on a branch `work`.
export type MakeOpts = { extra: { [string]: SpecOpts }?, setup: ((dir: string) -> ())? }
function gatefix.make(base: string, name: string, opts: MakeOpts?): string
	local o: MakeOpts = opts or {}
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	engine.copy(root, dir)
	process.exec("cp", { `{root}/.luaurc`, `{dir}/.luaurc` })
	-- engine.copy leaves z-nile/tests out: the fixture needs the runner and its library (as results.spec copies them)
	fs.writeDir(`{dir}/z-nile/tests`)
	for _, rel in { "z-nile/tests/run.luau", "z-nile/tests/lib" } do
		t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{dir}/{rel}` }).ok).toBe(true)
	end
	-- a fixture HOME, so check.sh's $HOME/.rokit/bin can't put the real tools before the stubs (as gate-homes.spec does)
	local version = string.match(process.exec("lune", { "--version" }).stdout, "(%d+%.%d+%.%d+)") or "0.0.0"
	fs.writeDir(`{dir}/home/.lune/.typedefs/{version}`)
	fs.writeFile(`{dir}/z-nile/projects.toml`, REGISTRY)
	if fs.isDir(`{dir}/z-nile/skills`) then
		fs.removeDir(`{dir}/z-nile/skills`) -- no skills stage in the fixture
	end
	gatefix.write(
		`{dir}/.gitignore`,
		".cache/\nsourcemap.json\n/.claude/.znile_tests.sqlite*\nran.log\nhold.marker\nbin/\nbin-*/\nhome/\n*.out\n*.rc\n"
	)
	gatefix.write(`{dir}/pickman/.tracker/.gitkeep`, "")
	gatefix.write(`{dir}/z-nile/.tracker/.gitkeep`, "")
	gatefix.write(`{dir}/pickman/tests/run.luau`, `return {R}("../../z-nile/tests/run")\n`)
	gatefix.write(`{dir}/pickman/tests/inputs.tsv`, "# extra inputs per spec\n")
	gatefix.write(`{dir}/pickman/src/A.luau`, "return { value = 1 }\n")
	gatefix.write(`{dir}/pickman/src/B.luau`, "return { value = 1 }\n")
	gatefix.write(`{dir}/pickman/src/C.luau`, "return { value = 1 }\n")
	gatefix.write(`{dir}/pickman/data/x.txt`, "ok\n")
	local specs: { [string]: SpecOpts } = {
		a = { needs = "A" },
		b = { needs = "B" },
		text = { reads = "data/x.txt" },
		slow1 = { hold = true },
	}
	for n, spec in o.extra or ({} :: { [string]: SpecOpts }) do
		specs[n] = spec
	end
	for n, spec in specs do
		gatefix.write(`{dir}/pickman/tests/unit/{n}.spec.luau`, gatefix.specText(dir, n, spec))
		local watched: { string } = {}
		if spec.needs then
			table.insert(watched, `pickman/src/{spec.needs}.luau`)
		end
		if spec.reads then
			local rel = spec.reads
			if string.sub(rel, 1, 8) ~= "pickman/" then
				rel = `pickman/{rel}`
			end
			table.insert(watched, rel)
		end
		table.sort(watched)
		if #watched > 0 then
			gatefix.write(`{dir}/pickman/tests/unit/{n}.watch.txt`, table.concat(watched, "\n") .. "\n")
		end
	end
	if o.setup then
		o.setup(dir)
	end
	gatefix.stubTools(dir)
	t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
	fixture.git(dir, { "config", "user.name", "c0165-gate" })
	fixture.git(dir, { "config", "user.email", "c0165-gate@example.invalid" })
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "commit", "-qm", "base" })
	fixture.git(dir, { "checkout", "-q", "-b", "work" })
	return dir
end

function gatefix.env(dir: string, extra: { [string]: string }?): { [string]: string }
	local e: { [string]: string } = {
		PATH = `{dir}/bin:{process.env.PATH or ""}`,
		PICKMAN_JOBS = "2",
		HOME = `{dir}/home`,
		-- "" makes the fixture's runner the outermost for the browser guard (it installs its own stubs and fails its own
		-- run), instead of leaving an opener to the real run around this spec
		PICKMAN_OPEN_GUARD = "",
	}
	for k, v in (extra or {}) :: { [string]: string } do
		e[k] = v
	end
	return e
end
-- `lune run z-nile/specs -- run --project pickman <args>` in the fixture
function gatefix.specs(dir: string, args: { string }, extra: { [string]: string }?): (boolean, string)
	local argv = { "run", "z-nile/specs", "--", "run", "--project", "pickman" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = dir, env = gatefix.env(dir, extra) })
	if not r.ok then
		print(`specs {table.concat(args, " ")} failed ({r.code}):\n{r.stdout}{r.stderr}`)
	end
	return r.ok, r.stdout .. r.stderr
end
-- `bash z-nile/check.sh <args>` in the fixture, exactly as given (no --project added)
function gatefix.gateRaw(dir: string, args: { string }, extra: { [string]: string }?): (boolean, string)
	local argv = { "z-nile/check.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, { cwd = dir, env = gatefix.env(dir, extra) })
	if not r.ok then
		print(`gate {table.concat(args, " ")} failed ({r.code}):\n{r.stdout}{r.stderr}`)
	end
	return r.ok, r.stdout .. r.stderr
end
-- `bash z-nile/check.sh --project pickman <args>` in the fixture
function gatefix.gate(dir: string, args: { string }, extra: { [string]: string }?): (boolean, string)
	local argv = { "--project", "pickman" }
	for _, a in args do
		table.insert(argv, a)
	end
	return gatefix.gateRaw(dir, argv, extra)
end
-- the exit status and output of `bash z-nile/check.sh --project pickman <args>`, nothing printed (for a refusal)
function gatefix.gateStatus(dir: string, args: { string }, extra: { [string]: string }?): (number, string)
	local argv = { "z-nile/check.sh", "--project", "pickman" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, { cwd = dir, env = gatefix.env(dir, extra) })
	return r.code, r.stdout .. r.stderr
end
-- `lune run z-nile/affected -- --project pickman <args>` in the fixture, its stdout trimmed
function gatefix.affected(dir: string, args: { string }): string
	local argv = { "run", "z-nile/affected", "--", "--project", "pickman" }
	for _, a in args do
		table.insert(argv, a)
	end
	return gatefix.trim(process.exec("lune", argv, { cwd = dir, env = gatefix.env(dir) }).stdout)
end
-- one sqlite3 query on the fixture's db, its output trimmed
function gatefix.sql(dir: string, query: string): string
	return gatefix.trim(process.exec("sqlite3", { `{dir}/.claude/.znile_tests.sqlite`, query }).stdout)
end
-- one sqlite3 statement that changes the fixture's db (seeding a row)
function gatefix.sqlWrite(dir: string, statement: string)
	local r = process.exec("sqlite3", { `{dir}/.claude/.znile_tests.sqlite`, statement })
	if not r.ok then
		error(`sqlite3 {statement} failed: {r.stderr}`)
	end
end
function gatefix.ran(dir: string): string
	return if fs.isFile(`{dir}/ran.log`) then fs.readFile(`{dir}/ran.log`) else ""
end
function gatefix.clearRan(dir: string)
	if fs.isFile(`{dir}/ran.log`) then
		fs.removeFile(`{dir}/ran.log`)
	end
end
-- a second worktree of the fixture at its HEAD, with its own stub tools
function gatefix.worktree(dir: string, path: string)
	if fs.isDir(path) then
		fs.removeDir(path)
	end
	fixture.git(dir, { "worktree", "add", "-q", "--detach", path })
	gatefix.stubTools(path)
end

-- Two orchestrators at once, one in `dir` and one in `other` (a worktree of it), both running `args`, while
-- <dir>/hold.marker holds `spec` (a held fixture spec, both runs log its name to <dir>/ran.log). `strict`: the marker is
-- removed only once the spec has started twice, so the two runs overlap by construction, never by timing, and neither
-- waited for the other (proof-interim.luau, today's behaviour). Not strict: the marker is also removed 3 s after the
-- spec first started, so a second run that waits for the first (c0238) cannot hold the case until the poll limit. Both
-- release at once when both orchestrators have ended (a run that fails early does not hold the case 60 s).
-- Returns each run's output and exit code.
export type Pair = { out1: string, out2: string, rc1: string, rc2: string }
function gatefix.together(dir: string, other: string, spec: string, args: { string }, strict: boolean): Pair
	fs.writeFile(`{dir}/hold.marker`, "")
	local outs = `{dir}/..`
	local r = process.exec("bash", {
		"-c",
		"d=$1 o=$2 x=$3 spec=$4 strict=$5; shift 5; "
			.. '(cd "$d"; PATH="$d/bin:$PATH" lune run z-nile/specs -- run --project pickman "$@" > "$x/p1.out" 2>&1; echo "$?" > "$x/p1.rc") & '
			.. '(cd "$o"; PATH="$o/bin:$PATH" lune run z-nile/specs -- run --project pickman "$@" > "$x/p2.out" 2>&1; echo "$?" > "$x/p2.rc") & '
			.. `n=0; for i in $(seq 1 {HOLD_POLLS}); do c=$(grep -c "^$spec$" "$d/ran.log" 2>/dev/null); [ "$c" = 2 ] && break; `
			.. 'if [ "$strict" != 1 ] && [ "${c:-0}" -ge 1 ]; then n=$((n+1)); [ "$n" -ge 30 ] && break; fi; [ -f "$x/p1.rc" ] && [ -f "$x/p2.rc" ] && break; sleep 0.1; done; '
			.. 'rm -f "$d/hold.marker"; wait',
		"_",
		dir,
		other,
		outs,
		spec,
		if strict then "1" else "0",
		table.unpack(args),
	}, { env = { PICKMAN_OPEN_GUARD = "", PICKMAN_JOBS = "2" } })
	t.expect(r.ok).toBe(true)
	return {
		out1 = fs.readFile(`{outs}/p1.out`),
		out2 = fs.readFile(`{outs}/p2.out`),
		rc1 = gatefix.trim(fs.readFile(`{outs}/p1.rc`)),
		rc2 = gatefix.trim(fs.readFile(`{outs}/p2.rc`)),
	}
end

-- A lune wrapper that lets the real runner finish, then edits its merged results before the orchestrator reads them.
-- `body` gets `doc`. Returns a PATH with the wrapper first.
function gatefix.editResults(dir: string, name: string, body: string): string
	local script = `{dir}/{name}.luau`
	gatefix.write(
		script,
		'local fs = require("@lune/fs")\nlocal serde = require("@lune/serde")\nlocal process = require("@lune/process")\n'
			.. 'local doc = serde.decode("json", fs.readFile(process.args[#process.args]))\n'
			.. body
			.. '\nfs.writeFile(process.args[#process.args], serde.encode("json", doc))\n'
	)
	gatefix.write(
		`{dir}/bin-{name}/lune`,
		'#!/bin/sh\nif [ "$1" = run ] && [ "$2" = tests/run ]; then\n'
			.. `"{dir}/bin/lune" "$@"\nrc=$?\n`
			.. `if [ -f "$PICKMAN_RESULTS" ]; then "{dir}/bin/lune" run "{script}" -- "$PICKMAN_RESULTS"; fi\n`
			.. 'exit "$rc"\nfi\n'
			.. `exec "{dir}/bin/lune" "$@"\n`
	)
	process.exec("chmod", { "+x", `{dir}/bin-{name}/lune` })
	return `{dir}/bin-{name}:{dir}/bin:{process.env.PATH or ""}`
end
function gatefix.weakJail(dir: string): string
	return gatefix.editResults(dir, "weak-jail", 'doc.jail = "outer sandbox (protects the repository)"')
end
function gatefix.omitResult(dir: string, spec: string): string
	return gatefix.editResults(dir, "omit-result", [[for i, f in doc.files do
	if f.file == "]] .. spec .. [[" then table.remove(doc.files, i) break end
end]])
end
return gatefix
