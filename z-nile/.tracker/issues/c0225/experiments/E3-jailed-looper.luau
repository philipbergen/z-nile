--!strict
-- E3 (prep experiment, not a check; copy it to a `.spec.luau` name to run it with tests/run): inside a real jailed spec run, does fence.SWEEPER leave a detached, exec-looping
-- leftover running? PICKMAN_E3_SWEEPS sweeps (default 60), each narrowed to the looper through the seam. Prints the
-- Run (from z-nile/, as a spec under .cache): PICKMAN_E3_SWEEPS=30 lune run tests/run -- <the .spec.luau copy> (the spec runner needs no wrapper; its jail stops the run's processes, and the looper its own 20 s deadline).
-- tally; the looper stops by itself after 20 s and is killed at once when it outlives a sweep.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local home = string.gsub(process.cwd, "/+$", "")
local base = `{home}/.cache/c0225-e3`

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local LOOP = 'use Time::HiRes qw(time); exec $^X, "-e", $ARGV[0], @ARGV if time < $ARGV[1]; exit'
local START = 'perl -e \'exit if fork; setpgrp(0, 0); exit if fork; open my $f, ">", $ARGV[0] or die; print $f "$$\\n"; '
	.. 'close $f; open STDOUT, ">", "/dev/null"; open STDERR, ">&STDOUT"; use Time::HiRes qw(time); '
	.. 'exec $^X, "-e", $ARGV[1], $ARGV[1], time + 20\' "$1" "$2"; sleep "$3"'

return t.spec("E3 sweeper and an exec-looping leftover", function(it)
	it("sweeps", function()
		if process.env.PICKMAN_TEST_JAIL ~= "sandbox-exec" then
			print("E3: not jailed; nothing measured")
			return
		end
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		local outside = trim(fs.readFile(`{process.env.PICKMAN_TEST_FENCE}/.cache/tests-run.lock/pid`))
		local n = tonumber(process.env.PICKMAN_E3_SWEEPS or "") or 60
		local wait = process.env.PICKMAN_E3_WAIT or "0.2"
		local left, said = 0, {} :: { [string]: number }
		for i = 1, n do
			local only = `{base}/only-{i}`
			fs.writeFile(only, "")
			local r = process.exec(
				"perl",
				{ "-e", fence.SWEEPER, outside, "sh", "-c", START, "_", only, LOOP, wait },
				{ env = { PICKMAN_SWEEP_ONLY = only } }
			)
			local msg = trim(r.stderr)
			said[msg] = (said[msg] or 0) + 1
			local pid = trim(fs.readFile(only))
			process.exec("sleep", { "0.1" })
			if string.match(pid, "^%d+$") and process.exec("kill", { "-0", pid }).ok then
				left += 1
				process.exec("kill", { "-KILL", pid })
				print(`E3 sweep {i}: looper {pid} left running; sweeper said: {msg}`)
			end
		end
		for msg, c in said do
			print(`E3 said {c}x: {msg}`)
		end
		print(`E3 left running: {left} of {n} (wait {wait})`)
		t.expect(true).toBe(true)
	end)
end)
