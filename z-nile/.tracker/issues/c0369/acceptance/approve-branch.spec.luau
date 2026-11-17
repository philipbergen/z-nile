--!strict
-- c0369 AC3: one `./zn approve <id>` of a design that is not on origin/main yet, run from the main checkout, records it
-- in the worktree of the issue's prep branch and pushes that branch (never forced); any other worktree is read only
-- when the command runs inside it, and its branch is pushed only when it is already on origin; a raft's layer branch
-- is never pushed; while a worktree holds a design of its own, main's older design is not approved behind it. A failed
-- push keeps the record and names `./zn approve <id> --publish`. The fixture is .cache/c0369-approve-branch.
-- Approving goes through `script` as in approve-main.spec: a terminal, `yes y |` for f0339's question, an explainer
-- page with every ready design, stub openers first on PATH, and the agent markers cleared.
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local BRANCH_NAME = "c0369-approve-branch"
local ID = "c0001"
local SLUG = "hold"
local ROOT = "z-nile/.tracker"
local ISSUE = `{ROOT}/issues/{ID}`
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. `# {ROOT}/issues/{ID}/check.sh\n` .. "finish\n"
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
local PAGE = `{ISSUE}/explainer.html`
local REJECT = "#!/bin/sh\necho 'the fixture origin refuses this push' >&2\nexit 1\n"

local function doc(design: string, ready: boolean?): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: {SLUG}\nraft: \ndepends_on: []\nemergent: false\ndesign: {if ready
			== false
		then "draft"
		else "ready"}\ncreated: 2026-11-10\nstatus: preparing-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\n{design}\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end
-- an explainer page of f0339's shape that names the contract of the document `text`
local function page(text: string): string
	local hash = contract.hash((contract.build(text, CHECK, { ["hold.spec.luau"] = SPEC })) :: contract.Parts)
	return `<!doctype html><html><head><meta charset="utf-8"><meta name="zn-contract" content="{hash}"><title>{ID}</title></head><body>`
		.. '<section id="idea"><p>Show the person a page before they say yes.</p></section>'
		.. '<section id="before"><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg></section>'
		.. '<section id="changes"><ul><li><code>z-nile/engine/hold.luau</code>: hold()</li></ul></section>'
		.. '<section id="after"><svg viewBox="0 0 10 10"><circle r="3"/></svg></section>'
		.. '<section id="choices"><div class="choice"><ul class="pros"><li>plain</li></ul><ul class="cons"><li>one more file</li></ul></div></section>'
		.. "</body></html>\n"
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end
local function seed(): { [string]: string }
	return {
		[`{ISSUE}/{ID}.md`] = doc("Hash the contract.", false), -- a ready seed would carry an approval (trackerfix seals it)
		[`{ISSUE}/check.sh`] = CHECK,
		[`{ISSUE}/acceptance/hold.spec.luau`] = SPEC,
	}
end
-- the folder of stub openers, first on PATH for every approve (set by each fixture's first case)
local stubs = ""
local function stubOpeners(base: string, repo: string)
	stubs = `{base}/stubs`
	fs.writeDir(stubs)
	for _, name in { "open", "xdg-open" } do
		fs.writeFile(`{stubs}/{name}`, "#!/bin/sh\nexit 0\n")
		fixture.exec(repo, "chmod", { "+x", `{stubs}/{name}` })
	end
end
-- `./zn approve c0001 <extra>` in `cwd`, with a terminal on stdin that answers y
local function approve(cwd: string, extra: { string }?, env: { [string]: string }?): fixture.Result
	local merged = table.clone(TERMINAL)
	merged.PATH = `{stubs}:{process.env.PATH or ""}`
	merged.HOME = process.env.HOME or ""
	local given: { [string]: string } = env or {}
	for k, v in given do
		merged[k] = v
	end
	local more: { string } = extra or {}
	local line =
		`yes y | script -q /dev/null sh -c './zn approve {ID} {table.concat(more, " ")}; echo "zn-exit=$?"'`
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
-- the place of `first` in `text` comes before the place of `second`
local function before(text: string, first: string, second: string): boolean
	local a = string.find(text, first, 1, true)
	local b = string.find(text, second, 1, true)
	return a ~= nil and b ~= nil and a < b
end
local function refuse(origin: string, on: boolean)
	local hook = `{origin}/hooks/pre-receive`
	if on then
		fs.writeDir(`{origin}/hooks`)
		fs.writeFile(hook, REJECT)
		local made = fixture.exec(origin, "chmod", { "+x", hook })
		if not made.ok then
			error(made.stderr)
		end
	elseif fs.isFile(hook) then
		fs.removeFile(hook)
	end
end

return t.spec("c0369 one approve from anywhere records and pushes an unmerged design", function(it)
	local g: trackerfix.Fixture
	local PREP = `prep-{SLUG}`
	local function wt(name: string): string
		return `{g.main}/.worktree/{name}`
	end
	local function design(name: string, text: string)
		fs.writeFile(`{wt(name)}/{ISSUE}/{ID}.md`, doc(text))
		fs.writeFile(`{wt(name)}/{PAGE}`, page(doc(text)))
		fixture.git(wt(name), { "add", "-A" })
		fixture.git(wt(name), { "commit", "-q", "-m", `prep: {text}` })
	end
	local function tip(name: string): string
		return fixture.git(wt(name), { "log", "-1", "--format=%s" })
	end
	local function headOf(name: string): string
		return fixture.git(wt(name), { "rev-parse", "HEAD" })
	end
	local function onOrigin(name: string): string?
		local r = fixture.exec(g.origin, "git", { "rev-parse", "-q", "--verify", `refs/heads/{name}` })
		return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else nil
	end
	local function mainOf(): string
		return fixture.git(g.origin, { "rev-parse", "main" })
	end

	it(
		"from the main checkout records an unmerged design in its prep worktree and pushes the branch",
		function()
			g = trackerfix.new(BRANCH_NAME, seed())
			stubOpeners(g.base, g.main)
			fixture.git(g.main, { "worktree", "add", "-q", "-b", PREP, wt(PREP), "origin/main" })
			design(PREP, "Hash the contract.")
			-- a prototype of the same issue: a ready design of its own that nobody is asked to approve
			fixture.git(
				g.main,
				{ "worktree", "add", "-q", "-b", "proto-hold", wt("proto-hold"), "origin/main" }
			)
			design("proto-hold", "A prototype's copy.")
			local mainBefore = mainOf()
			local head = fixture.git(g.main, { "rev-parse", "HEAD" })
			local out = must(approve(g.main))
			t.expect(before(out, `{ID}: approving in .worktree/{PREP}`, `approved {ID} `)).toBe(true)
			t.expect(has(out, `pushed {PREP}: the approval counts when its pull request merges`)).toBe(true)
			t.expect(fixture.git(wt(PREP), { "show", "--name-only", "--format=%s", "HEAD" }))
				.toBe(`tracker: approve {ID}\n\n{ISSUE}/approval.md`)
			t.expect(onOrigin(PREP)).toBe(headOf(PREP))
			-- a draft on main takes nothing, even though its text hashes the same; no checkout but the prep's changed
			t.expect(mainOf()).toBe(mainBefore)
			t.expect(fixture.git(g.main, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(tip("proto-hold")).toBe("prep: A prototype's copy.")
			t.expect(onOrigin("proto-hold")).toBe(nil)
			t.expect(fs.isDir(`{g.main}/.worktree/.approve-{ID}`)).toBe(false)
			-- asked again, it says where the approval waits and changes nothing
			local again = must(approve(g.main))
			t.expect(
				has(again, `{ID} is approved in .worktree/{PREP}: it counts when its pull request merges`)
			)
				.toBe(true)
			t.expect(tip(PREP)).toBe(`tracker: approve {ID}`)
			t.expect(tip("proto-hold")).toBe("prep: A prototype's copy.")
		end
	)

	it(
		"takes another worktree only when it is run inside it, and creates no branch on origin for it",
		function()
			local out = must(approve(wt("proto-hold")))
			t.expect(
				has(
					out,
					"proto-hold is not on origin, so nothing is pushed: it counts when this design reaches origin/main"
				)
			).toBe(true)
			t.expect(has(out, "pushed proto-hold")).toBe(false)
			t.expect(tip("proto-hold")).toBe(`tracker: approve {ID}`)
			t.expect(onOrigin("proto-hold")).toBe(nil)
		end
	)

	it("keeps the record when the push fails, and --publish from the main checkout pushes it", function()
		design(PREP, "A second design.")
		refuse(g.origin, true)
		local failed = approve(g.main)
		refuse(g.origin, false)
		t.expect(failed.ok).toBe(false)
		t.expect(has(say(failed), "but it does not count yet: ")).toBe(true)
		t.expect(has(say(failed), `.worktree/{PREP}`)).toBe(true)
		t.expect(has(say(failed), `Retry: ./zn approve {ID} --publish`)).toBe(true)
		t.expect(tip(PREP)).toBe(`tracker: approve {ID}`)
		t.expect(onOrigin(PREP) == headOf(PREP)).toBe(false)
		local out = must(approve(g.main, { "--publish" }))
		t.expect(has(out, `pushed {PREP}: the approval counts when its pull request merges`)).toBe(true)
		t.expect(onOrigin(PREP)).toBe(headOf(PREP))
		-- one row for the second design, not two
		t.expect(lines(fs.readFile(`{wt(PREP)}/{ISSUE}/approval.md`))).toBe(4)
	end)

	it("approves a redesign in its prep worktree while main still holds the approved older design", function()
		-- the prep's pull request merges: main holds its design and its approvals
		fixture.git(wt(PREP), { "push", "-q", "origin", "HEAD:main" })
		design(PREP, "A third design.")
		local mainBefore = mainOf()
		local out = must(approve(g.main))
		t.expect(has(out, `{ID}: approving in .worktree/{PREP}`)).toBe(true)
		t.expect(has(out, `pushed {PREP}: the approval counts when its pull request merges`)).toBe(true)
		t.expect(lines(fs.readFile(`{wt(PREP)}/{ISSUE}/approval.md`))).toBe(5)
		t.expect(mainOf()).toBe(mainBefore)
	end)

	it(
		"publishes the approval a prep holds when its design reached main without it, and records no second one",
		function()
			-- the pull request is squashed onto main from before the approval: the design is there, its approval is not
			trackerfix.elsewhere(
				g,
				{ [`{ISSUE}/{ID}.md`] = doc("A third design."), [PAGE] = page(doc("A third design.")) },
				"squash of the prep"
			)
			local held = fs.readFile(`{wt(PREP)}/{ISSUE}/approval.md`)
			local head = headOf(PREP)
			local commits = tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" })) :: number
			local out = must(approve(g.main))
			t.expect(has(out, `{ID}: publishing from .worktree/{PREP}`)).toBe(true)
			t.expect(has(out, `approved {ID} `)).toBe(false)
			t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" }))).toBe(commits + 1)
			t.expect(fixture.git(g.origin, { "show", `main:{ISSUE}/approval.md` }))
				.toBe((string.gsub(held, "%s+$", "")))
			t.expect(headOf(PREP)).toBe(head)
			local again = must(approve(g.main))
			t.expect(has(again, `{ID} is already approved on origin/main`)).toBe(true)
		end
	)

	it("does not take a prep worktree left behind after its design merged and main moved on", function()
		trackerfix.elsewhere(
			g,
			{ [`{ISSUE}/{ID}.md`] = doc("The design after it."), [PAGE] = page(doc("The design after it.")) },
			"a later design"
		)
		local head = headOf(PREP)
		local pushed = onOrigin(PREP)
		local commits = tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" })) :: number
		local out = must(approve(g.main))
		t.expect(has(out, `{ID}: approving in origin/main`)).toBe(true)
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" }))).toBe(commits + 1)
		t.expect(headOf(PREP)).toBe(head)
		t.expect(onOrigin(PREP)).toBe(pushed)
		-- the same for a prep that was never approved in its own worktree: its design merged, was approved on main,
		-- and main moved on again
		design(PREP, "A fifth design.")
		trackerfix.elsewhere(
			g,
			{ [`{ISSUE}/{ID}.md`] = doc("A fifth design."), [PAGE] = page(doc("A fifth design.")) },
			"squash of the prep, again"
		)
		must(approve(g.main))
		trackerfix.elsewhere(
			g,
			{ [`{ISSUE}/{ID}.md`] = doc("A sixth design."), [PAGE] = page(doc("A sixth design.")) },
			"and a later one"
		)
		local left = headOf(PREP)
		local later = must(approve(g.main))
		t.expect(has(later, `{ID}: approving in origin/main`)).toBe(true)
		t.expect(has(later, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(headOf(PREP)).toBe(left)
	end)

	it(
		"never approves main's older design behind a prep's own pushed design, asked again from anywhere",
		function()
			-- main holds an older design, ready and with no matching approval; the prep holds a redesign of its own
			trackerfix.elsewhere(
				g,
				{ [`{ISSUE}/{ID}.md`] = doc("An older design."), [PAGE] = page(doc("An older design.")) },
				"an older design, unapproved"
			)
			fixture.git(wt(PREP), { "fetch", "-q", "origin" })
			design(PREP, "A seventh design.")
			local mainBefore = mainOf()
			local first = must(approve(g.main))
			t.expect(has(first, `{ID}: approving in .worktree/{PREP}`)).toBe(true)
			t.expect(has(first, `pushed {PREP}: the approval counts when its pull request merges`)).toBe(true)
			t.expect(onOrigin(PREP)).toBe(headOf(PREP))
			-- asked again, from the main checkout and with ZN_APPROVE_IN naming another checkout (it still places): the
			-- approval waits for the pull request, and nothing is recorded or published for main's older design
			local placed: { { [string]: string } } = { {}, { ZN_APPROVE_IN = wt(PREP) } }
			for _, env in placed do
				local again = must(approve(g.main, nil, env))
				t.expect(
					has(again, `{ID} is approved in .worktree/{PREP}: it counts when its pull request merges`)
				)
					.toBe(true)
				t.expect(has(again, "origin/main's older design stays unapproved")).toBe(true)
				t.expect(mainOf()).toBe(mainBefore)
				t.expect(fs.isDir(`{g.main}/.worktree/.approve-{ID}`)).toBe(false)
				t.expect(tip(PREP)).toBe(`tracker: approve {ID}`)
			end
		end
	)

	it(
		"never forces a push: a prep branch that moved on origin keeps its commit and the record waits",
		function()
			-- someone else pushed to the prep branch from another checkout
			fixture.git(g.main, { "fetch", "-q", "origin" })
			fixture.git(g.main, { "worktree", "add", "-q", "-b", "moved", wt("moved"), `origin/{PREP}` })
			fs.writeFile(`{wt("moved")}/{ROOT}/note.md`, "a commit the prep worktree lacks\n")
			fixture.git(wt("moved"), { "add", "-A" })
			fixture.git(wt("moved"), { "commit", "-q", "-m", "elsewhere on the prep branch" })
			fixture.git(wt("moved"), { "push", "-q", "origin", `HEAD:refs/heads/{PREP}` })
			local theirs = headOf("moved")
			design(PREP, "An eighth design.")
			local failed = approve(g.main)
			t.expect(failed.ok).toBe(false)
			t.expect(has(say(failed), "but it does not count yet: ")).toBe(true)
			t.expect(has(say(failed), `Retry: ./zn approve {ID} --publish`)).toBe(true)
			t.expect(tip(PREP)).toBe(`tracker: approve {ID}`)
			t.expect(onOrigin(PREP)).toBe(theirs)
		end
	)

	it(
		"approves a design whose merge-base holds a draft of the same text, after main's draft moved on",
		function()
			trackerfix.elsewhere(
				g,
				{ [`{ISSUE}/{ID}.md`] = doc("A draft on main.", false) },
				"a draft on main"
			)
			fixture.git(g.main, { "fetch", "-q", "origin" })
			fixture.git(g.main, { "worktree", "add", "-q", "-b", "late", wt("late"), "origin/main" })
			design("late", "A draft on main.")
			trackerfix.elsewhere(
				g,
				{ [`{ISSUE}/{ID}.md`] = doc("The draft moved on.", false) },
				"the draft moved on"
			)
			local out = must(approve(wt("late")))
			t.expect(has(out, `{ID}: approving in .worktree/late`)).toBe(true)
			t.expect(tip("late")).toBe(`tracker: approve {ID}`)
			t.expect(onOrigin("late")).toBe(nil)
		end
	)

	it("records on a raft's layer branch and pushes nothing: it counts for finish and done there", function()
		local LAYER = `R0001/1/{ID}`
		fixture.git(g.main, { "fetch", "-q", "origin" })
		fixture.git(g.main, { "worktree", "add", "-q", "-b", LAYER, wt("R0001"), "origin/main" })
		design("R0001", "A change on the layer.")
		local mainBefore = mainOf()
		local out = must(approve(wt("R0001")))
		t.expect(
			has(
				out,
				`{ID}: approved on the layer branch {LAYER}: nothing is pushed; it counts for ./zn finish and ./zn done in `
			)
		).toBe(true)
		t.expect(tip("R0001")).toBe(`tracker: approve {ID}`)
		t.expect(onOrigin(LAYER)).toBe(nil)
		t.expect(mainOf()).toBe(mainBefore)
		t.expect(fixture.exec(wt("R0001"), "./zn", { "approve", ID, "--check" }).ok).toBe(true)
	end)
end)
