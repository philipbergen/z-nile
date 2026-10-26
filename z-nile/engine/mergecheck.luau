--!strict
-- c0152: may a pull request merge although origin's main moved after its green CI? Yes only when
-- 1. every commit main gained since the PR's head left it is tracker state the publisher allows (publish.allowed: an
--    item's document, check.sh or spend.md under a registered root, and the id counter; until c0117's trackerstate
--    lands, then that one definition) that adds or edits only documents and spend rows and adds new items' check.sh
--    files: an edit of an EXISTING item's check.sh is not skipped (design review 001 F4, the stricter reading c0117's
--    trackerstate takes), and touches none of the files the PR changes; and
-- 2. the would-be merged tree (`git merge-tree` of the head and main's tip) passes the gate stages that read tracker
--    files, run in a throwaway detached worktree under .cache: `./zn audit` and c0120's check-paths spec (decided with
--    the user, 2026-10-25: "Run those checks first"; design review 001 F1). A merge conflict is a no.
-- Main's tip is read from the remote (`git ls-remote origin refs/heads/main`), never the local tracking ref, and must
-- be a local commit. Every failed git read is a no naming the command (F5). Writes nothing tracked: the trial worktree
-- and its git metadata are removed before it returns.
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
local function lines(text: string): { string }
	local out: { string } = {}
	for l in string.gmatch(text, "[^\n]+") do
		table.insert(out, l)
	end
	return out
end

-- the gate stages that read tracker files, on the merge of `h` and `tip`, in a throwaway worktree: nil when they pass,
-- else the reasons
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
	local okTop, top = git(dir, { "rev-parse", "--show-toplevel" })
	if not okTop then
		return { "git rev-parse --show-toplevel failed" }
	end
	local wt = `{top}/.cache/merge-check-{string.sub(commit, 1, 12)}`
	if fs.isDir(wt) then
		git(dir, { "worktree", "remove", "--force", wt })
	end
	local okW = git(dir, { "worktree", "add", "-q", "--detach", wt, commit })
	if not okW then
		return { "git worktree add failed: can't check out the merged tree" }
	end
	local bad: { string } = {}
	local audit = process.exec("bash", { `{wt}/zn`, "audit" }, { cwd = wt })
	if not audit.ok then
		table.insert(
			bad,
			`the merged tree fails ./zn audit: {(string.gsub(audit.stdout .. audit.stderr, "%s+$", ""))}`
		)
	end
	local spec = "z-nile/tests/acceptance/c0120/check-paths.spec.luau"
	if fs.isFile(`{wt}/{spec}`) then
		local cp = process.exec(
			"lune",
			{ "run", "tests/run", "--", "tests/acceptance/c0120/check-paths.spec.luau" },
			{
				cwd = `{wt}/z-nile`,
			}
		)
		if not cp.ok then
			table.insert(
				bad,
				`the merged tree fails c0120's check-paths spec: {(string.gsub(
					cp.stdout .. cp.stderr,
					"%s+$",
					""
				))}`
			)
		end
	end
	git(dir, { "worktree", "remove", "--force", wt })
	git(dir, { "worktree", "prune" })
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
		-- a check.sh is added (a new item), or moved (deleted with the same blob added in this commit, as ready and
		-- done move items); a changed or dropped one is no
		local added: { [string]: boolean } = {}
		local entries: { { status: string, path: string, old: string } } = {}
		for _, l in lines(raw) do
			local old, new, status, p = string.match(l, "^:%d+ %d+ (%x+) (%x+) (%a)%d*\t(.+)$")
			if not old or not new or not status or not p then
				table.insert(bad, `{subject}: can't read its change "{l}"`)
			else
				if status == "A" then
					added[new] = true
				end
				table.insert(entries, { status = status, path = p, old = old })
			end
		end
		for _, e in entries do
			local p = e.path
			if not publish.allowed(p, roots) then
				table.insert(bad, `{subject}: {p} is not tracker state`)
			elseif
				string.match(p, "/check%.sh$")
				and e.status ~= "A"
				and not (e.status == "D" and added[e.old])
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
			`origin's main moved by {count} commit(s), all tracker state, none touching this PR's files; the merged tree passes audit and check-paths`,
		},
	}
end

return mergecheck
