--!strict
-- c0369 AC7 (design review 002 F2 and 003 F1, the user's rulings of 2026-11-17): for an issue in active/ on origin/main
-- whose contract changed on its raft's branch, one `./zn approve <id>` from the main checkout finds the raft's own
-- worktree (.worktree/<R-id>), records there only on the raft's top layer with a clean tree, and pushes that layer,
-- never forced; approval.md counts as written after a finish, so the layer stays finished for `./zn done`. A lower
-- layer or a dirty tree is refused, naming the branch, never a directory. No other worktree named like a raft's is
-- read, and an issue that is not in active/ never has its raft's worktree read.
-- The fixture is .cache/c0369-approve-raft. Approving goes through `script` as in approve-main.spec: a terminal,
-- `yes y |` for f0339's question, an explainer page with every ready design, stub openers first on PATH, and the
-- agent markers cleared.
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local layergit = require("@znile/engine/layergit")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0369-approve-raft"
local ROOT = "z-nile/.tracker"
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. "finish\n"
local SPEC = "--!strict\n"
	.. 'local t = require("@tests/lib/t")\n'
	.. 'return t.spec("holds", function(it)\n'
	.. '\tit("holds", function()\n'
	.. "\t\tt.expect(true).toBe(true)\n"
	.. "\tend)\n"
	.. "end)\n"
local TERMINAL: { [string]: string } = {
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

local function doc(id: string, design: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Hold\nslug: hold-{id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\n{design}\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end
-- an explainer page of f0339's shape that names the contract of the document `text`
local function page(id: string, text: string): string
	local hash = contract.hash((contract.build(text, CHECK, { ["hold.spec.luau"] = SPEC })) :: contract.Parts)
	return `<!doctype html><html><head><meta charset="utf-8"><meta name="zn-contract" content="{hash}"><title>{id}</title></head><body>`
		.. '<section id="idea"><p>Show the person a page before they say yes.</p></section>'
		.. '<section id="before"><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg></section>'
		.. '<section id="changes"><ul><li><code>z-nile/engine/hold.luau</code>: hold()</li></ul></section>'
		.. '<section id="after"><svg viewBox="0 0 10 10"><circle r="3"/></svg></section>'
		.. '<section id="choices"><div class="choice"><ul class="pros"><li>plain</li></ul><ul class="cons"><li>one more file</li></ul></div></section>'
		.. "</body></html>\n"
end
local function issueFiles(dir: string, id: string, design: string, raft: string): { [string]: string }
	return {
		[`{dir}/{id}.md`] = doc(id, design, raft),
		[`{dir}/check.sh`] = CHECK,
		[`{dir}/acceptance/hold.spec.luau`] = SPEC,
		[`{dir}/explainer.html`] = page(id, doc(id, design, raft)),
	}
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end
local stubs = ""
-- `./zn approve <id> <extra>` in `cwd`, with a terminal on stdin that answers y
local function approve(cwd: string, id: string, extra: { string }?): fixture.Result
	local merged = table.clone(TERMINAL)
	merged.PATH = `{stubs}:{process.env.PATH or ""}`
	merged.HOME = process.env.HOME or ""
	local more: { string } = extra or {}
	local line =
		`yes y | script -q /dev/null sh -c './zn approve {id} {table.concat(more, " ")}; echo "zn-exit=$?"'`
	local r = fixture.exec(cwd, "sh", { "-c", line }, { env = merged })
	local code = string.match(r.stdout, "zn%-exit=(%d+)")
	return { ok = code == "0", code = tonumber(code or "1") or 1, stdout = r.stdout, stderr = r.stderr }
end
local function must(r: fixture.Result): string
	if not r.ok then
		error(say(r), 2)
	end
	return say(r)
end
local function lines(text: string): number
	local n = 0
	for _ in string.gmatch(text, "[^\n]+") do
		n += 1
	end
	return n
end

return t.spec("c0369 approve finds an active issue's raft worktree", function(it)
	local f: trackerfix.Fixture
	local ACTIVE = `{ROOT}/issues/active/c0001`
	local function wt(name: string): string
		return `{f.main}/.worktree/{name}`
	end
	local function tip(name: string): string
		return fixture.git(wt(name), { "log", "-1", "--format=%s" })
	end
	local function mainOf(): string
		return fixture.git(f.origin, { "rev-parse", "main" })
	end
	local function onOrigin(name: string): string?
		local r = fixture.exec(f.origin, "git", { "rev-parse", "-q", "--verify", `refs/heads/{name}` })
		return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else nil
	end
	-- a worktree on a layer branch of origin/main with a changed design of `id` in `dir`
	local function changed(name: string, branch: string, dir: string, id: string, raft: string, text: string)
		fixture.git(f.main, { "fetch", "-q", "origin" })
		fixture.git(f.main, { "worktree", "add", "-q", "-b", branch, wt(name), "origin/main" })
		for rel, body in issueFiles(dir, id, text, raft) do
			fs.writeFile(`{wt(name)}/{rel}`, body)
		end
		fixture.git(wt(name), { "add", "-A" })
		fixture.git(wt(name), { "commit", "-q", "-m", `layer: {text}` })
	end

	it(
		"sets up an approved issue in active/ in raft R0001, and an approved backlog issue naming R0003",
		function()
			local seed = issueFiles(`{ROOT}/issues/c0001`, "c0001", "Hash the contract.", "")
			for rel, body in issueFiles(`{ROOT}/issues/c0002`, "c0002", "Hash it too.", "R0003") do
				seed[rel] = body
			end
			for rel, body in issueFiles(`{ROOT}/issues/c0003`, "c0003", "Readied before approval.", "") do
				seed[rel] = body
			end
			f = trackerfix.new(NAME, seed) -- ready seeds in the backlog are sealed: each carries a matching approval.md
			stubs = `{f.base}/stubs`
			fs.writeDir(stubs)
			for _, name in { "open", "xdg-open" } do
				fs.writeFile(`{stubs}/{name}`, "#!/bin/sh\nexit 0\n")
				fixture.exec(f.main, "chmod", { "+x", `{stubs}/{name}` })
			end
			-- ready moves c0001 to active/ and names its raft (the front matter is outside the contract)
			fixture.git(f.main, { "fetch", "-q", "origin" })
			fixture.git(f.main, { "worktree", "add", "-q", "-b", "ready", wt("ready"), "origin/main" })
			fixture.git(wt("ready"), { "mv", `{ROOT}/issues/c0001`, ACTIVE })
			local moved = fs.readFile(`{wt("ready")}/{ACTIVE}/c0001.md`)
			fs.writeFile(
				`{wt("ready")}/{ACTIVE}/c0001.md`,
				(string.gsub(moved, "\nraft: \n", "\nraft: R0001\n", 1))
			)
			-- and c0003, readied in R0001 with no approval yet (a raft that lands once the person approves)
			fixture.git(wt("ready"), { "mv", `{ROOT}/issues/c0003`, `{ROOT}/issues/active/c0003` })
			fixture.git(wt("ready"), { "rm", "-q", "-f", `{ROOT}/issues/active/c0003/approval.md` })
			local third = fs.readFile(`{wt("ready")}/{ROOT}/issues/active/c0003/c0003.md`)
			fs.writeFile(
				`{wt("ready")}/{ROOT}/issues/active/c0003/c0003.md`,
				(string.gsub(third, "\nraft: \n", "\nraft: R0001\n", 1))
			)
			fixture.git(wt("ready"), { "add", "-A" })
			fixture.git(wt("ready"), { "commit", "-q", "-m", "ready R0001" })
			fixture.git(wt("ready"), { "push", "-q", "origin", "HEAD:main" })
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			t.expect(fixture.exec(f.main, "./zn", { "approve", "c0001", "--check" }).ok).toBe(true)
			t.expect(fixture.exec(f.main, "./zn", { "approve", "c0002", "--check" }).ok).toBe(true)
		end
	)

	it("reads no worktree named like a raft but the active issue's own raft's", function()
		-- another raft's worktree with a changed copy of c0001, and the backlog c0002's raft worktree
		changed("R0002", "R0002/1/c0001", ACTIVE, "c0001", "R0001", "A change on another raft.")
		changed("R0003", "R0003/1/c0002", `{ROOT}/issues/c0002`, "c0002", "R0003", "A change on its raft.")
		local mainBefore = mainOf()
		for _, id in { "c0001", "c0002" } do
			local out = must(approve(f.main, id))
			t.expect(has(out, `{id} is already approved on origin/main`)).toBe(true)
		end
		t.expect(tip("R0002")).toBe("layer: A change on another raft.")
		t.expect(tip("R0003")).toBe("layer: A change on its raft.")
		t.expect(mainOf()).toBe(mainBefore)
	end)

	it(
		"from the main checkout approves a changed contract on the raft's top layer and pushes the layer",
		function()
			changed("R0001", "R0001/1/c0001", ACTIVE, "c0001", "R0001", "A change on the raft's layer.")
			local mainBefore = mainOf()
			local out = must(approve(f.main, "c0001"))
			t.expect(has(out, "c0001: approving in .worktree/R0001")).toBe(true)
			t.expect(has(out, "It lands with R0001: pushed to R0001/1/c0001, nothing to publish.")).toBe(true)
			t.expect(tip("R0001")).toBe("tracker: approve c0001")
			t.expect(onOrigin("R0001/1/c0001")).toBe(fixture.git(wt("R0001"), { "rev-parse", "HEAD" }))
			t.expect(tip("R0002")).toBe("layer: A change on another raft.")
			t.expect(mainOf()).toBe(mainBefore)
			t.expect(fs.isDir(wt(".approve-c0001"))).toBe(false)
			t.expect(fixture.exec(wt("R0001"), "./zn", { "approve", "c0001", "--check" }).ok).toBe(true)
			-- asked again, it records nothing new: the approval waits on the pushed layer
			local rows = lines(fs.readFile(`{wt("R0001")}/{ACTIVE}/approval.md`))
			local again = must(approve(f.main, "c0001"))
			t.expect(has(again, "c0001 is approved in .worktree/R0001: it lands with R0001")).toBe(true)
			t.expect(lines(fs.readFile(`{wt("R0001")}/{ACTIVE}/approval.md`))).toBe(rows)
			t.expect(tip("R0001")).toBe("tracker: approve c0001")
			t.expect(mainOf()).toBe(mainBefore)
			-- --publish is the retry, never refused for an issue in active/: with the layer pushed it has nothing to do
			local pushedTip = onOrigin("R0001/1/c0001")
			local retried = must(approve(f.main, "c0001", { "--publish" }))
			t.expect(has(retried, "c0001 is approved in .worktree/R0001: it lands with R0001")).toBe(true)
			t.expect(has(retried, "published")).toBe(false)
			t.expect(onOrigin("R0001/1/c0001")).toBe(pushedTip)
			t.expect(lines(fs.readFile(`{wt("R0001")}/{ACTIVE}/approval.md`))).toBe(rows)
			t.expect(mainOf()).toBe(mainBefore)
		end
	)

	it(
		"approves an active issue whose design is main's on the raft's top layer, never on origin/main",
		function()
			local mainBefore = mainOf()
			local out = must(approve(f.main, "c0003"))
			t.expect(has(out, "c0003: approving in .worktree/R0001")).toBe(true)
			t.expect(has(out, "It lands with R0001: pushed to R0001/1/c0001, nothing to publish.")).toBe(true)
			t.expect(has(out, "published")).toBe(false)
			t.expect(mainOf()).toBe(mainBefore)
			t.expect(fs.isDir(wt(".approve-c0003"))).toBe(false)
			t.expect(onOrigin("R0001/1/c0001")).toBe(fixture.git(wt("R0001"), { "rev-parse", "HEAD" }))
		end
	)

	it("refuses a raft worktree with uncommitted changes, and records nothing", function()
		for rel, body in issueFiles(ACTIVE, "c0001", "A second change on the layer.", "R0001") do
			fs.writeFile(`{wt("R0001")}/{rel}`, body)
		end
		fixture.git(wt("R0001"), { "add", "-A" })
		fixture.git(wt("R0001"), { "commit", "-q", "-m", "layer: a second change" })
		fs.writeFile(`{wt("R0001")}/stray.txt`, "not committed\n")
		local refused = approve(f.main, "c0001")
		t.expect(refused.ok).toBe(false)
		t.expect(has(say(refused), "c0001 is active in R0001: ")).toBe(true)
		t.expect(has(say(refused), " has uncommitted changes; commit them, then ./zn approve c0001"))
			.toBe(true)
		t.expect(tip("R0001")).toBe("layer: a second change")
		fs.removeFile(`{wt("R0001")}/stray.txt`)
	end)

	it("refuses a layer below the top, naming the top layer's branch and no directory", function()
		-- the top layer holds the second change; the worktree is on the layer below, whose copy was approved and pushed
		fixture.git(f.main, { "branch", "R0001/2/c0001", "R0001/1/c0001" })
		fixture.git(wt("R0001"), { "reset", "-q", "--hard", "HEAD~1" })
		local refused = approve(f.main, "c0001")
		t.expect(refused.ok).toBe(false)
		t.expect(
			has(
				say(refused),
				"c0001 is active in R0001: run ./zn approve c0001 on R0001/2/c0001, its top layer; "
			)
		).toBe(true)
		t.expect(has(say(refused), "the raft's worktree is on R0001/1/c0001")).toBe(true)
		t.expect(has(say(refused), "cd ")).toBe(false)
		t.expect(tip("R0001")).toBe("tracker: approve c0003") -- nothing recorded on the layer below
		fixture.git(wt("R0001"), { "reset", "-q", "--hard", "R0001/2/c0001" })
		fixture.git(f.main, { "branch", "-D", "R0001/2/c0001" })
	end)

	it("counts approval.md, in an issue's folder, as written after a layer's finish", function()
		t.expect(layergit.isPostFinishPath("z-nile/.tracker/issues/active/c0001/approval.md", "R0001"))
			.toBe(true)
		t.expect(layergit.isPostFinishPath("z-nile/.tracker/issues/c0001/approval.md", "R0001")).toBe(true)
		t.expect(layergit.isPostFinishPath("z-nile/.tracker/issues/active/c0001/check.sh", "R0001"))
			.toBe(false)
		t.expect(
			layergit.isPostFinishPath("z-nile/.tracker/issues/active/c0001/acceptance/approval.md", "R0001")
		)
			.toBe(false)
	end)

	it("records nothing in a raft worktree on no branch (a rebase in progress), and says so", function()
		fixture.git(wt("R0001"), { "checkout", "-q", "--detach" })
		for rel, body in issueFiles(ACTIVE, "c0001", "A change in the middle of a restack.", "R0001") do
			fs.writeFile(`{wt("R0001")}/{rel}`, body)
		end
		fixture.git(wt("R0001"), { "add", "-A" })
		fixture.git(wt("R0001"), { "commit", "-q", "-m", "layer: mid-restack" })
		local mainBefore = mainOf()
		local refused = approve(f.main, "c0001")
		t.expect(refused.ok).toBe(false)
		t.expect(
			has(
				say(refused),
				"is on no branch (a rebase or another operation may be in progress): nothing recorded"
			)
		).toBe(true)
		t.expect(tip("R0001")).toBe("layer: mid-restack")
		t.expect(mainOf()).toBe(mainBefore)
	end)
end)
