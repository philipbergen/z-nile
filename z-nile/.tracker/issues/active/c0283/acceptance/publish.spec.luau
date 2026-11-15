--!strict
-- c0283 AC6: the publish validator takes an `approved` row of an issue's provenance.md only in the commit that also
-- appends the matching row to its approval.md (the same human, `design=` the first 12 hex of the appended row's hash),
-- through publish.commit with crafted changes. A row alone, a mismatched human or hash, two rows, an old approval row
-- rewritten and an `active` issue are refused naming the file; `PUBLISHED` stays unwidened, so an approval.md alone is
-- as it was and `./zn provenance record` cannot publish an approval.
local contract = require("@znile/engine/contract")
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0283-publish`
local origin, work = `{base}/origin.git`, `{base}/work`

local function git(cwd: string, args: { string }): string
	local r: Result = process.exec("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function identity(cwd: string)
	git(cwd, { "config", "user.name", "t" })
	git(cwd, { "config", "user.email", "t@example.invalid" })
end

local ISSUE = "pickman/.tracker/issues/c0010"
local ACTIVE = "pickman/.tracker/issues/active/c0020"
local HASH = string.rep("ab", 32)
local OTHER = string.rep("cd", 32)
local function doc(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nstatus: prepared-a-b-c\n---\n\n# {id}\n`
end
local function approvals(rows: { { who: string, hash: string } }): string
	local out: { contract.Row } = {}
	for i, r in rows do
		table.insert(out, {
			when = `2026-11-1{i}T09:00:00Z`,
			who = r.who,
			hash = r.hash,
			parts = { design = r.hash, ["check.sh"] = r.hash },
		})
	end
	return contract.render(out)
end
local function approved(id: string, rows: { { who: string, hash: string } }): string
	local out: { provenance.Row } = {}
	for i, r in rows do
		table.insert(out, {
			when = `2026-11-1{i} 09:00`,
			event = "approved",
			actor = `human:{r.who}`,
			detail = `design={string.sub(r.hash, 1, 12)}`,
		})
	end
	return provenance.render(id, out)
end
local ANN = { who = "Ann Lee", hash = HASH }
local BOB = { who = "Bob", hash = OTHER }

return t.spec("c0283 publishing an approval with its approved row", function(it)
	local function tip(): string
		return git(origin, { "rev-parse", "main" })
	end
	local function commit(changes: { publish.Change }): publish.Result
		return publish.commit(work, function()
			return changes
		end, "tracker: approve c0010")
	end
	local function refused(changes: { publish.Change }, why: string)
		local before = tip()
		local r = commit(changes)
		t.expect(r.ok).toBe(false)
		if not string.find(r.reason or "", why, 1, true) then
			error(`reason lacks "{why}": {r.reason}`, 2)
		end
		t.expect(tip()).toBe(before)
	end

	it("sets up a bare origin with a prepared issue and an active one", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/seed`)
		git(`{base}/seed`, { "init", "-q", "-b", "main" })
		identity(`{base}/seed`)
		engine.registry(`{base}/seed`)
		for dir, id in { [ISSUE] = "c0010", [ACTIVE] = "c0020" } do
			fs.writeDir(`{base}/seed/{dir}`)
			fs.writeFile(`{base}/seed/{dir}/{id}.md`, doc(id))
		end
		git(`{base}/seed`, { "add", "-A" })
		git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
		git(base, { "clone", "-q", "--bare", `{base}/seed`, origin })
		git(base, { "clone", "-q", origin, work })
		identity(work)
	end)

	it("refuses an approved row alone, and a record command cannot publish one", function()
		refused({ { path = `{ISSUE}/provenance.md`, content = approved("c0010", { ANN }) } }, "approved")
		-- beside an approval.md that did not change: not an appended row
		refused({
			{ path = `{ISSUE}/provenance.md`, content = approved("c0010", { ANN }) },
			{ path = `{ISSUE}/approval.md`, content = approvals({}) },
		}, "provenance.md")
		t.expect(table.find(provenance.PUBLISHED, "approved")).toBe(nil)
	end)

	it("refuses a row whose human or hash is not the appended approval's, and two rows", function()
		local ok = approvals({ ANN })
		local eve = approved("c0010", { { who = "Eve", hash = HASH } })
		refused({
			{ path = `{ISSUE}/provenance.md`, content = eve },
			{ path = `{ISSUE}/approval.md`, content = ok },
		}, "human")
		local wrong = approved("c0010", { { who = "Ann Lee", hash = OTHER } })
		refused({
			{ path = `{ISSUE}/provenance.md`, content = wrong },
			{ path = `{ISSUE}/approval.md`, content = ok },
		}, "design=")
		local two = approved("c0010", { ANN, ANN })
		refused({
			{ path = `{ISSUE}/provenance.md`, content = two },
			{ path = `{ISSUE}/approval.md`, content = ok },
		}, "exactly one")
		-- two approval rows with one record row
		refused({
			{ path = `{ISSUE}/provenance.md`, content = approved("c0010", { ANN }) },
			{ path = `{ISSUE}/approval.md`, content = approvals({ ANN, BOB }) },
		}, "exactly one")
		-- another issue's approval.md is not the matching one
		refused({
			{ path = `{ISSUE}/provenance.md`, content = approved("c0010", { ANN }) },
			{ path = `{ACTIVE}/approval.md`, content = ok },
		}, "provenance.md")
		-- an active issue takes no approved row
		refused({
			{ path = `{ACTIVE}/provenance.md`, content = approved("c0020", { ANN }) },
			{ path = `{ACTIVE}/approval.md`, content = ok },
		}, "active")
	end)

	it("publishes the matching pair in one commit, and a second approval appends", function()
		local before = git(origin, { "rev-list", "--count", "main" })
		local first = commit({
			{ path = `{ISSUE}/approval.md`, content = approvals({ ANN }) },
			{ path = `{ISSUE}/provenance.md`, content = approved("c0010", { ANN }) },
		})
		if not first.ok then
			error(first.reason or "not ok")
		end
		t.expect(git(origin, { "rev-list", "--count", "main" }))
			.toBe(tostring(tonumber(before) :: number + 1))
		local files = git(origin, { "show", "--name-only", "--format=", "main" })
		t.expect(files).toBe(`{ISSUE}/approval.md\n{ISSUE}/provenance.md`)
		-- the row reached main, so `who` and the board can read it
		local rows =
			provenance.parse(git(origin, { "show", `main:{ISSUE}/provenance.md` }) .. "\n") :: { provenance.Row }
		t.expect(#rows).toBe(1)
		t.expect(rows[1].actor).toBe("human:Ann Lee")
		-- a redesign and a second approval by another human appends to both
		git(work, { "pull", "-q", "origin", "main" })
		local second = commit({
			{ path = `{ISSUE}/approval.md`, content = approvals({ ANN, BOB }) },
			{ path = `{ISSUE}/provenance.md`, content = approved("c0010", { ANN, BOB }) },
		})
		if not second.ok then
			error(second.reason or "not ok")
		end
		-- an old approval row rewritten alongside a valid new row is refused
		git(work, { "pull", "-q", "origin", "main" })
		refused({
			{ path = `{ISSUE}/approval.md`, content = approvals({ { who = "Eve", hash = HASH }, BOB, ANN }) },
			{ path = `{ISSUE}/provenance.md`, content = approved("c0010", { ANN, BOB, ANN }) },
		}, "differs from origin/main")
	end)

	it("still publishes an approval.md alone, as before", function()
		git(work, { "pull", "-q", "origin", "main" })
		local alone = commit({ { path = `{ACTIVE}/approval.md`, content = approvals({ ANN }) } })
		t.expect(alone.ok).toBe(true)
	end)
end)
