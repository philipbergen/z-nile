--!strict
-- d0383 reproduction (Task A): on the engine as it is on main, a kick from a raft's worktree prints "started", exits 0,
-- and the net's log holds the `git worktree add` failure (128). This spec PASSES on unmodified main (it documents the
-- defect) and prints what it saw. It is an experiment, not an acceptance spec: it is not promoted.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

return t.spec("d0383 reproduction", function(it)
	it(
		"a kick from a raft's worktree reports started, exits 0, and the net dies on worktree add 128",
		function()
			local f = trackerfix.new("d0383-repro", {
				["z-nile/next"] = "issue 1 fixture\nraft 1 fixture\n",
				["z-nile/check.sh"] = "#!/usr/bin/env bash\nexit 1\n",
				["z-nile/watch-passed"] = "",
			})
			local main = fixture.physical(f.main) :: string
			fixture.git(
				f.main,
				{ "worktree", "add", "-q", "-b", "watch-net", `{main}/.worktree/watch-net`, "origin/main" }
			)
			fixture.git(f.main, {
				"worktree",
				"add",
				"-q",
				"-b",
				"R9999-fixture",
				`{main}/.worktree/R9999-fixture`,
				"origin/main",
			})
			local raft = `{main}/.worktree/R9999-fixture`
			local r = trackerfix.tr(f, raft, { "watch-kick" }, { PICKMAN_WATCH_NET = "on" })
			local log = ""
			for _ = 1, 100 do
				process.exec("sleep", { "0.2" })
				if fs.isFile(`{raft}/.cache/watch-net.log`) then
					log = fs.readFile(`{raft}/.cache/watch-net.log`)
					if #log > 0 then
						break
					end
				end
			end
			print("--- kick exit code: " .. r.code)
			print("--- kick stdout: " .. r.stdout)
			print("--- kick stderr: [" .. r.stderr .. "]")
			print("--- net log (" .. raft .. "/.cache/watch-net.log):\n" .. log)
			print("--- worktrees:\n" .. fixture.git(f.main, { "worktree", "list" }))
			t.expect(r.code).toBe(0)
			t.expect(string.find(r.stdout, "watch-net: started, log at .cache/watch-net.log", 1, true) ~= nil)
				.toBe(true)
			t.expect(string.find(log, "worktree add", 1, true) ~= nil).toBe(true)
			t.expect(string.find(log, "128", 1, true) ~= nil).toBe(true)
		end
	)
end)
