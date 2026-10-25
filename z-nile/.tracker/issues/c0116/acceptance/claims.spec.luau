--!strict
-- c0116 AC1: rafting prepared issues. An issue's raft is its own `raft:` line, written in the rafting worktree and
-- carried by the rafting PR; the published claim stamps the raft only. Two rafting PRs over one issue conflict on that
-- line. `new raft` over prepared issues, `fold`, the carried `status <R> prepared`, `release`, a raft move that never
-- restamps a prepared member, and the orphan a released raft leaves. Driven through scripts/tracker.sh in worktrees of
-- a fixture under .cache/c0116-claims (tests/lib/trackerfix), the way z-raft runs them.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, raft: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 300\n{extra or ""}status: {PREPARED}\n---\n\n# {id}\n`
end
local function draft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-amber-otter-lynx\n---\n\n# {id}\n`
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Landed\nslug: landed\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nLanded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
end

local f: trackerfix.Fixture
local A, B, C, D, E = "", "", "", "", "" -- rafting worktrees, each a terminal of its own
local F, G, H = "", "", "" -- review 001 F1: two raftings and a z-design terminal
local R, R2 = "", ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function originStatus(path: string): string
	return string.match(onOrigin(path) or "", "\nstatus: (%S+)\n") or ""
end
local function tr(cwd: string, args: { string }): fixture.Result
	return trackerfix.tr(f, cwd, args)
end
local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function refused(cwd: string, args: { string }, ...: string)
	local before = tip()
	local r = tr(cwd, args)
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		if not has(r.stderr, needle) then
			error(`{table.concat(args, " ")}: stderr lacks {needle}: {r.stderr}`, 2)
		end
	end
	t.expect(tip()).toBe(before)
end
-- the plain-find replacement of one line of a document (never a Lua pattern on literal text)
local function setLine(path: string, key: string, value: string)
	local text = fs.readFile(path)
	local s, e = string.find(text, `\n{key}:[^\n]*\n`)
	assert(s and e, `{path} has no {key}:`)
	fs.writeFile(path, string.sub(text, 1, s) .. `{key}: {value}\n` .. string.sub(text, e + 1))
end
local function writeDesign(path: string)
	local text = fs.readFile(path)
	text = (string.gsub(text, "## Theme\n<!%-%-.-%-%->", "## Theme\nTwo chores on one surface.", 1))
	text = (string.gsub(text, "## Order & dependencies\n<!%-%-.-%-%->", "## Order & dependencies\nBy id.", 1))
	fs.writeFile(path, text)
end
local function land(wt: string)
	fixture.git(wt, { "fetch", "-q", "origin" })
	fixture.git(wt, { "merge", "-q", "--no-edit", "origin/main" })
	fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
	fixture.git(f.main, { "pull", "-q", "origin", "main" })
end

return t.spec(
	"c0116 rafting prepared issues: the raft: line is the lock, the stamp claims the raft",
	function(it)
		it("sets up prepared, raftless chores, a landed prepared raft and rafting worktrees", function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(".gitignore"),
				["tracker/architecture.md"] = "# Architecture\n",
				["tracker/issues/c0010/c0010.md"] = issue("c0010", ""),
				["tracker/issues/c0020/c0020.md"] = issue("c0020", ""),
				["tracker/issues/c0030/c0030.md"] = draft("c0030"),
				["tracker/issues/c0040/c0040.md"] = issue("c0040", ""),
				["tracker/issues/c0050/c0050.md"] = issue("c0050", "", "solo: true\n"),
				["tracker/issues/c0060/c0060.md"] = issue("c0060", ""),
				["tracker/issues/c0070/c0070.md"] = issue("c0070", "R0090"),
				-- review 001 F1: chores rafted while another terminal re-claims one for design
				["tracker/issues/c0013/c0013.md"] = issue("c0013", ""),
				["tracker/issues/c0014/c0014.md"] = issue("c0014", ""),
				["tracker/issues/c0015/c0015.md"] = issue("c0015", ""),
				["tracker/issues/c0016/c0016.md"] = issue("c0016", ""),
				-- another project's chore, and a feature, both prepared and raftless
				["z-nile/.tracker/issues/c0080/c0080.md"] = issue("c0080", ""),
				["tracker/issues/f0085/f0085.md"] = (
					string.gsub(issue("f0085", ""), "type: chore", "type: feature")
				),
				["tracker/rafts/R0090/R0090.md"] = raftDoc("R0090", "c0070"),
				-- lists c0070, which R0090 holds by its raft: line
				["tracker/rafts/R0100/R0100.md"] = raftDoc("R0100", "c0070"),
			}
			for _, id in
				{
					"c0010",
					"c0020",
					"c0030",
					"c0040",
					"c0050",
					"c0060",
					"c0070",
					"f0085",
					"c0013",
					"c0014",
					"c0015",
					"c0016",
				}
			do
				seed[`tracker/issues/{id}/check.sh`] = CHECK
			end
			seed["z-nile/.tracker/issues/c0080/check.sh"] = CHECK
			seed["tracker/rafts/R0090/check.sh"] = CHECK
			seed["tracker/rafts/R0100/check.sh"] = CHECK
			f = trackerfix.new("c0116-claims", seed)
			A = trOk(f.main, { "worktree", "raft-a" })
			B = trOk(f.main, { "worktree", "raft-b" })
			C = trOk(f.main, { "worktree", "raft-c" })
			D = trOk(f.main, { "worktree", "raft-d" })
			E = trOk(f.main, { "worktree", "raft-e" })
			F = trOk(f.main, { "worktree", "raft-f" })
			G = trOk(f.main, { "worktree", "prep-g" })
			H = trOk(f.main, { "worktree", "raft-h" })
			t.expect(trOk(A, { "status", "c0010" })).toBe("prepared")
		end)

		it(
			"new raft over prepared issues publishes the raft alone and writes raft: only in the worktree",
			function()
				local before = tip()
				local c10, c20 =
					onOrigin("tracker/issues/c0010/c0010.md"), onOrigin("tracker/issues/c0020/c0020.md")
				R =
					string.match(trOk(A, { "new", "raft", "chore", "pair", "c0010", "c0020" }), "(R%d+)") :: string
				-- the members' documents on origin are byte for byte as they were: no restamp, no raft: line
				t.expect(onOrigin("tracker/issues/c0010/c0010.md")).toBe(c10)
				t.expect(onOrigin("tracker/issues/c0020/c0020.md")).toBe(c20)
				local changed = fixture.git(f.origin, { "diff", "--name-only", before, "main" })
				t.expect(has(changed, "tracker/issues/")).toBe(false)
				local claim = originStatus(`tracker/rafts/{R}/{R}.md`)
				t.expect(string.match(claim, "^preparing%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
				-- membership is the worktree's, committed there; the claim is remembered in this checkout
				t.expect(has(fs.readFile(`{A}/tracker/issues/c0010/c0010.md`), `\nraft: {R}\n`)).toBe(true)
				t.expect(has(fs.readFile(`{A}/tracker/issues/c0010/c0010.md`), `\nstatus: {PREPARED}\n`))
					.toBe(true)
				t.expect(fixture.git(A, { "status", "--porcelain" })).toBe("")
				t.expect(fixture.git(A, { "log", "-1", "--format=%s" })).toBe(`tracker: {R} members`)
				t.expect(fs.isFile(`{A}/.cache/tracker-claim-{R}`)).toBe(true)
				t.expect((string.gsub(fs.readFile(`{A}/.cache/tracker-claim-{R}`), "%s+$", ""))).toBe(claim)
			end
		)

		it("new raft refuses new and prepared issues together, and a solo issue with others", function()
			refused(B, { "new", "raft", "chore", "mix", "c0030", "c0040" }, "not both")
			refused(B, { "new", "raft", "chore", "solo", "c0040", "c0050" }, "c0050", "solo")
			refused(B, { "fold", "R0090", "c0050" }, "c0050", "solo")
			-- the tracker's rules hold for fold too: one project, one type
			refused(B, { "fold", "R0090", "c0080" }, "c0080", "one project")
			refused(B, { "fold", "R0090", "f0085" }, "f0085", "feature")
		end)

		it(
			"the carried move needs the raft's Theme, Order and coherence review, then takes prepared members as they are",
			function()
				local doc = `{A}/tracker/rafts/{R}/{R}.md`
				setLine(doc, "design", "ready")
				local before = tip()
				local noTheme = tr(A, { "status", R, "prepared" })
				t.expect(noTheme.ok).toBe(false)
				t.expect(has(noTheme.stderr, "Theme")).toBe(true)
				writeDesign(doc)
				local noReview = tr(A, { "status", R, "prepared" })
				t.expect(noReview.ok).toBe(false)
				t.expect(has(noReview.stderr, "coherence review")).toBe(true)
				fs.writeFile(
					`{A}/tracker/rafts/{R}/design-review-001.md`,
					"# Review 001\n\nVerdict: approve\n"
				)
				trOk(A, { "status", R, "prepared" })
				t.expect(tip()).toBe(before) -- carried: nothing published
				t.expect(string.match(fs.readFile(doc), "\nstatus: prepared%-%a+%-%a+%-%a+\n") ~= nil)
					.toBe(true)
				t.expect(has(fs.readFile(`{A}/tracker/issues/c0010/c0010.md`), `\nstatus: {PREPARED}\n`))
					.toBe(true)
				fixture.git(A, { "add", "-A" })
				fixture.git(A, { "commit", "-q", "-m", `tracker: raft {R}` })
			end
		)

		it(
			"a second rafting of the same issue publishes, then conflicts on its raft: line once the first lands",
			function()
				R2 =
					string.match(trOk(B, { "new", "raft", "chore", "steal", "c0010", "--single" }), "(R%d+)") :: string
				t.expect(R2 ~= R).toBe(true)
				land(A) -- the first rafting PR merges
				t.expect(has(onOrigin("tracker/issues/c0010/c0010.md"), `\nraft: {R}\n`)).toBe(true)
				fixture.git(B, { "fetch", "-q", "origin" })
				local merged = fixture.exec(B, "git", { "merge", "--no-edit", "origin/main" })
				t.expect(merged.ok).toBe(false)
				t.expect(
					has(merged.stdout, "CONFLICT (content): Merge conflict in tracker/issues/c0010/c0010.md")
				)
					.toBe(true)
				fixture.git(B, { "merge", "--abort" })
				-- and the carried move, which reads origin's raft: line, refuses it early, naming the raft that holds it
				local doc = `{B}/tracker/rafts/{R2}/{R2}.md`
				setLine(doc, "design", "ready")
				writeDesign(doc)
				refused(B, { "status", R2, "prepared" }, "c0010", R)
				fixture.git(B, { "checkout", "-q", "--", "." })
			end
		)

		it(
			"release gives a new raft's claim back, publishing only that raft, and leaves an orphan audit names",
			function()
				local before = tip()
				local c10 = onOrigin("tracker/issues/c0010/c0010.md")
				trOk(B, { "release", R2 })
				local changed =
					string.split(fixture.git(f.origin, { "diff", "--name-only", before, "main" }), "\n")
				t.expect(changed).toEqual({ `tracker/rafts/{R2}/{R2}.md` })
				t.expect(fixture.git(f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
				t.expect(string.match(originStatus(`tracker/rafts/{R2}/{R2}.md`), "^new%-") ~= nil).toBe(true)
				t.expect(onOrigin("tracker/issues/c0010/c0010.md")).toBe(c10)
				t.expect(fs.isFile(`{B}/.cache/tracker-claim-{R2}`)).toBe(false)
				fixture.git(f.main, { "pull", "-q", "origin", "main" })
				local audit = tr(f.main, { "audit" }).stdout -- the fixture has no counter: audit exits 1 for that alone
				local line: string? = nil
				for l in string.gmatch(audit, "[^\n]+") do
					if has(l, "orphan-raft") then
						line = l
					end
				end
				t.expect(line ~= nil and has(line, R2) and has(line, "recombine")).toBe(true)
			end
		)

		it(
			"fold claims a prepared raft alone and once; another terminal, ready and a second claim are refused",
			function()
				local before = tip()
				local texts: { [string]: string? } = {}
				for _, id in { "c0010", "c0020", "c0040" } do
					texts[id] = onOrigin(`tracker/issues/{id}/{id}.md`)
				end
				trOk(C, { "fold", R, "c0040" })
				t.expect(fixture.git(f.origin, { "diff", "--name-only", before, "main" }))
					.toBe(`tracker/rafts/{R}/{R}.md`)
				t.expect(string.match(originStatus(`tracker/rafts/{R}/{R}.md`), "^preparing%-") ~= nil)
					.toBe(true)
				for id, text in texts do
					t.expect(onOrigin(`tracker/issues/{id}/{id}.md`)).toBe(text)
				end
				t.expect(has(fs.readFile(`{C}/tracker/issues/c0040/c0040.md`), `\nraft: {R}\n`)).toBe(true)
				t.expect(
					has(fs.readFile(`{C}/tracker/rafts/{R}/{R}.md`), "\nissues: [c0010, c0020, c0040]\n")
				)
					.toBe(true)
				-- this checkout's own claim is resumed: a second fold publishes nothing
				local mid = tip()
				trOk(C, { "fold", R, "c0060" })
				t.expect(tip()).toBe(mid)
				t.expect(
					has(
						fs.readFile(`{C}/tracker/rafts/{R}/{R}.md`),
						"\nissues: [c0010, c0020, c0040, c0060]\n"
					)
				)
					.toBe(true)
				refused(D, { "fold", R, "c0060" }, R, "preparing")
				refused(D, { "status", R, "preparing" }, "cannot move")
				fixture.git(f.main, { "pull", "-q", "origin", "main" })
				refused(f.main, { "ready", R }, R, "preparing")
			end
		)

		it(
			"release refuses another checkout's claim, and gives a fold back to prepared with its old members",
			function()
				refused(D, { "release", R }, "not this checkout's")
				trOk(C, { "release", R })
				t.expect(trOk(C, { "status", R })).toBe("prepared")
				t.expect(string.match(originStatus(`tracker/rafts/{R}/{R}.md`), "^prepared%-") ~= nil)
					.toBe(true)
				t.expect(has(onOrigin(`tracker/rafts/{R}/{R}.md`), "\nissues: [c0010, c0020]\n")).toBe(true)
				fixture.git(C, { "reset", "-q", "--hard", "origin/main" })
			end
		)

		it("a fold lands with its coherence review, and ready then claims the folded issue", function()
			trOk(C, { "fold", R, "c0040" })
			local doc = `{C}/tracker/rafts/{R}/{R}.md`
			-- a coherence review already on origin does not count: this rafting needs its own
			local stale = tr(C, { "status", R, "prepared" })
			t.expect(stale.ok).toBe(false)
			t.expect(has(stale.stderr, "coherence review")).toBe(true)
			fs.writeFile(`{C}/tracker/rafts/{R}/design-review-002.md`, "# Review 002\n\nVerdict: approve\n")
			trOk(C, { "status", R, "prepared" })
			t.expect(string.match(fs.readFile(doc), "\nstatus: prepared%-") ~= nil).toBe(true)
			fixture.git(C, { "add", "-A" })
			fixture.git(C, { "commit", "-q", "-m", `tracker: fold c0040 into {R}` })
			land(C)
			trOk(f.main, { "ready", R })
			t.expect(onOrigin("tracker/issues/active/c0040/c0040.md") ~= nil).toBe(true)
			-- an active raft is never folded into
			fixture.git(D, { "fetch", "-q", "origin" })
			fixture.git(D, { "reset", "-q", "--hard", "origin/main" })
			refused(D, { "fold", R, "c0060" }, R, "backlog")
			t.expect(string.match(originStatus("tracker/issues/active/c0040/c0040.md"), "^active%-") ~= nil)
				.toBe(true)
		end)

		it("a raft move never restamps a prepared member, and release needs the claim or --force", function()
			local c70 = onOrigin("tracker/issues/c0070/c0070.md")
			trOk(E, { "status", "R0090", "preparing" })
			t.expect(string.match(originStatus("tracker/rafts/R0090/R0090.md"), "^preparing%-") ~= nil)
				.toBe(true)
			t.expect(onOrigin("tracker/issues/c0070/c0070.md")).toBe(c70)
			refused(E, { "status", "R0090", "preparing" }, "cannot move")
			refused(E, { "release", "R0090" }, "not this checkout's")
			trOk(E, { "release", "R0090", "--force" })
			t.expect(string.match(originStatus("tracker/rafts/R0090/R0090.md"), "^prepared%-") ~= nil)
				.toBe(true)
			t.expect(onOrigin("tracker/issues/c0070/c0070.md")).toBe(c70)
		end)

		it(
			"a raft move refuses a listed member that another raft holds by its raft: line, naming that raft",
			function()
				refused(E, { "status", "R0100", "preparing" }, "c0070", "R0090")
			end
		)

		it(
			"a member re-claimed for design during a rafting is refused by the carried move, naming that claim",
			function()
				local RX = string.match(
					trOk(F, { "new", "raft", "chore", "race", "c0013", "c0014" }),
					"(R%d+)"
				) :: string
				-- z-design in another terminal claims c0013: nothing on origin says it is being rafted, so this succeeds
				trOk(G, { "status", "c0013", "preparing" })
				local claim = originStatus("tracker/issues/c0013/c0013.md")
				t.expect(string.match(claim, "^preparing%-") ~= nil).toBe(true)
				trOk(F, { "sync" }) -- the claim's status line merges in cleanly
				local doc = `{F}/tracker/rafts/{RX}/{RX}.md`
				setLine(doc, "design", "ready")
				writeDesign(doc)
				fs.writeFile(
					`{F}/tracker/rafts/{RX}/design-review-001.md`,
					"# Review 001\n\nVerdict: approve\n"
				)
				refused(F, { "status", RX, "prepared" }, "c0013", "claimed by another terminal", claim)
				t.expect(originStatus("tracker/issues/c0013/c0013.md")).toBe(claim)
				-- the rafting drops it and prepares the rest
				setLine(doc, "issues", "[c0014]")
				setLine(`{F}/tracker/issues/c0013/c0013.md`, "raft", "")
				trOk(F, { "status", RX, "prepared" })
				fixture.git(F, { "add", "-A" })
				fixture.git(F, { "commit", "-q", "-m", `tracker: raft {RX}` })
				land(F)
				-- once the rafting has landed, z-design can no longer claim a member past its raft
				refused(G, { "status", "c0014", "preparing" }, "c0014", RX, "z-raft takes it out")
				trOk(f.main, { "ready", RX })
				t.expect(onOrigin("tracker/issues/active/c0014/c0014.md") ~= nil).toBe(true)
				t.expect(originStatus("tracker/issues/c0013/c0013.md")).toBe(claim)
			end
		)

		it("a member claimed after the carried move but before the landing keeps ready refused", function()
			local RY =
				string.match(trOk(H, { "new", "raft", "chore", "late", "c0015", "c0016" }), "(R%d+)") :: string
			local doc = `{H}/tracker/rafts/{RY}/{RY}.md`
			setLine(doc, "design", "ready")
			writeDesign(doc)
			fs.writeFile(`{H}/tracker/rafts/{RY}/design-review-001.md`, "# Review 001\n\nVerdict: approve\n")
			trOk(H, { "status", RY, "prepared" })
			fixture.git(H, { "add", "-A" })
			fixture.git(H, { "commit", "-q", "-m", `tracker: raft {RY}` })
			trOk(G, { "status", "c0016", "preparing" }) -- c0016's raft: is still empty on origin
			land(H)
			refused(f.main, { "ready", RY }, "c0016", "preparing")
		end)
	end
)
