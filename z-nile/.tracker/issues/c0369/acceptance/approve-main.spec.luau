--!strict
-- c0369 AC2: one `./zn approve <id>` of a design merged to origin/main, run from the main checkout or any worktree,
-- records the approval in a detached worktree of origin/main it makes and removes, and publishes it in the same
-- command; the refusals come first; a failed publish or publishing off keeps the record and names
-- `./zn approve <id> --publish`, which finds it from anywhere. The fixture is .cache/c0369-approve-main.
-- Approving goes through `script`, which allocates a terminal; the spec process itself has none, and the exit code is
-- echoed inside `script`, whose own code is not ./zn's. Every ready design carries an explainer page that names its
-- contract, the opener is a stub first on PATH and `yes y |` answers at the terminal, so every case passes with or
-- without f0339's page check and y/n question in approve (c0368's outcome, carried here). Every command gets a
-- person's terminal: the agent markers and session ids cleared (zz-test lesson terminal-fixtures-clear-the-agent-session).
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MAIN_NAME = "c0369-approve-main"
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

return t.spec("c0369 one approve from anywhere records and publishes", function(it)
	local f: trackerfix.Fixture
	local scratch = "" -- the command's own worktree
	local other = "" -- a worktree of other work, behind main
	local persons = "" -- a worktree a person made, on a branch, named as the command's used to be

	local function onMain(rel: string): string
		return fixture.git(f.origin, { "show", `main:{rel}` })
	end
	local function count(): number
		return tonumber(fixture.git(f.origin, { "rev-list", "--count", "main" })) :: number
	end
	local function redesign(text: string)
		trackerfix.elsewhere(
			f,
			{ [`{ISSUE}/{ID}.md`] = doc(text), [PAGE] = page(doc(text)) },
			`design: {text}`
		)
	end
	local function rowsOnMain(): number
		return lines(onMain(`{ISSUE}/approval.md`)) - 2 -- less the title and the header
	end

	it("sets up a design that merged to main with no approval", function()
		f = trackerfix.new(MAIN_NAME, seed())
		scratch = `{f.main}/.worktree/.approve-{ID}`
		other = `{f.main}/.worktree/other-work`
		persons = `{f.main}/.worktree/approve-{ID}`
		stubOpeners(f.base, f.main)
		redesign("Hash the contract.")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "other-work", other, "HEAD" })
		fixture.git(f.main, { "worktree", "add", "-q", "-b", `approve-{ID}`, persons, "HEAD" })
	end)

	it("keeps every refusal before it makes anything, whatever ZN_APPROVE_IN says", function()
		local commits = count()
		local head = fixture.git(f.main, { "rev-parse", "HEAD" })
		local placed: { { [string]: string } } = { {}, { ZN_APPROVE_IN = f.main } }
		for _, extra in placed do
			-- without a terminal the zn wrapper refuses
			local piped = fixture.exec(f.main, "./zn", { "approve", ID }, { env = extra })
			t.expect(piped.ok).toBe(false)
			t.expect(has(say(piped), "approve is refused without a terminal on stdin")).toBe(true)
			local dispatched: { [string]: string } = { ZN_DISPATCH = "1" }
			for k, v in extra do
				dispatched[k] = v
			end
			local d = approve(f.main, nil, dispatched)
			t.expect(d.ok).toBe(false)
			t.expect(has(say(d), "ZN_DISPATCH is set")).toBe(true)
			-- the engine started past the wrapper, with a terminal, refuses before placement too
			local env = table.clone(TERMINAL)
			env.PATH = process.env.PATH or ""
			env.HOME = process.env.HOME or ""
			for k, v in dispatched do
				env[k] = v
			end
			local engine = fixture.exec(
				f.main,
				"script",
				{ "-q", "/dev/null", "lune", "run", "z-nile/engine/main", "--", "approve", ID },
				{ env = env }
			)
			-- (script's own exit code is not the engine's: the text is the evidence)
			t.expect(has(say(engine), "approve is refused while ZN_DISPATCH is set")).toBe(true)
		end
		-- a placed run never records in the main checkout
		local inMain = approve(f.main, nil, { ZN_APPROVE_IN = f.main })
		t.expect(inMain.ok).toBe(false)
		t.expect(has(say(inMain), "approve must run inside a worktree")).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fixture.git(f.main, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(fs.isFile(`{f.main}/{ISSUE}/approval.md`)).toBe(false)
		t.expect(fs.isDir(scratch)).toBe(false)
	end)

	it("refuses when its own worktree's path is taken by something else, naming the path", function()
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "taken", scratch, "HEAD" })
		local commits = count()
		local r = approve(f.main)
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), `.worktree/.approve-{ID} is in the way`)).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe("design: Hash the contract.")
		fixture.git(f.main, { "worktree", "remove", scratch })
	end)

	it(
		"from the main checkout records and publishes a merged design in one command, and writes no checkout",
		function()
			local commits = count()
			local head = fixture.git(f.main, { "rev-parse", "HEAD" })
			local out = must(approve(f.main))
			local hash = string.match(out, `approved {ID} (%x+) in a worktree of origin/main`)
			if not hash then
				error(out)
			end
			-- it says where before it records, and records before it publishes
			t.expect(before(out, `{ID}: approving in origin/main`, `approved {ID} `)).toBe(true)
			t.expect(before(out, `approved {ID} `, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			t.expect(fixture.git(f.origin, { "show", "--name-only", "--format=%s", "main" }))
				.toBe(`tracker: approve {ID}\n\n{ISSUE}/approval.md`)
			t.expect(has(onMain(`{ISSUE}/approval.md`), `\t{MAIN_NAME}\t{hash}\t`)).toBe(true)
			-- nothing was committed in the main checkout or in any other worktree, and the command's own is gone
			t.expect(fixture.git(f.main, { "log", "--format=%s", `{head}..HEAD`, "--", ISSUE })).toBe("")
			t.expect(fixture.git(f.main, { "status", "--porcelain", "--", ROOT })).toBe("")
			t.expect(fixture.git(other, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(fixture.git(persons, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(fs.isDir(scratch)).toBe(false)
			t.expect(has(fixture.git(f.main, { "worktree", "list" }), ".worktree/.approve-")).toBe(false)
		end
	)

	it("says an approved design is approved and publishes nothing more", function()
		local commits = count()
		local out = must(approve(f.main))
		t.expect(has(out, `{ID} is already approved on origin/main`)).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fs.isDir(scratch)).toBe(false)
	end)

	it("from a worktree that is only behind main approves main's design, not its own stale copy", function()
		redesign("A second design.")
		local head = fixture.git(other, { "rev-parse", "HEAD" })
		local commits = count()
		local out = must(approve(other))
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(count()).toBe(commits + 1)
		t.expect(rowsOnMain()).toBe(2)
		t.expect(fixture.git(other, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(fixture.git(other, { "status", "--porcelain" })).toBe("")
		-- the new row is for the second design: a checkout of main says it holds
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local held = fixture.exec(f.main, "./zn", { "approve", ID, "--check" })
		t.expect(held.ok).toBe(true)
	end)

	it("with publishing off keeps the record, fails saying so, and the retry publishes that row", function()
		redesign("A third design.")
		local commits = count()
		local off = approve(f.main, nil, { PICKMAN_PUBLISH = "0" })
		t.expect(off.ok).toBe(false)
		t.expect(has(say(off), "but it does not count yet: publishing is off")).toBe(true)
		t.expect(has(say(off), `Retry: ./zn approve {ID} --publish`)).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fs.isDir(scratch)).toBe(true) -- the command's worktree is kept after a failure
		t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe(`tracker: approve {ID}`)
		local kept = fs.readFile(`{scratch}/{ISSUE}/approval.md`)
		-- the plain command, asked again, publishes what was recorded and records nothing new
		local out = must(approve(f.main))
		t.expect(has(out, `{ID}: publishing from .worktree/.approve-{ID}`)).toBe(true)
		t.expect(has(out, `approved {ID} `)).toBe(false)
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(count()).toBe(commits + 1)
		t.expect(onMain(`{ISSUE}/approval.md`)).toBe((string.gsub(kept, "%s+$", "")))
		t.expect(rowsOnMain()).toBe(3)
		t.expect(fs.isDir(scratch)).toBe(false)
	end)

	it(
		"keeps the record when the publish fails, names the retry, and the retry finds it from anywhere",
		function()
			redesign("A fourth design.")
			refuse(f.origin, true)
			local commits = count()
			local failed = approve(f.main)
			refuse(f.origin, false)
			t.expect(failed.ok).toBe(false)
			t.expect(
				has(say(failed), `{ID}: approved in a worktree of origin/main, but it does not count yet: `)
			)
				.toBe(true)
			t.expect(has(say(failed), `Retry: ./zn approve {ID} --publish`)).toBe(true)
			t.expect(count()).toBe(commits)
			-- the record stays, committed, in the command's worktree
			t.expect(fs.isDir(scratch)).toBe(true) -- the command's worktree is kept after a failure
			t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe(`tracker: approve {ID}`)
			local kept = fs.readFile(`{scratch}/{ISSUE}/approval.md`)
			t.expect(lines(kept)).toBe(6)
			local out = must(approve(other, { "--publish" }))
			t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			-- the row published is the one recorded at the first attempt
			t.expect(onMain(`{ISSUE}/approval.md`)).toBe((string.gsub(kept, "%s+$", "")))
			t.expect(fs.isDir(scratch)).toBe(false)
			local again = must(approve(f.main, { "--publish" }))
			t.expect(has(again, `{ID} is already approved on origin/main`)).toBe(true)
		end
	)

	it(
		"drops a record left by a failed publish once main's design is replaced, and approves the new one",
		function()
			redesign("A fifth design.")
			refuse(f.origin, true)
			local failed = approve(f.main)
			refuse(f.origin, false)
			t.expect(failed.ok).toBe(false)
			t.expect(fs.isDir(scratch)).toBe(true) -- the command's worktree is kept after a failure
			t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe(`tracker: approve {ID}`)
			redesign("A sixth design.")
			-- the retry has nothing: the record is of a design that is nobody's now
			local commits = count()
			local retry = approve(f.main, { "--publish" })
			t.expect(retry.ok).toBe(false)
			t.expect(has(say(retry), `{ID} has no recorded approval to publish. Run ./zn approve {ID}.`))
				.toBe(true)
			t.expect(count()).toBe(commits)
			-- the plain command approves main's design in the same worktree, moved to origin/main
			local out = must(approve(f.main))
			t.expect(before(out, `approved {ID} `, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			t.expect(rowsOnMain()).toBe(5) -- the fifth design's row was never published
			t.expect(fs.isDir(scratch)).toBe(false)
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			t.expect(fixture.exec(f.main, "./zn", { "approve", ID, "--check" }).ok).toBe(true)
		end
	)

	it(
		"run inside a worktree that left main before the design there was replaced, approves main's",
		function()
			-- the worktree holds an unapproved design that was main's own when it branched; main then got another
			redesign("A seventh design.")
			fixture.git(f.main, { "fetch", "-q", "origin" })
			local left = `{f.main}/.worktree/left-behind`
			fixture.git(f.main, { "worktree", "add", "-q", "-b", "left-behind", left, "origin/main" })
			redesign("An eighth design.")
			local head = fixture.git(left, { "rev-parse", "HEAD" })
			local commits = count()
			local out = must(approve(left))
			t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			t.expect(fixture.git(left, { "rev-parse", "HEAD" })).toBe(head)
			-- and the person's own approve-<id> worktree was never in the way, nor touched
			t.expect(fixture.git(persons, { "log", "-1", "--format=%s" })).toBe("design: Hash the contract.")
		end
	)

	it("publishes a held approval onto main's rows, and loses none of them", function()
		-- a prep whose approval.md never had main's earlier rows, and whose design reached main without its approval
		fixture.git(f.main, { "fetch", "-q", "origin" })
		local prep = `{f.main}/.worktree/prep-{SLUG}`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", `prep-{SLUG}`, prep, "origin/main" })
		fixture.git(prep, { "rm", "-q", `{ISSUE}/approval.md` })
		fs.writeFile(`{prep}/{ISSUE}/{ID}.md`, doc("A ninth design."))
		fs.writeFile(`{prep}/{PAGE}`, page(doc("A ninth design.")))
		fixture.git(prep, { "add", "-A" })
		fixture.git(prep, { "commit", "-q", "-m", "prep: a ninth design, with no rows" })
		must(approve(f.main))
		t.expect(fs.isFile(`{prep}/{ISSUE}/approval.md`)).toBe(true) -- recorded in the prep worktree
		t.expect(lines(fs.readFile(`{prep}/{ISSUE}/approval.md`))).toBe(3)
		redesign("A ninth design.")
		local earlier = onMain(`{ISSUE}/approval.md`)
		local rows = rowsOnMain()
		local out = must(approve(f.main))
		t.expect(has(out, `{ID}: publishing from .worktree/prep-{SLUG}`)).toBe(true)
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		local now = onMain(`{ISSUE}/approval.md`)
		t.expect(rowsOnMain()).toBe(rows + 1)
		t.expect(string.sub(now, 1, #earlier)).toBe(earlier)
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		t.expect(fixture.exec(f.main, "./zn", { "approve", ID, "--check" }).ok).toBe(true)
	end)

	it(
		"replaces an approval.md on origin/main that does not parse, from the main checkout, in one command",
		function()
			trackerfix.elsewhere(f, {
				[`{ISSUE}/{ID}.md`] = doc("A tenth design."),
				[PAGE] = page(doc("A tenth design.")),
				[`{ISSUE}/approval.md`] = "not an approval\n",
			}, "a tenth design, and an unreadable approval")
			local commits = count()
			local out = must(approve(f.main))
			t.expect(has(out, `{ID}: approving in origin/main`)).toBe(true)
			t.expect(
				has(out, `{ID}: origin/main's {ISSUE}/approval.md does not parse: this approval replaces it`)
			)
				.toBe(true)
			t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			t.expect(rowsOnMain()).toBe(1)
			t.expect(fs.isDir(scratch)).toBe(false)
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			t.expect(fixture.exec(f.main, "./zn", { "approve", ID, "--check" }).ok).toBe(true)
		end
	)
end)
