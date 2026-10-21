--!strict
-- c0117 AC7: the git and gh a dispatched agent runs. A push that would put anything but tracker state on main is
-- refused, and so are --all, --mirror and deleting main; gh pr merge needs the dispatcher's authorisation and never
-- takes --admin; gh api writes to merge, protection and ruleset endpoints are refused. Pure cases on wrapper.luau,
-- then z-nile/bin/git and gh for real in a fixture under .cache/c0117-wrapper (a fake real gh records its calls).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local wrapper = require("@znile/engine/wrapper")

local function ctx(over: { [string]: any }?): wrapper.Ctx
	local c: { [string]: any } = {
		branch = "R0010-thing",
		upstream = "R0010-thing",
		changed = function(_src: string, _remote: string): { string }
			return { "z-nile/.tracker/issues/c0010/c0010.md" }
		end,
		allowed = { "z-nile/next", "z-nile/.tracker/", "pickman/.tracker/" },
		authorised = function(pr: string): boolean
			return pr == "12"
		end,
	}
	local more_over: { [string]: any } = over or {}
	for k, v in more_over do
		c[k] = v
	end
	return c :: any
end
local function code(paths: { string }): (string, string) -> { string }
	return function(_src: string, _remote: string): { string }
		return paths
	end
end
local function ok(d: wrapper.Decision): boolean
	return d.ok
end
local function why(d: wrapper.Decision): string
	return d.why or ""
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local base = ""
local repo, origin, bin, log = "", "", "", ""

return t.spec("c0117 git and gh wrapper", function(it)
	it("a push of tracker state to main passes; any other path is refused", function()
		t.expect(ok(wrapper.decideGit({ "push", "origin", "abc:refs/heads/main" }, ctx()))).toBe(true)
		t.expect(
			ok(
				wrapper.decideGit(
					{ "push", "-q", "--force-with-lease=refs/heads/main:x", "origin", "abc:refs/heads/main" },
					ctx()
				)
			)
		).toBe(true)
		t.expect(
			ok(
				wrapper.decideGit(
					{ "push", "origin", "abc:refs/heads/main" },
					ctx({ changed = code({ "z-nile/next" }) })
				)
			)
		)
			.toBe(true)
		local d =
			wrapper.decideGit({ "push", "origin", "HEAD:main" }, ctx({ changed = code({ "z-nile/engine/main.luau" }) }))
		t.expect(ok(d)).toBe(false)
		t.expect(has(why(d), "z-nile/engine/main.luau is not tracker state")).toBe(true)
		-- a root's name as a prefix of another folder is not that root
		t.expect(
			ok(
				wrapper.decideGit(
					{ "push", "origin", "HEAD:main" },
					ctx({ changed = code({ "z-nile/.tracker-x/a.md" }) })
				)
			)
		).toBe(false)
		t.expect(ok(wrapper.decideGit({ "push", "origin", "+HEAD:main" }, ctx({ changed = code({ "src/a.luau" }) }))))
			.toBe(false)
	end)

	it("finds main as the destination however the push names it", function()
		local bad = ctx({ changed = code({ "src/a.luau" }) })
		t.expect(ok(wrapper.decideGit({ "push", "origin", "main" }, bad))).toBe(false)
		t.expect(ok(wrapper.decideGit({ "-C", "x", "push", "origin", "refs/heads/main" }, bad))).toBe(false)
		t.expect(
			ok(
				wrapper.decideGit(
					{ "push" },
					ctx({ branch = "main", upstream = "main", changed = code({ "src/a.luau" }) })
				)
			)
		).toBe(false)
		t.expect(
			ok(
				wrapper.decideGit(
					{ "push", "origin", "HEAD" },
					ctx({ branch = "main", changed = code({ "src/a.luau" }) })
				)
			)
		).toBe(false)
		-- the step's own branch is never main
		t.expect(ok(wrapper.decideGit({ "push", "-u", "origin", "R0010-thing" }, bad))).toBe(true)
		t.expect(ok(wrapper.decideGit({ "push" }, bad))).toBe(true)
		t.expect(ok(wrapper.decideGit({ "status" }, bad))).toBe(true)
	end)

	it("refuses --all, --mirror and deleting main", function()
		for _, args in
			{
				{ "push", "--all" },
				{ "push", "--mirror", "origin" },
				{ "push", "origin", ":main" },
				{ "push", "-d", "origin", "main" },
			}
		do
			t.expect(ok(wrapper.decideGit(args, ctx()))).toBe(false)
		end
		t.expect(ok(wrapper.decideGit({ "push", "-d", "origin", "old-branch" }, ctx()))).toBe(true)
	end)

	it("gh pr merge needs the dispatcher's authorisation for that number, and never --admin", function()
		t.expect(ok(wrapper.decideGh({ "pr", "merge", "12", "--squash" }, ctx()))).toBe(true)
		t.expect(has(why(wrapper.decideGh({ "pr", "merge", "13", "--squash" }, ctx())), "did not authorise")).toBe(true)
		t.expect(has(why(wrapper.decideGh({ "pr", "merge", "12", "--admin" }, ctx())), "--admin")).toBe(true)
		t.expect(ok(wrapper.decideGh({ "pr", "merge", "--squash" }, ctx()))).toBe(false)
		t.expect(ok(wrapper.decideGh({ "pr", "view", "13" }, ctx()))).toBe(true)
	end)

	it("gh api writes to merge, protection and ruleset endpoints are refused; reads pass", function()
		t.expect(ok(wrapper.decideGh({ "api", "-X", "PUT", "repos/o/r/pulls/13/merge" }, ctx()))).toBe(false)
		t.expect(ok(wrapper.decideGh({ "api", "repos/o/r/branches/main/protection", "-f", "x=1" }, ctx()))).toBe(false)
		t.expect(ok(wrapper.decideGh({ "api", "--method=POST", "repos/o/r/rulesets" }, ctx()))).toBe(false)
		t.expect(ok(wrapper.decideGh({ "api", "repos/o/r/branches/main/protection" }, ctx()))).toBe(true)
		t.expect(ok(wrapper.decideGh({ "api", "-X", "POST", "repos/o/r/issues/1/comments" }, ctx()))).toBe(true)
	end)

	it("sets up a fixture repository with a bare origin and a fake real gh", function()
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
		fs.writeFile(`{repo}/z-nile/projects.toml`, '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n')
		fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "one\n")
		fixture.git(repo, { "add", "-A" })
		fixture.git(repo, { "commit", "-q", "-m", "seed" })
		fixture.git(repo, { "remote", "add", "origin", origin })
		fixture.git(repo, { "push", "-q", "origin", "main" })
		fs.writeFile(`{bin}/gh`, `#!/bin/sh\necho "gh $*" >> "{log}"\n`)
		process.exec("chmod", { "+x", `{bin}/gh` })
	end)

	it("z-nile/bin/git pushes a tracker-only commit to main and refuses one that adds code", function()
		local real = process.exec("sh", { "-c", "command -v git" })
		local env = { ZN_REAL_GIT = string.gsub(real.stdout, "%s+$", "") }
		local shim = `{fixture.physical(".")}/z-nile/bin/git`
		fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "two\n")
		fixture.git(repo, { "commit", "-q", "-am", "tracker" })
		local pushed = fixture.exec(repo, shim, { "push", "-q", "origin", "HEAD:main" }, { env = env })
		t.expect(pushed.ok).toBe(true)
		t.expect(fixture.git(origin, { "show", "main:z-nile/.tracker/issues/c0010/c0010.md" })).toBe("two")
		fs.writeDir(`{repo}/z-nile/engine`)
		fs.writeFile(`{repo}/z-nile/engine/x.luau`, "return 1\n")
		fixture.git(repo, { "add", "-A" })
		fixture.git(repo, { "commit", "-q", "-m", "code" })
		local refused = fixture.exec(repo, shim, { "push", "-q", "origin", "HEAD:main" }, { env = env })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "z-nile/engine/x.luau is not tracker state")).toBe(true)
		t.expect(fixture.exec(origin, "git", { "cat-file", "-e", "main:z-nile/engine/x.luau" }).ok).toBe(false)
		-- a root added in the working tree's registry widens nothing: the allow-list is origin/main's
		fixture.git(repo, { "reset", "-q", "--hard", "HEAD~1" })
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
		-- a branch of its own goes through
		t.expect(fixture.exec(repo, shim, { "push", "-q", "origin", "HEAD:refs/heads/R0010-x" }, { env = env }).ok)
			.toBe(true)
	end)

	it("z-nile/bin/gh merges only an authorised PR, and refuses --admin before the real gh runs", function()
		local home = `{base}/dispatch`
		local env = { ZN_REAL_GH = `{bin}/gh`, ZN_DISPATCH_HOME = home }
		local shim = `{fixture.physical(".")}/z-nile/bin/gh`
		local no = fixture.exec(repo, shim, { "pr", "merge", "5", "--squash" }, { env = env })
		t.expect(no.ok).toBe(false)
		t.expect(fs.isFile(log)).toBe(false)
		fs.writeDir(`{home}/authorised`)
		fs.writeFile(`{home}/authorised/5`, "x\n")
		t.expect(fixture.exec(repo, shim, { "pr", "merge", "5", "--squash" }, { env = env }).ok).toBe(true)
		t.expect(fs.readFile(log)).toBe("gh pr merge 5 --squash\n")
		t.expect(fixture.exec(repo, shim, { "pr", "merge", "5", "--admin" }, { env = env }).ok).toBe(false)
		t.expect(fixture.exec(repo, shim, { "pr", "list" }, { env = env }).ok).toBe(true)
		t.expect(fs.readFile(log)).toBe("gh pr merge 5 --squash\ngh pr list\n")
		-- without the dispatcher's environment the shim refuses to guess the real tool
		t.expect(fixture.exec(repo, shim, { "pr", "list" }, { env = { ZN_REAL_GH = "" } }).code).toBe(2)
	end)
end)
