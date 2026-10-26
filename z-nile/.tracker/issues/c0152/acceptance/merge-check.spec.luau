--!strict
-- c0152: `./zn merge-check <head>` says whether a PR whose CI went green at <head> may merge although origin's main
-- moved since: exit 0 only when every commit main gained is tracker state the publisher allows (publish.allowed: an
-- item's document, check.sh or spend.md under a registered root, and the id counter) and touches none of the PR's
-- files; otherwise exit 1, naming each commit and path. Main's tip comes from the remote (ls-remote), never the local
-- tracking ref, and must be fetched. Fixture under .cache/c0152-merge-check (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local DOC1 = "z-nile/.tracker/issues/c0001/c0001.md"
local DOC2 = "z-nile/.tracker/issues/c0002/c0002.md"
local f: trackerfix.Fixture
local head = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function check(): fixture.Result
	return trackerfix.tr(f, f.main, { "merge-check", head })
end
local function fetch()
	fixture.git(f.main, { "fetch", "-q", "origin" })
end

return t.spec("c0152 a PR may merge past main's tracker-only commits it doesn't touch", function(it)
	it("sets up a PR branch that changes code and c0001's document", function()
		f = trackerfix.new("c0152-merge-check", {
			["z-nile/projects.toml"] = REGISTRY,
			[DOC1] = trackerfix.stub("c0001", "one", "new-a-b-c"),
			[DOC2] = trackerfix.stub("c0002", "two", "new-a-b-c"),
			["pickman/.tracker/issues/.gitkeep"] = "",
		})
		fixture.git(f.main, { "checkout", "-q", "-b", "pr" })
		fs.writeDir(`{f.main}/z-nile/engine`)
		fs.writeFile(`{f.main}/z-nile/engine/c0152-demo.luau`, "return nil\n")
		fs.writeFile(`{f.main}/{DOC1}`, trackerfix.stub("c0001", "one, edited by the PR", "new-a-b-c"))
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "the PR" })
		head = (string.gsub(fixture.git(f.main, { "rev-parse", "HEAD" }), "%s+$", ""))
		local r = check()
		t.expect(r.code).toBe(0)
		t.expect(has(r.stdout, "has not moved")).toBe(true)
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
		fetch()
	end)

	it("tracker state the PR doesn't touch passes: a spend row, another document, the counter", function()
		trackerfix.elsewhere(
			f,
			{ [DOC2] = trackerfix.stub("c0002", "two", "preparing-a-b-c") },
			"tracker: c0002 preparing"
		)
		trackerfix.elsewhere(f, { ["z-nile/next"] = "f 1\nd 1\nc 3\nR 1\n" }, "tracker: counter")
		fetch()
		local r = check()
		t.expect(r.code).toBe(0)
		t.expect(has(r.stdout, "moved by 3 commit(s), all tracker state")).toBe(true)
	end)

	it("a tracker document the PR also changes, a sequestered spec and code each refuse, named", function()
		trackerfix.elsewhere(
			f,
			{ [DOC1] = trackerfix.stub("c0001", "one", "preparing-a-b-c") },
			"tracker: c0001 preparing"
		)
		fetch()
		local r1 = check()
		t.expect(r1.code).toBe(1)
		t.expect(has(r1.stdout, `{DOC1} is a file this PR changes`)).toBe(true)
		trackerfix.elsewhere(
			f,
			{ ["z-nile/.tracker/issues/c0002/acceptance/x.spec.luau"] = "return nil\n" },
			"tracker: a spec"
		)
		trackerfix.elsewhere(f, { ["z-nile/engine/other.luau"] = "return nil\n" }, "code on main")
		fetch()
		local r2 = check()
		t.expect(r2.code).toBe(1)
		t.expect(has(r2.stdout, "z-nile/.tracker/issues/c0002/acceptance/x.spec.luau is not tracker state"))
			.toBe(true)
		t.expect(has(r2.stdout, "z-nile/engine/other.luau is not tracker state")).toBe(true)
		t.expect(has(r2.stdout, "merge origin/main in")).toBe(true)
	end)

	it(
		"the local tracking ref is never the judge: forged back to the PR's base, the verdict stands",
		function()
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
			fs.removeDir(f.base)
		end
	)
end)
