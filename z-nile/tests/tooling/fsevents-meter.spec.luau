--!strict
-- c0179 slice 1: scripts/fsevents-meter's argument handling, refusals, missing-compiler path, output format and bounds,
-- all against a stub helper and stub ps/pgrep in the fixture folder, so no case depends on what FSEvents delivers. The one
-- real-FSEvents proof is a check.sh-only line (zz-test: real-work proofs are never promoted).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local FIX = ".cache/fsevents-meter-spec"
local METER = "scripts/fsevents-meter"

local function put(path: string, body: string)
	fs.writeFile(path, body)
	process.exec("chmod", { "+x", path })
end

local function setup(): string
	if fs.isDir(FIX) then
		fs.removeDir(FIX)
	end
	fs.writeDir(`{FIX}/stubs`)
	fs.writeDir(`{FIX}/cache`)
	fs.writeDir(`{FIX}/root-a`)
	fs.writeDir(`{FIX}/root-b`)
	-- a helper that writes the ready file, then reports 7 events per root when stopped
	put(
		`{FIX}/helper`,
		[[#!/usr/bin/env bash
ready="$1"; shift
roots=("$@")
trap 'for r in "${roots[@]}"; do printf "7\t%s\n" "$r"; done; exit 0' TERM
: > "$ready"
while :; do sleep 0.05; done
]]
	)
	put(`{FIX}/stubs/pgrep`, "#!/bin/sh\necho 4242\n")
	-- cumulative CPU: 1.50, 3.50 (the run took 2.00), 4.00, 4.25 (idle 0.25), the last in the H:MM:SS form
	put(
		`{FIX}/stubs/ps`,
		[[#!/bin/sh
d="$(dirname "$0")"
n=$(cat "$d/n" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$d/n"
case $n in 1) echo " 0:01.50";; 2) echo " 0:03.50";; 3) echo " 0:04.00";; *) echo " 0:00:04.25";; esac
]]
	)
	return FIX
end

type R = { ok: boolean, code: number, stdout: string, stderr: string }
local function meter(args: { string }, env: { [string]: string }?): R
	local e: { [string]: string } = {
		FSEVENTS_METER_UNAME = "Darwin",
		FSEVENTS_METER_HELPER = `{process.cwd}{FIX}/helper`,
		PATH = `{process.cwd}{FIX}/stubs:{process.env.PATH}`,
	}
	local extra: { [string]: string } = env or {}
	for k, v in extra do
		e[k] = v
	end
	return process.exec("bash", { METER, table.unpack(args) }, { env = e })
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("fsevents-meter", function(it)
	it(
		"reports one events line per root, the CPU-seconds of the run and the idle window, the wall time and the status",
		function()
			setup()
			local r = meter({ "--root", `{FIX}/root-a`, "--root", `{FIX}/root-b`, "--", "sleep", "0.3" })
			t.expect(r.code).toBe(0)
			local lines = string.split((string.gsub(r.stdout, "\n$", "")), "\n")
			t.expect(lines[1]).toBe(`events\t7\t{FIX}/root-a`)
			t.expect(lines[2]).toBe(`events\t7\t{FIX}/root-b`)
			t.expect(lines[3]).toBe("fseventsd-cpu-seconds\trun\t2.00")
			t.expect(lines[4]).toBe("fseventsd-cpu-seconds\tidle\t0.25")
			t.expect(string.match(lines[5] :: string, "^wall%-seconds\trun\t%d+%.%d+$") ~= nil).toBe(true)
			t.expect(lines[6]).toBe("status\t0")
			t.expect(#lines).toBe(6)
		end
	)

	it("--no-idle leaves the idle line out, and the command's own failure status is the meter's", function()
		setup()
		local r = meter({ "--no-idle", "--root", `{FIX}/root-a`, "--", "bash", "-c", "exit 3" })
		t.expect(r.code).toBe(3)
		t.expect(has(r.stdout, "idle")).toBe(false)
		t.expect(has(r.stdout, "status\t3")).toBe(true)
	end)

	it("refuses missing arguments with the usage line and 64", function()
		setup()
		t.expect(meter({ "--", "true" }).code).toBe(64)
		t.expect(meter({ "--root", FIX }).code).toBe(64)
		t.expect(meter({ "--root", FIX, "--" }).code).toBe(64)
		t.expect(meter({ "--bogus" }).code).toBe(64)
		t.expect(meter({ "--limit", "x", "--root", FIX, "--", "true" }).code).toBe(64)
		t.expect(meter({ "--limit", "0", "--root", FIX, "--", "true" }).code).toBe(64)
		local r = meter({ "--root" })
		t.expect(has(r.stderr, "usage: fsevents-meter")).toBe(true)
	end)

	it("refuses a root that does not exist, names it, and does not run the command", function()
		setup()
		local r = meter({ "--root", `{FIX}/root-a`, "--root", `{FIX}/nope`, "--", "touch", `{FIX}/ran` })
		t.expect(r.code).toBe(65)
		t.expect(has(r.stderr, `{FIX}/nope`)).toBe(true)
		t.expect(fs.isFile(`{FIX}/ran`)).toBe(false)
	end)

	it(
		"without swiftc and without a built helper it says so in one line and exits 66, writing nothing",
		function()
			setup()
			local r = meter({ "--root", `{FIX}/root-a`, "--", "true" }, {
				FSEVENTS_METER_HELPER = "",
				FSEVENTS_METER_SWIFTC = "no-such-swiftc-here",
				FSEVENTS_METER_CACHE = `{process.cwd}{FIX}/cache`,
			})
			t.expect(r.code).toBe(66)
			t.expect(#string.split((string.gsub(r.stderr, "\n$", "")), "\n")).toBe(1)
			t.expect(has(r.stderr, "swiftc is missing")).toBe(true)
			t.expect(#fs.readDir(`{FIX}/cache`)).toBe(0)
		end
	)

	it("off macOS it prints the not-available line, exits 0 and does not run the command", function()
		setup()
		local r = meter(
			{ "--root", `{FIX}/root-a`, "--", "touch", `{FIX}/ran` },
			{ FSEVENTS_METER_UNAME = "Linux" }
		)
		t.expect(r.code).toBe(0)
		t.expect(has(r.stderr, "meter: not available on this host")).toBe(true)
		t.expect(fs.isFile(`{FIX}/ran`)).toBe(false)
	end)

	it("stops a command at the limit with status 124 and leaves no process of its own behind", function()
		setup()
		local r = meter({
			"--limit",
			"1",
			"--no-idle",
			"--root",
			`{FIX}/root-a`,
			"--",
			"bash",
			"-c",
			`sleep 30 & echo $! > {FIX}/pid; wait`,
		})
		t.expect(r.code).toBe(124)
		t.expect(has(r.stdout, "status\t124")).toBe(true)
		local pid = string.gsub(fs.readFile(`{FIX}/pid`), "%s+", "")
		t.expect(process.exec("kill", { "-0", pid }).ok).toBe(false)
	end)

	it("stops its helper when the command ends", function()
		setup()
		meter({ "--no-idle", "--root", `{FIX}/root-a`, "--", "true" })
		local ps = process.exec("pgrep", { "-f", `{FIX}/helper` })
		t.expect(ps.ok).toBe(false)
	end)
end)
