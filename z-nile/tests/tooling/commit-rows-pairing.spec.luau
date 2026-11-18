--!strict
-- c0322 review 001 F1: `./zn commit` hands `ledger.commitRows` the shares it keeps (a build share that moved no
-- lines gets no row) and pairs each returned row with the share at the same position. Passing the unfiltered
-- shares would give the member that changed files the idle member's row. Fixture under .cache/commit-rows-pairing
-- (tests/lib/trackerfix): an active raft of two members, of which only the second owns the changed path. Also the
-- length guard of `ledger.commitTrailers`, so a mispaired call is loud instead of silent.
local buffer = require("@znile/engine/buffer")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local RAFT = "R0010"
local A, B = "c0010", "c0020"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, owned: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {RAFT}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n### Touched modules\n- \`{owned}\`\n\n### Notes\nx\n`
end
local RAFT_DOC =
	`---\nid: {RAFT}\ntype: chore\ntitle: Pair\nslug: pair\nsingle: false\nissues: [{A}, {B}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {RAFT}\n`

local function share(id: string, added: number): ledger.Share
	return { id = id, added = added, removed = 0, minutes = 0, how = "raft" }
end

return t.spec("a commit pairs each kept share with its own row", function(it)
	local f: trackerfix.Fixture

	it("the trailers refuse rows that do not match the shares one to one", function()
		local shares = { share(A, 0), share(B, 5) }
		local rows = ledger.commitRows("x", "2026-11-15 20:00", "build", shares, nil, nil, "")
		local ok, err = pcall(ledger.commitTrailers, "build", { shares[2] }, rows, nil)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "rows", 1, true) ~= nil).toBe(true)
		t.expect(#ledger.commitTrailers("build", shares, rows, nil)).toBe(2)
	end)

	it("sets up an active raft of two members, on its layer branch", function()
		local seed: { [string]: string } = {
			[`{ROOT}/rafts/active/{RAFT}/{RAFT}.md`] = RAFT_DOC,
			[`{ROOT}/rafts/active/{RAFT}/check.sh`] = CHECK,
			[`{ROOT}/issues/active/{A}/{A}.md`] = issue(A, "notes/alpha"),
			[`{ROOT}/issues/active/{A}/check.sh`] = CHECK,
			[`{ROOT}/issues/active/{B}/{B}.md`] = issue(B, "notes/beta"),
			[`{ROOT}/issues/active/{B}/check.sh`] = CHECK,
		}
		f = trackerfix.new("commit-rows-pairing", seed)
		fixture.git(f.main, { "checkout", "-q", "-b", `{RAFT}/1/{B}` })
	end)

	it(
		"a build commit that changes only the second member's path gives it its own row and trailer",
		function()
			fs.writeDir(`{f.main}/notes/beta`)
			fs.writeFile(`{f.main}/notes/beta/b.txt`, "1\n2\n3\n4\n5\n")
			local r = fixture.exec(f.main, "./zn", { "commit", "-m", "work on beta" })
			if not r.ok then
				error(`commit failed ({r.code}): {r.stderr}{r.stdout}`)
			end
			local body = fixture.git(f.main, { "log", "-1", "--format=%B" })
			local trailers: { string } = {}
			for line in string.gmatch(body, "[^\n]+") do
				if string.sub(line, 1, 7) == "Issue: " then
					table.insert(trailers, line)
				end
			end
			t.expect(#trailers).toBe(1)
			t.expect(trailers[1]).toBe(`Issue: {B} +5/-0 0.0m`)
			t.expect(string.find(body, `Issue: {A}`, 1, true) == nil).toBe(true)
			-- the spend rows: the changed member's carries its lines, and the idle one got none
			local function added(id: string): { number }
				local out: { number } = {}
				local folder = `{f.main}/{ROOT}/issues/active/{id}/spend.d`
				if fs.isDir(folder) then
					for _, name in fs.readDir(folder) do
						local parsed = buffer.parseTsv(fs.readFile(`{folder}/{name}`))
						if parsed then
							for _, row in parsed do
								table.insert(out, row.added)
							end
						end
					end
				end
				return out
			end
			t.expect(added(A)).toEqual({})
			t.expect(added(B)).toEqual({ 5 })
		end
	)
end)
