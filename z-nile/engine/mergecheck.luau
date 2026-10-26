--!strict
-- c0152: may a pull request merge although origin's main moved after its green CI? Yes only when every commit main
-- gained since the PR's head left it is tracker state the publisher allows (publish.allowed: an item's document,
-- check.sh or spend.md under a registered root, and the live id counter; the one definition, never a second list) and
-- touches none of the files the PR changes. Then GitHub's squash merge is the tree CI tested plus those tracker
-- changes. Anything else (code, specs, skills, a tracker file the PR also edits) means: merge origin/main in and run
-- the gate again. Main's tip is read from the remote (`git ls-remote origin refs/heads/main`), never the local
-- tracking ref, and must be a local commit (else: fetch origin). Reads only.
local process = require("@lune/process")
local projects = require("./projects")
local publish = require("./publish")

local mergecheck = {}

export type Verdict = { ok: boolean, lines: { string }, url: string }

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

-- the verdict for the PR whose green head is `head` (a commit), in the checkout at `dir`
function mergecheck.judge(dir: string, head: string): Verdict
	local _, url = git(dir, { "ls-remote", "--get-url", "origin" })
	local okR, remote = git(dir, { "ls-remote", "origin", "refs/heads/main" })
	local tip = string.match(remote, "^(%x+)%s+refs/heads/main$")
	if not okR or not tip then
		return {
			ok = false,
			url = url,
			lines = { "can't read main's tip from origin (git ls-remote origin refs/heads/main)" },
		}
	end
	if not git(dir, { "cat-file", "-e", tip .. "^{commit}" }) then
		return {
			ok = false,
			url = url,
			lines = { `origin's main {string.sub(tip, 1, 8)} is not here: git fetch origin` },
		}
	end
	local okH, h = git(dir, { "rev-parse", "--verify", head .. "^{commit}" })
	if not okH then
		return { ok = false, url = url, lines = { `no such commit: {head}` } }
	end
	local okB, base = git(dir, { "merge-base", h, tip })
	if not okB or base == "" then
		return { ok = false, url = url, lines = { `no merge-base between {head} and origin's main` } }
	end
	if base == tip then
		return { ok = true, url = url, lines = { "origin's main has not moved past this head" } }
	end
	local reg, why = projects.at(tip, dir)
	if not reg then
		return { ok = false, url = url, lines = { `can't read origin's main registry: {why}` } }
	end
	local roots = projects.roots(reg)
	local mine: { [string]: boolean } = {}
	local _, prFiles = git(dir, { "diff", "--name-only", "--no-renames", base, h })
	for _, p in lines(prFiles) do
		mine[p] = true
	end
	local _, revs = git(dir, { "rev-list", "--reverse", `{h}..{tip}` })
	local bad: { string } = {}
	local count = 0
	for _, c in lines(revs) do
		count += 1
		local _, subject = git(dir, { "log", "-1", "--format=%h %s", c })
		local _, files = git(
			dir,
			{ "diff-tree", "-r", "--no-commit-id", "--name-only", "--no-renames", "-m", "--first-parent", c }
		)
		for _, p in lines(files) do
			if not publish.allowed(p, roots) then
				table.insert(bad, `{subject}: {p} is not tracker state`)
			elseif mine[p] then
				table.insert(bad, `{subject}: {p} is a file this PR changes`)
			end
		end
	end
	if #bad > 0 then
		table.insert(bad, "merge origin/main in and run the gate again")
		return { ok = false, url = url, lines = bad }
	end
	return {
		ok = true,
		url = url,
		lines = {
			`origin's main moved by {count} commit(s), all tracker state, none touching this PR's files`,
		},
	}
end

return mergecheck
