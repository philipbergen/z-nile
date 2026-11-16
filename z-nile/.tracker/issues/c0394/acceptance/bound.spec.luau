--!strict
-- c0394 AC12: `new issue --with <id> --found <where>` makes a bound issue in its issue's project that reaches prepared
-- in the same prep with no idea challenge, rafts, folds, unfolds and recombines with its issue, and is not asked for an
-- approval by `ready`. Driven through ./zn in two fixtures under .cache/c0394-bound-plan and .cache/c0394-bound-raft
-- (tests/lib/trackerfix), as tests/acceptance/c0116/plan-cli.spec.luau does. Everything here is main's own behaviour
-- (backlog rafts, claims, ready), so these cases run on today's main and fail on the bound-issue rules.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local PREPARING = "preparing-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local KINDS = { f = "feature", d = "defect", c = "chore" }
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

-- `front` is extra frontmatter lines (size:, with:, waits:, found:); `design` is ready unless the issue is a draft
local function issue(id: string, raft: string, front: string, status: string?, design: string?): string
	return `---\nid: {id}\ntype: {KINDS[string.sub(id, 1, 1)]}\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: {design or "ready"}\ncreated: 2026-11-16\n{front}status: {status or PREPARED}\n---\n\n# {id}\n\n{CAPTURED}\n## Design\n\n### Touched modules\n\n### Affected specs\n\n## Unknowns & experiments\n`
end

local function bound(of: string): string
	return `size: 100\nwith: {of}\nwaits: approval\nfound: {of} design F1 medium\nidea: finding\n`
end

local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n`
end

local function seedIssue(seed: { [string]: string }, root: string, id: string, text: string)
	seed[`{root}/issues/{id}/{id}.md`] = text
	seed[`{root}/issues/{id}/check.sh`] = CHECK
end

local BASE: { [string]: string } = {
	[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
	["pickman/.tracker/architecture.md"] = "# Architecture\n",
	["z-nile/next"] = "issue 300 quiet-copper-falcon\nraft 300 quiet-copper-falcon\n",
}

local function seedFrom(extra: { [string]: string }): { [string]: string }
	local seed = table.clone(BASE)
	for path, text in extra do
		seed[path] = text
	end
	return seed
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function raftOf(dir: string, id: string): string?
	return string.match(fs.readFile(`{dir}/pickman/.tracker/issues/{id}/{id}.md`), "\nraft: (%S*)\n")
end

local plan: trackerfix.Fixture
local raft: trackerfix.Fixture
local W = ""
local B = "" -- the bound issue the first case makes

local function onOrigin(f: trackerfix.Fixture, path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(raft, dir, args)
end

local function ok(dir: string, args: { string }): string
	local r = tr(dir, args)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end

return t.spec("c0394 a bound issue travels with its issue", function(it)
	it(
		"new issue --with needs a preparing issue and --found, takes its project, and writes with, waits, found and idea: finding",
		function()
			local seed = seedFrom({})
			-- c0110 is being prepared, in z-nile's project; c0120 is prepared in pickman's
			seedIssue(seed, "z-nile/.tracker", "c0110", issue("c0110", "", "", PREPARING, "draft"))
			seedIssue(seed, "pickman/.tracker", "c0120", issue("c0120", "", "size: 100\n"))
			-- the rafts of the later cases; their members are seeded here
			seedIssue(seed, "pickman/.tracker", "c0070", issue("c0070", "R0010", "size: 100\n"))
			seedIssue(seed, "pickman/.tracker", "f0080", issue("f0080", "R0010", bound("c0070")))
			seedIssue(seed, "pickman/.tracker", "c0090", issue("c0090", "R0020", "size: 100\n"))
			seedIssue(seed, "pickman/.tracker", "f0100", issue("f0100", "R0020", bound("c0090")))
			seedIssue(seed, "pickman/.tracker", "c0210", issue("c0210", "R0030", "size: 100\n"))
			seedIssue(seed, "pickman/.tracker", "c0130", issue("c0130", "", "size: 100\n"))
			seedIssue(seed, "pickman/.tracker", "f0140", issue("f0140", "", bound("c0130")))
			seedIssue(seed, "pickman/.tracker", "c0150", issue("c0150", "R0050", "size: 100\n"))
			seedIssue(seed, "pickman/.tracker", "f0160", issue("f0160", "R0050", bound("c0150")))
			seedIssue(seed, "pickman/.tracker", "c0170", issue("c0170", "R0040", "size: 100\n"))
			local rafts: { [string]: string } = {
				R0010 = "c0070, f0080",
				R0020 = "c0090, f0100",
				R0030 = "c0210",
				R0040 = "c0170",
				R0050 = "c0150, f0160",
			}
			for id, members in rafts do
				seed[`pickman/.tracker/rafts/{id}/{id}.md`] = raftDoc(id, members)
				seed[`pickman/.tracker/rafts/{id}/check.sh`] = CHECK
			end
			raft = trackerfix.new("c0394-bound-raft", seed)
			-- f0100 waits for the user: its approval is not part of the seed
			ok(raft.main, { "sync" })
			fixture.git(raft.main, { "rm", "-q", "pickman/.tracker/issues/f0100/approval.md" })
			fixture.git(raft.main, { "commit", "-q", "-m", "f0100 waits for approval" })
			fixture.git(raft.main, { "push", "-q", "origin", "HEAD:main" })

			W = trackerfix.trOk(raft, raft.main, { "worktree", "bound-w" })
			local r = tr(W, {
				"new",
				"issue",
				"c",
				"found-by-prep",
				"--with",
				"c0110",
				"--found",
				"c0110 design F1 medium",
			})
			t.expect(r.ok).toBe(true)
			B = string.match(r.stdout, "(c%d%d%d%d)/c%d%d%d%d%.md") or ""
			t.expect(B ~= "").toBe(true)
			-- it takes its issue's project (z-nile), not the folder's
			t.expect(has(r.stdout, "z-nile/.tracker/issues/")).toBe(true)
			local doc = onOrigin(raft, `z-nile/.tracker/issues/{B}/{B}.md`)
			t.expect(doc ~= nil).toBe(true) -- the stub is published
			t.expect(has(doc :: string, "\nwith: c0110\n")).toBe(true)
			t.expect(has(doc :: string, "\nwaits: approval\n")).toBe(true)
			t.expect(has(doc :: string, "\nfound: c0110 design F1 medium\n")).toBe(true)
			t.expect(has(doc :: string, "\nidea: finding\n")).toBe(true)

			-- refused, and nothing is made: a prepared issue, a missing one, no --found, another project
			local tip = fixture.git(raft.origin, { "rev-parse", "main" })
			local prepared = tr(
				W,
				{ "new", "issue", "c", "found-late", "--with", "c0120", "--found", "c0120 design F1 medium" }
			)
			t.expect(prepared.ok).toBe(false)
			t.expect(has(prepared.stderr, "--with c0120: an added issue is made by the prep that found it"))
				.toBe(true)
			local missing = tr(
				W,
				{ "new", "issue", "c", "found-none", "--with", "c9999", "--found", "c9999 design F1 medium" }
			)
			t.expect(missing.ok).toBe(false)
			t.expect(has(missing.stderr, "--with c9999")).toBe(true)
			local unfound = tr(W, { "new", "issue", "c", "found-silent", "--with", "c0110" })
			t.expect(unfound.ok).toBe(false)
			t.expect(has(unfound.stderr, "--found")).toBe(true)
			local elsewhere = tr(W, {
				"new",
				"issue",
				"c",
				"found-else",
				"--with",
				"c0110",
				"--found",
				"x",
				"--project",
				"pickman",
			})
			t.expect(elsewhere.ok).toBe(false)
			t.expect(has(elsewhere.stderr, "an added issue is made in its issue's project")).toBe(true)
			t.expect(fixture.git(raft.origin, { "rev-parse", "main" })).toBe(tip)
		end
	)

	it("a bound issue goes from new to prepared in its issue's prep without an idea challenge", function()
		-- the prep that found it designs it: preparing needs no idea-review (idea: finding), then prepared
		if B == "" then
			-- the tool did not make the bound issue: make the same stub by hand so this case judges the prep alone
			local made = tr(W, { "new", "issue", "c", "found-by-prep", "--project", "z-nile" })
			B = string.match(made.stdout, "(c%d%d%d%d)/c%d%d%d%d%.md") or ""
			local path = `z-nile/.tracker/issues/{B}/{B}.md`
			local stub = onOrigin(raft, path) or ""
			stub = string.gsub(stub, "\nidea: %S+\n", "\nidea: finding\n", 1)
			stub = string.gsub(
				stub,
				"\nemergent: false\n",
				"\nemergent: false\nwith: c0110\nwaits: approval\nfound: c0110 design F1 medium\n",
				1
			)
			trackerfix.elsewhere(raft, { [path] = stub }, "the bound issue as the tool should make it")
		end
		local U = trackerfix.trOk(raft, raft.main, { "worktree", "prep-bound" })
		local docPath = `{U}/z-nile/.tracker/issues/{B}/{B}.md`
		t.expect(fs.isFile(docPath)).toBe(true)
		local claimed = tr(U, { "status", B, "preparing" })
		if not claimed.ok then
			error(`status {B} preparing refused: {claimed.stderr}{claimed.stdout}`, 0)
		end
		local doc = fs.readFile(docPath)
		fs.writeFile(docPath, (string.gsub(doc, "design: %a+", "design: ready", 1)))
		fs.writeFile(`{U}/z-nile/.tracker/issues/{B}/check.sh`, CHECK)
		fixture.git(U, { "add", "-A" })
		fixture.git(U, { "commit", "-q", "-m", "design the bound issue" })
		local prepared = tr(U, { "status", B, "prepared" })
		if not prepared.ok then
			error(`status {B} prepared refused: {prepared.stderr}{prepared.stdout}`, 0)
		end
		t.expect(has(fs.readFile(docPath), "\nstatus: prepared-")).toBe(true)
		t.expect(has(prepared.stderr .. prepared.stdout, "idea")).toBe(false)
	end)

	it("raft-plan puts a bound issue in its issue's raft whatever its type", function()
		local seed = seedFrom({})
		seedIssue(seed, "pickman/.tracker", "c0010", issue("c0010", "", "size: 100\n"))
		-- a feature and a defect bound to a chore: other types, one of them far over the size cap
		seedIssue(
			seed,
			"pickman/.tracker",
			"f0020",
			issue("f0020", "", (string.gsub(bound("c0010"), "size: 100", "size: 50")))
		)
		seedIssue(
			seed,
			"pickman/.tracker",
			"d0030",
			issue("d0030", "", (string.gsub(bound("c0010"), "size: 100", "size: 5000")))
		)
		-- a bound issue that is not prepared: neither it nor its issue is planned
		seedIssue(seed, "pickman/.tracker", "c0040", issue("c0040", "", "size: 100\n"))
		seedIssue(seed, "pickman/.tracker", "f0050", issue("f0050", "", bound("c0040"), PREPARING, "draft"))
		plan = trackerfix.new("c0394-bound-plan", seed)
		local out = trackerfix.trOk(plan, plan.main, { "raft-plan" })
		local together = 0
		for line in string.gmatch(out, "[^\n]+") do
			if has(line, "c0010") then
				t.expect(string.sub(line, 1, 2)).toBe("./") -- a command, not a skip
				t.expect(has(line, "f0020")).toBe(true)
				t.expect(has(line, "d0030")).toBe(true)
				together += 1
			elseif has(line, "f0020") or has(line, "d0030") then
				error(`a bound issue is planned apart from its issue: {line}`)
			end
			if has(line, "c0040") or has(line, "f0050") then
				t.expect(string.sub(line, 1, 5)).toBe("skip ")
			end
		end
		t.expect(together).toBe(1)
	end)

	it("fold, unfold and recombine move an issue and its bound issue together", function()
		local U = trackerfix.trOk(raft, raft.main, { "worktree", "move-w" })
		-- unfold: both leave R0010
		ok(U, { "unfold", "R0010", "c0070" })
		t.expect(raftOf(U, "c0070")).toBe("")
		t.expect(raftOf(U, "f0080")).toBe("")
		local listed = string.match(
			fs.readFile(`{U}/pickman/.tracker/rafts/R0010/R0010.md`),
			"\nissues: %[([^\n]*)%]"
		) or ""
		t.expect(has(listed, "f0080")).toBe(false)
		-- fold: both join R0030
		ok(U, { "fold", "R0030", "c0130" })
		t.expect(raftOf(U, "c0130")).toBe("R0030")
		t.expect(raftOf(U, "f0140")).toBe("R0030")
		-- recombine: R0050's c0150 goes to R0040 and takes f0160 with it
		ok(U, { "recombine", "R0040", "R0050", "c0150" })
		t.expect(raftOf(U, "c0150")).toBe("R0040")
		t.expect(raftOf(U, "f0160")).toBe("R0040")
	end)

	it("ready asks no approval of a waiting member", function()
		ok(raft.main, { "sync" })
		-- c0090 is approved (the seed); f0100 waits for the user and has no approval
		t.expect(fs.isFile(`{raft.main}/pickman/.tracker/issues/c0090/approval.md`)).toBe(true)
		t.expect(fs.isFile(`{raft.main}/pickman/.tracker/issues/f0100/approval.md`)).toBe(false)
		local r = tr(raft.main, { "ready", "R0020" })
		if not r.ok then
			error(`ready R0020 refused: {r.stderr}{r.stdout}`, 0)
		end
		t.expect(has(r.stdout, "readied R0020")).toBe(true)
		t.expect(onOrigin(raft, "pickman/.tracker/issues/active/c0090/c0090.md") ~= nil).toBe(true)
		t.expect(onOrigin(raft, "pickman/.tracker/issues/active/f0100/f0100.md") ~= nil).toBe(true)
	end)
end)
