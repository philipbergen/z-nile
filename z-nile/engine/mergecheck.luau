--!strict
-- c0152: may a pull request merge although origin's main moved after its head passed Merging steps 2 and 3? Yes only when
-- 1. every commit main gained since the PR's head left it is tracker state the publisher allows (publish.allowed: an
--    item's document, check.sh or spend.md under a registered root, and the id counter; until c0117's trackerstate
--    lands, then that one definition) that adds or edits only documents and spend rows and adds new items' check.sh
--    files (or moves one: the same item's, unchanged): an edit or drop of an EXISTING item's check.sh is not skipped
--    (design review 001 F4), and touches none of the files the PR changes; and
-- 2. the would-be merged tree (`git merge-tree` of the head and main's tip) passes the gate stages that read tracker
--    files (the `run` lines of z-nile/tests/merge-stages.txt in that tree, design review 002 F2), run in that tree as
--    its own repository: a `--no-hardlinks` clone in a fresh folder under $TMPDIR that borrows nothing from the
--    checkout (design review 003 F2), its origin removed, every stage run with the checkout's git directory in
--    PICKMAN_FENCE_REAL_GIT so the nested guards still protect it (decided with the user, 2026-10-25: "Run those checks
--    first"). A merge conflict, a stage missing from the merged tree, or a trial folder that can't be removed is a no.
-- 3. main's tip is pinned (design review 003 F1): read again after the trial. When main moved meanwhile, its new commits
--    must pass rule 1 too, and unless they change only files the stage list marks `notrial` (spend rows: decided with
--    the user, 2026-10-26: "Skip re-trial for spend-only moves") the trial runs again on the new tip, at most three
--    trials in all. The verdict names the tip it judged, and the merger merges only while origin still has it.
-- Main's tip is read from the remote (`git ls-remote origin refs/heads/main`), never the local tracking ref. Every
-- failed git read is a no naming the command (F5). It writes under $TMPDIR (the trial, removed before it returns), adds
-- unreferenced objects to the checkout's object store (`commit-tree`, and an objects-only fetch of main's new tip when
-- it moved during the check), and moves no ref.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./projects")
local publish = require("./publish")

local mergecheck = {}

export type Verdict = { ok: boolean, lines: { string }, url: string, head: string, tip: string }

local function git(dir: string, args: { string }): (boolean, string)
	local r = process.exec("git", args, { cwd = dir })
	return r.ok, (string.gsub(r.stdout, "%s+$", ""))
end
-- the item id a tracker path is under (`c0002` for `z-nile/.tracker/issues/done/c0002/check.sh`), or the path
local function itemOf(p: string): string
	return string.match(p, "/([fdcR]%d%d%d%d)/[^/]+$") or p
end
local function lines(text: string): { string }
	local out: { string } = {}
	for l in string.gmatch(text, "[^\n]+") do
		table.insert(out, l)
	end
	return out
end

-- the gate stages that read tracker files, in one place (design review 002 F2): `z-nile/tests/merge-stages.txt`, read
-- from the would-be merged tree, its `run <home> <spec>` lines. Nil and why when the file is missing or lists none.
mergecheck.STAGES_FILE = "z-nile/tests/merge-stages.txt"
export type Stage = { home: string, spec: string }
function mergecheck.stages(text: string): { Stage }
	local out: { Stage } = {}
	for l in string.gmatch(text, "[^\n]+") do
		local home, spec = string.match(l, "^run%s+(%S+)%s+(%S+)")
		if home and spec then
			table.insert(out, { home = home, spec = spec })
		end
	end
	return out
end

-- the `notrial <glob>` lines of the stage list: files a move of main during the check may change without a new trial.
-- A glob is matched folder by folder: `**` is any number of whole folders, `*` any characters within one name.
function mergecheck.notrial(text: string): { string }
	local out: { string } = {}
	for l in string.gmatch(text, "[^\n]+") do
		local glob = string.match(l, "^notrial%s+(%S+)")
		if glob then
			table.insert(out, glob)
		end
	end
	return out
end
local function split(p: string): { string }
	local out: { string } = {}
	for seg in string.gmatch(p, "[^/]+") do
		table.insert(out, seg)
	end
	return out
end
local function segMatch(globSeg: string, seg: string): boolean
	local pat = string.gsub(globSeg, "[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
	pat = string.gsub(pat, "%*", "[^/]*")
	return string.match(seg, "^" .. pat .. "$") ~= nil
end
local function globMatch(g: { string }, gi: number, p: { string }, pi: number): boolean
	if gi > #g then
		return pi > #p
	end
	if g[gi] == "**" then
		for k = pi, #p + 1 do
			if globMatch(g, gi + 1, p, k) then
				return true
			end
		end
		return false
	end
	return pi <= #p and segMatch(g[gi], p[pi]) and globMatch(g, gi + 1, p, pi + 1)
end
function mergecheck.globMatch(glob: string, path: string): boolean
	return globMatch(split(glob), 1, split(path), 1)
end
local function matchesAny(p: string, globs: { string }): boolean
	for _, glob in globs do
		if mergecheck.globMatch(glob, p) then
			return true
		end
	end
	return false
end

local function spawn(
	cmd: string,
	args: { string },
	cwd: string,
	env: { [string]: string }?
): (boolean, string)
	local r = process.exec(cmd, args, { cwd = cwd, env = env })
	return r.ok, (string.gsub(r.stdout .. r.stderr, "%s+$", ""))
end

-- the merged tree `commit` as its own repository in a fresh folder under $TMPDIR (design review 002 F1: never a
-- worktree of the checkout, nothing in its cache folder): a `--no-hardlinks` clone, a full copy of the objects (the
-- stages that read history, c0114's and c0120's finished specs, see it, and the unreferenced merge commit comes with
-- them) that borrows nothing from the checkout (no alternates: design review 003 F2), its origin removed; the folder, or
-- nil and why
local function checkout(dir: string, commit: string): (string?, string?)
	local okTop, top = git(dir, { "rev-parse", "--show-toplevel" })
	if not okTop then
		return nil, "git rev-parse --show-toplevel failed"
	end
	local tmpBase = string.gsub(process.env.TMPDIR or "", "/+$", "")
	local okM, made =
		spawn("mktemp", { "-d", `{if tmpBase == "" then "/tmp" else tmpBase}/merge-check.XXXXXX` }, dir)
	if not okM then
		return nil, `mktemp failed: {made}`
	end
	for _, args in
		{
			{ "clone", "-q", "--no-hardlinks", "--no-checkout", top, made },
			{ "-C", made, "remote", "remove", "origin" },
			{ "-C", made, "checkout", "-q", "--detach", commit },
		}
	do
		local ok, out = spawn("git", args, dir)
		if not ok then
			pcall(fs.removeDir, made)
			return nil, `git {table.concat(args, " ")} failed: {out}`
		end
	end
	return made, nil
end

-- the gate stages that read tracker files, on the merge of `h` and `tip`: nil when they all pass, else the reasons;
-- and the merged tree's `notrial` patterns. `say` reports progress as it happens (the trial's folder first, so a run
-- killed midway names what it left)
local function trial(dir: string, h: string, tip: string, say: (string) -> ()): ({ string }?, { string })
	local okT, tree = git(dir, { "merge-tree", "--write-tree", h, tip })
	if not okT then
		return { "the PR and origin's main conflict: merge origin/main in" }, {}
	end
	local treeSha = lines(tree)[1] or ""
	local okC, commit = git(dir, { "commit-tree", treeSha, "-p", h, "-p", tip, "-m", "merge-check trial" })
	if not okC then
		return { "git commit-tree failed: can't build the merged tree" }, {}
	end
	local wt, why = checkout(dir, commit)
	if not wt then
		return { `can't build the trial checkout: {why}` }, {}
	end
	say(`trial of main {string.sub(tip, 1, 12)} in {wt}`)
	-- the checkout's git directory joins the nested runs' protected list, so their hooks and jail still guard it
	local okG, common = git(dir, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
	if not okG or common == "" then
		pcall(fs.removeDir, wt)
		return { "git rev-parse --git-common-dir failed" }, {}
	end
	local inherited = process.env.PICKMAN_FENCE_REAL_GIT or ""
	local env = { PICKMAN_FENCE_REAL_GIT = if inherited == "" then common else `{inherited}:{common}` }
	local bad: { string } = {}
	local listFile = `{wt}/{mergecheck.STAGES_FILE}`
	local listText = if fs.isFile(listFile) then fs.readFile(listFile) else ""
	local stages: { Stage } = mergecheck.stages(listText)
	if #stages == 0 then
		table.insert(
			bad,
			`the merged tree lists no gate stage that reads tracker files ({mergecheck.STAGES_FILE}), so no`
		)
	end
	for _, stage in stages do
		local home = `{wt}/{stage.home}`
		if not fs.isFile(`{home}/{stage.spec}`) then
			table.insert(
				bad,
				`the merged tree has no {stage.home}/{stage.spec}: a listed stage can't run, so no`
			)
		else
			local ok, out = spawn("lune", { "run", "tests/run", "--", stage.spec }, home, env)
			if not ok then
				table.insert(bad, `the merged tree fails {stage.home}/{stage.spec}: {out}`)
			end
		end
	end
	local removed = pcall(fs.removeDir, wt)
	if not removed or fs.isDir(wt) then
		table.insert(bad, `can't remove the trial checkout {wt}: remove it by hand`)
	end
	return if #bad > 0 then bad else nil, mergecheck.notrial(listText)
end

-- origin's main tip, which must be a local commit: the tip, or nil and why
local function originTip(dir: string): (string?, string?)
	local okR, remote = git(dir, { "ls-remote", "origin", "refs/heads/main" })
	local tip = string.match(remote, "^(%x+)%s+refs/heads/main$")
	if not okR or not tip then
		return nil, "can't read main's tip from origin (git ls-remote origin refs/heads/main)"
	end
	if not git(dir, { "cat-file", "-e", tip .. "^{commit}" }) then
		return nil, `origin's main {string.sub(tip, 1, 8)} is not here: git fetch origin`
	end
	return tip, nil
end

-- rule 1 over the commits `from..tip`: the reasons each is not skippable tracker state, how many there were, and every
-- path they change; nil reasons and why when a git read fails
local function judgeCommits(
	dir: string,
	from: string,
	tip: string,
	roots: { string },
	mine: { [string]: boolean }
): ({ string }?, number, { string }, string?)
	local okL, revs = git(dir, { "rev-list", "--reverse", `{from}..{tip}` })
	if not okL then
		return nil, 0, {}, "git rev-list of main's new commits failed"
	end
	local bad: { string } = {}
	local paths: { string } = {}
	local count = 0
	for _, c in lines(revs) do
		count += 1
		local _, subject = git(dir, { "log", "-1", "--format=%h %s", c })
		local okF, raw = git(
			dir,
			{ "diff-tree", "-r", "--no-commit-id", "--raw", "--no-renames", "-m", "--first-parent", c }
		)
		if not okF then
			return nil, count, paths, `git diff-tree {c} failed`
		end
		-- a check.sh is added (a new item), or moved (the same item's, deleted and added with the same blob and mode in
		-- this commit); a changed or dropped one is no
		local added: { [string]: boolean } = {} -- "<item id> <blob> <mode>" of each check.sh added
		local entries: { { status: string, path: string, old: string, mode: string } } = {}
		for _, l in lines(raw) do
			local oldMode, newMode, old, new, status, p =
				string.match(l, "^:(%d+) (%d+) (%x+) (%x+) (%a)%d*\t(.+)$")
			if not oldMode or not newMode or not old or not new or not status or not p then
				table.insert(bad, `{subject}: can't read its change "{l}"`)
			else
				if status == "A" then
					added[`{itemOf(p)} {new} {newMode}`] = true
				end
				table.insert(entries, { status = status, path = p, old = old, mode = oldMode })
			end
		end
		for _, e in entries do
			local p = e.path
			table.insert(paths, p)
			if not publish.allowed(p, roots) then
				table.insert(bad, `{subject}: {p} is not tracker state`)
			elseif
				string.match(p, "/check%.sh$")
				and e.status ~= "A"
				-- a move: the same item's check.sh deleted and added with the same blob and mode, as the publisher's
				-- moves make (design review 002 F3: never paired by blob alone, which a decoy item could match)
				and not (e.status == "D" and added[`{itemOf(p)} {e.old} {e.mode}`])
			then
				table.insert(bad, `{subject}: {p} edits an existing item's check.sh`)
			elseif mine[p] then
				table.insert(bad, `{subject}: {p} is a file this PR changes`)
			end
		end
	end
	return bad, count, paths, nil
end

mergecheck.MAX_TRIALS = 3

-- the verdict for the PR whose green head is `head` (a commit), in the checkout at `dir`; `say` reports progress as it
-- happens (the trial's folder before it runs)
function mergecheck.judge(dir: string, head: string, say: ((string) -> ())?): Verdict
	local report: (string) -> () = say or function(_line: string) end
	local _, url = git(dir, { "ls-remote", "--get-url", "origin" })
	local function no(why: { string }, h: string?): Verdict
		return { ok = false, url = url, lines = why, head = h or "", tip = "" }
	end
	local tip, whyTip = originTip(dir)
	if not tip then
		return no({ whyTip or "can't read main's tip" })
	end
	local okH, h = git(dir, { "rev-parse", "--verify", head .. "^{commit}" })
	if not okH then
		return no({ `no such commit: {head}` })
	end
	local okB, base = git(dir, { "merge-base", h, tip })
	if not okB or base == "" then
		return no({ `no merge-base between {head} and origin's main` }, h)
	end
	if base == tip then
		return {
			ok = true,
			url = url,
			head = h,
			tip = tip,
			lines = { `origin's main has not moved past {h}`, `judged main {tip}` },
		}
	end
	local reg, why = projects.at(tip, dir)
	if not reg then
		return no({ `can't read origin's main registry: {why}` }, h)
	end
	local roots = projects.roots(reg)
	local okP, prFiles = git(dir, { "diff", "--name-only", "--no-renames", base, h })
	if not okP then
		return no({ "git diff of the PR failed" }, h)
	end
	local mine: { [string]: boolean } = {}
	for _, p in lines(prFiles) do
		mine[p] = true
	end
	-- design review 004 F2: a notrial file counts only while its item's document is still in that folder in the merged
	-- tree (the PR's copy when the PR changed that folder, else main's), so a row written for a folder the PR moved away
	-- is no row of a live item and is tried
	local function liveItem(p: string, at: string): boolean
		local folder = string.match(p, "^(.*)/[^/]+$")
		local id = folder and string.match(folder, "([fdcR]%d%d%d%d)$")
		if not folder or not id then
			return false
		end
		local prChanged = false
		for q in mine do
			if string.sub(q, 1, #folder + 1) == folder .. "/" then
				prChanged = true
			end
		end
		return (git(dir, { "cat-file", "-e", `{if prChanged then h else at}:{folder}/{id}.md` }))
	end
	local bad, count, _, whyC = judgeCommits(dir, h, tip, roots, mine)
	if not bad then
		return no({ whyC or "git read failed" }, h)
	end
	if #bad > 0 then
		table.insert(bad, "merge origin/main in and run the gate again")
		return no(bad, h)
	end
	local notes: { string } = {}
	local trials = 0
	while true do
		trials += 1
		local trialBad, notrial = trial(dir, h, tip, report)
		if trialBad then
			table.insert(trialBad, "merge origin/main in and run the gate again")
			return no(trialBad, h)
		end
		-- design review 003 F1: the tip judged must still be origin's; a move meanwhile is judged in turn
		local okR, remote = git(dir, { "ls-remote", "origin", "refs/heads/main" })
		local now = string.match(remote, "^(%x+)%s+refs/heads/main$")
		if not okR or not now then
			return no({ "can't read main's tip from origin again after the trial (git ls-remote)" }, h)
		end
		if now == tip then
			break
		end
		-- its objects only: no ref moves (an empty refmap, no FETCH_HEAD)
		local fetched = process.exec(
			"git",
			{ "fetch", "-q", "--no-write-fetch-head", "--refmap=", "origin", "refs/heads/main" },
			{ cwd = dir }
		)
		local okA = git(dir, { "merge-base", "--is-ancestor", tip, now })
		if not fetched.ok or not okA then
			return no({
				`origin's main moved during the check ({string.sub(tip, 1, 8)}..{string.sub(now, 1, 8)}) and can't be judged here: git fetch origin, then run merge-check again`,
			}, h)
		end
		local moreBad, more, paths, whyM = judgeCommits(dir, tip, now, roots, mine)
		if not moreBad then
			return no({ whyM or "git read failed" }, h)
		end
		if #moreBad > 0 then
			table.insert(moreBad, "merge origin/main in and run the gate again")
			return no(moreBad, h)
		end
		count += more
		local only = true
		for _, p in paths do
			if not matchesAny(p, notrial) or not liveItem(p, now) then
				only = false
			end
		end
		tip = now
		if only then
			-- decided with the user, 2026-10-26: "Skip re-trial for spend-only moves"
			table.insert(
				notes,
				`origin's main moved during the check by {more} commit(s) changing only files the stage list marks notrial: not tried again`
			)
			break
		end
		if trials >= mergecheck.MAX_TRIALS then
			return no({
				`origin's main kept moving during the check ({trials} trials): run merge-check again`,
			}, h)
		end
		table.insert(notes, `origin's main moved during the check by {more} commit(s): the trial ran again`)
	end
	local out = {
		`origin's main moved by {count} commit(s), all tracker state, none touching this PR's files; the merged tree passes every tracker-reading stage`,
	}
	for _, n in notes do
		table.insert(out, n)
	end
	table.insert(out, `judged main {tip}`)
	return { ok = true, url = url, head = h, tip = tip, lines = out }
end

return mergecheck
