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
local seal = require("@tests/lib/seal")
local swept = require("@tests/lib/swept")
local tally = require("@tests/lib/tally")

-- process.exec, counted (tally.started) beside the call.
local function counted(
	cmd: string,
	args: { string }?,
	options: any?
): { ok: boolean, code: number, stdout: string, stderr: string }
	tally.started(1)
	return process.exec(cmd, args, options)
end

local trackerfix = {}

export type Fixture = { base: string, origin: string, main: string, other: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- Runs `git` at `cwd`, a folder that is not a repository yet, to make the one at the path `args` names.
local function create(cwd: string, args: { string })
	local r = counted("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 3)
	end
end

-- A non-bare clone of `from` at `to`, committing as the fixture `name`. Copies, never hardlinks: nothing a spec does to
-- a fixture's objects can reach the image it came from.
local function cloneAs(cwd: string, name: string, from: string, to: string, bare: boolean)
	local args = { "clone", "-q", "--no-hardlinks" }
	if bare then
		table.insert(args, "--bare")
	else
		for _, a in { "-c", `user.name={name}`, "-c", `user.email={name}@example.invalid` } do
			table.insert(args, a)
		end
	end
	table.insert(args, from)
	table.insert(args, to)
	create(cwd, args)
end

-- Builds `.cache/<name>`: a bare origin and a main clone of it, and a second terminal's clone (`other`, made the first time a
-- fixture helper is asked to work in it), all holding one commit "seed" on main: the tooling (with the skills' lessons unless
-- `opts.noLessons`), empty tracker folders, `opts.copy`'s paths from the checkout, and `seed`'s extra files (those in
-- `opts.executable` executable). The tooling and its packed objects come from the
-- seed image (engine.seed), built once per content, not from the checkout. Removes what an earlier run left, and is
-- removed by the runner when the spec file passes (@tests/lib/swept).
export type Options = {
	noLessons: boolean?, -- no lessons in the copied skills (the spec seeds its own)
	copy: { string }?, -- paths of the checkout, relative to its top, copied into the seed with their modes and links
	executable: { string }?, -- seeded paths made executable before the seed commit
}

function trackerfix.new(name: string, seed: { [string]: string }?, opts: Options?): Fixture
	local root = fixture.physical(".")
	if not root then
		error("trackerfix.new: the current directory is not readable", 2)
	end
	local base = `{root}/.cache/{name}`
	local origin, main, other = `{base}/origin.git`, `{base}/main`, `{base}/other`
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
	swept.register(base)
	-- main first: the image's commit made the fixture's own (authored by `name`, holding the extra files) ...
	cloneAs(base, name, engine.seed(opts ~= nil and opts.noLessons == true), main, false)
	if opts and opts.copy then
		for _, rel in opts.copy do
			local parent = string.match(rel, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{main}/{parent}`)
			end
			local r = counted("cp", { "-R", `{engine.TOP}/{rel}`, `{main}/{rel}` })
			if not r.ok then
				error(`trackerfix.new: copying {rel} from the checkout failed: {r.stderr}`, 2)
			end
		end
	end
	local extra: { [string]: string } = seed or {}
	for path, text in extra do
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{main}/{parent}`)
		end
		fs.writeFile(`{main}/{path}`, text)
	end
	if opts and opts.executable then
		for _, rel in opts.executable do
			local r = counted("chmod", { "+x", `{main}/{rel}` })
			if not r.ok then
				error(`trackerfix.new: making {rel} executable failed: {r.stderr}`, 2)
			end
		end
	end
	-- a design-ready issue in the seed carries an approval, so ready's check can pass. The file is part of
	-- the seed commit, not an extra one ready makes.
	seal.stamp(main, name)
	fixture.git(main, { "add", "-A" })
	fixture.git(main, { "commit", "-q", "--amend", "--reset-author", "-m", "seed" })
	local seedSha = fixture.git(main, { "rev-parse", "HEAD" })
	-- ... then the origin made from it (no second copy of the objects is ever pushed), and main pointed at the origin
	cloneAs(base, name, main, origin, true)
	fixture.git(origin, { "remote", "remove", "origin" })
	fixture.git(main, { "remote", "set-url", "origin", origin })
	fixture.git(main, { "fetch", "-q", "origin" })
	tally.files(tally.count(base))
	-- `other`, the second terminal, is made when a helper is first asked to work in it: most specs never do
	-- and as the terminal the old setup made: at the seed, however far the origin has moved since, with only the seed's
	-- remote branch known
	fixture.defer(other, function()
		cloneAs(base, name, origin, other, false)
		fixture.git(other, { "reset", "-q", "--hard", seedSha })
		fixture.git(other, { "update-ref", "refs/remotes/origin/main", seedSha })
		for ref in
			string.gmatch(
				fixture.git(other, { "for-each-ref", "--format=%(refname)", "refs/remotes/origin" }),
				"[^\n]+"
			)
		do
			if ref ~= "refs/remotes/origin/main" and ref ~= "refs/remotes/origin/HEAD" then
				fixture.git(other, { "update-ref", "-d", ref })
			end
		end
		tally.files(tally.count(other))
	end)
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

-- The fresh named worktrees `names` of the fixture's main checkout, made as `./zn worktree <name>` makes a fresh one (a new branch
-- off origin/main with no upstream, under main's .worktree/), their paths in order. The first goes through tracker.sh;
-- the rest are its tree copied (copy-on-write where there is one) under their own git metadata, not checked out again
-- (c0178). Only names `./zn worktree` takes for a named worktree: lowercase, digits and -.
function trackerfix.worktrees(f: Fixture, names: { string }): { string }
	-- every name is judged before anything is made: its shape, a branch or an origin branch of that name, a folder of that
	-- name, and the list itself
	fixture.git(f.main, { "fetch", "-q", "--prune", "origin" }) -- as ./zn worktree does, so origin's branches are known
	local seen: { [string]: boolean } = {}
	for _, name in names do
		if not string.match(name, "^[a-z][a-z0-9%-]*$") or #name > 60 then
			error(`trackerfix.worktrees: {name} is not a named worktree (lowercase letters, digits and -)`, 2)
		elseif seen[name] then
			error(`trackerfix.worktrees: {name} is listed twice`, 2)
		end
		seen[name] = true
		for _, ref in { `refs/heads/{name}`, `refs/remotes/origin/{name}` } do
			if fixture.exec(f.main, "git", { "show-ref", "--verify", "--quiet", ref }).ok then
				error(
					`trackerfix.worktrees: {name} already exists as {ref}: only fresh named worktrees are made this way`,
					2
				)
			end
		end
		if fs.isDir(`{f.main}/.worktree/{name}`) then
			error(
				`trackerfix.worktrees: {name} already exists as {f.main}/.worktree/{name}: only fresh named worktrees are made this way`,
				2
			)
		end
	end
	local paths: { string } = {}
	for i, name in names do
		if i == 1 then
			table.insert(paths, trackerfix.trOk(f, f.main, { "worktree", name }))
			continue
		end
		local first = paths[1]
		local path = `{string.match(first, "^(.*)/[^/]+$")}/{name}`
		fixture.git(
			f.main,
			{ "worktree", "add", "-q", "--no-checkout", "--no-track", "-b", name, path, "origin/main" }
		)
		local args = { "-cR" }
		for _, entry in fs.readDir(first) do
			if entry ~= ".git" then
				table.insert(args, `{first}/{entry}`)
			end
		end
		table.insert(args, `{path}/`)
		local r = counted("cp", args)
		if not r.ok then
			args[1] = "-R"
			r = counted("cp", args)
		end
		if not r.ok then
			error(`trackerfix.worktrees: copying {first} into {path} failed: {r.stderr}`, 2)
		end
		fixture.git(path, { "reset", "-q" }) -- the index, from HEAD: the files are the ones HEAD holds
		table.insert(paths, path)
	end
	return paths
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
