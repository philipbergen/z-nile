--!strict
-- f0424 liveemit: the tracker's emits are budgeted and off-able. A failed call marks the layer unavailable for the rest of
-- the process (three events cost one attempt), a poke that finds no daemon is not repeated, an emit is not stopped by it,
-- and ZN_LIVE=off makes no call at all. Fake binaries under .cache/f0424-liveemit log every call.
local fs = require("@lune/fs")
local liveemit = require("@znile/engine/liveemit")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local home = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local dir = `{home}/.cache/f0424-liveemit`
local log = `{dir}/calls.log`

local function withEnv(vars: { [string]: string }, body: () -> ())
	local saved: { [string]: string? } = {}
	for k, v in vars do
		saved[k] = process.env[k]
		process.env[k] = v
	end
	liveemit.reset()
	local ok, err = pcall(body :: () -> any)
	for k in vars do
		process.env[k] = saved[k]
	end
	liveemit.reset()
	if not ok then
		error(err, 0)
	end
end

local function fake(name: string, script: string): string
	fs.writeDir(dir)
	local path = `{dir}/{name}`
	fs.writeFile(path, `#!/bin/sh\necho "$*" >> {log}\n{script}\n`)
	process.exec("chmod", { "+x", path })
	return path
end

local function calls(): number
	if not fs.isFile(log) then
		return 0
	end
	local n = 0
	for _ in string.gmatch(fs.readFile(log), "[^\n]+") do
		n += 1
	end
	return n
end

local function clear()
	if fs.isFile(log) then
		fs.removeFile(log)
	end
end

return t.spec("f0424 liveemit: one call per event, one failed attempt per process", function(it)
	it("three emits of an unavailable layer cost one call", function()
		local dead = fake("dead", "exit 3")
		clear()
		withEnv({ ZN_LIVE = "", ZN_LIVE_BIN = dead }, function()
			t.expect(liveemit.emit("a", { unit = "f1" })).toBe(3)
			t.expect(liveemit.emit("b", { unit = "f1" })).toBe(3)
			t.expect(liveemit.emit("c", { unit = "f1" })).toBe(3)
			t.expect(liveemit.poke("x", "y")).toBe(3)
		end)
		t.expect(calls()).toBe(1)
	end)

	it("a working layer gets one call per event", function()
		local ok = fake("ok", 'echo \'{"ok":true,"seq":1}\'')
		clear()
		withEnv({ ZN_LIVE = "", ZN_LIVE_BIN = ok }, function()
			t.expect(liveemit.emit("a", { unit = "f1", round = 2 })).toBe(0)
			t.expect(liveemit.emit("b", {})).toBe(0)
			t.expect(liveemit.poke("subject", "abc")).toBe(0)
		end)
		t.expect(calls()).toBe(3)
	end)

	it("a poke with no daemon is asked once, and an emit still goes through", function()
		local pokeless = fake("pokeless", 'case "$1" in poke) exit 3 ;; esac; echo \'{"ok":true,"seq":1}\'')
		clear()
		withEnv({ ZN_LIVE = "", ZN_LIVE_BIN = pokeless }, function()
			t.expect(liveemit.poke("a", "b")).toBe(3)
			t.expect(liveemit.poke("a", "b")).toBe(3)
			t.expect(liveemit.emit("a", {})).toBe(0)
		end)
		t.expect(calls()).toBe(2)
	end)

	it("ZN_LIVE=off makes no call at all", function()
		local ok = fake("off", "exit 0")
		clear()
		withEnv({ ZN_LIVE = "off", ZN_LIVE_BIN = ok }, function()
			t.expect(liveemit.emit("a", {})).toBe(3)
			t.expect(liveemit.poke("a", "b")).toBe(3)
			t.expect(liveemit.available()).toBe(false)
		end)
		t.expect(calls()).toBe(0)
	end)

	it("a spec run is fenced: the fence turned the live layer off for this process", function()
		t.expect(process.env.ZN_LIVE).toBe("off")
	end)
end)
