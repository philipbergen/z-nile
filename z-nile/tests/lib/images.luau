--!strict
-- Fixture images (c0178): a folder built once from the tooling, named by a digest of the content it is built from, and
-- copied into every fixture that needs it, so a fixture no longer lays out the tooling, hashes its objects and
-- clones them again. Images live in one folder, images.dir(), under the home's .cache.
local DateTime = require("@lune/datetime")
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local pruning = require("@tests/lib/pruning")
local tally = require("@tests/lib/tally")
local task = require("@lune/task")

-- process.exec, counted (tally.started) beside the call.
local function counted(
	cmd: string,
	args: { string }?,
	options: any?
): { ok: boolean, code: number, stdout: string, stderr: string }
	tally.started(1)
	return process.exec(cmd, args, options)
end

local images = {}

export type Spec = {
	name: string, -- the image's kind, lowercase letters, digits and "-": "tooling", "seed", "seed-nolessons"
	root: string, -- the checkout the inputs are read from
	inputs: { string }, -- root-relative files and folders the image is made from
	skip: { string }, -- root-relative paths inside the inputs that are left out of the key
	code: { string }, -- absolute paths of the harness files that build it: their bytes are part of the key
	salt: string?, -- something else the image depends on (the commit an image of a repository is of), part of the key
	build: (dest: string) -> (), -- fills the empty folder `dest` with the whole image
}
-- Seams for the specs, and the defaults for everyone else (seconds): a build lock older than `stale` no longer holds
-- anyone off, and a caller waits `wait` for another's build before it builds for itself. Nothing here removes an
-- image: that is pruning.run, once per run, before any spec starts.
export type Options = {
	dir: string?,
	stale: number?,
	wait: number?,
	beforeLock: ((final: string) -> ())?, -- called between looking for the image and taking the lock
}

-- Three folders above this file: the checkout that holds the harness (as engine.TOP)
local TOP = string.match(debug.info(1, "s"), "^(.*)/[^/]+/[^/]+/[^/]+/[^/]+$") or "."
local KEY_LENGTH = 24
local built = 0
local memo: { [string]: string } = {}

-- The folder the images live in, <home>/.cache/images, for the run's current folder (a project's home). The one place
-- that decides where images are; nothing else builds an image path.
function images.dir(): string
	return pruning.dir()
end

-- How many images this process has built (a seam for the specs: a second call for the same content builds nothing).
function images.builds(): number
	return built
end

local function keyOf(spec: Spec): string
	if not string.match(spec.name, "^[a-z][a-z0-9%-]*$") then
		error(`images: {spec.name} is not an image name (lowercase letters, digits and -)`, 3)
	end
	local args = { `{TOP}/z-nile/lib/image-key.pl`, spec.root }
	for _, p in spec.inputs do
		table.insert(args, p)
	end
	for _, p in spec.skip do
		table.insert(args, "--skip")
		table.insert(args, p)
	end
	for _, p in spec.code do
		table.insert(args, "--also")
		table.insert(args, p)
	end
	if spec.salt ~= nil then
		table.insert(args, "--salt")
		table.insert(args, spec.salt)
	end
	local r = counted("perl", args)
	local digest = string.match(r.stdout, "^(%x+)%s*$")
	if not r.ok or not digest then
		error(`images: the key of {spec.name} could not be read: {r.stderr}`, 3)
	end
	return string.sub(digest, 1, KEY_LENGTH)
end

-- Seconds since `path` last changed, by the wall clock of both (the file's mtime and now); nil when it is gone.
local function age(path: string): number?
	local ok, meta = pcall(fs.metadata, path)
	if not ok or meta.modifiedAt == nil then
		return nil
	end
	return os.time() - (meta.modifiedAt :: any).unixTimestamp
end

-- The text a builder writes into its lock: its pid and the start id of that process (fence.startOf), so a waiter can
-- tell a live builder from a dead one and from a reused pid.
local function ownerRecord(): string
	local r = counted("sh", { "-c", "echo $PPID" })
	local pid = string.match(r.stdout, "^(%d+)")
	if not r.ok or pid == nil then
		return ""
	end
	return `{pid} {fence.startOf(pid) or ""}`
end

-- Whether the lock's recorded owner is gone. A lock with no record yet, or one that cannot be read, is not dead.
local function ownerDead(lock: string): boolean
	local ok, text = pcall(fs.readFile, `{lock}/owner`)
	if not ok then
		return false
	end
	local pid, start = string.match(text :: string, "^(%d+) ?(%S*)")
	if pid == nil then
		return false
	end
	return not fence.holds(fence.alive(pid), if start ~= "" then start else nil, fence.startOf(pid))
end

-- The folder of the image `spec` describes, built on first use. Safe to call from any number of processes at once: a
-- build is published by one rename, so nobody sees half an image, and the lock only keeps the others from repeating
-- the work (it is advisory: a lock older than `stale`, or a wait longer than `wait`, is not obeyed, and the rename
-- still lets only one build win).
function images.ensure(spec: Spec, options: Options?): string
	local opts: Options = options or {}
	local home = opts.dir or images.dir()
	local memoKey = table.concat({
		spec.name,
		spec.root,
		table.concat(spec.inputs, "\0"),
		table.concat(spec.skip, "\0"),
		table.concat(spec.code, "\0"),
		spec.salt or "",
	}, "\n")
	local key = memo[memoKey]
	if not key then
		key = keyOf(spec)
		memo[memoKey] = key
	end
	local id = `{spec.name}-{key}`
	local final = `{home}/{id}`
	if fs.isDir(final) then
		return final
	end
	fs.writeDir(home)
	local lock = `{home}/{id}.lock`
	local stale, wait = opts.stale or 60, opts.wait or 180
	local began = DateTime.now().unixTimestampMillis
	local mine = false
	while true do
		if fs.isDir(final) then
			return final
		end
		if opts.beforeLock then
			opts.beforeLock(final)
		end
		if not fs.isDir(lock) then
			if counted("mkdir", { lock }).ok then
				if fs.isDir(final) then -- published between our look and our lock: nothing left to build
					pcall(fs.removeDir, lock)
					return final
				end
				pcall(fs.writeFile, `{lock}/owner`, ownerRecord())
				mine = true
				break
			end
		else
			local held = age(lock)
			if
				(held ~= nil and held >= stale)
				or DateTime.now().unixTimestampMillis - began >= wait * 1000
			then
				break -- not obeyed any more: build, and let the rename decide
			elseif ownerDead(lock) then
				break -- its builder is gone: build, and let the rename decide (a few duplicate builds at worst)
			end
		end
		task.wait(0.2)
	end
	local made = counted("mktemp", { "-d", `{home}/.build.XXXXXX` })
	if not made.ok then
		if mine then
			pcall(fs.removeDir, lock)
		end
		error(`images: cannot make a build folder in {home}: {made.stderr}`, 2)
	end
	local build = (string.gsub(made.stdout, "%s+$", ""))
	local ok, err = pcall(function(): any
		spec.build(build)
		return nil
	end)
	if ok then
		built += 1
	end
	if not ok then
		pcall(fs.removeDir, build)
		if mine then
			pcall(fs.removeDir, lock)
		end
		error(`images: building {id} failed: {err}`, 2)
	end
	local moved = pcall(fs.move, build, final, false)
	if mine then
		pcall(fs.removeDir, lock)
	end
	if not moved then
		pcall(fs.removeDir, build) -- another caller published first: theirs is the image
		if not fs.isDir(final) then
			error(`images: {id} could not be published to {final}`, 2)
		end
	end
	return final
end

return images
