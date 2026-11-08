--!strict
-- c0263 AC8, AC9: `./zn who <id>` merges what git says with the record, and the board shows the same. The history is
-- built here with distinct authors in a repository with a bare origin: a capture, status changes, a rafting merge, an
-- unfold, a second rafting, the move to done/ with an agent trailer, and a stored record whose rows win over the git
-- fallbacks. An old item (no record) is answered from git alone, with nothing written.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{fixture.physical(".")}/.cache/c0263-who`
local dir, origin = `{base}/main`, `{base}/origin.git`
local IDS = "pickman/.tracker/issues"
local OPUS = "agent:claude-opus-5-5 effort high"

local function env(name: string): { [string]: string }
	return {
		GIT_AUTHOR_NAME = name,
		GIT_AUTHOR_EMAIL = `{name}@example.invalid`,
		GIT_COMMITTER_NAME = name,
		GIT_COMMITTER_EMAIL = `{name}@example.invalid`,
		CLAUDECODE = "",
		AI_AGENT = "",
		CLAUDE_EFFORT = "",
		ZN_ACTOR = "",
	}
end
local function git(cwd: string, args: { string }, who: string?): string
	local r = fixture.exec(cwd, "git", args, { env = env(who or "Ann") })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function zn(cwd: string, args: { string }): Result
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env("Zed") })
end
local function commit(who: string, message: string)
	git(dir, { "add", "-A" }, who)
	git(dir, { "commit", "-q", "-m", message }, who)
end
local function doc(id: string, raft: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nstatus: {status}\n---\n\n# {id}\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0263 who and the board", function(it)
	local W = ""
	it("builds the history, a bare origin and a worktree", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		process.exec("git", { "init", "-q", "-b", "main", dir })
		engine.copy(root, dir)
		engine.empty(dir)
		fs.writeFile(`{dir}/.gitignore`, ".cache/\n.worktree/\n")
		fs.writeFile(`{dir}/z-nile/next`, "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n")
		commit("Ann", "seed")
		local function put(id: string, text: string)
			fs.writeDir(`{dir}/{IDS}/{id}`)
			fs.writeFile(`{dir}/{IDS}/{id}/{id}.md`, text)
		end
		-- c0010: captured by Ann, unblocked by Dee, rafted by Bob (an agent trailer), unfolded by Gus, rafted again by
		-- Fay, delivered by Cy (an agent trailer); a record holds a rafted row and an approval that win over git
		put("c0010", doc("c0010", "", "new-a-b-c"))
		commit("Ann", "tracker: new c0010 alpha")
		put("c0010", doc("c0010", "", "preparing-a-b-c"))
		commit("Dee", "tracker: c0010 preparing")
		put("c0010", doc("c0010", "", "new-d-e-f"))
		commit("Dee", "tracker: c0010 new")
		put("c0010", doc("c0010", "R0010", "prepared-a-b-c"))
		commit("Bob", "tracker: raft R0010 demo\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")
		put("c0010", doc("c0010", "", "prepared-a-b-c"))
		commit("Gus", "tracker: unfold c0010")
		put("c0010", doc("c0010", "R0011", "prepared-a-b-c"))
		commit("Fay", "tracker: raft R0011 again")
		fs.writeFile(
			`{dir}/{IDS}/c0010/provenance.md`,
			"# Provenance: c0010\n\n| # | when | event | actor | detail |\n|---|---|---|---|---|\n"
				.. `| 1 | 2026-11-08 09:00 | approved | human:Ann | design=aaaaaaaaaaaa; said="ok" |\n`
				.. `| 2 | 2026-11-08 09:30 | rafted | {OPUS} | raft=R0011 |\n`
		)
		commit("Fay", "tracker: record c0010")
		fs.writeDir(`{dir}/{IDS}/done`)
		git(dir, { "mv", `{IDS}/c0010`, `{IDS}/done/c0010` }, "Cy")
		commit("Cy", "R0011: demo (#1)\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>")
		-- c0020: an old backlog item, captured by Eve, no record
		put("c0020", doc("c0020", "", "new-a-b-c"))
		commit("Eve", "tracker: new c0020 beta")
		process.exec("git", { "clone", "-q", "--bare", dir, origin })
		git(dir, { "remote", "add", "origin", origin })
		git(dir, { "fetch", "-q", "origin" })
		git(dir, { "branch", "-q", "--set-upstream-to=origin/main", "main" })
		local made = zn(dir, { "worktree", "who-a" })
		if not made.ok then
			error(made.stdout .. made.stderr)
		end
		W = (string.gsub(made.stdout, "%s+$", ""))
	end)

	it("who prints the derived entries and the record, oldest first, the record winning over a git fallback", function()
		local before = git(W, { "status", "--porcelain" })
		local r = zn(W, { "who", "c0010" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local out = r.stdout
		t.expect(has(out, "idea  human:Ann (from git)")).toBe(true)
		t.expect(has(out, "status:preparing  human:Dee (from git)")).toBe(true)
		t.expect(has(out, "status:new  human:Dee (from git)")).toBe(true)
		-- the stored approval is the human's and its design hash; the stored rafted row beats the git rafter (Fay)
		t.expect(has(out, "approved  human:Ann")).toBe(true)
		t.expect(has(out, "design=aaaaaaaaaaaa")).toBe(true)
		t.expect(has(out, `rafted  {OPUS}`)).toBe(true)
		t.expect(has(out, "rafted  human:Fay")).toBe(false)
		-- a delivery nothing recorded comes from the done commit, the agent that merged it
		t.expect(has(out, "delivered  agent:claude-sonnet-5-5 effort unknown (from git)")).toBe(true)
		-- oldest first
		local order: { string } = {}
		for line in string.gmatch(out, "[^\n]+") do
			local event = string.match(line, "^%S+ %S+%s+(%S+)")
			if event then
				table.insert(order, event)
			end
		end
		t.expect(order[1]).toBe("idea")
		t.expect(order[#order]).toBe("delivered")
		-- it reads and writes nothing
		t.expect(git(W, { "status", "--porcelain" })).toBe(before)
	end)

	it("an old item with no record is answered from git alone, and who runs in the main checkout", function()
		local r = zn(dir, { "who", "c0020" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "idea  human:Eve (from git)")).toBe(true)
		t.expect(fs.isFile(`{dir}/{IDS}/c0020/provenance.md`)).toBe(false)
		t.expect(zn(dir, { "who", "c0099" }).ok).toBe(false)
	end)

	it("the board shows an item's provenance in its view", function()
		local page = `{base}/board.html`
		local r = zn(W, { "board", "-O", "--out", page })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local html = fs.readFile(page)
		t.expect(has(html, "Provenance")).toBe(true)
		t.expect(has(html, "human:Ann (from git)")).toBe(true)
		t.expect(has(html, OPUS)).toBe(true)
	end)
end)
