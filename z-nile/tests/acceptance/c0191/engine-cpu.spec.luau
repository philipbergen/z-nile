--!strict
-- c0191 AC5: `./zn` gives its engine a CPU-time limit (ZN_ENGINE_CPU, default 1800 s) that only lowers the caller's, so a
-- loop in engine code ends instead of spinning as long as the session lives. A copy of `zn` in a fixture folder runs a
-- stub engine; nothing here touches the real repository, spins or waits. That a spinning engine is really stopped by
-- the limit is `proof-limits.luau`, which only check.sh runs, before `./zn done`, and `./zn done` never promotes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local dir = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/engine-cpu`

local function fixture(engine: string)
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/z-nile/engine`)
	fs.writeDir(`{dir}/z-nile/lib`)
	fs.writeFile(`{dir}/z-nile/lib/cpu.sh`, fs.readFile(`{root}/z-nile/lib/cpu.sh`))
	fs.writeFile(`{dir}/zn`, fs.readFile(`{root}/zn`))
	process.exec("chmod", { "+x", `{dir}/zn` })
	fs.writeFile(`{dir}/z-nile/engine/main.luau`, engine)
end

-- A stand-in `ulimit` for `zn` (a bash script reads BASH_ENV first): it answers `ulimit -t` with FAKE_LIMIT (default
-- unlimited) and records every value `zn` asks for, so a case sees what `zn` requested, not what a limit this spec
-- already has (every spec runs under the jail's 1200 s) makes of it.
local STAND_IN = 'ulimit() { if [ "$1" = -t ] && [ $# -eq 1 ]; then echo "${FAKE_LIMIT:-unlimited}"; '
	.. 'elif [ "$1" = -t ]; then echo "$2" >> "$FAKE_LOG"; fi; }\n'

local STUB = '--!strict\nprint("engine ran")\n'

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

-- what `zn` asked for, given the limit in force and ZN_ENGINE_CPU
local function asked(engineCpu: string?, limit: string?): string
	fixture(STUB)
	fs.writeFile(`{dir}/fake-ulimit.sh`, STAND_IN)
	local log = `{dir}/asked.log`
	local r = process.exec("sh", { "-c", `exec {dir}/zn` }, {
		cwd = dir,
		env = {
			ZN_ENGINE_CPU = engineCpu or "",
			BASH_ENV = `{dir}/fake-ulimit.sh`,
			FAKE_LOG = log,
			FAKE_LIMIT = limit or "unlimited",
		},
	})
	if string.find(r.stdout, "engine ran", 1, true) == nil then
		error(`the stub engine did not run: {r.stdout}{r.stderr}`, 0)
	end
	return if fs.isFile(log) then (string.gsub(fs.readFile(log), "%s+$", "")) else ""
end

-- prints the limit its own child sees: no stand-in, so a limit set where it does not reach the engine shows here
local REPORT =
	'--!strict\nlocal process = require("@lune/process")\nprint(process.exec("sh", { "-c", "ulimit -t" }).stdout)\n'

return t.spec("zn's engine CPU limit", function(it)
	it(
		"AC5: the limit is in force in the engine's processes (the real thing: 90 is below the jail's)",
		function()
			fixture(REPORT)
			local r = process.exec(
				"sh",
				{ "-c", `exec {dir}/zn` },
				{ cwd = dir, env = { ZN_ENGINE_CPU = "90" } }
			)
			t.expect(string.match(r.stdout, "%d+")).toBe("90")
			fs.removeDir(dir)
		end
	)

	it("AC5: zn asks for 1800 CPU seconds for its engine by default, and ZN_ENGINE_CPU sets it", function()
		t.expect(asked(nil, nil)).toBe("1800")
		t.expect(asked("90", nil)).toBe("90")
		t.expect(asked("abc", nil)).toBe("1800")
	end)

	it("AC5: a limit the caller already has stays when it is lower; a higher one is lowered", function()
		t.expect(asked("500", "100")).toBe("")
		t.expect(asked("500", "500")).toBe("")
		t.expect(asked("500", "5000")).toBe("500")
		t.expect(asked(nil, "unlimited")).toBe("1800")
	end)
end)
