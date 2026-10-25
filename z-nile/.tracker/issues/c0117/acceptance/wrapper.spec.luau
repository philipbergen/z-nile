--!strict
-- c0117 AC4: the git and gh a dispatched agent runs: a convenience layer over the boundary (the agent's credential and
-- the tripwire), still hardened. A push is decided from git's own dry run against a private fresh copy of origin's
-- main, never from parsing its arguments: every spelling, alias, `-c` setting and plumbing push that would put code on
-- main is refused. gh allows only the skills' own commands: no merge (however spelled or aliased), and `gh api` reads
-- and comments only. Pure cases on wrapper.luau, then z-nile/bin/git and gh for real in a fixture under
-- .cache/c0117-wrapper (a bare origin, a fake real gh that records its calls).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerstate = require("@znile/engine/trackerstate")
local wrapper = require("@znile/engine/wrapper")
-- c0117 runs from its project's home, z-nile/ (c0120): every path of the real tree this spec reads is the
-- repository's, from its top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- a push decided against the shared tracker-state check (trackerstate.luau), fed the paths `src` would change
local ROOTS = { "z-nile/.tracker" }
local function push(updates: { wrapper.Update }, paths: { string }?): wrapper.Decision
	return wrapper.decidePush({
		updates = updates,
		check = function(_src: string): string?
			if not paths then
				return "could not fetch a fresh copy of main"
			end
			local entries: { trackerstate.Entry } = {}
			for _, p in paths :: { string } do
				table.insert(entries, {
					oldMode = "100644",
					newMode = "100644",
					oldBlob = "a",
					newBlob = "b",
					status = "M",
					path = p,
				})
			end
			return trackerstate.judge(entries, ROOTS, true)
		end,
	})
end
local function gh(args: { string }, aliases: { [string]: { string } }?): boolean
	return wrapper.decideGh(args, aliases or {}).ok
end

local base, repo, origin, bin, log = "", "", "", "", ""
local realGit = ""
local start = ""

return t.spec("c0117 git and gh wrapper", function(it)
	it("reads git's own dry run: every ref it would update", function()
		local text = "To ../origin.git\n=\trefs/heads/x:refs/heads/x\t[up to date]\n"
			.. "*\trefs/heads/feat:refs/heads/main\t[new branch]\n-\t:refs/heads/old\t[deleted]\nDone\n"
		t.expect(wrapper.parsePorcelain(text)).toEqual({
			{ flag = "=", src = "refs/heads/x", dst = "refs/heads/x" },
			{ flag = "*", src = "refs/heads/feat", dst = "refs/heads/main" },
			{ flag = "-", src = "", dst = "refs/heads/old" },
		})
	end)

	it(
		"a push to main passes with tracker state only; code, a deletion or an unknown base is refused",
		function()
			local toMain = { { flag = " ", src = "abc", dst = "refs/heads/main" } }
			t.expect(push(toMain, { "z-nile/.tracker/issues/c0010/c0010.md", "z-nile/next" }).ok).toBe(true)
			local d = push(toMain, { "z-nile/engine/x.luau" })
			t.expect(d.ok).toBe(false)
			t.expect(has(d.why or "", "z-nile/engine/x.luau is not tracker state")).toBe(true)
			t.expect(push(toMain, { "z-nile/.tracker-x/a.md" }).ok).toBe(false)
			t.expect(push(toMain, nil).ok).toBe(false)
			t.expect(push({ { flag = "-", src = "", dst = "refs/heads/main" } }, {}).ok).toBe(false)
			-- another branch is never main's business
			t.expect(push({ { flag = "*", src = "abc", dst = "refs/heads/R0010-x" } }, { "src/a.luau" }).ok)
				.toBe(true)
		end
	)

	it("splits git's own options from its command, values included", function()
		local g, c, r = wrapper.splitGit({ "--git-dir", ".git", "-c", "a=b", "push", "origin" })
		t.expect(g).toEqual({ "--git-dir", ".git", "-c", "a=b" })
		t.expect(c).toBe("push")
		t.expect(r).toEqual({ "origin" })
		t.expect(wrapper.PLUMBING["send-pack"]).toBe(true)
	end)

	it("gh allows the skills' own commands and refuses a merge however it is spelled or aliased", function()
		t.expect(gh({ "pr", "create", "--draft" })).toBe(true)
		t.expect(gh({ "pr", "comment", "5", "--body", "x" })).toBe(true)
		t.expect(gh({ "pr", "merge", "5" })).toBe(false)
		-- gh's global options are skipped and aliases expand: an allowed command stays allowed
		t.expect(gh({ "-R", "o/r", "pr", "create" })).toBe(true)
		t.expect(gh({ "c", "--draft" }, { c = { "pr", "create" } })).toBe(true)
		t.expect(gh({ "-R", "o/r", "pr", "merge", "5" })).toBe(false)
		t.expect(gh({ "--repo=o/r", "pr", "merge", "5" })).toBe(false)
		t.expect(gh({ "m", "5" }, { m = { "pr", "merge" } })).toBe(false)
		t.expect(gh({ "x" }, { x = { "!" } })).toBe(false)
		t.expect(gh({ "alias", "set", "m", "pr merge" })).toBe(false)
		t.expect(gh({ "repo", "edit", "--default-branch", "feat" })).toBe(false)
	end)

	it("gh api reads and comments pass; every other write, GraphQL mutations included, is refused", function()
		t.expect(gh({ "api", "repos/o/r/pulls/5" })).toBe(true)
		t.expect(gh({ "api", "repos/o/r/issues/5/comments", "-f", "body=x" })).toBe(true)
		t.expect(gh({ "api", "graphql", "-f", "query={viewer{login}}" })).toBe(true)
		t.expect(gh({ "api", "graphql", "-f", "query=mutation{mergePullRequest(input:{})}" })).toBe(false)
		t.expect(gh({ "api", "-X", "PATCH", "repos/o/r/git/refs/heads/main", "-f", "sha=1" })).toBe(false)
		t.expect(gh({ "api", "-X", "PUT", "repos/o/r/contents/src/x.lua" })).toBe(false)
		t.expect(gh({ "api", "-XPUT", "repos/o/r/pulls/5/merge" })).toBe(false)
		t.expect(gh({ "api", "-X", "PATCH", "repos/o/r", "-f", "default_branch=feat" })).toBe(false)
		t.expect(gh({ "api", "--method=DELETE", "repos/o/r/issues/5/comments" })).toBe(false)
	end)

	it(
		"every gh command the skills name is allowed, but the merges, which are the dispatcher's and a human's",
		function()
			local seen = 0
			for _, root in { "z-nile/skills", "pickman/skills" } do
				for _, name in fs.readDir(`{TOP}/{root}`) do
					local path = `{TOP}/{root}/{name}/SKILL.md`
					if fs.isFile(path) then
						for cmd, sub in string.gmatch(fs.readFile(path), "`gh ([a-z]+) ([a-z%-]+)") do
							seen += 1
							if not (cmd == "pr" and sub == "merge") then
								t.expect(gh({ cmd :: string, sub :: string })).toBe(true)
							end
						end
					end
				end
			end
			t.expect(seen > 5).toBe(true)
		end
	)

	it(
		"sets up a fixture: a bare origin at a base, a branch adding code, a local main at it, a fake real gh",
		function()
			local root = fixture.physical(".") :: string
			base = `{root}/.cache/c0117-wrapper`
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			repo, origin, bin, log = `{base}/repo`, `{base}/origin.git`, `{base}/bin`, `{base}/gh.log`
			fs.writeDir(repo)
			fs.writeDir(bin)
			process.exec("git", { "init", "-q", "-b", "main", repo })
			process.exec("git", { "init", "-q", "--bare", "-b", "main", origin })
			fixture.git(repo, { "config", "user.name", "c0117-wrapper" })
			fixture.git(repo, { "config", "user.email", "c0117-wrapper@example.invalid" })
			fs.writeDir(`{repo}/z-nile/.tracker/issues/c0010`)
			fs.writeFile(
				`{repo}/z-nile/projects.toml`,
				'[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
			)
			fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "one\n")
			fixture.git(repo, { "add", "-A" })
			fixture.git(repo, { "commit", "-q", "-m", "seed" })
			fixture.git(repo, { "remote", "add", "origin", origin })
			fixture.git(repo, { "push", "-q", "origin", "main" })
			start = fixture.git(repo, { "rev-parse", "HEAD" })
			fixture.git(repo, { "checkout", "-q", "-b", "feat" })
			fs.writeFile(`{repo}/code.lua`, "return 1\n")
			fixture.git(repo, { "add", "code.lua" })
			fixture.git(repo, { "commit", "-q", "-m", "code" })
			-- a local main at the code commit, for the matching-refspec forms
			fixture.git(repo, { "branch", "-f", "main", "HEAD" })
			fs.writeFile(
				`{bin}/gh`,
				`#!/bin/sh\nif [ "$1" = alias ] && [ "$2" = list ]; then echo "m: pr merge"; exit 0; fi\necho "gh $*" >> "{log}"\n`
			)
			process.exec("chmod", { "+x", `{bin}/gh` })
			realGit = (string.gsub(process.exec("sh", { "-c", "command -v git" }).stdout, "%s+$", ""))
		end
	)

	it("z-nile/bin/git refuses every way of putting the branch's code on main", function()
		local shim = `{TOP}/z-nile/bin/git`
		local env = { ZN_REAL_GIT = realGit, ZN_P = "push" }
		local function moved(): boolean
			return fixture.git(origin, { "rev-parse", "main" }) ~= start
		end
		local forms: { { string } } = {
			{ "push", "origin", "HEAD:main" },
			{ "push", "origin", "HEAD:refs/heads/main" },
			{ "push", "--force-with-lease", "origin", "HEAD:main" },
			{ "--git-dir", ".git", "push", "origin", "HEAD:main" },
			{ "--work-tree", ".", "push", "origin", "HEAD:main" },
			{ "-c", "alias.p=push", "p", "origin", "HEAD:main" },
			{ "--config-env=alias.p=ZN_P", "p", "origin", "HEAD:main" },
			{ "push", "origin", "HEAD:heads/main" },
			{ "push", "origin", "refs/heads/feat*:refs/heads/main*" },
			{ "push", "origin", ":" },
			{ "-c", "push.default=matching", "push", "origin" },
			{ "-c", "remote.origin.push=refs/heads/feat:refs/heads/main", "push", "origin" },
			{ "send-pack", origin, "feat:main" },
			{ "pp", "origin", "HEAD:main" },
			{ "push", "--all", "origin" },
			{ "push", "--mirror", "origin" },
		}
		fixture.git(repo, { "config", "alias.pp", "push" })
		for _, form in forms do
			local r = fixture.exec(repo, shim, form, { env = env })
			if moved() then
				fixture.exec(origin, "git", { "update-ref", "refs/heads/main", start })
				error(`moved main: git {table.concat(form, " ")} ({r.code}) {r.stderr}`)
			end
			t.expect(r.ok).toBe(false)
		end
		-- a rewritten tracking ref widens nothing: the base is a fresh fetch
		fixture.exec(repo, shim, { "update-ref", "refs/remotes/origin/main", "HEAD" }, { env = env })
		t.expect(fixture.exec(repo, shim, { "push", "origin", "HEAD:main" }, { env = env }).ok).toBe(false)
		t.expect(moved()).toBe(false)
	end)

	it("z-nile/bin/git lets tracker state reach main and a branch reach its own name", function()
		local shim = `{TOP}/z-nile/bin/git`
		local env = { ZN_REAL_GIT = realGit }
		fixture.git(repo, { "checkout", "-q", "-B", "tracker", start })
		fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "two\n")
		fixture.git(repo, { "commit", "-q", "-am", "tracker" })
		t.expect(fixture.exec(repo, shim, { "push", "-q", "origin", "HEAD:main" }, { env = env }).ok)
			.toBe(true)
		t.expect(fixture.git(origin, { "show", "main:z-nile/.tracker/issues/c0010/c0010.md" })).toBe("two")
		t.expect(
			fixture.exec(repo, shim, { "push", "-q", "origin", "feat:refs/heads/R0010-x" }, { env = env }).ok
		)
			.toBe(true)
		-- a root only the working tree's registry names widens nothing: the registry is the fresh main's
		fixture.git(repo, { "checkout", "-q", "-B", "widen", "tracker" })
		fs.writeDir(`{repo}/x/.tracker`)
		fs.writeFile(`{repo}/x/.tracker/run.luau`, "return 1\n")
		fixture.git(repo, { "add", "x" })
		fixture.git(repo, { "commit", "-q", "-m", "code under a root only the working tree names" })
		fs.writeFile(
			`{repo}/z-nile/projects.toml`,
			'[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n[[project]]\nname = "x"\nroot = "x/.tracker"\n'
		)
		local widened = fixture.exec(repo, shim, { "push", "-q", "origin", "HEAD:main" }, { env = env })
		t.expect(widened.ok).toBe(false)
		t.expect(has(widened.stderr, "x/.tracker/run.luau is not tracker state")).toBe(true)
		fixture.git(repo, { "checkout", "--", "z-nile/projects.toml" })
	end)

	it(
		"z-nile/bin/gh refuses a merge and API writes before the real gh runs, and passes the skills' commands",
		function()
			local shim = `{TOP}/z-nile/bin/gh`
			local env = { ZN_REAL_GH = `{bin}/gh` }
			for _, form in
				{
					{ "pr", "merge", "5", "--squash" },
					{ "-R", "o/r", "pr", "merge", "5" },
					{ "m", "5" },
					{ "api", "-XPUT", "repos/o/r/pulls/5/merge" },
					{ "api", "graphql", "-f", "query=mutation{x}" },
				}
			do
				t.expect(fixture.exec(repo, shim, form, { env = env }).ok).toBe(false)
			end
			t.expect(fs.isFile(log)).toBe(false)
			t.expect(fixture.exec(repo, shim, { "pr", "create", "--draft" }, { env = env }).ok).toBe(true)
			t.expect(fs.readFile(log)).toBe("gh pr create --draft\n")
			-- without the dispatcher's environment the shims refuse to guess the real tool
			t.expect(fixture.exec(repo, shim, { "pr", "list" }, { env = { ZN_REAL_GH = "" } }).code).toBe(2)
			local gitShim = `{TOP}/z-nile/bin/git`
			t.expect(fixture.exec(repo, gitShim, { "status" }, { env = { ZN_REAL_GIT = "" } }).code).toBe(2)
		end
	)
end)
