--!strict
-- A tracker fixture for specs that drive `scripts/tracker.sh`: a bare origin with a seed commit, a main checkout
-- and a second terminal, all under a .cache folder. A thin layer over @tests/lib/fixture: every git and tracker.sh
-- command goes through fixture.git and fixture.exec (and so is checked), except `git init` and `git clone` to a
-- path this module names itself. Each caller passes a name that no other spec file uses (the c0049 rule); the
-- path is built by concatenation, so only that name counts.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")

local trackerfix = {}

export type Fixture = { base: string, origin: string, main: string, other: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- Runs `git` at `cwd`, a folder that is not a repository yet, to make the one at the path `args` names.
local function create(cwd: string, args: { string })
	local r = process.exec("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 3)
	end
end

local function identity(dir: string, name: string)
	fixture.git(dir, { "config", "user.name", name })
	fixture.git(dir, { "config", "user.email", `{name}@example.invalid` })
end

-- Builds `.cache/<name>`: a seed commit (the tooling, with the skills' lessons unless `opts.noLessons`, empty tracker
-- folders, and `seed`'s extra files),
-- a bare origin made from it, and two clones of the origin. Removes what an earlier run left.
function trackerfix.new(name: string, seed: { [string]: string }?, opts: { noLessons: boolean? }?): Fixture
	local root = fixture.physical(".")
	if not root then
		error("trackerfix.new: the current directory is not readable", 2)
	end
	local base = `{root}/.cache/{name}`
	local origin, main, other = `{base}/origin.git`, `{base}/main`, `{base}/other`
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	local source = `{base}/seed`
	fs.writeDir(`{source}/tracker`)
	create(base, { "init", "-q", "-b", "main", source })
	identity(source, name)
	-- ./zn, scripts/ and z-nile/'s tooling, with no items, counter or map; empty folders under both project roots
	engine.copy(root, source)
	if opts and opts.noLessons then
		engine.clearLessons(source) -- the copied skills' lessons; the seed adds the spec's own
	end
	engine.roots(source)
	fs.writeFile(`{source}/.gitignore`, ".cache/\n.worktree/\n")
	local extra: { [string]: string } = seed or {}
	for path, text in extra do
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{source}/{parent}`)
		end
		fs.writeFile(`{source}/{path}`, text)
	end
	fixture.git(source, { "add", "-A" })
	fixture.git(source, { "commit", "-q", "-m", "seed" })
	create(base, { "clone", "-q", "--bare", source, origin })
	create(base, { "clone", "-q", origin, main })
	create(base, { "clone", "-q", origin, other })
	identity(main, name)
	identity(other, name)
	return { base = base, origin = origin, main = main, other = other }
end

-- `scripts/tracker.sh <args>` in the fixture folder `cwd`; never raises for the command's own failure.
function trackerfix.tr(_f: Fixture, cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, arg in args do
		table.insert(argv, arg)
	end
	return fixture.exec(cwd, "bash", argv, { env = env })
end

-- The trimmed stdout of `tracker.sh <args>`; raises with its output when it fails.
function trackerfix.trOk(f: Fixture, cwd: string, args: { string }): string
	local r = trackerfix.tr(f, cwd, args)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

-- Another terminal pushes a commit with these files straight to origin's main.
function trackerfix.elsewhere(f: Fixture, files: { [string]: string }, message: string)
	fixture.git(f.other, { "pull", "-q", "origin", "main" })
	for path, text in files do
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{f.other}/{parent}`)
		end
		fs.writeFile(`{f.other}/{path}`, text)
	end
	fixture.git(f.other, { "add", "-A" })
	fixture.git(f.other, { "commit", "-q", "-m", message })
	fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
end

-- A valid item document, as another terminal's `new` would have pushed it.
function trackerfix.stub(id: string, title: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {title}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-01-01\nstatus: {status}\n---\n\n# {id}\n`
end

return trackerfix
