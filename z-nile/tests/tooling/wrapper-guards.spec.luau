--!strict
-- R0052 code review 001 (c0117), through the agent's shims for real: F3, z-nile/bin/git never rewinds main (a forced
-- push, a +refspec, --force-with-lease, a rewind with a tracker-only commit on top, a deletion); F4, z-nile/bin/gh
-- never takes an option's value for gh api's endpoint (--jq, -H), refuses an option it doesn't know, and still passes
-- a read and a comment. Fixture under .cache/c0117-wrapguards.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local wrapper = require("@znile/engine/wrapper")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local base, repo, origin, bin, log = "", "", "", "", ""
local realGit = ""
local start, moved = "", ""

return t.spec("c0117 the agent's git never rewinds main, and its gh api reads its options", function(it)
	it("sets up a bare origin whose main moved past a start, and a fake real gh", function()
		local root = fixture.physical(".") :: string
		base = `{root}/.cache/c0117-wrapguards`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		repo, origin, bin, log = `{base}/repo`, `{base}/origin.git`, `{base}/bin`, `{base}/gh.log`
		fs.writeDir(repo)
		fs.writeDir(bin)
		process.exec("git", { "init", "-q", "-b", "main", repo })
		process.exec("git", { "init", "-q", "--bare", "-b", "main", origin })
		fixture.git(repo, { "config", "user.name", "c0117-wrapguards" })
		fixture.git(repo, { "config", "user.email", "c0117-wrapguards@example.invalid" })
		fs.writeDir(`{repo}/z-nile/.tracker/issues/c0010`)
		fs.writeFile(
			`{repo}/z-nile/projects.toml`,
			'[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "one\n")
		fixture.git(repo, { "add", "-A" })
		fixture.git(repo, { "commit", "-q", "-m", "seed" })
		start = fixture.git(repo, { "rev-parse", "HEAD" })
		-- main moves on: another terminal's tracker commit
		fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "two\n")
		fixture.git(repo, { "commit", "-q", "-am", "tracker two" })
		moved = fixture.git(repo, { "rev-parse", "HEAD" })
		fixture.git(repo, { "remote", "add", "origin", origin })
		fixture.git(repo, { "push", "-q", "origin", "main" })
		fs.writeFile(
			`{bin}/gh`,
			`#!/bin/sh\nif [ "$1" = alias ] && [ "$2" = list ]; then exit 0; fi\necho "gh $*" >> "{log}"\n`
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		realGit = (string.gsub(process.exec("sh", { "-c", "command -v git" }).stdout, "%s+$", ""))
	end)

	it("z-nile/bin/git refuses every rewind of main, a tracker-only tail included (F3)", function()
		local shim = `{TOP}/z-nile/bin/git`
		local env = { ZN_REAL_GIT = realGit }
		local function originMain(): string
			return fixture.git(origin, { "rev-parse", "main" })
		end
		-- a rewind with a tracker-only commit on top
		fixture.git(repo, { "checkout", "-q", "-B", "tail", start })
		fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "three\n")
		fixture.git(repo, { "commit", "-q", "-am", "tracker three, off the old main" })
		local forms: { { string } } = {
			{ "push", "--force", "origin", `{start}:refs/heads/main` },
			{ "push", "origin", `+{start}:refs/heads/main` },
			{ "push", "--force-with-lease", "origin", `{start}:main` },
			{ "push", "-f", "origin", "tail:main" },
			{ "push", "--force", "origin", "tail:refs/heads/main" },
			{ "push", "origin", ":main" },
			{ "push", "--delete", "origin", "main" },
		}
		for _, form in forms do
			local r = fixture.exec(repo, shim, form, { env = env })
			if originMain() ~= moved then
				fixture.exec(origin, "git", { "update-ref", "refs/heads/main", moved })
				error(`rewound main: git {table.concat(form, " ")} ({r.code}) {r.stderr}`)
			end
			t.expect(r.ok).toBe(false)
		end
		-- a fast-forward of main with tracker state still passes
		fixture.git(repo, { "checkout", "-q", "-B", "forward", moved })
		fs.writeFile(`{repo}/z-nile/.tracker/issues/c0010/c0010.md`, "four\n")
		fixture.git(repo, { "commit", "-q", "-am", "tracker four" })
		local ok = fixture.exec(repo, shim, { "push", "-q", "origin", "HEAD:main" }, { env = env })
		t.expect(ok.ok).toBe(true)
	end)

	it(
		"decidePush refuses a forced update of main on its own, whatever the check says (code review 002 F4)",
		function()
			local d = wrapper.decidePush({
				updates = { { flag = "+", src = "refs/heads/feat", dst = "refs/heads/main" } },
				check = function(_src: string): string?
					return nil
				end,
			})
			t.expect(d.ok).toBe(false)
			t.expect(has(d.why or "", "a forced update")).toBe(true)
		end
	)

	it("z-nile/bin/gh never takes an option's value for gh api's endpoint (F4)", function()
		local shim = `{TOP}/z-nile/bin/gh`
		local env = { ZN_REAL_GH = `{bin}/gh` }
		if fs.isFile(log) then
			fs.removeFile(log)
		end
		for _, form in
			{
				-- the reviewer's two forms: a merge of a branch into main behind a comment endpoint
				{
					"api",
					"--jq",
					"repos/o/r/issues/1/comments",
					"-X",
					"POST",
					"repos/o/r/merges",
					"-f",
					"base=main",
					"-f",
					"head=feat",
				},
				{ "api", "-H", "repos/o/r/issues/1/comments", "--method", "POST", "repos/o/r/merges" },
				{ "api", "--jq=.x", "-XPOST", "repos/o/r/merges", "-f", "base=main" },
				{ "api", "--frobnicate", "repos/o/r/issues/1/comments", "-f", "body=x" },
				-- code review 002 F2: a GraphQL body gh reads itself, which the wrapper can't judge
				-- code review 003 F3: a query or fragment riding in the repository segment
				{ "api", "repos/o/r?/issues/1/comments", "-f", "body=x" },
				{ "api", "repos/o#/r/pulls/1/comments", "-f", "body=x" },
				{ "api", "graphql", "-F", "query=@q.graphql" },
				{ "api", "graphql", "--input", "body.json" },
				{ "api", "graphql", "-f", "query={viewer{login}}", "-F", "owner=@-" },
			}
		do
			local r = fixture.exec(repo, shim, form, { env = env })
			t.expect(r.ok).toBe(false)
		end
		t.expect(fs.isFile(log)).toBe(false) -- refused before the real gh ran
		-- a read with a jq filter, and a comment, still pass
		t.expect(fixture.exec(repo, shim, { "api", "--jq", ".title", "repos/o/r/pulls/1" }, { env = env }).ok)
			.toBe(true)
		t.expect(
			fixture.exec(repo, shim, { "api", "-X", "POST", "repos/o/r/issues/1/comments", "-f", "body=x" }, {
				env = env,
			}).ok
		)
			.toBe(true)
		-- gh's own placeholders still name a comment endpoint
		t.expect(
			fixture.exec(
				repo,
				shim,
				{ "api", "repos/{owner}/{repo}/issues/1/comments", "-f", "body=x" },
				{ env = env }
			).ok
		).toBe(true)
		-- an inline GraphQL read still passes
		t.expect(
			fixture.exec(repo, shim, { "api", "graphql", "-f", "query={viewer{login}}" }, { env = env }).ok
		)
			.toBe(true)
		t.expect(has(fs.readFile(log), "gh api --jq .title repos/o/r/pulls/1")).toBe(true)
	end)
end)
