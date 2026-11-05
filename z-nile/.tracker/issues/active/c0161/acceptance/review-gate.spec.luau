--!strict
-- c0161 AC1: `./zn status <id> prepared` (the move z-design ends on, carried by the prep PR) refuses an issue whose
-- folder has no approving design review round that read the design as it is, so a closure (a defect that does not
-- reproduce, no code change) cannot reach z-raft without one, and neither can a design changed after its approving round
-- (a reviewed fix turned into a closure, a scope reset in place), nor one whose last round only asked for changes. An
-- approving round quoting the design's record passes, whether the files are committed or not. Driven through
-- scripts/tracker.sh in a worktree of a fixture under .cache/c0161-review-gate (tests/lib/trackerfix); the files are
-- written the way a reviewer leaves them, uncommitted.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local f: trackerfix.Fixture
local wt = ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tr(args: { string }): fixture.Result
	return trackerfix.tr(f, wt, args)
end
local function trOk(args: { string }): string
	return trackerfix.trOk(f, wt, args)
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function write(path: string, text: string)
	fs.writeFile(path, text)
end
local function setLine(path: string, key: string, value: string)
	local text = fs.readFile(path)
	local s, e = string.find(text, `\n{key}:[^\n]*\n`)
	assert(s and e, `{path} has no {key}:`)
	write(path, string.sub(text, 1, s) .. `{key}: {value}\n` .. string.sub(text, e + 1))
end
-- the record `./zn design-record <id>` prints for the design as it is now
local function record(id: string): string
	return trOk({ "design-record", id })
end
-- a round as a reviewer leaves it: with the record of the design it read, when it has one to quote
local function round(n: string, verdict: string, hash: string?): string
	local quote = if hash then `\nDesign record: {hash}\n` else ""
	return `# Review {n}: x (design mode)\nInputs: y\n\n### F1 [low] a claim\nWhere: a\nEvidence: b\n\nVerdict: {verdict}\n{quote}`
end

-- a claimed issue of this type with its design ready, as z-design leaves it just before `status <id> prepared`
local function claimed(kind: string, slug: string): (string, string)
	local id = string.match(trOk({ "new", "issue", kind, slug, "--project", "pickman" }), "(%a%d+)") :: string
	trOk({ "status", id, "preparing" })
	local dir = `{wt}/pickman/.tracker/issues/{id}`
	setLine(`{dir}/{id}.md`, "design", "ready")
	return id, dir
end
local function refusedWith(id: string, ...: string)
	local before = tip()
	local r = tr({ "status", id, "prepared" })
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		if not has(r.stderr, needle) then
			error(`status {id} prepared: stderr lacks {needle}: {r.stderr}`, 2)
		end
	end
	t.expect(tip()).toBe(before)
end
local function statusLine(dir: string, id: string): string
	return string.match(fs.readFile(`{dir}/{id}.md`), "\nstatus: (%S+)\n") or ""
end

return t.spec(
	"c0161 the move to prepared needs a reviewer's approving round that read the design",
	function(it)
		it("sets up a fixture and a prep worktree", function()
			f = trackerfix.new("c0161-review-gate", nil)
			wt = trackerfix.trOk(f, f.main, { "worktree", "prep-gate" })
			trOk({ "sync" })
		end)

		it(
			"a closure with design: ready and no review round is refused, naming the issue, the file and the rule",
			function()
				local id, dir = claimed("d", "not-reproduced")
				refusedWith(id, id, "design-review-001.md", "closure")
				t.expect(has(statusLine(dir, id), "prepared")).toBe(false) -- nothing was written
				t.expect(has(statusLine(dir, id), "preparing")).toBe(true)
				-- files that are not design review rounds do not count: a code-mode name, a refute alone, a stray copy
				write(`{dir}/review-001.md`, round("001", "approve", record(id)))
				write(`{dir}/design-refute-001.md`, "- F1: fixed\n")
				write(`{dir}/design-review-001.md.bak`, round("001", "approve", record(id)))
				refusedWith(id, "design-review-001.md")
			end
		)

		it(
			"a round must quote the design record, and an approving round passes alone with it (uncommitted files count)",
			function()
				local id, dir = claimed("c", "no-record")
				write(`{dir}/design-review-001.md`, round("001", "approve"))
				refusedWith(id, id, "design-review-001.md", "Design record", "./zn design-record")
				write(`{dir}/design-review-001.md`, round("001", "approve", record(id)))
				trOk({ "status", id, "prepared" }) -- the files are untracked: the engine reads the work tree as git sees it
				t.expect(string.match(statusLine(dir, id), "^prepared%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
			end
		)

		it(
			"a design changed after its approving round is refused, whatever the change (the closure after a fix design)",
			function()
				local id, dir = claimed("d", "fix-then-closure")
				write(`{dir}/design-review-001.md`, round("001", "approve", record(id)))
				-- the user's retest says it does not reproduce: the author rewrites the Design to a closure
				write(
					`{dir}/{id}.md`,
					fs.readFile(`{dir}/{id}.md`) .. "\n## Design\nNo code change: it does not reproduce.\n"
				)
				refusedWith(id, id, "design-review-001.md", "changed after this round", "needs a new round")
				-- the frontmatter lines the process itself writes do not count; check.sh, a spec and a prototype patch do
				local before = record(id)
				setLine(`{dir}/{id}.md`, "design", "reviewed")
				setLine(`{dir}/{id}.md`, "design", "ready")
				t.expect(record(id)).toBe(before)
				write(`{dir}/check.sh`, fs.readFile(`{dir}/check.sh`) .. "# edited\n")
				t.expect(record(id) ~= before).toBe(true)
				local withCheck = record(id)
				fs.writeDir(`{dir}/experiments`)
				write(`{dir}/experiments/proto.patch`, "a patch the executor applies\n")
				t.expect(record(id) ~= withCheck).toBe(true)
				-- a new round that read the closure passes
				write(`{dir}/design-review-002.md`, round("002", "approve", record(id)))
				trOk({ "status", id, "prepared" })
			end
		)

		it(
			"a round that says changes is never the last: answering it, by a refute or by an edit, needs the next round",
			function()
				local id, dir = claimed("c", "changes-round")
				write(`{dir}/design-review-001.md`, round("001", "changes", record(id)))
				refusedWith(id, id, "design-review-001.md", "Verdict: changes")
				-- every finding answered in a refute, the design edited to answer: still the same refusal
				write(`{dir}/design-refute-001.md`, "- F1: fixed: x; consequences: none\n")
				write(`{dir}/check.sh`, fs.readFile(`{dir}/check.sh`) .. "# fixed\n")
				refusedWith(id, "Verdict: changes", "next round")
				-- the next round, which reads the design as edited and approves, passes
				write(`{dir}/design-review-002.md`, round("002", "approve", record(id)))
				trOk({ "status", id, "prepared" })
			end
		)

		it(
			"a scope reset in place: the earlier scope's rounds, still in the folder, excuse nothing",
			function()
				local id, dir = claimed("c", "reset-in-place")
				for n = 1, 4 do
					local stem = string.format("%03d", n)
					write(`{dir}/design-review-{stem}.md`, round(stem, "changes", "aaaaaaaaaaaa"))
					write(`{dir}/design-refute-{stem}.md`, "- F1: fixed: x; consequences: none\n")
				end
				write(`{dir}/design-review-005.md`, round("005", "approve", "aaaaaaaaaaaa")) -- the earlier scope's approval
				refusedWith(id, "design-review-005.md", "changed after this round")
				write(`{dir}/design-review-006.md`, round("006", "approve", record(id)))
				trOk({ "status", id, "prepared" })
			end
		)

		it("a round with no Verdict line is refused, and the newest round decides", function()
			local id, dir = claimed("c", "two-rounds")
			write(
				`{dir}/design-review-001.md`,
				"# Review 001\n\n### F1 [low] x\nEvidence: Verdict: approve\n"
			)
			refusedWith(id, "design-review-001.md", "Verdict")
			write(`{dir}/design-review-001.md`, round("001", "approve", record(id)))
			write(`{dir}/design-review-002.md`, round("002", "changes", record(id)))
			refusedWith(id, "design-review-002.md") -- round 1's approval does not excuse round 2's changes
			write(`{dir}/design-review-002.md`, round("002", "approve", record(id)))
			trOk({ "status", id, "prepared" })
		end)

		it("a review that was committed counts as well as one that was not", function()
			local id, dir = claimed("c", "committed-round")
			write(`{dir}/design-review-001.md`, round("001", "approve", record(id)))
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", `tracker: prep {id}` })
			trOk({ "status", id, "prepared" })
		end)

		it(
			"a fifth round that says changes is refused too: only a sixth, by the user's decision, that approves passes",
			function()
				local id, dir = claimed("c", "round-five")
				for n = 1, 5 do
					local stem = string.format("%03d", n)
					write(`{dir}/design-review-{stem}.md`, round(stem, "changes", record(id)))
				end
				refusedWith(id, "design-review-005.md", "Verdict: changes")
				write(`{dir}/design-review-006.md`, round("006", "approve", record(id)))
				trOk({ "status", id, "prepared" })
			end
		)
	end
)
