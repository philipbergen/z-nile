--!strict
-- c0260 AC10: which issues must carry a capture record is read from the landing in git's history (the commit that adds
-- capturecheck.luau and whether the commit that added an issue's document descends from it), never from a date or a
-- commit time. capturecut over an injected git runner, and once over a real fixture repository whose commit dates run
-- backwards (a squash merge rewrites dates). Fixture under .cache/c0260-cut.
local capturecut = require("@znile/engine/capturecut")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0260-cut`

-- A runner that answers by the first words of the git command.
type Answer = { ok: boolean, out: string }
local function runner(answers: { [string]: Answer }): capturecut.Run
	return function(args: { string }): (boolean, string)
		local key = table.concat(args, " ")
		for pattern, answer in answers do
			if string.find(key, pattern, 1, true) then
				return answer.ok, answer.out
			end
		end
		return false, ""
	end
end
local FULL = { ["is-shallow"] = { ok = true, out = "false\n" } }
local function with(extra: { [string]: Answer }): { [string]: Answer }
	local out = table.clone(FULL)
	for k, v in extra do
		out[k] = v
	end
	return out
end

local function git(cwd: string, args: { string }, date: string?): string
	local r = process.exec("git", args, {
		cwd = cwd,
		env = {
			GIT_AUTHOR_NAME = "t",
			GIT_AUTHOR_EMAIL = "t@example.invalid",
			GIT_COMMITTER_NAME = "t",
			GIT_COMMITTER_EMAIL = "t@example.invalid",
			GIT_AUTHOR_DATE = date or "2026-01-01T00:00:00Z",
			GIT_COMMITTER_DATE = date or "2026-01-01T00:00:00Z",
		},
	})
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
	return r.stdout
end
local function commit(dir: string, rel: string, text: string, date: string)
	fs.writeDir(string.match(`{dir}/{rel}`, "^(.*)/[^/]+$") :: string)
	fs.writeFile(`{dir}/{rel}`, text)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-q", "-m", `add {rel}` }, date)
end

return t.spec("c0260 the cut-over is read from the landing", function(it)
	it("AC10: an unreadable history is unknown, a history without the module is older", function()
		local shallow = runner({ ["is-shallow"] = { ok = true, out = "true\n" } })
		t.expect(capturecut.of(shallow, "origin/main", "c0900", "x/c0900.md")).toBe("unknown")
		local broken = runner({})
		t.expect(capturecut.of(broken, "origin/main", "c0900", "x/c0900.md")).toBe("unknown")
		local noModule = runner(with({
			["--diff-filter=A --format=%H --reverse origin/main -- z-nile/.tracker/capture-since"] = {
				ok = true,
				out = "",
			},
		}))
		t.expect(capturecut.of(noModule, "origin/main", "c0900", "x/c0900.md")).toBe("older")
		local noDoc = runner(with({
			["capture-since"] = { ok = true, out = "aaaa\n" },
			["c0900/c0900.md"] = { ok = true, out = "" },
		}))
		t.expect(capturecut.of(noDoc, "origin/main", "c0900", "x/c0900.md")).toBe("unknown")
	end)

	it("AC10: a shallow clone is unknown even when every other answer would say after", function()
		local shallowButFull = runner({
			["is-shallow"] = { ok = true, out = "true\n" },
			["capture-since"] = { ok = true, out = "aaaa\n" },
			["c0900/c0900.md"] = { ok = true, out = "bbbb\n" },
			["--is-ancestor aaaa bbbb"] = { ok = true, out = "" },
		})
		t.expect(capturecut.of(shallowButFull, "origin/main", "c0900", "x/c0900.md")).toBe("unknown")
	end)

	it(
		"AC10: an issue whose document descends from the landing is after, one the landing descends from is older",
		function()
			local after = runner(with({
				["capture-since"] = { ok = true, out = "aaaa\n" },
				["c0900/c0900.md"] = { ok = true, out = "bbbb\n" },
				["--is-ancestor aaaa bbbb"] = { ok = true, out = "" },
			}))
			t.expect(capturecut.of(after, "origin/main", "c0900", "x/c0900.md")).toBe("after")
			local older = runner(with({
				["capture-since"] = { ok = true, out = "aaaa\n" },
				["c0900/c0900.md"] = { ok = true, out = "bbbb\n" },
				["--is-ancestor aaaa bbbb"] = { ok = false, out = "" },
				["--is-ancestor bbbb aaaa"] = { ok = true, out = "" },
			}))
			t.expect(capturecut.of(older, "origin/main", "c0900", "x/c0900.md")).toBe("older")
			local unrelated = runner(with({
				["capture-since"] = { ok = true, out = "aaaa\n" },
				["c0900/c0900.md"] = { ok = true, out = "bbbb\n" },
			}))
			t.expect(capturecut.of(unrelated, "origin/main", "c0900", "x/c0900.md")).toBe("unknown")
		end
	)

	it(
		"AC10: on a real repository whose dates run backwards, the order of the commits decides, not their times",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			git(base, { "init", "-q", "-b", "main" })
			-- the old issue is committed with the LATEST date, the new one with the EARLIEST: a calendar date would say the reverse
			commit(base, "z-nile/.tracker/issues/c0100/c0100.md", "old\n", "2026-12-31T00:00:00Z")
			commit(base, capturecut.MARKER, "the capture record is in force from this commit\n", "2026-06-01T00:00:00Z")
			commit(base, "z-nile/.tracker/issues/c0200/c0200.md", "new\n", "2026-01-01T00:00:00Z")
			local run: capturecut.Run = function(args: { string }): (boolean, string)
				local r = process.exec("git", args, { cwd = base })
				return r.ok, r.stdout
			end
			t.expect(capturecut.of(run, "HEAD", "c0100", "z-nile/.tracker/issues/c0100/c0100.md")).toBe("older")
			t.expect(capturecut.of(run, "HEAD", "c0200", "z-nile/.tracker/issues/c0200/c0200.md")).toBe("after")
			-- the document moved folders (backlog to active): its first add still decides
			git(base, { "mv", "z-nile/.tracker/issues/c0200", "z-nile/.tracker/issues/active-c0200" })
			git(base, { "commit", "-q", "-m", "move" })
			t.expect(capturecut.of(run, "HEAD", "c0200", "z-nile/.tracker/issues/active-c0200/c0200.md")).toBe("after")
			fs.removeDir(base)
		end
	)
end)
