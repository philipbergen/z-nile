--!strict
-- R0050 code review 001 F2: `recombine` refuses an id named twice (a count comparison retired a raft that still had a
-- member), and `audit` errors on a backlog or active issue whose raft: names a retired or missing raft (such an issue
-- can be neither readied, unfolded nor claimed). Driven through ./zn in a fixture under .cache/c0116-recombine-members
-- (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
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
				}, "issues naming dead rafts")
				fixture.git(f.main, { "pull", "-q", "origin", "main" })
				local r = trackerfix.tr(f, f.main, { "audit" })
				local out = r.stdout .. r.stderr
				t.expect(r.ok).toBe(false)
				t.expect(has(out, "c0031's raft R0030 is retired")).toBe(true)
				t.expect(has(out, "c0041's raft R0099 does not exist")).toBe(true)
				t.expect(has(out, "c0051")).toBe(false)
			end
		)
	end
)
