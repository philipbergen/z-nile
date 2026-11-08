--!strict
-- c0263 AC6: the publish validator's provenance.md branch, through publish.commit with crafted changes (the way
-- c0053's publish spec drives it for documents). A record may be created or appended to in a backlog folder, an issue's
-- or a raft's; an edited, removed or reordered row, a create that does not parse, a record in active/ and a record with
-- no document beside it are refused, naming the file.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0263-publish`
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
local RAFT = "pickman/.tracker/rafts/R0010"
local ACTIVE = "pickman/.tracker/issues/active/c0020"
local function doc(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nstatus: new-a-b-c\n---\n\n# {id}\n`
end
local function header(id: string): string
	return `# Provenance: {id}\n\n| when | event | actor | detail |\n|---|---|---|---|\n`
end
local function row(event: string, actor: string, detail: string): string
	return `| 2026-11-08 10:00 | {event} | {actor} | {detail} |\n`
end
local function one(id: string): string
	return header(id) .. row("approved", "human:Ann", "design=aaaaaaaaaaaa")
end

return t.spec("c0263 publish and provenance.md", function(it)
	it("sets up a bare origin with an issue, a raft and an active issue", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/seed`)
		git(`{base}/seed`, { "init", "-q", "-b", "main" })
		identity(`{base}/seed`)
		engine.registry(`{base}/seed`)
		for dir, id in { [ISSUE] = "c0010", [RAFT] = "R0010", [ACTIVE] = "c0020" } do
			fs.writeDir(`{base}/seed/{dir}`)
			fs.writeFile(`{base}/seed/{dir}/{id}.md`, doc(id))
		end
		git(`{base}/seed`, { "add", "-A" })
		git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
		git(base, { "clone", "-q", "--bare", `{base}/seed`, origin })
		git(base, { "clone", "-q", origin, work })
		identity(work)
	end)

	it("the file name is allowed in a backlog item's folder and nowhere odd", function()
		for _, ok in { `{ISSUE}/provenance.md`, `{RAFT}/provenance.md`, "pickman/.tracker/issues/done/c0010/provenance.md" } do
			t.expect(publish.allowed(ok, { "pickman/.tracker" })).toBe(true)
		end
		for _, bad in { "pickman/.tracker/provenance.md", `{ISSUE}/sub/provenance.md`, `{ISSUE}/provenance.txt` } do
			t.expect(publish.allowed(bad, { "pickman/.tracker" })).toBe(false)
		end
	end)

	it("a create and an append are accepted, everything else is refused naming the file", function()
		local made = publish.commit(work, function()
			return { { path = `{ISSUE}/provenance.md`, content = one("c0010") } }
		end, "tracker: record c0010")
		t.expect(made.ok).toBe(true)
		local first = git(origin, { "show", `main:{ISSUE}/provenance.md` })
		local before = git(origin, { "rev-parse", "main" })
		local function refused(content: string, path: string?, why: string)
			local r = publish.commit(work, function()
				return { { path = path or `{ISSUE}/provenance.md`, content = content } }
			end, "tracker: bad")
			t.expect(r.ok).toBe(false)
			if not string.find(r.reason or "", why, 1, true) then
				error(`reason lacks "{why}": {r.reason}`, 2)
			end
			t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		end
		-- an edited row
		refused((string.gsub(first, "human:Ann", "human:Eve")), nil, "provenance.md")
		-- a row removed (nothing appended)
		refused(header("c0010"), nil, "provenance.md")
		-- nothing appended
		refused(first, nil, "provenance.md")
		-- a create that does not parse, in a folder with no record yet
		refused("not a record\n", `{RAFT}/provenance.md`, "provenance.md")
		-- another item's header
		refused(one("c0099"), `{RAFT}/provenance.md`, "provenance.md")
		-- active/: the record is recorded on the raft's branch
		refused(one("c0020"), `{ACTIVE}/provenance.md`, "active")
		-- no document beside it
		refused(one("c0030"), "pickman/.tracker/issues/c0030/provenance.md", "c0030")
		-- a valid append, and a valid create in a raft's folder
		local more = first .. row("unblocked", "human:Bee", "")
		t.expect(publish.commit(work, function()
			return { { path = `{ISSUE}/provenance.md`, content = more } }
		end, "tracker: record").ok).toBe(true)
		local raft = header("R0010") .. row("unblocked", "human:Bee", "block=needs-decision")
		t.expect(publish.commit(work, function()
			return { { path = `{RAFT}/provenance.md`, content = raft } }
		end, "tracker: record raft").ok).toBe(true)
	end)
end)
