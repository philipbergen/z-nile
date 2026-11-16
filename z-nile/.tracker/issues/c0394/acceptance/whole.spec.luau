--!strict
-- c0394 AC10: a raft with no added issue lands exactly as before: one landing, the raft moves to done/, no part, no
-- Waiting: line. A small regression guard in a real-git fixture under .cache/c0394-whole (as stack-land.spec.luau); it
-- passes before c0394 and must stay green.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local f: trackerfix.Fixture
local env: { [string]: string } = {}

local function zn(dir: string, args: { string }): string
	local r = trackerfix.tr(f, dir, args, env)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

return t.spec("c0394 a raft with no added issue lands whole", function(it)
	it("a raft with no added issue lands whole", function()
		local body =
			"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"
		f = trackerfix.new("c0394-whole", {
			[".gitignore"] = fs.readFile(`{fixture.physical(".")}/../.gitignore`),
			[`{ROOT}/architecture.md`] = "# Architecture\n",
			[`{ROOT}/rafts/R0010/R0010.md`] = `---\nid: R0010\ntype: chore\ntitle: whole\nslug: whole\nsingle: false\nissues: [c0010]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\n`,
			[`{ROOT}/rafts/R0010/check.sh`] = CHECK,
			[`{ROOT}/issues/c0010/c0010.md`] = `---\nid: c0010\ntype: chore\ntitle: alpha\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# c0010\n\n{body}`,
			[`{ROOT}/issues/c0010/check.sh`] = CHECK,
			[`{ROOT}/issues/c0010/acceptance/.gitkeep`] = "",
		})
		local bin, log = `{f.base}/bin`, `{f.base}/gh.log`
		fs.writeDir(bin)
		local script = `#!/bin/sh\necho "$*" >> "{log}"\n`
			.. 'case "$1 $2" in\n'
			.. '  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
			.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
			.. '  "pr edit") exit 0 ;;\n'
			.. '  "pr view") echo body; exit 0 ;;\n'
			.. "esac\nexit 0\n"
		fs.writeFile(`{bin}/gh`, script)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		zn(wt, { "start", "R0010" })
		fs.writeDir(`{wt}/pickman/src`)
		fs.writeFile(`{wt}/pickman/src/alpha.luau`, "alpha\n")
		fs.writeDir(`{wt}/{ROOT}/rafts/active/R0010`)
		fs.writeFile(
			`{wt}/{ROOT}/rafts/active/R0010/final-review-001.md`,
			"# Final Review 001\n\nVerdict: approve\n"
		)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-qm", "c0010 work" })
		zn(wt, { "finish", "c0010" })
		seal.trace(wt, "R0010")

		local landed = zn(wt, { "done", "R0010" })
		t.expect(has(landed, "landed R0010")).toBe(true)
		t.expect(has(landed, "in part")).toBe(false)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`)).toBe(nil)
		t.expect(onOrigin(`{ROOT}/issues/done/c0010/c0010.md`) ~= nil).toBe(true)
		local bind = fixture.git(f.origin, { "log", "-1", "--format=%B", "main" })
		t.expect(has(bind, "R0010: bind c0010")).toBe(true)
		t.expect(has(bind, "Trace: pickman/.tracker/rafts/done/R0010/trace.md")).toBe(true)
		t.expect(has(bind, "Waiting:")).toBe(false)
	end)
end)
