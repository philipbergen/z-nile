--!strict
-- c0191 AC2: the two hook scripts. Copies of them run in a fixture folder against stand-ins for what they start: a `zn`
-- that records its arguments and answers only the call the Design names, and a hook entry. Nothing here spins, waits or
-- touches the real repository or runs the real reaper.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local dir = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/hooks-c0191`

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function fixture(status: number?)
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/scripts/hooks`)
	fs.writeDir(`{dir}/z-nile/lib`)
	fs.writeFile(`{dir}/z-nile/lib/cpu.sh`, fs.readFile(`{root}/z-nile/lib/cpu.sh`))
	for _, name in { "pre-bash.sh", "session-end.sh" } do
		fs.writeFile(`{dir}/scripts/hooks/{name}`, fs.readFile(`{root}/scripts/hooks/{name}`))
		process.exec("chmod", { "+x", `{dir}/scripts/hooks/{name}` })
	end
	-- the stand-in zn: records every call, and succeeds only for the one call session-end.sh is meant to make
	fs.writeFile(
		`{dir}/zn`,
		'#!/bin/sh\nprintf "%s\\n" "$*" >> "$(dirname "$0")/argv.log"\n'
			.. '[ "$1" = reap ] && [ "$2" = --session-end ] && [ "$3" = --min-age ] && [ "$4" = 60 ] && [ "$5" = --log ] && exit 3\n'
			.. "exit 64\n"
	)
	process.exec("chmod", { "+x", `{dir}/zn` })
	-- the stand-in hook entry: ends at once with `status` (default: prints and ends 0)
	fs.writeFile(
		`{dir}/z-nile/guard-bash.luau`,
		if status
			then `--!strict\nrequire("@lune/process").exit({status})\n`
			else '--!strict\nprint("entry ran")\n'
	)
end

local function hook(name: string, payload: string, env: { [string]: string }?): Result
	return process.exec("bash", { `{dir}/scripts/hooks/{name}` }, {
		cwd = "/",
		env = env,
		stdio = { stdin = payload },
	})
end

local function argv(): string
	local path = `{dir}/argv.log`
	return if fs.isFile(path) then fs.readFile(path) else ""
end

return t.spec("the hook scripts", function(it)
	it(
		"AC2: session-end.sh asks for a session-end reap with a log, and ends 0 whatever the reaper says",
		function()
			local want = `reap --session-end --min-age 60 --log {dir}/state/z-nile/reaped.log\n`
			for _, payload in
				{
					'{"reason":"prompt_input_exit"}',
					'{"hook_event_name":"SessionEnd","session_id":"abc","reason":"clear"}',
					'{"reason":"logout"}',
					'{"reason":"other"}',
					"",
					"garbage",
				}
			do
				fixture()
				local r = hook("session-end.sh", payload, { XDG_STATE_HOME = `{dir}/state` })
				if r.code ~= 0 then
					error(`payload {payload}: expected exit 0, got {r.code}: {r.stderr}`, 0)
				end
				if argv() ~= want then
					error(`payload {payload}: the stand-in zn saw "{argv()}", expected "{want}"`, 0)
				end
				t.expect(fs.isDir(`{dir}/state/z-nile`)).toBe(true)
			end
		end
	)

	it("AC2: session-end.sh does nothing when the session goes on (reason resume)", function()
		fixture()
		local r = hook("session-end.sh", '{"reason":"resume"}', { XDG_STATE_HOME = `{dir}/state` })
		t.expect(r.code).toBe(0)
		t.expect(argv()).toBe("")
		t.expect(fs.isDir(`{dir}/state`)).toBe(false)
	end)

	it("AC2: session-end.sh runs the reaper with at most 15 seconds of CPU", function()
		fixture()
		fs.writeFile(`{dir}/zn`, '#!/bin/sh\nulimit -t > "$(dirname "$0")/limit.txt"\nexit 0\n')
		hook("session-end.sh", '{"reason":"other"}', { XDG_STATE_HOME = `{dir}/state` })
		t.expect(fs.readFile(`{dir}/limit.txt`)).toBe("15\n")
	end)

	it(
		"AC2: pre-bash.sh runs the entry from its own checkout, with 2 seconds of CPU, and names the checkout",
		function()
			fixture()
			fs.writeFile(
				`{dir}/z-nile/guard-bash.luau`,
				'--!strict\nlocal process = require("@lune/process")\n'
					.. 'print(process.exec("sh", { "-c", "ulimit -t" }).stdout .. (process.env.ZN_CHECKOUT or "none"))\n'
			)
			local r = hook("pre-bash.sh", "{}", {})
			t.expect(r.code).toBe(0)
			t.expect(r.stdout).toBe(`2\n{dir}\n`)
		end
	)

	it(
		"AC2: an entry that the CPU limit stopped (status 1 or 152) does not refuse the call: only status 2 does",
		function()
			for _, status in { 1, 152 } do
				fixture(status)
				local r = hook("pre-bash.sh", "{}", {})
				-- the hook ends with the entry's status, which is neither 0 (a pass) nor the refusal's 2: the harness
				-- takes any other status as a non-blocking error and runs the call
				t.expect(r.code).toBe(status)
			end
			fixture(2)
			t.expect(hook("pre-bash.sh", "{}", {}).code).toBe(2)
			fs.removeDir(dir)
		end
	)
end)
