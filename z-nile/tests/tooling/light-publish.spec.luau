--!strict
-- f0420 step 3 (review 003 F5): the publish guard lets ONE publish fill an empty `raft:` of a moved ticket: the light
-- path's claim, `ready <issue>`, which passes `lightClaim`. The exception is judged in validateMoves on the whole change
-- set; every rule, broken, is refused with a sentence naming what is wrong. A bare origin and a clone under .cache.
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
local base = `{here}/.cache/f0420-light-publish`
local origin, work = `{base}/origin.git`, `{base}/work`
local ROOT = "pickman/.tracker"
local CLAIM = "active-brisk-amber-otter"

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

local function doc(id: string, raft: string?, status: string, body: string?): string
	local line = if raft then `raft: {raft}\n` else ""
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\n{line}depends_on: []\ndesign: ready\nstatus: {status}\n---\n\n# {id}\n\n{body or "Body.\n"}`
end
local function raftDoc(id: string, over: { [string]: string }?): string
	local f: { [string]: string } = {
		single = "true",
		light = "true",
		issues = "[c0010]",
		status = CLAIM,
	}
	for k, v in (over or {}) :: { [string]: string } do
		f[k] = v
	end
	local lines = { "---", `id: {id}`, "type: chore", `title: {id}`, `slug: {id}` }
	for _, k in { "single", "light", "issues", "status" } do
		if f[k] ~= "" then
			table.insert(lines, `{k}: {f[k]}`)
		end
	end
	table.insert(lines, "design: ready")
	table.insert(lines, "---")
	table.insert(lines, "")
	return table.concat(lines, "\n") .. `# {id}\n`
end

type Tweak = {
	raftId: string?,
	ticket: string?, -- the ticket to claim
	rewrite: ((text: string) -> string)?,
	raft: { [string]: string }?,
	noRaftDoc: boolean?,
	noCheck: boolean?,
	noCounter: boolean?,
	to: string?, -- the destination directory instead of issues/active/<id>
	fromDir: string?, -- where the ticket is on origin, instead of issues/<id>
}

-- The changes `ready <issue>` publishes for `ticket`, as the light path builds them; `tweak` breaks one rule.
local function claim(list: { string }, read: (string) -> string?, tweak: Tweak?): { publish.Change }
	local tw: Tweak = tweak or {}
	local id = tw.ticket or "c0010"
	local rid = tw.raftId or "R0100"
	local from = tw.fromDir or `{ROOT}/issues/{id}`
	local dest = tw.to or `{ROOT}/issues/active/{id}`
	local out: { publish.Change } = {}
	for _, p in list do
		if string.sub(p, 1, #from + 1) == from .. "/" then
			local rel = string.sub(p, #from + 2)
			local text = read(p) :: string
			if rel == `{id}.md` then
				text = string.gsub(text, "status: [^\n]*", `status: {CLAIM}`)
				text = string.gsub(text, "\nraft: \n", `\nraft: {rid}\n`)
				if tw.rewrite then
					text = tw.rewrite(text)
				end
			end
			table.insert(out, { path = `{dest}/{rel}`, from = p, content = text })
		end
	end
	if not tw.noRaftDoc then
		table.insert(out, { path = `{ROOT}/rafts/active/{rid}/{rid}.md`, content = raftDoc(rid, tw.raft) })
	end
	if not tw.noCheck then
		table.insert(
			out,
			{ path = `{ROOT}/rafts/active/{rid}/check.sh`, content = "#!/bin/sh\n", mode = "100755" }
		)
	end
	if not tw.noCounter then
		table.insert(out, {
			path = ids.FILE,
			content = ids.format(
				{ issue = 100, raft = (ids.parse(read(ids.FILE) :: string) :: ids.Counters).raft + 50 },
				"x-y-z"
			),
		})
	end
	return out
end

local function attempt(tweak: Tweak?, lightClaim: boolean?): publish.Result
	return publish.commit(work, function(list, read)
		return claim(list, read, tweak)
	end, "tracker: ready R0100 c0010", nil, if lightClaim == false then nil else { lightClaim = true })
end
local function refused(r: publish.Result, before: string, needle: string)
	t.expect(r.ok).toBe(false)
	if not has(r.reason, needle) then
		error(`wanted "{needle}", got "{r.reason}"`)
	end
	t.expect(tip()).toBe(before)
end

return t.spec("f0420 step 3: the publish guard's one exception, the light path's claim", function(it)
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
		for _, id in { "c0010", "c0011", "c0014", "c0015", "c0016", "c0017" } do
			write(`{ROOT}/issues/{id}/{id}.md`, doc(id, "", "prepared-quiet-copper-falcon"))
			write(`{ROOT}/issues/{id}/check.sh`, "#!/bin/sh\n")
		end
		-- c0011 has a body line `raft:` and no front-matter key: a body-only line is never filled
		write(`{ROOT}/issues/c0011/c0011.md`, doc("c0011", nil, "prepared-quiet-copper-falcon", "raft: \n"))
		-- c0020 has front-matter lines that carry no key: an indented list item and a comment
		write(
			`{ROOT}/issues/c0020/c0020.md`,
			(
				string.gsub(
					doc("c0020", "", "prepared-quiet-copper-falcon"),
					"\ndesign: ready\n",
					"\ndesign: ready\ntags:\n  - alpha\n# a comment\n"
				)
			)
		)
		write(`{ROOT}/issues/c0020/check.sh`, "#!/bin/sh\n")
		-- c0012 already names a raft
		write(`{ROOT}/issues/c0012/c0012.md`, doc("c0012", "R0050", "prepared-quiet-copper-falcon"))
		write(`{ROOT}/issues/c0012/check.sh`, "#!/bin/sh\n")
		-- c0013 is active already, with an empty raft: line
		write(`{ROOT}/issues/active/c0013/c0013.md`, doc("c0013", "", "active-old-claim-stamp"))
		write(`{ROOT}/issues/active/c0013/check.sh`, "#!/bin/sh\n")
		-- R0099 exists on origin (a backlog raft folder)
		write(`{ROOT}/rafts/R0099/R0099.md`, raftDoc("R0099", { status = "prepared-quiet-copper-falcon" }))
		write(`{ROOT}/rafts/R0099/check.sh`, "#!/bin/sh\n")
		git(`{base}/seed`, { "add", "-A" })
		git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", `{base}/seed`, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, work })
		git(work, { "config", "user.name", "t" })
		git(work, { "config", "user.email", "t@example.invalid" })
	end)

	it("without the opt-in the same change set is refused: only status: may change in a move", function()
		local before = tip()
		refused(attempt(nil, false), before, "a moved document may only change its status: line")
	end)

	it(
		"accepted: the claim that adds its single light raft, the stamp, the check.sh and the counter raise",
		function()
			local before = tip()
			local r = attempt()
			t.expect(r.ok).toBe(true)
			t.expect(tip() ~= before).toBe(true)
			local files = git(origin, { "ls-tree", "-r", "--name-only", "main" })
			t.expect(has(files, `{ROOT}/rafts/active/R0100/R0100.md`)).toBe(true)
			t.expect(has(files, `{ROOT}/issues/active/c0010/c0010.md`)).toBe(true)
			t.expect(has(git(origin, { "show", `main:{ROOT}/issues/active/c0010/c0010.md` }), "raft: R0100"))
				.toBe(true)
			-- the origin counter is raised past R0100 for the next raft
			t.expect(ids.parse(git(origin, { "show", `main:{ids.FILE}` })))
				.toEqual({ issue = 100, raft = 150 })
		end
	)

	it("rule 1: only the front-matter raft: key may differ, and it must be empty on origin", function()
		git(work, { "pull", "-q", "origin", "main" })
		local before = tip()
		refused(
			attempt({
				ticket = "c0014",
				rewrite = function(s)
					return (string.gsub(s, "title: c0014 title", "title: changed"))
				end,
				raftId = "R0101",
				raft = { issues = "[c0014]" },
			}),
			before,
			"besides status: and raft:, the front matter differs in title"
		)
		refused(
			attempt({
				ticket = "c0014",
				rewrite = function(s)
					return s .. "More.\n"
				end,
				raftId = "R0101",
				raft = { issues = "[c0014]" },
			}),
			before,
			"the body differs from origin/main"
		)
		refused(
			attempt({
				ticket = "c0012",
				raftId = "R0101",
				raft = { issues = "[c0012]" },
				rewrite = function(s)
					return (string.gsub(s, "raft: R0050", "raft: R0101"))
				end,
			}),
			before,
			"c0012 already names R0050 on origin/main"
		)
		-- a body-only raft: line (no front-matter key) is never filled
		refused(
			attempt({
				ticket = "c0011",
				raftId = "R0101",
				raft = { issues = "[c0011]" },
				rewrite = function(s)
					return (string.gsub(s, "\nraft: \n", "\nraft: R0101\n"))
				end,
			}),
			before,
			"a moved document may only change its status: line"
		)
		-- not a raft id
		refused(
			attempt({
				ticket = "c0014",
				raftId = "R0101",
				raft = { issues = "[c0014]" },
				rewrite = function(s)
					return (string.gsub(s, "raft: R0101", "raft: nonsense"))
				end,
			}),
			before,
			"raft: nonsense is not a raft id"
		)
	end)

	it(
		"rule 2: the raft is a document added by this publish, single, light, listing exactly the ticket",
		function()
			local before = tip()
			local function broken(over: Tweak, needle: string)
				local tw: Tweak = { ticket = "c0014", raftId = "R0101", raft = { issues = "[c0014]" } }
				for k, v in over :: any do
					if k == "raft" then
						for k2, v2 in v :: any do
							(tw.raft :: any)[k2] = v2
						end
					else
						(tw :: any)[k] = v
					end
				end
				refused(attempt(tw), before, needle)
			end
			broken({ noRaftDoc = true }, "R0101 is not added by this publish at")
			broken({ raft = { single = "false" } }, "R0101 is not single: true")
			broken({ raft = { single = "" } }, "R0101 is not single: true")
			broken({ raft = { light = "false" } }, "R0101 does not say light: true")
			broken({ raft = { light = "" } }, "R0101 does not say light: true")
			broken({ raft = { issues = "[c0014, c0015]" } }, "must list exactly [c0014] in issues:")
			broken({ raft = { issues = "[c0015]" } }, "must list exactly [c0014] in issues:")
			broken(
				{ raft = { status = "active-another-stamp" } },
				"must carry the same status: claim stamp as c0014"
			)
			broken({ noCheck = true }, "R0101's check.sh is not added with it")
		end
	)

	it("rule 3: the ticket moves to issues/active/<id>/", function()
		local before = tip()
		refused(
			attempt({
				ticket = "c0013",
				raftId = "R0101",
				raft = { issues = "[c0013]" },
				to = `{ROOT}/issues/c0013`,
				fromDir = `{ROOT}/issues/active/c0013`,
				rewrite = function(s)
					return s
				end,
			}),
			before,
			"must move to"
		)
	end)

	it("rule 4: the raft is new on origin, and the counter is raised past it", function()
		local before = tip()
		refused(
			attempt({ ticket = "c0014", raftId = "R0099", raft = { issues = "[c0014]" } }),
			before,
			"R0099 is not new: origin/main already has"
		)
		refused(
			attempt({ ticket = "c0014", raftId = "R0101", raft = { issues = "[c0014]" }, noCounter = true }),
			before,
			"the counter raise past R0101 (z-nile/next) is not in this publish"
		)
	end)

	it("rule 5: at most one such document per publish", function()
		local before = tip()
		local r = publish.commit(work, function(list, read)
			local out =
				claim(list, read, { ticket = "c0014", raftId = "R0101", raft = { issues = "[c0014]" } })
			for _, c in
				claim(list, read, { ticket = "c0015", raftId = "R0102", raft = { issues = "[c0015]" } })
			do
				if c.path ~= ids.FILE then
					table.insert(out, c)
				end
			end
			return out
		end, "tracker: two claims", nil, { lightClaim = true })
		refused(r, before, "at most one document per publish may fill its raft: line")
	end)

	it("no other mover passes the opt-in: ready <issue> is the only call that does", function()
		local count = 0
		for _, name in fs.readDir(`{TOP}/z-nile/engine`) do
			if string.match(name, "%.luau$") then
				local text = fs.readFile(`{TOP}/z-nile/engine/{name}`)
				for _ in string.gmatch(text, "lightClaim = true") do
					count += 1
				end
			end
		end
		t.expect(count).toBe(1)
		t.expect(
			string.find(fs.readFile(`{TOP}/z-nile/engine/main.luau`), "lightClaim = true", 1, true) ~= nil
		)
			.toBe(true)
	end)

	it("rule 1 (whole block): a front-matter line without a key may not change either", function()
		local before = tip()
		for _, change in
			{
				{ "  %- alpha", "  - beta" },
				{ "# a comment", "# another comment" },
			}
		do
			refused(
				attempt({
					ticket = "c0020",
					raftId = "R0101",
					raft = { issues = "[c0020]" },
					rewrite = function(text)
						return (string.gsub(text, change[1], change[2]))
					end,
				}),
				before,
				"besides status: and raft:, the front matter differs in a line without a key"
			)
		end
	end)

	it(
		"c0435 review 3 B: the raise exception accepts only a raise of this ticket and this light raft",
		function()
			local raise: publish.Raise = { ticket = "c0010", raft = "R0001", level = "normal" }
			local function ticketDoc(over: { [string]: string }?, body: string?): string
				local f: { [string]: string } = {
					id = "c0010",
					title = "c0010 title",
					risk = "easy",
					design = "ready",
					raft = "R0001",
					status = "active-a-b-c",
				}
				for k, v in (over or {}) :: { [string]: string } do
					f[k] = v
				end
				local lines = { "---" }
				for _, k in { "id", "title", "risk", "design", "raft", "status" } do
					if f[k] ~= "" then
						table.insert(lines, `{k}: {f[k]}`)
					end
				end
				table.insert(lines, "---")
				return table.concat(lines, "\n") .. `\n\n# c0010\n\n{body or "Body.\n"}`
			end
			local good = ticketDoc({ risk = "normal", design = "draft", raft = "", status = "new-a-b-c" })
			t.expect(publish.raiseEdit("c0010", ticketDoc(), good, raise)).toBe(true)
			local function refused(why: string, new: string, id: string?, old: string?, r: publish.Raise?)
				t.expect(publish.raiseEdit(id or "c0010", old or ticketDoc(), new, r or raise)).toBe(false)
				t.expect(why ~= "").toBe(true)
			end
			refused(
				"risk lowered",
				ticketDoc({ risk = "easy", design = "draft", raft = "" }),
				nil,
				ticketDoc({ risk = "normal" })
			)
			refused(
				"risk equal to easy",
				ticketDoc({ risk = "easy", design = "draft", raft = "" }),
				nil,
				nil,
				{ ticket = "c0010", raft = "R0001", level = "easy" }
			)
			refused(
				"risk unknown",
				ticketDoc({ risk = "hard", design = "draft", raft = "" }),
				nil,
				nil,
				{ ticket = "c0010", raft = "R0001", level = "hard" }
			)
			refused("risk not the raised level", ticketDoc({ risk = "risky", design = "draft", raft = "" }))
			refused("another ticket's document", good, "c9999")
			refused("body edit", ticketDoc({ risk = "normal", design = "draft", raft = "" }, "Other body.\n"))
			refused("design not draft", ticketDoc({ risk = "normal", design = "ready", raft = "" }))
			refused(
				"raft set to another raft",
				ticketDoc({ risk = "normal", design = "draft", raft = "R9999" })
			)
			refused(
				"a second key changed",
				ticketDoc({ risk = "normal", design = "draft", raft = "", title = "other" })
			)
			refused("the ticket was not in this raft", good, nil, ticketDoc({ raft = "R7777" }))
			-- the raft's document: its one ticket leaves, and only if it is a light raft
			local function raftOf(issues: string, light: string?): string
				return `---\nid: R0001\nsingle: true\n{if light then `light: {light}\n` else ""}issues: {issues}\nstatus: active-a-b-c\n---\n\n# R0001\n`
			end
			t.expect(publish.raiseEdit("R0001", raftOf("[c0010]", "true"), raftOf("[]", "true"), raise))
				.toBe(true)
			t.expect(publish.raiseEdit("R0001", raftOf("[c0010]"), raftOf("[]"), raise)).toBe(false) -- not light
			t.expect(publish.raiseEdit("R0001", raftOf("[c0011]", "true"), raftOf("[]", "true"), raise))
				.toBe(false)
			t.expect(publish.raiseEdit("R0001", raftOf("[c0010]", "true"), raftOf("[c0010]", "true"), raise))
				.toBe(false)
			t.expect(publish.raiseEdit("R0002", raftOf("[c0010]", "true"), raftOf("[]", "true"), raise))
				.toBe(false)
			-- a risk already raised on main (the author edited it first) is still allowed to stop, a lower one is not
			local already = ticketDoc({ risk = "normal" })
			t.expect(publish.raiseEdit("c0010", already, good, raise)).toBe(true)
			t.expect(publish.raiseEdit("c0010", ticketDoc({ risk = "risky" }), good, raise)).toBe(false)
		end
	)
end)
