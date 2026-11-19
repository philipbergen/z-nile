--!strict
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local images = require("@tests/lib/images")
local process = require("@lune/process")
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

local clone = {}

-- The packed bare image of the repository at `root` at its HEAD (c0178): one `--no-hardlinks` clone per run and HEAD,
-- built by the first spec that clones it, and cloned by the rest. `repo.git` inside it.
function clone.imageOf(root: string, options: { dir: string? }?): string
	local head = counted("git", { "rev-parse", "HEAD" }, { cwd = root })
	if not head.ok or not string.match(head.stdout, "^%x+%s*$") then
		error(`clone.imageOf: no HEAD in {root}: {head.stderr}`, 2)
	end
	local dir = images.ensure({
		name = "repo",
		root = root,
		inputs = {},
		skip = {},
		code = { `{engine.TOP}/z-nile/tests/lib/images.luau`, `{engine.TOP}/z-nile/tests/lib/clone.luau` },
		salt = `{root}\n{string.gsub(head.stdout, "%s+$", "")}`,
		build = function(dest: string)
			local r = counted("git", { "clone", "-q", "--bare", "--no-hardlinks", root, `{dest}/repo.git` })
			if not r.ok then
				error(`git clone --bare {root} failed: {r.stderr}`, 2)
			end
			fixture.git(`{dest}/repo.git`, { "remote", "remove", "origin" })
			fixture.git(`{dest}/repo.git`, { "repack", "-a", "-d", "-q" })
			fixture.git(`{dest}/repo.git`, { "prune", "--expire=now" }) -- unreachable loose objects the source had
			tally.files(tally.count(`{dest}/repo.git`))
		end,
	}, { dir = options and options.dir })
	return `{dir}/repo.git`
end

-- The image of this checkout's own repository.
function clone.image(): string
	return clone.imageOf(engine.TOP)
end

-- `git clone --no-hardlinks`: a plain local clone hardlinks the object files of `source`, so the
-- throwaway copy would share inodes with the real object store. Raises if the clone fails; returns
-- `dest` (so `pcall(clone.isolated, …)` has a typed second result in strict mode). The repository this harness is
-- in is cloned from its image, not again from itself. `dest` is swept when its spec file passes.
-- `paths`: when given, only these paths of the repository (repository-relative; a trailing "/" is a folder) are in the
-- clone's working tree: the rest is in its index and not on disk (a sparse checkout), so a spec that reads a few folders
-- does not write 2,500 files. The clone is made with --no-checkout and then checked out through them.
export type Options = {
	paths: { string }?, -- repository-relative paths written to the working tree (nil: all of it)
	tooling: boolean?, -- with `paths`: also the tooling a spec overlays (./zn, scripts/, z-nile/ but its tracker state, .gitignore)
}

-- The tooling the specs that clone the repository overlay with the working tree's (engine.PATHSPECS), as clone paths: `zn`,
-- `scripts/`, `.gitignore` and every entry of z-nile/ but its tracker state, read from the checkout, so a new entry joins
-- without an edit here.
local function toolingPaths(): { string }
	local list = { "zn", "scripts/", ".gitignore" }
	for _, name in fs.readDir(`{engine.TOP}/z-nile`) do
		if name ~= ".tracker" and name ~= "next" and name ~= "compaction.txt" and name ~= ".cache" then
			table.insert(list, `z-nile/{name}{if fs.isDir(`{engine.TOP}/z-nile/{name}`) then "/" else ""}`)
		end
	end
	return list
end

function clone.isolated(source: string, dest: string, opts: Options?): string
	local from = if source == engine.TOP then clone.image() else source
	local args = { "clone", "-q", "--no-hardlinks" }
	local paths = opts and opts.paths
	if paths then
		table.insert(args, "--no-checkout")
	end
	table.insert(args, from)
	table.insert(args, dest)
	local r = counted("git", args)
	if not r.ok then
		error(`git clone of {source} into {dest} failed ({r.code}): {r.stderr}`, 2)
	end
	if paths then
		local set = { "sparse-checkout", "set", "--no-cone" }
		local all = table.clone(paths)
		if opts and opts.tooling then
			for _, p in toolingPaths() do
				table.insert(all, p)
			end
		end
		for _, p in all do
			table.insert(set, "/" .. string.gsub(p, "^/", ""))
		end
		fixture.git(dest, set)
		fixture.git(dest, { "checkout", "-q" })
	end
	-- the clone's origin is the source it was asked for, not the image it was made from (a push from a fixture must never reach
	-- an image); for the repository itself that is the real repository, which the pre-push guard refuses
	if source == engine.TOP then
		fixture.git(dest, { "remote", "set-url", "origin", engine.TOP })
	end
	tally.files(tally.count(dest))
	if fs.isDir(dest) then
		swept.register(dest)
	end
	return dest
end

return clone
