--!strict
-- c0152 AC1: `./zn merge-check <head>` says whether a PR whose CI went green at <head> may merge although origin's main
-- moved since: exit 0 only when every commit main gained is tracker state the publisher allows that edits no existing
-- item's check.sh and touches none of the PR's files (merge commits judged by their first-parent diff), and the
-- would-be merged tree passes `./zn audit` and c0120's check-paths spec (decided with the user, 2026-10-25: "Run those
-- checks first"); otherwise exit 1, naming each commit and path or the failing check. Main's tip comes from the remote
-- (ls-remote), never the local tracking ref, and must be fetched. The ok output names the head to pass to
-- `gh pr merge --match-head-commit`. Fixture under .cache/c0152-merge-check (tests/lib/trackerfix), with z-nile's test
-- harness pushed to its main so the trial can run check-paths.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local DOC1 = "z-nile/.tracker/issues/c0001/c0001.md"
local DOC2 = "z-nile/.tracker/issues/c0002/c0002.md"
local OLD_SPEC = "z-nile/tests/tooling/c0152-old.spec.luau"
local f: trackerfix.Fixture
local head = ""
local baseline = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function check(): fixture.Result
	return trackerfix.tr(f, f.main, { "merge-check", head })
end
local function fetch()
	fixture.git(f.main, { "fetch", "-q", "origin" })
end
local function originMain(): string
	fixture.git(f.other, { "fetch", "-q", "origin" })
	return (string.gsub(fixture.git(f.other, { "rev-parse", "origin/main" }), "%s+$", ""))
end
-- origin's main back to the baseline (a fixture's own bare origin; never the real one)
local function reset()
	fixture.git(f.other, { "push", "-q", "-f", "origin", `{baseline}:refs/heads/main` })
	fixture.git(f.other, { "fetch", "-q", "origin" })
	fixture.git(f.other, { "reset", "-q", "--hard", baseline })
	fetch()
end
local function expectNo(needle: string)
	fetch()
	local r = check()
	t.expect(r.code).toBe(1)
	t.expect(has(r.stdout, needle)).toBe(true)
	t.expect(has(r.stdout, "merge origin/main in")).toBe(true)
	reset()
end

return t.spec(
	"c0152 a PR may merge past main's tracker-only commits only when the merged tree passes",
	function(it)
		it("sets up a PR branch; main hasn't moved: ok, naming the head to merge", function()
			f = trackerfix.new("c0152-merge-check", {
				["z-nile/projects.toml"] = REGISTRY,
				[DOC1] = trackerfix.stub("c0001", "one", "new-a-b-c"),
				[DOC2] = trackerfix.stub("c0002", "two", "new-a-b-c"),
				["z-nile/.tracker/issues/c0002/check.sh"] = "#!/usr/bin/env bash\ntrue\n",
				["pickman/.tracker/issues/.gitkeep"] = "",
				["z-nile/next"] = "issue 20 a-b-c\nraft 2 a-b-c\n",
			})
			-- the harness, so the trial merge can run c0120's check-paths spec, plus a spec the PR will delete
			local top = (
				string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
			)
			fixture.git(f.other, { "pull", "-q", "origin", "main" })
			t.expect(process.exec("cp", { "-R", `{top}/z-nile/tests`, `{f.other}/z-nile/tests` }).ok)
				.toBe(true)
			fs.writeFile(`{f.other}/{OLD_SPEC}`, "return nil\n")
			fixture.git(f.other, { "add", "-A" })
			fixture.git(f.other, { "commit", "-qm", "the harness" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			-- the PR: code, c0001's document, and the deletion of a spec
			fixture.git(f.main, { "checkout", "-q", "-b", "pr" })
			fs.writeDir(`{f.main}/z-nile/engine`)
			fs.writeFile(`{f.main}/z-nile/engine/c0152-demo.luau`, "return nil\n")
			fs.writeFile(`{f.main}/{DOC1}`, trackerfix.stub("c0001", "one, edited by the PR", "new-a-b-c"))
			fs.removeFile(`{f.main}/{OLD_SPEC}`)
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-qm", "the PR" })
			head = (string.gsub(fixture.git(f.main, { "rev-parse", "HEAD" }), "%s+$", ""))
			baseline = originMain()
			local r = check()
			t.expect(r.code).toBe(0)
			t.expect(has(r.stdout, "has not moved")).toBe(true)
			t.expect(has(r.stdout, `--match-head-commit {head}`)).toBe(true)
		end)

		it("a commit on origin's main that isn't fetched here refuses: fetch first", function()
			trackerfix.elsewhere(
				f,
				{ ["z-nile/.tracker/issues/c0002/spend.md"] = "| a spend row |\n" },
				"tracker: spend c0002"
			)
			local r = check()
			t.expect(r.code).toBe(1)
			t.expect(has(r.stdout, "git fetch origin")).toBe(true)
			reset()
		end)

		it(
			"tracker state the PR doesn't touch passes, and the merged tree passes audit and check-paths",
			function()
				trackerfix.elsewhere(
					f,
					{ ["z-nile/.tracker/issues/c0002/spend.md"] = "| a spend row |\n" },
					"tracker: spend c0002"
				)
				trackerfix.elsewhere(
					f,
					{ [DOC2] = trackerfix.stub("c0002", "two", "preparing-a-b-c") },
					"tracker: c0002 preparing"
				)
				trackerfix.elsewhere(f, {
					["z-nile/.tracker/issues/c0003/c0003.md"] = trackerfix.stub(
						"c0003",
						"three",
						"new-a-b-c"
					),
					["z-nile/.tracker/issues/c0003/check.sh"] = "#!/usr/bin/env bash\ntrue\n",
				}, "tracker: new c0003")
				fetch()
				local r = check()
				t.expect(r.code).toBe(0)
				t.expect(has(r.stdout, "moved by 3 commit(s), all tracker state")).toBe(true)
				t.expect(has(r.stdout, "passes audit and check-paths")).toBe(true)
				t.expect(has(r.stdout, `--match-head-commit {head}`)).toBe(true)
				reset()
			end
		)

		it(
			"a move of an item to done/ (its check.sh with it, as done and ready move items) is tracker state too",
			function()
				fixture.git(f.other, { "pull", "-q", "origin", "main" })
				fs.writeDir(`{f.other}/z-nile/.tracker/issues/done`)
				fixture.git(
					f.other,
					{ "mv", "z-nile/.tracker/issues/c0002", "z-nile/.tracker/issues/done/c0002" }
				)
				fixture.git(f.other, { "commit", "-qm", "tracker: done c0002" })
				fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
				fetch()
				local r = check()
				t.expect(r.code).toBe(0)
				t.expect(has(r.stdout, "moved by 1 commit(s), all tracker state")).toBe(true)
				reset()
			end
		)

		it(
			"a document the PR changes, a sequestered spec, code, or an existing check.sh edited: each a no",
			function()
				trackerfix.elsewhere(
					f,
					{ [DOC1] = trackerfix.stub("c0001", "one", "preparing-a-b-c") },
					"tracker: c0001 preparing"
				)
				expectNo(`{DOC1} is a file this PR changes`)
				trackerfix.elsewhere(
					f,
					{ ["z-nile/.tracker/issues/c0002/acceptance/x.spec.luau"] = "return nil\n" },
					"a spec"
				)
				expectNo("z-nile/.tracker/issues/c0002/acceptance/x.spec.luau is not tracker state")
				trackerfix.elsewhere(f, { ["z-nile/engine/other.luau"] = "return nil\n" }, "code on main")
				expectNo("z-nile/engine/other.luau is not tracker state")
				trackerfix.elsewhere(
					f,
					{ ["z-nile/.tracker/issues/c0002/check.sh"] = "#!/usr/bin/env bash\nfalse\n" },
					"edit"
				)
				expectNo("z-nile/.tracker/issues/c0002/check.sh edits an existing item's check.sh")
			end
		)

		it("a merge commit on main is judged by its own change (first parent)", function()
			fixture.git(f.other, { "checkout", "-q", "-b", "side" })
			fs.writeFile(`{f.other}/z-nile/.tracker/issues/c0002/spend.md`, "| side row |\n")
			fixture.git(f.other, { "add", "-A" })
			fixture.git(f.other, { "commit", "-qm", "tracker: side" })
			fixture.git(f.other, { "checkout", "-q", "main" })
			fixture.git(f.other, { "merge", "-q", "--no-ff", "--no-commit", "side" })
			fs.writeFile(`{f.other}/z-nile/engine/evil.luau`, "return nil\n")
			fixture.git(f.other, { "add", "-A" })
			fixture.git(f.other, { "commit", "-qm", "merge side, with code" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(f.other, { "branch", "-q", "-D", "side" })
			expectNo("z-nile/engine/evil.luau is not tracker state")
		end)

		it(
			"the merged tree is judged: a new item's check.sh naming a file the PR deletes, a bad document",
			function()
				trackerfix.elsewhere(f, {
					["z-nile/.tracker/issues/c0009/c0009.md"] = trackerfix.stub("c0009", "nine", "new-a-b-c"),
					["z-nile/.tracker/issues/c0009/check.sh"] = '#!/usr/bin/env bash\ncheck "AC1" lune run tests/run -- tests/tooling/c0152-old.spec.luau\n',
				}, "tracker: new c0009")
				expectNo("the merged tree fails c0120's check-paths spec")
				trackerfix.elsewhere(
					f,
					{ ["z-nile/.tracker/issues/c0010/c0010.md"] = "not a document\n" },
					"tracker: c0010"
				)
				expectNo("the merged tree fails ./zn audit")
			end
		)

		it("the local tracking ref is never the judge, and the trial leaves nothing behind", function()
			trackerfix.elsewhere(f, { ["z-nile/engine/other.luau"] = "return nil\n" }, "code on main")
			fetch()
			local base = (
				string.gsub(
					fixture.git(f.main, { "merge-base", head, "refs/remotes/origin/main" }),
					"%s+$",
					""
				)
			)
			fixture.git(f.main, { "update-ref", "refs/remotes/origin/main", base })
			local r = check()
			t.expect(r.code).toBe(1)
			t.expect(has(r.stdout, "z-nile/engine/other.luau is not tracker state")).toBe(true)
			t.expect(has(fixture.git(f.main, { "worktree", "list" }), "merge-check-")).toBe(false)
			fs.removeDir(f.base)
		end)
	end
)
