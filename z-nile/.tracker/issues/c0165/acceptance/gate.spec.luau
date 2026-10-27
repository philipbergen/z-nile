--!strict
-- c0165 AC5, AC7, AC8 through the real tools: the orchestrator (`z-nile/specs`) and the gate (`z-nile/check.sh`) in a
-- fixture repository that is a copy of the tooling with a tiny pickman home. Every fixture spec appends its name to
-- ran.log when it runs, so "ran" and "reused" are counted, not inferred from output. The fixture's own main checkout
-- holds its db (.claude/.znile_tests.sqlite under the fixture), never the real one. Static tools are stubs; lune, git,
-- perl and sqlite3 are real. Fixtures under .cache/c0165-gate.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0165-gate`
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
local REAL_HOME = process.env.HOME or ""
local REAL_LUNE = (string.gsub(process.exec("sh", { "-c", "command -v lune" }).stdout, "%s+$", ""))
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, line: string): number
	local n = 0
	for l in string.gmatch(text, "[^\n]+") do
		if l == line then
			n += 1
		end
	end
	return n
end

-- a fixture spec: logs its name to ran.log, optionally requires a src module, reads a data file, sleeps or hangs
type SpecOpts = {
	needs: string?,
	expect: number?,
	reads: string?,
	sleep: number?,
	hang: boolean?,
	broken: boolean?,
	writes: { path: string, text: string }?,
	opens: boolean?,
	quits: boolean?,
}
local function specText(dir: string, name: string, o: SpecOpts): string
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
	if o.hang then
		-- the process running this spec (the runner, or its worker), so a case can tell whether it outlived its owner
		table.insert(
			lines,
			`\t\tprocess.exec("sh", \{ "-c", 'echo "hangpid $PPID" >> "$1"', "_", "{dir}/ran.log" })`
		)
		table.insert(lines, `\t\tif fs.isFile("{dir}/hang.marker") then process.exec("sleep", \{ "30" }) end`)
	end
	if o.sleep then
		table.insert(lines, `\t\tprocess.exec("sleep", \{ "{o.sleep}" })`)
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

local function stubTools(dir: string)
	fs.writeDir(`{dir}/bin`)
	for _, tool in { "stylua", "selene", "luau-lsp" } do
		write(`{dir}/bin/{tool}`, "#!/bin/sh\nexit 0\n")
	end
	write(
		`{dir}/bin/rojo`,
		'#!/bin/sh\nif [ "$1" = --version ]; then echo "rojo 7.7.0"; exit 0; fi\no=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done\n[ -n "$o" ] && echo built > "$o"\nexit 0\n'
	)
	write(
		`{dir}/bin/curl`,
		'#!/bin/sh\no=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "-- defs" > "$o"\n'
	)
	-- the real lune, with the real HOME: the fixture's HOME keeps rokit's real tools from shadowing the stubs, but a
	-- rokit shim finds its tools through HOME (so does lune's own setup)
	write(`{dir}/bin/lune`, `#!/bin/sh\nHOME="{REAL_HOME}" exec "{REAL_LUNE}" "$@"\n`)
	for _, tool in { "stylua", "selene", "luau-lsp", "rojo", "curl", "lune" } do
		process.exec("chmod", { "+x", `{dir}/bin/{tool}` })
	end
end

-- the fixture repository: the tooling, a pickman home with specs a (needs A), b (needs B), text (reads data/x.txt),
-- slow1/slow2 (sleep), hang (hangs while hang.marker exists) and broken (always fails, only added where asked);
-- committed on main, then checked out on a branch `work`
local function make(name: string, withBroken: boolean?): string
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
	write(
		`{dir}/.gitignore`,
		".cache/\nsourcemap.json\n/.claude/.znile_tests.sqlite*\nran.log\nhang.marker\nbin/\nbin-silent/\nbin-gitfail/\nhome/\nw1.out\n"
	)
	write(`{dir}/pickman/.tracker/.gitkeep`, "")
	write(`{dir}/z-nile/.tracker/.gitkeep`, "")
	write(`{dir}/pickman/tests/run.luau`, `return {R}("../../z-nile/tests/run")\n`)
	write(`{dir}/pickman/tests/inputs.tsv`, "# extra inputs per spec\n")
	write(`{dir}/pickman/src/A.luau`, "return { value = 1 }\n")
	write(`{dir}/pickman/src/B.luau`, "return { value = 1 }\n")
	write(`{dir}/pickman/src/C.luau`, "return { value = 1 }\n")
	write(`{dir}/pickman/data/x.txt`, "ok\n")
	local specs: { [string]: SpecOpts } = {
		a = { needs = "A" },
		b = { needs = "B" },
		text = { reads = "data/x.txt" },
		slow1 = { sleep = 3 },
		slow2 = { sleep = 3 },
		hang = { hang = true },
	}
	if withBroken then
		specs.broken = { broken = true }
	end
	-- only the "changed" fixture: aa_edit dirties the tree mid-run, and cdep passes only on the edited content
	if name == "opener" then
		specs.opener = { opens = true }
	end
	if name == "waitfail" then
		specs.slowfail = { sleep = 3, broken = true }
	end
	if name == "dirty" then
		specs.dirty = { needs = "A", writes = { path = `{dir}/pickman/notes-dirty.txt`, text = "dirty\\n" } }
	end
	if name == "quitter" then
		specs.quitter = { quits = true }
	end
	if name == "trackmiss" then
		specs.trk = { reads = ".tracker/issues/f0009/notes.md" }
		write(`{dir}/pickman/.tracker/issues/f0009/notes.md`, "ok\n")
	end
	if name == "donetree" then
		write(`{dir}/pickman/docs/a.md`, "a\n")
		write(`{dir}/pickman/.tracker/issues/f0009/f0009.md`, "# f0009\n")
	end
	if name == "changed" then
		specs.cdep = { needs = "C", expect = 2 }
		-- aa_edit runs first in path order and rewrites C.luau, an input of cdep, before cdep loads it
		write(
			`{dir}/pickman/tests/unit/aa_edit.spec.luau`,
			specText(
				dir,
				"aa_edit",
				{ writes = { path = `{dir}/pickman/src/C.luau`, text = "return { value = 2 }\\n" } }
			)
		)
	end
	for n, o in specs do
		write(`{dir}/pickman/tests/unit/{n}.spec.luau`, specText(dir, n, o))
	end
	stubTools(dir)
	t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
	fixture.git(dir, { "config", "user.name", "c0165-gate" })
	fixture.git(dir, { "config", "user.email", "c0165-gate@example.invalid" })
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "commit", "-qm", "base" })
	fixture.git(dir, { "checkout", "-q", "-b", "work" })
	return dir
end

local function env(dir: string, extra: { [string]: string }?): { [string]: string }
	local e: { [string]: string } = {
		PATH = `{dir}/bin:{process.env.PATH or ""}`,
		PICKMAN_JOBS = "2",
		HOME = `{dir}/home`,
	}
	for k, v in (extra or {}) :: { [string]: string } do
		e[k] = v
	end
	return e
end
local function specs(dir: string, args: { string }, extra: { [string]: string }?): (boolean, string)
	local argv = { "run", "z-nile/specs", "--", "run", "--project", "pickman" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = dir, env = env(dir, extra) })
	if not r.ok then
		print(`specs {table.concat(args, " ")} failed ({r.code}):\n{r.stdout}{r.stderr}`)
	end
	return r.ok, r.stdout .. r.stderr
end
local function gate(dir: string, args: { string }, extra: { [string]: string }?): (boolean, string)
	local argv = { "z-nile/check.sh", "--project", "pickman" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, { cwd = dir, env = env(dir, extra) })
	if not r.ok then
		print(`gate {table.concat(args, " ")} failed ({r.code}):\n{r.stdout}{r.stderr}`)
	end
	return r.ok, r.stdout .. r.stderr
end
local function ran(dir: string): string
	return if fs.isFile(`{dir}/ran.log`) then fs.readFile(`{dir}/ran.log`) else ""
end
local function clearRan(dir: string)
	if fs.isFile(`{dir}/ran.log`) then
		fs.removeFile(`{dir}/ran.log`)
	end
end

local AB = { "--", "tests/unit/a.spec.luau", "tests/unit/b.spec.luau" }

return t.spec("c0165 reuse through the orchestrator and the gate", function(it)
	it(
		"AC5: a second run on the same content reuses every spec and runs none; an edit reruns only its specs",
		function()
			local dir = make("reuse")
			local ok1, out1 = specs(dir, AB)
			t.expect(ok1).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(1)
			t.expect(has(out1, "2 passed, 0 failed, 2 spec files")).toBe(true)
			t.expect(fs.isFile(`{dir}/.claude/.znile_tests.sqlite`)).toBe(true)
			clearRan(dir)
			local ok2, out2 = specs(dir, AB)
			t.expect(ok2).toBe(true)
			t.expect(ran(dir)).toBe("")
			t.expect(has(out2, "reused tests/unit/a.spec.luau")).toBe(true)
			t.expect(has(out2, "reused tests/unit/b.spec.luau")).toBe(true)
			t.expect(has(out2, "2 passed, 0 failed, 2 spec files")).toBe(true)
			-- an uncommitted edit of A: a reruns, b is reused
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local ok3, _ = specs(dir, AB)
			t.expect(ok3).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(0)
			-- --fresh runs both again
			clearRan(dir)
			local ok4, _ = specs(dir, { "--fresh", table.unpack(AB) })
			t.expect(ok4).toBe(true)
			t.expect(count(ran(dir), "a") + count(ran(dir), "b")).toBe(2)
		end
	)

	it(
		"AC5: through check.sh --affected: the edit's selection runs, and an unchanged second gate is reused whole",
		function()
			local dir = make("affected")
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local ok1, out1 = gate(dir, { "--affected" })
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "GATE PASSED (affected)")).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(0)
			clearRan(dir)
			local ok2, out2 = gate(dir, { "--affected" })
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(true)
			-- the static stages' report is shown from the record (the lint summary zz-execute Phase 4 reads)
			t.expect(has(out2, "== lint (selene)")).toBe(true)
			t.expect(has(out2, "GATE PASSED (affected)")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- --fresh runs the selection again
			local ok3, _ = gate(dir, { "--affected", "--fresh" })
			t.expect(ok3).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
		end
	)

	it(
		"AC5: two concurrent runs in two worktrees run each spec once, and both report every result",
		function()
			local dir = make("concurrent")
			local wt = `{base}/concurrent-wt`
			if fs.isDir(wt) then
				fs.removeDir(wt)
			end
			fixture.git(dir, { "worktree", "add", "-q", "--detach", wt })
			stubTools(wt)
			local args = { "--", "tests/unit/slow1.spec.luau", "tests/unit/slow2.spec.luau" }
			local r = process.exec("bash", {
				"-c",
				'cd "$1" && PATH="$1/bin:$PATH" lune run z-nile/specs -- run --project pickman "${@:3}" > "$1/../c1.out" 2>&1 & '
					.. 'cd "$2" && PATH="$2/bin:$PATH" lune run z-nile/specs -- run --project pickman "${@:3}" > "$1/../c2.out" 2>&1 & '
					.. "wait",
				"_",
				dir,
				wt,
				table.unpack(args),
			})
			t.expect(r.ok).toBe(true)
			local o1, o2 = fs.readFile(`{base}/c1.out`), fs.readFile(`{base}/c2.out`)
			t.expect(count(ran(dir), "slow1")).toBe(1)
			t.expect(count(ran(dir), "slow2")).toBe(1)
			t.expect(has(o1, "2 passed, 0 failed, 2 spec files")).toBe(true)
			t.expect(has(o2, "2 passed, 0 failed, 2 spec files")).toBe(true)
			t.expect(has(o1 .. o2, "waited for pid")).toBe(true)
		end
	)

	it("AC5: a killed owner's spec is taken over by the next run", function()
		local dir = make("killed")
		fs.writeFile(`{dir}/hang.marker`, "")
		-- the first run in its own process group, killed whole once its spec has started
		local r = process.exec("bash", {
			"-c",
			-- `cd; cmd &`, not `cd && cmd &`: the latter backgrounds a subshell, so $! would not be the owner's pid
			'cd "$1"; PATH="$1/bin:$PATH" perl -e \'setpgrp(0,0); exec @ARGV\' lune run z-nile/specs -- run --project pickman -- tests/unit/hang.spec.luau > /dev/null 2>&1 & '
				.. 'pid=$!; for i in $(seq 1 150); do grep -qx hang "$1/ran.log" 2>/dev/null && break; sleep 0.1; done; '
				.. 'kill -9 -- "-$pid"; wait "$pid" 2>/dev/null; exit 0',
			"_",
			dir,
		})
		t.expect(r.ok).toBe(true)
		t.expect(count(ran(dir), "hang")).toBe(1)
		fs.removeFile(`{dir}/hang.marker`)
		local started = os.clock()
		local ok, out = specs(dir, { "--", "tests/unit/hang.spec.luau" })
		t.expect(ok).toBe(true)
		t.expect(count(ran(dir), "hang")).toBe(2)
		t.expect(has(out, "1 passed, 0 failed, 1 spec files")).toBe(true)
		-- taken over at once, not after the wait's timeout
		t.expect(os.clock() - started < 60).toBe(true)
	end)

	it(
		"AC5: a wait on a live owner gives up after PICKMAN_REUSE_WAIT, runs the spec unclaimed and records nothing",
		function()
			local dir = make("timeout")
			fs.writeFile(`{dir}/hang.marker`, "")
			-- the owner: alive and hanging in its spec, in its own process group so the case can stop it whole
			local started = process.exec("bash", {
				"-c",
				-- `cd; cmd &`, not `cd && cmd &`: the latter backgrounds a subshell, so $! would not be the owner's pid
				'cd "$1"; PATH="$1/bin:$PATH" perl -e \'setpgrp(0,0); exec @ARGV\' lune run z-nile/specs -- run --project pickman -- tests/unit/hang.spec.luau > /dev/null 2>&1 < /dev/null & '
					.. 'echo $!; for i in $(seq 1 150); do grep -qx hang "$1/ran.log" 2>/dev/null && exit 0; sleep 0.1; done; exit 1',
				"_",
				dir,
			})
			t.expect(started.ok).toBe(true)
			local owner = (string.gsub(started.stdout, "%s+$", ""))
			fs.removeFile(`{dir}/hang.marker`) -- the waiter's own run of it returns at once
			local ok, out = specs(dir, { "--", "tests/unit/hang.spec.luau" }, { PICKMAN_REUSE_WAIT = "2" })
			local row = process.exec("sqlite3", {
				`{dir}/.claude/.znile_tests.sqlite`,
				"select state || ' ' || owner_pid from specs where spec = 'tests/unit/hang.spec.luau'",
			})
			process.exec("bash", { "-c", 'kill -9 -- "-$1" 2>/dev/null; exit 0', "_", owner })
			t.expect(ok).toBe(true)
			t.expect(count(ran(dir), "hang")).toBe(2)
			-- the pid the waiter gave up on is the owner the db records (not `$!`: a rokit shim runs the real lune as its
			-- child), and the owner's row is still its own: the waiter recorded nothing over it
			local gaveUp = string.match(out, "gave up waiting for pid (%d+)")
			t.expect(gaveUp ~= nil).toBe(true)
			t.expect((string.gsub(row.stdout, "%s+$", ""))).toBe(`running {gaveUp}`)
		end
	)

	it(
		"AC5: a spec whose input changed during the run is not recorded, so the old content runs it again",
		function()
			local dir = make("changed")
			-- one job, path order: aa_edit rewrites C.luau to value 2, then cdep loads C and passes only with value 2
			local ok1, _ = specs(
				dir,
				{ "--", "tests/unit/aa_edit.spec.luau", "tests/unit/cdep.spec.luau" },
				{ PICKMAN_JOBS = "1" }
			)
			t.expect(ok1).toBe(true)
			t.expect(count(ran(dir), "cdep")).toBe(1)
			-- back to the content the run was claimed under: a pass recorded under that fingerprint would be reused here
			write(`{dir}/pickman/src/C.luau`, "return { value = 1 }\n")
			local ok2, _ = specs(dir, { "--", "tests/unit/cdep.spec.luau" }, { PICKMAN_JOBS = "1" })
			t.expect(count(ran(dir), "cdep")).toBe(2)
			t.expect(ok2).toBe(false)
		end
	)

	it("AC5: with reuse off (no sqlite3) every given spec runs and the result is unchanged", function()
		local dir = make("off")
		local miss = { PICKMAN_SQLITE3 = `{dir}/no-such-sqlite3` }
		local ok1, out1 = specs(dir, AB, miss)
		t.expect(ok1).toBe(true)
		t.expect(has(out1, "reuse off:")).toBe(true)
		local ok2, _ = specs(dir, AB, miss)
		t.expect(ok2).toBe(true)
		t.expect(count(ran(dir), "a")).toBe(2)
		t.expect(count(ran(dir), "b")).toBe(2)
		t.expect(fs.isFile(`{dir}/.claude/.znile_tests.sqlite`)).toBe(false)
		-- a failing spec still fails the run with reuse off
		write(`{dir}/pickman/src/A.luau`, "return { value = 2 }\n")
		local ok3, _ = specs(dir, AB, miss)
		t.expect(ok3).toBe(false)
	end)

	it(
		"AC7: --full runs every spec despite recorded passes; --full --reuse needs a full record of the same content",
		function()
			local dir = make("full")
			-- an affected gate passes and records every spec it ran
			local ok0, _ = specs(dir, { "--all" })
			t.expect(ok0).toBe(true)
			local ok0g, _ = gate(dir, { "--affected" })
			t.expect(ok0g).toBe(true)
			-- an affected record never stands in for a full one
			clearRan(dir)
			local ok1, out1 = gate(dir, { "--full", "--reuse" })
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "GATE PASSED (full)")).toBe(true)
			for _, n in { "a", "b", "text", "slow1", "slow2", "hang" } do
				t.expect(count(ran(dir), n)).toBe(1)
			end
			-- plain --full runs everything again, even though every fingerprint passed
			clearRan(dir)
			local ok2, _ = gate(dir, { "--full" })
			t.expect(ok2).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "hang")).toBe(1)
			-- now a full record exists: --full --reuse runs nothing
			clearRan(dir)
			local ok3, out3 = gate(dir, { "--full", "--reuse" })
			t.expect(ok3).toBe(true)
			t.expect(has(out3, "reused: a full gate passed on this content")).toBe(true)
			t.expect(has(out3, "GATE PASSED (full)")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- a gate-check that answers 0 without its `reused` line (a stub, a wrapper) never skips the gate
			write(
				`{dir}/bin-silent/lune`,
				'#!/bin/sh\nif [ "$1" = run ] && [ "$2" = z-nile/specs ] && [ "$4" = gate-check ]; then exit 0; fi\n'
					.. `exec "{dir}/bin/lune" "$@"\n`
			)
			process.exec("chmod", { "+x", `{dir}/bin-silent/lune` })
			local okS, outS = gate(
				dir,
				{ "--full", "--reuse" },
				{ PATH = `{dir}/bin-silent:{dir}/bin:{process.env.PATH or ""}` }
			)
			t.expect(okS).toBe(true)
			t.expect(has(outS, "reused: a full gate passed on this content")).toBe(false)
			t.expect(count(ran(dir), "a")).toBe(1)
			clearRan(dir)
			-- an untracked file changes the content: it runs again
			write(`{dir}/pickman/notes.txt`, "new\n")
			local ok4, _ = gate(dir, { "--full", "--reuse" })
			t.expect(ok4).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			fs.removeFile(`{dir}/pickman/notes.txt`)
			-- committing the same content keeps the record: the digest is content, not a commit
			clearRan(dir)
			fixture.git(dir, { "commit", "-q", "--allow-empty", "-m", "empty" })
			local ok5, out5 = gate(dir, { "--full", "--reuse" })
			t.expect(ok5).toBe(true)
			t.expect(has(out5, "reused: a full gate passed on this content")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- conflicting flags refuse
			local ok6, _ = gate(dir, { "--affected", "--reuse" })
			t.expect(ok6).toBe(false)
			local ok7, _ = gate(dir, { "--full", "--fresh" })
			t.expect(ok7).toBe(false)
		end
	)

	it(
		"AC8: a seeded graph miss: the full gate fails, records and prints the dependency, and affected then selects it",
		function()
			local dir = make("miss", true)
			-- the change: data/x.txt, which text.spec reads as text (no require edge); broken.spec fails on the base too
			write(`{dir}/pickman/data/x.txt`, "bad\n")
			fixture.git(dir, { "commit", "-qam", "change x" })
			local before = process.exec(
				"lune",
				{ "run", "z-nile/affected", "--", "--project", "pickman", "pickman/data/x.txt" },
				{ cwd = dir, env = env(dir) }
			)
			t.expect((string.gsub(before.stdout, "%s+$", ""))).toBe("")
			local ok, out = gate(dir, { "--full" })
			t.expect(ok).toBe(false)
			t.expect(has(out, "graph miss: pickman/tests/unit/text.spec.luau depends on pickman/data/x.txt"))
				.toBe(true)
			t.expect(has(out, "add to pickman/tests/inputs.tsv:")).toBe(true)
			t.expect(has(out, "tests/unit/text.spec.luau\tpickman/data/x.txt")).toBe(true)
			t.expect(has(out, "tests/unit/broken.spec.luau: fails on the base too: not a graph miss"))
				.toBe(true)
			t.expect(has(out, "graph miss: pickman/tests/unit/broken.spec.luau")).toBe(false)
			-- the edge is in the db now: affected selects text.spec for that file, in this worktree and every other
			local after = process.exec(
				"lune",
				{ "run", "z-nile/affected", "--", "--project", "pickman", "--learned", "pickman/data/x.txt" },
				{ cwd = dir, env = env(dir) }
			)
			-- a bare call never reads the db: what reviewers paste and promoted specs run stays the committed answer
			local bare = process.exec(
				"lune",
				{ "run", "z-nile/affected", "--", "--project", "pickman", "pickman/data/x.txt" },
				{ cwd = dir, env = env(dir) }
			)
			t.expect((string.gsub(bare.stdout, "%s+$", ""))).toBe("")
			t.expect((string.gsub(after.stdout, "%s+$", ""))).toBe("tests/unit/text.spec.luau")
			-- the gate wrote no committed file: inputs.tsv is untouched, the tree is as it was
			t.expect(fs.readFile(`{dir}/pickman/tests/inputs.tsv`)).toBe("# extra inputs per spec\n")
			t.expect((string.gsub(fixture.git(dir, { "status", "--porcelain" }), "%s+$", ""))).toBe("")
			-- the learning clone is gone
			for _, name in fs.readDir(`{dir}/.cache`) do
				t.expect(string.sub(name, 1, 6) ~= "learn-").toBe(true)
			end
		end
	)

	it("AC5: a run the runner fails after every spec passed (the browser guard) records no pass", function()
		local dir = make("opener")
		local one = { "--", "tests/unit/opener.spec.luau" }
		local ok1, out1 = specs(dir, one)
		t.expect(ok1).toBe(false)
		t.expect(has(out1, "results not recorded")).toBe(true)
		local ok2, _ = specs(dir, one)
		t.expect(ok2).toBe(false)
		t.expect(count(ran(dir), "opener")).toBe(2)
		local rows = process.exec("sqlite3", {
			`{dir}/.claude/.znile_tests.sqlite`,
			"select count(*) from specs where state = 'passed'",
		})
		t.expect((string.gsub(rows.stdout, "%s+$", ""))).toBe("0")
		-- through the full gate too: red, and no passed row
		local okF, _ = gate(dir, { "--full" })
		t.expect(okF).toBe(false)
		local rowsF = process.exec("sqlite3", {
			`{dir}/.claude/.znile_tests.sqlite`,
			"select count(*) from specs where state = 'passed' and spec = 'tests/unit/opener.spec.luau'",
		})
		t.expect((string.gsub(rowsF.stdout, "%s+$", ""))).toBe("0")
	end)

	it("AC5: a waiter whose owner's spec fails counts the failure, and the spec ran once", function()
		local dir = make("waitfail")
		local wt = `{base}/waitfail-wt`
		if fs.isDir(wt) then
			fs.removeDir(wt)
		end
		fixture.git(dir, { "worktree", "add", "-q", "--detach", wt })
		stubTools(wt)
		local r = process.exec("bash", {
			"-c",
			'(cd "$1"; PATH="$1/bin:$PATH" lune run z-nile/specs -- run --project pickman -- tests/unit/slowfail.spec.luau > "$1/../w1.out" 2>&1; echo "$?" > "$1/../w1.rc") & '
				.. '(cd "$2"; PATH="$2/bin:$PATH" lune run z-nile/specs -- run --project pickman -- tests/unit/slowfail.spec.luau > "$1/../w2.out" 2>&1; echo "$?" > "$1/../w2.rc") & '
				.. "wait",
			"_",
			dir,
			wt,
		})
		t.expect(r.ok).toBe(true)
		t.expect(count(ran(dir), "slowfail")).toBe(1)
		t.expect((string.gsub(fs.readFile(`{base}/w1.rc`), "%s+$", ""))).toBe("1")
		t.expect((string.gsub(fs.readFile(`{base}/w2.rc`), "%s+$", ""))).toBe("1")
		t.expect(has(fs.readFile(`{base}/w1.out`) .. fs.readFile(`{base}/w2.out`), "failed in pid"))
			.toBe(true)
	end)

	it("AC5: a claimed spec with no result (the runner quit early) is released and counted failed", function()
		local dir = make("quitter")
		local ok, out = specs(
			dir,
			{ "--", "tests/unit/a.spec.luau", "tests/unit/quitter.spec.luau" },
			{ PICKMAN_JOBS = "1" }
		)
		t.expect(ok).toBe(false)
		t.expect(has(out, "results file missing")).toBe(true)
		local rows =
			process.exec("sqlite3", { `{dir}/.claude/.znile_tests.sqlite`, "select count(*) from specs" })
		t.expect((string.gsub(rows.stdout, "%s+$", ""))).toBe("0")
	end)

	it(
		"AC5: a killed orchestrator's runner dies with it (the lifeline), and the next run takes the spec over",
		function()
			local dir = make("orphan")
			fs.writeFile(`{dir}/hang.marker`, "")
			local db = `{dir}/.claude/.znile_tests.sqlite`
			-- the owner in its own process group; then only the orchestrator (the pid its db row names) is killed
			local r = process.exec("bash", {
				"-c",
				'cd "$1"; PATH="$1/bin:$PATH" perl -e \'setpgrp(0,0); exec @ARGV\' lune run z-nile/specs -- run --project pickman -- tests/unit/hang.spec.luau > /dev/null 2>&1 < /dev/null & '
					.. 'echo "$!"; for i in $(seq 1 150); do grep -q "^hangpid " "$1/ran.log" 2>/dev/null && break; sleep 0.1; done; '
					.. 'o=$(sqlite3 "$2" "select owner_pid from specs where state = \'running\'"); kill -9 "$o"; exit 0',
				"_",
				dir,
				db,
			})
			t.expect(r.ok).toBe(true)
			local group = (string.gsub(r.stdout, "%s+$", ""))
			local runner = string.match(ran(dir), "hangpid (%d+)") :: string
			fs.removeFile(`{dir}/hang.marker`)
			local ok, out = specs(dir, { "--", "tests/unit/hang.spec.luau" })
			t.expect(ok).toBe(true)
			t.expect(has(out, "1 passed, 0 failed, 1 spec files")).toBe(true)
			t.expect(count(ran(dir), "hang")).toBe(2)
			-- give the lifeline its poll (1 s), TERM and grace (2 s): then the orphaned runner, still in its 30 s sleep, is gone
			process.exec("sleep", { "5" })
			local alive = process.exec("sh", { "-c", 'kill -0 "$1" 2>/dev/null', "_", runner })
			process.exec("bash", { "-c", 'kill -9 -- "-$1" 2>/dev/null; exit 0', "_", group })
			t.expect(alive.ok).toBe(false)
		end
	)

	it(
		"AC5: a failed blob read (hash-object) turns reuse off: every spec runs and nothing is recorded",
		function()
			local dir = make("gitfail")
			local realGit = (string.gsub(process.exec("sh", { "-c", "command -v git" }).stdout, "%s+$", ""))
			write(
				`{dir}/bin-gitfail/git`,
				'#!/bin/sh\nif [ "$1" = hash-object ]; then exit 1; fi\n' .. `exec "{realGit}" "$@"\n`
			)
			process.exec("chmod", { "+x", `{dir}/bin-gitfail/git` })
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local env1 = { PATH = `{dir}/bin-gitfail:{dir}/bin:{process.env.PATH or ""}` }
			local ok1, out1 = specs(dir, AB, env1)
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "reuse off:")).toBe(true)
			local ok2, _ = specs(dir, AB, env1)
			t.expect(ok2).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(2)
			t.expect(count(ran(dir), "b")).toBe(2)
		end
	)

	it("AC7: a gate whose tree changes while it runs records no whole-gate pass, affected or full", function()
		local dir = make("dirty")
		local note = `{dir}/pickman/notes-dirty.txt`
		local function unnote()
			if fs.isFile(note) then
				fs.removeFile(note)
			end
		end
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n") -- selects dirty.spec and a.spec
		-- dirty.spec writes an untracked file while the gate runs: the digest moves, so no gates row
		local ok1, _ = gate(dir, { "--affected" })
		t.expect(ok1).toBe(true)
		t.expect(fs.isFile(note)).toBe(true)
		unnote()
		local ok2, out2 = gate(dir, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(false)
		unnote()
		-- the full gate: record --full finds the digest moved, records no row, and says so
		local okF, outF = gate(dir, { "--full" })
		t.expect(okF).toBe(true)
		t.expect(has(outF, "records nothing")).toBe(true)
		local rows = process.exec("sqlite3", {
			`{dir}/.claude/.znile_tests.sqlite`,
			"select count(*) from specs where spec = 'tests/unit/dirty.spec.luau' and state = 'passed'",
		})
		-- the one affected-mode row from the first gate (dirty.spec's own inputs didn't change); none from the full gate
		t.expect((string.gsub(rows.stdout, "%s+$", ""))).toBe("1")
		unnote()
		local okR, outR = gate(dir, { "--full", "--reuse" })
		t.expect(okR).toBe(true)
		t.expect(has(outR, "reused: a full gate passed on this content")).toBe(false)
	end)

	it(
		"AC7: done's uncommitted tree (staged moves and edits) is reused on the committed head; spend.md may change, nothing else",
		function()
			local dir = make("donetree")
			fixture.git(dir, { "mv", "pickman/docs/a.md", "pickman/docs/b.md" })
			write(`{dir}/pickman/src/B.luau`, "return { value = 1 } -- staged\n")
			fixture.git(dir, { "add", "pickman/src/B.luau" })
			local ok1, _ = gate(dir, { "--full" })
			t.expect(ok1).toBe(true)
			-- what done does after its gate: spend rows, then the commit of everything
			write(`{dir}/pickman/.tracker/issues/f0009/spend.md`, "# spend\n| phase | minutes |\n")
			fixture.git(dir, { "add", "-A" })
			fixture.git(dir, { "commit", "-qm", "done" })
			clearRan(dir)
			local ok2, out2 = gate(dir, { "--full", "--reuse" })
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused: a full gate passed on this content")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- any other tracker document is content: it runs again
			write(`{dir}/pickman/.tracker/issues/f0009/f0009.md`, "# f0009 edited\n")
			fixture.git(dir, { "commit", "-qam", "edit" })
			local ok3, out3 = gate(dir, { "--full", "--reuse" })
			t.expect(ok3).toBe(true)
			t.expect(has(out3, "reused: a full gate passed on this content")).toBe(false)
			t.expect(count(ran(dir), "a")).toBe(1)
		end
	)

	it(
		"AC8: a miss caused by a tracker file is learned too, and affected reads learned rows only when asked",
		function()
			local dir = make("trackmiss")
			write(`{dir}/pickman/.tracker/issues/f0009/notes.md`, "bad\n")
			fixture.git(dir, { "commit", "-qam", "change notes" })
			local ok, out = gate(dir, { "--full" })
			t.expect(ok).toBe(false)
			t.expect(
				has(
					out,
					"graph miss: pickman/tests/unit/trk.spec.luau depends on pickman/.tracker/issues/f0009/notes.md"
				)
			).toBe(true)
			local function affected(args: { string }): string
				local argv = { "run", "z-nile/affected", "--", "--project", "pickman" }
				for _, a in args do
					table.insert(argv, a)
				end
				local r = process.exec("lune", argv, { cwd = dir, env = env(dir) })
				return (string.gsub(r.stdout, "%s+$", ""))
			end
			local file = "pickman/.tracker/issues/f0009/notes.md"
			t.expect(affected({ "--learned", file })).toBe("tests/unit/trk.spec.luau")
			t.expect(affected({ file })).toBe("")
		end
	)
end)
