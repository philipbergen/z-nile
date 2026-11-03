--!strict
-- c0161 AC6: the design record. `raftplan.designRecord(id, files)` is one hash over an issue's document (without the
-- `status:`, `raft:` and `design:` lines the process itself writes), `check.sh`, `acceptance/` and `experiments/` (an
-- executor applies the patches kept there); the reviews, refutes, `harvest.md`, `spend.md` and `prompt.md` are not in it.
-- `raftplan.recordPaths(id, files, true)` lists just the specs' files (`check.sh`, `acceptance/`), for a proof of them. `./zn design-record <id>` prints it, and a
-- mechanical renumber re-records the `Design record:` lines that matched before it, so a round that read the design
-- still reads it. Pure cases first; then the command and a renumber in a fixture under .cache/c0161-design-record.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local DOC = "---\nid: c0001\ntype: chore\ntitle: A\nslug: a\nraft: \ndepends_on: []\nemergent: false\nsize: 10\n"
	.. "design: draft\ncreated: 2026-01-01\nstatus: preparing-quiet-copper-falcon\n---\n\n# c0001\n\n## Design\nOne.\n"
local function files(extra: { [string]: string }?): { [string]: string }
	local out: { [string]: string } = {
		["c0001.md"] = DOC,
		["check.sh"] = "check 'AC1' true\n",
		["acceptance/a.spec.luau"] = "return 1\n",
	}
	local more: { [string]: string } = extra or {}
	for k, v in more do
		out[k] = v
	end
	return out
end
local function record(extra: { [string]: string }?): string
	return raftplan.designRecord("c0001", files(extra))
end
local function line(text: string, from: string, to: string): string
	local s, e = string.find(text, from, 1, true)
	assert(s and e, `no {from}`)
	return string.sub(text, 1, s - 1) .. to .. string.sub(text, e + 1)
end

local f: trackerfix.Fixture
local wt = ""
local function trOk(args: { string }): string
	return trackerfix.trOk(f, wt, args)
end

return t.spec("c0161 the design record", function(it)
	it("is twelve hex digits and the same for the same design", function()
		t.expect(string.match(record(), "^%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil).toBe(true)
		t.expect(record()).toBe(record())
	end)

	it(
		"ignores what the process itself writes: status, raft and design lines, reviews, refutes, harvest, spend",
		function()
			local base = record()
			t.expect(record({
				["c0001.md"] = line(DOC, "status: preparing-quiet-copper-falcon", "status: prepared-a-b-c"),
			})).toBe(base)
			t.expect(record({ ["c0001.md"] = line(DOC, "raft: \n", "raft: R0010\n") })).toBe(base)
			t.expect(record({ ["c0001.md"] = line(DOC, "design: draft", "design: ready") })).toBe(base)
			for _, name in
				{
					"design-review-001.md",
					"design-refute-001.md",
					"harvest.md",
					"spend.md",
					"prompt.md",
				}
			do
				t.expect(record({ [name] = "anything\n" })).toBe(base)
			end
		end
	)

	it(
		"changes with the design: the document body, its other frontmatter, check.sh, a spec, a prototype patch, the id",
		function()
			local base = record()
			t.expect(record({ ["c0001.md"] = DOC .. "\n## Design\nTwo.\n" }) ~= base).toBe(true)
			t.expect(record({ ["c0001.md"] = line(DOC, "size: 10", "size: 11") }) ~= base).toBe(true)
			t.expect(record({ ["check.sh"] = "check 'AC1' false\n" }) ~= base).toBe(true)
			t.expect(record({ ["acceptance/a.spec.luau"] = "return 2\n" }) ~= base).toBe(true)
			t.expect(record({ ["acceptance/b.spec.luau"] = "return 3\n" }) ~= base).toBe(true)
			t.expect(record({ ["experiments/proto.patch"] = "a patch\n" }) ~= base).toBe(true)
			t.expect(
				record({ ["experiments/proto.patch"] = "a patch\n" })
					~= record({ ["experiments/proto.patch"] = "another\n" })
			).toBe(true)
			t.expect(raftplan.designRecord("c0002", files()) ~= base).toBe(true) -- another id reads other files
		end
	)

	it("recordPaths is the one list: sorted, with or without the document and the prototypes", function()
		local all = raftplan.recordPaths(
			"c0001",
			files({ ["experiments/p.patch"] = "x", ["design-review-001.md"] = "x", ["harvest.md"] = "x" })
		)
		t.expect(table.concat(all, ",")).toBe("acceptance/a.spec.luau,c0001.md,check.sh,experiments/p.patch")
		local specs = raftplan.recordPaths("c0001", files({ ["experiments/p.patch"] = "x" }), true)
		t.expect(table.concat(specs, ",")).toBe("acceptance/a.spec.luau,check.sh")
	end)

	it("keeps raftplan.designHash as it was: status and raft lines out, the design line in", function()
		local base = raftplan.designHash(DOC)
		t.expect(raftplan.designHash(line(DOC, "status: preparing-quiet-copper-falcon", "status: x-y-z")))
			.toBe(base)
		t.expect(raftplan.designHash(line(DOC, "raft: \n", "raft: R0010\n"))).toBe(base)
		t.expect(raftplan.designHash(line(DOC, "design: draft", "design: ready")) ~= base).toBe(true)
	end)

	it(
		"designHash still hashes the document without its status and raft lines, against a literal text",
		function()
			-- written out here, not through withoutFront, so a filter that changes the kept text fails (existing grouped: records)
			local expected = "---\nid: c0001\ntype: chore\ntitle: A\nslug: a\ndepends_on: []\nemergent: false\nsize: 10\n"
				.. "design: draft\ncreated: 2026-01-01\n---\n\n# c0001\n\n## Design\nOne.\n"
			t.expect(raftplan.designHash(DOC)).toBe(string.sub(serde.hash("sha256", expected), 1, 12))
		end
	)

	it("sets up a fixture and a prep worktree", function()
		f = trackerfix.new("c0161-design-record", nil)
		wt = trackerfix.trOk(f, f.main, { "worktree", "prep-record" })
		trOk({ "sync" })
	end)

	it(
		"./zn design-record <id> prints the record of the work tree as git sees it, and refuses a bad id",
		function()
			local id = string.match(
				trOk({ "new", "issue", "c", "recorded", "--project", "pickman" }),
				"(%a%d+)"
			) :: string
			local dir = `{wt}/pickman/.tracker/issues/{id}`
			local printed = trOk({ "design-record", id })
			t.expect(string.match(printed, "^%x+$") ~= nil).toBe(true)
			t.expect(#printed).toBe(12)
			-- an untracked spec changes it; an untracked review does not
			fs.writeDir(`{dir}/acceptance`)
			fs.writeFile(`{dir}/acceptance/x.spec.luau`, "return 1\n")
			t.expect(trOk({ "design-record", id }) ~= printed).toBe(true)
			local with = trOk({ "design-record", id })
			fs.writeFile(`{dir}/design-review-001.md`, "# Review 001\n\nVerdict: approve\n")
			t.expect(trOk({ "design-record", id })).toBe(with)
			local bad = trackerfix.tr(f, wt, { "design-record", "R0001" })
			t.expect(bad.ok).toBe(false)
			t.expect(string.find(bad.stderr, "usage: design-record", 1, true) ~= nil).toBe(true)
			-- a preparing issue's design never lives in the main checkout: the command refuses there and names the worktree
			local main = trackerfix.tr(f, f.main, { "design-record", id })
			t.expect(main.ok).toBe(false)
			t.expect(string.find(main.stderr, "worktree", 1, true) ~= nil).toBe(true)
			local none = trackerfix.tr(f, wt, { "design-record" })
			t.expect(none.ok).toBe(false)
		end
	)

	it("a renumber re-records the lines that matched before it, and leaves a stale line stale", function()
		local old = string.match(
			trOk({ "new", "issue", "c", "renumbered", "--project", "pickman" }),
			"(%a%d+)"
		) :: string
		trOk({ "status", old, "preparing" })
		local dir = `{wt}/pickman/.tracker/issues/{old}`
		local ready = fs.readFile(`{dir}/{old}.md`)
		fs.writeFile(`{dir}/{old}.md`, (string.gsub(ready, "design: draft", "design: ready")))
		local rec = trOk({ "design-record", old })
		fs.writeFile(
			`{dir}/design-review-001.md`,
			`# Review 001\n\nVerdict: approve\n\nDesign record: {rec}\n`
		)
		fs.writeFile(
			`{dir}/design-review-002.md`,
			"# Review 002\n\nVerdict: approve\n\nDesign record: aaaaaaaaaaaa\n"
		)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", `tracker: prep {old}` })
		local new = "c0777"
		trOk({ "renumber", old, new })
		local ndir = `{wt}/pickman/.tracker/issues/{new}`
		local fresh = trOk({ "design-record", new })
		t.expect(fresh ~= rec).toBe(true) -- the ids inside the design changed
		local one = fs.readFile(`{ndir}/design-review-001.md`)
		t.expect(string.find(one, `Design record: {fresh}`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(one, rec, 1, true) == nil).toBe(true)
		local two = fs.readFile(`{ndir}/design-review-002.md`)
		t.expect(string.find(two, "Design record: aaaaaaaaaaaa", 1, true) ~= nil).toBe(true) -- it did not match before
	end)

	it(
		"a renumbered member keeps its raft's grouped: record: the lines are re-recorded before grouped: is",
		function()
			local stub = "---\nid: c0920\ntype: chore\ntitle: Grouped\nslug: grouped\nraft: \ndepends_on: []\nemergent: false\n"
				.. "design: ready\nsize: 10\ncreated: 2026-01-01\nstatus: prepared-quiet-copper-falcon\n---\n\n# c0920\n"
			local rec = raftplan.designRecord("c0920", { ["c0920.md"] = stub, ["check.sh"] = "true\n" })
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "tracker: the earlier cases" })
			trackerfix.elsewhere(f, {
				["pickman/.tracker/issues/c0920/c0920.md"] = stub,
				["pickman/.tracker/issues/c0920/check.sh"] = "true\n",
				["pickman/.tracker/issues/c0920/design-review-001.md"] = `# Review 001\n\nVerdict: approve\n\nDesign record: {rec}\n`,
			}, "a prepared issue with an approving round")
			trOk({ "sync" })
			local raft = string.match(
				trOk({ "new", "raft", "chore", "grouped-raft", "c0920", "--project", "pickman" }),
				"(R%d+)"
			) :: string
			local rpath = `{wt}/pickman/.tracker/rafts/{raft}/{raft}.md`
			t.expect(string.find(fs.readFile(rpath), "grouped: [c0920@", 1, true) ~= nil).toBe(true)
			trOk({ "renumber", "c0920", "c0921" })
			local mdir = `{wt}/pickman/.tracker/issues/c0921`
			local onDisk: { [string]: string } = {}
			for _, name in { "c0921.md", "check.sh", "design-review-001.md" } do
				onDisk[name] = fs.readFile(`{mdir}/{name}`)
			end
			local grouped = string.match(fs.readFile(rpath), "\ngrouped: %[c0921@(%x+)%]")
			t.expect(grouped).toBe(raftplan.recordHash("c0921", onDisk)) -- hashed over the re-recorded review
			t.expect(
				string.find(
					onDisk["design-review-001.md"],
					`Design record: {raftplan.designRecord("c0921", onDisk)}`,
					1,
					true
				) ~= nil
			).toBe(true)
		end
	)

	it(
		"a renumber re-records an approving round that is not committed yet (renumber runs on a dirty tree)",
		function()
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "tracker: the earlier cases" })
			local old = string.match(
				trOk({ "new", "issue", "c", "untracked-round", "--project", "pickman" }),
				"(%a%d+)"
			) :: string
			trOk({ "status", old, "preparing" })
			local dir = `{wt}/pickman/.tracker/issues/{old}`
			fs.writeFile(
				`{dir}/design-review-001.md`,
				`# Review 001\n\nVerdict: approve\n\nDesign record: {trOk({ "design-record", old })}\n`
			) -- written after the last commit: untracked
			local new = "c0778"
			trOk({ "renumber", old, new })
			local quote = string.match(
				fs.readFile(`{wt}/pickman/.tracker/issues/{new}/design-review-001.md`),
				"Design record: (%x+)"
			)
			t.expect(quote).toBe(trOk({ "design-record", new }))
		end
	)

	it("a renumber re-records an issue that was not renamed but whose design names the renamed id", function()
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "tracker: the earlier case" })
		local target = string.match(
			trOk({ "new", "issue", "c", "renamed-target", "--project", "pickman" }),
			"(%a%d+)"
		) :: string
		local other = string.match(
			trOk({ "new", "issue", "c", "names-the-target", "--project", "pickman" }),
			"(%a%d+)"
		) :: string
		trOk({ "status", other, "preparing" })
		local odir = `{wt}/pickman/.tracker/issues/{other}`
		fs.writeFile(
			`{odir}/{other}.md`,
			fs.readFile(`{odir}/{other}.md`) .. `\n## Design\nBuilds on {target}.\n`
		)
		local rec = trOk({ "design-record", other })
		fs.writeFile(
			`{odir}/design-review-001.md`,
			`# Review 001\n\nVerdict: approve\n\nDesign record: {rec}\n`
		)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "tracker: two issues" })
		trOk({ "renumber", target, "c0779" })
		local fresh = trOk({ "design-record", other })
		t.expect(fresh ~= rec).toBe(true) -- the document names the renamed id, so its record changed
		local quote = string.match(fs.readFile(`{odir}/design-review-001.md`), "Design record: (%x+)")
		t.expect(quote).toBe(fresh)
	end)
end)
