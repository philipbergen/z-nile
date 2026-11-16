--!strict
-- c0075 AC4: scripts/linux-jail.sh, run whole against recording stubs. It installs bubblewrap when it is missing,
-- proves a jail can start, and only with --apply-sysctl switches off Ubuntu's user-namespace restriction. Nothing real
-- runs: PATH holds one stub, linked as uname, id, sudo, apt-get, sysctl and (when the case has it) bwrap; the script is
-- run with an absolute bash, so a tool it called that is not stubbed would simply be missing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0075-linux-jail`
local STUB = `{base}/stub`
local LOG = `{base}/calls.log`
local STATE = `{base}/sysctl-ran`
local TRIAL_PATTERN = "^bwrap %-%-ro%-bind / / %-%-tmpfs /run %-%-tmpfs /tmp %-%-bind (%S+) %1 "
	.. "%-%-bind (%S+) %2 %-%-remount%-ro /run %-%-dev /dev %-%-proc /proc %-%-unshare%-pid %-%-unshare%-net %-%-unshare%-ipc "
	.. "%-%-new%-session %-%-die%-with%-parent /bin/sh %-c :$"
local TRIAL = "TRIAL" -- what a trial line is called in the comparisons below
local DENIED = "bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted"

local STUB_TEXT = [[#!/bin/sh
name=${0##*/}
case "$name" in mkdir | rmdir) exec /bin/"$name" "$@" ;; esac
echo "$name $*" >> "$STUB_LOG"
case "$name" in
  uname) echo "$STUB_OS" ;;
  id) echo "$STUB_UID" ;;
  sudo) exec "$@" ;;
  apt-get)
    case "$1" in
      update) : > "$STUB_BIN/.updated" ;;
      install) if [ "$STUB_APT" = stale ] && [ ! -e "$STUB_BIN/.updated" ]; then exit 100; fi
        /bin/ln -s "$STUB" "$STUB_BIN/bwrap" ;;
    esac ;;
  sysctl) : > "$STUB_STATE" ;;
  bwrap)
    case "$STUB_TRIAL" in
      ok) exit 0 ;;
      fail) echo "bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted" >&2; exit 1 ;;
      other) echo "bwrap: execvp true: No such file or directory" >&2; exit 1 ;;
      after-sysctl) if [ -e "$STUB_STATE" ]; then exit 0; fi
        echo "bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted" >&2; exit 1 ;;
    esac ;;
esac
]]

local runs = 0
if fs.isDir(base) then
	fs.removeDir(base) -- bin folders a former run filled (apt-get links bwrap into its own)
end

-- One run of the script. `tools` are the names linked to the stub for it; `apt` false leaves apt-get out.
local function run(
	args: { string },
	trial: string,
	tools: { string },
	extra: { [string]: string }?
): (Result, string)
	runs += 1
	local bin = `{base}/bin-{runs}`
	fs.writeDir(bin)
	for _, name in tools do
		process.exec("ln", { "-s", STUB, `{bin}/{name}` })
	end
	if fs.isFile(LOG) then
		fs.removeFile(LOG)
	end
	if fs.isFile(STATE) then
		fs.removeFile(STATE)
	end
	local env: { [string]: string } = {
		PATH = bin,
		STUB = STUB,
		STUB_BIN = bin,
		STUB_LOG = LOG,
		STUB_STATE = STATE,
		STUB_OS = "Linux",
		STUB_UID = "1000",
		STUB_TRIAL = trial,
		TMPDIR = base,
	}
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	local argv = { "scripts/linux-jail.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("/bin/bash", argv, { cwd = root, env = env })
	return r, if fs.isFile(LOG) then fs.readFile(LOG) else ""
end

-- the log's lines, the runner's trial (this exact jail around two folders of the script's own) called TRIAL
local function lines(log: string): { string }
	local out: { string } = {}
	for line in string.gmatch(log, "[^\n]+") do
		table.insert(out, if string.match(line, TRIAL_PATTERN) then TRIAL else line)
	end
	return out
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local ALL = { "uname", "id", "sudo", "apt-get", "sysctl", "bwrap" }
local NO_BWRAP = { "uname", "id", "sudo", "apt-get", "sysctl" }

return t.spec("c0075 scripts/linux-jail.sh", function(it)
	it("does nothing off Linux", function()
		fs.writeDir(base)
		fs.writeFile(STUB, (string.gsub(STUB_TEXT, "\r", "")))
		process.exec("chmod", { "+x", STUB })
		local r, log = run({}, "ok", ALL, { STUB_OS = "Darwin" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "not Linux")).toBe(true)
		t.expect(lines(log)).toEqual({ "uname -s" })
	end)

	it("changes nothing when bubblewrap is there and a jail starts", function()
		local r, log = run({}, "ok", ALL)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "bubblewrap works")).toBe(true)
		t.expect(lines(log)).toEqual({ "uname -s", "id -u", TRIAL })
	end)

	it("installs bubblewrap through sudo apt-get when it is missing", function()
		local r, log = run({}, "ok", NO_BWRAP)
		t.expect(r.ok).toBe(true)
		t.expect(lines(log)).toEqual({
			"uname -s",
			"id -u",
			"sudo apt-get install -y bubblewrap",
			"apt-get install -y bubblewrap",
			TRIAL,
		})
	end)

	it("updates the package index once and tries again when the first install fails", function()
		local r, log = run({}, "ok", NO_BWRAP, { STUB_APT = "stale" })
		t.expect(r.ok).toBe(true)
		t.expect(lines(log)).toEqual({
			"uname -s",
			"id -u",
			"sudo apt-get install -y bubblewrap",
			"apt-get install -y bubblewrap",
			"sudo apt-get update",
			"apt-get update",
			"sudo apt-get install -y bubblewrap",
			"apt-get install -y bubblewrap",
			TRIAL,
		})
	end)

	it("installs without sudo as root", function()
		local r, log = run({}, "ok", NO_BWRAP, { STUB_UID = "0" })
		t.expect(r.ok).toBe(true)
		t.expect(lines(log)).toEqual({ "uname -s", "id -u", "apt-get install -y bubblewrap", TRIAL })
	end)

	it("fails, naming the way out, when bubblewrap is missing and there is no apt-get", function()
		local r, log = run({}, "ok", { "uname", "id", "sudo" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "no apt-get")).toBe(true)
		t.expect(lines(log)).toEqual({ "uname -s", "id -u" })
	end)

	it(
		"fails without touching the system when the jail cannot start and --apply-sysctl was not given",
		function()
			local r, log = run({}, "fail", ALL)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, DENIED)).toBe(true)
			t.expect(has(r.stderr, "kernel.apparmor_restrict_unprivileged_userns")).toBe(true)
			t.expect(has(r.stderr, "--apply-sysctl")).toBe(true)
			t.expect(lines(log)).toEqual({ "uname -s", "id -u", TRIAL })
		end
	)

	it("switches the restriction off with --apply-sysctl, then proves the jail starts", function()
		local r, log = run({ "--apply-sysctl" }, "after-sysctl", ALL)
		t.expect(r.ok).toBe(true)
		t.expect(lines(log)).toEqual({
			"uname -s",
			"id -u",
			TRIAL,
			"sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0",
			"sysctl -w kernel.apparmor_restrict_unprivileged_userns=0",
			TRIAL,
		})
	end)

	it(
		"neither advises nor applies the sysctl for a failure that is not the user-namespace restriction",
		function()
			for _, args in { {}, { "--apply-sysctl" } } do
				local r, log = run(args, "other", ALL)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "execvp true: No such file or directory")).toBe(true)
				t.expect(has(r.stderr, "kernel.apparmor_restrict_unprivileged_userns")).toBe(false)
				t.expect(has(log, "sysctl")).toBe(false)
			end
		end
	)

	it("fails when the jail still cannot start after the sysctl", function()
		local r = run({ "--apply-sysctl" }, "fail", ALL)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "still cannot start a jail")).toBe(true)
	end)

	it("leaves the sysctl alone when the first trial already works, flag or not", function()
		local _, log = run({ "--apply-sysctl" }, "ok", ALL)
		t.expect(has(log, "sysctl")).toBe(false)
	end)

	it("refuses an unknown argument before any tool runs", function()
		local r, log = run({ "--force" }, "ok", ALL)
		t.expect(r.code).toBe(2)
		t.expect(has(r.stderr, "unknown argument --force")).toBe(true)
		t.expect(log).toBe("")
	end)
end)
