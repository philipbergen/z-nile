--!strict
-- c0189 AC1: the repository's reference-transaction hook (z-nile/lib/repo-hooks/reference-transaction) refuses an
-- update of HEAD or of a ref to a commit whose author or committer email ends in @example.invalid, and nothing else.
-- Everything runs in a repository of its own under this home's .cache, through @tests/lib/fixture, with the hook copied
-- in as ./zn hooks would install it (hooks-command.spec proves that part). The real repository is only read.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- the checkout that holds the tooling (read only), and this home's .cache (the spec runs from its home)
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local home = fixture.physical(".") or error("the working directory is not readable")
local HOOK = `{root}/z-nile/lib/repo-hooks/reference-transaction`
local FENCE_HOOK = `{root}/z-nile/lib/git-hooks/reference-transaction`
local base = `{home}/.cache/c0189-repo-hook`
local repo = `{base}/repo`
local remote = `{base}/remote`
local wt = `{base}/linked`
local ZERO = string.rep("0", 40)
-- the fixture identity, and four addresses that are not it (repo-fence.spec lists them for this file)
local FX = "fixture@example.invalid"
local REAL = "real@normal.test"
local LOOKALIKES = { "x@notexample.invalid", "x@example.invalid.test", "example.invalid@normal.test" }

type Result = fixture.Result

local function git(dir: string, args: { string }, env: { [string]: string }?): Result
	return fixture.exec(dir, "git", args, { env = env })
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function who(author: string, committer: string): { [string]: string }
	return {
		GIT_AUTHOR_NAME = "a",
		GIT_AUTHOR_EMAIL = author,
		GIT_COMMITTER_NAME = "c",
		GIT_COMMITTER_EMAIL = committer,
	}
end

-- A commit of `dir`'s index and HEAD, no ref moved: the object only.
local function object(dir: string, author: string, committer: string, msg: string): string
	local tree = must(git(dir, { "write-tree" }), "write-tree")
	local head = must(git(dir, { "rev-parse", "HEAD" }), "rev-parse HEAD")
	return must(
		git(dir, { "commit-tree", tree, "-p", head, "-m", msg }, who(author, committer)),
		"commit-tree"
	)
end

local function commit(dir: string, author: string, committer: string, msg: string): Result
	return git(dir, { "commit", "-q", "--allow-empty", "-m", msg }, who(author, committer))
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function head(dir: string): string
	return must(git(dir, { "rev-parse", "HEAD" }), "rev-parse HEAD")
end

local function refExists(dir: string, ref: string): boolean
	return git(dir, { "rev-parse", "--verify", "-q", ref }).ok
end

-- The hook as git calls it, in `dir`, at `phase`, with `lines` on stdin.
local function drive(dir: string, phase: string, lines: string, env: { [string]: string }?): Result
	return fixture.exec(dir, HOOK, { phase }, { stdin = lines, env = env })
end

local gitdir = ""

return t.spec("c0189 the repository hook refuses commits under a fixture identity", function(it)
	it(
		"sets up a repository with a base commit and three old branches at it, then installs the hook",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			must(process.exec("git", { "init", "-q", "-b", "main", repo }), "init")
			must(process.exec("git", { "init", "-q", "-b", "main", remote }), "init remote")
			must(commit(repo, FX, FX, "base"), "base commit")
			-- two branches at a fixture-identity commit, as other sessions' prototype branches are today
			must(git(repo, { "branch", "legacy" }), "legacy branch")
			must(git(repo, { "branch", "gone" }), "gone branch")
			must(git(repo, { "branch", "gone2" }), "gone2 branch")
			must(git(repo, { "branch", "stays" }), "stays branch")
			must(process.exec("git", { "init", "-q", "-b", "main", `{base}/plain` }), "init plain")
			must(commit(`{base}/plain`, FX, FX, "plain base"), "plain base")
			must(git(repo, { "remote", "add", "origin", remote }), "remote add")
			gitdir = must(git(repo, { "rev-parse", "--path-format=absolute", "--git-common-dir" }), "git dir")
			-- the hook as ./zn hooks writes it: the tree's file, executable
			fs.writeFile(`{gitdir}/hooks/reference-transaction`, fs.readFile(HOOK))
			must(fixture.exec(repo, "chmod", { "755", `{gitdir}/hooks/reference-transaction` }), "chmod")
			t.expect(fs.isFile(`{gitdir}/hooks/reference-transaction`)).toBe(true)
		end
	)

	it("AC1: a commit under an ordinary identity is allowed", function()
		local before = head(repo)
		local r = commit(repo, REAL, REAL, "ordinary")
		t.expect(r.ok).toBe(true)
		t.expect(head(repo) == before).toBe(false)
	end)

	it(
		"AC1: a commit whose author is a fixture identity is refused, with the ref, the role, the address and the fix",
		function()
			local before = head(repo)
			local r = commit(repo, FX, REAL, "author")
			t.expect(r.ok).toBe(false)
			t.expect(head(repo)).toBe(before)
			t.expect(has(r.stderr, `(author {FX}): refs/heads/main`)).toBe(true)
			t.expect(has(r.stderr, "(committer")).toBe(false)
			t.expect(has(r.stderr, "scratch clone")).toBe(true)
			t.expect(has(r.stderr, "your own identity")).toBe(true)
			t.expect(has(r.stderr, "delete that branch there")).toBe(false)
		end
	)

	it("AC1: a commit whose committer alone is a fixture identity is refused", function()
		local before = head(repo)
		local r = commit(repo, REAL, FX, "committer")
		t.expect(r.ok).toBe(false)
		t.expect(head(repo)).toBe(before)
		t.expect(has(r.stderr, `(committer {FX}): refs/heads/main`)).toBe(true)
		t.expect(has(r.stderr, "(author")).toBe(false)
	end)

	it("AC1: the fixture domain is matched in any letter case, and only at the end of the address", function()
		local before = head(repo)
		local upper = commit(repo, "Mixed@EXAMPLE.Invalid", REAL, "upper")
		t.expect(upper.ok).toBe(false)
		t.expect(head(repo)).toBe(before)
		for i, address in LOOKALIKES do
			local r = commit(repo, address, address, `lookalike {i}`)
			t.expect(r.ok).toBe(true)
		end
	end)

	it(
		"AC1: update-ref, branch, tag and worktree add -b at a fixture commit are refused and leave nothing",
		function()
			local fx = object(repo, FX, FX, "unreferenced")
			local attempts: { { string } } = {
				{ "update-ref", "refs/heads/by-update-ref", fx },
				{ "branch", "by-branch", fx },
				{ "tag", "by-tag", fx },
				{ "worktree", "add", "-q", "-b", "by-worktree", `{base}/by-worktree`, fx },
			}
			for _, args in attempts do
				local r = git(repo, args, who(REAL, REAL))
				t.expect(`{args[1]} {args[2]} {r.ok}`).toBe(`{args[1]} {args[2]} false`)
				t.expect(has(r.stderr, "cannot become a ref of this repository")).toBe(true)
			end
			for _, ref in
				{
					"refs/heads/by-update-ref",
					"refs/heads/by-branch",
					"refs/tags/by-tag",
					"refs/heads/by-worktree",
				}
			do
				t.expect(`{ref} {refExists(repo, ref)}`).toBe(`{ref} false`)
			end
			t.expect(fs.isDir(`{base}/by-worktree`)).toBe(false)
			-- an annotated tag at the fixture commit: the transaction names the tag object, the message still names the ref
			local annotated = git(repo, { "tag", "-a", "-m", "m", "by-annotated", fx }, who(REAL, REAL))
			t.expect(annotated.ok).toBe(false)
			t.expect(has(annotated.stderr, "refs/tags/by-annotated")).toBe(true)
			t.expect(refExists(repo, "refs/tags/by-annotated")).toBe(false)
		end
	)

	it("AC1: a commit on a detached HEAD in a linked worktree is refused", function()
		must(git(repo, { "worktree", "add", "-q", "--detach", wt, "HEAD" }, who(REAL, REAL)), "worktree add")
		local before = head(wt)
		local r = commit(wt, FX, REAL, "detached")
		t.expect(r.ok).toBe(false)
		t.expect(head(wt)).toBe(before)
		t.expect(has(r.stderr, `(author {FX}): HEAD`)).toBe(true)
		t.expect(commit(wt, REAL, REAL, "detached ordinary").ok).toBe(true)
	end)

	it(
		"AC1: a fetch of a branch at a fixture commit is refused and says to delete it on the remote",
		function()
			must(commit(remote, REAL, REAL, "remote base"), "remote base")
			must(git(remote, { "branch", "ok" }, who(REAL, REAL)), "remote ok")
			must(git(remote, { "switch", "-q", "-c", "fx" }, who(REAL, REAL)), "remote fx")
			must(commit(remote, FX, FX, "remote fixture"), "remote fixture commit")
			must(git(remote, { "switch", "-q", "main" }, who(REAL, REAL)), "remote main")
			local r = git(repo, { "fetch", "-q", "origin" }, who(REAL, REAL))
			t.expect(r.ok).toBe(false)
			t.expect(refExists(repo, "refs/remotes/origin/fx")).toBe(false)
			t.expect(has(r.stderr, "refs/remotes/origin/fx")).toBe(true)
			t.expect(has(r.stderr, "delete that branch there")).toBe(true)
			t.expect(has(r.stderr, "git reset --merge")).toBe(false)
			must(git(remote, { "branch", "-q", "-D", "fx" }, who(REAL, REAL)), "remote delete fx")
			must(git(repo, { "fetch", "-q", "origin" }, who(REAL, REAL)), "fetch without the fixture branch")
			t.expect(refExists(repo, "refs/remotes/origin/ok")).toBe(true)
		end
	)

	it(
		"AC1: deleting a ref, a no-op update, and working on a branch that already sits at a fixture commit are allowed",
		function()
			must(git(repo, { "branch", "-q", "-D", "gone" }, who(REAL, REAL)), "delete the old branch")
			t.expect(refExists(repo, "refs/heads/gone")).toBe(false)
			-- deleting with the old value named, so the hook sees the fixture commit as the old value and zero as the new
			local oldTip = must(git(repo, { "rev-parse", "refs/heads/gone2" }), "rev-parse gone2")
			must(git(repo, { "update-ref", "-d", "refs/heads/gone2", oldTip }), "delete with the old value")
			t.expect(refExists(repo, "refs/heads/gone2")).toBe(false)
			-- a write of the value a ref already holds, old unspecified (what rebase --abort and pack-refs send), passes;
			-- the same line for a ref that does not exist yet is the refusal tested below
			local staysTip = must(git(repo, { "rev-parse", "refs/heads/stays" }), "rev-parse stays")
			t.expect(drive(repo, "prepared", `{ZERO} {staysTip} refs/heads/stays\n`).ok).toBe(true)
			t.expect(drive(repo, "prepared", `{ZERO} {staysTip} refs/heads/not-yet\n`).ok).toBe(false)
			-- the other old branch in its own worktree: stash (an update with old = new) and an ordinary commit on top of it
			local lw = `{base}/legacy-wt`
			must(git(repo, { "worktree", "add", "-q", lw, "legacy" }, who(REAL, REAL)), "worktree add legacy")
			fs.writeFile(`{lw}/work.txt`, "x\n")
			must(git(lw, { "add", "work.txt" }), "add")
			must(git(lw, { "stash", "push", "-q" }, who(REAL, REAL)), "stash on the old branch")
			-- git writes a new worktree's HEAD from the calling checkout: with the caller already at the fixture commit,
			-- the update must still be refused, and leave no folder and no worktree entry
			local listed = must(git(repo, { "worktree", "list" }), "worktree list")
			for i, args in
				{
					{ "worktree", "add", "-q", "--detach", `{base}/from-fx-1`, "legacy" },
					{
						"worktree",
						"add",
						"-q",
						"--detach",
						`{base}/from-fx-2`,
						must(git(lw, { "rev-parse", "HEAD" }), "sha"),
					},
				}
			do
				local r = git(lw, args, who(REAL, REAL))
				t.expect(`worktree add {i} {r.ok}`).toBe(`worktree add {i} false`)
				t.expect(has(r.stderr, "cannot become a ref of this repository")).toBe(true)
				t.expect(fs.isDir(`{base}/from-fx-{i}`)).toBe(false)
			end
			t.expect(must(git(repo, { "worktree", "list" }), "worktree list")).toBe(listed)
			t.expect(commit(lw, REAL, REAL, "on top of the old branch").ok).toBe(true)
			-- its tip is an ordinary commit now; another fixture-identity commit is still refused
			t.expect(commit(lw, FX, FX, "again").ok).toBe(false)
		end
	)

	it(
		"AC1: an object that is not a commit, a pseudo-ref and a symbolic update are allowed; only the prepared phase acts",
		function()
			local tree = must(git(repo, { "rev-parse", "HEAD^{tree}" }), "tree")
			local fx = object(repo, FX, FX, "for direct drive")
			t.expect(git(repo, { "update-ref", "refs/tags/tree-tag", tree }, who(REAL, REAL)).ok).toBe(true)
			t.expect(drive(repo, "prepared", `{ZERO} {fx} ORIG_HEAD\n{ZERO} {fx} CHERRY_PICK_HEAD\n`).ok)
				.toBe(true)
			t.expect(drive(repo, "prepared", `{ZERO} ref: refs/heads/main HEAD\n`).ok).toBe(true)
			t.expect(drive(repo, "prepared", `{fx} {fx} refs/heads/same\n`).ok).toBe(true)
			for _, phase in { "preparing", "committed", "aborted" } do
				t.expect(`{phase} {drive(repo, phase, `{ZERO} {fx} refs/heads/x\n`).ok}`).toBe(`{phase} true`)
			end
			-- the same line at the prepared phase is refused: the cases above are not passing for another reason
			t.expect(drive(repo, "prepared", `{ZERO} {fx} refs/heads/x\n`).ok).toBe(false)
			-- a transaction with nothing in it (a fetch with nothing new) is allowed
			t.expect(drive(repo, "prepared", "").ok).toBe(true)
		end
	)

	it("AC1: when the new commits cannot be read it refuses, naming the reason", function()
		local r = drive(repo, "prepared", `{ZERO} {string.rep("1", 40)} refs/heads/gone\n`)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "cannot read the new commits")).toBe(true)
	end)

	it(
		"AC1: a repository without the hook, and a clone of one with it, take fixture-identity commits",
		function()
			local plain = `{base}/plain`
			t.expect(commit(plain, FX, FX, "plain fixture commit").ok).toBe(true)
			local copy = `{base}/copy`
			must(process.exec("git", { "clone", "-q", repo, copy }), "clone of the hooked repository")
			t.expect(fs.isFile(`{copy}/.git/hooks/reference-transaction`)).toBe(false)
			t.expect(commit(copy, FX, FX, "fixture commit in the clone").ok).toBe(true)
		end
	)

	it(
		"AC1: a push of a prototype from a scratch clone is refused by the receiving repository; an ordinary push is allowed",
		function()
			local copy = `{base}/copy`
			-- the clone's tip is the fixture commit made above
			local refused = git(copy, { "push", "-q", "origin", "HEAD:refs/heads/from-scratch" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "cannot become a ref of this repository")).toBe(true)
			t.expect(
				has(
					refused.stderr,
					"Pushing a prototype to a repository with this hook is refused the same way."
				)
			).toBe(true)
			t.expect(refExists(repo, "refs/heads/from-scratch")).toBe(false)
			-- an ordinary commit on top of it: the new tip is ordinary, so the push (whose history holds the fixture commit) passes
			must(commit(copy, REAL, REAL, "ordinary in the clone"), "ordinary commit in the clone")
			must(git(copy, { "push", "-q", "origin", "HEAD:refs/heads/ordinary-push" }), "ordinary push")
			t.expect(refExists(repo, "refs/heads/ordinary-push")).toBe(true)
		end
	)

	it(
		"AC1: a rebase that replays an older prototype commit is refused part-way and says how to get out; a merge passes",
		function()
			local mix = `{base}/mix`
			must(process.exec("git", { "init", "-q", "-b", "main", mix }), "init mix")
			local function add(name: string)
				fs.writeFile(`{mix}/{name}`, name)
				must(git(mix, { "add", name }), "add")
			end
			add("a")
			must(commit(mix, REAL, REAL, "base"), "base")
			must(git(mix, { "switch", "-q", "-c", "proto" }), "switch")
			add("f1")
			must(commit(mix, FX, FX, "old prototype commit"), "prototype commit")
			local fxCommit = head(mix)
			add("f2")
			must(commit(mix, REAL, REAL, "ordinary on top"), "ordinary commit")
			local tip = head(mix)
			must(git(mix, { "switch", "-q", "main" }), "switch main")
			add("f3")
			must(commit(mix, REAL, REAL, "main moves on"), "main moves")
			-- a branch whose tip is itself an old prototype commit, as proto-wall-picks-base3 is today
			must(git(mix, { "switch", "-q", "-c", "tipbr", "main~1" }), "switch tipbr")
			add("f4")
			must(commit(mix, FX, FX, "old prototype tip"), "prototype tip")
			local tipbrTip = head(mix)
			must(git(mix, { "switch", "-q", "proto" }), "switch proto")
			local mixGit =
				must(git(mix, { "rev-parse", "--path-format=absolute", "--git-common-dir" }), "mix git dir")
			fs.writeFile(`{mixGit}/hooks/reference-transaction`, fs.readFile(HOOK))
			must(fixture.exec(mix, "chmod", { "755", `{mixGit}/hooks/reference-transaction` }), "chmod")
			local r = git(mix, { "rebase", "main" }, who(REAL, REAL))
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, `(author {FX}): HEAD`)).toBe(true)
			t.expect(
				has(
					r.stderr,
					"git rebase --abort (or git cherry-pick --abort), then merge instead of rebasing"
				)
			)
				.toBe(true)
			t.expect(git(mix, { "rebase", "--abort" }, who(REAL, REAL)).ok).toBe(true)
			t.expect(head(mix)).toBe(tip)
			t.expect(git(mix, { "merge", "-q", "-m", "merge main", "main" }, who(REAL, REAL)).ok).toBe(true)
			-- on a branch whose tip is the fixture commit, the rebase is refused the same way, and the abort the message
			-- names works: git sends it as a write of the value the ref already holds, with the old value unspecified
			must(git(mix, { "switch", "-q", "tipbr" }, who(REAL, REAL)), "switch tipbr")
			local stuck = git(mix, { "rebase", "main" }, who(REAL, REAL))
			t.expect(stuck.ok).toBe(false)
			t.expect(has(stuck.stderr, `(author {FX}): HEAD`)).toBe(true)
			t.expect(git(mix, { "rebase", "--abort" }, who(REAL, REAL)).ok).toBe(true)
			t.expect(head(mix)).toBe(tipbrTip)
			t.expect(must(git(mix, { "branch", "--show-current" }), "branch")).toBe("tipbr")
			t.expect(fs.isDir(`{mixGit}/rebase-merge`)).toBe(false)
			-- packing the loose refs writes every one of them with old unspecified too: the fixture-tip branch is no obstacle
			t.expect(git(mix, { "pack-refs", "--all" }).ok).toBe(true)
			t.expect(has(fs.readFile(`{mixGit}/packed-refs`), "refs/heads/tipbr")).toBe(true)
			-- an amend keeps the author: the retry the message suggests needs --reset-author
			local amend =
				git(mix, { "commit", "-q", "--allow-empty", "--amend", "-m", "amended" }, who(REAL, REAL))
			t.expect(amend.ok).toBe(false)
			t.expect(has(amend.stderr, "git commit --amend --reset-author takes over a prototype commit"))
				.toBe(true)
			t.expect(
				git(
					mix,
					{ "commit", "-q", "--allow-empty", "--amend", "--reset-author", "-m", "taken over" },
					who(REAL, REAL)
				).ok
			).toBe(true)
			-- a checkout of a prototype commit is refused after git has changed the files: the message says so and says how
			-- to put them back, and that way back keeps the person's own edit
			must(git(mix, { "switch", "-q", "proto" }, who(REAL, REAL)), "switch proto")
			fs.writeFile(`{mix}/a`, "my own edit")
			local jump = git(mix, { "checkout", "--detach", fxCommit }, who(REAL, REAL))
			t.expect(jump.ok).toBe(false)
			t.expect(
				has(
					jump.stderr,
					"git has already changed your files: git reset --merge puts them back and keeps your own edits"
				)
			).toBe(true)
			t.expect(must(git(mix, { "status", "--porcelain" }), "status") ~= "M a").toBe(true)
			t.expect(git(mix, { "reset", "-q", "--merge" }, who(REAL, REAL)).ok).toBe(true)
			t.expect(must(git(mix, { "status", "--porcelain" }), "status")).toBe("M a")
			t.expect(must(git(mix, { "branch", "--show-current" }), "branch")).toBe("proto")
		end
	)

	it(
		"AC1: the fence's own ref guard still decides first, and passes what it allows on to this hook",
		function()
			local fx = object(repo, FX, FX, "for the fence")
			local ok = head(repo)
			local env = { PICKMAN_FENCE_REAL_GIT = gitdir, PICKMAN_FENCE_SPECS = "" }
			local function fence(lines: string): Result
				return fixture.exec(repo, FENCE_HOOK, { "prepared" }, { stdin = lines, env = env })
			end
			-- a fetch-only transaction onto an ordinary tip: the fence allows it, this hook allows it
			t.expect(fence(`{ZERO} {ok} refs/remotes/origin/ok\n`).ok).toBe(true)
			-- onto a fixture tip: the fence allows it (a fetch), this hook, run through the fence's chain, refuses it
			local refused = fence(`{ZERO} {fx} refs/remotes/origin/fx\n`)
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "cannot become a ref of this repository")).toBe(true)
			-- a fetch with nothing new (an empty transaction, c0122) goes through the fence's chain to this hook and passes
			t.expect(fence("").ok).toBe(true)
			-- and the fence runs this hook only for the prepared phase it allowed: the other phases pass straight through
			for _, phase in { "preparing", "committed", "aborted" } do
				local r = fixture.exec(repo, FENCE_HOOK, { phase }, {
					stdin = `{ZERO} {fx} refs/remotes/origin/fx\n`,
					env = env,
				})
				t.expect(`{phase} {r.ok}`).toBe(`{phase} true`)
			end
			-- a branch update in the protected repository is still the fence's refusal, not this hook's
			local branch = fence(`{ZERO} {ok} refs/heads/new\n`)
			t.expect(branch.ok).toBe(false)
			t.expect(has(branch.stderr, "fence: a check tried to change refs")).toBe(true)
		end
	)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
