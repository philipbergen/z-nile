--!strict
-- c0249 AC10: a `rank:` edit must not void a design hash or an approval, and the publisher takes it only for a backlog
-- item. raftplan.designHash and recordHash (a raft's `grouped:` record) leave the rank line out as they leave `status:` and
-- `raft:` out; the approval contract does not read the front matter at all; publish.commit accepts a change to the rank
-- line of a backlog document (with or without a status change) and refuses it on an active or a done one, refuses two
-- rank lines and any other front-matter change beside it. Fixture under .cache/c0249-hash.
local contract = require("@znile/engine/contract")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local publish = require("@znile/engine/publish")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0249-hash`
local origin, work = `{base}/origin.git`, `{base}/work`
-- raw git only to make a repository at a path this spec names (`init`, `clone`); everything else goes through
-- @tests/lib/fixture, which refuses a directory that is not a fixture repository under .cache
local function create(cwd: string, args: { string })
	local r: Result = process.exec("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
end
local function identity(cwd: string)
	fixture.git(cwd, { "config", "user.name", "t" })
	fixture.git(cwd, { "config", "user.email", "t@example.invalid" })
end

local BACKLOG = "pickman/.tracker/issues/c0010"
local ACTIVE = "pickman/.tracker/issues/active/c0020"
local DONE = "pickman/.tracker/issues/done/c0030"
local RAFT = "pickman/.tracker/rafts/R0010"
local RETIRED = "pickman/.tracker/rafts/retired/R0099"
local function doc(id: string, rank: string?, status: string?, title: string?): string
	return `---\nid: {id}\n{rank and `rank: {rank}\n` or ""}type: chore\ntitle: {title or id}\nslug: {id}\nstatus: {status or "new-a-b-c"}\n---\n\n# {id}\n`
end

return t.spec("c0249 a rank edit meets every hash and guard", function(it)
	it("AC10: designHash and recordHash leave the rank line out, and nothing else", function()
		local plain = doc("c0010", nil)
		t.expect(raftplan.designHash(doc("c0010", "30"))).toBe(raftplan.designHash(plain))
		t.expect(raftplan.designHash(doc("c0010", "40"))).toBe(raftplan.designHash(doc("c0010", "30")))
		t.expect(raftplan.designHash(doc("c0010", "30", "prepared-x-y-z"))).toBe(raftplan.designHash(plain))
		-- a different title, a body edit and a key that only starts with rank still change it
		t.expect(raftplan.designHash(doc("c0010", nil, nil, "Other")) ~= raftplan.designHash(plain))
			.toBe(true)
		t.expect(raftplan.designHash(plain .. "more\n") ~= raftplan.designHash(plain)).toBe(true)
		t.expect(
			raftplan.designHash((string.gsub(plain, "\nstatus:", "\nranked: 3\nstatus:")))
				~= raftplan.designHash(plain)
		).toBe(true)
		-- a body line that says rank: is part of the design
		t.expect(raftplan.designHash(plain .. "rank: 3\n") ~= raftplan.designHash(plain)).toBe(true)
		-- a grouped member's record is the same with a rank, and changes with its check.sh as it did
		local files = { ["c0010.md"] = plain, ["check.sh"] = "check\n", ["acceptance/a.spec.luau"] = "x\n" }
		local ranked = table.clone(files)
		ranked["c0010.md"] = doc("c0010", "30")
		t.expect(raftplan.recordHash("c0010", ranked)).toBe(raftplan.recordHash("c0010", files))
		ranked["check.sh"] = "check changed\n"
		t.expect(raftplan.recordHash("c0010", ranked) ~= raftplan.recordHash("c0010", files)).toBe(true)
	end)

	it("AC10: the approval contract does not read the rank", function()
		local function parts(text: string): { [string]: string }
			return contract.build(text, "check\n", { ["a.spec.luau"] = "x\n" }) :: { [string]: string }
		end
		local withBody = function(front: string): string
			return `---\nid: c0010\n{front}status: prepared-a-b-c\n---\n\n# c0010\n\n## Problem\nP.\n\n## Design\nD.\n`
		end
		t.expect(contract.hash(parts(withBody("rank: 30\n")))).toBe(contract.hash(parts(withBody(""))))
		t.expect(
			contract.hash(parts(withBody("rank: 30\n")))
				~= contract.hash(parts(withBody("") .. "## Test plan\nT.\n"))
		).toBe(true)
	end)

	it("sets up a bare origin with a backlog, an active, a done and a raft document", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/seed`)
		create(`{base}/seed`, { "init", "-q", "-b", "main" })
		identity(`{base}/seed`)
		engine.registry(`{base}/seed`)
		for dir, text in
			{
				[BACKLOG] = doc("c0010", "20"),
				[ACTIVE] = doc("c0020", nil, "active-a-b-c"),
				[DONE] = doc("c0030", nil, "done-a-b-c"),
				[RETIRED] = (string.gsub(
					doc("R0099", nil, "preparing-a-b-c"),
					"slug: R0099",
					"slug: R0099\nissues: []"
				)),
				[RAFT] = (
					string.gsub(doc("R0010", nil, "prepared-a-b-c"), "slug: R0010", "slug: R0010\nissues: []")
				),
			} :: { [string]: string }
		do
			local id = string.match(dir, "([^/]+)$") :: string
			fs.writeDir(`{base}/seed/{dir}`)
			fs.writeFile(`{base}/seed/{dir}/{id}.md`, text)
		end
		fixture.git(`{base}/seed`, { "add", "-A" })
		fixture.git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
		create(base, { "clone", "-q", "--bare", `{base}/seed`, origin })
		create(base, { "clone", "-q", origin, work })
		identity(work)
	end)

	it(
		"AC10: the publisher takes a rank change on a backlog document, alone or with a status change",
		function()
			local function publishDoc(path: string, text: string, message: string): publish.Result
				return publish.commit(work, function()
					return { { path = path, content = text } }
				end, message)
			end
			local id = BACKLOG .. "/c0010.md"
			local r1 = publishDoc(id, doc("c0010", "25"), "tracker: rank c0010 25")
			t.expect(r1.ok).toBe(true)
			t.expect(string.find(fixture.git(origin, { "show", `main:{id}` }), "rank: 25\n", 1, true) ~= nil)
				.toBe(true)
			local r2 = publishDoc(id, doc("c0010", nil), "tracker: rank c0010 unset")
			t.expect(r2.ok).toBe(true)
			t.expect((string.find(fixture.git(origin, { "show", `main:{id}` }), "rank", 1, true))).toBe(nil)
			local r3 = publishDoc(id, doc("c0010", "5", "preparing-d-e-f"), "tracker: rank and status")
			t.expect(r3.ok).toBe(true)
			-- a raft's document takes it too
			t.expect(
				publishDoc(
					RAFT .. "/R0010.md",
					(
						string.gsub(
							doc("R0010", "7", "prepared-a-b-c"),
							"slug: R0010",
							"slug: R0010\nissues: []"
						)
					),
					"tracker: rank R0010"
				).ok
			).toBe(true)
		end
	)

	it(
		"AC10: it refuses a rank change on an active or a done document, naming the file and the rule",
		function()
			local before = fixture.git(origin, { "rev-parse", "main" })
			for path, text in
				{
					[ACTIVE .. "/c0020.md"] = doc("c0020", "3", "active-a-b-c"),
					[DONE .. "/c0030.md"] = doc("c0030", "3", "done-a-b-c"),
				} :: { [string]: string }
			do
				local r = publish.commit(work, function()
					return { { path = path, content = text } }
				end, "tracker: bad rank")
				t.expect(r.ok).toBe(false)
				local reason = r.reason or ""
				t.expect(string.find(reason, path, 1, true) ~= nil).toBe(true)
				t.expect(string.find(reason, "a rank is published for a backlog item only", 1, true) ~= nil)
					.toBe(true)
			end
			-- a retired raft is no tracker item file to the publisher at all: it refuses the rank (any edit) there too
			local retired = publish.commit(work, function()
				return {
					{
						path = RETIRED .. "/R0099.md",
						content = (string.gsub(
							doc("R0099", "3", "preparing-a-b-c"),
							"slug: R0099",
							"slug: R0099\nissues: []"
						)),
					},
				}
			end, "tracker: bad rank")
			t.expect(retired.ok).toBe(false)
			t.expect(string.find(retired.reason or "", "is not a tracker item file", 1, true) ~= nil)
				.toBe(true)
			t.expect(fixture.git(origin, { "rev-parse", "main" })).toBe(before)
		end
	)

	it("AC10: it refuses two rank lines, and a rank change beside any other front-matter change", function()
		local before = fixture.git(origin, { "rev-parse", "main" })
		local id = BACKLOG .. "/c0010.md"
		local function refused(text: string)
			local r = publish.commit(work, function()
				return { { path = id, content = text } }
			end, "tracker: bad")
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.reason or "", "may only edit its status: line", 1, true) ~= nil).toBe(true)
		end
		refused((string.gsub(doc("c0010", "9"), "rank: 9\n", "rank: 9\nrank: 8\n")))
		refused(doc("c0010", "9", nil, "A new title"))
		refused(doc("c0010", "9") .. "an edited body\n")
		refused((string.gsub(doc("c0010", "9"), "type: chore", "type: feature")))
		t.expect(fixture.git(origin, { "rev-parse", "main" })).toBe(before)
	end)
	it(
		"AC2: the publisher hands a build many files of its base in one read, and nil for a file that is not there",
		function()
			local got: { string? } = {}
			local r = publish.commit(work, function(_paths, _read, _roots, _counter, readMany)
				got = (readMany :: ({ string }) -> { string? })({
					BACKLOG .. "/c0010.md",
					"pickman/.tracker/issues/c9999/c9999.md",
					ACTIVE .. "/c0020.md",
				})
				return {}
			end, "tracker: nothing")
			t.expect(r.ok).toBe(true)
			t.expect(got[1] ~= nil and string.find(got[1] :: string, "\nid: c0010\n", 1, true) ~= nil)
				.toBe(true)
			t.expect(got[2]).toBe(nil)
			t.expect(got[3] ~= nil and string.find(got[3] :: string, "\nid: c0020\n", 1, true) ~= nil)
				.toBe(true)
		end
	)
end)
