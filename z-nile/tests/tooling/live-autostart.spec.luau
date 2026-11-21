--!strict
-- f0424 step 2: how `./zn live` finds, builds and starts the daemon. A daemon an op starts outlives the command that started
-- it (even a bounded one) and `./zn reap` never lists it; ten clients at once end with one daemon; and with no binary and
-- no Go every op exits 3 naming SETUP.md. Every daemon lives in the spec's fixture (tests/lib/live.luau).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local live = require("@tests/lib/live")
local process = require("@lune/process")
local reap = require("@znile/engine/reap")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")

local function sleeper(): number
	local r = process.exec("sh", { "-c", "sleep 60 </dev/null >/dev/null 2>&1 & echo $!" })
	return tonumber((string.gsub(r.stdout, "%s+", ""))) :: number
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function alive(pid: number): boolean
	return process.exec("kill", { "-0", tostring(pid) }).ok
end

-- A PATH with no go (or, when `old`, a go that says go1.22), as live-gate.spec does; nil when a system Go in /usr/bin cannot be hidden.
local function withoutGo(l: live.Live, old: boolean): { [string]: string }?
	if not old and process.exec("sh", { "-c", "PATH=/usr/bin:/bin command -v go" }).ok then
		return nil
	end
	local shadow = `{l.base}/shadow`
	fs.writeDir(shadow)
	if old then
		fs.writeFile(`{shadow}/go`, '#!/bin/sh\n[ "$1 $2" = "env GOVERSION" ] && echo go1.22.0\nexit 0\n')
		process.exec("chmod", { "+x", `{shadow}/go` })
	end
	return {
		PATH = `{shadow}:/usr/bin:/bin:/usr/sbin:/sbin`,
		ZN_LIVE_BIN = "",
		ZN_LIVE_ROOT = `{l.base}/norepo`,
	}
end

return t.spec("f0424 ./zn live: auto-start, the reaper, no Go", function(it)
	it(
		"a daemon started inside ./zn run --time 5 outlives it, is no leak, and exits by itself when idle",
		function()
			live.with("f0424-auto-bounded", nil, function(l)
				local pid = sleeper()
				local r = fixture.exec(l.repo, "bash", {
					`{l.root}/zn`,
					"run",
					"--time",
					"5",
					"--",
					"bash",
					`{l.root}/zn`,
					"live",
					"register",
					"--worker",
					"W",
					"--cli",
					"fake",
					"--pid",
					tostring(pid),
					"--idle-exit",
					"1",
					"--tick-every",
					"0.3",
				}, { env = l.env })
				t.expect(r.code).toBe(0)
				-- the bounded command is over (its group is gone); the daemon it started is not
				local daemons = l:pids()
				t.expect(#daemons).toBe(1)
				t.expect(alive(daemons[1])).toBe(true)
				local status = serde.decode("json" :: "json", l:zn({ "status" }).stdout)
				t.expect(status.pid).toBe(daemons[1])
				t.expect(fs.isFile(`{l.state}/daemon.log`)).toBe(true)
				-- it holds nothing of the starter's environment: no runner marker, no session, no TMPDIR (names, never values)
				local names =
					string.match(fs.readFile(`{l.state}/daemon.log`), "environment names %(%d+%): ([^\n]*)")
				t.expect(names ~= nil).toBe(true)
				for name in string.gmatch(names :: string, "[^,]+") do
					local allowed = name == "PATH"
						or name == "HOME"
						or name == "USER"
						or name == "LOGNAME"
						or name == "LANG"
						or string.sub(name, 1, 3) == "LC_"
					if not allowed then
						error(`the daemon holds {name}`, 0)
					end
				end
				-- the reaper's decision for it, with the facts the daemon has (a parent of 1, old, in scope, a passed deadline
				-- even): never a target. `./zn reap --dry-run` cannot run in the jail (ps is closed), so the pure part is
				-- decided here, and the real run is the by-hand proof.
				local command = `{l.bin} serve --dir {l.state} --idle-exit 1`
				local proc: reap.Proc = {
					pid = daemons[1],
					ppid = 1,
					uid = 501,
					age = 7200,
					cpu = 1,
					start = "Sat Nov 21 01:00:00 2026",
					command = command,
					cwd = l.repo,
					deadline = "1000000000",
				}
				local targets = reap.decide({ proc }, {
					uid = 501,
					now = 2000000000,
					minAge = 60,
					grace = 5,
					roots = { l.base },
					scratch = {},
					self = {},
					sessionAnywhere = true,
				})
				t.expect(#targets).toBe(0)
				-- it exits at its idle limit once the worker is gone
				process.exec("kill", { tostring(pid) })
				local exited = false
				for _ = 1, 100 do
					if #l:pids() == 0 then
						exited = true
						break
					end
					task.wait(0.1)
				end
				t.expect(exited).toBe(true)
				t.expect(has(fs.readFile(`{l.state}/daemon.log`), "idle for")).toBe(true)
			end)
		end
	)

	it("ten clients writing at once with no daemon end with one daemon and ten replies", function()
		live.with("f0424-auto-race", nil, function(l)
			local pid = sleeper()
			local jobs: { { string } } = {}
			for i = 1, 10 do
				table.insert(
					jobs,
					{ "register", "--worker", `W{i}`, "--cli", "fake", "--pid", tostring(pid) }
				)
			end
			local results = l:together(jobs)
			for i, r in results do
				if r.code ~= 0 then
					error(`client {i} exited {r.code}: {r.stdout}{r.stderr}`, 0)
				end
			end
			t.expect(#l:pids()).toBe(1)
			local workers = serde.decode("json" :: "json", l:zn({ "workers" }).stdout).workers
			t.expect(#workers).toBe(10)
			local log = fs.readFile(`{l.state}/daemon.log`)
			local _, started = string.gsub(log, "serving", "")
			t.expect(started).toBe(1)
			process.exec("kill", { tostring(pid) })
		end)
	end)

	it("with no binary and no Go every op exits 3 naming SETUP.md, in well under a second", function()
		live.with("f0424-auto-nogo", nil, function(l)
			local env = withoutGo(l, false)
			if not env then
				return -- a system Go lives in /usr/bin: the path alone cannot hide it
			end
			fs.writeDir(`{l.base}/norepo`)
			for _, op in
				{ { "claims" }, { "register", "--cli", "t", "--pid", "5" }, { "status" }, { "poke" } }
			do
				local t0 = os.clock()
				local r = l:znRaw(op, nil, env)
				t.expect(r.code).toBe(3)
				t.expect(r.stdout).toBe("")
				t.expect(has(r.stderr, "SETUP.md")).toBe(true)
				t.expect(os.clock() - t0 < 1).toBe(true)
			end
			t.expect(#l:pids()).toBe(0)
		end)
	end)

	it("an older Go exits 3 naming the version, and a missing ZN_LIVE_BIN exits 3", function()
		live.with("f0424-auto-oldgo", nil, function(l)
			local env = withoutGo(l, true) :: { [string]: string }
			fs.writeDir(`{l.base}/norepo`)
			local r = l:znRaw({ "claims" }, nil, env)
			t.expect(r.code).toBe(3)
			t.expect(has(r.stderr, "Go 1.24 or newer is needed (SETUP.md)")).toBe(true)
			local missing = l:znRaw({ "claims" }, nil, { ZN_LIVE_BIN = `{l.base}/no-such-binary` })
			t.expect(missing.code).toBe(3)
			t.expect(has(missing.stderr, "ZN_LIVE_BIN")).toBe(true)
			local usage = l:znRaw({}, nil)
			t.expect(usage.code).toBe(2)
			t.expect(has(usage.stderr, "usage: ./zn live <op>")).toBe(true)
		end)
	end)

	it("a built binary keeps working when Go is gone and a source is newer", function()
		live.with("f0424-auto-keep", nil, function(l)
			local env = withoutGo(l, false)
			if not env then
				return
			end
			local rootDir = `{l.base}/norepo`
			fs.writeDir(`{rootDir}/.cache/bin`)
			fs.writeDir(`{rootDir}/z-nile/go`)
			process.exec("cp", { l.bin, `{rootDir}/.cache/bin/znlive` })
			fs.writeFile(`{rootDir}/.cache/bin/znlive.id`, "abc\n")
			process.exec("sleep", { "1" })
			fs.writeFile(`{rootDir}/z-nile/go/main.go`, "package main\n") -- newer than the id: a rebuild is tried, and fails
			env.ZN_LIVE_ROOT = rootDir
			env.ZN_LIVE_BIN = ""
			local r = l:znRaw({ "claims" }, nil, env)
			t.expect(r.code).toBe(3)
			t.expect(has(r.stderr, "live daemon not running")).toBe(true) -- znlive itself answered
		end)
	end)

	it("a missing binary is built on the first op, and rebuilt only when a Go source is newer", function()
		live.with("f0424-auto-build", nil, function(l)
			-- a fake go that copies the real binary: the build trigger is what is under test, not the compiler
			local shadow = `{l.base}/shadow`
			local rootDir = `{l.base}/norepo`
			fs.writeDir(shadow)
			fs.writeDir(`{rootDir}/z-nile/go/cmd/znlive`)
			fs.writeFile(`{rootDir}/z-nile/go/go.mod`, "module znile\n")
			fs.writeFile(`{rootDir}/z-nile/go/cmd/znlive/main.go`, "package main\n")
			fs.writeFile(
				`{shadow}/go`,
				'#!/bin/sh\n[ "$1 $2" = "env GOVERSION" ] && { echo go1.24.0; exit 0; }\n'
					.. `echo "$@" >> {l.base}/go.log\n`
					.. 'if [ "$1" = build ]; then while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done; '
					.. `cp {l.bin} "$out"; exit 0; fi\nexit 0\n`
			)
			process.exec("chmod", { "+x", `{shadow}/go` })
			local env = {
				PATH = `{shadow}:/usr/bin:/bin:/usr/sbin:/sbin`,
				ZN_LIVE_BIN = "",
				ZN_LIVE_ROOT = rootDir,
			}
			local function builds(): number
				local log = if fs.isFile(`{l.base}/go.log`) then fs.readFile(`{l.base}/go.log`) else ""
				local _, n = string.gsub(log, "build ", "")
				return n
			end
			local r = l:znRaw({ "claims" }, nil, env) -- a read op: builds, runs, finds no daemon
			t.expect(r.code).toBe(3)
			t.expect(has(r.stderr, "live daemon not running")).toBe(true)
			t.expect(fs.isFile(`{rootDir}/.cache/bin/znlive`)).toBe(true)
			t.expect(fs.isFile(`{rootDir}/.cache/bin/znlive.id`)).toBe(true)
			t.expect(builds()).toBe(1)
			l:znRaw({ "claims" }, nil, env)
			t.expect(builds()).toBe(1) -- unchanged sources: no second build
			process.exec("sleep", { "1" })
			fs.writeFile(`{rootDir}/z-nile/go/cmd/znlive/main.go`, "package main\n// changed\n")
			l:znRaw({ "claims" }, nil, env)
			t.expect(builds()).toBe(2) -- a newer source: one rebuild
			l:znRaw({ "claims" }, nil, env)
			t.expect(builds()).toBe(2)
		end)
	end)

	it(
		"a failed rebuild is tried once per source change, says one line, and keeps the existing binary",
		function()
			live.with("f0424-auto-failed", nil, function(l)
				local shadow = `{l.base}/shadow`
				local rootDir = `{l.base}/norepo`
				fs.writeDir(shadow)
				fs.writeDir(`{rootDir}/z-nile/go/cmd/znlive`)
				fs.writeDir(`{rootDir}/.cache/bin`)
				fs.writeFile(`{rootDir}/z-nile/go/go.mod`, "module znile\n")
				fs.writeFile(`{rootDir}/z-nile/go/cmd/znlive/main.go`, "package main\n")
				process.exec("cp", { l.bin, `{rootDir}/.cache/bin/znlive` })
				fs.writeFile(`{rootDir}/.cache/bin/znlive.id`, "old\n")
				process.exec("sleep", { "1" })
				fs.writeFile(`{rootDir}/z-nile/go/cmd/znlive/main.go`, "package main\nsyntax error here\n")
				fs.writeFile(
					`{shadow}/go`,
					'#!/bin/sh\n[ "$1 $2" = "env GOVERSION" ] && { echo go1.24.0; exit 0; }\n'
						.. `echo "$@" >> {l.base}/go.log\n`
						.. 'if [ "$1" = build ]; then echo "main.go:2:1: syntax error: unexpected syntax" >&2; exit 1; fi\nexit 0\n'
				)
				process.exec("chmod", { "+x", `{shadow}/go` })
				local env = {
					PATH = `{shadow}:/usr/bin:/bin:/usr/sbin:/sbin`,
					ZN_LIVE_BIN = "",
					ZN_LIVE_ROOT = rootDir,
				}
				local function builds(): number
					local log = if fs.isFile(`{l.base}/go.log`) then fs.readFile(`{l.base}/go.log`) else ""
					local _, n = string.gsub(log, "build ", "")
					return n
				end
				local line = "rebuild of znlive failed; using the existing build; ./zn live build shows why"
				for _ = 1, 3 do
					local r = l:znRaw({ "claims" }, nil, env)
					t.expect(r.code).toBe(3) -- the existing znlive answered: no daemon is running
					t.expect(has(r.stderr, "live daemon not running")).toBe(true)
					t.expect(has(r.stderr, line)).toBe(true)
					t.expect(has(r.stderr, "syntax error")).toBe(false) -- never the compiler's output
					local _, lines = string.gsub(r.stderr, "rebuild of znlive failed", "")
					t.expect(lines).toBe(1)
					t.expect(builds()).toBe(1) -- tried once, not on every op
				end
				t.expect(fs.isFile(`{rootDir}/.cache/bin/znlive.failed`)).toBe(true)
				-- `./zn live build` always tries and shows the error
				local forced = l:znRaw({ "build" }, nil, env)
				t.expect(forced.code).toBe(1)
				t.expect(has(forced.stderr, "syntax error")).toBe(true)
				t.expect(builds()).toBe(2)
				-- a changed source is tried again, once
				process.exec("sleep", { "1" })
				fs.writeFile(`{rootDir}/z-nile/go/cmd/znlive/main.go`, "package main\nanother syntax error\n")
				l:znRaw({ "claims" }, nil, env)
				l:znRaw({ "claims" }, nil, env)
				t.expect(builds()).toBe(3)
			end)
		end
	)

	it(
		"out=$(./zn live register ...) returns at once: the daemon holds none of the caller's pipes",
		function()
			live.with("f0424-auto-capture", nil, function(l)
				local pid = sleeper()
				-- the command runs under its own 2 s alarm, its output in files: a daemon that kept the substitution's pipe would
				-- hold `$(...)` open, and the alarm ends the case at once instead of hanging the spec
				local script =
					`out=$(bash "{l.root}/zn" live register --worker W --cli fake --pid {pid} --idle-exit 20); echo "$out"`
				local r = fixture.exec(l.repo, "sh", {
					"-c",
					`perl -e 'alarm 2; exec @ARGV' sh -c '{script}' >"{l.base}/capture.out" 2>"{l.base}/capture.err"`,
				}, { env = l.env })
				local out = if fs.isFile(`{l.base}/capture.out`)
					then fs.readFile(`{l.base}/capture.out`)
					else ""
				t.expect(r.code).toBe(0)
				t.expect(has(out, '"ok":true')).toBe(true)
				t.expect(#l:pids()).toBe(1)
				process.exec("kill", { tostring(pid) })
			end)
		end
	)
end)
