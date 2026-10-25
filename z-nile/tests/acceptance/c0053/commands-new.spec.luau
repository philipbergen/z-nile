--!strict
-- c0062: one part of c0510's commands spec, split so that `tests/run` runs the parts concurrently.
-- This part: publishing new issues, id allocation (also against another terminal), offline commands and stamps.
-- Driven through `scripts/tracker.sh` in a worktree, exactly as a terminal would. Cases share this part's fixture
-- and run in order.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local git = fixture.git
local f: trackerfix.Fixture = { base = "", origin = "", main = "", other = "" }
local base, origin, main, other = "", "", "", ""

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local function tr(cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, cwd, args, env)
end
local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function onOrigin(path: string): string? -- the file's text on origin's main, or nil
	local r = fixture.exec(origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
-- another terminal pushes a commit straight to origin's main
local function elsewhere(files: { [string]: string }, message: string)
	trackerfix.elsewhere(f, files, message)
end
local stub = trackerfix.stub
-- fixture hooks run with the variables git exports to a hook; they unset them so their own git calls reach the right
-- repository
local function setHook(body: string?)
	local path = `{main}/.git/hooks/pre-push`
	if body == nil then
		if fs.isFile(path) then
			fs.removeFile(path)
		end
		return
	end
	fs.writeFile(path, "#!/bin/bash\nunset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE\n" .. body)
	process.exec("chmod", { "+x", path })
end

local cap = "" -- the capture worktree
local offlineId = "" -- the issue the PICKMAN_PUBLISH=0 case creates

return t.spec("tracker commands publish state to origin/main (new)", function(it)
	it("sets up a bare origin, a main checkout and a second terminal", function()
		f = trackerfix.new("c0053-commands-new")
		base, origin, main, other = f.base, f.origin, f.main, f.other
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(git(cap, { "branch", "--show-current" })).toBe("cap-a")
	end)

	it("new issue publishes the stub to origin/main and syncs the worktree to it", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local out = trOk(
			cap,
			{ "new", "issue", "c", "alpha", "--desc", "First line of alpha.", "--project", "pickman" }
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(out).toBe("pickman/.tracker/issues/c0010/c0010.md")
		local doc = onOrigin("pickman/.tracker/issues/c0010/c0010.md")
		t.expect(has(doc, "status: new")).toBe(true)
		t.expect(has(doc, "First line of alpha.")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(onOrigin("pickman/.tracker/issues/c0010/check.sh") ~= nil).toBe(true)
		t.expect(
			string.sub(git(origin, { "ls-tree", "main", "pickman/.tracker/issues/c0010/check.sh" }), 1, 6)
		)
			.toBe("100755")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{cap}/pickman/.tracker/issues/c0010/c0010.md`)).toBe(true)
		t.expect(git(cap, { "status", "--porcelain" })).toBe("") -- tracked and clean, not an untracked stub
		t.expect(git(cap, { "rev-parse", "HEAD" })).toBe(git(origin, { "rev-parse", "main" }))
	end)

	it("a local edit of the stub merges with origin/main without an add/add conflict", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local doc = `{cap}/pickman/.tracker/issues/c0010/c0010.md`
		fs.writeFile(doc, fs.readFile(doc) .. "\nMore detail.\n")
		git(cap, { "add", "-A" })
		git(cap, { "commit", "-q", "-m", "fill c0010" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		elsewhere(
			{ ["pickman/.tracker/issues/f0100/f0100.md"] = stub("f0100", "remote-a", "new") },
			"other f0100"
		)
		trOk(cap, { "sync" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{cap}/pickman/.tracker/issues/f0100/f0100.md`)).toBe(true)
		t.expect(has(fs.readFile(doc), "More detail.")).toBe(true)
	end)

	it("ids are allocated above the highest id on origin, not only in the local tree", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		elsewhere(
			{ ["pickman/.tracker/issues/f0200/f0200.md"] = stub("f0200", "remote-b", "new") },
			"other f0200"
		)
		-- cap has not fetched f0200
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{cap}/pickman/.tracker/issues/f0200/f0200.md`)).toBe(false)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(trOk(cap, { "new", "issue", "c", "beta", "--project", "pickman" }))
			.toBe("pickman/.tracker/issues/c0210/c0210.md")
	end)

	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	it(
		"an id taken by another terminal during the push is never overwritten: the next one is used",
		function()
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			setHook(
				`marker={base}/raced\n[ -e "$marker" ] && exit 0\ntouch "$marker"\ncd {other} && git pull -q origin main && mkdir -p pickman/.tracker/issues/c0220 && printf -- '---\\nid: c0220\\ntype: chore\\ntitle: theirs\\nslug: theirs\\nraft: \\ndepends_on: []\\nstatus: new\\n---\\n' > pickman/.tracker/issues/c0220/c0220.md && git add -A && git commit -qm theirs && git push -q origin HEAD:main\n`
			)
			local out = trOk(cap, { "new", "issue", "c", "gamma", "--project", "pickman" })
			setHook(nil)
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			t.expect(out).toBe("pickman/.tracker/issues/c0230/c0230.md")
			t.expect(has(onOrigin("pickman/.tracker/issues/c0220/c0220.md"), "title: theirs")).toBe(true)
			t.expect(onOrigin("pickman/.tracker/issues/c0230/c0230.md") ~= nil).toBe(true)
		end
	)

	it("PICKMAN_PUBLISH=0 keeps a command local: ids step by 10 and nothing is pushed", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		trOk(cap, { "sync" })
		local tip = git(origin, { "rev-parse", "main" })
		local r = tr(
			cap,
			{ "new", "issue", "c", "offline", "--project", "pickman" },
			{ PICKMAN_PUBLISH = "0" }
		)
		t.expect(r.ok).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		offlineId = string.match(trim(r.stdout), "pickman/.tracker/issues/(c%d+)/") :: string
		t.expect(trim(r.stdout)).toBe(`pickman/.tracker/issues/{offlineId}/{offlineId}.md`)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tip)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{cap}/pickman/.tracker/issues/{offlineId}/{offlineId}.md`)).toBe(true)
		t.expect(git(cap, { "status", "--porcelain" })).toBe(`?? pickman/.tracker/issues/{offlineId}/`)
	end)

	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	it(
		"raft ids come from the union of the local tree and origin, and an item made ready offline can start",
		function()
			trOk(cap, { "sync" })
			-- the offline issue from the previous case; make it a local-only raft and ready it the old way
			local local1 = tr(
				cap,
				{ "new", "raft", "chore", "offline-raft", offlineId, "--single", "--project", "pickman" },
				{ PICKMAN_PUBLISH = "0" }
			)
			t.expect(local1.ok).toBe(true)
			local localRaft = string.match(trim(local1.stdout), "(R%d+)") :: string
			for _, path in
				-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
				{
					`pickman/.tracker/issues/{offlineId}/{offlineId}.md`,
					`pickman/.tracker/rafts/{localRaft}/{localRaft}.md`,
				}
			do
				fs.writeFile(
					`{cap}/{path}`,
					(fs.readFile(`{cap}/{path}`):gsub("design: draft", "design: ready"))
				)
			end
			git(cap, { "add", "-A" })
			git(cap, { "commit", "-q", "-m", "offline prep" })
			trOk(cap, { "new", "issue", "c", "theta", "--project", "pickman" })
			local theta = string.match(
				trOk(cap, { "list", "backlog" }),
				"(c%d+)%s+backlog%s+chore%s+%S*%s+Theta"
			) :: string
			local made = trOk(
				cap,
				{ "new", "raft", "chore", "published-raft", theta, "--single", "--project", "pickman" }
			)
			local made_id = tonumber(string.match(made, "R(%d+)") :: string) :: number
			local local_id = tonumber(string.sub(localRaft, 2)) :: number
			t.expect(made_id > local_id).toBe(true) -- not reusing the local-only raft's number
			-- the offline raft reaches origin through a PR, then starts: its items derive `prepared` from design: ready
			git(cap, { "push", "-q", "origin", "HEAD:main" })
			trOk(main, { "sync" })
			local wt = trOk(main, { "worktree", localRaft })
			local started = tr(wt, { "start", localRaft })
			t.expect(started.ok).toBe(true)
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			t.expect(has(onOrigin(`pickman/.tracker/rafts/{localRaft}/{localRaft}.md`), "status: active"))
				.toBe(true)
		end
	)

	it("stamps from processes started together differ, so identical moves conflict in git", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		-- three terminals stamp at the same moment: a time-based seed would give them one phrase. Each is its own
		-- fixture.exec, started with task.spawn: the calls overlap (c0062 E3), so no shell string is needed.
		local outs: { fixture.Result } = {}
		local failures: { string } = {}
		local pending = 3
		for i = 1, 3 do
			task.spawn(function()
				-- a raise inside a spawned thread would never reach the case: count it down and report it
				local ok, err = pcall(function()
					outs[i] = tr(cap, { "stamp", "new" })
				end)
				if not ok then
					table.insert(failures, tostring(err))
				end
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
		t.expect(failures).toEqual({})
		local stamps: { string } = {}
		t.expect(#outs).toBe(3)
		for _, out in outs do
			t.expect(out.ok).toBe(true)
			for line in string.gmatch(out.stdout, "[^\n]+") do
				t.expect(string.match(line, "^new%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
				table.insert(stamps, line)
			end
		end
		t.expect(#stamps).toBe(3)
		t.expect(stamps[1] == stamps[2] or stamps[1] == stamps[3] or stamps[2] == stamps[3]).toBe(false)
		-- the stubs the CLI publishes carry such stamps too
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local doc = onOrigin("pickman/.tracker/issues/c0010/c0010.md") or ""
		t.expect(string.match(doc, "\nstatus: new%-%a+%-%a+%-%a+\n") ~= nil).toBe(true)
	end)
end)
