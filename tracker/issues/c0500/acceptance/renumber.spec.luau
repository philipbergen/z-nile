--!strict
-- `tracker.sh renumber <old>` with no <new> (c0500): the next free number is ONE above the highest number
-- of that kind in the local tree and on origin/main. Each case builds a throwaway git repo outside this
-- one: origin/main is a commit holding the "origin" items, the working tree holds the "local" ones.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local made: { string } = {}

local function git(cwd: string, args: { string }): process.ExecResult
	local all = { "-c", "user.name=t", "-c", "user.email=t@example.com" }
	for _, a in args do
		table.insert(all, a)
	end
	return process.exec("git", all, { cwd = cwd })
end

-- An item path is relative to tracker/ and ends in the id: "issues/c0100", "issues/done/c0300", "rafts/R0120".
local function put(base: string, path: string, body: string?)
	local id = string.match(path, "[^/]+$") :: string
	fs.writeDir(`{base}/tracker/{path}`)
	fs.writeFile(`{base}/tracker/{path}/{id}.md`, `---\nid: {id}\ntitle: T\nslug: s\n---\n\n{body or ""}\n`)
end

-- `origin` = nil: no origin/main ref at all. The repo has no remote, so tracker.sh's main-checkout guard is off.
local function fixture(origin: { string }?, localItems: { string }, bodies: { [string]: string }?): string
	local base = trim(process.exec("mktemp", { "-d" }).stdout)
	table.insert(made, base)
	fs.writeFile(`{base}/rokit.toml`, fs.readFile(`{root}/rokit.toml`))
	git(base, { "init", "-q" })
	if origin then
		for _, path in origin do
			put(base, path)
		end
		git(base, { "add", "-A" })
		git(base, { "commit", "-q", "-m", "origin" })
		git(base, { "update-ref", "refs/remotes/origin/main", "HEAD" })
		fs.removeDir(`{base}/tracker`)
	end
	for _, path in localItems do
		put(base, path, bodies and bodies[path])
	end
	return base
end

local function tracker(base: string, args: { string }): process.ExecResult
	local all = { "run", `{root}/scripts/tracker/main`, "--" }
	for _, a in args do
		table.insert(all, a)
	end
	return process.exec("lune", all, { cwd = base })
end

local function has(base: string, path: string): boolean
	return fs.isFile(`{base}/tracker/{path}`)
end

local function say(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("renumber without <new>", function(it)
	it("origin/main ahead of the local tree: one above origin's highest", function()
		local base = fixture({ "issues/c0100", "issues/c0150" }, { "issues/f0100" })
		local r = tracker(base, { "renumber", "f0100" })
		t.expect(r.ok).toBe(true)
		t.expect(say(r.stdout, "f0100 -> f0151")).toBe(true)
		t.expect(has(base, "issues/f0151/f0151.md")).toBe(true)
		t.expect(has(base, "issues/f0100/f0100.md")).toBe(false)
	end)

	it("local tree ahead of origin/main: one above the local highest", function()
		local base = fixture({ "issues/c0100" }, { "issues/f0100", "issues/c0130" })
		local r = tracker(base, { "renumber", "f0100" })
		t.expect(r.ok).toBe(true)
		t.expect(has(base, "issues/f0131/f0131.md")).toBe(true)
	end)

	it("the old id alone is the highest: it advances by exactly one", function()
		local base = fixture({ "issues/c0020" }, { "issues/f0100" })
		t.expect(tracker(base, { "renumber", "f0100" }).ok).toBe(true)
		t.expect(has(base, "issues/f0101/f0101.md")).toBe(true)
	end)

	it("f, d and c share one number space and the prefix is kept", function()
		local base = fixture({ "issues/d0200" }, { "issues/c0100" })
		t.expect(tracker(base, { "renumber", "c0100" }).ok).toBe(true)
		t.expect(has(base, "issues/c0201/c0201.md")).toBe(true)
	end)

	it("rafts have their own space: issue numbers on origin/main do not count", function()
		local base = fixture({ "rafts/R0120", "issues/c0900" }, { "rafts/R0100" })
		t.expect(tracker(base, { "renumber", "R0100" }).ok).toBe(true)
		t.expect(has(base, "rafts/R0121/R0121.md")).toBe(true)
	end)

	it("issue renumbering ignores raft numbers", function()
		local base = fixture({ "rafts/R0900", "issues/c0120" }, { "issues/f0100" })
		t.expect(tracker(base, { "renumber", "f0100" }).ok).toBe(true)
		t.expect(has(base, "issues/f0121/f0121.md")).toBe(true)
	end)

	it("origin items in active/ and done/ count", function()
		local base = fixture(
			{ "issues/done/c0300", "issues/active/c0350", "issues/c0100" },
			{ "issues/f0100" }
		)
		t.expect(tracker(base, { "renumber", "f0100" }).ok).toBe(true)
		t.expect(has(base, "issues/f0351/f0351.md")).toBe(true)
	end)

	it("origin raft items in active/ and done/ count", function()
		local base = fixture({ "rafts/done/R0400", "rafts/active/R0450" }, { "rafts/R0100" })
		t.expect(tracker(base, { "renumber", "R0100" }).ok).toBe(true)
		t.expect(has(base, "rafts/R0451/R0451.md")).toBe(true)
	end)

	it("local active and done items count too", function()
		local base = fixture(
			{ "issues/c0020" },
			{ "issues/f0100", "issues/done/c0600", "issues/active/c0650" }
		)
		t.expect(tracker(base, { "renumber", "f0100" }).ok).toBe(true)
		t.expect(has(base, "issues/f0651/f0651.md")).toBe(true)
	end)

	it("references to the old id are rewritten", function()
		local base = fixture(
			{ "issues/c0150" },
			{ "issues/f0100", "issues/c0120" },
			{ ["issues/c0120"] = "blocked by f0100 (not f01000)" }
		)
		t.expect(tracker(base, { "renumber", "f0100" }).ok).toBe(true)
		local doc = fs.readFile(`{base}/tracker/issues/c0120/c0120.md`)
		t.expect(say(doc, "blocked by f0151 (not f01000)")).toBe(true)
	end)

	it("an explicit <new> is used exactly as given, whatever origin/main holds", function()
		local base = fixture({ "issues/c0900" }, { "issues/f0100" })
		local r = tracker(base, { "renumber", "f0100", "f0500" })
		t.expect(r.ok).toBe(true)
		t.expect(has(base, "issues/f0500/f0500.md")).toBe(true)
	end)

	it("an explicit <new> that exists, or has another prefix, is still refused", function()
		local base = fixture({ "issues/c0900" }, { "issues/f0100", "issues/f0110" })
		t.expect(tracker(base, { "renumber", "f0100", "f0110" }).ok).toBe(false)
		t.expect(tracker(base, { "renumber", "f0100", "c0500" }).ok).toBe(false)
		t.expect(has(base, "issues/f0100/f0100.md")).toBe(true)
	end)

	it("origin/main unknown: refuses, names origin/main, and moves nothing", function()
		local base = fixture(nil, { "issues/f0100" })
		local r = tracker(base, { "renumber", "f0100" })
		t.expect(r.ok).toBe(false)
		t.expect(r.code).toBe(1)
		t.expect(say(r.stderr, "origin/main")).toBe(true)
		t.expect(has(base, "issues/f0100/f0100.md")).toBe(true)
	end)

	it("an id that does not exist is refused", function()
		local base = fixture({ "issues/c0100" }, { "issues/f0100" })
		t.expect(tracker(base, { "renumber", "f0999" }).ok).toBe(false)
	end)

	it("no room above 9999: refuses and moves nothing", function()
		local base = fixture({ "issues/c9999" }, { "issues/f0100" })
		local r = tracker(base, { "renumber", "f0100" })
		t.expect(r.ok).toBe(false)
		t.expect(say(r.stderr, "9999")).toBe(true)
		t.expect(has(base, "issues/f0100/f0100.md")).toBe(true)
	end)

	it("the usage text shows <new> as optional", function()
		local base = fixture({ "issues/c0100" }, { "issues/f0100" })
		local r = tracker(base, { "renumber" })
		t.expect(r.ok).toBe(false)
		t.expect(say(r.stderr, "renumber <old> [<new>]")).toBe(true)
	end)

	it("cleanup", function()
		for _, base in made do
			fs.removeDir(base)
		end
	end)
end)
