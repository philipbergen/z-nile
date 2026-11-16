--!strict
-- c0195's harness, shared by its specs (required as ./harness; it moves with them). c0195: where the fence sets the ref guard's hooks (no jail: check.sh flows, Linux spec runs), its own git
-- (z-nile/lib/git-hooks/git, first on the PATH) refuses, in a repository the fence protects, the ref writes git
-- makes outside a ref transaction: a branch copy (`branch -c`/`-C`/`--copy`, which runs no reference-transaction
-- hook at all) and a branch rename (`-m`/`-M`/`--move`, whose refusal by the hook still moves the branch's reflog
-- aside), in every spelling git accepts, and every command that is not one of git's own (an alias or an external
-- command, whose expansion it can't see). In a fixture the fence does not protect, all of them run.
--
-- Every case runs for real, on every git this machine has (the PATH's and the Command Line Tools' on macOS: 2.54 and
-- 2.50 when this was written). A "real" repository is a fixture under .cache that `pickman_fence` protects, exactly as
-- ac.sh protects the checkout; nothing outside .cache is involved.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local home = (string.gsub(process.cwd, "/+$", "")) -- z-nile/, its home
local FENCE = `{root}/z-nile/lib/fence.sh`
local HOOKS = `{root}/z-nile/lib/git-hooks`
local CLT = "/Library/Developer/CommandLineTools/usr/bin/git"
local ID = { "-c", "user.name=c0195", "-c", "user.email=c0195@example.invalid" }

local REFUSED_COPY = "copy or rename a branch"
local REFUSED_OTHER = "not one of git's own commands"

-- Every distinct git on this machine: each `git` on the PATH (not the fence's own) and the Command Line Tools', by
-- version. Each is run as `<its exec path>/git`, the binary itself, so no wrapper (z-nile/bin/git) stands in for it.
export type Git = { dir: string, version: string }
local function gits(): { Git }
	local out: { Git } = {}
	local seen: { [string]: boolean } = {}
	local candidates: { string } = {}
	for dir in string.gmatch(process.env.PATH or "", "[^:]+") do
		if not string.match(dir, "/git%-hooks/?$") then
			table.insert(candidates, `{dir}/git`)
		end
	end
	table.insert(candidates, CLT)
	for _, c in candidates do
		if fs.isFile(c) then
			local ok, v = pcall(process.exec, c, { "--version" })
			local ok2, x = pcall(process.exec, c, { "--exec-path" })
			if ok and ok2 and v.ok and x.ok then
				local version = trim(v.stdout)
				local exec = trim(x.stdout)
				if not seen[version] and fs.isFile(`{exec}/git`) then
					seen[version] = true
					table.insert(out, { dir = exec, version = version })
				end
			end
		end
	end
	return out
end
local GITS = gits()

-- A repository with main (two commits), side and a tag, every branch with a reflog, made by the given git.
local function makeRepo(dir: string, g: Git)
	local git = `{g.dir}/git`
	local init = process.exec(git, { "init", "-q", "-b", "main", dir })
	assert(init.ok, init.stderr)
	local function run(args: { string })
		local all = table.clone(ID)
		table.move(args, 1, #args, #all + 1, all)
		local r = process.exec(git, all, { cwd = dir })
		assert(r.ok, r.stderr)
	end
	fs.writeFile(`{dir}/f`, "a\n")
	run({ "add", "f" })
	run({ "commit", "-qm", "base" })
	fs.writeFile(`{dir}/f`, "b\n")
	run({ "commit", "-qam", "second" })
	run({ "branch", "side", "HEAD~1" })
	run({ "tag", "v1", "HEAD~1" })
	fs.writeFile(`{dir}/.git/info/exclude`, ".cache/\n")
end

-- What a ref write changes: every ref and its value, HEAD, and the files under refs/ and logs/ (the loose refs and
-- the reflogs). One shell command, so the guarded shell below prints it the same way.
local STATE = "git for-each-ref --format='%(refname) %(objectname)'; cat .git/HEAD; "
	.. "(cd .git && find refs logs -type f | LC_ALL=C sort)"
local function state(dir: string): string
	local r = process.exec("sh", { "-c", STATE }, { cwd = dir })
	assert(r.ok, r.stderr)
	return r.stdout
end

-- Runs each form (a git command line, `@REAL@` standing for the protected repository's path) in one shell that
-- the fence guards, protecting `real`: each "real" form in `real`, each "free" or "away" form in a fresh copy of
-- `free` (a fixture the fence does not protect). Returns, per form, its exit, stderr and (for free and away forms)
-- the copy's state after it, with the protected repository's state before and after them all and the copy's
-- state before.
export type Form = { where: string, args: { string } }
type Ran = { code: number, stderr: string, after: string }
type Batch = { ran: { Ran }, before: string, after: string, freeBefore: string }
local DRIVER = table.concat({
	"set -u",
	"fence=$1 gdir=$2 real=$3 free=$4 forms=$5 out=$6 state=$7",
	'. "$fence" || exit 90',
	'PATH="$gdir:$PATH"',
	'pickman_fence "$real" >"$out/fence.err" 2>&1 || exit 91',
	"i=0",
	"while IFS= read -r line; do",
	"  i=$((i + 1))",
	-- split on tabs by the shell itself (no process substitution, which can outlive the shell)
	"  set -f; old=$IFS; IFS=$'\\t'; w=($line); IFS=$old; set +f",
	"  where=${w[0]}",
	'  w=("${w[@]:1}")',
	"  dir=$real",
	'  if [ "$where" != real ]; then rm -rf "$free-run"; cp -R "$free" "$free-run"; dir=$free-run; fi',
	'  (cd "$dir" && git "${w[@]}") >"$out/$i.out" 2>"$out/$i.err"',
	'  echo $? >"$out/$i.rc"',
	'  if [ "$where" != real ]; then (cd "$dir" && sh -c "$state") >"$out/$i.after"; fi',
	'done <"$forms"',
}, "\n")

local function runForms(base: string, g: Git, name: string, forms: { Form }): Batch
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	local real, free, out = `{dir}/real`, `{dir}/free`, `{dir}/out`
	makeRepo(real, g)
	makeRepo(free, g)
	fs.writeDir(out)
	local lines: { string } = {}
	for _, f in forms do
		local words = { f.where }
		for _, a in f.args do
			local w = string.gsub(a, "@REAL@", real)
			table.insert(words, w)
		end
		table.insert(lines, table.concat(words, "\t"))
	end
	fs.writeFile(`{dir}/forms`, table.concat(lines, "\n") .. "\n")
	local before, freeBefore = state(real), state(free)
	local r =
		fixture.exec(real, "bash", { "-c", DRIVER, "_", FENCE, g.dir, real, free, `{dir}/forms`, out, STATE })
	if not r.ok then
		local why = if fs.isFile(`{out}/fence.err`) then fs.readFile(`{out}/fence.err`) else ""
		error(`{g.version}: the guarded shell failed ({r.code}): {r.stderr}{why}`)
	end
	local ran: { Ran } = {}
	for i = 1, #forms do
		table.insert(ran, {
			code = tonumber(trim(fs.readFile(`{out}/{i}.rc`))) or -1,
			stderr = fs.readFile(`{out}/{i}.err`),
			after = if fs.isFile(`{out}/{i}.after`) then fs.readFile(`{out}/{i}.after`) else "",
		})
	end
	return { ran = ran, before = before, after = state(real), freeBefore = freeBefore }
end

local function show(f: Form): string
	return `{f.where}: git {table.concat(f.args, " ")}`
end

-- Each form is refused in the protected repository with `said`, which stays as it was; the same form run in a
-- fixture the fence does not protect succeeds and changes its refs or reflogs (so it is a form git really runs).
local function refusedHereRunsThere(base: string, g: Git, name: string, forms: { { string } }, said: string)
	local all: { Form } = {}
	for _, args in forms do
		table.insert(all, { where = "real", args = args })
		table.insert(all, { where = "free", args = args })
	end
	local b = runForms(base, g, name, all)
	local bad: { string } = {}
	for i, f in all do
		local r = b.ran[i]
		if f.where == "real" then
			if r.code == 0 or not has(r.stderr, said) or not has(r.stderr, "refused") then
				table.insert(bad, `{show(f)} was not refused with "{said}" (exit {r.code}): {r.stderr}`)
			end
		elseif r.code ~= 0 then
			table.insert(
				bad,
				`{show(f)} failed in a fixture the fence does not protect (exit {r.code}): {r.stderr}`
			)
		elseif r.after == b.freeBefore then
			table.insert(bad, `{show(f)} changed nothing in the fixture, so it proves nothing`)
		end
	end
	if b.after ~= b.before then
		table.insert(bad, `the protected repository changed:\nbefore:\n{b.before}\nafter:\n{b.after}`)
	end
	if #bad > 0 then
		error(`{g.version}:\n  {table.concat(bad, "\n  ")}`)
	end
end

-- A fresh folder for one spec's fixtures under the home's .cache, and its removal.
local function fresh(name: string): string
	local dir = `{home}/.cache/c0195-{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	return dir
end
local function remove(dir: string)
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
end

return {
	GITS = GITS,
	CLT = CLT,
	FENCE = FENCE,
	HOOKS = HOOKS,
	REFUSED_COPY = REFUSED_COPY,
	REFUSED_OTHER = REFUSED_OTHER,
	trim = trim,
	has = has,
	makeRepo = makeRepo,
	runForms = runForms,
	refusedHereRunsThere = refusedHereRunsThere,
	show = show,
	fresh = fresh,
	remove = remove,
}
