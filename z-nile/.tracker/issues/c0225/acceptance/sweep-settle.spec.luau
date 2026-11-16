--!strict
-- c0225: the jail's sweeper (fence.SWEEPER) ends only after five scans in a row, at least 50 ms apart, found nothing,
-- because one scan can miss a live process of the sandbox (a leftover mid-exec). The test seam's `<pid>@<n>` entry
-- makes a pid a candidate only from the nth scan on, which stands in for the scans that miss it. Inside this spec's own
-- jail every spec worker shares the sandbox, so each sweep is narrowed to the pids a case lists (PICKMAN_SWEEP_ONLY), as
-- c0076's spec does, and only processes this spec started are signalled. Every process here is a sleeper that ends by
-- itself within 30 s, and each case stops what it started on every path. The real (unseamed) sweep of a leftover that
-- re-execs itself is check.sh's real run (AC5), never a spec: it burns a core while it lives.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local home = string.gsub(process.cwd, "/+$", "")
local base = `{home}/.cache/c0225-sweep-settle`
local jailed = process.env.PICKMAN_TEST_JAIL == "sandbox-exec"

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function alive(pid: string): boolean
	return string.match(pid, "^%d+$") ~= nil and process.exec("kill", { "-0", pid }).ok
end

local function waitGone(pid: string, seconds: number): boolean
	local waited = 0
	while alive(pid) do
		if waited >= seconds then
			return false
		end
		waited += task.wait(0.05)
	end
	return true
end

-- waits up to `seconds` for `file` to match `pattern`, and returns its text ("" if it never did)
local function waitFor(file: string, pattern: string, seconds: number): string
	local waited = 0
	while not (fs.isFile(file) and string.match(fs.readFile(file), pattern)) do
		if waited >= seconds then
			return ""
		end
		waited += task.wait(0.02)
	end
	return fs.readFile(file)
end

-- the run's top process: outside the jail, same user, alive for the whole run
local function outsidePid(): string
	local checkout = process.env.PICKMAN_TEST_FENCE or ""
	local pid = trim(fs.readFile(`{checkout}/.cache/tests-run.lock/pid`))
	assert(string.match(pid, "^%d+$"), "no top process recorded in the run's lock")
	return pid
end

-- A leftover: a sleeper in a session of its own whose parent is launchd, as a run's detached leftover is. It lives
-- 30 s at most. Returns its pid once it has written it.
local function leave(name: string): string
	local file = `{base}/{name}.pid`
	if fs.isFile(file) then
		fs.removeFile(file)
	end
	process.exec("perl", {
		"-e",
		'exit if fork; setpgrp(0, 0); exit if fork; open my $f, ">", $ARGV[0] or die; print $f "$$\\n"; close $f; '
			.. 'open STDIN, "<", "/dev/null"; open STDOUT, ">", "/dev/null"; open STDERR, ">&STDOUT"; '
			.. "select(undef, undef, undef, 30)",
		file,
	})
	local text = waitFor(file, "^%d+\n$", 5)
	assert(text ~= "", `the leftover {name} wrote no pid`)
	return trim(text)
end

-- Two sleepers A and B (30 s at most), children of one watcher that appends `<pid> <time>` to a file as each dies,
-- and then exits. Returns the watcher's, A's and B's pids, and the deaths file.
local function watched(name: string): (string, string, string, string)
	local pids = `{base}/{name}.pids`
	local deaths = `{base}/{name}.deaths`
	process.exec("sh", {
		"-c",
		'perl -MTime::HiRes=time -e "$2" "$1.tmp" "$1" "$3" </dev/null >/dev/null 2>&1 &',
		"_",
		pids,
		'my ($tmp, $pids, $deaths) = @ARGV; my @k; for (1, 2) { my $c = fork; die "fork: $!" unless defined $c; '
			.. "if ($c == 0) { select(undef, undef, undef, 30); exit 0 } push @k, $c } "
			.. 'open my $f, ">", $tmp or die; print $f "$$ @k\\n"; close $f; rename $tmp, $pids or die; '
			.. 'for my $c (@k) { waitpid($c, 0); open my $d, ">>", $deaths or die; printf $d "%d %.6f\\n", $c, time; close $d }',
		deaths,
	})
	local text = waitFor(pids, "^%d+ %d+ %d+\n$", 5)
	assert(text ~= "", `the watcher {name} wrote no pids`)
	local w, a, b = string.match(text, "^(%d+) (%d+) (%d+)")
	return w :: string, a :: string, b :: string, deaths
end

-- Runs the sweeper on `sh -c <script>` with the seam `only` (its text), bounded at 20 s (the sweeper ignores INT,
-- TERM and HUP, not ALRM, and a pending alarm outlives the exec).
local seams = 0
local function sweep(only: string, script: string): Result
	seams += 1
	local seam = `{base}/only-{seams}`
	fs.writeFile(seam, only)
	local r = process.exec("perl", {
		"-e",
		"alarm 20; exec { $ARGV[0] } @ARGV; exit 127",
		"perl",
		"-e",
		fence.SWEEPER,
		outsidePid(),
		"sh",
		"-c",
		script,
	}, { env = { PICKMAN_SWEEP_ONLY = seam } })
	fs.removeFile(seam)
	return r
end

-- runs `body` and then stops every pid it started, whatever happened, failing as the body failed
local function stopping(pids: { string }, body: () -> ())
	local ok, err = pcall(function()
		body()
	end)
	for _, pid in pids do
		if alive(pid) then
			process.exec("kill", { "-KILL", pid })
		end
	end
	if not ok then
		error(err, 0)
	end
	fs.writeFile(`{base}/jailed-cases-ran`, "")
end

return t.spec("c0225 the sweep ends only after five empty scans in a row", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it("when jailed, a leftover the first four scans miss is still stopped", function()
		if not jailed then
			return -- needs the jail's signal rule; check.sh requires the jailed run on macOS
		end
		local l = leave("hidden-four")
		stopping({ l }, function()
			local r = sweep(`{l}@5\n`, "exit 3")
			t.expect(waitGone(l, 2)).toBe(true)
			t.expect(r.code).toBe(3)
			t.expect(has(r.stderr, "sweeper: stopped 1 process(es) the specs left running")).toBe(true)
		end)
	end)

	it("when jailed, the sweep ends after five empty scans in a row", function()
		if not jailed then
			return
		end
		local l = leave("hidden-five")
		stopping({ l }, function()
			local r = sweep(`{l}@6\n`, "exit 0")
			t.expect(alive(l)).toBe(true) -- the sixth scan never came
			t.expect(r.code).toBe(0)
			t.expect(has(r.stderr, "stopped")).toBe(false)
		end)
	end)

	it("when jailed, a scan that stops something starts the count of empty scans again", function()
		if not jailed then
			return
		end
		local first = leave("count-first")
		local second = leave("count-second")
		stopping({ first, second }, function()
			-- scan 1 is empty, scan 2 stops the first, scans 3 to 6 are empty, scan 7 finds the second
			local r = sweep(`{first}@2 {second}@7\n`, "exit 0")
			t.expect(waitGone(first, 2)).toBe(true)
			t.expect(waitGone(second, 2)).toBe(true)
			t.expect(r.code).toBe(0)
			t.expect(has(r.stderr, "sweeper: stopped 2 process(es) the specs left running")).toBe(true)
		end)
	end)

	it("when jailed, the empty scans that end a sweep are at least 50 ms apart", function()
		if not jailed then
			return
		end
		local w, a, b, deaths = watched("gap")
		stopping({ a, b, w }, function()
			-- scan 1 stops A, scans 2 to 5 are empty, scan 6 finds B: between the two deaths come the pause after A's
			-- kill, four pauses after empty scans and B's re-probe, 50 ms each (0.3 s); with no pause after an empty
			-- scan only 0.1 s. Both deaths are timed by their parent, inside the loop, not by start-up times.
			local r = sweep(`{a}@1 {b}@6\n`, "exit 0")
			t.expect(r.code).toBe(0)
			t.expect(has(r.stderr, "sweeper: stopped 2 process(es) the specs left running")).toBe(true)
			local text = waitFor(deaths, "^%d+ [%d.]+\n%d+ [%d.]+\n$", 2)
			local at: { [string]: number } = {}
			for pid, time in string.gmatch(text, "(%d+) ([%d.]+)") do
				at[pid] = tonumber(time) :: number
			end
			t.expect(at[a] ~= nil and at[b] ~= nil).toBe(true)
			t.expect(at[b] - at[a] >= 0.2).toBe(true)
		end)
	end)

	it(
		"when jailed, a seam entry that is neither a pid nor a pid@scan is ignored, never a wider sweep",
		function()
			if not jailed then
				return
			end
			local l = leave("malformed")
			stopping({ l }, function()
				-- `0` alone is left out: under a parse that took it, kill 0 would stop this spec's own group
				local r = sweep(`{l}x {l}@ @{l} {l}@2x x{l}@1 {l}@-1 0{l} {l}@0 {l}@01\n`, "exit 0")
				t.expect(alive(l)).toBe(true)
				t.expect(r.code).toBe(0)
				t.expect(has(r.stderr, "stopped")).toBe(false)
			end)
		end
	)

	it("the testing skill and the sweeper's own comment state when the sweep ends", function()
		local top = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
		local skill = fs.readFile(`{top}/z-nile/skills/zz-test/SKILL.md`)
		local bullet = string.match(skill, "\n%s*%- %*%*Sweeper%*%*:[^\n]*") or ""
		for _, phrase in
			{
				"It ends only after five scans in a row, at least 50 ms apart, found nothing",
				"one scan can miss a live process of the sandbox (a leftover mid-exec, c0225)",
				"`<pid>@<n>`",
			}
		do
			if not has(bullet, phrase) then
				error(`the Sweeper bullet does not say: {phrase}`)
			end
		end
		local code = fs.readFile(`{top}/z-nile/tests/lib/fence.luau`)
		local comment = string.gsub(
			string.match(code, "\n(%-%- The jail's root %(c0076%).-)\nfence%.SWEEPER = ") or "",
			"\n%-%- ",
			" "
		)
		for _, phrase in
			{
				"It ends only after five scans in a row, at least 50 ms apart, found nothing",
				"an entry `<pid>@<n>` is a candidate only from the nth scan on",
			}
		do
			if not has(comment, phrase) then
				error(`the comment above fence.SWEEPER does not say: {phrase}`)
			end
		end
	end)
end)
