--!strict
-- c0248 AC4 to AC9, AC11 and AC12: the tool stamps a layer's review, a layer is complete before the next starts, a
-- stack lands as one bind or as a shorter one (`done --through`) with a final review and trace per landing, the layers
-- above a landing are restacked onto main and keep their reviews when the patch is unchanged, and every layer's pull
-- request names the stack. Real git in a fixture under .cache: a bare origin whose path contains github.com, a worktree
-- per raft, and a `gh` stub that keeps each PR's base and body. Fixture: .cache/c0248-layers-land-github.com.
-- Nothing here touches the real repository. Eight rafts, so each case that lands a raft has its own:
--   R0010 AC4, AC6, AC8 (landed branches kept), AC12     R0050 AC8 (landed branches deleted from origin)
--   R0020 AC5 (start, top layer, main moves, full bind)  R0030 AC7 (refusals)
--   R0060 AC6 (the rendered raft template)               R0070 AC11 (a raft readied without the marker)
--   R0080 AC5 (a restack that changes the patch)         R0090 AC9 (stop and ready after an early landing)
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local OLDER = "9b8e7f0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f60"
local OTHER_PATCH = "7e02b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4"

local CAPTURED = table.concat({
	"## Problem",
	"The marker is missing.",
	"",
	"## Solution",
	"Store the marker.",
	"",
	"## Acceptance criteria",
	"- AC1: the marker is stored",
	"",
}, "\n")

local function issue(id: string, title: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, slug: string, issues: string, order: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nThe {slug} theme: layers that are reviewed one by one.\n\nA second paragraph that is not the Theme line.\n\n## Order & dependencies\n{order}\n`
end

-- The raft template, rendered for R0060: its own lines, with the project gate (a whole gate run) stubbed to true,
-- the sourcing of ac.sh made the fixture's, and an RC1 line that leaves a mark when it runs.
local function renderedTemplate(): string
	local text = fs.readFile(`{TOP}/z-nile/templates/raft/check.sh`)
	text = string.gsub(text, "{{ID}}", "R0060")
	text = string.gsub(text, "{{PROJECT}}", "pickman")
	local lines: { string } = {}
	for line in string.gmatch(text, "([^\n]*)\n") do
		if string.match(line, '^check "RC0: project gate') then
			line = 'check "RC0: project gate passes (affected)" true'
		elseif string.match(line, "^source ") then
			line = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"'
		elseif string.match(line, "^check .RC0: acceptance specs will survive promotion") then
			-- the fixture has no pickman/tests to type check; promote-check's scoping is shown by its own line below
			line = 'check "RC0: acceptance specs will survive promotion into tests/" true'
		elseif string.match(line, '^# check "RC1:') then
			line = 'check "RC1: the stack works end to end" bash -c \'echo ran > "$ZN_ROOT/.cache/rc1-ran"\''
		end
		table.insert(lines, line)
	end
	return table.concat(lines, "\n") .. "\n"
end

-- gh keeps each pull request's base and body in files, numbered by the layer's branch: R00<r>0/<n>/... is PR <r><n>.
-- A file named fail-body in the state folder makes every body edit fail.
local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
num() { echo "$1" | sed -n 's|^R00\(.\)0/\(.\)/.*|\1\2|p'; }
after() { want="$1"; shift; prev=""; for a in "$@"; do if [ "$prev" = "$want" ]; then echo "$a"; return; fi; prev="$a"; done; }
case "$1 $2" in
  "pr list") case "$*" in *number*) n=$(num "$(after --head "$@")"); [ -n "$n" ] && echo "$n" ;; esac; exit 0 ;;
  "pr create") n=$(num "$(after --head "$@")"); after --base "$@" > "@STATE@/base-$n"; echo "https://github.com/x/y/pull/$n"; exit 0 ;;
  "pr view") cat "@STATE@/base-$3" 2>/dev/null || echo main; exit 0 ;;
  "pr edit") n="$3"
    case "$*" in
      *--body-file*) if [ -e "@STATE@/fail-body" ]; then cat > /dev/null; echo "gh: HTTP 502" >&2; exit 1; fi; cat > "@STATE@/body-$n.md" ;;
      *--base*) after --base "$@" > "@STATE@/base-$n" ;;
    esac
    exit 0 ;;
esac
exit 0
]=]

local f: trackerfix.Fixture
local log, state = "", ""
local env: { [string]: string } = {}
-- one worktree per raft that has a cross-case life
local w: { [string]: string } = {}
local r20Top = ""
local bodyStart1, bodyAfterFinish1, bodyAfterStart2, bodyAfterBind1 = "", "", "", ""

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

local function znTry(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function body(number: string): string
	return fs.readFile(`{state}/body-{number}.md`)
end

local function work(dir: string, issueId: string, file: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", `{issueId} work` })
end

local function finishSha(dir: string, issueId: string): string
	for line in string.gmatch(git(dir, { "log", "--format=%H%x09%s", "-120" }) .. "\n", "([^\n]*)\n") do
		local sha, subject = string.match(line, "^(%x+)\t(.*)$")
		if sha and subject and string.sub(subject, 1, #issueId + 2) == `{issueId}: ` then
			return sha
		end
	end
	error(`no finish commit for {issueId}`, 2)
end

local function patchOf(dir: string, sha: string): string
	local r = fixture.exec(dir, "bash", { "-c", `git show --format= --no-color {sha} | git patch-id --stable` })
	return string.match(r.stdout, "^(%x+)") :: string
end

local function issueDir(dir: string, issueId: string): string
	return zn(dir, { "find", issueId })
end

local function reviewFiles(dir: string, issueId: string): { string }
	local out: { string } = {}
	local base = `{dir}/{issueDir(dir, issueId)}`
	for _, name in fs.readDir(base) do
		if string.match(name, "^review%-%d+%.md$") or string.match(name, "^refute%-%d+%.md$") then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

local function nextNumber(dir: string, issueId: string): string
	local top = 0
	for _, name in reviewFiles(dir, issueId) do
		local n = tonumber((string.match(name, "^review%-(%d+)%.md$")))
		if n and n > top then
			top = n
		end
	end
	return string.format("%03d", top + 1)
end

-- A layer's review as the reviewer writes it (no stamp), committed by the tool, which stamps it. Returns the file.
local function review(dir: string, issueId: string): string
	local path = `{issueDir(dir, issueId)}/review-{nextNumber(dir, issueId)}.md`
	write(dir, path, "# Review\n\nVerdict: approve\n")
	zn(dir, { "commit", "-m", `tracker: review {issueId}` })
	return path
end

-- A review made by hand, stamped with a commit and patch that are not the layer's: committed and pushed with git.
local function staleReview(dir: string, issueId: string)
	local path = `{issueDir(dir, issueId)}/review-{nextNumber(dir, issueId)}.md`
	write(dir, path, `# Review\n\nCommit: {OLDER}\nPatch: {OTHER_PATCH}\nVerdict: approve\n`)
	git(dir, { "add", "-A", path })
	git(dir, { "commit", "-qm", `tracker: stale review {issueId}` })
	git(dir, { "push", "-q", "origin", git(dir, { "branch", "--show-current" }) })
end

local function stackText(_dir: string, raftId: string): string
	git(f.other, { "fetch", "-q", "--prune", "origin" })
	return zn(f.other, { "stack", raftId })
end

-- start the next layer, build it and finish it
local function layer(dir: string, raftId: string, issueId: string, file: string)
	zn(dir, { "start", raftId })
	work(dir, issueId, file)
	zn(dir, { "finish", issueId })
end

local function bindMessage(): string
	return git(f.main, { "log", "-1", "--format=%B", "origin/main" })
end

local function tree(): string
	return git(f.main, { "ls-tree", "-r", "--name-only", "origin/main" })
end

local function head12(path: string): string
	local out, n = "", 0
	for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
		n += 1
		if n <= 12 then
			out ..= line .. "\n"
		end
	end
	return out
end

return t.spec("c0248 layers are complete before the next, and land as one bind or a shorter one", function(it)
	it(
		"sets up eight readied rafts behind a local github-shaped origin and a gh that keeps PR bases and bodies",
		function()
			local rafts: { [string]: { string } } = {
				R0010 = { "c0010", "c0020", "c0030" },
				R0020 = { "c0040", "c0050" },
				R0030 = { "c0070", "c0080" },
				R0050 = { "c0110", "c0120", "c0130" },
				R0060 = { "c0140", "c0150", "c0160" },
				R0070 = { "c0170", "c0180" },
				R0080 = { "c0190" },
				R0090 = { "c0200", "c0210" },
			}
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			}
			for raft, ids in rafts do
				seed[`pickman/.tracker/rafts/{raft}/{raft}.md`] =
					raftDoc(raft, string.lower(raft), table.concat(ids, ", "), table.concat(ids, "\n"))
				seed[`pickman/.tracker/rafts/{raft}/check.sh`] = if raft == "R0060" then renderedTemplate() else CHECK
				for _, id in ids do
					seed[`pickman/.tracker/issues/{id}/{id}.md`] = issue(id, `title {id}`, raft)
					-- the third member of R0060 is green only while its mark exists: it passes its own finish and fails a done
					seed[`pickman/.tracker/issues/{id}/check.sh`] = if id == "c0160"
						then 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
							.. 'check "AC1: the mark exists" test -f "$ZN_ROOT/.cache/c0160-ok"\nfinish\n'
						else CHECK
					seed[`pickman/.tracker/issues/{id}/acceptance/.gitkeep`] = ""
				end
			end
			f = trackerfix.new("c0248-layers-land-github.com", seed)
			local bin = `{f.base}/bin`
			log, state = `{f.base}/gh.log`, `{f.base}/gh-state`
			fs.writeDir(bin)
			fs.writeDir(state)
			local script = (string.gsub((string.gsub(GH, "@LOG@", log)), "@STATE@", state))
			fs.writeFile(`{bin}/gh`, script)
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			for raft in rafts do
				trackerfix.trOk(f, f.main, { "ready", raft })
			end
			for raft in { R0010 = 1, R0020 = 1, R0030 = 1, R0050 = 1, R0060 = 1, R0080 = 1, R0090 = 1 } do
				w[raft] = trackerfix.trOk(f, f.main, { "worktree", raft })
			end
			-- AC11: ready marks the rafts it readies; R0070 is then made one that was readied before the marker existed
			git(f.other, { "pull", "-q", "origin", "main" })
			local doc = `pickman/.tracker/rafts/active/R0070/R0070.md`
			local text = fs.readFile(`{f.other}/{doc}`)
			t.expect(has(text, "\nlayers: reviewed\n")).toBe(true)
			t.expect(has(fs.readFile(`{f.other}/pickman/.tracker/rafts/active/R0010/R0010.md`), "\nlayers: reviewed\n"))
				.toBe(true)
			trackerfix.elsewhere(
				f,
				{ [doc] = (string.gsub(text, "layers: reviewed\n", "")) },
				"R0070 as readied before layers were reviewed"
			)
			w.R0070 = trackerfix.trOk(f, f.main, { "worktree", "R0070" })
		end
	)

	it(
		"AC4: ./zn commit stamps a new review in the issue folder with the finish commit and its patch, and refuses one on an unfinished layer",
		function()
			local wt = w.R0010
			zn(wt, { "start", "R0010" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/1/c0010")
			bodyStart1 = body("11")
			work(wt, "c0010", "alpha")
			-- a review on a layer that is not finished is refused, and the file is left as the reviewer wrote it
			local path = `{issueDir(wt, "c0010")}/review-001.md`
			write(wt, path, "# Review\n\nVerdict: approve\n")
			local early = znTry(wt, { "commit", "-m", "tracker: review c0010" })
			t.expect(early.ok).toBe(false)
			t.expect(has(early.stderr, "c0010 is not finished")).toBe(true)
			t.expect(fs.readFile(`{wt}/{path}`)).toBe("# Review\n\nVerdict: approve\n")
			fs.removeFile(`{wt}/{path}`)
			zn(wt, { "finish", "c0010" })
			bodyAfterFinish1 = body("11")
			-- finished: the tool stamps the commit the layer is at and its patch id, and commits the file
			local sha = finishSha(wt, "c0010")
			write(wt, path, "# Review\n\nVerdict: approve\n")
			zn(wt, { "commit", "-m", "tracker: review c0010" })
			local head = head12(`{wt}/{path}`)
			t.expect(has(head, `Commit: {sha}\n`)).toBe(true)
			t.expect(has(head, `Patch: {patchOf(wt, sha)}\n`)).toBe(true)
			t.expect(has(head, "Verdict: approve")).toBe(true)
			t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("tracker: review c0010")
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			-- a file that already carries a stamp keeps it
			write(wt, `{issueDir(wt, "c0010")}/refute-001.md`, `# Refute\n\nCommit: {OLDER}\nPatch: {OTHER_PATCH}\n`)
			zn(wt, { "commit", "-m", "tracker: refute c0010" })
			t.expect(has(fs.readFile(`{wt}/{issueDir(wt, "c0010")}/refute-001.md`), `Commit: {OLDER}\n`)).toBe(true)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			git(wt, { "push", "-q", "--force-with-lease", "origin", "R0010/1/c0010" })
		end
	)

	it("AC4: a review committed in the issue folder after finish keeps the layer finished", function()
		local wt = w.R0010
		-- the review is a commit after the finish commit; the layer is still finished (not claimed again) and complete
		t.expect(has(stackText(wt, "R0010"), "1 R0010/1/c0010 c0010 complete")).toBe(true)
		t.expect(git(wt, { "rev-list", "--count", "origin/main..HEAD" })).toBe("2") -- the finish commit and the review
		-- a layer is finished only while what follows its finish commit is such files: source after it is not
		write(wt, "pickman/src/extra.luau", "return 1\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "unfinishing" })
		git(wt, { "push", "-q" })
		t.expect(has(stackText(wt, "R0010"), "1 R0010/1/c0010 c0010 claimed")).toBe(true)
		git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		git(wt, { "push", "-q", "--force-with-lease" })
		t.expect(has(stackText(wt, "R0010"), "1 R0010/1/c0010 c0010 complete")).toBe(true)
	end)

	it("builds R0010's layers 2 and 3 above a complete layer 1, each complete before the next", function()
		local wt = w.R0010
		zn(wt, { "start", "R0010" })
		bodyAfterStart2 = body("11")
		work(wt, "c0020", "beta")
		zn(wt, { "finish", "c0020" })
		review(wt, "c0020")
		-- layer 3 exists before layers 1 and 2 land: the decided order
		layer(wt, "R0010", "c0030", "gamma")
		review(wt, "c0030")
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/3/c0030")
		local seen = stackText(wt, "R0010")
		for _, row in
			{
				"1 R0010/1/c0010 c0010 complete",
				"2 R0010/2/c0020 c0020 complete",
				"3 R0010/3/c0030 c0030 complete",
			}
		do
			t.expect(has(seen, row)).toBe(true)
		end
	end)

	it(
		"AC6: done --through lands only the layers up to the named one with its own final-review-NNN and trace-NNN, moves only them, keeps the raft active, retargets the next PR to main",
		function()
			local wt = w.R0010
			git(wt, { "switch", "-q", "R0010/2/c0020" })
			local before = git(f.main, { "rev-parse", "origin/main" })
			-- no final review yet
			local noReview = znTry(wt, { "done", "R0010", "--through", "c0020" })
			t.expect(noReview.ok).toBe(false)
			t.expect(has(noReview.stderr, "final-review")).toBe(true)
			-- the skeleton covers the layers up to c0020 and names that layer's finish commit
			local skeleton = zn(wt, { "trace", "R0010", "--through", "c0020" })
			t.expect(has(skeleton, `Commit: {finishSha(wt, "c0020")}`)).toBe(true)
			t.expect(has(skeleton, "| c0010:")).toBe(true)
			t.expect(has(skeleton, "| c0020:")).toBe(true)
			t.expect(has(skeleton, "c0030:")).toBe(false)
			t.expect(znTry(wt, { "trace", "R0010", "--through", "c0020", "--check" }).ok).toBe(false) -- no trace yet
			seal.trace(wt, "R0010", "c0020")
			t.expect(has(zn(wt, { "trace", "R0010", "--through", "c0020", "--check" }), "ok: R0010")).toBe(true)
			-- the trace and review are over the two layers; a done without --through wants a third
			t.expect(znTry(wt, { "done", "R0010" }).ok).toBe(false)
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
			-- a stale PR body, so that done's own rewrite shows
			fs.writeFile(`{state}/body-13.md`, "stale\n")
			local top = git(wt, { "rev-parse", "HEAD" })
			local landed = zn(wt, { "done", "R0010", "--through", "c0020" })
			t.expect(has(landed, "landed R0010")).toBe(true)
			local bind = bindMessage()
			t.expect(
				startsWith(
					bind,
					"R0010: bind c0010, c0020\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/active/R0010/trace-001.md\n"
				)
			).toBe(true)
			-- the bind names only what it landed
			t.expect(has(bind, "Issue: c0010") and has(bind, "Issue: c0020")).toBe(true)
			t.expect(has(bind, "c0030")).toBe(false)
			t.expect(git(f.main, { "rev-parse", "origin/main^2" })).toBe(top)
			-- exactly the landed members moved; the third and the raft did not
			local files = tree()
			t.expect(has(files, "pickman/.tracker/issues/done/c0010/c0010.md")).toBe(true)
			t.expect(has(files, "pickman/.tracker/issues/done/c0020/c0020.md")).toBe(true)
			t.expect(has(files, "pickman/.tracker/issues/active/c0030/c0030.md")).toBe(true)
			t.expect(has(files, "pickman/.tracker/issues/done/c0030/")).toBe(false)
			t.expect(has(files, "pickman/.tracker/rafts/active/R0010/R0010.md")).toBe(true)
			t.expect(has(files, "pickman/.tracker/rafts/done/R0010/")).toBe(false)
			-- the landing's own files, in the raft folder
			t.expect(has(files, "pickman/.tracker/rafts/active/R0010/final-review-001.md")).toBe(true)
			t.expect(has(files, "pickman/.tracker/rafts/active/R0010/trace-001.md")).toBe(true)
			t.expect(has(files, "pickman/.tracker/rafts/active/R0010/trace.md")).toBe(false)
			-- only the landed members' acceptance folders were promoted
			t.expect(has(files, "pickman/tests/acceptance/c0010/")).toBe(true)
			t.expect(has(files, "pickman/tests/acceptance/c0020/")).toBe(true)
			t.expect(has(files, "pickman/tests/acceptance/c0030/")).toBe(false)
			t.expect(has(files, "pickman/src/alpha.luau") and has(files, "pickman/src/beta.luau")).toBe(true)
			-- the landed layers' pull requests and the next layer's go to main
			local calls = fs.readFile(log)
			t.expect(has(calls, "pr edit 11 --base main")).toBe(true)
			t.expect(has(calls, "pr edit 12 --base main")).toBe(true)
			t.expect(has(calls, "pr edit 13 --base main")).toBe(true)
			t.expect(fs.readFile(`{state}/base-13`)).toBe("main\n")
			bodyAfterBind1 = body("13")
		end
	)

	it(
		"AC8: in the decided order (layer 3 exists, then layers 1-2 land), restack moves layer 3 onto main, its review stays current, and the second landing lands with its own final review and trace and moves the raft (landed branches kept)",
		function()
			local wt = w.R0010
			git(wt, { "switch", "-q", "R0010/3/c0030" })
			-- the landed branches are kept (GitHub's default): the stack shows them landed, the third is not yet on main
			local seen = stackText(wt, "R0010")
			t.expect(has(seen, "1 R0010/1/c0010 c0010 landed")).toBe(true)
			t.expect(has(seen, "2 R0010/2/c0020 c0020 landed")).toBe(true)
			-- layer 3 was cut from layer 2's old tip, not from main: it waits for a restack (its base is main now)
			t.expect(has(seen, "3 R0010/3/c0030 c0030 claimed")).toBe(true)
			local refusedHere = znTry(wt, { "done", "R0010" })
			t.expect(refusedHere.ok).toBe(false)
			t.expect(has(refusedHere.stderr, "R0010/3/c0030 is not based on main: ./zn restack R0010")).toBe(true)
			-- restack moves layer 3 onto main: new commits, the same patch, so the review stays current
			local oldSha = finishSha(wt, "c0030")
			local patch = patchOf(wt, oldSha)
			local files = reviewFiles(wt, "c0030")
			fs.writeFile(`{state}/body-13.md`, "stale\n")
			zn(wt, { "restack", "R0010" })
			t.expect(has(body("13"), "Raft **R0010**: r0010")).toBe(true) -- the restack rewrote the body
			git(wt, { "fetch", "-q", "origin" })
			t.expect(git(wt, { "merge-base", "--is-ancestor", "origin/main", "HEAD" }) == "").toBe(true)
			t.expect(finishSha(wt, "c0030") ~= oldSha).toBe(true)
			t.expect(patchOf(wt, finishSha(wt, "c0030"))).toBe(patch)
			t.expect(reviewFiles(wt, "c0030")).toEqual(files)
			t.expect(has(stackText(wt, "R0010"), "3 R0010/3/c0030 c0030 complete")).toBe(true)
			-- a body edit that fails only warns
			fs.writeFile(`{state}/fail-body`, "")
			local warned = znTry(wt, { "restack", "R0010" })
			fs.removeFile(`{state}/fail-body`)
			t.expect(warned.ok).toBe(true)
			t.expect(has(warned.stderr, "warning")).toBe(true)
			-- the second landing has its own final review and trace: no add/add with the first's
			seal.trace(wt, "R0010")
			t.expect(has(zn(wt, { "trace", "R0010", "--check" }), "ok: R0010")).toBe(true)
			local landed = zn(wt, { "done", "R0010" })
			t.expect(has(landed, "landed R0010")).toBe(true)
			local bind2 = bindMessage()
			t.expect(
				startsWith(
					bind2,
					"R0010: bind c0030\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/done/R0010/trace-002.md\n"
				)
			).toBe(true)
			t.expect(has(bind2, "c0010")).toBe(false)
			local landedTree = tree()
			for _, name in { "R0010.md", "final-review-001.md", "final-review-002.md", "trace-001.md", "trace-002.md" } do
				t.expect(has(landedTree, `pickman/.tracker/rafts/done/R0010/{name}`)).toBe(true)
			end
			t.expect(has(landedTree, "pickman/.tracker/rafts/active/R0010/")).toBe(false)
			t.expect(has(landedTree, "pickman/.tracker/issues/done/c0030/c0030.md")).toBe(true)
			t.expect(has(landedTree, "pickman/tests/acceptance/c0030/")).toBe(true)
			t.expect(git(f.main, { "log", "--format=%s", "--grep=^R0010: bind", "origin/main" }))
				.toBe("R0010: bind c0030\nR0010: bind c0010, c0020")
		end
	)

	it(
		"AC12: every layer PR body names the raft's Theme, Order and the stack, rewritten by start, finish, restack and done, and a failed edit only warns",
		function()
			-- written by start: layer 1's body before its finish
			t.expect(has(bodyStart1, "Raft **R0010**: r0010")).toBe(true)
			t.expect(has(bodyStart1, "The r0010 theme: layers that are reviewed one by one.")).toBe(true)
			t.expect(has(bodyStart1, "A second paragraph")).toBe(false) -- the Theme is its first paragraph
			t.expect(has(bodyStart1, "## Order")).toBe(true)
			t.expect(has(bodyStart1, "c0010\nc0020\nc0030")).toBe(true)
			t.expect(has(bodyStart1, "## Stack")).toBe(true)
			t.expect(has(bodyStart1, "| 1 (this layer) | c0010 | `R0010/1/c0010` | #11 | claimed |")).toBe(true)
			-- rewritten by finish
			t.expect(has(bodyAfterFinish1, "| 1 (this layer) | c0010 | `R0010/1/c0010` | #11 | finished |")).toBe(true)
			t.expect(has(bodyAfterFinish1, "| 2 | c0020 | `R0010/2/c0020` | - | missing |")).toBe(true)
			-- rewritten by the start of layer 2, on layer 1's PR
			t.expect(has(bodyAfterStart2, "| 2 | c0020 | `R0010/2/c0020` | #12 | claimed |")).toBe(true)
			-- rewritten by done for the layer that goes on: the landed layers show as landed, this one is marked
			t.expect(has(bodyAfterBind1, "| 1 | c0010 | `R0010/1/c0010` | - | landed |")).toBe(true)
			t.expect(has(bodyAfterBind1, "| 2 | c0020 | `R0010/2/c0020` | - | landed |")).toBe(true)
			t.expect(has(bodyAfterBind1, "| 3 (this layer) | c0030 | `R0010/3/c0030` | #13 | claimed |")).toBe(true) -- it waits for its restack onto main
			-- the refresh is an edit with the body on standard input; restack's and the failing edit's are in AC8's case
			t.expect(has(fs.readFile(log), "pr edit 13 --body-file -")).toBe(true)
		end
	)
	it(
		"AC5: start refuses the next layer until the layer below is complete, naming it, and opens it once the review is settled",
		function()
			local wt = w.R0020
			zn(wt, { "start", "R0020" })
			work(wt, "c0040", "pair1")
			zn(wt, { "finish", "c0040" })
			-- finished, but no review in the issue's folder
			local none = znTry(wt, { "start", "R0020" })
			t.expect(none.ok).toBe(false)
			t.expect(has(none.stderr, "c0040 is not complete")).toBe(true)
			t.expect(has(none.stderr, "review")).toBe(true)
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0020/1/c0040")
			-- a review stamped with another commit and another patch is not current
			staleReview(wt, "c0040")
			local stale = znTry(wt, { "start", "R0020" })
			t.expect(stale.ok).toBe(false)
			t.expect(has(stale.stderr, "c0040 is not complete")).toBe(true)
			t.expect(has(stale.stderr, string.sub(OLDER, 1, 7))).toBe(true)
			t.expect(has(stale.stderr, string.sub(finishSha(wt, "c0040"), 1, 7))).toBe(true)
			t.expect(has(stale.stderr, string.sub(OTHER_PATCH, 1, 4))).toBe(true)
			t.expect(has(git(f.main, { "branch", "-r" }), "R0020/2/c0050")).toBe(false)
			-- the newest review is the one that counts: the tool-stamped review-002 settles it
			t.expect(review(wt, "c0040")).toBe(`{issueDir(wt, "c0040")}/review-002.md`)
			zn(wt, { "start", "R0020" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0020/2/c0050")
			t.expect(has(fs.readFile(log), "--base R0020/1/c0040 --head R0020/2/c0050")).toBe(true)
			-- the first PR's body was rewritten by this start: the stack now has a second layer
			t.expect(has(body("21"), "| 2 | c0050 | `R0020/2/c0050` | #22 | claimed |")).toBe(true)
		end
	)

	it("AC5: done refuses a stack whose top layer is not complete", function()
		local wt = w.R0020
		work(wt, "c0050", "pair2")
		zn(wt, { "finish", "c0050" })
		-- its review names an older commit; the final review and trace are there
		staleReview(wt, "c0050")
		seal.trace(wt, "R0020")
		local before = git(f.main, { "rev-parse", "origin/main" })
		local refused = znTry(wt, { "done", "R0020" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "c0050 is not complete")).toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
		t.expect(has(git(f.main, { "log", "--format=%s", "origin/main" }), "R0020: bind")).toBe(false)
	end)

	it("AC5: main moves, restack, done lands with no new review files", function()
		local wt = w.R0020
		review(wt, "c0050")
		local files40, files50 = reviewFiles(wt, "c0040"), reviewFiles(wt, "c0050")
		local patch40, patch50 = patchOf(wt, finishSha(wt, "c0040")), patchOf(wt, finishSha(wt, "c0050"))
		local sha50 = finishSha(wt, "c0050")
		-- main moves under the stack
		trackerfix.elsewhere(f, { ["pickman/src/moved.luau"] = "return 'moved'\n" }, "main moves on")
		local restacked = zn(wt, { "restack", "R0020" })
		t.expect(has(restacked, "restacked R0020")).toBe(true)
		-- E6: a clean restack changes the commits and keeps the patches, so the reviews stay current
		t.expect(finishSha(wt, "c0050") ~= sha50).toBe(true)
		t.expect(patchOf(wt, finishSha(wt, "c0040"))).toBe(patch40)
		t.expect(patchOf(wt, finishSha(wt, "c0050"))).toBe(patch50)
		local seen = stackText(wt, "R0020")
		t.expect(has(seen, "1 R0020/1/c0040 c0040 complete")).toBe(true)
		t.expect(has(seen, "2 R0020/2/c0050 c0050 complete")).toBe(true)
		-- the trace named the old finish commit: the landing's trace is written again, and no review file is
		seal.trace(wt, "R0020")
		t.expect(reviewFiles(wt, "c0040")).toEqual(files40)
		t.expect(reviewFiles(wt, "c0050")).toEqual(files50)
		r20Top = git(wt, { "rev-parse", "HEAD" })
		local landed = zn(wt, { "done", "R0020" })
		t.expect(has(landed, "landed R0020")).toBe(true)
	end)

	it("AC5: a full done of complete layers lands the same bind as #296", function()
		local top = r20Top
		-- #296's bind: one --no-ff merge of the top layer, the message, every member and the raft in done/
		local bind = bindMessage()
		t.expect(
			startsWith(
				bind,
				"R0020: bind c0040, c0050\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/done/R0020/trace-001.md\n"
			)
		).toBe(true)
		t.expect(has(bind, "Issue: c0040") and has(bind, "Issue: c0050")).toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/main^2" })).toBe(top)
		local parents = git(f.main, { "log", "-1", "--format=%P", "origin/main" })
		t.expect(select(2, string.gsub(parents, "%x+", ""))).toBe(2)
		local files = tree()
		for _, id in { "c0040", "c0050" } do
			t.expect(has(files, `pickman/.tracker/issues/done/{id}/{id}.md`)).toBe(true)
			t.expect(has(files, `pickman/.tracker/issues/active/{id}/`)).toBe(false)
			t.expect(has(files, `pickman/tests/acceptance/{id}/`)).toBe(true)
		end
		t.expect(has(files, "pickman/.tracker/rafts/done/R0020/R0020.md")).toBe(true)
		t.expect(has(files, "pickman/.tracker/rafts/done/R0020/final-review-001.md")).toBe(true)
		t.expect(has(files, "pickman/.tracker/rafts/done/R0020/trace-001.md")).toBe(true)
		t.expect(has(files, "pickman/.tracker/rafts/active/R0020/")).toBe(false)
		t.expect(has(files, "pickman/src/pair1.luau") and has(files, "pickman/src/pair2.luau")).toBe(true)
		-- every layer's pull request went to main before the push
		local calls = fs.readFile(log)
		t.expect(has(calls, "pr edit 21 --base main")).toBe(true)
		t.expect(has(calls, "pr edit 22 --base main")).toBe(true)
	end)

	it(
		"AC5: a restack whose conflict resolution changes a layer's patch leaves it not complete, naming both commits",
		function()
			local wt = w.R0080
			zn(wt, { "start", "R0080" })
			work(wt, "c0190", "clash")
			zn(wt, { "finish", "c0190" })
			review(wt, "c0190")
			local oldSha, oldPatch = finishSha(wt, "c0190"), patchOf(wt, finishSha(wt, "c0190"))
			t.expect(has(stackText(wt, "R0080"), "1 R0080/1/c0190 c0190 complete")).toBe(true)
			-- main adds the same file with other content: the restack stops at the conflict
			trackerfix.elsewhere(f, { ["pickman/src/clash.luau"] = 'return "main"\n' }, "main adds clash")
			local stopped = znTry(wt, { "restack", "R0080" })
			t.expect(stopped.ok).toBe(false)
			t.expect(has(stopped.stderr, "conflict")).toBe(true)
			-- the resolution is made by hand, and it changes the layer's patch
			git(wt, { "fetch", "-q", "origin" })
			local branch = "R0080/1/c0190"
			local upstream = git(wt, { "merge-base", branch, "origin/main" })
			local rebase = fixture.exec(wt, "git", { "rebase", "--onto", "origin/main", upstream, branch })
			t.expect(rebase.ok).toBe(false)
			write(wt, "pickman/src/clash.luau", 'return "main and layer"\n')
			git(wt, { "add", "-A" })
			fixture.exec(wt, "git", { "-c", "core.editor=true", "rebase", "--continue" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe(branch)
			git(wt, { "push", "-q", "--force-with-lease", "origin", branch })
			local newSha = finishSha(wt, "c0190")
			t.expect(newSha ~= oldSha).toBe(true)
			t.expect(patchOf(wt, newSha) ~= oldPatch).toBe(true)
			t.expect(has(stackText(wt, "R0080"), "1 R0080/1/c0190 c0190 finished")).toBe(true)
			seal.trace(wt, "R0080")
			local refused = znTry(wt, { "done", "R0080" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "c0190 is not complete")).toBe(true)
			t.expect(has(refused.stderr, string.sub(oldSha, 1, 7))).toBe(true)
			t.expect(has(refused.stderr, string.sub(newSha, 1, 7))).toBe(true)
			t.expect(has(refused.stderr, string.sub(oldPatch, 1, 4))).toBe(true)
			t.expect(has(git(f.main, { "log", "--format=%s", "origin/main" }), "R0080: bind")).toBe(false)
		end
	)

	it("AC8: the same with the landed branches deleted from origin", function()
		local wt = w.R0050
		zn(wt, { "start", "R0050" })
		work(wt, "c0110", "d1")
		zn(wt, { "finish", "c0110" })
		review(wt, "c0110")
		layer(wt, "R0050", "c0120", "d2")
		review(wt, "c0120")
		layer(wt, "R0050", "c0130", "d3")
		review(wt, "c0130")
		-- the first landing, layers 1 and 2
		git(wt, { "switch", "-q", "R0050/2/c0120" })
		seal.trace(wt, "R0050", "c0120")
		zn(wt, { "done", "R0050", "--through", "c0120" })
		-- GitHub deletes a merged branch: the landed layers' branches go from origin and from this clone
		git(wt, { "switch", "-q", "R0050/3/c0130" })
		git(wt, { "push", "-q", "origin", "--delete", "R0050/1/c0110", "R0050/2/c0120" })
		git(wt, { "branch", "-q", "-D", "R0050/1/c0110", "R0050/2/c0120" })
		git(wt, { "fetch", "-q", "--prune", "origin" })
		t.expect(has(git(wt, { "branch", "-a" }), "R0050/2/c0120")).toBe(false)
		-- the count is one layer per member not yet landed: the stack shows the landed layers, the third is the one to build
		local seen = stackText(wt, "R0050")
		t.expect(has(seen, "c0110 landed")).toBe(true)
		t.expect(has(seen, "c0120 landed")).toBe(true)
		t.expect(has(seen, "3 R0050/3/c0130 c0130 claimed")).toBe(true) -- it waits for its restack onto main
		local resumed = zn(wt, { "start", "R0050" })
		t.expect(has(resumed, "on branch R0050/3/c0130")).toBe(true)
		local patch = patchOf(wt, finishSha(wt, "c0130"))
		zn(wt, { "restack", "R0050" })
		git(wt, { "fetch", "-q", "origin" })
		t.expect(git(wt, { "merge-base", "--is-ancestor", "origin/main", "HEAD" }) == "").toBe(true)
		t.expect(patchOf(wt, finishSha(wt, "c0130"))).toBe(patch)
		t.expect(has(stackText(wt, "R0050"), "3 R0050/3/c0130 c0130 complete")).toBe(true)
		seal.trace(wt, "R0050")
		zn(wt, { "done", "R0050" })
		local bind2 = bindMessage()
		t.expect(
			startsWith(
				bind2,
				"R0050: bind c0130\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/done/R0050/trace-002.md\n"
			)
		).toBe(true)
		local landedTree = tree()
		t.expect(has(landedTree, "pickman/.tracker/rafts/done/R0050/final-review-002.md")).toBe(true)
		t.expect(has(landedTree, "pickman/.tracker/rafts/done/R0050/trace-001.md")).toBe(true)
		t.expect(has(landedTree, "pickman/.tracker/issues/done/c0130/c0130.md")).toBe(true)
	end)

	it(
		"AC6: on a raft whose check.sh is the rendered template and whose third member's check.sh fails, done --through c0150 lands, members prints two folders, RC1 is skipped, and a full done refuses",
		function()
			local wt = w.R0060
			zn(wt, { "start", "R0060" })
			work(wt, "c0140", "t1")
			zn(wt, { "finish", "c0140" })
			review(wt, "c0140")
			layer(wt, "R0060", "c0150", "t2")
			review(wt, "c0150")
			-- the third member is green only while its mark exists
			fs.writeDir(`{wt}/.cache`)
			fs.writeFile(`{wt}/.cache/c0160-ok`, "")
			layer(wt, "R0060", "c0160", "t3")
			review(wt, "c0160")
			fs.removeFile(`{wt}/.cache/c0160-ok`)
			-- the raft's checks see the landing's own members when ZN_BIND_MEMBERS says so, and refuse a stranger
			local all = zn(wt, { "members", "R0060" })
			t.expect(#string.split(all, "\n")).toBe(3)
			local scopedEnv: { [string]: string } = { PATH = env.PATH, ZN_BIND_MEMBERS = "c0140,c0150" }
			local two = must(trackerfix.tr(f, wt, { "members", "R0060" }, scopedEnv), "members")
			t.expect(#string.split(two, "\n")).toBe(2)
			t.expect(has(two, "c0160")).toBe(false)
			local stranger: { [string]: string } = { PATH = env.PATH, ZN_BIND_MEMBERS = "c0140,c0099" }
			t.expect(trackerfix.tr(f, wt, { "members", "R0060" }, stranger).ok).toBe(false)
			-- promote-check copies only the landing's members' specs (it goes on to fail on the fixture's missing pickman/tests)
			local spec = `{wt}/{issueDir(wt, "c0160")}/acceptance/x.spec.luau`
			fs.writeFile(spec, "return nil\n")
			local unscoped = trackerfix.tr(f, wt, { "promote-check", "R0060" }, env)
			local scoped = trackerfix.tr(f, wt, { "promote-check", "R0060" }, scopedEnv)
			fs.removeFile(spec)
			t.expect(has(unscoped.stdout, "copied 1 acceptance specs")).toBe(true)
			t.expect(has(scoped.stdout, "copied 0 acceptance specs")).toBe(true)
			-- the first landing: layers 1 and 2, RC0 over their members, RC1 and up skipped
			git(wt, { "switch", "-q", "R0060/2/c0150" })
			seal.trace(wt, "R0060", "c0150")
			local landed = zn(wt, { "done", "R0060", "--through", "c0150" })
			t.expect(has(landed, "landed R0060")).toBe(true)
			t.expect(has(landed, "SKIP RC1: an early landing; it runs at the last landing")).toBe(true)
			t.expect(fs.isFile(`{wt}/.cache/rc1-ran`)).toBe(false)
			t.expect(has(bindMessage(), "R0060: bind c0140, c0150")).toBe(true)
			-- a full done: the third member's check fails, and RC1 runs this time
			git(wt, { "switch", "-q", "R0060/3/c0160" })
			fs.writeFile(`{wt}/.cache/c0160-ok`, "") -- restack runs the layer's check.sh
			zn(wt, { "restack", "R0060" })
			seal.trace(wt, "R0060")
			fs.removeFile(`{wt}/.cache/c0160-ok`)
			local before = git(f.main, { "rev-parse", "origin/main" })
			local refused = znTry(wt, { "done", "R0060" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stdout .. refused.stderr, "FAIL  RC0: c0160 acceptance checks pass")).toBe(true)
			t.expect(has(refused.stdout, "SKIP RC1")).toBe(false)
			t.expect(fs.isFile(`{wt}/.cache/rc1-ran`)).toBe(true)
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
			-- with the mark back, the last landing lands the third
			fs.writeFile(`{wt}/.cache/c0160-ok`, "")
			t.expect(has(zn(wt, { "done", "R0060" }), "landed R0060")).toBe(true)
		end
	)

	it(
		"AC7: done --through refuses a HEAD that is not that layer's tip, an id that is not a member or already landed, an incomplete layer",
		function()
			local wt = w.R0030
			local before = git(f.main, { "rev-parse", "origin/main" })
			zn(wt, { "start", "R0030" })
			work(wt, "c0070", "gap1")
			zn(wt, { "finish", "c0070" })
			-- layer 2 built by hand on a layer 1 that has no review
			git(wt, { "switch", "-q", "-c", "R0030/2/c0080" })
			git(wt, { "commit", "-q", "--allow-empty", "-m", "tracker: start R0030 r0030" })
			work(wt, "c0080", "gap2")
			zn(wt, { "finish", "c0080" })
			review(wt, "c0080")
			seal.trace(wt, "R0030")
			for _, args in { { "done", "R0030" }, { "done", "R0030", "--through", "c0080" } } do
				local below = znTry(wt, args)
				t.expect(below.ok).toBe(false)
				t.expect(has(below.stderr, "c0070 is not complete")).toBe(true)
			end
			-- a HEAD on layer 2 is no more the tip of the layer --through c0070 names
			local above = znTry(wt, { "done", "R0030", "--through", "c0070" })
			t.expect(above.ok).toBe(false)
			t.expect(has(above.stderr, "R0030/1/c0070 is")).toBe(true)
			-- a HEAD on the layer below the named one
			git(wt, { "switch", "-q", "R0030/1/c0070" })
			local wrongHead = znTry(wt, { "done", "R0030", "--through", "c0080" })
			t.expect(wrongHead.ok).toBe(false)
			t.expect(has(wrongHead.stderr, "R0030/2/c0080 is")).toBe(true)
			-- an id that is not a member of the raft, and a member of another raft
			local stranger = znTry(wt, { "done", "R0030", "--through", "c0099" })
			t.expect(stranger.ok).toBe(false)
			t.expect(has(stranger.stderr, "c0099")).toBe(true)
			t.expect(znTry(wt, { "done", "R0030", "--through", "c0010" }).ok).toBe(false)
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
			-- the review makes layer 1 complete, and it lands; landed, it cannot be named again
			review(wt, "c0070")
			seal.trace(wt, "R0030", "c0070")
			t.expect(has(zn(wt, { "done", "R0030", "--through", "c0070" }), "landed R0030")).toBe(true)
			local again = znTry(wt, { "done", "R0030", "--through", "c0070" })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stderr, "c0070 is already landed")).toBe(true)
		end
	)

	it(
		"AC9: after an early landing, stop and ready keep the landed members and start opens the next layer above them",
		function()
			local wt = w.R0090
			zn(wt, { "start", "R0090" })
			work(wt, "c0200", "s1")
			zn(wt, { "finish", "c0200" })
			review(wt, "c0200")
			seal.trace(wt, "R0090", "c0200")
			zn(wt, { "done", "R0090", "--through", "c0200" })
			-- stop gives the unlanded member back and leaves the landed one in done/
			trackerfix.trOk(f, f.main, { "stop", "R0090" })
			git(f.other, { "pull", "-q", "origin", "main" })
			local stopped = git(f.other, { "ls-tree", "-r", "--name-only", "origin/main" })
			t.expect(has(stopped, "pickman/.tracker/issues/done/c0200/c0200.md")).toBe(true)
			t.expect(has(stopped, "pickman/.tracker/issues/c0210/c0210.md")).toBe(true)
			t.expect(has(stopped, "pickman/.tracker/rafts/R0090/R0090.md")).toBe(true)
			-- ready moves only the unlanded member, and the raft keeps its marker
			trackerfix.trOk(f, f.main, { "ready", "R0090" })
			git(f.other, { "pull", "-q", "origin", "main" })
			local readied = git(f.other, { "ls-tree", "-r", "--name-only", "origin/main" })
			t.expect(has(readied, "pickman/.tracker/issues/active/c0210/c0210.md")).toBe(true)
			t.expect(has(readied, "pickman/.tracker/issues/done/c0200/c0200.md")).toBe(true)
			t.expect(has(readied, "pickman/.tracker/issues/active/c0200/")).toBe(false)
			t.expect(has(fs.readFile(`{f.other}/pickman/.tracker/rafts/active/R0090/R0090.md`), "\nlayers: reviewed\n"))
				.toBe(true)
			-- start resumes above the landed layer: cut from main, its PR on main
			git(wt, { "switch", "-q", "R0090/1/c0200" })
			zn(wt, { "sync" })
			local opened = zn(wt, { "start", "R0090" })
			t.expect(has(opened, "on branch R0090/2/c0210")).toBe(true)
			git(wt, { "fetch", "-q", "origin" })
			t.expect(git(wt, { "rev-parse", "HEAD~1" })).toBe(git(wt, { "rev-parse", "origin/main" }))
			t.expect(fs.readFile(`{state}/base-92`)).toBe("main\n")
		end
	)

	it("AC11: a raft readied without the marker keeps today's rule; ready writes layers: reviewed", function()
		local wt = w.R0070
		zn(wt, { "start", "R0070" })
		work(wt, "c0170", "old1")
		zn(wt, { "finish", "c0170" })
		-- today's rule: a finished layer opens the next, and the tool stamps nothing
		local path = `{issueDir(wt, "c0170")}/review-001.md`
		write(wt, path, "# Review\n\nVerdict: approve\n")
		zn(wt, { "commit", "-m", "tracker: review c0170" })
		t.expect(has(fs.readFile(`{wt}/{path}`), "Commit:")).toBe(false)
		zn(wt, { "start", "R0070" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0070/2/c0180")
		work(wt, "c0180", "old2")
		zn(wt, { "finish", "c0180" })
		t.expect(has(stackText(wt, "R0070"), "c0170 finished")).toBe(true)
		-- the per-landing rules name themselves in the refusal
		for _, args in { { "done", "R0070", "--through", "c0170" }, { "trace", "R0070", "--through", "c0170" } } do
			local refused = znTry(wt, args)
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "layers: reviewed")).toBe(true)
		end
		-- one trace.md and one landing, as #297 built it
		seal.trace(wt, "R0070")
		t.expect(fs.isFile(`{wt}/{zn(wt, { "find", "R0070" })}/trace.md`)).toBe(true)
		zn(wt, { "done", "R0070" })
		t.expect(
			startsWith(
				bindMessage(),
				"R0070: bind c0170, c0180\n\nVerdict: approve\nTrace: pickman/.tracker/rafts/done/R0070/trace.md\n"
			)
		).toBe(true)
	end)
end)
