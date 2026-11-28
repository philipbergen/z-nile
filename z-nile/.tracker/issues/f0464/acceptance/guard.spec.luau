--!strict
-- f0464 AC7: the publish guard's one exception (publish.luau, lightClaim: a moved ticket may fill its empty `raft:`
-- only with the single raft the same publish adds) takes a single raft with no `light:` line as well as one that says
-- `light: true`, and refuses any other `light:` value with a sentence naming it, publishing nothing. A bare origin and
-- a clone under .cache/f0464-guard.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ids = require("@znile/engine/ids")
local process = require("@lune/process")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local TOP = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{here}/.cache/f0464-guard`
local origin, work = `{base}/origin.git`, `{base}/work`
local ROOT = "pickman/.tracker"
local CLAIM = "active-brisk-amber-otter"
local NONE = "<none>" -- a light: value that means: no light: line at all
local EMPTY = "<empty>" -- a light: line with no value

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function tip(): string
	return git(origin, { "rev-parse", "main" })
end
local function has(s: string?, needle: string): boolean
	return s ~= nil and string.find(s, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	local full = `{base}/seed/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end

local function doc(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: \ndepends_on: []\ndesign: ready\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\nBody.\n`
end

local function raftDoc(id: string, ticket: string, light: string): string
	local lines = { "---", `id: {id}`, "type: chore", `title: {id}`, `slug: {id}`, "single: true" }
	if light == EMPTY then
		table.insert(lines, "light:")
	elseif light ~= NONE then
		table.insert(lines, `light: {light}`)
	end
	table.insert(lines, `issues: [{ticket}]`)
	table.insert(lines, `status: {CLAIM}`)
	table.insert(lines, "design: ready")
	table.insert(lines, "---")
	table.insert(lines, "")
	return table.concat(lines, "\n") .. `# {id}\n`
end

-- The changes `ready <issue>` publishes for `ticket` with a single raft `rid` whose light: is `light`.
local function attempt(ticket: string, rid: string, light: string): publish.Result
	return publish.commit(work, function(list, read)
		local from = `{ROOT}/issues/{ticket}`
		local out: { publish.Change } = {}
		for _, p in list do
			if string.sub(p, 1, #from + 1) == from .. "/" then
				local rel = string.sub(p, #from + 2)
				local text = read(p) :: string
				if rel == `{ticket}.md` then
					text = string.gsub(text, "status: [^\n]*", `status: {CLAIM}`)
					text = string.gsub(text, "\nraft: \n", `\nraft: {rid}\n`)
				end
				table.insert(out, { path = `{ROOT}/issues/active/{ticket}/{rel}`, from = p, content = text })
			end
		end
		table.insert(
			out,
			{ path = `{ROOT}/rafts/active/{rid}/{rid}.md`, content = raftDoc(rid, ticket, light) }
		)
		table.insert(
			out,
			{ path = `{ROOT}/rafts/active/{rid}/check.sh`, content = "#!/bin/sh\n", mode = "100755" }
		)
		local was = ids.parse(read(ids.FILE) :: string) :: ids.Counters
		table.insert(out, {
			path = ids.FILE,
			content = ids.format(
				{ issue = was.issue, raft = math.max(was.raft, ids.number(rid)) + 1 },
				"x-y-z"
			),
		})
		return out
	end, `tracker: ready {rid} {ticket}`, nil, { lightClaim = true })
end

return t.spec("f0464 the publish guard takes a single raft that is not light", function(it)
	it("sets up a bare origin and a clone with tickets to claim", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/seed`)
		process.exec("git", { "init", "-q", "-b", "main", `{base}/seed` }) -- raw: init to a named path
		git(`{base}/seed`, { "config", "user.name", "t" })
		git(`{base}/seed`, { "config", "user.email", "t@example.invalid" })
		write("z-nile/projects.toml", fs.readFile(`{TOP}/z-nile/projects.toml`))
		write(ids.FILE, ids.format({ issue = 100, raft = 100 }, "a-b-c"))
		write(`{ROOT}/issues/active/.gitkeep`, "")
		for _, id in { "c0010", "c0011", "c0012" } do
			write(`{ROOT}/issues/{id}/{id}.md`, doc(id))
			write(`{ROOT}/issues/{id}/check.sh`, "#!/bin/sh\n")
		end
		git(`{base}/seed`, { "add", "-A" })
		git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", `{base}/seed`, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, work })
		git(work, { "config", "user.name", "t" })
		git(work, { "config", "user.email", "t@example.invalid" })
	end)

	it("AC7: a light: value other than true is refused with its words, and nothing is published", function()
		local before = tip()
		for _, case in
			{
				{
					light = "false",
					words = "R0110's light: is false: a single raft ready makes says light: true or has no light: line",
				},
				{
					light = "yes",
					words = "R0110's light: is yes: a single raft ready makes says light: true or has no light: line",
				},
				{
					light = EMPTY,
					words = "R0110's light: is empty: a single raft ready makes says light: true or has no light: line",
				},
			}
		do
			local r = attempt("c0010", "R0110", case.light)
			t.expect(r.ok).toBe(false)
			if not has(r.reason, case.words) then
				error(`wanted "{case.words}", got "{r.reason}"`)
			end
			t.expect(tip()).toBe(before)
		end
	end)

	it(
		"AC7: a single raft with no light: line is accepted, and one that says light: true still is",
		function()
			local before = tip()
			local plain = attempt("c0011", "R0120", NONE)
			t.expect(plain.ok).toBe(true)
			t.expect(tip() ~= before).toBe(true)
			local moved = git(origin, { "show", `main:{ROOT}/issues/active/c0011/c0011.md` })
			t.expect(has(moved, "raft: R0120")).toBe(true)
			local raft = git(origin, { "show", `main:{ROOT}/rafts/active/R0120/R0120.md` })
			t.expect(has(raft, "\nlight:")).toBe(false)
			git(work, { "pull", "-q", "--ff-only", "origin", "main" })
			local lit = attempt("c0012", "R0130", "true")
			t.expect(lit.ok).toBe(true)
			t.expect(has(git(origin, { "show", `main:{ROOT}/rafts/active/R0130/R0130.md` }), "\nlight: true"))
				.toBe(true)
		end
	)
end)
