--!strict
-- f0417 AC7, AC9: `./zn assume` writes assumptions.md in a worktree and commits nothing, `./zn assumptions` and
-- `./zn approve --check` name an assumption added after the approval, and `./zn refuse` is a person's command.
-- Real git in a fixture under .cache (trackerfix): the seed stamps an approval on the design-ready issue c0010.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function doc(id: string, design: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: {design}\ncreated: 2026-11-18\nstatus: {status}\n---\n\n# {id}\n\n## Problem\np\n\n## Solution\ns\n\n## Design\nd\n\n## Acceptance criteria\n- AC1: ok\n\n## Test plan\nt\n\n## Open to the human\nnone\n`
end

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return `{r.stdout}{r.stderr}`
end

local f: trackerfix.Fixture = nil :: any
local made = false
local wt = ""

local function setup()
	if made then
		return
	end
	made = true
	local seed: { [string]: string } = {}
	seed[`{ROOT}/issues/c0010/c0010.md`] = doc("c0010", "ready", "prepared-quiet-copper-falcon")
	seed[`{ROOT}/issues/c0010/check.sh`] = CHECK
	seed[`{ROOT}/issues/done/c0020/c0020.md`] = doc("c0020", "ready", "done-quiet-copper-falcon")
	seed[`{ROOT}/issues/done/c0020/check.sh`] = CHECK
	seed[`{ROOT}/issues/c0030/c0030.md`] = doc("c0030", "draft", "new-quiet-copper-falcon")
	seed[`{ROOT}/issues/c0030/check.sh`] = CHECK
	-- two challenged tickets whose one idea round was answered: c0040 from before the cut-over, c0050 marked from birth
	local REV = "# Idea review 001\n\n## Findings\n- F1: too big.\n\n## Verdict\nrevise\n"
	for _, row in { { "c0040", "" }, { "c0050", "rounds: on\n" } } do
		local id = row[1]
		seed[`{ROOT}/issues/{id}/{id}.md`] = (
			string.gsub(
				doc(id, "draft", "new-quiet-copper-falcon"),
				"\nstatus: ",
				`\nidea: challenged\n{row[2]}status: `
			)
		)
		seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
		seed[`{ROOT}/issues/{id}/idea-review-001.md`] = REV
		seed[`{ROOT}/issues/{id}/idea-refute-001.md`] = "# Idea refute 001\n\n- F1: revised\n"
	end
	-- a prepared, marked issue whose design loop ended: claimed again, it starts a new design loop
	seed[`{ROOT}/issues/c0060/c0060.md`] = (
		string.gsub(
			doc("c0060", "ready", "prepared-quiet-copper-falcon"),
			"\nstatus: ",
			"\nrounds: on\nstatus: "
		)
	)
	seed[`{ROOT}/issues/c0060/check.sh`] = CHECK
	seed[`{ROOT}/issues/c0060/design-review-001.md`] =
		"# Review 001: c0060 (design mode)\nInputs: x\n\nVerdict: approve\n"
	-- an older prepared issue reviewed under the one-round rule: the claim that adopts it starts a new design loop
	seed[`{ROOT}/issues/c0070/c0070.md`] = doc("c0070", "ready", "prepared-quiet-copper-falcon")
	seed[`{ROOT}/issues/c0070/check.sh`] = CHECK
	seed[`{ROOT}/issues/c0070/design-review-001.md`] =
		"# Review 001: c0070 (design mode)\nInputs: x\n\n### F1 [medium] a claim\nWhere: x\nErred: z-design\nUpstream: none\n\nVerdict: changes\n"
	seed[`{ROOT}/issues/c0070/design-refute-001.md`] =
		"# Refute 001\n\n- F1: fixed: done; consequences: none\n"
	-- an older unchallenged ticket, unmarked and raftless: work next carries it through the idea stage
	seed[`{ROOT}/issues/c0080/c0080.md`] = (
		string.gsub(
			doc("c0080", "draft", "new-quiet-copper-falcon"),
			"\nstatus: ",
			"\nidea: unchallenged\nstatus: "
		)
	)
	seed[`{ROOT}/issues/c0080/check.sh`] = CHECK
	-- the cut-over file: while origin/main holds it, new stubs and claims are marked (fixtures never copy it)
	seed["z-nile/.tracker/rounds-since"] = "f0417: reviews go back and forth from here\n"
	f = trackerfix.new("f0417-cli", seed)
	wt = `{f.base}/prep`
	fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-f0417", wt, "HEAD" })
end

local function human(dir: string, args: { string }): fixture.Result
	local argv = { "-q", "/dev/null", "./zn" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "script", argv)
end

local function onOrigin(path: string): string
	return fixture.git(f.origin, { "show", `main:{path}` })
end

local function review(n: string, verdict: string, severity: string): string
	return `# Review {n}: c0030 (design mode)\nInputs: x\n\n### F1 [{severity}] a claim\nWhere: x\nErred: z-design\nUpstream: none\n\nVerdict: {verdict}\n`
end

local function assume(dir: string, id: string, step: string, what: string): fixture.Result
	return trackerfix.tr(f, dir, {
		"assume",
		id,
		"--step",
		step,
		"--what",
		what,
		"--because",
		"Its docs say so.",
		"--unproven",
		"A run that shows otherwise.",
	})
end

return t.spec("f0417: assume, assumptions and refuse", function(it)
	it("assume appends a line in a worktree and commits nothing", function()
		setup()
		local head = fixture.git(wt, { "rev-parse", "HEAD" })
		local r = assume(wt, "c0010", "design", "Ten calls fit.")
		if not r.ok then
			error(`./zn assume failed ({r.code}): {say(r)}`)
		end
		local file = `{wt}/{ROOT}/issues/c0010/assumptions.md`
		t.expect(fs.isFile(file)).toBe(true)
		local text = fs.readFile(file)
		local date = string.match(text, "^# assumptions\n%- A1 %(design, (%d%d%d%d%-%d%d%-%d%d)%): ")
		t.expect(date ~= nil).toBe(true)
		t.expect(text).toBe(
			`# assumptions\n- A1 (design, {date}): Ten calls fit. Because: Its docs say so. Unproven: A run that shows otherwise.\n`
		)
		t.expect(fixture.git(wt, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(has(fixture.git(wt, { "status", "--porcelain" }), "assumptions.md")).toBe(true)
		local two = assume(wt, "c0010", "build", "Git sorts names.")
		t.expect(two.ok).toBe(true)
		t.expect(has(fs.readFile(file), "\n- A2 (build, ")).toBe(true)
	end)

	it("assume refuses the main checkout, a done issue, a bad step and an empty field", function()
		setup()
		local main = assume(f.main, "c0010", "design", "x.")
		t.expect(main.ok).toBe(false)
		t.expect(fs.isFile(`{f.main}/{ROOT}/issues/c0010/assumptions.md`)).toBe(false)
		local done = assume(wt, "c0020", "design", "x.")
		t.expect(done.ok).toBe(false)
		t.expect(has(say(done), "c0020")).toBe(true)
		local step = assume(wt, "c0010", "deploy", "x.")
		t.expect(step.ok).toBe(false)
		t.expect(has(say(step), "idea|design|raft|build")).toBe(true)
		local empty = assume(wt, "c0010", "design", "")
		t.expect(empty.ok).toBe(false)
	end)

	it(
		"assumptions prints the count and whether the approval holds, and approve --check names the assumptions part",
		function()
			setup()
			if not fs.isFile(`{wt}/{ROOT}/issues/c0010/assumptions.md`) then
				assume(wt, "c0010", "design", "Ten calls fit.")
			end
			local r = trackerfix.tr(f, wt, { "assumptions", "c0010" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "c0010: ")).toBe(true)
			t.expect(has(r.stdout, "assumptions, changed since approval (assumptions)")).toBe(true)
			t.expect(has(r.stdout, "- A1 (design, ")).toBe(true)
			local check = trackerfix.tr(f, wt, { "approve", "c0010", "--check" })
			t.expect(has(say(check), "assumptions")).toBe(true)
			-- a broken file is refused by --check
			fs.writeFile(`{wt}/{ROOT}/issues/c0010/assumptions.md`, "# assumptions\n- A2 (x): y\n")
			t.expect(trackerfix.tr(f, wt, { "assumptions", "c0010", "--check" }).ok).toBe(false)
			fixture.git(wt, { "checkout", "-q", "--", "." })
			fs.removeFile(`{wt}/{ROOT}/issues/c0010/assumptions.md`)
		end
	)

	it("a new stub is marked, and a claim marks an older issue on origin", function()
		setup()
		local created = trackerfix.tr(
			f,
			wt,
			{ "new", "issue", "c", "marked-stub", "--project", "pickman", "--desc", "x" }
		)
		if not created.ok then
			error(`./zn new failed ({created.code}): {say(created)}`)
		end
		local path = string.match(created.stdout, "(pickman/%.tracker/issues/c%d+/c%d+%.md)") :: string
		t.expect(has(onOrigin(path), "\nrounds: on\n")).toBe(true)
		local claim = trackerfix.tr(f, wt, { "status", "c0030", "preparing" })
		if not claim.ok then
			error(`./zn status c0030 preparing failed ({claim.code}): {say(claim)}`)
		end
		local published = onOrigin(`{ROOT}/issues/c0030/c0030.md`)
		t.expect(has(published, "\nrounds: on\n")).toBe(true)
		t.expect(has(published, "\nstatus: preparing-")).toBe(true)
	end)

	it(
		"prepared refuses a lost mark and a design loop that has not ended, and takes an approving last round",
		function()
			setup()
			trackerfix.tr(f, wt, { "sync" })
			local dir = `{wt}/{ROOT}/issues/c0030`
			local marked = fs.readFile(`{dir}/c0030.md`)
			t.expect(has(marked, "\nrounds: on\n")).toBe(true)
			local ready = (string.gsub(marked, "design: draft", "design: ready"))
			fs.writeFile(`{dir}/c0030.md`, (string.gsub(ready, "\nrounds: on", "")))
			local lost = trackerfix.tr(f, wt, { "status", "c0030", "prepared" })
			t.expect(lost.ok).toBe(false)
			t.expect(has(say(lost), "rounds: on was published and cannot be removed")).toBe(true)
			fs.writeFile(`{dir}/c0030.md`, ready)
			fs.writeFile(`{dir}/design-review-001.md`, review("001", "changes", "medium"))
			fs.writeFile(
				`{dir}/design-refute-001.md`,
				"# Refute 001\n\n- F1: fixed: done; consequences: none\n"
			)
			local open = trackerfix.tr(f, wt, { "status", "c0030", "prepared" })
			t.expect(open.ok).toBe(false)
			t.expect(has(say(open), "the design loop has not ended")).toBe(true)
			t.expect(has(say(open), "design-review-002")).toBe(true)
			fs.writeFile(`{dir}/design-review-002.md`, review("002", "approve", "low"))
			fs.writeFile(`{dir}/design-refute-002.md`, "# Refute 002\n\n- F1: refuted: the design says so\n")
			local done = trackerfix.tr(f, wt, { "status", "c0030", "prepared" })
			if not done.ok then
				error(`./zn status c0030 prepared failed ({done.code}): {say(done)}`)
			end
			t.expect(has(fs.readFile(`{dir}/c0030.md`), "\nstatus: prepared-")).toBe(true)
		end
	)

	it("refuse, run by a person, refuses an issue that is done or new, naming the way", function()
		setup()
		local done = human(wt, { "refuse", "c0020", "--to", "design", "--why", "Not what I asked." })
		t.expect(done.ok).toBe(false)
		t.expect(has(say(done), "c0020 is done")).toBe(true)
		local fresh =
			trackerfix.tr(f, wt, { "new", "issue", "c", "fresh-idea", "--project", "pickman", "--desc", "x" })
		local id = string.match(fresh.stdout, "issues/(c%d+)/") :: string
		local new = human(wt, { "refuse", id, "--to", "idea", "--why", "Louder." })
		t.expect(new.ok).toBe(false)
		t.expect(has(say(new), `./zn idea {id} --record`)).toBe(true)
	end)

	it(
		"an older challenged ticket is claimed as before and marked; one marked from birth waits for its idea loop",
		function()
			setup()
			local old = trackerfix.tr(f, wt, { "status", "c0040", "preparing" })
			if not old.ok then
				error(`./zn status c0040 preparing failed ({old.code}): {say(old)}`)
			end
			t.expect(has(onOrigin(`{ROOT}/issues/c0040/c0040.md`), "\nrounds: on\n")).toBe(true)
			local born = trackerfix.tr(f, wt, { "status", "c0050", "preparing" })
			t.expect(born.ok).toBe(false)
			t.expect(has(say(born), "idea-review-002")).toBe(true)
			t.expect(has(onOrigin(`{ROOT}/issues/c0050/c0050.md`), "\nstatus: new-")).toBe(true)
			-- and work next takes it to its idea stage, never to a draft the claim refuses
			local next = trackerfix.tr(f, wt, { "work", "next", "c0050" })
			t.expect(has(next.stdout, "c0050: idea - ")).toBe(true)
			t.expect(has(next.stdout, "c0050: draft - ")).toBe(false)
		end
	)

	it(
		"a claim of an ended design loop publishes its new-loop line with the claim, as the last section",
		function()
			setup()
			local r = trackerfix.tr(f, wt, { "status", "c0060", "preparing" })
			if not r.ok then
				error(`./zn status c0060 preparing failed ({r.code}): {say(r)}`)
			end
			local published = onOrigin(`{ROOT}/issues/c0060/c0060.md`)
			local at = string.find(published, "\n## Loops\n", 1, true)
			t.expect(at ~= nil).toBe(true)
			local tail = string.sub(published, at :: number)
			t.expect(
				string.match(
					tail,
					"^\n## Loops\n%- Loop %(tool, %d%d%d%d%-%d%d%-%d%d%): a new design loop from design%-review%-002%s*$"
				) ~= nil
			).toBe(true)
			t.expect((string.find(string.sub(tail, 2), "\n## ", 1, true))).toBe(nil) -- the last section
			-- a copy that dropped origin's Loops line is refused at prepared, before any window is read
			trackerfix.tr(f, wt, { "sync" })
			local file = `{wt}/{ROOT}/issues/c0060/c0060.md`
			local local_ = fs.readFile(file)
			fs.writeFile(file, (string.gsub(local_, "\n## Loops\n[^\n]*\n?", "\n")))
			local dropped = trackerfix.tr(f, wt, { "status", "c0060", "prepared" })
			t.expect(dropped.ok).toBe(false)
			t.expect(has(say(dropped), "./zn sync")).toBe(true)
			fs.writeFile(file, local_)
			-- restored, the window starts at design-review-002: the old approval of 001 does not prepare the redesign
			local fresh = trackerfix.tr(f, wt, { "status", "c0060", "prepared" })
			t.expect(fresh.ok).toBe(false)
			t.expect(has(say(fresh), "design-review-002")).toBe(true)
			fs.writeFile(
				`{wt}/{ROOT}/issues/c0060/design-review-002.md`,
				"# Review 002: c0060 (design mode)\nInputs: x\n\nVerdict: approve\n"
			)
			local prepared = trackerfix.tr(f, wt, { "status", "c0060", "prepared" })
			if not prepared.ok then
				error(`./zn status c0060 prepared failed ({prepared.code}): {say(prepared)}`)
			end
		end
	)

	it(
		"the claim that adopts an older reviewed issue publishes the mark and a new design loop from the next round",
		function()
			setup()
			local r = trackerfix.tr(f, wt, { "status", "c0070", "preparing" })
			if not r.ok then
				error(`./zn status c0070 preparing failed ({r.code}): {say(r)}`)
			end
			local published = onOrigin(`{ROOT}/issues/c0070/c0070.md`)
			t.expect(has(published, "\nrounds: on\n")).toBe(true)
			t.expect(has(published, "): a new design loop from design-review-002")).toBe(true)
		end
	)

	it("work next names an unchallenged ticket's idea stage, read from origin by workread", function()
		setup()
		local r = trackerfix.tr(f, wt, { "work", "next", "c0080" })
		if not r.ok then
			error(`./zn work next c0080 failed ({r.code}): {say(r)}`)
		end
		t.expect(has(r.stdout, "c0080: idea - ")).toBe(true)
		t.expect(has(r.stdout, "./zn idea c0080 --guess")).toBe(true)
	end)

	it("refuse is refused under ZN_DISPATCH and without a terminal", function()
		setup()
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		local args = { "refuse", "c0010", "--to", "design", "--why", "Not what I asked." }
		local dispatched = trackerfix.tr(f, wt, args, { ZN_DISPATCH = "1" })
		t.expect(dispatched.ok).toBe(false)
		t.expect(has(say(dispatched), "refused while ZN_DISPATCH is set")).toBe(true)
		local noTerminal = trackerfix.tr(f, wt, args)
		t.expect(noTerminal.ok).toBe(false)
		t.expect(has(say(noTerminal), "without a terminal")).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
		local badTo = trackerfix.tr(f, wt, { "refuse", "c0010", "--to", "deploy", "--why", "x" })
		t.expect(badTo.ok).toBe(false)
		t.expect(has(say(badTo), "idea|design|build")).toBe(true)
	end)
end)
