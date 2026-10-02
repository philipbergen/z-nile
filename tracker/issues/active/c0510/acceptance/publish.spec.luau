--!strict
-- c0510: scripts/tracker/publish.luau pushes a tracker-only commit to origin/main using git plumbing:
-- it never touches the caller's working tree, index, HEAD or branch, and it retries a lost race.
local fs = require("@lune/fs")
local process = require("@lune/process")
local publish = require("@scripts/tracker/publish")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/c0510-publish`
local origin, work, other = `{base}/origin.git`, `{base}/work`, `{base}/other`

local function git(cwd: string, args: { string }): string
	local r: Result =
		process.exec("git", args, { cwd = cwd, env = { GIT_CEILING_DIRECTORIES = `{root}/.cache` } })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function identity(cwd: string)
	git(cwd, { "config", "user.name", "t" })
	git(cwd, { "config", "user.email", "t@example.invalid" })
end

local function hook(body: string?)
	local path = `{work}/.git/hooks/pre-push`
	if body == nil then
		if fs.isFile(path) then
			fs.removeFile(path)
		end
		return
	end
	fs.writeFile(path, "#!/bin/bash\nunset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE\n" .. body)
	process.exec("chmod", { "+x", path })
end

local DOC = "tracker/issues/c0010/c0010.md"
local function change(path: string, content: string): publish.Change
	return { path = path, content = content }
end

return t.spec("tracker publish (git plumbing)", function(it)
	it("sets up a bare origin and two clones", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		fs.writeDir(`{base}/seed`)
		git(`{base}/seed`, { "init", "-q", "-b", "main" })
		identity(`{base}/seed`)
		fs.writeDir(`{base}/seed/src`)
		fs.writeFile(`{base}/seed/src/x.luau`, "return 1\n")
		git(`{base}/seed`, { "add", "-A" })
		git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
		git(base, { "clone", "-q", "--bare", `{base}/seed`, origin })
		git(base, { "clone", "-q", origin, work })
		git(base, { "clone", "-q", origin, other })
		identity(work)
		identity(other)
		t.expect(git(work, { "branch", "--show-current" })).toBe("main")
	end)

	it("allows only an item's own document and check.sh, never anything else", function()
		for _, ok in
			{
				"tracker/issues/c0010/c0010.md",
				"tracker/issues/f0020/check.sh",
				"tracker/issues/active/d0030/d0030.md",
				"tracker/rafts/R0010/R0010.md",
				"tracker/rafts/done/R0140/check.sh",
			}
		do
			t.expect(publish.allowed(ok)).toBe(true)
		end
		for _, bad in
			{
				"src/x.luau",
				"tracker/architecture.md",
				"tracker/game-design.md",
				"tracker/issues/c0010/acceptance/a.spec.luau",
				"tracker/issues/c0010/spend.md",
				"tracker/issues/c0010/c0020.md",
				"tracker/issues/R0010/R0010.md",
				"tracker/rafts/c0010/c0010.md",
				"tracker/issues/active/done/c0010/c0010.md",
				"tracker/issues/../../src/x.luau",
				"/tracker/issues/c0010/c0010.md",
				"tracker/issues/c0010/c0010.md/../../../x",
				"",
			}
		do
			t.expect(publish.allowed(bad)).toBe(false)
		end
	end)

	it("a path outside the whitelist is refused and nothing is pushed", function()
		local before = git(origin, { "rev-parse", "main" })
		local r = publish.commit(work, function()
			return { change("src/x.luau", "return 2\n") }
		end, "tracker: bad")
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.reason or "", "src/x.luau", 1, true) ~= nil).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
	end)

	it(
		"pushes exactly the listed files on top of origin/main and leaves the caller's checkout alone",
		function()
			-- a local branch with its own commit and a dirty file, none of which may reach main
			git(work, { "switch", "-q", "-c", "topic" })
			fs.writeFile(`{work}/src/y.luau`, "return 3\n")
			git(work, { "add", "-A" })
			git(work, { "commit", "-q", "-m", "topic work" })
			fs.writeFile(`{work}/src/x.luau`, "return 99 -- dirty\n")
			local head, status = git(work, { "rev-parse", "HEAD" }), git(work, { "status", "--porcelain" })
			local tip = git(origin, { "rev-parse", "main" })
			local r = publish.commit(work, function()
				return { change(DOC, "---\nid: c0010\nstatus: new\n---\n") }
			end, "tracker: new c0010")
			t.expect(r.ok).toBe(true)
			t.expect(git(origin, { "rev-parse", "main" })).toBe(r.sha)
			t.expect(git(origin, { "rev-parse", "main^" })).toBe(tip)
			t.expect(git(origin, { "diff", "--name-only", tip, "main" })).toBe(DOC)
			t.expect(git(origin, { "log", "-1", "--format=%s", "main" })).toBe("tracker: new c0010")
			t.expect(git(work, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(git(work, { "branch", "--show-current" })).toBe("topic")
			t.expect(git(work, { "status", "--porcelain" })).toBe(status)
			t.expect(fs.readFile(`{work}/src/x.luau`)).toBe("return 99 -- dirty\n")
			t.expect(fs.isFile(`{work}/{DOC}`)).toBe(false)
			git(work, { "checkout", "-q", "--", "src/x.luau" })
		end
	)

	it("a new check.sh is created executable, but an existing one is never rewritten", function()
		local path = "tracker/issues/c0010/check.sh"
		local made = publish.commit(work, function()
			return { { path = path, content = "#!/bin/bash\nexit 0\n", mode = "100755" } }
		end, "tracker: stub check")
		t.expect(made.ok).toBe(true)
		t.expect(string.sub(git(origin, { "ls-tree", "main", path }), 1, 6)).toBe("100755")
		local before = git(origin, { "rev-parse", "main" })
		local again = publish.commit(work, function()
			return { { path = path, content = "#!/bin/bash\nrm -rf /\n", mode = "100755" } }
		end, "tracker: evil check")
		t.expect(again.ok).toBe(false)
		t.expect(string.find(again.reason or "", "check.sh is never rewritten", 1, true) ~= nil).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
	end)

	it("an existing document may change its status: line and nothing else", function()
		local before = git(origin, { "rev-parse", "main" })
		local body = publish.commit(work, function()
			return { change(DOC, "---\nid: c0010\nstatus: new\n---\nsneaky body\n") }
		end, "tracker: body")
		t.expect(body.ok).toBe(false)
		t.expect(string.find(body.reason or "", "status: line", 1, true) ~= nil).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		local front = publish.commit(work, function()
			return { change(DOC, "---\nid: c0010\nstatus: preparing\n---\n") }
		end, "tracker: claim")
		t.expect(front.ok).toBe(true)
		t.expect(string.find(git(origin, { "show", `main:{DOC}` }), "status: preparing", 1, true) ~= nil)
			.toBe(true)
	end)

	it(
		"only the status: line may change: other frontmatter, deleted fences and carriage returns are refused",
		function()
			local path = "tracker/issues/c0700/c0700.md"
			local doc =
				"---\nid: c0700\ntitle: Show claim status: on the board\nstatus: new-aa-bb-cc\n---\nbody\n"
			t.expect(publish.commit(work, function()
				return { change(path, doc) }
			end, "tracker: stub").ok).toBe(true)
			local before = git(origin, { "rev-parse", "main" })
			local function refused(content: string, why: string)
				local r = publish.commit(work, function()
					return { change(path, content) }
				end, "tracker: " .. why)
				t.expect(r.ok).toBe(false)
				t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
			end
			refused(string.gsub(doc, "id: c0700", "id: c0701"), "other key changed")
			refused(
				string.gsub(doc, "status: new%-aa%-bb%-cc\n", "status: new-aa-bb-cc\ndepends_on: [c0001]\n"),
				"added line"
			)
			refused("body\n", "frontmatter deleted")
			refused(string.gsub(doc, "\n", "\r\n"), "crlf")
			-- carriage returns are refused for a new document too, not only as a side effect of the status rule
			local created = publish.commit(work, function()
				return { change("tracker/issues/c0702/c0702.md", "---\r\nid: c0702\r\n---\r\n") }
			end, "tracker: crlf stub")
			t.expect(created.ok).toBe(false)
			t.expect(string.find(created.reason or "", "carriage", 1, true) ~= nil).toBe(true)
			refused(
				string.gsub(doc, "status: new%-aa%-bb%-cc\n", "status: a\nstatus: b\n"),
				"two status lines"
			)
			-- the real move touches the status line and not the title that mentions `status:`
			local moved = publish.commit(work, function()
				return {
					change(path, (string.gsub(doc, "status: new%-aa%-bb%-cc", "status: preparing-dd-ee-ff"))),
				}
			end, "tracker: claim")
			t.expect(moved.ok).toBe(true)
			local now = git(origin, { "show", `main:{path}` })
			t.expect(string.find(now, "title: Show claim status: on the board", 1, true) ~= nil).toBe(true)
			t.expect(string.find(now, "\nstatus: preparing-dd-ee-ff\n", 1, true) ~= nil).toBe(true)
		end
	)

	it("a change that is already on origin is a no-op, not an empty commit", function()
		local before = git(origin, { "rev-parse", "main" })
		local r = publish.commit(work, function()
			return { change(DOC, "---\nid: c0010\nstatus: preparing\n---\n") }
		end, "tracker: same")
		t.expect(r.ok).toBe(true)
		t.expect(r.sha).toBe(nil)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
	end)

	it("files with spaces, tabs or other odd names beside a change are kept exactly", function()
		-- odd names at every level the publisher rebuilds: the root, tracker/, tracker/issues/
		local odd = {
			"read me.txt",
			"tracker/odd\tname.md",
			"tracker/issues/na\u{ef}ve notes.md",
			"tracker/issues/x  y",
		}
		for _, p in odd do
			local dir = string.match(p, "^(.*)/[^/]+$")
			if dir then
				fs.writeDir(`{other}/{dir}`)
			end
			fs.writeFile(`{other}/{p}`, `kept: {p}\n`)
		end
		fs.writeDir(`{other}/tracker/issues`)
		fs.writeFile(`{other}/tracker/issues/run me.sh`, "#!/bin/sh\n")
		process.exec("chmod", { "+x", `{other}/tracker/issues/run me.sh` })
		git(other, { "pull", "-q", "--ff-only", "origin", "main" })
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "odd names" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		local before = git(origin, { "rev-parse", "main" })
		local made = "tracker/issues/c0401/c0401.md"
		local r = publish.commit(work, function()
			return { change(made, "---\nid: c0401\n---\n") }
		end, "tracker: beside odd names")
		t.expect(r.ok).toBe(true)
		local after = git(origin, { "rev-parse", "main" })
		-- exactly one path changed, and every other entry (name, mode, object) is byte-identical
		t.expect(git(origin, { "diff-tree", "-r", "--no-renames", "--name-only", before, after })).toBe(made)
		local function entries(rev: string): string
			local all =
				process.exec("git", { "ls-tree", "-r", "-z", "--full-tree", rev }, { cwd = origin }).stdout
			local kept: { string } = {}
			for _, rec in string.split(all, "\0") do
				if rec ~= "" and not string.find(rec, "\t" .. made, 1, true) then
					table.insert(kept, rec)
				end
			end
			return table.concat(kept, "\0")
		end
		t.expect(entries(after) == entries(before)).toBe(true)
	end)

	it("a path whose folder is a file on origin is refused, naming the whole path", function()
		git(other, { "pull", "-q", "--ff-only", "origin", "main" })
		fs.writeFile(`{other}/tracker/issues/c0402`, "a file, not a folder\n")
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "a file where a folder goes" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		local before = git(origin, { "rev-parse", "main" })
		local r = publish.commit(work, function()
			return { change("tracker/issues/c0402/c0402.md", "x\n") }
		end, "tracker: into a file")
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.reason or "", "tracker/issues/c0402 is a file", 1, true) ~= nil).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
	end)

	it("a git failure is reported with git's message and nothing is pushed", function()
		local before = git(origin, { "rev-parse", "main" })
		git(work, { "config", "user.name", "" })
		local r = publish.commit(work, function()
			return { change("tracker/issues/c0300/c0300.md", "x\n") }
		end, "tracker: no identity")
		git(work, { "config", "user.name", "t" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.reason or "", "commit-tree", 1, true) ~= nil).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		t.expect(fs.isFile(`{work}/.git/pickman-publish-index`)).toBe(false)
	end)

	it("a sibling worktree moving the shared origin/main mid-publish cannot be overwritten", function()
		-- both terminals are worktrees of one clone, so they share refs/remotes/origin/main
		local sibling = `{base}/sibling`
		git(work, { "worktree", "add", "-q", "--detach", sibling, "HEAD" })
		local calls, secondSaw = 0, false
		local r = publish.commit(work, function(paths)
			calls += 1
			if calls == 1 then
				local theirs = publish.commit(sibling, function()
					return { change("tracker/issues/c0020/c0020.md", "THEIRS\n") }
				end, "tracker: theirs")
				t.expect(theirs.ok).toBe(true)
			else
				secondSaw = table.find(paths, "tracker/issues/c0020/c0020.md") ~= nil
			end
			return { change("tracker/issues/c0020/c0020.md", "MINE\n") }
		end, "tracker: mine")
		git(work, { "worktree", "remove", "--force", sibling })
		-- the second try sees their file; since it is not frontmatter-only, writing over it is refused
		t.expect(calls).toBe(2)
		t.expect(secondSaw).toBe(true)
		t.expect(r.ok).toBe(false)
		t.expect(git(origin, { "show", "main:tracker/issues/c0020/c0020.md" })).toBe("THEIRS")
	end)

	it("the build function sees origin's current files and paths", function()
		local seen: { string } = {}
		local content: string? = nil
		local r = publish.commit(work, function(paths, read)
			seen = paths
			content = read(DOC)
			return {}
		end, "tracker: nothing")
		t.expect(r.ok).toBe(true)
		t.expect(r.sha).toBe(nil)
		t.expect(table.find(seen, DOC) ~= nil).toBe(true)
		t.expect(table.find(seen, "src/x.luau") ~= nil).toBe(false) -- only tracker item files are listed
		t.expect(content).toBe("---\nid: c0010\nstatus: preparing\n---\n")
	end)

	it("a build function that returns a string refuses with that reason and pushes nothing", function()
		local before = git(origin, { "rev-parse", "main" })
		local r = publish.commit(work, function()
			return "c0010 is preparing on origin/main"
		end, "tracker: refused")
		t.expect(r.ok).toBe(false)
		t.expect(r.reason).toBe("c0010 is preparing on origin/main")
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
	end)

	it("a lost race is retried: the build function runs again against the new origin", function()
		-- the first push is overtaken by a commit from another clone, which the hook makes
		hook(
			`marker={base}/raced\n[ -e "$marker" ] && exit 0\ntouch "$marker"\ncd {other} && git pull -q origin main && mkdir -p tracker/issues/c0040 && printf 'theirs\\n' > tracker/issues/c0040/c0040.md && git add -A && git commit -qm theirs && git push -q origin HEAD:main\n`
		)
		local calls, firstSaw = 0, false
		local r = publish.commit(work, function(paths)
			calls += 1
			if calls == 1 then
				firstSaw = table.find(paths, "tracker/issues/c0040/c0040.md") ~= nil
			end
			local id = if table.find(paths, "tracker/issues/c0040/c0040.md") then "c0050" else "c0040"
			return { change(`tracker/issues/{id}/{id}.md`, `mine {id}\n`) }
		end, "tracker: new")
		hook(nil)
		t.expect(r.ok).toBe(true)
		t.expect(calls).toBe(2)
		t.expect(firstSaw).toBe(false)
		t.expect(git(origin, { "show", "main:tracker/issues/c0040/c0040.md" })).toBe("theirs")
		t.expect(git(origin, { "show", "main:tracker/issues/c0050/c0050.md" })).toBe("mine c0050")
	end)

	it(
		"gives up after the allowed number of tries, naming the rejection, and pushes nothing of its own",
		function()
			-- every push is overtaken: the hook adds a fresh competing commit each time
			hook(
				`n=$(ls {base}/lost-* 2>/dev/null | wc -l | tr -d ' ')\ntouch {base}/lost-$n\ncd {other} && git pull -q origin main && mkdir -p tracker/issues/c010$n && printf 'x\\n' > tracker/issues/c010$n/c010$n.md && git add -A && git commit -qm race$n && git push -q origin HEAD:main\n`
			)
			local calls = 0
			local r = publish.commit(work, function()
				calls += 1
				return { change("tracker/issues/c0900/c0900.md", "mine\n") }
			end, "tracker: new", 3)
			hook(nil)
			t.expect(r.ok).toBe(false)
			t.expect(calls).toBe(3)
			t.expect(string.find(r.reason or "", "3", 1, true) ~= nil).toBe(true)
			git(work, { "fetch", "-q", "origin", "main" })
			t.expect(
				process.exec(
					"git",
					{ "cat-file", "-e", "origin/main:tracker/issues/c0900/c0900.md" },
					{ cwd = work }
				).ok
			).toBe(false)
		end
	)
end)
