--!strict
-- A tracker fixture for specs that drive `scripts/tracker.sh`: a bare origin with a seed commit, a main checkout
-- and a second terminal, all under a .cache folder. A thin layer over @tests/lib/fixture: every git and tracker.sh
-- command goes through fixture.git and fixture.exec (and so is checked), except `git init` and `git clone` to a
-- path this module names itself. Each caller passes a name that no other spec file uses (the c0049 rule); the
-- path is built by concatenation, so only that name counts.
--
-- c0178: `trackerfix.new` does not build its fixture. It clones this run's template (one per run, lessons choice and state of
-- the tooling; built once, packed, by `trackerfix.build`) with one whole-tree clone (@tests/lib/fxclone), rewrites the nine
-- files that name the template's path (`trackerfix.REWRITE`), checks them before any git runs in the fixture, and gives it its
-- own identity and seeded files with one amended seed commit, so a spec sees what a build gives it. A template lives in
-- <home>/.cache/fixture-templates; nothing hands it to a spec, and no spec may write into a template it did not build (a spec
-- that must damage one builds a private one through `trackerfix.TOOLING`).
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local fxclone = require("@tests/lib/fxclone")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")

local trackerfix = {}

export type Fixture = { base: string, origin: string, main: string, other: string }

-- The checkout whose tooling fixtures copy (and whose tooling state keys the templates). A spec that needs private templates
-- sets it to a copy made with engine.copy, and sets it back.
trackerfix.TOOLING = engine.TOP
-- The files of a template, and of every fixture cloned from it, that name the template's absolute path (c0178 E3). The build
-- refuses a template in which any other file names it; every clone checks these before any git runs in it.
trackerfix.REWRITE = {
	"main/.git/config",
	"main/.git/logs/HEAD",
	"main/.git/logs/refs/heads/main",
	"main/.git/logs/refs/remotes/origin/HEAD",
	"other/.git/config",
	"other/.git/logs/HEAD",
	"other/.git/logs/refs/heads/main",
	"other/.git/logs/refs/remotes/origin/HEAD",
	"origin.git/config",
}
-- Fault seams for c0178's spec: a relative path the clone's rewrite leaves out, and an errno the clone is told it failed with.
trackerfix.SKIP_REWRITE = nil :: string?
trackerfix.SIMULATE = nil :: string?
-- A fault seam: the path the clone's rewrite writes in place of the fixture's (so the remote check is seen to refuse).
trackerfix.REWRITE_TO = nil :: string?

local TEMPLATES = "fixture-templates"
local STAMP = ".fixture-stamp"

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

local function home(): string
	local root = fixture.physical(".")
	if not root then
		error("trackerfix: the current directory is not readable", 3)
	end
	return root
end

-- Builds `base` (which must not exist yet) as today's fixture: a seed commit (the tooling, with the skills' lessons unless
-- `noLessons`, empty tracker folders, and `seed`'s extra files), a bare origin made from it, and two clones of the origin.
-- With `pack`, the seed's objects are packed first, so every repository holds one pack.
local function buildAt(
	base: string,
	name: string,
	seed: { [string]: string }?,
	noLessons: boolean,
	pack: boolean
)
	local origin, main, other = `{base}/origin.git`, `{base}/main`, `{base}/other`
	local source = `{base}/seed`
	fs.writeDir(`{source}/tracker`)
	create(base, { "init", "-q", "-b", "main", source })
	identity(source, name)
	-- ./zn, scripts/ and z-nile/'s tooling, with no items, counter or map; empty folders under both project roots
	engine.copy(trackerfix.TOOLING, source)
	if noLessons then
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
	-- a design-ready issue in the seed carries an approval, so ready's check can pass. The file is part of
	-- the seed commit, not an extra one ready makes.
	seal.stamp(source, name)
	fixture.git(source, { "add", "-A" })
	fixture.git(source, { "commit", "-q", "-m", "seed" })
	if pack then
		fixture.git(source, { "repack", "-adq" })
		fixture.git(source, { "prune-packed" })
	end
	create(base, { "clone", "-q", "--bare", source, origin })
	create(base, { "clone", "-q", origin, main })
	create(base, { "clone", "-q", origin, other })
	identity(main, name)
	identity(other, name)
end

-- Today's builder, kept: builds `.cache/<name>` from scratch (removing what an earlier run left). The template build runs it,
-- and c0178's spec compares a cloned fixture with it.
function trackerfix.build(name: string, seed: { [string]: string }?, opts: { noLessons: boolean? }?): Fixture
	local base = `{home()}/.cache/{name}`
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
	buildAt(base, name, seed, (opts and opts.noLessons) == true, false)
	return { base = base, origin = `{base}/origin.git`, main = `{base}/main`, other = `{base}/other` }
end

-- This run: the basename of the runner's own temp folder (fresh per run, the same for every worker), or this process.
local runIdMemo: string? = nil
local pidMemo: string? = nil
local function pid(): string
	if not pidMemo then
		pidMemo = trim(process.exec("sh", { "-c", "echo $PPID" }).stdout)
	end
	return pidMemo :: string
end
local function runId(): string
	if not runIdMemo then
		local base = string.match(process.env.TMPDIR or "", "([^/]+)/*$") or ""
		runIdMemo = if string.match(base, "^pickman%-run%.%w+$") then base else `proc-{pid()}`
	end
	return runIdMemo :: string
end

-- The state of the tooling engine.copy copies from `root`: each entry's path, mode, size and mtime, hashed (nothing is read).
local KEY = [[
use strict; use File::Find; use Time::HiRes qw(lstat); use Digest::SHA qw(sha1_hex);
my $root = shift; chdir $root or die "trackerfix: cannot enter $root: $!\n";
my %skip = map { $_ => 1 } qw(. .. .tracker next compaction.txt tests .cache);
my @rows;
my $wanted = sub { my @s = lstat($_) or return; push @rows, join("\0", $_, $s[2], $s[7], $s[9]) };
for my $top ("zn", "scripts") { find({ wanted => $wanted, no_chdir => 1 }, $top) if -e $top || -l $top }
opendir(my $d, "z-nile") or die "trackerfix: no z-nile in $root\n";
for my $n (sort readdir $d) { next if $skip{$n}; find({ wanted => $wanted, no_chdir => 1 }, "z-nile/$n") }
print sha1_hex(join("\n", sort @rows)), "\n";
]]
local function toolingKey(root: string): string
	local r = process.exec("perl", { "-e", KEY, root })
	if not r.ok then
		error(`trackerfix: the tooling key of {root} could not be read: {r.stderr}`, 3)
	end
	return string.sub(trim(r.stdout), 1, 12)
end

-- The sweep: every entry of the templates folder's own grammar that belongs to another run (and every one being removed) is
-- renamed to a name of this process first (a lost rename is skipped: another worker has it), then removed. Only a real
-- folder is swept; nothing outside the grammar is touched. Prints the names it claimed, one a line.
local SWEEP = [[
use strict;
my ($dir, $run, $me) = @ARGV;
exit 0 unless -d $dir && !-l $dir;
opendir(my $d, $dir) or exit 0;
for my $n (readdir $d) {
  if ($n =~ /^((?:pickman-run\.\w+|proc-\d+))\.copied\.\d+$/) { unlink("$dir/$n") if $1 ne $run; next }
  next unless $n =~ /^((pickman-run\.\w+|proc-\d+)-(?:lessons|nolessons)-[0-9a-f]{12})(?:\.(build|gone)\.[\w-]+)?$/;
  my ($tpl, $r, $kind) = ($1, $2, $3 // "");
  next if $r eq $run && $kind ne "gone";
  my $to = "$tpl.gone.$me-" . int(rand(1e9));
  rename("$dir/$n", "$dir/$to") or next;
  print "$to\n";
}
]]
local function sweep(dir: string)
	local r = process.exec("perl", { "-e", SWEEP, dir, runId(), pid() })
	for name in string.gmatch(r.stdout, "[^\n]+") do
		pcall(fs.removeDir, `{dir}/{name}`)
	end
end

-- Replaces the path `from` with `to` in each of `files` (relative to `dir`) that holds it, through a sibling temp file and a
-- rename. One process.
local REPLACE = [[
use strict;
my ($dir, $from, $to, @files) = @ARGV;
for my $rel (@files) {
  my $f = "$dir/$rel";
  next unless -f $f && !-l $f;
  open(my $in, "<", $f) or die "cannot read $f: $!\n"; local $/; my $t = <$in>; close $in;
  next unless $t =~ s/\Q$from\E/$to/g;
  open(my $out, ">", "$f.c0178.$$") or die "cannot write $f: $!\n"; print $out $t; close $out or die "$f: $!\n";
  rename("$f.c0178.$$", $f) or die "cannot replace $f: $!\n";
}
]]
local function replace(dir: string, from: string, to: string, files: { string })
	local args = { "-e", REPLACE, dir, from, to }
	for _, rel in files do
		table.insert(args, rel)
	end
	local r = process.exec("perl", args)
	if not r.ok then
		error(`trackerfix: rewriting {dir}: {r.stderr}`, 3)
	end
end

-- every regular file under `dir` whose bytes hold `needle`, relative to `dir`, sorted
local function naming(dir: string, needle: string): { string }
	local r = process.exec("grep", { "-rlF", "--", needle, dir })
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, string.sub(line, #dir + 2))
	end
	table.sort(out)
	return out
end

local function sortedList(list: { string }): string
	local copy = table.clone(list)
	table.sort(copy)
	return table.concat(copy, ", ")
end

-- The first path under `template` that changed after it was built (its stamp is written last), or nil.
function trackerfix.changed(template: string): string?
	local stamp = `{template}/{STAMP}`
	if not fs.isFile(stamp) then
		return stamp .. " (missing)"
	end
	-- the change time only: every write and every mode change moves it (a modification time alone would miss a mode change);
	-- the stamp itself is left out, as its own change time can follow its modification time
	local r = process.exec("find", {
		template,
		"-mindepth",
		"1",
		"!",
		"-path",
		stamp,
		"-cnewer",
		stamp,
		"-print",
	})
	if not r.ok then
		return `{template} (find failed: {trim(r.stderr)})`
	end
	local first = string.match(r.stdout, "[^\n]+")
	return first
end

local resolved: { [string]: boolean } = {}
local swept = false
local built = 0

-- This process forgets the templates it resolved and that it swept, as a fresh worker would (a spec seam).
function trackerfix.forget()
	resolved = {}
	swept = false
end

-- How many templates this process built (a spec seam).
function trackerfix.builds(): number
	return built
end

-- Builds the template `final` in a build folder beside it and publishes it by one rename.
local function buildTemplate(final: string, noLessons: boolean)
	local build = `{final}.build.{pid()}-{math.random(1, 1e9)}`
	fs.writeDir(build)
	local ok, err = pcall(function()
		buildAt(build, "fixture-template", nil, noLessons, true)
		fs.removeDir(`{build}/seed`)
		-- pushes into the bare origin land as one pack (c0179's receive-side cut); the checkouts' configuration is untouched
		fixture.git(`{build}/origin.git`, { "config", "receive.unpackLimit", "1" })
		-- the build's files name the build folder: point them at the template's own path, then check that exactly the list does
		replace(build, build, final, trackerfix.REWRITE)
		local still = naming(build, build)
		if #still > 0 then
			error(
				`trackerfix: template {final} still names its build folder in {table.concat(still, ", ")}`,
				0
			)
		end
		local named = table.concat(naming(build, final), ", ")
		if named ~= sortedList(trackerfix.REWRITE) then
			error(
				`trackerfix: template {final} names its path in {named}: the rewrite list is {sortedList(
					trackerfix.REWRITE
				)}`,
				0
			)
		end
		fs.writeFile(`{build}/{STAMP}`, "") -- last: anything newer than it was written after the template was built
	end)
	if not ok then
		pcall(fs.removeDir, build)
		error(err, 0)
	end
	built += 1
	if not pcall(fs.move, build, final, false) then
		pcall(fs.removeDir, build) -- another worker published it first
		if not fs.isDir(final) then
			error(`trackerfix: template {final} could not be published`, 0)
		end
	end
end

-- This run's template for the lessons choice and the current state of `trackerfix.TOOLING`, built if needed.
function trackerfix.template(noLessons: boolean): string
	local dir = `{home()}/.cache/{TEMPLATES}`
	if process.exec("test", { "-L", dir }).ok then
		error(`trackerfix: {dir} is a link: refusing to use it`, 2)
	end
	local tooling = fixture.physical(trackerfix.TOOLING)
	if not tooling then
		error(`trackerfix: the tooling {trackerfix.TOOLING} is not readable`, 2)
	end
	local final = `{dir}/{runId()}-{if noLessons then "nolessons" else "lessons"}-{toolingKey(tooling)}`
	if resolved[final] then
		return final
	end
	fs.writeDir(dir)
	if not swept then
		swept = true
		sweep(dir)
	end
	if not fs.isDir(final) then
		buildTemplate(final, noLessons)
	end
	resolved[final] = true
	return final
end

-- A name a fixture may not take: the templates' own folder, or a path with an empty, `.` or `..` segment.
local function badName(name: string): boolean
	if name == "" then
		return true
	end
	local first = true
	for segment in string.gmatch(name .. "/", "([^/]*)/") do
		if segment == "" or segment == "." or segment == ".." then
			return true
		end
		if first and string.lower(segment) == TEMPLATES then
			return true
		end
		first = false
	end
	return false
end

local function originUrl(config: string): string?
	local section = string.match(config, '%[remote "origin"%]([^%[]*)')
	return if section then string.match(section, "\n%s*url%s*=%s*([^\n]+)") else nil
end

-- Builds `.cache/<name>`: a fixture with a seed commit (the tooling, with the skills' lessons unless `opts.noLessons`, empty
-- tracker folders, and `seed`'s extra files), a bare origin made from it, and two clones of the origin. Removes what an
-- earlier run left. Cloned from this run's template (c0178).
function trackerfix.new(name: string, seed: { [string]: string }?, opts: { noLessons: boolean? }?): Fixture
	if badName(name) then
		error(`trackerfix.new: {name} is a reserved or malformed fixture name`, 2)
	end
	local root = home()
	local base = `{root}/.cache/{name}`
	local origin, main, other = `{base}/origin.git`, `{base}/main`, `{base}/other`
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	local tpl = trackerfix.template((opts and opts.noLessons) == true)
	local parent = string.match(base, "^(.*)/[^/]+$") :: string
	fs.writeDir(parent)
	local how, reason = fxclone.tree(tpl, base, { simulate = trackerfix.SIMULATE })
	if how == "copy" and reason and process.os == "macos" then
		-- one line at the end of the run says so (z-nile/tests/run.luau): a silent copy would hide a lost saving
		local marker = `{root}/.cache/{TEMPLATES}/{runId()}.copied.{pid()}`
		local old = if fs.isFile(marker) then fs.readFile(marker) else ""
		fs.writeFile(marker, `{old}{reason}\t{base}\n`)
	end
	local changed = trackerfix.changed(tpl)
	if changed then
		pcall(fs.removeDir, base)
		error(
			`trackerfix: template changed: {changed} (something wrote into {tpl} after it was built); every later fixture of this run from it refuses`,
			2
		)
	end
	fs.removeFile(`{base}/{STAMP}`)
	local files: { string } = {}
	for _, rel in trackerfix.REWRITE do
		if rel ~= trackerfix.SKIP_REWRITE then
			table.insert(files, rel)
		end
	end
	replace(base, tpl, trackerfix.REWRITE_TO or base, files)
	-- before any git runs in the fixture: no file names the template, and both checkouts' origin is the fixture's own
	for _, rel in trackerfix.REWRITE do
		local path = `{base}/{rel}`
		if fs.isFile(path) and string.find(fs.readFile(path), tpl, 1, true) then
			pcall(fs.removeDir, base)
			error(`trackerfix: {rel} of {base} still names {tpl}`, 2)
		end
	end
	for _, dir in { main, other } do
		local url = originUrl(fs.readFile(`{dir}/.git/config`))
		if url ~= origin then
			pcall(fs.removeDir, base)
			error(
				`trackerfix: the remote origin of {dir} is {url or "missing"}, not {origin} (template {tpl})`,
				2
			)
		end
	end
	-- a clone's files have new inodes and ctimes: refresh the index once, so add and reset see no change
	fixture.exec(main, "git", { "update-index", "-q", "--refresh" })
	fixture.exec(other, "git", { "update-index", "-q", "--refresh" })
	identity(main, name)
	identity(other, name)
	local extra: { [string]: string } = seed or {}
	for path, text in extra do
		local p = string.match(path, "^(.*)/[^/]+$")
		if p then
			fs.writeDir(`{main}/{p}`)
		end
		fs.writeFile(`{main}/{path}`, text)
	end
	-- a design-ready issue in the seed carries an approval, so ready's check can pass (part of the seed commit)
	seal.stamp(main, name)
	fixture.git(main, { "add", "-A" })
	fixture.git(main, { "commit", "-q", "--amend", "--reset-author", "-m", "seed" })
	fixture.git(main, { "push", "-q", "-f", "origin", "HEAD:main" })
	fixture.git(other, { "fetch", "-q", "origin" })
	fixture.git(other, { "reset", "-q", "--hard", "origin/main" })
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
