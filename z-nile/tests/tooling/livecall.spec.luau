--!strict
-- f0424: livecall, the one Luau caller of the live layer, is non-fatal by contract: whatever the binary does (absent, exits 3,
-- prints junk, dies mid-call, hangs) every function returns a result and never raises, and none waits longer than its
-- timeout. Fake binaries are scripts under .cache; the last case runs the real daemon, in the fixture.
local fs = require("@lune/fs")
local live = require("@tests/lib/live")
local livecall = require("@znile/engine/livecall")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local home = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))

-- Runs `body` with these environment variables set in this process (livecall reads its own), and restores them.
local function withEnv(vars: { [string]: string }, body: () -> ())
	local saved: { [string]: string? } = {}
	-- the fence sets ZN_LIVE=off for every spec; this one tests the layer, so it opts in
	vars = table.clone(vars)
	vars.ZN_LIVE = ""
	for k, v in vars do
		saved[k] = process.env[k]
		process.env[k] = v
	end
	local ok, err = pcall(body :: () -> any)
	for k in vars do
		process.env[k] = saved[k]
	end
	if not ok then
		error(err, 0)
	end
end

-- Kills the process whose pid a fake script wrote to `path` (a child the script left behind), and forgets the file.
local function killPidFile(path: string)
	if fs.isFile(path) then
		local pid = string.match(fs.readFile(path), "%d+")
		if pid then
			process.exec("kill", { pid })
		end
		fs.removeFile(path)
	end
end

local function fake(name: string, script: string): string
	local dir = `{home}/.cache/f0424-livecall`
	fs.writeDir(dir)
	local path = `{dir}/{name}`
	fs.writeFile(path, `#!/bin/sh\n{script}\n`)
	process.exec("chmod", { "+x", path })
	return path
end

return t.spec("f0424 livecall: never raises, never waits long", function(it)
	it("with no binary every function answers unavailable at once", function()
		withEnv({ ZN_LIVE_BIN = `{home}/.cache/f0424-livecall/none`, ZN_LIVE_ROOT = "" }, function()
			local t0 = os.clock()
			local code, reply = livecall.run("claims", {})
			t.expect(code).toBe(3)
			t.expect(reply).toBe(nil)
			t.expect((livecall.emit("review-filed", { unit = "f1" }))).toBe(3)
			t.expect(livecall.poke("a publish", "abc")).toBe(3)
			local snap = livecall.snapshot()
			t.expect(snap.ok).toBe(false)
			t.expect(snap.reason ~= nil).toBe(true)
			t.expect(livecall.binary()).toBe(nil)
			t.expect(os.clock() - t0 < 0.5).toBe(true)
		end)
	end)

	it(
		"a binary that exits 3, prints junk, prints JSON, or dies mid-call gives a result and no error",
		function()
			local exit3 = fake("exit3", "echo unavailable >&2; exit 3")
			withEnv({ ZN_LIVE_BIN = exit3 }, function()
				local code, reply = livecall.run("claims", {})
				t.expect(code).toBe(3)
				t.expect(reply).toBe(nil)
				t.expect((livecall.emit("x", {}))).toBe(3)
			end)
			local junk = fake("junk", "echo 'not json'; exit 0")
			withEnv({ ZN_LIVE_BIN = junk }, function()
				local code, reply = livecall.run("claims", {})
				t.expect(code).toBe(0)
				t.expect(reply).toBe(nil)
			end)
			local good = fake("good", [[echo '{"ok":true,"seq":7,"claims":[]}'; exit 0]])
			withEnv({ ZN_LIVE_BIN = good }, function()
				local code, reply = livecall.run("claims", {})
				t.expect(code).toBe(0)
				t.expect((reply :: any).seq).toBe(7)
			end)
			local dies = fake("dies", [[printf '{"ok":tr'; kill -9 $$]])
			withEnv({ ZN_LIVE_BIN = dies }, function()
				local code, reply = livecall.run("claims", {})
				t.expect(code ~= 0).toBe(true)
				t.expect(reply).toBe(nil)
				t.expect(livecall.snapshot().ok).toBe(false)
			end)
		end
	)

	it("a binary that hangs is killed at the timeout and answers unavailable", function()
		local slow = fake("slow", "exec sleep 20")
		withEnv({ ZN_LIVE_BIN = slow }, function()
			local t0 = os.clock()
			local code, reply = livecall.run("claims", {}, 0.4)
			t.expect(code).toBe(3)
			t.expect(reply).toBe(nil)
			t.expect(os.clock() - t0 < 1.5).toBe(true)
			t0 = os.clock()
			t.expect(livecall.poke("x", "y")).toBe(3) -- the default timeout is the one-shot bound, 2 s
			local took = os.clock() - t0
			t.expect(took >= 1.8 and took < 3.5).toBe(true)
		end)
	end)

	it("emit and poke pass sorted flags and leave empty fields out", function()
		local log = `{home}/.cache/f0424-livecall/args.log`
		local rec = fake("record", `echo "$@" >> {log}; exit 0`)
		if fs.isFile(log) then
			fs.removeFile(log)
		end
		withEnv({ ZN_LIVE_BIN = rec }, function()
			local code =
				livecall.emit("review-filed", { unit = "f1", round = 2, raft = "", activity = "review" })
			t.expect(code).toBe(0)
			t.expect(livecall.poke("a commit subject", "abc123")).toBe(0)
			t.expect(livecall.poke(nil, nil)).toBe(0)
		end)
		t.expect(fs.readFile(log)).toBe(
			"emit review-filed --activity review --round 2 --unit f1\n"
				.. "poke --reason a commit subject --ref abc123\n"
				.. "poke\n"
		)
	end)

	it(
		"with the real daemon: run, snapshot and poke answer, and the binary is found by ZN_LIVE_BIN",
		function()
			live.with("f0424-livecall-real", nil, function(l)
				local sleeper = process.exec("sh", { "-c", "sleep 60 </dev/null >/dev/null 2>&1 & echo $!" })
				local pid = (string.gsub(sleeper.stdout, "%s+", ""))
				withEnv({ ZN_LIVE_BIN = l.bin, ZN_LIVE_DIR = l.state, ZN_LIVE_ROOT = "" }, function()
					t.expect(livecall.binary()).toBe(l.bin)
					local flags = { "--idle-exit", "20", "--tick-every", "0.3" }
					local code, reply = livecall.run(
						"register",
						{ "--worker", "W", "--cli", "fake", "--pid", pid, table.unpack(flags) }
					)
					t.expect(code).toBe(0)
					t.expect((reply :: any).worker).toBe("W")
					local snap = livecall.snapshot()
					t.expect(snap.ok).toBe(true)
					t.expect(#(snap.workers :: { any })).toBe(1)
					t.expect(#(snap.claims :: { any })).toBe(0)
					t.expect(snap.at ~= nil).toBe(true)
					t.expect(livecall.poke("a publish", "abc")).toBe(0)
					t.expect((livecall.emit("review-filed", { unit = "f1", worker = "W" }))).toBe(0)
					local _, events = livecall.run("status", {})
					t.expect((events :: any).seq >= 3).toBe(true)
				end)
				process.exec("kill", { pid })
			end)
		end
	)

	it(
		"an exit code nobody defined is answered as unavailable, and a descendant holding stdout cannot block",
		function()
			local nine = fake("nine", "exit 9")
			withEnv({ ZN_LIVE_BIN = nine }, function()
				local code = livecall.run("claims", {})
				t.expect(code).toBe(3)
			end)
			-- the binary leaves a child that keeps its stdout open for a minute: the call still returns at once
			local holdPid = `{home}/.cache/f0424-livecall/holder.pid`
			local holder =
				fake("holder", `sleep 60 & echo $! > {holdPid}; ` .. [[echo '{"ok":true,"seq":9}'; exit 0]])
			withEnv({ ZN_LIVE_BIN = holder }, function()
				local t0 = os.clock()
				local code, reply = livecall.run("claims", {})
				t.expect(code).toBe(0)
				t.expect((reply :: any).seq).toBe(9)
				t.expect(os.clock() - t0 < 1.5).toBe(true)
			end)
			killPidFile(holdPid)
			-- and one that hangs while a child holds the output: killed at the timeout, not at the child's end
			local hangPid = `{home}/.cache/f0424-livecall/hang.pid`
			local hang = fake("hang", `sleep 60 & echo $! > {hangPid}; exec sleep 30`)
			withEnv({ ZN_LIVE_BIN = hang }, function()
				local t0 = os.clock()
				local code = livecall.run("claims", {}, 0.4)
				t.expect(code).toBe(3)
				t.expect(os.clock() - t0 < 1.5).toBe(true)
			end)
			killPidFile(hangPid)
		end
	)

	it("a binary that cannot be started, or is a folder, still gives a result", function()
		local plain = fake("plain", "exit 0")
		process.exec("chmod", { "-x", plain })
		withEnv({ ZN_LIVE_BIN = plain }, function()
			t.expect((livecall.run("claims", {}))).toBe(3)
			t.expect(livecall.poke("x", "y")).toBe(3)
			t.expect(livecall.snapshot().ok).toBe(false)
		end)
		local dir = `{home}/.cache/f0424-livecall/adir`
		fs.writeDir(dir)
		withEnv({ ZN_LIVE_BIN = dir }, function()
			t.expect((livecall.run("claims", {}))).toBe(3)
			t.expect((livecall.emit("x", {}))).toBe(3)
		end)
	end)

	it("emit rounds numbers to integers and ignores a field that is not an event field, saying so", function()
		local log = `{home}/.cache/f0424-livecall/args2.log`
		local rec = fake("record2", `echo "$@" >> {log}; exit 0`)
		if fs.isFile(log) then
			fs.removeFile(log)
		end
		withEnv({ ZN_LIVE_BIN = rec }, function()
			local code, ignored = livecall.emit(
				"spent",
				{ unit = "f1", seconds = 1.5, tokens = 1200.4, bogus = "x", ["--dir"] = "/" }
			)
			t.expect(code).toBe(0)
			t.expect(table.concat(ignored, ",")).toBe("--dir,bogus")
		end)
		t.expect(fs.readFile(log)).toBe("emit spent --seconds 2 --tokens 1200 --unit f1\n")
	end)
end)
