--!strict
-- R0050 code review 001 F2: `recombine` refuses an id named twice (a count comparison retired a raft that still had a
-- member), and `audit` errors on a backlog or active issue whose raft: names a retired or missing raft (such an issue
-- can be neither readied, unfolded nor claimed). Driven through ./zn in a fixture under .cache/c0116-recombine-members
-- (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, raft: string, status: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 200\nstatus: {status or PREPARED}\n---\n\n# {id}\n`
end
local function raftDoc(id: string, issues: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\n{extra or ""}status: {PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
end

local f: trackerfix.Fixture
local W = ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end

return t.spec(
	"c0116 recombine never retires a raft that keeps a member; audit names an issue's dead raft",
	function(it)
		it("sets up two backlog rafts", function()
			local seed: { [string]: string } = {
				[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
				["pickman/.tracker/architecture.md"] = "# Architecture\n",
				["z-nile/next"] = "issue 200 quiet-copper-falcon\nraft 200 quiet-copper-falcon\n",
			}
			local function add(path: string, text: string)
				seed[path] = text
				seed[string.gsub(path, "/[^/]+$", "/check.sh")] = CHECK
			end
			add("pickman/.tracker/rafts/R0010/R0010.md", raftDoc("R0010", "c0011"))
			add("pickman/.tracker/issues/c0011/c0011.md", issue("c0011", "R0010"))
			add("pickman/.tracker/rafts/R0020/R0020.md", raftDoc("R0020", "c0021, c0022"))
			add("pickman/.tracker/issues/c0021/c0021.md", issue("c0021", "R0020"))
			add("pickman/.tracker/issues/c0022/c0022.md", issue("c0022", "R0020"))
			f = trackerfix.new("c0116-recombine-members", seed)
			W = trackerfix.trOk(f, f.main, { "worktree", "raft-w" })
			t.expect(trackerfix.tr(f, f.main, { "audit" }).ok).toBe(true)
		end)

		it("an id named twice is refused before anything is published", function()
			local before = tip()
			local r = trackerfix.tr(f, W, { "recombine", "R0010", "R0020", "c0021", "c0021" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "c0021 is named twice")).toBe(true)
			t.expect(tip()).toBe(before)
			-- the other raft and both its members are where they were
			t.expect(
				fixture.exec(f.origin, "git", { "show", "main:pickman/.tracker/rafts/R0020/R0020.md" }).ok
			)
				.toBe(true)
		end)

		it(
			"audit errors on a backlog or active issue whose raft: names a retired or a missing raft",
			function()
				trackerfix.elsewhere(f, {
					["pickman/.tracker/rafts/retired/R0030/R0030.md"] = raftDoc(
						"R0030",
						"",
						"retired: R0010\n"
					),
					["pickman/.tracker/issues/c0031/c0031.md"] = issue("c0031", "R0030"),
					["pickman/.tracker/issues/c0031/check.sh"] = CHECK,
					["pickman/.tracker/issues/active/c0041/c0041.md"] = issue(
						"c0041",
						"R0099",
						"active-jolly-silver-walrus"
					),
					["pickman/.tracker/issues/active/c0041/check.sh"] = CHECK,
					-- a done issue's raft: is history, never checked
					["pickman/.tracker/issues/done/c0051/c0051.md"] = issue("c0051", "R0098", "done"),
					["pickman/.tracker/issues/done/c0051/check.sh"] = CHECK,
					-- review 002 F2: live issues whose raft is in active/ or done/ are fine (never "missing")
					["pickman/.tracker/rafts/active/R0060/R0060.md"] = (string.gsub(
						raftDoc("R0060", "c0061"),
						(string.gsub(PREPARED, "%-", "%%-")),
						"active-jolly-silver-walrus"
					)),
					["pickman/.tracker/rafts/active/R0060/check.sh"] = CHECK,
					["pickman/.tracker/issues/active/c0061/c0061.md"] = issue(
						"c0061",
						"R0060",
						"active-jolly-silver-walrus"
					),
					["pickman/.tracker/issues/active/c0061/check.sh"] = CHECK,
					["pickman/.tracker/rafts/done/R0070/R0070.md"] = raftDoc("R0070", "c0071"),
					["pickman/.tracker/rafts/done/R0070/check.sh"] = CHECK,
					["pickman/.tracker/issues/c0071/c0071.md"] = issue("c0071", "R0070"),
					["pickman/.tracker/issues/c0071/check.sh"] = CHECK,
					-- review 003 F1: an active issue with no raft at all
					["pickman/.tracker/issues/active/c0081/c0081.md"] = issue(
						"c0081",
						"",
						"active-jolly-silver-walrus"
					),
					["pickman/.tracker/issues/active/c0081/check.sh"] = CHECK,
				}, "issues naming dead rafts")
				fixture.git(f.main, { "pull", "-q", "origin", "main" })
				local r = trackerfix.tr(f, f.main, { "audit" })
				local out = r.stdout .. r.stderr
				t.expect(r.ok).toBe(false)
				t.expect(has(out, "c0031's raft R0030 is retired")).toBe(true)
				t.expect(has(out, "c0041's raft R0099 does not exist")).toBe(true)
				t.expect(has(out, "c0051")).toBe(false)
				t.expect(has(out, "c0061")).toBe(false)
				t.expect(has(out, "c0071")).toBe(false)
				-- each error names the one command that clears it for the item's state (review 002 F1, 003 F1)
				t.expect(has(out, "./zn unfold R0030 c0031")).toBe(true)
				t.expect(has(out, "c0041's raft R0099 does not exist: give it back with ./zn stop c0041"))
					.toBe(true)
				t.expect(has(out, "c0081 is in active/ with no raft: give it back with ./zn stop c0081"))
					.toBe(true)
				t.expect(has(out, "audit: 3 errors")).toBe(true)
			end
		)

		it("unfold refuses a non-member, an active issue and a done one, publishing nothing", function()
			fixture.git(W, { "fetch", "-q", "origin" })
			fixture.git(W, { "merge", "-q", "--no-edit", "origin/main" })
			local before = tip()
			local function refused(args: { string }, needle: string)
				local r = trackerfix.tr(f, W, args)
				t.expect(r.ok).toBe(false)
				if not has(r.stderr, needle) then
					error(`{table.concat(args, " ")}: stderr lacks {needle}: {r.stderr}`, 2)
				end
			end
			refused({ "unfold", "R0030", "c0071" }, "c0071 is not a member of R0030")
			refused({ "unfold", "R0099", "c0041" }, "use ./zn stop c0041")
			refused({ "unfold", "R0098", "c0051" }, "c0051 is done")
			t.expect(tip()).toBe(before)
			t.expect(has(fs.readFile(`{W}/pickman/.tracker/issues/done/c0051/c0051.md`), "\nraft: R0098\n"))
				.toBe(true)
			t.expect(has(fs.readFile(`{W}/pickman/.tracker/issues/active/c0041/c0041.md`), "\nraft: R0099\n"))
				.toBe(true)
		end)

		it(
			"stop gives back an active issue whose raft is dead or empty, and refuses one whose raft is live",
			function()
				local r = trackerfix.tr(f, f.main, { "stop", "c0061" })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "use ./zn stop R0060")).toBe(true)
				trackerfix.trOk(f, f.main, { "stop", "c0041" })
				trackerfix.trOk(f, f.main, { "stop", "c0081" })
				for _, id in { "c0041", "c0081" } do
					local moved =
						fixture.exec(f.origin, "git", { "show", `main:pickman/.tracker/issues/{id}/{id}.md` })
					t.expect(moved.ok).toBe(true)
					t.expect(string.match(moved.stdout, "\nstatus: (prepared%-[%w%-]+)\n") ~= nil).toBe(true)
					t.expect(
						fixture.exec(
							f.origin,
							"git",
							{ "cat-file", "-e", `main:pickman/.tracker/issues/active/{id}/{id}.md` }
						).ok
					).toBe(false)
				end
				-- the backlog issue whose raft is dead is named for unfold now; the raftless one is clean
				local a = trackerfix.tr(f, f.main, { "audit" })
				local out = a.stdout .. a.stderr
				t.expect(has(out, "./zn unfold R0099 c0041")).toBe(true)
				t.expect(has(out, "c0081")).toBe(false)
			end
		)

		it("after the named commands, the next lifecycle step works: z-design claims each issue", function()
			fixture.git(W, { "fetch", "-q", "origin" })
			fixture.git(W, { "merge", "-q", "--no-edit", "origin/main" })
			trackerfix.trOk(f, W, { "unfold", "R0030", "c0031" })
			trackerfix.trOk(f, W, { "unfold", "R0099", "c0041" })
			-- the rafting PR lands
			fixture.git(W, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			local a = trackerfix.tr(f, f.main, { "audit" })
			t.expect(has(a.stdout .. a.stderr, "dead-raft")).toBe(false)
			t.expect(has(a.stdout .. a.stderr, "with no raft")).toBe(false)
			for _, id in { "c0031", "c0041", "c0081" } do
				trackerfix.trOk(f, W, { "status", id, "preparing" })
			end
		end)

		it("list shows a retired raft as retired, never as a backlog raft", function()
			local out = trackerfix.trOk(f, f.main, { "list" })
			t.expect(string.find(out, "R0030%s+retired") ~= nil).toBe(true)
			t.expect(string.find(out, "R0030%s+backlog") ~= nil).toBe(false)
		end)

		it(
			"the one rule: an active issue is its raft's only when that raft is active and holds its claim (or it is emergent)",
			function()
				local A = "active-jolly-silver-walrus"
				trackerfix.elsewhere(f, {
					-- review 004 F1's probe states: a backlog raft, a done raft, an issue id, an active raft without the stamp
					["pickman/.tracker/issues/active/c0091/c0091.md"] = issue("c0091", "R0010", A),
					["pickman/.tracker/issues/active/c0091/check.sh"] = CHECK,
					["pickman/.tracker/issues/active/c0094/c0094.md"] = issue("c0094", "R0070", A),
					["pickman/.tracker/issues/active/c0094/check.sh"] = CHECK,
					["pickman/.tracker/issues/active/c0093/c0093.md"] = issue("c0093", "c0011", A),
					["pickman/.tracker/issues/active/c0093/check.sh"] = CHECK,
					["pickman/.tracker/issues/active/c0095/c0095.md"] = issue(
						"c0095",
						"R0060",
						"active-other-stamp-here"
					),
					["pickman/.tracker/issues/active/c0095/check.sh"] = CHECK,
					-- an emergent issue made on R0060's branch: it carries no claim, and is R0060's
					["pickman/.tracker/issues/active/c0096/c0096.md"] = (string.gsub(
						issue("c0096", "R0060", "new-amber-otter-lynx"),
						"emergent: false",
						"emergent: true"
					)),
					["pickman/.tracker/issues/active/c0096/check.sh"] = CHECK,
				}, "active issues their rafts don't hold")
				fixture.git(f.main, { "pull", "-q", "origin", "main" })
				local a = trackerfix.tr(f, f.main, { "audit" })
				local out = a.stdout .. a.stderr
				for _, id in { "c0091", "c0094", "c0093", "c0095" } do
					if not has(out, `give it back with ./zn stop {id}`) then
						error(`audit names no stop for {id}: {out}`)
					end
				end
				t.expect(has(out, "c0091 is in active/, but its raft R0010 doesn't hold it")).toBe(true)
				t.expect(has(out, "c0096")).toBe(false)
				t.expect(has(out, "c0061")).toBe(false)
				for _, id in { "c0061", "c0096" } do
					local r = trackerfix.tr(f, f.main, { "stop", id })
					t.expect(r.ok).toBe(false)
					t.expect(has(r.stderr, "use ./zn stop R0060")).toBe(true)
				end
				for _, id in { "c0091", "c0094", "c0093", "c0095" } do
					trackerfix.trOk(f, f.main, { "stop", id })
					t.expect(
						fixture.exec(f.origin, "git", { "show", `main:pickman/.tracker/issues/{id}/{id}.md` }).ok
					).toBe(true)
				end
				local after = trackerfix.tr(f, f.main, { "audit" })
				t.expect(has(after.stdout .. after.stderr, "./zn stop c00")).toBe(false)
			end
		)

		it("the bare status never lists a retired raft (it walks only publishable paths)", function()
			local out = trackerfix.trOk(f, f.main, { "status" })
			t.expect(has(out, "R0030")).toBe(false)
		end)
	end
)
