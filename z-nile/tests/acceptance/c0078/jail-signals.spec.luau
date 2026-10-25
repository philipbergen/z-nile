--!strict
-- c0840: the jail refuses signals to anything outside it (the runner's own processes included), while a spec can
-- still signal what it started; the runner's liveness check counts a refused probe as alive; the outer-sandbox
-- link probe has an unpredictable name and counts only "Operation not permitted" as a refusal. Only processes this
-- spec started are signalled; probing the run's top process with kill -0 is harmless.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from its home (z-nile/), whose .cache is the one the jail lets it write
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0078-signals`
local jailed = process.env.PICKMAN_TEST_JAIL == "sandbox-exec"

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- the run's top process: outside the jail, same user, alive for the whole run
local function outsidePid(): string
	local pid = trim(fs.readFile(`{process.env.PICKMAN_TEST_FENCE or ""}/.cache/tests-run.lock/pid`))
	assert(string.match(pid, "^%d+$"), "no top process recorded in the run's lock")
	return pid
end

local function myPid(): string
	return trim(process.exec("sh", { "-c", "echo $PPID" }).stdout)
end

return t.spec("c0840 jail signals and the link probe", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it("when jailed, a spec can neither signal nor probe the run's top process", function()
		if not jailed then
			return -- check.sh requires the jailed run on macOS
		end
		local top = outsidePid()
		local probe = process.exec("kill", { "-0", top })
		t.expect(probe.ok).toBe(false)
		t.expect(has(probe.stderr, "Operation not permitted")).toBe(true)
		-- a signal the top process would ignore anyway, so nothing happens even if the rule were missing
		local urg = process.exec("kill", { "-URG", top })
		t.expect(urg.ok).toBe(false)
		t.expect(has(urg.stderr, "Operation not permitted")).toBe(true)
		fs.writeFile(`{base}/jailed-cases-ran`, "")
	end)

	it(
		"when jailed, a spec can still signal a process it started, even one in a session of its own",
		function()
			local pidfile = `{base}/detached.pid`
			local script = 'exit if fork; setpgrp(0, 0); exit if fork; open STDOUT, ">", "/dev/null"; '
				.. 'open STDERR, ">&STDOUT"; open my $f, ">", $ARGV[0] or die; print $f $$; close $f; '
				.. "select(undef, undef, undef, 30)"
			t.expect(process.exec("perl", { "-e", script, pidfile }).ok).toBe(true)
			process.exec("perl", { "-e", "select(undef, undef, undef, 0.3)" })
			local pid = trim(fs.readFile(pidfile))
			t.expect(process.exec("kill", { "-0", pid }).ok).toBe(true)
			t.expect(process.exec("kill", { "-KILL", pid }).ok).toBe(true)
		end
	)

	it("alive counts a refused probe as alive only when jailed, and a finished process as dead", function()
		t.expect(fence.alive(myPid())).toBe(true)
		if jailed then
			t.expect(fence.alive(outsidePid())).toBe(true) -- refused, but it exists
		end
		local done = trim(process.exec("sh", { "-c", "true & echo $!; wait" }).stdout)
		t.expect(fence.alive(done)).toBe(false)
		t.expect(fence.alive("not-a-pid")).toBe(false)
		-- pid 1 belongs to root: kill -0 is refused it everywhere. Jailed, a refusal means "exists outside"; unjailed
		-- (the lock code in the runner's top process), it means another user's process, which can't hold a lock
		local saved = process.env.PICKMAN_TEST_JAIL
		process.env.PICKMAN_TEST_JAIL = "sandbox-exec"
		local inside = fence.alive("1")
		process.env.PICKMAN_TEST_JAIL = "none (unjailed)"
		local outside = fence.alive("1")
		process.env.PICKMAN_TEST_JAIL = saved
		t.expect(inside).toBe(true)
		t.expect(outside).toBe(false)
		t.expect(fence.alive("")).toBe(false)
	end)

	it("the link probe makes and removes a link where links are allowed", function()
		local dir = `{base}/allowed`
		fs.writeDir(dir)
		local verdict = fence.linkProbe(dir)
		t.expect(verdict).toBe("made")
		t.expect(#fs.readDir(dir)).toBe(0)
	end)

	it("a regular file at the old predictable probe name does not make the probe say refused", function()
		local dir = `{base}/planted`
		fs.writeDir(dir)
		local mine = myPid()
		fs.writeFile(`{dir}/pickman-link-probe-{mine}`, "planted")
		local verdict = fence.linkProbe(dir)
		t.expect(verdict).toBe("made")
		t.expect(fs.readFile(`{dir}/pickman-link-probe-{mine}`)).toBe("planted")
		t.expect(#fs.readDir(dir)).toBe(1)
	end)

	it("a probe that fails for another reason is an error, not a refusal", function()
		local verdict, detail = fence.linkProbe(`{base}/no-such-folder`)
		t.expect(verdict).toBe("error")
		t.expect(#detail > 0).toBe(true)
	end)

	it("when jailed, the link probe at the top of .cache says refused", function()
		if not jailed then
			return
		end
		-- c0120 override: the run's .cache is its home's (z-nile/.cache); the checkout's top has none
		local verdict = fence.linkProbe(`{here}/.cache`)
		t.expect(verdict).toBe("refused")
	end)
end)
