--!strict
-- c0152: may a pull request merge although origin's main moved after its green CI? Yes only when
-- 1. every commit main gained since the PR's head left it is tracker state the publisher allows (publish.allowed: an
--    item's document, check.sh or spend.md under a registered root, and the id counter; until c0117's trackerstate
--    lands, then that one definition) that adds or edits only documents and spend rows and adds new items' check.sh
--    files: an edit of an EXISTING item's check.sh is not skipped (design review 001 F4, the stricter reading c0117's
--    trackerstate takes), and touches none of the files the PR changes; and
-- 2. the would-be merged tree (`git merge-tree` of the head and main's tip) passes the gate stages that read tracker
--    files (the `run` lines of z-nile/tests/merge-stages.txt in that tree, design review 002 F2), run in the merged tree as its own repository in a fresh folder
--    under $TMPDIR (decided with the user, 2026-10-25: "Run those checks first"; design review 002 F1). A merge
--    conflict, a stage missing from the merged tree, or a trial folder that can't be removed is a no.
-- Main's tip is read from the remote (`git ls-remote origin refs/heads/main`), never the local tracking ref, and must
-- be a local commit. Every failed git read is a no naming the command (F5). It writes only under $TMPDIR (the trial,
-- removed before it returns) and adds one unreferenced commit object to the checkout's object store (`commit-tree`).
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./projects")
local publish = require("./publish")

local mergecheck = {}

export type Verdict = { ok: boolean, lines: { string }, url: string, head: string }

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
-- worktree of the checkout, nothing in its cache folder): a `--shared` clone, which borrows the checkout's objects
-- read-only so the stages that read history (c0114's and c0120's finished specs) see it, with its origin removed so
-- nothing run there can reach the checkout; the folder, or nil and why
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
			{ "clone", "-q", "--shared", "--no-checkout", top, made },
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

-- the gate stages that read tracker files, on the merge of `h` and `tip`: nil when they all pass, else the reasons
local function trial(dir: string, h: string, tip: string): { string }?
	local okT, tree = git(dir, { "merge-tree", "--write-tree", h, tip })
	if not okT then
		return { "the PR and origin's main conflict: merge origin/main in" }
	end
	local treeSha = lines(tree)[1] or ""
	local okC, commit = git(dir, { "commit-tree", treeSha, "-p", h, "-p", tip, "-m", "merge-check trial" })
	if not okC then
		return { "git commit-tree failed: can't build the merged tree" }
	end
	local wt, why = checkout(dir, commit)
	if not wt then
		return { `can't build the trial checkout: {why}` }
	end
	local bad: { string } = {}
	local listFile = `{wt}/{mergecheck.STAGES_FILE}`
	local stages: { Stage } = if fs.isFile(listFile) then mergecheck.stages(fs.readFile(listFile)) else {}
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
			local ok, out = spawn("lune", { "run", "tests/run", "--", stage.spec }, home)
			if not ok then
				table.insert(bad, `the merged tree fails {stage.home}/{stage.spec}: {out}`)
			end
		end
	end
	local removed = pcall(fs.removeDir, wt)
	if not removed or fs.isDir(wt) then
		table.insert(bad, `can't remove the trial checkout {wt}: remove it by hand`)
	end
	return if #bad > 0 then bad else nil
end

-- the verdict for the PR whose green head is `head` (a commit), in the checkout at `dir`
function mergecheck.judge(dir: string, head: string): Verdict
	local _, url = git(dir, { "ls-remote", "--get-url", "origin" })
	local function no(why: { string }, h: string?): Verdict
		return { ok = false, url = url, lines = why, head = h or "" }
	end
	local okR, remote = git(dir, { "ls-remote", "origin", "refs/heads/main" })
	local tip = string.match(remote, "^(%x+)%s+refs/heads/main$")
	if not okR or not tip then
		return no({ "can't read main's tip from origin (git ls-remote origin refs/heads/main)" })
	end
	if not git(dir, { "cat-file", "-e", tip .. "^{commit}" }) then
		return no({ `origin's main {string.sub(tip, 1, 8)} is not here: git fetch origin` })
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
		return { ok = true, url = url, head = h, lines = { `origin's main has not moved past {h}` } }
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
	local okL, revs = git(dir, { "rev-list", "--reverse", `{h}..{tip}` })
	if not okL then
		return no({ "git rev-list of main's new commits failed" }, h)
	end
	local bad: { string } = {}
	local count = 0
	for _, c in lines(revs) do
		count += 1
		local _, subject = git(dir, { "log", "-1", "--format=%h %s", c })
		local okF, raw = git(
			dir,
			{ "diff-tree", "-r", "--no-commit-id", "--raw", "--no-renames", "-m", "--first-parent", c }
		)
		if not okF then
			return no({ `git diff-tree {c} failed` }, h)
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
			if not publish.allowed(p, roots) then
				table.insert(bad, `{subject}: {p} is not tracker state`)
			elseif
				string.match(p, "/check%.sh$")
				and e.status ~= "A"
				-- a move: the same item's check.sh deleted and added with the same blob and mode, as ready and done
				-- make (design review 002 F3: never paired by blob alone, which a decoy item could match)
				and not (e.status == "D" and added[`{itemOf(p)} {e.old} {e.mode}`])
			then
				table.insert(bad, `{subject}: {p} edits an existing item's check.sh`)
			elseif mine[p] then
				table.insert(bad, `{subject}: {p} is a file this PR changes`)
			end
		end
	end
	if #bad == 0 then
		local trialBad = trial(dir, h, tip)
		if trialBad then
			bad = trialBad
		end
	end
	if #bad > 0 then
		table.insert(bad, "merge origin/main in and run the gate again")
		return no(bad, h)
	end
	return {
		ok = true,
		url = url,
		head = h,
		lines = {
			`origin's main moved by {count} commit(s), all tracker state, none touching this PR's files; the merged tree passes every tracker-reading stage`,
		},
	}
end

return mergecheck
