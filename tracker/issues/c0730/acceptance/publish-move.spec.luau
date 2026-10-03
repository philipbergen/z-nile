--!strict
-- c0730: publish moves whole item directories (Change.from) as one tracker-only commit on origin/main, and validates
-- every moved file. A bare origin and a clone in .cache/c0730-publish; cases share the fixture and run in order.
local fs = require("@lune/fs")
local paths = require("@scripts/tracker/paths")
local process = require("@lune/process")
local publish = require("@scripts/tracker/publish")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/c0730-publish`
local origin, work = `{base}/origin.git`, `{base}/work`

local function git(cwd: string, args: { string }): string
	local r: Result =
		process.exec("git", args, { cwd = cwd, env = { GIT_CEILING_DIRECTORIES = `{root}/.cache` } })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function tip(): string
	return git(origin, { "rev-parse", "main" })
end
local function has(s: string?, needle: string): boolean
	return s ~= nil and string.find(s, needle, 1, true) ~= nil
end

local DOC =
	"---\nid: c0010\ntype: chore\ntitle: Movable\nstatus: prepared-quiet-copper-falcon\n---\n\n# c0010\n"
local CHECK = '#!/usr/bin/env bash\ncheck "AC1: a" lune run tests/run -- tracker/issues/c0010/acceptance/a.spec.luau\n'
	.. 'check "AC2: b" test -f tracker/issues/c0020/c0020.md\nfinish\n'
local SPEC = "-- c0010 acceptance marker\nreturn nil\n"
local RUN = "#!/bin/sh\necho spike\n"
local CRLF = "spike output\r\nline two\r\n" -- a moved file is byte-checked, so its carriage returns are kept
local FROM, TO = "tracker/issues/c0010", "tracker/issues/active/c0010"

local function write(path: string, text: string, exec: boolean?)
	local full = `{base}/seed/{path}`
	local parent = string.match(full, "^(.*)/[^/]+$") :: string
	fs.writeDir(parent)
	fs.writeFile(full, text)
	if exec then
		process.exec("chmod", { "+x", full })
	end
end

-- Every file of FROM moved to TO, as ready would build it: the document stamped, check.sh rewritten, the rest as is.
-- `tweak` may edit the list before it is returned.
local function moveChanges(
	list: { string },
	read: (string) -> string?,
	tweak: ((changes: { publish.Change }) -> ())?
): { publish.Change }
	local out: { publish.Change } = {}
	for _, p in list do
		if string.sub(p, 1, #FROM + 1) == FROM .. "/" then
			local rel = string.sub(p, #FROM + 2)
			local text = read(p) :: string
			if rel == "c0010.md" then
				text = (string.gsub(text, "status: [^\n]*", "status: active-brisk-amber-otter"))
			elseif rel == "check.sh" then
				text = paths.rewrite(text, { c0010 = TO })
			end
			table.insert(out, { path = `{TO}/{rel}`, from = p, content = text })
		end
	end
	if tweak then
		tweak(out)
	end
	return out
end
local function find(changes: { publish.Change }, rel: string): publish.Change
	for _, c in changes do
		if c.path == `{TO}/{rel}` then
			return c
		end
	end
	error(`no change for {rel}`)
end
local function attempt(tweak: ((changes: { publish.Change }) -> ())?): publish.Result
	return publish.commit(work, function(list, read)
		return moveChanges(list, read, tweak)
	end, "tracker: move c0010")
end
local function refused(r: publish.Result, before: string, needle: string?)
	t.expect(r.ok).toBe(false)
	if needle then
		t.expect(has(r.reason, needle)).toBe(true)
	end
	t.expect(tip()).toBe(before)
end

return t.spec("tracker publish moves", function(it)
	it("sets up a bare origin and a clone with items to move", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/seed`)
		git(`{base}/seed`, { "init", "-q", "-b", "main" })
		git(`{base}/seed`, { "config", "user.name", "t" })
		git(`{base}/seed`, { "config", "user.email", "t@example.invalid" })
		write("src/x.luau", "return 1\n")
		write("tracker/issues/active/.gitkeep", "")
		write("tracker/rafts/active/.gitkeep", "")
		write(`{FROM}/c0010.md`, DOC)
		write(`{FROM}/check.sh`, CHECK, true)
		write(`{FROM}/acceptance/a.spec.luau`, SPEC)
		write(`{FROM}/experiments/run.sh`, RUN, true)
		write(`{FROM}/experiments/out.txt`, CRLF)
		write("tracker/issues/c0020/c0020.md", "---\nid: c0020\nstatus: new\n---\n")
		write("tracker/issues/c0020/check.sh", "#!/bin/sh\n", true)
		-- c0040 is done: a published move may not take it out of done/
		write("tracker/issues/done/c0040/c0040.md", "---\nid: c0040\nstatus: done\n---\n")
		write(
			"tracker/issues/done/c0040/check.sh",
			"#!/bin/sh\ntest -f tracker/issues/done/c0040/c0040.md\n",
			true
		)
		-- c0030 exists in both places: a move onto it must be refused
		write("tracker/issues/c0030/c0030.md", "---\nid: c0030\nstatus: prepared\n---\n")
		write("tracker/issues/active/c0030/c0030.md", "---\nid: c0030\nstatus: active\n---\n")
		git(`{base}/seed`, { "add", "-A" })
		git(`{base}/seed`, { "commit", "-q", "-m", "seed" })
		git(base, { "clone", "-q", "--bare", `{base}/seed`, origin })
		git(base, { "clone", "-q", origin, work })
		git(work, { "config", "user.name", "t" })
		git(work, { "config", "user.email", "t@example.invalid" })
	end)

	it("non-move changes keep today's rules", function()
		t.expect(publish.allowed(`{FROM}/acceptance/a.spec.luau`)).toBe(false)
		local id, rel = publish.itemPath(`{FROM}/acceptance/a.spec.luau`)
		t.expect(id).toBe("c0010")
		t.expect(rel).toBe("acceptance/a.spec.luau")
		local rid, rrel = publish.itemPath("tracker/rafts/done/R0010/review-001.md")
		t.expect(rid).toBe("R0010")
		t.expect(rrel).toBe("review-001.md")
		for _, bad in
			{ "src/x.luau", "tracker/architecture.md", "tracker/issues/c0010/../x", "tracker/issues/R0010/a" }
		do
			t.expect(publish.itemPath(bad)).toBe(nil)
		end
		local before = tip()
		local r = publish.commit(work, function()
			return { { path = `{FROM}/acceptance/a.spec.luau`, content = "return 1\n" } }
		end, "tracker: edit a spec")
		refused(r, before)
	end)

	it("a move that leaves a file of the directory behind is refused", function()
		local before = tip()
		refused(
			attempt(function(changes)
				for i, c in changes do
					if c.from == `{FROM}/experiments/run.sh` then
						table.remove(changes, i)
						break
					end
				end
			end),
			before,
			FROM
		)
	end)

	it("a move that changes any byte of an ordinary file is refused", function()
		local before = tip()
		refused(
			attempt(function(changes)
				local c = find(changes, "acceptance/a.spec.luau")
				c.content = c.content .. "-- sneaky\n"
			end),
			before,
			"acceptance/a.spec.luau"
		)
	end)

	it("a moved document may change only its status line", function()
		local before = tip()
		refused(
			attempt(function(changes)
				local c = find(changes, "c0010.md")
				c.content = (string.gsub(c.content, "title: Movable", "title: Other"))
			end),
			before,
			"c0010.md"
		)
	end)

	it("a moved check.sh may change only its item paths' state segments", function()
		local before = tip()
		refused(
			attempt(function(changes)
				local c = find(changes, "check.sh")
				c.content = c.content .. "rm -rf /\n"
			end),
			before,
			"check.sh"
		)
		refused(
			attempt(function(changes)
				local c = find(changes, "check.sh")
				c.content = (string.gsub(c.content, "test %-f", "test -e"))
			end),
			before,
			"check.sh"
		)
		-- c0020 is not moved by this publish, so its path keeps its segment
		refused(
			attempt(function(changes)
				local c = find(changes, "check.sh")
				c.content = (string.gsub(c.content, "tracker/issues/c0020/", "tracker/issues/active/c0020/"))
			end),
			before,
			"check.sh"
		)
	end)

	it("a move onto an existing path, across ids or to another relative path is refused", function()
		local before = tip()
		local onto = publish.commit(work, function(_list, read)
			return {
				{
					path = "tracker/issues/active/c0030/c0030.md",
					from = "tracker/issues/c0030/c0030.md",
					content = read("tracker/issues/c0030/c0030.md") :: string,
				},
			}
		end, "tracker: onto")
		refused(onto, before)
		refused(
			attempt(function(changes)
				find(changes, "acceptance/a.spec.luau").path =
					"tracker/issues/active/c0020/acceptance/a.spec.luau"
			end),
			before
		)
		refused(
			attempt(function(changes)
				find(changes, "acceptance/a.spec.luau").path = `{TO}/acceptance/b.spec.luau`
			end),
			before
		)
	end)

	it("a move that changes a file's mode is refused", function()
		local before = tip()
		refused(
			attempt(function(changes)
				find(changes, "experiments/run.sh").mode = "100644"
			end),
			before
		)
	end)

	it("a move into or out of done/ is refused", function()
		local before = tip()
		local r = publish.commit(work, function(list, read)
			local out = moveChanges(list, read)
			for _, c in out do
				c.path = (string.gsub(c.path, "^tracker/issues/active/", "tracker/issues/done/"))
				if c.from == `{FROM}/check.sh` then -- a consistent move in every other respect
					c.content = paths.rewrite(
						read(c.from :: string) :: string,
						{ c0010 = "tracker/issues/done/c0010" }
					)
				end
			end
			return out
		end, "tracker: to done")
		refused(r, before)
		-- and out of done/, consistent in every other respect: only the source side is wrong
		local out = publish.commit(work, function(_list, read)
			local doc = read("tracker/issues/done/c0040/c0040.md") :: string
			local check = read("tracker/issues/done/c0040/check.sh") :: string
			return {
				{
					path = "tracker/issues/c0040/c0040.md",
					from = "tracker/issues/done/c0040/c0040.md",
					content = (string.gsub(doc, "status: done", "status: prepared-quiet-copper-falcon")),
				},
				{
					path = "tracker/issues/c0040/check.sh",
					from = "tracker/issues/done/c0040/check.sh",
					content = paths.rewrite(check, { c0040 = "tracker/issues/c0040" }),
				},
			}
		end, "tracker: out of done")
		refused(out, before)
		t.expect(git(origin, { "ls-tree", "--name-only", "main", "tracker/issues/done/c0040/c0040.md" }))
			.toBe("tracker/issues/done/c0040/c0040.md")
	end)

	it("a from outside an item directory is refused, and that file stays on origin", function()
		local before = tip()
		refused(
			attempt(function(changes)
				table.insert(changes, { path = `{TO}/x.luau`, from = "src/x.luau", content = "return 1\n" })
			end),
			before
		)
		t.expect(git(origin, { "show", "main:src/x.luau" })).toBe("return 1")
	end)

	it("a second change at a moved path is refused", function()
		local before = tip()
		-- a status edit of the source document beside its move would leave c0010 in two directories
		refused(
			attempt(function(changes)
				table.insert(changes, {
					path = `{FROM}/c0010.md`,
					content = (string.gsub(DOC, "status: [^\n]*", "status: new")),
				})
			end),
			before
		)
		-- a second write of the target would replace the validated move
		refused(
			attempt(function(changes)
				table.insert(
					changes,
					{ path = `{TO}/c0010.md`, content = "---\nid: c0010\nstatus: active\n---\n" }
				)
			end),
			before
		)
		-- the same source moved twice
		refused(
			attempt(function(changes)
				local c = find(changes, "acceptance/a.spec.luau")
				table.insert(
					changes,
					{ path = `{TO}/acceptance/b.spec.luau`, from = c.from, content = c.content }
				)
			end),
			before
		)
	end)

	it("a whole-directory move lands as one commit with every file, mode and sibling kept", function()
		local before = tip()
		local r = attempt(nil)
		t.expect(r.ok).toBe(true)
		t.expect(tip()).toBe(r.sha)
		t.expect(git(origin, { "rev-parse", "main^" })).toBe(before)
		local changed = git(origin, { "diff", "--name-only", "--no-renames", before, "main" })
		local want = {
			`{FROM}/acceptance/a.spec.luau`,
			`{FROM}/c0010.md`,
			`{FROM}/check.sh`,
			`{FROM}/experiments/out.txt`,
			`{FROM}/experiments/run.sh`,
			`{TO}/acceptance/a.spec.luau`,
			`{TO}/c0010.md`,
			`{TO}/check.sh`,
			`{TO}/experiments/out.txt`,
			`{TO}/experiments/run.sh`,
		}
		table.sort(want)
		local got = string.split(changed, "\n")
		table.sort(got)
		t.expect(got).toEqual(want)
		t.expect(git(origin, { "ls-tree", "main", FROM })).toBe("") -- the emptied directory is gone
		t.expect(git(origin, { "ls-tree", "--name-only", "main", "tracker/issues/active/.gitkeep" }))
			.toBe("tracker/issues/active/.gitkeep")
		t.expect(git(origin, { "show", `main:{TO}/acceptance/a.spec.luau` }) .. "\n").toBe(SPEC)
		t.expect(git(origin, { "show", `main:{TO}/experiments/run.sh` }) .. "\n").toBe(RUN)
		local crlf = process.exec(
			"git",
			{ "show", `main:{TO}/experiments/out.txt` },
			{ cwd = origin, env = { GIT_CEILING_DIRECTORIES = `{root}/.cache` } }
		)
		t.expect(crlf.stdout).toBe(CRLF)
		t.expect(string.sub(git(origin, { "ls-tree", "main", `{TO}/experiments/run.sh` }), 1, 6))
			.toBe("100755")
		t.expect(string.sub(git(origin, { "ls-tree", "main", `{TO}/check.sh` }), 1, 6)).toBe("100755")
		local check = git(origin, { "show", `main:{TO}/check.sh` }) .. "\n"
		t.expect(check).toBe((string.gsub(CHECK, "tracker/issues/c0010/", "tracker/issues/active/c0010/")))
		t.expect(has(check, "tracker/issues/c0020/c0020.md")).toBe(true)
		local doc = git(origin, { "show", `main:{TO}/c0010.md` })
		t.expect(has(doc, "status: active-brisk-amber-otter")).toBe(true)
		t.expect(has(doc, "title: Movable")).toBe(true)
		t.expect(git(origin, { "show", "main:tracker/issues/c0020/c0020.md" }))
			.toBe("---\nid: c0020\nstatus: new\n---")
	end)
end)
