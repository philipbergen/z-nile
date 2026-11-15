--!strict
-- c0286 AC2: `raft-plan` reads each issue's `tied:` line from its document, keeps a tie together (one raft once every
-- member is prepared, a skip naming why before), and `--apply` makes that one raft; z-raft with arguments still does
-- what it is asked: `new raft` takes a tied issue alone. Driven through scripts/tracker.sh in a fixture under
-- .cache/c0286-plan-cli.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ROOT = "z-nile/.tracker/issues"

-- a chore's document: `tied` is the whole `tied:` line's value (nil for none), written after `id:` (review 001 F7)
local function chore(id: string, size: number?, tied: string?, prepared: boolean?): string
	local ready = prepared ~= false
	return `---\nid: {id}\n{if tied then `tied: {tied}\n` else ""}type: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: {if ready
		then "ready"
		else "draft"}\ncreated: 2026-11-15\n{if size then `size: {size}\n` else ""}status: {if ready
		then PREPARED
		else "new-quiet-copper-falcon"}\n---\n\n# {id}\n\n## Design\n\n### Touched modules\n\n### Affected specs\n\n## Unknowns & experiments\n`
end

local f: trackerfix.Fixture
local W = ""

local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function raftOf(id: string): string?
	return string.match(fs.readFile(`{W}/{ROOT}/{id}/{id}.md`), "\nraft: (%S*)\n")
end

local EXPECTED = {
	"./zn new raft chore c0010 c0010 c0020 --project z-nile",
	"./zn new raft chore c0050 c0050 --project z-nile",
	"skip c0030: tied to c0040: c0040 (new, design draft) not prepared yet: raft-plan rafts them together when every one is (retry a dispatched member once that rafting has merged)",
}

return t.spec(
	"c0286 raft-plan keeps tied issues together, and z-raft with arguments does as asked",
	function(it)
		it("sets up a backlog with a prepared tie, a tie still waiting and an untied chore", function()
			local seed: { [string]: string } = {
				[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
			}
			local function add(id: string, text: string)
				seed[`{ROOT}/{id}/{id}.md`] = text
				seed[`{ROOT}/{id}/check.sh`] = CHECK
			end
			-- 900 + 900 is over the cap: only the tie keeps them in one raft; c0020 has no tied: line of its own
			add("c0010", chore("c0010", 900, "[c0020]"))
			add("c0020", chore("c0020", 900))
			add("c0030", chore("c0030", 100, "[c0040]"))
			add("c0040", chore("c0040", nil, "[c0030]", false))
			add("c0050", chore("c0050", 100))
			f = trackerfix.new("c0286-plan-cli", seed)
			W = trOk(f.main, { "worktree", "raft-w" })
		end)

		it("prints the tie as one raft and the waiting tie as a skip, writing nothing", function()
			local before = fixture.git(f.origin, { "rev-parse", "main" })
			t.expect(string.split(trOk(f.main, { "raft-plan" }), "\n")).toEqual(EXPECTED)
			t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
			t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
		end)

		it("--apply makes the tie one raft, and leaves the waiting tie alone", function()
			trOk(W, { "raft-plan", "--apply" })
			local tie = raftOf("c0010") :: string
			t.expect(tie ~= "").toBe(true)
			t.expect(raftOf("c0020")).toBe(tie)
			t.expect(raftOf("c0050") ~= "" and raftOf("c0050") ~= tie).toBe(true)
			t.expect(raftOf("c0030")).toBe("")
			t.expect(fixture.git(W, { "status", "--porcelain" })).toBe("")
			t.expect(trOk(W, { "raft-plan" })).toBe(EXPECTED[3])
		end)

		it("with arguments, new raft takes a tied issue alone, as asked", function()
			trOk(W, { "new", "raft", "chore", "c0030-alone", "c0030", "--project", "z-nile" })
			t.expect(raftOf("c0030") ~= "").toBe(true)
			t.expect(raftOf("c0030") ~= raftOf("c0010")).toBe(true)
			t.expect(trOk(W, { "raft-plan" }))
				.toBe("raft-plan: nothing to raft (no prepared issue without a raft)")
		end)
	end
)
