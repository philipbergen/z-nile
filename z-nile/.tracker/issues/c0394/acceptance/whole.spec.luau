--!strict
-- c0394 AC10: a raft with no added issue lands exactly as before: one landing, the raft moves to done/, no `through`, no
-- Waiting: line. A small regression guard in a real-git fixture under .cache/c0394-whole (as stack-land.spec.luau); it
-- passes on today's main and after c0248, and must stay green. A raft readied once c0248 is on main carries
-- `layers: reviewed`: its layer then needs a stamped review and its landing a trace-NNN.md, so the case follows the
-- marker; on today's main it lands the old way (seal.trace). The assertions on the landing are the same.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")
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

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function zn(dir: string, args: { string }): string
	return must(trackerfix.tr(f, dir, args, env), "./zn " .. table.concat(args, " "))
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

-- A layer's review as the reviewer writes it (no stamp), committed by the tool, which stamps it.
local function review(dir: string, issueId: string)
	local folder = zn(dir, { "find", issueId })
	local top = 0
	for _, name in fs.readDir(`{dir}/{folder}`) do
		top = math.max(top, tonumber((string.match(name, "^review%-(%d+)%.md$"))) or 0)
	end
	write(dir, `{folder}/review-{string.format("%03d", top + 1)}.md`, "# Review\n\nVerdict: approve\n")
	zn(dir, { "commit", "-m", `tracker: review {issueId}` })
	git(dir, { "push", "-q" })
end

-- The final review and the trace of one landing, committed on the layer `dir` is on after its finish. Each landing has
-- its own: the round is the newest final review not yet on origin/main, else one more than the last on it.
local function sealBind(dir: string, raftId: string, through: string?)
	local args = { "trace", raftId }
	if through then
		table.insert(args, "--through")
		table.insert(args, through)
	end
	local parsed, err = trace.parse(zn(dir, args))
	if not parsed then
		error(`trace skeleton did not parse: {err}`, 2)
	end
	local raftDir = zn(dir, { "find", raftId })
	local top, topLocal = 0, 0
	for _, name in fs.readDir(`{dir}/{raftDir}`) do
		local k = tonumber((string.match(name, "^final%-review%-(%d+)%.md$")))
		if k then
			if fixture.exec(dir, "git", { "cat-file", "-e", `origin/main:{raftDir}/{name}` }).ok then
				top = math.max(top, k)
			end
			topLocal = math.max(topLocal, k)
		end
	end
	local num = string.format("%03d", if topLocal > top then topLocal else top + 1)
	local issueDirs: { [string]: string } = {}
	local checkLines: { [string]: number } = {}
	for _, row in parsed.claims do
		local id = string.match(row.claimId, "^([^:]+):") :: string
		if not issueDirs[id] then
			issueDirs[id] = zn(dir, { "find", id })
			checkLines[id] = 1
			local idx = 0
			for line in string.gmatch(fs.readFile(`{dir}/{issueDirs[id]}/check.sh`) .. "\n", "([^\n]*)\n") do
				idx += 1
				if string.match(line, "^%s*check%s+") then
					checkLines[id] = idx
					break
				end
			end
		end
	end
	local codeRef = if #parsed.sources > 0 then `{parsed.sources[1].file}:1` else "none"
	local firstClaim = if #parsed.claims > 0 then parsed.claims[1].claimId else ""
	local lines = {
		`# Trace: {raftId}`,
		"",
		`Commit: {parsed.commit}`,
		"",
		"## Claims",
		"",
		"| claim | design | test | code |",
		"|---|---|---|---|",
	}
	for _, row in parsed.claims do
		local id = string.match(row.claimId, "^([^:]+):") :: string
		table.insert(
			lines,
			`| {row.rawClaim} | {issueDirs[id]}/{id}.md:1 | {issueDirs[id]}/check.sh:{checkLines[id]} | {codeRef} |`
		)
	end
	table.insert(lines, "")
	table.insert(lines, "## Source files")
	table.insert(lines, "")
	table.insert(lines, "| file | claims |")
	table.insert(lines, "|---|---|")
	for _, srow in parsed.sources do
		table.insert(lines, `| {srow.file} | {firstClaim} |`)
	end
	table.insert(lines, "")
	write(dir, `{raftDir}/trace-{num}.md`, table.concat(lines, "\n"))
	write(dir, `{raftDir}/final-review-{num}.md`, `# Final Review {num}\n\nVerdict: approve\n`)
	git(dir, { "add", "-A", raftDir })
	git(dir, { "commit", "-qm", `{raftId}: final-review-{num}` })
	git(dir, { "push", "-q", "origin", git(dir, { "branch", "--show-current" }) })
end

return t.spec("c0394 a raft with no added issue lands whole", function(it)
	it("a raft with no added issue lands whole", function()
		local body =
			"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"
		f = trackerfix.new("c0394-whole", {
			[".gitignore"] = fs.readFile(`{fixture.physical(".")}/../.gitignore`),
			[`{ROOT}/architecture.md`] = "# Architecture\n",
			[`{ROOT}/rafts/R0010/R0010.md`] = `---\nid: R0010\ntype: chore\ntitle: whole\nslug: whole\nsingle: false\nissues: [c0010]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Theme\nWhole.\n\n## Order & dependencies\nc0010\n`,
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
		write(wt, "pickman/src/alpha.luau", "return 'alpha'\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0010 work" })
		-- the old way writes the final review before the finish; a marked raft's final review comes with its trace
		local marked = has(fs.readFile(`{wt}/{ROOT}/rafts/active/R0010/R0010.md`), "\nlayers: reviewed\n")
		if not marked then
			write(
				wt,
				`{ROOT}/rafts/active/R0010/final-review-001.md`,
				"# Final Review 001\n\nVerdict: approve\n"
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "the final review" })
		end
		zn(wt, { "finish", "c0010" })
		if marked then
			review(wt, "c0010")
			sealBind(wt, "R0010", nil)
		else
			seal.trace(wt, "R0010")
		end

		local landed = zn(wt, { "done", "R0010" })
		t.expect(has(landed, "landed R0010")).toBe(true)
		t.expect(has(landed, "through")).toBe(false)
		t.expect(has(landed, "in part")).toBe(false)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`)).toBe(nil)
		t.expect(onOrigin(`{ROOT}/issues/done/c0010/c0010.md`) ~= nil).toBe(true)
		local bind = git(f.origin, { "log", "-1", "--format=%B", "main" })
		t.expect(has(bind, "R0010: bind c0010")).toBe(true)
		t.expect(has(bind, `Trace: {ROOT}/rafts/done/R0010/trace`)).toBe(true)
		t.expect(has(bind, "Waiting:")).toBe(false)
	end)
end)
