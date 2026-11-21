--!strict
-- d0426: the gate's guard for the kernel zone spec runs leak into. A fake `zprint` first on PATH gives the count.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local home = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local bin = `{home}/.cache/kzone-spec/bin`

-- Runs kzone_guard with a zprint that reports `count` (nil: no zprint line; false: no zprint at all).
local function guard(count: (number | boolean)?, env: { [string]: string }?): (number, string)
	pcall(function()
		fs.removeDir(`{home}/.cache/kzone-spec`)
	end)
	fs.writeDir(bin)
	local path = "/usr/bin:/bin"
	if count ~= false then
		local line = if count == nil
			then "other.zone 1024 0K 0K 0 0 7 0K 0"
			else `data.kalloc.1024 1024 0K 0K 0 0 {count} 0K 0`
		fs.writeFile(
			`{bin}/zprint`,
			`#!/bin/sh\necho "zone name elem cur max cur max cur alloc alloc"\necho "{line}"\n`
		)
		process.exec("chmod", { "+x", `{bin}/zprint` })
		path = `{bin}:{path}`
	end
	local vars: { [string]: string } = { PATH = path, ZN_KZONE_IN_SPEC = "1" }
	local extra: { [string]: string } = env or {}
	for k, v in extra do
		vars[k] = v
	end
	local r = process.exec(
		"/bin/bash",
		{ "-c", `. "{root}/z-nile/lib/kzone.sh"; kzone_guard` },
		{ env = vars }
	)
	return r.code, r.stderr
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("d0426 the gate's kernel zone guard", function(it)
	it("says nothing and passes below the warning level", function()
		local code, err = guard(13203)
		t.expect(code).toBe(0)
		t.expect(err).toBe("")
	end)

	it("warns once, with the count and both levels, at the warning level, and still passes", function()
		local code, err = guard(5000000)
		t.expect(code).toBe(0)
		t.expect(has(err, "a reboot is due")).toBe(true)
		t.expect(has(err, "5000000 elements")).toBe(true)
		t.expect(has(err, "warning level 5000000, refuse level 10000000")).toBe(true)
		t.expect(has(err, "d0426")).toBe(true)
	end)

	it("refuses at the refuse level, saying to reboot", function()
		local code, err = guard(10000000)
		t.expect(code).toBe(1)
		t.expect(has(err, "not started")).toBe(true)
		t.expect(has(err, "reboot")).toBe(true)
		t.expect(has(err, "20764352")).toBe(true)
	end)

	it(
		"takes the levels from ZN_KZONE_WARN and ZN_KZONE_REFUSE, and ignores a level that is not a number",
		function()
			local code, err = guard(500, { ZN_KZONE_WARN = "100", ZN_KZONE_REFUSE = "400" })
			t.expect(code).toBe(1)
			t.expect(has(err, "refuse level 400")).toBe(true)
			local code2, err2 = guard(500, { ZN_KZONE_WARN = "many", ZN_KZONE_REFUSE = "lots" })
			t.expect(code2).toBe(0)
			t.expect(err2).toBe("")
		end
	)

	it("says nothing and passes where the count cannot be read", function()
		local code, err = guard(false) -- no zprint on PATH (another OS)
		t.expect(code).toBe(0)
		t.expect(err).toBe("")
		local code2, err2 = guard(nil) -- zprint prints no such zone
		t.expect(code2).toBe(0)
		t.expect(err2).toBe("")
	end)

	it("is skipped inside a spec run unless the spec opts in", function()
		local code, err = guard(99999999, { PICKMAN_TEST_FENCE = "/somewhere", ZN_KZONE_IN_SPEC = "" })
		t.expect(code).toBe(0)
		t.expect(err).toBe("")
	end)

	it("is run by the gate before anything starts, and not for --plan", function()
		local text = fs.readFile(`{root}/z-nile/check.sh`)
		local at = string.find(text, "kzone_guard || exit 1", 1, true)
		local run = string.find(text, 'bounded.pl" --time 3600', 1, true)
		t.expect(at ~= nil and run ~= nil and (at :: number) < (run :: number)).toBe(true)
		t.expect(has(text, 'if [[ "$mode" != plan ]]; then')).toBe(true)
	end)
end)
