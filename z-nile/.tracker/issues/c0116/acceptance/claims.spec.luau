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
local J, K, L, M, N, O = "", "", "", "", "", "" -- review 002
local P, Q, S, U, V, X = "", "", "", "", "", "" -- review 003
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

-- a coherence review of the raft's current record (zz-review raft mode quotes it), review 003 F2
local function coherence(dir: string, n: string)
	local id = string.match(dir, "(R%d+)$") :: string
	local grouped = string.match(fs.readFile(`{dir}/{id}.md`), "\ngrouped: ([^\n]*)\n") or "[]"
	fs.writeFile(`{dir}/design-review-{n}.md`, `# Review {n}\n\nGrouped: {grouped}\n\nVerdict: approve\n`)
end

return t.spec(
	"c0116 rafting prepared issues: the raft: line is the lock, the stamp claims the raft",
	function(it)
		it("sets up prepared, raftless chores, a landed prepared raft and rafting worktrees", function()
			local seed: { [string]: string } = {
				[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
				["pickman/.tracker/architecture.md"] = "# Architecture\n",
				["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", ""),
				["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", ""),
				["pickman/.tracker/issues/c0030/c0030.md"] = draft("c0030"),
				["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", ""),
				["pickman/.tracker/issues/c0050/c0050.md"] = issue("c0050", "", "solo: true\n"),
				["pickman/.tracker/issues/c0060/c0060.md"] = issue("c0060", ""),
				["pickman/.tracker/issues/c0070/c0070.md"] = issue("c0070", "R0090"),
				-- review 001 F1: chores rafted while another terminal re-claims one for design
				["pickman/.tracker/issues/c0013/c0013.md"] = issue("c0013", ""),
				["pickman/.tracker/issues/c0014/c0014.md"] = issue("c0014", ""),
				["pickman/.tracker/issues/c0015/c0015.md"] = issue("c0015", ""),
				["pickman/.tracker/issues/c0016/c0016.md"] = issue("c0016", ""),
				-- review 002: redesigns inside the rafting window, the unfold route, and release of remembered claims
				["pickman/.tracker/issues/c0021/c0021.md"] = issue("c0021", ""),
				["pickman/.tracker/issues/c0022/c0022.md"] = issue("c0022", ""),
				["pickman/.tracker/issues/c0023/c0023.md"] = issue("c0023", ""),
				["pickman/.tracker/issues/c0024/c0024.md"] = issue("c0024", ""),
				["pickman/.tracker/issues/c0025/c0025.md"] = draft("c0025"),
				["pickman/.tracker/issues/c0026/c0026.md"] = draft("c0026"),
				-- review 003: redesigns of check.sh and specs, re-folding, an empty record, a fold window
				["pickman/.tracker/issues/c0031/c0031.md"] = issue("c0031", ""),
				["pickman/.tracker/issues/c0032/c0032.md"] = issue("c0032", ""),
				["pickman/.tracker/issues/c0033/c0033.md"] = issue("c0033", ""),
				["pickman/.tracker/issues/c0034/c0034.md"] = issue("c0034", ""),
				["pickman/.tracker/issues/c0035/c0035.md"] = issue("c0035", ""),
				["pickman/.tracker/issues/c0036/c0036.md"] = issue("c0036", ""),
				["pickman/.tracker/issues/c0037/c0037.md"] = issue("c0037", ""),
				["pickman/.tracker/issues/c0038/c0038.md"] = issue("c0038", ""),
				["pickman/.tracker/issues/c0039/c0039.md"] = issue("c0039", ""),
				["pickman/.tracker/issues/c0041/c0041.md"] = issue("c0041", ""),
				["pickman/.tracker/rafts/R0110/R0110.md"] = raftDoc("R0110", ""),
				-- another project's chore, and a feature, both prepared and raftless
				["z-nile/.tracker/issues/c0080/c0080.md"] = issue("c0080", ""),
				["pickman/.tracker/issues/f0085/f0085.md"] = (
					string.gsub(issue("f0085", ""), "type: chore", "type: feature")
				),
				["pickman/.tracker/rafts/R0090/R0090.md"] = raftDoc("R0090", "c0070"),
				-- lists c0070, which R0090 holds by its raft: line
				["pickman/.tracker/rafts/R0100/R0100.md"] = raftDoc("R0100", "c0070"),
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
				seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
			end
			for _, id in { "c0021", "c0022", "c0023", "c0024", "c0025", "c0026" } do
				seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
			end
			for _, id in
				{ "c0031", "c0032", "c0033", "c0034", "c0035", "c0036", "c0037", "c0038", "c0039", "c0041" }
			do
				seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
			end
			seed["pickman/.tracker/rafts/R0110/check.sh"] = CHECK
			seed["z-nile/.tracker/issues/c0080/check.sh"] = CHECK
			seed["pickman/.tracker/rafts/R0090/check.sh"] = CHECK
			seed["pickman/.tracker/rafts/R0100/check.sh"] = CHECK
			f = trackerfix.new("c0116-claims", seed)
			A = trOk(f.main, { "worktree", "raft-a" })
			B = trOk(f.main, { "worktree", "raft-b" })
			C = trOk(f.main, { "worktree", "raft-c" })
			D = trOk(f.main, { "worktree", "raft-d" })
			E = trOk(f.main, { "worktree", "raft-e" })
			F = trOk(f.main, { "worktree", "raft-f" })
			G = trOk(f.main, { "worktree", "prep-g" })
			H = trOk(f.main, { "worktree", "raft-h" })
			J = trOk(f.main, { "worktree", "raft-j" })
			K = trOk(f.main, { "worktree", "prep-k" })
			L = trOk(f.main, { "worktree", "raft-l" })
			M = trOk(f.main, { "worktree", "prep-m" })
			N = trOk(f.main, { "worktree", "raft-n" })
			O = trOk(f.main, { "worktree", "raft-o" })
			P = trOk(f.main, { "worktree", "raft-p" })
			Q = trOk(f.main, { "worktree", "prep-q" })
			S = trOk(f.main, { "worktree", "raft-s" })
			U = trOk(f.main, { "worktree", "raft-u" })
			V = trOk(f.main, { "worktree", "raft-v" })
			X = trOk(f.main, { "worktree", "raft-x" })
			t.expect(trOk(A, { "status", "c0010" })).toBe("prepared")
		end)

		it(
			"new raft over prepared issues publishes the raft alone and writes raft: only in the worktree",
			function()
				local before = tip()
				local c10, c20 =
					onOrigin("pickman/.tracker/issues/c0010/c0010.md"),
					onOrigin("pickman/.tracker/issues/c0020/c0020.md")
				R = string.match(
					trOk(A, { "new", "raft", "chore", "pair", "c0010", "c0020", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				-- the members' documents on origin are byte for byte as they were: no restamp, no raft: line
				t.expect(onOrigin("pickman/.tracker/issues/c0010/c0010.md")).toBe(c10)
				t.expect(onOrigin("pickman/.tracker/issues/c0020/c0020.md")).toBe(c20)
				local changed = fixture.git(f.origin, { "diff", "--name-only", before, "main" })
				t.expect(has(changed, "pickman/.tracker/issues/")).toBe(false)
				local claim = originStatus(`pickman/.tracker/rafts/{R}/{R}.md`)
				t.expect(string.match(claim, "^preparing%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
				-- membership is the worktree's, committed there; the claim is remembered in this checkout
				t.expect(has(fs.readFile(`{A}/pickman/.tracker/issues/c0010/c0010.md`), `\nraft: {R}\n`))
					.toBe(true)
				t.expect(
					has(fs.readFile(`{A}/pickman/.tracker/issues/c0010/c0010.md`), `\nstatus: {PREPARED}\n`)
				)
					.toBe(true)
				t.expect(fixture.git(A, { "status", "--porcelain" })).toBe("")
				t.expect(fixture.git(A, { "log", "-1", "--format=%s" })).toBe(`tracker: {R} members`)
				t.expect(fs.isFile(`{A}/.cache/tracker-claim-{R}`)).toBe(true)
				t.expect((string.gsub(fs.readFile(`{A}/.cache/tracker-claim-{R}`), "%s+$", ""))).toBe(claim)
			end
		)

		it("new raft refuses new and prepared issues together, and a solo issue with others", function()
			refused(
				B,
				{ "new", "raft", "chore", "mix", "c0030", "c0040", "--project", "pickman" },
				"not both"
			)
			refused(
				B,
				{ "new", "raft", "chore", "solo", "c0040", "c0050", "--project", "pickman" },
				"c0050",
				"solo"
			)
			refused(B, { "fold", "R0090", "c0050" }, "c0050", "solo")
			-- the tracker's rules hold for fold too: one project, one type
			refused(B, { "fold", "R0090", "c0080" }, "c0080", "one project")
			refused(B, { "fold", "R0090", "f0085" }, "f0085", "feature")
		end)

		it(
			"the carried move needs the raft's Theme, Order and coherence review, then takes prepared members as they are",
			function()
				local doc = `{A}/pickman/.tracker/rafts/{R}/{R}.md`
				setLine(doc, "design", "ready")
				local before = tip()
				local noTheme = tr(A, { "status", R, "prepared" })
				t.expect(noTheme.ok).toBe(false)
				t.expect(has(noTheme.stderr, "Theme")).toBe(true)
				writeDesign(doc)
				local noReview = tr(A, { "status", R, "prepared" })
				t.expect(noReview.ok).toBe(false)
				t.expect(has(noReview.stderr, "coherence review")).toBe(true)
				coherence(`{A}/pickman/.tracker/rafts/{R}`, "001")
				trOk(A, { "status", R, "prepared" })
				t.expect(tip()).toBe(before) -- carried: nothing published
				t.expect(string.match(fs.readFile(doc), "\nstatus: prepared%-%a+%-%a+%-%a+\n") ~= nil)
					.toBe(true)
				t.expect(
					has(fs.readFile(`{A}/pickman/.tracker/issues/c0010/c0010.md`), `\nstatus: {PREPARED}\n`)
				)
					.toBe(true)
				fixture.git(A, { "add", "-A" })
				fixture.git(A, { "commit", "-q", "-m", `tracker: raft {R}` })
			end
		)

		it(
			"a second rafting of the same issue publishes, then conflicts on its raft: line once the first lands",
			function()
				R2 = string.match(
					trOk(B, { "new", "raft", "chore", "steal", "c0010", "--single", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				t.expect(R2 ~= R).toBe(true)
				land(A) -- the first rafting PR merges
				t.expect(has(onOrigin("pickman/.tracker/issues/c0010/c0010.md"), `\nraft: {R}\n`)).toBe(true)
				fixture.git(B, { "fetch", "-q", "origin" })
				local merged = fixture.exec(B, "git", { "merge", "--no-edit", "origin/main" })
				t.expect(merged.ok).toBe(false)
				t.expect(
					has(
						merged.stdout,
						"CONFLICT (content): Merge conflict in pickman/.tracker/issues/c0010/c0010.md"
					)
				).toBe(true)
				fixture.git(B, { "merge", "--abort" })
				-- and the carried move, which reads origin's raft: line, refuses it early, naming the raft that holds it
				local doc = `{B}/pickman/.tracker/rafts/{R2}/{R2}.md`
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
				local c10 = onOrigin("pickman/.tracker/issues/c0010/c0010.md")
				trOk(B, { "release", R2 })
				local changed =
					string.split(fixture.git(f.origin, { "diff", "--name-only", before, "main" }), "\n")
				t.expect(changed).toEqual({ `pickman/.tracker/rafts/{R2}/{R2}.md` })
				t.expect(fixture.git(f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
				t.expect(string.match(originStatus(`pickman/.tracker/rafts/{R2}/{R2}.md`), "^new%-") ~= nil)
					.toBe(true)
				t.expect(onOrigin("pickman/.tracker/issues/c0010/c0010.md")).toBe(c10)
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
					texts[id] = onOrigin(`pickman/.tracker/issues/{id}/{id}.md`)
				end
				trOk(C, { "fold", R, "c0040" })
				t.expect(fixture.git(f.origin, { "diff", "--name-only", before, "main" }))
					.toBe(`pickman/.tracker/rafts/{R}/{R}.md`)
				t.expect(
					string.match(originStatus(`pickman/.tracker/rafts/{R}/{R}.md`), "^preparing%-") ~= nil
				)
					.toBe(true)
				for id, text in texts do
					t.expect(onOrigin(`pickman/.tracker/issues/{id}/{id}.md`)).toBe(text)
				end
				t.expect(has(fs.readFile(`{C}/pickman/.tracker/issues/c0040/c0040.md`), `\nraft: {R}\n`))
					.toBe(true)
				t.expect(
					has(
						fs.readFile(`{C}/pickman/.tracker/rafts/{R}/{R}.md`),
						"\nissues: [c0010, c0020, c0040]\n"
					)
				).toBe(true)
				-- this checkout's own claim is resumed: a second fold publishes nothing
				local mid = tip()
				trOk(C, { "fold", R, "c0060" })
				t.expect(tip()).toBe(mid)
				t.expect(
					has(
						fs.readFile(`{C}/pickman/.tracker/rafts/{R}/{R}.md`),
						"\nissues: [c0010, c0020, c0040, c0060]\n"
					)
				).toBe(true)
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
				t.expect(
					string.match(originStatus(`pickman/.tracker/rafts/{R}/{R}.md`), "^prepared%-") ~= nil
				)
					.toBe(true)
				t.expect(has(onOrigin(`pickman/.tracker/rafts/{R}/{R}.md`), "\nissues: [c0010, c0020]\n"))
					.toBe(true)
				fixture.git(C, { "reset", "-q", "--hard", "origin/main" })
			end
		)

		it("a fold lands with its coherence review, and ready then claims the folded issue", function()
			trOk(C, { "fold", R, "c0040" })
			local doc = `{C}/pickman/.tracker/rafts/{R}/{R}.md`
			-- a coherence review already on origin does not count: this rafting needs its own
			local stale = tr(C, { "status", R, "prepared" })
			t.expect(stale.ok).toBe(false)
			t.expect(has(stale.stderr, "coherence review")).toBe(true)
			coherence(`{C}/pickman/.tracker/rafts/{R}`, "002")
			trOk(C, { "status", R, "prepared" })
			t.expect(string.match(fs.readFile(doc), "\nstatus: prepared%-") ~= nil).toBe(true)
			fixture.git(C, { "add", "-A" })
			fixture.git(C, { "commit", "-q", "-m", `tracker: fold c0040 into {R}` })
			land(C)
			-- review 004 F1: an ignored file in a member's folder (Finder's .DS_Store) never changes its record
			fs.writeDir(`{f.main}/pickman/.tracker/issues/c0010/acceptance`)
			fs.writeFile(`{f.main}/pickman/.tracker/issues/c0010/acceptance/.DS_Store`, "finder")
			t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
			trOk(f.main, { "ready", R })
			t.expect(onOrigin("pickman/.tracker/issues/active/c0040/c0040.md") ~= nil).toBe(true)
			-- an active raft is never folded into
			fixture.git(D, { "fetch", "-q", "origin" })
			fixture.git(D, { "reset", "-q", "--hard", "origin/main" })
			refused(D, { "fold", R, "c0060" }, R, "backlog")
			t.expect(
				string.match(originStatus("pickman/.tracker/issues/active/c0040/c0040.md"), "^active%-")
					~= nil
			)
				.toBe(true)
		end)

		it("a raft move never restamps a prepared member, and release needs the claim or --force", function()
			local c70 = onOrigin("pickman/.tracker/issues/c0070/c0070.md")
			trOk(E, { "status", "R0090", "preparing" })
			t.expect(
				string.match(originStatus("pickman/.tracker/rafts/R0090/R0090.md"), "^preparing%-") ~= nil
			)
				.toBe(true)
			t.expect(onOrigin("pickman/.tracker/issues/c0070/c0070.md")).toBe(c70)
			refused(E, { "status", "R0090", "preparing" }, "cannot move")
			refused(E, { "release", "R0090" }, "not this checkout's")
			trOk(E, { "release", "R0090", "--force" })
			t.expect(
				string.match(originStatus("pickman/.tracker/rafts/R0090/R0090.md"), "^prepared%-") ~= nil
			)
				.toBe(true)
			t.expect(onOrigin("pickman/.tracker/issues/c0070/c0070.md")).toBe(c70)
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
					trOk(F, { "new", "raft", "chore", "race", "c0013", "c0014", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				-- z-design in another terminal claims c0013: nothing on origin says it is being rafted, so this succeeds
				trOk(G, { "status", "c0013", "preparing" })
				local claim = originStatus("pickman/.tracker/issues/c0013/c0013.md")
				t.expect(string.match(claim, "^preparing%-") ~= nil).toBe(true)
				trOk(F, { "sync" }) -- the claim's status line merges in cleanly
				local doc = `{F}/pickman/.tracker/rafts/{RX}/{RX}.md`
				setLine(doc, "design", "ready")
				writeDesign(doc)
				coherence(`{F}/pickman/.tracker/rafts/{RX}`, "001")
				refused(F, { "status", RX, "prepared" }, "c0013", "claimed by another terminal", claim)
				t.expect(originStatus("pickman/.tracker/issues/c0013/c0013.md")).toBe(claim)
				-- the rafting drops it and prepares the rest
				setLine(doc, "issues", "[c0014]")
				setLine(`{F}/pickman/.tracker/issues/c0013/c0013.md`, "raft", "")
				trOk(F, { "status", RX, "prepared" })
				fixture.git(F, { "add", "-A" })
				fixture.git(F, { "commit", "-q", "-m", `tracker: raft {RX}` })
				land(F)
				-- once the rafting has landed, z-design can no longer claim a member past its raft
				refused(G, { "status", "c0014", "preparing" }, "c0014", RX, "z-raft takes it out")
				trOk(f.main, { "ready", RX })
				t.expect(onOrigin("pickman/.tracker/issues/active/c0014/c0014.md") ~= nil).toBe(true)
				t.expect(originStatus("pickman/.tracker/issues/c0013/c0013.md")).toBe(claim)
			end
		)

		it("a member claimed after the carried move but before the landing keeps ready refused", function()
			local RY = string.match(
				trOk(H, { "new", "raft", "chore", "late", "c0015", "c0016", "--project", "pickman" }),
				"(R%d+)"
			) :: string
			local doc = `{H}/pickman/.tracker/rafts/{RY}/{RY}.md`
			setLine(doc, "design", "ready")
			writeDesign(doc)
			coherence(`{H}/pickman/.tracker/rafts/{RY}`, "001")
			trOk(H, { "status", RY, "prepared" })
			fixture.git(H, { "add", "-A" })
			fixture.git(H, { "commit", "-q", "-m", `tracker: raft {RY}` })
			trOk(G, { "status", "c0016", "preparing" }) -- c0016's raft: is still empty on origin
			land(H)
			refused(f.main, { "ready", RY }, "c0016", "preparing")
		end)

		-- z-design's whole cycle on an issue alone: claim, change the design, carried prepare, land
		local function redesign(wt: string, id: string, mark: string)
			trOk(wt, { "sync" })
			trOk(wt, { "status", id, "preparing" })
			local path = `{wt}/pickman/.tracker/issues/{id}/{id}.md`
			fs.writeFile(path, fs.readFile(path) .. `\n## Design\n{mark}: a new interface\n`)
			trOk(wt, { "status", id, "prepared" })
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", `tracker: prep {id}` })
			land(wt)
		end
		local function prepareRaft(wt: string, rid: string)
			local doc = `{wt}/pickman/.tracker/rafts/{rid}/{rid}.md`
			setLine(doc, "design", "ready")
			writeDesign(doc)
			coherence(`{wt}/pickman/.tracker/rafts/{rid}`, "001")
		end

		it(
			"a redesign landed after the carried move is caught by ready, naming the member and both hashes",
			function()
				local RZ = string.match(
					trOk(J, { "new", "raft", "chore", "late2", "c0021", "c0022", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				t.expect(
					string.match(
						fs.readFile(`{J}/pickman/.tracker/rafts/{RZ}/{RZ}.md`),
						"\ngrouped: %[c0021@%x+, c0022@%x+%]\n"
					) ~= nil
				).toBe(true)
				prepareRaft(J, RZ)
				trOk(J, { "status", RZ, "prepared" })
				fixture.git(J, { "add", "-A" })
				fixture.git(J, { "commit", "-q", "-m", `tracker: raft {RZ}` })
				trOk(K, { "status", "c0022", "preparing" }) -- its raft: is still empty on origin
				land(J)
				-- K finishes the redesign (its claim was made before the landing) and lands it
				local path = `{K}/pickman/.tracker/issues/c0022/c0022.md`
				trOk(K, { "sync" })
				fs.writeFile(path, fs.readFile(path) .. "\n## Design\nREDESIGNED-LATE: a new interface\n")
				trOk(K, { "status", "c0022", "prepared" })
				fixture.git(K, { "add", "-A" })
				fixture.git(K, { "commit", "-q", "-m", "tracker: prep c0022" })
				land(K)
				local r = tr(f.main, { "ready", RZ })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "c0022 (")).toBe(true)
				t.expect(has(r.stderr, "changed on origin/main since")).toBe(true)
				t.expect(string.match(r.stderr, "c0022 %(%x+ → %x+%)") ~= nil).toBe(true)
				t.expect(onOrigin(`pickman/.tracker/rafts/active/{RZ}/{RZ}.md`)).toBe(nil)
			end
		)

		it(
			"a redesign landed before the carried move is refused by it, and unfold takes the member out",
			function()
				local RW = string.match(
					trOk(L, { "new", "raft", "chore", "early2", "c0023", "c0024", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				prepareRaft(L, RW)
				redesign(M, "c0024", "REDESIGNED-EARLY")
				trOk(L, { "sync" })
				refused(L, { "status", RW, "prepared" }, "c0024 (", "changed on origin/main since")
				-- the route: take it out, prepare the rest, land; the member is raftless and z-design may claim it
				fixture.git(L, { "add", "-A" })
				fixture.git(L, { "commit", "-q", "-m", "wip: the raft's design" })
				trOk(L, { "unfold", RW, "c0024" })
				t.expect(
					string.match(fs.readFile(`{L}/pickman/.tracker/issues/c0024/c0024.md`), "\nraft: *\n")
						~= nil
				).toBe(true)
				t.expect(has(fs.readFile(`{L}/pickman/.tracker/rafts/{RW}/{RW}.md`), "\nissues: [c0023]\n"))
					.toBe(true)
				trOk(L, { "status", RW, "prepared" })
				fixture.git(L, { "add", "-A" })
				fixture.git(L, { "commit", "-q", "-m", `tracker: raft {RW}` })
				land(L)
				trOk(f.main, { "ready", RW })
				trOk(M, { "sync" })
				trOk(M, { "status", "c0024", "preparing" })
			end
		)

		it("unfold takes a member out of a landed raft, so z-design can claim it again", function()
			-- RX (c0014) and the readied rafts aside, R0090 holds c0070 and is landed and prepared
			refused(N, { "status", "c0070", "preparing" }, "c0070", "unfold")
			refused(N, { "unfold", "R0090", "c0010" }, "c0010 is not a member of R0090")
			trOk(N, { "unfold", "R0090", "c0070" })
			trOk(N, { "status", "R0090", "prepared" })
			fixture.git(N, { "add", "-A" })
			fixture.git(N, { "commit", "-q", "-m", "tracker: unfold c0070 from R0090" })
			land(N)
			t.expect(
				string.match(onOrigin("pickman/.tracker/issues/c0070/c0070.md") or "", "\nraft: *\n") ~= nil
			)
				.toBe(true)
			trOk(N, { "status", "c0070", "preparing" })
			-- review 003 F6: the raft unfold emptied is named by audit
			local audited = tr(f.main, { "audit" }).stdout
			t.expect(has(audited, "orphan-raft") and has(audited, "R0090")).toBe(true)
		end)

		it(
			"a cleared .cache names the way back, and release gives back the issue claims this checkout made",
			function()
				local RV = string.match(
					trOk(O, { "new", "raft", "chore", "oldflow", "c0025", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				trOk(O, { "status", "c0026", "preparing" }) -- an issue added during the old prep, claimed here
				local doc = `{O}/pickman/.tracker/rafts/{RV}/{RV}.md`
				setLine(doc, "design", "ready")
				setLine(`{O}/pickman/.tracker/issues/c0025/c0025.md`, "design", "ready")
				setLine(doc, "issues", "[c0025, c0026]")
				setLine(`{O}/pickman/.tracker/issues/c0026/c0026.md`, "raft", RV)
				local claim = (string.gsub(fs.readFile(`{O}/.cache/tracker-claim-c0026`), "%s+$", ""))
				fs.removeFile(`{O}/.cache/tracker-claim-c0026`)
				refused(
					O,
					{ "status", RV, "prepared" },
					"c0026",
					"its claim file was cleared",
					"status c0026 new"
				)
				fs.writeFile(`{O}/.cache/tracker-claim-c0026`, claim .. "\n")
				local before = tip()
				trOk(O, { "release", RV })
				local changed =
					string.split(fixture.git(f.origin, { "diff", "--name-only", before, "main" }), "\n")
				table.sort(changed)
				t.expect(changed).toEqual({
					"pickman/.tracker/issues/c0025/c0025.md",
					"pickman/.tracker/issues/c0026/c0026.md",
					`pickman/.tracker/rafts/{RV}/{RV}.md`,
				})
				t.expect(
					string.match(originStatus("pickman/.tracker/issues/c0026/c0026.md"), "^new%-") ~= nil
				)
					.toBe(true)
				t.expect(fs.isFile(`{O}/.cache/tracker-claim-c0026`)).toBe(false)
			end
		)

		-- z-design's cycle on an issue alone that changes only its contract: its check.sh (check), or else one acceptance spec
		local function recontract(wt: string, id: string, check: boolean)
			trOk(wt, { "sync" })
			trOk(wt, { "status", id, "preparing" })
			local dir = `{wt}/pickman/.tracker/issues/{id}`
			if check then
				fs.writeFile(
					`{dir}/check.sh`,
					fs.readFile(`{dir}/check.sh`) .. 'check "AC2: NEW CRITERION" true\n'
				)
			end
			if not check then
				fs.writeDir(`{dir}/acceptance`)
				fs.writeFile(`{dir}/acceptance/new.spec.luau`, "--!strict\nreturn nil\n")
			end
			trOk(wt, { "status", id, "prepared" })
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", `tracker: prep {id}` })
			land(wt)
		end
		local function commitAll(wt: string, msg: string)
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", msg })
		end

		it(
			"a redesign of only a member's check.sh or acceptance specs inside the window is refused",
			function()
				local R1 = string.match(
					trOk(P, { "new", "raft", "chore", "chk", "c0031", "c0032", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				prepareRaft(P, R1)
				commitAll(P, "wip")
				recontract(Q, "c0032", true)
				trOk(P, { "sync" })
				refused(P, { "status", R1, "prepared" }, "c0032 (", "changed on origin/main since")
				local RA = string.match(
					trOk(S, { "new", "raft", "chore", "acc", "c0033", "c0034", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				prepareRaft(S, RA)
				commitAll(S, "wip")
				recontract(Q, "c0034", false)
				trOk(S, { "sync" })
				refused(S, { "status", RA, "prepared" }, "c0034 (", "changed on origin/main since")
			end
		)

		it("re-folding a redesigned member needs a new coherence review; an unfold alone does not", function()
			local R3 = string.match(
				trOk(
					U,
					{ "new", "raft", "chore", "refold", "c0035", "c0036", "c0037", "--project", "pickman" }
				),
				"(R%d+)"
			) :: string
			prepareRaft(U, R3)
			commitAll(U, "wip")
			redesign(Q, "c0037", "REDESIGNED-REFOLD")
			trOk(U, { "sync" })
			refused(U, { "status", R3, "prepared" }, "c0037 (", "changed on origin/main since")
			trOk(U, { "unfold", R3, "c0037" })
			trOk(U, { "status", R3, "prepared" }) -- the review's record still covers c0035 and c0036
			commitAll(U, "wip")
			trOk(U, { "fold", R3, "c0037" })
			-- review 004 F4: the refusal names what to do, never a line to paste into the old review
			local stale = tr(U, { "status", R3, "prepared" })
			t.expect(has(stale.stderr, "Grouped: [")).toBe(false)
			t.expect(has(stale.stderr, "never edit a review")).toBe(true)
			refused(U, { "status", R3, "prepared" }, "predates its record")
			coherence(`{U}/pickman/.tracker/rafts/{R3}`, "002")
			trOk(U, { "status", R3, "prepared" })
		end)

		it("an empty grouped: record does not exempt the members this rafting grouped", function()
			local R4 = string.match(
				trOk(V, { "new", "raft", "chore", "empty", "c0038", "c0039", "--project", "pickman" }),
				"(R%d+)"
			) :: string
			prepareRaft(V, R4)
			setLine(`{V}/pickman/.tracker/rafts/{R4}/{R4}.md`, "grouped", "[]")
			refused(V, { "status", R4, "prepared" }, "has no grouped: record")
		end)

		it("a redesign inside a fold window is refused by the carried move", function()
			trOk(X, { "fold", "R0110", "c0041" })
			redesign(Q, "c0041", "REDESIGNED-FOLD")
			trOk(X, { "sync" })
			refused(X, { "status", "R0110", "prepared" }, "c0041 (", "changed on origin/main since")
		end)
	end
)
