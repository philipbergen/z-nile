--!strict
-- c0225's real run, for check.sh only (AC5 and AC9). Not a spec of the suite: it has no `.spec.luau` name, so nothing
-- runs it where it lies, here or once promoted. check.sh copies it as the one spec of a fixture copy of the runner and
-- runs that runner from outside any jail, so the fixture's run jails itself and its own sweeper runs unseamed, the path
-- every real run takes. It burns a core for at most 20 s, which is why it is not in the suite.
-- 1. It leaves a leftover that re-execs itself without a pause (the captured mid-exec case) in a session of its own,
--    so the launcher's group kill can't reach it and only the run's own sweeper can; check.sh then requires the run's
--    `stopped 1` and the leftover gone.
-- 2. Inside this jailed run it sweeps ten sleepers through the seam, one every five scans: fifty-one scans, ten of
--    them stopping. Only stopping scans count toward the sweep's limit of fifty, so the sweep ends with the command's
--    status; a limit that counted every scan would end it with 71. It takes about 3 s, too long for the suite.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

local home = string.gsub(process.cwd, "/+$", "")

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
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

-- a process that leaves the specs' group and writes its pid to `file`, then runs `body` (Perl)
local function detach(file: string, body: string): string
	process.exec("perl", {
		"-MPOSIX",
		"-e",
		'exit if fork; POSIX::setsid(); exit if fork; open my $f, ">", $ARGV[0] or die; print $f "$$\\n"; close $f; '
			.. 'open STDIN, "<", "/dev/null"; open STDOUT, ">", "/dev/null"; open STDERR, ">&STDOUT"; '
			.. body,
		file,
	})
	local text = waitFor(file, "^%d+\n$", 5)
	assert(text ~= "", `no pid in {file}`)
	return trim(text)
end

return t.spec("c0225 real run", function(it)
	it("leaves a detached leftover that re-execs itself in a loop", function()
		fs.writeDir(`{home}/.cache`)
		detach(
			`{home}/.cache/left.pid`,
			'use Time::HiRes qw(time); my $c = q{use Time::HiRes qw(time); exec $^X, "-e", $ARGV[0], @ARGV if time < $ARGV[1]; exit}; '
				.. 'exec $^X, "-e", $c, $c, time + 20'
		)
	end)

	it("a sweep of fifty-one scans, ten of them stopping, ends with the command's status", function()
		local dir = `{home}/.cache/c0225-cap`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		local pids: { string } = {}
		local entries: { string } = {}
		for i = 1, 10 do
			local pid = detach(`{dir}/s{i}.pid`, "select(undef, undef, undef, 30)")
			table.insert(pids, pid)
			table.insert(entries, `{pid}@{5 * i - 4}`)
		end
		local ok, err = pcall(function()
			fs.writeFile(`{dir}/only`, table.concat(entries, " ") .. "\n")
			-- the run's top process, outside the jail: this home's lock records it
			local outside = trim(fs.readFile(`{home}/.cache/tests-run.lock/pid`))
			local r = process.exec("perl", {
				"-e",
				"alarm 20; exec { $ARGV[0] } @ARGV; exit 127",
				"perl",
				"-e",
				fence.SWEEPER,
				outside,
				"sh",
				"-c",
				"exit 4",
			}, { env = { PICKMAN_SWEEP_ONLY = `{dir}/only` } })
			t.expect(r.code).toBe(4)
			t.expect(
				string.find(r.stderr, "sweeper: stopped 10 process(es) the specs left running", 1, true)
					~= nil
			)
				.toBe(true)
			for _, pid in pids do
				t.expect(waitGone(pid, 2)).toBe(true)
			end
		end)
		for _, pid in pids do
			if alive(pid) then
				process.exec("kill", { "-KILL", pid })
			end
		end
		if not ok then
			error(err, 0)
		end
	end)
end)
